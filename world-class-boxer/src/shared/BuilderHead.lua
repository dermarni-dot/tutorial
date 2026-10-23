-- BuilderHead: everything built on the head (server side; the Creator also calls SetDamage locally).
-- * the head: the engine's default head is swapped once for the classic head (a Part with the Head SpecialMesh,
--   classicHead) and the face is BUILT on it from Parts (no decal, no EditableMesh). Every feature is a lens: an
--   ellipsoid sunk into the classic head's exact surface (AnatomyHairKit.CLASSIC, FaceLayout surf / normal) so only
--   a low dome of the size asked shows, its rim on the skin; nothing floats or sinks. Ears flush on the side wall,
--   eyes set in (a shallow white, limbal ring, iris, pupil, catchlight; an upper lid fold whose edge is the lash
--   line, a low lower lid), solid 3-piece brows on the style's arch (6 styles), a nose with a bridge, tip, wings and
--   nostrils, two low lips overlapping at a dark seam with rigged corner pieces, teeth + interior behind them;
--   cheekbones, jaw angles and a heavy brow ridge only where the sliders ask for them. No default blush. From the
--   creator's face shape and Face / Eye / Skin / Wear sliders (Looks); heterochromia, asymmetry, undertone
-- * boxer wear and skin: cauliflower ear, bent nose, permanent fight scars (app.battle), a stitched
--   surgical repair scar, acne (active spots when young, pitted scars on adult skin), wrinkles by age,
--   pore texture (an honest approximation: material + sparse dots), temple/forehead veins, face fat
--   (full cheeks, jowls) and weight-cut hollows, grime (own folder, refreshed by SetSweat)
-- * part budget: A's share of Config.Detail partBudget (+60 / +10 / 0 over the old face, hair and beard);
--   optional face details and hair decorations are drawn in priority order while it lasts
-- * the built face above is dormant: every boxer wears a drawn face (BodyTiers.DrawnStyleOf never returns nil while
--   one is uploaded), so its parts and rig are only built in the emergency fallback with no drawn face uploaded
--   (and by the lune tests through BodyTiers.SetData). The code stays in place, unused
-- * drawn face styles (look.face.style = a BodyTiers.STYLE_KEYS key, the user's Boxer faces): the head wears the
--   drawn face as its front Decal "face" (white, opaque, the whole square canvas) instead of the built eyes, brows,
--   nose and lips (none of those parts, no face rig; the ears, head shape and skin details stay). Damage, sweat, grime
--   and the beard then follow the drawn features (Head.DecalLayout); FaceFX swaps the decal by mood
-- * face rig the client animates (FaceFX; Motor6D "FaceJoint", tag FaceRig, attribute Role): brows, lids,
--   lower lids, eyes (invisible EyeBall pivots), lips, mouth corners, mouth interior; BlinkLid parts
-- * hair: in BuilderHair (split out verbatim; Head.Hair, SetHairHidden and ApplyHairHidden forward
--   there and Head.Shared lends it the budget and head-surface helpers below)
-- * beards: growth stages, own colour, salt & pepper with age, 10 styles, material by hair type
-- * fight damage light .. severe (bruise colour by age), sweat (skin sheen, beads, drips, wet hair)
-- Builder.Cosmetics runs Face, Hair (BuilderHair) and Beard (in that order) and forwards FaceLayout,
-- SetDamage, SetSweat and SetHeadgear here. Level of detail: opts.detail through Config.DetailLevel.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
-- the drawn face styles (look.face.style) and their uploaded textures
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))
-- hair lives in BuilderHair (it requires this module lazily, on first use: no require cycle)
local Hair = require(script.Parent:WaitForChild("BuilderHair"))

local Head = {}

local V3, CF, ANG, SMOOTH = Kit.V3, Kit.CF, Kit.ANG, Kit.SMOOTH
local lerpColor, darken = Kit.lerpColor, Kit.darken
local mk, getFolder, part = Kit.mk, Kit.getFolder, Kit.part
local FABRIC, SAND, PLASTIC = Enum.Material.Fabric, Enum.Material.Sand, Enum.Material.Plastic
local clamp, rad = math.clamp, math.rad
local WHITE = Color3.new(1, 1, 1)

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------
local function lum(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

local function skinOf(app)
	return Looks.Color(Looks.SkinTones[app.skin or 5])
end

-- flush / lip tint per undertone (lips, blush, ear lobes, inner eye corners)
local UNDERTONE = {
	Neutral = Color3.fromRGB(196, 108, 104),
	Warm = Color3.fromRGB(212, 122, 88),
	Cool = Color3.fromRGB(188, 98, 128),
	Olive = Color3.fromRGB(168, 120, 86),
}

-- animatable cosmetic joint (CONTRACTS section 5): Part0 = the head, Part1 = the moving part, C0 holds
-- the build pose, C1 = identity; the client only writes Motor6D.Transform
local function joint(part0, part1, name)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * part1.CFrame
	m.C1 = CF()
	m.Parent = part1
	return m
end

-- attachment frame whose X axis (the Beam curve axis) points along dir
local function axisCF(pos, dir)
	if dir.Magnitude < 1e-4 then
		dir = V3(0, -1, 0)
	end
	dir = dir.Unit
	local up = math.abs(dir.Y) > 0.95 and V3(0, 0, -1) or V3(0, 1, 0)
	return CFrame.lookAt(pos, pos + dir, up) * ANG(0, math.pi / 2, 0)
end

-- the head surface: the classic head (FaceLayout: L.surf / L.normal, AnatomyHairKit.CLASSIC exactly)
local function surfNormal(L, x, y)
	if L.normal then
		return L.normal(x, y)
	end
	local e = 0.01
	local px = V3(2 * e, 0, L.surf(x + e, y) - L.surf(x - e, y))
	local py = V3(0, 2 * e, L.surf(x, y + e) - L.surf(x, y - e))
	local n = py:Cross(px)
	if n.Z > 0 then
		n = -n
	end
	return n.Unit
end

local function surfPoint(L, x, y, out)
	return V3(x, y, L.surf(x, y)) + surfNormal(L, x, y) * (out or 0)
end

-- head-local frame on the surface at (x, y): -Z (LookVector) points out of the skin
local function surfCF(L, x, y, out)
	local p = surfPoint(L, x, y, out)
	return CFrame.lookAt(p, p + surfNormal(L, x, y), V3(0, 1, 0))
end

-- a thin strip lying on the head surface between head-local (x0, y0) and (x1, y1):
-- size X = visible width, Y = thickness along the skin normal, Z = length
local function surfaceLine(folder, anchor, head, L, name, x0, y0, x1, y1, width, depth, color, transparency, out, material)
	out = out or 0.004
	local p0 = surfPoint(L, x0, y0, out)
	local p1 = surfPoint(L, x1, y1, out)
	local pm = surfPoint(L, (x0 + x1) / 2, (y0 + y1) / 2, out)
	local dir = p1 - p0
	local len = dir.Magnitude
	if len < 1e-3 then
		return nil
	end
	local cf = head.CFrame * CFrame.lookAt(pm, pm + dir, surfNormal(L, (x0 + x1) / 2, (y0 + y1) / 2))
	return mk(folder, anchor, name, V3(width, depth, len + width * 0.5), cf, color, "Ellipsoid", material or SMOOTH, transparency)
end

-- the same along a polyline { {x, y}, ... } (short segments keep a curved path on the skin)
local function surfacePath(folder, anchor, head, L, name, pts, width, depth, color, transparency, out, material)
	for i = 1, #pts - 1 do
		surfaceLine(folder, anchor, head, L, name, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], width, depth, color, transparency, out, material)
	end
end

-- a lens: an ellipsoid sunk into the head so that a footprint w x h (along the surface frame's X / Y at (x, y),
-- turned `roll` about the normal) shows and its middle rises `rise` above the skin. dk = the share of its depth
-- below the skin (0.3 a full dome with a steep rim .. 0.9 a nearly flat patch with a soft one). The head falls
-- away under a wide footprint (the round wall, the rounded brow and chin): the ellipsoid is sunk at least that far
-- so its rim never stands off the skin, and widened so the rim still lands at w / 2, h / 2. base lifts it off the
-- skin (a brow on the brow ridge). Returns the head-local CFrame (-Z out of the skin) and the Size, plus the
-- depth semi-axis D and the sink c (its height above the skin at (u, v) is D sqrt(1 - (u/a)^2 - (v/b)^2) - c).
local function lens(L, x, y, w, h, rise, dk, roll, base)
	local cf = surfCF(L, x, y, 0)
	if roll and roll ~= 0 then
		cf = cf * ANG(0, 0, roll)
	end
	local n, p0 = cf.LookVector, cf.Position
	local function sagAt(dx, dy)
		local t = p0 + cf.RightVector * dx + cf.UpVector * dy
		return math.max((p0 - V3(t.X, t.Y, L.surf(t.X, t.Y))):Dot(n), 0)
	end
	local sx = math.max(sagAt(w / 2, 0), sagAt(-w / 2, 0))
	local sy = math.max(sagAt(0, h / 2), sagAt(0, -h / 2))
	if (dk or 0.6) >= 0.7 then
		-- a flat patch (a bruise, a shadow, a scar): an ellipsoid barely flatter than the head under it would meet it in
		-- a squarish outline, so it is shaped from the curvatures instead: the head's (from the sag) plus what it takes to
		-- rise `rise` at the middle and come back to the skin at the footprint's edge, a near paraboloid there
		-- (at least 1.7 x the head's curvature, or the outline goes diamond-shaped; a wide patch on the round wall
		-- therefore rises a little more than asked. Neither semi-axis runs past 2.2 x the footprint: a long one poked
		-- out of the head where it rounds off)
		local hw, hh = w / 2, h / 2
		rise = math.max(rise, 0.4 * math.max(sx, sy))
		local kLx = math.max((2 * sx + 2 * rise) / (hw * hw), 1.7 * 2 * sx / (hw * hw))
		local kLy = math.max((2 * sy + 2 * rise) / (hh * hh), 1.7 * 2 * sy / (hh * hh))
		local m = 1.15 + (dk - 0.7) * 2
		local D = math.max(kLx * (hw * m) ^ 2, kLy * (hh * m) ^ 2, 0.01)
		local a = math.min(math.sqrt(D / kLx), 2.2 * hw)
		local b = math.min(math.sqrt(D / kLy), 2.2 * hh)
		return cf * CF(0, 0, D - rise - (base or 0)), V3(2 * a, 2 * b, 2 * D), D, D - rise
	end
	-- (Kit.mk keeps every axis >= 0.02: never thinner than that)
	local D = math.max(rise / (1 - clamp(dk or 0.6, 0.05, 0.95)), 0.01)
	local c = D - rise
	local need = math.max(sx, sy) * 1.1 + 0.0006
	if c < need then
		c = need
		D = rise + need
	end
	local fx = math.sqrt(math.max(1 - ((c - sx) / D) ^ 2, 0.04))
	local fy = math.sqrt(math.max(1 - ((c - sy) / D) ^ 2, 0.04))
	return cf * CF(0, 0, c - (base or 0)), V3(w / fx, h / fy, 2 * D), D, c
end

-- an ellipsoid on top of a dome (an iris on the white, a pupil on the iris): its middle stands rTop above the skin and
-- its rim meets the dome, hBase above the skin, at radius rho. Returns the semi-axis across, the depth semi-axis and the
-- sink below the skin.
local function capOn(rTop, rho, hBase, D)
	D = math.max(D or 0, 0.01, rTop + 0.0015)
	local c = D - rTop
	local f = math.sqrt(math.max(1 - ((math.max(hBase, 0) + c) / D) ^ 2, 0.04))
	return rho / f, D, c
end

------------------------------------------------------------------------
-- Face layout
------------------------------------------------------------------------
-- the classic head (AnatomyHairKit.CLASSIC, nominal 1.2 box: a vertical cylinder r 0.6, half height 0.6, its top and
-- bottom edges rounded by 0.24, centred on the part); real = nominal x Size / 1.2 per axis. A copy (requiring the hair kit
-- would load MeshKit on the server for three numbers); test_bodytiers checks it against AnatomyHairKit.CLASSIC
local CLASSIC = { r = 0.6, h = 0.6, round = 0.24 }
Head.CLASSIC = CLASSIC

-- returns head-local positions for face features (shared with hair, beard and damage visuals)
-- Fields: s, front(x), surf(x, y), normal(x, y), shellCF(az, y, out), eyeX, eyeY, mouthY, eyeSize, eyeW, eyeHt, eyeH,
-- browY, noseLen, noseW, noseB, noseTopY, noseBottomY, mouthW, eyeTilt, eyeYS[side], browTiltS[side], mouthTilt, noseDev
function Head.FaceLayout(head, face)
	face = face or {}
	local s = head.Size
	local kx, ky, kz = s.X / 1.2, s.Y / 1.2, s.Z / 1.2
	local R, RR = CLASSIC.r, CLASSIC.round
	local core, flat = R - RR, CLASSIC.h - RR
	-- the head's radius at nominal height yn and the tilt of its normal there (the rounded top / bottom edge)
	local function rhoN(yn)
		local e = math.abs(yn) - flat
		if e <= 0 then
			return R, 1, 0
		end
		e = math.min(e, RR * 0.995)
		local r = core + math.sqrt(RR * RR - e * e)
		return r, (r - core) / RR, (yn > 0 and 1 or -1) * e / RR
	end
	local function surf(x, y)
		local r = rhoN(y / ky)
		local xn = clamp(x / kx, -r * 0.985, r * 0.985)
		return -kz * math.sqrt(r * r - xn * xn)
	end
	local function front(x)
		return surf(x, 0)
	end
	local function normal(x, y)
		local r, ct, st = rhoN(y / ky)
		local xn = clamp(x / kx, -r * 0.985, r * 0.985)
		local zn = -math.sqrt(r * r - xn * xn)
		return V3(ct * xn / r / kx, st / ky, ct * zn / r / kz).Unit
	end
	-- a frame anywhere on the head: azimuth az from the front (+ towards +X), height y; -Z out of the skin
	local function shellCF(az, y, out)
		local yn = clamp(y / ky, -0.598, 0.598)
		local r, ct, st = rhoN(yn)
		local hx, hz = math.sin(az), -math.cos(az)
		local nn = V3(ct * hx / kx, st / ky, ct * hz / kz).Unit
		local p = V3(r * hx * kx, yn * ky, r * hz * kz) + nn * (out or 0)
		return CFrame.lookAt(p, p + nn, V3(0, 1, 0))
	end
	-- how far a head-local point lies outside the head (studs, radially; < 0 inside; above / below the head: its height
	-- past the top / bottom)
	local function outside(p)
		local yn = p.Y / ky
		if math.abs(yn) >= CLASSIC.h then
			return (math.abs(yn) - CLASSIC.h) * ky
		end
		local r = rhoN(yn)
		local k = math.sqrt((kx * kx + kz * kz) / 2)
		return (math.sqrt((p.X / kx) ^ 2 + (p.Z / kz) ^ 2) - r) * k
	end
	local eyeX = (0.19 + 0.035 * (face.eyeDist or 0)) * s.X
	local eyeY = 0.1 * s.Y
	local mouthY = -0.215 * s.Y
	local L = {
		s = s, front = front, surf = surf, normal = normal, shellCF = shellCF, outside = outside, eyeX = eyeX, eyeY = eyeY, mouthY = mouthY,
		eyeSize = 1 + 0.25 * (face.eyeSize or 0),
		eyeH = 1 - 0.45 * (face.eyeShape or 0.5),
		browY = eyeY + (0.13 + 0.025 * (face.forehead or 0) + 0.03 * (face.browHeight or 0)) * s.Y,
		noseLen = (0.2 + 0.07 * (face.noseLength or 0)) * s.Y,
		noseW = (0.11 + 0.05 * (face.noseWidth or 0)) * s.X,
		noseB = (0.085 + 0.05 * (face.noseBridge or 0)) * s.Z,
	}
	-- the visible eye opening (round .. almond)
	L.eyeW = 0.132 * L.eyeSize * s.X
	L.eyeHt = L.eyeW * (0.9 - 0.46 * clamp(face.eyeShape or 0.5, 0, 1))
	L.noseTopY = eyeY - 0.02 * s.Y
	L.noseBottomY = L.noseTopY - L.noseLen
	L.mouthW = (0.235 + 0.02 * (face.lips or 0) + 0.045 * (face.mouthWidth or 0)) * s.X
	L.eyeTilt = clamp(face.eyeTilt or 0, -1, 1) * rad(8)
	-- asymmetry: its own random stream so the skin-detail stream never shifts
	local asym = clamp(face.asym or 0, 0, 1)
	local r = Random.new((face.seed or 7) + 101)
	local dy, bl, br, mt, nd = r:NextNumber(-1, 1), r:NextNumber(-1, 1), r:NextNumber(-1, 1), r:NextNumber(-1, 1), r:NextNumber(-1, 1)
	L.eyeYS = { [-1] = eyeY + dy * asym * 0.014 * s.Y, [1] = eyeY - dy * asym * 0.014 * s.Y }
	L.browTiltS = { [-1] = bl * asym * rad(6), [1] = br * asym * rad(6) }
	L.mouthTilt = mt * asym * rad(4)
	L.noseDev = nd * asym * 0.018 * s.X
	return L
