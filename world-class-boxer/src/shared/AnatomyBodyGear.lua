-- AnatomyBodyGear: what a boxer wears on the Body meshes (AnatomyBody), and the hands and feet.
-- * Read(look): gloves / wraps / bare hands (look.attire.hands) and the gear's colours and styles
--   (look.attire.gear, published by the Builder from the round-1 gear: glove colour, trim, palm, piping,
--   stitching, finish, size and shape, closure, fight-night tape; wrap colours; shoe colour, style, height,
--   sole, laces, socks), with defaults for old looks
-- * LimbPainter(...): the colour of a limb piece at (bone parameter, angle) per vertex or per texel: skin
--   (joints, separations, veins, grain) and the garment zones AnatomyBodyLimbs builds (satin trunk legs with
--   the style's trim, the long trunks' cuff, socks, the boot shaft with laces / eyelets / collar, the glove's
--   cuff with its strap or laces, the hand wrap's layers)
-- * Build(...): the Hand piece (a relaxed bare hand with fingers and thumb, a wrapped fist, or a padded
--   boxing glove with its thumb) and the Foot piece (boxing boot or trainer: sole, toe box, heel, laces),
--   built as grid lofts like every body piece (textures from the same lattice)
local MeshKit = require(script.Parent:WaitForChild("MeshKit"))
local Kit = require(script.Parent:WaitForChild("AnatomyBodyKit"))

local Gear = {}

local abs, min, max, sqrt, cos, sin, pi, floor = math.abs, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi, math.floor
local clamp, smooth, lerp, bell = Kit.clamp, Kit.smooth, Kit.lerp, Kit.bell
local mix, sepShade = Kit.Mix, Kit.SepShade
local TAU = pi * 2
local LAT, FRONT, MED, BACK = 0, pi / 2, pi, 3 * pi / 2

-- resolution per level: palm / finger / thumb / glove / glove thumb / shoe { rings, sides, dome start, dome end }
Gear.RES = {
	full = { palm = { 6, 10, 1, 2 }, finger = { 5, 5, 0, 1 }, thumb = { 4, 5, 0, 1 }, glove = { 10, 12, 0, 3 }, gthumb = { 5, 6, 0, 2 }, shoe = { 9, 12, 1, 2 } },
	medium = { palm = { 5, 8, 1, 2 }, finger = nil, thumb = nil, glove = { 7, 8, 0, 1 }, gthumb = { 3, 5, 0, 1 }, shoe = { 5, 8, 1, 1 } },
	low = { palm = { 3, 6, 0, 0 }, finger = nil, thumb = nil, glove = { 4, 6, 0, 1 }, gthumb = nil, shoe = { 4, 6, 0, 1 } },
}

------------------------------------------------------------------------
-- Gear data
------------------------------------------------------------------------
local function rgbOr(t, d)
	local r, g, b = Kit.Rgb(t)
	if r then
		return { r, g, b }
	end
	return d
end

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

local function darker(c, k)
	return { c[1] * k, c[2] * k, c[3] * k }
end

function Gear.Read(look)
	local a = type(look.attire) == "table" and look.attire or {}
	local g = type(a.gear) == "table" and a.gear or {}
	local hands = (a.hands == "wraps" or a.hands == "bare") and a.hands or "gloves"
	local gl = type(g.glove) == "table" and g.glove or {}
	local main = rgbOr(gl.c, { 0.78, 0.1, 0.12 })
	local glove = {
		c = main, trim = rgbOr(gl.trim, { 0.93, 0.92, 0.89 }), palm = rgbOr(gl.palm, darker(main, 0.88)),
		stitch = rgbOr(gl.stitch, darker(main, 0.55)), stitchKind = type(gl.stitchKind) == "string" and gl.stitchKind or "Single",
		piping = rgbOr(gl.piping, nil), strap = rgbOr(gl.strap, nil), finish = type(gl.finish) == "string" and gl.finish or "Leather",
		oz = clamp(num(gl.oz, 16), 6, 20), w = clamp(num(gl.w, 1), 0.85, 1.15), l = clamp(num(gl.l, 1), 0.85, 1.15),
		k = clamp(num(gl.k, 1), 0.85, 1.2), cuff = clamp(num(gl.cuff, 1), 0.8, 1.3), closure = gl.closure == "lace" and "lace" or "velcro",
		tape = gl.tape == true, target = gl.target == true, cond = clamp(num(gl.cond, 100), 0, 100), plate = gl.plate,
	}
	-- where the cuff starts on the forearm (bone parameter from the elbow): long laced cuffs reach higher
	glove.cuffTop = clamp(0.68 - 0.28 * (glove.cuff - 1), 0.54, 0.78)
	local wr = type(g.wrap) == "table" and g.wrap or {}
	local wc = rgbOr(wr.c, { 0.94, 0.94, 0.93 })
	local wrap = { c = wc, c2 = rgbOr(wr.c2, wc), c3 = rgbOr(wr.c3, wc), gel = wr.gel == true, cond = clamp(num(wr.cond, 100), 0, 100), top = 0.82 }
	local sh = type(g.shoe) == "table" and g.shoe or {}
	local style = type(sh.style) == "string" and sh.style or "boot"
	local tall = sh.tall ~= false
	local shoe = {
		c = rgbOr(sh.c, { 0.1, 0.1, 0.1 }), accent = rgbOr(sh.accent, { 0.94, 0.94, 0.94 }), sole = rgbOr(sh.sole, { 0.12, 0.12, 0.13 }),
		lace = rgbOr(sh.lace, { 0.94, 0.94, 0.94 }), sockC = rgbOr(sh.sock, { 0.95, 0.95, 0.94 }), style = style, tall = tall,
		soleKind = type(sh.soleKind) == "string" and sh.soleKind or "Rubber", cond = clamp(num(sh.cond, 100), 0, 100),
	}
	shoe.trainer = style == "trainer"
	-- the shaft's top on the shin (bone parameter from the knee) and the sock band above it
	if shoe.trainer then
		shoe.shaft = tall and 0.84 or 1.2
		shoe.sock = tall and 0.76 or 0.8
	else
		shoe.shaft = tall and 0.52 or 0.84
		shoe.sock = shoe.shaft - 0.06
	end
	return { hands = hands, glove = glove, wrap = wrap, shoe = shoe }
end

------------------------------------------------------------------------
-- Limb painter (skin + garment zones)
------------------------------------------------------------------------
local function zoneAt(zones, bb)
	for _, z in ipairs(zones) do
		if bb <= z[2] + 1e-6 then
			return z
		end
	end
	return zones[#zones]
end

-- angular distance (radians, 0..pi)
local function adist(a, b)
	local d = (a - b) % TAU
	if d > pi then
		d = TAU - d
	end
	return d
end

-- a sharp-or-soft step: crisp in texels, a vertex-wide ramp in vertex colours
local function edge(x, w, crisp)
	local hw = crisp and w * 0.18 or w
	return smooth(-hw, hw, x)
end

-- laces criss-crossing up the front of a boot / glove cuff: (b, angle) -> 0..1 cover (texels only)
local function laceCover(bb, ang, b0, b1, center, halfW, pitch)
	if bb < b0 or bb > b1 then
		return 0
	end
	local da = MeshKit.WrapAngle(ang - center)
	if abs(da) > halfW then
		return 0
	end
	-- two diagonals per pitch: |da| / halfW against the phase of b
	local ph = ((bb - b0) / pitch) % 1
	local x = abs(da) / halfW
	local d1 = abs(x - ph * 2 % 2)
	local d2 = abs(x - (1 - ph) * 2 % 2)
	local d = min(d1, d2)
	return 1 - smooth(0.12, 0.22, d)
end

-- the shoe's length from the standing height (sole to the top of the head): a foot is ~15 % of it, a boxing
-- boot a little more; never from the shin (athletic rigs have long shins)
function Gear.FootLength(sk, P)
	local hd = sk.size.Head
	local top = sk.center.Head[2] + hd[2] / 2
	local fc, fs = sk.center.RightFoot, sk.size.RightFoot
	local H = top - (fc[2] - fs[2] / 2)
	return clamp(0.155 * H, 0.55, 1.4) * (P.female and 0.96 or 1)
end

-- criss-cross lacing in studs: Y along the lacing (Y0 = the first eyelet row, Y1 = the last), X across from
-- its centre line; eyelets in two rows at +-eyeX, every 'pitch'; laces lw wide run eyelet to eyelet across.
-- Returns lace cover, the lace's rounded shade (0..1), the eyelet ring, the eyelet hole, and the shadow the
-- laces cast on the tongue
local function lacing(Y, X, Y0, Y1, eyeX, pitch, lw)
	if Y < Y0 - pitch * 0.6 or Y > Y1 + pitch * 0.6 or abs(X) > eyeX * 1.5 then
		return 0, 0, 0, 0, 0
	end
	local n = max(2, floor((Y1 - Y0) / pitch + 0.5) + 1)
	local p = (Y1 - Y0) / (n - 1)
	local k0 = clamp(floor((Y - Y0) / p), 0, n - 2)
	local bestD = math.huge
	local eye, hole = 0, 0
	for k = max(0, k0 - 1), min(n - 2, k0 + 1) do
		local ya, yb = Y0 + k * p, Y0 + (k + 1) * p
		for q = -1, 1, 2 do
			-- segment (ya, q*eyeX) -> (yb, -q*eyeX)
			local ax, ay = q * eyeX, ya
			local bx, by = -q * eyeX - ax, yb - ay
			local l2 = bx * bx + by * by
			local tt = clamp(((X - ax) * bx + (Y - ay) * by) / l2, 0, 1)
			local dx, dy = X - ax - bx * tt, Y - ay - by * tt
			local d = sqrt(dx * dx + dy * dy)
			-- the lace on top alternates per crossing: a touch closer wins ties
			if (k + (q > 0 and 1 or 0)) % 2 == 0 then
				d *= 0.97
			end
			bestD = min(bestD, d)
		end
	end
	for k = max(0, k0 - 1), min(n - 1, k0 + 2) do
		local ey = Y0 + k * p
		for q = -1, 1, 2 do
			local de = sqrt((X - q * eyeX) ^ 2 + (Y - ey) ^ 2)
			eye = max(eye, 1 - smooth(lw * 0.75, lw * 1.0, de))
			hole = max(hole, 1 - smooth(lw * 0.35, lw * 0.5, de))
		end
	end
	local lace = 1 - smooth(lw * 0.42, lw * 0.55, bestD)
	local shade = 1 - (clamp(bestD / (lw * 0.55), 0, 1)) ^ 2
	local shadow = (1 - lace) * (1 - smooth(lw * 0.55, lw * 1.3, bestD))
	return lace, shade, eye, hole, shadow
end
Gear.Lacing = lacing

-- the lacing's measurements for a foot length (shared by the shoe and the boot shaft so they line up)
local function laceDims(FL)
	return 0.06 * FL, 0.075 * FL, 0.022 * FL -- eyelet half span, pitch, lace width
end

-- the lacing panel of a boot / shoe over colour (r, g, b): the tongue between the quarters (a shade darker, a
-- seam either side), eyelets in two rows, criss-cross laces with a rounded shade and a contact shadow.
-- tongueTo: the tongue runs from the lacing up to Y = tongueTo (nil = past the last eyelet only)
local function paintLacing(r, g, b, sh, Y, X, Y0, Y1, FL, crisp, tongueFrom, tongueTo)
	local eyeX, pitch, lw = laceDims(FL)
	if crisp then
		local tw = eyeX * 0.74
		local inY = Y > (tongueFrom or (Y0 - pitch * 0.7)) and Y < (tongueTo or (Y1 + pitch * 0.6))
		if inY then
			local inT = 1 - smooth(tw - 0.002, tw + 0.002, abs(X))
			r, g, b = mix(r, g, b, r * 0.78, g * 0.78, b * 0.78, inT)
			local seam = 1 - smooth(0.0025, 0.005, abs(abs(X) - tw))
			r, g, b = mix(r, g, b, r * 0.5, g * 0.5, b * 0.5, seam)
		end
		local lace, shade, eye, hole, shadow = lacing(Y, X, Y0, Y1, eyeX, pitch, lw)
		local k = 1 - 0.4 * shadow
		r, g, b = r * k, g * k, b * k
		r, g, b = mix(r, g, b, 0.72, 0.72, 0.74, eye)
		r, g, b = mix(r, g, b, 0.08, 0.08, 0.08, hole)
		local lk = 0.72 + 0.28 * shade
		r, g, b = mix(r, g, b, sh.lace[1] * lk, sh.lace[2] * lk, sh.lace[3] * lk, lace)
	else
		local l = (1 - smooth(eyeX * 0.5, eyeX * 1.25, abs(X))) * smooth(Y0 - pitch, Y0, Y) * (1 - smooth(Y1, Y1 + pitch, Y))
		r, g, b = mix(r, g, b, sh.lace[1], sh.lace[2], sh.lace[3], 0.45 * l)
	end
	return r, g, b
end
Gear.PaintLacing = paintLacing

function Gear.LimbPainter(pc, sk, P, look, wear, side, kind, info, trunk, Limbs)
	local spec, zones, L, S = info.spec, info.zones, info.L, info.S
	local sr, sg, sb = pc.sr, pc.sg, pc.sb
	local isArm = kind == "UpperArm" or kind == "LowerArm"
	local g = wear.gear
	local veins = info.veins
	local seed = pc.seed + #kind * 13 + (side == "Right" and 5 or 0)
	local function channels(bb, ang)
		local z = zoneAt(zones, bb)
		if z[3] ~= "skin" then
			return 0, 0
		end
		return Limbs.Channels(spec, clamp(bb, spec.b0, spec.b1), ang)
	end
	-- skin ---------------------------------------------------------------
	local function veinW(bb, ang)
		if not veins then
			return 0
		end
		local best = 0
		local rr = spec.rx(clamp(bb, 0, 1)) * S
		for _, path in ipairs(veins) do
			local pts = path.pts
			local w = path.r * 2.4
			for k = 1, #pts - 1 do
				local p, q = pts[k], pts[k + 1]
				local ax, ay = (bb - p[1]) * L, MeshKit.WrapAngle(ang - p[2]) * rr
				local bx, by = (q[1] - p[1]) * L, MeshKit.WrapAngle(q[2] - p[2]) * rr
				local l2 = bx * bx + by * by
				local t = l2 > 1e-9 and clamp((ax * bx + ay * by) / l2, 0, 1) or 0
				local dx, dy = ax - bx * t, ay - by * t
				local d = sqrt(dx * dx + dy * dy) / w
				if d < 1 then
					best = max(best, (1 - d * d) * (1 - d * d))
				end
			end
		end
		return best
	end
	local function skin(bb, ang, groove, crown, vw)
		local r, gg, b = sr, sg, sb
		-- elbows / knees: rougher, darker, redder skin
		local joint = 0
		if kind == "UpperArm" then
			joint = bell((bb - 1.0) / 0.14) * (0.5 + 0.5 * Limbs.win(ang, BACK, 1.6))
		elseif kind == "LowerArm" then
			joint = bell((bb - 0.0) / 0.14) * (0.5 + 0.5 * Limbs.win(ang, BACK, 1.6))
		elseif kind == "UpperLeg" then
			joint = bell((bb - 1.0) / 0.12) * (0.4 + 0.6 * Limbs.win(ang, FRONT, 1.4))
		else
			joint = bell((bb - 0.0) / 0.12) * (0.4 + 0.6 * Limbs.win(ang, FRONT, 1.4))
		end
		r, gg, b = mix(r, gg, b, sr * 0.9, sg * 0.76, sb * 0.72, 0.4 * joint)
		-- where the parent piece's end tucks over this one: a soft skin fold (a residual seam reads as a crease)
		if kind == "LowerArm" or kind == "LowerLeg" then
			local fold = bell((bb - 0.03) / 0.05) * (0.5 + 0.5 * Limbs.win(ang, kind == "LowerArm" and FRONT or BACK, 1.8))
			r, gg, b = mix(r, gg, b, sr * 0.8, sg * 0.7, sb * 0.66, 0.35 * fold)
		end
		-- outer arms / shins a touch darker than the inner sides (sun, hair)
		local outer = 0.5 + 0.5 * cos(ang)
		r, gg, b = mix(r, gg, b, sr * 0.94, sg * 0.9, sb * 0.88, (isArm and 0.18 or 0.12) * outer)
		r, gg, b = sepShade(pc, r, gg, b, groove, crown, isArm and 0.7 or 0.6, 0.22)
		-- veins: the skin's colour, a touch cooler and darker (blue-green under fair skin)
		if vw > 0 then
			r, gg, b = mix(r, gg, b, sr * 0.92, sg * 0.93, sb * 0.99, 0.55 * vw)
		end
		return r, gg, b
	end
	-- garments ---------------------------------------------------------------
	local function trunkLeg(bb, ang, crisp, z)
		local r, gg, b = trunk.r, trunk.g, trunk.b
		local lat = adist(ang, LAT)
		local st = trunk.style
		local hemB = z[2]
		if st == "Striped" then
			if edge(0.2 - lat, 0.05, crisp) > 0.5 then
				r, gg, b = trunk.tr, trunk.tg, trunk.tb
			end
		elseif st == "Pro" then
			-- trim hem band at the opening, a trim side panel with one broad white stripe
			local hem = hemB < 0.97 and edge(bb - (hemB - 0.07), 0.015, crisp) or 0
			local panel = edge(0.48 - lat, 0.05, crisp)
			local w = max(hem, panel)
			r, gg, b = mix(r, gg, b, trunk.tr, trunk.tg, trunk.tb, w)
			local stripe = edge(0.13 - lat, 0.03, crisp) * (1 - hem)
			r, gg, b = mix(r, gg, b, 0.95, 0.95, 0.95, stripe)
		elseif st == "Classic" and hemB < 0.97 then
			-- a narrow trim piping at the opening
			local hem = edge(bb - (hemB - 0.025), 0.008, crisp)
			r, gg, b = mix(r, gg, b, trunk.tr, trunk.tg, trunk.tb, hem)
		end
		-- the hem's folded edge is a shade darker
		if hemB < 0.97 then
			local fold = bell((bb - hemB) / 0.02) * 0.12
			r, gg, b = r * (1 - fold), gg * (1 - fold), b * (1 - fold)
		end
		return r, gg, b
	end
	local sh = g.shoe
	local footL = Gear.FootLength(sk, P)
	local function boot(bb, ang, crisp, z)
		local c = sh.c
		local r, gg, b = c[1], c[2], c[3]
		local top = z[1]
		local fr = adist(ang, FRONT)
		-- the padded collar round the top, a shade lighter; the tongue's top at the front
		local collar = 1 - edge(bb - (top + 0.05), 0.012, crisp)
		r, gg, b = mix(r, gg, b, min(1, r * 1.15 + 0.03), min(1, gg * 1.15 + 0.03), min(1, b * 1.15 + 0.03), 0.6 * collar)
		if not sh.trainer then
			-- the lacing down the front of the shaft (eyelets, criss-cross laces over the tongue), continuing onto
			-- the shoe's instep with the same spacing (Gear.PaintLacing: one lacing across the two pieces)
			local da = MeshKit.WrapAngle(ang - FRONT)
			local bc = clamp(bb, 0, 1.1)
			local rr = sqrt(spec.rx(clamp(bb, 0, 1)) * spec.rz(clamp(bb, 0, 1))) * S + 0.03 * S
			r, gg, b = paintLacing(r, gg, b, sh, bc * L, da * rr, (top + 0.08) * L, 1.12 * L, footL, crisp, (top + 0.055) * L, 2 * L)
			if sh.style == "proBoot" then
				-- the breathable mesh panel on the outside
				local panel = edge(0.7 - adist(ang, LAT), 0.08, crisp) * edge(bb - (top + 0.1), 0.02, crisp)
				r, gg, b = mix(r, gg, b, r * 0.72, gg * 0.72, b * 0.72, panel)
			elseif sh.style == "eliteBoot" then
				-- a gold accent stripe slanting down the outside
				local d = adist(ang, LAT + 0.3 * (bb - top - 0.2))
				local stripe = edge(0.12 - d, 0.03, crisp) * edge(bb - (top + 0.08), 0.02, crisp)
				r, gg, b = mix(r, gg, b, 0.86, 0.68, 0.26, stripe)
			end
		else
			-- hi-top trainer: the collar is the shoe's; a lighter band
			r, gg, b = mix(r, gg, b, sh.accent[1], sh.accent[2], sh.accent[3], 0.25 * collar)
		end
		if sh.cond < 50 then
			-- scuffed, faded leather
			local k = (50 - sh.cond) / 50 * 0.3
			r, gg, b = mix(r, gg, b, 0.45, 0.42, 0.38, k * (0.5 + 0.5 * cos(ang * 3 + bb * 9)))
		end
		return r, gg, b
	end
	local function sock(bb, ang, crisp, z)
		local c = sh.sockC
		local rib = crisp and (0.5 + 0.5 * cos(ang * 24)) * 0.06 or 0
		return c[1] * (1 - rib), c[2] * (1 - rib), c[3] * (1 - rib)
	end
	local gl = g.glove
	local function gloveCuff(bb, ang, crisp, z)
		local c = gl.c
		local r, gg, b = c[1], c[2], c[3]
		local top = z[1]
		local len = z[2] - top
		-- the rolled top edge in the trim colour
		local band = 1 - edge(bb - (top + 0.07), 0.012, crisp)
		r, gg, b = mix(r, gg, b, gl.trim[1], gl.trim[2], gl.trim[3], band)
		if gl.tape then
			-- fight night: tape over the strap / laces, signed by the inspector (the plate)
			local tape = edge(bb - (top + 0.12), 0.012, crisp) * (1 - edge(bb - (top + 0.12 + len * 0.45), 0.012, crisp))
			local tk = crisp and (0.96 + 0.04 * cos(ang * 7 + bb * 40)) or 0.97
			r, gg, b = mix(r, gg, b, 0.95 * tk, 0.95 * tk, 0.93 * tk, tape)
		elseif gl.closure == "lace" then
			-- lace-up: the laces down the palm side
			if crisp then
				local lace = laceCover(bb, ang, top + 0.1, z[2] - 0.04, MED, 0.42, 0.13)
				r, gg, b = mix(r, gg, b, 0.95, 0.95, 0.93, lace)
				local gap = edge(0.08 - adist(ang, MED), 0.02, true)
				r, gg, b = mix(r, gg, b, r * 0.7, gg * 0.7, b * 0.7, gap * (1 - band))
			else
				local lace = (1 - smooth(0.2, 0.42, adist(ang, MED))) * smooth(top + 0.08, top + 0.14, bb)
				r, gg, b = mix(r, gg, b, 0.95, 0.95, 0.93, 0.5 * lace)
			end
		else
			-- velcro strap round the middle of the cuff
			local s0, s1 = top + 0.13, top + 0.13 + len * 0.42
			local strap = edge(bb - s0, 0.012, crisp) * (1 - edge(bb - s1, 0.012, crisp))
			local sc = gl.strap or gl.trim
			r, gg, b = mix(r, gg, b, sc[1], sc[2], sc[3], strap)
			if crisp then
				-- stitched border on the strap
				local st = (1 - smooth(0.004, 0.009, min(abs(bb - s0 - 0.015), abs(bb - s1 + 0.015)))) * strap
				r, gg, b = mix(r, gg, b, r * 0.7, gg * 0.7, b * 0.7, st * (((ang * 9) % 1) < 0.6 and 1 or 0))
			end
		end
		return r, gg, b
	end
	local wr = g.wrap
	local function wrapZone(bb, ang, crisp, z)
		local c = wr.c
		local r, gg, b = c[1], c[2], c[3]
		if crisp then
			-- the layers: overlapping diagonal turns, a soft shadow along each edge
			local ph = (bb * 9 + ang / TAU * 1.0) % 1
			local layer = smooth(0.0, 0.12, ph) * 0.06
			r, gg, b = r * (0.96 + layer), gg * (0.96 + layer), b * (0.96 + layer)
		end
		-- two-tone / flag patterns: bands of the second / third colour
		local t = (bb - z[1]) / max(0.05, z[2] - z[1])
		if wr.c2 ~= wr.c and t > 0.35 and t < 0.6 then
			r, gg, b = wr.c2[1], wr.c2[2], wr.c2[3]
		elseif wr.c3 ~= wr.c and t > 0.6 and t < 0.75 then
			r, gg, b = wr.c3[1], wr.c3[2], wr.c3[3]
		end
		if wr.cond < 40 then
			r, gg, b = mix(r, gg, b, 0.59, 0.51, 0.39, 0.3)
		end
		return r, gg, b
	end
	local cloth = { trunk = true, trunkcuff = true, boot = true, sock = true, glove = true, wrap = true }
	local function garment(k2, bb, ang, crisp, z)
		if k2 == "trunk" then
			return trunkLeg(bb, ang, crisp, z)
		elseif k2 == "trunkcuff" then
			return trunk.r, trunk.g, trunk.b
		elseif k2 == "boot" then
			return boot(bb, ang, crisp, z)
		elseif k2 == "sock" then
			return sock(bb, ang, crisp, z)
		elseif k2 == "glove" then
			return gloveCuff(bb, ang, crisp, z)
		elseif k2 == "wrap" then
			return wrapZone(bb, ang, crisp, z)
		end
		return sr, sg, sb
	end
	-- vertex colours
	local function color(bb, ang, x, y, zz, nx, ny, nz, groove, crown, crisp, i)
		local z = zoneAt(zones, bb)
		local k2 = z[3]
		local r, gg, b
		if cloth[k2] then
			r, gg, b = garment(k2, bb, ang, false, z)
		else
			r, gg, b = skin(bb, ang, groove, crown, (i and info.Z[i] == "vein") and 1 or 0)
		end
		local k = 1 + (cloth[k2] and 0.012 or 0.028) * MeshKit.Noise(x * 2.6, y * 2.6, zz * 2.6, seed) + (cloth[k2] and 0 or 0.012 * MeshKit.Noise(x * 9, y * 9, zz * 9, seed + 7))
		return r * k, gg * k, b * k
	end
	local function aoK(bb)
		local z = zoneAt(zones, bb)
		return cloth[z[3]] and 0.7 or 1
	end
	local function tint(bb)
		local z = zoneAt(zones, bb)
		return cloth[z[3]] and pc.clothTint or pc.aoTint
	end
	-- the colour texture: the same painters per texel; the muscle channels are separable (every belly is an
	-- along-the-bone curve times an angular window: rows and columns are precomputed), veins culled per row
	local along, win = Limbs.along, Limbs.win
	local function texture(m, grid, w, h, dark, light)
		local tiles = pc.tiles
		local grain = Kit.GrainTable(pc, w, h)
		local list = {}
		for _, mm in ipairs(spec.mus) do
			if mm.id ~= "fat" and mm.id ~= "bone" and mm.id ~= "tendon" then
				list[#list + 1] = { m = mm, c = true, wgt = 0.6 * mm.h / max(0.02, mm.h) }
			end
		end
		for _, gg in ipairs(spec.grooves) do
			list[#list + 1] = { m = gg, c = false, wgt = gg.h / max(0.004, gg.h) * min(1, gg.h / 0.012) }
		end
		local nL = #list
		local uA, uB = grid.uA or 0, grid.uB or 1
		local colW, colA = {}, {}
		for px = 0, w - 1 do
			local u = (px + 0.5) / w
			local a = TAU * clamp((u - uA) / (uB - uA), 0, 1)
			local row = table.create(nL, 0)
			for k, e in ipairs(list) do
				row[k] = win(a, e.m.a, e.m.w)
			end
			colW[px], colA[px] = row, a
		end
		local rowA = table.create(nL, 0)
		local rowZ, rowB, rowSkin, rowCloth, rowAO, rowTint = zones[1], 0, true, false, 1, pc.aoTint
		local rowVeins = {}
		local rr = 0
		local o = { noP = true, noN = true, dark = dark, light = light }
		o.onRow = function(sm)
			local bb = sm.b
			rowB = bb
			rowZ = zoneAt(zones, bb)
			rowSkin = rowZ[3] == "skin"
			rowCloth = cloth[rowZ[3]] == true
			rowAO = rowCloth and 0.7 or 1
			rowTint = rowCloth and pc.clothTint or pc.aoTint
			local bev = clamp(bb, spec.b0, spec.b1)
			for k, e in ipairs(list) do
				local mm = e.m
				rowA[k] = mm.vee and -1 or along(bev, mm.b0, mm.bp, max(mm.b1, mm.bp + 0.02))
			end
			table.clear(rowVeins)
			rr = spec.rx(clamp(bb, 0, 1)) * S
			if veins and rowSkin then
				for _, path in ipairs(veins) do
					local reach = path.r * 2.4 / L
					local pts = path.pts
					for k = 1, #pts - 1 do
						local p, q = pts[k], pts[k + 1]
						if bb >= min(p[1], q[1]) - reach and bb <= max(p[1], q[1]) + reach then
							rowVeins[#rowVeins + 1] = { p, q, path.r * 2.4 }
						end
					end
				end
			end
		end
		return Kit.GridTexture(MeshKit, m, grid, w, h, function(sm)
			local bb, a = rowB, colA[sm.px]
			local r, gg, b, k
			if rowSkin then
				local cw = colW[sm.px]
				local cr, gr = 0, 0
				local bev = clamp(bb, spec.b0, spec.b1)
				for q = 1, nL do
					local wv = cw[q]
					if wv > 0 then
						local e = list[q]
						local mm = e.m
						local al = rowA[q]
						if al < 0 then
							al = along(bev, mm.b0, mm.bp, max(mm.b1 - mm.vee * (1 - wv), mm.bp + 0.02))
						end
						if al > 0 then
							local kk = al * wv
							if mm.sharp then
								kk = kk ^ mm.sharp
							end
							if e.c then
								cr += kk * e.wgt
							else
								gr += kk * e.wgt
							end
						end
					end
				end
				local vw = 0
				for _, sgm in ipairs(rowVeins) do
					local p, q, wd = sgm[1], sgm[2], sgm[3]
					local ax, ay = (bb - p[1]) * L, MeshKit.WrapAngle(a - p[2]) * rr
					local bx, by = (q[1] - p[1]) * L, MeshKit.WrapAngle(q[2] - p[2]) * rr
					local l2 = bx * bx + by * by
					local t = l2 > 1e-9 and clamp((ax * bx + ay * by) / l2, 0, 1) or 0
					local dx, dy = ax - bx * t, ay - by * t
					local d = sqrt(dx * dx + dy * dy) / wd
					if d < 1 then
						vw = max(vw, (1 - d * d) * (1 - d * d))
					end
				end
				r, gg, b = skin(bb, a, min(gr, 1), min(cr, 1), vw)
				k = grain[sm.py * w + sm.px + 1]
			else
				r, gg, b = garment(rowZ[3], bb, a, true, rowZ)
				k = 1 + 0.02 * Kit.TileAt(tiles.fine, sm.px * 0.5, sm.py * 0.5)
			end
			return Kit.ApplyAO(r * k, gg * k, b * k, sm.dark * rowAO, sm.light, rowTint)
		end, o)
	end
	local material, refl = "Plastic", 0
	if kind == "UpperLeg" and trunk then
		material, refl = "SmoothPlastic", 0.02 -- the satin dominates the thigh piece
	end
	return { color = color, channels = channels, aoK = aoK, tint = tint, texture = texture, material = material, reflectance = refl }
end

------------------------------------------------------------------------
-- Hands
------------------------------------------------------------------------
local function norm(x, y, z)
	local l = sqrt(x * x + y * y + z * z)
	if l < 1e-9 then
		return 0, -1, 0
	end
	return x / l, y / l, z / l
end

-- the hand's frame in body space: wrist pivot, down the hand (dn), lateral / back of the hand (lat), thumb
-- side (fw)
local function handFrame(sk, side)
	local sg = side == "Right" and 1 or -1
	local w, e = sk.piv[side .. "Wrist"], sk.piv[side .. "Elbow"]
	local dx, dy, dz = norm(w[1] - e[1], w[2] - e[2], w[3] - e[3])
	-- lateral made square to the forearm, then the thumb side (front)
	local lx, ly, lz = sg - (sg * dx) * dx, -(sg * dx) * dy, -(sg * dx) * dz
	lx, ly, lz = norm(lx, ly, lz)
	local fx, fy, fz = dy * lz - dz * ly, dz * lx - dx * lz, dx * ly - dy * lx
	if fz > 0 then
		fx, fy, fz = -fx, -fy, -fz
	end
	local Lf = sqrt((w[1] - e[1]) ^ 2 + (w[2] - e[2]) ^ 2 + (w[3] - e[3]) ^ 2)
	return { w = w, dn = { dx, dy, dz }, lat = { lx, ly, lz }, fw = { fx, fy, fz }, sg = sg, Lf = max(0.4, Lf) }
end

local function at(F, along, latK, fwK)
	local w, dn, lat, fw = F.w, F.dn, F.lat, F.fw
	return { w[1] + dn[1] * along + lat[1] * latK + fw[1] * fwK, w[2] + dn[2] * along + lat[2] * latK + fw[2] * fwK,
		w[3] + dn[3] * along + lat[3] * latK + fw[3] * fwK }
end

-- direction in the hand frame: a = along dn, l = along lat, f = along fw
local function dirIn(F, a, l, f)
	local dn, lat, fw = F.dn, F.lat, F.fw
	return { dn[1] * a + lat[1] * l + fw[1] * f, dn[2] * a + lat[2] * l + fw[2] * f, dn[3] * a + lat[3] * l + fw[3] * f }
end

-- a smooth spine through control points: n samples by arc length (Catmull-Rom)
local function spineThrough(pts, n)
	local dense = {}
	local total = 0
	local lens = {}
	local steps = 8 * (#pts - 1)
	local prev
	for k = 0, steps do
		local x, y, z = MeshKit.CatmullRom(pts, k / steps)
		dense[k + 1] = { x, y, z }
		if prev then
			total += sqrt((x - prev[1]) ^ 2 + (y - prev[2]) ^ 2 + (z - prev[3]) ^ 2)
		end
		lens[k + 1] = total
		prev = dense[k + 1]
	end
	local out = {}
	local j = 1
	for i = 1, n do
		local target = total * (i - 1) / (n - 1)
		while j < #dense and lens[j + 1] < target do
			j += 1
		end
		local a, b = dense[j], dense[min(j + 1, #dense)]
		local l0, l1 = lens[j], lens[min(j + 1, #dense)]
		local t = l1 > l0 and (target - l0) / (l1 - l0) or 0
		out[i] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
	end
	return out, total
end

-- the hand's measurements from the forearm the Limbs module builds (its wrist section) and its length
local function handSize(sk, P, side, Limbs)
	local S = sk.size[side .. "LowerArm"][1]
	local spec = Limbs.Specs.LowerArm(sk, P, side, S)
	local wx, wz = spec.rx(1.0) * spec.scale, spec.rz(1.0) * spec.scale
	return wx, wz, spec.scale, spec
end

-- a finger / thumb tube along control points: radius r0 at the root to r1 at the tip, knuckle swellings
local function finger(m, pts, r0, r1, res, sideHint, frontHint, rowTag, joints)
	local rings, sides = res[1], res[2]
	local spine, len = spineThrough(pts, rings)
	local rowB = {}
	for i = 1, rings do
		rowB[i] = (i - 1) / (rings - 1)
	end
	local info = Kit.GridLoft(m, MeshKit, {
		rings = rings, sides = sides, spine = spine, exact = true, sideHint = sideHint, frontHint = frontHint, rowB = rowB,
		radius = function(t, ang)
			local r = r0 + (r1 - r0) * t
			for _, jt in ipairs(joints or {}) do
				r *= 1 + 0.07 * bell((t - jt) / 0.12)
			end
			-- a little flatter on the palm side (pads), rounder on the back
			return r * (1 - 0.1 * max(0, -cos(ang)))
		end,
		capS = { depth = r0 * 0.4, rings = res[3], bDepth = 0.05 },
		capE = { depth = r1 * 0.85, rings = res[4], bDepth = 0.1 },
	})
	info.tag = rowTag
	info.len = len
	return info
end

-- bare hand (relaxed, fingers a little curled) or the wrapped fist; returns the grid atlas
local function buildHand(m, sk, P, lod, side, fist, Limbs)
	local R = Gear.RES[lod] or Gear.RES.full
	local F = handFrame(sk, side)
	local wx, wz, S = handSize(sk, P, side, Limbs)
	local Lf = F.Lf
	local fem = P.female
	local lp = 0.42 * Lf * (fem and 0.95 or 1) -- wrist to knuckles
	local lf = 0.36 * Lf * (fem and 0.95 or 1) -- the middle finger
	local hw = wz * 1.2 -- half width at the knuckles (thumb to little finger)
	local ht = wx * 0.56 -- half thickness (back to palm)
	local rf = hw * 0.225 -- (the four fingers side by side fill the knuckle width: a relaxed hand, not a rake)
	local atlas = {}
	local sg = F.sg
	local sideHint = { F.lat[1], F.lat[2], F.lat[3] }
	local frontHint = { F.fw[1], F.fw[2], F.fw[3] }
	-- the palm: from inside the forearm's end to the knuckles
	local pr = R.palm
	local palmPts = {}
	for i = 1, pr[1] do
		local t = (i - 1) / (pr[1] - 1)
		local along = -0.07 * Lf + (lp + 0.07 * Lf) * t
		-- a relaxed hand hangs a little flexed; a fist a little more
		palmPts[i] = at(F, along, -(fist and 0.06 or 0.04) * along, 0)
	end
	local palmRow = {}
	for i = 1, pr[1] do
		palmRow[i] = (i - 1) / (pr[1] - 1)
	end
	local palm = Kit.GridLoft(m, MeshKit, {
		rings = pr[1], sides = pr[2], spine = palmPts, exact = true, sideHint = sideHint, frontHint = frontHint, rowB = palmRow,
		section = function(t, ang)
			local i = floor(t * (pr[1] - 1) + 0.5) + 1
			local u = palmRow[i]
			local c, s = cos(ang), sin(ang)
			-- wrist size -> knuckle width; thick at the heel of the hand
			-- (the heel of the hand starts inside the forearm's wrist, round like it (an ellipse a little smaller
			-- than the forearm's end), and only widens / squares off once it is out of the forearm's blunt end,
			-- so it comes out of that end at a steep angle: a clean wrist line, no sliver crossings)
			local ex = lerp(wx * 0.84, ht, smooth(0.0, 0.6, u)) * (1 + 0.18 * bell((u - 0.35) / 0.4))
			local ez = lerp(wz * 0.88, hw, smooth(0.2, 0.75, u))
			local e = 2 / lerp(2.0, 2.4, smooth(0.25, 0.6, u))
			local x = ex * (c < 0 and -1 or 1) * abs(c) ^ e
			local f = ez * (s < 0 and -1 or 1) * abs(s) ^ e
			-- the thenar (thumb base) and hypothenar pads on the palm side
			local palmSide = max(0, -c)
			x -= (0.28 * ht * bell((u - 0.3) / 0.32) * Kit.bell(MeshKit.WrapAngle(ang - (MED - 0.75)) / 0.9)
				+ 0.14 * ht * bell((u - 0.45) / 0.4) * Kit.bell(MeshKit.WrapAngle(ang - (MED + 0.7)) / 0.8)) * palmSide
			return x, f
		end,
		capS = { depth = wx * 0.5, rings = pr[3], bDepth = 0.1 },
		capE = { depth = ht * (fist and 0.7 or 0.55), rings = pr[4], bDepth = 0.1 },
	})
	palm.tag = "palm"
	atlas[#atlas + 1] = palm
	-- fingers
	local fr = R.finger
	if fr then
		local fingers = {
			{ z = 0.7, len = 0.92, r = 1.0, low = 0.0, curl = 0 },
			{ z = 0.24, len = 1.0, r = 1.04, low = 0.0, curl = 4 },
			{ z = -0.24, len = 0.95, r = 0.98, low = 0.02, curl = 8 },
			{ z = -0.68, len = 0.76, r = 0.86, low = 0.08, curl = 14 },
		}
		for k, fd in ipairs(fingers) do
			local base = at(F, lp * (0.94 - fd.low), -0.15 * ht, fd.z * hw)
			local L1, L2, L3 = 0.45 * lf * fd.len, 0.3 * lf * fd.len, 0.25 * lf * fd.len
			local a1, a2, a3
			if fist then
				a1, a2, a3 = math.rad(84), math.rad(98 + fd.curl * 0.3), math.rad(62)
			else
				-- relaxed: every joint a little bent, more toward the little finger (the cascade of a resting hand)
				a1, a2, a3 = math.rad(22 + 1.2 * fd.curl), math.rad(32 + fd.curl), math.rad(18)
			end
			local spread = fd.z * 0.05 * (fist and 0.4 or 1)
			local function step(p, ang, l)
				-- curl toward the palm (the medial side, -lat), fan out across the hand
				local d = dirIn(F, cos(ang), -sin(ang), spread)
				local dx, dy, dz = norm(d[1], d[2], d[3])
				return { p[1] + dx * l, p[2] + dy * l, p[3] + dz * l }
			end
			local p0 = step(base, a1, -0.05 * lf)
			local p1 = step(base, a1, L1)
			local p2 = step(p1, a1 + a2, L2)
			local p3 = step(p2, a1 + a2 + a3, L3)
			local info = finger(m, { p0, base, p1, p2, p3 }, rf * fd.r, rf * fd.r * 0.82, fr, sideHint, frontHint, "finger" .. k, { 0.38, 0.7 })
			atlas[#atlas + 1] = info
		end
		-- the thumb: from the heel of the palm on the thumb side, along the index finger (a fist: across the
		-- middle of the fingers)
		local tr = R.thumb
		local tb = at(F, lp * 0.28, -0.35 * ht, 0.72 * hw)
		local d1 = fist and dirIn(F, 0.55, -0.7, 0.3) or dirIn(F, 0.78, -0.35, 0.45)
		local d2 = fist and dirIn(F, 0.2, -0.75, -0.55) or dirIn(F, 0.92, -0.3, 0.15)
		local tl = 0.62 * lf
		local function go(p, d, l)
			local dx, dy, dz = norm(d[1], d[2], d[3])
			return { p[1] + dx * l, p[2] + dy * l, p[3] + dz * l }
		end
		local t0 = go(tb, d1, -0.08 * lf)
		local t1 = go(tb, d1, 0.5 * tl)
		local t2 = go(t1, d2, 0.5 * tl)
		local info = finger(m, { t0, tb, t1, t2 }, rf * 1.22, rf * 1.0, tr, sideHint, frontHint, "thumb", { 0.5 })
		atlas[#atlas + 1] = info
	end
	return { atlas = atlas, F = F, lp = lp, lf = lf, hw = hw, ht = ht, rf = rf }
end

-- the standing height (sole to the top of the head)
local function standingHeight(sk)
	local hd = sk.size.Head
	local fc, fs = sk.center.RightFoot, sk.size.RightFoot
	return max(2, sk.center.Head[2] + hd[2] / 2 - (fc[2] - fs[2] / 2))
end

-- the glove's shape, shared by the mesh and its landmarks: a padded fist, not a mitten. Length from the
-- standing height (a 16 oz glove is ~12 % of it from the wrist to the knuckle pad's front); the hand
-- compartment swells from the cuff to its widest at ~2/3 (about 1.2 x the cuff) and narrows into a rounded
-- front; the spine curls toward the palm over the last third, so the knuckle pad is a round front face
-- (the fingers curled inside), finished by a deep dome
local function gloveShape(sk, P, side, gl, Limbs)
	local F = handFrame(sk, side)
	local _, _, S, spec = handSize(sk, P, side, Limbs)
	local Lf = F.Lf
	local ozK = 0.86 + 0.016 * (gl.oz - 8)
	local fem = P.female and 0.94 or 1
	local glen = 0.118 * standingHeight(sk) * gl.l * (0.9 + 0.1 * ozK) * fem
	-- the cuff's radius at the wrist (AnatomyBodyLimbs' glove zone: the forearm at the cuff's top, flared 6 %)
	local top = gl.cuffTop
	local cx, cz = (spec.rx(top) * 1.02 + 0.07) * S * 1.06, (spec.rz(top) * 1.06 + 0.07) * S * 1.06
	local bx = max(cx * 1.08, 0.3 * S * gl.w * ozK * fem) -- back-to-palm half size of the fist
	local bz = max(cz * 1.18, 0.34 * S * gl.w * ozK * fem) -- thumb-side-to-little-finger half size
	local capD = bx * 1.0
	-- (the body starts a little up the cuff, just outside it: the cuff's end is inside the glove, and the join is
	-- the seam ring where the hand compartment is sewn to the cuff, not two surfaces crossing)
	local s0, s1 = -0.06 * Lf, glen - capD * 0.75
	local curl = math.rad(48)
	local function theta(t)
		local k = smooth(0.5, 1.0, t)
		return curl * k * k
	end
	-- spine point at t (0..1): arc length from s0, the direction turning toward the palm (-lat)
	local STEPS = 24
	local pts = { { 0, 0 } }
	for i = 1, STEPS do
		local tm = (i - 0.5) / STEPS
		local th = theta(tm)
		local ds = (s1 - s0) / STEPS
		local p = pts[i]
		pts[i + 1] = { p[1] + cos(th) * ds, p[2] - sin(th) * ds }
	end
	local function spineAt(t)
		local f = clamp(t, 0, 1) * STEPS
		local i = min(STEPS - 1, floor(f))
		local w = f - i
		local a, b = pts[i + 1], pts[i + 2]
		local da, dl = a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w
		-- the fist sits a little toward the back of the hand (the padding is over the knuckles)
		return at(F, s0 + da, dl + 0.04 * S * smooth(0.2, 0.8, t), 0)
	end
	local kk = gl.k
	local function dims(u)
		local grow = smooth(0.0, 0.5, u)
		local ex = lerp(cx * 1.035, bx, grow) * (1 + 0.07 * kk * bell((u - 0.66) / 0.26)) * (1 - 0.1 * smooth(0.82, 1.0, u))
		local ez = lerp(cz * 1.035, bz, grow) * (1 + 0.04 * bell((u - 0.68) / 0.3)) * (1 - 0.08 * smooth(0.8, 1.0, u))
		return ex, ez
	end
	return { F = F, S = S, glen = glen, bx = bx, bz = bz, cx = cx, cz = cz, capD = capD, spineAt = spineAt, dims = dims, ozK = ozK, fem = fem }
end

-- the boxing glove: a padded fist on the cuff (the cuff is the forearm piece's glove zone), its thumb
local function buildGlove(m, sk, P, lod, side, gl, Limbs)
	local R = Gear.RES[lod] or Gear.RES.full
	local G = gloveShape(sk, P, side, gl, Limbs)
	local F, S, bx, bz = G.F, G.S, G.bx, G.bz
	local gr = R.glove
	local rows = gr[1]
	local pts, rowB = {}, {}
	for i = 1, rows do
		local t = (i - 1) / (rows - 1)
		pts[i] = G.spineAt(t)
		rowB[i] = t
	end
	local body = Kit.GridLoft(m, MeshKit, {
		rings = rows, sides = gr[2], spine = pts, exact = true, sideHint = { F.lat[1], F.lat[2], F.lat[3] }, frontHint = { F.fw[1], F.fw[2], F.fw[3] },
		rowB = rowB,
		section = function(t, ang)
			local i = floor(t * (rows - 1) + 0.5) + 1
			local u = rowB[i]
			local c, s = cos(ang), sin(ang)
			local ex, ez = G.dims(u)
			-- the back is domed padding, the palm side a little flatter with the grip bar's shallow dent across
			-- it (one exponent all round: no crease where the back meets the palm)
			local e = 2 / 2.25
			local palm = c < 0 and (0.9 - 0.06 * bell((u - 0.62) / 0.12) * (-c)) or 1
			local x = ex * (c < 0 and -1 or 1) * abs(c) ^ e * palm
			local f = ez * (s < 0 and -1 or 1) * abs(s) ^ e
			return x, f
		end,
		capS = { depth = 0.02, rings = gr[3], bDepth = 0.02 },
		capE = { depth = G.capD, rings = gr[4], bDepth = 0.25 },
	})
	body.tag = "glove"
	local atlas = { body }
	local tr = R.gthumb
	if tr then
		-- the thumb: a thick padded roll along the thumb side (sewn on along its length, its root inside the
		-- fist, its tip tucked against the padding toward the palm)
		local r = 0.17 * S * gl.w * G.ozK * G.fem
		local glen = G.glen
		local function tp(al, l, f)
			return at(F, al, l, f)
		end
		local p0 = tp(glen * 0.08, -0.25 * bx, bz * 0.62)
		local p1 = tp(glen * 0.26, -0.32 * bx, bz * 0.8)
		local p2 = tp(glen * 0.46, -0.42 * bx, bz * 0.82)
		local p3 = tp(glen * 0.62, -0.62 * bx, bz * 0.66)
		local info = finger(m, { p0, p1, p2, p3 }, r * 1.0, r * 0.86, tr, { F.lat[1], F.lat[2], F.lat[3] }, { F.fw[1], F.fw[2], F.fw[3] }, "gthumb", nil)
		atlas[#atlas + 1] = info
	end
	return { atlas = atlas, F = F, glen = G.glen, bx = bx, bz = bz }
end

------------------------------------------------------------------------
-- Feet
------------------------------------------------------------------------
-- boxing boot / trainer: a loft from the heel to the toe with a flat sole; the boot shaft above the ankle is
-- the shin piece's boot zone. Sized from the standing height (a shoe is ~15 % of it), not from the shin: longer
-- athletic shins must not stretch the foot into a flipper. The spine runs along the sole; the section is a
-- rounded upper over a sole with a vertical side wall; the end domes are lifted to mid height, so the toe box
-- and the heel are round, not pointed; at the ankle the upper is at least as wide as the shin's shaft (no
-- step where the shaft meets the shoe); the tongue under the laces is raised a little.
local function buildShoe(m, sk, P, lod, side, sh, Limbs, llZones)
	local R = Gear.RES[lod] or Gear.RES.full
	local sg = side == "Right" and 1 or -1
	local an = sk.piv[side .. "Ankle"]
	local fc = sk.center[side .. "Foot"]
	local fs = sk.size[side .. "Foot"]
	local soleY = fc[2] - fs[2] / 2
	local FL = Gear.FootLength(sk, P)
	local ankleH = max(0.12, an[2] - soleY)
	local trainer = sh.trainer
	local soleH = trainer and 0.085 or 0.06
	-- the shin's shaft (or bare ankle) round the ankle: the upper there encloses it
	local opt = { zones = llZones }
	local function off(ang)
		local p = Limbs.SurfacePoint(sk, P, side, "LowerLeg", opt, 1.0, ang)
		return abs(p[1] - an[1]), abs(p[3] - an[3])
	end
	local latW = off(LAT)
	local medW = off(MED)
	local _, backZ = off(BACK)
	local shaftW = max(latW, medW) + 0.008
	-- heel back / toe tip (dome tips): the ankle a quarter of the way from the heel
	local capS, capE = 0.06 * FL, 0.13 * FL
	local heelZ = an[3] + max(0.21 * FL, backZ + 0.045) - capS
	local toeZ = an[3] - 0.75 * FL + capE
	local span = heelZ - toeZ
	local uA = (heelZ - an[3]) / span -- the ankle's ring parameter
	local H = Kit.Curve({ { 0.0, ankleH * 0.86 }, { uA * 0.6, ankleH * 1.0 }, { uA, ankleH * 1.06 }, { uA + 0.12, ankleH * 0.94 }, { 0.5, max(0.27 * FL, soleH + 0.12) },
		{ 0.72, max(0.2 * FL, soleH + 0.09) }, { 0.88, max(0.165 * FL, soleH + 0.075) }, { 1.0, max(0.14 * FL, soleH + 0.065) } })
	local Wd = Kit.Curve({ { 0.0, max(0.125 * FL, shaftW * 0.9) }, { uA, max(0.135 * FL, shaftW) }, { uA + 0.14, max(0.15 * FL, shaftW * 0.96) }, { 0.5, 0.16 * FL },
		{ 0.72, 0.19 * FL }, { 0.88, 0.175 * FL }, { 1.0, 0.135 * FL } })
	local sr = R.shoe
	local rows = sr[1]
	local pts, rowB = {}, {}
	for i = 1, rows do
		local t = (i - 1) / (rows - 1)
		-- the toe sits a little toward the big toe (medial) and springs up a hair
		pts[i] = { an[1] - sg * 0.035 * FL * smooth(0.45, 1.0, t), soleY + 0.01 * smooth(0.8, 1.0, t), heelZ + (toeZ - heelZ) * t }
		rowB[i] = t
	end
	local u0, u1 = uA + 0.1, 0.8 -- the lacing over the instep (the tongue is raised under it)
	local info = Kit.GridLoft(m, MeshKit, {
		rings = rows, sides = sr[2], spine = pts, exact = true, sideHint = { sg, 0, 0 }, frontHint = { 0, 1, 0 }, rowB = rowB,
		section = function(t, ang)
			local i = floor(t * (rows - 1) + 0.5) + 1
			local u = rowB[i]
			local c, s = cos(ang), sin(ang)
			local hw = Wd(u)
			-- the arch: the inner side curves in under the middle of the foot
			if c < 0 then
				hw *= 1 - 0.1 * bell((u - 0.45) / 0.2)
			end
			local h = H(u)
			local x, f
			if s >= -1e-9 then -- (the seam column at 2 pi: sin a hair below 0, same branch as column 0)
				-- the upper: from the top of the sole's wall, rounded over the top, fuller at the toe box
				-- (round over the heel and ankle, so the top closes in onto the shaft above it with no ledge; fuller
				-- and squarer over the forefoot)
				local ex = lerp(2.0, 2.4, smooth(uA * 0.5, uA + 0.25, u))
				x = hw * (c < 0 and -1 or 1) * abs(c) ^ (2 / ex)
				f = soleH + (h - soleH) * max(s, 0) ^ (2 / lerp(2.0, 2.25, smooth(uA * 0.5, uA + 0.25, u)))
				-- the raised tongue under the laces
				f += 0.012 * FL * bell((ang - FRONT) / 0.45) * smooth(u0 - 0.05, u0 + 0.05, u) * (1 - smooth(u1 - 0.04, u1 + 0.06, u))
			else
				-- the sole: a near-vertical wall a hair wider than the upper (the welt), flat underneath
				local q = -s
				x = hw * 1.045 * (c < 0 and -1 or 1) * abs(c) ^ (2 / 7)
				f = soleH * max(0, 1 - q / 0.5) ^ 1.5 - 0.006 * q * q
			end
			return x, f
		end,
		capS = { depth = capS, rings = sr[3], bDepth = capS / span, shift = { 0, ankleH * 0.3, 0 } },
		capE = { depth = capE, rings = sr[4], bDepth = capE / span, shift = { 0, H(1.0) * 0.42, 0 } },
	})
	info.tag = "shoe"
	return { atlas = { info }, soleY = soleY, soleH = soleH, FL = FL, heelZ = heelZ, toeZ = toeZ, H = H, ankleH = ankleH, span = span, uA = uA, u0 = u0, u1 = u1 }
end

------------------------------------------------------------------------
-- Build a hand / foot piece: mesh, grid atlas, painter
------------------------------------------------------------------------
function Gear.Build(sk, P, lod, side, kind, wear, pc, seed)
	local Limbs = require(script.Parent:WaitForChild("AnatomyBodyLimbs"))
	local m = MeshKit.New(side .. kind)
	local g = wear.gear
	local sr, sgr, sb = pc.sr, pc.sg, pc.sb
	local grid, paint
	local aoSkin = pc.ao
	if kind == "Hand" then
		if g.hands == "gloves" then
			local gl = g.glove
			local G = buildGlove(m, sk, P, lod, side, gl, Limbs)
			grid = { atlas = G.atlas }
			Kit.GridNormals(m, MeshKit, grid)
			local material, refl = "Leather", 0.02
			if gl.finish == "Matte" then
				material, refl = "SmoothPlastic", 0
			elseif gl.finish == "Patent" then
				material, refl = "SmoothPlastic", 0.22
			elseif gl.finish == "Metallic" then
				material, refl = "Foil", 0.35
			end
			local c, palmC, trim = gl.c, gl.palm, gl.trim
			local pip = gl.piping
			local stc = gl.stitch
			local seamA1, seamA2 = FRONT + 0.5, BACK - 0.5
			local function gcolor(gi, t, ang, crisp, tiles, px, py)
				local r, gg, b = c[1], c[2], c[3]
				if gi == 1 then
					-- the palm panel (between the side seams, short of the striking surface) in the palm tone
					local inPalm = adist(ang, MED) < (MED - seamA1)
					local pw = (inPalm and t < 0.86) and 1 or 0
					if not crisp then
						pw = (1 - smooth(MED - seamA1 - 0.25, MED - seamA1 + 0.25, adist(ang, MED))) * (1 - smooth(0.8, 0.9, t))
					end
					r, gg, b = mix(r, gg, b, palmC[1], palmC[2], palmC[3], pw)
					-- piping and stitching along the seam round the glove's outline
					local ds = min(adist(ang, seamA1), adist(ang, seamA2))
					if crisp then
						if pip then
							local p = 1 - smooth(0.035, 0.06, ds)
							r, gg, b = mix(r, gg, b, pip[1], pip[2], pip[3], p * smooth(0.12, 0.2, t))
						end
						if gl.stitchKind ~= "Hidden" then
							local st = (1 - smooth(0.012, 0.024, abs(ds - 0.11))) * ((((t * 40) % 1) < 0.55) and 1 or 0) * smooth(0.12, 0.2, t)
							r, gg, b = mix(r, gg, b, stc[1], stc[2], stc[3], st)
							if gl.stitchKind == "Double" then
								local st2 = (1 - smooth(0.012, 0.024, abs(ds - 0.19))) * ((((t * 40 + 0.5) % 1) < 0.55) and 1 or 0) * smooth(0.12, 0.2, t)
								r, gg, b = mix(r, gg, b, stc[1], stc[2], stc[3], st2)
							end
						end
					elseif pip then
						r, gg, b = mix(r, gg, b, pip[1], pip[2], pip[3], 0.35 * (1 - smooth(0.05, 0.2, ds)))
					end
					-- amateur competition gloves: the white target area over the knuckles
					if gl.target then
						local ta = (crisp and (adist(ang, LAT) < 1.05 and t > 0.58) and 1 or 0) or (1 - smooth(0.9, 1.2, adist(ang, LAT))) * smooth(0.52, 0.64, t)
						r, gg, b = mix(r, gg, b, 0.95, 0.95, 0.94, ta)
					end
					-- wear on the striking surface: scuffs, then cracks
					if gl.cond < 70 then
						local wk = (70 - gl.cond) / 70
						local scuff = smooth(0.62, 0.86, t) * (1 - smooth(0.6, 1.4, adist(ang, LAT)))
						local n = crisp and (0.5 + 0.5 * Kit.TileAt(tiles.fine, px * 0.5, py * 0.5)) or 0.6
						r, gg, b = mix(r, gg, b, 0.8, 0.77, 0.7, 0.4 * wk * scuff * n)
						if gl.cond < 40 and crisp then
							local cr = (1 - smooth(0.0, 0.08, abs(Kit.TileAt(tiles.pore, px * 0.35, py * 0.35)))) * scuff
							r, gg, b = mix(r, gg, b, r * 0.45, gg * 0.45, b * 0.45, 0.6 * cr)
						end
					end
					-- a sweat mark spreading from the cuff on old gloves
					if gl.cond < 30 then
						local sw = (1 - smooth(0.1, 0.45, t)) * 0.3
						r, gg, b = r * (1 - sw), gg * (1 - sw), b * (1 - sw)
					end
				else
					-- the thumb: palm tone on its inner half
					local inner = crisp and (cos(ang) < 0 and 1 or 0) or 0.5 * (1 - cos(ang)) * 0.6
					r, gg, b = mix(r, gg, b, palmC[1], palmC[2], palmC[3], inner)
				end
				return r, gg, b
			end
			-- vertex colours: which grid a vertex belongs to, its row parameter and angle
			local gi, tB, tA = Gear.GridMaps(m, grid)
			paint = {
				vertex = function(i)
					return gcolor(gi[i], tB[i], tA[i], false)
				end,
				texel = function(s, tiles, tw)
					local r, gg, b = gcolor(s.grid, s.b, s.a, true, tiles, s.px, s.py)
					local k = 1 + 0.025 * Kit.TileAt(tiles.fine, s.px * 0.7, s.py * 0.7)
					return r * k, gg * k, b * k
				end,
				ao = { cavity = 0.3, down = 0.12, ridge = 0.06 }, tint = pc.clothTint, material = material, reflectance = refl,
			}
			-- flex: none (padding does not flex)
			return m, { grid = grid }, paint
		end
		-- bare hand or the wrapped fist
		local fist = g.hands == "wraps"
		local Hd = buildHand(m, sk, P, lod, side, fist, Limbs)
		grid = { atlas = Hd.atlas }
		Kit.GridNormals(m, MeshKit, grid)
		local wr = g.wrap
		local gi, tB, tA = Gear.GridMaps(m, grid)
		local function hcolor(gidx, t, ang, crisp, tiles, px, py, tw)
			local r, gg, b = sr, sgr, sb
			local tag = grid.atlas[gidx] and grid.atlas[gidx].tag or "palm"
			local back = 0.5 + 0.5 * cos(ang) -- 1 on the back of the hand / finger, 0 on the palm side
			if tag == "palm" then
				-- the palm a little lighter / pinker, the knuckles redder, the back of the hand a touch darker
				r, gg, b = mix(r, gg, b, min(1, sr * 1.06 + 0.03), sgr * 1.0, sb * 0.98, 0.35 * (1 - back))
				local knuck = smooth(0.78, 1.0, t) * back
				r, gg, b = mix(r, gg, b, sr * 0.92, sgr * 0.74, sb * 0.7, 0.35 * knuck)
				if fist then
					-- the wrap: over the palm, the back and the knuckles (the fingers come out of it)
					local cover = crisp and ((t < 0.97) and 1 or 0) or (1 - smooth(0.9, 1.05, t))
					local c = wr.c
					local lay = crisp and (0.96 + 0.06 * smooth(0.0, 0.15, ((t * 5 + ang / TAU) % 1))) or 1
					local wr2 = (wr.gel and back > 0.6 and t > 0.72) and 0.82 or 1
					r, gg, b = mix(r, gg, b, c[1] * lay * wr2, c[2] * lay * wr2, c[3] * lay * wr2, cover)
					-- the X across the back of the hand in the second colour
					if crisp and wr.c2 ~= wr.c then
						local x1 = abs(MeshKit.WrapAngle(ang - (t - 0.5) * 1.6)) < 0.1 and back > 0.5
						local x2 = abs(MeshKit.WrapAngle(ang + (t - 0.5) * 1.6)) < 0.1 and back > 0.5
						if x1 or x2 then
							r, gg, b = wr.c2[1], wr.c2[2], wr.c2[3]
						end
					end
				end
			else
				-- fingers / thumb: knuckle creases on the back, the nail on the last segment
				local nail = smooth(0.66, 0.74, t) * (1 - smooth(0.5, 0.75, adist(ang, LAT)))
				if not crisp then
					nail *= 0.8
				end
				r, gg, b = mix(r, gg, b, min(1, sr * 1.08 + 0.1), min(1, sgr * 1.02 + 0.08), min(1, sb * 1.02 + 0.08), 0.6 * nail)
				local crease = (bell((t - 0.38) / 0.05) + bell((t - 0.7) / 0.05)) * back
				r, gg, b = mix(r, gg, b, sr * 0.8, sgr * 0.68, sb * 0.64, 0.3 * crease)
				-- the wrap covers the root of the fingers on a wrapped hand
				if fist and tag ~= "thumb" then
					local cover = crisp and (t < 0.22 and 1 or 0) or (1 - smooth(0.15, 0.3, t))
					local c = wr.c
					r, gg, b = mix(r, gg, b, c[1], c[2], c[3], cover)
				elseif fist then
					local cover = crisp and (t < 0.3 and 1 or 0) or (1 - smooth(0.2, 0.38, t))
					local c = wr.c
					r, gg, b = mix(r, gg, b, c[1], c[2], c[3], cover)
				end
			end
			if crisp then
				local k = Kit.GrainTable(pc, tw, tw)[py * tw + px + 1]
				r, gg, b = r * k, gg * k, b * k
			end
			return r, gg, b
		end
		paint = {
			vertex = function(i, x, y, z)
				local r, gg, b = hcolor(gi[i], tB[i], tA[i], false)
				local k = 1 + 0.02 * MeshKit.Noise(x * 4, y * 4, z * 4, seed + 41)
				return r * k, gg * k, b * k
			end,
			texel = function(s, tiles, tw)
				return hcolor(s.grid, s.b, s.a, true, tiles, s.px, s.py, tw)
			end,
			ao = aoSkin, tint = pc.aoTint, material = "Plastic", reflectance = 0,
		}
		return m, { grid = grid }, paint
	end
	-- foot: boot or trainer
	local sh = g.shoe
	local Fd = buildShoe(m, sk, P, lod, side, sh, Limbs, wear.zones[side .. "LowerLeg"])
	grid = { atlas = Fd.atlas }
	Kit.GridNormals(m, MeshKit, grid)
	local gi, tB, tA = Gear.GridMaps(m, grid)
	local soleTop = Fd.soleY + Fd.soleH
	local trainer = sh.trainer
	local soleC = sh.sole
	if trainer then
		soleC = { 0.93, 0.93, 0.9 } -- foam midsole
	end
	local FL, span = Fd.FL, Fd.span
	local an = sk.piv[side .. "Ankle"]
	local fsg = side == "Right" and 1 or -1
	local Y0, Y1 = Fd.u0 * span, Fd.u1 * span
	-- (x, y body space) -> colour; t = the ring parameter (heel 0 .. toe 1), ang = the column angle
	local function fcolor(t, ang, x, y, crisp, tiles, px, py)
		local c = sh.c
		local r, gg, b = c[1], c[2], c[3]
		-- the sole: a darker side wall under a stitched welt line, the tread underneath
		local sw = crisp and (y < soleTop + 0.002 and 1 or 0) or (1 - smooth(soleTop - 0.01, soleTop + 0.01, y))
		if sw > 0 then
			local k = 0.8 + 0.2 * (1 - smooth(Fd.soleY + 0.004, Fd.soleY + 0.012, y)) -- the bottom lighter than the wall
			local sr2, sg2, sb2 = soleC[1] * k, soleC[2] * k, soleC[3] * k
			if trainer then
				-- rubber outsole under the foam
				local os = crisp and (y < Fd.soleY + 0.025 and 1 or 0) or (1 - smooth(Fd.soleY + 0.015, Fd.soleY + 0.035, y))
				sr2, sg2, sb2 = mix(sr2, sg2, sb2, 0.17, 0.17, 0.18, os)
			elseif crisp then
				-- a groove round the wall half way up
				local gv = 1 - smooth(0.002, 0.004, abs(y - (Fd.soleY + Fd.soleH * 0.45)))
				sr2, sg2, sb2 = sr2 * (1 - 0.3 * gv), sg2 * (1 - 0.3 * gv), sb2 * (1 - 0.3 * gv)
			end
			return mix(r, gg, b, sr2, sg2, sb2, sw)
		end
		if crisp then
			-- the welt stitching just above the sole
			local st = (1 - smooth(0.002, 0.004, abs(y - (soleTop + 0.008)))) * ((((t * span) / 0.02) % 1 < 0.55) and 1 or 0)
			r, gg, b = mix(r, gg, b, r * 0.55, gg * 0.55, b * 0.55, st)
		end
		if trainer then
			-- toe cap and heel counter in a lighter overlay, the brand stripe along the outer side
			local toe = crisp and (t > 0.86 and 1 or 0) or smooth(0.82, 0.9, t)
			r, gg, b = mix(r, gg, b, sh.accent[1], sh.accent[2], sh.accent[3], 0.3 * toe)
			local heel = 1 - smooth(0.13, crisp and 0.15 or 0.2, t + 0.1 * (y - Fd.soleY) / Fd.ankleH)
			r, gg, b = mix(r, gg, b, sh.accent[1], sh.accent[2], sh.accent[3], 0.5 * heel)
			local outer = adist(ang, LAT)
			local diag = abs(outer - (0.55 + (t - 0.5) * 1.6))
			local stripe = (crisp and (diag < 0.12 and t > 0.3 and t < 0.75) and 1 or 0) or 0
			r, gg, b = mix(r, gg, b, sh.accent[1], sh.accent[2], sh.accent[3], stripe)
		else
			-- the toe cap's stitched edge
			local tc = crisp and (1 - smooth(0.004, 0.008, abs(t - 0.84))) * (1 - smooth(0.9, 1.3, adist(ang, FRONT))) or 0
			r, gg, b = mix(r, gg, b, r * 0.6, gg * 0.6, b * 0.6, tc)
		end
		-- the lacing over the instep (continues the shaft's), the tongue up to the ankle (under the shin's shaft)
		if adist(ang, FRONT) < 1.2 then
			local X = x - (an[1] - fsg * 0.035 * FL * smooth(0.45, 1.0, t))
			r, gg, b = paintLacing(r, gg, b, sh, t * span, X, Y0, Y1, FL, crisp, -span, nil)
		end
		if sh.style == "eliteBoot" then
			local heel = crisp and (t < 0.1 and 1 or 0) or (1 - smooth(0.06, 0.14, t))
			r, gg, b = mix(r, gg, b, 0.86, 0.68, 0.26, 0.8 * heel)
		end
		if sh.cond < 50 then
			-- scuffed toe
			local k = (50 - sh.cond) / 50 * 0.35 * smooth(0.82, 1.0, t)
			r, gg, b = mix(r, gg, b, 0.47, 0.43, 0.37, k)
		end
		return r, gg, b
	end
	local fc = sk.center[side .. "Foot"]
	paint = {
		vertex = function(i, x, y, z)
			return fcolor(tB[i], tA[i], x, y, false)
		end,
		texel = function(s, tiles, tw)
			local r, gg, b = fcolor(s.b, s.a, s.x + fc[1], s.y + fc[2], true, tiles, s.px, s.py)
			local k = 1 + 0.025 * Kit.TileAt(tiles.fine, s.px * 0.6, s.py * 0.6)
			return r * k, gg * k, b * k
		end,
		ao = { cavity = 0.3, down = 0.2, ridge = 0.05 }, tint = pc.clothTint, material = trainer and "Fabric" or "Leather", reflectance = 0,
		needP = true,
	}
	return m, { grid = grid }, paint
end

-- per vertex: which grid of the atlas (1..), the row parameter and the column angle (for vertex paint)
function Gear.GridMaps(m, grid)
	local gi, tB, tA = table.create(m.nv, 1), table.create(m.nv, 0), table.create(m.nv, 0)
	for k, g in ipairs(grid.atlas or { grid }) do
		local sides = g.sides
		for _, row in ipairs(g.rows) do
			for j = 0, row.n - 1 do
				local v = row.s + j
				gi[v] = k
				tB[v] = row.b
				tA[v] = row.n > sides and TAU * j / sides or TAU * (j + 0.5) / sides
			end
		end
	end
	return gi, tB, tA
end

-- lettering spots on the gear: BodyFX puts the round-1 glove logo, the glove cuff's wordmark, the boot's
-- wordmark and heel mark there as client text plates (the round-1 patches hide with the gear they sat on).
-- Each spot is three landmarks: <name> (on the surface), <name>N (0.1 out along the surface normal), <name>U
-- (0.1 along the plate's up direction)
function Gear.Landmarks(sk, P, wear, put, Limbs)
	local g = wear.gear
	local function spot(name, part, pos, n, up)
		put(name, part, pos)
		put(name .. "N", part, { pos[1] + n[1] * 0.1, pos[2] + n[2] * 0.1, pos[3] + n[3] * 0.1 })
		put(name .. "U", part, { pos[1] + up[1] * 0.1, pos[2] + up[2] * 0.1, pos[3] + up[3] * 0.1 })
	end
	for _, side in ipairs({ "Right", "Left" }) do
		local L = side == "Right" and "R" or "L"
		if g.hands == "gloves" then
			local gl = g.glove
			-- the back of the fist (the glove's lateral side, half way down the padding)
			local G = gloveShape(sk, P, side, gl, Limbs)
			local F = G.F
			local t = 0.55
			local ex = G.dims(t)
			local c = G.spineAt(t)
			local pos = { c[1] + F.lat[1] * ex, c[2] + F.lat[2] * ex, c[3] + F.lat[3] * ex }
			spot("GloveLogo" .. L, side .. "Hand", pos, F.lat, { -F.dn[1], -F.dn[2], -F.dn[3] })
			-- the cuff's front, a little under its rolled top
			local zones = wear.zones[side .. "LowerArm"]
			local b = gl.cuffTop + 0.16 * (1 - gl.cuffTop)
			local p2, n2, u2 = Limbs.SurfaceFrame(sk, P, side, "LowerArm", { zones = zones }, b, FRONT)
			spot("CuffWord" .. L, side .. "LowerArm", p2, n2, u2)
		end
		local sh = g.shoe
		if sh.shaft < 0.9 then
			-- a boot: the wordmark on the shaft's outer side, the heel mark low on its back
			local zones = wear.zones[side .. "LowerLeg"]
			local b = sh.shaft + 0.3 * (1 - sh.shaft)
			local p3, n3, u3 = Limbs.SurfaceFrame(sk, P, side, "LowerLeg", { zones = zones }, b, LAT)
			spot("BootWord" .. L, side .. "LowerLeg", p3, n3, u3)
			local p4, n4, u4 = Limbs.SurfaceFrame(sk, P, side, "LowerLeg", { zones = zones }, max(b, 0.9), BACK)
			spot("BootHeel" .. L, side .. "LowerLeg", p4, n4, u4)
		end
	end
	return nil
end

return Gear
