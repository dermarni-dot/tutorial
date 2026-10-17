-- tools/sim/test_hairassets.luau: the pure half of the asset hair (src/shared/HairAssetKit.lua, and the
-- AnatomyHair helpers it uses: Gen.Resolve, Gen.CapCut) under lune. The engine half (client HairAssets:
-- CreateMeshPartAsync, EditableImages) needs Roblox; this covers what decides where and how it draws.
--   lune run tools/sim/test_hairassets.luau
local Host = require("./host")
local H = Host.new()
local HK = H.require("HairAssetKit")
local Gen = H.require("AnatomyHair")
local Kit = H.require("AnatomyHairKit")
local Data = H.require("HairAssetData")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, tol)
	return math.abs(a - b) <= (tol or 1e-6)
end
local function look(g, hair, face, extra)
	local spec = { g = g, hair = hair or {}, face = face }
	for k, v in pairs(extra or {}) do
		spec[k] = v
	end
	return (H.Look(spec))
end

------------------------------------------------------------------------
-- skull fit
------------------------------------------------------------------------
do
	local male = look(1)
	local S = Kit.Scalp(male)
	local W, T, Fz, Bz = HK.Measure(S)
	print(string.format("male default  W %.3f T %.3f Fz %.3f Bz %.3f", W, T, Fz, Bz))
	check("male W = fit0", near(W, HK.FIT0.W, 0.002), W)
	check("male T = fit0", near(T, HK.FIT0.T, 0.002), T)
	check("male Fz = fit0", near(Fz, HK.FIT0.Fz, 0.002), Fz)
	check("male Bz = fit0", near(Bz, HK.FIT0.Bz, 0.002), Bz)
	local f = HK.Fit(S, Data.fit0)
	check("male fit ~ identity", near(f.ax, 1, 0.006) and near(f.ay, 1, 0.006) and near(f.az, 1, 0.006) and near(f.dz, 0, 0.003),
		string.format("%.3f %.3f %.3f %.3f", f.ax, f.ay, f.az, f.dz))

	local fem = HK.Fit(Kit.Scalp(look(2)), Data.fit0)
	print(string.format("female default ax %.3f ay %.3f az %.3f dz %.3f", fem.ax, fem.ay, fem.az, fem.dz))
	check("female ax ~0.965", near(fem.ax, 0.965, 0.01), fem.ax)
	check("female ay ~0.99", near(fem.ay, 0.99, 0.01), fem.ay)
	check("female az ~0.995", near(fem.az, 0.995, 0.01), fem.az)
	check("female dz ~-0.004", near(fem.dz, -0.004, 0.004), fem.dz)

	local big = HK.Fit(Kit.Scalp(look(1, nil, { skullWidth = 1, skullLength = 1, crown = 1, forehead = 1 })), Data.fit0)
	local small = HK.Fit(Kit.Scalp(look(2, nil, { skullWidth = -1, skullLength = -1, crown = -1, forehead = -1 })), Data.fit0)
	print(string.format("male max      ax %.3f ay %.3f az %.3f dz %.3f", big.ax, big.ay, big.az, big.dz))
	print(string.format("female min    ax %.3f ay %.3f az %.3f dz %.3f", small.ax, small.ay, small.az, small.dz))
	check("male max fit range", near(big.ax, 1.05, 0.015) and near(big.ay, 1.03, 0.015) and near(big.az, 1.04, 0.015) and near(big.dz, 0.007, 0.005))
	check("female min fit range", near(small.ax, 0.92, 0.015) and near(small.ay, 0.97, 0.015) and near(small.az, 0.95, 0.015) and near(small.dz, -0.011, 0.005))

	-- the fit's residual on the extreme skull (CONTRACT: at most ~0.015 nominal): rays from the default centre
	local S0, S1 = Kit.Scalp(look(1)), Kit.Scalp(look(2, nil, { skullWidth = -1, skullLength = -1, crown = -1, forehead = -1 }))
	local worst = 0
	for th = 0, 110, 10 do
		for az = 0, 350, 30 do
			local t, a = math.rad(th), math.rad(az)
			local x, y, z = S0.ray(math.sin(t) * math.sin(a), math.cos(t), math.sin(t) * math.cos(a), 0)
			-- the default scalp point mapped by the fit, then how far off the small skull's surface it is
			local fx, fy, fz = x * small.ax, y * small.ay, z * small.az + small.dz
			worst = math.max(worst, math.abs(S1.f(fx, fy, fz)))
		end
	end
	print(string.format("female min residual after fit: %.4f nominal", worst))
	check("fit residual <= 0.02", worst <= 0.02, worst)
