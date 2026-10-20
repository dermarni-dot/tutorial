local process = require("@lune/process")
local FS = require("./fightsim")
local root = process.args[1] ~= "-" and process.args[1] or nil
local S = FS.new({ root = root })
local Fight = S.FightEngine._Fight
local by = {}
local oP, oS = Fight.Punch, Fight.Special
Fight.Punch = function(self, F, ...)
	if not F.isPlayer and F == self.O then
		local key = debug.info(2, "sl")
		local l = debug.info(2, "l")
		local l3 = debug.info(3, "l")
		local k = tostring(debug.info(2, "n")) .. ":" .. l .. "<" .. tostring(debug.info(3, "n")) .. ":" .. tostring(l3)
		by[k] = (by[k] or 0) + 1
	end
	return oP(self, F, ...)
end
local secs = 0
for i = 1, 24 do
	local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
	secs += r.seconds
end
local keys = {}
for k, v in pairs(by) do table.insert(keys, { k, v }) end
table.sort(keys, function(a, b) return a[2] > b[2] end)
for _, kv in ipairs(keys) do print(string.format("%6.1f/min  %s", kv[2] / secs * 60, kv[1])) end
