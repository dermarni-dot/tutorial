-- Typography: the game's type faces in one place, for the menus (Shared.UI) and for the signs in the world
-- (Signage, the Venues / GymDecor / CityMap / CityProps builders, the client detail layers), so the whole
-- game changes face together. No services, no client-only requires: a server sign builder can use it.
--
-- The look: a plain sports-broadcast system. One geometric grotesque (Gotham) for everything that is read as
-- a label - titles, headings, buttons, captions - a humanist sans (Builder Sans) for running text, and a
-- condensed face (Oswald) for the big numbers only: the round clock, the scores, the stat tiles. The loud
-- poster face (Bangers) is kept for the WCB wordmark on the brand ribbon and the signs out in the world.
--
--   role         face                         size   use
--   display      Gotham Bold                  24-28  the one title size: window titles, the result headline
--   displayMed   Gotham Bold                  14-16  buttons, tabs, the call-outs
--   heading      Gotham Bold                  16-18  section headings, a row's name, emphasised labels
--   label        Gotham Medium                11-13  captions, chips, kickers, row labels, key caps
--   body         Builder Sans Medium          13-15  body copy, inputs, descriptions, hints
--   number       Oswald SemiBold              20-50  the big numbers: the clock, scores, records, money
--   numberMed    Gotham Bold                  13-16  smaller readouts (tabular figures): the round text
--   mono         RobotoMono Medium                   technical readouts, monitors
--   brand        Bangers                             the WCB wordmark on the ribbon (nothing else)
--   sign         Bangers                             the world's sign face (the shop lockups, the venues)
--   signSub      Gotham Medium                       a sign's second line
--   plate        Oswald Bold                         the engraved look: belt plates
-- Flavour faces for particular props stay Enum.Font values (their families resolve inside the engine):
--   marker (hand-written placards), serif (the museum, an estate's gate), tech (a car dealer), led (LED
--   clocks), hand (fans' signs), screen (old monitors).
--
-- Built-in families only (Font.new on rbxasset families, inside pcall: Typography.Fonts[role] is nil where
-- Font.new is unavailable, and Typography.Apply falls back to the nearest Enum.Font).
local Typography = {}

Typography.Families = {
	display = "GothamSSm",
	text = "BuilderSans",
	number = "Oswald",
	brand = "Bangers",
	mono = "RobotoMono",
}

local function face(family, weight)
	local ok, f = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	end)
	return ok and f or nil
end
Typography.Face = face

local gothamBold = face("GothamSSm", Enum.FontWeight.Bold)
local gothamMedium = face("GothamSSm", Enum.FontWeight.Medium)
local brand = face("Bangers", Enum.FontWeight.Regular)
Typography.Fonts = {
	display = gothamBold,
	displayMed = gothamBold,
	heading = gothamBold,
	label = gothamMedium,
	body = face("BuilderSans", Enum.FontWeight.Medium),
	number = face("Oswald", Enum.FontWeight.SemiBold),
	numberMed = gothamBold,
	plate = face("Oswald", Enum.FontWeight.Bold),
	mono = face("RobotoMono", Enum.FontWeight.Medium),
	brand = brand,
	sign = brand,
	signSub = gothamMedium,
}

-- the nearest Enum.Font of each role
Typography.Fallback = {
	display = Enum.Font.GothamBold, displayMed = Enum.Font.GothamBold, heading = Enum.Font.GothamBold, label = Enum.Font.GothamMedium,
	body = Enum.Font.BuilderSansMedium,
	number = Enum.Font.Oswald, numberMed = Enum.Font.GothamBold, plate = Enum.Font.Oswald,
	mono = Enum.Font.RobotoMono,
	brand = Enum.Font.Bangers, sign = Enum.Font.Bangers, signSub = Enum.Font.GothamMedium,
}