end

------------------------------------------------------------------------
-- length / volume factors
------------------------------------------------------------------------
do
	check("length default 1", near(HK.LengthFactor(look(1, { length = 0.5, growth = 0 })), 1, 1e-9))
	check("length shortest 0.6", near(HK.LengthFactor(look(1, { length = 0, growth = 0 })), 0.6, 1e-9))
	check("length longest 1.45", near(HK.LengthFactor(look(1, { length = 1, growth = 1.5 })), 1.45, 1e-9))
	check("length growth", near(HK.LengthFactor(look(1, { length = 0.5, growth = 0.5 })), 0.6 + 0.8 * 0.8, 1e-9))
	check("volume default 1", near(HK.VolumeFactor(look(1, { length = 0.5, volume = 0 })), 1, 1e-9))
	check("volume max 1.3", near(HK.VolumeFactor(look(1, { length = 1, growth = 1.5, volume = 1 })), 1.3, 1e-9))
	check("volume min 0.8", near(HK.VolumeFactor(look(1, { length = 0, volume = -1 })), 0.8, 1e-9))
	check("volume mid", near(HK.VolumeFactor(look(1, { length = 0.5, volume = 0.5 })), 1.09, 1e-9))
end

------------------------------------------------------------------------
-- placement of sample pieces
------------------------------------------------------------------------
local fakeData = {
	fit0 = Data.fit0,
	textures = { short = { id = 11, size = 256, tile = true }, straight = { id = 12, size = 1024 }, coily = { id = 13, size = 1024 },
		braid = { id = 14, size = 1024 }, cornrow = { id = 15, size = 1024 } },
	cap = { mesh = 20, bbox = { 0, 0.2, 0.03, 0.82, 0.86, 1.02 }, thetaMax = 2.2, tile = { 8, 4 }, points = {} },
	entries = {
		{ key = "afro", styles = { "Afro" }, types = { "Kinky", "Coiled", "Curly" }, cap = { cut = "full", density = 1 },
			pieces = { HairAfro01 = { mesh = 30, tex = "coily", bbox = { 0, 0.34, 0.08, 1.3, 1.1, 1.36 }, points = { 0, 0.9, 0, 0.6, 0.3, 0.1 }, length = "volume" } } },
		{ key = "long", styles = { "Long Hair" }, types = { "Straight", "Wavy" }, cap = { cut = "style", density = 1 },
			pieces = {
				HairClump01 = { mesh = 31, tex = "straight", bbox = { 0.2, -0.1, 0.3, 0.2, 0.8, 0.2 }, points = { 0.2, 0.3, 0.3, 0.2, -0.5, 0.35 }, length = "hang",
					hairfx = { kind = "swing", chain = "C1", seg = 1, pivot = { 0.2, 0.3, 0.3 }, tip = { 0.2, -0.5, 0.35 } } },
				HairClump01b = { mesh = 32, tex = "straight", bbox = { 0.2, -0.8, 0.36, 0.2, 0.6, 0.2 }, points = { 0.2, -0.5, 0.35, 0.2, -1.1, 0.4 }, length = "hang",
					hairfx = { kind = "swing", chain = "C1", seg = 2, parent = "HairClump01", pivot = { 0.2, -0.5, 0.35 }, tip = { 0.2, -1.1, 0.4 } } },
			} },
		{ key = "fade", styles = { "Buzz Cut", "Fade", "Low Fade", "Mid Fade", "High Fade", "Taper Fade", "Burst Fade", "360 Waves" },
			cap = { cut = "style", density = 1 }, pieces = {} },
		{ key = "nocap", styles = { "Cornrows" }, cap = { cut = "none" }, pieces = {} },
	},
}

