-- BuilderHair: the hair on the head (server side), split verbatim out of BuilderHead so the hair and
-- the head have separate owners. Behaviour is identical to the pre-split BuilderHead (proven by
-- /tmp/claude-0/tests/anatomy_foundation/hair_split_equivalence.py).
-- * every Looks.HairStyles id x 5 hair types (shrinkage, curl size, sheen, material), fades with
--   gradient bands and a sharp line-up, hairlines and parts, visible growth stages, Beam strands
--   (tag HairStrand) for depth, sway joints (tag HairSway) on locs/braids/long hair and a bounce
--   joint on curl clusters (CONTRACTS section 5)
-- * hidden under headgear / robe hoods (SetHairHidden / ApplyHairHidden), wet hair (Wet, from SetSweat)
-- Shares A's part budget, the face layout and the head-surface helpers with BuilderHead (Head.Shared),
-- which requires this module while it loads: BuilderHead is therefore required lazily, on first use.
-- Builder.Cosmetics runs Hair.Build after the face and before the beard; BuilderHead keeps
-- Head.Hair / Head.SetHairHidden / Head.ApplyHairHidden as forwards for older callers.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))

local Hair = {}

local V3, CF, ANG, SMOOTH = Kit.V3, Kit.CF, Kit.ANG, Kit.SMOOTH
local lerpColor, darken = Kit.lerpColor, Kit.darken
local mk, getFolder, part = Kit.mk, Kit.getFolder, Kit.part
local FABRIC, SAND = Enum.Material.Fabric, Enum.Material.Sand
local clamp = math.clamp

-- BuilderHead and the helpers it shares (Head.Shared), bound on first use: BuilderHead requires this
-- module at load time, so requiring it back here at load time would be a require cycle
local Head
local lum, skinOf, joint, axisCF, surfPoint, surfCF, surfacePath, countParts, extraOf
local A_BUDGET, FACE_CAP, BEARD_RESERVE, HAIR_MAX
local function bind()
	if Head then
		return
	end
	local H = require(script.Parent:WaitForChild("BuilderHead"))
	local S = H.Shared
	lum, skinOf, joint, axisCF = S.lum, S.skinOf, S.joint, S.axisCF
	surfPoint, surfCF, surfacePath = S.surfPoint, S.surfCF, S.surfacePath
	countParts, extraOf = S.countParts, S.extraOf
	A_BUDGET, FACE_CAP, BEARD_RESERVE, HAIR_MAX = S.A_BUDGET, S.FACE_CAP, S.BEARD_RESERVE, S.HAIR_MAX
	Head = H
end

------------------------------------------------------------------------
-- Hair
------------------------------------------------------------------------
-- per hair type: shrinkage (share of the stretched length a hanging style shows), curl size,
-- sheen (Reflectance; above ~0.08 it mirrors the sky), material and sway physics
local HAIR_TYPES = {
	Straight = { shrink = 1, curl = 0, radius = 1, sheen = 0.04, mat = SMOOTH, stiff = 0.1, mass = 0.8 },
	Wavy = { shrink = 0.9, curl = 0.35, radius = 1, sheen = 0.03, mat = SMOOTH, stiff = 0.2, mass = 0.9 },
	Curly = { shrink = 0.75, curl = 0.7, radius = 1.2, sheen = 0.015, mat = FABRIC, stiff = 0.45, mass = 1 },
	Coiled = { shrink = 0.6, curl = 0.9, radius = 0.8, sheen = 0, mat = SAND, stiff = 0.7, mass = 1.2 },
	Kinky = { shrink = 0.5, curl = 1, radius = 0.65, sheen = 0, mat = SAND, stiff = 0.75, mass = 1.25 },
}
local CURLY = { Curly = true, Coiled = true, Kinky = true }
-- styles with a dedicated branch below; any other id draws Looks.HairStyleBase[id] (or Fade)
local DRAWN = {}
for _, id in ipairs({
	"Bald", "Buzz Cut", "Crew Cut", "Fade", "Low Fade", "Mid Fade", "High Fade", "Afro", "High Top", "Short Dreads",
	"Dreadlocks", "Twists", "Braids", "Cornrows", "Short Curly", "Long Curly", "Messy Hair", "Slick Back", "Undercut",
	"Mohawk", "Caesar Cut", "Long Hair", "Ponytail", "Wolf Cut", "Modern Athlete", "Taper Fade", "Textured Crop",
	"Curly Top", "Burst Fade", "360 Waves", "Box Braids",
}) do
	DRAWN[id] = true
end
local SHORT = {
	["Buzz Cut"] = 0.035, ["Crew Cut"] = 0.06, Fade = 0.08, ["Low Fade"] = 0.08, ["Mid Fade"] = 0.08, ["High Fade"] = 0.09,
	["Caesar Cut"] = 0.06, ["Modern Athlete"] = 0.08, ["Taper Fade"] = 0.08, ["Textured Crop"] = 0.07, ["360 Waves"] = 0.03,
}

-- lower bound on the part count of the pre-overhaul hair (the CONTRACTS 16 B budget baseline), from
-- the old builder's own counts; a style it did not have counts as its Looks.HairStyleBase style
local OLD_SHORT = {
	["Buzz Cut"] = 1, ["Crew Cut"] = 2, Fade = 2, ["Low Fade"] = 2, ["Mid Fade"] = 2, ["High Fade"] = 2,
	["Caesar Cut"] = 2, ["Modern Athlete"] = 9,
}
local function oldHairParts(hair, style)
	style = Looks.HairStyleBase[style] or style
	local d = clamp(tonumber(hair.density) or 0.7, 0, 1)
	local L = clamp((tonumber(hair.length) or 0.5) + (tonumber(hair.growth) or 0) * 0.6, 0, 1.5)
	local htype = hair.type or "Straight"
	local floor = math.floor
	-- the old top texture: curl bumps on curly types, four wave bands on wavy hair
	local function tex(count)
		return CURLY[htype] and floor(count * (0.5 + d)) or (htype == "Wavy" and 4 or 0)
	end
	if style == "Bald" then
		return 0
	elseif OLD_SHORT[style] then
		return OLD_SHORT[style] + tex(18)
	elseif style == "Afro" then
		return 2 + floor(floor(34 * (0.5 + d)) * 0.94) -- a few curls were skipped in front of the face
	elseif style == "High Top" then
		return 2
	elseif style == "Mohawk" then
		return 7
	elseif style == "Slick Back" then
		return 6 + (L > 0.6 and 2 or 0)
	elseif style == "Undercut" then
		return 7 + tex(10)
	elseif style == "Messy Hair" then
		return 1 + floor(10 + d * 10)
	elseif style == "Cornrows" then
		local rows = 5 + floor(d * 3)
		return 1 + rows * 4 + (L > 0.45 and floor(rows / 2) * 2 or 0)
	elseif style == "Dreadlocks" or style == "Twists" or style == "Braids" then
		local n = floor(8 + d * 12)
		local segs = style == "Twists" and 1 or (L > 0.7 and 3 or 2)
		return 1 + floor(n * 0.75) * segs + floor(n / 2) * 2
	elseif style == "Short Dreads" then
		return 47 + floor(23 * d)
	elseif style == "Short Curly" then
		return 1 + floor(28 * (0.6 + d))
	elseif style == "Long Curly" then
		return 2 + floor(26 * (0.6 + d)) + floor(6 + d * 6) * (L > 0.6 and 3 or 2)
	elseif style == "Long Hair" then
		return 2 + 3 * (L > 0.75 and 3 or 2) + tex(12)
	elseif style == "Wolf Cut" then
		return 19 + tex(12)
	elseif style == "Ponytail" then
		return 3 + (L > 0.6 and 4 or 3)
	end
	return 1 + tex(14)
end

local function hairPalette(hair)
	local base = Looks.Color(hair.color, Color3.fromRGB(25, 20, 18))
	local alt = Looks.Color(hair.hcolor, Color3.fromRGB(200, 160, 90))
	local dye = hair.dye or "None"
	return function(index, t, x)
		if dye == "Tips" then
			return t > 0.62 and alt or base
		elseif dye == "Ombre" then
			return lerpColor(base, alt, t)
		elseif dye == "Streaks" then
			return (index % 3 == 0) and alt or base
		elseif dye == "Split" then
			return (x or 0) > 0 and alt or base
		elseif hair.hl then
			return (index % 4 == 0) and lerpColor(base, alt, 0.75) or base
		end
		return base
	end
end

local function hairMaterial(htype)
	return (HAIR_TYPES[htype] or HAIR_TYPES.Straight).mat
end

-- detail-dependent count: full, medium, low
local function lod(H, full, medium, low)
	if H.detail == "full" then
		return full
	elseif H.detail == "medium" then
		return medium
	end
	return low
end

local function hpart(H, name, size, localCF, color, shape, material, transparency, anchor)
	return mk(H.folder, anchor or H.head, name, size, H.hcf * localCF, color, shape or "Ellipsoid", material or H.mat, transparency)
