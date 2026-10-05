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

local gui = UI.New("ScreenGui", { Name = "FightUI", ResetOnSpawn = false, IgnoreGuiInset = false, Enabled = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui") })

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
-- The HUD lives on a scaled root (UI.MountRoot): built on the 1600 x 900 design canvas.
local hud = UI.MountRoot(gui, "HUDRoot")
local GuiService = game:GetService("GuiService")

local bug = UI.Frame(hud, { Name = "Bug", Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152),
	BackgroundColor3 = T.red, Visible = false })
UI.Corner(bug, 4)
local bugText = UI.Text(bug, "LIVE  ·  WCB SPORTS", { Font = T.semi, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false })
UI.Pad(bugText, 0, 10)

local function tierColor(tier)
	local def = Config.HeadTiers[(tier or 0) + 1] or Config.HeadTiers[1]
	local c = def.rgb
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a bar with a permanent-damage cap (striped, from the far end), a trailing white "ghost" that
-- shows the chunk just lost, and the live fill. side "R" depletes toward the outside edge.
-- label (optional) sits inside the bar on the near end; the value on the far end.
local function hudBar(parent, props, color, side, label, thick)
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
	local value = UI.Text(bg, "", { Name = "Value", Face = "number", TextSize = thick and 15 or 11, TextStrokeTransparency = 0.5, ZIndex = 5, Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = value })
	if label then
		local l = UI.Text(bg, label, { Name = "Label", Font = T.semi, TextSize = thick and 11 or 9, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.6, ZIndex = 5,
			Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, TextWrapped = false })
		UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = l })
	end
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

-- the little body silhouette that flashes where a punch lands (head, left / right ribs)
local function zoneMap(parent, side)
	local f = UI.Frame(parent, { Name = "Zones", BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 74), AnchorPoint = Vector2.new(side == "L" and 0 or 1, 0),
		Position = side == "L" and UDim2.fromOffset(12, 48) or UDim2.new(1, -12, 0, 48) })
	local head = UI.Frame(f, { Name = "Head", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(18, 20), BackgroundColor3 = T.panel2 })
	UI.Corner(head, 9)
	local bodyL = UI.Frame(f, { Name = "BodyL", Position = UDim2.fromOffset(2, 24), Size = UDim2.fromOffset(14, 34), BackgroundColor3 = T.panel2 })
	UI.Corner(bodyL, 5)
	local bodyR = UI.Frame(f, { Name = "BodyR", Position = UDim2.fromOffset(18, 24), Size = UDim2.fromOffset(14, 34), BackgroundColor3 = T.panel2 })
	UI.Corner(bodyR, 5)
	local hips = UI.Frame(f, { Name = "Hips", Position = UDim2.fromOffset(5, 60), Size = UDim2.fromOffset(24, 12), BackgroundColor3 = T.panel2, BackgroundTransparency = 0.4 })
	UI.Corner(hips, 4)
	return { frame = f, head = head, bodyL = bodyL, bodyR = bodyR }
end

-- small status icons: cut (a drop), swelling (an eye), ribs (bars)
local function statusIcon(parent, kind, color, order)
	local f = UI.Frame(parent, { Name = kind, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, BackgroundTransparency = 0.2, Visible = false, LayoutOrder = order })
	UI.Corner(f, 4)
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 6), Parent = f })
	UI.List(f, 4, true)
	local glyph = UI.Frame(f, { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 18), LayoutOrder = 1 })
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
			UI.Frame(glyph, { Position = UDim2.fromOffset(1, 4 + i * 4), Size = UDim2.fromOffset(8, 2), BackgroundColor3 = Color3.new(1, 1, 1) })
		end
	end
	UI.Text(f, string.upper(kind), { Font = T.semi, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false, LayoutOrder = 2 })
	return f
end

local board = UI.Frame(hud, { Name = "Scoreboard", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(1, -40, 0, 134) })
UI.New("UISizeConstraint", { MaxSize = Vector2.new(1380, 134), Parent = board })
local boardScale = UI.New("UIScale", { Name = "Fit", Parent = board })

