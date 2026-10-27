-- Combos: punches thrown in rhythm chain into a combination. Shared and pure (no Roblox services): the server
-- (FightEngine runs the chains and is the only judge of the timing, FightAI throws combos), the client (the HUD's
-- combo counter and call-outs, Moves & Controls) and tools/sim (test_combos) load the same rules.
--
-- THE CHAIN. A punch's act takes windup x RECOVERY_MUL to play out (the wind-up, the contact, the recovery:
-- FightEngine's busyUntil = windup + windup x 0.9). The chain window opens when that recovery ends and stays open
-- Combos.Window(windup) seconds (0.30 + 0.6 x windup, clamped 0.32 .. 0.60: a jab about 0.40 s, a rear hook 0.48,
-- an overhand 0.55). The next punch thrown inside it continues the combination; later, a new one starts. A press up
-- to BUFFER seconds BEFORE the recovery ends is held by the server and thrown on the frame the recovery ends (so a
-- rhythm press is never lost); anything earlier is refused and counted as a MASH (a wild press) against the chain.
-- A dodge that makes a punch miss (slip, roll, weave, duck, pull, side-step) opens a chain of its own: the counter
-- thrown inside its counter window continues it ("SLIP-COUNTER", "WEAVE-COUNTER"...).
--
-- THE ACT FLAG (for the Animator, CONTRACTS section 7): a chained punch's act carries its place in the combination
-- as the act's sixth field ("jab|L|head|0.16||2": 2+ = thrown inside the previous punch's chain window, so the
-- animation flows out of the last recovery instead of resetting to the guard; an opener has no sixth field). Just
-- before the act, FightEngine also sets the model attribute `Chain` (1 = an opener, 2+ chained, 0 = any other
-- act); the client's own prediction does the same in PredAct and PredChain.
--
-- THE RULES (numbers below; FightEngine applies them, test_combos checks them):
--   * damage   every punch already LANDED in this chain adds RAMP (4%) x the style's combo factor, up to RAMP_MAX
--              of them (+16% at most for a Boxer-Puncher's 1.1: 17.6%); the punch that completes a named combo
--              adds NAMED_DMG (+8%), a signature combo SIG_DMG (+15%) instead
--   * accuracy the completing punch of a named combo +NAMED_HIT (+4 points; signature +SIG_HIT 6); a level change
--              (head <-> body) +LEVEL_MIX (3); from the LONG_FROM-th (5th) punch on -LONG_STEP (4) a punch, at most
--              LONG_MAX (16); the third same punch in a row (not the jab) -REPEAT (6) each; every MASH press in the
--              chain -MASH (3), at most MASH_MAX (9)
--   * stamina  from the STAM_FROM-th (4th) punch on each costs STAM_STEP (8%) more a punch, at most STAM_MAX (+40%);
--              a miss in a chain of WHIFF_FROM (4)+ costs WHIFF (1.5) more; a landed named combo gives REFUND (25%)
--              of its punches' stamina back
--   * blocked  the BLOCK_BREAK-th (2nd) blocked punch of a chain ends it: the defender gets a counter window of
--              BREAK_COUNTER (0.8 s) and the attacker BREAK_STALL (0.15 s) more recovery
--   * reading  a defender's AI reads a chain from its READ_FROM-th (4th) punch on (+READ_STEP 6 points of defence a
--              punch, at most READ_MAX 18) and a sequence the player keeps repeating (+LEARN_BONUS 15 points on the
--              punch it expects next, once it has seen it LEARN_SEEN (2) times)
-- A named combo LANDS when its last punch lands clean (not blocked) and at least max(2, n - 1) of its n punches
-- landed. Stats: chains of 2+ punches, named combos landed (each chain counts its longest landed one), the best
-- chain (most punches landed) and the best named combo (longest; a signature wins a tie).
local Combos = {}

Combos.RECOVERY_MUL = 1.9 -- a punch's act length / its windup (FightEngine: busyUntil = now + windup * 1.9)
Combos.BUFFER = 0.15
Combos.WINDOW_BASE, Combos.WINDOW_PER_WINDUP = 0.30, 0.6
Combos.WINDOW_MIN, Combos.WINDOW_MAX = 0.32, 0.60
Combos.CHAIN_WINDUP = 0.88 -- a chained punch winds up a little quicker (the old combo rule, kept)

