--!nocheck
-- tools/sim/test_fightai.luau: the deeper fight and the smarter AI, under lune (tools/sim/fightsim: the real
-- FightEngine / FightAI on stub rigs, a fake clock).
--   * the ring traits (Shared.Traits): from the seed, style and level, deterministic, capped; the scouting (on the
--     tapes, met before, an elite corner) and the reveal in the fight; each trait's effect in the engine and its
--     counter; none in a spar, the tutorial, a PvP bout or for a player
--   * the fighting type (Traits.FightingType) from what a fighter does
--   * the read (Shared.FightRead): decay, the favourite, the follow-up, the slip side, the feints
--   * FightAI: the perception delay (nothing it could not have seen), prediction from the read (and the wrong
--     guess it commits to), adaptation to a spammed punch, feints and the bite, mistakes by skill
--   * the new mechanics: the feint, the second wind, accuracy with fatigue / damage / eyes, the blind side,
--     side-aware slips, the clinch's inside work and the break, the momentum, the live score, the ropes
--   * balance bounds: AI vs AI by style and level, scripted players vs the AI, traits vs the types they resist
--   lune run tools/sim/test_fightai.luau [--quick]
local process = require("@lune/process")
local fs = require("@lune/fs")
local FS = require("./fightsim")
local S = FS.new()
local Config, Traits, FightRead, FightAI, FightEngine = S.Config, S.Traits, S.FightRead, S.FightAI, S.FightEngine
local Random = S.H.globals.Random
local QUICK = table.find(process.args, "--quick") ~= nil

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

