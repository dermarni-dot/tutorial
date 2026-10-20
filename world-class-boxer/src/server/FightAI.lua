-- FightAI: the opponent's brain. One per AI fighter (FightEngine.Run makes the blue corner's; the balance sims in
-- tools/sim give the red corner one too). It only ever acts through the engine's own moves (Punch, Feint, Slip,
-- Dodge, SetBlock, Clinch, MoveAI...), so it plays by the same rules as the player.
--
-- * FAIR PLAY. It never reacts to a punch it could not have seen: a punch starts, the AI notices it after its
--   perception delay (Config.FightAI.perceive, by skill; slower when concussed or dazed) and its move takes a
--   motor delay (by Reflexes) - if that is longer than the punch's wind-up it is simply too late. What lets a good
--   AI defend fast punches is PREDICTION: its read of the player (Shared.FightRead) says what usually comes next,
--   and a confident read lets it start early - but then it defends against the punch it EXPECTED, so a player who
--   changes his patterns makes it guess wrong. A feint looks exactly like a jab to it; only its read of how often
--   the player feints teaches it to stop biting.
-- * READING THE OPPONENT. The rolling read (FightRead: decays over ~30 s) of his favourite punches and follow-ups,
--   his head / body mix, which way he slips, when he blocks, how he manages his gas, the distance he likes, his
--   feints and what he does after his combinations. It slips the punch he throws most, expects his usual
--   follow-up, throws its hooks to the side he slips to, attacks when he is tired, punishes the end of his
--   combinations (unless he usually fires again), goes to the body when he shells up.
-- * RING GENERALSHIP. Distance by style (out-boxers keep range and back off, swarmers close in, sluggers stalk
--   and cut off the ring: FightEngine:MoveAI's cut), using the ropes (a man with his back to them is cut off; its
--   own back near them makes it circle out or pivot off), angles after its combinations.
-- * GAME PLANS by style and IQ: a base plan (outbox / swarm / stalk / bait / plan), feints and draws, pacing over
--   the rounds (a pace line for its stamina), a change of plan when the round or the cards go against it, a
--   gamble when it is losing late, the finish when he is hurt, survival (clinch, hold, cover, move) when it is.
-- * DEFENCE in layers: the guard, head movement, footwork off the line, the clinch; and REALISTIC MISTAKES scaled
--   by skill (Config.FightAI): a raw boxer picks the wrong defence now and then, drops its hands after its own
--   combinations, repeats its favourite combination and paces itself badly - an elite one rarely does.
-- * RING TRAITS (Shared.Traits): a Counter Specialist reads flurries, a Ring General slides off the ropes, a Slick
--   man slips more, a Weaver weaves more, a Pressure-proof man doesn't back off under pressure.
-- * reads the head-HP tiers and concussion (F.tier / F.conc): goes for the finish when the other man is dazed,
--   holds / covers / freezes when it is dazed itself, and reacts slower when concussed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
-- fight spacing (FightMotion.Spacing, R-anim; the round-1 numbers if that module is missing)
local SPACING = { pivot = 3.2, clinch = 4.2, cover = 5 }
do
	local fm = ReplicatedStorage.Shared:FindFirstChild("FightMotion")
	local ok, mod = false, nil
	if fm then
		ok, mod = pcall(require, fm)
	end
	if ok and type(mod) == "table" and mod.Spacing then
		SPACING = { pivot = mod.Spacing.pivot, clinch = mod.Spacing.clinch - 0.2, cover = mod.Spacing.cover }
	end
end

-- special moves (Moves.lua), nil-safe if the module is missing
local Moves
do
	local mm = ReplicatedStorage.Shared:FindFirstChild("Moves")
	local ok, mod = false, nil
	if mm then
		ok, mod = pcall(require, mm)
	end
	Moves = (ok and type(mod) == "table") and mod or nil
end

