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
-- Controls: 1/J jab, 2/K cross, 3/L lead hook, 4 rear hook, 5/U uppercut, 6/O overhand,
-- hold SHIFT = to the body, hold F block, R parry, Q/E slip, C roll, Z/X pivot, G clinch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local FightRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fight")

local gui = UI.New("ScreenGui", { Name = "FightUI", ResetOnSpawn = false, IgnoreGuiInset = false, Enabled = false, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })

local F = {} -- current fight state
local camConn, fxConn
local music
local savedLighting

local function send(msg)
	FightRemote:FireServer(msg)
end

-- accessibility scale for blur / shake / flashes / colour (0 disables them)
local function fxScale()
	return math.clamp(tonumber(Config.ScreenFX) or 1, 0, 2)
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
-- HUD
------------------------------------------------------------------------
local bug = UI.Frame(gui, { Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(16, 6), BackgroundColor3 = T.red })
UI.Corner(bug, 4)
local bugText = UI.Text(bug, "LIVE  -  WCB SPORTS", { Font = T.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })

local function tierColor(tier)
	local def = Config.HeadTiers[(tier or 0) + 1] or Config.HeadTiers[1]
	local c = def.rgb
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a bar with a permanent-damage cap (striped, from the far end), a trailing white "ghost" that
-- shows the chunk just lost, and the live fill. side "R" depletes toward the outside edge.
local function hudBar(parent, y, label, color, side)
	local right = side == "R"
	UI.Text(parent, label, { TextSize = 11, Font = T.semi, TextColor3 = T.sub, Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(58, 14), AutomaticSize = Enum.AutomaticSize.None })
	local bg = UI.Frame(parent, { Position = UDim2.new(0, 68, 0, y), Size = UDim2.new(1, -78, 0, 14), BackgroundColor3 = Color3.fromRGB(16, 16, 20), ClipsDescendants = true })
	UI.Corner(bg, 3)
	local anchor = right and Vector2.new(1, 0) or Vector2.new(0, 0)
	local pos = right and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 0)
	local ghost = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), AnchorPoint = anchor, Position = pos, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25, ZIndex = 2 })
	local fill = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), AnchorPoint = anchor, Position = pos, BackgroundColor3 = color, ZIndex = 3 })
	UI.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)), Parent = fill })
	-- the cap eats in from the far end: damage that will not come back this fight
	local cap = UI.Frame(bg, { Size = UDim2.fromScale(0, 1), AnchorPoint = right and Vector2.new(0, 0) or Vector2.new(1, 0),
		Position = right and UDim2.fromScale(0, 0) or UDim2.fromScale(1, 0), BackgroundColor3 = Color3.fromRGB(70, 14, 18), ZIndex = 4 })
	UI.New("UIGradient", { Rotation = 35, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.24, 0.1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(0.49, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(0.74, 0.1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 0.55),
	}), Parent = cap })
	local value = UI.Text(bg, "", { TextSize = 10, Font = T.semi, TextStrokeTransparency = 0.4, ZIndex = 5, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = value })
	return { bg = bg, fill = fill, ghost = ghost, cap = cap, value = value, v = 1, ghostV = 1, pending = false }
end

local function setBar(b, frac, capFrac, color)
	frac = math.clamp(frac or 0, 0, 1)
	capFrac = math.clamp(capFrac or 1, 0, 1)
	b.fill.Size = UDim2.fromScale(frac, 1)
	if color then
		b.fill.BackgroundColor3 = color
	end
	b.cap.Size = UDim2.fromScale(1 - capFrac, 1)
	b.value.Text = tostring(math.floor(frac * 100 + 0.5))
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

