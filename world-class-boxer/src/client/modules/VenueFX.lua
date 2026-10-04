-- VenueFX: client-only fight-night presentation for the player's own venue (stream G).
-- FightClient (stream D) calls every function below inside pcall (CONTRACTS 11):
--   VenueFX.Start(arena, info)  info = { venue, venueName, spar, stakes, kind, tape, rounds, oppModel, myModel }
--   VenueFX.Phase(name, data)   entrance / round / rest / kd / count / getup / bell / tier / final
--   VenueFX.Hit(data)           { target, heavy, dmg, punch }  (punch = "ropes" when a boxer is driven into them)
--   VenueFX.State(msg)          the 10 Hz fight state (clock, health for the telemetry board)
--   VenueFX.Screens(text)  VenueFX.Cheer(0..1)  VenueFX.Pyro("red"|"blue")
--   VenueFX.BroadcastCFrame(now) -> CFrame | nil  (on-air camera for the broadcast cuts)
--   VenueFX.Stop()              restores Lighting and removes everything this module made
-- What it does: fight-night lighting per venue and phase (VenueGrade / VenueBloom / VenueDOF,
-- atmosphere haze, house lights, par-can washes), follow spots with visible beams and light pools,
-- rope physics (sag, sway, bulge when a boxer leans or is knocked into them, bounce on impacts,
-- rope ties), crowd motion (bulk-moved, arms up in the front row), phone lights and camera flashes,
-- an upper-bowl crowd generated locally, jumbotron / scoreboard / LED ribbons / entrance screens,
-- walkout smoke, CO2, chase lights and pyro, confetti, gerbs and fireworks, cornermen and stool
-- between rounds, the ring announcer, panning TV cameras, a swinging jib and a gliding skycam with
-- on-air tally, canvas marks after knockdowns, window god-rays and dust in the sparring room,
-- crowd / bell audio (Config.SoundId, routed through SoundService.FightMix for concussion muffling).
-- Nothing here replicates: other players never pay for it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local VenueFX = {}
local player = Players.LocalPlayer

local V3 = Vector3.new
local CF = CFrame.new
local M = Enum.Material

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local RED = rgb(255, 60, 55)
local BLUE = rgb(70, 115, 255)
local GOLD = rgb(255, 205, 70)
local WHITE = rgb(240, 240, 240)

------------------------------------------------------------------------
-- Lighting profiles per venue, plus per-phase offsets (CONTRACTS 11: VenueGrade/Bloom/DOF are ours)
------------------------------------------------------------------------
local PROFILES = {
	CommunityCenter = {
		clock = 19.6, bright = 1.1, ambient = rgb(92, 88, 82), outdoor = rgb(70, 70, 78), exposure = 0.05, diffuse = 0.6, specular = 0.5,
		density = 0.1, haze = 0.6, atmColor = rgb(200, 190, 170), decay = rgb(120, 110, 100), glare = 0,
		contrast = 0.06, saturation = -0.1, tint = rgb(250, 248, 236), bloomI = 0.25, bloomS = 20, bloomT = 1.6,
	},
	ClubArena = {
		clock = 21.5, bright = 0.45, ambient = rgb(46, 40, 52), outdoor = rgb(30, 30, 38), exposure = 0.18, diffuse = 0.4, specular = 0.6,
		density = 0.34, haze = 2.4, atmColor = rgb(130, 110, 140), decay = rgb(70, 50, 80), glare = 0.3,
		contrast = 0.16, saturation = 0.04, tint = rgb(255, 238, 226), bloomI = 0.55, bloomS = 28, bloomT = 1.2,
	},
	Arena = {
		clock = 21.5, bright = 0.4, ambient = rgb(34, 36, 46), outdoor = rgb(26, 28, 40), exposure = 0.22, diffuse = 0.35, specular = 0.7,
		density = 0.26, haze = 1.6, atmColor = rgb(110, 116, 140), decay = rgb(60, 64, 90), glare = 0.35,
		contrast = 0.2, saturation = 0.08, tint = rgb(246, 246, 255), bloomI = 0.6, bloomS = 30, bloomT = 1.15,
	},
	Stadium = {
		clock = 21, bright = 1.0, ambient = rgb(40, 42, 56), outdoor = rgb(34, 38, 56), exposure = 0.22, diffuse = 0.4, specular = 0.7,
		density = 0.2, haze = 1.1, atmColor = rgb(92, 102, 132), decay = rgb(40, 48, 80), glare = 0.4,
		contrast = 0.22, saturation = 0.1, tint = rgb(236, 242, 255), bloomI = 0.7, bloomS = 32, bloomT = 1.1,
	},
	Gym = {
		clock = 14, bright = 1.8, ambient = rgb(80, 76, 72), outdoor = rgb(100, 96, 92), exposure = -0.05, diffuse = 0.7, specular = 0.5,
		density = 0.24, haze = 1.2, atmColor = rgb(210, 190, 160), decay = rgb(150, 130, 110), glare = 0.1,
		contrast = 0.06, saturation = 0.02, tint = rgb(255, 247, 234), bloomI = 0.3, bloomS = 24, bloomT = 1.4, gym = true,
	},
}

local PHASES = {
	start = { exposure = 0, contrast = 0, saturation = 0, bloom = 0, house = 0.55, dof = 0, spot = 5, base = 0.3 },
	entrance = { exposure = -0.28, contrast = 0.1, saturation = 0.05, bloom = 0.25, house = 0.12, dof = 0.3, spot = 8, base = 0.55 },
	round = { exposure = 0, contrast = 0.02, saturation = 0, bloom = 0, house = 0.25, dof = 0, spot = 5, base = 0.28 },
	rest = { exposure = 0.08, contrast = -0.02, saturation = 0, bloom = 0.05, house = 0.6, dof = 0, spot = 3, base = 0.35, tint = rgb(255, 238, 215) },
	win = { exposure = 0.1, contrast = 0.08, saturation = 0.12, bloom = 0.3, house = 1, dof = 0, spot = 8, base = 0.8, tint = rgb(255, 232, 192) },
	loss = { exposure = -0.12, contrast = 0.12, saturation = -0.3, bloom = 0.05, house = 0.9, dof = 0, spot = 4, base = 0.5, tint = rgb(212, 224, 255) },
	draw = { exposure = 0, contrast = 0.04, saturation = -0.05, bloom = 0.1, house = 0.9, dof = 0, spot = 6, base = 0.5 },
}

local GYM_EFFECTS = { "GymGrade", "GymBloom", "GymSunRays" }
local SHIRTS = { { 200, 30, 30 }, { 30, 60, 200 }, { 240, 240, 240 }, { 30, 30, 30 }, { 240, 190, 40 }, { 40, 150, 70 }, { 130, 40, 170 }, { 240, 120, 30 }, { 60, 60, 66 }, { 150, 150, 158 } }

local S -- the active session (nil when stopped)
local conn

local function fxScale()
	return math.clamp(tonumber(Config.ScreenFX) or 1, 0, 2)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- frame-rate independent approach factor
local function approach(dt, rate)
	return 1 - math.exp(-dt * rate)
end

local function rootOf(model)
	if typeof(model) ~= "Instance" or not model.Parent then
		return nil
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	return r and r:IsA("BasePart") and r or nil
end

local function track(inst)
	if S then
		table.insert(S.created, inst)
	end
	return inst
end

