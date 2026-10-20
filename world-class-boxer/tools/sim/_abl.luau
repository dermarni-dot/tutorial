local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local AI = S.FightAI
local which = process.args[1] or ""
if which:find("feint") then AI.TryFeint = function() return false end end
if which:find("punish") then local o = AI.OnOppComboEnd; AI.OnOppComboEnd = function(self, n) self.read:ComboEnd(n) end end
if which:find("done") then AI.ComboDone = function() end end
if which:find("prefs") then AI.PunchPrefs = function() return { jab = 1, cross = 1, leadhook = 1, rearhook = 1, uppercut = 1, overhand = 1 } end end
if which:find("mode") then local o = AI.UpdateMode; AI.UpdateMode = function(self) o(self); if self.mode == self.plan then self.mode = "plan" end end end
if which:find("expect") then local o = AI.OnOppPunch; AI.OnOppPunch = function(self, ...) self.expect = nil; self.drawUntil = 0; return o(self, ...) end end
local N = tonumber(process.args[2]) or 64
local w, th, secs, ko = 0, 0, 0, 0
for i = 1, N do
	local r = S.Fight({ red = { bot = process.args[3], style = process.args[4] or "BoxerPuncher", level = 60, noTraits = true }, blue = { style = process.args[5] or "BoxerPuncher", level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
	w += r.winner == "red" and 1 or 0; th += r.thrown.blue; secs += r.seconds
	ko = (ko or 0) + ((r.method == "KO" or r.method == "TKO" or r.method == "RTD") and 1 or 0)
end
print(which, string.format("win %.2f ko %.2f blue %.1f/min %.0fs", w / N, ko / N, th / secs * 60, secs / N))
