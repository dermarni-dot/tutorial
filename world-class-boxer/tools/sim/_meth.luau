local process = require("@lune/process")
local FS = require("./fightsim")
local root = process.args[1] ~= "-" and process.args[1] or nil
local S = FS.new({ root = root })
local m = {}
local reasons = {}
for i = 1, 40 do
	local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true }, blue = { style = "BoxerPuncher", level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13 })
	m[r.method] = (m[r.method] or 0) + 1
	local why = r.fight.reason or "-"
	reasons[why] = (reasons[why] or 0) + 1
end
for k, v in pairs(m) do print(k, v) end
for k, v in pairs(reasons) do print("  ", k, v) end
