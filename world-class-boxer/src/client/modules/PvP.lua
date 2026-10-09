-- PvP (client): challenge other players, answer challenges, Find Match, the PvP record.
--   * a "Challenge" prompt (T / Y on a pad, tap on touch) on every other boxer's character in the world
--   * the PvP panel (HUD button PVP / P / D-pad right, and the Career Hub's PvP tab): your PvP record and
--     rating, FIND MATCH (ranked, 3 rounds) and every boxer in the server with SPAR / RANKED buttons
--   * the challenge popup (accept / decline, 20 s; Y / N keys, A / B on a pad, buttons on touch)
--   * the match-found screen and the result screen of a PvP bout
-- Uses UI.lua's public functions read-only; the server (PvP.lua + Main) validates everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local State = require(script.Parent:WaitForChild("State"))

local PvP = {}
PvP.state = { outgoing = nil, queued = false, incoming = nil }
local remote -- ReplicatedStorage.Remotes.PvP
local started = false

local function toast(text, color, dur)
	State.toast(text, color or T.gold, dur)
end

local function modeText(mode, rounds)
	if mode == "ranked" then
		return string.format("RANKED BOUT (%d ROUNDS)", tonumber(rounds) or 3)
	end
	return "SPARRING"
end

local function padLabel(k, fallback)
	local G = UI.Gamepad
	if G and UI.InputMode() == "gamepad" then
		return G.Label(k)
	end
	return fallback
end

-- how to do something on the device in use: the pad's button, the keyboard key, or the touch words
local function howTo(k, key, touchText)
	if UI.InputMode() == "touch" then
		return touchText
	end
	return "press " .. padLabel(k, key)
end

------------------------------------------------------------------------
-- Sending a challenge
------------------------------------------------------------------------
function PvP.Challenge(userId, mode, rounds)
	local r = State.req("PvPChallenge", userId, mode, rounds)
	if r and r.ok then
		PvP.state.outgoing = { id = r.id, userId = userId, mode = mode, until_ = os.clock() + (r.timeout or 20) }
		local target = Players:GetPlayerByUserId(userId)
		toast(string.format("Challenge sent to %s: %s. Waiting for an answer...", target and target.DisplayName or "your opponent", modeText(mode, rounds)), T.gold, 5)
		PvP.Refresh()
	else
		toast((r and r.err) or "Couldn't send the challenge.", T.red)
	end
	return r
end

function PvP.CancelChallenge()
	local r = State.req("PvPCancel")
	PvP.state.outgoing = nil
	PvP.Refresh()
	return r
end

-- the small chooser a challenge prompt opens: SPARRING / RANKED 3 / RANKED 6
local chooser
function PvP.OpenChooser(target)
	if not (target and target.Parent) or State.inFight() then
		return
	end
	if chooser and chooser.Parent then
		chooser:Destroy()
	end
	local shade, win, body
	local function close()
		State.windows.PvPChoose = nil
		if shade then
			shade:Destroy()
		end
	end
	shade, win, body = UI.Window(State.gui, "PvPChoose", 560, 420, "CHALLENGE " .. string.upper(target.DisplayName), { onClose = close, kicker = "PLAYER VS PLAYER", accent = T.red })
	chooser = shade
	State.windows.PvPChoose = close
	local rating = target:GetAttribute("PvPRating")
	UI.Line(body, string.format("@%s  ·  PvP rating %s", target.Name, rating and tostring(rating) or "-"), { TextColor3 = T.sub, TextSize = 14 })
	local function pick(mode, rounds)
		close()
		task.spawn(PvP.Challenge, target.UserId, mode, rounds)
	end
	local spar = UI.Button(body, "SPARRING  -  headgear, no record", { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = T.blue }, function()
		pick("spar")
	end)
	spar.Name = "Spar"
	UI.PadStart(spar)
	local r3 = UI.Button(body, "RANKED BOUT  -  3 ROUNDS", { Name = "Ranked3", Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = T.red }, function()
		pick("ranked", 3)
	end)
	local r6 = UI.Button(body, "RANKED BOUT  -  6 ROUNDS", { Name = "Ranked6", Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = T.red }, function()
		pick("ranked", 6)
	end)
	r3.Name, r6.Name = "Ranked3", "Ranked6"
	UI.Line(body, "Ranked bouts count on your PvP record and rating and pay a small purse. Your career record, camp and injuries are never affected.", { TextColor3 = T.sub, TextSize = 13 })
	return shade
end

------------------------------------------------------------------------
-- Prompts on the other boxers
------------------------------------------------------------------------
local PROMPT = "PvPChallenge"
local function promptAllowed(other)
	local P = State.P
	if not (P and P.created and not P.retired) then
		return false
	end
	if other:GetAttribute("InFight") == true or other:GetAttribute("Busy") ~= nil then
		return false
	end
	return other:GetAttribute("Tier") ~= nil -- has a boxer (publishFame sets Tier once created)
end

local function attachPrompt(other, char)
	local root = char and char:WaitForChild("HumanoidRootPart", 10)
	if not root or root:FindFirstChild(PROMPT) then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = PROMPT
	pp.ActionText = "Challenge"
	pp.ObjectText = other.DisplayName
	pp.KeyboardKeyCode = Enum.KeyCode.T
	pp.GamepadKeyCode = Enum.KeyCode.ButtonY
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Default
	pp.Enabled = promptAllowed(other)
	pp.Parent = root
	pp.Triggered:Connect(function()
		PvP.OpenChooser(other)
	end)
	local function update()
		if pp.Parent then
			pp.Enabled = promptAllowed(other)
		end
	end
	local conns = {
		other:GetAttributeChangedSignal("InFight"):Connect(update),
		other:GetAttributeChangedSignal("Busy"):Connect(update),
		other:GetAttributeChangedSignal("Tier"):Connect(update),
		State.Changed:Connect(update),
	}
	-- the prompt goes with the character (respawn, leaving): so do its listeners
	pp.Destroying:Connect(function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end)
	char.AncestryChanged:Connect(function()
		if not char.Parent then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
		end
	end)
end

local function watchPlayer(other)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(char)
		attachPrompt(other, char)
	end)
	if other.Character then
		task.spawn(attachPrompt, other, other.Character)
	end
