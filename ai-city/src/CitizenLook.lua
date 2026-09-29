-- CitizenLook (ModuleScript) — ServerScriptService.Modules.CitizenLook
-- Gives every citizen their own look: skin tone, hairstyle and color, a
-- uniform for their job (police cap and badge, doctor's coat, chef's hat,
-- firefighter helmet...), something for their hobby (a beret for painters,
-- headphones for gamers...) and gray hair and a cane once they retire.
-- The look comes from the citizen's name, so the same person always looks the
-- same in every server.
--
--   CitizenLook.Apply(characterModel, citizen)  -- dress an existing R15 or R6 rig
--   CitizenLook.Build(citizen)                  -- make a new dressed R15 NPC (server only)
--
-- `citizen` can use either naming style: { Name/name, Job/job (title or
-- { title = ... }), Age/age, Hobby/hobby }. Missing fields are fine.
-- Options: CitizenLook.Apply(model, citizen, { KeepClothing = true }) keeps
-- existing Shirt/Pants instead of replacing them with the colored outfit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CitizenLook = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE = rgb(248, 248, 245)
local BLACK = rgb(28, 28, 32)
local GOLD = rgb(245, 200, 70)
local SILVER = rgb(200, 205, 215)

local SKIN_TONES = {
	rgb(255, 224, 196), rgb(245, 205, 170), rgb(234, 184, 146), rgb(214, 160, 120), rgb(196, 138, 98),
	rgb(168, 112, 78), rgb(141, 90, 62), rgb(112, 70, 48), rgb(88, 56, 40), rgb(250, 214, 180),
}
local HAIR_COLORS = {
	rgb(30, 24, 22), rgb(58, 38, 28), rgb(92, 60, 38), rgb(128, 84, 52), rgb(160, 96, 48), -- black to light brown
	rgb(214, 170, 100), rgb(236, 206, 140), rgb(178, 70, 40), -- blonde, light blonde, red
}
local FUN_HAIR = { rgb(240, 110, 170), rgb(90, 150, 240), rgb(140, 90, 220), rgb(90, 200, 160) }
local GRAY_HAIR = { rgb(200, 200, 200), rgb(170, 170, 172), rgb(235, 235, 235) }
local HAIRSTYLES = { "short", "buzz", "long", "ponytail", "bun", "afro", "curly", "mohawk", "bob", "spiky", "sidepart", "bald" }
local CASUAL_TOPS = { rgb(220, 70, 70), rgb(70, 130, 220), rgb(90, 180, 110), rgb(240, 190, 60), rgb(160, 100, 200), rgb(240, 140, 60), rgb(80, 190, 200), rgb(235, 235, 230), rgb(60, 60, 70), rgb(230, 120, 160) }
local CASUAL_BOTTOMS = { rgb(50, 70, 120), rgb(70, 60, 50), rgb(40, 40, 45), rgb(120, 110, 90), rgb(90, 100, 110), rgb(60, 90, 70) }

--------------------------------------------------------------------------------
-- Uniforms, by job title. Colors: Top, Sleeves ("long"/"short"), Bottom,
-- Shoes. Items are extra pieces added to the body (see ITEMS below).
--------------------------------------------------------------------------------
local UNIFORMS = {
	["Baker"] = { Top = WHITE, Bottom = rgb(90, 80, 70), Items = { "Toque", "Apron:240,220,190" } },
	["Barista"] = { Top = BLACK, Bottom = rgb(60, 50, 45), Items = { "Apron:40,120,80", "Cap:40,120,80", "NameTag" } },
	["Doctor"] = { Top = rgb(170, 210, 240), Bottom = rgb(60, 70, 90), Sleeves = "long", Items = { "LabCoat", "Stethoscope", "NameTag" } },
	["Nurse"] = { Top = rgb(70, 170, 170), Bottom = rgb(70, 170, 170), Items = { "Stethoscope", "NameTag" } },
	["Police Officer"] = { Top = rgb(40, 55, 110), Bottom = rgb(30, 40, 80), Sleeves = "long", Items = { "PoliceCap", "Badge", "Belt:25,25,30", "Radio" } },
	["Night Officer"] = { Top = rgb(28, 36, 70), Bottom = rgb(22, 28, 55), Sleeves = "long", Items = { "PoliceCap", "Badge", "Belt:25,25,30", "HiVisVest", "Radio" } },
	["Teacher"] = { Top = rgb(180, 90, 70), Bottom = rgb(70, 70, 90), Sleeves = "long", Items = { "Cardigan:140,60,50", "Glasses", "Lanyard" } },
	["Factory Worker"] = { Top = rgb(90, 110, 140), Bottom = rgb(50, 60, 80), Items = { "HardHat", "HiVisVest", "Gloves" } },
	["Shopkeeper"] = { Top = rgb(235, 235, 230), Bottom = rgb(60, 60, 70), Items = { "Apron:200,60,60", "NameTag" } },
	["City Clerk"] = { Top = rgb(120, 120, 130), Bottom = rgb(80, 80, 90), Sleeves = "long", Items = { "Tie:150,40,50", "Lanyard" } },
	["Gardener"] = { Top = rgb(200, 180, 140), Bottom = rgb(70, 110, 60), Items = { "StrawHat", "Overalls:70,110,60", "Gloves" } },
	["Street Musician"] = { Top = rgb(150, 60, 150), Bottom = rgb(40, 40, 60), Items = { "Beanie:230,120,40", "GuitarBack" } },
	["Bank Teller"] = { Top = rgb(40, 60, 90), Bottom = rgb(35, 45, 70), Sleeves = "long", Items = { "Tie:180,150,60", "NameTag" } },
	["Bank Manager"] = { Top = BLACK, Bottom = BLACK, Sleeves = "long", Items = { "BowTie:170,30,40", "PocketSquare", "GoldWatch" } },
	["Firefighter"] = { Top = rgb(190, 160, 100), Bottom = rgb(190, 160, 100), Sleeves = "long", Items = { "FireHelmet", "ReflectiveStripes", "Gloves" } },
	["Librarian"] = { Top = rgb(110, 140, 110), Bottom = rgb(90, 80, 70), Sleeves = "long", Items = { "Cardigan:70,90,70", "Glasses", "BookUnderArm" } },
	["Chef"] = { Top = WHITE, Bottom = rgb(40, 40, 45), Sleeves = "long", Items = { "TallToque", "ChefButtons", "Neckerchief:200,50,50" } },
	["Waiter"] = { Top = WHITE, Bottom = BLACK, Sleeves = "long", Items = { "Vest:30,30,35", "BowTie:30,30,35", "TowelArm" } },
	["Pharmacist"] = { Top = rgb(200, 230, 210), Bottom = rgb(70, 80, 90), Sleeves = "long", Items = { "LabCoat", "Glasses", "NameTag" } },
	["Office Worker"] = { Top = rgb(215, 225, 240), Bottom = rgb(60, 65, 80), Sleeves = "long", Items = { "Tie:60,90,160", "Lanyard" } },
	["Hotel Receptionist"] = { Top = WHITE, Bottom = rgb(40, 40, 50), Sleeves = "long", Items = { "Vest:130,30,45", "NameTag", "Neckerchief:220,180,70" } },
	["Cinema Clerk"] = { Top = rgb(200, 40, 50), Bottom = BLACK, Items = { "Cap:200,40,50", "NameTag" } },
	["Fitness Coach"] = { Top = rgb(250, 120, 40), Bottom = rgb(40, 40, 50), Items = { "Headband:250,250,250", "Whistle", "Wristbands" } },
	["Store Clerk"] = { Top = rgb(60, 150, 200), Bottom = rgb(60, 60, 70), Items = { "Lanyard", "NameTag" } },
	["Mechanic"] = { Top = rgb(50, 80, 140), Bottom = rgb(50, 80, 140), Sleeves = "long", Items = { "Cap:50,80,140", "Belt:60,50,40", "WrenchBelt", "Smudge" } },
	["Warehouse Worker"] = { Top = rgb(110, 110, 100), Bottom = rgb(60, 70, 90), Items = { "Beanie:60,60,70", "HiVisVest", "Gloves" } },
}

