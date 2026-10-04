-- FightEngine: server-authoritative real-time boxing.
-- Punches: jab, cross, lead hook, rear hook, uppercut, overhand (+ body shots).
-- Defense: block, parry, slip, roll, pivot, clinch. Counters, combos, stamina,
-- knockdowns + 10 count, KO/TKO, referee & doctor stoppages, visible face damage,
-- sweat, robes & mouthguards, venues, live commentary, three-judge scoring.
-- Also runs gym sparring sessions (Light / Medium / Hard).
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Builder = require(Shared:WaitForChild("Builder"))
local FightAI = require(script.Parent.FightAI)
local Career = require(script.Parent.Career)

local FightEngine = {}
FightEngine.Active = {} -- player -> fight
local Fight = {}
Fight.__index = Fight

local HEAD_SCALE = 0.55 -- how hard head shots land overall (lower = longer fights)

local SPAR = {
	Light = { rounds = 1, damage = 0.3, allowKD = false },
	Medium = { rounds = 2, damage = 0.55, allowKD = false },
	Hard = { rounds = 3, damage = 0.85, allowKD = true },
}
FightEngine.SparSettings = SPAR

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

------------------------------------------------------------------------
-- Fighter setup
------------------------------------------------------------------------
local function makeFighter(data, model, player)
	local s = data.stats
	local style = Config.FindById(Config.Styles, data.style) or Config.Styles[4]
	local mods = data.mods or {}
	local maxStam = (100 + (s.Stamina - 50) * 0.8) * (mods.staminaMul or 1)
	local fatigueFactor = 1 - math.max(0, (data.fatigue or 0) - 50) / 150
	local F = {
		data = data, model = model, player = player, isPlayer = player ~= nil,
		hum = model:FindFirstChildOfClass("Humanoid"), root = model:FindFirstChild("HumanoidRootPart"),
		style = style, classScale = 0.85 + (data.class - 1) * 0.045,
		powerMul = mods.powerMul or 1, speedMul = mods.speedMul or 1, moveMul = mods.moveMul or 1,
		maxStam = maxStam, stamina = maxStam * fatigueFactor,
		health = 100, healthCap = 100, body = 100,
		state = "idle", blocking = false, busyUntil = 0,
		slipUntil = 0, rollUntil = 0, parryUntil = 0, pivotEvadeUntil = 0, angleUntil = 0, nextPivot = 0,
		counterUntil = 0, hurtUntil = 0, clinchUntil = 0, nextClinch = 0, lastPunch = 0, combo = 0, hand = "R",
		kdRound = 0, kdTotal = 0, mash = 0, actId = 0, recentHits = {}, damageDealt = 0, damageTaken = 0,
		dmg = { leftEye = 0, rightEye = 0, cut = 0, cutSide = 1, noseBleed = 0, nose = false, bruise = 0, lip = 0 },
		tally = { landed = 0, power = 0, body = 0, thrown = 0, kd = 0, clinches = 0 },
		totals = { landed = 0, thrown = 0, power = 0, body = 0 },
		punchesUsed = { jab = 0, cross = 0, leadhook = 0, rearhook = 0, uppercut = 0, overhand = 0 },
	}
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

function Fight:PunchRange(F, ptype)
	local base = 3.5 + ((F.data.reach or 70) - 70) * 0.05 + ((F.data.height or 70) - 70) * 0.02
	-- never shorter than the closest the bodies can get (2.6 apart), so every punch can land up close
	return math.max(2.85, base * (Config.Punches[ptype] and Config.Punches[ptype].range or 1))
end

function Fight:IsHurt(F)
	return self:Now() < F.hurtUntil
end

function Fight:Other(F)
	return F == self.P and self.O or self.P
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
	if F.state == "down" then
		g = "down"
	elseif F.blocking then
		g = "block"
	elseif F.state == "clinch" then
		g = "clinch"
	elseif self:IsHurt(F) then
		g = "hurt"
	end
	if F.model:GetAttribute("Guard") ~= g then
		F.model:SetAttribute("Guard", g)
	end
end

function Fight:RefreshDamage(F)
	local d = F.dmg
	local key = string.format("%.1f%.1f%.1f%.1f%s%.1f%.1f", d.leftEye, d.rightEye, d.cut, d.noseBleed, tostring(d.nose), d.bruise, d.lip)
	if key ~= F.dmgKey then
		F.dmgKey = key
		Builder.SetDamage(F.model, F.data.app, d)
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

