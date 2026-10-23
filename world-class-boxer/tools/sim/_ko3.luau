--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[1] ~= "" and process.args[1]) or nil })
local FightAI = S.FightAI
local cnt, tot = {}, 0
local oldNote = FightAI.Note
local oldThrow = FightAI.Throw
local pending = {}
FightAI.Throw = function(self, p, body)
	self._threw = true
	return oldThrow(self, p, body)
end
FightAI.Note = function(self, now, why)
	if self._threw then
		local k = why:gsub("[%d%.]+", "#"):gsub(": .*", "")
		cnt[k] = (cnt[k] or 0) + 1; tot += 1
		self._threw = false
	end
	return oldNote(self, now, why)
end
local Fight = S.FightEngine._Fight
local oldSpecial = Fight.Special
local specials = 0
Fight.Special = function(self, F, id) specials += 1; return oldSpecial(self, F, id) end
local thrown = 0
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
for i = 1, 12 do
	local r = S.Fight({ red = { style = STY[(i % 5) + 1], level = 60 }, blue = { style = STY[((i + 2) % 5) + 1], level = 60 }, rounds = 6, seed = i * 7919 + 13 })
	thrown += r.thrown.red + r.thrown.blue
end
local keys = {}
for k in pairs(cnt) do table.insert(keys, k) end
table.sort(keys, function(a, b) return cnt[a] > cnt[b] end)
local out = {}
for _, k in ipairs(keys) do table.insert(out, string.format("%s %.0f%%", k, cnt[k] / thrown * 100)) end
print(string.format("thrown %d, via Throw %d (%.0f%%), specials %d: %s", thrown, tot, tot / thrown * 100, specials, table.concat(out, ", ")))