-- Something for each hobby. Hats only if the job didn't already give one.
local HOBBY_ITEMS = {
	painting = { "Beret:180,40,60", "PaintSmudge" },
	["playing chess"] = { "Glasses" },
	gardening = { "Gloves" },
	jogging = { "Headband:80,200,120", "Wristbands" },
	cooking = { "Apron:230,230,225" },
	["playing guitar"] = { "GuitarBack" },
	reading = { "Glasses" },
	gaming = { "Headphones" },
	fishing = { "BucketHat:110,130,90" },
	dancing = { "Headband:240,110,170" },
	birdwatching = { "Binoculars" },
	knitting = { "Scarf" },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function hash(text)
	local h = 5381
	for k = 1, #text do
		h = (h * 33 + string.byte(text, k)) % 2147483647
	end
	return h
end

local function field(t, ...)
	for _, k in ipairs({ ... }) do
		if t[k] ~= nil then
			return t[k]
		end
	end
	return nil
end

local function jobTitle(citizen)
	local job = field(citizen, "Job", "job")
	if type(job) == "table" then
		return job.title or job.Title
	end
	return job
end

local function first(model, ...)
	for _, name in ipairs({ ... }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function parseItem(item)
	local name, color = string.match(item, "^([^:]+):?(.*)$")
	if color ~= "" then
		local r, g, b = string.match(color, "(%d+),(%d+),(%d+)")
		return name, rgb(tonumber(r), tonumber(g), tonumber(b))
	end
	return name, nil
end

--------------------------------------------------------------------------------
-- The body: finds the parts of an R15 or R6 rig and measures the head
--------------------------------------------------------------------------------
local function readBody(model)
	local body = {
		Head = first(model, "Head"),
		Torso = first(model, "UpperTorso", "Torso"),
		Lower = first(model, "LowerTorso", "Torso"),
		LeftArm = first(model, "LeftUpperArm", "Left Arm"),
		RightArm = first(model, "RightUpperArm", "Right Arm"),
		LeftHand = first(model, "LeftHand", "Left Arm"),
		RightHand = first(model, "RightHand", "Right Arm"),
		LeftLeg = first(model, "LeftUpperLeg", "Left Leg"),
		RightLeg = first(model, "RightUpperLeg", "Right Leg"),
		R15 = model:FindFirstChild("UpperTorso") ~= nil,
	}
	if body.Head then
		-- R6 heads are 2x1x1 parts drawn with a round mesh about 1.25 across
		local mesh = body.Head:FindFirstChildOfClass("SpecialMesh")
		local s = body.Head.Size
		body.H = if mesh and not body.R15 then mesh.Scale.Y else math.min(s.X, s.Y, s.Z)
	end
	return body
end

-- A decoration welded to a body part; offset is in that part's space.
local function attach(folder, bodyPart, name, size, offset, color, shape, material)
	if not bodyPart then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.CFrame = bodyPart.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

--------------------------------------------------------------------------------
-- Hair. Head space: +Y up, -Z is the face.
--------------------------------------------------------------------------------
local function hair(folder, body, style, color)
	local head, H = body.Head, body.H
	if not head or style == "bald" then
		return
	end
	local top = H / 2
	local function add(name, size, offset, shape)
		return attach(folder, head, name, size * H, offset, color, shape, Enum.Material.SmoothPlastic)
	end
	if style == "buzz" then
		add("Hair", Vector3.new(1.02, 0.25, 1.02), CFrame.new(0, top - 0.08 * H, 0.02 * H))
	elseif style == "short" or style == "sidepart" then
		add("Hair", Vector3.new(1.06, 0.34, 1.06), CFrame.new(0, top - 0.06 * H, 0.03 * H))
		add("HairBack", Vector3.new(1.04, 0.5, 0.2), CFrame.new(0, 0.12 * H, 0.46 * H))
		if style == "sidepart" then
			add("Fringe", Vector3.new(0.6, 0.18, 0.2), CFrame.new(-0.18 * H, top - 0.12 * H, -0.47 * H) * CFrame.Angles(0, 0, math.rad(-12)))
		else
			add("Fringe", Vector3.new(0.9, 0.14, 0.16), CFrame.new(0, top - 0.14 * H, -0.47 * H))
		end
	elseif style == "long" or style == "bob" then
		local length = if style == "long" then 1.25 else 0.7
		add("Hair", Vector3.new(1.08, 0.34, 1.08), CFrame.new(0, top - 0.05 * H, 0.02 * H))
		add("HairBack", Vector3.new(1.1, length, 0.28), CFrame.new(0, top - length / 2 * H, 0.47 * H))
		for _, sx in ipairs({ -1, 1 }) do
			add("HairSide", Vector3.new(0.18, length * 0.85, 0.8), CFrame.new(sx * 0.53 * H, top - length * 0.45 * H, 0.08 * H))
		end
		add("Fringe", Vector3.new(0.95, 0.16, 0.14), CFrame.new(0, top - 0.14 * H, -0.48 * H))
	elseif style == "ponytail" or style == "bun" then
		add("Hair", Vector3.new(1.06, 0.34, 1.06), CFrame.new(0, top - 0.06 * H, 0.03 * H))
		add("HairBack", Vector3.new(1.04, 0.45, 0.2), CFrame.new(0, 0.15 * H, 0.46 * H))
		if style == "bun" then
			add("Bun", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, top + 0.12 * H, 0.2 * H), "Ball")
		else
			add("Tie", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, top - 0.15 * H, 0.56 * H), "Ball")
			add("Ponytail", Vector3.new(0.24, 0.8, 0.24), CFrame.new(0, top - 0.55 * H, 0.64 * H) * CFrame.Angles(math.rad(12), 0, 0))
		end
	elseif style == "afro" then
		add("Hair", Vector3.new(1.55, 1.3, 1.5), CFrame.new(0, top - 0.02 * H, 0.1 * H), "Ball")
	elseif style == "curly" then
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			add("Curl", Vector3.new(0.42, 0.42, 0.42), CFrame.new(math.cos(a) * 0.38 * H, top - 0.02 * H, math.sin(a) * 0.38 * H + 0.05 * H), "Ball")
		end
		add("Curl", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, top + 0.06 * H, 0.05 * H), "Ball")
	elseif style == "mohawk" then
		add("Hair", Vector3.new(1.02, 0.14, 1.02), CFrame.new(0, top - 0.1 * H, 0.02 * H))
		add("Mohawk", Vector3.new(0.18, 0.5, 1.0), CFrame.new(0, top + 0.18 * H, 0.05 * H))
	elseif style == "spiky" then
		add("Hair", Vector3.new(1.04, 0.28, 1.04), CFrame.new(0, top - 0.08 * H, 0.03 * H))
		for k = -2, 2 do
			local spike = add("Spike", Vector3.new(0.22, 0.4, 0.22), CFrame.new(k * 0.19 * H, top + 0.1 * H, (k % 2) * 0.15 * H) * CFrame.Angles(0, 0, math.rad(-k * 10)))
			if spike then
				spike.Name = "Spike"
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Items. Each one decorates the head, torso, arms or legs.
--------------------------------------------------------------------------------
local HATS = { Toque = true, TallToque = true, Cap = true, PoliceCap = true, HardHat = true, StrawHat = true, Beanie = true, FireHelmet = true, Beret = true, BucketHat = true }