end

-- The drawn Boxer faces (look.face.style): where their features lie on the head. The decal spans the head's front
-- (Size.X x Size.Y, u = 0 at +X: the image as the viewer sees it), so a canvas point (u, v) is head-local
-- ((0.5 - u) * Size.X, (0.5 - v) * Size.Y). Measured from the registered 1254 px set (tools/body/faces.py
-- register_pack: every face's eye centres at x 443 / 807, y 575): eyes +-0.145, y +0.0415, ink 0.057 x 0.101; brows
-- ~0.15 (0.13 .. 0.155 by face); mouths ~-0.175 (ink -0.12 .. -0.22, 0.14 .. 0.22 wide). eyeW / eyeH: the eye's
-- socket (what FaceLayout readers see as the eye opening), not the ink; SetDamage draws a drawn eye's marks itself.
local DECAL = {
	eyeX = 0.145, eyeY = 0.0415, eyeW = 0.1, eyeH = 0.1, browY = 0.15, mouthY = -0.175, mouthW = 0.2,
	noseBottomY = -0.085, noseW = 0.1,
}
Head.DECAL = DECAL
-- the drawn ink (fractions of the head size, |x| ranges: both sides), padded: skin spots keep off it
local DECAL_INK = {
	{ 0.085, 0.205, -0.05, 0.11 }, -- eyes
	{ 0.02, 0.285, 0.065, 0.21 }, -- brows
	{ 0, 0.2, -0.235, -0.105 }, -- mouth
}
Head.DECAL_INK = DECAL_INK

-- a FaceLayout moved onto the drawn features (in place; returns L): the eyes, brows, mouth and a nose line between
-- them (no nose is drawn: only the bleed and the sweat use it), no asymmetry or tilt
function Head.DecalLayout(L)
	local s = L.s
	L.eyeX, L.eyeY = DECAL.eyeX * s.X, DECAL.eyeY * s.Y
	L.eyeYS = { [-1] = L.eyeY, [1] = L.eyeY }
	L.eyeW, L.eyeHt, L.eyeSize, L.eyeTilt = DECAL.eyeW * s.X, DECAL.eyeH * s.Y, 1, 0
	L.browY = DECAL.browY * s.Y
	L.browTiltS = { [-1] = 0, [1] = 0 }
	L.mouthY, L.mouthW, L.mouthTilt = DECAL.mouthY * s.Y, DECAL.mouthW * s.X, 0
	L.noseTopY = L.eyeY - 0.02 * s.Y
	L.noseBottomY = DECAL.noseBottomY * s.Y
	L.noseLen = L.noseTopY - L.noseBottomY
	L.noseW, L.noseB, L.noseDev = DECAL.noseW * s.X, 0, 0
	L.decal = true
	return L
end

-- true when a mark of size w x h at head-local (x, y) would cover the drawn ink
function Head.DecalInkHit(L, x, y, w, h)
	local s = L.s
	local ax, rx, ry = math.abs(x) / s.X, (w or 0) / 2 / s.X, (h or 0) / 2 / s.Y
	local yy = y / s.Y
	for _, b in ipairs(DECAL_INK) do
		if ax + rx > b[1] and ax - rx < b[2] and yy + ry > b[3] and yy - ry < b[4] then
			return true
		end
	end
	return false
end

-- the drawn style the head's face was built with (the Face folder's FaceStyle attribute; nil = the built face)
function Head.FaceStyle(model)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Face")
	local st = f and f:GetAttribute("FaceStyle")
	return type(st) == "string" and st or nil
end

-- the head's front Decal "face" for a drawn style: one decal (any other decal on the head goes: an engine face, an
-- older build's), Front, white, opaque, the uploaded texture of the chosen face; tagged FaceDecal (FaceFX finds it
-- and swaps its Texture by mood on the client; the server's Texture stays the chosen face)
local function putFaceDecal(head, style)
	local keep
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") then
			if not keep and d.Name == "face" and d:GetAttribute("FaceStyle") == style then
				keep = d
			else
				d:Destroy()
			end
		end
	end
	local dec = keep or Instance.new("Decal")
	dec.Name = "face"
	dec.Face = Enum.NormalId.Front
	dec.Color3 = WHITE
	dec.Transparency = 0
	local tex = BodyTiers.FaceTexture(style)
	if dec.Texture ~= tex then
		dec.Texture = tex
	end
	dec:SetAttribute("FaceStyle", style)
	dec.Parent = head
	-- (tagged once parented: the tag's added signal finds the model from it)
	if not CollectionService:HasTag(dec, "FaceDecal") then
		CollectionService:AddTag(dec, "FaceDecal")
	end
	return dec
end

-- Builder's Face step, also when the face is served from cache: a drawn style's decal is on the head (something
-- may have replaced or removed it since the face was built: an ApplyDescription, a head swap). Built faces: no-op
function Head.EnsureFaceDecal(model)
	local head = model:FindFirstChild("Head")
	local style = Head.FaceStyle(model)
	if not (head and style) then
		return
	end
	local cur = head:FindFirstChild("face")
	local n = 0
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") then
			n += 1
		end
	end
	if n == 1 and cur and cur:IsA("Decal") and cur:GetAttribute("FaceStyle") == style and cur.Transparency == 0 then
		return
	end
	putFaceDecal(head, style)
end

------------------------------------------------------------------------
-- Face
------------------------------------------------------------------------
-- eyebrow shapes: thickness, arch (inner rise / tail drop), length, tail taper
local BROWS = {
	Natural = { thick = 1, arch = 0.4, len = 1, taper = 0.75 },
	Straight = { thick = 1, arch = 0.05, len = 1.03, taper = 0.85 },
	["Soft Arch"] = { thick = 0.85, arch = 0.65, len = 1, taper = 0.65 },
	["High Arch"] = { thick = 0.75, arch = 1, len = 0.98, taper = 0.55 },
	Thick = { thick = 1.45, arch = 0.3, len = 1.05, taper = 0.85 },
	Thin = { thick = 0.6, arch = 0.55, len = 0.95, taper = 0.5 },
}

-- which face rig roles exist at each detail level (CONTRACTS section 5)
local function rigOn(detail, role)
	if detail == "full" then
		return true
	end
	return detail == "medium" and (role == "EyeL" or role == "EyeR" or role == "BrowL" or role == "BrowR")
end

------------------------------------------------------------------------
-- Part budget (CONTRACTS section 16 B: baseline = the pre-overhaul face + old hair + old beard)
------------------------------------------------------------------------
-- A's share of Config.Detail[d].partBudget (B owns the other half; medium / low are whole-character
-- limits, so A keeps half of medium and nothing at low). Every head step records its parts over the
-- baseline in its folder's attribute "Extra"; the face is built first and takes what it needs (capped
-- by FACE_CAP), the hair gets the rest minus a beard reserve, the beard builds last into what is left.
local A_BUDGET = { full = 60, medium = 10, low = 0 }
local FACE_CAP = { full = 38, medium = 6, low = -2 }
local BEARD_RESERVE = { full = 4, medium = 2, low = 0 }
-- per-cut ceiling (section 16 A: hero ~60, NPC ~30 hair parts) even where the old hair had more
local HAIR_MAX = { full = 60, medium = 30, low = 15 }

local function countParts(folder)
	local n = 0
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
	end
	return n
end

-- the Extra a step recorded (nil-safe: a missing folder costs its default)
local function extraOf(model, name, default)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild(name)
	local v = f and f:GetAttribute("Extra")
	return type(v) == "number" and v or default
end

-- part count of the pre-overhaul face for these sliders (it had no detail levels)
local function oldFaceParts(face, opts)
	local shape = face.shape or "Oval"
	local jawW, cheek, cheekFat, chinDrop, browRidge = face.jawWidth or 0, face.cheek or 0, 0, 0, 0
	if shape == "Square" then
		jawW += 0.6
	elseif shape == "Diamond" then
		cheek += 0.7
		jawW -= 0.5
	elseif shape == "Round" then
		cheekFat = 0.8
		jawW += 0.3
	elseif shape == "Long" then
		chinDrop = 0.12
		cheek -= 0.3
	elseif shape == "Heart" then
		browRidge = 0.6
		jawW -= 0.4
	end
	-- ears, chin, 2 x (sclera, iris, pupil, glint, lid, brow), nose + tip, nostrils, lips + mouth line
	local n = 22
	n += (jawW > 0.1 and 1 or 0) + (chinDrop > 0 and 1 or 0) + (cheek > -0.5 and 2 or 0) + (cheekFat > 0 and 2 or 0)
	n += (math.max(browRidge, (face.forehead or 0) * 0.6) > 0.2 and 1 or 0) + ((face.lashes or 0) > 0.15 and 2 or 0)
	n += math.floor((face.freckles or 0) * 26) + math.floor(face.moles or 0) + math.floor(face.scars or 0)
	n += math.floor((face.acne or 0) * 14) + ((face.marks or 0) > 0.05 and 1 or 0) + (opts.mouthguard and 1 or 0)
	return n
end

-- the beard style beardBuild draws for this app (nil = none), whether it is a mere shadow, its growth and
-- whether the style comes from growth alone (no style chosen); shared with the face (lips through a beard)
local function beardStyle(app)
	if app.gender == 2 then
		return nil
	end
	local beard = type(app.beard) == "table" and app.beard or {}
	local style = beard.style or "None"
	if not table.find(Looks.BeardStyles, style) then
		style = Looks.BeardStyleBase[style] or "None"
	end
	local g = clamp(tonumber(beard.growth) or 0, 0, 1)
	if style == "None" then
		if g < 0.2 then
			return nil
		elseif g < 0.8 then
			return "Stubble", g < 0.45, g, true
		end
		return "Short Boxed", false, (g - 0.8) * 2, true
	end
	return style, false, g, false
end

-- part count of the pre-overhaul beard
local function oldBeardParts(app)
	if app.gender == 2 then
		return 0
	end
	local beard = type(app.beard) == "table" and app.beard or {}
	local style = beard.style or "None"
	if style == "None" then
		return clamp(tonumber(beard.growth) or 0, 0, 1) >= 0.45 and 1 or 0
	end
	return (style == "Stubble" or style == "Moustache") and 1 or (style == "Chin Strap" and 3 or 2)
end

-- everything the Face step reads from app.hair / app.beard / app.attire, for B's head cache key (Builder
-- headSig) in place of the whole tables: the brow colour, whether a beard covers the lips and the
-- mouthguard colour. Any other hair / beard / attire change never changes the face.
function Head.FaceSigParts(app)
	app = type(app) == "table" and app or {}
	local style = beardStyle(app)
	return {
		hairColor = (type(app.hair) == "table" and app.hair.color) or false,
		lipsCovered = style ~= nil and style ~= "Stubble",
		mouthguard = (type(app.attire) == "table" and app.attire.mouthguard) or false,
	}
end

-- road dirt on the face (CONTRACTS section 7: I sets the model attribute Grime after roadwork and clears
-- it at the shower; an opts.grime given to the last face build wins). Its own folder keyed by level,
-- detail and head, so Head.SetSweat - which B runs at the end of every Cosmetics, head-only rebuilds
-- included - shows and clears it without a face rebuild (the face itself may be served from cache).
local function faceGrime(model, app)
	local head = part(model, "Head")
	local look = model:FindFirstChild("BoxerLook")
	if not (head and look) then
		return
	end
	local faceF = look:FindFirstChild("Face")
	local detail = (faceF and faceF:GetAttribute("Detail")) or model:GetAttribute("Detail") or "full"
	local g = tonumber(faceF and faceF:GetAttribute("OptGrime")) or tonumber(model:GetAttribute("Grime")) or 0
	g = math.floor(clamp(g, 0, 1) * 10 + 0.5) / 10
	local old = look:FindFirstChild("FaceGrime")
	if g <= 0.1 or detail ~= "full" then
		if old then
			old:Destroy()
		end
		return
	end
	local L = Head.FaceLayout(head, (app and app.face) or {})
	if faceF and faceF:GetAttribute("FaceStyle") then
		Head.DecalLayout(L)
	end
	local key = string.format("%.1f|%.3f|%.3f", g, head.Size.X, L.browY)
	if old and old:GetAttribute("Key") == key then
		local p = old:FindFirstChildWhichIsA("BasePart")
		local w = p and p:FindFirstChildOfClass("WeldConstraint")
		if w and w.Part0 == head then
			return
		end
	end
	local folder = getFolder(model, "FaceGrime")
	folder:SetAttribute("Key", key)
	local s, hcf = L.s, head.CFrame
	local dirt = Color3.fromRGB(110, 90, 70)
	-- (flat translucent patches lying on the skin)
	local function patch(x, y, w, h, t)
		local cf, size = lens(L, x, y, w, h, 0.0018, 0.85)
		mk(folder, head, "Grime", size, hcf * cf, dirt, "Ellipsoid", SMOOTH, t)
	end
	patch(-0.1 * s.X, L.browY + 0.08 * s.Y, 0.26 * s.X, 0.1 * s.Y, 0.88 - 0.22 * g)
	if g > 0.5 then
		patch(0.3 * s.X, -0.15 * s.Y, 0.16 * s.X, 0.12 * s.Y, 0.9 - 0.22 * g)
	end
end

-- the classic head: the engine's default head (a MeshPart; a dynamic head bakes its face into the mesh, and that
-- texture cannot be removed while the game runs) is swapped once for a plain Part of the same size with the
-- Head SpecialMesh, the classic Roblox head the built face sits on. Builder keeps it at the engine's scale.
local function classicHead(model, head)
	if not head:IsA("MeshPart") then
		return head
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local clean = Instance.new("Part")
	clean.Name = "Head"
	clean.Size = head.Size
	clean.Color = head.Color
	clean.Material = head.Material
	clean.CFrame = head.CFrame
	clean.CanCollide = head.CanCollide
	clean.Massless = head.Massless
	clean.TopSurface = Enum.SurfaceType.Smooth
	clean.BottomSurface = Enum.SurfaceType.Smooth
	local hm = Instance.new("SpecialMesh")
	hm.MeshType = Enum.MeshType.Head
	hm.Parent = clean
	for _, c in ipairs(head:GetChildren()) do
		if c:IsA("Attachment") then
			c:Clone().Parent = clean
		end
	end
	local swapped, err = false, "no Humanoid"
	if hum then
		swapped, err = pcall(function()
			hum:ReplaceBodyPartR15(Enum.BodyPartR15.Head, clean)
		end)
	end
	local got = model:FindFirstChild("Head")
	if swapped and got == clean then
		if not clean:FindFirstChildOfClass("SpecialMesh") then
			Head.SwapFailed(model, "the engine dropped the Head SpecialMesh from the classic head")
		end
		return clean
	end
	-- the face, the headgear and the caps are built for the classic head's profile: on the engine's MeshPart head
	-- they sit in or off the skull. One Output line per reason
	Head.SwapFailed(model, swapped and ("the model still carries " .. (got and (got.ClassName .. " " .. got.Name) or "no Head")) or tostring(err))
	clean:Destroy()
	pcall(function()
		head.TextureID = ""
	end)
	return head
end
Head.ClassicHead = classicHead

-- the classic head swap did not take (warned once per reason; Head.SwapFailures counts them for tests / the diagnostic)
Head.SwapFailures = 0
local headSwapWarned = {}
function Head.SwapFailed(model, reason)
	Head.SwapFailures += 1
	local inGame = false
	pcall(function()
		inGame = model:IsDescendantOf(game)
	end)
	local key = tostring(reason) .. "|" .. tostring(inGame)
	if headSwapWarned[key] then
		return
	end
	headSwapWarned[key] = true
	warn(string.format("[Boxer] classic head swap did not take on %s: %s; %s (the headgear / face are built for the classic head)",
		tostring(model and model.Name), tostring(reason),
		inGame and "the model is in the DataModel" or "the model is OUTSIDE the DataModel: the engine cannot swap its parts there"))
end

-- a player's avatar face (Builder: the AvatarFace attribute, Config.AvatarLook.face): the head and face the
-- engine put on from the avatar's description stay exactly as they are; no built face. An empty Face folder
-- seals the step's cache (Extra 0: the hair and beard keep their share of the budget)
function Head.AvatarFace(model, _app, opts)
	if not model:FindFirstChild("Head") then
		return
	end
	local folder = getFolder(model, "Face")
	folder:SetAttribute("Detail", (Config.DetailLevel(opts or {})))
	folder:SetAttribute("Extra", 0)
	folder:SetAttribute("Avatar", true)
end

