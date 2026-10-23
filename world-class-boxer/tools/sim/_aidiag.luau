--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[4] and process.args[4] ~= "" and process.args[4]) or nil })
local bot = process.args[1] or "pressure"
local lvl = tonumber(process.args[2]) or 40
local N = tonumber(process.args[3]) or 6
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local notes, modes, press, dists = {}, {}, 0, {}
local ticks = 0
local miss = { red = {}, blue = {} }
for i = 1, N do
	local lastLog = {}
	local r = S.Fight({ red = { bot = bot, style = "BoxerPuncher", level = lvl }, blue = { style = STY[(i % 5) + 1], level = lvl }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f)
			if not f.live then return end
			ticks += 1
			local ai = f.O.ai
			modes[ai.mode] = (modes[ai.mode] or 0) + 1
			if f.O.pressured then press += 1 end
			local d = math.floor(f:Distance(f.P, f.O) * 2) / 2
			dists[d] = (dists[d] or 0) + 1
			local L = ai.log[#ai.log]
			if L and L ~= lastLog.e then
				lastLog.e = L
			end
			if L then
				local k = L.why:gsub("[%d%.]+", "#")
				notes[k] = (notes[k] or 0) + 1
			end
			if not f._wrapped then
				f._wrapped = true
				local old = f.Miss
				f.Miss = function(self, F, O, p, why)
					local side = F == self.P and "red" or "blue"
					miss[side][why] = (miss[side][why] or 0) + 1
					return old(self, F, O, p, why)
				end
			end
		end })
end
local function dump(t, title)
	local keys = {}
	local tot = 0
	for k, v in pairs(t) do table.insert(keys, k); tot += v end
	table.sort(keys, function(a, b) return t[a] > t[b] end)
	local out = {}
	for i = 1, math.min(#keys, 18) do table.insert(out, string.format("%s %.0f%%", tostring(keys[i]), t[keys[i]] / tot * 100)) end
	print(title .. ": " .. table.concat(out, ", "))
end
dump(modes, "modes")
dump(notes, "notes")
dump(dists, "dist")
dump(miss.red, "bot misses")
dump(miss.blue, "AI misses")
print(string.format("AI pressured %.0f%%", press / ticks * 100))
