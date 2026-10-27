--!nocheck
-- tools/sim/test_moves.luau: the special moves (src/shared/Moves.lua) and their fight milestones under lune.
--   * data: every move in Moves.List has its Moves.Data entry (the fields FightEngine / FightAI / FightClient
--     read), a FightMotion.Specials schedule with one punch per Moves.Data punch (same hands, same zones),
--     an AnimFight.SPECIAL_ANIM entry whose variant the punch knows, a Keymap action (no default conflicts),
--     numbers inside the existing moves' envelope; every move has a fight milestone, the fight moves only that
--   * unlock math: Moves.Info from a profile / a client summary / an old or dirty save (records summed over
--     the amateur and pro records, KOs never above wins), the ladder (3 bouts, 8 bouts, 15 wins, 25 bouts,
--     5 KO wins), the older moves' fight milestone as an OR with style / tier / training, UnlockedBy's words
--   * UnlockText: the conditions, and with info the progress ("Win 15 fights (9/15)")
--   * Moves.ForAI: amateurs none, the fight moves by aiTier and record, the older moves by style / tier only
--   lune run tools/sim/test_moves.luau
local Host = require("./host")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local H = Host.new()
local Moves = H.require("Moves")
local FM = H.require("FightMotion")
local Config = H.require("Config")
local Keymap = H.require("Keymap")
local okAF, AnimFight = pcall(H.require, "AnimFight")
check("AnimFight loads", okAF, AnimFight)

local FIGHT_MOVES = { "doublejab", "feintcross", "bodyhead", "onetwothree", "shovelhook" }
local OLD_MOVES = { "checkhook", "phillyshell", "pullcounter", "livershot", "gazelle", "peekaboo", "stepback", "overhand", "leaduppercut" }

