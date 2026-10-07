-- LookKit: the look editors' shared parts (Creator, barber): plain-word readouts, short labels and
-- one-line hints for every look slider, the defaults their reset buttons and notches use, colour names,
-- face / gear presets, and small frame-drawn glyphs (hairstyle, face shape, build, kit) for the
-- preset grids. Client-only and data-only apart from the glyph builders; nothing here is saved.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme

local LookKit = {}

------------------------------------------------------------------------
-- Colour names (same order as the Looks palettes)
------------------------------------------------------------------------
LookKit.SkinNames = { "Porcelain", "Ivory", "Fair", "Light", "Beige", "Tan", "Golden", "Brown", "Chestnut", "Dark brown", "Espresso", "Deep" }
LookKit.HairColorNames = { "Black", "Dark brown", "Brown", "Light brown", "Dark blonde", "Blonde", "Auburn", "Red", "Grey", "White", "Blue", "Purple" }
LookKit.PaletteNames = { "Red", "Blue", "Black", "White", "Gold", "Green", "Purple", "Orange", "Teal", "Pink", "Brown", "Silver" }

------------------------------------------------------------------------
-- Slider words
------------------------------------------------------------------------
-- -1..1 sliders: { low, high } -> Very low / Low / Average / High / Very high
local SYM = {
	jawWidth = { "Narrow", "Wide" }, chin = { "Small", "Large" }, cheek = { "Flat", "Prominent" }, forehead = { "Short", "Tall" },
	noseWidth = { "Narrow", "Wide" }, noseLength = { "Short", "Long" }, noseBridge = { "Low", "High" }, lips = { "Thin", "Full" },
	browThick = { "Thin", "Thick" }, browHeight = { "Low", "High" }, browAngle = { "Sloped down", "Sloped up" }, cheekFull = { "Hollow", "Full" },
	mouthWidth = { "Narrow", "Wide" }, earSize = { "Small", "Large" }, eyeSize = { "Small", "Large" }, eyeDist = { "Close-set", "Wide-set" },
	eyeTilt = { "Down", "Up" }, skullWidth = { "Narrow", "Wide" }, skullLength = { "Short", "Long" }, crown = { "Low", "High" },
	cheekHeight = { "Low", "High" }, chinProject = { "Receding", "Strong" }, noseTip = { "Drooping", "Upturned" },
	volume = { "Flat", "Full" }, curlSize = { "Tight", "Loose" },
	arms = { "Slim", "Big" }, chest = { "Narrow", "Broad" }, shoulders = { "Narrow", "Broad" }, waist = { "Narrow", "Wide" },
	legs = { "Slim", "Thick" }, neck = { "Slim", "Thick" },
}
-- 0..1 sliders between two looks
local SPAN = { eyeShape = { "Round", "Almond" }, jawAngle = { "Soft", "Sharp" }, clump = { "Fine", "Chunky" } }
-- 0..1 sliders with their own five words (evenly spread)
local LIST = {
	length = { "Very short", "Short", "Medium", "Long", "Very long" },
	density = { "Sparse", "Thin", "Medium", "Thick", "Very thick" },
	thickness = { "Very fine", "Fine", "Medium", "Coarse", "Very coarse" },
	smooth = { "Rough", "Textured", "Normal", "Smooth", "Flawless" },
	jawDef = { "Soft", "Slight", "Defined", "Strong", "Chiselled" },
}
local COUNT = { "None", "One", "Two", "Three" }

local function lower(s)
	return s:sub(1, 1):lower() .. s:sub(2)
end

