-- Scorecards: the judges' cards and the punch statistics on the player's screen (the WCB gold-glove UI kit).
--   * between rounds: the round's UNOFFICIAL scorecard - the three judges' round scores with each judge's reason,
--     the running totals - and the punch stats of both men (thrown / landed / % by type, power punches, body,
--     knockdowns, the defence), with the corner's advice and the cutman's note from the rest message. The server's
--     "scorecard" message (FightEngine's Fight:ScoreRound, before the bell) is kept (Scorecards.Note) and the panel
--     opens with the "rest" message (FightClient's handler: Scorecards.OpenRest); the next round's countdown, the
--     final bell or the fight's end close it.
--   * the builders the results screen (PostFightUI) shares: Scorecards.Grid (the full three-judge card, rounds x
--     judges), Scorecards.PunchTable (the stats by type), Scorecards.JudgeLabel.
-- Everything is local and goes away when closed. Phones (a short canvas) get the compact layout: fewer stat rows,
-- one line of advice, smaller type.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme

local Scorecards = {}

-- the judges' leanings, by the server's judge id (Judging.JUDGES)
Scorecards.JUDGE_LEAN = { aggression = "AGGRESSION", clean = "CLEAN PUNCHING", defence = "DEFENCE & RING" }
-- the punch types in the table's order, with their captions
Scorecards.TYPES = {
	{ "jab", "JABS" }, { "cross", "CROSSES" }, { "leadhook", "LEAD HOOKS" }, { "rearhook", "REAR HOOKS" }, { "uppercut", "UPPERCUTS" }, { "overhand", "OVERHANDS" },
}

local function num(v)
	return tonumber(v) or 0
end

local function pct(l, t)
	return t > 0 and string.format("%d%%", math.floor(l / t * 100 + 0.5)) or "-"
end

function Scorecards.JudgeLabel(j, id)
	local lean = Scorecards.JUDGE_LEAN[id]
	return lean and string.format("JUDGE %d  ·  %s", j, lean) or ("JUDGE " .. j)
end

------------------------------------------------------------------------
-- the shared rows
------------------------------------------------------------------------
-- you (red, left) against the opponent (blue, right): values, a centred caption, and the bars under it (the
-- share of the two). fmtA / fmtB: the texts; fracA / fracB 0..1 the bars; opts.h the row height, opts.size the
-- value's text size, opts.dim when neither leads
local function versus(parent, caption, textA, textB, fracA, fracB, opts)
	opts = opts or {}
	local h = opts.h or 30
	local f = UI.Frame(parent, { Name = "Versus", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = opts.order or 0 })
	local vs = opts.size or 20
	local aLeads, bLeads = fracA > fracB + 0.001, fracB > fracA + 0.001
	UI.Text(f, textA, { Face = "number", TextSize = vs, TextColor3 = aLeads and T.text or T.sub, Size = UDim2.new(0.22, 0, 0, vs + 4), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	UI.Text(f, textB, { Face = "number", TextSize = vs, TextColor3 = bLeads and T.text or T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.22, 0, 0, vs + 4),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	UI.Text(f, caption, { Font = T.semi, TextSize = opts.capSize or 11, TextColor3 = opts.capColor or T.sub, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(0.5, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if opts.bars ~= false then
		local by = opts.barY or (vs + 2)
		local total = math.max(0.001, fracA + fracB)
		local la = UI.Frame(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -4, 0, by), Size = UDim2.new(0.26 * fracA / total, 0, 0, 4), BackgroundColor3 = T.red, BackgroundTransparency = aLeads and 0 or 0.35 })
		UI.Corner(la, 2)
		local lb = UI.Frame(f, { Position = UDim2.new(0.5, 4, 0, by), Size = UDim2.new(0.26 * fracB / total, 0, 0, 4), BackgroundColor3 = T.blue, BackgroundTransparency = bLeads and 0 or 0.35 })
		UI.Corner(lb, 2)
	end
	return f
end
Scorecards.Versus = versus

-- the punch table: you / opp = Judging sides ({ landed, thrown, power, body, kd, blocked, evaded, parried, byType,
-- thrownByType }). opts.compact leaves the per-type rows out; opts.h / size as versus; opts.types = false leaves
-- the per-type rows out, opts.defence = false the defence rows
function Scorecards.PunchTable(parent, you, opp, opts)
	opts = opts or {}
	you, opp = you or {}, opp or {}
	local box = UI.Frame(parent, { Name = "PunchTable", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = opts.order or 0 })
	UI.List(box, opts.gap or 2)
	local n = 0
	local function row(caption, la, ta, lb, tb, rowOpts)
		n += 1
		local o = { h = opts.h, size = opts.size, order = n, capSize = opts.capSize }
		for k, v in pairs(rowOpts or {}) do
			o[k] = v
		end
		local textA = ta and string.format("%d/%d  %s", la, ta, pct(la, ta)) or tostring(la)
		local textB = tb and string.format("%s  %d/%d", pct(lb, tb), lb, tb) or tostring(lb)
		if opts.compact and ta then
			textA = string.format("%d/%d", la, ta)
			textB = string.format("%d/%d", lb, tb)
		end
		return versus(box, caption, textA, textB, la, lb, o)
	end
	local yl, yt, ol, ot = num(you.landed), num(you.thrown), num(opp.landed), num(opp.thrown)
	row("TOTAL PUNCHES", yl, yt, ol, ot, { capColor = T.gold })
	local yj, oj = num(you.byType and you.byType.jab), num(opp.byType and opp.byType.jab)
	local yjt, ojt = num(you.thrownByType and you.thrownByType.jab), num(opp.thrownByType and opp.thrownByType.jab)
	if yjt == 0 and ojt == 0 and (yj > 0 or oj > 0) then
		yjt, ojt = yj, oj
	end
	row("POWER PUNCHES", num(you.power), math.max(0, yt - yjt), num(opp.power), math.max(0, ot - ojt))
	if opts.types ~= false and not opts.compact then
		for _, tdef in ipairs(Scorecards.TYPES) do
			local k = tdef[1]
			local a, at = num(you.byType and you.byType[k]), num(you.thrownByType and you.thrownByType[k])
			local b, bt = num(opp.byType and opp.byType[k]), num(opp.thrownByType and opp.thrownByType[k])
			if a + at + b + bt > 0 then
				row(tdef[2], a, math.max(a, at), b, math.max(b, bt), { capColor = T.dim, size = (opts.size or 20) - 3, h = (opts.h or 30) - 4 })
			end
		end
	end
	row("BODY SHOTS", num(you.body), nil, num(opp.body), nil)
	row("KNOCKDOWNS", num(you.kd), nil, num(opp.kd), nil, { capColor = T.gold })
	if opts.defence ~= false then
		row("BLOCKED", num(you.blocked), nil, num(opp.blocked), nil)
		if not opts.compact then
			row("SLIPPED / PARRIED", num(you.evaded) + num(you.parried), nil, num(opp.evaded) + num(opp.parried), nil)
		end
	end
	return box
end

-- the full three-judge card: rounds across, the judges down, the totals at the right. judging = res.judging
-- (Judging.Report: rounds[r].cards[j] = { you, opp }, cards[j] = totals), names = { you, opp }, opts.rounds =
-- the bout's scheduled rounds (the unfought ones are blank), opts.compact for a short canvas
function Scorecards.Grid(parent, judging, names, opts)
	opts = opts or {}
	judging = judging or {}
	names = names or {}
	local rounds = judging.rounds or {}
	local nR = math.max(#rounds, math.min(num(opts.rounds), 12), 1)
	local compact = opts.compact
	local rowH = compact and 26 or 32
	local labelW = compact and 96 or 170
	local totalW = compact and 64 or 84
	local box = UI.Frame(parent, { Name = "CardGrid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH * 4 + 6), LayoutOrder = opts.order or 0 })
	local cellsW = UDim2.new(1, -(labelW + totalW), 0, 0)
	local function cellX(i)
		-- the i-th round cell's left edge, as a scale of the cells' span plus the label offset
		return UDim2.new((i - 1) / nR, labelW, 0, 0)
	end
	local function cellSize()
		return UDim2.new(1 / nR, 0, 0, rowH)
	end
	-- the header: R1..Rn and TOTAL
	local head = UI.Frame(box, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, -totalW, 0, rowH) })
	local cells = UI.Frame(head, { Name = "Cells", BackgroundTransparency = 1, Position = UDim2.fromOffset(labelW, 0), Size = UDim2.new(1, -labelW, 1, 0) })
	for i = 1, nR do
		UI.Text(cells, (compact and "" or "R") .. i, { Font = T.semi, TextSize = compact and 10 or 11, TextColor3 = i <= #rounds and T.sub or T.dim, Position = UDim2.new((i - 1) / nR, 0, 0, 0), Size = UDim2.new(1 / nR, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	end
	UI.Text(box, "TOTAL", { Font = T.semi, TextSize = compact and 10 or 11, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(totalW, rowH),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	local judgeNames = judging.judgeNames or {}
	for j = 1, 3 do
		local y = rowH * j + 2
		local rowF = UI.Frame(box, { Name = "Judge" .. j, BackgroundColor3 = T.panel2, BackgroundTransparency = j % 2 == 0 and 0.6 or 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, rowH) })
		UI.Frame(rowF, { Name = "Rule", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line })
		local lean = judgeNames[j] and judgeNames[j].lean or nil
		local leanKey = lean and ({ ["Effective aggression"] = "aggression", ["Clean punching"] = "clean", ["Defence and ring control"] = "defence" })[lean] or nil
		UI.Text(rowF, compact and ("JUDGE " .. j) or Scorecards.JudgeLabel(j, leanKey), { Font = T.semi, TextSize = compact and 10 or 11, TextColor3 = T.text, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(labelW - 12, rowH),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local rc = UI.Frame(rowF, { Name = "Cells", BackgroundTransparency = 1, Position = UDim2.fromOffset(labelW, 0), Size = UDim2.new(1, -(labelW + totalW), 1, 0) })
		for i = 1, nR do
			local r = rounds[i]
			local c = r and r.cards and r.cards[j]
			local text = c and string.format("%d-%d", num(c[1]), num(c[2])) or "-"
			local col = T.dim
			if c then
				col = num(c[1]) > num(c[2]) and T.redLight or (num(c[2]) > num(c[1]) and T.blue or T.sub)
			end
			local cell = UI.Text(rc, text, { Face = "number", TextSize = compact and 12 or 14, TextColor3 = col, Position = UDim2.new((i - 1) / nR, 0, 0, 0), Size = UDim2.new(1 / nR, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
			-- a knockdown round is marked
			if r and r.kd and (num(r.kd[1]) + num(r.kd[2])) > 0 then
				UI.Frame(cell, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(compact and 14 or 18, 2), BackgroundColor3 = T.gold })
			end
		end
		local tot = judging.cards and judging.cards[j]
		local a, b = tot and num(tot[1]) or 0, tot and num(tot[2]) or 0
		local tf = UI.Frame(rowF, { Name = "Total", BackgroundColor3 = a > b and T.red or (b > a and T.blue or T.panel2), BackgroundTransparency = a == b and 0.3 or 0.72, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(totalW, rowH) })
		UI.Text(tf, string.format("%d-%d", a, b), { Face = "number", TextSize = compact and 13 or 16, TextColor3 = T.text, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	end
	-- the legend
	if not compact then
		box.Size = UDim2.new(1, 0, 0, rowH * 4 + 24)
		UI.Text(box, string.format("%s  -  %s   ·   gold mark = a knockdown round", string.upper(names[1] or "YOU"), string.upper(names[2] or "OPPONENT")),
			{ Font = T.semi, TextSize = 10, TextColor3 = T.dim, Position = UDim2.fromOffset(0, rowH * 4 + 8), Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd })
	end
	return box
end

------------------------------------------------------------------------
-- the panel between rounds
------------------------------------------------------------------------
local pending -- the latest "scorecard" message (the round's, before the bell)
local open -- the panel on screen { sg, root, n }

function Scorecards.Note(msg)
	if type(msg) == "table" then
		pending = msg
	end
end

function Scorecards.Pending()
	return pending
end

function Scorecards.Close()
	if open then
		local o = open
		open = nil
		if o.sg then
			o.sg:Destroy()
		end
	end
end

function Scorecards.IsOpen()
	return open ~= nil
end

-- rest = the "rest" message (advice, cond, seconds, stats), ctx = { names = { you, opp }, rounds = n, spar = bool }.
-- Returns true when the panel is up (the scorecard of this round came), false when the caller's legacy overlay
-- should stand (a spar, no card).
function Scorecards.OpenRest(rest, ctx)
	rest = rest or {}
	ctx = ctx or {}
	local card = pending
	if ctx.spar or type(card) ~= "table" or (rest.n and card.n and card.n ~= rest.n) then
		return false
	end
	Scorecards.Close()
	local sg = UI.New("ScreenGui", { Name = "ScorecardUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 8, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	local root = UI.MountRoot(sg, "Root")
	local canvas = UI.CanvasSize(root)
	local compact = canvas.Y < 640
	local names = ctx.names or {}
	local you, opp = names[1] or "You", names[2] or "Opponent"
	local n = num(card.n) > 0 and num(card.n) or num(rest.n)
	open = { sg = sg, root = root, n = n }
	-- the panel: a glass band in the middle of the screen (the HUD's scoreboard above, the ticker below)
	local W = math.min(compact and 900 or 1080, canvas.X - (compact and 48 or 120))
	local panel = UI.Frame(root, { Name = "Scorecard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, compact and 0.53 or 0.55, 0), Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Glass(panel, { transparency = 0, radius = UI.R.sm })
	UI.New("UIPadding", { PaddingTop = UDim.new(0, compact and 10 or 16), PaddingBottom = UDim.new(0, compact and 10 or 16), PaddingLeft = UDim.new(0, compact and 14 or 22), PaddingRight = UDim.new(0, compact and 14 or 22), Parent = panel })
	UI.List(panel, compact and 6 or 10)
	UI.Frame(panel, { Name = "Stripe", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = T.gold, LayoutOrder = 0 })
	-- the head: the kicker and the round, the totals so far
	local head = UI.Frame(panel, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, compact and 46 or 56), LayoutOrder = 1 })
	UI.Kicker(head, string.format("End of round %d  ·  unofficial scorecard", n), nil, { Size = UDim2.new(0.6, 0, 0, 16), icon = "contract" })
	UI.Title(head, compact and "Your corner" or "Your corner  ·  between rounds", { TextSize = compact and 20 or 24, Position = UDim2.fromOffset(0, compact and 18 or 22), Size = UDim2.new(0.6, 0, 0, compact and 24 or 30),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the three totals at the right: you - opp on each card
	local totals = UI.Frame(head, { Name = "Totals", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0) })
	UI.List(totals, 6, true, Enum.HorizontalAlignment.Right)
	for j = 1, 3 do
		local c = card.cards and card.cards[j] or { 0, 0 }
		local a, b = num(c[1]), num(c[2])
		local f = UI.Frame(totals, { Size = UDim2.fromOffset(compact and 70 or 84, compact and 44 or 52), BackgroundColor3 = T.panel, BackgroundTransparency = 0, LayoutOrder = j })
		UI.Stroke(f, a > b and T.red or (b > a and T.blue or T.line), 1, 0)
		UI.Frame(f, { Name = "Mark", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = a > b and T.red or (b > a and T.blue or T.line) })
		UI.Text(f, string.format("%d-%d", a, b), { Face = "number", TextSize = compact and 16 or 22, TextColor3 = T.text, Size = UDim2.new(1, 0, 0.64, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(f, "JUDGE " .. j, { Font = T.semi, TextSize = 9, TextColor3 = T.sub, Position = UDim2.new(0, 0, 0.62, 0), Size = UDim2.new(1, 0, 0.38, 0), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	end
	-- the body: the round's card (left) and the punch stats (right)
	local body = UI.Frame(panel, { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.List(body, compact and 10 or 16, true)
	local left = UI.Frame(body, { Name = "Round", BackgroundColor3 = T.panel, BackgroundTransparency = 0, Size = UDim2.new(0.42, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	UI.Stroke(left, T.line, 1, 0)
	UI.New("UIPadding", { PaddingTop = UDim.new(0, compact and 8 or 12), PaddingBottom = UDim.new(0, compact and 8 or 12), PaddingLeft = UDim.new(0, compact and 10 or 14), PaddingRight = UDim.new(0, compact and 10 or 14), Parent = left })
	UI.List(left, compact and 4 or 6)
	local function surname(name)
		return tostring(name):match("(%S+)$") or tostring(name)
	end
	UI.Kicker(left, compact and string.format("ROUND %d  ·  %s v %s", n, string.upper(surname(you)), string.upper(surname(opp))) or string.format("ROUND %d  ·  %s v %s", n, string.upper(you), string.upper(opp)), T.sub,
		{ Size = UDim2.new(1, 0, 0, 16), order = 0 })
	for j = 1, 3 do
		local rc = card.round and card.round[j] or { 0, 0 }
		local jd = card.judges and card.judges[j] or {}
		local a, b = num(rc[1]), num(rc[2])
		local rowH = compact and 34 or 40
		local row = UI.Frame(left, { Name = "J" .. j, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = j })
		UI.Frame(row, { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = a > b and T.red or (b > a and T.blue or T.line) })
		UI.Text(row, Scorecards.JudgeLabel(j, jd.id), { Font = T.semi, TextSize = compact and 10 or 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(row, jd.reason or (a == b and "An even round" or "The better work"), { Font = T.font, TextSize = compact and 11 or 13, TextColor3 = T.text, Position = UDim2.fromOffset(12, compact and 13 or 16), Size = UDim2.new(1, -80, 0, compact and 15 or 20),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(row, string.format("%d-%d", a, b), { Face = "number", TextSize = compact and 20 or 26, TextColor3 = a > b and T.redLight or (b > a and T.blue or T.sub), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(70, rowH), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
	if card.kd and (num(card.kd[1]) + num(card.kd[2])) > 0 then
		UI.Chip(left, string.format("KNOCKDOWNS THIS ROUND  %d - %d", num(card.kd[1]), num(card.kd[2])), T.gold, { order = 5 })
	end
	local right = UI.Frame(body, { Name = "Stats", BackgroundColor3 = T.panel, BackgroundTransparency = 0.35, Size = UDim2.new(0.58, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.Corner(right, UI.R.lg)
	UI.Stroke(right, Color3.new(1, 1, 1), 1, UI.Hair.faint)
	UI.New("UIPadding", { PaddingTop = UDim.new(0, compact and 8 or 12), PaddingBottom = UDim.new(0, compact and 8 or 12), PaddingLeft = UDim.new(0, compact and 10 or 14), PaddingRight = UDim.new(0, compact and 10 or 14), Parent = right })
	UI.List(right, compact and 2 or 4)
	local tabs = UI.Frame(right, { Name = "Names", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0 })
	-- (a phone shows the surnames: the full names would run into the centre caption)
	local function short(name)
		if not compact then
			return string.upper(name)
		end
		local last = tostring(name):match("(%S+)$") or tostring(name)
		return string.upper(last)
	end
	UI.Text(tabs, short(you), { Font = T.semi, TextSize = 11, TextColor3 = T.redLight, Size = UDim2.new(0.34, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Text(tabs, compact and "ROUND " .. n or ("ROUND " .. n .. "  ·  LANDED / THROWN"), { Font = T.semi, TextSize = 10, TextColor3 = T.dim, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.3, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Text(tabs, short(opp), { Font = T.semi, TextSize = 11, TextColor3 = T.blue, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.34, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local st = card.stats or {}
	Scorecards.PunchTable(right, st.you, st.opp, { order = 1, compact = compact, h = compact and 24 or 28, size = compact and 15 or 18, capSize = compact and 10 or 11, types = not compact, defence = not compact })
	-- the fight so far (one line)
	local tot = card.totals or {}
	if tot.you and tot.opp then
		UI.Text(right, string.format("FIGHT  ·  %d/%d (%s)  landed / thrown  %d/%d (%s)", num(tot.you.landed), num(tot.you.thrown), pct(num(tot.you.landed), num(tot.you.thrown)), num(tot.opp.landed), num(tot.opp.thrown),
			pct(num(tot.opp.landed), num(tot.opp.thrown))), { Font = T.semi, TextSize = compact and 10 or 11, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, LayoutOrder = 2 })
	end
	-- the corner: the cutman's note and the advice (one line on a phone)
	local foot = UI.Frame(panel, { Name = "Corner", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	UI.List(foot, 4)
	local c = rest.cond
	if type(c) == "table" and c.notes and #c.notes > 0 and not compact then
		UI.Text(foot, "Cutman: " .. table.concat(c.notes, "  ·  "), { Font = T.semi, TextSize = 12, TextColor3 = T.orange, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
	end
	for i, line in ipairs(rest.advice or {}) do
		if not compact or i == 1 then
			UI.Text(foot, "\"" .. tostring(line) .. "\"  ·  your corner", { Font = T.font, TextSize = compact and 12 or 14, TextColor3 = T.gold, Size = UDim2.new(1, 0, 0, compact and 16 or 18), AutomaticSize = Enum.AutomaticSize.None,
				TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 + i })
		end
	end
	-- the opening motion
	local pop = UI.New("UIScale", { Scale = 0.96, Parent = panel })
	UI.Tween(pop, { Scale = 1 }, UI.Motion.base)
	return true
end

-- the fight remote closes the panel (the next round, the end)
local started = false
function Scorecards.Start()
	if started then
		return
	end
	started = true
	local ok, State = pcall(function()
		return require(script.Parent:WaitForChild("State", 5))
	end)
	local remote = ok and State and State.FightRemote or nil
	if remote then
		remote.OnClientEvent:Connect(function(msg)
			if type(msg) ~= "table" then
				return
			end
			local t = msg.t
			if t == "round" or t == "countdown" or t == "final" or t == "aborted" or t == "result" or t == "tutorialEnd" or t == "start" then
				Scorecards.Close()
				if t == "start" or t == "final" or t == "aborted" then
					pending = nil
				end
			end
		end)
	end
end
Scorecards.Start()

return Scorecards
