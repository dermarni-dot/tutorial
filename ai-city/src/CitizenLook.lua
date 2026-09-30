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
local Faces = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Faces"))

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
	rgb(226, 190, 150), rgb(186, 128, 90), rgb(128, 82, 58), rgb(72, 46, 34), rgb(240, 200, 164),
}
local HAIR_COLORS = {
	rgb(30, 24, 22), rgb(58, 38, 28), rgb(92, 60, 38), rgb(128, 84, 52), rgb(160, 96, 48), -- black to light brown
	rgb(214, 170, 100), rgb(236, 206, 140), rgb(178, 70, 40), -- blonde, light blonde, red
}
local FUN_HAIR = { rgb(240, 110, 170), rgb(90, 150, 240), rgb(140, 90, 220), rgb(90, 200, 160) }
local GRAY_HAIR = { rgb(200, 200, 200), rgb(170, 170, 172), rgb(235, 235, 235) }
local HAIRSTYLES = { "short", "buzz", "long", "ponytail", "bun", "afro", "curly", "mohawk", "bob", "spiky", "sidepart", "bald", "braids", "pigtails", "wavy", "undercut", "topknot", "locs" }
local CASUAL_TOPS = { rgb(220, 70, 70), rgb(70, 130, 220), rgb(90, 180, 110), rgb(240, 190, 60), rgb(160, 100, 200), rgb(240, 140, 60), rgb(80, 190, 200), rgb(235, 235, 230), rgb(60, 60, 70), rgb(230, 120, 160) }
local CASUAL_BOTTOMS = { rgb(50, 70, 120), rgb(70, 60, 50), rgb(40, 40, 45), rgb(120, 110, 90), rgb(90, 100, 110), rgb(60, 90, 70) }
local JEANS = { rgb(60, 90, 140), rgb(45, 65, 105), rgb(90, 120, 165), rgb(35, 40, 55) }
local KID_TOPS = { rgb(255, 90, 90), rgb(80, 170, 255), rgb(120, 220, 110), rgb(255, 210, 60), rgb(190, 120, 250), rgb(255, 150, 60), rgb(90, 220, 220), rgb(255, 130, 190) }
local SHOES = { rgb(40, 35, 32), rgb(240, 240, 240), rgb(110, 70, 45), rgb(200, 60, 60), rgb(60, 90, 160), rgb(30, 30, 30) }
-- everyday outfits for people off duty (a few items each)
local CASUAL_STYLES = {
	adult = { { "Tee" }, { "Tee" }, { "Polo" }, { "Hoodie" }, { "Jacket" }, { "Stripes" }, { "Sweater" }, { "Dress" },
		{ "Blazer" }, { "Flannel" }, { "Puffer" }, { "Tank" }, { "Skirt", "Tee" }, { "Flannel", "Tee" }, { "Blazer", "Skirt" } },
	teen = { { "Hoodie" }, { "Hoodie" }, { "Tee" }, { "Jacket" }, { "Stripes" }, { "Tee", "CapBack" }, { "Dress" }, { "Varsity" }, { "Puffer" }, { "Flannel" }, { "Skirt", "Tee" }, { "Tank" } },
	kid = { { "Tee" }, { "Stripes" }, { "Hoodie" }, { "Overalls" }, { "Dress" }, { "Varsity" }, { "Puffer" } },
}

--------------------------------------------------------------------------------
-- Uniforms, by job title. Colors: Top, Sleeves ("long"/"short"), Bottom,
-- Shoes. Items are extra pieces added to the body (see ITEMS below).
--------------------------------------------------------------------------------
local UNIFORMS = {
	["Baker"] = { Top = WHITE, Bottom = rgb(90, 80, 70), Items = { "Toque", "Apron:240,220,190" } },
	["Barista"] = { Top = BLACK, Bottom = rgb(60, 50, 45), Items = { "Apron:40,120,80", "Cap:40,120,80", "NameTag" } },
	["Doctor"] = { Top = rgb(170, 210, 240), Bottom = rgb(60, 70, 90), Sleeves = "long", Items = { "LabCoat", "Stethoscope", "NameTag" } },
	["Nurse"] = { Top = rgb(70, 170, 170), Bottom = rgb(70, 170, 170), Items = { "Stethoscope", "NameTag" } },
	-- the two street gangs, and rioters (masked)
	["Viper"] = { Top = rgb(40, 120, 60), Bottom = rgb(30, 30, 34), Sleeves = "long", Items = { "Hoodie:40,120,60", "Beanie:30,140,70", "Sneakers:40,200,90" } },
	["King"] = { Top = rgb(100, 45, 140), Bottom = rgb(40, 40, 46), Sleeves = "long", Items = { "Jacket:90,40,130", "CapBack:120,50,160", "Necklace", "Sneakers:170,90,230" } },
	["Rioter"] = { Top = rgb(30, 30, 34), Bottom = rgb(45, 45, 50), Sleeves = "long", Items = { "Hoodie:30,30,34", "Beanie:25,25,28" } },
	["Police Officer"] = { Top = rgb(40, 55, 110), Bottom = rgb(30, 40, 80), Sleeves = "long", Items = { "PoliceCap", "Badge", "Belt:25,25,30", "Radio" } },
	["Thief"] = { Top = rgb(38, 40, 48), Bottom = rgb(30, 32, 38), Sleeves = "long", Items = { "Hoodie:38,40,50", "Beanie:28,28,32", "Gloves" } },
	["SWAT Officer"] = { Top = rgb(32, 34, 40), Bottom = rgb(32, 34, 40), Sleeves = "long", Items = { "SWATHelmet", "Vest:22,24,28", "Badge", "Belt:20,20,22", "Gloves", "Radio" } },
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
	["Middle School Teacher"] = { Top = rgb(90, 130, 170), Bottom = rgb(80, 75, 70), Sleeves = "long", Items = { "Vest:60,70,90", "Lanyard", "Glasses" } },
	["High School Teacher"] = { Top = rgb(230, 225, 210), Bottom = rgb(60, 60, 75), Sleeves = "long", Items = { "Tie:120,40,60", "Lanyard" } },
	["Coach"] = { Top = rgb(30, 90, 170), Bottom = rgb(30, 30, 40), Items = { "Cap:30,90,170", "Whistle", "Stripes:250,250,250" } },
	["Daycare Worker"] = { Top = rgb(255, 190, 90), Bottom = rgb(80, 110, 160), Items = { "Apron:120,200,220", "NameTag" } },
	["Museum Guide"] = { Top = rgb(120, 40, 50), Bottom = rgb(40, 40, 45), Sleeves = "long", Items = { "Vest:40,40,45", "NameTag", "Lanyard" } },
	["Mail Carrier"] = { Top = rgb(170, 190, 220), Bottom = rgb(40, 60, 110), Items = { "Cap:40,60,110", "MailBag" } },
	["Arcade Attendant"] = { Top = rgb(120, 40, 180), Bottom = BLACK, Items = { "Cap:240,60,200", "NameTag", "Headphones" } },
	["Cook"] = { Top = WHITE, Bottom = rgb(60, 60, 60), Items = { "Toque", "Apron:220,50,60" } },
	["Programmer"] = { Top = rgb(50, 55, 65), Bottom = rgb(60, 90, 140), Sleeves = "long", Items = { "Hoodie", "Headphones", "Lanyard" } },
	["Accountant"] = { Top = rgb(235, 235, 240), Bottom = rgb(50, 55, 70), Sleeves = "long", Items = { "Tie:40,100,80", "Glasses", "Lanyard" } },
	["Night Janitor"] = { Top = rgb(80, 110, 120), Bottom = rgb(80, 110, 120), Items = { "Cap:60,80,90", "Gloves", "NameTag" } },
	["Community Organizer"] = { Top = rgb(90, 170, 110), Bottom = rgb(90, 80, 70), Items = { "Lanyard", "Scarf" } },
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
	-- on a sculpted (rounded) limb, anything wrapped around it — sleeves, cuffs,
	-- bands — becomes a round tube instead of a box
	if not shape and bodyPart:GetAttribute("Sculpted") then
		local ps = bodyPart.Size
		if size.X >= ps.X * 0.9 and size.Z >= ps.Z * 0.9 and size.X <= ps.X + 0.4 and size.Z <= ps.Z + 0.4 then
			-- fitted to the rounded limb (a little looser than it)
			local grow = math.max(size.X - ps.X, size.Z - ps.Z, 0)
			local d = (bodyPart:GetAttribute("SculptD") or math.max(size.X, size.Z)) + 0.06 + grow * 0.6
			size = Vector3.new(size.Y, d, d)
			offset = offset * CFrame.Angles(0, 0, math.rad(90))
			shape = "Cylinder"
		end
	end
	p.Size = size
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
		if name == "Hair" and not shape and Config.ROUND_HAIR ~= false then
			-- the cap of hair is round (a ball over the top and back of the
			-- head), not a box; thin haircuts sit lower and closer
			local thin = size.Y < 0.3
			local d = (if thin then 1.08 else 1.14) * H
			return attach(folder, head, name, Vector3.new(d, d, d), CFrame.new(0, (if thin then 0.1 else 0.15) * H, 0.1 * H), color, "Ball", Enum.Material.SmoothPlastic)
		end
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
	elseif style == "braids" or style == "locs" then
		-- a cap of hair and rows of braids / locs hanging down the back and sides
		add("Hair", Vector3.new(1.06, 0.32, 1.06), CFrame.new(0, top - 0.06 * H, 0.03 * H))
		local n = if style == "locs" then 9 else 7
		local len = if style == "locs" then 1.0 else 1.25
		for k = 0, n - 1 do
			local a = math.rad(-110 + k * (220 / (n - 1)))
			local x, z = math.sin(a) * 0.5, math.cos(a) * 0.5
			-- (cylinders run along X: turned upright)
			add("Braid", Vector3.new(len, 0.16, 0.16), CFrame.new(x * H, top - (0.2 + len / 2) * H, (z + 0.02) * H) * CFrame.Angles(0, 0, math.rad(90)), "Cylinder")
		end
		if style == "braids" then
			local tie = add("BraidTie", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, top - (0.2 + len) * H, 0.52 * H), "Ball")
		if tie then
			tie.Color = GOLD
		end
		end
	elseif style == "pigtails" then
		add("Hair", Vector3.new(1.06, 0.34, 1.06), CFrame.new(0, top - 0.06 * H, 0.03 * H))
		add("Fringe", Vector3.new(0.9, 0.16, 0.14), CFrame.new(0, top - 0.14 * H, -0.47 * H))
		for _, sx in ipairs({ -1, 1 }) do
			add("Pigtail", Vector3.new(0.34, 0.34, 0.34), CFrame.new(sx * 0.6 * H, top - 0.2 * H, 0.15 * H), "Ball")
			add("Pigtail", Vector3.new(0.26, 0.6, 0.26), CFrame.new(sx * 0.7 * H, top - 0.55 * H, 0.18 * H) * CFrame.Angles(0, 0, sx * math.rad(-12)))
		end
	elseif style == "wavy" then
		add("Hair", Vector3.new(1.1, 0.36, 1.1), CFrame.new(0, top - 0.04 * H, 0.02 * H))
		for k = 0, 4 do
			add("Wave", Vector3.new(0.34, 0.34, 0.34), CFrame.new((-0.42 + k * 0.21) * H, top - (0.5 + (k % 2) * 0.15) * H, 0.48 * H), "Ball")
			add("Wave", Vector3.new(0.3, 0.3, 0.3), CFrame.new((-0.42 + k * 0.21) * H, top - (0.8 + ((k + 1) % 2) * 0.12) * H, 0.46 * H), "Ball")
		end
		for _, sx in ipairs({ -1, 1 }) do
			add("HairSide", Vector3.new(0.2, 0.75, 0.7), CFrame.new(sx * 0.53 * H, top - 0.45 * H, 0.08 * H))
		end
		add("Fringe", Vector3.new(0.6, 0.2, 0.16), CFrame.new(0.16 * H, top - 0.14 * H, -0.47 * H) * CFrame.Angles(0, 0, math.rad(10)))
	elseif style == "undercut" then
		add("Hair", Vector3.new(1.0, 0.12, 1.0), CFrame.new(0, top - 0.14 * H, 0.02 * H))
		add("HairTop", Vector3.new(0.78, 0.36, 0.95), CFrame.new(0, top + 0.06 * H, -0.02 * H))
		add("Quiff", Vector3.new(0.7, 0.24, 0.3), CFrame.new(0, top + 0.16 * H, -0.4 * H) * CFrame.Angles(math.rad(-20), 0, 0))
	elseif style == "topknot" then
		add("Hair", Vector3.new(1.05, 0.3, 1.05), CFrame.new(0, top - 0.07 * H, 0.03 * H))
		add("HairBack", Vector3.new(1.02, 0.4, 0.2), CFrame.new(0, 0.16 * H, 0.46 * H))
		add("Knot", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, top + 0.2 * H, 0), "Ball")
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
local HATS = { Fedora = true, Toque = true, TallToque = true, Cap = true, PoliceCap = true, HardHat = true, StrawHat = true, Beanie = true, FireHelmet = true, Beret = true, BucketHat = true }

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
function ITEMS.SWATHelmet(f, b)
	local H = b.H
	attach(f, b.Head, "SWATHelmet", Vector3.new(1.22, 0.8, 1.26) * H, CFrame.new(0, H * 0.46, 0.02 * H), rgb(28, 30, 34), "Ball")
	attach(f, b.Head, "Visor", Vector3.new(0.95, 0.22, 0.1) * H, CFrame.new(0, H * 0.28, -0.6 * H), rgb(20, 22, 26), nil, Enum.Material.Glass)
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

