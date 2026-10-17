-- tools/sim/test_capshell.luau: the fur shells' variants of the painted cap (HairAssetKit.PaintCap's shell
-- argument, CapShellOf / CapShells) and the per-entry tile repeat (CapRepeat).
--   lune run tools/sim/test_capshell.luau
local Host = require("./host")
local H = Host.new()
local HK = H.require("HairAssetKit")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

-- a 16 x 16 tile whose texels' alpha runs 1..256 (every rank distinct), grey 200
local tw, th = 16, 16
local tile = buffer.create(tw * th * 4)
for k = 0, tw * th - 1 do
	buffer.writeu8(tile, k * 4, 200)
	buffer.writeu8(tile, k * 4 + 1, 200)
	buffer.writeu8(tile, k * 4 + 2, 200)
	buffer.writeu8(tile, k * 4 + 3, k)
end
local function gridOf(c)
	local n = 4 * 4
	local R, C = table.create(n, 1), table.create(n, c)
	return { r = R, g = R, b = R, c = C, w = 4, h = 4 }
end
-- the share of output texels with any alpha, and the summed alpha
local function stats(buf, size)
	local any, sum = 0, 0
	for k = 0, size * size - 1 do
		local a = buffer.readu8(buf, k * 4 + 3)
		if a > 0 then
			any += 1
		end
		sum += a
	end
	return any / (size * size), sum
end

local size = 16
local full = HK.PaintCap(gridOf(1), tile, tw, th, 1, 1, size, false)
local fAny, fSum = stats(full, size)
local s1 = HK.PaintCap(gridOf(1), tile, tw, th, 1, 1, size, false, nil, nil, { rank = 0.5, cov = 0 })
local aAny, aSum = stats(s1, size)
local s2 = HK.PaintCap(gridOf(1), tile, tw, th, 1, 1, size, false, nil, nil, { rank = 0.8, cov = 0 })
local bAny, bSum = stats(s2, size)
check("no shell: every texel kept", fAny > 0.99, fAny)
check("rank 0.5 keeps about the upper half", aAny > 0.4 and aAny < 0.62, aAny)
check("rank 0.8 sparser still", bAny < aAny and bAny > 0.1 and bAny < 0.32, bAny)
check("kept texels keep their own alpha", aSum > 0 and bSum < aSum and aSum < fSum)
-- the kept texels are the opaque (high-ranked) ones
local okHigh = true
for k = 0, size * size - 1 do
	local a = buffer.readu8(s2, k * 4 + 3)
	if a > 0 and buffer.readu8(full, k * 4 + 3) < 150 then
		okHigh = false
	end
end
check("the shell keeps the strand cores", okHigh)
-- a coverage floor: below it the shell is bare, above it as the cap at that coverage
local low = HK.PaintCap(gridOf(0.3), tile, tw, th, 1, 1, size, false, nil, nil, { rank = 0, cov = 0.4 })
local lAny = stats(low, size)
check("coverage under the floor: bare", lAny == 0, lAny)
local mid = HK.PaintCap(gridOf(0.7), tile, tw, th, 1, 1, size, false, nil, nil, { rank = 0, cov = 0.4 })
local capMid = HK.PaintCap(gridOf(0.5), tile, tw, th, 1, 1, size, false)
local mAny, cAny = stats(mid, size), stats(capMid, size)
check("coverage 0.7 over a 0.4 floor ~ the cap at 0.5", math.abs(mAny - cAny) < 0.02, string.format("%.3f %.3f", mAny, cAny))

-- CapShellOf / CapShells
local entry = { pieces = {
	A = { tex = "cap" }, B = { tex = "cap", capShell = { rank = 0.3, cov = 0.25 } },
	C = { tex = "cap", capShell = { rank = 0.3, cov = 0.25 } }, D = { tex = "cap", capShell = { rank = 0.75, cov = 0.7 } },
	E = { tex = "crop", capShell = { rank = 0.5 } },
} }
local n = 0
for _ in pairs(HK.CapShells(entry)) do
	n += 1
end
check("two distinct shell variants", n == 2, n)
check("no capShell: the cap itself", HK.CapShellOf(entry.pieces.A) == nil)
check("a card texture never takes a shell", HK.CapShellOf(entry.pieces.E) == nil)
local _, kb = HK.CapShellOf(entry.pieces.B)
local _, kc = HK.CapShellOf(entry.pieces.C)
check("equal specs share a key", kb == kc and kb ~= nil)

-- CapRepeat
local data = { cap = { tile = { 8, 4 } } }
local nu, nv = HK.CapRepeat(data, {})
check("cap tile repeat", nu == 8 and nv == 4)
nu, nv = HK.CapRepeat(data, { capTileRepeat = { 1, 1 } })
check("entry override", nu == 1 and nv == 1)
nu, nv = HK.CapRepeat({}, nil)
check("default 8 x 4", nu == 8 and nv == 4)

print(string.format("test_capshell: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_capshell failed")
end