local ITEMS = {}

-- torso helpers: front of the torso is -Z
local function torsoFront(body, name, size, y, color, material, folder)
	local t = body.Torso
	return attach(folder, t, name, size, CFrame.new(0, y, -t.Size.Z / 2 - size.Z / 2 + 0.02), color, nil, material)
end

function ITEMS.Toque(f, b, c)
	local H = b.H
	attach(f, b.Head, "HatBand", Vector3.new(1.04, 0.22, 1.04) * H, CFrame.new(0, H * 0.5, 0), WHITE, "Cylinder").CFrame = b.Head.CFrame * CFrame.new(0, H * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	attach(f, b.Head, "HatPuff", Vector3.new(1.1, 0.65, 1.1) * H, CFrame.new(0, H * 0.82, 0), c or WHITE, "Ball")
end
function ITEMS.TallToque(f, b, c)
	local H = b.H
	attach(f, b.Head, "HatBand", Vector3.new(1.04, 0.25, 1.04) * H, CFrame.new(0, H * 0.52, 0), WHITE)
	attach(f, b.Head, "HatTall", Vector3.new(0.95, 0.9, 0.95) * H, CFrame.new(0, H * 1.05, 0), WHITE)
	attach(f, b.Head, "HatPuff", Vector3.new(1.2, 0.5, 1.2) * H, CFrame.new(0, H * 1.5, 0), WHITE, "Ball")
end
function ITEMS.Cap(f, b, c)
	local H = b.H
	c = c or rgb(200, 50, 50)
	attach(f, b.Head, "Cap", Vector3.new(1.08, 0.36, 1.08) * H, CFrame.new(0, H * 0.46, 0.02 * H), c)
	attach(f, b.Head, "CapBrim", Vector3.new(0.9, 0.08, 0.5) * H, CFrame.new(0, H * 0.32, -0.7 * H), c:Lerp(BLACK, 0.2))
end
function ITEMS.PoliceCap(f, b)
	local H = b.H
	local navy = rgb(25, 32, 70)
	attach(f, b.Head, "CapBand", Vector3.new(1.1, 0.24, 1.1) * H, CFrame.new(0, H * 0.4, 0), BLACK)
	attach(f, b.Head, "CapTop", Vector3.new(1.3, 0.2, 1.3) * H, CFrame.new(0, H * 0.6, 0), navy)
	attach(f, b.Head, "CapBrim", Vector3.new(0.9, 0.07, 0.4) * H, CFrame.new(0, H * 0.3, -0.66 * H) * CFrame.Angles(math.rad(-12), 0, 0), BLACK)
	attach(f, b.Head, "CapBadge", Vector3.new(0.22, 0.2, 0.05) * H, CFrame.new(0, H * 0.43, -0.57 * H), GOLD, nil, Enum.Material.Metal)
end
function ITEMS.HardHat(f, b)
	local H = b.H
	attach(f, b.Head, "HardHat", Vector3.new(1.2, 0.75, 1.25) * H, CFrame.new(0, H * 0.55, 0), rgb(250, 200, 40), "Ball")
	attach(f, b.Head, "HardHatBrim", Vector3.new(1.3, 0.07, 1.4) * H, CFrame.new(0, H * 0.35, -0.05 * H), rgb(240, 190, 30))
end
function ITEMS.StrawHat(f, b)
	local H = b.H
	local straw = rgb(230, 200, 120)
	attach(f, b.Head, "HatBrim", Vector3.new(0.08, 2.1, 2.1) * H, CFrame.new(0, H * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), straw, "Cylinder", Enum.Material.Fabric)
	attach(f, b.Head, "HatCrown", Vector3.new(0.45, 1.05, 1.05) * H, CFrame.new(0, H * 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)), straw, "Cylinder", Enum.Material.Fabric)
	attach(f, b.Head, "HatRibbon", Vector3.new(0.1, 1.08, 1.08) * H, CFrame.new(0, H * 0.48, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(200, 60, 60), "Cylinder")
end
function ITEMS.Beanie(f, b, c)
	local H = b.H
	c = c or rgb(60, 60, 70)
	attach(f, b.Head, "Beanie", Vector3.new(1.1, 0.8, 1.1) * H, CFrame.new(0, H * 0.45, 0.02 * H), c, "Ball", Enum.Material.Fabric)
	attach(f, b.Head, "BeanieFold", Vector3.new(1.12, 0.18, 1.12) * H, CFrame.new(0, H * 0.28, 0.02 * H), c:Lerp(BLACK, 0.2), nil, Enum.Material.Fabric)
	attach(f, b.Head, "Pompom", Vector3.new(0.3, 0.3, 0.3) * H, CFrame.new(0, H * 0.9, 0), c:Lerp(WHITE, 0.5), "Ball", Enum.Material.Fabric)
end
function ITEMS.FireHelmet(f, b)
	local H = b.H
	local red = rgb(200, 30, 30)
	attach(f, b.Head, "Helmet", Vector3.new(1.25, 0.85, 1.3) * H, CFrame.new(0, H * 0.52, 0.05 * H), red, "Ball")
	attach(f, b.Head, "HelmetBrim", Vector3.new(1.3, 0.07, 1.7) * H, CFrame.new(0, H * 0.3, 0.2 * H), red:Lerp(BLACK, 0.2))
	attach(f, b.Head, "HelmetShield", Vector3.new(0.45, 0.4, 0.06) * H, CFrame.new(0, H * 0.72, -0.62 * H), GOLD, nil, Enum.Material.Metal)
end
function ITEMS.Beret(f, b, c)
	local H = b.H
	attach(f, b.Head, "Beret", Vector3.new(1.2, 0.3, 1.15) * H, CFrame.new(0.12 * H, H * 0.55, 0) * CFrame.Angles(0, 0, math.rad(-10)), c or rgb(180, 40, 60), "Ball", Enum.Material.Fabric)
	attach(f, b.Head, "BeretTip", Vector3.new(0.08, 0.14, 0.08) * H, CFrame.new(0.14 * H, H * 0.72, 0), c or rgb(180, 40, 60))
end
function ITEMS.BucketHat(f, b, c)
	local H = b.H
	c = c or rgb(110, 130, 90)
	attach(f, b.Head, "HatBrim", Vector3.new(0.08, 1.5, 1.5) * H, CFrame.new(0, H * 0.36, 0) * CFrame.Angles(0, 0, math.rad(90)), c, "Cylinder", Enum.Material.Fabric)
	attach(f, b.Head, "HatCrown", Vector3.new(0.5, 1.08, 1.08) * H, CFrame.new(0, H * 0.58, 0) * CFrame.Angles(0, 0, math.rad(90)), c, "Cylinder", Enum.Material.Fabric)
end
function ITEMS.Headband(f, b, c)
	local H = b.H
	attach(f, b.Head, "Headband", Vector3.new(0.16, 1.06, 1.06) * H, CFrame.new(0, H * 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), c or WHITE, "Cylinder", Enum.Material.Fabric)
end
function ITEMS.Headphones(f, b)
	local H = b.H
	attach(f, b.Head, "HeadphoneBand", Vector3.new(1.2, 0.1, 0.18) * H, CFrame.new(0, H * 0.58, 0), BLACK)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Earcup", Vector3.new(0.2, 0.42, 0.42) * H, CFrame.new(sx * 0.58 * H, H * 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 200, 220), "Cylinder", Enum.Material.Neon)
	end
end
function ITEMS.Glasses(f, b)
	local H = b.H
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Lens", Vector3.new(0.06, 0.28, 0.28) * H, CFrame.new(sx * 0.2 * H, H * 0.1, -0.52 * H) * CFrame.Angles(0, math.rad(90), 0), BLACK, "Cylinder", Enum.Material.Metal)
	end
	attach(f, b.Head, "Bridge", Vector3.new(0.14, 0.04, 0.04) * H, CFrame.new(0, H * 0.12, -0.53 * H), BLACK)
end

function ITEMS.Apron(f, b, c)
	local t = b.Torso
	c = c or WHITE
	torsoFront(b, "Apron", Vector3.new(t.Size.X * 0.7, t.Size.Y * 0.8, 0.08), -t.Size.Y * 0.05, c, Enum.Material.Fabric, f)
	if b.Lower and b.Lower ~= t then
		attach(f, b.Lower, "ApronSkirt", Vector3.new(b.Lower.Size.X * 0.75, 1.2, 0.08), CFrame.new(0, -0.35, -b.Lower.Size.Z / 2 - 0.05), c, nil, Enum.Material.Fabric)
	end
	torsoFront(b, "ApronPocket", Vector3.new(t.Size.X * 0.35, t.Size.Y * 0.18, 0.1), -t.Size.Y * 0.2, c:Lerp(BLACK, 0.12), Enum.Material.Fabric, f)
end
function ITEMS.LabCoat(f, b)
	local t = b.Torso
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "CoatPanel", Vector3.new(t.Size.X * 0.34, t.Size.Y + 0.1, 0.1), CFrame.new(sx * t.Size.X * 0.34, 0, -t.Size.Z / 2 - 0.05), WHITE, nil, Enum.Material.Fabric)
		attach(f, t, "CoatSide", Vector3.new(0.08, t.Size.Y + 0.1, t.Size.Z + 0.1), CFrame.new(sx * (t.Size.X / 2 + 0.04), 0, 0), WHITE, nil, Enum.Material.Fabric)
		if b.Lower and b.Lower ~= t then
			attach(f, b.Lower, "CoatTail", Vector3.new(b.Lower.Size.X * 0.45, 1.4, 0.1), CFrame.new(sx * b.Lower.Size.X * 0.26, -0.45, -b.Lower.Size.Z / 2 - 0.05), WHITE, nil, Enum.Material.Fabric)
		end
	end
	attach(f, t, "CoatBack", Vector3.new(t.Size.X + 0.1, t.Size.Y + 0.1, 0.08), CFrame.new(0, 0, t.Size.Z / 2 + 0.04), WHITE, nil, Enum.Material.Fabric)
	attach(f, b.LeftArm, "Sleeve", b.LeftArm and (b.LeftArm.Size + Vector3.new(0.08, 0, 0.08)) or Vector3.one, CFrame.new(), WHITE, nil, Enum.Material.Fabric)
	attach(f, b.RightArm, "Sleeve", b.RightArm and (b.RightArm.Size + Vector3.new(0.08, 0, 0.08)) or Vector3.one, CFrame.new(), WHITE, nil, Enum.Material.Fabric)
	torsoFront(b, "CoatPen", Vector3.new(0.06, 0.35, 0.06), b.Torso.Size.Y * 0.25, rgb(40, 80, 200), nil, f)