local function sideKey(hand)
	-- a left-hand punch lands on the opponent's right side, and vice versa
	return hand == "L" and "rightEye" or "leftEye", hand == "L" and 1 or -1
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
	local angled = now < F.angleUntil
	if angled then
		chance += 0.15
		F.angleUntil = 0
	end
	chance = math.clamp(chance * vision, 0.15, 0.95)
	if not O.blocking and self.rng:NextNumber() > chance then
		self:Miss(F, O, ptype, "miss")
		return
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
	if dist < 3 then
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

	-- block (the overhand comes over the top of the guard)
	if O.blocking and not body then
		local through = P.overGuard or 0
		local chip = dmg * math.clamp(0.28 - os_.Blocking / 400, 0.04, 0.25)
		O.health = math.max(0, O.health - chip - dmg * through * HEAD_SCALE * 0.6)
		O.stamina = math.max(0, O.stamina - (1.5 + dmg * 0.25))
		O.counterUntil = now + 0.55 * (os_.Countering / 70)
		self:Send({ t = "blocked", who = self:Who(O), punch = ptype })
		self:SetAct(O, "blockhit")
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
	local eyeKey, side = sideKey(F.hand)
	if body then
		F.tally.body += 1
		F.totals.body += 1
		local bd = dmg * 0.8 * (1.2 - os_.Endurance / 200)
		O.body = math.max(0, O.body - bd)
		O.stamina = math.max(0, O.stamina - dmg * 0.6)
		O.health = math.max(0, O.health - dmg * 0.15)
		F.damageDealt += bd * 0.5
		O.damageTaken += bd * 0.5
	else
		local chinMul = 1.35 - os_.Chin / 100 * 0.7
		local hd = dmg * HEAD_SCALE * chinMul * (O.dmg.cut > 0.5 and 1.08 or 1)
		O.health = math.max(0, O.health - hd)
		F.damageDealt += hd
		O.damageTaken += hd
		dmg = hd
		local d = O.dmg
		if P.kind == "hook" or P.kind == "overhand" then
			d[eyeKey] = math.min(1, d[eyeKey] + hd / 40)
			d.bruise = math.min(1, d.bruise + hd / 70)
		elseif P.kind == "straight" then
			d[eyeKey] = math.min(1, d[eyeKey] + hd / 110)
			d.noseBleed = math.min(1, d.noseBleed + hd / 45)
			d.lip = math.min(1, d.lip + hd / 90)
			if not d.nose and hd > 5 and self.rng:NextNumber() < 0.06 then
				d.nose = true
				self:Comment("That nose is BROKEN!", true)
			end
		else
			d.lip = math.min(1, d.lip + hd / 40)
			d.bruise = math.min(1, d.bruise + hd / 90)
		end
		if self.rng:NextNumber() < P.cutChance * (hd / 3.5) * (self.cutRisk[O] or 1) then
			d.cut = math.min(1.2, d.cut + self.rng:NextNumber(0.15, 0.32))
			d.cutSide = side
			self:Send({ t = "announce", text = (O == self.P and "You're" or O.data.name .. " is") .. " CUT!" })
			self:Comment("There's blood! " .. O.data.name .. " is cut over the eye!", true)
		end
		self:RefreshDamage(O)
	end
	local heavy = (body and dmg >= 9) or (not body and (dmg >= 9 * HEAD_SCALE * self.damageScale or (counter and dmg >= 5.5 * HEAD_SCALE * self.damageScale)))
	if heavy then
		O.hurtUntil = now + 1.4 + dmg / 6
	end
	self:SetAct(O, body and "hitbody" or ("hit|" .. ptype))
	self:Send({ t = "hit", who = self:Who(F), punch = ptype, body = body, dmg = math.floor(dmg * 10) / 10, counter = counter, heavy = heavy })
	if heavy then
		local name = Config.PunchNames[ptype]
		self:Comment(string.format("%s lands a %s%s%s!", F.data.name, counter and "counter " or "", body and "body " or "", name:lower()), counter)
	end

	-- knockdown checks
	local kd = false
	if O.health <= 0 or O.body <= 0 then
		kd = true
	elseif not body and dmg >= 8 * HEAD_SCALE * self.damageScale then
		local p = (dmg - 7 * HEAD_SCALE * self.damageScale) / (35 * HEAD_SCALE * self.damageScale) * (1.25 - O.health / 100) * (1.45 - os_.Chin / 100) * (counter and 1.6 or 1)
		p *= 1.1 - O.data.mental.Composure / 300
		kd = self.rng:NextNumber() < p
	elseif body and O.body < 25 and dmg >= 7 * self.damageScale then
		kd = self.rng:NextNumber() < 0.22
	end
	if kd then
		if self.allowKD then
			self:Knockdown(O, F)
		else
			-- sparring: the coach steps in instead of a knockdown
			O.health = math.max(O.health, 18)
			O.body = math.max(O.body, 20)
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
	self:Send({ t = "miss", who = self:Who(F), why = why })
