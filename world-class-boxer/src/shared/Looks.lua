-- Looks: everything about how a boxer looks (face, hair, body frame, attire, gloves).
-- Defines the options, default looks, server-side sanitizing of client input,
-- and deterministic random looks for AI boxers (generated from a seed so the
-- saved world stays small).
-- Slider entries marked v2 were added by the visual overhaul: Looks.Random draws them from a
-- separate Random stream so every existing AI boxer / gym NPC keeps its old face.
local Config = require(script.Parent:WaitForChild("Config"))

local Looks = {}

Looks.SkinTones = {
	{ 246, 216, 192 }, { 240, 204, 172 }, { 232, 188, 154 }, { 224, 172, 129 }, { 206, 150, 108 }, { 186, 128, 88 },
	{ 160, 106, 70 }, { 134, 86, 54 }, { 112, 70, 44 }, { 92, 58, 38 }, { 72, 46, 31 }, { 56, 36, 26 },
}
Looks.HairColors = {
	{ 22, 19, 17 }, { 48, 33, 24 }, { 82, 55, 34 }, { 122, 84, 50 }, { 196, 156, 92 }, { 228, 204, 150 },
	{ 150, 62, 30 }, { 128, 40, 28 }, { 150, 150, 150 }, { 225, 225, 220 }, { 40, 70, 180 }, { 120, 40, 150 },
}
Looks.EyeColors = {
	{ 60, 36, 22 }, { 96, 60, 34 }, { 120, 90, 48 }, { 72, 110, 60 }, { 70, 120, 180 }, { 110, 120, 130 }, { 160, 110, 40 },
}
Looks.EyeColorNames = { "Dark Brown", "Brown", "Hazel", "Green", "Blue", "Gray", "Amber" }
Looks.Palette = { -- attire / glove colors
	{ 200, 25, 30 }, { 25, 60, 200 }, { 20, 20, 20 }, { 240, 240, 240 }, { 230, 180, 30 }, { 20, 140, 60 },
	{ 120, 30, 160 }, { 240, 110, 20 }, { 0, 170, 190 }, { 240, 120, 170 }, { 110, 70, 40 }, { 160, 160, 170 },
}

Looks.FaceShapes = { "Oval", "Square", "Diamond", "Round", "Long", "Heart" }
Looks.FaceSliders = {
	{ key = "jawWidth", label = "Jaw Width", min = -1, max = 1 },
	{ key = "jawDef", label = "Jaw Definition", min = 0, max = 1 },
	{ key = "chin", label = "Chin Size", min = -1, max = 1 },
	{ key = "cheek", label = "Cheekbones", min = -1, max = 1 },
	{ key = "forehead", label = "Forehead Size", min = -1, max = 1 },
	{ key = "noseWidth", label = "Nose Width", min = -1, max = 1 },
	{ key = "noseLength", label = "Nose Length", min = -1, max = 1 },
	{ key = "noseBridge", label = "Nose Bridge", min = -1, max = 1 },
	{ key = "lips", label = "Lip Thickness", min = -1, max = 1 },
	{ key = "browThick", label = "Eyebrow Thickness", min = -1, max = 1 },
	{ key = "browHeight", label = "Brow Height", min = -1, max = 1, v2 = true },
	{ key = "browAngle", label = "Brow Angle", min = -1, max = 1, v2 = true },
	{ key = "cheekFull", label = "Cheek Fullness", min = -1, max = 1, v2 = true },
	{ key = "mouthWidth", label = "Mouth Width", min = -1, max = 1, v2 = true },
	{ key = "chinCleft", label = "Chin Cleft", min = 0, max = 1, v2 = true },
	{ key = "earSize", label = "Ear Size", min = -1, max = 1, v2 = true },
	{ key = "asym", label = "Asymmetry", min = 0, max = 1, v2 = true },
}
Looks.EyeSliders = {
	{ key = "eyeShape", label = "Eye Shape (round - almond)", min = 0, max = 1 },
	{ key = "eyeSize", label = "Eye Size", min = -1, max = 1 },
	{ key = "eyeDist", label = "Eye Distance", min = -1, max = 1 },
	{ key = "lashes", label = "Eyelashes", min = 0, max = 1 },
	{ key = "eyeTilt", label = "Eye Tilt", min = -1, max = 1, v2 = true },
	{ key = "lidHeavy", label = "Hooded Lids", min = 0, max = 1, v2 = true },
}
Looks.SkinSliders = {
	{ key = "freckles", label = "Freckles", min = 0, max = 1 },
	{ key = "moles", label = "Moles", min = 0, max = 3, step = 1 },
	{ key = "scars", label = "Scars", min = 0, max = 3, step = 1 },
	{ key = "acne", label = "Acne", min = 0, max = 1 },
	{ key = "marks", label = "Facial Marks", min = 0, max = 1 },
	{ key = "shine", label = "Sweat Shine", min = 0, max = 1 },
	{ key = "smooth", label = "Skin Smoothness", min = 0, max = 1 },
	{ key = "wrinkles", label = "Wrinkles", min = 0, max = 1, v2 = true },
	{ key = "pores", label = "Skin Texture (pores)", min = 0, max = 1, v2 = true },
}
-- a fighter's wear the player may also choose; fights add more through app.battle (server only)
Looks.WearSliders = {
	{ key = "cauliflower", label = "Cauliflower Ear", min = 0, max = 1, v2 = true },
	{ key = "noseBreak", label = "Broken Nose", min = 0, max = 1, v2 = true },
}
-- v3 (anatomy meshes): skull / face sculpt parameters the mesh heads read. A list of their own (not in
-- FaceSliders) so Looks.Random's legacy and v2 streams never draw them; defaults are neutral.
Looks.SculptSliders = {
	{ key = "skullWidth", label = "Skull Width", min = -1, max = 1, v3 = true },
	{ key = "skullLength", label = "Skull Length", min = -1, max = 1, v3 = true },
	{ key = "crown", label = "Crown Height", min = -1, max = 1, v3 = true },
	{ key = "browRidge", label = "Brow Ridge", min = 0, max = 1, v3 = true },
	{ key = "cheekHeight", label = "Cheekbone Height", min = -1, max = 1, v3 = true },
	{ key = "jawAngle", label = "Jaw Angle (soft - sharp)", min = 0, max = 1, v3 = true },
	{ key = "chinProject", label = "Chin Projection", min = -1, max = 1, v3 = true },
	{ key = "eyeDepth", label = "Eye Depth (deep set)", min = 0, max = 1, v3 = true },
	{ key = "noseTip", label = "Nose Tip (down - up)", min = -1, max = 1, v3 = true },
	{ key = "nostrilFlare", label = "Nostril Flare", min = 0, max = 1, v3 = true },
	{ key = "lipBow", label = "Cupid's Bow", min = 0, max = 1, v3 = true },
}
-- nose shapes (face.noseType); noseWidth / noseLength / noseBridge / noseTip still scale within a type
Looks.NoseTypes = { "Straight", "Roman", "Button", "Snub", "Hawk", "Wide", "Flat", "Nubian", "Greek", "Boxer" }
Looks.Undertones = { "Neutral", "Warm", "Cool", "Olive" }
Looks.BrowStyles = { "Natural", "Straight", "Soft Arch", "High Arch", "Thick", "Thin" }
-- permanent fight scars (app.battle.scars[i].kind)
Looks.ScarKinds = { "brow", "cheek", "nose", "lip", "chin" }

