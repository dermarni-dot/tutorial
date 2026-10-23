--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[3] and process.args[3] ~= "" and process.args[3]) or nil })
local a, b = process.args[1], process.args[2]
if process.args[4] and process.args[4] ~= "" then
	local luau = require("@lune/luau")
	luau.load(process.args[4], { environment = setmetatable({ AIC = S.Config.FightAI, S = S }, { __index = _G }) })()
end
local w, ko, rr, modes = 0, 0, 0, {}
local N = 24
for i = 1, N do
	local r = S.Fight({ red = { style = a, level = 60, noTraits = true }, blue = { style = b, level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f) if f.live then modes[f.O.ai.mode] = (modes[f.O.ai.mode] or 0) + 1 end end })
	w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
	if r.method == "KO" or r.method == "TKO" then ko += 1 end
	rr += r.round
end
local t = {}
for k, v in pairs(modes) do table.insert(t, k .. "=" .. v) end
print(string.format("%s vs %s: red %.2f ko %.2f r%.1f | blue modes %s", a, b, w / N, ko / N, rr / N, table.concat(t, " ")))