local function fighterPanel(side)
	local left = side == "L"
	local accent = left and T.red or T.blue
	local f = UI.Frame(board, { Name = left and "You" or "Opponent", Size = UDim2.new(0.5, -96, 1, 0), Position = left and UDim2.fromScale(0, 0) or UDim2.fromScale(1, 0),
		AnchorPoint = left and Vector2.new(0, 0) or Vector2.new(1, 0), Visible = false })
	UI.Glass(f, { transparency = 0.12, radius = UI.R.lg })
	-- the corner colour along the outer edge
	local edge = UI.Frame(f, { Name = "Corner", AnchorPoint = Vector2.new(left and 0 or 1, 0), Position = left and UDim2.fromOffset(0, 10) or UDim2.new(1, 0, 0, 10), Size = UDim2.new(0, 4, 1, -20), BackgroundColor3 = accent })
	UI.Corner(edge, 2)
	local inner = 56 -- room for the zone silhouette on the outer side
	local align = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	local flagHolder = UI.Frame(f, { Name = "FlagHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 20), AnchorPoint = Vector2.new(left and 0 or 1, 0),
		Position = left and UDim2.fromOffset(16, 13) or UDim2.new(1, -16, 0, 13) })
	local name = UI.Text(f, "", { Name = "Name", Face = "display", TextSize = 26, Position = left and UDim2.fromOffset(54, 6) or UDim2.new(0, 120, 0, 6), Size = UDim2.new(1, -174, 0, 32),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if not left then
		name.Position = UDim2.new(0, 120, 0, 6)
		name.Size = UDim2.new(1, -174, 0, 32)
	end
	-- status chip at the inner end of the name row (ROCKED / DAZED / ...)
	local chip = UI.Frame(f, { Name = "Chip", Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = left and Vector2.new(1, 0) or Vector2.new(0, 0),
		Position = left and UDim2.new(1, -12, 0, 12) or UDim2.new(0, 12, 0, 12), BackgroundColor3 = T.gold, Visible = false, ZIndex = 6 })
	UI.Corner(chip, 4)
	local chipText = UI.Text(chip, "", { Font = T.semi, TextSize = 11, TextColor3 = T.ink, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 7,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = chipText })
	-- record + knockdown tally under the name
	local sub = UI.Text(f, "", { Name = "Sub", Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = left and UDim2.fromOffset(54, 36) or UDim2.new(0, 120, 0, 36),
		Size = UDim2.new(1, -174, 0, 12), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align, TextWrapped = false })
	local kdRow = UI.Frame(f, { Name = "KD", BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 12), AnchorPoint = left and Vector2.new(1, 0) or Vector2.new(0, 0),
		Position = left and UDim2.new(1, -12, 0, 36) or UDim2.new(0, 12, 0, 36) })
	UI.List(kdRow, 3, true, left and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left)
	-- HEALTH (overall), then HEAD | BODY | STAMINA
	local x0 = left and inner or 12
	local barW = UDim2.new(1, -(inner + 12), 0, 16)
	local health = hudBar(f, { Name = "Health", Position = UDim2.fromOffset(x0, 54), Size = barW }, T.green, side, "HEALTH", true)
	local row = UI.Frame(f, { Name = "Pools", BackgroundTransparency = 1, Position = UDim2.fromOffset(x0, 76), Size = UDim2.new(1, -(inner + 12), 0, 26) })
	local function pool(i, caption, color)
		local cell = UI.Frame(row, { BackgroundTransparency = 1, Position = UDim2.new((i - 1) / 3, i > 1 and 4 or 0, 0, 0), Size = UDim2.new(1 / 3, -6, 1, 0) })
		UI.Text(cell, caption, { Font = T.semi, TextSize = 9, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 11), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align, TextWrapped = false })
		return hudBar(cell, { Position = UDim2.fromOffset(0, 13), Size = UDim2.new(1, 0, 0, 10) }, color, side)
	end
	local head = pool(left and 1 or 3, "HEAD", T.green)
	local body = pool(2, "BODY", T.orange)
	local stam = pool(left and 3 or 1, "STAMINA", T.blue)
	-- damage icons + the player's balance
	local icons = UI.Frame(f, { Name = "Icons", BackgroundTransparency = 1, Position = UDim2.fromOffset(x0, 108), Size = UDim2.new(1, -(inner + 12), 0, 18) })
	UI.List(icons, 5, true, left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right)
	local p = {
		frame = f, name = name, sub = sub, chip = chip, chipText = chipText, flag = flagHolder, kd = kdRow, kdCount = 0,
		health = health, head = head, body = body, stam = stam, zones = zoneMap(f, side),
		cut = statusIcon(icons, "Cut", T.red, 1), swell = statusIcon(icons, "Swelling", T.purple, 2), ribs = statusIcon(icons, "Ribs", T.orange, 3),
	}
	if left then
		-- the player's own legs: below a third, the next big shot (or a whiffed hook) staggers you
		local balHolder = UI.Frame(icons, { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 18), LayoutOrder = 9 })
		UI.Text(balHolder, "BALANCE", { Font = T.semi, TextSize = 9, TextColor3 = T.sub, Size = UDim2.fromOffset(52, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		local bg = UI.Frame(balHolder, { Position = UDim2.new(0, 54, 0.5, -2), Size = UDim2.new(1, -54, 0, 4), BackgroundColor3 = T.ink })
		UI.Corner(bg, 2)
		p.bal = UI.Frame(bg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 200, 210) })
		UI.Corner(p.bal, 2)
	end
	return p
end
local L = fighterPanel("L")
local R = fighterPanel("R")

-- one red "KD" tag per knockdown under the fighter's name
local function addKD(panel)
	panel.kdCount += 1
	local c = UI.Frame(panel.kd, { Name = "KD" .. panel.kdCount, Size = UDim2.fromOffset(24, 12), BackgroundColor3 = T.red, LayoutOrder = panel.kdCount })
	UI.Corner(c, 3)
	UI.Text(c, "KD", { Font = T.semi, TextSize = 9, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
end

-- center: the round and the clock, the crowd meter underneath
local clock = UI.Frame(board, { Name = "Clock", Size = UDim2.new(0, 176, 1, 0), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), Visible = false })
UI.Glass(clock, { transparency = 0.06, radius = UI.R.lg, color = T.ink })
local clockTop = UI.Frame(clock, { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.gold })
UI.Corner(clockTop, UI.R.lg)
UI.Frame(clockTop, { Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = T.gold })
local roundText = UI.Text(clockTop, "ROUND 1", { Face = "displayMed", TextSize = 18, TextColor3 = T.ink, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
	AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
local timeText = UI.Text(clock, "1:00", { Face = "number", TextSize = 50, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 34),
	AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
local crowdBox = UI.Frame(clock, { Name = "Crowd", BackgroundTransparency = 1, Position = UDim2.new(0, 12, 1, -40), Size = UDim2.new(1, -24, 0, 30) })
local crowdLabel = UI.Text(crowdBox, "CROWD  ·  QUIET", { Font = T.semi, TextSize = 9, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 11), AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
local crowdBar = UI.Frame(crowdBox, { Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = T.ink })
UI.Corner(crowdBar, 4)
local crowdLeft = UI.Frame(crowdBar, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.red })
UI.Corner(crowdLeft, 4)
local crowdRight = UI.Frame(crowdBar, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.blue })
UI.Corner(crowdRight, 4)
local crowdGlow = UI.Frame(crowdBar, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 3, 1, 6), BackgroundColor3 = Color3.new(1, 1, 1) })
local crowdMeter = { level = 0.2, lean = 0, shownLevel = -1, shownLean = 99 }
local CROWD_WORDS = { { 0.85, "ON THEIR FEET" }, { 0.6, "ROARING" }, { 0.35, "BUZZING" }, { 0, "QUIET" } }
local function updateCrowd(dt)
	crowdMeter.lean *= math.exp(-dt / 6)
	local lvl = math.floor(crowdMeter.level * 20 + 0.5) / 20
	local lean = math.floor(crowdMeter.lean * 40 + 0.5) / 40
	if lvl == crowdMeter.shownLevel and lean == crowdMeter.shownLean then
		return
	end
	crowdMeter.shownLevel, crowdMeter.shownLean = lvl, lean
	crowdLeft.Size = UDim2.fromScale(math.clamp(lean, 0, 1) * 0.5, 1)
	crowdRight.Size = UDim2.fromScale(math.clamp(-lean, 0, 1) * 0.5, 1)
	crowdGlow.BackgroundTransparency = 0.6 - lvl * 0.6
	for _, w in ipairs(CROWD_WORDS) do
		if lvl >= w[1] then
			crowdLabel.Text = "CROWD  ·  " .. w[2]
			crowdLabel.TextColor3 = lvl >= 0.6 and T.gold or T.sub
			break
		end
	end
end

local angleTag = UI.Chip(hud, "ANGLE  +ACCURACY", T.gold, { solid = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 184), h = 24, TextSize = 12 })
angleTag.Visible = false

-- the big centre banner (ROUND 1, KNOCKDOWN, KO!): a band that opens with display type
local bannerBand = UI.Frame(hud, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(1, 0, 0, 120),
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
local flash = label(0.6, 36)
local defFlash = label(0.67, 28)

-- the lower third: live commentary
local ticker = UI.Frame(hud, { Name = "Ticker", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -48, 0, 40), BackgroundColor3 = T.bg })
UI.New("UISizeConstraint", { MaxSize = Vector2.new(1080, 40), Parent = ticker })
UI.Glass(ticker, { transparency = 0.12, radius = UI.R.md })
local tickerTag = UI.Frame(ticker, { Size = UDim2.new(0, 132, 1, 0), BackgroundColor3 = T.red })
UI.Corner(tickerTag, UI.R.md)
UI.Frame(tickerTag, { Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = T.red })
local liveDot = UI.Frame(tickerTag, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1) })
UI.Corner(liveDot, 4)
UI.Text(tickerTag, "COMMENTARY", { Font = T.semi, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0),
	AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
local tickerText = UI.Text(ticker, "", { TextSize = 15, Font = T.semi, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(146, 0), Size = UDim2.new(1, -160, 1, 0),
	AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
-- control hints (key caps) above the ticker; touch players get the pad instead
local controls = UI.Frame(hud, { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -62), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
UI.Glass(controls, { transparency = 0.35, radius = 15 })
UI.New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), Parent = controls })
UI.List(controls, 12, true, Enum.HorizontalAlignment.Center)
for i, k in ipairs({ { "1/J", "JAB" }, { "2/K", "CROSS" }, { "3/L", "L.HOOK" }, { "4", "R.HOOK" }, { "5/U", "UPPER" }, { "6/O", "OVERHAND" }, { "SHIFT", "BODY" },
	{ "F", "BLOCK" }, { "R", "PARRY" }, { "Q/E", "SLIP" }, { "C", "ROLL" }, { "Z/X", "PIVOT" }, { "G", "CLINCH" } }) do
	local f = UI.Frame(controls, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i })
	UI.List(f, 5, true)
	local cap = UI.Frame(f, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel2, BackgroundTransparency = 0, LayoutOrder = 1 })
	UI.Corner(cap, 4)
	UI.Stroke(cap, Color3.new(1, 1, 1), 1, 0.85)
	local t = UI.Text(cap, k[1], { Font = T.semi, TextSize = 10, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Pad(t, 0, 6)
	UI.Text(f, k[2], { Font = T.semi, TextSize = 10, TextColor3 = Color3.fromRGB(200, 205, 216), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
end

local function showBanner(text, color, dur)
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

local function showFlash(lbl, text, color, dur)
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

local function setTicker(text)
	tickerText.Text = text
	tickerText.TextTransparency = 1
	UI.Tween(tickerText, { TextTransparency = 0 }, 0.3)
end

-- floating hit markers at the target's position on screen
local markers = UI.Frame(hud, { Name = "Markers", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 15 })
local function hitMarker(model, text, color, big)
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
	local x, y = p.X / s, (p.Y - inset.Y) / s
	local m = UI.Text(markers, text, { Face = "display", TextSize = big and 34 or 24, TextColor3 = color, TextStrokeTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + math.random(-14, 14), y), Size = UDim2.fromOffset(240, 40), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 16 })
	local sc = UI.New("UIScale", { Scale = 0.6, Parent = m })
	UI.Tween(sc, { Scale = 1 }, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	UI.Tween(m, { Position = m.Position - UDim2.fromOffset(0, 46), TextTransparency = 1, TextStrokeTransparency = 1 }, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	task.delay(0.95, function()
		m:Destroy()
	end)
end

-- the hit zone flashes on a fighter's silhouette (head / left ribs / right ribs)
local function zoneFlash(panel, isBody, hand, sev)
	local z = panel.zones
	local target = z.head
	if isBody then
		-- the attacker's left hand lands on the target's right side
		target = hand == "L" and z.bodyR or z.bodyL
	end
	target.BackgroundColor3 = Color3.new(1, 1, 1)
	UI.Tween(target, { BackgroundColor3 = T.red:Lerp(T.panel2, math.clamp(1 - sev, 0, 0.6)) }, TweenInfo.new(0.12))
	task.delay(0.5, function()
		if target.Parent then
			UI.Tween(target, { BackgroundColor3 = T.panel2 }, TweenInfo.new(0.8))
		end
	end)
end

-- overlay panel used for the tale of the tape and the corner / scorecard between rounds.
-- Builders below add rows in order and return their height so the panel can be fitted (UIScale)
-- between the scoreboard / letterbox and the ticker on any screen.
local OVERLAY_W = 820
local overlay = UI.Frame(hud, { Name = "Overlay", Size = UDim2.new(1, -80, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromScale(0.5, 0.56), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 10 })
UI.Glass(overlay, { transparency = 0.06, radius = UI.R.xl })
UI.New("UISizeConstraint", { MaxSize = Vector2.new(OVERLAY_W, 2000), Parent = overlay })
UI.New("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 22), PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28), Parent = overlay })
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

local function overlayBegin()
	UI.Clear(overlay)
	OV.order, OV.h = 0, 42 - 6
end

-- scale the panel to the room between the scoreboard (or the letterbox) and the ticker
local function fitOverlay()
	local canvas = UI.CanvasSize(hud)
	local top = L.frame.Visible and (16 + 134 * boardScale.Scale) or math.floor(canvas.Y * 0.08) + 10
	local bottom = 66
	local avail = math.max(140, canvas.Y - top - bottom)
	overlayFit.Scale = math.clamp(avail / math.max(1, OV.h), 0.45, 1)
	overlay.Position = UDim2.new(0.5, 0, 0, math.floor(top + avail / 2))
end
local function overlayShow()
	fitOverlay()
	overlay.Visible = true
end

local function ovHead(kicker, title, color)
	local f = UI.Frame(overlay, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = ovAdd(62) })
	local k = UI.Frame(f, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 })
	UI.List(k, 8, true, Enum.HorizontalAlignment.Center)
	UI.Frame(k, { Size = UDim2.fromOffset(18, 2), BackgroundColor3 = color or T.gold, LayoutOrder = 1 })
	UI.Text(k, string.upper(kicker or ""), { Font = T.semi, TextSize = 12, TextColor3 = color or T.gold, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, LayoutOrder = 2 })
	UI.Frame(k, { Size = UDim2.fromOffset(18, 2), BackgroundColor3 = color or T.gold, LayoutOrder = 3 })
	UI.Text(f, string.upper(title or ""), { Face = "display", TextSize = 36, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 42), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	return f
end

-- red corner vs blue corner: flags, names, nicknames
local function ovVersus(you, opp)
	local f = UI.Frame(overlay, { Name = "Versus", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = ovAdd(62) })
	local fl = getFlags()
	for i, t in ipairs({ you, opp }) do
		local left = i == 1
		local accent = left and T.red or T.blue
		local side = UI.Frame(f, { Name = left and "Red" or "Blue", BackgroundColor3 = accent, BackgroundTransparency = 0.84, Size = UDim2.new(0.5, -44, 1, 0),
			Position = left and UDim2.fromScale(0, 0) or UDim2.new(0.5, 44, 0, 0) })
		UI.Corner(side, UI.R.md)
		UI.Gradient(side, Color3.new(1, 1, 1), left and 0 or 180, NumberSequence.new(0, 0.6))
		UI.Frame(side, { Size = UDim2.new(0, 4, 1, -14), Position = left and UDim2.fromOffset(0, 7) or UDim2.new(1, -4, 0, 7), BackgroundColor3 = accent })
		local flag = UI.Frame(side, { Name = "Flag", BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 22), Position = left and UDim2.fromOffset(16, 9) or UDim2.new(1, -50, 0, 9) })
		if fl and t.nat then
			pcall(fl.Draw, flag, t.nat, { Size = UDim2.fromOffset(34, 22) })
		end
		local x = left and 60 or 14
		UI.Text(side, string.upper(t.name or ""), { Face = "display", TextSize = 26, Position = UDim2.fromOffset(x, 4), Size = UDim2.new(1, -74, 0, 32), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local nick = (t.nick and t.nick ~= "") and ('"' .. string.upper(t.nick) .. '"') or string.upper(t.nat or "")
		UI.Text(side, nick, { Font = T.semi, TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(left and 16 or 14, 38), Size = UDim2.new(1, -30, 0, 16), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	UI.Text(f, "VS", { Face = "display", TextSize = 32, TextColor3 = T.gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(80, 40),
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
	UI.Text(f, string.upper(caption), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromScale(0.38, 0), Size = UDim2.new(0.24, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Text(f, tostring(b), { Face = face, TextSize = size, TextColor3 = emphasis and T.gold or T.text, Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, -14, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	return f, h
end

local function ovRow(a, caption, b, emphasis)
	local h = emphasis and 40 or 32
	local order = ovAdd(h)
	return tapeRow(overlay, a, caption, b, order, emphasis)
end

-- a wrapped line of copy (weigh-in, scouting, cutman); color tints a small tag in front
local function ovNote(tag, text, color)
	local w = overlayWidth()
	local chars = #tag + #text + 4
	local lines = math.max(1, math.ceil(chars * 7.4 / math.max(200, w - 16)))
	local h = lines * 18 + 10
	local f = UI.Frame(overlay, { Name = "Note", BackgroundColor3 = color or T.panel2, BackgroundTransparency = 0.86, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
	UI.Corner(f, 4)
	UI.Text(f, string.format('<font color="#%s"><b>%s</b></font>   %s', (color or T.gold):ToHex(), string.upper(tag), text), {
		RichText = true, Font = T.font, TextSize = 14, TextColor3 = T.text, Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 1, -10), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	return f
end

-- a quote with a coloured rule (corner advice, trash talk)
local function ovQuote(text, who, color)
	local w = overlayWidth()
	local body = '"' .. text .. '"' .. (who and ("   -  " .. who) or "")
	local lines = math.max(1, math.ceil(#body * 7.6 / math.max(200, w - 30)))
	local h = lines * 19 + 12
	local f = UI.Frame(overlay, { Name = "Quote", BackgroundColor3 = T.panel2, BackgroundTransparency = 0.6, Size = UDim2.new(1, 0, 0, h), LayoutOrder = ovAdd(h) })
	UI.Corner(f, 4)
	UI.Frame(f, { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = color or T.gold })
	UI.Text(f, body, { Font = T.font, TextSize = 15, TextColor3 = T.text, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -28, 1, -12), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	return f
end

-- the score: both corners' totals, big, with a caption between them
local function ovScore(a, b, caption, you, opp)
	local f = UI.Frame(overlay, { Name = "Score", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 72), LayoutOrder = ovAdd(72) })
	for i, v in ipairs({ a, b }) do
		local left = i == 1
		local accent = left and T.red or T.blue
		local lead = (left and a > b) or (not left and b > a)
		local side = UI.Frame(f, { BackgroundColor3 = accent, BackgroundTransparency = 0.84, Size = UDim2.new(0.5, -64, 1, 0), Position = left and UDim2.fromScale(0, 0) or UDim2.new(0.5, 64, 0, 0) })
		UI.Corner(side, UI.R.md)
		UI.Frame(side, { Size = UDim2.new(0, 4, 1, -16), Position = left and UDim2.fromOffset(0, 8) or UDim2.new(1, -4, 0, 8), BackgroundColor3 = accent })
		UI.Text(side, string.upper(left and you or opp), { Face = "displayMed", TextSize = 18, Position = UDim2.fromOffset(left and 16 or 90, 0), Size = UDim2.new(1, -106, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.Text(side, tostring(v), { Face = "number", TextSize = 54, TextColor3 = lead and T.gold or T.text, AnchorPoint = Vector2.new(left and 1 or 0, 0.5),
			Position = left and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(78, 64), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = left and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, TextWrapped = false })
	end
	UI.Text(f, caption, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(116, 40),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	return f
end

-- round-by-round strip: R1 10-9 ... (red / blue underline for who took the round)
local function ovRounds(cards, rounds, current)
	local n = math.max(1, rounds or 1)
	local f = UI.Frame(overlay, { Name = "Rounds", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = ovAdd(46) })
	UI.List(f, 4, true, Enum.HorizontalAlignment.Center)
	local w = overlayWidth()
	local cellW = math.clamp(math.floor((w - (n - 1) * 4) / n), 36, 72)
	for i = 1, n do
		local c = cards[i]
		local cell = UI.Frame(f, { Size = UDim2.fromOffset(cellW, 46), BackgroundColor3 = i == current and T.panel2:Lerp(T.gold, 0.12) or T.panel2, BackgroundTransparency = c and 0.15 or 0.7, LayoutOrder = i })
		UI.Corner(cell, 4)
		UI.Text(cell, "R" .. i, { Font = T.semi, TextSize = 10, TextColor3 = i == current and T.gold or T.sub, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 2),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		UI.Text(cell, c and string.format("%d-%d", c[1], c[2]) or "-", { Face = "number", TextSize = 17, TextColor3 = c and T.text or T.dim, Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		if c then
			local col = c[1] > c[2] and T.red or (c[2] > c[1] and T.blue or T.sub)
			UI.Frame(cell, { Position = UDim2.new(0, 4, 1, -4), Size = UDim2.new(1, -8, 0, 3), BackgroundColor3 = col })
		end
	end
	return f
end

-- the player's condition between rounds: head and body with their permanent caps
local function ovCondition(c)
	local f = UI.Frame(overlay, { Name = "Condition", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = ovAdd(36) })
	for i, spec in ipairs({ { "HEAD", c.head, c.cap, T.green }, { "BODY", c.body, c.bodyCap, T.orange } }) do
		local v, cap = tonumber(spec[2]) or 0, tonumber(spec[3]) or 100
		local cell = UI.Frame(f, { BackgroundTransparency = 1, Position = UDim2.new((i - 1) * 0.5, i == 2 and 8 or 0, 0, 0), Size = UDim2.new(0.5, -8, 1, 0) })
		UI.Text(cell, spec[1], { Font = T.semi, TextSize = 10, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 12), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		UI.Text(cell, cap < 100 and string.format("MAX %d", cap) or "", { Font = T.semi, TextSize = 10, TextColor3 = T.red, Size = UDim2.new(1, 0, 0, 12), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		local color = v < 30 and T.red or spec[4]
		local bar = hudBar(cell, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 16) }, color, "L", nil, true)
		setBar(bar, v / 100, cap / 100, color)
	end
	return f
end

-- the knockdown count: a band with the referee's count, big
local countBox = UI.Frame(hud, { Name = "Count", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(520, 230), BackgroundTransparency = 1, Visible = false, ZIndex = 22 })
local countKicker, countKickerText = UI.Chip(countBox, "KNOCKDOWN", T.red, { solid = true, textColor = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), h = 28, TextSize = 14 })
countKicker.ZIndex = 23
local countFit = UI.New("UIScale", { Name = "Fit", Parent = countBox })
local countNum = UI.Text(countBox, "", { Face = "display", TextSize = 150, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 160),
	AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 23 })
local countScale = UI.New("UIScale", { Parent = countNum })
local countWho = UI.Text(countBox, "", { Face = "displayMed", TextSize = 22, TextColor3 = T.text, TextStrokeTransparency = 0.5, Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 30),
	AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 23 })
-- kicker: "KNOCKDOWN" / "EIGHT COUNT" ...; who: the line under the number
local function openCount(kicker, color, who)
	countKickerText.Text = string.upper(kicker)
	countKicker.BackgroundColor3 = color or T.red
	countWho.Text = who or ""
	countNum.Text = ""
	countBox.Visible = true
end
local function showCount(n, standing)
	countBox.Visible = true
	countNum.Text = tostring(n)
	countNum.TextColor3 = standing and Color3.fromRGB(230, 230, 230) or (n >= 8 and T.red or Color3.new(1, 1, 1))
	countScale.Scale = 1.35
	UI.Tween(countScale, { Scale = 1 }, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end
local function hideCount()
	countBox.Visible = false
end

------------------------------------------------------------------------
-- Get-up: mash SPACE / tap, and time presses on the sweeping marker (green zone = worth 3)
------------------------------------------------------------------------
local getup = UI.Frame(hud, { Name = "GetUp", Size = UDim2.fromOffset(540, 156), Position = UDim2.new(0.5, 0, 0.64, 0), AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 24 })
UI.Glass(getup, { transparency = 0.05, radius = UI.R.xl, stroke = T.red, strokeT = 0.3 })
local getupFit = UI.New("UIScale", { Name = "Fit", Parent = getup })
local getupTitle = UI.Text(getup, "YOU'RE DOWN!  MASH SPACE / TAP - HIT THE GREEN ZONE", { Face = "displayMed", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 26), TextColor3 = T.red, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 25 })
local _, setGetup = UI.Bar(getup, { Position = UDim2.fromOffset(24, 48), Size = UDim2.new(1, -48, 0, 20), ZIndex = 25 }, T.gold)
local timing = UI.Frame(getup, { Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 26), BackgroundColor3 = T.ink, ZIndex = 25 })
UI.Corner(timing, 6)
local zone = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.2, ZIndex = 26 })
UI.Corner(zone, 6)
local marker = UI.Frame(timing, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.2), Size = UDim2.new(0, 5, 1.4, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 27 })
UI.Corner(marker, 2)
local getupHint = UI.Text(getup, "", { Font = T.semi, TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 18),
	AutomaticSize = Enum.AutomaticSize.None, ZIndex = 25 })

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

local getupBtn = UI.Button(getup, "", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 28 }, getupPress)
getupBtn.Text = ""

-- responsive layout: short (phone) canvases get a smaller scoreboard, count and get-up panel; the
-- network bug sits under the clock in rounds and in the corner during walkouts / the tape
local function layoutHud()
	local canvas = UI.CanvasSize(hud)
	local compact = canvas.Y < 640
	local k = compact and 0.8 or 1
	if F.resting and overlay.Visible then
		-- between rounds on a phone the scorecard needs the room; the scoreboard returns with the bell
		L.frame.Visible, R.frame.Visible, clock.Visible = not compact, not compact, not compact
	end
	boardScale.Scale = k
	board.Size = UDim2.new(1 / k, -40 / k, 0, 134)
	local below = 10 + 134 * k
	if clock.Visible then
		bug.AnchorPoint = Vector2.new(0.5, 0)
		bug.Position = UDim2.new(0.5, 0, 0, below + 8)
	else
		bug.AnchorPoint = Vector2.new(0, 0)
		bug.Position = UDim2.fromOffset(20, 10)
	end
	angleTag.Position = UDim2.new(0.5, 0, 0, below + 40)
	countFit.Scale = compact and 0.62 or 1
	countBox.Position = UDim2.fromScale(0.5, compact and 0.56 or 0.42)
	getupFit.Scale = compact and 0.72 or 1
	getup.Position = UDim2.new(0.5, 0, compact and 0.6 or 0.64, 0)
	banner.TextSize = compact and 68 or 96
	bannerBand.Size = UDim2.new(1, 0, 0, compact and 90 or 120)
	if overlay.Visible then
		fitOverlay()
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
hud:GetAttributeChangedSignal("UIScale"):Connect(layoutHud)
layoutHud()

-- punches go through throwPunch (defined with the input code) so taps are predicted like keys
local throwPunch

-- touch controls: round pads (red punches, blue defence, green movement)
local touchPad
local function buildTouch()
	if touchPad or not UserInputService.TouchEnabled then
		return
	end
	touchPad = UI.Frame(hud, { Name = "TouchPad", BackgroundTransparency = 1, Size = UDim2.fromOffset(400, 220), Position = UDim2.new(1, -16, 1, -64), AnchorPoint = Vector2.new(1, 1) })
	UI.Grid(touchPad, 72, 64, 8)
	local function tb(label, color, down, up)
		local b = UI.Button(touchPad, label, { BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, TextSize = 13 })
		b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 32)
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color, st.Transparency, st.Thickness = color or T.line, 0.15, 2
		end
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
		bodyBtn.BackgroundColor3 = F.bodyMod and T.orange or T.bg
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
	controls.Visible = false
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
	-- the HUD's crowd meter follows every cheer (VenueFX or the built-in crowd does the sound / bob)
	crowdMeter.level = math.clamp(crowdMeter.level + (amount or 0) * 0.3, 0, 1)
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
	-- the HUD head and health bars pulse at danger
	if tier >= 2 then
		local p = math.sin(now * (tier >= 3 and 9 or 5)) * 0.5 + 0.5
		L.head.fill.BackgroundColor3 = tierColor(tier):Lerp(Color3.new(1, 1, 1), p * 0.35)
		L.health.fill.BackgroundColor3 = tierColor(tier):Lerp(Color3.new(1, 1, 1), p * 0.25)
	end
	local ot = F.opp and F.oppState and F.oppState.tier or 0
	if ot >= 2 then
		local p = math.sin(now * (ot >= 3 and 9 or 5)) * 0.5 + 0.5
		R.head.fill.BackgroundColor3 = tierColor(ot):Lerp(Color3.new(1, 1, 1), p * 0.35)
		R.health.fill.BackgroundColor3 = tierColor(ot):Lerp(Color3.new(1, 1, 1), p * 0.25)
	end
	crowdMeter.level = math.max(0.12, crowdMeter.level - dt * 0.06)
	updateCrowd(dt)
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
		local kick = shakeScale()
		local sh = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * FX.shake * fx * kick
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
				goal *= CFrame.Angles(0, 0, FX.roll * fx * kick)
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
	if not P or not char or not F.active or F.down or F.paused or now < (F.stumbleUntil or 0) or now < pred.busyUntil then
		return
	end
	-- the server's CanAct also refuses in a clinch, while down, in the corner or on the ring walk, and nobody
	-- may punch a man on the canvas: the Guard attributes it replicates already say so
	local g = char:GetAttribute("Guard")
	if g == "clinch" or g == "down" or g == "rest" or g == "walkout" or (F.opp and F.opp:GetAttribute("Guard") == "down") then
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
		panel.chip.Size = UDim2.fromOffset(0, 26)
		TweenService:Create(panel.chip, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(0, 20) }):Play()
	end
end

local function finish()
	F.active = false
	F.down = false
	gui.Enabled = false
	fxGui.Enabled = false
	overlay.Visible = false
	getup.Visible = false
	hideCount()
	bannerBand.Visible = false
	angleTag.Visible = false
	bug.Visible = false
	UI.Clear(markers)
	setRagdoll(false)
	F.stumbleUntil = 0
	pcall(RunService.UnbindFromRenderStep, RunService, STUMBLE_STEP)
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
	L.name.Text = string.upper(msg.tape.you.name)
	R.name.Text = string.upper(msg.tape.opp.name)
	for _, pair in ipairs({ { L, msg.tape.you }, { R, msg.tape.opp } }) do
		local panel, t = pair[1], pair[2]
		local r = t.record or {}
		panel.sub.Text = string.format("%d-%d-%d  ·  %d KO%s", r.w or 0, r.l or 0, r.d or 0, r.ko or 0, (t.nick and t.nick ~= "") and ('  ·  "' .. string.upper(t.nick) .. '"') or "")
		UI.Clear(panel.flag)
		local fl = getFlags()
		if fl and t.nat then
			pcall(fl.Draw, panel.flag, t.nat, { Size = UDim2.fromOffset(30, 20) })
		end
		UI.Clear(panel.kd)
		panel.kdCount = 0
		panel.cut.Visible, panel.swell.Visible, panel.ribs.Visible = false, false, false
		for _, z in ipairs({ panel.zones.head, panel.zones.bodyL, panel.zones.bodyR }) do
			z.BackgroundColor3 = T.panel2
		end
	end
	crowdMeter.level, crowdMeter.lean = 0.2, 0
	hideCount()
	bug.Visible = true
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
	if F.spar then
		bugText.Text = "SPARRING  ·  " .. string.upper(F.spar)
		bug.BackgroundColor3 = T.blue
		F.stakesText = string.format("SPARRING (%s) vs %s", string.upper(F.spar), msg.tape.opp.name)
	else
		bugText.Text = "LIVE  ·  WCB SPORTS"
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
			music.Name = "WalkoutMusic" -- Settings scales sounds named *Music* by the music volume
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
	local canvas = UI.CanvasSize(hud)
	local compact = canvas.Y < 640
	local function rec(x)
		local r = x.record or {}
		return string.format("%d-%d-%d", r.w or 0, r.l or 0, r.d or 0)
	end
	overlayBegin()
	ovHead(F.stakesText or "", "TALE OF THE TAPE", F.spar and T.blue or T.red)
	ovVersus(y, o)
	ovRow(rec(y), "Record", rec(o))
	ovRow((y.record or {}).ko or 0, "Knockouts", (o.record or {}).ko or 0)
	ovRow(Config.HeightText(y.height), "Height", Config.HeightText(o.height))
	ovRow(string.format("%d in", y.reach or 0), "Reach", string.format("%d in", o.reach or 0))
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
		else
			ovNote("Weigh-in", string.format("%.1f lbs (limit %d) - made weight", wi.weight, wi.limit), T.green)
		end
	end
	if F.notes and #F.notes > 0 then
		ovNote("Condition", table.concat(F.notes, ", "), T.orange)
	end
	if F.talk and F.talk ~= "" then
		ovQuote(F.talk, o.name, T.blue)
	end
	if F.myLine and F.myLine ~= "" and not compact then
		ovQuote(F.myLine, y.name, T.red)
	end
	overlayShow()
	stopMusic()
end

function handlers.round(msg)
	overlay.Visible = false
	F.resting = false
	setAnimate(false)
	F.active = true
	F.paused = false
	camMode = "fight"
	F.broadcastUntil = nil
	letterbox(false)
	L.frame.Visible, R.frame.Visible, clock.Visible, controls.Visible = true, true, true, touchPad == nil
	hideCount()
	layoutHud()
	roundText.Text = string.format("ROUND %d / %d", msg.n, msg.total)
	timeText.Text = fmtTime(F.spar and Config.SparRoundSeconds or Config.RoundSeconds)
	timeText.TextColor3 = T.text
	showBanner("ROUND " .. msg.n, T.gold, 1.8)
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

local function healthColor(v, tier)
	if (tier or 0) >= 1 then
		return tierColor(tier)
	end
	return v > 0.6 and T.green or (v > 0.35 and T.gold or (v > 0.18 and T.orange or T.red))
end

function handlers.state(msg)
	timeText.Text = fmtTime(msg.time)
	timeText.TextColor3 = (msg.time or 99) <= 10 and T.red or T.text
	F.me, F.oppState = msg.me, msg.opp
	local function apply(panel, s, female, model)
		local tier = s.tier or 0
		local headColor = tier >= 1 and tierColor(tier) or (s.hurt and T.gold or T.green)
		local overall, overallCap = overallOf(s)
		if tier < 2 then
			setBar(panel.head, s.hp / 100, (s.cap or 100) / 100, headColor)
			setBar(panel.health, overall, overallCap, healthColor(overall, tier))
		else
			-- colours pulse in updateFX
			setBar(panel.head, s.hp / 100, (s.cap or 100) / 100)
			setBar(panel.health, overall, overallCap)
		end
		setBar(panel.body, s.body / 100, (s.bodyCap or 100) / 100, s.body < 30 and T.red or T.orange)
		local max = math.max(1, s.max or 100)
		setBar(panel.stam, s.stam / max, (s.stamCap or max) / max, s.stam < max * 0.25 and Color3.fromRGB(120, 125, 140) or T.blue)
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
	-- the HUD: zone flash on the target's silhouette, the crowd leans, cuts show up
	local panel = mine and R or L
	zoneFlash(panel, msg.body == true, msg.hand, sev)
	if msg.bleed and not msg.body then
		panel.cut.Visible = true
	end
	crowdMeter.lean = math.clamp(crowdMeter.lean + (mine and 1 or -1) * (0.03 + sev * 0.07), -1, 1)
	local text = (msg.counter and "COUNTER " or "") .. (PUNCH_NAME[msg.punch] or tostring(msg.punch):upper()) .. (msg.body and " TO THE BODY" or "")
	if mine then
		-- hit markers over the opponent for every punch you land
		hitMarker(target, msg.counter and "COUNTER!" or (msg.heavy and "BIG SHOT!" or (PUNCH_NAME[msg.punch] or "HIT")), (msg.heavy or msg.counter) and T.gold or Color3.new(1, 1, 1),
			msg.heavy == true or msg.counter == true)
	end
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
	sfx(BUILTIN.Falling or "rbxasset://sounds/action_falling.ogg", 0.7, 1)
	sfx(BUILTIN.Thud or "rbxasset://sounds/action_jump_land.mp3", 0.5, 0.9)
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
	if msg.severity == "out" then
		countNum.Text = "KO"
		countNum.TextColor3 = mine and T.red or T.gold
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
	F.cards = F.cards or {}
	if type(msg.card) == "table" then
		F.cards[msg.n] = { tonumber(msg.card[1]) or 0, tonumber(msg.card[2]) or 0 }
	end
	local canvas = UI.CanvasSize(hud)
	local compact = canvas.Y < 640
	F.resting = true
	controls.Visible = false
	bannerBand.Visible = false -- the bell's banner would sit on the scorecard
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
		if c.notes and #c.notes > 0 then
			ovNote("Cutman", table.concat(c.notes, "  |  "), T.orange)
		end
	end
	for i, line in ipairs(msg.advice or {}) do
		if not compact or i == 1 then
			ovQuote(line, "your corner", T.gold)
		end
	end
	overlayShow()
	layoutHud()
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
	controls.Visible = false
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
