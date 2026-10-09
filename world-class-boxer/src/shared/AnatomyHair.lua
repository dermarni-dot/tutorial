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
	-- short clumps lying with the comb flow, a little lifted: the top's relief (it shades in tufts) and a broken
	-- silhouette instead of a helmet's smooth outline
	if spec.clumps ~= false then
		Parts.Clumps(H, {
			n = spec.clumpN or 320, seed = 21, sides = 3, accept = spec.accept or topRegion(0.2, 0.34), flow = flow,
			-- (lying low on the shell: lifted tufts caught the light edge-on and read as dark chevrons)
			lift = 0.045 + 0.1 * (spec.lift or 0.3), stick = 0.93, grav = 0.05, stiff = 0.5, free = 1,
			len = function(r)
				return lerp(0.04, 0.075, r[9]) * (0.8 + 0.5 * H.len)
			end, w = 0.016, h = 0.0032, flat = 0.7, off = function(u)
				-- (over the shell at its thickest, its tufts included: never buried in it)
				return top + 0.009 + 0.006 * u
			end, twist = 0.3, maxRings = 3, taper = 0.4, tipW = 0.2, layerK = 1.12, jitter = spec.jitter or { amp = 0.25, freq = 7 },
			-- (slim locks in the top's own tone: tufts of it, not flakes on it)
			uniform = 0.45, material = "Plastic", castShadow = false, share = 0.6,
		})
	end
	-- hundreds of fine strands lying with the comb flow and lifting a little off the shell: the hairy texture and
	-- soft broken outline of a short cut (the shell's texture carries the strand streaks under them)
	return Parts.Fur(H, {
		n = spec.n or 520, accept = spec.accept or topRegion(0.2, 0.34), flow = flow, lift = 0.22 + 0.25 * (spec.lift or 0.3),
		len = function(r)
			return lerp(len0, len1, r[9]) * (spec.lenK and spec.lenK(r) or 1)
		end, off = top * 0.6, jitter = spec.jitter and spec.jitter.amp or 0.22, share = spec.share or 0.4,
	})
end

------------------------------------------------------------------------
-- Recipes: function(H) builds the pieces; H.htype is the hair type
------------------------------------------------------------------------
local R = {}
local fill

local SHORT = {
	["Buzz Cut"] = { top = 0.003, side = 0.0025, clumps = false, density = 0.62 },
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
	["360 Waves"] = { top = 0.007, side = 0.005, clumps = false, pattern = "waves", density = 0.9 },
}
local FADE_TOP = { low = 0.15, mid = 0.24, high = 0.32, fade = 0.24, taper = 0.12, burst = 0.25 }
-- how far hair of each type stands off the scalp at the same clipper length: straight hair lies flat, curlier
-- hair springs up (a coily buzz is a fuller, darker layer than a straight one). It scales the short shells, so a
-- cut never builds the same geometry for two hair types (also far away, where the shell is all there is)
local STAND = { Straight = 1, Wavy = 1.1, Curly = 1.22, Kinky = 1.34, Coiled = 1.42 }

local function shortCut(H)
	local sp = SHORT[H.style]
	local L = H.len
	local grow = H.grow
	local hasTop = sp.clumps ~= false
	-- under the top clumps the shell is a thin dark under-layer; a clipper cut is the shell alone
	-- a short cut's top is a volume of hair (its texture and fur on top), the sides fade
	local stand = STAND[H.htype] or 1
	local top = hasTop and (0.022 + 0.022 * L) * stand or (sp.top + 0.004 * L + 0.01 * grow) * stand
	local side = (sp.side + 0.006 * grow) * stand
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
		-- (coily hair grows denser: a coily buzz is darker than a straight one)
		top = top, side = side, fade = sp.fade, density = sp.density and lerp(sp.density * (COILY[H.htype] and 1.18 or 1), 1, grow * 0.7) or 1,
		-- dense coily hair hides a low gradient: its fades are cut higher to read
		fadeLift = coily and 0.07 or nil,
		-- (curly hair: the shell carries curl clusters, not combed strands - a smooth shell under a few curls
		-- reads as a glossy helmet)
		pattern = sp.pattern or (COILY[H.htype] and (hasTop and "coil" or "stubble")) or (hasTop and (H.htype == "Curly" and "curl"
			or "strands") or "stubble"),
		flow = sp.pattern == "waves" and "down" or (sp.flow or "whorl"),
		grain = hasTop and 1 or 0.75, part = hasTop and H.partX or nil, capT = coily and 0.6 or (hasTop and 0.35 or 0.8),
		waveLam = 0.052, edge = hasTop and 0.07 or 0.05,
		-- clipper hair is too short for strands: no streaks, hair by hair over the scalp (the texture). A
		-- clipper shell is a skin-thin layer with the scalp's own smooth normals and the skin's material: it
		-- reads as a shadow on the scalp, never as a cap
		-- (short hair: its streaks faint, a texture rather than combed lines)
		streak = (clipper and sp.pattern ~= "waves") and 0 or 0.18,
		-- the scalp's smooth normals: a relief the grid could carry would be lobes, finer detail is the texture
		-- and the coil clusters
		material = "Plastic", reflectance = 0,
		-- a short top is never an even shell: a gentle unevenness of its thickness (tufts) breaks its outline
		extra = (hasTop and not coily) and function(x, y, z, c)
			return 0.009 * (0.5 + Kit.RNoise(x, y, z, 6, seed + 61, 1)) * smoothstep(0.6, 0.95, c) * smoothstep(fadeTop - 0.04, fadeTop + 0.08, y)
		end or nil,
		cols = (coily and full and 56) or (clipper and (full and 64 or (H.lod == "medium" and 40 or nil))) or nil,
		rows = (coily and full and 26) or (clipper and (full and 28 or (H.lod == "medium" and 16 or nil))) or nil,
	})
	if clipper and grow > 0.4 and H.lod ~= "low" then
		-- a clipper cut left to grow becomes a short natural cut: tufts appear over the crown
		shortTop(H, { top = top, len = { 0.035 + 0.03 * grow, 0.06 + 0.04 * grow }, flow = "whorl", lift = 0.3, n = floor(200 * (grow - 0.3)),
			accept = topRegion(0.1, 0.25), clumps = false, share = 0.9 })
	end
	if coily and H.lod ~= "low" then
		-- coil clusters and a little fuzz over the full part of the cut (above the fade, never in it)
		local fadeTop2 = (FADE_TOP[sp.fade or ""] or 0.2) + 0.07
		local acc = function(x, y, z, da, c)
			return smoothstep(fadeTop2 + 0.02, fadeTop2 + 0.1, y) * smoothstep(0.6, 0.95, c)
		end
		local cut = H.cut
		local layer = function(x, y, z)
			return H.S.f(x, y, z) - (cut.thick(x, y, z))
		end
		-- a soft, fuzzy outline: many short fine coils lifted a little off the surface, the surface's own tone
		Parts.Fuzz(H, { n = 320, vol = layer, accept = acc, len = 0.012 + 0.008 * L, lift = 0.45, zig = 0.0035, share = 0.85 })
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

-- the strands by the cheeks are tucked behind the ears (no wings of hair standing off the cheeks)
local function behindEar(pts)
	local p0 = pts[1]
	if p0[3] > -0.12 then
		return pts
	end
	local k0 = smoothstep(-0.12, -0.3, p0[3])
	for i = 2, #pts do
		local p = pts[i]
		local k = k0 * smoothstep(0.22, 0.02, p[2])
		if k > 0 then
			local zt = 0.06 + 0.04 * smoothstep(0.02, -0.4, p[2])
			if p[3] < zt then
				p[3] = lerp(p[3], zt, k)
			end
			-- and close to the head's side there (not flaring out over the ear)
			local xt = (p[1] < 0 and -1 or 1) * min(abs(p[1]), 0.5)
			p[1] = lerp(p[1], xt, k)
		end
	end
	return pts
end

-- long, layered hair (straight / wavy); curly and coily types are routed to their own recipes. The mass is a
-- sculpted sheet of locks (ridges and grooves that shade, pointed lock ends, a darker inside) from the
-- parting and the crown down past the shoulders; slim locks over it frame the face and break the silhouette
-- and the hem; a few flyaways
R["Long Hair"] = function(H)
	local S = H.S
	local L = H.len
	local px = H.partX or 0
	local flow = Kit.Flow(S, "part", { x = px })
	local vol = H.volume
	local full = H.lod == "full"
	S.guardFace = true
	Parts.Cap(H, { top = 0.02, side = 0.018, pattern = "strands", flow = "part", flowOpts = { x = px }, part = px, capT = 0.15,
		cols = full and 40 or nil, rows = full and 17 or nil, streak = 0.7, long = true, material = "Plastic" })
	local hangLen = 0.55 + 0.9 * L
	local function len(r)
		-- layers: the back longest, the face-framing front shorter
		local front = 1 - smoothstep(0.4, 1.6, r[7])
		return hangLen * (1 - 0.3 * front) * (0.9 + 0.2 * r[9])
	end
	local wavy = H.htype == "Wavy"
	-- broad S-waves (sampled by enough rings per wavelength: an under-sampled wave turns into a zigzag)
	local wave = wavy and { amp = 0.028, lam = 0.42, rise = 0.25, phase = wavePhase(H) } or nil
	-- an inner layer behind the mass: between the lock ends and their gaps there is more hair, never the neck
	-- (the longer hair under a layered cut's shorter locks: barely darker than they are, its own locks and
	-- strand streaks - a dark flat panel there read as grey slabs between the locks)
	if H.lod ~= "low" then
		fill(H, flow, hangLen * 0.9, "HairClump", 0.78, 30, { amp = 0.03, material = Parts.Material(H.htype) })
	end
	-- the mass: a continuous sheet of locks from temple to temple round the back, resting a little off the
	-- shoulders and back (bodyOff) so a guard's raised trapezius does not cut into it. Narrow locks on three
	-- length layers, each pointed into a strand-thin tip
	Parts.Curtain(H, {
		cols = 80, az0 = -2.7, az1 = 2.7, bend = behindEar, th = function(az)
			-- the roots close round the crown at the back, along the parting toward the front
			return 0.36 + 0.4 * (abs(az) / pi)
		end, len = function(az, rnd)
			-- the roots sit high on the crown: the strand first runs over the skull (~0.45), then hangs
			local front = smoothstep(1.6, 2.6, abs(az))
			return (0.45 - 0.1 * front + hangLen * (0.84 - 0.25 * front)) * (0.95 + 0.1 * rnd)
		end, flow = flow, off = function(u)
			return 0.016 + 0.01 * u + 0.012 * vol * u
		end, stick = 0.95, grav = 1, stiff = 0.2, shade = 0.95, innerShade = 0.66, hang = { prefix = "HairClump" }, wave = wave,
		bodyOff = 0.075, half = H.lod == "low" and 0.012 or 0.008, rings0 = wavy and 22 or 18, innerStride = 2,
		-- (locks 4 columns wide, each a rounded bundle: a semicircular ridge ~0.04 high on the outer face and
		-- half that on the inner one - a lens cross-section as deep as a third of its width - with a dark
		-- groove between locks: the back and the sides are sculpted locks, not flat ribbons)
		locks = { w = 4, amp = 0.04 + 0.012 * vol, root = 0.004, round = true, inner = 0.5, pointK = 0.3, jag = 0.06, layers = { 1, 0.88, 0.76 } },
		-- (locks pushed apart by the shoulders, or a short lock beside a long one at the hem, part instead of
		-- being bridged by a stretched flat panel; the fill sheet behind shows between them. Low detail has no
		-- fill sheet: there the curtain stays whole - parted, it showed the neck between a few strips)
		split = H.lod ~= "low" and 0.09 or nil,
	})
	-- slim locks over the mass (face framing, the sides, the crown), lying on it
	Parts.Clumps(H, {
		n = 48, seed = 2, len = function(r)
			return len(r) * (0.86 + 0.18 * r[9])
		end, w = 0.032, h = 0.0075, flow = flow, lift = 0.06 + 0.08 * vol, stick = 0.9, grav = 1, stiff = 0.25,
		off = function(u)
			return 0.03 + 0.012 * vol + 0.014 * u
		end, wave = wave, twist = 0.4, layerK = 1.02, hang = { prefix = "HairClump" }, tips = 0.7, maxRings = wavy and 13 or 9,
		bend = behindEar, bodyOff = 0.09, share = 0.62, taper = 0.55, tipW = 0.05, flat = 0.25, sides = 3, accept = function(x, y, z, da, c)
			-- more at the front and sides (over the face-framing sheet edges), fewer down the back
			return smoothstep(0.35, 0.8, c) * (0.45 + 0.55 * smoothstep(1.0, 2.2, da))
		end,
	})
	-- fine strands combed along the top and the front (the cap there is hair, not a smooth shell)
	Parts.Fur(H, { n = 240, flow = flow, lift = 0.05, len = function(r)
		return 0.12 + 0.1 * r[9]
	end, off = 0.022, jitter = 0.1, share = 0.5, accept = function(x, y, z, da, c)
		return smoothstep(0.6, 0.9, c) * smoothstep(0.15, 0.35, y)
	end })
	Parts.Flyaways(H, { n = 16, len = function(r)
		return 0.12 + 0.12 * r[9]
	end, flow = flow, share = 0.3 })
	S.guardFace = false