-- everyday clothes
local function band(f, part, name, y, height, color, grow)
	if part then
		grow = grow or 0.05
		attach(f, part, name, Vector3.new(part.Size.X + grow, height, part.Size.Z + grow), CFrame.new(0, y, 0), color, nil, Enum.Material.Fabric)
	end
end
function ITEMS.Tee(f, b, c)
	local t = b.Torso
	-- a round neckline and a small chest print
	attach(f, t, "Neckline", Vector3.new(t.Size.X * 0.4, 0.08, t.Size.Z * 0.6), CFrame.new(0, t.Size.Y / 2 - 0.02, -0.02), (c or WHITE):Lerp(BLACK, 0.25), nil, Enum.Material.Fabric)
	if c then
		torsoFront(b, "Print", Vector3.new(t.Size.X * 0.3, t.Size.Y * 0.25, 0.04), t.Size.Y * 0.1, c, Enum.Material.SmoothPlastic, f)
	end
end
function ITEMS.Polo(f, b, c)
	local t = b.Torso
	c = c or WHITE
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "Collar", Vector3.new(t.Size.X * 0.28, 0.1, 0.3), CFrame.new(sx * t.Size.X * 0.16, t.Size.Y / 2 - 0.05, -t.Size.Z / 2 + 0.1) * CFrame.Angles(0, 0, sx * math.rad(-15)), c, nil, Enum.Material.Fabric)
	end
	for k = 0, 1 do
		torsoFront(b, "Button", Vector3.new(0.08, 0.08, 0.04), t.Size.Y * (0.32 - k * 0.14), c, nil, f)
	end
end
function ITEMS.Hoodie(f, b, c)
	local t = b.Torso
	local base = c or t.Color
	attach(f, t, "Hood", Vector3.new(t.Size.X * 0.75, 0.5, 0.55), CFrame.new(0, t.Size.Y / 2 - 0.05, t.Size.Z / 2 + 0.05) * CFrame.Angles(math.rad(-20), 0, 0), base:Lerp(BLACK, 0.12), nil, Enum.Material.Fabric)
	torsoFront(b, "HoodiePocket", Vector3.new(t.Size.X * 0.6, t.Size.Y * 0.25, 0.08), -t.Size.Y * 0.28, base:Lerp(BLACK, 0.12), Enum.Material.Fabric, f)
	for _, sx in ipairs({ -1, 1 }) do
		torsoFront(b, "HoodieString", Vector3.new(0.05, t.Size.Y * 0.28, 0.04), t.Size.Y * 0.22, WHITE, nil, f).CFrame = t.CFrame * CFrame.new(sx * 0.14, t.Size.Y * 0.22, -t.Size.Z / 2 - 0.04)
	end
	band(f, b.Lower ~= t and b.Lower or nil, "HoodieHem", b.Lower and b.Lower.Size.Y * 0.3 or 0, 0.2, base:Lerp(BLACK, 0.12))
end
function ITEMS.Jacket(f, b, c)
	local t = b.Torso
	c = c or rgb(60, 60, 70)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "JacketPanel", Vector3.new(t.Size.X * 0.3, t.Size.Y + 0.04, 0.08), CFrame.new(sx * t.Size.X * 0.36, 0, -t.Size.Z / 2 - 0.04), c, nil, Enum.Material.Fabric)
		attach(f, t, "Lapel", Vector3.new(0.14, t.Size.Y * 0.4, 0.06), CFrame.new(sx * t.Size.X * 0.22, t.Size.Y * 0.28, -t.Size.Z / 2 - 0.07) * CFrame.Angles(0, 0, sx * math.rad(20)), c:Lerp(BLACK, 0.2), nil, Enum.Material.Fabric)
		attach(f, t, "JacketSide", Vector3.new(0.08, t.Size.Y + 0.04, t.Size.Z + 0.08), CFrame.new(sx * (t.Size.X / 2 + 0.04), 0, 0), c, nil, Enum.Material.Fabric)
	end
	attach(f, t, "JacketBack", Vector3.new(t.Size.X + 0.08, t.Size.Y + 0.04, 0.08), CFrame.new(0, 0, t.Size.Z / 2 + 0.04), c, nil, Enum.Material.Fabric)
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		attach(f, arm, "Sleeve", arm and (arm.Size + Vector3.new(0.08, 0, 0.08)) or Vector3.one, CFrame.new(), c, nil, Enum.Material.Fabric)
	end
end
function ITEMS.Stripes(f, b, c)
	local t = b.Torso
	c = c or WHITE
	for k = 0, 2 do
		band(f, t, "Stripe", t.Size.Y * (0.25 - k * 0.25), t.Size.Y * 0.1, c)
	end
end
function ITEMS.Sweater(f, b, c)
	local t = b.Torso
	c = c or t.Color
	band(f, t, "SweaterHem", -t.Size.Y / 2 + 0.1, 0.2, c:Lerp(BLACK, 0.15))
	band(f, t, "SweaterPattern", t.Size.Y * 0.15, 0.16, c:Lerp(WHITE, 0.4))
	for _, arm in ipairs({ b.LeftHand and b.LeftHand.Parent and b.LeftHand.Parent:FindFirstChild("LeftLowerArm"), b.RightHand and b.RightHand.Parent and b.RightHand.Parent:FindFirstChild("RightLowerArm") }) do
		if arm then
			band(f, arm, "Cuff", -arm.Size.Y / 2 + 0.1, 0.18, c:Lerp(BLACK, 0.15))
		end
	end
