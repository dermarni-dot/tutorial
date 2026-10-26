--!nocheck
-- tools/sim/test_heights.luau: the AI boxers' heights (Config.BoxerHeight / Config.TallNick, World.ApplyHeight /
-- World.MigrateHeights), through tools/sim/fightsim's server modules:
--   * the distribution over whole generated worlds: men 5'4" .. 6'9", women 5'0" .. 6'4", most of the field 5'8" .. 6'1",
--     every division taller on average than the one under it (a heavyweight about 6'4", a flyweight about 5'5") with
--     real spread inside each (short heavyweights, tall middleweights), the extremes present
--   * deterministic per boxer (his id and name): the same world seed gives the same heights, a boxer re-derived after
--     his fights (stats, record, age changed) keeps his, and so does his fight-night data (Career.FighterFromBoxer)
--   * the tall nickname: every boxer 6'5" and up goes by one of Config.TallNicknames (mostly the "Big" ones, varied:
--     "Big D" takes his first initial), nobody shorter does
--   * an older save: World.MigrateHeights gives every stored boxer his height and a tall one his nickname, once
--     (idempotent), keeps everything else, and survives a malformed world; the save loader calls it
--   * the tape: Config.HeightText in feet and inches, the scouting view (Career.OppView) carries the height
--   lune run tools/sim/test_heights.luau [-v]
local process = require("@lune/process")
local fs = require("@lune/fs")
local FS = require("./fightsim")

local verbose = table.find(process.args, "-v") ~= nil
local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local S = FS.new()
local Config, World, Career = S.Config, S.World, S.Career
local Random = S.H.globals.Random
local NCLASS = #Config.WeightClasses

------------------------------------------------------------------------
-- the distribution, over a few whole worlds
------------------------------------------------------------------------
local all, byClass, men, women = {}, {}, {}, {}
for ci = 1, NCLASS do
	byClass[ci] = {}
end
local worlds = {}
for _, seed in ipairs({ 11, 2024, 777, 31337, 5 }) do
	local w = World.Generate(seed)
	table.insert(worlds, w)
	for _, b in pairs(w.boxers) do
		table.insert(all, b)
		if b.gender == 2 then
			table.insert(women, b.height)
		else
			table.insert(men, b.height)
			table.insert(byClass[b.class], b.height)
		end
	end