Combos.RAMP, Combos.RAMP_MAX = 0.04, 4
Combos.NAMED_DMG, Combos.SIG_DMG = 1.08, 1.15
Combos.NAMED_HIT, Combos.SIG_HIT = 0.04, 0.06
Combos.LEVEL_MIX = 0.03
Combos.LONG_FROM, Combos.LONG_STEP, Combos.LONG_MAX = 5, 0.04, 0.16
Combos.REPEAT = 0.06
Combos.MASH, Combos.MASH_MAX = 0.03, 0.09
Combos.STAM_FROM, Combos.STAM_STEP, Combos.STAM_MAX = 4, 0.08, 0.4
Combos.WHIFF_FROM, Combos.WHIFF = 4, 1.5
Combos.REFUND = 0.25
Combos.BLOCK_BREAK, Combos.BREAK_COUNTER, Combos.BREAK_STALL = 2, 0.8, 0.15
Combos.READ_FROM, Combos.READ_STEP, Combos.READ_MAX = 4, 0.06, 0.18
Combos.LEARN_SEEN, Combos.LEARN_BONUS = 2, 0.15

function Combos.Recovery(windup)
	return windup * Combos.RECOVERY_MUL
end

function Combos.Window(windup)
	return math.clamp(Combos.WINDOW_BASE + Combos.WINDOW_PER_WINDUP * (tonumber(windup) or 0.25), Combos.WINDOW_MIN, Combos.WINDOW_MAX)
end

------------------------------------------------------------------------
-- Tokens: the boxing numbers. 1 jab, 2 cross, 3 lead hook, 4 rear hook, 5 lead uppercut, 6 rear uppercut,
-- O overhand; "b" after it = to the body. Dodges: s slip, r roll, w weave, d duck, p pull, t side-step.
------------------------------------------------------------------------
local NUM = { jab = "1", cross = "2", leadhook = "3", rearhook = "4", overhand = "O" }
Combos.DODGE_TOKEN = { slip = "s", roll = "r", weave = "w", duck = "d", pull = "p", sidestep = "t" }
Combos.DODGE_OF = {}
for k, v in pairs(Combos.DODGE_TOKEN) do
	Combos.DODGE_OF[v] = k
end

-- the token of a punch (hand = the punching hand: an uppercut with the left is a 5, with the right a 6; the
-- other punch types already say lead / rear)
function Combos.Token(ptype, body, hand)
	local n = NUM[ptype]
	if ptype == "uppercut" then
		n = hand == "L" and "5" or "6"
	end
	if not n then
		return nil
	end
	return (body and ptype ~= "overhand") and (n .. "b") or n
end

-- one pattern element: "1" a head jab, "1b" a body jab, "1~" either level; H = a hook (3 / 4), U = an uppercut
-- (5 / 6), S = a straight (1 / 2), X = any punch, B = any body shot (same as "Xb"); s r w d p t = a dodge;
-- E = any dodge
local SETS = { H = { "3", "4" }, U = { "5", "6" }, S = { "1", "2" }, X = { "1", "2", "3", "4", "5", "6", "O" }, E = { "s", "r", "w", "d", "p", "t" } }
local function parseElem(s)
	local base, suf = s:match("^([%w])([b~]?)$")
	if not base then
		return nil
	end
	if base == "B" then
		base, suf = "X", "b"
	end
	local set = SETS[base] or { base }
	local dodge = base == "E" or Combos.DODGE_OF[base] ~= nil
	return { set = set, level = dodge and "any" or (suf == "b" and "body" or (suf == "~" and "any" or "head")), dodge = dodge }
end
function Combos.Parse(pattern)
	local out = {}
	for part in string.gmatch(pattern, "%S+") do
		local e = parseElem(part)
		if not e then
			return nil
		end
		table.insert(out, e)
	end
	return out
end

local function elemMatches(e, tok)
	if type(tok) ~= "string" then
		return false
	end
	local num, b = tok:match("^([%w])(b?)$")
	if not num or not table.find(e.set, num) then
		return false
	end
	if e.level == "head" then
		return b == ""
	elseif e.level == "body" then
		return b == "b"
	end
	return true
end

