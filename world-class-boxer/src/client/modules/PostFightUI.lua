-- PostFightUI: the results screen after every fight (the "result" message: FightClient's handler calls
-- PostFightUI.Open(msg)), in the WCB gold-glove kit, replacing ClientMain's plain result window:
--   * the headline (VICTORY / DEFEAT / DRAW), the method with the judges' totals, the round, the opponent, the
--     announcer's call; a championship (a title note) gets the belt kicker
--   * OFFICIAL SCORECARDS: the three judges, every round (Scorecards.Grid) and each judge's leaning
--   * FIGHT STATISTICS: thrown / landed / % by type, power punches, body, knockdowns, the defence
--     (Scorecards.PunchTable), the combinations
--   * KNOCKDOWNS: every trip to the canvas, by round
--   * DAMAGE REPORT: what tonight took out of both men (the face and body damage model: cuts, swelling, the nose,
--     the ribs, the head trauma and body damage, the concussion), and the injuries on the profile (the server's
--     profile push after the result: Training.ActiveInjuries -> P.condition.injuries) as they arrive
--   * EARNINGS & RANKINGS: the purse breakdown and Career's notes, the record, the rankings before and after
--     (the profile at the first bell against the push after the result)
-- CONTINUE closes it. Modal: the HUD plate stays out until it is dismissed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))
local Scorecards = require(script.Parent:WaitForChild("Scorecards"))
local T = UI.Theme

local Combos
pcall(function()
	Combos = require(Shared:WaitForChild("Combos", 5))
end)

local PostFightUI = {}

local METHOD = { KO = "Knockout", TKO = "Technical knockout", RTD = "Retired on the stool", UD = "Unanimous decision", SD = "Split decision", MD = "Majority decision", Draw = "Draw",
	DQ = "Disqualification", Tutorial = "Tutorial", Quit = "Walked out", Stopped = "Stopped" }

local function num(v)
	return tonumber(v) or 0
end

local function pct(l, t)
	return t > 0 and string.format("%d%%", math.floor(l / t * 100 + 0.5)) or "-"
end