end
function ITEMS.Stethoscope(f, b)
	local t = b.Torso
	for _, sx in ipairs({ -1, 1 }) do
		torsoFront(b, "StethTube", Vector3.new(0.08, t.Size.Y * 0.5, 0.08), t.Size.Y * 0.15, BLACK, nil, f).CFrame = t.CFrame * CFrame.new(sx * 0.25, t.Size.Y * 0.15, -t.Size.Z / 2 - 0.12) * CFrame.Angles(0, 0, math.rad(sx * 15))
	end
	torsoFront(b, "StethDisk", Vector3.new(0.26, 0.26, 0.1), -t.Size.Y * 0.12, SILVER, Enum.Material.Metal, f)
end
function ITEMS.Badge(f, b)
	local t = b.Torso
	attach(f, t, "Badge", Vector3.new(0.34, 0.4, 0.06), CFrame.new(-t.Size.X * 0.25, t.Size.Y * 0.2, -t.Size.Z / 2 - 0.04), GOLD, nil, Enum.Material.Metal)
	attach(f, t, "BadgeStar", Vector3.new(0.18, 0.18, 0.07), CFrame.new(-t.Size.X * 0.25, t.Size.Y * 0.2, -t.Size.Z / 2 - 0.06) * CFrame.Angles(0, 0, math.rad(45)), rgb(210, 160, 40), nil, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "Epaulette", Vector3.new(0.5, 0.1, t.Size.Z * 0.9), CFrame.new(sx * t.Size.X * 0.38, t.Size.Y / 2, 0), rgb(20, 25, 55))
	end
