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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Builder = require(Shared:WaitForChild("Builder"))
local Looks = require(Shared:WaitForChild("Looks"))
-- R-anim: how fighters go down (DownPose / DownDir / DownDist / KOKind), nil-safe if missing
local FightMotion
do
	local fm = Shared:FindFirstChild("FightMotion")
	if fm then
		local ok, mod = pcall(require, fm)
		FightMotion = ok and mod or nil
	end
end
local FightAI = require(script.Parent.FightAI)
local Career = require(script.Parent.Career)
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

local SPAR = {
	Light = { rounds = 1, damage = 0.3, allowKD = false },
	Medium = { rounds = 2, damage = 0.55, allowKD = false },
	Hard = { rounds = 3, damage = 0.85, allowKD = true },
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
	}
	-- what the fighter walked in with, so the result reports only what happened in THIS fight
	-- (an old, healing broken nose or half-closed cut must not be "news" that restarts the healing clock)
	F.noseAtStart = F.dmg.nose == true
	F.cutAtStart = math.max(F.dmg.cut, F.dmg.cut2)
	return F
end

function Fight:Now()
	return os.clock()
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
function Fight:PunchRange(F, ptype)
	local base = SPACING.base + ((F.data.reach or 70) - 70) * 0.05 + ((F.data.height or 70) - 70) * 0.02
	-- never shorter than the closest the bodies get (MIN_SEP), so every punch can land up close
	return math.max(SPACING.min, base * (Config.Punches[ptype] and Config.Punches[ptype].range or 1))
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
-- Messaging & visuals
------------------------------------------------------------------------
function Fight:Send(msg)
	if self.player and self.player.Parent then
		self.remote:FireClient(self.player, msg)
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

function Fight:SetAct(F, act)
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
	if self.O.ai then
		self.O.ai:UpdateMode()
	end
end

