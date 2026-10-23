--!nocheck
-- (temporary bench: AI work rate / accuracy and bot win rates; args: root|- N levels bots)
local process = require("@lune/process")
local FS = require("./fightsim")
local root = process.args[1] ~= "-" and process.args[1] or nil
local S = FS.new({ root = root })
local N = tonumber(process.args[2]) or 12
local LV = {}
for v in string.gmatch(process.args[3] or "20,40,60,80", "[^,]+") do table.insert(LV, tonumber(v)) end
local BOTS = {}
for v in string.gmatch(process.args[4] or "smart,volume,pressure,counter,spam", "[^,]+") do table.insert(BOTS, v) end
-- args[5]: a chunk run with AIC = Config.FightAI (ablations)
if process.args[5] and process.args[5] ~= "" then
	local luau = require("@lune/luau")
	local fn = luau.load(process.args[5], { environment = setmetatable({ AIC = S.Config.FightAI, S = S }, { __index = _G }) })
	fn()
end
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
for _, lvl in ipairs(LV) do
	for _, bot in ipairs(BOTS) do
		local w, th, la, secs, ko, rnd = 0, 0, 0, 0, 0, 0
		local bth, bla = 0, 0
		for i = 1, N do
			local r
			if bot == "ai" then
				r = S.Fight({ red = { style = "BoxerPuncher", level = lvl, noTraits = true }, blue = { style = STYLES[(i % 5) + 1], level = lvl, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
			else
				r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STYLES[(i % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13 })
			end
			w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
			if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then ko += 1 end
			rnd += r.round
			th += r.thrown.blue; la += r.landed.blue; secs += r.seconds
			bth += r.thrown.red; bla += r.landed.red
		end
		print(string.format("L%2d %-9s red win %3d%% ko %3d%% r%.1f | AI %5.1f/min acc %4.1f%% | red %5.1f/min acc %4.1f%%", lvl, bot, math.floor(w / N * 100 + 0.5), math.floor(ko / N * 100 + 0.5), rnd / N, th / secs * 60, la / math.max(1, th) * 100, bth / secs * 60, bla / math.max(1, bth) * 100))
	end
end
