--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[3] and process.args[3] ~= "" and process.args[3]) or nil })
local C = S.Config
local orig = C.KOChance
local stats = { calls = 0, byTier = {}, flash = 0, kd = 0 }
local lastArgs
C.KOChance = function(a)
	local p, flash = orig(a)
	stats.calls += 1
	local k = "t" .. tostring(a.tier) .. (a.counter and "c" or "")
	local e = stats.byTier[k] or { n = 0, p = 0 }
	stats.byTier[k] = e
	e.n += 1; e.p += p
	return p, flash
end
local Fight = S.FightEngine._Fight
local ok = Fight.Knockdown
local kdBy = {}
Fight.Knockdown = function(self, F, by, sev, fall, cause)
	local k = (F.ai and F.ai.style and F.ai.style.id or "?") .. " t" .. tostring(F.tier) .. " " .. tostring(cause) .. string.format(" body<%d", math.floor((F.body or 0) / 25) * 25 + 25)
	kdBy[k] = (kdBy[k] or 0) + 1
	return ok(self, F, by, sev, fall, cause)
end
local a, b = process.args[1], process.args[2]
for i = 1, 24 do
	S.Fight({ red = { style = a, level = 60, noTraits = true }, blue = { style = b, level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
end
local t = {}
for k, e in pairs(stats.byTier) do table.insert(t, string.format("%s n%d expKD %.1f", k, e.n, e.p)) end
table.sort(t)
print("KO rolls: " .. table.concat(t, " | "))
local u = {}
for k, v in pairs(kdBy) do table.insert(u, k .. "=" .. v) end
print("knockdowns of: " .. table.concat(u, ", "))