------------------------------------------------------------------------
-- the profile at the first bell (the rankings' "before")
------------------------------------------------------------------------
local snap
local function takeSnap()
	local P = State.P
	if type(P) ~= "table" then
		return
	end
	snap = { ranks = type(P.ranks) == "table" and table.clone(P.ranks) or {}, bestRank = P.bestRank, record = type(P.record) == "table" and table.clone(P.record) or nil,
		money = P.money, injuries = {} }
	for _, inj in ipairs(P.condition and P.condition.injuries or {}) do
		snap.injuries[inj.id or inj.name] = true
	end
end

local function rankWord(r)
	if r == nil then
		return "-"
	end
	return r == "C" and "CHAMP" or ("#" .. tostring(r))
end

------------------------------------------------------------------------
-- the damage report
------------------------------------------------------------------------
-- what a fight's face / body table says, as lines ({ text, color })
local function damageLines(face, headTaken, bodyTaken, concPeak, noseBroken)
	local out = {}
	face = type(face) == "table" and face or {}
	local function side(s)
		return s == 1 and "right" or "left"
	end
	if num(face.cut) > 0.3 then
		table.insert(out, { string.format("Cut over the %s eye (%s)", side(face.cutSide), num(face.cut) > 0.7 and "deep" or "bleeding"), T.red })
	end
	if num(face.cut2) > 0.3 then
		table.insert(out, { string.format("Second cut, %s side", side(face.cutSide2)), T.red })
	end
	local eye = math.max(num(face.leftEye), num(face.rightEye))
	if eye > 0.3 then
		table.insert(out, { string.format("%s eye %s", num(face.leftEye) > num(face.rightEye) and "Left" or "Right", eye > 0.75 and "nearly shut" or "swollen"), T.orange })
	end
	if noseBroken or face.nose == true then
		table.insert(out, { "Broken nose", T.red })
	elseif num(face.noseBleed) > 0.4 then
		table.insert(out, { "Bloody nose", T.orange })
	end
	if math.max(num(face.ribsL), num(face.ribsR)) > 0.4 then
		table.insert(out, { "Bruised ribs", T.orange })
	end
	if num(concPeak) > 0.5 then
		table.insert(out, { "Concussed - a long count's worth of head trauma", T.purple })
	elseif num(concPeak) > 0.25 then
		table.insert(out, { "Rattled - the head took a few", T.purple })
	end
	if #out == 0 then
		table.insert(out, { (num(headTaken) + num(bodyTaken)) < 15 and "Barely a mark" or "Bruised, nothing broken", T.green })
	end
	return out
end

------------------------------------------------------------------------
-- the screen
------------------------------------------------------------------------
local active

local function close()
	if not active then
		return
	end
	local a = active
	active = nil
	State.windows.PostFight = nil
	for _, c in ipairs(a.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	if a.shade then
		a.shade:Destroy()
	end
end
PostFightUI.Close = close

function PostFightUI.IsOpen()
	return active ~= nil
end

-- data = the "result" message: { result = res, notes, earnings, opp, kind, venue }
function PostFightUI.Open(data)
	data = type(data) == "table" and data or {}
	local res = type(data.result) == "table" and data.result or {}
	close()
	-- ClientMain's plain result window opens half a second after the message: this one takes its place
	State.closeAll("PostFight")
	local gui = State.gui
	local won, lost = res.outcome == "win", res.outcome == "loss"
	local col = won and T.gold or (lost and T.red or T.text)
	local stoppage = res.method == "KO" or res.method == "TKO" or res.method == "RTD"
	local shade, win, body
	local entry = { conns = {} }
	shade, win, body = UI.Window(gui, "PostFight", 920, 780, nil, { footer = 64, onClose = close, accent = won and T.gold or (lost and T.red or T.sub) })
	entry.shade = shade
	active = entry
	State.windows.PostFight = close
	State.HideHud("PostFight", true)
	shade.Destroying:Connect(function()
		State.HideHud("PostFight", false)
	end)
	local canvas = UI.CanvasSize(gui)
	local short = canvas.Y < 560
	local compact = canvas.Y < 640
	local bodyTop = short and 108 or 146
	body.Position = UDim2.fromOffset(24, bodyTop)
	body.Size = UDim2.new(1, -48, 1, -(bodyTop + 72))
	local P = State.P or {}
	local youName = P.identity and P.identity.name or "You"
	local oppName = data.opp or "Opponent"
	local names = { youName, oppName }
	-- a title note from Career marks a championship night
	local titleNote
	for _, n in ipairs(data.notes or {}) do
		if type(n) == "string" and n:find("CHAMPION") then
			titleNote = n
			break
		end
	end

	-- the head: a full-bleed band across the top of the window in the result's colour (the shape of this
	-- screen), the kicker and the headline on it in ink, the emblem at its right; the method line under it
	local bandH = short and 96 or 132
	local band = UI.Frame(win, { Name = "Band", Size = UDim2.new(1, 0, 0, bandH), BackgroundColor3 = won and T.gold or (lost and T.red or T.panel2), ZIndex = win.ZIndex })
	UI.Corner(band, UI.R.xl)
	UI.Frame(band, { Name = "Square", Position = UDim2.new(0, 0, 1, -UI.R.xl), Size = UDim2.new(1, 0, 0, UI.R.xl), BackgroundColor3 = band.BackgroundColor3 })
	UI.Frame(win, { Name = "BandRule", Position = UDim2.new(0, 0, 0, bandH), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line })
	local ink = (won or lost) and T.ink or T.text
	local kickerText = titleNote and (won and "Championship night  ·  and new" or "Championship night") or ("Fight night" .. ((data.venue and data.venue ~= "") and ("  ·  " .. tostring(data.venue)) or ""))
	UI.Text(win, string.upper(kickerText), { Font = T.semi, TextSize = 11, TextColor3 = ink, TextTransparency = 0.25, Position = UDim2.fromOffset(28, short and 14 or 20), Size = UDim2.new(1, -130, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = win.ZIndex + 1 })
	local emblem = won and (stoppage and "ko" or (titleNote and "belt" or "trophy")) or (lost and (stoppage and "ko" or "glove") or "versus")
	local es = short and 50 or 72
	local tile = UI.IconTile(win, emblem, es, ink, { Name = "Emblem", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -84, 0, short and 24 or 30), iconScale = 0.62, fill = band.BackgroundColor3, fillT = 0 })
	local tileScale = UI.New("UIScale", { Scale = 0.6, Parent = tile })
	UI.Tween(tileScale, { Scale = 1 }, UI.Motion.spring)
	local headline = won and "Victory" or (lost and "Defeat" or "Draw")
	local big = UI.Title(win, headline, { TextSize = short and 40 or 56, TextColor3 = ink, Position = UDim2.fromOffset(26, short and 30 or 40), Size = UDim2.new(1, -140, 0, short and 44 or 60), TextTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = win.ZIndex + 1 })
	UI.Tween(big, { TextTransparency = 0 }, UI.Motion.slow)
	local scores = type(res.scores) == "table" and #res.scores > 0 and (" (" .. table.concat(res.scores, ", ") .. ")") or ""
	UI.Text(win, string.format("%s%s  ·  Round %d  ·  vs %s", METHOD[res.method] or tostring(res.method or ""), scores, num(res.round), oppName),
		{ Font = T.semi, TextSize = short and 13 or 14, TextColor3 = ink, Position = UDim2.fromOffset(28, short and 74 or 104), Size = UDim2.new(1, -140, 0, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = win.ZIndex + 1 })

	-- the announcer's call (a line of the ring announcer's script)
	local call
	if res.outcome == "draw" then
		call = "\"...this bout is declared a draw.\""
	elseif stoppage then
		call = string.format("\"...the winner, by %s: %s.\"", string.lower(METHOD[res.method] or res.method), won and youName or oppName)
	else
		call = string.format("\"...and the winner, by %s: %s.\"", string.lower(res.decisionText or METHOD[res.method] or "decision"), won and youName or oppName)
	end
	UI.Line(body, call, { Font = T.semi, TextSize = compact and 13 or 15, TextColor3 = T.sub, LayoutOrder = 1 })
	if titleNote then
		UI.Line(body, titleNote, { Face = "heading", TextSize = compact and 16 or 18, TextColor3 = T.gold, LayoutOrder = 2 })
	end
	if res.reason and res.reason ~= "" and res.reason ~= "Decision" then
		UI.Line(body, tostring(res.reason), { TextColor3 = T.sub, TextSize = 13, LayoutOrder = 3 })
	end

	-- OFFICIAL SCORECARDS
	local J = type(res.judging) == "table" and res.judging or nil
	local hasCards = res.cards and res.cards[1] and (num(res.cards[1][1]) + num(res.cards[1][2])) > 0
	if hasCards then
		UI.Kicker(body, stoppage and "Scorecards at the stoppage" or "Official scorecards", nil, { icon = "contract", order = 10 })
		local card = UI.Card(body, { pad = compact and 10 or 14, order = 11 })
		Scorecards.Grid(card, J or { cards = res.cards }, names, { rounds = (data.rounds or (J and #J.rounds) or num(res.round)), compact = compact })
		-- the judges' leanings
		if not compact then
			local leans = {}
			for j, jn in ipairs(J and J.judgeNames or {}) do
				table.insert(leans, string.format("Judge %d favours %s", j, string.lower(jn.lean or "")))
			end
			if #leans > 0 then
				UI.Line(card, table.concat(leans, "  ·  "), { TextColor3 = T.dim, TextSize = 12 })
			end
		end
	end

	-- FIGHT STATISTICS
	UI.Kicker(body, "Fight statistics  ·  red you, blue " .. oppName, T.sub, { icon = "chart", order = 20 })
	local stats = UI.Card(body, { pad = compact and 10 or 16, order = 21 })
	local you = J and J.totals and J.totals.you or { landed = res.landed, thrown = res.thrown, power = 0, kd = res.kdFor }
	local opp = J and J.totals and J.totals.opp or { landed = res.oppLanded, thrown = res.oppThrown, power = 0, kd = res.kdAgainst }
	you.kd = you.kd or num(res.kdFor)
	opp.kd = opp.kd or num(res.kdAgainst)
	Scorecards.PunchTable(stats, you, opp, { compact = compact, h = compact and 26 or 30, size = compact and 17 or 20 })
	if type(res.combos) == "table" then
		local oc = type(res.oppCombos) == "table" and res.oppCombos or {}
		Scorecards.Versus(stats, "COMBOS LANDED", tostring(num(res.combos.landed)), tostring(num(oc.landed)), num(res.combos.landed), num(oc.landed), { h = compact and 26 or 30, size = compact and 17 or 20, order = 90 })
		Scorecards.Versus(stats, "BEST COMBINATION", tostring(num(res.combos.best)), tostring(num(oc.best)), num(res.combos.best), num(oc.best), { h = compact and 26 or 30, size = compact and 17 or 20, order = 91 })
		if Combos and Combos.StatsText then
			local line = Combos.StatsText(res.combos)
			if line then
				UI.Line(stats, line, { TextColor3 = T.gold, TextSize = 13, Font = T.semi, LayoutOrder = 92 })
			end
		end
	end
	if res.dodges then
		UI.Line(stats, string.format("Head movement: %d dodges, %d punches made to miss  ·  %d feints (%d bites)  ·  %d second wind%s", num(res.dodges), num(res.evades), num(res.feints), num(res.feintBites), num(res.secondWinds),
			num(res.secondWinds) == 1 and "" or "s"), { TextColor3 = T.sub, TextSize = 12, LayoutOrder = 93 })
	end

	-- KNOCKDOWNS
	local kds = type(res.knockdowns) == "table" and res.knockdowns or {}
	UI.Kicker(body, string.format("Knockdowns  ·  %d", #kds), T.sub, { icon = "ko", order = 30 })
	local kdCard = UI.Card(body, { pad = compact and 10 or 14, gap = 4, order = 31 })
	if #kds == 0 then
		UI.Line(kdCard, "Nobody went down.", { TextColor3 = T.sub, TextSize = 13 })
	end
	for i, k in ipairs(kds) do
		local mine = k.who == "you"
		local sev = k.severity == "out" and "OUT COLD" or (k.severity == "heavy" and "a heavy knockdown" or "a flash knockdown")
		local row = UI.Frame(kdCard, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i })
		local dot = UI.Frame(row, { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = mine and T.red or T.blue })
		UI.Corner(dot, 4)
		UI.Text(row, string.format("Round %d  ·  %s down  ·  %s%s", num(k.round), string.upper(mine and youName or oppName), sev, (type(k.cause) == "string" and k.cause ~= "") and ("  ·  " .. k.cause) or ""),
			{ Font = T.semi, TextSize = 13, TextColor3 = T.text, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end

	-- DAMAGE REPORT
	UI.Kicker(body, "Damage report", T.orange, { icon = "injury", order = 40 })
	local dmg = UI.Card(body, { pad = compact and 10 or 14, gap = 6, order = 41 })
	local cols = UI.Frame(dmg, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.List(cols, 12, true)
	local function dmgCol(title, color, lines, headTaken, bodyTaken, order)
		local c = UI.Frame(cols, { BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
		UI.List(c, 3)
		UI.Text(c, string.upper(title), { Font = T.semi, TextSize = 11, TextColor3 = color, Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 0 })
		UI.Text(c, string.format("Head trauma %d  ·  Body %d%%", math.floor(num(headTaken)), math.floor(num(bodyTaken))), { Font = T.semi, TextSize = 12, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
		for i, l in ipairs(lines) do
			UI.Line(c, "-  " .. l[1], { TextColor3 = l[2], TextSize = 13, LayoutOrder = 1 + i })
		end
		return c
	end
	local yourCol = dmgCol(youName, T.redLight, damageLines(res.face, res.headTaken, res.bodyTaken, res.concPeak, res.noseBroken), res.headTaken, res.bodyTaken, 1)
	dmgCol(oppName, T.blue, damageLines(res.oppFace, res.damageDealt, 0, 0, res.oppFace and res.oppFace.nose), res.damageDealt, 0, 2)
	-- the injuries on the profile (the push after the result brings the new ones)
	local injLine = UI.Line(dmg, "", { TextColor3 = T.red, TextSize = 13, Font = T.semi, Visible = false })
	local function refreshInjuries()
		local list = State.P and State.P.condition and State.P.condition.injuries or {}
		if #list == 0 then
			injLine.Visible = false
			return
		end
		local parts = {}
		for _, inj in ipairs(list) do
			local new = snap and not snap.injuries[inj.id or inj.name]
			table.insert(parts, string.format("%s%s (%d days)", new and "NEW: " or "", inj.name or inj.id or "?", num(inj.days)))
		end
		injLine.Text = "INJURIES  ·  " .. table.concat(parts, "  ·  ")
		injLine.Visible = true
	end
	refreshInjuries()
	if res.weighIn and res.weighIn.over and res.weighIn.over > 0 then
		UI.Line(dmg, string.format("Missed weight by %.1f lbs.", res.weighIn.over), { TextColor3 = T.red, TextSize = 13, Font = T.semi })
	end
	if res.simulated then
		UI.Line(dmg, "Simulated fight", { TextColor3 = T.sub, TextSize = 12 })
	end

	-- EARNINGS & RANKINGS
	UI.Kicker(body, "Earnings and rankings", T.green, { icon = "coin", order = 50 })
	local money = UI.Card(body, { pad = compact and 10 or 14, gap = 6, order = 51 })
	local prow = UI.Frame(money, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, compact and 40 or 50) })
	UI.Title(prow, Config.Money(num(data.earnings)), { Face = "number", TextSize = compact and 28 or 36, TextColor3 = T.green, Size = UDim2.new(0.5, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = true })
	UI.New("UITextSizeConstraint", { MaxTextSize = compact and 28 or 36, MinTextSize = 16, Parent = prow:FindFirstChildWhichIsA("TextLabel") })
	local rankLabel = UI.Text(prow, "", { Font = T.semi, TextSize = compact and 12 or 13, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true })
	local function refreshRank()
		local Pn = State.P or {}
		local parts = {}
		local before = snap and snap.ranks or {}
		local after = type(Pn.ranks) == "table" and Pn.ranks or {}
		for _, org in ipairs(Config.Orgs or {}) do
			local a, b = before[org], after[org]
			if a ~= nil or b ~= nil then
				if a == b then
					table.insert(parts, org .. " " .. rankWord(b))
				else
					table.insert(parts, string.format("%s %s -> %s", org, rankWord(a), rankWord(b)))
				end
			end
		end
		local rec = type(Pn.record) == "table" and Pn.record or nil
		local recText = rec and string.format("Record %d-%d-%d (%d KO)", num(rec.w), num(rec.l), num(rec.d), num(rec.ko)) or nil
		local text = (#parts > 0 and table.concat(parts, "  ·  ") or "Unranked")
		rankLabel.Text = recText and (recText .. "\n" .. text) or text
	end
	refreshRank()
	for i, n in ipairs(data.notes or {}) do
		local bigNote = type(n) == "string" and (n:find("CHAMPION") or n:find("PRO") or n:find("LEGEND") or n:find("TOP 10") or n:find("Promoted") or n:find("SPECIAL MOVE"))
		UI.Line(money, tostring(n), { TextColor3 = bigNote and T.gold or T.text, Font = bigNote and T.semi or T.font, TextSize = 13, LayoutOrder = 10 + i })
	end
	-- the profile push after the result (the record, the rankings, the injuries)
	table.insert(entry.conns, State.Changed:Connect(function()
		if active ~= entry then
			return
		end
		pcall(refreshRank)
		pcall(refreshInjuries)
	end))

	local cbh = math.max(48, UI.MinHit(win))
	UI.PadStart(UI.Button(win, "Continue", { Size = UDim2.new(0, 260, 0, cbh), Position = UDim2.new(0.5, -130, 1, -(14 + cbh)), BackgroundColor3 = T.gold }, close))
	-- ClientMain's result window, when it comes after this one, is closed (this screen is the result)
	for _, delay in ipairs({ 0.2, 0.7, 1.4 }) do
		task.delay(delay, function()
			if active == entry then
				local legacy = State.windows.Result
				if type(legacy) == "function" then
					pcall(legacy)
				end
			end
		end)
	end
	return entry
end

local started = false
function PostFightUI.Start()
	if started then
		return
	end
	started = true
	State.FightRemote.OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.t == "start" then
			takeSnap()
		elseif msg.t == "aborted" then
			close()
		end
	end)
end
PostFightUI.Start()

return PostFightUI
