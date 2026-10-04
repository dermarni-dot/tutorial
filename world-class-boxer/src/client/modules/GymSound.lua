-- GymSound: every gym sound effect on the client, played from ONE pool of positional sounds
-- (no Instance.new per hit: members punching bags every half second would spam instances).
-- Only the 12 built-in Roblox sounds are guaranteed (Config.BuiltinSounds), so each effect is a
-- "shaped" built-in: pitch, volume and a SoundGroup with EQ / reverb / distortion turn the same
-- landing thud into a muffled canvas bag, a slapping leather bag, a deep body shot or a glove pop,
-- and the metallic sword hit into a chain jingle, a plate clank or the round bell.
-- An uploaded asset in Config.SoundIds (BagThud, BagChain, SpeedBag, PunchImpact, BodyShot,
-- RingBell, CoachShout ...) replaces the shaped built-in when it is set; empty ids are skipped.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local GymSound = {}

local S = Config.BuiltinSounds or {}
local THUD = S.Thud or "rbxasset://sounds/action_jump_land.mp3"
local METAL = S.SwordHit or "rbxasset://sounds/swordhit.wav"
local WHOOSH = S.SwordLunge or "rbxasset://sounds/swordlunge.wav"
local PING = S.Ping or "rbxasset://sounds/electronicpingshort.wav"
local STEPS = S.Footsteps or "rbxasset://sounds/action_footsteps_plastic.mp3"
local SPLASH = S.Splash or "rbxasset://sounds/impact_water.mp3"
local CLICK = S.Click or "rbxasset://sounds/clickfast.wav"
local GRUNT = S.Grunt or "rbxasset://sounds/uuhhh.mp3"
local FALL = S.Falling or "rbxasset://sounds/action_falling.ogg"

------------------------------------------------------------------------
-- Sound groups (mix buses). Each is created once under SoundService and reused.
------------------------------------------------------------------------
local GROUPS = {
	-- muffled, boomy: an old canvas bag stuffed with rags
	GymBagSoft = { volume = 1, eq = { 5, -3, -16 }, distort = 0.05 },
	-- leather slap with a short room tail
	GymBag = { volume = 1, eq = { 3, 0, -4 }, reverb = { 0.35, 0.18, -6 } },
	-- deep body shots / slams
	GymHeavy = { volume = 1, eq = { 7, -2, -10 } },
	-- chains, plates, bells: low cut so they ring instead of thump
	GymMetal = { volume = 0.9, eq = { -14, 0, 2 }, reverb = { 0.9, 0.25, -4 } },
	GymBell = { volume = 1, eq = { -10, 2, 0 }, reverb = { 1.6, 0.35, -2 } },
	-- quiet background bed (machines, footfalls, distant work)
	GymBed = { volume = 0.8, eq = { 2, -4, -12 } },
	-- crisp UI-ish clicks and smart-screen pings
	GymTech = { volume = 0.8, eq = { -8, 0, 0 } },
}

local groups = {}
local function group(name)
	local g = groups[name]
	if g and g.Parent then
		return g
	end
	g = SoundService:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		local def = GROUPS[name] or {}
		g.Volume = def.volume or 1
		pcall(function()
			if def.eq then
				local eq = Instance.new("EqualizerSoundEffect")
				eq.LowGain, eq.MidGain, eq.HighGain = def.eq[1], def.eq[2], def.eq[3]
				eq.Parent = g
			end
			if def.reverb then
				local rv = Instance.new("ReverbSoundEffect")
				rv.DecayTime = def.reverb[1]
				rv.WetLevel = def.reverb[3]
				rv.DryLevel = 0
				rv.Density = 1
				rv.Diffusion = 1
				rv.Parent = g
			end
			if def.distort then
				local d = Instance.new("DistortionSoundEffect")
				d.Level = def.distort
				d.Parent = g
			end
		end)
		g.Parent = SoundService
	end
	groups[name] = g
	return g
end

