-- Visuals (ModuleScript) — ReplicatedStorage.Shared.Visuals
-- Shared so the client can build pet models for 3D previews in the UI.
-- Builds every egg, pet and guardian from code in a chunky cartoon style:
-- big shiny eyes, blush, outlines on guardians, and a unique look per species.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local Visuals = {}

local EGG_SIZE = Vector3.new(2.8, 3.6, 2.8)
Visuals.EggHalfHeight = EGG_SIZE.Y / 2

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(25, 22, 30)
local BLUSH = Color3.fromRGB(255, 140, 170)
local GOLD = Color3.fromRGB(255, 205, 70)

--------------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------------
local function newPart(name, shape, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	if shape == "Blob" then
		-- a block with a sphere mesh stretches into any ellipsoid
		p.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
	else
		p.Shape = Enum.PartType.Block
	end
	return p
end

-- Returns an `add` function that welds parts onto `body` at an offset.
-- While a pet is being built, cartoon-only details are left off so pets look
-- like real animals (guardians keep their cartoon faces).
local PET_BUILD = false
local PET_SKIP = { Blush = true, ToeBean = true, Smile = true, Tongue = true, Lash = true, Gloss = true, Mouth = false }

local function rigger(model, body)
	return function(name, shape, size, offset, color, material)
		if PET_BUILD and PET_SKIP[name] then
			return newPart(name, shape, size, color) -- never parented
		end
		local p = newPart(name, shape, size, color)
		if material then
			p.Material = material
		end
		p.CFrame = body.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
end

-- Cartoon eye: white, big pupil, and a little shine. `offset` is the eye center.
local function addEye(add, offset, size, angry, side)
	add("Eye", "Blob", Vector3.new(size, size * 1.15, size * 0.7), offset, WHITE)
	add("Pupil", "Blob", Vector3.new(size * 0.55, size * 0.7, size * 0.4), offset * CFrame.new(0, -size * 0.05, -size * 0.2), BLACK)
	add("Shine", "Ball", Vector3.one * size * 0.22, offset * CFrame.new(size * 0.12, size * 0.18, -size * 0.36), WHITE, Enum.Material.Neon)
	if angry then
		add("Brow", "Block", Vector3.new(size * 1.1, size * 0.22, size * 0.3), offset * CFrame.new(0, size * 0.62, -size * 0.2) * CFrame.Angles(0, 0, math.rad(20 * side)), BLACK)
	end
end

local function outline(model, color)
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineColor = color or Color3.fromRGB(30, 20, 20)
	h.OutlineTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
end

--------------------------------------------------------------------------------
-- Labels
--------------------------------------------------------------------------------
function Visuals.AddLabel(part, offsetY, width)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(width or 190, 58)
	bb:SetAttribute("Width", width or 190)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0

	-- rounded pill behind the text for a clean, readable tag
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	pill.BackgroundTransparency = 0.35
	pill.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = pill
	local st = Instance.new("UIStroke")
	st.Name = "Stroke"
	st.Thickness = 2
	st.Transparency = 0.2
	st.Color = WHITE
	st.Parent = pill

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.06, 0.06)
	title.Size = UDim2.fromScale(0.88, 0.52)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = WHITE
	title.TextStrokeTransparency = 0.4
	title.Text = ""
	title.Parent = bb

	local sub = title:Clone()
	sub.Name = "Sub"
	sub.Position = UDim2.fromScale(0.08, 0.56)
	sub.Size = UDim2.fromScale(0.84, 0.36)
	sub.Font = Enum.Font.GothamBold
	sub.TextStrokeTransparency = 1
	sub.TextColor3 = Color3.fromRGB(230, 230, 240)
	sub.Parent = bb

	bb.Parent = part
	return bb
end

function Visuals.SetLabel(part, title, sub, titleColor)
	local bb = part:FindFirstChild("Label")
	if not bb then
		return
	end
	bb.Title.Text = title or ""
	bb.Sub.Text = sub or ""
	bb.Title.TextColor3 = titleColor or WHITE
	bb.Pill.Stroke.Color = titleColor or WHITE
	bb.Pill.Visible = (title or "") ~= "" or (sub or "") ~= ""
end

--------------------------------------------------------------------------------
-- Eggs: glossy, banded, spotted; rarer eggs glow and sparkle
--------------------------------------------------------------------------------
local EGG_DESIGNS = {}

-- Every egg: position helpers on the egg surface (an ellipsoid).
local function surface(angle, y, inset)
	local r = EGG_SIZE.X / 2 * math.sqrt(math.max(0, 1 - (y / (EGG_SIZE.Y / 2)) ^ 2)) * (inset or 0.97)
	return CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * CFrame.Angles(0, -angle + math.pi / 2, 0)
end

local function ring(add, y, color, material, thickness)
	local r = EGG_SIZE.X / 2 * math.sqrt(1 - (y / (EGG_SIZE.Y / 2)) ^ 2)
	add("Ring", "Cyl", Vector3.new(thickness or 0.28, r * 2 + 0.08, r * 2 + 0.08), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), color, material)
end

-- Common: creamy with brown speckles
function EGG_DESIGNS.Common(add, c)
	local speck = Color3.fromRGB(150, 115, 80)
	for i = 1, 14 do
		local a = i * 2.4
		local y = ((i * 37) % 26) / 10 - 1.3
		add("Speck", "Blob", Vector3.new(0.32, 0.32, 0.12), surface(a, y), speck)
	end
end

-- Uncommon: green with a leafy wrap and a zig-zag crack band
function EGG_DESIGNS.Uncommon(add, c, dark)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("Zig", "Block", Vector3.new(0.7, 0.24, 0.2), surface(a, if i % 2 == 0 then 0.1 else -0.25) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)), dark)
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("Leaf", "Blob", Vector3.new(0.9, 1.5, 0.25), surface(a, -1.05, 1.02) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(70, 160, 60))
	end
	add("Sprout", "Blob", Vector3.new(0.5, 0.2, 0.9), CFrame.new(0.3, 1.85, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(90, 190, 70))
	add("Sprout", "Blob", Vector3.new(0.5, 0.2, 0.9), CFrame.new(-0.3, 1.85, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(90, 190, 70))
end

-- Rare: striped blue with a glowing star
function EGG_DESIGNS.Rare(add, c, dark)
	ring(add, 0.55, WHITE)
	ring(add, -0.55, WHITE)
	ring(add, 0, dark)
	for side = 0, 1 do
		local cf = surface(side * math.pi, 1.05, 1.0)
		add("Star", "Block", Vector3.new(0.55, 0.55, 0.12), cf, Color3.fromRGB(255, 240, 120), Enum.Material.Neon)
		add("Star", "Block", Vector3.new(0.55, 0.55, 0.12), cf * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 240, 120), Enum.Material.Neon)
	end
end

-- Epic: crystals bursting out of the shell
function EGG_DESIGNS.Epic(add, c, dark)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("Zig", "Block", Vector3.new(0.7, 0.26, 0.22), surface(a, if i % 2 == 0 then 0.05 else -0.3) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 32 else -32)), Color3.fromRGB(240, 170, 255), Enum.Material.Neon)
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.3
		local y = if i % 2 == 0 then 0.8 else -0.7
		add("Crystal", "Block", Vector3.new(0.45, 1.3, 0.45), surface(a, y, 0.9) * CFrame.Angles(math.rad(-50), 0, math.rad(15)), Color3.fromRGB(200, 150, 255), Enum.Material.Glass)
	end
	add("TopCrystal", "Block", Vector3.new(0.5, 1.2, 0.5), CFrame.new(0, 1.9, 0) * CFrame.Angles(0, math.rad(45), math.rad(10)), Color3.fromRGB(220, 170, 255), Enum.Material.Neon)
end

-- Legendary: golden, with little wings and a jeweled crown band
function EGG_DESIGNS.Legendary(add, c)
	ring(add, 0.2, Color3.fromRGB(255, 235, 150), Enum.Material.Metal, 0.35)
	for i = 0, 5 do
		add("Jewel", "Ball", Vector3.one * 0.32, surface(i / 6 * math.pi * 2, 0.2, 1.07), if i % 2 == 0 then Color3.fromRGB(255, 60, 90) else Color3.fromRGB(80, 170, 255), Enum.Material.Neon)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			add("Feather", "Blob", Vector3.new(0.18, 0.5, 1.3 - j * 0.25), CFrame.new(sx * (1.5 + j * 0.05), 0.55 - j * 0.35, 0.2 + j * 0.1) * CFrame.Angles(math.rad(-10 - j * 12), 0, math.rad(-35 * sx)), WHITE)
		end
	end
end

-- Mythic: dark cosmic shell full of stars, with an orbiting ring and halo
function EGG_DESIGNS.Mythic(add, c)
	for i = 1, 16 do
		local a = i * 2.2
		local y = ((i * 29) % 30) / 10 - 1.5
		add("Star", "Ball", Vector3.one * (if i % 3 == 0 then 0.26 else 0.16), surface(a, y, 1.0), if i % 2 == 0 then WHITE else Color3.fromRGB(255, 180, 230), Enum.Material.Neon)
	end
	local tilt = CFrame.Angles(math.rad(20), 0, math.rad(15))
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		add("Orbit", "Ball", Vector3.one * 0.26, tilt * CFrame.new(math.cos(a) * 2.3, 0, math.sin(a) * 2.3), Color3.fromRGB(255, 130, 200), Enum.Material.Neon)
	end
	add("Halo", "Cyl", Vector3.new(0.14, 1.6, 1.6), CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 230, 140), Enum.Material.Neon)
end

--------------------------------------------------------------------------------
-- Mutations: tint + particles + extras on an egg (a part) or a pet (a model)
--------------------------------------------------------------------------------
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local KEEP_COLOR = { Eye = true, Pupil = true, Shine = true, Mark = true, Blush = true, Mouth = true, Tongue = true, Iris = true, Lid = true, ToeBean = true, Gloss = true, Halo = true, NoseShine = true }

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local MUTATION_FX = {
	Golden = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(255, 205, 60), 0.55)
			if p.Material == Enum.Material.SmoothPlastic then
				p.Material = Enum.Material.Foil
			end
		end
		emitter(main, { Color = ColorSequence.new(Color3.fromRGB(255, 225, 110)), Size = NumberSequence.new(0.35, 0), Lifetime = NumberRange.new(0.8, 1.4), Rate = 10, Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180) })
	end,
	Diamond = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(170, 240, 255), 0.6)
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.25
		end
		emitter(main, { Color = ColorSequence.new(Color3.fromRGB(200, 250, 255)), Size = NumberSequence.new(0.45, 0), Lifetime = NumberRange.new(0.5, 1), Rate = 8, Speed = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 180) })
	end,
	Electric = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(255, 240, 90), 0.35)
		end
		emitter(main, { Color = ColorSequence.new(Color3.fromRGB(255, 250, 150), Color3.fromRGB(120, 200, 255)), Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(0.15, 0.35), Rate = 30, Speed = NumberRange.new(6, 10), SpreadAngle = Vector2.new(180, 180) })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 240, 120)
		l.Range = 12
		l.Brightness = 2
		l.Parent = main
	end,
	Lava = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(80, 30, 20), 0.5)
		end
		local fire = Instance.new("Fire")
		fire.Size = math.max(main.Size.X, main.Size.Y) * 0.9
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 120, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
		fire.Parent = main
		emitter(main, { Color = ColorSequence.new(Color3.fromRGB(255, 150, 50), Color3.fromRGB(255, 60, 20)), Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(1, 2), Rate = 14, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top })
	end,
	Frozen = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(190, 235, 255), 0.55)
		end
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			local shard = newPart("IceShard", "Block", Vector3.new(0.35, 1.1, 0.35) * math.max(1, main.Size.Y / 3.5), Color3.fromRGB(200, 240, 255))
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.2
			shard.CFrame = main.CFrame * CFrame.new(math.cos(a) * main.Size.X * 0.45, main.Size.Y * 0.35, math.sin(a) * main.Size.Z * 0.45) * CFrame.Angles(math.rad(25), a, 0)
			local w = Instance.new("WeldConstraint")
			w.Part0 = main
			w.Part1 = shard
			w.Parent = shard
			shard.Parent = main
		end
		emitter(main, { Color = ColorSequence.new(WHITE), LightEmission = 0.4, Size = NumberSequence.new(0.25), Lifetime = NumberRange.new(1.5, 2.5), Rate = 12, Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, -2, 0), SpreadAngle = Vector2.new(180, 180) })
	end,
	Rainbow = function(main, parts)
		-- clients cycle the colors of these parts through the rainbow
		for _, p in ipairs(parts) do
			p:SetAttribute("RainbowFX", true)
		end
		emitter(main, { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)), ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)) }), Size = NumberSequence.new(0.4, 0), Lifetime = NumberRange.new(1, 1.6), Rate = 16, Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(180, 180) })
	end,
	Galaxy = function(main, parts)
		for _, p in ipairs(parts) do
			p.Color = p.Color:Lerp(Color3.fromRGB(40, 20, 90), 0.65)
		end
		emitter(main, { Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 150, 255)), Size = NumberSequence.new(0.25, 0), Lifetime = NumberRange.new(2, 3), Rate = 18, Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(180, 180) })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(160, 110, 255)
		l.Range = 14
		l.Brightness = 2
		l.Parent = main
	end,
}

local function glowLight(main, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = main
	return l
end
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

MUTATION_FX.Void = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(12, 6, 22), 0.8)
	end
	-- purple sparks pulled inward, like a black hole
	emitter(main, { Color = ColorSequence.new(Color3.fromRGB(200, 120, 255), Color3.fromRGB(60, 10, 120)), Size = NumberSequence.new(0.4, 0), Lifetime = NumberRange.new(0.8, 1.2), Rate = 26, Speed = NumberRange.new(-4, -2), SpreadAngle = Vector2.new(180, 180) })
	emitter(main, { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(40, 10, 70)), LightEmission = 0, Size = NumberSequence.new(1, 2.5), Transparency = NumberSequence.new(0.5, 1), Lifetime = NumberRange.new(1, 2), Rate = 8, Speed = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 180) })
	glowLight(main, Color3.fromRGB(150, 60, 255), 14, 2.5)
end
MUTATION_FX.Solar = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(255, 190, 60), 0.55)
	end
	emitter(main, { Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 140, 30)), Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(0.6, 1), Rate = 30, Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(180, 180) })
	glowLight(main, Color3.fromRGB(255, 200, 90), 18, 3)
end
MUTATION_FX.Neon = function(main, parts)
	local cols = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(40, 240, 255) }
	for i, p in ipairs(parts) do
		if i % 3 == 0 then
			p.Material = Enum.Material.Neon
			p.Color = cols[(i // 3) % 2 + 1]
		else
			p.Color = p.Color:Lerp(Color3.fromRGB(30, 20, 50), 0.5)
		end
	end
	glowLight(main, Color3.fromRGB(255, 80, 230), 16, 2.5)
end
MUTATION_FX.Shadow = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(25, 20, 35), 0.65)
	end
	emitter(main, { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(20, 15, 30)), LightEmission = 0, Size = NumberSequence.new(0.8, 2), Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(1.2, 2), Rate = 12, Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Top })
	glowLight(main, Color3.fromRGB(120, 80, 200), 10, 1)
end
MUTATION_FX.Ghostly = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(230, 245, 255), 0.6)
		p.Transparency = math.max(p.Transparency, 0.35)
	end
	emitter(main, { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(220, 245, 255)), LightEmission = 0.5, Size = NumberSequence.new(0.6, 1.4), Transparency = NumberSequence.new(0.5, 1), Lifetime = NumberRange.new(1.5, 2.5), Rate = 8, Speed = NumberRange.new(0.5, 1.2), EmissionDirection = Enum.NormalId.Top })
end
MUTATION_FX.Toxic = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(110, 230, 60), 0.5)
	end
	emitter(main, { Color = ColorSequence.new(Color3.fromRGB(170, 255, 90), Color3.fromRGB(60, 180, 40)), Size = NumberSequence.new(0.35, 0.6), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(1, 1.8), Rate = 16, Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top })
	glowLight(main, Color3.fromRGB(140, 255, 80), 12, 1.5)
end
MUTATION_FX.Crystal = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(170, 225, 255), 0.5)
		p.Material = Enum.Material.Glass
		p.Reflectance = 0.15
	end
	emitter(main, { Color = ColorSequence.new(WHITE, Color3.fromRGB(150, 220, 255)), Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(0.8, 1.4), Rate = 12, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180) })
end
MUTATION_FX.Candy = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(255, 170, 215), 0.45)
	end
	emitter(main, { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 170)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 220, 255)) }), LightEmission = 0.3, Size = NumberSequence.new(0.25), Lifetime = NumberRange.new(1, 1.6), Rate = 14, Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, -4, 0), SpreadAngle = Vector2.new(180, 180) })
end
MUTATION_FX.Aqua = function(main, parts)
	for _, p in ipairs(parts) do
		p.Color = p.Color:Lerp(Color3.fromRGB(70, 160, 255), 0.5)
		p.Reflectance = 0.1
	end
	emitter(main, { Color = ColorSequence.new(Color3.fromRGB(210, 240, 255)), LightEmission = 0.4, Size = NumberSequence.new(0.25, 0.5), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(1.2, 2), Rate = 14, Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top })
end

-- target: an egg part or a pet model. Returns the mutation def (or nil).
function Visuals.ApplyMutation(target, mutationId)
	local def = mutationId and Config.MutationById[mutationId]
	local fx = mutationId and MUTATION_FX[mutationId]
	if not def or not fx then
		return nil
	end
	local main = if target:IsA("Model") then target.PrimaryPart else target
	local parts = {}
	if target:IsA("BasePart") then
		table.insert(parts, target)
	end
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") and not KEEP_COLOR[d.Name] and d.Material ~= Enum.Material.Neon then
			table.insert(parts, d)
		end
	end
	fx(main, parts)
	return def
end

-- A glowing ring on the ground that shows an egg's rarity from far away.
function Visuals.MakeRarityRing(rarityId, groundPos)
	local rarity = Config.RarityById[rarityId]
	local ring = Instance.new("Part")
	ring.Name = "RarityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 7.6, 7.6)
	ring.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = rarity.Color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	if rarity.Order >= 4 then
		local beam = Instance.new("ParticleEmitter")
		beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		beam.Color = ColorSequence.new(rarity.Color)
		beam.LightEmission = 1
		beam.Size = NumberSequence.new(0.5, 0)
		beam.Lifetime = NumberRange.new(1.5, 2.5)
		beam.Rate = 12
		beam.Speed = NumberRange.new(3, 6)
		beam.SpreadAngle = Vector2.new(8, 8)
		beam.EmissionDirection = Enum.NormalId.Right -- cylinder's axis points up
		beam.Parent = ring
	end
	return ring
end

-- Divine: pearly white-gold, golden filigree, angel wings and a halo
function EGG_DESIGNS.Divine(add, c)
	local gold = Color3.fromRGB(255, 205, 80)
	ring(add, 0.6, gold, Enum.Material.Neon, 0.18)
	ring(add, -0.6, gold, Enum.Material.Neon, 0.18)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("Filigree", "Blob", Vector3.new(0.5, 0.28, 0.12), surface(a, 0, 1.0) * CFrame.Angles(0, 0, math.rad(45)), gold, Enum.Material.Neon)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 3 do
			add("WingFeather", "Blob", Vector3.new(0.2, 0.55, 1.8 - j * 0.32), CFrame.new(sx * (1.55 + j * 0.08), 0.75 - j * 0.38, 0.35 + j * 0.1) * CFrame.Angles(math.rad(-15 - j * 10), 0, math.rad(-30 * sx)), if j == 0 then Color3.fromRGB(255, 245, 210) else WHITE, Enum.Material.Neon)
		end
	end
	add("Halo", "Cyl", Vector3.new(0.16, 1.9, 1.9), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), gold, Enum.Material.Neon)
	add("HaloInner", "Cyl", Vector3.new(0.18, 1.4, 1.4), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 250, 235))
end

-- Secret: a black egg glitching with rainbow pixels and question marks
function EGG_DESIGNS.Secret(add, c)
	local rainbow = { Color3.fromRGB(255, 70, 90), Color3.fromRGB(255, 180, 50), Color3.fromRGB(255, 240, 80), Color3.fromRGB(80, 230, 120), Color3.fromRGB(70, 170, 255), Color3.fromRGB(190, 100, 255) }
	for i = 1, 22 do
		local a = i * 1.9
		local y = ((i * 31) % 32) / 10 - 1.6
		add("Pixel", "Block", Vector3.new(0.34, 0.34, 0.2), surface(a, y, 1.0), rainbow[(i % #rainbow) + 1], Enum.Material.Neon)
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("Crack", "Block", Vector3.new(0.66, 0.16, 0.18), surface(a, if i % 2 == 0 then 0.25 else -0.1) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)), rainbow[(i % #rainbow) + 1], Enum.Material.Neon)
	end
	for side = 0, 1 do
		local mark = add("Mark", "Block", Vector3.new(1, 1, 0.05), surface(side * math.pi, 0.9, 1.02), c)
		mark.Transparency = 1
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		local q = Instance.new("TextLabel")
		q.BackgroundTransparency = 1
		q.Size = UDim2.fromScale(1, 1)
		q.Font = Enum.Font.FredokaOne
		q.TextScaled = true
		q.Text = "?"
		q.TextColor3 = WHITE
		q.Parent = gui
		gui.Parent = mark
	end
end

--------------------------------------------------------------------------------
-- Egg variants: every rarity has its Classic design plus three more. Each
-- egg picks one at random when it spawns (Visuals.MakeEgg).
--------------------------------------------------------------------------------
-- A line running bottom to top that follows the curve of the shell
local function eggMeridian(add, angle, width, color, material, name)
	local h = EGG_SIZE.Y / 2
	local segments = 8
	for i = 0, segments - 1 do
		local y = -h * 0.92 + (i + 0.5) * (h * 1.84 / segments)
		local R = EGG_SIZE.X / 2
		local slope = -R * y / (h * h * math.sqrt(math.max(0.02, 1 - (y / h) ^ 2)))
		add(name or "Line", "Block", Vector3.new(width, h * 1.84 / segments + 0.06, 0.12), surface(angle, y, 1.0) * CFrame.Angles(math.atan(slope), 0, 0), color, material)
	end
end

local function eggDots(add, count, size, colors, material, seed)
	for i = 1, count do
		local a = i * 2.39996 + (seed or 0)
		local y = ((i * 37 + (seed or 0) * 11) % 28) / 10 - 1.4
		add("Dot", "Blob", Vector3.new(size, size, 0.12), surface(a, y, 1.0), colors[(i % #colors) + 1], material)
	end
end

local function eggZigzag(add, y, color, material)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("Zig", "Block", Vector3.new(0.7, 0.22, 0.2), surface(a, y + (if i % 2 == 0 then 0.18 else -0.18)) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)), color, material)
	end
end

local function eggStar(add, cf, size, color, material)
	add("Star", "Block", Vector3.new(size, size, 0.12), cf, color, material)
	add("Star", "Block", Vector3.new(size, size, 0.12), cf * CFrame.Angles(0, 0, math.rad(45)), color, material)
end

local function eggSpikes(add, y, count, len, color, material, offset)
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2 + (offset or 0)
		add("Spike", "Block", Vector3.new(0.26, 0.26, len), surface(a, y, 0.95) * CFrame.new(0, 0, len / 2) * CFrame.Angles(0, 0, math.rad(45)), color, material)
	end
end

local function eggWings(add, count, color, material, spread)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, count - 1 do
			add("Feather", "Blob", Vector3.new(0.18, 0.5, 1.4 - j * 0.25), CFrame.new(sx * (1.5 + j * 0.06), 0.6 - j * (spread or 0.36), 0.25 + j * 0.1) * CFrame.Angles(math.rad(-12 - j * 10), 0, math.rad(-32 * sx)), color, material)
		end
	end
end

local function eggSymbol(add, text, y, color, bgColor)
	for side = 0, 1 do
		local mark = add("Mark", "Block", Vector3.new(1, 1, 0.05), surface(side * math.pi + math.pi / 2, y, 1.02), bgColor)
		mark.Transparency = 1
		local sgui = Instance.new("SurfaceGui")
		sgui.Face = Enum.NormalId.Front
		sgui.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		t.Parent = sgui
		sgui.Parent = mark
	end
end

local function eggBow(add, color)
	add("Bow", "Blob", Vector3.new(0.9, 0.55, 0.3), CFrame.new(-0.42, 1.85, 0) * CFrame.Angles(0, 0, math.rad(20)), color)
	add("Bow", "Blob", Vector3.new(0.9, 0.55, 0.3), CFrame.new(0.42, 1.85, 0) * CFrame.Angles(0, 0, math.rad(-20)), color)
	add("BowKnot", "Ball", Vector3.one * 0.36, CFrame.new(0, 1.82, 0), color:Lerp(BLACK, 0.15))
	ring(add, 0, color, nil, 0.3)
end


-- Astral: pale starlit shell with a glowing ring and constellation dots
function EGG_DESIGNS.Astral(add, c)
	ring(add, 0.1, Color3.fromRGB(140, 230, 255), Enum.Material.Neon, 0.18)
	eggDots(add, 18, 0.16, { WHITE, Color3.fromRGB(150, 230, 255) }, Enum.Material.Neon, 21)
	for i = 0, 3 do
		eggMeridian(add, i * math.pi / 2, 0.08, Color3.fromRGB(190, 240, 255), Enum.Material.Neon)
	end
end
-- Cosmic: a deep purple galaxy swirl with colorful stars
function EGG_DESIGNS.Cosmic(add, c)
	local cols = { Color3.fromRGB(255, 120, 220), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 230, 120), Color3.fromRGB(190, 120, 255) }
	for i = 0, 29 do
		local a = i * 0.55
		local y = 1.5 - i * 0.1
		add("GalaxyArm", "Ball", Vector3.one * (0.18 + (i % 3) * 0.06), surface(a, y, 1.0), cols[(i % #cols) + 1], Enum.Material.Neon)
	end
	ring(add, -0.2, Color3.fromRGB(200, 140, 255), Enum.Material.Neon, 0.14)
	eggWings(add, 3, Color3.fromRGB(210, 170, 255), Enum.Material.Neon)
end
-- Omega: a dark crimson shell split by glowing cracks, with a gold crown band
function EGG_DESIGNS.Omega(add, c)
	local glow = Color3.fromRGB(255, 70, 90)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		for k = 0, 2 do
			add("Rift", "Block", Vector3.new(0.12, 0.55, 0.08), surface(a + k * 0.12, 1.1 - k * 0.55 - (i % 2) * 0.3, 1.01) * CFrame.Angles(0, 0, math.rad(if k % 2 == 0 then 25 else -25)), glow, Enum.Material.Neon)
		end
	end
	ring(add, 0.95, Color3.fromRGB(255, 205, 60), Enum.Material.Metal, 0.26)
	eggDots(add, 8, 0.2, { Color3.fromRGB(255, 205, 60) }, Enum.Material.Neon, 5)
end

local EGG_VARIANTS = {
	Common = {
		{ Name = "Polka", Color = Color3.fromRGB(255, 235, 240), Design = function(add)
			eggDots(add, 16, 0.42, { Color3.fromRGB(255, 150, 180), Color3.fromRGB(150, 210, 255), Color3.fromRGB(255, 220, 110) })
		end },
		{ Name = "Striped", Color = Color3.fromRGB(235, 245, 255), Design = function(add)
			for i, y in ipairs({ -1.1, -0.55, 0, 0.55, 1.1 }) do
				ring(add, y, if i % 2 == 0 then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 190, 150), nil, 0.26)
			end
		end },
		{ Name = "Gift", Color = Color3.fromRGB(240, 240, 250), Design = function(add)
			eggBow(add, Color3.fromRGB(240, 80, 110))
			eggDots(add, 8, 0.3, { Color3.fromRGB(255, 200, 80) }, nil, 3)
		end },
	},
	Uncommon = {
		{ Name = "Flower", Color = Color3.fromRGB(150, 225, 140), Design = function(add)
			for i = 0, 5 do
				local cf = surface(i / 6 * math.pi * 2, if i % 2 == 0 then 0.5 else -0.4, 1.0)
				add("FlowerCenter", "Ball", Vector3.one * 0.26, cf, Color3.fromRGB(255, 220, 80))
				for k = 0, 4 do
					local a = k / 5 * math.pi * 2
					add("Petal", "Blob", Vector3.new(0.3, 0.22, 0.1), cf * CFrame.new(math.cos(a) * 0.2, math.sin(a) * 0.2, 0), if i % 2 == 0 then Color3.fromRGB(255, 140, 190) else WHITE)
				end
			end
		end },
		{ Name = "Mossy", Color = Color3.fromRGB(120, 170, 90), Design = function(add)
			for i = 1, 12 do
				local a = i * 2.1
				add("Moss", "Ball", Vector3.one * (0.4 + (i % 3) * 0.1), surface(a, 1.2 - (i % 4) * 0.25, 0.95), Color3.fromRGB(70, 140, 60):Lerp(Color3.fromRGB(140, 200, 90), (i % 3) / 3))
			end
			add("Mushroom", "Blob", Vector3.new(0.7, 0.35, 0.7), CFrame.new(0.5, 1.75, 0), Color3.fromRGB(230, 70, 90))
			add("MushroomStem", "Cyl", Vector3.new(0.35, 0.2, 0.2), CFrame.new(0.5, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90)), WHITE)
		end },
		{ Name = "Mint Candy", Color = Color3.fromRGB(190, 250, 220), Design = function(add)
			for i = 0, 7 do
				eggMeridian(add, i / 8 * math.pi * 2, 0.34, WHITE, nil, "CandyStripe")
			end
			ring(add, 1.05, Color3.fromRGB(255, 240, 245), nil, 0.4)
			for i = 0, 5 do
				add("Drip", "Blob", Vector3.new(0.3, 0.55, 0.2), surface(i / 6 * math.pi * 2 + 0.3, 0.8, 1.0), Color3.fromRGB(255, 240, 245))
			end
		end },
	},
	Rare = {
		{ Name = "Ocean", Color = Color3.fromRGB(70, 150, 230), Design = function(add)
			eggZigzag(add, -0.4, Color3.fromRGB(180, 230, 255))
			eggZigzag(add, 0.4, Color3.fromRGB(130, 200, 255))
			for i = 1, 6 do
				add("Bubble", "Ball", Vector3.one * (0.18 + (i % 3) * 0.08), CFrame.new(math.cos(i) * 1.4, 1.2 + i * 0.25, math.sin(i) * 1.2), Color3.fromRGB(210, 240, 255), Enum.Material.Glass).Transparency = 0.3
			end
		end },
		{ Name = "Frost", Color = Color3.fromRGB(190, 225, 255), Design = function(add)
			add("SnowCap", "Blob", Vector3.new(2.3, 1.1, 2.3), CFrame.new(0, 1.45, 0), WHITE)
			for i = 0, 9 do
				local len = 0.4 + (i % 3) * 0.25
				add("Icicle", "Block", Vector3.new(0.18, len, 0.18), surface(i / 10 * math.pi * 2, 0.95 - len / 2, 1.0), Color3.fromRGB(210, 240, 255), Enum.Material.Glass)
			end
			eggStar(add, surface(0, -0.3, 1.0), 0.5, WHITE, Enum.Material.Neon)
			eggStar(add, surface(math.pi, -0.3, 1.0), 0.5, WHITE, Enum.Material.Neon)
		end },
		{ Name = "Swirl", Color = Color3.fromRGB(100, 140, 255), Design = function(add)
			for i = 0, 23 do
				add("Swirl", "Ball", Vector3.one * 0.28, surface(i * 0.55, 1.5 - i * 0.13, 1.0), if i % 2 == 0 then WHITE else Color3.fromRGB(255, 230, 120), if i % 4 == 0 then Enum.Material.Neon else nil)
			end
		end },
	},
	Epic = {
		{ Name = "Spiked", Color = Color3.fromRGB(110, 50, 170), Design = function(add)
			eggSpikes(add, 0.5, 8, 0.8, Color3.fromRGB(230, 160, 255), Enum.Material.Neon)
			eggSpikes(add, -0.5, 8, 0.6, Color3.fromRGB(180, 110, 240), nil, 0.4)
			add("TopSpike", "Block", Vector3.new(0.35, 1, 0.35), CFrame.new(0, 2.1, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(240, 190, 255), Enum.Material.Neon)
		end },
		{ Name = "Lightning", Color = Color3.fromRGB(60, 50, 110), Design = function(add)
			for i = 0, 3 do
				local a = i / 4 * math.pi * 2
				for k, off in ipairs({ { 0.6, 20 }, { 0.15, -25 }, { -0.3, 20 }, { -0.75, -25 } }) do
					add("Bolt", "Block", Vector3.new(0.22, 0.6, 0.14), surface(a + (k % 2) * 0.12, off[1], 1.0) * CFrame.Angles(0, 0, math.rad(off[2])), Color3.fromRGB(255, 240, 90), Enum.Material.Neon)
				end
			end
			for i = 1, 4 do
				add("Cloud", "Ball", Vector3.one * 0.7, CFrame.new(math.cos(i * 1.6) * 0.6, 1.75, math.sin(i * 1.6) * 0.6), Color3.fromRGB(150, 150, 180))
			end
		end },
		{ Name = "Geode", Color = Color3.fromRGB(120, 100, 110), Design = function(add)
			add("GeodeHole", "Blob", Vector3.new(1.7, 1.9, 0.6), CFrame.new(0, 0, -1.2), Color3.fromRGB(60, 30, 80))
			for i = 0, 8 do
				local a = i / 9 * math.pi * 2
				add("Crystal", "Block", Vector3.new(0.22, 0.6, 0.22), CFrame.new(math.cos(a) * 0.55, math.sin(a) * 0.65, -1.35) * CFrame.Angles(math.rad(-60), 0, a), Color3.fromRGB(210, 150, 255), Enum.Material.Neon)
			end
			eggDots(add, 10, 0.3, { Color3.fromRGB(90, 80, 90) }, nil, 5)
		end },
	},
	Legendary = {
		{ Name = "Sunburst", Color = Color3.fromRGB(255, 170, 40), Material = Enum.Material.Foil, Design = function(add)
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				add("Ray", "Block", Vector3.new(0.2, 0.2, if i % 2 == 0 then 1.1 else 0.7), surface(a, 0, 0.95) * CFrame.new(0, 0, 0.45), Color3.fromRGB(255, 240, 120), Enum.Material.Neon)
			end
			add("SunCore", "Ball", Vector3.one * 0.8, CFrame.new(0, 2.05, 0), Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
		end },
		{ Name = "Dragon", Color = Color3.fromRGB(200, 60, 40), Design = function(add)
			for row = 0, 4 do
				for i = 0, 9 do
					add("Scale", "Blob", Vector3.new(0.5, 0.4, 0.12), surface(i / 10 * math.pi * 2 + row * 0.3, -1.1 + row * 0.5, 1.0), Color3.fromRGB(255, 180, 60):Lerp(Color3.fromRGB(200, 60, 40), row / 5))
				end
			end
			for _, sx in ipairs({ -1, 1 }) do
				add("Horn", "Blob", Vector3.new(0.3, 0.9, 0.3), CFrame.new(sx * 0.45, 1.9, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx)), Color3.fromRGB(255, 235, 190))
			end
		end },
		{ Name = "Treasure", Color = Color3.fromRGB(150, 90, 50), Material = Enum.Material.Wood, Design = function(add)
			ring(add, 0.7, GOLD, Enum.Material.Metal, 0.3)
			ring(add, -0.7, GOLD, Enum.Material.Metal, 0.3)
			for i = 0, 9 do
				add("Coin", "Cyl", Vector3.new(0.08, 0.45, 0.45), surface(i / 10 * math.pi * 2, 0, 1.0) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
			end
			add("Lock", "Block", Vector3.new(0.5, 0.6, 0.2), surface(-math.pi / 2, 0.1, 1.02), GOLD, Enum.Material.Metal)
		end },
	},
	Mythic = {
		{ Name = "Inferno", Color = Color3.fromRGB(40, 20, 20), Design = function(add)
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				add("LavaCrack", "Block", Vector3.new(0.14, 0.9, 0.12), surface(a, ((i * 7) % 5) / 5 - 0.5, 1.0) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 25 else -25)), Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
				add("Flame", "Blob", Vector3.new(0.5, 1.1, 0.3), surface(a, -1.3, 1.02) * CFrame.new(0, 0.35, 0), if i % 2 == 0 then Color3.fromRGB(255, 140, 30) else Color3.fromRGB(255, 220, 80), Enum.Material.Neon)
			end
		end },
		{ Name = "Nebula", Color = Color3.fromRGB(30, 20, 70), Design = function(add)
			for i = 0, 29 do
				local cols = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(110, 140, 255), Color3.fromRGB(170, 90, 255) }
				add("NebulaCloud", "Blob", Vector3.new(0.6, 0.35, 0.1), surface(i * 0.62, 1.4 - i * 0.095, 1.0) * CFrame.Angles(0, 0, i * 0.4), cols[(i % 3) + 1], Enum.Material.Neon).Transparency = 0.25
			end
			eggDots(add, 12, 0.14, { WHITE }, Enum.Material.Neon, 2)
		end },
		{ Name = "Moon", Color = Color3.fromRGB(200, 205, 225), Design = function(add)
			for i = 1, 9 do
				local size = 0.35 + (i % 3) * 0.2
				add("Crater", "Cyl", Vector3.new(0.1, size, size), surface(i * 2.3, ((i * 13) % 24) / 10 - 1.2, 1.0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 155, 180))
			end
			local tilt = CFrame.Angles(math.rad(20), 0, math.rad(-15))
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				add("Orbit", "Ball", Vector3.one * 0.22, tilt * CFrame.new(math.cos(a) * 2.3, 0, math.sin(a) * 2.3), Color3.fromRGB(200, 220, 255), Enum.Material.Neon)
			end
		end },
	},
	Divine = {
		{ Name = "Seraph", Color = Color3.fromRGB(255, 250, 235), Material = Enum.Material.Glass, Design = function(add)
			eggWings(add, 4, WHITE, Enum.Material.Neon, 0.3)
			for _, y in ipairs({ 1.3, -1.2 }) do
				for _, sx in ipairs({ -1, 1 }) do
					add("SmallWing", "Blob", Vector3.new(0.16, 0.4, 0.9), CFrame.new(sx * 1.25, y, 0.2) * CFrame.Angles(0, 0, math.rad(-30 * sx)), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
				end
			end
			add("Halo", "Cyl", Vector3.new(0.16, 1.9, 1.9), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon)
		end },
		{ Name = "Holy Crystal", Color = Color3.fromRGB(255, 245, 200), Material = Enum.Material.Glass, Design = function(add)
			for i = 0, 7 do
				eggMeridian(add, i / 8 * math.pi * 2, 0.14, GOLD, Enum.Material.Neon, "Ray")
			end
			add("Core", "Ball", Vector3.one * 1.1, CFrame.new(), Color3.fromRGB(255, 255, 230), Enum.Material.Neon)
			add("Halo", "Cyl", Vector3.new(0.14, 1.7, 1.7), CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon)
		end },
		{ Name = "Cloud", Color = Color3.fromRGB(255, 250, 255), Design = function(add)
			for i = 0, 9 do
				local a = i / 10 * math.pi * 2
				add("Cloud", "Ball", Vector3.one * (0.9 + (i % 2) * 0.3), CFrame.new(math.cos(a) * 1.5, -1.35 + (i % 2) * 0.15, math.sin(a) * 1.5), WHITE)
			end
			ring(add, 0.3, GOLD, Enum.Material.Neon, 0.16)
			eggWings(add, 3, Color3.fromRGB(255, 245, 210), Enum.Material.Neon)
		end },
	},
	Secret = {
		{ Name = "Void", Color = Color3.fromRGB(8, 5, 15), Design = function(add)
			local tilt = CFrame.Angles(math.rad(70), 0, math.rad(10))
			for i = 0, 23 do
				local a = i / 24 * math.pi * 2
				add("Accretion", "Ball", Vector3.one * (0.26 + (i % 3) * 0.06), tilt * CFrame.new(math.cos(a) * 2.2, 0, math.sin(a) * 2.2), if i % 2 == 0 then Color3.fromRGB(170, 80, 255) else Color3.fromRGB(255, 140, 60), Enum.Material.Neon)
			end
			eggDots(add, 10, 0.12, { WHITE }, Enum.Material.Neon, 7)
		end },
		{ Name = "Error", Color = Color3.fromRGB(30, 5, 10), Design = function(add)
			for i = 1, 18 do
				add("ErrorBlock", "Block", Vector3.new(0.4, 0.24, 0.2), surface(i * 1.7, ((i * 31) % 30) / 10 - 1.5, 1.02), if i % 3 == 0 then WHITE else Color3.fromRGB(255, 40, 60), Enum.Material.Neon)
			end
			eggSymbol(add, "!", 0.5, Color3.fromRGB(255, 60, 70), BLACK)
		end },
		{ Name = "Prism", Color = Color3.fromRGB(245, 245, 255), Material = Enum.Material.Glass, Design = function(add)
			local rainbow = { Color3.fromRGB(255, 70, 90), Color3.fromRGB(255, 180, 50), Color3.fromRGB(255, 240, 80), Color3.fromRGB(80, 230, 120), Color3.fromRGB(70, 170, 255), Color3.fromRGB(190, 100, 255) }
			for i, col in ipairs(rainbow) do
				ring(add, 1.25 - i * 0.42, col, Enum.Material.Neon, 0.22)
			end
			eggSymbol(add, "?", 0.9, WHITE, BLACK)
		end },
	},
}

-- Two more designs per rarity
local function addVariant(rarityId, v)
	table.insert(EGG_VARIANTS[rarityId], v)
end

EGG_VARIANTS.Astral = {}
EGG_VARIANTS.Cosmic = {}
EGG_VARIANTS.Omega = {}
addVariant("Astral", { Name = "Moonstone", Color = Color3.fromRGB(220, 230, 255), Material = Enum.Material.Glass, Design = function(add)
	eggDots(add, 10, 0.3, { Color3.fromRGB(255, 250, 220) }, Enum.Material.Neon, 3)
	ring(add, -0.4, Color3.fromRGB(180, 200, 255), Enum.Material.Neon, 0.12)
end })
addVariant("Astral", { Name = "Constellation", Color = Color3.fromRGB(25, 40, 90), Design = function(add)
	eggDots(add, 24, 0.14, { WHITE, Color3.fromRGB(160, 220, 255) }, Enum.Material.Neon, 17)
	eggMeridian(add, 0.4, 0.06, Color3.fromRGB(160, 220, 255), Enum.Material.Neon)
	eggMeridian(add, 2.2, 0.06, Color3.fromRGB(160, 220, 255), Enum.Material.Neon)
end })
addVariant("Cosmic", { Name = "Nebula", Color = Color3.fromRGB(90, 40, 140), Design = function(add)
	eggDots(add, 30, 0.2, { Color3.fromRGB(255, 120, 220), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 255, 255) }, Enum.Material.Neon, 11)
end })
addVariant("Cosmic", { Name = "Wormhole", Color = Color3.fromRGB(10, 5, 25), Design = function(add)
	for i = 0, 5 do
		ring(add, -1.2 + i * 0.5, Color3.fromRGB(150 + i * 15, 90, 255), Enum.Material.Neon, 0.1)
	end
end })
addVariant("Omega", { Name = "Inferno", Color = Color3.fromRGB(90, 10, 5), Design = function(add)
	eggDots(add, 20, 0.22, { Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 220, 80) }, Enum.Material.Neon, 9)
	ring(add, 0.3, Color3.fromRGB(255, 90, 30), Enum.Material.Neon, 0.2)
end })
addVariant("Omega", { Name = "Final Form", Color = Color3.fromRGB(245, 240, 250), Material = Enum.Material.Glass, Design = function(add)
	for i = 0, 3 do
		eggMeridian(add, i * math.pi / 2, 0.1, Color3.fromRGB(255, 60, 90), Enum.Material.Neon)
	end
	ring(add, 0, Color3.fromRGB(255, 205, 60), Enum.Material.Metal, 0.24)
	eggWings(add, 4, Color3.fromRGB(255, 220, 230), Enum.Material.Neon)
end })

local SPRINKLES = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(255, 220, 70), Color3.fromRGB(110, 220, 255), Color3.fromRGB(140, 230, 120), Color3.fromRGB(190, 130, 255) }
addVariant("Common", { Name = "Sprinkle", Color = Color3.fromRGB(255, 245, 240), Design = function(add)
	for i = 1, 26 do
		add("Sprinkle", "Block", Vector3.new(0.14, 0.14, 0.45), surface(i * 2.39996, ((i * 37) % 30) / 10 - 1.5, 1.0) * CFrame.Angles(0, 0, i), SPRINKLES[(i % #SPRINKLES) + 1])
	end
end })
addVariant("Common", { Name = "Cloudy", Color = Color3.fromRGB(150, 205, 255), Design = function(add)
	for i = 0, 5 do
		local cf = surface(i / 6 * math.pi * 2, if i % 2 == 0 then 0.5 else -0.5, 0.98)
		for k = -1, 1 do
			add("Cloud", "Ball", Vector3.one * (0.45 + (k == 0 and 0.15 or 0)), cf * CFrame.new(k * 0.3, k == 0 and 0.08 or 0, 0), WHITE)
		end
	end
	add("Sun", "Ball", Vector3.one * 0.6, CFrame.new(0, 1.72, 0), Color3.fromRGB(255, 220, 80), Enum.Material.Neon)
end })
addVariant("Uncommon", { Name = "Ladybug", Color = Color3.fromRGB(220, 50, 50), Design = function(add)
	eggMeridian(add, math.pi / 2, 0.16, BLACK, nil, "Stripe")
	eggMeridian(add, -math.pi / 2, 0.16, BLACK, nil, "Stripe")
	eggDots(add, 12, 0.5, { BLACK }, nil, 4)
	add("Head", "Blob", Vector3.new(1.4, 0.6, 1.4), CFrame.new(0, 1.7, 0), BLACK)
	for _, sx in ipairs({ -1, 1 }) do
		add("Antenna", "Block", Vector3.new(0.08, 0.8, 0.08), CFrame.new(sx * 0.3, 2.2, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx)), BLACK)
		add("AntennaTip", "Ball", Vector3.one * 0.22, CFrame.new(sx * 0.5, 2.6, 0), BLACK)
	end
end })
addVariant("Uncommon", { Name = "Bamboo", Color = Color3.fromRGB(150, 205, 110), Design = function(add)
	for _, y in ipairs({ -1, -0.3, 0.4, 1.1 }) do
		ring(add, y, Color3.fromRGB(110, 170, 80), nil, 0.16)
	end
	for i = 0, 3 do
		add("Leaf", "Blob", Vector3.new(0.3, 0.9, 0.12), surface(i * 1.6, 0.8 - i * 0.4, 1.02) * CFrame.Angles(0, 0, math.rad(40)), Color3.fromRGB(80, 160, 70))
	end
end })
addVariant("Rare", { Name = "Seashell", Color = Color3.fromRGB(255, 205, 190), Design = function(add)
	for i = 0, 9 do
		eggMeridian(add, i / 10 * math.pi * 2, 0.22, Color3.fromRGB(240, 170, 160), nil, "Ridge")
	end
	local pearl = add("Pearl", "Ball", Vector3.one * 0.7, CFrame.new(0, 1.8, 0), Color3.fromRGB(250, 245, 255), Enum.Material.Neon)
	pearl.Transparency = 0.1
end })
addVariant("Rare", { Name = "Honeycomb", Color = Color3.fromRGB(255, 190, 60), Design = function(add)
	for row = 0, 5 do
		for i = 0, 7 do
			add("Cell", "Cyl", Vector3.new(0.1, 0.42, 0.42), surface(i / 8 * math.pi * 2 + (row % 2) * 0.39, -1.25 + row * 0.5, 1.0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 140, 30))
		end
	end
	add("Drip", "Blob", Vector3.new(0.5, 0.9, 0.3), surface(0.5, 0.9, 1.02), Color3.fromRGB(255, 170, 40), Enum.Material.Glass)
end })
addVariant("Epic", { Name = "Circuit", Color = Color3.fromRGB(25, 30, 45), Design = function(add)
	local cyan = Color3.fromRGB(60, 240, 255)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("Trace", "Block", Vector3.new(0.08, 1.4, 0.08), surface(a, 0.2 - (i % 2) * 0.6, 1.0), cyan, Enum.Material.Neon)
		add("Trace", "Block", Vector3.new(0.5, 0.08, 0.08), surface(a + 0.18, 0.9 - (i % 2) * 1.4, 1.0), cyan, Enum.Material.Neon)
		add("Chip", "Block", Vector3.new(0.28, 0.28, 0.1), surface(a, 0.9 - (i % 2) * 1.4, 1.01), Color3.fromRGB(255, 80, 200), Enum.Material.Neon)
	end
end })
addVariant("Epic", { Name = "Toadstool", Color = Color3.fromRGB(245, 235, 215), Design = function(add)
	add("Cap", "Blob", Vector3.new(3.4, 1.8, 3.4), CFrame.new(0, 1.2, 0), Color3.fromRGB(220, 40, 60))
	for i = 0, 6 do
		add("CapDot", "Blob", Vector3.new(0.5, 0.2, 0.5), CFrame.new(math.cos(i) * 1.1, 1.95 - (i % 2) * 0.25, math.sin(i) * 1.1), WHITE)
	end
	eggDots(add, 6, 0.3, { Color3.fromRGB(190, 170, 140) }, nil, 9)
end })
addVariant("Legendary", { Name = "Crown Jewel", Color = Color3.fromRGB(110, 50, 180), Design = function(add)
	ring(add, 1.15, GOLD, Enum.Material.Metal, 0.3)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("CrownPoint", "Block", Vector3.new(0.3, 0.7, 0.3), CFrame.new(math.cos(a) * 0.95, 1.65, math.sin(a) * 0.95) * CFrame.Angles(0, -a, math.rad(-15)), GOLD, Enum.Material.Metal)
		add("Gem", "Ball", Vector3.one * 0.3, surface(a, -0.2, 1.03), ({ Color3.fromRGB(255, 60, 90), Color3.fromRGB(80, 170, 255), Color3.fromRGB(80, 230, 120) })[(i % 3) + 1], Enum.Material.Neon)
	end
end })
addVariant("Legendary", { Name = "Sun Temple", Color = Color3.fromRGB(230, 195, 130), Design = function(add)
	for _, y in ipairs({ -0.9, 0, 0.9 }) do
		ring(add, y, Color3.fromRGB(190, 150, 90), Enum.Material.Sandstone, 0.22)
	end
	for side = 0, 1 do
		local cf = surface(side * math.pi, 0.45, 1.02)
		add("Eye", "Blob", Vector3.new(0.8, 0.4, 0.1), cf, GOLD, Enum.Material.Neon)
		add("Pupil", "Ball", Vector3.one * 0.26, cf * CFrame.new(0, 0, 0.05), Color3.fromRGB(40, 90, 110))
	end
end })
addVariant("Mythic", { Name = "Aurora", Color = Color3.fromRGB(15, 35, 50), Design = function(add)
	local cols = { Color3.fromRGB(90, 255, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(190, 120, 255) }
	for band = 0, 2 do
		for i = 0, 11 do
			add("AuroraBand", "Block", Vector3.new(0.5, 0.3, 0.1), surface(i / 12 * math.pi * 2, 0.8 - band * 0.45 + math.sin(i + band) * 0.15, 1.0), cols[band + 1], Enum.Material.Neon)
		end
	end
	eggDots(add, 10, 0.12, { WHITE }, Enum.Material.Neon, 11)
end })
addVariant("Mythic", { Name = "Clockwork", Color = Color3.fromRGB(180, 130, 60), Design = function(add)
	for i = 0, 4 do
		local cf = surface(i * 1.25, 0.9 - i * 0.45, 1.0)
		add("Gear", "Cyl", Vector3.new(0.12, 0.8, 0.8), cf * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(230, 190, 90), Enum.Material.Metal)
		for k = 0, 5 do
			add("Tooth", "Block", Vector3.new(0.16, 0.16, 0.14), cf * CFrame.Angles(0, 0, k / 6 * math.pi * 2) * CFrame.new(0, 0.45, 0), Color3.fromRGB(230, 190, 90), Enum.Material.Metal)
		end
	end
	add("Key", "Block", Vector3.new(0.2, 0.9, 0.2), CFrame.new(0, 2.1, 0), GOLD, Enum.Material.Metal)
end })
addVariant("Divine", { Name = "Angel Feather", Color = Color3.fromRGB(255, 252, 245), Design = function(add)
	for row = 0, 3 do
		for i = 0, 7 do
			add("Feather", "Blob", Vector3.new(0.5, 0.9, 0.12), surface(i / 8 * math.pi * 2 + row * 0.3, 1.0 - row * 0.65, 1.02) * CFrame.Angles(math.rad(-20), 0, 0), if row % 2 == 0 then WHITE else Color3.fromRGB(255, 240, 210))
		end
	end
	add("Halo", "Cyl", Vector3.new(0.14, 1.8, 1.8), CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon)
end })
addVariant("Divine", { Name = "Sunrise", Color = Color3.fromRGB(255, 200, 120), Design = function(add)
	ring(add, -0.7, Color3.fromRGB(255, 150, 90), Enum.Material.Neon, 0.3)
	ring(add, 0, Color3.fromRGB(255, 190, 110), Enum.Material.Neon, 0.24)
	ring(add, 0.7, Color3.fromRGB(255, 235, 170), Enum.Material.Neon, 0.18)
	for i = 0, 9 do
		add("Ray", "Block", Vector3.new(0.14, 0.14, 1.1), surface(i / 10 * math.pi * 2, 1.2, 0.95) * CFrame.new(0, 0.2, 0.4), GOLD, Enum.Material.Neon)
	end
end })
addVariant("Secret", { Name = "Static", Color = Color3.fromRGB(120, 120, 125), Design = function(add)
	for i = 1, 40 do
		local g = ((i * 53) % 255)
		add("Noise", "Block", Vector3.new(0.3, 0.2, 0.12), surface(i * 2.1, ((i * 29) % 32) / 10 - 1.6, 1.0), Color3.fromRGB(g, g, g))
	end
	ring(add, 0.3, WHITE, Enum.Material.Neon, 0.08)
	eggSymbol(add, "?", -0.2, WHITE, BLACK)
end })
addVariant("Secret", { Name = "Void Eye", Color = Color3.fromRGB(10, 5, 20), Design = function(add)
	for side = 0, 1 do
		local cf = surface(side * math.pi, 0.2, 1.01)
		add("EyeWhite", "Blob", Vector3.new(1.6, 1.1, 0.14), cf, Color3.fromRGB(255, 240, 250), Enum.Material.Neon)
		add("Iris", "Ball", Vector3.one * 0.8, cf * CFrame.new(0, 0, 0.05), Color3.fromRGB(190, 60, 255), Enum.Material.Neon)
		add("Pupil", "Blob", Vector3.new(0.2, 0.7, 0.2), cf * CFrame.new(0, 0, 0.1), BLACK)
	end
	eggDots(add, 12, 0.14, { Color3.fromRGB(190, 60, 255) }, Enum.Material.Neon, 13)
end })

-- Cracks spread over an egg as it gets close to hatching (stage 1 and 2)
function Visuals.CrackEgg(egg, stage, glowColor)
	if egg:FindFirstChild("CrackStage" .. stage) then
		return
	end
	local marker = Instance.new("BoolValue")
	marker.Name = "CrackStage" .. stage
	marker.Parent = egg
	-- cracks are laid out for a normal egg, then scaled to this egg's size
	local s = egg:GetAttribute("EggScale") or 1
	local raw = rigger(egg, egg)
	local function add(name, shape, size, offset, color, material)
		return raw(name, shape, size * s, CFrame.new(offset.Position * s) * (offset - offset.Position), color, material)
	end
	local crack = Color3.fromRGB(45, 35, 30)
	local count = if stage == 1 then 3 else 6
	for i = 1, count do
		local a = i * 2.2 + stage
		local y = 0.9 - ((i * 7) % 5) * 0.35
		for k = 0, 2 do
			add("Crack", "Block", Vector3.new(0.1, 0.5, 0.06), surface(a + k * 0.14, y - k * 0.25, 1.01) * CFrame.Angles(0, 0, math.rad(if k % 2 == 0 then 30 else -30)), if stage == 2 and k == 1 then glowColor or WHITE else crack, if stage == 2 and k == 1 then Enum.Material.Neon else nil)
		end
	end
end

-- Hatch progress bar under an egg's label (fraction nil hides it)
function Visuals.SetProgress(part, fraction, color)
	local bb = part:FindFirstChild("Label")
	if not bb then
		return
	end
	local bar = bb:FindFirstChild("Progress")
	if fraction == nil then
		if bar then
			bar.Visible = false
		end
		return
	end
	if not bar then
		bb.Size = UDim2.fromOffset(bb:GetAttribute("Width") or 190, 72)
		bar = Instance.new("Frame")
		bar.Name = "Progress"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, 0)
		bar.Size = UDim2.new(0.7, 0, 0, 9)
		bar.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
		bar.BackgroundTransparency = 0.2
		bar.Parent = bb
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = bar
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		local c2 = c:Clone()
		c2.Parent = fill
		bb.Pill.Size = UDim2.new(1, 0, 1, -14)
		bb.Pill.Position = UDim2.new(0.5, 0, 0.5, -7)
	end
	bar.Visible = true
	bar.Fill.BackgroundColor3 = color or WHITE
	bar.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

-- Scale a finished egg (and all its decorations, label and lights) by `factor`
-- around its center. Used so bigger pets come in bigger eggs.
function Visuals.ScaleEgg(egg, factor)
	if not factor or math.abs(factor - 1) < 0.01 then
		return
	end
	local center = egg.CFrame
	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = center:ToObjectSpace(d.CFrame)
			d.Size *= factor
			d.CFrame = center * CFrame.new(rel.Position * factor) * (rel - rel.Position)
		elseif d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh then
			d.Scale *= factor
		elseif d:IsA("BillboardGui") then
			d.StudsOffset *= factor
		elseif d:IsA("PointLight") then
			d.Range *= factor
		end
	end
	egg.Size *= factor
	egg:SetAttribute("EggScale", factor)
end

-- Names of every design an egg of this rarity can have (Classic first)
function Visuals.EggVariantNames(rarityId)
	local names = { "Classic" }
	for _, v in ipairs(EGG_VARIANTS[rarityId] or {}) do
		table.insert(names, v.Name)
	end
	return names
end

-- variantName is optional; by default the egg picks a random design.
function Visuals.MakeEgg(rarityId, variantName)
	local rarity = Config.RarityById[rarityId]
	local variants = EGG_VARIANTS[rarityId] or {}
	local variant = nil
	if variantName then
		for _, v in ipairs(variants) do
			if v.Name == variantName then
				variant = v
			end
		end
	elseif math.random(1, #variants + 1) > 1 then
		variant = variants[math.random(1, #variants)]
	end
	local baseColor = rarity.Color
	if rarityId == "Common" then
		baseColor = Color3.fromRGB(250, 240, 220)
	elseif rarityId == "Legendary" then
		baseColor = Color3.fromRGB(255, 200, 60)
	elseif rarityId == "Mythic" then
		baseColor = Color3.fromRGB(45, 25, 80)
	elseif rarityId == "Divine" then
		baseColor = Color3.fromRGB(255, 250, 240)
	elseif rarityId == "Secret" then
		baseColor = Color3.fromRGB(20, 20, 26)
	elseif rarityId == "Astral" then
		baseColor = Color3.fromRGB(200, 235, 255)
	elseif rarityId == "Cosmic" then
		baseColor = Color3.fromRGB(45, 20, 80)
	elseif rarityId == "Omega" then
		baseColor = Color3.fromRGB(40, 5, 12)
	end
	local egg = newPart(rarityId .. "Egg", "Blob", EGG_SIZE, baseColor)
	egg.Anchored = true
	egg.Massless = false
	egg.CastShadow = true
	if rarityId == "Legendary" then
		egg.Material = Enum.Material.Foil
		egg.Reflectance = 0.1
	elseif rarityId == "Divine" then
		egg.Material = Enum.Material.Glass
		egg.Reflectance = 0.2
	end

	if variant then
		baseColor = variant.Color
		egg.Color = baseColor
		egg.Material = variant.Material or Enum.Material.SmoothPlastic
		egg.Reflectance = if variant.Material == Enum.Material.Glass then 0.2 else 0
	end
	egg:SetAttribute("EggVariant", if variant then variant.Name else "Classic")

	local add = rigger(egg, egg)
	local dark = baseColor:Lerp(Color3.new(0, 0, 0), 0.35)
	local design = if variant then variant.Design else EGG_DESIGNS[rarityId]
	if design then
		design(add, baseColor, dark)
	end
	-- extra detail on every egg: natural speckles, a soft light band near the
	-- top, a metal band for rarer eggs and a glowing gem on the tip
	eggDots(add, 14, 0.13, { baseColor:Lerp(Color3.new(0, 0, 0), 0.25), baseColor:Lerp(Color3.new(1, 1, 1), 0.3) }, nil, #rarityId * 7)
	ring(add, 1.15, baseColor:Lerp(Color3.new(1, 1, 1), 0.55), nil, 0.08)
	if rarity.Order >= 3 then
		ring(add, -0.05, if rarity.Order >= 5 then GOLD else Color3.fromRGB(215, 220, 230), Enum.Material.Metal, 0.1)
	end
	if rarity.Order >= 4 then
		add("TipGem", "Block", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, EGG_SIZE.Y / 2 - 0.02, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Neon)
	end
	-- cartoon shine on every egg
	add("Shine", "Blob", Vector3.new(0.5, 0.95, 0.25), CFrame.new(-0.62, 0.95, -1.1) * CFrame.Angles(0, 0, math.rad(-20)), WHITE, Enum.Material.Neon)
	add("Shine", "Ball", Vector3.one * 0.28, CFrame.new(-0.32, 1.55, -0.88), WHITE, Enum.Material.Neon)

	if rarity.Order >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 8 + rarity.Order * 2
		light.Brightness = 1.4 + rarity.Order * 0.2
		light.Parent = egg
	end
	if rarity.Order >= 4 then
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(rarity.Color:Lerp(WHITE, 0.3))
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.4, 0)
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Rate = 4 + rarity.Order * 3
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = egg
	end

	Visuals.AddLabel(egg, 3.6)
	return egg
end

--------------------------------------------------------------------------------
-- Pets: round cartoon body + species features
--------------------------------------------------------------------------------
local PET_FEATURES = {}

-- How each species stands: 4 legs, 2 bird feet, 2 stubby feet, floating, or none
local BODY_PLANS = {
	Pup = "Walker", Cat = "Walker", Fox = "Walker", Stag = "Walker", Unicorn = "Walker", Kitsune = "Walker",
	Panda = "Walker", Cub = "Walker", Hamster = "Walker", Bunny = "Walker", Newt = "Walker", Axolotl = "Walker",
	Drake = "Walker", Turtle = "Walker", GlitchCat = "Walker", GlitchBunny = "Walker", Frog = "None",
	Monkey = "Biped", Dino = "Biped", Moss = "Biped", Mushroom = "Biped",
	Bird = "Bird", Chick = "Bird", Duck = "Bird", Owl = "Bird", Phoenix = "Bird", Penguin = "Bird",
	Fish = "Float", Koi = "Float", Jelly = "Float", Kraken = "Float", Serpent = "Float", Moth = "Float", Bat = "Float",
	Slime = "None",
}
-- Species whose eyes sit a little differently
local FUR = { Pup = true, Cat = true, Fox = true, Cub = true, Hamster = true, Bunny = true, Panda = true, Kitsune = true, Monkey = true, Stag = true, Unicorn = true, GlitchCat = true, GlitchBunny = true }

-- Isosceles triangle facing -Z (ears, horns, spikes, teeth); cf is its center
local function triangle(add, name, w, h, t, cf, color, material)
	add(name, "Wedge", Vector3.new(t, h, w / 2), cf * CFrame.new(-w / 4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), color, material)
	add(name, "Wedge", Vector3.new(t, h, w / 2), cf * CFrame.new(w / 4, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), color, material)
end

-- Two-part beak pointing forward (-Z); cf is the middle of the beak
local function beak(add, len, wid, cf, color)
	add("Beak", "Wedge", Vector3.new(wid, len * 0.34, len), cf * CFrame.new(0, len * 0.17, 0), color)
	add("Beak", "Wedge", Vector3.new(wid * 0.9, len * 0.22, len * 0.8), cf * CFrame.new(0, -len * 0.11, len * 0.1) * CFrame.Angles(0, 0, math.pi), color:Lerp(BLACK, 0.12))
end

-- Pointy ear with a pink inside, tilted outward
local function pointyEar(add, S, sx, x, y, w, h, outer, inner)
	local cf = CFrame.new(sx * x, y, -S * 0.02) * CFrame.Angles(0, 0, math.rad(-18 * sx))
	triangle(add, "Ear", w, h, S * 0.1, cf, outer)
	triangle(add, "InnerEar", w * 0.55, h * 0.6, S * 0.04, cf * CFrame.new(0, -h * 0.12, -S * 0.06), inner or BLUSH)
end

local function tuft(add, S, color)
	for i = -1, 1 do
		add("Tuft", "Blob", Vector3.new(S * 0.12, S * 0.24, S * 0.12), CFrame.new(i * S * 0.07, S * 0.5, -S * 0.12) * CFrame.Angles(math.rad(-15), 0, math.rad(-i * 30)), color)
	end
end

local function stripes(add, S, color, count)
	for i = 1, count do
		local z = -0.1 + i * 0.13
		add("Stripe", "Blob", Vector3.new(S * 0.9, S * 0.08, S * 0.12), CFrame.new(0, S * 0.36 - i * S * 0.02, S * z) * CFrame.Angles(math.rad(-20 - i * 12), 0, 0), color)
	end
end

function PET_FEATURES.Pup(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Blob", Vector3.new(S * 0.26, S * 0.5, S * 0.16), CFrame.new(sx * S * 0.43, S * 0.14, -S * 0.02) * CFrame.Angles(0, 0, math.rad(18 * sx)), dark)
		add("EarTip", "Blob", Vector3.new(S * 0.2, S * 0.16, S * 0.12), CFrame.new(sx * S * 0.5, -S * 0.08, -S * 0.02), dark:Lerp(BLACK, 0.2))
	end
	add("Snout", "Blob", Vector3.new(S * 0.4, S * 0.28, S * 0.28), CFrame.new(0, -S * 0.1, -S * 0.44), c:Lerp(WHITE, 0.45))
	add("Nose", "Blob", Vector3.new(S * 0.15, S * 0.1, S * 0.1), CFrame.new(0, -S * 0.02, -S * 0.58), BLACK)
	add("NoseShine", "Ball", Vector3.one * S * 0.04, CFrame.new(S * 0.03, 0, -S * 0.63), WHITE)
	add("Tail", "Blob", Vector3.new(S * 0.16, S * 0.38, S * 0.16), CFrame.new(0, S * 0.2, S * 0.5) * CFrame.Angles(math.rad(-35), 0, 0), dark)
	add("Spot", "Blob", Vector3.new(S * 0.32, S * 0.28, S * 0.1), CFrame.new(S * 0.24, S * 0.28, -S * 0.36), dark)
	add("Collar", "Cyl", Vector3.new(S * 0.1, S * 0.86, S * 0.86), CFrame.new(0, -S * 0.26, -S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 60, 70))
	add("Tag", "Cyl", Vector3.new(S * 0.03, S * 0.14, S * 0.14), CFrame.new(0, -S * 0.36, -S * 0.43) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
end

function PET_FEATURES.Moss(add, S)
	local leaf = Color3.fromRGB(90, 190, 70)
	add("Stem", "Block", Vector3.new(S * 0.06, S * 0.3, S * 0.06), CFrame.new(0, S * 0.6, 0), Color3.fromRGB(70, 130, 50))
	for _, sx in ipairs({ -1, 1 }) do
		add("Leaf", "Blob", Vector3.new(S * 0.44, S * 0.1, S * 0.22), CFrame.new(sx * S * 0.21, S * 0.74, 0) * CFrame.Angles(0, 0, math.rad(25 * sx)), leaf)
		add("LeafVein", "Block", Vector3.new(S * 0.3, S * 0.02, S * 0.02), CFrame.new(sx * S * 0.21, S * 0.79, 0) * CFrame.Angles(0, 0, math.rad(25 * sx)), leaf:Lerp(WHITE, 0.4))
	end
	for i = 1, 7 do
		local a = i * 0.9
		add("MossTuft", "Ball", Vector3.one * S * (0.16 + (i % 3) * 0.03), CFrame.new(math.cos(a) * S * 0.38, S * 0.28 + (i % 2) * S * 0.05, math.sin(a) * S * 0.3 + S * 0.12), leaf:Lerp(BLACK, 0.1 + (i % 3) * 0.05))
	end
	add("Flower", "Ball", Vector3.one * S * 0.12, CFrame.new(-S * 0.3, S * 0.42, -S * 0.1), Color3.fromRGB(255, 230, 90))
end

function PET_FEATURES.Bird(add, S, c, dark)
	beak(add, S * 0.26, S * 0.2, CFrame.new(0, -S * 0.06, -S * 0.58), Color3.fromRGB(255, 150, 40))
	for _, sx in ipairs({ -1, 1 }) do
		add("Wing", "Blob", Vector3.new(S * 0.14, S * 0.46, S * 0.52), CFrame.new(sx * S * 0.5, -S * 0.02, S * 0.05) * CFrame.Angles(0, 0, math.rad(-20 * sx)), dark)
		add("WingTip", "Blob", Vector3.new(S * 0.1, S * 0.2, S * 0.3), CFrame.new(sx * S * 0.55, -S * 0.2, S * 0.22) * CFrame.Angles(0, 0, math.rad(-20 * sx)), dark:Lerp(BLACK, 0.2))
	end
	for i = -1, 1 do
		add("Crest", "Blob", Vector3.new(S * 0.08, S * 0.34, S * 0.14), CFrame.new(i * S * 0.08, S * 0.56, -S * 0.05) * CFrame.Angles(0, 0, math.rad(i * 25)), Color3.fromRGB(255, 120, 60))
		add("TailFeather", "Blob", Vector3.new(S * 0.14, S * 0.08, S * 0.45), CFrame.new(i * S * 0.1, S * 0.05, S * 0.55) * CFrame.Angles(math.rad(20), math.rad(i * 18), 0), dark)
	end
end

function PET_FEATURES.Chick(add, S, c, dark)
	beak(add, S * 0.2, S * 0.18, CFrame.new(0, -S * 0.06, -S * 0.56), Color3.fromRGB(255, 150, 40))
	add("Fluff", "Blob", Vector3.new(S * 0.1, S * 0.3, S * 0.1), CFrame.new(0, S * 0.56, 0) * CFrame.Angles(0, 0, math.rad(15)), c)
	add("Fluff", "Blob", Vector3.new(S * 0.08, S * 0.22, S * 0.08), CFrame.new(S * 0.08, S * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-30)), c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Wing", "Blob", Vector3.new(S * 0.12, S * 0.3, S * 0.36), CFrame.new(sx * S * 0.49, -S * 0.08, S * 0.02) * CFrame.Angles(0, 0, math.rad(-35 * sx)), c:Lerp(Color3.fromRGB(255, 170, 60), 0.3))
	end
	add("Shell", "Blob", Vector3.new(S * 1.02, S * 0.4, S * 1.02), CFrame.new(0, -S * 0.32, 0), Color3.fromRGB(250, 245, 230))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		triangle(add, "ShellZig", S * 0.2, S * 0.16, S * 0.04, CFrame.new(math.cos(a) * S * 0.47, -S * 0.12, math.sin(a) * S * 0.47) * CFrame.Angles(0, -a - math.pi / 2, 0), Color3.fromRGB(250, 245, 230))
	end
end

function PET_FEATURES.Duck(add, S, c, dark)
	local bill = Color3.fromRGB(255, 150, 40)
	add("Bill", "Blob", Vector3.new(S * 0.42, S * 0.12, S * 0.3), CFrame.new(0, -S * 0.06, -S * 0.56), bill)
	add("BillLow", "Blob", Vector3.new(S * 0.36, S * 0.08, S * 0.24), CFrame.new(0, -S * 0.13, -S * 0.54), bill:Lerp(BLACK, 0.15))
	for _, sx in ipairs({ -1, 1 }) do
		add("Nostril", "Ball", Vector3.one * S * 0.04, CFrame.new(sx * S * 0.06, -S * 0.01, -S * 0.66), bill:Lerp(BLACK, 0.4))
		add("Wing", "Blob", Vector3.new(S * 0.14, S * 0.4, S * 0.55), CFrame.new(sx * S * 0.5, -S * 0.06, S * 0.08) * CFrame.Angles(0, 0, math.rad(-15 * sx)), c:Lerp(WHITE, 0.2))
	end
	add("Tuft", "Blob", Vector3.new(S * 0.08, S * 0.26, S * 0.08), CFrame.new(0, S * 0.56, -S * 0.02) * CFrame.Angles(math.rad(-25), 0, 0), c)
	add("TailTuft", "Blob", Vector3.new(S * 0.22, S * 0.24, S * 0.26), CFrame.new(0, S * 0.12, S * 0.5) * CFrame.Angles(math.rad(-40), 0, 0), c)
	add("Bow", "Blob", Vector3.new(S * 0.18, S * 0.14, S * 0.08), CFrame.new(-S * 0.1, -S * 0.3, -S * 0.43), Color3.fromRGB(90, 160, 255))
	add("Bow", "Blob", Vector3.new(S * 0.18, S * 0.14, S * 0.08), CFrame.new(S * 0.1, -S * 0.3, -S * 0.43), Color3.fromRGB(90, 160, 255))
end

function PET_FEATURES.Newt(add, S, c, dark)
	add("Tail", "Blob", Vector3.new(S * 0.3, S * 0.24, S * 0.9), CFrame.new(0, -S * 0.22, S * 0.72), c)
	add("TailTip", "Blob", Vector3.new(S * 0.18, S * 0.16, S * 0.4), CFrame.new(0, -S * 0.2, S * 1.22), dark)
	for i = 1, 6 do
		local a = i * 1.05
		add("GlowSpot", "Ball", Vector3.one * S * 0.12, CFrame.new(math.cos(a) * S * 0.33, S * 0.3 + math.sin(a) * S * 0.08, math.sin(a) * S * 0.2 + S * 0.15), Color3.fromRGB(200, 255, 120), Enum.Material.Neon)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 1 do
			add("Frill", "Blob", Vector3.new(S * 0.07, S * 0.3, S * 0.26), CFrame.new(sx * S * 0.46, S * (0.16 - j * 0.16), S * 0.05) * CFrame.Angles(0, 0, math.rad((-40 + j * 30) * sx)), Color3.fromRGB(255, 150, 200))
		end
	end
end

function PET_FEATURES.Mushroom(add, S)
	local cap = Color3.fromRGB(235, 70, 110)
	add("Cap", "Blob", Vector3.new(S * 1.25, S * 0.6, S * 1.25), CFrame.new(0, S * 0.58, 0.05 * S), cap)
	add("CapRim", "Cyl", Vector3.new(S * 0.08, S * 1.12, S * 1.12), CFrame.new(0, S * 0.36, 0.05 * S) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(250, 235, 220))
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		add("CapDot", "Blob", Vector3.new(S * 0.22, S * 0.1, S * 0.22), CFrame.new(math.cos(a) * S * 0.38, S * 0.76, math.sin(a) * S * 0.38) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), WHITE)
	end
	add("CapDot", "Blob", Vector3.new(S * 0.26, S * 0.1, S * 0.26), CFrame.new(0, S * 0.88, 0), WHITE)
end

function PET_FEATURES.Bat(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.26, S * 0.6, S * 0.28, S * 0.38, dark)
		for j = 0, 2 do
			add("Wing", "Blob", Vector3.new(S * 0.5, S * 0.05, S * 0.34), CFrame.new(sx * (S * 0.62 + j * S * 0.3), S * 0.1 - j * S * 0.08, S * 0.05 + j * S * 0.04) * CFrame.Angles(0, 0, math.rad((15 + j * 18) * sx)), dark)
			add("WingBone", "Block", Vector3.new(S * 0.5, S * 0.04, S * 0.04), CFrame.new(sx * (S * 0.62 + j * S * 0.3), S * 0.13 - j * S * 0.08, S * 0.05 + j * S * 0.04) * CFrame.Angles(0, 0, math.rad((15 + j * 18) * sx)), dark:Lerp(BLACK, 0.3))
		end
		triangle(add, "Fang", S * 0.08, S * 0.12, S * 0.03, CFrame.new(sx * S * 0.08, -S * 0.17, -S * 0.49) * CFrame.Angles(0, 0, math.pi), WHITE)
	end
end

function PET_FEATURES.Fish(add, S, c, dark, def)
	triangle(add, "DorsalFin", S * 0.5, S * 0.34, S * 0.06, CFrame.new(0, S * 0.58, S * 0.08) * CFrame.Angles(0, math.rad(90), 0), dark)
	for _, sy in ipairs({ -1, 1 }) do
		add("TailFin", "Blob", Vector3.new(S * 0.07, S * 0.42, S * 0.3), CFrame.new(0, S * 0.02 + sy * S * 0.16, S * 0.64) * CFrame.Angles(math.rad(35 * sy), 0, 0), dark)
	end
	for _, sx in ipairs({ -1, 1 }) do
		add("SideFin", "Blob", Vector3.new(S * 0.06, S * 0.22, S * 0.36), CFrame.new(sx * S * 0.5, -S * 0.12, S * 0.02) * CFrame.Angles(0, math.rad(20 * sx), math.rad(-30 * sx)), dark)
		add("Gill", "Blob", Vector3.new(S * 0.04, S * 0.3, S * 0.06), CFrame.new(sx * S * 0.46, 0, -S * 0.12) * CFrame.Angles(0, math.rad(-25 * sx), 0), dark)
	end
	for i = 1, 5 do
		add("Scale", "Blob", Vector3.new(S * 0.16, S * 0.12, S * 0.06), CFrame.new((i % 2 - 0.5) * S * 0.3, S * 0.3 - (i // 2) * S * 0.2, S * 0.1 + i * S * 0.04) * CFrame.Angles(0, math.rad(90), 0), c:Lerp(WHITE, 0.3))
	end
	if def and def.Plain then
		return
	end
	add("IceCrystal", "Block", Vector3.new(S * 0.14, S * 0.34, S * 0.14), CFrame.new(0, S * 0.66, -S * 0.2) * CFrame.Angles(0, math.rad(45), math.rad(10)), Color3.fromRGB(200, 240, 255), Enum.Material.Neon)
end

function PET_FEATURES.Koi(add, S, c, dark)
	local white = Color3.fromRGB(250, 248, 240)
	for _, p in ipairs({ { 0.2, 0.3, -0.25 }, { -0.25, 0.2, 0.15 }, { 0.15, -0.1, 0.3 } }) do
		add("KoiPatch", "Blob", Vector3.new(S * 0.4, S * 0.34, S * 0.2), CFrame.new(p[1] * S, p[2] * S, p[3] * S) * CFrame.Angles(0, math.rad(p[1] * 200), 0), white)
	end
	for i = -1, 1, 2 do
		add("TailFin", "Blob", Vector3.new(S * 0.06, S * 0.6, S * 0.5), CFrame.new(0, i * S * 0.12, S * 0.72) * CFrame.Angles(math.rad(40 * i), 0, 0), c:Lerp(WHITE, 0.25), Enum.Material.Glass)
	end
	triangle(add, "DorsalFin", S * 0.6, S * 0.3, S * 0.05, CFrame.new(0, S * 0.56, S * 0.12) * CFrame.Angles(0, math.rad(90), 0), c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Whisker", "Block", Vector3.new(S * 0.03, S * 0.03, S * 0.35), CFrame.new(sx * S * 0.12, -S * 0.14, -S * 0.6) * CFrame.Angles(math.rad(25), math.rad(25 * sx), 0), c:Lerp(BLACK, 0.2))
		add("SideFin", "Blob", Vector3.new(S * 0.05, S * 0.3, S * 0.4), CFrame.new(sx * S * 0.5, -S * 0.2, -S * 0.05) * CFrame.Angles(0, math.rad(20 * sx), math.rad(-40 * sx)), c:Lerp(WHITE, 0.3), Enum.Material.Glass)
	end
end

function PET_FEATURES.Cat(add, S, c, dark, def)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.26, S * 0.56, S * 0.3, S * 0.34, c)
		for j = 0, 1 do
			add("Whisker", "Block", Vector3.new(S * 0.3, S * 0.02, S * 0.02), CFrame.new(sx * S * 0.42, -S * 0.06 - j * S * 0.06, -S * 0.42) * CFrame.Angles(0, 0, math.rad((12 - j * 20) * sx)), BLACK)
		end
	end
	add("Nose", "Blob", Vector3.new(S * 0.08, S * 0.06, S * 0.05), CFrame.new(0, -S * 0.02, -S * 0.49), BLUSH)
	stripes(add, S, dark, 3)
	add("Tail", "Blob", Vector3.new(S * 0.14, S * 0.6, S * 0.14), CFrame.new(0, S * 0.3, S * 0.55) * CFrame.Angles(math.rad(-25), 0, 0), c)
	if def and def.Plain then
		add("TailTip", "Blob", Vector3.new(S * 0.18, S * 0.22, S * 0.18), CFrame.new(0, S * 0.6, S * 0.7), dark)
	else
		add("TailFlame", "Blob", Vector3.new(S * 0.28, S * 0.36, S * 0.28), CFrame.new(0, S * 0.66, S * 0.72), Color3.fromRGB(255, 190, 50), Enum.Material.Neon)
		add("TailFlameCore", "Blob", Vector3.new(S * 0.16, S * 0.24, S * 0.16), CFrame.new(0, S * 0.62, S * 0.72), Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
	end
end

function PET_FEATURES.GlitchCat(add, S, c, dark)
	local cyan, magenta = Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 60, 200)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.26, S * 0.56, S * 0.3, S * 0.34, c, if sx < 0 then cyan else magenta)
	end
	-- offset "glitch" blocks floating off the body
	for i, p in ipairs({ { 0.5, 0.2, -0.1 }, { -0.52, -0.1, 0.1 }, { 0.3, 0.45, 0.2 }, { -0.35, 0.35, -0.2 }, { 0.2, -0.35, 0.4 } }) do
		add("GlitchBit", "Block", Vector3.new(S * 0.14, S * 0.08, S * 0.14), CFrame.new(p[1] * S, p[2] * S, p[3] * S), if i % 2 == 0 then cyan else magenta, Enum.Material.Neon)
	end
	add("ScanLine", "Block", Vector3.new(S * 1.02, S * 0.03, S * 0.2), CFrame.new(0, S * 0.02, -S * 0.36), cyan, Enum.Material.Neon)
	add("Tail", "Block", Vector3.new(S * 0.12, S * 0.5, S * 0.12), CFrame.new(0, S * 0.3, S * 0.55) * CFrame.Angles(math.rad(-25), 0, 0), c)
	add("TailPixel", "Block", Vector3.new(S * 0.2, S * 0.2, S * 0.2), CFrame.new(S * 0.05, S * 0.6, S * 0.7), magenta, Enum.Material.Neon)
end

function PET_FEATURES.Cub(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Ball", Vector3.one * S * 0.28, CFrame.new(sx * S * 0.33, S * 0.44, 0), dark)
		add("InnerEar", "Ball", Vector3.one * S * 0.15, CFrame.new(sx * S * 0.33, S * 0.44, -S * 0.08), BLUSH)
	end
	add("Snout", "Blob", Vector3.new(S * 0.32, S * 0.22, S * 0.2), CFrame.new(0, -S * 0.1, -S * 0.44), c:Lerp(WHITE, 0.45))
	add("Nose", "Blob", Vector3.new(S * 0.12, S * 0.08, S * 0.08), CFrame.new(0, -S * 0.04, -S * 0.54), BLACK)
	-- lightning bolt on the forehead
	local bolt = Color3.fromRGB(255, 240, 80)
	add("Bolt", "Block", Vector3.new(S * 0.08, S * 0.2, S * 0.05), CFrame.new(S * 0.02, S * 0.38, -S * 0.38) * CFrame.Angles(0, 0, math.rad(25)), bolt, Enum.Material.Neon)
	add("Bolt", "Block", Vector3.new(S * 0.14, S * 0.05, S * 0.05), CFrame.new(0, S * 0.29, -S * 0.4), bolt, Enum.Material.Neon)
	add("Bolt", "Block", Vector3.new(S * 0.08, S * 0.2, S * 0.05), CFrame.new(-S * 0.02, S * 0.2, -S * 0.42) * CFrame.Angles(0, 0, math.rad(25)), bolt, Enum.Material.Neon)
	add("Tail", "Block", Vector3.new(S * 0.1, S * 0.3, S * 0.1), CFrame.new(0, S * 0.1, S * 0.52) * CFrame.Angles(math.rad(-40), 0, math.rad(30)), bolt, Enum.Material.Neon)
end

function PET_FEATURES.Hamster(add, S, c, dark)
	local cream = c:Lerp(WHITE, 0.6)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Blob", Vector3.new(S * 0.24, S * 0.22, S * 0.1), CFrame.new(sx * S * 0.3, S * 0.44, -S * 0.05) * CFrame.Angles(0, 0, math.rad(-20 * sx)), dark)
		add("InnerEar", "Blob", Vector3.new(S * 0.14, S * 0.13, S * 0.06), CFrame.new(sx * S * 0.3, S * 0.44, -S * 0.1) * CFrame.Angles(0, 0, math.rad(-20 * sx)), BLUSH)
		add("Cheek", "Blob", Vector3.new(S * 0.36, S * 0.3, S * 0.3), CFrame.new(sx * S * 0.34, -S * 0.12, -S * 0.26), cream)
		add("Whisker", "Block", Vector3.new(S * 0.26, S * 0.02, S * 0.02), CFrame.new(sx * S * 0.4, -S * 0.08, -S * 0.42) * CFrame.Angles(0, 0, math.rad(8 * sx)), dark:Lerp(BLACK, 0.3))
		add("Tooth", "Block", Vector3.new(S * 0.06, S * 0.08, S * 0.03), CFrame.new(sx * S * 0.035, -S * 0.17, -S * 0.49), WHITE)
	end
	add("Nose", "Ball", Vector3.one * S * 0.08, CFrame.new(0, -S * 0.04, -S * 0.5), BLUSH)
	add("Stripe", "Blob", Vector3.new(S * 0.3, S * 0.5, S * 0.12), CFrame.new(0, S * 0.3, -S * 0.2) * CFrame.Angles(math.rad(-40), 0, 0), dark)
	add("Seed", "Blob", Vector3.new(S * 0.12, S * 0.18, S * 0.08), CFrame.new(S * 0.05, -S * 0.3, -S * 0.5) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(60, 50, 45))
end

function PET_FEATURES.Monkey(add, S, c, dark)
	local face = Color3.fromRGB(245, 205, 165)
	add("Face", "Blob", Vector3.new(S * 0.68, S * 0.56, S * 0.2), CFrame.new(0, -S * 0.02, -S * 0.4), face)
	add("Muzzle", "Blob", Vector3.new(S * 0.42, S * 0.24, S * 0.2), CFrame.new(0, -S * 0.16, -S * 0.46), face:Lerp(WHITE, 0.2))
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Cyl", Vector3.new(S * 0.08, S * 0.32, S * 0.32), CFrame.new(sx * S * 0.5, S * 0.08, 0) * CFrame.Angles(0, 0, 0), c)
		add("InnerEar", "Cyl", Vector3.new(S * 0.06, S * 0.2, S * 0.2), CFrame.new(sx * S * 0.53, S * 0.08, -S * 0.02), face)
		add("Arm", "Blob", Vector3.new(S * 0.16, S * 0.46, S * 0.16), CFrame.new(sx * S * 0.46, -S * 0.2, -S * 0.12) * CFrame.Angles(0, 0, math.rad(20 * sx)), c)
		add("Hand", "Ball", Vector3.one * S * 0.16, CFrame.new(sx * S * 0.54, -S * 0.42, -S * 0.2), face)
	end
	add("Tail", "Blob", Vector3.new(S * 0.1, S * 0.1, S * 0.6), CFrame.new(0, -S * 0.05, S * 0.62) * CFrame.Angles(math.rad(35), 0, 0), c)
	add("TailCurl", "Cyl", Vector3.new(S * 0.08, S * 0.28, S * 0.28), CFrame.new(0, S * 0.18, S * 0.86) * CFrame.Angles(0, math.rad(90), 0), c)
	add("Banana", "Blob", Vector3.new(S * 0.1, S * 0.36, S * 0.1), CFrame.new(S * 0.6, -S * 0.36, -S * 0.28) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(255, 225, 70))
	tuft(add, S, dark)
end

function PET_FEATURES.Turtle(add, S, c, dark)
	local shell = Color3.fromRGB(125, 90, 55)
	add("Shell", "Blob", Vector3.new(S * 1.2, S * 0.75, S * 1.25), CFrame.new(0, S * 0.18, S * 0.18), shell)
	add("ShellRim", "Cyl", Vector3.new(S * 0.1, S * 1.24, S * 1.24), CFrame.new(0, -S * 0.08, S * 0.18) * CFrame.Angles(0, 0, math.rad(90)), shell:Lerp(Color3.fromRGB(230, 200, 120), 0.5))
	add("Scute", "Blob", Vector3.new(S * 0.4, S * 0.12, S * 0.4), CFrame.new(0, S * 0.54, S * 0.18), shell:Lerp(Color3.fromRGB(200, 170, 90), 0.5))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		add("Scute", "Blob", Vector3.new(S * 0.3, S * 0.1, S * 0.3), CFrame.new(math.cos(a) * S * 0.36, S * 0.42, S * 0.18 + math.sin(a) * S * 0.36) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), shell:Lerp(Color3.fromRGB(200, 170, 90), 0.35))
	end
	add("Tail", "Blob", Vector3.new(S * 0.14, S * 0.12, S * 0.3), CFrame.new(0, -S * 0.22, S * 0.8), c)
	add("Leaf", "Blob", Vector3.new(S * 0.3, S * 0.06, S * 0.16), CFrame.new(S * 0.1, S * 0.62, S * 0.15) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(90, 190, 70))
end

function PET_FEATURES.Moth(add, S, c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Antenna", "Block", Vector3.new(S * 0.04, S * 0.4, S * 0.04), CFrame.new(sx * S * 0.15, S * 0.62, -S * 0.15) * CFrame.Angles(math.rad(-20), 0, math.rad(-20 * sx)), BLACK)
		add("AntennaTip", "Ball", Vector3.one * S * 0.12, CFrame.new(sx * S * 0.23, S * 0.82, -S * 0.23), Color3.fromRGB(220, 160, 255), Enum.Material.Neon)
		add("WingTop", "Blob", Vector3.new(S * 0.85, S * 0.06, S * 0.62), CFrame.new(sx * S * 0.8, S * 0.25, S * 0.1) * CFrame.Angles(0, 0, math.rad(25 * sx)), c:Lerp(Color3.fromRGB(180, 120, 255), 0.4))
		add("WingEdge", "Blob", Vector3.new(S * 0.9, S * 0.05, S * 0.66), CFrame.new(sx * S * 0.8, S * 0.24, S * 0.1) * CFrame.Angles(0, 0, math.rad(25 * sx)), Color3.fromRGB(60, 30, 90))
		add("WingDot", "Blob", Vector3.new(S * 0.26, S * 0.07, S * 0.26), CFrame.new(sx * S * 0.9, S * 0.3, S * 0.1) * CFrame.Angles(0, 0, math.rad(25 * sx)), Color3.fromRGB(255, 200, 255), Enum.Material.Neon)
		add("WingLow", "Blob", Vector3.new(S * 0.5, S * 0.06, S * 0.45), CFrame.new(sx * S * 0.6, -S * 0.1, S * 0.3) * CFrame.Angles(0, 0, math.rad(-15 * sx)), c:Lerp(Color3.fromRGB(180, 120, 255), 0.2))
	end
	add("Fuzz", "Blob", Vector3.new(S * 0.7, S * 0.22, S * 0.5), CFrame.new(0, -S * 0.3, -S * 0.1), WHITE)
end

function PET_FEATURES.Stag(add, S, c, dark)
	local crystal = Color3.fromRGB(190, 160, 255)
	for _, sx in ipairs({ -1, 1 }) do
		add("Antler", "Block", Vector3.new(S * 0.08, S * 0.5, S * 0.08), CFrame.new(sx * S * 0.22, S * 0.72, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx)), crystal, Enum.Material.Neon)
		add("AntlerTine", "Block", Vector3.new(S * 0.07, S * 0.3, S * 0.07), CFrame.new(sx * S * 0.38, S * 0.82, -S * 0.08) * CFrame.Angles(math.rad(-20), 0, math.rad(-60 * sx)), crystal, Enum.Material.Neon)
		add("AntlerTip", "Block", Vector3.new(S * 0.07, S * 0.26, S * 0.07), CFrame.new(sx * S * 0.34, S * 1.0, S * 0.04) * CFrame.Angles(0, 0, math.rad(-10 * sx)), crystal, Enum.Material.Neon)
		add("Ear", "Blob", Vector3.new(S * 0.3, S * 0.12, S * 0.14), CFrame.new(sx * S * 0.45, S * 0.3, 0) * CFrame.Angles(0, 0, math.rad(-20 * sx)), dark)
	end
	for i = 1, 5 do
		add("Spot", "Ball", Vector3.one * S * 0.09, CFrame.new((i % 2 - 0.5) * S * 0.45, S * 0.36 - i * S * 0.03, S * 0.1 + i * S * 0.06), WHITE)
	end
	add("Snout", "Blob", Vector3.new(S * 0.32, S * 0.24, S * 0.22), CFrame.new(0, -S * 0.1, -S * 0.45), c:Lerp(WHITE, 0.4))
	add("Nose", "Blob", Vector3.new(S * 0.12, S * 0.08, S * 0.08), CFrame.new(0, -S * 0.04, -S * 0.56), BLACK)
	add("Tail", "Blob", Vector3.new(S * 0.2, S * 0.24, S * 0.14), CFrame.new(0, S * 0.1, S * 0.5), WHITE)
end

function PET_FEATURES.Drake(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		triangle(add, "Horn", S * 0.14, S * 0.38, S * 0.12, CFrame.new(sx * S * 0.24, S * 0.6, S * 0.08) * CFrame.Angles(math.rad(-20), 0, math.rad(-12 * sx)), GOLD)
		add("WingArm", "Block", Vector3.new(S * 0.06, S * 0.06, S * 0.7), CFrame.new(sx * S * 0.55, S * 0.55, S * 0.25) * CFrame.Angles(math.rad(30), math.rad(-35 * sx), 0), dark:Lerp(BLACK, 0.2))
		triangle(add, "Wing", S * 0.7, S * 0.6, S * 0.05, CFrame.new(sx * S * 0.62, S * 0.3, S * 0.3) * CFrame.Angles(0, math.rad(-60 * sx), math.rad(180)) , dark)
		add("Nostril", "Ball", Vector3.one * S * 0.05, CFrame.new(sx * S * 0.06, -S * 0.02, -S * 0.49), BLACK)
	end
	for i = 0, 3 do
		triangle(add, "Spike", S * 0.2, S * 0.18, S * 0.06, CFrame.new(0, S * 0.47 - i * S * 0.1, S * 0.1 + i * S * 0.15) * CFrame.Angles(math.rad(-25 - i * 12), math.rad(90), 0), GOLD)
	end
	add("Tail", "Blob", Vector3.new(S * 0.22, S * 0.22, S * 0.8), CFrame.new(0, -S * 0.25, S * 0.7), c)
	add("TailFlame", "Blob", Vector3.new(S * 0.3, S * 0.3, S * 0.3), CFrame.new(0, -S * 0.2, S * 1.12), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	add("BellyScales", "Blob", Vector3.new(S * 0.5, S * 0.5, S * 0.14), CFrame.new(0, -S * 0.2, -S * 0.42), Color3.fromRGB(255, 225, 150))
end

function PET_FEATURES.Serpent(add, S, c, dark)
	for i = 1, 5 do
		local r = S * (0.72 - i * 0.09)
		add("Segment", "Ball", Vector3.one * r, CFrame.new(math.sin(i * 1.1) * S * 0.22, -S * 0.2 + i * S * 0.02, S * 0.3 + i * S * 0.3), if i % 2 == 0 then dark else c)
		add("SegmentFin", "Blob", Vector3.new(S * 0.05, r * 0.5, r * 0.4), CFrame.new(math.sin(i * 1.1) * S * 0.22, -S * 0.2 + i * S * 0.02 + r * 0.5, S * 0.3 + i * S * 0.3), Color3.fromRGB(120, 230, 255))
	end
	add("TailFin", "Blob", Vector3.new(S * 0.06, S * 0.5, S * 0.4), CFrame.new(0, -S * 0.1, S * 1.9), Color3.fromRGB(120, 230, 255))
	for i = 0, 2 do
		add("Crest", "Blob", Vector3.new(S * 0.06, S * 0.34, S * 0.26), CFrame.new(0, S * 0.5 - i * S * 0.05, -S * 0.05 + i * S * 0.2), Color3.fromRGB(120, 230, 255))
	end
	for _, sx in ipairs({ -1, 1 }) do
		add("Whisker", "Block", Vector3.new(S * 0.5, S * 0.03, S * 0.03), CFrame.new(sx * S * 0.35, -S * 0.1, -S * 0.46) * CFrame.Angles(0, math.rad(-20 * sx), math.rad(-15 * sx)), GOLD)
		triangle(add, "Horn", S * 0.1, S * 0.3, S * 0.08, CFrame.new(sx * S * 0.18, S * 0.55, S * 0.05) * CFrame.Angles(math.rad(-30), 0, 0), GOLD)
	end
end

function PET_FEATURES.Phoenix(add, S, c, dark)
	local flame = Color3.fromRGB(255, 190, 60)
	beak(add, S * 0.24, S * 0.16, CFrame.new(0, -S * 0.06, -S * 0.58), GOLD)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 3 do
			add("WingFeather", "Blob", Vector3.new(S * 0.7, S * 0.08, S * 0.2), CFrame.new(sx * (S * 0.7 + j * S * 0.1), S * 0.38 - j * S * 0.1, S * 0.05 + j * S * 0.1) * CFrame.Angles(0, math.rad(15 * sx * j), math.rad(35 * sx)), if j == 0 then flame else c:Lerp(flame, j * 0.15), if j == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
	end
	for i = -1, 1 do
		add("Crest", "Blob", Vector3.new(S * 0.08, S * 0.45, S * 0.14), CFrame.new(i * S * 0.1, S * 0.62, S * 0.05) * CFrame.Angles(math.rad(-15), 0, math.rad(i * 20)), flame, Enum.Material.Neon)
	end
	for i = -2, 2 do
		add("TailFeather", "Blob", Vector3.new(S * 0.12, S * 0.1, S * 0.95), CFrame.new(i * S * 0.1, -S * 0.1 + math.abs(i) * S * 0.05, S * 0.85) * CFrame.Angles(math.rad(15), math.rad(i * 12), 0), if i == 0 then flame else c, Enum.Material.Neon)
	end
end

function PET_FEATURES.Owl(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("EyeRing", "Cyl", Vector3.new(S * 0.05, S * 0.4, S * 0.4), CFrame.new(sx * S * 0.2, S * 0.12, -S * 0.44) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(245, 225, 180))
		triangle(add, "Tuft", S * 0.18, S * 0.3, S * 0.1, CFrame.new(sx * S * 0.3, S * 0.56, 0) * CFrame.Angles(0, 0, math.rad(-20 * sx)), dark)
		add("Wing", "Blob", Vector3.new(S * 0.14, S * 0.6, S * 0.5), CFrame.new(sx * S * 0.5, -S * 0.08, S * 0.05), dark)
	end
	beak(add, S * 0.16, S * 0.12, CFrame.new(0, -S * 0.08, -S * 0.53) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(255, 190, 60))
	for row = 0, 1 do
		for i = -1, 1 do
			add("Feather", "Blob", Vector3.new(S * 0.16, S * 0.1, S * 0.06), CFrame.new(i * S * 0.14 + row * S * 0.07, -S * 0.26 - row * S * 0.1, -S * 0.43 + row * S * 0.02), c:Lerp(WHITE, 0.4))
		end
	end
	add("Glasses", "Block", Vector3.new(S * 0.62, S * 0.04, S * 0.03), CFrame.new(0, S * 0.14, -S * 0.52), BLACK)
end

function PET_FEATURES.Panda(add, S, c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Ball", Vector3.one * S * 0.28, CFrame.new(sx * S * 0.33, S * 0.44, 0), BLACK)
		add("EyePatch", "Blob", Vector3.new(S * 0.3, S * 0.36, S * 0.1), CFrame.new(sx * S * 0.2, S * 0.1, -S * 0.43) * CFrame.Angles(0, 0, math.rad(20 * sx)), BLACK)
		add("Arm", "Blob", Vector3.new(S * 0.24, S * 0.4, S * 0.24), CFrame.new(sx * S * 0.45, -S * 0.15, -S * 0.1), BLACK)
	end
	add("Snout", "Blob", Vector3.new(S * 0.3, S * 0.2, S * 0.18), CFrame.new(0, -S * 0.12, -S * 0.44), WHITE)
	add("Nose", "Blob", Vector3.new(S * 0.12, S * 0.08, S * 0.08), CFrame.new(0, -S * 0.06, -S * 0.53), BLACK)
	add("Bamboo", "Cyl", Vector3.new(S * 0.9, S * 0.1, S * 0.1), CFrame.new(S * 0.46, 0, -S * 0.3) * CFrame.Angles(0, 0, math.rad(70)), Color3.fromRGB(120, 190, 80))
	for j = 0, 2 do
		add("BambooNode", "Cyl", Vector3.new(S * 0.03, S * 0.12, S * 0.12), CFrame.new(S * 0.46 + (j - 1) * S * 0.1, (j - 1) * S * 0.28, -S * 0.3) * CFrame.Angles(0, 0, math.rad(70)), Color3.fromRGB(90, 150, 60))
	end
	add("BambooLeaf", "Blob", Vector3.new(S * 0.3, S * 0.05, S * 0.12), CFrame.new(S * 0.58, S * 0.4, -S * 0.3), Color3.fromRGB(90, 170, 60))
end

function PET_FEATURES.Bunny(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Blob", Vector3.new(S * 0.2, S * 0.75, S * 0.14), CFrame.new(sx * S * 0.16, S * 0.78, S * 0.02) * CFrame.Angles(0, 0, math.rad(-10 * sx)), c)
		add("InnerEar", "Blob", Vector3.new(S * 0.1, S * 0.55, S * 0.06), CFrame.new(sx * S * 0.16, S * 0.78, -S * 0.05) * CFrame.Angles(0, 0, math.rad(-10 * sx)), BLUSH)
		add("Tooth", "Block", Vector3.new(S * 0.07, S * 0.09, S * 0.03), CFrame.new(sx * S * 0.04, -S * 0.15, -S * 0.48), WHITE)
		add("Cheek", "Blob", Vector3.new(S * 0.26, S * 0.2, S * 0.2), CFrame.new(sx * S * 0.12, -S * 0.08, -S * 0.42), c:Lerp(WHITE, 0.5))
	end
	add("Nose", "Blob", Vector3.new(S * 0.1, S * 0.07, S * 0.06), CFrame.new(0, -S * 0.02, -S * 0.5), BLUSH)
	add("Tail", "Ball", Vector3.one * S * 0.32, CFrame.new(0, -S * 0.15, S * 0.5), WHITE)
end

function PET_FEATURES.GlitchBunny(add, S, c, dark)
	local cyan, magenta = Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 60, 200)
	for _, sx in ipairs({ -1, 1 }) do
		-- blocky pixel ears, one of them bent
		for j = 0, 3 do
			local bend = if sx > 0 and j >= 2 then (j - 1) * S * 0.12 else 0
			add("EarPixel", "Block", Vector3.new(S * 0.16, S * 0.16, S * 0.12), CFrame.new(sx * S * 0.16 + bend, S * (0.52 + j * 0.16) - (if bend > 0 then bend * 0.5 else 0), 0), if j == 3 then (if sx < 0 then cyan else magenta) else c, if j == 3 then Enum.Material.Neon else nil)
		end
	end
	add("ErrorSign", "Block", Vector3.new(S * 0.5, S * 0.18, S * 0.04), CFrame.new(0, S * 0.36, -S * 0.42), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
	for i, p in ipairs({ { 0.52, 0.1, 0 }, { -0.5, -0.2, 0.15 }, { 0.2, 0.5, 0.3 }, { -0.25, -0.4, -0.3 } }) do
		add("GlitchBit", "Block", Vector3.new(S * 0.12, S * 0.12, S * 0.12), CFrame.new(p[1] * S, p[2] * S, p[3] * S), if i % 2 == 0 then cyan else magenta, Enum.Material.Neon)
	end
	add("Tail", "Block", Vector3.new(S * 0.26, S * 0.26, S * 0.26), CFrame.new(0, -S * 0.15, S * 0.5), WHITE)
end

function PET_FEATURES.Frog(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("EyeBump", "Ball", Vector3.one * S * 0.4, CFrame.new(sx * S * 0.24, S * 0.4, -S * 0.2), c)
		add("BackLeg", "Blob", Vector3.new(S * 0.32, S * 0.26, S * 0.52), CFrame.new(sx * S * 0.42, -S * 0.35, S * 0.15), dark)
		add("FrontLeg", "Blob", Vector3.new(S * 0.14, S * 0.26, S * 0.14), CFrame.new(sx * S * 0.28, -S * 0.4, -S * 0.3), dark)
		add("Webfoot", "Blob", Vector3.new(S * 0.26, S * 0.06, S * 0.22), CFrame.new(sx * S * 0.3, -S * 0.52, -S * 0.36), dark)
		add("Webfoot", "Blob", Vector3.new(S * 0.3, S * 0.06, S * 0.26), CFrame.new(sx * S * 0.5, -S * 0.5, S * 0.02), dark)
		add("Spot", "Blob", Vector3.new(S * 0.2, S * 0.06, S * 0.2), CFrame.new(sx * S * 0.2, S * 0.43, S * 0.2), dark)
	end
	add("Smile", "Blob", Vector3.new(S * 0.5, S * 0.06, S * 0.08), CFrame.new(0, -S * 0.12, -S * 0.46), Color3.fromRGB(200, 60, 80))
	add("Crown", "Cyl", Vector3.new(S * 0.1, S * 0.22, S * 0.22), CFrame.new(0, S * 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		triangle(add, "CrownPoint", S * 0.06, S * 0.1, S * 0.03, CFrame.new(math.cos(a) * S * 0.1, S * 0.62, math.sin(a) * S * 0.1) * CFrame.Angles(0, -a - math.pi / 2, 0), GOLD)
	end
end

function PET_FEATURES.Slime(add, S, c)
	add("Goo", "Blob", Vector3.new(S * 1.3, S * 0.42, S * 1.25), CFrame.new(0, -S * 0.36, 0), c)
	for i = 1, 4 do
		local a = i * 1.6
		add("Drip", "Blob", Vector3.new(S * 0.16, S * 0.32, S * 0.16), CFrame.new(math.cos(a) * S * 0.46, -S * 0.1, math.sin(a) * S * 0.46), c:Lerp(WHITE, 0.2))
		add("Bubble", "Ball", Vector3.one * S * (0.08 + i * 0.025), CFrame.new(math.cos(a + 1) * S * 0.2, S * 0.2 + i * S * 0.07, math.sin(a + 1) * S * 0.2), WHITE, Enum.Material.Glass)
	end
	add("Core", "Ball", Vector3.one * S * 0.3, CFrame.new(0, -S * 0.05, S * 0.1), c:Lerp(WHITE, 0.4), Enum.Material.Neon)
end

function PET_FEATURES.Fox(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.3, S * 0.64, S * 0.34, S * 0.5, c, Color3.fromRGB(255, 230, 210))
		add("EarTip", "Blob", Vector3.new(S * 0.12, S * 0.12, S * 0.1), CFrame.new(sx * S * 0.38, S * 0.86, -S * 0.02), dark:Lerp(BLACK, 0.4))
		add("Cheek", "Blob", Vector3.new(S * 0.32, S * 0.24, S * 0.2), CFrame.new(sx * S * 0.25, -S * 0.12, -S * 0.36), WHITE)
		add("Sock", "Blob", Vector3.new(S * 0.2, S * 0.14, S * 0.22), CFrame.new(sx * S * 0.24, -S * 0.52, -S * 0.26), dark:Lerp(BLACK, 0.4))
	end
	add("Snout", "Blob", Vector3.new(S * 0.3, S * 0.2, S * 0.28), CFrame.new(0, -S * 0.08, -S * 0.48), WHITE)
	add("Nose", "Ball", Vector3.one * S * 0.1, CFrame.new(0, -S * 0.02, -S * 0.62), BLACK)
	add("Tail", "Blob", Vector3.new(S * 0.4, S * 0.4, S * 0.9), CFrame.new(0, S * 0.05, S * 0.75) * CFrame.Angles(math.rad(-30), 0, 0), c)
	add("TailTip", "Blob", Vector3.new(S * 0.3, S * 0.3, S * 0.3), CFrame.new(0, S * 0.32, S * 1.15), WHITE)
end

function PET_FEATURES.Penguin(add, S, c)
	add("Belly", "Blob", Vector3.new(S * 0.75, S * 0.8, S * 0.3), CFrame.new(0, -S * 0.08, -S * 0.36), WHITE)
	beak(add, S * 0.2, S * 0.16, CFrame.new(0, -S * 0.04, -S * 0.56), Color3.fromRGB(255, 170, 40))
	for _, sx in ipairs({ -1, 1 }) do
		add("Flipper", "Blob", Vector3.new(S * 0.12, S * 0.55, S * 0.3), CFrame.new(sx * S * 0.52, -S * 0.08, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx)), c)
	end
	add("Scarf", "Cyl", Vector3.new(S * 0.14, S * 0.95, S * 0.95), CFrame.new(0, -S * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 50, 60), Enum.Material.Fabric)
	add("ScarfStripe", "Cyl", Vector3.new(S * 0.05, S * 0.97, S * 0.97), CFrame.new(0, -S * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), WHITE, Enum.Material.Fabric)
	add("ScarfEnd", "Block", Vector3.new(S * 0.16, S * 0.35, S * 0.06), CFrame.new(S * 0.28, -S * 0.36, -S * 0.42), Color3.fromRGB(220, 50, 60), Enum.Material.Fabric)
	add("Beanie", "Blob", Vector3.new(S * 0.7, S * 0.3, S * 0.7), CFrame.new(0, S * 0.42, S * 0.02), Color3.fromRGB(80, 150, 255), Enum.Material.Fabric)
	add("Pompom", "Ball", Vector3.one * S * 0.18, CFrame.new(0, S * 0.6, S * 0.02), WHITE, Enum.Material.Fabric)
end

function PET_FEATURES.Axolotl(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			add("Gill", "Blob", Vector3.new(S * 0.08, S * 0.32, S * 0.08), CFrame.new(sx * (S * 0.42 + j * 0.03), S * (0.3 - j * 0.14), S * 0.05) * CFrame.Angles(0, 0, math.rad((50 - j * 30) * -sx)), Color3.fromRGB(255, 90, 150))
			add("GillTip", "Ball", Vector3.one * S * 0.08, CFrame.new(sx * (S * 0.55 + j * 0.02), S * (0.4 - j * 0.14 - j * 0.02), S * 0.05), Color3.fromRGB(255, 140, 190))
		end
	end
	add("Tail", "Blob", Vector3.new(S * 0.14, S * 0.34, S * 0.8), CFrame.new(0, -S * 0.1, S * 0.7), c)
	add("TailFin", "Blob", Vector3.new(S * 0.06, S * 0.45, S * 0.6), CFrame.new(0, -S * 0.1, S * 0.75), c:Lerp(WHITE, 0.4))
	add("Smile", "Blob", Vector3.new(S * 0.4, S * 0.06, S * 0.06), CFrame.new(0, -S * 0.12, -S * 0.47), Color3.fromRGB(200, 70, 110))
end

function PET_FEATURES.Dino(add, S, c, dark)
	for i = 0, 3 do
		triangle(add, "Plate", S * 0.26, S * 0.26, S * 0.06, CFrame.new(0, S * (0.5 - i * 0.08), S * (-0.05 + i * 0.2)) * CFrame.Angles(math.rad(-20 - i * 15), math.rad(90), 0), Color3.fromRGB(255, 150, 60))
	end
	add("Tail", "Blob", Vector3.new(S * 0.3, S * 0.3, S * 0.9), CFrame.new(0, -S * 0.2, S * 0.7) * CFrame.Angles(math.rad(10), 0, 0), c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Arm", "Blob", Vector3.new(S * 0.12, S * 0.22, S * 0.12), CFrame.new(sx * S * 0.3, -S * 0.1, -S * 0.42), dark)
		triangle(add, "Tooth", S * 0.07, S * 0.1, S * 0.03, CFrame.new(sx * S * 0.1, -S * 0.16, -S * 0.49) * CFrame.Angles(0, 0, math.pi), WHITE)
		add("Nostril", "Ball", Vector3.one * S * 0.05, CFrame.new(sx * S * 0.07, S * 0.0, -S * 0.49), dark:Lerp(BLACK, 0.4))
	end
	add("Belly", "Blob", Vector3.new(S * 0.5, S * 0.5, S * 0.14), CFrame.new(0, -S * 0.2, -S * 0.42), Color3.fromRGB(240, 230, 170))
end

function PET_FEATURES.Jelly(add, S, c)
	add("Bell", "Blob", Vector3.new(S * 1.15, S * 0.72, S * 1.15), CFrame.new(0, S * 0.25, 0), c, Enum.Material.Glass)
	add("BellRim", "Cyl", Vector3.new(S * 0.08, S * 1.05, S * 1.05), CFrame.new(0, -S * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), c:Lerp(WHITE, 0.4), Enum.Material.Neon)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("Tentacle", "Blob", Vector3.new(S * 0.09, S * (0.6 + (i % 3) * 0.15), S * 0.09), CFrame.new(math.cos(a) * S * 0.34, -S * 0.55, math.sin(a) * S * 0.34) * CFrame.Angles(math.rad(10), 0, math.rad(8)), c:Lerp(WHITE, 0.3), Enum.Material.Neon)
	end
	add("Crown", "Cyl", Vector3.new(S * 0.12, S * 0.36, S * 0.36), CFrame.new(0, S * 0.66, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		triangle(add, "CrownPoint", S * 0.08, S * 0.12, S * 0.03, CFrame.new(math.cos(a) * S * 0.16, S * 0.78, math.sin(a) * S * 0.16) * CFrame.Angles(0, -a - math.pi / 2, 0), GOLD)
		add("CrownGem", "Ball", Vector3.one * S * 0.07, CFrame.new(math.cos(a) * S * 0.19, S * 0.68, math.sin(a) * S * 0.19), Color3.fromRGB(255, 120, 220), Enum.Material.Neon)
	end
end

local function hornSpiral(add, S, cf, len, color)
	for i = 0, 3 do
		local w = S * (0.16 - i * 0.035)
		add("Horn", "Cyl", Vector3.new(len / 4, w, w), cf * CFrame.new(0, len * (i + 0.5) / 4, 0) * CFrame.Angles(0, math.rad(i * 25), math.rad(90)), color, Enum.Material.Neon)
	end
end

function PET_FEATURES.Unicorn(add, S, c)
	local rainbow = { Color3.fromRGB(255, 110, 130), Color3.fromRGB(255, 200, 90), Color3.fromRGB(120, 220, 140), Color3.fromRGB(110, 170, 255), Color3.fromRGB(190, 130, 255) }
	hornSpiral(add, S, CFrame.new(0, S * 0.42, -S * 0.25) * CFrame.Angles(math.rad(-15), 0, 0), S * 0.55, GOLD)
	for i, col in ipairs(rainbow) do
		add("Mane", "Blob", Vector3.new(S * 0.2, S * 0.32, S * 0.26), CFrame.new(0, S * (0.5 - i * 0.12), S * (0.05 + i * 0.1)), col)
		add("TailStrand", "Blob", Vector3.new(S * 0.14, S * 0.55, S * 0.14), CFrame.new((i - 3) * S * 0.06, -S * 0.05, S * 0.6) * CFrame.Angles(math.rad(-30), 0, math.rad((i - 3) * 8)), col)
	end
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.26, S * 0.56, S * 0.18, S * 0.26, c)
		for j = 0, 2 do
			add("WingFeather", "Blob", Vector3.new(S * 0.08, S * (0.5 - j * 0.1), S * 0.3), CFrame.new(sx * (S * 0.52 + j * S * 0.06), S * (0.34 - j * 0.08), S * (0.02 + j * 0.16)) * CFrame.Angles(math.rad(10), 0, math.rad(-40 * sx)), WHITE)
		end
		add("Hoof", "Blob", Vector3.new(S * 0.2, S * 0.08, S * 0.22), CFrame.new(sx * S * 0.24, -S * 0.56, -S * 0.26), GOLD)
	end
	add("Snout", "Blob", Vector3.new(S * 0.3, S * 0.2, S * 0.2), CFrame.new(0, -S * 0.12, -S * 0.44), c:Lerp(BLUSH, 0.3))
end

function PET_FEATURES.Kitsune(add, S, c)
	local fire = Color3.fromRGB(255, 120, 190)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.28, S * 0.62, S * 0.3, S * 0.48, c, fire)
		add("Marking", "Blob", Vector3.new(S * 0.08, S * 0.2, S * 0.04), CFrame.new(sx * S * 0.3, S * 0.05, -S * 0.43), Color3.fromRGB(230, 60, 90))
	end
	for i = 0, 8 do
		local a = (i / 8 - 0.5) * math.rad(150)
		local base = CFrame.new(0, S * 0.1, S * 0.3) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-30), 0, 0)
		add("Tail", "Blob", Vector3.new(S * 0.22, S * 0.22, S * 0.95), base * CFrame.new(0, 0, S * 0.5), c)
		add("TailFlame", "Ball", Vector3.one * S * 0.2, base * CFrame.new(0, 0, S * 1.0), fire, Enum.Material.Neon)
	end
	add("ForeheadGem", "Ball", Vector3.one * S * 0.1, CFrame.new(0, S * 0.35, -S * 0.43), fire, Enum.Material.Neon)
	add("Bell", "Ball", Vector3.one * S * 0.14, CFrame.new(0, -S * 0.34, -S * 0.42), GOLD, Enum.Material.Metal)
	add("Rope", "Cyl", Vector3.new(S * 0.06, S * 0.84, S * 0.84), CFrame.new(0, -S * 0.26, -S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 50, 60), Enum.Material.Fabric)
end

function PET_FEATURES.Kraken(add, S, c, dark)
	local glowC = Color3.fromRGB(140, 255, 230)
	add("Mantle", "Blob", Vector3.new(S * 0.9, S * 0.9, S * 0.9), CFrame.new(0, S * 0.45, S * 0.1), c)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local base = CFrame.new(math.cos(a) * S * 0.4, -S * 0.3, math.sin(a) * S * 0.4) * CFrame.Angles(0, -a + math.pi / 2, 0)
		add("Tentacle", "Blob", Vector3.new(S * 0.18, S * 0.18, S * 0.7), base * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, S * 0.1), if i % 2 == 0 then c else dark)
		add("TentacleCurl", "Ball", Vector3.one * S * 0.16, base * CFrame.new(0, S * 0.12, S * 0.44), if i % 2 == 0 then c else dark)
		add("Sucker", "Ball", Vector3.one * S * 0.08, base * CFrame.new(0, -S * 0.02, S * 0.2), glowC, Enum.Material.Neon)
	end
	add("Crown", "Cyl", Vector3.new(S * 0.14, S * 0.5, S * 0.5), CFrame.new(0, S * 0.92, S * 0.1) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		triangle(add, "CrownSpike", S * 0.1, S * 0.2, S * 0.04, CFrame.new(math.cos(a) * S * 0.22, S * 1.08, S * 0.1 + math.sin(a) * S * 0.22) * CFrame.Angles(0, -a - math.pi / 2, 0), glowC, Enum.Material.Neon)
	end
end

--------------------------------------------------------------------------------
-- More species
--------------------------------------------------------------------------------
BODY_PLANS.Bee = "Float"
BODY_PLANS.Ladybug = "Walker"
BODY_PLANS.Snail = "None"
BODY_PLANS.Crab = "Walker"
BODY_PLANS.Pig = "Walker"
BODY_PLANS.Sheep = "Walker"
BODY_PLANS.Cow = "Walker"
BODY_PLANS.Hedgehog = "Walker"
BODY_PLANS.Elephant = "Walker"
BODY_PLANS.Shark = "Float"
BODY_PLANS.Ghost = "Float"
BODY_PLANS.Robot = "Biped"
BODY_PLANS.Star = "Float"
BODY_PLANS.Cactus = "Biped"
BODY_PLANS.Lion = "Walker"
BODY_PLANS.Raccoon = "Walker"
BODY_PLANS.Wolf = "Walker"
BODY_PLANS.Bear = "Walker"
BODY_PLANS.Seal = "None"
BODY_PLANS.Octopus = "Float"
for _, furry in ipairs({ "Lion", "Raccoon", "Wolf", "Bear", "Sheep", "Cow", "Pig", "Hedgehog" }) do
	FUR[furry] = true
end

local function antennae(add, S, color, tip, tipMaterial)
	for _, sx in ipairs({ -1, 1 }) do
		add("Antenna", "Block", Vector3.new(S * 0.04, S * 0.32, S * 0.04), CFrame.new(sx * S * 0.13, S * 0.58, -S * 0.18) * CFrame.Angles(math.rad(-20), 0, math.rad(-22 * sx)), color)
		add("AntennaTip", "Ball", Vector3.one * S * 0.11, CFrame.new(sx * S * 0.19, S * 0.73, -S * 0.24), tip or color, tipMaterial)
	end
end

local function roundEars(add, S, outer, inner)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Ball", Vector3.one * S * 0.26, CFrame.new(sx * S * 0.32, S * 0.42, S * 0.02), outer)
		add("InnerEar", "Ball", Vector3.one * S * 0.14, CFrame.new(sx * S * 0.32, S * 0.42, -S * 0.08), inner or BLUSH)
	end
end

local function snout(add, S, color, noseColor, wide)
	add("Snout", "Blob", Vector3.new(S * (if wide then 0.46 else 0.36), S * 0.24, S * 0.24), CFrame.new(0, -S * 0.08, -S * 0.46), color)
	add("Nose", "Blob", Vector3.new(S * 0.14, S * 0.09, S * 0.08), CFrame.new(0, -S * 0.02, -S * 0.58), noseColor or BLACK)
	add("NoseShine", "Ball", Vector3.one * S * 0.035, CFrame.new(S * 0.03, 0, -S * 0.62), WHITE)
end

local function fluffyTail(add, S, color, tipColor)
	add("Tail", "Blob", Vector3.new(S * 0.24, S * 0.24, S * 0.5), CFrame.new(0, S * 0.12, S * 0.6) * CFrame.Angles(math.rad(35), 0, 0), color)
	add("TailTip", "Blob", Vector3.new(S * 0.2, S * 0.2, S * 0.22), CFrame.new(0, S * 0.3, S * 0.8), tipColor or color:Lerp(WHITE, 0.6))
end

function PET_FEATURES.Bee(add, S, c, dark)
	stripes(add, S, BLACK, 3)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 1 do
			local wing = add("Wing", "Blob", Vector3.new(S * (0.5 - j * 0.12), S * 0.05, S * (0.34 - j * 0.08)), CFrame.new(sx * S * (0.32 + j * 0.06), S * (0.46 - j * 0.12), S * (0.1 + j * 0.16)) * CFrame.Angles(0, math.rad(-20 * sx), math.rad(30 * sx)), Color3.fromRGB(220, 245, 255), Enum.Material.Glass)
			wing.Transparency = 0.35
		end
	end
	antennae(add, S, BLACK)
	triangle(add, "Stinger", S * 0.14, S * 0.22, S * 0.1, CFrame.new(0, -S * 0.02, S * 0.56) * CFrame.Angles(math.rad(90), 0, 0), BLACK)
end

function PET_FEATURES.Ladybug(add, S, c, dark)
	add("ShellLine", "Block", Vector3.new(S * 0.04, S * 0.5, S * 0.9), CFrame.new(0, S * 0.3, S * 0.08) * CFrame.Angles(math.rad(-20), 0, 0), BLACK)
	for i, p in ipairs({ { 0.24, 0.36, 0.05 }, { -0.24, 0.36, 0.05 }, { 0.3, 0.12, 0.3 }, { -0.3, 0.12, 0.3 }, { 0.14, 0.28, 0.36 }, { -0.14, 0.28, 0.36 } }) do
		add("ShellDot", "Blob", Vector3.new(S * 0.2, S * 0.2, S * 0.08), CFrame.lookAt(Vector3.new(p[1], p[2], p[3]) * S, Vector3.new(p[1], p[2], p[3]) * S * 2), BLACK)
	end
	add("Head", "Blob", Vector3.new(S * 0.7, S * 0.3, S * 0.2), CFrame.new(0, S * 0.34, -S * 0.36), BLACK)
	antennae(add, S, BLACK)
end

function PET_FEATURES.Snail(add, S, c, dark)
	local shell = c:Lerp(Color3.fromRGB(190, 120, 80), 0.5)
	add("Shell", "Ball", Vector3.one * S * 0.86, CFrame.new(0, S * 0.42, S * 0.28), shell)
	for i = 0, 9 do
		local a = i * 0.75
		local r = S * (0.36 - i * 0.03)
		add("Spiral", "Ball", Vector3.one * S * (0.16 - i * 0.008), CFrame.new(S * 0.42, S * 0.42 + math.sin(a) * r, S * 0.28 + math.cos(a) * r), shell:Lerp(BLACK, 0.25))
		add("Spiral", "Ball", Vector3.one * S * (0.16 - i * 0.008), CFrame.new(-S * 0.42, S * 0.42 + math.sin(a) * r, S * 0.28 + math.cos(a) * r), shell:Lerp(BLACK, 0.25))
	end
	add("Foot", "Blob", Vector3.new(S * 0.8, S * 0.2, S * 1.5), CFrame.new(0, -S * 0.42, S * 0.2), c:Lerp(WHITE, 0.2))
	for _, sx in ipairs({ -1, 1 }) do
		add("Stalk", "Block", Vector3.new(S * 0.06, S * 0.34, S * 0.06), CFrame.new(sx * S * 0.14, S * 0.56, -S * 0.26) * CFrame.Angles(0, 0, math.rad(-12 * sx)), c)
		add("StalkBall", "Ball", Vector3.one * S * 0.12, CFrame.new(sx * S * 0.18, S * 0.74, -S * 0.26), c)
	end
end

function PET_FEATURES.Crab(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Arm", "Blob", Vector3.new(S * 0.36, S * 0.14, S * 0.14), CFrame.new(sx * S * 0.6, -S * 0.02, -S * 0.2) * CFrame.Angles(0, math.rad(30 * sx), math.rad(25 * sx)), c)
		add("Claw", "Blob", Vector3.new(S * 0.34, S * 0.3, S * 0.26), CFrame.new(sx * S * 0.8, S * 0.14, -S * 0.36), c)
		add("Pincer", "Wedge", Vector3.new(S * 0.14, S * 0.14, S * 0.26), CFrame.new(sx * S * 0.8, S * 0.3, -S * 0.52), c:Lerp(WHITE, 0.25))
		add("Pincer", "Wedge", Vector3.new(S * 0.14, S * 0.1, S * 0.22), CFrame.new(sx * S * 0.8, S * 0.06, -S * 0.52) * CFrame.Angles(0, 0, math.pi), c:Lerp(WHITE, 0.25))
		for j = 0, 2 do
			add("CrabLeg", "Blob", Vector3.new(S * 0.36, S * 0.08, S * 0.08), CFrame.new(sx * S * 0.52, -S * 0.3, S * (0.02 + j * 0.16)) * CFrame.Angles(0, 0, math.rad(-35 * sx)), dark)
		end
		add("Stalk", "Block", Vector3.new(S * 0.06, S * 0.28, S * 0.06), CFrame.new(sx * S * 0.2, S * 0.5, -S * 0.3), c)
	end
end

function PET_FEATURES.Pig(add, S, c, dark)
	local pink = c:Lerp(Color3.fromRGB(255, 130, 160), 0.35)
	add("Snout", "Cyl", Vector3.new(S * 0.14, S * 0.3, S * 0.3), CFrame.new(0, -S * 0.06, -S * 0.5) * CFrame.Angles(0, math.rad(90), 0), pink)
	for _, sx in ipairs({ -1, 1 }) do
		add("Nostril", "Blob", Vector3.new(S * 0.06, S * 0.09, S * 0.04), CFrame.new(sx * S * 0.06, -S * 0.06, -S * 0.575), pink:Lerp(BLACK, 0.45))
		local ear = CFrame.new(sx * S * 0.27, S * 0.48, -S * 0.06) * CFrame.Angles(math.rad(-30), 0, math.rad(-25 * sx))
		triangle(add, "Ear", S * 0.26, S * 0.26, S * 0.06, ear, c)
		triangle(add, "InnerEar", S * 0.14, S * 0.14, S * 0.03, ear * CFrame.new(0, -S * 0.03, -S * 0.04), pink)
	end
	for i = 0, 3 do
		local a = i * 1.4
		add("CurlyTail", "Ball", Vector3.one * S * 0.08, CFrame.new(math.cos(a) * S * 0.08, S * 0.08 + math.sin(a) * S * 0.08, S * 0.52 + i * S * 0.02), pink)
	end
end

function PET_FEATURES.Sheep(add, S, c, dark)
	local wool = c:Lerp(WHITE, 0.55)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local y = if i % 2 == 0 then S * 0.34 else S * 0.18
		add("Wool", "Ball", Vector3.one * S * 0.36, CFrame.new(math.cos(a) * S * 0.4, y, math.sin(a) * S * 0.36 + S * 0.08), wool)
	end
	add("WoolTop", "Ball", Vector3.one * S * 0.42, CFrame.new(0, S * 0.5, S * 0.02), wool)
	add("Face", "Blob", Vector3.new(S * 0.62, S * 0.62, S * 0.22), CFrame.new(0, -S * 0.02, -S * 0.36), c:Lerp(Color3.fromRGB(255, 225, 200), 0.4))
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Blob", Vector3.new(S * 0.3, S * 0.12, S * 0.14), CFrame.new(sx * S * 0.44, S * 0.12, -S * 0.2) * CFrame.Angles(0, 0, math.rad(-25 * sx)), dark)
	end
end

function PET_FEATURES.Cow(add, S, c, dark)
	snout(add, S, Color3.fromRGB(255, 190, 200), Color3.fromRGB(200, 110, 130), true)
	for _, sx in ipairs({ -1, 1 }) do
		add("Horn", "Blob", Vector3.new(S * 0.1, S * 0.24, S * 0.1), CFrame.new(sx * S * 0.2, S * 0.54, -S * 0.02) * CFrame.Angles(0, 0, math.rad(-20 * sx)), Color3.fromRGB(245, 235, 210))
		add("Ear", "Blob", Vector3.new(S * 0.3, S * 0.12, S * 0.16), CFrame.new(sx * S * 0.46, S * 0.26, -S * 0.04) * CFrame.Angles(0, 0, math.rad(-15 * sx)), c)
	end
	for _, p in ipairs({ { 0.3, 0.25, 0.1 }, { -0.25, 0.1, 0.3 }, { 0.05, 0.4, 0.3 } }) do
		add("CowPatch", "Blob", Vector3.new(S * 0.36, S * 0.3, S * 0.1), CFrame.lookAt(Vector3.new(p[1], p[2], p[3]) * S, Vector3.new(p[1], p[2], p[3]) * S * 2), BLACK)
	end
	add("Bell", "Ball", Vector3.one * S * 0.15, CFrame.new(0, -S * 0.36, -S * 0.42), GOLD, Enum.Material.Metal)
	add("Collar", "Cyl", Vector3.new(S * 0.08, S * 0.84, S * 0.84), CFrame.new(0, -S * 0.26, -S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 60, 40), Enum.Material.Fabric)
	add("Tail", "Blob", Vector3.new(S * 0.06, S * 0.4, S * 0.06), CFrame.new(0, S * 0.02, S * 0.5) * CFrame.Angles(math.rad(-15), 0, 0), c)
	add("TailTuft", "Ball", Vector3.one * S * 0.12, CFrame.new(0, -S * 0.18, S * 0.54), BLACK)
end

function PET_FEATURES.Hedgehog(add, S, c, dark)
	local spike = c:Lerp(BLACK, 0.35)
	for i = 0, 17 do
		local yaw = (i % 6) / 5 * math.rad(200) - math.rad(100)
		local pitch = math.rad(-10 + (i // 6) * 32)
		local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
		local pos = Vector3.new(dir.X * S * 0.46, dir.Y * S * 0.44, dir.Z * S * 0.44)
		add("Spike", "Blob", Vector3.new(S * 0.12, S * 0.12, S * 0.42), CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -S * 0.12), spike)
	end
	add("Snout", "Blob", Vector3.new(S * 0.26, S * 0.2, S * 0.32), CFrame.new(0, -S * 0.1, -S * 0.5), c:Lerp(WHITE, 0.5))
	add("Nose", "Ball", Vector3.one * S * 0.1, CFrame.new(0, -S * 0.07, -S * 0.66), BLACK)
	roundEars(add, S, c:Lerp(WHITE, 0.3))
end

function PET_FEATURES.Elephant(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Ear", "Cyl", Vector3.new(S * 0.06, S * 0.62, S * 0.54), CFrame.new(sx * S * 0.52, S * 0.06, S * 0.05) * CFrame.Angles(0, math.rad(15 * sx), 0), c)
		add("InnerEar", "Cyl", Vector3.new(S * 0.05, S * 0.44, S * 0.38), CFrame.new(sx * S * 0.5, S * 0.06, S * 0.02) * CFrame.Angles(0, math.rad(15 * sx), 0), BLUSH)
		add("Tusk", "Blob", Vector3.new(S * 0.07, S * 0.07, S * 0.26), CFrame.new(sx * S * 0.13, -S * 0.2, -S * 0.52) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(250, 245, 230))
	end
	for i = 0, 3 do
		add("Trunk", "Ball", Vector3.one * S * (0.2 - i * 0.025), CFrame.new(0, -S * (0.06 + i * 0.12), -S * (0.52 + i * 0.05 - (if i == 3 then 0.08 else 0))), c)
	end
	add("Tail", "Blob", Vector3.new(S * 0.05, S * 0.3, S * 0.05), CFrame.new(0, 0, S * 0.5) * CFrame.Angles(math.rad(-20), 0, 0), dark)
end

function PET_FEATURES.Shark(add, S, c, dark)
	triangle(add, "DorsalFin", S * 0.44, S * 0.44, S * 0.08, CFrame.new(0, S * 0.62, S * 0.1) * CFrame.Angles(math.rad(-15), math.rad(90), 0), c)
	for _, sy in ipairs({ -1, 1 }) do
		add("TailFin", "Blob", Vector3.new(S * 0.08, S * 0.5, S * 0.26), CFrame.new(0, sy * S * 0.18, S * 0.66) * CFrame.Angles(math.rad(40 * sy), 0, 0), c)
	end
	for _, sx in ipairs({ -1, 1 }) do
		add("SideFin", "Blob", Vector3.new(S * 0.06, S * 0.3, S * 0.4), CFrame.new(sx * S * 0.5, -S * 0.2, S * 0.02) * CFrame.Angles(0, math.rad(20 * sx), math.rad(-45 * sx)), dark)
		for j = 0, 2 do
			add("Gill", "Block", Vector3.new(S * 0.03, S * 0.2, S * 0.03), CFrame.new(sx * S * 0.46, 0, -S * (0.02 + j * 0.07)) * CFrame.Angles(0, 0, math.rad(8 * sx)), dark)
		end
	end
	for i = -2, 2 do
		triangle(add, "Tooth", S * 0.07, S * 0.08, S * 0.03, CFrame.new(i * S * 0.06, -S * 0.18, -S * 0.46) * CFrame.Angles(0, 0, math.pi), WHITE)
	end
	add("WhiteBelly", "Blob", Vector3.new(S * 0.7, S * 0.36, S * 0.8), CFrame.new(0, -S * 0.3, 0), c:Lerp(WHITE, 0.75))
end

function PET_FEATURES.Ghost(add, S, c, dark)
	for i = -1, 1 do
		add("Wisp", "Blob", Vector3.new(S * 0.3, S * 0.4, S * 0.3), CFrame.new(i * S * 0.28, -S * 0.5, S * 0.05 + math.abs(i) * S * 0.05) * CFrame.Angles(0, 0, math.rad(i * 15)), c)
	end
	add("WispTail", "Blob", Vector3.new(S * 0.24, S * 0.2, S * 0.5), CFrame.new(0, -S * 0.3, S * 0.5) * CFrame.Angles(math.rad(30), 0, 0), c)
	for _, sx in ipairs({ -1, 1 }) do
		add("Arm", "Blob", Vector3.new(S * 0.3, S * 0.14, S * 0.14), CFrame.new(sx * S * 0.52, -S * 0.02, -S * 0.08) * CFrame.Angles(0, 0, math.rad(-30 * sx)), c)
	end
	local glow = add("Glow", "Blob", Vector3.new(S * 1.08, S * 1.02, S * 1.02), CFrame.new(), c:Lerp(WHITE, 0.5), Enum.Material.ForceField)
	glow.Transparency = 0.4
end

function PET_FEATURES.Robot(add, S, c, dark)
	local metal = c:Lerp(Color3.fromRGB(200, 205, 215), 0.3)
	add("Antenna", "Block", Vector3.new(S * 0.05, S * 0.3, S * 0.05), CFrame.new(0, S * 0.6, 0), metal:Lerp(BLACK, 0.3), Enum.Material.Metal)
	add("AntennaLight", "Ball", Vector3.one * S * 0.14, CFrame.new(0, S * 0.78, 0), Color3.fromRGB(255, 80, 90), Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		add("EarBolt", "Cyl", Vector3.new(S * 0.14, S * 0.22, S * 0.22), CFrame.new(sx * S * 0.5, S * 0.08, 0), metal:Lerp(BLACK, 0.2), Enum.Material.Metal)
		add("EarLight", "Cyl", Vector3.new(S * 0.04, S * 0.12, S * 0.12), CFrame.new(sx * S * 0.58, S * 0.08, 0), Color3.fromRGB(90, 220, 255), Enum.Material.Neon)
		add("Arm", "Blob", Vector3.new(S * 0.14, S * 0.4, S * 0.14), CFrame.new(sx * S * 0.5, -S * 0.2, -S * 0.08) * CFrame.Angles(0, 0, math.rad(15 * sx)), metal, Enum.Material.Metal)
	end
	add("Panel", "Block", Vector3.new(S * 0.4, S * 0.16, S * 0.05), CFrame.new(0, -S * 0.3, -S * 0.42) * CFrame.Angles(math.rad(-15), 0, 0), metal:Lerp(BLACK, 0.4), Enum.Material.Metal)
	for i, col in ipairs({ Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 80), Color3.fromRGB(90, 255, 140) }) do
		add("PanelLight", "Ball", Vector3.one * S * 0.07, CFrame.new((i - 2) * S * 0.11, -S * 0.3, -S * 0.45), col, Enum.Material.Neon)
	end
	for _, y in ipairs({ 0.34, -0.04 }) do
		add("Rivet", "Ball", Vector3.one * S * 0.06, CFrame.new(S * 0.3, S * y, S * 0.3), metal:Lerp(WHITE, 0.3), Enum.Material.Metal)
		add("Rivet", "Ball", Vector3.one * S * 0.06, CFrame.new(-S * 0.3, S * y, S * 0.3), metal:Lerp(WHITE, 0.3), Enum.Material.Metal)
	end
end

function PET_FEATURES.Star(add, S, c, dark)
	for i = 0, 4 do
		local a = math.rad(90 + i * 72)
		local cf = CFrame.new(math.cos(a) * S * 0.55, math.sin(a) * S * 0.55, S * 0.06) * CFrame.Angles(0, 0, a - math.rad(90))
		triangle(add, "StarPoint", S * 0.4, S * 0.42, S * 0.3, cf, c)
		add("PointGlow", "Ball", Vector3.one * S * 0.1, CFrame.new(math.cos(a) * S * 0.74, math.sin(a) * S * 0.74, S * 0.06), c:Lerp(WHITE, 0.6), Enum.Material.Neon)
	end
	add("Twinkle", "Ball", Vector3.one * S * 0.08, CFrame.new(S * 0.55, S * 0.7, -S * 0.1), WHITE, Enum.Material.Neon)
end

function PET_FEATURES.Cactus(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Arm", "Blob", Vector3.new(S * 0.3, S * 0.18, S * 0.18), CFrame.new(sx * S * 0.56, -S * 0.02, 0), c)
		add("ArmUp", "Blob", Vector3.new(S * 0.18, S * 0.42, S * 0.18), CFrame.new(sx * S * 0.66, S * 0.16, 0), c)
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("Needle", "Block", Vector3.new(S * 0.03, S * 0.03, S * 0.12), CFrame.new(math.cos(a) * S * 0.49, S * (0.3 - (i % 3) * 0.2), math.sin(a) * S * 0.47 + S * 0.05) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(250, 245, 220))
	end
	add("Rib", "Block", Vector3.new(S * 0.04, S * 0.8, S * 0.04), CFrame.new(0, 0, S * 0.47), dark)
	add("TopFlower", "Ball", Vector3.one * S * 0.14, CFrame.new(0, S * 0.52, 0), Color3.fromRGB(255, 220, 80))
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("Petal", "Blob", Vector3.new(S * 0.16, S * 0.06, S * 0.1), CFrame.new(math.cos(a) * S * 0.12, S * 0.52, math.sin(a) * S * 0.12) * CFrame.Angles(0, -a, 0), Color3.fromRGB(255, 110, 170))
	end
	add("Pot", "Cyl", Vector3.new(S * 0.36, S * 0.9, S * 0.9), CFrame.new(0, -S * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 110, 70))
end

function PET_FEATURES.Lion(add, S, c, dark)
	local mane = c:Lerp(Color3.fromRGB(150, 70, 20), 0.55)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		add("Mane", "Ball", Vector3.one * S * 0.34, CFrame.new(math.cos(a) * S * 0.46, S * 0.06 + math.sin(a) * S * 0.44, -S * 0.1), if i % 2 == 0 then mane else mane:Lerp(BLACK, 0.15))
	end
	roundEars(add, S, c)
	snout(add, S, c:Lerp(WHITE, 0.5), Color3.fromRGB(120, 70, 60))
	add("Tail", "Blob", Vector3.new(S * 0.06, S * 0.5, S * 0.06), CFrame.new(0, S * 0.1, S * 0.52) * CFrame.Angles(math.rad(-40), 0, 0), c)
	add("TailTuft", "Ball", Vector3.one * S * 0.16, CFrame.new(0, S * 0.32, S * 0.7), mane)
end

function PET_FEATURES.Raccoon(add, S, c, dark)
	add("Mask", "Blob", Vector3.new(S * 0.78, S * 0.26, S * 0.2), CFrame.new(0, S * 0.12, -S * 0.36), BLACK)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.28, S * 0.5, S * 0.24, S * 0.26, c)
	end
	snout(add, S, c:Lerp(WHITE, 0.65))
	for i = 0, 5 do
		add("TailRing", "Ball", Vector3.one * S * (0.26 - i * 0.015), CFrame.new(0, S * (0.02 + i * 0.1), S * (0.5 + i * 0.07)), if i % 2 == 0 then c else BLACK)
	end
end

function PET_FEATURES.Wolf(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		pointyEar(add, S, sx, S * 0.25, S * 0.56, S * 0.26, S * 0.38, c, dark)
	end
	add("Snout", "Blob", Vector3.new(S * 0.32, S * 0.24, S * 0.4), CFrame.new(0, -S * 0.1, -S * 0.5), c:Lerp(WHITE, 0.4))
	add("Nose", "Blob", Vector3.new(S * 0.14, S * 0.09, S * 0.08), CFrame.new(0, -S * 0.02, -S * 0.7), BLACK)
	add("Ruff", "Blob", Vector3.new(S * 0.7, S * 0.36, S * 0.3), CFrame.new(0, -S * 0.28, -S * 0.32), c:Lerp(WHITE, 0.5))
	fluffyTail(add, S, c)
end

function PET_FEATURES.Bear(add, S, c, dark)
	roundEars(add, S, c, c:Lerp(WHITE, 0.4))
	snout(add, S, c:Lerp(WHITE, 0.45))
	add("BellyPatch", "Blob", Vector3.new(S * 0.5, S * 0.5, S * 0.12), CFrame.new(0, -S * 0.18, -S * 0.43), c:Lerp(WHITE, 0.35))
	add("Tail", "Ball", Vector3.one * S * 0.18, CFrame.new(0, -S * 0.05, S * 0.48), c)
end

function PET_FEATURES.Seal(add, S, c, dark)
	for _, sx in ipairs({ -1, 1 }) do
		add("Flipper", "Blob", Vector3.new(S * 0.36, S * 0.08, S * 0.2), CFrame.new(sx * S * 0.46, -S * 0.36, -S * 0.1) * CFrame.Angles(0, math.rad(-20 * sx), math.rad(-15 * sx)), dark)
		add("TailFlipper", "Blob", Vector3.new(S * 0.3, S * 0.06, S * 0.26), CFrame.new(sx * S * 0.14, -S * 0.4, S * 0.6) * CFrame.Angles(0, math.rad(25 * sx), 0), dark)
		for j = 0, 2 do
			add("Whisker", "Block", Vector3.new(S * 0.26, S * 0.015, S * 0.015), CFrame.new(sx * S * 0.3, -S * 0.08 - j * S * 0.04, -S * 0.46) * CFrame.Angles(0, 0, math.rad((10 - j * 12) * sx)), WHITE)
		end
	end
	add("Muzzle", "Blob", Vector3.new(S * 0.36, S * 0.22, S * 0.18), CFrame.new(0, -S * 0.1, -S * 0.46), c:Lerp(WHITE, 0.4))
	add("Nose", "Blob", Vector3.new(S * 0.14, S * 0.08, S * 0.08), CFrame.new(0, -S * 0.02, -S * 0.55), BLACK)
	add("Spot", "Blob", Vector3.new(S * 0.2, S * 0.16, S * 0.06), CFrame.new(S * 0.3, S * 0.3, S * 0.25) * CFrame.Angles(0, math.rad(60), 0), dark)
end

function PET_FEATURES.Octopus(add, S, c, dark)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local base = CFrame.new(math.cos(a) * S * 0.34, -S * 0.34, math.sin(a) * S * 0.34) * CFrame.Angles(0, -a + math.pi / 2, 0)
		add("Tentacle", "Blob", Vector3.new(S * 0.16, S * 0.16, S * 0.6), base * CFrame.Angles(math.rad(-30), 0, 0) * CFrame.new(0, 0, S * 0.1), c)
		add("TentacleCurl", "Ball", Vector3.one * S * 0.14, base * CFrame.new(0, S * 0.1, S * 0.38), dark)
	end
	for _, p in ipairs({ { 0.25, 0.35, 0.15 }, { -0.28, 0.3, 0.2 }, { 0, 0.44, 0.25 }, { 0.18, 0.1, 0.4 } }) do
		add("HeadSpot", "Blob", Vector3.new(S * 0.14, S * 0.14, S * 0.05), CFrame.lookAt(Vector3.new(p[1], p[2], p[3]) * S, Vector3.new(p[1], p[2], p[3]) * S * 2), c:Lerp(WHITE, 0.35))
	end
end

--------------------------------------------------------------------------------
-- Patterns painted on a pet's back and sides (def.Pattern), and accessories
-- it wears (def.Accessory). Front (-Z) is the face, so patterns stay behind it.
--------------------------------------------------------------------------------
-- A point on the body surface: yaw 0 = straight back (+Z), pitch up = top.
local PATTERN_EXTENT = nil -- half size of the torso the pattern wraps (nil = round body of size S)
local function onBody(S, yawDeg, pitchDeg, lift)
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	local ext = PATTERN_EXTENT or Vector3.new(S * 0.5, S * 0.475, S * 0.475)
	local pos = Vector3.new(dir.X * ext.X, dir.Y * ext.Y, dir.Z * ext.Z) * (lift or 0.99)
	return CFrame.lookAt(pos, pos + dir)
end

local RAINBOW = { Color3.fromRGB(255, 70, 90), Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 235, 80), Color3.fromRGB(80, 220, 120), Color3.fromRGB(70, 160, 255), Color3.fromRGB(170, 90, 255) }

local SPOTS = { { 0, 30 }, { 50, 10 }, { -50, 10 }, { 90, 35 }, { -90, 35 }, { 20, 60 }, { -25, -10 }, { 120, 5 } }

local PATTERNS = {}
function PATTERNS.Spots(add, S, col, mat)
	for i, p in ipairs(SPOTS) do
		add("Pattern", "Blob", Vector3.new(S * (0.2 + (i % 3) * 0.04), S * (0.18 + (i % 2) * 0.04), S * 0.05), onBody(S, p[1], p[2]), col, mat)
	end
end
function PATTERNS.Patches(add, S, col, mat)
	for _, p in ipairs({ { 30, 25 }, { -70, 5 }, { 110, 40 } }) do
		add("Pattern", "Blob", Vector3.new(S * 0.42, S * 0.34, S * 0.06), onBody(S, p[1], p[2]), col, mat)
	end
end
function PATTERNS.Stripes(add, S, col, mat)
	for i = -2, 2 do
		add("Pattern", "Blob", Vector3.new(S * 0.08, S * 0.5, S * 0.05), onBody(S, i * 28, 25) * CFrame.Angles(0, 0, math.rad(i * 8)), col, mat)
	end
end
local function starShape(add, cf, size, col, mat)
	add("Pattern", "Block", Vector3.new(size, size * 0.3, size * 0.2), cf, col, mat)
	add("Pattern", "Block", Vector3.new(size * 0.3, size, size * 0.2), cf, col, mat)
	add("Pattern", "Block", Vector3.new(size * 0.55, size * 0.55, size * 0.2), cf * CFrame.Angles(0, 0, math.rad(45)), col, mat)
end
function PATTERNS.Stars(add, S, col, mat)
	for i, p in ipairs({ { 0, 30 }, { 70, 15 }, { -70, 15 }, { 25, 60 } }) do
		starShape(add, onBody(S, p[1], p[2]), S * (if i == 1 then 0.2 else 0.14), col, mat)
	end
end
function PATTERNS.Hearts(add, S, col, mat)
	for _, p in ipairs({ { 0, 25 }, { 75, 10 }, { -75, 10 } }) do
		local cf = onBody(S, p[1], p[2])
		add("Pattern", "Ball", Vector3.new(S * 0.12, S * 0.12, S * 0.06), cf * CFrame.new(-S * 0.045, S * 0.03, 0), col, mat)
		add("Pattern", "Ball", Vector3.new(S * 0.12, S * 0.12, S * 0.06), cf * CFrame.new(S * 0.045, S * 0.03, 0), col, mat)
		add("Pattern", "Block", Vector3.new(S * 0.11, S * 0.11, S * 0.05), cf * CFrame.new(0, -S * 0.02, 0) * CFrame.Angles(0, 0, math.rad(45)), col, mat)
	end
end
function PATTERNS.Gems(add, S, col, mat)
	for i, p in ipairs({ { 0, 35 }, { 45, 15 }, { -45, 15 }, { 90, 30 }, { -90, 30 } }) do
		add("Pattern", "Block", Vector3.new(S * 0.1, S * 0.1, S * 0.1), onBody(S, p[1], p[2], 1.02) * CFrame.Angles(0, 0, math.rad(45)), RAINBOW[(i % #RAINBOW) + 1]:Lerp(col, 0.4), Enum.Material.Neon)
	end
end
function PATTERNS.Swirl(add, S, col, mat)
	for i = 0, 11 do
		local a = i * 0.8
		local r = 8 + i * 4
		add("Pattern", "Ball", Vector3.new(S * 0.09, S * 0.09, S * 0.04), onBody(S, math.cos(a) * r, 25 + math.sin(a) * r), col, mat)
	end
end
function PATTERNS.Pixels(add, S, col, mat)
	local cyan, magenta = Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 60, 200)
	for i = 0, 9 do
		add("Pattern", "Block", Vector3.new(S * 0.12, S * 0.07, S * 0.1), onBody(S, -120 + i * 27, ((i * 37) % 70) - 10, 1.03), if i % 2 == 0 then cyan else magenta, Enum.Material.Neon)
	end
end
function PATTERNS.Rainbow(add, S, col, mat)
	for i, rc in ipairs(RAINBOW) do
		add("Pattern", "Blob", Vector3.new(S * 0.95, S * 0.07, S * 0.05), onBody(S, 0, -15 + i * 11) * CFrame.Angles(0, 0, 0), rc, Enum.Material.Neon)
	end
end
function PATTERNS.Freckles(add, S, col, mat)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			add("Pattern", "Ball", Vector3.one * S * 0.04, CFrame.new(sx * S * (0.26 + j * 0.05), -S * (0.03 + (j % 2) * 0.03), -S * 0.43), col, mat)
		end
	end
end

local ACCESSORY_COLORS = {
	Bow = Color3.fromRGB(255, 90, 140), TopHat = Color3.fromRGB(220, 50, 60), PartyHat = Color3.fromRGB(90, 160, 255),
	WizardHat = Color3.fromRGB(90, 70, 200), Beanie = Color3.fromRGB(230, 70, 70), Tiara = GOLD, Halo = GOLD,
	Scarf = Color3.fromRGB(220, 60, 70), Bandana = Color3.fromRGB(220, 50, 50), Shades = BLACK, Glasses = Color3.fromRGB(70, 45, 30),
	Headphones = Color3.fromRGB(255, 90, 120), Flower = Color3.fromRGB(255, 120, 180), Leaf = Color3.fromRGB(90, 190, 70),
	Horns = Color3.fromRGB(250, 240, 220), Antenna = BLACK, Bell = GOLD, Cape = Color3.fromRGB(200, 40, 60),
}

local ACCESSORIES = {}
function ACCESSORIES.Bow(add, S, a)
	local cf = CFrame.new(S * 0.24, S * 0.46, -S * 0.08) * CFrame.Angles(0, 0, math.rad(-20))
	add("Bow", "Blob", Vector3.new(S * 0.22, S * 0.16, S * 0.08), cf * CFrame.new(-S * 0.1, 0, 0) * CFrame.Angles(0, 0, math.rad(15)), a)
	add("Bow", "Blob", Vector3.new(S * 0.22, S * 0.16, S * 0.08), cf * CFrame.new(S * 0.1, 0, 0) * CFrame.Angles(0, 0, math.rad(-15)), a)
	add("BowKnot", "Ball", Vector3.one * S * 0.09, cf, a:Lerp(BLACK, 0.15))
end
function ACCESSORIES.TopHat(add, S, a)
	add("HatBrim", "Cyl", Vector3.new(S * 0.04, S * 0.6, S * 0.6), CFrame.new(0, S * 0.47, 0) * CFrame.Angles(0, 0, math.rad(90)), BLACK)
	add("Hat", "Cyl", Vector3.new(S * 0.4, S * 0.4, S * 0.4), CFrame.new(0, S * 0.68, 0) * CFrame.Angles(0, 0, math.rad(90)), BLACK)
	add("HatBand", "Cyl", Vector3.new(S * 0.08, S * 0.41, S * 0.41), CFrame.new(0, S * 0.54, 0) * CFrame.Angles(0, 0, math.rad(90)), a)
end
local function cone(add, name, S, baseY, height, radius, color, tilt, bands)
	for i = 0, 4 do
		local f = 1 - i / 5
		add(name, "Cyl", Vector3.new(height / 5, radius * 2 * f, radius * 2 * f), tilt * CFrame.new(0, baseY + height * (i + 0.5) / 5, 0) * CFrame.Angles(0, 0, math.rad(90)), if bands and i % 2 == 1 then bands else color)
	end
	return tilt * CFrame.new(0, baseY + height, 0)
end
function ACCESSORIES.PartyHat(add, S, a)
	local tip = cone(add, "PartyHat", S, S * 0.44, S * 0.5, S * 0.2, a, CFrame.Angles(0, 0, math.rad(-12)), WHITE)
	add("PomPom", "Ball", Vector3.one * S * 0.12, tip, Color3.fromRGB(255, 230, 90))
end
function ACCESSORIES.WizardHat(add, S, a)
	add("HatBrim", "Cyl", Vector3.new(S * 0.04, S * 0.75, S * 0.75), CFrame.new(0, S * 0.46, 0) * CFrame.Angles(0, 0, math.rad(90)), a)
	local tip = cone(add, "WizardHat", S, S * 0.46, S * 0.62, S * 0.26, a, CFrame.Angles(math.rad(8), 0, math.rad(-10)))
	starShape(add, CFrame.new(0, S * 0.62, -S * 0.19), S * 0.12, GOLD, Enum.Material.Neon)
	add("HatTip", "Ball", Vector3.one * S * 0.06, tip, GOLD, Enum.Material.Neon)
end
function ACCESSORIES.Beanie(add, S, a)
	add("Beanie", "Blob", Vector3.new(S * 0.8, S * 0.42, S * 0.8), CFrame.new(0, S * 0.36, S * 0.02), a)
	add("BeanieRim", "Cyl", Vector3.new(S * 0.1, S * 0.84, S * 0.84), CFrame.new(0, S * 0.26, S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), a:Lerp(WHITE, 0.4))
	add("PomPom", "Ball", Vector3.one * S * 0.18, CFrame.new(0, S * 0.6, S * 0.02), WHITE)
end
function ACCESSORIES.Tiara(add, S, a)
	add("Tiara", "Cyl", Vector3.new(S * 0.05, S * 0.56, S * 0.56), CFrame.new(0, S * 0.46, 0) * CFrame.Angles(0, 0, math.rad(90)), a, Enum.Material.Metal)
	for i = -1, 1 do
		triangle(add, "TiaraSpike", S * 0.1, S * (if i == 0 then 0.2 else 0.14), S * 0.03, CFrame.new(i * S * 0.12, S * 0.54, -S * 0.26), a, Enum.Material.Metal)
	end
	add("TiaraGem", "Ball", Vector3.one * S * 0.08, CFrame.new(0, S * 0.52, -S * 0.29), Color3.fromRGB(255, 70, 130), Enum.Material.Neon)
end
function ACCESSORIES.Halo(add, S, a)
	local halo = add("Halo", "Cyl", Vector3.new(S * 0.05, S * 0.56, S * 0.56), CFrame.new(0, S * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), a, Enum.Material.Neon)
	halo.Transparency = 0.1
end
function ACCESSORIES.Scarf(add, S, a)
	add("Scarf", "Cyl", Vector3.new(S * 0.16, S * 0.9, S * 0.9), CFrame.new(0, -S * 0.26, -S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), a, Enum.Material.Fabric)
	add("ScarfEnd", "Blob", Vector3.new(S * 0.16, S * 0.36, S * 0.06), CFrame.new(S * 0.2, -S * 0.4, -S * 0.44) * CFrame.Angles(0, 0, math.rad(10)), a, Enum.Material.Fabric)
	for i = 0, 1 do
		add("ScarfStripe", "Block", Vector3.new(S * 0.17, S * 0.04, S * 0.07), CFrame.new(S * 0.2, -S * (0.32 + i * 0.1), -S * 0.45) * CFrame.Angles(0, 0, math.rad(10)), WHITE, Enum.Material.Fabric)
	end
end
function ACCESSORIES.Bandana(add, S, a)
	add("Bandana", "Cyl", Vector3.new(S * 0.12, S * 0.92, S * 0.92), CFrame.new(0, S * 0.3, S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), a, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		add("BandanaTail", "Blob", Vector3.new(S * 0.08, S * 0.26, S * 0.06), CFrame.new(sx * S * 0.07, S * 0.2, S * 0.5) * CFrame.Angles(math.rad(20), 0, math.rad(25 * sx)), a, Enum.Material.Fabric)
	end
end
function ACCESSORIES.Shades(add, S, a)
	for _, sx in ipairs({ -1, 1 }) do
		add("Lens", "Blob", Vector3.new(S * 0.3, S * 0.2, S * 0.05), CFrame.new(sx * S * 0.2, S * 0.13, -S * 0.52), a, Enum.Material.Glass).Reflectance = 0.3
		add("Arm", "Block", Vector3.new(S * 0.03, S * 0.03, S * 0.4), CFrame.new(sx * S * 0.43, S * 0.16, -S * 0.3) * CFrame.Angles(0, math.rad(15 * sx), 0), a)
	end
	add("Bridge", "Block", Vector3.new(S * 0.12, S * 0.03, S * 0.03), CFrame.new(0, S * 0.18, -S * 0.53), a)
end
function ACCESSORIES.Glasses(add, S, a)
	for _, sx in ipairs({ -1, 1 }) do
		add("Frame", "Cyl", Vector3.new(S * 0.03, S * 0.3, S * 0.3), CFrame.new(sx * S * 0.2, S * 0.12, -S * 0.52) * CFrame.Angles(0, math.rad(90), 0), a)
		local lens = add("Lens", "Cyl", Vector3.new(S * 0.035, S * 0.25, S * 0.25), CFrame.new(sx * S * 0.2, S * 0.12, -S * 0.52) * CFrame.Angles(0, math.rad(90), 0), WHITE, Enum.Material.Glass)
		lens.Transparency = 0.7
	end
	add("Bridge", "Block", Vector3.new(S * 0.1, S * 0.03, S * 0.03), CFrame.new(0, S * 0.16, -S * 0.53), a)
end
function ACCESSORIES.Headphones(add, S, a)
	for i = -2, 2 do
		local ang = math.rad(i * 22)
		add("Band", "Block", Vector3.new(S * 0.18, S * 0.06, S * 0.12), CFrame.new(math.sin(ang) * S * 0.52, S * 0.1 + math.cos(ang) * S * 0.44, 0) * CFrame.Angles(0, 0, -ang), BLACK)
	end
	for _, sx in ipairs({ -1, 1 }) do
		add("Cup", "Cyl", Vector3.new(S * 0.14, S * 0.3, S * 0.3), CFrame.new(sx * S * 0.52, S * 0.08, 0), a)
		add("CupLight", "Cyl", Vector3.new(S * 0.03, S * 0.16, S * 0.16), CFrame.new(sx * S * 0.6, S * 0.08, 0), a:Lerp(WHITE, 0.5), Enum.Material.Neon)
	end
end
function ACCESSORIES.Flower(add, S, a)
	local center = CFrame.new(-S * 0.26, S * 0.44, -S * 0.12) * CFrame.Angles(math.rad(-20), 0, math.rad(20))
	add("FlowerCenter", "Ball", Vector3.one * S * 0.1, center, Color3.fromRGB(255, 220, 80))
	for i = 0, 4 do
		local ang = i / 5 * math.pi * 2
		add("Petal", "Blob", Vector3.new(S * 0.12, S * 0.05, S * 0.08), center * CFrame.new(math.cos(ang) * S * 0.09, 0, math.sin(ang) * S * 0.09) * CFrame.Angles(0, -ang, 0), a)
	end
end
function ACCESSORIES.Leaf(add, S, a)
	add("LeafStem", "Block", Vector3.new(S * 0.04, S * 0.16, S * 0.04), CFrame.new(0, S * 0.54, 0), a:Lerp(BLACK, 0.3))
	add("Leaf", "Blob", Vector3.new(S * 0.36, S * 0.06, S * 0.18), CFrame.new(S * 0.12, S * 0.62, 0) * CFrame.Angles(0, 0, math.rad(25)), a)
end
function ACCESSORIES.Horns(add, S, a)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			add("Horn", "Blob", Vector3.new(S * (0.11 - j * 0.025), S * 0.14, S * (0.11 - j * 0.025)), CFrame.new(sx * S * (0.22 + j * 0.05), S * (0.46 + j * 0.1), -S * 0.05) * CFrame.Angles(0, 0, math.rad(-25 * sx)), a)
		end
	end
end
function ACCESSORIES.Antenna(add, S, a)
	antennae(add, S, a, Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
end
function ACCESSORIES.Bell(add, S, a)
	add("Collar", "Cyl", Vector3.new(S * 0.08, S * 0.86, S * 0.86), CFrame.new(0, -S * 0.26, -S * 0.02) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 60, 70), Enum.Material.Fabric)
	add("Bell", "Ball", Vector3.one * S * 0.15, CFrame.new(0, -S * 0.36, -S * 0.44), a, Enum.Material.Metal)
	add("BellSlit", "Block", Vector3.new(S * 0.1, S * 0.02, S * 0.02), CFrame.new(0, -S * 0.38, -S * 0.52), BLACK)
end
function ACCESSORIES.Cape(add, S, a)
	add("Cape", "Block", Vector3.new(S * 0.8, S * 0.7, S * 0.04), CFrame.new(0, -S * 0.08, S * 0.5) * CFrame.Angles(math.rad(-12), 0, 0), a, Enum.Material.Fabric)
	add("CapeClasp", "Ball", Vector3.one * S * 0.1, CFrame.new(0, S * 0.2, S * 0.47), GOLD, Enum.Material.Metal)
end

-- Shared by MakeCreature: pattern, accessory, and extra flair for rare pets
local function decorate(add, S, def, rarity, color, dark)
	if def and def.Pattern and PATTERNS[def.Pattern] then
		local glow = def.PatternGlow or rarity.Order >= 5
		local col = def.PatternColor or (if def.Pattern == "Stars" or def.Pattern == "Hearts" then color:Lerp(WHITE, 0.7) else dark)
		PATTERNS[def.Pattern](add, S, col, if glow then Enum.Material.Neon else nil)
	end
	if def and def.Accessory and ACCESSORIES[def.Accessory] then
		ACCESSORIES[def.Accessory](add, S, def.Accent or ACCESSORY_COLORS[def.Accessory] or GOLD)
	end
end

-- Pet name tag: "🌟 Golden Bunbun · Juvenile" / "+$3/s · 6.4 kg · grows 0:42"
function Visuals.RefreshPetLabel(body, data)
	local rarity = Config.RarityById[data.Rarity]
	local stage = Config.Stages[Config.PetStage(data)]
	local title = Config.CreatureTitle(data)
	if data.Shiny then
		title = "✨ " .. title
	end
	local mutation = data.Mutation and Config.MutationById[data.Mutation]
	if mutation then
		title = mutation.Icon .. " " .. title
	end
	if (data.Size or 1) >= 2 then
		title = "HUGE " .. title
	end
	title = title .. " · " .. stage.Name
	local sub = "+" .. Util.Money(Config.CreatureIncome(data)) .. "/s · " .. string.format("%.1f kg", Config.PetWeight(data))
	local grow = Config.TimeToGrow(data)
	if grow then
		sub = sub .. " · grows " .. Util.FormatTime(grow)
	end
	Visuals.SetLabel(body, title, sub, if mutation then mutation.Color else rarity.Color)
end

-- Detailed cartoon eye: white, colored iris, pupil, two shines and a lid line
local EYE_SCALE = 0.62 -- realistic eyes are much smaller than cartoon ones
local function petEye(add, cf, size, iris)
	size *= EYE_SCALE
	-- a thin rim of white around a big dark iris, a round pupil and one small
	-- catch-light, like a real animal's eye
	local irisColor = iris:Lerp(Color3.fromRGB(45, 30, 20), 0.55)
	add("Eye", "Blob", Vector3.new(size, size * 1.05, size * 0.8), cf, Color3.fromRGB(235, 230, 220))
	add("Iris", "Blob", Vector3.new(size * 0.9, size * 0.94, size * 0.6), cf * CFrame.new(0, 0, -size * 0.14), irisColor)
	add("Pupil", "Blob", Vector3.new(size * 0.5, size * 0.52, size * 0.5), cf * CFrame.new(0, 0, -size * 0.2), Color3.fromRGB(10, 8, 12))
	add("Shine", "Ball", Vector3.one * size * 0.16, cf * CFrame.new(size * 0.16, size * 0.18, -size * 0.36), WHITE, Enum.Material.Neon)
end

--------------------------------------------------------------------------------
-- Real animal shapes. Each species below builds a torso, a head with the
-- shared cartoon face, legs, a neck, ears and a tail in its own proportions,
-- so a dragon looks like a dragon and a bunny looks like a bunny.
-- Species not listed here (slimes, ghosts, ladybugs...) keep the round body.
-- Units are in S (the pet's size). The torso sits at the origin, facing -Z.
--------------------------------------------------------------------------------
local ANATOMY = {}
local ORANGE_FOOT = Color3.fromRGB(255, 160, 50)

-- Head with the cartoon face. Returns an `add` that works in head space.
local HEAD_SCALE = 0.85 -- smaller heads look more like real animals
local function makeHead(ctx, cf, H, color, opts)
	opts = opts or {}
	local add = ctx.add
	-- the whole head (and everything built on it) shrinks around its center;
	-- the shared four-legged body already sizes its heads, so it skips this
	local k = if opts.Real then 1 else HEAD_SCALE
	add("Head", "Blob", Vector3.new(H, H * 0.95, H * 0.95) * k, cf, color)
	local function headAdd(name, shape, size, localCf, col, mat)
		return add(name, shape, size * k, cf * CFrame.new(localCf.Position * k) * (localCf - localCf.Position), col, mat)
	end
	local eyeX, eyeY, eyeSize = (opts.EyeX or 0.21) * H, (opts.EyeY or 0.1) * H, (opts.EyeSize or 0.27) * H
	for _, sx in ipairs({ -1, 1 }) do
		petEye(headAdd, CFrame.new(sx * eyeX, eyeY, -H * 0.39) * CFrame.Angles(0, math.rad(-12 * sx), 0), eyeSize, ctx.iris)
		headAdd("Blush", "Blob", Vector3.new(H * 0.17, H * 0.09, H * 0.06), CFrame.new(sx * H * 0.33, -H * 0.05, -H * 0.41), BLUSH)
		if opts.Mouth ~= false then
			headAdd("Mouth", "Blob", Vector3.new(H * 0.1, H * 0.05, H * 0.05), CFrame.new(sx * H * 0.045, -H * 0.13, -H * 0.46) * CFrame.Angles(0, 0, math.rad(25 * sx)), BLACK)
		end
	end
	if opts.Fur then
		for i = -1, 1 do
			headAdd("Tuft", "Blob", Vector3.new(H * 0.12, H * 0.24, H * 0.12), CFrame.new(i * H * 0.07, H * 0.5, -H * 0.1) * CFrame.Angles(math.rad(-15), 0, math.rad(-i * 30)), color)
		end
	end
	ctx.headCf, ctx.H, ctx.headAdd = cf, H, headAdd
	return headAdd
end

local function snoutOn(headAdd, H, len, width, color, noseColor)
	local l = len * H
	headAdd("Snout", "Blob", Vector3.new(H * width, H * 0.34, l), CFrame.new(0, -H * 0.15, -H * 0.34 - l * 0.32), color)
	headAdd("Nose", "Blob", Vector3.new(H * 0.16, H * 0.11, H * 0.1), CFrame.new(0, -H * 0.05, -H * 0.36 - l * 0.8), noseColor or BLACK)
	headAdd("NoseShine", "Ball", Vector3.one * H * 0.04, CFrame.new(H * 0.03, -H * 0.02, -H * 0.4 - l * 0.8), WHITE)
	headAdd("Smile", "Blob", Vector3.new(H * 0.16, H * 0.04, H * 0.04), CFrame.new(0, -H * 0.28, -H * 0.36 - l * 0.55), BLACK)
end

local function earsOn(headAdd, H, kind, color, inner)
	inner = inner or BLUSH
	for _, sx in ipairs({ -1, 1 }) do
		if kind == "Pointy" or kind == "Tall" then
			local tall = kind == "Tall"
			pointyEar(headAdd, H, sx, H * 0.25, H * (if tall then 0.58 else 0.5), H * (if tall then 0.34 else 0.28), H * (if tall then 0.5 else 0.34), color, inner)
		elseif kind == "Round" then
			headAdd("Ear", "Ball", Vector3.one * H * 0.3, CFrame.new(sx * H * 0.34, H * 0.4, H * 0.02), color)
			headAdd("InnerEar", "Ball", Vector3.one * H * 0.17, CFrame.new(sx * H * 0.34, H * 0.4, -H * 0.08), inner)
		elseif kind == "Floppy" then
			headAdd("Ear", "Blob", Vector3.new(H * 0.22, H * 0.55, H * 0.14), CFrame.new(sx * H * 0.47, H * 0.0, 0) * CFrame.Angles(0, 0, math.rad(16 * sx)), color)
		elseif kind == "Long" then
			local cf = CFrame.new(sx * H * 0.17, H * 0.78, H * 0.06) * CFrame.Angles(math.rad(8), 0, math.rad(-10 * sx))
			headAdd("Ear", "Blob", Vector3.new(H * 0.22, H * 0.9, H * 0.13), cf, color)
			headAdd("InnerEar", "Blob", Vector3.new(H * 0.12, H * 0.66, H * 0.06), cf * CFrame.new(0, 0, -H * 0.06), inner)
		elseif kind == "Side" then
			headAdd("Ear", "Blob", Vector3.new(H * 0.32, H * 0.13, H * 0.18), CFrame.new(sx * H * 0.5, H * 0.18, 0) * CFrame.Angles(0, 0, math.rad(-20 * sx)), color)
		elseif kind == "Pig" then
			local cf = CFrame.new(sx * H * 0.27, H * 0.46, -H * 0.04) * CFrame.Angles(math.rad(-30), 0, math.rad(-25 * sx))
			triangle(headAdd, "Ear", H * 0.28, H * 0.28, H * 0.06, cf, color)
			triangle(headAdd, "InnerEar", H * 0.15, H * 0.15, H * 0.03, cf * CFrame.new(0, -H * 0.03, -H * 0.04), inner)
		end
	end
end

-- Tails start at `cf` (back of the torso) and point backwards (+Z)
local function tailOn(ctx, kind, cf, color)
	local S, add = ctx.S, ctx.add
	if kind == "Thin" then
		add("Tail", "Blob", Vector3.new(S * 0.1, S * 0.1, S * 0.6), cf * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0, S * 0.26), color)
	elseif kind == "Bushy" then
		add("Tail", "Blob", Vector3.new(S * 0.26, S * 0.26, S * 0.66), cf * CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, 0, S * 0.3), color)
		add("TailTip", "Blob", Vector3.new(S * 0.22, S * 0.22, S * 0.24), cf * CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, 0, S * 0.6), color:Lerp(WHITE, 0.65))
	elseif kind == "Fluff" then
		add("Tail", "Ball", Vector3.one * S * 0.24, cf * CFrame.new(0, 0, S * 0.06), color:Lerp(WHITE, 0.4))
	elseif kind == "Curly" then
		for i = 0, 4 do
			local a = i * 1.3
			add("CurlyTail", "Ball", Vector3.one * S * 0.08, cf * CFrame.new(math.cos(a) * S * 0.07, S * 0.05 + math.sin(a) * S * 0.07, S * (0.04 + i * 0.025)), color)
		end
	elseif kind == "Tuft" then
		add("Tail", "Blob", Vector3.new(S * 0.07, S * 0.07, S * 0.6), cf * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, S * 0.28), color)
		add("TailTuft", "Ball", Vector3.one * S * 0.17, cf * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, S * 0.6), color:Lerp(BLACK, 0.35))
	elseif kind == "Flame" then
		add("Tail", "Blob", Vector3.new(S * 0.1, S * 0.1, S * 0.6), cf * CFrame.Angles(math.rad(45), 0, 0) * CFrame.new(0, 0, S * 0.26), color)
		local tip = cf * CFrame.Angles(math.rad(45), 0, 0) * CFrame.new(0, 0, S * 0.58)
		add("TailFlame", "Blob", Vector3.new(S * 0.26, S * 0.34, S * 0.26), tip, Color3.fromRGB(255, 190, 50), Enum.Material.Neon)
		add("TailFlameCore", "Blob", Vector3.new(S * 0.15, S * 0.22, S * 0.15), tip, Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
	elseif kind == "Nine" then
		for i = 0, 8 do
			local fan = math.rad(-72 + i * 18)
			local tcf = cf * CFrame.Angles(0, 0, fan) * CFrame.Angles(math.rad(-45), 0, 0)
			add("Tail", "Blob", Vector3.new(S * 0.2, S * 0.2, S * 0.7), tcf * CFrame.new(0, S * 0.02, S * 0.32), color)
			add("TailTip", "Blob", Vector3.new(S * 0.17, S * 0.17, S * 0.2), tcf * CFrame.new(0, S * 0.02, S * 0.66), if i % 2 == 0 then Color3.fromRGB(255, 130, 200) else Color3.fromRGB(150, 220, 255), Enum.Material.Neon)
		end
	elseif kind == "Stub" then
		add("Tail", "Blob", Vector3.new(S * 0.14, S * 0.18, S * 0.12), cf * CFrame.new(0, S * 0.04, S * 0.03), color)
	elseif kind == "Ringed" then
		for i = 0, 5 do
			add("TailRing", "Ball", Vector3.one * S * (0.24 - i * 0.015), cf * CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, 0, S * (0.08 + i * 0.1)), if i % 2 == 0 then color else BLACK)
		end
	elseif kind == "Lizard" or kind == "Dragon" then
		local prev = cf
		for i = 0, 4 do
			local w = S * (0.3 - i * 0.05)
			local seg = prev * CFrame.Angles(math.rad(if kind == "Dragon" then -6 else -4), 0, 0) * CFrame.new(0, 0, S * 0.2)
			add("Tail", "Blob", Vector3.new(w, w * 0.9, S * 0.3), seg, color)
			if kind == "Dragon" then
				triangle(add, "TailSpike", w * 0.5, w * 0.6, S * 0.04, seg * CFrame.new(0, w * 0.45, 0) * CFrame.Angles(0, math.rad(90), 0), ctx.dark)
			end
			prev = seg * CFrame.new(0, 0, S * 0.1)
		end
		if kind == "Dragon" then
			triangle(add, "TailSpade", S * 0.3, S * 0.3, S * 0.06, prev * CFrame.new(0, 0, S * 0.12) * CFrame.Angles(math.rad(90), 0, 0), ctx.dark)
		end
	end
end

-- Four legs under the torso. Returns how far the feet are below the torso center.
local function legs4(ctx, len, width, color, pawColor, opts)
	opts = opts or {}
	local S, T, add = ctx.S, ctx.T, ctx.add
	local l, w = len * S, width * S
	local topY = -T.Y * 0.28
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * T.X * (opts.Spread or 0.3), sz * T.Z * 0.32
			if opts.Splay then
				add("Leg", "Blob", Vector3.new(w * 2.2, w, w), CFrame.new(x + sx * w * 0.8, topY, z) * CFrame.Angles(0, 0, math.rad(-25 * sx)), color)
				add("Paw", "Blob", Vector3.new(w * 1.2, w * 0.5, w * 1.4), CFrame.new(x + sx * w * 1.7, topY - w * 0.55, z), pawColor)
			else
				add("Leg", "Blob", Vector3.new(w, l + w * 0.6, w), CFrame.new(x, topY - l / 2, z), color)
				add("Paw", "Blob", Vector3.new(w * 1.2, w * 0.55, w * 1.4), CFrame.new(x, topY - l + w * 0.1, z - w * 0.15), pawColor)
				if sz < 0 and opts.Beans ~= false then
					add("ToeBean", "Blob", Vector3.new(w * 0.6, w * 0.25, w * 0.2), CFrame.new(x, topY - l + w * 0.1, z - w * 0.85), BLUSH)
				end
			end
		end
	end
	if opts.Splay then
		return -topY + w * 0.8
	end
	return -(topY - l) + w * 0.18
end

-- Bird legs with three toes. Returns the foot drop.
local function birdLegs(ctx, len, color)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local topY = -T.Y * 0.4
	local l = len * S
	for _, sx in ipairs({ -1, 1 }) do
		add("Leg", "Blob", Vector3.new(S * 0.07, l + S * 0.05, S * 0.07), CFrame.new(sx * S * 0.16, topY - l / 2, 0), color)
		for t = -1, 1 do
			add("Toe", "Blob", Vector3.new(S * 0.06, S * 0.05, S * 0.2), CFrame.new(sx * S * 0.16 + t * S * 0.05, topY - l, -S * 0.08) * CFrame.Angles(0, math.rad(t * 25), 0), color)
		end
	end
	return -(topY - l) + S * 0.025
end

local function featherWing(ctx, sx, cf, span, color, tipColor, spread)
	for f = 0, 3 do
		ctx.add("Feather", "Blob", Vector3.new(ctx.S * 0.1, ctx.S * (0.3 - f * 0.03), ctx.S * (span - f * 0.08)), cf * CFrame.Angles(math.rad(-(spread or 10) * f), 0, 0) * CFrame.new(sx * ctx.S * 0.02 * f, -ctx.S * 0.06 * f, ctx.S * 0.05 * f), if f == 3 then tipColor or color else color)
	end
end

local function batWing(ctx, sx, root, span, color, bone)
	local add, S = ctx.add, ctx.S
	for j = 0, 2 do
		local cf = root * CFrame.Angles(0, 0, math.rad((20 + j * 22) * sx)) * CFrame.new(sx * S * span * 0.5, 0, S * j * 0.12)
		add("WingMembrane", "Blob", Vector3.new(S * span, S * 0.05, S * 0.5), cf, color)
		add("WingBone", "Blob", Vector3.new(S * span, S * 0.06, S * 0.06), cf * CFrame.new(0, S * 0.03, -S * 0.22), bone)
	end
end

-- Mammals ---------------------------------------------------------------------
-- Realistic proportions for four-legged animals: a longer, slimmer body,
-- longer legs, a smaller head held up on a neck and a longer muzzle.
local REAL_BODY = Vector3.new(0.9, 0.86, 1.25)
local REAL_LEG = 1.5
local REAL_LEG_W = 1
local REAL_HEAD = 0.8
local REAL_SNOUT = 1.35

local function mammal(ctx, o)
	-- stretch the torso to real-animal proportions first
	ctx.T = ctx.T * REAL_BODY
	if ctx.body then
		ctx.body.Size = ctx.T
	end
	local S, T, add = ctx.S, ctx.T, ctx.add
	local c = ctx.color
	if o.Belly ~= false then
		add("Belly", "Blob", Vector3.new(T.X * 0.72, T.Y * 0.55, T.Z * 0.78), CFrame.new(0, -T.Y * 0.2, 0), o.Belly or ctx.light)
	end
	ctx.footDrop = legs4(ctx, (o.Leg or 0.3) * REAL_LEG, (o.LegW or 0.2) * REAL_LEG_W, o.LegColor or c, o.Paw or ctx.dark, o.LegOpts)
	local H = (o.Head or 0.7) * S * REAL_HEAD
	local headCf = CFrame.new(0, T.Y * 0.32 + S * ((o.Neck or 0) + (o.HeadUp or 0.22) + 0.1), -T.Z * 0.5 - S * (o.HeadFwd or 0.08))
	-- a neck joining the shoulders to the head
	local shoulder = Vector3.new(0, T.Y * 0.18, -T.Z * 0.36)
	local headPos = headCf.Position + Vector3.new(0, -H * 0.2, H * 0.15)
	local neckLen = (headPos - shoulder).Magnitude
	add("Neck", "Blob", Vector3.new(S * (0.34 + (o.Neck or 0) * 0.2), S * (0.34 + (o.Neck or 0) * 0.2), neckLen + S * 0.3), CFrame.lookAt((shoulder + headPos) / 2, headPos), c)
	local headAdd = makeHead(ctx, headCf, H, o.HeadColor or c, { Fur = o.Fur, Mouth = o.Snout == nil, EyeY = o.EyeY, Real = true })
	if o.Snout then
		snoutOn(headAdd, H, o.Snout * REAL_SNOUT, o.SnoutW or 0.42, o.SnoutColor or ctx.light, o.NoseColor)
	end
	earsOn(headAdd, H, o.Ears, o.EarColor or c, o.EarInner)
	tailOn(ctx, o.Tail, CFrame.new(0, T.Y * 0.12, T.Z * 0.46), o.TailColor or c)
	return headAdd, H
end

ANATOMY.Pup = { Torso = Vector3.new(0.75, 0.62, 1.0), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.72, Snout = 0.5, Ears = "Floppy", EarColor = ctx.dark, Tail = "Thin", Fur = true })
	ctx.add("Collar", "Cyl", Vector3.new(ctx.S * 0.1, ctx.S * 0.5, ctx.S * 0.5), ctx.headCf * CFrame.new(0, -H * 0.45, H * 0.05) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 60, 70))
	ctx.add("Tag", "Cyl", Vector3.new(ctx.S * 0.03, ctx.S * 0.12, ctx.S * 0.12), ctx.headCf * CFrame.new(0, -H * 0.58, -H * 0.2) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
end }

local function catBuild(ctx, glitch)
	local def = ctx.def
	local headAdd, H = mammal(ctx, { Head = 0.7, Snout = 0.18, SnoutW = 0.36, NoseColor = BLUSH, Ears = "Pointy", Leg = 0.3, LegW = 0.17, Tail = if glitch or (def and def.Plain) then "Thin" else "Flame", Fur = true })
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 1 do
			headAdd("Whisker", "Block", Vector3.new(H * 0.34, H * 0.02, H * 0.02), CFrame.new(sx * H * 0.36, -H * 0.14 - j * H * 0.06, -H * 0.42) * CFrame.Angles(0, 0, math.rad((10 - j * 18) * sx)), BLACK)
		end
	end
	if glitch then
		local cyan, magenta = Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 60, 200)
		for i, p in ipairs({ { 0.5, 0.2, -0.1 }, { -0.5, -0.1, 0.2 }, { 0.3, 0.45, 0.3 }, { -0.35, 0.35, -0.2 }, { 0.2, -0.3, 0.5 } }) do
			ctx.add("GlitchBit", "Block", Vector3.new(ctx.S * 0.14, ctx.S * 0.08, ctx.S * 0.14), CFrame.new(p[1] * ctx.S, p[2] * ctx.S, p[3] * ctx.S), if i % 2 == 0 then cyan else magenta, Enum.Material.Neon)
		end
		headAdd("ScanLine", "Block", Vector3.new(H * 1.02, H * 0.03, H * 0.2), CFrame.new(0, H * 0.02, -H * 0.38), cyan, Enum.Material.Neon)
	end
end
ANATOMY.Cat = { Torso = Vector3.new(0.62, 0.55, 0.95), Build = function(ctx) catBuild(ctx, false) end }
ANATOMY.GlitchCat = { Torso = Vector3.new(0.62, 0.55, 0.95), Build = function(ctx) catBuild(ctx, true) end }

ANATOMY.Fox = { Torso = Vector3.new(0.6, 0.55, 1.0), Build = function(ctx)
	mammal(ctx, { Head = 0.66, Snout = 0.6, SnoutW = 0.34, SnoutColor = WHITE, Ears = "Tall", Leg = 0.3, LegW = 0.16, Paw = BLACK, Tail = "Bushy", Fur = true })
end }

ANATOMY.Wolf = { Torso = Vector3.new(0.72, 0.64, 1.12), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.66, Snout = 0.62, SnoutW = 0.38, Ears = "Pointy", EarInner = ctx.dark, Leg = 0.36, LegW = 0.19, Tail = "Bushy", Fur = true })
	ctx.add("Ruff", "Blob", Vector3.new(ctx.S * 0.62, ctx.S * 0.44, ctx.S * 0.32), ctx.headCf * CFrame.new(0, -H * 0.5, H * 0.15), ctx.light)
end }

ANATOMY.Lion = { Torso = Vector3.new(0.8, 0.68, 1.12), Build = function(ctx)
	local mane = ctx.color:Lerp(Color3.fromRGB(150, 70, 20), 0.55)
	local headAdd, H = mammal(ctx, { Head = 0.66, Snout = 0.34, SnoutW = 0.46, Ears = "Round", Leg = 0.34, LegW = 0.22, Tail = "Tuft", Fur = false })
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		headAdd("Mane", "Ball", Vector3.one * H * 0.42, CFrame.new(math.cos(a) * H * 0.55, math.sin(a) * H * 0.52, H * 0.12), if i % 2 == 0 then mane else mane:Lerp(BLACK, 0.15))
	end
end }

local function bearBuild(ctx, kind)
	local panda = kind == "Panda"
	local headAdd, H = mammal(ctx, { Head = 0.74, Snout = 0.3, SnoutW = 0.46, Ears = "Round", EarColor = if panda then BLACK else ctx.color, Leg = 0.26, LegW = 0.26, LegColor = if panda then BLACK else nil, Paw = if panda then BLACK else nil, Tail = "Fluff", Fur = not panda, Belly = if panda then WHITE else nil })
	if panda then
		for _, sx in ipairs({ -1, 1 }) do
			headAdd("EyePatch", "Blob", Vector3.new(H * 0.3, H * 0.36, H * 0.1), CFrame.new(sx * H * 0.21, H * 0.08, -H * 0.37) * CFrame.Angles(0, 0, math.rad(-20 * sx)), BLACK)
		end
		ctx.add("Shoulders", "Blob", Vector3.new(ctx.T.X * 1.02, ctx.T.Y * 0.5, ctx.S * 0.3), CFrame.new(0, ctx.T.Y * 0.1, -ctx.T.Z * 0.25), BLACK)
	elseif kind == "Cub" then
		local bolt = Color3.fromRGB(255, 240, 80)
		headAdd("Bolt", "Block", Vector3.new(H * 0.09, H * 0.22, H * 0.05), CFrame.new(H * 0.02, H * 0.34, -H * 0.4) * CFrame.Angles(0, 0, math.rad(25)), bolt, Enum.Material.Neon)
		headAdd("Bolt", "Block", Vector3.new(H * 0.15, H * 0.05, H * 0.05), CFrame.new(0, H * 0.25, -H * 0.42), bolt, Enum.Material.Neon)
		headAdd("Bolt", "Block", Vector3.new(H * 0.09, H * 0.22, H * 0.05), CFrame.new(-H * 0.02, H * 0.16, -H * 0.44) * CFrame.Angles(0, 0, math.rad(25)), bolt, Enum.Material.Neon)
	end
end
ANATOMY.Bear = { Torso = Vector3.new(0.92, 0.78, 1.05), Build = function(ctx) bearBuild(ctx, "Bear") end }
ANATOMY.Cub = { Torso = Vector3.new(0.85, 0.74, 0.98), Build = function(ctx) bearBuild(ctx, "Cub") end }
ANATOMY.Panda = { Torso = Vector3.new(0.92, 0.78, 1.05), Build = function(ctx) bearBuild(ctx, "Panda") end }

ANATOMY.Raccoon = { Torso = Vector3.new(0.72, 0.6, 0.98), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.68, Snout = 0.4, SnoutW = 0.36, SnoutColor = ctx.color:Lerp(WHITE, 0.65), Ears = "Pointy", Leg = 0.24, LegW = 0.17, Paw = BLACK, Tail = "Ringed", Fur = true })
	headAdd("Mask", "Blob", Vector3.new(H * 0.8, H * 0.26, H * 0.2), CFrame.new(0, H * 0.1, -H * 0.34), BLACK)
end }

ANATOMY.Pig = { Torso = Vector3.new(0.86, 0.7, 1.05), Build = function(ctx)
	local pink = ctx.color:Lerp(Color3.fromRGB(255, 130, 160), 0.35)
	local headAdd, H = mammal(ctx, { Head = 0.7, Ears = "Pig", EarInner = pink, Leg = 0.2, LegW = 0.2, Paw = ctx.dark, Tail = "Curly", TailColor = pink, Belly = false })
	headAdd("Snout", "Cyl", Vector3.new(H * 0.16, H * 0.34, H * 0.34), CFrame.new(0, -H * 0.1, -H * 0.5) * CFrame.Angles(0, math.rad(90), 0), pink)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Nostril", "Blob", Vector3.new(H * 0.07, H * 0.1, H * 0.04), CFrame.new(sx * H * 0.07, -H * 0.1, -H * 0.585), pink:Lerp(BLACK, 0.45))
	end
end }

ANATOMY.Cow = { Torso = Vector3.new(0.92, 0.76, 1.25), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.66, Snout = 0.36, SnoutW = 0.62, SnoutColor = Color3.fromRGB(255, 190, 200), NoseColor = Color3.fromRGB(200, 110, 130), Ears = "Side", Leg = 0.4, LegW = 0.2, Paw = Color3.fromRGB(60, 50, 45), Tail = "Tuft", Belly = false, Beans = false })
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Horn", "Blob", Vector3.new(H * 0.11, H * 0.3, H * 0.11), CFrame.new(sx * H * 0.24, H * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx)), Color3.fromRGB(245, 235, 210))
	end
	for _, p in ipairs({ { 0.3, 0.25, 0.1 }, { -0.28, 0.15, 0.35 }, { 0.1, 0.35, -0.3 } }) do
		local pos = Vector3.new(p[1] * ctx.T.X * 1.7, p[2] * ctx.T.Y * 1.6, p[3] * ctx.T.Z * 1.4)
		ctx.add("CowPatch", "Blob", Vector3.new(ctx.S * 0.36, ctx.S * 0.3, ctx.S * 0.1), CFrame.lookAt(pos, pos * 2), BLACK)
	end
	ctx.add("Bell", "Ball", Vector3.one * ctx.S * 0.14, ctx.headCf * CFrame.new(0, -H * 0.62, -H * 0.1), GOLD, Enum.Material.Metal)
end }

ANATOMY.Sheep = { Torso = Vector3.new(0.9, 0.76, 1.05), Build = function(ctx)
	local wool = ctx.color:Lerp(WHITE, 0.55)
	local face = ctx.color:Lerp(Color3.fromRGB(90, 70, 60), 0.5)
	local headAdd, H = mammal(ctx, { Head = 0.6, HeadColor = face, Snout = 0.2, SnoutW = 0.4, SnoutColor = face:Lerp(WHITE, 0.3), Ears = "Side", EarColor = face, Leg = 0.28, LegW = 0.14, LegColor = face, Paw = BLACK, Tail = "Fluff", TailColor = wool, Belly = false, Beans = false })
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		ctx.add("Wool", "Ball", Vector3.one * ctx.S * 0.4, CFrame.new(math.cos(a) * ctx.T.X * 0.42, ctx.T.Y * (if i % 2 == 0 then 0.28 else 0.05), math.sin(a) * ctx.T.Z * 0.42), wool)
	end
	ctx.add("WoolTop", "Ball", Vector3.one * ctx.S * 0.5, CFrame.new(0, ctx.T.Y * 0.42, 0), wool)
	headAdd("WoolCap", "Ball", Vector3.one * H * 0.55, CFrame.new(0, H * 0.45, 0), wool)
end }

ANATOMY.Hamster = { Torso = Vector3.new(0.9, 0.78, 0.95), Build = function(ctx)
	local cream = ctx.color:Lerp(WHITE, 0.6)
	local headAdd, H = mammal(ctx, { Head = 0.82, HeadUp = 0.02, HeadFwd = -0.2, Ears = "Round", Leg = 0.1, LegW = 0.18, Tail = "Stub", Belly = cream })
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Cheek", "Blob", Vector3.new(H * 0.36, H * 0.3, H * 0.3), CFrame.new(sx * H * 0.34, -H * 0.14, -H * 0.26), cream)
		headAdd("Tooth", "Block", Vector3.new(H * 0.06, H * 0.08, H * 0.03), CFrame.new(sx * H * 0.035, -H * 0.2, -H * 0.47), WHITE)
		ctx.add("Hand", "Ball", Vector3.one * ctx.S * 0.14, ctx.headCf * CFrame.new(sx * H * 0.14, -H * 0.5, -H * 0.3), ctx.color:Lerp(Color3.fromRGB(255, 170, 170), 0.4))
	end
	ctx.add("Seed", "Blob", Vector3.new(ctx.S * 0.12, ctx.S * 0.18, ctx.S * 0.08), ctx.headCf * CFrame.new(0, -H * 0.52, -H * 0.36) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(60, 50, 45))
end }

-- Bunnies sit up: tall ears, big back feet, little front paws and a cotton tail
local function bunnyBuild(ctx, glitch)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.7, T.Z * 0.5), CFrame.new(0, -T.Y * 0.08, -T.Z * 0.28), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		add("Haunch", "Ball", Vector3.one * S * 0.42, CFrame.new(sx * T.X * 0.36, -T.Y * 0.25, T.Z * 0.12), ctx.color)
		add("Foot", "Blob", Vector3.new(S * 0.22, S * 0.14, S * 0.5), CFrame.new(sx * T.X * 0.34, -T.Y * 0.43, -T.Z * 0.2), ctx.color)
		add("FootPad", "Blob", Vector3.new(S * 0.14, S * 0.06, S * 0.1), CFrame.new(sx * T.X * 0.34, -T.Y * 0.43, -T.Z * 0.2 - S * 0.25), BLUSH)
		add("FrontPaw", "Blob", Vector3.new(S * 0.14, S * 0.26, S * 0.14), CFrame.new(sx * S * 0.13, -T.Y * 0.3, -T.Z * 0.42), ctx.color)
	end
	ctx.footDrop = T.Y * 0.43 + S * 0.07
	local H = S * 0.72
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + S * 0.18, -T.Z * 0.18), H, ctx.color, { Fur = true })
	earsOn(headAdd, H, "Long", ctx.color, if glitch then Color3.fromRGB(60, 255, 240) else nil)
	headAdd("Nose", "Blob", Vector3.new(H * 0.1, H * 0.07, H * 0.05), CFrame.new(0, -H * 0.03, -H * 0.48), BLUSH)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Tooth", "Block", Vector3.new(H * 0.07, H * 0.09, H * 0.03), CFrame.new(sx * H * 0.04, -H * 0.2, -H * 0.46), WHITE)
	end
	tailOn(ctx, "Fluff", CFrame.new(0, -T.Y * 0.15, T.Z * 0.48), WHITE)
	if glitch then
		local magenta = Color3.fromRGB(255, 60, 200)
		for i = 1, 5 do
			add("GlitchBit", "Block", Vector3.new(S * 0.12, S * 0.07, S * 0.12), CFrame.new(math.cos(i * 1.3) * S * 0.5, S * (i * 0.12 - 0.2), math.sin(i * 1.3) * S * 0.45), if i % 2 == 0 then Color3.fromRGB(60, 255, 240) else magenta, Enum.Material.Neon)
		end
		headAdd("ErrorMark", "Block", Vector3.new(H * 0.08, H * 0.22, H * 0.04), CFrame.new(0, H * 0.34, -H * 0.4), magenta, Enum.Material.Neon)
	end
end
ANATOMY.Bunny = { Torso = Vector3.new(0.78, 0.82, 0.86), Build = function(ctx) bunnyBuild(ctx, false) end }
ANATOMY.GlitchBunny = { Torso = Vector3.new(0.78, 0.82, 0.86), Build = function(ctx) bunnyBuild(ctx, true) end }

-- Deer, unicorns and kitsune: long legs, long neck
ANATOMY.Stag = { Torso = Vector3.new(0.62, 0.6, 1.08), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Neck = 0.3, Head = 0.52, Snout = 0.5, SnoutW = 0.34, Ears = "Pointy", Leg = 0.55, LegW = 0.14, Paw = Color3.fromRGB(60, 45, 40), Tail = "Stub", TailColor = WHITE, Beans = false })
	local crystal = ctx.rarity.Order >= 4
	local antler = if crystal then ctx.color:Lerp(WHITE, 0.4) else Color3.fromRGB(215, 190, 150)
	for _, sx in ipairs({ -1, 1 }) do
		local base = CFrame.new(sx * H * 0.2, H * 0.45, 0) * CFrame.Angles(0, 0, math.rad(-25 * sx))
		headAdd("Antler", "Block", Vector3.new(H * 0.09, H * 0.7, H * 0.09), base * CFrame.new(0, H * 0.35, 0), antler, if crystal then Enum.Material.Neon else nil)
		for k = 1, 3 do
			headAdd("AntlerTine", "Block", Vector3.new(H * 0.07, H * 0.32, H * 0.07), base * CFrame.new(0, H * (0.15 + k * 0.17), 0) * CFrame.Angles(math.rad(-40), 0, math.rad(35 * sx * (if k % 2 == 0 then -1 else 1))) * CFrame.new(0, H * 0.14, 0), antler, if crystal then Enum.Material.Neon else nil)
		end
	end
	for i = 1, 4 do
		ctx.add("Spot", "Blob", Vector3.new(ctx.S * 0.1, ctx.S * 0.1, ctx.S * 0.04), CFrame.new((if i % 2 == 0 then 1 else -1) * ctx.T.X * 0.46, ctx.T.Y * 0.2, -ctx.T.Z * 0.3 + i * ctx.T.Z * 0.15) * CFrame.Angles(0, math.rad(90), 0), WHITE)
	end
end }

ANATOMY.Unicorn = { Torso = Vector3.new(0.72, 0.66, 1.18), Build = function(ctx)
	local rainbow = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 200, 100), Color3.fromRGB(140, 220, 255), Color3.fromRGB(190, 150, 255) }
	local headAdd, H = mammal(ctx, { Neck = 0.32, Head = 0.56, Snout = 0.6, SnoutW = 0.42, SnoutColor = ctx.color, NoseColor = BLUSH, Ears = "Pointy", Leg = 0.5, LegW = 0.16, Paw = Color3.fromRGB(255, 215, 120), Tail = nil, Beans = false })
	hornSpiral(headAdd, H, CFrame.new(0, H * 0.42, -H * 0.22) * CFrame.Angles(math.rad(-25), 0, 0), H * 0.8, Color3.fromRGB(255, 225, 120))
	for i = 0, 5 do
		ctx.add("Mane", "Blob", Vector3.new(ctx.S * 0.14, ctx.S * 0.26, ctx.S * 0.18), CFrame.new(0, ctx.T.Y * 0.35 + ctx.S * (0.62 - i * 0.1), -ctx.T.Z * 0.5 + ctx.S * i * 0.06) * CFrame.Angles(math.rad(-30), 0, 0), rainbow[(i % 4) + 1])
	end
	for i = 0, 4 do
		ctx.add("Tail", "Blob", Vector3.new(ctx.S * 0.16, ctx.S * 0.16, ctx.S * 0.3), CFrame.new(0, ctx.T.Y * 0.1 - i * ctx.S * 0.1, ctx.T.Z * 0.5 + ctx.S * (0.1 + i * 0.07)) * CFrame.Angles(math.rad(-50), 0, 0), rainbow[(i % 4) + 1])
	end
end }

ANATOMY.Kitsune = { Torso = Vector3.new(0.62, 0.56, 1.0), Build = function(ctx)
	local fire = Color3.fromRGB(255, 130, 200)
	local headAdd, H = mammal(ctx, { Head = 0.68, Snout = 0.56, SnoutW = 0.34, SnoutColor = WHITE, Ears = "Tall", EarInner = fire, Leg = 0.32, LegW = 0.15, Paw = fire, Tail = "Nine", Fur = true })
	headAdd("ForeheadGem", "Ball", Vector3.one * H * 0.12, CFrame.new(0, H * 0.33, -H * 0.43), fire, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Marking", "Blob", Vector3.new(H * 0.18, H * 0.04, H * 0.04), CFrame.new(sx * H * 0.3, H * 0.22, -H * 0.36) * CFrame.Angles(0, 0, math.rad(25 * sx)), fire, Enum.Material.Neon)
	end
	ctx.add("Rope", "Cyl", Vector3.new(ctx.S * 0.07, ctx.S * 0.46, ctx.S * 0.46), ctx.headCf * CFrame.new(0, -H * 0.46, H * 0.08) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 50, 60), Enum.Material.Fabric)
	ctx.add("Bell", "Ball", Vector3.one * ctx.S * 0.12, ctx.headCf * CFrame.new(0, -H * 0.6, -H * 0.22), GOLD, Enum.Material.Metal)
end }

ANATOMY.Elephant = { Torso = Vector3.new(1.0, 0.86, 1.2), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.74, HeadUp = 0.18, Ears = nil, Leg = 0.34, LegW = 0.3, Paw = ctx.light, Tail = "Thin", Belly = false, Beans = false })
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ear", "Cyl", Vector3.new(H * 0.08, H * 0.8, H * 0.7), CFrame.new(sx * H * 0.55, H * 0.02, H * 0.1) * CFrame.Angles(0, math.rad(20 * sx), 0), ctx.color)
		headAdd("InnerEar", "Cyl", Vector3.new(H * 0.06, H * 0.6, H * 0.52), CFrame.new(sx * H * 0.53, H * 0.02, H * 0.06) * CFrame.Angles(0, math.rad(20 * sx), 0), BLUSH)
		headAdd("Tusk", "Blob", Vector3.new(H * 0.08, H * 0.08, H * 0.36), CFrame.new(sx * H * 0.16, -H * 0.28, -H * 0.5) * CFrame.Angles(math.rad(30), 0, 0), Color3.fromRGB(250, 245, 230))
	end
	for i = 0, 4 do
		headAdd("Trunk", "Ball", Vector3.one * H * (0.28 - i * 0.03), CFrame.new(0, -H * (0.12 + i * 0.16), -H * (0.46 + i * 0.05 - (if i >= 3 then (i - 2) * 0.1 else 0))), ctx.color)
	end
end }

ANATOMY.Monkey = { Torso = Vector3.new(0.7, 0.82, 0.64), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local face = Color3.fromRGB(245, 205, 165)
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.7, S * 0.2), CFrame.new(0, -T.Y * 0.05, -T.Z * 0.42), face)
	for _, sx in ipairs({ -1, 1 }) do
		add("Leg", "Blob", Vector3.new(S * 0.2, S * 0.2, S * 0.4), CFrame.new(sx * T.X * 0.3, -T.Y * 0.4, -T.Z * 0.2), ctx.color)
		add("Foot", "Blob", Vector3.new(S * 0.2, S * 0.1, S * 0.26), CFrame.new(sx * T.X * 0.3, -T.Y * 0.47, -T.Z * 0.5), face)
		add("Arm", "Blob", Vector3.new(S * 0.14, S * 0.6, S * 0.14), CFrame.new(sx * T.X * 0.55, -T.Y * 0.05, -T.Z * 0.1) * CFrame.Angles(0, 0, math.rad(12 * sx)), ctx.color)
		add("Hand", "Ball", Vector3.one * S * 0.16, CFrame.new(sx * T.X * 0.6, -T.Y * 0.38, -T.Z * 0.2), face)
	end
	ctx.footDrop = T.Y * 0.47 + S * 0.05
	local H = S * 0.7
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + S * 0.25, -T.Z * 0.05), H, ctx.color, { Fur = true })
	headAdd("Face", "Blob", Vector3.new(H * 0.7, H * 0.58, H * 0.2), CFrame.new(0, -H * 0.02, -H * 0.36), face)
	headAdd("Muzzle", "Blob", Vector3.new(H * 0.44, H * 0.26, H * 0.2), CFrame.new(0, -H * 0.18, -H * 0.44), face:Lerp(WHITE, 0.2))
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ear", "Cyl", Vector3.new(H * 0.08, H * 0.34, H * 0.34), CFrame.new(sx * H * 0.52, H * 0.06, 0), ctx.color)
		headAdd("InnerEar", "Cyl", Vector3.new(H * 0.06, H * 0.22, H * 0.22), CFrame.new(sx * H * 0.55, H * 0.06, -H * 0.02), face)
	end
	for i = 0, 5 do
		local a = i * 0.8
		add("Tail", "Ball", Vector3.one * S * 0.1, CFrame.new(math.sin(a) * S * 0.1, -T.Y * 0.3 + i * S * 0.12, T.Z * 0.5 + math.cos(a) * S * 0.12 + S * 0.1), ctx.color)
	end
end }

ANATOMY.Seal = { Torso = Vector3.new(0.74, 0.62, 1.3), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.5, T.Z * 0.8), CFrame.new(0, -T.Y * 0.2, 0), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		add("Flipper", "Blob", Vector3.new(S * 0.36, S * 0.07, S * 0.2), CFrame.new(sx * T.X * 0.55, -T.Y * 0.4, -T.Z * 0.25) * CFrame.Angles(0, math.rad(-20 * sx), math.rad(-15 * sx)), ctx.dark)
		add("TailFlipper", "Blob", Vector3.new(S * 0.3, S * 0.06, S * 0.24), CFrame.new(sx * S * 0.13, -T.Y * 0.4, T.Z * 0.58) * CFrame.Angles(0, math.rad(25 * sx), 0), ctx.dark)
	end
	ctx.footDrop = T.Y * 0.5
	local H = S * 0.62
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.35, -T.Z * 0.48), H, ctx.color, { Mouth = false })
	headAdd("Muzzle", "Blob", Vector3.new(H * 0.44, H * 0.26, H * 0.2), CFrame.new(0, -H * 0.13, -H * 0.44), ctx.light)
	headAdd("Nose", "Blob", Vector3.new(H * 0.16, H * 0.09, H * 0.08), CFrame.new(0, -H * 0.04, -H * 0.54), BLACK)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			headAdd("Whisker", "Block", Vector3.new(H * 0.3, H * 0.015, H * 0.015), CFrame.new(sx * H * 0.3, -H * 0.1 - j * H * 0.04, -H * 0.48) * CFrame.Angles(0, 0, math.rad((10 - j * 12) * sx)), WHITE)
		end
	end
end }

-- Reptiles and amphibians -------------------------------------------------------
ANATOMY.Newt = { Torso = Vector3.new(0.55, 0.38, 1.0), Build = function(ctx)
	local S, T = ctx.S, ctx.T
	ctx.add("Belly", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.5, T.Z * 0.85), CFrame.new(0, -T.Y * 0.2, 0), ctx.light)
	ctx.footDrop = legs4(ctx, 0.12, 0.12, ctx.color, ctx.dark, { Splay = true, Beans = false })
	local H = S * 0.56
	makeHead(ctx, CFrame.new(0, T.Y * 0.12, -T.Z * 0.5 - S * 0.12), H, ctx.color)
	tailOn(ctx, "Lizard", CFrame.new(0, 0, T.Z * 0.45), ctx.color)
	for i = 1, 6 do
		ctx.add("GlowSpot", "Ball", Vector3.one * S * 0.1, CFrame.new((if i % 2 == 0 then 1 else -1) * T.X * 0.3, T.Y * 0.4, -T.Z * 0.35 + i * T.Z * 0.12), Color3.fromRGB(200, 255, 120), Enum.Material.Neon)
	end
end }

ANATOMY.Axolotl = { Torso = Vector3.new(0.6, 0.44, 1.0), Build = function(ctx)
	local S, T = ctx.S, ctx.T
	ctx.add("Belly", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.5, T.Z * 0.85), CFrame.new(0, -T.Y * 0.2, 0), ctx.light)
	ctx.footDrop = legs4(ctx, 0.12, 0.12, ctx.color, ctx.color, { Splay = true, Beans = false })
	local H = S * 0.74
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.2, -T.Z * 0.5 - S * 0.14), H, ctx.color)
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			headAdd("Gill", "Blob", Vector3.new(H * 0.08, H * 0.34, H * 0.12), CFrame.new(sx * H * 0.5, H * (0.2 - j * 0.18), H * 0.05) * CFrame.Angles(0, 0, math.rad((-50 + j * 30) * sx)), Color3.fromRGB(255, 110, 150))
		end
	end
	tailOn(ctx, "Lizard", CFrame.new(0, 0, T.Z * 0.45), ctx.color)
	ctx.add("TailFin", "Blob", Vector3.new(S * 0.04, S * 0.3, S * 0.8), CFrame.new(0, T.Y * 0.1, T.Z * 0.5 + S * 0.45), ctx.color:Lerp(WHITE, 0.3))
end }

ANATOMY.Turtle = { Torso = Vector3.new(0.8, 0.45, 0.95), Build = function(ctx)
	local S, T = ctx.S, ctx.T
	local shell = ctx.color:Lerp(Color3.fromRGB(90, 70, 40), 0.35)
	ctx.add("Shell", "Blob", Vector3.new(T.X * 1.25, S * 0.62, T.Z * 1.2), CFrame.new(0, T.Y * 0.35, 0), shell)
	for i, p in ipairs({ { 0, 0.66, 0 }, { 0.3, 0.5, -0.25 }, { -0.3, 0.5, -0.25 }, { 0.3, 0.5, 0.25 }, { -0.3, 0.5, 0.25 } }) do
		local pos = Vector3.new(p[1] * S, p[2] * S, p[3] * S)
		ctx.add("ShellPlate", "Blob", Vector3.new(S * 0.3, S * 0.28, S * 0.06), CFrame.lookAt(pos, pos + (pos - Vector3.new(0, T.Y * 0.2, 0))), shell:Lerp(WHITE, if i == 1 then 0.25 else 0.15))
	end
	ctx.add("ShellRim", "Cyl", Vector3.new(S * 0.08, T.X * 1.3, T.X * 1.3), CFrame.new(0, T.Y * 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), shell:Lerp(BLACK, 0.2))
	ctx.footDrop = legs4(ctx, 0.12, 0.2, ctx.color, ctx.color, { Spread = 0.42, Beans = false })
	local H = S * 0.46
	makeHead(ctx, CFrame.new(0, T.Y * 0.1, -T.Z * 0.62), H, ctx.color, { EyeSize = 0.3 })
	tailOn(ctx, "Stub", CFrame.new(0, 0, T.Z * 0.55), ctx.color)
end }

ANATOMY.Hedgehog = { Torso = Vector3.new(0.8, 0.66, 0.95), Build = function(ctx)
	local S, T = ctx.S, ctx.T
	ctx.footDrop = legs4(ctx, 0.08, 0.14, ctx.light, ctx.dark)
	local spike = ctx.color:Lerp(BLACK, 0.35)
	for i = 0, 20 do
		local yaw = math.rad((i % 7) / 6 * 200 - 100)
		local pitch = math.rad(-5 + (i // 7) * 30)
		local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
		local pos = Vector3.new(dir.X * T.X * 0.46, dir.Y * T.Y * 0.46, dir.Z * T.Z * 0.46)
		ctx.add("Spike", "Blob", Vector3.new(S * 0.12, S * 0.12, S * 0.42), CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -S * 0.12), spike)
	end
	local H = S * 0.56
	local headAdd = makeHead(ctx, CFrame.new(0, 0, -T.Z * 0.45), H, ctx.light)
	headAdd("Snout", "Blob", Vector3.new(H * 0.36, H * 0.3, H * 0.5), CFrame.new(0, -H * 0.12, -H * 0.5), ctx.light)
	headAdd("Nose", "Ball", Vector3.one * H * 0.14, CFrame.new(0, -H * 0.08, -H * 0.76), BLACK)
	earsOn(headAdd, H, "Round", ctx.light)
end }

-- Dragons and dinosaurs -----------------------------------------------------------
ANATOMY.Drake = { Torso = Vector3.new(0.8, 0.7, 1.3), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local horn = Color3.fromRGB(250, 235, 200)
	local wing = ctx.color:Lerp(ctx.rarity.Color, 0.35):Lerp(BLACK, 0.15)
	-- belly plates
	for i = 0, 4 do
		add("BellyPlate", "Blob", Vector3.new(T.X * 0.6, S * 0.1, S * 0.24), CFrame.new(0, -T.Y * 0.42, -T.Z * 0.35 + i * T.Z * 0.17), ctx.light)
	end
	ctx.footDrop = legs4(ctx, 0.34, 0.22, ctx.color, ctx.dark, { Beans = false })
	for _, sx in ipairs({ -1, 1 }) do
		for c = -1, 1 do
			add("Claw", "Blob", Vector3.new(S * 0.04, S * 0.05, S * 0.1), CFrame.new(sx * T.X * 0.3 + c * S * 0.06, -ctx.footDrop + S * 0.03, -T.Z * 0.32 - S * 0.2), horn)
		end
	end
	-- long curved neck
	local prev = CFrame.new(0, T.Y * 0.2, -T.Z * 0.42)
	for i = 1, 3 do
		prev = prev * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, 0, -S * 0.2)
		add("Neck", "Blob", Vector3.new(S * (0.36 - i * 0.03), S * (0.36 - i * 0.03), S * 0.34), prev, ctx.color)
		triangle(add, "NeckSpike", S * 0.12, S * 0.14, S * 0.04, prev * CFrame.new(0, S * 0.18, 0) * CFrame.Angles(0, math.rad(90), 0), ctx.dark)
	end
	local H = S * 0.58
	local headCf = CFrame.new(prev.Position + Vector3.new(0, S * 0.2, -S * 0.12))
	local headAdd = makeHead(ctx, headCf, H, ctx.color, { Mouth = false, EyeY = 0.16 })
	headAdd("Snout", "Blob", Vector3.new(H * 0.56, H * 0.4, H * 0.7), CFrame.new(0, -H * 0.12, -H * 0.55), ctx.color)
	headAdd("Jaw", "Blob", Vector3.new(H * 0.5, H * 0.16, H * 0.6), CFrame.new(0, -H * 0.32, -H * 0.5), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Nostril", "Ball", Vector3.one * H * 0.08, CFrame.new(sx * H * 0.12, -H * 0.02, -H * 0.88), ctx.dark:Lerp(BLACK, 0.4))
		headAdd("Horn", "Blob", Vector3.new(H * 0.12, H * 0.12, H * 0.6), CFrame.new(sx * H * 0.24, H * 0.42, H * 0.2) * CFrame.Angles(math.rad(35), math.rad(12 * sx), 0), horn)
		triangle(headAdd, "Fang", H * 0.08, H * 0.12, H * 0.03, CFrame.new(sx * H * 0.16, -H * 0.3, -H * 0.8) * CFrame.Angles(0, 0, math.pi), WHITE)
		headAdd("Frill", "Blob", Vector3.new(H * 0.06, H * 0.3, H * 0.34), CFrame.new(sx * H * 0.48, H * 0.05, H * 0.15) * CFrame.Angles(0, 0, math.rad(-30 * sx)), wing)
		batWing(ctx, sx, CFrame.new(sx * T.X * 0.35, T.Y * 0.45, -T.Z * 0.1) * CFrame.Angles(math.rad(-15), 0, 0), 0.75, wing, ctx.dark)
	end
	for i = 0, 3 do
		triangle(add, "BackSpike", S * 0.16, S * 0.2, S * 0.04, CFrame.new(0, T.Y * 0.5, -T.Z * 0.3 + i * T.Z * 0.2) * CFrame.Angles(0, math.rad(90), 0), ctx.dark)
	end
	tailOn(ctx, "Dragon", CFrame.new(0, T.Y * 0.05, T.Z * 0.42), ctx.color)
end }

ANATOMY.Dino = { Torso = Vector3.new(0.78, 0.8, 1.05), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.6, T.Z * 0.6), CFrame.new(0, -T.Y * 0.12, -T.Z * 0.2), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		add("Thigh", "Blob", Vector3.new(S * 0.3, S * 0.44, S * 0.4), CFrame.new(sx * T.X * 0.42, -T.Y * 0.22, T.Z * 0.08), ctx.color)
		add("Leg", "Blob", Vector3.new(S * 0.18, S * 0.36, S * 0.18), CFrame.new(sx * T.X * 0.42, -T.Y * 0.55, T.Z * 0.08), ctx.color)
		add("Foot", "Blob", Vector3.new(S * 0.26, S * 0.12, S * 0.36), CFrame.new(sx * T.X * 0.42, -T.Y * 0.72, -T.Z * 0.02), ctx.dark)
		add("Arm", "Blob", Vector3.new(S * 0.08, S * 0.2, S * 0.08), CFrame.new(sx * T.X * 0.35, -T.Y * 0.05, -T.Z * 0.48) * CFrame.Angles(math.rad(-40), 0, 0), ctx.color)
	end
	ctx.footDrop = T.Y * 0.72 + S * 0.06
	local H = S * 0.72
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.55, -T.Z * 0.45), H, ctx.color, { Mouth = false, EyeY = 0.2 })
	headAdd("Snout", "Blob", Vector3.new(H * 0.62, H * 0.42, H * 0.6), CFrame.new(0, -H * 0.08, -H * 0.5), ctx.color)
	headAdd("Jaw", "Blob", Vector3.new(H * 0.56, H * 0.18, H * 0.56), CFrame.new(0, -H * 0.34, -H * 0.42), ctx.light)
	for i = -2, 2 do
		triangle(headAdd, "Tooth", H * 0.08, H * 0.1, H * 0.03, CFrame.new(i * H * 0.1, -H * 0.26, -H * 0.76) * CFrame.Angles(0, 0, math.pi), WHITE)
	end
	for i = 0, 3 do
		add("BackPlate", "Blob", Vector3.new(S * 0.06, S * 0.22, S * 0.2), CFrame.new(0, T.Y * 0.5 - i * S * 0.04, -T.Z * 0.2 + i * T.Z * 0.22), Color3.fromRGB(255, 140, 60))
	end
	tailOn(ctx, "Lizard", CFrame.new(0, 0, T.Z * 0.45), ctx.color)
end }

-- Serpents coil through the air in an S curve
ANATOMY.Serpent = { Torso = Vector3.new(0.5, 0.5, 0.6), Float = true, Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local fin = ctx.color:Lerp(ctx.rarity.Color, 0.4)
	-- one smooth S-shaped body: overlapping segments that each point at the next
	local points = {}
	for i = 0, 13 do
		points[i] = Vector3.new(math.sin(i * 0.55) * S * 0.5, math.sin(i * 0.9 + 0.6) * S * 0.32 + S * 0.12, i * S * 0.24)
	end
	for i = 0, 12 do
		local a, b = points[i], points[i + 1]
		local w = S * (0.5 - i * 0.03)
		add("Coil", "Blob", Vector3.new(w, w, (b - a).Magnitude * 1.7), CFrame.lookAt((a + b) / 2, b), if i % 2 == 0 then ctx.color else ctx.color:Lerp(ctx.light, 0.3))
		if i % 2 == 1 then
			triangle(add, "DorsalFin", w * 0.5, w * 0.55, S * 0.04, CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, w * 0.45, 0) * CFrame.Angles(0, math.rad(90), 0), fin)
		end
	end
	triangle(add, "TailFin", S * 0.4, S * 0.4, S * 0.05, CFrame.lookAt(points[13], points[13] + (points[13] - points[12])) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, S * 0.15, 0), fin)
	ctx.footDrop = T.Y * 0.5
	local H = S * 0.72
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.8, -T.Z * 0.5), H, ctx.color, { Mouth = false })
	ctx.add("Neck", "Blob", Vector3.new(S * 0.4, S * 0.5, S * 0.4), CFrame.new(0, T.Y * 0.35, -T.Z * 0.2) * CFrame.Angles(math.rad(-20), 0, 0), ctx.color)
	headAdd("Snout", "Blob", Vector3.new(H * 0.5, H * 0.34, H * 0.6), CFrame.new(0, -H * 0.12, -H * 0.5), ctx.color)
	headAdd("Mane", "Blob", Vector3.new(H * 0.3, H * 0.5, H * 0.6), CFrame.new(0, H * 0.35, H * 0.3) * CFrame.Angles(math.rad(-20), 0, 0), fin)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Horn", "Blob", Vector3.new(H * 0.1, H * 0.1, H * 0.55), CFrame.new(sx * H * 0.22, H * 0.4, H * 0.2) * CFrame.Angles(math.rad(40), 0, 0), Color3.fromRGB(255, 225, 130))
		headAdd("Whisker", "Block", Vector3.new(H * 0.03, H * 0.03, H * 0.6), CFrame.new(sx * H * 0.2, -H * 0.18, -H * 0.72) * CFrame.Angles(math.rad(25), math.rad(35 * sx), 0), fin)
		headAdd("Fin", "Blob", Vector3.new(H * 0.05, H * 0.3, H * 0.34), CFrame.new(sx * H * 0.48, H * 0.05, H * 0.1) * CFrame.Angles(0, 0, math.rad(-35 * sx)), fin)
	end
end }

-- Fish ----------------------------------------------------------------------------
local function fishBuild(ctx, kind)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local fin = if kind == "Koi" then ctx.color:Lerp(WHITE, 0.3) else ctx.dark
	local finMat = if kind == "Koi" then Enum.Material.Glass else nil
	ctx.footDrop = T.Y * 0.5
	add("Belly", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.45, T.Z * 0.85), CFrame.new(0, -T.Y * 0.22, 0), if kind == "Shark" then ctx.color:Lerp(WHITE, 0.75) else ctx.light)
	-- the front of the body is the head: eyes on the sides, a mouth at the tip
	for _, sx in ipairs({ -1, 1 }) do
		petEye(add, CFrame.new(sx * T.X * 0.38, T.Y * 0.12, -T.Z * 0.3) * CFrame.Angles(0, math.rad(-55 * sx), 0), S * 0.24, ctx.iris)
		add("Blush", "Blob", Vector3.new(S * 0.14, S * 0.08, S * 0.05), CFrame.new(sx * T.X * 0.42, -T.Y * 0.08, -T.Z * 0.22) * CFrame.Angles(0, math.rad(-60 * sx), 0), BLUSH)
		add("SideFin", "Blob", Vector3.new(S * 0.3, S * 0.04, S * 0.22), CFrame.new(sx * T.X * 0.55, -T.Y * 0.22, -T.Z * 0.1) * CFrame.Angles(0, math.rad(-30 * sx), math.rad(-25 * sx)), fin, finMat)
	end
	ctx.headCf, ctx.H = CFrame.new(0, 0, -T.Z * 0.1), T.Y
	ctx.headAdd = function(name, shape, size, cf, col, mat)
		return add(name, shape, size, ctx.headCf * cf, col, mat)
	end
	for _, sy in ipairs({ -1, 1 }) do
		add("TailFin", "Blob", Vector3.new(S * 0.06, S * 0.44, S * 0.32), CFrame.new(0, sy * S * 0.16, T.Z * 0.5 + S * 0.14) * CFrame.Angles(math.rad(40 * sy), 0, 0), fin, finMat)
	end
	if kind == "Shark" then
		add("Snout", "Blob", Vector3.new(T.X * 0.6, T.Y * 0.5, S * 0.4), CFrame.new(0, T.Y * 0.05, -T.Z * 0.5), ctx.color)
		triangle(add, "DorsalFin", S * 0.44, S * 0.44, S * 0.07, CFrame.new(0, T.Y * 0.62, T.Z * 0.05) * CFrame.Angles(math.rad(-15), math.rad(90), 0), ctx.color)
		for i = -2, 2 do
			triangle(add, "Tooth", S * 0.06, S * 0.07, S * 0.02, CFrame.new(i * S * 0.05, -T.Y * 0.18, -T.Z * 0.52) * CFrame.Angles(0, 0, math.pi), WHITE)
		end
		for _, sx in ipairs({ -1, 1 }) do
			for j = 0, 2 do
				add("Gill", "Block", Vector3.new(S * 0.02, S * 0.2, S * 0.03), CFrame.new(sx * T.X * 0.48, 0, -T.Z * (0.1 - j * 0.07)), ctx.dark)
			end
		end
	else
		add("Mouth", "Blob", Vector3.new(S * 0.16, S * 0.1, S * 0.06), CFrame.new(0, -T.Y * 0.08, -T.Z * 0.5), Color3.fromRGB(255, 120, 140))
		triangle(add, "DorsalFin", S * 0.8, S * 0.2, S * 0.04, CFrame.new(0, T.Y * 0.5, T.Z * 0.12) * CFrame.Angles(0, math.rad(90), 0), fin, finMat)
		if kind == "Koi" then
			for i, p in ipairs({ { 0.2, 0.3, -0.2 }, { -0.25, 0.2, 0.15 }, { 0.15, -0.1, 0.3 } }) do
				local pos = Vector3.new(p[1] * T.X * 2, p[2] * T.Y * 1.5, p[3] * T.Z * 1.4)
				add("KoiPatch", "Blob", Vector3.new(S * 0.34, S * 0.3, S * 0.08), CFrame.lookAt(pos, pos * 2), Color3.fromRGB(250, 248, 240))
			end
			for _, sx in ipairs({ -1, 1 }) do
				add("Whisker", "Block", Vector3.new(S * 0.03, S * 0.03, S * 0.35), CFrame.new(sx * S * 0.1, -T.Y * 0.1, -T.Z * 0.58) * CFrame.Angles(math.rad(25), math.rad(25 * sx), 0), ctx.dark)
			end
		elseif ctx.def == nil or not ctx.def.Plain then
			add("IceCrystal", "Block", Vector3.new(S * 0.14, S * 0.34, S * 0.14), CFrame.new(0, T.Y * 0.7, -T.Z * 0.2) * CFrame.Angles(0, math.rad(45), math.rad(10)), Color3.fromRGB(200, 240, 255), Enum.Material.Neon)
		end
	end
end
ANATOMY.Fish = { Torso = Vector3.new(0.46, 0.7, 1.25), Float = true, Build = function(ctx) fishBuild(ctx, "Fish") end }
ANATOMY.Koi = { Torso = Vector3.new(0.5, 0.58, 1.4), Float = true, Build = function(ctx) fishBuild(ctx, "Koi") end }
ANATOMY.Shark = { Torso = Vector3.new(0.7, 0.66, 1.5), Float = true, Build = function(ctx) fishBuild(ctx, "Shark") end }

-- Birds -----------------------------------------------------------------------------
local function birdBuild(ctx, kind)
	if kind == "Bird" or kind == "Duck" or kind == "Phoenix" then
		-- slimmer, longer body like a real bird
		ctx.T = ctx.T * Vector3.new(0.85, 0.9, 1.2)
		if ctx.body then
			ctx.body.Size = ctx.T
		end
	end
	local S, T, add = ctx.S, ctx.T, ctx.add
	local orange = Color3.fromRGB(255, 150, 40)
	local legColor = if kind == "Owl" then Color3.fromRGB(120, 100, 80) elseif kind == "Phoenix" then Color3.fromRGB(255, 200, 80) else ORANGE_FOOT
	ctx.footDrop = birdLegs(ctx, if kind == "Penguin" or kind == "Chick" then 0.06 else 0.16, legColor)
	add("Belly", "Blob", Vector3.new(T.X * 0.72, T.Y * 0.65, S * 0.2), CFrame.new(0, -T.Y * 0.08, -T.Z * 0.4), if kind == "Penguin" then WHITE else ctx.light)
	local H, headCf
	if false then -- (old round chick; chicks now get a real head below)
		H, headCf = T.Y * 0.9, CFrame.new(0, T.Y * 0.05, 0)
		ctx.headCf, ctx.H = headCf, H
		ctx.headAdd = function(name, shape, size, cf, col, mat)
			return add(name, shape, size, headCf * cf, col, mat)
		end
		for _, sx in ipairs({ -1, 1 }) do
			petEye(ctx.headAdd, CFrame.new(sx * H * 0.2, H * 0.12, -H * 0.41), H * 0.26, ctx.iris)
			ctx.headAdd("Blush", "Blob", Vector3.new(H * 0.17, H * 0.09, H * 0.06), CFrame.new(sx * H * 0.33, -H * 0.03, -H * 0.42), BLUSH)
		end
	else
		H = S * (if kind == "Owl" then 0.78 elseif kind == "Chick" then 0.56 else 0.6)
		headCf = CFrame.new(0, T.Y * 0.45 + H * (if kind == "Owl" then 0.2 else 0.32), -T.Z * (if kind == "Duck" then 0.35 else 0.1))
		makeHead(ctx, headCf, H, if kind == "Penguin" then BLACK else ctx.color, { Mouth = false, EyeSize = if kind == "Owl" then 0.34 else 0.27 })
	end
	local headAdd = ctx.headAdd
	-- beak / bill
	if kind == "Duck" then
		headAdd("Bill", "Blob", Vector3.new(H * 0.44, H * 0.12, H * 0.36), CFrame.new(0, -H * 0.1, -H * 0.56), orange)
		headAdd("BillLow", "Blob", Vector3.new(H * 0.38, H * 0.08, H * 0.28), CFrame.new(0, -H * 0.17, -H * 0.54), orange:Lerp(BLACK, 0.15))
	else
		beak(headAdd, H * (if kind == "Owl" then 0.2 else 0.3), H * 0.22, CFrame.new(0, -H * 0.06, -H * 0.56), if kind == "Owl" then Color3.fromRGB(230, 180, 80) else orange)
	end
	if kind == "Penguin" then
		headAdd("Face", "Blob", Vector3.new(H * 0.7, H * 0.55, H * 0.2), CFrame.new(0, -H * 0.02, -H * 0.36), WHITE)
	elseif kind == "Owl" then
		headAdd("FaceDisc", "Blob", Vector3.new(H * 0.84, H * 0.66, H * 0.16), CFrame.new(0, H * 0.02, -H * 0.36), ctx.light)
		for _, sx in ipairs({ -1, 1 }) do
			headAdd("EarTuft", "Blob", Vector3.new(H * 0.14, H * 0.34, H * 0.12), CFrame.new(sx * H * 0.32, H * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-20 * sx)), ctx.dark)
		end
	elseif kind == "Bird" or kind == "Phoenix" then
		for i = -1, 1 do
			headAdd("Crest", "Blob", Vector3.new(H * 0.1, H * 0.46, H * 0.18), CFrame.new(i * H * 0.1, H * 0.55, H * 0.05) * CFrame.Angles(math.rad(-20), 0, math.rad(i * 25)), if kind == "Phoenix" then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(255, 120, 60), if kind == "Phoenix" then Enum.Material.Neon else nil)
		end
	elseif kind == "Duck" then
		headAdd("Tuft", "Blob", Vector3.new(H * 0.1, H * 0.34, H * 0.1), CFrame.new(0, H * 0.56, 0) * CFrame.Angles(math.rad(-25), 0, 0), ctx.color)
	end
	-- wings
	for _, sx in ipairs({ -1, 1 }) do
		if kind == "Penguin" then
			add("Flipper", "Blob", Vector3.new(S * 0.1, S * 0.5, S * 0.22), CFrame.new(sx * T.X * 0.52, -T.Y * 0.05, 0) * CFrame.Angles(0, 0, math.rad(-18 * sx)), BLACK)
		elseif kind == "Chick" then
			add("Wing", "Blob", Vector3.new(S * 0.12, S * 0.3, S * 0.36), CFrame.new(sx * T.X * 0.5, -T.Y * 0.05, 0) * CFrame.Angles(0, 0, math.rad(-35 * sx)), ctx.color:Lerp(orange, 0.3))
		elseif kind == "Phoenix" then
			local root = CFrame.new(sx * T.X * 0.4, T.Y * 0.2, S * 0.05)
			for f = 0, 4 do
				local col = Color3.fromRGB(255, 200 - f * 30, 60 - f * 8)
				add("WingFeather", "Blob", Vector3.new(S * (0.9 - f * 0.1), S * 0.08, S * (0.32 - f * 0.03)), root * CFrame.Angles(0, math.rad(f * 12 * sx), math.rad((40 - f * 14) * sx)) * CFrame.new(sx * S * 0.42, 0, 0), col, if f >= 2 then Enum.Material.Neon else nil)
			end
		else
			local root = CFrame.new(sx * T.X * 0.5, 0, S * 0.05) * CFrame.Angles(0, 0, math.rad(-12 * sx))
			featherWing(ctx, sx, root, 0.55, ctx.dark, ctx.dark:Lerp(BLACK, 0.2), 6)
		end
	end
	-- tail
	if kind == "Phoenix" then
		for i = -2, 2 do
			local plume = CFrame.new(i * S * 0.08, -T.Y * 0.1, T.Z * 0.45) * CFrame.Angles(math.rad(20), math.rad(i * 12), 0)
			add("Plume", "Blob", Vector3.new(S * 0.14, S * 0.06, S * 1.1), plume * CFrame.new(0, 0, S * 0.5), Color3.fromRGB(255, 120 + (i + 2) * 25, 40), Enum.Material.Neon)
		end
	elseif kind == "Chick" then
		add("Shell", "Blob", Vector3.new(T.X * 1.04, S * 0.36, T.Z * 1.04), CFrame.new(0, -T.Y * 0.35, 0), Color3.fromRGB(250, 245, 230))
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			triangle(add, "ShellZig", S * 0.18, S * 0.14, S * 0.04, CFrame.new(math.cos(a) * T.X * 0.48, -T.Y * 0.18, math.sin(a) * T.Z * 0.48) * CFrame.Angles(0, -a - math.pi / 2, 0), Color3.fromRGB(250, 245, 230))
		end
	elseif kind ~= "Penguin" then
		for i = -1, 1 do
			add("TailFeather", "Blob", Vector3.new(S * 0.14, S * 0.06, S * 0.45), CFrame.new(i * S * 0.1, -T.Y * 0.05, T.Z * 0.52) * CFrame.Angles(math.rad(25), math.rad(i * 18), 0), ctx.dark)
		end
	end
end
ANATOMY.Bird = { Torso = Vector3.new(0.72, 0.82, 0.78), Build = function(ctx) birdBuild(ctx, "Bird") end }
ANATOMY.Chick = { Torso = Vector3.new(0.9, 0.9, 0.9), Build = function(ctx) birdBuild(ctx, "Chick") end }
ANATOMY.Duck = { Torso = Vector3.new(0.8, 0.7, 1.05), Build = function(ctx) birdBuild(ctx, "Duck") end }
ANATOMY.Owl = { Torso = Vector3.new(0.86, 0.95, 0.8), Build = function(ctx) birdBuild(ctx, "Owl") end }
ANATOMY.Phoenix = { Torso = Vector3.new(0.72, 0.85, 0.8), Build = function(ctx) birdBuild(ctx, "Phoenix") end }
ANATOMY.Penguin = { Torso = Vector3.new(0.76, 0.98, 0.72), Build = function(ctx) birdBuild(ctx, "Penguin") end }

-- More species -------------------------------------------------------------------
local function hooves(ctx, len, width, color)
	return legs4(ctx, len, width, ctx.color, color or Color3.fromRGB(70, 55, 45), { Beans = false })
end

local function horseBuild(ctx, winged)
	local headAdd, H = mammal(ctx, { Neck = 0.34, Head = 0.56, Snout = 0.62, SnoutW = 0.42, SnoutColor = ctx.color:Lerp(WHITE, 0.25), Ears = "Pointy", Leg = 0.52, LegW = 0.16, Paw = Color3.fromRGB(70, 55, 45), Tail = nil, Beans = false })
	local mane = ctx.dark:Lerp(ctx.rarity.Color, 0.25)
	for i = 0, 5 do
		ctx.add("Mane", "Blob", Vector3.new(ctx.S * 0.12, ctx.S * 0.26, ctx.S * 0.18), CFrame.new(0, ctx.T.Y * 0.35 + ctx.S * (0.62 - i * 0.1), -ctx.T.Z * 0.5 + ctx.S * i * 0.06) * CFrame.Angles(math.rad(-30), 0, 0), mane)
	end
	for i = 0, 4 do
		ctx.add("Tail", "Blob", Vector3.new(ctx.S * 0.15, ctx.S * 0.15, ctx.S * 0.3), CFrame.new(0, ctx.T.Y * 0.1 - i * ctx.S * 0.1, ctx.T.Z * 0.5 + ctx.S * (0.1 + i * 0.07)) * CFrame.Angles(math.rad(-50), 0, 0), mane)
	end
	if winged then
		for _, sx in ipairs({ -1, 1 }) do
			local root = CFrame.new(sx * ctx.T.X * 0.45, ctx.T.Y * 0.35, -ctx.T.Z * 0.1)
			for f = 0, 4 do
				ctx.add("WingFeather", "Blob", Vector3.new(ctx.S * (0.8 - f * 0.1), ctx.S * 0.07, ctx.S * (0.3 - f * 0.03)), root * CFrame.Angles(0, math.rad(f * 10 * sx), math.rad((50 - f * 12) * sx)) * CFrame.new(sx * ctx.S * 0.38, 0, 0), if f == 0 then ctx.color:Lerp(ctx.rarity.Color, 0.4) else WHITE)
			end
		end
	end
end
ANATOMY.Pony = { Torso = Vector3.new(0.72, 0.66, 1.15), Build = function(ctx) horseBuild(ctx, false) end }
ANATOMY.Pegasus = { Torso = Vector3.new(0.72, 0.66, 1.15), Build = function(ctx) horseBuild(ctx, true) end }

ANATOMY.Giraffe = { Torso = Vector3.new(0.72, 0.66, 1.05), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Neck = 0.9, Head = 0.5, Snout = 0.45, SnoutW = 0.4, Ears = "Side", Leg = 0.62, LegW = 0.14, Paw = Color3.fromRGB(80, 60, 45), Tail = "Tuft", Beans = false })
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ossicone", "Blob", Vector3.new(H * 0.1, H * 0.34, H * 0.1), CFrame.new(sx * H * 0.16, H * 0.55, H * 0.05), ctx.dark)
		headAdd("OssiconeTip", "Ball", Vector3.one * H * 0.14, CFrame.new(sx * H * 0.16, H * 0.74, H * 0.05), ctx.dark:Lerp(BLACK, 0.3))
	end
	for i = 1, 8 do
		local pos = Vector3.new((if i % 2 == 0 then 1 else -1) * ctx.T.X * 0.48, ctx.T.Y * (0.25 - (i % 3) * 0.2), -ctx.T.Z * 0.4 + i * ctx.T.Z * 0.1)
		ctx.add("Spot", "Blob", Vector3.new(ctx.S * 0.05, ctx.S * 0.16, ctx.S * 0.18), CFrame.new(pos), ctx.dark)
	end
end }

ANATOMY.Kangaroo = { Torso = Vector3.new(0.7, 0.9, 0.7), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Pouch", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.45, S * 0.22), CFrame.new(0, -T.Y * 0.18, -T.Z * 0.42), ctx.light)
	add("Joey", "Ball", Vector3.one * S * 0.24, CFrame.new(0, -T.Y * 0.02, -T.Z * 0.5), ctx.color:Lerp(WHITE, 0.2))
	for _, sx in ipairs({ -1, 1 }) do
		add("Haunch", "Ball", Vector3.one * S * 0.44, CFrame.new(sx * T.X * 0.4, -T.Y * 0.3, T.Z * 0.1), ctx.color)
		add("Foot", "Blob", Vector3.new(S * 0.16, S * 0.12, S * 0.6), CFrame.new(sx * T.X * 0.38, -T.Y * 0.47, -T.Z * 0.2), ctx.dark)
		add("Arm", "Blob", Vector3.new(S * 0.1, S * 0.3, S * 0.1), CFrame.new(sx * S * 0.16, T.Y * 0.05, -T.Z * 0.45) * CFrame.Angles(math.rad(-30), 0, 0), ctx.color)
	end
	ctx.footDrop = T.Y * 0.47 + S * 0.06
	local H = S * 0.56
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + S * 0.22, -T.Z * 0.2), H, ctx.color, { Mouth = false })
	snoutOn(headAdd, H, 0.5, 0.36, ctx.light)
	earsOn(headAdd, H, "Tall", ctx.color)
	for i = 0, 4 do
		add("Tail", "Blob", Vector3.new(S * (0.26 - i * 0.04), S * (0.26 - i * 0.04), S * 0.3), CFrame.new(0, -T.Y * 0.3 - i * S * 0.04, T.Z * 0.5 + i * S * 0.2), ctx.color)
	end
end }

ANATOMY.Koala = { Torso = Vector3.new(0.8, 0.82, 0.72), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.7, S * 0.2), CFrame.new(0, -T.Y * 0.05, -T.Z * 0.42), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		add("Leg", "Blob", Vector3.new(S * 0.24, S * 0.22, S * 0.36), CFrame.new(sx * T.X * 0.32, -T.Y * 0.42, -T.Z * 0.22), ctx.color)
		add("Arm", "Blob", Vector3.new(S * 0.18, S * 0.42, S * 0.18), CFrame.new(sx * T.X * 0.45, -T.Y * 0.05, -T.Z * 0.3) * CFrame.Angles(math.rad(-30), 0, math.rad(15 * sx)), ctx.color)
	end
	ctx.footDrop = T.Y * 0.42 + S * 0.11
	local H = S * 0.78
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + S * 0.24, -T.Z * 0.08), H, ctx.color, { Mouth = false })
	headAdd("Nose", "Blob", Vector3.new(H * 0.22, H * 0.3, H * 0.16), CFrame.new(0, -H * 0.08, -H * 0.46), Color3.fromRGB(60, 55, 60))
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ear", "Ball", Vector3.one * H * 0.44, CFrame.new(sx * H * 0.5, H * 0.3, H * 0.05), ctx.color)
		headAdd("EarFluff", "Ball", Vector3.one * H * 0.3, CFrame.new(sx * H * 0.5, H * 0.3, -H * 0.06), ctx.light)
	end
	add("Leaf", "Blob", Vector3.new(S * 0.3, S * 0.05, S * 0.14), ctx.headCf * CFrame.new(H * 0.2, -H * 0.3, -H * 0.5) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(90, 170, 90))
end }

ANATOMY.Sloth = { Torso = Vector3.new(0.78, 0.7, 0.9), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	for _, sx in ipairs({ -1, 1 }) do
		add("Arm", "Blob", Vector3.new(S * 0.16, S * 0.6, S * 0.16), CFrame.new(sx * T.X * 0.5, -T.Y * 0.08, -T.Z * 0.25) * CFrame.Angles(math.rad(-20), 0, math.rad(20 * sx)), ctx.color)
		for c = -1, 1 do
			add("Claw", "Blob", Vector3.new(S * 0.03, S * 0.14, S * 0.03), CFrame.new(sx * T.X * 0.56 + c * S * 0.04, -T.Y * 0.08 - S * 0.34, -T.Z * 0.25 - S * 0.12), Color3.fromRGB(240, 230, 210))
		end
		add("Leg", "Blob", Vector3.new(S * 0.2, S * 0.2, S * 0.36), CFrame.new(sx * T.X * 0.3, -T.Y * 0.42, -T.Z * 0.1), ctx.color)
	end
	ctx.footDrop = T.Y * 0.42 + S * 0.1
	local H = S * 0.62
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.48 + S * 0.16, -T.Z * 0.32), H, ctx.color:Lerp(WHITE, 0.4))
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("EyeStripe", "Blob", Vector3.new(H * 0.36, H * 0.16, H * 0.1), CFrame.new(sx * H * 0.26, H * 0.06, -H * 0.37) * CFrame.Angles(0, 0, math.rad(-15 * sx)), ctx.dark)
	end
	headAdd("Nose", "Blob", Vector3.new(H * 0.16, H * 0.1, H * 0.08), CFrame.new(0, -H * 0.05, -H * 0.47), BLACK)
end }

ANATOMY.Otter = { Torso = Vector3.new(0.58, 0.5, 1.1), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.58, Snout = 0.3, SnoutW = 0.44, SnoutColor = ctx.light, Ears = "Round", Leg = 0.16, LegW = 0.15, Tail = nil })
	for i = 0, 3 do
		ctx.add("Tail", "Blob", Vector3.new(ctx.S * (0.2 - i * 0.03), ctx.S * 0.12, ctx.S * 0.24), CFrame.new(0, -ctx.T.Y * 0.1, ctx.T.Z * 0.5 + i * ctx.S * 0.18), ctx.color)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 1 do
			headAdd("Whisker", "Block", Vector3.new(H * 0.3, H * 0.02, H * 0.02), CFrame.new(sx * H * 0.3, -H * 0.16 - j * H * 0.05, -H * 0.5) * CFrame.Angles(0, 0, math.rad((8 - j * 14) * sx)), WHITE)
		end
	end
	ctx.add("Shell", "Blob", Vector3.new(ctx.S * 0.2, ctx.S * 0.07, ctx.S * 0.16), ctx.headCf * CFrame.new(0, -H * 0.55, -H * 0.3), Color3.fromRGB(250, 200, 210))
end }

ANATOMY.Squirrel = { Torso = Vector3.new(0.6, 0.66, 0.72), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.7, T.Y * 0.6, S * 0.18), CFrame.new(0, -T.Y * 0.05, -T.Z * 0.42), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		add("Haunch", "Ball", Vector3.one * S * 0.34, CFrame.new(sx * T.X * 0.38, -T.Y * 0.28, T.Z * 0.05), ctx.color)
		add("Foot", "Blob", Vector3.new(S * 0.14, S * 0.1, S * 0.32), CFrame.new(sx * T.X * 0.36, -T.Y * 0.45, -T.Z * 0.2), ctx.dark)
		add("Paw", "Ball", Vector3.one * S * 0.12, CFrame.new(sx * S * 0.1, -T.Y * 0.05, -T.Z * 0.52), ctx.color)
	end
	add("Acorn", "Ball", Vector3.new(S * 0.16, S * 0.2, S * 0.16), CFrame.new(0, -T.Y * 0.1, -T.Z * 0.58), Color3.fromRGB(170, 110, 60))
	ctx.footDrop = T.Y * 0.45 + S * 0.05
	local H = S * 0.6
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + S * 0.18, -T.Z * 0.12), H, ctx.color, { Fur = true })
	earsOn(headAdd, H, "Pointy", ctx.color)
	headAdd("Nose", "Blob", Vector3.new(H * 0.1, H * 0.07, H * 0.05), CFrame.new(0, -H * 0.04, -H * 0.48), BLUSH)
	for i = 0, 4 do
		add("Tail", "Blob", Vector3.new(S * 0.34, S * 0.34, S * 0.36), CFrame.new(0, -T.Y * 0.2 + i * S * 0.2, T.Z * 0.55 + math.sin(i * 0.8) * S * 0.18), ctx.color:Lerp(ctx.light, i * 0.1))
	end
end }

ANATOMY.Mouse = { Torso = Vector3.new(0.62, 0.52, 0.82), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.62, Snout = 0.3, SnoutW = 0.32, NoseColor = BLUSH, Ears = nil, Leg = 0.1, LegW = 0.12, Tail = nil })
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ear", "Cyl", Vector3.new(H * 0.06, H * 0.52, H * 0.52), CFrame.new(sx * H * 0.36, H * 0.42, H * 0.05) * CFrame.Angles(0, math.rad(90 - 20 * sx), 0), ctx.color)
		headAdd("InnerEar", "Cyl", Vector3.new(H * 0.05, H * 0.36, H * 0.36), CFrame.new(sx * H * 0.36, H * 0.42, 0) * CFrame.Angles(0, math.rad(90 - 20 * sx), 0), BLUSH)
	end
	local prev = CFrame.new(0, -ctx.T.Y * 0.1, ctx.T.Z * 0.5)
	for i = 1, 5 do
		prev = prev * CFrame.Angles(math.rad(12), math.rad(10), 0) * CFrame.new(0, 0, ctx.S * 0.14)
		ctx.add("Tail", "Blob", Vector3.new(ctx.S * 0.05, ctx.S * 0.05, ctx.S * 0.18), prev, BLUSH)
	end
	ctx.add("Cheese", "Wedge", Vector3.new(ctx.S * 0.2, ctx.S * 0.14, ctx.S * 0.24), ctx.headCf * CFrame.new(0, -H * 0.5, -H * 0.5), Color3.fromRGB(255, 210, 70))
end }

ANATOMY.Hippo = { Torso = Vector3.new(1.05, 0.85, 1.25), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.72, HeadUp = 0.1, Ears = "Round", Leg = 0.2, LegW = 0.3, Paw = ctx.dark, Tail = "Stub", Beans = false, Belly = ctx.color:Lerp(Color3.fromRGB(255, 170, 190), 0.4) })
	headAdd("Muzzle", "Blob", Vector3.new(H * 0.9, H * 0.6, H * 0.6), CFrame.new(0, -H * 0.18, -H * 0.42), ctx.color:Lerp(Color3.fromRGB(255, 170, 190), 0.3))
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Nostril", "Ball", Vector3.one * H * 0.1, CFrame.new(sx * H * 0.16, H * 0.06, -H * 0.66), ctx.dark)
		headAdd("Tooth", "Block", Vector3.new(H * 0.08, H * 0.14, H * 0.06), CFrame.new(sx * H * 0.22, -H * 0.38, -H * 0.7), WHITE)
	end
end }

ANATOMY.Rhino = { Torso = Vector3.new(0.95, 0.8, 1.3), Build = function(ctx)
	local headAdd, H = mammal(ctx, { Head = 0.64, HeadUp = 0.05, Snout = 0.5, SnoutW = 0.56, SnoutColor = ctx.color, Ears = "Pointy", Leg = 0.26, LegW = 0.27, Paw = ctx.dark, Tail = "Tuft", Beans = false, Belly = false })
	headAdd("Horn", "Blob", Vector3.new(H * 0.18, H * 0.5, H * 0.18), CFrame.new(0, H * 0.18, -H * 0.8) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(240, 230, 210))
	headAdd("SmallHorn", "Blob", Vector3.new(H * 0.12, H * 0.26, H * 0.12), CFrame.new(0, H * 0.3, -H * 0.5) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(240, 230, 210))
	for i = 0, 2 do
		ctx.add("ArmorPlate", "Blob", Vector3.new(ctx.T.X * 1.02, ctx.S * 0.08, ctx.S * 0.24), CFrame.new(0, ctx.T.Y * 0.1, -ctx.T.Z * 0.25 + i * ctx.T.Z * 0.25), ctx.dark)
	end
end }

ANATOMY.Croc = { Torso = Vector3.new(0.72, 0.4, 1.3), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.5, T.Z * 0.9), CFrame.new(0, -T.Y * 0.2, 0), ctx.light)
	ctx.footDrop = legs4(ctx, 0.12, 0.14, ctx.color, ctx.dark, { Splay = true, Beans = false })
	for i = 0, 5 do
		add("Scute", "Block", Vector3.new(S * 0.1, S * 0.1, S * 0.1), CFrame.new(-S * 0.12, T.Y * 0.48, -T.Z * 0.4 + i * T.Z * 0.16) * CFrame.Angles(0, math.rad(45), 0), ctx.dark)
		add("Scute", "Block", Vector3.new(S * 0.1, S * 0.1, S * 0.1), CFrame.new(S * 0.12, T.Y * 0.48, -T.Z * 0.4 + i * T.Z * 0.16) * CFrame.Angles(0, math.rad(45), 0), ctx.dark)
	end
	local H = S * 0.56
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.25, -T.Z * 0.55), H, ctx.color, { Mouth = false, EyeY = 0.3 })
	headAdd("Snout", "Blob", Vector3.new(H * 0.62, H * 0.3, H * 1.1), CFrame.new(0, -H * 0.18, -H * 0.8), ctx.color)
	headAdd("Jaw", "Blob", Vector3.new(H * 0.56, H * 0.14, H * 1.0), CFrame.new(0, -H * 0.36, -H * 0.72), ctx.light)
	for i = 0, 4 do
		for _, sx in ipairs({ -1, 1 }) do
			triangle(headAdd, "Tooth", H * 0.06, H * 0.09, H * 0.02, CFrame.new(sx * H * 0.28, -H * 0.3, -H * (0.45 + i * 0.16)) * CFrame.Angles(0, 0, math.pi), WHITE)
		end
	end
	tailOn(ctx, "Dragon", CFrame.new(0, 0, T.Z * 0.45), ctx.color)
end }

local function waterBird(ctx, kind)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local legColor = if kind == "Flamingo" then ctx.color:Lerp(BLACK, 0.2) else BLACK
	ctx.footDrop = birdLegs(ctx, if kind == "Flamingo" then 0.7 else 0.08, legColor)
	-- long S-curved neck
	local prev = CFrame.new(0, T.Y * 0.2, -T.Z * 0.4)
	for i = 1, 4 do
		prev = prev * CFrame.Angles(math.rad(if i <= 2 then 38 else -30), 0, 0) * CFrame.new(0, 0, -S * 0.15)
		add("Neck", "Blob", Vector3.new(S * 0.16, S * 0.16, S * 0.26), prev, ctx.color)
	end
	local H = S * 0.44
	local headAdd = makeHead(ctx, CFrame.new(prev.Position + Vector3.new(0, S * 0.14, -S * 0.04)), H, ctx.color, { Mouth = false })
	if kind == "Flamingo" then
		headAdd("Beak", "Blob", Vector3.new(H * 0.22, H * 0.2, H * 0.6), CFrame.new(0, -H * 0.12, -H * 0.62) * CFrame.Angles(math.rad(25), 0, 0), WHITE)
		headAdd("BeakTip", "Blob", Vector3.new(H * 0.16, H * 0.16, H * 0.24), CFrame.new(0, -H * 0.3, -H * 0.84) * CFrame.Angles(math.rad(45), 0, 0), BLACK)
	else
		headAdd("Beak", "Blob", Vector3.new(H * 0.3, H * 0.14, H * 0.44), CFrame.new(0, -H * 0.1, -H * 0.58), Color3.fromRGB(255, 140, 40))
		headAdd("Knob", "Ball", Vector3.one * H * 0.18, CFrame.new(0, -H * 0.02, -H * 0.4), BLACK)
	end
	for _, sx in ipairs({ -1, 1 }) do
		featherWing(ctx, sx, CFrame.new(sx * T.X * 0.48, T.Y * 0.08, S * 0.05) * CFrame.Angles(0, 0, math.rad(-10 * sx)), 0.6, ctx.color:Lerp(WHITE, 0.2), if kind == "Flamingo" then BLACK else ctx.color, 6)
	end
	add("TailFeather", "Blob", Vector3.new(S * 0.3, S * 0.1, S * 0.3), CFrame.new(0, T.Y * 0.15, T.Z * 0.5) * CFrame.Angles(math.rad(30), 0, 0), ctx.color)
end
ANATOMY.Flamingo = { Torso = Vector3.new(0.6, 0.55, 0.85), Build = function(ctx) waterBird(ctx, "Flamingo") end }
ANATOMY.Swan = { Torso = Vector3.new(0.75, 0.6, 1.0), Build = function(ctx) waterBird(ctx, "Swan") end }

ANATOMY.Parrot = { Torso = Vector3.new(0.66, 0.85, 0.7), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	ctx.footDrop = birdLegs(ctx, 0.1, Color3.fromRGB(90, 90, 100))
	local H = S * 0.6
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.45 + H * 0.3, -T.Z * 0.1), H, ctx.color, { Mouth = false })
	headAdd("Beak", "Blob", Vector3.new(H * 0.3, H * 0.4, H * 0.3), CFrame.new(0, -H * 0.12, -H * 0.5) * CFrame.Angles(math.rad(30), 0, 0), Color3.fromRGB(60, 60, 70))
	headAdd("FacePatch", "Blob", Vector3.new(H * 0.7, H * 0.4, H * 0.16), CFrame.new(0, H * 0.05, -H * 0.36), WHITE)
	local wing1, wing2 = Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 220, 60)
	for _, sx in ipairs({ -1, 1 }) do
		featherWing(ctx, sx, CFrame.new(sx * T.X * 0.5, 0, S * 0.05) * CFrame.Angles(0, 0, math.rad(-10 * sx)), 0.55, wing1, wing2, 6)
	end
	for i = -1, 1 do
		add("TailFeather", "Blob", Vector3.new(S * 0.1, S * 0.05, S * 0.8), CFrame.new(i * S * 0.07, -T.Y * 0.35, T.Z * 0.5) * CFrame.Angles(math.rad(-40), math.rad(i * 8), 0) * CFrame.new(0, 0, S * 0.35), ({ Color3.fromRGB(255, 60, 60), wing1, wing2 })[i + 2])
	end
end }

ANATOMY.Peacock = { Torso = Vector3.new(0.62, 0.7, 0.85), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	ctx.footDrop = birdLegs(ctx, 0.24, Color3.fromRGB(120, 110, 100))
	local neck = CFrame.new(0, T.Y * 0.4, -T.Z * 0.35) * CFrame.Angles(math.rad(-15), 0, 0)
	add("Neck", "Blob", Vector3.new(S * 0.2, S * 0.5, S * 0.2), neck, ctx.color)
	local H = S * 0.44
	local headAdd = makeHead(ctx, neck * CFrame.new(0, S * 0.3, -S * 0.05), H, ctx.color, { Mouth = false })
	beak(headAdd, H * 0.3, H * 0.2, CFrame.new(0, -H * 0.06, -H * 0.56), Color3.fromRGB(80, 80, 90))
	for i = -1, 1 do
		headAdd("Crest", "Block", Vector3.new(H * 0.03, H * 0.4, H * 0.03), CFrame.new(i * H * 0.08, H * 0.6, 0) * CFrame.Angles(0, 0, math.rad(i * 15)), ctx.color)
		headAdd("CrestTip", "Ball", Vector3.one * H * 0.1, CFrame.new(i * H * 0.13, H * 0.8, 0), ctx.rarity.Color)
	end
	-- big fanned tail with eye spots
	for i = 0, 10 do
		local a = math.rad(-75 + i * 15)
		local cf = CFrame.new(0, T.Y * 0.1, T.Z * 0.45) * CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(-15), 0, 0)
		add("TailFan", "Blob", Vector3.new(S * 0.24, S * 1.3, S * 0.05), cf * CFrame.new(0, S * 0.65, 0), Color3.fromRGB(60, 170, 110):Lerp(ctx.color, 0.3))
		add("EyeSpot", "Blob", Vector3.new(S * 0.16, S * 0.2, S * 0.06), cf * CFrame.new(0, S * 1.15, 0), Color3.fromRGB(60, 90, 220))
		add("EyeSpotCore", "Blob", Vector3.new(S * 0.08, S * 0.1, S * 0.07), cf * CFrame.new(0, S * 1.15, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
	end
end }

local function whaleBuild(ctx, kind)
	local S, T, add = ctx.S, ctx.T, ctx.add
	ctx.footDrop = T.Y * 0.5
	add("Belly", "Blob", Vector3.new(T.X * 0.85, T.Y * 0.45, T.Z * 0.85), CFrame.new(0, -T.Y * 0.22, 0), ctx.light)
	for _, sx in ipairs({ -1, 1 }) do
		petEye(add, CFrame.new(sx * T.X * 0.38, T.Y * 0.05, -T.Z * 0.28) * CFrame.Angles(0, math.rad(-55 * sx), 0), S * 0.2, ctx.iris)
		add("Blush", "Blob", Vector3.new(S * 0.12, S * 0.07, S * 0.05), CFrame.new(sx * T.X * 0.42, -T.Y * 0.12, -T.Z * 0.2) * CFrame.Angles(0, math.rad(-60 * sx), 0), BLUSH)
		add("Flipper", "Blob", Vector3.new(S * 0.4, S * 0.06, S * 0.22), CFrame.new(sx * T.X * 0.55, -T.Y * 0.25, -T.Z * 0.1) * CFrame.Angles(0, math.rad(-25 * sx), math.rad(-25 * sx)), ctx.dark)
		add("Fluke", "Blob", Vector3.new(S * 0.45, S * 0.06, S * 0.28), CFrame.new(sx * S * 0.22, T.Y * 0.1, T.Z * 0.5 + S * 0.25) * CFrame.Angles(0, math.rad(20 * sx), math.rad(10 * sx)), ctx.dark)
	end
	ctx.headCf, ctx.H = CFrame.new(0, 0, -T.Z * 0.15), T.Y
	ctx.headAdd = function(name, shape, size, cf, col, mat)
		return add(name, shape, size, ctx.headCf * cf, col, mat)
	end
	if kind == "Dolphin" then
		add("Beak", "Blob", Vector3.new(S * 0.2, S * 0.16, S * 0.4), CFrame.new(0, -T.Y * 0.1, -T.Z * 0.55), ctx.color)
		triangle(add, "DorsalFin", S * 0.3, S * 0.34, S * 0.06, CFrame.new(0, T.Y * 0.6, T.Z * 0.05) * CFrame.Angles(math.rad(-20), math.rad(90), 0), ctx.color)
	else
		add("Mouth", "Blob", Vector3.new(T.X * 0.5, S * 0.04, S * 0.05), CFrame.new(0, -T.Y * 0.1, -T.Z * 0.49), ctx.dark)
		for i = 0, 2 do
			add("Spout", "Ball", Vector3.one * S * (0.16 - i * 0.03), CFrame.new(0, T.Y * 0.55 + i * S * 0.16, -T.Z * 0.15), Color3.fromRGB(180, 230, 255), Enum.Material.Glass)
		end
	end
end
ANATOMY.Dolphin = { Torso = Vector3.new(0.6, 0.6, 1.3), Float = true, Build = function(ctx) whaleBuild(ctx, "Dolphin") end }
ANATOMY.Whale = { Torso = Vector3.new(0.9, 0.8, 1.5), Float = true, Build = function(ctx) whaleBuild(ctx, "Whale") end }

ANATOMY.Griffin = { Torso = Vector3.new(0.78, 0.7, 1.2), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local feathers = WHITE:Lerp(ctx.color, 0.2)
	ctx.footDrop = legs4(ctx, 0.36, 0.2, ctx.color, ctx.dark, { Beans = false })
	add("Chest", "Blob", Vector3.new(T.X * 0.9, T.Y * 0.8, S * 0.4), CFrame.new(0, T.Y * 0.15, -T.Z * 0.4), feathers)
	local H = S * 0.56
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.55 + S * 0.25, -T.Z * 0.5), H, feathers, { Mouth = false })
	beak(headAdd, H * 0.45, H * 0.28, CFrame.new(0, -H * 0.1, -H * 0.6), Color3.fromRGB(255, 200, 60))
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("EarTuft", "Blob", Vector3.new(H * 0.12, H * 0.34, H * 0.12), CFrame.new(sx * H * 0.3, H * 0.52, H * 0.1) * CFrame.Angles(math.rad(20), 0, math.rad(-20 * sx)), feathers)
		local root = CFrame.new(sx * T.X * 0.45, T.Y * 0.4, -T.Z * 0.1)
		for f = 0, 4 do
			add("WingFeather", "Blob", Vector3.new(S * (0.85 - f * 0.1), S * 0.08, S * (0.3 - f * 0.03)), root * CFrame.Angles(0, math.rad(f * 10 * sx), math.rad((55 - f * 12) * sx)) * CFrame.new(sx * S * 0.4, 0, 0), if f % 2 == 0 then feathers else ctx.color:Lerp(ctx.rarity.Color, 0.3))
		end
	end
	tailOn(ctx, "Tuft", CFrame.new(0, T.Y * 0.1, T.Z * 0.46), ctx.color)
end }

ANATOMY.Cerberus = { Torso = Vector3.new(0.9, 0.72, 1.15), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	ctx.footDrop = legs4(ctx, 0.34, 0.22, ctx.color, ctx.dark, { Beans = false })
	local fire = Color3.fromRGB(255, 120, 40)
	local main
	for i = -1, 1 do
		local H = S * (if i == 0 then 0.58 else 0.5)
		local cf = CFrame.new(i * S * 0.36, T.Y * 0.4 + S * (if i == 0 then 0.32 else 0.2), -T.Z * 0.5 - S * 0.05) * CFrame.Angles(0, math.rad(-i * 20), 0)
		add("Neck", "Blob", Vector3.new(S * 0.26, S * 0.4, S * 0.26), CFrame.new(i * S * 0.26, T.Y * 0.35, -T.Z * 0.4) * CFrame.Angles(math.rad(-25), 0, math.rad(-i * 20)), ctx.color)
		local headAdd = makeHead(ctx, cf, H, ctx.color, { Mouth = false })
		snoutOn(headAdd, H, 0.5, 0.38, ctx.light)
		earsOn(headAdd, H, "Pointy", ctx.color, fire)
		headAdd("Collar", "Cyl", Vector3.new(H * 0.14, H * 0.8, H * 0.8), CFrame.new(0, -H * 0.42, H * 0.12) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
		if i == 0 then
			main = { cf, H, headAdd }
		end
	end
	ctx.headCf, ctx.H, ctx.headAdd = main[1], main[2], main[3]
	tailOn(ctx, "Flame", CFrame.new(0, T.Y * 0.12, T.Z * 0.46), ctx.color)
end }


-- Frog: squat body, wide flat head with bulging eyes on top, folded back legs
-- and webbed feet
ANATOMY.Frog = { Torso = Vector3.new(0.9, 0.55, 0.8), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local c, light, dark = ctx.color, ctx.light, ctx.dark
	add("Belly", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.5, T.Z * 0.8), CFrame.new(0, -T.Y * 0.22, -T.Z * 0.05), light)
	local headCf = CFrame.new(0, T.Y * 0.12, -T.Z * 0.42)
	add("Head", "Blob", Vector3.new(T.X * 1.02, S * 0.4, S * 0.62), headCf, c)
	add("Chin", "Blob", Vector3.new(T.X * 0.8, S * 0.16, S * 0.5), headCf * CFrame.new(0, -S * 0.14, -S * 0.02), light)
	add("MouthLine", "Block", Vector3.new(T.X * 0.78, S * 0.025, S * 0.03), headCf * CFrame.new(0, -S * 0.06, -S * 0.3), dark)
	for _, sx in ipairs({ -1, 1 }) do
		local bump = headCf * CFrame.new(sx * S * 0.2, S * 0.2, -S * 0.08)
		add("EyeBump", "Ball", Vector3.one * S * 0.26, bump, c)
		petEye(add, bump * CFrame.new(0, S * 0.02, -S * 0.1) * CFrame.Angles(math.rad(-10), math.rad(-25 * sx), 0), S * 0.34, ctx.iris)
		add("Nostril", "Ball", Vector3.one * S * 0.035, headCf * CFrame.new(sx * S * 0.07, S * 0.08, -S * 0.3), dark)
		-- folded back legs: big thigh, shin along the ground, long webbed foot
		add("Thigh", "Blob", Vector3.new(S * 0.3, S * 0.3, S * 0.46), CFrame.new(sx * T.X * 0.5, -T.Y * 0.05, T.Z * 0.18) * CFrame.Angles(math.rad(-20), 0, 0), c)
		add("Shin", "Blob", Vector3.new(S * 0.16, S * 0.14, S * 0.44), CFrame.new(sx * T.X * 0.55, -T.Y * 0.38, T.Z * 0.05), c)
		add("BackFoot", "Blob", Vector3.new(S * 0.3, S * 0.06, S * 0.4), CFrame.new(sx * T.X * 0.6, -T.Y * 0.5, -T.Z * 0.18), dark)
		-- front legs
		add("Arm", "Blob", Vector3.new(S * 0.12, S * 0.3, S * 0.12), CFrame.new(sx * T.X * 0.34, -T.Y * 0.3, -T.Z * 0.32) * CFrame.Angles(0, 0, math.rad(10 * sx)), c)
		add("FrontFoot", "Blob", Vector3.new(S * 0.2, S * 0.05, S * 0.18), CFrame.new(sx * T.X * 0.38, -T.Y * 0.5, -T.Z * 0.4), dark)
	end
	for i = 1, 5 do
		add("BackSpot", "Blob", Vector3.new(S * 0.14, S * 0.05, S * 0.12), CFrame.new(((i * 37) % 7 - 3) * T.X * 0.1, T.Y * 0.46, ((i * 23) % 5 - 2) * T.Z * 0.15), dark)
	end
	ctx.footDrop = T.Y * 0.5 + S * 0.03
	ctx.headCf, ctx.H = headCf * CFrame.new(0, S * 0.15, 0), S * 0.55
	ctx.headAdd = function(name, shape, size, cf, col, mat)
		return add(name, shape, size, ctx.headCf * cf, col, mat)
	end
end }

-- Octopus / Kraken: a tall mantle with eyes low on the front and eight curling
-- tentacles spread out on the ground
local function octoBuild(ctx, kraken)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local c, dark, light = ctx.color, ctx.dark, ctx.light
	local sucker = if kraken then Color3.fromRGB(140, 255, 230) else light
	local suckerMat = if kraken then Enum.Material.Neon else nil
	add("MantleTop", "Blob", Vector3.new(T.X * 0.9, T.Y * 0.6, T.Z * 0.95), CFrame.new(0, T.Y * 0.3, T.Z * 0.12), c)
	for _, sx in ipairs({ -1, 1 }) do
		petEye(add, CFrame.new(sx * T.X * 0.28, -T.Y * 0.12, -T.Z * 0.4) * CFrame.Angles(0, math.rad(-25 * sx), 0), S * 0.3, ctx.iris)
		add("EyeRidge", "Blob", Vector3.new(S * 0.22, S * 0.08, S * 0.12), CFrame.new(sx * T.X * 0.28, -T.Y * 0.02, -T.Z * 0.4), dark)
	end
	add("Siphon", "Blob", Vector3.new(S * 0.1, S * 0.08, S * 0.12), CFrame.new(T.X * 0.4, -T.Y * 0.3, -T.Z * 0.15), dark)
	local groundY = -T.Y * 0.5 - S * 0.2
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local root = Vector3.new(0, -T.Y * 0.4, 0) + dir * T.X * 0.28
		local knee = Vector3.new(0, groundY + S * 0.06, 0) + dir * (T.X * 0.55 + S * 0.25)
		local tip = knee + dir * S * 0.45 + Vector3.new(0, S * 0.12, 0)
		local curl = tip + dir * S * 0.08 + Vector3.new(0, S * 0.12, 0)
		local w = S * 0.16
		add("Tentacle", "Blob", Vector3.new(w, w, (knee - root).Magnitude + w * 0.5), CFrame.lookAt((root + knee) / 2, knee), if i % 2 == 0 then c else dark)
		add("TentacleEnd", "Blob", Vector3.new(w * 0.75, w * 0.75, (tip - knee).Magnitude + w * 0.4), CFrame.lookAt((knee + tip) / 2, tip), if i % 2 == 0 then c else dark)
		add("TentacleCurl", "Ball", Vector3.one * w * 0.6, CFrame.new(curl), if i % 2 == 0 then c else dark)
		for k = 1, 2 do
			local p = root:Lerp(knee, k / 3) - Vector3.new(0, w * 0.4, 0)
			add("Sucker", "Ball", Vector3.one * w * 0.35, CFrame.new(p), sucker, suckerMat)
		end
	end
	ctx.footDrop = -groundY
	ctx.headCf, ctx.H = CFrame.new(0, T.Y * 0.4, T.Z * 0.1), T.X * 0.9
	ctx.headAdd = function(name, shape, size, cf, col, mat)
		return add(name, shape, size, ctx.headCf * cf, col, mat)
	end
	if kraken then
		local GOLD_C = Color3.fromRGB(255, 205, 60)
		ctx.headAdd("KrakenCrown", "Cyl", Vector3.new(S * 0.14, S * 0.46, S * 0.46), CFrame.new(0, T.Y * 0.32, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD_C, Enum.Material.Metal)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			triangle(ctx.headAdd, "CrownSpike", S * 0.1, S * 0.2, S * 0.04, CFrame.new(math.cos(a) * S * 0.2, T.Y * 0.46, math.sin(a) * S * 0.2) * CFrame.Angles(0, -a - math.pi / 2, 0), sucker, Enum.Material.Neon)
		end
	end
end
ANATOMY.Octopus = { Torso = Vector3.new(0.8, 0.9, 0.8), Build = function(ctx) octoBuild(ctx, false) end }
ANATOMY.Kraken = { Torso = Vector3.new(0.85, 1.0, 0.85), Build = function(ctx) octoBuild(ctx, true) end }

-- Bat: small furry body, big pointed ears, a pug nose with fangs and wide
-- leathery wings; it hovers
ANATOMY.Bat = { Torso = Vector3.new(0.5, 0.55, 0.45), Float = true, Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	add("Belly", "Blob", Vector3.new(T.X * 0.75, T.Y * 0.7, T.Z * 0.5), CFrame.new(0, -T.Y * 0.05, -T.Z * 0.2), ctx.light)
	local H = S * 0.5
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.55, -T.Z * 0.08), H, ctx.color, { Mouth = false })
	earsOn(headAdd, H, "Tall", ctx.color, ctx.dark)
	headAdd("PugNose", "Blob", Vector3.new(H * 0.28, H * 0.18, H * 0.14), CFrame.new(0, -H * 0.1, -H * 0.45), ctx.dark)
	for _, sx in ipairs({ -1, 1 }) do
		triangle(headAdd, "Fang", H * 0.07, H * 0.12, H * 0.03, CFrame.new(sx * H * 0.07, -H * 0.3, -H * 0.42) * CFrame.Angles(0, 0, math.pi), WHITE)
		batWing(ctx, sx, CFrame.new(sx * T.X * 0.4, T.Y * 0.2, 0), 0.75, ctx.dark, ctx.color:Lerp(Color3.new(0, 0, 0), 0.5))
		add("Foot", "Blob", Vector3.new(S * 0.08, S * 0.14, S * 0.08), CFrame.new(sx * T.X * 0.2, -T.Y * 0.55, T.Z * 0.1), ctx.dark)
	end
	ctx.footDrop = T.Y * 0.62
end }

-- Real-animal colors. Common pets are almost exactly their real color,
-- rarer ones keep more of their own fantasy color, and Mythic and up are
-- fully their own (they're magical).
local NATURAL_COLOR = {
	Pup = Color3.fromRGB(165, 120, 80), Cat = Color3.fromRGB(200, 150, 95), Fox = Color3.fromRGB(215, 110, 45),
	Wolf = Color3.fromRGB(140, 140, 145), Lion = Color3.fromRGB(205, 160, 95), Bear = Color3.fromRGB(115, 78, 50),
	Raccoon = Color3.fromRGB(120, 115, 110), Pig = Color3.fromRGB(240, 180, 175), Cow = Color3.fromRGB(245, 243, 238),
	Sheep = Color3.fromRGB(240, 236, 225), Hamster = Color3.fromRGB(215, 165, 110), Bunny = Color3.fromRGB(190, 170, 150),
	Stag = Color3.fromRGB(160, 105, 65), Elephant = Color3.fromRGB(150, 150, 155), Monkey = Color3.fromRGB(120, 85, 55),
	Seal = Color3.fromRGB(140, 145, 150), Newt = Color3.fromRGB(215, 120, 50), Axolotl = Color3.fromRGB(250, 190, 200),
	Turtle = Color3.fromRGB(100, 130, 80), Hedgehog = Color3.fromRGB(140, 110, 85), Dino = Color3.fromRGB(100, 130, 80),
	Fish = Color3.fromRGB(150, 160, 175), Koi = Color3.fromRGB(240, 140, 60), Shark = Color3.fromRGB(120, 135, 150),
	Bird = Color3.fromRGB(110, 140, 195), Chick = Color3.fromRGB(250, 225, 120), Duck = Color3.fromRGB(245, 240, 230),
	Owl = Color3.fromRGB(140, 110, 80), Pony = Color3.fromRGB(150, 100, 60), Giraffe = Color3.fromRGB(225, 180, 100),
	Kangaroo = Color3.fromRGB(180, 120, 80), Koala = Color3.fromRGB(150, 150, 155), Sloth = Color3.fromRGB(140, 115, 90),
	Otter = Color3.fromRGB(110, 80, 55), Squirrel = Color3.fromRGB(170, 100, 55), Mouse = Color3.fromRGB(160, 150, 145),
	Hippo = Color3.fromRGB(145, 120, 130), Rhino = Color3.fromRGB(140, 140, 140), Croc = Color3.fromRGB(80, 110, 60),
	Flamingo = Color3.fromRGB(250, 140, 170), Swan = Color3.fromRGB(250, 250, 250), Parrot = Color3.fromRGB(60, 180, 80),
	Peacock = Color3.fromRGB(40, 90, 170), Dolphin = Color3.fromRGB(130, 150, 175), Whale = Color3.fromRGB(80, 100, 140),
	Frog = Color3.fromRGB(90, 160, 60), Octopus = Color3.fromRGB(220, 110, 90), Bat = Color3.fromRGB(75, 62, 62),
	Crab = Color3.fromRGB(220, 90, 60), Snail = Color3.fromRGB(190, 160, 120), Bee = Color3.fromRGB(245, 200, 50),
	Gorilla = Color3.fromRGB(60, 58, 62), Ladybug = Color3.fromRGB(220, 40, 40), Penguin = Color3.fromRGB(40, 40, 50), Panda = Color3.fromRGB(245, 245, 245),
}
local NATURAL_BLEND = { 0.8, 0.7, 0.55, 0.4, 0.25 } -- by rarity order; Mythic and up: 0
local NATURAL_PATTERNS = { Spots = true, Stripes = true, Patches = true, Freckles = true }

function Visuals.PetColor(def, rarity)
	local color = if def then def.Color else rarity.Color
	local natural = def and NATURAL_COLOR[def.Style]
	local blend = NATURAL_BLEND[rarity.Order] or 0
	if natural and blend > 0 then
		color = color:Lerp(natural, blend)
	end
	return color
end

-- Everyday pets (Common to Epic) look like real animals: no hats or costumes,
-- and only natural markings.
local function isNaturalPet(rarity)
	return rarity.Order <= 4
end


-- Gorilla: a broad, muscular ape that walks on its knuckles, with a big
-- chest, a small head with a heavy brow, and a crown if it's a king
ANATOMY.Gorilla = { Torso = Vector3.new(1.05, 1.0, 0.85), Build = function(ctx)
	local S, T, add = ctx.S, ctx.T, ctx.add
	local c, dark, light = ctx.color, ctx.dark, ctx.light
	local skin = c:Lerp(Color3.fromRGB(40, 35, 40), 0.55)
	add("Chest", "Blob", Vector3.new(T.X * 0.8, T.Y * 0.7, S * 0.3), CFrame.new(0, T.Y * 0.05, -T.Z * 0.42), skin)
	for _, sx in ipairs({ -1, 1 }) do
		add("Shoulder", "Blob", Vector3.new(S * 0.55, S * 0.5, S * 0.55), CFrame.new(sx * T.X * 0.5, T.Y * 0.3, -T.Z * 0.2), c)
		add("Arm", "Blob", Vector3.new(S * 0.32, S * 0.95, S * 0.34), CFrame.new(sx * T.X * 0.58, -T.Y * 0.1, -T.Z * 0.35) * CFrame.Angles(math.rad(-10), 0, math.rad(6 * sx)), c)
		add("Fist", "Blob", Vector3.new(S * 0.36, S * 0.28, S * 0.36), CFrame.new(sx * T.X * 0.6, -T.Y * 0.5 - S * 0.12, -T.Z * 0.45), skin)
		add("Leg", "Blob", Vector3.new(S * 0.3, S * 0.45, S * 0.34), CFrame.new(sx * T.X * 0.3, -T.Y * 0.45, T.Z * 0.25), c)
		add("Foot", "Blob", Vector3.new(S * 0.32, S * 0.16, S * 0.42), CFrame.new(sx * T.X * 0.3, -T.Y * 0.5 - S * 0.14, T.Z * 0.2), skin)
	end
	local H = S * 0.5
	local headAdd = makeHead(ctx, CFrame.new(0, T.Y * 0.5 + H * 0.2, -T.Z * 0.35), H, c, { Mouth = false })
	headAdd("Face", "Blob", Vector3.new(H * 0.8, H * 0.7, H * 0.3), CFrame.new(0, -H * 0.08, -H * 0.36), skin)
	headAdd("Brow", "Block", Vector3.new(H * 0.9, H * 0.16, H * 0.2), CFrame.new(0, H * 0.18, -H * 0.42), dark)
	headAdd("Nose", "Blob", Vector3.new(H * 0.3, H * 0.14, H * 0.1), CFrame.new(0, -H * 0.05, -H * 0.5), skin:Lerp(Color3.new(0, 0, 0), 0.3))
	headAdd("Mouth", "Block", Vector3.new(H * 0.36, H * 0.05, H * 0.05), CFrame.new(0, -H * 0.25, -H * 0.5), Color3.fromRGB(30, 20, 25))
	headAdd("Crest", "Blob", Vector3.new(H * 0.5, H * 0.3, H * 0.6), CFrame.new(0, H * 0.45, H * 0.05), c)
	for _, sx in ipairs({ -1, 1 }) do
		headAdd("Ear", "Blob", Vector3.new(H * 0.14, H * 0.2, H * 0.1), CFrame.new(sx * H * 0.48, 0, 0), skin)
	end
	if ctx.def and ctx.def.Name:find("King") then
		local gold = Color3.fromRGB(255, 205, 60)
		headAdd("KingCrown", "Block", Vector3.new(H * 0.8, H * 0.18, H * 0.8), CFrame.new(0, H * 0.66, 0), gold, Enum.Material.Metal)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			triangle(headAdd, "CrownSpike", H * 0.16, H * 0.3, H * 0.06, CFrame.new(math.cos(a) * H * 0.34, H * 0.88, math.sin(a) * H * 0.34) * CFrame.Angles(0, -a - math.pi / 2, 0), gold, Enum.Material.Metal)
		end
		headAdd("CrownGem", "Block", Vector3.new(H * 0.14, H * 0.14, H * 0.06), CFrame.new(0, H * 0.66, -H * 0.42), ctx.rarity.Color, Enum.Material.Neon)
	end
	ctx.footDrop = T.Y * 0.5 + S * 0.22
end }

-- Builds a pet from its ANATOMY entry (called by Visuals.MakeCreature)
local function buildAnatomy(spec, data, def, rarity, tier, S, color, dark, light)
	local model = Instance.new("Model")
	model.Name = data.Name
	local T = spec.Torso * S
	local body = newPart("Body", "Blob", T, color)
	body.Anchored = true
	body.CFrame = CFrame.new()
	body.Parent = model
	model.PrimaryPart = body
	local add = rigger(model, body)
	local ctx = {
		S = S, T = T, add = add, color = color, dark = dark, light = light, rarity = rarity, def = def, data = data,
		iris = if data.Shiny then Color3.fromRGB(255, 205, 70) else rarity.Color:Lerp(Color3.fromRGB(70, 110, 200), 0.35),
		footDrop = T.Y * 0.5,
		body = body,
	}
	local gloss = add("Gloss", "Blob", Vector3.new(T.X * 0.4, S * 0.12, T.Z * 0.3), CFrame.new(-T.X * 0.18, T.Y * 0.42, -T.Z * 0.1) * CFrame.Angles(math.rad(-10), 0, math.rad(15)), WHITE)
	gloss.Transparency = 0.5
	spec.Build(ctx)

	-- Detail pass: toes on paws and feet, nostrils on noses and soft eyelids
	-- over the eyes (the body sits at the origin while building, so each
	-- part's CFrame is already relative to it).
	local lidColor = dark:Lerp(color, 0.35)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local n, cf, sz = part.Name, part.CFrame, part.Size
			if n == "Paw" or n == "Foot" or n == "FrontFoot" or n == "BackFoot" then
				for k = -1, 1 do
					add("Toe", "Blob", Vector3.new(sz.X * 0.3, sz.Y * 0.55, sz.Z * 0.28), cf * CFrame.new(k * sz.X * 0.3, -sz.Y * 0.12, -sz.Z * 0.42), part.Color:Lerp(Color3.new(0, 0, 0), 0.12))
				end
			elseif n == "Nose" and sz.X > S * 0.05 then
				for _, sx in ipairs({ -1, 1 }) do
					add("Nostril", "Ball", Vector3.one * math.min(sz.X, sz.Y) * 0.28, cf * CFrame.new(sx * sz.X * 0.22, -sz.Y * 0.12, -sz.Z * 0.42), Color3.fromRGB(15, 12, 14))
				end
			elseif n == "Eye" then
				add("EyeLid", "Blob", Vector3.new(sz.X * 1.1, sz.Y * 0.24, sz.Z * 0.9), cf * CFrame.new(0, sz.Y * 0.5, -sz.Z * 0.02), lidColor)
			end
		end
	end

	-- patterns wrap the torso; accessories sit on the head
	if def and def.Pattern and PATTERNS[def.Pattern] and (not isNaturalPet(rarity) or NATURAL_PATTERNS[def.Pattern]) then
		PATTERN_EXTENT = ctx.T * 0.5
		local glow = def.PatternGlow or rarity.Order >= 5
		local col = def.PatternColor or (if def.Pattern == "Stars" or def.Pattern == "Hearts" then color:Lerp(WHITE, 0.7) else dark)
		PATTERNS[def.Pattern](add, S, col, if glow then Enum.Material.Neon else nil)
		PATTERN_EXTENT = nil
	end
	local H, headAdd = ctx.H or S * 0.7, ctx.headAdd or add
	if def and def.Accessory and ACCESSORIES[def.Accessory] and not isNaturalPet(rarity) then
		ACCESSORIES[def.Accessory](headAdd, H, def.Accent or ACCESSORY_COLORS[def.Accessory] or GOLD)
	end
	if tier.Multiplier > 1 then
		headAdd("Crown", "Cyl", Vector3.new(H * 0.16, H * 0.36, H * 0.36), CFrame.new(-H * 0.18, H * 0.55, -H * 0.05) * CFrame.Angles(0, 0, math.rad(90 - 15)), GOLD, Enum.Material.Metal)
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			headAdd("CrownGem", "Ball", Vector3.one * H * 0.07, CFrame.new(-H * 0.18 + math.cos(a) * H * 0.13, H * 0.62, -H * 0.05 + math.sin(a) * H * 0.13), Color3.fromRGB(255, 80, 120), Enum.Material.Neon)
		end
	end
	if rarity.Order >= 6 then
		local halo = headAdd("Halo", "Cyl", Vector3.new(H * 0.06, H * 0.7, H * 0.7), CFrame.new(0, H * 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), rarity.Color, Enum.Material.Neon)
		halo.Transparency = 0.2
	end
	if rarity.Order >= 3 then
		local pl = Instance.new("PointLight")
		pl.Color = rarity.Color
		pl.Range = 10
		pl.Brightness = 1
		pl.Parent = body
	end
	if rarity.Order >= 5 then
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(rarity.Color:Lerp(WHITE, 0.3))
		aura.LightEmission = 1
		aura.Size = NumberSequence.new(S * 0.12, 0)
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Rate = 2 + rarity.Order
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Parent = body
	end
	if rarity.Order >= 7 then
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			add("Orb", "Ball", Vector3.one * S * 0.12, CFrame.new(math.cos(a) * S * 0.85, S * (0.2 + i * 0.14), math.sin(a) * S * 0.85), rarity.Color:Lerp(WHITE, 0.4), Enum.Material.Neon)
		end
	end
	if data.Shiny then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 230, 120)
		sparkles.Parent = body
	end

	-- stand on the lowest part of the model (feet, shell rim, tail coil...);
	-- floaters then hover above that
	local lowest = -ctx.footDrop
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Orb" then
			lowest = math.min(lowest, p.CFrame.Position.Y - p.Size.Y / 2)
		end
	end
	model:SetAttribute("FootDrop", -lowest)
	model:SetAttribute("Hover", if spec.Float then S * 0.45 else 0)

	Visuals.ApplyMutation(model, data.Mutation)

	local top = 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Orb" then
			top = math.max(top, p.CFrame.Position.Y + p.Size.Y / 2)
		end
	end
	Visuals.AddLabel(body, top + 2.2, 240)
	Visuals.RefreshPetLabel(body, data)
	return model
end

-- data = { Name, Rarity, Shiny, Tier, Mutation, Size, Age }
local function buildCreature(data)
	local rarity = Config.RarityById[data.Rarity]
	local def = Config.CreatureByName[data.Name]
	local color = Visuals.PetColor(def, rarity)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.3)
	local light = color:Lerp(WHITE, 0.45)
	local tier = Config.Tiers[data.Tier or 1] or Config.Tiers[1]
	-- grows with age (Baby -> Adult) and with its rolled size / weight
	-- bigger for rarer pets, growing more slowly past Secret so top pets stay a sensible size
	local S = (2.8 + math.min(rarity.Order, 8) * 0.45 + math.max(0, rarity.Order - 8) * 0.15) * tier.Scale * Config.PetVisualScale(data)
	local style = def and def.Style
	if style and ANATOMY[style] then
		return buildAnatomy(ANATOMY[style], data, def, rarity, tier, S, color, dark, light)
	end
	local plan = (style and BODY_PLANS[style]) or "Walker"

	local model = Instance.new("Model")
	model.Name = data.Name

	local body = newPart("Body", "Blob", Vector3.new(S, S * 0.95, S * 0.95), color)
	body.Anchored = true
	body.CFrame = CFrame.new()
	body.Parent = model
	model.PrimaryPart = body
	local add = rigger(model, body)

	-- soft shading: a darker underside and a glossy highlight on top
	add("Underside", "Blob", Vector3.new(S * 0.9, S * 0.4, S * 0.86), CFrame.new(0, -S * 0.24, S * 0.02), color:Lerp(BLACK, 0.12))
	local gloss = add("Gloss", "Blob", Vector3.new(S * 0.34, S * 0.14, S * 0.26), CFrame.new(-S * 0.16, S * 0.4, -S * 0.16) * CFrame.Angles(math.rad(-25), 0, math.rad(20)), WHITE)
	gloss.Transparency = 0.45

	-- shared cartoon face
	if style ~= "Penguin" and style ~= "Monkey" and style ~= "Turtle" then
		add("Belly", "Blob", Vector3.new(S * 0.62, S * 0.55, S * 0.2), CFrame.new(0, -S * 0.14, -S * 0.4), light)
	end
	local iris = if data.Shiny then Color3.fromRGB(255, 205, 70) else rarity.Color:Lerp(Color3.fromRGB(70, 110, 200), 0.35)
	for _, sx in ipairs({ -1, 1 }) do
		petEye(add, CFrame.new(sx * S * 0.2, S * 0.12, -S * 0.41), S * 0.26, iris)
		add("Blush", "Blob", Vector3.new(S * 0.17, S * 0.09, S * 0.06), CFrame.new(sx * S * 0.34, -S * 0.03, -S * 0.42), BLUSH)
		-- little "w" mouth
		add("Mouth", "Blob", Vector3.new(S * 0.1, S * 0.05, S * 0.05), CFrame.new(sx * S * 0.045, -S * 0.1, -S * 0.47) * CFrame.Angles(0, 0, math.rad(25 * sx)), BLACK)
	end
	add("Tongue", "Blob", Vector3.new(S * 0.08, S * 0.06, S * 0.04), CFrame.new(0, -S * 0.13, -S * 0.475), Color3.fromRGB(255, 110, 130))
	if FUR[style] then
		tuft(add, S, color)
	end

	-- legs and feet depend on the body plan
	if plan == "Walker" then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local leg = CFrame.new(sx * S * 0.25, -S * 0.42, sz * S * 0.2)
				add("Leg", "Blob", Vector3.new(S * 0.22, S * 0.26, S * 0.22), leg, color)
				add("Paw", "Blob", Vector3.new(S * 0.26, S * 0.14, S * 0.3), leg * CFrame.new(0, -S * 0.1, -S * 0.04), dark)
				if sz < 0 then
					add("ToeBean", "Blob", Vector3.new(S * 0.14, S * 0.06, S * 0.05), leg * CFrame.new(0, -S * 0.1, -S * 0.19), BLUSH)
				end
			end
		end
	elseif plan == "Biped" then
		for _, sx in ipairs({ -1, 1 }) do
			add("Foot", "Blob", Vector3.new(S * 0.28, S * 0.16, S * 0.36), CFrame.new(sx * S * 0.22, -S * 0.47, -S * 0.08), dark)
			add("ToeBean", "Blob", Vector3.new(S * 0.16, S * 0.06, S * 0.05), CFrame.new(sx * S * 0.22, -S * 0.47, -S * 0.26), BLUSH)
		end
	elseif plan == "Bird" then
		local orange = Color3.fromRGB(255, 160, 50)
		for _, sx in ipairs({ -1, 1 }) do
			add("Leg", "Cyl", Vector3.new(S * 0.14, S * 0.07, S * 0.07), CFrame.new(sx * S * 0.18, -S * 0.46, 0) * CFrame.Angles(0, 0, math.rad(90)), orange)
			for t = -1, 1 do
				add("Toe", "Blob", Vector3.new(S * 0.06, S * 0.05, S * 0.2), CFrame.new(sx * S * 0.18 + t * S * 0.05, -S * 0.52, -S * 0.08) * CFrame.Angles(0, math.rad(t * 25), 0), orange)
			end
		end
	end
	-- floaters hover above the ground and get a soft shadow instead of feet
	local hover = if plan == "Float" then S * 0.45 else 0
	model:SetAttribute("Hover", hover)

	if style and PET_FEATURES[style] then
		PET_FEATURES[style](add, S, color, dark, def)
	end
	decorate(add, S, def, rarity, color, dark)

	if tier.Multiplier > 1 then
		-- fused pets wear a crown
		add("Crown", "Cyl", Vector3.new(S * 0.14, S * 0.34, S * 0.34), CFrame.new(-S * 0.18, S * 0.55, -S * 0.1) * CFrame.Angles(0, 0, math.rad(90 - 15)), GOLD, Enum.Material.Metal)
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			add("CrownGem", "Ball", Vector3.one * S * 0.06, CFrame.new(-S * 0.18 + math.cos(a) * S * 0.12, S * 0.6, -S * 0.1 + math.sin(a) * S * 0.12), Color3.fromRGB(255, 80, 120), Enum.Material.Neon)
		end
	end
	if rarity.Order >= 3 then
		local pl = Instance.new("PointLight")
		pl.Color = rarity.Color
		pl.Range = 10
		pl.Brightness = 1
		pl.Parent = body
	end
	if rarity.Order >= 6 then
		-- Mythic and up: a slowly glowing halo ring floating above the head
		local halo = add("Halo", "Cyl", Vector3.new(S * 0.05, S * 0.6, S * 0.6), CFrame.new(0, S * 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), rarity.Color, Enum.Material.Neon)
		halo.Transparency = 0.2
	end
	if rarity.Order >= 5 then
		-- Legendary and up: a soft sparkle aura in the rarity's color
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(rarity.Color:Lerp(WHITE, 0.3))
		aura.LightEmission = 1
		aura.Size = NumberSequence.new(S * 0.12, 0)
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Rate = 2 + rarity.Order
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Parent = body
	end
	if rarity.Order >= 7 then
		-- Divine and Secret: three glowing orbs floating around the pet
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			add("Orb", "Ball", Vector3.one * S * 0.12, CFrame.new(math.cos(a) * S * 0.75, S * (0.2 + i * 0.12), math.sin(a) * S * 0.75), rarity.Color:Lerp(WHITE, 0.4), Enum.Material.Neon)
		end
	end
	if data.Shiny then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 230, 120)
		sparkles.Parent = body
	end

	Visuals.ApplyMutation(model, data.Mutation)

	Visuals.AddLabel(body, S * 0.6 + 2.6 + (if rarity.Order >= 6 then S * 0.4 else 0), 240)
	Visuals.RefreshPetLabel(body, data)
	return model
end

--------------------------------------------------------------------------------
-- Guardians: each one is its own cartoon creature. Built with feet on the
-- ground at y = 0; returns the model and the height of its pivot (Body center).
--------------------------------------------------------------------------------
local GUARDIANS = {}

-- Starts a guardian: body blob at `bodyY` (in unscaled units), scaled by `sc`.
local function startGuardian(def, bodySize, bodyY, sc, color)
	local model = Instance.new("Model")
	model.Name = def.GuardianName
	local body = newPart("Body", "Blob", bodySize * sc, color)
	body.Anchored = true
	body.CFrame = CFrame.new()
	body.Parent = model
	model.PrimaryPart = body
	local rawAdd = rigger(model, body)
	-- add(name, shape, size, x, y, z, color, material, rot) using ground coordinates
	local function add(name, shape, size, x, y, z, color2, material, rot)
		local offset = CFrame.new(x * sc, (y - bodyY) * sc, z * sc) * (rot or CFrame.new())
		return rawAdd(name, shape, size * sc, offset, color2, material)
	end
	local function eye(x, y, z, size, side)
		addEye(rawAdd, CFrame.new(x * sc, (y - bodyY) * sc, z * sc), size * sc, true, side)
	end
	return model, body, add, eye, bodyY * sc
end

function GUARDIANS.Bear(def)
	local brown = def.GuardianColor
	local tan = Color3.fromRGB(215, 175, 125)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(8, 7.5, 7), 6, 1, brown)
	add("Belly", "Blob", Vector3.new(5, 5, 1.4), 0, 5.4, -3.1, tan)
	add("Head", "Ball", Vector3.one * 6, 0, 11, -1.2, brown)
	add("Muzzle", "Blob", Vector3.new(3.4, 2.3, 2.2), 0, 10.1, -3.9, tan)
	add("Nose", "Blob", Vector3.new(1.3, 0.9, 0.8), 0, 10.8, -5, BLACK)
	add("Mouth", "Blob", Vector3.new(1.6, 0.5, 0.3), 0, 9.4, -4.95, Color3.fromRGB(90, 30, 30))
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.35, 12.1, -3.7, 1.5, sx)
		add("Ear", "Ball", Vector3.one * 2.3, sx * 2.5, 13.7, -0.8, brown)
		add("InnerEar", "Ball", Vector3.one * 1.3, sx * 2.5, 13.6, -1.6, BLUSH)
		add("Arm", "Blob", Vector3.new(2.5, 4.8, 2.5), sx * 4.5, 6.4, -1.4, brown, nil, CFrame.Angles(0, 0, math.rad(20 * sx)))
		add("Paw", "Ball", Vector3.one * 2.4, sx * 5.2, 4.1, -2.5, brown:Lerp(BLACK, 0.2))
		add("PawPad", "Blob", Vector3.new(1.2, 1, 0.4), sx * 5.2, 4.1, -3.7, BLUSH)
		add("Leg", "Blob", Vector3.new(3, 3, 3.2), sx * 2.3, 1.5, -0.4, brown)
		add("Foot", "Blob", Vector3.new(3, 1, 3.6), sx * 2.3, 0.5, -1.2, brown:Lerp(BLACK, 0.2))
		add("Tooth", "Block", Vector3.new(0.35, 0.45, 0.2), sx * 0.45, 9.15, -5.05, WHITE)
	end
	-- bramble crown with berries
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		add("Bramble", "Block", Vector3.new(0.9, 0.9, 0.9), math.cos(a) * 2.1, 13.9 + (i % 2) * 0.4, -1.2 + math.sin(a) * 2.1, Color3.fromRGB(70, 140, 55), nil, CFrame.Angles(a, a, 0))
		if i % 2 == 0 then
			add("Berry", "Ball", Vector3.one * 0.6, math.cos(a) * 2.3, 14.5, -1.2 + math.sin(a) * 2.3, Color3.fromRGB(220, 40, 60))
		end
	end
	add("Tail", "Ball", Vector3.one * 1.8, 0, 5, 3.6, brown)
	return model, height
end

function GUARDIANS.Scorpion(def)
	local shell = def.GuardianColor
	local darkShell = shell:Lerp(BLACK, 0.3)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(7, 3.4, 6), 3, 1.15, shell)
	add("Abdomen", "Blob", Vector3.new(5.6, 3, 4), 0, 3.2, 4, darkShell)
	add("Abdomen2", "Blob", Vector3.new(4.6, 2.7, 3.4), 0, 3.4, 7, shell)
	add("Head", "Blob", Vector3.new(5, 3.2, 3.6), 0, 3.3, -4, shell)
	for _, sx in ipairs({ -1, 1 }) do
		add("EyeStalk", "Block", Vector3.new(0.5, 1.6, 0.5), sx * 1.2, 5.2, -4.5, darkShell)
		eye(sx * 1.2, 6.2, -4.7, 1.4, sx)
		add("ClawArm", "Blob", Vector3.new(1.3, 1.3, 4.2), sx * 3.8, 3.1, -5.8, darkShell, nil, CFrame.Angles(0, math.rad(-20 * sx), 0))
		add("Pincer", "Blob", Vector3.new(2.6, 2, 2.8), sx * 5, 3.3, -8.6, shell)
		add("PincerTop", "Blob", Vector3.new(0.9, 0.9, 3), sx * 4.3, 3.6, -10.7, shell, nil, CFrame.Angles(0, math.rad(15 * sx), 0))
		add("PincerLow", "Blob", Vector3.new(0.8, 0.8, 2.6), sx * 5.7, 3.1, -10.5, darkShell, nil, CFrame.Angles(0, math.rad(-15 * sx), 0))
		for i, z in ipairs({ -1.5, 1, 3.5 }) do
			add("Leg", "Block", Vector3.new(4.2, 0.6, 0.6), sx * 4.8, 1.8, z, darkShell, nil, CFrame.Angles(0, math.rad((i - 2) * 15 * sx), math.rad(-30 * sx)))
		end
	end
	-- curled tail with a glowing stinger
	local tail = { { 0, 4.8, 9.6, 2.5 }, { 0, 7.2, 10.6, 2.2 }, { 0, 9.6, 9.9, 2 }, { 0, 11.2, 7.9, 1.8 } }
	for i, t in ipairs(tail) do
		add("TailSeg", "Ball", Vector3.one * t[4], t[1], t[2], t[3], if i % 2 == 0 then darkShell else shell)
	end
	add("Stinger", "Wedge", Vector3.new(1, 1.4, 2.6), 0, 10.8, 6, Color3.fromRGB(255, 60, 60), Enum.Material.Neon, CFrame.Angles(math.rad(200), 0, 0))
	return model, height
end

function GUARDIANS.Yeti(def)
	local fur = Color3.fromRGB(240, 246, 255)
	local skin = Color3.fromRGB(140, 190, 230)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(9, 10, 8), 8, 1, fur)
	add("Belly", "Blob", Vector3.new(5.5, 6, 1.4), 0, 7.5, -3.6, Color3.fromRGB(215, 232, 250))
	add("Head", "Ball", Vector3.one * 6.5, 0, 13.6, -0.6, fur)
	add("Face", "Blob", Vector3.new(4.6, 4, 1.4), 0, 13.2, -3.2, skin)
	add("Mouth", "Blob", Vector3.new(2.6, 1, 0.5), 0, 12, -3.95, Color3.fromRGB(60, 30, 50))
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.2, 14, -3.9, 1.4, sx)
		add("Fang", "Wedge", Vector3.new(0.45, 0.8, 0.3), sx * 0.7, 11.7, -4.05, WHITE, nil, CFrame.Angles(math.rad(180), 0, 0))
		add("Horn", "Block", Vector3.new(0.9, 2.6, 0.9), sx * 2.6, 17.2, -0.3, Color3.fromRGB(225, 205, 160), nil, CFrame.Angles(0, 0, math.rad(-25 * sx)))
		add("HornTip", "Block", Vector3.new(0.7, 1.6, 0.7), sx * 3.6, 18.6, -0.3, Color3.fromRGB(225, 205, 160), nil, CFrame.Angles(0, 0, math.rad(15 * sx)))
		add("Arm", "Blob", Vector3.new(3.2, 8.5, 3.2), sx * 5.8, 8.2, -0.5, fur, nil, CFrame.Angles(0, 0, math.rad(12 * sx)))
		add("Hand", "Ball", Vector3.one * 3.6, sx * 6.6, 3.8, -1, skin)
		add("Leg", "Blob", Vector3.new(3.4, 3.6, 3.6), sx * 2.4, 1.8, 0, fur)
		add("Foot", "Blob", Vector3.new(3.8, 1.2, 4.8), sx * 2.4, 0.6, -0.8, skin)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("FurTuft", "Ball", Vector3.one * 1.8, math.cos(a) * 4.2, 11.5 + (i % 2) * 0.6, math.sin(a) * 3.6, fur)
	end
	return model, height
end

function GUARDIANS.Golem(def)
	local rock = Color3.fromRGB(60, 48, 48)
	local lava = Color3.fromRGB(255, 110, 30)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(9, 8, 6), 9, 1, rock)
	body:FindFirstChildOfClass("SpecialMesh"):Destroy() -- blocky, not round
	add("Core", "Ball", Vector3.one * 2.6, 0, 9.5, -3.1, lava, Enum.Material.Neon)
	local core = model:FindFirstChild("Core")
	local glow = Instance.new("PointLight")
	glow.Color = lava
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = core
	for i, c in ipairs({ { -2.6, 11, 25 }, { 2.4, 7.5, -30 }, { -1.5, 6.4, 60 }, { 2.9, 11.4, 70 } }) do
		add("Crack", "Block", Vector3.new(2.6, 0.3, 0.3), c[1], c[2], -3.05, lava, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(c[3])))
	end
	add("Head", "Block", Vector3.new(4.6, 4, 4.2), 0, 15, -0.6, rock:Lerp(BLACK, 0.1))
	add("Brow", "Block", Vector3.new(4.8, 0.8, 1), 0, 16.1, -2.7, rock:Lerp(BLACK, 0.3))
	for _, sx in ipairs({ -1, 1 }) do
		add("Eye", "Block", Vector3.new(1.1, 0.7, 0.3), sx * 1.05, 15.3, -2.75, Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
		local shoulder = add("Shoulder", "Block", Vector3.new(4, 3.6, 4), sx * 6, 12.2, 0, rock:Lerp(WHITE, 0.05), nil, CFrame.Angles(0.2, 0.3 * sx, 0.2 * sx))
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 8
		fire.Parent = shoulder
		add("Arm", "Block", Vector3.new(3, 6, 3), sx * 6.6, 7.6, -0.4, rock)
		add("Fist", "Block", Vector3.new(4.2, 3.6, 4.2), sx * 6.9, 3.6, -1, rock:Lerp(BLACK, 0.1))
		add("Knuckles", "Block", Vector3.new(4.3, 0.4, 0.4), sx * 6.9, 4.4, -3.1, lava, Enum.Material.Neon)
		add("Leg", "Block", Vector3.new(3.4, 5, 3.4), sx * 2.4, 2.5, 0, rock)
	end
	add("Mouth", "Block", Vector3.new(2.4, 0.4, 0.3), 0, 13.9, -2.75, lava, Enum.Material.Neon)
	return model, height
end

function GUARDIANS.Wraith(def)
	local robe = Color3.fromRGB(58, 34, 96)
	local glowC = Color3.fromRGB(230, 120, 255)
	local sc = 1.35
	local model, body, add, eye, height = startGuardian(def, Vector3.new(8, 10, 7), 12, sc, robe)
	add("Hood", "Ball", Vector3.one * 7, 0, 17.5, 0.3, robe:Lerp(BLACK, 0.1))
	add("HoodPeak", "Wedge", Vector3.new(3, 3, 3), 0, 21, 1.5, robe:Lerp(BLACK, 0.1), nil, CFrame.Angles(0, math.rad(180), 0))
	add("Face", "Blob", Vector3.new(4.6, 4.4, 1.4), 0, 17, -2.7, Color3.fromRGB(10, 5, 20))
	for _, sx in ipairs({ -1, 1 }) do
		add("Eye", "Blob", Vector3.new(1.3, 0.8, 0.4), sx * 0.95, 17.4, -3.45, glowC, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(-15 * sx)))
		add("Sleeve", "Blob", Vector3.new(2.8, 6.5, 2.8), sx * 5.2, 12.5, -1, robe, nil, CFrame.Angles(math.rad(-25), 0, math.rad(35 * sx)))
		add("Hand", "Ball", Vector3.one * 2, sx * 7, 9.8, -3, Color3.fromRGB(200, 190, 230))
		add("Orb", "Ball", Vector3.one * 1.8, sx * 7.4, 11.4, -4, glowC, Enum.Material.Neon)
	end
	-- floating tattered robe tail (no legs: it hovers)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("Tatter", "Wedge", Vector3.new(1.8, 3.4, 1.4), math.cos(a) * 3.2, 5.6 - (i % 2) * 0.8, math.sin(a) * 2.8, robe:Lerp(BLACK, 0.25), nil, CFrame.Angles(math.rad(180), -a, 0))
	end
	-- crown
	add("CrownBand", "Cyl", Vector3.new(0.8, 4.6, 4.6), 0, 20.6, 0.3, GOLD, Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("CrownSpike", "Wedge", Vector3.new(0.8, 1.8, 0.8), math.cos(a) * 1.9, 21.9, 0.3 + math.sin(a) * 1.9, GOLD, Enum.Material.Metal, CFrame.Angles(0, -a, 0))
		add("CrownGem", "Ball", Vector3.one * 0.6, math.cos(a) * 2.3, 20.6, 0.3 + math.sin(a) * 2.3, glowC, Enum.Material.Neon)
	end
	-- orbiting crystals
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		add("Crystal", "Block", Vector3.new(1.2, 3, 1.2), math.cos(a) * 7.5, 15 + i, math.sin(a) * 7.5, glowC, Enum.Material.Neon, CFrame.Angles(0.3, a, 0.3))
	end
	local aura = Instance.new("ParticleEmitter")
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(glowC, Color3.fromRGB(120, 60, 200))
	aura.LightEmission = 1
	aura.Size = NumberSequence.new(0.8, 0)
	aura.Transparency = NumberSequence.new(0.2, 1)
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Rate = 30
	aura.Speed = NumberRange.new(2, 4)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Parent = body
	local light = Instance.new("PointLight")
	light.Color = glowC
	light.Range = 30
	light.Brightness = 2
	light.Parent = body
	return model, height
end

-- Candy Kingdom: a giant see-through gummy bear with a candy crown
function GUARDIANS.Gummy(def)
	local gummy = def.GuardianColor
	local light = gummy:Lerp(WHITE, 0.35)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(9, 9, 8), 7, 1.15, gummy)
	body.Material = Enum.Material.Glass
	body.Transparency = 0.12
	local function g(name, shape, size, x, y, z, rot)
		local p = add(name, shape, size, x, y, z, gummy, Enum.Material.Glass, rot)
		p.Transparency = 0.12
		return p
	end
	g("Head", "Ball", Vector3.one * 7, 0, 13.4, -0.8)
	add("Muzzle", "Blob", Vector3.new(3.6, 2.6, 2.2), 0, 12.3, -3.8, light, Enum.Material.Glass)
	add("Nose", "Blob", Vector3.new(1.4, 1, 0.8), 0, 13.1, -4.9, gummy:Lerp(BLACK, 0.4))
	add("Mouth", "Blob", Vector3.new(1.8, 0.5, 0.3), 0, 11.5, -4.8, Color3.fromRGB(90, 20, 40))
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.5, 14.5, -3.9, 1.6, sx)
		g("Ear", "Ball", Vector3.one * 2.4, sx * 2.9, 16.6, -0.6)
		g("Arm", "Blob", Vector3.new(2.8, 5.2, 2.8), sx * 5, 7.6, -1.2, CFrame.Angles(0, 0, math.rad(25 * sx)))
		g("Leg", "Blob", Vector3.new(3.4, 3.6, 3.6), sx * 2.6, 1.8, -0.2)
		add("Tooth", "Block", Vector3.new(0.4, 0.5, 0.2), sx * 0.5, 11.3, -4.95, WHITE)
	end
	-- sugar sparkle, gumdrop buttons and a lollipop scepter
	for i, col in ipairs({ Color3.fromRGB(255, 220, 70), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 230, 110) }) do
		add("Gumdrop", "Ball", Vector3.one * 1.3, 0, 8.6 - i * 1.6, -3.9, col)
	end
	add("ScepterStick", "Cyl", Vector3.new(9, 0.6, 0.6), 6.2, 8.5, -4, WHITE, nil, CFrame.Angles(0, 0, math.rad(90)))
	add("ScepterCandy", "Cyl", Vector3.new(0.8, 4.2, 4.2), 6.2, 13.2, -4, Color3.fromRGB(255, 90, 170), nil, CFrame.Angles(0, math.rad(90), 0))
	add("ScepterSwirl", "Cyl", Vector3.new(0.9, 2.6, 2.6), 6.2, 13.2, -4, WHITE, nil, CFrame.Angles(0, math.rad(90), 0))
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		add("CandyCrown", "Ball", Vector3.one * 1.1, math.cos(a) * 2.2, 17.2 + (i % 2) * 0.5, -0.8 + math.sin(a) * 2.2, ({ Color3.fromRGB(255, 90, 170), Color3.fromRGB(255, 230, 80), Color3.fromRGB(110, 220, 255) })[(i % 3) + 1], Enum.Material.Neon)
	end
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = Color3.fromRGB(255, 220, 240)
	sparkle.Parent = body
	return model, height
end

-- Sunken Reef: a huge crab king with barnacles and a coral crown
function GUARDIANS.ReefKing(def)
	local shell = def.GuardianColor
	local dark = shell:Lerp(BLACK, 0.3)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(11, 5, 8), 4.5, 1.2, shell)
	add("ShellTop", "Blob", Vector3.new(10, 3.4, 7.4), 0, 6.2, 0.2, shell:Lerp(WHITE, 0.1))
	add("Belly", "Blob", Vector3.new(8, 2, 6), 0, 3.2, 0, shell:Lerp(WHITE, 0.4))
	for _, sx in ipairs({ -1, 1 }) do
		add("EyeStalk", "Block", Vector3.new(0.6, 3, 0.6), sx * 1.8, 8.6, -2.4, dark)
		eye(sx * 1.8, 10.6, -2.6, 1.6, sx)
		add("Arm", "Blob", Vector3.new(5, 1.6, 1.6), sx * 7, 5.5, -2.6, shell, nil, CFrame.Angles(0, math.rad(30 * sx), math.rad(25 * sx)))
		add("Claw", "Blob", Vector3.new(4.4, 3.6, 3), sx * 9.4, 8, -4.8, shell)
		add("Pincer", "Wedge", Vector3.new(1.6, 1.6, 2.8), sx * 9.4, 10, -6.4, shell:Lerp(WHITE, 0.25))
		add("Pincer", "Wedge", Vector3.new(1.6, 1.2, 2.4), sx * 9.4, 6.6, -6.4, shell:Lerp(WHITE, 0.25), nil, CFrame.Angles(0, 0, math.pi))
		for j = 0, 2 do
			add("CrabLeg", "Blob", Vector3.new(5, 1, 1), sx * 6.5, 2.2, -0.8 + j * 2.2, dark, nil, CFrame.Angles(0, 0, math.rad(-40 * sx)))
		end
	end
	for i = 0, 7 do
		local a = i * 2.1
		add("Barnacle", "Ball", Vector3.one * (0.8 + (i % 3) * 0.2), math.cos(a) * 3.6, 7.4, 0.4 + math.sin(a) * 2.4, Color3.fromRGB(235, 225, 205))
	end
	local coral = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 190, 80), Color3.fromRGB(150, 110, 255) }
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("CoralCrown", "Block", Vector3.new(0.7, 2.6, 0.7), math.cos(a) * 2, 8.6, 0.4 + math.sin(a) * 1.6, coral[(i % 3) + 1], Enum.Material.Neon, CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4))
	end
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	bubbles.Size = NumberSequence.new(0.6, 0.2)
	bubbles.Transparency = NumberSequence.new(0.3, 1)
	bubbles.Lifetime = NumberRange.new(2, 3)
	bubbles.Rate = 8
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Parent = body
	return model, height
end

-- Celestial Heights boss: a floating winged guardian in gold and white
function GUARDIANS.Seraph(def)
	local robe = Color3.fromRGB(250, 248, 240)
	local gold = def.GuardianColor
	local glowC = Color3.fromRGB(255, 240, 170)
	local sc = 1.35
	local model, body, add, eye, height = startGuardian(def, Vector3.new(8, 10, 7), 12, sc, robe)
	add("Sash", "Blob", Vector3.new(8.2, 1.4, 7.2), 0, 13, 0, gold, Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(20)))
	add("Head", "Ball", Vector3.one * 6, 0, 18.5, 0, Color3.fromRGB(255, 235, 215))
	add("Hair", "Blob", Vector3.new(6.4, 3.4, 6.4), 0, 20.2, 0.6, gold)
	for _, sx in ipairs({ -1, 1 }) do
		add("Eye", "Blob", Vector3.new(1.1, 1.3, 0.4), sx * 1.1, 18.6, -2.85, Color3.fromRGB(120, 200, 255), Enum.Material.Neon)
		add("Sleeve", "Blob", Vector3.new(2.6, 6, 2.6), sx * 5, 12.8, -0.6, robe, nil, CFrame.Angles(math.rad(-20), 0, math.rad(30 * sx)))
		add("Hand", "Ball", Vector3.one * 1.8, sx * 6.6, 10.2, -2.4, Color3.fromRGB(255, 235, 215))
		-- two pairs of big feathered wings
		for pair = 0, 1 do
			for f = 0, 3 do
				add("Feather", "Blob", Vector3.new(1.2, 3.2 - f * 0.4, 7 - f * 1.1 - pair * 1.5), sx * (5.5 + f * 1.4 + pair * 0.6), 17 - pair * 5 - f * 0.9, 3 + f * 0.4, if f == 0 then gold:Lerp(WHITE, 0.5) else WHITE, Enum.Material.Neon, CFrame.Angles(math.rad(-20 - pair * 15), math.rad(-30 * sx), math.rad(-25 * sx)))
			end
		end
	end
	add("Spear", "Block", Vector3.new(0.6, 16, 0.6), 7, 12, -3, gold, Enum.Material.Metal)
	add("SpearTip", "Block", Vector3.new(1.4, 2.6, 0.5), 7, 21, -3, glowC, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(45)))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("RobeHem", "Wedge", Vector3.new(1.8, 3, 1.4), math.cos(a) * 3.2, 5.8 - (i % 2) * 0.6, math.sin(a) * 2.8, robe, nil, CFrame.Angles(math.rad(180), -a, 0))
	end
	local halo = add("Halo", "Cyl", Vector3.new(0.5, 6, 6), 0, 23, 0.4, glowC, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(90)))
	halo.Transparency = 0.1
	local aura = Instance.new("ParticleEmitter")
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(glowC, WHITE)
	aura.LightEmission = 1
	aura.Size = NumberSequence.new(0.9, 0)
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Rate = 30
	aura.Speed = NumberRange.new(2, 4)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Parent = body
	local pl = Instance.new("PointLight")
	pl.Color = glowC
	pl.Range = 34
	pl.Brightness = 2
	pl.Parent = body
	return model, height
end

-- Glowshroom Grotto: a walking mushroom giant with a glowing spotted cap
function GUARDIANS.Shroom(def)
	local stem = Color3.fromRGB(230, 225, 215)
	local cap = Color3.fromRGB(150, 60, 190)
	local glowC = def.GuardianColor
	local model, body, add, eye, height = startGuardian(def, Vector3.new(7, 9, 6.5), 6.5, 1.2, stem)
	add("Cap", "Blob", Vector3.new(16, 7, 16), 0, 13.5, 0, cap)
	add("CapRim", "Cyl", Vector3.new(0.6, 15.4, 15.4), 0, 11.2, 0, glowC, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(90)))
	add("Gills", "Cyl", Vector3.new(0.4, 14, 14), 0, 10.9, 0, cap:Lerp(BLACK, 0.5), nil, CFrame.Angles(0, 0, math.rad(90)))
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local r = if i == 0 then 0 else 4.4
		add("CapSpot", "Blob", Vector3.new(2.2, 0.8, 2.2), math.cos(a) * r, (if i == 0 then 17 else 15.8), math.sin(a) * r, glowC:Lerp(WHITE, 0.4), Enum.Material.Neon)
	end
	add("Mouth", "Blob", Vector3.new(2.4, 0.9, 0.4), 0, 6.2, -3.2, Color3.fromRGB(70, 40, 60))
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.4, 8.2, -3.1, 1.6, sx)
		add("Cheek", "Blob", Vector3.new(1.2, 0.7, 0.3), sx * 2.4, 7, -3.1, BLUSH)
		add("Arm", "Blob", Vector3.new(2, 5.2, 2), sx * 4.6, 6.2, -0.6, stem, nil, CFrame.Angles(0, 0, math.rad(25 * sx)))
		add("Leg", "Blob", Vector3.new(2.6, 3, 2.8), sx * 1.9, 1.5, 0, stem:Lerp(BLACK, 0.1))
		-- little mushrooms growing on its shoulders
		add("ShoulderStem", "Block", Vector3.new(0.5, 1.4, 0.5), sx * 3, 10.5, 1.4, stem)
		add("ShoulderCap", "Blob", Vector3.new(2, 1, 2), sx * 3, 11.3, 1.4, glowC, Enum.Material.Neon)
	end
	local spores = Instance.new("ParticleEmitter")
	spores.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spores.Color = ColorSequence.new(glowC, Color3.fromRGB(255, 120, 230))
	spores.LightEmission = 1
	spores.Size = NumberSequence.new(0.5, 0)
	spores.Lifetime = NumberRange.new(2, 3)
	spores.Rate = 14
	spores.Speed = NumberRange.new(1, 3)
	spores.SpreadAngle = Vector2.new(180, 180)
	spores.Parent = body
	local pl = Instance.new("PointLight")
	pl.Color = glowC
	pl.Range = 28
	pl.Brightness = 1.5
	pl.Parent = body
	return model, height
end

-- Haunted Hollow: a floating pumpkin-headed king in a tattered cloak with a lantern
function GUARDIANS.Pumpkin(def)
	local cloak = Color3.fromRGB(40, 30, 50)
	local orange = def.GuardianColor
	local glowC = Color3.fromRGB(255, 220, 90)
	local sc = 1.25
	local model, body, add, eye, height = startGuardian(def, Vector3.new(7, 9, 6), 11, sc, cloak)
	-- pumpkin head: three overlapping lobes with a carved glowing face
	for k = -1, 1 do
		add("PumpkinHead", "Blob", Vector3.new(4.4, 6, 7), k * 2, 18, 0, orange:Lerp(Color3.fromRGB(200, 80, 20), math.abs(k) * 0.4))
	end
	add("HeadStem", "Block", Vector3.new(0.8, 2, 0.8), 0, 21.6, 0, Color3.fromRGB(80, 110, 40), nil, CFrame.Angles(0, 0, 0.3))
	for _, sx in ipairs({ -1, 1 }) do
		add("CarvedEye", "Wedge", Vector3.new(0.4, 1.6, 1.8), sx * 1.4, 19, -3.45, glowC, Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0))
		add("Sleeve", "Blob", Vector3.new(2.6, 6, 2.6), sx * 4.6, 12, -1, cloak, nil, CFrame.Angles(math.rad(-25), 0, math.rad(30 * sx)))
		add("Hand", "Ball", Vector3.one * 1.6, sx * 6.3, 9.4, -3, Color3.fromRGB(150, 220, 160))
		add("Collar", "Wedge", Vector3.new(1.4, 3.4, 3), sx * 2.8, 15.6, 0.6, Color3.fromRGB(110, 30, 40), nil, CFrame.Angles(0, 0, math.rad(-25 * sx)))
	end
	add("CarvedNose", "Wedge", Vector3.new(0.4, 0.9, 0.9), 0, 17.9, -3.5, glowC, Enum.Material.Neon)
	add("CarvedMouth", "Block", Vector3.new(4, 0.8, 0.4), 0, 16.6, -3.35, glowC, Enum.Material.Neon)
	for i = -1, 1 do
		add("MouthTooth", "Block", Vector3.new(0.5, 0.5, 0.45), i * 1.2, 16.9, -3.45, orange)
	end
	-- crooked crown, tattered cloak hem and a hanging lantern
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("CrownSpike", "Wedge", Vector3.new(0.8, 1.8, 0.8), math.cos(a) * 2.2, 22.2, math.sin(a) * 2.2, GOLD, Enum.Material.Metal, CFrame.Angles(0, -a, 0.2))
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("Tatter", "Wedge", Vector3.new(1.8, 3.4, 1.4), math.cos(a) * 3.1, 5.6 - (i % 2) * 0.8, math.sin(a) * 2.7, cloak:Lerp(BLACK, 0.3), nil, CFrame.Angles(math.rad(180), -a, 0))
	end
	add("LanternChain", "Block", Vector3.new(0.2, 3, 0.2), 6.6, 7.4, -3.4, Color3.fromRGB(60, 60, 60))
	local lantern = add("Lantern", "Block", Vector3.new(1.8, 2.2, 1.8), 6.6, 5, -3.4, Color3.fromRGB(120, 255, 150), Enum.Material.Neon)
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(140, 255, 170)
	pl.Range = 26
	pl.Brightness = 1.6
	pl.Parent = lantern
	local wisps = Instance.new("ParticleEmitter")
	wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(150, 255, 180))
	wisps.LightEmission = 0.6
	wisps.Size = NumberSequence.new(1.5, 3)
	wisps.Transparency = NumberSequence.new(0.6, 1)
	wisps.Lifetime = NumberRange.new(1, 2)
	wisps.Rate = 12
	wisps.Speed = NumberRange.new(1, 2)
	wisps.EmissionDirection = Enum.NormalId.Bottom
	wisps.Parent = body
	return model, height
end

-- Clockwork Citadel: a brass robot with a clock in its chest and a gear on its back
function GUARDIANS.Automaton(def)
	local brass = def.GuardianColor
	local copper = Color3.fromRGB(190, 105, 60)
	local iron = Color3.fromRGB(70, 70, 80)
	local glowC = Color3.fromRGB(120, 230, 255)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(9, 8, 6.5), 9, 1.2, brass)
	body.Material = Enum.Material.Metal
	add("Head", "Block", Vector3.new(6, 5, 5), 0, 15.6, 0, brass, Enum.Material.Metal)
	add("Visor", "Block", Vector3.new(5, 1.4, 0.4), 0, 16, -2.55, Color3.fromRGB(30, 30, 40))
	for _, sx in ipairs({ -1, 1 }) do
		add("EyeLens", "Cyl", Vector3.new(0.4, 1.4, 1.4), sx * 1.3, 16, -2.8, glowC, Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0))
		add("EarBolt", "Cyl", Vector3.new(0.8, 1.6, 1.6), sx * 3.3, 15.6, 0, copper, Enum.Material.Metal)
		add("Shoulder", "Ball", Vector3.one * 3, sx * 5.4, 12.2, 0, copper, Enum.Material.Metal)
		add("Arm", "Cyl", Vector3.new(5, 1.6, 1.6), sx * 6, 9.2, -0.4, iron, Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90 + 15 * sx)))
		add("Claw", "Block", Vector3.new(2.2, 2, 2.2), sx * 6.7, 6.4, -0.8, brass, Enum.Material.Metal)
		add("Leg", "Cyl", Vector3.new(4, 2, 2), sx * 2.2, 3.4, 0, iron, Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
		add("Foot", "Block", Vector3.new(3, 1.2, 4.2), sx * 2.2, 0.6, -0.6, copper, Enum.Material.Metal)
	end
	add("Mouth", "Block", Vector3.new(3, 0.5, 0.3), 0, 14.2, -2.6, iron)
	add("Antenna", "Block", Vector3.new(0.3, 3, 0.3), 0, 19.6, 0, iron, Enum.Material.Metal)
	add("AntennaBulb", "Ball", Vector3.one * 1.1, 0, 21.2, 0, Color3.fromRGB(255, 80, 60), Enum.Material.Neon)
	-- a clock set into its chest
	add("ChestClock", "Cyl", Vector3.new(0.4, 4.4, 4.4), 0, 9.6, -3.3, Color3.fromRGB(250, 240, 210), Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0))
	add("ClockRim", "Cyl", Vector3.new(0.3, 5, 5), 0, 9.6, -3.2, brass, Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
	add("ClockHand", "Block", Vector3.new(0.3, 1.8, 0.2), 0.3, 10.2, -3.6, iron, nil, CFrame.Angles(0, 0, math.rad(-30)))
	add("ClockHand", "Block", Vector3.new(0.25, 1.4, 0.2), -0.4, 9.9, -3.62, iron, nil, CFrame.Angles(0, 0, math.rad(60)))
	-- a big wind-up key on its back
	add("KeyShaft", "Cyl", Vector3.new(3, 0.8, 0.8), 0, 10, 4.4, brass, Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
	for _, sx in ipairs({ -1, 1 }) do
		add("KeyBow", "Ball", Vector3.new(0.8, 2.6, 2.6), sx * 1.4, 10, 6, brass, Enum.Material.Metal)
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
	steam.Size = NumberSequence.new(1, 3)
	steam.Transparency = NumberSequence.new(0.6, 1)
	steam.Lifetime = NumberRange.new(1, 1.6)
	steam.Rate = 10
	steam.Speed = NumberRange.new(3, 5)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Parent = body
	return model, height
end

-- Neon Nexus boss: a giant hovering mech with a glowing visor and jet boosters
function GUARDIANS.Mech(def)
	local armor = Color3.fromRGB(40, 36, 60)
	local neon = def.GuardianColor
	local cyan = Color3.fromRGB(40, 240, 255)
	local sc = 1.35
	local model, body, add, eye, height = startGuardian(def, Vector3.new(10, 9, 7), 12, sc, armor)
	body.Material = Enum.Material.Metal
	add("ChestPlate", "Block", Vector3.new(8, 5, 1), 0, 13, -3.4, armor:Lerp(WHITE, 0.1), Enum.Material.Metal)
	add("Core", "Ball", Vector3.one * 2.6, 0, 13, -4, cyan, Enum.Material.Neon)
	add("Head", "Block", Vector3.new(5.5, 4.2, 5), 0, 19, 0, armor, Enum.Material.Metal)
	add("Visor", "Block", Vector3.new(4.8, 1.2, 0.4), 0, 19.4, -2.55, neon, Enum.Material.Neon)
	add("Crest", "Wedge", Vector3.new(0.8, 2.6, 4), 0, 22.2, 0.4, neon, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		add("ShoulderPad", "Block", Vector3.new(4, 2.2, 5), sx * 6.4, 16.4, 0, armor:Lerp(WHITE, 0.15), Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(-15 * sx)))
		add("ShoulderStripe", "Block", Vector3.new(4.1, 0.4, 5.1), sx * 6.4, 16.9, 0, neon, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(-15 * sx)))
		add("Arm", "Block", Vector3.new(2.4, 7, 2.6), sx * 7, 11, -0.6, armor, Enum.Material.Metal)
		add("Cannon", "Cyl", Vector3.new(4, 1.8, 1.8), sx * 7, 7.4, -2.4, armor:Lerp(WHITE, 0.2), Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
		add("CannonGlow", "Cyl", Vector3.new(0.3, 1.4, 1.4), sx * 7, 7.4, -4.45, cyan, Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0))
		add("Jet", "Cyl", Vector3.new(3, 2.2, 2.2), sx * 2.6, 6.4, 1.2, armor:Lerp(WHITE, 0.2), Enum.Material.Metal, CFrame.Angles(0, 0, math.rad(90)))
		add("JetFlame", "Ball", Vector3.new(1.8, 3, 1.8), sx * 2.6, 4.2, 1.2, Color3.fromRGB(120, 200, 255), Enum.Material.Neon)
		add("Fin", "Wedge", Vector3.new(0.6, 5, 4), sx * 4, 17, 4, neon, Enum.Material.Neon, CFrame.Angles(0, math.rad(180), math.rad(20 * sx)))
	end
	-- a spinning holo ring around it
	local ring = add("HoloRing", "Cyl", Vector3.new(0.3, 18, 18), 0, 10, 0, cyan, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(90)))
	ring.Transparency = 0.6
	local jets = Instance.new("ParticleEmitter")
	jets.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	jets.Color = ColorSequence.new(cyan, neon)
	jets.LightEmission = 1
	jets.Size = NumberSequence.new(1, 0)
	jets.Lifetime = NumberRange.new(0.4, 0.8)
	jets.Rate = 40
	jets.Speed = NumberRange.new(8, 14)
	jets.EmissionDirection = Enum.NormalId.Bottom
	jets.Parent = body
	local pl = Instance.new("PointLight")
	pl.Color = neon
	pl.Range = 34
	pl.Brightness = 2
	pl.Parent = body
	return model, height
end

-- Jungle Ruins: a huge silverback gorilla with a vine headband
function GUARDIANS.Gorilla(def)
	local fur = def.GuardianColor
	local skin = Color3.fromRGB(110, 95, 100)
	local model, body, add, eye, height = startGuardian(def, Vector3.new(10, 8, 8), 7.5, 1.1, fur)
	add("Chest", "Blob", Vector3.new(6, 5, 1.6), 0, 8.4, -3.6, skin)
	add("Head", "Ball", Vector3.one * 6, 0, 13.4, -1.8, fur)
	add("Face", "Blob", Vector3.new(4.4, 4, 1.8), 0, 12.8, -4, skin)
	add("Brow", "Block", Vector3.new(4.6, 0.9, 1.2), 0, 14.4, -4.4, fur:Lerp(BLACK, 0.2))
	add("Nose", "Blob", Vector3.new(1.8, 0.9, 0.6), 0, 12.6, -4.9, skin:Lerp(BLACK, 0.3))
	add("Mouth", "Blob", Vector3.new(2.4, 0.5, 0.3), 0, 11.4, -4.85, Color3.fromRGB(70, 30, 35))
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.1, 13.5, -4.7, 1.2, sx)
		add("Shoulder", "Ball", Vector3.one * 4, sx * 5, 10.4, -0.8, fur)
		-- long arms reaching down to the knuckles
		add("Arm", "Blob", Vector3.new(3, 8, 3), sx * 6.4, 6.2, -1.8, fur, nil, CFrame.Angles(math.rad(-10), 0, math.rad(8 * sx)))
		add("Fist", "Ball", Vector3.one * 3.2, sx * 6.8, 1.8, -3, skin)
		add("Leg", "Blob", Vector3.new(3.2, 3.6, 3.4), sx * 2.8, 1.8, 0.4, fur)
		add("Ear", "Ball", Vector3.one * 1.2, sx * 3, 13.4, -1.6, skin)
	end
	-- vine headband with a gold temple medallion
	add("Headband", "Cyl", Vector3.new(0.8, 6.2, 6.2), 0, 15.2, -1.8, Color3.fromRGB(70, 150, 60), nil, CFrame.Angles(0, 0, math.rad(90)))
	add("Medallion", "Cyl", Vector3.new(0.4, 1.6, 1.6), 0, 15.2, -4.9, Color3.fromRGB(255, 200, 60), Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0))
	for i = 0, 4 do
		local a = i / 5 * math.pi - math.pi / 2
		add("Leaf", "Blob", Vector3.new(1.4, 0.3, 2.2), math.cos(a) * 3.2, 15.6, -1.8 + math.sin(a) * 3.2, Color3.fromRGB(80, 180, 70), nil, CFrame.Angles(0, -a, 0.3))
	end
	return model, height
end

-- Sakura Gardens: a floating nine-tailed fox spirit with glowing tails
function GUARDIANS.Kitsune(def)
	local fur = Color3.fromRGB(255, 245, 240)
	local glowC = def.GuardianColor
	local model, body, add, eye, height = startGuardian(def, Vector3.new(6, 6.5, 9), 7, 1.25, fur)
	add("Head", "Ball", Vector3.one * 5.4, 0, 11, -4.2, fur)
	add("Snout", "Blob", Vector3.new(2.4, 2, 3), 0, 10.2, -7, fur)
	add("Nose", "Ball", Vector3.one * 0.8, 0, 10.6, -8.5, BLACK)
	add("Marking", "Blob", Vector3.new(0.6, 1.8, 0.3), 0, 12.6, -6.7, glowC, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		eye(sx * 1.2, 11.6, -6.2, 1.1, sx)
		add("Ear", "Wedge", Vector3.new(0.6, 3, 2.4), sx * 1.8, 14.6, -3.8, fur, nil, CFrame.Angles(0, math.rad(90), math.rad(-10 * sx)))
		add("EarTip", "Wedge", Vector3.new(0.65, 1.2, 1.1), sx * 1.8, 15.6, -3.8, glowC, Enum.Material.Neon, CFrame.Angles(0, math.rad(90), math.rad(-10 * sx)))
		add("FrontLeg", "Blob", Vector3.new(1.6, 4.5, 1.6), sx * 1.8, 3, -3, fur)
		add("BackLeg", "Blob", Vector3.new(1.8, 4.5, 2.2), sx * 1.9, 3, 3, fur)
		add("Paw", "Ball", Vector3.one * 1.8, sx * 1.8, 0.9, -3.3, glowC:Lerp(WHITE, 0.4))
	end
	-- nine fanned tails, each tipped with glowing fire
	for i = 0, 8 do
		local a = (i / 8 - 0.5) * math.rad(150)
		local dir = Vector3.new(math.sin(a), 0.9, 0.6).Unit
		local base = Vector3.new(0, 7.5, 4.5)
		local tip = base + dir * 7
		local mid = (base + tip) / 2
		add("Tail", "Blob", Vector3.new(1.8, 1.8, 7.5), mid.X, mid.Y, mid.Z, fur, nil, CFrame.lookAt(Vector3.zero, dir))
		add("TailFlame", "Ball", Vector3.new(1.6, 2.4, 1.6), tip.X, tip.Y, tip.Z, glowC, Enum.Material.Neon)
	end
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(glowC, WHITE)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.6, 0)
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Rate = 18
	sparks.Speed = NumberRange.new(1, 3)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = body
	return model, height
end

-- Rainbow Realm final boss: a huge crystal dragon shimmering in every color
function GUARDIANS.Dragon(def)
	local scales = Color3.fromRGB(245, 240, 255)
	local glowC = def.GuardianColor
	local rainbow = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 240, 90), Color3.fromRGB(100, 230, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(180, 110, 255) }
	local sc = 1.35
	local model, body, add, eye, height = startGuardian(def, Vector3.new(9, 8, 12), 9, sc, scales)
	add("Belly", "Blob", Vector3.new(6.4, 5.4, 9), 0, 7.6, -0.6, Color3.fromRGB(255, 225, 245))
	add("Neck", "Blob", Vector3.new(3.4, 7, 3.4), 0, 13, -5.6, scales, nil, CFrame.Angles(math.rad(-30), 0, 0))
	add("Head", "Blob", Vector3.new(5, 4, 6), 0, 17, -8, scales)
	add("Jaw", "Blob", Vector3.new(4, 1.6, 4.6), 0, 15.4, -9.6, Color3.fromRGB(255, 225, 245))
	for _, sx in ipairs({ -1, 1 }) do
		add("Eye", "Blob", Vector3.new(1.3, 1, 0.5), sx * 1.5, 17.8, -10.6, glowC, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(-12 * sx)))
		add("Horn", "Wedge", Vector3.new(0.8, 3.4, 2), sx * 1.6, 20, -6.8, Color3.fromRGB(255, 220, 120), Enum.Material.Metal, CFrame.Angles(math.rad(-30), 0, 0))
		add("Nostril", "Ball", Vector3.one * 0.5, sx * 0.8, 16.6, -11, BLACK)
		add("Leg", "Blob", Vector3.new(2.6, 5, 2.8), sx * 3.8, 2.8, -3.4, scales)
		add("BackLeg", "Blob", Vector3.new(3, 5, 3.4), sx * 3.8, 2.8, 3.6, scales)
		-- big crystal wings in rainbow bands
		for f = 0, 5 do
			add("WingPanel", "Wedge", Vector3.new(0.5, 6 - f * 0.5, 4), sx * (7 + f * 2.6), 14 + f * 0.8, 1 + f * 0.4, rainbow[f + 1], Enum.Material.Neon, CFrame.Angles(math.rad(-15), math.rad(90 * sx), math.rad(-15 * sx)))
		end
	end
	-- spines and a rainbow tail
	for i = 0, 4 do
		add("Spine", "Wedge", Vector3.new(0.6, 1.8, 1.8), 0, 12.4, -3 + i * 2.2, rainbow[i + 1], Enum.Material.Neon)
	end
	for i = 0, 5 do
		add("TailSegment", "Blob", Vector3.new(2.6 - i * 0.3, 2.2 - i * 0.25, 3.2), 0, 7 - i * 0.6, 7 + i * 2.6, rainbow[i + 1])
	end
	local aura = Instance.new("ParticleEmitter")
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rainbow[1]), ColorSequenceKeypoint.new(0.5, rainbow[4]), ColorSequenceKeypoint.new(1, rainbow[6]) })
	aura.LightEmission = 1
	aura.Size = NumberSequence.new(1, 0)
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Rate = 35
	aura.Speed = NumberRange.new(2, 5)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Parent = body
	local pl = Instance.new("PointLight")
	pl.Color = glowC
	pl.Range = 36
	pl.Brightness = 2
	pl.Parent = body
	return model, height
end

function Visuals.MakeGuardian(def)
	local builder = GUARDIANS[def.GuardianStyle or "Bear"] or GUARDIANS.Bear
	local model, height = builder(def)
	local body = model.PrimaryPart
	outline(model, if def.Boss then Color3.fromRGB(255, 200, 255) else Color3.fromRGB(35, 20, 20))

	-- name tag
	local labelY = body.Size.Y / 2 + (if def.Boss then 16 else 8)
	Visuals.AddLabel(body, labelY, if def.Boss then 300 else 230)
	if def.Boss then
		Visuals.SetLabel(body, "👑 " .. def.GuardianName, "BOSS  •  Outrun with " .. Util.FormatNumber(def.SpeedNeeded) .. " Speed", Color3.fromRGB(240, 150, 255))
		body.Label.Size = UDim2.fromOffset(300, 72)
		body.Label.MaxDistance = 250
	else
		Visuals.SetLabel(body, def.GuardianName, if def.SpeedNeeded > 0 then "Outrun with " .. Util.FormatNumber(def.SpeedNeeded) .. " Speed" else "Slow and sleepy", Color3.fromRGB(255, 140, 110))
	end

	-- "Zzz" shown while it naps next to the nest
	local sleep = Instance.new("BillboardGui")
	sleep.Name = "SleepGui"
	sleep.Size = UDim2.fromOffset(90, 60)
	sleep.StudsOffset = Vector3.new(3, labelY - 3, 0)
	sleep.LightInfluence = 0
	sleep.MaxDistance = 120
	local z = Instance.new("TextLabel")
	z.BackgroundTransparency = 1
	z.Size = UDim2.fromScale(1, 1)
	z.Font = Enum.Font.FredokaOne
	z.TextScaled = true
	z.Text = "z Z z"
	z.TextColor3 = Color3.fromRGB(150, 200, 255)
	z.TextStrokeTransparency = 0.3
	z.Parent = sleep
	sleep.Parent = body

	return model, height
end

-- Natural surfaces: fur and feathers get a soft fabric texture, reptiles,
-- amphibians and sea animals get slightly glossy skin. Only the pet's own
-- body colors change; eyes, accessories, gems and glow stay as they are.
local blockify -- defined below
local FUR_STYLES = {}
for _, s in ipairs({ "Gorilla", "Pup", "Cat", "Fox", "Wolf", "Lion", "Bear", "Cub", "Panda", "Raccoon", "Pig", "Cow", "Sheep", "Hamster", "Bunny", "Stag", "Unicorn", "Kitsune", "Elephant", "Monkey", "Hedgehog", "Pony", "Pegasus", "Giraffe", "Kangaroo", "Koala", "Sloth", "Otter", "Squirrel", "Mouse", "Hippo", "Rhino", "Griffin", "Cerberus", "Bat", "Bird", "Chick", "Duck", "Owl", "Phoenix", "Penguin", "Flamingo", "Swan", "Parrot", "Peacock", "Moth", "Bee" }) do
	FUR_STYLES[s] = true
end
local SKIN_STYLES = {}
for _, s in ipairs({ "Drake", "Dino", "Serpent", "Croc", "Newt", "Axolotl", "Turtle", "Frog", "Fish", "Koi", "Shark", "Dolphin", "Whale", "Seal", "Octopus", "Kraken", "Crab", "Snail" }) do
	SKIN_STYLES[s] = true
end

-- Blocky, studded look (like the big showpiece pets in Steal an Egg): every
-- rounded part becomes a block sized to sit inside its old shape, every face
-- gets classic studs, and rare pets get a spiky back and glowing eyes.
local PET_BLOCKY = true
local BLOCK_FIT = 0.84 -- a block this fraction of an ellipsoid's size stays inside it
local STUD_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }
local SHINY_MATERIALS = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }

blockify = function(model, data)
	if not PET_BLOCKY then
		return
	end
	local rarity = Config.RarityById[data.Rarity]
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == Enum.MeshType.Sphere then
				mesh:Destroy()
				part.Size *= BLOCK_FIT
			elseif part.Shape == Enum.PartType.Ball then
				part.Shape = Enum.PartType.Block
				part.Size *= BLOCK_FIT
			elseif part.Shape == Enum.PartType.Cylinder then
				part.Shape = Enum.PartType.Block
				part.Size = Vector3.new(part.Size.X, part.Size.Y * BLOCK_FIT, part.Size.Z * BLOCK_FIT)
			end
			if not SHINY_MATERIALS[part.Material] and part.Material ~= Enum.Material.Metal then
				part.Material = Enum.Material.Plastic
				for _, face in ipairs(STUD_FACES) do
					part[face] = Enum.SurfaceType.Studs
				end
			end
		end
	end
	local body = model.PrimaryPart
	if body and rarity then
		local add = rigger(model, body)
		local sz = body.Size
		-- Legendary and up: a row of spikes down the back
		if rarity.Order >= 5 then
			for i = 0, 4 do
				local spike = add("BackSpike", "Wedge", Vector3.new(sz.X * 0.12, sz.Y * (0.22 + (i % 2) * 0.08), sz.Z * 0.14), CFrame.new(0, sz.Y * 0.5 + sz.Y * 0.08, -sz.Z * 0.32 + i * sz.Z * 0.16), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.Plastic)
				for _, face in ipairs(STUD_FACES) do
					spike[face] = Enum.SurfaceType.Studs
				end
			end
		end
		-- Mythic and up: glowing eyes in the rarity's color
		if rarity.Order >= 6 then
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and (part.Name == "Pupil" or part.Name == "Iris") then
					part.Material = Enum.Material.Neon
					part.Color = if part.Name == "Pupil" then rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3) else rarity.Color
				end
			end
		end
	end
	-- the blocks are a bit smaller than the round parts were: re-plant the feet
	if model:GetAttribute("FootDrop") ~= nil then
		local lowest = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "Orb" then
				lowest = math.min(lowest, part.CFrame.Position.Y - part.Size.Y / 2)
			end
		end
		if lowest < math.huge then
			model:SetAttribute("FootDrop", -lowest)
		end
	end
end

function Visuals.MakeCreature(data)
	PET_BUILD = true
	local ok, model = pcall(buildCreature, data)
	PET_BUILD = false
	if not ok then
		error(model, 2)
	end
	local def = Config.CreatureByName[data.Name]
	local style = def and def.Style
	if style and (FUR_STYLES[style] or SKIN_STYLES[style]) then
		local rarity = Config.RarityById[data.Rarity]
		local color = Visuals.PetColor(def, rarity)
		local palette = { color, color:Lerp(Color3.new(0, 0, 0), 0.3), color:Lerp(WHITE, 0.45) }
		local function isBody(c)
			for _, pc in ipairs(palette) do
				if math.abs(c.R - pc.R) + math.abs(c.G - pc.G) + math.abs(c.B - pc.B) < 0.03 then
					return true
				end
			end
			return false
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Material == Enum.Material.SmoothPlastic and isBody(part.Color) then
				if FUR_STYLES[style] then
					part.Material = Enum.Material.Fabric
				else
					part.Reflectance = 0.06
				end
			end
		end
	end
	blockify(model, data)
	return model
end

-- Gentle idle bob for pets. Call after the model is placed.
function Visuals.StartBob(model)
	local body = model.PrimaryPart
	local tween = TweenService:Create(
		body,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = body.CFrame * CFrame.new(0, 0.6, 0) }
	)
	tween:Play()
end

return Visuals
