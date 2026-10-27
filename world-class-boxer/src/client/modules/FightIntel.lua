-- FightIntel: the fight HUD's small reads of the deeper fight (FightClient mounts it in its HUD root and feeds it
-- the server's messages). Display only: FightEngine decides everything.
--   trait  { id, name, hint, counter, reveal? }  one of his ring traits made a difference (Shared.Traits): the
--          corner's call ("He's walking through your hooks! Go to the body!"), with the trait's name when it
--          was hidden until now ("REVEALED: IRON CHIN")
--   intel  { hint, tone = "good" | "warn" }      a one-line call (he bit on the feint, a second wind)
--   mom    { m, d?, cards?, round? }              the momentum (-1..1, the viewer's side positive) every half
--          second it changes; every 2 s in a career bout also the live score: this round's work (d, the
--          viewer's lead in judges' points) and the three cards so far - shown only with the player's Live score
--          setting on (player attribute LiveScore, Settings.liveScore)
-- Pieces: the hint chip (a glass card under the combo counter, gold for a trait, green / orange for a call; it
-- fades after a few seconds and never stacks), the momentum strip (a thin bar centred under the scoreboard, the
-- viewer's gold growing from the centre his way, the opponent's red the other), the live-score chip (right,
-- under the scoreboard).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme

local FightIntel = {}

local HINT_W, HINT_H = 300, 46
local MOM_W, MOM_H = 220, 5
local COMBO_W = 176 -- the combo counter's width (ComboHud): on a phone the hint takes its slot
local root, hint, hintKicker, hintText, momBar, momFill, score, scoreTop, scoreCards
local token = 0
local hintInComboSlot = false -- a phone: the hint sits where the combo counter is and gives way to it
local revealed = {} -- trait id -> its name, for the tale of the tape / the corner (this fight)

local function liveScoreOn()
	return Players.LocalPlayer and Players.LocalPlayer:GetAttribute("LiveScore") == true
end

-- the tutorial's step card is up (BoxerClient.Tutorial: TutorialUI.Root.Prompt): the hint chip would sit under
-- it on a phone, and the card does not chase a chip that comes and goes, so the corner's calls wait
local function stepCardUp()
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local tg = pg and pg:FindFirstChild("TutorialUI")
	local rootF = tg and tg.Enabled and tg:FindFirstChild("Root")
	local card = rootF and rootF:FindFirstChild("Prompt")
	return card ~= nil and card.Visible == true
end