local function localPart(name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color or WHITE
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = S.folder
	return p
end

local function emitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Enabled = true
	pe.LightInfluence = 0
	for k, v in pairs(props) do
		if k ~= "Brightness" then
			pe[k] = v
		end
	end
	-- Brightness is a newer emitter property: optional
	pcall(function()
		pe.Brightness = props.Brightness or 1
	end)
	pe.Parent = parent
	return track(pe)
end

local function NS(a, b)
	return NumberSequence.new(a, b)
end

-- each subsystem runs in its own pcall: one failing piece is switched off with a single warning
-- instead of throwing every frame or taking the whole presentation down
local function step(name, fn, ...)
	if not S or S.dead[name] then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		S.dead[name] = true
		warn("[VenueFX] " .. name .. " disabled:", err)
	end
end

------------------------------------------------------------------------
-- Sound (optional uploads via Config.SoundId, built-in stand-ins only where they sound right)
------------------------------------------------------------------------
local function soundId(key)
	local ok, id = pcall(Config.SoundId, key)
	return ok and id or nil
end

local function builtin(key)
	return Config.BuiltinSounds and Config.BuiltinSounds[key] or nil
end

local function mkSound(name, id, volume, looped, speed)
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Looped = looped == true
	s.PlaybackSpeed = speed or 1
	local mix = SoundService:FindFirstChild("FightMix")
	if mix and mix:IsA("SoundGroup") then
		s.SoundGroup = mix
	end
	s.Parent = S.soundFolder
	return s
end

local function play(s, volume, speed)
	if s then
		if volume then
			s.Volume = volume
		end
		if speed then
			s.PlaybackSpeed = speed
		end
		s.TimePosition = 0
		s:Play()
	end
end

-- the ring bell: an uploaded RingBell, else Ping + a quiet metal strike for the attack
local function ringBell(times)
	if not S then
		return
	end
	-- delayed work belongs to THIS session: a new fight must not get the old fight's bells
	local sess = S
	for i = 1, times do
		task.delay((i - 1) * 0.42, function()
			if S ~= sess then
				return
			end
			if S.snd.bell then
				play(S.snd.bell, 0.9)
			else
				play(S.snd.ping, 0.55, 1.25)
				play(S.snd.clang, 0.18, 1.6)
			end
		end)
	end
	-- the timekeeper strikes the bell
	S.bellStrike = os.clock()
end

------------------------------------------------------------------------
-- Lighting
------------------------------------------------------------------------
local function saveLighting()
	local saved = {
		ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale, effects = {},
	}
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		saved.atm = { inst = atm, Density = atm.Density, Haze = atm.Haze, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Offset = atm.Offset }
	end
	S.saved = saved
end

local function restoreLighting()
	local saved = S and S.saved
	if not saved then
		return
	end
	for _, k in ipairs({ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }) do
		pcall(function()
			Lighting[k] = saved[k]
		end)
	end
	for e, on in pairs(saved.effects) do
		if e.Parent then
			e.Enabled = on
		end
	end
	local a = saved.atm
	if a and a.inst.Parent then
		a.inst.Density, a.inst.Haze, a.inst.Color, a.inst.Decay, a.inst.Glare, a.inst.Offset = a.Density, a.Haze, a.Color, a.Decay, a.Glare, a.Offset
	end
	for _, n in ipairs({ "VenueGrade", "VenueBloom", "VenueDOF" }) do
		local e = Lighting:FindFirstChild(n)
		if e then
			e:Destroy()
		end
	end
	if S.ownAtm and S.ownAtm.Parent then
		S.ownAtm:Destroy()
	end
	S.saved = nil
end

local function effect(class, name)
	local e = Lighting:FindFirstChild(name)
	if e and not e:IsA(class) then
		e:Destroy()
		e = nil
	end
	if not e then
		e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

local function setupLighting()
	saveLighting()
	local prof = S.profile
	-- the gym's own grade, bloom and sun rays belong to the gym, not to a fight night
	if not prof.gym then
		for _, n in ipairs(GYM_EFFECTS) do
			local e = Lighting:FindFirstChild(n)
			if e and e:IsA("PostEffect") then
				S.saved.effects[e] = e.Enabled
				e.Enabled = false
			end
		end
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
		S.ownAtm = atm
	end
	S.atm = atm
	atm.Color, atm.Decay, atm.Glare, atm.Offset = prof.atmColor, prof.decay, prof.glare, 0
	S.grade = effect("ColorCorrectionEffect", "VenueGrade")
	S.bloom = effect("BloomEffect", "VenueBloom")
	S.dof = effect("DepthOfFieldEffect", "VenueDOF")
	S.dof.NearIntensity = 0
	S.dof.FarIntensity = 0
	S.dof.InFocusRadius = 14
	S.dof.Enabled = false
	Lighting.ClockTime = prof.clock
	Lighting.Brightness = prof.bright
	Lighting.Ambient = prof.ambient
	Lighting.OutdoorAmbient = prof.outdoor
	pcall(function()
		Lighting.EnvironmentDiffuseScale = prof.diffuse or 0.5
		Lighting.EnvironmentSpecularScale = prof.specular or 0.5
	end)
	-- current values start from the venue base and ease toward each phase target
	S.cur = {
		exposure = Lighting.ExposureCompensation, contrast = 0, saturation = 0, bloomI = 0, house = 0.55, dof = 0, spot = 5,
		tint = WHITE, density = atm.Density, haze = atm.Haze,
	}
	S.kick = { exposure = 0, contrast = 0, saturation = 0, bloom = 0 }
end

local function setPhaseLook(name)
	local ph = PHASES[name] or PHASES.round
	local prof = S.profile
	S.look = ph
	S.tgt = {
		exposure = prof.exposure + ph.exposure, contrast = prof.contrast + ph.contrast, saturation = prof.saturation + ph.saturation,
		bloomI = prof.bloomI + ph.bloom, house = ph.house, dof = ph.dof, spot = ph.spot,
		tint = ph.tint and prof.tint:Lerp(ph.tint, 0.85) or prof.tint, density = prof.density, haze = prof.haze,
	}
	S.baseExcite = ph.base or 0.3
end

local function kick(c, sat, exposure, bloom)
	local fx = fxScale()
	S.kick.contrast += c * fx
	S.kick.saturation += sat * fx
	S.kick.exposure += exposure * fx
	S.kick.bloom += bloom * fx
end

local function updateLighting(dt)
	local cur, tgt, k = S.cur, S.tgt, S.kick
	local a = approach(dt, 1.6)
	for _, key in ipairs({ "exposure", "contrast", "saturation", "bloomI", "house", "dof", "spot", "density", "haze" }) do
		cur[key] = lerp(cur[key], tgt[key], a)
	end
	cur.tint = cur.tint:Lerp(tgt.tint, a)
	local d = math.exp(-dt * 1.4)
	k.contrast *= d
	k.saturation *= d
	k.exposure *= d
	k.bloom *= d
	local fx = math.clamp(fxScale(), 0, 1)
	-- accessibility: a low ScreenFX flattens the grade toward neutral
	local g = lerp(0.4, 1, fx)
	Lighting.ExposureCompensation = cur.exposure + k.exposure
	S.grade.Contrast = (cur.contrast + k.contrast) * g
	S.grade.Saturation = (cur.saturation + k.saturation) * g
	S.grade.TintColor = Color3.new(1, 1, 1):Lerp(cur.tint, g)
	S.bloom.Intensity = cur.bloomI + k.bloom
	S.bloom.Size = S.profile.bloomS
	S.bloom.Threshold = S.profile.bloomT
	S.atm.Density = cur.density
	S.atm.Haze = cur.haze
	local far = cur.dof * fx
	S.dof.Enabled = far > 0.02
	if S.dof.Enabled then
		local cam = workspace.CurrentCamera
		local r = rootOf(S.focusModel)
		if cam and r then
			S.dof.FocusDistance = math.clamp((cam.CFrame.Position - r.Position).Magnitude, 4, 200)
		end
		S.dof.FarIntensity = far
	end
	-- house lights, roof lamps and the upper bowl follow the house level
	for _, h in ipairs(S.house) do
		h.light.Brightness = h.base * cur.house
	end
	for _, p in ipairs(S.houseLamps) do
		p.Transparency = 1 - math.clamp(cur.house, 0.05, 1) * 0.95
	end
	for _, sg in ipairs(S.bowlGuis) do
		sg.Brightness = 0.25 + cur.house * 0.6
	end
end

------------------------------------------------------------------------
-- Arena scan helpers (everything is found by the names Venues.lua builds; all optional)
------------------------------------------------------------------------
local function arenaLocal(x, y, z)
	-- (x, z) around the ring centre, y above the canvas
	return S.center + V3(x, y, z)
end

local function figureArms(fig)
	local t = {}
	for _, n in ipairs({ "ArmL", "ArmR" }) do
		local a = fig:FindFirstChild(n)
		if a then
			table.insert(t, { p = a, side = a:GetAttribute("Side") or (n == "ArmL" and -1 or 1), pitch = a:GetAttribute("Pitch") or 0, roll = a:GetAttribute("Roll") or 0 })
		end
	end
	return t
end

local function poseArms(fig, arms, pitchL, rollL, pitchR, rollR)
	local torso = fig.PrimaryPart
	if not torso then
		return
	end
	local tcf = torso.CFrame
	for _, a in ipairs(arms) do
		local pitch = a.side < 0 and pitchL or pitchR
		local roll = a.side < 0 and rollL or rollR
		a.p.CFrame = tcf * CF(a.side * 1.05, 0.75, 0) * CFrame.Angles(pitch, 0, roll * a.side) * CF(0, -0.9, 0)
	end
end

------------------------------------------------------------------------
-- Ropes: Beam curve physics on the invisible Rope proxies (sag + sway + bulge + bounce)
------------------------------------------------------------------------
local function ropeAxisCF(pos, w)
	local x = w.Unit
	local y = V3(0, 0, 1):Cross(x)
	if y.Magnitude < 1e-3 then
		y = V3(0, 1, 0)
	end
	y = y.Unit
	return CFrame.fromMatrix(pos, x, y, x:Cross(y))
end

local function setupRopes()
	S.ropes = {}
	local bySide = {}
	for _, p in ipairs(S.arena:GetChildren()) do
		if p.Name == "Rope" and p:IsA("BasePart") then
			local a0, a1 = p:FindFirstChild("RopeA"), p:FindFirstChild("RopeB")
			local beams = {}
			for _, b in ipairs(p:GetChildren()) do
				if b:IsA("Beam") then
					table.insert(beams, b)
				end
			end
			if a0 and a1 and #beams > 0 then
				local L = p.Size.Z
				local mid = p.Position
				local outW = V3(mid.X - S.center.X, 0, mid.Z - S.center.Z)
				outW = outW.Magnitude > 0.01 and outW.Unit or V3(1, 0, 0)
				local r = {
					p = p, a0 = a0, a1 = a1, beams = beams, L = L, tier = p:GetAttribute("RopeTier") or 2, side = p:GetAttribute("RopeSide") or 1,
					sag = tonumber(p:GetAttribute("Sag")) or 0.12, outL = p.CFrame:VectorToObjectSpace(outW), off = 0, vel = 0, y = 0, yv = 0, s = 0.5,
					phase = math.random() * 6.28, w0 = V3(0, -0.1, 0), w1 = V3(0, -0.1, 0),
				}
				table.insert(S.ropes, r)
				bySide[r.side] = bySide[r.side] or {}
				bySide[r.side][r.tier] = r
			end
		end
	end
	-- rope ties: short vertical straps that hold the three ropes together (they follow the bulge)
	S.ties = {}
	local ringHalf = S.arena:GetAttribute("RingHalf") or 11
	local ts = ringHalf >= 12 and { 1 / 3, 2 / 3 } or { 0.5 }
	for _, tiers in pairs(bySide) do
		local lo, hi = tiers[1], tiers[3]
		if lo and hi then
			for _, t in ipairs(ts) do
				local aLo = track(Instance.new("Attachment"))
				aLo.Name = "TieLo"
				aLo.Parent = lo.p
				local aHi = track(Instance.new("Attachment"))
				aHi.Name = "TieHi"
				aHi.Parent = hi.p
				local b = track(Instance.new("Beam"))
				b.Name = "RopeTie"
				b.Attachment0, b.Attachment1 = aLo, aHi
				b.Width0, b.Width1 = 0.13, 0.13
				b.FaceCamera = true
				b.Segments = 1
				b.LightInfluence = 1
				b.Color = ColorSequence.new(rgb(235, 235, 235))
				b.Parent = lo.p
				table.insert(S.ties, { lo = lo, hi = hi, t = t, aLo = aLo, aHi = aHi })
			end
		end
	end
end

-- cubic Bezier point in rope-local space (P0 = +Z end, P3 = -Z end)
local function ropePoint(r, t)
	local P0, P3 = V3(0, 0, r.L / 2), V3(0, 0, -r.L / 2)
	local u = 1 - t
	return P0 * (u * u * u) + (P0 + r.w0) * (3 * u * u * t) + (P3 + r.w1) * (3 * u * t * t) + P3 * (t * t * t)
end

local ropePush = {}
local function updateRopes(dt, now)
	if #S.ropes == 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	-- who can touch the ropes: both boxers and the referee
	local roots = ropePush
	table.clear(roots)
	for _, m in ipairs({ S.info.myModel, S.info.oppModel }) do
		local r = rootOf(m)
		if r then
			table.insert(roots, r.Position)
		end
	end
	for _, ref in ipairs(S.referees) do
		local r = rootOf(ref)
		if r then
			table.insert(roots, r.Position)
		end
	end
	local tierW = { 0.55, 1, 0.9 }
	for _, r in ipairs(S.ropes) do
		local push, at = 0, r.s
		local pcf = r.p.CFrame
		for _, pos in ipairs(roots) do
			local lp = pcf:PointToObjectSpace(pos)
			local s = 0.5 - lp.Z / r.L
			if s > 0.04 and s < 0.96 then
				-- distance of the body surface past the rope line (roots stay >= 1.5 studs inside)
				local d = lp.X * r.outL.X + lp.Z * r.outL.Z + 2.25
				local hy = math.abs(lp.Y + 0.2)
				if d > 0 and hy < 4.5 then
					local p = math.min(d * 0.95, 1.7) * tierW[r.tier] * math.clamp(1.2 - hy / 4, 0.3, 1)
					if p > push then
						push, at = p, s
					end
				end
			end
		end
		r.s = lerp(r.s, at, approach(dt, 6))
		-- springy rope: bulges out under a body, bounces after impacts, settles with a little sway
		local sub = 2
		local h = dt / sub
		for _ = 1, sub do
			r.vel += ((push - r.off) * 140 - r.vel * 9) * h
			r.off += r.vel * h
			r.yv += (-r.y * 90 - r.yv * 5) * h
			r.y += r.yv * h
		end
		r.off = math.clamp(r.off, -0.35, 2.2)
		r.y = math.clamp(r.y, -0.8, 0.8)
		local sway = math.sin(now * 1.3 + r.phase) * 0.02
		local sag = (r.sag + r.y + sway + r.off * 0.18) / 0.75
		local bulge = r.off / 0.75
		local c0 = math.clamp(2 * (1 - r.s), 0.15, 1.85)
		local c1 = math.clamp(2 * r.s, 0.15, 1.85)
		local down = V3(0, -1, 0)
		local w0 = down * sag + r.outL * (bulge * c0)
		local w1 = down * sag + r.outL * (bulge * c1)
		if (w0 - r.w0).Magnitude > 0.003 or (w1 - r.w1).Magnitude > 0.003 then
			r.w0, r.w1 = w0, w1
			local m0, m1 = w0.Magnitude, w1.Magnitude
			if m0 > 1e-3 and m1 > 1e-3 then
				r.a0.CFrame = ropeAxisCF(V3(0, 0, r.L / 2), w0)
				r.a1.CFrame = ropeAxisCF(V3(0, 0, -r.L / 2), w1)
				for _, b in ipairs(r.beams) do
					b.CurveSize0, b.CurveSize1 = m0, -m1
				end
			end
		end
	end
	-- both proxies of a side run the same way, so the same t is the same spot along the side
	for _, tie in ipairs(S.ties) do
		tie.aLo.Position = ropePoint(tie.lo, tie.t)
		tie.aHi.Position = ropePoint(tie.hi, tie.t)
	end
end

local function ropeImpulse(pos, strength)
	if not S or not S.ropes then
		return
	end
	for _, r in ipairs(S.ropes) do
		local lp = r.p.CFrame:PointToObjectSpace(pos)
		local s = 0.5 - lp.Z / r.L
		local d = lp.X * r.outL.X + lp.Z * r.outL.Z
		if s > 0 and s < 1 and d > -3.2 and math.abs(lp.Y) < 5 then
			local near = math.clamp((d + 3.2) / 2, 0.2, 1)
			r.vel += strength * near * (r.tier == 1 and 0.6 or 1)
			r.yv -= strength * 0.35 * near
			r.s = s
		end
	end
end

------------------------------------------------------------------------
-- Follow spots with beams and light pools
------------------------------------------------------------------------
local rayParams
local function setupSpots()
	S.spots = {}
	local folder = S.arena:FindFirstChild("Spots")
	if not folder then
		return
	end
	for i, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			local light = p:FindFirstChildOfClass("SpotLight")
			local col = p:GetAttribute("Color")
			col = typeof(col) == "Color3" and col or (light and light.Color) or WHITE
			local from = track(Instance.new("Attachment"))
			from.Name = "BeamFrom"
			from.Position = V3(0, 0, -p.Size.Z / 2)
			from.Parent = p
			local target = localPart("SpotTarget", V3(0.2, 0.2, 0.2), CF(S.center), WHITE, nil, { Transparency = 1 })
			local to = Instance.new("Attachment")
			to.Name = "BeamTo"
			to.Parent = target
			local beam = track(Instance.new("Beam"))
			beam.Name = "SpotBeam"
			beam.Attachment0, beam.Attachment1 = from, to
			beam.Width0, beam.Width1 = 0.9, 7
			beam.FaceCamera = true
			beam.Segments = 1
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(col)
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(0.7, 0.93), NumberSequenceKeypoint.new(1, 0.97) })
			beam.Parent = p
			local pool = localPart("LightPool", V3(0.04, 8, 8), CF(S.center), col, M.Neon, { Transparency = 0.86, Shape = Enum.PartType.Cylinder })
			table.insert(S.spots, {
				p = p, base = p.Position, light = light, col = col, beam = beam, target = target, pool = pool, aim = S.center, i = i,
				hit = S.center, hitN = V3(0, 1, 0), nextRay = 0,
			})
		end
	end
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { S.folder }
	for _, m in ipairs({ S.info.myModel, S.info.oppModel }) do
		if typeof(m) == "Instance" then
			table.insert(ex, m)
		end
	end
	local crowd = S.arena:FindFirstChild("Crowd")
	if crowd then
		table.insert(ex, crowd)
	end
	local js = S.arena:FindFirstChild("Jumbotron")
	if js then
		table.insert(ex, js)
	end
	rayParams.FilterDescendantsInstances = ex
