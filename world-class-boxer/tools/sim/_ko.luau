--!nocheck
local FS = require("./fightsim")
local process = require("@lune/process")
local S = FS.new({ root = (process.args[1] ~= "" and process.args[1]) or nil })
if process.args[2] and process.args[2] ~= "" then
	local luau = require("@lune/luau")
	luau.load(process.args[2], { environment = setmetatable({ AIC = S.Config.FightAI, S = S }, { __index = _G }) })()
end
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local m, rounds, kds, n = {}, {}, 0, 24
local firstKD = 0
local th, la, dmg, secs, ctr = 0, 0, 0, 0, 0
for i = 1, n do
	local t0 = nil
	local r = S.Fight({ red = { style = STY[(i % 5) + 1], level = 60 }, blue = { style = STY[((i + 2) % 5) + 1], level = 60 }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f, clock)
			if not t0 and (f.P.kdTotal or 0) + (f.O.kdTotal or 0) > 0 then t0 = (f.round - 1) * 60 + (60 - (f.roundEnd - clock)) end
		end })
	m[r.method] = (m[r.method] or 0) + 1
	rounds[r.round] = (rounds[r.round] or 0) + 1
	kds += r.kd.red + r.kd.blue
	firstKD += t0 or 360
	th += r.thrown.red + r.thrown.blue; la += r.landed.red + r.landed.blue; dmg += r.P.damageDealt + r.O.damageDealt; ctr += r.P.typeStats.counters + r.O.typeStats.counters; secs += r.seconds
end
local t = {}
for k, v in pairs(m) do table.insert(t, k .. " " .. v) end
local u = {}
for k, v in pairs(rounds) do table.insert(u, "r" .. k .. " " .. v) end
print("methods: " .. table.concat(t, ", ") .. " | ended in: " .. table.concat(u, ", ") .. string.format(" | kd/fight %.1f | first kd at %.0fs | each man %.0f thrown/min %.0f%% landed, dmg/landed %.2f, counters %.0f%% of landed", kds / n, firstKD / n, th / secs * 30, la / th * 100, dmg / la, ctr / la * 100))
