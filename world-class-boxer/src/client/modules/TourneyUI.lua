-- TourneyUI: the Career Hub's Tournaments tab (Hub's R.Tournaments) and the belt badge the FighterCard, the Hub and
-- the cutscene's banner draw. Everything it shows comes from the profile summary (P.tourney: Tourney.View on the
-- server); its buttons are the Request actions EnterTournament / WithdrawTournament / WearBelt.
--   TourneyUI.BeltIcon(parent, key, width, props)  a belt drawn in GUI frames: the strap in the design's colour with
--                                                  its trim, the centre plate's shape and the emblem (an icon)
--   TourneyUI.Tab(body, P, ctx)                    the tab: the bracket being fought (rounds side by side on a wide
--                                                  screen, stacked on a phone), the calendar of events with their
--                                                  rules / prizes / holders and ENTER, the belts won (WEAR IN RING
--                                                  WALKS), the recent results. ctx = { render = fn, close = fn, open = fn }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local Signage = require(Shared:WaitForChild("Signage"))
local Tournaments = require(Shared:WaitForChild("Tournaments"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local TourneyUI = {}

local function rgb(t, d)
	if type(t) == "table" and tonumber(t[1]) then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return d
end

local EMBLEM_ICON = { glove = "glove", tower = "home", star = "star", laurel = "laurel", globe = "crown" }

------------------------------------------------------------------------
-- The belt badge
------------------------------------------------------------------------
-- a shape in GUI frames (the plate): round = a circle, hexagon / octagon = rotated bars, shield = a square and a
-- diamond under it, crown = a circle with three points
local function plateShape(parent, shape, s, color, z)
	local function piece(w, h, rot, y, radius)
		local f = UI.Frame(parent, { Name = "PlatePiece", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, y or 0), Size = UDim2.fromOffset(w, h),
			Rotation = rot or 0, BackgroundColor3 = color, ZIndex = z })
		if radius then
			UI.Corner(f, radius)
		end
		UI.Gradient(f, { Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190) }, 90)
		return f
	end
	if shape == "hexagon" or shape == "octagon" then
		local n = shape == "hexagon" and 3 or 4
		local half = math.pi / (2 * n)
		for k = 0, n - 1 do
			piece(math.floor(s * math.cos(half)), math.floor(s * math.sin(half)), 90 + k * 180 / n)
		end
	elseif shape == "shield" then
		piece(math.floor(s * 0.9), math.floor(s * 0.62), 0, -math.floor(s * 0.16), 2)
		local d = math.floor(s * 0.9 / math.sqrt(2))
		piece(d, d, 45, math.floor(s * 0.1), 2)
	else
		if shape == "crown" then
			for i = -1, 1 do
				local p = piece(math.floor(s * 0.22), math.floor(s * 0.22), 45, -math.floor(s * 0.48), 2)
				p.Position = UDim2.new(0.5, i * math.floor(s * 0.28), 0.5, -math.floor(s * 0.44))
			end
		end
		piece(s, s, 0, 0, math.floor(s / 2))
	end
end