-- Stored hair type ids never change (saves); the UI shows Looks.HairTypeNames in HairTypeOrder.
Looks.HairTypes = { "Straight", "Wavy", "Curly", "Kinky", "Coiled" }
Looks.HairTypeNames = { Straight = "Straight", Wavy = "Wavy", Curly = "Curly", Coiled = "Coily", Kinky = "Afro-textured" }
Looks.HairTypeOrder = { "Straight", "Wavy", "Curly", "Coiled", "Kinky" }
-- display names / other spellings a client may send, mapped to the stored id
Looks.HairTypeAliases = { Coily = "Coiled", Afro = "Kinky", ["Afro-textured"] = "Kinky", ["Afro-Textured"] = "Kinky", Kinky = "Kinky" }
Looks.HairStyles = {
	"Bald", "Buzz Cut", "Crew Cut", "Fade", "Low Fade", "Mid Fade", "High Fade", "Afro", "High Top",
	"Short Dreads", "Dreadlocks", "Twists", "Braids", "Cornrows", "Short Curly", "Long Curly", "Messy Hair", "Slick Back",
	"Undercut", "Mohawk", "Caesar Cut", "Long Hair", "Ponytail", "Wolf Cut", "Modern Athlete",
	-- overhaul additions (append only: ids are saved strings)
	"Taper Fade", "Textured Crop", "Curly Top", "Burst Fade", "360 Waves", "Box Braids",
}
-- closest older style for each new id: a builder without a dedicated branch draws this instead
Looks.HairStyleBase = {
	["Taper Fade"] = "Low Fade", ["Textured Crop"] = "Crew Cut", ["Curly Top"] = "Short Curly",
	["Burst Fade"] = "Mid Fade", ["360 Waves"] = "Buzz Cut", ["Box Braids"] = "Braids",
}
-- grouping for the creator / barber style grids (every style appears exactly once)
Looks.HairStyleGroups = {
	{ name = "Short", styles = { "Bald", "Buzz Cut", "Crew Cut", "Caesar Cut", "360 Waves", "Textured Crop", "Modern Athlete" } },
	{ name = "Fades", styles = { "Fade", "Low Fade", "Mid Fade", "High Fade", "Taper Fade", "Burst Fade", "Undercut", "Mohawk" } },
	{ name = "Curly & Coily", styles = { "Curly Top", "Short Curly", "Long Curly", "Afro", "High Top" } },
	{ name = "Locs & Braids", styles = { "Short Dreads", "Dreadlocks", "Twists", "Braids", "Box Braids", "Cornrows" } },
	{ name = "Long & Styled", styles = { "Messy Hair", "Slick Back", "Long Hair", "Ponytail", "Wolf Cut" } },
}
Looks.HairSliders = {
	{ key = "length", label = "Hair Length", min = 0, max = 1 },
	{ key = "density", label = "Hair Density", min = 0, max = 1 },
	{ key = "thickness", label = "Hair Thickness", min = 0, max = 1 },
}
-- v3 (anatomy meshes): how the strand clumps are built (fine strands .. chunky clumps, flyaways, overall
-- volume, curl cluster size); a separate list so older UIs and Random's streams are unaffected
Looks.HairDetailSliders = {
	{ key = "clump", label = "Strand Clumping (fine - chunky)", min = 0, max = 1 },
	{ key = "frizz", label = "Frizz / Flyaways", min = 0, max = 1 },
	{ key = "volume", label = "Volume", min = -1, max = 1 },
	{ key = "curlSize", label = "Curl Size", min = -1, max = 1 },
}
Looks.DyePatterns = { "None", "Tips", "Streaks", "Ombre", "Split" }
Looks.Hairlines = { "Natural", "Straight", "Widow's Peak", "Receding", "Line-Up" }
Looks.HairParts = { "None", "Left", "Right", "Middle" }
Looks.BeardStyles = {
	"None", "Stubble", "Goatee", "Moustache", "Chin Strap", "Short Boxed", "Full Beard",
	"Circle Beard", "Van Dyke", "Mutton Chops",
}
Looks.BeardStyleBase = { ["Circle Beard"] = "Goatee", ["Van Dyke"] = "Goatee", ["Mutton Chops"] = "Chin Strap" }
Looks.WrapPatterns = { "Solid", "TwoTone", "Flag" }
Looks.TrunkStyles = { "Classic", "Long", "Striped", "Pro" }
Looks.ShoeStyles = { "Low-Top", "High-Top" }
Looks.GloveFinishes = { "Leather", "Matte", "Patent", "Metallic" }
Looks.GloveLogos = { "None", "Star", "Crown", "Lightning", "Flame", "Skull", "Initials", "Flag" }
Looks.GloveStitching = { "Classic", "Double", "Contrast", "Gold" }