local function fighterPanel(side)
	local f = UI.Frame(gui, { Size = UDim2.new(0.34, 0, 0, side == "L" and 116 or 106), Position = side == "L" and UDim2.new(0, 16, 0, 40) or UDim2.new(1, -16, 0, 40),
		AnchorPoint = side == "L" and Vector2.new(0, 0) or Vector2.new(1, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 0.2 })
	UI.Corner(f, 8)
	UI.Stroke(f, side == "L" and T.red or T.blue, 2)
	UI.New("UISizeConstraint", { MinSize = Vector2.new(250, 0), Parent = f })
	local name = UI.Text(f, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = side == "L" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
	-- status chip: sits at the inner end of the name row
	local chip = UI.Frame(f, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = side == "L" and Vector2.new(1, 0) or Vector2.new(0, 0),
		Position = side == "L" and UDim2.new(1, -8, 0, 6) or UDim2.new(0, 8, 0, 6), BackgroundColor3 = T.gold, Visible = false, ZIndex = 6 })
	UI.Corner(chip, 4)
	local chipText = UI.Text(chip, "", { Font = T.bold, TextSize = 11, TextColor3 = Color3.fromRGB(15, 15, 18), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 7,
		TextXAlignment = Enum.TextXAlignment.Center })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = chipText })
	local p = {
		frame = f, name = name, chip = chip, chipText = chipText,
		head = hudBar(f, 32, "HEAD", T.green, side), body = hudBar(f, 52, "BODY", T.orange, side), stam = hudBar(f, 72, "STAMINA", T.blue, side),
	}
	if side == "L" then
		-- the player's own legs: below a third, the next big shot (or a whiffed hook) staggers you
		UI.Text(f, "BALANCE", { TextSize = 9, Font = T.semi, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 92), Size = UDim2.fromOffset(58, 12), AutomaticSize = Enum.AutomaticSize.None })
		local bg = UI.Frame(f, { Position = UDim2.new(0, 68, 0, 95), Size = UDim2.new(1, -78, 0, 5), BackgroundColor3 = Color3.fromRGB(16, 16, 20) })
		UI.Corner(bg, 2)
		p.bal = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 200, 210) })
		UI.Corner(p.bal, 2)
	end
	return p
end
local L = fighterPanel("L")
local R = fighterPanel("R")

local clock = UI.Frame(gui, { Size = UDim2.fromOffset(150, 70), Position = UDim2.new(0.5, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 0.15 })
UI.Corner(clock, 8)
UI.Stroke(clock, T.gold, 2)
local roundText = UI.Text(clock, "ROUND 1", { Font = T.bold, TextSize = 14, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 4), AutomaticSize = Enum.AutomaticSize.None })
local timeText = UI.Text(clock, "1:00", { Font = T.bold, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.None })
local angleTag = UI.Text(gui, "ANGLE! +ACCURACY", { Font = T.bold, TextSize = 14, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(200, 20), Position = UDim2.new(0.5, -100, 0, 114), Visible = false, AutomaticSize = Enum.AutomaticSize.None })