-- props: AnchorPoint / Position / LayoutOrder / Name; dim = true draws it as a goal (greyed)
function TourneyUI.BeltIcon(parent, key, width, props)
	props = props or {}
	local design = Tournaments.Design(key, Config.Orgs)
	if not design then
		return nil
	end
	local w = math.floor(width or 96)
	local h = math.floor(w * 0.5)
	local dim = props.dim == true
	local f = UI.Frame(parent, { Name = props.Name or "BeltIcon", BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h), LayoutOrder = props.LayoutOrder or 0 })
	if props.AnchorPoint then
		f.AnchorPoint = props.AnchorPoint
	end
	if props.Position then
		f.Position = props.Position
	end
	f:SetAttribute("Belt", key)
	local strapC = dim and T.panel2 or rgb(design.strap, T.ink)
	local trimC = dim and T.line or rgb(design.trim, T.goldDeep)
	local plateC = dim and T.dim or rgb(design.plate, T.gold)
	local z = f.ZIndex
	-- the strap with its piping
	local piping = UI.Frame(f, { Name = "Piping", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, math.floor(h * 0.5)), BackgroundColor3 = trimC, ZIndex = z })
	UI.Corner(piping, math.floor(h * 0.16))
	local strap = UI.Frame(f, { Name = "Strap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -4, 0, math.floor(h * 0.42)), BackgroundColor3 = strapC, ZIndex = z })
	UI.Corner(strap, math.floor(h * 0.14))
	UI.Gradient(strap, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 90)
	-- side plates
	local sides = math.clamp(math.floor(tonumber(design.sides) or 1), 0, 3)
	local ss = math.floor(h * 0.34)
	for i = 1, sides do
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (h * 0.55 + (i - 0.5) * ss * 1.15)
			if math.abs(x) + ss / 2 < w / 2 - 2 then
				local sp = UI.Frame(f, { Name = "SidePlate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.floor(x), 0.5, 0), Size = UDim2.fromOffset(ss, ss),
					BackgroundColor3 = trimC, ZIndex = z + 1 })
				UI.Corner(sp, design.shape == "round" and math.floor(ss / 2) or 3)
			end
		end
	end
	-- the centre plate and its emblem
	local s = math.floor(h * 0.9)
	local plate = UI.Frame(f, { Name = "Plate", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(s, s), ZIndex = z + 2 })
	plateShape(plate, design.shape, math.floor(s * 1.08), trimC, z + 2)
	plateShape(plate, design.shape, s - 4, plateC, z + 3)
	local icon = EMBLEM_ICON[design.emblem] or "star"
	UI.Icon(plate, icon, math.floor(s * 0.5), dim and T.line or rgb(design.strap, T.ink), { Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = z + 5 })
	return f
end

------------------------------------------------------------------------
-- The tab
------------------------------------------------------------------------
local function money(n)
	return Config.Money(n)
end

local function hit(obj, h)
	return math.max(h, UI.MinHit(obj))
end

local function widthOf(obj)
	local px = obj.AbsoluteSize.X
	local s = UI.ScaleOf(obj)
	if px and px > 10 then
		return px / math.max(0.1, s)
	end
	return 640
end

local function req(action, ...)
	local r = State.req(action, ...)
	if not r.ok then
		State.toast(r.err or "Can't do that.", T.red)
	end
	return r
end

local PLACE = { "QUARTER-FINALIST", "SEMI-FINALIST", "RUNNER-UP", "CHAMPION" }

-- one match: two rows (seed, name, OVR); the winner gold, the player outlined
local function matchBox(parent, m, w, rowH, props)
	props = props or {}
	local box = UI.Frame(parent, { Name = props.Name or "Match", Size = UDim2.fromOffset(w, rowH * 2 + 2), BackgroundColor3 = T.panel, BackgroundTransparency = 0.1,
		LayoutOrder = props.order or 0 })
	if props.Position then
		box.Position = props.Position
	end
	UI.Corner(box, UI.R.md)
	local you = (m.a and m.a.you) or (m.b and m.b.you)
	UI.Stroke(box, you and T.gold or Color3.new(1, 1, 1), you and 1.5 or 1, you and 0.25 or 0.86)
	for i = 1, 2 do
		local x = i == 1 and m.a or m.b
		local won = m.win ~= nil and x ~= nil and m.win == x.id
		local lost = m.win ~= nil and x ~= nil and m.win ~= x.id
		local row = UI.Frame(box, { Name = "Row" .. i, BackgroundTransparency = won and 0.55 or 1, BackgroundColor3 = T.bg:Lerp(T.gold, 0.25), Position = UDim2.fromOffset(0, (i - 1) * (rowH + 2)),
			Size = UDim2.new(1, 0, 0, rowH) })
		UI.Corner(row, UI.R.md)
		local seed = UI.Frame(row, { Name = "Seed", Position = UDim2.fromOffset(6, math.floor((rowH - 18) / 2)), Size = UDim2.fromOffset(22, 18), BackgroundColor3 = T.ink, BackgroundTransparency = 0.3 })
		UI.Corner(seed, 4)
		UI.Text(seed, x and x.seed and tostring(x.seed) or "-", { Face = "number", TextSize = 12, TextColor3 = T.sub, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		local name = x and (x.you and ("YOU · " .. tostring(x.name)) or tostring(x.name)) or "TBD"
		UI.Text(row, string.upper(name), { Name = "Name", Face = "displayMed", TextSize = 15, TextColor3 = won and T.gold or (lost and T.dim or (x and x.you and T.text or T.text)),
			Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -82, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(row, x and tostring(x.overall or "") or "", { Name = "Ovr", Face = "number", TextSize = 15, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(40, rowH), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
	if m.method and m.win then
		UI.Text(box, tostring(m.method), { Name = "Method", Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0),
			Size = UDim2.fromOffset(40, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
	return box
end

-- the bracket: three columns (QF / SF / F) on a wide content area, the rounds stacked on a narrow one
function TourneyUI.Bracket(parent, run, order)
	local W = widthOf(parent) - 12
	local wide = W >= 640
	local holder = UI.Frame(parent, { Name = "Bracket", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0 })
	local rowH = 28
	local boxH = rowH * 2 + 2
	if wide then
		local gap = 18
		local colW = math.floor((W - 2 * gap) / 3)
		local top = 24
		local slot = boxH + 12
		local totalH = top + 4 * slot
		local grid = UI.Frame(holder, { Name = "Columns", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, totalH) })
		for r = 1, 3 do
			local x = (r - 1) * (colW + gap)
			UI.Text(grid, string.upper(Tournaments.ROUND_NAMES[r]) .. (r < 3 and "S" or ""), { Name = "RoundHead" .. r, Font = T.semi, TextSize = 12, TextColor3 = r == run.round and T.gold or T.sub,
				Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(colW, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
			local matches = run.rounds[r] or {}
			local n = #matches
			for k, m in ipairs(matches) do
				-- each match centred on the two it comes from
				local span = 4 / math.max(1, n)
				local cy = top + ((k - 1) * span + span / 2) * slot - slot / 2 + 6
				matchBox(grid, m, colW, rowH, { Name = "Match" .. r .. "_" .. k, Position = UDim2.fromOffset(x, math.floor(cy)) })
				if r < 3 then
					-- the connector to the next round
					UI.Frame(grid, { Name = "Link", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, Position = UDim2.fromOffset(x + colW, math.floor(cy + boxH / 2)),
						Size = UDim2.fromOffset(gap, 1) })
				end
			end
		end
	else
		UI.List(holder, 6)
		for r = 1, 3 do
			UI.Kicker(holder, string.upper(Tournaments.ROUND_NAMES[r]) .. (r < 3 and "S" or ""), r == run.round and T.gold or T.sub, { order = r * 10 })
			for k, m in ipairs(run.rounds[r] or {}) do
				matchBox(holder, m, math.floor(W), rowH, { Name = "Match" .. r .. "_" .. k, order = r * 10 + k })
			end
		end
	end
	return holder
end

-- a status chip for an event: OPEN / OPENS IN N DAYS / NOT ELIGIBLE / ENTERED
local function status(e, P, running)
	if running then
		return "ENTERED", T.gold
	elseif not e.eligible then
		return "NOT ELIGIBLE", T.dim
	elseif e.open then
		return "ENTRIES OPEN", T.green
	end
	local d = math.max(0, (e.opens or 0) - (P.day or 1))
	return string.format("OPENS IN %d DAY%s", d, d == 1 and "" or "S"), T.sub
end

function TourneyUI.Tab(body, P, ctx)
	ctx = ctx or {}
	local V = P.tourney
	if type(V) ~= "table" then
		UI.Line(body, "Tournaments are not available on this server yet.", { TextColor3 = T.sub })
		return
	end
	local W = widthOf(body)
	local narrow = W < 560
	-- the summary chips
	local chips = UI.Frame(body, { Name = "TourneyChips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	UI.List(chips, 8, true)
	UI.Chip(chips, "Day " .. tostring(P.day or 1), T.text, { order = 1, icon = "calendar" })
	UI.Chip(chips, tostring(#(V.belts or {})) .. " belts", T.gold, { order = 2, icon = "belt" })
	if not narrow then
		UI.Chip(chips, tostring(math.floor(V.points or 0)) .. " ranking pts", T.cyan, { order = 3, icon = "podium" })
	end

	-- the bracket being fought
	if V.run then
		local run = V.run
		UI.Header(body, "YOUR BRACKET", T.gold, "podium")
		local c = UI.Card(body, { stroke = T.gold })
		UI.Title(c, string.upper(run.name), { Name = "RunName", TextSize = narrow and 22 or 28, Size = UDim2.new(1, 0, 0, narrow and 26 or 32), AutomaticSize = Enum.AutomaticSize.None,
			TextTruncate = Enum.TextTruncate.AtEnd })
		local camp = P.camp
		local daysLeft = camp and tonumber(camp.daysLeft) or 0
		UI.Line(c, string.format("%s  ·  seed %s  ·  %s", run.roundName, tostring(run.seed or "-"), daysLeft > 0 and string.format("fight night in %d day%s", daysLeft, daysLeft == 1 and "" or "s")
			or "FIGHT NIGHT"), { Font = T.semi, TextSize = 14, TextColor3 = daysLeft > 0 and T.sub or T.gold })
		local meters = UI.Frame(c, { Name = "Meters", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58) })
		UI.List(meters, 8, true)
		local wear = run.wear or {}
		UI.Stat(meters, string.format("%d%%", 100 - (wear.head or 0)), "HEAD FRESH", { Size = UDim2.new(0.33, -6, 1, 0), order = 1, valueSize = 26, scaled = true,
			valueColor = (wear.head or 0) > 15 and T.red or T.green, icon = "heart" })
		UI.Stat(meters, string.format("%d%%", 100 - (wear.body or 0)), "BODY FRESH", { Size = UDim2.new(0.33, -6, 1, 0), order = 2, valueSize = 26, scaled = true,
			valueColor = (wear.body or 0) > 15 and T.red or T.green, icon = "pulse" })
		UI.Stat(meters, money(run.prize or 0), "PRIZE SO FAR", { Size = UDim2.new(0.34, -6, 1, 0), order = 3, valueSize = 26, scaled = true, valueColor = T.green, icon = "coin" })
		UI.Line(c, "Health and injuries carry over between rounds: a hard night now is a slower start in the next one. A loss or a withdrawal ends the run.",
			{ TextSize = 13, TextColor3 = T.sub })
		local confirm = false
		local wBtn
		local row = UI.Row(c, hit(c, 40))
		UI.Button(row, "GO TO FIGHT CAMP", { Name = "ToCamp", Size = UDim2.new(0, narrow and 190 or 220, 1, 0), BackgroundColor3 = T.red, TextSize = 14 }, function()
			if ctx.open then
				ctx.open("Career")
			end
		end)
		wBtn = UI.Button(row, "WITHDRAW", { Name = "Withdraw", Size = UDim2.new(0, narrow and 150 or 170, 1, 0), BackgroundColor3 = T.panel2, TextSize = 14 }, function()
			if not confirm then
				confirm = true
				wBtn.Text = "CONFIRM WITHDRAW"
				return
			end
			local r = req("WithdrawTournament")
			if r.ok then
				State.toast((r.notes and r.notes[#r.notes]) or "You withdrew.", T.gold)
			end
		end)
		TourneyUI.Bracket(body, run)
	end

	-- the calendar
	UI.Header(body, "TOURNAMENT CALENDAR", nil, "calendar")
	local list = table.clone(V.list or {})
	table.sort(list, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end
		return tostring(a.id) < tostring(b.id)
	end)
	for i, e in ipairs(list) do
		local running = V.run and V.run.id == e.id
		local c = UI.Card(body, { stroke = (e.open and e.eligible and not V.run) and T.gold or nil, order = 0 })
		c.Name = "Event_" .. tostring(e.id)
		local head = UI.Frame(c, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, narrow and 44 or 56) })
		local bw = narrow and 84 or 112
		TourneyUI.BeltIcon(head, e.id, bw, { Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), dim = e.won == 0 })
		local tx = bw + 12
		local st, stColor = status(e, P, running)
		local stW = math.max(96, UI.TextWidth(st, 11, T.semi) + 22)
		UI.Title(head, string.upper(e.name), { Name = "EventName", TextSize = narrow and 19 or 24, Position = UDim2.fromOffset(tx, 0), Size = UDim2.new(1, -(tx + stW + 8), 0, narrow and 24 or 30),
			AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
		-- "DAY 12 · 8 ROUNDS" and the venue's badge (its sign's lockup) where the head has the height for it; the
		-- name in the line on a narrow screen (or for a place that is not known)
		local loc = (not narrow) and Signage.Find(e.venue) or nil
		local when = string.format("DAY %d  ·  %d ROUNDS%s", e.start or 0, e.rounds or 0, loc and "" or ("  ·  " .. string.upper(e.venue or "")))
		local whenY = narrow and 25 or 32
		local whenW = loc and math.min(UI.TextWidth(when, 12, T.semi) + 8, 200) or nil
		UI.Text(head, when, { Name = "When", Font = T.semi, TextSize = 12, TextColor3 = T.sub,
			Position = UDim2.fromOffset(tx, whenY), Size = whenW and UDim2.new(0, whenW, 0, 16) or UDim2.new(1, -tx, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		if loc then
			local bh = UI.LocationBadgeHeight(head, 18)
			UI.LocationBadge(head, loc, 18, { Name = "Venue", sub = false, Position = UDim2.fromOffset(tx + whenW + 2, whenY + 8 - math.floor(bh / 2)) })
		end
		UI.Chip(head, st, stColor, { Name = "Status", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), solid = e.open and e.eligible and not running })
		if not narrow then
			UI.Line(c, e.blurb or "", { TextSize = 13, TextColor3 = T.sub })
		end
		UI.Line(c, "ENTRY: " .. tostring((not e.eligible and e.why) or e.rule or ""), { Name = "Rule", TextSize = 13, Font = T.semi, TextColor3 = e.eligible and T.text or T.red })
		local pr = e.prize or {}
		UI.Line(c, string.format("PRIZES: winner %s  ·  runner-up %s  ·  semi-final %s", money(pr[4] or 0), money(pr[3] or 0), money(pr[2] or 0)), { Name = "Prizes", TextSize = 13, TextColor3 = T.green })
		if e.holder then
			UI.Line(c, string.format("HOLDER: %s%s", e.holder.you and "YOU" or tostring(e.holder.name), e.won > 0 and string.format("  ·  you've won it %d time%s", e.won, e.won == 1 and "" or "s") or ""),
				{ Name = "Holder", TextSize = 13, TextColor3 = e.holder.you and T.gold or T.sub })
		end
		if e.open and e.eligible and not V.run and not P.camp then
			local row = UI.Row(c, hit(c, 40))
			UI.Button(row, "ENTER TOURNAMENT", { Name = "Enter", Size = UDim2.new(0, 220, 1, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg, TextSize = 14 }, function()
				local r = req("EnterTournament", e.id)
				if r.ok and r.info then
					State.toast(string.format("Entered the %s as the #%d seed. Quarter-final vs %s on day %d.", e.name, r.info.seed or 0, tostring(r.info.opp), r.info.start or 0), T.green, 6)
				end
			end)
		elseif e.open and e.eligible and P.camp and not V.run then
			UI.Line(c, "You have a fight booked: finish it first.", { TextSize = 12, TextColor3 = T.sub })
		end
		c.LayoutOrder = 100 + i
	end

	-- the belts won
	if #(V.belts or {}) > 0 then
		local h = UI.Header(body, "BELTS WON", T.gold, "belt")
		h.Parent.LayoutOrder = 200
		local grid = UI.Frame(body, { Name = "Belts", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 201 })
		UI.List(grid, 8)
		for i, b in ipairs(V.belts) do
			local row = UI.Frame(grid, { Name = "Belt_" .. b.id, Size = UDim2.new(1, 0, 0, hit(grid, 56)), BackgroundColor3 = T.panel, BackgroundTransparency = 0.15, LayoutOrder = i })
			UI.Corner(row, UI.R.md)
			TourneyUI.BeltIcon(row, b.id, 92, { Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
			local worn = V.wear == b.id
			local bw = narrow and 120 or 200
			UI.Text(row, string.upper(b.name) .. (b.n > 1 and ("  x" .. b.n) or ""), { Face = "displayMed", TextSize = 16, Position = UDim2.fromOffset(110, 0), Size = UDim2.new(1, -(110 + bw + 16), 1, 0),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = T.gold })
			UI.Button(row, worn and "WORN IN WALKS" or (narrow and "WEAR IT" or "WEAR IN RING WALKS"), { Name = "Wear", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0, bw, 0, hit(row, 38)), BackgroundColor3 = worn and T.gold or T.panel2, TextColor3 = worn and T.bg or T.text, TextSize = 13 }, function()
				req("WearBelt", worn and nil or b.id)
			end)
		end
	end

	-- results: the player's finishes, then the division's champions
	if #(V.history or {}) > 0 or #(V.log or {}) > 0 then
		local h = UI.Header(body, "RECENT RESULTS", nil, "chart")
		h.Parent.LayoutOrder = 300
		local c = UI.Card(body, { order = 301 })
		for _, e in ipairs(V.history or {}) do
			UI.Line(c, string.format("Day %d  ·  %s  ·  %s%s", e.day or 0, e.name, PLACE[e.place] or "?", (e.prize or 0) > 0 and ("  ·  " .. money(e.prize)) or ""),
				{ TextSize = 13, TextColor3 = e.place == 4 and T.gold or T.text })
		end
		for _, e in ipairs(V.log or {}) do
			UI.Line(c, string.format("%s  ·  %s won by %s%s", (e.day or 0) >= 1 and ("Day " .. e.day) or "Last season", e.name, e.you and "YOU" or tostring(e.winner), e.runnerUp and (" over " .. e.runnerUp) or ""),
				{ TextSize = 12, TextColor3 = e.you and T.gold or T.sub })
		end
	end
end

return TourneyUI