-- body frame ids (Config.BodyTypes) and physique choices ("Auto" = classify from the build)
Looks.Frames = {}
for _, bt in ipairs(Config.BodyTypes) do
	table.insert(Looks.Frames, bt.id)
end
Looks.Physiques = { "Auto" }
for _, ph in ipairs(Config.Physiques) do
	table.insert(Looks.Physiques, ph.id)
end

Looks.BodySliders = {
	{ key = "arms", label = "Arm Size", min = -1, max = 1 },
	{ key = "chest", label = "Chest Size", min = -1, max = 1 },
	{ key = "shoulders", label = "Shoulder Width", min = -1, max = 1 },
	{ key = "waist", label = "Waist Width", min = -1, max = 1 },
	{ key = "legs", label = "Leg Thickness", min = -1, max = 1 },
	{ key = "neck", label = "Neck Thickness", min = -1, max = 1 },
}

-- every numeric face key (all slider lists), kept in sync automatically
Looks.FaceKeys = {}
for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders, Looks.WearSliders, Looks.SculptSliders }) do
	for _, sl in ipairs(list) do
		table.insert(Looks.FaceKeys, sl.key)
	end
end

function Looks.HairTypeName(id)
	return Looks.HairTypeNames[id] or tostring(id)
end

local function rgb(t)
	return { t[1], t[2], t[3] }
end

function Looks.Color(c, fallback)
	if type(c) == "table" and type(c[1]) == "number" then
		return Color3.fromRGB(c[1], c[2] or 0, c[3] or 0)
	end
	return fallback or Color3.new(1, 1, 1)
end

function Looks.Defaults(gender)
	local female = gender == 2
	return {
		gender = female and 2 or 1,
		skin = 6,
		height = female and 66 or 70,
		face = {
			shape = "Oval", jawWidth = 0, jawDef = 0.5, chin = 0, cheek = 0, forehead = 0,
			noseWidth = 0, noseLength = 0, noseBridge = 0, lips = female and 0.2 or 0, browThick = female and -0.4 or 0,
			eyeShape = 0.5, eyeSize = 0, eyeDist = 0, lashes = female and 0.8 or 0.2, eyeColor = 2,
			freckles = 0, moles = 0, scars = 0, acne = 0, marks = 0, shine = 0.2, smooth = 0.6, seed = 7,
			browHeight = 0, browAngle = 0, cheekFull = 0, mouthWidth = 0, chinCleft = 0, earSize = 0, asym = 0, -- v2 defaults are neutral so old saves look unchanged
			eyeTilt = 0, lidHeavy = 0, wrinkles = 0, pores = 0, cauliflower = 0, noseBreak = 0,
			undertone = "Neutral", browStyle = "Natural", eyeColor2 = 0, -- 0 = both eyes eyeColor
			-- v3 sculpt (anatomy meshes): neutral
			skullWidth = 0, skullLength = 0, crown = 0, browRidge = female and 0.1 or 0.35, cheekHeight = 0, jawAngle = female and 0.3 or 0.55,
			chinProject = 0, eyeDepth = 0.3, noseTip = 0, nostrilFlare = 0.3, lipBow = female and 0.6 or 0.4, noseType = "Straight",
		},
		hair = {
			style = female and "Ponytail" or "Short Dreads", type = female and "Wavy" or "Coiled",
			length = 0.5, density = 0.7, thickness = 0.5, growth = 0,
			color = rgb(Looks.HairColors[1]), hl = false, hcolor = rgb(Looks.HairColors[5]), dye = "None",
			hairline = "Natural", part = "None",
			clump = 0.5, frizz = 0.3, volume = 0, curlSize = 0, -- v3 strand clump parameters (anatomy meshes)
		},
		beard = { style = "None", growth = 0 }, -- optional beard.color {r,g,b}; missing = hair colour
		body = { frame = "Athletic", arms = 0, chest = 0, shoulders = 0, waist = 0, legs = 0, neck = 0, physique = "Auto" },
		attire = {
			trunks = rgb(Looks.Palette[3]), trim = rgb(Looks.Palette[1]), trunkStyle = "Pro",
			socks = rgb(Looks.Palette[4]), shoes = rgb(Looks.Palette[3]), shoeStyle = "High-Top",
			robe = rgb(Looks.Palette[1]), robeTrim = rgb(Looks.Palette[5]),
			wraps = rgb(Looks.Palette[4]), mouthguard = rgb(Looks.Palette[2]),
			laces = { 240, 240, 240 }, wrapPattern = "Solid",
		},
		gloves = {
			color = rgb(Looks.Palette[1]), trim = rgb(Looks.Palette[4]), finish = "Leather",
			logo = "None", stitching = "Classic", embName = false, embNick = false,
			brand = "Auto", -- "Auto" = the equipped glove's own brand; else a Catalog.Brands id (gloves with custom.brand)
		},
		-- permanent fight wear, written by the server only (Training face healing); never taken from a client
		battle = { scars = {}, ears = 0, nose = 0 },
	}
