-- FightEngine: server-authoritative real-time boxing.
-- Punches: jab, cross, lead hook, rear hook, uppercut, overhand (+ body shots).
-- Defense: block, parry, slip, roll, pivot, clinch. Counters, combos, stamina,
-- knockdowns + 10 count, KO/TKO, referee & doctor stoppages, visible face damage,
-- sweat, robes & mouthguards, venues, live commentary, three-judge scoring.
-- Also runs gym sparring sessions (Light / Medium / Hard).
-- Health model (CONTRACTS section 8): F.health IS head HP (tiers via Config.HeadTier: conscious /
-- dazed / severe danger / out on his feet), F.body is body HP, F.stamina with a cap that body damage
-- and the rounds erode. Knockdown odds per landed head shot come from Config.KOChance (chin,
-- conditioning, stamina, power, clean accuracy, previous damage); flash / normal / heavy / out-cold
-- knockdowns, stumbles and balance loss, concussion that slows, blurs and recovers, a mandatory
-- eight count with a referee check, and a referee NPC who moves, counts and waves it off.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Builder = require(Shared:WaitForChild("Builder"))
local Officials = require(Shared:WaitForChild("Officials"))
-- the tournaments' belts and the celebration cutscene's beats (Shared.Tournaments / Shared.BeltModel): optional
local Tournaments, BeltModel
do
	local okT, modT = pcall(function()
		return require(Shared:WaitForChild("Tournaments", 5))
	end)
	Tournaments = okT and type(modT) == "table" and modT or nil
	local okB, modB = pcall(function()
		return require(Shared:WaitForChild("BeltModel", 5))
	end)
	BeltModel = okB and type(modB) == "table" and modB or nil
end
-- R-anim: how fighters go down (DownPose / DownDir / DownDist / KOKind), nil-safe if missing
local FightMotion
do
	local fm = Shared:FindFirstChild("FightMotion")
	if fm then
		local ok, mod = pcall(require, fm)
		FightMotion = ok and mod or nil
	end
end
-- special moves (Moves.lua: data + unlocks), nil-safe if the module is missing
local Moves
do
	local mm = Shared:FindFirstChild("Moves")
	if mm then
		local ok, mod = pcall(require, mm)
		Moves = ok and mod or nil
	end
end
-- the first-time tutorial fight's steps and rules (Tutorial.lua), nil-safe if missing
local Tutorial
do
	local tm = Shared:FindFirstChild("Tutorial")
	if tm then
		local ok, mod = pcall(require, tm)
		Tutorial = ok and type(mod) == "table" and mod or nil
	end
end
-- combinations (the chain window, named combos, their rules) and the dodges (evade windows by punch type)
local Combos = require(Shared:WaitForChild("Combos"))
local Evasion = require(Shared:WaitForChild("Evasion"))
-- the AI boxers' ring traits (resistances, scouting) and the player's fighting type
local Traits = require(Shared:WaitForChild("Traits"))
-- reach and hit volumes from the live rigs (Shared.HitGeometry: the client's prediction runs the same code);
-- optional: without it the ranges fall back to the old tape-based numbers
local HitGeometry
do
	local hg = Shared:FindFirstChild("HitGeometry")
	if hg then
		local ok, mod = pcall(require, hg)
		HitGeometry = ok and type(mod) == "table" and mod or nil
	end
end
local FightAI = require(script.Parent.FightAI)
local Career = require(script.Parent.Career)
-- [Entrance] the ring-walk cinematic's beats (RingWalk + Shared.Entrance): optional, the old walkout runs without it
local RingWalk
do
	local okR, modR = pcall(require, script.Parent:FindFirstChild("RingWalk"))
	RingWalk = okR and type(modR) == "table" and modR or nil
end
-- fight spacing (FightMotion.Spacing; the round-1 numbers if that module is missing)
local SPACING = FightMotion and FightMotion.Spacing
	or { base = 3.5, min = 2.85, minSep = 2.6, inside = 3, clinch = 4.4, pivot = 3.2, cover = 5 }

local FightEngine = {}
FightEngine.Active = {} -- player -> fight
local Fight = {}
Fight.__index = Fight

-- how hard head shots land overall (lower = longer fights). 0.55 before the per-punch head
-- multipliers (Config.Punches[p].head, jab 0.65 .. uppercut 1.55) existed; 0.48 keeps the average
-- head damage per round about where it was while hooks and uppercuts now hurt far more than jabs.
local HEAD_SCALE = 0.48
FightEngine.HEAD_SCALE = HEAD_SCALE

-- Head HP model: part of every head shot is "stun" that clears when the fighter gets a breather (a few
-- seconds without eating a head shot, a clinch, the corner); the rest is damage that stays all fight.
-- Recovery buys a bigger recoverable share. (The old flat regen gave back almost everything, so the
-- head tiers were never reached.)
local STUN_SHARE, STUN_PER_RECOVERY = 0.15, 0.002 -- share of head damage that is recoverable stun
local STUN_CLEAR, STUN_CLEAR_PER_RECOVERY = 0.5, 0.01 -- stun cleared per second once quiet
local STUN_QUIET = 2.5 -- seconds without a landed head shot before it starts to clear

local KO = Config.KO
local CONC = Config.Concussion
local FACE = Config.FaceDamage
local DEPTH = Config.FightDepth

-- work = how busy the gym partner is (FightAI multiplies its punch rate; a fight-night opponent is 1)
-- and range = how close he stays (a share of his normal distance). A sparring partner's job is to give
-- you rounds: at the old fight-night pace he threw ~5 punches in a Light round and never won a spar.
local SPAR = {
	Light = { rounds = 1, damage = 0.3, allowKD = false, work = 2.0, range = 0.86 },
	Medium = { rounds = 2, damage = 0.55, allowKD = false, work = 2.4, range = 0.84 },
	Hard = { rounds = 3, damage = 0.85, allowKD = true, work = 2.2, range = 0.82 },
	-- PvP sparring between two players: headgear, lighter shots, no knockdowns (the coach calls time)
	PvP = { rounds = 2, damage = 0.5, allowKD = false },
}
FightEngine.SparSettings = SPAR

-- every numeric field of the face damage table (CONTRACTS section 8); nose is a bool, cutSide/cutSide2 are -1|1
local DMG_FIELDS = { "leftEye", "rightEye", "cut", "cut2", "noseBleed", "bruise", "lip", "cheekL", "cheekR", "forehead", "earL", "earR", "redness", "ribsL", "ribsR" }
local DMG_CAP = { cut = 1.2, cut2 = 1.2 }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, fallback)
	if v.Magnitude > 0.05 then
		return v.Unit
	end
	return fallback
end

