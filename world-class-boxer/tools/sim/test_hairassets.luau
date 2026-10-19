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
	-- (the organic skull against the organic fit0: the v7 meshes' reference)
	local f = HK.Fit(S, HK.FIT0)
	check("male fit ~ identity", near(f.ax, 1, 0.006) and near(f.ay, 1, 0.006) and near(f.az, 1, 0.006) and near(f.dz, 0, 0.003),
		string.format("%.3f %.3f %.3f %.3f", f.ax, f.ay, f.az, f.dz))

	local fem = HK.Fit(Kit.Scalp(look(2)), HK.FIT0)
	print(string.format("female default ax %.3f ay %.3f az %.3f dz %.3f", fem.ax, fem.ay, fem.az, fem.dz))
	check("female ax ~0.965", near(fem.ax, 0.965, 0.01), fem.ax)
	check("female ay ~0.99", near(fem.ay, 0.99, 0.01), fem.ay)
	check("female az ~0.995", near(fem.az, 0.995, 0.01), fem.az)
	check("female dz ~-0.004", near(fem.dz, -0.004, 0.004), fem.dz)

	local big = HK.Fit(Kit.Scalp(look(1, nil, { skullWidth = 1, skullLength = 1, crown = 1, forehead = 1 })), HK.FIT0)
	local small = HK.Fit(Kit.Scalp(look(2, nil, { skullWidth = -1, skullLength = -1, crown = -1, forehead = -1 })), HK.FIT0)
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
-- the classic head (v9: the meshes modelled on it, data.fit0.shape = "classic")
------------------------------------------------------------------------
do
	local lk = look(1, nil, nil, { headShape = "classic" })
	local S = Kit.Scalp(lk)
	local W, T, Fz, Bz = HK.Measure(S)
	check("classic extents = FIT0_CLASSIC", near(W, HK.FIT0_CLASSIC.W, 0.002) and near(T, HK.FIT0_CLASSIC.T, 0.002)
		and near(Fz, HK.FIT0_CLASSIC.Fz, 0.002) and near(Bz, HK.FIT0_CLASSIC.Bz, 0.002))
	local f = HK.Fit(S, HK.FIT0_CLASSIC)
	check("classic fit0: identity", near(f.ax, 1, 0.003) and near(f.ay, 1, 0.003) and near(f.az, 1, 0.003) and near(f.dz, 0, 0.002)
		and f.dy == 0, string.format("%.3f %.3f %.3f %.3f %.3f", f.ax, f.ay, f.az, f.dz, f.dy))
	local fem = HK.Fit(Kit.Scalp(look(2, nil, nil, { headShape = "classic" })), HK.FIT0_CLASSIC)
	check("classic fit0: the female classic head too", near(fem.ax, 1, 0.003) and near(fem.az, 1, 0.003) and fem.dy == 0)
	-- the v7 manifest (organic fit0) keeps today's stopgap on the classic head
	local legacy = HK.Fit(S, HK.FIT0)
	check("organic fit0 on the classic head: CLASSIC_FIT", near(legacy.dy, HK.CLASSIC_FIT.dy, 1e-9)
		and near(legacy.ax, W / HK.FIT0.W * HK.CLASSIC_FIT.kx, 1e-6))
	-- the classic hairline: above the built face's brows (browY 0.276, the highest brows' top 0.371), round the ear
	local dist, height = Kit.Hairline(S, "Natural", 0)
	check("classic hairline front ~0.42", near(height(0), 0.421, 0.02), height(0))
	check("classic hairline over the ear above the ear top (0.2)", height(1.57) > 0.23, height(1.57))
	check("classic hairline nape -0.3", near(height(math.pi), -0.3, 0.01), height(math.pi))
	check("classic front hairline above the highest brows", height(0) - 0.04 > 0.371 - 0.03, height(0))
	-- the cap's texels on a classic fit0 are read on the classic head (its own polar UV, rays from its centre)
	local cov = HK.CapCoverage(lk, "full", { cut = "full" })
	local pal = HK.Palette(lk, "Kinky")
	local gw, gh, thMax = 24, 12, 2.27
	local grid = HK.CapGrid(S, cov, pal, thMax, gw, gh, f)
	local ok, worst = true, 0
	for j = 0, gh - 1 do
		for i = 0, gw - 1 do
			local th, az = (j + 0.5) / gh * thMax, (i + 0.5) / gw * math.pi * 2
			local x, y, z = S.ray(math.sin(th) * math.sin(az), math.cos(th), math.sin(th) * math.cos(az), 0.02)
			local px, py, pz = S.onto(x, y, z, 0)
			local c = math.clamp(cov(px, py, pz), 0, 1)
			worst = math.max(worst, math.abs(grid.c[i + j * gw + 1] - c))
			if math.abs(grid.c[i + j * gw + 1] - c) > 0.05 then
				ok = false
			end
		end
	end
	check("classic cap grid samples the classic head's polar UV", ok, worst)
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
	fit0 = HK.FIT0,
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

	-- volume: evenly by kc (clamped near 1) and outward by the rest, about the boxer's scalp point under the
	-- piece's centre (on the ray from the skull centre)
	local lk2 = look(1, { style = "Afro", type = "Kinky", length = 1, volume = 1 })
	local S2 = Kit.Scalp(lk2)
	local fit2 = HK.Fit(S2, fakeData.fit0)
	local placed2, _, _, Vf = HK.Place(fakeData, fakeData.entries[1], lk2, S2, fit2)
	local q = placed2.HairAfro01
	local kc = math.clamp(Vf, HK.VOLUME_CENTRE[1], HK.VOLUME_CENTRE[2])
	local bx, by, bz = 0, 0.34 * fit2.ay, 0.08 * fit2.az + fit2.dz
	local dx, dy, dz = bx, by - S2.cy, bz - S2.cz
	local l = math.sqrt(dx * dx + dy * dy + dz * dz)
	dx, dy, dz = dx / l, dy / l, dz / l
	local ax, ay, az = S2.ray(dx, dy, dz, 0)
	local w = 1 / math.max(dx * dx, dy * dy, dz * dz)
	local ky = kc * (1 + (Vf / kc - 1) * dy * dy * w)
	local kx = kc * (1 + (Vf / kc - 1) * dx * dx * w)
	check("volume centre y (about the scalp point)", near(q.centre[2], (ay + (by - ay) * ky) * S2.ky, 1e-9), q.centre[2])
	check("volume size", near(q.size[1], 1.3 * fit2.ax * kx * S2.kx, 1e-9) and near(q.size[2], 1.1 * fit2.ay * ky * S2.ky, 1e-9))
	-- the anchor stays where it was: on the scalp
	local m = q.map
	local qx, qy, qz = ax / fit2.ax, ay / fit2.ay, (az - fit2.dz) / fit2.az
	local mx, my, mz = HK.Apply(m, qx, qy, qz)
	check("volume anchor on the scalp", math.abs(S2.f(mx / S2.kx, my / S2.ky, mz / S2.kz)) < 1e-4 and near(my / S2.ky, ay, 1e-9))
	-- HairFX's pivot / tip and points ride the same map
	local px, py, pz = HK.Apply(m, 0, 0.9, 0)
	check("volume points follow", near(q.P[1], px, 1e-9) and near(q.P[2], py, 1e-9) and near(q.P[3], pz, 1e-9))
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
	-- the shipped data (uploaded ids): every asset style draws its asset hair, the rest stays generated
	local missing = {}
	for _, st in ipairs({ "Afro", "Long Hair", "Fade", "High Fade", "Buzz Cut", "Dreadlocks", "Short Dreads", "Braids", "Box Braids", "Cornrows", "360 Waves", "Crew Cut" }) do
		local ty = st == "Long Hair" and "Straight" or "Kinky"
		if not HK.Select(Data, look(1, { style = st, type = ty })) then
			table.insert(missing, st)
		end
	end
	check("HairAssetData: every asset style selects", #missing == 0, table.concat(missing, ", "))
	check("HairAssetData: generated styles stay generated", HK.Select(Data, look(1, { style = "Mohawk", type = "Straight" })) == nil
		and HK.Select(Data, look(1, { style = "Long Hair", type = "Curly" })) == nil)
	local zero = 0
	for _, e in ipairs(Data.entries) do
		for _, p in pairs(e.pieces) do
			if not HK.Id(p.mesh) then
				zero += 1
			end
		end
	end
	for _, t in pairs(Data.textures) do
		if not HK.Id(t.id) then
			zero += 1
		end
	end
	check("HairAssetData: no id left at 0", zero == 0 and HK.Id(Data.cap.mesh) ~= nil, zero)
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
	-- the multiply plus the dark-colour contrast lift (0.16 (1 - lum)^2 of the texel's offset from 140)
	local lum = 0.3 * r + 0.59 * g + 0.11 * b
	local d = 0.16 * (1 - math.min(1, lum)) ^ 2 * (200 - 140)
	local function q(x)
		return math.max(0, math.min(255, math.floor(200 * x + d + 0.5)))
	end
	check("flat multiply r", buffer.readu8(out, 0) == q(r), buffer.readu8(out, 0))
	check("flat multiply g/b", buffer.readu8(out, 1) == q(g) and buffer.readu8(out, 2) == q(b))
	do -- black hair keeps strand contrast: texels 60 and 220 stay well apart
		local s2 = buffer.create(2 * 4 * 4)
		for i = 0, 3 do
			local v = (i % 2 == 0) and 60 or 220
			buffer.writeu8(s2, i * 4, v)
			buffer.writeu8(s2, i * 4 + 1, v)
			buffer.writeu8(s2, i * 4 + 2, v)
			buffer.writeu8(s2, i * 4 + 3, 255)
		end
		local blk = HK.Colors(HK.Palette(look(1, { color = { 22, 19, 17 }, dye = "None" }), "Kinky"), 2, true)
		local o2 = HK.Tint(s2, 2, 2, 1, blk, false)
		check("black keeps contrast", buffer.readu8(o2, 4) - buffer.readu8(o2, 0) >= 20, buffer.readu8(o2, 4) - buffer.readu8(o2, 0))
	end
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

------------------------------------------------------------------------
-- volume pieces grow outward: the scalp side stays on the head
------------------------------------------------------------------------
do
	-- shells shaped as the afro build's mass pieces (tools/hair/out/afro: back, sides, top, front); inner points
	-- 0.025 above the reference scalp, outer ones 0.3
	local S0 = Kit.Scalp({})
	local boxes = { back = { 0.006, 0.23, 0.436, 0.987, 1.034, 0.57 }, left = { -0.379, 0.289, 0.082, 0.416, 0.855, 0.956 },
		right = { 0.37, 0.307, 0.096, 0.464, 0.842, 0.972 }, top = { 0.008, 0.624, 0.05, 0.966, 0.431, 0.967 },
		front = { 0.002, 0.491, -0.317, 0.865, 0.436, 0.376 } }
	local pieces, inner, outer = {}, {}, {}
	for name, b in pairs(boxes) do
		local pin, pout = {}, {}
		for th = 0, 110, 5 do
			for az = 0, 355, 10 do
				local t, a = math.rad(th), math.rad(az)
				local d = { math.sin(t) * math.sin(a), math.cos(t), math.sin(t) * math.cos(a) }
				local x, y, z = S0.ray(d[1], d[2], d[3], 0)
				local ix, iy, iz = x + d[1] * 0.025, y + d[2] * 0.025, z + d[3] * 0.025
				if math.abs(ix - b[1]) <= b[4] / 2 and math.abs(iy - b[2]) <= b[5] / 2 and math.abs(iz - b[3]) <= b[6] / 2 then
					table.insert(pin, { ix, iy, iz })
					table.insert(pout, { x + d[1] * 0.3, y + d[2] * 0.3, z + d[3] * 0.3 })
				end
			end
		end
		pieces["HairAfro" .. name] = { mesh = 1, tex = "coily", bbox = b, points = {}, length = "volume" }
		inner["HairAfro" .. name], outer["HairAfro" .. name] = pin, pout
	end
	local entry = { key = "afro", cap = { cut = "none" }, pieces = pieces }
	local function clearances(hair, face, old)
		local lk = look(1, hair, face)
		local S = Kit.Scalp(lk)
		local placed, fit, _, Vf = HK.Place(fakeData, entry, lk, S)
		local out = {}
		for name in pairs(pieces) do
			local m = placed[name].map
			local function f(p)
				local x, y, z
				if old then
					-- the old placement: about the skull centre by Vf
					x, y, z = p[1] * fit.ax, p[2] * fit.ay, p[3] * fit.az + fit.dz
					x, y, z = x * Vf, S.cy + (y - S.cy) * Vf, S.cz + (z - S.cz) * Vf
				else
					x, y, z = HK.Apply(m, p[1], p[2], p[3])
					x, y, z = x / S.kx, y / S.ky, z / S.kz
				end
				return S.f(x, y, z)
			end
			local lo, hi = math.huge, -math.huge
			for _, p in ipairs(inner[name]) do
				lo = math.min(lo, f(p))
			end
			for _, p in ipairs(outer[name]) do
				hi = math.max(hi, f(p))
			end
			out[name] = { lo = lo, hi = hi }
		end
		return out, Vf
	end
	local face = { skullWidth = 1, skullLength = 1, crown = 1, forehead = 1 }
	for _, fc in ipairs({ {}, face }) do
		local base = clearances({ style = "Afro", type = "Kinky", length = 0.5, volume = 0 }, fc)
		local big, Vf = clearances({ style = "Afro", type = "Kinky", length = 1, growth = 1.5, volume = 1 }, fc)
		local old = clearances({ style = "Afro", type = "Kinky", length = 1, growth = 1.5, volume = 1 }, fc, true)
		local small = clearances({ style = "Afro", type = "Kinky", length = 0, volume = -1 }, fc)
		local lift, oldLift, grow, sink = 0, 0, math.huge, math.huge
		for name, c in pairs(big) do
			lift = math.max(lift, c.lo - base[name].lo)
			oldLift = math.max(oldLift, old[name].lo - base[name].lo)
			grow = math.min(grow, c.hi / base[name].hi)
			sink = math.min(sink, small[name].lo)
		end
		print(string.format("volume Vf %.2f%s: scalp side lifts %.3f (about the centre %.3f), outward x%.2f at least; Vf min: lowest %.3f",
			Vf, fc == face and " (big skull)" or "", lift, oldLift, grow, sink))
		check("volume: scalp side stays on the head", lift <= 0.02 and oldLift > 0.1, string.format("%.3f / %.3f", lift, oldLift))
		check("volume: grows outward", grow >= 1.12, grow)
		check("volume: smallest does not sink far in", sink > -0.02, sink)
	end
end

------------------------------------------------------------------------
-- the cap's texels are read where the fitted cap mesh lies on this boxer
------------------------------------------------------------------------
do
	local lk = look(2, { style = "High Fade", type = "Straight", hairline = "Line-Up" }, { skullWidth = -1, skullLength = -1, crown = -1, forehead = -1 })
	local cov, S = HK.CapCoverage(lk, "full", { cut = "style" })
	local fit = HK.Fit(S, HK.FIT0)
	local pal = HK.Palette(lk, "Straight")
	local gw, gh = 48, 24
	local grid = HK.CapGrid(S, cov, pal, 2.2, gw, gh, fit)
	local S0 = Kit.Scalp({})
	local same, moved = true, 0
	for j = 0, gh - 1 do
		for i = 0, gw - 1 do
			local th, az = (j + 0.5) / gh * 2.2, (i + 0.5) / gw * math.pi * 2
			local d = { math.sin(th) * math.sin(az), math.cos(th), math.sin(th) * math.cos(az) }
			local x, y, z = S0.ray(d[1], d[2], d[3], 0)
			x, y, z = x + d[1] * 0.02, y + d[2] * 0.02, z + d[3] * 0.02
			local px, py, pz = S.onto(x * fit.ax, y * fit.ay, z * fit.az + fit.dz, 0)
			-- (the cached grid's rays start warm: the same point within the ray's 6e-5, a line-up's edge is 3 mm)
			if not near(grid.c[i + j * gw + 1], math.clamp(cov(px, py, pz), 0, 1), 0.05) then
				same = false
			end
			-- where the old sampling read it: this boxer's skull along the reference direction
			local ox, oy, oz = S.ray(d[1], d[2], d[3], 0)
			moved = math.max(moved, math.sqrt((ox - px) ^ 2 + (oy - py) ^ 2 + (oz - pz) ^ 2))
		end
	end
	print(string.format("cap texels on the fitted cap: up to %.4f nominal from the old (ray from the centre) sample, female min skull", moved))
	check("cap grid samples the fitted cap point", same)
	check("the old sample was off (the fix matters)", moved > 0.01, moved)
	-- the reference skull's points are cached per grid size: a second boxer's grid costs no skull rays
	local t0 = os.clock()
	HK.CapGrid(S, cov, pal, 2.2, gw, gh, fit)
	local t1 = os.clock()
	HK.CapGrid(Kit.Scalp(look(1)), cov, pal, 2.2, gw + 2, gh, nil)
	print(string.format("cap grid %dx%d warm %.1f ms, cold %.1f ms", gw, gh, (t1 - t0) * 1000, (os.clock() - t1) * 1000))
end

------------------------------------------------------------------------
-- time slicing: the gaps between MeshKit ticks (the builder yields there) at real sizes
------------------------------------------------------------------------
do
	local MeshKit = H.require("MeshKit")
	-- every gap between ticks (ms); the one after the output buffer's allocation is that allocation alone
	-- (a ~2 ms buffer.create of 4 MB: one engine-level step, kept apart by a tick on each side)
	local function gaps(fn)
		local last, list = os.clock(), {}
		MeshKit.SetTick(function()
			local t = os.clock()
			list[#list + 1] = (t - last) * 1000
			last = t
		end)
		fn()
		MeshKit.SetTick(nil)
		list[#list + 1] = (os.clock() - last) * 1000
		return list
	end
	local function summary(name, fn, allocAt)
		-- warm (the reference grid, the first big buffers), then the best of 3 runs (the machine's own pauses)
		gaps(fn)
		local best
		for _ = 1, 3 do
			local list = gaps(fn)
			local work = {}
			for i, v in ipairs(list) do
				if i ~= allocAt then
					work[#work + 1] = v
				end
			end
			table.sort(work)
			local r = { n = #list, max = work[#work], p99 = work[math.max(1, math.floor(#work * 0.99))], p50 = work[#work // 2 + 1],
				alloc = allocAt and list[allocAt] or 0 }
			if not best or r.max < best.max then
				best = r
			end
		end
		print(string.format("ticks %-16s n %5d  max %.2f ms  p99 %.2f  p50 %.3f  (allocation %.2f)", name, best.n, best.max, best.p99, best.p50, best.alloc))
		check("tick gaps " .. name .. ": p99 under 1 ms", best.p99 < 1, best.p99)
		check("tick gaps " .. name .. ": median well under 1 ms", best.p50 < 0.6, best.p50)
		return best
	end
	local lk = look(1, { style = "High Fade", type = "Coiled", hairline = "Line-Up" })
	local cov, S = HK.CapCoverage(lk, "full", { cut = "style" })
	local pal = HK.Palette(lk, "Coiled")
	local gw, gh = HK.GridSize(true)
	local grid
	summary("CapGrid 192x96", function()
		grid = HK.CapGrid(S, cov, pal, 2.2, gw, gh)
	end)
	local tile = buffer.create(256 * 256 * 4)
	buffer.fill(tile, 0, 200)
	summary("PaintCap 1024", function()
		HK.PaintCap(grid, tile, 256, 256, 8, 4, 1024, false)
	end, 2)
	local src = buffer.create(1024 * 1024 * 4)
	buffer.fill(src, 0, 180)
	local c1 = HK.Colors(pal, 1024, false, HK.BANDS)
	summary("Tint 1024 f=1", function()
		HK.Tint(src, 1024, 1024, 1, c1, false)
	end, 2)
	local c2 = HK.Colors(pal, 512, false, HK.BANDS)
	summary("Tint 1024 f=2", function()
		HK.Tint(src, 1024, 1024, 2, c2, false)
	end, 2)
end

------------------------------------------------------------------------
-- the painted cap's users and its tile: tex "cap" pieces, capTile, hair type
------------------------------------------------------------------------
do
	local d = table.clone(fakeData)
	d.textures = table.clone(fakeData.textures)
	d.textures.shortcoil = { id = 16, size = 256, tile = true }
	d.textures.waves = { id = 17, size = 256, tile = true }
	d.textures.crop = { id = 18, size = 512 }
	local fur = { mesh = 40, tex = "cap", bbox = { 0, 0.2, 0.03, 0.82, 0.86, 1.02 }, points = {} }
	local crop = { mesh = 41, tex = "crop", bbox = { 0, 0.5, -0.2, 0.6, 0.2, 0.3 }, points = {} }
	local buzz = { key = "buzz", styles = { "Buzz Cut" }, cap = { cut = "style", density = 1 }, pieces = { HairFur = fur } }
	local waves = { key = "waves", styles = { "360 Waves" }, capTile = "waves", cap = { cut = "style", density = 1 }, pieces = { HairFur = fur } }
	local shells = { key = "shells", styles = { "High Fade" }, cap = { cut = "none" }, pieces = { HairTop1 = fur, HairCrop = crop } }
	local bare = { key = "bare", styles = { "Cornrows" }, cap = { cut = "none" }, pieces = { HairCrop = crop } }
	d.entries = { buzz, waves, shells, bare }

	check("CapTile: straight -> short", HK.CapTile(d, buzz, "Straight") == "short")
	check("CapTile: wavy -> short", HK.CapTile(d, buzz, "Wavy") == "short")
	for _, ty in ipairs({ "Curly", "Kinky", "Coiled" }) do
		check("CapTile: " .. ty .. " -> shortcoil", HK.CapTile(d, buzz, ty) == "shortcoil")
	end
	check("CapTile: no type -> short", HK.CapTile(d, buzz, nil) == "short")
	check("CapTile: entry capTile wins over the type", HK.CapTile(d, waves, "Kinky") == "waves" and HK.CapTile(d, waves, "Straight") == "waves")
	-- data.cap.tiles (out/cap/style.json) overrides the built-in rule
	local dt = table.clone(d)
	dt.cap = table.clone(d.cap)
	dt.cap.tiles = { default = "short", Wavy = "shortcoil" }
	check("CapTile: data.cap.tiles by type", HK.CapTile(dt, buzz, "Wavy") == "shortcoil" and HK.CapTile(dt, buzz, "Kinky") == "short")
	-- a tile without an id: the short one
	local dn = table.clone(d)
	dn.textures = table.clone(d.textures)
	dn.textures.shortcoil = { id = 0, size = 256, tile = true }
	dn.textures.waves = nil
	check("CapTile: shortcoil without id -> short", HK.CapTile(dn, buzz, "Kinky") == "short")
	check("CapTile: capTile without id -> short", HK.CapTile(dn, waves, "Straight") == "short")

	-- TexturesOf: "cap" is the painted image, not a texture; the tile goes by the hair type
	local function keys(t)
		local out = {}
		for k in pairs(t) do
			out[#out + 1] = k
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	check("TexturesOf buzz straight", keys(HK.TexturesOf(d, buzz, "Straight")) == "short", keys(HK.TexturesOf(d, buzz, "Straight")))
	check("TexturesOf buzz kinky", keys(HK.TexturesOf(d, buzz, "Kinky")) == "shortcoil", keys(HK.TexturesOf(d, buzz, "Kinky")))
	check("TexturesOf waves", keys(HK.TexturesOf(d, waves, "Kinky")) == "waves")
	check("TexturesOf shells, cap none: still the tile", keys(HK.TexturesOf(d, shells, "Kinky")) == "crop,shortcoil", keys(HK.TexturesOf(d, shells, "Kinky")))
	check("TexturesOf no cap user: no tile", keys(HK.TexturesOf(d, bare, "Kinky")) == "crop")
	check("NeedsCapImage", HK.NeedsCapImage(buzz) and HK.NeedsCapImage(shells) and not HK.NeedsCapImage(bare) and not HK.HasCap(shells))

	-- Usable / Select require the tile the look draws with
	check("Usable: tex cap pieces need no 'cap' texture", HK.Usable(d, buzz, "Straight") and HK.Usable(d, shells, "Kinky"))
	local dk = table.clone(d)
	dk.textures = table.clone(d.textures)
	dk.textures.short = { id = 0, size = 256, tile = true }
	check("Usable: straight needs short", not HK.Usable(dk, buzz, "Straight") and HK.Usable(dk, buzz, "Kinky"))
	local function sel(data, hair)
		local e = HK.Select(data, look(1, hair))
		return e and e.key or nil
	end
	check("Select: no short id -> no straight buzz", sel(dk, { style = "Buzz Cut", type = "Straight" }) == nil)
	check("Select: no short id -> kinky buzz (shortcoil)", sel(dk, { style = "Buzz Cut", type = "Kinky" }) == "buzz")
	check("Select: waves", sel(d, { style = "360 Waves", type = "Straight" }) == "waves")
	local dw = table.clone(dk)
	dw.textures = table.clone(dk.textures)
	dw.textures.waves = { id = 0, size = 256, tile = true }
	check("Select: waves without waves or short id -> none", sel(dw, { style = "360 Waves", type = "Kinky" }) == nil)
	check("Select: shells (cap none) usable", sel(d, { style = "High Fade", type = "Coiled" }) == "shells")
	-- the skip callback is given the hair type (the client's failed ids depend on the tile)
	local gotType
	HK.Select(d, look(1, { style = "Buzz Cut", type = "Coiled" }), function(_, ht)
		gotType = ht
		return false
	end)
	check("skip gets the hair type", gotType == "Coiled", gotType)
	-- Place: an entry without HairCap in its pieces still gets the shared cap (cut style)
	local lk = look(1, { style = "Buzz Cut", type = "Kinky" })
	local placed = HK.Place(d, buzz, lk, Kit.Scalp(lk))
	check("Place: the shared cap for a tex-cap entry", placed.HairCap ~= nil and placed.HairFur ~= nil)
	local placedS = HK.Place(d, shells, lk, Kit.Scalp(lk))
	check("Place: cap none -> no HairCap mesh", placedS.HairCap == nil and placedS.HairTop1 ~= nil)
end

------------------------------------------------------------------------
-- the cap's fade: strands / coils thin out (thresholded over the tile's rank), not uniformly translucent
------------------------------------------------------------------------
do
	-- a 32 x 32 tile of "coils": alpha and grey vary (a dome per 8 x 8 cell, a faint fringe, some empty texels)
	local tw, th = 32, 32
	local tile = buffer.create(tw * th * 4)
	for j = 0, th - 1 do
		for i = 0, tw - 1 do
			local cx, cy = (i % 8) - 3.5, (j % 8) - 3.5
			local r = math.sqrt(cx * cx + cy * cy) / 4.95
			local a = math.clamp(1.15 - r * r * 1.3, 0, 1)
			local h = math.sin(i * 12.9898 + j * 78.233) * 43758.5453
			a = math.clamp(a * (0.85 + 0.15 * (h - math.floor(h))), 0, 1)
			local grey = math.floor(255 * (0.35 + 0.6 * (1 - r)))
			local o = (i + j * tw) * 4
			buffer.writeu8(tile, o, math.clamp(grey, 0, 255))
			buffer.writeu8(tile, o + 1, math.clamp(grey, 0, 255))
			buffer.writeu8(tile, o + 2, math.clamp(grey, 0, 255))
			buffer.writeu8(tile, o + 3, math.floor(a * 255 + 0.5))
		end
	end
	-- a flat grid of one coverage c
	local function gridOf(c)
		local n = 4 * 4
		local g = { r = table.create(n, 0.5), g = table.create(n, 0.4), b = table.create(n, 0.3), c = table.create(n, c), w = 4, h = 4 }
		return g
	end
	-- the output is texel-aligned with the tile (size = tw x nu): alpha(c = 1) must be the tile's own alpha
	local nu, size = 2, 64
	local function paint(c, k)
		return HK.PaintCap(gridOf(c), tile, tw, th, nu, nu, size, false, 1, k)
	end
	local full = paint(1)
	local exact = true
	for j = 0, size - 1 do
		for i = 0, size - 1 do
			local a = buffer.readu8(full, (i + j * size) * 4 + 3)
			local ta = buffer.readu8(tile, ((i % tw) + (j % th) * tw) * 4 + 3)
			if a ~= ta then
				exact = false
			end
		end
	end
	check("cap fade: alpha(c = 1) = tile alpha", exact)
	local function stats(buf)
		local sum, semi, solid = 0, 0, 0
		for j = 0, size - 1 do
			for i = 0, size - 1 do
				local a = buffer.readu8(buf, (i + j * size) * 4 + 3)
				local ta = buffer.readu8(tile, ((i % tw) + (j % th) * tw) * 4 + 3)
				sum += a
				if ta > 76 then
					solid += 1
					local q = a / ta
					if q > 0.1 and q < 0.9 then
						semi += 1
					end
				end
			end
		end
		return sum / (size * size * 255), semi / math.max(1, solid)
	end
	local fullMean = stats(full)
	local prev, mono, curve = -1, true, {}
	local semiT, semiM = 0, 0
	for s = 0, 20 do
		local c = s / 20
		local m, semi = stats(paint(c))
		local _, semiMul = stats(paint(c, 0))
		if m < prev - 1e-9 then
			mono = false
		end
		prev = m
		if s % 5 == 0 then
			curve[#curve + 1] = string.format("%.2f:%.2f", c, m / fullMean)
		end
		if s == 10 then
			semiT, semiM = semi, semiMul
		end
	end
	print("cap fade mean alpha / full by coverage: " .. table.concat(curve, " ")
		.. string.format("; translucent texels at c 0.5: threshold %.2f, multiply %.2f", semiT, semiM))
	check("cap fade: mean alpha rises with c", mono)
	check("cap fade: none at c = 0", stats(paint(0)) == 0)
	check("cap fade: continuous at c = 1", math.abs(stats(paint(0.999)) - fullMean) < 0.01, stats(paint(0.999)))
	check("cap fade: continuous at c = 0", stats(paint(0.004)) < 0.01, stats(paint(0.004)))
	local half = stats(paint(0.5)) / fullMean
	check("cap fade: c 0.5 about half", half > 0.3 and half < 0.75, half)
	check("cap fade: thins whole coils (few translucent texels)", semiT < 0.4 and semiM > 0.9, string.format("%.2f %.2f", semiT, semiM))
	check("cap fade: k 0 = the old multiply", buffer.readu8(paint(0.5, 0), 3 + 4 * 3) == math.floor(buffer.readu8(tile, 3 + 4 * 3) * 0.5 + 0.5))
	-- the rank is cached per tile
	check("TileRank cached", HK.TileRank(tile, tw, th) == HK.TileRank(tile, tw, th))
end

------------------------------------------------------------------------
-- the real builds: tools/hair/out/*/style.json through publish.py --local (fake ids, nothing uploaded)
------------------------------------------------------------------------
do
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local luau = require("@lune/luau")
	local out = "/tmp/claude-0/test_hairassets_local.lua"
	local res = process.exec("python3", { "tools/hair/publish.py", "--local", out })
	check("publish.py --local runs", res.ok, res.stderr)
	local okL, real = pcall(function()
		return luau.load(fs.readFile(out), { debugName = "HairAssetData_local" })()
	end)
	check("local manifest loads", okL and type(real) == "table", real)
	if okL and type(real) == "table" then
		local side = require("@lune/serde").decode("json", fs.readFile(out:gsub("%.lua$", "") .. ".ids.json"))
		local nIds = 0
		for _ in pairs(side.ids) do
			nIds += 1
		end
		print(string.format("local manifest: %d entries, %d fake ids", #real.entries, nIds))
		-- (v9: modelled on the classic head, its cap to 130 deg from its centre; v7: the organic skull's, 148 deg)
		local classicData = type(real.fit0) == "table" and real.fit0.shape == "classic"
		local headX = classicData and { headShape = "classic" } or nil
		check("cap from out/cap", real.cap and real.cap.thetaMax
			and math.abs(real.cap.thetaMax - (classicData and 2.26893 or 2.58309)) < 1e-4
			and real.cap.tiles and real.cap.tiles.Kinky == "shortcoil" and HK.Id(real.cap.mesh) ~= nil)
		check("tiles flagged", real.textures.short.tile and real.textures.shortcoil.tile and real.textures.waves.tile
			and not real.textures.crop.tile)
		local byKey = {}
		for _, e in ipairs(real.entries) do
			byKey[e.key] = e
		end
		check("waves360 carries capTile", byKey.waves360 and byKey.waves360.capTile == "waves")
		check("afro pieces Fabric", byKey.afro and (function()
			for _, p in pairs(byKey.afro.pieces) do
				if p.material ~= "Fabric" then
					return false
				end
			end
			return next(byKey.afro.pieces) ~= nil
		end)())
		check("every id resolves to a file", (function()
			for _, e in ipairs(real.entries) do
				for _, p in pairs(e.pieces) do
					if not side.ids[tostring(p.mesh)] then
						return false
					end
				end
			end
			return side.ids[tostring(real.cap.mesh)] ~= nil
		end)())
		local cases = {
			{ "Buzz Cut", "Kinky", "buzz", "shortcoil" },
			{ "Buzz Cut", "Straight", "buzz", "short" },
			{ "High Fade", "Straight", "fade_high", "short" },
			{ "High Fade", "Kinky", "fade_high_c", "shortcoil" },
			{ "360 Waves", "Straight", "waves360", "waves" },
			{ "360 Waves", "Kinky", "waves360", "waves" },
			{ "Afro", "Kinky", "afro", "shortcoil" },
			{ "Afro", "Curly", "afro_curly", "shortcoil" },
			{ "High Top", "Kinky", "hightop", "shortcoil" },
			{ "High Top", "Straight", "hightop", "short" },
			{ "Mid Fade", "Wavy", "fade_mid", "short" },
			{ "Fade", "Coiled", "fade_mid_c", "shortcoil" },
			{ "Crew Cut", "Curly", "crew_c", "shortcoil" },
			{ "Caesar Cut", "Straight", "caesar", "short" },
		}
		for _, cs in ipairs(cases) do
			local lk = look(1, { style = cs[1], type = cs[2] })
			local e, _, ht = HK.Select(real, lk)
			local tileKey = e and HK.CapTile(real, e, ht)
			check(string.format("real Select %s / %s -> %s (%s)", cs[1], cs[2], cs[3], cs[4]), e and e.key == cs[3] and tileKey == cs[4],
				(e and e.key or "nil") .. " " .. tostring(tileKey))
		end
		-- every entry is usable on each of its types
		local bad = {}
		for _, e in ipairs(real.entries) do
			for _, ty in ipairs(e.types or { "Straight", "Kinky" }) do
				if not HK.Usable(real, e, ty) then
					bad[#bad + 1] = e.key .. "/" .. ty
				end
			end
		end
		check("every real entry usable", #bad == 0, table.concat(bad, ","))

		-- the afro at the volume extremes: the edge rings (no length flag) never move, the volume pieces stay
		-- out of the head
		for _, key in ipairs({ "afro", "afro_curly", "hightop" }) do
			local e = byKey[key]
			local worstIn, edgeMoved = math.huge, 0
			for _, hair in ipairs({ { length = 0, volume = -1 }, { length = 0.5, volume = 0 }, { length = 1, growth = 1.5, volume = 1 } }) do
				hair.style, hair.type = e.styles[1], (e.types and e.types[1]) or "Kinky"
				local lk = look(1, hair, nil, headX)
				local S = Kit.Scalp(lk)
				local fit = HK.Fit(S, real.fit0)
				local placed = HK.Place(real, e, lk, S, fit)
				for name, p in pairs(e.pieces) do
					local m = placed[name].map
					if p.length == nil then
						local bm = { fit.ax * S.kx, fit.ay * S.ky, fit.az * S.kz, 0, 0, fit.dz * S.kz }
						for i = 1, 6 do
							edgeMoved = math.max(edgeMoved, math.abs(m[i] - bm[i]))
						end
					else
						local pts = p.points
						for i = 1, #pts - 2, 3 do
							local x, y, z = HK.Apply(m, pts[i], pts[i + 1], pts[i + 2])
							worstIn = math.min(worstIn, S.f(x / S.kx, y / S.ky, z / S.kz))
						end
					end
				end
			end
			print(string.format("%s volume extremes: edge ring moved %.2g, volume pieces' lowest point %.4f above the skull", key, edgeMoved, worstIn))
			check(key .. ": edge ring fixed at every volume", edgeMoved < 1e-9, edgeMoved)
			check(key .. ": volume pieces stay out of the head", worstIn > -0.01, worstIn)
		end
	end
end

------------------------------------------------------------------------
-- capFade: a crew cut's tapered sides on a natural hairline
------------------------------------------------------------------------
do
	local lk = look(1, { style = "Crew Cut", type = "Straight" })
	local full, S = HK.CapCoverage(lk, "full", { cut = "style" })
	local taper = HK.CapCoverage(lk, "full", { cut = "style" }, S, "fade")
	local x, y, z = S.ray(1, 0, 0.3, 0) -- low on the side, above and behind the ear
	local tx, ty, tz = S.ray(0, 1, 0, 0) -- the top
	check("capFade thins the low sides", taper(x, y, z) < full(x, y, z) - 0.2, string.format("%.2f vs %.2f", taper(x, y, z), full(x, y, z)))
	check("capFade keeps the top", taper(tx, ty, tz) > 0.9, taper(tx, ty, tz))
	check("unknown capFade is ignored", HK.CapCoverage(lk, "full", { cut = "style" }, S, "nope")(x, y, z) == full(x, y, z))
end

------------------------------------------------------------------------
-- capEarLine: the barber's line round each ear
------------------------------------------------------------------------
do
	local E = { centre = { -0.07, 0.148 }, axes = { 0.19, 0.128 }, xmin = 0.24, feather = 0.03 }
	local one = function()
		return 1
	end
	local f = HK.EarLined(one, E)
	check("ear line: 0 at the ear", f(0.38, -0.07, 0.148) == 0)
	check("ear line: full well above the ear", f(0.38, 0.2, 0.148) == 1)
	check("ear line: full on the crown (|x| < xmin)", f(0.1, -0.07, 0.148) == 1)
	local mid = f(0.38, -0.07 + 0.19 + 0.015, 0.148)
	check("ear line: feathered just outside", mid > 0 and mid < 1, mid)
	local lk = look(1, { style = "Low Fade", type = "Kinky" })
	local cov, S = HK.CapCoverage(lk, "full", { cut = "style" }, nil, nil, E)
	check("CapCoverage applies the ear line", cov(0.38, -0.07, 0.148) == 0)
end

print(string.format("test_hairassets: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_hairassets failed")
end