end

-- combed straight back: a sheet of locks from the front hairline over the top and the sides to the back of the
-- head (the comb's grooves shade it), its ends tucked where the head turns under at the occiput; a few loose
-- locks over it, fine strands lifting off the crown
R["Slick Back"] = function(H)
	local S = H.S
	local L = H.len
	local flow = Kit.Flow(S, "back")
	Parts.Cap(H, { top = 0.02, side = 0.016, pattern = "strands", flow = "back", grain = 0.8, capT = 0.45, contrast = 1.15,
		material = "Plastic", reflectance = 0.02 })
	local cut = H.cut
	Parts.Curtain(H, {
		cols = 44, az0 = pi - 1.55, az1 = pi + 1.55, th = function(az)
			return Kit.HairlinePolar(S, cut, az, 0.012)
		end, len = function()
			return 1.3 + 0.2 * L
		end, flow = flow, off = function(u)
			-- rising out of the cap at the hairline (no lip on the forehead)
			return 0.006 + 0.016 * smoothstep(0, 0.12, u) + 0.006 * u + 0.01 * H.volume * u
		end, stick = 1, grav = 0.2, stiff = 0.3, free = 0.99, clipY = 0.02 - 0.08 * L,
		shade = 1.02, innerShade = 0.55, half = 0.004, rings0 = 18, innerStride = 3, material = "Plastic",
		locks = { w = 3, amp = 0.0065, root = 0.002, pointK = 0.04 },
	})
	Parts.Clumps(H, {
		n = 34, seed = 4, len = function(r)
			return (0.35 + 0.4 * L) * (0.8 + 0.3 * r[9])
		end, w = 0.03, h = 0.005, flow = flow, lift = 0.02, stick = 1, grav = 0.2, stiff = 0.2, free = 0.99,
		off = function(u)
			return 0.03 + 0.004 * u
		end, twist = 0.15, layerK = 1.04, material = "Plastic", maxRings = 9, taper = 0.6, tipW = 0.15, flat = 0.5, sides = 3,
		accept = function(x, y, z, da, c)
			return smoothstep(0.6, 0.9, c) * smoothstep(0.15, 0.3, y)
		end, bend = function(pts)
			-- tucked: never below the occiput
			for i = 2, #pts do
				if pts[i][2] < -0.08 then
					return table.move(pts, 1, i, 1, {})
				end
			end
			return pts
		end, share = 0.6,
	})
	Parts.Fur(H, { n = 160, flow = flow, lift = 0.25, len = function(r)
		return 0.04 + 0.04 * r[9]
	end, off = 0.022, share = 0.35, accept = function(x, y, z, da, c)
		return smoothstep(0.6, 0.9, c) * smoothstep(0.25, 0.45, y)
	end })
end

-- messy: a thick textured base, many slim locks pointing every which way (lifted on the crown, falling at the
-- nape), fine strands and flyaways breaking the outline
R["Messy Hair"] = function(H)
	local S = H.S
	local L = H.len
	local flow = Kit.Flow(S, "whorl")
	-- the shell is the hair's shadowed depth between the clumps (darker than they are)
	Parts.Cap(H, { top = 0.036, side = 0.028, pattern = "strands", flow = "whorl", capT = 0.15, capK = 0.78, contrast = 0.9,
		material = "Plastic" })
	local wave = H.htype == "Wavy" and { amp = 0.01, lam = 0.16, phase = wavePhase(H) } or nil
	if H.lod == "low" then
		-- far away: a short, ragged layer round the back and sides keeps the tousled outline (not a smooth cap)
		Parts.Curtain(H, { cols = 24, az0 = -2.4, az1 = 2.4, th = function(az)
			return 0.9 + 0.25 * (abs(az) / pi)
		end, len = function(az, rnd)
			return (0.24 + 0.16 * L) * (1 - 0.35 * smoothstep(1.6, 2.4, abs(az)))
		end, flow = Kit.Flow(S, "down"), off = function(u)
			return 0.036 + 0.012 * u
		end, stick = 0.7, grav = 0.6, stiff = 0.4, shade = 0.8, half = 0.008, material = "Plastic",
			locks = { w = 3, amp = 0.01, root = 0.004, pointK = 0.4, jag = 0.25 } })
	end
	-- the nape's locks fall instead of sticking out sideways
	local function nape(r)
		return smoothstep(2.0, 2.5, r[7]) * (1 - smoothstep(0.05, 0.2, r[2]))
	end
	Parts.Clumps(H, {
		n = 210, seed = 5, sides = 3, len = function(r)
			-- shorter round the face (the temples) and at the nape (no rat tails)
			local temple = smoothstep(0.7, 1.1, r[7]) * (1 - smoothstep(1.5, 1.9, r[7])) * (1 - smoothstep(0.25, 0.4, r[2]))
			return (0.12 + 0.18 * L) * (0.7 + 0.6 * r[9]) * (1 - 0.3 * smoothstep(1.2, 2.6, r[7])) * (1 - 0.4 * temple)
				* (1 - 0.4 * nape(r))
		end, w = 0.026, h = 0.005, flat = 0.55, flow = flow, lift = 0.32, stick = 0.35, grav = 0.3, stiff = 0.45,
		dir = function(r)
			local k = nape(r)
			if k > 0.3 then
				return { r[4] * 0.2, -1, r[6] * 0.4 }
			end
			return nil
		end, off = function(u)
			return 0.03 + 0.016 * u
		end, wave = wave, twist = 0.5, jitter = { amp = 0.4, freq = 5 }, tips = 0.5, maxRings = wave and 8 or 6, material = "Plastic",
		taper = 0.55, tipW = 0.12, share = H.lod == "low" and 0.9 or 0.68, layerK = 1.05,
	})
	Parts.Fur(H, { n = 260, flow = flow, lift = 0.45, jitter = 0.45, len = function(r)
		return 0.04 + 0.05 * r[9]
	end, off = 0.03, share = 0.2 })
	Parts.Flyaways(H, { n = 22, len = function(r)
		return 0.08 + 0.1 * r[9]
	end, flow = flow, share = 0.08 })
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

-- smooth union / intersection of two distances (blend width k)
local function smin(a, b, k)
	local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return lerp(b, a, h) - k * h * (1 - h)
end
local function smax(a, b, k)
	local h = clamp(0.5 - 0.5 * (b - a) / k, 0, 1)
	return lerp(b, a, h) + k * h * (1 - h)
end

-- a mass's underside curving back to the scalp: at most maxD deep, from ~0.03 at the height where the hair
-- starts (yFront over the forehead, ySide over the ears, yBack at the nape) to `deep` a `span` higher. A smooth
-- function of the position (not of the hairline distance, whose notches round the ears and temples would cut
-- grooves into the mass), blended: the mass rounds into the hairline like the underside of a sphere (no brim,
-- no flat underside)
local function tuckUnder(S, vol, deep, span, yFront, ySide, yBack, spanFront, spanBack)
	local f = S.f
	local atan2 = math.atan2
	spanFront = spanFront or span
	spanBack = spanBack or span
	return function(x, y, z)
		local da = atan2(abs(x), 0.05 - z)
		local sd = smoothstep(0.5, 1.4, da)
		local sb = smoothstep(2.0, 2.8, da)
		local yA = lerp(lerp(yFront, ySide, sd), yBack, sb)
		-- (spanFront: over the forehead; span: round the temples and the sideburns; spanBack: the nape - the
		-- rays there run nearly level, so the depth must grow slowly with the height or the mass overhangs)
		local maxD = 0.03 + deep * smoothstep(yA, yA + lerp(lerp(spanFront, span, sd), spanBack, sb), y) ^ 1.4
		return smax(vol(x, y, z), f(x, y, z) - maxD, 0.05)
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
-- the soft, fuzzy outline of a short coily cut: many short fine coils lifted a little off its surface, in the
-- surface's own tone (vol = the layer's volume, acc = where)
local function coilyFuzz(H, vol, acc, n)
	return Parts.Fuzz(H, { n = n or 320, vol = vol, accept = acc, len = 0.012 + 0.01 * H.len, lift = 0.45, zig = 0.0035, share = 0.85 })