-- words(key, min, max) -> fn(v) for UI.Slider opts.words (nil: the number alone)
function LookKit.Words(key, min, max)
	local sym, span, list = SYM[key], SPAN[key], LIST[key]
	if sym then
		local vlo, vhi = "Very " .. lower(sym[1]), "Very " .. lower(sym[2])
		return function(v)
			return v <= -0.6 and vlo or (v <= -0.2 and sym[1] or (v < 0.2 and "Average" or (v < 0.6 and sym[2] or vhi)))
		end
	elseif span then
		local slo, shi = "Slightly " .. lower(span[1]), "Slightly " .. lower(span[2])
		return function(v)
			return v < 0.2 and span[1] or (v < 0.4 and slo or (v <= 0.6 and "In between" or (v < 0.8 and shi or span[2])))
		end
	elseif list then
		return list
	elseif min == 0 and max == 3 then
		return function(v)
			return COUNT[math.clamp(math.floor(v + 0.5), 0, 3) + 1]
		end
	elseif min == 0 and max == 1 then
		return function(v)
			return v < 0.04 and "None" or (v < 0.3 and "Light" or (v < 0.6 and "Medium" or (v < 0.85 and "Strong" or "Max")))
		end
	elseif min == -1 and max == 1 then
		return function(v)
			return v <= -0.6 and "Much less" or (v <= -0.2 and "Less" or (v < 0.2 and "Average" or (v < 0.6 and "More" or "Much more")))
		end
	end
	return nil
end

-- the number beside the words: signed for -1..1, a percentage for 0..1, the count for steps
function LookKit.Num(min, max, step)
	if step and step >= 1 then
		return function()
			return ""
		end
	elseif min < 0 then
		return function(v)
			return string.format("%+d", math.floor(v * 100 + (v >= 0 and 0.5 or -0.5)))
		end
	end
	return function(v)
		return string.format("%d%%", math.floor((v - min) / (max - min) * 100 + 0.5))
	end
end

-- shorter labels where the Looks label spells out its ends (the words now say it)
local LABELS = {
	eyeShape = "Eye Shape", jawAngle = "Jaw Angle", eyeDepth = "Deep-set Eyes", noseTip = "Nose Tip", clump = "Strand Clumping",
	frizz = "Frizz & Flyaways", pores = "Skin Texture", lidHeavy = "Hooded Lids",
}
function LookKit.Label(entry)
	return LABELS[entry.key] or entry.label
end

-- one-line hints (the main sliders show them)
LookKit.Hints = {
	jawWidth = "How wide the jaw sits under the ears", chin = "Size of the chin", cheek = "How much the cheekbones stand out",
	noseWidth = "Width of the nose at the nostrils", noseLength = "From the brow down to the tip", lips = "Fuller or thinner lips",
	eyeSize = "Bigger or smaller eyes", eyeShape = "Round eyes or narrow almond eyes", eyeDist = "How far apart the eyes sit",
	freckles = "Freckles across the nose and cheeks", wrinkles = "Lines that also deepen with age", smooth = "Smooth skin or a rougher grain",
	length = "Longer hair hangs lower (short cuts barely change)", volume = "How much the hair stands up and out",
	shoulders = "Frame width across the shoulders", arms = "Muscle on the upper arms and forearms",
	age = "Young boxers start weaker but grow faster; veterans peak sooner",
	height = "Taller boxers have more reach", weight = "Your weight between fights, inside your division",
	reach = "Arm span beyond your height: longer jabs land from further out",
}

-- slider opts for a Looks slider entry: words, number, default (and the hint when asked)
function LookKit.Opts(entry, default, withHint)
	return {
		words = LookKit.Words(entry.key, entry.min, entry.max),
		default = type(default) == "number" and default or nil,
		hint = withHint and LookKit.Hints[entry.key] or nil,
	}, LookKit.Num(entry.min, entry.max, entry.step)
end

-- a Looks slider list by key (face / eye / skin / wear / sculpt / hair / body)
local ENTRY = {}
for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders, Looks.WearSliders, Looks.SculptSliders or {}, Looks.HairSliders, Looks.HairDetailSliders or {}, Looks.BodySliders }) do
	for _, e in ipairs(list) do
		ENTRY[e.key] = e
	end
end
function LookKit.Entry(key)
	return ENTRY[key]
end