local banner = UI.Text(gui, "", { Font = T.bold, TextSize = 60, TextColor3 = T.gold, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0, 0, 0.3, 0), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local flash = UI.Text(gui, "", { Font = T.bold, TextSize = 26, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0.5, 40), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local defFlash = UI.Text(gui, "", { Font = T.bold, TextSize = 22, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, 78), Visible = false, AutomaticSize = Enum.AutomaticSize.None })
local ticker = UI.Frame(gui, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), BackgroundColor3 = T.bg, BackgroundTransparency = 0.1 })
local tickerTag = UI.Frame(ticker, { Size = UDim2.fromOffset(110, 30), BackgroundColor3 = T.red })
UI.Text(tickerTag, "COMMENTARY", { Font = T.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })
local tickerText = UI.Text(ticker, "", { TextSize = 15, Font = T.semi, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(120, 0), Size = UDim2.new(1, -130, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
local controls = UI.Text(gui, "1/J Jab  2/K Cross  3/L Lead Hook  4 Rear Hook  5/U Uppercut  6/O Overhand  |  SHIFT body  F block  R parry  Q/E slip  C roll  Z/X pivot  G clinch  |  down: SPACE",
	{ TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -50), AutomaticSize = Enum.AutomaticSize.None })

local function showBanner(text, color, dur)
	banner.Text = text
	banner.TextColor3 = color or T.gold
	banner.Visible = true
	local id = os.clock()
	banner:SetAttribute("Id", id)
	task.delay(dur or 1.6, function()
		if banner:GetAttribute("Id") == id then
			banner.Visible = false
		end
	end)
end

local function showFlash(label, text, color, dur)
	label.Text = text
	label.TextColor3 = color or T.text
	label.Visible = true
	local id = os.clock()
	label:SetAttribute("Id", id)
	task.delay(dur or 0.8, function()
		if label:GetAttribute("Id") == id then
			label.Visible = false
		end
	end)
end

local function setTicker(text)
	tickerText.Text = text
end

-- overlay panel used for the tale of the tape / corner
local overlay = UI.Frame(gui, { Size = UDim2.new(0.94, 0, 0, 420), Position = UDim2.fromScale(0.5, 0.55), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.bg, BackgroundTransparency = 0.08, Visible = false })
UI.Corner(overlay, 12)
UI.Stroke(overlay, T.gold, 2)
UI.Pad(overlay, 14)
UI.List(overlay, 3)
UI.New("UISizeConstraint", { MaxSize = Vector2.new(660, 460), Parent = overlay })

-- an overlay line: { text, bold?, size?, color?, left? }
local function line(text, props)
	props = props or {}
	props[1] = text
	return props
end

local function overlayLines(lines)
	UI.Clear(overlay)
	for _, l in ipairs(lines) do
		UI.Text(overlay, l[1], { Font = l.bold and T.bold or T.font, TextSize = l.size or 16, TextColor3 = l.color or T.text,
			TextXAlignment = l.left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	end
	overlay.Visible = true
end

------------------------------------------------------------------------
-- Get-up: mash SPACE / tap, and time presses on the sweeping marker (green zone = worth 3)
------------------------------------------------------------------------
local getup = UI.Frame(gui, { Size = UDim2.fromOffset(440, 126), Position = UDim2.new(0.5, 0, 0.6, 0), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.bg, Visible = false })
UI.Corner(getup, 10)
UI.Stroke(getup, T.red, 2)
local getupTitle = UI.Text(getup, "YOU'RE DOWN!  MASH SPACE / TAP - HIT THE GREEN ZONE", { Font = T.bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.red, AutomaticSize = Enum.AutomaticSize.None })
local _, setGetup = UI.Bar(getup, { Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -32, 0, 18) }, T.gold)
local timing = UI.Frame(getup, { Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 0, 20), BackgroundColor3 = Color3.fromRGB(30, 30, 36) })
UI.Corner(timing, 4)
local zone = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.25 })
UI.Corner(zone, 4)
local marker = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.15), Size = UDim2.new(0, 4, 1.3, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
local getupHint = UI.Text(getup, "", { TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.None })

local function getupPress()
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

local getupBtn = UI.Button(getup, "", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, getupPress)
getupBtn.Text = ""

-- punches go through throwPunch (defined with the input code) so taps are predicted like keys
local throwPunch

-- touch controls
local touchPad
local function buildTouch()
	if touchPad or not UserInputService.TouchEnabled then
		return
	end
	touchPad = UI.Frame(gui, { BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 186), Position = UDim2.new(1, -12, 1, -56), AnchorPoint = Vector2.new(1, 1) })
	UI.Grid(touchPad, 70, 56, 6)
	local function tb(label, color, down, up)
		local b = UI.Button(touchPad, label, { BackgroundColor3 = color or T.panel2, BackgroundTransparency = 0.15, TextSize = 13 })
		b.MouseButton1Down:Connect(down)
		if up then
			b.MouseButton1Up:Connect(up)
		end
		return b
	end
	local function punch(p)
		return function()
			throwPunch(p, F.bodyMod == true and p ~= "overhand")
		end
	end
	tb("JAB", T.red, punch("jab"))
	tb("CROSS", T.red, punch("cross"))
	tb("L.HOOK", T.red, punch("leadhook"))
	tb("R.HOOK", T.red, punch("rearhook"))
	tb("UPPER", T.red, punch("uppercut"))
	tb("OVER\nHAND", T.red, punch("overhand"))
	local bodyBtn
	bodyBtn = tb("BODY", T.orange, function()
		F.bodyMod = not F.bodyMod
		bodyBtn.BackgroundColor3 = F.bodyMod and T.gold or T.orange
		showFlash(flash, F.bodyMod and "BODY SHOTS" or "HEAD SHOTS", T.gold)
	end)
	tb("BLOCK", T.blue, function()
		send({ t = "block", on = true })
	end, function()
		send({ t = "block", on = false })
	end)
	tb("PARRY", T.blue, function()
		send({ t = "parry" })
	end)
	tb("SLIP L", T.blue, function()
		send({ t = "slip", dir = -1 })
	end)
	tb("SLIP R", T.blue, function()
		send({ t = "slip", dir = 1 })
	end)
	tb("ROLL", T.blue, function()
		send({ t = "roll" })
	end)
	tb("PIVOT L", T.green, function()
		send({ t = "pivot", dir = -1 })
	end)
	tb("PIVOT R", T.green, function()
		send({ t = "pivot", dir = 1 })
	end)
	tb("CLINCH", T.green, function()
		send({ t = "clinch" })
	end)