end
function ITEMS.Radio(f, b)
	local t = b.Torso
	attach(f, t, "Radio", Vector3.new(0.25, 0.4, 0.15), CFrame.new(t.Size.X * 0.3, t.Size.Y * 0.28, -t.Size.Z / 2 - 0.08), BLACK)
end
function ITEMS.Belt(f, b, c)
	local lower = b.Lower or b.Torso
	attach(f, lower, "Belt", Vector3.new(lower.Size.X + 0.06, 0.25, lower.Size.Z + 0.06), CFrame.new(0, if b.R15 then 0 else -lower.Size.Y / 2 + 0.15, 0), c or BLACK, nil, Enum.Material.Fabric)
	attach(f, lower, "Buckle", Vector3.new(0.3, 0.2, 0.06), CFrame.new(0, if b.R15 then 0 else -lower.Size.Y / 2 + 0.15, -lower.Size.Z / 2 - 0.04), SILVER, nil, Enum.Material.Metal)
end
function ITEMS.HiVisVest(f, b)
	local t = b.Torso
	local vest = rgb(250, 140, 30)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "Vest", Vector3.new(t.Size.X * 0.4, t.Size.Y, 0.08), CFrame.new(sx * t.Size.X * 0.3, 0, -t.Size.Z / 2 - 0.04), vest, nil, Enum.Material.Fabric)
	end
	attach(f, t, "VestBack", Vector3.new(t.Size.X, t.Size.Y, 0.08), CFrame.new(0, 0, t.Size.Z / 2 + 0.04), vest, nil, Enum.Material.Fabric)
	attach(f, t, "VestStripe", Vector3.new(t.Size.X + 0.2, 0.14, t.Size.Z + 0.2), CFrame.new(0, -t.Size.Y * 0.15, 0), rgb(230, 240, 240), nil, Enum.Material.Neon)
end
function ITEMS.ReflectiveStripes(f, b)
	local t = b.Torso
	for _, y in ipairs({ 0.15, -0.25 }) do
		attach(f, t, "Stripe", Vector3.new(t.Size.X + 0.1, 0.16, t.Size.Z + 0.1), CFrame.new(0, t.Size.Y * y, 0), rgb(240, 240, 120), nil, Enum.Material.Neon)
	end
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		attach(f, arm, "Stripe", arm and Vector3.new(arm.Size.X + 0.08, 0.14, arm.Size.Z + 0.08) or Vector3.one, CFrame.new(0, -0.1, 0), rgb(240, 240, 120), nil, Enum.Material.Neon)
	end
end
function ITEMS.Gloves(f, b)
	for _, hand in ipairs({ b.LeftHand, b.RightHand }) do
		if hand then
			local s = if b.R15 then hand.Size + Vector3.new(0.08, 0.08, 0.08) else Vector3.new(hand.Size.X + 0.06, 0.5, hand.Size.Z + 0.06)
			attach(f, hand, "Glove", s, CFrame.new(0, if b.R15 then 0 else -hand.Size.Y / 2 + 0.25, 0), rgb(190, 150, 90), nil, Enum.Material.Fabric)
		end
	end
end
function ITEMS.Overalls(f, b, c)
	local t = b.Torso
	torsoFront(b, "Bib", Vector3.new(t.Size.X * 0.6, t.Size.Y * 0.55, 0.08), -t.Size.Y * 0.2, c, Enum.Material.Fabric, f)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "Strap", Vector3.new(0.18, t.Size.Y * 0.5, t.Size.Z + 0.1), CFrame.new(sx * t.Size.X * 0.25, t.Size.Y * 0.25, 0), c, nil, Enum.Material.Fabric)
		torsoFront(b, "Button", Vector3.new(0.12, 0.12, 0.06), t.Size.Y * 0.07, SILVER, Enum.Material.Metal, f).CFrame = t.CFrame * CFrame.new(sx * t.Size.X * 0.25, t.Size.Y * 0.07, -t.Size.Z / 2 - 0.1)
	end
end
function ITEMS.GuitarBack(f, b)
	local t = b.Torso
	local wood = rgb(190, 110, 50)
	local cf = CFrame.new(0.2, -0.2, t.Size.Z / 2 + 0.3) * CFrame.Angles(0, 0, math.rad(35))
	attach(f, t, "GuitarBody", Vector3.new(1.1, 1.3, 0.35), cf * CFrame.new(0, -0.3, 0), wood, "Ball")
	attach(f, t, "GuitarNeck", Vector3.new(0.2, 1.4, 0.15), cf * CFrame.new(0, 0.9, 0), rgb(80, 50, 30))
	attach(f, t, "GuitarStrap", Vector3.new(0.12, t.Size.Y * 1.1, t.Size.Z + 0.25), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(-35)), rgb(60, 40, 30), nil, Enum.Material.Fabric)