end

function Fight:SetBlock(F, on)
	if not self:CanAct(F) then
		return
	end
	if on and self:Now() < F.busyUntil and F.state == "punching" then
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
	F.slipUntil = now + 0.26 + F.data.stats.Reflexes * 0.003 + F.data.stats.HeadMovement * 0.002
	F.busyUntil = now + 0.42
	self:SetAct(F, "slip|" .. (dir == -1 and "L" or "R"))
end

function Fight:Roll(F)
	if not defenseReady(self, F, 5) then
		return
	end
	local now = self:Now()
	F.rollUntil = now + 0.3 + F.data.stats.HeadMovement * 0.003
	F.busyUntil = now + 0.55
	self:SetAct(F, "roll")
end

function Fight:Parry(F)
	if not defenseReady(self, F, 2) then
		return
	end
	local now = self:Now()
	F.parryUntil = now + 0.18 + F.data.stats.Reflexes * 0.002
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
	F.pivotEvadeUntil = now + 0.25
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
	return self:CanAct(F) and O.state ~= "down" and self:Now() >= F.nextClinch and F.stamina >= 4 and self:Distance(F, O) < 4.4
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
	end
	F.health = math.min(F.healthCap, F.health + 4)
	F.hurtUntil = math.min(F.hurtUntil, now + 0.6)
	self:Send({ t = "announce", text = "CLINCH! The referee steps in..." })
	self:Comment(F.data.name .. " ties up. Smart veteran move.")
end

------------------------------------------------------------------------
-- Knockdowns & stoppages
------------------------------------------------------------------------
function Fight:Knockdown(F, by)
	if F.state == "down" or self.finished then
		return
	end
	F.state = "down"
	F.blocking = false
	F.kdRound += 1
	F.kdTotal += 1
	F.mash = 0
	by.tally.kd += 1
	self.paused = true
	self:UpdateGuard(F)
	self:Send({ t = "kd", who = self:Who(F) })
	self:Comment("DOWN GOES " .. F.data.name:upper() .. "!", true)
	local corner = (by == self.P) and self.anchors.RedNeutral or self.anchors.BlueNeutral
	self:Place(by, corner.Position)
	if F.kdRound >= 3 then
		task.wait(1.5)
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
	return math.clamp(a, 0.05, 0.95)
end

function Fight:Count(F)
	local id = self.id
	local ability = self:GetUpAbility(F)
	local aiUpAt = nil
	if not F.isPlayer and self.rng:NextNumber() < ability + 0.15 then
		aiUpAt = math.clamp(math.floor(9 - ability * 6 + self.rng:NextInteger(-1, 1)), 3, 9)
	end
	local target = math.floor(12 + F.kdTotal * 6 + (1 - ability) * 18)
	if F.isPlayer then
		self:Send({ t = "getupStart", target = target })
	end
	for n = 1, 10 do
		task.wait(0.85)
		if self.id ~= id or self.finished then
			return
		end
		self:Send({ t = "count", n = n, who = self:Who(F), mash = F.mash, target = target })
		local up
		if F.isPlayer then
			up = n >= 2 and n <= 9 and F.mash >= target
		else
			up = aiUpAt ~= nil and n >= aiUpAt
		end
		if up then
			self:GetUp(F)
			return
		end
	end
	self:Comment("It's OVER! " .. F.data.name .. " can't beat the count!", true)
	self:End(self:Other(F), "KO", "Counted out")
end

function Fight:GetUp(F)
	local s = F.data.stats
	F.health = math.max(F.health, math.min(F.healthCap, 22 + s.Recovery * 0.25 - F.kdTotal * 4))
	F.body = math.max(F.body, 20)
	F.healthCap = math.max(35, F.healthCap - 8)
	F.state = "idle"
	F.hurtUntil = self:Now() + 2.5
	F.busyUntil = self:Now() + 0.8
	F.stamina = math.max(F.stamina, F.maxStam * 0.3)
	self:UpdateGuard(F)
	self:Send({ t = "getup", who = self:Who(F) })
	self:Comment(F.data.name .. " beats the count! What heart!", true)
	task.wait(1.2)
	if not self.finished then
		self:Send({ t = "announce", text = "BOX!" })
		self.paused = false
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
	if F.health < 16 and n >= 5 and now - F.lastPunch > 2 then
		if self.allowKD then
			self:Comment("The referee waves it off!", true)
			self:End(self:Other(F), "TKO", "Referee stops the fight")
		else
			self:End(self:Other(F), "Stopped", "Coach stops the sparring session")
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
local MIN_SEP, CLINCH_SEP = 2.6, 1.9

