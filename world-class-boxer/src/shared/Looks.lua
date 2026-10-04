-- Looks: everything about how a boxer looks (face, hair, body frame, attire, gloves).
-- Defines the options, default looks, server-side sanitizing of client input,
-- and deterministic random looks for AI boxers (generated from a seed so the
-- saved world stays small).
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
}
Looks.EyeSliders = {
	{ key = "eyeShape", label = "Eye Shape (round - almond)", min = 0, max = 1 },
	{ key = "eyeSize", label = "Eye Size", min = -1, max = 1 },
	{ key = "eyeDist", label = "Eye Distance", min = -1, max = 1 },
	{ key = "lashes", label = "Eyelashes", min = 0, max = 1 },
}
Looks.SkinSliders = {
	{ key = "freckles", label = "Freckles", min = 0, max = 1 },
	{ key = "moles", label = "Moles", min = 0, max = 3, step = 1 },
	{ key = "scars", label = "Scars", min = 0, max = 3, step = 1 },
	{ key = "acne", label = "Acne", min = 0, max = 1 },
	{ key = "marks", label = "Facial Marks", min = 0, max = 1 },
	{ key = "shine", label = "Sweat Shine", min = 0, max = 1 },
	{ key = "smooth", label = "Skin Smoothness", min = 0, max = 1 },
}

Looks.HairTypes = { "Straight", "Wavy", "Curly", "Kinky", "Coiled" }
Looks.HairStyles = {
	"Bald", "Buzz Cut", "Crew Cut", "Fade", "Low Fade", "Mid Fade", "High Fade", "Afro", "High Top",
	"Short Dreads", "Dreadlocks", "Twists", "Braids", "Cornrows", "Short Curly", "Long Curly", "Messy Hair", "Slick Back",
	"Undercut", "Mohawk", "Caesar Cut", "Long Hair", "Ponytail", "Wolf Cut", "Modern Athlete",
}
Looks.HairSliders = {
	{ key = "length", label = "Hair Length", min = 0, max = 1 },
	{ key = "density", label = "Hair Density", min = 0, max = 1 },
	{ key = "thickness", label = "Hair Thickness", min = 0, max = 1 },
}
Looks.DyePatterns = { "None", "Tips", "Streaks", "Ombre", "Split" }
Looks.BeardStyles = { "None", "Stubble", "Goatee", "Moustache", "Chin Strap", "Short Boxed", "Full Beard" }

Looks.BodySliders = {
	{ key = "arms", label = "Arm Size", min = -1, max = 1 },
	{ key = "chest", label = "Chest Size", min = -1, max = 1 },
	{ key = "shoulders", label = "Shoulder Width", min = -1, max = 1 },
	{ key = "waist", label = "Waist Width", min = -1, max = 1 },
	{ key = "legs", label = "Leg Thickness", min = -1, max = 1 },
	{ key = "neck", label = "Neck Thickness", min = -1, max = 1 },
}

Looks.FaceKeys = {
	"jawWidth", "jawDef", "chin", "cheek", "forehead", "noseWidth", "noseLength", "noseBridge", "lips", "browThick",
	"eyeShape", "eyeSize", "eyeDist", "lashes", "freckles", "moles", "scars", "acne", "marks", "shine", "smooth",
}

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
		},
		hair = {
			style = female and "Ponytail" or "Short Dreads", type = female and "Wavy" or "Coiled",
			length = 0.5, density = 0.7, thickness = 0.5, growth = 0,
			color = rgb(Looks.HairColors[1]), hl = false, hcolor = rgb(Looks.HairColors[5]), dye = "None",
		},
		beard = { style = "None", growth = 0 },
		body = { frame = "Athletic", arms = 0, chest = 0, shoulders = 0, waist = 0, legs = 0, neck = 0 },
		attire = {
			trunks = rgb(Looks.Palette[3]), trim = rgb(Looks.Palette[1]), trunkStyle = "Pro",
			socks = rgb(Looks.Palette[4]), shoes = rgb(Looks.Palette[3]), shoeStyle = "High-Top",
			robe = rgb(Looks.Palette[1]), robeTrim = rgb(Looks.Palette[5]),
			wraps = rgb(Looks.Palette[4]), mouthguard = rgb(Looks.Palette[2]),
		},
		gloves = {
			color = rgb(Looks.Palette[1]), trim = rgb(Looks.Palette[4]), finish = "Leather",
			logo = "None", stitching = "Classic", embName = false, embNick = false,
		},
	}
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

