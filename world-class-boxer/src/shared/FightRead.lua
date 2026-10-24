-- FightRead: an AI's rolling read of the man in front of it (FightAI owns one per fight). Shared and pure: no Roblox
-- services, so tools/sim/test_fightai drives it directly.
--
-- Everything it counts decays with a half-life of HALF_LIFE seconds of fight time, so it reads what he is doing
-- NOW (a man who spammed the jab in round 1 and switched to the body in round 3 reads as a body puncher):
--   punches     each punch type thrown, to the head and to the body (favourite punch, head / body share)
--   follow-ups  which punch follows which (the previous token -> the next: "after his jab comes the cross")
--   combos      how long his combinations run, and what he does when one ends (punches again / blocks /
--               backs off / nothing): the AI times its attack to the end of his combinations
--   dodges      which way he slips (left / right) and which dodges he uses
--   guard       how much of the time he blocks, and how often he blocks the moment the AI throws
--   gas         how often he still throws when tired (his stamina management)
--   distance    the distance he likes to fight at
--   feints      how many of his "punches" were feints (the AI learns to stop biting)
-- The read never sees anything the AI could not see in a real ring: only what he already did.
local FightRead = {}
FightRead.__index = FightRead

FightRead.HALF_LIFE = 30
FightRead.MIN_SEEN = 4 -- weight before a prediction is trusted at all

local PUNCH_KIND = { jab = "straight", cross = "straight", leadhook = "hook", rearhook = "hook", uppercut = "uppercut", overhand = "overhand" }
FightRead.KIND = PUNCH_KIND

function FightRead.new()
	local self = setmetatable({}, FightRead)
	self.t = 0
	self.punch = {} -- ptype -> w
	self.kind = {} -- kind -> w
	self.head, self.body = 0, 0
	self.trans = {} -- prev ptype -> { ptype -> w }
	self.slip = { [-1] = 0, [1] = 0 }
	self.dodge = {} -- kind -> w
	self.blockT, self.timeT = 0, 0
	self.reactBlock, self.reactSeen = 0, 0
	self.tiredThrows, self.tiredTime = 0, 0
	self.distSum, self.distW = 0, 0
	self.feints, self.leads = 0, 0
	self.chainLen, self.chains = 0, 0
	self.after = { punch = 0, block = 0, move = 0, idle = 0 }
	self.prev = nil
	self.prevAt = -10
	self.total = 0
	return self
end

-- the decay factor for dt seconds
local function decay(dt)
	return 0.5 ^ (dt / FightRead.HALF_LIFE)
end

local function scaleMap(m, k)
	for key, v in pairs(m) do
		m[key] = v * k
	end
end

-- once a frame (or every few): the decay, the guard time, the tired time
function FightRead:Tick(dt, blocking, tired)
	if dt <= 0 then
		return
	end
	self.t += dt
	local k = decay(dt)
	scaleMap(self.punch, k)
	scaleMap(self.kind, k)
	scaleMap(self.dodge, k)
	scaleMap(self.after, k)
	for _, m in pairs(self.trans) do
		scaleMap(m, k)
	end
	self.slip[-1] *= k
	self.slip[1] *= k
	self.head *= k
	self.body *= k
	self.total *= k
	self.feints *= k
	self.leads *= k
	self.blockT = self.blockT * k + (blocking and dt or 0)
	self.timeT = self.timeT * k + dt
	self.tiredTime = self.tiredTime * k + (tired and dt or 0)
	self.tiredThrows *= k
	self.reactBlock *= k
	self.reactSeen *= k
	self.distSum *= k
	self.distW *= k
	self.chainLen *= k
	self.chains *= k
end

-- he threw a punch (chainPos = its place in his combination, 1 = an opener; dist = the distance; tired = his
-- stamina is low)
function FightRead:Punch(ptype, body, chainPos, dist, tired)
	self.punch[ptype] = (self.punch[ptype] or 0) + 1
	local kind = PUNCH_KIND[ptype] or "straight"
	self.kind[kind] = (self.kind[kind] or 0) + 1
	if body then
		self.body += 1
	else
		self.head += 1
	end
	self.total += 1
	if (tonumber(chainPos) or 1) >= 2 and self.prev then
		local m = self.trans[self.prev]
		if not m then
			m = {}
			self.trans[self.prev] = m
		end
		m[ptype] = (m[ptype] or 0) + 1
	else
		self.leads += 1
	end
	self.prev = ptype
	if tired then
		self.tiredThrows += 1
	end
	if dist then
		self.distSum += dist
		self.distW += 1
	end