do
	local lk = look(2, { style = "Long Hair", type = "Straight", length = 1, growth = 0 })
	local S = Kit.Scalp(lk)
	local fit = HK.Fit(S, fakeData.fit0)
	local placed, _, Lf = HK.Place(fakeData, fakeData.entries[2], lk, S, fit)
	check("long places the cap", placed.HairCap ~= nil)
	local a, b = placed.HairClump01, placed.HairClump01b
	-- by hand: fit, then the chain's stretch about its root pivot (y 0.3 x ay), then the head size
	local anchor = 0.3 * fit.ay
	local k = Lf
	local bottom = (-0.8 - 0.3) * fit.ay
	k = math.max(1, math.min(k, (anchor - (S.torso[2])) / (anchor - bottom)))
	local function byHand(x, y, z)
		local nx, ny, nz = x * fit.ax, y * fit.ay, z * fit.az + fit.dz
		ny = anchor + (ny - anchor) * k
		return nx * S.kx, ny * S.ky, nz * S.kz
	end
	local cx, cy, cz = byHand(0.2, -0.1, 0.3)
	check("hang centre", near(a.centre[1], cx, 1e-9) and near(a.centre[2], cy, 1e-9) and near(a.centre[3], cz, 1e-9),
		string.format("%.4f %.4f %.4f vs %.4f %.4f %.4f", a.centre[1], a.centre[2], a.centre[3], cx, cy, cz))
	check("hang size", near(a.size[1], 0.2 * fit.ax * S.kx, 1e-9) and near(a.size[2], 0.8 * fit.ay * k * S.ky, 1e-9) and near(a.size[3], 0.2 * fit.az * S.kz, 1e-9))
	-- the joint stays closed: seg 1's tip = seg 2's pivot after the stretch
	local t1, p2 = a.hairfx.tip, b.hairfx.pivot
	check("chain joint closed", near(t1[1], p2[1], 1e-9) and near(t1[2], p2[2], 1e-9) and near(t1[3], p2[3], 1e-9))
	check("landmarks", a.landmarks["HairClump01.0"] ~= nil and a.landmarks["HairClump01.1"] ~= nil)
	local px, py, pz = byHand(0.2, -0.5, 0.35)
	check("points mapped", near(a.P[4], px, 1e-9) and near(a.P[5], py, 1e-9) and near(a.P[6], pz, 1e-9) and a.nv == 2)
	print(string.format("long hair: Lf %.3f, chain k %.3f, real head k %.3f", Lf, k, S.ky))

	-- volume: about the boxer's skull centre
	local lk2 = look(1, { style = "Afro", type = "Kinky", length = 1, volume = 1 })
	local S2 = Kit.Scalp(lk2)
	local fit2 = HK.Fit(S2, fakeData.fit0)
	local placed2, _, _, Vf = HK.Place(fakeData, fakeData.entries[1], lk2, S2, fit2)
	local q = placed2.HairAfro01
	local ny = S2.cy + (0.34 * fit2.ay - S2.cy) * Vf
	check("volume centre y", near(q.centre[2], ny * S2.ky, 1e-9), q.centre[2])
	check("volume size", near(q.size[1], 1.3 * fit2.ax * Vf * S2.kx, 1e-9))
	check("no points -> box corners", placed2.HairCap.nv == 9)
	print(string.format("afro: Vf %.3f", Vf))
end