end
function ITEMS.Tie(f, b, c)
	local t = b.Torso
	c = c or rgb(150, 40, 50)
	torsoFront(b, "Collar", Vector3.new(0.6, 0.14, 0.06), t.Size.Y / 2 - 0.08, WHITE, nil, f)
	torsoFront(b, "Tie", Vector3.new(0.22, t.Size.Y * 0.62, 0.06), t.Size.Y * 0.12, c, Enum.Material.Fabric, f)
	torsoFront(b, "TieKnot", Vector3.new(0.26, 0.2, 0.08), t.Size.Y / 2 - 0.2, c:Lerp(BLACK, 0.15), Enum.Material.Fabric, f)
end
function ITEMS.BowTie(f, b, c)
	local t = b.Torso
	c = c or BLACK
	for _, sx in ipairs({ -1, 1 }) do
		torsoFront(b, "BowWing", Vector3.new(0.24, 0.2, 0.08), t.Size.Y / 2 - 0.16, c, Enum.Material.Fabric, f).CFrame = t.CFrame * CFrame.new(sx * 0.15, t.Size.Y / 2 - 0.16, -t.Size.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(sx * 20))
	end
	torsoFront(b, "BowKnot", Vector3.new(0.1, 0.12, 0.1), t.Size.Y / 2 - 0.16, c:Lerp(BLACK, 0.2), nil, f)
end
function ITEMS.Vest(f, b, c)
	local t = b.Torso
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "VestPanel", Vector3.new(t.Size.X * 0.38, t.Size.Y * 0.85, 0.08), CFrame.new(sx * t.Size.X * 0.31, -t.Size.Y * 0.07, -t.Size.Z / 2 - 0.04), c, nil, Enum.Material.Fabric)
	end
	attach(f, t, "VestBack", Vector3.new(t.Size.X, t.Size.Y * 0.85, 0.08), CFrame.new(0, -t.Size.Y * 0.07, t.Size.Z / 2 + 0.04), c, nil, Enum.Material.Fabric)
end
function ITEMS.Cardigan(f, b, c)
	ITEMS.Vest(f, b, c)
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		attach(f, arm, "Sleeve", arm and (arm.Size + Vector3.new(0.08, 0, 0.08)) or Vector3.one, CFrame.new(), c, nil, Enum.Material.Fabric)
	end
	for k = 0, 2 do
		torsoFront(b, "Button", Vector3.new(0.1, 0.1, 0.06), b.Torso.Size.Y * (0.2 - k * 0.25), GOLD, nil, f).CFrame = b.Torso.CFrame * CFrame.new(b.Torso.Size.X * 0.13, b.Torso.Size.Y * (0.2 - k * 0.25), -b.Torso.Size.Z / 2 - 0.1)
	end
end
function ITEMS.ChefButtons(f, b)
	local t = b.Torso
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			torsoFront(b, "ChefButton", Vector3.new(0.12, 0.12, 0.06), 0, rgb(40, 40, 45), nil, f).CFrame = t.CFrame * CFrame.new(sx * 0.3, t.Size.Y * (0.25 - k * 0.25), -t.Size.Z / 2 - 0.04)
		end
	end
end
function ITEMS.Neckerchief(f, b, c)
	local t = b.Torso
	torsoFront(b, "Neckerchief", Vector3.new(0.7, 0.3, 0.08), t.Size.Y / 2 - 0.15, c, Enum.Material.Fabric, f)
	torsoFront(b, "NeckerchiefTip", Vector3.new(0.3, 0.3, 0.08), t.Size.Y / 2 - 0.35, c, Enum.Material.Fabric, f).CFrame = t.CFrame * CFrame.new(0, t.Size.Y / 2 - 0.35, -t.Size.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(45))
end
function ITEMS.NameTag(f, b)
	local t = b.Torso
	attach(f, t, "NameTag", Vector3.new(0.45, 0.2, 0.05), CFrame.new(t.Size.X * 0.25, t.Size.Y * 0.2, -t.Size.Z / 2 - 0.04), WHITE)
end
function ITEMS.Lanyard(f, b)
	local t = b.Torso
	for _, sx in ipairs({ -1, 1 }) do
		torsoFront(b, "Lanyard", Vector3.new(0.06, t.Size.Y * 0.45, 0.05), 0, rgb(40, 90, 200), nil, f).CFrame = t.CFrame * CFrame.new(sx * 0.17, t.Size.Y * 0.2, -t.Size.Z / 2 - 0.04) * CFrame.Angles(0, 0, math.rad(sx * 12))
	end
	torsoFront(b, "IdCard", Vector3.new(0.34, 0.44, 0.05), -t.Size.Y * 0.08, WHITE, nil, f)
end
function ITEMS.PocketSquare(f, b)
	local t = b.Torso
	attach(f, t, "PocketSquare", Vector3.new(0.3, 0.16, 0.06), CFrame.new(-t.Size.X * 0.27, t.Size.Y * 0.22, -t.Size.Z / 2 - 0.04), WHITE)
end
function ITEMS.GoldWatch(f, b)
	local arm = b.LeftHand
	if arm then
		attach(f, arm, "Watch", Vector3.new(arm.Size.X + 0.06, 0.16, arm.Size.Z + 0.06), CFrame.new(0, if b.R15 then arm.Size.Y / 2 else -arm.Size.Y / 2 + 0.5, 0), GOLD, nil, Enum.Material.Metal)
	end
end
function ITEMS.Wristbands(f, b)
	for _, hand in ipairs({ b.LeftHand, b.RightHand }) do
		if hand then
			attach(f, hand, "Wristband", Vector3.new(hand.Size.X + 0.08, 0.2, hand.Size.Z + 0.08), CFrame.new(0, if b.R15 then hand.Size.Y / 2 else -hand.Size.Y / 2 + 0.55, 0), WHITE, nil, Enum.Material.Fabric)
		end
	end
end
function ITEMS.Whistle(f, b)
	local t = b.Torso
	torsoFront(b, "WhistleCord", Vector3.new(0.05, t.Size.Y * 0.4, 0.05), t.Size.Y * 0.18, rgb(40, 40, 45), nil, f)
	torsoFront(b, "Whistle", Vector3.new(0.3, 0.16, 0.16), -t.Size.Y * 0.02, SILVER, Enum.Material.Metal, f)