end

local function coilyCap(H, spec)
	local S = H.S
	local th = spec.thickness
	return Parts.Volume(H, {
		vol = layerVol(S, th, spec.mask), layerT = th, layerMask = spec.mask, edge = spec.edge or 0.05,
		bump = spec.bump or 0.004, bumpFreq = 5,
		fade = spec.fade, top = spec.top or 0.012, side = spec.side or 0.01, region = spec.region, shaved = spec.shaved,
		pattern = "coil", material = "Plastic", capT = 0.6, cols = spec.cols or (H.lod == "full" and 52 or nil),
		rows = spec.rows or (H.lod == "full" and 24 or nil), part = spec.part, radial = spec.radial,
	})
end

------------------------------------------------------------------------
-- More recipes
------------------------------------------------------------------------
-- a dark fill sheet behind hanging locs / twists / braids (temple to temple round the back): gaps between the
-- strands show hair, not the neck. Swings with the strands' groups.
fill = function(H, flow, len, prefix, shade, cols, opts)
	-- rooted low on the back of the head (under the strands lying over it), ridged like more strands behind,
	-- each ending on its own (no sheet edge, no straight hem); opts.amp: a deeper relief, opts.material (the
	-- inner layer of a long mass, seen between its parted lock ends: locks of the same hair), opts.th0: its
	-- roots' polar angle at the back (lower: only behind where the strands leave the scalp), opts.az: how far
	-- round from the back it reaches
	local amp = opts and opts.amp
	local th0 = opts and opts.th0 or 1.15
	local az1 = opts and opts.az or 1.9
	return Parts.Curtain(H, {
		cols = cols or 18, rings0 = 10, az0 = -az1, az1 = az1, th = function(az)
			return th0 + 0.3 * (abs(az) / pi)
		end, len = function(az, rnd)
			return len * (0.75 + 0.25 * rnd) * (1 - 0.4 * smoothstep(az1 - 0.9, az1, abs(az)))
		end, flow = flow, off = function(u)
			return 0.022 + 0.01 * u
		end, stick = 0.9, grav = 1, stiff = 0.2, shade = shade, innerShade = shade * 0.8, hang = { prefix = prefix },
		material = opts and opts.material or "Fabric",
		half = 0.008, locks = { w = 2, amp = amp or 0.018, root = 0.004, pointK = 0.35, jag = 0.25, round = amp and true or nil, inner = amp and 0.5 or nil },
		streakK = amp and 0.2 or nil,
	})