end

local function spotGoal(s, now)
	local mode = S.spotMode
	local function on(model, wobble)
		local r = rootOf(model)
		if r then
			local p = r.Position
			return V3(p.X + math.cos(now * 0.7 + s.i) * wobble, p.Y - 2.6, p.Z + math.sin(now * 0.6 + s.i) * wobble)
		end
		return nil
	end
	local function sweep()
		local a = now * 0.35 + s.i * 1.7
		local rr = S.crowdR
		return S.center + V3(math.cos(a) * rr, S.crowdY + math.sin(now * 0.9 + s.i) * 3, math.sin(a * 0.8) * rr)
	end
	if mode == "walker" then
		if s.i <= 2 then
			return on(S.focusModel, 0.3) or sweep()
		end
		return sweep()
	elseif mode == "downed" then
		return on(S.downModel, 0.15) or S.center
	elseif mode == "winner" then
		return on(S.winModel, 0.25) or sweep()
	elseif mode == "sweep" then
		return sweep()
	end
	-- ring: the spots split over the two boxers, operators drifting a little
	local m = s.i % 2 == 1 and S.info.myModel or S.info.oppModel
	return on(m, 0.6) or (S.center + V3(math.cos(now * 0.3 + s.i) * 3, 0, math.sin(now * 0.25 + s.i) * 3))
end

local function updateSpots(dt, now)
	if #S.spots == 0 then
		return
	end
	local rate = (S.spotMode == "downed" or S.spotMode == "winner") and 7 or 3.2
	local a = approach(dt, rate)
	local bright = S.cur.spot
	for _, s in ipairs(S.spots) do
		local goal = spotGoal(s, now)
		s.aim = s.aim:Lerp(goal, a)
		local dir = s.aim - s.base
		if dir.Magnitude > 0.1 then
			s.p.CFrame = CFrame.lookAt(s.base, s.aim)
		end
		if s.light then
			s.light.Brightness = bright
		end
		if now >= s.nextRay then
			s.nextRay = now + 0.08
			local res = workspace:Raycast(s.base, dir.Unit * math.min(140, dir.Magnitude + 8), rayParams)
			if res then
				s.hit, s.hitN = res.Position, res.Normal
			else
				s.hit, s.hitN = s.aim, V3(0, 1, 0)
			end
		end
		local dist = (s.hit - s.base).Magnitude
		local d = math.clamp(dist * 0.2, 4, 14)
		s.target.CFrame = CF(s.hit)
		s.beam.Width1 = d * 0.85
		s.pool.Size = V3(0.04, d, d)
		s.pool.CFrame = CFrame.lookAt(s.hit + s.hitN * 0.04, s.hit + s.hitN * 2) * CFrame.Angles(0, math.pi / 2, 0)
		local vis = math.clamp(bright / 8, 0.15, 1)
		s.pool.Transparency = 1 - 0.14 * vis
	end
end

------------------------------------------------------------------------
-- Crowd (front-row arms, supporters, bulk-moved, distance-culled) and the upper bowl
------------------------------------------------------------------------
local function setupCrowd()
	S.fans = {}
	S.bulkParts, S.bulkCFs = {}, {}
	local crowd = S.arena:FindFirstChild("Crowd")
	local minR, maxR, sumY, n = math.huge, 0, 0, 0
	if crowd then
		for _, fan in ipairs(crowd:GetChildren()) do
			if fan:IsA("BasePart") and fan.Name == "Fan" then
				local e = { fan = fan, base = fan.CFrame, kids = {}, phase = math.random() * 6.28, speed = 5 + math.random() * 4, sup = fan:GetAttribute("Supporter") == true }
				for _, c in ipairs(fan:GetChildren()) do
					if c:IsA("BasePart") then
						local side = c:GetAttribute("Side")
						local rel = fan.CFrame:ToObjectSpace(c.CFrame)
						table.insert(e.kids, { p = c, rel = rel, side = (c.Name == "ArmL" or c.Name == "ArmR") and side or nil })
					end
				end
				table.insert(S.fans, e)
				local flat = V3(fan.Position.X - S.center.X, 0, fan.Position.Z - S.center.Z)
				minR = math.min(minR, flat.Magnitude)
				maxR = math.max(maxR, flat.Magnitude)
				sumY += fan.Position.Y
				n += 1
			end
		end
	end
	S.crowdR = n > 0 and (minR + maxR) / 2 or 30
	S.crowdY = n > 0 and (sumY / n - S.center.Y) or 4
	S.fanIdx = 0
end

local function updateCrowd(dt, now)
	local fans = S.fans
	local count = #fans
	if count == 0 then
		return
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or S.center
	local ex = S.excite
	local parts, cfs = S.bulkParts, S.bulkCFs
	local k = 0
	-- half the crowd per tick: at 30 Hz each fan still moves 15 times a second
	S.fanIdx = (S.fanIdx + 1) % 2
	for i = 1 + S.fanIdx, count, 2 do
		local e = fans[i]
		if (e.base.Position - camPos).Magnitude < 170 then
			local amp = 0.08 + ex * 1.1 + (e.sup and S.supportBoost or 0)
			local up = math.max(0, math.sin(now * e.speed + e.phase)) * amp
			local sway = math.sin(now * 1.1 + e.phase) * 0.05 * (0.3 + ex)
			local cf = e.base * CF(0, up, 0) * CFrame.Angles(0, 0, sway)
			k += 1
			parts[k], cfs[k] = e.fan, cf
			local raise = math.clamp((ex - 0.5) * 2.2 + (e.sup and S.supportBoost or 0), 0, 1) * (0.55 + 0.45 * math.sin(now * e.speed * 0.5 + e.phase))
			for _, c in ipairs(e.kids) do
				k += 1
				parts[k] = c.p
				if c.side then
					-- arms swing up around the shoulder
					local s = c.side
					cfs[k] = cf * CF(s * 1.02, 0.85, 0) * CFrame.Angles(0, 0, s * raise * 2.6) * CF(0, -0.8, 0)
				else
					cfs[k] = cf * c.rel
				end
			end
		end
	end
	for j = k + 1, #parts do
		parts[j], cfs[j] = nil, nil
	end
	if k > 0 then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for j = 1, k do
				parts[j].CFrame = cfs[j]
			end
		end
	end
