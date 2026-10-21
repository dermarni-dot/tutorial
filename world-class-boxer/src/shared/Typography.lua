-- Typography: the game's type faces in one place, for the menus (Shared.UI) and for the signs in the world
-- (Signage, the Venues / GymDecor / CityMap / CityProps builders, the client detail layers), so the whole
-- game changes face together. No services, no client-only requires: a server sign builder can use it.
--
-- The look: a loud sports-poster display face for everything that shouts (titles, buttons, call-outs, the
-- HUD's big counters, the signs on Main Street), a condensed face for the numbers that line up in columns,
-- a round geometric sans for the reading.
--
--   role         face                         use
--   display      Bangers                      titles, the logo lockups, call-outs, sign wordmarks
--   displayMed   Bangers                      buttons, tabs, section heads
--   number       Oswald Bold                  tabular numbers: stats, clocks, records, money
--   numberMed    Oswald SemiBold              smaller readouts, the round text
--   heading      Montserrat ExtraBold         small headings, emphasised labels (GothamBlack under title size)
--   label        Montserrat Bold              captions, chips, kickers, row labels, a sign's second line
--   body         Montserrat Medium            body copy, inputs, descriptions
--   mono         RobotoMono Medium            technical readouts, monitors
--   sign         = display                    the world's default sign face
--   signSub      = label
--   plate        Oswald Bold                  the engraved look: belt plates
-- Flavour faces for particular props stay Enum.Font values (their families resolve inside the engine):
--   marker (hand-written placards), serif (the museum, an estate's gate), tech (a car dealer), led (LED
--   clocks), hand (fans' signs), screen (old monitors).
--
-- Built-in families only (Font.new on rbxasset families, inside pcall: Typography.Fonts[role] is nil where
-- Font.new is unavailable, and Typography.Apply falls back to the nearest Enum.Font).
local Typography = {}

Typography.Families = {
	display = "Bangers",
	number = "Oswald",
	text = "Montserrat",
	mono = "RobotoMono",
}

local function face(family, weight)
	local ok, f = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	end)
	return ok and f or nil
end
Typography.Face = face

local display = face("Bangers", Enum.FontWeight.Regular)
local numberBold = face("Oswald", Enum.FontWeight.Bold)
Typography.Fonts = {
	display = display,
	displayMed = display,
	sign = display,
	number = numberBold,
	numberMed = face("Oswald", Enum.FontWeight.SemiBold),
	plate = numberBold,
	heading = face("Montserrat", Enum.FontWeight.ExtraBold),
	label = face("Montserrat", Enum.FontWeight.Bold),
	signSub = face("Montserrat", Enum.FontWeight.Bold),
	body = face("Montserrat", Enum.FontWeight.Medium),
	mono = face("RobotoMono", Enum.FontWeight.Medium),
}

-- the nearest Enum.Font of each role (no Montserrat enum exists: Gotham stands in)
Typography.Fallback = {
	display = Enum.Font.Bangers, displayMed = Enum.Font.Bangers, sign = Enum.Font.Bangers,
	number = Enum.Font.Oswald, numberMed = Enum.Font.Oswald, plate = Enum.Font.Oswald,
	heading = Enum.Font.GothamBlack, label = Enum.Font.GothamBold, signSub = Enum.Font.GothamBold, body = Enum.Font.GothamMedium,
	mono = Enum.Font.RobotoMono,
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
	[Enum.Font.Oswald] = "number",
	[Enum.Font.Bangers] = "display",
	[Enum.Font.RobotoMono] = "mono",
}

-- the width one character of an UPPERCASE line takes, in em, per role (a generous estimate for layouts
-- measured before the text draws: Bangers caps run about 0.41 em and its space 0.2, Oswald Bold caps
-- 0.53, Montserrat Bold caps 0.73; TextService measures Enum fonts only)
Typography.Em = {
	display = 0.46, displayMed = 0.46, sign = 0.46,
	number = 0.56, numberMed = 0.55, plate = 0.56,
	heading = 0.8, label = 0.76, signSub = 0.76, body = 0.74,
	mono = 0.64,
}

-- Bangers' capitals stand 0.72 em (Oswald's 0.81): the display roles draw a little larger than the size
-- asked for, so a title keeps the presence it had
Typography.Scale = { display = 1.12, displayMed = 1.12, sign = 1 }

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
		return Typography.Fallback[spec] or Typography.Flavour[spec] or Enum.Font.GothamBlack
	end
	if typeof(spec) == "EnumItem" then
		return spec
	end
	if typeof(spec) == "Font" then
		local fam = tostring(spec.Family or "")
		for role, f in pairs(Typography.Fonts) do
			if f and tostring(f.Family) == fam then
				return Typography.Fallback[role]
			end
		end
	end
	return Enum.Font.GothamBlack
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
		obj.Font = Typography.Fallback[spec] or Typography.Flavour[spec] or Enum.Font.GothamBlack
		return obj
	end
	if typeof(spec) == "Font" then
		local ok = pcall(function()
			obj.FontFace = spec
		end)
		if not ok then
			obj.Font = Enum.Font.GothamBlack
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
		props.Font = Typography.Fallback[role] or Typography.Flavour[role] or Enum.Font.GothamBlack
	end
	return props
end

-- an estimate of the width (px) of a line in a role at `size`
function Typography.Width(text, size, role)
	text = tostring(text or "")
	local n = utf8.len(text) or #text
	return math.ceil(n * size * (Typography.Em[role or "label"] or 0.76))
end

return Typography
