-- Pets (ModuleScript) — StarterPlayerScripts.CityClient.Pets
-- Draws everyone's pets on your screen (see PetService): the pet walks at its
-- owner's heels with its legs going, sits down and wags its tail when they
-- stop, and wears a name tag. The parrot flies at its owner's shoulder, and
-- the golden pup sparkles. Citizens walking their dogs get one too, and the
-- pens at the adoption stand have pets waiting for a home.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Pets = {}
local pets = {} -- [owner (player or model or display part)] = pet
Pets.All = pets
local folder
local RANGE = 170

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- what each kind looks like: colors, size, ears, tail, legs
local KINDS = {
	Dog = { Body = rgb(150, 100, 60), Accent = rgb(240, 225, 200), Scale = 1, Ears = "flop", Tail = "up" },
	Cat = { Body = rgb(130, 130, 136), Accent = rgb(240, 240, 240), Scale = 0.8, Ears = "point", Tail = "long" },
	Hamster = { Body = rgb(220, 170, 110), Accent = rgb(250, 240, 225), Scale = 0.45, Ears = "round", Tail = "none", Round = true },
	Fox = { Body = rgb(225, 110, 40), Accent = rgb(250, 250, 245), Scale = 0.85, Ears = "point", Tail = "bushy" },
	Duck = { Body = rgb(250, 220, 60), Accent = rgb(250, 150, 40), Scale = 0.6, Ears = "none", Tail = "none", Round = true, Beak = true },
	Bunny = { Body = rgb(245, 245, 245), Accent = rgb(250, 190, 200), Scale = 0.6, Ears = "long", Tail = "puff", Round = true },
	Parrot = { Body = rgb(40, 190, 90), Accent = rgb(230, 50, 50), Scale = 0.55, Ears = "none", Tail = "feather", Flying = true, Beak = true },
	GoldenPup = { Body = rgb(245, 200, 60), Accent = rgb(255, 245, 200), Scale = 1, Ears = "flop", Tail = "up", Shiny = true },
}
Pets.KINDS = KINDS