end

------------------------------------------------------------------------
-- The challenge popup
------------------------------------------------------------------------
local popup
local function closePopup()
	if popup and popup.Parent then
		popup:Destroy()
	end
	popup = nil
	PvP.state.incoming = nil
end

local function respond(accept)
	local c = PvP.state.incoming
	if not c then
		return
	end
	closePopup()
	local r = State.req("PvPRespond", c.id, accept == true)
	if accept and not (r and r.ok) then
		toast((r and r.err) or "The challenge is gone.", T.red)
	elseif not accept then
		toast("Challenge declined.", T.sub)
	end
end
PvP.Respond = respond

local function showChallenge(msg)
	closePopup()
	PvP.state.incoming = msg
	local shade, win, body
	shade, win, body = UI.Window(State.gui, "PvPChallenge", 600, 400, (msg.fromName or "A boxer") .. " CHALLENGES YOU", {
		kicker = "PLAYER VS PLAYER  ·  " .. modeText(msg.mode, msg.rounds), accent = T.red, footer = 64, z = 40,
		onClose = function()
			respond(false)
		end,
	})
	popup = shade
	UI.Line(body, string.format("@%s  ·  %s", tostring(msg.fromUser or ""), tostring(msg.boxer or "")), { Font = T.semi, TextSize = 16 })
	UI.Line(body, string.format("PvP %s  ·  rating %s  ·  %s", tostring(msg.record or "0-0-0"), tostring(msg.rating or "-"), tostring(msg.rank or "")), { TextColor3 = T.sub, TextSize = 14 })
	UI.Line(body, msg.mode == "ranked" and "A ranked bout counts on your PvP record and rating. Your career is never affected."
		or "Sparring: headgear on, lighter shots, nothing on any record.", { TextColor3 = T.sub, TextSize = 13 })
	local timer = UI.Line(body, "", { Font = T.semi, TextSize = 14, TextColor3 = T.gold })
	timer.Name = "Timer"
	local accept = UI.Button(win, "ACCEPT", { Name = "Accept", Size = UDim2.new(0.5, -30, 0, 48), Position = UDim2.new(0, 20, 1, -60), BackgroundColor3 = T.green }, function()
		respond(true)
	end)
	UI.Button(win, "DECLINE", { Name = "Decline", Size = UDim2.new(0.5, -30, 0, 48), Position = UDim2.new(0.5, 10, 1, -60), BackgroundColor3 = T.panel2 }, function()
		respond(false)
	end)
	UI.PadStart(accept)
	local untilT = os.clock() + (tonumber(msg.timeout) or 20)
	task.spawn(function()
		while popup == shade and shade.Parent do
			local left = math.max(0, math.ceil(untilT - os.clock()))
			timer.Text = UI.InputMode() == "touch" and string.format("%d s to answer", left)
				or string.format("%d s to answer  ·  %s accept  ·  %s decline", left, padLabel(Enum.KeyCode.ButtonA, "Y"), padLabel(Enum.KeyCode.ButtonB, "N"))
			if left <= 0 then
				closePopup()
				break
			end
			task.wait(0.25)
		end
	end)
