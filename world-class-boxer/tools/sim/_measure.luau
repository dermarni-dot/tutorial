local process = require("@lune/process")
local FS = require("./fightsim")
local root = process.args[1] ~= "-" and process.args[1] or nil
local S = FS.new({ root = root })
local red, blue = process.args[2] or "BoxerPuncher", process.args[3] or "BoxerPuncher"
local bot = process.args[4]
local N = tonumber(process.args[5]) or 16
local lvl = tonumber(process.args[6]) or 60
local w, ko, th, la, oth, ola, secs, ev, oev, kd = 0,0,0,0,0,0,0,0,0,0
for i = 1, N do
	local r = S.Fight({ red = { style = red, level = lvl, noTraits = true, bot = bot }, blue = { style = blue, level = lvl, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
	w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
	if r.method == "KO" or r.method == "TKO" or r.method == "RTD" then ko += 1 end
	th += r.thrown.red; la += r.landed.red; oth += r.thrown.blue; ola += r.landed.blue; secs += r.seconds
	ev += r.P.evades; oev += r.O.evades; kd += r.kd.red + r.kd.blue
end
print(string.format("win %.2f ko %.2f | red acc %.2f %.0f/min | blue acc %.2f %.0f/min | evades %.1f/%.1f | kd/fight %.2f | %.0fs", w/N, ko/N, la/th, th/secs*60, ola/oth, oth/secs*60, ev/N, oev/N, kd/N, secs/N))
