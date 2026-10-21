-- Signage: the game's places and their logo lockups - one system for the signs in the world and the badges
-- in the menus, so a location looks the same on its shop front, in the Career Hub, on a fight offer and on
-- a tournament card.
--
-- Every location (the gym, the Main Street shops, the fight venues, the places you travel to) has one entry:
-- its wordmark (`short`, with the full `name` and a `sub` line), an icon of the game's icon set
-- (Shared.IconData), and its colours (`bg` board / badge fill, `fg` wordmark, `accent` the icon's tile).
--
-- The lockup is an icon tile beside (or above) the wordmark, laid out in Scale units so it fits any board:
--   * Signage.Board(part, face, loc, opts) - a SurfaceGui on a part's face. The pixel density is chosen from
--     the face's height so TextScaled text fills the board (the engine caps text at 100 px: a 7-stud banner at
--     40 px per stud drew its name a third of the height) and the layout centres a lockup that is narrower
--     than the board instead of stretching one name across forty studs of sign.
--   * Signage.Lockup(parent, loc, opts) - the same lockup inside any GuiObject (opts.aspect = width / height).
--   * Signage.Badge(parent, loc, h, opts) - a menu badge h px tall: the tile, the wordmark, the sub line.
-- Icons come from the uploaded sheets (ImageLabel + ImageRectOffset); an icon that is not uploaded is drawn
-- as its initial in a ring, so the layout never changes. The faces are Shared.Typography's: the wordmark in
-- the sign face (Bangers), the sub line in the label face (Montserrat Bold).
local Signage = {}

local Typography = require(script.Parent:WaitForChild("Typography"))
Signage.Typography = Typography

local IconData
do
	local ok, m = pcall(function()
		return require(script.Parent:WaitForChild("IconData", 5))
	end)
	IconData = ok and type(m) == "table" and m or nil
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local INK = rgb(12, 13, 18)
local GOLD = rgb(255, 205, 83)
local WHITE = rgb(245, 245, 248)
local CREAM = rgb(235, 232, 220)