------------------------------------------------------------------------
-- entry selection
------------------------------------------------------------------------
do
	local function sel(hair, data)
		local e = HK.Select(data or fakeData, look(1, hair))
		return e and e.key or nil
	end
	check("afro kinky", sel({ style = "Afro", type = "Kinky" }) == "afro")
	check("afro straight -> none", sel({ style = "Afro", type = "Straight" }) == nil)
	check("long straight", sel({ style = "Long Hair", type = "Straight" }) == "long")
	check("long wavy", sel({ style = "Long Hair", type = "Wavy" }) == "long")
	check("long curly (longCurly recipe) -> none", sel({ style = "Long Hair", type = "Curly" }) == nil)
	check("taper fade", sel({ style = "Taper Fade", type = "Straight" }) == "fade")
	check("high fade coiled", sel({ style = "High Fade", type = "Coiled" }) == "fade")
	check("bald -> none", sel({ style = "Bald", type = "Kinky" }) == nil)
	check("cap none + no pieces -> unusable", sel({ style = "Cornrows", type = "Kinky" }) == nil)
	check("unknown style -> Fade", sel({ style = "Nonsense", type = "Straight" }) == "fade")
	local s, t, route = Gen.Resolve(look(1, { style = "Short Curly", type = "Straight" }))
	check("Resolve: curly-only cut on straight hair reads Curly", s == "Short Curly" and t == "Curly" and route == nil)
	s, t, route = Gen.Resolve(look(1, { style = "Long Hair", type = "Coiled" }))
	check("Resolve: longCurly route", s == "Long Hair" and t == "Coiled" and route == "longCurly")
	-- a failed id skips its entry
	local e = HK.Select(fakeData, look(1, { style = "Afro", type = "Kinky" }), function(en)
		return en.key == "afro"
	end)
	check("skip callback", e == nil)
	-- the shipped data (ids 0): nothing anywhere
	local any = false
	for _, st in ipairs({ "Afro", "Long Hair", "Fade", "High Fade", "Buzz Cut", "Dreadlocks", "Braids", "Cornrows" }) do
		for _, ty in ipairs({ "Straight", "Kinky" }) do
			if HK.Select(Data, look(1, { style = st, type = ty })) then
				any = true
			end
		end
	end
	check("HairAssetData ids 0 -> no entry", not any)
	-- one missing texture id makes an entry unusable
	local d2 = table.clone(fakeData)
	d2.textures = table.clone(fakeData.textures)
	d2.textures.coily = { id = 0, size = 1024 }
	check("missing texture id -> none", HK.Select(d2, look(1, { style = "Afro", type = "Kinky" })) == nil)
end

------------------------------------------------------------------------
-- cap coverage
------------------------------------------------------------------------
do
	local function covAt(hair, capSpec, dir)
		local lk = look(1, hair)
		local cov, S = HK.CapCoverage(lk, "full", capSpec)
		local l = math.sqrt(dir[1] ^ 2 + dir[2] ^ 2 + dir[3] ^ 2)
		local x, y, z = S.ray(dir[1] / l, dir[2] / l, dir[3] / l, 0)
		return cov(x, y, z), y
	end
	-- SIDE_LOW just above the hairline over the ear (y ~0.13: inside every fade), SIDE_MID higher (y ~0.2)
	local TOP, SIDE_LOW, SIDE_MID, NAPE_LOW, FOREHEAD = { 0, 1, 0.1 }, { 1, -0.05, 0.25 }, { 1, 0.06, 0.25 }, { 0, -0.2, 1 }, { 0, -0.1, -1 }
	local styles = { "High Fade", "Mid Fade", "Low Fade", "Buzz Cut", "Crew Cut" }
	for _, st in ipairs(styles) do
		local top = covAt({ style = st, type = "Straight" }, { cut = "style" }, TOP)
		local side, sy = covAt({ style = st, type = "Straight" }, { cut = "style" }, SIDE_LOW)
		local nape = covAt({ style = st, type = "Straight" }, { cut = "style" }, NAPE_LOW)
		local mid, my = covAt({ style = st, type = "Straight" }, { cut = "style" }, SIDE_MID)
		print(string.format("%-10s cov top %.2f side(y %.2f) %.2f side(y %.2f) %.2f nape %.2f", st, top, sy, side, my, mid, nape))
		if st == "High Fade" then
			check("high fade top ~1", top > 0.9, top)
			check("high fade low side ~0", side < 0.1, side)
		elseif st == "Buzz Cut" then
			check("buzz even: side ~ top", math.abs(mid - top) < 0.05 and top > 0.5, string.format("%.2f %.2f", top, mid))
		elseif st == "Crew Cut" then
			check("crew cut full side", mid > 0.95, mid)
		elseif st == "Mid Fade" then
			check("mid fade: part faded at y 0.17 (below its 0.22 line), full on top", mid < 0.75 and top > 0.9, mid)
		end
	end
	local hiF = covAt({ style = "High Fade" }, { cut = "style" }, SIDE_LOW)
	local loF = covAt({ style = "Low Fade" }, { cut = "style" }, SIDE_LOW)
	check("fade heights ordered (low fade keeps more side)", loF > hiF, string.format("%.2f %.2f", loF, hiF))
	local fTop = covAt({ style = "Afro", type = "Kinky" }, { cut = "full", density = 1 }, TOP)
	local fFace = covAt({ style = "Afro", type = "Kinky" }, { cut = "full", density = 1 }, FOREHEAD)
	local fHalf = covAt({ style = "Afro", type = "Kinky" }, { cut = "full", density = 0.5 }, TOP)
	check("full: top 1, forehead 0, density", near(fTop, 1, 0.01) and fFace < 0.01 and near(fHalf, 0.5, 0.01), string.format("%.2f %.2f %.2f", fTop, fFace, fHalf))
	-- every style's cut can be captured (the recipes up to their shell)
	local Looks = H.require("Looks")
	local nCut = 0
	for _, st in ipairs(Looks.HairStyles) do
		for _, ty in ipairs({ "Straight", "Kinky" }) do
			local ok, cut = pcall(Gen.CapCut, look(1, { style = st, type = ty }), "full")
			check("CapCut " .. st .. " " .. ty, ok and (st == "Bald" or cut ~= nil), cut)
			if ok and cut then
				nCut += 1
			end
		end
	end
	print("CapCut: " .. nCut .. " style / type cuts captured")
	-- the captured cut is the generated HairCap's: same coverage as the generator's own H.cut
	local Parts = H.require("AnatomyHairParts")
	local lk = look(1, { style = "Mid Fade", type = "Coiled", hairline = "Line-Up" })
	local H0 = Parts.Context(lk, "full", nil, "Mid Fade", "Coiled")
	Gen._R["Mid Fade"](H0)
	local cut = Gen.CapCut(lk, "full")
	local same = true
	for _, p in ipairs({ { 0.3, 0.2, 0.2 }, { 0, 0.5, 0 }, { 0.35, 0.05, 0.1 }, { 0, 0.33, -0.43 } }) do
		local a, b = H0.cut.cov(p[1], p[2], p[3]), cut.cov(p[1], p[2], p[3])
		if not near(a, b, 1e-9) then
			same = false
		end
	end
	check("CapCut = the generator's cut", same)