------------------------------------------------------------------------
-- The named combinations (called out when they land). Order = priority among equally long matches.
-- id, name (the call-out), short (the HUD's chip), patterns, desc
------------------------------------------------------------------------
Combos.Named = {
	{ id = "onetwothreetwo", name = "1-2-3-2", patterns = { "1 2 3 2" }, desc = "Jab, cross, lead hook and the cross again as he comes back to centre." },
	{ id = "onetwoupper", name = "1-2-UPPERCUT", patterns = { "1 2 5" }, desc = "Jab, cross, then the lead uppercut through the middle of his guard." },
	{ id = "onetwothree", name = "1-2-3", patterns = { "1 2 3" }, desc = "The bread-and-butter three: jab, cross, lead hook." },
	{ id = "doublejabcross", name = "1-1-2", patterns = { "1 1 2" }, desc = "Double up the jab, then the cross behind it." },
	{ id = "crosshookcross", name = "2-3-2", patterns = { "2 3 2" }, desc = "Cross, lead hook, cross: the right hand twice around the hook." },
	{ id = "jabbodyhook", name = "JAB-BODY-HOOK", patterns = { "1 B H" }, desc = "Jab upstairs, a shot to the body, and the hook up top as his guard drops." },
	{ id = "bodyhead", name = "DOWNSTAIRS-UPSTAIRS", patterns = { "Hb H", "2b 3" }, desc = "A body shot, then straight back to the head." },
	{ id = "doublehook", name = "DOUBLE HOOK", patterns = { "3~ 3~", "4~ 4~" }, desc = "The same hook twice: the second comes before he resets." },
	{ id = "upperhook", name = "UPPERCUT-HOOK", patterns = { "U~ H" }, desc = "The uppercut lifts his chin; the hook goes round to it." },
	{ id = "hookhook", name = "LEFT-RIGHT HOOKS", patterns = { "3 4", "4 3" }, desc = "Both hooks, one after the other, inside." },
	{ id = "jaboverhand", name = "JAB-OVERHAND", patterns = { "1 O" }, desc = "A jab to draw the guard, the overhand over it." },
	{ id = "onetwo", name = "1-2", patterns = { "1 2" }, desc = "Jab, cross. The first combination every boxer learns." },
	-- out of a dodge (the dodge opens the chain; the punch comes inside its counter window)
	{ id = "weavecounter", name = "WEAVE-COUNTER", patterns = { "w X~", "r X~" }, desc = "Weave (or roll) under his punch and come up firing.", counter = true },
	{ id = "slipcounter", name = "SLIP-COUNTER", patterns = { "s X~", "p X~" }, desc = "Slip (or pull) off his punch and fire back before he resets.", counter = true },
	{ id = "duckupper", name = "DUCK-UPPERCUT", patterns = { "d U" }, desc = "Duck under it and drive the uppercut up from the crouch.", counter = true },
	{ id = "stepcounter", name = "STEP-COUNTER", patterns = { "t X~" }, desc = "Side-step out of the line and hit him from the angle.", counter = true },
}

-- signature combos: unlocked by the fight milestones (Moves.FIGHT_STATS: bouts fought, wins, KO wins over the
-- whole career), shown in Moves & Controls; landed by a fighter who owns them they hit harder (SIG_DMG / SIG_HIT).
-- aiTier = the career tier an AI boxer needs (and the same milestone met by its record)
Combos.Signatures = {
	{ id = "sig_bodyattack", name = "BODY ATTACK", patterns = { "1 2b 3b 3" }, fight = { stat = "fights", n = 5 }, aiTier = 2,
		desc = "Jab up top, then the cross and the lead hook into the ribs, and the hook back upstairs as his elbows drop." },
	{ id = "sig_dempsey", name = "DEMPSEY FINISH", patterns = { "3 4 3" }, fight = { stat = "wins", n = 3 }, aiTier = 3,
		desc = "Left hook, right hook, left hook: the finisher's three, rolling the weight side to side." },
	{ id = "sig_fourpiece", name = "FOUR-PIECE", patterns = { "1 2 3 U" }, fight = { stat = "kos", n = 2 }, aiTier = 3,
		desc = "The 1-2-3 with an uppercut on the end for the man who covers up." },
	{ id = "sig_weavehooks", name = "WEAVE & HOOK", patterns = { "w 3 4", "r 3 4" }, fight = { stat = "fights", n = 10 }, aiTier = 4, counter = true,
		desc = "Weave under his shot and come up with both hooks." },
}

Combos.ById = {}
for _, list in ipairs({ Combos.Named, Combos.Signatures }) do
	for _, c in ipairs(list) do
		c.signature = list == Combos.Signatures
		c.parsed = {}
		c.len = 0
		for _, p in ipairs(c.patterns) do
			local parsed = assert(Combos.Parse(p), "bad combo pattern " .. p)
			table.insert(c.parsed, parsed)
			c.len = math.max(c.len, #parsed)
		end
		Combos.ById[c.id] = c
	end
end

-- the combo (and its length) the tail of `tokens` completes at its last token, or nil. sigs = { id = true }: the
-- signature combos this fighter owns. The longest match wins; a signature wins a tie; then list order.
function Combos.Match(tokens, sigs)
	local n = #tokens
	if n < 2 then
		return nil, 0
	end
	local best, bestLen = nil, 0
	local function try(c)
		for _, parsed in ipairs(c.parsed) do
			local len = #parsed
			if len <= n and (len > bestLen or (len == bestLen and c.signature and not (best and best.signature))) then
				local ok = true
				for i = 1, len do
					if not elemMatches(parsed[i], tokens[n - len + i]) then
						ok = false
						break
					end
				end
				if ok then
					best, bestLen = c, len
				end
			end
		end
	end
	if type(sigs) == "table" then
		for _, c in ipairs(Combos.Signatures) do
			if sigs[c.id] then
				try(c)
			end
		end
	end
	for _, c in ipairs(Combos.Named) do
		try(c)
	end
	return best, bestLen
end

------------------------------------------------------------------------
-- The AI's plans: each named / signature combo as the punches FightAI queues ({ p, body }), and how much each
-- style likes them (FightAI.BuildCombo weighs them by its style, picks one that fits the distance; a skilled
-- boxer picks a plan far more often than a few random punches, a raw one keeps them short)
------------------------------------------------------------------------
Combos.Plans = {
	onetwo = { { "jab" }, { "cross" } },
	onetwothree = { { "jab" }, { "cross" }, { "leadhook" } },
	doublejabcross = { { "jab" }, { "jab" }, { "cross" } },
	crosshookcross = { { "cross" }, { "leadhook" }, { "cross" } },
	jabbodyhook = { { "jab" }, { "cross", true }, { "leadhook" } },
	bodyhead = { { "leadhook", true }, { "leadhook" } },
	doublehook = { { "leadhook" }, { "leadhook" } },
	upperhook = { { "uppercut" }, { "leadhook" } },
	hookhook = { { "leadhook" }, { "rearhook" } },
	onetwoupper = { { "jab" }, { "cross" }, { "uppercut" } },
	onetwothreetwo = { { "jab" }, { "cross" }, { "leadhook" }, { "cross" } },
	jaboverhand = { { "jab" }, { "overhand" } },
	sig_bodyattack = { { "jab" }, { "cross", true }, { "leadhook", true }, { "leadhook" } },
	sig_dempsey = { { "leadhook" }, { "rearhook" }, { "leadhook" } },
	sig_fourpiece = { { "jab" }, { "cross" }, { "leadhook" }, { "uppercut" } },
}
Combos.StylePlans = {
	OutBoxer = { onetwo = 3, doublejabcross = 3, onetwothree = 1.5, crosshookcross = 1, jaboverhand = 0.3 },
	Swarmer = { hookhook = 2, bodyhead = 2.5, doublehook = 2, upperhook = 2, jabbodyhook = 1.5, onetwothree = 1 },
	Slugger = { jaboverhand = 2.5, upperhook = 1.5, hookhook = 1.5, onetwo = 1.5, onetwoupper = 1 },
	BoxerPuncher = { onetwo = 2, onetwothree = 2, onetwothreetwo = 1.5, jabbodyhook = 1.5, crosshookcross = 1, onetwoupper = 1 },
	CounterPuncher = { onetwo = 2, crosshookcross = 2, upperhook = 1, doublejabcross = 1, onetwothree = 1 },
}
Combos.SIG_PLAN_WEIGHT = 1.5
-- the share of an AI's combinations that are a plan (skill = (RingIQ + Focus) / 200): 0.25 .. 0.9
function Combos.PlanShare(skill)
	return math.clamp(0.25 + (tonumber(skill) or 0.5) * 0.9, 0.25, 0.9)
end
-- the longest plan a boxer of that skill throws (a raw amateur keeps it to three punches)
function Combos.PlanMax(skill)
	return (tonumber(skill) or 0.5) < 0.45 and 3 or 4
end

------------------------------------------------------------------------
-- Signature unlocks (the fight milestones; info = Moves.Info(profileOrSummary))
------------------------------------------------------------------------
local FIGHT_GOAL = { fights = "Fight %d bouts", wins = "Win %d fights", kos = "Win %d fights by KO" }
local FIGHT_DONE = { fights = "%d bouts fought", wins = "%d wins", kos = "%d KO wins" }

function Combos.SignatureProgress(id, info)
	local c = Combos.ById[id]
	if not (c and c.signature) then
		return nil, nil
	end
	local have = type(info) == "table" and tonumber(info[c.fight.stat]) or 0
	return math.max(0, math.floor(have or 0)), c.fight.n
end

function Combos.SignatureUnlockedBy(id, info)
	local have, need = Combos.SignatureProgress(id, info)
	if need and have >= need then
		return string.format(FIGHT_DONE[Combos.ById[id].fight.stat], need)
	end
	return nil
end

function Combos.SignatureUnlockText(id, info)
	local have, need = Combos.SignatureProgress(id, info)
	if not need then
		return ""
	end
	local s = string.format(FIGHT_GOAL[Combos.ById[id].fight.stat], need)
	if type(info) == "table" then
		s ..= string.format(" (%d/%d)", math.min(have, need), need)
	end
	return s
end

function Combos.UnlockedSignatures(info)
	local out = {}
	for _, c in ipairs(Combos.Signatures) do
		if Combos.SignatureUnlockedBy(c.id, info) then
			out[c.id] = true
		end
	end
	return out
end

-- an AI boxer's signature combos: its tier (from its overall when not given) and its record ({ w, l, d, ko })
function Combos.ForAI(tier, record)
	local out = {}
	tier = tonumber(tier) or 1
	if tier <= 1 then
		return out
	end
	local have = { fights = 0, wins = 0, kos = 0 }
	if type(record) == "table" then
		local w = math.max(0, math.floor(tonumber(record.w) or 0))
		have.wins = w
		have.fights = w + math.max(0, math.floor(tonumber(record.l) or 0)) + math.max(0, math.floor(tonumber(record.d) or 0))
		have.kos = math.min(w, math.max(0, math.floor(tonumber(record.ko) or 0)))
	end
	for _, c in ipairs(Combos.Signatures) do
		if tier >= c.aiTier and (record == nil or have[c.fight.stat] >= c.fight.n) then
			out[c.id] = true
		end
	end
	return out
end

------------------------------------------------------------------------
-- The chain tracker (FightEngine keeps one per fighter; pure so the rules are testable)
------------------------------------------------------------------------
-- a new chain at `now`
function Combos.NewChain(now)
	return { items = {}, punches = 0, landed = 0, blocked = 0, missed = 0, mash = 0, closeAt = now, startAt = now, namedLanded = nil, closed = false }
end

-- is a punch thrown at `now` part of this chain? (busyUntil = the end of the last act's recovery)
function Combos.Continues(chain, now)
	return chain ~= nil and not chain.closed and now <= chain.closeAt
end

-- the tokens of the chain (with one more appended, optional)
function Combos.Tokens(chain, extra)
	local out = {}
	for _, it in ipairs(chain.items) do
		table.insert(out, it.tok)
	end
	if extra then
		table.insert(out, extra)
	end
	return out
end

-- the stamina multiplier of the n-th punch of a chain
function Combos.StamMul(n)
	if n < Combos.STAM_FROM then
		return 1
	end
	return 1 + math.min(Combos.STAM_MAX, (n - Combos.STAM_FROM + 1) * Combos.STAM_STEP)
end

-- add a punch: { tok, p, body, cost, at, windup }. Returns the item, with its position (it.n = punch count),
-- the named combo it completes (it.named, it.namedLen) and its accuracy change (it.hit) and damage multiplier
-- (it.dmg, the named / signature part: the landed ramp is Combos.Ramp at the contact)
function Combos.AddPunch(chain, it, sigs)
	chain.punches += 1
	it.n = chain.punches
	local tokens = Combos.Tokens(chain, it.tok)
	local named, len = Combos.Match(tokens, sigs)
	it.named, it.namedLen = named, len
	local hit, dmg = 0, 1
	if named then
		hit += named.signature and Combos.SIG_HIT or Combos.NAMED_HIT
		dmg *= named.signature and Combos.SIG_DMG or Combos.NAMED_DMG
	end
	-- a level change from the last punch
	local prev
	for i = #chain.items, 1, -1 do
		if not chain.items[i].dodge then
			prev = chain.items[i]
			break
		end
	end
	if prev and (prev.body == true) ~= (it.body == true) then
		hit += Combos.LEVEL_MIX
	end
	-- a long flurry and a predictable one
	if it.n >= Combos.LONG_FROM then
		hit -= math.min(Combos.LONG_MAX, (it.n - Combos.LONG_FROM + 1) * Combos.LONG_STEP)
	end
	if it.p ~= "jab" then
		local same = 0
		for i = #chain.items, 1, -1 do
			local x = chain.items[i]
			if x.dodge or x.p ~= it.p then
				break
			end
			same += 1
		end
		if same >= 2 then
			hit -= Combos.REPEAT * (same - 1)
		end
	end
	hit -= math.min(Combos.MASH_MAX, chain.mash * Combos.MASH)
	it.hit, it.dmg = hit, dmg
	table.insert(chain.items, it)
	return it
end

-- a dodge opening a chain (it made his punch miss): its counter window is the chain window
function Combos.AddDodge(chain, kind, now, window)
	local tok = Combos.DODGE_TOKEN[kind]
	table.insert(chain.items, { tok = tok, dodge = true, kind = kind, res = "landed", at = now })
	chain.closeAt = math.max(chain.closeAt, now + window)
	return tok
end

-- the landed-chain damage ramp for the item at index idx (styleCombo = Config.Styles[].fight.combo)
function Combos.Ramp(chain, it, styleCombo)
	local before = 0
	for _, x in ipairs(chain.items) do
		if x == it then
			break
		end
		if not x.dodge and x.res == "landed" then
			before += 1
		end
	end
	return 1 + math.min(before, Combos.RAMP_MAX) * Combos.RAMP * (tonumber(styleCombo) or 1)
end

-- the punch's result: "landed" | "blocked" | "miss". Returns events: { named = the combo that just landed (nil),
-- broken = the chain ends on the guard, refund = stamina to give back }
function Combos.Result(chain, it, res)
	it.res = res
	local ev = {}
	if res == "landed" then
		chain.landed += 1
	elseif res == "blocked" then
		chain.blocked += 1
		if chain.blocked >= Combos.BLOCK_BREAK and chain.punches >= 2 then
			ev.broken = true
		end
	else
		chain.missed += 1
	end
	if it.named and res == "landed" then
		local len = it.namedLen
		local idx = table.find(chain.items, it) or #chain.items
		local got, cost = 0, 0
		for i = math.max(1, idx - len + 1), idx do
			local x = chain.items[i]
			if x.res == "landed" then
				got += 1
			end
			cost += x.cost or 0
		end
		local need = math.max(2, len - 1)
		if it.named.counter then
			need = len -- (the dodge counts as landed: the counter punch itself must land)
		end
		if got >= need then
			ev.named = it.named
			ev.refund = cost * Combos.REFUND
			local cur = chain.namedLanded
			if not cur or len > cur.len or (len == cur.len and it.named.signature) then
				chain.namedLanded = { id = it.named.id, name = it.named.name, len = len, signature = it.named.signature }
			end
		end
	end
	return ev
end

-- the chain is over: its summary { punches, landed, named = { id, name, len } | nil }
function Combos.Close(chain)
	chain.closed = true
	return { punches = chain.punches, landed = chain.landed, named = chain.namedLanded }
end

------------------------------------------------------------------------
-- Fight stats (FightEngine result: res.combos; the result screen and the rest card show them)
------------------------------------------------------------------------
function Combos.NewStats()
	return { chains = 0, landed = 0, best = 0, bestName = nil, bestLen = 0, named = {} }
end

function Combos.Record(stats, summary)
	if type(summary) ~= "table" or (summary.punches or 0) < 2 and not summary.named then
		return stats
	end
	stats.chains += 1
	stats.best = math.max(stats.best, summary.landed or 0)
	local nm = summary.named
	if nm then
		stats.landed += 1
		stats.named[nm.id] = (stats.named[nm.id] or 0) + 1
		if nm.len > stats.bestLen or (nm.len == stats.bestLen and nm.signature) then
			stats.bestLen, stats.bestName = nm.len, nm.name
		end
	end
	return stats
end

-- the post-fight line: "Best combo: 5 punches (1-2-3-2)  ·  Combos landed: 7"
function Combos.StatsText(stats)
	if type(stats) ~= "table" then
		return nil
	end
	local best = tonumber(stats.best) or 0
	local landed = tonumber(stats.landed) or 0
	if best < 2 and landed == 0 then
		return "Combos landed: 0"
	end
	local name = type(stats.bestName) == "string" and (" (" .. stats.bestName .. ")") or ""
	return string.format("Best combo: %d punch%s%s  ·  Combos landed: %d", best, best == 1 and "" or "es", name, landed)
end

return Combos
