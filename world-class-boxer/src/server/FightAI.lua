-- FightAI: adaptive opponent brain.
-- * archetypes: Aggressive Pressure Fighter, Fast Counter Puncher, Technical Genius,
--   Knockout Artist, Defensive Specialist (different defense habits and punch choices)
-- * reacts to incoming punches with blocks, slips, rolls, parries and pivots
-- * anticipates the player's favourite punches (learned from previous fights)
-- * exploits weaknesses (shelling up -> body shots, gassed -> pressure)
-- * switches game plan with the scorecards; protects itself when hurt
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FightAI = {}
FightAI.__index = FightAI

local DEFAULT_ARCH = { aggr = 0, block = 0.3, slip = 0.25, roll = 0.2, parry = 0.1, pivot = 0.1, body = 0.1, overhand = 0.05, adapt = 1 }

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
	return self
end

function FightAI:Observe(dt)
	self.obs.time += dt
	if self.O.blocking then
		self.obs.blockTime += dt
	end
end

function FightAI:Intel()
	local o = self.obs
	local fav, favN = nil, 0
	for k, v in pairs(o.punches) do
		if v > favN then
			fav, favN = k, v
		end
	end
	return { blockRatio = o.time > 0 and o.blockTime / o.time or 0, favorite = fav, slips = o.slips }
end

-- called by the engine when the opponent starts a punch at us
function FightAI:OnOppPunch(ptype, body, windup)
	local F, engine = self.F, self.engine
	self.obs.punches[ptype] = (self.obs.punches[ptype] or 0) + 1
	if body then
		self.obs.body += 1
	end
	if F.state == "down" or F.state == "clinch" or engine:Now() < F.busyUntil then
		return
	end
	local s = F.data.stats
	local chance = (s.Reflexes * 0.5 + s.RingIQ * 0.3 + s.HeadMovement * 0.2) / 100 * 0.62
	chance += (self.anticipate[ptype] or 0) * 0.3
	local total = 0
	for _, v in pairs(self.obs.punches) do
		total += v
	end
	chance += ((self.obs.punches[ptype] or 0) / math.max(1, total)) * 0.12 * self.arch.adapt
	if F.stamina < F.maxStam * 0.25 then
		chance *= 0.6
	end
	if engine:IsHurt(F) then
		chance += 0.12
	end
	chance = math.clamp(chance, 0.05, 0.8)
	if self.rng:NextNumber() > chance then
		return
	end
	local react = math.max(0.06, 0.26 - s.Reflexes * 0.0018)
	if react >= windup then
		return
	end
	local kind = Config.Punches[ptype].kind
	-- choose a defense that suits the punch and this fighter's habits
	local a = self.arch
	local options = {}
	local function add(move, w)
		if w > 0 then
			table.insert(options, { move, w })
		end
	end
	add("block", a.block + (body and 0.3 or 0))
	if not body then
		if kind == "straight" then
			add("slip", a.slip)
			add("parry", a.parry)
			add("pivot", a.pivot * 0.6)
		elseif kind == "hook" or kind == "overhand" then
			add("roll", a.roll)
			add("slip", a.slip * 0.4)
		end
	end
	local totalW = 0
	for _, o in ipairs(options) do
		totalW += o[2]
	end
	local pick = self.rng:NextNumber() * totalW
	local move = "block"
	for _, o in ipairs(options) do
		pick -= o[2]
		if pick <= 0 then
			move = o[1]
			break
		end
	end
	task.delay(react, function()
		if F.state == "down" or engine.finished then
			return
		end
		if move == "slip" then
			engine:Slip(F, self.rng:NextNumber() < 0.5 and -1 or 1)
		elseif move == "roll" then
			engine:Roll(F)
		elseif move == "parry" then
			engine:Parry(F)
		elseif move == "pivot" then
			engine:Pivot(F, self.rng:NextNumber() < 0.5 and -1 or 1)
		else
			engine:SetBlock(F, true)
			self.blockUntil = engine:Now() + 0.55
		end
	end)
end

function FightAI:UpdateMode()
	local engine, F, O = self.engine, self.F, self.O
	local lead = engine:EstimateLead(F)
	local r, total = engine.round, engine.rounds
	if engine:IsHurt(F) or F.health < 30 then
		self.mode = "survive"
	elseif r > total / 2 and lead < 0 then
		self.mode = "pressure"
	elseif r >= total - 1 and lead >= 2 then
		self.mode = "cruise"
	elseif engine:IsHurt(O) or O.health < 35 then
		self.mode = "pressure"
	else
		self.mode = "plan"
	end
	local intel = self:Intel()
	self.bodyBias = 0.12 + self.arch.body + intel.blockRatio * 0.55 * self.arch.adapt
	self.exploitGassed = O.stamina < O.maxStam * 0.3
end

