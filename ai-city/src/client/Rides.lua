-- Rides (ModuleScript) — StarterPlayerScripts.CityClient.Rides
-- Makes Funland go round on your screen: the Ferris wheel turns (its gondolas
-- hang straight down), the carousel spins while the horses bob up and down,
-- and the drop tower climbs... and falls. Everyone's screen uses the server's
-- clock, so all players see the rides in the same place, and whoever sits in a
-- ride seat goes round with it (citizens riding are moved along too).
--
-- It also runs the Sky Obby's moving platforms and spinning bars, and sends
-- you back to your last checkpoint if you touch lava or a bar, or fall off.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Rides = {}
local player = Players.LocalPlayer
local RANGE = 520

local rides = {} -- [model] = { Parts = { { Part, Orig, Pivot, Bob, Phase } } }
local movers = {} -- [part] = original CFrame
local seats -- [name] = seat

local function capture(model)
	local info = { Parts = {} }
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(info.Parts, {
				Part = p, Orig = p.CFrame, Pivot = p:GetAttribute("Pivot"), Spin = p:GetAttribute("Spin"),
				Bob = p:GetAttribute("Bob"), Phase = p:GetAttribute("BobPhase") or 0, Lift = p:GetAttribute("Lift"),
			})
		end
	end
	rides[model] = info
	return info
end

local function rotation(axis, angle)
	if math.abs(axis.X) > 0.5 then
		return CFrame.Angles(angle, 0, 0)
	elseif math.abs(axis.Z) > 0.5 then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(0, angle, 0)
end

-- the drop tower's height over its 24-second cycle
function Rides.DropHeight(t, top)
	local c = t % 24
	if c < 4 then
		return 0 -- boarding
	elseif c < 14 then
		local u = (c - 4) / 10
		return top * (1 - math.cos(u * math.pi)) / 2 -- the slow climb
	elseif c < 17 then
		return top -- the wait at the top...
	elseif c < 18.3 then
		local u = (c - 17) / 1.3
		return top * (1 - u * u) -- FREEFALL
	elseif c < 20 then
		local u = (c - 18.3) / 1.7
		return math.abs(math.sin(u * math.pi)) * 3 * (1 - u) -- a little bounce
	end
	return 0
end

local function animate(model, info, t)
	local kind = model:GetAttribute("Kind")
	local hub = model:GetAttribute("Hub")
	if kind == "wheel" or kind == "spin" then
		local axis = model:GetAttribute("Axis") or Vector3.new(0, 1, 0)
		local angle = t * (model:GetAttribute("Speed") or 0.2)
		local rot = rotation(axis, angle)
		local around = CFrame.new(hub) * rot * CFrame.new(-hub)
		for _, e in ipairs(info.Parts) do
			if e.Pivot then
				-- a gondola: its hanging point goes round, it stays upright
				local pivot = around * e.Pivot
				e.Part.CFrame = e.Orig + (pivot - e.Pivot)
			elseif e.Spin then
				local cf = around * e.Orig
				if e.Bob then
					cf = cf + Vector3.new(0, math.sin(t * 2.2 + e.Phase) * e.Bob, 0)
				end
				e.Part.CFrame = cf
			end
		end
	elseif kind == "drop" then
		local h = Rides.DropHeight(t, model:GetAttribute("Height") or 60)
		for _, e in ipairs(info.Parts) do
			if e.Lift then
				e.Part.CFrame = e.Orig + Vector3.new(0, h, 0)
			end
		end
	end
end

local function seatByName(name)
	if not seats then
		seats = {}
		for _, s in ipairs(CollectionService:GetTagged("CitySeat")) do
			seats[s.Name] = s
		end
	end
	local s = seats[name]
	if s and not s.Parent then
		seats = nil
		return nil
	end
	return s
end

-- citizens on a ride go round in their seats
local function riders()
	for _, m in ipairs(CollectionService:GetTagged("Citizen")) do
		local name = m:GetAttribute("RideSeat")
		if name then
			local seat = seatByName(name)
			local root = m:FindFirstChild("HumanoidRootPart")
			if seat and root then
				local scale = m:GetAttribute("Scale") or 1
				root.CFrame = CFrame.new(seat.Position + Vector3.new(0, seat.Size.Y / 2 + 0.55 * scale, 0)) * (seat.CFrame - seat.Position)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The Sky Obby
--------------------------------------------------------------------------------
local function inside(part, pos, pad)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2 + pad
	return math.abs(rel.X) < half.X and math.abs(rel.Y) < half.Y and math.abs(rel.Z) < half.Z
end

function Rides.ObbyStep(t)
	for p in pairs(movers) do
		if not p.Parent then
			movers[p] = nil
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("ObbyMover")) do
		movers[p] = movers[p] or p.CFrame
		local axis = p:GetAttribute("MoveAxis") or Vector3.new(1, 0, 0)
		local speed, dist = p:GetAttribute("MoveSpeed") or 1, p:GetAttribute("MoveDist") or 6
		p.CFrame = movers[p] + axis * math.sin(t * speed) * dist
		-- (a velocity on the platform carries whoever stands on it along)
		p.AssemblyLinearVelocity = axis * math.cos(t * speed) * speed * dist
	end
	for _, p in ipairs(CollectionService:GetTagged("ObbySpinner")) do
		movers[p] = movers[p] or p.CFrame
		p.CFrame = movers[p] * CFrame.Angles(0, t * (p:GetAttribute("SpinSpeed") or 1.5), 0)
	end
	-- in a run: lava, the bars and falling send you back to your checkpoint
	local cp = player:GetAttribute("ObbyCheckpoint")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not cp or not root then
		return nil
	end
	local fail
	if root.Position.Y < cp.Y - 6 then
		fail = "fell"
	else
		for _, p in ipairs(CollectionService:GetTagged("ObbyKill")) do
			if inside(p, root.Position, Vector3.new(0.8, 2.6, 0.8)) then
				fail = if p.Name == "ObbySpinner" then "bar" else "lava"
				break
			end
		end
	end
	if fail and os.clock() - (Rides.LastFail or 0) > 0.6 then
		Rides.LastFail = os.clock()
		Rides.Fails = (Rides.Fails or 0) + 1
		root.CFrame = CFrame.new(cp + Vector3.new(0, 3.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		if Rides.OnFail then
			Rides.OnFail(fail)
		end
		return fail
	end
	return nil
end

function Rides.Step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = workspace:GetServerTimeNow()
	for _, model in ipairs(CollectionService:GetTagged("Ride")) do
		local hub = model:GetAttribute("Hub")
		if hub and (hub - camPos).Magnitude < RANGE then
			local info = rides[model]
			-- (streamed out and back in: the parts are new, start over)
			if info and (#info.Parts == 0 or not info.Parts[1].Part.Parent) then
				info = nil
			end
			animate(model, info or capture(model), t)
		end
	end
	riders()
	Rides.ObbyStep(t)
end

function Rides.Start(ctx)
	Rides.OnFail = function(why)
		if ctx and ctx.Hud then
			ctx.Hud.Toast(if why == "fell" then "🪂" else "🔥", if why == "fell" then "You fell!" else "Ouch!", "Back to your last checkpoint.", Color3.fromRGB(255, 140, 60))
		end
	end
	local step = RunService.PreSimulation or RunService.Stepped
	step:Connect(function()
		local ok, err = pcall(Rides.Step)
		if not ok then
			warn("[Rides] " .. tostring(err))
		end
	end)
end

return Rides