end

-- the upper bowl's heads are RichText dots generated here, so the server never replicates them
local function setupBowl()
	S.bowlGuis = {}
	local bowl = S.arena:FindFirstChild("Bowl")
	if not bowl then
		return
	end
	local share = tonumber(S.arena:GetAttribute("CrowdShare")) or 1
	local rng = Random.new(#S.venue * 977)
	for _, slab in ipairs(bowl:GetChildren()) do
		local sg = slab:FindFirstChild("CrowdPrint")
		local rows = tonumber(slab:GetAttribute("CrowdRows"))
		if sg and rows then
			local fill = (tonumber(slab:GetAttribute("Fill")) or 0.85) * share
			for i = 0, rows - 1 do
				local parts = table.create(110)
				for j = 1, 110 do
					if rng:NextNumber() < fill then
						local sh = SHIRTS[rng:NextInteger(1, #SHIRTS)]
						local kk = 0.5 + rng:NextNumber() * 0.5
						parts[j] = string.format('<font color="#%02x%02x%02x">●</font>', math.floor(sh[1] * kk), math.floor(sh[2] * kk), math.floor(sh[3] * kk))
					else
						parts[j] = '<font transparency="1">●</font>'
					end
				end
				local l = track(Instance.new("TextLabel"))
				l.Name = "CrowdRow"
				l.BackgroundTransparency = 1
				l.RichText = true
				l.TextScaled = true
				l.Font = Enum.Font.Arial
				l.TextColor3 = WHITE
				l.Text = table.concat(parts)
				l.Size = UDim2.fromScale(1, 1 / rows)
				l.Position = UDim2.fromScale(0, i / rows)
				l.Parent = sg
			end
			-- lit by the house level instead of the (out of range) lights
			sg.LightInfluence = 0
			table.insert(S.bowlGuis, sg)
		end
	end
end

------------------------------------------------------------------------
-- Particles: phone lights, camera flashes, smoke, CO2, confetti, gerbs, fireworks, dust
------------------------------------------------------------------------
local function setupParticles()
	S.phones, S.flashes = {}, {}
	-- one volume per stand side, sized from the fans actually seated there
	local boxes = {}
	for _, e in ipairs(S.fans) do
		local p = e.fan.Position - S.center
		local side = math.abs(p.Z) > math.abs(p.X) and (p.Z > 0 and 1 or 3) or (p.X > 0 and 2 or 4)
		local b = boxes[side]
		if not b then
			b = { min = p, max = p }
			boxes[side] = b
		end
		b.min = V3(math.min(b.min.X, p.X), math.min(b.min.Y, p.Y), math.min(b.min.Z, p.Z))
		b.max = V3(math.max(b.max.X, p.X), math.max(b.max.Y, p.Y), math.max(b.max.Z, p.Z))
	end
	local vols = {}
	for _, b in pairs(boxes) do
		local size = (b.max - b.min) + V3(2, 2, 2)
		table.insert(vols, localPart("CrowdVolume", size, CF(S.center + (b.min + b.max) / 2 + V3(0, 1.2, 0)), WHITE, nil, { Transparency = 1 }))
	end
	local bowl = S.arena:FindFirstChild("Bowl")
	if bowl then
		for _, slab in ipairs(bowl:GetChildren()) do
			if slab.Name == "BowlTier" and slab:IsA("BasePart") then
				table.insert(vols, slab)
			end
		end
	end
	for _, v in ipairs(vols) do
		local far = v.Name == "BowlTier"
		table.insert(S.phones, emitter(v, {
			Name = "PhoneLights", Lifetime = NumberRange.new(2.5, 5), Speed = NumberRange.new(0), Size = NS(far and 0.55 or 0.22),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.15), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1, Color = ColorSequence.new(rgb(230, 240, 255)), LockedToPart = true,
		}))
		table.insert(S.flashes, emitter(v, {
			Name = "CameraFlashes", Lifetime = NumberRange.new(0.05, 0.11), Speed = NumberRange.new(0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, far and 1.6 or 0.8), NumberSequenceKeypoint.new(1, 0) }), LightEmission = 1, Color = ColorSequence.new(WHITE),
			Brightness = 4,
		}))
	end
	-- above the ring: confetti and (pyro venues) corner gerbs
	S.confetti = {}
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local p = localPart("ConfettiCannon", V3(4, 1, 4), CF(arenaLocal(c[1] * 5, 22, c[2] * 5)), WHITE, nil, { Transparency = 1 })
		table.insert(S.confetti, emitter(p, {
			Name = "Confetti", EmissionDirection = Enum.NormalId.Bottom, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(70, 70), Acceleration = V3(0, -4.5, 0), Drag = 1.3, RotSpeed = NumberRange.new(-260, 260), Rotation = NumberRange.new(0, 360),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0.26) }), LightInfluence = 1, LightEmission = 0.25,
			Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD), ColorSequenceKeypoint.new(0.33, WHITE), ColorSequenceKeypoint.new(0.66, RED), ColorSequenceKeypoint.new(1, BLUE) }),
		}))
	end
	S.gerbs = {}
	if S.arena:FindFirstChild("Pyro") then
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local h = S.ringHalf
			local p = localPart("Gerb", V3(0.4, 0.4, 0.4), CF(arenaLocal(c[1] * h, 5.9, c[2] * h)), WHITE, nil, { Transparency = 1 })
			table.insert(S.gerbs, emitter(p, {
				Name = "Gerb", EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.7, 1.2), Speed = NumberRange.new(18, 26), SpreadAngle = Vector2.new(5, 5),
				Acceleration = V3(0, -32, 0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.08) }), LightEmission = 1,
				Color = ColorSequence.new(rgb(255, 236, 160), rgb(255, 150, 40)), Brightness = 3,
			}))
		end
	end
	-- fireworks over the stadium bowl rim
	S.fireworks = {}
	if S.venue == "Stadium" then
		for k = 1, 6 do
			local a = k / 6 * math.pi * 2
			local p = localPart("Firework", V3(1, 1, 1), CF(arenaLocal(math.cos(a) * 90, 75 + (k % 3) * 6, math.sin(a) * 90)), WHITE, nil, { Transparency = 1 })
			local light = Instance.new("PointLight")
			light.Range = 60
			light.Brightness = 0
			light.Parent = p
			table.insert(S.fireworks, {
				light = light,
				pe = emitter(p, {
					Name = "Firework", Lifetime = NumberRange.new(1.1, 1.8), Speed = NumberRange.new(26, 36), SpreadAngle = Vector2.new(180, 180), Drag = 2.4,
					Acceleration = V3(0, -10, 0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) }), LightEmission = 1, Brightness = 4,
				}),
			})
		end
	end
	-- walkout smoke and CO2 jets on the entrance stage (club: smoke at the tunnel)
	S.smoke, S.co2 = { Red = {}, Blue = {} }, { Red = {}, Blue = {} }
	for _, d in ipairs(S.arena:GetDescendants()) do
		if d:IsA("BasePart") then
			local corner = d:GetAttribute("Corner")
			if d.Name == "SmokeJet" and S.smoke[corner] then
				table.insert(S.smoke[corner], emitter(d, {
					Name = "Smoke", EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(1.5, 4), SpreadAngle = Vector2.new(60, 60),
					Acceleration = V3(0, 0.3, 0), Drag = 0.8, RotSpeed = NumberRange.new(-20, 20), Rotation = NumberRange.new(0, 360),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) }),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), LightInfluence = 1, Color = ColorSequence.new(rgb(190, 190, 200)),
				}))
			elseif d.Name == "CO2Jet" and S.co2[corner] then
				table.insert(S.co2[corner], emitter(d, {
					Name = "CO2", EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(45, 58), SpreadAngle = Vector2.new(5, 5),
					Drag = 3, Acceleration = V3(0, -6, 0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 7) }),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }), LightInfluence = 0.6, Color = ColorSequence.new(WHITE),
				}))
			end
		end
	end
	if S.venue == "ClubArena" or S.venue == "CommunityCenter" then
		for _, t in ipairs(S.arena:GetChildren()) do
			if t.Name == "Tunnel" and t:IsA("BasePart") then
				local corner = (t.Position - S.center).Z < 0 and "Red" or "Blue"
				local dir = (t.Position - S.center).Z < 0 and 1 or -1
				local p = localPart("TunnelSmoke", V3(8, 1, 2), CF(t.Position + V3(0, -6.5, dir * 3)), WHITE, nil, { Transparency = 1 })
				table.insert(S.smoke[corner], emitter(p, {
					Name = "Smoke", EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(70, 70),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 9) }), RotSpeed = NumberRange.new(-20, 20),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }), LightInfluence = 1, Color = ColorSequence.new(rgb(180, 180, 190)),
				}))
			end
		end
	end
end

local function phones(rate)
	for _, pe in ipairs(S.phones) do
		pe.Rate = rate * (pe.Parent and pe.Parent.Name == "BowlTier" and 2.2 or 1)
	end
end

local function flashBurst(n)
	if not S then
		return
	end
	for _, pe in ipairs(S.flashes) do
		pe:Emit(math.max(1, math.floor(n * (pe.Parent and pe.Parent.Name == "BowlTier" and 1.6 or 1))))
	end
end

local function confettiBurst()
	for _, pe in ipairs(S.confetti) do
		pe:Emit(140)
	end
end

local function gerbs(dur)
	for _, pe in ipairs(S.gerbs) do
		pe.Rate = 160
	end
	local sess = S
	task.delay(dur, function()
		if S == sess then
			for _, pe in ipairs(S.gerbs) do
				pe.Rate = 0
			end
		end
	end)
end

