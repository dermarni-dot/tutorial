--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new()
local a, b = process.args[1] or "Athletic", process.args[2] or "Athletic"
local n = tonumber(process.args[3]) or 8
for i = 1, n do
	local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true, frame = a }, blue = { style = "BoxerPuncher", level = 60, noTraits = true, frame = b }, rounds = 6, seed = i * 7919 + 13 })
	local extra = ""
	for k, v in pairs(r) do if type(v) ~= "table" and k ~= "winner" and k ~= "method" and k ~= "round" and k ~= "seconds" then extra ..= k .. "=" .. tostring(v) .. " " end end
	print(i, r.winner, r.method, r.round, string.format("%.0f", r.seconds), extra)
end