------------------------------------------------------------------------
-- Presets
------------------------------------------------------------------------
-- face presets: a shape, a nose type and the face / sculpt keys that differ from the gender default
LookKit.FacePresets = {
	{ id = "Classic", shape = "Oval", desc = "Even features", set = {} },
	{ id = "Chiselled", shape = "Square", desc = "Strong jaw", set = { jawWidth = 0.5, jawDef = 0.9, cheek = 0.5, chin = 0.3, jawAngle = 0.85, cheekHeight = 0.4 } },
	{ id = "Rugged", shape = "Square", nose = "Boxer", desc = "Heavy brow", set = { jawWidth = 0.6, browRidge = 0.85, noseWidth = 0.4, noseBridge = 0.3, chin = 0.4, eyeDepth = 0.7, browThick = 0.4 } },
	{ id = "Baby Face", shape = "Round", nose = "Button", desc = "Soft and young", set = { jawWidth = -0.4, jawDef = 0.2, cheekFull = 0.6, chin = -0.3, eyeSize = 0.3, noseLength = -0.3, lips = 0.2, browRidge = 0.1, jawAngle = 0.2 } },
	{ id = "Sharp", shape = "Diamond", nose = "Greek", desc = "High cheekbones", set = { cheek = 0.7, cheekHeight = 0.6, cheekFull = -0.5, jawWidth = -0.2, chin = 0.3, noseLength = 0.2, noseWidth = -0.3, jawAngle = 0.75 } },
	{ id = "Long", shape = "Long", desc = "Long and lean", set = { forehead = 0.3, chin = 0.4, noseLength = 0.4, jawWidth = -0.2, skullLength = 0.3 } },
	{ id = "Heart", shape = "Heart", desc = "Narrow chin", set = { forehead = 0.3, chin = -0.3, jawWidth = -0.4, cheek = 0.4, lips = 0.3 } },
	{ id = "Brawler", shape = "Round", nose = "Flat", desc = "Flat nose", set = { noseWidth = 0.6, noseBridge = -0.4, lips = 0.4, jawWidth = 0.5, browThick = 0.5, browRidge = 0.95, noseBreak = 0.35 } },
}

-- gear kits: trunks, trim, socks, shoes, laces, gloves (+ cuff), robe (+ trim), wraps
LookKit.KitPresets = {
	{ id = "Champion", desc = "Black & red", trunks = { 20, 20, 20 }, trim = { 200, 25, 30 }, socks = { 240, 240, 240 }, shoes = { 20, 20, 20 }, laces = { 200, 25, 30 },
		gloves = { 200, 25, 30 }, cuff = { 240, 240, 240 }, robe = { 20, 20, 20 }, robeTrim = { 200, 25, 30 }, wraps = { 240, 240, 240 }, trunkStyle = "Pro", shoeStyle = "High-Top" },
	{ id = "Golden", desc = "White & gold", trunks = { 240, 240, 240 }, trim = { 230, 180, 30 }, socks = { 240, 240, 240 }, shoes = { 240, 240, 240 }, laces = { 230, 180, 30 },
		gloves = { 230, 180, 30 }, cuff = { 240, 240, 240 }, robe = { 240, 240, 240 }, robeTrim = { 230, 180, 30 }, wraps = { 240, 240, 240 }, trunkStyle = "Classic", shoeStyle = "High-Top" },
	{ id = "Blue Corner", desc = "Royal blue", trunks = { 25, 60, 200 }, trim = { 240, 240, 240 }, socks = { 240, 240, 240 }, shoes = { 25, 60, 200 }, laces = { 240, 240, 240 },
		gloves = { 25, 60, 200 }, cuff = { 240, 240, 240 }, robe = { 25, 60, 200 }, robeTrim = { 240, 240, 240 }, wraps = { 240, 240, 240 }, trunkStyle = "Striped", shoeStyle = "Low-Top" },
	{ id = "Red Corner", desc = "Fight red", trunks = { 200, 25, 30 }, trim = { 230, 180, 30 }, socks = { 20, 20, 20 }, shoes = { 200, 25, 30 }, laces = { 230, 180, 30 },
		gloves = { 200, 25, 30 }, cuff = { 230, 180, 30 }, robe = { 200, 25, 30 }, robeTrim = { 230, 180, 30 }, wraps = { 20, 20, 20 }, trunkStyle = "Classic", shoeStyle = "High-Top" },
	{ id = "Jungle", desc = "Green & gold", trunks = { 20, 140, 60 }, trim = { 230, 180, 30 }, socks = { 240, 240, 240 }, shoes = { 20, 20, 20 }, laces = { 20, 140, 60 },
		gloves = { 20, 140, 60 }, cuff = { 230, 180, 30 }, robe = { 20, 140, 60 }, robeTrim = { 230, 180, 30 }, wraps = { 240, 240, 240 }, trunkStyle = "Long", shoeStyle = "High-Top" },
	{ id = "Royal", desc = "Purple & gold", trunks = { 120, 30, 160 }, trim = { 230, 180, 30 }, socks = { 20, 20, 20 }, shoes = { 20, 20, 20 }, laces = { 230, 180, 30 },
		gloves = { 120, 30, 160 }, cuff = { 230, 180, 30 }, robe = { 120, 30, 160 }, robeTrim = { 230, 180, 30 }, wraps = { 20, 20, 20 }, trunkStyle = "Pro", shoeStyle = "Low-Top" },
}