function FightAI:Aggression()
	local a = self.baseAggr
	if self.mode == "pressure" then
		a += 0.3
	elseif self.mode == "cruise" then
		a -= 0.2
	elseif self.mode == "survive" then
		a -= 0.45
	end
	if self.exploitGassed then
		a += 0.2
	end
	if self.F.stamina < self.F.maxStam * 0.3 then
		a -= 0.25
	end
	a += (self.F.data.mental.Confidence - 50) / 250
	return math.clamp(a, 0.05, 0.95)
end

-- preferred distance, as a share of this fighter's jab range
function FightAI:Range()
	local jab = self.engine:PunchRange(self.F, "jab")
	if self.mode == "survive" then
		return jab * 1.9
	elseif self.mode == "pressure" then
		return jab * math.min(self.baseRange, 0.74)
	elseif self.mode == "cruise" then
		return jab * math.max(self.baseRange, 0.94)
	end
	return jab * self.baseRange
end

function FightAI:Fits(ptype, dist)
	return dist <= self.engine:PunchRange(self.F, ptype) + 0.25
end

function FightAI:BuildCombo()
	local n = 1
	local aggr = self:Aggression()
	if self.rng:NextNumber() < aggr then
		n = self.rng:NextInteger(2, self.comboMax + (self.engine:IsHurt(self.O) and 1 or 0))
	end
	n = math.max(1, math.min(n, math.floor(self.F.stamina / 6)))
	local dist = self.engine:Distance(self.F, self.O)
	local list = {}
	for i = 1, n do
		local p = "jab"
		local roll = self.rng:NextNumber()
		if not (i == 1 and roll < self.jabRate + (self.mode == "cruise" and 0.25 or 0)) then
			local pool, total = {}, 0
			for _, opt in ipairs({
				{ "cross", 0.4 }, { "leadhook", 0.25 }, { "rearhook", 0.18 }, { "uppercut", 0.15 },
				{ "overhand", 0.03 + self.arch.overhand }, { "jab", 0.12 },
			}) do
				if self:Fits(opt[1], dist) then
					table.insert(pool, opt)
					total += opt[2]
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

function FightAI:Think(now)
	local F, O, engine = self.F, self.O, self.engine
	if now < self.nextThink then
		return
	end
	self.nextThink = now + 0.32 - F.data.stats.RingIQ * 0.0018
	if F.state == "down" or F.state == "clinch" or O.state == "down" then
		self.queue = {}
		return
	end
	local dist = engine:Distance(F, O)
	if now >= self.nextMove then
		self.nextMove = now + 0.35
		if self.rng:NextNumber() < 0.08 then
			self.circleDir = -self.circleDir
		end
		engine:MoveAI(F, self:Range(), self.circleDir * (self.style.id == "OutBoxer" and 0.45 or 0.22))
	end
	if F.blocking and now >= self.blockUntil then
		engine:SetBlock(F, false)
	end
	if now < F.busyUntil then
		return
	end
	-- cut off / escape the corner with a pivot
	if self.arch.pivot > 0.15 and dist < 3.2 and self.rng:NextNumber() < self.arch.pivot * 0.08 then
		engine:Pivot(F, self.circleDir)
		return
	end
	if self.mode == "survive" then
		if dist < 4.2 and self.rng:NextNumber() < 0.25 and engine:CanClinch(F) then
			engine:Clinch(F)
			return
		end
		if dist < 5 and self.rng:NextNumber() < 0.6 then
			engine:SetBlock(F, true)
			self.blockUntil = now + 0.7
			return
		end
	end
	if now < F.counterUntil and self:Fits("jab", dist) then
		local p = "jab"
		if self:Fits("leadhook", dist) and self.rng:NextNumber() < 0.5 then
			p = self.rng:NextNumber() < 0.5 and "leadhook" or "rearhook"
		elseif self:Fits("cross", dist) then
			p = (self.arch.overhand > 0.2 and self.rng:NextNumber() < 0.3) and "overhand" or "cross"
		end
		engine:Punch(F, p, false)
		return
	end
	if #self.queue > 0 then
		local nxt = table.remove(self.queue, 1)
		if dist <= engine:PunchRange(F, nxt.p) + 0.4 then
			engine:Punch(F, nxt.p, nxt.body)
		else
			self.queue = {}
		end
		return
	end
	local aggr = self:Aggression()
	if self:Fits("jab", dist) then
		if self.rng:NextNumber() < aggr * 0.13 + self.jabRate * 0.07 then
			self.queue = self:BuildCombo()
			local first = table.remove(self.queue, 1)
			engine:Punch(F, first.p, first.body)
		elseif self.rng:NextNumber() < (1 - aggr) * 0.3 * (0.6 + self.arch.block) then
			engine:SetBlock(F, true)
			self.blockUntil = now + 0.5
		end
	end
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
	return tips[lowest]
end

return FightAI
