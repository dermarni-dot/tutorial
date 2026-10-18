-- HairAssetKit: the pure half of the asset hair (tools/hair/CONTRACT.md; the client's HairAssets does the
-- engine half). No Instances, deterministic, so lune tests run it as the client does.
-- * Select(data, look): the HairAssetData entry a look draws (AnatomyHair's own style / type routing:
--   Gen.Resolve), nil for Bald, an unknown look or an entry with an id still missing (Usable)
-- * CapTile / NeedsCapImage / TexturesOf: the painted cap image (the HairCap's, and every tex "cap" piece's: the
--   fades' shells and fur) and the tile it is painted from (entry.capTile, else short / shortcoil by hair type)
-- * Fit(S, fit0): the per-boxer skull fit (W, T, Fz, Bz from the skull field, against the default male's)
-- * LengthFactor / VolumeFactor(look): the per-style length / volume stretch
-- * Place(data, entry, look, S): every piece's affine map nominal -> Head space (diagonal scale + offset),
--   its MeshPart size and weld centre, its HairFX pivot / tip and point cloud, and the cap's
-- * CapCoverage(look, lod, capSpec, S): the coverage the cap's alpha takes (the style's own Kit.Cut, or a
--   natural hairline); CapGrid + PaintCap paint the cap texture from it
-- * Colors / Tint / ColorKey: the greyscale card textures tinted by the look's palette (Kit.Palette's rules:
--   darker roots, lighter tips, dye along v, streaks and highlights on u bands, age greying)
-- Heavy loops call MeshKit.Step (the builder's tick yields there: time-sliced, cancellable).
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyHairKit"))
local Gen = require(Shared:WaitForChild("AnatomyHair"))

local HK = {}

local abs, floor, min, max, sin, cos, pi = math.abs, math.floor, math.min, math.max, math.sin, math.cos, math.pi
local TAU = pi * 2
local clamp, lerp, num = Kit.clamp, Kit.lerp, Kit.num
local step = MeshKit.Step
-- a tick at once (before and after one big allocation: a 4 MB buffer.create is ~1.7 ms that cannot be
-- sliced, kept apart from the loop's own slices)
local function stepNow()
	step(MeshKit.TICK_EVERY)
end
local readu8, writeu8, writeu32 = buffer.readu8, buffer.writeu8, buffer.writeu32

-- the default male skull's extents (skull.json fit0): the meshes are modelled on it
HK.FIT0 = { W = 0.383, T = 0.591, Fz = -0.460, Bz = 0.520 }
-- textures drawn as one flat colour (tileable: no root or tip along v) even when the data does not say so
local FLAT = { short = true, shortcoil = true, waves = true, braid = true, cornrow = true }
-- hair types whose scalp cap takes the coiled tile (when the entry names none: data.cap.tiles, else this)
local CURLY = { Curly = true, Kinky = true, Coiled = true }
-- the cap's fade (PaintCap): the threshold's width is 1 / CAP_FADE_K of the tile's alpha rank
HK.CAP_FADE_K = 4
-- u bands a card texture's strands are coloured by (streaks, highlights, the per-lock variation): 3 per strip
HK.BANDS = 12

------------------------------------------------------------------------
-- Entry selection
------------------------------------------------------------------------
local function idOf(v)
	local n = tonumber(v)
	return (n and n > 0) and floor(n) or nil
end
HK.Id = idOf

local function listHas(list, v)
	if type(list) ~= "table" then
		return false
	end
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

-- the entry draws the shared HairCap mesh (data.cap): its cap spec paints one
function HK.HasCap(entry)
	local c = entry.cap
	return type(c) == "table" and (c.cut == "style" or c.cut == "full")
end

-- the entry needs the boxer's painted cap image: for the HairCap, or for pieces drawn with it (tex "cap": the
-- fades' shells and fur, on the cap's polar UV)
function HK.NeedsCapImage(entry)
	if HK.HasCap(entry) then
		return true
	end
	for _, p in pairs(type(entry.pieces) == "table" and entry.pieces or {}) do
		if type(p) == "table" and p.tex == "cap" then
			return true
		end
	end
	return false
end

local function texHasId(data, key)
	local t = type(data) == "table" and type(data.textures) == "table" and data.textures[key] or nil
	return type(t) == "table" and idOf(t.id) ~= nil
end

-- the tile texture the cap is painted with for this entry on hair type htype (Gen.Resolve's): the entry's own
-- capTile ("waves"), else data.cap.tiles by type (tools/hair/out/cap: "shortcoil" for curly / coily hair),
-- else "shortcoil" for Curly / Kinky / Coiled and "short" otherwise; "short" when the chosen one has no id
function HK.CapTile(data, entry, htype)
	local want = type(entry) == "table" and type(entry.capTile) == "string" and entry.capTile or nil
	if not want then
		local cap = type(data) == "table" and data.cap or nil
		local tiles = type(cap) == "table" and type(cap.tiles) == "table" and cap.tiles or nil
		if tiles then
			want = (htype and tiles[htype]) or tiles.default
		end
		if type(want) ~= "string" then
			want = CURLY[htype] and "shortcoil" or "short"
		end
	end
	if want ~= "short" and not texHasId(data, want) then
		want = "short"
	end
	return want
end

-- the texture keys an entry needs on hair type htype: its pieces' (tex "cap" is the painted cap, not a texture)
-- and, when it paints the cap, the cap's tile (CapTile)
function HK.TexturesOf(data, entry, htype)
	local out = {}
	for _, p in pairs(type(entry.pieces) == "table" and entry.pieces or {}) do
		if type(p.tex) == "string" and p.tex ~= "cap" then
			out[p.tex] = true
		end
	end
	if HK.NeedsCapImage(entry) then
		out[HK.CapTile(data, entry, htype)] = true
	end
	return out
end

-- a tex "cap" piece's fur-shell variant of the painted cap: its capShell { rank = 0..1, cov = 0..1 } (nil: the
-- cap image itself) and the key its image is shared under within a build
function HK.CapShellOf(piece)
	local s = type(piece) == "table" and piece.tex == "cap" and piece.capShell or nil
	if type(s) ~= "table" then
		return nil
	end
	local r, c = clamp(tonumber(s.rank) or 0, 0, 0.98), clamp(tonumber(s.cov) or 0, 0, 0.95)
	if r <= 0 and c <= 0 then
		return nil
	end
	return { rank = r, cov = c }, string.format("%.3f/%.3f", r, c)
end

-- the distinct shell variants an entry's pieces ask for: key -> spec
function HK.CapShells(entry)
	local out = {}
	for _, p in pairs(type(entry) == "table" and type(entry.pieces) == "table" and entry.pieces or {}) do
		local s, key = HK.CapShellOf(p)
		if s then
			out[key] = s
		end
	end
	return out
end

-- the crown's planar sampling for this entry's cap (out/cap/style.json pole = { theta0, theta1, su, sv }):
-- nil for a whole-cap image (capTileRepeat { 1, 1 }) or when the cap data has none. See PaintCap
function HK.CapPole(data, entry)
	local nu = HK.CapRepeat(data, entry)
	local cap = type(data) == "table" and data.cap or nil
	local p = type(cap) == "table" and cap.pole or nil
	if nu <= 1 or type(p) ~= "table" then
		return nil
	end
	local t0, t1 = tonumber(p.theta0), tonumber(p.theta1)
	local su, sv = tonumber(p.su), tonumber(p.sv)
	if not (t0 and t1 and su and sv) or t1 <= t0 or su <= 0 or sv <= 0 then
		return nil
	end
	return { theta0 = t0, theta1 = t1, su = su, sv = sv, thetaMax = tonumber(cap.thetaMax) or 2.2 }
end

-- the tile's repeats over the cap for this entry: its capTileRepeat ({ 1, 1 }: a whole-cap texture such as
-- the waves), else data.cap.tile, else 8 x 4
function HK.CapRepeat(data, entry)
	local t = type(entry) == "table" and entry.capTileRepeat or nil
	if type(t) ~= "table" then
		local cap = type(data) == "table" and data.cap or nil
		t = type(cap) == "table" and cap.tile or nil
	end
	if type(t) ~= "table" then
		return 8, 4
	end
	return math.max(1, floor(tonumber(t[1]) or 8)), math.max(1, floor(tonumber(t[2]) or 4))