-- puts a kit on attire a and gloves g (copies, so later edits never touch the preset)
function LookKit.ApplyKit(kit, a, g)
	local function c(t)
		return { t[1], t[2], t[3] }
	end
	a.trunks, a.trim, a.socks, a.shoes, a.laces = c(kit.trunks), c(kit.trim), c(kit.socks), c(kit.shoes), c(kit.laces)
	a.robe, a.robeTrim, a.wraps = c(kit.robe), c(kit.robeTrim), c(kit.wraps)
	a.trunkStyle, a.shoeStyle = kit.trunkStyle, kit.shoeStyle
	g.color, g.trim = c(kit.gloves), c(kit.cuff)
end

------------------------------------------------------------------------
-- Glyphs: tiny frame drawings for the preset cards (no image assets)
------------------------------------------------------------------------
local function box(parent, props, radius)
	props.BorderSizePixel = 0
	props.Parent = parent
	local f = UI.New("Frame", props)
	if radius then
		UI.New("UICorner", { CornerRadius = radius, Parent = f })
	end
	return f
end
local ROUND = UDim.new(0.5, 0)

-- a square drawing area centred in the card's art box, on a soft disc (dark hair still reads on it)
local function glyphRoot(parent)
	local g = box(parent, { Name = "Glyph", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
	UI.New("UIAspectRatioConstraint", { AspectRatio = 1, Parent = g })
	box(g, { Name = "Disc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.96), BackgroundColor3 = T.line, BackgroundTransparency = 0.45, ZIndex = 1 }, ROUND)
	return g
end

-- hairstyle families for the glyphs
local HAIR_KIND = {
	Bald = "bald", ["Buzz Cut"] = "buzz", ["360 Waves"] = "buzz", ["Crew Cut"] = "crop", ["Caesar Cut"] = "crop", ["Textured Crop"] = "crop",
	["Modern Athlete"] = "crop", Fade = "fade", ["Low Fade"] = "fade", ["Mid Fade"] = "fade", ["High Fade"] = "fade", ["Taper Fade"] = "fade",
	["Burst Fade"] = "fade", Undercut = "fade", Mohawk = "mohawk", ["High Top"] = "hightop", Afro = "afro", ["Curly Top"] = "curly",
	["Short Curly"] = "curly", ["Long Curly"] = "longcurly", ["Short Dreads"] = "locs", Twists = "locs", Dreadlocks = "longlocs",
	Braids = "longlocs", ["Box Braids"] = "longlocs", Cornrows = "cornrows", ["Messy Hair"] = "messy", ["Slick Back"] = "slick",
	["Long Hair"] = "long", Ponytail = "ponytail", ["Wolf Cut"] = "wolf",
}

-- a head in the hairstyle: draws into a square frame the caller sizes (hair / skin as {r,g,b} or Color3)
function LookKit.HairGlyph(parent, style, hairRGB, skinRGB)
	local hair, skin = UI.ToColor(hairRGB), UI.ToColor(skinRGB)
	local g = glyphRoot(parent)
	local kind = HAIR_KIND[style] or "crop"
	local behind = 2
	local front = 4
	-- long hair behind the head
	if kind == "afro" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.92, 0.82), BackgroundColor3 = hair, ZIndex = behind }, ROUND)
	elseif kind == "longcurly" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.1), Size = UDim2.fromScale(0.86, 0.82), BackgroundColor3 = hair, ZIndex = behind }, UDim.new(0.4, 0))
	elseif kind == "long" or kind == "wolf" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.14), Size = UDim2.fromScale(0.72, kind == "long" and 0.84 or 0.66), BackgroundColor3 = hair, ZIndex = behind }, UDim.new(0.3, 0))
	elseif kind == "longlocs" then
		for i = 0, 5 do
			local x = 0.2 + i * 0.12
			box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0.2), Size = UDim2.fromScale(0.07, 0.76), BackgroundColor3 = hair, ZIndex = behind }, ROUND)
		end
	elseif kind == "ponytail" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.83, 0.42), Size = UDim2.fromScale(0.2, 0.2), BackgroundColor3 = hair, ZIndex = behind }, ROUND)
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.88, 0.45), Size = UDim2.fromScale(0.12, 0.42), BackgroundColor3 = hair, ZIndex = behind }, ROUND)
	end
	-- the head
	box(g, { Name = "Head", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.54, 0.64), BackgroundColor3 = skin, ZIndex = 3 }, ROUND)
	-- the cap of hair over the top of the head: a head-sized oval clipped to its upper part
	local function cap(depth, lift, alpha)
		local clip = box(g, { Name = "Cap", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.24 - lift), Size = UDim2.fromScale(0.6, depth), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = front })
		box(clip, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, 0, 0.64 / depth, 0), BackgroundColor3 = hair, BackgroundTransparency = alpha or 0, ZIndex = front }, ROUND)
		return clip
	end
	if kind == "bald" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.42, 0.34), Size = UDim2.fromScale(0.1, 0.06), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, ZIndex = front }, ROUND)
	elseif kind == "buzz" then
		cap(0.16, 0, 0.35)
	elseif kind == "crop" or kind == "slick" or kind == "messy" or kind == "curly" or kind == "locs" or kind == "cornrows" or kind == "ponytail" or kind == "long" or kind == "wolf" then
		cap(kind == "slick" and 0.2 or 0.18, kind == "slick" and 0.04 or 0.02)
	elseif kind == "fade" then
		cap(0.16, 0.02)
		-- the faded sides: a light wash of hair colour down the temples
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.56, 0.12), BackgroundColor3 = hair, BackgroundTransparency = 0.7, ZIndex = front }, UDim.new(0.3, 0))
	elseif kind == "mohawk" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromScale(0.14, 0.3), BackgroundColor3 = hair, ZIndex = front }, UDim.new(0.3, 0))
	elseif kind == "hightop" then
		box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.52, 0.34), BackgroundColor3 = hair, ZIndex = front }, UDim.new(0.12, 0))
	elseif kind == "afro" or kind == "longcurly" then
		cap(0.16, 0.04)
	elseif kind == "longlocs" then
		cap(0.18, 0.03)
	end
	if kind == "curly" or kind == "longcurly" then
		for i = 0, 3 do
			box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.29 + i * 0.14, 0.22 + (i % 2) * 0.03), Size = UDim2.fromScale(0.17, 0.17), BackgroundColor3 = hair, ZIndex = front }, ROUND)
		end
	elseif kind == "locs" then
		for i = 0, 4 do
			box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.26 + i * 0.12, 0.12 + (i % 2) * 0.03), Size = UDim2.fromScale(0.07, 0.2), BackgroundColor3 = hair, ZIndex = front }, ROUND)
		end
	elseif kind == "cornrows" then
		for i = 0, 3 do
			box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.35 + i * 0.1, 0.24), Size = UDim2.fromScale(0.025, 0.16), BackgroundColor3 = skin, BackgroundTransparency = 0.3, ZIndex = front + 1 })
		end
	elseif kind == "messy" or kind == "wolf" then
		for i = 0, 3 do
			box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3 + i * 0.13, 0.22), Size = UDim2.fromScale(0.06, 0.16), Rotation = -30 + i * 20, BackgroundColor3 = hair, ZIndex = front }, ROUND)
		end
	end
	return g
