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
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local FighterCard = require(script.Parent:WaitForChild("FighterCard"))
local BodyMap = require(script.Parent:WaitForChild("BodyMap"))
-- the Muscle Progression screen (3D figure, groups, growth graphs); registers State.open.Muscle
local okMuscle, MuscleScreen = pcall(require, script.Parent:WaitForChild("MuscleScreen"))
if not okMuscle then
	MuscleScreen = nil
end
local Flags = require(script.Parent:WaitForChild("Flags"))
local T = UI.Theme
local rec = State.rec

local Hub = {}
local shade, win, content
local tab = "Career"
-- every Hub.Render bumps it; a tab that waited on the server stops when it is stale (closed, re-rendered or
-- rebuilt for another screen size meanwhile), so no rows land in a destroyed or newer list
local renderId = 0
local function stale(body, id)
	return id ~= renderId or not body.Parent
end
local TABS = { "Career", "Training", "Body", "Stats", "Gym", "Gear", "Coaches", "Sponsors", "Life", "Rankings", "Rivals", "PvP", "Shop", "Legacy" }
Hub.Tabs = TABS -- every tab (the side navigation groups them in NAV)
-- the side navigation, grouped like a sports game's career menu
local NAV = {
	{ "CAREER", { "Career", "Rankings", "Rivals", "PvP", "Legacy" } },
	{ "TRAINING", { "Training", "Body", "Stats", "Gym", "Coaches" } },
	{ "LIFE", { "Gear", "Sponsors", "Life", "Shop" } },
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

local function act(text, color, fn, width)
	return function(parent)
		return UI.Button(parent, text, { Size = UDim2.new(0, width or 170, 1, 0), BackgroundColor3 = color or T.panel2, TextColor3 = (color == T.gold) and T.bg or T.text, TextSize = 14 }, fn)
	end
end

local function buttons(parent, list, h)
	local row = UI.Row(parent, h or 36)
	for _, make in ipairs(list) do
		make(row)
	end
	return row
end

-- a sponsor's logo as a little coloured badge (bg / fg / text from Catalog.Sponsors logo)
local function logoChip(parent, logo, w, h)
	logo = type(logo) == "table" and logo or {}
	local f = UI.Frame(parent, { Size = UDim2.fromOffset(w or 130, h or 40), BackgroundColor3 = rgb(logo.bg, T.panel2) })
	UI.Corner(f, 6)
	UI.Text(f, tostring(logo.text or "?"), { Font = T.bold, TextScaled = true, TextColor3 = rgb(logo.fg, T.text), Size = UDim2.new(1, -10, 0.62, 0), Position = UDim2.fromOffset(5, 3), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	if logo.glyph then
		UI.Text(f, tostring(logo.glyph), { Font = T.semi, TextScaled = true, TextColor3 = rgb(logo.fg, T.text), Size = UDim2.new(1, -10, 0.28, 0), Position = UDim2.new(0, 5, 0.66, 0), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
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
	UI.Stat(strip, string.format("%d-%d-%d", b.record.w, b.record.l, b.record.d), "RECORD", { Size = UDim2.new(0.36, -8, 1, 0), order = 1, valueSize = 28, scaled = true })
	UI.Stat(strip, tostring(b.record.ko), "KOS", { Size = UDim2.new(0.2, -8, 1, 0), order = 2, valueSize = 28, valueColor = T.red })
	UI.Stat(strip, tostring(b.overall), "OVERALL", { Size = UDim2.new(0.22, -8, 1, 0), order = 3, valueSize = 28, valueColor = T.gold })
	UI.Stat(strip, tostring(math.floor(b.heat or 0)), "RIVALRY", { Size = UDim2.new(0.22, -8, 1, 0), order = 4, valueSize = 28 })
	UI.Line(body, string.format("%s  ·  %s  ·  %s", b.style, b.archetype ~= "" and b.archetype or "?", b.personality), { TextColor3 = T.sub, TextSize = 14 })
	UI.Line(body, "Rankings: " .. rankText(b.ranks), { Font = T.semi, TextSize = 14 })
	if b.belts and #b.belts > 0 then
		UI.Line(body, "HOLDS: " .. table.concat(b.belts, "  ·  "), { TextColor3 = T.gold, Font = T.semi })
	end
	if b.h2h.w + b.h2h.l + b.h2h.d > 0 then
		UI.Line(body, string.format("HEAD TO HEAD: you %d - %d them (%d draws)", b.h2h.w, b.h2h.l, b.h2h.d), { TextColor3 = T.red, Font = T.semi })
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
	if o.h2h and (o.h2h.w + o.h2h.l + o.h2h.d) > 0 then
		UI.Line(parent, string.format("RIVALRY: you %d - %d them (%d draws)  ·  heat %d", o.h2h.w, o.h2h.l, o.h2h.d, math.floor(o.heat or 0)), { TextColor3 = T.red, Font = T.semi, TextSize = 13 })
	end
	if o.belts and #o.belts > 0 then
		UI.Line(parent, "HOLDS: " .. table.concat(o.belts, "  ·  "), { TextColor3 = T.gold, Font = T.semi, TextSize = 13 })
	end
end

-- "AMATEUR BOUT · 3 ROUNDS · COMMUNITY CENTER" on the left, the purse on the right
local function fightHeader(parent, o, special)
	local row = UI.Frame(parent, { Name = "FightHeader", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) })
	UI.Text(row, string.format("%s  ·  %d ROUNDS  ·  %s", o.kind:upper(), o.rounds, string.upper(o.venueName or "")), { Font = T.semi, TextSize = 12, TextColor3 = special and T.gold or T.sub,
		Size = UDim2.new(1, -150, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
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
-- Tabs
------------------------------------------------------------------------
local R = {}

R.Career = function(body, P)
	FighterCard.Compact(body, P, { order = 0 })
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
	local chips = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	UI.List(chips, 8, true)
	UI.Chip(chips, "Day " .. P.day, T.text, { order = 1 })
	UI.Chip(chips, "Purse " .. money(P.money), T.gold, { order = 2 })
	UI.Chip(chips, commas(followers(P)) .. " followers", T.cyan, { order = 3 })
	UI.Chip(chips, "Popularity " .. P.popularity, T.text, { order = 4 })
	if #deals > 0 then
		UI.Chip(chips, "Sponsored: " .. table.concat(deals, ", "), T.green, { order = 5 })
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
		UI.Line(body, "TITLES: " .. table.concat(belts, "  ·  ") .. string.format("   (defenses %d)", P.defenses), { TextColor3 = T.gold, Font = T.semi, TextSize = 14 })
	end
	if not P.storeOk then
		UI.Line(body, "Saving is off in this session (enable Studio API access or publish the game to save progress).", { TextColor3 = T.red, TextSize = 13 })
	end

	if P.camp then
		UI.Header(body, "FIGHT CAMP", T.red)
		local c = UI.Card(body, { stroke = T.red })
		local o = P.camp.offer
		fightHeader(c, o, true)
		oppBlock(c, o.opp)
		quote(c, o.talk)
		local stakes = stakesText(o)
		if #stakes > 0 then
			UI.Line(c, "ON THE LINE: " .. table.concat(stakes, "  ·  ") .. " WORLD TITLE" .. (#stakes > 1 and "S" or ""), { Font = T.semi, TextColor3 = T.gold, TextSize = 14 })
		end
		-- camp countdown and the weight cut
		local meters = UI.Frame(c, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
		UI.List(meters, 8, true)
		UI.Stat(meters, tostring(P.camp.daysLeft), "CAMP DAYS LEFT", { Size = UDim2.new(0.33, -6, 1, 0), order = 1, valueSize = 28, valueColor = P.camp.daysLeft <= 0 and T.gold or T.text })
		UI.Stat(meters, string.format("%.1f", P.weight), string.format("WEIGHT / %d LBS", P.weightLimit), { Size = UDim2.new(0.33, -6, 1, 0), order = 2, valueSize = 28, valueColor = P.overWeight > 0 and T.red or T.green })
		UI.Stat(meters, money(o.purse), "PURSE", { Size = UDim2.new(0.34, -6, 1, 0), order = 3, valueSize = 28, valueColor = T.green, scaled = true })
		if P.overWeight > 0 then
			UI.Line(c, string.format("You're %.1f lbs over the limit! Burn fat with cardio or cut water in the sauna before fight night - missing weight costs stamina and %s.", P.overWeight, P.overWeight > 2 and "20% of your purse" or "no fine yet"), { TextColor3 = T.red, TextSize = 13 })
		end
		if #P.camp.log > 0 then
			UI.Line(c, "Camp so far: " .. table.concat(P.camp.log, ", "):sub(1, 220), { TextColor3 = T.sub, TextSize = 12 })
		end
		local ready = P.camp.daysLeft <= 0
		UI.Line(c, ready and "Camp is complete. It's FIGHT NIGHT." or "Train at the gym, eat, sleep: each night is a camp day. You can also fight early (fewer camp days).", { TextColor3 = ready and T.gold or T.sub, TextSize = 13 })
		local confirmEarly = false
		local fightBtn
		buttons(c, {
			function(row)
				fightBtn = UI.Button(row, ready and "FIGHT NIGHT (LIVE)" or "FIGHT NOW (EARLY)", { Size = UDim2.new(0, 230, 1, 0), BackgroundColor3 = T.red, TextSize = 16 }, function()
					if not ready and not confirmEarly then
						confirmEarly = true
						fightBtn.Text = "CONFIRM: FIGHT EARLY"
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
					UI.Line(c, "ON THE LINE: " .. table.concat(stakes, "  ·  "), { TextColor3 = T.gold, TextSize = 13, Font = T.semi })
				end
				buttons(c, {
					act("ACCEPT FIGHT", T.gold, function()
						if result(State.req("AcceptOffer", i), "Fight signed! Training camp begins.") then
							Hub.Render()
						end
					end, 180),
					act("SCOUT", T.panel2, function()
						showBoxer(o.oppId)
					end, 110),
				}, 40)
			end
			UI.Line(body, "Offers refresh every week (7 days). Rivals with heat call you out for rematches and trilogies.", { TextColor3 = T.sub, TextSize = 13 })
		end
		local wc = UI.Card(body)
		UI.Line(wc, "WEIGHT CLASS: " .. P.className:upper() .. string.format("  ·  limit %d lbs, you weigh %.1f", P.weightLimit, P.weight), { Font = T.semi, TextSize = 14 })
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

local AREAS = { "Boxing Area", "Weight Room", "Cardio Room", "Outdoors", "Pool", "Recovery Area" }
local function gainsText(a)
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local w = a.gains and a.gains[k]
		if w then
			table.insert(parts, Config.StatNames[k] .. (w >= 0.9 and " ++" or " +"))
		end
	end
	return table.concat(parts, ", ")
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
	local frameDef = Config.FindById(Config.BodyTypes, P.appearance and P.appearance.body and P.appearance.body.frame or "") or Config.BodyTypes[2]
	return 100 * (frameDef.potential or 1), frameDef
end

local function partLevel(P, id)
	return tonumber(Config.PartValue and Config.PartValue(P.body, id) or (P.body and P.body[id])) or 0
end

-- one condition meter tile: big number, caption, bar
local function meterTile(parent, caption, value, color, order)
	local f, v = UI.Stat(parent, tostring(math.floor(value)), caption, { Size = UDim2.new(0.25, -8, 1, 0), order = order, valueSize = 30, valueColor = color })
	local _, set = UI.Bar(f, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 4) }, color)
	set(value / 100)
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
local function exerciseCard(grid, a, P, order, cap)
	local st = Catalog.Stations[a.station]
	local lv = math.max(1, P.gym.levels[a.station] or 1)
	local lvName = st and st.levels[math.min(lv, #st.levels)].name or ""
	local cost = a.recovery and (a.price and (P.gym.levels.massage or 1) < 2 and money(a.price) or "free") or ("energy " .. (a.id == "Sparring" and "25-45" or tostring(a.energy)))
	local tile = UI.Frame(grid, { Name = "Activity", LayoutOrder = order, BackgroundColor3 = T.panel, BackgroundTransparency = 0.05 })
	UI.Corner(tile, UI.R.lg)
	UI.Stroke(tile, Color3.new(1, 1, 1), 1, 0.92)
	local accent = UI.Frame(tile, { Size = UDim2.new(0, 3, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = a.recovery and T.blue or T.red })
	UI.Corner(accent, 2)
	local THUMB_W = 78
	local right = THUMB_W + 22
	UI.Text(tile, string.upper(a.name), { Face = "displayMed", TextSize = 20, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -(right + 90), 0, 24), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Chip(tile, cost, a.recovery and T.blue or T.gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, 10), TextSize = 12 })
	local detail = a.recovery and a.desc or gainsText(a)
	UI.Text(tile, detail, { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -(right + 12), 0, a.recovery and 52 or 18), AutomaticSize = Enum.AutomaticSize.None,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = a.recovery == true, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the muscles it works: name, level against the potential (tick), the level number
	local listed = {}
	if not a.recovery then
		for i, e in ipairs(topParts(a, 3)) do
			listed[e.id] = e.w
			local y = 56 + (i - 1) * 21
			local v = partLevel(P, e.id)
			UI.Text(tile, string.upper(BodyMap.Short(e.id)), { Font = T.semi, TextSize = 12, TextColor3 = e.k >= 0.75 and T.text or T.sub, Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(96, 16),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.LevelBar(tile, { Position = UDim2.fromOffset(116, y + 5), Size = UDim2.new(1, -(right + 116 + 40), 0, 7) }, { value = v, cap = cap, color = workColor(e.k) })
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
		local _, set = UI.Bar(tile, { Position = UDim2.fromOffset(48, by + 13), Size = UDim2.new(1, -(right + 48 + 92), 0, 6) }, gcol)
		set(pct / 100)
		UI.Text(tile, string.format("%d%%  ·  %d×", pct, sessions), { Face = "number", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(right + 2), 0, by + 2),
			Size = UDim2.fromOffset(88, 18), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	else
		UI.Text(tile, lvName ~= "" and ("NOT TRIED YET  ·  " .. string.upper(lvName)) or "NOT TRIED YET", { Font = T.semi, TextSize = 12, TextColor3 = T.dim, Position = UDim2.fromOffset(16, by + 2),
			Size = UDim2.new(1, -(right + 16), 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	-- the body map: what it works (recovery: the whole body, cool)
	local ok, map = pcall(BodyMap.new, tile, { Size = UDim2.fromOffset(THUMB_W, 100), views = "front", labels = false, glow = false, AnchorPoint = Vector2.new(1, 0),
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
	UI.Button(tile, "GO", { Size = UDim2.fromOffset(THUMB_W, 32), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), BackgroundColor3 = T.gold, TextSize = 16 }, function()
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

R.Training = function(body, P)
	local c = P.condition
	local compact = compactHub()
	local card = UI.Card(body)
	-- the card's header: the kicker, and the moves list / control map (ControlsMenu) on the right -
	-- what the drills and the ring run on
	local head = UI.Frame(card, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28) })
	UI.Kicker(head, string.format("CONDITION  ·  DAY %d", P.day), T.gold, { Size = UDim2.new(1, -196, 1, 0) })
	if State.open.Controls then
		local mc = UI.Button(head, "MOVES & CONTROLS", { Name = "MovesControls", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(compact and 150 or 180, 28),
			BackgroundColor3 = T.panel2, TextSize = 13 }, function()
			Hub.Close()
			State.open.Controls()
		end)
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
		UI.Chip(chips, string.format("Sleep %d%%", math.floor(c.sleepQ * 100)), T.blue, { order = 1, TextSize = 12 })
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
		UI.Line(card, string.format("FACE: %s%s - about %d day%s to heal.", tostring(f.label or ""), #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "", f.days or 0, (f.days or 0) == 1 and "" or "s"),
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
		UI.Line(card, "SORE: " .. table.concat(soreTxt, ", ") .. (compact and "" or "  - growth is slower on sore muscles; sleep and eat to recover."), { TextColor3 = T.orange, TextSize = 13 })
	end
	if c.fatigue > 70 then
		UI.Line(card, "OVERTRAINING: gains are cut in half and injury risk is high. Recover (ice bath, massage, stretching) or sleep.", { TextColor3 = T.red, TextSize = 13, Font = T.semi })
	elseif c.fatigue > 40 and not compact then
		UI.Line(card, "Fatigue is building - gains are dropping. Mix in recovery.", { TextColor3 = T.orange, TextSize = 13 })
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
	local cap = frameCap(P)
	local cols = (UI.CanvasSize(State.gui).X - (compact and 120 or 260)) >= 700 and 2 or 1
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
	MuscleScreen.Open({ group = group, back = function()
		if not State.inFight() then
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
	-- the physique hero: the body map coloured by development toward the frame's potential (dark =
	-- untrained, gold = at the potential) beside the physique and the three muscles to train next
	local c = UI.Card(body, { stroke = T.gold })
	local mapW, mapH = compact and 220 or 330, compact and 290 or 420
	local top = UI.Frame(c, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, mapH) })
	local map = BodyMap.new(top, { Size = UDim2.fromOffset(mapW, mapH), legend = true })
	map:SetDevelopment(dev, cap)
	local info = UI.Frame(top, { BackgroundTransparency = 1, Position = UDim2.fromOffset(mapW + 24, 0), Size = UDim2.new(1, -(mapW + 24), 1, 0) })
	UI.List(info, 6)
	UI.Kicker(info, "PHYSIQUE", T.gold, { order = 1 })
	UI.Title(info, tostring(P.physique or "?"):upper(), { TextSize = compact and 32 or 40, Size = UDim2.new(1, 0, 0, compact and 36 or 44), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	if P.physiqueDesc and P.physiqueDesc ~= "" then
		UI.Line(info, P.physiqueDesc, { TextSize = 14, LayoutOrder = 3, TextColor3 = T.sub })
	end
	if P.physiquePinned and not compact then
		UI.Line(info, "Look chosen in the creator: training still grows every muscle, the silhouette keeps this archetype.", { TextColor3 = T.sub, TextSize = 13, LayoutOrder = 4 })
	end
	-- the three least developed muscles (against the potential), each with the exercise that builds it
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
	UI.Kicker(info, "TRAIN NEXT  ·  YOUR WEAKEST MUSCLES", T.red, { order = 5 })
	for i = 1, 3 do
		local e = order[i]
		if not e then
			break
		end
		local ex = bestExerciseFor(e.id)
		local row = UI.Frame(info, { BackgroundColor3 = T.panel2, BackgroundTransparency = 0.45, Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 5 + i })
		UI.Corner(row, UI.R.md)
		UI.Text(row, string.upper(BodyMap.Short(e.id)) .. (ex and string.format('<font color="#%s">  ·  %s</font>', T.sub:ToHex(), string.upper(ex.name)) or ""), {
			Face = "displayMed", TextSize = 18, RichText = true, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -150, 0, 22), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.LevelBar(row, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -196, 0, 8) }, { value = e.v, cap = cap, color = BodyMap.DevColor(e.v / cap) })
		UI.Text(row, string.format("%d / %d", math.floor(e.v + 0.5), math.floor(cap + 0.5)), { Face = "number", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 26),
			Size = UDim2.fromOffset(52, 18), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		if ex then
			UI.Button(row, "TRAIN THIS", { Size = UDim2.fromOffset(120, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg, TextSize = 14 }, function()
				startExercise(ex)
			end)
		end
	end
	-- the 3D muscle view: the figure to turn, every group lit, growth over time
	if MuscleScreen then
		local b = UI.Button(info, "3D MUSCLE VIEW  ·  GROWTH OVER TIME", { Name = "MuscleView", Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 9, BackgroundColor3 = T.panel2, TextSize = 14 }, function()
			openMuscleScreen(nil)
		end)
		UI.Stroke(b, T.gold, 1, 0.5)
	end
	-- the archetype ladder: where this build sits among the physiques the game recognises
	local row = UI.Frame(c, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	UI.List(row, 6, true)
	for i, ph in ipairs(Config.Physiques) do
		local cur = ph.id == P.physiqueId or ph.name == P.physique
		if cur then
			UI.Badge(row, ph.name, T.gold, { order = i, h = 26, TextSize = 12 })
		elseif not compact then
			UI.Chip(row, ph.name, T.sub, { order = i, h = 26, TextSize = 12 })
		end
	end
	local fat = P.body.fat or 14
	local ph = Config.FindById(Config.Physiques, P.physiqueId or "")
	local def = Config.Definition(fat, ph and ph.defBonus or 0)
	UI.Line(c, string.format("Height %s  ·  Reach %d in  ·  Weight %.1f lbs  ·  Frame: %s (potential %d)",
		Config.HeightText(P.physical.height), P.physical.reach, P.weight, P.appearance.body.frame, math.floor(cap + 0.5)), { TextSize = 14 })
	UI.StatRow(c, "Body fat", fat - 6, 24, fat > 18 and T.orange or T.green, string.format("%.1f%%", fat))
	UI.StatRow(c, "Definition", def * 100, 100, Color3.fromRGB(150, 200, 255), string.format("%d%%", math.floor(def * 100 + 0.5)))
	UI.StatRow(c, "Vascularity", P.body.vasc or 0, 100, Color3.fromRGB(110, 150, 230), string.format("%d", math.floor(P.body.vasc or 0)))
	local fat2 = fat >= Config.BodyFat.bellyAt and "A soft belly is showing - cardio and clean meals bring the abs back."
		or (def >= Config.BodyFat.absRow4Def and "Shredded: full eight-pack, veins and muscle separation on show."
		or (def >= 0.4 and "Abs are visible; drop a little more fat for full separation." or "Muscles are smooth under the skin - lower body fat brings out definition."))
	UI.Line(c, fat2, { TextColor3 = T.sub, TextSize = 13 })

	-- every muscle under its group: the level bar (fill = level, gold tick = your frame's potential)
	local sore = P.condition and P.condition.sore or {}
	local m = UI.Card(body)
	UI.Kicker(m, "MUSCLE DEVELOPMENT", T.gold)
	UI.Line(m, string.format("Bars fill toward 100; the gold tick is your frame's potential (%d). Soreness shows in orange.", math.floor(cap + 0.5)), { TextColor3 = T.sub, TextSize = 13 })
	local function levelRow(parent, label, v, h, strong, labelColor)
		local f = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h) })
		-- a group row leaves room for its "3D" button before the bar
		UI.Text(f, label, { Font = strong and T.semi or T.font, TextSize = strong and 14 or 13, TextColor3 = labelColor or (strong and T.text or T.sub), Size = UDim2.new(0.34, (strong and MuscleScreen) and -44 or 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.LevelBar(f, { Position = UDim2.new(0.34, 0, 0.5, strong and -5 or -3), Size = UDim2.new(0.52, 0, 0, strong and 10 or 6) }, { value = v, cap = cap, color = BodyMap.DevColor(v / cap) })
		UI.Text(f, string.format("%.1f", v), { Face = "number", TextSize = strong and 16 or 14, Position = UDim2.new(0.86, 0, 0, 0), Size = UDim2.new(0.14, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		return f
	end
	for _, k in ipairs(Config.MuscleKeys) do
		local sv = tonumber(sore[k]) or 0
		local gname = Config.MuscleNames[k]:upper() .. (sv >= 0.1 and string.format("  ·  SORE %d%%", math.floor(sv * 100)) or "")
		local groupRow = levelRow(m, gname, tonumber(P.body[k]) or 0, 26, true, sv >= 0.4 and T.orange or nil)
		if MuscleScreen then
			-- the group's own page of the muscle screen (its figure lit, its growth graph)
			UI.Button(groupRow, "3D", { Name = "View_" .. k, Size = UDim2.fromOffset(34, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.33, 0, 0.5, 0), BackgroundColor3 = T.panel2, TextSize = 12 }, function()
				openMuscleScreen(k)
			end)
		end
		for _, part in ipairs(Config.MuscleGroupParts[k] or {}) do
			levelRow(m, "      " .. BodyMap.Short(part.id), dev[part.id] or 0, 20, false)
		end
	end

	-- flex in front of the mirror: shows off the pump, veins and every muscle you built
	local fl = UI.Card(body)
	UI.Kicker(fl, "FLEX", T.gold)
	UI.Line(fl, "Strike a pose wherever you stand. Freshly trained muscles show a pump and the veins come up.", { TextColor3 = T.sub, TextSize = 13 })
	local flexRow = UI.Row(fl, 34)
	for _, pose in ipairs((Config.Pump and Config.Pump.poses) or {}) do
		UI.Button(flexRow, FLEX_NAMES[pose] or pose, { Size = UDim2.fromOffset(132, 32), TextSize = 13 }, function()
			local r = State.req("Flex", pose)
			if r.ok then
				Hub.Close()
			else
				State.toast(r.err or "Can't flex right now.", T.red)
			end
		end)
	end

	local g = UI.Card(body)
	UI.Kicker(g, "WHAT BUILDS WHAT", T.gold)
	for _, line in ipairs(exerciseGuide()) do
		UI.Line(g, line, { TextSize = 13, TextColor3 = T.sub })
	end
	UI.Line(body, "Every session grows the muscles it works; most of the growth lands overnight if you sleep and eat well. Muscles you neglect for a week start to fade. Muscle adds punching power and weight; fat costs stamina and makes weight harder to make. Bulk up and you may need to move up a division.", { TextColor3 = T.sub, TextSize = 13 })
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
	UI.Line(body, "Confidence boosts power, Focus improves accuracy, Composure helps you beat the count, Discipline speeds up training, Aggression adds pop. Stats gain less as they get higher - and age catches up with everyone after 30.", { TextColor3 = T.sub, TextSize = 13 })
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
	UI.Line(c, string.format("FACILITY: %s (%d%%)", tostring(gt.name or gt.id):upper(), math.floor((gt.frac or 0) * 100 + 0.5)), { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
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
		local chip = UI.Text(row, t.name, { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, TextSize = 11, Font = cur and T.bold or T.font, TextWrapped = false, TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0,
			BackgroundColor3 = cur and T.gold or (reached and Color3.fromRGB(60, 50, 20) or T.panel2), TextColor3 = cur and T.bg or (reached and T.gold or T.sub) })
		UI.Corner(chip, 6)
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
	UI.Line(body, "Better equipment = faster gains (and it looks the part). Equipment wears down with use: below 30% condition gains drop - repair it.", { TextColor3 = T.sub, TextSize = 13 })
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
				UI.Line(c, g.kind == "gloves" and "Your gloves are cracking - less power and more hand injuries." or (g.kind == "shoes" and "Worn-out shoes slow your footwork." or "Dirty, loose wraps - more hand injuries."), { TextColor3 = T.red, TextSize = 13 })
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
		UI.Line(c, string.format("%s COACH  -  %s", (spec.name or spec.id):upper(), table.concat(statNames, ", ")), { Font = T.bold, TextColor3 = T.gold })
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
					result(State.req("HireCoach", spec.id, t), "Hired " .. Catalog.CoachNames[spec.id][t] .. "!")
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
			logoChip(row, d.logo)
			local info = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0) })
			UI.List(info, 2)
			UI.Line(info, string.format("%s  (%s)", d.name, d.scope or ""), { Font = T.semi, TextSize = 15 })
			UI.Line(info, string.format("%s   -   %d fight%s left", payLine(d), d.fightsLeft or 0, (d.fightsLeft or 0) == 1 and "" or "s"), { TextSize = 12, TextColor3 = T.sub })
			UI.Line(c, SLOT_WHERE[slot] or "", { TextSize = 12, TextColor3 = T.sub })
			local confirming = dropConfirm == slot
			buttons(c, {
				act(confirming and "CONFIRM: END DEAL" or "END DEAL", confirming and T.red or T.panel2, function()
					if not confirming then
						dropConfirm = slot
						Hub.Render()
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
		logoChip(row, o.logo)
		local info = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0) })
		UI.List(info, 2)
		UI.Line(info, string.format("%s  -  %s  (%s)", o.name, SLOT_NAMES[o.slot] or o.slot, o.scope or ""), { Font = T.semi, TextSize = 15 })
		UI.Line(info, string.format("%s   -   %d-fight contract%s", payLine(o), o.fights or 0, (o.signingBonus or 0) > 0 and ("   -   signing bonus " .. money(o.signingBonus)) or ""), { TextSize = 12, TextColor3 = T.sub })
		buttons(c, {
			act(o.taken and ("REPLACE " .. tostring(o.taken):upper()) or "SIGN", o.taken and T.panel2 or T.gold, function()
				if result(State.req("SignSponsor", o.id, o.taken ~= nil), "Signed with " .. o.name .. "!") then
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
local CITY_GUIDE = {
	{ "Iron Supplements", "protein, creatine and pre-workout (gains buffs)" },
	{ "Champ's Diner / Tony's Pizza", "real food: refuel your nutrition" },
	{ "WCB Pro Shop", "gloves, boots, wraps, robes by every brand" },
	{ "Fresh Fades Barbershop", "haircuts, fades, beards" },
	{ "Prestige Motors", "sports cars, supercars and the hypercar" },
	{ "Boxing Hall of Fame Museum", "the legends - and one day your exhibit" },
	{ "WCB Arena Tickets", "fight offers and your next card" },
}

R.Life = function(body, P)
	local home = bestHome(P)
	local owned = P.owned or {}
	-- home
	local hc = UI.Card(body, { stroke = home and T.gold or nil })
	local item = home and Catalog.Find(Catalog.Shop, home)
	UI.Line(hc, home and ("HOME: " .. (item and item.name or home):upper()) or "HOME: THE GYM BUNK ROOM", { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	UI.Line(hc, home and (HOME_WHERE[home] or "") or "You sleep in the gym's bunk room. Buy a home in the Shop to sleep better and give the city something to talk about.", { TextSize = 13, TextColor3 = T.sub })
	if item and item.sleep then
		UI.Line(hc, string.format("Sleep quality +%d%%", math.floor(item.sleep * 100 + 0.5)), { TextSize = 13, TextColor3 = T.green })
	end
	local addons = {}
	for _, it in ipairs(Catalog.Shop) do
		if it.cat == "Home Upgrades" then
			table.insert(addons, (owned[it.id] and "[x] " or "[ ] ") .. it.name)
		end
	end
	UI.Line(hc, "Upgrades: " .. table.concat(addons, "   "), { TextSize = 12, TextColor3 = T.sub })
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
		Hub.Render()
	end, 190))
	buttons(hc, list, 34)
	if home then
		local wake = (P.settings and P.settings.wakeAt) or "here"
		local row = UI.Row(hc, 30)
		UI.Text(row, "Wake up:", { Size = UDim2.fromOffset(80, 28), AutomaticSize = Enum.AutomaticSize.None, TextSize = 13, TextColor3 = T.sub })
		for _, w in ipairs(WAKE) do
			UI.Button(row, w[2], { Size = UDim2.fromOffset(140, 28), TextSize = 12, BackgroundColor3 = wake == w[1] and T.gold or T.panel2, TextColor3 = wake == w[1] and T.bg or T.text }, function()
				result(State.req("SetWakeAt", w[1]))
			end)
		end
	end

	-- travel
	local tc = UI.Card(body)
	UI.Line(tc, "AROUND THE CITY", { Font = T.bold, TextColor3 = T.gold })
	local gt = P.gymTier and P.gymTier.index or 1
	local trips = {
		act("GYM", T.panel2, function()
			travel("TravelPlace", "gym")
		end, 110),
		act("MAIN STREET", T.panel2, function()
			travel("TravelPlace", "city")
		end, 140),
		act(gt >= 3 and "ELITE CENTER" or "ELITE CENTER (LOCKED)", gt >= 3 and T.panel2 or Color3.fromRGB(50, 40, 40), function()
			if gt < 3 then
				State.toast("Reach the Elite facility tier first (Gym tab).", T.red)
				return
			end
			travel("TravelPlace", "elite")
		end, 200),
		act("HILLCREST", T.panel2, function()
			travel("TravelPlace", "estate")
		end, 120),
	}
	if P.camp and (owned.MountainCamp or owned.EliteCamp) then
		table.insert(trips, act("TRAINING CAMP", T.gold, function()
			travel("TravelPlace", "camp")
		end, 160))
	end
	buttons(tc, trips, 34)
	for _, g in ipairs(CITY_GUIDE) do
		UI.Line(tc, g[1] .. "  -  " .. g[2], { TextSize = 12, TextColor3 = T.sub })
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
	UI.Line(fc, string.format("%s followers  -  popularity %d", commas(followers(P)), P.popularity or 0), { TextSize = 15, Font = T.semi })
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
	local top = UI.Row(body, 40)
	local prev = UI.Button(top, "", { Size = UDim2.fromOffset(38, 38) }, function()
		rankClass = math.max(1, rankClass - 1)
		Hub.Render()
	end)
	UI.Icon(prev, "left", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	UI.Text(top, string.upper(Config.WeightClasses[rankClass].name), { Face = "display", TextSize = 24, Size = UDim2.fromOffset(190, 38), TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local nextB = UI.Button(top, "", { Size = UDim2.fromOffset(38, 38) }, function()
		rankClass = math.min(#Config.WeightClasses, rankClass + 1)
		Hub.Render()
	end)
	UI.Icon(nextB, "right", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	for _, org in ipairs(Config.Orgs) do
		UI.Button(top, org, { Size = UDim2.fromOffset(72, 38), BackgroundColor3 = org == rankOrg and T.gold or T.panel2 }, function()
			rankOrg = org
			Hub.Render()
		end)
	end
	local myId = renderId
	local res = State.req("GetRankings", rankClass, rankOrg)
	if not res.ok or stale(body, myId) then
		return
	end
	if P.tier < 2 then
		UI.Line(body, "You're an amateur - win 4 amateur bouts to turn pro and enter the world rankings.", { TextColor3 = T.gold, TextSize = 14, Font = T.semi })
	end
	for i, e in ipairs(res.list) do
		local champ = e.rank == "C"
		local b = UI.Button(body, "", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = e.isPlayer and Color3.fromRGB(58, 46, 16) or T.panel, BackgroundTransparency = e.isPlayer and 0 or (i % 2 == 0 and 0.4 or 0.15) }, function()
			if not e.isPlayer then
				showBoxer(e.id)
			end
		end)
		if e.isPlayer then
			UI.Stroke(b, T.gold, 1.5, 0.2)
		end
		local badge = UI.Frame(b, { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(champ and 62 or 44, 30), BackgroundColor3 = champ and T.gold or T.panel2 })
		UI.Corner(badge, 5)
		UI.Text(badge, champ and "CHAMP" or tostring(e.rank), { Face = "number", TextSize = champ and 15 or 18, TextColor3 = champ and T.ink or T.text, Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
		local x = champ and 80 or 62
		Flags.Draw(b, e.nat, { Size = UDim2.fromOffset(27, 18), Position = UDim2.fromOffset(x, 13) })
		UI.Text(b, string.format("%s  \"%s\"", e.name, e.nick), { Font = T.semi, TextSize = 15, TextColor3 = e.isPlayer and T.gold or T.text, Position = UDim2.fromOffset(x + 36, 0), Size = UDim2.new(0.55, -(x + 36), 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(b, string.format("%d-%d-%d", e.record.w, e.record.l, e.record.d), { Face = "number", TextSize = 20, Position = UDim2.new(0.56, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(b, string.format("%d KO", e.record.ko), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.new(0.76, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(b, tostring(e.overall), { Face = "number", TextSize = 20, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(40, 44),
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
		UI.Line(body, "No rivals yet. Every opponent remembers you - rematches, revenge missions and trilogies appear as offers when rivalries heat up.", { TextColor3 = T.sub })
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
	UI.Line(c, lg.hallOfFame and "HALL OF FAME: INDUCTED" or string.format("Hall of Fame needs %d legacy", Config.HallOfFameScore), { Font = T.bold, TextColor3 = lg.hallOfFame and T.gold or T.sub })
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
	b = UI.Button(c, "RETIRE", { Size = UDim2.new(0, 220, 0, 40), BackgroundColor3 = T.red }, function()
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
	b.BackgroundTransparency = on and 0.1 or 1
	local label = b:FindFirstChild("Label")
	if label then
		label.TextColor3 = on and T.text or T.sub
	end
	local bar = b:FindFirstChild("Active")
	if bar then
		bar.Visible = on
	end
end

function Hub.Render()
	local P = State.P
	if not (shade and shade.Parent and P and P.created) then
		return
	end
	for name, b in pairs(tabButtons) do
		styleTab(name, b)
	end
	local y = content.CanvasPosition
	renderId += 1
	UI.Clear(content)
	local ok, err = pcall(R[tab], content, P)
	if not ok then
		warn("[Hub]", tab, err)
	end
	task.defer(function()
		if content and content.Parent then
			content.CanvasPosition = y
		end
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
		Hub.Render()
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
	local navW = rail and 76 or 176
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
			local b = UI.New("TextButton", { Name = name, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.new(1, rail and -4 or -8, 0, rail and 34 or 36), LayoutOrder = order,
				BackgroundColor3 = T.panel2, BackgroundTransparency = 1, Parent = side })
			UI.Corner(b, UI.R.md)
			UI.Hover(b, { amount = 0.94 })
			local bar = UI.Frame(b, { Name = "Active", Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(3, rail and 18 or 20), BackgroundColor3 = T.gold, Visible = false })
			UI.Corner(bar, 2)
			UI.Text(b, string.upper(name), { Name = "Label", Face = "displayMed", TextSize = rail and 16 or 18, TextColor3 = T.sub, Position = UDim2.fromOffset(rail and 6 or 14, 0),
				Size = UDim2.new(1, rail and -8 or -14, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
				TextXAlignment = rail and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left })
			b.MouseButton1Click:Connect(function()
				tab = name
				content.CanvasPosition = Vector2.zero
				Hub.Render()
			end)
			tabButtons[name] = b
		end
	end
	UI.Frame(body, { Name = "NavLine", Position = UDim2.new(0, navW + 8, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92 })
	content = UI.Scroll(body, { Name = "Content", Position = UDim2.new(0, navW + (rail and 14 or 24), 0, 0), Size = UDim2.new(1, -(navW + (rail and 14 or 24)), 1, 0) })
	-- the screen crosses the phone / desktop line (rotation, a resized window): rebuild for it
	local sizeConn
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
		Hub.Render()
		local b = tabButtons[tab]
		if b and UI.IsPad() then
			GuiService.SelectedObject = b
		end
	end)
	shade.Destroying:Connect(function()
		padConn:Disconnect()
	end)
	Hub.Render()
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