end
function ITEMS.Dress(f, b, c)
	local L = b.Lower
	if not L or L == b.Torso then
		return
	end
	c = c or b.Torso.Color
	attach(f, L, "Skirt", Vector3.new(L.Size.X + 0.25, 0.7, L.Size.Z + 0.25), CFrame.new(0, -0.25, 0), c, nil, Enum.Material.Fabric)
	attach(f, L, "SkirtHem", Vector3.new(L.Size.X + 0.6, 0.6, L.Size.Z + 0.5), CFrame.new(0, -0.85, 0), c, nil, Enum.Material.Fabric)
	attach(f, L, "SkirtTrim", Vector3.new(L.Size.X + 0.64, 0.1, L.Size.Z + 0.54), CFrame.new(0, -1.1, 0), c:Lerp(WHITE, 0.45), nil, Enum.Material.Fabric)
end
function ITEMS.Blazer(f, b, c)
	ITEMS.Jacket(f, b, c or rgb(40, 50, 80))
	local t = b.Torso
	-- a shirt showing between the lapels, with buttons
	torsoFront(b, "Shirt", Vector3.new(t.Size.X * 0.34, t.Size.Y * 0.9, 0.05), 0, WHITE, Enum.Material.Fabric, f)
	for k = 0, 1 do
		torsoFront(b, "BlazerButton", Vector3.new(0.1, 0.1, 0.12), -t.Size.Y * (0.08 + k * 0.2), rgb(30, 30, 30), nil, f).CFrame = t.CFrame * CFrame.new(t.Size.X * 0.2, -t.Size.Y * (0.08 + k * 0.2), -t.Size.Z / 2 - 0.1)
	end
end
function ITEMS.Flannel(f, b, c)
	local t = b.Torso
	c = c or rgb(170, 50, 50)
	-- a plaid shirt: dark bands across and down, and on the sleeves
	for k = -2, 2 do
		band(f, t, "Plaid", k * t.Size.Y * 0.2, 0.08, c:Lerp(BLACK, 0.45), 0.04)
		attach(f, t, "PlaidV", Vector3.new(0.08, t.Size.Y + 0.03, t.Size.Z + 0.03), CFrame.new(k * t.Size.X * 0.2, 0, 0), c:Lerp(BLACK, 0.45), nil, Enum.Material.Fabric)
	end
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		if arm then
			attach(f, arm, "FlannelSleeve", arm.Size + Vector3.new(0.06, 0, 0.06), CFrame.new(), c, nil, Enum.Material.Fabric)
			band(f, arm, "Plaid", 0, 0.08, c:Lerp(BLACK, 0.45), 0.1)
		end
	end
	for k = 0, 2 do
		torsoFront(b, "Button", Vector3.new(0.07, 0.07, 0.04), t.Size.Y * (0.3 - k * 0.25), WHITE, nil, f)
	end
end
function ITEMS.Puffer(f, b, c)
	local t = b.Torso
	c = c or rgb(40, 60, 110)
	-- a padded jacket: puffy quilted rings around the body and the arms
	for k = -2, 2 do
		attach(f, t, "Puff", Vector3.new(t.Size.X + 0.3, t.Size.Y * 0.2, t.Size.Z + 0.3), CFrame.new(0, k * t.Size.Y * 0.2, 0), if k % 2 == 0 then c else c:Lerp(BLACK, 0.12), nil, Enum.Material.Fabric)
	end
	attach(f, t, "PufferCollar", Vector3.new(t.Size.X * 0.7, 0.35, t.Size.Z + 0.35), CFrame.new(0, t.Size.Y / 2 + 0.1, 0), c:Lerp(BLACK, 0.1), nil, Enum.Material.Fabric)
	torsoFront(b, "Zip", Vector3.new(0.05, t.Size.Y, 0.2), 0, SILVER, Enum.Material.Metal, f)
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		if arm then
			attach(f, arm, "PufferSleeve", arm.Size + Vector3.new(0.22, 0, 0.22), CFrame.new(), c, nil, Enum.Material.Fabric)
		end
	end
end
function ITEMS.Varsity(f, b, c)
	c = c or rgb(150, 30, 40)
	local t = b.Torso
	ITEMS.Jacket(f, b, c)
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		if arm then
			attach(f, arm, "VarsitySleeve", arm.Size + Vector3.new(0.12, 0, 0.12), CFrame.new(), rgb(240, 236, 226), nil, Enum.Material.Fabric)
		end
	end
	band(f, t, "VarsityHem", -t.Size.Y / 2 + 0.08, 0.16, rgb(240, 236, 226), 0.14)
	attach(f, t, "Letter", Vector3.new(0.4, 0.5, 0.06), CFrame.new(-t.Size.X * 0.3, t.Size.Y * 0.12, -t.Size.Z / 2 - 0.12), GOLD, nil, Enum.Material.Fabric)
end
function ITEMS.Tank(f, b, c)
	local t = b.Torso
	c = c or t.Color
	-- bare shoulders and arms under the straps
	for _, arm in ipairs({ b.LeftArm, b.RightArm }) do
		if arm then
			arm.Color = b.Head.Color
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, t, "Strap", Vector3.new(0.3, 0.1, t.Size.Z + 0.04), CFrame.new(sx * t.Size.X * 0.28, t.Size.Y / 2, 0), c, nil, Enum.Material.Fabric)
	end
end
function ITEMS.Skirt(f, b, c)
	local L = b.Lower
	if not L or L == b.Torso then
		return
	end
	c = c or rgb(40, 40, 60)
	attach(f, L, "Skirt", Vector3.new(L.Size.X + 0.3, 1.0, L.Size.Z + 0.3), CFrame.new(0, -0.45, 0), c, nil, Enum.Material.Fabric)
	for k = -2, 2 do
		attach(f, L, "Pleat", Vector3.new(0.05, 0.9, 0.05), CFrame.new(k * L.Size.X * 0.18, -0.5, -L.Size.Z / 2 - 0.17), c:Lerp(BLACK, 0.25), nil, Enum.Material.Fabric)
	end
end
function ITEMS.Sunglasses(f, b)
	local H = b.H
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Shades", Vector3.new(0.34, 0.2, 0.05) * H, CFrame.new(sx * 0.2 * H, H * 0.1, -0.53 * H), rgb(20, 20, 26), nil, Enum.Material.Glass)
	end
	attach(f, b.Head, "ShadesBridge", Vector3.new(0.9, 0.05, 0.04) * H, CFrame.new(0, H * 0.18, -0.53 * H), rgb(20, 20, 26), nil, Enum.Material.Metal)
end
function ITEMS.Fedora(f, b, c)
	local H = b.H
	c = c or rgb(70, 60, 50)
	attach(f, b.Head, "HatBrim", Vector3.new(0.08, 1.5, 1.5) * H, CFrame.new(0, H * 0.46, 0) * CFrame.Angles(0, 0, math.rad(90)), c, "Cylinder", Enum.Material.Fabric)
	attach(f, b.Head, "HatCrown", Vector3.new(0.9, 0.45, 0.9) * H, CFrame.new(0, H * 0.7, 0), c, nil, Enum.Material.Fabric)
	attach(f, b.Head, "HatBand", Vector3.new(0.92, 0.1, 0.92) * H, CFrame.new(0, H * 0.54, 0), rgb(30, 30, 30), nil, Enum.Material.Fabric)
end
function ITEMS.CrossBag(f, b, c)
	local t = b.Torso
	c = c or rgb(120, 70, 45)
	attach(f, t, "BagStrap", Vector3.new(0.1, t.Size.Y * 1.35, 0.06), CFrame.new(0, 0, -t.Size.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(-38)), c:Lerp(BLACK, 0.3), nil, Enum.Material.Fabric)
	attach(f, t, "Bag", Vector3.new(0.7, 0.6, 0.3), CFrame.new(t.Size.X / 2 + 0.1, -t.Size.Y / 2, -0.1), c, nil, Enum.Material.Fabric)
end
function ITEMS.Bracelets(f, b, c)
	local arm = b.LeftHand
	if arm then
		for k = 0, 1 do
			attach(f, arm, "Bracelet", Vector3.new(arm.Size.X + 0.08, 0.07, arm.Size.Z + 0.08), CFrame.new(0, arm.Size.Y / 2 - 0.05 - k * 0.1, 0), c or GOLD, nil, Enum.Material.Metal)
		end
	end
end
function ITEMS.CapBack(f, b, c)
	local H = b.H
	c = c or rgb(40, 40, 50)
	attach(f, b.Head, "Cap", Vector3.new(1.08, 0.36, 1.08) * H, CFrame.new(0, H * 0.46, 0.02 * H), c)
	attach(f, b.Head, "CapBrim", Vector3.new(0.9, 0.08, 0.5) * H, CFrame.new(0, H * 0.34, 0.7 * H), c:Lerp(BLACK, 0.2))
end
function ITEMS.Beard(f, b, c)
	local H = b.H
	c = c or rgb(60, 40, 30)
	attach(f, b.Head, "Beard", Vector3.new(0.86, 0.3, 0.4) * H, CFrame.new(0, -0.42 * H, -0.36 * H), c)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Sideburn", Vector3.new(0.12, 0.5, 0.36) * H, CFrame.new(sx * 0.46 * H, -0.18 * H, -0.2 * H), c)
	end
	attach(f, b.Head, "Mustache", Vector3.new(0.38, 0.09, 0.1) * H, CFrame.new(0, -0.16 * H, -0.54 * H), c)