end
local function stats(list)
	local s, n = 0, #list
	for _, v in ipairs(list) do
		s += v
	end
	local mean = s / math.max(1, n)
	local v2 = 0
	for _, v in ipairs(list) do
		v2 += (v - mean) ^ 2
	end
	local lo, hi = math.huge, -math.huge
	for _, v in ipairs(list) do
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	return mean, math.sqrt(v2 / math.max(1, n - 1)), lo, hi
end
local function share(list, a, b)
	local k = 0
	for _, v in ipairs(list) do
		if v >= a and v <= b then
			k += 1
		end
	end
	return k / math.max(1, #list)
end
local mMean, _, mLo, mHi = stats(men)
local _, _, wLo, wHi = stats(women)
check(string.format("distribution: the men run 5'4\" .. 6'9\" (%d .. %d in)", mLo, mHi), mLo >= 64 and mHi <= 81)
check(string.format("distribution: the extremes are there (shortest man %d, tallest %d)", mLo, mHi), mLo <= 64 and mHi >= 80)
check(string.format("distribution: the women run 5'0\" .. 6'4\" (%d .. %d in)", wLo, wHi), wLo >= 60 and wHi <= 76)
local mid = share(men, 68, 73)
check(string.format("distribution: most of the men are 5'8\" .. 6'1\" (%.0f%%)", mid * 100), mid >= 0.45)
check(string.format("distribution: not all of them are within an inch or two of 5'10\" (%.0f%% at 5'9\" .. 5'11\")", share(men, 69, 71) * 100), share(men, 69, 71) <= 0.4)
check(string.format("distribution: the mean man about 5'10\" (%.1f in)", mMean), mMean >= 68.5 and mMean <= 71.5)
local last = -math.huge
local mono = true
for ci = 1, NCLASS do
	local mean, sd, lo, hi = stats(byClass[ci])
	if verbose then
		print(string.format("  %-18s n %3d mean %.1f sd %.1f  %s .. %s", Config.WeightClasses[ci].name, #byClass[ci], mean, sd, Config.HeightText(lo), Config.HeightText(hi)))
	end
	if mean <= last then
		mono = false
	end
	last = mean
	check(string.format("distribution: %s has real spread (sd %.1f, %d .. %d)", Config.WeightClasses[ci].name, sd, lo, hi), sd >= 1.3 and hi - lo >= 5)
end
check("distribution: every division taller on average than the one under it", mono)
local hMean, _, hLo, hHi = stats(byClass[NCLASS])
local fMean = stats(byClass[1])
check(string.format("distribution: a heavyweight about 6'4\" (%.1f in), a flyweight about 5'5\" (%.1f)", hMean, fMean), hMean >= 74.5 and hMean <= 77 and fMean >= 64 and fMean <= 66.5)
check(string.format("distribution: heavyweights from 6' and under to 6'8\"+ (%d .. %d)", hLo, hHi), hLo <= 72 and hHi >= 80)
check(string.format("distribution: a tall heavyweight is common, a tall flyweight is not (%.0f%% vs %.0f%% at 6'5\"+)", share(byClass[NCLASS], 77, 99) * 100,
	share(byClass[1], 77, 99) * 100), share(byClass[NCLASS], 77, 99) >= 0.2 and share(byClass[1], 77, 99) == 0)

------------------------------------------------------------------------
-- deterministic per boxer
------------------------------------------------------------------------
do
	local a, b = World.Generate(2024), World.Generate(2024)
	local same = true
	for id, x in pairs(a.boxers) do
		local y = b.boxers[id]
		if not y or y.height ~= x.height or y.nick ~= x.nick or y.name ~= x.name then
			same = false
		end
	end
	check("determinism: the same world seed, the same heights and nicknames", same)
	local stable, fighter = true, true
	for _, x in pairs(a.boxers) do
		local h, n = x.height, x.nick
		-- (his fights, his ageing, a new record: none of it moves his height)
		x.stats.Power += 5
		x.record.w += 3
		x.age += 2
		x.overall = Config.Overall(x.stats)
		World.ApplyHeight(x)
		if x.height ~= h or x.nick ~= n then
			stable = false
		end
		local d1, d2 = Career.FighterFromBoxer(x), Career.FighterFromBoxer(x)
		if d1.height ~= h or d2.height ~= h or d1.nick ~= n or d1.app.height ~= h then
			fighter = false
		end
	end
	check("determinism: a boxer keeps his height and nickname after his fights", stable)
	check("determinism: his fight-night data carries it, every fight (the rig's height too)", fighter)
	-- (by id and name: the same id in another world - another man - is not the same height every time)
	local differ = 0
	for id, x in pairs(a.boxers) do
		local o = worlds[1].boxers[id]
		if o and o.name ~= x.name and o.height ~= x.height then
			differ += 1
		end
	end
	check(string.format("determinism: keyed on the man, not the id slot (%d ids differ between two worlds)", differ), differ > 100)
	check("determinism: Config.BoxerHeight is a pure function", Config.BoxerHeight("b7|Marcus Reed", 9, false) == Config.BoxerHeight("b7|Marcus Reed", 9, false)
		and Config.TallNick("b7|x", 80, "Darnell") == Config.TallNick("b7|x", 80, "Darnell"))
	-- the tutorial's one-off boxers (World.RandomBoxer) are drawn the same way
	local t1 = World.RandomBoxer(Random.new(99), 9, 50)
	local t2 = World.RandomBoxer(Random.new(99), 9, 50)
	check("determinism: the tutorial's random boxer too", t1.height == t2.height and t1.height == Config.BoxerHeight(World.HeightKey(t1), 9, t1.gender == 2) and t1.heightV == World.HEIGHT_V)
	local tf = World.RandomBoxer(Random.new(3), 9, 50, { female = true })
	check("determinism: a forced-gender tutorial boxer's height is a woman's, under her new name", tf.gender == 2 and tf.height == Config.BoxerHeight(World.HeightKey(tf), 9, true))
end

------------------------------------------------------------------------
-- the tall nickname
------------------------------------------------------------------------
do
	local tallN, wrong, shortTall, bigs, initials, initialOk = 0, 0, 0, 0, 0, true
	local kinds = {}
	local formats = {}
	for _, f in ipairs(Config.TallNicknames) do
		formats[f] = true
	end
	for _, b in ipairs(all) do
		if b.height >= Config.TALL_INCHES then
			tallN += 1
			if not Config.IsTallNick(b.nick) then
				wrong += 1
				print("  not a tall nickname: " .. b.name .. " " .. b.height .. " in \"" .. tostring(b.nick) .. "\"")
			end
			kinds[b.nick] = true
			if b.nick:find("Big", 1, true) then
				bigs += 1
			end
			local ini = b.nick:match("^Big (%u)$")
			if ini then
				initials += 1
				if ini ~= b.name:sub(1, 1):upper() then
					initialOk = false
				end
			end
		elseif Config.IsTallNick(b.nick) then
			shortTall += 1
		end
	end
	local nk = 0
	for _ in pairs(kinds) do
		nk += 1
	end
	check(string.format("tall nickname: %d boxers are 6'5\"+ across the worlds", tallN), tallN >= 30)
	check("tall nickname: every one of them goes by a tall nickname", wrong == 0, wrong)
	check("tall nickname: nobody under 6'5\" does", shortTall == 0, shortTall)
	check(string.format("tall nickname: mostly the \"Big\" ones (%.0f%%)", bigs / math.max(1, tallN) * 100), bigs / math.max(1, tallN) >= 0.5)
	check(string.format("tall nickname: varied (%d different)", nk), nk >= 10)
	check(string.format("tall nickname: \"Big D\" is his first initial (%d of them)", initials), initials > 0 and initialOk)
	check("tall nickname: the list has the towers and the giants", formats["The Tower"] and formats["Skyscraper"] and formats["Long"] and formats["The Giant"] and formats["Big"])
	-- (a name with no letter to take an initial from falls back to plain "Big")
	check("tall nickname: an odd name still gets one", Config.TallNick("k1", 80, "") ~= nil and not tostring(Config.TallNick("k2", 80, "")):find("%%"))
	check("tall nickname: 6'4\" is not tall enough", Config.TallNick("k3", 76, "Darnell") == nil and Config.TallNick("k3", 77, "Darnell") ~= nil)
	local ex
	for _, b in ipairs(all) do
		if b.height >= Config.TALL_INCHES then
			ex = ex or {}
			if #ex < 5 then
				table.insert(ex, string.format("%s \"%s\" %s (%s)", b.name:match("^(%S+)"), b.nick, b.name:match("%s(.+)$"), Config.HeightText(b.height)))
			end
		end
	end
	if verbose and ex then
		print("  e.g. " .. table.concat(ex, ", "))
	end
end

------------------------------------------------------------------------
-- an older save's world
------------------------------------------------------------------------
do
	local w = World.Generate(4242)
	-- (as a save from before the varied heights stored it: 60 + 1.6 x class +- 3, the generated nickname, no marker)
	local rng = Random.new(1)
	local before = {}
	for id, b in pairs(w.boxers) do
		b.height = math.clamp(60 + b.class * 1.6 + rng:NextInteger(-3, 3), 60, 84)
		b.nick = b.ownNick or b.nick
		b.ownNick, b.heightV = nil, nil
		before[id] = { nick = b.nick, overall = b.overall, record = b.record.w, name = b.name }
	end
	local n = World.MigrateHeights(w)
	local count = 0
	for _ in pairs(w.boxers) do
		count += 1
	end
	check(string.format("migration: every stored boxer brought up to date (%d of %d)", n, count), n == count)
	local ok, kept = true, true
	for id, b in pairs(w.boxers) do
		local want = Config.BoxerHeight(World.HeightKey(b), b.class, b.gender == 2)
		if b.height ~= want or b.heightV ~= World.HEIGHT_V then
			ok = false
		end
		if b.height >= Config.TALL_INCHES then
			if not Config.IsTallNick(b.nick) or b.ownNick ~= before[id].nick then
				ok = false
			end
		elseif b.nick ~= before[id].nick then
			ok = false
		end
		if b.overall ~= before[id].overall or b.record.w ~= before[id].record or b.name ~= before[id].name then
			kept = false
		end
	end
	check("migration: the heights and tall nicknames a new world would give them", ok)
	check("migration: nothing else changes (name, stats, record)", kept)
	check("migration: idempotent (a second load changes nobody)", World.MigrateHeights(w) == 0)
	local snap = {}
	for id, b in pairs(w.boxers) do
		snap[id] = b.height .. "|" .. b.nick
	end
	World.MigrateHeights(w)
	local same = true
	for id, b in pairs(w.boxers) do
		if snap[id] ~= b.height .. "|" .. b.nick then
			same = false
		end
	end
	check("migration: a boxer keeps his height across saves", same)
	local okNil = pcall(World.MigrateHeights, nil) and pcall(World.MigrateHeights, {}) and pcall(World.MigrateHeights, { boxers = { x = { name = "Odd" }, y = 5 } })
	check("migration: a malformed world does not error", okNil)
	local odd = { boxers = { x = { name = "Odd One" } } }
	World.MigrateHeights(odd)
	check("migration: a boxer missing his class and id still gets a height", type(odd.boxers.x.height) == "number" and odd.boxers.x.id == "x")
	local dm = fs.readFile(S.H.src .. "/server/DataManager.lua")
	check("migration: the save loader runs it (guarded)", dm:find("pcall(World.MigrateHeights, data.world)", 1, true) ~= nil)
end

------------------------------------------------------------------------
-- the tape and the scouting view
------------------------------------------------------------------------
check("tape: feet and inches", Config.HeightText(77) == "6'5\"" and Config.HeightText(64) == "5'4\"" and Config.HeightText(81) == "6'9\"")
do
	local w = World.Generate(9)
	local b
	for _, x in pairs(w.boxers) do
		b = x
		break
	end
	local profile = { tier = 1, world = w }
	local v = Career.OppView(profile, b)
	check("tape: the scouting view carries his height", v.height == b.height)
	local d = Career.FighterFromBoxer(b)
	local f = S.NewFight(d, S.Boxer({}, Random.new(1)), 3, 1)
	check("tape: the fight's data has it for the tale of the tape", f.P.data.height == b.height)
end

print(string.format("test_heights: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
