-- WorldDetail: the client-side detail layer of the gym and the city (GymDetail, CityDetail on DetailKit's
-- Streamer). Everything lives under workspace.WorldDetail (Gym, City), is built on this client only (nothing
-- replicates, other players never pay for it) and follows the Graphics level (Perf) and the camera:
--   High    tiers 1-3: fine detail within ~170 studs, the main dressing within ~320, surfaces / print within ~600
--   Medium  tiers 1-2: the fine detail is left out, the main dressing within ~200
--   Low     tier 1 only (floor textures, banners and posters, curbs, signals) within ~260
-- A tier is built the first time the camera comes near it (a piece at a time on FrameBudget, its ~4 ms a frame shared
-- with the client's other time-sliced builds) and kept while hidden; the city's streaming pauses while the character creator is open (LocalPlayer CreatorOpen). WorldLOD
-- watches the folder too (sign resolution, shadow casters on Low). A Graphics level change re-applies at once;
-- dropping below a tier frees what that tier built.
--   WorldDetail.Start()            once (ClientMain); waits for the server gym / city to replicate
--   WorldDetail.Stats()            { gym = {...}, city = {...} } parts / instances shown (profiler, tests)
--   WorldDetail.BuildAll(opts)     the simulator: every cell at opts.level at once, no camera
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local function optional(name)
	local m = script.Parent:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and type(mod) == "table" and mod or nil
end
local Perf = optional("Perf")
-- the client's time slicer: a tier is built a piece at a time behind the frames (one tier was up to ~40 ms in a pass)
local FrameBudget = optional("FrameBudget")
local GymDetail = optional("GymDetail")
local CityDetail = optional("CityDetail")

local WorldDetail = {}

local STEP = 0.35 -- seconds between streamer passes
local FAR = 1500 -- beyond this from the town's centre (fight venues, the menu set, homes): nothing streams

local folder, gymS, cityS
local level = 3

local function lv()
	local ok, l = pcall(function()
		return Perf and Perf.Level() or nil
	end)
	if ok and type(l) == "number" then
		return math.clamp(math.floor(l), 1, 3)
	end
	local p = Players.LocalPlayer
	local a = p and p:GetAttribute("GfxLevel")
	return type(a) == "number" and math.clamp(math.floor(a), 1, 3) or 3
end

local function ensureFolder()
	if folder and folder.Parent then
		return folder
	end
	folder = workspace:FindFirstChild("WorldDetail") or Instance.new("Folder")
	folder.Name = "WorldDetail"
	folder.Parent = workspace
	return folder
end

local function sub(name)
	local f = ensureFolder()
	local s = f:FindFirstChild(name)
	if not s then
		s = Instance.new("Folder")
		s.Name = name
		s.Parent = f
	end
	return s
end

local function gymReady()
	local g = workspace:FindFirstChild("Gym")
	return g ~= nil and g:FindFirstChild("GymRing") ~= nil
end

local function makeGym()
	if gymS or not GymDetail or not gymReady() then
		return
	end
	gymS = DetailKit.Streamer.new(sub("Gym"))
	GymDetail.Register(gymS)
end

local function makeCity()
	if cityS or not CityDetail or not CityDetail.Ready() then
		return
	end
	cityS = DetailKit.Streamer.new(sub("City"))
	CityDetail.Register(cityS)
end

-- a level drop frees the tiers the new level no longer shows
local function applyLevel(l)
	if l == level then
		return
	end
	local old = level
	level = l
	if l < old then
		for _, s in ipairs({ gymS, cityS }) do
			if s then
				for _, cell in ipairs(s.cells) do
					for t = l + 1, 3 do
						local m = cell.models[t]
						if m then
							m:Destroy()
							cell.models[t] = nil
							cell.shown[t] = false
						end
					end
				end
			end
		end
	end
end

local started = false
function WorldDetail.Start()
	if started then
		return
	end
	started = true
	level = lv()
	if Perf and Perf.Changed then
		Perf.Changed:Connect(function(l)
			applyLevel(math.clamp(math.floor(tonumber(l) or 3), 1, 3))
		end)
	end
	local acc = STEP
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < STEP then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			-- (one streamer registered per pass: each reads the server's world)
			if gymS or not (GymDetail and gymReady()) then
				makeCity()
			else
				makeGym()
			end
			applyLevel(lv())
			local cam = workspace.CurrentCamera
			local pos = cam and cam.CFrame.Position or Vector3.zero
			-- far away (a fight venue, a home interior) or behind the main menu (its set floats right above the town's
			-- centre, so the distance alone keeps the whole gym and Main Street streaming): hide it all (built tiers are
			-- kept, so the world is back at once when the menu closes)
			local menu = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("MenuStage") == true
			if menu or Vector3.new(pos.X, 0, pos.Z).Magnitude > FAR then
				pos = Vector3.new(1e6, 0, 1e6)
			end
			if gymS then
				gymS:Step(pos, level, FrameBudget)
			end
			-- behind the character creator (its camera stays on the boxer in the gym): the town's streaming waits (nothing
			-- new is built out there, what is shown stays) until it closes
			local creating = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("CreatorOpen") == true
			if cityS and not creating then
				cityS:Step(pos, level, FrameBudget)
			end
		end)
		if not ok and not WorldDetail.warned then
			WorldDetail.warned = true
			warn("[WorldDetail]", err)
		end
	end)
end

function WorldDetail.Stats()
	return { level = level, gym = gymS and gymS:Stats() or nil, city = cityS and cityS:Stats() or nil }
end

-- the simulator / previews: everything opts.level allows, built now (opts.level 1..3)
function WorldDetail.BuildAll(opts)
	opts = opts or {}
	level = math.clamp(math.floor(tonumber(opts.level) or 3), 1, 3)
	makeGym()
	makeCity()
	if gymS then
		gymS:BuildAll(level)
	end
	if cityS then
		cityS:BuildAll(level)
	end
	return folder
end

return WorldDetail