function FightIntel.Mount(hud)
	if root and root.Parent == hud then
		return root
	end
	root = UI.Frame(hud, { Name = "FightIntel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 11 })
	-- the hint chip
	hint = UI.Frame(root, { Name = "Hint", Size = UDim2.fromOffset(HINT_W, HINT_H), Position = UDim2.fromOffset(20, 250), Visible = false, ZIndex = 12 })
	UI.Glass(hint, { transparency = 0.2, stroke = T.gold, strokeT = 0.45 })
	hintKicker = UI.Text(hint, "", { Name = "Kicker", Font = T.semi, TextSize = 11, TextColor3 = T.gold, Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
	hintText = UI.Text(hint, "", { Name = "Text", Face = "displayMed", TextSize = 14, TextColor3 = T.text, Position = UDim2.fromOffset(10, 19),
		Size = UDim2.new(1, -20, 0, 22), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
	-- the momentum strip: a track, the fill grows from the centre (the viewer's way gold, the other way red)
	-- (shown from the first reading of a fight; hidden again by Reset)
	momBar = UI.Frame(root, { Name = "Momentum", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(MOM_W, MOM_H), Position = UDim2.new(0.5, 0, 0, 120),
		BackgroundColor3 = T.ink, BackgroundTransparency = 0.45, ZIndex = 12, Visible = false })
	UI.Corner(momBar, 3)
	momFill = UI.Frame(momBar, { Name = "Fill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = T.gold, ZIndex = 13 })
	UI.Corner(momFill, 3)
	UI.Frame(momBar, { Name = "Mid", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.sub,
		BackgroundTransparency = 0.3, ZIndex = 14 })
	-- the live score chip
	score = UI.Frame(root, { Name = "LiveScore", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(210, 40), Position = UDim2.new(1, -20, 0, 130), Visible = false, ZIndex = 12 })
	UI.Glass(score, { transparency = 0.2, stroke = T.sub, strokeT = 0.6 })
	scoreTop = UI.Text(score, "", { Name = "Round", Font = T.semi, TextSize = 13, TextColor3 = T.text, Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 13 })
	scoreCards = UI.Text(score, "", { Name = "Cards", Font = T.font, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 21), Size = UDim2.new(1, -20, 0, 14),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
	return root
end

-- where the pieces sit: hudTop = the design y under the scoreboard; touch = the touch pads are up (padH = the
-- MOVES / SPRINT row's height); comboH = the combo counter's height (the chip goes under it)
function FightIntel.Layout(hudTop, compact, touch, padH)
	if not root then
		return
	end
	local comboTop = touch and (hudTop + 8 + (tonumber(padH) or 44) + (compact and 6 or 10)) or (hudTop + (compact and 8 or 12))
	hintInComboSlot = compact == true
	if hintInComboSlot then
		-- a phone has no room under the counter (the key strip, the touch pads): the hint takes the counter's
		-- slot while the counter is down
		hint.Position = UDim2.fromOffset(touch and 132 or 20, comboTop)
		hint.Size = UDim2.fromOffset(COMBO_W, HINT_H)
	else
		hint.Position = UDim2.fromOffset(touch and 132 or 20, comboTop + 60 + 8)
		hint.Size = UDim2.fromOffset(HINT_W, HINT_H)
	end
	-- (the strip and its centre tick stay inside the gap under the scoreboard, above where the tutorial's step
	-- card and the hit markers start: hudTop + 2 .. + 7)
	momBar.Position = UDim2.new(0.5, 0, 0, hudTop + 2)
	momBar.Size = UDim2.fromOffset(compact and 160 or MOM_W, MOM_H)
	score.Position = UDim2.new(1, -20, 0, hudTop + (compact and 8 or 12))
	score.Size = UDim2.fromOffset(compact and 180 or 210, 40)
end

-- the combo counter's card (ComboHud, mounted in the same HUD root)
local function comboCard()
	local meter = root and root.Parent and root.Parent:FindFirstChild("ComboMeter")
	return meter and meter:FindFirstChild("Card") or nil
end

local function showHint(kicker, text, color, sec)
	if not hint or stepCardUp() then
		return
	end
	local combo = hintInComboSlot and comboCard() or nil
	if combo and combo.Visible then
		return -- the counter is up in the slot: it wins
	end
	token += 1
	local my = token
	if combo then
		-- the counter coming up takes the slot back
		local conn
		conn = combo:GetPropertyChangedSignal("Visible"):Connect(function()
			if combo.Visible then
				conn:Disconnect()
				if token == my and hint then
					hint.Visible = false
				end
			end
		end)
		task.delay(sec or 4, function()
			conn:Disconnect()
		end)
	end
	hintKicker.Text = kicker
	hintKicker.TextColor3 = color
	hintText.Text = text
	local st = hint:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
	end
	hint.Visible = true
	task.delay(sec or 4, function()
		if token == my and hint then
			hint.Visible = false
		end
	end)
end

-- a server message (FightClient's handlers.trait / intel / mom)
function FightIntel.On(msg)
	if not (root and type(msg) == "table") then
		return
	end
	if msg.t == "trait" then
		local name = type(msg.name) == "string" and msg.name or "?"
		if msg.reveal then
			revealed[msg.id] = name
			showHint("REVEALED: " .. string.upper(name), tostring(msg.hint or ""), T.gold, 5)
		else
			showHint("CORNER: " .. string.upper(name), tostring(msg.hint or ""), T.gold, 3.5)
		end
	elseif msg.t == "intel" then
		local good = msg.tone == "good"
		showHint(good and "CORNER" or "WATCH OUT", tostring(msg.hint or ""), good and T.green or T.orange, 2.5)
	elseif msg.t == "mom" then
		local m = math.clamp(tonumber(msg.m) or 0, -1, 1)
		momBar.Visible = true
		local w = (momBar.AbsoluteSize.X > 0 and momBar.AbsoluteSize.X or MOM_W) / 2
		momFill.BackgroundColor3 = m >= 0 and T.gold or T.red
		momFill.AnchorPoint = Vector2.new(m >= 0 and 0 or 1, 0.5)
		UI.Tween(momFill, { Size = UDim2.new(0, math.floor(math.abs(m) * w + 0.5), 1, 0) }, TweenInfo.new(0.35))
		if msg.cards ~= nil then
			local on = liveScoreOn()
			score.Visible = on
			if on then
				local d = tonumber(msg.d) or 0
				local lead = math.abs(d) < 0.5 and "EVEN" or ((d > 0 and "YOU +" or "HIM +") .. string.format("%.0f", math.abs(d)))
				scoreTop.Text = string.format("ROUND %d  ·  %s", tonumber(msg.round) or 0, lead)
				scoreTop.TextColor3 = math.abs(d) < 0.5 and T.text or (d > 0 and T.gold or T.red)
				local parts = {}
				for _, c in ipairs(type(msg.cards) == "table" and msg.cards or {}) do
					if type(c) == "table" then
						table.insert(parts, string.format("%d-%d", tonumber(c[1]) or 0, tonumber(c[2]) or 0))
					end
				end
				-- (a phone's chip is 180 wide at a 15 px floor: the cards alone, a space apart)
				local compact = score.AbsoluteSize.X > 0 and score.AbsoluteSize.X < 200 * UI.ScaleOf(score)
				scoreCards.Text = compact and table.concat(parts, "   ") or ("CARDS  " .. table.concat(parts, "  ·  "))
			end
		end
	end
end

-- the tale of the tape's scouting line for the opponent (tape.opp.traits from the server: the known ones by name,
-- the hidden ones as "?")
function FightIntel.TapeLine(traits)
	if type(traits) ~= "table" or #traits == 0 then
		return nil
	end
	local names, hidden = {}, 0
	for _, t in ipairs(traits) do
		if type(t) == "table" and t.hidden then
			hidden += 1
		elseif type(t) == "table" and type(t.name) == "string" then
			table.insert(names, t.name .. (type(t.desc) == "string" and (" - " .. t.desc) or ""))
		end
	end
	if hidden > 0 then
		table.insert(names, hidden == 1 and "1 unknown trait" or (hidden .. " unknown traits"))
	end
	return table.concat(names, "  ·  ")
end

-- the bell / the end of the fight: clear the chip (the momentum and the reveals stay for the fight)
function FightIntel.Reset(all)
	token += 1
	if hint then
		hint.Visible = false
	end
	if all then
		table.clear(revealed)
		if momFill then
			momFill.Size = UDim2.new(0, 0, 1, 0)
			momBar.Visible = false
		end
		if score then
			score.Visible = false
		end
	end
end

return FightIntel
