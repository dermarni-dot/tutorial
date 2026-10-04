-- Activities: every training session and its minigame.
-- A session is a short structured workout: rounds or sets with rests in between, a live
-- heart-rate / calorie readout and the drill's own numbers on the panel (and on the smart
-- screens), coach technique tips during the rests, and a graded result with personal
-- bests (the server keeps the records).
--  combo     heavy bag: combinations, power shots on a power meter, speed burst
--  rhythm    speed bag: alternating rhythm, then faster doubles / triplets
--  reaction  double-end bag: react, then slip & counter
--  mitts     mitt work: the coach calls combos over two rounds
--  shadow    mirror: single moves, then flow chains
--  reps      bench, dumbbells, deadlift, squat, pull-ups: 2 sets x 5 reps at a real load
--  pace      treadmill / bike / rower intervals with live machine readouts
--  ladder    named agility drills (smart reaction lights at the top level)
--  rope      basic bounce, boxer skip, double unders
--  hold      recovery breathing: ice bath, stretching, massage, sauna, recovery chamber
--  course    roadwork loop      swim  pool lengths (both measured by the server)
-- Sparring opens the intensity picker and hands over to the fight client.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local GymVisuals = require(script.Parent:WaitForChild("GymVisuals"))
local T = UI.Theme
local K = Enum.KeyCode

local Activities = {}
local player = Players.LocalPlayer
local current = nil

local TIME_SCALE = Config.TrainingTimeScale or 6 -- training seconds per real second (kcal, distance, time-in)
local DOT = " · "
local PANEL_H = 314
local STAGE_Y = 92
local STAGE_H = 120
local STUD_M = 0.28 -- metres per stud (roadwork distance)
-- how hard each drill works you even between presses (heart-rate effort floor, 0..1)
local BASE_EFFORT = { combo = 0.45, rhythm = 0.3, reaction = 0.5, mitts = 0.55, shadow = 0.45, ladder = 0.45, rope = 0.45 }

local WINDUP = { jab = 0.16, cross = 0.22, leadhook = 0.24, rearhook = 0.26, uppercut = 0.26, overhand = 0.34 }
local HAND = { jab = "L", cross = "R", leadhook = "L", rearhook = "R", uppercut = "R", overhand = "R" }
local POWER = { jab = 0.55, cross = 0.9, leadhook = 0.95, rearhook = 1.05, uppercut = 1.0, overhand = 1.25 }

local PUNCH_ACTIONS = {
	{ id = "jab", label = "JAB", keys = { K.J, K.One } },
	{ id = "cross", label = "CROSS", keys = { K.K, K.Two } },
	{ id = "leadhook", label = "L.HOOK", keys = { K.L, K.Three } },
	{ id = "rearhook", label = "R.HOOK", keys = { K.Four, K.Semicolon } },
	{ id = "uppercut", label = "UPPER", keys = { K.U, K.Five } },
	{ id = "overhand", label = "OVERHAND", keys = { K.O, K.Six } },
}
local DEFENSE_ACTIONS = {
	{ id = "slipL", label = "SLIP L", keys = { K.Q } },
	{ id = "slipR", label = "SLIP R", keys = { K.E } },
	{ id = "roll", label = "ROLL", keys = { K.C } },
	{ id = "pivotL", label = "PIVOT", keys = { K.Z } },
	{ id = "parry", label = "PARRY", keys = { K.R } },
}
local KEYNAME = { [K.J] = "J", [K.K] = "K", [K.L] = "L", [K.Four] = "4", [K.U] = "U", [K.O] = "O", [K.Q] = "Q", [K.E] = "E",
	[K.C] = "C", [K.Z] = "Z", [K.R] = "R", [K.Space] = "SPACE", [K.W] = "W", [K.A] = "A", [K.S] = "S", [K.D] = "D", [K.F] = "F", [K.G] = "G" }
local LABEL = { jab = "JAB", cross = "CROSS", leadhook = "L.HOOK", rearhook = "R.HOOK", uppercut = "UPPER", overhand = "OVERHAND",
	slipL = "SLIP L", slipR = "SLIP R", roll = "ROLL", pivotL = "PIVOT", parry = "PARRY",
	F = "STEP IN", B = "STEP BACK", L = "CIRCLE L", R = "CIRCLE R" }

