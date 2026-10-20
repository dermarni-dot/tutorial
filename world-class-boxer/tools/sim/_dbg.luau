local process = require("@lune/process")
local FS = require("./fightsim")
local root = process.args[1] ~= "-" and process.args[1] or nil
local S = FS.new({ root = root })
local AI = S.FightAI
local cnt = { combo = 0, counter = 0, throw = 0, special = 0 }
local oB, oC, oT = AI.BuildCombo, AI.CounterPunch, AI.Throw
AI.BuildCombo = function(self, ...) cnt.combo += 1 local l = oB(self, ...) cnt.comboLen = (cnt.comboLen or 0) + #l return l end
if oC then AI.CounterPunch = function(self, ...) cnt.counter += 1 return oC(self, ...) end end
local secs, special, feints = 0, 0, 0
for i = 1, 8 do
	local r = S.Fight({ red = { bot = process.args[2] or "smart", style = "BoxerPuncher", level = 40, noTraits = true }, blue = { style = "BoxerPuncher", level = 40, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
	secs += r.seconds; special += r.O.specialsUsed; feints += (r.O.feints or 0)
	cnt.thrown = (cnt.thrown or 0) + r.O.totals.thrown
end
local m = secs / 60
print(string.format("per min: thrown %.1f combos %.1f (len %.2f) counters %.1f specials %.1f feints %.1f", cnt.thrown / m, cnt.combo / m, (cnt.comboLen or 0) / math.max(1, cnt.combo), cnt.counter / m, special / m, feints / m))