end

-- a decoration part (curl, tuft, wave band...) queued until the cut's structure exists; hairBuild then
-- draws as many as the part budget leaves room for, in queue order. The material is resolved now
-- (styles swap H.mat around their curl clusters).
local function later(H, name, size, localCF, color, shape, material, transparency, anchor)
	local mat = material or H.mat
	H.deco[#H.deco + 1] = function()
		hpart(H, name, size, localCF, color, shape, mat, transparency, anchor)
	end
end

-- parts the cut may still add before reaching its cap (structural choices that scale use this); one
-- part stays reserved for the strand anchor until it exists (strands themselves cost no parts)
local function room(H, reserve)
	local anchor = (H.anchor or H.maxStrands <= 0) and 0 or 1
	return H.cap - countParts(H.folder) - (reserve or 0) - anchor
end

-- invisible part that carries every strand attachment (never parented to the Head: getFolder's
-- destroy must clean them up on each rebuild)
local function strandAnchor(H)
	if not H.anchor then
		H.anchor = mk(H.folder, H.head, "StrandAnchor", V3(0.05, 0.05, 0.05), H.hcf, H.base, "Block", SMOOTH, 1)
	end
	return H.anchor
end

-- one Beam strand cluster from p0 (leaving along d0) to p1 (arriving along d1), head-local
local function strand(H, p0, d0, p1, d1, width, curve, idx, t0, t1, depth, transparency)
	if H.strands >= H.maxStrands then
		return nil
	end
	H.strands += 1
	local anchor = strandAnchor(H)
	local a0 = Instance.new("Attachment")
	a0.Name = "StrandRoot"
	a0.CFrame = axisCF(p0, d0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "StrandTip"
	a1.CFrame = axisCF(p1, d1)
	a1.Parent = anchor
	local len = (p1 - p0).Magnitude
	local c0 = darken(H.colorFn(idx, t0 or 0, p0.X), 0.82) -- roots read darker: depth
	local c1 = H.colorFn(idx, t1 or 1, p1.X)
	local b = Instance.new("Beam")
	b.Name = "Strand"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.CurveSize0 = len * curve
	b.CurveSize1 = len * curve
	b.Width0 = width
	b.Width1 = width * 0.3
	b.Segments = H.detail == "full" and 8 or 4
	b.FaceCamera = true
	b.LightInfluence = 1
	b.Color = ColorSequence.new(c0, c1)
	b.Transparency = NumberSequence.new(transparency or 0.05, math.min(1, (transparency or 0.05) + 0.35))
	b:SetAttribute("BaseCurve0", b.CurveSize0)
	b:SetAttribute("BaseCurve1", b.CurveSize1)
	b:SetAttribute("Depth", depth or 1)
	b:SetAttribute("DryColor0", c0)
	b:SetAttribute("DryColor1", c1)
	b.Parent = anchor
	CollectionService:AddTag(b, "HairStrand")
	return b
end

-- point on the current hair shell (H.capC / H.capR, head-local): polar angle th from the crown
-- (0 = top), azimuth ph (0 = back, pi = front, +pi/2 = the character's right)
local function shellDir(th, ph)
	return V3(math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph))
end
local function shellPoint(H, th, ph, out)
	local d = shellDir(th, ph)
	local r = H.capR
	return H.capC + V3(d.X * (r.X + out), d.Y * (r.Y + out), d.Z * (r.Z + out))
end

-- strands lying along the shell from (th0, ph0) to (th1, ph1)
local function shellStrand(H, th0, ph0, th1, ph1, width, lift, idx, curl)
	local p0 = shellPoint(H, th0, ph0, 0.004)
	local p1 = shellPoint(H, th1, ph1, 0.004 + lift)
	-- tangents: the direction of travel, bent outward a touch so the strand arcs over the shell
	local mid = shellPoint(H, (th0 + th1) / 2, (ph0 + ph1) / 2, 0.01 + lift)
	local d0 = (mid - p0)
	local d1 = (p1 - mid)
	return strand(H, p0, d0, p1, d1, width, 0.33 + 0.25 * (curl or 0), idx, 0, 1, 1)
end

-- loose flyaway strands over a short or medium cut (straight / wavy) or curl loops (curly types)
local function flyaways(H, count, len, yMinTh, yMaxTh)
	if not H.capC then
		return
	end
	local rng = Random.new(H.seed + 41)
	local w = (0.025 + 0.025 * H.thick) * H.s.X
	for i = 1, count do
		local th = rng:NextNumber(yMinTh or 0.15, yMaxTh or 1.2)
		local ph = rng:NextNumber(-2.4, 2.4)
		local dth = len * (0.6 + 0.6 * rng:NextNumber())
		if CURLY[H.htype] then
			-- a springy loop that stands off the shell
			local p0 = shellPoint(H, th, ph, 0.004)
			local p1 = shellPoint(H, th + dth * 0.4, ph + rng:NextNumber(-0.3, 0.3), 0.03 + 0.03 * H.T.curl)
			local out = (p0 - H.capC).Unit
			strand(H, p0, out, p1, -out, w * 0.8, 0.6 + 0.6 * H.T.curl, i, 0.3, 0.8, 1)
		else
			shellStrand(H, th, ph, th + dth, ph + rng:NextNumber(-0.15, 0.15) + (H.htype == "Wavy" and (i % 2 == 0 and 0.12 or -0.12) or 0), w, 0.01, i, H.T.curl)
		end
	end
end

-- point on the hair shell in a front-to-back sweep: f = sideways (-1 .. 1, the character's left to
-- right), psi = 0 on top, negative toward the face, positive toward the nape
local function combPoint(H, f, psi, out)
	local d = V3(f, math.cos(psi), math.sin(psi)).Unit
	local r = H.capR
	return H.capC + V3(d.X * (r.X + out), d.Y * (r.Y + out), d.Z * (r.Z + out))
end

-- point on the front hairline (the forehead surface), dipping toward the temples
local function hairlinePoint(H, x, out)
	local k = x / (0.38 * H.s.X)
	return surfPoint(H.Lay, x, H.hlY - 0.16 * H.s.Y * k * k, out)
end

-- strips between consecutive head-local points lying on the hair (parts, box partings)
local function pathLine(H, name, points, width, color, transparency)
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local dir = p1 - p0
		if dir.Magnitude > 1e-3 then
			local pm = (p0 + p1) / 2
			local n = (pm - (H.capC or V3())).Unit
			hpart(H, name, V3(width, 0.012 * H.s.Y, dir.Magnitude + width * 0.5), CFrame.lookAt(pm, pm + dir, n), color, "Ellipsoid", SMOOTH, transparency)
		end
	end
end

-- combed lines from the front hairline back over the crown (slick back, undercut, long hair):
-- two beziers per line (hairline -> crown, crown -> nape), one cannot follow half the shell
local function combLines(H, count, spread, back, width, sweep)
	if not H.capC then
		return
	end
	local rng = Random.new(H.seed + 57)
	sweep = sweep or 0
	for i = 1, count do
		local f = (count == 1 and 0 or (i - 1) / (count - 1) - 0.5) * 2 * spread
		local p0 = hairlinePoint(H, f * 0.38 * H.s.X, 0.012)
		local p1 = combPoint(H, f * 0.55 + sweep, -0.1 + rng:NextNumber(-0.08, 0.08), 0.006)
		strand(H, p0, (p1 - p0) + V3(0, 0.25 * H.s.Y, 0), p1, V3(sweep, -0.15, 1), width, 0.35, i, 0, back and 0.5 or 1, 1)
		if back then
			local p2 = combPoint(H, f * 0.7 + sweep, back, 0.006)
			strand(H, p1, V3(sweep, -0.15, 1), p2, V3(0, -math.sin(back), math.cos(back)), width, 0.35, i, 0.5, 1, 1)
		end
	end
end

-- a swinging chain of segments (dreads, braids, long hair, ponytail); stiff / mass feed the
-- client's spring (CONTRACTS section 5)
local function chain(H, startLocal, dir, segs, segLen, width, depth, idx, htype, beads, stiff, mass)
	local folder, head, colorFn = H.folder, H.head, H.colorFn
	local parent = head
	local jointWorld = head.CFrame * CF(startLocal)
	local look = head.CFrame:VectorToWorldSpace((dir.Magnitude > 0.01) and dir.Unit or V3(0, -1, 0))
	local mat = hairMaterial(htype)
	local T = HAIR_TYPES[htype] or HAIR_TYPES.Straight
	for i = 1, segs do
		local t = i / segs
		local color = colorFn(idx, t, startLocal.X)
		-- frame whose -Y axis points along the hanging direction
		local orient = CFrame.lookAt(jointWorld.Position, jointWorld.Position + look) * ANG(math.rad(90), 0, 0)
		local segCF = orient * CF(0, -segLen / 2, 0)
		local p
		local w = width * (1 - 0.18 * t)
		if CURLY[htype] or beads then
			p = mk(folder, nil, "HairSeg", V3(w * 1.1, segLen, w * 1.1), segCF, color, "Ellipsoid", mat)
		elseif htype == "Wavy" then
			p = mk(folder, nil, "HairSeg", V3(w, segLen, depth), segCF * ANG(0, 0, math.rad((i % 2 == 0) and 7 or -7)), color, "Block", mat)
		else
			p = mk(folder, nil, "HairSeg", V3(w, segLen, depth), segCF, color, "Block", mat)
		end
		local m = Instance.new("Motor6D")
		m.Name = "HairJoint"
		m.Part0 = parent
		m.Part1 = p
		m.C0 = parent.CFrame:Inverse() * orient
		m.C1 = p.CFrame:Inverse() * orient
		m:SetAttribute("Depth", i)
		m:SetAttribute("Stiff", stiff or T.stiff)
		m:SetAttribute("Mass", mass or T.mass)
		m.Parent = p
		CollectionService:AddTag(m, "HairSway")
		parent = p
		jointWorld = orient * CF(0, -segLen, 0)
		look = (look + V3(0, -0.6, 0)).Unit -- gravity pulls lower segments down
	end
end

-- curl clusters ride on one pivot with a bounce joint so the client can jiggle them as a mass
local function bouncePivot(H, localPos)
	if H.detail == "low" then
		return H.head
	end
	local p = mk(H.folder, nil, "BouncePivot", V3(0.05, 0.05, 0.05), H.hcf * CF(localPos), H.base, "Block", SMOOTH, 1)
	local m = joint(H.head, p, "HairBounce")
	m:SetAttribute("Depth", 1)
	m:SetAttribute("Bounce", true)
	m:SetAttribute("Stiff", H.T.stiff)
	m:SetAttribute("Mass", 1.4)
	CollectionService:AddTag(m, "HairSway")
	return p
end

local function bumps(H, count, radius, yMin, seed, anchor)
	local s = H.s
	local rng = Random.new(seed)
	count = math.min(count, H.D.hairBumps or count)
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local yN = rng:NextNumber(yMin, 0.98)
		local ring = math.sqrt(math.max(0, 1 - yN * yN))
		local x = math.cos(a) * ring * 0.55 * s.X
		local z = math.sin(a) * ring * 0.55 * s.Z
		if z < -0.3 * s.Z and yN < 0.45 then
			z = math.abs(z) -- keep the forehead clear
		end
		local y = 0.18 * s.Y + yN * 0.42 * s.Y
		local r = radius * rng:NextNumber(0.8, 1.25)
		later(H, "Curl", V3(r, r, r), CF(x, y, z), H.colorFn(i, yN, x), "Ball", H.mat, nil, anchor)
	end
end

-- tiny coil strands breaking up the silhouette of a curl cluster
local function coilHalo(H, count, center, radii, seed)
	local rng = Random.new(seed)
	local w = (0.018 + 0.012 * H.thick) * H.s.X
	for i = 1, count do
		local th = rng:NextNumber(0.1, 1.5)
		local ph = rng:NextNumber(-2.6, 2.6)
		local d = shellDir(th, ph)
		local p0 = center + V3(d.X * radii.X, d.Y * radii.Y, d.Z * radii.Z)
		local p1 = p0 + d * (0.03 + 0.04 * H.T.curl) * H.s.X + V3(rng:NextNumber(-0.02, 0.02), 0, rng:NextNumber(-0.02, 0.02))
		strand(H, p0, d + V3(0, 0.5, 0), p1, -d + V3(0, 0.3, 0), w, 1.1, i, 0.4, 0.9, 1)
	end
end

local function hairBuild(model, app, opts)
	bind()
	opts = opts or {}
	app = app or {}
	if Config.BaldMode then
		-- debug kill-switch: every boxer is bald
		local look = model:FindFirstChild("BoxerLook")
		local old = look and look:FindFirstChild("Hair")
		if old then
			old:Destroy()
		end
		return
	end
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local folder = getFolder(model, "Hair")
	local hair = app.hair or Looks.Defaults(app.gender).hair
	local style = hair.style or "Fade"
	if not DRAWN[style] then
		style = Looks.HairStyleBase[style] or "Fade"
		if not DRAWN[style] then
			style = "Fade"
		end
	end
	local detail, D = Config.DetailLevel(opts)
	local htype = HAIR_TYPES[hair.type] and hair.type or "Straight"
	local T = HAIR_TYPES[htype]
	local growth = clamp(tonumber(opts.previewGrowth) or tonumber(hair.growth) or 0, 0, 1.5)
	local s = head.Size
	local H = {
		folder = folder, head = head, s = s, hcf = head.CFrame, hair = hair, htype = htype, T = T, mat = T.mat,
		colorFn = hairPalette(hair), detail = detail, D = D, growth = growth,
		density = hair.density or 0.7, thick = hair.thickness or 0.5,
		seed = app.face and app.face.seed or 7, fore = app.face and app.face.forehead or 0,
		recede = hair.hairline == "Receding" and 1 or 0,
		strands = 0, maxStrands = D.strands or 0, skin = skinOf(app), deco = {},
	}
	-- part cap: the old hair's count plus what is left of A's budget after the face (already built)
	-- and a reserve for the beard (built after the hair)
	local faceExtra = extraOf(model, "Face", FACE_CAP[detail])
	H.cap = math.min(HAIR_MAX[detail], oldHairParts(hair, style) + A_BUDGET[detail] - faceExtra - BEARD_RESERVE[detail])
	H.base = H.colorFn(1, 0, 0)
	H.Lay = Head.FaceLayout(head, app.face or {})
	H.hlY = (0.37 + 0.03 * H.fore + 0.06 * H.recede) * s.Y
	local base, skin, mat, colorFn = H.base, H.skin, H.mat, H.colorFn
	local L = clamp((hair.length or 0.5) + growth * 0.6, 0, 1.5)
	local hang = L * T.shrink -- curly hair springs up: hanging styles show less of their length
	local density, thick = H.density, H.thick
	local grow = clamp(growth / 0.5, 0, 1) -- 0 fresh cut .. 1 grown out
	local fore = H.fore
	folder:SetAttribute("Detail", detail)
	folder:SetAttribute("Style", style)
	local function at(x, y, z)
		return CF(x, y, z)
	end
	local function add(name, size, cf, color, shape, material, transparency, anchor)
		return hpart(H, name, size, cf, color, shape, material, transparency, anchor)
	end
	local function setShell(c, size)
		H.capC, H.capR = c, size / 2
	end

	-- snug hair shell: covers the crown, sides and back with the hairline above the forehead
	local function cap(t, backDrop, transparency)
		local lift = 0.03 * fore + 0.04 * H.recede
		local c = V3(0, (0.16 + lift) * s.Y, (0.12 + 0.06 * H.recede) * s.Z)
		local size = V3(s.X * (1.04 + t * 0.7), s.Y * (0.9 + t * 1.2), s.Z * (0.98 + t * 0.7))
		local p = add("HairCap", size, CF(c), base, "Ellipsoid", mat, transparency)
		setShell(c, size)
		if backDrop and backDrop > 0 then
			add("HairBack", V3(s.X * 1.0, s.Y * (0.5 + backDrop), s.Z * 0.62), at(0, (-0.02 - backDrop * 0.35) * s.Y, 0.24 * s.Z), base, "Ellipsoid", mat)
		end
		return p
	end
	-- short top with gradient faded sides: each lower band hugs the head tighter and shows more
	-- scalp; level 0 = low fade .. 1 = high fade, k = how much skin shows at the bottom
	local function fadeCut(t, level, k)
		k *= 1 - 0.8 * grow -- the sides grow back in
		local lift = 0.03 * fore + 0.04 * H.recede
		local c = V3(0, (0.24 + level * 0.06 + lift) * s.Y, (0.1 + 0.05 * H.recede) * s.Z)
		local size = V3(s.X * (0.98 + t), s.Y * (0.66 + t - level * 0.1), s.Z * (0.96 + t))
		add("HairTop", size, CF(c), base, "Ellipsoid", mat)
		setShell(c, size)
		-- medium keeps the old two-tone cut (top + sides): the bands only read up close
		local bands = lod(H, 3, 1, 1)
		for i = 1, bands do
			local f = bands == 1 and 1 or (i - 1) / (bands - 1)
			local shade = k * (0.3 + 0.7 * f)
			local band = add(i == 1 and "FadeSides" or ("FadeBand" .. i), V3(s.X * (1.035 - 0.008 * (i - 1)), s.Y * (0.6 - level * 0.12) * (1 - 0.1 * (i - 1)), s.Z * (0.93 - 0.01 * (i - 1))),
				at(0, (0.08 + level * 0.05 - 0.075 * (i - 1)) * s.Y, 0.16 * s.Z), lerpColor(base, skin, shade), "Ellipsoid", i == 1 and mat or SMOOTH, (i == bands and k > 0.5) and 0.25 or 0)
			band:SetAttribute("Fade", i)
		end
	end
	-- top texture by hair type
	local function texture(count, radius, anchor)
		if CURLY[htype] then
			local r = radius * T.radius
			bumps(H, math.min(math.floor(count * (0.5 + density)), lod(H, 24, 8, 4)), r * s.X * (0.8 + 0.4 * thick), 0.25, H.seed + 3, anchor)
		elseif htype == "Wavy" and H.detail ~= "low" then
			for i = 1, 4 do
				later(H, "Wave", V3(s.X * 0.9, 0.025 * s.Y, 0.12 * s.Z), at(0, (0.3 + i * 0.045) * s.Y, (-0.35 + i * 0.16) * s.Z) * ANG(math.rad(-20 + i * 10), 0, 0), darken(base, 0.85), "Ellipsoid", mat)
			end
		end
	end
	-- hairline shape, visible part, crisp line-up while the cut is fresh. The front band lies on the
	-- forehead up to where the shell takes over, so every cut has a defined hairline.
	local hlY = H.hlY
	local function hairline(shaved, frontTransparency)
		local Lay = H.Lay
		local kind = hair.hairline or "Natural"
		local sx = s.X
		if frontTransparency ~= false then
			local segs = lod(H, 4, 2, 1)
			if segs > 1 and room(H) < 2 * segs then
				segs = 1 -- a tight budget: one strip still marks the hairline
			end
			local pts = {}
			for i = 0, segs do
				local x = (-0.34 + 0.68 * i / segs) * sx
				local k = x / (0.38 * sx)
				pts[i + 1] = { x, hlY + 0.06 * s.Y - 0.12 * s.Y * k * k }
			end
			surfacePath(H.folder, head, head, Lay, "HairFront", pts, 0.14 * s.Y, 0.035 * s.Z, base, frontTransparency or 0, 0.01, mat)
		end
		if kind == "Widow's Peak" then
			add("WidowsPeak", V3(0.08 * sx, 0.08 * sx, 0.03 * s.Z), surfCF(Lay, 0, hlY - 0.02 * s.Y, 0.008) * ANG(0, 0, math.rad(45)), base, "Block", mat)
		elseif kind == "Straight" and H.detail ~= "low" and room(H) >= 2 then
			surfacePath(H.folder, head, head, Lay, "HairlineEdge", { { -0.28 * sx, hlY - 0.005 * s.Y }, { 0, hlY - 0.012 * s.Y }, { 0.28 * sx, hlY - 0.005 * s.Y } }, 0.045 * s.Y, 0.03 * s.Z, base, 0, 0.01, mat)
		end
		-- the line-up: barber-sharp edges at the hairline, temple corners and sideburns (gone in ~2 weeks)
		if (kind == "Line-Up" or (shaved and kind == "Straight")) and growth < 0.35 and H.detail == "full" and room(H) >= 8 then
			local edge = lerpColor(darken(base, 0.7), base, growth * 2)
			local y0 = hlY - 0.015 * s.Y
			for side = -1, 1, 2 do
				surfacePath(H.folder, head, head, Lay, "LineUp", {
					{ 0, y0 }, { side * 0.13 * sx, y0 }, { side * 0.26 * sx, y0 - 0.004 * s.Y }, { side * 0.36 * sx, y0 - 0.13 * s.Y },
				}, 0.022 * s.Y, 0.02 * s.Z, edge, 0, 0.012)
				add("Sideburn", V3(0.03 * sx, 0.24 * s.Y, 0.09 * s.Z), at(side * 0.5 * sx, 0.06 * s.Y, -0.1 * s.Z), lerpColor(base, skin, 0.15), "Block", SMOOTH)
			end
		end
		-- a part: a clean shaved line on short cuts, the scalp showing through on longer hair
		local p = hair.part or "None"
		if p ~= "None" and H.capC and H.detail == "full" and room(H) >= 2 then
			local f = p == "Left" and -0.32 or (p == "Right" and 0.32 or 0)
			local col = lerpColor(base, skin, shaved and 0.75 or 0.45)
			pathLine(H, "HairPart", { hairlinePoint(H, f * 0.5 * sx, 0.016), combPoint(H, f, -0.45, 0.005), combPoint(H, f * 0.95, 0.1, 0.005) },
				(shaved and 0.02 or 0.013) * sx, col, 0)
		end
	end
	-- growth stages: hair creeps down the nape and over the ears as a cut grows out
	local function grownOut()
		if growth > 0.6 and H.detail ~= "low" and room(H) >= 1 then
			add("Nape", V3(0.78 * s.X, (0.16 + 0.12 * grow) * s.Y, 0.3 * s.Z), at(0, -0.12 * s.Y, 0.42 * s.Z), lerpColor(base, skin, 0.15), "Ellipsoid", mat)
			if growth > 0.9 and room(H) >= 2 then
				for side = -1, 1, 2 do
					add("EarTuft", V3(0.08 * s.X, 0.12 * s.Y, 0.18 * s.Z), at(side * 0.5 * s.X, 0.16 * s.Y, 0.08 * s.Z), base, "Ellipsoid", mat)
				end
			end
		end
	end

	if style == "Bald" then
		-- a shaved head grows back in as a shadow
		if growth > 0.05 then
			cap(0.01, nil, clamp(0.93 - 0.4 * growth, 0.4, 0.93)).Name = "Regrowth"
		end
	elseif SHORT[style] then
		local t = SHORT[style] + L * 0.05
		local shaved = true
		local frontT = nil
		if style == "Fade" or style == "Mid Fade" then
			fadeCut(t, 0.5, 0.45)
		elseif style == "Low Fade" then
			fadeCut(t, 0, 0.3)
		elseif style == "High Fade" then
			fadeCut(t, 1, 0.65)
		elseif style == "Taper Fade" then
			-- the fade only tapers at the sideburns and the nape
			fadeCut(t, 0.15, 0.25)
			if H.detail ~= "low" and room(H, lod(H, 5, 3, 2)) >= 1 then
				add("NapeTaper", V3(0.8 * s.X, 0.22 * s.Y, 0.3 * s.Z), at(0, -0.08 * s.Y, 0.42 * s.Z), lerpColor(base, skin, 0.7 * (1 - 0.8 * grow)), "Ellipsoid", SMOOTH)
				if H.detail == "full" or room(H, 3) >= 2 then
					for side = -1, 1, 2 do
						add("SideburnTaper", V3(0.05 * s.X, 0.2 * s.Y, 0.12 * s.Z), at(side * 0.5 * s.X, 0.02 * s.Y, -0.06 * s.Z), lerpColor(base, skin, 0.5 * (1 - 0.8 * grow)), "Ellipsoid", SMOOTH)
					end
				end
			end
		elseif style == "Buzz Cut" or style == "360 Waves" then
			-- clipper-short: the scalp shows through until it grows in
			frontT = clamp(0.3 - 0.25 * grow, 0.02, 0.3)
			local p = cap(t, nil, frontT)
			if style == "360 Waves" then
				-- brushed waves: concentric rings around the crown whorl, with a soft sheen
				p.Material = SMOOTH
				p.Reflectance = 0.03
				-- the whorl sits on the crown, behind the top of the head
				local tilt = 0.4
				local function wave(th, ph)
					local d = shellDir(th, ph)
					d = V3(d.X, d.Y * math.cos(tilt) - d.Z * math.sin(tilt), d.Y * math.sin(tilt) + d.Z * math.cos(tilt))
					local r = H.capR
					return H.capC + V3(d.X * (r.X + 0.004), d.Y * (r.Y + 0.004), d.Z * (r.Z + 0.004))
				end
				for r = 1, lod(H, 5, 3, 0) do
					local th = 0.16 + 0.19 * r
					for q = 0, 3 do
						local ph0, ph1 = q * math.pi / 2 + r * 0.3, (q + 1) * math.pi / 2 + r * 0.3
						local p0, p1 = wave(th, ph0), wave(th, ph1)
						strand(H, p0, wave(th, ph0 + 0.05) - p0, p1, p1 - wave(th, ph1 - 0.05), 0.026 * s.X, 0.3, r, 0.3, 0.3, 1, 0.15)
					end
				end
			end
		elseif style == "Caesar Cut" then
			cap(t)
			-- short, straight-cut fringe brushed forward at the hairline
			add("Fringe", V3(s.X * 0.62, 0.05 * s.Y, 0.12 * s.Z), at(0, 0.41 * s.Y, -0.43 * s.Z), base, "Ellipsoid", mat)
			shaved = false
		elseif style == "Modern Athlete" then
			fadeCut(t, 0.7, 0.55)
			for i = 1, lod(H, 7, 4, 2) do
				local x = (i - 4) * 0.12 * s.X
				later(H, "Texture", V3(0.13 * s.X, (0.09 + L * 0.06) * s.Y, 0.5 * s.Z), at(x, 0.55 * s.Y, -0.05 * s.Z) * ANG(math.rad(-10), 0, math.rad((i % 2 == 0) and 6 or -6)),
					colorFn(i, 0.2, x), "Ellipsoid", mat)
			end
		elseif style == "Textured Crop" then
			-- choppy top pushed forward to a blunt fringe over mid fade sides
			fadeCut(t, 0.6, 0.5)
			add("CropFringe", V3(s.X * 0.6, (0.06 + 0.03 * L) * s.Y, 0.14 * s.Z), at(0, 0.39 * s.Y, -0.42 * s.Z) * ANG(math.rad(-12), 0, 0), base, "Ellipsoid", mat)
			local rng = Random.new(H.seed + 61)
			for i = 1, lod(H, 10, 5, 3) do
				local x = rng:NextNumber(-0.3, 0.3) * s.X
				local z = rng:NextNumber(-0.38, 0.15) * s.Z
				later(H, "Tuft", V3(0.11 * s.X, (0.1 + 0.06 * L) * s.Y, 0.12 * s.Z), at(x, (0.55 - 0.15 * (z / s.Z + 0.38) * 0.4) * s.Y, z) * ANG(rng:NextNumber(-0.9, -0.4), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.3, 0.3)),
					colorFn(i, 0.3, x), "Wedge", mat)
			end
			shaved = false
		else -- Crew Cut
			cap(t)
			add("CrewTop", V3(s.X * 0.8, (0.12 + L * 0.06) * s.Y, s.Z * 0.6), at(0, 0.55 * s.Y, -0.12 * s.Z), base, "Ellipsoid", mat)
		end
		if style ~= "360 Waves" then
			texture(18, 0.08)
		end
		hairline(shaved, frontT)
		grownOut()
		if not CURLY[htype] and style ~= "Buzz Cut" and style ~= "360 Waves" then
			flyaways(H, lod(H, 14, 6, 0), 0.35 + 0.3 * L, 0.1, 0.9)
		end
	elseif style == "Burst Fade" then
		-- fade bursts in a half circle around each ear; full hair stays at the back and on top
		cap(0.07 + L * 0.04)
		local k = 0.75 * (1 - 0.8 * grow)
		for side = -1, 1, 2 do
			add("Burst", V3(0.14 * s.X, 0.5 * s.Y, 0.6 * s.Z), at(side * 0.5 * s.X, 0.02 * s.Y, 0.04 * s.Z), lerpColor(base, skin, k * 0.55), "Ellipsoid", SMOOTH)
			if H.detail ~= "low" and room(H, lod(H, 5, 3, 2)) >= 1 then
				add("BurstSkin", V3(0.1 * s.X, 0.34 * s.Y, 0.42 * s.Z), at(side * 0.53 * s.X, -0.02 * s.Y, 0.04 * s.Z), lerpColor(base, skin, k), "Ellipsoid", SMOOTH, 0.15)
			end
		end
		if CURLY[htype] then
			local pivot = bouncePivot(H, V3(0, 0.4 * s.Y, 0))
			bumps(H, math.floor(lod(H, 26, 14, 8) * (0.6 + 0.5 * density)), (0.1 + 0.05 * thick) * T.radius * s.X, 0.5, H.seed + 13, pivot)
			coilHalo(H, lod(H, 10, 4, 0), V3(0, 0.3 * s.Y, 0.08 * s.Z), V3(0.5 * s.X, 0.42 * s.Y, 0.5 * s.Z), H.seed + 14)
		else
			add("BurstTop", V3(s.X * 0.7, (0.16 + 0.1 * L) * s.Y, s.Z * 0.8), at(0, 0.54 * s.Y, -0.02 * s.Z), base, "Ellipsoid", mat)
			flyaways(H, lod(H, 12, 5, 0), 0.4 + 0.3 * L, 0.1, 0.8)
		end
		hairline(true)
		grownOut()
	elseif style == "Curly Top" then
		-- tight high-fade sides under a crown of springy curls
		fadeCut(0.06, 0.8, 0.6)
		local htex = CURLY[htype] and htype or "Curly"
		local TT = HAIR_TYPES[htex]
		local pivot = bouncePivot(H, V3(0, 0.45 * s.Y, 0))
		local oldMat = H.mat
		H.mat = TT.mat
		bumps(H, math.floor(lod(H, 30, 10, 6) * (0.6 + 0.5 * density)), (0.1 + 0.05 * thick + 0.04 * L * TT.shrink) * TT.radius * s.X, 0.55, H.seed + 23, pivot)
		H.mat = oldMat
		coilHalo(H, lod(H, 14, 5, 0), V3(0, 0.36 * s.Y, 0.06 * s.Z), V3(0.46 * s.X, 0.36 * s.Y, 0.46 * s.Z), H.seed + 24)
		hairline(true)
		grownOut()
	elseif style == "Afro" then
		-- a big round crown that sits above and behind the hairline, leaving the face clear;
		-- tighter coils shrink more, so the same length makes a denser, rounder shape
		local htex = CURLY[htype] and htype or "Kinky"
		local TT = HAIR_TYPES[htex]
		local size = 1.18 + 0.55 * L * (0.5 + 0.5 * TT.shrink)
		local hm = TT.mat
		local hx, hy, hz = 0.5 * size * s.X, 0.425 * size * s.Y, 0.475 * size * s.Z
		local cy = 0.3 * s.Y + 0.4 * hy -- the front edge meets the hairline at 0.3 of the head height
		local cz = -0.48 * s.Z + 0.9165 * hz
		local pivot = bouncePivot(H, V3(0, 0.3 * s.Y, 0.05 * s.Z))
		add("Afro", V3(hx * 2, hy * 2, hz * 2), at(0, cy, cz), base, "Ellipsoid", hm, nil, pivot)
		cap(0.06)
		setShell(V3(0, cy, cz), V3(hx * 2, hy * 2, hz * 2))
		local rng = Random.new(H.seed + 11)
		local n = math.min(math.floor(34 * (0.5 + density) * (htex == "Curly" and 0.8 or 1.1)), lod(H, 40, D.hairBumps or 18, D.hairBumps or 10))
		for i = 1, n do
			local u = rng:NextNumber(-0.45, 1)
			local a = rng:NextNumber(0, math.pi * 2)
			local ring = math.sqrt(1 - u * u)
			local px, py, pz = math.cos(a) * ring * hx * 0.96, cy + u * hy * 0.96, cz + math.sin(a) * ring * hz * 0.96
			if not (pz < -0.2 * s.Z and py < 0.34 * s.Y) then
				local r = (0.15 + 0.05 * thick) * s.X * rng:NextNumber(0.8, 1.25) * (0.7 + 0.3 * TT.radius)
				later(H, "Curl", V3(r, r, r), at(px, py, pz), colorFn(i, (u + 1) / 2, px), "Ball", hm, nil, pivot)
			end
		end
		coilHalo(H, lod(H, 18, 6, 0), V3(0, cy, cz), V3(hx, hy, hz), H.seed + 12)
		hairline(false)
	elseif style == "High Top" then
		local hgt = 0.5 + 0.55 * L * (0.6 + 0.4 * T.shrink)
		local hm = hairMaterial(CURLY[htype] and htype or "Kinky")
		local pivot = bouncePivot(H, V3(0, 0.45 * s.Y, 0))
		add("HighTop", V3(s.X * 0.92, s.Y * hgt, s.Z * 0.92), at(0, (0.45 + hgt / 2) * s.Y, 0.03 * s.Z), base, "Block", hm, nil, pivot)
		add("FadeSides", V3(s.X * 1.02, s.Y * 0.5, s.Z * 1.02), at(0, 0.2 * s.Y, 0.08 * s.Z), lerpColor(base, skin, 0.5 * (1 - 0.7 * grow)), "Ellipsoid", SMOOTH, 0.2)
		setShell(V3(0, (0.45 + hgt / 2) * s.Y, 0.03 * s.Z), V3(s.X * 0.92, s.Y * hgt, s.Z * 0.92))
		-- sponge-twist texture across the flat top
		local rng = Random.new(H.seed + 17)
		for i = 1, lod(H, 10, 5, 0) do
			local x, z = rng:NextNumber(-0.4, 0.4) * s.X, rng:NextNumber(-0.4, 0.4) * s.Z
			local r = 0.09 * s.X * rng:NextNumber(0.8, 1.2)
			-- flattened twists: a Ball part is always a sphere, so these are ellipsoids
			later(H, "Curl", V3(r, r * 0.6, r), at(x, (0.45 + hgt) * s.Y, z), colorFn(i, 1, x), "Ellipsoid", hm, nil, pivot)
		end
		hairline(true)
	elseif style == "Mohawk" then
		add("ShavedSides", V3(s.X * 1.02, s.Y * 0.55, s.Z * 1.03), at(0, 0.28 * s.Y, 0.05 * s.Z), lerpColor(base, skin, 0.75 * (1 - 0.7 * grow)), "Ellipsoid", SMOOTH, 0.35)
		setShell(V3(0, 0.28 * s.Y, 0.05 * s.Z), V3(s.X * 1.02, s.Y * 0.55, s.Z * 1.03))
		local n = 6
		for i = 1, n do
			local z = (-0.45 + (i - 1) * 0.18) * s.Z
			local hgt = (0.18 + 0.4 * L * T.shrink) * s.Y * (1 - math.abs(i - n / 2) * 0.06)
			add("Spike", V3(0.14 * s.X, hgt, 0.2 * s.Z), at(0, 0.5 * s.Y + hgt * 0.4, z), colorFn(i, i / n, 0), CURLY[htype] and "Ellipsoid" or "Block", mat)
		end
		-- strands standing up out of the crest
		local rng = Random.new(H.seed + 19)
		for i = 1, lod(H, 12, 4, 0) do
			local z = rng:NextNumber(-0.42, 0.42) * s.Z
			local p0 = V3(rng:NextNumber(-0.04, 0.04) * s.X, 0.5 * s.Y, z)
			local p1 = p0 + V3(rng:NextNumber(-0.05, 0.05), (0.2 + 0.35 * L * T.shrink) * s.Y, rng:NextNumber(-0.05, 0.08))
			strand(H, p0, V3(0, 1, 0), p1, V3(0, 0.6, 0.4), 0.035 * s.X, 0.3 + 0.4 * T.curl, i, 0.2, 1, 2)
		end
	elseif style == "Slick Back" then
		local p = cap(0.05 + L * 0.04, 0.1)
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("BasePart") then
				-- wet-look gel: a soft sheen (strong reflectance mirrors the sky and turns the hair blue)
				c.Material = SMOOTH
				c.Reflectance = 0.05
			end
		end
		if H.detail == "full" then
			for i = 1, 4 do
				local x = (i - 2.5) * 0.18 * s.X
				later(H, "Groove", V3(0.02 * s.X, 0.02 * s.Y, 0.7 * s.Z), at(x, 0.56 * s.Y, 0.02 * s.Z), darken(base, 0.6), "Block", SMOOTH)
			end
		end
		combLines(H, lod(H, 14, 6, 0), 0.75, 1.5, (0.03 + 0.02 * thick) * s.X)
		if hang > 0.6 then
			chain(H, V3(0, 0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.4), 2, 0.25 * s.Y * hang, 0.5 * s.X, 0.1 * s.Z, 1, htype, false, 0.3, 0.9)
		end
		p.Reflectance = 0.05
		hairline(false)
	elseif style == "Undercut" then
		add("ShavedSides", V3(s.X * 1.02, s.Y * 0.55, s.Z * 1.03), at(0, 0.2 * s.Y, 0.06 * s.Z), lerpColor(base, skin, 0.6 * (1 - 0.7 * grow)), "Ellipsoid", SMOOTH, 0.3)
		-- a full top section swept to one side, sitting on the crown rather than floating like a cap
		local topH = (0.34 + L * 0.2) * s.Y
		add("TopSweep", V3(s.X * 0.9, topH, s.Z * 1.04), at(0.04 * s.X, 0.5 * s.Y - topH * 0.18, 0.0), base, "Ellipsoid", mat)
		setShell(V3(0.04 * s.X, 0.5 * s.Y - topH * 0.18, 0), V3(s.X * 0.9, topH, s.Z * 1.04))
		for i = 1, lod(H, 5, 3, 1) do
			local x = (i - 3) * 0.15 * s.X
			later(H, "Sweep", V3(0.16 * s.X, (0.1 + L * 0.06) * s.Y, 0.6 * s.Z), at(x + 0.05 * s.X, 0.5 * s.Y + topH * 0.3, -0.12 * s.Z) * ANG(math.rad(-14), 0, math.rad(-12)),
				colorFn(i, 0.2, x), "Ellipsoid", mat)
		end
		texture(10, 0.08)
		combLines(H, lod(H, 12, 5, 0), 0.5, nil, (0.03 + 0.02 * thick) * s.X, 0.25)
		hairline(false)
	elseif style == "Messy Hair" then
		cap(0.08)
		local rng = Random.new(H.seed + 5)
		for i = 1, math.floor(lod(H, 10, 6, 4) + density * lod(H, 10, 4, 0)) do
			local a = rng:NextNumber(0, math.pi * 2)
			local x, z = math.cos(a) * 0.35 * s.X, math.sin(a) * 0.35 * s.Z
			later(H, "Tuft", V3(0.12 * s.X, (0.15 + L * 0.2 * T.shrink) * s.Y, 0.12 * s.Z),
				at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.7, 0.7), 0, rng:NextNumber(-0.7, 0.7)), colorFn(i, 0.3, x), "Wedge", mat)
		end
		flyaways(H, lod(H, 20, 8, 0), 0.5 + 0.4 * L, 0.05, 1.3)
		hairline(false)
	elseif style == "Cornrows" then
		add("Scalp", V3(s.X * 1.03, s.Y * 0.5, s.Z * 1.05), at(0, 0.36 * s.Y, 0.03 * s.Z), lerpColor(base, skin, 0.25), "Ellipsoid", SMOOTH)
		setShell(V3(0, 0.36 * s.Y, 0.03 * s.Z), V3(s.X * 1.03, s.Y * 0.5, s.Z * 1.05))
		local per = lod(H, 4, 3, 2)
		local tail = lod(H, 5, 2, 1) + 2 + ((growth > 0.4 and H.detail ~= "low") and 1 or 0)
		-- rows fit the cap (at least three); the hanging ends below only while there is room left
		local rows = clamp(math.floor(room(H, tail) / per), 3, lod(H, 5 + math.floor(density * 3), 5, 3))
		for i = 1, rows do
			local x = (i - (rows + 1) / 2) * (0.85 / rows) * s.X
			for j = 0, per - 1 do
				local a = math.rad(-50 + j * (152 / per))
				local y = 0.3 * s.Y + math.cos(a) * 0.25 * s.Y
				local z = math.sin(a) * 0.58 * s.Z
				-- alternate a slight twist so each row reads as plaited
				add("Row", V3(0.07 * s.X * (0.8 + thick * 0.5), 0.07 * s.Y, 0.24 * s.Z), at(x, y, z) * ANG(a, 0, math.rad((j % 2 == 0) and 8 or -8)), colorFn(i, j / 3, x), "Ellipsoid", mat)
			end
			if hang > 0.45 and i % 2 == 0 and H.detail ~= "low" and room(H, tail + (rows - i) * per) >= 2 then
				chain(H, V3(x, -0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.2), 2, 0.25 * s.Y * hang, 0.07 * s.X, 0.07 * s.Z, i, htype, true, 0.5, 1.3)
			end
		end
		if growth > 0.4 and H.detail ~= "low" then
			add("RootFrizz", V3(s.X * 1.06, s.Y * 0.52, s.Z * 1.08), at(0, 0.36 * s.Y, 0.03 * s.Z), lerpColor(base, darken(base, 0.8), 0.5), "Ellipsoid", SAND, clamp(0.85 - 0.4 * (growth - 0.4), 0.45, 0.85))
		end
		hairline(true, false)
	elseif style == "Dreadlocks" or style == "Twists" or style == "Braids" or style == "Box Braids" then
		cap(0.07)
		local box = style == "Box Braids"
		local braided = style == "Braids" or box
		local twists = style == "Twists"
		-- locs, twists and braids keep their length (the hair is set), but grow heavier and stiffer
		local n = math.floor(lod(H, box and 14 or 10, box and 6 or 8, 5) + density * lod(H, box and 4 or 6, 2, 1))
		local segs = twists and 1 or ((hang > 0.7 or L > 0.7) and lod(H, 3, 1, 1) or lod(H, 2, 1, 1))
		local segLen = (twists and 0.22 or 0.28 + 0.2 * L) * s.Y
		if segs == 1 and not twists then
			segLen *= 1.6
		end
		local w = (box and 0.06 or (braided and 0.07 or 0.1)) * s.X * (0.8 + 0.5 * thick)
		-- keep the chains inside the part budget (hero ~50, NPC ~22 segments, and the cut's cap less what
		-- the parting grid, root frizz and hairline still add), never fewer than four locs
		local crownSegs = segs >= 3 and 1 or segs
		local tail = lod(H, 5, 2, 1) + 2 + ((box and H.detail ~= "low") and lod(H, 6, 4, 0) or 0) + ((growth > 0.4 and H.detail ~= "low") and 1 or 0)
		n = math.min(n, math.floor(math.min(lod(H, 50, 22, 10), room(H, tail)) / (segs + 0.5 * crownSegs)))
		n = math.max(n, 4)
		local stiff = braided and 0.55 or 0.7
		local mass = braided and 1.3 or 1.6
		local ltype = braided and (CURLY[htype] and htype or "Curly") or "Coiled"
		for i = 1, n do
			local a = math.rad(-150 + (i - 1) * (300 / math.max(1, n - 1)))
			local x = math.sin(a) * 0.5 * s.X
			local z = math.cos(a) * 0.5 * s.Z
			if z > -0.3 * s.Z then
				local y = (0.05 + math.abs(math.cos(a)) * 0.15) * s.Y
				chain(H, V3(x, y, z), V3(x * 0.4, -1, z * 0.4 + 0.2), segs, segLen, w, w, i, ltype, braided, stiff, mass)
			end
		end
		-- locs from the crown fall back over the head
		for i = 1, math.floor(n / 2) do
			local x = (i - n / 4) * 0.14 * s.X
			chain(H, V3(x, 0.5 * s.Y, 0.1 * s.Z), V3(x * 0.3, -0.35, 1), crownSegs, segLen * (crownSegs == 1 and 0.9 or 0.6), w, w, i + 50, ltype, braided, stiff, mass)
		end
		if box and H.detail ~= "low" then
			-- box parting grid on the scalp
			local col = lerpColor(base, skin, 0.55)
			for i = 1, lod(H, 3, 2, 0) do
				local f = (i - 2) * 0.45
				pathLine(H, "BoxPart", { hairlinePoint(H, f * 0.4 * s.X, 0.016), combPoint(H, f, -0.4, 0.005), combPoint(H, f, 0.3, 0.005) }, 0.012 * s.X, col, 0.2)
			end
		end
		-- new growth at the roots: a soft halo before the next retwist
		if growth > 0.4 and H.detail ~= "low" then
			add("RootFrizz", V3(s.X * 1.1, s.Y * 1.02, s.Z * 1.06), at(0, 0.18 * s.Y, 0.14 * s.Z), lerpColor(base, darken(base, 0.8), 0.5), "Ellipsoid", SAND, clamp(0.85 - 0.4 * (growth - 0.4), 0.45, 0.85))
		end
		hairline(false)
	elseif style == "Short Dreads" then
		-- short freeform locs: a crown of locs that spring up and out before drooping, a fringe that
		-- falls over the forehead (stopping above the brows so the face stays clear) and locs
		-- hanging over the sides and back - a spiky silhouette wider than the head
		cap(0.08)
		local w = 0.085 * s.X * (0.85 + 0.5 * thick)
		local len = (0.22 + 0.12 * L) * s.Y
		local rng = Random.new(H.seed + 31)
		local idx = 0
		local twoSeg = H.detail == "full"
		local function loc(x, y, z, dir, segs, segLen, width)
			idx += 1
			if not twoSeg and segs > 1 then
				segLen *= segs * 0.8
				segs = 1
			end
			chain(H, V3(x, y, z), dir, segs, segLen, width or w, width or w, idx, "Coiled", false, 0.7, 1.3)
		end
		local nf = lod(H, 5 + math.floor(density * 2), 4, 3)
		for i = 1, nf do
			local x = (i - (nf + 1) / 2) * (0.7 / nf) * s.X
			local k = math.clamp(x / (s.X * 0.5), -0.97, 0.97)
			local z = -0.5 * s.Z * math.sqrt(1 - k * k) + 0.05 * s.Z
			loc(x, 0.5 * s.Y, z, V3(x * 0.35 + rng:NextNumber(-0.08, 0.08), -1, -0.25), 1, (0.2 + 0.05 * L) * s.Y * rng:NextNumber(0.9, 1.1))
		end
		local nc = lod(H, 9 + math.floor(density * 4), 6, 4)
		for i = 1, nc do
			local a = (i - 0.5) / nc * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
			local dx, dz = math.sin(a), math.cos(a) -- dz < 0 is towards the face
			if dz > -0.8 then
				local r0 = rng:NextNumber(0.12, 0.3)
				loc(dx * r0 * s.X, 0.56 * s.Y, dz * r0 * s.Z + 0.04 * s.Z, V3(dx, rng:NextNumber(-0.05, 0.25), dz), 2, len * rng:NextNumber(0.85, 1.15))
			end
		end
		local ns = lod(H, 8 + math.floor(density * 4), 6, 3)
		for i = 1, ns do
			local a = math.rad(-118 + (i - 1) * (236 / math.max(1, ns - 1)))
			local dx, dz = math.sin(a), math.cos(a)
			loc(dx * 0.5 * s.X, 0.3 * s.Y, dz * 0.5 * s.Z, V3(dx * 0.5, -1, dz * 0.5), 2, len * rng:NextNumber(0.8, 1.0))
		end
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Material = SMOOTH
			end
		end
		if growth > 0.4 and H.detail ~= "low" then
			add("RootFrizz", V3(s.X * 1.1, s.Y * 0.98, s.Z * 1.06), at(0, 0.2 * s.Y, 0.12 * s.Z), lerpColor(base, darken(base, 0.8), 0.5), "Ellipsoid", SAND, clamp(0.85 - 0.4 * (growth - 0.4), 0.45, 0.85))
		end
		hairline(false)
	elseif style == "Short Curly" then
		local ctype = CURLY[htype] and htype or "Curly"
		local TT = HAIR_TYPES[ctype]
		cap(0.08)
		local pivot = bouncePivot(H, V3(0, 0.35 * s.Y, 0.05 * s.Z))
		local oldMat = H.mat
		H.mat = TT.mat
		bumps(H, math.floor(lod(H, 26, 14, 8) * (0.6 + density)), (0.11 + 0.05 * thick) * TT.radius * s.X, 0.3, H.seed + 21, pivot)
		H.mat = oldMat
		coilHalo(H, lod(H, 12, 4, 0), V3(0, 0.25 * s.Y, 0.1 * s.Z), V3(0.56 * s.X, 0.5 * s.Y, 0.56 * s.Z), H.seed + 22)
		hairline(false)
	elseif style == "Long Curly" or ((style == "Long Hair" or style == "Wolf Cut") and (htype == "Coiled" or htype == "Kinky")) then
		-- long coily hair shrinks into big curls instead of hanging straight
		local ctype = CURLY[htype] and htype or "Curly"
		local TT = HAIR_TYPES[ctype]
		cap(0.1, 0.1)
		local pivot = bouncePivot(H, V3(0, 0.3 * s.Y, 0.05 * s.Z))
		local oldMat = H.mat
		H.mat = TT.mat
		bumps(H, math.floor(lod(H, 22, 12, 6) * (0.6 + 0.5 * density)), (0.13 + 0.05 * thick) * TT.radius * s.X, 0.2, H.seed + 22, pivot)
		H.mat = oldMat
		local n = math.floor(lod(H, 5, 3, 2) + density * lod(H, 3, 1, 0))
		local hl = TT.shrink * L
		for i = 1, n do
			local a = math.rad(-120 + (i - 1) * (240 / math.max(1, n - 1)))
			local x, z = math.sin(a) * 0.52 * s.X, math.cos(a) * 0.52 * s.Z
			chain(H, V3(x, 0.05 * s.Y, z), V3(x * 0.3, -1, z * 0.3 + 0.2), lod(H, hl > 0.6 and 3 or 2, 1, 1), (0.25 + 0.15 * hl) * s.Y, 0.18 * s.X * (0.8 + 0.4 * TT.radius), 0.18 * s.Z, i, ctype, false, TT.stiff, TT.mass)
		end
		coilHalo(H, lod(H, 14, 5, 0), V3(0, 0.22 * s.Y, 0.12 * s.Z), V3(0.58 * s.X, 0.55 * s.Y, 0.58 * s.Z), H.seed + 25)
		hairline(false)
	elseif style == "Long Hair" or style == "Wolf Cut" then
		cap(0.09, 0.12)
		local isWolf = style == "Wolf Cut"
		local segs = isWolf and 1 or lod(H, hang > 0.75 and 3 or 2, 2, 1)
		local segLen = (isWolf and 0.25 or 0.3 + 0.25 * hang) * s.Y
		-- back curtain
		chain(H, V3(0, 0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.3), segs, segLen, 0.9 * s.X, (0.12 + 0.08 * thick) * s.Z, 1, htype, false, T.stiff, T.mass)
		-- side curtains
		for side = -1, 1, 2 do
			chain(H, V3(side * 0.5 * s.X, 0.15 * s.Y, 0.05 * s.Z), V3(side * 0.2, -1, 0.1), segs, segLen * 0.9, 0.12 * s.X, 0.5 * s.Z, side + 3, htype, false, T.stiff, T.mass)
		end
		if isWolf then
			local rng = Random.new(H.seed + 9)
			for i = 1, lod(H, 9, 5, 2) do
				local a = rng:NextNumber(0, math.pi * 2)
				local x, z = math.cos(a) * 0.38 * s.X, math.sin(a) * 0.38 * s.Z
				later(H, "Shag", V3(0.16 * s.X, 0.2 * s.Y, 0.16 * s.Z), at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)), colorFn(i, 0.2, x), "Wedge", mat)
			end
			-- choppy fringe: separate strands that follow the curve of the forehead
			for i = 1, lod(H, 5, 3, 0) do
				local x = (i - 3) * 0.14 * s.X
				local k = math.clamp(x / (s.X * 0.5), -0.97, 0.97)
				local z = -0.5 * s.Z * math.sqrt(1 - k * k) * 0.93
				add("Bangs", V3(0.15 * s.X, (0.2 + 0.06 * L) * s.Y, 0.07 * s.Z), at(x, 0.38 * s.Y, z) * ANG(math.rad(-10), 0, math.rad((i - 3) * -6)),
					colorFn(i, 0.1, x), "Ellipsoid", mat)
			end
		end
		-- the outer layer: strands from the crown over the curtains
		local rng = Random.new(H.seed + 71)
		local nOuter = lod(H, 18, 6, 0)
		local drop = (isWolf and 0.45 or 0.5 + 0.55 * hang) * s.Y
		for i = 1, nOuter do
			local ph = rng:NextNumber(-1.9, 1.9)
			local p0 = shellPoint(H, 0.55 + rng:NextNumber(-0.1, 0.1), ph, 0.006)
			local out = V3(math.sin(ph), 0, math.cos(ph))
			local p1 = V3(p0.X * 1.05, p0.Y - drop * rng:NextNumber(0.75, 1.05), p0.Z) + out * 0.04 * s.X
			local wave = htype == "Wavy" and ((i % 2 == 0) and 0.45 or -0.25) or 0.25
			strand(H, p0, out + V3(0, -0.3, 0), p1, V3(0, -1, 0) + out * 0.2, (0.04 + 0.03 * thick) * s.X, wave, i, 0.1, 1, 2)
		end
		combLines(H, lod(H, 8, 3, 0), 0.6, nil, (0.03 + 0.02 * thick) * s.X)
		texture(12, 0.08)
		hairline(false)
	elseif style == "Ponytail" then
		cap(0.06, 0.05)
		for _, p in ipairs(folder:GetChildren()) do
			if p:IsA("BasePart") and htype == "Straight" then
				p.Reflectance = 0.05
			end
		end
		local tie = V3(0, 0.28 * s.Y, 0.56 * s.Z)
		-- a hair elastic in a shade of the hair (it only depends on hair data: the head cache key for the
		-- Hair step does not cover attire); dark hair gets a soft charcoal band so it still reads
		local tieColor = lum(base) > 0.22 and darken(base, 0.45) or Color3.fromRGB(62, 60, 66)
		add("HairTie", V3(0.14 * s.X, 0.14 * s.Y, 0.1 * s.Z), CF(tie), tieColor, "Ellipsoid", SMOOTH)
		chain(H, V3(0, 0.28 * s.Y, 0.6 * s.Z), V3(0, -0.8, 0.6), lod(H, hang > 0.6 and 4 or 3, 2, 1), (0.22 + 0.12 * hang) * s.Y * lod(H, 1, 1.5, 3), (0.2 + 0.1 * thick) * s.X, (0.2 + 0.1 * thick) * s.Z, 1, htype, false, T.stiff, T.mass)
		-- hair pulled back tight from the hairline to the tie
		local n = lod(H, 11, 5, 0)
		local w = (0.03 + 0.02 * thick) * s.X
		for i = 1, n do
			local f = n == 1 and 0 or (i - 1) / (n - 1) - 0.5
			local p0 = hairlinePoint(H, f * 0.72 * s.X, 0.012)
			local p1 = combPoint(H, f * 0.6, 0.15, 0.008)
			strand(H, p0, (p1 - p0) + V3(0, 0.25 * s.Y, 0), p1, V3(-f * 0.4, -0.1, 1), w, 0.35, i, 0, 0.6, 1)
			strand(H, p1, V3(-f * 0.4, -0.1, 1), tie + V3(f * 0.06 * s.X, 0, -0.02), tie - p1, w, 0.3, i, 0.6, 1, 1)
		end
		hairline(false)
	else
		cap(0.08)
		texture(14, 0.08)
		hairline(false)
	end

	-- decorations (curls, tufts, wave bands...) in queue order while the cap leaves room
	for i = 1, math.min(#H.deco, math.max(0, room(H))) do
		H.deco[i]()
	end
	-- parts over the old hair (the beard reads this to share A's budget)
	folder:SetAttribute("Extra", countParts(folder) - oldHairParts(hair, style))
	-- sheen by hair type on the hair material (curls and coils stay matte)
	if T.sheen > 0 then
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 and p.Material == T.mat and p.Reflectance < T.sheen then
				p.Reflectance = T.sheen
			end
		end
	end
	-- the client spring reads the stiffness of the whole cut too (locs / coils barely move)
	folder:SetAttribute("Stiff", T.stiff)
	Hair.ApplyHairHidden(model)
end

------------------------------------------------------------------------
-- Hair under headgear / a robe hood
------------------------------------------------------------------------
-- hides every hair part / strand the shell or hood would swallow and restores them afterwards.
-- Parts get attribute HGHidden (and HGBaseT, the transparency to restore); strands are disabled.
function Hair.ApplyHairHidden(model)
	bind()
	local hg = model:GetAttribute("HairHiddenHeadgear") == true
	local hood = model:GetAttribute("HairHiddenHood") == true
	local look = model:FindFirstChild("BoxerLook")
	local hair = look and look:FindFirstChild("Hair")
	local head = part(model, "Head")
	if not (hair and head) then
		return
	end
	local s = head.Size
	local hcf = head.CFrame
	local function hidden(p, size)
		local big = size and (size.X > 0.62 * s.X or size.Z > 0.62 * s.Z)
		if hg and (p.Y > 0.3 * s.Y or (big and p.Y > -0.1 * s.Y)) then
			return true
		end
		-- a hood covers the crown, sides and back; a fringe on the face stays visible
		return hood and p.Y > -0.4 * s.Y and p.Z > -0.36 * s.Z
	end
	for _, d in ipairs(hair:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name ~= "StrandAnchor" and d.Name ~= "BouncePivot" then
				local hide = hidden(hcf:PointToObjectSpace(d.Position), d.Size)
				if hide then
					if not d:GetAttribute("HGHidden") then
						d:SetAttribute("HGBaseT", d.Transparency)
					end
					d:SetAttribute("HGHidden", true)
					d.Transparency = 1
				elseif d:GetAttribute("HGHidden") then
					d.Transparency = d:GetAttribute("HGBaseT") or 0
					d:SetAttribute("HGHidden", nil)
					d:SetAttribute("HGBaseT", nil)
				end
			end
		elseif d:IsA("Beam") then
			local a0 = d.Attachment0
			d.Enabled = not (a0 and hidden(a0.Position, nil))
		end
	end
end

-- region = "headgear" | "hood"; the state is kept on the model so a rebuild stays hidden
function Hair.SetHairHidden(model, region, on)
	bind()
	model:SetAttribute(region == "hood" and "HairHiddenHood" or "HairHiddenHeadgear", on and true or nil)
	Hair.ApplyHairHidden(model)
end

------------------------------------------------------------------------
-- Sweat
------------------------------------------------------------------------
-- wet hair darkens and (except coils) gains a slight sheen; strands darken too
local function wetHair(model, q)
	bind()
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		return
	end
	for _, fname in ipairs({ "Hair", "Beard" }) do
		local f = look:FindFirstChild(fname)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local dry = d:GetAttribute("DryColor")
					if typeof(dry) ~= "Color3" then
						if q <= 0 then
							-- dry and never wetted since this build: nothing to restore, no attribute writes
							continue
						end
						dry = d.Color
						d:SetAttribute("DryColor", dry)
						d:SetAttribute("DryRefl", d.Reflectance)
					end
					d.Color = lerpColor(dry, darken(dry, 0.7), q)
					if d.Material ~= SAND then
						d.Reflectance = math.min(0.06, (d:GetAttribute("DryRefl") or 0) + 0.04 * q)
					end
				elseif d:IsA("Beam") then
					local c0, c1 = d:GetAttribute("DryColor0"), d:GetAttribute("DryColor1")
					if typeof(c0) == "Color3" and typeof(c1) == "Color3" then
						d.Color = ColorSequence.new(lerpColor(c0, darken(c0, 0.7), q), lerpColor(c1, darken(c1, 0.7), q))
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
Hair.Build = hairBuild -- (model, app, opts): BoxerLook/Hair (Builder.Cosmetics step "Hair")
Hair.Wet = wetHair -- (model, q 0..1): wet hair / beard look (Head.SetSweat calls it)
Hair.TYPES = HAIR_TYPES -- per hair type: shrink, curl, radius, sheen, mat, stiff, mass (read-only data)
Hair.CURLY = CURLY
Hair.Drawn = DRAWN -- styles with a dedicated branch (others draw Looks.HairStyleBase[id])
Hair.Palette = hairPalette -- (hair) -> fn(index, t, x) -> Color3

return Hair
