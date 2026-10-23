--!nocheck
-- landed % and win rates: AI vs AI by style (level 60, 6 rounds) and scripted bots vs the AI
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local N = tonumber(process.args[1]) or 10
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local function run(label, spec)
	local lr, tr, lb, tb, w, secs = 0, 0, 0, 0, 0, 0
	for i = 1, N do
		local sp = spec(i)
		sp.seed = i * 7919 + 13
		local r = S.Fight(sp)
		lr += r.landed.red; tr += r.thrown.red; lb += r.landed.blue; tb += r.thrown.blue
		w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
		secs += r.seconds
	end
	print(string.format("%-28s red %5.1f%% (%d/%d)  blue %5.1f%% (%d/%d)  red wins %4.2f  %4.0fs", label,
		100 * lr / math.max(1, tr), lr, tr, 100 * lb / math.max(1, tb), lb, tb, w / N, secs / N))
end
for i, st in ipairs(STYLES) do
	local o = STYLES[(i % 5) + 1]
	run(st .. " v " .. o, function() return { red = { style = st, level = 60, noTraits = true }, blue = { style = o, level = 60, noTraits = true }, rounds = 6 } end)
end
for _, bot in ipairs({ "smart", "volume", "pressure", "counter", "spam" }) do
	run("bot " .. bot .. " v AI", function(i) return { red = { bot = bot, style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60 }, rounds = 6 } end)
end
