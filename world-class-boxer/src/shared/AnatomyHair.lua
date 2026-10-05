-- AnatomyHair: the "Hair" section of the anatomy meshes (ANATOMY_CONTRACTS.md). Hair that follows the
-- skull the Head section builds (AnatomySkull): a scalp shell carrying the cut (fades as smooth gradients,
-- stubble, crisp line-ups, partings, 360 waves, cornrow / box partings) and, over it, hundreds of strands
-- grouped into clumps (tapered, slightly twisted lens-section sweeps with soft thin tips and flyaways),
-- layered for volume, per hair type: straight and wavy clumps, curly = curl clusters of ringlets, coily /
-- afro-textured = dense springy coils with shrinkage. Locs, braids (3-strand plaits), twists, cornrows,
-- ponytails; growth over time; hairline types; dye and highlights. Long hair, locs, braids and tails hang
-- in rigid groups HairFX swings (mesh.hairfx + joint landmarks <piece>.0 / <piece>.1); curls and coily
-- volumes bounce.
-- Pieces (all attached to Head): HairCap (shell, strand texture at full / medium), HairTop (static clumps,
-- curls, coils), HairStrands (fine strands, flyaways: double sided), HairMass (volumes: afro, high top),
-- moving groups HairClumpNN / HairLocNN / HairBraidNN / HairTailN (+ "b" for a group's lower segment).
-- Built in nominal space (a 1.2-stud head) and scaled to the real head in Parts.Finish.
local Shared = script.Parent
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Kit = require(Shared:WaitForChild("AnatomyHairKit"))
local Parts = require(Shared:WaitForChild("AnatomyHairParts"))

local Gen = {}
Gen.Section = "Hair"
Gen.LODs = { full = true, medium = true, low = true }
-- default replace rules (LookData.DEFAULT_REPLACES.Hair = the round-1 Hair folder)
Gen.Replaces = nil

local clamp, lerp, smoothstep, num = Kit.clamp, Kit.lerp, Kit.smoothstep, Kit.num
local abs, min, max, floor, sin, cos, pi = math.abs, math.min, math.max, math.floor, math.sin, math.cos, math.pi

local TYPES = { Straight = true, Wavy = true, Curly = true, Kinky = true, Coiled = true }
local CURLY = { Curly = true, Kinky = true, Coiled = true }
local COILY = { Kinky = true, Coiled = true }
-- the closest older style for an id without a recipe (mirrors Looks.HairStyleBase; data only)
local BASE = {
	["Taper Fade"] = "Low Fade", ["Textured Crop"] = "Crew Cut", ["Curly Top"] = "Short Curly",
	["Burst Fade"] = "Mid Fade", ["360 Waves"] = "Buzz Cut", ["Box Braids"] = "Braids",
}

------------------------------------------------------------------------
-- Shared pieces of the recipes
------------------------------------------------------------------------
-- the region above a fade's top line (where the top hair grows), soft
local function topRegion(y0, y1)
	return function(x, y, z, da, c)
		return smoothstep(y0, y1, y) * smoothstep(0.4, 0.8, c)
	end
end

-- short top clumps: the visible top of a short cut, many small tapered clumps shingled over a thin
-- under-layer shell (a soft broken silhouette instead of a helmet); curls / coils by type
local function shortTop(H, spec)
	local S = H.S
	local ht = H.htype
	local top = spec.top or 0.015
	if CURLY[ht] then
		return Parts.ShortCurls(H, spec)
	end
	local flow = Kit.Flow(S, spec.flow or "forward", spec.flowOpts)
	local len0, len1 = spec.len[1], spec.len[2]
	local rise = spec.rise or 0.016
	return Parts.Clumps(H, {
		n = spec.n or 260, seed = 3, sides = H.lod == "full" and 4 or 3,
		accept = spec.accept or topRegion(0.2, 0.34),
		len = function(r)
			return lerp(len0, len1, r[9]) * (spec.lenK and spec.lenK(r) or 1)
		end,
		w = spec.w or 0.017, h = spec.h or 0.0075, flow = flow, lift = (spec.lift or 0.3) + 0.15, stick = spec.stick or 0.3,
		grav = 0, stiff = spec.stiff or 0.6, free = 2,
		off = function(u)
			return top * 0.75 + u * rise
		end,
		wave = ht == "Wavy" and { amp = 0.006, lam = 0.06 } or nil,
		twist = 0.8, jitter = spec.jitter or { amp = 0.22, freq = 9 }, tips = spec.tips or 0.25, layerK = 1, maxRings = 6, taper = 0.35,
	})
end

------------------------------------------------------------------------
-- Recipes: function(H) builds the pieces; H.htype is the hair type
------------------------------------------------------------------------
local R = {}
local fill

local SHORT = {
	["Buzz Cut"] = { top = 0.0045, side = 0.004, clumps = false, density = 0.62 },
	["Crew Cut"] = { side = 0.011, len = { 0.05, 0.085 }, flow = "forward", lift = 0.45 },
	["Caesar Cut"] = { side = 0.014, len = { 0.05, 0.075 }, flow = "forward", lift = 0.12, stick = 0.75, all = true },
	["Fade"] = { side = 0.014, fade = "fade", len = { 0.05, 0.09 }, flow = "forward", lift = 0.35 },
	["Low Fade"] = { side = 0.014, fade = "low", len = { 0.05, 0.09 }, flow = "forward", lift = 0.35 },
	["Mid Fade"] = { side = 0.014, fade = "mid", len = { 0.05, 0.09 }, flow = "forward", lift = 0.35 },
	["High Fade"] = { side = 0.014, fade = "high", len = { 0.055, 0.1 }, flow = "forward", lift = 0.4 },
	["Taper Fade"] = { side = 0.013, fade = "taper", len = { 0.05, 0.085 }, flow = "forward", lift = 0.35 },
	["Burst Fade"] = { side = 0.015, fade = "burst", len = { 0.06, 0.11 }, flow = "forward", lift = 0.4 },
	["Textured Crop"] = { side = 0.013, fade = "mid", len = { 0.07, 0.12 }, flow = "forward", lift = 0.2,
		jitter = { amp = 0.5, freq = 8 }, stick = 0.5 },
	["Modern Athlete"] = { side = 0.013, fade = "high", len = { 0.08, 0.14 }, flow = "back", lift = 0.65, stick = 0.3 },
	["360 Waves"] = { top = 0.008, side = 0.006, clumps = false, pattern = "waves", density = 0.9 },
}
local FADE_TOP = { low = 0.15, mid = 0.24, high = 0.32, fade = 0.24, taper = 0.12, burst = 0.25 }

local function shortCut(H)
	local sp = SHORT[H.style]
	local L = H.len
	local grow = H.grow
	local hasTop = sp.clumps ~= false
	-- under the top clumps the shell is a thin dark under-layer; a clipper cut is the shell alone
	local top = hasTop and (0.014 + 0.008 * L) or (sp.top + 0.006 * L + 0.012 * grow)
	local side = sp.side + 0.008 * grow
	local fadeTop = FADE_TOP[sp.fade or ""] or 0.2
	local coily = COILY[H.htype] and hasTop
	if coily then
		-- short coily hair: a springy layer as thick as the hair is long, pebbled with coil clusters
		top = 0.026 + 0.03 * L + 0.01 * grow
	end
	local seed = H.seed % 1000
	local clipper = not hasTop
	local full = H.lod == "full"
	Parts.Cap(H, {
		top = top, side = side, fade = sp.fade, density = sp.density and lerp(sp.density, 1, grow * 0.7) or 1,
		pattern = sp.pattern or (COILY[H.htype] and (hasTop and "coil" or "stubble") or (hasTop and "strands" or "stubble")),
		flow = sp.pattern == "waves" and "down" or (sp.flow or "whorl"),
		grain = hasTop and 1 or 0.75, part = hasTop and H.partX or nil, capT = coily and 0.6 or (hasTop and 0.35 or 0.8),
		waveLam = 0.052, reflectance = sp.pattern == "waves" and 0.03 or nil, edge = hasTop and 0.07 or 0.05,
		-- clipper hair is too short for strands: no streaks, a speckled grain
		streak = (clipper and sp.pattern ~= "waves") and 0 or nil,
		gridNormals = coily or clipper,
		extra = (clipper and sp.pattern ~= "waves") and function(x, y, z, c)
			-- clipper stubble: a fine relief catching the light unevenly (no smooth shell)
			return (0.0016 + 0.002 * grow) * (Kit.RNoise(x, y, z, 26, seed, 1) + 0.5 * Kit.RNoise(x, y, z, 55, seed + 1, 2)) * c
		end or coily and function(x, y, z, c)
			local b = 0.006 * MeshKit.Noise(x * 22, y * 22, z * 22, seed) + 0.003 * MeshKit.Noise(x * 50, y * 50, z * 50, seed + 1)
			return b * smoothstep(0.5, 0.9, c) * smoothstep(0.1, 0.3, y)
		end or (sp.pattern == "waves" and function(x, y, z, c)
			-- brushed waves are ridges in the hair itself
			local wx, wy, wz = Kit.Whorl(H.S)
			local dx, dy, dz = x - wx, y - wy, z - wz
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			return 0.0022 * math.sin((d + 0.012 * math.sin(math.atan2(dx, dz) * 3)) / 0.052 * 2 * pi) * c
		end) or nil,
		cols = (coily and full and 56) or (clipper and (full and 84 or (H.lod == "medium" and 44 or nil))) or nil,
		rows = (coily and full and 26) or (clipper and (full and 38 or (H.lod == "medium" and 18 or nil))) or nil,
	})
	if clipper and grow > 0.4 and H.lod ~= "low" then
		-- a clipper cut left to grow becomes a short natural cut: tufts appear over the crown
		shortTop(H, { top = top, len = { 0.035 + 0.03 * grow, 0.06 + 0.04 * grow }, flow = "whorl", lift = 0.3, n = floor(200 * (grow - 0.3)),
			accept = topRegion(0.1, 0.25) })
	end
	if coily and H.lod ~= "low" then
		local fadeTop2 = FADE_TOP[sp.fade or ""] or 0.2
		local acc = function(x, y, z, da, c)
			return smoothstep(fadeTop2 - 0.04, fadeTop2 + 0.06, y) * smoothstep(0.6, 0.95, c)
		end
		local layer = function(x, y, z)
			return H.S.f(x, y, z) - top
		end
		Parts.Fuzz(H, { n = 220, vol = layer, accept = acc, len = 0.022 + 0.02 * L, zig = 0.004, share = 0.4 })
		Parts.CoilHalo(H, { n = 90, vol = layer, accept = acc, radius = 0.009, tube = 0.0045 })
		return
	end
	if hasTop and H.lod ~= "low" then
		shortTop(H, {
			top = top, len = { sp.len[1] * (0.8 + 0.6 * L), sp.len[2] * (0.8 + 0.6 * L) }, flow = sp.flow, lift = sp.lift,
			stick = sp.stick, jitter = sp.jitter, accept = sp.all and function(_, y, _, _, c)
				return smoothstep(0.45, 0.85, c) * smoothstep(-0.05, 0.12, y)
			end or topRegion(fadeTop - 0.07, fadeTop + 0.05),
		})
	end
end
for id in pairs(SHORT) do
	R[id] = shortCut
end

-- coherent wave phase: neighbouring clumps wave together (sections of hair), with a little scatter
local function wavePhase(H)
	local seed = H.seed % 1000
	return function(r)
		-- the waves of neighbouring locks line up (hair waves in sections), drifting slowly across the head
		return MeshKit.Noise(r[1] * 1.6, r[2] * 1.6, r[3] * 1.6, seed) * 1.6 + r[9] * 0.35
	end
end

-- long, layered hair (straight / wavy); curly and coily types are routed to their own recipes
R["Long Hair"] = function(H)
	local S = H.S
	local L = H.len
	local px = H.partX or 0
	local flow = Kit.Flow(S, "part", { x = px })
	local vol = H.volume
	S.guardFace = true
	Parts.Cap(H, { top = 0.02, side = 0.018, pattern = "strands", flow = "part", flowOpts = { x = px }, part = px, capT = 0.15,
		cols = H.lod == "full" and 40 or nil, rows = H.lod == "full" and 17 or nil, streak = 0.7, material = "SmoothPlastic" })
	local hangLen = 0.55 + 0.9 * L
	local function len(r)
		-- layers: the back longest, the face-framing front shorter
		local front = 1 - smoothstep(0.4, 1.6, r[7])
		return hangLen * (1 - 0.3 * front) * (0.9 + 0.2 * r[9])
	end
	local wavy = H.htype == "Wavy"
	-- broad S-waves (sampled by enough rings per wavelength: an under-sampled wave turns into a zigzag)
	local wave = wavy and { amp = 0.028, lam = 0.42, rise = 0.25, phase = wavePhase(H) } or nil
	-- inner fill: a continuous two-sided sheet from temple to temple round the back
	Parts.Curtain(H, {
		cols = 22, az0 = -2.55, az1 = 2.55, th = function(az)
			return 0.55 + 0.25 * (abs(az) / pi)
		end, len = function(az, rnd)
			-- the roots sit high on the crown: the strand first runs over the skull (~0.45), then hangs
			local front = smoothstep(1.6, 2.5, abs(az))
			return (0.45 - 0.1 * front + hangLen * (0.84 - 0.25 * front)) * (0.95 + 0.1 * rnd)
		end, flow = flow, off = function(u)
			return 0.016 + 0.008 * u
		end, stick = 0.95, grav = 1, stiff = 0.2, shade = 0.8, hang = { prefix = "HairClump" }, wave = wave, bodyOff = 0.03,
		half = H.lod == "low" and 0.012 or 0.006, rings0 = wavy and 18 or 14,
	})
	-- outer layer: wide locks of hair overlapping into a full mass, lifted for volume
	Parts.Clumps(H, {
		n = 44, seed = 2, len = function(r)
			return len(r) * (0.86 + 0.18 * r[9])
		end, w = 0.07, h = 0.014, flow = flow, lift = 0.1 + 0.1 * vol, stick = 0.88, grav = 1, stiff = 0.25,
		off = function(u)
			return 0.034 + 0.02 * vol + 0.016 * u
		end, wave = wave, twist = 0.4, layerK = 1.0, hang = { prefix = "HairClump" }, tips = 0.7, maxRings = wavy and 17 or 12,
		bodyOff = 0.05, share = 0.85, taper = 0.72, tipW = 0.3, flat = 0.45,
	})
	Parts.Flyaways(H, { n = 14, len = function(r)
		return 0.12 + 0.12 * r[9]
	end, flow = flow })
	S.guardFace = false
end

R["Slick Back"] = function(H)
	local S = H.S
	local L = H.len
	local flow = Kit.Flow(S, "back")
	Parts.Cap(H, { top = 0.02, side = 0.016, pattern = "strands", flow = "back", grain = 0.8, capT = 0.45, contrast = 1.25, reflectance = 0.04 })
	local len = 0.3 + 0.45 * L
	Parts.Clumps(H, {
		n = 80, seed = 4, len = function(r)
			return len * (0.85 + 0.3 * r[9]) * (1 - 0.35 * smoothstep(1.4, 2.6, r[7]))
		end, w = 0.024, h = 0.0065, flow = flow, lift = 0, stick = 1, grav = 1, stiff = 0.15, free = 0.95,
		off = function(u)
			return 0.017 + 0.004 * u
		end, twist = 0.2, layerK = 1, material = "SmoothPlastic", reflectance = 0.05, maxRings = 10, taper = 0.6,
		hang = L > 0.55 and { prefix = "HairClump" } or nil,
	})
end

R["Messy Hair"] = function(H)
	local S = H.S
	local L = H.len
	local flow = Kit.Flow(S, "whorl")
	Parts.Cap(H, { top = 0.036, side = 0.028, pattern = "strands", flow = "whorl", capT = 0.4 })
	Parts.Clumps(H, {
		n = 105, seed = 5, len = function(r)
			return (0.12 + 0.18 * L) * (0.7 + 0.6 * r[9]) * (1 - 0.3 * smoothstep(1.2, 2.6, r[7]))
		end, w = 0.03, h = 0.009, flow = flow, lift = 0.4, stick = 0.3, grav = 0.25, stiff = 0.45,
		off = function(u)
			return 0.03 + 0.02 * u
		end, wave = H.htype == "Wavy" and { amp = 0.01, lam = 0.16, phase = wavePhase(H) } or nil, twist = 0.5,
		jitter = { amp = 0.45, freq = 5 }, tips = 0.6, maxRings = 8,
	})
	Parts.Flyaways(H, { n = 26, len = function(r)
		return 0.08 + 0.1 * r[9]
	end, flow = flow })
end

------------------------------------------------------------------------
-- Curly / coily volumes and textures
------------------------------------------------------------------------
-- how much of its length coily hair shows (shrinkage), by type
local SHRINK = { Straight = 1, Wavy = 0.9, Curly = 0.75, Coiled = 0.6, Kinky = 0.5 }

-- the scalp offset by `t` as a volume (a uniform layer of coily hair), optionally only where mask(x, y, z) > 0
local function layerVol(S, t, mask)
	local f = S.f
	return function(x, y, z)
		local d = f(x, y, z) - t
		if mask then
			d = max(d, -mask(x, y, z))
		end
		return d
	end
end

-- bounce groups for coils / curls: top, left, right, back (full), one group at medium
local function bounceKey(H)
	return function(r)
		if H.lod ~= "full" then
			return "HairCurl01"
		end
		local x, y, z = r[1], r[2], r[3]
		if y > 0.42 then
			return "HairCurl01"
		elseif z > 0.18 then
			return "HairCurl02"
		elseif x < 0 then
			return "HairCurl03"
		end
		return "HairCurl04"
	end
end

-- a short coily cut's shell: a layer of tight coils with a pebbled surface and coil texture
local function coilyCap(H, spec)
	local S = H.S
	local th = spec.thickness
	return Parts.Volume(H, {
		vol = layerVol(S, th, spec.mask), edge = spec.edge or 0.05, bump = spec.bump or 0.012, bumpFreq = 12,
		fade = spec.fade, top = spec.top or 0.012, side = spec.side or 0.01, region = spec.region, shaved = spec.shaved,
		pattern = "coil", material = "Fabric", capT = 0.6, cols = spec.cols or (H.lod == "full" and 52 or nil),
		rows = spec.rows or (H.lod == "full" and 24 or nil), part = spec.part,
	})
end

------------------------------------------------------------------------
-- More recipes
------------------------------------------------------------------------
-- a dark fill sheet behind hanging locs / twists / braids (temple to temple round the back): gaps between the
-- strands show hair, not the neck. Swings with the strands' groups.
fill = function(H, flow, len, prefix, shade)
	return Parts.Curtain(H, {
		cols = 16, rings0 = 10, az0 = -2.3, az1 = 2.3, th = function(az)
			return 0.7 + 0.35 * (abs(az) / pi)
		end, len = function(az, rnd)
			return len * (0.8 + 0.2 * rnd) * (1 - 0.35 * smoothstep(1.4, 2.3, abs(az)))
		end, flow = flow, off = function(u)
			return 0.022 + 0.01 * u
		end, stick = 0.9, grav = 1, stiff = 0.2, shade = shade, hang = { prefix = prefix }, material = "Plastic", half = 0.008,
	})
end
R["Afro"] = function(H)
	local S = H.S
	local L = H.len
	local ht = COILY[H.htype] and H.htype or (H.htype == "Curly" and "Curly" or "Kinky")
	local size = 0.13 + 0.24 * L * (0.55 + 0.45 * SHRINK[ht]) + 0.06 * H.volume
	local cy, cz = 0.16 + 0.3 * size, 0.1 + 0.22 * size
	local rx, ry, rz = 0.41 + size, 0.42 + size * 0.95, 0.47 + size * 0.85
	local vol = function(x, y, z)
		local dx, dy, dz = x / rx, (y - cy) / ry, (z - cz) / rz
		return (math.sqrt(dx * dx + dy * dy + dz * dz) - 1) * min(rx, ry, rz)
	end
	local full = H.lod == "full"
	Parts.Volume(H, {
		vol = vol, edge = 0.08, frontEdge = 0.2, bump = ht == "Curly" and 0.045 or 0.04, bumpFreq = ht == "Curly" and 5 or 6, tmax = 0.7,
		top = 0.02, side = 0.02, pattern = ht == "Curly" and "curl" or "coil", material = "Fabric", capT = 0.55, grain = H.lod == "full" and 1.9 or 1.5,
		cols = full and 64 or (H.lod == "medium" and 40 or 20), rows = full and 30 or (H.lod == "medium" and 17 or 9),
	})
	if ht == "Curly" then
		Parts.Curls(H, { n = 70, vol = vol, accept = function(x, y, z, da, c)
			return smoothstep(0.7, 0.95, c)
		end, flow = Kit.Flow(S, "whorl"), lift = 1, stick = 0, grav = 0.1, stiff = 0.8, len = function(r)
			return 0.06 + 0.05 * r[9]
		end, radius = 0.03, tube = 0.011, off = function(u, r)
			return Parts.DepthIn(vol, r[1], r[2], r[3], r[4], r[5], r[6], 0.7) - 0.03
		end, bounce = bounceKey(H), share = 0.8 })
	else
		Parts.Fuzz(H, { n = 320, vol = vol, len = 0.05, zig = 0.007, share = 0.4 })
		Parts.CoilHalo(H, { n = 150, vol = vol, bounce = bounceKey(H) })
	end
	H.fx = { kind = "bounce", stiff = 0.7, mass = 1.4 }
end

R["High Top"] = function(H)
	local S = H.S
	local L = H.len
	local yTop = 0.66 + 0.32 * L * (0.6 + 0.4 * SHRINK[H.htype]) + 0.04 * H.volume
	local yb = 0.18
	local hy = (yTop - yb) / 2
	local vol = function(x, y, z)
		-- a flat-topped block with rounded edges, a little narrower at the top
		local k = smoothstep(yb, yTop, y)
		local hx, hz = 0.44 - 0.03 * k, 0.5 - 0.03 * k
		local qx, qy, qz = abs(x) - hx + 0.09, abs(y - (yb + hy)) - hy + 0.09, abs(z - 0.04) - hz + 0.09
		local ox, oy, oz = max(qx, 0), max(qy, 0), max(qz, 0)
		return math.sqrt(ox * ox + oy * oy + oz * oz) + min(max(qx, max(qy, qz)), 0) - 0.09
	end
	local full = H.lod == "full"
	Parts.Volume(H, {
		vol = vol, edge = 0.05, frontEdge = 0.06, bump = 0.028, bumpFreq = 7, tmax = 0.8, fade = "high", top = 0.016, side = 0.012,
		pattern = "coil", material = "Fabric", capT = 0.55, grain = H.lod == "full" and 1.9 or 1.5,
		cols = full and 64 or (H.lod == "medium" and 40 or 20), rows = full and 32 or (H.lod == "medium" and 17 or 9),
	})
	local acc = function(x, y, z, da, c)
		return smoothstep(0.3, 0.42, y) * smoothstep(0.6, 0.9, c)
	end
	Parts.Fuzz(H, { n = 240, vol = vol, accept = acc, len = 0.04, zig = 0.006, share = 0.45 })
	Parts.CoilHalo(H, { n = 90, vol = vol, accept = acc, bounce = bounceKey(H) })
	H.fx = { kind = "bounce", stiff = 0.8, mass = 1.3 }
end

R["Short Curly"] = function(H)
	local S = H.S
	local L = H.len
	if COILY[H.htype] then
		local t = 0.045 + 0.06 * L * SHRINK[H.htype] + 0.015 * H.volume
		coilyCap(H, { thickness = t, bump = 0.016 })
		Parts.Fuzz(H, { n = 260, vol = layerVol(S, t), len = 0.035, zig = 0.006, share = 0.4 })
		Parts.CoilHalo(H, { n = 110, vol = layerVol(S, t), bounce = bounceKey(H) })
	else
		-- a dark, lumpy under-volume of curls, ringlets over it
		local t = 0.03 + 0.03 * L
		Parts.Volume(H, { vol = layerVol(S, t), edge = 0.05, bump = 0.024, bumpFreq = 7, top = 0.02, side = 0.02, pattern = "curl",
			material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
		Parts.Curls(H, { n = 80, flow = Kit.Flow(S, "down"), lift = 0.55, stick = 0.2, grav = 0.25, stiff = 0.5,
			len = function(r)
				return (0.08 + 0.07 * r[9]) * (0.8 + 0.6 * L)
			end, radius = 0.03, tube = 0.0115, off = function()
				return t * 0.7
			end, bounce = bounceKey(H) })
	end
	H.fx = { kind = "bounce", stiff = 0.55, mass = 1.1 }
end

R["Curly Top"] = function(H)
	local S = H.S
	local L = H.len
	local topMask = function(x, y, z)
		return (y - 0.3) * 4
	end
	local acc = function(x, y, z, da, c)
		return smoothstep(0.3, 0.4, y) * smoothstep(0.6, 0.9, c)
	end
	if COILY[H.htype] then
		local t = 0.06 + 0.08 * L
		coilyCap(H, { thickness = t, mask = topMask, fade = "high", bump = 0.016, edge = 0.04 })
		Parts.Fuzz(H, { n = 220, vol = layerVol(S, t, topMask), accept = acc, len = 0.035, zig = 0.006, share = 0.4 })
		Parts.CoilHalo(H, { n = 90, vol = layerVol(S, t, topMask), accept = acc, bounce = bounceKey(H) })
	else
		local t = 0.035 + 0.04 * L
		Parts.Volume(H, { vol = layerVol(S, t, topMask), edge = 0.04, bump = 0.022, bumpFreq = 7, fade = "high", top = 0.016, side = 0.012,
			pattern = "curl", material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
		Parts.Curls(H, { n = 75, flow = Kit.Flow(S, "forward"), lift = 0.7, stick = 0.15, grav = 0.1, stiff = 0.6,
			accept = acc, len = function(r)
				return (0.09 + 0.07 * r[9]) * (0.8 + 0.6 * L)
			end, radius = 0.03, tube = 0.0115, off = function()
				return t * 0.75
			end, bounce = bounceKey(H) })
	end
	H.fx = { kind = "bounce", stiff = 0.55, mass = 1.1 }
end

-- long ringlets (curly) or a long coily volume (coily / afro-textured): Long Curly and the long styles on
-- curly / coily hair
local function longCurly(H)
	local S = H.S
	local L = H.len
	S.guardFace = true
	if COILY[H.htype] then
		-- coils shrink: the length becomes a big rounded volume, deeper at the back and sides
		local size = 0.12 + 0.22 * L * SHRINK[H.htype] + 0.05 * H.volume
		local drop = 0.1 + 0.35 * L * SHRINK[H.htype]
		local vol = function(x, y, z)
			local dx, dy, dz = x / (0.42 + size), (y - 0.1 + 0.25 * drop) / (0.47 + size + drop * 0.6), (z - 0.1 - 0.15 * size) / (0.5 + size * 0.8)
			return (math.sqrt(dx * dx + dy * dy + dz * dz) - 1) * 0.45
		end
		local full = H.lod == "full"
		Parts.Volume(H, { vol = vol, edge = 0.08, frontEdge = 0.2, bump = 0.04, bumpFreq = 6, tmax = 0.8, top = 0.02, side = 0.02,
			pattern = "coil", material = "Fabric", capT = 0.55, grain = H.lod == "full" and 1.9 or 1.5, cols = full and 64 or (H.lod == "medium" and 40 or 20),
			rows = full and 30 or (H.lod == "medium" and 17 or 9) })
		Parts.Fuzz(H, { n = 300, vol = vol, len = 0.05, zig = 0.007, share = 0.4 })
		Parts.CoilHalo(H, { n = 140, vol = vol, bounce = bounceKey(H) })
		H.fx = { kind = "bounce", stiff = 0.65, mass = 1.4 }
		S.guardFace = false
		return
	end
	local hangLen = (0.45 + 0.85 * L) * SHRINK.Curly
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local t = 0.035 + 0.02 * L
	Parts.Volume(H, { vol = layerVol(S, t), edge = 0.05, bump = 0.022, bumpFreq = 7, top = 0.02, side = 0.02, pattern = "curl",
		material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
	-- a dark curly mass behind the hanging ringlets, down to where they end (the roots sit high on the head:
	-- the strand first runs over the skull)
	Parts.Curtain(H, { cols = 20, az0 = -2.45, az1 = 2.45, th = function(az)
		return 0.7 + 0.3 * (abs(az) / pi)
	end, len = function(az, rnd)
		return 0.36 + hangLen * (0.95 - 0.3 * smoothstep(1.5, 2.4, abs(az)))
	end, flow = flow, off = function(u)
		return t + 0.012 + 0.05 * u
	end, shade = 0.6, hang = { prefix = "HairCurl" }, material = "Fabric", half = 0.02,
		wave = { amp = 0.035, lam = 0.11, rise = 0.1 } })
	-- short curls on the crown
	Parts.Curls(H, { n = 40, flow = Kit.Flow(S, "down"), lift = 0.55, stick = 0.2, grav = 0.25, stiff = 0.5, accept = function(x, y, z, da, c)
		return smoothstep(0.25, 0.4, y) * smoothstep(0.6, 0.9, c)
	end, len = function(r)
		return 0.08 + 0.06 * r[9]
	end, radius = 0.03, tube = 0.0115, off = function()
		return t * 0.7
	end, share = 0.3 })
	-- long ringlets from round the lower head, hanging to the shoulders
	Parts.Curls(H, { n = 60, flow = flow, lift = 0.2, stick = 0.5, grav = 1, stiff = 0.35, accept = function(x, y, z, da, c)
		return (1 - smoothstep(0.22, 0.34, y)) * smoothstep(0.7, 1.1, da) * smoothstep(0.5, 0.9, c)
	end, len = function(r)
		return hangLen * (0.75 + 0.35 * r[9])
	end, radius = 0.03, tube = 0.0165, off = function(u)
		return t + 0.025 + 0.045 * u
	end, hang = { prefix = "HairCurl" }, pitch = 1.75 })
	H.fx = { kind = "swing", stiff = 0.45, mass = 1.0 }
	S.guardFace = false
end
R["Long Curly"] = longCurly

-- locs: Dreadlocks (long, hanging, swinging in groups) and Short Dreads (springing up and out)
R["Dreadlocks"] = function(H)
	local S = H.S
	local L = H.len
	S.guardFace = true
	local grown = H.growth > 0.4
	-- new growth at the roots reads as a soft coily halo on the shell
	Parts.Cap(H, { top = 0.024, side = 0.02, pattern = grown and "coil" or "strands", flow = "down", capT = 0.3, material = "Plastic" })
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local hang = clamp(0.45 + 0.8 * L, 0.3, 1.4)
	H.sparseTop = true
	fill(H, flow, hang * 0.85, "HairLoc", 0.5)
	Parts.Tubes(H, { n = 52, minN = 10, section = "loc", r = 0.042, flow = flow, lift = 0.4, stick = 0.45, grav = 1, stiff = 0.4, sides = 5, ringsPer = 15,
		lodK = { full = 1, medium = 0.5, low = 0.3 }, len = function(r)
			local front = 1 - smoothstep(0.4, 1.4, r[7])
			return hang * (0.85 + 0.25 * r[9]) * (1 - 0.3 * front)
		end, hang = { prefix = "HairLoc" }, tip = "dome" })
	H.fx = { kind = "swing", stiff = 0.6, mass = 1.6 }
	S.guardFace = false
end

R["Short Dreads"] = function(H)
	local S = H.S
	local L = H.len
	Parts.Cap(H, { top = 0.024, side = 0.02, pattern = H.growth > 0.4 and "coil" or "strands", flow = "down", capT = 0.3, material = "Plastic" })
	local flow = Kit.Flow(S, "whorl")
	Parts.Tubes(H, { n = 56, minN = 12, section = "loc", r = 0.034, flow = flow, lift = 0.75, stick = 0.15, grav = 0.55, stiff = 0.6,
		free = 0.2, lodK = { full = 1, medium = 0.45, low = 0.28 }, len = function(r)
			return (0.13 + 0.12 * r[9]) * (0.8 + 0.6 * L)
		end, ringsPer = 22, tip = "dome", piece = H.lod == "low" and "HairTop" or nil })
	H.fx = { kind = "bounce", stiff = 0.75, mass = 1.3 }
end

R["Twists"] = function(H)
	local S = H.S
	local L = H.len
	S.guardFace = true
	Parts.Cap(H, { top = 0.02, side = 0.018, pattern = "coil", flow = "down", capT = 0.3, material = "Plastic" })
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local hang = 0.22 + 0.55 * L
	H.sparseTop = true
	fill(H, flow, hang * 0.8, "HairTwist", 0.45)
	Parts.Tubes(H, { n = 52, minN = 10, section = "twist", period = 0.075, r = 0.038, flow = flow, lift = 0.4, stick = 0.45, sides = H.lod == "full" and 4 or nil,
		grav = 0.9, stiff = 0.45, lodK = { full = 1, medium = 0.45, low = 0.28 }, len = function(r)
			return hang * (0.85 + 0.3 * r[9])
		end, hang = { prefix = "HairTwist" }, tip = "dome" })
	H.fx = { kind = "swing", stiff = 0.55, mass = 1.3 }
	S.guardFace = false
end

-- braids (fewer, thicker) and box braids (many, thinner, square partings on the scalp)
local function braids(H, box)
	local S = H.S
	local L = H.len
	S.guardFace = true
	local rows, region = Parts.RowLayout(H, box and 9 or 5, 0.08)
	local boxRegion = region
	if box then
		-- square sections: the rows' partings plus partings across them
		boxRegion = function(x, y, z, da)
			local b = math.atan2(z - 0.05, y - S.cy + 0.25)
			local f = abs((b / 0.3) - floor(b / 0.3 + 0.5))
			return region(x, y, z, da) * (1 - smoothstep(0.32, 0.42, f))
		end
	end
	Parts.Cap(H, { top = 0.016, side = 0.014, pattern = "strands", flow = "back", capT = 0.3, material = "Plastic",
		region = boxRegion, shaved = 0.45, density = 1 })
	local flow = Kit.Flow(S, "back")
	local hang = 0.4 + 0.85 * L
	H.sparseTop = true
	fill(H, Kit.Flow(S, "part", { x = 0 }), hang * 0.82, "HairBraid", 0.5)
	Parts.Tubes(H, { n = box and 30 or 16, minN = box and 10 or 6, section = "braid", period = box and 0.08 or 0.1,
		r = box and 0.03 or 0.05, flow = flow, lift = 0.15, stick = 0.7, grav = 1, stiff = 0.3, sides = box and H.lod == "full" and 4 or nil,
		lodK = { full = 1, medium = 0.5, low = 0.32 }, len = function(r)
			local front = 1 - smoothstep(0.4, 1.4, r[7])
			return hang * (0.9 + 0.2 * r[9]) * (1 - 0.2 * front)
		end, hang = { prefix = "HairBraid" }, tip = "dome", accept = function(x, y, z, da, c)
			return smoothstep(0.5, 0.9, c)
		end })
	H.fx = { kind = "swing", stiff = 0.45, mass = 1.3 }
	S.guardFace = false
end
R["Braids"] = function(H)
	braids(H, false)
end
R["Box Braids"] = function(H)
	braids(H, true)
end

R["Cornrows"] = function(H)
	local S = H.S
	local L = H.len
	local n = H.lod == "low" and 6 or (H.lod == "medium" and 7 or floor(6 + 4 * H.density + 0.5))
	local _, region = Parts.RowLayout(H, n)
	Parts.Cap(H, { top = 0.01, side = 0.008, pattern = "strands", flow = "back", capT = 0.35, material = "Plastic", region = region,
		shaved = 0.2, density = 1, hairline = H.hairline == "Natural" and "Straight" or H.hairline })
	local hang = H.len * SHRINK[H.htype] - 0.4
	-- far away the braided tails are not worth their triangles: the rows alone read as cornrows
	local tails = hang > 0 and H.lod ~= "low"
	Parts.Cornrows(H, { n = n, r = 0.027 * (0.85 + 0.3 * H.thick), period = 0.085, tails = tails, tail = function(i)
		return tails and (0.12 + 0.6 * hang) or 0
	end })
	if H.tails then
		Parts.Hang(H, H.tails, "braid", 0.075, "HairBraid")
	end
	H.fx = { kind = "swing", stiff = 0.5, mass = 1.2 }
end

R["Ponytail"] = function(H)
	local S = H.S
	local L = H.len
	local tx, ty, tz = S.ray(0, 0.42, 0.9, 0.035)
	local tie = { tx, ty, tz }
	local flow = Kit.Flow(S, "tie", { p = tie })
	Parts.Cap(H, { top = 0.012, side = 0.012, pattern = "strands", flow = "tie", capT = 0.4, streak = 0.6,
		material = H.htype == "Straight" and "SmoothPlastic" or "Plastic" })
	if H.lod ~= "low" then
		-- hair pulled back tight from the hairline into the tie
		Parts.Clumps(H, { n = 110, seed = 9, sides = H.lod == "full" and 4 or 3, flow = flow, lift = 0, stick = 1, grav = 0, stiff = 0.2,
			free = 2, glue = true, len = function(r)
				local dx, dy, dz = tie[1] - r[1], tie[2] - r[2], tie[3] - r[3]
				return math.sqrt(dx * dx + dy * dy + dz * dz) * 1.08
			end, w = 0.026, h = 0.006, off = function(u)
				return 0.014 + 0.004 * u
			end, bend = function(pts)
				-- stop at the tie: never run past it
				local best, bi = 1e9, #pts
				for i, p in ipairs(pts) do
					local dx, dy, dz = tie[1] - p[1], tie[2] - p[2], tie[3] - p[3]
					local d = dx * dx + dy * dy + dz * dz
					if d < best then
						best, bi = d, i
					end
				end
				return table.move(pts, 1, math.max(bi, 2), 1, {})
			end, maxRings = 10, taper = 0.85, twist = 0.2, layerK = 1, share = 0.42 })
	end
	local hang = 0.4 + 0.9 * L
	local pal = H.pal
	local lum = pal.lum
	if COILY[H.htype] then
		-- coily hair gathers into a puff
		local pr = 0.1 + 0.12 * L * SHRINK[H.htype]
		local cx, cy, cz = tie[1], tie[2] + 0.02, tie[3] + pr * 0.85
		local vol = function(x, y, z)
			local dx, dy, dz = x - cx, y - cy, z - cz
			return math.sqrt(dx * dx + dy * dy + dz * dz) - pr
		end
		local m = Parts.Piece(H, "HairTail01", { material = "Plastic", castShadow = true }).mesh
		local seed = H.seed % 1000
		MeshKit.Ellipsoid(m, cx, cy, cz, pr, pr, pr, { rings = H.lod == "full" and 16 or 8, sides = H.lod == "full" and 22 or 10,
			radial = function(dx, dy, dz)
				return 1 + 0.09 * MeshKit.Noise(dx * 3.5, dy * 3.5, dz * 3.5, seed) + 0.04 * MeshKit.Noise(dx * 9, dy * 9, dz * 9, seed + 1)
			end,
			color = function(x, y, z, dx, dy, dz)
				local r, g, b = pal.at(0.5, 0.7, x)
				local k = 0.75 + 0.35 * smoothstep(-0.5, 0.9, MeshKit.Noise(x * 40, y * 40, z * 40, seed + 2))
				return r * k, g * k, b * k
			end })
		MeshKit.ComputeNormals(m)
		H.bounce = H.bounce or {}
		H.bounce.HairTail01 = true
		H.fx = { kind = "bounce", stiff = 0.6, mass = 1.2 }
	else
		Parts.PonyTail(H, { tie = tie, dir = { 0, -0.35, 1 }, len = hang * SHRINK[H.htype], n = 44, r0 = 0.075, w = 0.055, h = 0.014,
			wave = (H.htype == "Wavy" or H.htype == "Curly") and { amp = H.htype == "Curly" and 0.04 or 0.025, lam = H.htype == "Curly" and 0.1 or 0.26 } or nil,
			tieColor = lum > 0.22 and { pal.base[1] * 0.4, pal.base[2] * 0.4, pal.base[3] * 0.4 } or { 0.24, 0.23, 0.26 } })
		H.fx = { kind = "swing", stiff = H.htype == "Straight" and 0.2 or 0.3, mass = 1.0 }
	end
	H.hideTail = true
end

-- shaved sides: the region a mohawk / undercut keeps long
local function stripRegion(w)
	return function(x, y, z, da)
		return 1 - smoothstep(w, w + 0.035, abs(x))
	end
end
local function topOnly(ySide, yBack)
	return function(x, y, z, da)
		local yl = lerp(ySide, yBack, smoothstep(1.7, 2.8, da))
		return smoothstep(yl - 0.008, yl + 0.008, y)
	end
end

R["Mohawk"] = function(H)
	local S = H.S
	local L = H.len
	local strip = stripRegion(0.11)
	if CURLY[H.htype] then
		-- a frohawk / curly crest
		local t = 0.08 + 0.16 * L * SHRINK[H.htype]
		local mask = function(x, y, z)
			return (0.13 - abs(x)) * 6
		end
		coilyCap(H, { thickness = t, mask = mask, region = strip, shaved = 0.18, bump = 0.012, edge = 0.03 })
		Parts.CoilHalo(H, { n = 70, vol = layerVol(S, t, mask), accept = function(x, y, z, da, c)
			return (1 - smoothstep(0.08, 0.12, abs(x))) * smoothstep(0.6, 0.9, c)
		end, bounce = bounceKey(H) })
		H.fx = { kind = "bounce", stiff = 0.6, mass = 1.2 }
		return
	end
	Parts.Cap(H, { top = 0.02, side = 0.006, pattern = "strands", flow = "up", capT = 0.35, region = strip, shaved = 0.18 })
	local up = Kit.Flow(S, "up")
	Parts.Clumps(H, { n = 130, seed = 12, sides = H.lod == "full" and 4 or 3, flow = up, lift = 1, stick = 0, grav = 0.08, stiff = 0.85,
		free = 0, accept = function(x, y, z, da, c)
			return (1 - smoothstep(0.07, 0.11, abs(x))) * smoothstep(0.5, 0.9, c)
		end, len = function(r)
			return (0.12 + 0.2 * L) * (0.75 + 0.4 * r[9]) * (1 - 0.35 * smoothstep(1.8, 2.8, r[7]))
		end, w = 0.026, h = 0.011, off = function(u)
			return 0.015
		end, dir = function(r)
			-- the crest leans back a little and its fins converge into spikes
			return { r[4] - r[1] * 1.2, r[5] + 0.15, r[6] + 0.35 }
		end, twist = 0.4, maxRings = 8, taper = 0.4, tips = 0.4 })
	H.fx = { kind = "bounce", stiff = 0.85, mass = 0.9 }
end

R["Undercut"] = function(H)
	local S = H.S
	local L = H.len
	local region = topOnly(0.27, 0.14)
	if CURLY[H.htype] then
		if COILY[H.htype] then
			local t = 0.05 + 0.08 * L * SHRINK[H.htype]
			local mask = function(x, y, z)
				return (y - 0.29) * 5
			end
			coilyCap(H, { thickness = t, mask = mask, region = region, shaved = 0.2, bump = 0.009, edge = 0.03 })
			Parts.CoilHalo(H, { n = 70, vol = layerVol(S, t, mask), accept = function(x, y, z, da, c)
				return smoothstep(0.32, 0.4, y) * smoothstep(0.6, 0.9, c)
			end, bounce = bounceKey(H) })
		else
			Parts.Cap(H, { top = 0.03, side = 0.006, pattern = "strands", flow = "whorl", capT = 0.35, region = region, shaved = 0.2, material = "Plastic" })
			Parts.Curls(H, { n = 70, flow = Kit.Flow(S, "side", { dir = 1 }), lift = 0.6, stick = 0.2, grav = 0.2, stiff = 0.5,
				accept = function(x, y, z, da, c)
					return smoothstep(0.3, 0.36, y) * smoothstep(0.7, 0.95, c)
				end, len = function(r)
					return (0.1 + 0.08 * r[9]) * (0.8 + 0.6 * L)
				end, radius = 0.022, off = function()
					return 0.03
				end, bounce = bounceKey(H) })
		end
		H.fx = { kind = "bounce", stiff = 0.6, mass = 1.1 }
		return
	end
	Parts.Cap(H, { top = 0.026, side = 0.006, pattern = "strands", flow = "side", flowOpts = { dir = 1 }, capT = 0.35, region = region, shaved = 0.2 })
	local flow = Kit.Flow(S, "side", { dir = 1 })
	Parts.Clumps(H, { n = 95, seed = 13, flow = flow, lift = 0.45, stick = 0.7, grav = 0.3, stiff = 0.35, accept = function(x, y, z, da, c)
		return region(x, y, z, da) * smoothstep(0.7, 0.95, c)
	end, len = function(r)
		return (0.2 + 0.28 * L) * (0.8 + 0.35 * r[9])
	end, w = 0.034, h = 0.009, off = function(u)
		return 0.026 + 0.03 * u * (1 + H.volume * 0.5)
	end, wave = H.htype == "Wavy" and { amp = 0.012, lam = 0.2, phase = wavePhase(H) } or nil, twist = 0.5, maxRings = 10, tips = 0.5 })
	Parts.Flyaways(H, { n = 10, flow = flow, accept = function(x, y, z, da, c)
		return region(x, y, z, da) * c
	end })
	H.fx = { kind = "bounce", stiff = 0.6, mass = 0.9 }
end

R["Wolf Cut"] = function(H)
	local S = H.S
	local L = H.len
	if CURLY[H.htype] then
		return longCurly(H)
	end
	S.guardFace = true
	Parts.Cap(H, { top = 0.03, side = 0.026, pattern = "strands", flow = "whorl", capT = 0.3, streak = 0.6 })
	local whorl = Kit.Flow(S, "down")
	local wave = { amp = H.htype == "Wavy" and 0.022 or 0.01, lam = 0.2, phase = wavePhase(H), rise = 0.08 }
	-- the crown: short choppy layers lifted for volume
	Parts.Clumps(H, { n = 70, seed = 14, flow = whorl, lift = 0.45, stick = 0.35, grav = 0.35, stiff = 0.4,
		accept = function(x, y, z, da, c)
			return smoothstep(0.3, 0.42, y) * smoothstep(0.6, 0.9, c)
		end, len = function(r)
			return (0.14 + 0.12 * L) * (0.75 + 0.5 * r[9])
		end, w = 0.034, h = 0.01, off = function(u)
			return 0.03 + 0.03 * u
		end, wave = wave, twist = 0.8, jitter = { amp = 0.35, freq = 6 }, maxRings = 9, tips = 0.5 })
	-- the fringe: choppy, falling forward, stopping above the brows
	S.guardFace = false
	Parts.Clumps(H, { n = 22, seed = 15, flow = Kit.Flow(S, "forward"), lift = 0.25, stick = 0.6, grav = 0.6, stiff = 0.4, free = 0.6,
		accept = function(x, y, z, da, c)
			return (1 - smoothstep(0.5, 0.9, da)) * smoothstep(0.5, 0.9, c)
		end, len = function(r)
			return (0.12 + 0.08 * L) * (0.8 + 0.4 * r[9])
		end, w = 0.03, h = 0.009, off = function(u)
			return 0.03 + 0.01 * u
		end, bend = function(pts)
			-- never below the brows (nominal y ~0.13)
			for _, p in ipairs(pts) do
				if p[2] < 0.15 then
					p[2] = 0.15
				end
			end
			return pts
		end, twist = 0.6, maxRings = 8, tips = 0.5 })
	S.guardFace = true
	-- sides and back: longer layers that flick out at the ends (the mullet line)
	local flow = Kit.Flow(S, "down")
	Parts.Clumps(H, { n = 60, seed = 16, flow = flow, lift = 0.25, stick = 0.8, grav = 1, stiff = 0.3,
		accept = function(x, y, z, da, c)
			return smoothstep(0.9, 1.4, da) * smoothstep(0.5, 0.9, c) * (1 - smoothstep(0.38, 0.5, y))
		end, len = function(r)
			return (0.26 + 0.3 * L) * (0.8 + 0.4 * r[9])
		end, w = 0.036, h = 0.01, off = function(u)
			return 0.034 + 0.02 * u
		end, bend = function(pts)
			-- the ends flick outward
			local n = #pts
			for i = math.floor(n * 0.7), n do
				local u = (i - n * 0.7) / (n * 0.3)
				local p = pts[i]
				local ox, oy, oz = Kit.norm3(p[1], 0, p[3] - 0.05)
				p[1] += ox * 0.05 * u * u
				p[3] += oz * 0.05 * u * u
				p[2] += 0.02 * u * u
			end
			return pts
		end, wave = wave, hang = { prefix = "HairClump" }, twist = 0.6, maxRings = 12, tips = 0.5 })
	Parts.Flyaways(H, { n = 18, flow = whorl })
	H.fx = { kind = "swing", stiff = 0.3, mass = 0.9 }
	S.guardFace = false
end

------------------------------------------------------------------------
-- Generate
------------------------------------------------------------------------
local function resolve(look)
	local hair = type(look.hair) == "table" and look.hair or {}
	local style = type(hair.style) == "string" and hair.style or "Fade"
	local htype = TYPES[hair.type] and hair.type or "Straight"
	if not R[style] and style ~= "Bald" then
		style = BASE[style] or style
	end
	if not R[style] and style ~= "Bald" then
		style = "Fade"
	end
	return style, htype
end

-- the recipe a style uses on a hair type (curly / coily hair changes what a cut can be)
local function recipeFor(style, htype)
	if CURLY[htype] and (style == "Long Hair") then
		return longCurly
	elseif CURLY[htype] and style == "Messy Hair" then
		return R["Short Curly"]
	elseif (style == "Short Curly" or style == "Curly Top" or style == "Long Curly") and not CURLY[htype] then
		-- these cuts are curly by definition: straight / wavy hair gets loose curls
		return function(H)
			H.htype = "Curly"
			H.pal = Kit.Palette(H.look, "Curly")
			return R[style](H)
		end
	end
	return R[style]
end

-- HairCrown / HairFront for the server and tools (same numbers Generate returns)
local function baseLandmarks(H)
	local S = H.S
	local x, y, z = S.ray(0, 1, 0, 0.02)
	H.landmarks.HairCrown = { x, y, z }
	local _, height = Kit.Hairline(S, H.hairline, H.growth)
	local h = height(0)
	-- the front hairline centre: the scalp point at that height on the midline
	local lo, hi = 0.05, 1.6
	for _ = 1, 18 do
		local mid = (lo + hi) / 2
		local px, py, pz = S.ray(0, cos(mid), -sin(mid), 0)
		if py > h then
			lo = mid
		else
			hi = mid
		end
	end
	local fx, fy, fz = S.ray(0, cos(lo), -sin(lo), 0)
	H.landmarks.HairFront = { fx, fy, fz }
end

local function build(look, lod, ctx, style, htype, nScale)
	local H = Parts.Context(look, lod, ctx, style, htype)
	H.nScale = nScale
	if style == "Bald" then
		-- a shaved head shows its regrowth as a shadow; freshly shaved: no hair meshes at all
		if H.growth <= 0.05 then
			return H, true
		end
		local full = H.lod == "full"
		local seed = H.seed % 1000
		Parts.Cap(H, { top = 0.004 + 0.006 * H.grow, side = 0.004 + 0.005 * H.grow, density = clamp(0.2 + 0.5 * H.grow, 0, 0.72),
			pattern = "stubble", flow = "whorl", grain = 0.75, capT = 0.8, edge = 0.05, gridNormals = true, streak = 0,
			cols = full and 84 or (H.lod == "medium" and 44 or nil), rows = full and 38 or (H.lod == "medium" and 18 or nil),
			extra = function(x, y, z, c)
				return 0.0015 * (Kit.RNoise(x, y, z, 26, seed, 1) + 0.5 * Kit.RNoise(x, y, z, 55, seed + 1, 2)) * c
			end })
	else
		recipeFor(style, htype)(H)
	end
	baseLandmarks(H)
	return H, false
end

function Gen.Generate(look, lod, ctx)
	look = type(look) == "table" and look or {}
	if lod ~= "full" and lod ~= "medium" and lod ~= "low" then
		lod = "full"
	end
	local style, htype = resolve(look)
	-- the strand counts scale down until the section fits its triangle budget (the shells are fixed cost)
	local scale = 1
	local H, empty
	for attempt = 1, 4 do
		H, empty = build(look, lod, ctx, style, htype, scale)
		if empty then
			return { pieces = {} }
		end
		local tris = Parts.Tris(H)
		if tris <= H.budget or attempt == 4 then
			break
		end
		scale *= clamp(H.budget / tris * 0.9, 0.3, 0.92)
	end
	return Parts.Finish(H, H.fx)
end

function Gen.Landmarks(look)
	look = type(look) == "table" and look or {}
	local style, htype = resolve(look)
	local H = Parts.Context(look, "low", nil, style, htype)
	baseLandmarks(H)
	local out = {}
	for name, p in pairs(H.landmarks) do
		out[name] = { part = "Head", pos = { p[1] * H.S.kx, p[2] * H.S.ky, p[3] * H.S.kz } }
	end
	return out
end

Gen._R = R
return Gen