end

------------------------------------------------------------------------
-- Match found / result
------------------------------------------------------------------------
local matchShade
local function showMatch(msg)
	closePopup()
	State.closeAll()
	if matchShade and matchShade.Parent then
		matchShade:Destroy()
	end
	local shade, win, body = UI.Window(State.gui, "PvPMatch", 720, 420, "MATCH FOUND", { kicker = modeText(msg.mode, msg.rounds), accent = T.gold, z = 45 })
	matchShade = shade
	local me = msg.me or {}
	local row = UI.Row(body, 120)
	local function side(name, user, boxer, rating, record, color)
		local c = UI.Frame(row, { BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, Size = UDim2.new(0.5, -6, 1, 0) })
		UI.Corner(c, UI.R.lg)
		UI.Stroke(c, color, 1.5, 0.3)
		UI.Pad(c, 12)
		UI.List(c, 4)
		UI.Text(c, string.upper(tostring(boxer or name)), { Face = "displayMed", TextSize = 24, TextColor3 = color, Size = UDim2.new(1, 0, 0, 28), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Line(c, user, { TextColor3 = T.sub, TextSize = 14 })
		UI.Line(c, string.format("PvP %s  ·  rating %s", tostring(record or "0-0-0"), tostring(rating or "-")), { TextSize = 14 })
	end
	side(player.DisplayName, "@" .. player.Name .. "  (you)", me.boxer, me.rating, me.record, msg.corner == "red" and T.red or T.blue)
	side(msg.oppName, "@" .. tostring(msg.oppUser or ""), msg.oppBoxer, msg.oppRating, msg.oppRecord, msg.corner == "red" and T.blue or T.red)
	local count = UI.Line(body, "", { Face = "display", TextSize = 34, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center })
	count.Name = "Count"
	local t0 = os.clock()
	local secs = tonumber(msg.seconds) or 4
	task.spawn(function()
		while matchShade == shade and shade.Parent do
			local left = math.ceil(secs - (os.clock() - t0))
			count.Text = left > 0 and string.format("TO THE RING IN %d...", left) or "TO THE RING!"
			if os.clock() - t0 > secs + 1.5 or State.inFight() then
				break
			end
			task.wait(0.2)
		end
		task.delay(0.5, function()
			if matchShade == shade and shade.Parent then
				shade:Destroy()
			end
		end)
	end)
end

local function showResult(msg)
	if matchShade and matchShade.Parent then
		matchShade:Destroy()
	end
	if msg.aborted then
		toast(msg.why or "The bout was called off.", T.red, 5)
		return
	end
	local res = msg.result or {}
	local outcome = res.outcome == "win" and "WIN" or (res.outcome == "loss" and "LOSS" or "DRAW")
	local color = res.outcome == "win" and T.gold or (res.outcome == "loss" and T.red or T.blue)
	local shade
	local function close()
		State.windows.PvPResult = nil
		if shade then
			shade:Destroy()
		end
	end
	local win, body
	shade, win, body = UI.Window(State.gui, "PvPResult", 640, 560, outcome .. "  ·  " .. tostring(res.method or ""), {
		kicker = (msg.ranked and "PVP RANKED BOUT" or "PVP SPARRING") .. "  ·  vs " .. tostring(msg.oppPlayer or ""), accent = color, footer = 64, onClose = close,
	})
	State.windows.PvPResult = close
	UI.Line(body, string.format("%s  (%s)", tostring(msg.opp or "?"), tostring(msg.oppPlayer or "")), { Font = T.semi, TextSize = 16 })
	if res.reason then
		UI.Line(body, tostring(res.reason) .. (res.round and ("  ·  round " .. res.round) or ""), { TextColor3 = T.sub, TextSize = 14 })
	end
	local c = UI.Card(body, { pad = 14 })
	UI.Line(c, string.format("Landed %d / %d  ·  opponent %d / %d", res.landed or 0, res.thrown or 0, res.oppLanded or 0, res.oppThrown or 0), { TextSize = 14 })
	UI.Line(c, string.format("Knockdowns: %d scored, %d taken", res.kdFor or 0, res.kdAgainst or 0), { TextSize = 14 })
	if msg.ranked then
		local v = msg.pvp or {}
		UI.Line(body, string.format("PvP rating %s (%s%s)", tostring(msg.rating or v.rating or "-"), (msg.delta or 0) >= 0 and "+" or "", tostring(msg.delta or 0)),
			{ Font = T.semi, TextSize = 18, TextColor3 = (msg.delta or 0) >= 0 and T.green or T.red })
		UI.Line(body, string.format("PvP record %d-%d-%d (%d KO)  ·  purse %s", v.w or 0, v.l or 0, v.d or 0, v.ko or 0, Config.Money(msg.money or 0)), { TextSize = 14 })
	else
		UI.Line(body, "Sparring: nothing on any record. Good work.", { TextColor3 = T.sub, TextSize = 14 })
	end
	for _, n in ipairs(msg.notes or {}) do
		UI.Line(body, tostring(n), { TextColor3 = T.sub, TextSize = 13 })
	end
	UI.PadStart(UI.Button(win, "CONTINUE", { Name = "Continue", Size = UDim2.new(0, 240, 0, 46), Position = UDim2.new(0.5, -120, 1, -58), BackgroundColor3 = T.gold }, close))
end

------------------------------------------------------------------------
-- The PvP panel (its own window, and the Career Hub's PvP tab)
------------------------------------------------------------------------
local panelShade, panelBody
-- fills `body` (a list container) with the record card, FIND MATCH and the boxers in the server
function PvP.RenderInto(body, isStale)
	local data = State.req("GetPvP")
	if not body.Parent or (isStale and isStale()) then
		return
	end
	if not (data and data.ok) then
		UI.Line(body, (data and data.err) or "PvP is unavailable right now.", { TextColor3 = T.red })
		return
	end
	PvP.state.queued = data.queued == true
	-- after a button: draw this body again (the panel window or the Hub tab)
	local function rerender()
		if body == panelBody then
			PvP.Refresh()
		elseif body.Parent and not (isStale and isStale()) then
			for _, c in ipairs(body:GetChildren()) do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			PvP.RenderInto(body, isStale)
		end
	end
	local me = data.me or {}
	local card = UI.Card(body, { stroke = T.gold })
	card.Name = "PvPRecord"
	UI.Line(card, string.format("PVP RECORD  %d-%d-%d  ·  %d KO", me.w or 0, me.l or 0, me.d or 0, me.ko or 0), { Face = "displayMed", TextSize = 22, Name = "Record" })
	UI.Line(card, string.format("Rating %d (%s)  ·  peak %d  ·  %d ranked bouts  ·  %d spars", me.rating or 1000, tostring(me.rank or ""), me.peak or me.rating or 1000, me.bouts or 0, me.spars or 0),
		{ TextColor3 = T.sub, TextSize = 14, Name = "Rating" })
	local row = UI.Row(body, 48)
	local find = UI.Button(row, PvP.state.queued and "LEAVE QUEUE" or "FIND MATCH  (RANKED, 3 RDS)", { Name = "FindMatch", Size = UDim2.new(0, 320, 1, 0), BackgroundColor3 = PvP.state.queued and T.panel2 or T.gold,
		TextColor3 = PvP.state.queued and T.text or T.ink }, function()
		local r = State.req("PvPQueue", not PvP.state.queued)
		if r and r.ok then
			PvP.state.queued = not PvP.state.queued
			toast(PvP.state.queued and "Looking for an opponent near your rating..." or "Left the queue.", T.gold)
		else
			toast((r and r.err) or "Can't queue right now.", T.red)
		end
		rerender()
	end)
	UI.PadStart(find)
	if PvP.state.outgoing then
		UI.Button(row, "CANCEL CHALLENGE", { Name = "CancelChallenge", Size = UDim2.new(0, 220, 1, 0), BackgroundColor3 = T.panel2 }, function()
			PvP.CancelChallenge()
			rerender()
		end)
	end
	UI.Line(body, PvP.state.queued and string.format("In the queue (%d waiting). The rating gap widens the longer you wait; after 30 s anybody is a match.", data.queueSize or 1)
		or "Find Match pairs you with a boxer near your PvP rating. Or walk up to a boxer and " .. howTo(Enum.KeyCode.ButtonY, "T", "tap the CHALLENGE prompt over him") .. " to challenge him.",
		{ TextColor3 = T.sub, TextSize = 13 })
	UI.Header(body, "Boxers in this server")
	if #(data.players or {}) == 0 then
		UI.Line(body, "Nobody else is here yet.", { TextColor3 = T.sub, TextSize = 14 })
	end
	for i, p in ipairs(data.players or {}) do
		local c = UI.Card(body, { pad = 10, order = 10 + i })
		c.Name = "Player_" .. tostring(p.userId)
		UI.Line(c, string.format("%s  (@%s)  ·  %s", tostring(p.boxer), tostring(p.name), tostring(p.rank or "")), { Font = T.semi, TextSize = 15 })
		UI.Line(c, string.format("Rating %d  ·  PvP %s%s", p.rating or 1000, tostring(p.record or "0-0-0"), p.available and "" or ("  ·  " .. string.upper(tostring(p.why or "busy")))),
			{ TextColor3 = p.available and T.sub or T.orange, TextSize = 13 })
		local btns = UI.Row(c, 40)
		local function btn(name, text, color, mode, rounds)
			local b = UI.Button(btns, text, { Name = name, Size = UDim2.new(0, 150, 1, 0), BackgroundColor3 = p.available and color or T.panel2 }, function()
				if p.available then
					task.spawn(PvP.Challenge, p.userId, mode, rounds)
				else
					toast(tostring(p.displayName) .. " can't fight right now.", T.red)
				end
			end)
			return b
		end
		btn("Spar", "SPAR", T.blue, "spar")
		btn("Ranked3", "RANKED 3", T.red, "ranked", 3)
		btn("Ranked6", "RANKED 6", T.red, "ranked", 6)
	end
end

function PvP.Close()
	State.windows.PvP = nil
	if panelShade then
		panelShade:Destroy()
	end
	panelShade, panelBody = nil, nil
end

function PvP.IsOpen()
	return panelShade ~= nil and panelShade.Parent ~= nil
end

function PvP.Open()
	local P = State.P
	if State.inFight() or not (P and P.created and not P.retired) then
		return
	end
	if PvP.IsOpen() then
		PvP.Refresh()
		return
	end
	State.closeAll("PvP")
	local win
	panelShade, win, panelBody = UI.Window(State.gui, "PvP", 820, 700, "PLAYER VS PLAYER", { onClose = PvP.Close, kicker = "SPARRING  ·  RANKED  ·  FIND MATCH", accent = T.red })
	State.windows.PvP = PvP.Close
	PvP.Refresh()
	-- the list follows the server while the panel is open (who is free, the queue)
	local shade = panelShade
	task.spawn(function()
		while panelShade == shade and shade.Parent do
			task.wait(4)
			if panelShade == shade and shade.Parent and UI.InputMode() ~= "gamepad" then
				PvP.Refresh()
			end
		end
	end)
end

function PvP.Toggle()
	if PvP.IsOpen() then
		PvP.Close()
	else
		PvP.Open()
	end
end

local refreshing = false
function PvP.Refresh()
	if not (panelBody and panelBody.Parent) or refreshing then
		return
	end
	refreshing = true
	local body = panelBody
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local ok, err = pcall(PvP.RenderInto, body)
	if not ok then
		warn("[PvP]", err)
	end
	refreshing = false
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
function PvP.Start()
	if started then
		return
	end
	started = true
	remote = State.Remotes:WaitForChild("PvP", 30)
	if remote then
		remote.OnClientEvent:Connect(function(msg)
			if type(msg) ~= "table" then
				return
			end
			local ok, err = pcall(function()
				if msg.t == "challenge" then
					if State.inFight() then
						return
					end
					showChallenge(msg)
				elseif msg.t == "challengeEnd" then
					if PvP.state.incoming and PvP.state.incoming.id == msg.id then
						closePopup()
					end
					if PvP.state.outgoing and PvP.state.outgoing.id == msg.id then
						PvP.state.outgoing = nil
					end
					local why = { declined = " declined your challenge.", timeout = " didn't answer in time.", cancelled = " cancelled the challenge.", left = " left the server.", unavailable = " can't fight right now." }
					toast(tostring(msg.name or "The other boxer") .. (why[msg.why] or " - challenge over."), msg.why == "declined" and T.red or T.sub, 4)
					PvP.Refresh()
				elseif msg.t == "queue" then
					PvP.state.queued = msg.on == true
					if msg.on == false and msg.why == "matched" then
						toast("Opponent found!", T.green)
					end
					PvP.Refresh()
				elseif msg.t == "match" then
					PvP.state.outgoing = nil
					PvP.state.queued = false
					showMatch(msg)
				elseif msg.t == "matchCancel" then
					if matchShade and matchShade.Parent then
						matchShade:Destroy()
					end
					toast(msg.why or "The match was cancelled.", T.red, 5)
				end
			end)
			if not ok then
				warn("[PvP]", msg.t, err)
			end
		end)
	end
	State.FightRemote.OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.t == "pvpResult" then
			task.delay(0.5, showResult, msg)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	-- keyboard answers to a challenge: Y accepts, N declines (a pad uses the popup's A / B)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not PvP.state.incoming or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Y then
			respond(true)
		elseif input.KeyCode == Enum.KeyCode.N then
			respond(false)
		end
	end)
	State.open.PvP = PvP.Open
end

return PvP