end

-- he feinted (counted as a lead the AI may have bitten on)
function FightRead:Feint()
	self.feints += 1
end

-- his combination ended after n punches; what = what he did next ("punch" | "block" | "move" | "idle")
function FightRead:ComboEnd(n)
	if (tonumber(n) or 0) >= 2 then
		self.chainLen += n
		self.chains += 1
	end
	self.prev = nil
end
function FightRead:After(what)
	if self.after[what] ~= nil then
		self.after[what] += 1
	end
end

-- he dodged (kind, dir = -1 left / 1 right for a slip or a weave)
function FightRead:Dodge(kind, dir)
	self.dodge[kind] = (self.dodge[kind] or 0) + 1
	if (kind == "slip" or kind == "weave") and (dir == -1 or dir == 1) then
		self.slip[dir] += 1
	end
end

-- the AI threw at him: did he block it on the spot?
function FightRead:Reacted(blocked)
	self.reactSeen += 1
	if blocked then
		self.reactBlock += 1
	end
end

------------------------------------------------------------------------
-- What it knows
------------------------------------------------------------------------
-- his favourite punch and its share of what he throws
function FightRead:Favourite()
	local best, bw = nil, 0
	for p, w in pairs(self.punch) do
		if w > bw or (w == bw and best and p < best) then
			best, bw = p, w
		end
	end
	return best, self.total > 0 and bw / self.total or 0
end

-- the share of a punch type in what he throws
function FightRead:Share(ptype)
	return self.total > 0 and (self.punch[ptype] or 0) / self.total or 0
end
function FightRead:KindShare(kind)
	return self.total > 0 and (self.kind[kind] or 0) / self.total or 0
end

function FightRead:BodyShare()
	local n = self.head + self.body
	return n > 0 and self.body / n or 0
end

function FightRead:BlockShare()
	return self.timeT > 0 and self.blockT / self.timeT or 0
end

-- how often he blocks the moment the AI throws (0..1, 0.5 until seen)
function FightRead:ReactBlock()
	if self.reactSeen < 2 then
		return 0.5
	end
	return self.reactBlock / self.reactSeen
end

-- his slip side (-1 left / 1 right) and how one-sided it is (0 = even, 1 = always that side)
function FightRead:SlipSide()
	local l, r = self.slip[-1], self.slip[1]
	local n = l + r
	if n < 2 then
		return 0, 0
	end
	if l >= r then
		return -1, (l - r) / n
	end
	return 1, (r - l) / n
end

-- the distance he likes to fight at (nil until seen)
function FightRead:Distance()
	return self.distW > 0.5 and self.distSum / self.distW or nil
end

-- his punches per minute of read time while tired / overall: a man who keeps throwing when gassed
function FightRead:TiredOutput()
	return self.tiredTime > 1 and self.tiredThrows / self.tiredTime * 60 or 0
end

function FightRead:FeintShare()
	local n = self.feints + self.leads
	return n > 0.5 and self.feints / n or 0
end

-- the average length of his combinations (0 until seen)
function FightRead:ComboLength()
	return self.chains > 0.3 and self.chainLen / self.chains or 0
end

-- what he does most after a combination ("punch" | "block" | "move" | "idle") and its share
function FightRead:AfterCombo()
	local best, bw, n = nil, 0, 0
	for k, w in pairs(self.after) do
		n += w
		if w > bw then
			best, bw = k, w
		end
	end
	if n < 1.5 then
		return nil, 0
	end
	return best, bw / n
end

-- the punch he throws next after `prev` (nil = as a lead): ptype, confidence 0..1 (how much of his record
-- after that punch it is, scaled by how much it has seen)
function FightRead:Predict(prev)
	local m = prev and self.trans[prev]
	local src, n = m, 0
	if m then
		for _, w in pairs(m) do
			n += w
		end
	end
	if n < 1.5 then
		src, n = self.punch, self.total
	end
	if not src or n <= 0 then
		return nil, 0
	end
	local best, bw = nil, 0
	for p, w in pairs(src) do
		if w > bw or (w == bw and best and p < best) then
			best, bw = p, w
		end
	end
	local seen = math.clamp(n / FightRead.MIN_SEEN, 0, 1)
	return best, (bw / n) * seen
end

return FightRead
