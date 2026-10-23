--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local bot = process.args[1] or "volume"
local lvl = tonumber(process.args[2]) or 20
local N = tonumber(process.args[3]) or 20
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local st, stB, n = 0, 0, 0
local lossR = {}
local wins = 0
local bySty = {}
for i = 1, N do
	local r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STY[(i % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f)
			if f.live then
				st += f.O.stamina / f.O.maxStam; stB += f.P.stamina / f.P.maxStam; n += 1
			end
		end })
	local sty = STY[(i % 5) + 1]
	bySty[sty] = bySty[sty] or { 0, 0 }
	bySty[sty][2] += 1
	if r.winner == "red" then wins += 1; bySty[sty][1] += 1; lossR[r.round] = (lossR[r.round] or 0) + 1 end
end
print(string.format("bot wins %d/%d; AI stamina avg %.2f, bot %.2f", wins, N, st / n, stB / n))
local t = {}
for k, v in pairs(bySty) do table.insert(t, string.format("%s %d/%d", k, v[1], v[2])) end
print("bot wins vs AI style: " .. table.concat(t, ", "))
local t2 = {}
for k, v in pairs(lossR) do table.insert(t2, string.format("r%d:%d", k, v)) end
print("AI losses by round: " .. table.concat(t2, " "))
