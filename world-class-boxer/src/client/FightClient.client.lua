-- FightClient: fight-night presentation and controls (also used for gym sparring).
-- TV broadcast overlay, weigh-in + tale of the tape, ring walks with music, live commentary
-- ticker, defense call-outs, corner advice between rounds. HUD with separate HEAD / BODY / STAMINA
-- bars (permanent-damage caps + trailing "ghost" chips, tier colours) and status chips (ROCKED /
-- DAZED / IN DANGER / OUT ON HIS FEET). Cinematic screen FX scaled by Config.ScreenFX: concussion
-- blur + colour drain, vignette / tunnel vision, red hit flash, FOV kick and roll, drunk camera,
-- muffled audio (SoundService.FightMix), heartbeat, sweat and blood spray, letterbox, broadcast
-- cuts. Knockdowns: skill-based get-up (timing marker + mashing), mandatory eight count, referee
-- check, out-cold ragdoll. Venue dressing / lighting / crowd come from VenueFX (stream G) when it is
-- present; the old built-in venue effects stay as a fallback so a fight always presents.
-- Controls come from the control map (Shared.Keymap: the defaults, and the player's custom map through
-- Settings.Keymap()). Keyboard defaults: left click jab, right click cross, F lead hook, R rear hook, T
-- uppercut, G body hook, middle click overhand, C = to the body, B block, V parry, Q / E slip, Space dodge,
-- Shift + Space quick dodge, double-tap A / D pivot, Ctrl clinch, Q + click counter jab, E + right click
-- counter cross, 1-9 the special moves, H the controls strip, Tab (or `) the Moves & Controls menu (the
-- fight hides Roblox's player list, which owns Tab), Shift sprints (in the ring: the server's quicker
-- footwork). Block, body and the controls legend are TAP TOGGLES on every device (tap: on, tap again:
-- off); a press held longer than Tog.HOLD still works as a hold (released when you let go). A punch drops
-- a tapped guard (as the server does) and spends a tapped body modifier. The menu pauses a solo fight.
-- Gamepad (bound through ContextActionService for the fight, above the default jump / camera bindings):
-- X jab, Y cross, B lead hook, A rear hook, RT uppercut, RB overhand (tap: it goes on the release) and the
-- special-move modifier (hold RB + a button), LB = to the body, LT block (both tap toggles), right stick
-- flick left / right slip, down roll, up parry, flick then X / Y counter jab / cross, RS click quick dodge,
-- D-pad left / right pivot, D-pad up parry, D-pad down or LS click clinch, VIEW the controls strip (hold
-- it for the menu); when down, mash A. Aim assist (Settings, gamepad only) reads the left stick relative
-- to the opponent; vibration on hits (Gamepad.Rumble); the fight camera frames both fighters and the right
-- stick nudges it. Touch: see buildTouch (pads and swipes for every move, MOVES for the menu).
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local Gamepad = UI.Gamepad -- input device and button names (optional)
local Keymap = require(Shared:WaitForChild("Keymap")) -- the control map (actions, defaults, labels)
local Moves = require(Shared:WaitForChild("Moves")) -- the special moves (names, hands, cooldowns)
local K = Enum.KeyCode
local FightRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fight")

local gui = UI.New("ScreenGui", { Name = "FightUI", ResetOnSpawn = false, IgnoreGuiInset = false, Enabled = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui") })

local F = {} -- current fight state
local camConn, fxConn
local music
local savedLighting

local function send(msg)
	FightRemote:FireServer(msg)
end

-- Tap toggles (block / body / legend): one state for keyboard, gamepad and touch. A quick press flips
-- the state; a press held longer than HOLD acts as a hold and lets go on release. Tog.views are HUD
-- painters called with (name, on) whenever a state changes (touch pads, key caps, the stance chips).
local Tog = { on = { block = false, body = false, legend = false }, pressedAt = {}, HOLD = 0.35, views = {}, effects = {} }
function Tog.set(name, v, quiet)
	v = v == true
	local was = Tog.on[name]
	Tog.on[name] = v
	local fx = Tog.effects[name]
	if fx and not quiet then
		fx(v, was)
	end
	for _, view in ipairs(Tog.views) do
		pcall(view, name, v)
	end
end
function Tog.press(name)
	if Tog.on[name] then
		Tog.pressedAt[name] = nil
		Tog.set(name, false)
	else
		Tog.pressedAt[name] = os.clock()
		Tog.set(name, true)
	end
end
function Tog.release(name)
	local t = Tog.pressedAt[name]
	Tog.pressedAt[name] = nil
	if t and os.clock() - t >= Tog.HOLD and Tog.on[name] then
		Tog.set(name, false)
	end
end
function Tog.held(name)
	return Tog.pressedAt[name] ~= nil
end
-- everything off (fight over, round over, knocked down); quiet = the server already dropped the guard
function Tog.reset(quiet)
	for name, v in pairs(Tog.on) do
		Tog.pressedAt[name] = nil
		if v then
			Tog.set(name, false, quiet and name == "block")
		end
	end
end

-- accessibility scale for blur / shake / flashes / colour (0 disables them)
local function fxScale()
	return math.clamp(tonumber(Config.ScreenFX) or 1, 0, 2)
end

-- the player's camera-shake setting (Settings publishes it as a client-local attribute)
local function shakeScale()
	return math.clamp(tonumber(player:GetAttribute("CamShake")) or 1, 0, 1.5)
end

local BUILTIN = Config.BuiltinSounds or {}
local function soundId(key, fallback)
	local ok, id = pcall(Config.SoundId, key)
	return (ok and id) or BUILTIN[fallback] or "rbxasset://sounds/action_jump_land.mp3"
end

------------------------------------------------------------------------
-- VenueFX (stream G): optional. Every call is pcall-guarded; without it the legacy effects run.
------------------------------------------------------------------------
local VenueFX = nil -- nil = not resolved yet, false = not available
local venueOn = false
local resolving = false
-- wait = true only from the background task at startup; a fight start never blocks on it
local function resolveVenueFX(wait)
	if VenueFX ~= nil or resolving then
		return VenueFX or nil
	end
	resolving = true
	local ok, mod = pcall(function()
		local folder = script.Parent:FindFirstChild("BoxerClient") or (wait and script.Parent:WaitForChild("BoxerClient", 8))
		local m = folder and (folder:FindFirstChild("VenueFX") or (wait and folder:WaitForChild("VenueFX", 2)))
		return m and require(m)
	end)
	resolving = false
	if ok and type(mod) == "table" then
		VenueFX = mod
	elseif wait or not ok then
		VenueFX = false
	end
	return VenueFX or nil
end
task.spawn(resolveVenueFX, true)

-- nationality flags for the scoreboard (BoxerClient.Flags, R-ui); optional, cached once found
local Flags
local function getFlags()
	if Flags then
		return Flags
	end
	local ok, mod = pcall(function()
		local folder = script.Parent:FindFirstChild("BoxerClient")
		local m = folder and folder:FindFirstChild("Flags")
		return m and require(m)
	end)
	if ok and type(mod) == "table" then
		Flags = mod
	end
	return Flags
end

local function vfx(name, ...)
	if not venueOn or not VenueFX then
		return nil
	end
	local fn = VenueFX[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, r = pcall(fn, ...)
	if not ok then
		warn("[FightClient] VenueFX." .. name .. ":", r)
		return nil
	end
	return r
end

------------------------------------------------------------------------
-- Audio: SoundService.FightMix (concussion muffling for every fight sound, VenueFX routes its
-- crowd / bell / music through it too) and a small round-robin pool (no Instance.new per hit)
------------------------------------------------------------------------
local mix, mixEq
local pool, poolIdx = {}, 0

local function ensureMix()
	if mix and mix.Parent then
		return mix
	end
	mix = SoundService:FindFirstChild("FightMix")
	if not mix then
		mix = Instance.new("SoundGroup")
		mix.Name = "FightMix"
		mix.Volume = 1
		mix.Parent = SoundService
	end
	mixEq = mix:FindFirstChild("ConcussionEQ")
	if not mixEq then
		mixEq = Instance.new("EqualizerSoundEffect")
		mixEq.Name = "ConcussionEQ"
		mixEq.HighGain, mixEq.MidGain, mixEq.LowGain = 0, 0, 0
		mixEq.Parent = mix
	end
	table.clear(pool)
	for i = 1, 10 do
		local s = Instance.new("Sound")
		s.Name = "FightSfx" .. i
		s.SoundGroup = mix
		s.Parent = mix
		pool[i] = s
	end
	return mix
end

local function destroyMix()
	table.clear(pool)
	local m = SoundService:FindFirstChild("FightMix")
	if m then
		m:Destroy()
	end
	mix, mixEq = nil, nil
end

local function sfx(id, speed, volume)
	if #pool == 0 then
		-- never rebuild the mix outside a fight: a delayed beat / bell landing after finish() would
		-- otherwise leave a new FightMix (and its pooled Sounds) behind until the next fight
		if not gui.Enabled then
			return
		end
		ensureMix()
	end
	poolIdx = poolIdx % #pool + 1
	local s = pool[poolIdx]
	if not s or not s.Parent then
		return
	end
	s:Stop()
	s.SoundId = id
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 0.5
	s:Play()
end

------------------------------------------------------------------------
-- HUD (broadcast style)
------------------------------------------------------------------------
-- The HUD lives on a scaled root (UI.MountRoot): built on the 1600 x 900 design canvas. Two layouts:
-- the full broadcast scoreboard, and on short (phone) canvases a slim strip per fighter (name, the
-- HEALTH bar, three mini bars with icons) that leaves the ring in view. Nothing is shrunk with a
-- UIScale: compact pieces get their own sizes, so no text drops under UI.MinTextPx on screen.
local hud = UI.MountRoot(gui, "HUDRoot")
-- everything the rest of the script uses from the HUD (built in the block below, which keeps its
-- own helpers local: the script stays well under Luau's 200-locals-per-function limit)
local compactHud, tierColor, rampColor, stamColor, setBar, ZONE_IDLE, L, R, addKD, clock, roundText, timeText, crowdMeter, layoutClockTop
local updateCrowd, bug, setBug, angleTag, bannerBand, flash, defFlash, crowdStrip, flashbulbs, crowdMoment, crowdPulse
local controls, controlsUntil, showBanner, showFlash, setTicker, markers, hitMarker, zoneFlash, overlay, overlayBegin
local overlayShow, ovHead, ovVersus, ovRow, ovNote, ovQuote, ovScore, ovRounds, ovCondition, countBox, countKicker, countKickerText
local countNum, countWho, openCount, showCount, hideCount, getup, getupTitle, setGetup, zone, marker, getupHint, getupPress
local refreshControls, layoutHud, throwPunch, pickHook, buildTouch, holdH, throwSpecial, setTouchSpecials, openMoves
-- the control map in use (Settings.Keymap() once the BoxerClient modules are up; the defaults before), the
-- strip's key-cap labels (repainted when the map changes) and the BoxerClient modules resolved lazily
-- (Settings, ControlsMenu; every require guarded)
local KM = { caps = {}, modules = {} }
function KM.module(name)
	local m = KM.modules[name]
	if m ~= nil then
		return m or nil
	end
	local ok, mod = pcall(function()
		local folder = script.Parent:FindFirstChild("BoxerClient")
		local inst = folder and folder:FindFirstChild(name)
		return inst and require(inst)
	end)
	if ok and type(mod) == "table" then
		KM.modules[name] = mod
		return mod
	end
	return nil
end
function KM.now()
	local Settings = KM.module("Settings")
	if Settings and type(Settings.Keymap) == "function" then
		local ok, m = pcall(Settings.Keymap)
		if ok and type(m) == "table" then
			return m
		end
	end
	return Keymap.Resolve(nil)
end
-- KM.capText(ids, mode) -> a cap's text (set by the HUD block)
function KM.refresh()
	local mode = Gamepad and Gamepad.Mode() or "keyboard"
	for _, list in ipairs({ KM.caps, KM.specialCaps or {} }) do
		for _, c in ipairs(list) do
			local ok, text = pcall(KM.capText, c.ids, mode)
			if ok and type(text) == "string" and c.label.Text ~= text then
				c.label.Text = text
			end
		end
	end
end
do
	local GuiService = game:GetService("GuiService")
	compactHud = false -- layoutHud keeps it current
	local hudTop = 160 -- design y under the scoreboard (hit markers and banners stay below it)
	local touchPad, defencePad -- the touch controls (buildTouch), nil on keyboard / gamepad

	function tierColor(tier)
		local def = Config.HeadTiers[(tier or 0) + 1] or Config.HeadTiers[1]
		local c = def.rgb
		return Color3.fromRGB(c[1], c[2], c[3])
	end

	-- the one colour ramp every damage bar uses (HEALTH, HEAD, BODY; UI.Ramp, shared with the gym
	-- screens): the value decides the colour, the label and icon say which bar it is. Stamina has its
	-- own: blue while there is gas, amber from half, red under a quarter (and then it pulses: updateFX)
	rampColor, stamColor = UI.Ramp, UI.StamColor

	-- a bar with a permanent-damage cap (striped, from the far end), a trailing white "ghost" that
	-- shows the chunk just lost, and the live fill. side "R" depletes toward the outside edge.
	-- label (optional) sits inside the bar on the near end; showValue puts the number on the far end
	-- (thick bars only: a thin bar carries its number on its caption)
	local function hudBar(parent, props, color, side, label, thick, showValue)
		local right = side == "R"
		local bg = UI.Frame(parent, props)
		bg.BackgroundColor3 = T.ink
		bg.BackgroundTransparency = 0.1
		bg.ClipsDescendants = true
		UI.Corner(bg, thick and 4 or 2)
		local anchor = right and Vector2.new(1, 0) or Vector2.new(0, 0)
		local pos = right and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 0)
		local ghost = UI.Frame(bg, { Name = "Ghost", Size = UDim2.fromScale(1, 1), AnchorPoint = anchor, Position = pos, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2, ZIndex = 2 })
		local fill = UI.Frame(bg, { Name = "Fill", Size = UDim2.fromScale(1, 1), AnchorPoint = anchor, Position = pos, BackgroundColor3 = color, ZIndex = 3 })
		UI.Gradient(fill, { Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165) }, 90)
		-- the cap eats in from the far end: damage that will not come back this fight
		local cap = UI.Frame(bg, { Name = "Cap", Size = UDim2.fromScale(0, 1), AnchorPoint = right and Vector2.new(0, 0) or Vector2.new(1, 0),
			Position = right and UDim2.fromScale(0, 0) or UDim2.fromScale(1, 0), BackgroundColor3 = Color3.fromRGB(80, 14, 20), ZIndex = 4 })
		local stripes = UI.Gradient(cap, Color3.new(1, 1, 1), 35, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.24, 0.1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(0.49, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(0.74, 0.1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 0.55),
		}))
		pcall(function()
			stripes.TileMode = Enum.GradientTileMode.Repeat
			stripes.Scale = 0.25
		end)
		local value
		if showValue then
			value = UI.Text(bg, "", { Name = "Value", Face = "number", TextSize = 16, TextStrokeTransparency = 0.5, ZIndex = 5, Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false })
			UI.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = value })
		end
		local labelText
		if label then
			labelText = UI.Text(bg, label, { Name = "Label", Font = T.semi, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.6, ZIndex = 5,
				Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, TextWrapped = false })
			UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = labelText })
		end
		return { bg = bg, fill = fill, ghost = ghost, cap = cap, value = value, label = labelText, v = 1, ghostV = 1, pending = false }
	end

	function setBar(b, frac, capFrac, color)
		frac = math.clamp(frac or 0, 0, 1)
		capFrac = math.clamp(capFrac or 1, 0, 1)
		b.fill.Size = UDim2.fromScale(frac, 1)
		if color then
			b.fill.BackgroundColor3 = color
		end
		b.cap.Size = UDim2.fromScale(1 - capFrac, 1)
		local pct = math.floor(frac * 100 + 0.5)
		if b.value then
			b.value.Text = tostring(pct)
		end
		if b.caption then
			-- thin pool bars carry the number on their caption: "HEAD  72"
			b.caption.Text = b.word .. "  " .. pct
		end
		if frac < b.ghostV - 0.003 then
			-- hold the lost chunk for a beat, then let it drain away
			if not b.pending then
				b.pending = true
				task.delay(0.35, function()
					b.pending = false
					b.ghostV = b.v
					TweenService:Create(b.ghost, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(b.v, 1) }):Play()
				end)
			end
		elseif not b.pending then
			b.ghostV = frac
			b.ghost.Size = UDim2.fromScale(frac, 1)
		end
		b.v = frac
	end

	-- the hit-location figure on the outer side of each panel: head, neck, shoulders, both sides of the
	-- ribs (the liver is the target's right side), hips. The zone a punch lands on flashes.
	ZONE_IDLE = Color3.fromRGB(62, 69, 88)
	local function zoneMap(parent, side)
		local f = UI.Frame(parent, { Name = "Zones", BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 92), AnchorPoint = Vector2.new(side == "L" and 0 or 1, 0) })
		local head = UI.Frame(f, { Name = "Head", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(22, 24), BackgroundColor3 = ZONE_IDLE })
		UI.Corner(head, 11)
		UI.Frame(f, { Name = "Neck", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 23), Size = UDim2.fromOffset(10, 6), BackgroundColor3 = ZONE_IDLE, BackgroundTransparency = 0.3 })
		local shoulders = UI.Frame(f, { Name = "Shoulders", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(44, 12), BackgroundColor3 = ZONE_IDLE, BackgroundTransparency = 0.3 })
		UI.Corner(shoulders, 6)
		-- the two rib zones are drawn from the viewer's side: the target faces us
		local bodyL = UI.Frame(f, { Name = "BodyL", Position = UDim2.fromOffset(4, 40), Size = UDim2.fromOffset(18, 34), BackgroundColor3 = ZONE_IDLE })
		UI.Corner(bodyL, 6)
		local bodyR = UI.Frame(f, { Name = "BodyR", Position = UDim2.fromOffset(24, 40), Size = UDim2.fromOffset(18, 34), BackgroundColor3 = ZONE_IDLE })
		UI.Corner(bodyR, 6)
		local hips = UI.Frame(f, { Name = "Hips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), Size = UDim2.fromOffset(30, 14), BackgroundColor3 = ZONE_IDLE, BackgroundTransparency = 0.4 })
		UI.Corner(hips, 5)
		return { frame = f, head = head, bodyL = bodyL, bodyR = bodyR }
	end

	-- small status icons: cut (a drop), swelling (an eye), ribs (bars)
	local function statusIcon(parent, kind, color, order)
		local f = UI.Frame(parent, { Name = kind, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, BackgroundTransparency = 0.2, Visible = false, LayoutOrder = order })
		UI.Corner(f, 4)
		UI.New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 6), Parent = f })
		UI.List(f, 4, true)
		local glyph = UI.Frame(f, { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 20), LayoutOrder = 1 })
		if kind == "Cut" then
			local d = UI.Frame(glyph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1) })
			UI.Corner(d, 4)
			UI.Frame(glyph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(5, 5), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1) })
		elseif kind == "Swelling" then
			local e = UI.Frame(glyph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 6), BackgroundColor3 = Color3.new(1, 1, 1) })
			UI.Corner(e, 3)
			local p = UI.Frame(e, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = color })
			UI.Corner(p, 2)
		else
			for i = 0, 2 do
				UI.Frame(glyph, { Position = UDim2.fromOffset(1, 5 + i * 4), Size = UDim2.fromOffset(8, 2), BackgroundColor3 = Color3.new(1, 1, 1) })
			end
		end
		UI.Text(f, string.upper(kind), { Font = T.semi, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false, LayoutOrder = 2 })
		return f
	end

	-- tiny glyphs for the compact pool bars (no captions there): a head, a torso, a lightning bolt
	local function poolGlyph(parent, kind, color)
		local g = UI.Frame(parent, { Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), Visible = false })
		if kind == "HEAD" then
			local c = UI.Frame(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = color })
			UI.Corner(c, 5)
		elseif kind == "BODY" then
			local c = UI.Frame(g, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(9, 12), BackgroundColor3 = color })
			UI.Corner(c, 3)
		else
			UI.Icon(g, "bolt", 12, color, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		end
		return g
	end

	local board = UI.Frame(hud, { Name = "Scoreboard", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(1, -40, 0, 140) })
	local boardMax = UI.New("UISizeConstraint", { MaxSize = Vector2.new(1380, 140), Parent = board })
	local BOARD_H, BOARD_H_COMPACT = 140, 70

	local function fighterPanel(side)
		local left = side == "L"
		local accent = left and T.red or T.blue
		local f = UI.Frame(board, { Name = left and "You" or "Opponent", Size = UDim2.new(0.5, -96, 1, 0), Position = left and UDim2.fromScale(0, 0) or UDim2.fromScale(1, 0),
			AnchorPoint = left and Vector2.new(0, 0) or Vector2.new(1, 0), Visible = false })
		UI.Glass(f, { transparency = 0.12, radius = UI.R.lg })
		-- the corner colour along the outer edge
		local edge = UI.Frame(f, { Name = "Corner", AnchorPoint = Vector2.new(left and 0 or 1, 0), Position = left and UDim2.fromOffset(0, 10) or UDim2.new(1, 0, 0, 10), Size = UDim2.new(0, 4, 1, -20), BackgroundColor3 = accent })
		UI.Corner(edge, 2)
		local align = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
		local outer = Vector2.new(left and 0 or 1, 0)
		local flagHolder = UI.Frame(f, { Name = "FlagHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 20), AnchorPoint = outer })
		local name = UI.Text(f, "", { Name = "Name", Face = "display", TextSize = 26, AnchorPoint = outer, AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align, TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd })
		-- the inner end of the name row: knockdown tags, then the status chip (ROCKED / DAZED / ...)
		local tags = UI.Frame(f, { Name = "Tags", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(left and 1 or 0, 0), ZIndex = 6 })
		UI.List(tags, 4, true, left and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left)
		local kdRow = UI.Frame(tags, { Name = "KD", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = left and 1 or 2 })
		UI.List(kdRow, 3, true)
		local chip = UI.Frame(tags, { Name = "Chip", Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.gold, Visible = false, LayoutOrder = left and 2 or 1, ZIndex = 6 })
		UI.Corner(chip, 4)
		local chipText = UI.Text(chip, "", { Font = T.semi, TextSize = 13, TextColor3 = T.ink, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 7,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.New("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = chipText })
		-- record + nickname under the name
		local sub = UI.Text(f, "", { Name = "Sub", Font = T.semi, TextSize = 13, TextColor3 = T.sub, AnchorPoint = outer, AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		-- HEALTH (overall), then HEAD | BODY | STAMINA
		local health = hudBar(f, { Name = "Health", AnchorPoint = outer }, T.green, side, "HEALTH", true, true)
		local pools = UI.Frame(f, { Name = "Pools", BackgroundTransparency = 1, AnchorPoint = outer })
		local function pool(i, word, color)
			local cell = UI.Frame(pools, { Name = word, BackgroundTransparency = 1, Position = UDim2.new((i - 1) / 3, i > 1 and 4 or 0, 0, 0), Size = UDim2.new(1 / 3, -6, 1, 0) })
			local cap = UI.Text(cell, word, { Name = "Caption", Font = T.semi, TextSize = 13, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = align, TextWrapped = false })
			local glyph = poolGlyph(cell, word, T.sub)
			glyph.AnchorPoint = Vector2.new(left and 0 or 1, 0.5)
			local b = hudBar(cell, { Name = "Bar" }, color, side)
			b.caption, b.word, b.glyph, b.cell = cap, word, glyph, cell
			return b
		end
		local head = pool(left and 1 or 3, "HEAD", T.green)
		local body = pool(2, "BODY", T.green)
		local stam = pool(left and 3 or 1, "STAMINA", T.blue)
		-- damage icons + the player's balance
		local icons = UI.Frame(f, { Name = "Icons", BackgroundTransparency = 1, AnchorPoint = outer })
		UI.List(icons, 5, true, left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right)
		local p = {
			frame = f, side = side, left = left, name = name, sub = sub, chip = chip, chipText = chipText, flag = flagHolder, kd = kdRow, tags = tags, kdCount = 0,
			health = health, head = head, body = body, stam = stam, pools = pools, icons = icons, zones = zoneMap(f, side),
			cut = statusIcon(icons, "Cut", T.red, 1), swell = statusIcon(icons, "Swelling", T.purple, 2), ribs = statusIcon(icons, "Ribs", T.orange, 3),
		}
		if left then
			-- the player's own legs: below a third, the next big shot (or a whiffed hook) staggers you
			local balHolder = UI.Frame(icons, { BackgroundTransparency = 1, Size = UDim2.fromOffset(176, 20), LayoutOrder = 9 })
			UI.Text(balHolder, "BALANCE", { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Size = UDim2.fromOffset(70, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
			local bg = UI.Frame(balHolder, { Position = UDim2.new(0, 74, 0.5, -2), Size = UDim2.new(1, -74, 0, 5), BackgroundColor3 = T.ink })
			UI.Corner(bg, 2)
			p.bal = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 200, 210) })
			UI.Corner(p.bal, 2)
		end
		return p
	end
	L = fighterPanel("L")
	R = fighterPanel("R")

	-- positions every piece of a panel for the full board or the slim phone strip
	local function layoutPanel(p, compact)
		local left = p.left
		local function at(x, y)
			return left and UDim2.fromOffset(x, y) or UDim2.new(1, -x, 0, y)
		end
		local inner = left and Vector2.new(1, 0) or Vector2.new(0, 0)
		p.tags.AnchorPoint = inner
		if compact then
			p.flag.Position, p.flag.Size = at(12, 8), UDim2.fromOffset(24, 16)
			p.name.Position, p.name.Size = at(42, 3), UDim2.new(1, -(42 + 124), 0, 26)
			UI.SetTextSize(p.name, 21)
			p.tags.Position = left and UDim2.new(1, -8, 0, 5) or UDim2.fromOffset(8, 5)
			p.sub.Visible = false
			p.health.bg.Position, p.health.bg.Size = at(10, 32), UDim2.new(1, -20, 0, 18)
			p.health.label.Visible = false
			p.pools.Position, p.pools.Size = at(10, 55), UDim2.new(1, -20, 0, 10)
			for _, b in ipairs({ p.head, p.body, p.stam }) do
				b.caption.Visible = false
				b.glyph.Visible = true
				b.glyph.Position = left and UDim2.new(0, 0, 0.5, 0) or UDim2.new(1, 0, 0.5, 0)
				b.bg.Position = left and UDim2.fromOffset(16, 1) or UDim2.fromOffset(0, 1)
				b.bg.Size = UDim2.new(1, -16, 0, 8)
			end
			p.icons.Visible = false
			p.zones.frame.Visible = false
		else
			local x0 = 72 -- the figure column on the outer side
			p.flag.Position, p.flag.Size = at(16, 12), UDim2.fromOffset(30, 20)
			p.name.Position, p.name.Size = at(54, 5), UDim2.new(1, -(54 + 150), 0, 32)
			UI.SetTextSize(p.name, 26)
			p.tags.Position = left and UDim2.new(1, -12, 0, 10) or UDim2.fromOffset(12, 10)
			p.sub.Visible = true
			p.sub.Position, p.sub.Size = at(54, 39), UDim2.new(1, -66, 0, 16)
			p.health.bg.Position, p.health.bg.Size = at(x0, 60), UDim2.new(1, -(x0 + 14), 0, 20)
			p.health.label.Visible = true
			p.pools.Position, p.pools.Size = at(x0, 86), UDim2.new(1, -(x0 + 14), 0, 30)
			for _, b in ipairs({ p.head, p.body, p.stam }) do
				b.caption.Visible = true
				b.glyph.Visible = false
				b.bg.Position, b.bg.Size = UDim2.fromOffset(0, 19), UDim2.new(1, 0, 0, 10)
			end
			p.icons.Visible = true
			p.icons.Position, p.icons.Size = at(x0, 118), UDim2.new(1, -(x0 + 14), 0, 20)
			p.zones.frame.Visible = true
			p.zones.frame.Position = at(14, 42)
		end
	end

	-- one red "KD" tag per knockdown, at the inner end of the name row
	function addKD(panel)
		panel.kdCount += 1
		local c = UI.Frame(panel.kd, { Name = "KD" .. panel.kdCount, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.red, LayoutOrder = panel.kdCount })
		UI.Corner(c, 4)
		local t = UI.Text(c, "KD", { Font = T.semi, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Pad(t, 0, 6)
	end

	-- center: the round and the clock (the network's LIVE tag sits in the clock's top band, inside the
	-- scoreboard); the crowd meter under the time
	clock = UI.Frame(board, { Name = "Clock", Size = UDim2.new(0, 176, 1, 0), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), Visible = false })
	UI.Glass(clock, { transparency = 0.06, radius = UI.R.lg, color = T.ink })
	local clockTop = UI.Frame(clock, { Name = "Top", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.gold })
	UI.Corner(clockTop, UI.R.lg)
	UI.Frame(clockTop, { Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = T.gold })
	local liveTag = UI.Frame(clockTop, { Name = "Live", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0), Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.red, ZIndex = 2 })
	UI.Corner(liveTag, 4)
	local liveText = UI.Text(liveTag, "LIVE", { Font = T.semi, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 3 })
	UI.Pad(liveText, 0, 5)
	roundText = UI.Text(clockTop, "ROUND 1", { Face = "displayMed", TextSize = 18, TextColor3 = T.ink, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -48, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	-- the round text starts where the SPAR / LIVE tag ends (a phone's text floor makes the tag wider than its
	-- 44 px slot, and "SPAR" over "ROUND 1 / 1" read as one word)
	function layoutClockTop()
		local tagW = liveTag.AbsoluteSize.X / math.max(0.01, UI.ScaleOf(clockTop))
		local x = math.max(compactHud and 38 or 44, tagW + 10)
		roundText.Position = UDim2.fromOffset(x, 0)
		roundText.Size = UDim2.new(1, -(x + 4), 1, 0)
	end
	liveTag:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutClockTop)
	timeText = UI.Text(clock, "1:00", { Face = "number", TextSize = 50, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	-- the crowd: a two-sided meter (red fills left when they are behind you, blue right when they back
	-- him), a glow that pulses on big shots, the mood in words under it
	local crowdBox = UI.Frame(clock, { Name = "Crowd", BackgroundTransparency = 1, Position = UDim2.new(0, 12, 1, -46), Size = UDim2.new(1, -24, 0, 40) })
	local crowdBar = UI.Frame(crowdBox, { Name = "Meter", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Color3.fromRGB(26, 28, 36) })
	UI.Corner(crowdBar, 4)
	local crowdGlow = UI.Frame(crowdBox, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, 10, 0, 18), BackgroundColor3 = T.gold,
		BackgroundTransparency = 1, ZIndex = 0 })
	UI.Corner(crowdGlow, 9)
	local crowdLeft = UI.Frame(crowdBar, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.red })
	UI.Corner(crowdLeft, 4)
	local crowdRight = UI.Frame(crowdBar, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.blue })
	UI.Corner(crowdRight, 4)
	local crowdMid = UI.Frame(crowdBar, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 6), BackgroundColor3 = Color3.new(1, 1, 1) })
	local crowdLabel = UI.Text(crowdBox, "CROWD  ·  QUIET", { Name = "Mood", Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	crowdMeter = { level = 0.2, lean = 0, shownLevel = -1, shownLean = 99, quiet = 0, lastBanner = -100 }
	local CROWD_WORDS = { { 0.85, "ON THEIR FEET" }, { 0.6, "CROWD  ·  ROARING" }, { 0.35, "CROWD  ·  BUZZING" }, { 0, "CROWD  ·  QUIET" } }
	function updateCrowd(dt)
		crowdMeter.lean *= math.exp(-dt / 6)
		local lvl = math.floor(crowdMeter.level * 20 + 0.5) / 20
		local lean = math.floor(crowdMeter.lean * 40 + 0.5) / 40
		if lvl == crowdMeter.shownLevel and lean == crowdMeter.shownLean then
			return
		end
		crowdMeter.shownLevel, crowdMeter.shownLean = lvl, lean
		-- the meter fills toward the corner the crowd is behind, as far as it is loud
		local reach = 0.2 + 0.8 * lvl
		crowdLeft.Size = UDim2.fromScale(math.clamp(lean, 0, 1) * 0.5 * reach + (lean > 0 and 0.02 or 0), 1)
		crowdRight.Size = UDim2.fromScale(math.clamp(-lean, 0, 1) * 0.5 * reach + (lean < 0 and 0.02 or 0), 1)
		crowdMid.BackgroundTransparency = 0.6 - lvl * 0.6
		for _, w in ipairs(CROWD_WORDS) do
			if lvl >= w[1] then
				crowdLabel.Text = w[2]
				crowdLabel.TextColor3 = lvl >= 0.6 and T.gold or T.sub
				break
			end
		end
	end

	-- the network bug in the top-left corner during walkouts and the tape (in rounds the clock's LIVE
	-- tag stands in for it)
	bug = UI.Frame(hud, { Name = "Bug", Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromOffset(20, 10), BackgroundColor3 = T.red, Visible = false })
	UI.Corner(bug, 4)
	local bugText = UI.Text(bug, "LIVE  ·  WCB SPORTS", { Font = T.semi, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false })
	UI.Pad(bugText, 0, 10)
	function setBug(text, color, short)
		bugText.Text = text
		bug.BackgroundColor3 = color
		liveText.Text = short
		liveTag.BackgroundColor3 = color
		layoutClockTop()
	end

	angleTag = UI.Chip(hud, "ANGLE  +ACCURACY", T.gold, { solid = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 184), h = 26, TextSize = 13 })
	angleTag.Visible = false

	-- the big centre banner (ROUND 1, KNOCKDOWN, KO!): a band that opens with display type
	bannerBand = UI.Frame(hud, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = T.ink, BackgroundTransparency = 1, Visible = false, ZIndex = 20 })
	UI.Gradient(bannerBand, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1) }))
	local bannerScale = UI.New("UIScale", { Parent = bannerBand })
	local banner = UI.Text(bannerBand, "", { Face = "display", TextSize = 96, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 21 })
	local bannerGrad = UI.Gradient(banner, { Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205) }, 90)
	local function label(y, size)
		return UI.Text(hud, "", { Face = "display", TextSize = size, TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, size + 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, y, 0), Visible = false, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 18 })
	end
	flash = label(0.6, 36)
	defFlash = label(0.67, 28)

	-- the crowd moments: a strip slides in under the scoreboard ("THE CROWD IS ON ITS FEET!"), at most one
	-- every 20 seconds, while photographers' flashes sparkle along the top of the picture
	crowdStrip = UI.Frame(hud, { Name = "CrowdMoment", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(560, 48), BackgroundColor3 = T.red,
		Visible = false, ZIndex = 19, ClipsDescendants = true })
	UI.Corner(crowdStrip, UI.R.md)
	local crowdStripGrad = UI.Gradient(crowdStrip, { Color3.fromRGB(170, 20, 30), Color3.fromRGB(230, 60, 40) }, 0)
	local crowdStripText = UI.Text(crowdStrip, "", { Face = "display", TextSize = 28, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 20 })
	local crowdStripScale = UI.New("UIScale", { Parent = crowdStrip })
	-- photographers' flashes along the top edge of the picture, behind the scoreboard panels (they pop in
	-- the gaps around and under it): a hot core and a soft halo, gone in a third of a second
	local sparkles = UI.Frame(hud, { Name = "Flashbulbs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 220), ZIndex = 0 })
	local bulbs = {}
	for i = 1, 18 do
		local halo = UI.Frame(sparkles, { Name = "Bulb", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(255, 250, 235),
			BackgroundTransparency = 1, ZIndex = 0 })
		UI.Corner(halo, 17)
		local core = UI.Frame(halo, { Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.3, 0.3),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 0 })
		UI.Corner(core, 6)
		bulbs[i] = { halo = halo, core = core }
	end
	local BULB_FADE = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	function flashbulbs(n)
		for i = 1, math.min(n, #bulbs) do
			local b = bulbs[i]
			task.delay(math.random() * 1.6, function()
				local sz = math.random(22, 40)
				b.halo.Position = UDim2.new(0.02 + math.random() * 0.96, 0, 0, math.random(4, math.floor(hudTop + 46)))
				b.halo.Size = UDim2.fromOffset(sz, sz)
				b.halo.BackgroundTransparency = 0.72
				b.core.BackgroundTransparency = 0
				UI.Tween(b.halo, { BackgroundTransparency = 1 }, BULB_FADE)
				UI.Tween(b.core, { BackgroundTransparency = 1 }, BULB_FADE)
			end)
		end
	end
	function crowdMoment(text, color)
		local now = os.clock()
		if now - crowdMeter.lastBanner < 20 then
			return
		end
		-- the count, the get-up panel, the scorecards and the round banner own the middle of the screen: the
		-- crowd gets its flashbulbs then, not a strip over them
		if (countBox and countBox.Visible) or (getup and getup.Visible) or (overlay and overlay.Visible) or (bannerBand and bannerBand.Visible) then
			if color ~= T.orange then
				flashbulbs(16)
			end
			return
		end
		crowdMeter.lastBanner = now
		crowdStripText.Text = text
		crowdStripGrad.Color = ColorSequence.new(UI.Shade(color, -0.35), color)
		crowdStrip.Visible = true
		crowdStripScale.Scale = 0.85
		crowdStripText.TextTransparency = 1
		UI.Tween(crowdStripScale, { Scale = 1 }, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		UI.Tween(crowdStripText, { TextTransparency = 0 }, 0.2)
		if color ~= T.orange then
			flashbulbs(16)
		end
		task.delay(2.4, function()
			if crowdMeter.lastBanner == now then
				UI.Tween(crowdStripText, { TextTransparency = 1 }, 0.25)
				task.delay(0.26, function()
					if crowdMeter.lastBanner == now then
						crowdStrip.Visible = false
					end
				end)
			end
		end)
	end
	-- a big shot: the meter glows for a moment
	function crowdPulse(k)
		crowdGlow.BackgroundTransparency = 1 - 0.55 * math.clamp(k, 0, 1)
		UI.Tween(crowdGlow, { BackgroundTransparency = 1 }, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end

	-- the lower third: live commentary
	local ticker = UI.Frame(hud, { Name = "Ticker", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -48, 0, 40), BackgroundColor3 = T.bg })
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(1080, 40), Parent = ticker })
	UI.Glass(ticker, { transparency = 0.12, radius = UI.R.md })
	local tickerTag = UI.Frame(ticker, { Size = UDim2.new(0, 140, 1, 0), BackgroundColor3 = T.red })
	UI.Corner(tickerTag, UI.R.md)
	UI.Frame(tickerTag, { Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = T.red })
	local liveDot = UI.Frame(tickerTag, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1) })
	UI.Corner(liveDot, 4)
	UI.Text(tickerTag, "COMMENTARY", { Font = T.semi, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local tickerText = UI.Text(ticker, "", { TextSize = 15, Font = T.semi, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(154, 0), Size = UDim2.new(1, -168, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- control hints (key caps) above the ticker: shown for the first seconds of the fight, then while H is
	-- held (or always, with the setting); touch players get the pads instead
	-- one row on a wide screen, two (punches / defence) on a short one
	controls = UI.Frame(hud, { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -62), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY })
	UI.Glass(controls, { transparency = 0.35, radius = 16 })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = controls })
	UI.List(controls, 2, false, Enum.HorizontalAlignment.Center)
	local ctlRows = {}
	for r = 1, 3 do
		ctlRows[r] = UI.Frame(controls, { Name = "Row" .. r, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = r })
		UI.List(ctlRows[r], 12, true, Enum.HorizontalAlignment.Center)
	end
	local ctlItems = {}
	-- { action id(s), caption }: the caps read the control map for the device in use (the right-stick
	-- flicks read "RS LEFT/RIGHT", "RS DOWN"); KM.refresh repaints them when the map changes
	local function capText(ids, mode)
		local map = KM.now()
		local device = (mode == "gamepad" and Gamepad) and "pad" or "kbd"
		local parts = {}
		for _, id in ipairs(ids) do
			local t = Keymap.ActionText(map, id, device, Gamepad)
			if device == "kbd" then
				t = t:match("^(.-) / ") or t -- the primary key only: the strip is tight
			end
			if #parts > 0 and t:sub(1, 3) == "RS " and parts[1]:sub(1, 3) == "RS " then
				t = t:sub(4)
			end
			table.insert(parts, t)
		end
		return table.concat(parts, "/")
	end
	KM.capText = capText
	for i, k in ipairs({ { { "jab" }, "JAB" }, { { "cross" }, "CROSS" }, { { "leadhook" }, "L.HOOK" }, { { "rearhook" }, "R.HOOK" }, { { "uppercut" }, "UPPER" },
		{ { "overhand" }, "OVERHAND" }, { { "body" }, "BODY" }, { { "block" }, "BLOCK" }, { { "parry" }, "PARRY" },
		{ { "slipL", "slipR" }, "SLIP" }, { { "dodge" }, "DODGE" }, { { "pivotL", "pivotR" }, "PIVOT" }, { { "clinch" }, "CLINCH" }, { { "moveslist" }, "MOVES" } }) do
		local f = UI.Frame(ctlRows[1], { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i })
		ctlItems[i] = f
		UI.List(f, 5, true)
		local cap = UI.Frame(f, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel2, BackgroundTransparency = 0, LayoutOrder = 1 })
		UI.Corner(cap, 4)
		UI.Stroke(cap, Color3.new(1, 1, 1), 1, 0.85)
		local t = UI.Text(cap, "", { Font = T.semi, TextSize = 12, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Pad(t, 0, 6)
		UI.BindHint(t, function(mode)
			return capText(k[1], mode)
		end)
		table.insert(KM.caps, { label = t, ids = k[1] })
		UI.Text(f, k[2], { Font = T.semi, TextSize = 12, TextColor3 = Color3.fromRGB(200, 205, 216), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
		-- the toggles light their key cap while on
		local togName = (k[2] == "BODY" and "body") or (k[2] == "BLOCK" and "block") or nil
		if togName then
			cap.Name = "Cap_" .. togName
			table.insert(Tog.views, function(name, on)
				if name == togName then
					cap.BackgroundColor3 = on and (togName == "block" and T.blue or T.orange) or T.panel2
					t.TextColor3 = on and T.ink or Color3.new(1, 1, 1)
				end
			end)
		end
	end
	-- the third row: the special moves this fighter has unlocked, with their key / chord on the device in use
	-- (from the fight's start message; KM.refresh repaints these caps too, KM.paintSpecials dims them while
	-- a special is not ready)
	KM.specialCaps = {}
	function KM.buildSpecialStrip(list)
		UI.Clear(ctlRows[3])
		table.clear(KM.specialCaps)
		local mode = Gamepad and Gamepad.Mode() or "keyboard"
		for i, id in ipairs(list or {}) do
			local a = Keymap.ById["special_" .. id]
			if a then
				local f = UI.Frame(ctlRows[3], { Name = "StripSpecial_" .. id, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i })
				UI.List(f, 5, true)
				local cap = UI.Frame(f, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel2, BackgroundTransparency = 0, LayoutOrder = 1 })
				UI.Corner(cap, 4)
				local stroke = UI.New("UIStroke", { Color = T.gold, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cap })
				local t = UI.Text(cap, capText({ a.id }, mode), { Font = T.semi, TextSize = 12, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
					TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
				UI.Pad(t, 0, 6)
				UI.BindHint(t, function(m)
					return capText({ a.id }, m)
				end)
				table.insert(KM.specialCaps, { label = t, ids = { a.id } })
				local name = UI.Text(f, a.touch or id:upper(), { Font = T.semi, TextSize = 12, TextColor3 = T.gold, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
					TextWrapped = false, LayoutOrder = 2 })
				-- the strip's caps share the touch pads' readiness painter
				local e = KM.specialPads[id] or {}
				e.stripLabel, e.stripStroke = name, stroke
				KM.specialPads[id] = e
			end
		end
		ctlRows[3].Visible = #list > 0
	end
	-- the reminder once the strip has faded
	local controlsHint, controlsHintText = UI.Chip(hud, "H  ·  CONTROLS", T.sub, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -62), h = 24, TextSize = 13 })
	controlsHint.Visible = false
	UI.BindHint(controlsHintText, function(mode)
		return "TAP " .. ((mode == "gamepad" and Gamepad) and Gamepad.Label(K.ButtonSelect) or "H") .. "  ·  CONTROLS"
	end)
	controlsUntil = 0 -- os.clock() until which the strip shows on its own

	function showBanner(text, color, dur)
		banner.Text = text
		banner.TextColor3 = Color3.new(1, 1, 1)
		bannerGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), (color or T.gold))
		bannerBand.Visible = true
		bannerBand.BackgroundTransparency = 0
		bannerScale.Scale = 1.25
		banner.TextTransparency = 1
		UI.Tween(bannerScale, { Scale = 1 }, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		UI.Tween(banner, { TextTransparency = 0 }, 0.18)
		local id = os.clock()
		bannerBand:SetAttribute("Id", id)
		task.delay(dur or 1.6, function()
			if bannerBand:GetAttribute("Id") == id then
				UI.Tween(banner, { TextTransparency = 1 }, 0.25)
				task.delay(0.26, function()
					if bannerBand:GetAttribute("Id") == id then
						bannerBand.Visible = false
					end
				end)
			end
		end)
	end

	function showFlash(lbl, text, color, dur)
		lbl.Text = text
		lbl.TextColor3 = color or T.text
		lbl.Visible = true
		lbl.TextTransparency = 0
		local id = os.clock()
		lbl:SetAttribute("Id", id)
		task.delay(dur or 0.8, function()
			if lbl:GetAttribute("Id") == id then
				lbl.Visible = false
			end
		end)
	end

	function setTicker(text)
		tickerText.Text = text
		tickerText.TextTransparency = 1
		UI.Tween(tickerText, { TextTransparency = 0 }, 0.3)
	end

	-- floating hit markers over the opponent for every punch you land: the punch's name (gold and bigger for
	-- a big shot), kept under the scoreboard and inside the picture
	markers = UI.Frame(hud, { Name = "Markers", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 15 })
	function hitMarker(model, text, color, big)
		local cam = workspace.CurrentCamera
		local part = model and (model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart"))
		if not (cam and part) then
			return
		end
		local p, onScreen = cam:WorldToViewportPoint(part.Position + Vector3.new(0, 0.9, 0))
		if not onScreen then
			return
		end
		local s = UI.ScaleOf(hud)
		local inset = GuiService:GetGuiInset()
		local canvas = UI.CanvasSize(hud)
		local x, y = p.X / s, (p.Y - inset.Y) / s
		-- Oswald is condensed: about half the text size per character
		local half = math.min(canvas.X / 2 - 12, #text * (big and 19 or 13) / 2 + 12)
		-- clear of the touch pads (punches bottom right, defence on the left edge)
		local padL, padR = 8, 8
		if touchPad and touchPad.Visible and y > canvas.Y * 0.3 then
			padL, padR = 130, 230
		end
		x = math.clamp(x + math.random(-14, 14), math.min(half + padL, canvas.X / 2), math.max(canvas.X - half - padR, canvas.X / 2))
		y = math.clamp(y, hudTop + 34, canvas.Y - 110)
		local m = UI.Text(markers, text, { Face = "display", TextSize = big and 38 or 26, TextColor3 = color, TextStrokeTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(half * 2, big and 46 or 34), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 16 })
		local sc = UI.New("UIScale", { Scale = 0.6, Parent = m })
		UI.Tween(sc, { Scale = 1 }, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		UI.Tween(m, { Position = m.Position - UDim2.fromOffset(0, 46), TextTransparency = 1, TextStrokeTransparency = 1 }, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		task.delay(0.95, function()
			m:Destroy()
		end)
	end

	-- where a punch lands: the zone on the target's figure flashes (full board) and its bar's track
	-- lights up for a moment (both layouts: on a phone the bars are all there is)
	function zoneFlash(panel, isBody, hand, sev)
		local z = panel.zones
		local target = z.head
		if isBody then
			-- the attacker's left hand lands on the target's right side
			target = hand == "L" and z.bodyR or z.bodyL
		end
		target.BackgroundColor3 = Color3.new(1, 1, 1)
		UI.Tween(target, { BackgroundColor3 = T.red:Lerp(ZONE_IDLE, math.clamp(1 - sev, 0, 0.6)) }, TweenInfo.new(0.12))
		task.delay(0.5, function()
			if target.Parent then
				UI.Tween(target, { BackgroundColor3 = ZONE_IDLE }, TweenInfo.new(0.8))
			end
		end)
		local bar = isBody and panel.body or panel.head
		bar.bg.BackgroundColor3 = T.red:Lerp(Color3.new(1, 1, 1), 0.3)
		UI.Tween(bar.bg, { BackgroundColor3 = T.ink }, TweenInfo.new(0.45))
		if bar.glyph.Visible then
			bar.glyph.Size = UDim2.fromOffset(16, 16)
			UI.Tween(bar.glyph, { Size = UDim2.fromOffset(12, 12) }, TweenInfo.new(0.3, Enum.EasingStyle.Back))
		end
	end

	-- overlay panel used for the tale of the tape and the corner / scorecard between rounds.
	-- Builders below add rows in order and return their height so the panel can be fitted between the
	-- scoreboard / letterbox and the ticker on any screen. On a phone the builders leave rows out instead
	-- of shrinking the panel (its text stays readable).
	local OVERLAY_W = 820
	overlay = UI.Frame(hud, { Name = "Overlay", Size = UDim2.new(1, -80, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromScale(0.5, 0.56), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 10 })
	UI.Glass(overlay, { transparency = 0.06, radius = UI.R.xl })
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(OVERLAY_W, 2000), Parent = overlay })
	local overlayPad = UI.New("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 22), PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28), Parent = overlay })
	UI.List(overlay, 6)
	local overlayFit = UI.New("UIScale", { Name = "Fit", Parent = overlay })
	local OV = { order = 0, h = 0 }

	local function overlayWidth()
		local canvas = UI.CanvasSize(hud)
		return math.min(OVERLAY_W, canvas.X - 80) - 56
	end

	local function ovAdd(h)
		OV.order += 1
		OV.h += h + 6
		return OV.order
	end

	function overlayBegin()
		UI.Clear(overlay)
		local small = UI.CanvasSize(hud).Y < 640
		overlayPad.PaddingTop = UDim.new(0, small and 12 or 20)
		overlayPad.PaddingBottom = UDim.new(0, small and 12 or 22)
		OV.order, OV.h = 0, (small and 24 or 42) - 6
	end

	-- place the panel in the room between the scoreboard (or the letterbox) and the ticker; it only
	-- shrinks a little (a phone gets fewer rows instead)
	local function fitOverlay()
		local canvas = UI.CanvasSize(hud)
		local top = L.frame.Visible and (10 + board.AbsoluteSize.Y / math.max(0.01, UI.ScaleOf(hud)) + 8) or math.floor(canvas.Y * 0.08) + 10
		local bottom = (ticker.Visible and 66) or 14
		local avail = math.max(140, canvas.Y - top - bottom)
		overlayFit.Scale = math.clamp(avail / math.max(1, OV.h), canvas.Y < 640 and 0.94 or 0.7, 1)
		overlay.Position = UDim2.new(0.5, 0, 0, math.floor(top + avail / 2))
	end
	function overlayShow()
		fitOverlay()
		overlay.Visible = true
	end

	function ovHead(kicker, title, color)
		local small = UI.CanvasSize(hud).Y < 640
		local h = small and 46 or 62
		local f = UI.Frame(overlay, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
		local k = UI.Frame(f, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 })
		UI.List(k, 8, true, Enum.HorizontalAlignment.Center)
		UI.Frame(k, { Size = UDim2.fromOffset(18, 2), BackgroundColor3 = color or T.gold, LayoutOrder = 1 })
		UI.Text(k, string.upper(kicker or ""), { Font = T.semi, TextSize = 13, TextColor3 = color or T.gold, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
		UI.Frame(k, { Size = UDim2.fromOffset(18, 2), BackgroundColor3 = color or T.gold, LayoutOrder = 3 })
		UI.Text(f, string.upper(title or ""), { Face = "display", TextSize = small and 28 or 36, Position = UDim2.fromOffset(0, small and 16 or 18), Size = UDim2.new(1, 0, 0, small and 30 or 42), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		return f
	end

	-- red corner vs blue corner: flags, names, nicknames
	function ovVersus(you, opp)
		local small = UI.CanvasSize(hud).Y < 640
		local h = small and 48 or 62
		local f = UI.Frame(overlay, { Name = "Versus", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
		local fl = getFlags()
		for i, t in ipairs({ you, opp }) do
			local left = i == 1
			local accent = left and T.red or T.blue
			local side = UI.Frame(f, { Name = left and "Red" or "Blue", BackgroundColor3 = accent, BackgroundTransparency = 0.84, Size = UDim2.new(0.5, -44, 1, 0),
				Position = left and UDim2.fromScale(0, 0) or UDim2.new(0.5, 44, 0, 0) })
			UI.Corner(side, UI.R.md)
			UI.Gradient(side, Color3.new(1, 1, 1), left and 0 or 180, NumberSequence.new(0, 0.6))
			UI.Frame(side, { Size = UDim2.new(0, 4, 1, -14), Position = left and UDim2.fromOffset(0, 7) or UDim2.new(1, -4, 0, 7), BackgroundColor3 = accent })
			local flag = UI.Frame(side, { Name = "Flag", BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 22), Position = left and UDim2.fromOffset(16, small and 4 or 9) or UDim2.new(1, -50, 0, small and 4 or 9) })
			if fl and t.nat then
				pcall(fl.Draw, flag, t.nat, { Size = UDim2.fromOffset(34, 22) })
			end
			local x = left and 60 or 14
			UI.Text(side, string.upper(t.name or ""), { Face = "display", TextSize = small and 22 or 26, Position = UDim2.fromOffset(x, small and 0 or 4), Size = UDim2.new(1, -74, 0, small and 28 or 32), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			local nick = (t.nick and t.nick ~= "") and ('"' .. string.upper(t.nick) .. '"') or string.upper(t.nat or "")
			UI.Text(side, nick, { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(left and 16 or 14, small and 28 or 38), Size = UDim2.new(1, -30, 0, 18), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		UI.Text(f, "VS", { Face = "display", TextSize = small and 26 or 32, TextColor3 = T.gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(80, 40),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		return f
	end

	-- a comparison row: left value | caption | right value (emphasis = big gold / red numbers)
	local function tapeRow(parent, a, caption, b, order, emphasis)
		local h = emphasis and 40 or 32
		local f = UI.Frame(parent, { Name = "Row", BackgroundColor3 = T.panel2, BackgroundTransparency = order % 2 == 0 and 0.55 or 0.8, Size = UDim2.new(1, 0, 0, h), LayoutOrder = order })
		UI.Corner(f, 4)
		local face = emphasis and "number" or "displayMed"
		local size = emphasis and 28 or 19
		UI.Text(f, tostring(a), { Face = face, TextSize = size, TextColor3 = emphasis and T.gold or T.text, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.38, -14, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(f, string.upper(caption), { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromScale(0.38, 0), Size = UDim2.new(0.24, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(f, tostring(b), { Face = face, TextSize = size, TextColor3 = emphasis and T.gold or T.text, Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, -14, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		return f, h
	end

	function ovRow(a, caption, b, emphasis)
		local h = emphasis and 40 or 32
		local order = ovAdd(h)
		return tapeRow(overlay, a, caption, b, order, emphasis)
	end

	-- a wrapped line of copy (weigh-in, scouting, cutman); color tints a small tag in front
	function ovNote(tag, text, color)
		local w = overlayWidth()
		local chars = #tag + #text + 4
		local lines = math.max(1, math.ceil(chars * 8 / math.max(200, w - 16)))
		local h = lines * 20 + 10
		local f = UI.Frame(overlay, { Name = "Note", BackgroundColor3 = color or T.panel2, BackgroundTransparency = 0.86, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
		UI.Corner(f, 4)
		UI.Text(f, string.format('<font color="#%s"><b>%s</b></font>   %s', (color or T.gold):ToHex(), string.upper(tag), text), {
			RichText = true, Font = T.font, TextSize = 15, TextColor3 = T.text, Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 1, -10), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
		return f
	end

	-- a quote with a coloured rule (corner advice, trash talk)
	function ovQuote(text, who, color)
		local w = overlayWidth()
		local body = '"' .. text .. '"' .. (who and ("   -  " .. who) or "")
		local lines = math.max(1, math.ceil(#body * 8 / math.max(200, w - 30)))
		local h = lines * 20 + 12
		local f = UI.Frame(overlay, { Name = "Quote", BackgroundColor3 = T.panel2, BackgroundTransparency = 0.6, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
		UI.Corner(f, 4)
		UI.Frame(f, { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = color or T.gold })
		UI.Text(f, body, { Font = T.font, TextSize = 15, TextColor3 = T.text, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -28, 1, -12), AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
		return f
	end

	-- the score: both corners' totals, big, with a caption between them
	function ovScore(a, b, caption, you, opp)
		local small = UI.CanvasSize(hud).Y < 640
		local h = small and 56 or 72
		local f = UI.Frame(overlay, { Name = "Score", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
		for i, v in ipairs({ a, b }) do
			local left = i == 1
			local accent = left and T.red or T.blue
			local lead = (left and a > b) or (not left and b > a)
			local side = UI.Frame(f, { BackgroundColor3 = accent, BackgroundTransparency = 0.84, Size = UDim2.new(0.5, -64, 1, 0), Position = left and UDim2.fromScale(0, 0) or UDim2.new(0.5, 64, 0, 0) })
			UI.Corner(side, UI.R.md)
			UI.Frame(side, { Size = UDim2.new(0, 4, 1, -16), Position = left and UDim2.fromOffset(0, 8) or UDim2.new(1, -4, 0, 8), BackgroundColor3 = accent })
			UI.Text(side, string.upper(left and you or opp), { Face = "displayMed", TextSize = 18, Position = UDim2.fromOffset(left and 16 or 90, 0), Size = UDim2.new(1, -106, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.Text(side, tostring(v), { Face = "number", TextSize = small and 44 or 54, TextColor3 = lead and T.gold or T.text, AnchorPoint = Vector2.new(left and 1 or 0, 0.5),
				Position = left and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(78, h - 8), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = left and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, TextWrapped = false })
		end
		UI.Text(f, caption, { Font = T.semi, TextSize = 13, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(120, 44),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		return f
	end

	-- round-by-round strip: R1 10-9 ... (red / blue underline for who took the round)
	function ovRounds(cards, rounds, current)
		local n = math.max(1, rounds or 1)
		local f = UI.Frame(overlay, { Name = "Rounds", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = ovAdd(48) })
		UI.List(f, 4, true, Enum.HorizontalAlignment.Center)
		local w = overlayWidth()
		local cellW = math.clamp(math.floor((w - (n - 1) * 4) / n), 40, 72)
		for i = 1, n do
			local c = cards[i]
			local cell = UI.Frame(f, { Size = UDim2.fromOffset(cellW, 48), BackgroundColor3 = i == current and T.panel2:Lerp(T.gold, 0.12) or T.panel2, BackgroundTransparency = c and 0.15 or 0.7, LayoutOrder = i })
			UI.Corner(cell, 4)
			UI.Text(cell, "R" .. i, { Font = T.semi, TextSize = 13, TextColor3 = i == current and T.gold or T.sub, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 2),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
			UI.Text(cell, c and string.format("%d-%d", c[1], c[2]) or "-", { Face = "number", TextSize = 18, TextColor3 = c and T.text or T.dim, Position = UDim2.fromOffset(0, 18),
				Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
			if c then
				local col = c[1] > c[2] and T.red or (c[2] > c[1] and T.blue or T.sub)
				UI.Frame(cell, { Position = UDim2.new(0, 4, 1, -4), Size = UDim2.new(1, -8, 0, 3), BackgroundColor3 = col })
			end
		end
		return f
	end

	-- the player's condition between rounds: head and body with their permanent caps
	function ovCondition(c)
		local f = UI.Frame(overlay, { Name = "Condition", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = ovAdd(40) })
		for i, spec in ipairs({ { "HEAD", c.head, c.cap }, { "BODY", c.body, c.bodyCap } }) do
			local v, cap = tonumber(spec[2]) or 0, tonumber(spec[3]) or 100
			local cell = UI.Frame(f, { BackgroundTransparency = 1, Position = UDim2.new((i - 1) * 0.5, i == 2 and 8 or 0, 0, 0), Size = UDim2.new(0.5, -8, 1, 0) })
			UI.Text(cell, spec[1] .. "  " .. math.floor(v + 0.5), { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
			UI.Text(cell, cap < 100 and string.format("MAX %d", cap) or "", { Font = T.semi, TextSize = 13, TextColor3 = T.red, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			local color = rampColor(v / 100)
			local bar = hudBar(cell, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16) }, color, "L", nil, true)
			setBar(bar, v / 100, cap / 100, color)
		end
		return f
	end

	-- the knockdown count: a band with the referee's count, big (a phone gets its own sizes, not a UIScale)
	countBox = UI.Frame(hud, { Name = "Count", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(520, 230), BackgroundTransparency = 1, Visible = false, ZIndex = 22 })
	countKicker, countKickerText = UI.Chip(countBox, "KNOCKDOWN", T.red, { solid = true, textColor = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), h = 28, TextSize = 15 })
	countKicker.ZIndex = 23
	countNum = UI.Text(countBox, "", { Face = "display", TextSize = 150, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 160),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 23 })
	local countScale = UI.New("UIScale", { Parent = countNum })
	countWho = UI.Text(countBox, "", { Face = "displayMed", TextSize = 22, TextColor3 = T.text, TextStrokeTransparency = 0.5, Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 23 })
	-- kicker: "KNOCKDOWN" / "EIGHT COUNT" ...; who: the line under the number
	function openCount(kicker, color, who)
		-- the count takes the middle of the screen: a crowd strip that is still up gives way
		crowdStrip.Visible = false
		countKickerText.Text = string.upper(kicker)
		countKicker.BackgroundColor3 = color or T.red
		countWho.Text = who or ""
		countNum.Text = ""
		countBox.Visible = true
	end
	function showCount(n, standing)
		crowdStrip.Visible = false
		countBox.Visible = true
		countNum.Text = tostring(n)
		countNum.TextColor3 = standing and Color3.fromRGB(230, 230, 230) or (n >= 8 and T.red or Color3.new(1, 1, 1))
		countScale.Scale = 1.35
		UI.Tween(countScale, { Scale = 1 }, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end
	function hideCount()
		countBox.Visible = false
	end

	------------------------------------------------------------------------
	-- Get-up: mash SPACE / tap, and time presses on the sweeping marker (green zone = worth 3)
	------------------------------------------------------------------------
	getup = UI.Frame(hud, { Name = "GetUp", Size = UDim2.fromOffset(560, 160), Position = UDim2.new(0.5, 0, 0.64, 0), AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 24 })
	UI.Glass(getup, { transparency = 0.05, radius = UI.R.xl, stroke = T.red, strokeT = 0.3 })
	getupTitle = UI.Text(getup, "YOU'RE DOWN!  MASH SPACE / TAP - HIT THE GREEN ZONE", { Face = "displayMed", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 26), TextColor3 = T.red, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = true, ZIndex = 25 })
	UI.New("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 16, Parent = getupTitle })
	local getupBarBg
	getupBarBg, setGetup = UI.Bar(getup, { Position = UDim2.fromOffset(24, 48), Size = UDim2.new(1, -48, 0, 20), ZIndex = 25 }, T.gold)
	local timing = UI.Frame(getup, { Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 26), BackgroundColor3 = T.ink, ZIndex = 25 })
	UI.Corner(timing, 6)
	zone = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.2, ZIndex = 26 })
	UI.Corner(zone, 6)
	marker = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.2), Size = UDim2.new(0, 5, 1.4, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 27 })
	UI.Corner(marker, 2)
	getupHint = UI.Text(getup, "", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(12, 118), Size = UDim2.new(1, -24, 0, 30),
		AutomaticSize = Enum.AutomaticSize.None, ZIndex = 25 })

	function getupPress()
		if not F.down then
			return
		end
		local m = F.markerPos or 0
		local good = math.abs(m - 0.5) <= (F.zoneW or 0.2) / 2
		F.mash += good and 3 or 1
		send({ t = "mash", good = good })
		zone.BackgroundColor3 = good and Color3.fromRGB(120, 255, 150) or T.red
		task.delay(0.12, function()
			zone.BackgroundColor3 = T.green
		end)
		setGetup(F.mash / math.max(1, F.target))
	end

	local getupBtn = UI.Button(getup, "", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 28 }, getupPress)
	getupBtn.Text = ""
	getupBtn.Selectable = false -- a gamepad mashes A through the fight bindings, not the UI selection

	-- responsive layout: short (phone) canvases get the slim scoreboard and their own sizes for the count
	-- and the get-up panel, placed so they never overlap (count under the board, get-up under the count)
	function layoutHud()
		local canvas = UI.CanvasSize(hud)
		local compact = canvas.Y < 640
		compactHud = compact
		if F.resting and overlay.Visible then
			-- between rounds on a phone the scorecard needs the room; the scoreboard returns with the bell
			L.frame.Visible, R.frame.Visible, clock.Visible = not compact, not compact, not compact
		end
		local bh = compact and BOARD_H_COMPACT or BOARD_H
		board.Size = UDim2.new(1, compact and -20 or -40, 0, bh)
		board.Position = UDim2.new(0.5, 0, 0, compact and 6 or 10)
		boardMax.MaxSize = Vector2.new(1380, bh)
		layoutPanel(L, compact)
		layoutPanel(R, compact)
		local clockW = compact and 132 or 176
		clock.Size = UDim2.new(0, clockW, 1, 0)
		L.frame.Size = UDim2.new(0.5, -(clockW / 2 + 8), 1, 0)
		R.frame.Size = UDim2.new(0.5, -(clockW / 2 + 8), 1, 0)
		clockTop.Size = UDim2.new(1, 0, 0, compact and 22 or 30)
		UI.SetTextSize(roundText, compact and 15 or 18)
		timeText.Position = UDim2.fromOffset(0, compact and 20 or 32)
		timeText.Size = UDim2.new(1, 0, 0, compact and 34 or 56)
		UI.SetTextSize(timeText, compact and 32 or 50)
		crowdBox.Position = UDim2.new(0, 12, 1, compact and -12 or -46)
		crowdBox.Size = UDim2.new(1, -24, 0, compact and 10 or 40)
		crowdBar.Size = UDim2.new(1, 0, 0, compact and 6 or 8)
		crowdLabel.Visible = not compact
		local below = (compact and 6 or 10) + bh
		hudTop = below
		-- the key strip: punches over defence on a short screen
		for i, item in ipairs(ctlItems) do
			item.Parent = (compact and i > 7) and ctlRows[2] or ctlRows[1]
		end
		ctlRows[2].Visible = compact
		ctlRows[3].Visible = #ctlRows[3]:GetChildren() > 1
		-- the corner bug outside rounds (in rounds the clock carries the LIVE tag); a phone's scorecard
		-- needs the corner
		bug.Visible = bug:GetAttribute("On") == true and not clock.Visible and not (compact and overlay.Visible)
		liveTag.Size = UDim2.fromOffset(0, compact and 16 or 20)
		layoutClockTop()
		angleTag.Position = UDim2.new(0.5, 0, 0, below + (compact and 8 or 32))
		-- the crowd strip sits under the angle tag's line (both can show at once)
		crowdStrip.Position = UDim2.new(0.5, 0, 0, below + (compact and 40 or 66))
		crowdStrip.Size = UDim2.fromOffset(compact and 420 or 560, compact and 38 or 48)
		UI.SetTextSize(crowdStripText, compact and 21 or 28)
		-- the count under the board; the get-up panel under the count (or at the bottom)
		local countH = compact and 150 or 230
		countBox.Size = UDim2.fromOffset(compact and 420 or 520, countH)
		UI.SetTextSize(countNum, compact and 92 or 150)
		countNum.Size = UDim2.new(1, 0, 0, compact and 98 or 160)
		countNum.Position = UDim2.fromOffset(0, compact and 26 or 26)
		countWho.Position = UDim2.new(0, 0, 1, compact and -28 or -34)
		UI.SetTextSize(countWho, compact and 18 or 22)
		local countTop = compact and (below + 6) or math.floor(canvas.Y * 0.42 - countH / 2)
		countBox.Position = UDim2.new(0.5, 0, 0, countTop)
		local getupH = compact and 136 or 160
		getup.Size = UDim2.fromOffset(compact and 500 or 560, getupH)
		getupBarBg.Position, getupBarBg.Size = UDim2.fromOffset(24, compact and 42 or 48), UDim2.new(1, -48, 0, compact and 16 or 20)
		timing.Position, timing.Size = UDim2.fromOffset(24, compact and 66 or 80), UDim2.new(1, -48, 0, compact and 24 or 26)
		getupHint.Position = UDim2.fromOffset(12, compact and 96 or 118)
		getupHint.Size = UDim2.new(1, -24, 0, compact and 34 or 30)
		local getupTop = math.max(countTop + countH + 6, canvas.Y - getupH - (compact and 10 or 90))
		if not compact then
			getupTop = math.floor(canvas.Y * 0.64)
		end
		getup.Position = UDim2.new(0.5, 0, 0, getupTop)
		banner.TextSize = compact and 68 or 96
		bannerBand.Size = UDim2.new(1, 0, 0, compact and 90 or 120)
		if overlay.Visible then
			if F.overlayBuild and F.overlayCompact ~= compact then
				F.overlayBuild()
			end
			fitOverlay()
		end
		if refreshControls then
			refreshControls()
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
	hud:GetAttributeChangedSignal("UIScale"):Connect(layoutHud)
	layoutHud()

	-- punches go through throwPunch (defined with the input code) so taps are predicted like keys;
	-- pickHook decides which hand a HOOK tap throws (the one that did not just punch)

	-- touch controls (phones / tablets): a 2 x 2 punch cluster at the bottom right (HOOK / UPPER over JAB /
	-- CROSS) with OVERHAND and a BODY toggle over it, the unlocked special moves in a grid left of it, and
	-- the defence on the left edge above the thumbstick: BLOCK (tap toggle; swipe left / right on it to slip,
	-- down to roll under, up to parry, hold it and swipe down for the quick dodge) and CLINCH (tap; swipe
	-- left / right to pivot). A slip followed by JAB / CROSS within half a second is the counter jab / cross.
	-- MOVES (top left) opens the Moves & Controls menu. Big, semi-transparent round pads (64 pt and up);
	-- every target is at least a fingertip (UI.MinHit) on screen.
	local function roundPad(parent, name, text, color, size, pos, anchor)
		local b = UI.New("TextButton", { Name = name, Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = T.bg, BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(size, size), Position = pos, AnchorPoint = anchor or Vector2.new(0.5, 0.5), Parent = parent })
		UI.Corner(b, math.floor(size / 2))
		b.Selectable = false
		UI.New("UIStroke", { Color = color, Thickness = 2.5, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		UI.Text(b, text, { Face = "displayMed", TextSize = size >= 80 and 20 or 17, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		return b
	end

	-- a touch on a pad: swipes are read off the start point; onSwipe(dir, heldFor) fires once per touch for a
	-- swipe ("L" / "R" / "U" / "D"), onTap(swiped) on the release. The finger is followed through the global
	-- input events too (a swipe can leave the pad before it is long enough, and its release still counts)
	local function swipePad(b, onBegin, onSwipe, onTap)
		local cur
		local function isPress(input)
			return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
		end
		local function finish()
			local c = cur
			cur = nil
			if c and onTap then
				onTap(c.swiped)
			end
		end
		local function moved(input)
			local c = cur
			if not c or c.swiped then
				return
			end
			-- the touch's own InputObject, or the mouse moving while the button that began it is down
			local mine = input == c.input or (c.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
			if not mine then
				return
			end
			local dx, dy = input.Position.X - c.x, input.Position.Y - c.y
			local th = 36 * UI.ScaleOf(hud)
			if math.abs(dx) > th or math.abs(dy) > th then
				c.swiped = true
				local dir = math.abs(dx) >= math.abs(dy) and (dx < 0 and "L" or "R") or (dy > 0 and "D" or "U")
				onSwipe(dir, os.clock() - c.at)
			end
		end
		b.InputBegan:Connect(function(input)
			if isPress(input) then
				cur = { input = input, x = input.Position.X, y = input.Position.Y, at = os.clock(), swiped = false }
				if onBegin then
					onBegin()
				end
			end
		end)
		b.InputChanged:Connect(moved)
		UserInputService.InputChanged:Connect(moved)
		-- (the pad's own release of that kind of press ends it: a mouse button's InputObject need not be the
		-- same one that began it; anywhere else only the touch's own InputObject does)
		b.InputEnded:Connect(function(input)
			if cur and isPress(input) and (input == cur.input or input.UserInputType == cur.input.UserInputType) then
				finish()
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if cur and input == cur.input then
				finish()
			end
		end)
	end

	-- the unlocked special moves (setTouchSpecials, from the fight's start message): a grid of gold pads left
	-- of the punch cluster, up to three a row, filled from the bottom right so a short list hugs the punches.
	-- KM.paintSpecials dims a pad while the shared cooldown runs or the gas is not there for it
	local touchSpecials
	KM.specialPads = {}
	function setTouchSpecials(list)
		table.clear(KM.specialPads)
		if not touchSpecials then
			return
		end
		UI.Clear(touchSpecials)
		list = list or {}
		local cell = math.max(50, UI.MinHit(touchPad))
		local gap = 6
		local cols = math.min(3, #list)
		local rows = math.ceil(#list / math.max(1, cols))
		touchSpecials.Size = UDim2.fromOffset(cols * cell + math.max(0, cols - 1) * gap, rows * cell + math.max(0, rows - 1) * gap)
		for i, id in ipairs(list) do
			local a = Keymap.ById["special_" .. id]
			-- rows from the bottom up; inside a row the moves read left to right, the row hugging the punches
			local row = math.floor((i - 1) / cols)
			local inRow = math.min(cols, #list - row * cols)
			local col = inRow - 1 - (i - 1) % cols
			local b = roundPad(touchSpecials, "Special_" .. id, a and a.touch or id:upper(), T.gold, cell, UDim2.new(1, -col * (cell + gap), 1, -row * (cell + gap)), Vector2.new(1, 1))
			b.LayoutOrder = i
			local lbl = b:FindFirstChildOfClass("TextLabel")
			if lbl then
				-- one line, never broken inside a word (the touch names are short: CHECK, SHELL, L.UPPER)
				lbl.TextWrapped = false
				UI.SetTextSize(lbl, 13)
			end
			b.MouseButton1Down:Connect(function()
				throwSpecial(id)
			end)
			KM.specialPads[id] = { pad = b, label = lbl, stroke = b:FindFirstChildOfClass("UIStroke") }
		end
		KM.paintSpecials()
	end

	-- the specials' readiness on the touch pads and the strip's caps: the shared cooldown and the gas each needs
	function KM.paintSpecials()
		local now = os.clock()
		local stam = F.me and tonumber(F.me.stam)
		for id, v in pairs(KM.specialPads) do
			local M = Moves.Data[id]
			local ready = M ~= nil and now >= (F.specialReady or 0) and not (stam and stam < M.stam)
			if v.pad then
				v.pad.BackgroundTransparency = ready and 0.35 or 0.7
				if v.stroke then
					v.stroke.Color = ready and T.gold or T.dim
				end
			end
			if v.label then
				v.label.TextTransparency = ready and 0 or 0.5
			end
			if v.stripLabel then
				v.stripLabel.TextColor3 = ready and T.gold or T.dim
				v.stripStroke.Color = ready and T.gold or T.dim
			end
		end
	end

	local movesPad
	function buildTouch()
		if touchPad or not UserInputService.TouchEnabled then
			return
		end
		touchPad = UI.Frame(hud, { Name = "TouchPad", BackgroundTransparency = 1, Size = UDim2.fromOffset(204, 262), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12) })
		local P = 90 -- pad size (design px: 70 pt on a phone)
		local function punchPad(text, p, pos)
			local b = roundPad(touchPad, "Punch" .. text, text, T.red, P, pos)
			b.MouseButton1Down:Connect(function()
				local kind = p == "hook" and pickHook() or p
				-- straight out of a slip on the BLOCK pad: the counter jab / cross
				local counter = (kind == "jab" or kind == "cross") and os.clock() - (KM.touchSlipAt or -10) < 0.5
				if counter then
					KM.touchSlipAt = -10
				end
				throwPunch(kind, Tog.on.body and kind ~= "overhand", counter or nil)
			end)
			return b
		end
		punchPad("HOOK", "hook", UDim2.fromOffset(52, 106))
		punchPad("UPPER", "uppercut", UDim2.fromOffset(152, 106))
		punchPad("JAB", "jab", UDim2.fromOffset(52, 210))
		punchPad("CROSS", "cross", UDim2.fromOffset(152, 210))
		touchSpecials = UI.Frame(touchPad, { Name = "Specials", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0, -10, 1, 0), Size = UDim2.fromOffset(0, 0) })
		-- the top row: OVERHAND and the BODY toggle, a fingertip tall
		local rowH = math.max(40, UI.MinHit(touchPad))
		local overBtn = UI.Button(touchPad, "OVERHAND", { Name = "Overhand", Size = UDim2.fromOffset(98, rowH), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(0, 56),
			BackgroundColor3 = T.bg, BackgroundTransparency = 0.35, TextSize = 15 })
		overBtn.Selectable = false
		UI.Stroke(overBtn, T.red, 2, 0.15)
		overBtn.MouseButton1Down:Connect(function()
			throwPunch("overhand", false)
		end)
		local bodyBtn = UI.Button(touchPad, "BODY", { Name = "Body", Size = UDim2.fromOffset(98, rowH), AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(204, 56),
			BackgroundColor3 = T.bg, BackgroundTransparency = 0.35, TextSize = 16 })
		bodyBtn.Selectable = false
		UI.Stroke(bodyBtn, T.orange, 2, 0.15)
		-- a tap arms the next punch to the body (lit orange); it clears after that punch or on a second tap
		bodyBtn.MouseButton1Down:Connect(function()
			Tog.press("body")
			showFlash(flash, Tog.on.body and "NEXT PUNCH: BODY" or "HEAD SHOTS", T.gold)
		end)
		bodyBtn.MouseButton1Up:Connect(function()
			Tog.release("body")
		end)
		table.insert(Tog.views, function(name, on)
			if name == "body" then
				bodyBtn.BackgroundColor3 = on and T.orange or T.bg
				bodyBtn.BackgroundTransparency = on and 0 or 0.35
				bodyBtn.TextColor3 = on and T.ink or T.text
			end
		end)
		defencePad = UI.Frame(hud, { Name = "DefencePad", BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 214), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.56, 0) })
		-- CLINCH: a tap ties him up (on the release, so a swipe can be a pivot instead)
		local clinch = roundPad(defencePad, "Clinch", "CLINCH\n< PIVOT >", T.green, 76, UDim2.fromOffset(55, 38))
		UI.SetTextSize(clinch:FindFirstChildOfClass("TextLabel"), 15)
		swipePad(clinch, nil, function(dir)
			if dir == "L" or dir == "R" then
				send({ t = "pivot", dir = dir == "L" and -1 or 1 })
			end
		end, function(swiped)
			if not swiped then
				send({ t = "clinch" })
			end
		end)
		-- BLOCK: tap to raise the guard, tap again to drop it (a long press still blocks while held); swipes are
		-- the head movement
		local block = roundPad(defencePad, "Block", "BLOCK\n< SLIP >", T.blue, 104, UDim2.fromOffset(55, 158))
		for _, h in ipairs({ { "PARRY", 0, -60 }, { "ROLL", 0, 60 } }) do
			UI.Text(block, h[1], { Name = "Hint" .. h[1], Font = T.semi, TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, h[2], 0.5, h[3]),
				Size = UDim2.fromOffset(80, 16), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		end
		table.insert(Tog.views, function(name, on)
			if name == "block" then
				block.BackgroundColor3 = on and T.blue or T.bg
				block.BackgroundTransparency = on and 0.1 or 0.35
			end
		end)
		swipePad(block, function()
			Tog.press("block")
		end, function(dir, heldFor)
			-- a swipe is a defence move, not a guard tap: the guard the press raised goes down again (told to
			-- the server too, in case the move is refused there)
			Tog.pressedAt.block = nil
			Tog.set("block", false)
			if dir == "L" or dir == "R" then
				KM.touchSlipAt = os.clock()
				send({ t = "slip", dir = dir == "L" and -1 or 1 })
			elseif dir == "D" then
				-- held first (the guard was up as a hold): the quick dodge, else the full roll
				send({ t = "roll", quick = heldFor >= Tog.HOLD or nil })
			else
				send({ t = "parry" })
			end
		end, function(swiped)
			if not swiped then
				Tog.release("block")
			end
		end)
		-- MOVES: the Moves & Controls menu (it pauses a solo fight), under the left board, right of CLINCH
		movesPad = UI.Button(hud, "MOVES", { Name = "MovesPad", Size = UDim2.fromOffset(96, math.max(40, UI.MinHit(hud))), Position = UDim2.fromOffset(132, hudTop + 8),
			BackgroundColor3 = T.bg, BackgroundTransparency = 0.35, TextSize = 15, Visible = false })
		movesPad.Selectable = false
		UI.Stroke(movesPad, T.gold, 2, 0.2)
		movesPad.MouseButton1Down:Connect(function()
			openMoves()
		end)
		controls.Visible = false
	end

	-- what shows when: the key strip for the first 10 s of the fight, while H (VIEW on a pad) is held, or
	-- always (the ControlHints setting); the touch pads only in a live round and not while you are down
	-- (the get-up panel takes over); on a phone the commentary ticker leaves the picture during rounds.
	-- The strip names keys or pad buttons by the device in use; a device with both touch and keys shows the
	-- pads after a touch and the strip after a key press (Gamepad.Mode)
	holdH = false
	function refreshControls()
		local live = F.active == true and not F.resting and not F.down and not F.paused and not F.countdown and not F.menuPaused
		local mode = Gamepad and Gamepad.Mode() or "keyboard"
		local touchUI = touchPad ~= nil and mode ~= "gamepad" and (mode == "touch" or not UserInputService.KeyboardEnabled)
		local keyboard = not touchUI
		local show = live and keyboard and (holdH or os.clock() < controlsUntil or player:GetAttribute("ControlHints") == true)
		if controls.Visible ~= show then
			controls.Visible = show
		end
		local hint = live and keyboard and not show and not compactHud
		if controlsHint.Visible ~= hint then
			controlsHint.Visible = hint
		end
		if touchPad then
			local pads = live and touchUI
			if touchPad.Visible ~= pads then
				touchPad.Visible = pads
				defencePad.Visible = pads
			end
			-- the menu pad: whenever the fight HUD is up on touch (between rounds too), not while down
			local mp = touchUI and gui.Enabled and not F.down and not F.menuPaused
			movesPad.Visible = mp
			movesPad.Position = UDim2.fromOffset(132, hudTop + 8)
		end
		-- the commentary leaves the picture during rounds on a phone, and wherever the touch pads are up
		-- (the punch cluster sits on the ticker's corner on a tablet)
		local tick = not ((compactHud or (touchPad ~= nil and touchPad.Visible)) and F.active == true and not F.resting)
		if ticker.Visible ~= tick then
			ticker.Visible = tick
		end
	end

end


------------------------------------------------------------------------
-- Round countdown (3 - 2 - 1 - BOX!) and the stance chips (GUARD UP / BODY), on the HUD root so they
-- scale with the phone / tablet / desktop layouts. The server sends one "countdown" beat per number.
------------------------------------------------------------------------
local Countdown = {}
do
	local holder = UI.Frame(hud, { Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(600, 260),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30 })
	local scale = UI.New("UIScale", { Parent = holder })
	local num = UI.Text(holder, "", { Name = "Number", Face = "display", TextSize = 200, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 31 })
	local sub = UI.Text(holder, "", { Name = "Sub", Font = T.semi, TextSize = 22, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, 0, 0, 28), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 31 })
	Countdown.holder, Countdown.label = holder, num
	local seq = 0
	function Countdown.Show(n, round)
		seq += 1
		local id = seq
		holder.Visible = true
		local go = n <= 0
		num.Text = go and (F.spar and "FIGHT!" or "BOX!") or tostring(n)
		num.TextColor3 = go and T.gold or Color3.new(1, 1, 1)
		sub.Text = go and "" or ((round and round > 0) and ("ROUND " .. round .. "  ·  IN YOUR CORNER") or "IN YOUR CORNER")
		num.TextTransparency = 0
		-- punch in: big and fast, then settle (GO hits harder and fades out)
		scale.Scale = go and 2.2 or 1.8
		UI.Tween(scale, { Scale = go and 1.15 or 1 }, TweenInfo.new(go and 0.3 or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		if go then
			local bell = Config.SoundSpec and Config.SoundSpec("RingBell")
			if bell and bell.id then
				sfx(bell.id, bell.speed or 1, math.clamp(bell.volume or 0.8, 0.2, 1))
			else
				local ping = BUILTIN.Ping or "rbxasset://sounds/electronicpingshort.wav"
				for i = 0, 1 do
					task.delay(i * 0.22, function()
						if gui.Enabled then
							sfx(ping, 0.6, 0.75)
						end
					end)
				end
			end
		else
			sfx(BUILTIN.Click or "rbxasset://sounds/clickfast.wav", 0.8 + (3 - n) * 0.12, 0.7)
		end
		task.delay(go and 0.75 or 0.62, function()
			if seq == id then
				UI.Tween(num, { TextTransparency = 1 }, 0.18)
				task.delay(0.2, function()
					if seq == id then
						holder.Visible = false
					end
				end)
			end
		end)
	end
	function Countdown.Hide()
		seq += 1
		holder.Visible = false
	end

	-- stance chips: what is toggled on right now, always visible in a live round (on every device)
	local chips = UI.Frame(hud, { Name = "StanceChips", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 12 })
	UI.List(chips, 8, true, Enum.HorizontalAlignment.Center)
	local guardChip = UI.Chip(chips, "GUARD UP", T.blue, { order = 1, h = 30, TextSize = 15 })
	local bodyChip = UI.Chip(chips, "BODY SHOT ARMED", T.orange, { order = 2, h = 30, TextSize = 15 })
	guardChip.Name, bodyChip.Name = "GuardChip", "BodyChip"
	guardChip.Visible, bodyChip.Visible = false, false
	table.insert(Tog.views, function(name, on)
		if name == "block" then
			guardChip.Visible = on
		elseif name == "body" then
			bodyChip.Visible = on
		end
	end)

	-- the round held by the Moves & Controls menu (handlers.pause)
	local pausedChip = UI.Chip(hud, "ROUND PAUSED  ·  MOVES & CONTROLS", T.gold, { solid = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), h = 30, TextSize = 15 })
	pausedChip.Name = "PausedChip"
	pausedChip.Visible = false
	function KM.showPaused(on)
		pausedChip.Visible = on == true
	end
end
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Screen FX layer (below the HUD): flashes, vignette, letterbox, blackout
------------------------------------------------------------------------
local fxGui = UI.New("ScreenGui", { Name = "FightFX", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, DisplayOrder = 4, Parent = player:WaitForChild("PlayerGui") })
local redFlash = UI.Frame(fxGui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 0, 0), BackgroundTransparency = 1, ZIndex = 2 })
local whiteFlash = UI.Frame(fxGui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 3 })
local blackout = UI.Frame(fxGui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 5 })
-- vignette: four edge panels with transparency ramps; they darken (and redden) with damage
local vignette = {}
for _, v in ipairs({
	{ UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 0.62), 270 },
	{ UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), 180 },
}) do
	local fr = UI.Frame(fxGui, { Size = v[1], Position = v[2], BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, ZIndex = 1 })
	local grad = UI.New("UIGradient", { Rotation = v[3], Transparency = NumberSequence.new(1), Parent = fr })
	table.insert(vignette, { frame = fr, grad = grad })
end
-- a swollen-shut eye darkens its half of the picture (the camera sits behind the fighter, so his left
-- eye is the screen's left); [1] = left eye, [2] = right eye
local eyeShade = {}
for i, v in ipairs({ { UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.5, 0), 180 } }) do
	local fr = UI.Frame(fxGui, { Name = i == 1 and "EyeL" or "EyeR", Size = UDim2.fromScale(0.5, 1), Position = v[1], BackgroundColor3 = Color3.fromRGB(14, 6, 10),
		BackgroundTransparency = 0, ZIndex = 1, Visible = false })
	local grad = UI.New("UIGradient", { Rotation = v[2], Transparency = NumberSequence.new(1), Parent = fr })
	eyeShade[i] = { frame = fr, grad = grad }
end
-- cinematic letterbox for walkouts, the tape, knockdowns and the final bell
local boxTop = UI.Frame(fxGui, { Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 6 })
local boxBottom = UI.Frame(fxGui, { Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 6 })
local letterboxOn = false
local function letterbox(on)
	if letterboxOn == on then
		return
	end
	letterboxOn = on
	local h = on and 0.1 or 0
	local ti = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(boxTop, ti, { Size = UDim2.fromScale(1, h) }):Play()
	TweenService:Create(boxBottom, ti, { Size = UDim2.fromScale(1, h) }):Play()
end

local function flashFrame(frame, from, dur)
	frame.BackgroundTransparency = from
	TweenService:Create(frame, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- post effects live on the camera (never collide with the gym's Lighting effects)
local blurFx, gradeFx
local function ensurePost()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if not (blurFx and blurFx.Parent == cam) then
		blurFx = cam:FindFirstChild("ConcussionBlur") or Instance.new("BlurEffect")
		blurFx.Name = "ConcussionBlur"
		blurFx.Size = 0
		blurFx.Parent = cam
	end
	if not (gradeFx and gradeFx.Parent == cam) then
		gradeFx = cam:FindFirstChild("ConcussionGrade") or Instance.new("ColorCorrectionEffect")
		gradeFx.Name = "ConcussionGrade"
		gradeFx.Saturation, gradeFx.Contrast, gradeFx.Brightness = 0, 0, 0
		gradeFx.TintColor = Color3.new(1, 1, 1)
		gradeFx.Parent = cam
	end
end
local function destroyPost()
	for _, inst in ipairs({ blurFx, gradeFx }) do
		if inst then
			inst:Destroy()
		end
	end
	blurFx, gradeFx = nil, nil
	local cam = workspace.CurrentCamera
	if cam then
		for _, n in ipairs({ "ConcussionBlur", "ConcussionGrade" }) do
			local e = cam:FindFirstChild(n)
			if e then
				e:Destroy()
			end
		end
	end
end

-- transient FX state (decays every frame)
local FX = { shake = 0, hitBlur = 0, fovKick = 0, roll = 0, rollVel = 0, hitStop = 0, grade = 0, heartAt = 0, downBlur = 0, vig = -1, vigTier = -1, eyeL = -1, eyeR = -1 }

-- how dark a swollen eye's side of the screen gets: nothing until the lid starts to close (0.45),
-- nearly black when it is shut (CONTRACTS 8: face damage 0..1), scaled by Config.ScreenFX
local function eyeDark(eye, fx)
	local a = math.clamp((eye - 0.45) * 1.8, 0, 0.9) * math.min(fx, 1.2)
	return math.floor(math.clamp(a, 0, 0.92) * 50 + 0.5) / 50
end
local VIG_RED, VIG_BLACK, WHITE = Color3.fromRGB(60, 0, 0), Color3.new(0, 0, 0), Color3.new(1, 1, 1)

------------------------------------------------------------------------
-- Sweat & blood spray (client-only emitters, Emit bursts) and blood drops on the canvas
------------------------------------------------------------------------
-- the soft round puff (not the 4-point sparkle star), squashed along the flight path into droplets
local SPRAY_TEX = "rbxasset://textures/particles/smoke_main.dds"
local function sprayEmitters(part)
	local att = part:FindFirstChild("FightSprayAtt")
	if att then
		return att, att:FindFirstChild("Sweat"), att:FindFirstChild("Blood")
	end
	att = Instance.new("Attachment")
	att.Name = "FightSprayAtt"
	att.Parent = part
	local function emitter(name, color, size, speed, life, accel, rate)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = name
		pe.Texture = SPRAY_TEX
		pe.Color = ColorSequence.new(color)
		-- sweat catches the ring lights (a wet glint); blood stays matte and dark
		pe.LightEmission = name == "Sweat" and 0.2 or 0
		pe.LightInfluence = 1
		pcall(function()
			pe.Brightness = name == "Sweat" and 1.5 or 1
			pe.Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, -0.6), NumberSequenceKeypoint.new(1, 0) })
			pe.Orientation = Enum.ParticleOrientation.VelocityParallel
		end)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, name == "Sweat" and 0.2 or 0), NumberSequenceKeypoint.new(1, 1) })
		pe.Speed = NumberRange.new(speed[1], speed[2])
		pe.Lifetime = NumberRange.new(life[1], life[2])
		pe.Acceleration = Vector3.new(0, accel, 0)
		pe.Drag = 2
		pe.SpreadAngle = Vector2.new(28, 28)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Rate = rate or 0
		pe.Enabled = true
		pe.Parent = att
		return pe
	end
	local sweat = emitter("Sweat", Color3.fromRGB(215, 235, 255), 0.09, { 8, 14 }, { 0.25, 0.45 }, -30)
	local blood = emitter("Blood", Color3.fromRGB(120, 8, 10), 0.11, { 5, 10 }, { 0.3, 0.55 }, -45)
	return att, sweat, blood
end

local bloodFolder
local function bloodDrop(model)
	if not F.arena or #(bloodFolder and bloodFolder:GetChildren() or {}) >= 12 then
		return
	end
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if not (bloodFolder and bloodFolder.Parent) then
		bloodFolder = Instance.new("Folder")
		bloodFolder.Name = "FightBlood"
		bloodFolder.Parent = workspace
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { bloodFolder }
	for _, m in ipairs({ player.Character, F.opp, F.ref }) do
		if m then
			table.insert(exclude, m)
		end
	end
	params.FilterDescendantsInstances = exclude
	local origin = root.Position + Vector3.new(math.random() * 1.6 - 0.8, 0, math.random() * 1.6 - 0.8)
	local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
	if not hit then
		return
	end
	local d = Instance.new("Part")
	d.Name = "BloodDrop"
	d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
	d.Shape = Enum.PartType.Cylinder
	local s = 0.25 + math.random() * 0.35
	d.Size = Vector3.new(0.02, s, s)
	d.Color = Color3.fromRGB(90 + math.random(0, 30), 6, 10)
	d.Material = Enum.Material.SmoothPlastic
	d.Reflectance = 0.05
	d.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.012, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	d.Parent = bloodFolder
end

local function spray(model, partName, dir, amount, bleed)
	local part = model and model:FindFirstChild(partName)
	if not part then
		return
	end
	local att, sweat, blood = sprayEmitters(part)
	if not att then
		return
	end
	local pos = part.Position
	-- point the attachment's up axis along the punch so EmissionDirection Top sprays off the far side
	att.WorldCFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
	local wet = (model:GetAttribute("Sweat") or 0.3) + 0.25
	if sweat then
		sweat:Emit(math.floor(4 + amount * 10 * wet))
	end
	if bleed and blood then
		blood:Emit(math.floor(2 + amount * 6))
		if math.random() < 0.35 + amount * 0.3 then
			bloodDrop(model)
		end
	end
end

------------------------------------------------------------------------
-- Ragdoll for the local character on an out-cold KO (the client owns its physics)
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Impact: the flash at the point of contact (a pooled emitter + light per hit part), the impact sound
-- layered by punch kind with its pitch and volume varied (never the same sound twice in a row), the
-- camera shake scaled by the punch's power, and the controller rumble
------------------------------------------------------------------------
local Impact = { TEX = "rbxasset://textures/particles/sparkles_main.dds", fx = {}, last = { id = nil, speed = 0 } } -- fx: part -> { att, emitter, light }
function Impact.flash(model, partName, strength, counter)
	local part = model and model:FindFirstChild(partName)
	if not part or fxScale() <= 0 then
		return
	end
	local fx = Impact.fx[part]
	if not (fx and fx.att.Parent) then
		local att = Instance.new("Attachment")
		att.Name = "FightImpactAtt"
		att.Parent = part
		local e = Instance.new("ParticleEmitter")
		e.Name = "ImpactFlash"
		e.Texture = Impact.TEX
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.1, 0.18)
		e.Speed = NumberRange.new(0, 0)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 214, 150))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = att
		local light = Instance.new("PointLight")
		light.Name = "ImpactLight"
		light.Brightness = 0
		light.Range = 7
		light.Color = Color3.fromRGB(255, 236, 200)
		light.Parent = att
		fx = { att = att, emitter = e, light = light }
		Impact.fx[part] = fx
	end
	strength = math.clamp(strength or 0.5, 0.2, 1.6)
	local size = 1.1 + strength * 1.6
	fx.emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	fx.emitter:Emit(counter and 3 or (strength > 0.9 and 2 or 1))
	fx.light.Brightness = 1.5 + strength * 2.5
	TweenService:Create(fx.light, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
end

function Impact.clear()
	for _, fx in pairs(Impact.fx) do
		if fx.att then
			fx.att:Destroy()
		end
	end
	table.clear(Impact.fx)
end

-- the last impact sound: a repeat of the same id at nearly the same pitch is pushed apart
function Impact.sfx(id, speed, volume)
	local last = Impact.last
	if id == last.id and math.abs(speed - last.speed) < 0.07 then
		speed += (speed >= last.speed) and 0.09 or -0.09
	end
	last.id, last.speed = id, speed
	sfx(id, speed, volume)
end

-- the impact of a landed punch: a base thud pitched by kind (straights snap high, hooks slap, uppercuts and
-- overhands thump), a second layer under hooks / power shots / body shots, a third crack on the heavy ones
function Impact.sound(msg, sev)
	local kind = msg.kind or (Config.Punches[msg.punch] and Config.Punches[msg.punch].kind) or "straight"
	local vol = math.clamp(0.35 + sev * 0.5, 0.35, 1)
	local r = math.random()
	if msg.body then
		Impact.sfx(soundId("BodyShot", "Thud"), 0.72 + r * 0.22 - (msg.heavy and 0.1 or 0), vol)
		sfx(BUILTIN.Grunt or "rbxasset://sounds/uuhhh.mp3", 0.75 + math.random() * 0.2, 0.18 + sev * 0.2)
	elseif kind == "straight" then
		Impact.sfx(soundId("PunchImpact", "Thud"), 1.45 + r * 0.3 - (msg.heavy and 0.25 or 0), vol * 0.9)
	elseif kind == "hook" then
		Impact.sfx(soundId("PunchImpact", "Thud"), 1.05 + r * 0.25 - (msg.heavy and 0.15 or 0), vol)
		sfx(BUILTIN.SwordHit or "rbxasset://sounds/swordhit.wav", 0.7 + math.random() * 0.25, 0.1 + sev * 0.12)
	else
		-- uppercut / overhand: a low thump with a slap on top
		Impact.sfx(soundId("PunchImpact", "Thud"), 0.85 + r * 0.2, vol)
		sfx(BUILTIN.SwordHit or "rbxasset://sounds/swordhit.wav", 0.5 + math.random() * 0.2, 0.12 + sev * 0.15)
	end
	if msg.heavy or msg.counter then
		sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 0.42 + math.random() * 0.12, 0.3 + sev * 0.2)
	end
end

-- the controller rumble (Gamepad.Rumble: a no-op off a gamepad or with vibration off)
function Impact.rumble(large, small, dur)
	if Gamepad and Gamepad.Rumble then
		pcall(Gamepad.Rumble, large, small, dur)
	end
end

-- how much a punch kind rocks the camera (the punch's damage against a cross)
function Impact.power(ptype)
	local P = Config.Punches[ptype]
	return math.clamp(((P and P.dmg) or 6.5) / 6.5, 0.55, 1.6)
end

local STUMBLE_STEP = "FightStumble" -- RenderStep binding that drives the player's stagger (handlers.stumble)
local ragdoll
local function setRagdoll(on)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if on then
		if ragdoll or not char or not hum then
			return
		end
		ragdoll = { motors = {}, made = {}, collide = {} }
		local ok, err = pcall(function()
			-- the Neck motor is disabled below: with RequiresNeck on, the Humanoid would die, the death replicates
			-- (the client owns this Humanoid) and Main's Died handler aborts the fight before the KO is recorded
			hum.RequiresNeck = false
			for _, m in ipairs(char:GetDescendants()) do
				if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Parent and m.Parent.Parent == char and m.Name ~= "Root" and m.Enabled then
					local a0 = Instance.new("Attachment")
					a0.CFrame = m.C0
					a0.Parent = m.Part0
					local a1 = Instance.new("Attachment")
					a1.CFrame = m.C1
					a1.Parent = m.Part1
					local bs = Instance.new("BallSocketConstraint")
					bs.LimitsEnabled = true
					bs.UpperAngle = m.Name == "Neck" and 35 or 65
					bs.TwistLimitsEnabled = true
					bs.TwistLowerAngle, bs.TwistUpperAngle = -25, 25
					bs.Attachment0, bs.Attachment1 = a0, a1
					bs.Parent = m.Parent
					table.insert(ragdoll.made, a0)
					table.insert(ragdoll.made, a1)
					table.insert(ragdoll.made, bs)
					table.insert(ragdoll.motors, m)
					m.Enabled = false
					if not ragdoll.collide[m.Part1] then
						ragdoll.collide[m.Part1] = m.Part1.CanCollide
						m.Part1.CanCollide = true
					end
				end
			end
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		if not ok then
			warn("[FightClient] ragdoll:", err)
		end
	elseif ragdoll then
		local r = ragdoll
		ragdoll = nil
		pcall(function()
			for _, m in ipairs(r.motors) do
				if m.Parent then
					m.Enabled = true
				end
			end
			if hum then
				-- back to the default (the server may already have replicated false before the kd message,
				-- so the value seen when the ragdoll started is not a reliable "previous" value)
				hum.RequiresNeck = true
			end
			for _, inst in ipairs(r.made) do
				inst:Destroy()
			end
			for part, was in pairs(r.collide) do
				if part.Parent then
					part.CanCollide = was
				end
			end
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
end

------------------------------------------------------------------------
-- Legacy venue presentation (used only when VenueFX is missing or failed to start)
------------------------------------------------------------------------
local VENUE_LIGHT = {
	Stadium = { ClockTime = 21, Brightness = 1.2, Ambient = Color3.fromRGB(50, 50, 60), OutdoorAmbient = Color3.fromRGB(40, 40, 55), Exposure = 0.2 },
	-- (brighter ambients than the first cut: the faces stayed readable in the dark arenas only with the
	-- VenueFX rig; this fallback has to carry them on its own)
	Arena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(70, 70, 84), OutdoorAmbient = Color3.fromRGB(56, 56, 70), Exposure = 0.3 },
	ClubArena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(70, 70, 84), OutdoorAmbient = Color3.fromRGB(58, 56, 68), Exposure = 0.25 },
	CommunityCenter = { ClockTime = 19, Brightness = 1, Ambient = Color3.fromRGB(96, 94, 96), OutdoorAmbient = Color3.fromRGB(84, 84, 92), Exposure = 0 },
	Gym = { ClockTime = 14, Brightness = 0.9, Ambient = Color3.fromRGB(120, 112, 104), OutdoorAmbient = Color3.fromRGB(118, 114, 112), Exposure = -0.1 },
}

-- the gym's outdoor look (sun rays, warm grade, bloom, hazy atmosphere) is switched off for
-- fight nights in the venues and put back afterwards
local GYM_EFFECTS = { "GymSunRays", "GymGrade", "GymBloom" }
local function setVenueLighting(venue)
	if not savedLighting then
		savedLighting = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Exposure = Lighting.ExposureCompensation, effects = {} }
		if venue ~= "Gym" then
			for _, n in ipairs(GYM_EFFECTS) do
				local e = Lighting:FindFirstChild(n)
				if e and e:IsA("PostEffect") then
					savedLighting.effects[e] = e.Enabled
					e.Enabled = false
				end
			end
			local atm = Lighting:FindFirstChildOfClass("Atmosphere")
			if atm then
				savedLighting.atm = { inst = atm, Density = atm.Density, Haze = atm.Haze }
				atm.Density = 0.12
				atm.Haze = 0.4
			end
		end
	end
	local v = VENUE_LIGHT[venue] or VENUE_LIGHT.Arena
	Lighting.ClockTime = v.ClockTime
	Lighting.Brightness = v.Brightness
	Lighting.Ambient = v.Ambient
	Lighting.OutdoorAmbient = v.OutdoorAmbient
	Lighting.ExposureCompensation = v.Exposure
end

local function restoreLighting()
	if savedLighting then
		Lighting.ClockTime = savedLighting.ClockTime
		Lighting.Brightness = savedLighting.Brightness
		Lighting.Ambient = savedLighting.Ambient
		Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
		Lighting.ExposureCompensation = savedLighting.Exposure
		for e, on in pairs(savedLighting.effects or {}) do
			if e.Parent then
				e.Enabled = on
			end
		end
		local a = savedLighting.atm
		if a and a.inst.Parent then
			a.inst.Density = a.Density
			a.inst.Haze = a.Haze
		end
		savedLighting = nil
	end
end

local crowd = {}
local spots = {}
local tallies = {}
local excitement = 0.2
local sweeping = 0

local function startVenueFx(arena)
	crowd, spots, tallies = {}, {}, {}
	if not arena then
		return
	end
	local folder = arena:FindFirstChild("Crowd")
	if folder then
		for _, fan in ipairs(folder:GetChildren()) do
			if fan:IsA("BasePart") then
				local head = fan:FindFirstChild("Head")
				table.insert(crowd, { fan = fan, head = head, base = fan.CFrame, hbase = head and head.CFrame, phase = math.random() * 6.28, speed = 6 + math.random() * 4 })
			end
		end
	end
	local sf = arena:FindFirstChild("Spots")
	if sf then
		for i, s in ipairs(sf:GetChildren()) do
			if s:IsA("BasePart") then
				table.insert(spots, { p = s, base = s.Position, phase = i })
			end
		end
	end
	for _, d in ipairs(arena:GetDescendants()) do
		if d.Name == "TallyLight" and d:IsA("BasePart") then
			table.insert(tallies, d)
		end
	end
	if fxConn then
		fxConn:Disconnect()
	end
	local frame = 0
	local center = F.center or Vector3.zero
	fxConn = RunService.Heartbeat:Connect(function(dt)
		excitement = math.max(0.15, excitement - dt * 0.35)
		sweeping = math.max(0, sweeping - dt)
		frame += 1
		local t = os.clock()
		if frame % 2 == 0 then
			for _, c in ipairs(crowd) do
				local up = math.max(0, math.sin(t * c.speed + c.phase)) * excitement * 1.2
				local off = CFrame.new(0, up, 0)
				c.fan.CFrame = c.base * off
				if c.head then
					c.head.CFrame = c.hbase * off
				end
			end
		end
		-- spotlights: sweep the crowd at big moments, otherwise lock onto the ring
		for _, s in ipairs(spots) do
			local target
			if sweeping > 0 then
				local a = t * 1.3 + s.phase * 1.1
				target = center + Vector3.new(math.cos(a) * 45, 0, math.sin(a * 0.8) * 45)
			else
				target = center + Vector3.new(math.cos(t * 0.6 + s.phase) * 4, 0, math.sin(t * 0.5 + s.phase) * 4)
			end
			s.p.CFrame = CFrame.lookAt(s.base, target)
		end
		for _, tl in ipairs(tallies) do
			tl.Transparency = (math.floor(t * 2) % 2 == 0) and 0 or 0.7
		end
	end)
end

-- the crowd erupts: one strip under the scoreboard (crowdMoment rate-limits it to one every 20 s), as soon
-- as the picture is clear of the count, the get-up, the scorecard and the big banner
local function crowdEruption()
	local lean = crowdMeter.lean
	local text, color = "THE CROWD IS ON ITS FEET!", T.gold
	if lean > 0.2 then
		text, color = "THEY'RE CHANTING YOUR NAME!", T.red
	elseif lean < -0.2 then
		text, color = "THE CROWD IS BEHIND " .. string.upper((F.tape and F.tape.opp.name or "HIM"):match("(%S+)$") or "HIM") .. "!", T.blue
	end
	task.spawn(function()
		for _ = 1, 14 do
			if not F.active then
				return
			end
			if not (countBox.Visible or getup.Visible or overlay.Visible or bannerBand.Visible) then
				crowdMoment(text, color)
				return
			end
			task.wait(0.25)
		end
	end)
end

local function cheer(amount)
	-- the HUD's crowd meter follows every cheer (VenueFX or the built-in crowd does the sound / bob)
	amount = amount or 0
	local before = crowdMeter.level
	crowdMeter.level = math.clamp(crowdMeter.level + amount * 0.35, 0, 1)
	if amount >= 0.5 then
		crowdPulse(amount / 1.2)
	end
	-- a spike (a man badly hurt, back up off the canvas) or the noise building past the top
	if F.active and (amount >= 0.8 or (before < 0.85 and crowdMeter.level >= 0.85)) then
		crowdEruption()
	end
	if venueOn then
		vfx("Cheer", math.clamp(amount / 1.6, 0, 1))
		return
	end
	excitement = math.min(1.6, excitement + amount)
end

local function screens(text)
	if venueOn then
		vfx("Screens", text)
		return
	end
	if not F.arena then
		return
	end
	for _, name in ipairs({ "Jumbotron", "BigScreen" }) do
		for _, screen in ipairs(F.arena:GetChildren()) do
			if screen.Name == name then
				for _, d in ipairs(screen:GetDescendants()) do
					if d:IsA("TextLabel") then
						d.Text = text
					end
				end
			end
		end
	end
end

local function pyro(side)
	if venueOn then
		vfx("Pyro", side)
		return
	end
	local folder = F.arena and F.arena:FindFirstChild("Pyro")
	if not folder then
		return
	end
	for _, p in ipairs(folder:GetChildren()) do
		if p.Name == (side == "red" and "PyroRed" or "PyroBlue") then
			local pe = p:FindFirstChildOfClass("ParticleEmitter")
			if pe then
				pe.Enabled = true
				task.delay(1.6, function()
					pe.Enabled = false
				end)
			end
		end
	end
	sweeping = 4
end

local function phase(name, data)
	vfx("Phase", name, data or {})
end

------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------
local camMode = "fight" -- fight | entrance | wide | tape
local camTarget
local baseFov

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

-- ropes, posts and pads that sit between the camera and the fighters fade out so they never block
-- the action. VenueFX ropes are invisible proxy parts named Rope that each hold a visible Beam.
local ringParts, faded, fadeClock = {}, {}, 0
local FADE_NAMES = { Rope = true, Post = true, Pad = true, TurnbucklePad = true, PostCap = true, PadSeam = true, Turnbuckle = true }
local function setFade(p, on)
	p.LocalTransparencyModifier = on and 0.8 or 0
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("SurfaceGui") then
			-- pad prints / sponsor logos ignore LocalTransparencyModifier: hide them while the pad is faded
			if on then
				if faded[c] == nil then
					faded[c] = c.Enabled
				end
				c.Enabled = false
			elseif faded[c] ~= nil then
				c.Enabled = faded[c]
				faded[c] = nil
			end
		elseif c:IsA("Beam") then
			if on then
				if c:GetAttribute("FadeSaved") == nil then
					c:SetAttribute("FadeSaved", true)
					faded[c] = c.Transparency
				end
				c.Transparency = NumberSequence.new(0.8)
			elseif faded[c] then
				c.Transparency = faded[c]
				faded[c] = nil
				c:SetAttribute("FadeSaved", nil)
			end
		end
	end
end
local function clearFades()
	for p in pairs(faded) do
		if p.Parent and p:IsA("BasePart") then
			setFade(p, false)
		end
	end
	for b, seq in pairs(faded) do
		if b.Parent and b:IsA("Beam") then
			b.Transparency = seq
			b:SetAttribute("FadeSaved", nil)
		elseif b.Parent and b:IsA("SurfaceGui") then
			b.Enabled = seq
		end
	end
	table.clear(faded)
end
local function collectRingParts()
	table.clear(ringParts)
	clearFades()
	if not F.arena then
		return
	end
	for _, d in ipairs(F.arena:GetDescendants()) do
		if d:IsA("BasePart") and FADE_NAMES[d.Name] then
			table.insert(ringParts, d)
		end
	end
end
-- closest distance between segments p1-q1 and p2-q2, plus how far along the first segment it happens (0..1)
local function segSegDist(p1, q1, p2, q2)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t
	if a <= 1e-6 then
		s, t = 0, (e > 1e-6) and math.clamp(f / e, 0, 1) or 0
	else
		local c = d1:Dot(r)
		if e <= 1e-6 then
			t, s = 0, math.clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = denom > 1e-6 and math.clamp((b * f - c * e) / denom, 0, 1) or 0
			t = (b * s + f) / e
			if t < 0 then
				t, s = 0, math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t, s = 1, math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * t)).Magnitude, s
end

local fadeHit = {}
local function updateOccluders(camPos, targets)
	if #ringParts == 0 then
		return
	end
	table.clear(fadeHit)
	for _, p in ipairs(ringParts) do
		if p.Parent then
			-- ropes run along their length (Z); posts and pads stand upright (Y)
			local axis, half, thr
			if p.Name == "Rope" then
				axis, half, thr = p.CFrame.LookVector, p.Size.Z / 2, 1.9
			elseif p.Name == "Turnbuckle" then
				-- Cylinder parts run along their X axis
				axis, half, thr = p.CFrame.RightVector, p.Size.X / 2, 1.6
			else
				axis, half, thr = p.CFrame.UpVector, p.Size.Y / 2, 1.6
			end
			local a, b = p.Position - axis * half, p.Position + axis * half
			for _, target in ipairs(targets) do
				local d, s = segSegDist(camPos, target, a, b)
				if d < thr and s < 0.93 then
					fadeHit[p] = true
					break
				end
			end
		end
	end
	for p in pairs(faded) do
		if p:IsA("BasePart") and not fadeHit[p] then
			if p.Parent then
				setFade(p, false)
			end
			faded[p] = nil
		end
	end
	for p in pairs(fadeHit) do
		if not faded[p] then
			setFade(p, true)
			faded[p] = true
		end
	end
end

-- per-frame screen FX from the latest state (tier, concussion) plus the transient kicks
local function updateFX(dt, now)
	local fx = fxScale()
	local me = F.me or {}
	local tier, conc = me.tier or 0, me.conc or 0
	FX.hitBlur = math.max(0, FX.hitBlur - dt * 14)
	FX.fovKick += (0 - FX.fovKick) * math.clamp(dt * 4, 0, 1)
	FX.grade = math.max(0, FX.grade - dt * 1.5)
	-- camera roll is a damped spring so a hook "knocks" the picture sideways and it wobbles back
	FX.rollVel += (-FX.roll * 60 - FX.rollVel * 9) * dt
	FX.roll += FX.rollVel * dt
	local eyeL, eyeR = math.clamp(tonumber(me.eyeL) or 0, 0, 1), math.clamp(tonumber(me.eyeR) or 0, 0, 1)
	if blurFx then
		-- a closing eye also smears the whole picture a little (Roblox blur is full-screen)
		local eyeBlur = math.max(0, math.max(eyeL, eyeR) - 0.6) * 4
		local size = (Config.Concussion.blurPerTier * tier + Config.Concussion.blurPerConc * conc + FX.hitBlur + FX.downBlur + eyeBlur) * fx
		blurFx.Size = math.clamp(size, 0, 24)
	end
	if gradeFx then
		local C = Config.Concussion
		gradeFx.Saturation = math.clamp(-(C.desatPerTier * tier + C.desatPerConc * conc) * fx - FX.grade * 0.3 * fx, -1, 0)
		gradeFx.Contrast = 0.04 * tier * fx
		gradeFx.Brightness = -0.06 * FX.grade * fx
		if tier >= 3 then
			-- out on your feet: the picture pulses red with the heartbeat
			local pulse = (math.sin(now * 6) * 0.5 + 0.5) * 0.25 * fx
			gradeFx.TintColor = Color3.new(1, 1 - pulse, 1 - pulse)
		elseif gradeFx.TintColor ~= WHITE then
			gradeFx.TintColor = WHITE
		end
	end
	local C = Config.Concussion
	local vig = math.clamp((C.vignettePerTier * tier + C.vignettePerConc * conc) * fx + (F.down and 0.35 or 0), 0, 0.9)
	vig = math.floor(vig * 50 + 0.5) / 50 -- rebuild the gradients only when it visibly changes
	if vig ~= FX.vig or tier ~= FX.vigTier then
		FX.vig, FX.vigTier = vig, tier
		local vigColor = tier >= 2 and VIG_RED or VIG_BLACK
		for _, v in ipairs(vignette) do
			v.frame.BackgroundColor3 = vigColor
			if vig < 0.01 then
				v.frame.Visible = false
			else
				v.frame.Visible = true
				v.grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - vig), NumberSequenceKeypoint.new(0.6, 1 - vig * 0.25), NumberSequenceKeypoint.new(1, 1) })
			end
		end
	end
	-- difficulty seeing: a swollen-shut eye blacks out its side of the screen
	local aL, aR = eyeDark(eyeL, fx), eyeDark(eyeR, fx)
	if aL ~= FX.eyeL or aR ~= FX.eyeR then
		FX.eyeL, FX.eyeR = aL, aR
		for i, a in ipairs({ aL, aR }) do
			local e = eyeShade[i]
			e.frame.Visible = a > 0
			if a > 0 then
				e.grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - a), NumberSequenceKeypoint.new(0.45, 1 - a * 0.7), NumberSequenceKeypoint.new(1, 1) })
			end
		end
	end
	-- muffled hearing: the high end drops away with concussion and danger
	if mixEq and mixEq.Parent then
		mixEq.HighGain = math.clamp(-(20 * conc + 6 * tier) * math.min(fx, 1), -40, 0)
		mixEq.MidGain = math.clamp(-(6 * conc + 2 * tier) * math.min(fx, 1), -20, 0)
	end
	-- heartbeat in your ears when you are in danger
	if F.active and (tier >= 2 or conc > 0.6 or F.down) and now >= FX.heartAt then
		local bpm = 70 + 18 * tier + (F.down and 30 or 0)
		FX.heartAt = now + 60 / bpm
		local id = soundId("Heartbeat", "Thud")
		sfx(id, 0.35, 0.5)
		local fight = F
		task.delay(0.16, function()
			if F == fight and gui.Enabled then
				sfx(id, 0.32, 0.35)
			end
		end)
	end
	-- the HUD head and health bars pulse at danger (keeping their value colour), stamina pulses red
	-- when the tank is nearly empty
	local ot = F.opp and F.oppState and F.oppState.tier or 0
	for _, pt in ipairs({ { L, tier }, { R, ot } }) do
		local panel, t = pt[1], pt[2]
		if t >= 2 then
			local p = math.sin(now * (t >= 3 and 9 or 5)) * 0.5 + 0.5
			panel.head.fill.BackgroundColor3 = rampColor(panel.head.v):Lerp(WHITE, p * 0.4)
			panel.health.fill.BackgroundColor3 = rampColor(panel.health.v):Lerp(WHITE, p * 0.3)
		end
		if panel.stam.v < 0.25 and F.active then
			local p = math.sin(now * 7) * 0.5 + 0.5
			panel.stam.fill.BackgroundColor3 = T.red:Lerp(WHITE, p * 0.45)
		end
	end
	crowdMeter.level = math.max(0.15, crowdMeter.level - dt * 0.035)
	-- a long quiet spell in a round: the crowd gets restless (one strip, rate-limited with the others)
	if F.active and not F.resting and not F.down and crowdMeter.level < 0.25 then
		crowdMeter.quiet += dt
		if crowdMeter.quiet > 25 then
			crowdMeter.quiet = 0
			crowdMoment("BOOS RAIN DOWN!", T.orange)
		end
	else
		crowdMeter.quiet = 0
	end
	updateCrowd(dt)
	refreshControls() -- the key strip's first seconds run out
	return tier, conc, fx
end

-- the gamepad state (the input code below): the sticks, the fight binding, the camera nudge
local pad = { bound = false, leftX = 0, leftY = 0, rightX = 0, rightY = 0, nudgeX = 0, nudgeY = 0, flick = Gamepad and Gamepad.Flick() }
local padOn -- () -> the fight pad binding is live and the player is on a gamepad (set with the input code)
local sendDevice -- () -> tells the server the device the fight runs on (set with the input code)
local function startCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	baseFov = baseFov or cam.FieldOfView
	if camConn then
		camConn:Disconnect()
	end
	collectRingParts()
	local t0 = os.clock()
	local targets = {}
	camConn = RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local now = os.clock()
		local tier, conc, fx = updateFX(dt, now)
		local me = getRoot(player.Character)
		local opp = getRoot(F.opp)
		if not me then
			return
		end
		FX.shake = math.max(0, FX.shake - dt * 3)
		local kick = shakeScale()
		local sh = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * FX.shake * fx * kick
		local goal
		local koModel = F.koTrack
		if koModel then
			local head = koModel.Parent and koModel:FindFirstChild("Head")
			local landed = koModel:GetAttribute("KOLanded")
			local done = not head or now - (F.koTrackFrom or now) > 4 or (type(landed) == "number" and now > landed + 0.8)
			if done then
				F.koTrack = nil
			else
				-- a low shot from the side of the fall, looking at the head wherever it goes
				local hp = head.Position
				local side = head.CFrame.RightVector
				local flatSide = Vector3.new(side.X, 0, side.Z)
				flatSide = flatSide.Magnitude > 0.05 and flatSide.Unit or Vector3.xAxis
				F.broadcastCF = CFrame.lookAt(hp + flatSide * 7 + Vector3.new(0, 1.2, 0), hp)
				F.broadcastUntil = now + 0.1
			end
		end
		if F.broadcastUntil and now < F.broadcastUntil and F.broadcastCF then
			goal = F.broadcastCF -- hard cut to the on-air camera
		elseif camMode == "entrance" and camTarget then
			local r = getRoot(camTarget)
			if r then
				-- ringwalk dolly: tracking backwards in front of the walker, slowly arcing round
				local p = r.Position
				local a = (now - (F.walkStart or now)) * 0.18
				local look = r.CFrame.LookVector
				local side = r.CFrame.RightVector
				local offset = look * (9 - math.min(3, (now - (F.walkStart or now)) * 0.4)) + side * (math.sin(a) * 3.5) + Vector3.new(0, 2.6, 0)
				goal = CFrame.lookAt(p + offset, p + Vector3.new(0, 1.5, 0))
			end
		elseif camMode == "wide" or camMode == "tape" then
			local center = F.center or me.Position
			local a = (now - t0) * 0.15
			local dist = F.spar and 22 or 30
			goal = CFrame.lookAt(center + Vector3.new(math.cos(a) * dist, 14, math.sin(a) * dist), center + Vector3.new(0, 3, 0))
		elseif opp then
			local dir = Vector3.new(opp.Position.X - me.Position.X, 0, opp.Position.Z - me.Position.Z)
			if dir.Magnitude < 0.1 then
				dir = Vector3.new(0, 0, -1)
			end
			dir = dir.Unit
			local right = dir:Cross(Vector3.yAxis)
			local mid = (me.Position + opp.Position) / 2 + Vector3.new(0, 1.2, 0)
			-- high 3/4 view from behind your shoulder; pick the side nearer the ring centre
			local center = F.center or mid
			local function flatDist(a, b)
				return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
			end
			-- auto-framing: the camera backs off as the fighters separate so both stay in the picture
			local sep = flatDist(me.Position, opp.Position)
			local back = 6.6 + math.clamp((sep - 4.5) * 0.4, 0, 3)
			local up = 5.4 + math.clamp((sep - 4.5) * 0.15, 0, 1.2)
			-- a 3/4 angle (about 40 degrees off the fight line) keeps both fighters readable instead of stacked
			local function camPos(side)
				return me.Position - dir * back + right * (side * 5.8) + Vector3.new(0, up, 0)
			end
			F.camSide = F.camSide or 1
			local pos = camPos(F.camSide)
			local other = camPos(-F.camSide)
			if flatDist(other, center) + 3 < flatDist(pos, center) then
				F.camSide = -F.camSide
				pos = other
			end
			-- gamepad: the right stick nudges the view round the pair and up / down; it eases back when let go
			local onPad = padOn()
			local nx, ny = onPad and pad.rightX or 0, onPad and pad.rightY or 0
			pad.nudgeX += (nx - pad.nudgeX) * math.clamp(dt * 5, 0, 1)
			pad.nudgeY += (ny - pad.nudgeY) * math.clamp(dt * 5, 0, 1)
			if math.abs(pad.nudgeX) > 0.01 or math.abs(pad.nudgeY) > 0.01 then
				local rel = pos - mid
				rel = CFrame.Angles(0, -pad.nudgeX * 0.55, 0):VectorToWorldSpace(rel)
				pos = mid + rel + Vector3.new(0, pad.nudgeY * 1.8, 0)
			end
			goal = CFrame.lookAt(pos, mid)
			F.camPad = onPad
		end
		if goal then
			-- drunk camera: a slow, sick sway that grows with the head tier and concussion
			local sway = (tier * 0.35 + conc) * fx
			if sway > 0.01 and camMode == "fight" then
				goal *= CFrame.Angles(math.sin(now * 0.8) * 0.01 * sway, math.sin(now * 1.1) * 0.02 * sway, math.sin(now * 0.7) * 0.04 * sway)
			end
			if math.abs(FX.roll) > 0.0005 then
				goal *= CFrame.Angles(0, 0, FX.roll * fx * kick)
			end
			if FX.hitStop > now then
				-- hit-stop: freeze the picture for a few frames on a big landed shot
				cam.CFrame += sh
			elseif F.broadcastUntil and now < F.broadcastUntil then
				cam.CFrame = goal + sh
			else
				-- a pad's camera eases a touch more (no mouse to re-aim: the stick nudges a smooth view)
				cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * (F.camPad and 6 or 8), 0, 1)) + sh
			end
		end
		cam.FieldOfView = math.clamp((baseFov or 70) + FX.fovKick * fx * kick, 40, 100)
		fadeClock += dt
		if fadeClock > 0.08 then
			fadeClock = 0
			table.clear(targets)
			targets[1] = me.Position + Vector3.new(0, 1.5, 0)
			targets[2] = me.Position
			targets[3] = me.Position - Vector3.new(0, 1.2, 0)
			if opp then
				targets[4] = opp.Position + Vector3.new(0, 1.5, 0)
				targets[5] = opp.Position
			end
			updateOccluders(cam.CFrame.Position, targets)
		end
		-- broadcast cuts while the camera is wide (between rounds, knockdowns, the final bell)
		if (camMode == "wide" or camMode == "tape") and venueOn and now >= (F.nextCut or 0) then
			F.nextCut = now + 4.5
			local cf = vfx("BroadcastCFrame", now)
			if typeof(cf) == "CFrame" and not (F.broadcastUntil and now < F.broadcastUntil) and math.random() < 0.6 then
				F.broadcastCF = cf
				F.broadcastUntil = now + 2.8
			end
		end
		-- get-up timing marker
		if F.down then
			F.markerPos = 0.5 + 0.5 * math.sin((now - (F.downAt or now)) * (F.markerSpeed or 3))
			marker.Position = UDim2.fromScale(F.markerPos, -0.15)
			FX.downBlur = 14 * math.clamp(1 - F.mash / math.max(1, F.target), 0, 1)
		else
			FX.downBlur = math.max(0, FX.downBlur - dt * 20)
		end
	end)
end

------------------------------------------------------------------------
-- Input: one dispatcher for keyboard + mouse, gamepad and the right-stick flicks, driven by the control
-- map (Keymap defaults + the player's custom map through Settings.Keymap()). A binding is a key, a chord
-- ("hold A, press B"; on a pad the first half may be a flick, which counts as held for 0.4 s) or a double
-- tap. Chords win over double taps, double taps over plain presses. A key that is both a plain punch and
-- a chord's modifier (RB: overhand, RB + X: check hook) throws its punch on RELEASE when no chord used it.
-- Local punch prediction: the Animator starts the punch on the key press (PredAct).
------------------------------------------------------------------------
local bindPad, unbindPad, setSprint -- (the input block below; the fight's start / finish use them)
-- (one function: its locals get their own registers, so the script stays under Luau's 200 per function)
local function setupInput()
local GuiService = game:GetService("GuiService")
local pred = { id = 0, busyUntil = 0, lastAt = 0, hand = "R" }
local ASSIST_STEP = "FightAssistMove" -- RenderStep binding: the left stick read relative to the opponent (aim assist)
local SPRINT_MUL = 1.55
local sprint = { on = false, base = 16 }
local Ctl = { map = nil, lk = nil, held = {}, pressedAt = {}, lastTap = {}, flickAt = {}, deferred = {}, chordUsed = {}, keyAction = {} }
padOn = function()
	return pad.bound and Gamepad ~= nil and Gamepad.IsPad()
end

-- the device a fight input is sent from (the server's aim assist only honours gamepad inputs)
-- the device the fight runs on, for the server (FightEngine `device`: rate-limited there, arms the aim
-- assist only after a while on the pad, drops it at once on the keyboard)
sendDevice = function()
	send({ t = "device", pad = (Gamepad ~= nil and Gamepad.IsPad()) or false })
end

local function padFlag()
	return (Gamepad and Gamepad.IsPad()) and true or nil
end

-- the touch HOOK pad throws the hook with the hand that did not just punch (a rear hook after a jab
-- or a lead hook, a lead hook after a cross); the lead hook when you have been still for a moment
pickHook = function()
	if os.clock() - pred.lastAt > 1.2 then
		return "leadhook"
	end
	return pred.hand == "L" and "rearhook" or "leadhook"
end

-- a punch can go out: the server's CanAct also refuses in a clinch, while down, in the corner or on the
-- ring walk, and nobody may punch a man on the canvas: the Guard attributes it replicates already say so
local function canPredict(char)
	local now = os.clock()
	if not char or not F.active or F.down or F.paused or F.menuPaused or now < (F.stumbleUntil or 0) or now < pred.busyUntil then
		return false
	end
	local g = char:GetAttribute("Guard")
	return not (g == "clinch" or g == "down" or g == "rest" or g == "walkout" or (F.opp and F.opp:GetAttribute("Guard") == "down"))
end

-- the predicted wind-up (the server's, roughly: fatigue and daze slow it)
local function predWindup(base)
	local stam = F.me and F.me.max and F.me.stam / math.max(1, F.me.max) or 1
	return base * (stam < 0.3 and 1.25 or 1) * (1 + 0.08 * ((F.me and F.me.tier) or 0))
end

-- counter = a counter jab / cross out of a slip (Q + click): the server lets it through the slip's recovery
throwPunch = function(p, body, counter)
	if F.countdown then
		return -- held in the corner until BOX! (the server refuses it anyway)
	end
	send({ t = "punch", p = p, body = body, counter = counter or nil, pad = padFlag() })
	-- the server drops the guard for a punch: a tapped guard drops with it; a held one comes back up
	-- once the punch is out. A tapped body modifier is spent on this punch.
	if Tog.on.block then
		if Tog.held("block") then
			task.delay(0.45, function()
				if Tog.on.block and Tog.held("block") and F.active then
					-- tagged like every input: an untagged message is a keyboard press to the server (aim assist)
					send({ t = "block", on = true, pad = padFlag() })
				end
			end)
		else
			Tog.set("block", false, true)
		end
	end
	if Tog.on.body and not Tog.held("body") then
		Tog.set("body", false)
	end
	local P = Config.Punches[p]
	local char = player.Character
	local now = os.clock()
	-- only predict what the server will almost surely accept (not down / stumbling / mid-punch); a
	-- counter punch comes out of the slip's recovery, which the local busy clock counts
	if not P or not (canPredict(char) or (counter and char and F.active and not F.down and now < pred.busyUntil and now - pred.lastAt > 0.2)) then
		return
	end
	local windup = predWindup(P.windup)
	local hand = P.hand
	if p == "uppercut" then
		hand = (pred.hand == "R" and now - pred.lastAt < 0.7) and "L" or "R"
	end
	pred.hand = hand
	pred.lastAt = now
	pred.busyUntil = now + windup * 1.9
	pred.id += 1
	char:SetAttribute("PredAct", string.format("%s|%s|%s|%.2f", p, hand, body and "body" or "head", windup))
	char:SetAttribute("PredActId", pred.id)
end

-- a special move (Moves.lua): sent only when the server said it is unlocked (the fight's start message);
-- predicted like a punch with the special act (the Animator matches the server's echo by id + hand). All
-- specials share one cooldown (F.specialReady: set on the throw, corrected by the server's echo and its
-- refusals) and each needs its gas: a press the server would refuse says so on the HUD and sends nothing
throwSpecial = function(id)
	if F.countdown or not F.active then
		return
	end
	local sid = Moves.Id(id) or id
	if not (F.moves and F.moves[sid]) then
		showFlash(flash, "LOCKED - SEE MOVES & CONTROLS", T.sub, 0.8)
		return
	end
	local M = Moves.Data[sid]
	local now = os.clock()
	local wait = (F.specialReady or 0) - now
	if M and wait > 0.05 then
		showFlash(flash, string.format("SPECIAL READY IN %.1fs", wait), T.sub, 0.6)
		return
	end
	local stam = F.me and tonumber(F.me.stam)
	if M and stam and stam < M.stam then
		showFlash(flash, "NO GAS FOR THE " .. (M.short or sid:upper()), T.orange, 0.7)
		return
	end
	send({ t = "special", id = sid, pad = padFlag() })
	if Tog.on.block and not Tog.held("block") then
		Tog.set("block", false, true)
	end
	local char = player.Character
	if not M or not canPredict(char) then
		return
	end
	local P = Config.Punches[M.punch[1]] or Config.Punches.cross
	local windup = predWindup(P.windup)
	pred.hand = M.hand
	pred.lastAt = now
	pred.specialAt = now
	pred.specialId = sid
	pred.busyUntil = now + windup * 2.2 + 0.3
	F.specialReady = now + (M.cooldown or 1.5)
	KM.paintSpecials()
	pred.id += 1
	char:SetAttribute("PredAct", string.format("special|%s|%s|%.2f|%.2f", sid, M.hand, windup, M.power or 1))
	char:SetAttribute("PredActId", pred.id)
end

-- the server refused a special this client predicted (handlers.refused): the local busy clock lets go and
-- the Animator is told to drop the move it started on the key press ("cancel|special|<id>", a predicted
-- act; an Animator without it ignores the unknown act)
KM.cancelSpecial = function(id)
	local char = player.Character
	if not char or pred.specialId ~= id or os.clock() - (pred.specialAt or -10) > 2.5 then
		return
	end
	pred.specialId = nil
	pred.busyUntil = 0
	pred.id += 1
	char:SetAttribute("PredAct", "cancel|special|" .. id)
	char:SetAttribute("PredActId", pred.id)
end

-- the Moves & Controls menu (BoxerClient.ControlsMenu), over the fight. A career fight or a spar PAUSES
-- while it is open (the server stops the round at the next quiet moment: `pause`, handlers.pause); a PvP
-- bout goes on and the window says so. The pad binding is let go while it is open so its buttons navigate
-- the menu; anything held (guard, body, sprint) is let go too
openMoves = function()
	local CM = KM.module("ControlsMenu")
	if not CM or CM.IsOpen() or (CM.RecentlyClosed and CM.RecentlyClosed()) then
		return
	end
	local inFight = gui.Enabled
	if inFight and F.down then
		return -- (not during a count: the get-up needs the keys)
	end
	local wasBound = pad.bound
	if wasBound then
		pcall(ContextActionService.UnbindAction, ContextActionService, "BoxerFightPad")
		pad.bound = false
	end
	if inFight then
		Tog.reset()
		setSprint(false)
		if not F.pvp then
			send({ t = "pause", on = true })
		end
	end
	UI.PadHold("Fight", false)
	local ok = pcall(CM.Open, {
		kicker = inFight and (F.pvp and "PVP: THE FIGHT GOES ON" or "ROUND PAUSED") or nil,
		onClose = function()
			if inFight then
				send({ t = "pause", on = false })
			end
			if F.active or gui.Enabled then
				UI.PadHold("Fight", true)
				if wasBound and not pad.bound then
					bindPad()
				end
			end
			KM.refresh()
		end,
	})
	if not ok then
		if inFight then
			send({ t = "pause", on = false })
		end
		UI.PadHold("Fight", true)
		if wasBound then
			bindPad()
		end
	end
end

------------------------------------------------------------------------
-- Sprint (Shift, LS click) outside the ring: on the player's own Humanoid (client-owned physics). Put back
-- exactly when let go, and never over a speed something else set meanwhile: any other write while it runs
-- (the main menu's hold, the server) ends the sprint there and then. The base speed is published as the
-- Humanoid's local SprintBase attribute, so a hold that saves the speed (MainMenu) saves the walk, not the
-- sprint. In the ring Shift is the server's quicker footwork instead (ringSprint, FightEngine `sprint`).
------------------------------------------------------------------------
local function endSprint(hum)
	sprint.on = false
	if sprint.conn then
		sprint.conn:Disconnect()
		sprint.conn = nil
	end
	if hum then
		hum:SetAttribute("SprintBase", nil)
	end
end

setSprint = function(on)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		endSprint(nil)
		return
	end
	if on then
		if sprint.on or F.active or gui.Enabled or player:GetAttribute("InFight") == true or player:GetAttribute("Busy") ~= nil then
			return
		end
		if hum.WalkSpeed <= 0 then
			return
		end
		sprint.on = true
		sprint.base = hum.WalkSpeed
		sprint.writing = true
		hum:SetAttribute("SprintBase", sprint.base)
		hum.WalkSpeed = sprint.base * SPRINT_MUL
		sprint.writing = false
		sprint.conn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if sprint.on and not sprint.writing and math.abs(hum.WalkSpeed - sprint.base * SPRINT_MUL) >= 0.01 then
				endSprint(hum)
			end
		end)
	elseif sprint.on then
		local mine = math.abs(hum.WalkSpeed - sprint.base * SPRINT_MUL) < 0.01
		endSprint(hum)
		if mine then
			hum.WalkSpeed = sprint.base
		end
	end
end

-- Shift in the ring: the server speeds the footwork up while it is held (and charges stamina for it)
local function ringSprint(on)
	if (sprint.ring == true) == on then
		return
	end
	sprint.ring = on
	send({ t = "sprint", on = on, pad = padFlag() })
end
KM.dropRingSprint = function()
	sprint.ring = false -- (the fight is over: the server's flag went with it)
end

------------------------------------------------------------------------
-- Aim assist (gamepad only; Settings > Controls): the left stick is read RELATIVE TO THE OPPONENT, so
-- pushing up always closes the distance and sideways always circles him; the facing itself is the
-- server's (AlignOrientation). The server adds its own small hit-chance forgiveness from the SAVED
-- level for inputs tagged as gamepad. Low = relative movement; High = the same plus a gentle pull that
-- keeps you squared up while you circle.
------------------------------------------------------------------------
local function assistLevel()
	local v = player:GetAttribute("AimAssist")
	return v == "High" and 2 or (v == "Low" and 1 or 0)
end

local function stopAssistMove()
	pcall(RunService.UnbindFromRenderStep, RunService, ASSIST_STEP)
	pad.assistMoving = false
end

local function assistMoveStep()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local me, opp = getRoot(player.Character), getRoot(F.opp)
	local level = assistLevel()
	if not (hum and me and opp and F.active and not F.down and level > 0 and Gamepad and Gamepad.IsPad()) then
		if pad.assistMoving then
			pad.assistMoving = false
			if hum then
				hum:Move(Vector3.zero)
			end
		end
		return
	end
	if os.clock() < math.max(F.stumbleUntil or 0, F.lungeUntil or 0) then
		return -- a stagger / lunge drives the character
	end
	local x, y = pad.leftX, pad.leftY
	if x * x + y * y < 0.04 then
		if pad.assistMoving then
			pad.assistMoving = false
			hum:Move(Vector3.zero)
		end
		return
	end
	local dir = Vector3.new(opp.Position.X - me.Position.X, 0, opp.Position.Z - me.Position.Z)
	if dir.Magnitude < 0.05 then
		return
	end
	dir = dir.Unit
	local right = dir:Cross(Vector3.yAxis)
	local move = dir * y + right * x
	if level >= 2 then
		-- high: circling drifts a little toward the fight line, so you never walk off at an angle
		move += dir * math.abs(x) * 0.25
	end
	if move.Magnitude > 1 then
		move = move.Unit
	end
	pad.assistMoving = true
	hum:Move(move, false)
end

local function startAssistMove()
	stopAssistMove()
	-- bound right after the default ControlModule's own Move (Input priority) so this write wins
	pcall(RunService.BindToRenderStep, RunService, ASSIST_STEP, Enum.RenderPriority.Input.Value + 1, assistMoveStep)
end

------------------------------------------------------------------------
-- The dispatcher
------------------------------------------------------------------------
local TOGGLE_ACTIONS = { block = "block", body = "body", legend = "legend" }
local SEND_ACTIONS = {
	slipL = { t = "slip", dir = -1 }, slipR = { t = "slip", dir = 1 }, dodge = { t = "roll" }, quickdodge = { t = "roll", quick = true },
	parry = { t = "parry" }, pivotL = { t = "pivot", dir = -1 }, pivotR = { t = "pivot", dir = 1 }, clinch = { t = "clinch" },
}

local function addBinding(dev, b, id)
	local last, mod, double = Keymap.Trigger(b)
	if not last then
		return
	end
	if mod then
		dev.chord[last] = dev.chord[last] or {}
		table.insert(dev.chord[last], { mod = mod, id = id })
		dev.modOf[mod] = true
	elseif double then
		dev.double[last] = id
	else
		dev.plain[last] = id
	end
end

-- in the ring a flick up doubles as D-pad up (the parry), the LS click as D-pad down (the clinch) and the RS
-- click as D-pad left (the pivot, as the old map had it; the default map now gives RS click the quick dodge,
-- which wins): the flicks share the stick with the slips and the roll. Only while the map gives the alias
-- key nothing of its own (the sprint does not count: a pad's ring sprint gives way to the clinch); never
-- outside a fight.
local PAD_ALIAS = { Thumbstick2Up = "DPadUp", ButtonL3 = "DPadDown", ButtonR3 = "DPadLeft" }

-- the lookup tables of the map in use (rebuilt when Settings hands out a new map)
local function lookup()
	local map = KM.now()
	if Ctl.lk and Ctl.map == map then
		return Ctl.lk
	end
	local lk = { kbd = { plain = {}, chord = {}, double = {}, modOf = {}, alias = {} }, pad = { plain = {}, chord = {}, double = {}, modOf = {}, alias = {} } }
	for _, a in ipairs(Keymap.Actions) do
		if not a.fixed then
			for _, b in ipairs(map.kbd[a.id] or {}) do
				addBinding(lk.kbd, b, a.id)
			end
			local pb = map.pad[a.id]
			if pb and not a.padFixed then
				addBinding(lk.pad, pb, a.id)
			end
		end
	end
	for from, to in pairs(PAD_ALIAS) do
		local own = lk.pad.plain[from]
		if (own == nil or own == "sprint") and not lk.pad.chord[from] and not lk.pad.double[from] and lk.pad.plain[to] then
			lk.pad.alias[from] = lk.pad.plain[to]
		end
	end
	Ctl.map, Ctl.lk = map, lk
	KM.refresh()
	return lk
end

-- what an action does (device = "kbd" | "pad")
local function act(id)
	local A = Keymap.ById[id]
	if not A then
		return
	end
	if id == "legend" then
		Tog.press("legend")
		return
	elseif id == "moveslist" then
		openMoves()
		return
	elseif id == "sprint" then
		if gui.Enabled then
			ringSprint(true)
		else
			setSprint(true)
		end
		return
	elseif id == "body" then
		Tog.press("body") -- armed even between rounds, so a tap carried over a bell still counts
		return
	elseif id == "block" then
		Tog.press("block")
		return
	end
	if not F.active or F.countdown or F.down then
		return
	end
	if A.section == "punch" then
		if id == "bodyhook" then
			throwPunch(pickHook(), true)
		else
			throwPunch(id, Tog.on.body and id ~= "overhand")
		end
	elseif id == "counterjab" then
		throwPunch("jab", Tog.on.body, true)
	elseif id == "countercross" then
		throwPunch("cross", Tog.on.body, true)
	elseif A.special then
		throwSpecial(A.special)
	elseif SEND_ACTIONS[id] then
		local m = table.clone(SEND_ACTIONS[id])
		m.pad = padFlag()
		send(m)
	end
end

local function fire(id, keyName)
	Ctl.keyAction[keyName] = id
	act(id)
end

local function isHeld(mod, now)
	if Ctl.held[mod] then
		return true
	end
	local at = Ctl.flickAt[mod]
	return at ~= nil and now - at < 0.4
end

-- a key went down (name = KeyCode name or MouseButton1 / 2 / 3 / a flick's KeyCode name)
local function onPress(name, device)
	local lk = lookup()[device]
	local now = os.clock()
	Ctl.held[name] = true
	Ctl.pressedAt[name] = now
	Ctl.keyAction[name] = nil
	local chords = lk.chord[name]
	if chords then
		for _, c in ipairs(chords) do
			if isHeld(c.mod, now) then
				Ctl.chordUsed[c.mod] = true
				Ctl.deferred[c.mod] = nil
				fire(c.id, name)
				return
			end
		end
	end
	local d = lk.double[name]
	if d and now - (Ctl.lastTap[name] or -10) < 0.3 then
		Ctl.lastTap[name] = -10
		fire(d, name)
		return
	end
	Ctl.lastTap[name] = now
	local p = lk.alias[name] or lk.plain[name] -- (onPress only runs in a fight: the ring aliases apply)
	if p then
		local A = Keymap.ById[p]
		if lk.modOf[name] and A and A.section == "punch" then
			-- a modifier's own punch waits for the release: a chord may still claim the key
			Ctl.deferred[name] = p
			Ctl.chordUsed[name] = nil
		else
			fire(p, name)
		end
	end
end

local function onRelease(name)
	local now = os.clock()
	Ctl.held[name] = nil
	local p = Ctl.deferred[name]
	Ctl.deferred[name] = nil
	if p and not Ctl.chordUsed[name] and now - (Ctl.pressedAt[name] or 0) < 0.35 then
		fire(p, name)
	end
	Ctl.chordUsed[name] = nil
	local id = Ctl.keyAction[name]
	Ctl.keyAction[name] = nil
	if not id then
		return
	end
	if TOGGLE_ACTIONS[id] then
		Tog.release(TOGGLE_ACTIONS[id])
	elseif id == "sprint" then
		setSprint(false)
		ringSprint(false)
	end
end

-- the name a key / mouse button goes by in the map
local function inputName(input)
	local it = input.UserInputType
	if it == Enum.UserInputType.MouseButton1 then
		return "MouseButton1", "kbd"
	elseif it == Enum.UserInputType.MouseButton2 then
		return "MouseButton2", "kbd"
	elseif it == Enum.UserInputType.MouseButton3 then
		return "MouseButton3", "kbd"
	end
	local k = input.KeyCode
	if k.Value == 0 then
		return nil -- no key (a mouse move, a touch): KeyCode 0 is Unknown / None depending on the API version
	end
	if Gamepad and Gamepad.IsPadKey(k) then
		return k.Name, "pad"
	end
	return k.Name, "kbd"
end

local function menuOpen()
	local CM = KM.modules.ControlsMenu
	return CM and CM.IsOpen() or false
end

-- keys Roblox claims that the fight takes back: Tab (the player list, hidden for the fight: KM.listOff) and
-- Shift (shift-lock may claim it; the ring sprint and the Shift + Space chord still need it)
local RING_KEYS = { Tab = "list", LeftShift = true, RightShift = true }

UserInputService.InputBegan:Connect(function(input, gp)
	local name, device = inputName(input)
	if not name then
		return
	end
	-- the sprint and the menu work in the world too; everything else needs the fight
	if device == "pad" and pad.bound then
		return -- the fight's ContextActionService binding handles the pad
	end
	if menuOpen() or UserInputService:GetFocusedTextBox() then
		return
	end
	-- SHIFT before the gameProcessed check: shift-lock may claim the key, the chords must still see it held
	Ctl.held[name] = true
	local ringKey = gui.Enabled and RING_KEYS[name] ~= nil and (RING_KEYS[name] ~= "list" or KM.listOff == true)
	if gp and not (device == "pad" and GuiService.SelectedObject == nil) and not ringKey then
		return
	end
	if not F.active and not F.down then
		local lk = lookup()[device]
		local p = lk.plain[name]
		if p == "sprint" and not gui.Enabled then
			fire("sprint", name)
		elseif p == "moveslist" then
			-- in the world too (the backquote key; Tab there is Roblox's player list), but not over the main
			-- menu (it has its own CONTROLS) or in the middle of a drill
			local MM = KM.module("MainMenu")
			if gui.Enabled or not (player:GetAttribute("Busy") ~= nil or (MM and MM.IsOpen and MM.IsOpen())) then
				fire("moveslist", name)
			end
		end
		return
	end
	if F.down and (name == "Space" or name == "MouseButton1" or name == "ButtonA") then
		getupPress()
		return
	end
	onPress(name, device)
end)

UserInputService.InputEnded:Connect(function(input)
	local name, device = inputName(input)
	if name then
		onRelease(name)
	end
end)

-- what each toggle does: the guard goes to the server (only in a live round), the legend shows the strip
Tog.effects.block = function(on)
	if F.active and not F.countdown then
		send({ t = "block", on = on, pad = padFlag() })
	end
end
Tog.effects.legend = function(on)
	holdH = on
	refreshControls()
end

------------------------------------------------------------------------
-- Gamepad: one ContextActionService binding for the whole fight, at High priority so it runs before (and
-- sinks) the default bindings of the same buttons: A's jump, the right stick's camera turn and RS click's
-- zoom, X's proximity prompts, VIEW's UI selection. The left stick is left alone (Roblox's movement)
-- unless the aim assist re-reads it. Bound on the fight's start message, unbound in finish(); everything
-- it holds (block, body modifier, the controls strip) is let go there too, so nothing stays stuck.
------------------------------------------------------------------------
local PAD_ACTION = "BoxerFightPad"
local PAD_KEYS = {
	K.ButtonX, K.ButtonY, K.ButtonB, K.ButtonA, K.ButtonR1, K.ButtonR2, K.ButtonL1, K.ButtonL2, K.ButtonR3, K.ButtonL3,
	K.DPadUp, K.DPadDown, K.DPadLeft, K.DPadRight, K.ButtonSelect, K.Thumbstick2,
}
local FLICK_KEY = { L = "Thumbstick2Left", R = "Thumbstick2Right", U = "Thumbstick2Up", D = "Thumbstick2Down" }

local function padRelease()
	Tog.reset()
	if pad.flick then
		pad.flick:Reset()
	end
	table.clear(Ctl.held)
	table.clear(Ctl.deferred)
end

local function padFlick(dir)
	if not F.active or F.down then
		return
	end
	local name = FLICK_KEY[dir]
	Ctl.flickAt[name] = os.clock()
	onPress(name, "pad")
	Ctl.held[name] = nil
end

local function padBegin(k)
	local name = k.Name
	if k == K.ButtonSelect and not F.down then
		-- VIEW: held for a second it always opens the Moves & Controls menu; the press itself does what the
		-- map gives VIEW (the controls strip by default, any action the player bound to it otherwise)
		onPress(name, "pad")
		local at = Ctl.pressedAt[name]
		task.delay(0.8, function()
			if Ctl.held[name] and Ctl.pressedAt[name] == at and pad.bound then
				if Ctl.keyAction[name] == "legend" then
					Tog.pressedAt.legend = nil
					Tog.set("legend", false)
				end
				Ctl.keyAction[name] = nil
				openMoves()
			end
		end)
		return
	end
	if F.down then
		-- the get-up: A mashes exactly like SPACE (the marker in the green zone = a good press)
		if k == K.ButtonA then
			getupPress()
		end
		return
	end
	onPress(name, "pad")
end

local function padEnd(k)
	onRelease(k.Name)
end

local function padAction(_, state, input)
	local k = input.KeyCode
	if k == K.Thumbstick2 then
		local p = input.Position
		pad.rightX, pad.rightY = p.X, p.Y
		if pad.flick then
			local dir = pad.flick:Update(p.X, p.Y, os.clock())
			if dir then
				padFlick(dir)
			end
		end
	elseif state == Enum.UserInputState.Begin then
		padBegin(k)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		padEnd(k)
	end
	return Enum.ContextActionResult.Sink
end

bindPad = function()
	if pad.bound then
		return
	end
	local ok = pcall(function()
		ContextActionService:BindActionAtPriority(PAD_ACTION, padAction, false, Enum.ContextActionPriority.High.Value, table.unpack(PAD_KEYS))
	end)
	pad.bound = ok
	-- the fight HUD is not navigated: no window selection may take the D-pad / A meanwhile
	UI.PadHold("Fight", true)
	startAssistMove()
end

unbindPad = function()
	padRelease()
	if pad.bound then
		pad.bound = false
		pcall(ContextActionService.UnbindAction, ContextActionService, PAD_ACTION)
	end
	UI.PadHold("Fight", false)
	stopAssistMove()
	pad.rightX, pad.rightY, pad.nudgeX, pad.nudgeY = 0, 0, 0, 0
end

-- the left stick stays Roblox's movement (the aim assist re-reads it); its lean also picks the RS-click
-- pivot's side (ButtonR3 is the "pivot toward the lean" button when it is bound to a pivot)
UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == K.Thumbstick1 then
		pad.leftX, pad.leftY = input.Position.X, input.Position.Y
	end
end)
-- another device picked up: the strip / pads / get-up title follow it, and the server is told (the aim
-- assist is tied to the device the server holds the fighter on)
if Gamepad then
	Gamepad.Changed:Connect(function(mode)
		refreshControls()
		if mode ~= "gamepad" then
			Gamepad.Rumble(0, 0, 0)
		end
		if F.active or F.countdown then
			sendDevice()
		end
	end)
end
end -- setupInput
setupInput()

------------------------------------------------------------------------
-- Animate script control for the local character during a fight
------------------------------------------------------------------------
local function setAnimate(on)
	local char = player.Character
	if not char then
		return
	end
	local animate = char:FindFirstChild("Animate")
	if animate then
		animate.Disabled = not on
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and not on then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0.1)
		end
	end
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
local function fmtTime(s)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function stopMusic()
	if music then
		local m = music
		music = nil
		TweenService:Create(m, TweenInfo.new(2), { Volume = 0 }):Play()
		task.delay(2.1, function()
			m:Destroy()
		end)
	end
end

local function chipFor(s, hurt, female)
	local tier = s.tier or 0
	if tier >= 1 then
		local label = (Config.HeadTiers[tier + 1] or {}).label or ""
		if female then
			label = label:gsub("HIS", "HER")
		end
		return label, tierColor(tier)
	elseif hurt then
		return "ROCKED", T.gold
	elseif (s.conc or 0) > 0.45 then
		return "CONCUSSED", T.purple
	elseif s.stam and s.max and s.stam < s.max * 0.2 then
		return "GASSED", s.stam < s.max * 0.1 and T.red or T.orange
	elseif s.body and s.body < 30 then
		return "BODY HURT", T.orange
	end
	return nil
end

-- the slim phone strip has less room at the end of the name row
local SHORT_CHIP = { ["IN DANGER"] = "DANGER", ["OUT ON HIS FEET"] = "OUT ON FEET", ["OUT ON HER FEET"] = "OUT ON FEET" }
local function setChip(panel, text, color)
	if text and compactHud then
		text = SHORT_CHIP[text] or text
	end
	if not text then
		panel.chip.Visible = false
		panel.chipLast = nil
		return
	end
	panel.chip.Visible = true
	panel.chip.BackgroundColor3 = color
	panel.chipText.TextColor3 = UI.InkOn(color)
	panel.chipText.Text = text
	if panel.chipLast ~= text then
		panel.chipLast = text
		-- pop when it changes
		panel.chip.BackgroundTransparency = 0
		panel.chip.Size = UDim2.fromOffset(0, 26)
		TweenService:Create(panel.chip, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(0, 22) }):Play()
	end
end

-- Career fights: leaving after the opening bell counts as a loss (RTD) on the server, so the reset
-- button is switched off for the bout and back on in finish(). Spars keep it (a reset only ends them).
-- SetCore fails while the CoreScripts are still registering the callback (the first bout right after a
-- join): the lock is then retried once a second, up to ten times, while the fight wants it.
local resetLocked = false
local resetWant = false
local resetTry = 0
local function lockReset(on)
	resetWant = on
	if on == resetLocked then
		return
	end
	local ok = pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", not on)
	if ok then
		resetLocked = on
		resetTry = 0
	elseif on then
		resetTry += 1
		if resetTry <= 10 then
			task.delay(1, function()
				if resetWant and not resetLocked then
					lockReset(true)
				end
			end)
		end
	else
		resetLocked = false
	end
end
-- Roblox's player list owns Tab (it toggles the list and sinks the key). A fight hides the list, which hands
-- Tab to the Moves & Controls menu, and puts it back as it was at the end (the game has its own rankings)
function KM.setPlayerList(on)
	if not on then
		if KM.listOff then
			return
		end
		local okGet, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList)
		KM.listWas = not okGet or was ~= false
		KM.listOff = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
	elseif KM.listOff then
		KM.listOff = false
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, KM.listWas ~= false)
	end
end
-- the callback is registered once at start too (the usual pattern), so the first bout's lock holds
task.spawn(function()
	for _ = 1, 6 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", true) then
			return
		end
		task.wait(2)
	end
end)

local function finish()
	lockReset(false)
	KM.setPlayerList(true)
	KM.dropRingSprint()
	KM.showPaused(false)
	unbindPad()
	Countdown.Hide()
	F.countdown = false
	F.active = false
	F.down = false
	gui.Enabled = false
	fxGui.Enabled = false
	overlay.Visible = false
	getup.Visible = false
	hideCount()
	bannerBand.Visible = false
	angleTag.Visible = false
	bug:SetAttribute("On", false)
	bug.Visible = false
	crowdStrip.Visible = false
	controlsUntil, holdH = 0, false
	refreshControls()
	UI.Clear(markers)
	setRagdoll(false)
	F.stumbleUntil = 0
	F.koTrack = nil
	F.broadcastUntil = nil
	pcall(RunService.UnbindFromRenderStep, RunService, STUMBLE_STEP)
	pcall(RunService.UnbindFromRenderStep, RunService, "FightLunge")
	F.lungeUntil = 0
	Impact.clear()
	Impact.last.id = nil
	if Gamepad and Gamepad.Rumble then
		pcall(Gamepad.Rumble, 0, 0, 0)
	end
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	clearFades()
	table.clear(ringParts)
	if fxConn then
		fxConn:Disconnect()
		fxConn = nil
	end
	stopMusic()
	if venueOn then
		vfx("Stop")
		venueOn = false
	end
	restoreLighting()
	destroyPost()
	destroyMix()
	if bloodFolder then
		bloodFolder:Destroy()
		bloodFolder = nil
	end
	for _, m in ipairs({ player.Character, F.opp }) do
		for _, n in ipairs({ "Head", "UpperTorso" }) do
			local part = m and m:FindFirstChild(n)
			local att = part and part:FindFirstChild("FightSprayAtt")
			if att then
				att:Destroy()
			end
		end
	end
	local char = player.Character
	if char then
		char:SetAttribute("PredAct", nil)
		char:SetAttribute("PredActId", nil)
	end
	for k in pairs(FX) do
		FX[k] = 0
	end
	FX.vig, FX.vigTier = -1, -1
	FX.eyeL, FX.eyeR = -1, -1
	for _, e in ipairs(eyeShade) do
		e.frame.Visible = false
	end
	letterbox(false)
	blackout.BackgroundTransparency = 1
	setAnimate(true)
	local cam = workspace.CurrentCamera
	if baseFov then
		cam.FieldOfView = baseFov
		baseFov = nil
	end
	cam.CameraType = Enum.CameraType.Custom
	player:SetAttribute("InFight", false)
end

local PUNCH_NAME = { jab = "JAB", cross = "CROSS", leadhook = "LEAD HOOK", rearhook = "REAR HOOK", uppercut = "UPPERCUT", overhand = "OVERHAND" }

local handlers = {}

function handlers.start(msg)
	F = { active = false, mash = 0, target = 10, arena = msg.arena, opp = msg.oppModel, ref = msg.refModel, rounds = msg.rounds, tape = msg.tape, kind = msg.kind,
		spar = msg.spar, venue = msg.venue, venueName = msg.venueName, weighIn = msg.weighIn, notes = msg.notes, talk = msg.talk, myLine = msg.myLine,
		moves = {}, moveList = {}, assist = tonumber(msg.assist) or 0 }
	-- the special moves the server will accept from this fighter (Moves.List order)
	for _, id in ipairs(type(msg.moves) == "table" and msg.moves or {}) do
		if type(id) == "string" then
			F.moves[id] = true
			table.insert(F.moveList, id)
		end
	end
	setSprint(false)
	KM.dropRingSprint()
	KM.refresh()
	player:SetAttribute("InFight", true)
	gui.Enabled = true
	fxGui.Enabled = true
	lockReset(not F.spar)
	KM.setPlayerList(false)
	sendDevice()
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = false, false, false, false
	setChip(L, nil)
	setChip(R, nil)
	if F.arena then
		local center = F.arena:FindFirstChild("Anchors") and F.arena.Anchors:FindFirstChild("RingCenter")
		F.center = center and center.Position
	end
	L.name.Text = string.upper(msg.tape.you.name)
	R.name.Text = string.upper(msg.tape.opp.name)
	for _, pair in ipairs({ { L, msg.tape.you }, { R, msg.tape.opp } }) do
		local panel, t = pair[1], pair[2]
		local r = t.record or {}
		panel.sub.Text = string.format("%d-%d-%d  ·  %d KO%s", r.w or 0, r.l or 0, r.d or 0, r.ko or 0, (t.nick and t.nick ~= "") and ('  ·  "' .. string.upper(t.nick) .. '"') or "")
		if type(t.player) == "string" then
			-- PvP: the Roblox account behind the boxer, and his PvP rating
			panel.sub.Text = t.player .. (t.rating and ("  ·  " .. tostring(t.rating)) or "") .. "  ·  " .. string.format("%d-%d-%d", r.w or 0, r.l or 0, r.d or 0)
		end
		UI.Clear(panel.flag)
		local fl = getFlags()
		if fl and t.nat then
			pcall(fl.Draw, panel.flag, t.nat, { Size = UDim2.fromOffset(30, 20) })
		end
		UI.Clear(panel.kd)
		panel.kdCount = 0
		panel.cut.Visible, panel.swell.Visible, panel.ribs.Visible = false, false, false
		for _, z in ipairs({ panel.zones.head, panel.zones.bodyL, panel.zones.bodyR }) do
			z.BackgroundColor3 = ZONE_IDLE
		end
	end
	crowdMeter.level, crowdMeter.lean, crowdMeter.quiet, crowdMeter.lastBanner = 0.2, 0, 0, -100
	crowdStrip.Visible = false
	hideCount()
	bug:SetAttribute("On", true)
	layoutHud()
	local stakes = {}
	for _, s in ipairs(msg.stakes or {}) do
		table.insert(stakes, s)
	end
	for _, s in ipairs(msg.playerStakes or {}) do
		if not table.find(stakes, s) then
			table.insert(stakes, s)
		end
	end
	F.pvp = msg.pvp == true
	local oppTag = type(msg.tape.opp.player) == "string" and (" (" .. msg.tape.opp.player .. ")") or ""
	if F.spar then
		setBug("SPARRING  ·  " .. string.upper(F.spar), T.blue, "SPAR")
		F.stakesText = string.format("SPARRING (%s) vs %s%s", string.upper(F.spar), msg.tape.opp.name, oppTag)
	elseif F.pvp then
		setBug("PVP  ·  RANKED", T.gold, "PVP")
		F.stakesText = string.format("%s vs %s%s", string.upper(msg.kind or "PVP RANKED BOUT"), msg.tape.opp.name, oppTag)
	else
		setBug("LIVE  ·  WCB SPORTS", T.red, "LIVE")
		F.stakesText = #stakes > 0 and (table.concat(stakes, " - ") .. " WORLD TITLE" .. (#stakes > 1 and "S" or "") .. " ON THE LINE") or msg.kind:upper()
	end
	setTicker(string.format("%s vs %s  -  %d ROUND%s  -  %s%s", msg.tape.you.name:upper(), msg.tape.opp.name:upper(), msg.rounds, msg.rounds > 1 and "S" or "", F.stakesText,
		(msg.venueName and msg.venueName ~= "" and not F.spar) and ("  -  LIVE FROM THE " .. msg.venueName:upper()) or ""))
	-- the mix exists BEFORE VenueFX starts so its crowd / bell / music route through FightMix
	ensureMix()
	ensurePost()
	resolveVenueFX()
	venueOn = false
	if VenueFX and type(VenueFX.Start) == "function" then
		local ok, err = pcall(VenueFX.Start, F.arena, {
			venue = F.spar and "Gym" or msg.venue, venueName = msg.venueName, spar = F.spar, stakes = stakes, kind = msg.kind, tape = msg.tape,
			rounds = msg.rounds, oppModel = F.opp, myModel = player.Character,
		})
		venueOn = ok
		if not ok then
			warn("[FightClient] VenueFX.Start failed, using built-in venue effects:", err)
		end
	end
	if not venueOn then
		setVenueLighting(F.spar and "Gym" or msg.venue)
		startVenueFx(F.arena)
	end
	screens(msg.tape.you.name:upper() .. "\nvs\n" .. msg.tape.opp.name:upper())
	startCamera()
	camMode = F.spar and "wide" or "entrance"
	letterbox(not F.spar)
	buildTouch()
	setTouchSpecials(F.moveList)
	KM.buildSpecialStrip(F.moveList)
	bindPad()
end

function handlers.entrance(msg)
	F.walkStart = os.clock()
	letterbox(true)
	if msg.phase == "opp" then
		camMode = "entrance"
		camTarget = F.opp
		showBanner("INTRODUCING...", T.blue, 2.5)
		setTicker("Making the walk to the ring: " .. ((F.tape.opp.nick or "") ~= "" and ("\"" .. F.tape.opp.nick .. "\" ") or "") .. F.tape.opp.name)
		phase("entrance", { who = "opp", target = F.opp, pyro = msg.pyro == true })
		cheer(0.6)
		if msg.pyro then
			pyro("blue")
		end
	else
		camMode = "entrance"
		camTarget = player.Character
		showBanner("YOUR WALKOUT", T.red, 2.5)
		setTicker((msg.intro or "And now...") .. "  " .. F.tape.you.name:upper() .. " \"" .. (F.tape.you.nick or "") .. "\"!")
		phase("entrance", { who = "you", target = player.Character, pyro = msg.pyro == true })
		cheer(1.2)
		if msg.pyro then
			pyro("red")
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and msg.target then
			hum.WalkSpeed = 10
			hum:MoveTo(msg.target)
		end
		if msg.music and msg.music ~= "" then
			music = Instance.new("Sound")
			music.Name = "WalkoutMusic" -- Settings scales sounds named *Music* by the music volume
			music.SoundId = "rbxassetid://" .. msg.music
			music.Volume = 0.8
			-- the music setting's group (Settings routes every *Music* sound there; set here so the
			-- first frame is already right); the sfx setting and the concussion EQ never touch it
			local mm = SoundService:FindFirstChild("MusicMix")
			if mm and mm:IsA("SoundGroup") then
				music.SoundGroup = mm
			end
			music.Parent = SoundService
			music:Play()
		end
	end
end

-- the tale of the tape. A phone gets the short version (it has to fit between the letterbox and
-- the ticker without shrinking): combined height / reach, no knockouts / nationality / scouting rows,
-- the weigh-in only when it was missed, the trash talk on the ticker instead
local function buildTape()
	local y, o = F.tape.you, F.tape.opp
	local compact = UI.CanvasSize(hud).Y < 640
	F.overlayCompact = compact
	local function rec(x)
		local r = x.record or {}
		return string.format("%d-%d-%d", r.w or 0, r.l or 0, r.d or 0)
	end
	overlayBegin()
	ovHead(F.stakesText or "", "TALE OF THE TAPE", F.spar and T.blue or T.red)
	ovVersus(y, o)
	ovRow(rec(y), "Record", rec(o))
	if compact then
		ovRow(string.format("%s · %d in", Config.HeightText(y.height), y.reach or 0), "Height · Reach", string.format("%s · %d in", Config.HeightText(o.height), o.reach or 0))
	else
		ovRow((y.record or {}).ko or 0, "Knockouts", (o.record or {}).ko or 0)
		ovRow(Config.HeightText(y.height), "Height", Config.HeightText(o.height))
		ovRow(string.format("%d in", y.reach or 0), "Reach", string.format("%d in", o.reach or 0))
	end
	ovRow(string.upper(y.style or "-"), "Style", string.upper(o.style or "-"))
	if not compact then
		ovRow(string.upper(y.nat or "-"), "Nationality", string.upper(o.nat or "-"))
	end
	ovRow(y.overall or 0, "Overall", o.overall or 0, true)
	if o.archetype and not compact then
		ovNote("Scouting", o.archetype, T.blue)
	end
	local wi = F.weighIn
	if wi then
		if wi.over > 0 then
			ovNote("Weigh-in", string.format("%.1f lbs (limit %d) - MISSED WEIGHT by %.1f lbs: stamina -%d%%%s", wi.weight, wi.limit, wi.over, math.floor(wi.penalty * 100),
				wi.fine > 0 and ", fined 20% of your purse" or ""), T.red)
		elseif not compact then
			ovNote("Weigh-in", string.format("%.1f lbs (limit %d) - made weight", wi.weight, wi.limit), T.green)
		end
	end
	if F.notes and #F.notes > 0 and not compact then
		ovNote("Condition", table.concat(F.notes, ", "), T.orange)
	end
	if F.talk and F.talk ~= "" then
		if compact then
			setTicker(o.name .. ': "' .. F.talk .. '"')
		else
			ovQuote(F.talk, o.name, T.blue)
		end
	end
	if F.myLine and F.myLine ~= "" and not compact then
		ovQuote(F.myLine, y.name, T.red)
	end
	overlayShow()
end

function handlers.tape()
	camMode = "tape"
	letterbox(true)
	F.overlayBuild = buildTape
	buildTape()
	stopMusic()
end

function handlers.round(msg)
	overlay.Visible = false
	F.overlayBuild = nil
	F.resting = false
	-- held in the corner until the countdown's BOX! (failsafe: never stuck if a beat is lost)
	F.countdown = true
	local fight = F
	task.delay(8, function()
		if F == fight and F.countdown then
			F.countdown = false
			refreshControls()
		end
	end)
	Tog.reset(true)
	KM.dropRingSprint() -- (the server lets a held Shift go at the bell too)
	setAnimate(false)
	F.active = true
	F.paused = false
	camMode = "fight"
	F.broadcastUntil = nil
	letterbox(false)
	L.frame.Visible, R.frame.Visible, clock.Visible = true, true, true
	if msg.n == 1 then
		-- the key strip shows for the first seconds of the fight, then H (or the setting) brings it back
		controlsUntil = os.clock() + 10
	end
	hideCount()
	layoutHud()
	roundText.Text = string.format("ROUND %d / %d", msg.n, msg.total)
	timeText.Text = fmtTime(F.spar and Config.SparRoundSeconds or Config.RoundSeconds)
	timeText.TextColor3 = T.text
	showBanner("ROUND " .. msg.n, T.gold, 0.55) -- short: the corner countdown (3 - 2 - 1 - BOX!) follows in its place
	phase("round", { n = msg.n })
	if not venueOn then
		sfx(BUILTIN.Ping or "rbxasset://sounds/electronicpingshort.wav", 0.55, 0.6)
	end
	screens("ROUND " .. msg.n)
	cheer(0.5)
end

-- overall health: the head carries more weight than the body (a fight ends on the chin)
local function overallOf(s)
	local hp, body = tonumber(s.hp) or 0, tonumber(s.body) or 0
	local cap, bodyCap = tonumber(s.cap) or 100, tonumber(s.bodyCap) or 100
	return (hp * 0.6 + body * 0.4) / 100, (cap * 0.6 + bodyCap * 0.4) / 100
end

function handlers.state(msg)
	timeText.Text = fmtTime(msg.time)
	timeText.TextColor3 = (msg.time or 99) <= 10 and T.red or T.text
	F.me, F.oppState = msg.me, msg.opp
	local function apply(panel, s, female, model)
		-- one colour language: HEALTH / HEAD / BODY follow their value (green, gold, orange, red),
		-- STAMINA is blue, amber from half, red under a quarter; danger pulses in updateFX
		local overall, overallCap = overallOf(s)
		local hv, bv = (tonumber(s.hp) or 0) / 100, (tonumber(s.body) or 0) / 100
		setBar(panel.head, hv, (s.cap or 100) / 100, rampColor(hv))
		setBar(panel.health, overall, overallCap, rampColor(overall))
		setBar(panel.body, bv, (s.bodyCap or 100) / 100, rampColor(bv))
		local max = math.max(1, s.max or 100)
		local sv = (tonumber(s.stam) or 0) / max
		setBar(panel.stam, sv, (s.stamCap or max) / max, stamColor(sv))
		setChip(panel, chipFor(s, s.hurt, female))
		-- damage icons: swelling from the face damage stage the builder publishes, bruised ribs from body HP
		local stage = model and tonumber(model:GetAttribute("FaceDmgTier")) or 0
		panel.swell.Visible = stage >= 2
		panel.ribs.Visible = (tonumber(s.body) or 100) < 40
	end
	apply(L, msg.me, F.tape and F.tape.you.female, player.Character)
	apply(R, msg.opp, F.tape and F.tape.opp.female, F.opp)
	if L.bal and msg.me.bal then
		local b = math.clamp(msg.me.bal / 100, 0, 1)
		L.bal.Size = UDim2.fromScale(b, 1)
		L.bal.BackgroundColor3 = b < 0.3 and T.red or (b < 0.55 and T.gold or Color3.fromRGB(200, 200, 210))
	end
	angleTag.Visible = msg.me.angle == true
	KM.paintSpecials()
	vfx("State", msg)
end

function handlers.hit(msg)
	local mine = msg.who == "you"
	local target = mine and F.opp or player.Character
	local attacker = mine and player.Character or F.opp
	local sev = msg.sev or (msg.heavy and 1 or 0.4)
	local fx = fxScale()
	local power = Impact.power(msg.punch) * (msg.special and 1.15 or 1)
	local big = msg.heavy == true or msg.counter == true
	Impact.sound(msg, sev * (msg.special and 1.1 or 1))
	-- spray flies off the far side of the target, along the punch (more of it off a power shot or a
	-- counter), and the contact point flashes
	local tr, ar = getRoot(target), getRoot(attacker)
	if tr and ar then
		local dir = tr.Position - ar.Position
		dir = Vector3.new(dir.X, 0.35, dir.Z)
		if dir.Magnitude > 0.05 then
			spray(target, msg.body and "UpperTorso" or "Head", dir.Unit, sev * (big and 1.5 or 1) * (0.7 + power * 0.3), msg.bleed == true and not msg.body)
		end
	end
	Impact.flash(target, msg.body and "UpperTorso" or "Head", sev * (big and 1.4 or 0.9) * power, msg.counter == true)
	vfx("Hit", { target = target, heavy = msg.heavy == true, dmg = msg.dmg, punch = msg.punch })
	if msg.heavy then
		cheer(0.5)
	end
	if mine then
		-- landing it: a kick that grows with the punch (a jab barely moves the picture, an overhand rocks it)
		FX.shake = math.max(FX.shake, (0.04 + sev * 0.12) * power * (big and 1.5 or 1))
		Impact.rumble(big and 0.35 or 0.1, 0.2 + sev * 0.35, 0.08 + sev * 0.08)
		if msg.heavy then
			FX.hitStop = os.clock() + 0.06
			flashFrame(whiteFlash, 1 - 0.18 * fx, 0.15)
		end
	else
		-- taking it: the picture lurches toward the side the punch came from, blurs and flashes red,
		-- the pad thumps
		FX.shake = math.max(FX.shake, (0.18 + sev * 0.4) * power)
		FX.rollVel += (msg.hand == "L" and 1 or -1) * (msg.body and 0.15 or 0.6) * sev
		Impact.rumble(0.35 + sev * 0.6, 0.15 + sev * 0.3, 0.12 + sev * 0.22)
		if msg.heavy then
			FX.hitBlur = math.max(FX.hitBlur, 4 + sev * 7)
			FX.fovKick = -6 * sev
			flashFrame(redFlash, 1 - math.clamp(0.25 + sev * 0.25, 0, 0.6) * fx, 0.35)
		end
		if msg.body then
			FX.grade = math.max(FX.grade, 0.6 * sev) -- breath knocked out of you
		end
	end
	-- the HUD: zone flash on the target's silhouette, the crowd leans, cuts show up
	local panel = mine and R or L
	zoneFlash(panel, msg.body == true, msg.hand, sev)
	if msg.bleed and not msg.body then
		panel.cut.Visible = true
	end
	crowdMeter.lean = math.clamp(crowdMeter.lean + (mine and 1 or -1) * (0.03 + sev * 0.07), -1, 1)
	local name = PUNCH_NAME[msg.punch] or tostring(msg.punch):upper()
	if msg.special then
		local M = Moves.Data[msg.special]
		name = M and M.short or tostring(msg.special):upper()
		big = true
	end
	if mine then
		-- one marker over the opponent for every punch you land: the punch's name, gold and bigger
		-- (with COUNTER in front) for the ones that matter; no second line in the middle of the screen
		local text = (msg.counter and "COUNTER " or "") .. name .. (msg.body and " · BODY" or "") .. (big and "!" or "")
		hitMarker(target, text, big and T.gold or Color3.new(1, 1, 1), big)
	elseif msg.counter then
		-- the centre flash is for counters (and knockdowns / round events): a heavy shot you take
		-- already shakes, blurs and reddens the picture
		showFlash(flash, "COUNTER " .. name .. (msg.body and " TO THE BODY" or "") .. "!", T.red)
	end
end

function handlers.blocked(msg)
	Impact.sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 1.75 + math.random() * 0.3, 0.22 + math.random() * 0.08)
	if msg.who == "you" then
		showFlash(flash, "BLOCKED", T.blue, 0.5)
		FX.shake = math.max(FX.shake, 0.08)
		Impact.rumble(0.08, 0.2, 0.07)
	else
		-- his gloves took yours: a light buzz
		Impact.rumble(0.12, 0.1, 0.07)
	end
end

-- a special move going out: its name, and the pad rumbles on the launch of the big ones
function handlers.special(msg)
	local M = Moves.Data[msg.id]
	local name = (M and M.short) or msg.name or tostring(msg.id):upper()
	if msg.who == "you" then
		showFlash(defFlash, name .. "!", T.gold, 0.7)
		Impact.rumble(0, 0.25, 0.06)
		-- the shared cooldown runs from the server's go (a special this client did not predict counts too)
		F.specialReady = math.max(F.specialReady or 0, os.clock() + ((M and M.cooldown) or 1.5) - 0.1)
		KM.paintSpecials()
	else
		showFlash(defFlash, "HE GOES FOR THE " .. name .. "!", T.sub, 0.7)
	end
end

-- the server did not throw a special this client asked for: why, on the HUD, and the local prediction (if
-- one started) is called off
-- (a field, not a local: the script's main chunk is at Luau's 200-locals limit)
KM.REFUSED = { cooldown = "SPECIAL NOT READY", stamina = "NO GAS FOR THE %s", busy = "TOO SOON AFTER THE LAST PUNCH", locked = "LOCKED - SEE MOVES & CONTROLS" }
function handlers.refused(msg)
	if msg.what ~= "special" then
		return
	end
	local M = Moves.Data[msg.id]
	local now = os.clock()
	F.specialReady = msg.why == "cooldown" and now + math.clamp(tonumber(msg.wait) or 0, 0, 5) or now
	KM.cancelSpecial(msg.id)
	KM.paintSpecials()
	local text = KM.REFUSED[msg.why]
	if text then
		showFlash(flash, string.format(text, M and M.short or tostring(msg.id):upper()), msg.why == "stamina" and T.orange or T.sub, 0.7)
	end
end

-- the Moves & Controls menu holds the round (FightEngine `pause`: on once the round stops, off when it goes
-- on: the window closed, or it stayed open past the cap)
function handlers.pause(msg)
	F.menuPaused = msg.on == true
	KM.showPaused(F.menuPaused)
	refreshControls()
	if not F.menuPaused and msg.why == "cap" then
		showFlash(flash, "THE ROUND IS BACK ON", T.gold, 1.4)
	end
end

-- a special's set-up moves the root (a leap in, two steps back): the server glides its NPC, the player's
-- own character is client-owned, so this client pushes it (like a stumble, Humanoid:Move from RenderStep)
local LUNGE_STEP = "FightLunge"
function handlers.lunge(msg)
	if msg.who ~= "you" then
		return
	end
	local dir = Vector3.new(msg.dir and msg.dir.x or 0, 0, msg.dir and msg.dir.z or 0)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not (hum and dir.Magnitude > 0.05) then
		return
	end
	local dur = tonumber(msg.dur) or 0.3
	F.lungeUntil = os.clock() + dur
	local unit = dir.Unit
	pcall(RunService.UnbindFromRenderStep, RunService, LUNGE_STEP)
	RunService:BindToRenderStep(LUNGE_STEP, Enum.RenderPriority.Input.Value + 2, function()
		if os.clock() > (F.lungeUntil or 0) or not hum.Parent or F.down then
			pcall(RunService.UnbindFromRenderStep, RunService, LUNGE_STEP)
			hum:Move(Vector3.zero)
			return
		end
		hum:Move(unit, false)
	end)
end

local DEF_TEXT = { SLIPPED = "SLIPPED", ["ROLLED UNDER"] = "ROLLED UNDER", PARRIED = "PARRIED", PIVOT = "PIVOTED OFF" }
function handlers.defense(msg)
	local mine = msg.who == "you"
	if mine then
		showFlash(defFlash, (DEF_TEXT[msg.move] or msg.move) .. "! COUNTER NOW!", T.gold, 0.8)
	else
		showFlash(defFlash, "OPPONENT " .. (DEF_TEXT[msg.move] or msg.move), T.sub, 0.6)
	end
end

function handlers.miss(msg)
	if msg.why ~= "short" then
		-- the whoosh of a punch cutting air
		sfx(BUILTIN.SwordLunge or "rbxasset://sounds/swordlunge.wav", 1.5 + math.random() * 0.3, 0.12)
	end
	if msg.who == "you" and msg.why == "short" then
		showFlash(flash, "OUT OF RANGE", T.sub, 0.5)
	end
end

function handlers.comment(msg)
	setTicker(msg.text)
end

function handlers.announce(msg)
	setTicker(msg.text)
	showFlash(flash, msg.text, T.gold, 1.2)
end

local TIER_CALL = { "ROCKED!", "HURT BAD!", "OUT ON HIS FEET!" }
function handlers.tier(msg)
	local tier = msg.tier or 0
	phase("tier", { who = msg.who, tier = tier })
	local prev = msg.who == "you" and F.myTier or F.oppTier
	if msg.who == "you" then
		F.myTier = tier
	else
		F.oppTier = tier
	end
	if tier <= (prev or 0) then
		return
	end
	if msg.who == "opp" then
		local call = TIER_CALL[tier] or "ROCKED!"
		if F.tape and F.tape.opp.female then
			call = call:gsub("HIS", "HER")
		end
		showFlash(defFlash, call .. " FINISH IT!", tierColor(tier), 1.2)
		screens(call)
		cheer(0.4 * tier)
	else
		showFlash(defFlash, tier >= 2 and "YOU'RE IN TROUBLE - HOLD (G) AND COVER UP!" or "YOU'RE HURT - TIE HIM UP (G)!", tierColor(tier), 1.6)
		flashFrame(redFlash, 1 - 0.35 * fxScale(), 0.6)
	end
end

function handlers.stumble(msg)
	local mine = msg.who == "you"
	if mine then
		-- the server owns the timing; the client owns the character's physics, so it pushes the stagger
		local dir = Vector3.new(msg.dir and msg.dir.x or 0, 0, msg.dir and msg.dir.z or 0)
		local dur = msg.dur or 0.6
		F.stumbleUntil = os.clock() + dur
		FX.rollVel += (math.random() < 0.5 and -1 or 1) * 0.5 * (msg.sev or 0.5)
		FX.shake = math.max(FX.shake, 0.3)
		Impact.rumble(0.5, 0.1, 0.25)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and dir.Magnitude > 0.05 then
			local unit = dir.Unit
			pcall(RunService.UnbindFromRenderStep, RunService, STUMBLE_STEP)
			-- the default ControlModule calls Move every frame from RenderStep (Input priority), even with no
			-- keys held; binding right after it makes this write the last one before physics, so the stagger
			-- is involuntary (a Heartbeat write would be overwritten before it was ever simulated)
			RunService:BindToRenderStep(STUMBLE_STEP, Enum.RenderPriority.Input.Value + 1, function()
				if os.clock() > F.stumbleUntil or not hum.Parent then
					pcall(RunService.UnbindFromRenderStep, RunService, STUMBLE_STEP)
					hum:Move(Vector3.zero)
					return
				end
				hum:Move(unit, false)
			end)
		end
		sfx(BUILTIN.Footsteps or "rbxasset://sounds/action_footsteps_plastic.mp3", 0.8, 0.4)
	else
		cheer(0.3)
	end
end

function handlers.ropes(msg)
	local target = msg.who == "you" and player.Character or F.opp
	vfx("Hit", { target = target, heavy = true, dmg = 0, punch = "ropes" })
	cheer(0.3)
end

local SEVERITY_TEXT = { flash = "FLASH KNOCKDOWN!", heavy = "DOWN HARD!", out = "KNOCKOUT!" }
function handlers.kd(msg)
	local mine = msg.who == "you"
	-- the server pauses the fight for the count, eight count and referee check (no punches are accepted)
	F.paused = true
	local target = mine and player.Character or F.opp
	-- R-anim: the knockout close-up follows the falling man's head until he has landed (+0.8 s)
	if msg.severity == "out" and target then
		F.koTrack, F.koTrackFrom = target, os.clock()
	end
	sfx(BUILTIN.Falling or "rbxasset://sounds/action_falling.ogg", 0.65 + math.random() * 0.1, 1)
	Impact.sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 0.45 + math.random() * 0.1, 0.9)
	Impact.rumble(1, 1, mine and 0.7 or 0.45)
	phase("kd", { who = msg.who, target = target, severity = msg.severity })
	cheer(1.6)
	FX.shake = 1
	sweeping = 3
	camMode = "wide"
	letterbox(true)
	local oppName = F.tape and F.tape.opp.name:upper() or "HE"
	local name = mine and "YOU'RE DOWN!" or ("DOWN GOES " .. oppName .. "!")
	if msg.severity == "out" then
		name = mine and "YOU'RE OUT COLD" or (oppName .. " IS OUT COLD!")
	end
	-- the count panel carries the headline; the referee's count fills it in
	addKD(mine and L or R)
	crowdMeter.lean = math.clamp(crowdMeter.lean + (mine and -0.6 or 0.6), -1, 1)
	openCount(SEVERITY_TEXT[msg.severity] or "KNOCKDOWN!", mine and T.red or T.gold, name)
	flashbulbs(mine and 8 or 16)
	if msg.severity == "out" then
		countNum.Text = "KO"
		countNum.TextColor3 = mine and T.red or T.gold
	end
	screens(msg.severity == "out" and "KNOCKOUT!" or "KNOCKDOWN!")
	if mine then
		Tog.reset(true)
		F.down = true
		F.mash = 0
		F.downAt = os.clock()
		refreshControls()
		flashFrame(redFlash, 1 - 0.6 * fxScale(), 0.8)
		if msg.severity == "out" then
			-- lights out: the Animator plays the knockout fall (msg.anim); the physics ragdoll is the
			-- round-1 fallback for a server that does not animate it
			if not msg.anim then
				setRagdoll(true)
			end
			TweenService:Create(blackout, TweenInfo.new(1.4), { BackgroundTransparency = 0.25 }):Play()
		end
	end
end

function handlers.getupStart(msg)
	F.target = msg.target
	F.mash = 0
	F.downAt = os.clock()
	local ability = math.clamp(tonumber(msg.ability) or 0.5, 0, 1)
	F.zoneW = 0.12 + ability * 0.25
	local conc = F.me and F.me.conc or 0
	F.markerSpeed = 3.2 - ability * 1.2 + conc * 1.5
	zone.Size = UDim2.fromScale(F.zoneW, 1)
	setGetup(0)
	-- the title names the press of the device in use: SPACE, A / CROSS on a pad, taps on touch
	local isFlash = msg.severity == "flash"
	UI.BindHint(getupTitle, function(mode)
		local touch = mode == "touch" or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and mode ~= "gamepad")
		if mode == "gamepad" and Gamepad then
			local a = Gamepad.Label(K.ButtonA)
			return isFlash and ("FLASH KNOCKDOWN! SHAKE IT OFF - MASH " .. a .. " / HIT THE GREEN") or ("YOU'RE DOWN!  MASH " .. a .. " - HIT THE GREEN ZONE")
		end
		return isFlash and ("FLASH KNOCKDOWN! SHAKE IT OFF - " .. (touch and "TAP" or "MASH") .. " / HIT THE GREEN")
			or (touch and "YOU'RE DOWN!  TAP FAST - HIT THE GREEN ZONE" or "YOU'RE DOWN!  MASH SPACE / TAP - HIT THE GREEN ZONE")
	end)
	getupHint.Text = string.format("Get up before 10. Green-zone presses count triple. (needed: %d)", msg.target or 10)
	getup.Visible = true
end

function handlers.count(msg)
	local n = msg.n or 0
	if msg.standing and countKickerText.Text ~= "EIGHT COUNT" then
		countKickerText.Text = "EIGHT COUNT"
		countKicker.BackgroundColor3 = T.blue
	end
	showCount(n, msg.standing == true)
	phase("count", { n = n })
	sfx(soundId("RefereeCount", "Click"), 0.8, 0.45)
	if msg.who == "you" and not msg.standing then
		setGetup((msg.mash or F.mash) / math.max(1, msg.target or F.target))
	end
end

function handlers.getup(msg)
	local mine = msg.who == "you"
	if mine then
		F.down = false
		getup.Visible = false
		refreshControls()
		sfx(BUILTIN.Grunt or "rbxasset://sounds/uuhhh.mp3", 1, 0.5)
		FX.hitBlur = 10 -- the world swims back into focus
	end
	phase("getup", { who = msg.who })
	cheer(0.8)
	countWho.Text = mine and "YOU BEAT THE COUNT" or ((F.tape and F.tape.opp.name:upper() or "HE") .. " BEATS THE COUNT")
	countKickerText.Text = "EIGHT COUNT"
	countKicker.BackgroundColor3 = T.blue
	setTicker(mine and ("You beat the count! Show the " .. (F.spar and "coach" or "referee") .. " you can continue...") or (F.tape.opp.name .. " beats the count!"))
end

function handlers.refcheck(msg)
	hideCount()
	if msg.ok then
		F.paused = false
		showBanner("OK TO CONTINUE", T.green, 1.2)
		camMode = "fight"
		letterbox(false)
		-- he's back up and the fight is on: the place erupts
		cheer(0.9)
	else
		showBanner("WAVED OFF!", T.red, 2.5)
		cheer(1.2)
	end
end

function handlers.bell(msg)
	F.active = false
	Tog.reset(true) -- the server drops the guard in the corner
	refreshControls()
	showBanner("DING DING DING", T.gold, 1.5)
	setTicker("End of round " .. msg.n)
	phase("bell", { n = msg.n })
	if not venueOn then
		local bell = BUILTIN.Ping or "rbxasset://sounds/electronicpingshort.wav"
		local fight = F
		for i = 0, 2 do
			task.delay(i * 0.28, function()
				if F == fight and gui.Enabled then
					sfx(bell, 0.6, 0.7)
				end
			end)
		end
	end
end

local buildRest
function handlers.rest(msg)
	camMode = "wide"
	phase("rest", { n = msg.n })
	F.cards = F.cards or {}
	if type(msg.card) == "table" then
		F.cards[msg.n] = { tonumber(msg.card[1]) or 0, tonumber(msg.card[2]) or 0 }
	end
	F.resting = true
	refreshControls()
	bannerBand.Visible = false -- the bell's banner would sit on the scorecard
	F.overlayBuild = function()
		buildRest(msg)
	end
	buildRest(msg)
	layoutHud()
end

-- the scorecard between rounds (a phone leaves out the accuracy row, the cutman and all but one line
-- of advice: it has to fit between the scoreboard and the ticker without shrinking)
function buildRest(msg)
	local compact = UI.CanvasSize(hud).Y < 640
	F.overlayCompact = compact
	local you, opp = F.tape and F.tape.you.name or "You", F.tape and F.tape.opp.name or "Opponent"
	overlayBegin()
	ovHead(string.format("End of round %d  -  your corner", msg.n), F.spar and "BETWEEN ROUNDS" or "SCORECARD", T.gold)
	local u = msg.unofficial or { 0, 0 }
	ovScore(tonumber(u[1]) or 0, tonumber(u[2]) or 0, F.spar and "COACH'S CARD" or "UNOFFICIAL CARD", you, opp)
	ovRounds(F.cards, F.rounds, msg.n)
	local st = msg.stats
	if type(st) == "table" then
		local function pct(l, t)
			return t > 0 and string.format("%d%%", math.floor(l / t * 100 + 0.5)) or "-"
		end
		ovRow(string.format("%d / %d", st.landed or 0, st.thrown or 0), "Landed / thrown", string.format("%d / %d", st.oppLanded or 0, st.oppThrown or 0))
		if not compact then
			ovRow(pct(st.landed or 0, st.thrown or 0), "Accuracy", pct(st.oppLanded or 0, st.oppThrown or 0))
		end
	end
	local c = msg.cond
	if type(c) == "table" then
		ovCondition(c)
		if c.notes and #c.notes > 0 and not compact then
			ovNote("Cutman", table.concat(c.notes, "  |  "), T.orange)
		end
	end
	for i, line in ipairs(msg.advice or {}) do
		if not compact or i == 1 then
			ovQuote(line, "your corner", T.gold)
		end
	end
	overlayShow()
end

function handlers.final(msg)
	F.active = false
	F.down = false
	getup.Visible = false
	local res = msg.result
	local text
	if res.method == "KO" or res.method == "TKO" or res.method == "RTD" then
		text = res.method .. "!"
	elseif F.spar then
		text = "TIME!"
	else
		text = "THE JUDGES' DECISION..."
	end
	camMode = "wide"
	sweeping = 4
	letterbox(true)
	hideCount()
	overlay.Visible = false
	refreshControls()
	phase("final", { result = res.outcome, method = res.method })
	showBanner(text, res.outcome == "win" and T.gold or T.red, 3)
	screens(res.outcome == "win" and ("WINNER\n" .. F.tape.you.name:upper()) or (res.outcome == "loss" and ("WINNER\n" .. F.tape.opp.name:upper()) or "DRAW"))
	cheer(1.6)
	-- the server moves the character home ~3 s after this: stand back up before that
	if ragdoll then
		task.delay(2.2, function()
			setRagdoll(false)
			TweenService:Create(blackout, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		end)
	end
end

function handlers.result()
	finish()
end

function handlers.pvpResult()
	finish()
end

-- the round countdown: n = 3, 2, 1, then 0 = BOX! (movement and punches come back exactly then)
function handlers.countdown(msg)
	local n = tonumber(msg.n) or 0
	Countdown.Show(n, msg.round)
	if n <= 0 then
		F.countdown = false
		F.active = true
		refreshControls()
		cheer(0.6)
	else
		F.countdown = true
	end
end

function handlers.sparResult()
	finish()
end

function handlers.aborted()
	finish()
end

FightRemote.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then
		return
	end
	local h = handlers[msg.t]
	if h then
		local ok, err = pcall(h, msg)
		if not ok then
			warn("[FightClient]", msg.t, err)
		end
	end
end)

player.CharacterAdded:Connect(function()
	ragdoll = nil -- the old rig is gone with its constraints
	if F.active or gui.Enabled then
		finish()
	end
end)