------------------------------------------------------------------------
-- Actions (used by both the player's input and the AI)
------------------------------------------------------------------------
function Fight:CanAct(F)
	return not self.finished and self.live and not self.paused and F.state ~= "down" and F.state ~= "clinch"
end

function Fight:Punch(F, ptype, body)
	local P = Config.Punches[ptype]
	if not P or not self:CanAct(F) then
		return
	end
	local now = self:Now()
	if now < F.busyUntil then
		return
	end
	local O = self:Other(F)
	if O.state == "down" then
		return
	end
	if ptype == "overhand" then
		body = false
	end
	local s = F.data.stats
	local stamPct = F.stamina / F.maxStam
	local speedMul = (1.25 - s.PunchSpeed / 200) * (stamPct < 0.3 and 1.25 or 1)
	speedMul /= (1.08 - (F.data.class - 1) * 0.02) * F.speedMul
	-- a dazed or concussed fighter is a beat slow on everything
	speedMul *= (1 + CONC.tierWindup * F.tier) * (1 + CONC.windup * F.conc)
	local windup = P.windup * speedMul
	if now - F.lastPunch < 0.7 then
		F.combo += 1
		windup *= 0.88
	else
		F.combo = 1
	end
	F.lastPunch = now
	local cost = P.stam * (body and 1.1 or 1) * (1.2 - s.Endurance / 250) * (F.combo > 2 and 1.1 or 1)
	F.stamina = math.max(0, F.stamina - cost)
	F.blocking = false
	F.state = "punching"
	F.busyUntil = now + windup + windup * 0.9
	local hand = P.hand
	if ptype == "uppercut" then
		hand = (F.hand == "R" and F.combo > 1) and "L" or "R"
	end
	F.hand = hand
	self:SetAct(F, string.format("%s|%s|%s|%.2f", ptype, hand, body and "body" or "head", windup))
	F.tally.thrown += 1
	F.totals.thrown += 1
	F.punchesUsed[ptype] = (F.punchesUsed[ptype] or 0) + 1
	if O.ai then
		O.ai:OnOppPunch(ptype, body, windup)
	end
	local fightId = self.id
	task.delay(windup, function()
		if self.id == fightId and not self.finished then
			self:Resolve(F, O, ptype, body, stamPct)
		end
	end)
end

function Fight:Evaded(F, O, ptype, body, now)
	local kind = Config.Punches[ptype].kind
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
		return true
	end
	if now < O.slipUntil and not body then
		if kind == "straight" or (kind == "hook" and self.rng:NextNumber() < 0.5) then
			O.counterUntil = now + 0.85
			self:Send({ t = "defense", who = self:Who(O), move = "SLIPPED" })
			self:Comment(O.data.name .. " slips it beautifully!")
			return true
		end
	end
	if now < O.rollUntil and not body then
		if kind == "hook" or kind == "overhand" or (kind == "straight" and self.rng:NextNumber() < 0.5) then
			O.counterUntil = now + 0.8
			self:Send({ t = "defense", who = self:Who(O), move = "ROLLED UNDER" })
			self:Comment(O.data.name .. " rolls under it!")
			return true
		end
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
		self:Send({ t = "announce", text = (O == self.P and "You're" or O.data.name .. " is") .. " CUT!" })
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

function Fight:Resolve(F, O, ptype, body, stamPct)
	if F.state == "down" or O.state == "down" or F.state == "clinch" or O.state == "clinch" or not self.live then
		return
	end
	local P = Config.Punches[ptype]
	local s, os_ = F.data.stats, O.data.stats
	local now = self:Now()
	local dist = self:Distance(F, O)
	if dist > self:PunchRange(F, ptype) then
		self:Miss(F, O, ptype, "short")
		return
	end
	if self:Evaded(F, O, ptype, body, now) then
		if F.ai then
			F.ai.obs.slips += 1
		end
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
	-- concussion and daze cost accuracy
	chance *= (1 - CONC.hitChance * F.conc) * (1 - CONC.tierHitChance * F.tier)
	chance = math.clamp(chance * vision, 0.15, 0.95)
	-- clean = how cleanly it landed (feeds the knockdown odds); 0.5 when it comes through a guard
	local clean = 0.5
	if not O.blocking then
		local roll = self.rng:NextNumber()
		if roll > chance then
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
	if angled then
		dmg *= 1.1
	end
	if dist < SPACING.inside then
		if P.kind == "hook" or P.kind == "uppercut" then
			dmg *= F.style.fight.inside
		else
			dmg *= 0.85
		end
	end
	if F.combo >= 2 then
		dmg *= 1 + (F.style.fight.combo - 1) * 0.5
	end
	local counter = false
	if now < F.counterUntil then
		counter = true
		dmg *= 1.2 * F.style.fight.counter * (0.85 + s.Countering / 300)
		F.counterUntil = 0
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
	-- reference head damage for "how big was that": a solid cross at full strength is about 1
	local hdRef = 6 * HEAD_SCALE * self.damageScale

	-- block (the overhand comes over the top of the guard)
	if O.blocking and not body then
		local through = P.overGuard or 0
		local arms = 1.3 - 0.3 * math.clamp(O.stamina / O.maxStam, 0, 1)
		-- tired arms and a dazed, loose guard let more through
		local chip = dmg * math.clamp(0.28 - os_.Blocking / 400, 0.04, 0.25) * arms * (1 + 0.35 * O.tier)
		local hd = chip + dmg * through * HEAD_SCALE * 0.6 * (P.head or 1)
		self:HeadDamage(O, hd)
		O.stamina = math.max(0, O.stamina - (1.5 + dmg * 0.25))
		O.counterUntil = now + 0.55 * (os_.Countering / 70)
		O.balance -= (P.stun or 10) * 0.25
		self:Send({ t = "blocked", who = self:Who(O), punch = ptype })
		self:SetAct(O, "blockhit")
		self:CheckTier(O)
		return
	elseif O.blocking and body then
		dmg *= 0.75
	end

	-- landed
	F.tally.landed += 1
	F.totals.landed += 1
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
		local bd = dmg * 0.8 * (1.2 - os_.Endurance / 200) * (P.body or 1) * armor
		O.body = math.max(0, O.body - bd)
		O.stamina = math.max(0, O.stamina - dmg * 0.6 * (P.body or 1))
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
		elseif ptype == "leadhook" and F.hand == "L" and O.body < 60 and self.allowKD
			and self.rng:NextNumber() < 0.12 * (1.2 - os_.Endurance / 100) * math.clamp(bd / (5 * self.damageScale), 0.5, 1.5) then
			-- the liver sits under the right ribs: a left hook there drops people a beat AFTER it lands
			liver = true
		end
		fall = "knee"
	else
		local chinMul = 1.35 - os_.Chin / 100 * 0.7
		local hd = dmg * HEAD_SCALE * chinMul * (P.head or 1) * (O.dmg.cut > 0.5 and 1.08 or 1) * (1 + KO.tierDamage * O.tier)
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
			if self.rng:NextNumber() < p then
				kd = true
				severity = (flash and tierBefore == 0) and "flash" or nil
			end
		end
		O.conc = math.min(1, O.conc + hd * CONC.perHeadDamage * (P.ko or 1) * (1.3 - os_.Chin / 150))
		O.concPeak = math.max(O.concPeak, O.conc)
		-- balance: hooks and uppercuts take the legs, footwork keeps them
		local loss = (P.stun or 10) * math.clamp(rel, 0.2, 2.5) * (1.3 - os_.Footwork / 200) * (1 + 0.25 * O.tier) * (counter and 1.3 or 1)
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
	local sev = math.clamp(rel * 0.6 * (counter and 1.15 or 1), 0, 1.5)
	if body then
		self:SetAct(O, string.format("hitbody|%s|%s|%.2f", ptype, F.hand == "L" and "R" or "L", sev))
	else
		self:SetAct(O, string.format("hit|%s|%s|%.2f|%s", ptype, heavy and "heavy" or (counter and "counter" or "head"), sev, F.hand or "R"))
	end
	self:Send({
		t = "hit", who = self:Who(F), punch = ptype, body = body, dmg = math.floor(dmg * 10) / 10, counter = counter, heavy = heavy,
		hand = F.hand, sev = math.floor(sev * 100) / 100, bleed = (O.dmg.cut > 0.35 or O.dmg.cut2 > 0.35 or O.dmg.noseBleed > 0.4),
	})
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
		end
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
			if self.spar == "Medium" then
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
	F.blocking = on and true or false
	if F.state ~= "punching" then
		F.state = on and "blocking" or "idle"
	end
end

local function defenseReady(self, F, cost)
	if not self:CanAct(F) then
		return false
	end
	local now = self:Now()
	if now < F.busyUntil or F.stamina < cost then
		return false
	end
	F.stamina -= cost
	F.blocking = false
	F.state = "idle"
	return true
end

function Fight:Slip(F, dir)
	if not defenseReady(self, F, 4) then
		return
	end
	local now = self:Now()
	F.slipUntil = now + (0.26 + F.data.stats.Reflexes * 0.003 + F.data.stats.HeadMovement * 0.002) * self:DefenseMul(F)
	F.busyUntil = now + 0.42
	self:SetAct(F, "slip|" .. (dir == -1 and "L" or "R"))
end

function Fight:Roll(F)
	if not defenseReady(self, F, 5) then
		return
	end
	local now = self:Now()
	F.rollUntil = now + (0.3 + F.data.stats.HeadMovement * 0.003) * self:DefenseMul(F)
	F.busyUntil = now + 0.55
	self:SetAct(F, "roll")
end

function Fight:Parry(F)
	if not defenseReady(self, F, 2) then
		return
	end
	local now = self:Now()
	F.parryUntil = now + (0.18 + F.data.stats.Reflexes * 0.002) * self:DefenseMul(F)
	F.busyUntil = now + 0.32
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
	return self:CanAct(F) and O.state ~= "down" and self:Now() >= F.nextClinch and F.stamina >= 4 and self:Distance(F, O) < SPACING.clinch
end

function Fight:Clinch(F)
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
	end
	-- holding buys a hurt fighter time: a little head HP, the legs come back
	self:ClearStun(F, 6 + 3 * F.tier)
	F.balance = math.min(100, F.balance + 25)
	F.hurtUntil = math.min(F.hurtUntil, now + 0.6)
	self:CheckTier(F)
	self:Send({ t = "announce", text = self.spar and "COACH: \"Break! Let go, work your way out.\"" or "CLINCH! The referee steps in..." })
	self:Comment(F.data.name .. " ties up. Smart veteran move.")
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

function Fight:SpawnReferee()
	local ok, model = pcall(function()
		local seed = 9000 + self.rng:NextInteger(1, 50000)
		local age = self.spar and self.rng:NextInteger(45, 62) or self.rng:NextInteger(38, 58)
		local app = Looks.Random(seed, 1, {})
		local build = Looks.RandomBuild(seed, self.spar and 0.35 or 0.2, age)
		local outfit = self.spar and "cornerman" or "referee"
		return Builder.CreateNPC(app, build, {}, "Referee", { detail = "medium", outfit = outfit, hands = "bare", age = age, name = "", nick = "", waistText = "" })
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
	model:PivotTo(CFrame.lookAt(Vector3.new(pos.X, center.Y + 3.2, pos.Z), Vector3.new(center.X, center.Y + 3.2, center.Z)))
	model.Parent = self.arena
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local R = { model = model, root = root, hum = hum, actId = 0, nextMove = 0 }
	-- the Humanoid turns CanCollide back on for the head / torso parts in its own step; re-clear the rig
	-- parts before every physics step so he never shoves the NPC or jitters against the player in a clinch
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
local FALL_ROOM = { face = 5.0, forward = 4.2, standing = 5.0, knee = 3.8, flash = 3.8 }

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
				F.model:PivotTo(F.root.CFrame + d)
				if onArrive then
					onArrive()
				end
				break
			end
			F.model:PivotTo(F.root.CFrame + d * (step / m))
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
local CATCH_DIST = 2.4
function Fight:RefCatch(F)
	local R = self.ref
	if not (R and R.root and R.model.Parent and F.root) then
		return
	end
	local other = self:Other(F)
	local toward = other.root and flat(other.root.Position - F.root.Position) or flat(F.root.CFrame.LookVector)
	local d = unitOr(toward, Vector3.new(1, 0, 0))
	R.catching = { at = self:ClampToRing(F.root.Position + d * CATCH_DIST), look = F.root.Position, untilT = self:Now() + 6 }
	R.nextMove = 0
	self:RefAct(string.format("catch|%.1f", (FightMotion and FightMotion.CATCH_TIME or 2) + 1.4))
end

function Fight:Knockdown(F, by, severity, fall, cause)
	if F.state == "down" or self.finished then
		return
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
	-- how he goes down (R-anim FightMotion: the punch, the severity, where he stands in the ring)
	local choice = self:ChooseFall(F, by, severity, cause, fall)
	fall = choice.pose
	F.koKind = choice.ko
	table.insert(self.knockdowns, { who = self:Who(F), severity = severity, fall = fall, round = self.round, cause = cause })
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
		self.neckOff = true
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
	local target = 12 + F.kdTotal * 6 + (1 - ability) * 18 + F.conc * 15
	if sev == "flash" then
		target *= 0.35
	elseif sev == "heavy" then
		target *= 1.2
	end
	target = math.max(4, math.floor(target))
	if F.isPlayer then
		self:Send({ t = "getupStart", target = target, ability = ability, severity = sev })
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
		self.paused = false
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
	local p = Vector3.new(pos.X, pos.Y + 3.2, pos.Z)
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
local MIN_SEP, CLINCH_SEP = SPACING.minSep, 1.9

function Fight:MoveAI(F, range, circle)
	if not F.hum or F.state == "down" or F.state == "clinch" or self:IsStumbling(F) then
		return
	end
	local O = self:Other(F)
	local away = flat(F.root.Position - O.root.Position)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	away = away.Unit
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
	local minSep = (P.state == "clinch" or O.state == "clinch") and CLINCH_SEP or MIN_SEP
	local d = flat(O.root.Position - P.root.Position)
	local m = d.Magnitude
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
		X.model:PivotTo(X.root.CFrame + (goal - p))
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
			F.align.CFrame = CFrame.lookAt(Vector3.zero, dir.Unit)
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
			-- dazed legs and a concussion slow every step
			speed *= (1 - CONC.tierSpeed * F.tier) * (1 - CONC.speed * F.conc)
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
			F.model:PivotTo(F.root.CFrame + (goal - p))
		end
		local p = F.root.Position
		local clamped = self:ClampToRing(p)
		if (clamped - p).Magnitude > 0.5 then
			F.model:PivotTo(F.root.CFrame + (clamped - p))
		end
	end
end

------------------------------------------------------------------------
-- Per-frame update
------------------------------------------------------------------------
function Fight:Update(dt)
	local now = self:Now()
	for _, F in ipairs({ self.P, self.O }) do
		if F.state == "punching" and now >= F.busyUntil then
			F.state = F.blocking and "blocking" or "idle"
		end
		if F.state == "clinch" and now >= F.clinchUntil then
			F.state = "idle"
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
		if F.stamina < F.stamCap then
			F.stamina = math.min(F.stamCap, F.stamina + regen * dt)
		end
		if F.state ~= "down" then
			if now - F.lastHitAt > STUN_QUIET and F.stun > 0 then
				-- a badly hurt fighter clears his head more slowly
				self:ClearStun(F, (STUN_CLEAR + s.Recovery * STUN_CLEAR_PER_RECOVERY) * (1 - 0.4 * F.tier) * dt)
			end
			if now - F.lastBodyHitAt > 3 then
				F.body = math.min(F.bodyCap, F.body + 0.12 * dt)
			end
			-- the legs come back with footwork; slower while dazed
			F.balance = math.min(100, F.balance + (18 + s.Footwork * 0.15) * (1 - 0.25 * F.tier) * dt)
		end
		-- concussion clears slowly (Recovery helps); the peak is what follows the fighter home
		F.conc = math.max(0, F.conc - (CONC.decay + s.Recovery * CONC.decayPerRecovery) * dt)
		local strainFloor = (F.state == "clinch" and 0.8) or ((self:IsHurt(F) or F.tier >= 2) and 0.5) or 0
		F.strain = math.max(strainFloor, F.strain - dt * 0.5)
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
	if self.O.ai then
		self.O.ai:Observe(dt)
		if self.live and not self.paused then
			self.O.ai:Think(now)
		end
	end
	if self.P.blocking then
		self.P.blockTime = (self.P.blockTime or 0) + dt
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
		local P, O = self.P, self.O
		self:Send({
			t = "state",
			time = math.max(0, math.ceil(self.roundEnd - now)),
			me = { hp = P.health, cap = P.healthCap, body = P.body, bodyCap = P.bodyCap, stam = P.stamina, max = P.maxStam, stamCap = P.stamCap,
				hurt = self:IsHurt(P), angle = now < P.angleUntil, tier = P.tier, conc = P.conc, bal = P.balance },
			opp = { hp = O.health, cap = O.healthCap, body = O.body, bodyCap = O.bodyCap, stam = O.stamina, max = O.maxStam, stamCap = O.stamCap,
				hurt = self:IsHurt(O), tier = O.tier, conc = O.conc },
		})
	end
end

------------------------------------------------------------------------
-- Scoring & corner
------------------------------------------------------------------------
function Fight:ScoreRound()
	local P, O = self.P, self.O
	local function pts(F, other)
		local t = F.tally
		return t.landed * 1 + t.power * 0.8 + t.body * 0.5 + t.thrown * 0.04 - t.clinches * 0.3 + (other.tally.thrown - other.tally.landed) * 0.03
	end
	local pP, pO = pts(P, O), pts(O, P)
	local round = {}
	for j = 1, 3 do
		local diff = pP - pO + self.rng:NextNumber(-1.6, 1.6) * (j == 3 and 1.4 or 1)
		local a, b = 10, 10
		if diff > 0.7 then
			b = 9
		elseif diff < -0.7 then
			a = 9
		end
		a -= O.tally.kd
		b -= P.tally.kd
		a, b = math.max(6, a), math.max(6, b)
		self.cards[j][1] += a
		self.cards[j][2] += b
		round[j] = { a, b }
	end
	table.insert(self.roundCards, round)
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

function Fight:CornerAdvice()
	local P, O = self.P, self.O
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

function Fight:DoctorCheck()
	for _, F in ipairs({ self.P, self.O }) do
		local d = F.dmg
		local why
		if d.cut >= 1 or d.cut2 >= 1 then
			why = "cut"
		elseif d.leftEye >= 1 and d.rightEye >= 1 then
			why = "eyes swollen shut"
		elseif F.conc >= 0.92 and F.kdTotal >= 2 then
			why = "concussion"
		end
		if why then
			self:Comment("The ringside doctor has seen enough!", true)
			self:End(self:Other(F), self.spar and "Stopped" or "TKO", "Doctor stops the fight (" .. why .. ")")
			return
		end
	end
	local O = self.O
	if not self.spar and (O.healthCap < 40 or O.conc > 0.8) and self:EstimateLead(O) < -2 and self.rng:NextNumber() < 0.3 then
		self:End(self.P, "RTD", "Opponent's corner retires them")
	end
end

function Fight:Entrance()
	local P, O = self.P, self.O
	local isStadium = self.venue == "Stadium"
	pcall(Builder.SetRobe, O.model, O.data.app, true, O.data.lookOpts)
	pcall(Builder.SetRobe, P.model, P.data.app, true, P.data.lookOpts)
	self:Place(O, self.anchors.BlueEntrance.Position, self.anchors.RingCenter.Position)
	self:Place(P, self.anchors.RedEntrance.Position, self.anchors.RingCenter.Position)
	for _, F in ipairs({ P, O }) do
		F.guardOverride = "walkout"
		F.exprOverride = (F.data.mental.Confidence or 50) > 60 and "confident" or "determined"
		self:UpdateGuard(F)
		self:SyncAttrs(F)
	end
	task.wait(0.5)
	self:Send({ t = "entrance", phase = "opp", pyro = isStadium })
	self:Comment("Making the walk now... " .. O.data.name .. "!", true)
	O.hum.WalkSpeed = 8
	O.hum:MoveTo(self.anchors.BlueSteps.Position)
	task.wait(isStadium and 6 or 4.5)
	self:Place(O, self.anchors.BlueCorner.Position)
	self:Send({ t = "entrance", phase = "you", music = P.data.music, target = self.anchors.RedSteps.Position, pyro = isStadium,
		intro = Config.AnnouncerIntro[P.data.voice or "Calm"] or Config.AnnouncerIntro.Calm })
	task.wait(isStadium and 7 or 5.5)
	if self.aborted then
		return
	end
	self:Place(P, self.anchors.RedCorner.Position)
	pcall(Builder.SetRobe, P.model, P.data.app, false)
	pcall(Builder.SetRobe, O.model, O.data.app, false)
end

local function femaleOf(F)
	return type(F.data.app) == "table" and F.data.app.gender == 2
end

function Fight:Run()
	local P, O = self.P, self.O
	local offer = self.offer
	self.knockdowns = {}
	for _, F in ipairs({ P, O }) do
		setAttr(F.model, "Style", F.style.id)
		self:SyncAttrs(F)
	end
	self:SpawnReferee()
	self:Send({
		t = "start", rounds = self.rounds, kind = offer.kind, stakes = offer.stakes or {}, playerStakes = offer.playerStakes or {},
		arena = self.arena, oppModel = O.model, venue = self.venue, venueName = offer.venueName or "", spar = self.spar,
		weighIn = P.data.mods and P.data.mods.weighIn, notes = P.data.mods and P.data.mods.notes,
		refModel = self.ref and self.ref.model, allowKD = self.allowKD,
		tape = {
			you = { name = P.data.name, nick = P.data.nick, nat = P.data.nat, record = P.data.record, height = P.data.height, reach = P.data.reach, style = P.style.name, overall = Config.Overall(P.data.stats), female = femaleOf(P) },
			opp = { name = O.data.name, nick = O.data.nick, nat = O.data.nat, record = O.data.record, height = O.data.height, reach = O.data.reach, style = O.style.name, overall = Config.Overall(O.data.stats),
				archetype = (Config.FindById(Config.Archetypes, O.data.archetype) or {}).name, female = femaleOf(O) },
		},
		talk = offer.talk, myLine = offer.myLine,
	})
	-- the Animator only drives tagged models: tag now so the ring walk / warm-up (Guard "walkout") is animated
	-- (E's integration request; the later AddTag calls are harmless no-ops)
	CollectionService:AddTag(P.model, "Fighter")
	CollectionService:AddTag(O.model, "Fighter")
	if self.spar then
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
	if not self.spar then
		self:Send({ t = "tape" })
		task.wait(5)
	end

	for r = 1, self.rounds do
		if self.finished or self.aborted then
			break
		end
		self.round = r
		for _, F in ipairs({ P, O }) do
			F.tally = { landed = 0, power = 0, body = 0, thrown = 0, kd = 0, clinches = 0 }
			F.guardOverride = nil
			F.exprOverride = nil
			self:UpdateGuard(F)
		end
		if O.ai then
			O.ai:UpdateMode()
		end
		self:SetSweat(math.min(1, (r - 1) / math.max(1, self.rounds - 1) * 1.1 + 0.1))
		self:Send({ t = "round", n = r, total = self.rounds })
		if r == 1 then
			self:Comment(self.spar and "Sparring session starts. Work on your craft." or "Here we go! Round one!", true)
		elseif r == self.rounds then
			self:Comment("Final round! Everything on the line!", true)
		end
		task.wait(2)
		self.live = true
		self.paused = false
		self.resumedAt = self:Now()
		local remaining = self.roundSeconds
		self.roundEnd = self:Now() + remaining
		while remaining > 0 and not self.finished and not self.aborted do
			local dt = RunService.Heartbeat:Wait()
			if self.paused then
				self.roundEnd += dt
			else
				remaining -= dt
			end
			self:Update(dt)
		end
		self.live = false
		if self.finished or self.aborted then
			break
		end
		local rc = self:ScoreRound()
		self:Send({ t = "bell", n = r })
		if r < self.rounds then
			self:Rest()
			self:DoctorCheck()
			if self.finished then
				break
			end
			local avgP, avgO = 0, 0
			for j = 1, 3 do
				avgP += self.cards[j][1]
				avgO += self.cards[j][2]
			end
			self:Send({
				t = "rest", n = r, advice = self:CornerAdvice(), card = rc[1],
				unofficial = { math.floor(avgP / 3 + 0.5), math.floor(avgO / 3 + 0.5) },
				stats = { landed = P.totals.landed, thrown = P.totals.thrown, oppLanded = O.totals.landed, oppThrown = O.totals.thrown },
				seconds = Config.RestSeconds, cond = self:ConditionReport(P),
			})
			task.wait(self.spar and 4 or Config.RestSeconds)
		end
	end
	if self.aborted then
		return nil
	end

	local res
	if self.finished then
		res = { outcome = self.winner == P and "win" or "loss", method = self.method, reason = self.reason, round = self.endRound or self.round }
	else
		res = Career.DecideCards(self.cards)
		res.round = self.rounds
		res.reason = self.spar and "Session complete" or "Decision"
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
	res.cards = self.cards
	res.kdFor = O.kdTotal
	res.kdAgainst = P.kdTotal
	res.landed, res.thrown = P.totals.landed, P.totals.thrown
	res.oppLanded, res.oppThrown = O.totals.landed, O.totals.thrown
	res.punches = P.punchesUsed
	res.damageDealt, res.damageTaken = P.damageDealt, P.damageTaken
	res.weighIn = P.data.mods and P.data.mods.weighIn
	-- a cut counts when it was opened (or ripped open further) tonight, not when an old one merely shows
	local cutNow = math.max(P.dmg.cut, P.dmg.cut2)
	res.cutTaken = cutNow > 0.3 and cutNow > (P.cutAtStart or 0) + 0.1
	-- persistence hand-off (CONTRACTS section 8): Career / Training carry these into the profile
	res.face = cloneDamage(P.dmg)
	res.oppFace = cloneDamage(O.dmg)
	res.concPeak = math.floor(P.concPeak * 100) / 100
	res.noseBroken = P.dmg.nose == true and not P.noseAtStart
	-- the profile residual already carries an old break (AddFaceDamage never clears it): only a fresh one is news
	res.face.nose = res.noseBroken
	res.knockdowns = self.knockdowns
	res.bodyTaken = math.floor(100 - P.bodyCap)
	res.headTaken = math.floor(P.headTaken * 10) / 10 -- Training.AddTrauma prefers this over damageTaken
	return res
end

local FIGHT_ATTRS = { "Guard", "Act", "HeadHP", "BodyHP", "Stam", "Daze", "Conc", "Strain", "DownPose", "DownDir", "DownDist", "KOKind", "Count", "Style", "Expr" }

function Fight:Cleanup()
	for _, F in ipairs({ self.P, self.O }) do
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
	local P = self.P
	if P.hum and self.neckOff then
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
		P.hum.WalkSpeed = 16
		P.hum.JumpHeight = 7.2
	end
	if P.model and P.model.Parent then
		-- put the hair back right away (Cosmetics would also reconcile it on the next applyLook)
		pcall(Builder.SetRobe, P.model, P.data.app, false)
		pcall(Builder.SetHeadgear, P.model, Color3.new(), false)
		local look = P.model:FindFirstChild("BoxerLook")
		if look then
			-- the next applyLook redraws the healing residual through opts.damage (Training.FaceView)
			for _, n in ipairs({ "Damage", "Robe", "Headgear" }) do
				local f = look:FindFirstChild(n)
				if f then
					f:Destroy()
				end
			end
		end
		pcall(Builder.SetSweat, P.model, P.data.app, 0)
	end
	if self.ref and self.ref.noclip then
		self.ref.noclip:Disconnect()
		self.ref.noclip = nil
	end
	if self.arena then
		self.arena:Destroy()
	end
end

------------------------------------------------------------------------
-- Entry point (yields until the fight ends). Returns result or nil if aborted.
-- opts: { spar = "Light"|"Medium"|"Hard" }
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
	self.rounds = sp and sp.rounds or offer.rounds
	self.roundSeconds = sp and Config.SparRoundSeconds or Config.RoundSeconds
	self.damageScale = sp and sp.damage or 1
	self.allowKD = (not sp) or sp.allowKD
	self.venue = opts.spar and "Gym" or (offer.venue or "Arena")
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
	local npc = Builder.CreateNPC(oData.app, oData.build, oData.gear, oData.name, npcOpts)
	if not npc then
		arena:Destroy()
		return nil
	end
	npc.Parent = arena
	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	if npcRoot then
		npcRoot:SetNetworkOwner(nil)
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
		Builder.SetHeadgear(char, Color3.fromRGB(30, 60, 160), true)
		Builder.SetHeadgear(npc, Color3.fromRGB(170, 25, 30), true)
	end
	self.P = makeFighter(pData, char, player)
	self.O = makeFighter(oData, npc, nil)
	if pData.injuryCut then
		self.cutRisk[self.P] = 1.8
	end
	-- the residual damage is drawn from the first punch on (Cosmetics drew opts.damage, keep it in step)
	for _, F in ipairs({ self.P, self.O }) do
		if Config.FaceDamageScore(F.dmg) > 0 or F.dmg.ribsL > 0 or F.dmg.ribsR > 0 then
			self:RefreshDamage(F, true)
		end
	end
	self.O.ai = FightAI.new(self.O, self.P, self)
	FightEngine.Active[player] = self

	local ok, res = pcall(function()
		return self:Run()
	end)
	if not ok then
		warn("[Boxer] Fight error:", res)
		res = nil
	end
	if res then
		self:Send({ t = "final", result = res, oppName = oData.name, spar = self.spar })
		task.wait(3)
	end
	self:Cleanup()
	FightEngine.Active[player] = nil
	return res
end

-- player input from the client
function FightEngine.Input(player, msg)
	local fight = FightEngine.Active[player]
	if not fight or type(msg) ~= "table" then
		return
	end
	local F = fight.P
	local t = msg.t
	if t == "punch" and Config.Punches[msg.p] then
		fight:Punch(F, msg.p, msg.body == true)
	elseif t == "block" then
		fight:SetBlock(F, msg.on == true)
	elseif t == "slip" then
		fight:Slip(F, msg.dir == -1 and -1 or 1)
	elseif t == "roll" then
		fight:Roll(F)
	elseif t == "parry" then
		fight:Parry(F)
	elseif t == "pivot" then
		fight:Pivot(F, msg.dir == -1 and -1 or 1)
	elseif t == "clinch" then
		fight:Clinch(F)
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
				if msg.good == true and now - (F.goodAt or 0) >= 0.3 then
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

return FightEngine