Typography.Flavour = {
	marker = Enum.Font.PermanentMarker,
	serif = Enum.Font.Garamond,
	tech = Enum.Font.Michroma,
	led = Enum.Font.Arcade,
	hand = Enum.Font.Cartoon,
	screen = Enum.Font.Code,
	glyph = Enum.Font.Arial, -- a face with the ● glyph (VenueFX's crowd rows)
}

-- the role a legacy Enum.Font stands for (modules still pass UI.Theme.font / semi / bold)
Typography.RoleOf = {
	[Enum.Font.GothamBlack] = "heading",
	[Enum.Font.GothamBold] = "label",
	[Enum.Font.GothamMedium] = "body",
	[Enum.Font.Gotham] = "body",
	[Enum.Font.BuilderSans] = "body",
	[Enum.Font.BuilderSansMedium] = "body",
	[Enum.Font.BuilderSansBold] = "heading",
	[Enum.Font.Oswald] = "number",
	[Enum.Font.Bangers] = "brand",
	[Enum.Font.RobotoMono] = "mono",
}

-- the width one character of an UPPERCASE line takes, in em, per role (a generous estimate for layouts
-- measured before the text draws: Gotham Bold caps run about 0.68 em and its space 0.28, Builder Sans
-- Medium caps 0.64, Oswald SemiBold caps 0.53, Bangers caps 0.41 with a 0.2 space; TextService measures
-- Enum fonts only)
Typography.Em = {
	display = 0.72, displayMed = 0.72, heading = 0.72, label = 0.7, signSub = 0.7, numberMed = 0.7,
	body = 0.66,
	number = 0.56, plate = 0.56,
	mono = 0.64,
	brand = 0.46, sign = 0.46,
}

-- a role that draws larger than the size asked for (none now: every face in the system keeps its em; the
-- table stays for callers that scale a role's size)
Typography.Scale = {}

-- the size a role really draws at
function Typography.SizeOf(role, size)
	local k = role and Typography.Scale[role]
	if k and k ~= 1 then
		return math.floor(size * k + 0.5)
	end
	return size
end

-- the Enum.Font nearest a role / a Font / an Enum.Font (for APIs that take only an enum: TextService)
function Typography.Enum(spec)
	if type(spec) == "string" then
		return Typography.Fallback[spec] or Typography.Flavour[spec] or Enum.Font.GothamBold
	end
	if typeof(spec) == "EnumItem" then
		return spec
	end
	if typeof(spec) == "Font" then
		local fam = tostring(spec.Family or "")
		local wt = tostring(spec.Weight or "")
		for role, f in pairs(Typography.Fonts) do
			if f and tostring(f.Family) == fam and tostring(f.Weight) == wt then
				return Typography.Fallback[role]
			end
		end
		for role, f in pairs(Typography.Fonts) do
			if f and tostring(f.Family) == fam then
				return Typography.Fallback[role]
			end
		end
	end
	return Enum.Font.GothamBold
end

-- puts a face on a text object: spec = a role name, a Font, an Enum.Font or nil (the sign face)
function Typography.Apply(obj, spec)
	spec = spec or "sign"
	if type(spec) == "string" then
		local f = Typography.Fonts[spec]
		if f then
			local ok = pcall(function()
				obj.FontFace = f
			end)
			if ok then
				return obj
			end
		end
		obj.Font = Typography.Fallback[spec] or Typography.Flavour[spec] or Enum.Font.GothamBold
		return obj
	end
	if typeof(spec) == "Font" then
		local ok = pcall(function()
			obj.FontFace = spec
		end)
		if not ok then
			obj.Font = Enum.Font.GothamBold
		end
		return obj
	end
	obj.Font = spec
	return obj
end

-- the props key/value that puts a role on an object built from a props table ({ FontFace = ... } or
-- { Font = ... }); merged into `props` when given
function Typography.Props(role, props)
	props = props or {}
	local f = Typography.Fonts[role]
	if f then
		props.FontFace = f
	else
		props.Font = Typography.Fallback[role] or Typography.Flavour[role] or Enum.Font.GothamBold
	end
	return props
end

-- an estimate of the width (px) of a line in a role at `size`
function Typography.Width(text, size, role)
	text = tostring(text or "")
	local n = utf8.len(text) or #text
	return math.ceil(n * size * (Typography.Em[role or "label"] or 0.7))
end

-- words shouted in capitals turned into Title Case ("MOVE DOWN" -> "Move Down"), for the kit's buttons and
-- titles: a plain look speaks in mixed case. Short tokens and known initialisms (KO, PVP, WBC, OVR, R1,
-- W/A/S/D) stay as they are; text that already has lower-case letters is returned untouched.
local KEEP = { KO = true, TKO = true, PVP = true, OVR = true, OK = true, HP = true, XP = true, UI = true, AI = true, ID = true, TV = true, VS = true, KOS = true, KD = true,
	WBC = true, WBA = true, IBF = true, WBO = true, USA = true, UK = true, HUD = true, FPS = true, RD = true, MMA = true, LB = true, LBS = true, DNA = true, NPC = true, CPU = true,
	GPU = true, VSYNC = true, FX = true, SFX = true, BGM = true, PC = true, II = true, III = true, IV = true, VI = true, VII = true, VIII = true, IX = true }
local SMALL = { ["a"] = true, ["an"] = true, ["and"] = true, ["at"] = true, ["by"] = true, ["for"] = true, ["in"] = true, ["of"] = true, ["on"] = true, ["or"] = true, ["the"] = true, ["to"] = true, ["vs"] = true, ["v"] = true }
function Typography.TitleCase(text)
	text = tostring(text or "")
	if text:find("%l") or not text:find("%u%u") then
		return text
	end
	local first = true
	local out = text:gsub("(%a[%a']*)", function(word)
		if word == "PVP" then
			first = false
			return "PvP"
		end
		local keep = KEEP[word] or #word <= 2 and word:find("^%u%d*$") ~= nil
		if keep or word:find("%d") then
			first = false
			return word
		end
		local lower = word:lower()
		local res
		if SMALL[lower] and not first then
			res = lower
		else
			res = lower:sub(1, 1):upper() .. lower:sub(2)
		end
		first = false
		return res
	end)
	return out
end

-- a line led by a shouted label turned into sentence case for display ("WORLD CHAMPION: you won the WBC belt" ->
-- "World champion: you won the WBC belt", "GYM COACH: ..." -> "Gym coach: ..."); initialisms (KEEP) stay, and a
-- whole line in capitals becomes one sentence. The data keeps its capitals (code matches on them).
function Typography.Sentence(text)
	text = tostring(text or "")
	local function sentence(chunk, first)
		local out = chunk:gsub("(%a[%a']*)", function(word)
			if KEEP[word] or word:find("%d") or (#word <= 2 and word:find("^%u%d*$") and not first) then
				first = false
				return word
			end
			if not word:find("%u%u") and not word:find("^%u$") then
				first = false
				return word
			end
			local lower = word:lower()
			local res = first and (lower:sub(1, 1):upper() .. lower:sub(2)) or lower
			first = false
			return res
		end)
		return out
	end
	local head, rest = text:match("^([%u][%u%s'%-]+):(.*)$")
	if head and head:find("%u%u") then
		return sentence(head, true) .. ":" .. rest
	end
	if text:find("%u%u%u") and not text:find("%l") then
		return sentence(text, true)
	end
	return text
end

return Typography
