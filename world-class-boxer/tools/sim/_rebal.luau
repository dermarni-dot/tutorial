--!nocheck
-- temporary: rebalance measurement.  lune run _rebal.luau <mode> <n> [--root DIR]
local process = require("@lune/process")
local FS = require("./fightsim")
local ROOT, args = nil, {}
for i = 1, #process.args do
	if process.args[i] == "--root" then ROOT = process.args[i + 1]
	elseif process.args[i - 1] ~= "--root" then table.insert(args, process.args[i]) end
end
local S = FS.new({ root = ROOT })
-- --set Damage.head=0.27,KO.count.aiUp=0.5 (Config paths)
do
	local at = table.find(args, "--set")
	if at then
		for kv in args[at + 1]:gmatch("[^,]+") do
			local path, v = kv:match("^(.-)=(.*)$")
			local t, keys = S.Config, {}
			if path:sub(1, 3) == "FT." then
				t = S.H.require("FrameTraits").Data
				path = path:sub(4)
			end
			for k in path:gmatch("[^%.]+") do table.insert(keys, tonumber(k) or k) end
			for i = 1, #keys - 1 do t = t[keys[i]] end
			t[keys[#keys]] = tonumber(v)
		end
		table.remove(args, at + 1)
		table.remove(args, at)
	end
end
local MODE, N = args[1] or "pace", tonumber(args[2]) or 48
local SEED0 = tonumber(process.env.SEED0 or "") or 0
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local function run(n, spec, seed0)
	local st = { w = 0, ko = 0, rounds = 0, secs = 0, th = 0, la = 0, kd = 0, dmg = 0, early = 0, r1kd = 0 }
	for i = 1, n do
		local sp = spec(i)
		sp.seed = (seed0 or SEED0) + i * 7919 + 13
		local r = S.Fight(sp)
		st.w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
		if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then
			st.ko += 1
			if r.round <= 2 then st.early += 1 end
		end
		st.rounds += r.round
		st.secs += r.seconds
		st.th += r.thrown.red + r.thrown.blue
		st.la += r.landed.red + r.landed.blue
		st.kd += (r.kd.red or 0) + (r.kd.blue or 0)
		st.dmg += (r.P.damageTaken or 0) + (r.O.damageTaken or 0)
	end
	return st
end
local function fmt(st, n)
	return string.format("ppm %4.1f  landed %3.0f%%  rounds %.2f  stop %3.0f%% (r1-2 %3.0f%%)  kd/fight %.2f  dmg/landed %.2f  redwin %3.0f%%",
		st.th / math.max(1, st.secs) * 30, st.la / math.max(1, st.th) * 100, st.rounds / n, st.ko / n * 100, st.early / n * 100, st.kd / n, st.dmg / math.max(1, st.la), st.w / n * 100)
end
if MODE == "pace" then
	for _, lvl in ipairs({ 60, 40, 80 }) do
		local st = run(N, function(i) return { red = { style = STYLES[(i % 5) + 1], level = lvl }, blue = { style = STYLES[((i + 2) % 5) + 1], level = lvl }, rounds = 6 } end)
		print(string.format("AIvAI L%d mixed traits  %s", lvl, fmt(st, N)))
	end
	local st = run(N, function() return { red = { style = "BoxerPuncher", level = 60, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6 } end)
	print(string.format("AIvAI L60 B-P mirror    %s", fmt(st, N)))
elseif MODE == "bots" then
	local lv = tonumber(args[3])
	local bots = args[4] and string.split(args[4], ",") or { "smart", "volume", "pressure", "counter", "spam", "novice" }
	for _, lvl in ipairs(lv and { lv } or { 20, 40, 60, 80 }) do
		local line = string.format("L%2d ", lvl)
		for _, bot in ipairs(bots) do
			local st = run(N, function(i) return { red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STYLES[(i % 5) + 1], level = lvl }, rounds = 6 } end)
			line ..= string.format(" %s %3.0f%% (r%.1f)", bot, st.w / N * 100, st.rounds / N)
		end
		print(line)
	end
end
if MODE == "diag" then
	local bot, lvl = args[3] or "pressure", tonumber(args[4]) or 60
	local FightAI = S.FightAI
	local notes, modes = {}, {}
	local orig = FightAI.Note
	FightAI.Note = function(self, now, why)
		if self.F == self.engine.O then
			local k = why:gsub("[%d%.]+", "#")
			notes[k] = (notes[k] or 0) + 1
			modes[self.mode] = (modes[self.mode] or 0) + 1
		end
		return orig(self, now, why)
	end
	local agg = { bt = 0, bl = 0, at = 0, al = 0, bd = 0, ad = 0, bkd = 0, akd = 0, w = 0, rounds = 0, secs = 0, blockT = 0 }
	local meth = {}
	for i = 1, N do
		local r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STYLES[(i % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13 })
		agg.bt += r.thrown.red; agg.bl += r.landed.red; agg.at += r.thrown.blue; agg.al += r.landed.blue
		agg.bd += r.P.damageDealt; agg.ad += r.O.damageDealt
		agg.bkd += r.kd.red or 0; agg.akd += r.kd.blue or 0
		agg.w += r.winner == "red" and 1 or 0; agg.rounds += r.round; agg.secs += r.seconds
		agg.blockT += r.O.blockTime or 0
		for _, kd in ipairs(r.fight.knockdowns) do
			local key = kd.who .. ":" .. kd.severity .. "/" .. tostring(kd.cause) .. "/r" .. kd.round
			meth[key] = (meth[key] or 0) + 1
		end
		local m = (r.winner == "red" and "bot " or "ai ") .. tostring(r.fight.reason or r.method)
		meth[m] = (meth[m] or 0) + 1
	end
	local mins = agg.secs / 60
	print(string.format("%s L%d: bot win %.0f%% rounds %.2f | bot %.1f ppm %.0f%% landed dmg/min %.1f kd %.2f | AI %.1f ppm %.0f%% landed dmg/min %.1f kd %.2f | AI block %.0f%% of time",
		bot, lvl, agg.w / N * 100, agg.rounds / N, agg.bt / mins, agg.bl / math.max(1, agg.bt) * 100, agg.bd / mins, agg.bkd / N, agg.at / mins, agg.al / math.max(1, agg.at) * 100, agg.ad / mins, agg.akd / N, agg.blockT / agg.secs * 100))
	local ks = {}
	for k, v in pairs(meth) do table.insert(ks, k .. "=" .. v) end
	print("methods: " .. table.concat(ks, " "))
	local arr = {}
	for k, v in pairs(notes) do table.insert(arr, { k, v }) end
	table.sort(arr, function(a, b) return a[2] > b[2] end)
	local tot = 0
	for _, x in ipairs(arr) do tot += x[2] end
	for i = 1, math.min(22, #arr) do print(string.format("  %5.1f%% %s", arr[i][2] / tot * 100, arr[i][1])) end
	local ms = {}
	for k, v in pairs(modes) do table.insert(ms, string.format("%s %.0f%%", k, v / tot * 100)) end
	print("modes: " .. table.concat(ms, " "))
end
if MODE == "why" then
	local lvl = tonumber(args[3]) or 60
	local reasons, sev, kdRound, endRound = {}, {}, {}, {}
	local conc, hp, tierTime = 0, 0, 0
	for i = 1, N do
		local r = S.Fight({ red = { style = STYLES[(i % 5) + 1], level = lvl }, blue = { style = STYLES[((i + 2) % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13 })
		local f = r.fight
		local k = tostring(f.reason or r.method)
		reasons[k] = (reasons[k] or 0) + 1
		for _, kd in ipairs(f.knockdowns) do
			local key = kd.severity .. "/" .. tostring(kd.cause)
			sev[key] = (sev[key] or 0) + 1
			kdRound[kd.round] = (kdRound[kd.round] or 0) + 1
		end
		if f.finished then endRound[r.round] = (endRound[r.round] or 0) + 1 end
		local L = r.winner == "red" and r.O or r.P
		conc += L.concPeak
		hp += L.healthCap
	end
	local function dump(t, label)
		local a = {}
		for k, v in pairs(t) do table.insert(a, tostring(k) .. "=" .. v) end
		table.sort(a)
		print(label .. table.concat(a, "  "))
	end
	dump(reasons, "end: ")
	dump(sev, "kd severity/cause: ")
	dump(kdRound, "kd by round: ")
	dump(endRound, "stoppage by round: ")
	print(string.format("loser concPeak %.2f healthCap %.0f", conc / N, hp / N))
end
if MODE == "count" then
	local Fight = S.FightEngine._Fight
	local orig = Fight.GetUpAbility
	local rows = {}
	Fight.GetUpAbility = function(self, F)
		local a = orig(self, F)
		if not rows[F] then
			table.insert(rows, string.format("kd#%d sev %-6s ab %.2f hp %4.1f conc %.2f chin %d comp %d rec %d", F.kdTotal, tostring(F.downSeverity), a, F.health, F.conc, F.data.stats.Chin, F.data.mental.Composure, F.data.stats.Recovery))
		end
		return a
	end
	for i = 1, N do
		S.Fight({ red = { style = STYLES[(i % 5) + 1], level = 60 }, blue = { style = STYLES[((i + 2) % 5) + 1], level = 60 }, rounds = 6, seed = i * 7919 + 13 })
	end
	for i = 1, math.min(40, #rows) do print(rows[i]) end
end
if MODE == "frame" then
	local A, B = args[3] or "Heavyweight Build", args[4] or "Lean"
	local w, koA, koB, decA, decB, stop = 0, 0, 0, 0, 0, 0
	for i = 1, N do
		local flip = i % 2 == 0
		local ra, rb = flip and B or A, flip and A or B
		local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true, frame = ra }, blue = { style = "BoxerPuncher", level = 60, noTraits = true, frame = rb }, rounds = 6, seed = SEED0 + i * 7919 + 13 })
		local aWon = (r.winner == "red") ~= flip
		local ko = r.method == "KO" or r.method == "TKO" or r.method == "RTD"
		if ko then stop += 1 end
		if r.winner == "draw" then w += 0.5
		elseif aWon then w += 1; if ko then koA += 1 else decA += 1 end
		else if ko then koB += 1 else decB += 1 end end
	end
	print(string.format("%s vs %s: %s wins %.0f%% (KO %d, pts %d) - %s KO %d pts %d; stoppages %.0f%%", A, B, A, w / N * 100, koA, decA, B, koB, decB, stop / N * 100))
end
if MODE == "edge" then
	local bot, trait = args[3], args[4]
	local function edge(withT)
		local d, t = 0, 0
		for i = 1, N do
			local r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60, traits = withT and { { id = trait, s = 1 } } or nil, noTraits = not withT or nil }, rounds = 6, seed = SEED0 + i * 7919 + 13 })
			d += r.P.damageDealt; t += r.P.damageTaken
		end
		return d / math.max(1e-6, t)
	end
	local wo, wi = edge(false), edge(true)
	print(string.format("edge %s/%s: without %.2f with %.2f ratio %.2f", bot, trait, wo, wi, wi / wo))
end