end
function ITEMS.Mustache(f, b, c)
	local H = b.H
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Mustache", Vector3.new(0.24, 0.09, 0.1) * H, CFrame.new(sx * 0.11 * H, -0.15 * H, -0.54 * H) * CFrame.Angles(0, 0, sx * math.rad(-10)), c or rgb(60, 40, 30))
	end
end
function ITEMS.Stubble(f, b, c)
	local H = b.H
	local s = attach(f, b.Head, "Stubble", Vector3.new(0.8, 0.28, 0.3) * H, CFrame.new(0, -0.38 * H, -0.37 * H), c or rgb(60, 40, 30))
	if s then
		s.Transparency = 0.55
	end
end
function ITEMS.Earrings(f, b, c)
	local H = b.H
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Earring", Vector3.new(0.12, 0.12, 0.12) * H, CFrame.new(sx * 0.52 * H, -0.12 * H, 0), c or GOLD, "Ball", Enum.Material.Metal)
	end
end
function ITEMS.Necklace(f, b, c)
	local t = b.Torso
	attach(f, t, "Necklace", Vector3.new(t.Size.X * 0.42, 0.05, t.Size.Z * 0.75), CFrame.new(0, t.Size.Y / 2 - 0.06, -0.05), c or GOLD, nil, Enum.Material.Metal)
	torsoFront(b, "Pendant", Vector3.new(0.12, 0.12, 0.05), t.Size.Y * 0.35, c or GOLD, Enum.Material.Metal, f)
end
function ITEMS.Watch(f, b, c)
	local arm = b.LeftHand and b.LeftHand.Parent and b.LeftHand.Parent:FindFirstChild("LeftLowerArm")
	if arm then
		band(f, arm, "Watch", -arm.Size.Y / 2 + 0.12, 0.12, c or BLACK, 0.06)
	end
end
function ITEMS.HairBow(f, b, c)
	local H = b.H
	c = c or rgb(250, 110, 160)
	for _, sx in ipairs({ -1, 1 }) do
		attach(f, b.Head, "Bow", Vector3.new(0.3, 0.22, 0.08) * H, CFrame.new(0.3 * H + sx * 0.14 * H, 0.52 * H, -0.1 * H) * CFrame.Angles(0, 0, sx * math.rad(20)), c)
	end
	attach(f, b.Head, "BowKnot", Vector3.new(0.1, 0.1, 0.1) * H, CFrame.new(0.3 * H, 0.52 * H, -0.1 * H), c:Lerp(BLACK, 0.2), "Ball")
end
function ITEMS.Pacifier(f, b)
	local H = b.H
	attach(f, b.Head, "Pacifier", Vector3.new(0.3, 0.2, 0.06) * H, CFrame.new(0, -0.25 * H, -0.56 * H), rgb(150, 210, 255), nil)
	attach(f, b.Head, "PacifierRing", Vector3.new(0.14, 0.14, 0.14) * H, CFrame.new(0, -0.25 * H, -0.62 * H), rgb(255, 255, 255), "Ball")
end
function ITEMS.Sneakers(f, b, c)
	local model = b.Head and b.Head.Parent
	for _, side in ipairs({ "Left", "Right" }) do
		local foot = model and model:FindFirstChild(side .. "Foot")
		if foot and foot:IsA("BasePart") then
			attach(f, foot, "Sole", Vector3.new(foot.Size.X + 0.06, 0.12, foot.Size.Z + 0.1), CFrame.new(0, -foot.Size.Y / 2 + 0.05, 0), WHITE, nil, Enum.Material.Rubber)
			attach(f, foot, "Swoosh", Vector3.new(foot.Size.X + 0.04, 0.08, foot.Size.Z * 0.5), CFrame.new(0, 0, 0), c or rgb(230, 60, 60))
		end
	end
end
function ITEMS.MailBag(f, b)
	local t = b.Torso
	attach(f, t, "BagStrap", Vector3.new(0.14, t.Size.Y * 1.3, t.Size.Z + 0.14), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(35)), rgb(90, 60, 40), nil, Enum.Material.Fabric)
	attach(f, t, "MailBag", Vector3.new(0.5, 0.9, 1.1), CFrame.new(t.Size.X / 2 + 0.3, -t.Size.Y * 0.45, 0), rgb(40, 60, 110), nil, Enum.Material.Fabric)
end

--------------------------------------------------------------------------------
-- Putting it together
--------------------------------------------------------------------------------

-- Names in Config.FirstNames alternate female / male; other names get a coin flip
local function isFeminine(name, rng)
	local firstName = string.match(name, "^(%S+)") or name
	for index, n in ipairs(Config.FirstNames or {}) do
		if n == firstName then
			return index % 2 == 1
		end
	end
	return rng:NextNumber() < 0.5
end