end

-- a face outline for a face shape (width / chin read at a glance)
local FACE_SHAPE = {
	Oval = { 0.56, 0.74, 0.5 }, Square = { 0.64, 0.72, 0.22 }, Round = { 0.68, 0.7, 0.5 }, Long = { 0.5, 0.82, 0.42 },
	Diamond = { 0.56, 0.76, 0.36 }, Heart = { 0.62, 0.74, 0.44 },
}
function LookKit.FaceGlyph(parent, shape, skinRGB)
	local skin = UI.ToColor(skinRGB)
	local g = glyphRoot(parent)
	local s = FACE_SHAPE[shape] or FACE_SHAPE.Oval
	box(g, { Name = "Head", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(s[1], s[2]), BackgroundColor3 = skin, ZIndex = 2 }, UDim.new(s[3], 0))
	if shape == "Heart" or shape == "Diamond" then
		-- a narrower chin under a wider brow / cheek line
		box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(s[1] * 0.42, 0.16), BackgroundColor3 = skin, ZIndex = 2, Rotation = 45 }, UDim.new(0.2, 0))
	end
	local ink = T.ink
	for _, x in ipairs({ 0.4, 0.6 }) do
		box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.45), Size = UDim2.fromScale(0.08, 0.05), BackgroundColor3 = ink, ZIndex = 3 }, ROUND)
	end
	box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(0.18, 0.035), BackgroundColor3 = ink, BackgroundTransparency = 0.3, ZIndex = 3 }, ROUND)
	return g
