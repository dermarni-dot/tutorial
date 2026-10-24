--!nocheck
-- tools/sim/balance.luau: the fight balance tables (tools/sim/fightsim: the real engine and FightAI, headless).
--   lune run tools/sim/balance.luau [n]          n fights a cell (default 40)
--   lune run tools/sim/balance.luau 40 styles    only one table: pace | styles | levels | bots | traits | adapt
--   lune run tools/sim/balance.luau 40 styles --root /tmp/before   the same on an export of an older commit
-- Prints, for each table, the red corner's win rate, the knockout share and the average fight length.
local process = require("@lune/process")
local FS = require("./fightsim")
-- --root DIR: run the tables on another checkout (an export of an older commit: the "before")
local ROOT = nil
local args = {}
for i = 1, #process.args do
	if process.args[i] == "--root" then
		ROOT = process.args[i + 1]
	elseif process.args[i - 1] ~= "--root" then
		table.insert(args, process.args[i])
	end
end
local S = FS.new({ root = ROOT })

local N = tonumber(args[1]) or 40
local ONLY = args[2]
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local SHORT = { OutBoxer = "OUT", Swarmer = "SWA", Slugger = "SLU", BoxerPuncher = "B-P", CounterPuncher = "CTR" }

-- n fights of spec(seed) -> the red corner's wins (a draw is half), the stoppages, the average seconds
local function run(n, spec)
	local w, ko, secs, rounds = 0, 0, 0, 0
	for i = 1, n do
		local sp = spec(i)
		sp.seed = sp.seed or (i * 7919 + 13)
		local r = S.Fight(sp)
		if r.winner == "red" then
			w += 1
		elseif r.winner == "draw" then
			w += 0.5
		end
		if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then
			ko += 1
		end
		secs += r.seconds
		rounds += r.round
	end
	return { win = w / n, ko = ko / n, secs = secs / n, rounds = rounds / n }
end
local function pct(x)
	return string.format("%3d%%", math.floor(x * 100 + 0.5))
end
local function cell(st)
	return string.format("%s ko %s %4.1fr", pct(st.win), pct(st.ko), st.rounds)
end
S.results = {}