end

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
local FX = { shake = 0, hitBlur = 0, fovKick = 0, roll = 0, rollVel = 0, hitStop = 0, grade = 0, heartAt = 0, downBlur = 0, vig = -1, vigTier = -1 }
local VIG_RED, VIG_BLACK, WHITE = Color3.fromRGB(60, 0, 0), Color3.new(0, 0, 0), Color3.new(1, 1, 1)

------------------------------------------------------------------------
-- Sweat & blood spray (client-only emitters, Emit bursts) and blood drops on the canvas
------------------------------------------------------------------------
local SPRAY_TEX = "rbxasset://textures/particles/sparkles_main.dds"
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
		pe.LightEmission = name == "Sweat" and 0.35 or 0
		pe.LightInfluence = 1
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
	Arena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(38, 38, 46), OutdoorAmbient = Color3.fromRGB(30, 30, 40), Exposure = 0.3 },
	ClubArena = { ClockTime = 21, Brightness = 0.6, Ambient = Color3.fromRGB(46, 44, 50), OutdoorAmbient = Color3.fromRGB(35, 35, 42), Exposure = 0.25 },
	CommunityCenter = { ClockTime = 19, Brightness = 1, Ambient = Color3.fromRGB(80, 80, 86), OutdoorAmbient = Color3.fromRGB(70, 70, 80), Exposure = 0 },
	Gym = { ClockTime = 14, Brightness = 0.9, Ambient = Color3.fromRGB(78, 78, 86), OutdoorAmbient = Color3.fromRGB(95, 95, 105), Exposure = -0.1 },
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

local function cheer(amount)
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
local FADE_NAMES = { Rope = true, Post = true, Pad = true, TurnbucklePad = true }
local function setFade(p, on)
	p.LocalTransparencyModifier = on and 0.8 or 0
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Beam") then
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
	if blurFx then
		local size = (Config.Concussion.blurPerTier * tier + Config.Concussion.blurPerConc * conc + FX.hitBlur + FX.downBlur) * fx
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
		task.delay(0.16, function()
			sfx(id, 0.32, 0.35)
		end)
	end
	-- the player's HUD head bar pulses at danger
	if tier >= 2 then
		local p = math.sin(now * (tier >= 3 and 9 or 5)) * 0.5 + 0.5
		L.head.fill.BackgroundColor3 = tierColor(tier):Lerp(Color3.new(1, 1, 1), p * 0.35)
	end
	local ot = F.opp and F.oppState and F.oppState.tier or 0
	if ot >= 2 then
		local p = math.sin(now * (ot >= 3 and 9 or 5)) * 0.5 + 0.5
		R.head.fill.BackgroundColor3 = tierColor(ot):Lerp(Color3.new(1, 1, 1), p * 0.35)
	end
	return tier, conc, fx
end

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
		local sh = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * FX.shake * fx
		local goal
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
			-- a 3/4 angle (about 40 degrees off the fight line) keeps both fighters readable instead of stacked
			local function camPos(side)
				return me.Position - dir * 6.6 + right * (side * 5.8) + Vector3.new(0, 5.4, 0)
			end
			local function flatDist(a, b)
				return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
			end
			F.camSide = F.camSide or 1
			local pos = camPos(F.camSide)
			local other = camPos(-F.camSide)
			if flatDist(other, center) + 3 < flatDist(pos, center) then
				F.camSide = -F.camSide
				pos = other
			end
			goal = CFrame.lookAt(pos, mid)
		end
		if goal then
			-- drunk camera: a slow, sick sway that grows with the head tier and concussion
			local sway = (tier * 0.35 + conc) * fx
			if sway > 0.01 and camMode == "fight" then
				goal *= CFrame.Angles(math.sin(now * 0.8) * 0.01 * sway, math.sin(now * 1.1) * 0.02 * sway, math.sin(now * 0.7) * 0.04 * sway)
			end
			if math.abs(FX.roll) > 0.0005 then
				goal *= CFrame.Angles(0, 0, FX.roll * fx)
			end
			if FX.hitStop > now then
				-- hit-stop: freeze the picture for a few frames on a big landed shot
				cam.CFrame += sh
			elseif F.broadcastUntil and now < F.broadcastUntil then
				cam.CFrame = goal + sh
			else
				cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 8, 0, 1)) + sh
			end
		end
		cam.FieldOfView = math.clamp((baseFov or 70) + FX.fovKick * fx, 40, 100)
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
-- Input (with local punch prediction: the Animator starts the punch on the key press)
------------------------------------------------------------------------
local keyPunch = {
	[Enum.KeyCode.One] = "jab", [Enum.KeyCode.J] = "jab",
	[Enum.KeyCode.Two] = "cross", [Enum.KeyCode.K] = "cross",
	[Enum.KeyCode.Three] = "leadhook", [Enum.KeyCode.L] = "leadhook",
	[Enum.KeyCode.Four] = "rearhook", [Enum.KeyCode.Semicolon] = "rearhook",
	[Enum.KeyCode.Five] = "uppercut", [Enum.KeyCode.U] = "uppercut",
	[Enum.KeyCode.Six] = "overhand", [Enum.KeyCode.O] = "overhand",
}