-- how high a character's root stands above the floor: its own rig's hip height + half the root (the
-- classic rig's 2 + 1, but the athletic rigs stand 3.2-4.7). Placing at a fixed 3.2 put tall boxers' feet
-- inside the canvas and the Humanoid sprang them up (a pop, and a jump the Animator read as root motion)
local function standHeight(hum, root)
	-- (an R6 rig reports HipHeight 0: its legs hold it at the classic 3)
	if hum and root and hum.HipHeight > 0.5 then
		return hum.HipHeight + root.Size.Y / 2 + 0.05
	end
	return 3.2
end
FightEngine.StandHeight = standHeight

-- the rig's size against the classic R15 the fight spacing was fitted on (FightMotion.RigFactor) and its
-- standing height (studs, sole to crown; the server sees the rig in its rest pose)
local function rigSize(model, hum, root)
	local ut = model and model:FindFirstChild("UpperTorso")
	local k = 1
	if ut and ut:IsA("BasePart") and FightMotion and FightMotion.RigFactor then
		local depth = nil
		local nv = hum and hum:FindFirstChild("BodyDepthScale")
		if nv and nv:IsA("NumberValue") then
			depth = nv.Value
		elseif hum then
			local ok, desc = pcall(function()
				return hum:GetAppliedDescription()
			end)
			depth = ok and desc and desc.DepthScale or nil
		end
		k = FightMotion.RigFactor(ut.Size.Z, depth)
	end
	local head = model and model:FindFirstChild("Head")
	local height = nil
	if head and head:IsA("BasePart") and root then
		height = standHeight(hum, root) + (head.Position.Y + head.Size.Y / 2 - root.Position.Y)
	end
	return k, height
end

-- a fighter's body as the hit detection sees it (HitGeometry frame): off the rig's parts when it has them, else
-- from Builder.Scales of his app and the tale of the tape (the headless sims' stub rigs, an old record)
local function geoFrame(F)
	if not HitGeometry then
		return nil
	end
	local data = F.data or {}
	local app = type(data.app) == "table" and table.clone(data.app) or { gender = 1 }
	app.height = tonumber(data.height) or app.height or 70
	local ok, sc = pcall(Builder.Scales, app, data.build, nil)
	local fallback = HitGeometry.FrameFromScales(ok and sc or nil, { height = app.height, reach = tonumber(data.reach), female = app.gender == 2 })
	local root = F.root
	local soleY = root and root.Position and (root.Position.Y - standHeight(F.hum, root)) or nil
	local okF, frame = pcall(HitGeometry.Frame, F.model, soleY, fallback)
	return okF and frame or fallback
end

-- server attributes are change-only (CONTRACTS ground rules)
local function setAttr(inst, k, v)
	if inst and inst:GetAttribute(k) ~= v then
		inst:SetAttribute(k, v)
	end
end

local function his(F)
	return (type(F.data.app) == "table" and F.data.app.gender == 2) and "her" or "his"
end

local function quant(v, step)
	return math.floor(v / step + 0.5) * step
end

-- slides a fighter by `delta` studs: the root's CFrame carries the whole welded rig (one assembly move),
-- where Model:PivotTo walks the ~270-part model and moves every part (60% of a spar's server Lua)
local function shift(F, delta)
	F.root.CFrame += delta
end

local function newDamage(seed, mul)
	local d = { cutSide = 1, cutSide2 = -1, nose = false, age = 0 }
	for _, k in ipairs(DMG_FIELDS) do
		d[k] = 0
	end
	if type(seed) == "table" then
		-- a fight starts from the residual of earlier fights: swelling and half-healed cuts open up quicker
		for _, k in ipairs(DMG_FIELDS) do
			local v = tonumber(seed[k])
			if v then
				d[k] = math.clamp(v * mul, 0, DMG_CAP[k] or 1)
			end
		end
		d.nose = seed.nose == true
		if seed.cutSide == -1 or seed.cutSide == 1 then
			d.cutSide = seed.cutSide
		end
		if seed.cutSide2 == -1 or seed.cutSide2 == 1 then
			d.cutSide2 = seed.cutSide2
		end
	end
	return d
end

local function cloneDamage(d)
	local c = table.clone(d)
	c.age = 0
	return c
end

------------------------------------------------------------------------
-- Fighter setup
------------------------------------------------------------------------
local MENTAL_DEFAULTS = { "Confidence", "Discipline", "Aggression", "Focus", "Composure" }

-- an AI boxer's signature combos (Combos.ForAI): its tier as Moves.ForAI reads it (an overall of 55 is a Local
-- Pro, 65 Regional, 75 Top 10, 85 a champion) and its record
local function aiSignatures(data)
	local tier = tonumber(data.tier)
	if not tier then
		local ov = Config.Overall(data.stats)
		tier = ov >= 85 and 8 or (ov >= 75 and 6 or (ov >= 65 and 4 or (ov >= 55 and 2 or 1)))
	end
	return Combos.ForAI(tier, type(data.record) == "table" and data.record or nil)
end

local function makeFighter(data, model, player)
	data.stats = type(data.stats) == "table" and data.stats or {}
	data.mental = type(data.mental) == "table" and data.mental or {}
	local s = data.stats
	for _, k in ipairs(Config.StatKeys) do
		if type(s[k]) ~= "number" then
			s[k] = 50
		end
	end
	for _, k in ipairs(MENTAL_DEFAULTS) do
		if type(data.mental[k]) ~= "number" then
			data.mental[k] = 50
		end
	end
	data.class = tonumber(data.class) or 5
	local style = Config.FindById(Config.Styles, data.style) or Config.Styles[4]
	local mods = data.mods or {}
	-- AI boxers carry the raw Training.FightModifiersFromBuild output: fold the neck's chin bonus in
	-- here (once). The player's Training.FightModifiers already added it through mods.stats.Chin, which
	-- Career.FighterFromProfile applied to the stats.
	-- (the level the ring traits scale with: the overall the world and the offer card show, before the chin fold)
	local overall = Config.Overall(s)
	if data.isPlayer ~= true and type(mods.chinAdd) == "number" and not data.chinApplied then
		data.chinApplied = true
		s.Chin = math.clamp(s.Chin + mods.chinAdd, 10, Config.StatCap)
	end
	local maxStam = (100 + (s.Stamina - 50) * 0.8) * (mods.staminaMul or 1)
	local fatigueFactor = 1 - math.max(0, (data.fatigue or 0) - 50) / 150
	-- career head trauma and an unhealed concussion mean the fighter walks in already "shaky"
	local conc = (tonumber(data.trauma) or 0) * CONC.startFromTrauma + (data.concussed and CONC.activeInjury or 0)
	conc = math.clamp(conc, 0, 0.6)
	local F = {
		data = data, model = model, player = player, isPlayer = player ~= nil,
		hum = model:FindFirstChildOfClass("Humanoid"), root = model:FindFirstChild("HumanoidRootPart"),
		style = style, classScale = 0.85 + (data.class - 1) * 0.045,
		powerMul = mods.powerMul or 1, speedMul = mods.speedMul or 1, moveMul = mods.moveMul or 1,
		maxStam = maxStam, stamCap = maxStam, stamina = maxStam * fatigueFactor, stamErosion = 0,
		health = 100, healthCap = 100, body = 100, bodyCap = 100,
		tier = 0, stun = 0, conc = conc, concPeak = conc, balance = 100, strain = 0, downSeverity = nil,
		state = "idle", blocking = false, busyUntil = 0,
		slipUntil = 0, rollUntil = 0, parryUntil = 0, pivotEvadeUntil = 0, angleUntil = 0, nextPivot = 0,
		counterUntil = 0, hurtUntil = 0, clinchUntil = 0, nextClinch = 0, lastPunch = 0, combo = 0, hand = "R",
		stumbleUntil = 0, stumbleVel = nil, stumbleSpeed = 0, stumbles = 0, lastHitAt = -10, lastBodyHitAt = -10, headTaken = 0,
		kdRound = 0, kdTotal = 0, mash = 0, actId = 0, recentHits = {}, damageDealt = 0, damageTaken = 0,
		dmg = newDamage(data.face, FACE.seedFromResidual),
		tally = { landed = 0, power = 0, body = 0, thrown = 0, kd = 0, clinches = 0 },
		totals = { landed = 0, thrown = 0, power = 0, body = 0 },
		punchesUsed = { jab = 0, cross = 0, leadhook = 0, rearhook = 0, uppercut = 0, overhand = 0 },
		-- special moves: the unlocked set (Main computes the player's from the profile; an AI boxer gets its
		-- style's), the running move, its set-up's evade window and its cooldown
		moves = type(data.moves) == "table" and data.moves or (Moves and player == nil and Moves.ForAI(data)) or {},
		special = nil, specialToken = 0, nextSpecial = 0, shellUntil = 0, shellKind = nil, shellHit = false, specialsUsed = 0,
		lungeUntil = 0, lungeVel = nil,
		-- combinations (Combos): the running chain, the buffered press, the signature combos owned (Main computes the
		-- player's from the profile, an AI boxer's come from its tier and record), the fight's combo stats
		chain = nil, buffered = false, comboStats = Combos.NewStats(),
		sigs = type(data.sigs) == "table" and data.sigs or (player == nil and aiSignatures(data)) or {},
		-- the dodges (Evasion): the one running, its evade window and its end (after the window and before the end a
		-- punch CATCHES him), and the last defence's start / cost (a new dodge may cancel it: the pad's chords)
		dodgeKind = nil, dodgeUntil = 0, dodgeEnd = 0, defAt = -10, defCost = 0, defCancelled = false, dodges = 0, evades = 0,
		-- console aim assist level from the saved settings (0 off, 1 low, 2 high); the device the server holds
		-- the fighter on ("kbd" until a rate-limited device message says pad), when it switched, how often it
		-- switched lately, when the last input of each device arrived and when the server last saw the
		-- analog stick in Humanoid.MoveDirection (Fight:AssistBonus)
		assist = math.clamp(math.floor(tonumber(data.assist) or 0), 0, 2), padAt = -10, kbdAt = -10, assistNext = 0,
		device = "kbd", deviceAt = -10, deviceSwitches = 0, deviceWindow = -100, assistLockUntil = 0, analogAt = -100, moveSeen = false,
		-- the deeper fight (Config.FightDepth): the feint (when, the bite's opening, the recent ones), the second
		-- wind (left, running until, time spent gassed), the punches of the last seconds (pressure), being walked
		-- down / on the ropes, a raw AI's dropped hands, the slip's side, the clinch's inside work, the stats of
		-- the fighting type (Traits.FightingType)
		feintAt = -10, feintOpenUntil = 0, feintTimes = {}, feints = 0, feintBites = 0,
		windLeft = ((s.Stamina >= 75 or (data.mental.Discipline or 50) >= 80) and 2 or 1), windUntil = 0, gassedFor = 0, winds = 0,
		throwTimes = {}, pressured = false, onRopes = false, guardDropUntil = 0, slipDir = 0,
		clinchHits = 0, clinchNext = 0, clinchAt = 0,
		typeStats = { thrown = 0, body = 0, heavy = 0, counters = 0, landed = 0, pressT = 0, liveT = 0 },
		-- the ring traits (Shared.Traits): every AI boxer's from his seed, style and level (traitsAll); the fight
		-- switches them on (traits) only for a career bout; traitSeen = the ones revealed / hinted so far
		traitsAll = (player == nil and data.isPlayer ~= true) and Traits.ForBoxer({ id = data.id, style = data.style, archetype = data.archetype, overall = overall }) or {},
		traits = {}, traitSeen = {}, traitHints = {},
	}
	-- what the fighter walked in with, so the result reports only what happened in THIS fight
	-- (an old, healing broken nose or half-closed cut must not be "news" that restarts the healing clock)
	F.noseAtStart = F.dmg.nose == true
	F.cutAtStart = math.max(F.dmg.cut, F.dmg.cut2)
	F.dmgStart = table.clone(F.dmg)
	-- a tournament's later rounds (Career: data.carry = Tourney.Carry): he walks in with what the earlier rounds took
	-- out of him, as lower head / body health caps (never under 60%)
	if type(data.carry) == "table" then
		F.healthCap = 100 * math.clamp(tonumber(data.carry.head) or 1, 0.6, 1)
		F.bodyCap = 100 * math.clamp(tonumber(data.carry.body) or 1, 0.6, 1)
		F.health, F.body = F.healthCap, F.bodyCap
	end
	return F
end

-- the fight's damage table minus what the fighter walked in with: a zone that did not get worse
-- tonight reports 0. The seed is the healing residual, and Career heals that over the suspension
-- before it merges res.face, so reporting it again would bring old marks back fresh (age 0) and
-- flag an old cut as new (a second scar for it). A zone that did get worse keeps its full value.
local function tonightDamage(F)
	local d = cloneDamage(F.dmg)
	local start = F.dmgStart or {}
	for _, k in ipairs(DMG_FIELDS) do
		if d[k] <= (tonumber(start[k]) or 0) + 0.01 then
			d[k] = 0
		end
	end
	return d
end
FightEngine.TonightDamage = tonightDamage

function Fight:Now()
	return os.clock()
end

-- a pause in the flow that ends early when the fight is over (a PvP forfeit during the rest minute)
function Fight:Wait(t)
	local t0 = os.clock()
	while os.clock() - t0 < t and not self.finished and not self.aborted do
		task.wait(math.min(0.25, t))
	end
end

function Fight:Distance(A, B)
	if not (A.root and B.root) then
		return 99
	end
	return flat(A.root.Position - B.root.Position).Magnitude
end

-- Ranges fit the rigs: with these shoulders and arms a jab lands with the arm nearly straight at about
-- 4.4 studs root to root, and two guards have about a stud of air between them at the AI's usual 3.4-4.4
-- (FightMotion.Spacing; the client fits each punch to the actual distance)
-- mul (optional) = a special move's range multiplier (Moves.Data.range): applied BEFORE the floor, so a short
-- move (liver shot 0.95, lead uppercut 0.9) still reaches a man standing as close as the bodies allow
function Fight:PunchRange(F, ptype, mul)
	local floor = (self.sp or SPACING).min
	local G, OG = self:Geo(F), self:Geo(self:Other(F))
	if G and OG then
		-- the live rigs (HitGeometry): how far out this man's punch reaches the other's head at a level stance;
		-- the frames never change in a fight, so each punch is worked out once
		local key = ptype .. "|" .. tostring(mul or 1)
		F.rangeCache = F.rangeCache or {}
		local r = F.rangeCache[key]
		if not r then
			r = HitGeometry.Range(G, OG, ptype, false, { mul = mul, floor = floor })
			F.rangeCache[key] = r
		end
		-- never shorter than the closest the bodies get, so every punch can land up close (the height still
		-- decides there: Fight:HitTest)
		return math.max(floor, r)
	end
	-- (no HitGeometry: the tape's reach and height, as before)
	local base = SPACING.base + ((F.data.reach or 70) - 70) * 0.05 + ((F.data.height or 70) - 70) * 0.02
	return math.max(floor, base * (Config.Punches[ptype] and Config.Punches[ptype].range or 1) * (mul or 1))
end

-- a fighter's HitGeometry frame (built once, from his rig or his tape: geoFrame); nil without the module
function Fight:Geo(F)
	if not HitGeometry or not F then
		return nil
	end
	if not F.geo then
		F.geo = geoFrame(F)
	end
	return F.geo
end

-- what the two sizes favour in F's hands (HitGeometry.PunchPrefs: ptype -> weight), nil without the module
function Fight:GeoPrefs(F)
	local G, OG = self:Geo(F), self:Geo(self:Other(F))
	if not (G and OG) then
		return nil
	end
	return (HitGeometry.PunchPrefs(G, OG))
end

-- how bent over the man is right now, 0..1 (HitGeometry lowers his head and chest by it): a roll or a weave takes
-- him right down, a duck and a body-shot crouch most of the way, a slip and a hurt man's hunch a little
function Fight:Bend(O)
	local now = self:Now()
	local bend = 0
	if now < (O.rollUntil or 0) then
		bend = 1
	elseif O.dodgeKind == "weave" and now < (O.dodgeEnd or 0) then
		bend = 0.9
	elseif O.dodgeKind == "duck" and now < (O.dodgeEnd or 0) then
		bend = 0.8
	end
	if O.state == "punching" and O.punchBody then
		bend = math.max(bend, 0.5)
	end
	if now < (O.slipUntil or 0) then
		bend = math.max(bend, 0.3)
	end
	if self:IsHurt(O) or (O.tier or 0) >= 1 then
		bend = math.max(bend, 0.25)
	end
	if O.blocking then
		bend = math.max(bend, 0.1)
	end
	return bend
end

-- does F's punch reach O from dist (root to root)? The geometry of the two rigs (HitGeometry.Test): his glove's
-- path against O's head or body, O's bend, the fight's close floor. Returns the test's verdict table (ok, zone,
-- why = "short" | "high" | "low", redirected = a head shot that lands on the body); without the module, the old
-- range check as a verdict
function Fight:HitTest(F, O, ptype, body, dist, mul)
	local G, OG = self:Geo(F), self:Geo(O)
	if not (G and OG) then
		local ok = dist <= self:PunchRange(F, ptype, mul)
		return { ok = ok, zone = body and "body" or "head", why = (not ok) and "short" or nil }
	end
	return HitGeometry.Test(G, OG, ptype, body, dist, { mul = mul, floor = (self.sp or SPACING).min, bend = self:Bend(O), noRedirect = ptype == "overhand" })
end

-- the closest the two bodies get, centre to centre (the pair's scaled spacing, and no less than their real torsos
-- and gloves need: HitGeometry.MinSep)
function Fight:MinSep()
	local base = (self.sp or SPACING).minSep
	if not self.minSepGeo then
		local G, OG = self:Geo(self.P), self:Geo(self.O)
		self.minSepGeo = (G and OG) and HitGeometry.MinSep(G, OG) or 0
	end
	return math.max(base, self.minSepGeo)
end

-- how far out F can tie the other man up: his arms' reach (HitGeometry.ClinchRange), never inside the bodies
function Fight:ClinchRange(F)
	local G, OG = self:Geo(F), self:Geo(self:Other(F))
	if not (G and OG) then
		return (self.sp or SPACING).clinch
	end
	F.clinchRange = F.clinchRange or math.max(HitGeometry.ClinchRange(G, OG), self:MinSep() + 0.4)
	return F.clinchRange
end

-- the player ends a sparring session early (the spar HUD's Leave Sparring): the coach's cards so far decide it,
-- the session pays out its share (res.partial: the rounds boxed over the rounds booked) and the round loop ends
-- as it does on any stoppage (Cleanup restores the player, Main's runSpar puts him back in the gym)
function Fight:LeaveSpar(F)
	if not self.spar or self.pvp or not F.isPlayer or self.finished or self.aborted then
		return false
	end
	local now = self:Now()
	local boxed = math.max(0, (self.round or 0) - 1)
	if self.live and self.roundSeconds > 0 then
		boxed += math.clamp((self.roundSeconds - math.max(0, (self.roundEnd or now) - now)) / self.roundSeconds, 0, 1)
	end
	local d = Career.DecideCards(self.cards)
	self.sparExit = {
		outcome = d.outcome, method = "Ended", reason = "Session ended early", round = math.max(1, self.round or 1),
		partial = math.clamp(boxed / math.max(1, self.rounds or 1), 0.1, 1),
	}
	self.finished = true
	self.live = false
	self.winner = d.outcome == "win" and self.P or (d.outcome == "loss" and self.O or nil)
	self.method, self.reason, self.endRound = "Ended", "Session ended early", self.round
	self:Send({ t = "announce", text = "COACH: \"That's time. Good work today.\"" })
	return true
end

function Fight:IsHurt(F)
	return self:Now() < F.hurtUntil
end

function Fight:IsStumbling(F)
	return self:Now() < F.stumbleUntil
end

function Fight:Other(F)
	return F == self.P and self.O or self.P
end

function Fight:HeadDamage(F, hd)
	F.headTaken += hd
	F.health = math.max(0, F.health - hd)
	F.stun = math.min(60, F.stun + hd * (STUN_SHARE + F.data.stats.Recovery * STUN_PER_RECOVERY))
end

-- give back up to `amount` of the recoverable stun
function Fight:ClearStun(F, amount)
	local give = math.min(F.stun, amount)
	if give > 0 then
		F.stun -= give
		F.health = math.min(F.healthCap, F.health + give)
	end
end

-- how much a dazed / concussed fighter's defensive windows shrink (slip, roll, parry, pivot)
function Fight:DefenseMul(F)
	return math.max(0.35, (1 - CONC.tierDefense * F.tier) * (1 - CONC.defense * F.conc))
end

------------------------------------------------------------------------
-- The deeper fight: ring traits, momentum, ring position, vision (Config.FightDepth, Shared.Traits)
------------------------------------------------------------------------
-- the strength of one of F's ring traits tonight (0 = he doesn't have it, or this bout has none)
function Fight:Trait(F, id)
	return Traits.Strength(F.traits, id)
end

-- trait id of D's just made a difference against A: the first time it is revealed (if it was hidden) and A's
-- corner calls it, after that a hint now and then (at most 4 a fight, 9 s apart); the AI never needs telling
function Fight:TraitFired(D, id)
	local A = self:Other(D)
	local now = self:Now()
	local h = D.traitHints[id]
	if not h then
		h = { n = 0, at = -100 }
		D.traitHints[id] = h
	end
	h.fired = (h.fired or 0) + 1
	local reveal = not D.traitSeen[id]
	if not reveal and (h.n >= 4 or now - h.at < 9) then
		return
	end
	D.traitSeen[id] = true
	h.n += 1
	h.at = now
	local T = Traits.Data[id]
	if A.player then
		self:SendTo(A, { t = "trait", id = id, name = T.name, hint = T.hint, counter = T.counter, reveal = reveal or nil })
	end
end

-- momentum: -1..1, positive = the red corner (P). Mom(F) = from F's side; Swing(F, x) moves it toward F
function Fight:Mom(F)
	local m = self.mom or 0
	return F == self.P and m or -m
end
function Fight:Swing(F, x)
	if self.tutorial then
		return
	end
	local m = (self.mom or 0) + (F == self.P and x or -x)
	self.mom = math.clamp(m, -1, 1)
end

-- how far F stands from the ropes (studs; the ring's usable square, ClampToRing) and whether he is on them with
-- the other man inside him (between him and the ring centre)
function Fight:RopeDist(F)
	if not (F.root and self.anchors) then
		return 99
	end
	local off = flat(F.root.Position - self.anchors.RingCenter.Position)
	local half = self.ringHalf - 1.5
	return half - math.max(math.abs(off.X), math.abs(off.Z))
end
function Fight:OnRopes(F)
	local O = self:Other(F)
	if not (F.root and O.root and self.anchors) or self:RopeDist(F) > DEPTH.ropeDist then
		return false
	end
	local c = self.anchors.RingCenter.Position
	local toC = flat(c - F.root.Position)
	local toO = flat(O.root.Position - F.root.Position)
	return toC.Magnitude < 0.5 or (toO.Magnitude > 0.05 and toC.Unit:Dot(toO.Unit) > 0.2)
end
-- the share of the ropes' penalty that applies to F (a Ring General slides off them; the body work slows his legs)
function Fight:RopeMul(F)
	local s = self:Trait(F, "RingGeneral")
	if s <= 0 then
		return 1
	end
	return 1 - Traits.Effect("RingGeneral", "corner", s) * math.clamp(F.body / 100 + 0.2, 0.3, 1)
end

-- how blind F is on one side (side 1 = his right, -1 = his left): the swollen eye, a cut bleeding into it
function Fight:Blind(F, side)
	local d = F.dmg
	local eye = side == 1 and d.rightEye or d.leftEye
	local cut = 0
	if d.cut > 0.4 and d.cutSide == side then
		cut = d.cut * 0.35
	end
	if d.cut2 > 0.4 and d.cutSide2 == side then
		cut = math.max(cut, d.cut2 * 0.35)
	end
	return math.clamp(math.max(0, eye - 0.25) / 0.75 + cut, 0, 1)
end

-- the punches F threw in the last `win` seconds (the ring buffer is trimmed as it is read)
function Fight:RecentThrows(F, win)
	local now = self:Now()
	local t = F.throwTimes
	local n = 0
	for i = #t, 1, -1 do
		if now - t[i] <= win then
			n += 1
		elseif now - t[i] > 8 then
			table.remove(t, i)
		end
	end
	return n
end

-- F's fighting type tonight (Traits.FightingType over what he has done)
function Fight:FightingType(F)
	local st = F.typeStats
	return Traits.FightingType({
		style = F.style.id, thrown = st.thrown, minutes = math.max(0.25, st.liveT / 60), body = st.body, heavy = st.heavy,
		counters = st.counters, landed = st.landed, pressing = st.liveT > 0 and st.pressT / st.liveT or 0,
	})
end

-- a defence F just started (a dodge, a slip, a block going up...): if the other man feinted a moment ago, F
-- bit on it (the feinter's next punch is open); the AI's read learns the player's defences
function Fight:NoteDefense(F, kind, dir)
	local O = self:Other(F)
	local now = self:Now()
	if now - O.feintAt <= DEPTH.feint.bite and now > O.feintOpenUntil then
		O.feintOpenUntil = now + DEPTH.feint.open
		O.feintBites += 1
		-- (the counter he was saving is gone: he spent it on air)
		F.counterUntil = math.min(F.counterUntil, now)
		self:Swing(O, 0.03)
		if O.player then
			self:SendTo(O, { t = "intel", hint = "He bit on the feint! Fire now!", tone = "good" })
		end
	end
	if O.ai and O.ai.read and kind ~= "block" then
		O.ai.read:Dodge(kind, dir)
	end
end

------------------------------------------------------------------------
-- Messaging & visuals
------------------------------------------------------------------------
-- Every message is written from the red corner's (P's) point of view: who = "you" means P. A PvP bout
-- has a second player in the blue corner (O); his copy gets "you" / "opp" swapped, so each client sees
-- the fight from its own side. Messages whose content differs per side (state, start, rest, final, the
-- cut call) are built per viewer with SendEach / SendTo.
local FLIP = { you = "opp", opp = "you" }

-- the fighters that have a client watching (P always in a career fight / spar, O too in PvP)
function Fight:Viewers()
	local out = {}
	for _, F in ipairs({ self.P, self.O }) do
		if F and F.player and not F.gone then
			table.insert(out, F)
		end
	end
	return out
end

function Fight:SendTo(V, msg)
	local plr = V and V.player
	if plr and plr.Parent and not V.gone then
		self.remote:FireClient(plr, msg)
	end
end

function Fight:Send(msg)
	for _, V in ipairs(self:Viewers()) do
		local m = msg
		if V ~= self.P and type(msg.who) == "string" and FLIP[msg.who] then
			m = table.clone(msg)
			m.who = FLIP[msg.who]
		end
		self:SendTo(V, m)
	end
end

-- fn(V) -> the message for viewer V (or nil to send nothing)
function Fight:SendEach(fn)
	for _, V in ipairs(self:Viewers()) do
		local m = fn(V)
		if m then
			self:SendTo(V, m)
		end
	end
end

function Fight:Who(F)
	return F == self.P and "you" or "opp"
end

function Fight:Comment(text, priority)
	local now = self:Now()
	if not priority and now - (self.lastComment or 0) < 2.5 then
		return
	end
	self.lastComment = now
	self:Send({ t = "comment", text = text })
end

-- chain = the punch's place in its combination (the model attribute Chain, set BEFORE Act / ActId so the
-- Animator reads it with the act: Combos header); every other act sets it to 0
function Fight:SetAct(F, act, chain)
	setAttr(F.model, "Chain", chain or 0)
	F.actId += 1
	F.model:SetAttribute("Act", act)
	F.model:SetAttribute("ActId", F.actId)
end

function Fight:UpdateGuard(F)
	local g = "stance"
	if F.guardOverride then
		g = F.guardOverride -- walkout / rest / win / lose
	elseif F.state == "down" then
		g = "down"
	elseif F.blocking then
		g = "block"
	elseif F.state == "clinch" then
		g = "clinch"
	elseif self:IsHurt(F) or self:IsStumbling(F) then
		g = "hurt"
	elseif F.tier >= 1 then
		g = "dazed"
	end
	setAttr(F.model, "Guard", g)
end

-- face expression for the Animator's face rig (Config.Expressions)
function Fight:ExprFor(F)
	if F.exprOverride then
		return F.exprOverride
	end
	local now = self:Now()
	if F.state == "down" then
		return F.downSeverity == "out" and "ko" or "dazed"
	end
	if F.tier >= 2 or (F.tier >= 1 and F.conc > 0.35) then
		return "dazed"
	end
	if now < F.hurtUntil or now < F.stumbleUntil or now - F.lastHitAt < 0.5 or now - F.lastBodyHitAt < 0.5 then
		return "pain"
	end
	if F.state == "clinch" or (F.state == "punching" and F.combo >= 3) then
		return "effort"
	end
	if F.stamina < F.maxStam * 0.22 then
		return "fatigue"
	end
	if F.tier == 1 then
		return "fear"
	end
	local O = self:Other(F)
	if O.tier >= 1 or O.state == "down" then
		return "anger" -- smells blood
	end
	if self:EstimateLead(F) >= 1 or (F.data.mental.Confidence > 70 and F.health > 70) then
		return "confident"
	end
	return "determined"
end

-- quantized, change-only model attributes the Animator / face rig / client read (CONTRACTS section 7)
function Fight:SyncAttrs(F)
	local m = F.model
	if not m then
		return
	end
	setAttr(m, "HeadHP", quant(math.clamp(F.health / 100, 0, 1), 0.02))
	setAttr(m, "BodyHP", quant(math.clamp(F.body / 100, 0, 1), 0.02))
	setAttr(m, "Stam", quant(math.clamp(F.stamina / F.maxStam, 0, 1), 0.02))
	setAttr(m, "Daze", F.tier)
	setAttr(m, "Conc", quant(F.conc, 0.05))
	setAttr(m, "Strain", quant(math.clamp(F.strain, 0, 1), 0.1))
	setAttr(m, "Expr", self:ExprFor(F))
end

-- face damage rebuilds are throttled: a flurry marks the face dirty and Update redraws it at most
-- twice a second, so the server never rebuilds the Damage folder on every punch
function Fight:RefreshDamage(F, force)
	local d = F.dmg
	local bits = {}
	for i, k in ipairs(DMG_FIELDS) do
		bits[i] = string.format("%.1f", d[k])
	end
	local key = table.concat(bits, ",") .. tostring(d.nose) .. d.cutSide .. d.cutSide2
	if key == F.dmgKey then
		F.dmgDirty = false
		return
	end
	local now = self:Now()
	if not force and now < (F.dmgNext or 0) then
		F.dmgDirty = true
		return
	end
	F.dmgKey = key
	F.dmgDirty = false
	F.dmgNext = now + 0.5
	local ok, err = pcall(Builder.SetDamage, F.model, F.data.app, d)
	if not ok then
		warn("[Boxer] SetDamage failed:", err)
	end
end

-- head tier changes drive the HUD chip, the dazed body language and the AI's game plan
function Fight:CheckTier(F)
	local t = Config.HeadTier(F.health)
	if t == F.tier then
		return
	end
	local rising = t > F.tier
	F.tier = t
	setAttr(F.model, "Daze", t)
	self:Send({ t = "tier", who = self:Who(F), tier = t })
	if rising and F.state ~= "down" then
		local name = F.data.name
		if t == 1 then
			self:Comment(name .. " is HURT! Those legs just did a little dance!", true)
		elseif t == 2 then
			self:Comment(name .. " is in serious trouble! One more clean shot could end it!", true)
		else
			self:Comment(name .. " is OUT ON " .. his(F):upper() .. " FEET! " .. self:Official(true) .. " is watching closely!", true)
		end
	end
	for _, X in ipairs({ self.P, self.O }) do
		if X.ai then
			X.ai:UpdateMode()
		end
	end
end

------------------------------------------------------------------------
-- Actions (used by both the player's input and the AI)
------------------------------------------------------------------------
function Fight:CanAct(F)
	return not self.finished and self.live and not self.paused and F.state ~= "down" and F.state ~= "clinch"
end

-- the wind-up multiplier of this fighter right now: hand speed, class, fatigue, and a dazed or concussed
-- fighter is a beat slow on everything
local function punchSpeed(F, stamPct)
	local s = F.data.stats
	local speedMul = (1.25 - s.PunchSpeed / 200) * (stamPct < 0.3 and 1.25 or 1)
	speedMul /= (1.08 - (F.data.class - 1) * 0.02) * F.speedMul
	return speedMul * (1 + CONC.tierWindup * F.tier) * (1 + CONC.windup * F.conc)
end

-- Console aim assist: a small hit-chance forgiveness (Low 2 / High 4 points) for punches thrown from a
-- gamepad. The level comes from the SAVED settings (never from a message). The device is the one the
-- SERVER holds the fighter on: it starts as the keyboard, a `device` message moves it, switches are
-- rate-limited (ASSIST.switches in ASSIST.switchWindow seconds; more lock the help for the rest of the
-- window) and a switch to the pad arms the help only ASSIST.arm seconds later. On top of that every input
-- is tagged with its device: any keyboard / mouse / touch input in the last ASSIST.kbdOff seconds switches
-- the help off, and the punch itself has to be a pad one. Last, the one thing the server can SEE: the
-- character's Humanoid.MoveDirection replicates from the client, and a thumbstick gives fractional
-- magnitudes where a keyboard gives exactly 0 or 1 (Fight:SampleDevice). Once the server has seen this
-- fighter move at all in the fight, the help needs an analog magnitude within ASSIST.analog seconds, so a
-- keyboard client claiming the pad gets nothing. The bonus is capped (never lifts a punch past
-- ASSIST.cap) and counts for at most ASSIST.perRound punches a round.
local ASSIST_BONUS = { 0, 0.02, 0.04 }
local ASSIST = { arm = 2, kbdOff = 5, padFresh = 1.5, analog = 10, switches = 3, switchWindow = 30, cap = 0.85, perRound = 25 }
function Fight:AssistBonus(F)
	if not F.isPlayer or F.assist <= 0 or F.device ~= "pad" then
		return 0
	end
	local now = self:Now()
	if now < F.assistLockUntil or now - F.deviceAt < ASSIST.arm then
		return 0
	end
	if now - F.kbdAt < ASSIST.kbdOff or now - F.padAt > ASSIST.padFresh then
		return 0
	end
	if F.moveSeen and now - F.analogAt > ASSIST.analog then
		return 0
	end
	if (F.assistCount or 0) >= ASSIST.perRound then
		return 0
	end
	F.assistCount = (F.assistCount or 0) + 1
	return ASSIST_BONUS[F.assist + 1] or 0
end
FightEngine.ASSIST = ASSIST

-- the client's device changed (FightEngine.Input `device`): rate-limited, and it only ever LOWERS the help
-- at once (a switch to the keyboard is immediate, a switch to the pad arms later)
function Fight:SetDevice(F, pad)
	local dev = pad and "pad" or "kbd"
	if dev == F.device then
		return
	end
	local now = self:Now()
	if now - F.deviceWindow > ASSIST.switchWindow then
		F.deviceWindow = now
		F.deviceSwitches = 0
	end
	F.deviceSwitches += 1
	if F.deviceSwitches > ASSIST.switches then
		-- flapping between devices: no help until the window is over
		F.assistLockUntil = F.deviceWindow + ASSIST.switchWindow
	end
	F.device = dev
	F.deviceAt = now
	if dev == "kbd" then
		F.kbdAt = now
	end
end

-- once a frame: what the replicated MoveDirection says about the device (a stick gives in-between magnitudes)
function Fight:SampleDevice(F, now)
	local hum = F.hum
	if not (F.isPlayer and hum) then
		return
	end
	local m = hum.MoveDirection.Magnitude
	if m > 0.02 then
		F.moveSeen = true
		if m < 0.96 then
			F.analogAt = now
		end
	end
end

-- The Moves & Controls menu stops a SOLO fight (career, sparring; never a PvP bout): the client asks
-- (`pause`) while the window is open. The round stops at the next quiet moment (nobody mid-punch or
-- down, no count running), and then everything waits: the clock, the AI, stamina and every recovery
-- (Update's rdt), and the timers still running are carried over the pause. It resumes when the window
-- closes, or after MENU_PAUSE.cap seconds with it still open; a new pause needs MENU_PAUSE.gap seconds
-- of boxing after the last one.
local MENU_PAUSE = { cap = 60, gap = 3 }
FightEngine.MENU_PAUSE = MENU_PAUSE
local CARRY = { "hurtUntil", "stumbleUntil", "clinchUntil", "counterUntil", "angleUntil", "nextClinch", "nextSpecial", "nextPivot", "slipUntil",
	"rollUntil", "parryUntil", "pivotEvadeUntil", "shellUntil", "lungeUntil", "busyUntil", "dodgeUntil", "dodgeEnd",
	"feintOpenUntil", "windUntil", "guardDropUntil", "clinchNext" }
function Fight:MenuPause(F, on)
	if self.pvp or not F.isPlayer or self.finished then
		return
	end
	if on then
		F.menuAt = F.menuAt or self:Now()
	else
		F.menuAt = nil
	end
end

-- once a frame in a live round: start / end the menu's hold (the knockdown count has its own, kdHold)
function Fight:UpdateMenuHold(now)
	local P = self.P
	local want = P.menuAt ~= nil and now - P.menuAt < MENU_PAUSE.cap
	local pending = false
	if want and not self.menuHold then
		local quiet = not self.kdHold and P.state ~= "punching" and P.state ~= "down" and self.O.state ~= "punching" and self.O.state ~= "down"
		if now - (self.menuEndAt or -100) < MENU_PAUSE.gap then
			want = false
		elseif not quiet then
			-- the AI starts nothing new meanwhile, so the quiet moment comes
			want, pending = false, true
		end
	end
	self.menuPending = pending
	if want == (self.menuHold == true) then
		return
	end
	self.menuHold = want
	self.paused = self.kdHold == true or want
	if want then
		self.menuStartAt = now
	else
		local dur = now - (self.menuStartAt or now)
		for _, F in ipairs({ self.P, self.O }) do
			for _, k in ipairs(CARRY) do
				if type(F[k]) == "number" and F[k] > (self.menuStartAt or now) then
					F[k] += dur
				end
			end
			F.lastHitAt += dur
			F.lastBodyHitAt += dur
			if F.chain and not F.chain.closed then
				F.chain.closeAt += dur -- (a combination's window waits over the pause too)
			end
		end
		self.menuEndAt = now
		self.resumedAt = now
	end
	self:SendTo(P, { t = "pause", on = want, why = (not want and P.menuAt ~= nil) and "cap" or nil, cap = MENU_PAUSE.cap })
end

-- Shift in the ring (FightEngine.Input `sprint`, held): quicker feet to cut him off or get off the ropes.
-- Not while punching or behind the guard, it drains stamina while he moves and stops when he is gassed.
local SPRINT = { mul = 1.3, drain = 7, floor = 0.15 }
function Fight:SetSprint(F, on)
	F.sprintOn = on == true and F.isPlayer
end
function Fight:Sprinting(F)
	return F.sprintOn == true and F.hum ~= nil and F.state ~= "punching" and not F.blocking and F.stamina > F.maxStam * SPRINT.floor
end

-- counter = a counter jab / cross (Q + click, E + right click): the punch comes straight out of the slip
-- (the slip's recovery does not hold it) and counts as a counter when it catches the other man punching.
-- Combinations (Shared.Combos): a punch thrown inside the last one's chain window continues its chain; a press
-- up to Combos.BUFFER before the recovery ends is held and thrown on the frame it ends (fromBuffer); an earlier
-- one is refused and counted against the chain as a mash
function Fight:Punch(F, ptype, body, counter, fromBuffer)
	local P = Config.Punches[ptype]
	if P and F.state == "clinch" and not self.finished and self.live and not self.paused then
		-- in the clinch a punch is inside work: a short shot to the body (Fight:ClinchWork)
		return self:ClinchWork(F, ptype)
	end
	if not P or not self:CanAct(F) then
		return
	end
	local now = self:Now()
	-- only the straight counters (jab / cross, all the keymap sends) skip the slip's recovery, once per slip
	local outOfSlip = counter == true and (ptype == "jab" or ptype == "cross") and now - (F.slipAt or -10) < 0.6 and F.state ~= "punching"
	if now < F.busyUntil and not outOfSlip and not (fromBuffer and now >= F.busyUntil - 0.03) then
		if F.state == "punching" and not F.special and not fromBuffer then
			if F.busyUntil - now <= Combos.BUFFER and not F.buffered then
				F.buffered = true
				local fightId = self.id
				task.delay(F.busyUntil - now, function()
					if self.id == fightId and not self.finished then
						F.buffered = false
						self:Punch(F, ptype, body, counter, true)
					end
				end)
			elseif F.chain and not F.chain.closed then
				F.chain.mash += 1 -- (a wild press: the chain's accuracy pays for it)
			end
		end
		return
	end
	if outOfSlip then
		F.slipAt = -10
	end
	local O = self:Other(F)
	if O.state == "down" then
		return
	end
	if ptype == "overhand" then
		body = false
	elseif not body and HitGeometry then
		-- a head shot the geometry says lands on the body from here (a much taller man out at range) is thrown
		-- at the body: the act (and the client's prediction, which runs the same test) aims where it will land
		local pre = self:HitTest(F, O, ptype, false, self:Distance(F, O))
		if pre.redirected then
			body = true
		end
	end
	F.punchBody = body == true
	local s = F.data.stats
	local stamPct = F.stamina / F.maxStam
	local windup = P.windup * punchSpeed(F, stamPct)
	-- (Granite: almost impossible to drop, but slow)
	windup *= 1 + Traits.Effect("Granite", "windup", self:Trait(F, "Granite"))
	-- the chain: inside the window it goes on, else a new one starts (the old one is scored)
	local chained = Combos.Continues(F.chain, now)
	if not chained then
		self:CloseChain(F)
		F.chain = Combos.NewChain(now)
	end
	local chain = F.chain
	F.combo = chain.punches + 1
	if chained and chain.punches > 0 then
		windup *= Combos.CHAIN_WINDUP
	end
	F.lastPunch = now
	local cost = P.stam * (body and 1.1 or 1) * (1.2 - s.Endurance / 250) * Combos.StamMul(F.combo)
	F.stamina = math.max(0, F.stamina - cost)
	F.blocking = false
	F.state = "punching"
	F.special = nil -- a plain punch replaces whatever special was still being thrown
	F.dodgeKind = nil
	F.busyUntil = now + windup * Combos.RECOVERY_MUL
	chain.closeAt = F.busyUntil + Combos.Window(windup)
	F.assistNext = self:AssistBonus(F)
	local hand = P.hand
	if ptype == "uppercut" then
		hand = (F.hand == "R" and F.combo > 1) and "L" or "R"
	end
	F.hand = hand
	local item = Combos.AddPunch(chain, { tok = Combos.Token(ptype, body, hand), p = ptype, body = body == true, cost = cost, at = now, windup = windup }, F.sigs)
	-- (with the act flag the Animator reads, Combos header: the punch's place in the combination)
	-- (a chained punch also carries its place as the act's sixth field, the Animator's format: "jab|L|head|0.16||2")
	local act = string.format("%s|%s|%s|%.2f", ptype, hand, body and "body" or "head", windup)
	if F.combo >= 2 then
		act ..= "||" .. F.combo
	end
	self:SetAct(F, act, F.combo)
	F.tally.thrown += 1
	F.totals.thrown += 1
	F.punchesUsed[ptype] = (F.punchesUsed[ptype] or 0) + 1
	self:NoteThrow(F, ptype, body)
	if O.ai then
		O.ai:OnOppPunch(ptype, body, windup, { hand = hand, chainPos = F.combo })
	end
	if self.tutorial and F == self.P then
		self:TutorialNote({ k = "punch", p = ptype, body = body == true })
		if item.named then
			self:TutorialNote({ k = "combo", id = item.named.id, counter = item.named.counter == true })
		end
	end
	local fightId = self.id
	local opts = { counterPunch = outOfSlip or nil, chain = item, chainRef = chain }
	task.delay(windup, function()
		if self.id == fightId and not self.finished then
			self:Resolve(F, O, ptype, body, stamPct, opts)
		end
	end)
end

-- a punch thrown (plain or a special's): the pressure clock, the fighting type's stats, the AI's read of him
function Fight:NoteThrow(F, ptype, body)
	local now = self:Now()
	table.insert(F.throwTimes, now)
	if #F.throwTimes > 24 then
		table.remove(F.throwTimes, 1)
	end
	local st = F.typeStats
	st.thrown += 1
	if body then
		st.body += 1
	end
	local kind = Config.Punches[ptype] and Config.Punches[ptype].kind
	if kind ~= "straight" then
		st.heavy += 1
	end
	local O = self:Other(F)
	if O.ai and O.ai.read then
		O.ai.read:Punch(ptype, body == true, F.combo, self:Distance(F, O), F.stamina < F.maxStam * 0.3)
	end
end

-- The feint (the `feint` input; Config.FightDepth.feint): a fake jab - the shoulder and the lead hand jump, no
-- punch comes. Cheap, quick, and if the other man reacts to it (a block, a slip, a dodge within `bite` s) he
-- bit: the next punch is open (Fight:NoteDefense). The AI sees it as it would see a jab (it cannot know); a feint
-- spammed costs more stamina and the AI's read learns to stop biting. A flick-then-button on a pad may turn the
-- flick's parry into the feint (Evasion.CANCEL), as the dodges do.
function Fight:Feint(F)
	local FT = DEPTH.feint
	if not self:CanAct(F) or self:Other(F).state == "down" then
		return false
	end
	local now = self:Now()
	if now < F.busyUntil then
		if not (F.state ~= "punching" and not F.defCancelled and now - F.defAt < Evasion.CANCEL) then
			return false
		end
		-- (the flick's parry / slip turns into the feint: half its stamina back, its window off)
		F.stamina += F.defCost * 0.5
		F.slipUntil, F.rollUntil, F.parryUntil, F.pivotEvadeUntil, F.dodgeUntil = 0, 0, 0, 0, 0
		F.dodgeKind = nil
		F.defCancelled = true
	end
	local recent = 0
	for i = #F.feintTimes, 1, -1 do
		if now - F.feintTimes[i] <= FT.spamWin then
			recent += 1
		else
			table.remove(F.feintTimes, i)
		end
	end
	local cost = FT.stam + math.max(0, recent - FT.spamFree) * FT.spamStam
	if F.stamina < cost then
		return false
	end
	F.stamina -= cost
	table.insert(F.feintTimes, now)
	F.feints += 1
	F.feintAt = now
	F.blocking = false
	F.state = "idle"
	F.busyUntil = now + FT.busy
	F.hand = "L"
	-- (the Animator plays it as a short, light jab: the act's power field keeps it a pump, not a punch)
	self:SetAct(F, string.format("jab|L|head|%.2f|0.20", FT.windup))
	local O = self:Other(F)
	if O.ai then
		O.ai:OnOppPunch("jab", false, Config.Punches.jab.windup * punchSpeed(F, F.stamina / F.maxStam), { feint = true, hand = "L", chainPos = 1 })
		if O.ai.read then
			O.ai.read:Feint()
		end
	end
	return true
end

-- the end of a fighter's chain: scored into his combo stats, and the HUD's counter told it is over
function Fight:CloseChain(F)
	local chain = F.chain
	if not chain or chain.closed then
		return
	end
	local sum = Combos.Close(chain)
	Combos.Record(F.comboStats, sum)
	local O = self:Other(F)
	if O and O.ai and O.ai.OnOppComboEnd then
		O.ai:OnOppComboEnd(sum.punches or 0)
	end
	if sum.punches >= 2 then
		self:Send({ t = "comboEnd", who = self:Who(F), hits = sum.landed, n = sum.punches, name = sum.named and sum.named.name or nil })
	end
end

-- a punch of a chain has its result (res = "landed" | "blocked" | "miss"): the combo rules (Combos.Result) and
-- the HUD's counter / call-outs
function Fight:ChainResult(F, O, sp, res)
	local it, chain = sp and sp.chain, sp and sp.chainRef
	if not (it and chain) or it.res then
		return
	end
	local ev = Combos.Result(chain, it, res)
	if res == "miss" and chain.punches >= Combos.WHIFF_FROM then
		F.stamina = math.max(0, F.stamina - Combos.WHIFF) -- a wild flurry's misses cost more
	end
	if ev.refund and ev.refund > 0 then
		F.stamina = math.min(F.stamCap or F.maxStam, F.stamina + ev.refund)
	end
	local who = self:Who(F)
	if ev.named then
		self:Swing(F, 0.03 + 0.01 * (it.namedLen or 2))
		self:Send({ t = "combo", who = who, hits = chain.landed, n = chain.punches, name = ev.named.name, id = ev.named.id, sig = ev.named.signature or nil })
		if ev.named.signature or it.namedLen >= 3 then
			self:Comment(string.format("%s lands the %s!", F.data.name, ev.named.signature and ev.named.name:lower() or ev.named.name), ev.named.signature)
		end
	elseif chain.punches >= 2 then
		self:Send({ t = "combo", who = who, hits = chain.landed, n = chain.punches })
	end
	if ev.broken and F.chain == chain then
		-- the second punch into the guard: the combination is smothered and the other man's counter is on
		local now = self:Now()
		O.counterUntil = math.max(O.counterUntil, now + Combos.BREAK_COUNTER)
		F.busyUntil = math.max(F.busyUntil, now) + Combos.BREAK_STALL
		self:Swing(O, 0.04)
		self:CloseChain(F)
		self:Send({ t = "comboBroken", who = who })
	end
end

-- a dodge that made the punch miss opens a chain for the man who dodged: the counter thrown in its window
-- continues it (SLIP-COUNTER, WEAVE-COUNTER...)
function Fight:DodgeChain(F, kind, window)
	self:CloseChain(F)
	F.chain = Combos.NewChain(self:Now())
	Combos.AddDodge(F.chain, kind, self:Now(), window)
	F.evades += 1
end

-- the root travel of a special's set-up (a leap in, two steps back): the NPC glides on the server, the
-- player's client drives its own character from the 'lunge' message (as it does a stumble)
function Fight:Lunge(F, dist, dur)
	local O = self:Other(F)
	if not (F.root and O.root) then
		return
	end
	local toward = flat(O.root.Position - F.root.Position)
	local dir = unitOr(toward, flat(F.root.CFrame.LookVector))
	if dist < 0 then
		dir, dist = -dir, -dist
	else
		-- never into the other man: stop a body's width short
		dist = math.max(0, math.min(dist, toward.Magnitude - (self.sp or SPACING).minSep))
	end
	if dist < 0.1 then
		return
	end
	local now = self:Now()
	F.lungeUntil = now + dur
	F.lungeVel = dir * (dist / dur)
	self:Send({ t = "lunge", who = self:Who(F), dir = { x = dir.X, z = dir.Z }, dur = dur, speed = dist / dur })
end

-- A special move (Moves.Data): a set-up (FightMotion.Specials[id].pre: shoulder roll, pull, step back, leap,
-- bob and weave) and one or two ordinary punches landed on the FightMotion.SpecialHits schedule through
-- Resolve, with the move's multipliers. The set-up of a counter move is an evade window (shell); a leap
-- or a step moves the root. A medium-or-worse hit taken cancels the punches not yet thrown.
function Fight:Special(F, id)
	local sid = Moves and Moves.Id(id)
	local M = sid and Moves.Data[sid]
	if not M or not self:CanAct(F) then
		return
	end
	local now = self:Now()
	-- a player is told why a special did not go (the HUD says so and the local prediction is called off)
	local why = (not F.moves[sid] and "locked") or (now < F.nextSpecial and "cooldown") or (F.stamina < M.stam and "stamina")
		or (now < F.busyUntil and "busy") or (self:Other(F).state == "down" and "down") or nil
	if why then
		if F.isPlayer then
			self:SendTo(F, { t = "refused", what = "special", id = sid, why = why, wait = math.max(0, math.max(F.nextSpecial, F.busyUntil) - now) })
		end
		return
	end
	local O = self:Other(F)
	local first = Config.Punches[M.punch[1]]
	local stamPct = F.stamina / F.maxStam
	local windup = first.windup * punchSpeed(F, stamPct)
	local hits = FightMotion and FightMotion.SpecialHits and FightMotion.SpecialHits(sid, windup) or {}
	local pre = 0.25
	if FightMotion and FightMotion.Specials and FightMotion.Specials[sid] then
		pre = FightMotion.Specials[sid].pre
	end
	if #hits == 0 then
		hits = { pre + windup } -- no FightMotion: a plain punch after the set-up
	end
	local last = hits[#hits]
	F.stamina = math.max(0, F.stamina - M.stam * (1.2 - F.data.stats.Endurance / 250))
	F.blocking = false
	F.state = "punching"
	self:CloseChain(F) -- (a special is a combination of its own: it ends the chain)
	F.chain = nil
	F.combo = 1
	F.dodgeKind = nil
	F.lastPunch = now
	-- the recovery of the last punch (the check hook's long pivot-out animates on its own; the next act
	-- simply replaces it)
	F.busyUntil = now + last + windup * 0.9
	F.nextSpecial = now + M.cooldown
	F.assistNext = self:AssistBonus(F)
	F.hand = M.hand
	F.specialToken += 1
	local token = F.specialToken
	F.special = { id = sid, token = token }
	F.specialsUsed += 1
	if M.shell then
		F.shellUntil = now + pre + 0.12
		F.shellKind = M.shell
		F.shellText = M.shellText
		F.shellHit = false
	end
	if M.lunge and M.lunge ~= 0 then
		self:Lunge(F, M.lunge, math.max(0.2, pre))
	end
	self:SetAct(F, string.format("special|%s|%s|%.2f|%.2f", sid, M.hand, windup, M.power or 1))
	F.tally.thrown += #hits
	F.totals.thrown += #hits
	self:Send({ t = "special", who = self:Who(F), id = sid, name = M.name })
	if self.tutorial and F == self.P then
		self:TutorialNote({ k = "special", id = sid })
	end
	-- each punch's body flag: Moves.Data bodies[i] (the body-head hook goes low, then high), else the move's
	local function bodyOf(i)
		local b = M.bodies and M.bodies[i]
		if b == nil then
			return M.body == true
		end
		return b == true
	end
	if O.ai then
		for i, at in ipairs(hits) do
			O.ai:OnOppPunch(M.punch[i] or M.punch[1], bodyOf(i), at)
		end
	end
	local fightId = self.id
	for i, at in ipairs(hits) do
		local kind = M.punch[i] or M.punch[1]
		task.delay(at, function()
			if self.id == fightId and not self.finished and F.special and F.special.token == token then
				-- the second punch of a rush is the other hand (a double jab's / body-head hook's hands are
				-- listed: Moves.Data hands)
				F.hand = (M.hands and M.hands[i]) or ((i % 2 == 0) and (M.hand == "L" and "R" or "L") or M.hand)
				F.punchesUsed[kind] = (F.punchesUsed[kind] or 0) + 1
				self:NoteThrow(F, kind, bodyOf(i))
				self:Resolve(F, O, kind, bodyOf(i), stamPct, M)
				if i == #hits and F.special and F.special.token == token then
					F.special = nil
				end
			end
		end)
	end
end

function Fight:Evaded(F, O, ptype, body, now)
	local kind = Config.Punches[ptype].kind
	-- a punch from the side of a closing eye (or a cut bleeding into it) is one he never saw: a dodge beats it
	-- only part of the time (Config.FightDepth.blindDodge). F's left hand lands on O's right side.
	local landSide = F.hand == "L" and 1 or -1
	local blind = self:Blind(O, landSide)
	if blind > 0 and self.rng:NextNumber() < blind * DEPTH.blindDodge then
		return false
	end
	-- a special's set-up: the shoulder roll and the weave take head shots (not uppercuts), the pull takes
	-- straights, the step back takes everything; what it makes miss turns the move's punch into a counter
	if now < O.shellUntil then
		local k = O.shellKind
		if k == "all" or (not body and ((k == "straight" and kind == "straight") or (k == "head" and kind ~= "uppercut"))) then
			O.shellUntil = 0
			O.shellHit = true
			O.counterUntil = now + 0.9
			self:Send({ t = "defense", who = self:Who(O), move = O.shellText or "SLIPPED" })
			self:Comment(O.data.name .. " makes him miss and the counter is coming!")
			return true
		end
	end
	if now < O.parryUntil and kind == "straight" and not body then
		O.parryUntil = 0
		O.counterUntil = now + 0.7
		F.stamina = math.max(0, F.stamina - 4)
		self:SetAct(O, "parryhit")
		self:Send({ t = "defense", who = self:Who(O), move = "PARRIED" })
		self:Comment(O.data.name .. " parries it away and fires back!")
		return true
	end
	if now < O.pivotEvadeUntil and kind == "straight" then
		O.counterUntil = now + 0.6
		self:Send({ t = "defense", who = self:Who(O), move = "PIVOT" })
		self:DodgeChain(O, "sidestep", 0.6)
		return true
	end
	if now < O.slipUntil and not body then
		-- a hook against a slip: slipping AWAY from the hand it comes from (to his left away from a left hook,
		-- which lands on his right) makes it miss; slipping into it walks onto it (Resolve: a little harder).
		-- No side recorded (an old caller): the coin, as before
		local hookAway
		if kind == "hook" then
			if O.slipDir == -1 or O.slipDir == 1 then
				hookAway = O.slipDir == -landSide
			else
				hookAway = self.rng:NextNumber() < 0.5
			end
		end
		if kind == "straight" or hookAway then
			O.counterUntil = now + 0.85
			self:Send({ t = "defense", who = self:Who(O), move = "SLIPPED", dodge = "slip" })
			self:Comment(O.data.name .. " slips it beautifully!")
			self:DodgeChain(O, "slip", 0.85)
			return true
		end
	end
	if now < O.rollUntil and not body then
		if kind == "hook" or kind == "overhand" or (kind == "straight" and self.rng:NextNumber() < 0.5) then
			O.counterUntil = now + 0.8
			self:Send({ t = "defense", who = self:Who(O), move = "ROLLED UNDER", dodge = "roll" })
			self:Comment(O.data.name .. " rolls under it!")
			self:DodgeChain(O, "roll", 0.8)
			return true
		end
	end
	-- the dodges of Shared.Evasion (weave, duck, pull, side-step): inside the window, when it beats the punch
	local dk = O.dodgeKind
	local E = dk and dk ~= "slip" and dk ~= "roll" and Evasion.Moves[dk]
	if E and now < O.dodgeUntil and Evasion.Beats(dk, kind, body, self.rng:NextNumber()) then
		O.dodgeUntil = 0
		O.counterUntil = now + E.counter
		self:Send({ t = "defense", who = self:Who(O), move = E.text, dodge = dk })
		if self.rng:NextNumber() < 0.5 then
			self:Comment(string.format("%s %s!", O.data.name, dk == "weave" and "weaves under it" or (dk == "duck" and "ducks it" or (dk == "pull" and "pulls back from it" or "steps off the line"))))
		end
		self:DodgeChain(O, dk, E.counter)
		return true
	end
	return false
end

-- which face zones a clean head shot marks (Config.Punches[p].face). A left hand lands on the
-- opponent's RIGHT side (Side +1) and vice versa.
function Fight:FaceHit(O, F, ptype, hd, hdRef)
	local P = Config.Punches[ptype]
	local d = O.dmg
	local left = F.hand == "L"
	local side = left and 1 or -1
	local eyeKey = left and "rightEye" or "leftEye"
	local cheekKey = left and "cheekR" or "cheekL"
	local earKey = left and "earR" or "earL"
	local kind = P.kind
	local function add(k, v)
		d[k] = math.min(DMG_CAP[k] or 1, d[k] + v)
	end
	add("redness", hd / 50)
	local noseZone = false
	for _, zone in ipairs(P.face or {}) do
		if zone == "eye" then
			add(eyeKey, hd / (kind == "straight" and 110 or (kind == "overhand" and 55 or 40)))
		elseif zone == "nose" then
			noseZone = true
			add("noseBleed", hd / (kind == "straight" and 45 or 70))
		elseif zone == "lip" then
			add("lip", hd / (kind == "uppercut" and 40 or 90))
		elseif zone == "cheek" then
			add(cheekKey, hd / 45)
		elseif zone == "ear" then
			add(earKey, hd / 70)
		elseif zone == "forehead" then
			add("forehead", hd / 45)
		elseif zone == "bruise" then
			add("bruise", hd / (kind == "uppercut" and 90 or 70))
		end
	end
	if noseZone and kind == "straight" and not d.nose and hd > 1.5 * hdRef and self.rng:NextNumber() < 0.06 then
		d.nose = true
		self:Comment("That nose is BROKEN!", true)
	end
	-- cuts: the punch's cutChance scaled by how hard it landed (and an old cut that reopens)
	if self.rng:NextNumber() < P.cutChance * (hd / 3.1) * (self.cutRisk[O] or 1) then
		local gash = self.rng:NextNumber(0.15, 0.32)
		if d.cut > 0.25 and side ~= d.cutSide then
			d.cut2 = math.min(1.2, d.cut2 + gash)
			d.cutSide2 = side
		else
			d.cut = math.min(1.2, d.cut + gash)
			d.cutSide = side
		end
		self:SendEach(function(V)
			return { t = "announce", text = (O == V and "You're" or O.data.name .. " is") .. " CUT!" }
		end)
		self:Comment("There's blood! " .. O.data.name .. " is cut over the eye!", true)
	end
	self:RefreshDamage(O)
end

-- knockdown severity once a knockdown is decided: flash (tier-0 counter) | normal | heavy | out
function Fight:Severity(O, rel)
	local sv = KO.severity
	if (O.health <= 0 or O.tier >= 3) and rel >= sv.outHd and self.rng:NextNumber() < 0.5 then
		return "out"
	end
	if O.health <= 0 or O.tier >= sv.heavyTier or rel >= sv.heavyHd then
		return "heavy"
	end
	return "normal"
end

-- DownPose: how the fighter falls (Config.KO.falls)
local function fallFor(ptype, body, severity)
	if severity == "flash" then
		return "sit"
	elseif severity == "out" then
		return "face"
	elseif body then
		return "knee"
	end
	local kind = Config.Punches[ptype].kind
	if kind == "hook" then
		return "side"
	elseif kind == "overhand" then
		return "face"
	end
	return "back"
end

-- sp (optional) = the special move this punch belongs to (Moves.Data: range / hit / dmg / kd multipliers,
-- its counter and liver rules) or { counterPunch = true } for a counter jab / cross out of a slip
function Fight:Resolve(F, O, ptype, body, stamPct, sp)
	if F.state == "down" or O.state == "down" or F.state == "clinch" or O.state == "clinch" or not self.live or self.menuHold then
		return
	end
	local P = Config.Punches[ptype]
	local s, os_ = F.data.stats, O.data.stats
	local now = self:Now()
	local dist = self:Distance(F, O)
	sp = sp or {}
	-- the reach (HitGeometry through Fight:HitTest): his glove's path from his real shoulder against the other
	-- man's real head or body at this distance, his bend, the fight's close floor. A head shot that cannot get up
	-- to a much taller chin lands on the body when it reaches that far
	local hit = self:HitTest(F, O, ptype, body, dist, sp.range)
	if not hit.ok then
		self:ChainResult(F, O, sp, "miss")
		self:Miss(F, O, ptype, hit.why == "high" and "high" or (hit.why == "low" and "low" or "short"))
		return
	end
	if hit.redirected and not body then
		body = true
		self:Send({ t = "redirect", who = self:Who(F), punch = ptype })
	end
	if self:Evaded(F, O, ptype, body, now) then
		if F.ai and F.ai.obs then
			F.ai.obs.slips += 1
		end
		-- the dodge WON: it is over (a punch that follows is not one that "caught him mid-dodge": no catch bonus,
		-- no Punish multiplier, no announce for the rest of its recovery)
		O.dodgeKind = nil
		O.dodgeEnd = math.min(O.dodgeEnd, now)
		self:Swing(O, 0.025)
		self:ChainResult(F, O, sp, "miss")
		self:Miss(F, O, ptype, "evaded")
		return
	end
	local slipping = now < O.slipUntil
	local rolling = now < O.rollUntil
	-- hit chance
	local vision = math.max(F.dmg.leftEye, F.dmg.rightEye) > 0.8 and 0.88 or 1
	local chance = P.hit * (0.7 + (F.data.mental.Focus + s.RingIQ) / 500) - os_.HeadMovement / 350
	if body then
		chance += 0.1
	end
	if O.state == "punching" then
		chance += 0.12
	end
	if self:IsHurt(O) then
		chance += 0.12
	end
	-- a dazed or stumbling target cannot get out of the way
	chance += 0.04 * O.tier
	if self:IsStumbling(O) then
		chance += 0.15
	end
	local angled = now < F.angleUntil
	if angled then
		chance += 0.15
		F.angleUntil = 0
	end
	-- the check hook pivots out after the hook: an angle for the next punch and a moment off his line
	if sp.pivotOut then
		F.angleUntil = now + 1.2
		F.pivotEvadeUntil = now + 0.3 * self:DefenseMul(F)
	end
	chance += (sp.hit or 0)
	-- the combination (Combos: a named combo's last punch, a level change, a long or predictable flurry, mashing)
	local item = sp.chain
	if item then
		chance += item.hit or 0
	end
	-- a punch out of a dodge's counter window finds him off balance (Evasion.COUNTER_HIT); one that catches him
	-- after his dodge's window but before he is set again lands easier and harder (Evasion: the timing)
	if now < F.counterUntil then
		chance += Evasion.COUNTER_HIT
	end
	local caught = O.dodgeKind ~= nil and now >= O.dodgeUntil and now < O.dodgeEnd
	if caught then
		chance += Evasion.CAUGHT_HIT
	end
	-- the deeper fight (Config.FightDepth): the side of a closing eye, the momentum, being walked down (a
	-- Pressure-proof man doesn't wilt), the ropes (a Ring General slides off them), a feint he bit on, a raw
	-- boxer's hands hanging after his combination
	chance += DEPTH.blindHit * self:Blind(O, F.hand == "L" and 1 or -1)
	chance += DEPTH.momHit * self:Mom(F)
	local proofF = self:Trait(F, "PressureProof")
	if F.pressured and proofF <= 0 then
		chance -= DEPTH.pressHit
	end
	if O.onRopes then
		chance += DEPTH.ropeHit * self:RopeMul(O)
	end
	local opened = now < F.feintOpenUntil
	if opened then
		chance += DEPTH.feint.hit
		F.feintOpenUntil = 0
	end
	if now < O.guardDropUntil then
		chance += Config.FightAI.dropHit
	end
	-- the ring traits on the punches they read (Shared.Traits): a Slick man's straights, a Weaver's hooks (his
	-- dip meets the uppercut); none of it right after he bit on a feint. A Pressure-proof man counters a swarmer.
	local traitCut, traitId = 0, nil
	if not body and not opened then
		if P.kind == "straight" then
			traitCut, traitId = Traits.Effect("Slick", "hit", self:Trait(O, "Slick")), "Slick"
		elseif P.kind == "hook" or P.kind == "overhand" then
			traitCut, traitId = Traits.Effect("Weaver", "hit", self:Trait(O, "Weaver")), "Weaver"
		elseif P.kind == "uppercut" then
			chance += Traits.Effect("Weaver", "upper", self:Trait(O, "Weaver"))
		end
		chance -= traitCut
	end
	if proofF > 0 and F.pressured and (now < F.counterUntil or O.state == "punching") then
		chance += Traits.Effect("PressureProof", "hit", proofF)
	end
	if (F.assistNext or 0) > 0 then
		-- the console forgiveness never lifts a punch past the cap (and never lowers one that is already above it)
		chance = math.max(chance, math.min(chance + F.assistNext, ASSIST.cap))
	end
	F.assistNext = 0
	-- concussion and daze cost accuracy; so do a tired body and a damaged head, and the eyes he still has
	chance *= (1 - CONC.hitChance * F.conc) * (1 - CONC.tierHitChance * F.tier)
	chance *= 1 - DEPTH.fatigueHit * math.max(0, DEPTH.fatigueAt - stamPct) / DEPTH.fatigueAt
	chance *= 1 - DEPTH.damageHit * math.max(0, DEPTH.damageAt - F.health) / DEPTH.damageAt
	vision = math.min(vision, 1 - DEPTH.visionHit * math.max(F.dmg.leftEye, F.dmg.rightEye))
	chance = math.clamp(chance * vision, 0.15, 0.95)
	-- clean = how cleanly it landed (feeds the knockdown odds); 0.5 when it comes through a guard
	local clean = 0.5
	if not O.blocking then
		local roll = self.rng:NextNumber()
		if roll > chance then
			if traitId and traitCut > 0 and roll <= chance + traitCut then
				self:TraitFired(O, traitId) -- (the trait made it miss)
			end
			self:ChainResult(F, O, sp, "miss")
			self:Miss(F, O, ptype, "miss")
			return
		end
		clean = (chance - roll) / chance
	end

	-- damage
	local dmg = P.dmg * (0.55 + s.Power / 110) * F.style.fight.power * F.classScale * F.powerMul
	if ptype == "jab" then
		dmg *= F.style.fight.jab
	end
	dmg *= math.clamp(0.55 + stamPct * 0.6, 0.55, 1.05)
	dmg *= 0.9 + F.data.mental.Confidence / 500
	dmg *= 0.95 + (F.data.mental.Aggression or 50) / 1000
	dmg *= self.rng:NextNumber(0.85, 1.15)
	dmg *= self.damageScale
	if self.tutorial and Tutorial then
		-- the tutorial is forgiving: the player's shots land harder, the opponent's barely hurt
		dmg *= Tutorial.DamageMul(self.tutorial, O.isPlayer)
	end
	if angled then
		dmg *= 1.1
	end
	if dist < (self.sp or SPACING).inside then
		if P.kind == "hook" or P.kind == "uppercut" then
			dmg *= F.style.fight.inside
		else
			dmg *= 0.85
		end
	end
	if F.combo >= 2 then
		dmg *= 1 + (F.style.fight.combo - 1) * 0.5
	end
	if item and sp.chainRef then
		-- the landed-chain ramp and the named / signature combo's own bonus
		dmg *= Combos.Ramp(sp.chainRef, item, F.style.fight.combo) * (item.dmg or 1)
	end
	if O.dodgeKind ~= nil and now < O.dodgeEnd then
		-- caught in a dodge that does not beat this punch (an uppercut into a weave), or after its window
		dmg *= Evasion.Punish(O.dodgeKind, P.kind) * (caught and Evasion.CAUGHT_DMG or 1)
	end
	dmg *= sp.dmg or 1
	-- the momentum: the man it favours lands a little heavier (Config.FightDepth.momDmg)
	dmg *= 1 + DEPTH.momDmg * self:Mom(F)
	-- slipping INTO a hook (toward the hand it comes from) walks onto it
	if slipping and P.kind == "hook" and O.slipDir == (F.hand == "L" and 1 or -1) then
		dmg *= 1.15
	end
	local counter = false
	if now < F.counterUntil then
		counter = true
		dmg *= 1.2 * F.style.fight.counter * (0.85 + s.Countering / 300)
		F.counterUntil = 0
	elseif O.state == "punching" and (sp.counter or sp.counterPunch or sp.pivotOut) then
		-- a counter move (shell, pull, step back, check hook, a jab or cross out of a slip) that catches him
		-- punching is a counter in its own right
		counter = true
		dmg *= 1.15 * (0.85 + s.Countering / 300)
	elseif O.state == "punching" then
		dmg *= 1.1
	end
	if slipping and (P.kind == "uppercut" or P.kind == "overhand") then
		dmg *= 1.3
		counter = true
	elseif rolling and P.kind == "uppercut" then
		dmg *= 1.4
		counter = true
	end
	-- a Counter Specialist's counter into a flurry (the 3rd+ punch of a combination, or a busy spell)
	local cs = self:Trait(F, "CounterSpecialist")
	if counter and cs > 0 and ((O.chain and not O.chain.closed and O.chain.punches >= 3) or self:RecentThrows(O, 4) >= 7) then
		dmg *= 1 + Traits.Effect("CounterSpecialist", "counter", cs)
		self:TraitFired(F, "CounterSpecialist")
	end
	-- reference head damage for "how big was that": a solid cross at full strength is about 1
	local hdRef = 6 * HEAD_SCALE * self.damageScale

	-- block (the overhand comes over the top of the guard)
	if O.blocking and not body then
		local through = sp.overGuard or P.overGuard or 0
		local arms = 1.3 - 0.3 * math.clamp(O.stamina / O.maxStam, 0, 1)
		-- tired arms and a dazed, loose guard let more through
		local chip = dmg * math.clamp(0.28 - os_.Blocking / 400, 0.04, 0.25) * arms * (1 + 0.35 * O.tier)
		local hd = chip + dmg * through * HEAD_SCALE * 0.6 * (P.head or 1)
		self:HeadDamage(O, hd)
		O.stamina = math.max(0, O.stamina - (1.5 + dmg * 0.25))
		O.counterUntil = now + 0.55 * (os_.Countering / 70)
		O.balance -= (P.stun or 10) * 0.25
		self:Send({ t = "blocked", who = self:Who(O), punch = ptype })
		if self.tutorial and O == self.P then
			self:TutorialNote({ k = "blocked" })
		end
		self:SetAct(O, "blockhit")
		self:CheckTier(O)
		self:ChainResult(F, O, sp, "blocked")
		return
	elseif O.blocking and body then
		-- elbows in: a good guard takes more off a body shot (the sims had body punchers walking through every
		-- AI at every level: 0.75 flat let through too much)
		dmg *= math.clamp(0.8 - os_.Blocking / 250, 0.45, 0.75)
	end

	-- landed
	F.tally.landed += 1
	F.totals.landed += 1
	F.typeStats.landed += 1
	if counter then
		F.typeStats.counters += 1
	end
	if ptype ~= "jab" then
		F.tally.power += 1
		F.totals.power += 1
	end
	table.insert(O.recentHits, now)
	local kd, severity, fall, cause = false, nil, nil, nil
	-- what the knockdown animation needs to know about this punch (FightMotion.ChooseFall)
	local kdInfo = { ptype = ptype, body = body, hand = F.hand, counter = false, tier = O.tier }
	local rel, liver
	if body then
		F.tally.body += 1
		F.totals.body += 1
		local armor = (type(O.data.mods) == "table" and tonumber(O.data.mods.bodyArmor)) or 1
		-- Body Armor (the ring trait): body shots barely bother him, and drain less of his gas
		local ba = self:Trait(O, "BodyArmor")
		local baCut = Traits.Effect("BodyArmor", "dmg", ba)
		local bd = dmg * 0.8 * (1.2 - os_.Endurance / 200) * (P.body or 1) * armor * (1 - baCut)
		if ba > 0 then
			self:TraitFired(O, "BodyArmor")
		end
		O.body = math.max(0, O.body - bd)
		O.stamina = math.max(0, O.stamina - dmg * 0.6 * (P.body or 1) * (1 - Traits.Effect("BodyArmor", "drain", ba)))
		O.health = math.max(0, O.health - dmg * 0.15)
		O.lastBodyHitAt = now
		-- rib bruising on the side that was hit (a left hand lands on the right flank)
		local rib = F.hand == "L" and "ribsR" or "ribsL"
		O.dmg[rib] = math.min(1, O.dmg[rib] + bd / 55)
		O.dmgDirty = true
		F.damageDealt += bd * 0.5
		O.damageTaken += bd * 0.5
		rel = bd / hdRef * 0.5
		O.balance -= (P.stun or 10) * 0.35 * math.clamp(rel, 0.3, 2)
		dmg = bd
		self:CheckTier(O)
		if O.body <= 0 or (O.body < 25 and bd >= 5 * self.damageScale and self.rng:NextNumber() < 0.22) then
			kd, severity = true, "normal"
		elseif ptype == "leadhook" and F.hand == "L" and O.body < (sp.liver and 85 or 60) and self.allowKD
			and self.rng:NextNumber() < (sp.liver and 0.4 or 0.12) * (1.2 - os_.Endurance / 100) * math.clamp(bd / (5 * self.damageScale), 0.5, 1.5) * (1 - baCut) then
			-- the liver sits under the right ribs: a left hook there drops people a beat AFTER it lands (the
			-- liver-shot special is aimed at it and folds a man who is nowhere near done)
			liver = true
		end
		fall = "knee"
	else
		local chinMul = 1.35 - os_.Chin / 100 * 0.7
		local hd = dmg * HEAD_SCALE * chinMul * (P.head or 1) * (O.dmg.cut > 0.5 and 1.08 or 1) * (1 + KO.tierDamage * O.tier)
		-- Iron Chin (the ring trait): power shots to the head do less, and drop him less; it cracks as his body
		-- and his gas go (the counter is the body work)
		local ic = ptype ~= "jab" and self:Trait(O, "IronChin") or 0
		local icK = 0
		if ic > 0 then
			icK = math.clamp(O.body / 100 + 0.2, 0.3, 1) * (O.stamina < O.maxStam * 0.3 and 0.7 or 1)
			hd *= 1 - Traits.Effect("IronChin", "dmg", ic) * icK
			if hd >= hdRef * 0.8 then
				self:TraitFired(O, "IronChin")
			end
		end
		self:HeadDamage(O, hd)
		O.lastHitAt = now
		F.damageDealt += hd
		O.damageTaken += hd
		dmg = hd
		rel = hd / hdRef
		self:FaceHit(O, F, ptype, hd, hdRef)
		local tierBefore = O.tier
		self:CheckTier(O)
		-- knockdown odds (Config.KOChance): uses the state BEFORE this punch's concussion is added
		if O.health <= 0 then
			kd = true
		else
			-- a fresh fighter only goes down to a true flash: a very clean power counter that catches
			-- him walking onto it (while punching, or as he slips / rolls into it)
			local flashy = counter and ptype ~= "jab" and clean >= 0.7 and (O.state == "punching" or slipping or rolling)
			local p, flash = Config.KOChance({
				tier = O.tier, punch = ptype, hd = hd, hdRef = hdRef, counter = (O.tier > 0 and counter) or flashy,
				chin = os_.Chin, endurance = os_.Endurance, stamina = os_.Stamina, stamPct = O.stamina / O.maxStam,
				power = s.Power, clean = clean, kdTotal = O.kdTotal, conc = O.conc, healthCap = O.healthCap,
				trauma = O.data.trauma, composure = O.data.mental.Composure,
			})
			p *= sp.kd or 1
			if self.tutorial and Tutorial and not O.isPlayer then
				p *= Tutorial.KoMul(self.tutorial)
			end
			-- the ring traits on the knockdown odds (capped together: Traits.CAP.kd)
			local full = p
			local gr = self:Trait(O, "Granite")
			local kdCut = math.min(Traits.CAP.kd, Traits.Effect("IronChin", "kd", ic) * icK + Traits.Effect("Granite", "kd", gr))
			p *= 1 - kdCut
			local kdRoll = self.rng:NextNumber()
			if kdRoll < p then
				kd = true
				severity = (flash and tierBefore == 0) and "flash" or nil
			elseif kdRoll < full then
				-- he should have gone down
				self:TraitFired(O, gr > 0 and "Granite" or "IronChin")
			end
		end
		O.conc = math.min(1, O.conc + hd * CONC.perHeadDamage * (P.ko or 1) * (1.3 - os_.Chin / 150))
		O.concPeak = math.max(O.concPeak, O.conc)
		-- balance: hooks and uppercuts take the legs, footwork keeps them
		local loss = (P.stun or 10) * math.clamp(rel, 0.2, 2.5) * (1.3 - os_.Footwork / 200) * (1 + 0.25 * O.tier) * (counter and 1.3 or 1)
		loss *= 1 - Traits.Effect("Granite", "balance", self:Trait(O, "Granite"))
		O.balance -= loss
		if kd then
			severity = severity or self:Severity(O, rel)
			fall = fallFor(ptype, false, severity)
		end
	end
	local heavy = (body and dmg >= 7 * self.damageScale) or (not body and (rel >= 2 or (counter and rel >= 1.75)))
	if heavy then
		O.hurtUntil = now + 1.4 + rel * 0.6
	end
	-- the momentum swings with the work: a clean shot, more for a big one and for a counter
	self:Swing(F, 0.02 + 0.015 * math.min(rel, 2) + (counter and 0.04 or 0) + (heavy and 0.04 or 0))
	local sev = math.clamp(rel * 0.6 * (counter and 1.15 or 1), 0, 1.5)
	if body then
		self:SetAct(O, string.format("hitbody|%s|%s|%.2f", ptype, F.hand == "L" and "R" or "L", sev))
	else
		self:SetAct(O, string.format("hit|%s|%s|%.2f|%s", ptype, heavy and "heavy" or (counter and "counter" or "head"), sev, F.hand or "R"))
	end
	-- a medium-or-worse shot cancels the special the other man was still throwing (the Animator drops it too)
	if O.special and sev >= 0.35 then
		O.special = nil
		O.shellUntil = 0
		O.busyUntil = math.min(O.busyUntil, now + 0.3)
	end
	self:Send({
		t = "hit", who = self:Who(F), punch = ptype, body = body, dmg = math.floor(dmg * 10) / 10, counter = counter, heavy = heavy,
		hand = F.hand, sev = math.floor(sev * 100) / 100, bleed = (O.dmg.cut > 0.35 or O.dmg.cut2 > 0.35 or O.dmg.noseBleed > 0.4),
		special = sp.id, kind = P.kind, caught = caught or nil, chain = item and item.n or nil,
	})
	self:ChainResult(F, O, sp, "landed")
	if caught and O.isPlayer then
		self:SendTo(O, { t = "announce", text = "CAUGHT MID-DODGE!" })
	end
	if heavy then
		local name = Config.PunchNames[ptype]
		self:Comment(string.format("%s lands a %s%s%s!", F.data.name, counter and "counter " or "", body and "body " or "", name:lower()), counter)
	end

	-- legs: a fighter whose balance runs out stumbles; at severe danger the legs simply go
	if not kd and O.balance < 30 and O.state ~= "down" then
		if O.balance < 0 and O.tier >= 2 then
			kd, severity, fall, cause = true, "normal", "knee", "legs"
		else
			local away = unitOr(flat(O.root and F.root and (O.root.Position - F.root.Position) or Vector3.zero), Vector3.new(0, 0, 1))
			if P.kind == "hook" and F.root then
				-- a hook spins the target toward the side it came from
				local lateral = flat(F.root.CFrame.RightVector) * (F.hand == "L" and 1 or -1)
				away = unitOr(away * 0.7 + lateral * 0.6, away)
			end
			self:Stumble(O, away, math.clamp(0.4 + rel * 0.35 + O.tier * 0.15, 0.3, 1.5))
			self:Swing(F, 0.06)
		end
	end

	-- the tutorial: the player never goes down, the opponent only once the last step is up
	if self.tutorial and Tutorial and (kd or liver) and self:Protected(O) then
		kd, liver = false, nil
		O.health = math.max(O.health, 25)
		O.body = math.max(O.body, 25)
		O.balance = math.max(O.balance, 60)
		self:CheckTier(O)
	end
	if liver and not kd then
		local fightId = self.id
		task.delay(0.6, function()
			if self.id == fightId and not self.finished and self.live and not self.paused and O.state ~= "down" then
				self:Comment("Delayed reaction... that's the LIVER! " .. O.data.name .. " folds up!", true)
				O.kdInfo = { ptype = ptype, body = true, hand = F.hand, tier = O.tier }
				self:Knockdown(O, F, "normal", "knee", "liver")
			end
		end)
	end
	if kd then
		if self.allowKD then
			kdInfo.counter = counter
			O.kdInfo = kdInfo
			self:Knockdown(O, F, severity or "normal", fall or "back", cause)
		else
			-- sparring: the coach steps in instead of a knockdown
			O.health = math.max(O.health, 18)
			O.body = math.max(O.body, 20)
			O.balance = 100
			self:CheckTier(O)
			self:Send({ t = "announce", text = "COACH: \"Time! Take a breather.\"" })
			if self.spar == "Medium" or self.spar == "PvP" then
				self:End(F, "Stopped", "Coach stops the sparring session")
			else
				O.hurtUntil = now + 2
			end
		end
	end
end

function Fight:Miss(F, O, ptype, why)
	F.stamina = math.max(0, F.stamina - 1)
	if why == "miss" and O.data.stats.Countering > 55 then
		O.counterUntil = self:Now() + 0.45
	end
	-- whiffing a big shot pulls the fighter off balance (worse when gassed or dazed)
	if why ~= "short" and Config.Punches[ptype].kind ~= "straight" then
		local gassed = F.stamina < F.maxStam * 0.25
		F.balance -= (gassed and 15 or 10) * (1 + 0.25 * F.tier)
		if F.balance < 30 and F.root then
			self:Stumble(F, flat(F.root.CFrame.LookVector), gassed and 0.6 or 0.4)
		end
	end
	self:Send({ t = "miss", who = self:Who(F), why = why })
end

-- balance loss: a short involuntary stagger. NPCs glide on the server; the player's character is
-- client-owned, so the client drives it (Humanoid:Move) from the 'stumble' message.
function Fight:Stumble(F, dir, sev)
	if F.state == "down" or F.state == "clinch" or self.finished or not F.root then
		return
	end
	local now = self:Now()
	if now < F.stumbleUntil then
		return
	end
	sev = math.clamp(sev or 0.5, 0.2, 1.5)
	dir = unitOr(flat(dir), flat(-F.root.CFrame.LookVector))
	local dur = 0.45 + 0.35 * sev
	F.stumbleUntil = now + dur
	F.busyUntil = math.max(F.busyUntil, now + dur * 0.8)
	F.blocking = false
	if F.state ~= "punching" then
		F.state = "idle"
	end
	F.balance = math.max(F.balance, 55)
	F.stumbles += 1
	F.strain = math.max(F.strain, 0.5)
	local look, right = flat(F.root.CFrame.LookVector), flat(F.root.CFrame.RightVector)
	local fwd, lat = dir:Dot(look), dir:Dot(right)
	local letter = "B"
	if math.abs(lat) > math.abs(fwd) or fwd > 0 then
		letter = lat >= 0 and "R" or "L"
	end
	self:SetAct(F, string.format("stumble|%s|%.2f|%.2f", letter, sev, dur))
	F.stumbleSpeed = 6 + 5 * sev
	if not F.isPlayer then
		F.stumbleVel = dir * F.stumbleSpeed
	end
	self:Send({ t = "stumble", who = self:Who(F), dir = { x = dir.X, z = dir.Z }, dur = dur, sev = sev })
	if sev >= 0.8 then
		self:Comment(F.data.name .. " is stumbling! The legs are not there!")
	end
end

function Fight:SetBlock(F, on)
	if not self:CanAct(F) then
		return
	end
	if on and self:Now() < F.busyUntil and F.state == "punching" then
		return
	end
	if on and self:IsStumbling(F) then
		return
	end
	local was = F.blocking
	F.blocking = on and true or false
	if F.state ~= "punching" then
		F.state = on and "blocking" or "idle"
	end
	if F.blocking and not was then
		self:NoteDefense(F, "block", 0)
	end
end

-- a dodge window's share for F right now: pinned on the ropes he has less room (a Ring General slides off them)
function Fight:EvadeMul(F)
	if F.onRopes then
		return 1 - 0.15 * self:RopeMul(F)
	end
	return 1
end

-- cancel = a new dodge may replace a defence started less than Evasion.CANCEL ago (the pad's flick-then-button
-- chords: the flick's slip, roll or parry turns into the weave, the duck, the pull or the side-step), with half
-- the first one's stamina back; a punch's recovery is never cancelled
local function defenseReady(self, F, cost, cancel)
	if not self:CanAct(F) then
		return false
	end
	local now = self:Now()
	local cancelling = false
	if now < F.busyUntil then
		if not (cancel and F.state ~= "punching" and not F.defCancelled and now - F.defAt < Evasion.CANCEL) then
			return false
		end
		cancelling = true
	end
	if F.stamina + (cancelling and F.defCost * 0.5 or 0) < cost then
		return false
	end
	if cancelling then
		F.stamina += F.defCost * 0.5
		F.slipUntil, F.rollUntil, F.parryUntil, F.pivotEvadeUntil, F.dodgeUntil = 0, 0, 0, 0, 0
	end
	F.stamina -= cost
	F.blocking = false
	F.state = "idle"
	F.defAt, F.defCost, F.defCancelled = now, cost, cancelling
	F.dodges += 1
	return true
end

function Fight:Slip(F, dir)
	if not defenseReady(self, F, Evasion.Moves.slip.stam) then
		return
	end
	local now = self:Now()
	F.slipUntil = now + Evasion.Window("slip", F.data.stats, self:DefenseMul(F)) * self:EvadeMul(F)
	F.busyUntil = now + Evasion.Moves.slip.recover
	F.dodgeKind, F.dodgeUntil, F.dodgeEnd = "slip", F.slipUntil, F.busyUntil
	F.slipAt = now -- a counter jab / cross may come straight out of this slip (Punch)
	F.slipDir = dir == -1 and -1 or 1
	self:NoteDefense(F, "slip", F.slipDir)
	self:SetAct(F, "slip|" .. (dir == -1 and "L" or "R"))
	if self.tutorial and F == self.P then
		self:TutorialNote({ k = "slip" })
	end
end

-- quick = the quick dodge (Shift + Space): a shorter window, a quicker recovery, cheaper
function Fight:Roll(F, quick)
	if not defenseReady(self, F, quick and 3 or Evasion.Moves.roll.stam) then
		return
	end
	local now = self:Now()
	F.rollUntil = now + (quick and (Evasion.Window("roll", F.data.stats, self:DefenseMul(F)) - 0.1) or Evasion.Window("roll", F.data.stats, self:DefenseMul(F))) * self:EvadeMul(F)
	F.busyUntil = now + (quick and 0.36 or Evasion.Moves.roll.recover)
	F.dodgeKind, F.dodgeUntil, F.dodgeEnd = "roll", F.rollUntil, F.busyUntil
	self:NoteDefense(F, "roll", 0)
	self:SetAct(F, "roll")
	if self.tutorial and F == self.P then
		self:TutorialNote({ k = "roll" })
	end
end

-- the dodges of Shared.Evasion beyond the slip and the roll: weave (dir), duck, pull, side-step (dir). The act
-- (Evasion.Act: weave|L, duck, pull, sidestep|R) is the Animator's; the evade window, the recovery (a punch that
-- lands after the window but inside it CATCHES him) and the stamina are Evasion's; a side-step also moves him off
-- the line (as the pivot does, sideways) and leaves him at an angle
function Fight:Dodge(F, kind, dir)
	if kind == "slip" then
		return self:Slip(F, dir)
	elseif kind == "roll" then
		return self:Roll(F, false)
	end
	local E = Evasion.Moves[kind]
	if not E or not defenseReady(self, F, E.stam, true) then
		return
	end
	local now = self:Now()
	dir = dir == -1 and -1 or 1
	F.dodgeKind = kind
	F.dodgeUntil = now + Evasion.Window(kind, F.data.stats, self:DefenseMul(F)) * self:EvadeMul(F)
	F.busyUntil = now + E.recover
	F.dodgeEnd = F.busyUntil
	self:NoteDefense(F, kind, dir)
	if kind ~= "sidestep" then
		F.slipAt = now -- (a counter jab / cross may come straight out of the head movement, as out of a slip)
	else
		F.angleUntil = now + E.angle
		local O = self:Other(F)
		if F.root and O.root then
			local toward = unitOr(flat(O.root.Position - F.root.Position), flat(F.root.CFrame.LookVector))
			local side = Vector3.new(-toward.Z, 0, toward.X) * dir
			local goal = self:ClampToRing(F.root.Position + side * E.step)
			local d = flat(goal - F.root.Position)
			if d.Magnitude > 0.1 then
				local dur = 0.22
				F.lungeUntil = now + dur
				F.lungeVel = d.Unit * (d.Magnitude / dur)
				self:Send({ t = "lunge", who = self:Who(F), dir = { x = d.Unit.X, z = d.Unit.Z }, dur = dur, speed = d.Magnitude / dur })
			end
		end
	end
	self:SetAct(F, Evasion.Act(kind, dir, E.recover))
	if self.tutorial and F == self.P then
		self:TutorialNote({ k = "dodge", kind = kind })
	end
end

function Fight:Parry(F)
	if not defenseReady(self, F, 2) then
		return
	end
	local now = self:Now()
	F.parryUntil = now + (0.18 + F.data.stats.Reflexes * 0.002) * self:DefenseMul(F) * self:EvadeMul(F)
	F.busyUntil = now + 0.32
	self:NoteDefense(F, "parry", 0)
	self:SetAct(F, "parry|" .. (F.hand == "L" and "R" or "L"))
end

function Fight:Pivot(F, dir)
	local now = self:Now()
	if now < F.nextPivot or not defenseReady(self, F, 5) then
		return
	end
	F.nextPivot = now + 1.2
	F.busyUntil = now + 0.35
	F.pivotEvadeUntil = now + 0.25 * self:DefenseMul(F)
	self:NoteDefense(F, "pivot", dir == -1 and -1 or 1)
	F.angleUntil = now + 1.1
	local O = self:Other(F)
	if F.root and O.root then
		local offset = flat(F.root.Position - O.root.Position)
		if offset.Magnitude > 0.1 then
			local ang = math.rad(38) * (dir == -1 and -1 or 1)
			local rotated = CFrame.Angles(0, ang, 0):VectorToWorldSpace(offset)
			local target = self:ClampToRing(O.root.Position + rotated)
			local y = F.root.Position.Y
			F.model:PivotTo(CFrame.lookAt(Vector3.new(target.X, y, target.Z), Vector3.new(O.root.Position.X, y, O.root.Position.Z)))
		end
	end
	self:SetAct(F, "pivot|" .. (dir == -1 and "L" or "R"))
end

function Fight:CanClinch(F)
	local O = self:Other(F)
	return self:CanAct(F) and O.state ~= "down" and self:Now() >= F.nextClinch and F.stamina >= 4 and self:Distance(F, O) < self:ClinchRange(F)
end

function Fight:Clinch(F)
	if F.state == "clinch" then
		-- the clinch key in a clinch: break it with a shove (Fight:BreakClinch)
		return self:BreakClinch(F)
	end
	if not self:CanClinch(F) then
		return
	end
	local O = self:Other(F)
	local now = self:Now()
	F.stamina -= 4
	F.nextClinch = now + 6
	F.tally.clinches += 1
	for _, X in ipairs({ F, O }) do
		X.state = "clinch"
		X.blocking = false
		X.clinchUntil = now + 1.8
		X.busyUntil = now + 1.9
		X.stumbleUntil = 0
		X.stumbleVel = nil
		X.strain = math.max(X.strain, 0.8)
		X.clinchHits, X.clinchNext, X.clinchAt = 0, now + 0.3, now
	end
	-- holding buys a hurt fighter time: a little head HP, the legs come back
	self.clinchBy = F
	self:ClearStun(F, 6 + 3 * F.tier)
	F.balance = math.min(100, F.balance + 25)
	F.hurtUntil = math.min(F.hurtUntil, now + 0.6)
	self:CheckTier(F)
	self:TieUp()
	self:Send({ t = "announce", text = self.spar and "COACH: \"Break! Let go, work your way out.\"" or "CLINCH! The referee steps in..." })
	self:Comment(F.data.name .. " ties up. Smart veteran move.")
end

-- the tie-up: a clinch starts from anywhere inside the clinch range (out to 4.8 x the rig factor, with
-- arms that only wrap at close quarters) or, pinned on the ropes or between two players, from inside the
-- chests. The pair closes to (or opens out to) the clinch distance over a short slide: the AI side moves,
-- two players meet halfway (neither can walk while they hold), and a player pinned against an AI on the
-- ropes gives back what the ropes do not let the AI take.
function Fight:TieUp()
	local P, O = self.P, self.O
	if not (P.root and O.root) then
		return
	end
	local want = self:ClinchSep()
	local d = flat(O.root.Position - P.root.Position)
	local m = d.Magnitude
	if math.abs(m - want) < 0.1 then
		return
	end
	-- (Separate leaves the opening out to the slide meanwhile: its clinch floor would jump a deep-chested
	-- pair apart in one frame, up to 0.57 studs, and the feet would skate)
	self.tieUntil = self:Now() + 0.5
	local dir = m > 0.05 and d.Unit or flat(P.root.CFrame.LookVector).Unit
	if P.isPlayer and O.isPlayer then
		-- each takes half: P along -dir when opening out (m < want), along +dir when closing in
		local half = (m - want) / 2
		self:Glide(P, self:ClampToRing(P.root.Position + dir * half), 10)
		self:Glide(O, self:ClampToRing(O.root.Position - dir * half), 10)
		return
	end
	local mover, still = O, P
	if not P.isPlayer and O.isPlayer then
		mover, still = P, O
	end
	local away = mover == O and dir or -dir -- from the still man to the mover
	local goal = self:ClampToRing(still.root.Position + away * want)
	self:Glide(mover, goal, 10)
	-- the ropes stop the mover short of the distance: the still man gives back the rest
	local short = want - flat(goal - still.root.Position).Magnitude
	if short > 0.1 then
		self:Glide(still, self:ClampToRing(still.root.Position - away * short), 10)
	end
end

-- Inside the clinch (Config.FightDepth): a punch is a short shot to the body - a fraction of a punch, one every
-- clinchGap seconds, at most clinchMax a clinch (then the referee breaks them). The man who tied up is holding:
-- his arms smother clinchSmother of what comes at him. It wears the body and the gas, and the judges see a
-- little of it (tally.inside).
function Fight:ClinchWork(F, ptype)
	local O = self:Other(F)
	local now = self:Now()
	if O.state ~= "clinch" or now < F.clinchNext or F.stamina < 2 or F.clinchHits >= DEPTH.clinchMax or now >= F.clinchUntil then
		return
	end
	F.clinchNext = now + DEPTH.clinchGap
	F.clinchHits += 1
	F.stamina -= 1.5
	local P = Config.Punches[ptype] or Config.Punches.leadhook
	local s, os_ = F.data.stats, O.data.stats
	local dmg = P.dmg * DEPTH.clinchDmg * (0.55 + s.Power / 110) * F.style.fight.inside * F.classScale * self.damageScale
	if self.clinchBy == O then
		dmg *= 1 - DEPTH.clinchSmother
	end
	dmg *= 1 - Traits.Effect("BodyArmor", "dmg", self:Trait(O, "BodyArmor"))
	if self.tutorial and Tutorial then
		dmg *= Tutorial.DamageMul(self.tutorial, O.isPlayer)
	end
	local bd = dmg * (1.2 - os_.Endurance / 200)
	O.body = math.max(1, O.body - bd)
	O.stamina = math.max(0, O.stamina - dmg * 0.5)
	O.lastBodyHitAt = now
	F.tally.inside = (F.tally.inside or 0) + 1
	F.damageDealt += bd * 0.5
	O.damageTaken += bd * 0.5
	F.hand = F.hand == "L" and "R" or "L"
	self:SetAct(F, string.format("uppercut|%s|body|0.18|0.35", F.hand))
	self:SetAct(O, string.format("hitbody|%s|%s|%.2f", ptype, F.hand == "L" and "R" or "L", 0.15))
	self:Send({ t = "inside", who = self:Who(F), dmg = math.floor(bd * 10) / 10 })
	self:Swing(F, 0.01)
	if F.clinchHits >= DEPTH.clinchMax then
		-- holding and hitting: the referee breaks them
		self:Send({ t = "announce", text = self.spar and "COACH: \"Break!\"" or "BREAK! The referee pulls them apart." })
		for _, X in ipairs({ F, O }) do
			X.clinchUntil = math.min(X.clinchUntil, now)
			X.busyUntil = math.min(X.busyUntil, now + 0.2)
		end
	end
end

-- The clinch key in a clinch: a shove off the break (after clinchMinHold seconds of it). The pair let go, the
-- other man is pushed back a step and off balance for a moment, the breaker comes off at an angle
function Fight:BreakClinch(F)
	local O = self:Other(F)
	local now = self:Now()
	if F.state ~= "clinch" or now - F.clinchAt < DEPTH.clinchMinHold or F.stamina < 3 or self.finished then
		return false
	end
	F.stamina -= 3
	for _, X in ipairs({ F, O }) do
		X.state = "idle"
		X.clinchUntil = now
		X.busyUntil = math.min(X.busyUntil, now + 0.1)
	end
	O.busyUntil = now + DEPTH.breakBusy
	O.balance = math.max(20, O.balance - DEPTH.breakBalance)
	F.angleUntil = now + DEPTH.breakAngle
	F.nextClinch = math.max(F.nextClinch, now + 2)
	if O.root and F.root and not O.isPlayer then
		local away = unitOr(flat(O.root.Position - F.root.Position), flat(F.root.CFrame.LookVector))
		self:Glide(O, self:ClampToRing(O.root.Position + away * 1.2), 9)
	end
	self:SetAct(F, "pivot|" .. (self.rng:NextNumber() < 0.5 and "L" or "R"))
	self:Send({ t = "announce", text = "OFF THE BREAK!" })
	self:Comment(F.data.name .. " shoves off and comes out at an angle!")
	return true
end

------------------------------------------------------------------------
-- Referee (a real Builder NPC in the ring: moves with the action, counts, waves it off)
------------------------------------------------------------------------
-- who runs the ring: a fight-night referee, or in a gym spar the coach (older, gym polo + towel)
function Fight:Official(capital)
	if self.spar then
		return capital and "The coach" or "the coach"
	end
	return capital and "The referee" or "the referee"
end

-- Collision groups: the referee walks through both fighters (he never shoves the NPC or jitters
-- against the player in a clinch) and still stands on the canvas like any NPC. The Humanoid turns
-- CanCollide back on for his head / torso every step, so a group is the only lasting way; it costs
-- nothing per frame. Fighters join "Boxers" for the fight (they still collide with each other and the
-- world) and get their old group back in Cleanup. nil = not tried yet, false = unavailable (the
-- per-step CanCollide fallback runs then).
local REF_GROUP, BOXER_GROUP = "Referee", "Boxers"
local groupsReady
local function ensureGroups()
	if groupsReady == nil then
		local ok, err = pcall(function()
			for _, g in ipairs({ REF_GROUP, BOXER_GROUP }) do
				if not PhysicsService:IsCollisionGroupRegistered(g) then
					PhysicsService:RegisterCollisionGroup(g)
				end
			end
			PhysicsService:CollisionGroupSetCollidable(REF_GROUP, BOXER_GROUP, false)
		end)
		groupsReady = ok
		if not ok then
			warn("[Boxer] referee collision group unavailable, using the per-step fallback:", err)
		end
	end
	return groupsReady
end

-- puts a fighter's colliding parts in "Boxers", remembering the group each had
local function joinBoxers(F)
	if not F.model or F.groupWas then
		return
	end
	F.groupWas = {}
	for _, d in ipairs(F.model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Parent == F.model or d.CanCollide) then
			F.groupWas[d] = d.CollisionGroup
			d.CollisionGroup = BOXER_GROUP
		end
	end
end

local function leaveBoxers(F)
	local was = F.groupWas
	F.groupWas = nil
	if was then
		for part, g in pairs(was) do
			if part.Parent then
				part.CollisionGroup = g
			end
		end
	end
end

function Fight:SpawnReferee()
	local ok, model = pcall(function()
		-- (Officials: the look, the drawn face, the venue's / a title fight's shirt; the mesh outfit is BuilderBody's)
		local kind = self.spar and "cornerman" or "referee"
		local app, build, gear, opts = Officials.Look(self.rng:NextInteger(1, 2 ^ 30), kind, { venue = self.venue, kind = self.offerKind })
		return Builder.CreateNPC(app, build, gear, "Referee", opts)
	end)
	if not ok or not model then
		warn("[Boxer] referee could not be built:", model)
		return
	end
	model.Name = "Referee"
	-- never part of the fight physics: fighters walk straight through him
	local solid = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			if d.Parent == model then
				table.insert(solid, d)
			end
		end
	end
	local center = self.anchors.RingCenter.Position
	local spot = self.arena:FindFirstChild("RefereeSpot", true)
	local pos = spot and spot:IsA("BasePart") and spot.Position or (center + Vector3.new(4.5, 0, 0))
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	local y = center.Y + standHeight(hum, root)
	model:PivotTo(CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(center.X, y, center.Z)))
	model.Parent = self.arena
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local R = { model = model, root = root, hum = hum, actId = 0, nextMove = 0 }
	if ensureGroups() then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CollisionGroup = REF_GROUP
			end
		end
		joinBoxers(self.P)
		joinBoxers(self.O)
	else
		-- fallback: the Humanoid turns CanCollide back on for the head / torso parts in its own step;
		-- re-clear the rig parts before every physics step
		R.noclip = RunService.Stepped:Connect(function()
			if not model.Parent then
				if R.noclip then
					R.noclip:Disconnect()
				end
				return
			end
			for _, part in ipairs(solid) do
				part.CanCollide = false
			end
		end)
	end
	if hum and root then
		hum.WalkSpeed = 11
		hum.AutoRotate = false
		local att = Instance.new("Attachment")
		att.Name = "RefFacingAtt"
		att.Parent = root
		local ao = Instance.new("AlignOrientation")
		ao.Name = "RefFacing"
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.MaxTorque = math.huge
		ao.Responsiveness = 18
		ao.Parent = root
		R.align = ao
	end
	model:SetAttribute("Loop", "referee")
	CollectionService:AddTag(model, "Referee")
	self.ref = R
end

function Fight:RefAct(act)
	local R = self.ref
	if R and R.model.Parent then
		R.actId += 1
		R.model:SetAttribute("Act", act)
		R.model:SetAttribute("ActId", R.actId)
	end
end

function Fight:UpdateReferee(now)
	local R = self.ref
	if not (R and R.root and R.hum and R.model.Parent) or now < R.nextMove then
		return
	end
	R.nextMove = now + 0.3
	local P, O = self.P, self.O
	if not (P.root and O.root) then
		return
	end
	local target, look
	local down = (P.state == "down" and P) or (O.state == "down" and O) or nil
	local catching = R.catching
	if catching and now > catching.untilT then
		R.catching = nil
		catching = nil
	end
	if catching then
		-- holding up a fighter knocked out on his feet
		target, look = catching.at, catching.look
		R.nextMove = now + 0.1
		if R.hum and R.hum.WalkSpeed < 16 then
			R.hum.WalkSpeed = 16
		end
	elseif down then
		-- stand over the downed fighter, between him and the other man (who is in the neutral corner)
		local other = self:Other(down)
		local d = unitOr(flat(other.root.Position - down.root.Position), Vector3.new(1, 0, 0))
		target = down.root.Position + d * 3
		look = down.root.Position
	else
		local mid = (P.root.Position + O.root.Position) / 2
		local line = unitOr(flat(O.root.Position - P.root.Position), Vector3.new(1, 0, 0))
		local perp = Vector3.new(-line.Z, 0, line.X)
		if P.state == "clinch" then
			target = mid + perp * 1.6 -- steps in to break them
		else
			-- off the fight line, on the side nearer the ring centre so he never ends up on the ropes
			local c = self.anchors.RingCenter.Position
			local a, b = mid + perp * 4.5, mid - perp * 4.5
			R.side = R.side or 1
			local cur, alt = R.side == 1 and a or b, R.side == 1 and b or a
			if flat(alt - c).Magnitude + 1.5 < flat(cur - c).Magnitude then
				R.side = -R.side
				cur = alt
			end
			target = cur
		end
		look = mid
	end
	target = self:ClampToRing(target)
	local p = R.root.Position
	if flat(target - p).Magnitude > (catching and 0.3 or 0.8) then
		R.hum:MoveTo(Vector3.new(target.X, p.Y, target.Z))
	end
	if R.align then
		local dir = flat(look - p)
		if dir.Magnitude > 0.1 then
			R.align.CFrame = CFrame.lookAt(Vector3.zero, dir.Unit)
		end
	end
end

------------------------------------------------------------------------
-- Knockdowns & stoppages
------------------------------------------------------------------------
-- out-cold knockouts ragdoll the NPC on the server (the player's own rig is ragdolled by FightClient,
-- because the client owns its physics). The NPC is destroyed with the arena, so nothing is restored.
function Fight:Ragdoll(F)
	if F.isPlayer or not F.model then
		return
	end
	local ok, err = pcall(function()
		if F.hum then
			-- the Neck motor is disabled below: with RequiresNeck on the Humanoid would die, and BreakJointsOnDeath
			-- would then snap the cosmetic face / hair Motor6Ds under BoxerLook while the KO is on camera
			F.hum.RequiresNeck = false
			F.hum.BreakJointsOnDeath = false
		end
		for _, m in ipairs(F.model:GetDescendants()) do
			-- only the R15 rig joints (cosmetic FaceJoint / HairJoint motors live deeper, under BoxerLook)
			if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Parent and m.Parent.Parent == F.model and m.Name ~= "Root" then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagA0"
				a0.CFrame = m.C0
				a0.Parent = m.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagA1"
				a1.CFrame = m.C1
				a1.Parent = m.Part1
				local bs = Instance.new("BallSocketConstraint")
				bs.Name = "Ragdoll"
				bs.LimitsEnabled = true
				bs.UpperAngle = m.Name == "Neck" and 35 or 65
				bs.TwistLimitsEnabled = true
				bs.TwistLowerAngle = -25
				bs.TwistUpperAngle = 25
				bs.Attachment0 = a0
				bs.Attachment1 = a1
				bs.Parent = m.Parent
				m.Enabled = false
				m.Part1.CanCollide = true
			end
		end
		if F.hum then
			F.hum.PlatformStand = true
			F.hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
		if F.align then
			F.align.Enabled = false
		end
	end)
	if not ok then
		warn("[Boxer] ragdoll failed:", err)
	end
end

-- room (studs, centre to centre) a fall that folds forward needs in front of the man going down: the
-- attacker backs off to it. A face-first timber fall goes diagonally past him (FightMotion), the
-- others fold onto the hands / knees / into the referee's arms just in front of the feet
-- (FightMotion.FALL_ROOM, scaled by the fallen man's height: F.bodyK)
local FALL_ROOM = FightMotion and FightMotion.FALL_ROOM or { face = 5.0, forward = 4.2, standing = 5.0, knee = 3.8, flash = 3.8 }

-- walks a fighter's root over the canvas at a walking pace (never a teleport): the Animator senses the
-- motion and gives him real steps. The speed ramps up and brakes into the spot; a newer glide or a
-- Place cancels it. onArrive runs when he gets there.
function Fight:Glide(F, goal, speed, onArrive)
	if not (F.root and F.model) then
		return
	end
	F.glideId = (F.glideId or 0) + 1
	local id, fightId = F.glideId, self.id
	task.spawn(function()
		local v, acc = 0, speed * 4
		while F.glideId == id and self.id == fightId and not self.aborted and F.root and F.root.Parent do
			local dt = RunService.Heartbeat:Wait()
			local d = flat(goal - F.root.Position)
			local m = d.Magnitude
			-- brake into the spot (v^2 = 2 a s), never slower than a shuffle until there
			v = math.min(speed, v + acc * dt, math.sqrt(2 * acc * m))
			local step = math.max(v, 0.8) * dt
			if m <= step then
				shift(F, d)
				if onArrive then
					onArrive()
				end
				break
			end
			shift(F, d * (step / m))
		end
	end)
end

-- the fall for this knockdown (FightMotion when present, else the round-1 pose)
function Fight:ChooseFall(F, by, severity, cause, fall)
	local info = F.kdInfo or {}
	F.kdInfo = nil
	local legacy = { pose = fall or "back", dir = (fall == "face" or fall == "knee") and 0 or math.pi, dist = 20, ko = nil }
	if not (FightMotion and FightMotion.ChooseFall) then
		return legacy
	end
	local P = info.ptype and Config.Punches[info.ptype]
	local vr, ar = F.root, by and by.root
	local c = self.anchors and self.anchors.RingCenter
	local yaw
	if vr then
		local look = vr.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end
	local ok, res = pcall(FightMotion.ChooseFall, {
		ptype = info.ptype, kind = P and P.kind or nil, body = info.body, hand = info.hand, severity = severity,
		cause = cause, tier = info.tier, counter = info.counter,
		victimX = vr and vr.Position.X, victimZ = vr and vr.Position.Z, victimYaw = yaw,
		attackerX = ar and ar.Position.X, attackerZ = ar and ar.Position.Z,
		ringX = c and c.Position.X, ringZ = c and c.Position.Z, ringHalf = self.ringHalf,
		roll = self.rng:NextNumber(), roll2 = self.rng:NextNumber(),
	})
	if ok and type(res) == "table" and FightMotion.ValidFall[res.pose] then
		return res
	end
	return legacy
end

-- a knockout on the feet: the referee rushes in, gets his arms round the fighter and holds him up. He
-- stands chest to chest at arm's length (2.4 studs, centre to centre: two torsos plus the arms between
-- them); the fighter sags forward into him
local CATCH_DIST = FightMotion and FightMotion.CATCH_DIST or 2.4
function Fight:RefCatch(F)
	local R = self.ref
	if not (R and R.root and R.model.Parent and F.root) then
		return
	end
	local other = self:Other(F)
	local toward = other.root and flat(other.root.Position - F.root.Position) or flat(F.root.CFrame.LookVector)
	local d = unitOr(toward, Vector3.new(1, 0, 0))
	R.catching = { at = self:ClampToRing(F.root.Position + d * CATCH_DIST * (F.bodyK or 1)), look = F.root.Position, untilT = self:Now() + 6 }
	R.nextMove = 0
	self:RefAct(string.format("catch|%.1f", (FightMotion and FightMotion.CATCH_TIME or 2) + 1.4))
end

function Fight:Knockdown(F, by, severity, fall, cause)
	if F.state == "down" or self.finished then
		return
	end
	if self.tutorial and Tutorial then
		if self:Protected(F) then
			return -- (the tutorial: see Resolve; a stray caller is refused here too)
		end
		if not F.isPlayer then
			self:TutorialNote({ k = "kd" })
		end
	end
	severity = severity or "normal"
	fall = fall or "back"
	F.state = "down"
	F.blocking = false
	F.kdRound += 1
	F.kdTotal += 1
	F.mash = 0
	F.downSeverity = severity
	F.stumbleUntil = 0
	F.stumbleVel = nil
	F.exprOverride = nil
	local add = severity == "flash" and CONC.perFlashKnockdown or CONC.perKnockdown
	if severity == "heavy" then
		add += 0.08
	elseif severity == "out" then
		add += 0.2
	end
	F.conc = math.min(1, F.conc + add)
	F.concPeak = math.max(F.concPeak, F.conc)
	by.tally.kd += 1
	self:Swing(by, severity == "flash" and 0.25 or 0.4)
	-- how he goes down (R-anim FightMotion: the punch, the severity, where he stands in the ring)
	local choice = self:ChooseFall(F, by, severity, cause, fall)
	fall = choice.pose
	F.koKind = choice.ko
	table.insert(self.knockdowns, { who = self:Who(F), severity = severity, fall = fall, round = self.round, cause = cause })
	self.kdHold = true
	self.paused = true
	-- DownPose (+ DownDir / DownDist / KOKind) before Guard = "down" so the Animator picks the right
	-- fall on the first frame
	setAttr(F.model, "DownPose", fall)
	setAttr(F.model, "DownDir", choice.dir)
	setAttr(F.model, "DownDist", choice.dist)
	setAttr(F.model, "KOKind", severity == "out" and choice.ko or nil)
	setAttr(F.model, "Count", 0)
	self:UpdateGuard(F)
	self:SyncAttrs(F)
	if severity == "out" and F.isPlayer and F.hum then
		-- belt and braces for FightClient's ragdoll (it disables the Neck motor): a neckless death would
		-- fire Main's Died -> Abort before End records the KO. Replicates ahead of the kd message.
		F.hum.RequiresNeck = false
		F.neckOff = true
	end
	-- anim = true: the knockout is animated on every client (FightClient skips its physics ragdoll)
	local animKO = severity == "out" and FightMotion ~= nil and FightMotion.ANIMATED_KO == true
	self:Send({ t = "kd", who = self:Who(F), severity = severity, fall = fall, ko = choice.ko, anim = animKO or nil })
	local NAME = F.data.name:upper()
	if severity == "flash" then
		self:Comment("Flash knockdown! " .. F.data.name .. " is down - more surprised than hurt!", true)
	elseif severity == "out" then
		self:Comment(NAME .. " IS OUT COLD! THE REFEREE DOESN'T EVEN COUNT!", true)
	elseif severity == "heavy" then
		self:Comment("DOWN GOES " .. NAME .. "! WHAT A SHOT!", true)
	elseif cause ~= "liver" then
		self:Comment("DOWN GOES " .. NAME .. "!", true)
	end
	-- a man folding forward goes past the one who dropped him, not through him: the attacker backs off a
	-- step to give the fall its room (a walk the Animator turns into real steps, never a teleport)
	-- (a knocked-out man does not stop on his hands: a forward knockout goes all the way to the face)
	local room = FALL_ROOM[(severity == "out" and fall == "forward") and "face" or fall]
	room = room and room * (F.bodyK or 1)
	if room and F.root and by.root then
		local d = flat(F.root.Position - by.root.Position)
		if d.Magnitude > 0.05 and d.Magnitude < room then
			self:Glide(by, self:ClampToRing(by.root.Position - d.Unit * (room - d.Magnitude)), 6)
		end
	end
	-- driven into the ropes / the corner: his root really staggers there (the body never drifts away from
	-- it, so the get-up does not slide), and the ropes take the impact
	if choice.moveX and choice.moveZ and F.root then
		local fightId = self.id
		local goal = self:ClampToRing(F.root.Position + Vector3.new(choice.moveX, 0, choice.moveZ))
		self:Glide(F, goal, math.clamp((choice.dist or 1) / 0.45, 3, 9), function()
			if self.id == fightId and not self.finished then
				self:Send({ t = "ropes", who = self:Who(F) })
			end
		end)
	end
	if severity == "out" then
		if not animKO then
			self:Ragdoll(F)
		end
		if choice.ko == "standing" then
			-- out on his feet: the referee rushes in and catches him before he waves it off
			self:RefCatch(F)
			task.wait(FightMotion and FightMotion.CATCH_TIME or 2)
		else
			-- the fall plays out (the slow-motion beat included) before anybody reacts to it
			task.wait(FightMotion and FightMotion.KOFallWall and FightMotion.KOFallWall(choice.ko, fall) or 1.6)
		end
		-- no neutral corner after a knockout: it is over, the winner celebrates where he stands
		by.guardOverride = "win"
		self:UpdateGuard(by)
		self:RefAct("waveoff")
		task.wait(1.2)
		self:End(by, "KO", "Knocked out cold")
		return
	end
	-- to the neutral corner once the fall has landed in front of him: an NPC walks there (backing off, eyes
	-- on the man he dropped), the player's character is walked there by the server
	local corner = (by == self.P) and self.anchors.RedNeutral or self.anchors.BlueNeutral
	do
		local fightId = self.id
		task.delay(0.6, function()
			if self.id ~= fightId or self.finished or F.state ~= "down" then
				return
			end
			if by.isPlayer or not by.hum then
				self:Glide(by, corner.Position, 8)
			else
				by.glideId = (by.glideId or 0) + 1
				by.cornerWalk = corner.Position
				by.cornerWalkSent = false
			end
		end)
	end
	if F.kdRound >= 3 then
		task.wait(1.5)
		self:RefAct("waveoff")
		self:End(by, "TKO", "Three knockdowns in the round")
		return
	end
	task.spawn(function()
		self:Count(F)
	end)
end

-- seconds between two green-zone presses that count triple (the client mirrors it for its bar)
local GOOD_GAP = 0.25

function Fight:GetUpAbility(F)
	local s, m = F.data.stats, F.data.mental
	local a = (s.Chin * 0.4 + m.Composure * 0.3 + s.Recovery * 0.3) / 100
	a -= (F.kdTotal - 1) * 0.12
	a += F.health / 300
	a -= F.conc * 0.25
	if F.downSeverity == "flash" then
		a += 0.25
	elseif F.downSeverity == "heavy" then
		a -= 0.1
	end
	return math.clamp(a, 0.05, 0.95)
end

function Fight:Count(F)
	local id = self.id
	local sev = F.downSeverity or "normal"
	local ability = self:GetUpAbility(F)
	local aiUpAt = nil
	if not F.isPlayer then
		local p = ability + 0.15
		if sev == "flash" then
			p = 1
		elseif sev == "heavy" then
			p -= 0.15
		end
		if self.rng:NextNumber() < p then
			if sev == "flash" then
				aiUpAt = self.rng:NextInteger(2, 4)
			else
				aiUpAt = math.clamp(math.floor(9 - ability * 6 + self.rng:NextInteger(-1, 1) + (sev == "heavy" and 1 or 0)), 3, 9)
			end
		end
	end
	-- presses needed (a green-zone press counts 3): a first knockdown takes a few seconds of honest work, a
	-- third one when he's badly hurt still needs good timing on top of the mashing
	local target = 8 + F.kdTotal * 4 + (1 - ability) * 12 + F.conc * 8
	if sev == "flash" then
		target *= 0.35
	elseif sev == "heavy" then
		target *= 1.15
	end
	target = math.max(4, math.floor(target))
	if F.isPlayer then
		-- only the man on the canvas gets the get-up panel (in PvP the other client just sees the count)
		self:SendTo(F, { t = "getupStart", target = target, ability = ability, severity = sev })
	end
	for n = 1, 10 do
		task.wait(0.85)
		if self.id ~= id or self.finished then
			return
		end
		setAttr(F.model, "Count", n)
		self:RefAct("refcount|" .. n)
		self:Send({ t = "count", n = n, who = self:Who(F), mash = F.mash, target = target })
		local up
		if F.isPlayer then
			up = n >= 2 and n <= 9 and F.mash >= target
		else
			up = aiUpAt ~= nil and n >= aiUpAt
		end
		if up then
			self:GetUp(F, n)
			return
		end
	end
	self:RefAct("waveoff")
	self:Comment("It's OVER! " .. F.data.name .. " can't beat the count!", true)
	self:End(self:Other(F), "KO", "Counted out")
end

-- beats the count: mandatory eight count on the feet, then the referee looks into the eyes
function Fight:GetUp(F, n)
	local id = self.id
	local s = F.data.stats
	local now = self:Now()
	local sev = F.downSeverity or "normal"
	if sev == "flash" then
		F.health = math.max(F.health, math.min(F.healthCap, 34))
	else
		-- back up, but still on wobbly legs (dazed tier) until the head clears
		F.health = math.max(F.health, math.min(F.healthCap, 18 + s.Recovery * 0.2 - F.kdTotal * 3))
		F.stun = 6 -- a few seconds without getting hit clears the worst of it
		F.healthCap = math.max(35, F.healthCap - 8)
	end
	F.body = math.max(F.body, 20)
	F.state = "idle"
	-- every fall has its own get-up (off the back: roll, hands and knees, a knee, up)
	local fall = F.model:GetAttribute("DownPose") or "back"
	local upT = FightMotion and FightMotion.GetUpTime and FightMotion.GetUpTime(fall) or 0.9
	F.hurtUntil = now + upT + (sev == "flash" and 1.2 or 2.5)
	F.busyUntil = now + upT
	F.stamina = math.max(F.stamina, F.maxStam * 0.3)
	F.balance = 70
	F.strain = 1
	self:SetAct(F, string.format("getup|%s|0|%.2f", fall, upT))
	self:CheckTier(F)
	self:UpdateGuard(F)
	self:Send({ t = "getup", who = self:Who(F) })
	self:Comment(F.data.name .. " beats the count! What heart!", true)
	-- the mandatory eight count continues while the fighter stands
	for k = n + 1, 8 do
		task.wait(0.45)
		if self.id ~= id or self.finished then
			return
		end
		setAttr(F.model, "Count", k)
		self:RefAct("refcount|" .. k)
		self:Send({ t = "count", n = k, who = self:Who(F), standing = true })
	end
	task.wait(0.55)
	-- the referee looks into his eyes once he is all the way up
	local upLeft = now + upT + 0.15 - self:Now()
	if upLeft > 0 then
		task.wait(upLeft)
	end
	if self.id ~= id or self.finished then
		return
	end
	-- referee check: glassy eyes, unsteady legs, no answer -> it's over
	local risk = F.conc * 0.6 + F.tier * 0.12 - (F.data.mental.Composure or 50) / 400 + (sev == "heavy" and 0.08 or 0) + (F.kdRound >= 2 and 0.1 or 0)
	if sev == "flash" then
		risk -= 0.2
	end
	local ok = self.rng:NextNumber() >= risk
	setAttr(F.model, "Count", 0)
	setAttr(F.model, "DownPose", nil)
	setAttr(F.model, "DownDir", nil)
	setAttr(F.model, "DownDist", nil)
	setAttr(F.model, "KOKind", nil)
	self:Send({ t = "refcheck", who = self:Who(F), ok = ok })
	if not ok then
		self:RefAct("waveoff")
		self:Comment(self:Official(true) .. " looks into " .. his(F) .. " eyes... and waves it off!", true)
		if self.spar then
			self:End(self:Other(F), "Stopped", "Coach stops the sparring session after the count")
		else
			self:End(self:Other(F), "TKO", "Referee waves it off after the count")
		end
		return
	end
	self:Comment(self:Official(true) .. " asks " .. F.data.name .. " to walk forward... OK to continue!", true)
	task.wait(0.6)
	if self.id == id and not self.finished then
		self:Send({ t = "announce", text = "BOX!" })
		self.kdHold = false
		self.paused = self.menuHold == true -- (the Moves & Controls menu may still hold the round)
		self.resumedAt = self:Now()
	end
end

function Fight:CheckStoppage(F)
	if F.state == "down" or self.finished then
		return
	end
	local now = self:Now()
	local n = 0
	for i = #F.recentHits, 1, -1 do
		if now - F.recentHits[i] <= 3 then
			n += 1
		else
			table.remove(F.recentHits, i)
		end
	end
	if n >= 4 then
		self:Comment(self:Other(F).data.name .. " is unloading a flurry!")
	end
	if self.tutorial and Tutorial and self:Protected(F) then
		return -- the tutorial: nobody is waved off before the last step (the debut's player: before the final round)
	end
	-- time since the fighter last threw, not counting a pause he could not punch through
	local idle = now - math.max(F.lastPunch, self.resumedAt or 0)
	local stop = (F.health < 16 and n >= 5 and idle > 2)
		-- out on the feet and not fighting back: the referee saves the fighter
		or (F.tier >= 3 and n >= 3 and idle > 1.5 and not F.blocking)
		or (F.tier >= 2 and F.conc > 0.75 and n >= 4 and idle > 1.5)
		-- hurt and taking a beating without answering back
		or (F.tier >= 1 and n >= 6 and idle > 2 and not F.blocking)
	if stop then
		self:RefAct("waveoff")
		if self.spar then
			-- in the gym the man in the ring is the coach: he stops a spar, there is no TKO on a record
			self:Send({ t = "announce", text = "COACH: \"That's enough! Stop!\"" })
			self:End(self:Other(F), "Stopped", "Coach stops the sparring session")
		else
			self:Comment("The referee waves it off!", true)
			self:End(self:Other(F), "TKO", "Referee stops the fight")
		end
	end
end

------------------------------------------------------------------------
-- Positioning / movement
------------------------------------------------------------------------

function Fight:Place(F, pos, lookAt)
	if not F.root then
		return
	end
	F.glideId = (F.glideId or 0) + 1 -- a placement wins over any walk in progress
	local target = lookAt or self.anchors.RingCenter.Position
	local p = Vector3.new(pos.X, pos.Y + standHeight(F.hum, F.root), pos.Z)
	F.model:PivotTo(CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z)))
	F.root.AssemblyLinearVelocity = Vector3.zero
end

function Fight:ClampToRing(pos)
	local c = self.anchors.RingCenter.Position
	local off = flat(pos - c)
	local half = self.ringHalf - 1.5
	return Vector3.new(c.X + math.clamp(off.X, -half, half), pos.Y, c.Z + math.clamp(off.Z, -half, half))
end

-- centre-to-centre spacing the bodies need so gloves and torsos never sink into each other
-- (self.sp.minSep: FightMotion.Spacing scaled to the pair's rigs). In a clinch AnimFight's tie-up steps
-- each man 0.38 in and leans him onto the other, so the roots stay this far apart for the two chests to
-- meet without sinking in: CLINCH_SEP x the pair's rig factor, and more for deep chests (a heavyweight's
-- pecs and belly stand well proud of the classic torso the rig factor measures): CLINCH_CHEST +
-- CLINCH_DEPTH x the two UpperTorsos' depths. Lab clinch sweep, torso into torso: 1.9 x (the old value)
-- 11-18 cm; 3.0 x clears the lean, female and power bodies against a balanced partner, 3.25 x the
-- heavyweight; heavy against heavy needs 4.15 studs (3.7 x), power against heavy 3.85.
local CLINCH_SEP, CLINCH_CHEST, CLINCH_DEPTH = 3.25, 1.55, 1.03

function Fight:ClinchSep()
	local sep = CLINCH_SEP * (self.rigK or 1)
	local a = self.P.model and self.P.model:FindFirstChild("UpperTorso")
	local b = self.O.model and self.O.model:FindFirstChild("UpperTorso")
	if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
		sep = math.max(sep, CLINCH_CHEST + CLINCH_DEPTH * (a.Size.Z + b.Size.Z))
	end
	return sep
end

-- cut (optional, 0..1): ring generalship - stand on the ring-centre side of him rather than wherever he leads,
-- so his back stays to the ropes (cutting off the ring); 0 = follow him round
function Fight:MoveAI(F, range, circle, cut)
	if not F.hum or F.state == "down" or F.state == "clinch" or self:IsStumbling(F) then
		return
	end
	local O = self:Other(F)
	local away = flat(F.root.Position - O.root.Position)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	away = away.Unit
	if cut and cut > 0 and self.anchors then
		local toC = flat(self.anchors.RingCenter.Position - O.root.Position)
		if toC.Magnitude > 1 then
			away = unitOr(away * (1 - cut) + toC.Unit * cut, away)
		end
	end
	local MIN_SEP = self:MinSep()
	range = math.max(range, MIN_SEP)
	local rot = CFrame.Angles(0, circle, 0):VectorToWorldSpace(away)
	local target = self:ClampToRing(O.root.Position + rot * range)
	-- a cornered opponent pulls the clamped spot in close: slide it round the ring instead
	if flat(target - O.root.Position).Magnitude < MIN_SEP then
		for _, a in ipairs({ 0.6, -0.6, 1.2, -1.2, 1.8, -1.8 }) do
			local alt = self:ClampToRing(O.root.Position + CFrame.Angles(0, a, 0):VectorToWorldSpace(rot) * range)
			if flat(alt - O.root.Position).Magnitude >= MIN_SEP then
				target = alt
				break
			end
		end
	end
	-- pace: cover the way in about the AI's decision interval (never slower than a shuffle)
	local togo = flat(target - F.root.Position).Magnitude
	F.aiStepSpeed = math.clamp(togo / 0.42, 4, 30)
	-- a new spot within a few inches of the current one is not worth a restart of the walk, as long as that
	-- walk is still live (UpdateMovement forgets it whenever it cancels the walk) and younger than Roblox's
	-- 8 s MoveTo timeout
	local now = self:Now()
	local last = F.aiTarget
	if last and flat(last - target).Magnitude < 0.35 and togo > 0.35 and now - (F.aiTargetT or 0) < 4 then
		return
	end
	F.aiTarget = target
	F.aiTargetT = now
	F.hum:MoveTo(target)
end

-- keep the two bodies apart (the AI side gives ground; the player's own movement is never fought)
function Fight:Separate()
	local P, O = self.P, self.O
	if not (P.root and O.root) or P.state == "down" or O.state == "down" then
		return
	end
	local minSep = self:MinSep()
	local d = flat(O.root.Position - P.root.Position)
	local m = d.Magnitude
	if P.state == "clinch" or O.state == "clinch" then
		-- the clinch distance; while the tie-up slides the pair there, no closer than they are (or the minimum)
		local cs = self:ClinchSep()
		if self.tieUntil and self:Now() < self.tieUntil then
			cs = math.min(cs, math.max(m, minSep))
		end
		minSep = cs
	end
	if m >= minSep then
		return
	end
	local dir = m > 0.05 and d.Unit or flat(P.root.CFrame.LookVector).Unit -- stacked: put them back in front
	local movers = {}
	if not O.isPlayer then
		table.insert(movers, { O, dir })
	end
	if not P.isPlayer then
		table.insert(movers, { P, -dir })
	end
	local share = (minSep - m) / math.max(1, #movers)
	for _, mv in ipairs(movers) do
		local X, v = mv[1], mv[2]
		local p = X.root.Position
		local goal = self:ClampToRing(p + v * share)
		shift(X, goal - p)
	end
end

function Fight:SetupFacing(F)
	local att = Instance.new("Attachment")
	att.Name = "FightFacingAtt"
	att.Parent = F.root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FightFacing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 60
	ao.Parent = F.root
	F.align = ao
	F.alignAtt = att
	if F.hum then
		F.hum.AutoRotate = false
		F.hum.UseJumpPower = false
		F.hum.JumpHeight = 0
	end
end

function Fight:UpdateMovement(F, dt)
	local O = self:Other(F)
	local now = self:Now()
	if F.align and F.root and O.root then
		local dir = flat(O.root.Position - F.root.Position)
		if dir.Magnitude > 0.05 then
			-- a new facing only once it turns by more than about a degree: the goal replicates to every
			-- client on each change, and physics jitter alone changed it nearly every frame
			dir = dir.Unit
			local last = F.alignDir
			if not last or last:Dot(dir) < 0.99985 then
				F.alignDir = dir
				F.align.CFrame = CFrame.lookAt(Vector3.zero, dir)
			end
		end
		F.align.Enabled = F.state ~= "down"
	end
	local stumbling = now < F.stumbleUntil
	if F.hum then
		local s = F.data.stats
		local speed = (8 + s.Footwork * 0.08) * F.style.fight.move * F.moveMul
		local cw = F.cornerWalk
		if cw and (not F.root or F.isPlayer or F.state == "down" or not self.paused or flat(cw - F.root.Position).Magnitude < 1.2) then
			F.cornerWalk = nil
			cw = nil
		end
		if cw then
			-- after a knockdown: backs off to the neutral corner at a walk (AnimLoco gives him real steps)
			speed = 8
		elseif F.state == "down" or F.state == "clinch" or self.paused or not self.live then
			speed = 0
		elseif stumbling then
			-- the player's client pushes the stagger with Humanoid:Move; NPCs glide below
			speed = F.isPlayer and F.stumbleSpeed or 0
		else
			if F.state == "punching" then
				speed *= 0.45
			elseif F.blocking then
				speed *= 0.6
			end
			if self:IsHurt(F) then
				speed *= 0.6
			end
			if F.stamina < F.maxStam * 0.25 then
				speed *= 0.8
			end
			if self:Sprinting(F) then
				speed *= SPRINT.mul
			end
			-- dazed legs and a concussion slow every step (and Granite is slow on his feet)
			speed *= (1 - CONC.tierSpeed * F.tier) * (1 - CONC.speed * F.conc)
			speed *= 1 - Traits.Effect("Granite", "slow", self:Trait(F, "Granite"))
			-- an NPC paces itself to arrive about when the AI next decides: continuous footwork instead
			-- of dash-and-stop (its full speed is still there for a long way to go)
			if not F.isPlayer and F.aiStepSpeed then
				speed = math.min(speed, F.aiStepSpeed)
			end
		end
		-- quantised: no replication churn from tiny changes
		speed = quant(speed, 0.5)
		if F.hum.WalkSpeed ~= speed then
			F.hum.WalkSpeed = speed
		end
		if cw then
			if not F.cornerWalkSent then
				F.cornerWalkSent = true
				F.aiTarget = nil
				F.hum:MoveTo(Vector3.new(cw.X, F.root.Position.Y, cw.Z))
			end
		elseif speed == 0 and not F.isPlayer then
			-- the walk is cancelled: MoveAI must re-issue its next spot even if that spot has not moved
			F.aiTarget = nil
			F.hum:MoveTo(F.root.Position)
		end
	end
	if F.root then
		-- a special's leap / step back (NPCs; the player's client drives its own)
		if now < F.lungeUntil and F.lungeVel and not F.isPlayer and F.state ~= "down" then
			local p = F.root.Position
			shift(F, self:ClampToRing(p + F.lungeVel * dt) - p)
		end
		if stumbling and F.stumbleVel and not F.isPlayer and F.state ~= "down" then
			local p = F.root.Position
			local want = p + F.stumbleVel * dt
			local goal = self:ClampToRing(want)
			if flat(goal - want).Magnitude > 0.05 then
				-- into the ropes: they catch and push back a little
				F.stumbleVel = -F.stumbleVel * 0.25
				self:Send({ t = "ropes", who = self:Who(F) })
			else
				F.stumbleVel *= math.max(0, 1 - dt * 3.5)
			end
			shift(F, goal - p)
		end
		local p = F.root.Position
		local clamped = self:ClampToRing(p)
		if (clamped - p).Magnitude > 0.5 then
			shift(F, clamped - p)
		end
	end
end

------------------------------------------------------------------------
-- The 10 Hz state message, packed: 42 bytes in a buffer where the keyed table cost about 370 on the wire
-- (every key name, every number a double). FightClient (handlers.state) unpacks it into the same time /
-- me / opp fields; the two must keep this layout. Bars are 0.01 HP / stamina steps, concussion 0.001:
-- finer than any bar or readout shows.
--   0 time u16 | me: 2 hp, 4 cap, 6 body, 8 bodyCap, 10 stam, 12 max, 14 stamCap (x100 u16), 16 conc (x1000),
--   18 bal (x100), 20 tier u8, 21 flags u8 (1 hurt, 2 angle), 22 eyeL, 23 eyeR (x100 u8)
--   opp: 24 hp, 26 cap, 28 body, 30 bodyCap, 32 stam, 34 max, 36 stamCap (x100), 38 conc (x1000), 40 tier, 41 flags (1 hurt)
------------------------------------------------------------------------
local STATE_BYTES = 42
local function put16(b, o, v, scale)
	v = tonumber(v) or 0
	buffer.writeu16(b, o, math.clamp(math.floor(v * scale + 0.5), 0, 65535))
end
function Fight:PackState(P, O, time, now)
	local b = buffer.create(STATE_BYTES)
	buffer.writeu16(b, 0, math.clamp(time, 0, 65535))
	for side, X in ipairs({ P, O }) do
		local o = side == 1 and 2 or 24
		local vals = { X.health, X.healthCap, X.body, X.bodyCap, X.stamina, X.maxStam, X.stamCap }
		for i = 1, 7 do
			put16(b, o + (i - 1) * 2, vals[i], 100)
		end
		put16(b, o + 14, X.conc, 1000)
		local flags = self:IsHurt(X) and 1 or 0
		if side == 1 then
			put16(b, 18, X.balance, 100)
			buffer.writeu8(b, 20, math.clamp(X.tier or 0, 0, 255))
			if now < X.angleUntil then
				flags += 2
			end
			buffer.writeu8(b, 21, flags)
			-- swollen eyes: FightClient darkens that side of the screen (CONTRACTS 8: P.dmg 0..1)
			buffer.writeu8(b, 22, math.clamp(math.floor(quant(X.dmg.leftEye, 0.05) * 100 + 0.5), 0, 100))
			buffer.writeu8(b, 23, math.clamp(math.floor(quant(X.dmg.rightEye, 0.05) * 100 + 0.5), 0, 100))
		else
			buffer.writeu8(b, 40, math.clamp(X.tier or 0, 0, 255))
			buffer.writeu8(b, 41, flags)
		end
	end
	return b
end
------------------------------------------------------------------------
-- Per-frame update
------------------------------------------------------------------------
-- once a frame per fighter in a live round: being walked down / on the ropes, the second wind, a breather at
-- range, the momentum's share; returns his stamina regen multiplier (Config.FightDepth)
function Fight:DepthRegen(F, now, rdt)
	local O = self:Other(F)
	local live = self.live and not self.paused and F.state ~= "down"
	local mul = 1
	if not live then
		F.pressured, F.onRopes = false, false
		return mul
	end
	local dist = self:Distance(F, O)
	local jab = self:PunchRange(O, "jab")
	F.pressured = O.state ~= "down" and dist <= jab * DEPTH.pressRange and self:RecentThrows(O, DEPTH.pressWin) >= DEPTH.pressPunches
	F.onRopes = self:OnRopes(F)
	local st = O.typeStats
	st.liveT += rdt
	if F.pressured or (F.onRopes and dist <= jab * 1.1) then
		st.pressT += rdt
	end
	if F.pressured then
		local proof = self:Trait(F, "PressureProof")
		if proof > 0 then
			-- (doesn't wilt; his corner never needs telling, the other man's does now and then)
			if self.rng:NextNumber() < rdt * 0.2 then
				self:TraitFired(F, "PressureProof")
			end
		else
			mul *= DEPTH.pressRegen
		end
	end
	if F.onRopes then
		local rm = self:RopeMul(F)
		mul *= 1 - (1 - DEPTH.ropeRegen) * rm
		if rm < 0.999 and self.rng:NextNumber() < rdt * 0.25 then
			self:TraitFired(F, "RingGeneral")
		end
	end
	-- a breather: no punch for a moment and out at range
	if now - F.lastPunch > DEPTH.breatheAfter and dist > jab and not F.blocking then
		mul *= DEPTH.breatheRegen
	end
	-- the second wind: gassed for a while and not punching -> a surge, once a fight (twice for the fittest)
	if F.stamina < F.maxStam * DEPTH.windAt and F.state ~= "punching" and not self.tutorial then
		F.gassedFor += rdt
		if F.gassedFor >= DEPTH.windAfter and F.windLeft > 0 and now >= F.windUntil then
			F.windLeft -= 1
			F.winds += 1
			F.windUntil = now + DEPTH.windTime
			F.gassedFor = 0
			F.stamina = math.min(F.stamCap, F.stamina + F.maxStam * DEPTH.windGive)
			self:SendEach(function(V)
				return { t = "intel", hint = V == F and "SECOND WIND! Breathe and go again." or (F.data.name .. " has found a second wind!"), tone = V == F and "good" or "warn", wind = V == F or nil }
			end)
			self:Comment(F.data.name .. " has found a second wind!")
		end
	elseif F.stamina > F.maxStam * (DEPTH.windAt + 0.1) then
		F.gassedFor = 0
	end
	if now < F.windUntil then
		mul *= DEPTH.windRegen
	end
	mul *= 1 + DEPTH.momRegen * self:Mom(F)
	return mul
end

-- every few frames of a live round: the momentum drifts back to even and the clients get it (and the live score)
function Fight:UpdateIntel(dt, now)
	if not self.live or self.paused then
		return
	end
	local m = self.mom or 0
	local k = DEPTH.momDecay * dt
	self.mom = m > 0 and math.max(0, m - k) or math.min(0, m + k)
	self.momSum = (self.momSum or 0) + (self.mom or 0) * dt
	self.intelAcc = (self.intelAcc or 0) + dt
	if self.intelAcc < 0.5 then
		return
	end
	self.intelAcc = 0
	local q = math.floor((self.mom or 0) * 20 + 0.5) / 20
	local live = self.tutorial == nil and not self.spar
	local card = nil
	if live and now >= (self.judgesAt or 0) then
		self.judgesAt = now + 2
		card = self:LiveCard()
	end
	if q == self.momSent and not card then
		return
	end
	self.momSent = q
	self:SendEach(function(V)
		local red = V == self.P
		local msg = { t = "mom", m = red and q or -q }
		if card then
			msg.d = red and card.d or -card.d
			msg.cards = {}
			for j, c in ipairs(card.cards) do
				msg.cards[j] = red and { c[1], c[2] } or { c[2], c[1] }
			end
			msg.round = self.round
		end
		return msg
	end)
end

-- the live score (the judge-scoring visibility option): this round's work so far (the red corner's lead in the
-- judges' points) and the three cards through the last round
function Fight:LiveCard()
	local d = self:RoundPoints(self.P, self.O) - self:RoundPoints(self.O, self.P)
	local cards = {}
	for j = 1, 3 do
		cards[j] = { self.cards[j][1], self.cards[j][2] }
	end
	return { d = math.floor(d * 10 + 0.5) / 10, cards = cards }
end

function Fight:Update(dt)
	local now = self:Now()
	-- while the Moves & Controls menu holds the round nobody recovers: no stamina, no clearing head, no legs
	-- coming back (the menu is for reading, not a free breather)
	local rdt = self.menuHold and 0 or dt
	for _, F in ipairs(self.pair or { self.P, self.O }) do
		self:SampleDevice(F, now)
		if F.state == "punching" and now >= F.busyUntil then
			F.state = F.blocking and "blocking" or "idle"
		end
		if F.state == "clinch" and now >= F.clinchUntil then
			F.state = "idle"
		end
		-- a combination whose window has run out (and whose last punch has its result) is over
		if F.chain and not F.chain.closed and now > F.chain.closeAt and now >= F.busyUntil then
			self:CloseChain(F)
			F.chain = nil
		end
		if F.dodgeKind and now >= F.dodgeEnd then
			F.dodgeKind = nil
		end
		local s = F.data.stats
		-- stamina ceiling: body damage and the rounds wear the gas tank down
		F.stamCap = math.clamp(F.maxStam * (0.72 + 0.28 * F.body / 100) - F.stamErosion, F.maxStam * 0.35, F.maxStam)
		local regen = 5 + s.Endurance * 0.06
		if F.state == "punching" then
			regen *= 0.2
		elseif F.blocking then
			regen *= 0.5
		elseif F.state == "clinch" then
			regen *= 1.6
		end
		if F.body < 50 then
			regen *= 0.6
		end
		if F.dmg.nose then
			regen *= 0.85
		end
		regen *= self:DepthRegen(F, now, rdt)
		-- Shift in the ring: quicker feet cost stamina while he moves (none comes back meanwhile)
		if self:Sprinting(F) and F.hum.MoveDirection.Magnitude > 0.1 then
			F.stamina = math.max(0, F.stamina - SPRINT.drain * rdt)
		elseif F.stamina < F.stamCap then
			F.stamina = math.min(F.stamCap, F.stamina + regen * rdt)
		end
		if F.state ~= "down" then
			if now - F.lastHitAt > STUN_QUIET and F.stun > 0 then
				-- a badly hurt fighter clears his head more slowly
				self:ClearStun(F, (STUN_CLEAR + s.Recovery * STUN_CLEAR_PER_RECOVERY) * (1 - 0.4 * F.tier) * rdt)
			end
			if now - F.lastBodyHitAt > 3 then
				F.body = math.min(F.bodyCap, F.body + 0.12 * rdt)
			end
			-- the legs come back with footwork; slower while dazed
			F.balance = math.min(100, F.balance + (18 + s.Footwork * 0.15) * (1 - 0.25 * F.tier) * rdt)
		end
		-- concussion clears slowly (Recovery helps); the peak is what follows the fighter home
		F.conc = math.max(0, F.conc - (CONC.decay + s.Recovery * CONC.decayPerRecovery) * rdt)
		local strainFloor = (F.state == "clinch" and 0.8) or ((self:IsHurt(F) or F.tier >= 2) and 0.5) or 0
		F.strain = math.max(strainFloor, F.strain - rdt * 0.5)
		if F.tier ~= Config.HeadTier(F.health) then
			self:CheckTier(F)
		end
		if F.dmgDirty and now >= (F.dmgNext or 0) then
			self:RefreshDamage(F)
		end
		self:UpdateMovement(F, dt)
		if F == self.O then
			self:Separate()
		end
		self:UpdateGuard(F)
		-- nobody can punch during a count / eight count / referee check, so "not answering back" means nothing
		-- then (the standing man would otherwise be stopped in favour of the one on the canvas)
		if not self.paused then
			self:CheckStoppage(F)
		end
		if F.stamina < F.maxStam * 0.15 and not F.gassedNoted then
			F.gassedNoted = true
			self:Comment(F.data.name .. " is running on fumes!")
		elseif F.stamina > F.maxStam * 0.5 then
			F.gassedNoted = false
		end
	end
	-- (the AI: the blue corner's; the balance sims give the red corner one too)
	for _, F in ipairs(self.pair or { self.P, self.O }) do
		if F.ai then
			F.ai:Observe(self.menuHold and 0 or dt)
			if self.live and not self.paused and not self.menuPending then
				F.ai:Think(now)
			end
		end
	end
	self:UpdateIntel(self.menuHold and 0 or dt, now)
	for _, F in ipairs(self.pair or { self.P, self.O }) do
		if F.blocking then
			F.blockTime = (F.blockTime or 0) + dt
		end
	end
	if self.tutorial then
		self:TutorialStep(dt, now)
	end
	self:UpdateReferee(now)
	-- model attributes at 5 Hz (quantized, change-only)
	self.attrAcc = (self.attrAcc or 0) + dt
	if self.attrAcc >= 0.2 then
		self.attrAcc = 0
		self:SyncAttrs(self.P)
		self:SyncAttrs(self.O)
	end
	self.sendAcc = (self.sendAcc or 0) + dt
	if self.sendAcc >= 0.1 then
		self.sendAcc = 0
		local time = math.max(0, math.ceil(self.roundEnd - now))
		self:SendEach(function(P)
			return { t = "state", b = self:PackState(P, self:Other(P), time, now) }
		end)
	end
end

------------------------------------------------------------------------
-- The first-time tutorial (Tutorial.lua): what the player does moves the guided steps on; the client's
-- prompt card follows the "tutorial" messages
------------------------------------------------------------------------
-- the guided bout's protection: may F not be knocked down / stopped right now? (the practice round: the player
-- never, the opponent until the last step is up; the debut: the player until the final round)
function Fight:Protected(F)
	local tr = self.tutorial
	if not (tr and Tutorial) then
		return false
	end
	if F.isPlayer then
		return not Tutorial.PlayerCanDrop(tr, self.round)
	end
	-- (the debut's final round is a real fight both ways: once the player can be dropped, so can he, even if
	-- the guide's hold ran out before its last step)
	if self.debut and (self.round or 0) >= (self.rounds or math.huge) then
		return false
	end
	return not Tutorial.CanDrop(tr)
end

-- the debut's step card: SKIP GUIDE (the Fight remote's tutorialSkip) ends the guidance, the bout goes on as a
-- normal fight (the forgiving damage stays for this one night)
function Fight:EndGuide()
	local tr = self.tutorial
	if not (tr and self.debut) or tr.done then
		return
	end
	tr.done = true
	tr.skipped = true
	self.aiWork = Tutorial.AiWork(tr)
	self.aiDefense = Tutorial.AiDefense(tr)
	self:SendTo(self.P, Tutorial.View(tr))
end
FightEngine.EndGuide = function(player)
	local fight = FightEngine.Active[player]
	if fight then
		fight:EndGuide()
	end
end

function Fight:TutorialNote(ev)
	local tr = self.tutorial
	if not (tr and Tutorial) or tr.done then
		return
	end
	ev.now = self:Now()
	if Tutorial.Feed(tr, ev) then
		self.aiWork = Tutorial.AiWork(tr)
		self.aiDefense = Tutorial.AiDefense(tr)
		self:SendTo(self.P, Tutorial.View(tr))
		if tr.done and not self.tutorialEndAt and not self.debut then
			-- (a knockdown: the count plays out first; Update ends the bout once both men are up, or the
			-- count ends it as a KO)
			self.tutorialEndAt = ev.now + 1.5
		end
	end
end

-- every frame of a live round: footwork, the guard held, the stamina tank, the step timeouts, the end
function Fight:TutorialStep(dt, now)
	local P = self.P
	if self.live and not self.paused and not self.menuHold and P.state ~= "down" then
		local root = P.root
		if root then
			local pos = root.Position
			local last = self.tutorialPos
			self.tutorialPos = pos
			if last then
				local d = flat(pos - last).Magnitude
				if d > 0.01 and d < 3 then -- (a teleport back to the corner is not footwork)
					self:TutorialNote({ k = "move", dist = d })
				end
			end
		end
		if P.blocking then
			self:TutorialNote({ k = "block", dt = dt })
		end
		self:TutorialNote({ k = "stamina", pct = P.stamina / math.max(1, P.maxStam) })
		self:TutorialNote({ k = "tick" })
	else
		self.tutorialPos = nil
	end
	if self.tutorialEndAt and not self.debut and now >= self.tutorialEndAt and not self.finished and P.state ~= "down" and self.O.state ~= "down" then
		self:End(P, "Tutorial", "Tutorial complete")
	end
end

------------------------------------------------------------------------
-- Scoring & corner
------------------------------------------------------------------------
-- [Judging] the three ringside judges (BoxerModules.Judging: pure, tools/sim/test_judging.luau pins it) and the
-- post-fight scene (BoxerModules.PostFight: the men to the centre, the announcer, the referee raises the hand).
-- Both optional: without them the flat card below stands in and the fight ends as it did.
local Judging, PostFight
do
	local okJ, modJ = pcall(require, script.Parent:FindFirstChild("Judging"))
	Judging = okJ and type(modJ) == "table" and modJ or nil
	local okP, modP = pcall(require, script.Parent:FindFirstChild("PostFight"))
	PostFight = okP and type(modP) == "table" and modP or nil
end
-- One judge's 10-point must card for a round. diff = the judge's punch differential (positive: the
-- first fighter did the better work), kdA / kdB = knockdowns each fighter SCORED. As real judges do:
-- the round winner gets 10 and the loser 9; a knockdown wins the round for whoever scored it (equal
-- knockdowns cancel and the work decides), and every net knockdown costs the man who went down one
-- more point (one knockdown 10-8, two 10-7) - unless he dominated the rest of the round, which earns
-- that point back (10-9). 10-10 only for a truly even round with no knockdowns; never 9-9.
-- (Judging.MustScore is the same rule plus the fouls' point deductions; this stays as the fallback.)
local EVEN_ROUND = 0.25 -- |diff| under this is an even round (rare: judges are told to pick a winner)
local DOMINANT_ROUND = 3 -- a punch differential this big outweighs one knockdown point
function FightEngine.MustScore(diff, kdA, kdB, foulsA, foulsB)
	if Judging then
		return Judging.MustScore(diff, kdA, kdB, foulsA, foulsB)
	end
	kdA, kdB = tonumber(kdA) or 0, tonumber(kdB) or 0
	diff = tonumber(diff) or 0
	local net = kdA - kdB
	local aWins
	if net ~= 0 then
		aWins = net > 0
	elseif kdA == 0 and math.abs(diff) < EVEN_ROUND then
		return 10, 10
	else
		aWins = diff >= 0
	end
	local down = math.abs(net)
	if down > 0 and (aWins and -diff or diff) >= DOMINANT_ROUND then
		down -= 1 -- the knocked-down man won the rest of the round clearly
	end
	local loser = math.max(6, 9 - down)
	if aWins then
		return 10, loser
	end
	return loser, 10
end

-- a fighter's work in the round as the judges see it: clean punches, power, body work, activity, inside work in
-- the clinch, minus the holding, plus the other man's misses, plus a little of the round's momentum (effective
-- aggression and ring generalship: Config.FightDepth.momScore at a round spent all his way)
function Fight:RoundPoints(F, other)
	local t = F.tally
	local mom = (self.momSum or 0) / math.max(1, self.roundSeconds or 60)
	if F ~= self.P then
		mom = -mom
	end
	return t.landed * 1 + t.power * 0.8 + t.body * 0.5 + t.thrown * 0.04 - t.clinches * 0.3 + (other.tally.thrown - other.tally.landed) * 0.03
		+ (t.inside or 0) * 0.3 + DEPTH.momScore * math.clamp(mom, -1, 1)
end

-- [Judging] the judges' observer. The tallies keep the landed / thrown / power / body / knockdown counts; what the
-- judges also want (punches landed BY TYPE, blocks, slips, rolls, parries, the other man's misses, the time in the
-- centre of the ring) is read off the engine's own traffic - Fight:Send's "hit" / "blocked" / "defense" / "miss"
-- (red-corner perspective: who = "you" is P) and the 5 Hz attribute sync (the ring position while the round is
-- live) - so the hit path carries no judging code. A sim that replaces Send per fight (tools/sim/fightsim) leaves
-- these at zero and the tallies carry the card.
local function judgeSide(F)
	if not F.judge then
		F.judge = Judging and Judging.NewSide() or { byType = {}, thrownByType = {} }
	end
	return F.judge
end
local baseSend = Fight.Send
function Fight:Send(msg)
	if Judging and type(msg) == "table" and self.P and self.O then
		if self.live and self.roundEnd then
			-- (the round clock at the last live event: a stoppage's "at 1:32 of round 3" for the announcer)
			self.judgeRoundLeft = self.roundEnd - self:Now()
		end
		local who = msg.who == "you" and self.P or (msg.who == "opp" and self.O or nil)
		if who then
			local t = msg.t
			if t == "hit" then
				local S = judgeSide(who)
				local k = msg.punch
				if type(k) == "string" then
					S.byType[k] = (S.byType[k] or 0) + 1
				end
				if msg.heavy then
					S.heavy += 1
				end
				S.damage += tonumber(msg.dmg) or 0
			elseif t == "blocked" then
				judgeSide(who).blocked += 1 -- (who = the man whose guard took it)
			elseif t == "defense" then
				local S = judgeSide(who) -- (who = the man who made it miss)
				if msg.move == "PARRIED" then
					S.parried += 1
				else
					S.evaded += 1
				end
			elseif t == "miss" then
				judgeSide(self:Other(who)).missed += 1 -- (who = the man who threw it)
			end
		end
	end
	return baseSend(self, msg)
end
local baseSyncAttrs = Fight.SyncAttrs
function Fight:SyncAttrs(F)
	if Judging and self.live and F and F.root and self.anchors and self.anchors.RingCenter then
		local now = self:Now()
		local dt = now - (F.judgeAt or now)
		F.judgeAt = now
		if dt > 0 and dt < 1 then
			local S = judgeSide(F)
			S.liveT += dt
			local off = flat(F.root.Position - self.anchors.RingCenter.Position)
			if math.max(math.abs(off.X), math.abs(off.Z)) <= (self.ringHalf or 11) * 0.42 then
				S.centreT += dt
			end
		end
	end
	return baseSyncAttrs(self, F)
end

-- the observer's slate for the next round: the running fight counters are snapshotted so the round's share is
-- their difference at the bell
function Fight:JudgeReset(F)
	F.judge = nil
	F.judgeAt = nil
	F.judgeSnap = { counters = F.typeStats.counters, pressT = F.typeStats.pressT, liveT = F.typeStats.liveT, evades = F.evades, used = table.clone(F.punchesUsed) }
end

local function plainSide(S)
	local o = {}
	for k, v in pairs(S) do
		if type(v) == "number" then
			o[k] = math.floor(v * 100) / 100
		elseif type(v) == "table" then
			o[k] = table.clone(v)
		end
	end
	return o
end

-- the round's stats for the judges (Judging.Score's input): both corners, red first
function Fight:RoundStats()
	local function side(F)
		local S = judgeSide(F)
		local t = F.tally
		local snap = F.judgeSnap or {}
		S.landed, S.thrown, S.power, S.body = t.landed, t.thrown, t.power, t.body
		S.jabs = math.max(0, t.landed - t.power)
		S.kd, S.clinches, S.inside = t.kd, t.clinches, t.inside or 0
		S.counters = math.max(0, F.typeStats.counters - (snap.counters or 0))
		S.pressT = math.max(0, F.typeStats.pressT - (snap.pressT or 0))
		if S.liveT <= 0 then
			S.liveT = math.max(0, F.typeStats.liveT - (snap.liveT or 0))
		end
		for k, n in pairs(F.punchesUsed) do
			S.thrownByType[k] = math.max(0, n - ((snap.used or {})[k] or 0))
		end
		-- punches a dodge made miss (the engine's own count) when the observer saw fewer
		S.evaded = math.max(S.evaded, F.evades - (snap.evades or 0))
		local mom = (self.momSum or 0) / math.max(1, self.roundSeconds or 60)
		S.mom = math.clamp(F == self.P and mom or -mom, -1, 1)
		-- (the engine hands out no fouls yet: a referee's point deduction lands here)
		S.fouls = tonumber(F.fouls) or 0
		return S
	end
	return { red = side(self.P), blue = side(self.O), seconds = self.roundSeconds or Config.RoundSeconds }
end

-- the round's scorecard for viewer V (the client's Scorecards opens it with the rest message): the three judges'
-- round cards and reasons, the round's and the fight's punch stats of both men, the running totals
function Fight:ScorecardFor(V, detail, n)
	local red = V == self.P
	local function flip2(c)
		return red and { c[1], c[2] } or { c[2], c[1] }
	end
	local msg = { t = "scorecard", n = n, rounds = self.rounds, cards = {}, round = {}, judges = {}, kd = flip2(detail.kd) }
	for j = 1, 3 do
		msg.cards[j] = flip2(self.cards[j])
		msg.round[j] = flip2(detail.cards[j])
		local jd = detail.judges[j]
		msg.judges[j] = { id = jd.id, reason = jd.reason, diff = red and jd.diff or -jd.diff }
	end
	local st, tot = detail.stats, self.judgeTotals
	msg.stats = { you = red and st.red or st.blue, opp = red and st.blue or st.red }
	msg.totals = { you = plainSide(red and tot.red or tot.blue), opp = plainSide(red and tot.blue or tot.red) }
	return msg
end

function Fight:ScoreRound()
	local P, O = self.P, self.O
	local round, detail
	if Judging then
		local stats = self:RoundStats()
		detail = Judging.Score(stats, self.rng)
		detail.stats = { red = plainSide(stats.red), blue = plainSide(stats.blue) }
		round = detail.cards
		self.judgeRounds = self.judgeRounds or {}
		table.insert(self.judgeRounds, detail)
		self.judgeTotals = self.judgeTotals or { red = Judging.NewSide(), blue = Judging.NewSide() }
		Judging.AddSide(self.judgeTotals.red, stats.red)
		Judging.AddSide(self.judgeTotals.blue, stats.blue)
	else
		local pP, pO = self:RoundPoints(P, O), self:RoundPoints(O, P)
		round = {}
		for j = 1, 3 do
			local diff = pP - pO + self.rng:NextNumber(-1.6, 1.6) * (j == 3 and 1.4 or 1)
			local a, b = FightEngine.MustScore(diff, P.tally.kd, O.tally.kd)
			round[j] = { a, b }
		end
	end
	for j = 1, 3 do
		self.cards[j][1] += round[j][1]
		self.cards[j][2] += round[j][2]
	end
	table.insert(self.roundCards, round)
	self:JudgeReset(P)
	self:JudgeReset(O)
	if detail then
		local n = #self.roundCards
		self:SendEach(function(V)
			return self:ScorecardFor(V, detail, n)
		end)
	end
	return round
end

function Fight:EstimateLead(F)
	local lead = 0
	for _, r in ipairs(self.roundCards) do
		local a, b = r[1][1], r[1][2]
		if F == self.O then
			a, b = b, a
		end
		if a > b then
			lead += 1
		elseif b > a then
			lead -= 1
		end
	end
	return lead
end

function Fight:CornerAdvice(P)
	P = P or self.P
	local O = self:Other(P)
	local tips = {}
	if self.spar then
		table.insert(tips, "Good work. Keep your hands up and work on your timing.")
	end
	if P.healthCap < 60 or P.conc > 0.4 or P.tier >= 1 then
		table.insert(tips, "You're hurt. Hold (G), tie him up, keep that guard high and SURVIVE this round.")
	end
	if P.stamina < P.maxStam * 0.4 then
		table.insert(tips, "Breathe! You're punching yourself out - pick your shots.")
	end
	if O.tally.body >= 3 or P.body < 55 then
		table.insert(tips, "Elbows tight! They're investing in the body.")
	end
	if O.tier >= 1 or O.conc > 0.4 then
		table.insert(tips, "Those legs are GONE! Hooks and uppercuts - go finish it, but stay behind the jab.")
	elseif O.ai and O.ai.mode == "survive" then
		table.insert(tips, "They're HURT! Go get them, but don't get careless.")
	elseif O.ai and O.ai.mode == "pressure" then
		table.insert(tips, "They're coming forward now - pivot (Z/X) and make them pay with counters.")
	end
	-- the ring traits we know about against what we're doing tonight (Shared.Traits), then his eyes, then his read
	local myType = self:FightingType(P)
	for _, t in ipairs(O.traits or {}) do
		if O.traitSeen[t.id] and Traits.Resists(t.id, myType) then
			local D = Traits.Data[t.id]
			table.insert(tips, string.format("%s, and you're fighting like a %s. %s", D.name, Traits.Types[myType].name:lower(), D.counter))
			break
		end
	end
	for _, side in ipairs({ 1, -1 }) do
		if self:Blind(O, side) > 0.45 then
			table.insert(tips, string.format("His %s eye is closing - work the %s hand, he can't see it coming.", side == 1 and "right" or "left", side == 1 and "left" or "right"))
			break
		end
	end
	if O.ai and O.ai.read then
		local fav, share = O.ai.read:Favourite()
		if fav and share > 0.42 and O.ai.read.total > 8 then
			table.insert(tips, string.format("He's reading your %s. Mix it up, feint it, then throw something else.", (Config.PunchNames[fav] or fav):lower()))
		end
	end
	local lead = self:EstimateLead(P)
	if lead < 0 then
		table.insert(tips, "We're behind on the cards. You need to win this round!")
	elseif lead >= 2 then
		table.insert(tips, "You're up on the cards. Stay smart, don't get caught.")
	end
	if P.dmg.cut > 0.4 or P.dmg.cut2 > 0.4 then
		table.insert(tips, "Cutman's working on that cut - keep your guard high.")
	end
	if math.max(P.dmg.leftEye, P.dmg.rightEye) > 0.5 then
		table.insert(tips, "The enswell is on that eye. Turn away from the hand that's closing it.")
	end
	if P.data.eliteCorner and O.ai then
		table.insert(tips, "ELITE COACH: " .. (O.ai:Weakness() or "Stay focused."))
	elseif #tips == 0 then
		table.insert(tips, "Good round. Jab, move, parry (R) their straight shots and counter.")
	end
	if O.isPlayer and P.isPlayer and #tips < 2 then
		table.insert(tips, "He's a real fighter, not a script: watch what he does after he throws, and make him pay.")
	end
	if P.blockTime and P.blockTime > 15 then
		table.insert(tips, "Don't just shell up - slip (Q/E) or roll (C) and counter!")
	end
	return tips
end

-- what the corner sees on its own fighter between rounds (shown under the advice)
function Fight:ConditionReport(F)
	local d = F.dmg
	local out = {}
	local function sideName(side)
		return side == 1 and "right" or "left"
	end
	if d.cut > 0.2 then
		table.insert(out, string.format("Cut over the %s eye (%s)", sideName(d.cutSide), d.cut > 0.7 and "deep" or "bleeding"))
	end
	if d.cut2 > 0.2 then
		table.insert(out, string.format("Second cut, %s side", sideName(d.cutSide2)))
	end
	local eye = math.max(d.leftEye, d.rightEye)
	if eye > 0.3 then
		table.insert(out, string.format("%s eye %s", d.leftEye > d.rightEye and "Left" or "Right", eye > 0.75 and "nearly shut" or "swelling"))
	end
	if d.nose then
		table.insert(out, "Broken nose")
	end
	if math.max(d.ribsL, d.ribsR) > 0.4 then
		table.insert(out, "Ribs are sore")
	end
	if F.conc > 0.5 then
		table.insert(out, "Still seeing double")
	elseif F.conc > 0.25 then
		table.insert(out, "Head's a little foggy")
	end
	return {
		head = math.floor(F.health), cap = math.floor(F.healthCap), body = math.floor(F.body), bodyCap = math.floor(F.bodyCap),
		conc = math.floor(F.conc * 100) / 100, face = (Config.FaceDamageStage(d)), notes = out,
	}
end

------------------------------------------------------------------------
-- Flow
------------------------------------------------------------------------
function Fight:End(winner, method, reason)
	if self.finished then
		return
	end
	self.finished = true
	self.live = false
	self.winner = winner
	self.method = method
	self.reason = reason
	self.endRound = self.round
end

function Fight:SetSweat(level)
	for _, F in ipairs({ self.P, self.O }) do
		if F.model then
			local ok, err = pcall(Builder.SetSweat, F.model, F.data.app, level)
			if not ok then
				warn("[Boxer] SetSweat failed:", err)
			end
		end
	end
end

function Fight:Rest()
	local P, O = self.P, self.O
	self.live = false
	self:Place(P, self.anchors.RedCorner.Position)
	self:Place(O, self.anchors.BlueCorner.Position)
	for _, F in ipairs({ P, O }) do
		local s = F.data.stats
		local nut = F.data.nutrition and 1.15 or 1
		local elite = F.data.eliteCorner
		-- every round leaves a little less in the tank; Endurance slows that
		F.stamErosion += F.maxStam * 0.03 * math.max(0, 1 - s.Endurance / 150)
		F.bodyCap = math.max(40, F.bodyCap - (F.bodyCap - F.body) * 0.25)
		F.body = math.min(F.bodyCap, F.body + 8 * nut)
		F.stamCap = math.clamp(F.maxStam * (0.72 + 0.28 * F.body / 100) - F.stamErosion, F.maxStam * 0.35, F.maxStam)
		F.stamina = math.min(F.stamCap, F.stamina + F.maxStam * (0.25 + s.Recovery * 0.004) * nut)
		F.healthCap = math.max(30, F.healthCap - (100 - F.health) * 0.12)
		-- the minute's rest clears the stun and the corner gets a little more back
		F.health = math.min(F.healthCap, F.health + F.stun + (2 + s.Recovery * 0.05) * nut)
		F.stun = 0
		F.conc = math.max(0, F.conc - (elite and CONC.restHealElite or CONC.restHeal))
		-- the cutman and the enswell
		local d = F.dmg
		d.cut = math.max(0, d.cut - (elite and 0.25 or 0.15))
		d.cut2 = math.max(0, d.cut2 - (elite and 0.25 or 0.15))
		d.noseBleed = math.max(0, d.noseBleed - 0.3)
		d.leftEye = math.max(0, d.leftEye - (elite and 0.12 or 0.08))
		d.rightEye = math.max(0, d.rightEye - (elite and 0.12 or 0.08))
		d.redness = math.max(0, d.redness - 0.2)
		F.hurtUntil = 0
		F.stumbleUntil = 0
		F.stumbleVel = nil
		F.balance = 100
		F.kdRound = 0
		F.blocking = false
		F.state = "idle"
		F.strain = 0
		F.guardOverride = "rest"
		F.exprOverride = (F.stamina < F.maxStam * 0.5 or F.tier >= 1) and "fatigue" or nil
		self:CheckTier(F)
		self:RefreshDamage(F, true)
		self:UpdateGuard(F)
		self:SyncAttrs(F)
	end
end

-- the guided debut's last rest: the held rounds can leave the player at ~30 head HP after long lessons, so the
-- corner gets him back to his cap for the final round (the one where he can be stopped)
function Fight:DebutFinalRest()
	local P = self.P
	if not P.isPlayer then
		return
	end
	P.health = math.max(P.health, P.healthCap)
	P.stun = 0
	P.stamina = math.max(P.stamina, P.stamCap)
	P.conc = math.min(P.conc, 0.2)
	self:CheckTier(P)
end

function Fight:DoctorCheck()
	for _, F in ipairs({ self.P, self.O }) do
		local d = F.dmg
		local why
		if self:Protected(F) then
			-- (the guided bout: nobody it protects is stopped by the doctor either - the debut's player before
			-- the final round)
			d = { cut = 0, cut2 = 0, leftEye = 0, rightEye = 0 }
		end
		if d.cut >= 1 or d.cut2 >= 1 then
			why = "cut"
		elseif d.leftEye >= 1 and d.rightEye >= 1 then
			why = "eyes swollen shut"
		elseif F.conc >= 0.92 and F.kdTotal >= 2 and not self:Protected(F) then
			why = "concussion"
		end
		if why then
			self:Comment("The ringside doctor has seen enough!", true)
			self:End(self:Other(F), self.spar and "Stopped" or "TKO", "Doctor stops the fight (" .. why .. ")")
			return
		end
	end
	local O = self.O
	-- (never in the guided bout before its final round: the lesson is the player's to finish)
	local guided = self.tutorial ~= nil and (not self.debut or (self.round or 0) + 1 < (self.rounds or 0) or self:Protected(O))
	if not self.spar and not guided and not O.isPlayer and (O.healthCap < 40 or O.conc > 0.8) and self:EstimateLead(O) < -2 and self.rng:NextNumber() < 0.3 then
		self:End(self.P, "RTD", "Opponent's corner retires them")
	end
end

-- one fighter's ring walk: his own client walks a player (and plays his music / intro); everybody else
-- gets the "opp" walkout shot; an NPC is walked by the server
function Fight:WalkOut(W, steps, pyro)
	self:SendEach(function(V)
		if V == W then
			return { t = "entrance", phase = "you", music = W.data.music, target = steps, pyro = pyro,
				intro = Config.AnnouncerIntro[W.data.voice or "Calm"] or Config.AnnouncerIntro.Calm }
		end
		return { t = "entrance", phase = "opp", pyro = pyro }
	end)
	if not W.isPlayer and W.hum then
		W.hum.WalkSpeed = 8
		W.hum:MoveTo(steps)
	end
end

function Fight:Entrance()
	local P, O = self.P, self.O
	-- [Entrance] the cinematic ring walk: RingWalk runs the Shared.Entrance beats (and ends in the corners)
	if RingWalk then
		local okW, errW = pcall(RingWalk.Run, self)
		if okW then
			return
		end
		warn("[Boxer] RingWalk failed:", errW)
		if self.aborted then
			return
		end
	end
	local isStadium = self.venue == "Stadium"
	pcall(Builder.SetRobe, O.model, O.data.app, true, O.data.lookOpts)
	pcall(Builder.SetRobe, P.model, P.data.app, true, P.data.lookOpts)
	-- a tournament belt he won, round the waist over the robe for the walk (data.walkBelt: Tourney.WornBelt)
	self:WalkBelt(P, true)
	self:Place(O, self.anchors.BlueEntrance.Position, self.anchors.RingCenter.Position)
	self:Place(P, self.anchors.RedEntrance.Position, self.anchors.RingCenter.Position)
	for _, F in ipairs({ P, O }) do
		F.guardOverride = "walkout"
		F.exprOverride = (F.data.mental.Confidence or 50) > 60 and "confident" or "determined"
		self:UpdateGuard(F)
		self:SyncAttrs(F)
	end
	task.wait(0.5)
	self:Comment("Making the walk now... " .. O.data.name .. "!", true)
	self:WalkOut(O, self.anchors.BlueSteps.Position, isStadium)
	task.wait(isStadium and 6 or 4.5)
	if self.aborted then
		return
	end
	self:Place(O, self.anchors.BlueCorner.Position)
	self:WalkOut(P, self.anchors.RedSteps.Position, isStadium)
	task.wait(isStadium and 7 or 5.5)
	if self.aborted then
		return
	end
	self:Place(P, self.anchors.RedCorner.Position)
	pcall(Builder.SetRobe, P.model, P.data.app, false)
	pcall(Builder.SetRobe, O.model, O.data.app, false)
	self:WalkBelt(P, false)
end

-- the ring walk's belt (on = true builds it round the LowerTorso, false takes it off): BeltModel's worn loop, welded
function Fight:WalkBelt(F, on)
	if F.walkBelt then
		F.walkBelt:Destroy()
		F.walkBelt = nil
	end
	local key = F.data and F.data.walkBelt
	if not (on and key and BeltModel and Tournaments and F.model) then
		return
	end
	pcall(function()
		local lt = F.model:FindFirstChild("LowerTorso")
		local design = Tournaments.Design(key, Config.Orgs)
		if not (lt and design) then
			return
		end
		-- over the robe: a little wider than the bare waist
		local robe = F.model:FindFirstChild("BoxerLook") and F.model.BoxerLook:FindFirstChild("Robe")
		local pad = robe and 0.28 or 0.04
		local m = BeltModel.Build(design, { mode = "worn", waist = lt.Size + Vector3.new(pad, 0, pad), anchored = false, cframe = lt.CFrame * CFrame.new(0, 0.05, 0), name = "WalkBelt" })
		local w = Instance.new("WeldConstraint")
		w.Part0 = lt
		w.Part1 = m.PrimaryPart
		w.Parent = m.PrimaryPart
		m.Parent = F.model
		F.walkBelt = m
	end)
end

-- Before every round: both fighters stand in their own corners, held there (no steps, no punches - the
-- fight is not live, so the engine refuses every input), while the clients count 3 - 2 - 1 - BOX!. The
-- server owns the timing: one "countdown" message per beat, n = 0 is the bell. Movement comes back on GO.
local COUNT_BEAT = 0.8
FightEngine.COUNT_BEAT = COUNT_BEAT
function Fight:HoldCorners()
	local red, blue = self.anchors.RedCorner.Position, self.anchors.BlueCorner.Position
	for _, X in ipairs({ { self.P, red, blue }, { self.O, blue, red } }) do
		local F = X[1]
		if F.root and F.model and F.model.Parent then
			local p = F.root.Position
			local want = X[2]
			-- re-place only when he is not already there (a quiet corner stays quiet)
			if flat(p - want).Magnitude > 1.2 or not F.cornerHeld then
				self:Place(F, want, X[3])
			end
			F.cornerHeld = true
			if F.align then
				local dir = flat(X[3] - want)
				if dir.Magnitude > 0.05 then
					F.align.CFrame = CFrame.lookAt(Vector3.zero, dir.Unit)
					F.alignDir = nil -- UpdateMovement writes its next facing whatever it is
				end
			end
		end
		if F.hum and F.hum.Parent then
			F.hum.WalkSpeed = 0
			if not F.isPlayer then
				F.aiTarget = nil
				F.hum:MoveTo(F.root and F.root.Position or Vector3.zero)
			end
		end
		F.blocking = false
		if F.state ~= "down" then
			F.state = "idle"
		end
	end
end

function Fight:Countdown()
	self.live = false
	self.inCountdown = true
	for _, F in ipairs({ self.P, self.O }) do
		F.cornerHeld = false
	end
	self:HoldCorners()
	task.wait(0.6)
	for n = 3, 0, -1 do
		if self.finished or self.aborted then
			break
		end
		self:HoldCorners()
		self:Send({ t = "countdown", n = n, round = self.round })
		if n > 0 then
			-- hold the corners through the beat (a client that ignores WalkSpeed 0 is put back)
			local t0 = self:Now()
			while self:Now() - t0 < COUNT_BEAT and not self.finished and not self.aborted do
				task.wait(0.1)
				self:HoldCorners()
			end
		end
	end
	self.inCountdown = false
end

function Fight:ReleaseCorners()
	for _, F in ipairs({ self.P, self.O }) do
		F.cornerHeld = false
	end
	-- UpdateMovement sets each fighter's real speed from the next frame on
end

-- a fighter's unlocked special moves as an ordered list of ids (Moves.List order)
local function movesList(F)
	local out = {}
	if Moves then
		for _, id in ipairs(Moves.List) do
			if F.moves[id] then
				table.insert(out, id)
			end
		end
	end
	return out
end

local function femaleOf(F)
	return type(F.data.app) == "table" and F.data.app.gender == 2
end

-- a round's fresh start (Run, and the balance sims' own loop): the tallies, the round's momentum for the judges,
-- the AI's game plan
function Fight:StartRound(r)
	self.round = r
	self.momSum = 0
	for _, F in ipairs({ self.P, self.O }) do
		F.tally = { landed = 0, power = 0, body = 0, thrown = 0, kd = 0, clinches = 0, inside = 0 }
		F.guardOverride = nil
		F.exprOverride = nil
		self:UpdateGuard(F)
	end
	for _, F in ipairs({ self.P, self.O }) do
		if F.ai then
			F.ai:UpdateMode()
		end
	end
end

-- the ring traits on tonight: an AI boxer's (Shared.Traits) in a career bout only - never in a spar, the tutorial
-- or the guided debut, never for a player
function Fight:EnableTraits()
	for _, F in ipairs({ self.P, self.O }) do
		F.traits = {}
		if not F.isPlayer and not self.spar and not self.tutorial and not self.pvp then
			F.traits = F.traitsAll or {}
		end
	end
end

-- the scouting of F's traits for the tale of the tape (Traits.Scout: on the tapes, met before, an elite corner)
function Fight:ScoutTraits(F, viewer)
	if #F.traits == 0 then
		return nil
	end
	local list = Traits.Scout(F.traits, { fights = F.data.record, h2h = F.data.h2h, elite = viewer and viewer.data.eliteCorner })
	local out = {}
	for _, t in ipairs(list) do
		local D = Traits.Data[t.id]
		if t.known then
			F.traitSeen[t.id] = true
			table.insert(out, { id = t.id, name = D.name, desc = D.desc, counter = D.counter })
		else
			table.insert(out, { hidden = true })
		end
	end
	return out
end

function Fight:Run()
	local P, O = self.P, self.O
	local offer = self.offer
	self.knockdowns = {}
	self:EnableTraits()
	for _, F in ipairs({ P, O }) do
		setAttr(F.model, "Style", F.style.id)
		self:SyncAttrs(F)
	end
	self:SpawnReferee()
	local function tapeOf(F)
		local t = { name = F.data.name, nick = F.data.nick, nat = F.data.nat, record = F.data.record, height = F.data.height, reach = F.data.reach, style = F.style.name,
			overall = Config.Overall(F.data.stats), female = femaleOf(F) }
		if F.isPlayer then
			-- PvP: the HUD names the Roblox account behind the boxer (and the record is the PvP one)
			t.player = self.pvp and F.player and ("@" .. F.player.Name) or nil
			t.rating = self.pvp and F.data.pvpRating or nil
		else
			t.archetype = (Config.FindById(Config.Archetypes, F.data.archetype) or {}).name
			-- the scouting report on his ring traits (the hidden ones as "?"; revealed in the fight: `trait`)
			t.traits = self:ScoutTraits(F, self:Other(F))
		end
		return t
	end
	self:SendEach(function(V)
		local X = self:Other(V)
		return {
			t = "start", rounds = self.rounds, kind = offer.kind, stakes = offer.stakes or {}, playerStakes = offer.playerStakes or {},
			arena = self.arena, oppModel = X.model, venue = self.venue, venueName = offer.venueName or "", spar = self.spar,
			weighIn = V.data.mods and V.data.mods.weighIn, notes = V.data.mods and V.data.mods.notes,
			refModel = self.ref and self.ref.model, allowKD = self.allowKD, pvp = self.pvp,
			tape = { you = tapeOf(V), opp = tapeOf(X) },
			talk = V == P and offer.talk or "", myLine = V == P and offer.myLine or "",
			-- the special moves this viewer may throw (ids) and the aim-assist level the server will honour
			moves = movesList(V), assist = V.assist,
			-- the hit detection's frames (HitGeometry): the client's prediction and range read-out run on these
			geo = { you = V.geo, opp = X.geo, floor = (self.sp or SPACING).min },
			-- the first-time tutorial: the client puts its step card up
			tutorial = self.tutorial and Tutorial and { total = #(self.tutorial.steps or Tutorial.STEPS), special = self.tutorial.special or (not self.debut and Tutorial.SPECIAL) or nil,
				debut = self.debut or nil } or nil,
		}
	end)
	if self.tutorial and Tutorial then
		self:SendTo(P, Tutorial.View(self.tutorial))
	end
	-- the Animator only drives tagged models: tag now so the ring walk / warm-up (Guard "walkout") is animated
	-- (E's integration request; the later AddTag calls are harmless no-ops)
	CollectionService:AddTag(P.model, "Fighter")
	CollectionService:AddTag(O.model, "Fighter")
	if self.spar or (self.tutorial and not self.debut) then
		self:Place(O, self.anchors.BlueCorner.Position)
		self:Place(P, self.anchors.RedCorner.Position)
		task.wait(1.5)
	else
		self:Entrance()
		if self.aborted then
			return nil
		end
	end
	self:SetupFacing(P)
	self:SetupFacing(O)
	CollectionService:AddTag(P.model, "Fighter")
	CollectionService:AddTag(O.model, "Fighter")
	if not self.spar and (not self.tutorial or self.debut) then
		self:Send({ t = "tape" })
		self:Wait(5)
	end

	for r = 1, self.rounds do
		if self.finished or self.aborted then
			break
		end
		self.round = r
		self:StartRound(r)
		self:SetSweat(math.min(1, (r - 1) / math.max(1, self.rounds - 1) * 1.1 + 0.1))
		-- (a Shift held over the bell is let go here and on the client's `round`: a fresh press for the new round)
		P.sprintOn, O.sprintOn = false, false
		self:Send({ t = "round", n = r, total = self.rounds })
		if r == 1 then
			self:Comment(self.spar and "Sparring session starts. Work on your craft." or (self.debut and "The debut! Follow your coach's steps on screen."
				or (self.tutorial and "Your first fight. Follow the steps on screen." or "Here we go! Round one!")), true)
		elseif r == self.rounds then
			self:Comment("Final round! Everything on the line!", true)
		end
		-- both men wait in their own corners for the bell, then 3 - 2 - 1 - BOX!
		self:Countdown()
		if self.finished or self.aborted then
			break
		end
		self.live = true
		self.paused, self.kdHold, self.menuHold = false, false, false
		self.resumedAt = self:Now()
		P.assistCount, O.assistCount = 0, 0
		self:ReleaseCorners()
		local remaining = self.roundSeconds
		self.roundEnd = self:Now() + remaining
		while remaining > 0 and not self.finished and not self.aborted do
			local dt = RunService.Heartbeat:Wait()
			self:UpdateMenuHold(self:Now())
			-- the tutorial holds the clock while a step is being learned; round 1 ends soon after its last step
			local tphase = self.tutorial and Tutorial and Tutorial.Phase(self.tutorial, r, self:Now()) or nil
			if tphase == "break" and self.tutorialBreak ~= r then
				self.tutorialBreak = r
				remaining = math.min(remaining, Tutorial.BREAK_SECONDS)
				self.roundEnd = self:Now() + remaining
			end
			if self.paused or tphase == "hold" then
				self.roundEnd += dt
			else
				remaining -= dt
			end
			self:Update(dt)
			if self.tutorial and not (self.player and self.player.Parent) then
				-- (the player left: nothing would ever move a held clock on)
				self.aborted, self.finished = true, true
			end
		end
		self.live = false
		if self.menuHold then
			-- (the fight ended under the menu's hold: a forfeit, a disconnect)
			self.menuHold, self.paused = false, false
			self:SendTo(P, { t = "pause", on = false })
		end
		if self.finished or self.aborted then
			break
		end
		local rc = self:ScoreRound()
		-- (the bell ends every running combination)
		self:CloseChain(P)
		self:CloseChain(O)
		self:Send({ t = "bell", n = r })
		if self.tutorial then
			self:TutorialNote({ k = "bell" })
			if self.tutorial.done and not self.finished and not self.debut then
				self:End(P, "Tutorial", "Tutorial complete")
				break
			end
		end
		if r < self.rounds then
			self:Rest()
			if self.debut and r + 1 >= self.rounds then
				self:DebutFinalRest()
			end
			if not self.tutorial or (self.debut and r + 1 >= self.rounds) then
				self:DoctorCheck()
			end
			if self.finished then
				break
			end
			local avgP, avgO = 0, 0
			for j = 1, 3 do
				avgP += self.cards[j][1]
				avgO += self.cards[j][2]
			end
			local uP, uO = math.floor(avgP / 3 + 0.5), math.floor(avgO / 3 + 0.5)
			self:SendEach(function(V)
				local X = self:Other(V)
				local red = V == P -- the cards are kept red corner first
				return {
					t = "rest", n = r, advice = self:CornerAdvice(V), card = red and rc[1] or { rc[1][2], rc[1][1] },
					unofficial = red and { uP, uO } or { uO, uP },
					stats = { landed = V.totals.landed, thrown = V.totals.thrown, oppLanded = X.totals.landed, oppThrown = X.totals.thrown,
						combos = V.comboStats.landed, oppCombos = X.comboStats.landed, bestCombo = V.comboStats.best, bestComboName = V.comboStats.bestName },
					seconds = Config.RestSeconds, cond = self:ConditionReport(V),
				}
			end)
			self:Wait(self.spar and 4 or (self.tutorial and Tutorial and not self.debut and Tutorial.REST_SECONDS) or Config.RestSeconds)
		end
	end
	if self.aborted then
		return nil
	end

	local res
	if self.finished then
		res = self.sparExit or { outcome = self.winner == P and "win" or "loss", method = self.method, reason = self.reason, round = self.endRound or self.round }
	else
		-- [Judging] the three judges' totals decide it (unanimous / split / majority / draw; Career's rule as the fallback)
		res = Judging and Judging.Decide(self.cards) or Career.DecideCards(self.cards)
		res.round = self.rounds
		res.reason = self.spar and "Session complete" or ((self.tutorial and not self.debut) and "Tutorial complete" or "Decision")
	end
	-- the winner celebrates, the loser slumps (the Animator reads Guard / Expr)
	for _, F in ipairs({ P, O }) do
		local won = (F == P and res.outcome == "win") or (F == O and res.outcome == "loss")
		if F.state ~= "down" then
			F.guardOverride = res.outcome == "draw" and "rest" or (won and "win" or "lose")
		end
		F.exprOverride = won and "happy" or (F.state == "down" and (F.downSeverity == "out" and "ko" or "dazed") or "fatigue")
		self:UpdateGuard(F)
		self:SyncAttrs(F)
	end
	-- the red corner's result is the one Run returns; a PvP bout also keeps the blue corner's (self.results)
	self.results = { [P] = self:ResultFor(P, res), [O] = self:ResultFor(O, res) }
	return self.results[P]
end

-- the result from fighter F's side. base is the red corner's { outcome, method, reason, round }.
function Fight:ResultFor(F, base)
	local O = self:Other(F)
	local red = F == self.P
	local res = { method = base.method, reason = base.reason, round = base.round, partial = base.partial }
	local FLIP_OUT = { win = "loss", loss = "win" }
	res.outcome = red and base.outcome or (FLIP_OUT[base.outcome] or base.outcome)
	if red then
		res.cards = self.cards
	else
		res.cards = {}
		for j, c in ipairs(self.cards) do
			res.cards[j] = { c[2], c[1] }
		end
	end
	res.kdFor = O.kdTotal
	res.kdAgainst = F.kdTotal
	res.landed, res.thrown = F.totals.landed, F.totals.thrown
	res.oppLanded, res.oppThrown = O.totals.landed, O.totals.thrown
	res.punches = F.punchesUsed
	res.damageDealt, res.damageTaken = F.damageDealt, F.damageTaken
	res.weighIn = F.data.mods and F.data.mods.weighIn
	-- a cut counts when it was opened (or ripped open further) tonight, not when an old one merely shows
	local cutNow = math.max(F.dmg.cut, F.dmg.cut2)
	res.cutTaken = cutNow > 0.3 and cutNow > (F.cutAtStart or 0) + 0.1
	-- persistence hand-off (CONTRACTS section 8): Career / Training carry these into the profile
	res.face = tonightDamage(F)
	res.oppFace = tonightDamage(O)
	res.concPeak = math.floor(F.concPeak * 100) / 100
	res.noseBroken = F.dmg.nose == true and not F.noseAtStart
	-- the profile residual already carries an old break (AddFaceDamage never clears it): only a fresh one is news
	res.face.nose = res.noseBroken
	if red then
		res.knockdowns = self.knockdowns
	else
		res.knockdowns = {}
		for i, k in ipairs(self.knockdowns) do
			local c = table.clone(k)
			c.who = FLIP[k.who] or k.who
			res.knockdowns[i] = c
		end
	end
	res.bodyTaken = math.floor(100 - F.bodyCap)
	res.headTaken = math.floor(F.headTaken * 10) / 10 -- Training.AddTrauma prefers this over damageTaken
	-- the combinations (Combos.Record: chains of 2+, named combos landed, the best chain and the best named one)
	-- and the head movement (dodges tried, punches they made miss)
	self:CloseChain(F)
	self:CloseChain(O)
	local cs = F.comboStats
	res.combos = { chains = cs.chains, landed = cs.landed, best = cs.best, bestName = cs.bestName, named = table.clone(cs.named) }
	res.oppCombos = { landed = O.comboStats.landed, best = O.comboStats.best, bestName = O.comboStats.bestName }
	res.dodges, res.evades = F.dodges, F.evades
	-- the deeper fight: his fighting type tonight (Traits.FightingType), the other man's ring traits he found out,
	-- feints that drew a bite, second winds
	res.fightType = (self:FightingType(F))
	local found = {}
	for _, t in ipairs(O.traits or {}) do
		if O.traitSeen[t.id] then
			table.insert(found, t.id)
		end
	end
	res.oppTraits = found
	res.feints, res.feintBites, res.secondWinds = F.feints, F.feintBites, F.winds
	-- [Judging] the judges' report (per-round cards and reasons, the punch stats by type) and the decision as read
	res.judging = Judging and Judging.Report(self.judgeRounds or {}, self.cards, self.judgeTotals or {}, not red) or nil
	res.scores, res.decisionText = base.scores, base.text
	return res
end

local FIGHT_ATTRS = { "Guard", "Act", "Chain", "HeadHP", "BodyHP", "Stam", "Daze", "Conc", "Strain", "DownPose", "DownDir", "DownDist", "KOKind", "Count", "Style", "Expr" }

function Fight:Cleanup()
	for _, F in ipairs({ self.P, self.O }) do
		leaveBoxers(F)
		if F.model then
			CollectionService:RemoveTag(F.model, "Fighter")
			for _, k in ipairs(FIGHT_ATTRS) do
				F.model:SetAttribute(k, nil)
			end
		end
		if F.align then
			F.align:Destroy()
		end
		if F.alignAtt then
			F.alignAtt:Destroy()
		end
	end
	for _, P in ipairs({ self.P, self.O }) do
		if P.isPlayer then
			self:RestorePlayer(P)
		end
	end
	if self.ref and self.ref.noclip then
		self.ref.noclip:Disconnect()
		self.ref.noclip = nil
	end
	if self.arena then
		self.arena:Destroy()
	end
end

-- a player's own character after the fight: movement, jump, the neck, robe / headgear / fight damage off
function Fight:RestorePlayer(P)
	if P.hum and P.neckOff then
		-- FightClient re-enables the rig 2.2 s after "final"; Cleanup runs 3 s after it, so wait a little longer
		-- before the neck is required again (a slow client would otherwise die on the spot)
		local hum = P.hum
		task.delay(4, function()
			if hum.Parent then
				hum.RequiresNeck = true
			end
		end)
	end
	if P.hum then
		P.hum.AutoRotate = true
		P.hum.WalkSpeed = Config.TownWalkSpeed
		P.hum.JumpHeight = 7.2
	end
	if P.model and P.model.Parent then
		-- put the hair back right away (Cosmetics would also reconcile it on the next applyLook)
		pcall(Builder.SetRobe, P.model, P.data.app, false)
		-- (the sparring corner's colour off: a boxer's own headgear, Config.AlwaysHeadgear, stays on in his colour)
		pcall(Builder.SetHeadgear, P.model, Color3.new(), false)
		local look = P.model:FindFirstChild("BoxerLook")
		if look then
			-- the next applyLook redraws the healing residual through opts.damage (Training.FaceView)
			local own = Builder.HasOwnHeadgear(P.model)
			for _, n in ipairs(own and { "Damage", "Robe" } or { "Damage", "Robe", "Headgear" }) do
				local f = look:FindFirstChild(n)
				if f then
					f:Destroy()
				end
			end
		end
		pcall(Builder.SetSweat, P.model, P.data.app, 0)
	end
end

------------------------------------------------------------------------
-- The celebration cutscene (FightEngine.Run opts.ceremony = Tourney.CeremonyFor's spec: belt key, kicker, title,
-- event, name), after the final bell of a won tournament final or a new title. The server owns it: it stands the
-- winner in the centre of the ring, brings the referee to his side and an official in with the belt, sets the poses
-- (Pose on a "Trainee": BoxerClient.AnimCeremony's poses, played by the Animator) on the shared beats
-- (Shared.Tournaments.Ceremony), and tells the winner's client once (t = "ceremony"). The client
-- (BoxerClient.Ceremony) runs the camera, confetti, pyro, spotlights, the banner and the belt's visuals, and may
-- cut it short (t = "ceremonySkip"); "ceremonyEnd" closes it either way. Nothing is awarded here: Career does that.
------------------------------------------------------------------------
local function setPose(model, pose)
	if model and model.Parent then
		model:SetAttribute("Pose", pose)
	end
end

function Fight:Ceremony(spec)
	local P, O = self.P, self.O
	local B = Tournaments and Tournaments.Ceremony
	if not (B and P.model and P.model.Parent and P.root and self.anchors.RingCenter) then
		return
	end
	local center = self.anchors.RingCenter.Position
	local toRed = flat(self.anchors.RedCorner.Position - center)
	toRed = toRed.Magnitude > 0.1 and toRed.Unit or Vector3.new(0, 0, -1)
	-- he faces a ring side (between his corner and the next post), the hard camera's side
	local face = CFrame.Angles(0, math.rad(45), 0):VectorToWorldSpace(toRed)
	local right = face:Cross(Vector3.yAxis)
	self:Place(P, center, center + face * 10)
	if O.model and O.model.Parent then
		self:Place(O, self.anchors.BlueCorner.Position, center)
	end
	if P.hum then
		P.hum.WalkSpeed = 0
		P.hum.AutoRotate = false
	end
	-- the winner's poses come from the Animator's Trainee path (a Fighter plays guards only)
	CollectionService:RemoveTag(P.model, "Fighter")
	CollectionService:AddTag(P.model, "Trainee")
	setPose(P.model, "cerProud")
	local function stand(model, pos, look)
		local root = model and model:FindFirstChild("HumanoidRootPart")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if root then
			local y = center.Y + standHeight(hum, root)
			model:PivotTo(CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(look.X, y, look.Z)))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	-- the referee at his right shoulder, facing the same way (his left hand takes the winner's right)
	local refModel = self.ref and self.ref.model
	if refModel and refModel.Parent then
		local at = center + right * 2.1
		stand(refModel, at, at + face * 5)
		if self.ref.hum then
			self.ref.hum:MoveTo(at)
		end
	end
	-- the official with the belt, waiting by the ropes in front of him
	local official
	pcall(function()
		local app, build, gear, lopts = Officials.Look(self.rng:NextInteger(1, 2 ^ 30), "referee", { venue = self.venue, kind = "World Title" })
		official = Builder.CreateNPC(app, build, gear, "Official", lopts)
	end)
	if official then
		official.Name = "Official"
		for _, d in ipairs(official:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
			end
		end
		official.Parent = self.arena
		stand(official, center + face * 6.5 - right * 1.2, center)
		local oroot = official:FindFirstChild("HumanoidRootPart")
		if oroot then
			pcall(function()
				oroot:SetNetworkOwner(nil)
			end)
		end
		CollectionService:AddTag(official, "Trainee")
	end
	local ohum = official and official:FindFirstChildOfClass("Humanoid")
	if ohum then
		ohum.WalkSpeed = 7
	end
	self.ceremonySkip = false
	self:SendTo(P, { t = "ceremony", spec = spec, winner = P.model, ref = refModel, official = official, center = center, face = face, beats = B })
	-- the beats (the client's camera runs on the same clock from the message's arrival)
	local plan = {
		{ B.raise, function()
			setPose(refModel, "cerRaise")
			setPose(P.model, "cerHandUp")
		end },
		{ B.walkIn, function()
			setPose(refModel, "cerClap")
			setPose(P.model, "cerProud")
			if ohum then
				ohum:MoveTo(center + face * 1.75)
			end
			if refModel and self.ref.hum then
				self.ref.hum:MoveTo(center + right * 3.1 - face * 0.9)
			end
		end },
		{ B.strap, function()
			if official then
				stand(official, center + face * 1.75, center)
			end
			setPose(official, "cerStrap")
			setPose(P.model, "cerStrapped")
		end },
		{ B.strap + 1.5, function()
			setPose(official, "cerClap")
			if ohum then
				ohum:MoveTo(center - right * 2.7 - face * 1.1)
			end
		end },
		{ B.lift, function()
			setPose(P.model, "cerLift")
		end },
		{ B.wide, function()
			setPose(P.model, "cerCelebrate")
		end },
	}
	local t0 = os.clock()
	local nextBeat = 1
	while os.clock() - t0 < B.dur and not self.ceremonySkip and not self.aborted and P.model.Parent and (not self.player or self.player.Parent) do
		local t = os.clock() - t0
		while plan[nextBeat] and t >= plan[nextBeat][1] do
			pcall(plan[nextBeat][2])
			nextBeat += 1
		end
		task.wait(0.05)
	end
	self:SendTo(P, { t = "ceremonyEnd", skipped = self.ceremonySkip == true })
	-- hand the rigs back (Cleanup takes the Fighter attributes off and restores the player)
	setPose(P.model, nil)
	setPose(refModel, nil)
	CollectionService:RemoveTag(P.model, "Trainee")
	if official then
		official:Destroy()
	end
	task.wait(0.2)
end

------------------------------------------------------------------------
-- Entry point (yields until the fight ends). Returns result or nil if aborted.
-- opts: { spar = "Light"|"Medium"|"Hard"|"PvP", oppPlayer = Player (PvP: the blue corner is that player's
-- own character, driven by his inputs), rounds = n (PvP ranked: 3 or 6) }
-- Returns the red corner's result (nil if aborted) and the results table { [fighter] = res } whose
-- fighters carry .player, so a PvP caller can pick each side's result.
------------------------------------------------------------------------
local fightCounter = 0
function FightEngine.Run(player, remote, offer, pData, oData, arena, opts)
	opts = opts or {}
	fightCounter += 1
	local self = setmetatable({}, Fight)
	self.id = fightCounter
	self.player = player
	self.remote = remote
	self.offer = offer
	self.spar = opts.spar
	local sp = opts.spar and SPAR[opts.spar]
	local oppPlayer = typeof(opts.oppPlayer) == "Instance" and opts.oppPlayer:IsA("Player") and opts.oppPlayer or nil
	self.pvp = oppPlayer ~= nil
	self.rounds = (oppPlayer and tonumber(opts.rounds)) or (sp and sp.rounds) or offer.rounds
	self.roundSeconds = sp and Config.SparRoundSeconds or Config.RoundSeconds
	self.damageScale = sp and sp.damage or 1
	self.allowKD = (not sp) or sp.allowKD
	self.aiWork = sp and sp.work or 1
	self.aiRange = sp and sp.range or 1
	-- the first-time tutorial (opts.tutorial): short rounds on a held clock, guided steps, a forgiving
	-- opponent (FightAI reads aiWork / aiDefense), knockdowns only for the opponent and only at the end
	if opts.tutorial and Tutorial and not oppPlayer and not sp then
		self.tutorial = Tutorial.NewTracker()
		self.rounds = Tutorial.ROUNDS
		self.roundSeconds = Tutorial.ROUND_SECONDS
		self.aiWork = Tutorial.AiWork(self.tutorial)
		self.aiDefense = Tutorial.AI_DEFENSE
	elseif opts.debut and Tutorial and not oppPlayer and not sp then
		-- the guided debut (Tutorial.Debut): a real career bout, its own rounds, the same step card with the steps
		-- this boxer has (his first special move, if any), forgiving only for this night
		local special = nil
		if Moves and type(pData.moves) == "table" then
			for _, id in ipairs(Moves.List) do
				if pData.moves[id] then
					special = id
					break
				end
			end
		end
		self.debut = true
		self.tutorial = Tutorial.NewTracker({ debut = true, special = special, specialName = special and Moves.Data[special].name or nil, rounds = self.rounds })
		self.aiWork = Tutorial.AiWork(self.tutorial)
		self.aiDefense = Tutorial.AiDefense(self.tutorial)
	end
	self.venue = opts.spar and "Gym" or (offer.venue or "Arena")
	self.offerKind = offer.kind -- (a title fight's referee wears white: Officials.Colors)
	self.round = 0
	self.rng = Random.new()
	self.cards = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
	self.roundCards = {}
	self.knockdowns = {}
	self.arena = arena
	self.roundEnd = 0
	self.cutRisk = {}
	local anchors = {}
	for _, p in ipairs(arena:WaitForChild("Anchors"):GetChildren()) do
		anchors[p.Name] = p
	end
	self.anchors = anchors
	self.ringHalf = arena:GetAttribute("RingHalf") or 11

	-- fight-night look for the opponent (CONTRACTS section 4): full detail, taped fight gloves
	local npcOpts = table.clone(oData.lookOpts or {})
	npcOpts.hands, npcOpts.mouthguard = "gloves", true
	npcOpts.name, npcOpts.nick, npcOpts.nat, npcOpts.waistText = oData.name, oData.nick, oData.nat, oData.nick
	npcOpts.detail = "full"
	npcOpts.fightNight = not self.spar -- taped, inspector-signed, compact fight gloves (spars keep bag gloves)
	npcOpts.age = npcOpts.age or oData.age
	npcOpts.damage = type(oData.face) == "table" and oData.face or nil
	local npc
	if oppPlayer then
		-- PvP: the blue corner is the other player's own character (client-owned physics, like the red one)
		npc = oppPlayer.Character
		if not (npc and npc:FindFirstChild("HumanoidRootPart")) then
			arena:Destroy()
			return nil
		end
		local oOpts = table.clone(oData.lookOpts or {})
		oOpts.hands, oOpts.mouthguard, oOpts.fightNight, oOpts.detail = "gloves", true, not self.spar, "full"
		Builder.Cosmetics(npc, oData.app, oData.build, oData.gear, oOpts)
	else
		npc = Builder.CreateNPC(oData.app, oData.build, oData.gear, oData.name, npcOpts)
		if not npc then
			arena:Destroy()
			return nil
		end
		npc.Parent = arena
		local npcRoot = npc:FindFirstChild("HumanoidRootPart")
		if npcRoot then
			npcRoot:SetNetworkOwner(nil)
		end
	end
	local char = player.Character
	if not char then
		arena:Destroy()
		return nil
	end
	-- fight-night look for the player: gloves on, mouthguard in
	local lookOpts = table.clone(pData.lookOpts or {})
	lookOpts.hands = "gloves"
	lookOpts.mouthguard = true
	lookOpts.fightNight = not self.spar
	lookOpts.detail = "full"
	Builder.Cosmetics(char, pData.app, pData.build, pData.gear, lookOpts)
	if self.spar then
		-- the corners' colours over each boxer's own headgear (RestorePlayer gives the player's back)
		Builder.SetHeadgear(char, Color3.fromRGB(30, 60, 160), true)
		Builder.SetHeadgear(npc, Color3.fromRGB(170, 25, 30), true)
	end
	self.P = makeFighter(pData, char, player)
	self.O = makeFighter(oData, npc, oppPlayer)
	self.pair = { self.P, self.O } -- the per-frame loops walk this (no new table every frame)
	-- the distances fit the bodies in the ring: athletic rigs carry deeper chests and bigger gloves than the
	-- classic one the spacing was fitted on, and a taller man needs more room to fall
	local kP, hP = rigSize(char, self.P.hum, self.P.root)
	local kO, hO = rigSize(npc, self.O.hum, self.O.root)
	self.rigK = (kP + kO) / 2
	self.sp = FightMotion and FightMotion.ScaledSpacing and FightMotion.ScaledSpacing(self.rigK) or SPACING
	for _, X in ipairs({ { self.P, hP }, { self.O, hO } }) do
		X[1].bodyK = FightMotion and FightMotion.BodyScale and FightMotion.BodyScale(X[2]) or 1
	end
	-- the hit detection's frames off the rigs now, in their rest pose (Fight:Geo; the start message hands the
	-- client the same numbers)
	self:Geo(self.P)
	self:Geo(self.O)
	if pData.injuryCut then
		self.cutRisk[self.P] = 1.8
	end
	if oppPlayer and oData.injuryCut then
		self.cutRisk[self.O] = 1.8
	end
	-- the residual damage is drawn from the first punch on (Cosmetics drew opts.damage, keep it in step)
	for _, F in ipairs({ self.P, self.O }) do
		if Config.FaceDamageScore(F.dmg) > 0 or F.dmg.ribsL > 0 or F.dmg.ribsR > 0 then
			self:RefreshDamage(F, true)
		end
	end
	if not oppPlayer then
		self.O.ai = FightAI.new(self.O, self.P, self)
	end
	FightEngine.Active[player] = self
	if oppPlayer then
		FightEngine.Active[oppPlayer] = self
	end

	local ok, res = pcall(function()
		return self:Run()
	end)
	if not ok then
		warn("[Boxer] Fight error:", res)
		res = nil
	end
	if res then
		self:SendEach(function(V)
			return { t = "final", result = self.results and self.results[V] or res, oppName = self:Other(V).data.name, spar = self.spar, pvp = self.pvp }
		end)
		task.wait(3)
		-- [Judging] the post-fight scene (PostFight: both men to the centre, the referee between them, the announcer
		-- reads the cards, the winner's hand goes up; the crowd's "FightResult"); not for sparring or the practice bout
		if PostFight and not self.aborted and not self.spar and not (self.tutorial and not self.debut) then
			local okP, errP = pcall(PostFight.Run, self, res, opts)
			if not okP then
				warn("[Boxer] postfight:", errP)
			end
		end
		-- the celebration cutscene (a won tournament final / a new title: Career's Tourney.CeremonyFor spec)
		if type(opts.ceremony) == "table" and res.outcome == "win" and not self.aborted and not self.spar and not self.pvp and not self.tutorial then
			local okC, errC = pcall(self.Ceremony, self, opts.ceremony)
			if not okC then
				warn("[Boxer] ceremony:", errC)
			end
		end
	end
	self:Cleanup()
	if FightEngine.Active[player] == self then
		FightEngine.Active[player] = nil
	end
	if oppPlayer and FightEngine.Active[oppPlayer] == self then
		FightEngine.Active[oppPlayer] = nil
	end
	return res, self.results
end

-- the fighter a player controls in his fight (P, or O in a PvP bout)
function Fight:FighterOf(player)
	if self.P and self.P.player == player then
		return self.P
	elseif self.O and self.O.player == player then
		return self.O
	end
	return nil
end

-- player input from the client
function FightEngine.Input(player, msg)
	local fight = FightEngine.Active[player]
	if not fight or type(msg) ~= "table" then
		return
	end
	local F = fight:FighterOf(player)
	if not F or F.gone then
		return
	end
	-- flood guard: a client may send at most 30 fight messages a second (the mash has its own 15/s cap)
	local now = fight:Now()
	if now - (F.inWindow or 0) >= 1 then
		F.inWindow = now
		F.inCount = 0
	end
	F.inCount = (F.inCount or 0) + 1
	if F.inCount > 30 then
		return
	end
	local t = msg.t
	if t == "device" then
		fight:SetDevice(F, msg.pad == true)
		return
	elseif t == "ceremonySkip" then
		-- (the celebration cutscene's SKIP: the server ends its timeline)
		fight.ceremonySkip = true
		return
	elseif t == "entranceSkip" then
		-- [Entrance] the ring walk's SKIP (RingWalk: vs the AI at once, in PvP once both asked)
		if RingWalk then
			RingWalk.Skip(fight, F)
		end
		return
	elseif t == "pause" then
		-- (not a fight input: the Moves & Controls window opened / closed)
		fight:MenuPause(F, msg.on == true)
		return
	elseif t == "leaveSpar" then
		-- the spar HUD's Leave Sparring (a spar only; a PvP spar or a fight ignores it)
		fight:LeaveSpar(F)
		return
	end
	-- which device the input came from (the client tags gamepad inputs): the aim assist reads it; a pad
	-- tag only counts while the server holds the fighter on the pad (Fight:SetDevice)
	if t ~= "mash" then
		if msg.pad == true and F.device == "pad" then
			F.padAt = now
		else
			F.kbdAt = now
		end
	end
	if t == "punch" and Config.Punches[msg.p] then
		fight:Punch(F, msg.p, msg.body == true, msg.counter == true)
	elseif t == "special" then
		fight:Special(F, msg.id)
	elseif t == "block" then
		fight:SetBlock(F, msg.on == true)
	elseif t == "slip" then
		fight:Slip(F, msg.dir == -1 and -1 or 1)
	elseif t == "dodge" and (msg.kind == "weave" or msg.kind == "duck" or msg.kind == "pull" or msg.kind == "sidestep") then
		fight:Dodge(F, msg.kind, msg.dir == -1 and -1 or 1)
	elseif t == "roll" then
		fight:Roll(F, msg.quick == true)
	elseif t == "parry" then
		fight:Parry(F)
	elseif t == "pivot" then
		fight:Pivot(F, msg.dir == -1 and -1 or 1)
	elseif t == "clinch" then
		fight:Clinch(F)
	elseif t == "feint" then
		fight:Feint(F)
	elseif t == "sprint" then
		fight:SetSprint(F, msg.on == true)
	elseif t == "mash" then
		if F.state == "down" then
			local now = fight:Now()
			-- at most 15 presses a second count (auto-clickers gain nothing)
			if now - (F.mashWindow or 0) >= 1 then
				F.mashWindow = now
				F.mashCount = 0
			end
			F.mashCount = (F.mashCount or 0) + 1
			if F.mashCount <= 15 then
				-- a "good" press = the client's sweeping marker was in the green zone; the marker passes
				-- the zone at most about three times a second, so faster "good" claims count as plain
				local worth = 1
				if msg.good == true and now - (F.goodAt or 0) >= GOOD_GAP then
					F.goodAt = now
					worth = 3
				end
				F.mash += worth
			end
		end
	end
end

function FightEngine.Abort(player)
	local fight = FightEngine.Active[player]
	if fight then
		fight.aborted = true
		fight.finished = true
	end
end

-- PvP: a player walks out of a bout that is under way (left the game, reset, died). After the first bell
-- that is a loss ("Forfeit") and the fight ends with a result for the other corner; before it (or in a
-- spar, when ranked = false) the bout is simply called off. Returns "forfeit" | "aborted" | nil.
function FightEngine.Forfeit(player, ranked)
	local fight = FightEngine.Active[player]
	if not fight then
		return nil
	end
	local F = fight:FighterOf(player)
	if not F then
		return nil
	end
	F.gone = true
	if ranked and not fight.aborted and (fight.round or 0) >= 1 then
		if not fight.finished then
			fight:End(fight:Other(F), "Forfeit", (F.data.name or "The opponent") .. " left the ring")
		end
		return "forfeit"
	end
	fight.aborted = true
	fight.finished = true
	return "aborted"
end

-- (for tools/sim/test_combos: the fight's methods and the fighter constructor, driven on stub models)
FightEngine._Fight = Fight
FightEngine._makeFighter = makeFighter

return FightEngine