------------------------------------------------------------------------
-- Effect profiles: id, group, base speed / volume and random spread.
-- key = Config.SoundIds key that replaces the built-in when set.
------------------------------------------------------------------------
local P = {
	bag_canvas = { id = THUD, group = "GymBagSoft", speed = 0.78, vol = 0.55, spread = 0.08, key = "BagThud" },
	bag_leather = { id = THUD, group = "GymBag", speed = 1.08, vol = 0.55, spread = 0.07, key = "BagThud" },
	bag_premium = { id = THUD, group = "GymBag", speed = 0.96, vol = 0.6, spread = 0.05, key = "BagThud" },
	bag_body = { id = THUD, group = "GymHeavy", speed = 0.82, vol = 0.6, spread = 0.06, key = "BodyShot" },
	bag_smartping = { id = PING, group = "GymTech", speed = 1.35, vol = 0.12, spread = 0.03 },
	chain = { id = METAL, group = "GymMetal", speed = 1.9, vol = 0.07, spread = 0.25, key = "BagChain" },
	speedbag = { id = THUD, group = "GymBag", speed = 2.4, vol = 0.32, spread = 0.12, key = "SpeedBag" },
	doubleend = { id = THUD, group = "GymBag", speed = 1.85, vol = 0.36, spread = 0.08 },
	glove = { id = THUD, group = "GymBag", speed = 1.6, vol = 0.38, spread = 0.12, key = "PunchImpact" },
	whoosh = { id = WHOOSH, group = "GymBed", speed = 1.3, vol = 0.05, spread = 0.2 },
	plate = { id = METAL, group = "GymMetal", speed = 0.82, vol = 0.12, spread = 0.12 },
	rack = { id = METAL, group = "GymMetal", speed = 1.15, vol = 0.08, spread = 0.15 },
	slam = { id = THUD, group = "GymHeavy", speed = 0.62, vol = 0.75, spread = 0.05 },
	ballcatch = { id = THUD, group = "GymBag", speed = 1.25, vol = 0.3, spread = 0.1 },
	footfall = { id = STEPS, group = "GymBed", speed = 1.0, vol = 0.12, spread = 0.1 },
	ropetick = { id = CLICK, group = "GymBed", speed = 0.75, vol = 0.1, spread = 0.1 },
	bell = { id = METAL, group = "GymBell", speed = 0.62, vol = 0.35, spread = 0.01, key = "RingBell" },
	ping = { id = PING, group = "GymTech", speed = 1.0, vol = 0.25, spread = 0.02 },
	reveal = { id = PING, group = "GymBell", speed = 0.8, vol = 0.4, spread = 0 },
	splash = { id = SPLASH, group = "GymBed", speed = 1.2, vol = 0.18, spread = 0.1 },
	drip = { id = SPLASH, group = "GymBed", speed = 2.6, vol = 0.06, spread = 0.2 },
	grunt = { id = GRUNT, group = "GymBed", speed = 1.0, vol = 0.12, spread = 0.12 },
	drop = { id = FALL, group = "GymHeavy", speed = 1.6, vol = 0.12, spread = 0.1 },
	shout = { id = nil, group = "GymBed", speed = 1, vol = 0.5, spread = 0.06, key = "CoachShout" },
	-- unshaped: callers give the id / speed / volume themselves (GymVisuals.Sound)
	raw = { id = THUD, group = "GymBag", speed = 1, vol = 1, spread = 0 },
}
GymSound.Profiles = P

------------------------------------------------------------------------
-- The pool: N Attachment+Sound pairs parked under the Terrain, reused round robin.
------------------------------------------------------------------------
local POOL_SIZE = 28
local pool = {}
local nextIndex = 1

local function ensurePool()
	if pool[1] and pool[1].att.Parent then
		return
	end
	pool = {}
	for i = 1, POOL_SIZE do
		local att = Instance.new("Attachment")
		att.Name = "GymSFX" .. i
		local snd = Instance.new("Sound")
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 6
		snd.RollOffMaxDistance = 90
		snd.Parent = att
		-- attachments must live in a BasePart: the Terrain is one that never moves
		att.Parent = workspace.Terrain
		pool[i] = { att = att, snd = snd }
	end
end

-- returns the next pooled voice that is not still playing (or the oldest one)
local function voice()
	ensurePool()
	for _ = 1, POOL_SIZE do
		local e = pool[nextIndex]
		nextIndex = nextIndex % POOL_SIZE + 1
		if not e.snd.IsPlaying then
			return e
		end
	end
	local e = pool[nextIndex]
	nextIndex = nextIndex % POOL_SIZE + 1
	return e
end

-- play effect `name` at world position `pos`. opts = { volume = x (multiplier), speed = x
-- (multiplier), id = override SoundId, maxDistance = studs }
function GymSound.Play(name, pos, opts)
	local prof = P[name]
	if not prof or typeof(pos) ~= "Vector3" then
		return nil
	end
	opts = opts or {}
	local id = opts.id or (prof.key and Config.SoundId and Config.SoundId(prof.key)) or prof.id
	if not id then
		return nil -- optional voice line with no upload: stay silent
	end
	local uploaded = prof.key and id ~= prof.id
	local e = voice()
	local ok = pcall(function()
		e.att.WorldPosition = pos
		local snd = e.snd
		snd:Stop()
		snd.SoundId = id
		local spread = prof.spread or 0
		-- an uploaded asset is already the right sound: play it nearly unshaped
		local speed = uploaded and (1 + (math.random() - 0.5) * 0.06) or (prof.speed * (1 + (math.random() * 2 - 1) * spread))
		snd.PlaybackSpeed = math.max(0.1, speed * (opts.speed or 1))
		snd.Volume = math.clamp(prof.vol * (opts.volume or 1), 0, 3)
		snd.RollOffMaxDistance = opts.maxDistance or 90
		snd.SoundGroup = group(prof.group)
		snd.TimePosition = 0
		snd:Play()
	end)
	return ok and e.snd or nil
end

-- a quick burst of the same effect (speed bag rattle: 3 hits 40 ms apart)
function GymSound.Burst(name, pos, n, gap, opts)
	for i = 0, (n or 3) - 1 do
		task.delay(i * (gap or 0.04), function()
			local o = table.clone(opts or {})
			o.volume = (o.volume or 1) * (1 - i * 0.22)
			GymSound.Play(name, pos, o)
		end)
	end
end

-- a long looping bed sound parented to a part (machine hum, gym music). Not pooled: there are
-- only a handful and they live as long as the gym does.
function GymSound.Loop(parentPart, id, volume, speed, groupName)
	if not (parentPart and id) then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = "GymLoop"
	snd.SoundId = id
	snd.Looped = true
	snd.Volume = volume or 0.1
	snd.PlaybackSpeed = speed or 1
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 10
	snd.RollOffMaxDistance = 80
	pcall(function()
		snd.SoundGroup = group(groupName or "GymBed")
	end)
	snd.Parent = parentPart
	pcall(function()
		snd:Play()
	end)
	return snd
end

function GymSound.Group(name)
	return group(name)
end

return GymSound