local pred = { id = 0, busyUntil = 0, lastAt = 0, hand = "R" }
throwPunch = function(p, body)
	send({ t = "punch", p = p, body = body })
	local P = Config.Punches[p]
	local char = player.Character
	local now = os.clock()
	-- only predict what the server will almost surely accept (not down / stumbling / mid-punch)
	if not P or not char or not F.active or F.down or now < (F.stumbleUntil or 0) or now < pred.busyUntil then
		return
	end
	local stam = F.me and F.me.max and F.me.stam / math.max(1, F.me.max) or 1
	local windup = P.windup * (stam < 0.3 and 1.25 or 1) * (1 + 0.08 * ((F.me and F.me.tier) or 0))
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

UserInputService.InputBegan:Connect(function(input, gp)
	if not F.active and not F.down then
		return
	end
	if gp then
		return
	end
	if F.down and (input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1) then
		getupPress()
		return
	end
	if not F.active then
		return
	end
	local body = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) or F.bodyMod == true
	local p = keyPunch[input.KeyCode]
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		p = "jab"
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		p = "cross"
	end
	local k = input.KeyCode
	if p then
		throwPunch(p, body and p ~= "overhand")
	elseif k == Enum.KeyCode.F then
		send({ t = "block", on = true })
	elseif k == Enum.KeyCode.R then
		send({ t = "parry" })
	elseif k == Enum.KeyCode.Q then
		send({ t = "slip", dir = -1 })
	elseif k == Enum.KeyCode.E then
		send({ t = "slip", dir = 1 })
	elseif k == Enum.KeyCode.C then
		send({ t = "roll" })
	elseif k == Enum.KeyCode.Z then
		send({ t = "pivot", dir = -1 })
	elseif k == Enum.KeyCode.X then
		send({ t = "pivot", dir = 1 })
	elseif k == Enum.KeyCode.G then
		send({ t = "clinch" })
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if F.active and input.KeyCode == Enum.KeyCode.F then
		send({ t = "block", on = false })
	end
end)

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
		return "CONCUSSED", Color3.fromRGB(190, 150, 255)
	elseif s.stam and s.max and s.stam < s.max * 0.2 then
		return "GASSED", Color3.fromRGB(150, 160, 175)
	elseif s.body and s.body < 30 then
		return "BODY HURT", T.orange
	end
	return nil
end

local function setChip(panel, text, color)
	if not text then
		panel.chip.Visible = false
		panel.chipLast = nil
		return
	end
	panel.chip.Visible = true
	panel.chip.BackgroundColor3 = color
	panel.chipText.Text = text
	if panel.chipLast ~= text then
		panel.chipLast = text
		-- pop when it changes
		panel.chip.Size = UDim2.fromOffset(0, 24)
		TweenService:Create(panel.chip, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(0, 18) }):Play()
	end
end

local function finish()
	F.active = false
	F.down = false
	gui.Enabled = false
	fxGui.Enabled = false
	overlay.Visible = false
	getup.Visible = false
	setRagdoll(false)
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
		spar = msg.spar, venue = msg.venue, venueName = msg.venueName, weighIn = msg.weighIn, notes = msg.notes, talk = msg.talk, myLine = msg.myLine }
	player:SetAttribute("InFight", true)
	gui.Enabled = true
	fxGui.Enabled = true
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = false, false, false, false
	setChip(L, nil)
	setChip(R, nil)
	if F.arena then
		local center = F.arena:FindFirstChild("Anchors") and F.arena.Anchors:FindFirstChild("RingCenter")
		F.center = center and center.Position
	end
	L.name.Text = msg.tape.you.name
	R.name.Text = msg.tape.opp.name
	local stakes = {}
	for _, s in ipairs(msg.stakes or {}) do
		table.insert(stakes, s)
	end
	for _, s in ipairs(msg.playerStakes or {}) do
		if not table.find(stakes, s) then
			table.insert(stakes, s)
		end
	end
	if F.spar then
		bugText.Text = "SPARRING  -  " .. string.upper(F.spar)
		bug.BackgroundColor3 = T.blue
		F.stakesText = string.format("SPARRING (%s) vs %s", string.upper(F.spar), msg.tape.opp.name)
	else
		bugText.Text = "LIVE  -  WCB SPORTS"
		bug.BackgroundColor3 = T.red
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
			music.SoundId = "rbxassetid://" .. msg.music
			music.Volume = 0.8
			music.SoundGroup = ensureMix()
			music.Parent = SoundService
			music:Play()
		end
	end