local function fireworks(bursts)
	if #S.fireworks == 0 then
		return
	end
	local palette = { GOLD, RED, BLUE, WHITE, rgb(80, 255, 140), rgb(255, 120, 220) }
	local sess = S
	for b = 1, bursts do
		task.delay((b - 1) * 0.55 + math.random() * 0.2, function()
			if S ~= sess or #S.fireworks == 0 then
				return
			end
			local f = S.fireworks[math.random(1, #S.fireworks)]
			local col = palette[math.random(1, #palette)]
			f.pe.Color = ColorSequence.new(col, col:Lerp(WHITE, 0.5))
			f.pe:Emit(80)
			f.light.Color = col
			f.light.Brightness = 6
			task.delay(0.25, function()
				if f.light.Parent then
					f.light.Brightness = 0
				end
			end)
		end)
	end
end

local function walkoutFX(corner, burst)
	for _, pe in ipairs(S.smoke[corner] or {}) do
		if burst then
			pe:Emit(28)
		end
		pe.Rate = 8
	end
	if burst then
		for _, pe in ipairs(S.co2[corner] or {}) do
			pe:Emit(90)
		end
	end
	local sess = S
	task.delay(7, function()
		if S == sess then
			for _, pe in ipairs(S.smoke[corner] or {}) do
				pe.Rate = 0
			end
		end
	end)
end

------------------------------------------------------------------------
-- Screens, LED ribbons, entrance screens, walk lights, chase lights, par cans
------------------------------------------------------------------------
local function recordText(rec)
	if type(rec) ~= "table" then
		return ""
	end
	local s = string.format("%d-%d-%d", rec.w or 0, rec.l or 0, rec.d or 0)
	if (rec.ko or 0) > 0 then
		s ..= string.format("  (%d KO)", rec.ko)
	end
	return s
end

local function setupScreens()
	S.screens = { text = {}, red = {}, blue = {}, round = {}, clock = {}, header = {} }
	S.tickers, S.flashFrames, S.sweeps, S.entrance = {}, {}, {}, { Red = {}, Blue = {} }
	local tape = type(S.info.tape) == "table" and S.info.tape or {}
	local you, opp = tape.you or {}, tape.opp or {}
	local header = (S.info.venueName and S.info.venueName ~= "") and string.upper(S.info.venueName) or "WCB FIGHT NIGHT"
	if #S.stakes > 0 then
		header = table.concat(S.stakes, " - ") .. " WORLD CHAMPIONSHIP"
	elseif S.spar then
		header = "SPARRING"
	end
	for _, d in ipairs(S.arena:GetDescendants()) do
		if d:IsA("SurfaceGui") then
			if d.Name == "Screen" then
				local corner = d.Parent and d.Parent:GetAttribute("Corner")
				for _, l in ipairs(d:GetDescendants()) do
					if l:IsA("TextLabel") then
						if corner and (l.Name == "Name" or l.Name == "Nick" or l.Name == "Record") then
							S.entrance[corner][l.Name] = l
						elseif l.Name == "ScreenText" then
							table.insert(S.screens.text, l)
						elseif l.Name == "NameRed" then
							table.insert(S.screens.red, l)
							l.Text = string.upper(you.name or "RED CORNER")
						elseif l.Name == "NameBlue" then
							table.insert(S.screens.blue, l)
							l.Text = string.upper(opp.name or "BLUE CORNER")
						elseif l.Name == "Round" then
							table.insert(S.screens.round, l)
						elseif l.Name == "Clock" then
							table.insert(S.screens.clock, l)
						elseif l.Name == "Header" and l.Parent and l.Parent.Name == "Bg" and not corner then
							table.insert(S.screens.header, l)
							if d.Parent.Name ~= "Telemetry" then
								l.Text = header
							end
						end
					end
				end
			elseif d.Name == "Ribbon" then
				local tick = d:FindFirstChild("Ticker")
				local text = tick and tick:FindFirstChild("Text")
				if text then
					table.insert(S.tickers, { label = text, base = text.Text, offset = math.random() * 300 })
				end
				local fl = d:FindFirstChild("Flash")
				if fl then
					table.insert(S.flashFrames, fl)
				end
				local g = tick and tick:FindFirstChild("Sweep")
				if g then
					table.insert(S.sweeps, g)
				end
			elseif d.Name == "SkirtPrint" then
				local g = d:FindFirstChild("Sweep", true)
				if g then
					table.insert(S.sweeps, g)
				end
			end
		end
	end
	for corner, who in pairs({ Red = you, Blue = opp }) do
		local e = S.entrance[corner]
		if e.Name then
			e.Name.Text = string.upper(who.name or (corner .. " CORNER"))
		end
		if e.Nick then
			e.Nick.Text = (who.nick and who.nick ~= "") and ('"' .. string.upper(who.nick) .. '"') or ""
		end
		if e.Record then
			e.Record.Text = recordText(who.record) .. ((who.nat and who.nat ~= "") and ("   " .. string.upper(who.nat)) or "")
		end
	end
	-- the walk is lit and the chase tiles run per corner
	S.chase = { Red = {}, Blue = {} }
	S.archLeds = { Red = {}, Blue = {} }
	S.walkLights = {}
	S.parCans = {}
	for _, d in ipairs(S.arena:GetDescendants()) do
		if d:IsA("BasePart") then
			local corner = d:GetAttribute("Corner")
			if d.Name == "Chase" and S.chase[corner] then
				table.insert(S.chase[corner], { p = d, idx = d:GetAttribute("Idx") or 1 })
			elseif d.Name == "ArchLED" and S.archLeds[corner] then
				table.insert(S.archLeds[corner], d)
			elseif d.Name == "WalkLight" then
				local l = d:FindFirstChildOfClass("PointLight")
				if l then
					table.insert(S.walkLights, { light = l, corner = (d.Position - S.center).Z < 0 and "Red" or "Blue", base = l.Brightness })
				end
			elseif d.Name == "ParCan" then
				local l = d:FindFirstChildOfClass("SpotLight")
				local lens = d:FindFirstChild("Lens")
				local glow = lens and lens:FindFirstChild("Glow")
				if l then
					table.insert(S.parCans, { light = l, glow = glow, base = l.Color, wash = d:GetAttribute("Wash") or "amber", bright = l.Brightness })
				end
			end
		end
	end
end

local function setScreens(text, hold)
	for _, l in ipairs(S.screens.text) do
		l.Text = text
	end
	S.screenPop = 1
	S.screenHold = os.clock() + (hold or 4)
end

local function ribbonText(text)
	for _, t in ipairs(S.tickers) do
		t.label.Text = text and string.rep(text, 6) or t.base
	end
end

local function ribbonFlash(color, dur)
	S.ribbonFlash = { color = color, untilT = os.clock() + (dur or 1.5) }
end

local function updateScreens(dt, now)
	for _, t in ipairs(S.tickers) do
		local lab = t.label
		local w = lab.TextBounds.X
		if w > 0 then
			-- the text is repeated, so wrapping at a third of it is seamless
			t.offset = (t.offset + 55 * dt) % math.max(1, w / 3)
			lab.Position = UDim2.new(0, -math.floor(t.offset), 0, 0)
		end
	end
	for _, g in ipairs(S.sweeps) do
		g.Offset = Vector2.new(math.sin(now * 0.6) * 0.6, 0)
	end
	local rf = S.ribbonFlash
	local on = rf and now < rf.untilT
	for _, f in ipairs(S.flashFrames) do
		if on then
			local blink = math.floor(now * 8) % 2 == 0
			f.BackgroundColor3 = blink and rf.color or WHITE
			f.BackgroundTransparency = blink and 0.35 or 0.7
		elseif f.BackgroundTransparency < 1 then
			f.BackgroundTransparency = 1
		end
	end
	if S.screenPop > 0 then
		S.screenPop = math.max(0, S.screenPop - dt * 2)
		for _, l in ipairs(S.screens.text) do
			l.TextTransparency = 0
			l.TextStrokeTransparency = 1 - S.screenPop * 0.8
		end
	end
	-- chase lights: a travelling wave toward the ring for the boxer walking out
	for corner, tiles in pairs(S.chase) do
		local active = S.walkCorner == corner or S.chaseAll
		for _, c in ipairs(tiles) do
			if active then
				local w = (now * 7 - c.idx * 0.9) % 6
				c.p.Transparency = w < 1.2 and 0 or 0.72
			elseif c.p.Transparency ~= 0.75 then
				c.p.Transparency = 0.75
			end
		end
	end
	for corner, leds in pairs(S.archLeds) do
		local active = S.walkCorner == corner or S.chaseAll
		local tr = active and (0.05 + 0.25 * (0.5 + 0.5 * math.sin(now * 9))) or 0.55
		for _, p in ipairs(leds) do
			p.Transparency = tr
		end
	end
end

local function setWalkLights(corner)
	for _, w in ipairs(S.walkLights) do
		w.light.Brightness = (corner == nil or w.corner == corner) and w.base * (corner and 1.6 or 0.4) or w.base * 0.15
	end
end

local function setWash(mode, corner)
	for _, c in ipairs(S.parCans) do
		local col = c.base
		local bright = c.bright
		if mode == "walk" then
			col = corner == "Red" and RED or BLUE
			bright = c.bright * 1.4
		elseif mode == "rest" then
			col = rgb(255, 190, 120)
			bright = c.bright * 0.6
		elseif mode == "win" then
			col = GOLD
			bright = c.bright * 1.5
		elseif mode == "loss" then
			col = rgb(120, 140, 255)
		end
		c.light.Color = col
		c.light.Brightness = bright
		if c.glow then
			c.glow.BackgroundColor3 = col
		end
	end
end

------------------------------------------------------------------------
-- People: cornermen + stool between rounds, the announcer, gym onlookers
------------------------------------------------------------------------
local function setupPeople()
	S.corner, S.stools, S.watchers = {}, {}, {}
	local off = S.arena:FindFirstChild("Officials")
	local half = S.ringHalf
	if off then
		for _, fig in ipairs(off:GetChildren()) do
			if fig:IsA("Model") and fig.PrimaryPart then
				local loop = fig:GetAttribute("Loop")
				local role = fig:GetAttribute("Role")
				local e = { m = fig, home = fig:GetPivot(), arms = figureArms(fig), phase = math.random() * 6.28, role = role }
				if loop == "cornerman" then
					local s = fig:GetAttribute("Corner") == "Blue" and 1 or -1
					local diag = V3(s, 0, s).Unit
					local perp = V3(-diag.Z, 0, diag.X)
					local slot = fig:GetAttribute("Slot") or 1
					local pos = arenaLocal(s * (half + 1.9), 0, s * (half + 1.9)) + perp * (slot == 1 and -1.4 or 1.4)
					local hipH = e.home.Position.Y - S.floorY
					e.rest = CFrame.lookAt(pos + V3(0, hipH, 0), S.center + V3(0, hipH, 0))
					table.insert(S.corner, e)
				elseif role == "Announcer" then
					local hipH = e.home.Position.Y - S.floorY
					e.stage = CFrame.lookAt(S.center + V3(0, hipH, 2.5), S.center + V3(0, hipH, -6))
					S.announcer = e
				elseif loop == "ringside" or loop == "coachwatch" or role == "Judge" or role == "Timekeeper" or role == "CameraOp" or role == "Press" then
					table.insert(S.watchers, e)
				end
			end
		end
	end
	for _, st in ipairs(S.arena:GetChildren()) do
		if st:IsA("Model") and st.Name == "CornerStool" then
			local s = st:GetAttribute("Corner") == "Blue" and 1 or -1
			local home = st:GetPivot()
			local target = arenaLocal(s * (half - 1.3), 0, s * (half - 1.3))
			-- the stool moves from the floor into the corner on the canvas
			local delta = V3(target.X - home.Position.X, S.center.Y - S.floorY, target.Z - home.Position.Z)
			table.insert(S.stools, { m = st, home = home, rest = CF(delta) * home })
		end
	end
end

local function cornerMode(on)
	for _, e in ipairs(S.corner) do
		if e.m.Parent then
			e.m:PivotTo(on and e.rest or e.home)
			if not on and e.arms[1] then
				-- back on the floor with their hands down
				poseArms(e.m, e.arms, e.arms[1].pitch, e.arms[1].roll, e.arms[1].pitch, e.arms[1].roll)
			end
		end
	end
	for _, s in ipairs(S.stools) do
		if s.m.Parent then
			s.m:PivotTo(on and s.rest or s.home)
		end
	end
	S.cornerOn = on
end

local function announcerMode(on)
	local a = S.announcer
	if a and a.m.Parent then
		a.m:PivotTo(on and a.stage or a.home)
		S.announcing = on
	end
end

local function updatePeople(dt, now)
	if S.cornerOn then
		for _, e in ipairs(S.corner) do
			local w = math.sin(now * 3 + e.phase)
			if e.role == "Cutman" then
				-- working on the face: both hands up and forward
				poseArms(e.m, e.arms, 1.9 + w * 0.1, 0.2, 1.7 - w * 0.12, 0.25)
			else
				-- the trainer talks with his hands, towel-waving the fighter
				poseArms(e.m, e.arms, 1.2 + w * 0.5, 0.3, 0.6 + math.sin(now * 6 + e.phase) * 0.6, 0.5)
			end
		end
	end
	if S.announcing and S.announcer then
		local w = math.sin(now * 2.2)
		poseArms(S.announcer.m, S.announcer.arms, 0.3 + w * 0.6, 0.6 + w * 0.3, 2.5, 0.25)
	end
	-- watchers react to the action: hands up when it gets wild, the timekeeper strikes the bell
	local ex = S.excite
	for _, e in ipairs(S.watchers) do
		local a = e.arms[1]
		if a then
			if e.role == "Timekeeper" then
				local strike = S.bellStrike and now - S.bellStrike < 2 and math.max(0, math.sin((now - S.bellStrike) * 15)) or 0
				poseArms(e.m, e.arms, 0.8, 0.12, 0.8 + strike * 0.7, 0.12)
			elseif e.role == "Onlooker" or e.role == "Coach" then
				local up = math.clamp((ex - 0.55) * 2.5, 0, 1)
				local clap = up > 0.2 and math.sin(now * 14 + e.phase) * 0.15 or 0
				local p0 = e.arms[1].pitch
				poseArms(e.m, e.arms, lerp(p0, 2.7, up) + clap, lerp(e.arms[1].roll, -0.3, up), lerp(p0, 2.7, up) - clap, lerp(e.arms[1].roll, -0.3, up))
			end
		end
	end
end

------------------------------------------------------------------------
-- Broadcast: panning cameras, jib, skycam, on-air tally
------------------------------------------------------------------------
local function setupBroadcast()
	S.cams, S.sources = {}, {}
	local bc = S.arena:FindFirstChild("Broadcast")
	if not bc then
		return
	end
	for _, m in ipairs(bc:GetChildren()) do
		if m:IsA("Model") and m.Name == "BroadcastCam" then
			local body = m:FindFirstChild("TVCamera")
			if body then
				local e = { body = body, pos = body.Position, rel = {}, tally = m:FindFirstChild("TallyLight") }
				for _, n in ipairs({ "TVCamera", "Lens", "Viewfinder", "TallyLight" }) do
					local p = m:FindFirstChild(n)
					if p then
						table.insert(e.rel, { p = p, rel = body.CFrame:ToObjectSpace(p.CFrame) })
					end
				end
				table.insert(S.cams, e)
				table.insert(S.sources, { kind = "cam", e = e })
			end
		elseif m:IsA("Model") and m.Name == "Jib" then
			local pivot = m:GetAttribute("Pivot")
			local aim = m:GetAttribute("Aim")
			if typeof(pivot) == "Vector3" and typeof(aim) == "Vector3" then
				-- attributes are template-space: re-anchor them on the arena's actual position
				local head = m:FindFirstChild("JibCam")
				local col = m:FindFirstChild("JibColumn")
				local pivotW = col and (col.Position + V3(0, col.Size.X / 2, 0)) or pivot
				local flat = V3(aim.X, 0, aim.Z)
				flat = flat.Magnitude > 0.01 and flat.Unit or V3(-1, 0, 0)
				local p0 = CFrame.lookAt(pivotW, pivotW + flat)
				local e = { parts = {}, p0 = p0, head = head, tally = m:FindFirstChild("TallyLight") }
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") and p:GetAttribute("Moving") then
						table.insert(e.parts, { p = p, rel = p0:ToObjectSpace(p.CFrame) })
					end
				end
				S.jib = e
				table.insert(S.sources, { kind = "jib", e = e })
			end
		end
	end
	local sky = bc:FindFirstChild("SkyCam")
	if sky and sky:IsA("BasePart") then
		local tally = localPart("SkyTally", V3(0.3, 0.3, 0.3), sky.CFrame * CF(0, -0.7, 0), rgb(255, 30, 30), M.Neon)
		S.sky = { p = sky, tally = tally, y = sky.Position.Y - S.center.Y }
		table.insert(S.sources, { kind = "sky", e = S.sky })
	end
	S.onAir = nil
	S.srcIdx = 0
end

local function focusPoint()
	local a, b = rootOf(S.info.myModel), rootOf(S.info.oppModel)
	if a and b then
		return (a.Position + b.Position) / 2 + V3(0, 0.6, 0)
	end
	local r = a or b
	return r and r.Position or (S.center + V3(0, 3, 0))
end

local function updateBroadcast(dt, now)
	local focus = focusPoint()
	for _, e in ipairs(S.cams) do
		local look = CFrame.lookAt(e.pos, focus)
		for _, r in ipairs(e.rel) do
			r.p.CFrame = look * r.rel
		end
		if e.tally then
			e.tally.Transparency = (S.onAir == e) and 0 or 0.85
		end
	end
	local j = S.jib
	if j then
		local yaw = math.sin(now * 0.21) * 0.45
		local pitch = math.sin(now * 0.31) * 0.14
		local pcf = j.p0 * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		for _, r in ipairs(j.parts) do
			r.p.CFrame = pcf * r.rel
		end
		if j.head then
			local hp = j.head.Position
			j.head.CFrame = CFrame.lookAt(hp, focus)
			if j.tally then
				j.tally.CFrame = j.head.CFrame * CF(0, 0.75, -0.6)
			end
		end
		if j.tally then
			j.tally.Transparency = (S.onAir == j) and 0 or 0.85
		end
	end
	local sky = S.sky
	if sky then
		local h = S.ringHalf
		local pos = S.center + V3(math.sin(now * 0.11) * h * 0.75, sky.y + math.sin(now * 0.17) * 2.5, math.cos(now * 0.09) * h * 0.75)
		sky.p.CFrame = CFrame.lookAt(pos, focus)
		sky.tally.CFrame = sky.p.CFrame * CF(0, -0.7, 0)
		sky.tally.Transparency = (S.onAir == sky) and 0 or 0.85
	end
end

------------------------------------------------------------------------
-- Sparring room: window god-rays, dust, round timer, telemetry
------------------------------------------------------------------------
local function setupGym()
	S.gymTimer = nil
	S.telemetry = nil
	for _, d in ipairs(S.arena:GetDescendants()) do
		if d.Name == "WindowPane" and d:IsA("BasePart") then
			local dir = d:GetAttribute("SunDir")
			dir = typeof(dir) == "Vector3" and dir.Unit or V3(-1, -0.75, 0.15).Unit
			local start = d.Position
			local t = (start.Y - S.floorY) / math.max(0.1, -dir.Y)
			local stop = start + dir * t
			local a0 = track(Instance.new("Attachment"))
			a0.Parent = d
			local holder = localPart("RayEnd", V3(0.2, 0.2, 0.2), CF(stop), WHITE, nil, { Transparency = 1 })
			local a1 = Instance.new("Attachment")
			a1.Parent = holder
			local beam = track(Instance.new("Beam"))
			beam.Name = "GodRay"
			beam.Attachment0, beam.Attachment1 = a0, a1
			beam.Width0, beam.Width1 = d.Size.Z * 0.9, d.Size.Z * 1.3
			beam.FaceCamera = true
			beam.Segments = 1
			beam.LightEmission = 0.6
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(rgb(255, 226, 170))
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.75, 0.93), NumberSequenceKeypoint.new(1, 1) })
			beam.Parent = d
			-- dust drifting in the shaft
			local len = (stop - start).Magnitude
			local shaft = localPart("DustShaft", V3(d.Size.Z * 0.8, d.Size.Y * 0.6, len), CFrame.lookAt((start + stop) / 2, stop), WHITE, nil, { Transparency = 1 })
			emitter(shaft, {
				Name = "Dust", Rate = 7, Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(0.05, 0.2), SpreadAngle = Vector2.new(180, 180),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0.05) }), Acceleration = V3(0, -0.02, 0),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) }),
				LightEmission = 0.6, Color = ColorSequence.new(rgb(255, 236, 200)), RotSpeed = NumberRange.new(-30, 30),
			})
		elseif d.Name == "GymTimer" and d:IsA("Model") then
			local box = d:FindFirstChild("TimerBox")
			local sg = box and box:FindFirstChildOfClass("SurfaceGui")
			if sg then
				S.gymTimer = { phase = sg:FindFirstChild("Phase"), time = sg:FindFirstChild("Time"), go = d:FindFirstChild("LampGo"), warn = d:FindFirstChild("LampWarn"), rest = d:FindFirstChild("LampRest") }
			end
		elseif d.Name == "Telemetry" and d:IsA("BasePart") then
			local sg = d:FindFirstChild("Screen")
			if sg then
				S.telemetry = {}
				for i = 1, 4 do
					S.telemetry[i] = sg:FindFirstChild("Val" .. i, true)
				end
			end
		end
	end
	S.punches = 0