local function faceBuild(model, app, opts, build)
	opts = opts or {}
	app = app or {}
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local face = app.face or Looks.Defaults(app.gender).face
	-- the classic head (the default head's baked face cannot be removed while the game runs), then only the
	-- built face: an engine face decal, an older build's classic-face / damage decals, face controls go
	head = classicHead(model, head)
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") or d:IsA("FaceControls") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	if model:GetAttribute("FaceKey") ~= nil then
		model:SetAttribute("FaceKey", nil) -- (the retired classic decal face's key)
	end
	-- a drawn face style: its decal on the head front instead of the built eyes, brows, nose and mouth (every boxer:
	-- DrawnStyleOf falls back to the default drawn face; nil only with no drawn face uploaded)
	local drawn = BodyTiers.DrawnStyleOf(app)
	if drawn then
		putFaceDecal(head, drawn)
	end
	local detail, D = Config.DetailLevel(opts)
	local full, low = detail == "full", detail == "low"
	local folder = getFolder(model, "Face")
	folder:SetAttribute("Detail", detail)
	folder:SetAttribute("FaceStyle", drawn)
	local L = Head.FaceLayout(head, face)
	if drawn then
		Head.DecalLayout(L)
	end
	local s = L.s
	local hcf = head.CFrame
	local skin = skinOf(app)
	local skinL = lum(skin)
	local under = UNDERTONE[face.undertone or "Neutral"] or UNDERTONE.Neutral
	local hairColor = Looks.Color(app.hair and app.hair.color, Color3.fromRGB(30, 22, 18))
	local battle = type(app.battle) == "table" and app.battle or {}
	local female = app.gender == 2
	local age = tonumber(opts.age) or 24
	local FB = Config.BodyFat
	local fat = (type(build) == "table" and tonumber(build.fat)) or FB.default
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	local function add(name, size, cf, color, shape, material, transparency)
		return mk(folder, head, name, size, cf, color, shape or "Ellipsoid", material, transparency)
	end
	local function rig(role, side, name, size, cf, color, shape, material, transparency)
		if not rigOn(detail, role) then
			return add(name, size, cf, color, shape, material, transparency)
		end
		local p = mk(folder, nil, name, size, cf, color, shape or "Ellipsoid", material, transparency)
		local m = joint(head, p, "FaceJoint")
		m:SetAttribute("Role", role)
		if side then
			m:SetAttribute("Side", side)
		end
		CollectionService:AddTag(m, "FaceRig")
		return p
	end
	-- a thin mark lying on the skin, rising `rise` (default 0.0015) above it (Kit.mk's 0.02 floor is its thickness)
	local function line(name, x0, y0, x1, y1, width, color, transparency, rise)
		return surfaceLine(folder, head, head, L, name, x0, y0, x1, y1, width, 0.02, color, transparency, (rise or 0.0015) - 0.01)
	end
	-- a lens on the skin (see lens above); o = { roll, base, mat, t (transparency), anchor, role, side }
	local function lp(name, x, y, w, h, rise, dk, color, o)
		o = o or {}
		local cf, size = lens(L, x, y, w, h, rise, dk, o.roll, o.base)
		cf = hcf * cf
		if o.role then
			return rig(o.role, o.side, name, size, cf, color, "Ellipsoid", o.mat, o.t)
		end
		return mk(folder, o.anchor or head, name, size, cf, color, "Ellipsoid", o.mat, o.t)
	end
	-- skin finish: a pore-heavy or rough skin uses Plastic (a fine grain), smooth skin SmoothPlastic
	head.Material = ((face.smooth or 0.5) >= 0.5 and (face.pores or 0) < 0.5) and SMOOTH or PLASTIC
	head.Reflectance = (face.shine or 0) * 0.03

	-- face shape presets layered on top of the sliders
	local shape = face.shape or "Oval"
	local jawW, jawDef, chin, cheek = face.jawWidth or 0, face.jawDef or 0.5, face.chin or 0, face.cheek or 0
	local chinDrop, chinNarrow, cheekFat, browRidge = 0, 0, 0, 0
	if shape == "Square" then
		jawW += 0.6
		jawDef = math.max(jawDef, 0.85)
	elseif shape == "Diamond" then
		cheek += 0.7
		jawW -= 0.5
		chinNarrow = 0.35
	elseif shape == "Round" then
		cheekFat = 0.8
		jawW += 0.3
		jawDef = math.min(jawDef, 0.2)
	elseif shape == "Long" then
		chinDrop = 0.12
		cheek -= 0.3
	elseif shape == "Heart" then
		browRidge = 0.6
		jawW -= 0.4
		chinNarrow = 0.45
	end
	-- body fat shows in the face first: fuller cheeks, then jowls; lean or weight-cut faces hollow out
	local faceFat = clamp((fat - FB.faceFatAt) / 8, 0, 1)
	local jowl = clamp((fat - FB.jowlsAt) / 7, 0, 1)
	local gaunt = math.max(clamp((FB.gauntBelow + 1 - fat) / 3, 0, 1), clamp(tonumber(opts.dry) or 0, 0, 1))
	local cheekFull = face.cheekFull or 0
	cheekFat = math.max(cheekFat, faceFat * 0.9, cheekFull * 0.8) * (1 - 0.7 * gaunt)
	local hollow = clamp(math.max(gaunt, -cheekFull * 0.8) - cheekFat, 0, 1)
	-- wear a boxer chose plus wear earned in fights (server-only app.battle)
	local cauli = math.max(face.cauliflower or 0, tonumber(battle.ears) or 0)
	local noseBreak = math.max(face.noseBreak or 0, tonumber(battle.nose) or 0)
	local wr = math.max(face.wrinkles or 0, clamp((age - 30) / 26, 0, 1) * 0.85)
	local scarCount = type(battle.scars) == "table" and #battle.scars or 0
	-- optional detail spends from two small budgets so a veteran, aged, pore-heavy face stays inside
	-- the part budget: wear (scars, cauliflower, bent nose) first, then age / skin cosmetics. A spend
	-- also never takes the face past FACE_CAP parts over the old face, leaving the hair its share.
	local budget = { wear = full and 8 or (detail == "medium" and 2 or 0), skin = full and 8 or (detail == "medium" and 1 or 0) }
	local oldParts = oldFaceParts(face, opts)
	local function spend(kind, n)
		if budget[kind] < n or countParts(folder) + n - oldParts > FACE_CAP[detail] then
			return false
		end
		budget[kind] -= n
		return true
	end
	-- optional details are queued and drawn at the end in this order, when every fixed part exists and
	-- the cap check above sees the real count (fn may spend() again for nested extras)
	local queued = {}
	local function opt(kind, n, fn)
		queued[#queued + 1] = { kind, n, fn }
	end
	-- left / right halves of one detail are queued as a pair so a face is never shaded on one side only
	local sides = {}
	local function side2(key, kind, n, fn)
		local entry = sides[key]
		if not entry then
			entry = {}
			sides[key] = entry
			opt(kind, n * 2, function()
				for _, f in ipairs(entry) do
					f()
				end
			end)
		end
		entry[#entry + 1] = fn
	end

	-- Every feature is a lens on the classic head (lens / lp above: an ellipsoid sunk into the skin so only a low
	-- dome of the size asked shows, its rim on the skin): nothing stands off the face or sinks into it. Heights
	-- (rise) are fractions of s.Z: skin sculpt 0.005 .. 0.02, the eye 0.006 .. 0.012, lids and brows ~0.01 .. 0.02,
	-- the nose tip ~0.05 (the one feature that stands out).

	-- ears: a low shell flush on the side wall, inside the arc the hair keeps clear (Kit.CLASSIC_HAIR.ear: centre y
	-- 0.035, z 0.06 nominal), its back edge turned out a little, the darker bowl of the concha in it; cauliflower
	-- lumps fill the upper rim
	local earS = 1 + 0.2 * (face.earSize or 0)
	local earW, earH = 0.13 * s.Z * earS, 0.26 * s.Y * earS
	local earRise = (0.026 + 0.012 * cauli) * s.X
	for side = -1, 1, 2 do
		-- (shellCF's local +X is the back on the right side, the front on the left)
		local ecf = hcf * L.shellCF(side * rad(96), 0.03 * s.Y, 0) * ANG(0, side * rad(10 + 12 * cauli), 0)
		local D = earRise / 0.55
		local f = math.sqrt(1 - 0.45 * 0.45)
		add("Ear", V3(earW / f, earH / f, 2 * D), ecf * CF(0, 0, D - earRise), skin, "Ellipsoid")
		if full then
			-- the concha: a darker hollow toward the front of the ear, just above its surface
			add("EarHelix", V3(earW * 0.5, earH * 0.5, 0.02), ecf * CF(-side * 0.12 * earW, -0.06 * earH, 0.01 - earRise * 0.92 - 0.0015),
				darken(skin, 0.86), "Ellipsoid")
		end
		if cauli > 0.15 and not low then
			local lumps = full and math.min(2, 1 + math.floor(cauli * 2)) or 1
			side2("cauli", "wear", lumps, function()
				for i = 1, lumps do
					local sz = (0.045 + 0.04 * cauli) * s.X * (1 - 0.15 * (i - 1))
					add("Cauliflower", V3(sz, sz * 1.1, sz * 0.8), ecf * CF(side * 0.12 * earW, (0.24 - 0.2 * (i - 1)) * earH, -earRise * 0.7),
						lerpColor(skin, Color3.fromRGB(150, 100, 100), 0.12 + 0.1 * cauli), "Ellipsoid")
				end
			end)
		end
	end
	-- jaw angles: low swells at the corners of the jaw (wider jaws further out, defined jaws higher)
	-- (only on defined or wide jaws: on the round classic head a soft jaw is the head itself)
	local jw = clamp(jawW, -1, 1.6)
	local ja = (female and 0.7 or 1) * (clamp((jawDef - 0.45) / 0.55, 0, 1) + 0.5 * clamp(jw - 0.3, 0, 1))
	if full and ja > 0.2 then
		for side = -1, 1, 2 do
			lp("JawAngle", side * (0.39 + 0.03 * jw) * s.X, -0.33 * s.Y, 0.24 * s.Y, (0.075 + 0.015 * jw) * s.X, (0.002 + 0.008 * ja) * s.Z, 0.6, skin,
				{ roll = side * rad(-48) })
		end
	end
	-- chin: a soft swell on the rounded bottom edge of the head
	local chinY = (-0.385 - 0.025 * chin - chinDrop * 0.5) * s.Y
	local chinRise = (0.0065 + 0.0055 * chin + 0.003 * jawDef) * s.Z
	lp("Chin", 0, chinY + 0.005 * s.Y, (0.24 + 0.07 * chin) * (1 - chinNarrow) * s.X, (0.11 + 0.03 * chin + chinDrop * 0.3) * s.Y, math.max(chinRise, 0.0015), 0.72, skin)
	if chinDrop > 0 then -- long face: extend the lower face
		add("LowerFace", V3(0.7 * s.X, chinDrop * 2 * s.Y, 0.7 * s.Z), at(0, -0.5 * s.Y, 0), skin, "Ellipsoid")
	end
	if (face.chinCleft or 0) > 0.15 and full then
		opt("skin", 1, function()
			local c = face.chinCleft
			lp("ChinCleft", 0, chinY + 0.005 * s.Y, 0.014 * s.X, (0.05 + 0.05 * c) * s.Y, 0.0015, 0.85, darken(skin, 0.8), { base = chinRise * 0.85, t = 0.75 - 0.35 * c })
		end)
	end
	if jowl > 0.05 and full then
		opt("skin", 2, function()
			for side = -1, 1, 2 do
				add("Jowl", V3(0.2 * s.X, (0.14 + 0.06 * jowl) * s.Y, 0.24 * s.Z), at(side * 0.3 * s.X, -0.38 * s.Y, -0.24 * s.Z), skin, "Ellipsoid")
			end
		end)
	end
	if jowl > 0.3 and not low then
		opt("skin", 1, function()
			add("DoubleChin", V3((0.42 + 0.12 * jowl) * s.X, (0.1 + 0.06 * jowl) * s.Y, 0.45 * s.Z), at(0, -0.5 * s.Y, -0.18 * s.Z), skin, "Ellipsoid")
		end)
	end
	-- cheekbones and cheeks (lean faces show more bone); below full detail full cheeks replace the bone. The
	-- slider and the Diamond preset reach cheek = 1.7: clamped, so high cheekbones stay a swell
	-- (flat cheeks shade in under the bone; high cheekbones stand out as a long swell up to the ear)
	hollow = math.max(hollow, clamp((-cheek - 0.2) / 0.8, 0, 1) * 0.6)
	local fullCheeks = cheekFat > 0.05 and hollow <= 0.1
	local ck = clamp(cheek, -0.5, 1)
	local boneRise = 0.0075 * clamp((ck - 0.05) / 0.95, 0, 1) + 0.003 * hollow
	if boneRise > 0.0015 and (full or not fullCheeks) then
		for side = -1, 1, 2 do
			lp("Cheekbone", side * 0.33 * s.X, -0.03 * s.Y, (0.26 + 0.03 * ck) * s.X, (0.085 + 0.015 * ck) * s.Y, boneRise * s.Z, 0.78, skin, { roll = side * rad(20) })
		end
	end
	if fullCheeks then
		for side = -1, 1, 2 do
			lp("Cheek", side * 0.37 * s.X, -0.17 * s.Y, 0.26 * s.X, 0.28 * s.Y, (0.005 + 0.008 * math.min(cheekFat, 1)) * s.Z, 0.82, skin)
		end
	end
	if hollow > 0.1 and full then
		for side = -1, 1, 2 do
			lp("Hollow", side * 0.3 * s.X, -0.13 * s.Y, 0.16 * s.X, 0.14 * s.Y, 0.0015, 0.88, darken(skin, 0.8), { t = 0.82 - 0.3 * hollow })
		end
	end
	-- brow ridge: two low swells over the eyes the brows lie on (scar tissue thickens it on veterans); its height
	-- under any point is kept so the brows sit on it, never floating off it or sinking in
	local ridge = math.max(browRidge, (face.forehead or 0) * 0.6, female and 0 or 0.25, math.min(scarCount, 3) * 0.15)
	local ridges = {}
	local function ridgeAt(x, y)
		local best = 0
		for _, r in ipairs(ridges) do
			local q = 1 - ((x - r.x) / r.a) ^ 2 - ((y - r.y) / r.b) ^ 2
			if q > 0 then
				best = math.max(best, r.D * math.sqrt(q) - r.c)
			end
		end
		return best
	end
	local function ridgeLens(x, y, w, h, rise, roll)
		local p = lp("BrowRidge", x, y, w, h, rise, 0.6, skin, { roll = roll })
		local _, size, D, c = lens(L, x, y, w, h, rise, 0.6, roll)
		table.insert(ridges, { x = x, y = y, a = size.X / 2, b = size.Y / 2, D = D, c = c })
		return p
	end
	-- (a heavy brow only: a heart face, a big forehead, scar tissue; an ordinary brow lies on the flat front. Full detail
	-- only: across both brows at a distance it read as a band over the forehead)
	if full and ridge > 0.3 and not drawn then
		for side = -1, 1, 2 do
			-- (no taller than the brow on it, which hides its rim: a taller one drew a second line over the brow)
			local rb = (0.03 + 0.018 * ((face.browThick or 0) + 1)) * s.Y * (BROWS[face.browStyle or "Natural"] or BROWS.Natural).thick
			ridgeLens(side * 0.18 * s.X, L.browY - 0.006 * s.Y, (0.26 + 0.04 * ridge) * s.X, rb * 1.05, (0.002 + 0.01 * (ridge - 0.25)) * s.Z, side * rad(-4))
		end
	end

	-- eyes: set into the head. A shallow white, the iris (limbal ring) and pupil just proud of it, the upper lid a
	-- fold that covers the top of the iris (its edge the lash line), a low lower lid; nothing stands far off the face.
	local eyeColors = {
		[-1] = Looks.Color(Looks.EyeColors[face.eyeColor or 2]),
		[1] = Looks.Color(Looks.EyeColors[(face.eyeColor2 or 0) > 0 and face.eyeColor2 or (face.eyeColor or 2)]),
	}
	local lidColor = darken(skin, 0.92)
	-- whites of the eye are never pure white; they yellow slightly with age
	local scleraColor = lerpColor(Color3.fromRGB(236, 232, 224), Color3.fromRGB(230, 220, 200), clamp((age - 25) / 30, 0, 1))
	local heavy = clamp(face.lidHeavy or 0, 0, 1)
	local brow = BROWS[face.browStyle or "Natural"] or BROWS.Natural
	local browColor = darken(hairColor, 0.88)
	local bt = (0.03 + 0.018 * ((face.browThick or 0) + 1)) * s.Y * brow.thick
	local lashT = 1 - (0.35 + 0.6 * clamp(face.lashes or 0, 0, 1))
	local underEye = full and (wr > 0.3 or heavy > 0.6)
	local w, h = L.eyeW, L.eyeHt
	local rWhite, rLimb, rIris, rPupil, rGlint = 0.006 * s.Z, 0.0088 * s.Z, 0.0095 * s.Z, 0.0104 * s.Z, 0.0116 * s.Z
	local browInfo = {}
	-- (a drawn face style: the eyes and brows are its decal; none of these parts or their rig joints)
	if not drawn then
		for side = -1, 1, 2 do
			local roleSide = side == -1 and "L" or "R"
			local x0, y0 = side * L.eyeX, L.eyeYS[side]
			-- eye frame: canthal tilt raises the outer corner
			local roll = side * L.eyeTilt
			local cr, sr = math.cos(roll), math.sin(roll)
			local function ep(dx, dy)
				return x0 + dx * cr - dy * sr, y0 + dx * sr + dy * cr
			end
			local ef = surfCF(L, x0, y0, 0) * ANG(0, 0, roll)
			local eyeColor = eyeColors[side]
			local scf, ssz, sD, sc = lens(L, x0, y0, w, h, rWhite, 0.72, roll)
			local sclera = add("Sclera", ssz, hcf * scf, scleraColor, "Ellipsoid")
			sclera:SetAttribute("BaseColor", scleraColor)
			sclera:SetAttribute("Side", side)
			sclera:SetAttribute("VisW", w)
			sclera:SetAttribute("VisH", h)
			local sa, sb = ssz.X / 2, ssz.Y / 2
			local function hWhite(u, v)
				local q = 1 - (u / sa) ^ 2 - (v / sb) ^ 2
				return q > 0 and sD * math.sqrt(q) - sc or 0
			end
			-- iris, limbal ring and pupil ride on an invisible EyeBall pivot behind the eye so the client can turn the
			-- gaze; the catchlight stays fixed to the head like a real reflection. Each is shaped (across and up apart)
			-- so its rim meets the white in a circle.
			local rho = 0.5 * math.min(0.58 * w, 0.98 * h)
			local holder = head
			if rigOn(detail, "Eye" .. roleSide) then
				holder = rig("Eye" .. roleSide, side, "EyeBall", V3(0.04, 0.04, 0.04), hcf * ef * CF(0, 0, 0.03), scleraColor, "Ball", SMOOTH, 1)
				holder:SetAttribute("Side", side)
			end
			local iD = rIris + 0.004 * s.Z
			local iax = capOn(rIris, rho, hWhite(rho, 0), iD)
			local iay, _, ic = capOn(rIris, rho, hWhite(0, rho), iD)
			local function hIris(u, v)
				local q = 1 - (u / iax) ^ 2 - (v / iay) ^ 2
				return q > 0 and iD * math.sqrt(q) - ic or 0
			end
			if full then
				local lD = rLimb + 0.004 * s.Z
				local lax = capOn(rLimb, rho * 1.13, hWhite(rho * 1.13, 0), lD)
				local lay, _, lc = capOn(rLimb, rho * 1.13, hWhite(0, rho * 1.13), lD)
				mk(folder, holder, "Limbal", V3(2 * lax, 2 * lay, 2 * lD), hcf * ef * CF(0, 0, lc), darken(eyeColor, 0.45), "Ellipsoid")
			end
			local iris = mk(folder, holder, "Iris", V3(2 * iax, 2 * iay, 2 * iD), hcf * ef * CF(0, 0, ic), eyeColor, "Ellipsoid")
			iris:SetAttribute("VisW", 2 * rho)
			local pr = rho * 0.44
			local pD = rPupil + 0.003 * s.Z
			local pax = capOn(rPupil, pr, hIris(pr, 0), pD)
			local pay, _, pc = capOn(rPupil, pr, hIris(0, pr), pD)
			mk(folder, holder, "Pupil", V3(2 * pax, 2 * pay, 2 * pD), hcf * ef * CF(0, 0, pc), Color3.fromRGB(10, 9, 10), "Ellipsoid")
			local gx, gy = side * rho * 0.28, rho * 0.3
			local ga, gD, gc = capOn(rGlint, rho * 0.15, hIris(gx, gy) + 0.0006, 0.01)
			local glint = add("Glint", V3(2 * ga, 2 * ga, 2 * gD), hcf * ef * CF(gx, gy, gc), WHITE, "Ellipsoid")
			glint:SetAttribute("Side", side) -- (SetDamage hides it while a swollen lid has the eye shut)
			-- upper lid: a fold over the top of the eye; its lower edge (where it meets the eye) is the lid line, at 0.3 of
			-- the eye's height above its middle (hooded lids come lower). CloseY: how far that edge travels to shut the eye
			-- (FaceFX); damage swelling hides it
			local lidLine = h * (0.36 - 0.2 * heavy)
			local lb = (h * 0.98 - lidLine) / 1.75
			local lx, ly = ep(0, lidLine + 0.8 * lb)
			local lid = lp("Lid", lx, ly, w * 1.16, 1.9 * lb, (0.0128 + 0.005 * heavy) * s.Z, 0.3, lidColor, { roll = roll, role = "Lid" .. roleSide, side = side })
			lid:SetAttribute("Side", side)
			lid:SetAttribute("CloseY", lidLine + h * 0.5)
			if not low then
				-- the lash line along the lid's edge, welded to the lid so it follows a blink or squint
				local ax, ay = ep(0, lidLine)
				local lashes = lp("Lashes", ax, ay, w * 1.05, (0.011 + 0.008 * clamp(face.lashes or 0, 0, 1)) * s.Y, 0.0122 * s.Z, 0.5,
					Color3.fromRGB(18, 13, 11), { roll = roll, anchor = lid, t = math.max(0.08, lashT) })
				lashes:SetAttribute("BaseT", lashes.Transparency)
				lashes:SetAttribute("Side", side)
			end
			if full then
				-- the lid crease shows on hooded and ageing lids
				if heavy > 0.3 or wr > 0.4 then
					side2("crease", "skin", 1, function()
						local cx, cy = ep(0, h * 1.0)
						lp("Crease", cx, cy, w * 0.95, 0.01 * s.Y, 0.0015, 0.8, darken(skin, 0.74), { roll = roll, t = 0.45 + 0.4 * heavy })
					end)
				end
				-- lower lid: a low rim under the eye with the wet line in its colour, rigged for squints
				local ux, uy = ep(0, -h * 0.56)
				local lower = lp("LowerLid", ux, uy, w * 1.0, h * 0.28, 0.008 * s.Z, 0.45,
					lerpColor(lerpColor(lidColor, skin, 0.5), Color3.fromRGB(226, 160, 158), 0.12), { roll = roll, role = "LowerLid" .. roleSide, side = side })
				lower:SetAttribute("Side", side)
			end
			if not low then
				-- the closed lid the client shows for a blink (never the Lid, which SetDamage hides)
				local kx, ky = ep(0, h * 0.04)
				local blink = lp("BlinkLid", kx, ky, w * 1.14, h * 1.18, 0.0165 * s.Z, 0.5, lerpColor(lidColor, skin, 0.4), { roll = roll, t = 1 })
				blink:SetAttribute("Side", side)
			end
			if underEye then
				side2("underEye", "skin", 1, function()
					local ux, uy = ep(0, -h * 0.92)
					lp("UnderEye", ux, uy, w * 1.1, h * 0.5, 0.0015, 0.86, darken(skin, 0.82), { roll = roll, t = 0.82 - 0.3 * wr })
				end)
			end
			-- eyebrow: a solid strip on the brow ridge in three overlapping pieces along the style's arch (inner head,
			-- body, tapering tail); the body is the rigged part, the others are welded to it. Below full detail the body
			-- alone spans the brow.
			local bx = side * L.eyeX * 1.02
			local by = L.browY + (L.eyeYS[side] - L.eyeY)
			local tilt = side * ((face.browAngle or 0) * rad(9)) + L.browTiltS[side]
			local blen = 0.21 * s.X * brow.len
			local ar = brow.arch
			local ct, st = math.cos(tilt), math.sin(tilt)
			-- a point along the brow: t -0.5 (inner end) .. 0.5 (tail), its height on the arch
			local function bpt(t)
				local dy
				-- (the arch's peak on the brow line: the hair's front edge keeps clear of it, ref/classic browTop)
				if t <= 0.1 then
					dy = bt * (-0.5 * ar * ((t - 0.1) / 0.6) ^ 2)
				else
					dy = bt * (-(0.25 + 1.15 * ar) * ((t - 0.1) / 0.4) ^ 2)
				end
				local dx = side * t * blen
				return bx + dx * ct - dy * st, by + dx * st + dy * ct
			end
			local browRise = (0.0055 + 0.003 * brow.thick) * s.Z
			local function seg(name, t0, t1, thick, anchorPart)
				local xa, ya = bpt(t0)
				local xb, yb = bpt(t1)
				local xm, ym = bpt((t0 + t1) / 2)
				local cx, cy = (xa + xb) / 2 * 0.5 + xm * 0.5, (ya + yb) / 2 * 0.5 + ym * 0.5
				local dx, dy = xb - xa, yb - ya
				local len = math.sqrt(dx * dx + dy * dy)
				local base = 0.5 * (math.min(ridgeAt(xa, ya), ridgeAt(xb, yb)) + ridgeAt(cx, cy))
				local sg = dx < 0 and -1 or 1
				local o = { roll = math.atan2(dy * sg, dx * sg), base = base, mat = FABRIC }
				if anchorPart then
					o.anchor = anchorPart
				else
					o.role, o.side = "Brow" .. roleSide, side
				end
				return lp(name, cx, cy, len * 1.1, thick, browRise, 0.4, browColor, o), base
			end
			local browPart, bBase
			if full then
				browPart, bBase = seg("Brow", -0.3, 0.32, bt * 0.94)
				seg("BrowInner", -0.5, 0.0, bt * (1 + 0.08 * brow.thick), browPart)
				seg("BrowOuter", 0.15, 0.5, bt * brow.taper * 0.8, browPart)
			else
				browPart, bBase = seg("Brow", -0.5, 0.5, bt * 0.9)
			end
			browPart:SetAttribute("Side", side)
			browInfo[side] = { part = browPart, base = bBase, rise = browRise, y = by }
		end
	end

	-- nose: a bridge running down from between the eyes into a rounded tip, the alar wings either side of it and the
	-- nostrils under it; a broken nose sits flatter, wider and bent
	local bend = (Random.new((face.seed or 7) + 303):NextNumber() < 0.5) and -1 or 1
	local nW = L.noseW * (1 + 0.2 * noseBreak)
	local proj = L.noseB * (0.56 - 0.14 * noseBreak) -- how far the tip stands off the face
	local dev = L.noseDev + 0.03 * noseBreak * bend * s.X
	local noseCol = darken(skin, 0.97)
	local nroll = rad(-7 * noseBreak * bend)
	local tipY = L.noseBottomY + nW * 0.3
	-- the bridge: a narrow ridge pitched out of the face, sunk into the forehead at the top, meeting the tip below
	local bTop, bBot = L.noseTopY + 0.03 * s.Y, tipY + nW * 0.05
	local ay = (bTop - bBot) * 0.56
	local pitch = math.atan2(0.4 * proj, ay)
	local bD = 0.5 * proj
	if not drawn then
		local nose = add("Nose", V3(nW * (0.62 + 0.1 * noseBreak), 2 * ay, 2 * bD),
			hcf * surfCF(L, dev * 0.5, (bTop + bBot) / 2, 0) * ANG(0, 0, nroll) * ANG(pitch, 0, 0) * CF(0, 0, 0.1 * proj), noseCol, "Ellipsoid")
		nose:SetAttribute("Base", true)
		-- the tip: a rounded ball whose back sinks into the face (the overhang under it is the columella's shadow)
		local tD = proj * 0.55
		add("NoseTip", V3(nW * (full and 0.76 or 0.88), nW * 0.52, 2 * tD), hcf * surfCF(L, dev, tipY, proj - tD) * ANG(0, 0, nroll), noseCol, "Ellipsoid")
		if full then
			for side = -1, 1, 2 do
				add("NoseWing", V3(nW * 0.44, nW * 0.4, 0.64 * proj), hcf * surfCF(L, dev + side * nW * 0.38, L.noseBottomY + nW * 0.2, 0.08 * proj) * ANG(0, 0, side * rad(-20)),
					darken(skin, 0.95), "Ellipsoid")
				add("Nostril", V3(nW * 0.26, nW * 0.11, 0.24 * proj), hcf * surfCF(L, dev + side * nW * 0.18, L.noseBottomY + 0.012 * s.Y, 0.24 * proj) * ANG(0, 0, side * rad(-15)),
					darken(skin, 0.42), "Ellipsoid")
			end
		end
		if noseBreak > 0.3 and full then
			opt("wear", 1, function()
				add("NoseBump", V3(nW * 0.5, L.noseLen * 0.2, 0.25 * proj), hcf * surfCF(L, dev * 0.3, L.noseTopY - L.noseLen * 0.32, 0.12 * proj), noseCol, "Ellipsoid")
			end)
		end
	end
	-- nasolabial folds: deepen with age, fat and a big smile line
	if full and not drawn then
		local fold = clamp(0.3 + 0.5 * wr + 0.25 * faceFat, 0, 1)
		for side = -1, 1, 2 do
			line("Nasolabial", dev + side * nW * 0.6, L.noseBottomY + nW * 0.12, side * L.mouthW * 0.6, L.mouthY - 0.02 * s.Y,
				(0.012 + 0.008 * fold) * s.X, darken(skin, 0.78), 0.86 - 0.35 * fold, 0.0012)
		end
	end

	-- mouth: two low lips that overlap at the seam (so nothing behind them shows until they part), the dark seam line
	-- riding on the upper lip, corner pieces of that line (rigged: they curl up in a smile), and behind them the
	-- interior and teeth (full). A mouthguard parts the lips.
	local guard = (opts.mouthguard and not drawn) and true or false -- (a drawn mouth wears no guard lens)
	local lt = face.lips or 0
	local mw = L.mouthW
	local upperH = (0.032 + 0.016 * lt + (female and 0.006 or 0)) * s.Y
	local lowerH = (0.042 + 0.02 * lt + (female and 0.008 or 0)) * s.Y
	local gap = guard and 0.03 * s.Y or 0
	local bulge = guard and 0.004 * s.Z or 0
	local mroll = L.mouthTilt
	local mcr, msr = math.cos(mroll), math.sin(mroll)
	local function mp(dx, dy)
		return dx * mcr - dy * msr, L.mouthY + dx * msr + dy * mcr
	end
	-- pigmented lips: a shade of the skin, darker on deep skin tones, a little rosier on light ones
	local lipColor = lerpColor(darken(skin, 0.86 + 0.08 * skinL), under, 0.1 + 0.22 * skinL + (female and 0.08 or 0))
	local seamRise = (0.0085 + 0.003 * lt) * s.Z + bulge
	if full and not drawn then
		local ix, iy = mp(0, -gap * 0.5)
		local inside = lp("MouthInside", ix, iy, mw * 0.8, (upperH + lowerH) * 0.55 + gap, 0.003 * s.Z, 0.6, Color3.fromRGB(62, 20, 24),
			{ roll = mroll, role = "MouthInside" })
		local tx, ty = mp(0, upperH * 0.05 - gap * 0.3)
		lp("TeethUpper", tx, ty, mw * 0.56, upperH * 0.75, 0.0045 * s.Z, 0.6, Color3.fromRGB(232, 226, 208), { roll = mroll })
		local qx, qy = mp(0, -gap - lowerH * 0.22)
		lp("TeethLower", qx, qy, mw * 0.5, lowerH * 0.5, 0.0042 * s.Z, 0.6, Color3.fromRGB(222, 214, 194), { roll = mroll, anchor = inside })
	end
	-- (a drawn face style draws its own mouth: no lips, seam, corners, philtrum or lip fold)
	if not drawn then
		local ux, uy = mp(0, upperH * 0.32 + gap * 0.5)
		local upper = lp("UpperLip", ux, uy, mw, upperH * 1.3, (0.0095 + 0.004 * lt) * s.Z + bulge, 0.55, lipColor, { roll = mroll, role = "UpperLip" })
		local lx, ly = mp(0, -lowerH * 0.38 - gap * 0.5)
		local lower = lp("LowerLip", lx, ly, mw * 0.84, lowerH * 1.2, (0.012 + 0.005 * lt) * s.Z + bulge, 0.55, lerpColor(lipColor, WHITE, 0.04),
			{ roll = mroll, role = "LowerLip" })
		upper:SetAttribute("BaseSize", upper.Size)
		upper:SetAttribute("VisW", mw)
		lower:SetAttribute("BaseSize", lower.Size)
		local sx, sy = mp(0, -gap * 0.5)
		local mline = lp("MouthLine", sx, sy, mw * 0.88, 0.008 * s.Y, seamRise, 0.5, darken(lipColor, 0.45), { roll = mroll, anchor = upper, t = guard and 0.7 or 0 })
		mline:SetAttribute("BaseSize", mline.Size)
		-- a beard covering the mouth pushes the lips out so they show through it. The face does this itself
		-- (the same rule beardBuild applies from BaseSize) so a face-only rebuild, e.g. after a body fat
		-- change while the beard is cached, never buries the lips.
		local bStyle = beardStyle(app)
		if bStyle and bStyle ~= "Stubble" then
			for _, p in ipairs({ upper, lower, mline }) do
				p.Size = p:GetAttribute("BaseSize") + V3(0, 0, 0.03)
			end
		end
		if full then
			for side = -1, 1, 2 do
				local cx, cy = mp(side * mw * 0.4, -gap * 0.5)
				local corner = lp("MouthCorner", cx, cy, mw * 0.26, 0.01 * s.Y, seamRise + 0.0008, 0.5, darken(lipColor, 0.42),
					{ roll = mroll, role = "MouthCorner" .. (side == -1 and "L" or "R"), side = side })
				corner:SetAttribute("Side", side)
			end
			-- philtrum groove and the fold under the lower lip
			local py0 = L.noseBottomY - 0.004 * s.Y
			local py1 = L.mouthY + upperH * 1.0
			if py0 > py1 then
				opt("skin", 1, function()
					lp("Philtrum", dev * 0.5, (py0 + py1) / 2, 0.05 * s.X, py0 - py1, 0.0015, 0.88, darken(skin, 0.88), { t = 0.6 })
				end)
			end
			opt("skin", 1, function()
				line("LipFold", -mw * 0.26, L.mouthY - lowerH * 1.25 - gap, mw * 0.26, L.mouthY - lowerH * 1.25 - gap, 0.012 * s.Y, darken(skin, 0.8), 0.6, 0.0012)
			end)
		end
	end

	-- skin details (deterministic from the face seed; draw order is load-bearing, keep it)
	local rng = Random.new(face.seed or 7)
	-- a mark on the skin: flat (rise ~0.001) unless it is a raised spot
	local function spot(name, size, color, xMin, xMax, yMin, yMax, transparency, skip, rise)
		local x = rng:NextNumber(xMin, xMax) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(yMin, yMax) * s.Y
		if skip or (drawn and Head.DecalInkHit(L, x, y, size.X, size.Y)) then
			return nil
		end
		return lp(name, x, y, size.X, size.Y, rise or 0.001, rise and 0.5 or 0.85, color, { t = transparency })
	end
	local freck = math.floor((face.freckles or 0) * 26)
	for i = 1, freck do
		local sz = rng:NextNumber(0.018, 0.03)
		spot("Freckle", V3(sz, sz, 0.01), darken(skin, 0.72), 0.06, 0.34, -0.1, 0.06, 0.25, i > (D.freckles or 26))
	end
	for _ = 1, math.floor(face.moles or 0) do
		spot("Mole", V3(0.032, 0.032, 0.015), darken(skin, 0.35), 0.1, 0.36, -0.32, 0.25, nil, nil, 0.004)
	end
	for _ = 1, math.floor(face.scars or 0) do
		local x = rng:NextNumber(0.08, 0.32) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(-0.12, 0.3) * s.Y
		local a = math.rad(rng:NextNumber(-40, 40))
		local len = rng:NextNumber(0.1, 0.2) * s.Y
		if drawn and Head.DecalInkHit(L, x, y, 0.016, len) then
			continue
		end
		lp("Scar", x, y, 0.016, len, 0.0015, 0.8, lerpColor(skin, Color3.fromRGB(235, 190, 190), 0.55), { roll = a })
	end
	-- acne: inflamed spots on a young face; from the mid twenties (or with heavy acne) what is left are
	-- pitted scars, slightly darker shallow dents rather than red bumps. Same rng draws either way. An
	-- unknown age (Creator preview) keeps the spots the player is choosing.
	local acneScars = (tonumber(opts.age) or 0) >= 25 or (face.acne or 0) > 0.6
	for i = 1, math.floor((face.acne or 0) * 14) do
		if acneScars and i % 3 ~= 0 then
			spot("AcneScar", V3(0.03, 0.026, 0.008), darken(skin, 0.86), 0.05, 0.36, -0.32, 0.32, 0.55, low)
		else
			spot("Acne", V3(0.024, 0.024, 0.012), lerpColor(skin, Color3.fromRGB(190, 60, 60), 0.5), 0.05, 0.36, -0.32, 0.32, nil, low, 0.003)
		end
	end
	if (face.marks or 0) > 0.05 then
		local sz = 0.08 + 0.14 * face.marks
		spot("Birthmark", V3(sz, sz * 0.7, 0.01), lerpColor(skin, Color3.fromRGB(150, 70, 70), 0.35), 0.15, 0.32, -0.2, 0.25, 0.35)
	end

	-- v2 skin detail stream (separate so the stream above never shifts)
	local r2 = Random.new((face.seed or 7) + 202)
	local scarColor = lerpColor(skin, Color3.fromRGB(236, 196, 192), 0.5)
	-- permanent fight scars where the cuts happened
	if full and type(battle.scars) == "table" then
		for i, sc in ipairs(battle.scars) do
			if i <= 6 and type(sc) == "table" then
				opt("wear", 1, function()
					local side = (tonumber(sc.side) or 1) < 0 and -1 or 1
					local t = clamp(tonumber(sc.at) or 0.5, 0, 1)
					local size = clamp(tonumber(sc.size) or 0.5, 0, 1)
					local len = (0.06 + 0.1 * size) * s.Y
					local kind = sc.kind
					local x, y, ang = side * L.eyeX * (0.55 + 0.7 * t), L.browY + 0.01 * s.Y, side * rad(70)
					if kind == "cheek" then
						x, y, ang = side * (0.2 + 0.12 * t) * s.X, -0.06 * s.Y, side * rad(20)
					elseif kind == "nose" then
						x, y, ang = side * 0.015 * s.X, L.noseTopY - t * L.noseLen * 0.55, rad(80)
					elseif kind == "lip" then
						x, y, ang = side * mw * 0.3 * t, L.mouthY + upperH * 1.3, rad(95)
					elseif kind == "chin" then
						x, y, ang = side * 0.09 * t * s.X, chinY + 0.02 * s.Y, rad(15 * side)
					end
					local dx, dy = math.cos(ang) * len * 0.5, math.sin(ang) * len * 0.5
					line("BattleScar", x - dx, y - dy, x + dx, y + dy, (0.012 + 0.01 * size) * s.X, scarColor, 0.1, 0.002 + ((kind == "brow" or kind == nil) and ridgeAt(x, y) or 0))
					if (kind == "brow" or kind == nil) and not drawn and spend("wear", 1) then
						-- the hair never grows back through a brow scar: a skin-coloured notch over the brow
						local bi = browInfo[side]
						lp("BrowGap", x, bi.y, 0.02 * s.X, bt * 1.5, bi.base + bi.rise + 0.002, 0.5, skin, { anchor = bi.part })
					end
				end)
			end
		end
	end
	-- a surgically repaired cut: a straight, pale scar over the brow with the cross-marks the stitches
	-- left ("railroad tracks"); for a chosen scarred face or a boxer who has been cut more than once
	if full and ((face.scars or 0) >= 1 or scarCount >= 2) then
		local r3 = Random.new((face.seed or 7) + 204)
		local side = r3:NextNumber() < 0.5 and -1 or 1
		local x0 = side * L.eyeX * r3:NextNumber(0.45, 0.7)
		local x1 = side * L.eyeX * r3:NextNumber(1.25, 1.5)
		local y0 = L.browY + r3:NextNumber(0.03, 0.05) * s.Y
		local y1 = y0 + r3:NextNumber(-0.03, 0.02) * s.Y
		opt("skin", 4, function()
			line("SurgicalScar", x0, y0, x1, y1, 0.011 * s.X, scarColor, 0.05, 0.002 + ridgeAt((x0 + x1) / 2, (y0 + y1) / 2))
			local dx, dy = x1 - x0, y1 - y0
			local len = math.sqrt(dx * dx + dy * dy)
			local nx, ny = -dy / len * 0.016 * s.Y, dx / len * 0.016 * s.Y
			for k = 1, 3 do
				local px, py = x0 + dx * k / 4, y0 + dy * k / 4
				line("Suture", px - nx, py - ny, px + nx, py + ny, 0.006 * s.X, lerpColor(scarColor, WHITE, 0.15), 0.15, 0.003 + ridgeAt(px, py))
			end
		end)
	end
	-- wrinkles with age (forehead lines, crow's feet)
	if D.wrinkles and full and wr > 0.25 then
		opt("skin", 2, function()
			local lines = (wr > 0.75 and spend("skin", 2)) and 2 or 1
			for i = 1, lines do
				local yy = L.browY + (0.08 + 0.05 * i) * s.Y
				local wob = r2:NextNumber(-0.01, 0.01) * s.Y
				for side = -1, 1, 2 do
					line("ForeheadLine", side * 0.01 * s.X, yy + wob, side * (0.22 - 0.03 * i) * s.X, yy - 0.012 * s.Y, 0.01 * s.Y, darken(skin, 0.8), 0.86 - 0.3 * wr, 0.001)
				end
			end
			if wr > 0.35 and spend("skin", 2) then
				for side = -1, 1, 2 do
					local x0 = side * (L.eyeX + 0.1 * s.X)
					line("CrowFeet", x0, L.eyeY + 0.01 * s.Y, x0 + side * 0.06 * s.X, L.eyeY - 0.015 * s.Y + r2:NextNumber(-0.01, 0.01) * s.Y, 0.008 * s.Y, darken(skin, 0.8), 0.86 - 0.3 * wr, 0.001)
				end
			end
		end)
	end
	-- pores: textures are not possible here, so a pore-heavy skin gets a grainy material (above)
	-- plus a few sparse darker dots on the nose and cheeks at full detail
	if full and (face.pores or 0) > 0.3 then
		opt("skin", 0, function()
			local n = math.min(5, math.floor((face.pores - 0.3) / 0.7 * 5 + 0.5))
			for _ = 1, n do
				if not spend("skin", 1) then
					break
				end
				local x = r2:NextNumber(-0.28, 0.28) * s.X
				local y = r2:NextNumber(-0.14, 0.02) * s.Y
				if not (drawn and Head.DecalInkHit(L, x, y, 0.014, 0.014)) then
					lp("Pore", x, y, 0.014, 0.014, 0.001, 0.85, darken(skin, 0.8), { t = 0.6 })
				end
			end
		end)
	end
	-- veins the client reveals during effort / anger / heavy sweat; leaner faces show them more
	if full then
		local veinColor = lerpColor(darken(skin, 0.86), Color3.fromRGB(70, 92, 140), 0.18)
		local vis = clamp(0.62 - 0.25 * clamp((FB.defZero - fat) / (FB.defZero - FB.defFull), 0, 1), 0.3, 0.7)
		-- one temple (seeded side) and the classic diagonal forehead vein on the other
		local vs = (Random.new((face.seed or 7) + 203):NextNumber() < 0.5) and -1 or 1
		local veins = {
			line("TempleVein", vs * 0.36 * s.X, L.browY + 0.02 * s.Y, vs * 0.33 * s.X, L.browY + 0.14 * s.Y, 0.014 * s.X, veinColor, 1, 0.0028),
			line("ForeheadVein", -vs * 0.07 * s.X, L.browY + 0.05 * s.Y, -vs * 0.1 * s.X, L.browY + 0.19 * s.Y, 0.014 * s.X, veinColor, 1, 0.0028),
		}
		for _, v in ipairs(veins) do
			v:SetAttribute("BaseTransparency", vis)
		end
	end
	-- mouthguard sits at teeth depth, showing between the parted lips. Head.SetDamage tints it after a
	-- split lip (from BaseColor), so in-fight damage shows without a face rebuild.
	if guard then
		local mg = Looks.Color(app.attire and app.attire.mouthguard, Color3.fromRGB(40, 80, 200))
		local gx, gy = mp(0, -gap * 0.5)
		local mgPart = lp("Mouthguard", gx, gy, mw * 0.86, gap * 1.4 + (0.012 + 0.004 * lt) * s.Y, 0.0062 * s.Z, 0.6, mg, { roll = mroll })
		mgPart:SetAttribute("BaseColor", mg)
	end

	-- optional details, in priority order, while the budget lasts
	for _, q in ipairs(queued) do
		if spend(q[1], q[2]) then
			q[3]()
		end
	end
	-- what the damage marks lie on (Head.SetDamage: a bruise over a full cheek, a split in the lower lip)
	folder:SetAttribute("CheekRise", math.max(boneRise, fullCheeks and (0.005 + 0.008 * math.min(cheekFat, 1)) or 0) * s.Z * 0.6)
	folder:SetAttribute("RidgeRise", ridgeAt(L.eyeX, L.browY + 0.03 * s.Y))
	folder:SetAttribute("LowerLipRise", drawn and 0 or (0.012 + 0.005 * lt) * s.Z + bulge)
	folder:SetAttribute("LipColor", lipColor)
	-- parts over the old face (the hair and beard steps read this to share A's budget)
	folder:SetAttribute("Extra", countParts(folder) - oldParts)
	-- grime lives in its own folder (Head.SetSweat refreshes it); a grime opt rides on the face folder
	folder:SetAttribute("OptGrime", tonumber(opts.grime))
	faceGrime(model, app)
end

------------------------------------------------------------------------
-- Beard
------------------------------------------------------------------------
local function beardBuild(model, app, opts)
	opts = opts or {}
	app = app or {}
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local folder = getFolder(model, "Beard")
	local face = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Face")
	-- lips back to their own size (a previous beard build may have pushed them out)
	if face then
		for _, c in ipairs(face:GetChildren()) do
			local bs = c:GetAttribute("BaseSize")
			if bs and c:IsA("BasePart") then
				c.Size = bs
			end
		end
	end
	local detail = Config.DetailLevel(opts)
	local full, low = detail == "full", detail == "low"
	-- growth stages without a chosen style: shadow -> stubble -> a short natural beard (beardStyle)
	local style, shadow, g, grown = beardStyle(app)
	-- the lips follow the full-detail rule at every detail level, exactly as faceBuild pushes them
	local coversLips = style ~= nil and style ~= "Stubble"
	if style and low and grown then
		-- far away a five o'clock shadow is invisible and a grown-in beard reads as stubble (old budget)
		if shadow then
			style = nil
		elseif style == "Short Boxed" then
			style, g = "Stubble", 1
		end
	end
	if not style then
		folder:SetAttribute("Extra", 0 - oldBeardParts(app))
		return
	end
	local beard = app.beard or {}
	local s = head.Size
	local hcf = head.CFrame
	local L = Head.FaceLayout(head, app.face or {})
	if Head.FaceStyle(model) then
		Head.DecalLayout(L) -- (the moustache over the drawn mouth; the beard's cache key holds the style)
	end
	local hair = app.hair or {}
	local color = Looks.Color(beard.color or hair.color, Color3.fromRGB(25, 20, 18))
	-- salt & pepper: beards grey before the hair does
	local age = tonumber(opts.age) or 24
	local grey = clamp((age - 38) / 25, 0, 0.6)
	if grey > 0 then
		color = lerpColor(color, Color3.fromRGB(165, 162, 158), grey * 0.55)
	end
	local htype = hair.type or "Straight"
	local mat = (htype == "Kinky" or htype == "Coiled") and SAND or FABRIC
	-- part cap: the old beard plus what the face and hair left of A's budget (both are built first)
	local old = oldBeardParts(app)
	local cap = old + A_BUDGET[detail] - extraOf(model, "Face", FACE_CAP[detail]) - extraOf(model, "Hair", 0)
	local function fits(n)
		return countParts(folder) + n <= cap
	end
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	local function add(name, size, cf, col, shape, material, transparency)
		return mk(folder, head, name, size, cf, col or color, shape or "Ellipsoid", material or mat, transparency)
	end
	local mw = L.mouthW
	local function moustache(width, drop)
		if full and fits(2) then
			-- two halves angled down toward the mouth corners
			for side = -1, 1, 2 do
				add("Moustache", V3((width or 0.17) * s.X, (0.045 + 0.03 * g) * s.Y, 0.06 * s.Z),
					at(side * 0.075 * s.X, L.mouthY + 0.062 * s.Y, L.front(side * 0.075 * s.X) - 0.025) * ANG(0, 0, L.mouthTilt + side * math.rad(-(drop or 10))))
			end
		else
			-- one centred bar (medium / low detail, or no room left)
			add("Moustache", V3(((width or 0.17) + 0.13) * s.X, (0.045 + 0.03 * g) * s.Y, 0.06 * s.Z),
				at(0, L.mouthY + 0.064 * s.Y, L.front(0) - 0.025) * ANG(0, 0, L.mouthTilt))
		end
	end
	local function chinPatch(w, h, y)
		add("Goatee", V3(w * s.X, (h + 0.08 * g) * s.Y, 0.16 * s.Z), at(0, (y or -0.44) * s.Y, L.front(0) * 0.82))
	end
	-- optional pieces, drawn after the style's own parts while the cap leaves room
	local wantSideburns, wantNeck, neckT = false, false, nil
	if style == "Stubble" then
		-- front-biased shell: covers the jaw, chin and upper lip but never the back of the head
		local t = shadow and 0.9 or (0.8 - 0.12 * g)
		-- (top edge kept under the cheekbones: a shell up to the eyes read as a mask)
		add("Stubble", V3(s.X * 1.05, s.Y * 0.42, s.Z * 0.99), at(0, -0.33 * s.Y, -0.07 * s.Z), color, "Ellipsoid", SMOOTH, t)
		wantNeck, neckT = true, math.min(0.95, t + 0.05)
	elseif style == "Goatee" then
		chinPatch(0.24, 0.2)
		moustache()
	elseif style == "Van Dyke" then
		-- pointed chin beard and a moustache that does not connect to it
		add("Goatee", V3(0.2 * s.X, (0.22 + 0.08 * g) * s.Y, 0.15 * s.Z), at(0, -0.46 * s.Y, L.front(0) * 0.8), color, "Ellipsoid")
		if not low then
			add("SoulPatch", V3(0.06 * s.X, 0.06 * s.Y, 0.05 * s.Z), at(0, L.mouthY - 0.085 * s.Y, L.front(0) - 0.02))
		end
		moustache(0.16, 18)
	elseif style == "Circle Beard" then
		chinPatch(0.26, 0.18)
		moustache()
		-- the ring around the mouth joining moustache and chin
		if not low then
			for side = -1, 1, 2 do
				local x = side * mw * 0.62
				add("CircleSide", V3(0.05 * s.X, 0.16 * s.Y, 0.05 * s.Z), at(x, L.mouthY - 0.03 * s.Y, L.front(x) - 0.012) * ANG(0, 0, side * math.rad(8)))
			end
		end
	elseif style == "Moustache" then
		moustache()
	elseif style == "Chin Strap" then
		for side = -1, 1, 2 do
			add("Strap", V3(0.06 * s.X, 0.42 * s.Y, 0.5 * s.Z), at(side * 0.46 * s.X, -0.25 * s.Y, -0.05 * s.Z) * ANG(0, 0, math.rad(side * 12)), color, "Ellipsoid")
		end
		add("StrapChin", V3(0.55 * s.X, 0.08 * s.Y, 0.3 * s.Z), at(0, -0.5 * s.Y, L.front(0) * 0.55))
	elseif style == "Mutton Chops" then
		-- broad sideburns down to the jaw, a clean chin
		for side = -1, 1, 2 do
			add("Chop", V3(0.12 * s.X, (0.36 + 0.06 * g) * s.Y, 0.42 * s.Z), at(side * 0.45 * s.X, -0.18 * s.Y, -0.08 * s.Z) * ANG(0, 0, math.rad(side * 8)))
		end
		moustache(0.18, 6)
	elseif style == "Short Boxed" then
		-- a denser core under a sparser, slightly larger edge layer: the outline thins into the skin
		-- instead of ending in a hard shell rim (the edge layer only when the part cap leaves room)
		add("Beard", V3(s.X * 1.03, s.Y * (0.42 + 0.06 * g), s.Z * 1.0), at(0, -0.35 * s.Y, -0.06 * s.Z))
		if not low and fits(2) then
			add("BeardEdge", V3(s.X * 1.07, s.Y * (0.47 + 0.06 * g), s.Z * 1.03), at(0, -0.33 * s.Y, -0.06 * s.Z), color, "Ellipsoid", mat, 0.55)
		end
		moustache()
		wantSideburns, wantNeck = true, true
	else -- Full Beard
		-- core + sparser edge layer (see Short Boxed); the top stays below the cheekbones
		add("Beard", V3(s.X * 1.06, s.Y * (0.5 + 0.14 * g), s.Z * 1.04), at(0, -0.41 * s.Y, -0.06 * s.Z))
		if not low and fits(3) then
			add("BeardEdge", V3(s.X * 1.1, s.Y * (0.56 + 0.14 * g), s.Z * 1.07), at(0, -0.39 * s.Y, -0.06 * s.Z), color, "Ellipsoid", mat, 0.55)
		end
		if not low then
			add("BeardChin", V3(0.5 * s.X, (0.2 + 0.1 * g) * s.Y, 0.3 * s.Z), at(0, (-0.55 - 0.05 * g) * s.Y, -0.3 * s.Z))
		end
		moustache(0.18, 8)
		wantSideburns, wantNeck = true, true
	end
	-- sideburns joining the beard to the hair, then the neck line (full detail only)
	if wantSideburns and full and fits(2) then
		for side = -1, 1, 2 do
			-- lying on the side wall just in front of the ear (a low shell, its rim on the skin)
			local rise = 0.012 * s.X
			add("Sideburn", V3(0.065 * s.Z, 0.27 * s.Y, 2 * rise / 0.5), hcf * L.shellCF(side * rad(76), -0.01 * s.Y, 0) * CF(0, 0, rise / 0.5 - rise), color, "Ellipsoid", mat)
		end
	end
	if wantNeck and full and fits(1) then
		add("NeckBeard", V3(0.72 * s.X, 0.12 * s.Y, 0.6 * s.Z), at(0, -0.49 * s.Y, -0.12 * s.Z), color, "Ellipsoid", mat, neckT)
	end
	-- grey flecks on older beards
	if grey > 0.15 and full and style ~= "Stubble" then
		local rng = Random.new((app.face and app.face.seed or 7) + 404)
		for _ = 1, 2 + math.floor(grey * 4) do
			local x = rng:NextNumber(-0.12, 0.12) * s.X
			local y = rng:NextNumber(-0.47, -0.36) * s.Y
			if not fits(1) then
				break
			end
			add("GreyFleck", V3(0.05 * s.X, 0.04 * s.Y, 0.03 * s.Z), at(x, y, L.front(x) * 0.84 - 0.03), Color3.fromRGB(200, 198, 192), "Ellipsoid", mat, 0.3)
		end
	end
	folder:SetAttribute("Extra", countParts(folder) - old)
	-- keep the lips visible through the beard (from their base size: rebuilds never stack; faceBuild
	-- applies the same rule when it is rebuilt on its own)
	if face and coversLips then
		for _, n in ipairs({ "UpperLip", "LowerLip", "MouthLine" }) do
			local p = face:FindFirstChild(n)
			if p then
				local bs = p:GetAttribute("BaseSize") or p.Size
				p.Size = bs + V3(0, 0, 0.03)
			end
		end
	end
end

------------------------------------------------------------------------
-- Headgear (every boxer's, Config.AlwaysHeadgear; else only while sparring)
------------------------------------------------------------------------
-- An open-face amateur headgear built from explicit pads: the face opening is geometry, never an accident of overlap.
-- Only shapes the engine sizes from the part (Sphere meshes = ellipsoids, Cylinder parts, Blocks): NO Head mesh (the
-- engine scales that one uniformly by the smallest axis and never stretches it; two rebuilds were bitten by it).
-- Everything is sized and placed from the head's live size (Head.HeadSpan, its smallest axis) in head spans
-- (y up from the head's centre, -z the face), welded to the head, so it fits every head and follows a rescale
-- (followHead below rebuilds it when the Head's Size changes after the build).
-- The pads (Head.HG, in spans; see tools/sim/test_bodytiers / test_referee, which check these against the
-- forbidden front region without any model of the head mesh):
-- * HGBrow: the brow roll, a flat ring round the head just above the brows (its rim meets the forehead at
--   y 0.27, above HEADGEAR_OPENING.top; 0.08 proud at the front, sunk inside the head at the back)
-- * HGTop: the crown cap over the top, flush with the forehead under the brow roll, 0.11 thick on the crown
-- * HGShell: the back shell, a half-dome behind the ears down to the nape (the part Diag measures)
-- * HGCheek x2: the cheek bolsters, upright rolls beside the face from the brow roll to under the jaw, outside
--   the eyes (|x| >= 0.37; the drawn ink ends at 0.237), never across the face (z >= -0.29)
-- * HGSide x2 (full) / HGEars (medium: one drum through the head whose ends are the two ear pads): the ear pads
--   flush on the side walls, 0.1 proud; HGEarHole x2 (full): the dark openings over the ears
-- * HGStrap x2 (full): the chin strap from under each ear pad to a point under the chin
-- Nothing in front of the face: no part reaches z < -0.35 spans below the brow line (HEADGEAR_OPENING.top), none
-- covers the eye points (+-0.2, 0, -0.5); the ear pads stand >= 0.03 off the side planes, the crown cap >= 0.03
-- above the top. The opening (fractions of the head): the band from y = top up, nothing at |x| < side above the
-- mouth line (y > -0.1) or at |x| < sideLow below it; checked against every drawn face by test_bodytiers.
-- detail = Config.DetailLevel: full 11 parts, medium 6, low 3 (the crowd: brow roll, crown cap, back shell).
Head.HEADGEAR_OPENING = { top = 0.225, side = 0.29, sideLow = 0.24 }
local HG_PARTS = { full = 11, medium = 6, low = 3 }
Head.HEADGEAR_PARTS = HG_PARTS

-- The engine's Head SpecialMesh is NOT stretched by the part's Size per axis (unlike the Sphere mesh): it is the one
-- head shape, scaled uniformly by the part's smallest axis. Every head-worn part is therefore sized from the head's
-- smallest axis (Head.HeadSpan); the headgear and the caps use no Head mesh at all.
function Head.HeadSpan(head)
	local s = head.Size
	return math.min(s.X, s.Y, s.Z)
end

-- the pads in head spans (centre x / y / z, then the size w x h x d; cheek: a roll of radius r and length h; strap:
-- its end points a (under the ear pad) and b (under the chin), its width w and thickness t)
Head.HG = {
	brow = { y = 0.305, z = -0.04, w = 1.16, h = 0.15, d = 1.08 },
	top = { y = 0.36, z = 0.04, w = 1.14, h = 0.5, d = 1.08 },
	back = { y = 0.02, z = 0.2, w = 1.22, h = 0.84, d = 0.86 },
	cheek = { x = 0.46, y = -0.06, z = -0.2, r = 0.09, h = 0.76 },
	side = { x = 0.52, y = 0, z = -0.02, w = 0.16, h = 0.6, d = 0.62 },
	ears = { y = 0, z = -0.02, d = 0.6, len = 1.2 },
	hole = { x = 0.595, y = 0.02, z = -0.02, w = 0.03, h = 0.16, d = 0.12 },
	strap = { a = { 0.5, -0.28, 0.02 }, b = { 0.08, -0.52, -0.24 }, w = 0.07, t = 0.025 },
}

-- A pad colour within a hair of the skin reads as a bare, bulging head (Looks.Palette's brown {110, 70, 40} against
-- SkinTones[9] {112, 70, 44}: a seed-coloured NPC's headgear, a cornerman's team cap). Such a colour is nudged away
-- from the skin: darker on a light skin, lighter on a dark one. Returns the colour and whether it was adjusted.
function Head.OffSkin(color, skin)
	if typeof(color) ~= "Color3" or typeof(skin) ~= "Color3" then
		return color, false
	end
	local d = math.abs(color.R - skin.R) + math.abs(color.G - skin.G) + math.abs(color.B - skin.B)
	if d >= 0.12 then
		return color, false
	end
	if lum(skin) > 0.3 then
		return darken(color, 0.6), true
	end
	return lerpColor(color, WHITE, 0.3), true
end

-- The head is scaled after a build at times (ApplyDescription, a head swap kept at the engine's scale): the gear
-- was then built for another size. The folder records the size it was built for (attribute HeadSize) and watches
-- the head's Size while it lives; a change rebuilds it through `rebuild` (deferred: one rebuild per change burst).
-- Builder's cache keys carry the head size too, so a Cosmetics after the change rebuilds either way; this covers a
-- change with no Cosmetics after it. Quiet when the host has no property signals (the lune tests).
local function followHead(folder, head, rebuild)
	folder:SetAttribute("HeadSize", head.Size)
	local conn
	local ok = pcall(function()
		conn = head:GetPropertyChangedSignal("Size"):Connect(function()
			if folder.Parent == nil then
				conn:Disconnect()
				return
			end
			task.defer(function()
				if folder.Parent == nil or head.Parent == nil then
					return
				end
				local was = folder:GetAttribute("HeadSize")
				if typeof(was) == "Vector3" and (head.Size - was).Magnitude > 1e-3 then
					conn:Disconnect()
					rebuild()
				end
			end)
		end)
	end)
	if ok and conn then
		-- (the folder goes with the model, a rebuild or a fight cleanup: the watch goes with it)
		pcall(function()
			folder.Destroying:Once(function()
				conn:Disconnect()
			end)
		end)
	end
end

function Head.SetHeadgear(model, color, on, detail)
	local folder = getFolder(model, "Headgear")
	Head.SetHairHidden(model, "headgear", on)
	if not on then
		return
	end
	local head = part(model, "Head")
	if not head then
		return
	end
	detail = Config.DetailLevel(detail or model:GetAttribute("Detail"))
	local full, low = detail == "full", detail == "low"
	folder:SetAttribute("Detail", detail)
	color = typeof(color) == "Color3" and color or Color3.fromRGB(200, 25, 30)
	local asked = color
	local adjusted
	color, adjusted = Head.OffSkin(color, head.Color)
	folder:SetAttribute("Color", asked)
	folder:SetAttribute("ColorAdjusted", adjusted)
	local hs = Head.HeadSpan(head)
	local hcf = head.CFrame
	local mat = Enum.Material.Leather
	local G = Head.HG
	local function at(x, y, z)
		return hcf * CF(x * hs, y * hs, z * hs)
	end
	-- an ellipsoid pad: centre (x, y, z) and size w x h x d in spans
	local function pad(name, x, y, z, w, h, d, c, m)
		return mk(folder, head, name, V3(w * hs, h * hs, d * hs), at(x, y, z), c, "Ellipsoid", m or mat)
	end
	local browC, strapC, holeC = darken(color, 0.9), darken(color, 0.55), darken(color, 0.35)
	-- the brow roll, the crown cap and the back shell: every detail level
	pad("HGBrow", 0, G.brow.y, G.brow.z, G.brow.w, G.brow.h, G.brow.d, browC)
	pad("HGTop", 0, G.top.y, G.top.z, G.top.w, G.top.h, G.top.d, color)
	pad("HGShell", 0, G.back.y, G.back.z, G.back.w, G.back.h, G.back.d, color)
	if low then
		followHead(folder, head, function()
			Head.SetHeadgear(model, asked, true, detail)
		end)
		return folder
	end
	-- the cheek bolsters: upright rolls (long ellipsoids) beside the face, outside the eyes
	local C = G.cheek
	for side = -1, 1, 2 do
		pad("HGCheek", side * C.x, C.y, C.z, 2 * C.r, C.h, 2 * C.r, color)
	end
	if not full then
		-- one drum through the head along X: its two ends are the ear pads (a Cylinder part's axis is its X)
		local E = G.ears
		mk(folder, head, "HGEars", V3(E.len * hs, E.d * hs, E.d * hs), at(0, E.y, E.z), color, "Cylinder", mat)
		followHead(folder, head, function()
			Head.SetHeadgear(model, asked, true, detail)
		end)
		return folder
	end
	local S, Hh, St = G.side, G.hole, G.strap
	for side = -1, 1, 2 do
		-- the ear pad flush on the side wall, the dark ear hole in its outer face
		pad("HGSide", side * S.x, S.y, S.z, S.w, S.h, S.d, color)
		pad("HGEarHole", side * Hh.x, Hh.y, Hh.z, Hh.w, Hh.h, Hh.d, holeC)
		-- the chin strap: from under the ear pad along the jaw to a point under the chin
		local a = at(side * St.a[1], St.a[2], St.a[3]).Position
		local b = at(side * St.b[1], St.b[2], St.b[3]).Position
		local mid = (a + b) * 0.5
		local out = mid - at(0, -0.1, 0).Position
		mk(folder, head, "HGStrap", V3(St.w * hs, St.t * hs, (b - a).Magnitude), CFrame.lookAt(mid, b, out.Unit), strapC, "Block", SMOOTH)
	end
	followHead(folder, head, function()
		Head.SetHeadgear(model, asked, true, detail)
	end)
	return folder
end

------------------------------------------------------------------------
-- Officials' caps (the referee's peaked cap, the spar coach's team cap): Builder's "Hat" Cosmetics step
------------------------------------------------------------------------
-- Parts on the classic head (no uploaded mesh), welded to the head and sized from it (Head.HeadSpan), so they scale
-- with the head; BoxerLook/Hat is cached by Builder on the style, colours, head size and detail. Only shapes the
-- engine sizes from the part (Cylinder parts, Sphere meshes = ellipsoids): no Head mesh, which it never stretches.
-- * "referee": a black flat-topped peaked cap: a band hugging the head just above the brows (a Cylinder standing
--   on end, a little wider than the head) in the venue shirt's colour (light blue at the clubs, white for a title
--   fight), the crown over it (a wider, taller Cylinder: the flat top overhangs the band), a short stiff visor (a
--   flat ellipsoid rooted under the band, pitched down a little) and a gold WCB badge on the crown's front (a gold
--   disc and the "WCB" wordmark, GothamBlack in ink, as UI.Brand's); full adds the gold cord across the band
-- * "baseball": the coach's team cap: a domed six-panel crown (an ellipsoid) in his team colour, a longer bill in its
--   darker shade, the top button and a white "WCB" on the front; full adds the front seam
-- Nothing reaches the drawn face: every part stays above Head.CAP_CLEAR (fractions of the head height, the drawn
-- ink's padded brow top Head.DECAL_INK is 0.21, the measured ink 0.183) in front of the face, so the brows and eyes
-- show from the front, the 3/4 and a camera up to ~10 deg above (test_bodytiers casts the rays).
-- detail = Config.DetailLevel: referee full 6 parts, medium 5, low 2; baseball full 5, medium 4, low 2.
Head.CAP_CLEAR = 0.235
Head.CAP_PARTS = { referee = { full = 6, medium = 5, low = 2 }, baseball = { full = 5, medium = 4, low = 2 } }
-- referee cap geometry (fractions of the head span; y up from the head's centre, z: -0.5 = the forehead). The band
-- from bandLo up bandH (its diameter bandW: the head is 1.0 wide there), the crown from crownBase (inside the band's
-- top) up crownH at crownW; the visor's root centre at visorY, visorT thick, reaching visorReach ahead of the forehead
Head.REFCAP = { bandLo = 0.25, bandH = 0.12, bandW = 1.04, crownBase = 0.36, crownH = 0.3, crownW = 1.08,
	visorY = 0.268, visorT = 0.034, visorReach = 0.24, visorW = 0.78, visorTilt = 3, badgeY = 0.46 }
Head.BALLCAP = { domeY = 0.33, domeH = 0.27, domeW = 1.07, domeD = 1.09, billY = 0.27, billT = 0.034, billReach = 0.36,
	billW = 0.68, billTilt = 3 }

-- colors = { cap, trim, badge } (Color3, all optional); style = "referee" | "baseball" | nil (none: the folder goes)
function Head.SetCap(model, style, colors, detail)
	local folder = getFolder(model, "Hat")
	if style ~= "referee" and style ~= "baseball" then
		folder:Destroy()
		return nil
	end
	local head = part(model, "Head")
	if not head then
		return folder
	end
	detail = Config.DetailLevel(detail or model:GetAttribute("Detail"))
	local full, low = detail == "full", detail == "low"
	folder:SetAttribute("Detail", detail)
	folder:SetAttribute("Style", style)
	colors = type(colors) == "table" and colors or {}
	local ref = style == "referee"
	local capC = typeof(colors.cap) == "Color3" and colors.cap or (ref and Color3.fromRGB(18, 18, 21) or Color3.fromRGB(30, 30, 34))
	-- (a team colour within a hair of the skin reads as a bare head: nudged off it, Head.OffSkin)
	local adjusted
	capC, adjusted = Head.OffSkin(capC, head.Color)
	folder:SetAttribute("ColorAdjusted", adjusted)
	local trimC = typeof(colors.trim) == "Color3" and colors.trim or (ref and Color3.fromRGB(150, 190, 226) or darken(capC, 0.75))
	local badgeC = typeof(colors.badge) == "Color3" and colors.badge or (ref and Color3.fromRGB(212, 172, 64) or Color3.fromRGB(238, 238, 232))
	local hs = Head.HeadSpan(head)
	local hcf = head.CFrame
	-- the cap follows a head rescale after the build (followHead above)
	local function done()
		followHead(folder, head, function()
			Head.SetCap(model, style, colors, detail)
		end)
		return folder
	end
	local function ell(name, size, cf, c, m)
		return mk(folder, head, name, size, cf, c, "Ellipsoid", m or FABRIC)
	end
	-- a round, flat-topped drum standing on end: diameter d, height h (fractions of the head span), its centre y up
	-- from the head's centre (a Cylinder part's axis is its X: stood up with a 90 deg roll)
	local function drum(name, d, h, y, c, m)
		return mk(folder, head, name, V3(h * hs, d * hs, d * hs), hcf * CF(0, y * hs, 0) * ANG(0, 0, math.pi / 2), c, "Cylinder", m or FABRIC)
	end
	-- a flat ellipsoid visor reaching `reach` ahead of the forehead, its root under the band, pitched down by tilt
	-- degrees about its root (its back end 0.1 behind the forehead, inside the head; the tip at 0.5 + reach in front
	-- of the head's centre)
	local function visor(name, y, t, reach, w, tilt, c)
		local hl = (0.4 + reach) / 2
		local root = hcf * CF(0, y * hs, -0.5 * hs) * ANG(rad(-tilt), 0, 0)
		return ell(name, V3(w * hs, t * hs, 2 * hl * hs), root * CF(0, 0, (0.4 - hl) * hs), c, SMOOTH)
	end
	if ref then
		local R = Head.REFCAP
		-- the crown (at low detail, without the band, it comes down to the band's foot)
		local base = low and R.bandLo or R.crownBase
		local top = R.crownBase + R.crownH
		drum("RCCrown", R.crownW, top - base, (base + top) / 2, capC)
		visor("RCVisor", R.visorY, R.visorT, R.visorReach, R.visorW, R.visorTilt, darken(capC, 0.8))
		if low then
			return done()
		end
		drum("RCBand", R.bandW, R.bandH, R.bandLo + R.bandH / 2, trimC)
		-- the WCB badge on the crown's front, above the band: a gold disc standing 0.02 proud, the wordmark on it
		local fz = -R.crownW / 2 * hs
		local by = R.badgeY * hs
		ell("RCBadge", V3(0.2 * hs, 0.14 * hs, 0.05 * hs), hcf * CF(0, by, fz - 0.005 * hs), badgeC, Enum.Material.Metal)
		Kit.textPatch(folder, head, "RCBadgeText", V3(0.16 * hs, 0.07 * hs, 0.01), hcf * CF(0, by, fz - 0.034 * hs), "WCB",
			Color3.fromRGB(20, 22, 30), Enum.NormalId.Front, "GothamBlack")
		if full then
			-- the gold cord across the band's front, over the visor's root
			ell("RCCord", V3(0.78 * hs, 0.022 * hs, 0.2 * hs), hcf * CF(0, (R.bandLo + 0.04) * hs, -0.47 * hs), badgeC, Enum.Material.Metal)
		end
		return done()
	end
	local B = Head.BALLCAP
	ell("BCCrown", V3(hs * B.domeW, hs * B.domeH * 2, hs * B.domeD), hcf * CF(0, B.domeY * hs, 0.01 * hs), capC)
	visor("BCBill", B.billY, B.billT, B.billReach, B.billW, B.billTilt, trimC)
	if low then
		return done()
	end
	ell("BCButton", V3(0.09 * hs, 0.05 * hs, 0.09 * hs), hcf * CF(0, (B.domeY + B.domeH - 0.008) * hs, 0.01 * hs), capC)
	-- the front panel's WCB (on the dome's front at y 0.41: inside the dome's skin there, the wordmark just out of it)
	local ly = 0.41
	local dz = 0.01 - B.domeD / 2 * math.sqrt(math.max(1 - ((ly - B.domeY) / B.domeH) ^ 2, 0))
	Kit.textPatch(folder, head, "BCLogo", V3(0.2 * hs, 0.08 * hs, 0.01), hcf * CF(0, ly * hs, (dz - 0.012) * hs)
		* ANG(rad(22), 0, 0), "WCB", badgeC, Enum.NormalId.Front, "GothamBlack")
	if full then
		ell("BCSeam", V3(0.03 * hs, hs * B.domeH * 2 + 0.006, hs * B.domeD + 0.006), hcf * CF(0, B.domeY * hs, 0.01 * hs), darken(capC, 0.8))
	end
	return done()
end

------------------------------------------------------------------------
-- Damage
------------------------------------------------------------------------
-- bruise colour by age (Config.FaceDamage.bruiseColors: fresh red-purple, blue-purple, yellow-green,
-- then skin); on deep skin tones bruises read darker rather than coloured
local function bruiseColor(skin, age)
	local stops = Config.FaceDamage.bruiseColors
	local function col(stop)
		return stop.rgb and Color3.fromRGB(stop.rgb[1], stop.rgb[2], stop.rgb[3]) or skin
	end
	local c = col(stops[1])
	for i = 1, #stops - 1 do
		local a, b = stops[i], stops[i + 1]
		if age >= a.day and age <= b.day then
			c = lerpColor(col(a), col(b), (age - a.day) / math.max(0.01, b.day - a.day))
			break
		elseif age > b.day then
			c = col(b)
		end
	end
	local dark = clamp((0.45 - lum(skin)) / 0.3, 0, 1)
	return lerpColor(c, darken(skin, 0.55), dark * 0.55)
end

-- dmg = the CONTRACTS section 8 table (every field optional): leftEye, rightEye, cut, cutSide, cut2,
-- cutSide2, noseBleed, nose (broken), bruise, lip, cheekL, cheekR, forehead, earL, earR, redness, age.
-- folderName (optional) lets the Creator preview into its own folder. Sets attribute FaceDmgTier.
-- About 20 parts at the worst, every one a lens lying on the skin (no Beams: blood is a thin trickle part).
function Head.SetDamage(model, app, dmg, folderName)
	app = app or {}
	dmg = type(dmg) == "table" and dmg or {}
	local stage = Config.FaceDamageStage(dmg)
	model:SetAttribute("FaceDmgTier", stage)
	local head = part(model, "Head")
	if not head then
		return
	end
	local folder = getFolder(model, folderName or "Damage")
	local function n(k)
		return clamp(tonumber(dmg[k]) or 0, 0, 1.5)
	end
	local face = app.face or {}
	local L = Head.FaceLayout(head, face)
	-- a drawn face style: the marks lie on the skin at the drawn features (the swollen lid and the black eye are
	-- surface patches over the drawn eye; no built lid, lashes or white to tint)
	local drawnFace = Head.FaceStyle(model) ~= nil
	if drawnFace then
		Head.DecalLayout(L)
	end
	local s = L.s
	local hcf = head.CFrame
	local skin = skinOf(app)
	local age = math.max(0, tonumber(dmg.age) or 0)
	-- old bruises fade toward the skin over about a week
	local fade = clamp(1 - age / 8, 0.15, 1)
	local bruise = bruiseColor(skin, age)
	local blood = Color3.fromRGB(122, 6, 10)
	local fresh = age < 0.5 -- blood only on fresh damage
	local faceFolder = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Face")
	local function fattr(k, d)
		local v = faceFolder and faceFolder:GetAttribute(k)
		return v ~= nil and v or d
	end
	-- every mark is a lens on the skin (or on the feature it lies on: base = that feature's height); t = transparency
	local function mark(name, x, y, w, h, rise, dk, color, t, roll, base)
		local cf, size = lens(L, x, y, w, h, rise, dk, roll, base)
		return mk(folder, head, name, size, hcf * cf, color, "Ellipsoid", SMOOTH, t)
	end
	-- blood: a thin trickle lying on the skin from (x0, y0) to (x1, y1)
	local function trickle(x0, y0, x1, y1, width, base)
		if not fresh then
			return
		end
		local dx, dy = x1 - x0, y1 - y0
		local len = math.sqrt(dx * dx + dy * dy)
		if len < 1e-3 then
			return
		end
		local sg = dx < 0 and -1 or 1
		local roll = math.atan2(dy * sg, dx * sg)
		-- two pieces: a fuller drop where it starts, a thinner run below
		mark("Blood", x0 + dx * 0.22, y0 + dy * 0.22, len * 0.5, width, 0.0024 + (base or 0), 0.7, blood, 0.05, roll)
		return mark("Blood", x0 + dx * 0.62, y0 + dy * 0.62, len * 0.62, width * 0.62, 0.0022 + (base or 0), 0.7, darken(blood, 0.9), 0.12, roll)
	end
	-- face parts the damage changes: restore first so a lighter state heals visually
	local eyeV = { [-1] = n("leftEye"), [1] = n("rightEye") }
	local severe = stage >= 4
	local brokenNose = dmg.nose == true
	if faceFolder then
		for _, c in ipairs(faceFolder:GetDescendants()) do
			if c:IsA("BasePart") then
				local side = c:GetAttribute("Side")
				local nm = c.Name
				local shut = side and clamp((eyeV[side] - 0.3) / 0.7, 0, 1) > 0
				if nm == "Lid" or nm == "LowerLid" or nm == "BlinkLid" or nm == "Nose" or nm == "NoseTip" or nm == "NoseWing" then
					-- a black eye darkens the lids, a broken nose the nose (from the build colour: a lighter state heals it)
					local baseC = c:GetAttribute("BaseColor")
					if typeof(baseC) ~= "Color3" then
						baseC = c.Color
						c:SetAttribute("BaseColor", baseC)
					end
					local k = 0
					if nm == "Lid" or nm == "BlinkLid" then
						k = (side and eyeV[side] or 0) > 0.12 and clamp(eyeV[side], 0, 1) * 0.6 * fade or 0
					elseif nm == "LowerLid" then
						k = (side and eyeV[side] or 0) > 0.12 and clamp(eyeV[side], 0, 1) * 0.5 * fade or 0
					elseif brokenNose then
						k = 0.35 * fade
					end
					c.Color = k > 0 and lerpColor(baseC, bruise, k) or baseC
					if nm == "Lid" then
						c.Transparency = shut and 1 or 0
					end
				elseif nm == "Glint" then
					c.Transparency = shut and 1 or 0
				elseif nm == "Lashes" then
					-- the lash line rides on its lid: hidden while the swollen lid replaces it
					c.Transparency = shut and 1 or (c:GetAttribute("BaseT") or c.Transparency)
				elseif nm == "Sclera" then
					local baseC = c:GetAttribute("BaseColor")
					if typeof(baseC) == "Color3" then
						local red = clamp((side and eyeV[side] or 0) * 0.5 + (severe and 0.35 or 0) + n("redness") * 0.15, 0, 0.8)
						c.Color = lerpColor(baseC, Color3.fromRGB(228, 150, 140), red)
					end
				elseif nm == "Mouthguard" then
					-- bloodied after a split lip; SetDamage(model, app, {}) cleans it again
					local baseC = c:GetAttribute("BaseColor")
					if typeof(baseC) == "Color3" then
						c.Color = n("lip") > 0.6 and lerpColor(baseC, Color3.fromRGB(140, 10, 16), 0.3) or baseC
					end
				end
			end
		end
	end
	local w, h = L.eyeW, L.eyeHt
	local lidColor = darken(skin, 0.92)
	-- the eyes: a black eye is the socket going dark (a translucent tint that lies under the eye's own parts, so the
	-- eye stays open and readable inside it) with the darker, puffy crescent under the eye where the blood pools; the
	-- lids take the bruise (above). Past 0.3 the upper lid swells: a puffy dome that grows down over the eye until it
	-- shuts it.
	for side = -1, 1, 2 do
		local v = eyeV[side]
		local x, y = side * L.eyeX, L.eyeYS[side]
		local closing = clamp((v - 0.3) / 0.7, 0, 1)
		local k = clamp(v, 0, 1) * fade
		if drawnFace then
			-- a drawn eye (ink ~0.057 x 0.1 of the head, at x, y): the socket darkens round it, a crescent pools under
			-- it, and past 0.3 a puffy lid grows down over it from above until it hides the drawn eye (a slit when shut)
			if closing > 0 then
				local top = y + 0.065 * s.Y
				local bottom = top - (0.04 + 0.1 * closing) * s.Y
				local rise = (0.0115 + 0.005 * closing) * s.Z
				mark("SwollenLid", x + side * 0.004 * s.X, (top + bottom) / 2, (0.105 + 0.02 * closing) * s.X, top - bottom, rise, 0.62,
					lerpColor(darken(skin, 0.94), bruise, 0.12 + 0.2 * k))
				if closing > 0.6 then
					mark("SwollenSlit", x, bottom + 0.012 * s.Y, 0.075 * s.X, 0.009 * s.Y, rise * 0.62, 0.5, Color3.fromRGB(62, 36, 34), 0.15)
				end
			end
			if v > 0.15 then
				mark("BlackEye", x, y + 0.005 * s.Y, (0.15 + 0.02 * k) * s.X, (0.16 + 0.02 * k) * s.Y, 0.0022, 0.75, bruise, clamp(0.8 - 0.32 * k, 0.45, 0.85))
				mark("BlackEyeLow", x + side * 0.006 * s.X, y - (0.075 + 0.006 * k) * s.Y, (0.11 + 0.02 * k) * s.X, (0.035 + 0.015 * k) * s.Y, (0.003 + 0.005 * k) * s.Z, 0.62,
					lerpColor(skin, darken(bruise, 0.85), 0.45 + 0.4 * k), clamp(0.55 - 0.25 * k, 0.3, 0.7), side * rad(-6))
			end
		elseif closing > 0 then
			-- (a wide, low swelling: the lid puffs out sideways more than it stands off the face)
			local top, bottom = y + h * 0.95, y + h * (0.5 - (0.4 + 0.66 * closing))
			local rise = (0.0115 + 0.005 * closing) * s.Z
			mark("SwollenLid", x + side * 0.006 * s.X, (top + bottom) / 2, w * (1.42 + 0.12 * closing), top - bottom, rise, 0.62,
				lerpColor(lidColor, bruise, 0.1 + 0.18 * k), nil, side * L.eyeTilt)
			if closing > 0.6 then
				-- shut: the lash line pressed into a slit at the swelling's lower edge
				mark("SwollenSlit", x, bottom + h * 0.2, w * 0.95, 0.009 * s.Y, rise * 0.62, 0.5, Color3.fromRGB(62, 36, 34), 0.15, side * L.eyeTilt)
			end
		end
		if v > 0.15 and not drawnFace then
			mark("BlackEye", x, y + h * 0.25, w * (1.32 + 0.16 * k), h * (2.1 + 0.3 * k), 0.0022, 0.75, bruise, clamp(0.8 - 0.32 * k, 0.45, 0.85), side * L.eyeTilt)
			mark("BlackEyeLow", x + side * 0.008 * s.X, y - h * (0.8 + 0.06 * k), w * (1.0 + 0.18 * k), h * (0.5 + 0.22 * k), (0.003 + 0.005 * k) * s.Z, 0.62,
				lerpColor(skin, darken(bruise, 0.85), 0.45 + 0.4 * k), clamp(0.55 - 0.25 * k, 0.3, 0.7), side * rad(-6))
		end
		-- a swelling on the cheekbone (a "mouse"): a low smooth dome, the skin going bruise-coloured
		local ck = n(side == -1 and "cheekL" or "cheekR")
		if ck > 0.15 then
			local kk = clamp(ck, 0, 1)
			mark("CheekSwell", side * 0.29 * s.X, -0.05 * s.Y, (0.22 + 0.06 * kk) * s.X, (0.15 + 0.04 * kk) * s.Y, (0.003 + 0.007 * kk) * s.Z + fattr("CheekRise", 0), 0.75,
				lerpColor(skin, bruise, 0.06 + 0.15 * kk * fade), nil, side * rad(14))
		end
		-- swollen ear (the hematoma that becomes a cauliflower ear): a swelling on the upper ear
		local ear = n(side == -1 and "earL" or "earR")
		if ear > 0.25 then
			local earS = 1 + 0.2 * (face.earSize or 0)
			local ecf = hcf * L.shellCF(side * rad(96), 0.03 * s.Y, 0) * ANG(0, side * rad(10), 0)
			local r = (0.026 + 0.016 * ear) * s.X
			mk(folder, head, "EarSwell", V3(0.1 * s.Z * earS, (0.12 + 0.05 * ear) * s.Y * earS, 2 * r), ecf * CF(side * 0.01 * s.Z, 0.06 * s.Y * earS, 0.2 * r),
				lerpColor(skin, bruise, 0.25 + 0.35 * fade), "Ellipsoid", SMOOTH)
		end
	end
	-- cuts: a thin split lying flat on the skin with a little blood. The first opens over the outer end of the brow
	-- (the blood runs down past the outside of the eye), the second on the other cheekbone
	local ridgeRise = fattr("RidgeRise", 0)
	local cutColor = Color3.fromRGB(110, 8, 12)
	local c1, side1 = n("cut"), (tonumber(dmg.cutSide) or 1) < 0 and -1 or 1
	if c1 > 0.05 then
		local v = math.min(c1, 1)
		-- across the tail of the brow (over the brow hairs: the brow lens is ~0.008 high)
		local x, y = side1 * 0.27 * s.X, L.browY + 0.004 * s.Y
		local len = (0.05 + 0.06 * v) * s.X
		mark("Cut", x, y, len, (0.01 + 0.006 * v) * s.Y, 0.0026 + (0.0055 + 0.003) * s.Z + ridgeRise, 0.7, cutColor, nil, side1 * rad(28))
		if v > 0.35 then
			-- the blood runs down past the outside of the eye
			local x0 = side1 * 0.325 * s.X
			trickle(x0, y - 0.015 * s.Y, x0 + side1 * 0.012 * s.X, L.eyeY - (0.0 + 0.04 * v) * s.Y, (0.016 + 0.006 * v) * s.X)
		end
	end
	local c2 = n("cut2")
	if c2 > 0.05 then
		local side2 = tonumber(dmg.cutSide2) and ((tonumber(dmg.cutSide2) < 0) and -1 or 1) or -side1
		local v = math.min(c2, 1)
		mark("Cut", side2 * 0.3 * s.X, -0.01 * s.Y, (0.04 + 0.05 * v) * s.X, (0.009 + 0.005 * v) * s.Y, 0.0026 + fattr("CheekRise", 0), 0.7, cutColor, nil,
			side2 * rad(30))
	end
	-- nose: a broken nose takes the bruise (above); a bleed runs from the nostrils down to the upper lip
	local bleed = n("noseBleed")
	if bleed > 0.2 then
		for side = -1, 1, 2 do
			local x = side * L.noseW * 0.2
			trickle(x, L.noseBottomY - 0.004 * s.Y, x * 1.15, L.mouthY + (0.06 - 0.03 * math.min(bleed, 1)) * s.Y, (0.016 + 0.008 * bleed) * s.X)
		end
	end
	-- bruised face (or a red flush when only lightly marked): a soft translucent tint over the cheek
	local br = n("bruise")
	local cheekBase = fattr("CheekRise", 0)
	if br > 0.2 then
		for side = -1, 1, 2 do
			-- an uneven patch: a wide pale one and a darker core off its middle
			mark("Bruise", side * 0.29 * s.X, -0.06 * s.Y, 0.18 * s.X, 0.12 * s.Y, 0.0022 + cheekBase, 0.7, bruise, math.clamp(0.88 - br * 0.3 * fade, 0.62, 0.9), side * rad(14))
			if br > 0.45 then
				mark("Bruise", side * 0.31 * s.X, -0.045 * s.Y, 0.09 * s.X, 0.065 * s.Y, 0.0032 + cheekBase, 0.7, darken(bruise, 0.9),
					math.clamp(0.86 - br * 0.3 * fade, 0.6, 0.88), side * rad(30))
			end
		end
	elseif stage >= 1 or n("redness") > 0.1 then
		local r = math.max(n("redness"), 0.3)
		for side = -1, 1, 2 do
			mark("Flush", side * 0.28 * s.X, -0.05 * s.Y, 0.18 * s.X, 0.12 * s.Y, 0.002 + cheekBase, 0.7, Color3.fromRGB(196, 70, 66), 0.91 - 0.12 * r, side * rad(14))
		end
	end
	-- a lump over the brow (a "mouse" from a clash of heads or a hook): a low swelling just above the brow
	local lump = n("forehead")
	if lump > 0.2 then
		local side = (tonumber(dmg.cutSide) or 1) < 0 and -1 or 1
		local kk = clamp(lump, 0, 1)
		mark("Lump", side * 0.17 * s.X, L.browY + 0.075 * s.Y, (0.18 + 0.05 * kk) * s.X, (0.1 + 0.03 * kk) * s.Y, (0.003 + 0.006 * kk) * s.Z + ridgeRise * 0.5, 0.75,
			lerpColor(skin, bruise, 0.1 + 0.25 * kk * fade))
	end
	-- busted lip: the lower lip swells on one side, a dark split in it, a little blood running down from it
	local lip = n("lip")
	if lip > 0.25 then
		local lipBase = fattr("LowerLipRise", 0.012 * s.Z)
		local lipC = fattr("LipColor", darken(skin, 0.86))
		local ly = L.mouthY - (0.042 + 0.02 * (face.lips or 0)) * s.Y * 0.38
		if drawnFace then
			ly = L.mouthY - 0.045 * s.Y -- (under the drawn mouth line: the lower lip)
		end
		local top = lipBase
		if lip > 0.45 then
			local kk = clamp(lip, 0, 1)
			top = lipBase + (0.004 + 0.007 * kk) * s.Z
			mark("SwollenLip", 0.045 * s.X, ly, L.mouthW * (0.42 + 0.18 * kk), (0.05 + 0.02 * kk) * s.Y, top, 0.5, lerpColor(lipC, bruise, 0.3 * fade + 0.1))
		end
		mark("SplitLip", 0.05 * s.X, ly + 0.004 * s.Y, 0.028 * s.X, 0.012 * s.Y, top + 0.0012, 0.6, Color3.fromRGB(120, 4, 12))
		if lip > 0.6 then
			trickle(0.055 * s.X, ly - 0.02 * s.Y, 0.06 * s.X, (-0.33 - 0.05 * (severe and 1 or 0)) * s.Y, 0.018 * s.X)
		end
	end
	-- severe: blood on the chest, a mark on the skin over the upper chest (BuilderBody's torso surface)
	if severe and fresh and (n("cut") > 0.3 or bleed > 0.3 or lip > 0.5) then
		local torso = part(model, "UpperTorso")
		-- (required here, never at load: BuilderBody requires this module lazily too)
		local Body = require(script.Parent:WaitForChild("BuilderBody"))
		if torso and Body and Body.SurfaceMark then
			Body.SurfaceMark(folder, torso, "BloodChest", 0.12, 0.3, 0.18, 0.3, Color3.fromRGB(110, 6, 10), 0.35)
		end
	end
end

------------------------------------------------------------------------
-- Sweat
------------------------------------------------------------------------
local SKIN_PARTS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
	"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
}

-- sheen spots, beads and drips on the face (its own folder: it survives face rebuilds as long as
-- the level and the head are unchanged)
local function faceSweat(model, app, q)
	local head = part(model, "Head")
	local look = model:FindFirstChild("BoxerLook")
	if not (head and look) then
		return
	end
	local faceF = look:FindFirstChild("Face")
	local detail = (faceF and faceF:GetAttribute("Detail")) or model:GetAttribute("Detail") or "full"
	local L = Head.FaceLayout(head, app.face or {})
	local drawnStyle = faceF and faceF:GetAttribute("FaceStyle")
	if drawnStyle then
		Head.DecalLayout(L)
	end
	-- the face sliders move the brow / nose the sheen follows: they are part of the key too (and the face style)
	local key = string.format("%.2f|%s|%.3f|%.3f|%.3f|%s", q, tostring(detail), head.Size.X, L.browY, L.noseTopY, tostring(drawnStyle or ""))
	local old = look:FindFirstChild("FaceSweat")
	if old and old:GetAttribute("Key") == key then
		local a = old:FindFirstChild("SweatAnchor")
		local w = a and a:FindFirstChildOfClass("WeldConstraint")
		if w and w.Part0 == head then
			return
		end
	end
	if q < 0.1 or detail == "low" then
		if old then
			old:Destroy()
		end
		return
	end
	local folder = getFolder(model, "FaceSweat")
	folder:SetAttribute("Key", key)
	local s = L.s
	local hcf = head.CFrame
	local anchor = mk(folder, head, "SweatAnchor", V3(0.05, 0.05, 0.05), hcf, WHITE, "Block", SMOOTH, 1)
	-- specular highlights where a wet face catches the light (transparent parts, not Reflectance)
	local cheekRise = (faceF and faceF:GetAttribute("CheekRise")) or 0
	local spots = {
		-- (x, y, w, h, base: what it lies on, the nose bridge or a full cheek)
		{ 0, L.browY + 0.08 * s.Y, 0.24, 0.1 }, { 0, L.noseTopY - L.noseLen * 0.45, 0.05, 0.1, L.noseB * 0.2 },
		{ -0.28 * s.X, -0.02 * s.Y, 0.12, 0.07, cheekRise }, { 0.28 * s.X, -0.02 * s.Y, 0.12, 0.07, cheekRise }, { 0, -0.36 * s.Y, 0.12, 0.06 },
	}
	for i, sp in ipairs(spots) do
		if detail == "full" or i <= 3 then
			-- (faint: a wet face catches the light, it does not wear white patches)
			local cf, size = lens(L, sp[1], sp[2], sp[3] * s.X * 0.85, sp[4] * s.Y * 0.85, 0.0016, 0.85, nil, sp[5])
			mk(folder, head, "Sheen", size, hcf * cf, WHITE, "Ellipsoid", SMOOTH, 0.985 - 0.04 * q)
		end
	end
	if detail ~= "full" then
		return
	end
	if q >= 0.35 then
		local rng = Random.new(((app.face and app.face.seed) or 7) + 505)
		for _ = 1, math.floor(3 + 7 * q) do
			local x = rng:NextNumber(-0.3, 0.3) * s.X
			-- (on a drawn face the beads sit on the forehead above the drawn brows, never on their ink)
			local y = L.browY + rng:NextNumber(-0.02, 0.18) * s.Y + (drawnStyle and 0.07 * s.Y or 0)
			local sz = rng:NextNumber(0.018, 0.03)
			if not (drawnStyle and Head.DecalInkHit(L, x, y, sz, sz * 1.3)) then
				local cf, size = lens(L, x, y, sz, sz * 1.3, 0.006, 0.4)
				local bead = mk(folder, head, "SweatBead", size, hcf * cf, lerpColor(skinOf(app), WHITE, 0.32), "Ellipsoid", SMOOTH, 0.5)
				bead.Reflectance = 0.08
			end
		end
	end
	if q >= 0.4 then
		for _, pos in ipairs({ surfPoint(L, 0.05 * s.X, L.browY + 0.05 * s.Y, 0.01), V3(0, -0.5 * s.Y, L.front(0) * 0.8) }) do
			local a = Instance.new("Attachment")
			a.Name = "Drip"
			a.Position = pos
			a.Parent = anchor
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "SweatDrip"
			pe.Rate = 4 * q
			pe.Lifetime = NumberRange.new(0.5, 0.8)
			pe.Speed = NumberRange.new(0, 0.2)
			pe.Acceleration = V3(0, -14, 0)
			pe.Size = NumberSequence.new(0.035)
			pe.Transparency = NumberSequence.new(0.3, 0.7)
			pe.Color = ColorSequence.new(Color3.fromRGB(235, 240, 245))
			pe.LightInfluence = 1
			pe.Parent = a
		end
	end
end

-- level 0..1; the model attribute "Sweat" is the single source of truth (0.05 steps).
-- Body.SetSweat (BuilderBody) handles muscles, gloves and wraps after this.
function Head.SetSweat(model, app, level)
	app = app or {}
	local q = math.floor(clamp(tonumber(level) or 0, 0, 1) * 20 + 0.5) / 20
	model:SetAttribute("Sweat", q)
	-- a subtle skin sheen: Reflectance mirrors the sky, so keep it low or skin glows white
	local base = (app.face and app.face.shine or 0) * 0.03
	local r = clamp(base + q * 0.05, 0, 0.08)
	for _, n in ipairs(SKIN_PARTS) do
		local p = part(model, n)
		if p and p:IsA("BasePart") then
			if math.abs(p.Reflectance - r) > 1e-4 then
				p.Reflectance = r
			end
			if q > 0.05 then
				if p:GetAttribute("DryMaterial") == nil then
					local ok, name = pcall(function()
						return p.Material.Name
					end)
					p:SetAttribute("DryMaterial", ok and name or "")
				end
				p.Material = SMOOTH
			elseif p:GetAttribute("DryMaterial") ~= nil then
				local name = p:GetAttribute("DryMaterial")
				p:SetAttribute("DryMaterial", nil)
				pcall(function()
					if name ~= "" then
						p.Material = Enum.Material[name]
					end
				end)
			end
		end
	end
	Hair.Wet(model, q)
	faceSweat(model, app, q)
	faceGrime(model, app)
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics)
------------------------------------------------------------------------
Head.Face = faceBuild -- (model, app, opts, build)
Head.Hair = Hair.Build -- (model, app, opts): BuilderHair
Head.Beard = beardBuild -- (model, app, opts)

------------------------------------------------------------------------
-- Hair forwards (BuilderHair) and the helpers the hair shares with the face
------------------------------------------------------------------------
-- hides every hair part / strand a sparring headgear or a robe hood would swallow (BuilderHair)
function Head.ApplyHairHidden(model)
	return Hair.ApplyHairHidden(model)
end

-- region = "headgear" | "hood"; BuilderBody's SetRobe and SetHeadgear below call this
function Head.SetHairHidden(model, region, on)
	return Hair.SetHairHidden(model, region, on)
end

-- A's part budget, the head-surface helpers and the face layout's neighbours, shared with BuilderHair
Head.Shared = {
	lum = lum, skinOf = skinOf, joint = joint, axisCF = axisCF,
	surfNormal = surfNormal, surfPoint = surfPoint, surfCF = surfCF, surfaceLine = surfaceLine, surfacePath = surfacePath,
	countParts = countParts, extraOf = extraOf,
	A_BUDGET = A_BUDGET, FACE_CAP = FACE_CAP, BEARD_RESERVE = BEARD_RESERVE, HAIR_MAX = HAIR_MAX,
}

return Head