end

-- a torso for a body frame (shoulder width = the frame's width)
function LookKit.BuildGlyph(parent, width, skinRGB)
	local skin = UI.ToColor(skinRGB)
	local g = glyphRoot(parent)
	local w = math.clamp(0.5 + (width - 1) * 2.2, 0.32, 0.86)
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.06), Size = UDim2.fromScale(0.22, 0.24), BackgroundColor3 = skin, ZIndex = 2 }, ROUND)
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromScale(w, 0.3), BackgroundColor3 = skin, ZIndex = 2 }, UDim.new(0.25, 0))
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(w * 0.62, 0.36), BackgroundColor3 = skin, ZIndex = 2 }, UDim.new(0.2, 0))
	return g
end

-- a kit's colours: trunks with their trim band, a glove and a boot
function LookKit.KitGlyph(parent, kit)
	local g = glyphRoot(parent)
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.36, 0.16), Size = UDim2.fromScale(0.48, 0.5), BackgroundColor3 = UI.ToColor(kit.trunks), ZIndex = 2 }, UDim.new(0.12, 0))
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.36, 0.16), Size = UDim2.fromScale(0.48, 0.1), BackgroundColor3 = UI.ToColor(kit.trim), ZIndex = 3 }, UDim.new(0.12, 0))
	box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.76, 0.36), Size = UDim2.fromScale(0.34, 0.4), BackgroundColor3 = UI.ToColor(kit.gloves), ZIndex = 2 }, UDim.new(0.45, 0))
	box(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.76, 0.6), Size = UDim2.fromScale(0.26, 0.08), BackgroundColor3 = UI.ToColor(kit.cuff), ZIndex = 3 }, UDim.new(0.3, 0))
	box(g, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.36, 0.74), Size = UDim2.fromScale(0.42, 0.16), BackgroundColor3 = UI.ToColor(kit.shoes), ZIndex = 2 }, UDim.new(0.3, 0))
	return g
