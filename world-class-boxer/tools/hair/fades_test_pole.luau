-- tools/hair/fades_test_pole.luau: checks fades_paintcap_pole.diff (HairAssetKit.PaintCap's crown planar
-- sampling, HK.CapPole). Run against a tree with the diff applied:
--   lune run tools/hair/fades_test_pole.luau [src folder with the patch, default <repo>/src]
local process = require("@lune/process")
local Host = require("../sim/host")
local H = Host.new({ src = process.args[1] })
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

-- a 64 x 128 tile of random grey / alpha (deterministic)
local tw, th = 64, 128
local tile = buffer.create(tw * th * 4)
local seed = 7
local rng = {}
function rng:NextInteger(lo, hi)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return lo + seed % (hi - lo + 1)
end
for k = 0, tw * th - 1 do
	local g = rng:NextInteger(60, 255)
	buffer.writeu8(tile, k * 4, g)
	buffer.writeu8(tile, k * 4 + 1, g)
	buffer.writeu8(tile, k * 4 + 2, g)
	buffer.writeu8(tile, k * 4 + 3, rng:NextInteger(150, 255))
end
local n = 8 * 8
local R, C = table.create(n, 1), table.create(n, 1)
local grid = { r = R, g = R, b = R, c = C, w = 8, h = 8 }
local data = { cap = { thetaMax = 2.58309, tile = { 8, 4 }, pole = { theta0 = 0.43633, theta1 = 0.69813, su = 0.42347, sv = 0.64577 } } }
local pole = HK.CapPole(data, {})
check("CapPole from the cap data", pole and pole.theta1 == 0.69813 and pole.thetaMax == 2.58309)
check("no pole for a whole-cap image", HK.CapPole(data, { capTileRepeat = { 1, 1 } }) == nil)
check("no pole without cap data", HK.CapPole({ cap = { tile = { 8, 4 } } }, {}) == nil)

local size = 256
local a = HK.PaintCap(grid, tile, tw, th, 8, 4, size, false)
local b = HK.PaintCap(grid, tile, tw, th, 8, 4, size, false, nil, nil, nil, pole)
-- rows beyond theta1 are unchanged
local same = true
local j1 = math.ceil(pole.theta1 / pole.thetaMax * size) + 1
for j = j1, size - 1 do
	for i = 0, size - 1 do
		local o = (j * size + i) * 4
		if buffer.readu32(a, o) ~= buffer.readu32(b, o) then
			same = false
		end
	end
end
check("polar sampling unchanged below the crown", same)
-- near the pole the polar painting repeats every size / 8 texels round the row (the star's spokes); the planar
-- one does not
local function periodicity(buf, j)
	local d, m = 0, 0
	for i = 0, size - 1 do
		local o = (j * size + i) * 4
		local o2 = (j * size + (i + size // 8) % size) * 4
		d += math.abs(buffer.readu8(buf, o) - buffer.readu8(buf, o2))
		m += 1
	end
	return d / m
end
local jp = math.floor(0.15 / pole.thetaMax * size)
local pa, pb = periodicity(a, jp), periodicity(b, jp)
check("polar row repeats 8 times (control)", pa < 1, pa)
check("planar crown row does not repeat", pb > 10, pb)
print(string.format("pole: %d passed, %d failed (row %d: polar %.2f, planar %.2f mean |diff| at 1/8 turn)", pass, fail, jp, pa, pb))
if fail > 0 then
	process.exit(1)
end