local function actionList(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, a in ipairs(list) do
			table.insert(out, a)
		end
	end
	return out
end

-- 1240 -> "1,240"
local function fmtInt(n)
	local s = tostring(math.max(0, math.floor((tonumber(n) or 0) + 0.5)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- 5.30 -> "5.3", 12 -> "12", 1500 -> "1,500"
local function fmtNum(v)
	v = tonumber(v) or 0
	if v >= 100 or v % 1 == 0 then
		return fmtInt(v)
	end
	local s = string.format("%.2f", v)
	s = (s:gsub("0+$", ""))
	s = (s:gsub("%.$", ""))
	return s
end

-- 75 -> "1:15"
local function clock(sec)
	sec = math.max(0, math.floor((tonumber(sec) or 0) + 0.5))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function gradeColor(id)
	local g = Config.GradeInfo(id)
	return Color3.fromRGB(g.rgb[1], g.rgb[2], g.rgb[3])
end

local function pickDistinct(list, n)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	local out = {}
	for i = 1, math.min(n, #copy) do
		out[i] = copy[i]
	end
	return out
end

------------------------------------------------------------------------
-- Session context (UI + input + heart rate + local animation helpers)
------------------------------------------------------------------------
local function newContext(info)
	local P = State.P
	local ctx = {
		level = info.level or 1, params = info.params or {}, act = info.act, station = info.station,
		handler = nil, keymap = {}, conns = {}, buttons = {}, cleanups = {},
		out = {}, -- drill numbers sent with the result (display / personal bests only)
		lines = {}, -- the one-line session summary on the result screen
		tipIndex = math.random(0, 5), mode = "work", resting = false, baseEffort = info.baseEffort,
	}
	ctx.smart = ctx.params.smart == true
	local panel = UI.Frame(State.gui, { Name = "Activity", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0.96, 0, 0, PANEL_H), BackgroundColor3 = T.bg, BackgroundTransparency = 0.04 })
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(600, PANEL_H), Parent = panel })
	UI.Corner(panel, 12)
	UI.Stroke(panel, T.gold, 2)
	ctx.panel = panel
	ctx.title = UI.Text(panel, info.act.name:upper(), { Font = T.bold, TextSize = 20, TextColor3 = T.gold, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.4, -14, 0, 24), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true, TextWrapped = false })
	UI.New("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 10, Parent = ctx.title })
	-- live numbers: heart rate, calories, round - and the drill's own stats on a second line
	ctx.live = UI.Text(panel, "", { Font = T.semi, TextSize = 13, RichText = true, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -108, 0, 4), Size = UDim2.new(0.6, -116, 0, 32), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, TextScaled = true, TextWrapped = false, AutomaticSize = Enum.AutomaticSize.None })
	UI.New("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8, Parent = ctx.live })
	ctx.info = UI.Text(panel, "", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 30), AutomaticSize = Enum.AutomaticSize.None })
	-- ROUND / SET header
	ctx.header = UI.Text(panel, "", { Font = T.bold, TextSize = 13, TextColor3 = T.gold, Position = UDim2.fromOffset(14, 67), Size = UDim2.new(1, -28, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local _, setProg = UI.Bar(panel, { Position = UDim2.new(0, 14, 0, 83), Size = UDim2.new(1, -28, 0, 5) }, T.gold)
	ctx.setProgress = setProg
	setProg(0)
	ctx.stage = UI.Frame(panel, { Name = "Stage", Position = UDim2.new(0, 14, 0, STAGE_Y), Size = UDim2.new(1, -28, 0, STAGE_H), BackgroundColor3 = Color3.fromRGB(10, 10, 14), ClipsDescendants = true })
	UI.Corner(ctx.stage, 8)
	ctx.flash = UI.Text(panel, "", { Font = T.bold, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -28, 0, 34), Position = UDim2.new(0, 14, 0, STAGE_Y + 84), ZIndex = 5, AutomaticSize = Enum.AutomaticSize.None, TextStrokeTransparency = 0.4 })
	ctx.inputBar = UI.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, STAGE_Y + STAGE_H + 6), Size = UDim2.new(1, -28, 0, 88) })
	UI.Grid(ctx.inputBar, UDim2.new(1 / 6, -5, 0, 40), nil, 5)
	ctx.quit = UI.Button(panel, "QUIT", { Size = UDim2.fromOffset(86, 28), Position = UDim2.new(1, -100, 0, 8), BackgroundColor3 = T.red, TextSize = 13 }, function()
		ctx.cancelled = true
	end)

	function ctx.setInfo(text)
		ctx.info.Text = text
	end
	function ctx.feedback(text, color)
		ctx.flash.Text = text
		ctx.flash.TextColor3 = color or T.text
		local id = os.clock()
		ctx.flashId = id
		task.delay(0.8, function()
			if ctx.flashId == id and ctx.flash.Parent then
				ctx.flash.Text = ""
			end
		end)
	end
	-- the session summary (result screen) and the numbers sent to the server
	function ctx.note(text)
		table.insert(ctx.lines, text)
	end
	function ctx.put(key, value)
		if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
			ctx.out[key] = value
		end
	end
	function ctx.onDestroy(fn)
		table.insert(ctx.cleanups, fn)
	end

	-- heart rate & calories: resting HR from fatigue and fitness, rising toward the drill's working
	-- HR (faster with more input), dropping during rests; kcal integrated from the heart rate
	local cond = P and P.condition or {}
	local pstats = P and P.stats or {}
	local age = P and P.identity and P.identity.age or 22
	ctx.restHR = math.clamp(66 + (cond.fatigue or 20) * 0.14 - ((pstats.Stamina or 40) - 40) * 0.15, 48, 84)
	ctx.maxHR = math.floor(208 - 0.7 * age)
	ctx.hr = ctx.restHR + 10 + math.random() * 8
	ctx.hrPeak = ctx.hr
	ctx.kcal = 0
	local recHR = Config.RecoveryHR[info.act.id]
	ctx.recovery = recHR ~= nil
	ctx.workHR = recHR and (ctx.restHR + recHR) or (Config.TrainingHR[info.act.id] or 150)
	local activity, sinceLive = 0, 1
	function ctx.pulse(n)
		activity = math.min(6, activity + 0.25 * (n or 1))
	end
	function ctx.refreshLive()
		local hr = math.floor(ctx.hr + 0.5)
		local f = hr / ctx.maxHR
		local col = f >= 0.9 and "#FF5A50" or (f >= 0.8 and "#FFA040" or (f >= 0.65 and "#6EE696" or "#F0F0F5"))
		local top = string.format('<font color="%s">HR %d</font> bpm%s%d kcal', col, hr, DOT, math.floor(ctx.kcal + 0.5))
		if ctx.roundText then
			top ..= DOT .. ctx.roundText
		end
		local extra = ctx.statsText
		ctx.live.Text = (extra and extra ~= "") and (top .. "\n" .. extra) or top
	end
	-- the drill's live numbers (second line of the live readout)
	function ctx.stats(text)
		if text ~= ctx.statsText then
			ctx.statsText = text
			ctx.refreshLive()
		end
	end
	table.insert(ctx.conns, RunService.Heartbeat:Connect(function(dt)
		if ctx.mode == "done" then
			return
		end
		dt = math.min(dt, 0.1)
		activity *= math.exp(-dt / 1.5)
		local effort = math.clamp(math.max(activity / 1.5, ctx.intensity or ctx.baseEffort or 0), 0, 1)
		local target, k
		if ctx.mode == "rest" then
			target, k = math.min(ctx.hr, ctx.restHR + 16), 0.11
		elseif ctx.recovery then
			target, k = ctx.workHR, 0.09
		else
			target = ctx.restHR + (ctx.workHR - ctx.restHR) * (0.4 + 0.6 * effort)
			k = target > ctx.hr and (0.04 + 0.22 * effort) or 0.07
		end
		ctx.hr = math.min(ctx.maxHR, ctx.hr + (target - ctx.hr) * (1 - math.exp(-k * dt)))
		ctx.hrPeak = math.max(ctx.hrPeak, ctx.hr)
		ctx.kcal += math.max(0, ctx.hr - 60) * 0.1 / 60 * dt * TIME_SCALE
		sinceLive += dt
		if sinceLive >= 0.15 then
			sinceLive = 0
			ctx.refreshLive()
		end
	end))

	-- input: on-screen buttons and keys go through one dispatcher; rests ignore new presses
	-- (releases still pass so a held lift / breath can't get stuck)
	local function dispatch(id, down)
		local h = ctx.handler
		if not h then
			return
		end
		if down then
			if ctx.resting then
				return
			end
			ctx.pulse()
		end
		h(id, down)
	end
	function ctx.on(fn)
		ctx.handler = fn
	end
	function ctx.bind(actions, cellsPerRow)
		UI.Clear(ctx.inputBar)
		local grid = ctx.inputBar:FindFirstChildOfClass("UIGridLayout")
		grid.CellSize = UDim2.new(1 / (cellsPerRow or math.min(6, #actions)), -5, 0, 40)
		ctx.keymap = {}
		ctx.buttons = {}
		for i, a in ipairs(actions) do
			for _, key in ipairs(a.keys or {}) do
				ctx.keymap[key] = a.id
			end
			local keyText = a.keys and a.keys[1] and (KEYNAME[a.keys[1]] or a.keys[1].Name) or ""
			local b = UI.Button(ctx.inputBar, a.label .. (keyText ~= "" and ("  [" .. keyText .. "]") or ""), { LayoutOrder = i, TextSize = 13, BackgroundColor3 = a.color or T.panel2 })
			b.MouseButton1Down:Connect(function()
				dispatch(a.id, true)
			end)
			b.MouseButton1Up:Connect(function()
				dispatch(a.id, false)
			end)
			ctx.buttons[a.id] = b
		end
	end
	function ctx.wait(sec)
		local t0 = os.clock()
		while os.clock() - t0 < sec do
			if ctx.cancelled then
				return false
			end
			RunService.Heartbeat:Wait()
		end
		return not ctx.cancelled
	end

	-- rounds, rests and progress
	local function overlay(transparency)
		local o = UI.Frame(panel, { Name = "Overlay", Position = UDim2.new(0, 14, 0, STAGE_Y), Size = UDim2.new(1, -28, 0, STAGE_H), BackgroundColor3 = Color3.fromRGB(14, 14, 20), BackgroundTransparency = transparency or 0, ZIndex = 8 })
		UI.Corner(o, 8)
		UI.Stroke(o, T.line, 1)
		return o
	end
	function ctx.nextTip()
		local tips = Config.TrainingTips[ctx.act.id]
		if not tips or #tips == 0 then
			return nil
		end
		ctx.tipIndex += 1
		return tips[(ctx.tipIndex - 1) % #tips + 1]
	end
	-- sets the "ROUND 2/3 · POWER SHOTS" header and shows a short intro banner (sec = 0: header only)
	function ctx.round(i, n, name, kind, sec)
		kind = kind or "ROUND"
		ctx.roundI, ctx.roundN = i, n
		local tag = n > 1 and string.format("%s %d/%d", kind, i, n) or kind
		ctx.roundText = n > 1 and tag or nil
		ctx.header.Text = name and (tag .. DOT .. name) or tag
		ctx.refreshLive()
		sec = sec or (i == 1 and 1.4 or 1.0)
		if sec <= 0 then
			return not ctx.cancelled
		end
		ctx.resting = true
		local o = overlay(0.12)
		UI.Text(o, n > 1 and string.format("%s %d", kind, i) or kind, { Font = T.bold, TextSize = 34, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 40), AutomaticSize = Enum.AutomaticSize.None })
		if name then
			UI.Text(o, name, { Font = T.semi, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
		end
		local ok = ctx.wait(sec)
		o:Destroy()
		ctx.resting = false
		return ok
	end
	-- a breather between rounds / sets: countdown + coach tip; inputs are ignored and the heart rate drops
	function ctx.rest(sec, title, note, tip)
		ctx.resting = true
		ctx.mode = "rest"
		local o = overlay(0.03)
		UI.Text(o, title or "REST", { Font = T.bold, TextSize = 17, TextColor3 = T.gold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -110, 0, 22), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		if note then
			UI.Text(o, note, { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -110, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		local count = UI.Text(o, "", { Font = T.bold, TextSize = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 2), Size = UDim2.fromOffset(90, 44), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(o, "REST", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 44), Size = UDim2.fromOffset(90, 12), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		tip = tip or ctx.nextTip()
		if tip then
			UI.Text(o, "COACH:  \"" .. tip .. "\"", { Font = T.semi, TextSize = 15, Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 44), TextYAlignment = Enum.TextYAlignment.Top, AutomaticSize = Enum.AutomaticSize.None })
		end
		local _, setBar = UI.Bar(o, { Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 4) }, T.blue)
		local t0 = os.clock()
		local ok = true
		while true do
			if ctx.cancelled then
				ok = false
				break
			end
			local left = sec - (os.clock() - t0)
			if left <= 0 then
				break
			end
			count.Text = tostring(math.ceil(left))
			setBar(left / sec)
			RunService.Heartbeat:Wait()
		end
		o:Destroy()
		ctx.resting = false
		ctx.mode = "work"
		return ok
	end
	-- progress through the current round, shown as progress through the whole session
	function ctx.progress(f)
		local n = math.max(1, ctx.roundN or 1)
		local i = math.clamp(ctx.roundI or 1, 1, n)
		setProg((i - 1 + math.clamp(f, 0, 1)) / n)
	end

	-- local animation helpers
	local char = player.Character
	function ctx.punch(ptype, zone)
		local c = player.Character
		if not c then
			return 0.2, "R"
		end
		local hand = HAND[ptype] or "R"
		if ptype == "uppercut" then
			ctx.upHand = ctx.upHand == "R" and "L" or "R"
			hand = ctx.upHand
		end
		c:SetAttribute("Act", string.format("%s|%s|%s|%.2f", ptype, hand, zone or "head", WINDUP[ptype] or 0.2))
		c:SetAttribute("ActId", (c:GetAttribute("ActId") or 0) + 1)
		return WINDUP[ptype] or 0.2, hand
	end
	function ctx.move(kind, dir)
		local c = player.Character
		if c then
			c:SetAttribute("Act", string.format("%s|%s|head|0.25", kind, dir or "L"))
			c:SetAttribute("ActId", (c:GetAttribute("ActId") or 0) + 1)
		end
	end
	function ctx.drive(d)
		if char then
			char:SetAttribute("PoseDrive", d)
		end
	end
	function ctx.speed(w)
		if char then
			char:SetAttribute("PoseSpeed", w)
		end
	end
	function ctx.attr(name, v)
		if char then
			char:SetAttribute(name, v)
		end
	end
	function ctx.impact(power, side)
		if ctx.station then
			GymVisuals.Impact(ctx.station, power, side)
		end
	end
	-- keys work while the panel is alive
	table.insert(ctx.conns, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		local id = ctx.keymap[input.KeyCode]
		if id then
			dispatch(id, true)
		end
	end))
	table.insert(ctx.conns, UserInputService.InputEnded:Connect(function(input)
		local id = ctx.keymap[input.KeyCode]
		if id then
			dispatch(id, false)
		end
	end))
	function ctx.destroy()
		ctx.mode = "done"
		ctx.handler = nil
		for _, c in ipairs(ctx.conns) do
			c:Disconnect()
		end
		for _, fn in ipairs(ctx.cleanups) do
			pcall(fn)
		end
		if panel.Parent then
			panel:Destroy()
		end
		if char then
			for _, a in ipairs({ "PoseDrive", "PoseSpeed", "RepCount", "RopeSpin", "RopeFoot" }) do
				char:SetAttribute(a, nil)
			end
		end
	end
	return ctx
end

local function stageWidth(ctx)
	local w = ctx.stage.AbsoluteSize.X
	return w > 100 and w or 520
end

local function chip(parent, text, x, w, color)
	local f = UI.Frame(parent, { Position = UDim2.new(0, x, 0.5, -20), Size = UDim2.fromOffset(w, 40), BackgroundColor3 = color or T.panel2 })
	UI.Corner(f, 8)
	UI.Pad(f, 2, 4)
	local t = UI.Text(f, text, { Font = T.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true })
	UI.New("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = t })
	return f, t
end

-- a row of chips at a fixed height (with ">" between them for flow chains)
local function chipRow(ctx, labels, top, arrows, maxW)
	local n = #labels
	local gap = arrows and 20 or 8
	local w = math.max(36, math.min(maxW or 100, math.floor((stageWidth(ctx) - 20 - (n - 1) * gap) / math.max(1, n))))
	local chips = {}
	for i, text in ipairs(labels) do
		local x = 10 + (i - 1) * (w + gap)
		local f = chip(ctx.stage, text, x, w)
		f.Position = UDim2.new(0, x, 0, top)
		chips[i] = f
		if arrows and i < n then
			UI.Text(ctx.stage, ">", { Font = T.bold, TextSize = 16, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, x + w, 0, top), Size = UDim2.fromOffset(gap, 40), AutomaticSize = Enum.AutomaticSize.None })
		end
	end
	return chips
end

local function timeBar(ctx, top, color)
	local bar = UI.Frame(ctx.stage, { Position = UDim2.new(0, 10, 0, top), Size = UDim2.new(1, -20, 0, 6), BackgroundColor3 = color or T.green })
	UI.Corner(bar, 3)
	return function(frac)
		bar.Size = UDim2.new(math.clamp(frac, 0, 1), -20 * math.clamp(frac, 0, 1), 0, 6)
	end
end

-- the full-height panel (course / swim shrink it while running)
local function compactPanel(ctx)
	ctx.panel.Size = UDim2.new(0.96, 0, 0, 196)
	ctx.stage.Size = UDim2.new(1, -28, 0, 48)
	ctx.flash.Position = UDim2.new(0, 14, 0, STAGE_Y + 8)
	ctx.inputBar.Position = UDim2.new(0, 14, 0, STAGE_Y + 54)
end
local function fullPanel(ctx)
	ctx.panel.Size = UDim2.new(0.96, 0, 0, PANEL_H)
	ctx.stage.Size = UDim2.new(1, -28, 0, STAGE_H)
	ctx.flash.Position = UDim2.new(0, 14, 0, STAGE_Y + 84)
	ctx.inputBar.Position = UDim2.new(0, 14, 0, STAGE_Y + STAGE_H + 6)
end

------------------------------------------------------------------------
-- Minigames: each returns a performance 0..1 (nil if cancelled)
------------------------------------------------------------------------
local GAMES = {}

-- HEAVY BAG -------------------------------------------------------------
local function comboPool(lv)
	local pool = { { "jab", "cross" }, { "jab", "jab", "cross" }, { "jab", "cross", "leadhook" } }
	if lv >= 2 then
		table.insert(pool, { "jab", "cross", "leadhook", "cross" })
		table.insert(pool, { "cross", "leadhook", "cross" })
	end
	if lv >= 3 then
		table.insert(pool, { "jab", "uppercut", "leadhook" })
		table.insert(pool, { "leadhook", "rearhook", "leadhook" })
		table.insert(pool, { "jab", "cross", "leadhook*", "cross" })
	end
	if lv >= 4 then
		table.insert(pool, { "jab", "cross", "leadhook", "rearhook", "uppercut" })
		table.insert(pool, { "jab", "overhand", "leadhook*" })
		table.insert(pool, { "leadhook*", "leadhook", "cross", "uppercut" })
	end
	return pool
end

-- estimated punch force: grows with the Power stat and the bag level (roughly 350..1500 lbs)
local function punchLbs(ctx, ptype, quality)
	local P = State.P
	local power = math.clamp(P and P.stats and P.stats.Power or 40, 10, 99)
	local potential = 500 + power * 8 + (math.clamp(ctx.level, 1, 6) - 1) * 40
	local pf = 0.85 + 0.15 * ((POWER[ptype] or 0.9) - 0.55) / 0.7
	return math.floor(math.max(350, potential * (0.45 + 0.55 * math.clamp(quality, 0, 1)) * pf))
end

-- the smart bag's screen (after the impact readout the bag shows by itself)
local function bagScreen(ctx, text)
	if ctx.smart then
		task.delay(0.4, function()
			GymVisuals.SetDisplay("heavybag", text)
		end)
	end
end

-- 3 rounds: combinations, power shots on a power meter, a 6-second speed burst
GAMES.combo = function(ctx)
	local lv = ctx.level
	local pool = comboPool(lv)
	local punches, maxLbs = 0, 0

	-- ROUND 1: COMBINATIONS
	ctx.bind(PUNCH_ACTIONS)
	ctx.setInfo("Throw each combination in order before the bar runs out. (body) = dig it to the body." .. (ctx.smart and "  SMART BAG: impact tracking on." or ""))
	if not ctx.round(1, 3, "COMBINATIONS") then
		return nil
	end
	local combos, total, good, speed, clean = 4, 0, 0, 0, 0
	for r = 1, combos do
		UI.Clear(ctx.stage)
		local combo = pool[math.random(1, #pool)]
		local labels = {}
		for i, c in ipairs(combo) do
			local name = c:gsub("%*", "")
			labels[i] = (LABEL[name] or name) .. (c:find("%*") and " (body)" or "")
		end
		local chips = chipRow(ctx, labels, 34, false, 100)
		local setTime = timeBar(ctx, 14)
		local limit = 1.3 + #combo * 0.55 - lv * 0.05
		local idx, wrong, start = 1, 0, os.clock()
		chips[1].BackgroundColor3 = T.gold
		ctx.on(function(id, down)
			if not down or idx > #combo then
				return
			end
			local want = combo[idx]:gsub("%*", "")
			local body = combo[idx]:find("%*") ~= nil
			if id == want then
				local windup, hand = ctx.punch(id, body and "body" or "head")
				local pw = POWER[id] * (0.85 + math.random() * 0.3)
				local lbs = punchLbs(ctx, id, 0.5 + math.random() * 0.35)
				maxLbs = math.max(maxLbs, lbs)
				task.delay(windup, function()
					ctx.impact(pw, hand == "L" and -1 or 1)
				end)
				punches += 1
				chips[idx].BackgroundColor3 = T.green
				idx += 1
				if chips[idx] then
					chips[idx].BackgroundColor3 = T.gold
				end
				if ctx.smart then
					ctx.feedback(fmtInt(lbs) .. " lbs", Color3.fromRGB(80, 200, 255))
				end
			else
				wrong += 1
				local at = idx
				chips[at].BackgroundColor3 = T.red
				task.delay(0.15, function()
					if idx == at and chips[at] then
						chips[at].BackgroundColor3 = T.gold
					end
				end)
			end
		end)
		while idx <= #combo and os.clock() - start < limit do
			if ctx.cancelled then
				return nil
			end
			local el = os.clock() - start
			setTime(1 - el / limit)
			ctx.progress((r - 1 + el / limit) / combos)
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		local done = idx - 1
		total += #combo
		good += math.max(0, done - wrong * 0.5)
		local frac = done == #combo and math.max(0, 1 - (os.clock() - start) / limit) or 0
		speed += frac
		if done == #combo and wrong == 0 then
			clean += 1
			ctx.feedback(frac > 0.45 and "PERFECT!" or "CLEAN!", T.gold)
		elseif done == #combo then
			ctx.feedback("SLOPPY", T.orange)
		else
			ctx.feedback("TOO SLOW", T.red)
		end
		ctx.stats(string.format("Combo %d/%d%s%d clean%s%d punches", r, combos, DOT, clean, DOT, punches))
		ctx.progress(r / combos)
		bagScreen(ctx, string.format("COMBO %d/%d\n%d CLEAN", r, combos, clean))
		if not ctx.wait(0.7) then
			return nil
		end
	end
	local comboScore = math.clamp(0.7 * good / math.max(1, total) + 0.3 * speed / combos / 0.6, 0, 1)
	if not ctx.rest(3, "ROUND 1 DONE", string.format("%d/%d clean combinations%s%d punches", clean, combos, DOT, punches)) then
		return nil
	end

	-- ROUND 2: POWER SHOTS - throw when the needle crosses the gold sweet spot
	ctx.bind(actionList({ { id = "power", label = "POWER", keys = { K.Space }, color = T.gold } }, PUNCH_ACTIONS), 4)
	if ctx.buttons.power then
		ctx.buttons.power.TextColor3 = T.bg
	end
	ctx.setInfo("Throw POWER (SPACE) or any punch while the needle is in the GOLD zone. Timing is power - hooks and overhands land heaviest.")
	if not ctx.round(2, 3, "POWER SHOTS") then
		return nil
	end
	local shots = lv >= 3 and 4 or 3
	local powerSum = 0
	for s = 1, shots do
		UI.Clear(ctx.stage)
		UI.Text(ctx.stage, string.format("SHOT %d/%d", s, shots), { Font = T.bold, TextSize = 15, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(0.5, -10, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
		local bestText = UI.Text(ctx.stage, maxLbs > 0 and ("BEST " .. fmtInt(maxLbs) .. " lbs") or "", { Font = T.bold, TextSize = 15, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0.5, -10, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		local meter = UI.Frame(ctx.stage, { Position = UDim2.new(0, 10, 0, 38), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = Color3.fromRGB(30, 30, 38) })
		UI.Corner(meter, 6)
		local w = math.max(0.04, 0.065 - lv * 0.004)
		local c = 0.66 + math.random() * 0.18
		UI.Frame(meter, { Position = UDim2.fromScale(c - w * 2.5, 0), Size = UDim2.fromScale(w * 5, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.55 })
		UI.Frame(meter, { Position = UDim2.fromScale(c - w, 0), Size = UDim2.fromScale(w * 2, 1), BackgroundColor3 = T.gold })
		local needle = UI.Frame(meter, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 5, 1, 14), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
		UI.Text(ctx.stage, "LIGHT", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 70), Size = UDim2.fromOffset(80, 14), AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(ctx.stage, "KNOCKOUT", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 70), Size = UDim2.fromOffset(80, 14), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		local sweep = 0.9 + lv * 0.08 + s * 0.05 -- needle sweeps per second
		local t0 = os.clock()
		local thrown
		local pos = 0
		ctx.on(function(id, down)
			if not down or thrown then
				return
			end
			local ptype = id == "power" and "cross" or id
			if WINDUP[ptype] then
				thrown = { ptype = ptype, pos = pos }
			end
		end)
		while not thrown and os.clock() - t0 < 4.5 do
			if ctx.cancelled then
				return nil
			end
			local u = ((os.clock() - t0) * sweep) % 2
			pos = u < 1 and u or 2 - u
			needle.Position = UDim2.fromScale(pos, 0.5)
			ctx.progress((s - 1 + math.min(1, (os.clock() - t0) / 4.5)) / shots)
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		if thrown then
			local d = math.abs(thrown.pos - c)
			local timing
			if d <= w then
				timing = 1 - 0.2 * d / w
			elseif d <= 2.5 * w then
				timing = 0.8 - 0.5 * (d - w) / (1.5 * w)
			else
				timing = math.max(0, 0.3 - (d - 2.5 * w) * 1.5)
			end
			local lbs = punchLbs(ctx, thrown.ptype, timing)
			maxLbs = math.max(maxLbs, lbs)
			powerSum += timing
			punches += 1
			local windup, hand = ctx.punch(thrown.ptype)
			local imp = math.min(1.5, 0.5 + timing * (0.6 + 0.4 * POWER[thrown.ptype] / 1.25))
			task.delay(windup, function()
				ctx.impact(imp, hand == "L" and -1 or 1)
			end)
			bagScreen(ctx, string.format("POWER\n%s lbs\nBEST %s", fmtInt(lbs), fmtInt(maxLbs)))
			local verdict, col
			if d <= w * 0.35 then
				verdict, col = "PERFECT!", T.gold
			elseif d <= w then
				verdict, col = "SWEET SPOT", T.green
			elseif d <= 2.5 * w then
				verdict, col = "GOOD", T.text
			else
				verdict, col = "MISTIMED", T.orange
			end
			needle.BackgroundColor3 = col
			bestText.Text = "BEST " .. fmtInt(maxLbs) .. " lbs"
			ctx.feedback(verdict .. "   " .. fmtInt(lbs) .. " lbs", col)
		else
			ctx.feedback("TOO LATE", T.red)
		end
		ctx.stats(string.format("Shot %d/%d%sMax %s lbs", s, shots, DOT, fmtInt(maxLbs)))
		ctx.progress(s / shots)
		if not ctx.wait(1.0) then
			return nil
		end
	end
	local powerScore = math.clamp(powerSum / shots, 0, 1)
	if not ctx.rest(3, "ROUND 2 DONE", string.format("Max power %s lbs", fmtInt(maxLbs))) then
		return nil
	end

	-- ROUND 3: SPEED BURST - alternate hands as fast as possible
	ctx.bind({ { id = "L", label = "LEFT", keys = { K.J, K.F, K.One }, color = T.blue }, { id = "R", label = "RIGHT", keys = { K.K, K.G, K.Two }, color = T.red } }, 2)
	ctx.setInfo("Alternate LEFT (J) and RIGHT (K) as fast as you can for 6 seconds. Only alternating punches count!")
	if not ctx.round(3, 3, "SPEED BURST") then
		return nil
	end
	UI.Clear(ctx.stage)
	local burst = 6
	local setTime = timeBar(ctx, 10, T.gold)
	local countText = UI.Text(ctx.stage, "0", { Font = T.bold, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 48), AutomaticSize = Enum.AutomaticSize.None })
	local rateText = UI.Text(ctx.stage, "punches", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.None })
	local count, lastHand = 0, nil
	ctx.on(function(id, down)
		if not down then
			return
		end
		if id == lastHand then
			ctx.feedback("ALTERNATE!", T.orange)
			return
		end
		lastHand = id
		count += 1
		punches += 1
		local windup, hand = ctx.punch(id == "L" and "jab" or "cross")
		task.delay(windup * 0.6, function()
			ctx.impact(0.3 + math.random() * 0.15, hand == "L" and -1 or 1)
		end)
	end)
	local t0 = os.clock()
	while true do
		if ctx.cancelled then
			return nil
		end
		local el = os.clock() - t0
		if el >= burst then
			break
		end
		local rate = count / math.max(0.75, el)
		countText.Text = tostring(count)
		rateText.Text = string.format("%.1f punches / sec", rate)
		setTime(1 - el / burst)
		ctx.progress(el / burst)
		ctx.stats(string.format("%d punches%s%.1f / sec", count, DOT, rate))
		RunService.Heartbeat:Wait()
	end
	ctx.on(nil)
	local pps = count / burst
	local target = 4.4 + lv * 0.2
	local speedScore = math.clamp(pps / target, 0, 1)
	countText.Text = tostring(count)
	rateText.Text = string.format("%.1f punches / sec", pps)
	setTime(0)
	ctx.feedback(pps >= target and "BLAZING HANDS!" or string.format("%.1f / sec", pps), pps >= target and T.gold or T.text)
	bagScreen(ctx, string.format("SESSION\n%d PUNCHES\nMAX %s lbs", punches, fmtInt(maxLbs)))
	ctx.put("punches", punches)
	ctx.put("maxPower", maxLbs)
	ctx.put("handSpeed", math.floor(pps * 10 + 0.5) / 10)
	ctx.note(string.format("Max power %s lbs", fmtInt(maxLbs)))
	ctx.note(string.format("%.1f punches/sec", pps))
	ctx.note(string.format("%d punches", punches))
	if not ctx.wait(0.8) then
		return nil
	end
	return math.clamp(0.5 * comboScore + 0.25 * powerScore + 0.25 * speedScore, 0, 1)
end

-- SPEED BAG -------------------------------------------------------------
local function rhythmLanes(pattern, count, lv)
	local lanes = {}
	if pattern == "alt" then
		for i = 1, count do
			local lane = (i % 2 == 1) and "L" or "R"
			if lv >= 3 and i % 7 == 0 then
				lane = lanes[i - 1] or lane -- a double now and then on the better bags
			end
			lanes[i] = lane
		end
	else
		local hand = "L"
		while #lanes < count do
			local g = (pattern == "mixed" and math.random() < 0.45) and 3 or 2
			for _ = 1, g do
				if #lanes < count then
					table.insert(lanes, hand)
				end
			end
			hand = hand == "L" and "R" or "L"
		end
	end
	return lanes
end

-- 2 rounds: alternating rhythm, then faster doubles (and triplets on the better bags)
GAMES.rhythm = function(ctx)
	local lv = ctx.level
	local baseBpm = ({ 112, 140, 168, 196 })[lv] or 140
	ctx.bind({ { id = "L", label = "LEFT", keys = { K.J, K.F }, color = T.blue }, { id = "R", label = "RIGHT", keys = { K.K, K.G }, color = T.red } }, 2)
	local rounds = {
		{ name = "ALTERNATING RHYTHM", bpm = baseBpm, pattern = "alt" },
		{ name = lv >= 3 and "DOUBLES & TRIPLETS" or "DOUBLES", bpm = math.floor(baseBpm * 1.15 + 0.5), pattern = lv >= 3 and "mixed" or "doubles" },
	}
	local scoreSum, hitsAll, notesAll, bestStreak, bestHpm = 0, 0, 0, 0, 0
	for ri, rd in ipairs(rounds) do
		local interval = 60 / rd.bpm
		local count = math.clamp(math.floor(10 / interval), 16, 40)
		ctx.setInfo(ri == 1 and string.format("Hit LEFT (J) and RIGHT (K) as each beat crosses the gold line. %d BPM - better bags rebound faster.", rd.bpm)
			or string.format("Same hand two%s times in a row now, at %d BPM. Stay loose and keep the rhythm.", lv >= 3 and " or three" or "", rd.bpm))
		if not ctx.round(ri, #rounds, string.format("%s%s%d BPM", rd.name, DOT, rd.bpm)) then
			return nil
		end
		UI.Clear(ctx.stage)
		local lineX = 70
		UI.Frame(ctx.stage, { Position = UDim2.new(0, lineX - 2, 0, 6), Size = UDim2.new(0, 4, 1, -46), BackgroundColor3 = T.gold })
		local lanes = rhythmLanes(rd.pattern, count, lv)
		local notes = {}
		local start = os.clock() + 1.2
		for i = 1, count do
			local lane = lanes[i]
			local f = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -100, 0, lane == "L" and 30 or 62), BackgroundColor3 = lane == "L" and T.blue or T.red })
			UI.Corner(f, 13)
			UI.Text(f, lane, { Font = T.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })
			notes[i] = { t = start + (i - 1) * interval, lane = lane, f = f, judged = false }
		end
		local perfect, goodN, streak, hits = 0, 0, 0, 0
		local function judge(n, dt)
			n.judged = true
			n.f.Visible = false
			local a = math.abs(dt)
			if a < 0.06 then
				perfect += 1
				hits += 1
				streak += 1
				ctx.feedback("PERFECT x" .. streak, T.gold)
			elseif a < 0.13 then
				goodN += 1
				hits += 1
				streak += 1
				ctx.feedback("GOOD", T.green)
			else
				streak = 0
				ctx.feedback("OFF BEAT", T.orange)
			end
			bestStreak = math.max(bestStreak, streak)
			ctx.speed(1 + math.min(streak, 20) * 0.04)
		end
		ctx.on(function(id, down)
			if not down then
				return
			end
			local now = os.clock()
			ctx.impact(ri == 1 and 0.8 or 0.9, id == "L" and -1 or 1)
			local best, bestDt
			for _, n in ipairs(notes) do
				if not n.judged and n.lane == id then
					local dt = now - n.t
					if math.abs(dt) < 0.22 and (not best or math.abs(dt) < math.abs(bestDt)) then
						best, bestDt = n, dt
					end
				end
			end
			if best then
				judge(best, bestDt)
			end
		end)
		local pxPerSec = 260
		while true do
			if ctx.cancelled then
				return nil
			end
			local now = os.clock()
			local alive = false
			for _, n in ipairs(notes) do
				if not n.judged then
					alive = true
					local x = lineX + (n.t - now) * pxPerSec
					n.f.Position = UDim2.new(0, x, 0, n.lane == "L" and 30 or 62)
					if now - n.t > 0.22 then
						n.judged = true
						n.f.Visible = false
						streak = 0
						ctx.feedback("MISS", T.red)
					end
				end
			end
			local el = now - start
			ctx.progress(el / (count * interval))
			ctx.stats(string.format("%d hits/min%sstreak %d (best %d)", el > 1 and math.floor(hits / el * 60) or 0, DOT, streak, bestStreak))
			if not alive then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		ctx.speed(1)
		bestHpm = math.max(bestHpm, hits / math.max(1, os.clock() - start) * 60)
		scoreSum += (perfect + goodN * 0.65) / count
		hitsAll += hits
		notesAll += count
		if ri < #rounds then
			if not ctx.rest(3, "ROUND 1 DONE", string.format("%d/%d on the beat%sbest streak %d", hits, count, DOT, bestStreak)) then
				return nil
			end
		end
	end
	local acc = math.floor(hitsAll / math.max(1, notesAll) * 100 + 0.5)
	ctx.put("hitsPerMin", math.floor(bestHpm + 0.5))
	ctx.put("bestStreak", bestStreak)
	ctx.put("accuracy", acc)
	ctx.note(string.format("%d hits/min", math.floor(bestHpm + 0.5)))
	ctx.note(string.format("Best streak %d", bestStreak))
	ctx.note(string.format("%d%% on the beat", acc))
	return math.clamp(scoreSum / #rounds, 0, 1)
end

-- DOUBLE-END BAG --------------------------------------------------------
local DEF_TEXT = { slipL = "<< SLIP LEFT", slipR = "SLIP RIGHT >>", roll = "ROLL UNDER!" }

local function defenseMove(ctx, id)
	if id == "roll" then
		ctx.move("roll", "L")
	elseif id == "slipL" or id == "slipR" then
		ctx.move("slip", id == "slipL" and "L" or "R")
	end
end

local function bagPunch(ctx)
	local windup, hand = ctx.punch(math.random() < 0.5 and "jab" or "cross")
	task.delay(windup, function()
		ctx.impact(0.8, hand == "L" and -1 or 1)
	end)
end

-- 2 rounds: react (punch / slip / roll on cue), then slip & counter (defend, then punch straight back)
GAMES.reaction = function(ctx)
	local lv = ctx.level
	local window = ({ 0.95, 0.8, 0.68, 0.56 })[lv] or 0.8
	local actions = { { id = "punch", label = "PUNCH", keys = { K.J, K.K } }, { id = "slipL", label = "SLIP L", keys = { K.Q } }, { id = "slipR", label = "SLIP R", keys = { K.E } } }
	if lv >= 2 then
		table.insert(actions, { id = "roll", label = "ROLL", keys = { K.C } })
	end
	ctx.bind(actions, #actions)
	local reactSum, reactN = 0, 0
	local function avgMs()
		return reactN > 0 and math.floor(reactSum / reactN * 1000 + 0.5) or 0
	end

	-- ROUND 1: REACT
	ctx.setInfo(string.format("PUNCH when the bag comes into range, SLIP or ROLL when it swings back at you. Reaction window %.2fs.", window))
	if not ctx.round(1, 2, "REACT") then
		return nil
	end
	local cues, score, hits = 8, 0, 0
	for i = 1, cues do
		UI.Clear(ctx.stage)
		if not ctx.wait(0.45 + math.random() * 0.9) then
			return nil
		end
		local options = { "punch", "punch", "slipL", "slipR" }
		if lv >= 2 then
			table.insert(options, "roll")
		end
		local cue = options[math.random(1, #options)]
		local text = cue == "punch" and "PUNCH!" or DEF_TEXT[cue]
		local f = chip(ctx.stage, text, 0, 260, cue == "punch" and T.green or T.orange)
		f.Position = UDim2.new(0.5, -130, 0.5, -34)
		if cue ~= "punch" then
			ctx.impact(-0.7, 0) -- the bag springs back toward you
		end
		local shown = os.clock()
		local answered, correct = false, false
		ctx.on(function(id, down)
			if not down or answered then
				return
			end
			answered = true
			correct = id == cue
			if id == "punch" then
				bagPunch(ctx)
			else
				defenseMove(ctx, id)
			end
		end)
		while not answered and os.clock() - shown < window do
			if ctx.cancelled then
				return nil
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		local rt = os.clock() - shown
		if answered and correct and rt <= window then
			score += 1 - 0.4 * (rt / window)
			hits += 1
			reactSum += rt
			reactN += 1
			f.BackgroundColor3 = T.green
			ctx.feedback(string.format("%d ms", math.floor(rt * 1000)), T.green)
		elseif not answered and cue ~= "punch" then
			f.BackgroundColor3 = T.red
			ctx.feedback("CLIPPED!", T.red)
		else
			f.BackgroundColor3 = T.red
			ctx.feedback(answered and "WRONG MOVE" or "TOO SLOW", T.red)
		end
		ctx.stats(string.format("%d/%d%savg %d ms", hits, i, DOT, avgMs()))
		ctx.progress(i / cues)
		if not ctx.wait(0.35) then
			return nil
		end
	end
	local r1 = math.clamp(score / cues / 0.85, 0, 1)
	if not ctx.rest(3, "ROUND 1 DONE", string.format("%d/%d reactions%savg %d ms", hits, cues, DOT, avgMs())) then
		return nil
	end

	-- ROUND 2: SLIP & COUNTER
	ctx.setInfo("The bag swings at you: make the defensive move first, then PUNCH straight back before it settles.")
	if not ctx.round(2, 2, "SLIP & COUNTER") then
		return nil
	end
	local cues2, score2, counters = 5, 0, 0
	local counterWindow = window * 0.9 + 0.2
	for i = 1, cues2 do
		UI.Clear(ctx.stage)
		if not ctx.wait(0.5 + math.random() * 0.7) then
			return nil
		end
		local defs = { "slipL", "slipR" }
		if lv >= 2 then
			table.insert(defs, "roll")
		end
		local want = defs[math.random(1, #defs)]
		local cw = math.min(190, math.floor((stageWidth(ctx) - 60) / 2))
		local c1 = chip(ctx.stage, DEF_TEXT[want], 0, cw, T.orange)
		c1.Position = UDim2.new(0.5, -cw - 24, 0.5, -34)
		UI.Text(ctx.stage, ">", { Font = T.bold, TextSize = 20, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.5, -24, 0.5, -34), Size = UDim2.fromOffset(48, 40), AutomaticSize = Enum.AutomaticSize.None })
		local c2 = chip(ctx.stage, "COUNTER!", 0, cw, T.panel2)
		c2.Position = UDim2.new(0.5, 24, 0.5, -34)
		ctx.impact(-0.7, 0)
		local step, shown, shown2 = 1, os.clock(), 0
		local failed, rt = false, nil
		ctx.on(function(id, down)
			if not down or failed or step > 2 then
				return
			end
			if step == 1 then
				if id == "punch" then
					bagPunch(ctx)
				else
					defenseMove(ctx, id)
				end
				if id == want then
					step = 2
					shown2 = os.clock()
					c1.BackgroundColor3 = T.green
					c2.BackgroundColor3 = T.gold
				else
					failed = true
					c1.BackgroundColor3 = T.red
				end
			elseif id == "punch" then
				bagPunch(ctx)
				rt = os.clock() - shown2
				step = 3
				c2.BackgroundColor3 = T.green
			else
				defenseMove(ctx, id)
				failed = true
				c2.BackgroundColor3 = T.red
			end
		end)
		while not failed and step <= 2 do
			if ctx.cancelled then
				return nil
			end
			local now = os.clock()
			if (step == 1 and now - shown > window) or (step == 2 and now - shown2 > counterWindow) then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		if step == 3 and rt then
			counters += 1
			reactSum += rt
			reactN += 1
			score2 += 0.6 + 0.4 * math.clamp(1 - rt / counterWindow, 0, 1)
			ctx.feedback(string.format("COUNTER!  %d ms", math.floor(rt * 1000)), T.gold)
		elseif step == 2 then
			score2 += 0.3
			if not failed then
				c2.BackgroundColor3 = T.red
			end
			ctx.feedback(failed and "THROW THE COUNTER" or "NO COUNTER", T.orange)
		else
			if not failed then
				c1.BackgroundColor3 = T.red
			end
			ctx.feedback(failed and "WRONG MOVE" or "CLIPPED!", T.red)
		end
		ctx.stats(string.format("Counters %d/%d%savg %d ms", counters, i, DOT, avgMs()))
		ctx.progress(i / cues2)
		if not ctx.wait(0.45) then
			return nil
		end
	end
	local r2 = math.clamp(score2 / cues2 / 0.9, 0, 1)
	local acc = math.floor((hits + counters) / (cues + cues2) * 100 + 0.5)
	ctx.put("accuracy", acc)
	ctx.put("counters", counters)
	ctx.note(string.format("Avg reaction %d ms", avgMs()))
	ctx.note(string.format("%d/%d reactions", hits, cues))
	ctx.note(string.format("%d/%d counters", counters, cues2))
	return math.clamp(0.55 * r1 + 0.45 * r2, 0, 1)
end

-- MITT WORK -------------------------------------------------------------
-- 2 rounds of called combinations (round 2 is called faster) with a rest in between
GAMES.mitts = function(ctx)
	local lv = ctx.level
	local members = workspace:FindFirstChild("GymMembers")
	local coach = members and members:FindFirstChild("Coach Benny")
	local coachName = Catalog.Stations.mitts.levels[math.clamp(lv, 1, 5)].name
	local list = {}
	for _, c in ipairs(Config.MittCombos) do
		if c.tier <= lv then
			-- favour combos near your coach's level
			for _ = 1, (c.tier >= lv - 1) and 2 or 1 do
				table.insert(list, c)
			end
		end
	end
	local function say(text)
		local head = coach and coach:FindFirstChild("Head")
		if head then
			pcall(function()
				TextChatService:DisplayBubble(head, text)
			end)
		end
	end
	local function pick(t)
		return t[math.random(1, #t)]
	end
	ctx.bind(actionList(PUNCH_ACTIONS, DEFENSE_ACTIONS))
	local perRound, rounds = 4, 2
	local score, clean, thrown = 0, 0, 0
	for rd = 1, rounds do
		ctx.setInfo(rd == 1 and (coachName .. " calls the combo - throw it back exactly. Higher-level coaches call harder combos, faster.")
			or "Same drill, faster calls. Snap every combination back before the bar runs out.")
		if not ctx.round(rd, rounds, rd == 1 and "CALLED COMBOS" or "SHARPEN UP") then
			return nil
		end
		for r = 1, perRound do
			UI.Clear(ctx.stage)
			local c = list[math.random(1, #list)]
			UI.Text(ctx.stage, "COACH: \"" .. c.name .. "!\"", { Font = T.bold, TextSize = 18, TextColor3 = T.gold, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
			say(c.name .. "!")
			local labels = {}
			for i, k in ipairs(c.keys) do
				labels[i] = LABEL[k] or k
			end
			local chips = chipRow(ctx, labels, 40, false, 92)
			local limit = math.max(1.6, 1.4 + #c.keys * 0.55 - lv * 0.12) * (rd == 2 and 0.85 or 1)
			local setTime = timeBar(ctx, 30)
			local idx, wrong, start = 1, 0, os.clock()
			chips[1].BackgroundColor3 = T.gold
			ctx.on(function(id, down)
				if not down or idx > #c.keys then
					return
				end
				if id == c.keys[idx] then
					local mittSide = "R"
					if WINDUP[id] then
						local _, hand = ctx.punch(id)
						mittSide = hand
					elseif id == "slipL" or id == "slipR" then
						ctx.move("slip", id == "slipL" and "L" or "R")
						mittSide = "D"
					elseif id == "roll" then
						ctx.move("roll", "L")
						mittSide = "D"
					elseif id == "pivotL" then
						ctx.move("pivot", "L")
						mittSide = "D"
					elseif id == "parry" then
						ctx.move("parry", "R")
						mittSide = "L"
					end
					if coach then
						coach:SetAttribute("MittCall", mittSide)
						coach:SetAttribute("MittCallT", os.clock())
						local h = coach:FindFirstChild("Head")
						if h and mittSide ~= "D" then
							task.delay(WINDUP[id] or 0.2, function()
								GymVisuals.Sound(h.Position, 1.6 + math.random() * 0.15, 0.4)
							end)
						end
					end
					thrown += 1
					chips[idx].BackgroundColor3 = T.green
					idx += 1
					if chips[idx] then
						chips[idx].BackgroundColor3 = T.gold
					end
				else
					wrong += 1
					local at = idx
					chips[at].BackgroundColor3 = T.red
					task.delay(0.15, function()
						if idx == at and chips[at] then
							chips[at].BackgroundColor3 = T.gold
						end
					end)
				end
			end)
			while idx <= #c.keys and os.clock() - start < limit do
				if ctx.cancelled then
					return nil
				end
				local el = os.clock() - start
				setTime(1 - el / limit)
				ctx.progress((r - 1 + el / limit) / perRound)
				RunService.Heartbeat:Wait()
			end
			ctx.on(nil)
			local done = idx - 1
			local part = math.max(0, done - wrong * 0.5) / #c.keys
			local fast = done == #c.keys and math.max(0, 1 - (os.clock() - start) / limit) or 0
			score += math.min(1.15, part * 0.8 + fast * 0.35)
			if done == #c.keys and wrong == 0 then
				clean += 1
				local line = pick(Config.MittPraise)
				ctx.feedback(line, T.gold)
				say(line)
			elseif done == #c.keys then
				local line = pick(Config.MittCritique.sloppy)
				ctx.feedback(line, T.orange)
				say(line)
			else
				local line = pick(Config.MittCritique.slow)
				ctx.feedback(line, T.red)
				say(line)
			end
			ctx.stats(string.format("Combo %d/%d%s%d clean", (rd - 1) * perRound + r, perRound * rounds, DOT, clean))
			ctx.progress(r / perRound)
			if not ctx.wait(0.75) then
				return nil
			end
		end
		if rd < rounds then
			local tip = ctx.nextTip()
			if tip then
				say(tip)
			end
			if not ctx.rest(3.5, "ROUND 1 DONE", string.format("%d/%d clean combos", clean, perRound), tip) then
				return nil
			end
		end
	end
	ctx.put("cleanCombos", clean)
	ctx.put("punches", thrown)
	ctx.note(string.format("%d/%d clean combos", clean, perRound * rounds))
	ctx.note(string.format("%d shots & moves", thrown))
	return math.clamp(score / (perRound * rounds), 0, 1)
end

-- SHADOW BOXING ---------------------------------------------------------
local SHADOW_PROMPTS = {
	{ id = "F", text = "STEP IN", keys = { K.W, K.Up } }, { id = "B", text = "STEP BACK", keys = { K.S, K.Down } },
	{ id = "L", text = "CIRCLE LEFT", keys = { K.A, K.Left } }, { id = "R", text = "CIRCLE RIGHT", keys = { K.D, K.Right } },
	{ id = "slipL", text = "SLIP LEFT", keys = { K.Q } }, { id = "slipR", text = "SLIP RIGHT", keys = { K.E } },
	{ id = "roll", text = "ROLL", keys = { K.C } }, { id = "jab", text = "JAB", keys = { K.J } }, { id = "cross", text = "CROSS", keys = { K.K } },
	{ id = "leadhook", text = "HOOK", keys = { K.L } },
}
local SHADOW_LABEL = { F = "STEP IN", B = "STEP BACK", L = "CIRCLE L", R = "CIRCLE R", slipL = "SLIP L", slipR = "SLIP R", roll = "ROLL", jab = "JAB", cross = "CROSS", leadhook = "HOOK" }

local function shadowMove(ctx, id)
	if id == "F" or id == "B" or id == "L" or id == "R" then
		ctx.move("step", id)
	elseif id == "slipL" or id == "slipR" then
		ctx.move("slip", id == "slipL" and "L" or "R")
	elseif id == "roll" then
		ctx.move("roll", "L")
	elseif WINDUP[id] then
		ctx.punch(id)
	end
end

-- 2 rounds: single moves on cue, then flow chains of mixed moves
GAMES.shadow = function(ctx)
	local lv = ctx.level
	local window = ({ 1.25, 1.0, 0.8 })[lv] or 1.0
	local actions = {}
	for _, p in ipairs(SHADOW_PROMPTS) do
		table.insert(actions, { id = p.id, label = (p.text:gsub("CIRCLE ", ""):gsub("STEP ", "")), keys = p.keys })
	end
	ctx.bind(actions, 5)
	local function mirror(text)
		if lv >= 3 then
			GymVisuals.SetDisplay("mirror", text)
		end
	end

	-- ROUND 1: MOVES
	ctx.setInfo("Footwork (W/A/S/D), head movement (Q/E/C) and punches (J/K/L): follow the prompts in the mirror.")
	if not ctx.round(1, 2, "MOVES") then
		return nil
	end
	local n, score, movesHit = 8, 0, 0
	for i = 1, n do
		UI.Clear(ctx.stage)
		if not ctx.wait(0.15 + math.random() * 0.3) then
			return nil
		end
		local p = SHADOW_PROMPTS[math.random(1, #SHADOW_PROMPTS)]
		local f = chip(ctx.stage, p.text, 0, 240, T.panel2)
		f.Position = UDim2.new(0.5, -120, 0.5, -34)
		local shown = os.clock()
		local answered, ok = false, false
		ctx.on(function(id, down)
			if not down or answered then
				return
			end
			answered = true
			ok = id == p.id
			shadowMove(ctx, id)
		end)
		while not answered and os.clock() - shown < window do
			if ctx.cancelled then
				return nil
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		local rt = os.clock() - shown
		if ok then
			score += 1 - 0.35 * rt / window
			movesHit += 1
			f.BackgroundColor3 = T.green
		else
			f.BackgroundColor3 = T.red
			ctx.feedback(answered and "WRONG MOVE" or "TOO SLOW", T.red)
		end
		local form = math.floor(score / i * 100)
		mirror(string.format("FORM %d%%", form))
		ctx.stats(string.format("Move %d/%d%sform %d%%", i, n, DOT, form))
		ctx.progress(i / n)
		if not ctx.wait(0.3) then
			return nil
		end
	end
	local r1 = math.clamp(score / n / 0.85, 0, 1)
	if not ctx.rest(3, "ROUND 1 DONE", string.format("%d/%d moves on cue", movesHit, n)) then
		return nil
	end

	-- ROUND 2: FLOW - chains of 3-4 mixed moves
	ctx.setInfo("Flow through each chain in order: punches, head movement and footwork blended together. Smooth beats fast.")
	if not ctx.round(2, 2, "FLOW") then
		return nil
	end
	local chains = 3
	local flows = pickDistinct(Config.ShadowFlows, chains)
	local score2, flowsClean = 0, 0
	for ci = 1, #flows do
		UI.Clear(ctx.stage)
		local flow = flows[ci]
		local len = lv <= 1 and 3 or (lv == 2 and (math.random() < 0.5 and 3 or 4) or 4)
		local seq = {}
		for k = 1, math.min(len, #flow) do
			seq[k] = flow[k]
		end
		local labels = {}
		for k, id in ipairs(seq) do
			labels[k] = SHADOW_LABEL[id] or id
		end
		local chips = chipRow(ctx, labels, 36, true, 110)
		local setTime = timeBar(ctx, 14)
		local limit = 1.4 + #seq * 0.75 - (lv - 1) * 0.2
		local idx, wrong, start = 1, 0, os.clock()
		chips[1].BackgroundColor3 = T.gold
		ctx.on(function(id, down)
			if not down or idx > #seq then
				return
			end
			shadowMove(ctx, id)
			if id == seq[idx] then
				chips[idx].BackgroundColor3 = T.green
				idx += 1
				if chips[idx] then
					chips[idx].BackgroundColor3 = T.gold
				end
			else
				wrong += 1
				local at = idx
				chips[at].BackgroundColor3 = T.red
				task.delay(0.15, function()
					if idx == at and chips[at] then
						chips[at].BackgroundColor3 = T.gold
					end
				end)
			end
		end)
		while idx <= #seq and os.clock() - start < limit do
			if ctx.cancelled then
				return nil
			end
			local el = os.clock() - start
			setTime(1 - el / limit)
			ctx.progress((ci - 1 + el / limit) / #flows)
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		local done = idx - 1
		local part = math.max(0, done - wrong * 0.5) / #seq
		local fast = done == #seq and math.max(0, 1 - (os.clock() - start) / limit) or 0
		score2 += math.min(1, part * 0.8 + fast * 0.4)
		if done == #seq and wrong == 0 then
			flowsClean += 1
			ctx.feedback(fast > 0.4 and "FLOWING!" or "SMOOTH", T.gold)
		elseif done == #seq then
			ctx.feedback("CHOPPY", T.orange)
		else
			ctx.feedback("LOST THE FLOW", T.red)
		end
		mirror(string.format("FLOW %d/%d\nFORM %d%%", ci, #flows, math.floor(score2 / ci * 100)))
		ctx.stats(string.format("Flow %d/%d%s%d clean", ci, #flows, DOT, flowsClean))
		ctx.progress(ci / #flows)
		if not ctx.wait(0.7) then
			return nil
		end
	end
	local r2 = math.clamp(score2 / math.max(1, #flows), 0, 1)
	local acc = math.floor((movesHit / n * 0.5 + r2 * 0.5) * 100 + 0.5)
	ctx.put("accuracy", acc)
	ctx.put("cleanFlows", flowsClean)
	ctx.note(string.format("%d/%d moves", movesHit, n))
	ctx.note(string.format("%d/%d clean flows", flowsClean, #flows))
	return math.clamp(0.5 * r1 + 0.5 * r2, 0, 1)
end

-- STRENGTH --------------------------------------------------------------
-- a believable working load from the Power stat, the trained muscle group and the station level
local function liftLoad(ctx)
	local def = Config.LiftLoads[ctx.act.id]
	if not def then
		return nil, nil, nil
	end
	local P = State.P
	local power = P and P.stats and P.stats.Power or 40
	local muscle = P and P.body and P.body[def.muscle] or 10
	local st = Catalog.Stations[ctx.station]
	local maxLv = st and #st.levels or 4
	local s = math.clamp((power - 20) / 79, 0, 1) * 0.6 + math.clamp(muscle / 100, 0, 1) * 0.25
		+ (maxLv > 1 and math.clamp((ctx.level - 1) / (maxLv - 1), 0, 1) or 0) * 0.15
	if def.bodyweight then
		-- body weight first, then a weight belt
		local add = math.floor(math.max(0, (s - 0.35) / 0.65) * def.max / 5 + 0.5) * 5
		return add, add > 0 and ("BW +" .. add .. " lbs") or "BW", def.name, true
	end
	local load = math.floor((def.min + (def.max - def.min) * s) / 5 + 0.5) * 5
	return load, string.format(def.each and "%d lbs each" or "%d lbs", load), def.name, false
end

-- 2 sets x 5 reps: hold to lift, release in the green zone (set 2 is tighter); a spotter saves failed reps
GAMES.reps = function(ctx)
	local lv = ctx.level
	local load, loadText, exName, bodyweight = liftLoad(ctx)
	exName = exName or ctx.act.name:upper()
	local sets, reps = 2, 5
	ctx.bind({ { id = "lift", label = "HOLD TO LIFT", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Hold SPACE (or the button) to drive the weight up and release inside the green zone. Overshoot and you fail the rep. Set 2 is tighter.")
	UI.Clear(ctx.stage)
	local barBg = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 34), BackgroundColor3 = Color3.fromRGB(40, 20, 20) })
	UI.Corner(barBg, 6)
	local zone = UI.Frame(barBg, { BackgroundColor3 = T.green, Size = UDim2.fromScale(0.2, 1) })
	UI.Corner(zone, 6)
	local fill = UI.Frame(barBg, { BackgroundColor3 = T.gold, BackgroundTransparency = 0.25, Size = UDim2.fromScale(0, 1) })
	UI.Corner(fill, 6)
	local repText = UI.Text(ctx.stage, "", { Font = T.bold, Position = UDim2.fromOffset(20, 56), Size = UDim2.new(0.6, -20, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
	UI.Text(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 56), Size = UDim2.new(0.4, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
	local holding = false
	ctx.on(function(_, down)
		holding = down
	end)
	local P = State.P
	local fatigue = P and P.condition and P.condition.fatigue or 0
	local total, goodReps, fails, lastRpe = 0, 0, 0, 6
	local function rpeText(v)
		return "RPE " .. (v % 1 == 0 and tostring(math.floor(v)) or string.format("%.1f", v))
	end
	for set = 1, sets do
		if not ctx.round(set, sets, loadText and (exName .. DOT .. loadText) or exName, "SET") then
			return nil
		end
		holding = false
		local setGood, setFails = 0, 0
		for r = 1, reps do
			local width = math.max(0.08, (0.24 - r * 0.012 + lv * 0.01) * (set == 2 and 0.78 or 1))
			local lo = math.clamp(0.58 + math.random() * 0.2, 0.5, 0.95 - width)
			zone.Position = UDim2.fromScale(lo, 0)
			zone.Size = UDim2.fromScale(width, 1)
			repText.Text = string.format("SET %d%sREP %d / %d", set, DOT, r, reps)
			local f = 0
			local speed = (0.55 + r * 0.03) * (set == 2 and 1.08 or 1)
			ctx.attr("RepCount", (set - 1) * reps + r)
			ctx.intensity = 0.3
			-- wait for the press
			while not holding do
				if ctx.cancelled then
					return nil
				end
				RunService.Heartbeat:Wait()
			end
			ctx.intensity = 0.85
			local failed = false
			while holding do
				if ctx.cancelled then
					return nil
				end
				f = math.min(1, f + RunService.Heartbeat:Wait() * speed)
				fill.Size = UDim2.fromScale(f, 1)
				ctx.drive(f)
				if f >= 1 then
					failed = true
					break
				end
			end
			local result
			if failed then
				result = 0
				fails += 1
				setFails += 1
				ctx.feedback("SPOTTER: I got you!", T.orange)
			elseif f >= lo and f <= lo + width then
				local center = math.abs(f - (lo + width / 2)) / (width / 2)
				result = center < 0.35 and 1 or 0.85
				goodReps += 1
				setGood += 1
				ctx.feedback(center < 0.35 and "PERFECT REP" or "GOOD REP", center < 0.35 and T.gold or T.green)
			else
				result = f < lo and 0.45 or 0.3
				ctx.feedback(f < lo and "HALF REP" or "LOST CONTROL", T.orange)
			end
			total += result
			-- lower the weight
			ctx.intensity = 0.5
			local t0 = os.clock()
			while os.clock() - t0 < 0.55 do
				if ctx.cancelled then
					return nil
				end
				local k = (os.clock() - t0) / 0.55
				ctx.drive(f * (1 - k))
				fill.Size = UDim2.fromScale(f * (1 - k), 1)
				RunService.Heartbeat:Wait()
			end
			ctx.drive(0)
			fill.Size = UDim2.fromScale(0, 1)
			holding = false
			ctx.stats(string.format("Set %d%s%d/%d good reps%s", set, DOT, setGood, r, setFails > 0 and (DOT .. setFails .. " spotted") or ""))
			ctx.progress(r / reps)
			if not ctx.wait(0.25) then
				return nil
			end
		end
		-- how hard that set felt (rate of perceived exertion, 6-10)
		local rpe = math.clamp(6 + setFails * 1.2 + (reps - setGood) * 0.35 + (set - 1) * 0.6 + fatigue / 50, 6, 10)
		rpe = math.floor(rpe * 2 + 0.5) / 2
		lastRpe = rpe
		ctx.intensity = nil
		if set < sets then
			local left = math.max(0, math.floor(10 - rpe))
			if not ctx.rest(3, string.format("SET %d DONE%s%s", set, DOT, rpeText(rpe)), string.format("%d/%d good reps%s%s", setGood, reps, DOT, left > 0 and (left .. " more in the tank") or "nothing left in the tank")) then
				return nil
			end
		else
			ctx.feedback(rpeText(rpe), rpe >= 9 and T.red or (rpe >= 8 and T.orange or T.green))
		end
	end
	ctx.intensity = nil
	ctx.put(bodyweight and "addedLoad" or "load", load or 0)
	ctx.put("goodReps", goodReps)
	if load and not bodyweight then
		ctx.put("volume", load * goodReps)
	end
	ctx.note(exName .. (loadText and (" " .. loadText) or ""))
	ctx.note(string.format("%d/%d good reps", goodReps, sets * reps))
	if fails > 0 then
		ctx.note(string.format("%d spotted", fails))
	end
	ctx.note(rpeText(lastRpe))
	if not ctx.wait(0.6) then
		return nil
	end
	return math.clamp(total / (sets * reps), 0, 1)
end

-- CARDIO MACHINES -------------------------------------------------------
local INCLINE = { 1.0, 2.0, 0.5, 4.0 } -- treadmill incline per interval

-- tap to hold the pace inside each interval zone; the machine shows its own readouts
GAMES.pace = function(ctx)
	local lv = ctx.level
	local id = ctx.act.id
	local duration = 28
	ctx.bind({ { id = "push", label = "PUSH PACE", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Tap SPACE to speed up. Keep the marker inside the green zone through every interval: warm-up, sprint, recover, all out.")
	local phases = { { 0.3, 0.5, "WARM-UP" }, { 0.6, 0.82, "SPRINT!" }, { 0.35, 0.55, "RECOVER" }, { 0.66, 0.88, "ALL OUT!" } }
	if not ctx.round(1, #phases, phases[1][3], "INTERVAL") then
		return nil
	end
	UI.Clear(ctx.stage)
	local barBg = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 30), BackgroundColor3 = Color3.fromRGB(25, 25, 32) })
	UI.Corner(barBg, 6)
	local zone = UI.Frame(barBg, { BackgroundColor3 = T.green, BackgroundTransparency = 0.3, Size = UDim2.fromScale(0.2, 1) })
	UI.Corner(zone, 6)
	local marker = UI.Frame(barBg, { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 6, 1, 10), Position = UDim2.new(0, 0, 0, -5) })
	local metrics = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 15, TextColor3 = Color3.fromRGB(120, 220, 255), Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 22), AutomaticSize = Enum.AutomaticSize.None })
	local status = UI.Text(ctx.stage, "", { Font = T.bold, Position = UDim2.fromOffset(20, 76), Size = UDim2.new(1, -40, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
	local v = 0.2
	ctx.on(function(_, down)
		if down then
			v = math.min(1, v + 0.085)
		end
	end)
	local inZone, start, last = 0, os.clock(), os.clock()
	local miles, meters, topSpeed, maxWatts, maxSpm, rpmSum, rpmTime = 0, 0, 0, 0, 0, 0, 0
	local phaseIdx, sinceScreen = 1, 1
	local screen = ""
	while true do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		local dt = now - last
		last = now
		local el = now - start
		if el >= duration then
			break
		end
		local pi = math.min(#phases, math.floor(el / (duration / #phases)) + 1)
		if pi ~= phaseIdx then
			phaseIdx = pi
			ctx.round(pi, #phases, phases[pi][3], "INTERVAL", 0)
		end
		local ph = phases[pi]
		local shrink = (lv - 1) * 0.02
		local lo, hi = ph[1] + shrink, ph[2] - shrink
		zone.Position = UDim2.fromScale(lo, 0)
		zone.Size = UDim2.fromScale(hi - lo, 1)
		v = math.max(0, v - dt * 0.2)
		marker.Position = UDim2.new(v, -3, 0, -5)
		local ok = v >= lo and v <= hi
		if ok then
			inZone += dt
		end
		ctx.intensity = 0.25 + v * 0.75
		ctx.speed(0.5 + v * 1.6)
		-- machine readouts
		local readout
		if id == "Bike" then
			local rpm = 50 + v * 70
			local watts = 0.022 * rpm * rpm * (0.9 + 0.12 * lv)
			maxWatts = math.max(maxWatts, watts)
			rpmSum += rpm * dt
			rpmTime += dt
			readout = string.format("%d RPM%s%d W", math.floor(rpm), DOT, math.floor(watts))
			screen = string.format("RPM %d\n%d WATTS", math.floor(rpm), math.floor(watts))
		elseif id == "Rower" then
			local split = 165 - v * 70 -- seconds per 500 m
			local spm = 18 + v * 18
			meters += 500 / split * dt * TIME_SCALE
			maxSpm = math.max(maxSpm, spm)
			readout = string.format("%s /500m%s%d spm%s%d m", clock(split), DOT, math.floor(spm), DOT, math.floor(meters))
			screen = string.format("%s /500\n%d SPM\n%d m", clock(split), math.floor(spm), math.floor(meters))
		else
			local mph = 3 + v * 10
			local incline = INCLINE[pi] + (lv >= 3 and 2 or 0)
			miles += mph / 3600 * dt * TIME_SCALE
			topSpeed = math.max(topSpeed, mph)
			readout = string.format("%.1f mph%s%.1f%% incline%s%.2f mi", mph, DOT, incline, DOT, miles)
			screen = string.format("%.1f MPH\nINCLINE %.1f%%\n%.2f mi", mph, incline, miles)
		end
		metrics.Text = readout
		status.Text = string.format("%s   %s   %.1fs left", ph[3], ok and "IN ZONE" or (v < lo and "FASTER!" or "EASE OFF"), duration - el)
		status.TextColor3 = ok and T.green or T.orange
		ctx.stats(readout)
		sinceScreen += dt
		if sinceScreen >= 0.25 then
			sinceScreen = 0
			GymVisuals.SetDisplay(ctx.station, screen)
		end
		ctx.setProgress(el / duration)
		RunService.Heartbeat:Wait()
	end
	ctx.intensity = nil
	ctx.speed(1)
	local zonePct = math.floor(inZone / duration * 100 + 0.5)
	if id == "Bike" then
		local avgRpm = rpmTime > 0 and rpmSum / rpmTime or 0
		ctx.put("maxWatts", math.floor(maxWatts))
		ctx.put("avgRpm", math.floor(avgRpm))
		ctx.note(string.format("Max %d W", math.floor(maxWatts)))
		ctx.note(string.format("avg %d RPM", math.floor(avgRpm)))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\nMAX %d W", math.floor(maxWatts)))
	elseif id == "Rower" then
		ctx.put("meters", math.floor(meters))
		ctx.put("maxSpm", math.floor(maxSpm))
		ctx.note(string.format("%d m rowed", math.floor(meters)))
		ctx.note(string.format("max %d spm", math.floor(maxSpm)))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%d m", math.floor(meters)))
	else
		ctx.put("distance", math.floor(miles * 100 + 0.5) / 100)
		ctx.put("topSpeed", math.floor(topSpeed * 10 + 0.5) / 10)
		ctx.note(string.format("%.2f mi", miles))
		ctx.note(string.format("top %.1f mph", topSpeed))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%.2f mi", miles))
	end
	ctx.put("inZone", zonePct)
	ctx.note(string.format("%d%% in zone", zonePct))
	return math.clamp(inZone / duration / 0.85, 0, 1)
end

-- AGILITY LADDER --------------------------------------------------------
local LADDER_DIRS = {
	{ id = "F", label = "UP", keys = { K.W, K.Up }, arrow = "^" }, { id = "L", label = "LEFT", keys = { K.A, K.Left }, arrow = "<" },
	{ id = "B", label = "DOWN", keys = { K.S, K.Down }, arrow = "v" }, { id = "R", label = "RIGHT", keys = { K.D, K.Right }, arrow = ">" },
}
local LADDER_PAD = { F = 1, L = 3, B = 4, R = 2 } -- reaction pods: forward, right, left, back

-- named footwork drills (smart reaction lights at the top level: a lit drill, then random lights)
GAMES.ladder = function(ctx)
	local lv = ctx.level
	local dirById = {}
	for _, d in ipairs(LADDER_DIRS) do
		dirById[d.id] = d
	end
	ctx.bind(LADDER_DIRS, 4)
	local smart = lv >= 4
	ctx.onDestroy(function()
		GymVisuals.Light("ladder", 0)
	end)
	local available = {}
	for _, d in ipairs(Config.LadderDrills) do
		if d.lv <= lv then
			table.insert(available, d)
		end
	end
	local drills
	if smart then
		local tpl = available[math.random(1, #available)]
		local steps = {}
		while #steps < 12 do
			for _, s in ipairs(tpl.steps) do
				if #steps < 12 then
					table.insert(steps, s)
				end
			end
		end
		local rnd = {}
		for i = 1, 12 do
			rnd[i] = LADDER_DIRS[math.random(1, 4)].id
		end
		drills = { { name = tpl.name .. " (LIGHTS)", steps = steps }, { name = "RANDOM REACTION", steps = rnd } }
	else
		drills = pickDistinct(available, 4)
	end
	ctx.setInfo(smart and "SMART LIGHTS: step toward each pad as it lights up (W/A/S/D or arrows), as fast as you can."
		or "Run each named footwork drill in order (W/A/S/D or arrows). Speed and accuracy count.")
	local score, total, completed, correct, stepTime = 0, 0, 0, 0, 0
	for p, drill in ipairs(drills) do
		if not ctx.round(p, #drills, drill.name, "DRILL") then
			return nil
		end
		UI.Clear(ctx.stage)
		local seq = {}
		for i, s in ipairs(drill.steps) do
			seq[i] = dirById[s] or LADDER_DIRS[1]
		end
		local len = #seq
		local chips = {}
		if not smart then
			local w = math.max(24, math.min(44, math.floor((stageWidth(ctx) - 20) / len) - 4))
			for i, d in ipairs(seq) do
				chips[i] = chip(ctx.stage, d.arrow, 10 + (i - 1) * (w + 4), w)
			end
			chips[1].BackgroundColor3 = T.gold
		end
		local idx, start = 1, os.clock()
		local limit = smart and 14 or (len * 0.55 + 1)
		local lightAt, lit, nextLight = os.clock(), false, os.clock() + 0.2
		local lightChip
		local function lightUp()
			local d = seq[idx]
			if lightChip then
				lightChip:Destroy()
			end
			lightChip = chip(ctx.stage, d.arrow .. "  " .. d.label, 0, 160, T.blue)
			lightChip.Position = UDim2.new(0.5, -80, 0.5, -34)
			GymVisuals.Light("ladder", LADDER_PAD[d.id], Color3.fromRGB(60, 200, 255))
			lightAt = os.clock()
			lit = true
		end
		ctx.on(function(id, down)
			if not down or idx > len or (smart and not lit) then
				return
			end
			total += 1
			ctx.move("step", id)
			ctx.speed(1.3)
			if id == seq[idx].id then
				correct += 1
				score += smart and math.max(0.3, 1 - (os.clock() - lightAt) / 1.2) or 1
				if chips[idx] then
					chips[idx].BackgroundColor3 = T.green
				end
				idx += 1
				if chips[idx] then
					chips[idx].BackgroundColor3 = T.gold
				end
				if smart then
					lit = false
					GymVisuals.Light("ladder", 0)
					if lightChip then
						lightChip:Destroy()
						lightChip = nil
					end
					nextLight = os.clock() + 0.12 + math.random() * 0.2
				end
			else
				if chips[idx] then
					chips[idx].BackgroundColor3 = T.red
				end
				ctx.feedback("WRONG FOOT", T.red)
			end
		end)
		while idx <= len and os.clock() - start < limit do
			if ctx.cancelled then
				return nil
			end
			if smart and not lit and os.clock() >= nextLight then
				lightUp()
			end
			local el = os.clock() - start
			ctx.progress((idx - 1) / len)
			ctx.stats(string.format("Step %d/%d%s%.1f steps/s", math.min(idx, len), len, DOT, (idx - 1) / math.max(0.5, el)))
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		ctx.speed(1)
		GymVisuals.Light("ladder", 0)
		local el = os.clock() - start
		stepTime += el
		if idx > len then
			completed += 1
			ctx.feedback(string.format("%.1fs", el), T.gold)
		else
			ctx.feedback("OUT OF TIME", T.red)
		end
		ctx.progress(1)
		if not ctx.wait(0.6) then
			return nil
		end
		if p < #drills and ((smart and p == 1) or (not smart and p == 2)) then
			if not ctx.rest(smart and 3 or 2.5, string.format("DRILL %d DONE", p), string.format("%d/%d drills completed", completed, p)) then
				return nil
			end
		end
	end
	local sps = correct / math.max(1, stepTime)
	ctx.put("stepsPerSec", math.floor(sps * 10 + 0.5) / 10)
	ctx.put("drills", completed)
	ctx.note(string.format("%d/%d drills completed", completed, #drills))
	ctx.note(string.format("%.1f steps/s", sps))
	return math.clamp(score / math.max(1, total), 0, 1) * (0.5 + 0.5 * completed / #drills)
end

-- JUMP ROPE -------------------------------------------------------------
local ROPE_INFO = {
	jump = "Press SPACE (or JUMP) as the rope reaches your feet - the bottom of the circle.",
	feet = "BOXER SKIP: land on the called foot - LEFT (A) or RIGHT (D) - as the rope passes your feet.",
	doubles = "DOUBLE UNDER = two quick presses while the rope spins twice. Plain jumps in between.",
	speed = "The rope spins faster now. Same timing - quick, light feet.",
}

-- phases with banners: basic bounce, boxer skip (footwork rope), double unders (weighted rope)
GAMES.rope = function(ctx)
	local doubles = ctx.params.doubleUnders
	local feet = ctx.params.footwork
	local actions = { { id = "jump", label = "JUMP", keys = { K.Space }, color = T.blue } }
	if feet then
		table.insert(actions, { id = "footL", label = "LEFT FOOT", keys = { K.A } })
		table.insert(actions, { id = "footR", label = "RIGHT FOOT", keys = { K.D } })
	end
	ctx.bind(actions, #actions)
	local phases = { { name = "BASIC BOUNCE", mode = "jump" } }
	if feet then
		table.insert(phases, { name = "BOXER SKIP", mode = "feet" })
	end
	if doubles then
		table.insert(phases, { name = "DOUBLE UNDERS", mode = "doubles" })
	end
	if #phases == 1 then
		table.insert(phases, { name = "SPEED SKIP", mode = "speed" })
	end
	local perPhase = #phases >= 3 and { 12, 10, 10 } or { 14, 14 }
	UI.Clear(ctx.stage)
	local R = 44
	local ring = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(R * 2, R * 2), Position = UDim2.new(0, 30, 0.5, -R - 12), BackgroundTransparency = 1 })
	UI.Stroke(UI.Corner(UI.Frame(ring, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }), R), T.line, 3)
	local zoneDot = UI.Frame(ring, { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(R, R * 2), BackgroundColor3 = T.green })
	UI.Corner(zoneDot, 11)
	local dot = UI.Frame(ring, { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(R, 0), BackgroundColor3 = Color3.new(1, 1, 1) })
	UI.Corner(dot, 7)
	local cueText = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 22, Position = UDim2.new(0, R * 2 + 60, 0, 20), Size = UDim2.new(1, -(R * 2 + 70), 0, 30), AutomaticSize = Enum.AutomaticSize.None })
	local countText = UI.Text(ctx.stage, "", { TextSize = 15, Position = UDim2.new(0, R * 2 + 60, 0, 52), Size = UDim2.new(1, -(R * 2 + 70), 0, 22), AutomaticSize = Enum.AutomaticSize.None, TextColor3 = T.sub })
	local totalJumps = 0
	for i = 1, #phases do
		totalJumps += perPhase[i] or 10
	end
	local clean, attempts, streak, bestStreak, doublesDone = 0, 0, 0, 0, 0
	local pressed = {}
	ctx.on(function(id, down)
		if down then
			table.insert(pressed, { id = id, t = os.clock() })
		end
	end)
	for phI, ph in ipairs(phases) do
		ctx.setInfo(ROPE_INFO[ph.mode])
		ctx.attr("RopeSpin", 0)
		cueText.Text = ""
		if not ctx.round(phI, #phases, ph.name, "PHASE") then
			return nil
		end
		local jumps = perPhase[phI] or 10
		local done = 0
		local phase = math.pi -- rope starts overhead
		local omega = ph.mode == "speed" and 7.8 or 6.5
		local cue, need = "jump", 1
		local footNext = math.random() < 0.5 and "footL" or "footR"
		local function newCue()
			cue, need = "jump", 1
			if ph.mode == "doubles" and math.random() < 0.5 then
				cue, need = "double", 2
			elseif ph.mode == "feet" then
				cue = footNext
				if math.random() < 0.8 then
					footNext = footNext == "footL" and "footR" or "footL"
				end
			end
			cueText.Text = cue == "double" and "DOUBLE UNDER!" or (cue == "footL" and "LEFT FOOT (A)" or (cue == "footR" and "RIGHT FOOT (D)" or "JUMP"))
			cueText.TextColor3 = cue == "jump" and T.text or T.gold
		end
		newCue()
		pressed = {}
		local judgeAt, passCue, passNeed, passTime = nil, "jump", 1, 0 -- judge just after the rope passes so slightly late presses count
		local last = os.clock()
		local tripped = 0
		while done < jumps do
			if ctx.cancelled then
				return nil
			end
			local now = os.clock()
			local dt = now - last
			last = now
			if now < tripped then
				pressed = {}
				RunService.Heartbeat:Wait()
				continue
			end
			local w = omega * (cue == "double" and 1.9 or 1)
			local prev = phase
			phase += dt * w
			ctx.attr("RopeSpin", phase)
			ctx.intensity = math.clamp(0.45 + (omega - 6) * 0.07 + (cue == "double" and 0.1 or 0), 0, 1)
			local a = phase % (2 * math.pi)
			dot.Position = UDim2.fromOffset(R + math.sin(a) * R, R + math.cos(a) * R)
			-- the rope passes the feet at multiples of 2*pi
			if not judgeAt and math.floor(prev / (2 * math.pi)) ~= math.floor(phase / (2 * math.pi)) then
				judgeAt = now + 0.1
				passCue, passNeed, passTime = cue, need, now
			end
			if judgeAt and now >= judgeAt then
				judgeAt = nil
				done += 1
				attempts += 1
				local count, good = 0, true
				for _, p in ipairs(pressed) do
					if p.t >= passTime - 0.32 and p.t <= passTime + 0.1 then
						count += 1
						if passCue == "jump" or passCue == "double" then
							good = good and p.id == "jump"
						else
							good = good and p.id == passCue
						end
					end
				end
				pressed = {}
				if count >= passNeed and good then
					clean += 1
					streak += 1
					bestStreak = math.max(bestStreak, streak)
					if passCue == "double" then
						doublesDone += 1
					end
					ctx.move("jump", "L")
					local _, _, root = State.char()
					if root then
						GymVisuals.Sound(root.Position - Vector3.new(0, 3, 0), 2 + math.random() * 0.3, 0.2, "rbxasset://sounds/action_footsteps_plastic.mp3")
					end
					ctx.attr("RopeFoot", passCue == "footL" and "L" or (passCue == "footR" and "R" or nil))
					ctx.feedback(passCue == "double" and "DOUBLE!" or (streak >= 5 and ("CLEAN x" .. streak) or "CLEAN"), T.green)
					omega = math.min(11.5, omega + 0.12)
				else
					streak = 0
					ctx.feedback(count == 0 and "TRIPPED!" or "MISTIMED!", T.red)
					tripped = now + 0.8
					omega = math.max(6, omega - 0.6)
					phase = math.pi
				end
				countText.Text = string.format("Clean %d / %d%sstreak %d", clean, attempts, DOT, streak)
				ctx.stats(string.format("Clean %d/%d%sstreak %d (best %d)", clean, attempts, DOT, streak, bestStreak))
				ctx.progress(done / jumps)
				newCue()
			end
			RunService.Heartbeat:Wait()
		end
		ctx.intensity = nil
		if phI < #phases then
			ctx.attr("RopeSpin", 0)
			ctx.attr("RopeFoot", nil)
			if not ctx.rest(2.5, ph.name .. " DONE", string.format("%d/%d clean%sbest streak %d", clean, attempts, DOT, bestStreak)) then
				return nil
			end
		end
	end
	ctx.put("cleanJumps", clean)
	ctx.put("bestStreak", bestStreak)
	if doubles then
		ctx.put("doubleUnders", doublesDone)
	end
	ctx.note(string.format("%d/%d clean jumps", clean, totalJumps))
	ctx.note(string.format("best streak %d", bestStreak))
	if doubles then
		ctx.note(string.format("%d double unders", doublesDone))
	end
	return math.clamp(clean / math.max(1, totalJumps), 0, 1)
end

-- RECOVERY --------------------------------------------------------------
local HOLD_INFO = {
	IceBath = "Cold water constricts the blood vessels and flushes soreness. Hold to inhale, release to exhale - slow and calm.",
	Stretch = "Long exhales let the muscles release. Hold to inhale, release to exhale and sink into each stretch.",
	Massage = "Relax into the table. Hold to inhale, release to exhale while the tension melts away.",
	Chamber = "Elite recovery tech - oxygen, compression and cold. Breathe with the circle.",
	Sauna = "Sweat out water weight before a weigh-in - rehydrate afterwards! Breathe with the circle.",
}
local MASSAGE_FOCUS = { "BACK & SHOULDERS", "LEGS", "FOREARMS", "NECK", "LOWER BACK" }

-- guided breathing - hold while the circle grows, release while it shrinks - plus what the session does for you
GAMES.hold = function(ctx)
	ctx.bind({ { id = "breathe", label = "HOLD TO INHALE", keys = { K.Space }, color = T.blue } }, 1)
	local act = ctx.act
	local lv = ctx.level
	local P = State.P
	ctx.setInfo(HOLD_INFO[act.id] or "Breathe with the circle: hold to inhale, release to exhale.")
	local breaths, inhale, exhale = 5, 2.6, 2.6
	local cycle = inhale + exhale
	local duration = breaths * cycle
	local fatigue = P and P.condition and P.condition.fatigue or 30
	local tempC = Config.IceBathTempC[math.clamp(lv, 1, #Config.IceBathTempC)]
	local saunaC = Config.SaunaTempC[math.clamp(lv, 1, #Config.SaunaTempC)]
	local st = Catalog.Stations[ctx.station]
	local lvMult = st and st.levels[math.clamp(lv, 1, #st.levels)].mult or 1
	local tensionStart = math.clamp(35 + fatigue * 0.55, 35, 92)
	local function toF(c)
		return math.floor(c * 9 / 5 + 32 + 0.5)
	end
	local stretchStart = math.random(1, #Config.StretchNames)
	local focusStart = math.random(1, #MASSAGE_FOCUS)
	-- what each breath is about (shown in the BREATH header)
	local function breathName(b)
		if act.id == "Stretch" then
			return Config.StretchNames[(stretchStart + b - 2) % #Config.StretchNames + 1]
		elseif act.id == "Massage" then
			return MASSAGE_FOCUS[(focusStart + b - 2) % #MASSAGE_FOCUS + 1]
		elseif act.id == "IceBath" then
			return string.format("WATER %d°F", toF(tempC))
		elseif act.id == "Sauna" then
			return saunaC > 0 and string.format("%d°F", toF(saunaC)) or "SAUNA SUIT"
		elseif act.id == "Chamber" then
			return "1.3 ATA"
		end
		return nil
	end
	if not ctx.round(1, breaths, breathName(1), "BREATH") then
		return nil
	end
	UI.Clear(ctx.stage)
	local circle = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 70, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(80, 170, 255), BackgroundTransparency = 0.3 })
	UI.Corner(circle, 60)
	local label = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.new(0, 140, 0, 8), Size = UDim2.new(1, -150, 0, 22), AutomaticSize = Enum.AutomaticSize.None })
	local line1 = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 14, TextColor3 = Color3.fromRGB(150, 210, 255), Position = UDim2.new(0, 140, 0, 34), Size = UDim2.new(1, -150, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
	local line2 = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, Position = UDim2.new(0, 140, 0, 56), Size = UDim2.new(1, -150, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
	local setMeter
	if act.id == "Massage" or act.id == "Chamber" then
		local _, set = UI.Bar(ctx.stage, { Position = UDim2.new(0, 140, 0, 80), Size = UDim2.new(1, -160, 0, 8) }, act.id == "Massage" and T.orange or T.green)
		setMeter = set
	end
	local holding = false
	ctx.on(function(_, down)
		holding = down
	end)
	local sync, total = 0, 0
	local start, last = os.clock(), os.clock()
	local breathIdx = 1
	local syncF, prog, waterLost, tension, recovered = 0, 0, 0, tensionStart, 0
	while true do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		local dt = now - last
		last = now
		local el = now - start
		if el >= duration then
			break
		end
		local b = math.min(breaths, math.floor(el / cycle) + 1)
		if b ~= breathIdx then
			breathIdx = b
			ctx.round(b, breaths, breathName(b), "BREATH", 0)
		end
		local c = el % cycle
		local inPhase = c < inhale
		local k = inPhase and (c / inhale) or (1 - (c - inhale) / exhale)
		local size = 30 + 70 * k
		circle.Size = UDim2.fromOffset(size, size)
		label.Text = inPhase and "INHALE... (hold)" or "EXHALE... (release)"
		total += dt
		if holding == inPhase then
			sync += dt
		end
		syncF = sync / math.max(0.01, total)
		prog = el / duration
		-- what this recovery is doing for you
		if act.id == "IceBath" then
			line1.Text = string.format("WATER %d°F (%d°C)", toF(tempC), tempC)
			line2.Text = "TIME IN " .. clock(el * TIME_SCALE)
		elseif act.id == "Sauna" then
			line1.Text = saunaC > 0 and string.format("%s %d°F (%d°C)", lv >= 3 and "INFRARED" or "SAUNA", toF(saunaC), saunaC)
				or string.format("SAUNA SUIT%sCORE %.1f°F", DOT, 98.6 + 2.2 * prog)
			waterLost = 2.5 * lvMult * (0.8 + 0.2 * (0.5 + syncF * 0.95)) * prog
			line2.Text = string.format("WATER WEIGHT LOST %.1f lbs", waterLost)
		elseif act.id == "Massage" then
			local finish = tensionStart * (0.6 - 0.3 * syncF)
			tension = tensionStart + (finish - tensionStart) * prog
			line1.Text = string.format("MUSCLE TENSION %d%%", math.floor(tension + 0.5))
			line2.Text = "WORKING: " .. (breathName(b) or "")
			if setMeter then
				setMeter(tension / 100)
			end
		elseif act.id == "Stretch" then
			line1.Text = "STRETCH: " .. (breathName(b) or "")
			line2.Text = string.format("RANGE OF MOTION +%d%%", math.floor(3 + 9 * syncF * prog + 0.5))
		elseif act.id == "Chamber" then
			line1.Text = string.format("PRESSURE 1.3 ATA%sO2 %d%%", DOT, 94 + math.floor(prog * 4))
			recovered = (60 + 40 * syncF) * prog
			line2.Text = string.format("CELL RECOVERY %d%%", math.floor(recovered))
			if setMeter then
				setMeter(recovered / 100)
			end
		end
		ctx.stats(string.format("Breath %d/%d%ssync %d%%", b, breaths, DOT, math.floor(syncF * 100)))
		ctx.setProgress(prog)
		RunService.Heartbeat:Wait()
	end
	local syncPct = math.floor(syncF * 100 + 0.5)
	ctx.put("sync", syncPct)
	ctx.note(string.format("Breathing sync %d%%", syncPct))
	if act.id == "Sauna" then
		waterLost = 2.5 * lvMult * (0.8 + 0.2 * (0.5 + syncF * 0.95))
		ctx.put("waterLost", math.floor(waterLost * 10 + 0.5) / 10)
		ctx.note(string.format("~%.1f lbs water", waterLost))
	elseif act.id == "Massage" then
		ctx.note(string.format("Tension %d%% -> %d%%", math.floor(tensionStart + 0.5), math.floor(tension + 0.5)))
	elseif act.id == "IceBath" then
		ctx.note(string.format("%s at %d°F", clock(duration * TIME_SCALE), toF(tempC)))
	elseif act.id == "Chamber" then
		ctx.note(string.format("Cell recovery %d%%", math.floor(60 + 40 * syncF)))
	end
	return math.clamp(sync / math.max(0.01, total), 0, 1)
end

-- ROADWORK & SWIM -------------------------------------------------------
-- running speed from the character's movement, smoothed (drives the heart rate)
local function trackMovement(ctx, state, dt)
	local _, _, root = State.char()
	if not root then
		return
	end
	local p = Vector3.new(root.Position.X, 0, root.Position.Z)
	if state.lastPos then
		local step = (p - state.lastPos).Magnitude
		if step < 12 then -- ignore teleports
			state.dist += step
		end
		local inst = math.clamp(step / math.max(dt, 1e-3) / 24, 0, 1)
		ctx.intensity = (ctx.intensity or 0) * 0.93 + inst * 0.07
	end
	state.lastPos = p
end

-- ROADWORK: run the loop through every checkpoint (measured by the server)
GAMES.course = function(ctx, info)
	ctx.bind({ { id = "finish", label = "FINISH EARLY", keys = {}, color = T.red } }, 1)
	ctx.setInfo("Run the loop around the gym through all 8 checkpoints and back to the start arch. Hold W - your stamina sets your pace.")
	compactPanel(ctx)
	ctx.header.Text = "ROADWORK" .. DOT .. "8 CHECKPOINTS"
	UI.Clear(ctx.stage)
	local status = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	local gym = workspace:FindFirstChild("Gym")
	local cpFolder = gym and gym:FindFirstChild("TrackCheckpoints")
	local order = { 2, 3, 4, 5, 6, 7, 8, 1 }
	local reached = 0
	local done = false
	local beacon = Instance.new("Part")
	beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch = true, false, false, false
	beacon.Size = Vector3.new(1.5, 40, 1.5)
	beacon.Material = Enum.Material.Neon
	beacon.Color = T.gold
	beacon.Transparency = 0.35
	beacon.Parent = workspace
	ctx.onDestroy(function()
		beacon:Destroy()
	end)
	local function place()
		local cp = cpFolder and cpFolder:FindFirstChild("CP" .. order[math.min(#order, reached + 1)])
		if cp then
			beacon.CFrame = CFrame.new(cp.Position.X, 20, cp.Position.Z)
		end
	end
	place()
	table.insert(ctx.conns, State.Notify.OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.t == "checkpoint" then
			reached = msg.n
			ctx.feedback("CHECKPOINT " .. msg.n .. "/" .. msg.total, T.gold)
			ctx.setProgress(msg.n / msg.total)
			if msg.n >= msg.total then
				done = true
			else
				place()
			end
		end
	end))
	local quit = false
	ctx.on(function(id, down)
		if down and id == "finish" then
			quit = true
		end
	end)
	local move = { dist = 0, lastPos = nil }
	local start, last = os.clock(), os.clock()
	local miles = 0
	while not done and not quit do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		trackMovement(ctx, move, now - last)
		last = now
		local _, _, root = State.char()
		local cp = cpFolder and cpFolder:FindFirstChild("CP" .. order[math.min(#order, reached + 1)])
		local dist = (root and cp) and math.floor((Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(cp.Position.X, 0, cp.Position.Z)).Magnitude) or 0
		local el = now - start
		miles = move.dist * STUD_M / 1609.34
		local pace = miles > 0.01 and clock(el / miles) or "--:--"
		status.Text = string.format("CP %d/8%sNext %d studs%s%s%s%.2f mi%s%s /mi", reached, DOT, dist, DOT, clock(el), DOT, miles, DOT, pace)
		ctx.stats(string.format("%.2f mi%s%s /mi", miles, DOT, pace))
		RunService.Heartbeat:Wait()
	end
	ctx.intensity = nil
	beacon:Destroy()
	local el = os.clock() - start
	ctx.put("distance", math.floor(miles * 100 + 0.5) / 100)
	if miles > 0.01 then
		ctx.put("speed", math.floor(miles / (el / 3600) * 10 + 0.5) / 10)
		ctx.note(string.format("%.2f mi in %s (%s /mi)", miles, clock(el), clock(el / miles)))
	end
	ctx.note(string.format("%d/8 checkpoints", reached))
	return 1
end

-- SWIMMING: swim lengths of the pool (measured by the server)
GAMES.swim = function(ctx, info)
	ctx.bind({ { id = "finish", label = "FINISH EARLY", keys = {}, color = T.red } }, 1)
	local target = info.lengths or 4
	ctx.setInfo(string.format("Jump in and swim %d lengths: touch the far wall, then come back. Swimming builds stamina and speeds recovery.", target))
	compactPanel(ctx)
	ctx.header.Text = string.format("SWIM%s%d LENGTHS", DOT, target)
	UI.Clear(ctx.stage)
	local status = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	local lengths, done, quit = 0, false, false
	local lastLengthAt
	local bestLength
	local start, last = os.clock(), os.clock()
	table.insert(ctx.conns, State.Notify.OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.t == "length" then
			local now = os.clock()
			local split = now - (lastLengthAt or start)
			lastLengthAt = now
			bestLength = bestLength and math.min(bestLength, split) or split
			lengths = msg.n
			ctx.feedback(string.format("LENGTH %d/%d  %s", msg.n, msg.total, clock(split)), T.gold)
			ctx.setProgress(msg.n / msg.total)
			done = msg.n >= msg.total
		end
	end))
	ctx.on(function(id, down)
		if down and id == "finish" then
			quit = true
		end
	end)
	local move = { dist = 0, lastPos = nil }
	while not done and not quit do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		trackMovement(ctx, move, now - last)
		last = now
		local el = now - start
		local pace = lengths > 0 and (clock(el / lengths) .. " /length") or "--:-- /length"
		status.Text = string.format("Lengths %d/%d%s%s%s%s", lengths, target, DOT, clock(el), DOT, pace)
		ctx.stats(string.format("%d/%d lengths%s%s", lengths, target, DOT, pace))
		RunService.Heartbeat:Wait()
	end
	ctx.intensity = nil
	local el = os.clock() - start
	ctx.put("lengths", lengths)
	if lengths > 0 then
		ctx.put("speed", math.floor(lengths / (el / 60) * 10 + 0.5) / 10)
		ctx.note(string.format("%d lengths in %s (%s each)", lengths, clock(el), clock(el / lengths)))
	end
	if bestLength then
		ctx.note("fastest length " .. clock(bestLength))
	end
	return 1
end

------------------------------------------------------------------------
-- Camera during station work
------------------------------------------------------------------------
local LOW = { bench = true, lie = true, lieup = true, longsit = true, sit = true, row = true, bike = true }
-- lifts and cardio read best from the side; bag work over the shoulder
local SIDE = { curl = true, deadlift = true, squat = true, pullup = true, run = true, rope = true, ladder = true, stretch = true }
local function stationCamera(pose)
	local cam = workspace.CurrentCamera
	local _, _, root = State.char()
	if not root then
		return nil
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local base = root.CFrame
	return RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local _, _, r = State.char()
		if not r then
			return
		end
		local p = base.Position
		local look, right = base.LookVector, base.RightVector
		local goal
		-- the activity panel covers the bottom of the screen, so the camera aims a little low:
		-- that lifts the athlete into the clear upper part of the view (feet included)
		if LOW[pose] then
			goal = CFrame.lookAt(p + right * 7.5 + look * 1.5 + Vector3.new(0, 5, 0), p + look * 0.5 - Vector3.new(0, 1.4, 0))
		elseif SIDE[pose] then
			local lift = pose == "pullup" and 1.2 or 0
			goal = CFrame.lookAt(p + right * 10 + look * 2.5 + Vector3.new(0, 2.2 + lift, 0), p + look * 0.6 + Vector3.new(0, lift - 1.7, 0))
		else
			-- over the right shoulder, looking at the equipment
			goal = CFrame.lookAt(p + right * 3.8 - look * 6 + Vector3.new(0, 3.2, 0), p + look * 2.6 + Vector3.new(0, 0.1, 0))
		end
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 6, 0, 1))
	end)
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------
local STAT_NAMES = {
	punches = "Punches", maxPower = "Max power", handSpeed = "Hand speed", hitsPerMin = "Hits per minute",
	bestStreak = "Best streak", accuracy = "Accuracy", counters = "Counters", cleanCombos = "Clean combos",
	cleanFlows = "Clean flows", load = "Load", addedLoad = "Added load", goodReps = "Good reps", volume = "Volume",
	distance = "Distance", topSpeed = "Top speed", maxWatts = "Max watts", avgRpm = "Avg cadence", meters = "Distance",
	maxSpm = "Stroke rate", inZone = "Time in zone", stepsPerSec = "Foot speed", drills = "Drills completed",
	cleanJumps = "Clean jumps", doubleUnders = "Double unders", sync = "Breathing sync", waterLost = "Water cut",
	lengths = "Lengths", speed = "Average speed",
}
local STAT_UNITS = {
	maxPower = " lbs", handSpeed = " punches/s", accuracy = "%", load = " lbs", addedLoad = " lbs", volume = " lbs",
	distance = " mi", topSpeed = " mph", maxWatts = " W", avgRpm = " rpm", meters = " m", maxSpm = " spm", inZone = "%",
	stepsPerSec = " steps/s", sync = "%", waterLost = " lbs",
}
local function statText(actId, key, v)
	local unit = STAT_UNITS[key] or ""
	if key == "speed" then
		unit = actId == "Swimming" and " lengths/min" or " mph"
	end
	return (STAT_NAMES[key] or key) .. " " .. fmtNum(v) .. unit
end

local function coachRemark(actId, grade)
	local special = Config.ActivityRemarks[actId]
	if special then
		if (grade == "S" or grade == "A") and special.hi and math.random() < 0.6 then
			return special.hi
		elseif (grade == "C" or grade == "D") and special.lo and math.random() < 0.6 then
			return special.lo
		end
	end
	local list = Config.GradeRemarks[grade] or Config.GradeRemarks.B
	return list[math.random(1, #list)]
end

local function resultLines(res)
	local lines = {}
	local r = res.result or {}
	if r.gains then
		local parts = {}
		for _, k in ipairs(Config.StatKeys) do
			local g = r.gains[k]
			if g and g > 0.001 then
				table.insert(parts, string.format("+%.2f %s", g, Config.StatNames[k]))
			end
		end
		if #parts > 0 then
			table.insert(lines, { table.concat(parts, "   "), T.green })
		end
	end
	if r.muscle then
		local parts = {}
		for _, k in ipairs(Config.MuscleKeys) do
			local g = r.muscle[k]
			if g and g > 0.01 then
				table.insert(parts, string.format("+%.1f %s", g, Config.MuscleNames[k]))
			end
		end
		if #parts > 0 then
			table.insert(lines, { "Muscle: " .. table.concat(parts, ", "), Color3.fromRGB(150, 200, 255) })
		end
	end
	if r.fat and math.abs(r.fat) > 0.001 then
		table.insert(lines, { string.format("Body fat %+.2f%%", r.fat), r.fat < 0 and T.green or T.orange })
	end
	if r.fatigue then
		table.insert(lines, { string.format("Fatigue now %d%%", math.floor(r.fatigue)), T.sub })
	end
	for _, n in ipairs(r.notes or {}) do
		table.insert(lines, { n, n:find("INJURY") and T.red or T.sub })
	end
	return lines
end

local function showResult(ctx, res, quality)
	ctx.mode = "done" -- freeze the heart-rate readout
	ctx.resting = false
	ctx.handler = nil
	ctx.roundText, ctx.statsText = nil, nil
	ctx.refreshLive()
	fullPanel(ctx)
	for _, c in ipairs(ctx.panel:GetChildren()) do
		if c.Name == "Overlay" then
			c:Destroy()
		end
	end
	UI.Clear(ctx.inputBar)
	UI.Clear(ctx.stage)
	ctx.flash.Text = ""
	local rec = type(res.record) == "table" and res.record or {}
	local grade = type(rec.grade) == "string" and rec.grade or Config.GradeFor(quality)
	local gcol = gradeColor(grade)
	ctx.title.Text = ctx.act.name:upper()
	ctx.header.Text = "SESSION COMPLETE" .. DOT .. "GRADE " .. grade
	ctx.header.TextColor3 = gcol
	ctx.setProgress(1)
	local parts = { string.format("Session quality %d%%", Config.QualityPct(quality)) }
	if type(rec.best) == "number" and rec.best > 0 then
		table.insert(parts, string.format("Personal best %d%%", Config.QualityPct(rec.best)))
	end
	if type(rec.sessions) == "number" and rec.sessions > 0 then
		table.insert(parts, string.format("%d session%s", rec.sessions, rec.sessions == 1 and "" or "s"))
	end
	ctx.info.Text = table.concat(parts, DOT)
	-- the grade badge
	local badge = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(88, STAGE_H - 16), BackgroundColor3 = T.panel2 })
	UI.Corner(badge, 10)
	UI.Stroke(badge, gcol, 2)
	local letter = UI.Text(badge, grade, { Font = T.bold, TextSize = 24, TextColor3 = gcol, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 72), AutomaticSize = Enum.AutomaticSize.None, TextStrokeTransparency = 0.5 })
	TweenService:Create(letter, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 66 }):Play()
	UI.Text(badge, "GRADE", { Font = T.semi, TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None })
	-- details
	local list = UI.Scroll(ctx.stage, { Position = UDim2.fromOffset(104, 6), Size = UDim2.new(1, -110, 1, -12) })
	UI.List(list, 2)
	local order = 0
	local function line(text, color, font, size)
		order += 1
		UI.Line(list, text, { TextColor3 = color or T.text, Font = font or T.semi, TextSize = size or 13, LayoutOrder = order })
	end
	if rec.newBest then
		line(string.format("NEW PERSONAL BEST!   (was %d%%)", Config.QualityPct(rec.prevBest or 0)), T.gold, T.bold, 17)
	elseif rec.first then
		line("FIRST SESSION LOGGED - this is the score to beat.", T.gold, T.bold, 14)
	elseif rec.uncounted then
		line("Too quick to count for your records.", T.orange, T.semi, 13)
	end
	if type(rec.newStats) == "table" and type(rec.bests) == "table" then
		for _, key in ipairs(rec.newStats) do
			local v = rec.bests[key]
			if type(v) == "number" then
				line("NEW BEST: " .. statText(ctx.act.id, key, v), T.gold, T.semi, 13)
			end
		end
	end
	line("COACH:  \"" .. coachRemark(ctx.act.id, grade) .. "\"", T.text, T.semi, 14)
	local summary = table.clone(ctx.lines)
	if ctx.recovery then
		table.insert(summary, string.format("HR settled at %d", math.floor(ctx.hr + 0.5)))
	else
		table.insert(summary, string.format("HR peak %d", math.floor(ctx.hrPeak + 0.5)))
	end
	table.insert(summary, string.format("%d kcal", math.floor(ctx.kcal + 0.5)))
	line(table.concat(summary, DOT), Color3.fromRGB(150, 210, 255), T.semi, 13)
	for _, l in ipairs(resultLines(res)) do
		line(l[1], l[2], T.semi, 13)
	end
	ctx.quit.Text = "CLOSE"
	ctx.quit.BackgroundColor3 = T.panel2
	ctx.bind({ { id = "close", label = "CONTINUE", keys = { K.Space }, color = T.gold } }, 1)
	if ctx.buttons.close then
		ctx.buttons.close.TextColor3 = T.bg
	end
	local closed = false
	local t0 = os.clock()
	ctx.on(function(_, down)
		-- a key still being mashed from the drill (SPACE) mustn't skip the results instantly
		if down and os.clock() - t0 > 0.8 then
			closed = true
		end
	end)
	ctx.cancelled = false
	while not closed and not ctx.cancelled and os.clock() - t0 < 15 do
		RunService.Heartbeat:Wait()
	end
end

------------------------------------------------------------------------
-- Entry points
------------------------------------------------------------------------
local SPAR_INFO = {
	Light = "1 round, 30% power, coach steps in before any knockdown. Low energy, safe.",
	Medium = "2 rounds, 55% power, the coach stops it if someone gets dropped.",
	Hard = "3 rounds, 85% power, knockdowns allowed. Big Ring IQ & chin gains, risk of cuts and bruised ribs.",
}

function Activities.SparPicker()
	if current or State.busy() then
		State.toast("Finish what you're doing first.", T.red)
		return
	end
	local shade, win, body
	local function close()
		State.windows.Spar = nil
		if shade then
			shade:Destroy()
		end
	end
	State.closeAll("Spar")
	shade, win, body = UI.Window(State.gui, "Spar", 520, 420, "SPARRING", { onClose = close })
	State.windows.Spar = close
	local P = State.P
	UI.Line(body, "Live rounds in the sparring ring with headgear on, against a gym partner matched to your level.", { TextColor3 = T.sub, TextSize = 14 })
	for _, name in ipairs({ "Light", "Medium", "Hard" }) do
		local c = UI.Card(body)
		local cost = ({ Light = 25, Medium = 35, Hard = 45 })[name]
		UI.Line(c, name:upper() .. string.format("   (energy %d)", cost), { Font = T.bold, TextColor3 = name == "Hard" and T.red or (name == "Medium" and T.gold or T.green) })
		UI.Line(c, SPAR_INFO[name], { TextSize = 13, TextColor3 = T.sub })
		UI.Button(c, "SPAR " .. name:upper(), { Size = UDim2.new(0, 180, 0, 34), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
			if P and P.condition and P.condition.energy < cost then
				State.toast(string.format("Not enough energy (%d needed). Eat, recover or sleep.", cost), T.red)
				return
			end
			close()
			local r = State.req("StartSparring", name)
			if not r.ok then
				State.toast(r.err or "Can't spar right now", T.red)
			end
		end)
	end
end

function Activities.Start(actId)
	if current then
		State.toast("Finish your current exercise first.", T.red)
		return
	end
	if State.inFight() or State.busy() == "fight" or State.busy() == "spar" then
		return
	end
	local P = State.P
	if not (P and P.created) or P.retired then
		return
	end
	local act = Config.FindById(Config.Activities, actId)
	if not act then
		return
	end
	if act.id == "Sparring" then
		Activities.SparPicker()
		return
	end
	State.closeAll()
	local res = State.req("StartActivity", actId)
	if not res.ok then
		State.toast(res.err or "Can't do that right now", T.red)
		return
	end
	local drill = GAMES[res.minigame]
	if not drill then
		State.req("CancelActivity")
		return
	end
	current = { token = res.token, act = act }
	State.activity = current
	local ctx = newContext({ act = act, level = res.level, params = res.params, station = act.station, baseEffort = BASE_EFFORT[res.minigame] })
	current.ctx = ctx
	local camConn
	if res.pose then
		task.wait(0.15) -- let the server place the character
		camConn = stationCamera(res.pose)
	end
	local ok, perf = pcall(drill, ctx, res)
	ctx.on(nil)
	ctx.intensity = nil
	ctx.resting = false
	if not ok then
		warn("[Activities]", perf)
		perf = nil
	end
	if type(perf) == "number" and perf ~= perf then
		perf = 0
	end
	if type(perf) ~= "number" or ctx.cancelled then
		ctx.mode = "done"
		State.req("CancelActivity")
		State.toast(act.name .. " cancelled - no energy used.", T.sub)
	else
		ctx.mode = "done"
		local quality = 0.5 + math.clamp(perf, 0, 1) * 0.95
		local fin = State.req("FinishActivity", res.token, quality, ctx.out)
		if fin.ok then
			if camConn then
				camConn:Disconnect()
				camConn = nil
				workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			end
			if fin.result and fin.result.injury then
				State.toast("INJURY: " .. fin.result.injury, T.red, 6)
			end
			showResult(ctx, fin, fin.quality or quality)
		else
			State.toast(fin.err or "Session didn't count.", T.red)
		end
	end
	if camConn then
		camConn:Disconnect()
	end
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	ctx.destroy()
	current = nil
	State.activity = nil
end

function Activities.Busy()
	return current ~= nil
end

function Activities.Cancel()
	if current and current.ctx then
		current.ctx.cancelled = true
	end
end

State.open.Activity = function(actId)
	task.spawn(Activities.Start, actId)
end
State.open.Spar = Activities.SparPicker
return Activities
