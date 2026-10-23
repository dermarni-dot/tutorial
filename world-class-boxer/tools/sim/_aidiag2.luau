--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local bot = process.args[1] or "pressure"
local lvl = tonumber(process.args[2]) or 40
local N = tonumber(process.args[3]) or 10
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local Fight = S.FightEngine._Fight
local stat = { red = {}, blue = {} }
local dmgT = { red = 0, blue = 0 }
local oldCR = Fight.ChainResult
Fight.ChainResult = function(self, F, O, sp, res)
	local it = sp and sp.chain
	if it then
		local side = F == self.P and "red" or "blue"
		local k = it.p .. (it.body and "B" or "")
		local t = stat[side][k] or { n = 0, landed = 0, blocked = 0, miss = 0 }
		stat[side][k] = t
		t.n += 1
		t[res] = (t[res] or 0) + 1
	end
	return oldCR(self, F, O, sp, res)
end
local wins, kdr, kdb = 0, 0, 0
for i = 1, N do
	local r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STY[(i % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13 })
	if r.winner == "red" then wins += 1 end
	kdr += r.kd.red; kdb += r.kd.blue
	dmgT.red += r.P.damageDealt; dmgT.blue += r.O.damageDealt
end
print(string.format("red wins %d/%d  kd red %d blue %d  dmg red %.0f blue %.0f", wins, N, kdr, kdb, dmgT.red, dmgT.blue))
for _, side in ipairs({ "red", "blue" }) do
	local keys = {}
	for k in pairs(stat[side]) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return stat[side][a].n > stat[side][b].n end)
	local out = {}
	for _, k in ipairs(keys) do
		local t = stat[side][k]
		table.insert(out, string.format("%s %d L%.0f%% B%.0f%%", k, t.n, t.landed / t.n * 100, t.blocked / t.n * 100))
	end
	print(side .. ": " .. table.concat(out, " | "))
end
