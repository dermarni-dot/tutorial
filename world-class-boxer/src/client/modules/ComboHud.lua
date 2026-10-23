-- ComboHud: the fight HUD's combo counter (FightClient mounts it in its HUD root and feeds it the server's
-- messages). Display only: the server (FightEngine + Shared.Combos) decides what chains, what lands and what
-- is called out.
--   combo      { who, hits, n, name?, sig? }  a punch of a running combination has its result; name = a named
--              combo that just landed (sig = a signature combo)
--   comboEnd   { who, hits, n, name? }        the combination is over
--   comboBroken { who }                       his guard smothered it (the second blocked punch)
-- The counter is the viewer's: a glass chip under the left of the scoreboard (desktop / console), or right of the
-- defence pads on a touch screen (clear of BLOCK / CLINCH, MOVES / SPRINT and the punch cluster). The other man's
-- named combos show on its second line in his corner colour. The frame (ComboMeter) keeps its place when idle
-- (transparent), so the tutorial's step card can keep clear of it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme

local ComboHud = {}

local W, H = 176, 60
local root, card, count, hitsWord, callout, icon, bar
local token = 0
local state = { hits = 0, shownAt = 0 }

local function setShown(on)
	if not card then
		return
	end
	card.Visible = on
end

-- mount in the HUD root (once per HUD)
function ComboHud.Mount(hud)
	if root and root.Parent == hud then
		return root
	end
	root = UI.Frame(hud, { Name = "ComboMeter", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H), Position = UDim2.fromOffset(20, 170), ZIndex = 12 })
	card = UI.Frame(root, { Name = "Card", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 12 })
	UI.Glass(card, { transparency = 0.15, stroke = T.gold, strokeT = 0.5 })
	icon = UI.Icon(card, "fist", 26, T.gold, { Name = "ComboIcon", Position = UDim2.fromOffset(10, 8), ZIndex = 13 })
	count = UI.Text(card, "0", { Name = "Count", Face = "number", TextSize = 30, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(42, 2),
		Size = UDim2.fromOffset(44, 34), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 13 })
	hitsWord = UI.Text(card, "HIT COMBO", { Name = "Hits", Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(88, 12),
		Size = UDim2.new(1, -94, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
	callout = UI.Text(card, "", { Name = "Callout", Face = "displayMed", TextSize = 15, TextColor3 = T.gold, Position = UDim2.fromOffset(10, 36),
		Size = UDim2.new(1, -20, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 })
	bar = UI.Frame(card, { Name = "Window", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -3), Size = UDim2.new(1, -16, 0, 2), BackgroundColor3 = T.gold, ZIndex = 13 })
	return root
end

-- where it sits: hudTop = the design y under the scoreboard; touch = the touch pads are up (padH = the MOVES /
-- SPRINT row's height, a fingertip: it grows on a small screen)
function ComboHud.Layout(hudTop, compact, touch, padH)
	if not root then
		return
	end
	if touch then
		-- right of the defence pads (BLOCK / CLINCH at x 14..124), under the MOVES / SPRINT row
		root.Position = UDim2.fromOffset(132, hudTop + 8 + (tonumber(padH) or 44) + (compact and 6 or 10))
	else
		root.Position = UDim2.fromOffset(20, hudTop + (compact and 8 or 12))
	end
end

-- fade out a beat after the last update
local function linger(sec)
	token += 1
	local my = token
	if bar then
		bar.Size = UDim2.new(1, -16, 0, 2)
		UI.Tween(bar, { Size = UDim2.new(0, 0, 0, 2) }, TweenInfo.new(sec, Enum.EasingStyle.Linear))
	end
	task.delay(sec, function()
		if token == my then
			setShown(false)
			state.hits = 0
			callout.Text = ""
		end
	end)
end

local function pop()
	if not count then
		return
	end
	local sc = count:FindFirstChildOfClass("UIScale") or UI.New("UIScale", { Parent = count })
	sc.Scale = 1.35
	UI.Tween(sc, { Scale = 1 }, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

-- a server message (FightClient's handlers.combo / comboEnd / comboBroken)
function ComboHud.On(msg)
	if not (card and type(msg) == "table") then
		return
	end
	local mine = msg.who == "you"
	if msg.t == "comboBroken" then
		if mine then
			setShown(true)
			callout.Text = "SMOTHERED"
			callout.TextColor3 = T.red
			linger(1.0)
		end
		return
	end
	if not mine then
		-- the other man's named combos (his corner colour), under our own count
		if type(msg.name) == "string" and msg.t == "combo" then
			setShown(true)
			if state.hits < 2 then
				count.Text = "-"
				hitsWord.Text = "OPPONENT"
			end
			callout.Text = "OPP  " .. msg.name
			callout.TextColor3 = T.blue
			linger(1.4)
		end
		return
	end
	local hits = math.max(0, math.floor(tonumber(msg.hits) or 0))
	if msg.t == "comboEnd" then
		if hits >= 2 then
			count.Text = tostring(hits)
			hitsWord.Text = hits >= 2 and "HIT COMBO" or "HIT"
			linger(0.9)
		else
			linger(0.3)
		end
		return
	end
	-- a running combination: shown from the second punch landed (or a named one)
	if hits < 2 and type(msg.name) ~= "string" then
		return
	end
	setShown(true)
	if hits ~= state.hits then
		pop()
	end
	state.hits = hits
	count.Text = tostring(hits)
	hitsWord.Text = "HIT COMBO"
	if type(msg.name) == "string" then
		callout.Text = msg.name
		callout.TextColor3 = msg.sig and T.orange or T.gold
		if card:FindFirstChildOfClass("UIStroke") then
			local st = card:FindFirstChildOfClass("UIStroke")
			st.Color, st.Transparency = msg.sig and T.orange or T.gold, 0
			UI.Tween(st, { Transparency = 0.5 }, TweenInfo.new(0.6))
		end
	end
	linger(1.6)
end

-- the round is over / the fight ended: clear it
function ComboHud.Reset()
	token += 1
	state.hits = 0
	if callout then
		callout.Text = ""
	end
	setShown(false)
end

return ComboHud