end

function handlers.tape()
	camMode = "tape"
	letterbox(true)
	local y, o = F.tape.you, F.tape.opp
	local function r(x)
		return string.format("%d-%d-%d (%d KO)", x.record.w, x.record.l, x.record.d, x.record.ko)
	end
	local lines = {
		{ "TALE OF THE TAPE", bold = true, size = 24, color = T.gold },
		{ F.stakesText, bold = true, size = 14, color = T.red },
		{ string.format("%s  vs  %s", y.name:upper(), o.name:upper()), bold = true, size = 21 },
		{ string.format("\"%s\"   -   \"%s\"", y.nick or "", o.nick or ""), color = T.sub },
		{ string.format("%s   RECORD   %s", r(y), r(o)) },
		{ string.format("%s   HEIGHT   %s", Config.HeightText(y.height), Config.HeightText(o.height)) },
		{ string.format("%d in   REACH   %d in", y.reach, o.reach) },
		{ string.format("%s   STYLE   %s", y.style, o.style) },
		{ string.format("%s   FROM   %s", y.nat, o.nat) },
		{ string.format("%d   OVERALL   %d", y.overall, o.overall), bold = true },
	}
	if o.archetype then
		table.insert(lines, { "Scouting report: " .. o.archetype, color = T.sub, size = 14 })
	end
	local wi = F.weighIn
	if wi then
		if wi.over > 0 then
			table.insert(lines, { string.format("WEIGH-IN: %.1f lbs (limit %d) - MISSED WEIGHT by %.1f lbs: stamina -%d%%%s", wi.weight, wi.limit, wi.over, math.floor(wi.penalty * 100), wi.fine > 0 and ", fined 20% of your purse" or ""), color = T.red, size = 14, bold = true })
		else
			table.insert(lines, { string.format("WEIGH-IN: %.1f lbs (limit %d) - MADE WEIGHT", wi.weight, wi.limit), color = T.green, size = 14 })
		end
	end
	if F.notes and #F.notes > 0 then
		table.insert(lines, { "Your condition: " .. table.concat(F.notes, ", "), color = T.orange, size = 13 })
	end
	if F.talk and F.talk ~= "" then
		table.insert(lines, { "\"" .. F.talk .. "\"  - " .. o.name, color = Color3.fromRGB(255, 160, 160), size = 14 })
	end
	if F.myLine and F.myLine ~= "" then
		table.insert(lines, { "\"" .. F.myLine .. "\"  - " .. y.name, color = Color3.fromRGB(160, 200, 255), size = 14 })
	end
	overlayLines(lines)
	stopMusic()
end

function handlers.round(msg)
	overlay.Visible = false
	setAnimate(false)
	F.active = true
	camMode = "fight"
	F.broadcastUntil = nil
	letterbox(false)
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = true, true, true, true
	roundText.Text = string.format("ROUND %d / %d", msg.n, msg.total)
	timeText.Text = fmtTime(F.spar and Config.SparRoundSeconds or Config.RoundSeconds)
	showBanner("ROUND " .. msg.n, T.gold, 1.8)
	phase("round", { n = msg.n })
	if not venueOn then
		sfx(BUILTIN.Ping or "rbxasset://sounds/electronicpingshort.wav", 0.55, 0.6)
	end
	screens("ROUND " .. msg.n)
	cheer(0.5)
end

