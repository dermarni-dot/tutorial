-- Water (ModuleScript) — StarterPlayerScripts.CityClient.Water
-- Fish you can see: schools of fish swim around under the surface of Mirror
-- Lake (and koi in the park ponds). Every "Water" part (see Landscape and
-- Places) gets its own fish: bodies with a tail that sways as they swim, a fin
-- and eyes. They cruise, turn, dart away now and then, and when a fish bites
-- your line one swims right up to the bobber. They only swim near the camera
-- (made on each player's screen, so they cost the server nothing).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Water = {}
local schools = {} -- [water part] = { Fish = { fish }, Folder }
local RANGE = 320

local KINDS = {
	lake = {
		{ Color3.fromRGB(90, 130, 170), 1.3 }, { Color3.fromRGB(200, 180, 80), 1 }, { Color3.fromRGB(150, 120, 70), 2 },
		{ Color3.fromRGB(80, 120, 70), 1.6 }, { Color3.fromRGB(200, 140, 160), 1.4 }, { Color3.fromRGB(110, 100, 90), 2.2 },
		{ Color3.fromRGB(230, 150, 60), 0.9 },
	},
	pond = { { Color3.fromRGB(255, 140, 40), 1 }, { Color3.fromRGB(250, 250, 245), 1 }, { Color3.fromRGB(255, 190, 40), 1.1 }, { Color3.fromRGB(230, 70, 60), 0.9 } },
}

local function part(parent, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function makeFish(folder, color, scale)
	local body = part(folder, "Fish", Vector3.new(0.5, 0.6, 1.5) * scale, color)
	local belly = part(folder, "FishBelly", Vector3.new(0.42, 0.25, 1.2) * scale, color:Lerp(Color3.new(1, 1, 1), 0.45))
	local tail = part(folder, "FishTail", Vector3.new(0.08, 0.7, 0.5) * scale, color:Lerp(Color3.new(0, 0, 0), 0.15))
	local fin = part(folder, "FishFin", Vector3.new(0.06, 0.3, 0.6) * scale, color:Lerp(Color3.new(0, 0, 0), 0.15))
	local eyes = {}
	for k = 1, 2 do
		eyes[k] = part(folder, "FishEye", Vector3.one * 0.14 * scale, Color3.fromRGB(20, 20, 20), Enum.PartType.Ball)
	end
	return { Body = body, Belly = belly, Tail = tail, Fin = fin, Eyes = eyes, Scale = scale }
end

local function randomPoint(w, rng)
	local c = w.Position
	local r = (w:GetAttribute("Radius") or 10) * 0.85
	local a = rng:NextNumber(0, math.pi * 2)
	local d = math.sqrt(rng:NextNumber()) * r
	local surface = w:GetAttribute("Surface") or c.Y
	local depth = w:GetAttribute("Depth") or 4
	local y = if depth < 1.5 then surface - depth * 0.45 else surface - rng:NextNumber(1.2, math.max(1.5, depth - 1))
	return Vector3.new(c.X + math.cos(a) * d, y, c.Z + math.sin(a) * d)
end

local function build(w)
	local folder = Instance.new("Folder")
	folder.Name = "LocalFish"
	folder.Parent = workspace
	local rng = Random.new(math.floor(w.Position.X * 7 + w.Position.Z))
	local kinds = KINDS[w:GetAttribute("Kind") or "lake"] or KINDS.lake
	local list = {}
	for k = 1, (w:GetAttribute("Fish") or 20) do
		local kind = kinds[rng:NextInteger(1, #kinds)]
		local scale = kind[2] * rng:NextNumber(0.7, 1.3) * (if w:GetAttribute("Kind") == "pond" then 0.8 else 1)
		local f = makeFish(folder, kind[1], scale)
		f.Pos = randomPoint(w, rng)
		f.Goal = randomPoint(w, rng)
		f.Dir = (f.Goal - f.Pos).Unit
		f.Speed = rng:NextNumber(2, 4.5) / math.sqrt(scale)
		f.Phase = rng:NextNumber(0, 6)
		f.Rng = rng
		table.insert(list, f)
	end
	schools[w] = { Fish = list, Folder = folder, Water = w }
end

local function place(f, t)
	local cf = CFrame.lookAt(f.Pos, f.Pos + f.Dir)
	local s = f.Scale
	local wag = math.sin(t * (6 + f.Speed * 2) + f.Phase)
	f.Body.CFrame = cf
	f.Belly.CFrame = cf * CFrame.new(0, -0.18 * s, 0)
	f.Tail.CFrame = cf * CFrame.new(0, 0, 0.75 * s) * CFrame.Angles(0, wag * 0.6, 0) * CFrame.new(0, 0, 0.25 * s)
	f.Fin.CFrame = cf * CFrame.new(0, 0.38 * s, 0.05 * s)
	f.Eyes[1].CFrame = cf * CFrame.new(0.22 * s, 0.1 * s, -0.55 * s)
	f.Eyes[2].CFrame = cf * CFrame.new(-0.22 * s, 0.1 * s, -0.55 * s)
end

local function step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	for _, w in ipairs(CollectionService:GetTagged("Water")) do
		local near = (w.Position - camPos).Magnitude < RANGE + (w:GetAttribute("Radius") or 10)
		local school = schools[w]
		if near and not school then
			build(w)
			school = schools[w]
		end
		if school then
			school.Folder.Parent = if near then workspace else nil
			if near then
				for _, f in ipairs(school.Fish) do
					local toGoal = f.Goal - f.Pos
					if toGoal.Magnitude < 1.5 or (f.Chase and t > f.Chase) then
						f.Chase = nil
						f.Goal = randomPoint(w, f.Rng)
						toGoal = f.Goal - f.Pos
						-- now and then a quick dart
						f.Burst = if f.Rng:NextNumber() < 0.15 then t + 0.8 else nil
					end
					local want = toGoal.Unit
					-- turn smoothly toward where it's going
					f.Dir = f.Dir:Lerp(want, math.min(1, dt * 1.6))
					if f.Dir.Magnitude < 0.01 then
						f.Dir = want
					end
					f.Dir = f.Dir.Unit
					local speed = f.Speed * (if f.Burst and t < f.Burst then 3 else 1) * (if f.Chase then 1.6 else 1)
					f.Pos += f.Dir * speed * dt
					place(f, t)
				end
			end
		end
	end
end

-- a fish bites your line: the nearest one swims up to the bobber
function Water.Bite(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	local best, bestD
	for _, school in pairs(schools) do
		for _, f in ipairs(school.Fish) do
			local d = (f.Pos - position).Magnitude
			if d < 40 and (not bestD or d < bestD) then
				best, bestD = f, d
			end
		end
	end
	if best then
		best.Goal = position - Vector3.new(0, 0.6, 0)
		best.Chase = os.clock() + 3
	end
end

function Water.Start()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, math.min(dt, 0.1))
		if not ok then
			warn("[Water] " .. tostring(err))
		end
	end)
end

return Water