function Looks.Sanitize(input, old)
	input = type(input) == "table" and input or {}
	local base = old or Looks.Defaults(input.gender == 2 and 2 or 1)
	local out = Looks.Defaults(input.gender == 2 and 2 or (base.gender or 1))
	out.gender = input.gender == 2 and 2 or 1
	out.skin = math.floor(num(input.skin, 1, #Looks.SkinTones, base.skin or 5))
	out.height = math.floor(num(input.height, 60, 84, base.height or 70))

	local f, bf = type(input.face) == "table" and input.face or {}, base.face or out.face
	out.face.shape = pick(f.shape, Looks.FaceShapes, bf.shape or "Oval")
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders }) do
		for _, s in ipairs(list) do
			local v = num(f[s.key], s.min, s.max, bf[s.key] or out.face[s.key])
			if s.step then
				v = math.floor(v + 0.5)
			end
			out.face[s.key] = v
		end
	end
	out.face.eyeColor = math.floor(num(f.eyeColor, 1, #Looks.EyeColors, bf.eyeColor or 2))
	out.face.seed = math.floor(num(f.seed, 1, 1000000, bf.seed or 7))

	local h, bh = type(input.hair) == "table" and input.hair or {}, base.hair or out.hair
	out.hair.style = pick(h.style, Looks.HairStyles, bh.style)
	out.hair.type = pick(h.type, Looks.HairTypes, bh.type)
	for _, s in ipairs(Looks.HairSliders) do
		out.hair[s.key] = num(h[s.key], 0, 1, bh[s.key])
	end
	out.hair.growth = num(bh.growth, 0, 1.5, 0) -- growth only changes over time / at the barber
	out.hair.color = color(h.color, bh.color)
	out.hair.hl = h.hl == true
	out.hair.hcolor = color(h.hcolor, bh.hcolor)
	out.hair.dye = pick(h.dye, Looks.DyePatterns, bh.dye or "None")

	local b, bb = type(input.beard) == "table" and input.beard or {}, base.beard or out.beard
	out.beard.style = out.gender == 2 and "None" or pick(b.style, Looks.BeardStyles, bb.style)
	out.beard.growth = num(bb.growth, 0, 1, 0)

	local bo, bbo = type(input.body) == "table" and input.body or {}, base.body or out.body
	local frames = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
	out.body.frame = pick(bo.frame, frames, bbo.frame)
	for _, s in ipairs(Looks.BodySliders) do
		out.body[s.key] = num(bo[s.key], -1, 1, bbo[s.key])
	end

	local a, ba = type(input.attire) == "table" and input.attire or {}, base.attire or out.attire
	for _, k in ipairs({ "trunks", "trim", "socks", "shoes", "robe", "robeTrim", "wraps", "mouthguard" }) do
		out.attire[k] = color(a[k], ba[k])
	end
	out.attire.trunkStyle = pick(a.trunkStyle, { "Classic", "Long", "Striped", "Pro" }, ba.trunkStyle)
	out.attire.shoeStyle = pick(a.shoeStyle, { "Low-Top", "High-Top" }, ba.shoeStyle)

	local g, bg = type(input.gloves) == "table" and input.gloves or {}, base.gloves or out.gloves
	out.gloves.color = color(g.color, bg.color)
	out.gloves.trim = color(g.trim, bg.trim)
	out.gloves.finish = pick(g.finish, { "Leather", "Matte", "Patent", "Metallic" }, bg.finish)
	out.gloves.logo = pick(g.logo, { "None", "Star", "Crown", "Lightning", "Flame", "Skull", "Initials", "Flag" }, bg.logo)
	out.gloves.stitching = pick(g.stitching, { "Classic", "Double", "Contrast", "Gold" }, bg.stitching)
	out.gloves.embName = g.embName == true
	out.gloves.embNick = g.embNick == true
	return out
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
			f[s.key] = s.min + (s.max - s.min) * (0.2 + rng:NextNumber() * 0.6)
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
	app.beard.style = female and "None" or Looks.BeardStyles[rng:NextInteger(1, #Looks.BeardStyles)]
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
	return app
end

-- Muscle development for an AI boxer (0..100 per group) based on career level
function Looks.RandomBuild(seed, frac, age, frame)
	local rng = Random.new(seed + 17)
	local base = 12 + frac * 55 + math.clamp((age or 25) - 20, 0, 10) * 1.5
	local build = {}
	for _, k in ipairs({ "chest", "shoulders", "arms", "back", "legs", "core", "neck" }) do
		build[k] = math.clamp(base + rng:NextNumber(-12, 12), 3, 95)
	end
	local fatBase = (frame == "Heavyweight Build") and 18 or 12
	build.fat = math.clamp(fatBase - frac * 4 + rng:NextNumber(-3, 5), 7, 26)
	return build
end

return Looks