end
function ITEMS.BookUnderArm(f, b)
	local arm = b.LeftArm
	if arm then
		attach(f, arm, "Book", Vector3.new(0.25, 0.9, 0.7), CFrame.new(0.55, -0.2, 0), rgb(120, 40, 50))
	end
end
function ITEMS.TowelArm(f, b)
	local arm = b.LeftArm
	if arm then
		attach(f, arm, "Towel", Vector3.new(arm.Size.X + 0.12, 0.5, arm.Size.Z + 0.12), CFrame.new(0, -arm.Size.Y * 0.2, 0), WHITE, nil, Enum.Material.Fabric)
	end
end
function ITEMS.WrenchBelt(f, b)
	local lower = b.Lower or b.Torso
	attach(f, lower, "Wrench", Vector3.new(0.14, 0.8, 0.1), CFrame.new(lower.Size.X * 0.45, -0.3, -lower.Size.Z / 2 - 0.08), SILVER, nil, Enum.Material.Metal)
end
function ITEMS.Smudge(f, b)
	if b.Head then
		attach(f, b.Head, "Smudge", Vector3.new(0.22, 0.12, 0.04) * b.H, CFrame.new(0.22 * b.H, -0.12 * b.H, -0.5 * b.H), rgb(60, 50, 45))
	end
end
function ITEMS.PaintSmudge(f, b)
	local t = b.Torso
	for k, col in ipairs({ rgb(230, 60, 60), rgb(60, 120, 230), rgb(250, 200, 50) }) do
		attach(f, t, "Paint", Vector3.new(0.2, 0.16, 0.05), CFrame.new(-0.5 + k * 0.3, -t.Size.Y * 0.25 + k * 0.1, -t.Size.Z / 2 - 0.03), col)
	end
end
function ITEMS.Binoculars(f, b)
	local t = b.Torso
	torsoFront(b, "Strap", Vector3.new(0.06, t.Size.Y * 0.4, 0.05), t.Size.Y * 0.2, rgb(60, 40, 30), nil, f)
	for _, sx in ipairs({ -1, 1 }) do
		torsoFront(b, "Lens", Vector3.new(0.2, 0.36, 0.2), -t.Size.Y * 0.05, rgb(40, 45, 40), Enum.Material.Metal, f).CFrame = t.CFrame * CFrame.new(sx * 0.13, -t.Size.Y * 0.05, -t.Size.Z / 2 - 0.14)
	end
end
function ITEMS.Scarf(f, b)
	local t = b.Torso
	local c = rgb(200, 60, 70)
	attach(f, t, "Scarf", Vector3.new(t.Size.X * 0.7, 0.3, t.Size.Z + 0.2), CFrame.new(0, t.Size.Y / 2 - 0.1, 0), c, nil, Enum.Material.Fabric)
	torsoFront(b, "ScarfEnd", Vector3.new(0.3, t.Size.Y * 0.5, 0.08), t.Size.Y * 0.1, c, Enum.Material.Fabric, f).CFrame = t.CFrame * CFrame.new(t.Size.X * 0.15, t.Size.Y * 0.1, -t.Size.Z / 2 - 0.08)
	for k = 0, 2 do
		attach(f, t, "ScarfStripe", Vector3.new(0.32, 0.06, 0.1), CFrame.new(t.Size.X * 0.15, t.Size.Y * (0.25 - k * 0.12), -t.Size.Z / 2 - 0.12), WHITE, nil, Enum.Material.Fabric)
	end
end
function ITEMS.Backpack(f, b, c)
	local t = b.Torso
	c = c or rgb(60, 130, 220)
	attach(f, t, "Backpack", Vector3.new(t.Size.X * 0.7, t.Size.Y * 0.8, 0.6), CFrame.new(0, -t.Size.Y * 0.05, t.Size.Z / 2 + 0.3), c, nil, Enum.Material.Fabric)
	attach(f, t, "BackpackPocket", Vector3.new(t.Size.X * 0.5, t.Size.Y * 0.3, 0.2), CFrame.new(0, -t.Size.Y * 0.2, t.Size.Z / 2 + 0.68), c:Lerp(BLACK, 0.2), nil, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "BackpackStrap", Vector3.new(0.14, t.Size.Y * 0.9, t.Size.Z + 0.12), CFrame.new(sx * t.Size.X * 0.22, 0, 0), c:Lerp(BLACK, 0.3), nil, Enum.Material.Fabric)
	end
end
function ITEMS.Bib(f, b, c)
	local t = b.Torso
	torsoFront(b, "Bib", Vector3.new(t.Size.X * 0.55, t.Size.Y * 0.5, 0.06), t.Size.Y * 0.1, c or rgb(255, 200, 220), Enum.Material.Fabric, f)
end
function ITEMS.Cane(f, b)
	local hand = b.RightHand
	if hand then
		attach(f, hand, "Cane", Vector3.new(0.14, 3, 0.14), CFrame.new(0.1, -1.4, -0.3), rgb(100, 65, 40), nil, Enum.Material.Wood)
		attach(f, hand, "CaneHandle", Vector3.new(0.14, 0.14, 0.5), CFrame.new(0.1, 0.05, -0.15), rgb(100, 65, 40), nil, Enum.Material.Wood)
	end
end

--------------------------------------------------------------------------------
-- Putting it together
--------------------------------------------------------------------------------