-- combinations (the AI's plans by style and skill, the chain it reads), the dodges (by style), the read of the
-- player, the ring traits
local Combos = require(ReplicatedStorage.Shared:WaitForChild("Combos"))
local Evasion = require(ReplicatedStorage.Shared:WaitForChild("Evasion"))
local FightRead = require(ReplicatedStorage.Shared:WaitForChild("FightRead"))
local Traits = require(ReplicatedStorage.Shared:WaitForChild("Traits"))

local AIC = Config.FightAI

local FightAI = {}
FightAI.__index = FightAI

local DEFAULT_ARCH = { aggr = 0, block = 0.3, slip = 0.25, roll = 0.2, parry = 0.1, pivot = 0.1, body = 0.1, overhand = 0.05, adapt = 1 }
-- the base game plan by style (UpdateMode): out-boxers box from range, swarmers swarm, sluggers stalk and cut
-- off the ring, counter-punchers bait a lead and counter it, boxer-punchers mix it
local BASE_PLAN = { OutBoxer = "outbox", Swarmer = "swarm", Slugger = "stalk", CounterPuncher = "bait", BoxerPuncher = "plan" }
-- the alternative plan a thinking boxer switches to when its base plan is losing
local ALT_PLAN = { outbox = "swarm", swarm = "outbox", stalk = "plan", bait = "swarm", plan = "outbox" }
-- mode -> aggression shift, range (a share of the jab range; nil = the style's), how hard it cuts off the ring
local MODES = {
	plan = { aggr = 0 },
	outbox = { aggr = -0.08, range = 1.0, cut = 0 },
	swarm = { aggr = 0.12, range = 0.7, cut = 0.5 },
	stalk = { aggr = 0.02, range = 0.8, cut = 0.8 },
	bait = { aggr = -0.15, range = 0.97, cut = 0 },
	pressure = { aggr = 0.3, range = 0.74, cut = 0.6 },
	finish = { aggr = 0.45, range = 0.7, cut = 0.7 },
	gamble = { aggr = 0.35, range = 0.75, cut = 0.6 },
	cruise = { aggr = -0.2, range = 0.98, cut = 0 },
	reset = { aggr = -0.3, range = 1.15, cut = 0 },
	survive = { aggr = -0.45, range = 1.9, cut = 0 },
}
FightAI.MODES = MODES

-- a wrong defence a raw boxer picks (by the kind of punch coming; a list entry twice is twice as likely): ducking
-- a straight, weaving into an uppercut, reaching to parry a hook or slipping into it ("slipinto" = a slip toward
-- the hand it comes from)
local MISTAKES = { straight = { "duck", "weave" }, hook = { "parry", "parry", "slipinto" }, overhand = { "parry", "slipinto" }, uppercut = { "duck", "weave" } }

local function lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

function FightAI.new(F, O, engine)
	local style = Config.FindById(Config.Styles, F.data.style) or Config.Styles[4]
	local arch = Config.FindById(Config.Archetypes, F.data.archetype)
	local self = setmetatable({}, FightAI)
	self.F, self.O, self.engine = F, O, engine
	self.rng = Random.new()
	self.style = style
	self.arch = arch and arch.ai or DEFAULT_ARCH
	self.baseRange = style.ai.range
	self.baseAggr = style.ai.aggression + ((F.data.mental.Aggression or 50) - 50) / 200 + self.arch.aggr
	self.jabRate = style.ai.jabRate
	self.comboMax = style.fight.combo >= 1.2 and 4 or 3
	self.queue = {}
	self.nextThink = 0
	self.nextMove = 0
	self.circleDir = self.rng:NextNumber() < 0.5 and -1 or 1
	self.mode = "plan"
	self.basePlan = BASE_PLAN[style.id] or "plan"
	self.plan = self.basePlan
	self.nextMode = 0
	self.freezeUntil = 0
	self.bodyBias = 0.2
	self.blockUntil = 0
	local learned = F.data.learned or {}
	local total = 0
	for _, v in pairs(learned) do
		total += v
	end
	self.anticipate = {}
	for k, v in pairs(learned) do
		self.anticipate[k] = total > 0 and v / total or 0
	end
	self.obs = { blockTime = 0, time = 0, punches = {}, body = 0, slips = 0 }
	-- the player's sequences it has seen ("1 2>3": a lead hook after a 1-2), for the defence that adapts
	self.seq = {}
	-- the rolling read of the man in front of it (Shared.FightRead) and what it expects him to throw next
	self.read = FightRead.new()
	self.expect = nil
	-- how good a boxer it is: its ring IQ and focus (0..1); its hands (Reflexes, 0..1) for the motor delay
	self.skill = math.clamp(((F.data.stats.RingIQ or 50) + (F.data.mental.Focus or 50)) / 200, 0, 1)
	self.hands = math.clamp((F.data.stats.Reflexes or 50) / 100, 0, 1)
	self.dodgeMul = Evasion.StyleDodge[style.id] or 1
	self.favourite = Evasion.StyleFavourite[style.id]
	self.planSwitches = 0
	self.punishAt = nil
	self.afterAt = nil
	self.drawUntil = 0
	self.nextFeint = 0
	self.lastCombo = 0
	return self
end

------------------------------------------------------------------------
-- What it sees
------------------------------------------------------------------------
function FightAI:Observe(dt)
	self.obs.time += dt
	local O = self.O
	if O.blocking then
		self.obs.blockTime += dt
	end
	self.read:Tick(dt, O.blocking == true, O.stamina < O.maxStam * 0.3)
	-- what he did after his last combination (FightRead.After), a beat after it ended
	local now = self.engine:Now()
	if self.afterAt and now >= self.afterAt then
		local A = self.afterAt
		self.afterAt = nil
		if O.lastPunch > A - 0.45 then
			self.read:After("punch")
		elseif O.blocking then
			self.read:After("block")
		elseif self.engine:Distance(self.F, O) > (self.afterDist or 0) + 0.6 then
			self.read:After("move")
		else
			self.read:After("idle")
		end
	end
end

function FightAI:Intel()
	local o = self.obs
	local fav = self.read:Favourite()
	return { blockRatio = math.max(o.time > 0 and o.blockTime / o.time or 0, self.read:BlockShare()), favorite = fav, slips = o.slips }
end

-- the engine: his combination of n punches just ended. A long one leaves him in his recovery: punish it (unless
-- the read says he usually fires again right after - then it is ready to defend instead)
function FightAI:OnOppComboEnd(n)
	self.read:ComboEnd(n)
	local engine, O = self.engine, self.O
	local now = engine:Now()
	self.afterAt = now + 0.45
	self.afterDist = engine:Distance(self.F, O)
	if n >= 3 and self.skill >= 0.3 then
		local again, share = self.read:AfterCombo()
		if again == "punch" and share > 0.5 then
			self.punishAt = nil
			self.blockUntil = math.max(self.blockUntil, now + 0.6)
		else
			-- it sees the combination end a perception delay later
			self.punishAt = math.max(O.busyUntil, now) + self:Perception() * 0.6
		end
	end
end

-- seconds from a punch starting to the AI noticing it
function FightAI:Perception()
	local F = self.F
	local C = Config.Concussion
	return lerp(AIC.perceive[1], AIC.perceive[2], self.skill) + C.aiReact * (F.conc or 0) + 0.04 * (F.tier or 0)
end
function FightAI:Motor()
	return lerp(AIC.motor[1], AIC.motor[2], self.hands)
end

-- called by the engine when the opponent starts a punch at us (info = { hand, chainPos, feint }: what the eye can
-- see - which hand moves; whether it is a feint it cannot know)
function FightAI:OnOppPunch(ptype, body, windup, info)
	info = type(info) == "table" and info or {}
	local F, O, engine = self.F, self.O, self.engine
	local now = engine:Now()
	self.obs.punches[ptype] = (self.obs.punches[ptype] or 0) + 1
	if body then
		self.obs.body += 1
	end
	-- what it expected (the read made at his last punch) and what it expects next
	local expect = self.expect
	if expect and now - expect.at > 1.2 then
		expect = nil
	end
	local np, nconf = self.read:Predict(ptype)
	self.expect = np and { p = np, conf = nconf, at = now } or nil
	-- (read and learn the player's combination even while busy: the sequence counts either way)
	local readBonus = self:ReadChain()
	if F.state == "down" or F.state == "clinch" or now < F.busyUntil then
		return
	end
	if now < (F.guardDropUntil or 0) then
		return -- (a raw boxer's hands are down after its own combination)
	end
	local s = F.data.stats
	local chance = (s.Reflexes * 0.5 + s.RingIQ * 0.3 + s.HeadMovement * 0.2) / 100 * 0.62
	chance += (self.anticipate[ptype] or 0) * 0.3
	-- slip the punch he throws most (the read of tonight)
	chance += self.read:Share(ptype) * 0.25 * self.arch.adapt
	chance += readBonus
	-- a Counter Specialist reads a flurry
	local cs = engine.Trait and engine:Trait(F, "CounterSpecialist") or 0
	if cs > 0 and ((O.chain and not O.chain.closed and O.chain.punches >= 3) or (engine.RecentThrows and engine:RecentThrows(O, 4) >= 7)) then
		chance += Traits.Effect("CounterSpecialist", "read", cs)
	end
	-- a feint: it bites as on any jab, less once it has seen him feint a lot (and the smarter it is)
	if info.feint then
		chance *= 1 - 0.85 * self.read:FeintShare() * self.skill
	end
	if F.stamina < F.maxStam * 0.25 then
		chance *= 0.6
	end
	if engine:IsHurt(F) then
		chance += 0.12
	end
	-- dazed / concussed: sees it late and cannot always do anything about it
	local tier, conc = F.tier or 0, F.conc or 0
	local C = Config.Concussion
	chance *= (1 - C.aiDefense * conc) * (1 - C.tierDefense * tier)
	if engine:IsStumbling(F) or now < self.freezeUntil then
		return
	end
	-- (engine.aiDefense: the tutorial's opponent reacts far less, so the lesson's punches land)
	chance = math.clamp(chance, 0.05, 0.85) * (engine.aiDefense or 1)
	if self.rng:NextNumber() > chance then
		return
	end
	-- the timing: perception + the move. A confident read (or a draw it set up) lets it start early, but it
	-- then defends against what it EXPECTED
	local perceive, motor = self:Perception(), self:Motor()
	local kind = Config.Punches[ptype].kind
	local hand = info.hand or Config.Punches[ptype].hand
	local guessBody = body
	local early = 0
	if now < self.drawUntil then
		early = 0.5 -- (it drew the lead: it was waiting for exactly this)
	elseif expect and expect.conf >= AIC.predictFrom and engine.tutorial == nil then
		early = AIC.predictCut * expect.conf * (0.4 + 0.6 * self.skill)
		local P = Config.Punches[expect.p]
		if P and self.rng:NextNumber() < expect.conf then
			-- it commits to the punch it expected (right or wrong)
			kind, hand = P.kind, P.hand
		end
	end
	local react = perceive * (1 - early) + motor
	if react >= windup then
		return -- too late
	end
	local move = self:PickDefence(kind, guessBody, hand)
	local dir = self.rng:NextNumber() < 0.5 and -1 or 1
	-- slips go away from the hand a hook comes from (a left hook lands on its right: slip left); a slip INTO it
	-- is the raw boxer's mistake
	local landSide = hand == "L" and 1 or -1
	if move == "slipinto" then
		move, dir = "slip", landSide
	elseif move == "slip" and (kind == "hook" or kind == "overhand") then
		dir = -landSide
	end
	task.delay(react, function()
		if F.state == "down" or engine.finished then
			return
		end
		if move == "slip" then
			engine:Slip(F, dir)
		elseif move == "roll" then
			engine:Roll(F)
		elseif move == "parry" then
			engine:Parry(F)
		elseif move == "pivot" then
			engine:Pivot(F, dir)
		elseif move == "clinch" and engine.CanClinch and engine:CanClinch(F) then
			engine:Clinch(F)
		elseif Evasion.Moves[move] and engine.Dodge then
			engine:Dodge(F, move, dir)
		else
			engine:SetBlock(F, true)
			self.blockUntil = engine:Now() + 0.55
		end
	end)
end

-- the layered defence for a punch of this kind: the guard, the head movement that beats it, the footwork off the
-- line when it is under fire or on the ropes, the clinch when it is hurt up close; a raw boxer's wrong pick now
-- and then (MISTAKES)
function FightAI:PickDefence(kind, body, hand)
	local F, O, engine = self.F, self.O, self.engine
	if self.rng:NextNumber() < AIC.mistake * (1 - self.skill) ^ 1.5 and MISTAKES[kind] and not body then
		local list = MISTAKES[kind]
		return list[self.rng:NextInteger(1, #list)]
	end
	local a = self.arch
	local options = {}
	local function add(move, w)
		if w > 0 then
			table.insert(options, { move, w })
		end
	end
	-- layer 1: the guard (elbows in for the body)
	add("block", a.block + (body and 0.3 or 0))
	-- layer 2: the head movement that beats this punch
	local slick = engine.Trait and engine:Trait(F, "Slick") or 0
	local weaver = engine.Trait and engine:Trait(F, "Weaver") or 0
	if not body then
		if kind == "straight" then
			add("slip", a.slip * (1 + slick))
			add("parry", a.parry)
			add("pivot", a.pivot * 0.6)
		elseif kind == "hook" or kind == "overhand" then
			add("roll", a.roll * (1 + weaver))
			add("slip", a.slip * 0.3)
		end
	end
	-- the dodges (Evasion): the ones that beat this punch, by style (counter-punchers and out-boxers move their
	-- heads most) and its habits; a side-step is dear on the gas, so a tired man keeps it for later
	local head = (a.slip + a.roll) * 0.5
	for d, w in pairs(Evasion.AIWeights[kind] or {}) do
		if not body or (Evasion.Moves[d] and Evasion.Moves[d].body) then
			local fav = d == self.favourite and 1.5 or 1
			local cost = Evasion.Moves[d] and Evasion.Moves[d].stam or 5
			local trait = (d == "weave" and (1 + weaver)) or ((d == "slip" or d == "pull") and (1 + slick * 0.5)) or 1
			if F.stamina >= cost * 2.5 then
				-- layer 3: footwork off the line when he is in a flurry or it is on the ropes
				local under = (O.chain and not O.chain.closed and O.chain.punches >= 3) or F.onRopes
				local foot = (d == "sidestep" and under) and 2.2 or 1
				add(d, w * head * self.dodgeMul * fav * trait * foot * 0.55)
			end
		end
	end
	-- layer 4: hurt and up close in his flurry - hold on
	if (F.tier or 0) >= 1 and O.chain and not O.chain.closed and O.chain.punches >= 2 and engine.CanClinch and engine:CanClinch(F) then
		add("clinch", 0.5)
	end
	local totalW = 0
	for _, o in ipairs(options) do
		totalW += o[2]
	end
	local pick = self.rng:NextNumber() * totalW
	for _, o in ipairs(options) do
		pick -= o[2]
		if pick <= 0 then
			return o[1]
		end
	end
	return "block"
end

------------------------------------------------------------------------
-- The game plan
------------------------------------------------------------------------
-- the engine also calls this whenever either fighter's head tier changes
function FightAI:UpdateMode()
	local engine, F, O = self.engine, self.F, self.O
	local lead = engine:EstimateLead(F)
	local r, total = engine.round or 1, engine.rounds or 3
	local myTier, oTier = F.tier or 0, O.tier or 0
	local now = engine:Now()
	self.nextMode = now + 1.5
	local mom = engine.Mom and engine:Mom(F) or 0
	-- a thinking boxer changes its plan when it is losing the round it is in (or the cards) with it
	if self.skill >= 0.45 and engine.RoundPoints and (engine.round or 0) > 0 and now >= (self.planCheck or 0) then
		self.planCheck = now + 12
		local d = engine:RoundPoints(F, O) - engine:RoundPoints(O, F)
		if (d < -4 or (lead < 0 and r > total / 2)) and self.planSwitches < 3 then
			self.plan = ALT_PLAN[self.plan] or "plan"
			self.planSwitches += 1
		end
	end
	if engine:IsHurt(F) or F.health < 30 or myTier >= 1 then
		self.mode = "survive"
	elseif oTier >= 1 or (O.conc or 0) > 0.4 then
		-- killer instinct: the other man is dazed, go and end it
		self.mode = "finish"
	elseif r >= total * 0.66 and lead <= -2 and r > 1 then
		-- losing late on the cards: go for broke
		self.mode = "gamble"
	elseif (r > total / 2 and lead < 0) or engine:IsHurt(O) or O.health < 35 then
		self.mode = "pressure"
	elseif r >= total - 1 and lead >= 2 then
		self.mode = "cruise"
	elseif mom < -0.45 and self.skill >= 0.4 and now >= (self.resetUntil or 0) - 4 then
		-- the momentum is all his: reset (move, jab, hold) for a few seconds
		self.mode = "reset"
		self.resetUntil = now + 4
	else
		self.mode = self.plan
	end
	local intel = self:Intel()
	self.bodyBias = 0.12 + self.arch.body + intel.blockRatio * 0.55 * self.arch.adapt
	-- he blocks the moment it throws: go round it (the body) - and his Iron Chin wants the body too
	if self.read:ReactBlock() > 0.6 then
		self.bodyBias += 0.1 * self.arch.adapt
	end
	if self.mode == "finish" then
		self.bodyBias *= 0.3 -- head hunting
	end
	self.bodyBias = math.clamp(self.bodyBias, 0, 0.7)
	self.exploitGassed = O.stamina < O.maxStam * 0.3
end

-- the stamina it wants to have left at this point of the fight (the pace line; 0 = spend it all)
function FightAI:PaceLine()
	local engine = self.engine
	local rounds = engine.rounds or 3
	local r = engine.round or 1
	if r >= rounds then
		return 0
	end
	local len = engine.roundSeconds or 60
	local left = math.clamp((engine.roundEnd or 0) - engine:Now(), 0, len)
	local progress = math.clamp(((r - 1) + (len - left) / len) / rounds, 0, 1)
	return 0.25 + 0.35 * (1 - progress)
end

function FightAI:Aggression()
	local a = self.baseAggr
	local M = MODES[self.mode] or MODES.plan
	a += M.aggr
	if self.exploitGassed then
		a += 0.2
	end
	local F, engine = self.F, self.engine
	local stam = F.stamina / F.maxStam
	if stam < 0.3 then
		a -= 0.25
	end
	-- the pace line: a thinking boxer slows down before it runs dry (a raw one pays less heed)
	local pace = self:PaceLine()
	if stam < pace - AIC.paceSlack then
		a -= 0.25 * (0.3 + 0.7 * self.skill)
	end
	-- walked down: it wilts and backs off a little (unless it is Pressure-proof)
	if F.pressured and not (engine.Trait and engine:Trait(F, "PressureProof") > 0) then
		a -= 0.1
	end
	a += (self.F.data.mental.Confidence - 50) / 250
	return math.clamp(a, 0.05, 0.95)
end

-- preferred distance, as a share of this fighter's jab range
function FightAI:Range()
	local jab = self.engine:PunchRange(self.F, "jab")
	local M = MODES[self.mode]
	local share = (M and M.range) or self.baseRange
	if self.mode == "pressure" then
		share = math.min(self.baseRange, 0.74)
	elseif self.mode == "cruise" then
		share = math.max(self.baseRange, 0.94)
	elseif self.mode == "plan" then
		share = self.baseRange
	end
	-- an out-boxer facing a man who wants it close keeps a little further off
	if self.mode == "outbox" and self.read:Distance() and self.read:Distance() < jab * 0.85 then
		share += 0.06
	end
	return jab * share * (self.engine.aiRange or 1)
end

function FightAI:Fits(ptype, dist)
	return dist <= self.engine:PunchRange(self.F, ptype) + 0.25
end

------------------------------------------------------------------------
-- Offence
------------------------------------------------------------------------
-- the hand that lands on his blind side (a closing eye) and the hook that finds the side he slips to: weights for
-- the punch pool (1 = no preference)
function FightAI:PunchPrefs()
	local engine, O = self.engine, self.O
	local pref = { jab = 1, cross = 1, leadhook = 1, rearhook = 1, uppercut = 1, overhand = 1 }
	if engine.Blind and engine.tutorial == nil then
		-- its left hand lands on his right side (side 1)
		local bR, bL = engine:Blind(O, 1), engine:Blind(O, -1)
		pref.jab *= 1 + bR
		pref.leadhook *= 1 + bR * 1.5
		pref.cross *= 1 + bL
		pref.rearhook *= 1 + bL * 1.5
		pref.overhand *= 1 + bL
	end
	local side, strength = self.read:SlipSide()
	if strength > 0.3 then
		-- his head goes to side `side`: the hook that lands there (lead hook -> his right, side 1)
		local k = 1 + strength * self.arch.adapt
		if side == 1 then
			pref.leadhook *= k
		else
			pref.rearhook *= k
		end
	end
	-- a Weaver's dip meets the uppercut; a Slick man's head is off the line of straights (an AI knows its own
	-- kind: the other side's traits only matter in the AI-vs-AI sims)
	local weaver = engine.Trait and engine:Trait(O, "Weaver") or 0
	local slick = engine.Trait and engine:Trait(O, "Slick") or 0
	pref.uppercut *= 1 + weaver * self.skill
	pref.cross *= 1 - slick * 0.4 * self.skill
	pref.jab *= 1 - slick * 0.3 * self.skill
	return pref
end

-- the combination to throw. A plan (Combos.Plans: a named or a signature combo its style likes, every punch in
-- range) Combos.PlanShare(skill) of the time; otherwise the old few random punches (a raw boxer's wilder flurry,
-- which the combo rules punish)
function FightAI:BuildCombo()
	local n = 1
	local aggr = self:Aggression()
	local wantCombo = self.rng:NextNumber() < aggr
	local dist = self.engine:Distance(self.F, self.O)
	if wantCombo and self.rng:NextNumber() < Combos.PlanShare(self.skill) then
		local plan = self:PickPlan(dist)
		if plan then
			return plan
		end
	end
	if wantCombo then
		local extra = (self.engine:IsHurt(self.O) or self.mode == "finish") and 1 or 0
		n = self.rng:NextInteger(2, self.comboMax + extra)
	end
	local finish = (self.mode == "finish" or self.mode == "gamble") and 0.2 or 0
	n = math.max(1, math.min(n, math.floor(self.F.stamina / 6)))
	local pref = self:PunchPrefs()
	local list = {}
	for i = 1, n do
		local p = "jab"
		local roll = self.rng:NextNumber()
		if not (i == 1 and roll < self.jabRate + ((self.mode == "cruise" or self.mode == "outbox" or self.mode == "reset") and 0.25 or 0)) then
			local pool, total = {}, 0
			for _, opt in ipairs({
				{ "cross", 0.4 }, { "leadhook", 0.25 + finish }, { "rearhook", 0.18 + finish }, { "uppercut", 0.15 + finish },
				{ "overhand", 0.03 + self.arch.overhand + finish }, { "jab", 0.12 },
			}) do
				if self:Fits(opt[1], dist) then
					local w = opt[2] * (pref[opt[1]] or 1)
					table.insert(pool, { opt[1], w })
					total += w
				end
			end
			local pick = self.rng:NextNumber() * total
			for _, opt in ipairs(pool) do
				pick -= opt[2]
				if pick <= 0 then
					p = opt[1]
					break
				end
			end
		end
		local body = p ~= "overhand" and self.rng:NextNumber() < self.bodyBias
		table.insert(list, { p = p, body = body })
	end
	return list
end

-- a plan its style likes (and its signature combos), every punch in reach from here, no longer than its skill
-- allows and affordable on its gas; nil when none fits. A raw boxer repeats its last plan more often than it
-- should (a pattern the player can learn)
function FightAI:PickPlan(dist)
	local F = self.F
	local likes = Combos.StylePlans[self.style.id] or Combos.StylePlans.BoxerPuncher
	local maxLen = Combos.PlanMax(self.skill)
	local pool, total = {}, 0
	local function fits(id)
		local plan = Combos.Plans[id]
		if not plan or #plan > maxLen + (Combos.ById[id] and Combos.ById[id].signature and 1 or 0) or F.stamina < #plan * 6 then
			return false
		end
		for i, step in ipairs(plan) do
			-- (the later punches are thrown a step closer: only the first must reach from here, the rest nearly)
			if dist > self.engine:PunchRange(F, step[1]) + (i == 1 and 0.25 or 0.6) then
				return false
			end
		end
		return true
	end
	local function consider(id, w)
		if w <= 0 or not fits(id) then
			return
		end
		table.insert(pool, { id, w })
		total += w
	end
	local chosen = nil
	if self.lastPlan and self.rng:NextNumber() < (1 - self.skill) * 0.5 and fits(self.lastPlan) then
		chosen = self.lastPlan
	else
		for id, w in pairs(likes) do
			local bodyHeavy = id == "jabbodyhook" or id == "bodyhead"
			consider(id, w * (bodyHeavy and (0.6 + self.bodyBias * 2) or 1) * ((self.mode == "finish" or self.mode == "gamble") and #Combos.Plans[id] >= 3 and 1.4 or 1))
		end
		for id in pairs(F.sigs or {}) do
			if Combos.Plans[id] then
				consider(id, Combos.SIG_PLAN_WEIGHT)
			end
		end
		if total <= 0 then
			return nil
		end
		table.sort(pool, function(x, y)
			return x[1] < y[1]
		end)
		local pick = self.rng:NextNumber() * total
		for _, o in ipairs(pool) do
			pick -= o[2]
			if pick <= 0 then
				chosen = o[1]
				break
			end
		end
	end
	if not chosen then
		return nil
	end
	local out = {}
	for _, step in ipairs(Combos.Plans[chosen]) do
		table.insert(out, { p = step[1], body = step[2] == true })
	end
	self.lastPlan = chosen
	return out
end

-- the defence that adapts to the player's combinations: a long flurry is read from its READ_FROM-th punch, and
-- a follow-up it has seen him throw after the same punches LEARN_SEEN times is expected. Returns the extra
-- defend chance (and learns the sequence)
function FightAI:ReadChain()
	local chain = self.O.chain
	if not chain or chain.closed or #chain.items == 0 then
		return 0
	end
	local bonus = 0
	local n = chain.punches
	if n >= Combos.READ_FROM then
		bonus += math.min(Combos.READ_MAX, (n - Combos.READ_FROM + 1) * Combos.READ_STEP)
	end
	local items = chain.items
	local cur = items[#items]
	if #items >= 2 and not cur.dodge then
		local prev = {}
		for i = math.max(1, #items - 2), #items - 1 do
			table.insert(prev, items[i].tok)
		end
		local key = table.concat(prev, " ") .. ">" .. tostring(cur.tok)
		local seen = self.seq[key] or 0
		if seen >= Combos.LEARN_SEEN then
			bonus += Combos.LEARN_BONUS * math.min(1.5, self.arch.adapt or 1)
		end
		self.seq[key] = seen + 1
	end
	return bonus
end

-- a punch it throws (the queue's or a counter): the engine's Punch, its read of whether he blocks on the spot
function FightAI:Throw(p, body)
	local engine, O = self.engine, self.O
	engine:Punch(self.F, p, body)
	if self.F.state == "punching" then
		self.read:Reacted(O.blocking == true)
	end
end

-- a counter: the hand that lands on his blind side or the hook to the side he slips to, else the style's
function FightAI:CounterPunch(dist)
	local p = "jab"
	local pref = self:PunchPrefs()
	if self:Fits("leadhook", dist) and self.rng:NextNumber() < 0.5 then
		p = (self.rng:NextNumber() * (pref.leadhook + pref.rearhook) < pref.leadhook) and "leadhook" or "rearhook"
	elseif self:Fits("cross", dist) then
		p = (self.arch.overhand > 0.2 and self.rng:NextNumber() < 0.3) and "overhand" or "cross"
	end
	return p
end

function FightAI:Think(now)
	local F, O, engine = self.F, self.O, self.engine
	if now < self.nextThink then
		return
	end
	self.nextThink = now + 0.32 - F.data.stats.RingIQ * 0.0018
	if F.state == "down" or O.state == "down" then
		self.queue = {}
		return
	end
	if F.state == "clinch" then
		self.queue = {}
		self:ClinchThink(now)
		return
	end
	if now >= self.nextMode then
		self:UpdateMode()
	end
	local tier = F.tier or 0
	-- a dazed fighter sometimes just freezes for a moment (and gets hit): ~15% per second per tier
	if now < self.freezeUntil or engine:IsStumbling(F) then
		return
	end
	if tier >= 1 and self.rng:NextNumber() < 0.15 * tier * 0.32 then
		self.freezeUntil = now + 0.4
		self.queue = {}
		return
	end
	local dist = engine:Distance(F, O)
	if now >= self.nextMove then
		self.nextMove = now + 0.35
		self:Move(now, dist)
	end
	if F.blocking and now >= self.blockUntil then
		engine:SetBlock(F, false)
	end
	if now < F.busyUntil then
		return
	end
	-- (the engine's spacing is scaled to the pair's rigs: engine.rigK)
	local rk = engine.rigK or 1
	-- off the ropes / out of the corner: a pivot (more for a pivoting archetype, a skilled boxer and a Ring General)
	local rg = engine.Trait and engine:Trait(F, "RingGeneral") or 0
	local escape = self.arch.pivot * 0.08 + (F.onRopes and (0.05 + 0.1 * self.skill + Traits.Effect("RingGeneral", "escape", rg) * 0.4) or 0)
	if (self.arch.pivot > 0.15 or F.onRopes) and dist < SPACING.pivot * rk * 1.15 and self.rng:NextNumber() < escape then
		if F.onRopes and rg > 0 then
			engine:TraitFired(F, "RingGeneral")
		end
		engine:Pivot(F, self.circleDir)
		return
	end
	if self.mode == "survive" or self.mode == "reset" then
		local hold = self.mode == "survive" and (tier >= 1 and 0.45 or 0.25) or 0.12
		if dist < SPACING.clinch * rk and self.rng:NextNumber() < hold and engine:CanClinch(F) then
			engine:Clinch(F)
			return
		end
		if dist < SPACING.cover * rk and self.rng:NextNumber() < (self.mode == "survive" and 0.6 or 0.3) then
			engine:SetBlock(F, true)
			self.blockUntil = now + 0.7
			return
		end
	end
	-- he bit on its feint: fire now (it saw him react)
	if now < (F.feintOpenUntil or 0) and self:Fits("cross", dist) then
		self:Throw(self:CounterPunch(dist), self.rng:NextNumber() < self.bodyBias)
		return
	end
	if self:TrySpecial(now, dist) then
		return
	end
	if now < F.counterUntil and self:Fits("jab", dist) then
		self:Throw(self:CounterPunch(dist), false)
		return
	end
	-- the end of his combination: he is in his recovery (it saw it end)
	if self.punishAt and now >= self.punishAt then
		local at = self.punishAt
		self.punishAt = nil
		if now - at < 0.4 and self:Fits("jab", dist) and self.mode ~= "survive" then
			self:Throw(self:CounterPunch(dist), self.rng:NextNumber() < self.bodyBias * 0.6)
			return
		end
	end
	if #self.queue > 0 then
		local nxt = table.remove(self.queue, 1)
		if dist <= engine:PunchRange(F, nxt.p) + 0.4 then
			self:Throw(nxt.p, nxt.body)
			self:ChainNext()
			if #self.queue == 0 then
				self:ComboDone(now)
			end
		else
			self.queue = {}
		end
		return
	end
	local aggr = self:Aggression()
	if self:Fits("jab", dist) or (self:Fits("jab", dist - 0.6) and (self.mode == "bait" or self.mode == "outbox")) then
		-- a feint / a draw: show him a jab and see what he does (counter-punchers and out-boxers, the smart ones)
		if self:TryFeint(now, dist) then
			return
		end
	end
	if self:Fits("jab", dist) then
		-- (engine.aiWork: a gym sparring partner works harder than the fight-night pace)
		if self.rng:NextNumber() < (aggr * 0.13 + self.jabRate * 0.07) * (engine.aiWork or 1) then
			self.queue = self:BuildCombo()
			local first = table.remove(self.queue, 1)
			self:Throw(first.p, first.body)
			self:ChainNext()
			if #self.queue == 0 then
				self:ComboDone(now)
			end
		elseif self.rng:NextNumber() < (1 - aggr) * 0.3 * (0.6 + self.arch.block) * (engine.aiDefense or 1) * (1 + 0.4 * self.skill) then
			engine:SetBlock(F, true)
			self.blockUntil = now + 0.5
		end
	end
end

-- its own combination is out: a skilled boxer turns off at an angle now and then, a raw one drops its hands
function FightAI:ComboDone(now)
	local F, engine = self.F, self.engine
	self.lastCombo = now
	local after = F.busyUntil
	if self.rng:NextNumber() < AIC.drop * (1 - self.skill) * 1.6 then
		F.guardDropUntil = after + AIC.drop * (1 - self.skill)
	elseif self.skill > 0.5 and self.rng:NextNumber() < (self.skill - 0.5) * 0.6 and engine.tutorial == nil then
		local fightId = engine.id
		task.delay(math.max(0, after - now) + 0.02, function()
			if engine.id == fightId and not engine.finished and engine:CanAct(F) and F.state ~= "punching" then
				if F.stamina > 25 and self.rng:NextNumber() < 0.4 then
					engine:Dodge(F, "sidestep", self.circleDir)
				else
					engine:Pivot(F, self.circleDir)
				end
			end
		end)
	end
end

-- a feint (and the draw that comes with it: for a moment after, it is ready for his lead)
function FightAI:TryFeint(now, dist)
	local F, engine = self.F, self.engine
	if engine.tutorial or engine.spar or not engine.Feint or now < self.nextFeint then
		return false
	end
	local styleK = (self.style.id == "CounterPuncher" and 1.6) or (self.style.id == "OutBoxer" and 1.3) or (self.style.id == "BoxerPuncher" and 1.1) or 0.7
	local rate = (0.02 + 0.1 * self.skill) * styleK * (self.mode == "bait" and 1.5 or 1)
	-- he blocks the moment it throws: feints work on him
	rate *= 0.7 + self.read:ReactBlock()
	if F.stamina < F.maxStam * 0.3 or self.rng:NextNumber() > rate then
		return false
	end
	self.nextFeint = now + 1.2 + self.rng:NextNumber() * 1.5
	if engine:Feint(F) then
		self.drawUntil = now + 0.6
		-- (look again the moment it is set: if he bit, the punch goes in)
		self.nextThink = math.min(self.nextThink, F.busyUntil + 0.02)
		return true
	end
	return false
end

-- footwork: the distance by the plan, the ring cut off when he is near the ropes, out of the corner itself
function FightAI:Move(now, dist)
	local F, O, engine = self.F, self.O, self.engine
	local tier = F.tier or 0
	if self.rng:NextNumber() < 0.08 then
		self.circleDir = -self.circleDir
	end
	local M = MODES[self.mode] or MODES.plan
	local circle = self.circleDir * (self.style.id == "OutBoxer" and 0.45 or 0.22)
	if self.mode == "outbox" or self.mode == "bait" then
		-- (a pressure fighter coming in: circle more, don't back straight up)
		circle = self.circleDir * ((self.mode == "outbox" and 0.5 or 0.35) + (F.pressured and 0.15 or 0))
	elseif self.mode == "stalk" then
		circle = self.circleDir * 0.1
	end
	local cut = M.cut or 0
	local oRope = engine.RopeDist and engine:RopeDist(O) or 99
	if cut > 0 then
		-- cut the ring off for real only when he is near the ropes; a skilled boxer does it better
		cut = cut * (oRope < 4 and (0.5 + 0.5 * self.skill) or (0.15 + 0.2 * self.skill))
		circle *= 0.5
	end
	local myRope = engine.RopeDist and engine:RopeDist(F) or 99
	local backOff = self.mode == "outbox" or self.mode == "bait" or self.mode == "survive" or self.mode == "reset" or self.mode == "cruise"
	if tier >= 1 or (backOff and myRope < 2.5) then
		-- hurt, or a mover near the ropes: circle away hard toward open space (the ring centre), never along them
		local c = engine.anchors and engine.anchors.RingCenter
		if c and F.root and O.root then
			local toC = c.Position - F.root.Position
			local fromO = F.root.Position - O.root.Position
			local cross = fromO.X * toC.Z - fromO.Z * toC.X
			self.circleDir = cross >= 0 and -1 or 1
		end
		circle = self.circleDir * 0.6
		cut = 0
	end
	engine:MoveAI(F, self:Range(), circle, cut)
end

-- in the clinch: the man who tied up holds (and recovers); the other works the body inside when it is fresh and
-- he is tiring, or shoves off the break to come out at an angle when it wants to press
function FightAI:ClinchThink(now)
	local F, O, engine = self.F, self.O, self.engine
	if now < (self.nextClinchThink or 0) then
		return
	end
	self.nextClinchThink = now + 0.4 + (1 - self.skill) * 0.2
	local holding = engine.clinchBy == F
	if holding and (self.mode == "survive" or (F.tier or 0) >= 1) then
		return -- hold on
	end
	local inside = self.style.fight.inside or 1
	if F.stamina > F.maxStam * 0.3 and (O.stamina < O.maxStam * 0.5 or inside > 1.05 or self.mode == "pressure") and self.rng:NextNumber() < 0.6 then
		local p = self.rng:NextNumber() < 0.5 and "leadhook" or "uppercut"
		engine:Punch(F, p, true)
		return
	end
	if (self.mode == "pressure" or self.mode == "finish" or self.mode == "swarm" or self.mode == "gamble") and engine.BreakClinch and self.rng:NextNumber() < 0.35 then
		engine:BreakClinch(F)
	end
end

-- with more of the combination queued, think again the moment the punch's recovery ends: the next one lands
-- inside the chain window (Combos) instead of whenever the next think comes round
function FightAI:ChainNext()
	if #self.queue > 0 then
		self.nextThink = math.min(self.nextThink, self.F.busyUntil + 0.02 + self.rng:NextNumber() * 0.08 * (1.2 - self.skill))
	end
end

-- Special moves (the engine's Fight:Special, the fighter's unlocked set F.moves): each has a situation it
-- is for. Counters (shell, pull, step back) answer a punch that is on its way or the counter window; the
-- check hook meets a man walking in; the liver shot goes under a high guard or at a worn body; the gazelle
-- closes from long range; the rush is pressure; the overhand goes over a shell; the lead uppercut opens a
-- tight guard. The fight moves: the double jab works the outside, the feint-cross beats a high guard, the
-- body-head hook brings it down and goes over it, the jab-cross-hook presses and finishes, the shovel hook
-- is for a hurt man up close. At most one every few seconds, more from an aggressive or finishing fighter.
-- the range the move needs (else its own first punch's): the 1-2-3 is started at cross range so its hook reaches
local SPECIAL_RANGE = { gazelle = "cross", stepback = "jab", peekaboo = "cross", onetwothree = "cross" }
-- a gym partner keeps his tricks for the harder sessions: none in a Light spar, fewer and further apart in
-- a Medium or Hard one (fight night = 1); the punch pacing of the spar (SPAR.work) never adds to these
local SPAR_SPECIALS = { Light = 0, Medium = 0.4, Hard = 0.7 }
function FightAI:TrySpecial(now, dist)
	local F, O, engine = self.F, self.O, self.engine
	local sparMul = engine.spar and (SPAR_SPECIALS[engine.spar] or 1) or 1
	if not Moves or sparMul <= 0 or now < (self.nextSpecial or 0) or F.stamina < F.maxStam * 0.3 then
		return false
	end
	local pool, total = {}, 0
	local function add(id, w)
		local M = F.moves and F.moves[id] and Moves.Data[id]
		if not M or w <= 0 or now < F.nextSpecial or F.stamina < M.stam * 1.3 then
			return
		end
		local range = engine:PunchRange(F, SPECIAL_RANGE[id] or M.punch[1], M.range)
		if dist > range + 0.3 then
			return
		end
		table.insert(pool, { id, w })
		total += w
	end
	local coming = O.state == "punching" and now < O.busyUntil
	local counterWin = now < F.counterUntil
	local blocking = O.blocking or self:Intel().blockRatio > 0.4
	local finishing = self.mode == "finish" or self.mode == "pressure" or self.mode == "gamble"
	add("phillyshell", (coming and 0.6 or 0) + (counterWin and 0.4 or 0))
	add("pullcounter", (coming and 0.6 or 0) + (counterWin and 0.4 or 0))
	add("stepback", (coming and 0.5 or 0) + (self.mode == "survive" and 0.4 or 0))
	add("checkhook", (coming and 0.5 or 0) + (engine:IsHurt(O) and 0.2 or 0))
	add("livershot", (blocking and 0.5 or 0.15) + (O.body < 60 and 0.4 or 0))
	add("gazelle", (dist > engine:PunchRange(F, "jab") and 0.5 or 0.05) + (finishing and 0.2 or 0))
	add("peekaboo", (finishing and 0.6 or 0.15))
	add("overhand", (blocking and 0.55 or 0.1) + (finishing and 0.25 or 0))
	add("leaduppercut", (blocking and 0.35 or 0.1) + (now < O.rollUntil and 0.6 or 0))
	local hurt = engine:IsHurt(O)
	add("doublejab", (dist > engine:PunchRange(F, "leadhook") and 0.45 or 0.1) + (self.mode == "survive" and 0.2 or 0))
	add("feintcross", (blocking and 0.55 or 0.15))
	add("bodyhead", (blocking and 0.4 or 0.15) + (O.body < 70 and 0.25 or 0))
	add("onetwothree", (finishing and 0.4 or 0.2) + (hurt and 0.2 or 0))
	add("shovelhook", (hurt and 0.6 or 0.1) + (finishing and 0.3 or 0))
	if total <= 0 then
		return false
	end
	-- a tentative fighter keeps its specials for the right moment; an aggressive one throws them freely
	local eager = (0.22 + self:Aggression() * 0.3 + (coming and 0.3 or 0)) * sparMul
	if self.rng:NextNumber() > eager then
		self.nextSpecial = now + 0.6
		return false
	end
	local pick = self.rng:NextNumber() * total
	for _, o in ipairs(pool) do
		pick -= o[2]
		if pick <= 0 then
			self.nextSpecial = now + (2.5 + self.rng:NextNumber() * 2.5) / sparMul
			self.queue = {}
			engine:Special(F, o[1])
			return true
		end
	end
	return false
end

-- corner advice for the PLAYER about this opponent (elite corner sees deeper)
function FightAI:Weakness()
	local s = self.F.data.stats
	local lowest, lowV = nil, 999
	for _, k in ipairs({ "Blocking", "HeadMovement", "Chin", "Stamina", "Footwork", "Reflexes" }) do
		if s[k] < lowV then
			lowest, lowV = k, s[k]
		end
	end
	local tips = {
		Blocking = "Their guard is leaky - straight punches are getting through. Double up the jab and cross!",
		HeadMovement = "Their head stays on the centre line. Throw power shots up top!",
		Chin = "That chin is suspect. Land one clean hook and they're going down!",
		Stamina = "Their gas tank is weak. Go to the body and make them carry it late!",
		Footwork = "They're flat-footed. Pivot off the ropes and make them reset!",
		Reflexes = "They're slow to react. Feint, then fire the overhand!",
	}
	-- a hidden trait the elite corner has spotted on the tapes
	local seen = self.F.traitSeen or {}
	for _, t in ipairs(self.F.traits or {}) do
		if not seen[t.id] then
			return "Watch it - he's " .. Traits.Data[t.id].name:lower() .. ". " .. Traits.Data[t.id].counter
		end
	end
	return tips[lowest]
end

return FightAI