function handlers.state(msg)
	timeText.Text = fmtTime(msg.time)
	F.me, F.oppState = msg.me, msg.opp
	local function apply(panel, s, female)
		local tier = s.tier or 0
		local headColor = tier >= 1 and tierColor(tier) or (s.hurt and T.gold or T.green)
		if tier < 2 then
			setBar(panel.head, s.hp / 100, (s.cap or 100) / 100, headColor)
		else
			setBar(panel.head, s.hp / 100, (s.cap or 100) / 100) -- colour pulses in updateFX
		end
		setBar(panel.body, s.body / 100, (s.bodyCap or 100) / 100, s.body < 30 and T.red or T.orange)
		local max = math.max(1, s.max or 100)
		setBar(panel.stam, s.stam / max, (s.stamCap or max) / max, s.stam < max * 0.25 and Color3.fromRGB(120, 125, 140) or T.blue)
		setChip(panel, chipFor(s, s.hurt, female))
	end
	apply(L, msg.me, F.tape and F.tape.you.female)
	apply(R, msg.opp, F.tape and F.tape.opp.female)
	if L.bal and msg.me.bal then
		local b = math.clamp(msg.me.bal / 100, 0, 1)
		L.bal.Size = UDim2.fromScale(b, 1)
		L.bal.BackgroundColor3 = b < 0.3 and T.red or (b < 0.55 and T.gold or Color3.fromRGB(200, 200, 210))
	end
	angleTag.Visible = msg.me.angle == true
	vfx("State", msg)
end

function handlers.hit(msg)
	local mine = msg.who == "you"
	local target = mine and F.opp or player.Character
	local attacker = mine and player.Character or F.opp
	local sev = msg.sev or (msg.heavy and 1 or 0.4)
	local fx = fxScale()
	if msg.body then
		sfx(soundId("BodyShot", "Thud"), 0.95 + math.random() * 0.1 - (msg.heavy and 0.15 or 0), math.clamp(0.4 + sev * 0.45, 0.35, 1))
	else
		sfx(soundId("PunchImpact", "Thud"), 1.2 + math.random() * 0.15 - (msg.heavy and 0.25 or 0), math.clamp(0.35 + sev * 0.5, 0.35, 1))
	end
	if msg.heavy then
		sfx(BUILTIN.SwordHit or "rbxasset://sounds/swordhit.wav", 0.45 + math.random() * 0.1, 0.25)
	end
	-- spray flies off the far side of the target, along the punch
	local tr, ar = getRoot(target), getRoot(attacker)
	if tr and ar then
		local dir = tr.Position - ar.Position
		dir = Vector3.new(dir.X, 0.35, dir.Z)
		if dir.Magnitude > 0.05 then
			spray(target, msg.body and "UpperTorso" or "Head", dir.Unit, sev, msg.bleed == true and not msg.body)
		end
	end
	vfx("Hit", { target = target, heavy = msg.heavy == true, dmg = msg.dmg, punch = msg.punch })
	if msg.heavy then
		cheer(0.5)
	end
	if mine then
		if msg.heavy then
			FX.hitStop = os.clock() + 0.06
			flashFrame(whiteFlash, 1 - 0.18 * fx, 0.15)
		end
	else
		-- taking it: the picture lurches toward the side the punch came from, blurs and flashes red
		FX.shake = math.max(FX.shake, 0.25 + sev * 0.45)
		FX.rollVel += (msg.hand == "L" and 1 or -1) * (msg.body and 0.15 or 0.6) * sev
		if msg.heavy then
			FX.hitBlur = math.max(FX.hitBlur, 4 + sev * 7)
			FX.fovKick = -6 * sev
			flashFrame(redFlash, 1 - math.clamp(0.25 + sev * 0.25, 0, 0.6) * fx, 0.35)
		end
		if msg.body then
			FX.grade = math.max(FX.grade, 0.6 * sev) -- breath knocked out of you
		end
	end
	local text = (msg.counter and "COUNTER " or "") .. (PUNCH_NAME[msg.punch] or tostring(msg.punch):upper()) .. (msg.body and " TO THE BODY" or "")
	if msg.heavy or msg.counter then
		showFlash(flash, text .. "!", mine and T.gold or T.red)
	end
end

function handlers.blocked(msg)
	sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 1.9, 0.25)
	if msg.who == "you" then
		showFlash(flash, "BLOCKED", T.blue, 0.5)
		FX.shake = math.max(FX.shake, 0.08)
	end
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
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and dir.Magnitude > 0.05 then
			local unit = dir.Unit
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if os.clock() > F.stumbleUntil or not hum.Parent then
					conn:Disconnect()
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