end

------------------------------------------------------------------------
-- Hairstyle picker: group chips over the picked group's style cards
------------------------------------------------------------------------
local GROUP_SHORT = { Short = "SHORT", Fades = "FADES", ["Curly & Coily"] = "CURLY", ["Locs & Braids"] = "LOCS", ["Long & Styled"] = "LONG" }

function LookKit.GroupOf(style)
	for _, g in ipairs(Looks.HairStyleGroups) do
		if table.find(g.styles, style) then
			return g.name
		end
	end
	return Looks.HairStyleGroups[1].name
end

-- group = the group shown (nil: the current style's own, whose chip is gold-lettered while another
-- group is shown); onPick(style), onGroup(name) (the caller re-renders)
function LookKit.HairPicker(parent, h, skinRGB, group, onPick, onGroup)
	local own = LookKit.GroupOf(h.style)
	group = group or own
	local groups = Looks.HairStyleGroups
	local tabs = UI.Frame(parent, { Name = "HairGroups", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
	UI.Grid(tabs, UDim2.new(1 / #groups, -6, 0, 36), nil, 6)
	local shown
	for i, g in ipairs(groups) do
		local on = g.name == group
		if on then
			shown = g
		end
		UI.Button(tabs, GROUP_SHORT[g.name] or g.name:upper(), { Name = "Group_" .. i, LayoutOrder = i, TextSize = 14, BackgroundColor3 = on and T.gold or T.panel2,
			TextColor3 = on and T.bg or (g.name == own and T.gold or T.text) }, function()
			onGroup(g.name)
		end)
	end
	shown = shown or groups[1]
	local items = {}
	for _, st in ipairs(shown.styles) do
		table.insert(items, { id = st, label = st, glyph = function(art)
			LookKit.HairGlyph(art, st, h.color, skinRGB)
		end })
	end
	return LookKit.PresetGrid(parent, items, { name = "Styles", cols = 4, cellH = 96, picked = h.style }, function(it)
		onPick(it.id)
	end)
end

------------------------------------------------------------------------
-- Preset grid: cards with a glyph over a caption, the picked one outlined in gold
------------------------------------------------------------------------
-- items = { { id, label, sub?, glyph = fn(holder) } }; opts = { cols = n (on a wide row), cellH, picked = id }
-- onPick(item). Returns the grid frame.
function LookKit.PresetGrid(parent, items, opts, onPick)
	opts = opts or {}
	local cellH = opts.cellH or 96
	local grid = UI.Frame(parent, { Name = opts.name or "Presets", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local cols = opts.cols or 4
	UI.Grid(grid, UDim2.new(1 / cols, -6, 0, cellH), nil, 6)
	for i, it in ipairs(items) do
		local on = opts.picked ~= nil and opts.picked == it.id
		local b = UI.Button(grid, "", { Name = "Preset_" .. tostring(it.id), LayoutOrder = i, BackgroundColor3 = on and T.panel:Lerp(T.gold, 0.22) or T.panel2 }, function()
			onPick(it)
		end)
		b:SetAttribute("PresetId", tostring(it.id))
		if on then
			UI.Stroke(b, T.gold, 2)
		end
		local textH = it.sub and 36 or 24
		local art = UI.Frame(b, { Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(1, -12, 0, cellH - textH - 8) })
		if it.glyph then
			pcall(it.glyph, art)
		end
		UI.Text(b, it.label, { Name = "Caption", Face = "displayMed", TextSize = 14, TextColor3 = on and T.gold or T.text, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, it.sub and -16 or -6),
			Size = UDim2.new(1, -8, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		if it.sub then
			UI.Text(b, it.sub, { Name = "Sub", TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -8, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
	end
	return grid
end

return LookKit
