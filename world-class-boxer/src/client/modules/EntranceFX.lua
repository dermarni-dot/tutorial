-- EntranceFX: the ring-walk cinematic on the client. The server (RingWalk) sends one "entrance" message per walk with
-- its plan (Shared.Entrance); from it this module, on every client (PvP: both see both walks):
--   * cuts the camera between the tunnel, tracking, crowd, steps, corner and robe shots on the plan's beats
--     (EntranceFX.Camera: FightClient's camera takes it as the on-air shot while camMode is "entrance")
--   * starts the body language (BoxerClient.AnimEntrance: the celebrations, the climb, the duck, the turnbuckle)
--   * draws the crowd that carries a popular boxer in on its shoulders (2-4 cheap local figures by Graphics level,
--     in his corner's colour, walking in formation under him) and the belt he lifts
--   * shows the name / nickname reveal and a SKIP button (Space / Enter / pad A, or tap): a skip asks the server to
--     end the entrance (vs the AI at once, in PvP when both asked) and cuts this client to the ring at once
--   * walks the player's own character on the beats (his client owns its physics: the same points the server places
--     him on, so nothing ever pulls him back)
--   * after a big non-title win, lifts the winner for a parade round the ring (Entrance.CarryAfterWin; a title win
--     is the victory ceremony's, not this)
-- Everything here is client-local: the figures, the belt, the offsets; the server's fighters never move for it.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Entrance = require(Shared:WaitForChild("Entrance"))
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme
local AE = require(script.Parent:WaitForChild("AnimEntrance"))

local EntranceFX = {}

local player = Players.LocalPlayer
local V3 = Vector3.new
local CF = CFrame.new
local A = CFrame.Angles
local sin, abs, max, min, PI = math.sin, math.abs, math.max, math.min, math.pi
local clamp = math.clamp
local smooth = AE.smooth

local function optional(name)
	local ok, mod = pcall(function()
		local m = script.Parent:FindFirstChild(name)
		return m and require(m)
	end)
	return ok and type(mod) == "table" and mod or nil
end

local function level()
	local Perf = optional("Perf")
	local ok, l = pcall(function()
		return Perf and Perf.Level() or 3
	end)
	return ok and clamp(tonumber(l) or 3, 1, 3) or 3
end
EntranceFX.Level = level

local function venueFX(name, ...)
	local VF = optional("VenueFX")
	local fn = VF and VF[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

-- (an Instance in the game; the offline tools' stand-ins are tables)
local function isInst(v)
	return v ~= nil and (typeof(v) == "Instance" or type(v) == "table")
end

local function flat(v)
	return V3(v.X, 0, v.Z)
end
local function unitOr(v, d)
	return v.Magnitude > 1e-3 and v.Unit or d
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
-- S.walk = the walk on now: { plan, st (AnimEntrance), model, you, t0, beats, total, carriers, lastBeat, ... }
local S = { walk = nil, skipped = false, plans = {}, cam = nil, camKey = nil, ui = nil, parade = nil }
EntranceFX.S = S

------------------------------------------------------------------------
-- The carriers: cheap local figures (legs, torso, head, arms), in the walker's corner colour
------------------------------------------------------------------------
local SHIRTS = {
	Red = { Color3.fromRGB(196, 32, 36), Color3.fromRGB(150, 22, 28), Color3.fromRGB(235, 235, 238), Color3.fromRGB(210, 60, 50) },
	Blue = { Color3.fromRGB(34, 64, 196), Color3.fromRGB(24, 44, 140), Color3.fromRGB(235, 235, 238), Color3.fromRGB(60, 96, 210) },
}
local SKINS = { Color3.fromRGB(234, 192, 160), Color3.fromRGB(198, 140, 100), Color3.fromRGB(142, 92, 62), Color3.fromRGB(96, 62, 42), Color3.fromRGB(222, 170, 130) }
local PANTS = { Color3.fromRGB(32, 34, 42), Color3.fromRGB(52, 58, 74), Color3.fromRGB(26, 26, 30) }

local function part(parent, name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function buildCarrier(folder, i, k, corner, seed)
	local shirts = SHIRTS[corner] or SHIRTS.Red
	local m = Instance.new("Model")
	m.Name = "Carrier" .. i
	local shirt = shirts[(seed + i) % #shirts + 1]
	local skin = SKINS[(seed * 3 + i * 7) % #SKINS + 1]
	local pants = PANTS[(i + seed) % #PANTS + 1]
	local c = {
		model = m, k = k,
		legL = part(m, "LegL", V3(0.62, 2.6, 0.66) * k, pants, Enum.Material.Fabric),
		legR = part(m, "LegR", V3(0.62, 2.6, 0.66) * k, pants, Enum.Material.Fabric),
		torso = part(m, "Torso", V3(1.6, 1.9, 0.85) * k, shirt, Enum.Material.Fabric),
		head = part(m, "Head", V3(1.0, 1.12, 1.04) * k, skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball),
		armL = part(m, "ArmL", V3(0.46, 1.8, 0.5) * k, shirt, Enum.Material.Fabric),
		armR = part(m, "ArmR", V3(0.46, 1.8, 0.5) * k, shirt, Enum.Material.Fabric),
	}
	if (seed + i) % 3 ~= 0 then
		c.hair = part(m, "Hair", V3(1.06, 0.55, 1.1) * k, Color3.fromRGB(30 + (i * 23) % 40, 22, 18), Enum.Material.Fabric, Enum.PartType.Ball)
	end
	-- the main carrier's shadow grounds the group (the rest stay cheap)
	c.torso.CastShadow = i == 1
	c.list = { c.legL, c.legR, c.torso, c.head, c.armL, c.armR, c.hair }
	m.Parent = folder
	return c
end

local function poseCarrier(c, pose, out, cfs)
	local k = c.k
	local feet = pose.cf
	local bob = pose.bob * k - pose.crouch * k
	local hipY = 2.6 * k + bob
	local sw = pose.swing
	table.insert(out, c.legL)
	table.insert(cfs, feet * CF(-0.33 * k, hipY, 0) * A(sw, 0, 0) * CF(0, -1.3 * k, 0))
	table.insert(out, c.legR)
	table.insert(cfs, feet * CF(0.33 * k, hipY, 0) * A(-sw, 0, 0) * CF(0, -1.3 * k, 0))
	local lean = pose.role == "base" and -0.08 or (pose.role == "back" and -0.18 or -0.05)
	local torso = feet * CF(0, hipY + 0.95 * k, 0) * A(lean, 0, 0)
	table.insert(out, c.torso)
	table.insert(cfs, torso)
	local headCF = torso * CF(0, 1.5 * k, pose.role == "base" and -0.12 * k or 0) * A(pose.role == "base" and -0.35 or 0.25, 0, 0)
	table.insert(out, c.head)
	table.insert(cfs, headCF)
	if c.hair then
		table.insert(out, c.hair)
		table.insert(cfs, headCF * CF(0, 0.3 * k, 0.05 * k))
	end
	for _, side in ipairs({ -1, 1 }) do
		local pitch = side < 0 and pose.armL or pose.armR
		local swing = pose.role == "base" and 0 or 0.08 * sin(pose.swing * 3 + side)
		table.insert(out, side < 0 and c.armL or c.armR)
		table.insert(cfs, torso * CF(side * 1.03 * k, 0.75 * k, 0) * A(pitch + swing, 0, -0.1 * side) * CF(0, -0.9 * k, 0))
	end
end

local function moveParts(parts, cfs)
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

local function dropCarriers(w)
	if w and w.carryFolder then
		w.carryFolder:Destroy()
		w.carryFolder = nil
		w.carriers = nil
	end
end

local function ensureCarriers(w, geo, count)
	if w.carriers then
		return w.carriers
	end
	local folder = Instance.new("Folder")
	folder.Name = "EntranceCarriers"
	folder.Parent = workspace
	w.carryFolder = folder
	w.carriers = {}
	for i = 1, count do
		table.insert(w.carriers, buildCarrier(folder, i, geo.k, w.plan.corner, w.plan.seed or 0))
	end
	return w.carriers
end

-- the carriers under (or around) the walker this frame: lift 0..1 (1 = on the shoulders), crouch for the set-down
local partsBuf, cfBuf = {}, {}
local function updateCarriers(w, rootCF, geo, dt, lift, crouch, spread, yawSpin)
	local carriers = w.carriers
	if not carriers then
		return
	end
	local floorY = rootCF.Position.Y - geo.stand
	local pos = rootCF.Position
	local last = w.lastRootPos or pos
	local v = flat(pos - last).Magnitude / max(dt, 1 / 240)
	w.lastRootPos = pos
	w.carryPhase = (w.carryPhase or 0) + dt * clamp(v, 0, 12) / (1.35 * geo.k) * PI
	table.clear(partsBuf)
	table.clear(cfBuf)
	local base = rootCF
	if yawSpin and yawSpin ~= 0 then
		base = CFrame.new(rootCF.Position) * A(0, yawSpin, 0) * (rootCF - rootCF.Position)
	end
	for i, c in ipairs(carriers) do
		local pose = AE.CarrierPose(i, base, geo, floorY, w.carryPhase, lift, crouch * (i == 1 and 1 or 0.4))
		if spread > 0 and i > 1 then
			-- the helpers step away from him once he is down
			local s = AE.CARRY_SLOTS[i]
			pose.cf = pose.cf * CF(s.x * spread * 0.9, 0, s.z * spread * 0.6)
			pose.armL, pose.armR = pose.armL * (1 - spread) + 0.2 * spread, pose.armR * (1 - spread) + 0.2 * spread
		end
		if spread > 0 and i == 1 then
			pose.cf = pose.cf * CF(0, 0, -1.2 * spread)
			pose.armL, pose.armR = 1.25 * (1 - spread), 1.25 * (1 - spread)
		end
		poseCarrier(c, pose, partsBuf, cfBuf)
	end
	moveParts(partsBuf, cfBuf)
end

------------------------------------------------------------------------
-- The belt he lifts (a local prop between his gloves while a belt lift plays)
------------------------------------------------------------------------
local BELT_GOLD = Color3.fromRGB(222, 178, 60)
local function ensureBelt(w)
	if w.belt then
		return w.belt
	end
	local m = Instance.new("Model")
	m.Name = "EntranceBelt"
	local b = {
		model = m,
		strap = part(m, "Strap", V3(2, 0.42, 0.08), Color3.fromRGB(24, 24, 26), Enum.Material.Leather),
		plate = part(m, "Plate", V3(0.9, 0.74, 0.14), BELT_GOLD, Enum.Material.Metal),
		gem = part(m, "Gem", V3(0.34, 0.34, 0.06), w.plan.corner == "Blue" and Color3.fromRGB(60, 110, 255) or Color3.fromRGB(230, 40, 40), Enum.Material.Neon),
		sideL = part(m, "SideL", V3(0.36, 0.5, 0.12), BELT_GOLD, Enum.Material.Metal),
		sideR = part(m, "SideR", V3(0.36, 0.5, 0.12), BELT_GOLD, Enum.Material.Metal),
	}
	b.plate.Reflectance, b.sideL.Reflectance, b.sideR.Reflectance = 0.25, 0.25, 0.25
	w.belt = b
	return b
end

local function hand(model, side)
	return model:FindFirstChild(side .. "Hand") or model:FindFirstChild(side .. "LowerArm")
end

local function updateBelt(w, on)
	local model = w.model
	if not on then
		if w.belt and w.belt.model.Parent then
			w.belt.model.Parent = nil
		end
		return
	end
	local l, r = hand(model, "Left"), hand(model, "Right")
	if not (l and r) then
		return
	end
	local b = ensureBelt(w)
	if not b.model.Parent then
		b.model.Parent = workspace
	end
	local pl, pr = l.Position, r.Position
	local x = unitOr(pr - pl, V3(1, 0, 0))
	local up = unitOr(V3(0, 1, 0) - x * x.Y, V3(0, 1, 0))
	local mid = (pl + pr) / 2 + up * 0.25
	local frame = CFrame.fromMatrix(mid, x, up)
	local len = (pr - pl).Magnitude + 0.3
	b.strap.Size = V3(max(1, len), 0.42, 0.08)
	moveParts({ b.strap, b.plate, b.gem, b.sideL, b.sideR }, {
		frame, frame * CF(0, 0.02, -0.06), frame * CF(0, 0.05, -0.14), frame * CF(-0.62, 0, -0.05), frame * CF(0.62, 0, -0.05),
	})
end

------------------------------------------------------------------------
-- Tunnel smoke (High detail: a burst at the tunnel mouth over VenueFX's own jets)
------------------------------------------------------------------------
local function tunnelSmoke(w)
	if level() < 3 or not w.plan.pts then
		return
	end
	local p = part(workspace, "EntranceSmoke", V3(4, 0.2, 2), Color3.new(), nil)
	p.Transparency = 1
	p.CFrame = CF(w.plan.pts.entrance + V3(0, 0.3, 0))
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(205, 205, 215))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(2.5, 4)
	pe.Speed = NumberRange.new(2, 5)
	pe.SpreadAngle = Vector2.new(60, 20)
	pe.Rate = 0
	pe.LightEmission = 0.15
	pe.Parent = p
	pcall(function()
		pe:Emit(26)
	end)
	task.delay(5, function()
		p:Destroy()
	end)
end

------------------------------------------------------------------------
-- The overlay: the name reveal and SKIP
------------------------------------------------------------------------
local function ensureUI()
	if S.ui and S.ui.gui.Parent then
		return S.ui
	end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	local gui = UI.New("ScreenGui", { Name = "EntranceUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false, Parent = pg })
	local root = UI.MountRoot(gui, "Root")
	-- the reveal: lower left, above the commentary ticker
	local card = UI.Frame(root, { Name = "Reveal", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -70), Size = UDim2.fromOffset(440, 104),
		BackgroundColor3 = T.bg, Visible = false })
	UI.Glass(card, { transparency = 0.1, radius = UI.R.md })
	local stripe = UI.Frame(card, { Name = "Stripe", Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = T.red })
	UI.Corner(stripe, UI.R.md)
	local kicker = UI.Text(card, "", { Name = "Kicker", Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(22, 8), Size = UDim2.new(1, -34, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local nick = UI.Text(card, "", { Name = "Nick", Face = "displayMed", TextSize = 18, TextColor3 = T.gold, Position = UDim2.fromOffset(22, 26), Size = UDim2.new(1, -34, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local name = UI.Text(card, "", { Name = "Name", Face = "display", TextSize = 34, TextColor3 = T.text, Position = UDim2.fromOffset(22, 50), Size = UDim2.new(1, -34, 0, 44),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
	UI.New("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 14, Parent = name })
	-- SKIP: lower right, above the ticker; finger-sized on touch
	local h = max(40, UI.MinHit(root))
	local skip = UI.Button(root, "SKIP  >>", { Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -70), Size = UDim2.fromOffset(max(150, h * 2.6), h),
		BackgroundColor3 = T.panel2, BackgroundTransparency = 0.15, TextSize = 16, Visible = false }, function()
		EntranceFX.Skip()
	end)
	local hint = UI.Text(skip, "", { Name = "Hint", Font = T.semi, TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	S.ui = { gui = gui, root = root, card = card, stripe = stripe, kicker = kicker, nick = nick, name = name, skip = skip, hint = hint }
	return S.ui
end

local function recordText(r)
	r = type(r) == "table" and r or {}
	return string.format("%d-%d-%d  ·  %d KO", tonumber(r.w) or 0, tonumber(r.l) or 0, tonumber(r.d) or 0, tonumber(r.ko) or 0)
end

local function showReveal(plan)
	local ui = ensureUI()
	ui.gui.Enabled = true
	ui.stripe.BackgroundColor3 = plan.corner == "Blue" and T.blue or T.red
	ui.kicker.Text = string.upper((plan.corner or "Red") .. " CORNER") .. "   ·   " .. recordText(plan.record) .. ((plan.nat and plan.nat ~= "") and ("   ·   " .. string.upper(plan.nat)) or "")
	ui.nick.Text = (plan.nick and plan.nick ~= "") and ('"' .. string.upper(plan.nick) .. '"') or ""
	ui.name.Text = string.upper(tostring(plan.name or ""))
	ui.card.Visible = true
	ui.card.Position = UDim2.new(0, -460, 1, -70)
	TweenService:Create(ui.card, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(0, 24, 1, -70) }):Play()
	local mode = UI.InputMode and UI.InputMode() or "keyboard"
	ui.hint.Text = mode == "gamepad" and "A" or (mode == "touch" and "" or "SPACE")
	ui.skip.Text = "SKIP  >>"
	ui.skip.Visible = true
end

local function hideReveal()
	local ui = S.ui
	if ui and ui.card.Visible then
		TweenService:Create(ui.card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -460, 1, -70) }):Play()
		local c = ui.card
		task.delay(0.36, function()
			if c.Parent and not (S.walk and S.walk.revealOn) then
				c.Visible = false
			end
		end)
	end
end

local function hideUI()
	local ui = S.ui
	if ui then
		ui.card.Visible = false
		ui.skip.Visible = false
		ui.gui.Enabled = false
	end
end

------------------------------------------------------------------------
-- The walker's own client walks him (the same points the server places him on)
------------------------------------------------------------------------
local function drive(w, beatId)
	if not w.you then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local pts = w.plan.pts
	if not (hum and pts) then
		return
	end
	local target, speed
	if beatId == "aisle" or beatId == "setdown" then
		target, speed = pts.steps, w.plan.speed
	elseif beatId == "steps" then
		target, speed = pts.apron, w.plan.speed
	elseif beatId == "ropes" then
		target, speed = pts.inside, w.plan.speed
	elseif beatId == "ring" then
		target, speed = pts.corner, Entrance.SPEED.ring
	end
	if target then
		hum.WalkSpeed = speed or 9
		hum:MoveTo(target)
	end
end

------------------------------------------------------------------------
-- Camera shots
------------------------------------------------------------------------
local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

-- the shot for this frame: CFrame and a key (a new key = a hard cut)
local function shot(w, now)
	local plan, pts = w.plan, w.plan.pts
	if not pts then
		return nil
	end
	local el = now - w.t0
	local beat, _, bt = Entrance.BeatAt(w.beats, el)
	if not beat then
		beat, bt = w.beats[#w.beats], el - w.beats[#w.beats].t0
	end
	local r = rootOf(w.model)
	local rp = r and r.Position or pts.steps
	local floorY, canvasY = pts.steps.Y, pts.centre.Y
	local out = unitOr(flat(pts.steps - pts.centre), V3(0, 0, -1)) -- ring -> this corner's tunnel
	local side = out:Cross(V3(0, 1, 0))
	local geo = w.geo or AE.Geom(w.model)
	w.geo = geo
	local lift = plan.carry and geo.lift or 0
	local id = beat.id
	local d = beat.t1 - beat.t0
	local e = clamp(bt / d, 0, 1)
	if id == "tunnel" then
		local dist = 12.5 - 3 * smooth(e)
		local pos = pts.entrance - out * dist + side * 2.6
		pos = V3(pos.X, floorY + 2.3 + lift * 0.4, pos.Z)
		return CFrame.lookAt(pos, pts.entrance + V3(0, 3.6 + lift * 0.9, 0)), "tunnel"
	elseif id == "aisle" then
		local fwd = -out
		local pos = rp + fwd * (plan.carry and 10.5 or 8.5) + side * 1.8
		pos = V3(pos.X, floorY + (plan.carry and 5.2 or 2.8), pos.Z)
		return CFrame.lookAt(pos, rp + V3(0, (plan.carry and lift + 1.2 or 0) + 0.9, 0)), "aisle"
	elseif id == "crowd" then
		-- beside the walkway rail ahead of him, the far stands behind him
		w.crowdAt = w.crowdAt or rp
		local pos = w.crowdAt - out * 7 + side * 7.4
		pos = V3(pos.X, floorY + 3.2 + lift * 0.5, pos.Z)
		return CFrame.lookAt(pos, rp + V3(0, 1.2 + lift, 0)), "crowd"
	elseif id == "setdown" then
		local pos = pts.steps + side * 9.5 + out * 3.5
		pos = V3(pos.X, floorY + 4.2, pos.Z)
		return CFrame.lookAt(pos, pts.steps + V3(0, 2.4 + lift * 0.6 * (1 - e), 0)), "setdown"
	elseif id == "steps" or id == "ropes" then
		-- (inside the ring, a few strides from his ropes: he comes up the steps and through them toward the lens)
		local pos = pts.centre + out * (pts.half - 7.5) + side * 4.2
		pos = V3(pos.X, canvasY + 3.6, pos.Z)
		local at = id == "steps" and pts.steps:Lerp(pts.apron, smooth(e)) or pts.apron:Lerp(pts.inside, smooth(e))
		return CFrame.lookAt(pos, V3(at.X, (id == "steps" and floorY + (canvasY - floorY) * smooth(e) or canvasY) + 2.4, at.Z)), "ringin"
	elseif id == "ring" then
		local celeb = plan.ring
		if bt < Entrance.RING_WALK then
			local pos = pts.centre - out * 1 + side * -3
			pos = V3(pos.X, canvasY + 5, pos.Z)
			return CFrame.lookAt(pos, rp + V3(0, 1.5, 0)), "ringwalk"
		elseif celeb == "victorylap" then
			local pos = pts.centre + V3(0, 0, 0) - flat(pts.corner - pts.centre) * 0.1
			pos = V3(pos.X, canvasY + 6.5, pos.Z)
			return CFrame.lookAt(pos, pts.corner + V3(0, 2, 0)), "lap"
		end
		-- outside his corner, looking back at him over the post (he faces his fans out there)
		-- (off the corner's diagonal: the post and its pad never stand between the lens and him)
		local diag = unitOr(flat(pts.post - pts.centre), out)
		local tb = celeb == "turnbuckle"
		local pos = pts.post + diag * (tb and 8.5 or 7.8) + diag:Cross(V3(0, 1, 0)) * (tb and 4.6 or 3.2)
		pos = V3(pos.X, canvasY + (tb and 4.4 or 2.8), pos.Z)
		return CFrame.lookAt(pos, pts.corner + V3(0, tb and 3.8 or 2.6, 0) + diag * (tb and 1.9 or 0)), "corner"
	elseif id == "robe" then
		local toC = unitOr(flat(pts.centre - pts.corner), -out)
		local pos = pts.corner + toC * 7.2 + toC:Cross(V3(0, 1, 0)) * 1.8
		pos = V3(pos.X, canvasY + 3.2, pos.Z)
		return CFrame.lookAt(pos, pts.corner + V3(0, 2.4, 0)), "robe"
	end
	return nil
end
EntranceFX.Shot = shot

-- the wide shot over the ring once a walk is skipped (until the tape)
local function wideShot(now)
	local w = S.walk or S.lastWalk
	local pts = w and w.plan.pts
	if not pts then
		return nil
	end
	local a = now * 0.12
	local c = pts.centre
	return CFrame.lookAt(c + V3(math.cos(a) * 30, 14, math.sin(a) * 30), c + V3(0, 3, 0))
end

-- FightClient's camera asks for the on-air shot every frame while its camMode is "entrance" (nil = its own dolly)
function EntranceFX.Camera(now)
	now = now or os.clock()
	if S.skipped then
		return wideShot(now)
	end
	local w = S.walk
	if not w then
		return nil
	end
	local cf, key = shot(w, now)
	if not cf then
		return nil
	end
	local dt = S.camT and clamp(now - S.camT, 0, 0.1) or 0
	S.camT = now
	if key ~= S.camKey or not S.cam then
		S.camKey = key
		S.cam = cf -- a hard cut
	else
		S.cam = S.cam:Lerp(cf, clamp(dt * 6, 0, 1))
	end
	return S.cam
end

------------------------------------------------------------------------
-- Per frame
------------------------------------------------------------------------
local function carriersFor()
	return ({ 2, 3, 4 })[level()]
end

local function step(dt)
	local now = os.clock()
	local w = S.walk
	-- (his own walk keeps walking on the beats even when this client skipped the pictures: PvP waits for both)
	if w and S.skipped then
		local beat = Entrance.BeatAt(w.beats, now - w.t0)
		local id = beat and beat.id or "end"
		if id ~= w.lastBeat then
			w.lastBeat = id
			drive(w, id)
		end
		if now - w.t0 > w.total + 0.5 then
			EntranceFX.EndWalk(w)
		end
	elseif w then
		local el = now - w.t0
		local beat = Entrance.BeatAt(w.beats, el)
		local id = beat and beat.id or "end"
		if id ~= w.lastBeat then
			w.lastBeat = id
			drive(w, id)
			if id == "aisle" then
				venueFX("Cheer", w.you and 0.7 or 0.45)
			elseif id == "crowd" then
				venueFX("Cheer", 0.6)
			elseif id == "ring" then
				venueFX("Cheer", 0.5)
			elseif id == "steps" then
				w.revealOn = false
				hideReveal()
			end
		end
		local r = rootOf(w.model)
		local st = AE.active[w.model]
		if r and st then
			local geo = w.geo or AE.Geom(w.model)
			w.geo = geo
			local fr = AE.Frame(st, now)
			-- the carriers: on through the tunnel, the aisle and the set-down; gone at the steps
			if w.plan.carry and (fr.mode == "carried" or fr.mode == "setdown") then
				ensureCarriers(w, geo, carriersFor())
				local down = fr.mode == "setdown" and smooth(fr.bt / ((fr.dur or 1) * 0.8)) or 0
				updateCarriers(w, r.CFrame, geo, dt, 1 - down, AE.bump(down, 0, 1) * 0.5, fr.mode == "setdown" and smooth((fr.bt - 0.5) / 0.5) or 0)
			elseif w.carriers then
				dropCarriers(w)
			end
			updateBelt(w, fr.gesture ~= nil and fr.gesture.id == "beltlift" and fr.gesture.u > 0.15 and fr.gesture.u < fr.gesture.dur - 0.15)
		end
		if el > w.total + 0.5 then
			EntranceFX.EndWalk(w)
		end
	end
	local pr = S.parade
	if pr then
		local el = now - pr.t0
		local r = rootOf(pr.model)
		if r and el < pr.dur then
			local e = smooth(el / 0.6) * (1 - smooth((el - (pr.dur - 0.6)) / 0.6))
			updateCarriers(pr, r.CFrame, pr.geo, dt, e, 0, 0, el * 0.55)
		else
			dropCarriers(pr)
			S.parade = nil
		end
	end
end

------------------------------------------------------------------------
-- Walks
------------------------------------------------------------------------
function EntranceFX.EndWalk(w)
	if not w then
		return
	end
	dropCarriers(w)
	if w.belt then
		w.belt.model:Destroy()
		w.belt = nil
	end
	if w.model then
		AE.Stop(w.model)
	end
	if S.walk == w then
		S.lastWalk = w
		S.walk = nil
	end
end

function EntranceFX.Begin(msg)
	local plan = type(msg) == "table" and msg.plan
	if type(plan) ~= "table" or not isInst(plan.model) then
		return nil -- an older server: FightClient's own walkout runs
	end
	if S.walk then
		EntranceFX.EndWalk(S.walk)
	end
	local now = os.clock()
	local beats, total = Entrance.Timeline(plan)
	local w = { plan = plan, model = plan.model, you = msg.phase == "you", t0 = now, beats = beats, total = total, revealOn = true }
	S.walk = w
	S.plans[msg.phase == "you" and "you" or "opp"] = plan
	S.camKey = nil
	if not S.skipped then
		w.st = AE.Start(w.model, plan, now)
		showReveal(plan)
		pcall(tunnelSmoke, w)
		venueFX("Cheer", w.you and 1.0 or 0.6)
		if plan.carry then
			venueFX("Cheer", 1.2)
		end
	end
	return w
end

-- the server ended the entrance (the last beat, or a skip): everything off
function EntranceFX.Finish()
	if S.walk then
		EntranceFX.EndWalk(S.walk)
	end
	AE.StopAll()
	hideUI()
	S.skipped = false
	S.cam, S.camKey = nil, nil
end

-- SKIP: this client cuts to the ring now; the server is asked to end the entrance (vs the AI: at once; PvP: both)
function EntranceFX.Skip()
	if S.skipped or not (S.walk or S.lastWalk) then
		return
	end
	S.skipped = true
	if S.walk then
		local w = S.walk
		dropCarriers(w)
		if w.belt then
			w.belt.model.Parent = nil
		end
	end
	AE.StopAll()
	local ui = S.ui
	if ui then
		ui.card.Visible = false
		ui.skip.Text = "SKIPPING..."
	end
	local remote = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remote and remote:FindFirstChild("Fight")
	if remote then
		pcall(function()
			remote:FireServer({ t = "entranceSkip" })
		end)
	end
end

-- the post-win parade: the winner is lifted where he stands for the last seconds of the final bell's shot
function EntranceFX.Parade(model, plan, dur)
	if not isInst(model) or not model.Parent then
		return
	end
	local geo = AE.Geom(model)
	local pr = { model = model, plan = plan or { corner = "Red", seed = 0 }, t0 = os.clock(), dur = dur or 3.2, geo = geo }
	ensureCarriers(pr, geo, carriersFor())
	AE.StartParade(model, pr.t0, pr.dur)
	S.parade = pr
	venueFX("Cheer", 1.3)
end

------------------------------------------------------------------------
-- Messages and input
------------------------------------------------------------------------
local SKIP_KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.ButtonA] = true }

function EntranceFX.OnMessage(msg)
	if type(msg) ~= "table" then
		return
	end
	local t = msg.t
	if t == "entrance" then
		EntranceFX.Begin(msg)
	elseif t == "entranceEnd" or t == "tape" or t == "round" or t == "aborted" or t == "result" or t == "sparResult" or t == "pvpResult" then
		EntranceFX.Finish()
	elseif t == "final" then
		EntranceFX.Finish()
		local res = type(msg.result) == "table" and msg.result or {}
		local won = res.outcome == "win"
		local winnerPlan = won and S.plans.you or (res.outcome == "loss" and S.plans.opp or nil)
		if winnerPlan and winnerPlan.afterWin and Entrance.CarryAfterWin({ won = true, method = res.method, popularity = winnerPlan.popularity,
			importance = winnerPlan.importance, title = winnerPlan.title, venue = winnerPlan.venue, pref = winnerPlan.pref }) then
			EntranceFX.Parade(winnerPlan.model, winnerPlan, 3.2)
		end
		S.plans = {}
	end
end

-- (for tools/sim/v9_entrance.luau: the same carriers and belt the game draws, driven offline)
EntranceFX._tools = { ensureCarriers = ensureCarriers, updateCarriers = updateCarriers, updateBelt = updateBelt, dropCarriers = dropCarriers }

local started = false
function EntranceFX.Start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local remote = remotes and remotes:WaitForChild("Fight", 10)
	if remote then
		remote.OnClientEvent:Connect(function(msg)
			local ok, err = pcall(EntranceFX.OnMessage, msg)
			if not ok then
				warn("[EntranceFX]", err)
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input, gp)
		if SKIP_KEYS[input.KeyCode] and S.walk and not S.skipped and not (gp and input.KeyCode ~= Enum.KeyCode.ButtonA) then
			if UserInputService:GetFocusedTextBox() then
				return
			end
			EntranceFX.Skip()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not S.warned then
			S.warned = true
			warn("[EntranceFX] step:", err)
		end
	end)
end

return EntranceFX