function Fight:MoveAI(F, range, circle)
	if not F.hum or F.state == "down" or F.state == "clinch" then
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

function Fight:UpdateMovement(F)
	local O = self:Other(F)
	if F.align and F.root and O.root then
		local dir = flat(O.root.Position - F.root.Position)
		if dir.Magnitude > 0.05 then
			F.align.CFrame = CFrame.lookAt(Vector3.zero, dir.Unit)
		end
		F.align.Enabled = F.state ~= "down"
	end
	if F.hum then
		local s = F.data.stats
		local speed = (8 + s.Footwork * 0.08) * F.style.fight.move * F.moveMul
		if F.state == "down" or F.state == "clinch" or self.paused or not self.live then
			speed = 0
		elseif F.state == "punching" then
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
		if math.abs(F.hum.WalkSpeed - speed) > 0.05 then
			F.hum.WalkSpeed = speed
		end
		if speed == 0 and not F.isPlayer then
			F.hum:MoveTo(F.root.Position)
		end
	end
	if F.root then
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
		F.stamina = math.min(F.maxStam, F.stamina + regen * dt)
		if F.state ~= "down" and #F.recentHits == 0 then
			F.health = math.min(F.healthCap, F.health + (0.3 + s.Recovery * 0.008) * dt)
		end
		self:UpdateMovement(F)
		if F == self.O then
			self:Separate()
		end
		self:UpdateGuard(F)
		self:CheckStoppage(F)
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
	self.sendAcc = (self.sendAcc or 0) + dt
	if self.sendAcc >= 0.1 then
		self.sendAcc = 0
		self:Send({
			t = "state",
			time = math.max(0, math.ceil(self.roundEnd - now)),
			me = { hp = self.P.health, cap = self.P.healthCap, body = self.P.body, stam = self.P.stamina, max = self.P.maxStam, hurt = self:IsHurt(self.P), angle = now < self.P.angleUntil },
			opp = { hp = self.O.health, cap = self.O.healthCap, body = self.O.body, stam = self.O.stamina, max = self.O.maxStam, hurt = self:IsHurt(self.O) },
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
	if P.stamina < P.maxStam * 0.4 then
		table.insert(tips, "Breathe! You're punching yourself out - pick your shots.")
	end
	if O.tally.body >= 3 then
		table.insert(tips, "Elbows tight! They're investing in the body.")
	end
	if O.ai and O.ai.mode == "survive" then
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
	if P.dmg.cut > 0.4 then
		table.insert(tips, "Cutman's working on that cut - keep your guard high.")
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
			Builder.SetSweat(F.model, F.data.app, level)
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
		F.stamina = math.min(F.maxStam, F.stamina + F.maxStam * (0.25 + s.Recovery * 0.004) * nut)
		F.healthCap = math.max(30, F.healthCap - (100 - F.health) * 0.12)
		F.health = math.min(F.healthCap, F.health + (8 + s.Recovery * 0.15) * nut)
		F.body = math.min(100, F.body + 5)
		F.dmg.cut = math.max(0, F.dmg.cut - (F.data.eliteCorner and 0.25 or 0.15))
		F.dmg.noseBleed = math.max(0, F.dmg.noseBleed - 0.3)
		F.hurtUntil = 0
		F.kdRound = 0
		F.blocking = false
		F.state = "idle"
		self:RefreshDamage(F)
	end
end

function Fight:DoctorCheck()
	for _, F in ipairs({ self.P, self.O }) do
		if F.dmg.cut >= 1 or (F.dmg.leftEye >= 1 and F.dmg.rightEye >= 1) then
			self:Comment("The ringside doctor has seen enough!", true)
			self:End(self:Other(F), self.spar and "Stopped" or "TKO", "Doctor stops the fight (" .. (F.dmg.cut >= 1 and "cut" or "eyes swollen shut") .. ")")
			return
		end
	end
	local O = self.O
	if not self.spar and O.healthCap < 40 and self:EstimateLead(O) < -2 and self.rng:NextNumber() < 0.3 then
		self:End(self.P, "RTD", "Opponent's corner retires them")
	end
end

function Fight:Entrance()
	local P, O = self.P, self.O
	local isStadium = self.venue == "Stadium"
	Builder.SetRobe(O.model, O.data.app, true, O.data.lookOpts)
	Builder.SetRobe(P.model, P.data.app, true, P.data.lookOpts)
	self:Place(O, self.anchors.BlueEntrance.Position, self.anchors.RingCenter.Position)
	self:Place(P, self.anchors.RedEntrance.Position, self.anchors.RingCenter.Position)
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
	Builder.SetRobe(P.model, P.data.app, false)
	Builder.SetRobe(O.model, O.data.app, false)
end

function Fight:Run()
	local P, O = self.P, self.O
	local offer = self.offer
	self:Send({
		t = "start", rounds = self.rounds, kind = offer.kind, stakes = offer.stakes or {}, playerStakes = offer.playerStakes or {},
		arena = self.arena, oppModel = O.model, venue = self.venue, venueName = offer.venueName or "", spar = self.spar,
		weighIn = P.data.mods and P.data.mods.weighIn, notes = P.data.mods and P.data.mods.notes,
		tape = {
			you = { name = P.data.name, nick = P.data.nick, nat = P.data.nat, record = P.data.record, height = P.data.height, reach = P.data.reach, style = P.style.name, overall = Config.Overall(P.data.stats) },
			opp = { name = O.data.name, nick = O.data.nick, nat = O.data.nat, record = O.data.record, height = O.data.height, reach = O.data.reach, style = O.style.name, overall = Config.Overall(O.data.stats),
				archetype = (Config.FindById(Config.Archetypes, O.data.archetype) or {}).name },
		},
		talk = offer.talk, myLine = offer.myLine,
	})
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
				seconds = Config.RestSeconds,
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
	res.cards = self.cards
	res.kdFor = O.kdTotal
	res.kdAgainst = P.kdTotal
	res.landed, res.thrown = P.totals.landed, P.totals.thrown
	res.oppLanded, res.oppThrown = O.totals.landed, O.totals.thrown
	res.punches = P.punchesUsed
	res.damageDealt, res.damageTaken = P.damageDealt, P.damageTaken
	res.weighIn = P.data.mods and P.data.mods.weighIn
	res.cutTaken = P.dmg.cut > 0.3
	return res
end

function Fight:Cleanup()
	for _, F in ipairs({ self.P, self.O }) do
		if F.model then
			CollectionService:RemoveTag(F.model, "Fighter")
			F.model:SetAttribute("Guard", nil)
			F.model:SetAttribute("Act", nil)
		end
		if F.align then
			F.align:Destroy()
		end
		if F.alignAtt then
			F.alignAtt:Destroy()
		end
	end
	local P = self.P
	if P.hum then
		P.hum.AutoRotate = true
		P.hum.WalkSpeed = 16
		P.hum.JumpHeight = 7.2
	end
	if P.model and P.model.Parent then
		local look = P.model:FindFirstChild("BoxerLook")
		if look then
			for _, n in ipairs({ "Damage", "Robe", "Headgear" }) do
				local f = look:FindFirstChild(n)
				if f then
					f:Destroy()
				end
			end
		end
		Builder.SetSweat(P.model, P.data.app, 0)
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
	self.arena = arena
	self.roundEnd = 0
	self.cutRisk = {}
	local anchors = {}
	for _, p in ipairs(arena:WaitForChild("Anchors"):GetChildren()) do
		anchors[p.Name] = p
	end
	self.anchors = anchors
	self.ringHalf = arena:GetAttribute("RingHalf") or 11

	local npc = Builder.CreateNPC(oData.app, oData.build, oData.gear, oData.name, { hands = "gloves", mouthguard = true, name = oData.name, nick = oData.nick, nat = oData.nat, waistText = oData.nick })
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
	Builder.Cosmetics(char, pData.app, pData.build, pData.gear, lookOpts)
	if self.spar then
		Builder.SetHeadgear(char, Color3.fromRGB(30, 60, 160), true)
		Builder.SetHeadgear(npc, Color3.fromRGB(170, 25, 30), true)
	end
	self.P = makeFighter(pData, char, player)
	self.O = makeFighter(oData, npc, nil)
	if (pData.injuryCut) then
		self.cutRisk[self.P] = 1.8
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
			F.mash += 1
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