local SEVERITY_TEXT = { flash = "FLASH KNOCKDOWN!", heavy = "DOWN HARD!", out = "OUT COLD!" }
function handlers.kd(msg)
	local mine = msg.who == "you"
	local target = mine and player.Character or F.opp
	sfx(BUILTIN.Falling or "rbxasset://sounds/action_falling.ogg", 0.7, 1)
	sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 0.5, 0.9)
	phase("kd", { who = msg.who, target = target, severity = msg.severity })
	cheer(1.6)
	FX.shake = 1
	sweeping = 3
	camMode = "wide"
	letterbox(true)
	local name = mine and "YOU'RE DOWN!" or ("DOWN GOES " .. F.tape.opp.name:upper() .. "!")
	if msg.severity == "out" and not mine then
		name = F.tape.opp.name:upper() .. " IS OUT COLD!"
	end
	showBanner(name, mine and T.red or T.gold, 2.5)
	if SEVERITY_TEXT[msg.severity] and msg.severity ~= "out" then
		showFlash(defFlash, SEVERITY_TEXT[msg.severity], mine and T.red or T.gold, 2)
	end
	screens(msg.severity == "out" and "KNOCKOUT!" or "KNOCKDOWN!")
	if mine then
		F.down = true
		F.mash = 0
		F.downAt = os.clock()
		flashFrame(redFlash, 1 - 0.6 * fxScale(), 0.8)
		if msg.severity == "out" then
			-- lights out: ragdoll and fade to near-black
			setRagdoll(true)
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
	getupTitle.Text = msg.severity == "flash" and "FLASH KNOCKDOWN! SHAKE IT OFF - MASH / HIT THE GREEN" or "YOU'RE DOWN!  MASH SPACE / TAP - HIT THE GREEN ZONE"
	getupHint.Text = string.format("Get up before 10. Green-zone presses count triple. (needed: %d)", msg.target or 10)
	getup.Visible = true
end

function handlers.count(msg)
	local n = msg.n or 0
	if msg.standing then
		showBanner("EIGHT COUNT: " .. n, Color3.fromRGB(230, 230, 230), 0.5)
	else
		showBanner(tostring(n), Color3.new(1, 1, 1), 0.8)
	end
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
		sfx(BUILTIN.Grunt or "rbxasset://sounds/uuhhh.mp3", 1, 0.5)
		FX.hitBlur = 10 -- the world swims back into focus
	end
	phase("getup", { who = msg.who })
	cheer(0.8)
	setTicker(mine and "You beat the count! Show the referee you can continue..." or (F.tape.opp.name .. " beats the count!"))
end

function handlers.refcheck(msg)
	if msg.ok then
		showBanner("OK TO CONTINUE", T.green, 1.2)
		camMode = "fight"
		letterbox(false)
	else
		showBanner("WAVED OFF!", T.red, 2.5)
		cheer(1.2)
	end
end

function handlers.bell(msg)
	F.active = false
	showBanner("DING DING DING", T.gold, 1.5)
	setTicker("End of round " .. msg.n)
	phase("bell", { n = msg.n })
	if not venueOn then
		local bell = BUILTIN.Ping or "rbxasset://sounds/electronicpingshort.wav"
		for i = 0, 2 do
			task.delay(i * 0.28, function()
				sfx(bell, 0.6, 0.7)
			end)
		end
	end
end

function handlers.rest(msg)
	camMode = "wide"
	phase("rest", { n = msg.n })
	local lines = {
		{ "YOUR CORNER  -  END OF ROUND " .. msg.n, bold = true, size = 22, color = T.gold },
		{ string.format("Unofficial card: %d - %d   (this round %d-%d)", msg.unofficial[1], msg.unofficial[2], msg.card[1], msg.card[2]), bold = true },
		{ string.format("Punches: you %d/%d   opponent %d/%d", msg.stats.landed, msg.stats.thrown, msg.stats.oppLanded, msg.stats.oppThrown), color = T.sub },
	}
	local c = msg.cond
	if type(c) == "table" then
		table.insert(lines, line(string.format("HEAD %d%% (max %d%%)    BODY %d%% (max %d%%)", c.head or 0, c.cap or 100, c.body or 0, c.bodyCap or 100), { color = (c.head or 100) < 30 and T.red or T.text, size = 14 }))
		if c.notes and #c.notes > 0 then
			table.insert(lines, line("Cutman: " .. table.concat(c.notes, "  |  "), { color = T.orange, size = 13 }))
		end
	end
	for _, a in ipairs(msg.advice) do
		table.insert(lines, { "\"" .. a .. "\"", left = true })
	end
	overlayLines(lines)
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