end

local function setTimer(phaseText, timeText, lamp, color)
	local t = S.gymTimer
	if not t then
		return
	end
	if t.phase and phaseText then
		t.phase.Text = phaseText
	end
	if t.time and timeText then
		t.time.Text = timeText
		if color then
			t.time.TextColor3 = color
		end
	end
	for n, p in pairs({ go = t.go, warn = t.warn, rest = t.rest }) do
		if p then
			p.Transparency = (n == lamp) and 0 or 0.65
		end
	end
end

------------------------------------------------------------------------
-- Per-frame driver
------------------------------------------------------------------------
local acc30, acc10 = 0, 0
local function update(dt)
	if not S then
		return
	end
	if not S.arena.Parent then
		-- the server cleaned the arena up before FightClient got to Stop()
		VenueFX.Stop()
		return
	end
	local now = os.clock()
	S.excite = math.max(S.baseExcite, S.excite - dt * 0.3)
	S.supportBoost = math.max(0, S.supportBoost - dt * 0.4)
	step("ropes", updateRopes, dt, now)
	step("spots", updateSpots, dt, now)
	acc30 += dt
	if acc30 >= 1 / 30 then
		local d = acc30
		acc30 = 0
		step("lighting", updateLighting, d)
		step("crowd", updateCrowd, d, now)
		step("screens", updateScreens, d, now)
		step("broadcast", updateBroadcast, d, now)
	end
	acc10 += dt
	if acc10 >= 0.1 then
		local d = acc10
		acc10 = 0
		step("people", updatePeople, d, now)
		-- the referee's tag can replicate after Start: look again now and then
		if #S.referees == 0 and now >= (S.nextRefScan or 0) then
			S.nextRefScan = now + 2
			for _, r in ipairs(CollectionService:GetTagged("Referee")) do
				if r:IsDescendantOf(S.arena) then
					table.insert(S.referees, r)
				end
			end
		end
		-- crowd audio follows excitement
		if S.snd.roar then
			S.snd.roar.Volume = 0.05 + S.excite * 0.6
		end
		if S.snd.murmur then
			S.snd.murmur.Volume = 0.25 + (1 - S.excite) * 0.15
		end
	end
	if S.screenHold and now > S.screenHold and S.defaultScreen then
		S.screenHold = nil
		setScreens(S.defaultScreen, 0)
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function VenueFX.Start(arena, info)
	VenueFX.Stop()
	if typeof(arena) ~= "Instance" then
		error("VenueFX.Start: no arena")
	end
	info = type(info) == "table" and info or {}
	local anchors = arena:FindFirstChild("Anchors")
	local center = anchors and anchors:FindFirstChild("RingCenter")
	if not center then
		error("VenueFX.Start: arena has no Anchors.RingCenter")
	end
	local venue = (info.spar and "Gym") or info.venue or arena:GetAttribute("Venue") or "Arena"
	if not PROFILES[venue] then
		venue = arena:GetAttribute("Venue") or "Arena"
	end
	local floor = arena.PrimaryPart or arena:FindFirstChild("Floor")
	local folder = Instance.new("Folder")
	folder.Name = "VenueFX_Local"
	folder.Parent = workspace
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "VenueFXSounds"
	soundFolder.Parent = SoundService
	local stakes = {}
	for _, s in ipairs(type(info.stakes) == "table" and info.stakes or {}) do
		if type(s) == "string" then
			table.insert(stakes, s)
		end
	end
	S = {
		arena = arena, info = info, venue = venue, profile = PROFILES[venue] or PROFILES.Arena, spar = info.spar, stakes = stakes,
		center = center.Position, ringHalf = arena:GetAttribute("RingHalf") or 11,
		floorY = floor and (floor.Position.Y + floor.Size.Y / 2) or (center.Position.Y - 4),
		folder = folder, soundFolder = soundFolder, created = {}, dead = {}, snd = {},
		excite = 0.3, baseExcite = 0.3, supportBoost = 0, screenPop = 0, spotMode = "ring", house = {}, houseLamps = {}, bowlGuis = {},
		referees = {}, spots = {}, ropes = {}, ties = {}, fans = {}, phones = {}, flashes = {}, confetti = {}, gerbs = {}, fireworks = {},
		smoke = { Red = {}, Blue = {} }, co2 = { Red = {}, Blue = {} }, cams = {}, sources = {}, corner = {}, stools = {}, watchers = {},
		tickers = {}, flashFrames = {}, sweeps = {}, chase = { Red = {}, Blue = {} }, archLeds = { Red = {}, Blue = {} }, walkLights = {}, parCans = {},
		screens = { text = {}, red = {}, blue = {}, round = {}, clock = {}, header = {} }, entrance = { Red = {}, Blue = {} }, round = 1,
		crowdR = 30, crowdY = 4, punches = 0, bulkParts = {}, bulkCFs = {}, fanIdx = 0,
	}
	local ok, err = pcall(function()
		setupLighting()
		setPhaseLook("start")
		S.cur.house = S.tgt.house
		for _, r in ipairs(CollectionService:GetTagged("Referee")) do
			if r:IsDescendantOf(arena) then
				table.insert(S.referees, r)
			end
		end
		local hl = arena:FindFirstChild("HouseLights")
		if hl then
			for _, p in ipairs(hl:GetChildren()) do
				local l = p:FindFirstChildOfClass("PointLight")
				if l then
					table.insert(S.house, { light = l, base = l.Brightness })
				end
				if p:GetAttribute("Lamp") then
					table.insert(S.houseLamps, p)
				end
			end
		end
		-- the optional pieces: any of them may fail without stopping the rest
		for _, piece in ipairs({
			{ "ropes", setupRopes }, { "spots", setupSpots }, { "crowd", setupCrowd }, { "bowl", setupBowl }, { "particles", setupParticles },
			{ "screens", setupScreens }, { "people", setupPeople }, { "broadcast", setupBroadcast }, { "gym", setupGym },
		}) do
			step(piece[1], piece[2])
		end
		-- audio: crowd bed and reactions only with uploads; the bell has a built-in stand-in
		S.snd.murmur = mkSound("CrowdMurmur", soundId("CrowdMurmur"), 0.3, true)
		S.snd.roar = mkSound("CrowdRoar", soundId("CrowdRoar"), 0.1, true)
		S.snd.ooh = mkSound("CrowdOoh", soundId("CrowdOoh"), 0.6, false)
		S.snd.boo = mkSound("CrowdBoo", soundId("CrowdBoo"), 0.5, false)
		S.snd.bell = mkSound("RingBell", soundId("RingBell"), 0.9, false)
		S.snd.ping = mkSound("BellPing", builtin("Ping"), 0.55, false, 1.25)
		S.snd.clang = mkSound("BellClang", builtin("SwordHit"), 0.18, false, 1.6)
		S.snd.music = mkSound("ArenaMusic", soundId("ArenaMusic"), 0.3, true)
		S.snd.walkout = mkSound("WalkoutMusic", soundId("WalkoutMusic"), 0.6, true)
		S.snd.announcer = mkSound("Announcer", soundId("Announcer"), 0.9, false)
		S.snd.flash = mkSound("CameraFlash", soundId("CameraFlash"), 0.25, false)
		if not S.spar then
			for _, k in ipairs({ "murmur", "roar", "music" }) do
				if S.snd[k] then
					S.snd[k]:Play()
				end
			end
		end
	end)
	if not ok then
		-- leave nothing half-applied: FightClient falls back to its own effects
		VenueFX.Stop()
		error(err)
	end
	local tape = type(info.tape) == "table" and info.tape or {}
	local you, opp = tape.you or {}, tape.opp or {}
	S.defaultScreen = S.spar and "SPARRING" or (string.upper(you.name or "RED") .. "\nvs\n" .. string.upper(opp.name or "BLUE"))
	step("screens", setScreens, S.defaultScreen, 0)
	if S.spar then
		step("gym", setTimer, "SPARRING", "3:00", "go")
	end
	step("lighting", setWalkLights, nil)
	phones(S.venue == "Stadium" and 4 or 0)
	if conn then
		conn:Disconnect()
	end
	conn = RunService.Heartbeat:Connect(update)
	return true