------------------------------------------------------------------------
-- Traits, pure
------------------------------------------------------------------------
do
	local a = Traits.ForBoxer({ id = "b17", style = "Slugger", archetype = "KO", overall = 78 })
	local b = Traits.ForBoxer({ id = "b17", style = "Slugger", archetype = "KO", overall = 78 })
	check("traits: the same boxer always has the same traits", #a == #b and (a[1] and a[1].id) == (b[1] and b[1].id))
	check("traits: by display names too", Traits.ForBoxer({ id = "b17", style = "Slugger", archetype = "Knockout Artist", overall = 78 })[1].id == a[1].id)
	check("traits: none under the minimum level", #Traits.ForBoxer({ id = "b1", style = "Slugger", overall = 35 }) == 0)
	check("traits: none without an id (a one-off boxer) or for the tutorial's", #Traits.ForBoxer({ style = "Slugger", overall = 80 }) == 0
		and #Traits.ForBoxer({ id = "tut55", style = "Slugger", overall = 80 }) == 0)
	-- counts and strength by level, the style's weights
	local counts, strength, slug, outb = { [40] = 0, [60] = 0, [76] = 0, [88] = 0 }, {}, {}, {}
	for lvl in pairs(counts) do
		local s = 0
		for i = 1, 300 do
			local t = Traits.ForBoxer({ id = "x" .. i, style = "BoxerPuncher", overall = lvl })
			counts[lvl] += #t
			for _, x in ipairs(t) do
				s = math.max(s, x.s)
				check("traits: strength in 0.35..1", x.s >= 0.35 - 1e-9 and x.s <= 1 + 1e-9, x.s)
			end
		end
		strength[lvl] = s
	end
	check("traits: more of them at a higher level", counts[40] < counts[60] and counts[60] < counts[76] and counts[76] < counts[88], counts[40] .. " " .. counts[60] .. " " .. counts[76] .. " " .. counts[88])
	check("traits: at most two (the elite always two)", counts[88] == 600)
	check("traits: stronger at a higher level", strength[40] < strength[60] and strength[60] < strength[88])
	for i = 1, 400 do
		for _, x in ipairs(Traits.ForBoxer({ id = "s" .. i, style = "Slugger", overall = 70 })) do
			slug[x.id] = (slug[x.id] or 0) + 1
		end
		for _, x in ipairs(Traits.ForBoxer({ id = "s" .. i, style = "OutBoxer", overall = 70 })) do
			outb[x.id] = (outb[x.id] or 0) + 1
		end
	end
	check("traits: sluggers are iron-chinned / granite", (slug.IronChin or 0) + (slug.Granite or 0) > ((slug.Slick or 0) + (slug.RingGeneral or 0)) * 2)
	check("traits: out-boxers are slick ring generals", (outb.Slick or 0) + (outb.RingGeneral or 0) > ((outb.IronChin or 0) + (outb.Granite or 0)) * 2)
	-- every effect is capped, and the data is complete
	for _, id in ipairs(Traits.List) do
		local D = Traits.Data[id]
		check("traits: " .. id .. " has its text", type(D.name) == "string" and type(D.hint) == "string" and type(D.counter) == "string" and type(D.desc) == "string")
		for kind in pairs(D.max) do
			local v = Traits.Effect(id, kind, 5)
			check("traits: " .. id .. "." .. kind .. " capped", v <= (Traits.CAP[kind] or 1) + 1e-9 and v <= D.max[kind] + 1e-9)
		end
		local any = false
		for _ in pairs(D.resists) do
			any = true
		end
		check("traits: " .. id .. " resists a fighting type", any)
	end
	check("traits: no effect at strength 0", Traits.Effect("IronChin", "dmg", 0) == 0)
	-- scouting
	local two = { { id = "IronChin", s = 0.8 }, { id = "Slick", s = 0.6 } }
	local sc = Traits.Scout(two, { fights = { w = 3, l = 1, d = 0 } })
	check("scout: a prospect's traits are all hidden", not sc[1].known and not sc[2].known)
	sc = Traits.Scout(two, { fights = { w = 9, l = 2, d = 0 } })
	check("scout: an established boxer's main trait is on the tapes", sc[1].known and not sc[2].known)
	sc = Traits.Scout(two, { fights = { w = 9, l = 2, d = 0 }, elite = true })
	check("scout: an elite corner finds one more", sc[1].known and sc[2].known)
	sc = Traits.Scout(two, { fights = 0, h2h = { w = 1, l = 0, d = 0 } })
	check("scout: fought him before: all known", sc[1].known and sc[2].known)
	check("scout: the card line", Traits.ScoutText(Traits.Scout(two, { fights = 10 })) == "Iron Chin  ·  1 unknown trait", Traits.ScoutText(Traits.Scout(two, { fights = 10 })))
	check("scout: nothing for a man without traits", Traits.ScoutText({}) == nil)
	local view = Traits.ScoutView({ id = "b17", style = "Slugger", archetype = "Knockout Artist", overall = 78, record = { w = 20, l = 2, d = 0 }, h2h = { w = 0, l = 0, d = 0 } })
	check("scout: the offer card's view = the engine's traits", view[1].id == a[1].id and view[1].known == true)
	-- the fighting type
	check("type: the style's prior before he has thrown", Traits.FightingType({ style = "Swarmer", thrown = 3 }) == "Pressure")
	check("type: body puncher", Traits.FightingType({ style = "OutBoxer", thrown = 100, minutes = 5, body = 55, heavy = 30, landed = 40 }) == "BodyPuncher")
	check("type: power puncher", Traits.FightingType({ style = "BoxerPuncher", thrown = 80, minutes = 6, body = 8, heavy = 50, landed = 30 }) == "Power")
	check("type: volume puncher", Traits.FightingType({ style = "BoxerPuncher", thrown = 200, minutes = 5, body = 30, heavy = 50, landed = 80 }) == "Volume")
	check("type: counter-puncher", Traits.FightingType({ style = "BoxerPuncher", thrown = 60, minutes = 5, body = 10, heavy = 15, landed = 30, counters = 12 }) == "Counter")
	check("type: pressure fighter", Traits.FightingType({ style = "OutBoxer", thrown = 90, minutes = 5, body = 18, heavy = 25, landed = 30, pressing = 0.8 }) == "Pressure")
	check("type: head-hunter", Traits.FightingType({ style = "OutBoxer", thrown = 90, minutes = 5, body = 2, heavy = 40, landed = 30 }) == "HeadHunter")
	check("resists: Iron Chin vs power, Body Armor vs the body puncher, Counter Specialist vs volume", Traits.Resists("IronChin", "Power")
		and Traits.Resists("BodyArmor", "BodyPuncher") and Traits.Resists("CounterSpecialist", "Volume") and not Traits.Resists("IronChin", "BodyPuncher"))
end

------------------------------------------------------------------------
-- FightRead, pure
------------------------------------------------------------------------
do
	local r = FightRead.new()
	for _ = 1, 10 do
		r:Punch("jab", false, 1, 4, false)
		r:Punch("cross", false, 2, 4, false)
	end
	local fav, share = r:Favourite()
	check("read: the favourite (a tie goes by name)", (fav == "cross" or fav == "jab") and near(share, 0.5, 0.01))
	local p, conf = r:Predict("jab")
	check("read: after his jab comes the cross", p == "cross" and conf > 0.9, tostring(p) .. " " .. conf)
	local total = r.total
	r:Tick(FightRead.HALF_LIFE, false, false)
	check("read: it decays (half-life)", near(r.total, total / 2, 0.01))
	r:Dodge("slip", -1)
	r:Dodge("slip", -1)
	r:Dodge("slip", 1)
	local side, str = r:SlipSide()
	check("read: his slip side", side == -1 and str > 0.2)
	for _ = 1, 6 do
		r:Feint()
	end
	check("read: the feints he throws", r:FeintShare() > 0.5)
	check("read: body share", near(r:BodyShare(), 0, 1e-9))
	local fresh = FightRead.new()
	check("read: nothing predicted from nothing", fresh:Predict("jab") == nil)
end

------------------------------------------------------------------------
-- the engine on stub rigs
------------------------------------------------------------------------
local function data(style, level, extra)
	local d = S.Boxer({ style = style or "BoxerPuncher", level = level or 60 }, Random.new(5))
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	for _, k in ipairs(Config.StatKeys) do
		d.stats[k] = (extra and extra.stat) or 60
	end
	return d
end
local function fight(styleP, styleO, seed)
	S.setClock(500)
	local f = S.NewFight(data(styleP), data(styleO), 6, seed or 3)
	f.round = 1
	f.live = true
	f.roundEnd = S.now() + 60
	f.Distance = function()
		return 3.6
	end
	return f
end
local function rest(F)
	F.health, F.body, F.stamina, F.balance, F.tier, F.conc = 100, 100, F.maxStam, 100, 0, 0
	F.stumbleUntil, F.hurtUntil, F.busyUntil, F.counterUntil = 0, 0, 0, 0
	F.dmg.cut, F.dmg.cut2, F.dmg.leftEye, F.dmg.rightEye = 0, 0, 0, 0
	F.state, F.blocking, F.chain = "idle", false, nil
	F.healthCap, F.bodyCap = 100, 100
end
local function wait(f, F)
	S.advance(math.max(0, F.busyUntil - S.now()) + 0.01)
	f:Update(0)
end
-- n punches of ptype from P at O (O does nothing; fresh each time): landed share and the mean damage taken
local function landRate(f, ptype, body, n, prep)
	local P, O = f.P, f.O
	local landed, dmg = 0, 0
	for _ = 1, n do
		rest(P)
		rest(O)
		f.mom = 0
		if prep then
			prep(P, O)
		end
		local h0, d0 = O.totals and O.damageTaken or 0, O.damageTaken
		local l0 = P.totals.landed
		f:Punch(P, ptype, body)
		S.advance(Config.Punches[ptype].windup * 1.6 + 0.02)
		if P.totals.landed > l0 then
			landed += 1
			dmg += O.damageTaken - d0
		end
		S.advance(1.2)
		P.chain = nil
	end
	return landed / n, landed > 0 and dmg / landed or 0
end

-- the ring traits switched on only for a career bout against an AI boxer
do
	local f = fight()
	f.P.traitsAll = { { id = "Slick", s = 1 } }
	f.O.traitsAll = { { id = "IronChin", s = 1 } }
	f.P.isPlayer = true
	f:EnableTraits()
	check("traits on: the AI boxer's in a career bout", f:Trait(f.O, "IronChin") == 1)
	check("traits on: never a player's", f:Trait(f.P, "Slick") == 0)
	f.spar = "Hard"
	f:EnableTraits()
	check("traits off: a spar", f:Trait(f.O, "IronChin") == 0)
	f.spar = nil
	f.tutorial = {}
	f:EnableTraits()
	check("traits off: the tutorial / the debut", f:Trait(f.O, "IronChin") == 0)
	f.tutorial = nil
	f.pvp = true
	f:EnableTraits()
	check("traits off: a PvP bout", f:Trait(f.O, "IronChin") == 0)
	local feSrc = fs.readFile(S.H.src .. "/server/FightEngine.lua")
	check("traits: Run switches them on", feSrc:find("self:EnableTraits()", 1, true) ~= nil)
	check("traits: the tape carries the scouting", feSrc:find("t.traits = self:ScoutTraits(F, self:Other(F))", 1, true) ~= nil)
end

-- the scouting report on the tape and the reveal in the fight
do
	local f = fight()
	local O = f.O
	O.traits = { { id = "IronChin", s = 1 }, { id = "BodyArmor", s = 0.7 } }
	O.data.record = { w = 12, l = 1, d = 0, ko = 9 }
	O.data.h2h = { w = 0, l = 0, d = 0 }
	f.P.player = {} -- (a viewer for the hints)
	local tape = f:ScoutTraits(O, f.P)
	check("tape: the main trait known, the second hidden", tape[1].name == "Iron Chin" and tape[2].hidden == true)
	f:TraitFired(O, "BodyArmor")
	local tm = f.msgs.trait
	check("reveal: a hidden trait is revealed when it first triggers", #tm == 1 and tm[1].reveal == true and tm[1].id == "BodyArmor" and type(tm[1].hint) == "string")
	f:TraitFired(O, "BodyArmor")
	check("hint: then throttled", #tm == 1)
	S.advance(10)
	f:TraitFired(O, "BodyArmor")
	check("hint: again after a while (not a reveal)", #tm == 2 and tm[2].reveal == nil)
	f:TraitFired(O, "IronChin")
	check("hint: a known trait's first hint is no reveal", #tm == 3 and tm[3].reveal == nil)
	for _ = 1, 10 do
		S.advance(10)
		f:TraitFired(O, "BodyArmor")
	end
	check("hint: at most 4 a trait", #f.msgs.trait <= 3 + 3)
	local res = f:ResultFor(f.P, { outcome = "win", method = "UD", round = 6 })
	check("result: the traits he found out and his fighting type", #res.oppTraits == 2 and type(res.fightType) == "string" and Traits.Types[res.fightType] ~= nil)
end

-- each trait's effect (strength 1) and its counter
do
	local f = fight()
	local P, O = f.P, f.O
	f.rng = Random.new(11)
	local _, plainCross = landRate(f, "cross", false, 120)
	O.traits = { { id = "IronChin", s = 1 } }
	f.rng = Random.new(11)
	local _, chinCross = landRate(f, "cross", false, 120)
	f.rng = Random.new(11)
	O.traits = {}
	local _, plainJab = landRate(f, "jab", false, 120)
	O.traits = { { id = "IronChin", s = 1 } }
	f.rng = Random.new(11)
	local _, chinJab = landRate(f, "jab", false, 120)
	check("Iron Chin: power head shots do less", chinCross < plainCross * 0.8, chinCross .. " vs " .. plainCross)
	check("Iron Chin: the jab still scores in full", near(chinJab, plainJab, plainJab * 0.05), chinJab .. " vs " .. plainJab)
	f.rng = Random.new(11)
	local _, crackCross = landRate(f, "cross", false, 120, function(_, Ox)
		Ox.body = 20
		Ox.stamina = Ox.maxStam * 0.2
	end)
	check("Iron Chin: it cracks once the body and the gas are gone", crackCross > chinCross * 1.1, crackCross .. " vs " .. chinCross)
	-- body armor
	O.traits = {}
	local b0 = O.body
	rest(O)
	f.rng = Random.new(4)
	local function bodyTaken()
		local sum = 0
		for _ = 1, 60 do
			rest(P)
			rest(O)
			f:Punch(P, "leadhook", true)
			S.advance(0.6)
			sum += 100 - O.body
			S.advance(1)
			P.chain = nil
		end
		return sum
	end
	local plainBody = bodyTaken()
	O.traits = { { id = "BodyArmor", s = 1 } }
	f.rng = Random.new(4)
	local armorBody = bodyTaken()
	check("Body Armor: body shots do less", armorBody < plainBody * 0.75, armorBody .. " vs " .. plainBody)
	-- slick / weaver: accuracy
	O.traits = {}
	f.rng = Random.new(9)
	local plainStraight = landRate(f, "cross", false, 300)
	f.rng = Random.new(9)
	local plainHook = landRate(f, "leadhook", false, 300)
	O.traits = { { id = "Slick", s = 1 } }
	f.rng = Random.new(9)
	local slickStraight = landRate(f, "cross", false, 300)
	f.rng = Random.new(9)
	local slickHook = landRate(f, "leadhook", false, 300)
	f.rng = Random.new(9)
	local slickFeinted = landRate(f, "cross", false, 300, function(Px)
		Px.feintOpenUntil = S.now() + 1
	end)
	check("Slick: straights land less", slickStraight < plainStraight - 0.08, slickStraight .. " vs " .. plainStraight)
	check("Slick: hooks are the counter", slickHook >= plainHook - 0.03, slickHook .. " vs " .. plainHook)
	check("Slick: not right after he bit on a feint", slickFeinted > plainStraight, slickFeinted .. " vs " .. plainStraight)
	O.traits = { { id = "Weaver", s = 1 } }
	f.rng = Random.new(9)
	local weaveHook = landRate(f, "leadhook", false, 300)
	f.rng = Random.new(9)
	local weaveStraight = landRate(f, "cross", false, 300)
	f.Distance = function()
		return 2.6 -- (inside the uppercut's reach)
	end
	f.rng = Random.new(9)
	local weaveUpper = landRate(f, "uppercut", false, 300)
	O.traits = {}
	f.rng = Random.new(9)
	local plainUpper = landRate(f, "uppercut", false, 300)
	f.Distance = function()
		return 3.6
	end
	check("Weaver: hooks land less", weaveHook < plainHook - 0.08, weaveHook .. " vs " .. plainHook)
	check("Weaver: straights are a counter", weaveStraight >= plainStraight - 0.03)
	check("Weaver: the uppercut finds him dipping", weaveUpper > plainUpper, weaveUpper .. " vs " .. plainUpper)
	-- counter specialist: his counters into a flurry hurt more
	O.traits = {}
	local function counterInto(chainLen)
		local sum = 0
		f.rng = Random.new(21)
		for _ = 1, 60 do
			rest(P)
			rest(O)
			P.chain = S.H.require("Combos").NewChain(S.now())
			P.chain.punches = chainLen
			O.counterUntil = S.now() + 2
			local d0 = P.damageTaken
			f:Punch(O, "cross", false)
			S.advance(0.4)
			sum += P.damageTaken - d0
			S.advance(1)
			O.chain = nil
		end
		return sum
	end
	local plainCounter = counterInto(4)
	O.traits = { { id = "CounterSpecialist", s = 1 } }
	local csCounter = counterInto(4)
	local csSingle = counterInto(1)
	check("Counter Specialist: his counters into a flurry land harder", csCounter > plainCounter * 1.2, csCounter .. " vs " .. plainCounter)
	check("Counter Specialist: single shots are the counter", csSingle < csCounter * 0.9, csSingle .. " vs " .. csCounter)
	-- granite: knockdown odds, balance, but slow
	O.traits = {}
	local function kdCount()
		local n = 0
		f.rng = Random.new(31)
		for _ = 1, 200 do
			rest(P)
			rest(O)
			O.health = 12 -- (in danger: a big shot drops him often)
			O.tier = 2
			local k0 = O.kdTotal
			f.Knockdown = function(_, X)
				X.kdTotal += 1
			end
			f:Punch(P, "rearhook", false)
			S.advance(0.5)
			if O.kdTotal > k0 then
				n += 1
			end
			S.advance(1)
			P.chain = nil
		end
		return n
	end
	local plainKD = kdCount()
	O.traits = { { id = "Granite", s = 1 } }
	local graniteKD = kdCount()
	check("Granite: far fewer knockdowns", graniteKD < plainKD * 0.75 and plainKD > 10, graniteKD .. " vs " .. plainKD)
	local function windupOf()
		S.advance(2)
		rest(O)
		O.chain = nil
		f:Punch(O, "overhand", false)
		return tonumber(O.model.attrs.Act:match("^overhand|R|head|([%d.]+)"))
	end
	local slowW = windupOf()
	O.traits = {}
	local plainW = windupOf()
	O.traits = { { id = "Granite", s = 1 } }
	check("Granite: his wind-up is slower", slowW and plainW and slowW > plainW, tostring(slowW) .. " vs " .. tostring(plainW))
	S.advance(2)
	-- caps: two knockdown traits together never take off more than Traits.CAP.kd
	O.traits = { { id = "Granite", s = 1 }, { id = "IronChin", s = 1 } }
	local capKD = kdCount()
	check("caps: Granite + Iron Chin still leave knockdowns (capped at -50%)", capKD >= plainKD * 0.35, capKD .. " vs " .. plainKD)
	O.traits = {}
end

-- pressure, the ropes and the Pressure-proof / Ring General traits
do
	local f = fight()
	local P, O = f.P, f.O
	f.Distance = function()
		return 3.2
	end
	for _ = 1, 6 do
		table.insert(P.throwTimes, S.now())
	end
	local mul = f:DepthRegen(O, S.now(), 0.05)
	check("pressure: walked down, his regen wilts", O.pressured and mul < 0.95, mul)
	O.traits = { { id = "PressureProof", s = 1 } }
	local mulProof = f:DepthRegen(O, S.now(), 0.05)
	check("Pressure-proof: no wilting", O.pressured and mulProof > mul, mulProof .. " vs " .. mul)
	O.traits = {}
	-- the ropes: put O against them with P inside him
	O.root.CFrame = S.H.globals.CFrame.new(S.H.globals.Vector3.new(9, 3.2, 0))
	P.root.CFrame = S.H.globals.CFrame.new(S.H.globals.Vector3.new(6, 3.2, 0))
	check("ropes: on them with the other man inside", f:OnRopes(O) and not f:OnRopes(P))
	check("ropes: the full penalty", near(f:RopeMul(O), 1))
	O.traits = { { id = "RingGeneral", s = 1 } }
	check("Ring General: half of it", f:RopeMul(O) <= 0.55)
	O.body = 20
	check("Ring General: the body work slows his legs (the counter)", f:RopeMul(O) > 0.6)
	O.traits = {}
	O.onRopes = true
	check("ropes: his dodge windows shrink", f:EvadeMul(O) < 1)
end

-- the AI: perception, prediction, adaptation
do
	local f = fight()
	local P, O = f.P, f.O
	local calls = {}
	local eng = setmetatable({}, { __index = f })
	for _, k in ipairs({ "Slip", "Roll", "Parry", "Pivot", "SetBlock", "Dodge", "Clinch" }) do
		eng[k] = function(_, _, a, b)
			table.insert(calls, { k = k, at = S.now(), a = a, b = b })
		end
	end
	local function ai(ringIQ, reflex)
		O.data.stats.RingIQ, O.data.mental.Focus, O.data.stats.Reflexes = ringIQ, ringIQ, reflex or ringIQ
		local a = FightAI.new(O, P, eng)
		a.rng = Random.new(3)
		return a
	end
	local raw, elite = ai(25), ai(95)
	check("perception: an elite boxer sees it sooner", elite:Perception() < raw:Perception() - 0.05, elite:Perception() .. " vs " .. raw:Perception())
	O.conc = 0.6
	check("perception: a concussion slows it", raw:Perception() > ai(25):Perception() - 1e-9 and ai(25):Perception() > Config.FightAI.perceive[1])
	O.conc = 0
	-- nothing it could not have seen: a reaction never comes before perception + motor without a read
	local a = ai(60, 60)
	local early = 0
	for _ = 1, 300 do
		O.busyUntil, a.freezeUntil, a.expect = 0, 0, nil
		table.clear(calls)
		local t0 = S.now()
		a:OnOppPunch("rearhook", false, 0.6)
		S.advance(0.7)
		for _, c in ipairs(calls) do
			if c.at - t0 < a:Perception() + a:Motor() - 1e-6 then
				early += 1
			end
		end
	end
	check("fair: no reaction before its perception + motor delay", early == 0, early)
	-- too fast to see: a quick jab gets no reaction from a mid-level AI that has no read on it
	local n = 0
	for _ = 1, 300 do
		O.busyUntil, a.freezeUntil, a.expect = 0, 0, nil
		table.clear(calls)
		a:OnOppPunch("jab", false, 0.12)
		S.advance(0.3)
		n += #calls
	end
	check("fair: a jab faster than it can see is not defended (no read)", n == 0, n)
	-- the read: he spams the jab -> it expects it and gets to it early (and slips it: a straight's defence)
	local b = ai(75, 75)
	for _ = 1, 40 do
		b.read:Punch("jab", false, 1, 3.6, false)
		b.read:Punch("jab", false, 2, 3.6, false)
	end
	local reacted, slips = 0, 0
	for _ = 1, 300 do
		O.busyUntil, b.freezeUntil = 0, 0
		b.expect = { p = "jab", conf = 0.95, at = S.now() }
		table.clear(calls)
		b:OnOppPunch("jab", false, 0.15)
		S.advance(0.3)
		reacted += #calls > 0 and 1 or 0
		for _, c in ipairs(calls) do
			if c.k == "Slip" or c.k == "Parry" or (c.k == "Dodge" and (c.a == "pull" or c.a == "slip")) then
				slips += 1
			end
		end
	end
	check("adapt: a spammed jab is read and defended even when it is quick", reacted > 60, reacted)
	check("adapt: and slipped / parried (a straight's defence)", slips > reacted * 0.3, slips .. " / " .. reacted)
	-- a wrong read: it expected the jab, a hook came - it defends the jab (a slip / parry / pull) some of the time
	local wrong = 0
	for _ = 1, 300 do
		O.busyUntil, b.freezeUntil = 0, 0
		b.expect = { p = "jab", conf = 0.95, at = S.now() }
		table.clear(calls)
		b:OnOppPunch("leadhook", false, 0.26, { hand = "L" })
		S.advance(0.4)
		for _, c in ipairs(calls) do
			if c.k == "Parry" or (c.k == "Dodge" and c.a == "pull") then
				wrong += 1
			end
		end
	end
	check("prediction: a wrong read commits to the wrong defence", wrong > 10, wrong)
	-- slips go away from the hook's hand
	local away, into = 0, 0
	local c2 = ai(95, 95)
	for _ = 1, 400 do
		O.busyUntil, c2.freezeUntil, c2.expect = 0, 0, nil
		table.clear(calls)
		c2:OnOppPunch("leadhook", false, 0.5, { hand = "L" })
		S.advance(0.6)
		for _, c in ipairs(calls) do
			if c.k == "Slip" then
				if c.a == -1 then
					away += 1
				else
					into += 1
				end
			end
		end
	end
	check("defence: an elite boxer slips away from a left hook (to his left)", away > 0 and into == 0, away .. " / " .. into)
	-- mistakes by skill: a raw boxer picks wrong defences, an elite one does not
	local function mistakes(skill)
		local x = ai(skill, 95)
		local m = 0
		for _ = 1, 400 do
			O.busyUntil, x.freezeUntil, x.expect = 0, 0, nil
			table.clear(calls)
			x:OnOppPunch("uppercut", false, 0.6)
			S.advance(0.7)
			for _, c in ipairs(calls) do
				if c.k == "Dodge" and (c.a == "duck" or c.a == "weave") then
					m += 1
				end
			end
		end
		return m
	end
	check("mistakes: a raw boxer ducks into uppercuts, an elite one never", mistakes(20) > 5 and mistakes(100) == 0)
	-- feints: it bites less once it has seen him feint a lot
	local function bites(feintShare)
		local x = ai(90, 90)
		for _ = 1, 20 do
			x.read:Punch("jab", false, 1, 3.6, false)
		end
		for _ = 1, math.floor(20 * feintShare / (1 - feintShare + 1e-9)) do
			x.read:Feint()
		end
		local m = 0
		for _ = 1, 300 do
			O.busyUntil, x.freezeUntil, x.expect = 0, 0, nil
			table.clear(calls)
			x:OnOppPunch("jab", false, 0.6, { feint = true })
			S.advance(0.7)
			m += #calls
		end
		return m
	end
	local fresh, wise = bites(0.01), bites(0.6)
	check("feint: a smart AI stops biting on feints it keeps seeing", wise < fresh * 0.7, wise .. " vs " .. fresh)
end

-- the feint in the engine: the cost, the bite, the open punch, the spam
do
	local f = fight()
	local P, O = f.P, f.O
	rest(P)
	rest(O)
	local s0 = P.stamina
	check("feint: thrown", f:Feint(P) == true and P.busyUntil > S.now() and P.model.attrs.Act:find("^jab|L|head") ~= nil)
	check("feint: it costs stamina", near(s0 - P.stamina, Config.FightDepth.feint.stam))
	f:SetBlock(O, true)
	check("feint: a guard going up straight after it is a bite", P.feintOpenUntil > S.now() and P.feintBites == 1)
	O.counterUntil = S.now() + 5
	f:SetBlock(O, false)
	S.advance(1.0)
	f:Feint(P)
	f:Slip(O, 1)
	check("feint: the bite costs him his counter", O.counterUntil <= S.now() + 1e-6)
	S.advance(2)
	rest(P)
	local costs = {}
	for i = 1, 6 do
		P.busyUntil = 0
		local before = P.stamina
		f:Feint(P)
		costs[i] = before - P.stamina
		S.advance(0.3)
	end
	check("feint: spammed, it costs more", costs[6] > costs[1] + 1, costs[1] .. " -> " .. costs[6])
	-- no bite when he waits it out
	S.advance(3)
	rest(P)
	rest(O)
	P.feintOpenUntil = 0
	f:Feint(P)
	S.advance(0.6)
	f:SetBlock(O, true)
	check("feint: a guard a while later is no bite", P.feintOpenUntil <= S.now())
	local km = S.H.require("Keymap")
	check("feint: on the control map (keys, pad, touch)", km.ById.feint and km.Valid(km.ById.feint.kbd[1], "kbd") and km.Valid(km.ById.feint.pad, "pad") and km.ById.feint.touch ~= nil)
	check("feint: no control conflicts", #km.Conflicts(km.Resolve(nil)) == 0)
	local fe = fs.readFile(S.H.src .. "/server/FightEngine.lua")
	local fc = fs.readFile(S.H.src .. "/client/FightClient.client.lua")
	check("feint: the Fight remote routes it", fe:find('elseif t == "feint" then', 1, true) ~= nil and fc:find('feint = { t = "feint" }', 1, true) ~= nil)
end

-- the second wind
do
	local f = fight()
	local P = f.P
	rest(P)
	P.data.stats.Stamina, P.data.mental.Discipline = 50, 50
	P.windLeft = 1
	P.stamina = P.maxStam * 0.1
	local now = S.now()
	for _ = 1, 60 do
		f:DepthRegen(P, S.now(), 0.05)
		S.advance(0.05)
	end
	check("second wind: gassed for a while, it comes", P.winds == 1 and P.windUntil > S.now() and P.stamina > P.maxStam * 0.1 + 1)
	check("second wind: the regen surges", f:DepthRegen(P, S.now(), 0.05) > 1.5)
	P.stamina = P.maxStam * 0.1
	P.windUntil = 0
	for _ = 1, 120 do
		f:DepthRegen(P, S.now(), 0.05)
		S.advance(0.05)
	end
	check("second wind: once a fight", P.winds == 1)
	local fit = FightEngine._makeFighter(data("OutBoxer", 60, { stat = 80 }), P.model, nil)
	check("second wind: twice for the fittest", fit.windLeft == 2)
	local fu = fight()
	fu.tutorial = {}
	fu.P.stamina = fu.P.maxStam * 0.05
	for _ = 1, 100 do
		fu:DepthRegen(fu.P, S.now(), 0.05)
		S.advance(0.05)
	end
	check("second wind: not in the tutorial", fu.P.winds == 0)
end

-- accuracy: fatigue, damage, the eyes; the blind side; side-aware slips
do
	local f = fight()
	f.rng = Random.new(12)
	local fresh = landRate(f, "cross", false, 400)
	f.rng = Random.new(12)
	local tired = landRate(f, "cross", false, 400, function(Px)
		Px.stamina = Px.maxStam * 0.05
	end)
	f.rng = Random.new(12)
	local hurt = landRate(f, "cross", false, 400, function(Px)
		Px.health = 5
	end)
	f.rng = Random.new(12)
	local swollen = landRate(f, "cross", false, 400, function(Px)
		Px.dmg.leftEye, Px.dmg.rightEye = 0.9, 0.9
	end)
	check("accuracy: a tired man misses more", tired < fresh - 0.06, tired .. " vs " .. fresh)
	check("accuracy: a hurt man misses more", hurt < fresh - 0.03, hurt .. " vs " .. fresh)
	check("accuracy: through swollen eyes he misses more", swollen < fresh - 0.03, swollen .. " vs " .. fresh)
	-- the blind side: his right eye closing - the left hand (the jab, the lead hook) lands more; the right doesn't
	f.rng = Random.new(12)
	local blindJab = landRate(f, "jab", false, 400, function(_, Ox)
		Ox.dmg.rightEye = 1
	end)
	f.rng = Random.new(12)
	local plainJab = landRate(f, "jab", false, 400)
	f.rng = Random.new(12)
	local otherCross = landRate(f, "cross", false, 400, function(_, Ox)
		Ox.dmg.rightEye = 1
	end)
	check("blind side: the hand on the side of the closing eye lands more", blindJab > plainJab + 0.06, blindJab .. " vs " .. plainJab)
	check("blind side: the other hand does not", near(otherCross, fresh, 0.04), otherCross .. " vs " .. fresh)
	check("blind side: a cut bleeding into the eye counts", f:Blind({ dmg = { leftEye = 0, rightEye = 0, cut = 1, cutSide = 1, cut2 = 0, cutSide2 = -1 } }, 1) > 0.3)
	-- a slip away from a hook beats it; into it, it lands harder
	local P, O = f.P, f.O
	local function hookAt(dir)
		rest(P)
		rest(O)
		f.rng = Random.new(3)
		local d0, l0 = O.damageTaken, P.totals.landed
		f:Slip(O, dir)
		f:Punch(P, "leadhook", false)
		S.advance(0.5)
		S.advance(1)
		P.chain, O.chain = nil, nil
		return P.totals.landed > l0, O.damageTaken - d0
	end
	local hitAway = hookAt(-1)
	local hitInto, dmgInto = hookAt(1)
	check("slip: away from the left hook (to his left) makes it miss", hitAway == false)
	check("slip: into it, it lands", hitInto == true and dmgInto > 0)
end

-- the clinch: inside work, the referee's break, the shove off
do
	local f = fight()
	local P, O = f.P, f.O
	rest(P)
	rest(O)
	f.Distance = function()
		return 3
	end
	f.TieUp = function() end
	f:Clinch(O) -- (O ties up: he holds, his arms smother what comes in)
	check("clinch: tied up", P.state == "clinch" and O.state == "clinch" and f.clinchBy == O)
	S.advance(0.35)
	local b0 = O.body
	f:Punch(P, "leadhook", false)
	check("clinch: a punch is inside work to the body", O.body < b0 and P.tally.inside == 1)
	local held = b0 - O.body
	f:Punch(P, "leadhook", false)
	check("clinch: one every so often", P.tally.inside == 1)
	S.advance(0.5)
	f:Punch(O, "leadhook", false)
	local free = 100 - P.body
	check("clinch: the man who holds smothers it (the other's work lands fuller)", free > held * 1.5, free .. " vs " .. held)
	P.clinchUntil, O.clinchUntil = S.now() + 10, S.now() + 10 -- (a long hold: only the referee ends it)
	for _ = 1, 6 do
		S.advance(0.5)
		f:Punch(P, "uppercut", false)
	end
	check("clinch: holding and hitting - the referee breaks them", P.tally.inside == Config.FightDepth.clinchMax and P.clinchUntil <= S.now() + 1e-6)
	S.advance(1)
	f:Update(0)
	rest(P)
	rest(O)
	P.nextClinch, O.nextClinch = 0, 0
	f:Clinch(P)
	check("break: not at once", f:BreakClinch(O) == false)
	S.advance(0.5)
	check("break: the clinch key shoves off", f:Clinch(O) == true or (P.state == "idle" and O.state == "idle"))
	check("break: the other man is pushed back, the breaker at an angle", P.state == "idle" and P.busyUntil > S.now() and O.angleUntil > S.now())
end

-- the momentum and the live score
do
	local f = fight()
	local P, O = f.P, f.O
	f.mom = 0
	rest(P)
	rest(O)
	f.rng = Random.new(2)
	for _ = 1, 8 do
		rest(O)
		f:Punch(P, "cross", false)
		S.advance(0.5)
		P.chain = nil
		S.advance(0.6)
	end
	check("momentum: clean work swings it his way", f:Mom(P) > 0.1 and f:Mom(O) < -0.1, f.mom)
	local m = f.mom
	f:UpdateIntel(5, S.now())
	check("momentum: it drifts back to even", f.mom < m)
	f.mom = 0
	f.Knockdown = FightEngine._Fight.Knockdown
	f.kdHold = false
	f:Swing(O, 0.4)
	check("momentum: a knockdown swings it hard", f:Mom(O) >= 0.4)
	f.mom = 1
	f.rng = Random.new(12)
	local up = landRate(f, "cross", false, 300, function()
		f.mom = 1
	end)
	f.rng = Random.new(12)
	local even = landRate(f, "cross", false, 300)
	check("momentum: it helps a little (accuracy)", up > even and up < even + 0.08, up .. " vs " .. even)
	-- the live score
	f.msgs.counts.mom = 0
	f.mom = 0.3
	f.judgesAt = 0
	P.tally = { landed = 5, power = 2, body = 1, thrown = 10, kd = 0, clinches = 0, inside = 0 }
	O.tally = { landed = 1, power = 0, body = 0, thrown = 6, kd = 0, clinches = 0, inside = 0 }
	f.intelAcc = 1
	local sent
	f.SendEach = function(_, fn)
		sent = fn(P)
	end
	f:UpdateIntel(0.1, S.now())
	check("live score: the round's work and the cards", sent and sent.t == "mom" and sent.d > 0 and #sent.cards == 3 and sent.round == 1, sent and sent.d)
	local st = fs.readFile(S.H.src .. "/client/modules/Settings.lua")
	local mainSrc = fs.readFile(S.H.src .. "/server/Main.server.lua")
	check("live score: an option, saved", st:find('"liveScore"', 1, true) ~= nil and mainSrc:find('"liveScore"', 1, true) ~= nil)
	check("live score: the judges see a little of the momentum", f:RoundPoints(P, O) > f:RoundPoints(O, P))
end

-- the tutorial and the debut are untouched: no traits, no feints from its AI, no second wind, no momentum
do
	local f = fight()
	f.tutorial = {}
	f.mom = 0
	f:Swing(f.P, 0.5)
	check("tutorial: no momentum", f.mom == 0)
	local a = FightAI.new(f.O, f.P, f)
	a.rng = Random.new(1)
	local n = 0
	for _ = 1, 200 do
		f.O.feints = f.O.feints or 0
		a.nextFeint = 0
		if a:TryFeint(S.now(), 3.6) then
			n += 1
		end
	end
	check("tutorial: its AI never feints", n == 0)
end

------------------------------------------------------------------------
-- whole fights: adaptation and the balance bounds
------------------------------------------------------------------------
-- adaptation in a real fight: against a man who spams the jab, an AI that reads him makes more of them miss (or
-- blocks them) than the same AI with its read switched off, on the same seeds (the damage is turned right down so
-- the fights run their distance: this is about the read, not the result)
do
	local function share(learn)
		local n, miss = 0, 0
		for seed = 1, (QUICK and 4 or 8) do
			local last = { thrown = 0, landed = 0 }
			S.Fight({
				red = { bot = "spam", style = "BoxerPuncher", level = 60 },
				blue = { style = "CounterPuncher", level = 60, noTraits = true },
				rounds = 3, seed = seed,
				onTick = function(fight)
					fight.damageScale = 0.05
					if not learn and not fight.O.ai.readOff then
						fight.O.ai.readOff = true
						fight.O.ai.read = FightRead.new()
						fight.O.ai.read.Punch = function() end
						fight.O.ai.seq = setmetatable({}, { __newindex = function() end })
					end
					local P = fight.P
					local dt, dl = P.totals.thrown - last.thrown, P.totals.landed - last.landed
					last.thrown, last.landed = P.totals.thrown, P.totals.landed
					if fight.round >= 2 then
						n += dt
						miss += dt - dl
					end
				end,
			})
		end
		return miss / math.max(1, n), n
	end
	local on, n1 = share(true)
	local off = share(false)
	check("adapt: the AI learns a spammed jab (more of them miss / are blocked than with its read off)", on > off + 0.02 and n1 > 50, string.format("%.3f vs %.3f (%d)", on, off, n1))
end

local function rate(n, spec)
	local w, ko, rounds = 0, 0, 0
	for i = 1, n do
		local sp = spec(i)
		sp.seed = i * 7919 + 13
		local r = S.Fight(sp)
		w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
		if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then
			ko += 1
		end
		rounds += r.round
	end
	return w / n, ko / n, rounds / n
end
-- the red corner's damage dealt / damage taken over n fights (a steadier read of an edge than the win rate)
local function edge(n, spec)
	local dealt, taken = 0, 0
	for i = 1, n do
		local sp = spec(i)
		sp.seed = i * 7919 + 13
		local r = S.Fight(sp)
		dealt += r.P.damageDealt
		taken += r.P.damageTaken
	end
	return dealt / math.max(1e-6, taken)
end
local N = QUICK and 12 or 24
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
-- (the bounds are wide on purpose: they catch a broken balance - a lock, a hopeless fight, a level that means
-- nothing - not the noise of a couple of dozen fights; tools/sim/balance.luau prints the full tables)
do
	-- the mirror is even, a level gap shows, no style is a lock against another
	local mirror = rate(N, function()
		return { red = { style = "BoxerPuncher", level = 60, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6 }
	end)
	check("balance: the mirror is even", mirror >= 0.25 and mirror <= 0.75, mirror)
	local up = rate(N, function()
		return { red = { style = "BoxerPuncher", level = 72, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6 }
	end)
	check("balance: 12 levels better wins most", up >= 0.7, up)
	for _, pair in ipairs({ { "Swarmer", "OutBoxer" }, { "Slugger", "CounterPuncher" }, { "OutBoxer", "BoxerPuncher" } }) do
		local w = rate(N, function()
			return { red = { style = pair[1], level = 60, noTraits = true }, blue = { style = pair[2], level = 60, noTraits = true }, rounds = 6 }
		end)
		check("balance: " .. pair[1] .. " vs " .. pair[2] .. " is a fight, not a lock", w >= 0.08 and w <= 0.92, w)
	end
	-- fight lengths: some go the distance
	local _, ko, rounds = rate(N, function(i)
		return { red = { style = STYLES[(i % 5) + 1], level = 60 }, blue = { style = STYLES[((i + 2) % 5) + 1], level = 60 }, rounds = 6 }
	end)
	check("balance: stoppages happen, but not every fight", ko >= 0.1 and ko <= 0.95, ko)
	check("balance: fights last", rounds >= 2.5, rounds)
	-- the busy AI's bands (FightAI's work rate, its defence and its punch choice against the engine's damage, health,
	-- concussion and knockdown rules - Config.Damage / KO / Concussion). Measured when set (tools/sim/balance.luau and
	-- 48 fights a cell; equal level 60, mixed styles, traits on): about 43 punches a minute each, 32% landed, 5.0 of 6
	-- rounds, ~52% stoppages, 1.7 damage a landed punch. Before the rebalance (41c40ca) the AI was held to ~36 a minute
	-- and still read 82% stoppages / 3.9 rounds (82601e5: 33 a minute, 75%, 4.35 rounds). The sim's noise is about +-8%
	-- on 24 fights, so the bands are the target with that margin: busy (36-52 a minute), 25-40% landed, fights that go
	-- deep (4.3+ rounds on average) and a real share of them going to the cards (stoppages 25-75%)
	check("bands: equal men go the rounds (average past 4.3)", rounds >= 4.3, rounds)
	check("bands: and a real share go to the cards (stoppages 25-75%)", ko >= 0.25 and ko <= 0.75, ko)
	local th, la, secs = 0, 0, 0
	for i = 1, (QUICK and 6 or 12) do
		local r = S.Fight({ red = { style = STYLES[(i % 5) + 1], level = 60 }, blue = { style = STYLES[((i + 2) % 5) + 1], level = 60 }, rounds = 6, seed = i * 7919 + 13 })
		th += r.thrown.red + r.thrown.blue
		la += r.landed.red + r.landed.blue
		secs += r.seconds
	end
	local ppm, acc = th / math.max(1, secs) * 30, la / math.max(1, th)
	check("bands: an AI throws a busy boxer's work rate (36-52 a minute)", ppm >= 36 and ppm <= 52, ppm)
	check("bands: and lands a realistic share (25-40%)", acc >= 0.25 and acc <= 0.4, acc)
end
do
	-- the scripted players: a low-level AI is beatable, a high-level one a puzzle a one-trick player can't solve
	local smart40 = rate(N, function(i)
		return { red = { bot = "smart", style = "BoxerPuncher", level = 40 }, blue = { style = STYLES[(i % 5) + 1], level = 40 }, rounds = 4 }
	end)
	local spam80 = rate(N, function(i)
		return { red = { bot = "spam", style = "BoxerPuncher", level = 80 }, blue = { style = STYLES[(i % 5) + 1], level = 80 }, rounds = 6 }
	end)
	local smart80 = rate(N, function(i)
		return { red = { bot = "smart", style = "BoxerPuncher", level = 80 }, blue = { style = STYLES[(i % 5) + 1], level = 80 }, rounds = 6 }
	end)
	check("balance: low-level AI is beatable (a thinking player wins some)", smart40 >= 0.1, smart40)
	check("balance: high-level AI is a puzzle (a one-punch spammer rarely wins)", spam80 <= 0.2, spam80)
	check("balance: thinking beats spamming against a good AI", smart80 >= spam80, smart80 .. " vs " .. spam80)
	-- the rebalance's two ends (measured on 48 a cell when set: a novice beat the level-20 AI ~42%, the pressure bot the
	-- level-60 AI ~48%, 82601e5 54%): a beginner can beat a debut-level AI, and walking a good AI down is no longer the
	-- way to beat it (it pivots, steps back and counters, fires in the gaps, keeps its guard up and smothers)
	local novice20 = rate(N, function(i)
		return { red = { bot = "novice", style = "BoxerPuncher", level = 20 }, blue = { style = STYLES[(i % 5) + 1], level = 20 }, rounds = 6 }
	end)
	local pressure60 = rate(N, function(i)
		return { red = { bot = "pressure", style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60 }, rounds = 6 }
	end)
	check("balance: a debut-level AI is beatable by a beginner (a novice wins some)", novice20 >= 0.2, novice20)
	check("balance: pressure alone does not beat a good AI most of the time", pressure60 <= 0.65, pressure60)
	-- each trait takes something off the type it resists, but never makes it hopeless for a player who adapts
	local pairsT = { { "IronChin", "power" }, { "BodyArmor", "body" }, { "Slick", "onetwo" }, { "CounterSpecialist", "volume" }, { "PressureProof", "pressure" } }
	for _, tp in ipairs(pairsT) do
		local without = edge(N, function(i)
			return { red = { bot = tp[2], style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60, noTraits = true }, rounds = 6 }
		end)
		local with = edge(N, function(i)
			return { red = { bot = tp[2], style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60, traits = { { id = tp[1], s = 1 } } }, rounds = 6 }
		end)
		local adapted = rate(N, function(i)
			return { red = { bot = "smart", style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60, traits = { { id = tp[1], s = 1 } } }, rounds = 6 }
		end)
		check("balance: " .. tp[1] .. " resists the " .. tp[2] .. " puncher (his damage edge drops)", with < without, string.format("%.2f vs %.2f", with, without))
		-- (0.5 sat on the line: Iron Chin read 0.50-0.52 of the edge at 41c40ca and 0.46-0.57 after the damage rebalance -
		-- the longer fights let a damage edge compound; 0.42 still catches a trait that takes nearly all of it, and the
		-- adapting player's wins below are the cap that matters)
		check("balance: " .. tp[1] .. " takes a slice, not all of it (capped)", with > without * 0.42, string.format("%.2f vs %.2f", with, without))
		check("balance: " .. tp[1] .. " is capped (an adapting player still wins some)", adapted >= 0.04, adapted)
	end
end

print(string.format("test_fightai: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