end

------------------------------------------------------------------------
-- tint math
------------------------------------------------------------------------
do
	local w, h = 4, 4
	local src = buffer.create(w * h * 4)
	for i = 0, w * h - 1 do
		buffer.writeu8(src, i * 4, 200)
		buffer.writeu8(src, i * 4 + 1, 200)
		buffer.writeu8(src, i * 4 + 2, 200)
		buffer.writeu8(src, i * 4 + 3, (i % 2 == 0) and 255 or 0)
	end
	local lk = look(1, { color = { 255, 0, 0 }, hcolor = { 0, 0, 255 }, dye = "None" })
	local pal = HK.Palette(lk, "Straight")
	local flat = HK.Colors(pal, h, true)
	local out = HK.Tint(src, w, h, 1, flat, false)
	local r, g, b = pal.at(0.5, 0.5, -1)
	check("flat multiply r", buffer.readu8(out, 0) == math.floor(200 * r + 0.5), buffer.readu8(out, 0))
	check("flat multiply g/b", buffer.readu8(out, 1) == math.floor(200 * g + 0.5) and buffer.readu8(out, 2) == math.floor(200 * b + 0.5))
	check("alpha kept", buffer.readu8(out, 3) == 255 and buffer.readu8(out, 7) == 0)
	-- root darker than tip along v
	local cols = HK.Colors(pal, h, false, 1)
	local o2 = HK.Tint(src, w, h, 1, cols, false)
	local root, tip = buffer.readu8(o2, 0), buffer.readu8(o2, ((h - 1) * w) * 4)
	check("root darker than tip", root < tip, string.format("%d %d", root, tip))
	-- Tips dye: the last rows take hcolor (blue), the first keep the base (red)
	local lkT = look(1, { color = { 255, 0, 0 }, hcolor = { 0, 0, 255 }, dye = "Tips" })
	local palT = HK.Palette(lkT, "Straight")
	local cT = HK.Colors(palT, 16, false, 1)
	local hh = 16
	local srcT = buffer.create(1 * hh * 4)
	buffer.fill(srcT, 0, 255)
	local oT = HK.Tint(srcT, 1, hh, 1, cT, false)
	check("tips: root red", buffer.readu8(oT, 0) > 150 and buffer.readu8(oT, 2) < 40, string.format("%d %d", buffer.readu8(oT, 0), buffer.readu8(oT, 2)))
	local last = (hh - 1) * 4
	check("tips: tip blue", buffer.readu8(oT, last + 2) > 150 and buffer.readu8(oT, last) < 60, string.format("%d %d", buffer.readu8(oT, last), buffer.readu8(oT, last + 2)))
	-- flipV puts the tip row first
	local oF = HK.Tint(srcT, 1, hh, 1, cT, true)
	check("flipV", buffer.readu8(oF, 0) == buffer.readu8(oT, last) and buffer.readu8(oF, 2) == buffer.readu8(oT, last + 2))
	-- Ombre: a gradient along v (monotone toward hcolor)
	local palO = HK.Palette(look(1, { color = { 255, 0, 0 }, hcolor = { 0, 0, 255 }, dye = "Ombre" }), "Straight")
	local cO = HK.Colors(palO, 16, false, 1)
	local mono = true
	for j = 1, 15 do
		if cO.cols[1][j * 3 + 3] + 1e-9 < cO.cols[1][(j - 1) * 3 + 3] then
			mono = false
		end
	end
	check("ombre blue rises along v", mono)
	-- Streaks: some u bands carry hcolor, others not
	local palS = HK.Palette(look(1, { color = { 255, 0, 0 }, hcolor = { 0, 0, 255 }, dye = "Streaks" }), "Straight")
	local cS = HK.Colors(palS, 4, false, HK.BANDS)
	local blue, red = 0, 0
	for bi = 1, HK.BANDS do
		if cS.cols[bi][3] > 0.3 then
			blue += 1
		else
			red += 1
		end
	end
	check("streaks on some bands", blue >= 1 and red >= 6, string.format("%d streak bands of %d", blue, HK.BANDS))
	-- downscale: a 2x2 box
	local s4 = buffer.create(2 * 2 * 4)
	for i, v in ipairs({ 0, 100, 200, 100 }) do
		buffer.writeu8(s4, (i - 1) * 4, v)
		buffer.writeu8(s4, (i - 1) * 4 + 3, 255)
	end
	local one = { flat = true, r = 1, g = 1, b = 1 }
	local d, dw, dh = HK.Tint(s4, 2, 2, 2, one, false)
	check("box filter", dw == 1 and dh == 1 and buffer.readu8(d, 0) == 100 and buffer.readu8(d, 3) == 255, buffer.readu8(d, 0))
	-- greying with age (the palette's rules): an old boxer's black hair is lighter
	local young = HK.Colors(HK.Palette(look(1, { color = { 22, 19, 17 } }), "Straight"), 4, true)
	local old = HK.Colors(HK.Palette(look(1, { color = { 22, 19, 17 } }, nil, { age = 70 }), "Straight"), 4, true)
	check("greying", old.r > young.r + 0.05, string.format("%.3f %.3f", young.r, old.r))
	check("color key differs by age", HK.ColorKey(look(1, {}, nil, { age = 70 }), "Straight") ~= HK.ColorKey(look(1), "Straight"))
	check("color key same look", HK.ColorKey(look(1), "Straight") == HK.ColorKey(look(1), "Straight"))

	-- the cap paint: alpha = tile alpha x coverage, colour = grey x the grid's colour
	local lkC = look(1, { style = "High Fade", type = "Straight" })
	local cov, S = HK.CapCoverage(lkC, "full", { cut = "style" })
	local grid = HK.CapGrid(S, cov, HK.Palette(lkC, "Straight"), 2.2, 32, 16)
	local tile = buffer.create(4 * 4 * 4)
	buffer.fill(tile, 0, 255)
	local cap = HK.PaintCap(grid, tile, 4, 4, 2, 2, 32, false)
	local a0 = buffer.readu8(cap, 3) -- row 0: the crown
	local aLow = buffer.readu8(cap, ((31 * 32) + 8) * 4 + 3) -- the last row, a side: under the hairline / fade
	check("cap crown covered", a0 > 230, a0)
	check("cap low edge bare", aLow < 30, aLow)
end

print(string.format("test_hairassets: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_hairassets failed")
end