local function part(m, parts, name, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	table.insert(parts, { Part = p, Offset = offset, Role = name })
	return p
end

local function build(kind, name)
	local k = KINDS[kind] or KINDS.Dog
	local s = k.Scale
	local m = Instance.new("Model")
	m.Name = "Pet_" .. kind
	local parts = {}
	local legH = if k.Round then 0.35 * s else 1 * s
	local body = if k.Round then Vector3.new(1.3, 1.2, 1.5) * s else Vector3.new(1.2, 1, 2.2) * s
	local by = legH + body.Y / 2
	local material = if k.Shiny then Enum.Material.Metal else Enum.Material.SmoothPlastic
	part(m, parts, "Body", body, CFrame.new(0, by, 0), k.Body, if k.Round then Enum.PartType.Ball else nil, material)
	local headY, headZ = by + body.Y * 0.55, -body.Z * 0.5
	if k.Round then
		headY, headZ = by + body.Y * 0.45, -body.Z * 0.35
	end
	local hs = (if k.Round then 0.9 else 1) * s
	part(m, parts, "Head", Vector3.one * hs, CFrame.new(0, headY, headZ), k.Body, if k.Round then Enum.PartType.Ball else nil, material)
	if k.Beak then
		part(m, parts, "Beak", Vector3.new(0.35, 0.25, 0.5) * s, CFrame.new(0, headY - 0.05 * s, headZ - hs * 0.55), rgb(250, 150, 40))
	elseif not k.Round then
		part(m, parts, "Snout", Vector3.new(0.55, 0.45, 0.5) * s, CFrame.new(0, headY - 0.15 * s, headZ - 0.65 * s), k.Accent)
		part(m, parts, "Nose", Vector3.new(0.2, 0.15, 0.1) * s, CFrame.new(0, headY - 0.02 * s, headZ - 0.92 * s), rgb(30, 30, 30))
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(m, parts, "Eye", Vector3.one * 0.16 * s, CFrame.new(sx * 0.24 * s, headY + 0.15 * s, headZ - hs * 0.48), rgb(20, 20, 20), Enum.PartType.Ball)
		if k.Ears == "flop" then
			part(m, parts, "Ear", Vector3.new(0.18, 0.6, 0.4) * s, CFrame.new(sx * 0.55 * s, headY + 0.05 * s, headZ + 0.05 * s) * CFrame.Angles(0, 0, sx * 0.25), k.Body:Lerp(rgb(0, 0, 0), 0.25))
		elseif k.Ears == "point" then
			part(m, parts, "Ear", Vector3.new(0.3, 0.45, 0.15) * s, CFrame.new(sx * 0.3 * s, headY + 0.6 * s, headZ + 0.1 * s) * CFrame.Angles(0, 0, sx * -0.2), k.Body)
		elseif k.Ears == "long" then
			part(m, parts, "Ear", Vector3.new(0.25, 1.2, 0.15) * s, CFrame.new(sx * 0.2 * s, headY + 0.95 * s, headZ + 0.1 * s) * CFrame.Angles(0, 0, sx * -0.12), k.Body)
		elseif k.Ears == "round" then
			part(m, parts, "Ear", Vector3.one * 0.35 * s, CFrame.new(sx * 0.32 * s, headY + 0.4 * s, headZ), k.Accent, Enum.PartType.Ball)
		end
	end
	if not k.Flying then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local leg = part(m, parts, "Leg", Vector3.new(0.3 * s, legH, 0.3 * s), CFrame.new(sx * body.X * 0.32, legH / 2, sz * body.Z * 0.32), if k.Beak then rgb(250, 150, 40) else k.Body:Lerp(rgb(0, 0, 0), 0.1))
				leg:SetAttribute("Side", sx * sz)
			end
		end
	else
		for _, sx in ipairs({ -1, 1 }) do
			local wing = part(m, parts, "Wing", Vector3.new(0.2, 0.7, 1.1) * s, CFrame.new(sx * 0.7 * s, by, 0.1 * s), k.Accent)
			wing:SetAttribute("Side", sx)
		end
	end
	local tailBase = CFrame.new(0, by + body.Y * 0.2, body.Z * 0.5)
	if k.Tail == "up" then
		part(m, parts, "Tail", Vector3.new(0.22, 0.22, 1) * s, tailBase * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, 0, 0.45 * s), k.Body)
	elseif k.Tail == "long" then
		part(m, parts, "Tail", Vector3.new(0.18, 0.18, 1.5) * s, tailBase * CFrame.Angles(math.rad(55), 0, 0) * CFrame.new(0, 0, 0.7 * s), k.Body)
	elseif k.Tail == "bushy" then
		part(m, parts, "Tail", Vector3.new(0.6, 0.6, 1.6) * s, tailBase * CFrame.Angles(math.rad(25), 0, 0) * CFrame.new(0, 0, 0.75 * s), k.Body)
		part(m, parts, "TailTip", Vector3.new(0.62, 0.62, 0.5) * s, tailBase * CFrame.Angles(math.rad(25), 0, 0) * CFrame.new(0, 0, 1.45 * s), k.Accent)
	elseif k.Tail == "puff" then
		part(m, parts, "Tail", Vector3.one * 0.5 * s, tailBase * CFrame.new(0, 0, 0.1), rgb(255, 255, 255), Enum.PartType.Ball)
	elseif k.Tail == "feather" then
		part(m, parts, "Tail", Vector3.new(0.4, 0.1, 1.2) * s, tailBase * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, 0.5 * s), rgb(40, 110, 220))
	end
	if k.Shiny then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = rgb(255, 230, 120)
		sparkle.Parent = parts[1].Part
	end
	if name then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 24)
		gui.StudsOffset = Vector3.new(0, 1.6 * s + 0.8, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 60
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "🐾 " .. name
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.5
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		gui.Adornee = parts[2].Part
		gui.Parent = m
	end
	m.Parent = folder
	return { Model = m, Parts = parts, Kind = kind, Spec = k, Name = name, Walk = 0 }
end

local function place(pet, cf, t, moving, sitting)
	local k = pet.Spec
	local s = k.Scale
	local wag = math.sin(t * (if sitting then 9 else 6)) * (if sitting then 0.5 else 0.25)
	pet.Walk += if moving then 0.2 else 0
	local swing = if moving then math.sin(t * 12) * 0.6 else 0
	local sit = if sitting and not k.Flying then CFrame.new(0, 0, 0.3 * s) * CFrame.Angles(math.rad(-18), 0, 0) else CFrame.new()
	for _, e in ipairs(pet.Parts) do
		local off = e.Offset
		if e.Role == "Leg" then
			off = off * CFrame.Angles(swing * (e.Part:GetAttribute("Side") or 1), 0, 0)
		elseif e.Role == "Tail" or e.Role == "TailTip" then
			off = CFrame.Angles(0, wag, 0) * off
		elseif e.Role == "Wing" then
			off = off * CFrame.Angles(0, 0, math.sin(t * 16) * 0.7 * (e.Part:GetAttribute("Side") or 1))
		end
		if e.Role ~= "Leg" then
			off = sit * off
		end
		e.Part.CFrame = cf * off
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundBelow(pos, fallback)
	local ok, hit = pcall(function()
		return workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
	end)
	if ok and hit then
		return hit.Position.Y
	end
	return fallback
end

local function follow(pet, root, dt, t, ownerScale)
	local k = pet.Spec
	local rootCf = root.CFrame
	local groundY = root.Position.Y - 3 * (ownerScale or 1)
	local want
	if k.Flying then
		want = (rootCf * CFrame.new(1.8, 1.8, 0.4)).Position + Vector3.new(0, math.sin(t * 3) * 0.3, 0)
	else
		want = (rootCf * CFrame.new(2.4, 0, 2.8)).Position
		want = Vector3.new(want.X, groundBelow(want, groundY), want.Z)
	end
	pet.Pos = pet.Pos or want
	local d = (want - pet.Pos).Magnitude
	if d > 45 then
		pet.Pos = want -- (fell too far behind: catch up)
	else
		pet.Pos = pet.Pos:Lerp(want, 1 - math.exp(-dt * 5))
	end
	local moving = d > 0.9
	local look = if moving then Vector3.new(want.X - pet.Pos.X, 0, want.Z - pet.Pos.Z) else Vector3.new(rootCf.LookVector.X, 0, rootCf.LookVector.Z)
	if look.Magnitude > 0.01 then
		pet.Look = (pet.Look or look.Unit):Lerp(look.Unit, math.min(1, dt * 8))
	end
	local dir = pet.Look or Vector3.new(0, 0, -1)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	local base = if k.Flying then CFrame.lookAt(pet.Pos, pet.Pos + dir) else CFrame.lookAt(pet.Pos, pet.Pos + dir)
	place(pet, base, t, moving, not moving)
	pet.Moving = moving
end

local function drop(owner)
	local pet = pets[owner]
	if pet then
		pet.Model:Destroy()
		pets[owner] = nil
	end
end

function Pets.Step(dt)
	local camera = workspace.CurrentCamera
	if not camera or not folder then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local seen = {}
	local function want(owner, kind, name, root, scale)
		if not kind or not root or (root.Position - camPos).Magnitude > RANGE then
			return
		end
		seen[owner] = true
		local pet = pets[owner]
		if pet and (pet.Kind ~= kind or pet.Name ~= name) then
			drop(owner)
			pet = nil
		end
		if not pet then
			pet = build(kind, name)
			pets[owner] = pet
		end
		follow(pet, root, dt, t, scale)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		want(p, p:GetAttribute("Pet"), p:GetAttribute("PetName"), root, 1)
	end
	for _, m in ipairs(CollectionService:GetTagged("Citizen")) do
		local kind = m:GetAttribute("Pet")
		if kind then
			local root = m:FindFirstChild("HumanoidRootPart")
			-- (dogs stay home while their owner sleeps or works indoors)
			local action = m:GetAttribute("Action") or ""
			if root and (action == "" or action == "wait" or action == "phone" or action == "sit" or action == "birdwatch" or action == "chat") then
				want(m, kind, nil, root, m:GetAttribute("Scale") or 1)
			end
		end
	end
	-- the pets waiting at the adoption stand sit and wag
	for _, d in ipairs(CollectionService:GetTagged("PetDisplay")) do
		if (d.Position - camPos).Magnitude < RANGE then
			seen[d] = true
			local pet = pets[d]
			if not pet then
				pet = build(d:GetAttribute("Pet") or "Dog", nil)
				pets[d] = pet
			end
			place(pet, CFrame.new(d.Position - Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.sin(t * 0.3 + d.Position.X) * 0.8, 0), t, false, true)
		end
	end
	for owner in pairs(pets) do
		if not seen[owner] then
			drop(owner)
		end
	end
end

function Pets.Start()
	folder = Instance.new("Folder")
	folder.Name = "LocalPets"
	folder.Parent = workspace
	rayParams.FilterDescendantsInstances = { folder }
	RunService.Heartbeat:Connect(function(dt)
		local skip = { folder, workspace:FindFirstChild("Citizens") }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(skip, p.Character)
			end
		end
		rayParams.FilterDescendantsInstances = skip
		local ok, err = pcall(Pets.Step, math.min(dt, 0.1))
		if not ok then
			warn("[Pets] " .. tostring(err))
		end
	end)
end

return Pets