end
-- broad cluster lobes on a mass round (cx, cy, cz): n bumps in seeded directions (most over the top, sides and
-- back, few low in front), each a rounded swell `amp` high over a cap of angular radius ~acos(c0). Returns
-- lobes(dx, dy, dz) -> outward swell for a unit direction, 0..1 "how far onto a lobe" (1 its crown, 0 a valley)
local function clusterLobes(seed, n, amp)
	local rng = MeshKit.Rng(seed)
	local L = {}
	for i = 1, n do
		-- a Fibonacci spread over the upper part of the sphere (none low on the sides: no brim), jittered
		local yv = 1 - (i - 0.5) / n * 1.15 + rng:Range(-0.08, 0.08)
		local rr = math.sqrt(max(0, 1 - yv * yv))
		local a = i * 2.399963 + rng:Range(-0.4, 0.4)
		local lx, ly, lz = rr * cos(a), yv, rr * sin(a)
		L[#L + 1] = { lx, ly, lz, amp * rng:Range(0.6, 1.25), rng:Range(0.8, 0.88) }
	end
	return function(dx, dy, dz)
		local s, top = 0, 0
		for i = 1, #L do
			local l = L[i]
			local c = dx * l[1] + dy * l[2] + dz * l[3]
			if c > l[5] then
				local k = (c - l[5]) / (1 - l[5])
				local w = k * k * (3 - 2 * k)
				s += l[4] * w
				if w > top then
					top = w
				end
			end
		end
		return s, top
	end
end

R["Afro"] = function(H)
	local S = H.S
	local L = H.len
	local ht = COILY[H.htype] and H.htype or (H.htype == "Curly" and "Curly" or "Kinky")
	local size = 0.13 + 0.24 * L * (0.55 + 0.45 * SHRINK[ht]) + 0.06 * H.volume
	-- the mass sits a little behind the hairline and low enough to blend into the scalp at the sides
	local cy, cz = 0.08 + 0.3 * size, 0.17 + 0.22 * size
	local rx, ry, rz = 0.39 + size * 0.92, 0.42 + size * 0.95, 0.47 + size * 0.85
	local seed = H.seed % 1000
	-- 8-12 broad clusters swelling out of the mass: a lumpy, cauliflower outline instead of an ellipse
	local lobes = clusterLobes(H.seed + 401, 8 + floor((seed % 5) * 1.01), 0.05 + 0.04 * size)
	local mr = min(rx, ry, rz)
	-- egg-shaped: fullest above the ears, narrowing below toward where it tucks in (a round mass that blends
	-- into the scalp, not a mushroom cap that is widest at its rim)
	local function narrow(y)
		return 1 - 0.14 * smoothstep(cy + 0.12, cy - 0.42, y)
	end
	local ell = function(x, y, z)
		local nk = narrow(y)
		local dx, dy, dz = x / (rx * nk), (y - cy) / ry, (z - cz) / (rz * nk)
		local l = math.sqrt(dx * dx + dy * dy + dz * dz)
		local sw = 0
		if l > 1e-4 then
			sw = lobes(dx / l, dy / l, dz / l)
		end
		-- an irregular outline: the lobes plus a broad, clearly uneven wobble (not a perfect ellipse)
		return (l - 1) * mr - sw + 0.08 * Kit.RNoise(x, y, z, 3.5, seed + 41, 1) + 0.025 * Kit.RNoise(x, y, z, 7, seed + 42, 2)
	end
	-- its underside curves back into the scalp at the nape, over the ears and at the sideburns - a long, gradual
	-- tuck (no brim, no shelf over the ears with a shadow gap under it)
	local vol = tuckUnder(S, ell, 0.85, 0.62, 0.3, -0.12, -0.36, 0.4, 1.0)
	-- occlusion: the valleys between the clusters and the underside are darker (depth, not a smooth sheen)
	local ao = function(x, y, z)
		local dx, dy, dz = x / rx, (y - cy) / ry, (z - cz) / rz
		local l = math.sqrt(dx * dx + dy * dy + dz * dz)
		local top = 1
		if l > 1e-4 then
			local _, t = lobes(dx / l, dy / l, dz / l)
			top = t
		end
		local under = smoothstep(cy - 0.05, cy - 0.45, y)
		return (0.78 + 0.22 * top) * (1 - 0.3 * under)
	end
	local full = H.lod == "full"
	Parts.Volume(H, {
		-- (the mass rounds down into the scalp over ~0.2 studs above the ears and at the nape: the shell grows
		-- from the hairline, so a steep rise there is the brim over the ears with a dark gap under it)
		vol = vol, radial = true, edge = 0.2, frontEdge = 0.09, bump = ht == "Curly" and 0.055 or 0.05, bumpFreq = 4.5, tmax = 0.8,
		top = 0.02, side = 0.02, pattern = ht == "Curly" and "curl" or "coil", material = "Fabric", reflectance = 0, capT = 0.55,
		grain = ht == "Curly" and 1.3 or (H.lod == "full" and 1.9 or 1.5), ao = ao,
		cols = full and 64 or (H.lod == "medium" and 40 or 20), rows = full and 30 or (H.lod == "medium" and 17 or 9),
	})
	-- the coil clusters break the outline: most of them where the mass is the silhouette (its sides, top and
	-- back rim), fewer over the face-on middle
	local rim = function(x, y, z, da, c)
		local side = smoothstep(0.4, 1.3, da)
		return smoothstep(0.7, 0.95, c) * (0.35 + 0.65 * max(side, smoothstep(0.25, 0.5, y)))
	end
	if ht == "Curly" then
		-- curl clusters half sunk in the mass (bumps of ringlets breaking up the surface and its outline)
		Parts.Curls(H, { n = 160, vol = vol, accept = rim, flow = Kit.Flow(S, "whorl"), lift = 1, stick = 0, grav = 0.1, stiff = 0.8, len = function(r)
			return 0.04 + 0.04 * r[9]
		end, radius = 0.03, tube = 0.012, off = function(u, r)
			return Parts.DepthIn(vol, r[1], r[2], r[3], r[4], r[5], r[6], 0.8) - 0.045
		end, bounce = bounceKey(H), share = 0.75 })
	else
		Parts.Fuzz(H, { n = 300, vol = vol, len = 0.018, zig = 0.005, lift = 0.25, share = 0.3 })
		Parts.CoilHalo(H, { n = 220, vol = vol, accept = rim, sink = 0.7, radius = 0.015, len = 0.03, bounce = bounceKey(H), share = 0.62 })
	end
	H.fx = { kind = "bounce", stiff = 0.7, mass = 1.4 }
end

-- the high top: a tall column of coils over a high fade. Its section a superellipse (rounded, not a box),
-- a little wider toward the soft-domed top, the front face leaning back, its edges well rounded, its foot
-- blended into the faded sides
R["High Top"] = function(H)
	local S = H.S
	local L = H.len
	local yTop = 0.66 + 0.32 * L * (0.6 + 0.4 * SHRINK[H.htype]) + 0.04 * H.volume
	local yb = 0.18
	local f = S.f
	local seed = H.seed % 1000
	local vol = function(x, y, z)
		local k = clamp((y - yb) / (yTop - yb), 0, 1)
		local hx = 0.44 + 0.03 * k
		-- the front face leans back ~8 degrees (its centre moves back, its depth shrinks)
		local lean = 0.07 * (y - yb)
		local hz = 0.5 - lean
		local cz = 0.04 + lean
		local ax, az = abs(x) / hx, abs(z - cz) / hz
		local r = (ax ^ 2.6 + az ^ 2.6) ^ (1 / 2.6)
		local dSide = (r - 1) * min(hx, hz)
		local dTop = y - (yTop + 0.04 * (1 - min(1, r * r)))
		local d = smax(dSide, dTop, 0.2) + 0.012 * Kit.RNoise(x, y, z, 3, seed + 43, 1)
		-- the foot blends into the thin faded layer at the sides and back (no ledge); the front face rises
		-- straight from the line-up (a blend there would bulge into a brow)
		local da = math.atan2(abs(x), 0.05 - z)
		return smin(d, f(x, y, z) - 0.012, 0.01 + 0.11 * smoothstep(0.7, 1.4, da))
	end
	local full = H.lod == "full"
	Parts.Volume(H, {
		vol = vol, radial = true, edge = 0.02, frontEdge = 0.03, bump = full and 0.045 or 0.03, bumpFreq = 5, tmax = 0.8, fade = "high", top = 0.016, side = 0.012,
		pattern = "coil", material = "Fabric", capT = 0.55, grain = H.lod == "full" and 1.9 or 1.5,
		cols = full and 64 or (H.lod == "medium" and 40 or 20), rows = full and 32 or (H.lod == "medium" and 17 or 9),
	})
	local acc = function(x, y, z, da, c)
		return smoothstep(0.3, 0.42, y) * smoothstep(0.6, 0.9, c)
	end
	Parts.Fuzz(H, { n = 260, vol = vol, accept = acc, len = 0.016, zig = 0.004, lift = 0.2, share = 0.35 })
	Parts.CoilHalo(H, { n = 90, vol = vol, accept = acc, sink = 0.85, bounce = bounceKey(H), share = 0.5 })
	H.fx = { kind = "bounce", stiff = 0.8, mass = 1.3 }
end

R["Short Curly"] = function(H)
	local S = H.S
	local L = H.len
	if COILY[H.htype] then
		local t = 0.045 + 0.06 * L * SHRINK[H.htype] + 0.015 * H.volume
		coilyCap(H, { thickness = t, bump = 0.005 })
		coilyFuzz(H, layerVol(S, t))
	else
		-- a dark, lumpy under-volume of curls, ringlets over it
		local t = 0.03 + 0.03 * L
		Parts.Volume(H, { vol = layerVol(S, t), edge = 0.05, bump = 0.024, bumpFreq = 7, top = 0.02, side = 0.02, pattern = "curl",
			material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
		-- dense clusters of short curls packed into the volume (its relief and broken outline), not loose springs
		-- (fat short coils leaning over in the layer: curl clusters, not wire springs standing off the cap)
		Parts.CoilHalo(H, { n = 440, vol = layerVol(S, t), sink = 0.6, radius = 0.017 * (0.85 + 0.3 * L), len = 0.034 + 0.016 * L, tube = 0.011,
			lean = 0.6, bounce = bounceKey(H), share = 0.9 })
	end
	H.fx = { kind = "bounce", stiff = 0.55, mass = 1.1 }
end

R["Curly Top"] = function(H)
	local S = H.S
	local L = H.len
	-- the curly top rises over the high fade's band (a gradient, not a ledge)
	local topMask = function(x, y, z)
		return (y - 0.24) * 2.2
	end
	local acc = function(x, y, z, da, c)
		return smoothstep(0.3, 0.4, y) * smoothstep(0.6, 0.9, c)
	end
	if COILY[H.htype] then
		local t = 0.06 + 0.08 * L
		coilyCap(H, { thickness = t, mask = topMask, fade = "high", bump = 0.005, edge = 0.04 })
		coilyFuzz(H, layerVol(S, t, topMask), acc)
	else
		local t = 0.035 + 0.04 * L
		Parts.Volume(H, { vol = layerVol(S, t, topMask), edge = 0.04, bump = 0.022, bumpFreq = 7, fade = "high", top = 0.016, side = 0.012,
			pattern = "curl", material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
		-- dense clusters of short curls packed into the top (its relief and broken outline), not loose springs
		Parts.CoilHalo(H, { n = 420, vol = layerVol(S, t, topMask), accept = acc, sink = 0.6, radius = 0.017 * (0.85 + 0.3 * L),
			len = 0.036 + 0.016 * L, tube = 0.011, lean = 0.6, bounce = bounceKey(H), share = 0.9 })
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
		-- coils shrink: the length becomes a big rounded mass, deeper at the back and sides, made of broad
		-- cluster lobes (a lumpy outline: not one smooth dome) with coil clusters breaking its surface and
		-- clumps of coils hanging out of its underside below the ears and at the nape
		local size = 0.12 + 0.22 * L * SHRINK[H.htype] + 0.05 * H.volume
		local drop = 0.1 + 0.35 * L * SHRINK[H.htype]
		local seed = H.seed % 1000
		local rx, ry, rz = 0.42 + size, 0.47 + size + drop * 0.6, 0.5 + size * 0.8
		local cy, cz = 0.1 - 0.25 * drop, 0.14 + 0.15 * size
		local mr = min(rx, ry, rz)
		local lobes = clusterLobes(H.seed + 403, 9 + floor((seed % 4) * 1.01), 0.055 + 0.035 * size)
		local ell = function(x, y, z)
			local dx, dy, dz = x / rx, (y - cy) / ry, (z - cz) / rz
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			local sw = 0
			if l > 1e-4 then
				sw = lobes(dx / l, dy / l, dz / l)
			end
			return (l - 1) * mr - sw + 0.06 * Kit.RNoise(x, y, z, 2.6, seed + 41, 1) + 0.022 * Kit.RNoise(x, y, z, 6, seed + 42, 2)
		end
		-- deeper at the back and sides; the underside rounds back into the scalp over a long run (no hard
		-- tuck edge above the ears), lower for longer hair
		local vol = tuckUnder(S, ell, 0.75, 0.6, 0.28, -0.22 - 0.25 * drop, -0.45 - 0.3 * drop, 0.45, 1.0)
		local ao = function(x, y, z)
			local dx, dy, dz = x / rx, (y - cy) / ry, (z - cz) / rz
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			local top = 1
			if l > 1e-4 then
				local _, t = lobes(dx / l, dy / l, dz / l)
				top = t
			end
			return (0.78 + 0.22 * top) * (1 - 0.3 * smoothstep(cy - 0.05, cy - 0.45, y))
		end
		local full = H.lod == "full"
		-- (edgeDepth: the mass rolls off to its hairline over ~0.8 x its depth there - a slope, no shelf of hair
		-- standing on the forehead and the temples)
		local _, shell = Parts.Volume(H, { vol = vol, radial = true, edge = 0.14, frontEdge = 0.16, edgeDepth = 0.8, bump = 0.05, bumpFreq = 4.5, tmax = 0.8, top = 0.02, side = 0.02,
			pattern = "coil", material = "Fabric", capT = 0.55, grain = H.lod == "full" and 1.9 or 1.5, ao = ao, cols = full and 64 or (H.lod == "medium" and 40 or 20),
			rows = full and 30 or (H.lod == "medium" and 17 or 9) })
		local rim = function(x, y, z, da, c)
			return smoothstep(0.7, 0.95, c) * (0.35 + 0.65 * max(smoothstep(0.4, 1.3, da), smoothstep(0.25, 0.5, y)))
		end
		if H.lod ~= "low" then
			-- hanging coil clumps: short ringlets dropping out of the mass's underside at the sides and the nape,
			-- each a clump of two coils wound round one another (a bundle of coils, not a wire spring), uneven in
			-- length; swinging in groups (HairClump: the HairCurl names are the mass's bounce clusters). Rooted
			-- a little inside the hairline (under the mass, not its rolled-off edge), each runs just under the
			-- mass's visible surface (its shell, not vol: near the hairline the shell lies well inside vol) to
			-- where it comes out of it, and is built from just inside there. Rounded coils: 4-sided tubes, 7
			-- points a turn (3 sides and 5 a turn read as angular rope, barbed wire). Built before the halo and
			-- the fuzz: those fill whatever budget is left
			local cut = H.cut
			local depth = {}
			Parts.Curls(H, { n = 24, seed = 3, ply = 2, flow = Kit.Flow(S, "down"), lift = 0.15, stick = 0.4, grav = 1, stiff = 0.35,
				accept = function(x, y, z, da, c)
					-- (behind the ears and round the back: none at the temples, over the face)
					return (1 - smoothstep(-0.05, 0.15, y)) * smoothstep(1.2, 1.6, da) * smoothstep(0.5, 0.9, c) * smoothstep(0.05, 0.14, cut.dist(x, y, z))
				end, len = function()
					return 0.9
				end, inside = vol, shell = shell, hangLen = function(r)
					return (0.08 + 0.24 * L * SHRINK[H.htype]) * (0.45 + 1.1 * r[9])
				end, radius = 0.019, tube = 0.015, off = function(u, r)
					-- (the shell's depth over the root: a ray and a depth search, once a clump)
					local d = depth[r]
					if not d then
						d = -shell(r[1], r[2], r[3])
						depth[r] = d
					end
					return max(0.02, d - 0.04)
				end, hang = { prefix = "HairClump" }, pitch = 1.6, maxTurns = 3.5, perTurn = 7, sides = 4, bodyOff = 0.06, share = 0.5 })
		end
		Parts.Fuzz(H, { n = 230, vol = vol, len = 0.018, zig = 0.005, lift = 0.25, share = 0.22 })
		Parts.CoilHalo(H, { n = 150, vol = vol, accept = rim, sink = 0.7, radius = 0.015, len = 0.03, bounce = bounceKey(H), share = 0.36 })
		H.fx = { kind = "bounce", stiff = 0.65, mass = 1.4 }
		S.guardFace = false
		return
	end
	local hangLen = (0.45 + 0.85 * L) * SHRINK.Curly
	local vol = H.volume
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local t = 0.035 + 0.02 * L + 0.01 * vol
	Parts.Volume(H, { vol = layerVol(S, t), layerT = t, edge = 0.05, bump = 0.02, bumpFreq = 6, top = 0.02, side = 0.02, pattern = "curl",
		material = "Fabric", capT = 0.3, cols = H.lod == "full" and 44 or nil, rows = H.lod == "full" and 20 or nil })
	-- A-line: below the ears the mass flares out, wider toward the ends (big curly hair is a triangle, not a sign
	-- hanging off the head)
	local flare = (0.1 + 0.08 * vol) * (0.6 + 0.4 * L)
	local function spread(pts)
		for _, p in ipairs(pts) do
			local k = smoothstep(0.15, -0.65, p[2]) ^ 1.3
			if k > 0 then
				local ox, _, oz = Kit.norm3(p[1], 0, p[3] - 0.04)
				p[1] += ox * flare * k
				p[3] += oz * flare * k * 0.8
			end
		end
		return pts
	end
	-- the mass: a deep-ridged sheet of curly locks (ringlet bundles) from high on the head round the back and the
	-- sides to the shoulders, crimped by the curl, its hem uneven and soft (no corners: the sides end in short
	-- locks well behind the face)
	-- (its roots start under the curly cap and rise out of it gradually - the cap overlaps the sheet by ~0.03,
	-- so there is no straight top edge where one meets the other - and the sheet is split into crimped locks:
	-- deep grooves, each lock waving on its own phase, uneven ends)
	Parts.Curtain(H, { az0 = -2.2, az1 = 2.2, th = function(az)
		return 0.42 + 0.4 * (abs(az) / pi)
	end, len = function(az, rnd)
		return (0.48 + hangLen * (0.95 - 0.35 * smoothstep(1.3, 2.2, abs(az)))) * (0.92 + 0.16 * rnd)
	end, flow = flow, off = function(u)
		return t - 0.03 + 0.072 * smoothstep(0, 0.3, u) + 0.03 * u
	end, stick = 0.9, grav = 1, stiff = 0.2, bend = function(pts)
		return spread(behindEar(pts))
	end, shade = 0.8, innerShade = 0.62, hang = { prefix = "HairCurl" },
		material = "Fabric", half = 0.012, bodyOff = 0.08, rings0 = 24, streakK = 0.22, cols = 44,
		wave = { amp = 0.03 * (1 + 0.4 * vol), lam = 0.11, rise = 0.1, phase = function(r)
			-- (a phase that drifts round the head: neighbouring columns of a lock crimp together, locks apart)
			return MeshKit.Noise(r[1] * 5, r[2] * 2, r[3] * 5, H.seed % 1000 + 9) * 4
		end },
		locks = { w = 4, amp = 0.045, root = 0.004, pointK = 0.12, jag = 0.25 } })
	-- curls on the crown and round the face
	Parts.Curls(H, { n = 110, flow = Kit.Flow(S, "down"), lift = 0.45, stick = 0.3, grav = 0.3, stiff = 0.5, accept = function(x, y, z, da, c)
		return smoothstep(0.2, 0.36, y) * smoothstep(0.6, 0.9, c)
	end, len = function(r)
		return 0.09 + 0.07 * r[9]
	end, radius = 0.03, tube = 0.012, off = function()
		return t * 0.8
	end, pitch = 2.8, perTurn = 5, sides = 3, share = 0.3 })
	-- ringlets lying on the mass, hanging with it: fewer, fuller ones (a ringlet is a bundle of hair, not a wire
	-- spring) - cheap springs: few sides and points per turn
	Parts.Curls(H, { n = 54, flow = flow, lift = 0.2, stick = 0.5, grav = 1, stiff = 0.35, accept = function(x, y, z, da, c)
		return (1 - smoothstep(0.3, 0.42, y)) * smoothstep(0.5, 1.0, da) * smoothstep(0.5, 0.9, c)
	end, len = function(r)
		return hangLen * (0.7 + 0.35 * r[9])
	end, radius = 0.063 * (1 + 0.4 * vol), tube = 0.019, off = function(u)
		return t + 0.06 + 0.03 * u
	end, bend = spread, hang = { prefix = "HairCurl" }, pitch = 2.6, maxTurns = 6, perTurn = 6, sides = 4, share = 0.7 })
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
	-- the scalp between the locs: matte and darker (sectioned roots), soft new growth when grown out
	Parts.Cap(H, { top = 0.024, side = 0.02, pattern = (grown or COILY[H.htype]) and "coil" or "strands", flow = "down", capT = 0.2,
		capK = 0.85, material = "Fabric", reflectance = 0 })
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local hang = clamp(0.45 + 0.8 * L, 0.3, 1.4)
	H.sparseTop = true
	-- up close the locs are dense enough on their own (between them: the neck, as on a real head of locs; a
	-- sheet behind them reads as a dark panel with a straight top edge). Further away a sheet in a shadowed
	-- tone of the locs keeps the mass of the hair
	if H.lod ~= "full" then
		fill(H, flow, hang * 0.6, "HairLoc", 0.75)
	end
	-- many locs of uneven thickness, lumpy, thinner at the root, gently S-bent, matte and frizzy
	-- (far away fewer, thicker locs keep the silhouette of a head of locs)
	Parts.Tubes(H, { n = 72, minN = 10, section = "loc", r = H.lod == "low" and 0.056 or (H.lod == "medium" and 0.044 or 0.036), rVar = 0.3, flow = flow, lift = 0.4, stick = 0.45,
		grav = 1, stiff = 0.4,
		sides = H.lod == "full" and 5 or nil, ringsPer = 13, wave = { amp = 0.012, lam = 0.35 }, frizz = 0.22, material = "Fabric",
		lodK = { full = 1, medium = 0.5, low = 0.3 }, len = function(r)
			local front = 1 - smoothstep(0.4, 1.4, r[7])
			return hang * (0.75 + 0.4 * r[9]) * (1 - 0.3 * front)
		end, hang = { prefix = "HairLoc" }, tip = "point", bodyOff = 0.06, share = 0.95 })
	H.fx = { kind = "swing", stiff = 0.6, mass = 1.6 }
	S.guardFace = false
end

R["Short Dreads"] = function(H)
	local S = H.S
	local L = H.len
	Parts.Cap(H, { top = 0.024, side = 0.02, pattern = (H.growth > 0.4 or COILY[H.htype]) and "coil" or "strands", flow = "down", capT = 0.2,
		capK = 0.85, material = "Fabric", reflectance = 0 })
	local flow = Kit.Flow(S, "whorl")
	-- short locs lying out and down from the crown (not radial spikes), uneven in length, thickness and spacing
	Parts.Tubes(H, { n = 64, minN = 12, section = "loc", r = 0.032, rVar = 0.25, flow = flow, lift = 0.4, stick = 0.15, grav = 0.8, stiff = 0.6,
		free = 0.2, lodK = { full = 1, medium = 0.45, low = 0.28 }, len = function(r)
			return (0.12 + 0.12 * r[9]) * (0.8 + 0.6 * L) * (0.6 + 0.8 * ((r[9] * 7.3) % 1))
		end, ringsPer = 18, tip = "point", piece = H.lod == "low" and "HairTop" or nil, rootJitter = 2.2, frizz = 0.12, material = "Fabric",
		jitter = { amp = 0.35, freq = 7 }, share = 0.95 })
	H.fx = { kind = "bounce", stiff = 0.75, mass = 1.3 }
end

R["Twists"] = function(H)
	local S = H.S
	local L = H.len
	S.guardFace = true
	Parts.Cap(H, { top = 0.02, side = 0.018, pattern = "coil", flow = "down", capT = 0.3, capK = 0.85, material = "Fabric", reflectance = 0 })
	local flow = Kit.Flow(S, "part", { x = H.partX or 0 })
	local hang = 0.22 + 0.55 * L
	H.sparseTop = true
	Parts.Tubes(H, { n = 64, minN = 10, section = "twist", period = 0.1, r = 0.034, rVar = 0.15, flow = flow, lift = 0.4, stick = 0.45,
		sides = H.lod == "full" and 4 or nil, grav = 0.9, stiff = 0.45, lodK = { full = 1, medium = 0.45, low = 0.28 }, len = function(r)
			return hang * (0.8 + 0.35 * r[9])
		end, hang = { prefix = "HairTwist" }, tip = "point", maxRings = 36, wave = { amp = 0.008, lam = 0.4 }, share = 0.95 })
	H.fx = { kind = "swing", stiff = 0.55, mass = 1.3 }
	S.guardFace = false
end

-- braids (fewer, thicker) and box braids (many, thinner, square partings on the scalp)
local function braids(H, box)
	local S = H.S
	local L = H.len
	S.guardFace = true
	local rows, region, psiOf, dpsi = Parts.RowLayout(H, box and 9 or 5, 0.08)
	local boxRegion = region
	-- box sections across the rows: every BSTEP of the angle b round an axis through (cy - 0.25, 0.05),
	-- phased from the front hairline (b0: the first row of sections starts at the line - a parting just
	-- behind it left a bare band along the forehead)
	local BSTEP = 0.3
	local function bOf(y, z)
		return math.atan2(z - 0.05, y - S.cy + 0.25)
	end
	local b0 = 0
	if box then
		local hdist = Kit.Hairline(S, H.hairline, H.growth)
		local lo, hi = 0.3, 1.8
		for _ = 1, 16 do
			local mid = (lo + hi) * 0.5
			local x, y, z = Kit.ScalpAt(S, pi, mid, 0)
			if hdist(x, y, z) > 0 then
				lo = mid
			else
				hi = mid
			end
		end
		local _, hy, hz = Kit.ScalpAt(S, pi, lo, 0)
		b0 = bOf(hy, hz) + 0.5 * BSTEP
		-- square sections: the rows' partings plus partings across them
		boxRegion = function(x, y, z, da)
			local q = (bOf(y, z) - b0) / BSTEP
			local f = abs(q - floor(q + 0.5))
			return region(x, y, z, da) * (1 - smoothstep(0.32, 0.42, f))
		end
	end
	-- the parted scalp: the head's own skin with a fine stipple of new growth, a little denser in each section
	-- round its braid's root (soft and skin-toned: no dark squares), thin clean partings between sections
	local dens = 0.42 + 0.15 * H.grow
	Parts.Cap(H, { top = 0.005, side = 0.004, pattern = "stubble", flow = "back", capT = 0.6, material = "Plastic", grain = 0.6, streak = 0,
		region = boxRegion, shaved = 0.45, density = dens,
		-- (a skin-thin stubble cap: its grid only follows the skull - a coarser one leaves triangles for braids)
		cols = (box and H.lod == "full") and 40 or nil, rows = (box and H.lod == "full") and 18 or nil })
	local flow = Kit.Flow(S, "back")
	if box then
		-- box braids fall round the head the way long hair does: in front of the ears they run back (over the
		-- top, past the temples), behind them they turn down the head's own slope (gravity along the surface,
		-- a little back: each keeps its place round the head), so the side braids leave the scalp at the
		-- sides and the back ones fan across the back - the comb flow alone took every braid over the skull
		-- into one tail at the nape
		local back = flow
		flow = function(x, y, z, nx, ny, nz)
			local tx, ty, tz = back(x, y, z, nx, ny, nz)
			-- (at the ears' height the turn waits until behind them)
			local zk = lerp(0.12, -0.1, smoothstep(0.1, 0.32, y))
			local k = smoothstep(zk, zk + 0.22, z)
			if k <= 0 then
				return tx, ty, tz
			end
			local d = -ny + 0.35 * nz
			local gx, gy, gz = Kit.norm3(-nx * d, -1 - ny * d, 0.35 - nz * d)
			if gx == 0 and gy == 0 and gz == 0 then
				return tx, ty, tz
			end
			return Kit.norm3(lerp(tx, gx, k), lerp(ty, gy, k), lerp(tz, gz, k))
		end
	end
	local hang = 0.4 + 0.85 * L
	-- (a thick plait's run over the scalp needs fewer rings than its hanging part; a thin box braid keeps
	-- them all: halved, its run was a chain of straight 0.2-stud rods cutting across the skull's curve)
	H.sparseTop = not box
	-- a dark sheet low on the back of the head behind the hanging braids: between them more braids in
	-- shadow, not the neck (the parted scalp still shows over the top and the sides, where the braids lie on it)
	-- (box braids fan out over the back of the head with the parted scalp between them: their sheet starts
	-- only where they leave it and stays behind the head, its locks rounded like braids - higher up and
	-- reaching round to the ears it lay between them as a flat dark panel. At medium detail the braids are too
	-- few to hide its top edge, a dark band across the nape: none there)
	if H.lod == "full" or (H.lod == "medium" and not box) then
		fill(H, flow, hang * 0.55, "HairBraid", 0.7, box and 16 or 14, box and { th0 = 2.05, az = 1.35, amp = 0.03 } or nil)
	end
	-- box braids at full detail: one braid out of the middle of each section (a lattice dropped over the
	-- sections left some empty and doubled others: bare squares over the forehead), its place jittered a
	-- little; farther away a lattice spread is as good
	local sectionRoots
	-- the braids of one row run back over the sections behind their own: each steers into one of four lanes
	-- side by side across its row (by its section, in turn), so they lie beside one another and cover the
	-- row toward the crown and the back instead of piling up in one line with bare scalp between rows
	local LANES = { 0.125, -0.375, 0.375, -0.125 }
	if box and H.lod == "full" then
		sectionRoots = {}
		local rng = MeshKit.Rng(H.seed + 77)
		local ox, oy, oz = 0, S.cy - 0.25, 0.05
		local nRows = #rows
		for i = 1, nRows do
			for j = 0, 12 do
				local lane = rows[i] + LANES[j % 4 + 1] * dpsi
				local psi = rows[i] + rng:Range(-0.12, 0.12) * dpsi
				local b = b0 + (j + rng:Range(-0.12, 0.12)) * BSTEP
				if b > 1.45 then
					break
				end
				-- the scalp point with these angles: along the ray from the axis point (inside the skull)
				local dx, dy, dz = Kit.norm3(math.tan(psi), 1, math.tan(b))
				local lo, hi = 0, 1.6
				for _ = 1, 18 do
					local mid = (lo + hi) * 0.5
					if S.f(ox + dx * mid, oy + dy * mid, oz + dz * mid) < 0 then
						lo = mid
					else
						hi = mid
					end
				end
				local t = (lo + hi) * 0.5
				local x, y, z = ox + dx * t, oy + dy * t, oz + dz * t
				local c, _, _, da = H.cut.cov(x, y, z)
				local rnd = rng:Next()
				if da and smoothstep(0.5, 0.9, c / dens) >= 0.5 then
					local nx, ny, nz = S.normal(x, y, z)
					sectionRoots[#sectionRoots + 1] = { x, y, z, nx, ny, nz, da, c, rnd, lane }
				end
			end
		end
	end
	-- braids: thick plaits (the weave modelled); box braids: many thin ones (a cord with the plait's crossings
	-- in its tone). Each is glued to the scalp from its root (lift 0, stick 1: a plait is braided flat against
	-- the head and only hangs once the head turns under), its root under the skin and the cord out of the scalp
	-- and lying on it within ~0.05 studs (it never runs half buried from a hairline section to the crown). Its
	-- length is that run over the scalp plus the hanging length (one from the front hairline hangs as low as
	-- one from the nape - it does not end on the back of the head). A box braid's run on the scalp has rings
	-- enough to bend with the skull (9 a stud: chords sag < 0.004 into it), its hanging run fewer (5: it hangs
	-- straight); the budget leaves out the lowest ones first (under the braids hanging over them)
	local laneK = 1 / (0.25 * dpsi)
	local function flowFor(r)
		local lane = r[10]
		if not lane then
			return nil
		end
		-- the comb flow plus a sideways pull toward the braid's lane (round the rows' axis), full strength a
		-- quarter of a row off it - over the top only: the rows' planes all meet where their axis leaves the
		-- back of the head, so lanes held down the back would gather every braid into one tail at the nape
		return function(x, y, z, nx, ny, nz)
			local tx, ty, tz = flow(x, y, z, nx, ny, nz)
			local yy = y - S.cy + 0.25
			local e = clamp((lane - psiOf(x, y)) * laneK, -1, 1) * 0.7 * smoothstep(0.2, 0.45, yy)
			local px, py = yy, -x
			local l = math.sqrt(px * px + py * py)
			if l < 1e-6 then
				return tx, ty, tz
			end
			px, py = px / l * e, py / l * e
			local d = px * nx + py * ny
			return Kit.norm3(tx + px - nx * d, ty + py - ny * d, tz - nz * d)
		end
	end
	local accept = function(x, y, z, da, c)
		-- (in a section, not on a parting: the coverage relative to the stipple's density)
		return smoothstep(0.5, 0.9, c / dens)
	end
	if box then
		-- the ears: a braid that passes one (falling down the side, or run back over it from the temple) lies over
		-- it - lifted out of an ellipsoid round the ear (its outer half, the braid's radius clear of the
		-- ear's free back edge), never through it
		local earX
		do
			local lo, hi = 0.1, 0.9
			for _ = 1, 16 do
				local mid = (lo + hi) * 0.5
				if S.f(mid, -0.09, 0.15) < 0 then
					lo = mid
				else
					hi = mid
				end
			end
			earX = lo
		end
		local function overEars(pts)
			for i = 2, #pts do
				local p = pts[i]
				local dy, dz = (p[2] + 0.09) / 0.2, (p[3] - 0.14) / 0.12
				local q = dy * dy + dz * dz
				-- (only beside the head: not a braid hanging behind the jaw, inside the ear's line)
				if q < 1 and abs(p[1]) > earX - 0.08 then
					local xo = earX + 0.12 * math.sqrt(1 - q)
					if abs(p[1]) < xo then
						p[1] = p[1] < 0 and -xo or xo
					end
				end
			end
			return pts
		end
		-- (built in an order that interleaves round the head - a van der Corput sequence over the azimuth, the
		-- higher root first within a slot - so a triangle budget that runs out leaves braids all round it:
		-- built from the top down, a far one was nine braids off the midline over bald sides; and 3-sided far
		-- away, a few more of them for the same triangles)
		local function vdc(q)
			local k, f = 0, 0.5
			for _ = 1, 5 do
				if q % 2 == 1 then
					k += f
				end
				q //= 2
				f *= 0.5
			end
			return k
		end
		Parts.Tubes(H, { n = 100, minN = 10, section = "boxbraid", r = 0.03, flow = flow, flowFor = flowFor, lift = 0, stick = 1, grav = 1,
			stiff = 0.3, sides = H.lod == "low" and 3 or 4, hangSides = 3, ringsPer = 4.5, ringsGlued = 8, rVar = 0.08, frizz = 0.08,
			lodK = { full = 1, medium = 0.5, low = 0.32 }, len = function()
				return 1.5
			end, hangLen = function(r)
				return hang * (0.9 + 0.2 * r[9])
			end, order = function(r)
				return vdc(floor((math.atan2(r[1], r[3]) + pi) / (2 * pi) * 32) % 32) - 0.01 * r[2]
			end, sinkRoot = 0.8, off = function(u, _, r0, len)
				-- (lying on the scalp within ~0.05 of the root; a braid from the front lies over the braids rooted
				-- further back in its lane: it rises onto them as it runs back over the head)
				return r0 * (lerp(0.2, 0.88, smoothstep(0, 0.05 / max(len, 0.1), u)) + 1.1 * smoothstep(0.25, 0.8, u * len))
			end, hang = { prefix = "HairBraid" }, tip = "dome", roots = sectionRoots, rootsEven = true, rootJitter = 0.5, accept = accept,
			bend = overEars, share = 0.95 })
	else
		Parts.Tubes(H, { n = 26, minN = 6, section = "braid", period = 0.13, r = 0.038, flow = flow, lift = 0, stick = 1, free = 0.5, grav = 1,
			stiff = 0.3, sides = 4, lodK = { full = 1, medium = 0.5, low = 0.32 }, len = function(r)
				local front = 1 - smoothstep(0.4, 1.4, r[7])
				return hang * (0.9 + 0.2 * r[9]) * (1 - 0.2 * front)
			end, off = function(u, _, r0)
				return r0 * lerp(0.45, 0.9, smoothstep(0.03, 0.3, u)) + 0.004
			end, hang = { prefix = "HairBraid" }, tip = "dome", rootsEven = true, rootJitter = 0.5, accept = accept, share = 0.95 })
	end
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
	local n = H.lod == "low" and 7 or (H.lod == "medium" and 9 or floor(9 + 3 * H.density + 0.5))
	-- the rows' planes through an axis deep under the head: they run parallel from the hairline to the nape
	-- (no star where they would meet), the outer ones from the temples back over the ears
	local AXIS, PSI = 0.75, 0.82
	local _, region = Parts.RowLayout(H, n, 0.07, AXIS, PSI)
	local stand = STAND[H.htype] or 1
	-- between the rows the scalp shows (the head's own skin tone) with a fine stipple of new growth; the
	-- partings are thin clean lines. The braids lie over the rows (no painted bands)
	Parts.Cap(H, { top = 0.004 * stand, side = 0.0035 * stand, pattern = "stubble", flow = "back", capT = 0.6, material = "Plastic", region = region,
		shaved = 0.4, density = 0.14 + 0.15 * H.grow, grain = 0.6, streak = 0, edge = 0.05,
		hairline = H.hairline == "Natural" and "Straight" or H.hairline })
	local hang = H.len * SHRINK[H.htype] - 0.4
	-- far away the braided tails are not worth their triangles: the rows alone read as cornrows
	local tails = hang > 0 and H.lod ~= "low"
	-- (curlier hair braids into fuller, rounder rows)
	Parts.Cornrows(H, { n = n, r = 0.058 * (0.85 + 0.3 * H.thick) * (0.94 + 0.06 * stand) * min(1, 11 / n), axis = AXIS, psiMax = PSI, stitch = 0.03,
		tails = tails, tail = function(i)
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
	if COILY[H.htype] then
		-- coily hair pulled back: a slight layer of tight coils brushed toward the tie (matte, coil texture)
		Parts.Cap(H, { top = 0.012, side = 0.012, pattern = "coil", grain = 2.4, flow = "tie", flowOpts = { p = tie }, capT = 0.5,
			material = "Fabric", reflectance = 0 })
	else
		-- (its streaks soft: hard ones read as scratches, wood grain)
		Parts.Cap(H, { top = 0.012, side = 0.012, pattern = "strands", flow = "tie", capT = 0.4, streak = 0.3, contrast = 0.8,
			material = H.htype == "Straight" and "SmoothPlastic" or "Plastic" })
	end
	if H.lod ~= "low" and not COILY[H.htype] then
		-- hair pulled back tight from the hairline into the tie
		Parts.Clumps(H, { n = 110, seed = 9, sides = H.lod == "full" and 4 or 3, flow = flow, lift = 0, stick = 1, grav = 0, stiff = 0.2,
			free = 2, glue = true, len = function(r)
				local dx, dy, dz = tie[1] - r[1], tie[2] - r[2], tie[3] - r[3]
				return math.sqrt(dx * dx + dy * dy + dz * dz) * 1.08
			end, w = 0.026, h = 0.005, off = function(u)
				-- (flush with the cap: pulled tight, no gap under each lock)
				return 0.011 + 0.002 * u
			end, layerK = 1.02, flat = 0.6, bend = function(pts)
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
			end, maxRings = 10, taper = 0.85, twist = 0.2, share = 0.42 })
	end
	local hang = 0.4 + 0.9 * L
	local pal = H.pal
	local lum = pal.lum
	if COILY[H.htype] then
		-- coily hair gathers into a puff: a big, slightly squashed ball of coil clusters (lumpy outline, light
		-- cluster tops, dark gaps between them, a fuzzy fine grain), matte
		local pr = 0.14 + 0.16 * L * SHRINK[H.htype] + 0.03 * H.volume
		local ex, ey, ez = 1.15, 0.9, 1.05
		local cx, cy, cz = tie[1], tie[2] + 0.03, tie[3] + pr * ez * 0.8
		local m = Parts.Piece(H, "HairTail01", { material = "Fabric", castShadow = true }).mesh
		local seed = H.seed % 1000
		local worley = Kit.Worley(H.seed % 9973 + 17)
		local full = H.lod == "full"
		local darkLift = clamp((0.16 - lum) / 0.16, 0, 1) * 0.1
		-- the clusters, by direction on the ball (~0.05-stud cells on its surface)
		local cf = 0.85 / 0.06 * pr
		local function cluster(dx, dy, dz)
			local wx = 0.25 * MeshKit.Noise(dx * 3, dy * 3, dz * 3, seed + 5)
			local f1, f2 = worley((dx + wx) * cf, (dy - wx) * cf, (dz + wx) * cf)
			return 1 - smoothstep(0.05, 0.55, f1), smoothstep(0.0, 0.25, f2 - f1)
		end
		local step = MeshKit.Step
		MeshKit.Ellipsoid(m, cx, cy, cz, pr * ex, pr * ey, pr * ez, { rings = full and 24 or 10, sides = full and 34 or 14,
			radial = function(dx, dy, dz)
				-- (a cellular lookup and two noises a vertex)
				step(6)
				local top = cluster(dx, dy, dz)
				return 1 + 0.07 * MeshKit.Noise(dx * 2.2, dy * 2.2, dz * 2.2, seed) + (full and 0.07 or 0.04) * (top - 0.5)
			end,
			color = function(x, y, z, dx, dy, dz)
				step(6)
				local top, crev = cluster(dx, dy, dz)
				local r, g, b = pal.at(0.5, 0.7, x)
				local k = (0.95 + 0.45 * top) * (0.85 + 0.15 * crev) * (0.92 + 0.16 * MeshKit.Noise(x * 60, y * 60, z * 60, seed + 2))
				local l = darkLift * (0.5 + 0.7 * top)
				return r * k + l, g * k + l * 0.82, b * k + l * 0.62
			end })
		MeshKit.ComputeNormals(m)
		if H.lod ~= "low" then
			-- coil clusters half sunk in the puff (3-4 short springs each): bumps that break up its surface and
			-- its outline, bouncing with it
			local rng = MeshKit.Rng(H.seed + 97)
			local out = H.out
			local nc = floor((full and 30 or 10) * (H.nScale or 1) + 0.5)
			local rx, ry, rz = pr * ex, pr * ey, pr * ez
			for i = 1, nc do
				-- spread over the puff (a Fibonacci lattice), the part against the head left out
				local zc = 1 - (i - 0.5) / nc * 1.7
				local rr = math.sqrt(max(0, 1 - zc * zc))
				local a = i * 2.399963 + rng:Range(-0.3, 0.3)
				local dx, dy, dz = rr * cos(a), zc, rr * sin(a)
				if dz > -0.55 then
					local nx, ny, nz = Kit.norm3(dx / rx, dy / ry, dz / rz)
					local px, py, pz = cx + dx * rx, cy + dy * ry, cz + dz * rz
					local tx, ty, tz = Kit.norm3(Kit.cross(nx, ny, nz, 0.3, 1, 0.2))
					if tx == 0 and ty == 0 and tz == 0 then
						tx, ty, tz = 1, 0, 0
					end
					local bx2, by2, bz2 = Kit.cross(nx, ny, nz, tx, ty, tz)
					local rnd = rng:Next()
					for _ = 1, 3 + floor(rng:Next() * 1.99) do
						local ang, dist = rng:Range(0, 2 * pi), 0.012 * rng:Range(0.3, 1.6)
						local rad = 0.011 * (0.75 + 0.5 * rng:Next())
						local sunk = rad * 0.85
						local ox = (tx * cos(ang) + bx2 * sin(ang)) * dist
						local oy = (ty * cos(ang) + by2 * sin(ang)) * dist
						local oz = (tz * cos(ang) + bz2 * sin(ang)) * dist
						local qx, qy, qz = px + ox - nx * sunk, py + oy - ny * sunk, pz + oz - nz * sunk
						local len = 0.022 * (0.7 + 0.6 * rng:Next())
						local ddx, ddy, ddz = Kit.norm3(nx + rng:Range(-0.35, 0.35), ny + rng:Range(-0.3, 0.3), nz + rng:Range(-0.35, 0.35))
						local base = {}
						for k = 0, 3 do
							local u = k / 3
							base[#base + 1] = { qx + ddx * len * u, qy + ddy * len * u, qz + ddz * len * u }
						end
						local hp = Kit.Helix(base, out, rad, clamp(len / (rad * 2.2), 1, 2), rng:Range(0, 2 * pi), 4)
						local tube = rad * 0.5
						Kit.Tube(m, hp, {
							sides = 3, out = out, rad = tube, tip = "point",
							r = function(t)
								return tube * (1 - 0.35 * smoothstep(0.75, 1, t))
							end,
							color = function(t, ang2)
								local r, g, b = pal.at(rnd, 0.6 + 0.4 * t, px, nil, py, (1 - t) * len)
								local k = (0.95 + 0.3 * smoothstep(-0.5, 0.9, math.sin(ang2))) * (0.92 + 0.15 * t)
								return r * k + darkLift, g * k + darkLift * 0.82, b * k + darkLift * 0.62
							end,
						})
					end
				end
			end
		end
		H.bounce = H.bounce or {}
		H.bounce.HairTail01 = true
		H.fx = { kind = "bounce", stiff = 0.6, mass = 1.2 }
	else
		-- a full tail (never a stub: down past the nape, at least ~0.7 nominal) with volume at the tie
		Parts.PonyTail(H, { tie = tie, dir = { 0, -0.35, 1 }, len = max(0.7, hang * SHRINK[H.htype] * 1.3), n = 70, r0 = 0.09 + 0.02 * H.volume, w = 0.06, h = 0.016,
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
		-- (a rounded crest grown along the rays from the head's centre: its walls cannot fold over the crown)
		local t = 0.06 + 0.12 * L * SHRINK[H.htype]
		local mask = function(x, y, z)
			return (0.135 - abs(x)) * 3.5
		end
		-- (a fine grid across the crest: its rounded shoulders span several columns, no steep slivers)
		-- (the crest's texture is drawn at its raised surface, which the radial growth spreads ~15% wider: the
		-- haired strip is as much wider)
		coilyCap(H, { thickness = t, mask = mask, region = stripRegion(0.135), shaved = 0.18, bump = 0.005, edge = 0.03, radial = true,
			cols = H.lod == "full" and 84 or nil, rows = H.lod == "full" and 26 or nil })
		coilyFuzz(H, layerVol(S, t, mask), function(x, y, z, da, c)
			return (1 - smoothstep(0.08, 0.12, abs(x))) * smoothstep(0.6, 0.9, c)
		end)
		return
	end
	-- the crest: a filled ridge of hair along the strip (the mass the spikes rise out of: no painted strip
	-- showing between them), thick overlapping clumps spiking up and back out of it
	local t = 0.045 + 0.05 * L
	local mask = function(x, y, z)
		return (0.125 - abs(x)) * 4
	end
	Parts.Volume(H, { vol = layerVol(S, t, mask), layerT = t, layerMask = mask, region = stripRegion(0.135), shaved = 0.18, edge = 0.03,
		bump = 0.008, bumpFreq = 6, radial = true, top = 0.02, side = 0.006, pattern = "strands", flow = "up", capT = 0.35, material = "Plastic",
		cols = H.lod == "full" and 84 or nil, rows = H.lod == "full" and 26 or nil })
	local up = Kit.Flow(S, "up")
	Parts.Clumps(H, { n = 84, seed = 12, sides = H.lod == "full" and 4 or 3, flow = up, lift = 1, stick = 0, grav = 0.08, stiff = 0.85,
		free = 0, accept = function(x, y, z, da, c)
			return (1 - smoothstep(0.08, 0.12, abs(x))) * smoothstep(0.5, 0.9, c)
		end, len = function(r)
			return (0.14 + 0.2 * L) * (0.75 + 0.4 * r[9]) * (1 - 0.35 * smoothstep(1.8, 2.8, r[7]))
		end, w = 0.04, h = 0.024, flat = 0.3, off = function(u)
			return t * 0.55
		end, dir = function(r)
			-- the crest leans back a little and its fins converge into spikes
			return { r[4] - r[1] * 1.2, r[5] + 0.15, r[6] + 0.35 }
		end, twist = 0.6, maxRings = 8, taper = 0.7, tipW = 0.15, tips = 0.4, share = 0.8 })
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
			coilyCap(H, { thickness = t, mask = mask, region = region, shaved = 0.2, bump = 0.005, edge = 0.03 })
			coilyFuzz(H, layerVol(S, t, mask), function(x, y, z, da, c)
				return smoothstep(0.32, 0.4, y) * smoothstep(0.6, 0.9, c)
			end)
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
	Parts.Cap(H, { top = 0.026, side = 0.006, pattern = "strands", flow = "side", flowOpts = { dir = 1 }, capT = 0.35, region = region,
		shaved = 0.2, material = "Plastic" })
	-- swept across to the right and back; over the forehead up and back (never down over the eyes)
	local flow = function(x, y, z, nx, ny, nz)
		local front = smoothstep(-0.1, -0.35, z)
		local back = smoothstep(0.2, 0.5, z)
		local vx, vy, vz = 1 - 0.5 * back, -0.25 + 0.3 * front - 0.3 * back, 0.3 + 0.2 * z + 0.7 * front + 0.3 * back
		local d = vx * nx + vy * ny + vz * nz
		return Kit.norm3(vx - nx * d, vy - ny * d, vz - nz * d)
	end
	local wave = H.htype == "Wavy" and { amp = 0.01, lam = 0.24, phase = wavePhase(H) } or nil
	-- the long top swept over to the right: a sheet of locks from the left edge of the top over the crown, ending
	-- over the right side (its ends pointed and uneven), slim locks and fine strands over it
	local vol = H.volume
	Parts.Curtain(H, {
		az0 = 1.5 * pi - 1.4, az1 = 1.5 * pi + 1.45, th = function(az)
			-- just inside the top region's left edge (and the front hairline)
			local da = abs(az - pi)
			local yl = lerp(0.27, 0.14, smoothstep(1.7, 2.8, da)) + 0.03
			local lo, hi = 0.1, 2.4
			for _ = 1, 12 do
				local mid = (lo + hi) * 0.5
				local _, y = Kit.ScalpAt(S, az, mid, 0)
				if y > yl then
					lo = mid
				else
					hi = mid
				end
			end
			return min(lo, Kit.HairlinePolar(S, H.cut, az, 0.02))
		end, len = function(az, rnd)
			return (0.85 + 0.3 * L) * lerp(1, 0.5, smoothstep(0.7, 1.45, abs(az - 1.5 * pi))) * (0.94 + 0.12 * rnd)
		end, flow = flow, off = function(u)
			return 0.03 + 0.022 * smoothstep(0, 0.25, u) * (1 + vol * 0.6) - 0.012 * u
		end, stick = 0.92, grav = 0.25, stiff = 0.35, free = 0.85, clipY = 0.21, wave = wave,
		shade = 1.0, innerShade = 0.55, half = 0.005, rings0 = 16, innerStride = 3, material = "Plastic", streakK = 0.2,
		cols = 46, locks = { w = 3, amp = 0.009, root = 0.002, pointK = 0.2 },
	})
	-- slim locks lying in the sheet (half sunk: raised strands of it, not shavings on it), a touch lighter
	Parts.Clumps(H, { n = 56, seed = 13, sides = 3, flow = flow, lift = 0.1, stick = 0.85, grav = 0.25, stiff = 0.35, accept = function(x, y, z, da, c)
		return region(x, y, z, da) * smoothstep(0.7, 0.95, c)
	end, bend = function(pts, r)
		-- the top's locks end at the cut line (a little over it), never hanging over the shaved back
		local yl = lerp(0.27, 0.14, smoothstep(1.7, 2.8, r[7])) - 0.04
		for i = 3, #pts do
			if pts[i][2] < yl then
				return table.move(pts, 1, i, 1, {})
			end
		end
		return pts
	end, len = function(r)
		return (0.22 + 0.3 * L) * (0.8 + 0.35 * r[9])
	end, w = 0.022, h = 0.005, flat = 0.5, off = function(u)
		return 0.038 + 0.016 * smoothstep(0, 0.3, u) * (1 + vol * 0.5)
	end, wave = wave, twist = 0.3, maxRings = 10, tips = 0.5, material = "Plastic", taper = 0.55, tipW = 0.12, layerK = 1.1,
		share = 0.45 })
	Parts.Fur(H, { n = 300, flow = flow, lift = 0.2, len = function(r)
		return 0.05 + 0.06 * r[9]
	end, off = 0.045, share = 0.35, accept = function(x, y, z, da, c)
		return region(x, y, z, da) * smoothstep(0.7, 0.95, c)
	end })
	Parts.Flyaways(H, { n = 10, flow = flow, accept = function(x, y, z, da, c)
		return region(x, y, z, da) * c
	end, share = 0.08 })
	H.fx = { kind = "bounce", stiff = 0.6, mass = 0.9 }
end

-- the wolf cut: a shaggy, layered cut - a sheet of choppy locks from the crown over the back and sides to
-- the neck, its ends flicking out (the mullet line), short choppy layers lifted on the crown, a fringe stopping
-- above the brows, fine strands and flyaways. Every layer has its own share of the budget (the back layer is the
-- style: it is built first, as the mass)
R["Wolf Cut"] = function(H)
	local S = H.S
	local L = H.len
	if CURLY[H.htype] then
		return longCurly(H)
	end
	Parts.Cap(H, { top = 0.03, side = 0.026, pattern = "strands", flow = "whorl", capT = 0.2, capK = 0.8, streak = 0.6, material = "Plastic" })
	local whorl = Kit.Flow(S, "down")
	local wave = { amp = H.htype == "Wavy" and 0.022 or 0.01, lam = 0.2, phase = wavePhase(H), rise = 0.08 }
	-- the back and side layer falls straight down the back and the sides (a little back at the temples)
	local fall = function(x, y, z, nx, ny, nz)
		local vx, vy, vz = 0.2 * x, -1, 0.15 + 0.5 * smoothstep(0.05, -0.35, z)
		local d = vx * nx + vy * ny + vz * nz
		return Kit.norm3(vx - nx * d, vy - ny * d, vz - nz * d)
	end
	-- the ends flick outward (the shag's flipped-out hem)
	local flick = function(pts)
		local n = #pts
		local i0 = floor(n * 0.72)
		for i = i0, n do
			local u = (i - i0) / max(1, n - i0)
			local p = pts[i]
			local ox, _, oz = Kit.norm3(p[1], 0, p[3] - 0.05)
			p[1] += ox * 0.045 * u * u
			p[3] += oz * 0.045 * u * u
			p[2] += 0.018 * u * u
		end
		return pts
	end
	Parts.Curtain(H, {
		cols = 52, az0 = -2.5, az1 = 2.5, th = function(az)
			-- under the crown layers: high on the back, lower round the sides to the temples
			return 1.08 - 0.12 * smoothstep(0.4, 1.6, abs(az)) + 0.04 * smoothstep(1.8, 2.5, abs(az))
		end, len = function(az, rnd)
			-- longest at the back (to the neck), shorter round the sides, shortest at the temples
			local a = abs(az)
			return (0.62 + 0.45 * L) * lerp(1, 0.62, smoothstep(0.5, 1.7, a)) * lerp(1, 0.75, smoothstep(1.9, 2.5, a))
				* (0.9 + 0.2 * rnd)
		end, flow = fall, off = function(u)
			return 0.03 + 0.014 * u
		end, stick = 0.8, grav = 1, stiff = 0.3, bend = flick, wave = wave, bodyOff = 0.07, hang = { prefix = "HairClump" },
		shade = 0.98, innerShade = 0.5, half = 0.005, rings0 = 16, innerStride = 2, material = "Plastic",
		locks = { w = 3, amp = 0.012, root = 0.004, pointK = 0.22, jag = 0.16 },
	})
	-- slim locks over the back layer: strand detail and a broken, flicked hem
	Parts.Clumps(H, { n = 46, seed = 16, sides = 3, flow = fall, lift = 0.04, stick = 0.85, grav = 1, stiff = 0.3,
		accept = function(x, y, z, da, c)
			return smoothstep(1.1, 2.0, da) * smoothstep(0.12, 0.24, y) * (1 - smoothstep(0.36, 0.44, y)) * smoothstep(0.6, 0.9, c)
		end, len = function(r)
			local a = abs(math.atan2(r[1], r[3]))
			return (0.5 + 0.4 * L) * lerp(1, 0.6, smoothstep(0.5, 1.7, a)) * (0.85 + 0.3 * r[9])
		end, w = 0.024, h = 0.005, flat = 0.4, off = function(u)
			return 0.046 + 0.014 * u
		end, bend = flick, wave = wave, twist = 0.4, bodyOff = 0.085, hang = { prefix = "HairClump" }, maxRings = 9, tips = 0.6,
		material = "Plastic", taper = 0.55, tipW = 0.1, share = 0.16 })
	-- the crown: short choppy layers lifted for volume, lying over the back layer's roots
	Parts.Clumps(H, { n = 280, seed = 14, sides = 3, flow = whorl, lift = 0.3, stick = 0.5, grav = 0.4, stiff = 0.4,
		accept = function(x, y, z, da, c)
			return smoothstep(0.24, 0.36, y) * smoothstep(0.6, 0.9, c)
		end, len = function(r)
			return (0.15 + 0.12 * L) * (0.75 + 0.5 * r[9])
		end, w = 0.026, h = 0.005, flat = 0.5, off = function(u)
			return 0.04 + 0.022 * u
		end, wave = wave, twist = 0.6, jitter = { amp = 0.3, freq = 6 }, maxRings = 6, tips = 0.5, material = "Plastic",
		taper = 0.55, tipW = 0.12, share = 0.44 })
	-- the fringe: choppy, falling forward, stopping above the brows
	Parts.Clumps(H, { n = 30, seed = 15, sides = 3, flow = Kit.Flow(S, "forward"), lift = 0.2, stick = 0.6, grav = 0.6, stiff = 0.4,
		free = 0.6, accept = function(x, y, z, da, c)
			return (1 - smoothstep(0.5, 0.9, da)) * smoothstep(0.5, 0.9, c)
		end, len = function(r)
			return (0.12 + 0.08 * L) * (0.8 + 0.4 * r[9])
		end, w = 0.024, h = 0.005, flat = 0.5, off = function(u)
			return 0.035 + 0.01 * u
		end, bend = function(pts)
			-- never below the brows
			for _, p in ipairs(pts) do
				if p[2] < 0.2 then
					p[2] = 0.2
				end
			end
			return pts
		end, twist = 0.5, maxRings = 8, tips = 0.5, material = "Plastic", taper = 0.55, tipW = 0.12, share = 0.12 })
	Parts.Fur(H, { n = 200, flow = whorl, lift = 0.4, len = function(r)
		return 0.05 + 0.05 * r[9]
	end, off = 0.035, share = 0.12, accept = function(x, y, z, da, c)
		return smoothstep(0.6, 0.9, c) * smoothstep(0.2, 0.35, y)
	end })
	Parts.Flyaways(H, { n = 18, flow = whorl, share = 0.06 })
	H.fx = { kind = "swing", stiff = 0.3, mass = 0.9 }
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
		-- regrowth on a shaved head: a skin-thin stubble layer (texture only, the scalp's own normals and
		-- material), sparse enough that the skin shows through as a shadow
		local stand = STAND[htype] or 1
		Parts.Cap(H, { top = (0.0025 + 0.002 * H.grow) * stand, side = (0.002 + 0.0015 * H.grow) * stand, density = clamp(0.12 + 0.3 * H.grow, 0, 0.42),
			pattern = "stubble", flow = "whorl", grain = 0.75, capT = 0.8, edge = 0.05, streak = 0, material = "SmoothPlastic",
			reflectance = 0, cols = full and 64 or (H.lod == "medium" and 40 or nil), rows = full and 28 or (H.lod == "medium" and 16 or nil) })
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