-- What a citizen will look like (colors, hair, items), without building it.
function CitizenLook.Describe(citizen)
	local name = tostring(field(citizen, "Name", "name", "DisplayName") or "Citizen")
	local rng = Random.new(hash(name) + (Config.SEED or 0))
	local age = tonumber(field(citizen, "Age", "age")) or rng:NextInteger(20, 60)
	local job = jobTitle(citizen)
	local hobby = field(citizen, "Hobby", "hobby")
	local retired = age >= (Config.RETIRE_AGE or 67)
	local kid = age < (Config.ADULT_AGE or 18)
	local uniform = (not retired) and (not kid) and job and UNIFORMS[job] or nil

	local look = {
		Skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)],
		Hair = HAIRSTYLES[rng:NextInteger(1, #HAIRSTYLES)],
		HairColor = HAIR_COLORS[rng:NextInteger(1, #HAIR_COLORS)],
		Top = CASUAL_TOPS[rng:NextInteger(1, #CASUAL_TOPS)],
		Bottom = CASUAL_BOTTOMS[rng:NextInteger(1, #CASUAL_BOTTOMS)],
		Shoes = ({ rgb(40, 35, 32), rgb(240, 240, 240), rgb(110, 70, 45), rgb(200, 60, 60) })[rng:NextInteger(1, 4)],
		Sleeves = if rng:NextNumber() < 0.5 then "long" else "short",
		Items = {},
		Age = age,
		Job = job,
	}
	if age < 3 then
		-- babies: a little soft hair and a bib
		look.Hair = if rng:NextNumber() < 0.5 then "buzz" else "bald"
		look.Sleeves = "long"
		look.Top = ({ rgb(255, 220, 230), rgb(200, 230, 255), rgb(255, 245, 200), rgb(210, 245, 210) })[rng:NextInteger(1, 4)]
		look.Bottom = look.Top
		table.insert(look.Items, "Bib")
		return look
	elseif kid and age >= 6 then
		table.insert(look.Items, "Backpack:" .. ({ "60,130,220", "220,70,90", "90,180,110", "240,170,40", "150,90,210" })[rng:NextInteger(1, 5)])
	end
	if age < 30 and rng:NextNumber() < 0.15 then
		look.HairColor = FUN_HAIR[rng:NextInteger(1, #FUN_HAIR)]
	elseif age >= 55 then
		look.HairColor = GRAY_HAIR[rng:NextInteger(1, #GRAY_HAIR)]
		if look.Hair == "mohawk" or look.Hair == "spiky" then
			look.Hair = "short"
		end
	end
	if uniform then
		look.Top = uniform.Top or look.Top
		look.Bottom = uniform.Bottom or look.Bottom
		look.Sleeves = uniform.Sleeves or look.Sleeves
		for _, item in ipairs(uniform.Items or {}) do
			table.insert(look.Items, item)
		end
	end
	if retired then
		table.insert(look.Items, "Cardigan:" .. ({ "150,120,100", "120,130,150", "160,110,120" })[rng:NextInteger(1, 3)])
		table.insert(look.Items, "Glasses")
		table.insert(look.Items, "Cane")
	end
	-- a hobby touch, unless the uniform already covers that spot
	local hasHat = false
	for _, item in ipairs(look.Items) do
		if HATS[(parseItem(item))] then
			hasHat = true
		end
	end
	for _, item in ipairs((hobby and HOBBY_ITEMS[hobby]) or {}) do
		local itemName = parseItem(item)
		local duplicate = false
		for _, existing in ipairs(look.Items) do
			if parseItem(existing) == itemName then
				duplicate = true
			end
		end
		if not duplicate and not (HATS[itemName] and hasHat) and not (itemName == "Headband" and hasHat) then
			table.insert(look.Items, item)
		end
	end
	-- hats sit better on shorter hair
	if hasHat and (look.Hair == "afro" or look.Hair == "mohawk" or look.Hair == "spiky" or look.Hair == "bun") then
		look.Hair = "short"
	end
	return look
end

local function paint(part, color)
	if part then
		part.Color = color
	end
end

function CitizenLook.Apply(model, citizen, options)
	options = options or {}
	local look = CitizenLook.Describe(citizen or {})
	local old = model:FindFirstChild("CitizenLook")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "CitizenLook"
	folder.Parent = model

	-- body colors: skin, top, sleeves, bottom and shoes
	if not options.KeepClothing then
		for _, c in ipairs(model:GetChildren()) do
			if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then
				c:Destroy()
			end
		end
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy() -- we color the parts directly (works for R15 and R6)
	end
	local sleeve = if look.Sleeves == "long" then look.Top else look.Skin
	local r15 = model:FindFirstChild("UpperTorso") ~= nil
	paint(model:FindFirstChild("Head"), look.Skin)
	if r15 then
		paint(model:FindFirstChild("UpperTorso"), look.Top)
		paint(model:FindFirstChild("LowerTorso"), look.Bottom)
		for _, side in ipairs({ "Left", "Right" }) do
			paint(model:FindFirstChild(side .. "UpperArm"), look.Top)
			paint(model:FindFirstChild(side .. "LowerArm"), sleeve)
			paint(model:FindFirstChild(side .. "Hand"), look.Skin)
			paint(model:FindFirstChild(side .. "UpperLeg"), look.Bottom)
			paint(model:FindFirstChild(side .. "LowerLeg"), look.Bottom)
			paint(model:FindFirstChild(side .. "Foot"), look.Shoes)
		end
	else
		paint(model:FindFirstChild("Torso"), look.Top)
		paint(model:FindFirstChild("Left Arm"), sleeve)
		paint(model:FindFirstChild("Right Arm"), sleeve)
		paint(model:FindFirstChild("Left Leg"), look.Bottom)
		paint(model:FindFirstChild("Right Leg"), look.Bottom)
	end
	-- everything else is welded on
	local body = readBody(model)
	if body.Head and body.Torso then
		hair(folder, body, look.Hair, look.HairColor)
		for _, item in ipairs(look.Items) do
			local name, color = parseItem(item)
			local build = ITEMS[name]
			if build then
				local ok, err = pcall(build, folder, body, color)
				if not ok then
					warn("[CitizenLook] " .. name .. ": " .. tostring(err))
				end
			end
		end
		if not r15 then
			-- R6 has no shoes: give the bottom of the legs a shoe color band
			for _, leg in ipairs({ body.LeftLeg, body.RightLeg }) do
				attach(folder, leg, "Shoe", leg and Vector3.new(leg.Size.X + 0.04, 0.35, leg.Size.Z + 0.12) or Vector3.one, CFrame.new(0, leg and (-leg.Size.Y / 2 + 0.17) or 0, -0.05), look.Shoes)
			end
		end
	end
	model:SetAttribute("Look", look.Hair .. (if look.Job then " / " .. look.Job else ""))
	return look
end

-- A brand new dressed R15 NPC (server only). Parent it and set its position yourself.
function CitizenLook.Build(citizen)
	local Players = game:GetService("Players")
	local description = Instance.new("HumanoidDescription")
	local look = CitizenLook.Describe(citizen or {})
	description.HeadColor = look.Skin
	description.LeftArmColor = look.Skin
	description.RightArmColor = look.Skin
	description.TorsoColor = look.Top
	description.LeftLegColor = look.Bottom
	description.RightLegColor = look.Bottom
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = tostring(field(citizen or {}, "Name", "name") or "Citizen")
	CitizenLook.Apply(model, citizen)
	return model
end

-- the uniform table, so other scripts can add or tweak outfits
CitizenLook.Uniforms = UNIFORMS
CitizenLook.HobbyItems = HOBBY_ITEMS

return CitizenLook