end

-- every mesh and texture id the entry needs (on hair type htype: the cap's tile) is uploaded; the entry draws
-- something (pieces or a cap)
function HK.Usable(data, entry, htype)
	if type(data) ~= "table" or type(entry) ~= "table" then
		return false
	end
	local textures = type(data.textures) == "table" and data.textures or {}
	local any = false
	for _, p in pairs(type(entry.pieces) == "table" and entry.pieces or {}) do
		if not idOf(p.mesh) or type(p.bbox) ~= "table" or #p.bbox < 6 then
			return false
		end
		any = true
	end
	if HK.HasCap(entry) then
		local cap = data.cap
		if type(cap) ~= "table" or not idOf(cap.mesh) or type(cap.bbox) ~= "table" or #cap.bbox < 6 then
			return false
		end
		any = true
	end
	for key in pairs(HK.TexturesOf(data, entry, htype)) do
		local t = textures[key]
		if type(t) ~= "table" or not idOf(t.id) then
			return false
		end
	end
	return any
end

-- the entry the look draws, or nil: style / type as AnatomyHair routes them (a curly Long Hair is AnatomyHair's
-- longCurly recipe: only an entry listing that type takes it), Bald never. skip(entry) -> true leaves an entry
-- out (its asset failed to load; it is given the look's resolved hair type too)
function HK.Select(data, look, skip)
	if type(data) ~= "table" or type(data.entries) ~= "table" then
		return nil
	end
	look = type(look) == "table" and look or {}
	local style, htype = Gen.Resolve(look)
	if style == "Bald" then
		return nil
	end
	local raw = type(look.hair) == "table" and look.hair.style or nil
	for pass = 1, 2 do
		-- (the recipe's style first; then the look's own id, for an entry written for a style without a recipe)
		local want = pass == 1 and style or raw
		if want and (pass == 1 or want ~= style) then
			for _, e in ipairs(data.entries) do
				if type(e) == "table" and listHas(e.styles, want) and (e.types == nil or listHas(e.types, htype)) then
					if HK.Usable(data, e, htype) and not (skip and skip(e, htype)) then
						return e, style, htype
					end
				end
			end
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Skull fit
------------------------------------------------------------------------
-- distance from (ox, oy, oz) along a unit direction to the field's zero set (bisection: the origin is inside)
local function crossing(f, ox, oy, oz, dx, dy, dz)
	local lo, hi = 0, 1.6
	if f(ox, oy, oz) >= 0 then
		return 0
	end
	for _ = 1, 40 do
		local m = (lo + hi) * 0.5
		if f(ox + dx * m, oy + dy * m, oz + dz * m) < 0 then
			lo = m
		else
			hi = m
		end
	end
	return (lo + hi) * 0.5
end

-- the boxer's skull against the default male's (CONTRACT: W at y 0.15 toward +X, T straight up from the skull
-- centre, Fz at y 0.2 toward -Z, Bz at y 0.1 toward +Z): ax = W / W0, ay = T / T0 (about y = 0), az = the front
-- to back span's ratio, dz = the shift of its middle
function HK.Measure(S)
	local f, cz = S.f, S.cz or 0.035
	local W = crossing(f, 0, 0.15, cz, 1, 0, 0)
	local T = (S.cy or 0.15) + crossing(f, 0, S.cy or 0.15, cz, 0, 1, 0)
	local Fz = cz - crossing(f, 0, 0.2, cz, 0, 0, -1)
	local Bz = cz + crossing(f, 0, 0.1, cz, 0, 0, 1)
	return W, T, Fz, Bz
end

-- The classic head (S.classic: Kit.Scalp of a look.headShape "classic") is a rounded cylinder, the cards' skull an
-- ellipsoid: matched only at the four extents above, the cap sank up to 0.141 (nominal) into the classic head's
-- upper corners (10 % of its points more than 0.059 under the surface; tools/sim/fit_classic_hair.luau). On it
-- the fit takes CLASSIC_FIT on top (per-axis x 1.06 / 1.20 / 1.20 and 0.06 down: the best per-axis map found
-- for the cap, 2 % of its points at most 0.01 under the surface, worst 0.055 at the top corners, its middle
-- 0.066 above the head)
HK.CLASSIC_FIT = { kx = 1.06, ky = 1.2, kz = 1.2, dy = -0.06 }

function HK.Fit(S, fit0)
	fit0 = type(fit0) == "table" and fit0 or HK.FIT0
	local W0, T0 = num(fit0.W, HK.FIT0.W), num(fit0.T, HK.FIT0.T)
	local F0, B0 = num(fit0.Fz, HK.FIT0.Fz), num(fit0.Bz, HK.FIT0.Bz)
	local W, T, Fz, Bz = HK.Measure(S)
	local fit = {
		W = W, T = T, Fz = Fz, Bz = Bz,
		ax = W / W0, ay = T / T0, az = (Bz - Fz) / (B0 - F0), dz = (Bz + Fz) / 2 - (B0 + F0) / 2, dy = 0,
	}
	if S.classic then
		local C = HK.CLASSIC_FIT
		fit.ax, fit.ay, fit.az, fit.dy = fit.ax * C.kx, fit.ay * C.ky, fit.az * C.kz, C.dy
	end
	return fit
end

------------------------------------------------------------------------
-- Length and volume
------------------------------------------------------------------------
-- AnatomyHair's effective length (H.len: the cut's length plus 0.6 x what grew since), 0..1.5
function HK.Len(look)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	return clamp(clamp(num(hair.length, 0.5), 0, 1) + clamp(num(hair.growth, 0), 0, 1.5) * 0.6, 0, 1.5)
end

-- hanging hair's stretch along y: 1 at the default length (0.5), 0.6 cropped short .. 1.45 at the longest
function HK.LengthFactor(look)
	return clamp(0.6 + 0.8 * HK.Len(look), 0.6, 1.45)
end

-- a volume's (afro, high top) scale: the volume slider and the length. Place splits it: at most
-- VOLUME_CENTRE about the skull centre (the shell grows round the head a little), the rest about the scalp
-- point under the piece (it grows outward: the inner surface stays on the head, never a hollow shell)
function HK.VolumeFactor(look)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	local vol = clamp(num(hair.volume, 0), -1, 1)
	return clamp(1 + 0.18 * vol + 0.25 * (HK.Len(look) - 0.5), 0.8, 1.3)
end
HK.VOLUME_CENTRE = { 0.94, 1.10 }

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------
-- an affine map with a diagonal matrix: p' = s * p + o (per axis)
local function xf(sx, sy, sz, ox, oy, oz)
	return { sx, sy, sz, ox, oy, oz }
end
function HK.Apply(m, x, y, z)
	return m[1] * x + m[4], m[2] * y + m[5], m[3] * z + m[6]
end
-- y -> c + (y - c) * k after m
local function stretchY(m, c, k)
	return xf(m[1], m[2] * k, m[3], m[4], c + (m[5] - c) * k, m[6])
end
-- p -> C + (p - C) * k after m
local function scaleAbout(m, cx, cy, cz, k)
	return xf(m[1] * k, m[2] * k, m[3] * k, cx + (m[4] - cx) * k, cy + (m[5] - cy) * k, cz + (m[6] - cz) * k)
end
-- p -> C + (p - C) * (kx, ky, kz) after m
local function scaleAbout3(m, cx, cy, cz, kx, ky, kz)
	return xf(m[1] * kx, m[2] * ky, m[3] * kz, cx + (m[4] - cx) * kx, cy + (m[5] - cy) * ky, cz + (m[6] - cz) * kz)
end
-- then nominal -> real (the head's size per axis)
local function toReal(m, kx, ky, kz)
	return xf(m[1] * kx, m[2] * ky, m[3] * kz, m[4] * kx, m[5] * ky, m[6] * kz)
end

-- the lowest a hanging chain may reach after its stretch (nominal y): the torso box's middle (mid-back)
local function hangFloor(S)
	local t = S.torso
	return type(t) == "table" and num(t[2], -1.8) or -1.8
end

-- one piece's placement from its nominal data and its map m (nominal -> real)
local function placeOf(name, ap, m)
	local b = ap.bbox
	local cx, cy, cz = HK.Apply(m, b[1], b[2], b[3])
	local out = {
		name = name, map = m, centre = { cx, cy, cz }, size = { abs(m[1] * b[4]), abs(m[2] * b[5]), abs(m[3] * b[6]) },
		bounds = { cx - abs(m[1] * b[4]) / 2, cy - abs(m[2] * b[5]) / 2, cz - abs(m[3] * b[6]) / 2,
			cx + abs(m[1] * b[4]) / 2, cy + abs(m[2] * b[5]) / 2, cz + abs(m[3] * b[6]) / 2 },
	}
	-- the point cloud HairFX samples (head space, as a generated piece's vertices)
	local pts = type(ap.points) == "table" and ap.points or {}
	local P = table.create(#pts)
	for i = 1, #pts - 2, 3 do
		local x, y, z = HK.Apply(m, pts[i], pts[i + 1], pts[i + 2])
		P[i], P[i + 1], P[i + 2] = x, y, z
	end
	if #P == 0 then
		-- no cloud exported: the box's corners and centre (enough for the samples HairFX takes)
		local x0, y0, z0, x1, y1, z1 = table.unpack(out.bounds)
		for _, c in ipairs({ { x0, y0, z0 }, { x1, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, { x0, y0, z1 }, { x1, y0, z1 },
			{ x0, y1, z1 }, { x1, y1, z1 }, { cx, cy, cz } }) do
			P[#P + 1], P[#P + 2], P[#P + 3] = c[1], c[2], c[3]
		end
	end
	out.P, out.nv = P, #P // 3
	local fx = ap.hairfx
	if type(fx) == "table" and type(fx.pivot) == "table" then
		local tip = type(fx.tip) == "table" and fx.tip or { fx.pivot[1], fx.pivot[2] - 0.3, fx.pivot[3] }
		local px, py, pz = HK.Apply(m, fx.pivot[1], fx.pivot[2], fx.pivot[3])
		local tx, ty, tz = HK.Apply(m, tip[1], tip[2], tip[3])
		out.hairfx = {
			kind = fx.kind == "bounce" and "bounce" or "swing", chain = fx.chain, seg = fx.seg, parent = fx.parent,
			stiff = fx.stiff, mass = fx.mass, pivot = { px, py, pz }, tip = { tx, ty, tz },
		}
		out.landmarks = { [name .. ".0"] = { px, py, pz }, [name .. ".1"] = { tx, ty, tz } }
	end
	return out
end

-- every piece's placement for this boxer: { [name] = { map, centre, size, bounds, P, nv, hairfx, landmarks } }
-- (the cap as "HairCap" when the entry has one), plus the fit, the length and the volume factors used
function HK.Place(data, entry, look, S, fit)
	fit = fit or HK.Fit(S, data.fit0)
	local kx, ky, kz = num(S.kx, 1), num(S.ky, 1), num(S.kz, 1)
	local base = xf(fit.ax, fit.ay, fit.az, 0, num(fit.dy, 0), fit.dz)
	local Lf, Vf = HK.LengthFactor(look), HK.VolumeFactor(look)
	local pieces = type(entry.pieces) == "table" and entry.pieces or {}
	-- hanging chains stretch as one about their root's pivot (a lower segment about its own would tear open at
	-- the joint), each no lower than the floor
	local function rootOf(name)
		local seen = 0
		local cur = name
		while seen < 8 do
			local fx = pieces[cur] and pieces[cur].hairfx
			local parent = type(fx) == "table" and fx.parent or nil
			if not (parent and pieces[parent]) then
				break
			end
			cur, seen = parent, seen + 1
		end
		return cur
	end
	local chains = {}
	for name, ap in pairs(pieces) do
		if ap.length == "hang" then
			local root = rootOf(name)
			local ch = chains[root]
			if not ch then
				local rp = pieces[root]
				local fx = rp.hairfx
				local ay = type(fx) == "table" and type(fx.pivot) == "table" and fx.pivot[2] or (rp.bbox[2] + rp.bbox[5] / 2)
				ch = { anchor = ay * fit.ay + num(fit.dy, 0), bottom = math.huge }
				chains[root] = ch
			end
			ch.bottom = min(ch.bottom, (ap.bbox[2] - ap.bbox[5] / 2) * fit.ay + num(fit.dy, 0))
		end
	end
	local yFloor = hangFloor(S)
	for _, ch in pairs(chains) do
		local k = Lf
		if k > 1 and ch.bottom < ch.anchor then
			k = max(1, min(k, (ch.anchor - yFloor) / (ch.anchor - ch.bottom)))
		end
		ch.k = k
	end
	local out = {}
	for name, ap in pairs(pieces) do
		local m = base
		if ap.length == "hang" then
			local ch = chains[rootOf(name)]
			m = stretchY(m, ch.anchor, ch.k)
		elseif ap.length == "volume" then
			-- about A, the boxer's scalp point under the piece's centre (on the ray from the skull centre C):
			-- the scalp under it stays put and the piece grows away from the head (about C its scalp side
			-- lifted ~0.15 at the largest: a hollow shell). Evenly by kc (kept near 1), then by the rest of Vf
			-- per axis by how much the ray lies along it (a side piece thickens sideways, not up and down its
			-- length, where its ends would leave the head)
			local cy, cz = num(S.cy, 0.15), num(S.cz, 0.035)
			local kc = clamp(Vf, HK.VOLUME_CENTRE[1], HK.VOLUME_CENTRE[2])
			local bx, by, bz = HK.Apply(m, ap.bbox[1], ap.bbox[2], ap.bbox[3])
			local dx, dy, dz = bx - num(S.cx, 0), by - cy, bz - cz
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			if l > 1e-6 and type(S.ray) == "function" then
				dx, dy, dz = dx / l, dy / l, dz / l
				local px, py, pz = S.ray(dx, dy, dz, 0)
				local ko = Vf / kc - 1
				local w = 1 / max(dx * dx, dy * dy, dz * dz)
				m = scaleAbout(m, px, py, pz, kc)
				m = scaleAbout3(m, px, py, pz, 1 + ko * dx * dx * w, 1 + ko * dy * dy * w, 1 + ko * dz * dz * w)
			else
				m = scaleAbout(m, num(S.cx, 0), cy, cz, Vf)
			end
		end
		out[name] = placeOf(name, ap, toReal(m, kx, ky, kz))
	end
	if HK.HasCap(entry) and type(data.cap) == "table" then
		out.HairCap = placeOf("HairCap", data.cap, toReal(base, kx, ky, kz))
	end
	return out, fit, Lf, Vf
end

------------------------------------------------------------------------
-- The cap's coverage
------------------------------------------------------------------------
-- cov(x, y, z) -> 0..1 at a nominal scalp point of THIS boxer's skull: the style's own cut (the coverage the
-- generated HairCap draws: fades, hairline type, line-up, growth) for cut "style", else a natural hairline at
-- the entry's density ("full"). capFade (an entry's optional Kit.FADES key) puts that fade on a natural
-- hairline instead (a crew cut's tapered sides, which its recipe draws without a fade). earLine (the cap data's
-- earLine, for entries with capEarLine): the barber's line round each ear, an ellipse in the side (y, z) plane
-- beyond |x| > xmin with coverage 0 inside and a smoothstep over feather outside, so a fade's cap and shells end
-- in a clean arc over the ear. Also returns the scalp S and whether the edge is sharp (a line-up)
local function earLined(cov, E)
	local cy, cz = num(E.centre and E.centre[1], -0.07), num(E.centre and E.centre[2], 0.148)
	local ay, az = max(1e-3, num(E.axes and E.axes[1], 0.19)), max(1e-3, num(E.axes and E.axes[2], 0.128))
	local xmin, feather = num(E.xmin, 0.24), max(1e-3, num(E.feather, 0.03))
	return function(x, y, z)
		local c = cov(x, y, z)
		if c <= 0 then
			return c
		end
		local qy, qz = (y - cy) / ay, (z - cz) / az
		local k = math.sqrt(qy * qy + qz * qz) + 1e-9
		local k2 = math.sqrt((qy / ay) ^ 2 + (qz / az) ^ 2) + 1e-9
		local d = max((k - 1) * k / k2, xmin - abs(x))
		if d >= feather then
			return c
		elseif d <= 0 then
			return 0
		end
		local t = d / feather
		return c * t * t * (3 - 2 * t)
	end
end
HK.EarLined = earLined

function HK.CapCoverage(look, lod, capSpec, S, capFade, earLine)
	if type(earLine) == "table" then
		local cov, S2, sharp = HK.CapCoverage(look, lod, capSpec, S, capFade)
		return earLined(cov, earLine), S2, sharp
	end
	look = type(look) == "table" and look or {}
	local hair = type(look.hair) == "table" and look.hair or {}
	local density = clamp(num(capSpec and capSpec.density, 1), 0, 1)
	local cut, S2
	if type(capFade) == "string" and Kit.FADES[capFade] then
		S = S or Kit.Scalp(look)
		cut = Kit.Cut(S, { hairline = type(hair.hairline) == "string" and hair.hairline or "Natural",
			growth = clamp(num(hair.growth, 0), 0, 1.5), density = density, fade = capFade })
		return cut.cov, S, (cut.soft or 0.016) < 0.006
	end
	if capSpec and capSpec.cut == "style" then
		cut, S2 = Gen.CapCut(look, lod)
	end
	S = S2 or S or Kit.Scalp(look)
	if not cut then
		cut = Kit.Cut(S, { hairline = type(hair.hairline) == "string" and hair.hairline or "Natural",
			growth = clamp(num(hair.growth, 0), 0, 1.5), density = density })
		return cut.cov, S, (cut.soft or 0.016) < 0.006
	end
	local cov = cut.cov
	if density < 1 then
		return function(x, y, z)
			return cov(x, y, z) * density
		end, S, (cut.soft or 0.016) < 0.006
	end
	return cov, S, (cut.soft or 0.016) < 0.006
end

-- the reference (default male) skull the cap mesh was modelled on, and per grid size its texel points: the
-- cap vertex at UV (theta, az) is that skull's point along the ray (theta, az) from its centre, CAP_OFF out
local CAP_OFF = 0.02
local refScalp
local refGrids = {}
local function refGrid(thetaMax, gw, gh)
	local key = table.concat({ thetaMax, gw, gh }, "|")
	local g = refGrids[key]
	if g then
		return g
	end
	refScalp = refScalp or Kit.Scalp({})
	local n = gw * gh
	local X, Y, Z = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local t0 = 0.5
	for j = 0, gh - 1 do
		local th = (j + 0.5) / gh * thetaMax
		local st, ct = sin(th), cos(th)
		for i = 0, gw - 1 do
			local az = (i + 0.5) / gw * TAU
			local dx, dy, dz = st * sin(az), ct, st * cos(az)
			local x, y, z, t = refScalp.ray(dx, dy, dz, 0, t0)
			t0 = t
			local k = i + j * gw + 1
			X[k], Y[k], Z[k] = x + dx * CAP_OFF, y + dy * CAP_OFF, z + dz * CAP_OFF
			step(30) -- (a skull ray: ~30 field samples)
		end
	end
	g = { x = X, y = Y, z = Z }
	refGrids[key] = g
	return g
end

-- the cap's coverage and colour on a gw x gh grid over its UV (texel centres; u = az / 2pi with az = 0 at the
-- back toward +X, v = theta / thetaMax): flat arrays r, g, b, c (index i + j * gw, 0-based i, j). Each texel
-- is read where the cap mesh shows it on this boxer: the reference skull's cap point, through the skull fit
-- (Place's map for the cap), onto this boxer's scalp. fit = HK.Fit(S) when not given
function HK.CapGrid(S, cov, pal, thetaMax, gw, gh, fit)
	fit = fit or HK.Fit(S)
	local ref = refGrid(thetaMax, gw, gh)
	local ax, ay, az, dz, dy = fit.ax, fit.ay, fit.az, fit.dz, num(fit.dy, 0)
	local n = gw * gh
	local R, G, B, C = table.create(n, 0), table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local RX, RY, RZ = ref.x, ref.y, ref.z
	for k = 1, n do
		local x, y, z = S.onto(RX[k] * ax, RY[k] * ay + dy, RZ[k] * az + dz, 0)
		local c = clamp(cov(x, y, z), 0, 1)
		-- (scalp hair is short: the roots' colour; Split by its side, Ombre by its height)
		local r, g, b = pal.at(0.5, 0, x, false, y)
		R[k], G[k], B[k], C[k] = r, g, b, c
		step(12) -- (onto the scalp: ~2 normal steps of 5 field samples, and the coverage: ~8 us)
	end
	return { r = R, g = G, b = B, c = C, w = gw, h = gh }
end

-- the grid's size for a cut: finer for a sharp edge (a line-up's 3 mm reads only on a finer grid)
function HK.GridSize(sharp)
	if sharp then
		return 192, 96
	end
	return 128, 64
end

-- bilinear sample of a flat grid (wraps in u, clamps in v)
local function gridAt(arr, gw, gh, gu, gv)
	gu = gu % gw
	local i0 = floor(gu)
	local fu = gu - i0
	local i1 = (i0 + 1) % gw
	gv = clamp(gv, 0, gh - 1)
	local j0 = floor(gv)
	local fv = gv - j0
	local j1 = min(j0 + 1, gh - 1)
	local a = arr[i0 + j0 * gw + 1] * (1 - fu) + arr[i1 + j0 * gw + 1] * fu
	local b = arr[i0 + j1 * gw + 1] * (1 - fu) + arr[i1 + j1 * gw + 1] * fu
	return a + (b - a) * fv
end
HK.GridAt = gridAt

-- a tile's texels ranked 0..1 (f32 per texel) by alpha, then grey: the order its strands / coils give way in
-- as the cap's coverage falls (the faint edges and dark crevices first, the opaque bright cores last). Mid-rank
-- of each (alpha, grey) value, so the ranks are spread evenly over the tile. Cached per tile buffer
local rankCache = setmetatable({}, { __mode = "k" })
function HK.TileRank(tile, tw, th)
	local hit = rankCache[tile]
	if hit and hit.w == tw and hit.h == th then
		return hit.rank
	end
	local n = tw * th
	local hist = table.create(65536, 0)
	for k = 0, n - 1 do
		local o = k * 4
		local key = readu8(tile, o + 3) * 256 + readu8(tile, o) + 1
		hist[key] += 1
		if k % 256 == 255 then
			step(8)
		end
	end
	-- each value's mid-rank: (texels below + half its own) / n
	local below = 0
	for key = 1, 65536 do
		local c = hist[key]
		if c > 0 then
			hist[key] = (below + c * 0.5) / n
			below += c
		end
		if key % 1024 == 0 then
			step(8)
		end
	end
	local rank = buffer.create(n * 4)
	for k = 0, n - 1 do
		local o = k * 4
		buffer.writef32(rank, o, hist[readu8(tile, o + 3) * 256 + readu8(tile, o) + 1])
		if k % 256 == 255 then
			step(8)
		end
	end
	rankCache[tile] = { w = tw, h = th, rank = rank }
	return rank
end

-- the cap texture (size x size RGBA8): the tile (tw x th, RGBA8, wraps both ways: short / shortcoil / waves)
-- repeated nu x nv times, its grey times the grid's colour. Alpha: the tile's alpha where the coverage c is 1,
-- none at 0; between, a threshold over the tile's rank (TileRank) that moves with c, so a fade thins out whole
-- strands and coils (each texel is either kept at its own alpha or gone, over a 1 / k wide rank window) instead
-- of turning every hair uniformly translucent: g = smoothstep(clamp((rank - t) * k)), t = (1 - c)(1 + 1/k) - 1/k,
-- alpha = tileA * g (g = 1 at c = 1, 0 at c = 0, rising with c). fadeK (default CAP_FADE_K) <= 0: tileA * c.
-- flipV writes the rows bottom-up. pole (HK.CapPole): round the crown (theta < pole.theta1) the tile is sampled
-- by a planar (azimuthal-equidistant) projection, (X, Z) = theta (sin az, cos az), one tile per (su, sv), and
-- crossfaded (smoothstep, theta0 .. theta1) into the polar sampling: the polar UV squeezes the nu repeats into
-- wedges at the pole (an nu-spoke star from above), the planar one keeps the tile's own size there.
-- (MeshKit's step units are ~1-5 us: a texel here is ~0.6 us, so 22 units every
-- 64 texels)
function HK.PaintCap(grid, tile, tw, th, nu, nv, size, flipV, gain, fadeK, shell, pole)
	gain = gain or 1
	local K = tonumber(fadeK) or HK.CAP_FADE_K
	-- a fur shell's variant (HK.CapShellOf): coverage below shell.cov counts as none (outer shells give way first
	-- down a fade: shorter hair), and only the tile's texels ranked above shell.rank stay (sparser outward: tips)
	local sCov = shell and clamp(tonumber(shell.cov) or 0, 0, 0.95) or 0
	local sRank = shell and clamp(tonumber(shell.rank) or 0, 0, 0.98) or 0
	if sRank > 0 and K <= 0 then
		K = HK.CAP_FADE_K
	end
	local rank = K > 0 and HK.TileRank(tile, tw, th) or nil
	local invK = K > 0 and 1 / K or 0
	local readf32 = buffer.readf32
	local n64 = 0
	stepNow()
	local out = buffer.create(size * size * 4)
	stepNow()
	local gw, gh = grid.w, grid.h
	local R, G, B, C = grid.r, grid.g, grid.b, grid.c
	-- per output column (fixed for every row): the grid's columns and weight (wrapping round the head), the
	-- tile's texel columns (byte offsets) and weight
	local gi0, gi1, gfu = table.create(size), table.create(size), table.create(size)
	local tx0s, tx1s, tfx = table.create(size), table.create(size), table.create(size)
	for i = 0, size - 1 do
		local u = (i + 0.5) / size
		local gu = (u * gw - 0.5) % gw
		local i0 = floor(gu)
		gi0[i + 1], gi1[i + 1], gfu[i + 1] = i0 + 1, (i0 + 1) % gw + 1, gu - i0
		local tu = (u * nu * tw - 0.5) % tw
		local t0 = floor(tu)
		tx0s[i + 1], tx1s[i + 1], tfx[i + 1] = t0 * 4, ((t0 + 1) % tw) * 4, tu - t0
		if i % 64 == 63 then
			step(4)
		end
	end
	-- one grid row interpolated in v (r, g, b, c over the gw columns), per output row
	local rr, rg, rb, rc = table.create(gw, 0), table.create(gw, 0), table.create(gw, 0), table.create(gw, 0)
	for j = 0, size - 1 do
		local v = (j + 0.5) / size
		local row = flipV and (size - 1 - j) or j
		local gv = clamp(v * gh - 0.5, 0, gh - 1)
		local j0 = floor(gv)
		local fv = gv - j0
		local j1 = min(j0 + 1, gh - 1)
		local b0, b1 = j0 * gw, j1 * gw
		for q = 1, gw do
			rr[q] = R[b0 + q] + (R[b1 + q] - R[b0 + q]) * fv
			rg[q] = G[b0 + q] + (G[b1 + q] - G[b0 + q]) * fv
			rb[q] = B[b0 + q] + (B[b1 + q] - B[b0 + q]) * fv
			rc[q] = C[b0 + q] + (C[b1 + q] - C[b0 + q]) * fv
		end
		step(gw // 16)
		local tv = (v * nv * th - 0.5) % th
		local ty0 = floor(tv)
		local fy = tv - ty0
		local ro0, ro1 = ty0 * tw * 4, ((ty0 + 1) % th) * tw * 4
		local o = row * size * 4
		-- the crown's planar sample weight on this row (0: polar only)
		local theta = pole and v * pole.thetaMax or 0
		local wp = 0
		if pole and theta < pole.theta1 then
			local q = clamp((theta - pole.theta0) / (pole.theta1 - pole.theta0), 0, 1)
			wp = 1 - q * q * (3 - 2 * q)
		end
		for i = 1, size do
			local q0, q1, fu = gi0[i], gi1[i], gfu[i]
			local c = rc[q0] + (rc[q1] - rc[q0]) * fu
			if sCov > 0 then
				c = (c - sCov) / (1 - sCov)
			end
			local r = rr[q0] + (rr[q1] - rr[q0]) * fu
			local g = rg[q0] + (rg[q1] - rg[q0]) * fu
			local b = rb[q0] + (rb[q1] - rb[q0]) * fu
			if c <= 0.002 then
				-- (bare scalp: the head shows; the colour kept so filtering never pulls in black. The palette's
				-- colours are 0..1: no clamp below; RGBA packed little-endian)
				writeu32(out, o, floor(r * 255 + 0.5) + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5) * 65536)
			else
				local x0, x1, fx = tx0s[i], tx1s[i], tfx[i]
				local w00, w10, w01, w11 = (1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy
				local a00, a10, a01, a11 = ro0 + x0, ro0 + x1, ro1 + x0, ro1 + x1
				local grey = (readu8(tile, a00) * w00 + readu8(tile, a10) * w10 + readu8(tile, a01) * w01 + readu8(tile, a11) * w11) * gain
				local al = readu8(tile, a00 + 3) * w00 + readu8(tile, a10 + 3) * w10 + readu8(tile, a01 + 3) * w01 + readu8(tile, a11 + 3) * w11
				-- the crown: the planar sample, blended in (its rank too, below)
				local p00, p10, p01, p11, q00, q10, q01, q11
				if wp > 0 then
					local az = (i - 0.5) / size * TAU
					local pu = (theta * sin(az) / pole.su * tw - 0.5) % tw
					local pv = (theta * cos(az) / pole.sv * th - 0.5) % th
					local px0, py0 = floor(pu), floor(pv)
					local pfx, pfy = pu - px0, pv - py0
					local px1, py1 = (px0 + 1) % tw, (py0 + 1) % th
					q00, q10, q01, q11 = (1 - pfx) * (1 - pfy), pfx * (1 - pfy), (1 - pfx) * pfy, pfx * pfy
					p00, p10 = (py0 * tw + px0) * 4, (py0 * tw + px1) * 4
					p01, p11 = (py1 * tw + px0) * 4, (py1 * tw + px1) * 4
					local g2 = (readu8(tile, p00) * q00 + readu8(tile, p10) * q10 + readu8(tile, p01) * q01 + readu8(tile, p11) * q11) * gain
					local a2 = readu8(tile, p00 + 3) * q00 + readu8(tile, p10 + 3) * q10 + readu8(tile, p01 + 3) * q01 + readu8(tile, p11 + 3) * q11
					grey += (g2 - grey) * wp
					al += (a2 - al) * wp
				end
				local keep
				if not rank then
					keep = c
				elseif c >= 1 and sRank <= 0 then
					keep = 1
				else
					local rk = readf32(rank, a00) * w00 + readf32(rank, a10) * w10 + readf32(rank, a01) * w01 + readf32(rank, a11) * w11
					if wp > 0 then
						local r2 = readf32(rank, p00) * q00 + readf32(rank, p10) * q10 + readf32(rank, p01) * q01 + readf32(rank, p11) * q11
						rk += (r2 - rk) * wp
					end
					-- (the shell's floor: the higher of the fade's threshold and its own rank)
					local t = c >= 1 and -invK or ((1 - c) * (1 + invK) - invK)
					if sRank > 0 and sRank > t then
						t = sRank
					end
					local q = (rk - t) * K
					if q <= 0 then
						keep = 0
					elseif q >= 1 then
						keep = 1
					else
						keep = q * q * (3 - 2 * q)
					end
				end
				writeu32(out, o, min(255, floor(r * grey + 0.5)) + min(255, floor(g * grey + 0.5)) * 256 + min(255, floor(b * grey + 0.5)) * 65536
					+ min(255, floor(al * keep + 0.5)) * 16777216)
			end
			o += 4
			n64 += 1
			if n64 == 64 then
				n64 = 0
				step(22)
			end
		end
	end
	return out
end

------------------------------------------------------------------------
-- Tinting the card textures
------------------------------------------------------------------------
-- a band's random value (0..1, stable): which bands carry a streak / highlight, the lock-to-lock variation
local function bandRnd(b)
	local x = sin(b * 12.9898 + 4.1414) * 43758.5453
	return x - floor(x)
end
HK.BandRnd = bandRnd

-- the colour table a texture is tinted with: flat -> one colour { flat, r, g, b } (tileable strips: a mid tone,
-- no root or tip); else { rows, bands, cols[band] = { r, g, b per row } }: root (v = 0) to tip (v = 1) along the rows, a band's own rnd across u. Kit.Palette's
-- pal.at does every rule (darker roots, lighter tips, Tips / Ombre by v, Streaks / highlights on bands, greying);
-- Split cannot follow the head's side on a card: its base colour
function HK.Colors(pal, rows, flat, bands)
	bands = bands or HK.BANDS
	if flat then
		local r, g, b = pal.at(0.5, 0.5, -1)
		return { flat = true, r = r, g = g, b = b }
	end
	local t = { rows = rows, bands = bands, cols = {} }
	for bi = 0, bands - 1 do
		local rnd = bandRnd(bi)
		local col = table.create(rows * 3)
		for j = 0, rows - 1 do
			local r, g, b = pal.at(rnd, (j + 0.5) / rows, -1)
			col[j * 3 + 1], col[j * 3 + 2], col[j * 3 + 3] = r, g, b
		end
		t.cols[bi + 1] = col
		step(rows // 8)
	end
	return t
end

-- src (sw x sh RGBA8) box-filtered down by the integer factor f (1 = as is), times the colours, alpha kept:
-- a new (sw / f) x (sh / f) buffer. The colours' rows run along the texture's own v (its rows as uploaded),
-- flipV writes them bottom-up. (Step units of ~2.5 us: an output texel is ~0.12 us plus ~0.24 us per source
-- texel read: 4 + 9 f^2 units every 64 texels, measured under ~1 ms between ticks)
function HK.Tint(src, sw, sh, f, colors, flipV, gain)
	f = max(1, floor(f or 1))
	gain = gain or 1
	local unit64 = 6 + 12 * f * f -- (the dark-colour lift costs a little per texel)
	local n64 = 0
	local w, h = sw // f, sh // f
	stepNow()
	local out = buffer.create(w * h * 4)
	stepNow()
	local inv = gain / (f * f)
	local flat = colors.flat
	local rows, bands, cols = colors.rows, colors.bands, colors.cols
	-- per column: its band; per row: each band's colour (x gain / box area)
	local bandOf = table.create(w, 1)
	if not flat then
		for i = 0, w - 1 do
			bandOf[i + 1] = min(bands - 1, floor((i + 0.5) / w * bands)) + 1
		end
	end
	local nb = flat and 1 or bands
	local mr, mg, mb = table.create(nb, 0), table.create(nb, 0), table.create(nb, 0)
	if flat then
		mr[1], mg[1], mb[1] = colors.r * inv, colors.g * inv, colors.b * inv
	end
	local ainv = 1 / (f * f)
	-- dark colours keep their strand detail: a plain multiply flattens black hair to a 4/255 ripple, so
	-- each band adds back a little of the texture's own contrast, more the darker the colour (lift)
	local lift = table.create(nb, 0)
	local function setLift(bi)
		local lum = (0.3 * mr[bi] + 0.59 * mg[bi] + 0.11 * mb[bi]) / inv
		lift[bi] = 0.16 * (1 - min(1, lum)) ^ 2 * ainv
	end
	if flat then
		setLift(1)
	end
	for j = 0, h - 1 do
		local orow = flipV and (h - 1 - j) or j
		if not flat then
			local crow = min(rows - 1, floor((j + 0.5) / h * rows)) * 3
			for bi = 1, bands do
				local col = cols[bi]
				mr[bi], mg[bi], mb[bi] = col[crow + 1] * inv, col[crow + 2] * inv, col[crow + 3] * inv
				setLift(bi)
			end
		end
		local o = orow * w * 4
		for i = 1, w do
			local r, g, b, a
			if f == 1 then
				local s0 = (j * sw + i - 1) * 4
				r, g, b, a = readu8(src, s0), readu8(src, s0 + 1), readu8(src, s0 + 2), readu8(src, s0 + 3)
			else
				r, g, b, a = 0, 0, 0, 0
				for dy = 0, f - 1 do
					local s0 = ((j * f + dy) * sw + (i - 1) * f) * 4
					for _ = 1, f do
						r += readu8(src, s0)
						g += readu8(src, s0 + 1)
						b += readu8(src, s0 + 2)
						a += readu8(src, s0 + 3)
						s0 += 4
					end
				end
				a *= ainv
			end
			local bi = bandOf[i]
			local d = lift[bi] * (r - 140 / ainv)
			writeu32(out, o, max(0, min(255, floor(r * mr[bi] + d + 0.5)))
				+ max(0, min(255, floor(g * mg[bi] + d + 0.5))) * 256
				+ max(0, min(255, floor(b * mb[bi] + d + 0.5))) * 65536
				+ min(255, floor(a + 0.5)) * 16777216)
			o += 4
			n64 += 1
			if n64 == 64 then
				n64 = 0
				step(unit64)
			end
		end
	end
	return out, w, h
end

function HK.IsFlat(key, tex)
	return (type(tex) == "table" and tex.tile == true) or FLAT[key] == true
end

-- what a tinted texture depends on (two looks with the same key share one image): the palette's inputs
function HK.ColorKey(look, htype)
	local hair = type(look) == "table" and type(look.hair) == "table" and look.hair or {}
	local function c3(c, d)
		if type(c) ~= "table" then
			return d
		end
		return string.format("%d.%d.%d", floor(num(c[1], 0) + 0.5), floor(num(c[2], 0) + 0.5), floor(num(c[3], 0) + 0.5))
	end
	local age = num(look.age, 26)
	local grey = floor(clamp((age - 38) / 40, 0, 0.55) * 40 + 0.5)
	local kind = (htype == "Coiled" or htype == "Kinky") and "c" or (htype == "Curly" and "u" or "s")
	return table.concat({ c3(hair.color, "-"), c3(hair.hcolor, "-"), type(hair.dye) == "string" and hair.dye or "None",
		hair.hl == true and "h" or "", tostring(grey), kind }, "|")
end

-- the palette the tint uses (Kit.Palette, the generated hair's own colours)
function HK.Palette(look, htype)
	return Kit.Palette(type(look) == "table" and look or {}, htype)
end

-- the colour a piece's part shows where its texture does not cover (a mid hair tone)
function HK.MidColor(pal)
	return pal.at(0.5, 0.5, -1)
end

return HK
