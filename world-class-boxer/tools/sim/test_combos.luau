--!nocheck
-- tools/sim/test_combos.luau: the combinations (src/shared/Combos.lua) and the dodges (src/shared/Evasion.lua), and
-- how FightEngine / FightAI run them, under lune.
--   * the rules, pure: the chain window from the punch timings, the boxing numbers, every named / signature combo
--     recognised (the longest match, a signature wins a tie), the accuracy / damage / stamina numbers, a named
--     combo's "landed" rule and refund, the blocked chain's break, the stats and their post-fight line, the
--     signature unlocks through the fight milestones (Moves.Info), the AI plans each being the combo they name
--   * the engine (FightEngine's real Fight methods on stub models, a fake clock and scheduler): a punch inside
--     the window chains (the Chain act flag), one after it starts a new chain, a press just before the recovery
--     ends is buffered and thrown on time, an earlier one counts as a mash; the landed ramp on the damage, the
--     stamina of a long chain, the named call-out and the refund, a blocked combo smothered with the defender's
--     counter window; the stats in the result
--   * the dodges: the evade windows by punch type (weave / duck beat hooks, slip / pull straights, side-step
--     everything and the body at a stamina cost), the timing (after the window and before the recovery he is
--     CAUGHT), an uppercut into a weave punished, the counter window and the counter combos (WEAVE-COUNTER),
--     the pad's flick-then-button cancel, every new dodge on the Fight remote and in the control map
--   * FightAI: plans by style and skill, the chain read and the learned sequence, the dodges by style
--   lune run tools/sim/test_combos.luau
local Host = require("./host")
local fs = require("@lune/fs")
local process = require("@lune/process")

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

-- a fake clock and scheduler (FightEngine's task.delay runs on it)
local clock = 0
local queue = {}
local fakeTask = {
	delay = function(t, fn, ...)
		local args = table.pack(...)
		table.insert(queue, { at = clock + (t or 0), fn = fn, args = args })
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	wait = function()
		return 0
	end,
	cancel = function() end,
}
local function advance(dt)
	local goal = clock + dt
	while true do
		table.sort(queue, function(a, b)
			return a.at < b.at
		end)
		local nxt = queue[1]
		if not nxt or nxt.at > goal then
			break
		end
		table.remove(queue, 1)
		clock = math.max(clock, nxt.at)
		nxt.fn(table.unpack(nxt.args, 1, nxt.args.n))
	end
	clock = goal
end

local H = Host.new({ server = true, globals = { task = fakeTask } })
local Combos = H.require("Combos")
local Evasion = H.require("Evasion")
local Config = H.require("Config")
local Moves = H.require("Moves")
local Keymap = H.require("Keymap")
local Tutorial = H.require("Tutorial")

local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
for _, f in ipairs(fs.readDir(H.src .. "/server")) do
	local base = f:match("^(.-)%.lua$")
	if base and not f:find("%.server%.") then
		local n = Host.NewNode(base, "ModuleScript", folder)
		rawset(n, "_file", H.src .. "/server/" .. f)
	end
end
local FightEngine = H.requireNode(folder._kids.FightEngine)
local FightAI = H.requireNode(folder._kids.FightAI)

------------------------------------------------------------------------
-- the rules, pure
------------------------------------------------------------------------
-- the window: from the punch timings (Config windups, the act's recovery)
for _, p in ipairs(Config.PunchList) do
	local w = Config.Punches[p].windup
	local win = Combos.Window(w)
	check("window " .. p .. " within 0.32..0.60", win >= Combos.WINDOW_MIN and win <= Combos.WINDOW_MAX, win)
	check("recovery " .. p .. " = windup x 1.9", near(Combos.Recovery(w), w * 1.9))
end
check("jab window ~0.40 s", near(Combos.Window(0.16), 0.396, 1e-9), Combos.Window(0.16))
check("rear hook window 0.48 s", near(Combos.Window(0.30), 0.48, 1e-9))
check("overhand window 0.55 s", near(Combos.Window(0.42), 0.552, 1e-9))
check("a slower punch has a longer window", Combos.Window(0.3) > Combos.Window(0.16))
-- the numbers
check("token jab", Combos.Token("jab", false, "L") == "1")
check("token body cross", Combos.Token("cross", true, "R") == "2b")
check("token lead uppercut", Combos.Token("uppercut", false, "L") == "5")
check("token rear uppercut", Combos.Token("uppercut", false, "R") == "6")
check("token overhand never body", Combos.Token("overhand", true, "R") == "O")
-- recognition: every named and signature combo by its own pattern
local function toks(str)
	local out = {}
	for t in str:gmatch("%S+") do
		table.insert(out, t)
	end
	return out
end
local ALL_SIGS = {}
for _, c in ipairs(Combos.Signatures) do
	ALL_SIGS[c.id] = true
end
local CASES = {
	{ "1 2", "onetwo" }, { "1 2 3", "onetwothree" }, { "1 1 2", "doublejabcross" }, { "2 3 2", "crosshookcross" },
	{ "1 2b 3", "jabbodyhook" }, { "1 3b 4", "jabbodyhook" }, { "3b 3", "bodyhead" }, { "2b 3", "bodyhead" }, { "3 3", "doublehook" },
	{ "4b 4b", "doublehook" }, { "6 3", "upperhook" }, { "5b 4", "upperhook" }, { "3 4", "hookhook" }, { "1 2 3 2", "onetwothreetwo" },
	{ "1 2 5", "onetwoupper" }, { "1 O", "jaboverhand" }, { "s 2", "slipcounter" }, { "p 1", "slipcounter" }, { "w 3", "weavecounter" },
	{ "r 6", "weavecounter" }, { "d 5", "duckupper" }, { "t 2", "stepcounter" },
}
for _, c in ipairs(CASES) do
	local m = Combos.Match(toks(c[1]))
	check("match " .. c[1] .. " = " .. c[2], m and m.id == c[2], m and m.id)
end
check("no match for a lone jab", Combos.Match({ "1" }) == nil)
check("no match for 1 1", Combos.Match(toks("1 1")) == nil)
check("a head 1-2 to the body is no 1-2", Combos.Match(toks("1b 2b")) == nil)
check("the longest match wins (1-2-3-2 over 3-2 / 2-3-2)", Combos.Match(toks("1 2 3 2")).id == "onetwothreetwo")
check("a tail match (... 1-2)", Combos.Match(toks("3 4 1 2")).id == "onetwo")
-- signatures: only for their owner, and a signature wins a tie
check("Dempsey not for a stranger", (Combos.Match(toks("3 4 3"))).id ~= "sig_dempsey")
check("Dempsey for its owner", Combos.Match(toks("3 4 3"), { sig_dempsey = true }).id == "sig_dempsey")
check("Four-piece for its owner", Combos.Match(toks("1 2 3 6"), ALL_SIGS).id == "sig_fourpiece")
check("Body attack for its owner", Combos.Match(toks("1 2b 3b 3"), ALL_SIGS).id == "sig_bodyattack")
check("Weave & hook for its owner", Combos.Match(toks("w 3 4"), ALL_SIGS).id == "sig_weavehooks")
for _, c in ipairs(Combos.Signatures) do
	check("signature " .. c.id .. " has a fight milestone", type(c.fight) == "table" and table.find(Moves.FIGHT_STATS, c.fight.stat) ~= nil and c.fight.n > 0)
end
-- the AI plans are the combos they are named after (hands as the engine gives them)
for id, plan in pairs(Combos.Plans) do
	local tokens, hand, n = {}, "R", 0
	for _, step in ipairs(plan) do
		n += 1
		local p = step[1]
		local h = Config.Punches[p].hand
		if p == "uppercut" then
			h = (hand == "R" and n > 1) and "L" or "R"
		end
		hand = h
		table.insert(tokens, Combos.Token(p, step[2] == true, h))
	end
	local m = Combos.Match(tokens, ALL_SIGS)
	check("plan " .. id .. " throws " .. id, m and m.id == id, (m and m.id or "none") .. " for " .. table.concat(tokens, " "))
end
for style, list in pairs(Combos.StylePlans) do
	check("style " .. style .. " exists", Config.FindById(Config.Styles, style) ~= nil)
	for id in pairs(list) do
		check("style " .. style .. " plan " .. id, Combos.Plans[id] ~= nil and Combos.ById[id] ~= nil)
	end
end
-- signature unlocks: the fight milestones over the whole career (Moves.Info)
local info0 = Moves.Info({ record = { w = 0, l = 0, d = 0, ko = 0 }, amateurRecord = { w = 0, l = 0, d = 0, ko = 0 } })
check("no signature at the start", next(Combos.UnlockedSignatures(info0)) == nil)
local info1 = Moves.Info({ record = { w = 2, l = 1, d = 0, ko = 1 }, amateurRecord = { w = 3, l = 0, d = 0, ko = 1 } })
local u1 = Combos.UnlockedSignatures(info1)
check("6 bouts / 5 wins / 2 KOs: body attack, Dempsey, four-piece", u1.sig_bodyattack and u1.sig_dempsey and u1.sig_fourpiece and not u1.sig_weavehooks)
check("unlock text with progress", Combos.SignatureUnlockText("sig_weavehooks", info1) == "Fight 10 bouts (6/10)", Combos.SignatureUnlockText("sig_weavehooks", info1))
check("unlocked by", Combos.SignatureUnlockedBy("sig_dempsey", info1) == "3 wins")
check("AI amateurs: no signatures", next(Combos.ForAI(1, { w = 30, l = 0, d = 0, ko = 20 })) == nil)
check("AI by tier and record", Combos.ForAI(3, { w = 10, l = 2, d = 0, ko = 6 }).sig_dempsey == true and Combos.ForAI(3, { w = 10, l = 2, d = 0, ko = 6 }).sig_weavehooks == nil)
-- stamina
check("stamina: 1..3 normal", Combos.StamMul(1) == 1 and Combos.StamMul(3) == 1)
check("stamina: the 4th +8%", near(Combos.StamMul(4), 1.08))
check("stamina: the 6th +24%", near(Combos.StamMul(6), 1.24))
check("stamina: capped +40%", near(Combos.StamMul(20), 1.4))
-- accuracy mods
do
	local ch = Combos.NewChain(0)
	local a = Combos.AddPunch(ch, { tok = "1", p = "jab", body = false })
	local b = Combos.AddPunch(ch, { tok = "2", p = "cross", body = false })
	check("an opener: no mods", a.hit == 0 and a.dmg == 1 and a.named == nil)
	check("1-2: named, +4 hit, +8% dmg", b.named and b.named.id == "onetwo" and near(b.hit, 0.04) and near(b.dmg, 1.08))
	local c = Combos.AddPunch(ch, { tok = "3b", p = "leadhook", body = true })
	check("level change +3 (and no named for 1 2 3b)", near(c.hit, 0.03) and c.named == nil, c.hit)
	ch.mash = 2
	local d = Combos.AddPunch(ch, { tok = "3b", p = "leadhook", body = true })
	check("4th: double hook named, mashing -6", d.named and d.named.id == "doublehook" and near(d.hit, 0.04 - 0.06), d.hit)
	local e = Combos.AddPunch(ch, { tok = "3", p = "leadhook", body = false })
	-- 5th punch: -4 long; the third lead hook in a row: -6; level change +3; mash -6; "3b 3b 3" ends in 3b 3 (bodyhead) ... the longest is "3b 3" (2) or "3~ 3~" (2): bodyhead first
	check("5th: long flurry -4, a third same punch -6", e.named and near(e.hit, 0.04 + 0.03 - 0.04 - 0.06 - 0.06), e.hit)
	ch.mash = 10
	local f = Combos.AddPunch(ch, { tok = "1", p = "jab", body = false })
	check("mash capped at -9, long at -8 by the 6th", near(f.hit, -0.08 - 0.09), f.hit)
end
-- the landed rule, the ramp and the refund
do
	local ch = Combos.NewChain(0)
	local a = Combos.AddPunch(ch, { tok = "1", p = "jab", cost = 2 })
	local b = Combos.AddPunch(ch, { tok = "2", p = "cross", cost = 4 })
	Combos.Result(ch, a, "landed")
	check("ramp after one landed (style 1.0): +4%", near(Combos.Ramp(ch, b, 1.0), 1.04))
	check("ramp scales with the style", near(Combos.Ramp(ch, b, 1.3), 1.052))
	local ev = Combos.Result(ch, b, "landed")
	check("1-2 landed: called, 25% refund", ev.named and ev.named.id == "onetwo" and near(ev.refund, 1.5))
	local ch2 = Combos.NewChain(0)
	local x = Combos.AddPunch(ch2, { tok = "1", p = "jab", cost = 2 })
	local y = Combos.AddPunch(ch2, { tok = "2", p = "cross", cost = 4 })
	Combos.Result(ch2, x, "miss")
	check("a 1-2 needs both", Combos.Result(ch2, y, "landed").named == nil)
	local ch3 = Combos.NewChain(0)
	local i1 = Combos.AddPunch(ch3, { tok = "1", p = "jab" })
	local i2 = Combos.AddPunch(ch3, { tok = "2", p = "cross" })
	local i3 = Combos.AddPunch(ch3, { tok = "3", p = "leadhook" })
	Combos.Result(ch3, i1, "blocked")
	Combos.Result(ch3, i2, "landed")
	check("a 1-2-3 with one blocked still lands", Combos.Result(ch3, i3, "landed").named.id == "onetwothree")
	local ch4 = Combos.NewChain(0)
	local j1 = Combos.AddPunch(ch4, { tok = "1", p = "jab" })
	local j2 = Combos.AddPunch(ch4, { tok = "2", p = "cross" })
	check("the first block: no break", not Combos.Result(ch4, j1, "blocked").broken)
	check("the second blocked punch breaks it", Combos.Result(ch4, j2, "blocked").broken == true)
	local ramp5 = Combos.NewChain(0)
	local last
	for _ = 1, 7 do
		last = Combos.AddPunch(ramp5, { tok = "1", p = "jab" })
		Combos.Result(ramp5, last, "landed")
	end
	check("the ramp caps at 4 landed (+16%)", near(Combos.Ramp(ramp5, last, 1.0), 1.16))
end
-- stats
do
	local st = Combos.NewStats()
	Combos.Record(st, { punches = 1, landed = 1 })
	check("a single punch is no combination", st.chains == 0)
	Combos.Record(st, { punches = 3, landed = 3, named = { id = "onetwothree", name = "1-2-3", len = 3 } })
	Combos.Record(st, { punches = 5, landed = 4, named = { id = "onetwo", name = "1-2", len = 2 } })
	Combos.Record(st, { punches = 2, landed = 0 })
	check("stats: chains / landed / best / best named", st.chains == 3 and st.landed == 2 and st.best == 4 and st.bestName == "1-2-3" and st.named.onetwo == 1)
	check("the post-fight line", Combos.StatsText(st) == "Best combo: 4 punches (1-2-3)  ·  Combos landed: 2", Combos.StatsText(st))
end
-- evasion by punch type
local KINDS = { "straight", "hook", "uppercut", "overhand" }
local function share(dodge, kind, body)
	local n = 0
	for i = 0, 99 do
		if Evasion.Beats(dodge, kind, body, (i + 0.5) / 100) then
			n += 1
		end
	end
	return n / 100
end
check("weave beats hooks", share("weave", "hook") == 1 and share("weave", "overhand") == 1)
check("duck beats hooks", share("duck", "hook") == 1)
check("slip beats straights", share("slip", "straight") == 1 and share("slip", "hook") == 0.5)
check("pull beats straights", share("pull", "straight") == 1 and share("pull", "hook") < 0.5)
check("weave / duck lose to the uppercut", share("weave", "uppercut") == 0 and share("duck", "uppercut") == 0)
check("weave / duck do not beat straights reliably", share("weave", "straight") < 0.5 and share("duck", "straight") < 1)
for _, k in ipairs(KINDS) do
	check("side-step beats " .. k, share("sidestep", k) == 1)
end
check("side-step beats the body", share("sidestep", "hook", true) == 1)
check("nothing else beats the body", share("weave", "hook", true) == 0 and share("slip", "straight", true) == 0 and share("duck", "hook", true) == 0)
check("side-step is the dearest", Evasion.Moves.sidestep.stam > Evasion.Moves.weave.stam and Evasion.Moves.sidestep.stam >= 9)
check("uppercut punishes a weave / duck", Evasion.Punish("weave", "uppercut") > 1 and Evasion.Punish("duck", "uppercut") > Evasion.Punish("weave", "uppercut"))
for _, k in ipairs(Evasion.List) do
	local E = Evasion.Moves[k]
	local w = Evasion.Window(k, { Reflexes = 50, HeadMovement = 50, Footwork = 50 }, 1)
	if k ~= "slip" and k ~= "roll" then
		-- (the slip and the roll keep their old windows)
		check("dodge " .. k .. ": the window is shorter than the recovery (timing)", w > 0.2 and w < E.recover, w .. " / " .. E.recover)
		check("dodge " .. k .. ": even elite head movement leaves a gap", Evasion.Window(k, { Reflexes = 100, HeadMovement = 100, Footwork = 100 }, 1) <= E.recover - 0.08 + 1e-9)
	end
	check("dodge " .. k .. ": a counter window", E.counter >= 0.6)
	check("dodge " .. k .. ": better head movement, longer window", w > Evasion.Window(k, { Reflexes = 20, HeadMovement = 20, Footwork = 20 }, 1))
end
check("acts: weave|L, duck, pull, sidestep|R", Evasion.Act("weave", -1) == "weave|L" and Evasion.Act("duck") == "duck" and Evasion.Act("pull", 1) == "pull" and Evasion.Act("sidestep", 1) == "sidestep|R")
check("acts: with the length as the last field", Evasion.Act("duck", nil, 0.4) == "duck|0.40" and Evasion.Act("sidestep", -1, 0.55) == "sidestep|L|0.55")
-- the controls
for _, id in ipairs({ "weaveL", "weaveR", "duck", "pull", "sidestepL", "sidestepR" }) do
	local a = Keymap.ById[id]
	check("control " .. id, a ~= nil and a.section == "advanced")
	if a then
		for _, b in ipairs(a.kbd) do
			check("control " .. id .. " kbd " .. b .. " valid", Keymap.Valid(b, "kbd"))
		end
		check("control " .. id .. " pad " .. a.pad .. " valid", Keymap.Valid(a.pad, "pad"))
		check("control " .. id .. " has a touch gesture (no new pad)", type(a.touch) == "string" and (a.touch:find("BLOCK", 1, true) or a.touch:find("CLINCH", 1, true)) ~= nil)
	end
end
check("no default control conflicts", #Keymap.Conflicts(Keymap.Resolve(nil)) == 0, #Keymap.Conflicts(Keymap.Resolve(nil)) > 0 and Keymap.Conflicts(Keymap.Resolve(nil))[1].binding)
local fcSrc = fs.readFile(H.src .. "/client/FightClient.client.lua")
for _, k in ipairs({ "weave", "duck", "pull", "sidestep" }) do
	check("the client sends the " .. k, fcSrc:find('kind = "' .. k .. '"', 1, true) ~= nil)
end

------------------------------------------------------------------------
-- the engine (the real Fight methods on stub models)
------------------------------------------------------------------------
local Fight = FightEngine._Fight
local function model()
	local attrs = {}
	return {
		attrs = attrs,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		FindFirstChildOfClass = function()
			return nil
		end,
		FindFirstChild = function()
			return nil
		end,
		PivotTo = function() end,
	}
end
local function fighterData(style)
	local stats = {}
	for _, k in ipairs(Config.StatKeys) do
		stats[k] = 60
	end
	return { name = "Boxer " .. style, style = style, stats = stats, mental = {}, class = 5, record = { w = 0, l = 0, d = 0, ko = 0 }, moves = {}, app = { gender = 1 } }
end
local function constRng(v)
	return {
		NextNumber = function(_, a, b)
			if a == nil then
				return v
			end
			return a + (b - a) * v
		end,
		NextInteger = function(_, a)
			return a
		end,
	}
end
local function newFight(styleP, styleO)
	local self = setmetatable({}, Fight)
	self.id = 1
	self.live = true
	self.rounds, self.round = 3, 1
	self.damageScale, self.allowKD = 1, true
	self.rng = constRng(0.001)
	self.cutRisk = {}
	self.cards = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
	self.knockdowns = {}
	self.msgs = {}
	self.P = FightEngine._makeFighter(fighterData(styleP or "BoxerPuncher"), model(), nil)
	self.O = FightEngine._makeFighter(fighterData(styleO or "BoxerPuncher"), model(), nil)
	self.pair = { self.P, self.O }
	self.Now = function()
		return clock
	end
	self.Distance = function()
		return 4.0
	end
	self.Send = function(_, m)
		table.insert(self.msgs, m)
	end
	self.SendTo = function(_, _, m)
		table.insert(self.msgs, m)
	end
	self.Knockdown = function() end
	self.Stumble = function() end
	self.RefreshDamage = function() end
	return self
end
local function msgsOf(fight, t)
	local out = {}
	for _, m in ipairs(fight.msgs) do
		if m.t == t then
			table.insert(out, m)
		end
	end
	return out
end
local function rest(F)
	F.health, F.body, F.stamina, F.balance, F.tier, F.conc = 100, 100, F.maxStam, 100, 0, 0
	F.stumbleUntil, F.hurtUntil = 0, 0
	F.dmg.cut, F.dmg.cut2 = 0, 0 -- (a cut makes head shots land 8% harder: keep the comparisons clean)
end
local function waitFree(fight, F)
	advance(math.max(0, F.busyUntil - clock) + 0.001)
	fight:Update(0)
end

-- a chain: inside the window it goes on (with the act flag), after it a new one starts
do
	clock = 100
	local fight = newFight()
	local P, O = fight.P, fight.O
	fight:Punch(P, "jab", false)
	check("engine: the opener's Chain flag is 1", P.model.attrs.Chain == 1 and P.combo == 1, P.model.attrs.Chain)
	check("engine: an opener's act has no chain field", P.model.attrs.Act:match("^jab|L|head|[%d.]+$") ~= nil, P.model.attrs.Act)
	local chain = P.chain
	waitFree(fight, P)
	advance(0.1) -- inside the window
	fight:Punch(P, "cross", false)
	check("engine: a punch in the window chains (Chain 2)", P.chain == chain and P.model.attrs.Chain == 2 and chain.punches == 2)
	check("engine: the chained act's sixth field (the Animator's format)", P.model.attrs.Act:match("^cross|R|head|[%d.]+||2$") ~= nil, P.model.attrs.Act)
	waitFree(fight, P)
	check("engine: 1-2 landed and called", #msgsOf(fight, "combo") >= 1 and msgsOf(fight, "combo")[#msgsOf(fight, "combo")].name == "1-2")
	advance(Combos.Window(0.24) + 0.05)
	fight:Update(0)
	check("engine: the window ran out: chain over (comboEnd)", P.chain == nil and #msgsOf(fight, "comboEnd") == 1 and msgsOf(fight, "comboEnd")[1].hits == 2)
	fight:Punch(P, "jab", false)
	check("engine: a late punch starts a new chain", P.chain ~= chain and P.chain.punches == 1 and P.model.attrs.Chain == 1)
	check("engine: stats after the 1-2", P.comboStats.chains == 1 and P.comboStats.landed == 1 and P.comboStats.best == 2)
	-- a defence act clears the flag
	waitFree(fight, P)
	advance(1)
	fight:Update(0)
	fight:Slip(P, 1)
	check("engine: a defence act sets Chain 0", P.model.attrs.Chain == 0)
end

-- the buffer and the mash
do
	clock = 200
	local fight = newFight()
	local P = fight.P
	fight:Punch(P, "jab", false)
	local busy = P.busyUntil
	advance(0.05)
	fight:Punch(P, "jab", false) -- far too early: a mash
	check("engine: an early press is a mash, not a punch", P.chain.mash == 1 and P.chain.punches == 1)
	advance(math.max(0, busy - clock - Combos.BUFFER * 0.5))
	fight:Punch(P, "cross", false) -- just before the recovery ends: buffered
	check("engine: a press inside the buffer is held", P.buffered == true and P.chain.punches == 1)
	advance(Combos.BUFFER)
	check("engine: and thrown when the recovery ends, chained", P.chain.punches == 2 and P.model.attrs.Chain == 2 and not P.buffered)
	check("engine: the mash costs the next punch accuracy", near(P.chain.items[2].hit, Combos.NAMED_HIT - Combos.MASH), P.chain.items[2].hit)
end

-- the landed ramp on the damage, the stamina of a long chain
do
	clock = 300
	local fight = newFight("BoxerPuncher")
	local P, O = fight.P, fight.O
	local style = Config.FindById(Config.Styles, "BoxerPuncher").fight.combo
	local taken = {}
	local costs = {}
	for i = 1, 5 do
		rest(O)
		P.stamina = P.maxStam
		local before = O.damageTaken
		local s0 = P.stamina
		fight:Punch(P, "jab", false)
		costs[i] = s0 - P.stamina
		waitFree(fight, P)
		taken[i] = O.damageTaken - before
		advance(0.05)
	end
	check("engine: five chained jabs", P.chain and P.chain.punches == 5 and P.chain.landed == 5, P.chain and P.chain.landed)
	local styleTerm = 1 + (style - 1) * 0.5
	local exp3 = (1 + 2 * Combos.RAMP * style) * styleTerm
	check("engine: the 3rd landed jab hits harder by the ramp", near(taken[3] / taken[1], exp3, 0.02), taken[3] / taken[1] .. " vs " .. exp3)
	local exp5 = (1 + 4 * Combos.RAMP * style) * styleTerm
	check("engine: the 5th by the capped ramp", near(taken[5] / taken[1], exp5, 0.02), taken[5] / taken[1] .. " vs " .. exp5)
	check("engine: the 4th punch costs 8% more stamina", near(costs[4] / costs[1], 1.08, 0.01), costs[4] / costs[1])
	check("engine: the 5th 16% more", near(costs[5] / costs[1], 1.16, 0.01))
	advance(1)
	local res = fight:ResultFor(P, { outcome = "win", method = "UD", round = 3 })
	check("engine: the result carries the combo stats", type(res.combos) == "table" and res.combos.best == 5 and res.combos.chains == 1, res.combos and res.combos.best)
end

-- a named combo's refund, a blocked combo smothered
do
	clock = 400
	local fight = newFight()
	local P, O = fight.P, fight.O
	fight:Punch(P, "jab", false)
	waitFree(fight, P)
	advance(0.05)
	local s0 = P.stamina
	fight:Punch(P, "cross", false)
	local paid = s0 - P.stamina
	local after = P.stamina
	advance(P.busyUntil - clock - 0.05) -- the cross has landed
	check("engine: a landed 1-2 gives stamina back", P.stamina > after and near(P.stamina - after, (P.chain.items[1].cost + paid) * Combos.REFUND, 0.2), P.stamina - after)
	waitFree(fight, P)
	-- now O blocks: two blocked punches smother it
	advance(1)
	fight:Update(0)
	O.blocking = true
	fight:Punch(P, "jab", false)
	waitFree(fight, P)
	advance(0.05)
	local busyBefore
	fight:Punch(P, "cross", false)
	busyBefore = P.busyUntil
	advance(0.3)
	check("engine: the second blocked punch smothers the combo", P.chain == nil or P.chain.closed, P.chain and P.chain.blocked)
	check("engine: the defender's counter window", O.counterUntil >= clock + Combos.BREAK_COUNTER - 0.31)
	check("engine: the attacker is stuck a beat longer", P.busyUntil >= busyBefore + Combos.BREAK_STALL - 1e-6)
	check("engine: told to the HUD", #msgsOf(fight, "comboBroken") == 1)
end

-- the dodges
do
	clock = 500
	local fight = newFight("BoxerPuncher", "Swarmer")
	local P, O = fight.P, fight.O
	fight.Distance = function()
		return 3.3 -- (inside every punch's reach)
	end
	fight.rng = constRng(0.4)
	-- a weave beats the hook inside its window, opens the counter window and a chain
	fight:Dodge(O, "weave", -1)
	check("dodge: the weave's act (with its length)", O.model.attrs.Act == "weave|L|0.50" and O.dodgeKind == "weave", O.model.attrs.Act)
	fight:Punch(P, "leadhook", false)
	advance(Config.Punches.leadhook.windup + 0.01)
	local def = msgsOf(fight, "defense")
	check("dodge: the hook misses the weave", #def == 1 and def[1].move == "WEAVED" and def[1].dodge == "weave", def[1] and def[1].move)
	check("dodge: the counter window", O.counterUntil > clock + 0.5)
	check("dodge: a chain from the weave", O.chain and O.chain.items[1].tok == "w")
	advance(math.max(0, O.busyUntil - clock) + 0.01)
	fight:Update(0)
	local before = #msgsOf(fight, "combo")
	fight:Punch(O, "leadhook", false)
	check("dodge: the counter continues the weave's chain", O.chain.punches == 1 and O.chain.items[2].named and O.chain.items[2].named.id == "weavecounter")
	advance(Config.Punches.leadhook.windup + 0.01)
	local cm = msgsOf(fight, "combo")
	check("dodge: WEAVE-COUNTER called when it lands", #cm > before and cm[#cm].name == "WEAVE-COUNTER", cm[#cm] and cm[#cm].name)
	local hits = msgsOf(fight, "hit")
	check("dodge: the counter lands as a counter", hits[#hits] and hits[#hits].counter == true)
	-- the timing: after the window but inside the recovery he is caught
	advance(2)
	fight:Update(0)
	rest(O)
	O.chain = nil
	fight:Dodge(O, "duck")
	advance(O.dodgeUntil - clock + 0.01) -- the window is over, the recovery is not
	fight:Punch(P, "cross", false)
	advance(0.01) -- (the cross's wind-up is longer than the duck's recovery left: land it inside)
	O.dodgeEnd = clock + 1
	advance(Config.Punches.cross.windup)
	local h = msgsOf(fight, "hit")
	check("dodge: caught after the window", h[#h] and h[#h].caught == true, h[#h] and tostring(h[#h].caught))
	-- an uppercut into a weave is punished
	advance(2)
	fight:Update(0)
	rest(O)
	fight.rng = constRng(0.001)
	P.stamina = P.maxStam
	local d0 = O.damageTaken
	fight:Punch(P, "uppercut", false)
	advance(Config.Punches.uppercut.windup + 0.01)
	local plain = O.damageTaken - d0
	advance(2)
	fight:Update(0)
	rest(O)
	P.stamina = P.maxStam
	P.chain = nil
	fight:Dodge(O, "weave", 1)
	d0 = O.damageTaken
	fight:Punch(P, "uppercut", false)
	advance(Config.Punches.uppercut.windup * 0.9)
	check("dodge: the uppercut is not beaten by the weave", O.dodgeKind == "weave")
	advance(0.1)
	local punished = O.damageTaken - d0
	check("dodge: an uppercut into a weave lands bigger", punished > plain * 1.2, punished .. " vs " .. plain)
	-- the side-step: everything, the body too, at the price
	advance(2)
	fight:Update(0)
	rest(O)
	local s0 = O.stamina
	fight:Dodge(O, "sidestep", 1)
	check("dodge: the side-step costs 9", near(s0 - O.stamina, Evasion.Moves.sidestep.stam))
	fight:Punch(P, "leadhook", true)
	advance(Config.Punches.leadhook.windup + 0.01)
	local dd = msgsOf(fight, "defense")
	check("dodge: the side-step beats a body hook", dd[#dd].move == "SIDESTEPPED")
	-- the pad's flick-then-button: a slip turns into a pull, half its cost back
	advance(2)
	fight:Update(0)
	rest(O)
	s0 = O.stamina
	fight:Slip(O, 1)
	advance(0.1)
	fight:Dodge(O, "pull")
	check("dodge: the slip turns into the pull", O.dodgeKind == "pull" and O.slipUntil == 0 and near(s0 - O.stamina, Evasion.Moves.slip.stam * 0.5 + Evasion.Moves.pull.stam))
	advance(0.05)
	fight:Dodge(O, "weave", 1)
	check("dodge: only once (no chain of cancels)", O.dodgeKind == "pull")
	-- a punch's recovery is never cancelled
	advance(2)
	fight:Update(0)
	fight:Punch(O, "jab", false)
	advance(0.05)
	fight:Dodge(O, "duck")
	check("dodge: never out of a punch", O.dodgeKind ~= "duck")
end

-- the engine's input: the Fight remote's dodge message
local feSrc = fs.readFile(H.src .. "/server/FightEngine.lua")
check("Input routes the dodges", feSrc:find('t == "dodge" and (msg.kind == "weave" or msg.kind == "duck" or msg.kind == "pull" or msg.kind == "sidestep")', 1, true) ~= nil)

------------------------------------------------------------------------
-- FightAI
------------------------------------------------------------------------
local function aiFor(style, ringIQ, focus)
	clock = 900
	local fight = newFight("BoxerPuncher", style)
	local F, O = fight.O, fight.P
	F.data.stats.RingIQ = ringIQ or 60
	F.data.mental.Focus = focus or 60
	local calls = {}
	local eng = setmetatable({}, { __index = fight })
	eng.Slip = function(_, _, dir)
		table.insert(calls, "slip")
	end
	eng.Roll = function()
		table.insert(calls, "roll")
	end
	eng.Parry = function()
		table.insert(calls, "parry")
	end
	eng.Pivot = function()
		table.insert(calls, "pivot")
	end
	eng.SetBlock = function()
		table.insert(calls, "block")
	end
	eng.Dodge = function(_, _, kind)
		table.insert(calls, kind)
	end
	eng.Distance = function()
		return 3.8
	end
	eng.rounds, eng.round = 3, 1
	local ai = FightAI.new(F, O, eng)
	ai.rng = H.globals.Random.new(7)
	return ai, calls, fight
end
-- plans by style
local function planShare(style, ringIQ, focus, n)
	local ai = aiFor(style, ringIQ, focus)
	local planned, ids, long = 0, {}, 0
	for _ = 1, n do
		ai.lastPlan = nil
		ai.mode = "pressure"
		local list = ai:BuildCombo()
		if ai.lastPlan then
			planned += 1
			ids[ai.lastPlan] = (ids[ai.lastPlan] or 0) + 1
			if #list > 3 then
				long += 1
			end
		end
	end
	return planned / n, ids, long
end
local shareHi, idsOut = planShare("OutBoxer", 90, 90, 400)
local shareLo, _, longLo = planShare("OutBoxer", 25, 25, 400)
check("AI: a skilled boxer throws named combos more", shareHi > shareLo + 0.2, shareHi .. " vs " .. shareLo)
check("AI: a raw boxer keeps them to three punches", longLo == 0, longLo)
check("AI: the out-boxer's favourites are jab combos", (idsOut.onetwo or 0) + (idsOut.doublejabcross or 0) > (idsOut.jaboverhand or 0) * 3, idsOut.onetwo)
local _, idsSw = planShare("Swarmer", 80, 80, 400)
check("AI: the swarmer throws hooks and body work", (idsSw.hookhook or 0) + (idsSw.bodyhead or 0) + (idsSw.doublehook or 0) + (idsSw.upperhook or 0) > (idsSw.onetwothree or 0) * 2)
check("AI: never a plan its style does not have", idsSw.doublejabcross == nil and idsSw.jaboverhand == nil)
-- the chain read and the learned sequence
do
	local ai, _, fight = aiFor("CounterPuncher", 60, 60)
	local O = fight.P
	local function chainOf(tokens)
		local ch = Combos.NewChain(0)
		for _, t in ipairs(tokens) do
			Combos.AddPunch(ch, { tok = t, p = "jab" })
		end
		return ch
	end
	O.chain = chainOf({ "1" })
	check("AI: a lone punch is not read", ai:ReadChain() == 0)
	O.chain = chainOf({ "1", "2", "3", "2" })
	local b4 = ai:ReadChain()
	O.chain = chainOf({ "1", "2", "3", "2", "3", "2" })
	local b6 = ai:ReadChain()
	check("AI: a long flurry is read from the 4th punch", b4 >= Combos.READ_STEP - 1e-9 and b6 > b4, b4 .. " / " .. b6)
	local ai2 = aiFor("CounterPuncher", 60, 60)
	ai2.O.chain = chainOf({ "1", "2" })
	local first = ai2:ReadChain()
	ai2:ReadChain()
	local third = ai2:ReadChain()
	check("AI: a 1-2 it has seen twice is expected", first == 0 and third >= Combos.LEARN_BONUS - 1e-9, first .. " / " .. third)
end
-- the dodges by style
local function dodgeShare(style, kind)
	local ai, calls = aiFor(style, 60, 60)
	ai.F.data.stats.Reflexes = 95
	local n, dodges = 0, 0
	for _ = 1, 300 do
		ai.F.busyUntil = 0
		ai.freezeUntil = 0
		table.clear(calls)
		ai:OnOppPunch(kind == "hook" and "leadhook" or "jab", false, 0.6)
		advance(0.5)
		for _, c in ipairs(calls) do
			n += 1
			if c ~= "block" and c ~= "parry" then
				dodges += 1
			end
		end
	end
	return n > 0 and dodges / n or 0, n
end
local cp = dodgeShare("CounterPuncher", "straight")
local sl = dodgeShare("Slugger", "straight")
local ob = dodgeShare("OutBoxer", "hook")
local slh = dodgeShare("Slugger", "hook")
check("AI: counter-punchers dodge more than sluggers", cp > sl, cp .. " vs " .. sl)
check("AI: out-boxers dodge hooks more than sluggers", ob > slh, ob .. " vs " .. slh)
do
	local ai, calls = aiFor("Swarmer", 60, 60)
	ai.F.data.stats.Reflexes = 95
	local seen = {}
	for _ = 1, 400 do
		ai.F.busyUntil = 0
		table.clear(calls)
		ai:OnOppPunch("rearhook", false, 0.6)
		advance(0.5)
		for _, c in ipairs(calls) do
			seen[c] = (seen[c] or 0) + 1
		end
	end
	check("AI: the swarmer weaves under hooks", (seen.weave or 0) > 0 and (seen.weave or 0) >= (seen.slip or 0), seen.weave)
	check("AI: nobody slips into a pull against a hook more than he weaves", (seen.pull or 0) == 0)
end

------------------------------------------------------------------------
-- the tutorial / debut steps (the combo and counter steps) see the engine's events
------------------------------------------------------------------------
do
	local tr = Tutorial.NewTracker()
	tr.step = Tutorial.IndexOf(tr, "combo")
	Tutorial.Feed(tr, { k = "combo", id = "weavecounter", counter = true, now = 1 })
	check("tutorial: a counter is not the combo step", Tutorial.Current(tr).id == "combo")
	Tutorial.Feed(tr, { k = "combo", id = "onetwo", now = 2 })
	check("tutorial: a 1-2 passes the combo step", Tutorial.Current(tr).id == "block")
	tr.step = Tutorial.IndexOf(tr, "slip")
	Tutorial.Feed(tr, { k = "dodge", kind = "weave", now = 3 })
	check("tutorial: a weave passes the slip step", Tutorial.Current(tr).id == "counter")
	Tutorial.Feed(tr, { k = "combo", id = "onetwo", now = 4 })
	check("tutorial: a plain combo is not a counter", Tutorial.Current(tr).id == "counter")
	Tutorial.Feed(tr, { k = "combo", id = "slipcounter", counter = true, now = 5 })
	check("tutorial: a slip-counter passes the counter step", Tutorial.Current(tr).id == "stamina")
	check("engine feeds combos to the tutorial", feSrc:find('TutorialNote({ k = "combo", id = item.named.id', 1, true) ~= nil)
	check("engine feeds dodges to the tutorial", feSrc:find('TutorialNote({ k = "dodge", kind = kind })', 1, true) ~= nil)
end

print(string.format("test_combos: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