end

function VenueFX.Phase(name, data)
	if not S then
		return
	end
	data = type(data) == "table" and data or {}
	local tape = type(S.info.tape) == "table" and S.info.tape or {}
	if name == "entrance" then
		local corner = data.who == "you" and "Red" or "Blue"
		local who = data.who == "you" and (tape.you or {}) or (tape.opp or {})
		S.focusModel = typeof(data.target) == "Instance" and data.target or (data.who == "you" and S.info.myModel or S.info.oppModel)
		S.walkCorner = corner
		S.spotMode = "walker"
		setPhaseLook("entrance")
		S.excite = math.max(S.excite, data.who == "you" and 0.9 or 0.65)
		if data.who == "you" then
			S.supportBoost = 0.8
		end
		step("walkout", walkoutFX, corner, true)
		step("lights", setWalkLights, corner)
		step("lights", setWash, "walk", corner)
		step("screens", setScreens, (who.nick and who.nick ~= "" and ('"' .. string.upper(who.nick) .. '"\n') or "") .. string.upper(who.name or ""), 9)
		ribbonText(string.upper(who.name or "") .. "   -   " .. recordText(who.record) .. "   -   ")
		phones(30)
		announcerMode(true)
		-- the stadium pyro arrives from FightClient (Pyro); other pyro venues fire their own
		if not data.pyro and S.arena:FindFirstChild("Pyro") then
			VenueFX.Pyro(corner == "Red" and "red" or "blue")
		end
		if data.who == "opp" and S.snd.walkout then
			if S.snd.music then
				S.snd.music:Pause()
			end
			play(S.snd.walkout, 0.6)
		elseif data.who == "you" and S.snd.walkout then
			-- FightClient plays the player's own entrance music
			S.snd.walkout:Stop()
		end
		if data.who == "opp" and S.snd.announcer then
			play(S.snd.announcer)
		end
		-- second CO2 blast when the boxer reaches the ring
		local sess = S
		task.delay(data.who == "you" and 5 or 4, function()
			if S == sess and S.walkCorner == corner then
				for _, pe in ipairs(S.co2[corner] or {}) do
					pe:Emit(60)
				end
				flashBurst(20)
			end
		end)
	elseif name == "round" then
		S.round = tonumber(data.n) or S.round
		S.walkCorner, S.chaseAll = nil, false
		S.spotMode = "ring"
		S.focusModel = nil
		setPhaseLook("round")
		cornerMode(false)
		announcerMode(false)
		phones(S.venue == "Stadium" and 3 or 0)
		step("lights", setWalkLights, nil)
		step("lights", setWash, "round")
		for _, l in ipairs(S.screens.round) do
			l.Text = "R" .. tostring(S.round)
		end
		ribbonText(nil)
		if S.snd.walkout then
			S.snd.walkout:Stop()
		end
		if S.snd.music then
			S.snd.music:Pause()
		end
		ringBell(1)
		step("screens", setScreens, "ROUND " .. tostring(S.round), 3)
		step("gym", setTimer, "ROUND " .. tostring(S.round), nil, "go", rgb(255, 60, 50))
		S.excite = math.max(S.excite, 0.55)
	elseif name == "rest" then
		setPhaseLook("rest")
		cornerMode(true)
		step("lights", setWash, "rest")
		step("screens", setScreens, "END OF ROUND " .. tostring(data.n or S.round), 6)
		step("gym", setTimer, "REST", "1:00", "rest", rgb(80, 200, 255))
		if S.snd.music then
			S.snd.music:Resume()
		end
		phones(S.venue == "Stadium" and 6 or 2)
	elseif name == "bell" then
		ringBell(3)
		S.excite = math.max(S.excite, 0.6)
	elseif name == "kd" then
		local target = typeof(data.target) == "Instance" and data.target or (data.who == "you" and S.info.myModel or S.info.oppModel)
		S.downModel = target
		S.spotMode = "downed"
		kick(0.35, -0.4, 0.18, 0.5)
		S.excite = 1
		if data.who ~= "you" then
			S.supportBoost = 1
		end
		flashBurst(70)
		ribbonFlash(RED, 2.5)
		ribbonText("KNOCKDOWN!   -   ")
		step("screens", setScreens, data.severity == "flash" and "FLASH KNOCKDOWN!" or "KNOCKDOWN!", 3)
		if S.snd.ooh then
			play(S.snd.ooh, 0.8)
		end
		local r = rootOf(target)
		if r then
			ropeImpulse(r.Position, 7)
			step("canvas", function()
				-- the knockdown leaves a sweat mark on the canvas
				local canvas = S.arena:FindFirstChild("Canvas")
				local col = canvas and canvas.Color:Lerp(Color3.new(), 0.3) or rgb(120, 120, 120)
				local y = S.center.Y + 0.03
				localPart("CanvasMark", V3(0.03, 2.4, 1.8), CF(r.Position.X, y, r.Position.Z) * CFrame.Angles(0, math.random() * 6.28, 0) * CFrame.Angles(0, 0, math.pi / 2), col, M.SmoothPlastic, { Transparency = 0.72, Shape = Enum.PartType.Cylinder })
			end)
		end
	elseif name == "count" then
		local n = tonumber(data.n) or 0
		step("screens", setScreens, tostring(n), 1.2)
		flashBurst(8)
		S.excite = math.max(S.excite, 0.85)
	elseif name == "getup" then
		S.spotMode = "ring"
		S.downModel = nil
		S.excite = 0.95
		flashBurst(25)
		ribbonText(nil)
		step("screens", setScreens, "BACK UP!", 2)
	elseif name == "tier" then
		local tier = tonumber(data.tier) or 0
		if tier >= 2 then
			S.excite = math.max(S.excite, 0.85)
			ribbonFlash(GOLD, 1)
			if data.who ~= "you" then
				S.supportBoost = 0.6
			end
		end
	elseif name == "final" then
		local result = data.result == "win" and "win" or (data.result == "loss" and "loss" or "draw")
		setPhaseLook(result)
		S.winModel = result == "win" and S.info.myModel or (result == "loss" and S.info.oppModel or nil)
		S.spotMode = S.winModel and "winner" or "sweep"
		S.chaseAll = true
		S.walkCorner = nil
		S.excite = 1
		S.supportBoost = result == "win" and 1 or 0
		ringBell(5)
		flashBurst(120)
		phones(35)
		step("lights", setWash, result == "draw" and "round" or result)
		ribbonFlash(result == "win" and GOLD or (result == "loss" and BLUE or WHITE), 6)
		local tape2 = type(S.info.tape) == "table" and S.info.tape or {}
		local winner = result == "win" and (tape2.you or {}).name or (result == "loss" and (tape2.opp or {}).name or nil)
		ribbonText(winner and ("WINNER   -   " .. string.upper(winner) .. "   -   " .. tostring(data.method or "") .. "   -   ") or "DRAW   -   ")
		if not S.spar then
			if result ~= "draw" then
				local sess = S
				task.delay(1.2, function()
					if S == sess then
						confettiBurst()
					end
				end)
			end
			if #S.gerbs > 0 and result ~= "draw" then
				gerbs(3)
			end
			if result == "win" then
				fireworks(#S.stakes > 0 and 10 or 6)
			end
			if result == "loss" and S.snd.boo then
				play(S.snd.boo, 0.4)
			end
		end
		step("gym", setTimer, "TIME", "0:00", "warn", rgb(255, 200, 40))
	end
end

function VenueFX.Hit(data)
	if not S or type(data) ~= "table" then
		return
	end
	local r = rootOf(data.target)
	if data.target == S.info.oppModel then
		S.punches += 1
	end
	local heavy = data.heavy == true
	local dmg = tonumber(data.dmg) or 0
	if data.punch == "ropes" then
		if r then
			ropeImpulse(r.Position, 9)
		end
		S.excite = math.max(S.excite, 0.75)
		return
	end
	if r then
		ropeImpulse(r.Position, heavy and 4.5 or 1.6)
	end
	S.excite = math.min(1, S.excite + (heavy and 0.22 or 0.05) + dmg * 0.01)
	if heavy then
		flashBurst(12)
		kick(0.06, 0, 0.04, 0.12)
		if S.snd.ooh and dmg >= 6 then
			play(S.snd.ooh, 0.45 + math.min(0.4, dmg * 0.03))
		end
		if data.target == S.info.oppModel then
			S.supportBoost = math.max(S.supportBoost, 0.5)
		end
	end
end

function VenueFX.State(msg)
	if not S or type(msg) ~= "table" then
		return
	end
	local secs = math.max(0, math.floor(tonumber(msg.time) or 0))
	local text = string.format("%d:%02d", secs // 60, secs % 60)
	for _, l in ipairs(S.screens.clock) do
		l.Text = text
	end
	if S.gymTimer and S.look ~= PHASES.rest then
		setTimer(nil, text, secs <= 10 and "warn" or "go", secs <= 10 and rgb(255, 200, 40) or rgb(255, 60, 50))
	end
	local tel = S.telemetry
	local me = type(msg.me) == "table" and msg.me or nil
	if tel and me then
		local function pct(a, b)
			return string.format("%d%%", math.floor(math.clamp((tonumber(a) or 0) / math.max(1, tonumber(b) or 100), 0, 1) * 100 + 0.5))
		end
		if tel[1] then
			tel[1].Text = tostring(S.punches)
		end
		if tel[2] then
			tel[2].Text = pct(me.hp, 100)
		end
		if tel[3] then
			tel[3].Text = pct(me.body, 100)
		end
		if tel[4] then
			tel[4].Text = pct(me.stam, me.max)
		end
	end
end

function VenueFX.Screens(text)
	if not S then
		return
	end
	step("screens", setScreens, tostring(text or ""), 5)
end

function VenueFX.Cheer(amount)
	if not S then
		return
	end
	local a = math.clamp(tonumber(amount) or 0, 0, 1)
	S.excite = math.max(S.excite, a)
	if a > 0.8 then
		flashBurst(math.floor(a * 30))
	end
end

function VenueFX.Pyro(side)
	if not S then
		return
	end
	local folder = S.arena:FindFirstChild("Pyro")
	local want = side == "red" and "PyroRed" or "PyroBlue"
	if folder then
		for _, p in ipairs(folder:GetChildren()) do
			if p.Name == want then
				local pe = p:FindFirstChildOfClass("ParticleEmitter")
				if pe then
					pe.Enabled = true
					task.delay(1.6, function()
						if pe.Parent then
							pe.Enabled = false
						end
					end)
				end
				-- the blast lights the room for a moment
				local l = track(Instance.new("PointLight"))
				l.Color = rgb(255, 170, 80)
				l.Range = 40
				l.Brightness = 5
				l.Parent = p
				task.delay(0.9, function()
					l:Destroy()
				end)
			end
		end
	end
	kick(0.05, 0.05, 0.12, 0.35)
	S.excite = math.max(S.excite, 0.9)
	S.spotMode = S.spotMode == "ring" and "sweep" or S.spotMode
end

-- on-air camera for FightClient's broadcast cuts: cycles tripods, jib and skycam, lights its tally
function VenueFX.BroadcastCFrame(now)
	if not S or #S.sources == 0 then
		return nil
	end
	S.srcIdx = S.srcIdx % #S.sources + 1
	local src = S.sources[S.srcIdx]
	local focus = focusPoint()
	local pos
	if src.kind == "cam" then
		-- tighter than the tripod itself (a long lens), and just above the top rope
		pos = src.e.pos:Lerp(focus, 0.3) + V3(0, 0.8, 0)
	elseif src.kind == "jib" then
		pos = src.e.head and src.e.head.Position or nil
	elseif src.kind == "sky" then
		pos = src.e.p.Position
	end
	if not pos then
		return nil
	end
	S.onAir = src.e
	return CFrame.lookAt(pos, focus)
end

function VenueFX.Stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if not S then
		return
	end
	pcall(restoreLighting)
	for _, s in pairs(S.snd) do
		pcall(function()
			s:Stop()
		end)
	end
	for _, inst in ipairs(S.created) do
		pcall(function()
			inst:Destroy()
		end)
	end
	-- the arena is usually gone already; if not, put the people we moved back where they were
	pcall(function()
		for _, e in ipairs(S.corner) do
			if e.m.Parent then
				e.m:PivotTo(e.home)
			end
		end
		for _, st in ipairs(S.stools) do
			if st.m.Parent then
				st.m:PivotTo(st.home)
			end
		end
		if S.announcer and S.announcer.m.Parent then
			S.announcer.m:PivotTo(S.announcer.home)
		end
	end)
	pcall(function()
		S.folder:Destroy()
		S.soundFolder:Destroy()
	end)
	S = nil
end

-- a respawn mid-fight must never leave the venue grade on the gym
player.CharacterAdded:Connect(function()
	if S then
		VenueFX.Stop()
	end
end)

return VenueFX