------------------------------------------------------------------------
-- The places
------------------------------------------------------------------------
-- kind: gym | place | shop | venue. shop = the CityMap shop front's sign text (its Store key);
-- venue = the Venues kind. font: the wordmark's face (default Typography's sign face, Bangers).
Signage.Locations = {
	-- the gym and the places you travel to
	{ id = "gym", kind = "gym", name = "WORLD CLASS BOXING GYM", short = "WORLD CLASS BOXING GYM", sub = "CHAMPIONS ARE MADE HERE  ·  EST. 1987", icon = "glove", bg = rgb(18, 18, 22), fg = GOLD, accent = GOLD },
	{ id = "city", kind = "place", name = "MAIN STREET", short = "MAIN STREET", sub = "CHAMPION AVE & MAIN", icon = "pin", bg = rgb(30, 110, 60), fg = WHITE, accent = WHITE },
	{ id = "elite", kind = "place", name = "WCB ELITE PERFORMANCE CENTER", short = "ELITE PERFORMANCE", sub = "WCB SPORTS SCIENCE", icon = "bolt", bg = rgb(16, 16, 20), fg = rgb(150, 220, 255), accent = rgb(150, 220, 255) },
	{ id = "estate", kind = "place", name = "HILLCREST ESTATES", short = "HILLCREST", sub = "ESTATES", icon = "home", bg = rgb(40, 40, 44), fg = GOLD, accent = GOLD },
	{ id = "camp", kind = "place", name = "SUMMIT TRAINING CAMP", short = "SUMMIT", sub = "TRAINING CAMP", icon = "mountain", bg = rgb(70, 46, 30), fg = rgb(255, 230, 170), accent = rgb(255, 230, 170) },
	-- Main Street (shop = the CityMap sign text: the Store key of its prompt and windows)
	{ id = "barber", kind = "shop", shop = "FRESH FADES BARBERSHOP", name = "FRESH FADES BARBERSHOP", short = "FRESH FADES", sub = "BARBERSHOP", icon = "scissors", bg = rgb(14, 30, 70), fg = rgb(240, 240, 245), accent = rgb(240, 240, 245) },
	{ id = "diner", kind = "shop", shop = "CHAMP'S DINER", name = "CHAMP'S DINER", short = "CHAMP'S", sub = "DINER  ·  OPEN LATE", icon = "burger", bg = rgb(190, 20, 30), fg = WHITE, accent = WHITE },
	{ id = "supplements", kind = "shop", shop = "IRON SUPPLEMENTS", name = "IRON SUPPLEMENTS", short = "IRON", sub = "SUPPLEMENTS", icon = "dumbbell", bg = rgb(16, 18, 20), fg = rgb(80, 220, 110), accent = rgb(80, 220, 110) },
	{ id = "proshop", kind = "shop", shop = "WCB PRO SHOP - GLOVES & GEAR", name = "WCB PRO SHOP", short = "WCB PRO SHOP", sub = "GLOVES & GEAR", icon = "glove", bg = rgb(14, 14, 16), fg = GOLD, accent = GOLD },
	{ id = "cafe", kind = "shop", shop = "CORNER CAFE", name = "CORNER CAFE", short = "CORNER CAFE", sub = "COFFEE  ·  PASTRY", icon = "cup", bg = rgb(60, 40, 30), fg = rgb(255, 230, 190), accent = rgb(255, 230, 190) },
	{ id = "laundromat", kind = "shop", shop = "SPIN CITY LAUNDROMAT", name = "SPIN CITY LAUNDROMAT", short = "SPIN CITY", sub = "LAUNDROMAT", icon = "washer", bg = rgb(40, 110, 200), fg = WHITE, accent = WHITE },
	{ id = "tattoo", kind = "shop", shop = "INK & IRON TATTOO", name = "INK & IRON TATTOO", short = "INK & IRON", sub = "TATTOO", icon = "needle", bg = rgb(20, 14, 26), fg = rgb(220, 90, 255), accent = rgb(220, 90, 255) },
	{ id = "bakery", kind = "shop", shop = "SUNRISE BAKERY", name = "SUNRISE BAKERY", short = "SUNRISE", sub = "BAKERY  ·  FRESH DAILY", icon = "bread", bg = rgb(250, 240, 220), fg = rgb(170, 90, 40), accent = rgb(240, 170, 60) },
	{ id = "tickets", kind = "shop", shop = "WCB ARENA TICKETS", name = "WCB ARENA TICKETS", short = "ARENA TICKETS", sub = "WCB FIGHT NIGHTS", icon = "ticket", bg = rgb(150, 16, 24), fg = rgb(255, 220, 90), accent = rgb(255, 220, 90) },
	{ id = "cornerstore", kind = "shop", shop = "CORNER STORE 24/7", name = "CORNER STORE", short = "CORNER STORE", sub = "OPEN 24 / 7", icon = "bag", bg = rgb(30, 120, 60), fg = WHITE, accent = WHITE },
	{ id = "pizza", kind = "shop", shop = "TONY'S PIZZA", name = "TONY'S PIZZA", short = "TONY'S", sub = "PIZZA  ·  SINCE 1972", icon = "pizza", bg = rgb(20, 110, 50), fg = WHITE, accent = rgb(255, 210, 90) },
	{ id = "apartments", kind = "shop", shop = "RIVERSIDE APARTMENTS", name = "RIVERSIDE APARTMENTS", short = "RIVERSIDE", sub = "APARTMENTS", icon = "building", bg = rgb(30, 34, 40), fg = WHITE, accent = WHITE },
	{ id = "museum", kind = "shop", shop = "BOXING HALL OF FAME MUSEUM", name = "BOXING HALL OF FAME", short = "HALL OF FAME", sub = "BOXING MUSEUM", icon = "columns", bg = rgb(20, 20, 24), fg = GOLD, accent = GOLD },
	{ id = "motel", kind = "shop", shop = "STARLIGHT MOTEL", name = "STARLIGHT MOTEL", short = "STARLIGHT", sub = "MOTEL  ·  VACANCY", icon = "bed", bg = rgb(16, 20, 40), fg = rgb(255, 120, 180), accent = rgb(255, 120, 180) },
	{ id = "motors", kind = "shop", shop = "PRESTIGE MOTORS", name = "PRESTIGE MOTORS", short = "PRESTIGE", sub = "MOTORS", icon = "car", bg = rgb(12, 12, 16), fg = rgb(220, 220, 230), accent = rgb(220, 220, 230) },
	{ id = "gas", kind = "shop", shop = "FUEL & GO", name = "FUEL & GO", short = "FUEL & GO", sub = "SNACKS  ·  ICE", icon = "pump", bg = rgb(200, 30, 36), fg = WHITE, accent = WHITE },
	-- the fight venues (venue = the Venues kind; Config.Venues names)
	{ id = "community", kind = "venue", venue = "CommunityCenter", name = "COMMUNITY CENTER", short = "COMMUNITY CENTER", sub = "LOCAL BOXING NIGHT", icon = "people", bg = CREAM, fg = rgb(170, 25, 30), accent = rgb(170, 25, 30) },
	{ id = "club", kind = "venue", venue = "ClubArena", name = "CITY CLUB ARENA", short = "CITY CLUB ARENA", sub = "FIGHT NIGHT", icon = "ring", bg = rgb(14, 14, 18), fg = GOLD, accent = GOLD },
	{ id = "arena", kind = "venue", venue = "Arena", name = "GRAND ARENA", short = "GRAND ARENA", sub = "PROFESSIONAL BOXING", icon = "arena", bg = rgb(14, 14, 18), fg = GOLD, accent = GOLD },
	{ id = "stadium", kind = "venue", venue = "Stadium", name = "NATIONAL STADIUM", short = "NATIONAL STADIUM", sub = "WORLD CHAMPIONSHIP BOXING", icon = "stadium", bg = rgb(14, 14, 18), fg = GOLD, accent = GOLD },
	{ id = "spar", kind = "venue", venue = "Gym", name = "SPARRING RING", short = "SPARRING", sub = "WORLD CLASS BOXING GYM", icon = "glove", bg = rgb(14, 14, 18), fg = GOLD, accent = GOLD },
}