end

-- Fill fields an older save is missing (in place, never overwrites; idempotent). Returns app.
function Looks.Fill(app)
	if type(app) ~= "table" then
		return Looks.Defaults(1)
	end
	local def = Looks.Defaults(app.gender == 2 and 2 or 1)
	for k, v in pairs(def) do
		if app[k] == nil then
			app[k] = v
		elseif type(v) == "table" and type(app[k]) == "table" and k ~= "battle" then
			for k2, v2 in pairs(v) do
				if app[k][k2] == nil then
					app[k][k2] = v2
				end
			end
		end
	end
	if type(app.battle) ~= "table" then
		app.battle = def.battle
	end
	if type(app.battle.scars) ~= "table" then
		app.battle.scars = {}
	end
	app.battle.ears = tonumber(app.battle.ears) or 0
	app.battle.nose = tonumber(app.battle.nose) or 0
	return app
end

------------------------------------------------------------------------
-- Sanitizing (server side). Accepts untrusted client tables.
------------------------------------------------------------------------
local function num(v, lo, hi, default)
	v = tonumber(v)
	if v == nil or v ~= v then
		return default
	end
	return math.clamp(v, lo, hi)
end

local function pick(v, list, default)
	if type(v) == "string" and table.find(list, v) then
		return v
	end
	return default
end

local function color(v, default)
	if type(v) == "table" and #v >= 3 then
		local out = {}
		for i = 1, 3 do
			out[i] = math.floor(num(v[i], 0, 255, 128))
		end
		return out
	end
	return default
end

-- permanent fight wear: copied from the trusted old look only, clamped
local function battle(b)
	local out = { scars = {}, ears = 0, nose = 0 }
	if type(b) ~= "table" then
		return out
	end
	out.ears = num(b.ears, 0, 1, 0)
	out.nose = num(b.nose, 0, 1, 0)
	if type(b.scars) == "table" then
		for _, sc in ipairs(b.scars) do
			if type(sc) == "table" and #out.scars < 6 then
				table.insert(out.scars, {
					kind = pick(sc.kind, Looks.ScarKinds, "brow"),
					side = (tonumber(sc.side) or 1) < 0 and -1 or 1,
					at = num(sc.at, 0, 1, 0.5),
					size = num(sc.size, 0, 1, 0.5),
				})
			end
		end
	end
	return out
end

local function hairType(v, default)
	if type(v) == "string" then
		v = Looks.HairTypeAliases[v] or v
	end
	return pick(v, Looks.HairTypes, default)
end

