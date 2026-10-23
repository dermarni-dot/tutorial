--!nocheck
-- scratch (frame-traits tuning): lune run _ft_tune.luau A B n seed0 [overrides.json] [root]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local FS = require("./fightsim")
local root = process.args[6]
local S = FS.new({ root = (root and root ~= "") and root or nil })
local FT = S.H.require("FrameTraits")
local ov = process.args[5]
if ov and ov ~= "" and fs.isFile(ov) then
	for id, t in pairs(serde.decode("json", fs.readFile(ov))) do
		for k, v in pairs(t) do
			if type(v) == "table" then
				for k2, v2 in pairs(v) do FT.Data[id][k][k2] = v2 end
			else
				FT.Data[id][k] = v
			end
		end
	end
end
local a, b, n, s0 = process.args[1], process.args[2], tonumber(process.args[3]), tonumber(process.args[4])
for i = s0, s0 + n - 1 do
	local r = S.Fight({ red = { style = "BoxerPuncher", level = 60, noTraits = true, frame = a }, blue = { style = "BoxerPuncher", level = 60, noTraits = true, frame = b }, rounds = 6, seed = i * 7919 + 13 })
	print(string.format("R %s %s %s %s %d", a, b, r.winner, r.method, r.round))
end