if not ONLY or ONLY == "pace" then
	-- the fight's pace at equal level (mixed styles, traits on, 6 rounds: the bands of tools/sim/test_fightai): punches a
	-- minute a man, the landed share, the rounds, the stoppages (and those in rounds 1-2), knockdowns a fight, damage
	-- a landed punch (head + half the body)
	print(string.format("\n== the pace at equal level (AI vs AI, mixed styles, traits on, 6 rounds), %d a cell", N))
	for _, lvl in ipairs({ 40, 60, 80 }) do
		local th, la, secs, rounds, ko, early, kd, dmg = 0, 0, 0, 0, 0, 0, 0, 0
		for i = 1, N do
			local r = S.Fight({ red = { style = STYLES[(i % 5) + 1], level = lvl }, blue = { style = STYLES[((i + 2) % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13 })
			th += r.thrown.red + r.thrown.blue
			la += r.landed.red + r.landed.blue
			secs += r.seconds
			rounds += r.round
			if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then
				ko += 1
				early += r.round <= 2 and 1 or 0
			end
			kd += (r.kd.red or 0) + (r.kd.blue or 0)
			dmg += r.P.damageTaken + r.O.damageTaken
		end
		print(string.format("level %d: %4.1f a minute, %s landed, %.2f rounds, stoppages %s (rounds 1-2 %s), %.2f knockdowns, %.2f damage a landed punch",
			lvl, th / math.max(1, secs) * 30, pct(la / math.max(1, th)), rounds / N, pct(ko / N), pct(early / N), kd / N, dmg / math.max(1, la)))
	end
end

if not ONLY or ONLY == "styles" then
	print(string.format("\n== AI vs AI by style (level 60, no traits, 6 rounds; red win %% | stoppages | rounds), %d a cell", N))
	local head = "red \\ blue  "
	for _, b in ipairs(STYLES) do
		head ..= string.format("%-20s", SHORT[b])
	end
	print(head)
	for _, a in ipairs(STYLES) do
		local line = string.format("%-12s", SHORT[a])
		for _, b in ipairs(STYLES) do
			local st = run(N, function()
				return { red = { style = a, level = 60, noTraits = true }, blue = { style = b, level = 60, noTraits = true }, rounds = 6 }
			end)
			line ..= string.format("%-20s", cell(st))
		end
		print(line)
	end
end

if not ONLY or ONLY == "levels" then
	print(string.format("\n== AI vs AI by level gap (Boxer-Puncher vs Boxer-Puncher, 6 rounds), %d a cell", N))
	for _, gap in ipairs({ -15, -8, -4, 0, 4, 8, 15 }) do
		local st = run(N, function()
			return { red = { style = "BoxerPuncher", level = 60 + gap, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6 }
		end)
		print(string.format("red %+3d: %s  (%.0f s)", gap, cell(st), st.secs))
	end
end

if not ONLY or ONLY == "bots" then
	print(string.format("\n== scripted players vs the AI (same level, the AI's own traits from its seed, 6 rounds), %d a cell", N))
	for _, lvl in ipairs({ 20, 40, 60, 80 }) do
		local line = string.format("level %2d  ", lvl)
		for _, bot in ipairs({ "novice", "spam", "headhunter", "body", "volume", "power", "counter", "pressure", "smart" }) do
			local st = run(N, function(i)
				return { red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STYLES[(i % #STYLES) + 1], level = lvl }, rounds = 6 }
			end)
			line ..= string.format("%s %s  ", bot, pct(st.win))
		end
		print(line)
	end
end

if not ONLY or ONLY == "traits" then
	print(string.format("\n== each trait (full strength) against the scripted types it resists, vs the same AI without it (level 60), %d a cell", N))
	local BOTS = { "headhunter", "body", "volume", "power", "pressure", "spam", "smart" }
	local line = string.format("%-18s", "trait \\ bot")
	for _, b in ipairs(BOTS) do
		line ..= string.format("%-12s", b)
	end
	print(line)
	local base = {}
	for _, b in ipairs(BOTS) do
		base[b] = run(N, function(i)
			return { red = { bot = b, style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % #STYLES) + 1], level = 60, noTraits = true }, rounds = 6 }
		end).win
	end
	line = string.format("%-18s", "(none)")
	for _, b in ipairs(BOTS) do
		line ..= string.format("%-12s", pct(base[b]))
	end
	print(line)
	for _, t in ipairs(S.Traits.List) do
		line = string.format("%-18s", t)
		for _, b in ipairs(BOTS) do
			local st = run(N, function(i)
				return { red = { bot = b, style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % #STYLES) + 1], level = 60, traits = { { id = t, s = 1 } } }, rounds = 6 }
			end)
			line ..= string.format("%-12s", string.format("%s %+d", pct(st.win), math.floor((st.win - base[b]) * 100 + 0.5)))
		end
		print(line)
	end
end

if not ONLY or ONLY == "adapt" then
	print(string.format("\n== the counter to each trait: the smart player adapting to the hints vs a stubborn one (level 60), %d a cell", N))
	for _, t in ipairs(S.Traits.List) do
		local stub = run(N, function(i)
			return { red = { bot = "headhunter", style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % #STYLES) + 1], level = 60, traits = { { id = t, s = 1 } } }, rounds = 6 }
		end)
		local smart = run(N, function(i)
			return { red = { bot = "smart", style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % #STYLES) + 1], level = 60, traits = { { id = t, s = 1 } } }, rounds = 6 }
		end)
		print(string.format("%-18s head-hunter %s   adapting %s", t, pct(stub.win), pct(smart.win)))
	end
end