-- Builds a clean look from untrusted input. `old` (the saved look) supplies anything the input
-- leaves out and the server-only fields (hair/beard growth, battle wear).
function Looks.Sanitize(input, old)
	input = type(input) == "table" and input or {}
	if type(old) ~= "table" then
		old = nil
	end
	local base = old or Looks.Defaults(input.gender == 2 and 2 or 1)
	local out = Looks.Defaults((input.gender == 2 or base.gender == 2) and 2 or 1)
	out.gender = input.gender == 2 and 2 or 1
	out.skin = math.floor(num(input.skin, 1, #Looks.SkinTones, num(base.skin, 1, #Looks.SkinTones, 5)))
	out.height = math.floor(num(input.height, 60, 84, num(base.height, 60, 84, 70)))

	local f = type(input.face) == "table" and input.face or {}
	local bf = type(base.face) == "table" and base.face or out.face
	out.face.shape = pick(f.shape, Looks.FaceShapes, pick(bf.shape, Looks.FaceShapes, "Oval"))
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders, Looks.WearSliders, Looks.SculptSliders }) do
		for _, sl in ipairs(list) do
			local fallback = num(bf[sl.key], sl.min, sl.max, out.face[sl.key])
			local v = num(f[sl.key], sl.min, sl.max, fallback)
			if sl.step then
				v = math.floor(v + 0.5)
			end
			out.face[sl.key] = v
		end
	end
	out.face.eyeColor = math.floor(num(f.eyeColor, 1, #Looks.EyeColors, num(bf.eyeColor, 1, #Looks.EyeColors, 2)))
	out.face.eyeColor2 = math.floor(num(f.eyeColor2, 0, #Looks.EyeColors, num(bf.eyeColor2, 0, #Looks.EyeColors, 0)))
	out.face.seed = math.floor(num(f.seed, 1, 1000000, num(bf.seed, 1, 1000000, 7)))
	out.face.undertone = pick(f.undertone, Looks.Undertones, pick(bf.undertone, Looks.Undertones, out.face.undertone))
	out.face.browStyle = pick(f.browStyle, Looks.BrowStyles, pick(bf.browStyle, Looks.BrowStyles, out.face.browStyle))
	out.face.noseType = pick(f.noseType, Looks.NoseTypes, pick(bf.noseType, Looks.NoseTypes, out.face.noseType))

	local h = type(input.hair) == "table" and input.hair or {}
	local bh = type(base.hair) == "table" and base.hair or out.hair
	out.hair.style = pick(h.style, Looks.HairStyles, pick(bh.style, Looks.HairStyles, out.hair.style))
	out.hair.type = hairType(h.type, hairType(bh.type, out.hair.type))
	for _, sl in ipairs(Looks.HairSliders) do
		out.hair[sl.key] = num(h[sl.key], 0, 1, num(bh[sl.key], 0, 1, out.hair[sl.key]))
	end
	for _, sl in ipairs(Looks.HairDetailSliders) do
		out.hair[sl.key] = num(h[sl.key], sl.min, sl.max, num(bh[sl.key], sl.min, sl.max, out.hair[sl.key]))
	end
	out.hair.growth = num(bh.growth, 0, 1.5, 0) -- growth only changes over time / at the barber
	out.hair.color = color(h.color, color(bh.color, out.hair.color))
	out.hair.hl = h.hl == true
	out.hair.hcolor = color(h.hcolor, color(bh.hcolor, out.hair.hcolor))
	out.hair.dye = pick(h.dye, Looks.DyePatterns, pick(bh.dye, Looks.DyePatterns, "None"))
	out.hair.hairline = pick(h.hairline, Looks.Hairlines, pick(bh.hairline, Looks.Hairlines, "Natural"))
	out.hair.part = pick(h.part, Looks.HairParts, pick(bh.part, Looks.HairParts, "None"))

	local b = type(input.beard) == "table" and input.beard or {}
	local bb = type(base.beard) == "table" and base.beard or out.beard
	out.beard.style = out.gender == 2 and "None" or pick(b.style, Looks.BeardStyles, pick(bb.style, Looks.BeardStyles, "None"))
	out.beard.growth = num(bb.growth, 0, 1, 0)
	out.beard.color = color(b.color, color(bb.color, nil)) -- nil = use the hair colour

	local bo = type(input.body) == "table" and input.body or {}
	local bbo = type(base.body) == "table" and base.body or out.body
	out.body.frame = pick(bo.frame, Looks.Frames, pick(bbo.frame, Looks.Frames, "Athletic"))
	for _, sl in ipairs(Looks.BodySliders) do
		out.body[sl.key] = num(bo[sl.key], -1, 1, num(bbo[sl.key], -1, 1, 0))
	end
	out.body.physique = pick(bo.physique, Looks.Physiques, pick(bbo.physique, Looks.Physiques, "Auto"))

	local a = type(input.attire) == "table" and input.attire or {}
	local ba = type(base.attire) == "table" and base.attire or out.attire
	for _, k in ipairs({ "trunks", "trim", "socks", "shoes", "robe", "robeTrim", "wraps", "mouthguard", "laces" }) do
		out.attire[k] = color(a[k], color(ba[k], out.attire[k]))
	end
	out.attire.trunkStyle = pick(a.trunkStyle, Looks.TrunkStyles, pick(ba.trunkStyle, Looks.TrunkStyles, out.attire.trunkStyle))
	out.attire.shoeStyle = pick(a.shoeStyle, Looks.ShoeStyles, pick(ba.shoeStyle, Looks.ShoeStyles, out.attire.shoeStyle))
	out.attire.wrapPattern = pick(a.wrapPattern, Looks.WrapPatterns, pick(ba.wrapPattern, Looks.WrapPatterns, "Solid"))

	local g = type(input.gloves) == "table" and input.gloves or {}
	local bg = type(base.gloves) == "table" and base.gloves or out.gloves
	out.gloves.color = color(g.color, color(bg.color, out.gloves.color))
	out.gloves.trim = color(g.trim, color(bg.trim, out.gloves.trim))
	out.gloves.finish = pick(g.finish, Looks.GloveFinishes, pick(bg.finish, Looks.GloveFinishes, "Leather"))
	out.gloves.logo = pick(g.logo, Looks.GloveLogos, pick(bg.logo, Looks.GloveLogos, "None"))
	out.gloves.stitching = pick(g.stitching, Looks.GloveStitching, pick(bg.stitching, Looks.GloveStitching, "Classic"))
	out.gloves.embName = g.embName == true
	out.gloves.embNick = g.embNick == true
	-- brand override: a short id; the Builder ignores ids that are not in Catalog.Brands
	local brand = type(g.brand) == "string" and g.brand or (type(bg.brand) == "string" and bg.brand or "Auto")
	out.gloves.brand = (#brand <= 24 and brand:match("^[%w]+$")) and brand or "Auto"

	out.battle = battle(old and old.battle)
	return out
end

-- Barber price for changing `old` to `new` (both sanitized looks). Shared so the barber UI
-- and the server charge the same.
local COMPLEX = { Dreadlocks = 120, ["Short Dreads"] = 90, Twists = 90, Braids = 120, ["Box Braids"] = 140, Cornrows = 100 }
local FADES = { Fade = true, ["Low Fade"] = true, ["Mid Fade"] = true, ["High Fade"] = true, ["Taper Fade"] = true, ["Burst Fade"] = true }
local function sameColor(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
function Looks.BarberPrice(old, new)
	local price = 30
	local h1, h2 = old.hair or {}, new.hair or {}
	if h2.hl ~= h1.hl or h2.dye ~= h1.dye or ((h2.hl or h2.dye ~= "None") and not sameColor(h2.hcolor, h1.hcolor)) then
		price += 60
	end
	if not sameColor(h2.color, h1.color) then
		price += 40
	end
	if h2.style ~= h1.style then
		price += COMPLEX[h2.style] or (FADES[h2.style] and 10 or 0)
	end
	if h2.hairline ~= h1.hairline and h2.hairline == "Line-Up" then
		price += 15
	end
	local b1, b2 = old.beard or {}, new.beard or {}
	if b2.style ~= b1.style and b2.style ~= "None" then
		price += 15
	end
	if not sameColor(b2.color, b1.color) and b2.color ~= nil then
		price += 20
	end
	return price
end

------------------------------------------------------------------------
-- Random looks (AI boxers, gym members). Deterministic from a seed.
------------------------------------------------------------------------
local maleStyles = {
	"Bald", "Buzz Cut", "Crew Cut", "Fade", "Low Fade", "Mid Fade", "High Fade", "Afro", "High Top", "Dreadlocks",
	"Twists", "Braids", "Cornrows", "Short Curly", "Messy Hair", "Slick Back", "Undercut", "Mohawk", "Caesar Cut",
	"Wolf Cut", "Modern Athlete", "Long Curly", "Long Hair", "Ponytail",
}
local femaleStyles = { "Ponytail", "Braids", "Cornrows", "Long Hair", "Long Curly", "Afro", "Twists", "Slick Back", "Undercut", "Dreadlocks", "Short Curly" }
-- overhaul styles, swapped in for some AI boxers through a separate stream (seed + 77)
local newMaleStyles = { "Taper Fade", "Textured Crop", "Curly Top", "Burst Fade", "360 Waves", "Box Braids" }
local newFemaleStyles = { "Box Braids", "Curly Top", "Textured Crop", "Taper Fade" }
local coilyNew = { ["Curly Top"] = true, ["360 Waves"] = true, ["Box Braids"] = true }
-- the beard list before the overhaul: Random must keep drawing from exactly these
local legacyBeards = { "None", "Stubble", "Goatee", "Moustache", "Chin Strap", "Short Boxed", "Full Beard" }
-- AI ring personality (Config.Archetypes id) -> physique archetype
Looks.PhysiqueForArchetype = {
	Pressure = "PowerPuncher", KO = "PowerPuncher", Counter = "LeanTechnical", Technician = "LeanTechnical", Defensive = "LeanTechnical",
}

-- opts: { class = weight class index, age, veteran = bool, height, archetype = Config.Archetypes id,
--         champion = bool, fights = career bouts }. New traits come from Random(seed + 101)
-- so faces generated before the overhaul stay the same.
function Looks.Random(seed, gender, opts)
	opts = opts or {}
	local rng = Random.new(seed)
	local female = gender == 2
	local app = Looks.Defaults(gender)
	app.skin = rng:NextInteger(1, #Looks.SkinTones)
	app.height = opts.height or (female and rng:NextInteger(60, 70) or rng:NextInteger(64, 76))
	local f = app.face
	f.shape = Looks.FaceShapes[rng:NextInteger(1, #Looks.FaceShapes)]
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders }) do
		for _, s in ipairs(list) do
			if not s.v2 then
				f[s.key] = s.min + (s.max - s.min) * (0.2 + rng:NextNumber() * 0.6)
			end
		end
	end
	if female then
		f.lashes = 0.6 + rng:NextNumber() * 0.4
		f.browThick = -0.6 + rng:NextNumber() * 0.5
		f.jawWidth = -0.6 + rng:NextNumber() * 0.5
	end
	f.eyeColor = (app.skin >= 6 and rng:NextNumber() < 0.85) and rng:NextInteger(1, 2) or rng:NextInteger(1, #Looks.EyeColors)
	f.freckles = rng:NextNumber() < 0.15 and rng:NextNumber() or 0
	f.moles = rng:NextNumber() < 0.3 and rng:NextInteger(1, 2) or 0
	f.scars = (opts.veteran and rng:NextNumber() < 0.6) and rng:NextInteger(1, 3) or (rng:NextNumber() < 0.15 and 1 or 0)
	f.acne = rng:NextNumber() < 0.1 and rng:NextNumber() * 0.6 or 0
	f.marks = rng:NextNumber() < 0.08 and rng:NextNumber() or 0
	f.shine = rng:NextNumber() * 0.4
	f.smooth = rng:NextNumber()
	f.seed = rng:NextInteger(1, 1000000)

	local h = app.hair
	local styles = female and femaleStyles or maleStyles
	h.style = styles[rng:NextInteger(1, #styles)]
	local curlyStyles = { Afro = true, ["High Top"] = true, Dreadlocks = true, Twists = true, ["Short Curly"] = true, ["Long Curly"] = true }
	if curlyStyles[h.style] then
		h.type = ({ "Curly", "Kinky", "Coiled" })[rng:NextInteger(1, 3)]
	else
		h.type = Looks.HairTypes[rng:NextInteger(1, #Looks.HairTypes)]
	end
	h.length = rng:NextNumber()
	h.density = 0.4 + rng:NextNumber() * 0.6
	h.thickness = rng:NextNumber()
	local hc = Looks.HairColors[(opts.age or 25) > 34 and rng:NextNumber() < 0.4 and 9 or rng:NextInteger(1, 8)]
	if app.skin >= 7 and rng:NextNumber() < 0.8 then
		hc = Looks.HairColors[rng:NextInteger(1, 2)]
	end
	h.color = rgb(hc)
	h.hl = rng:NextNumber() < 0.12
	h.hcolor = rgb(Looks.HairColors[rng:NextInteger(5, 12)])
	h.dye = h.hl and Looks.DyePatterns[rng:NextInteger(2, #Looks.DyePatterns)] or "None"
	app.beard.style = female and "None" or legacyBeards[rng:NextInteger(1, #legacyBeards)]
	app.beard.growth = rng:NextNumber()

	local frames = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
	local fi = rng:NextInteger(1, 3)
	if (opts.class or 5) >= 8 then
		fi = rng:NextInteger(3, 5)
	elseif (opts.class or 5) >= 6 then
		fi = rng:NextInteger(2, 4)
	end
	app.body.frame = frames[fi]
	for _, s in ipairs(Looks.BodySliders) do
		app.body[s.key] = rng:NextNumber() * 1.4 - 0.7
	end

	local function pal()
		return rgb(Looks.Palette[rng:NextInteger(1, #Looks.Palette)])
	end
	app.attire.trunks = pal()
	app.attire.trim = pal()
	app.attire.trunkStyle = ({ "Classic", "Long", "Striped", "Pro" })[rng:NextInteger(1, 4)]
	app.attire.socks = rng:NextNumber() < 0.6 and rgb(Looks.Palette[4]) or pal()
	app.attire.shoes = rng:NextNumber() < 0.5 and rgb(Looks.Palette[3]) or pal()
	app.attire.shoeStyle = rng:NextNumber() < 0.7 and "High-Top" or "Low-Top"
	app.attire.robe = app.attire.trunks
	app.attire.robeTrim = pal()
	app.attire.mouthguard = pal()
	app.gloves.color = rng:NextNumber() < 0.6 and app.attire.trunks or pal()
	app.gloves.trim = pal()
	app.gloves.finish = ({ "Leather", "Matte", "Patent" })[rng:NextInteger(1, 3)]
	app.gloves.logo = rng:NextNumber() < 0.3 and ({ "Star", "Crown", "Lightning", "Flame", "Skull" })[rng:NextInteger(1, 5)] or "None"
	app.gloves.stitching = ({ "Classic", "Double", "Contrast" })[rng:NextInteger(1, 3)]

	-- overhaul traits (separate streams: never shift the draws above)
	local r2 = Random.new(seed + 101)
	local age = opts.age or 25
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders }) do
		for _, s in ipairs(list) do
			if s.v2 then
				f[s.key] = s.min + (s.max - s.min) * (0.1 + r2:NextNumber() * 0.8)
			end
		end
	end
	f.asym = 0.05 + r2:NextNumber() * 0.45
	f.chinCleft = r2:NextNumber() < 0.2 and r2:NextNumber() or 0
	f.lidHeavy = r2:NextNumber() * 0.6
	if female then
		f.browAngle = 0.1 + r2:NextNumber() * 0.5
		f.earSize = -0.5 + r2:NextNumber() * 0.5
	end
	f.wrinkles = math.clamp((age - 27) / 25, 0, 1) * (0.5 + 0.5 * r2:NextNumber()) * (female and 0.8 or 1)
	f.pores = 0.15 + r2:NextNumber() * 0.6
	f.undertone = Looks.Undertones[r2:NextInteger(1, #Looks.Undertones)]
	f.browStyle = female and ({ "Soft Arch", "High Arch", "Thin", "Natural" })[r2:NextInteger(1, 4)]
		or ({ "Natural", "Straight", "Thick", "Natural" })[r2:NextInteger(1, 4)]
	f.eyeColor2 = r2:NextNumber() < 0.02 and r2:NextInteger(1, #Looks.EyeColors) or 0
	h.hairline = female and "Natural" or ({ "Natural", "Natural", "Straight", "Line-Up", "Widow's Peak" })[r2:NextInteger(1, 5)]
	if not female and age > 33 and r2:NextNumber() < 0.35 then
		h.hairline = "Receding"
	end
	h.part = ({ "None", "None", "Left", "Right", "Middle" })[r2:NextInteger(1, 5)]
	if not female and r2:NextNumber() < 0.12 then
		app.beard.style = ({ "Circle Beard", "Van Dyke", "Mutton Chops" })[r2:NextInteger(1, 3)]
	end
	-- boxer wear: veterans carry cauliflower ears, flattened noses and old scars
	local wear = opts.veteran and 1 or math.clamp(((opts.fights or 0) - 10) / 40, 0, 0.5)
	local battle = { scars = {}, ears = 0, nose = 0 }
	if r2:NextNumber() < 0.5 * wear + 0.04 then
		battle.ears = 0.2 + r2:NextNumber() * 0.7 * math.max(wear, 0.3)
	end
	if r2:NextNumber() < 0.55 * wear + 0.05 then
		battle.nose = 0.15 + r2:NextNumber() * 0.7 * math.max(wear, 0.3)
	end
	for _ = 1, (r2:NextNumber() < 0.7 * wear) and r2:NextInteger(1, 3) or 0 do
		table.insert(battle.scars, {
			kind = Looks.ScarKinds[r2:NextInteger(1, #Looks.ScarKinds)], side = r2:NextNumber() < 0.5 and -1 or 1,
			at = r2:NextNumber(), size = 0.3 + r2:NextNumber() * 0.7,
		})
	end
	app.battle = battle
	-- physique archetype
	local ph = opts.champion and "EliteChampion" or Looks.PhysiqueForArchetype[opts.archetype or ""]
	if (opts.class or 5) >= 8 and not opts.champion then
		ph = "Heavyweight"
	end
	if not ph then
		local frame = app.body.frame
		local options = (frame == "Lean" or frame == "Athletic") and { "LeanTechnical", "Balanced", "Balanced" }
			or { "PowerPuncher", "Balanced", "PowerPuncher" }
		ph = options[r2:NextInteger(1, #options)]
	end
	-- only AI callers pin a physique: a player's random look (Creator, no opts) stays "Auto" so the
	-- body follows their training. The r2 draws above still run, so later draws are unchanged.
	app.body.physique = (opts.archetype or opts.champion or opts.class) and ph or "Auto"
	-- some AI boxers wear the newer cuts
	local r3 = Random.new(seed + 77)
	if r3:NextNumber() < 0.25 then
		local pool = female and newFemaleStyles or newMaleStyles
		h.style = pool[r3:NextInteger(1, #pool)]
		if coilyNew[h.style] then
			h.type = ({ "Curly", "Kinky", "Coiled" })[r3:NextInteger(1, 3)]
		end
	end
	-- v3 sculpt + strand traits (anatomy meshes): their own stream, so every older trait is unchanged
	local r4 = Random.new(seed + 131)
	for _, s in ipairs(Looks.SculptSliders) do
		f[s.key] = s.min + (s.max - s.min) * (0.15 + r4:NextNumber() * 0.7)
	end
	if female then
		f.browRidge *= 0.4
		f.jawAngle *= 0.7
		f.lipBow = 0.4 + r4:NextNumber() * 0.5
	end
	-- boxers' noses: veterans drift toward flat / boxer noses
	local noses = { "Straight", "Straight", "Roman", "Button", "Snub", "Hawk", "Wide", "Flat", "Nubian", "Greek" }
	f.noseType = noses[r4:NextInteger(1, #noses)]
	if (battle.nose or 0) > 0.4 and r4:NextNumber() < 0.6 then
		f.noseType = "Boxer"
	end
	h.clump = 0.25 + r4:NextNumber() * 0.6
	h.frizz = r4:NextNumber() * 0.6
	h.volume = -0.4 + r4:NextNumber() * 0.8
	h.curlSize = -0.6 + r4:NextNumber() * 1.2
	return app
end

-- Muscle development for an AI boxer (0..100 per group plus every sub-muscle part) based on
-- career level. physiqueId (optional, a Config.Physiques id) biases the parts and body fat.
function Looks.RandomBuild(seed, frac, age, frame, physiqueId)
	local rng = Random.new(seed + 17)
	local base = 12 + frac * 55 + math.clamp((age or 25) - 20, 0, 10) * 1.5
	local build = {}
	for _, k in ipairs({ "chest", "shoulders", "arms", "back", "legs", "core", "neck" }) do
		build[k] = math.clamp(base + rng:NextNumber(-12, 12), 3, 95)
	end
	local fatBase = (frame == "Heavyweight Build") and 18 or 12
	build.fat = math.clamp(fatBase - frac * 4 + rng:NextNumber(-3, 5), 7, 26)
	-- sub-muscles: per-part variety that averages back to the group, then the physique bias
	local r2 = Random.new(seed + 29)
	for _, g in ipairs(Config.MuscleKeys) do
		local parts = Config.MuscleGroupParts[g]
		local sum = 0
		for _, p in ipairs(parts) do
			build[p.id] = build[g] * (1 + r2:NextNumber(-0.12, 0.12))
			sum += p.share * build[p.id]
		end
		local delta = build[g] - sum
		for _, p in ipairs(parts) do
			build[p.id] += delta
		end
	end
	local ph = physiqueId and Config.FindById(Config.Physiques, physiqueId)
	if ph then
		local k = 0.4 + 0.6 * frac
		for id, add in pairs(ph.partBias or {}) do
			if build[id] then
				build[id] += add * k
			end
		end
		build.fat = math.clamp(build.fat + (ph.fatBias or 0), 7, 28)
	end
	for _, p in ipairs(Config.MuscleParts) do
		build[p.id] = math.clamp(build[p.id], 1, 120)
	end
	Config.SyncGroups(build)
	return build
end

return Looks