Signage.ById, Signage.ByShop, Signage.ByVenue, Signage.ByName = {}, {}, {}, {}
for _, loc in ipairs(Signage.Locations) do
	Signage.ById[loc.id] = loc
	if loc.shop then
		Signage.ByShop[loc.shop] = loc
	end
	if loc.venue then
		Signage.ByVenue[loc.venue] = loc
	end
	Signage.ByName[string.upper(loc.name)] = loc
end

-- a location by id, shop sign text, venue kind or display name (Config.Venues[kind].name, a shop's title)
function Signage.Get(key)
	if type(key) == "table" then
		return key
	end
	if type(key) ~= "string" then
		return nil
	end
	local u = string.upper(key)
	return Signage.ById[key] or Signage.ByShop[u] or Signage.ByVenue[key] or Signage.ByName[u]
end

-- a location from loose text: "Grand Arena", "LIVE FROM THE NATIONAL STADIUM", a Catalog sponsor's shop
function Signage.Find(text)
	local loc = Signage.Get(text)
	if loc then
		return loc
	end
	if type(text) ~= "string" then
		return nil
	end
	local u = string.upper(text)
	for _, l in ipairs(Signage.Locations) do
		if u:find(l.name, 1, true) or u:find(l.short, 1, true) then
			return l
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

function Signage.IconEntry(name)
	local e = IconData and IconData.icons and IconData.icons[name]
	if e and (tonumber(e.id) or 0) > 0 then
		return e
	end
	return nil
end

-- the icon as a glyph filling a Frame (Scale layout, any size): the sheet image, or the initial in a ring
function Signage.Glyph(parent, name, color, props)
	local f = new("Frame", { Name = "Glyph", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f:SetAttribute("Icon", name)
	local e = Signage.IconEntry(name)
	if e then
		new("ImageLabel", { Name = "Image", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Image = "rbxassetid://" .. tostring(e.id),
			ImageRectOffset = Vector2.new(e.x, e.y), ImageRectSize = Vector2.new(IconData.cell or 256, IconData.cell or 256), ImageColor3 = color, ScaleType = Enum.ScaleType.Fit, ZIndex = f.ZIndex }, f)
	else
		local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(0.84, 0.84), Position = UDim2.fromScale(0.08, 0.08), ZIndex = f.ZIndex }, f)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
		new("UIStroke", { Color = color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
		Typography.Apply(new("TextLabel", { Name = "Letter", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = string.upper(string.sub(tostring(name), 1, 1)), TextColor3 = color,
			TextScaled = true, ZIndex = f.ZIndex }, ring), "heading")
	end
	f.Parent = parent
	return f
end

-- the icon tile: a rounded square in the accent with the glyph knocked out in the board colour
local function tile(parent, loc, size, pos, anchor, z)
	local t = new("Frame", { Name = "Tile", BackgroundColor3 = loc.accent or loc.fg, BorderSizePixel = 0, Size = size, Position = pos, AnchorPoint = anchor or Vector2.new(0, 0), ZIndex = z or 2 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0.22, 0) }, t)
	new("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, t)
	Signage.Glyph(t, loc.icon, loc.bg, { Size = UDim2.fromScale(0.68, 0.68), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = (z or 2) + 1 })
	return t
end

-- a TextScaled label in a Typography role (props.Face, default the sign face)
local function text(parent, str, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, TextScaled = true, TextWrapped = false, Text = str, TextColor3 = WHITE })
	Typography.Apply(t, props.Face or "sign")
	for k, v in pairs(props) do
		if k ~= "Face" then
			t[k] = v
		end
	end
	t.Parent = parent
	return t
end

-- the lockup's natural width in height units (1 = the lockup's height): the tile, the gap and the wordmark
-- (Typography.Em: Bangers caps run about 0.46 em with their spaces, Montserrat Bold 0.76; the wordmark is
-- 0.56 of the height when a sub line is shown)
local function naturalUnits(loc, opts)
	local words = opts.text or loc.short
	local sub = opts.sub ~= false and (opts.subText or loc.sub) or nil
	local wordH = sub and 0.56 or 0.66
	local subH = 0.2
	local w = #words * wordH * Typography.Em.sign
	if sub then
		w = math.max(w, #sub * subH * Typography.Em.signSub)
	end
	return 0.14 + 0.72 + 0.2 + w + 0.16
end

-- the lockup inside `parent` (a SurfaceGui or any GuiObject). opts:
--   aspect   width / height of the parent (required for a good fit; default 4)
--   sub      false: no sub line;  subText: another sub line;  text: another wordmark
--   centre   true (default) centres a narrow lockup on the board; false: flush left
--   stack    force the stacked layout (icon above the words); row: force the row layout
--   z        base ZIndex
function Signage.Lockup(parent, loc, opts)
	opts = opts or {}
	loc = Signage.Get(loc) or Signage.ById.gym
	local aspect = opts.aspect or 4
	local z = opts.z or 2
	local fg = opts.fg or loc.fg
	local stack = opts.stack or (not opts.row and aspect < 2.4)
	local subLine = opts.sub ~= false and (opts.subText or loc.sub) or nil
	local holder = new("Frame", { Name = "Lockup", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z }, parent)
	holder:SetAttribute("Location", loc.id)
	if stack then
		-- tile on top, the wordmark and the sub line under it
		local hasSub = subLine ~= nil
		local tileH = hasSub and 0.46 or 0.52
		tile(holder, loc, UDim2.fromScale(tileH / aspect, tileH), UDim2.fromScale(0.5, 0.08), Vector2.new(0.5, 0), z)
		text(holder, opts.text or loc.short, { Name = "Wordmark", Size = UDim2.fromScale(0.9, hasSub and 0.2 or 0.26), Position = UDim2.fromScale(0.5, hasSub and 0.58 or 0.64),
			AnchorPoint = Vector2.new(0.5, 0), TextColor3 = fg, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
		if hasSub then
			text(holder, subLine, { Name = "Sub", Size = UDim2.fromScale(0.86, 0.11), Position = UDim2.fromScale(0.5, 0.8), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = fg,
				TextTransparency = 0.2, Face = "signSub", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
		end
		return holder
	end
	-- the row: a group no wider than its natural width, centred on the board (or flush left)
	local units = naturalUnits(loc, opts)
	local groupW = math.min(1, units / aspect)
	local group = new("Frame", { Name = "Group", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(groupW, 1),
		Position = UDim2.fromScale(opts.centre == false and 0 or 0.5, 0), AnchorPoint = Vector2.new(opts.centre == false and 0 or 0.5, 0), ZIndex = z }, holder)
	local ga = aspect * groupW -- the group's own aspect
	local hasSub = subLine ~= nil
	tile(group, loc, UDim2.fromScale(0.76 / ga, 0.76), UDim2.fromScale(0.12 / ga, 0.12), nil, z)
	local x0 = 1.06 / ga
	local tw = 1 - x0 - 0.14 / ga
	text(group, opts.text or loc.short, { Name = "Wordmark", Size = UDim2.fromScale(tw, hasSub and 0.56 or 0.66), Position = UDim2.fromScale(x0, hasSub and 0.06 or 0.17), TextColor3 = fg,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 1 })
	if hasSub then
		-- a hairline in the accent, then the sub line
		new("Frame", { Name = "Rule", BackgroundColor3 = loc.accent or fg, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(tw, 0.035), Position = UDim2.fromScale(x0, 0.655), ZIndex = z + 1 }, group)
		text(group, subLine, { Name = "Sub", Size = UDim2.fromScale(tw, 0.2), Position = UDim2.fromScale(x0, 0.72), TextColor3 = fg, TextTransparency = 0.15, Face = "signSub",
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 1 })
	end
	return holder
end

-- the face's width and height (studs) of a part's face
local function faceDims(size, face)
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	end
	return size.X, size.Y
end
Signage.FaceDims = faceDims

-- the pixel density for a board h studs tall whose text takes `frac` of the height: the engine draws text
-- at 100 px at most, so a tall board at a high density leaves its name small (a 7-stud banner at 40 px
-- per stud: 100 px of 280). The sign is drawn at the density that lets TextScaled fill its box.
function Signage.PPS(h, frac)
	return math.clamp(math.floor(96 / math.max(0.05, h * (frac or 0.6))), 8, 50)
end

-- a SurfaceGui lockup on a part's face. opts: those of Lockup plus
--   bg     false: no board colour (transparent, the part's own colour shows);  a Color3: that colour
--   light  LightInfluence (default 0: lit at night);  bright  Brightness;  maxDist  MaxDistance (default 600)
--   pps    pixels per stud (default: from the face's height, Signage.PPS);  name  the SurfaceGui's name
function Signage.Board(part, face, loc, opts)
	opts = opts or {}
	loc = Signage.Get(loc) or Signage.ById.gym
	face = face or Enum.NormalId.Front
	local w, h = faceDims(part.Size, face)
	local sg = Instance.new("SurfaceGui")
	sg.Name = opts.name or "Signage"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = opts.pps or Signage.PPS(h, 0.6)
	sg.LightInfluence = opts.light or 0
	sg.Brightness = opts.bright or 1
	sg.MaxDistance = opts.maxDist or 600
	sg.ClipsDescendants = true
	sg.AlwaysOnTop = false
	sg:SetAttribute("Location", loc.id)
	if opts.bg ~= false then
		new("Frame", { Name = "Board", BackgroundColor3 = opts.bg or loc.bg, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, sg)
	end
	local o = table.clone(opts)
	o.aspect = w / math.max(0.05, h)
	Signage.Lockup(sg, loc, o)
	sg.Parent = part
	return sg
end

-- the same board on several faces (a hanging sign read from both sides)
function Signage.Boards(part, faces, loc, opts)
	local out = {}
	for _, f in ipairs(faces) do
		table.insert(out, Signage.Board(part, f, loc, opts))
	end
	return out
end

-- the badge's layout for a height h: pad, the tile's side, the gap to the words, the wordmark's and the sub
-- line's text sizes (sub = nil when the badge is too short for a readable second line), and the width the
-- badge takes with the words `text` (an estimate from Typography.Em: the sign face's capitals and spaces run
-- about 0.46 em, the sub line's 0.76)
function Signage.BadgeMetrics(h, minText, text, sub)
	h = h or 28
	minText = minText or 9
	local pad = math.floor(h * 0.14)
	local ts = h - pad * 2
	local m = { h = h, pad = pad, tile = ts, gap = math.floor(h * 0.3) }
	local subSize = math.floor(h * 0.26)
	m.sub = (sub and h >= 40 and subSize >= minText) and subSize or nil
	m.word = math.max(minText, math.floor(h * (m.sub and 0.42 or 0.46)))
	local wordW = #tostring(text or "") * m.word * Typography.Em.sign
	if m.sub then
		wordW = math.max(wordW, #tostring(sub) * m.sub * Typography.Em.signSub)
	end
	m.width = pad + ts + m.gap + math.ceil(wordW) + pad * 2 + 2
	return m
end

-- a menu badge h px tall (Offset layout; the text sizes follow h). opts:
--   sub      false: wordmark only;  subText: another sub line;  text: another wordmark
--   w        a fixed width (else the badge hugs its content);  minText: the smallest text size (a readability floor)
--   plain    true: no fill, just the tile and the words (inline in a text row)
--   button   true: a TextButton (hover / selection by the caller)
-- Returns the badge, its wordmark label and its metrics (Signage.BadgeMetrics)
function Signage.Badge(parent, loc, h, opts)
	opts = opts or {}
	loc = Signage.Get(loc) or Signage.ById.gym
	h = h or 28
	local words = opts.text or loc.short
	local subLine = opts.sub ~= false and (opts.subText or loc.sub) or nil
	local m = Signage.BadgeMetrics(h, opts.minText, words, subLine)
	local hasSub = m.sub ~= nil
	local pad = m.pad
	local f = new(opts.button and "TextButton" or "Frame", { Name = opts.Name or ("Badge_" .. loc.id), BackgroundColor3 = loc.bg, BackgroundTransparency = opts.plain and 1 or 0, BorderSizePixel = 0,
		Size = UDim2.fromOffset(opts.w or 0, h), AutomaticSize = opts.w and Enum.AutomaticSize.None or Enum.AutomaticSize.X, LayoutOrder = opts.order or 0, ZIndex = opts.ZIndex or 1 })
	if opts.button then
		f.Text = ""
		f.AutoButtonColor = false
	end
	for _, k in ipairs({ "Position", "AnchorPoint" }) do
		if opts[k] ~= nil then
			f[k] = opts[k]
		end
	end
	f:SetAttribute("Location", loc.id)
	if not opts.plain then
		new("UICorner", { CornerRadius = UDim.new(0, math.max(4, math.floor(h * 0.22))) }, f)
		new("UIStroke", { Color = loc.accent or loc.fg, Transparency = 0.6, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	end
	local ts = m.tile
	local t = new("Frame", { Name = "Tile", BackgroundColor3 = loc.accent or loc.fg, BorderSizePixel = 0, Size = UDim2.fromOffset(ts, ts), Position = UDim2.fromOffset(pad, pad), ZIndex = f.ZIndex + 1 }, f)
	new("UICorner", { CornerRadius = UDim.new(0, math.max(3, math.floor(ts * 0.22))) }, t)
	Signage.Glyph(t, loc.icon, loc.bg, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex + 2 })
	local x = pad + ts + m.gap
	local fg = opts.plain and (opts.fg or WHITE) or loc.fg
	local wordSize = m.word
	local right = opts.w and UDim2.new(1, -(x + pad), 0, 0) or nil
	local wm = new("TextLabel", Typography.Props("sign", { Name = "Wordmark", BackgroundTransparency = 1, BorderSizePixel = 0, TextSize = wordSize, Text = words, TextColor3 = fg,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false, TextTruncate = opts.w and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		Position = UDim2.fromOffset(x, hasSub and pad - 1 or 0), Size = right and UDim2.new(1, -(x + pad + 2), 0, hasSub and wordSize + 2 or h) or UDim2.fromOffset(0, hasSub and wordSize + 2 or h),
		AutomaticSize = right and Enum.AutomaticSize.None or Enum.AutomaticSize.X, ZIndex = f.ZIndex + 1 }), f)
	if hasSub then
		new("TextLabel", Typography.Props("signSub", { Name = "Sub", BackgroundTransparency = 1, BorderSizePixel = 0, TextSize = m.sub, Text = subLine, TextColor3 = fg,
			TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(x, pad + wordSize), Size = right and UDim2.new(1, -(x + pad + 2), 0, h - pad * 2 - wordSize) or UDim2.fromOffset(0, h - pad * 2 - wordSize),
			AutomaticSize = right and Enum.AutomaticSize.None or Enum.AutomaticSize.X, ZIndex = f.ZIndex + 1 }), f)
	end
	if not opts.w then
		-- the hug: the wordmark's right edge plus the padding (AutomaticSize X on the badge ends at the
		-- widest child; the padding is a spacer so the words never touch the edge)
		new("UIPadding", { PaddingRight = UDim.new(0, pad * 2 + 2) }, f)
	end
	f.Parent = parent
	return f, wm, m
end

return Signage