local function colorText(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local FEMININE_HAIR = { "long", "ponytail", "bun", "bob", "curly", "afro", "long", "sidepart", "braids", "wavy", "pigtails", "topknot", "locs" }
local MASCULINE_HAIR = { "short", "buzz", "sidepart", "spiky", "afro", "curly", "short", "mohawk", "bald", "undercut", "locs", "topknot", "braids" }

-- How tall someone is for their age (1 = a grown adult). height is their own
-- factor (so two 8-year-olds aren't the same size).
function CitizenLook.ScaleFor(age, height)
	local points = { { 0, 0.4 }, { 1, 0.45 }, { 3, 0.52 }, { 6, 0.6 }, { 9, 0.69 }, { 12, 0.79 }, { 14, 0.88 }, { 16, 0.95 }, { 18, 1 } }
	local scale = 1
	if age < 18 then
		for k = 1, #points - 1 do
			local a, b = points[k], points[k + 1]
			if age >= a[1] and age < b[1] then
				scale = a[2] + (b[2] - a[2]) * (age - a[1]) / (b[1] - a[1])
				break
			end
		end
	elseif age >= 75 then
		scale = 0.97 -- a little stoop
	end
	return scale * (height or 1)
end

-- What a citizen will look like (colors, hair, items, face, height), without building it.
function CitizenLook.Describe(citizen)
	local name = tostring(field(citizen, "Name", "name", "DisplayName") or "Citizen")
	local rng = Random.new(hash(name) + (Config.SEED or 0))
	local age = tonumber(field(citizen, "Age", "age")) or rng:NextInteger(20, 60)
	local job = jobTitle(citizen)
	local hobby = field(citizen, "Hobby", "hobby")
	local retired = age >= (Config.RETIRE_AGE or 67)
	local kid = age < (Config.ADULT_AGE or 18)
	local uniform = (not retired) and (not kid) and job and UNIFORMS[job] or nil
	local feminine = isFeminine(name, rng)
	local hairList = if rng:NextNumber() < 0.8 then (if feminine then FEMININE_HAIR else MASCULINE_HAIR) else HAIRSTYLES

	local look = {
		Skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)],
		Hair = hairList[rng:NextInteger(1, #hairList)],
		HairColor = HAIR_COLORS[rng:NextInteger(1, #HAIR_COLORS)],
		Top = if age < 13 then KID_TOPS[rng:NextInteger(1, #KID_TOPS)] else CASUAL_TOPS[rng:NextInteger(1, #CASUAL_TOPS)],
		Bottom = if rng:NextNumber() < 0.5 then JEANS[rng:NextInteger(1, #JEANS)] else CASUAL_BOTTOMS[rng:NextInteger(1, #CASUAL_BOTTOMS)],
		Shoes = SHOES[rng:NextInteger(1, #SHOES)],
		Sleeves = if rng:NextNumber() < 0.5 then "long" else "short",
		Items = {},
		Age = age,
		Job = job,
		Feminine = feminine,
		-- everyone has their own height: grown-ups from short to tall (women a
		-- little shorter on average), kids a bit more spread
		Height = if kid then rng:NextNumber(0.88, 1.12) elseif feminine then rng:NextNumber(0.84, 1.08) else rng:NextNumber(0.9, 1.18),
		Width = rng:NextNumber(0.85, 1.1),
	}
	-- a build: how wide and deep the body is, and its shape
	local builds = if kid then { "slim", "average", "average", "heavy" }
		elseif feminine then { "slim", "average", "average", "curvy", "curvy", "athletic", "athletic", "heavy", "muscular" }
		else { "slim", "average", "average", "athletic", "athletic", "heavy", "stocky", "muscular", "muscular" }
	look.Build = builds[rng:NextInteger(1, #builds)]
	look.Width = ({ slim = 0.78, average = 0.9, curvy = 0.92, athletic = 1, heavy = 1, stocky = 1, muscular = 1 })[look.Build] * rng:NextNumber(0.96, 1.04)
	look.Depth = ({ slim = 0.8, average = 0.9, curvy = 1, athletic = 0.92, heavy = 1, stocky = 0.96, muscular = 1 })[look.Build]
	look.Face = Faces.Describe(rng, age, feminine)
	look.Scale = CitizenLook.ScaleFor(age, look.Height)
	if age < 3 then
		-- babies: a little soft hair, a onesie, a bib and maybe a pacifier
		look.Hair = if rng:NextNumber() < 0.5 then "buzz" else "bald"
		look.Sleeves = "long"
		look.Top = ({ rgb(255, 220, 230), rgb(200, 230, 255), rgb(255, 245, 200), rgb(210, 245, 210) })[rng:NextInteger(1, 4)]
		look.Bottom = look.Top
		look.Shoes = look.Top
		table.insert(look.Items, "Bib")
		if rng:NextNumber() < 0.5 then
			table.insert(look.Items, "Pacifier")
		end
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
		if not feminine and rng:NextNumber() < 0.3 then
			look.Hair = "bald"
		end
	end
	if uniform then
		look.Top = uniform.Top or look.Top
		look.Bottom = uniform.Bottom or look.Bottom
		look.Sleeves = uniform.Sleeves or look.Sleeves
		for _, item in ipairs(uniform.Items or {}) do
			table.insert(look.Items, item)
		end
	elseif not retired then
		-- an everyday outfit
		local styles = CASUAL_STYLES[if age < 13 then "kid" elseif kid then "teen" else "adult"]
		local style = styles[rng:NextInteger(1, #styles)]
		if style[1] == "Dress" and not feminine then
			style = styles[1]
		end
		local palette = if age < 13 then KID_TOPS else CASUAL_TOPS
		local accent = palette[rng:NextInteger(1, #palette)]
		for _, item in ipairs(style) do
			if item == "Tee" then
				table.insert(look.Items, "Tee:" .. colorText(accent))
			elseif item == "Jacket" then
				table.insert(look.Items, "Jacket:" .. colorText(({ rgb(50, 50, 60), rgb(110, 80, 55), rgb(40, 70, 120), rgb(90, 100, 70) })[rng:NextInteger(1, 4)]))
			elseif item == "Stripes" then
				table.insert(look.Items, "Stripes:" .. colorText(if rng:NextNumber() < 0.5 then WHITE else accent))
			elseif item == "Dress" then
				table.insert(look.Items, "Dress:" .. colorText(look.Top))
				look.Bottom = look.Skin -- bare legs under the skirt
			elseif item == "Overalls" then
				table.insert(look.Items, "Overalls:" .. colorText(JEANS[rng:NextInteger(1, #JEANS)]))
			elseif item == "Blazer" then
				table.insert(look.Items, "Blazer:" .. colorText(({ rgb(40, 50, 80), rgb(60, 60, 66), rgb(150, 120, 90), rgb(110, 40, 50) })[rng:NextInteger(1, 4)]))
			elseif item == "Flannel" then
				table.insert(look.Items, "Flannel:" .. colorText(({ rgb(170, 50, 50), rgb(50, 100, 70), rgb(50, 80, 140), rgb(200, 150, 60) })[rng:NextInteger(1, 4)]))
			elseif item == "Puffer" then
				table.insert(look.Items, "Puffer:" .. colorText(({ rgb(40, 60, 110), rgb(30, 30, 34), rgb(200, 70, 60), rgb(90, 130, 90), rgb(240, 200, 70) })[rng:NextInteger(1, 5)]))
			elseif item == "Varsity" then
				table.insert(look.Items, "Varsity:" .. colorText(({ rgb(150, 30, 40), rgb(30, 50, 110), rgb(30, 90, 50), rgb(40, 40, 44) })[rng:NextInteger(1, 4)]))
			elseif item == "Jersey" then
				table.insert(look.Items, "Jersey:" .. colorText(({ rgb(40, 90, 200), rgb(200, 40, 50), rgb(250, 190, 40), rgb(30, 30, 36), rgb(90, 40, 140), rgb(30, 130, 80), rgb(240, 240, 240), rgb(0, 120, 190) })[rng:NextInteger(1, 8)]))
			elseif item == "Tank" then
				table.insert(look.Items, "Tank")
				look.Sleeves = "short"
			elseif item == "Skirt" then
				if feminine then
					table.insert(look.Items, "Skirt:" .. colorText(({ rgb(40, 40, 60), rgb(150, 40, 60), rgb(200, 180, 150), rgb(60, 90, 140) })[rng:NextInteger(1, 4)]))
					look.Bottom = look.Skin
				end
			elseif item == "CapBack" then
				table.insert(look.Items, "CapBack:" .. colorText(accent))
			else
				table.insert(look.Items, item)
			end
		end
	end
	if retired then
		table.insert(look.Items, "Cardigan:" .. ({ "150,120,100", "120,130,150", "160,110,120" })[rng:NextInteger(1, 3)])
		table.insert(look.Items, "Glasses")
		if age >= 72 or rng:NextNumber() < 0.4 then
			table.insert(look.Items, "Cane")
		end
	end
	-- little touches: facial hair, jewelry, watches, bows and sneakers
	if not kid and not feminine then
		local roll = rng:NextNumber()
		local hairColor = colorText(look.HairColor)
		if roll < 0.28 then
			table.insert(look.Items, "Beard:" .. hairColor)
		elseif roll < 0.42 then
			table.insert(look.Items, "Mustache:" .. hairColor)
		elseif roll < 0.58 and age < 60 then
			table.insert(look.Items, "Stubble:" .. hairColor)
		end
	end
	if not kid and feminine and rng:NextNumber() < 0.4 then
		table.insert(look.Items, "Earrings:" .. (if rng:NextNumber() < 0.6 then "245,200,70" else "220,225,235"))
	end
	if not kid and rng:NextNumber() < 0.2 and not uniform then
		table.insert(look.Items, "Necklace")
	end
	if not kid and rng:NextNumber() < 0.3 then
		table.insert(look.Items, "Watch:" .. ({ "30,30,35", "245,200,70", "200,205,215" })[rng:NextInteger(1, 3)])
	end
	-- a few more accessories so people don't all look alike
	if not kid and not uniform then
		if rng:NextNumber() < 0.15 then
			table.insert(look.Items, "Sunglasses")
		end
		if rng:NextNumber() < 0.2 then
			table.insert(look.Items, "CrossBag:" .. ({ "120,70,45", "30,30,34", "190,60,70", "200,170,130" })[rng:NextInteger(1, 4)])
		end
		if age >= 35 and rng:NextNumber() < 0.08 then
			table.insert(look.Items, "Fedora:" .. ({ "70,60,50", "40,40,44", "150,130,100" })[rng:NextInteger(1, 3)])
		end
	end
	if not kid and feminine and rng:NextNumber() < 0.25 then
		table.insert(look.Items, "Bracelets")
	end
	if age < 11 and feminine and rng:NextNumber() < 0.45 then
		table.insert(look.Items, "HairBow:" .. ({ "250,110,160", "255,200,60", "120,180,255", "170,110,240" })[rng:NextInteger(1, 4)])
	end
	if not uniform and (kid or rng:NextNumber() < 0.3) then
		table.insert(look.Items, "Sneakers:" .. colorText(KID_TOPS[rng:NextInteger(1, #KID_TOPS)]))
	end
	-- a hobby touch, unless the uniform already covers that spot
	local hasHat = false
	for _, item in ipairs(look.Items) do
		local itemName = parseItem(item)
		if HATS[itemName] or itemName == "CapBack" then
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
			if HATS[itemName] then
				hasHat = true
			end
		end
	end
	-- hats sit better on shorter hair; bows don't go with hats
	if hasHat and (look.Hair == "afro" or look.Hair == "mohawk" or look.Hair == "spiky" or look.Hair == "bun" or look.Hair == "topknot" or look.Hair == "undercut" or look.Hair == "pigtails") then
		look.Hair = "short"
	end
	if hasHat then
		for k = #look.Items, 1, -1 do
			if parseItem(look.Items[k]) == "HairBow" then
				table.remove(look.Items, k)
			end
		end
	end
	return look
end

local function paint(part, color)
	if part then
		part.Color = color
	end
end

--------------------------------------------------------------------------------
-- Sculpted bodies: no blocks. Every limb is rebuilt from round pieces welded
-- over the (then hidden) R15 parts, so the animations move them as usual:
-- capsule arms and legs with ball joints at the shoulders, elbows, hips and
-- knees, a chest with rounded sides and shoulders, round hips, round hands
-- and shoes with a rounded toe. The build adds a waist, curves, broad
-- shoulders or a belly. Colors come from the painted parts (clothes, skin).
--------------------------------------------------------------------------------
local LIMBS = { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }

local function piece(folder, part, name, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = part.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder

-- how thick the rounded arms and legs are for a build (R15 limbs are a full
-- stud thick: real arms and legs are much slimmer)
local function tapers(look)
	local build = look.Build or "average"
	local arm = (if build == "muscular" then 0.86 elseif build == "athletic" or build == "stocky" or build == "heavy" then 0.74 elseif build == "slim" then 0.58 else 0.66) * (if look.Feminine then 0.92 else 1)
	local leg = if build == "heavy" or build == "curvy" or build == "muscular" then 0.9 elseif build == "slim" then 0.72 else 0.8
	return arm, leg
end
CitizenLook.Tapers = tapers
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up (they run along X)

-- a capsule along the part's length: a tube and a ball at the top joint
local function capsule(folder, part, name, color, material, taper, jointAtTop)
	local s = part.Size
	local d = math.min(s.X, s.Z) * (taper or 1)
	piece(folder, part, name, Vector3.new(s.Y - d * 0.3, d, d), UPRIGHT, color, CYL, material)
	if jointAtTop then
		piece(folder, part, name .. "Joint", Vector3.new(d, d, d) * 1.02, CFrame.new(0, s.Y / 2 - d * 0.15, 0), color, BALL, material)
	end
	return d
end

function CitizenLook.Sculpt(model, folder, look)
	local build = look.Build or "average"
	local fabric = Enum.Material.Fabric
	local function hide(p)
		p.Transparency = 1
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
	end
	-- arms and legs
	for _, side in ipairs({ "Left", "Right" }) do
		local ua, la, hand = model:FindFirstChild(side .. "UpperArm"), model:FindFirstChild(side .. "LowerArm"), model:FindFirstChild(side .. "Hand")
		local ul, ll, foot = model:FindFirstChild(side .. "UpperLeg"), model:FindFirstChild(side .. "LowerLeg"), model:FindFirstChild(side .. "Foot")
		local armTaper, legTaper = tapers(look)
		if ua then
			local d = capsule(folder, ua, "Arm", ua.Color, nil, armTaper, true)
			if build == "muscular" or build == "athletic" then
				-- a bicep
				piece(folder, ua, "Bicep", Vector3.new(1, 1, 1) * d * 1.08, CFrame.new(0, -ua.Size.Y * 0.05, -d * 0.12), ua.Color, BALL)
			end
			hide(ua)
		end
		if la then
			capsule(folder, la, "Forearm", la.Color, nil, armTaper * 0.88, true)
			hide(la)
		end
		if hand then
			local s = hand.Size
			local d = math.min(s.X, s.Z) * armTaper * 0.85
			piece(folder, hand, "Palm", Vector3.new(d, d, d), CFrame.new(0, s.Y * 0.1, 0), hand.Color, BALL)
			piece(folder, hand, "Fingers", Vector3.new(s.Y * 0.7, d * 0.75, d * 0.75), CFrame.new(0, -s.Y * 0.25, 0) * UPRIGHT, hand.Color, CYL)
			hide(hand)
		end
		if ul then
			capsule(folder, ul, "Thigh", ul.Color, fabric, legTaper, true)
			hide(ul)
		end
		if ll then
			capsule(folder, ll, "Shin", ll.Color, fabric, legTaper * 0.88, true)
			hide(ll)
		end
		if foot then
			local s = foot.Size
			local h = s.Y * 1.1
			piece(folder, foot, "Shoe", Vector3.new(s.Z * 0.75, h, s.X * 0.95), CFrame.new(0, 0, s.Z * 0.1) * CFrame.Angles(0, math.rad(90), 0), foot.Color, CYL, Enum.Material.SmoothPlastic)
			piece(folder, foot, "ShoeToe", Vector3.new(1, 1, 1) * math.min(s.X * 0.95, h * 1.3), CFrame.new(0, 0, -s.Z * 0.28), foot.Color, BALL, Enum.Material.SmoothPlastic)
			piece(folder, foot, "Sole", Vector3.new(s.X * 0.95, 0.08, s.Z * 1.05), CFrame.new(0, -h / 2 + 0.03, -s.Z * 0.05), look.Shoes:Lerp(Color3.new(1, 1, 1), 0.6))
			hide(foot)
		end
	end
	-- the chest: a core with rounded sides and shoulders, narrower at the waist
	local ut = model:FindFirstChild("UpperTorso")
	if ut then
		local s = ut.Size
		local depth = s.Z * (if build == "curvy" or build == "heavy" then 1.05 else 0.95)
		local shoulders = if build == "muscular" then 1.16 elseif build == "athletic" or build == "stocky" then 1.06 elseif build == "slim" then 0.94 else 1
		local core = piece(folder, ut, "Chest", Vector3.new(s.X * shoulders - depth, s.Y * 0.98, depth), CFrame.new(), ut.Color, nil, fabric)
		for _, sx in ipairs({ -1, 1 }) do
			piece(folder, ut, "ChestSide", Vector3.new(s.Y * 0.62, depth, depth), CFrame.new(sx * (s.X * shoulders - depth) / 2, s.Y * 0.14, 0) * UPRIGHT, ut.Color, CYL, fabric)
			piece(folder, ut, "Shoulder", Vector3.new(depth, depth, depth) * 1.02, CFrame.new(sx * (s.X * shoulders - depth) / 2, s.Y * 0.3, 0), ut.Color, BALL, fabric)
		end
		-- the waist, tucked in (wider on heavy builds)
		local waist = if build == "heavy" then 0.98 elseif build == "athletic" or build == "curvy" or build == "muscular" then 0.72 else 0.82
		local wd = depth * 0.96
		piece(folder, ut, "Waist", Vector3.new(math.max(0.1, s.X * waist - wd), s.Y * 0.4, wd), CFrame.new(0, -s.Y * 0.28, 0), ut.Color, nil, fabric)
		for _, sx in ipairs({ -1, 1 }) do
			piece(folder, ut, "WaistSide", Vector3.new(s.Y * 0.4, wd, wd), CFrame.new(sx * (s.X * waist - wd) / 2, -s.Y * 0.28, 0) * UPRIGHT, ut.Color, CYL, fabric)
		end
		if build == "heavy" then
			piece(folder, ut, "Belly", Vector3.new(1, 1, 1) * s.X * 0.62, CFrame.new(0, -s.Y * 0.18, -depth * 0.2), ut.Color, BALL, fabric)
		elseif build == "muscular" then
			-- a big chest
			for _, sx in ipairs({ -1, 1 }) do
				piece(folder, ut, "Pec", Vector3.new(1, 1, 1) * depth * 0.62, CFrame.new(sx * s.X * 0.2, s.Y * 0.14, -depth * 0.26), ut.Color, BALL, fabric)
			end
		elseif build == "curvy" or (look.Feminine and look.Age >= 13) then
			for _, sx in ipairs({ -1, 1 }) do
				piece(folder, ut, "Bust", Vector3.new(1, 1, 1) * depth * 0.5, CFrame.new(sx * s.X * 0.17, s.Y * 0.1, -depth * 0.26), ut.Color, BALL, fabric)
			end
		end
		-- a neck
		piece(folder, ut, "NeckSkin", Vector3.new(s.Y * 0.3, s.Z * 0.5, s.Z * 0.5), CFrame.new(0, s.Y / 2 + s.Y * 0.05, 0) * UPRIGHT, look.Skin, CYL)
		hide(ut)
		core.Name = "Chest"
	end
	-- the hips: rounded, wider on curvy builds
	local lt = model:FindFirstChild("LowerTorso")
	if lt then
		local s = lt.Size
		local wide = if build == "curvy" then 1.08 elseif build == "slim" then 0.92 else 1
		piece(folder, lt, "Hips", Vector3.new(s.X * wide, s.Y * 1.1, s.Z * 0.95), CFrame.new(), lt.Color, CYL, fabric)
		for _, sx in ipairs({ -1, 1 }) do
			piece(folder, lt, "HipJoint", Vector3.new(1, 1, 1) * math.min(s.Y * 1.25, s.Z), CFrame.new(sx * s.X * wide * 0.3, -s.Y * 0.2, 0), lt.Color, BALL, fabric)
		end
		hide(lt)
	end
end


--------------------------------------------------------------------------------
-- Painted clothes: the outfit is drawn flat on the body (like a Roblox shirt
-- and pants), not built from extra blocks. Sleeves are the arm color; collars,
-- pockets, zips, plaid, stripes, jersey numbers and open jackets are painted on
-- the chest's faces. (Config.PAINTED_CLOTHES = false: the old 3D pieces.)
--------------------------------------------------------------------------------
local FACES = { Front = Enum.NormalId.Front, Back = Enum.NormalId.Back, Left = Enum.NormalId.Left, Right = Enum.NormalId.Right }

local function canvas(f, part, face)
	if not part then
		return nil
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Painted" .. face
	gui.Face = FACES[face]
	gui.Adornee = part
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.ResetOnSpawn = false
	gui.Parent = f
	return gui
end

-- a rectangle on a canvas (x, y, w, h as fractions of the face)
local function rect(gui, x, y, w, h, color, rot, round)
	if not gui then
		return nil
	end
	local r = Instance.new("Frame")
	r.BorderSizePixel = 0
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(x, y)
	r.Size = UDim2.fromScale(w, h)
	r.BackgroundColor3 = color
	r.Rotation = rot or 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = r
	end
	r.Parent = gui
	return r
end

local function label(gui, text, x, y, w, h, color, outline)
	if not gui then
		return nil
	end
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color
	if outline then
		t.TextStrokeColor3 = outline
		t.TextStrokeTransparency = 0
	end
	t.Parent = gui
	return t
end

local function armParts(b)
	local model = b.Torso and b.Torso.Parent
	local out = {}
	if model then
		for _, n in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }) do
			local p = model:FindFirstChild(n)
			if p then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function sleeves(b, color, long)
	for _, p in ipairs(armParts(b)) do
		if long or string.find(p.Name, "Upper") then
			p.Color = color
		end
	end
end

-- the same thing on all four sides of the chest
local function around(f, b, fn)
	for _, face in ipairs({ "Front", "Back", "Left", "Right" }) do
		fn(canvas(f, b.Torso, face), face)
	end
end

local PAINTED = {}
function PAINTED.Tee(f, b, c)
	local t = b.Torso
	local front = canvas(f, t, "Front")
	rect(front, 0.5, 0.02, 0.34, 0.1, t.Color:Lerp(BLACK, 0.3), 0, 0.5)
	if c then
		rect(front, 0.5, 0.42, 0.34, 0.26, c, 0, 0.15)
	end
end
function PAINTED.Polo(f, b, c)
	local t = b.Torso
	c = c or WHITE
	local front = canvas(f, t, "Front")
	rect(front, 0.4, 0.06, 0.2, 0.08, c, -18)
	rect(front, 0.6, 0.06, 0.2, 0.08, c, 18)
	rect(front, 0.5, 0.18, 0.05, 0.22, t.Color:Lerp(BLACK, 0.15))
	for k = 0, 1 do
		rect(front, 0.5, 0.14 + k * 0.1, 0.04, 0.04, c, 0, 1)
	end
end
function PAINTED.Hoodie(f, b, c)
	local base = c or b.Torso.Color
	local dark = base:Lerp(BLACK, 0.15)
	local front = canvas(f, b.Torso, "Front")
	rect(front, 0.5, 0.78, 0.6, 0.26, dark, 0, 0.2)
	for _, x in ipairs({ 0.43, 0.57 }) do
		rect(front, x, 0.22, 0.025, 0.28, WHITE)
	end
	rect(front, 0.5, 0.03, 0.46, 0.08, dark, 0, 0.5)
	-- the hood lying on the back
	rect(canvas(f, b.Torso, "Back"), 0.5, 0.14, 0.62, 0.3, dark, 0, 0.4)
	sleeves(b, base, true)
end
local function openJacket(f, b, c, inner)
	around(f, b, function(gui, face)
		if face == "Front" then
			rect(gui, 0.16, 0.5, 0.34, 1, c)
			rect(gui, 0.84, 0.5, 0.34, 1, c)
			rect(gui, 0.34, 0.2, 0.06, 0.4, c:Lerp(BLACK, 0.2), 14)
			rect(gui, 0.66, 0.2, 0.06, 0.4, c:Lerp(BLACK, 0.2), -14)
			if inner then
				rect(gui, 0.5, 0.5, 0.3, 1, inner)
			end
		else
			rect(gui, 0.5, 0.5, 1, 1, c)
		end
	end)
	sleeves(b, c, true)
end
function PAINTED.Jacket(f, b, c)
	openJacket(f, b, c or rgb(60, 60, 70))
end
function PAINTED.Blazer(f, b, c)
	c = c or rgb(40, 50, 80)
	openJacket(f, b, c, WHITE)
	local front = f:FindFirstChild("PaintedFront")
	rect(front, 0.5, 0.35, 0.08, 0.5, rgb(60, 70, 110))
	for k = 0, 1 do
		rect(front, 0.68, 0.55 + k * 0.18, 0.05, 0.05, BLACK, 0, 1)
	end
end
function PAINTED.Cardigan(f, b, c)
	openJacket(f, b, c or rgb(150, 120, 100))
end
function PAINTED.Vest(f, b, c)
	c = c or rgb(60, 60, 70)
	around(f, b, function(gui, face)
		if face == "Front" then
			rect(gui, 0.2, 0.55, 0.38, 0.9, c)
			rect(gui, 0.8, 0.55, 0.38, 0.9, c)
		elseif face == "Back" then
			rect(gui, 0.5, 0.55, 1, 0.9, c)
		end
	end)
end
function PAINTED.Stripes(f, b, c)
	c = c or WHITE
	around(f, b, function(gui)
		for k = 0, 2 do
			rect(gui, 0.5, 0.25 + k * 0.25, 1, 0.1, c)
		end
	end)
end
function PAINTED.Sweater(f, b, c)
	c = c or b.Torso.Color
	around(f, b, function(gui)
		rect(gui, 0.5, 0.95, 1, 0.1, c:Lerp(BLACK, 0.15))
		rect(gui, 0.5, 0.35, 1, 0.1, c:Lerp(WHITE, 0.4))
		for k = 0, 5 do
			rect(gui, 0.08 + k * 0.17, 0.35, 0.06, 0.06, c:Lerp(BLACK, 0.2), 45)
		end
	end)
	b.Torso.Color = c
	sleeves(b, c, true)
end
function PAINTED.Flannel(f, b, c)
	c = c or rgb(170, 50, 50)
	local line = c:Lerp(BLACK, 0.45)
	b.Torso.Color = c
	around(f, b, function(gui, face)
		for k = 0, 4 do
			rect(gui, 0.5, 0.1 + k * 0.2, 1, 0.05, line)
			rect(gui, 0.1 + k * 0.2, 0.5, 0.05, 1, line)
			rect(gui, 0.5, 0.2 + k * 0.2, 1, 0.015, WHITE:Lerp(c, 0.5))
		end
		if face == "Front" then
			rect(gui, 0.5, 0.5, 0.03, 1, line)
			for k = 0, 3 do
				rect(gui, 0.53, 0.15 + k * 0.22, 0.04, 0.04, WHITE, 0, 1)
			end
		end
	end)
	sleeves(b, c, true)
end
function PAINTED.Puffer(f, b, c)
	c = c or rgb(40, 60, 110)
	b.Torso.Color = c
	around(f, b, function(gui, face)
		for k = 1, 4 do
			rect(gui, 0.5, k * 0.2, 1, 0.025, c:Lerp(BLACK, 0.25))
		end
		if face == "Front" then
			rect(gui, 0.5, 0.5, 0.03, 1, SILVER)
			rect(gui, 0.5, 0.03, 0.6, 0.08, c:Lerp(BLACK, 0.1), 0, 0.5)
		end
	end)
	sleeves(b, c, true)
end
function PAINTED.Varsity(f, b, c)
	c = c or rgb(150, 30, 40)
	b.Torso.Color = c
	local cream = rgb(240, 236, 226)
	around(f, b, function(gui, face)
		rect(gui, 0.5, 0.96, 1, 0.08, cream)
		if face == "Front" then
			rect(gui, 0.5, 0.5, 0.04, 1, cream)
			label(gui, string.char(65 + math.floor(c.R * 20) % 26), 0.25, 0.35, 0.3, 0.35, GOLD, cream)
		elseif face == "Back" then
			label(gui, "CITY", 0.5, 0.3, 0.8, 0.28, GOLD, cream)
		end
	end)
	sleeves(b, cream, true)
end
function PAINTED.Tank(f, b, c)
	-- bare arms and shoulders
	for _, p in ipairs(armParts(b)) do
		p.Color = b.Head.Color
	end
	local skin = b.Head.Color
	for _, face in ipairs({ "Front", "Back" }) do
		local gui = canvas(f, b.Torso, face)
		rect(gui, 0.08, 0.12, 0.18, 0.26, skin)
		rect(gui, 0.92, 0.12, 0.18, 0.26, skin)
		rect(gui, 0.5, 0.02, 0.36, 0.12, skin, 0, 0.5)
	end
	for _, face in ipairs({ "Left", "Right" }) do
		rect(canvas(f, b.Torso, face), 0.5, 0.12, 1, 0.26, skin)
	end
end
-- a basketball jersey with a big number, like the hoops games
function PAINTED.Jersey(f, b, c)
	c = c or rgb(40, 90, 200)
	local trim = if (c.R + c.G + c.B) > 1.8 then rgb(30, 30, 40) else WHITE
	b.Torso.Color = c
	for _, p in ipairs(armParts(b)) do
		p.Color = b.Head.Color
	end
	local number = tostring((math.floor(c.R * 97 + c.G * 53 + c.B * 31) % 34) + 1)
	for _, face in ipairs({ "Front", "Back" }) do
		local gui = canvas(f, b.Torso, face)
		rect(gui, 0.07, 0.14, 0.16, 0.3, b.Head.Color)
		rect(gui, 0.93, 0.14, 0.16, 0.3, b.Head.Color)
		rect(gui, 0.5, 0.03, 0.4, 0.14, b.Head.Color, 0, 0.5)
		rect(gui, 0.5, 0.1, 0.44, 0.03, trim)
		label(gui, number, 0.5, if face == "Front" then 0.55 else 0.5, 0.55, 0.5, trim, c:Lerp(BLACK, 0.4))
		if face == "Back" then
			label(gui, "CITY", 0.5, 0.2, 0.6, 0.14, trim)
		end
	end
	for _, face in ipairs({ "Left", "Right" }) do
		rect(canvas(f, b.Torso, face), 0.5, 0.14, 1, 0.3, b.Head.Color)
		rect(canvas(f, b.Torso, face), 0.5, 0.5, 0.12, 1, trim)
	end
	-- matching shorts
	if b.Lower then
		b.Lower.Color = c
		local model = b.Torso.Parent
		for _, n in ipairs({ "LeftUpperLeg", "RightUpperLeg" }) do
			local leg = model:FindFirstChild(n)
			if leg then
				leg.Color = c
				rect(canvas(f, leg, "Left"), 0.5, 0.5, 0.15, 1, trim)
				rect(canvas(f, leg, "Right"), 0.5, 0.5, 0.15, 1, trim)
			end
		end
		for _, n in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
			local leg = model:FindFirstChild(n)
			if leg then
				leg.Color = b.Head.Color
			end
		end
	end
end
function PAINTED.Overalls(f, b, c)
	c = c or rgb(60, 90, 140)
	local front = canvas(f, b.Torso, "Front")
	rect(front, 0.5, 0.72, 0.6, 0.56, c)
	rect(front, 0.5, 0.62, 0.24, 0.14, c:Lerp(BLACK, 0.2))
	for _, x in ipairs({ 0.25, 0.75 }) do
		rect(front, x, 0.25, 0.12, 0.5, c)
		rect(front, x, 0.45, 0.07, 0.07, SILVER, 0, 1)
	end
	local back = canvas(f, b.Torso, "Back")
	rect(back, 0.35, 0.3, 0.12, 0.7, c, 20)
	rect(back, 0.65, 0.3, 0.12, 0.7, c, -20)
	if b.Lower then
		b.Lower.Color = c
	end
end
CitizenLook.PAINTED = PAINTED

-- the outfit pieces that a real 3D (layered) garment replaces
local CLOTHING_ITEMS = { Jersey = true, Tee = true, Polo = true, Hoodie = true, Jacket = true, Stripes = true, Sweater = true, Dress = true, Blazer = true, Flannel = true, Puffer = true, Varsity = true, Tank = true, Skirt = true, Overalls = true, Cardigan = true, Vest = true }

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
	local sculpt = r15 and Config.SCULPTED_BODIES == true -- (off: opt in with Config.SCULPTED_BODIES = true)
	if sculpt then
		local armT, legT = tapers(look)
		for _, name in ipairs(LIMBS) do
			local p = model:FindFirstChild(name)
			if p then
				local t = if string.find(name, "Arm") then armT else legT
				if string.find(name, "Lower") then
					t *= if string.find(name, "Arm") then 0.88 else 0.88
				end
				p:SetAttribute("Sculpted", true)
				p:SetAttribute("SculptD", math.min(p.Size.X, p.Size.Z) * t)
			end
		end
	end
	if body.Head and body.Torso then
		if not options.RealHair then
			hair(folder, body, look.Hair, look.HairColor)
		end
		for _, item in ipairs(look.Items) do
			local name, color = parseItem(item)
			local build = ITEMS[name]
			if options.RealClothes and CLOTHING_ITEMS[name] then
				build = nil
			elseif PAINTED[name] and Config.PAINTED_CLOTHES ~= false then
				build = PAINTED[name]
			end
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
	if sculpt and body.Head and body.Torso then
		CitizenLook.Sculpt(model, folder, look)
	end
	-- the drawn face (R15 heads; every client animates it)
	if r15 and body.Head and not options.KeepFace then
		Faces.Build(body.Head, look.Face, look.Skin)
		model:SetAttribute("Expression", model:GetAttribute("Expression") or "neutral")
	end
	model:SetAttribute("Look", look.Hair .. (if look.Job then " / " .. look.Job else ""))
	model:SetAttribute("Height", look.Height)
	return look
end

-- Smoother, more human body shapes: Roblox's free classic "Man" and "Woman"
-- body packages (rounded shoulders and limbs instead of blocks). The default
-- head stays, so the drawn faces fit. Override with Config.CITIZEN_BODIES, or
-- set Config.SMOOTH_BODIES = false for the classic blocky bodies.
CitizenLook.BODIES = Config.CITIZEN_BODIES or {
	Man = { Torso = 86500008, LeftArm = 86500036, RightArm = 86500054, LeftLeg = 86500064, RightLeg = 86500078 },
	Woman = { Torso = 86499666, LeftArm = 86499698, RightArm = 86499716, LeftLeg = 86499753, RightLeg = 86499793 },
}
local R15_PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local bodyWorks = {} -- [package] = false once it failed to load (then everyone uses the default body)

--------------------------------------------------------------------------------
-- Realistic bodies from the Roblox catalog. Put body bundle ids (the number in
-- a roblox.com/bundles/<id>/... link) in Config.CITIZEN_BUNDLES = { Man = {...},
-- Woman = {...} }. Each citizen always gets the same one of the list (so the
-- town has a mix of bodies). Bundles with a 3D head (a "DynamicHead") give the
-- citizen that head and its own animated face instead of the drawn one
-- (Config.BUNDLE_HEADS = false keeps the drawn faces).
--------------------------------------------------------------------------------
local AssetService = game:GetService("AssetService")
local BODY_SLOTS = { Torso = "Torso", LeftArm = "LeftArm", RightArm = "RightArm", LeftLeg = "LeftLeg", RightLeg = "RightLeg", DynamicHead = "Head", Head = "Head" }
local bundleCache = {} -- [id] = { slot = assetId } or false
local function bundleParts(id)
	if bundleCache[id] ~= nil then
		return bundleCache[id]
	end
	local ok, info = pcall(AssetService.GetBundleDetailsAsync, AssetService, id)
	local parts = false
	if ok and type(info) == "table" and type(info.Items) == "table" then
		parts = {}
		for _, item in ipairs(info.Items) do
			local slot = BODY_SLOTS[tostring(item.AssetType or "")]
			if slot and item.Type == "Asset" then
				parts[slot] = item.Id
			end
		end
		if not parts.Torso then
			parts = false
		end
	end
	if not parts then
		warn("[CitizenLook] body bundle " .. tostring(id) .. " couldn't be used" .. (if ok then " (no body parts in it)" else ": " .. tostring(info)))
	end
	bundleCache[id] = parts
	return parts
end
CitizenLook.BundleParts = bundleParts

local function complete(model)
	if not model then
		return false
	end
	for _, name in ipairs(R15_PARTS) do
		local part = model:FindFirstChild(name)
		if not part or not part:IsA("BasePart") then
			return false
		end
	end
	return model:FindFirstChildOfClass("Humanoid") ~= nil
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
	description.WidthScale = math.clamp(look.Width, 0.7, 1)
	description.DepthScale = math.clamp(look.Depth or look.Width, 0.7, 1)
	description.HeightScale = 1
	-- realistic proportions: taller, longer-limbed and narrower than the stubby
	-- default body (slim builds are the most slender, heavy builds the widest)
	-- the classic Roblox body (like the hoops games): standard proportions, with
	-- builds made from height and width (Config.REALISTIC_PROPORTIONS = true
	-- gives taller, slimmer Rthro-like proportions instead)
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	if Config.REALISTIC_PROPORTIONS == true and look.Age >= 13 then
		description.BodyTypeScale = if look.Feminine then 0.75 else 0.65
		description.ProportionScale = ({ slim = 1, average = 0.6, athletic = 0.35, curvy = 0.2, heavy = 0, stocky = 0, muscular = 0.1 })[look.Build or "average"] or 0.5
	end
	local model
	local package = if look.Feminine then "Woman" else "Man"
	-- catalog hair and 3D (layered) clothes, if the city has some
	local seed = hash(tostring(field(citizen or {}, "Name", "name") or ""))
	local hairList = Config.CITIZEN_HAIR and Config.CITIZEN_HAIR[package]
	if hairList and #hairList > 0 and look.Hair ~= "bald" and look.Age >= 3 then
		description.HairAccessory = tostring(hairList[seed % #hairList + 1])
		look.RealHair = true
	end
	local clothes = Config.CITIZEN_CLOTHES
	if clothes and #clothes > 0 and look.Age >= 13 and not look.Job then
		local c = clothes[seed // 7 % #clothes + 1]
		pcall(function()
			description:SetAccessories({ { Order = 1, AssetId = c.AssetId or c[1], AccessoryType = c.AccessoryType or Enum.AccessoryType[c[2] or "Shirt"], IsLayered = true } }, true)
		end)
		look.RealClothes = true
	end
	-- a catalog body bundle, if the city has some
	local bundles = Config.CITIZEN_BUNDLES and Config.CITIZEN_BUNDLES[package]
	if bundles and #bundles > 0 and look.Age >= 13 then
		local pick = bundles[hash(tostring(field(citizen or {}, "Name", "name") or "")) % #bundles + 1]
		local parts = bundleParts(pick)
		if parts then
			local real = description:Clone()
			for slot, id in pairs(parts) do
				if slot ~= "Head" or Config.BUNDLE_HEADS ~= false then
					real[slot] = id
				end
			end
			local ok, result = pcall(function()
				return Players:CreateHumanoidModelFromDescription(real, Enum.HumanoidRigType.R15)
			end)
			if ok and complete(result) then
				model = result
				look.BundleHead = parts.Head ~= nil and Config.BUNDLE_HEADS ~= false
			elseif ok and result then
				result:Destroy()
			end
		end
	end
	local ids = not model and Config.SMOOTH_BODIES == true and CitizenLook.BODIES[package]
	if ids and not model and bodyWorks[package] ~= false then
		-- try the smooth body; if it can't load, fall back to the default one
		local smooth = description:Clone()
		for slot, id in pairs(ids) do
			smooth[slot] = id
		end
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(smooth, Enum.HumanoidRigType.R15)
		end)
		if ok and complete(result) then
			model = result
			bodyWorks[package] = true
		else
			if ok and result then
				result:Destroy()
			end
			if bodyWorks[package] == nil then
				warn("[CitizenLook] the " .. package .. " body package didn't load; using the default body (" .. tostring(if ok then "missing parts" else result) .. ")")
			end
			bodyWorks[package] = false
		end
	end
	model = model or Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = tostring(field(citizen or {}, "Name", "name") or "Citizen")
	-- kids have bigger heads for their size (so they read as kids, not tiny adults)
	local headScale = if look.Age < 3 then 1.35 elseif look.Age < 9 then 1.25 elseif look.Age < 14 then 1.12 else 1
	if headScale ~= 1 and not look.BundleHead then
		CitizenLook.ScaleHead(model, headScale)
	end
	-- (a real 3D head keeps its own face)
	CitizenLook.Apply(model, citizen, { KeepFace = look.BundleHead, RealHair = look.RealHair, RealClothes = look.RealClothes })
	model:SetAttribute("RealHead", look.BundleHead or nil)
	return model, look
end

-- Makes the head bigger or smaller, keeping it on the neck
function CitizenLook.ScaleHead(model, factor)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	head.Size *= factor
	for _, child in ipairs(head:GetChildren()) do
		if child:IsA("Attachment") then
			child.Position *= factor
		end
	end
	local neck = head:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		neck.C1 = CFrame.new(neck.C1.Position * factor) * neck.C1.Rotation
	end
end

-- the uniform table, so other scripts can add or tweak outfits
CitizenLook.Uniforms = UNIFORMS
CitizenLook.HobbyItems = HOBBY_ITEMS

return CitizenLook
