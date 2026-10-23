-- Hub: the Career Hub window.
-- Career (offers, camp, fight night), Training (condition, face, soreness, food, sleep, every
-- activity), Body (physique badge, every muscle, soreness, veins, FLEX), Stats, Gym (facility tier,
-- upgrade / repair equipment), Gear (gloves, shoes, wraps, mouthguards, robes), Coaches, Sponsors
-- (deals and offers), Life (home, travel, garage, fame), Rankings, Rivals, Shop, Legacy.
-- Gamepad: the D-pad moves the selection (UI kit), A presses, B closes, LB / RB (L1 / R1) step through the
-- tabs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
-- the opponents' ring traits as the scouting report knows them (Traits.ScoutView)
local Traits = require(Shared:WaitForChild("Traits"))
local UI = require(Shared:WaitForChild("UI"))
local Signage = require(Shared:WaitForChild("Signage"))
local State = require(script.Parent:WaitForChild("State"))
local FighterCard = require(script.Parent:WaitForChild("FighterCard"))
local BodyMap = require(script.Parent:WaitForChild("BodyMap"))
-- the Muscle Progression screen (3D figure, groups, growth graphs); registers State.open.Muscle
local okMuscle, MuscleScreen = pcall(require, script.Parent:WaitForChild("MuscleScreen"))
if not okMuscle then
	MuscleScreen = nil
end
local Flags = require(script.Parent:WaitForChild("Flags"))
-- the training programme's rules (plans, camps, mastery, goals, coach personas): optional, nil-safe
local okTP, TP = pcall(function()
	return require(Shared:WaitForChild("TrainingPlan", 5))
end)
if not okTP then
	TP = nil
end
-- the Tournaments tab (bracket, calendar, belts): optional, a broken module leaves the tab with a notice
local okTourney, TourneyUI = pcall(require, script.Parent:WaitForChild("TourneyUI"))
if not okTourney then
	TourneyUI = nil
end
-- the tournament calendar (the Career dashboard's schedule): optional
local okTD, TD = pcall(function()
	return require(Shared:WaitForChild("Tournaments", 5))
end)
if not okTD or type(TD) ~= "table" or type(TD.Calendar) ~= "function" then
	TD = nil
end
local T = UI.Theme
local rec = State.rec

local Hub = {}
local shade, win, content
local tab = "Career"
-- every tab rebuild (Hub.RenderNow) bumps it; a tab that waited on the server stops when it is stale (closed,
-- re-rendered or rebuilt for another screen size meanwhile), so no rows land in a destroyed or newer list
local renderId = 0
local function stale(body, id)
	return id ~= renderId or not body.Parent
end
local TABS = { "Career", "Tournaments", "Training", "Body", "Stats", "Gym", "Gear", "Coaches", "Sponsors", "Life", "Rankings", "Rivals", "PvP", "Shop", "Legacy" }
Hub.Tabs = TABS -- every tab (the side navigation groups them in NAV)
-- the side navigation, grouped like a sports game's career menu
local NAV = {
	{ "CAREER", { "Career", "Tournaments", "Rankings", "Rivals", "PvP", "Legacy" } },
	{ "TRAINING", { "Training", "Body", "Stats", "Gym", "Coaches" } },
	{ "LIFE", { "Gear", "Sponsors", "Life", "Shop" } },
}
local NAV_ICONS = {
	Career = "glove", Training = "dumbbell", Body = "heart", Stats = "chart", Gym = "home",
	Gear = "shield", Coaches = "people", Sponsors = "coin", Life = "home", Rankings = "trophy",
	Rivals = "people", PvP = "glove", Shop = "bag", Legacy = "crown", Tournaments = "belt",
}
-- (the phone's narrow rail: a shorter label where the tab's name would not fit)
local RAIL_LABELS = { Tournaments = "Events", Rankings = "Ranks", Coaches = "Corner", Sponsors = "Deals", Training = "Train" }
local TAB_HINTS = {
	Career = "Your next step toward a world title.", Training = "Build strength. Sharpen your craft.",
	Body = "Track your physique and recovery.", Stats = "Know your strengths. Find your edge.",
	Gym = "Build a gym worthy of a champion.", Gear = "Choose the kit for your next fight.",
	Coaches = "Build your corner team.", Sponsors = "Turn your reputation into opportunity.",
	Life = "Your life beyond the ropes.", Rankings = "See where you stand in the world.",
	Rivals = "Scout the competition.", PvP = "Test yourself against other players.",
	Shop = "Equip your journey to the top.", Legacy = "Every round becomes part of your story.",
	Tournaments = "Eight boxers, three nights, one belt.",
}
local tabButtons = {}

local function money(n)
	return Config.Money(n)
end

-- 1234567 -> "1,234,567"
local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- social following derived from fame and wins (display only)
local function followers(P)
	local pop = tonumber(P.popularity) or 0
	local w = P.record and tonumber(P.record.w) or 0
	return math.floor(pop * pop * 950 + w * 120)
end
Hub.Followers = followers

local function rgb(t, fallback)
	if type(t) == "table" and tonumber(t[1]) then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return fallback or T.panel2
end

local function ownsAny(owned, list)
	for _, id in ipairs(list or {}) do
		if owned and owned[id] then
			return true
		end
	end
	return false
end

-- the player's best home (Summary sends P.home; derive it for older servers)
local function bestHome(P)
	if P.home then
		return P.home
	end
	for _, id in ipairs({ "Mansion", "House", "Apartment" }) do
		if P.owned and P.owned[id] then
			return id
		end
	end
	return nil
end

local function rankText(ranks)
	local parts = {}
	for _, org in ipairs(Config.Orgs) do
		local r = ranks and ranks[org]
		if r then
			table.insert(parts, org .. " " .. (r == "C" and "CHAMP" or ("#" .. r)))
		end
	end
	return #parts > 0 and table.concat(parts, "  ") or "Unranked"
end

local function stakesText(o)
	local s = {}
	for _, x in ipairs(o.stakes or {}) do
		table.insert(s, x)
	end
	for _, x in ipairs(o.playerStakes or {}) do
		if not table.find(s, x) then
			table.insert(s, x)
		end
	end
	return s
end

-- a control's height on touch: never under a fingertip (UI.MinHit: 44 screen px under obj's scale)
local function hit(obj, h)
	return math.max(h, UI.MinHit(obj))
end

