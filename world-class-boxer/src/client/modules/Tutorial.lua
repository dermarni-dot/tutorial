-- Tutorial (client): the guided fights around the real fight HUD (FightClient).
--   OfferDebut()   the "YOUR DEBUT" card a new boxer meets right after the creator (ClientMain, from the summary's
--                  debut.offer): FIGHT MY DEBUT (StartDebut: a real career bout, guided) / SKIP THE GUIDE
--                  (SkipDebut: the career goes on as usual, nothing booked)
--   Offer(after)   the practice round's card (START / SKIP); Begin() asks the server for the practice bout
--                  (StartTutorial; State.open.Tutorial, the Settings screen's PRACTICE ROUND)
--   the step card  during the bout: the step, what to do and the key / button / touch pad for it on the device
--                  in use (Shared.Tutorial.Caps over the player's own control map), placed under the scoreboard
--                  and clear of the touch pads; SKIP TUTORIAL calls the bout off
--   the wrap-up    "YOU'RE READY": then the creator (a new player) or the main menu (a replay)
-- The server runs the bout (Main: runTutorial, FightEngine opts.tutorial) and sends "tutorial" (the step
-- tracker's view) and "tutorialEnd" on the Fight remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Keymap = require(Shared:WaitForChild("Keymap"))
local Steps = require(Shared:WaitForChild("Tutorial"))
local Modules = script.Parent
local State = require(Modules:WaitForChild("State"))
local T = UI.Theme
local Gamepad = UI.Gamepad

local Tutorial = {}
local player = Players.LocalPlayer

local gui, root
local card -- the step card (built per bout)
local card_key = "" -- the HUD pieces' places it was placed for
local view = nil -- the last "tutorial" message
local inBout = false -- a tutorial bout is on the screen
local hidden = false -- the card is down for the rest between rounds / a knockdown / the end
local busy = false -- from Begin until the wrap-up is closed (ClientMain keeps the creator / menu away meanwhile)
local started = false
local conns = {}

local function ensureGui()
	if gui and gui.Parent then
		return
	end
	-- below the top bar like the fight HUD (same coordinates as FightUI), above it and the title screen,
	-- under the toasts
	gui = UI.New("ScreenGui", { Name = "TutorialUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 32,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	root = UI.MountRoot(gui, "Root")
end

local function mode()
	local m = UI.InputMode()
	if m == "keyboard" and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return m
end

local function keymapNow()
	local ok, Settings = pcall(require, Modules:WaitForChild("Settings"))
	if ok and type(Settings) == "table" and type(Settings.Keymap) == "function" then
		local okMap, m = pcall(Settings.Keymap)
		if okMap and type(m) == "table" then
			return m
		end
	end
	return Keymap.Resolve(nil)
end

------------------------------------------------------------------------
-- The step card
------------------------------------------------------------------------
local PAD = 10
local GAP = 6
local CAP_H = 26
local SKIP_W = 104

local function compact()
	return UI.CanvasSize(root).Y < 600
end

-- the size a label really draws at under this root (UI's readability floor)
local function eff(size)
	return math.max(size, UI.TextFloor(UI.ScaleOf(root)))
end

local function sizes()
	local small = compact()
	return { kicker = 12, title = small and 20 or 24, body = small and 13 or 15, cap = 13, caption = 12 }
end

-- the caps (or, for the stamina step, the goal chips) of the current step, measured: { key, label, w, done }
local function capList(step)
	local out = {}
	local sz = sizes()
	local goals = view and view.goals or {}
	if #step.actions == 0 then
		for _, g in ipairs(step.goals) do
			local text = Steps.GoalText[g] or g
			table.insert(out, { label = string.upper(text), w = math.ceil(UI.TextWidth(string.upper(text), eff(sz.caption), T.semi) * 1.15) + 20, done = goals[g] == true, chip = true })
		end
		return out
	end
	for _, c in ipairs(Steps.Caps(step, mode(), keymapNow(), Keymap, Gamepad)) do
		local done = (c.action == "leadhook" or c.action == "rearhook") and goals.hook or (c.action == "uppercut" and step.id == "power" and goals.uppercut)
		-- (bold capitals run wide: a little slack so no caption is cut on a device whose metrics differ)
		local kw = math.ceil(UI.TextWidth(c.key, eff(sz.cap), T.semi) * 1.1) + 14
		local lw = math.ceil(UI.TextWidth(c.label, eff(sz.caption), T.semi) * 1.15) + 4
		table.insert(out, { key = c.key, label = c.label, kw = kw, w = kw + 6 + lw, done = done == true })
	end
	return out
end

-- caps into rows of `inner` width: { rows, height }
local function packCaps(list, inner)
	local rows, row, used = {}, {}, 0
	for _, c in ipairs(list) do
		local w = math.min(c.w, inner)
		if #row > 0 and used + 10 + w > inner then
			table.insert(rows, row)
			row, used = {}, 0
		end
		table.insert(row, c)
		used += (#row > 1 and 10 or 0) + w
	end
	if #row > 0 then
		table.insert(rows, row)
	end
	return rows, #rows * CAP_H + math.max(0, #rows - 1) * 4
end

local function lines(text, size, width)
	local w = UI.TextWidth(text, size, T.font)
	return math.max(1, math.ceil(w * 1.05 / math.max(40, width)))
end

-- the card's height at width w (design px), from the same measures the build uses (tight: no body text,
-- for a short screen with the key strip up)
local function estimate(step, w, tight)
	local sz = sizes()
	local inner = w - 2 * PAD
	local headH = math.max(eff(sz.kicker) + 2 + eff(sz.title) + 4, math.max(30, UI.MinHit(root)))
	local bodyH = tight and 0 or (GAP + lines(step.text, eff(sz.body), inner) * math.ceil(eff(sz.body) * 1.25))
	local _, capsH = packCaps(capList(step), inner)
	return PAD * 2 + headH + bodyH + (capsH > 0 and (GAP + capsH) or 0)
end

-- the fight HUD's pieces the card keeps clear of, as design-px rects in this root's space
-- (a dotted name is a piece inside another: FightIntel's live-score chip. Its momentum strip sits in the gap
-- right under the scoreboard, above where the card starts; its hint chip waits while the card is up)
local OBSTACLES = { "Scoreboard", "TouchPad", "DefencePad", "MovesPad", "SprintPad", "StanceChips", "Controls", "Ticker", "ComboMeter", "FightIntel.LiveScore" }
local function rectOf(obj, s, origin)
	local p, z = obj.AbsolutePosition, obj.AbsoluteSize
	return { x0 = (p.X - origin.X) / s, y0 = (p.Y - origin.Y) / s, x1 = (p.X + z.X - origin.X) / s, y1 = (p.Y + z.Y - origin.Y) / s }
end
local function shown(obj)
	local o = obj
	while o and o:IsA("GuiObject") do
		if not o.Visible then
			return false
		end
		o = o.Parent
	end
	return true
end
local function obstacles()
	local out, board = {}, nil
	local fg = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("FightUI")
	local hud = fg and fg:FindFirstChild("HUDRoot")
	if not (hud and fg.Enabled) then
		return out, nil
	end
	local s = UI.ScaleOf(root)
	local origin = root.AbsolutePosition
	for _, name in ipairs(OBSTACLES) do
		local o = hud
		for part in name:gmatch("[^.]+") do
			o = o and o:FindFirstChild(part)
		end
		if o and o:IsA("GuiObject") and shown(o) then
			-- the piece and what it draws (a pad cluster's buttons reach past its own frame)
			local r
			for _, d in ipairs({ o, table.unpack(o:GetDescendants()) }) do
				if d:IsA("GuiObject") and d.AbsoluteSize.X > 1 and d.AbsoluteSize.Y > 1 and shown(d)
					and (d == o or d.BackgroundTransparency < 0.99 or d:IsA("GuiButton") or d:IsA("TextLabel")) then
					local q = rectOf(d, s, origin)
					if r then
						r.x0, r.y0, r.x1, r.y1 = math.min(r.x0, q.x0), math.min(r.y0, q.y0), math.max(r.x1, q.x1), math.max(r.y1, q.y1)
					else
						r = q
					end
				end
			end
			if r and r.x1 - r.x0 > 1 and r.y1 - r.y0 > 1 then
				r.name = name
				table.insert(out, r)
				if name == "Scoreboard" then
					board = r
				end
			end
		end
	end
	return out, board
end

local function overlaps(a, b, m)
	return a.x0 < b.x1 + m and b.x0 < a.x1 + m and a.y0 < b.y1 + m and b.y0 < a.y1 + m
end

-- where the card goes: under the scoreboard, as wide as fits, clear of every HUD piece and on the screen.
-- Returns x, y, w, h (design px) and tight (no room for the body text: only the title and the keys)
local function place(step, tight)
	local canvas = UI.CanvasSize(root)
	local cw, ch = canvas.X, canvas.Y
	local obs, board = obstacles()
	local margin = 12
	local top0 = (board and board.y1 or 52) + 8
	local small = compact()
	local widths = small and { 480, 420, 360, 320, 280 } or { 620, 540, 460, 400, 340 }
	local ys = { top0 }
	for _, o in ipairs(obs) do
		if o.y1 + 8 > top0 then
			table.insert(ys, o.y1 + 8)
		end
	end
	table.sort(ys)
	for _, w in ipairs(widths) do
		if w <= cw - 2 * margin then
			local h = estimate(step, w, tight)
			for _, y in ipairs(ys) do
				-- the room left and right of the pieces beside this band
				local L, R = margin, cw - margin
				for _, o in ipairs(obs) do
					if o.y0 < y + h and o.y1 > y then
						if (o.x0 + o.x1) / 2 < cw / 2 then
							L = math.max(L, o.x1 + 8)
						else
							R = math.min(R, o.x0 - 8)
						end
					end
				end
				for _, x in ipairs({ cw / 2 - w / 2, (L + R) / 2 - w / 2, L }) do
					local r = { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
					local ok = r.x0 >= margin - 0.5 and r.x1 <= cw - margin + 0.5 and r.y1 <= ch - margin
					if ok then
						for _, o in ipairs(obs) do
							if overlaps(r, o, 2) then
								ok = false
								break
							end
						end
					end
					if ok then
						return x, y, w, h
					end
				end
			end
		end
	end
	return nil
end
function Tutorial.Place(step)
	for _, tight in ipairs({ false, true }) do
		local x, y, w, h = place(step, tight)
		if x then
			return x, y, w, h, tight
		end
	end
	local canvas = UI.CanvasSize(root)
	local _, board = obstacles()
	local w = math.min(340, canvas.X - 24)
	return canvas.X / 2 - w / 2, (board and board.y1 or 52) + 8, w, estimate(step, w, true), true
end

-- the HUD pieces' places, rounded (the card is placed again when they move: the key strip shown / hidden)
local function obstacleKey()
	local parts = {}
	for _, o in ipairs((obstacles())) do
		table.insert(parts, string.format("%s%d,%d,%d,%d", o.name, o.x0 // 4, o.y0 // 4, o.x1 // 4, o.y1 // 4))
	end
	return table.concat(parts, ";")
end

local function skipBout()
	-- (the debut: the guide stops, the fight goes on; the practice round: the bout is called off)
	State.FightRemote:FireServer({ t = "tutorialSkip" })
	if card then
		card.Visible = false
	end
end

local function buildCard()
	if not (inBout and view) then
		return
	end
	ensureGui()
	if card then
		card:Destroy()
		card = nil
	end
	local step = Steps.StepOf(view)
	local debut = view.debut == true
	local skipText = debut and "SKIP GUIDE" or "SKIP TUTORIAL"
	local sz = sizes()
	local x, y, w, _, tight = Tutorial.Place(step)
	card_key = obstacleKey()
	local inner = w - 2 * PAD
	card = UI.Frame(root, { Name = "Prompt", Position = UDim2.fromOffset(math.floor(x), math.floor(y)), Size = UDim2.fromOffset(w, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Visible = not hidden })
	UI.Glass(card, { transparency = 0.12, stroke = T.gold, strokeT = 0.55 })
	UI.New("UIPadding", { PaddingTop = UDim.new(0, PAD), PaddingBottom = UDim.new(0, PAD), PaddingLeft = UDim.new(0, PAD), PaddingRight = UDim.new(0, PAD), Parent = card })
	UI.List(card, GAP)
	-- head: the step and its title on the left, SKIP TUTORIAL on the right
	local hit = math.max(30, UI.MinHit(root))
	local headH = math.max(eff(sz.kicker) + 2 + eff(sz.title) + 4, hit)
	local head = UI.Frame(card, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headH), LayoutOrder = 1 })
	local skipW = math.max(SKIP_W, UI.TextWidth(skipText, eff(12), T.semi) + 16)
	-- the coach's whistle (a tick once it is done) before the step line
	local ks = eff(sz.kicker) + 2
	UI.Icon(head, view.done and "check" or "whistle", ks, view.done and T.green or T.gold, { Name = "StepIcon" })
	UI.Text(head, string.format("%s  ·  STEP %d OF %d", debut and "YOUR DEBUT" or "TUTORIAL", view.step, view.total or #Steps.STEPS), { Name = "Step", Font = T.semi, TextSize = sz.kicker, TextColor3 = T.gold,
		Position = UDim2.fromOffset(ks + 6, 0), Size = UDim2.new(1, -(skipW + 14 + ks), 0, ks), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UI.Title(head, view.done and "NICE WORK!" or step.title, { Name = "Title", TextSize = sz.title, Position = UDim2.fromOffset(0, eff(sz.kicker) + 2),
		Size = UDim2.new(1, -(skipW + 8), 0, eff(sz.title) + 4), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
	local skip = UI.Button(head, skipText, { Name = "Skip", Font = T.semi, TextSize = 12, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(skipW, hit), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.2 }, skipBout)
	skip.Selectable = false -- (a pad's buttons are the fight's: the pad skips at the offer)
	-- what to do (a short screen with the key strip up keeps the title and the keys)
	if not tight or view.done then
		UI.Text(card, view.done and (debut and "That's the guide done. Now win your debut." or "That's the tutorial. You're ready for a real fight.") or step.text, { Name = "Body", TextSize = sz.body, TextColor3 = T.text, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	end
	-- the keys (or the stamina step's checklist)
	local list = view.done and {} or capList(step)
	if #list > 0 then
		local rows, capsH = packCaps(list, inner)
		local keys = UI.Frame(card, { Name = "Keys", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, capsH), LayoutOrder = 3 })
		for r, row in ipairs(rows) do
			local cx = 0
			for _, c in ipairs(row) do
				local cy = (r - 1) * (CAP_H + 4)
				local wc = math.min(c.w, inner)
				local item = UI.Frame(keys, { Name = "Cap", BackgroundTransparency = 1, Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(wc, CAP_H) })
				if c.chip then
					item.BackgroundTransparency = 0
					item.BackgroundColor3 = c.done and T.green or T.panel2
					UI.Corner(item, UI.R.md)
					UI.Text(item, c.label, { Font = T.semi, TextSize = sz.caption, TextColor3 = c.done and T.ink or T.text, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
						TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
				else
					local kw = math.min(c.kw, wc)
					local key = UI.Frame(item, { Name = "Key", Size = UDim2.fromOffset(kw, CAP_H - 2), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = c.done and T.green or T.panel2 })
					UI.Corner(key, 4)
					UI.Stroke(key, c.done and T.green or T.gold, 1, 0.35)
					UI.Text(key, c.key, { Font = T.semi, TextSize = sz.cap, TextColor3 = c.done and T.ink or T.white, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
						TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
					UI.Text(item, c.label, { Font = T.semi, TextSize = sz.caption, TextColor3 = c.done and T.green or T.sub, Position = UDim2.fromOffset(kw + 6, 0),
						Size = UDim2.new(1, -(kw + 6), 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
				end
				cx += wc + 10
			end
		end
	end
end

local function setHidden(on)
	hidden = on
	if card then
		card.Visible = not on
	end
end

local function onFight(msg)
	if type(msg) ~= "table" then
		return
	end
	local t = msg.t
	if t == "start" then
		inBout = type(msg.tutorial) == "table"
		view = nil
		hidden = false
		if card then
			card:Destroy()
			card = nil
		end
	elseif t == "debutEnd" then
		inBout = false
		Tutorial.DebutEnded(msg)
		return
	elseif not inBout then
		if t == "tutorialEnd" then
			Tutorial.Ended(msg)
		end
		return
	elseif t == "tutorial" then
		local stepChanged = view ~= nil and (view.step ~= msg.step or view.done ~= msg.done)
		view = msg
		buildCard()
		if stepChanged and card then
			-- a step done: the card flashes green as the next one comes up
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color, stroke.Transparency = T.green, 0
				UI.Tween(stroke, { Color = T.gold, Transparency = 0.55 }, TweenInfo.new(0.8))
			end
		end
		if msg.done then
			task.delay(2.5, function()
				if view == msg then
					setHidden(true)
				end
			end)
		end
	elseif t == "final" or t == "result" or t == "aborted" then
		-- (the debut is a career bout: it ends like one, the result screen is ClientMain's; a practice round's
		-- "final" just hides the card, its tutorialEnd wraps up)
		if view and view.debut then
			inBout = false
			view = nil
			if card then
				card:Destroy()
				card = nil
			end
			busy = false
		elseif t == "final" then
			setHidden(true)
		end
	elseif t == "bell" or t == "kd" then
		setHidden(true)
	elseif t == "countdown" then
		if (tonumber(msg.n) or 0) <= 0 and not (view and view.done) then
			setHidden(false)
			buildCard() -- (the HUD may have moved between rounds)
		end
	elseif t == "getup" then
		if not (view and view.done) then
			setHidden(false)
		end
	elseif t == "tutorialEnd" then
		inBout = false
		Tutorial.Ended(msg)
	end
end

------------------------------------------------------------------------
-- The offer, the start, the wrap-up
------------------------------------------------------------------------
local function closeWindow(name)
	local w = root and root:FindFirstChild(name)
	if w then
		w:Destroy()
	end
end

local afterOffer -- what follows the offer when it is skipped (the title screen)

-- what follows the tutorial: a new player creates his boxer, a replay goes back to the menu
local function goOn(created)
	busy = false
	if created then
		if State.open.Menu then
			State.open.Menu()
		end
	elseif State.open.Creator then
		State.open.Creator()
	end
end

local starting = false
function Tutorial.Begin()
	if starting or inBout or (root and root:FindFirstChild("TutorialDone")) then
		return false
	end
	starting, busy = true, true
	closeWindow("TutorialOffer")
	local r = State.req("StartTutorial")
	starting = false
	if not (type(r) == "table" and r.ok) then
		busy = false
		State.toast((type(r) == "table" and r.err) or "Couldn't start the tutorial right now.", T.red)
		local P = State.P
		if not (P and P.created) and afterOffer then
			afterOffer()
		end
		return false
	end
	return true
end

function Tutorial.Skip()
	closeWindow("TutorialOffer")
	busy = false
	task.spawn(State.req, "SkipTutorial")
	State.toast("Tutorial skipped. You can replay it any time from Settings.", T.gold, 5)
	if afterOffer then
		afterOffer()
	end
end

-- the card a new player meets first: after = what SKIP leads to (the title screen)
function Tutorial.Offer(after)
	ensureGui()
	afterOffer = after
	busy = true
	local shade, win, body = UI.Window(root, "TutorialOffer", 620, 430, "YOUR FIRST FIGHT", { kicker = "TUTORIAL", footer = 64 })
	local _ = shade
	UI.Text(body, "Learn the ropes in a short practice fight before you create your own boxer.", { TextSize = 17, Font = T.semi, LayoutOrder = 1 })
	UI.Text(body, "You box as a random fighter against a random opponent, one step at a time: moving, the jab and the cross, hooks, uppercuts and body shots, combinations, blocking, slipping and weaving, counters, stamina and a special move.",
		{ TextSize = 14, TextColor3 = T.sub, LayoutOrder = 2 })
	UI.Text(body, "It is only practice: nothing carries over to your career.", { TextSize = 14, TextColor3 = T.sub, LayoutOrder = 3 })
	local bh = math.max(44, UI.MinHit(win))
	local start = UI.Button(win, "START TUTORIAL", { Name = "Start", Size = UDim2.new(0.5, -24, 0, bh), Position = UDim2.new(0, 16, 1, -(10 + bh)), BackgroundColor3 = T.gold, TextColor3 = T.ink },
		function()
			Tutorial.Begin()
		end)
	UI.PadStart(start)
	UI.Button(win, "SKIP TUTORIAL", { Name = "SkipTutorial", Size = UDim2.new(0.5, -24, 0, bh), Position = UDim2.new(0.5, 8, 1, -(10 + bh)) }, Tutorial.Skip)
	return win
end

-- the bout is over (msg = the server's tutorialEnd)
function Tutorial.Ended(msg)
	inBout = false
	view = nil
	if card then
		card:Destroy()
		card = nil
	end
	local created = msg.created == true
	if msg.how ~= "completed" then
		if msg.how == "skipped" then
			State.toast("Tutorial skipped. You can replay it any time from Settings.", T.gold, 5)
		else
			State.toast("The tutorial was called off.", T.red, 5)
		end
		task.delay(0.6, goOn, created)
		return
	end
	busy = true
	ensureGui()
	task.wait(0.4)
	local _, win, body = UI.Window(root, "TutorialDone", 600, 440, "YOU'RE READY", { kicker = "TUTORIAL COMPLETE", footer = 64 })
	UI.Text(body, created and "That was a practice bout. Your career, record and money are exactly as you left them."
		or "You've got the basics. Now create your boxer: your own name, look and fighting style.", { TextSize = 17, Font = T.semi, LayoutOrder = 1 })
	if type(msg.you) == "string" and type(msg.opp) == "string" then
		UI.Text(body, string.format("You fought as %s against %s%s.", msg.you, msg.opp, type(msg.venue) == "string" and (" at the " .. msg.venue) or ""), { TextSize = 14, TextColor3 = T.sub, LayoutOrder = 2 })
	end
	local res = type(msg.result) == "table" and msg.result or nil
	if res then
		UI.Text(body, string.format("Punches landed: %d of %d  ·  Knockdowns: %d", tonumber(res.landed) or 0, tonumber(res.thrown) or 0, tonumber(res.kdFor) or 0),
			{ TextSize = 14, TextColor3 = T.sub, LayoutOrder = 3 })
	end
	UI.Text(body, "Every move, key and button is in Moves & Controls (the main menu's CONTROLS).", { TextSize = 14, TextColor3 = T.sub, LayoutOrder = 4 })
	local bh = math.max(44, UI.MinHit(win))
	local go = UI.Button(win, created and "BACK TO THE MENU" or "CREATE YOUR BOXER", { Name = "Continue", Size = UDim2.new(0, 280, 0, bh), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10), BackgroundColor3 = T.gold, TextColor3 = T.ink }, function()
		closeWindow("TutorialDone")
		goOn(created)
	end)
	UI.PadStart(go)
end

------------------------------------------------------------------------
-- The debut (a new boxer's first career fight, guided)
------------------------------------------------------------------------
local debutStarting = false
function Tutorial.BeginDebut()
	if debutStarting or inBout then
		return false
	end
	debutStarting, busy = true, true
	local r = State.req("StartDebut")
	debutStarting = false
	if not (type(r) == "table" and r.ok) then
		-- refused (the character isn't ready after a reset, a server hiccup): the offer stays up to try again
		local open = root and root:FindFirstChild("DebutOffer") ~= nil
		busy = open
		State.toast((type(r) == "table" and r.err) or "Couldn't start your debut right now.", T.red)
		return false
	end
	-- (only once the server has taken it: a refusal must not lose the offer for the session)
	closeWindow("DebutOffer")
	return true
end

function Tutorial.SkipDebut()
	closeWindow("DebutOffer")
	busy = false
	task.spawn(State.req, "SkipDebut")
	State.toast("No guide, then. Book your first fight at the FIGHT BOARD (or press H) when you're ready.", T.gold, 6)
end

-- the card a new boxer meets right after the creator (info = the summary's debut table)
function Tutorial.OfferDebut(info)
	ensureGui()
	closeWindow("DebutOffer")
	busy = true
	info = type(info) == "table" and info or {}
	local _, win, body = UI.Window(root, "DebutOffer", 640, 470, "YOUR DEBUT", { kicker = "AMATEUR BOUT  ·  TONIGHT", footer = 64 })
	UI.Text(body, "Your first fight is tonight: a " .. tostring(info.rounds or 3) .. "-round amateur bout against a fellow novice from your division, at the "
		.. tostring(info.venue or "Community Center") .. ".", { Name = "Lead", TextSize = 17, Font = T.semi, LayoutOrder = 1 })
	local vb = UI.LocationBadge(body, info.venue or "Community Center", 30, { Name = "VenueBadge", order = 1 })
	if vb then
		vb.LayoutOrder = 1
	end
	UI.Text(body, "Your coach talks you through it step by step: moving, the jab and the cross, hooks, uppercuts and body shots, combinations, blocking, slipping and weaving, counters and stamina. The clock waits while you learn each one.",
		{ TextSize = 14, TextColor3 = T.sub, LayoutOrder = 2 })
	UI.Text(body, "It's a real fight: the result goes on your record and pays a purse. Gentler rules for this one night: his punches hurt half as much and you can't be stopped before the last round. The win is still yours to earn.",
		{ TextSize = 14, TextColor3 = T.sub, LayoutOrder = 3 })
	local bh = math.max(44, UI.MinHit(win))
	local start = UI.Button(win, "FIGHT MY DEBUT", { Name = "StartDebut", Size = UDim2.new(0.5, -24, 0, bh), Position = UDim2.new(0, 16, 1, -(10 + bh)), BackgroundColor3 = T.gold, TextColor3 = T.ink },
		function()
			Tutorial.BeginDebut()
		end)
	UI.PadStart(start)
	UI.Button(win, "SKIP THE GUIDE", { Name = "SkipDebut", Size = UDim2.new(0.5, -24, 0, bh), Position = UDim2.new(0.5, 8, 1, -(10 + bh)) }, Tutorial.SkipDebut)
	return win
end

-- the debut was called off (left the ring, a reset, a crash): it is still on offer (msg.how)
function Tutorial.DebutEnded(msg)
	view = nil
	if card then
		card:Destroy()
		card = nil
	end
	busy = false
	if type(msg) == "table" and msg.how ~= "completed" then
		State.toast("Your debut was called off: nothing went on your record. It's still waiting for you.", T.gold, 6)
		local P = State.P
		if msg.offer ~= false and not (P and P.retired) then
			task.delay(1.2, function()
				if not inBout and not busy then
					Tutorial.OfferDebut(msg.info)
				end
			end)
		end
	end
end

-- a tutorial offer, bout or wrap-up is up (ClientMain keeps the title screen / the creator away meanwhile)
function Tutorial.Busy()
	return busy or inBout
end

function Tutorial.Start()
	if started then
		return
	end
	started = true
	ensureGui()
	table.insert(conns, State.FightRemote.OnClientEvent:Connect(onFight))
	-- a new screen size (rotation, the UI scale setting) or another device: the card is rebuilt in place
	table.insert(conns, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if card then
			task.defer(buildCard)
		end
	end))
	if Gamepad and Gamepad.Changed then
		table.insert(conns, Gamepad.Changed:Connect(function()
			if card then
				task.defer(buildCard)
			end
		end))
	end
	State.open.Tutorial = Tutorial.Begin
	State.open.Debut = Tutorial.OfferDebut
	-- the HUD moved under the card (the key strip comes and goes, the pads page): place it again
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(0.5)
			if inBout and card and not hidden and obstacleKey() ~= card_key then
				buildCard()
			end
		end
	end)
end

return Tutorial