------------------------------------------------------------------------
-- data
------------------------------------------------------------------------
check("14 moves", #Moves.List == 14, #Moves.List)
for _, id in ipairs(FIGHT_MOVES) do
	check("listed " .. id, table.find(Moves.List, id) ~= nil)
end
for _, id in ipairs(OLD_MOVES) do
	check("still listed " .. id, table.find(Moves.List, id) ~= nil)
end
local seen = {}
for i, id in ipairs(Moves.List) do
	check("unique " .. id, not seen[id])
	seen[id] = true
	check("Index " .. id, Moves.Index(id) == i)
end
for id in pairs(Moves.Data) do
	check("data is listed " .. id, seen[id] == true)
end

local function num(v, lo, hi)
	return type(v) == "number" and v == v and v >= lo and v <= hi
end
local STATS = { fights = true, wins = true, kos = true }
for _, id in ipairs(Moves.List) do
	local M = Moves.Data[id]
	local tag = id .. ": "
	check(tag .. "data", type(M) == "table")
	if type(M) ~= "table" then
		continue
	end
	check(tag .. "id", M.id == id and Moves.Id(id) == id)
	check(tag .. "name", type(M.name) == "string" and #M.name > 0 and type(M.short) == "string" and #M.short > 0)
	check(tag .. "desc / how", type(M.desc) == "string" and #M.desc > 20 and type(M.how) == "string" and #M.how > 20)
	check(tag .. "hand", M.hand == "L" or M.hand == "R")
	check(tag .. "punches", type(M.punch) == "table" and #M.punch >= 1 and #M.punch <= 3, M.punch and #M.punch)
	for i, p in ipairs(M.punch) do
		check(tag .. "punch kind " .. i, Config.Punches[p] ~= nil, p)
	end
	if M.hands then
		check(tag .. "hands per punch", #M.hands == #M.punch)
		check(tag .. "first hand", M.hands[1] == M.hand)
	end
	if M.bodies then
		check(tag .. "bodies per punch", #M.bodies == #M.punch)
	end
	-- the envelope of the original nine (a fight move must not outclass them)
	check(tag .. "stam", num(M.stam, 4, 14), M.stam)
	check(tag .. "dmg", num(M.dmg, 0.85, 1.35), M.dmg)
	check(tag .. "hit", num(M.hit, -0.06, 0.12), M.hit)
	check(tag .. "range", num(M.range, 0.8, 1.5), M.range)
	check(tag .. "kd", num(M.kd, 0.9, 1.35), M.kd)
	check(tag .. "power", num(M.power, 0.85, 1.25), M.power)
	check(tag .. "cooldown", num(M.cooldown, 1.3, 3), M.cooldown)
	check(tag .. "styles table", type(M.styles) == "table")
	for _, s in ipairs(M.styles) do
		check(tag .. "style " .. tostring(s), Config.FindById(Config.Styles, s) ~= nil)
	end
	if M.training then
		check(tag .. "training", Config.FindById(Config.Activities, M.training.activity) ~= nil and num(M.training.sessions, 1, 100))
	end
	-- every move opens by fighting
	check(tag .. "fight milestone", type(M.fight) == "table" and STATS[M.fight.stat] == true and num(M.fight.n, 1, 60), M.fight and M.fight.stat)

	-- FightMotion: the schedule the server lands the punches on and the Animator throws them on
	local sp = FM.Specials[id]
	check(tag .. "FightMotion.Specials", sp ~= nil)
	if sp then
		check(tag .. "motion hand", sp.hand == M.hand)
		check(tag .. "motion punches", #sp.punches == #M.punch, #sp.punches)
		check(tag .. "motion move = lunge", math.abs((sp.move or 0) - (M.lunge or 0)) < 1e-6, sp.move)
		local fallback = M.hand
		for i, pu in ipairs(sp.punches) do
			-- the animated punch is the scored one (the engine scores M.punch[i]; the Animator throws pu.kind)
			check(tag .. "motion kind " .. i, pu.kind == M.punch[i], pu.kind)
			-- the engine's hand: hands[i], else alternating from M.hand; the Animator's: pu.hand or the move's
			local engineHand = (M.hands and M.hands[i]) or ((i % 2 == 0) and (M.hand == "L" and "R" or "L") or M.hand)
			check(tag .. "motion hand " .. i, (pu.hand or fallback) == engineHand, pu.hand)
			local body = M.bodies and M.bodies[i]
			if body == nil then
				body = M.body == true
			end
			check(tag .. "motion zone " .. i, ((pu.zone or sp.zone) == "body") == body, pu.zone or sp.zone)
		end
		for _, w in ipairs({ 0.16, 0.24, 0.42 }) do
			local hits = FM.SpecialHits(id, w)
			check(tag .. "hits " .. w, #hits == #M.punch)
			for i = 2, #hits do
				check(tag .. "hits in order " .. i, hits[i] > hits[i - 1] + 0.05, hits[i] - hits[i - 1])
			end
			check(tag .. "move length", FM.SpecialDuration(id, w) > hits[#hits])
			check(tag .. "move under 2.5 s", FM.SpecialDuration(id, w) < 2.5 + (id == "checkhook" and 1.1 or 0), FM.SpecialDuration(id, w))
		end
	end
	-- AnimFight: the set-up and a punch variant its punch kind knows
	if okAF then
		local anim = AnimFight.SPECIAL_ANIM[id]
		check(tag .. "SPECIAL_ANIM", anim ~= nil)
		local KNOWN = {
			jab = { snap = 1, step = 1, paw = 1, long = 1 }, cross = { standard = 1, long = 1, dip = 1, counter = 1 },
			leadhook = { tight = 1, wide = 1, check = 1 }, rearhook = { tight = 1, wide = 1 },
			uppercut = { short = 1, dipping = 1 }, overhand = { looping = 1, dipping = 1 },
		}
		if anim and anim.variant then
			check(tag .. "variant " .. anim.variant, KNOWN[M.punch[1]] and KNOWN[M.punch[1]][anim.variant] == 1)
		end
	end
	-- Keymap: a remappable action for it
	local a = Keymap.ById["special_" .. id]
	check(tag .. "keymap action", a ~= nil and a.special == id and a.section == "special")
	if a then
		check(tag .. "kbd valid", Keymap.Valid(a.kbd[1], "kbd"), a.kbd[1])
		check(tag .. "pad valid", Keymap.Valid(a.pad, "pad"), a.pad)
		check(tag .. "touch name", type(a.touch) == "string" and #a.touch <= 8, a.touch)
	end
end
check("default keymap: no conflicts", #Keymap.Conflicts(Keymap.Default()) == 0, #Keymap.Conflicts(Keymap.Default()))

for _, id in ipairs(FIGHT_MOVES) do
	local M = Moves.Data[id]
	check(id .. ": fight move only", #M.styles == 0 and M.tier == nil and M.anyTier == nil and M.training == nil)
	check(id .. ": aiTier", num(M.aiTier, 2, 10))
end
-- the specific shapes
check("double jab: two lefts", Moves.Data.doublejab.hands[1] == "L" and Moves.Data.doublejab.hands[2] == "L" and Moves.Data.doublejab.punch[2] == "jab")
check("body-head: low then high", Moves.Data.bodyhead.bodies[1] == true and Moves.Data.bodyhead.bodies[2] == false)
check("1-2-3: jab cross hook", table.concat(Moves.Data.onetwothree.punch, ",") == "jab,cross,leadhook")
check("shovel hook: the KO move", Moves.Data.shovelhook.fight.stat == "kos" and Moves.Data.shovelhook.kd >= 1.25)

------------------------------------------------------------------------
-- unlock math
------------------------------------------------------------------------
local function rec(w, l, d, ko)
	return { w = w, l = l or 0, d = d or 0, ko = ko or 0 }
end
-- a profile as the server holds it (style id, tier, records, the two fight records)
local function profile(t)
	return {
		style = t.style or "OutBoxer", tier = t.tier or 1, records = t.records or {},
		amateurRecord = t.am or rec(0), record = t.pro or rec(0),
	}
end

local info = Moves.Info(profile({ am = rec(4, 1, 0, 2), pro = rec(3, 1, 1, 1) }))
check("Info fights", info.fights == 10, info.fights)
check("Info wins", info.wins == 7, info.wins)
check("Info kos", info.kos == 3, info.kos)

-- old / dirty saves: no record fields, junk in them
local old = Moves.Info({ style = "Slugger", tier = 2, records = { HeavyBag = { sessions = 3 } } })
check("old save: no fights", old.fights == 0 and old.wins == 0 and old.kos == 0)
check("old save: unlocks still work", Moves.Unlocked(old).overhand == true)
local dirty = Moves.Info({ style = "Slugger", amateurRecord = { w = 0 / 0, l = "x", d = -4, ko = math.huge }, record = "3-0" })
check("dirty save: zeros", dirty.fights == 0 and dirty.wins == 0 and dirty.kos == 0, dirty.fights)
check("KOs never above wins", Moves.Info({ record = rec(2, 0, 0, 9) }).kos == 2)
check("Info(nil)", Moves.Info(nil).fights == 0 and next(Moves.Unlocked(Moves.Info(nil))) == nil)
local okNil = pcall(function()
	Moves.UnlockText("doublejab", {})
	Moves.UnlockedBy("doublejab", {})
	Moves.FightProgress("nope", nil)
end)
check("nil-safe on empty info", okNil)

-- the client summary: style NAME in style, id in styleId, the same records
local sum = Moves.Info({ style = "Out-Boxer", styleId = "OutBoxer", tier = 2, record = rec(8, 2), amateurRecord = rec(4, 1, 0, 3) })
check("summary info", sum.style == "OutBoxer" and sum.fights == 15 and sum.wins == 12 and sum.kos == 3, sum.fights)

-- the ladder (a style with no home move among the old ones it would get: count only the fight moves)
local function fightSet(fights, wins, kos)
	local i = { style = "OutBoxer", tier = 1, sessions = {}, fights = fights, wins = wins, kos = kos }
	return Moves.Unlocked(i), i
end
local function has(set, list)
	for _, id in ipairs(list) do
		if not set[id] then
			return false
		end
	end
	return true
end
local function none(set, list)
	for _, id in ipairs(list) do
		if set[id] then
			return false
		end
	end
	return true
end
local s0 = fightSet(0, 0, 0)
check("ladder 0: no fight move", none(s0, FIGHT_MOVES))
check("ladder 2 bouts: still none", none(fightSet(2, 2, 0), FIGHT_MOVES))
local s3 = fightSet(3, 0, 0)
check("ladder 3 bouts: double jab", s3.doublejab and none(s3, { "feintcross", "bodyhead", "onetwothree", "shovelhook" }))
local s8 = fightSet(8, 1, 0)
check("ladder 8 bouts: feint-cross", s8.doublejab and s8.feintcross and not s8.bodyhead)
check("ladder 14 wins: no body-head", not fightSet(20, 14, 0).bodyhead)
check("ladder 15 wins: body-head", fightSet(20, 15, 0).bodyhead == true)
check("ladder 30 bouts, 0 wins: no body-head", not fightSet(30, 0, 0).bodyhead)
check("ladder 24 bouts: no 1-2-3", not fightSet(24, 24, 0).onetwothree)
check("ladder 25 bouts: 1-2-3", fightSet(25, 0, 0).onetwothree == true)
check("ladder 4 KOs: no shovel", not fightSet(40, 40, 4).shovelhook)
check("ladder 5 KOs: shovel", fightSet(5, 5, 5).shovelhook == true)
-- enough fighting opens everything, whatever the style, tier or training
local all = fightSet(30, 20, 5)
check("30 bouts / 20 wins / 5 KOs: every move", has(all, Moves.List))
for _, st in ipairs({ "OutBoxer", "Swarmer", "Slugger", "CounterPuncher", "BoxerPuncher" }) do
	check("every move by fighting: " .. st, has(Moves.Unlocked({ style = st, tier = 1, sessions = {}, fights = 30, wins = 20, kos = 5 }), Moves.List))
end

-- the older moves: the fight milestone is one more way in (OR); the old ways still work alone
check("checkhook: none at tier 1, 11 bouts", not Moves.Unlocked({ style = "Slugger", tier = 1, sessions = {}, fights = 11, wins = 0, kos = 0 }).checkhook)
check("checkhook: 12 bouts", Moves.Unlocked({ style = "Slugger", tier = 1, sessions = {}, fights = 12, wins = 0, kos = 0 }).checkhook == true)
check("checkhook: home style + tier", Moves.Unlocked({ style = "OutBoxer", tier = 2, sessions = {} }).checkhook == true)
check("checkhook: training", Moves.Unlocked({ style = "Slugger", tier = 1, sessions = { Ladder = 10 } }).checkhook == true)
check("gazelle: 20 wins", Moves.Unlocked({ style = "OutBoxer", tier = 1, sessions = {}, fights = 25, wins = 20, kos = 0 }).gazelle == true)
check("gazelle: 19 wins", not Moves.Unlocked({ style = "OutBoxer", tier = 1, sessions = {}, fights = 40, wins = 19, kos = 0 }).gazelle)
check("anyTier still opens", Moves.Unlocked({ style = "OutBoxer", tier = 7, sessions = {} }).peekaboo == true)
-- a tier-only unlock does not hand out the fight moves
check("tier 10 alone: no fight move", none(Moves.Unlocked({ style = "Swarmer", tier = 10, sessions = {} }), FIGHT_MOVES))

-- UnlockedBy's words (the menu's "Unlocked: ..." and the result note)
local i3 = { style = "OutBoxer", tier = 1, sessions = {}, fights = 3, wins = 0, kos = 0 }
check("UnlockedBy bouts", Moves.UnlockedBy("doublejab", i3) == "3 bouts fought", Moves.UnlockedBy("doublejab", i3))
check("UnlockedBy wins", Moves.UnlockedBy("bodyhead", { fights = 15, wins = 15, kos = 0 }) == "15 wins")
check("UnlockedBy KOs", Moves.UnlockedBy("shovelhook", { fights = 5, wins = 5, kos = 5 }) == "5 KO wins")
check("UnlockedBy locked", Moves.UnlockedBy("onetwothree", i3) == nil)
check("UnlockedBy old way first", Moves.UnlockedBy("checkhook", { style = "OutBoxer", tier = 2, sessions = {}, fights = 40, wins = 40, kos = 0 }) ~= "12 bouts fought")
check("UnlockedBy old move by bouts", Moves.UnlockedBy("checkhook", { style = "Slugger", tier = 1, sessions = {}, fights = 12, wins = 0, kos = 0 }) == "12 bouts fought")

------------------------------------------------------------------------
-- UnlockText (the menu)
------------------------------------------------------------------------
local mid = { style = "OutBoxer", tier = 1, sessions = { HeavyBag = 4 }, fights = 5, wins = 9, kos = 2 }
local function eq(name, got, want)
	check(name, got == want, string.format("%q, want %q", tostring(got), want))
end
eq("text double jab", Moves.UnlockText("doublejab"), "Fight 3 bouts")
eq("text double jab progress", Moves.UnlockText("doublejab", mid), "Fight 3 bouts (3/3)")
eq("text feint-cross progress", Moves.UnlockText("feintcross", mid), "Fight 8 bouts (5/8)")
eq("text body-head progress", Moves.UnlockText("bodyhead", mid), "Win 15 fights (9/15)")
eq("text 1-2-3 progress", Moves.UnlockText("onetwothree", mid), "Fight 25 bouts (5/25)")
eq("text shovel progress", Moves.UnlockText("shovelhook", mid), "Win 5 fights by KO (2/5)")
eq("text shovel, no info", Moves.UnlockText("shovelhook"), "Win 5 fights by KO")
eq("text shovel, old save", Moves.UnlockText("shovelhook", Moves.Info({})), "Win 5 fights by KO (0/5)")
local lh = Moves.UnlockText("livershot", mid)
check("text old move: all ways", lh:find("from", 1, true) ~= nil and lh:find("any style from", 1, true) ~= nil and lh:find("(4/12)", 1, true) ~= nil
	and lh:find("Fight 12 bouts (5/12)", 1, true) ~= nil, lh)
check("text old move, no info: no progress", not Moves.UnlockText("livershot"):find("/", 1, true), Moves.UnlockText("livershot"))
eq("text unknown", Moves.UnlockText("nope", mid), "")
check("progress capped", Moves.UnlockText("doublejab", { fights = 40 }) == "Fight 3 bouts (3/3)")
local have, need = Moves.FightProgress("bodyhead", mid)
check("FightProgress", have == 9 and need == 15)

------------------------------------------------------------------------
-- ForAI
------------------------------------------------------------------------
check("AI amateur: none", next(Moves.ForAI({ style = "Swarmer", tier = 1, record = rec(40, 0, 0, 30) })) == nil)
local ai2 = Moves.ForAI({ style = "Swarmer", tier = 2, record = rec(3) })
check("AI tier 2, 3 bouts: double jab", ai2.doublejab == true and not ai2.feintcross)
check("AI tier 2: home moves as before", ai2.livershot == true and ai2.leaduppercut == true and not ai2.checkhook)
local ai2b = Moves.ForAI({ style = "Swarmer", tier = 2, record = rec(40, 2, 0, 30) })
check("AI tier 2 veteran: aiTier holds the later ones", ai2b.doublejab and not ai2b.feintcross and not ai2b.shovelhook)
check("AI: older moves' fight milestones are not the AI's", not ai2b.checkhook and not ai2b.stepback)
local ai4 = Moves.ForAI({ style = "Slugger", tier = 4, record = rec(20, 3, 0, 4) })
check("AI tier 4, 23 bouts 20 wins 4 KOs", ai4.doublejab and ai4.feintcross and ai4.bodyhead and not ai4.onetwothree and not ai4.shovelhook)
local ai4r = Moves.ForAI({ style = "Slugger", tier = 4 })
check("AI without a record: by tier", has(ai4r, FIGHT_MOVES))
local ai3 = Moves.ForAI({ style = "Slugger", tier = 3 })
check("AI tier 3 no record", ai3.feintcross and ai3.bodyhead and not ai3.onetwothree and not ai3.shovelhook)
local aiTop = Moves.ForAI({ style = "OutBoxer", tier = 10, record = rec(40, 0, 0, 30) })
check("AI at the top: everything", has(aiTop, Moves.List))
local aiOv = Moves.ForAI({ style = "OutBoxer", stats = {} })
check("AI from overall (no tier)", type(aiOv) == "table")
check("ForAI(nil)", next(Moves.ForAI(nil)) == nil)

print(string.format("test_moves: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_moves failed")
end