-- does a caption of design `size` fit `width` design px at obj's readability floor? (a line that
-- would end in "..." takes a shorter form instead)
local function textW(text, px, font)
	-- capitals run ~0.8 em in the bold face ("KNOCKOUT POWER" 10.5 em), wider than the kit's 0.6 em
	-- floor for body text: count them (digits ~0.64, spaces and marks ~0.34)
	local _, caps = string.gsub(text, "%u", "")
	local _, digits = string.gsub(text, "%d", "")
	local rest = (utf8.len(text) or #text) - caps - digits
	return math.max(UI.TextWidth(text, px, font), math.ceil(px * (caps * 0.8 + digits * 0.64 + rest * 0.34)))
end
local function fits(obj, text, size, width, font)
	return textW(text, math.max(size, UI.TextFloor(UI.ScaleOf(obj))), font) <= width
end

local function act(text, color, fn, width, icon)
	return function(parent)
		return UI.Button(parent, text, { Size = UDim2.new(0, width or 170, 1, 0), BackgroundColor3 = color or T.panel2, TextColor3 = (color == T.gold) and T.bg or T.text, TextSize = 14, icon = icon }, fn)
	end
end

local function buttons(parent, list, h)
	local row = UI.Row(parent, hit(parent, h or 36))
	for _, make in ipairs(list) do
		make(row)
	end
	return row
end

-- a sponsor's logo as a little coloured badge (bg / fg / text from Catalog.Sponsors logo). A local brand that
-- owns a Main Street shop carries the shop's icon tile (Shared.Signage), so the chip matches the shop front.
local function logoChip(parent, def, w, h)
	def = type(def) == "table" and def or {}
	local logo = type(def.logo) == "table" and def.logo or def
	w, h = w or 130, h or 40
	local fg = rgb(logo.fg, T.text)
	local f = UI.Frame(parent, { Name = "LogoChip", Size = UDim2.fromOffset(w, h), BackgroundColor3 = rgb(logo.bg, T.panel2) })
	UI.Corner(f, UI.R.sm)
	UI.Stroke(f, fg, 1, 0.7)
	UI.Gradient(f, { Color3.new(1, 1, 1), Color3.fromRGB(214, 214, 214) }, 90)
	local loc = def.shop and Signage.ByShop[string.upper(def.shop)]
	local x = 6
	if loc then
		local ts = h - 12
		local tile = UI.Frame(f, { Name = "Tile", Size = UDim2.fromOffset(ts, ts), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = fg })
		UI.Corner(tile, math.floor(ts * 0.22))
		Signage.Glyph(tile, loc.icon, rgb(logo.bg, T.panel2), { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		x = 6 + ts + 6
	end
	local mark = UI.Text(f, tostring(logo.text or "?"), { Name = "Wordmark", Font = T.bold, TextScaled = true, TextColor3 = fg, Size = UDim2.new(1, -(x + 6), 0, math.floor(h * 0.5)), Position = UDim2.fromOffset(x, logo.glyph and 4 or math.floor(h * 0.25)),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = loc and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center, TextWrapped = false })
	UI.New("UITextSizeConstraint", { MaxTextSize = math.floor(h * 0.42), MinTextSize = 9, Parent = mark })
	if logo.glyph then
		local gl = UI.Text(f, tostring(logo.glyph), { Name = "Glyph", Font = T.semi, TextScaled = true, TextColor3 = fg, TextTransparency = 0.25, Size = UDim2.new(1, -(x + 6), 0, math.floor(h * 0.3)), Position = UDim2.fromOffset(x, math.floor(h * 0.56)),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = loc and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center, TextWrapped = false })
		UI.New("UITextSizeConstraint", { MaxTextSize = math.floor(h * 0.26), MinTextSize = 8, Parent = gl })
	end
	return f
end

-- server travel (TravelHome / LeaveHome / TravelPlace): close the Hub on success
local function travel(action, ...)
	local r = State.req(action, ...)
	if r.ok then
		Hub.Close()
	else
		State.toast(r.err or "Can't go there right now.", T.red)
	end
	return r.ok
end

local function result(r, okText)
	if r.ok then
		if okText then
			State.toast(okText, T.green)
		end
	else
		State.toast(r.err or "Can't do that", T.red)
	end
	return r.ok
end

------------------------------------------------------------------------
-- Boxer scouting card
------------------------------------------------------------------------
local function showBoxer(id)
	local res = State.req("GetBoxer", id)
	if not res.ok then
		return
	end
	local b = res.boxer
	local s
	local function close()
		if s then
			s:Destroy()
			s = nil
		end
		if State.windows.BoxerCard == close then
			State.windows.BoxerCard = nil
		end
	end
	-- one card at a time, and a window every other opener closes (State.closeAll): walking to the
	-- barber or a store with a card up used to open that window underneath it
	if State.windows.BoxerCard then
		pcall(State.windows.BoxerCard)
	end
	local _, _, body
	s, _, body = UI.Window(State.gui, "BoxerCard", 560, 640, b.name, { onClose = close, z = 20, kicker = "SCOUTING REPORT", accent = T.red })
	s.ZIndex = 20
	State.windows.BoxerCard = close
	local top = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	Flags.Draw(top, b.nat, { Size = UDim2.fromOffset(33, 22) })
	UI.Text(top, string.format("\"%s\"  ·  %s  ·  Age %d", b.nick, b.nat, b.age), { Font = T.semi, TextColor3 = T.gold, TextSize = 14, Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -44, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local strip = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64) })
	UI.List(strip, 8, true)
	UI.Stat(strip, string.format("%d-%d-%d", b.record.w, b.record.l, b.record.d), "RECORD", { Size = UDim2.new(0.36, -8, 1, 0), order = 1, valueSize = 28, scaled = true, icon = "glove" })
	UI.Stat(strip, tostring(b.record.ko), "KOS", { Size = UDim2.new(0.2, -8, 1, 0), order = 2, valueSize = 28, valueColor = T.red, icon = "ko" })
	UI.Stat(strip, tostring(b.overall), "OVERALL", { Size = UDim2.new(0.22, -8, 1, 0), order = 3, valueSize = 28, valueColor = T.gold, icon = "star" })
	UI.Stat(strip, tostring(math.floor(b.heat or 0)), "RIVALRY", { Size = UDim2.new(0.22, -8, 1, 0), order = 4, valueSize = 28, icon = "flame" })
	UI.Line(body, string.format("%s  ·  %s  ·  %s", b.style, b.archetype ~= "" and b.archetype or "?", b.personality), { TextColor3 = T.sub, TextSize = 14 })
	local scout = Traits.ScoutText(Traits.ScoutView(b))
	if scout then
		UI.Line(body, "TRAITS: " .. scout, { TextColor3 = T.orange, Font = T.semi, TextSize = 14 })
	end
	UI.Line(body, "Rankings: " .. rankText(b.ranks), { Font = T.semi, TextSize = 14 })
	if b.belts and #b.belts > 0 then
		UI.Line(body, "HOLDS: " .. table.concat(b.belts, "  ·  "), { TextColor3 = T.gold, Font = T.semi })
	end
	if type(b.tbelts) == "table" and #b.tbelts > 0 then
		UI.Line(body, "TOURNAMENTS WON: " .. table.concat(b.tbelts, "  ·  "), { TextColor3 = T.gold, TextSize = 13 })
	end
	if b.h2h.w + b.h2h.l + b.h2h.d > 0 then
		UI.Line(body, string.format("Head to head: you %d-%d them (%d draws)", b.h2h.w, b.h2h.l, b.h2h.d), { TextColor3 = T.red, Font = T.semi })
	end
	local st = UI.Card(body)
	for _, k in ipairs(Config.StatKeys) do
		UI.StatRow(st, Config.StatNames[k], b.stats[k], 99, T.red)
	end
end
Hub.ShowBoxer = showBoxer
State.open.BoxerCard = showBoxer

-- the opponent as a fight-poster row: flag, name in the display face, record and OVR on the right
local function oppBlock(parent, o)
	local row = UI.Frame(parent, { Name = "Opponent", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 54) })
	Flags.Draw(row, o.nat, { Size = UDim2.fromOffset(36, 24), Position = UDim2.fromOffset(0, 6) })
	UI.Title(row, string.upper(o.name), { TextSize = 30, Position = UDim2.fromOffset(46, -2), Size = UDim2.new(1, -230, 0, 34), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(row, (o.nick and o.nick ~= "") and ('"' .. string.upper(o.nick) .. '"') or "", { Face = "displayMed", TextSize = 15, TextColor3 = T.gold, Position = UDim2.fromOffset(46, 32),
		Size = UDim2.new(1, -230, 0, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(row, string.format("%d-%d-%d", o.record.w, o.record.l, o.record.d), { Face = "number", TextSize = 30, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, -2),
		Size = UDim2.fromOffset(120, 34), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	UI.Text(row, string.format("%d KO", o.record.ko), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 34),
		Size = UDim2.fromOffset(120, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	local ovr = UI.Frame(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(72, 48), BackgroundColor3 = T.ink, BackgroundTransparency = 0.3 })
	UI.Corner(ovr, UI.R.md)
	UI.Stroke(ovr, T.red, 1, 0.4)
	UI.Text(ovr, tostring(o.overall), { Face = "number", TextSize = 28, TextColor3 = T.text, Size = UDim2.new(1, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	UI.Text(ovr, "OVR", { Font = T.semi, TextSize = 9, TextColor3 = T.sub, Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 10), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	UI.Line(parent, string.format("%s  ·  %s  ·  Age %d  ·  %s", o.style, o.archetype or "", o.age, rankText(o.ranks)), { TextColor3 = T.sub, TextSize = 13 })
	-- the scouting report on his ring traits (the hidden ones are revealed in the fight)
	local scout = Traits.ScoutText(Traits.ScoutView(o))
	if scout then
		UI.Line(parent, "SCOUTING: " .. scout, { TextColor3 = T.orange, Font = T.semi, TextSize = 13 })
	end
	if o.h2h and (o.h2h.w + o.h2h.l + o.h2h.d) > 0 then
		UI.Line(parent, string.format("Rivalry: you %d-%d them (%d draws)  ·  heat %d", o.h2h.w, o.h2h.l, o.h2h.d, math.floor(o.heat or 0)), { TextColor3 = T.red, Font = T.semi, TextSize = 13 })
	end
	if o.belts and #o.belts > 0 then
		UI.Line(parent, "HOLDS: " .. table.concat(o.belts, "  ·  "), { TextColor3 = T.gold, Font = T.semi, TextSize = 13 })
	end
end

-- "AMATEUR BOUT · 3 ROUNDS" and the venue's badge (its sign's lockup) on the left, the purse on the right
local function fightHeader(parent, o, special)
	local loc = Signage.Get(o.venue) or Signage.Find(o.venueName)
	local bh = loc and UI.LocationBadgeHeight(parent, 20) or 20
	local row = UI.Frame(parent, { Name = "FightHeader", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.max(22, bh + 2)) })
	local line = string.format("%s  ·  %d ROUNDS", o.kind:upper(), o.rounds)
	if not loc and o.venueName and o.venueName ~= "" then
		line = line .. "  ·  " .. string.upper(o.venueName)
	end
	local lineW = loc and math.min(textW(line, 12, T.semi) + 8, 260) or nil
	UI.Text(row, line, { Font = T.semi, TextSize = 12, TextColor3 = special and T.gold or T.sub,
		Size = lineW and UDim2.new(0, lineW, 1, 0) or UDim2.new(1, -150, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if loc then
		UI.LocationBadge(row, loc, 20, { sub = false, Position = UDim2.fromOffset(lineW + 4, 1) })
	end
	UI.Text(row, "PURSE  " .. money(o.purse), { Face = "number", TextSize = 18, TextColor3 = T.green, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(150, 24), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	return row
end

local function quote(parent, text)
	if not text or text == "" then
		return
	end
	UI.Line(parent, "\"" .. text .. "\"", { TextColor3 = Color3.fromRGB(255, 170, 170), TextSize = 14, Font = T.font })
end

------------------------------------------------------------------------
-- The Career dashboard: record strip, schedule timeline, location tiles
------------------------------------------------------------------------
-- the record strip: a square ledger across the page (name, then one cell per number, 1 px rules between)
local function recordStrip(body, P, compact)
	local id = P.identity or {}
	local ri = FighterCard.RecordInfo(P)
	local rankT, champ = FighterCard.BestRank(P)
	local h = compact and 64 or 78
	local strip = UI.Frame(body, { Name = "RecordStrip", BackgroundColor3 = T.panel, Size = UDim2.new(1, -8, 0, h) })
	UI.Stroke(strip, T.line, 1, 0)
	-- the corner colour down the outer edge (the player's red corner)
	UI.Frame(strip, { Name = "Corner", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = T.red })
	local nameW = compact and 0.34 or 0.3
	local nameCell = UI.Frame(strip, { Name = "Name", BackgroundTransparency = 1, Size = UDim2.new(nameW, 0, 1, 0) })
	Flags.Draw(nameCell, id.nationality, { Size = UDim2.fromOffset(24, 16), Position = UDim2.fromOffset(16, compact and 10 or 14) })
	UI.Text(nameCell, string.upper(string.format("%s  ·  %s", P.className or "", P.tierName or "")), { Font = T.semi, TextSize = 11, TextColor3 = T.gold,
		Position = UDim2.fromOffset(48, compact and 10 or 14), Size = UDim2.new(1, -56, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local nameSize = compact and 18 or 22
	local room = math.max(120, (compact and 600 or 1000) * nameW - 28)
	while nameSize > 14 and UI.TextWidth(id.name or "", nameSize, "display") > room do
		nameSize -= 1
	end
	UI.Text(nameCell, id.name or "", { Face = "display", TextSize = nameSize, Position = UDim2.fromOffset(16, compact and 28 or 34), Size = UDim2.new(1, -24, 0, nameSize + 6),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local cells = {
		{ ri.text, "RECORD" },
		{ tostring(ri.ko), "KOS", ri.ko > 0 and T.red or nil },
		{ tostring(P.overall or 0), "OVR" },
		{ rankT == "UNRANKED" and "—" or rankT, "RANKING", champ and T.gold or nil },
	}
	if not compact then
		table.insert(cells, { money(P.money or 0), "PURSE", T.gold })
		table.insert(cells, { commas(followers(P)), "FOLLOWERS" })
	end
	local cw = (1 - nameW) / #cells
	for i, c in ipairs(cells) do
		local x = nameW + (i - 1) * cw
		UI.Frame(strip, { Name = "Rule" .. i, Position = UDim2.new(x, 0, 0, 10), Size = UDim2.new(0, 1, 1, -20), BackgroundColor3 = T.line })
		local cell = UI.Frame(strip, { Name = "Cell" .. i, BackgroundTransparency = 1, Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(cw, 0, 1, 0) })
		local v = UI.Text(cell, c[1], { Face = "number", TextSize = compact and 22 or 28, TextColor3 = c[3] or T.text, Position = UDim2.fromOffset(14, compact and 8 or 12),
			Size = UDim2.new(1, -22, 0, compact and 28 or 34), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = true })
		UI.New("UITextSizeConstraint", { MaxTextSize = compact and 22 or 28, MinTextSize = 12, Parent = v })
		UI.Text(cell, c[2], { Font = T.semi, TextSize = 11, TextColor3 = T.dim, Position = UDim2.new(0, 14, 1, compact and -22 or -26), Size = UDim2.new(1, -20, 0, 14),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	return strip
end

-- the schedule: the next DAYS days on one horizontal line (today at the left), with fight night and the
-- tournament start days marked on it, their labels in two lanes so neighbours never overlap
local DAYS = 14
local function scheduleTimeline(body, P, compact)
	local day = P.day or 1
	local events = {}
	if P.camp and P.camp.offer then
		local d = day + math.max(0, P.camp.daysLeft or 0)
		local opp = P.camp.offer.opp and P.camp.offer.opp.name
		table.insert(events, { d = d, text = opp and ("Fight night vs " .. opp) or "Fight night", color = T.red })
	end
	if TD then
		local okC, cal = pcall(TD.Calendar, day, 1)
		for _, e in ipairs(okC and cal or {}) do
			if e.start >= day and e.start < day + DAYS then
				table.insert(events, { d = e.start, text = tostring(e.def.name) .. (e.open and "  ·  entries open" or ""), color = e.open and T.gold or T.sub })
			end
		end
	end
	table.sort(events, function(a, b)
		return a.d < b.d
	end)
	local panel = UI.Frame(body, { Name = "Schedule", BackgroundColor3 = T.panel, Size = UDim2.new(1, -8, 0, compact and 110 or 120) })
	UI.Stroke(panel, T.line, 1, 0)
	UI.Kicker(panel, string.format("Schedule  ·  the next %d days", DAYS), nil, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 16) })
	local axisY = compact and 76 or 82
	local track = UI.Frame(panel, { Name = "Track", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 1, 0) })
	UI.Frame(track, { Name = "Axis", Position = UDim2.fromOffset(0, axisY), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line })
	local function xAt(d)
		return (d - day) / (DAYS - 1)
	end
	for k = 0, DAYS - 1 do
		local today = k == 0
		UI.Frame(track, { Name = "Tick" .. k, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(xAt(day + k), 0, 0, axisY - (today and 6 or 3)), Size = UDim2.fromOffset(1, today and 13 or 7),
			BackgroundColor3 = today and T.gold or T.line })
		if today or k % (compact and 4 or 2) == 0 then
			UI.Text(track, today and "Today" or ("Day " .. (day + k)), { Font = T.semi, TextSize = 11, TextColor3 = today and T.gold or T.dim, AnchorPoint = Vector2.new(today and 0 or 0.5, 0),
				Position = UDim2.new(xAt(day + k), today and -2 or 0, 0, axisY + 10), Size = UDim2.fromOffset(60, 14), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = today and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center, TextWrapped = false })
		end
	end
	if #events == 0 then
		UI.Text(panel, "Nothing booked yet. Sign a fight below, or enter a tournament.", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 18),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	for i, e in ipairs(events) do
		local x = xAt(e.d)
		local dot = UI.Frame(track, { Name = "Event" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, axisY), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = e.color, ZIndex = 3 })
		UI.Corner(dot, 2)
		local lane = (i - 1) % 2
		local ly = axisY - 20 - lane * 18
		UI.Frame(track, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 0, axisY - 4), Size = UDim2.fromOffset(1, 12 + lane * 18), BackgroundColor3 = e.color, BackgroundTransparency = 0.4 })
		-- the label runs away from the nearer end of the line, in the room between its marker and that end
		local right = x > 0.55
		UI.Text(track, string.format("Day %d  ·  %s", e.d, e.text), { Font = T.semi, TextSize = 12, TextColor3 = e.color == T.sub and T.text or e.color, AnchorPoint = Vector2.new(right and 1 or 0, 0.5),
			Position = UDim2.new(x, right and -6 or 6, 0, ly), Size = right and UDim2.new(x, -6, 0, 16) or UDim2.new(1 - x, -6, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	return panel
end

-- the places to go from here: one tile per destination (a tab of this window), what is waiting there on its second line
local function locationTiles(body, P, compact, goTab)
	local c = P.condition or {}
	local nextEvent
	if TD then
		local okC, cal = pcall(TD.Calendar, P.day or 1, 1)
		nextEvent = okC and cal and cal[1]
	end
	local home = bestHome(P)
	local tiles = {
		{ "Training", "dumbbell", "Gym floor", string.format("Energy %d  ·  fatigue %d", math.floor(c.energy or 0), math.floor(c.fatigue or 0)) },
		{ "Body", "heart", "Body", tostring(P.physique or "Physique") },
		{ "Tournaments", "belt", "Tournaments", nextEvent and string.format("%s  ·  day %d", tostring(nextEvent.def.name), nextEvent.start) or "The calendar" },
		{ "Rankings", "trophy", "Rankings", rankText(P.ranks) },
		{ "Gear", "shield", "Locker room", "Gloves, wraps, boots and robes" },
		{ "Life", "home", "Home", home and tostring(home) or "Find a place to live" },
	}
	local cols = compact and 2 or 3
	local rows = math.ceil(#tiles / cols)
	local tileH = math.max(compact and 56 or 64, hit(body, 44))
	local grid = UI.Frame(body, { Name = "Places", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, rows * tileH + (rows - 1) * 8) })
	local gap = 8
	for i, t in ipairs(tiles) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local b = UI.New("TextButton", { Name = "Go_" .. t[1], Text = "", AutoButtonColor = false, BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = i,
			Position = UDim2.new(col / cols, math.floor(col * gap / cols), 0, row * (tileH + gap)), Size = UDim2.new(1 / cols, -math.ceil(gap * (cols - 1) / cols), 0, tileH), Parent = grid })
		UI.Stroke(b, T.line, 1, 0)
		UI.Hover(b, { amount = 0.96, press = 0.985 })
		UI.Icon(b, UI.HasIcon(t[2]) and t[2] or "star", 18, T.gold, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
		UI.Text(b, t[3], { Face = "heading", TextSize = 14, Position = UDim2.new(0, 44, 0.5, -18), Size = UDim2.new(1, -72, 0, 18), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(b, t[4], { TextSize = 12, TextColor3 = T.sub, Position = UDim2.new(0, 44, 0.5, 2), Size = UDim2.new(1, -72, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Icon(b, "right", 12, T.dim, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0) })
		b.MouseButton1Click:Connect(function()
			goTab(t[1])
		end)
	end
	return grid
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local R = {}

R.Career = function(body, P)
	-- the dashboard (this tab's own shape): the record strip, the schedule line, the places to go, then the
	-- fight offers or the camp (compact: a short canvas, as compactHub below)
	local compact = UI.CanvasSize(State.gui).Y < 640
	recordStrip(body, P, compact)
	scheduleTimeline(body, P, compact)
	locationTiles(body, P, compact, function(name)
		tab = name
		Hub.RenderNow()
	end)
	-- fame & sponsors: the city reacts to these (fans, billboards, your logo on the trunks)
	local deals = {}
	if P.sponsors and P.sponsors.deals then
		for _, slot in ipairs(Catalog.SponsorSlots) do
			local d = P.sponsors.deals[slot]
			if d then
				table.insert(deals, d.name)
			end
		end
	end
	if #deals > 0 then
		UI.Line(body, "Sponsored by " .. table.concat(deals, ", "), { TextColor3 = T.green, Font = T.semi, TextSize = 13 })
	end
	local belts = {}
	for _, org in ipairs(Config.Orgs) do
		if P.belts[org] then
			table.insert(belts, org)
		end
	end
	if P.regional.regional then
		table.insert(belts, "Regional")
	end
	if P.regional.national then
		table.insert(belts, "National")
	end
	if #belts > 0 then
		UI.Line(body, "Titles: " .. table.concat(belts, "  ·  ") .. string.format("   (%d defences)", P.defenses), { TextColor3 = T.gold, Font = T.semi, TextSize = 14 })
	end
	if not P.storeOk then
		UI.Line(body, "Saving is off in this session (enable Studio API access or publish the game to save progress).", { TextColor3 = T.red, TextSize = 13 })
	end

	if P.camp then
		UI.Header(body, "FIGHT CAMP", T.red)
		local c = UI.Card(body, { stroke = T.red })
		local o = P.camp.offer
		fightHeader(c, o, true)
		if type(o.tourney) == "table" then
			-- a tournament bout: the event, the round, the belt for the final
			local trow = UI.Frame(c, { Name = "TourneyLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) })
			local iw = 0
			if TourneyUI then
				TourneyUI.BeltIcon(trow, o.tourney.id, 60, { Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
				iw = 68
			end
			UI.Text(trow, string.upper(string.format("%s  ·  %s%s", tostring(o.tourney.name or ""), tostring(o.tourney.roundName or ""), o.tourneyBelt and "  ·  FOR THE BELT" or "")),
				{ Face = "displayMed", TextSize = 16, TextColor3 = T.gold, Position = UDim2.fromOffset(iw, 0), Size = UDim2.new(1, -iw, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
					TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		oppBlock(c, o.opp)
		quote(c, o.talk)
		local stakes = stakesText(o)
		if #stakes > 0 then
			UI.Line(c, "On the line: the " .. table.concat(stakes, " and ") .. " world title" .. (#stakes > 1 and "s" or ""), { Font = T.semi, TextColor3 = T.gold, TextSize = 14 })
		end
		-- camp countdown and the weight cut
		local meters = UI.Frame(c, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
		UI.List(meters, 8, true)
		UI.Stat(meters, tostring(P.camp.daysLeft), "CAMP DAYS LEFT", { Size = UDim2.new(0.33, -6, 1, 0), order = 1, valueSize = 28, valueColor = P.camp.daysLeft <= 0 and T.gold or T.text, icon = "calendar" })
		UI.Stat(meters, string.format("%.1f", P.weight), string.format("WEIGHT / %d LBS", P.weightLimit), { Size = UDim2.new(0.33, -6, 1, 0), order = 2, valueSize = 28, valueColor = P.overWeight > 0 and T.red or T.green })
		UI.Stat(meters, money(o.purse), "PURSE", { Size = UDim2.new(0.34, -6, 1, 0), order = 3, valueSize = 28, valueColor = T.green, scaled = true, icon = "coin" })
		if P.overWeight > 0 then
			UI.Line(c, string.format("You are %.1f lbs over the limit. Burn fat with cardio or cut water in the sauna before fight night; missing weight costs stamina and %s.", P.overWeight, P.overWeight > 2 and "20% of your purse" or "no fine yet"), { TextColor3 = T.red, TextSize = 13 })
		end
		if #P.camp.log > 0 then
			UI.Line(c, "Camp so far: " .. table.concat(P.camp.log, ", "):sub(1, 220), { TextColor3 = T.sub, TextSize = 12 })
		end
		local ready = P.camp.daysLeft <= 0
		local tourneyWait = type(o.tourney) == "table" and not ready
		UI.Line(c, ready and "Camp is complete. It is fight night." or (tourneyWait and "A tournament bout is on its day: train, eat and sleep until then. Health and injuries carry over between rounds."
			or "Train at the gym, eat and sleep: each night is a camp day. You can also fight early, with fewer camp days behind you."), { TextColor3 = ready and T.gold or T.sub, TextSize = 13 })
		if tourneyWait then
			-- (the bracket does not move for one boxer: no early fight, the bracket is one tap away)
			buttons(c, {
				act("THE BRACKET", T.gold, function()
					tab = "Tournaments"
					Hub.RenderNow()
				end, 180),
				act("SCOUT", T.panel2, function()
					showBoxer(o.oppId)
				end, 110),
			}, 44)
		end
		local confirmEarly = false
		local fightBtn
		local _ = not tourneyWait and buttons(c, {
			function(row)
				fightBtn = UI.Button(row, ready and "FIGHT NIGHT (LIVE)" or "FIGHT NOW (EARLY)", { Size = UDim2.new(0, 230, 1, 0), BackgroundColor3 = T.red, TextSize = 16 }, function()
					if not ready and not confirmEarly then
						confirmEarly = true
						fightBtn.Text = "Confirm: Fight Early"
						return
					end
					local r = State.req("StartFight", "live")
					if r.ok then
						Hub.Close()
					else
						State.toast(r.err or "Can't start", T.red)
					end
				end)
			end,
			act("SIMULATE FIGHT", T.panel2, function()
				local r = State.req("StartFight", "sim")
				if r.ok then
					Hub.Close()
					if State.open.Result then
						State.open.Result(r)
					end
				else
					State.toast(r.err or "Can't simulate", T.red)
				end
			end, 180),
			act("SCOUT", T.panel2, function()
				showBoxer(o.oppId)
			end, 110),
		}, 44)
	else
		UI.Header(body, "FIGHT OFFERS")
		-- the guided debut, while it is still on offer (a refused or called-off start never loses it)
		if type(P.debut) == "table" and P.debut.offer == true and State.open.Debut then
			local dc = UI.Card(body, { stroke = T.gold })
			UI.Line(dc, "Your debut is waiting: a guided amateur bout, your coach in your ear.", { TextColor3 = T.gold, Font = T.semi, TextSize = 14 })
			UI.Button(dc, "FIGHT MY DEBUT", { Name = "OpenDebut", Size = UDim2.fromOffset(220, math.max(40, UI.MinHit(dc))), BackgroundColor3 = T.gold, TextColor3 = T.ink }, function()
				Hub.Close()
				State.open.Debut(P.debut)
			end)
		end
		local myId = renderId
		local res = State.req("GetOffers")
		if stale(body, myId) then
			return
		end
		if not res.ok then
			UI.Line(body, res.err or "No offers", { TextColor3 = T.red })
		else
			for i, o in ipairs(res.offers or {}) do
				local special = o.kind ~= "Pro Fight" and o.kind ~= "Amateur Bout"
				local c = UI.Card(body, { stroke = special and T.gold or nil })
				fightHeader(c, o, special)
				oppBlock(c, o.opp)
				quote(c, o.talk)
				local stakes = stakesText(o)
				if #stakes > 0 then
					UI.Line(c, "On the line: " .. table.concat(stakes, ", "), { TextColor3 = T.gold, TextSize = 13, Font = T.semi })
				end
				buttons(c, {
					act("ACCEPT FIGHT", T.gold, function()
						-- (the signed fight's profile push redraws the tab: a Render here drew the old profile
						-- first, one rebuild too many)
						result(State.req("AcceptOffer", i), "Fight signed. Training camp begins.")
					end, 180),
					act("SCOUT", T.panel2, function()
						showBoxer(o.oppId)
					end, 110),
				}, 40)
			end
			UI.Line(body, "Offers refresh every week (7 days). Rivals with heat call you out for rematches and trilogies.", { TextColor3 = T.sub, TextSize = 13 })
		end
		local wc = UI.Card(body)
		UI.Line(wc, "Weight class: " .. P.className .. string.format("  ·  limit %d lbs, you weigh %.1f", P.weightLimit, P.weight), { Font = T.semi, TextSize = 14 })
		UI.Line(wc, "Moving divisions vacates any world titles you hold.", { TextColor3 = T.sub, TextSize = 13 })
		buttons(wc, {
			act("MOVE DOWN", T.panel2, function()
				result(State.req("ChangeWeightClass", -1), "Moved down a division.")
			end, 140),
			act("MOVE UP", T.panel2, function()
				result(State.req("ChangeWeightClass", 1), "Moved up a division.")
			end, 140),
		})
	end
	if #P.history > 0 then
		UI.Header(body, "RECENT FIGHTS")
		for i = 1, math.min(8, #P.history) do
			local h = P.history[i]
			local col = h.outcome == "win" and T.green or (h.outcome == "loss" and T.red or T.sub)
			local row = UI.Frame(body, { BackgroundColor3 = T.panel, BackgroundTransparency = 0.2, Size = UDim2.new(1, -8, 0, 36) })
			UI.Corner(row, UI.R.md)
			local tag = UI.Frame(row, { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(28, 24), BackgroundColor3 = col })
			UI.Corner(tag, 4)
			UI.Text(tag, h.outcome == "win" and "W" or (h.outcome == "loss" and "L" or "D"), { Face = "number", TextSize = 16, TextColor3 = T.ink, Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
			UI.Text(row, string.format("vs %s  ·  %s R%d", h.opp, h.method, h.round), { Font = T.semi, TextSize = 14, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(0.6, -46, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.Text(row, string.format("Day %d  ·  %s%s", h.day or 0, h.kind, h.venue and ("  ·  " .. h.venue) or ""), { TextSize = 12, TextColor3 = T.sub, Position = UDim2.new(0.6, 0, 0, 0),
				Size = UDim2.new(0.4, -12, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
	end
end

R.Tournaments = function(body, P)
	if not TourneyUI then
		UI.Line(body, "Tournaments are unavailable right now.", { TextColor3 = T.sub })
		return
	end
	TourneyUI.Tab(body, P, {
		open = function(name)
			tab = name
			Hub.RenderNow()
		end,
	})
end

local AREAS = { "Boxing Area", "Weight Room", "Cardio Room", "Outdoors", "Pool", "Recovery Area" }
-- what an exercise builds, strongest first; with a width, as many whole stats as fit at the text
-- floor and "+N more" for the rest (a narrow card never cuts a stat name)
local function gainsText(a, obj, size, width)
	local parts = {}
	for i, k in ipairs(Config.StatKeys) do
		local w = a.gains and a.gains[k]
		if w then
			table.insert(parts, { i = i, w = w, text = Config.StatNames[k] .. (w >= 0.9 and " ++" or " +") })
		end
	end
	table.sort(parts, function(x, y)
		if x.w ~= y.w then
			return x.w > y.w
		end
		return x.i < y.i
	end)
	local texts = {}
	for i, p in ipairs(parts) do
		texts[i] = p.text
	end
	for n = #texts, 1, -1 do
		local s = table.concat(texts, ", ", 1, n) .. (n < #texts and string.format(", +%d more", #texts - n) or "")
		if not width or n == 1 or fits(obj, s, size, width) then
			return s
		end
	end
	return ""
end


-- the muscle parts an activity builds (Config.ExerciseTargets via act.parts), strongest first:
-- { { id, w, k = w / strongest } }
local function topParts(a, n)
	local list = {}
	for id, w in pairs(type(a.parts) == "table" and a.parts or {}) do
		table.insert(list, { id = id, w = tonumber(w) or 0 })
	end
	table.sort(list, function(x, y)
		if x.w ~= y.w then
			return x.w > y.w
		end
		return x.id < y.id
	end)
	local out = {}
	local top = list[1] and list[1].w or 1
	for i = 1, math.min(n or 3, #list) do
		list[i].k = top > 0 and list[i].w / top or 0
		table.insert(out, list[i])
	end
	return out
end

local function compactHub()
	return UI.CanvasSize(State.gui).Y < 640
end

-- the frame's potential (cap on the 0..100 muscle scale)
local function frameCap(P)
	-- the frame the server builds the boxer on (P.frame = Training.Frame), else the saved look's
	local id = type(P.frame) == "string" and P.frame or (P.appearance and P.appearance.body and P.appearance.body.frame) or ""
	local frameDef = Config.FindById(Config.BodyTypes, id) or Config.BodyTypes[2]
	return 100 * (frameDef.potential or 1), frameDef
end

local function partLevel(P, id)
	return tonumber(Config.PartValue and Config.PartValue(P.body, id) or (P.body and P.body[id])) or 0
end

-- one condition meter tile: big number, caption, bar
local METER_ICONS = { ENERGY = "energy", HYDRATION = "water", NUTRITION = "food", FATIGUE = "pulse" }
local function meterTile(parent, caption, value, color, order)
	local f, v, c = UI.Stat(parent, tostring(math.floor(value)), caption, { Size = UDim2.new(0.25, -8, 1, 0), order = order, valueSize = 30, valueColor = color,
		icon = METER_ICONS[caption], iconColor = color, iconSize = 18 })
	-- three rows: the number, its caption, the bar (the caption never runs under the bar)
	v.Size = UDim2.new(1, -42, 1, -40)
	c.Position, c.Size = UDim2.new(0, 12, 1, -32), UDim2.new(1, -24, 0, 14)
	UI.Meter(f, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 5) }, { color = color }):set(value / 100)
	return f, v
end

-- the muscle colour for "how hard this exercise works it" (the body map's highlight)
local WORK_IDLE = BodyMap.Colors.muscle
local function workColor(k)
	return WORK_IDLE:Lerp(T.red, 0.35 + 0.65 * math.clamp(k, 0, 1))
end

-- an exercise card: what it builds (stats), the muscles it works as level bars against the frame's
-- potential (coloured by how hard it works them), your personal best and sessions, a body map thumbnail
local CARD_H = 166
-- The exercise cards' body-map thumbnails are built only for the cards in (or just below) the view: the
-- Training tab holds thirty cards, and each thumbnail is a painted figure (an EditableImage and its mask, or a
-- hundred frames without one) - built all at once they were two thirds of the tab's objects and most of its
-- build time. lazyMaps = { tile, build }; the view's scroll (Hub.Open's listener) and every render pass check
-- which cards came into the view and build theirs once.
local lazyMaps = {}
local lazyQueued = false
local function buildVisibleMaps()
	if not (content and content.Parent) or #lazyMaps == 0 then
		return
	end
	local top = content.AbsolutePosition.Y
	local bottom = top + content.AbsoluteSize.Y
	local margin = content.AbsoluteSize.Y * 0.5
	local keep = {}
	for _, e in ipairs(lazyMaps) do
		local t = e.tile
		if t.Parent then
			local y0 = t.AbsolutePosition.Y
			local y1 = y0 + t.AbsoluteSize.Y
			if y1 >= top - margin and y0 <= bottom + margin then
				e.build()
			else
				table.insert(keep, e)
			end
		end
	end
	lazyMaps = keep
end
local function queueVisibleMaps()
	if lazyQueued then
		return
	end
	lazyQueued = true
	task.defer(function()
		lazyQueued = false
		buildVisibleMaps()
	end)
end

local function exerciseCard(grid, a, P, order, cap)
	local st = Catalog.Stations[a.station]
	local lv = math.max(1, P.gym.levels[a.station] or 1)
	local lvName = st and st.levels[math.min(lv, #st.levels)].name or ""
	local cost = a.recovery and (a.price and (P.gym.levels.massage or 1) < 2 and money(a.price) or "free") or ("energy " .. (a.id == "Sparring" and "25-45" or tostring(a.energy)))
	local tile = UI.Frame(grid, { Name = "Activity", LayoutOrder = order, BackgroundColor3 = T.panel, BackgroundTransparency = 0.05 })
	UI.Corner(tile, UI.R.lg)
	UI.Stroke(tile, Color3.new(1, 1, 1), 1, 0.92)
	-- (gold: on today's plan / camp focus block)
	local onFocus = false
	local trv = type(P.training) == "table" and P.training or nil
	for _, f in ipairs(trv and trv.focus or {}) do
		if TP and TP.OnFocus(a.id, f) then
			onFocus = true
		end
	end
	local accent = UI.Frame(tile, { Name = onFocus and "FocusAccent" or "Accent", Size = UDim2.new(0, onFocus and 4 or 3, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = onFocus and T.gold or (a.recovery and T.blue or T.red) })
	UI.Corner(accent, 2)
	local THUMB_W = 78
	local right = THUMB_W + 22
	-- the cost chip's width at the text floor: the title ends before it (a long name shrinks to fit
	-- beside it before it is cut: "DOUBLE-END BAG" on a phone)
	local chipW = textW(string.upper(cost), math.max(12, UI.TextFloor(UI.ScaleOf(tile))), T.semi) + 18
	local title = UI.Text(tile, string.upper(a.name), { Face = "displayMed", TextSize = 20, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -(right + chipW + 24), 0, 24), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextScaled = true })
	UI.New("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 13, Parent = title })
	UI.Chip(tile, cost, a.recovery and T.blue or T.gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, 10), TextSize = 12 })
	local detail = UI.Text(tile, a.recovery and a.desc or gainsText(a), { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -(right + 12), 0, a.recovery and 52 or 18),
		AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = a.recovery == true, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the muscles it works: name, level against the potential (tick), the level number
	local listed = {}
	if not a.recovery then
		for i, e in ipairs(topParts(a, 3)) do
			listed[e.id] = e.w
			local y = 56 + (i - 1) * 21
			local v = partLevel(P, e.id)
			-- the name takes 40% of the card (a fixed 96 px cut "FRONT DELTS" at the phone's text floor)
			UI.Text(tile, string.upper(BodyMap.Short(e.id)), { Font = T.semi, TextSize = 12, TextColor3 = e.k >= 0.75 and T.text or T.sub, Position = UDim2.fromOffset(16, y), Size = UDim2.new(0.4, -16, 0, 18),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.LevelBar(tile, { Position = UDim2.new(0.4, 4, 0, y + 5), Size = UDim2.new(0.6, -(right + 44), 0, 7) }, { value = v, cap = cap, color = workColor(e.k) })
			UI.Text(tile, string.format("%d", math.floor(v + 0.5)), { Face = "number", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(right + 2), 0, y - 1),
				Size = UDim2.fromOffset(34, 18), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		end
	end
	-- personal best: the grade letter, the best session's quality as a bar, sessions logged
	local r = P.records and P.records[a.id]
	local sessions = type(r) == "table" and (tonumber(r.sessions) or 0) or 0
	local by = CARD_H - 36
	if sessions > 0 then
		local grade = Config.GradeFor(r.best)
		local rgb = Config.GradeInfo(grade).rgb
		local gcol = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		local pct = Config.QualityPct(r.best)
		UI.Text(tile, grade, { Face = "display", TextSize = 22, TextColor3 = gcol, Position = UDim2.fromOffset(16, by - 4), Size = UDim2.fromOffset(28, 26), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(tile, "BEST", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(48, by - 2), Size = UDim2.fromOffset(40, 12), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		-- the drill's mastery level (M0..M5) next to the best and the sessions
		local m = trv and type(trv.mastery) == "table" and trv.mastery[a.id] or nil
		local mtxt = m and string.format("  ·  M%d", m.lv or 0) or ""
		local numW = m and 124 or 88
		local _, set = UI.Bar(tile, { Position = UDim2.fromOffset(48, by + 13), Size = UDim2.new(1, -(right + 48 + numW + 4), 0, 6) }, gcol)
		set(pct / 100)
		UI.Text(tile, string.format("%d%%  ·  %d×%s", pct, sessions, mtxt), { Face = "number", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(right + 2), 0, by + 2),
			Size = UDim2.fromOffset(numW, 18), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
	local tried = sessions == 0 and UI.Text(tile, "NOT TRIED YET", { Font = T.semi, TextSize = 12, TextColor3 = T.dim, Position = UDim2.fromOffset(16, by + 2), Size = UDim2.new(1, -(right + 16), 0, 18),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the lines that depend on the card's width refit when the grid lays it out: whole stats, the
	-- station's name only where it fits whole
	local function refit()
		-- the card's design width: its share of the scaled root's (whatever the root's UIScale is)
		local rootW = State.gui.AbsoluteSize.X
		local w = rootW > 1 and tile.AbsoluteSize.X / rootW * UI.CanvasSize(State.gui).X or 0
		if w < 120 then
			return
		end
		if not a.recovery then
			detail.Text = gainsText(a, tile, 13, w - (right + 28))
		end
		if tried then
			local full = "NOT TRIED YET  ·  " .. string.upper(lvName)
			tried.Text = (lvName ~= "" and fits(tile, full, 12, w - (right + 32), T.semi)) and full or "NOT TRIED YET"
		end
	end
	refit()
	tile:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	-- the body map: what it works (recovery: the whole body, cool); a finger-high GO under it. Built when the
	-- card scrolls into the view (lazyMaps above)
	local goH = hit(tile, 32)
	local built = false
	table.insert(lazyMaps, { tile = tile, build = function()
		if built or not tile.Parent then
			return
		end
		built = true
		local ok, map = pcall(BodyMap.new, tile, { Size = UDim2.fromOffset(THUMB_W, math.min(100, CARD_H - goH - 30)), views = "front", labels = false, glow = false, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8) })
		if ok and map then
			if a.recovery then
				local all = {}
				for _, p in ipairs(Config.MuscleParts) do
					all[p.id] = 0.5
				end
				map:SetTargets(all, T.cyan, 1)
			else
				-- the thumbnail lights what the card lists (its three main muscles)
				map:SetTargets(listed, T.red)
			end
		end
	end })
	-- done today already: the next one pays less (TrainingPlan.RepeatMul)
	local nToday = trv and type(trv.today) == "table" and tonumber(trv.today[a.id]) or 0
	if nToday > 0 and not a.recovery and TP then
		-- (over the thumbnail's top corner: "2× -20%")
		local rc = UI.Chip(tile, string.format("%d× %+d%%", nToday, math.floor((TP.RepeatMul(nToday) - 1) * 100 + 0.5)), T.orange, { Name = "RepeatChip", AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8), TextSize = 11, h = 18 })
		rc.ZIndex = 3
	end
	UI.Button(tile, "GO", { Size = UDim2.fromOffset(THUMB_W, goH), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), BackgroundColor3 = T.gold, TextSize = 16 }, function()
		Hub.Close()
		if a.id == "Sparring" then
			State.open.Spar()
			return
		end
		local res = State.req("TravelTo", a.station)
		if res.ok then
			task.wait(0.35)
			State.open.Activity(a.id)
		else
			State.toast(res.err or "Can't go there", T.red)
		end
	end)
	return tile
end

-- MOVES & CONTROLS from the Training tab: the menu takes the hub's place and closing it brings the tab
-- back - unless another window took over (its opener's State.closeAll closes the menu: no hub then)
local function openControls()
	Hub.Close()
	local okCM, CM = pcall(function()
		return require(script.Parent:WaitForChild("ControlsMenu", 2))
	end)
	if not (okCM and type(CM) == "table" and type(CM.Open) == "function") then
		if State.open.Controls then
			State.open.Controls()
		end
		return
	end
	local back = true
	CM.Open({ onClose = function()
		if back and not State.inFight() and not State.activity and next(State.windows) == nil then
			Hub.Open("Training")
		end
	end })
	local close = State.windows.Controls
	if close then
		State.windows.Controls = function(...)
			back = false
			return close(...)
		end
	end
end

------------------------------------------------------------------------
-- Training programme (Training tab): the weekly plan or the fight camp, today's goals, the coach's
-- tips, personal records. P.training = server Training.ProgramView; the rules are Shared.TrainingPlan.
------------------------------------------------------------------------
local FOCUS_SHORT = { power = "POWER", speed = "SPEED", endurance = "CARDIO", defence = "DEFENCE", ringiq = "RING IQ", conditioning = "FITNESS", weightcut = "CUT", rest = "REST" }
local planEdit = false -- the template picker is open

local function focusColor(id)
	local f = TP and TP.FocusById[id]
	return f and rgb(f.rgb, T.sub) or T.sub
end

local function goalRows(card, list, compact)
	for i, g in ipairs(list) do
		local row = UI.Frame(card, { Name = "Goal", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 100 + i })
		row:SetAttribute("Kind", g.kind)
		row:SetAttribute("Done", g.done == true)
		local col = g.done and T.green or (g.weekly and T.purple or T.text)
		UI.Icon(row, g.done and "check" or (g.icon or "target"), 16, g.done and T.green or T.gold, { Position = UDim2.fromOffset(0, 3) })
		UI.Text(row, (g.weekly and "This week: " or "") .. g.text, { Font = T.semi, TextSize = 13, TextColor3 = col, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -78, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(row, string.format("%d/%d", g.n or 0, g.need or 1), { Face = "number", TextSize = 15, TextColor3 = col, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(52, 22), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
end

-- the seven days of the plan: tap a day to cycle its focus block
local function weekStrip(card, plan)
	local h = hit(card, 50)
	local strip = UI.Frame(card, { Name = "WeekStrip", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h) })
	UI.List(strip, 4, true)
	local order = {}
	for _, f in ipairs(TP.Focus) do
		table.insert(order, f.id)
	end
	for i = 1, TP.WEEK do
		local id = plan.days[i] or "rest"
		local today = i == plan.today
		local col = focusColor(id)
		local b = UI.Button(strip, "", { Name = "PlanDay" .. i, Size = UDim2.new(1 / TP.WEEK, -4, 1, 0), BackgroundColor3 = today and col:Lerp(T.bg, 0.55) or T.panel2, LayoutOrder = i }, function()
			local k = table.find(order, id) or 0
			result(State.req("SetPlanDay", i, order[k % #order + 1]))
		end)
		if today then
			UI.Stroke(b, T.gold, 2, 0)
		end
		UI.Icon(b, TP.FocusById[id] and TP.FocusById[id].icon or "sleep", 16, col, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5) })
		UI.Text(b, today and "TODAY" or ("DAY " .. i), { Font = T.semi, TextSize = 11, TextColor3 = today and T.gold or T.dim, Position = UDim2.new(0, 0, 0, 21), Size = UDim2.new(1, 0, 0, 12),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true })
		local lbl = UI.Text(b, FOCUS_SHORT[id] or id, { Font = T.semi, TextSize = 11, TextColor3 = col, Position = UDim2.new(0, 2, 1, -16), Size = UDim2.new(1, -4, 0, 13),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true })
		UI.New("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8, Parent = lbl })
	end
end

local function templatePicker(card, P)
	local grid = UI.Frame(card, { Name = "Templates", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local cols = UI.CanvasSize(State.gui).X >= 1000 and 4 or 2
	UI.Grid(grid, UDim2.new(1 / cols, -6, 0, hit(card, 40)), nil, 6)
	local function pick(id)
		planEdit = false
		result(State.req("SetPlan", id), id == "none" and "Free training: no plan." or nil)
	end
	for i, tpl in ipairs(TP.Templates) do
		local b = UI.Button(grid, string.upper(tpl.name), { Name = "Template_" .. tpl.id, LayoutOrder = i, TextSize = 13,
			BackgroundColor3 = (P.training and P.training.plan and P.training.plan.template == tpl.id) and T.goldDeep or T.panel2 }, function()
			pick(tpl.id)
		end)
		b:SetAttribute("Template", tpl.id)
	end
	UI.Button(grid, "NO PLAN (FREE)", { Name = "Template_none", LayoutOrder = 99, TextSize = 13, BackgroundColor3 = T.panel2 }, function()
		pick("none")
	end)
end

-- the camp: day strip coloured by phase, readiness, the focus against the opponent
local function campBlock(card, camp)
	local phases = camp.phases or {}
	local n = math.max(1, #phases)
	local strip = UI.Frame(card, { Name = "CampStrip", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) })
	UI.List(strip, 3, true)
	for i = 1, n do
		local ph = TP.Phases[phases[i]] or TP.Phases.build
		local col = rgb(ph.rgb, T.sub)
		local cell = UI.Frame(strip, { Name = "CampDay", Size = UDim2.new(1 / n, -3, 1, 0), BackgroundColor3 = i < camp.day and col:Lerp(T.bg, 0.6) or (i == camp.day and col or T.panel2), LayoutOrder = i })
		UI.Corner(cell, UI.R.sm)
		if i == camp.day then
			UI.Stroke(cell, T.white, 1.5, 0.1)
		end
		local lbl = UI.Text(cell, (n <= 6 and (ph.name .. " ") or "") .. i, { Font = T.semi, TextSize = 11, TextColor3 = i == camp.day and T.ink or col, Size = UDim2.new(1, -4, 1, -6), Position = UDim2.fromOffset(2, 3),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true })
		UI.New("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8, Parent = lbl })
	end
	local ph = TP.Phases[camp.phase or ""]
	if ph then
		UI.Line(card, string.format("%s: %s  Today %d/%d sessions.", ph.name, ph.desc, camp.todayN or 0, ph.target), { TextSize = 13, TextColor3 = rgb(ph.rgb, T.text), Font = T.semi })
	elseif camp.phase == "fight" then
		UI.Line(card, "Camp is over: it's fight night.", { TextSize = 13, TextColor3 = T.gold, Font = T.semi })
	end
	if camp.readiness then
		local score = camp.readiness
		local col = score >= 80 and T.gold or (score >= 65 and T.green or (score >= 45 and T.text or T.orange))
		local row = UI.StatRow(card, "Readiness", score, 100, col, string.format("%d", score))
		row.Name = "Readiness"
		local warn = {}
		if camp.over then
			table.insert(warn, "overtrained: ease off")
		end
		if camp.drained then
			table.insert(warn, "drained by the cut")
		end
		UI.Line(card, string.format("Fight-night forecast: %s%s. Peak right for a bonus in the ring; overtraining or a hard cut costs you.", tostring(camp.label or ""),
			#warn > 0 and (" (" .. table.concat(warn, ", ") .. ")") or ""), { TextSize = 12, TextColor3 = #warn > 0 and T.orange or T.sub })
	end
	if type(camp.focus) == "table" and #camp.focus > 0 then
		local names = {}
		for _, id in ipairs(camp.focus) do
			table.insert(names, TP.FocusById[id] and TP.FocusById[id].name or id)
		end
		UI.Line(card, string.format("Camp focus%s: %s (+%d%% gains). %s", camp.opp and (" vs " .. camp.opp) or "", table.concat(names, " + "), math.floor(TP.PLAN_BONUS * 100 + 0.5), camp.why or ""),
			{ TextSize = 13, TextColor3 = T.text })
	end
end

-- the programme card: plan / camp, goals, coach tips
local function programSection(body, P)
	local tr = P.training
	if not (TP and type(tr) == "table") then
		return
	end
	local compact = compactHub()
	local camp = tr.camp
	local card = UI.Card(body, { stroke = camp and T.red or nil })
	card.Name = "Programme"
	local head = UI.Frame(card, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hit(card, 28)) })
	local title
	if camp then
		title = string.format("FIGHT CAMP  ·  DAY %d OF %d", math.min(camp.day or 1, camp.total or 1), camp.total or 1)
	elseif tr.plan then
		local f = tr.focus and tr.focus[1]
		title = "TRAINING PLAN  ·  TODAY: " .. (f and (TP.FocusById[f] and string.upper(TP.FocusById[f].name) or f) or "-")
	else
		title = "TRAINING PLAN  ·  FREE TRAINING"
	end
	UI.Kicker(head, title, camp and T.red or T.gold, { icon = "calendar", Size = UDim2.new(1, -150, 1, 0) })
	if not camp then
		UI.Button(head, planEdit and "CLOSE" or (tr.plan and "CHANGE PLAN" or "SET A PLAN"), { Name = "PlanEdit", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 140, 1, 0), BackgroundColor3 = planEdit and T.panel2 or T.goldDeep, TextSize = 13 }, function()
			planEdit = not planEdit
			Hub.RenderNow()
		end)
	end
	if camp then
		campBlock(card, camp)
	elseif tr.plan then
		weekStrip(card, tr.plan)
		local f = tr.focus and TP.FocusById[tr.focus[1]]
		if f and not compact then
			UI.Line(card, f.rest and "Rest day: recovery only and a proper meal. Skip hard training for fresh legs tomorrow (+6% gains)."
				or string.format("%s: %s. Drills on today's block earn +%d%% gains. Tap a day to change it.", f.name, f.desc, math.floor(TP.PLAN_BONUS * 100 + 0.5)), { TextSize = 12, TextColor3 = T.sub })
		end
	elseif not planEdit then
		UI.Line(card, "Pick a weekly plan: training on the day's focus block earns bonus gains. Free training still works.", { TextSize = 12, TextColor3 = T.sub })
	end
	if planEdit and not camp then
		templatePicker(card, P)
	end
	-- goals
	local gl = {}
	for _, g in ipairs(tr.goals or {}) do
		table.insert(gl, g)
	end
	if tr.weekly then
		local w = table.clone(tr.weekly)
		w.weekly = true
		table.insert(gl, w)
	end
	if #gl > 0 then
		local done = 0
		for _, g in ipairs(tr.goals or {}) do
			if g.done then
				done += 1
			end
		end
		local gh = UI.Frame(card, { Name = "GoalsHead", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 99 })
		UI.Kicker(gh, string.format("TODAY'S GOALS  %d/%d", done, #(tr.goals or {})), T.gold, { icon = "target", Size = UDim2.new(1, -120, 1, 0) })
		if (tr.streak or 0) > 0 then
			UI.Chip(gh, string.format("STREAK %d", tr.streak), T.orange, { icon = "flame", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), TextSize = 12 })
		end
		goalRows(card, gl, compact)
		local rw = tr.reward or {}
		if not compact and rw.goal then
			local f = UI.Line(card, string.format("Each goal %s and %d XP; all three +%s more%s. Weekly challenge %s.", money(rw.goal.money or 0), rw.goal.xp or 0, money(rw.sweep and rw.sweep.money or 0),
				(tr.streak or 0) > 0 and " (streak bonus)" or "", money(rw.weekly and rw.weekly.money or 0)), { TextSize = 12, TextColor3 = T.dim })
			f.LayoutOrder = 200
		end
	end
	-- the coach
	for i, tip in ipairs(tr.tips or {}) do
		if i > (compact and 1 or 2) then
			break
		end
		local l = UI.Line(card, string.format('<font color="#%s">%s%s:</font> %s', T.gold:ToHex(), UI.Type.Sentence(string.upper(tip.coach or "Coach")), tip.persona and (" (" .. tip.persona .. ")") or "", tip.text or ""),
			{ RichText = true, TextSize = 13, TextColor3 = T.text })
		l.Name = "CoachTip"
		l.LayoutOrder = 300 + i
	end
	if tr.rust then
		local l = UI.Line(card, string.format("RING RUST: %d days without training. Stamina, speed and timing are fading.", tr.idle or 0), { TextSize = 13, TextColor3 = T.orange, Font = T.semi })
		l.LayoutOrder = 400
	end
end
Hub.ProgramSection = programSection

-- personal records: each drill's best grade and best numbers, its mastery and overload
local REC_NAMES = {
	punches = "punches", maxPower = "max power", handSpeed = "hand speed", hitsPerMin = "hits/min", bestStreak = "streak", accuracy = "accuracy", counters = "counters",
	cleanCombos = "clean combos", load = "load", goodReps = "good reps", distance = "distance", topSpeed = "top speed", maxWatts = "watts", meters = "metres",
	stepsPerSec = "steps/s", cleanJumps = "clean jumps", doubleUnders = "double unders", lengths = "lengths", cleanSlams = "slams", perfectCurls = "perfect curls",
}
local function recordsSection(body, P)
	local recs = type(P.records) == "table" and P.records or {}
	local mastery = type(P.training) == "table" and P.training.mastery or {}
	local list = {}
	for _, a in ipairs(Config.Activities) do
		local r = recs[a.id]
		if type(r) == "table" and (tonumber(r.sessions) or 0) > 0 then
			table.insert(list, { a = a, r = r, m = mastery[a.id] })
		end
	end
	if #list == 0 then
		return
	end
	UI.Header(body, "PERSONAL RECORDS", T.gold, "trophy")
	local cols = UI.CanvasSize(State.gui).X >= 1100 and 3 or (UI.CanvasSize(State.gui).X >= 760 and 2 or 1)
	local grid = UI.Frame(body, { Name = "Records", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(grid, UDim2.new(1 / cols, cols > 1 and -6 or 0, 0, 62), nil, 6)
	for i, e in ipairs(list) do
		local tile = UI.Frame(grid, { Name = "Record", LayoutOrder = i, BackgroundColor3 = T.panel, BackgroundTransparency = 0.05 })
		UI.Corner(tile, UI.R.md)
		tile:SetAttribute("Activity", e.a.id)
		local grade = Config.GradeFor(tonumber(e.r.best) or 0)
		local g = Config.GradeInfo(grade).rgb
		local gcol = Color3.fromRGB(g[1], g[2], g[3])
		UI.Text(tile, grade, { Face = "display", TextSize = 24, TextColor3 = gcol, Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(28, 30), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		local lv = e.m and e.m.lv or 0
		local mtxt = TP and string.format("%s%s", string.upper(TP.MasteryName(lv) or ""), (e.m and (e.m.ov or 0) > 0) and string.format(" · OVERLOAD %d", e.m.ov) or "") or ""
		UI.Text(tile, string.upper(e.a.name), { Font = T.semi, TextSize = 13, Position = UDim2.fromOffset(42, 6), Size = UDim2.new(1, -50, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(tile, string.format("%d%% best  ·  %d×  ·  %s", Config.QualityPct(tonumber(e.r.best) or 0), tonumber(e.r.sessions) or 0, mtxt), { TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(42, 23), Size = UDim2.new(1, -50, 0, 14),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local nums = {}
		local keys = {}
		for k in pairs(type(e.r.stats) == "table" and e.r.stats or {}) do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			if REC_NAMES[k] and #nums < 3 then
				local v = tonumber(e.r.stats[k]) or 0
				table.insert(nums, string.format("%s %s", REC_NAMES[k], v == math.floor(v) and tostring(v) or string.format("%.1f", v)))
			end
		end
		UI.Text(tile, #nums > 0 and table.concat(nums, "  ·  ") or "No numbers logged yet", { TextSize = 12, TextColor3 = #nums > 0 and T.gold or T.dim, Position = UDim2.fromOffset(42, 40), Size = UDim2.new(1, -50, 0, 14),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
end
Hub.RecordsSection = recordsSection

R.Training = function(body, P)
	local c = P.condition
	local compact = compactHub()
	local card = UI.Card(body)
	-- the card's header: the kicker, and the moves list / control map (ControlsMenu) on the right -
	-- what the drills and the ring run on
	local headH = hit(card, 28)
	local head = UI.Frame(card, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headH) })
	UI.Kicker(head, string.format("CONDITION  ·  DAY %d", P.day), T.gold, { Size = UDim2.new(1, -196, 0, 28), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	if State.open.Controls then
		local mc = UI.Button(head, "MOVES & CONTROLS", { Name = "MovesControls", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(compact and 150 or 180, headH),
			BackgroundColor3 = T.panel2, TextSize = 13 }, openControls)
		UI.Stroke(mc, T.gold, 1, 0.5)
	end
	if compact then
		-- a phone: the condition as one line of chips, so the exercise cards start above the fold
		local chips = UI.Frame(card, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
		UI.List(chips, 6, true)
		local function chip(text, color, order)
			UI.Chip(chips, text, color, { order = order, h = 26, TextSize = 13 })
		end
		chip(string.format("ENERGY %d", c.energy), c.energy < 25 and T.red or T.gold, 1)
		chip(string.format("WATER %d", c.hydration), c.hydration < 30 and T.red or T.cyan, 2)
		chip(string.format("FOOD %d", c.nutrition), c.nutrition < 30 and T.red or T.green, 3)
		chip(string.format("FATIGUE %d", c.fatigue), c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green), 4)
		chip(string.format("%.1f/%d LBS", P.weight, P.weightLimit), P.overWeight > 0 and T.red or T.sub, 5)
	else
		local meters = UI.Frame(card, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70) })
		UI.List(meters, 8, true)
		meterTile(meters, "ENERGY", c.energy, c.energy < 25 and T.red or T.gold, 1)
		meterTile(meters, "HYDRATION", c.hydration, c.hydration < 30 and T.red or T.cyan, 2)
		meterTile(meters, "NUTRITION", c.nutrition, c.nutrition < 30 and T.red or T.green, 3)
		meterTile(meters, "FATIGUE", c.fatigue, c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green), 4)
		local chips = UI.Frame(card, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) })
		UI.List(chips, 6, true)
		UI.Chip(chips, string.format("Sleep %d%%", math.floor(c.sleepQ * 100)), T.blue, { order = 1, TextSize = 12, icon = "sleep" })
		UI.Chip(chips, string.format("%.1f / %d lbs", P.weight, P.weightLimit), P.overWeight > 0 and T.red or T.text, { order = 2, TextSize = 12 })
		UI.Chip(chips, string.format("Body fat %.1f%%", P.body.fat or 14), T.text, { order = 3, TextSize = 12 })
	end
	-- residual fight damage healing day by day, accumulated head trauma, muscle soreness
	if c.face and (tonumber(c.face.stage) or 0) > 0 then
		local f = c.face
		local bits = {}
		if f.eyes and f.eyes > 0.3 then
			table.insert(bits, "swollen eye")
		end
		if f.cut then
			table.insert(bits, "stitched cut")
		end
		if f.nose then
			table.insert(bits, "broken nose")
		end
		UI.Line(card, string.format("Face: %s%s, about %d day%s to heal.", tostring(f.label or ""), #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "", f.days or 0, (f.days or 0) == 1 and "" or "s"),
			{ TextColor3 = (f.stage or 0) >= 3 and T.red or T.orange, TextSize = 13, Font = T.semi })
	end
	if (tonumber(c.trauma) or 0) > 0 then
		UI.StatRow(card, "HEAD TRAUMA", c.trauma, 100, c.trauma >= 40 and T.red or T.orange)
		if c.trauma >= 40 then
			UI.Line(card, "Accumulated head trauma weakens your chin. Time between fights lets it settle.", { TextColor3 = T.red, TextSize = 13 })
		end
	end
	local soreTxt = {}
	for _, k in ipairs(Config.MuscleKeys) do
		local v = c.sore and tonumber(c.sore[k])
		if v and v >= 0.1 then
			table.insert(soreTxt, string.format("%s %d%%", Config.MuscleNames[k], math.floor(v * 100)))
		end
	end
	if #soreTxt > 0 then
		UI.Line(card, "SORE: " .. table.concat(soreTxt, ", ") .. (compact and "" or ". Growth is slower on sore muscles; sleep and eat to recover."), { TextColor3 = T.orange, TextSize = 13 })
	end
	if c.fatigue > 70 then
		UI.Line(card, "OVERTRAINING: gains are cut in half and injury risk is high. Recover (ice bath, massage, stretching) or sleep.", { TextColor3 = T.red, TextSize = 13, Font = T.semi })
	elseif c.fatigue > 40 and not compact then
		UI.Line(card, "Fatigue is building and gains are dropping. Mix in recovery.", { TextColor3 = T.orange, TextSize = 13 })
	end
	for _, inj in ipairs(c.injuries or {}) do
		UI.Line(card, string.format("INJURED: %s (%d days)", inj.name, inj.days), { TextColor3 = T.red, TextSize = 14, Font = T.semi })
	end
	local buffs = {}
	if c.buffs and c.buffs.gains then
		table.insert(buffs, string.format("+%d%% gains", c.buffs.gains * 100))
	end
	if c.buffs and c.buffs.muscle then
		table.insert(buffs, string.format("+%d%% muscle", c.buffs.muscle * 100))
	end
	if c.flexible then
		table.insert(buffs, "limber (lower injury risk)")
	end
	if #buffs > 0 then
		UI.Line(card, "TODAY: " .. table.concat(buffs, ", "), { TextColor3 = T.green, TextSize = 13, Font = T.semi })
	end
	buttons(card, {
		act("NUTRITION BAR", T.panel2, function()
			Hub.Close()
			State.open.Nutrition()
		end, compact and 150 or 160),
		act("DRINK WATER", T.panel2, function()
			State.open.Water()
		end, compact and 130 or 140),
		act("SLEEP (END DAY)", T.gold, function()
			Hub.Close()
			State.open.Sleep()
		end, compact and 160 or 170),
	}, compact and 36 or 40)
	-- the weekly plan / fight camp, today's goals and the coach (programSection above)
	programSection(body, P)
	local cap = frameCap(P)
	-- two columns only where a card keeps its name, cost chip and gains whole at the text floor (a
	-- 667 phone's half-width card cut "DOUBLE-END BAG" under its chip): the smallest phones take one
	local cols = (UI.CanvasSize(State.gui).X - (compact and 120 or 260)) >= 780 and 2 or 1
	for _, area in ipairs(AREAS) do
		local list = {}
		for _, a in ipairs(Config.Activities) do
			if a.area == area then
				table.insert(list, a)
			end
		end
		if #list > 0 then
			UI.Header(body, area)
			local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
			UI.Grid(grid, UDim2.new(1 / cols, cols > 1 and -6 or 0, 0, CARD_H), nil, 10)
			for i, a in ipairs(list) do
				exerciseCard(grid, a, P, i, cap)
			end
		end
	end
	recordsSection(body, P)
end

local FLEX_NAMES = {
	flex_biceps = "DOUBLE BICEPS", flex_lat = "LAT SPREAD", flex_chest = "SIDE CHEST", flex_most = "MOST MUSCULAR", flex_abs = "ABS & THIGH",
}

-- which exercises build which muscles (from Config.ExerciseTargets via act.parts), strongest first
local function exerciseGuide()
	local lines = {}
	for _, a in ipairs(Config.Activities) do
		if type(a.parts) == "table" and not a.recovery then
			local list = {}
			for id, wgt in pairs(a.parts) do
				table.insert(list, { id = id, w = tonumber(wgt) or 0 })
			end
			table.sort(list, function(x, y)
				return x.w > y.w
			end)
			local names = {}
			for i = 1, math.min(4, #list) do
				table.insert(names, Config.MusclePartNames[list[i].id] or list[i].id)
			end
			if #names > 0 then
				table.insert(lines, a.name .. ": " .. table.concat(names, ", "))
			end
		end
	end
	return lines
end

-- the exercise that works a muscle part hardest (ties: the cheaper one)
local function bestExerciseFor(id)
	local best, bw = nil, 0
	for _, a in ipairs(Config.Activities) do
		local w = not a.recovery and type(a.parts) == "table" and tonumber(a.parts[id]) or 0
		if w > bw + 1e-6 or (best and math.abs(w - bw) <= 1e-6 and w > 0 and (tonumber(a.energy) or 99) < (tonumber(best.energy) or 99)) then
			best, bw = a, w
		end
	end
	return best
end

local function startExercise(a)
	Hub.Close()
	if a.id == "Sparring" then
		State.open.Spar()
		return
	end
	local res = State.req("TravelTo", a.station)
	if res.ok then
		task.wait(0.35)
		State.open.Activity(a.id)
	else
		State.toast(res.err or "Can't go there", T.red)
	end
end

-- the Muscle Progression screen takes the hub's place; closing it brings the Body tab back
local function openMuscleScreen(group)
	if not (MuscleScreen and MuscleScreen.Open) then
		return
	end
	Hub.Close()
	-- (the screen runs `back` only when the player closes it; another opener closes it silently)
	MuscleScreen.Open({ group = group, back = function()
		if not State.inFight() and not State.activity and next(State.windows) == nil then
			Hub.Open("Body")
		end
	end })
end

R.Body = function(body, P)
	local compact = compactHub()
	local cap, frameDef = frameCap(P)
	local dev = {}
	for _, part in ipairs(Config.MuscleParts) do
		dev[part.id] = partLevel(P, part.id)
	end
	-- the composition of this screen (its own shape in the hub): the figure on a dark stage at the left, a
	-- stacked column of readouts at the right - the physique, a ledger of the three muscles to train next, a
	-- vertical timeline of the growth logged day by day - and the body's numbers under them
	local c = UI.Frame(body, { Name = "Physique", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local mapW, mapH = compact and 220 or 300, compact and 290 or 400
	local stageW = mapW + 32
	local stage = UI.Frame(c, { Name = "Stage", BackgroundColor3 = T.ink, Size = UDim2.fromOffset(stageW, mapH + 32) })
	UI.Corner(stage, UI.R.lg)
	UI.Stroke(stage, T.line, 1, 0)
	local map = BodyMap.new(stage, { Size = UDim2.fromOffset(mapW, mapH), Position = UDim2.fromOffset(16, 16), legend = true })
	map:SetDevelopment(dev, cap)
	local info = UI.Frame(c, { Name = "Readouts", BackgroundTransparency = 1, Position = UDim2.fromOffset(stageW + 20, 0), Size = UDim2.new(1, -(stageW + 20), 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.List(info, 8)
	UI.Kicker(info, "Physique", nil, { order = 1 })
	UI.Title(info, tostring(P.physique or "?"), { TextSize = compact and 22 or 26, Size = UDim2.new(1, 0, 0, compact and 26 or 30), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	if P.physiqueDesc and P.physiqueDesc ~= "" then
		UI.Line(info, P.physiqueDesc, { TextSize = 13, LayoutOrder = 3, TextColor3 = T.sub })
	end
	if P.physiquePinned and not compact then
		UI.Line(info, "The look chosen in the creator stays; training still builds every muscle.", { TextColor3 = T.sub, TextSize = 13, LayoutOrder = 4 })
	end
	-- the ledger: the three least developed muscles (against the potential), each with the exercise that builds it
	local order = {}
	for _, part in ipairs(Config.MuscleParts) do
		table.insert(order, { id = part.id, v = dev[part.id] or 0 })
	end
	table.sort(order, function(a, b)
		if a.v ~= b.v then
			return a.v < b.v
		end
		return a.id < b.id
	end)
	UI.Kicker(info, "Train next  ·  your weakest muscles", T.red, { order = 5 })
	local ledger = UI.Frame(info, { Name = "TrainNext", BackgroundColor3 = T.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })
	UI.Stroke(ledger, T.line, 1, 0)
	UI.List(ledger, 0)
	for i = 1, 3 do
		local e = order[i]
		if not e then
			break
		end
		local ex = bestExerciseFor(e.id)
		local trainH = hit(info, 32)
		local rowH = math.max(52, trainH + 16)
		local row = UI.Frame(ledger, { Name = "Next" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = i })
		if i > 1 then
			UI.Frame(row, { Name = "Rule", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line })
		end
		UI.Text(row, BodyMap.Short(e.id), { Face = "heading", TextSize = 14, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0.5, -12, 0, 18), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		if ex then
			UI.Text(row, ex.name, { TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 27), Size = UDim2.new(0.5, -12, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
				TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		UI.LevelBar(row, { Position = UDim2.new(0.5, 0, 0, math.floor(rowH / 2) - 3), Size = UDim2.new(0.5, -(trainH * 3 + 72), 0, 6) }, { value = e.v, cap = cap, color = BodyMap.DevColor(e.v / cap) })
		UI.Text(row, string.format("%d / %d", math.floor(e.v + 0.5), math.floor(cap + 0.5)), { Face = "numberMed", TextSize = 13, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(trainH * 3 + 12), 0.5, 0),
			Size = UDim2.fromOffset(52, 18), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		if ex then
			UI.Button(row, "Train", { Size = UDim2.fromOffset(trainH * 3 - 8, trainH), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = T.gold, TextColor3 = T.ink, TextSize = 13 }, function()
				startExercise(ex)
			end)
		end
	end
	-- the muscle screen: the figure to turn, every group lit, growth over time
	if MuscleScreen then
		UI.Button(info, "Muscle view and growth", { Name = "MuscleView", Size = UDim2.new(1, 0, 0, hit(info, 34)), LayoutOrder = 7, BackgroundColor3 = T.panel2, TextSize = 13 }, function()
			openMuscleScreen(nil)
		end)
	end
	-- the growth timeline: the days the server logged (GetMuscleHistory: one row per day with every group's
	-- level), the total of the groups and what each day added, newest at the bottom
	do
		local okH, hres = pcall(State.req, "GetMuscleHistory")
		local hist = (okH and type(hres) == "table" and type(hres.history) == "table") and hres.history or {}
		local rows = {}
		for _, r in ipairs(hist) do
			local total, d = 0, tonumber(r.d)
			for _, k in ipairs(Config.MuscleKeys) do
				total += tonumber(r[k]) or 0
			end
			if d then
				table.insert(rows, { d = d, v = total })
			end
		end
		local live = 0
		for _, k in ipairs(Config.MuscleKeys) do
			live += tonumber(P.body[k]) or 0
		end
		if #rows == 0 or rows[#rows].d < (P.day or 1) then
			table.insert(rows, { d = P.day or 1, v = live, today = true })
		else
			rows[#rows].v, rows[#rows].today = live, true
		end
		local first = math.max(1, #rows - 5)
		UI.Kicker(info, "Growth  ·  muscle logged day by day", nil, { order = 8 })
		local tl = UI.Frame(info, { Name = "Timeline", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9 })
		UI.List(tl, 0)
		local n = #rows - first + 1
		if n <= 1 and #hist == 0 then
			UI.Line(tl, "No days logged yet. Train, eat and sleep: every night adds a line here.", { TextSize = 13, TextColor3 = T.sub })
		end
		for i = first, #rows do
			local r = rows[i]
			local prev = rows[i - 1]
			local delta = prev and (r.v - prev.v) or nil
			local rowH = 30
			local row = UI.Frame(tl, { Name = "Day" .. r.d, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = i })
			-- the spine: a line through the dots, a filled dot for today
			if i > first then
				UI.Frame(row, { Size = UDim2.new(0, 1, 0.5, 0), Position = UDim2.fromOffset(5, 0), BackgroundColor3 = T.line })
			end
			if i < #rows then
				UI.Frame(row, { Size = UDim2.new(0, 1, 0.5, 0), Position = UDim2.new(0, 5, 0.5, 0), BackgroundColor3 = T.line })
			end
			local dot = UI.Frame(row, { Size = UDim2.fromOffset(9, 9), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), BackgroundColor3 = r.today and T.gold or T.panel2 })
			UI.Corner(dot, 5)
			UI.Stroke(dot, r.today and T.gold or T.sub, 1, 0)
			UI.Text(row, r.today and string.format("Day %d  ·  today", r.d) or string.format("Day %d", r.d), { Font = T.semi, TextSize = 13, TextColor3 = r.today and T.text or T.sub,
				Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.5, -22, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.Text(row, string.format("%.1f", r.v), { Face = "numberMed", TextSize = 13, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 0), Size = UDim2.fromOffset(70, rowH),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			UI.Text(row, delta and string.format("%s%.1f", delta >= 0 and "+" or "", delta) or "", { Face = "numberMed", TextSize = 13, TextColor3 = (delta or 0) > 0.05 and T.green or ((delta or 0) < -0.05 and T.orange or T.dim),
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(56, rowH), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		end
	end
	-- the archetype ladder: where this build sits among the physiques the game recognises
	local row = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 26) })
	UI.List(row, 6, true)
	for i, ph in ipairs(Config.Physiques) do
		local cur = ph.id == P.physiqueId or ph.name == P.physique
		if cur then
			UI.Badge(row, ph.name, T.gold, { order = i, h = 26, TextSize = 12 })
		elseif not compact then
			UI.Chip(row, ph.name, T.sub, { order = i, h = 26, TextSize = 12 })
		end
	end
	-- the body's numbers: what the frame is (the body type picked in the creator, which sets the potential every
	-- muscle grows toward) is said as such, apart from what the training made of it
	local facts = UI.Card(body, { gap = 6 })
	local fat = P.body.fat or 14
	local ph = Config.FindById(Config.Physiques, P.physiqueId or "")
	local def = Config.Definition(fat, ph and ph.defBonus or 0)
	UI.Line(facts, string.format("Height %s  ·  Reach %d in  ·  Weight %.1f lbs", Config.HeightText(P.physical.height), P.physical.reach, P.weight), { TextSize = 14 })
	UI.Line(facts, string.format("Frame: %s  ·  muscle potential %d (set in the creator)", tostring(frameDef.id), math.floor(cap + 0.5)), { Name = "FrameLine", TextSize = 13, TextColor3 = T.sub })
	UI.StatRow(facts, "Body fat", fat - 6, 24, fat > 18 and T.orange or T.green, string.format("%.1f%%", fat))
	UI.StatRow(facts, "Definition", def * 100, 100, T.blue, string.format("%d%%", math.floor(def * 100 + 0.5)))
	UI.StatRow(facts, "Vascularity", P.body.vasc or 0, 100, T.blue, string.format("%d", math.floor(P.body.vasc or 0)))
	local fat2 = fat >= Config.BodyFat.bellyAt and "A soft belly is showing. Cardio and clean meals bring the abs back."
		or (def >= Config.BodyFat.absRow4Def and "Shredded: a full eight-pack, veins and muscle separation on show."
		or (def >= 0.4 and "The abs are visible; a little less fat brings full separation." or "The muscles are smooth under the skin; lower body fat brings out definition."))
	UI.Line(facts, fat2, { TextColor3 = T.sub, TextSize = 13 })

	-- every muscle under its group: the level bar (fill = level, gold tick = your frame's potential)
	local sore = P.condition and P.condition.sore or {}
	local m = UI.Card(body)
	UI.Kicker(m, "Muscle development")
	UI.Line(m, string.format("Each bar fills toward 100; the gold tick is your body type's potential (%d). Soreness shows in orange.", math.floor(cap + 0.5)), { TextColor3 = T.sub, TextSize = 13 })
	-- a group row's "3D" button: finger-sized on touch (the row grows to it)
	local viewH = hit(m, 22)
	local viewW = math.max(34, viewH)
	-- sub: a second line under the label (a finger-high group row: the soreness under the name, where
	-- one line beside the "3D" button would cut it at a phone's text floor)
	local function levelRow(parent, label, v, h, strong, labelColor, sub)
		local f = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h) })
		-- a group row leaves room for its "3D" button before the bar
		local labelW = (strong and MuscleScreen) and -(viewW + 10) or 0
		UI.Text(f, label, { Font = strong and T.semi or T.font, TextSize = strong and 14 or 13, TextColor3 = labelColor or (strong and T.text or T.sub), Size = UDim2.new(0.34, labelW, sub and 0.5 or 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = sub and Enum.TextYAlignment.Bottom or nil })
		if sub then
			UI.Text(f, sub, { Name = "Sub", Font = T.semi, TextSize = 12, TextColor3 = labelColor or T.orange, Position = UDim2.new(0, 0, 0.5, 2), Size = UDim2.new(0.34, labelW, 0.5, -2),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top })
		end
		UI.LevelBar(f, { Position = UDim2.new(0.34, 0, 0.5, strong and -5 or -3), Size = UDim2.new(0.52, 0, 0, strong and 10 or 6) }, { value = v, cap = cap, color = BodyMap.DevColor(v / cap) })
		UI.Text(f, string.format("%.1f", v), { Face = "number", TextSize = strong and 16 or 14, Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		return f
	end
	for _, k in ipairs(Config.MuscleKeys) do
		local sv = tonumber(sore[k]) or 0
		local soreText = sv >= 0.1 and string.format("SORE %d%%", math.floor(sv * 100)) or nil
		local rowH = MuscleScreen and math.max(26, viewH + 4) or 26
		-- a finger-high row has room for two lines: the soreness goes under the name
		local twoLines = soreText ~= nil and rowH >= 40
		local gname = Config.MuscleNames[k] .. ((soreText and not twoLines) and ("  ·  " .. soreText) or "")
		local groupRow = levelRow(m, gname, tonumber(P.body[k]) or 0, rowH, true, sv >= 0.4 and T.orange or nil, twoLines and soreText or nil)
		if MuscleScreen then
			-- the group's own page of the muscle screen (its figure lit, its growth graph)
			UI.Button(groupRow, "3D", { Name = "View_" .. k, Size = UDim2.fromOffset(viewW, viewH), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.33, 0, 0.5, 0), BackgroundColor3 = T.panel2, TextSize = 12 }, function()
				openMuscleScreen(k)
			end)
		end
		for _, part in ipairs(Config.MuscleGroupParts[k] or {}) do
			levelRow(m, "      " .. BodyMap.Short(part.id), dev[part.id] or 0, 20, false)
		end
	end

	-- flex in front of the mirror: shows off the pump, veins and every muscle you built
	local fl = UI.Card(body)
	UI.Kicker(fl, "Flex")
	UI.Line(fl, "Strike a pose wherever you stand. Freshly trained muscles show a pump and the veins come up.", { TextColor3 = T.sub, TextSize = 13 })
	local flexH = hit(fl, 32)
	local flexRow = UI.Row(fl, flexH + 2)
	for _, pose in ipairs((Config.Pump and Config.Pump.poses) or {}) do
		UI.Button(flexRow, FLEX_NAMES[pose] or pose, { Size = UDim2.fromOffset(132, flexH), TextSize = 13 }, function()
			local r = State.req("Flex", pose)
			if r.ok then
				Hub.Close()
			else
				State.toast(r.err or "Can't flex right now.", T.red)
			end
		end)
	end

	local g = UI.Card(body)
	UI.Kicker(g, "What builds what")
	for _, line in ipairs(exerciseGuide()) do
		UI.Line(g, line, { TextSize = 13, TextColor3 = T.sub })
	end
	UI.Line(body, string.format("Every session grows the muscles it works: %d%% of the growth at once, the rest overnight if you sleep and eat well. Muscles you neglect for a week start to fade. Muscle adds punching power and weight; fat costs stamina and makes weight harder to make. Bulk up and you may need to move up a division.",
		math.floor(BodyMap.GrowthSplit(1) * 100 + 0.5)), { TextColor3 = T.sub, TextSize = 13 })
end

R.Stats = function(body, P)
	local c = UI.Card(body)
	UI.Line(c, string.format("%s \"%s\"  -  OVERALL %d", P.identity.name, P.identity.nickname, P.overall), { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	UI.Line(c, string.format("%s  -  %s specialty  -  %d training sessions", P.style, P.specialty, P.sessions or 0), { TextSize = 14, TextColor3 = T.sub })
	local s = UI.Card(body)
	UI.Line(s, "CORE STATS", { Font = T.bold, TextColor3 = T.gold })
	for _, k in ipairs(Config.StatKeys) do
		local v = P.stats[k] or 0
		UI.StatRow(s, Config.StatNames[k], v, 99, T.green, string.format("%.2f", v))
	end
	local m = UI.Card(body)
	UI.Line(m, "MENTAL", { Font = T.bold, TextColor3 = T.gold })
	for _, k in ipairs(Config.MentalKeys) do
		UI.StatRow(m, k, P.mental[k] or 0, 100, T.blue)
	end
	UI.Line(body, "Confidence boosts power, Focus improves accuracy, Composure helps you beat the count, Discipline speeds up training, Aggression adds pop. Stats gain less as they get higher, and age catches up with everyone after 30.", { TextColor3 = T.sub, TextSize = 13 })
end

-- facility tier card (CONTRACTS section 9): derived from equipment levels, career tier and Shop items
local function facilityCard(body, P)
	local gt = P.gymTier
	if type(gt) ~= "table" then
		local ok, idx, def, frac, needs = pcall(Catalog.GymTier, P.gym and P.gym.levels, P.owned, P.tier)
		if not ok then
			return
		end
		local nextDef = Config.GymTiers[idx + 1]
		gt = { index = idx, id = def.id, name = def.name, desc = def.desc, growth = def.growth, frac = frac, needs = needs or {}, nextName = nextDef and nextDef.name }
	end
	local c = UI.Card(body, { stroke = T.gold })
	UI.Line(c, string.format("Facility: %s (%d%%)", tostring(gt.name or gt.id), math.floor((gt.frac or 0) * 100 + 0.5)), { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	if gt.desc then
		UI.Line(c, gt.desc, { TextSize = 13 })
	end
	UI.Line(c, string.format("Muscle growth x%.2f from the facility", tonumber(gt.growth) or 1), { TextSize = 13, TextColor3 = T.green })
	-- tier ladder: the four tiers share the card's width (fixed 170 px chips ran off a phone's card)
	local row = UI.Frame(c, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	UI.Grid(row, UDim2.new(1 / #Config.GymTiers, -6, 0, 26), nil, 6)
	for i, t in ipairs(Config.GymTiers) do
		local cur = i == gt.index
		local reached = i <= (gt.index or 1)
		local font = cur and T.bold or T.font
		local chip = UI.Text(row, t.name, { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, TextSize = 11, Font = font, TextWrapped = false, TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0,
			BackgroundColor3 = cur and T.gold or (reached and Color3.fromRGB(60, 50, 20) or T.panel2), TextColor3 = cur and T.bg or (reached and T.gold or T.sub) })
		UI.Corner(chip, 6)
		-- the full name where it fits whole at the text floor, else the short one ("Elite", not "Elite Training Cent...")
		local short = (t.name:gsub(" Gym$", ""):gsub(" Training Center$", ""):gsub(" Facility$", ""))
		local function refit()
			local rootW = State.gui.AbsoluteSize.X
			local w = rootW > 1 and chip.AbsoluteSize.X / rootW * UI.CanvasSize(State.gui).X or 0
			chip.Text = (w <= 0 or fits(chip, t.name, 11, w - 8, font)) and t.name or short
		end
		refit()
		chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	end
	if gt.nextName then
		UI.Line(c, "NEXT: " .. gt.nextName, { Font = T.semi, TextSize = 14 })
		for _, n in ipairs(gt.needs or {}) do
			UI.Line(c, "  - " .. n, { TextSize = 13, TextColor3 = T.orange })
		end
		if #(gt.needs or {}) == 0 then
			UI.Line(c, "  Ready: the upgrade lands with your next push.", { TextSize = 13, TextColor3 = T.green })
		end
	else
		UI.Line(c, "Top tier: the best gym in the world is yours.", { TextSize = 13, TextColor3 = T.gold })
	end
	local names = {}
	local ok, set = pcall(Catalog.GymFacilities, gt.index)
	if ok then
		for _, t in ipairs(Config.GymTiers) do
			for _, fid in ipairs(t.facilities) do
				if set[fid] then
					table.insert(names, Config.FacilityNames[fid] or fid)
				end
			end
		end
	end
	if #names > 0 then
		UI.Line(c, "Facilities: " .. table.concat(names, ", "), { TextSize = 12, TextColor3 = T.sub })
	end
	local elite = (gt.index or 1) >= 3
	UI.Line(c, elite and "The WCB Elite Performance Center across town is open to you." or "The WCB Elite Performance Center (north-east of the arena) opens at the Elite tier.",
		{ TextSize = 13, TextColor3 = elite and T.green or T.sub })
	if elite then
		buttons(c, {
			act("GO TO THE ELITE CENTER", T.gold, function()
				travel("TravelPlace", "elite")
			end, 240),
		}, 32)
	end
end

R.Gym = function(body, P)
	facilityCard(body, P)
	UI.Line(body, "Money " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 18 })
	UI.Line(body, "Better equipment means faster gains, and it looks the part. Equipment wears down with use: below 30% condition, gains drop. Repair it.", { TextColor3 = T.sub, TextSize = 13 })
	local lastArea
	for _, id in ipairs(Catalog.StationOrder) do
		local st = Catalog.Stations[id]
		if st.area ~= lastArea then
			lastArea = st.area
			UI.Header(body, st.area:upper())
		end
		local lv = math.max(1, P.gym.levels[id] or 1)
		local cur = st.levels[math.min(lv, #st.levels)]
		local nxt = st.levels[lv + 1]
		local cond = P.gym.cond[id] or 100
		local c = UI.Card(body)
		UI.Line(c, string.format("%s  -  Lv.%d %s  (x%.2f gains)", st.name, lv, cur.name, cur.mult), { Font = T.bold, TextSize = 15, TextColor3 = cur.elite and T.gold or T.text })
		UI.StatRow(c, "Condition", cond, 100, cond < 30 and T.red or (cond < 60 and T.orange or T.green))
		local list = {}
		if cond < 99 and #st.levels > 0 then
			local cost = math.floor(60 + (cur.cost or 0) * 0.04)
			table.insert(list, act("REPAIR " .. money(cost), T.panel2, function()
				result(State.req("RepairStation", id), st.name .. " repaired.")
			end, 160))
		end
		if nxt then
			local locked = nxt.requiresTier and P.tier < nxt.requiresTier
			UI.Line(c, string.format("Next: %s - %s  (x%.2f)%s", nxt.name, nxt.desc, nxt.mult, locked and "  [World Champions only]" or ""), { TextSize = 13, TextColor3 = locked and T.sub or T.text })
			table.insert(list, act(locked and "LOCKED" or ("UPGRADE " .. money(nxt.cost)), locked and T.panel2 or (P.money >= nxt.cost and T.gold or Color3.fromRGB(70, 40, 40)), function()
				if locked then
					return
				end
				result(State.req("UpgradeStation", id), "Upgraded: " .. nxt.name)
			end, 190))
		else
			UI.Line(c, "Top level reached.", { TextSize = 13, TextColor3 = T.gold })
		end
		if #list > 0 then
			buttons(c, list, 32)
		end
	end
end

local GEAR_KINDS = {
	{ kind = "gloves", title = "GLOVES", list = Catalog.Gloves },
	{ kind = "shoes", title = "BOXING SHOES", list = Catalog.Shoes },
	{ kind = "wraps", title = "HAND WRAPS", list = Catalog.Wraps },
	{ kind = "mouthguard", title = "MOUTHGUARDS", list = Catalog.Mouthguards },
	{ kind = "robe", title = "ROBES", list = Catalog.Robes },
}

local function gearStats(kind, item)
	local p = {}
	if kind == "gloves" then
		table.insert(p, string.format("power %+d%%", item.power * 100))
		table.insert(p, string.format("speed %+d%%", item.speed * 100))
		table.insert(p, string.format("durability x%.1f", item.durability))
	elseif kind == "shoes" then
		table.insert(p, string.format("footwork %+d%%", item.footwork * 100))
		table.insert(p, string.format("durability x%.1f", item.durability))
	elseif kind == "wraps" then
		table.insert(p, string.format("hand injury risk x%.2f", item.injury))
	elseif kind == "mouthguard" then
		table.insert(p, string.format("chin %+d", item.chin))
	elseif kind == "robe" then
		table.insert(p, string.format("popularity +%d", item.pop))
	end
	return table.concat(p, "  -  ")
end

R.Gear = function(body, P)
	UI.Line(body, "Money " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 18 })
	buttons(body, {
		act("OPEN LOCKER ROOM (customize)", T.gold, function()
			Hub.Close()
			State.open.Locker()
		end, 280),
	})
	for _, g in ipairs(GEAR_KINDS) do
		UI.Header(body, g.title)
		local eq = P.gear.equipped[g.kind]
		local cond = P.gear.cond[g.kind .. ":" .. tostring(eq)]
		if cond and g.kind ~= "mouthguard" and g.kind ~= "robe" then
			local item = Catalog.Find(g.list, eq)
			local c = UI.Card(body)
			UI.StatRow(c, "Equipped condition", cond, 100, cond < 30 and T.red or (cond < 60 and T.orange or T.green))
			if cond < 40 then
				UI.Line(c, g.kind == "gloves" and "Your gloves are cracking: less power and more hand injuries." or (g.kind == "shoes" and "Worn-out shoes slow your footwork." or "Dirty, loose wraps: more hand injuries."), { TextColor3 = T.red, TextSize = 13 })
			end
			if cond < 99 and item then
				local cost = math.floor(25 + (item.price or 0) * (g.kind == "gloves" and 0.06 or 0.08))
				buttons(c, {
					act("REPAIR " .. money(cost), T.panel2, function()
						result(State.req("RepairGear", g.kind), "Repaired.")
					end, 170),
				}, 30)
			end
		end
		for _, item in ipairs(g.list) do
			local owned = P.gear.owned[g.kind] and P.gear.owned[g.kind][item.id]
			local equipped = eq == item.id
			local locked = item.requiresTier and P.tier < item.requiresTier
			local c = UI.Card(body, { stroke = equipped and T.gold or nil })
			UI.Line(c, item.name .. (item.tier and ("  (" .. item.tier .. ")") or "") .. (equipped and "  - EQUIPPED" or ""), { Font = T.bold, TextSize = 15, TextColor3 = equipped and T.gold or T.text })
			UI.Line(c, gearStats(g.kind, item), { TextSize = 13, TextColor3 = T.sub })
			local list = {}
			if owned and not equipped then
				table.insert(list, act("EQUIP", T.panel2, function()
					result(State.req("Equip", g.kind, item.id))
				end, 110))
			end
			if not owned or (g.kind ~= "mouthguard" and g.kind ~= "robe" and item.price > 0) then
				local label = locked and "WORLD CHAMPS ONLY" or ((owned and "BUY NEW " or "BUY ") .. money(item.price))
				if not owned or (cond and cond < 50 and equipped) then
					table.insert(list, act(label, locked and T.panel2 or (P.money >= item.price and T.gold or Color3.fromRGB(70, 40, 40)), function()
						if locked then
							return
						end
						result(State.req("BuyGear", g.kind, item.id), "Bought " .. item.name .. ".")
					end, 200))
				end
			end
			if #list > 0 then
				buttons(c, list, 30)
			end
		end
	end
end

-- the coach's personality and what he adds to the training programme (Shared.TrainingPlan personas)
local function coachPersonaLine(card, specId, tier)
	local p = TP and TP.CoachPersonas[specId]
	if not p then
		return
	end
	local says = p.says and p.says[1] or ""
	local l = UI.Line(card, string.format('<font color="#%s">%s.</font> %s%s', T.text:ToHex(), string.upper(p.persona), p.perkText, says ~= "" and string.format('  <font color="#%s">"%s"</font>', T.dim:ToHex(), says) or ""),
		{ RichText = true, TextSize = 13, TextColor3 = tier > 0 and T.green or T.sub })
	l.Name = "CoachPersona"
end

R.Coaches = function(body, P)
	UI.Line(body, string.format("Money %s    Team salary per fight: %s", money(P.money), money(P.salary or 0)), { Font = T.bold, TextColor3 = T.green, TextSize = 16 })
	UI.Line(body, "Each coach boosts the stats of their specialty in training. Salaries come out of every purse. An elite Ring IQ or Defense coach also reads your opponents between rounds.", { TextColor3 = T.sub, TextSize = 13 })
	for _, spec in ipairs(Catalog.CoachSpecialties) do
		local tier = P.coaches[spec.id] or 0
		local c = UI.Card(body, { stroke = tier > 0 and T.gold or nil })
		local statNames = {}
		for _, k in ipairs(spec.stats) do
			table.insert(statNames, Config.StatNames[k])
		end
		UI.Line(c, string.format("%s coach  ·  %s", tostring(spec.name or spec.id), table.concat(statNames, ", ")), { Font = T.bold, TextColor3 = T.gold })
		coachPersonaLine(c, spec.id, tier)
		if tier > 0 then
			local def = Catalog.CoachTiers[tier]
			UI.Line(c, string.format("Hired: %s (%s, +%d%% gains, %s per fight)", Catalog.CoachNames[spec.id][tier], def.name, def.boost * 100, money(def.salary)), { TextSize = 14 })
		else
			UI.Line(c, "No coach hired.", { TextSize = 14, TextColor3 = T.sub })
		end
		local list = {}
		for t, def in ipairs(Catalog.CoachTiers) do
			if t > tier then
				table.insert(list, act(string.format("%s %s", def.name:upper(), money(def.cost)), P.money >= def.cost and T.gold or Color3.fromRGB(70, 40, 40), function()
					result(State.req("HireCoach", spec.id, t), "Hired " .. Catalog.CoachNames[spec.id][t] .. ".")
				end, 150))
			end
		end
		if tier > 0 then
			table.insert(list, act("RELEASE", T.red, function()
				result(State.req("FireCoach", spec.id), "Coach released.")
			end, 100))
		end
		buttons(c, list, 32)
	end
end

------------------------------------------------------------------------
-- Sponsors: real deals (one brand per slot), paid every fight
------------------------------------------------------------------------
local SLOT_NAMES = { trunks = "TRUNKS", robe = "ROBE", corner = "CORNER (fight night)", gear = "GEAR & MERCH" }
local SLOT_WHERE = {
	trunks = "Logo on your trunks, on billboards and in their shop window.",
	robe = "Logo on your ring robe and on billboards.",
	corner = "Their banner in your corner and on the ring apron on fight night.",
	gear = "Your face in their store window and ads around the city.",
}
local dropConfirm = nil

local function payLine(d)
	return string.format("%s per fight  +%s win  +%s KO", money(d.perFight or 0), money(d.winBonus or 0), money(d.koBonus or 0))
end

-- PvP: the record / rating, Find Match and the boxers in the server (the PvP module draws it)
R.PvP = function(body)
	local ok, PvPClient = pcall(require, script.Parent:WaitForChild("PvP", 5))
	if ok and type(PvPClient) == "table" and PvPClient.RenderInto then
		local id = renderId
		PvPClient.RenderInto(body, function()
			return stale(body, id) -- another tab took over while the list loaded
		end)
	else
		UI.Line(body, "PvP is unavailable right now.", { TextColor3 = T.sub })
	end
end

R.Sponsors = function(body, P)
	local sp = P.sponsors or {}
	local deals = sp.deals or {}
	UI.Line(body, "Sponsors pay every fight you take, with bonuses for wins and knockouts. One brand per slot. Bigger names come to you as your tier and popularity grow.", { TextColor3 = T.sub, TextSize = 13 })
	for _, slot in ipairs(Catalog.SponsorSlots) do
		local d = deals[slot]
		local c = UI.Card(body, { stroke = d and T.gold or nil })
		UI.Line(c, (SLOT_NAMES[slot] or slot:upper()) .. (d and "" or "  -  open slot"), { Font = T.bold, TextColor3 = d and T.gold or T.sub })
		if d then
			local row = UI.Row(c, 44)
			logoChip(row, d)
			local info = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0) })
			UI.List(info, 2)
			UI.Line(info, string.format("%s  (%s)", d.name, d.scope or ""), { Font = T.semi, TextSize = 15 })
			UI.Line(info, string.format("%s   -   %d fight%s left", payLine(d), d.fightsLeft or 0, (d.fightsLeft or 0) == 1 and "" or "s"), { TextSize = 12, TextColor3 = T.sub })
			UI.Line(c, SLOT_WHERE[slot] or "", { TextSize = 12, TextColor3 = T.sub })
			local confirming = dropConfirm == slot
			buttons(c, {
				act(confirming and "Confirm: End Deal" or "END DEAL", confirming and T.red or T.panel2, function()
					if not confirming then
						dropConfirm = slot
						Hub.RenderNow()
						return
					end
					dropConfirm = nil
					result(State.req("DropSponsor", slot), "Deal ended.")
				end, 180),
			}, 30)
		else
			UI.Line(c, SLOT_WHERE[slot] or "", { TextSize = 12, TextColor3 = T.sub })
		end
	end
	local offers = sp.offers or {}
	UI.Header(body, "OFFERS ON THE TABLE")
	if #offers == 0 then
		UI.Line(body, "No brand wants you yet. Win fights, climb the tiers and build your popularity.", { TextColor3 = T.sub, TextSize = 13 })
	end
	for _, o in ipairs(offers) do
		local c = UI.Card(body)
		local row = UI.Row(c, 44)
		logoChip(row, o)
		local info = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0) })
		UI.List(info, 2)
		UI.Line(info, string.format("%s  -  %s  (%s)", o.name, SLOT_NAMES[o.slot] or o.slot, o.scope or ""), { Font = T.semi, TextSize = 15 })
		UI.Line(info, string.format("%s   -   %d-fight contract%s", payLine(o), o.fights or 0, (o.signingBonus or 0) > 0 and ("   -   signing bonus " .. money(o.signingBonus)) or ""), { TextSize = 12, TextColor3 = T.sub })
		buttons(c, {
			act(o.taken and ("REPLACE " .. tostring(o.taken):upper()) or "SIGN", o.taken and T.panel2 or T.gold, function()
				if result(State.req("SignSponsor", o.id, o.taken ~= nil), "Signed with " .. o.name .. ".") then
					dropConfirm = nil
				end
			end, o.taken and 260 or 140),
		}, 30)
	end
	-- who comes next: requirements of the brands not interested yet
	local later = {}
	local active = {}
	for _, d in pairs(deals) do
		active[d.id] = true
	end
	local offered = {}
	for _, o in ipairs(offers) do
		offered[o.id] = true
	end
	for _, def in ipairs(Catalog.Sponsors) do
		if not active[def.id] and not offered[def.id] then
			local tierName = Config.Tiers[def.minTier] and Config.Tiers[def.minTier].name or ("tier " .. def.minTier)
			table.insert(later, string.format("%s (%s, %s): needs %s and %d popularity", def.name, def.scope, SLOT_NAMES[def.slot] or def.slot, tierName, def.minPop))
		end
	end
	if #later > 0 then
		local c = UI.Card(body)
		UI.Line(c, "WATCHING YOUR CAREER", { Font = T.bold, TextColor3 = T.sub })
		for _, l in ipairs(later) do
			UI.Line(c, l, { TextSize = 12, TextColor3 = T.sub })
		end
	end
end

------------------------------------------------------------------------
-- Life: home, travel around the city, garage, fame
------------------------------------------------------------------------
local CAR_NAMES = { SportsCar = "Sports Car", Supercar = "Supercar", Hypercar = "Hypercar" }
local HOME_WHERE = {
	Apartment = "Penthouse at Riverside Apartments, Main Street",
	House = "Your house on Oak Street",
	Mansion = "The Hillcrest estate at the top of Oak Street",
}
local WAKE = { { "here", "WHERE I SLEPT" }, { "home", "AT HOME" }, { "gym", "AT THE GYM" } }
-- Main Street's shops by their Signage id (the badge is the shop front's own lockup)
local CITY_GUIDE = {
	{ "supplements", "protein, creatine and pre-workout (gains buffs)" },
	{ "diner", "real food: refuel your nutrition" },
	{ "pizza", "a slice of champions (cheat meal)" },
	{ "proshop", "gloves, boots, wraps, robes by every brand" },
	{ "barber", "haircuts, fades, beards" },
	{ "motors", "sports cars, supercars and the hypercar" },
	{ "museum", "the legends, and one day your exhibit" },
	{ "tickets", "fight offers and your next card" },
}

R.Life = function(body, P)
	local home = bestHome(P)
	local owned = P.owned or {}
	-- home
	local hc = UI.Card(body, { stroke = home and T.gold or nil })
	local item = home and Catalog.Find(Catalog.Shop, home)
	UI.Line(hc, home and ("Home: " .. tostring(item and item.name or home)) or "Home: the gym bunk room", { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	UI.Line(hc, home and (HOME_WHERE[home] or "") or "You sleep in the gym's bunk room. Buy a home in the Shop to sleep better and give the city something to talk about.", { TextSize = 13, TextColor3 = T.sub })
	if item and item.sleep then
		UI.Line(hc, string.format("Sleep quality +%d%%", math.floor(item.sleep * 100 + 0.5)), { TextSize = 13, TextColor3 = T.green })
	end
	-- the home upgrades: owned ones gold with a check, the rest plain (chips, not [x] / [ ] text)
	local addRow = UI.Frame(hc, { Name = "Upgrades", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) })
	UI.List(addRow, 6, true)
	local n = 0
	for _, it in ipairs(Catalog.Shop) do
		if it.cat == "Home Upgrades" then
			n += 1
			UI.Chip(addRow, it.name, owned[it.id] and T.gold or T.dim, { order = n, icon = owned[it.id] and "check" or nil, h = 24, TextSize = 11 })
		end
	end
	local list = {}
	if home then
		table.insert(list, act("GO HOME", T.gold, function()
			travel("TravelHome")
		end, 140))
		table.insert(list, act("STEP OUTSIDE", T.panel2, function()
			travel("LeaveHome")
		end, 150))
	end
	table.insert(list, act("HOMES & UPGRADES", T.panel2, function()
		tab = "Shop"
		Hub.RenderNow()
	end, 190))
	buttons(hc, list, 34)
	if home then
		local wake = (P.settings and P.settings.wakeAt) or "here"
		local wakeH = hit(hc, 28)
		local row = UI.Row(hc, wakeH + 2)
		UI.Text(row, "Wake up:", { Size = UDim2.fromOffset(80, wakeH), AutomaticSize = Enum.AutomaticSize.None, TextSize = 13, TextColor3 = T.sub })
		for _, w in ipairs(WAKE) do
			UI.Button(row, w[2], { Size = UDim2.fromOffset(140, wakeH), TextSize = 12, BackgroundColor3 = wake == w[1] and T.gold or T.panel2, TextColor3 = wake == w[1] and T.bg or T.text }, function()
				result(State.req("SetWakeAt", w[1]))
			end)
		end
	end

	-- travel
	local tc = UI.Card(body)
	UI.Line(tc, "AROUND THE CITY", { Font = T.bold, TextColor3 = T.gold })
	local gt = P.gymTier and P.gymTier.index or 1
	-- (each trip's button carries its place's icon: the same glyph as the sign there)
	local trips = {
		act("GYM", T.panel2, function()
			travel("TravelPlace", "gym")
		end, 110, "glove"),
		act("MAIN STREET", T.panel2, function()
			travel("TravelPlace", "city")
		end, 150, "pin"),
		act(gt >= 3 and "ELITE CENTER" or "ELITE CENTER (LOCKED)", gt >= 3 and T.panel2 or Color3.fromRGB(50, 40, 40), function()
			if gt < 3 then
				State.toast("Reach the Elite facility tier first (Gym tab).", T.red)
				return
			end
			travel("TravelPlace", "elite")
		end, gt >= 3 and 160 or 210, gt >= 3 and "bolt" or "lock"),
		act("HILLCREST", T.panel2, function()
			travel("TravelPlace", "estate")
		end, 130, "home"),
	}
	if P.camp and (owned.MountainCamp or owned.EliteCamp) then
		table.insert(trips, act("TRAINING CAMP", T.gold, function()
			travel("TravelPlace", "camp")
		end, 170, "mountain"))
	end
	-- a phone keeps the trips to two rows
	local compact = compactHub()
	if compact then
		buttons(tc, { trips[1], trips[2] }, 34)
		buttons(tc, { trips[3], trips[4], trips[5] }, 34)
	else
		buttons(tc, trips, 34)
	end
	-- Main Street: each shop's badge (its sign's lockup) and what it is for
	local guide = UI.Frame(tc, { Name = "CityGuide", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local cols = compact and 1 or 2
	local bh = UI.LocationBadgeHeight(tc, 26)
	UI.Grid(guide, UDim2.new(1 / cols, cols > 1 and -4 or 0, 0, bh + 4), nil, 4)
	for i, g in ipairs(CITY_GUIDE) do
		local row = UI.Frame(guide, { Name = "Guide_" .. g[1], BackgroundTransparency = 1, LayoutOrder = i })
		local badge, _, m = UI.LocationBadge(row, g[1], 26, { sub = false, Position = UDim2.fromOffset(0, 2) })
		local bw = m and (m.width + 8) or 0
		UI.Text(row, g[2], { TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(bw, 0), Size = UDim2.new(1, -bw, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Center })
		if badge then
			badge.ZIndex = 2
		end
	end

	-- garage
	local cars = {}
	for _, id in ipairs({ "Hypercar", "Supercar", "SportsCar" }) do
		if owned[id] then
			table.insert(cars, CAR_NAMES[id])
		end
	end
	local gc = UI.Card(body)
	UI.Line(gc, "GARAGE", { Font = T.bold, TextColor3 = T.gold })
	if #cars == 0 then
		UI.Line(gc, "No car yet. Prestige Motors on Main Street sells them; your best car takes the reserved bay outside the gym.", { TextSize = 13, TextColor3 = T.sub })
	else
		UI.Line(gc, table.concat(cars, ", "), { TextSize = 15, Font = T.semi })
		UI.Line(gc, "Your best car is parked in the reserved bay at the gym" .. (home and (owned.Garage and " and the whole collection at home." or " and at home.") or "."), { TextSize = 12, TextColor3 = T.sub })
	end

	-- fame
	local fc = UI.Card(body)
	UI.Line(fc, "FAME", { Font = T.bold, TextColor3 = T.gold })
	UI.Line(fc, string.format("%s followers  ·  popularity %d", commas(followers(P)), P.popularity or 0), { TextSize = 15, Font = T.semi })
	UI.StatRow(fc, "Popularity", P.popularity or 0, 100, T.gold)
	local pop = P.popularity or 0
	local fans = pop >= 70 and "Crowds wait outside the gym and the arena, the paparazzi follow you." or (pop >= 35 and "Fans wait outside the gym with signs." or (pop >= 10 and "A few locals recognise you on the street." or "Nobody knows your name yet."))
	UI.Line(fc, fans, { TextSize = 13, TextColor3 = T.sub })
	if P.legacy then
		UI.Line(fc, string.format("Legacy %d  -  all-time rank #%d%s", P.legacy.score or 0, P.legacy.goatRank or 0, P.legacy.hof and "  -  HALL OF FAMER" or ""), { TextSize = 13 })
	end
	buttons(fc, {
		act(P.autographReady == false and "SIGNED TODAY" or "SIGN AUTOGRAPHS", P.autographReady == false and T.panel2 or T.gold, function()
			if P.autographReady == false then
				return
			end
			result(State.req("Autograph"), "The fans love you. Popularity up.")
		end, 200),
	}, 32)
end

local rankClass, rankOrg = nil, "WBA"
R.Rankings = function(body, P)
	rankClass = rankClass or P.physical.weightClass
	local navH = hit(body, 38)
	local top = UI.Row(body, navH + 2)
	local prev = UI.Button(top, "", { Size = UDim2.fromOffset(navH, navH) }, function()
		rankClass = math.max(1, rankClass - 1)
		Hub.RenderNow()
	end)
	UI.Icon(prev, "left", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	UI.Text(top, string.upper(Config.WeightClasses[rankClass].name), { Face = "display", TextSize = 24, Size = UDim2.fromOffset(190, 38), TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local nextB = UI.Button(top, "", { Size = UDim2.fromOffset(navH, navH) }, function()
		rankClass = math.min(#Config.WeightClasses, rankClass + 1)
		Hub.RenderNow()
	end)
	UI.Icon(nextB, "right", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	for _, org in ipairs(Config.Orgs) do
		UI.Button(top, org, { Size = UDim2.fromOffset(72, navH), BackgroundColor3 = org == rankOrg and T.gold or T.panel2 }, function()
			rankOrg = org
			Hub.RenderNow()
		end)
	end
	local myId = renderId
	local res = State.req("GetRankings", rankClass, rankOrg)
	if not res.ok or stale(body, myId) then
		return
	end
	if P.tier < 2 then
		UI.Line(body, "You're an amateur. Win 4 amateur bouts to turn pro and enter the world rankings.", { TextColor3 = T.gold, TextSize = 14, Font = T.semi })
	end
	for i, e in ipairs(res.list) do
		local champ = e.rank == "C"
		local b = UI.Button(body, "", { Size = UDim2.new(1, -8, 0, hit(body, 44)), BackgroundColor3 = e.isPlayer and Color3.fromRGB(58, 46, 16) or T.panel, BackgroundTransparency = e.isPlayer and 0 or (i % 2 == 0 and 0.4 or 0.15) }, function()
			if not e.isPlayer then
				showBoxer(e.id)
			end
		end)
		if e.isPlayer then
			UI.Stroke(b, T.gold, 1.5, 0.2)
		end
		local badge = UI.Frame(b, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(champ and 62 or 44, 30), BackgroundColor3 = champ and T.gold or T.panel2 })
		UI.Corner(badge, 5)
		UI.Text(badge, champ and "CHAMP" or tostring(e.rank), { Face = "number", TextSize = champ and 15 or 18, TextColor3 = champ and T.ink or T.text, Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
		local x = champ and 80 or 62
		Flags.Draw(b, e.nat, { Size = UDim2.fromOffset(27, 18), Position = UDim2.new(0, x, 0.5, -9) })
		UI.Text(b, string.format("%s  \"%s\"", e.name, e.nick), { Font = T.semi, TextSize = 15, TextColor3 = e.isPlayer and T.gold or T.text, Position = UDim2.fromOffset(x + 36, 0), Size = UDim2.new(0.55, -(x + 36), 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(b, string.format("%d-%d-%d", e.record.w, e.record.l, e.record.d), { Face = "number", TextSize = 20, Position = UDim2.new(0.56, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(b, string.format("%d KO", e.record.ko), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.new(0.76, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(b, tostring(e.overall), { Face = "number", TextSize = 20, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 40, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
end

R.Rivals = function(body, P)
	local myId = renderId
	local res = State.req("GetRivals")
	if stale(body, myId) then
		return
	end
	if not res.ok or #res.list == 0 then
		UI.Line(body, "No rivals yet. Every opponent remembers you: rematches, revenge missions and trilogies appear as offers when rivalries heat up.", { TextColor3 = T.sub })
		return
	end
	for _, r in ipairs(res.list) do
		local c = UI.Card(body)
		UI.Line(c, string.format("%s \"%s\"%s", r.name, r.nick, r.retired and "  (retired)" or ""), { Font = T.bold })
		UI.Line(c, string.format("Head-to-head: you %d - %d them, %d draws   -   %s   -   OVR %d", r.h2h.w, r.h2h.l, r.h2h.d, r.personality, r.overall), { TextSize = 14, TextColor3 = T.sub })
		UI.StatRow(c, "Rivalry heat", r.heat, 100, T.red)
		local total = r.h2h.w + r.h2h.l + r.h2h.d
		local status = r.heat >= 70 and "HEATED RIVALRY" or (r.heat >= 40 and "Rivalry" or "Old foe")
		if total == 2 and r.heat >= 40 then
			status = status .. " - TRILOGY BREWING"
		end
		UI.Line(c, status, { TextColor3 = T.red, TextSize = 13 })
	end
end

R.Shop = function(body, P)
	UI.Line(body, "Money: " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 20 })
	if P.studio then
		buttons(body, {
			act("STUDIO TEST: +$1,000,000", T.panel2, function()
				result(State.req("DebugMoney"), "Test money added (Studio only).")
			end, 260),
		})
	end
	local lastCat
	for _, item in ipairs(Catalog.Shop) do
		if item.cat ~= lastCat then
			lastCat = item.cat
			UI.Header(body, item.cat:upper())
		end
		local owned = P.owned[item.id]
		local locked = item.requiresTier and P.tier < item.requiresTier
		-- home add-ons need a home (Career.Buy checks requiresAny too)
		local needsHome = item.requiresAny and not ownsAny(P.owned, item.requiresAny)
		local isHome = item.cat == "Houses"
		local c = UI.Card(body, { stroke = owned and T.gold or nil })
		UI.Line(c, item.name, { Font = T.bold })
		UI.Line(c, item.desc, { TextSize = 13, TextColor3 = T.sub })
		if needsHome and not owned then
			local names = {}
			for _, id in ipairs(item.requiresAny) do
				local def = Catalog.Find(Catalog.Shop, id)
				table.insert(names, def and def.name or id)
			end
			UI.Line(c, "Needs: " .. table.concat(names, " or "), { TextSize = 12, TextColor3 = T.orange })
		end
		local text = owned and (isHome and "OWNED - GO HOME" or "OWNED") or (locked and "WORLD CHAMPS ONLY" or (needsHome and "NEEDS A HOME" or money(item.price)))
		local color = owned and (isHome and T.gold or T.panel2) or ((locked or needsHome) and T.panel2 or (P.money >= item.price and T.gold or Color3.fromRGB(70, 40, 40)))
		buttons(c, {
			act(text, color, function()
				if owned then
					if isHome then
						travel("TravelHome", item.id)
					end
					return
				end
				if locked or needsHome then
					return
				end
				result(State.req("Buy", item.id), "Purchased: " .. item.name)
			end, 200),
		}, 32)
	end
end

local function legacyBody(body, lg, past)
	local c = UI.Card(body)
	UI.Line(c, "LEGACY SCORE  " .. lg.score, { Font = T.bold, TextSize = 26, TextColor3 = T.gold })
	UI.Line(c, lg.hallOfFame and "Hall of Fame: inducted" or string.format("Hall of Fame needs %d legacy", Config.HallOfFameScore), { Font = T.bold, TextColor3 = lg.hallOfFame and T.gold or T.sub })
	UI.Line(c, "GOAT RANKING: #" .. lg.goatRank .. " of all time", { Font = T.bold, TextSize = 20 })
	for _, p in ipairs(lg.parts) do
		if p[2] ~= 0 then
			UI.Line(c, string.format("%s: %s%d", p[1], p[2] > 0 and "+" or "", math.floor(p[2])), { TextSize = 14, TextColor3 = T.sub })
		end
	end
	local g = UI.Card(body)
	UI.Line(g, "ALL-TIME GREATS", { Font = T.bold, TextColor3 = T.gold })
	for i, e in ipairs(lg.goatList) do
		if i <= 12 or e.you then
			UI.Line(g, string.format("%d. %s  (%d)", i, e.name, e.score), { TextSize = 14, TextColor3 = e.you and T.gold or T.text, Font = e.you and T.bold or T.font })
		end
	end
	if #lg.greatest > 0 then
		local f = UI.Card(body)
		UI.Line(f, "GREATEST FIGHTS", { Font = T.bold, TextColor3 = T.gold })
		for _, h in ipairs(lg.greatest) do
			UI.Line(f, string.format("%.1f/10  %s vs %s - %s R%d (%s)", h.rating, h.outcome:upper(), h.opp, h.method, h.round, h.kind), { TextSize = 14 })
		end
	end
	if past and #past > 0 then
		local pc = UI.Card(body)
		UI.Line(pc, "PAST CAREERS", { Font = T.bold, TextColor3 = T.gold })
		for _, x in ipairs(past) do
			UI.Line(pc, string.format("%s \"%s\"  %s  -  %d titles  -  Legacy %d  -  GOAT #%d%s", x.name, x.nick, rec(x.record), x.titles, x.score, x.goatRank, x.hof and "  - HOF" or ""), { TextSize = 13 })
		end
	end
end
Hub.LegacyBody = legacyBody

R.Legacy = function(body, P)
	local myId = renderId
	local res = State.req("GetLegacy")
	if not res.ok or stale(body, myId) then
		return
	end
	legacyBody(body, res.legacy, res.pastCareers)
	local c = UI.Card(body)
	UI.Line(c, "Retiring ends this career for good: Hall of Fame induction, career stats, greatest fights and your final GOAT ranking.", { TextColor3 = T.sub, TextSize = 14 })
	local confirm = false
	local b
	b = UI.Button(c, "RETIRE", { Size = UDim2.new(0, 220, 0, hit(c, 40)), BackgroundColor3 = T.red }, function()
		if not confirm then
			confirm = true
			b.Text = "CONFIRM RETIREMENT"
			return
		end
		local r = State.req("Retire")
		if r.ok then
			Hub.Close()
		else
			State.toast(r.err or "Can't retire now", T.red)
		end
	end)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function styleTab(name, b)
	local on = name == tab
	b.BackgroundTransparency = on and 0 or 1
	b.BackgroundColor3 = on and T.panel2 or T.panel2
	local label = b:FindFirstChild("Label")
	if label then
		label.TextColor3 = on and T.gold or T.sub
	end
	local bar = b:FindFirstChild("Active")
	if bar then
		bar.Visible = on
	end
end

-- rebuilds the open tab now: the hub's own clicks and pad steps (the selection moves on what they drew)
Hub.Renders = 0 -- how many times a tab was rebuilt (diagnostics)
function Hub.RenderNow()
	local P = State.P
	if not (shade and shade.Parent and P and P.created) then
		return
	end
	Hub.Renders += 1
	for name, b in pairs(tabButtons) do
		styleTab(name, b)
	end
	local y = content.CanvasPosition
	renderId += 1
	lazyMaps = {}
	UI.Clear(content)
	local summary = UI.Frame(content, { Name = "SectionIntro", BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, compactHub() and 54 or 70), LayoutOrder = -100 })
	UI.Icon(summary, NAV_ICONS[tab] or "glove", 28, T.gold, { Position = UDim2.fromOffset(0, 4) })
	UI.Title(summary, tab, { Position = UDim2.fromOffset(42, 0), TextSize = 24,
		Size = UDim2.new(1, -42, 0, 36), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(summary, TAB_HINTS[tab] or "", { Position = UDim2.fromOffset(42, 38), TextSize = 13,
		TextColor3 = T.sub, Size = UDim2.new(1, -42, 0, 24), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Visible = not compactHub() })
	local ok, err = pcall(R[tab], content, P)
	if not ok then
		warn("[Hub]", tab, err)
	end
	task.defer(function()
		if content and content.Parent then
			content.CanvasPosition = y
		end
		buildVisibleMaps()
	end)
end

-- a rebuild from outside (ClientMain on every profile push): hundreds of GUI objects, and the Body tab paints
-- its body map. The pushes a frame brings are one rebuild at the end of that frame, with the newest profile
local renderQueued = false
function Hub.Render()
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		Hub.RenderNow()
	end)
end

function Hub.Close()
	State.windows.Hub = nil
	if shade then
		shade:Destroy()
		shade = nil
	end
	State.HideHud("Hub", false)
end

function Hub.IsOpen()
	return shade ~= nil and shade.Parent ~= nil
end

function Hub.Open(which)
	local P = State.P
	if State.inFight() or not P or not P.created or P.retired then
		return
	end
	if which then
		tab = which
	end
	if Hub.IsOpen() then
		Hub.RenderNow()
		return
	end
	State.closeAll("Hub")
	-- the hub is modal: the HUD plate would peek out from behind it (hidden before the window exists,
	-- so the refresh this triggers does not try to render a half-built hub)
	State.HideHud("Hub", true)
	local body
	shade, win, body = UI.Window(State.gui, "Hub", 1180, 760, "CAREER HUB", { onClose = Hub.Close, scroll = false, kicker = string.format("%s  ·  %s", P.tierName, P.className) })
	State.windows.Hub = Hub.Close
	-- the side navigation: grouped tabs; on a phone a narrow rail (no group captions, centred labels)
	-- so the tab's first cards show without scrolling
	local rail = compactHub()
	local navW = rail and 76 or 192
	local side = UI.Scroll(body, { Name = "Nav", Size = UDim2.new(0, navW, 1, 0), ScrollBarThickness = rail and 0 or nil })
	UI.List(side, 2)
	tabButtons = {}
	local order = 0
	for gi, group in ipairs(NAV) do
		order += 1
		if rail then
			if gi > 1 then
				UI.Frame(side, { Name = "Gap", LayoutOrder = order, Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88 })
			end
		else
			UI.Text(side, group[1], { Font = T.semi, TextSize = 11, TextColor3 = T.dim, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), AutomaticSize = Enum.AutomaticSize.None,
				TextYAlignment = Enum.TextYAlignment.Bottom, TextWrapped = false })
		end
		for _, name in ipairs(group[2]) do
			order += 1
			local b = UI.New("TextButton", { Name = name, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.new(1, rail and -4 or -8, 0, hit(side, rail and 34 or 40)), LayoutOrder = order,
				BackgroundColor3 = T.panel2, BackgroundTransparency = 1, Parent = side })
			UI.Corner(b, UI.R.md)
			UI.Hover(b, { amount = 0.94 })
			local bar = UI.Frame(b, { Name = "Active", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(3, rail and 18 or 20), BackgroundColor3 = T.gold, Visible = false })
			UI.Corner(bar, 2)
			UI.Text(b, (rail and RAIL_LABELS[name]) or name, { Name = "Label", Face = "displayMed", TextSize = rail and 12 or 15, TextColor3 = T.sub, Position = UDim2.fromOffset(rail and 4 or 44, 0),
				Size = UDim2.new(1, rail and -8 or -50, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
				TextXAlignment = rail and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left })
			if not rail then
				UI.Icon(b, NAV_ICONS[name] or "star", 20, T.gold, { Name = "NavIcon",
					Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
			end
			b.MouseButton1Click:Connect(function()
				tab = name
				content.CanvasPosition = Vector2.zero
				Hub.RenderNow()
			end)
			tabButtons[name] = b
		end
	end
	UI.Frame(body, { Name = "NavLine", Position = UDim2.new(0, navW + 8, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92 })
	content = UI.Scroll(body, { Name = "Content", Position = UDim2.new(0, navW + (rail and 14 or 24), 0, 0), Size = UDim2.new(1, -(navW + (rail and 14 or 24)), 1, 0) })
	-- the cards' thumbnails follow the scroll (one check per frame at most; the listener dies with the window)
	content:GetPropertyChangedSignal("CanvasPosition"):Connect(queueVisibleMaps)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueVisibleMaps)
	-- the screen crosses the phone / desktop line (rotation, a resized window): rebuild for it
	local sizeConn
	-- (let go with the window: a closed hub keeps no listener on the root)
	shade.Destroying:Connect(function()
		if sizeConn then
			sizeConn:Disconnect()
		end
	end)
	sizeConn = State.gui:GetAttributeChangedSignal("UIScale"):Connect(function()
		if not (shade and shade.Parent) then
			sizeConn:Disconnect()
			return
		end
		if compactHub() ~= rail then
			sizeConn:Disconnect()
			task.defer(function()
				if Hub.IsOpen() then
					local keep = tab
					Hub.Close()
					Hub.Open(keep)
				end
			end)
		end
	end)
	UI.List(content, 10)
	UI.Pad(content, 2, 4)
	-- gamepad: the open tab's button is where the selection starts; LB / RB step through the tabs in the
	-- order the side navigation shows them (while the hub is the top window: not under a scouting card)
	UI.PadStart(tabButtons[tab])
	local flat = {}
	for _, group in ipairs(NAV) do
		for _, name in ipairs(group[2]) do
			table.insert(flat, name)
		end
	end
	local myWin = win
	local padConn = UserInputService.InputBegan:Connect(function(input)
		local k = input.KeyCode
		if (k ~= Enum.KeyCode.ButtonL1 and k ~= Enum.KeyCode.ButtonR1) or UI.PadTop() ~= myWin or UserInputService:GetFocusedTextBox() then
			return
		end
		local i = table.find(flat, tab) or 1
		tab = flat[(i - 1 + (k == Enum.KeyCode.ButtonR1 and 1 or -1)) % #flat + 1]
		content.CanvasPosition = Vector2.zero
		Hub.RenderNow()
		local b = tabButtons[tab]
		if b and UI.IsPad() then
			GuiService.SelectedObject = b
		end
	end)
	shade.Destroying:Connect(function()
		padConn:Disconnect()
	end)
	Hub.RenderNow()
end

function Hub.Toggle()
	if Hub.IsOpen() then
		Hub.Close()
	else
		Hub.Open()
	end
end

State.open.Hub = Hub.Open
return Hub
