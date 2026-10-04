-- BuilderHead: everything built on the head (server side; the Creator also calls SetDamage locally).
-- * procedural face on the R15 head: sculpted planes (brow ridge, cheekbones, jaw angles, nasolabial
--   folds, philtrum, chin, lip fold), layered eyes (socket shading, tinted sclera, iris with limbal
--   ring and collarette, pupil, two catchlights, wet tear line, caruncle, lids with thickness and a
--   crease), full lips with a vermilion border, teeth + mouth interior (mouthguard at teeth depth),
--   ears with helix and lobe, 6 brow styles, heterochromia, asymmetry, undertone
-- * boxer wear and skin: cauliflower ear, bent nose, permanent fight scars (app.battle), wrinkles by
--   age, pore texture (an honest approximation: material + sparse dots), temple/forehead veins,
--   face fat (full cheeks, jowls) and weight-cut hollows, grime
-- * face rig the client animates (Motor6D "FaceJoint", tag FaceRig, attribute Role): brows, lids,
--   lower lids, eyes (invisible EyeBall pivots), lips, mouth corners, mouth interior; BlinkLid parts
-- * hair: every Looks.HairStyles id x 5 hair types (shrinkage, curl size, sheen, material), fades
--   with gradient bands and a sharp line-up, hairlines and parts, visible growth stages, Beam strands
--   (tag HairStrand) for depth, sway joints (tag HairSway) on locs/braids/long hair and a bounce
--   joint on curl clusters; hidden under headgear / robe hoods
-- * beards: growth stages, own colour, salt & pepper with age, 10 styles, material by hair type
-- * fight damage light .. severe (bruise colour by age), sweat (skin sheen, beads, drips, wet hair)
-- Builder.Cosmetics runs Face, Hair and Beard (in that order) and forwards FaceLayout, SetDamage,
-- SetSweat and SetHeadgear here. Level of detail: opts.detail through Config.DetailLevel.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))

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

-- the head surface: an ellipse across the face (front) that rounds back towards the crown and chin
local function surfNormal(L, x, y)
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

------------------------------------------------------------------------
-- Face layout
------------------------------------------------------------------------
-- returns head-local positions for face features (shared with hair, beard and damage visuals)
-- Fields: s, front(x), surf(x, y), eyeX, eyeY, mouthY, eyeSize, eyeH, browY, noseLen, noseW, noseB,
-- noseTopY, noseBottomY, mouthW, eyeTilt, eyeYS[side], browTiltS[side], mouthTilt, noseDev
function Head.FaceLayout(head, face)
	face = face or {}
	local s = head.Size
	local function front(x)
		local k = clamp(x / (s.X * 0.5), -0.97, 0.97)
		return -s.Z * 0.5 * math.sqrt(1 - k * k)
	end
	-- the head mesh rounds back above the brows and below the mouth
	local function vround(y)
		local e = (math.abs(y) / s.Y - 0.3) / 0.28
		if e <= 0 then
			return 1
		end
		e = math.min(e, 0.97)
		return math.sqrt(1 - e * e)
	end
	local eyeX = (0.19 + 0.035 * (face.eyeDist or 0)) * s.X
	local eyeY = 0.1 * s.Y
	local mouthY = -0.21 * s.Y
	local L = {
		s = s, front = front, eyeX = eyeX, eyeY = eyeY, mouthY = mouthY,
		eyeSize = 1 + 0.25 * (face.eyeSize or 0),
		eyeH = 1 - 0.45 * (face.eyeShape or 0.5),
		browY = eyeY + (0.13 + 0.025 * (face.forehead or 0) + 0.03 * (face.browHeight or 0)) * s.Y,
		noseLen = (0.2 + 0.07 * (face.noseLength or 0)) * s.Y,
		noseW = (0.11 + 0.05 * (face.noseWidth or 0)) * s.X,
		noseB = (0.085 + 0.05 * (face.noseBridge or 0)) * s.Z,
	}
	L.surf = function(x, y)
		return front(x) * vround(y)
	end
	L.noseTopY = eyeY - 0.02 * s.Y
	L.noseBottomY = L.noseTopY - L.noseLen
	L.mouthW = (0.26 + 0.02 * (face.lips or 0) + 0.05 * (face.mouthWidth or 0)) * s.X
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

local function faceBuild(model, app, opts, build)
	opts = opts or {}
	app = app or {}
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local face = app.face or Looks.Defaults(app.gender).face
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") or d:IsA("FaceControls") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	-- the default R15 "dynamic head" bakes a face texture into the mesh: remove it,
	-- the procedural face below replaces it
	-- The face texture can't be removed from a dynamic head while the game is running, so
	-- swap the whole head for a clean one (no built-in eyes) before drawing the face.
	if head:IsA("MeshPart") then
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
		local swapped = hum and pcall(function()
			hum:ReplaceBodyPartR15(Enum.BodyPartR15.Head, clean)
		end)
		if swapped and model:FindFirstChild("Head") == clean then
			head = clean
		else
			clean:Destroy()
			pcall(function()
				head.TextureID = ""
			end)
		end
	end
	local detail, D = Config.DetailLevel(opts)
	local full, low = detail == "full", detail == "low"
	local folder = getFolder(model, "Face")
	folder:SetAttribute("Detail", detail)
	local L = Head.FaceLayout(head, face)
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
	local function on(x, y, out)
		return hcf * surfCF(L, x, y, out or 0)
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
	local function line(name, x0, y0, x1, y1, width, color, transparency, out)
		return surfaceLine(folder, head, head, L, name, x0, y0, x1, y1, width, 0.012 * s.Z, color, transparency, out)
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
	-- the part budget: wear (scars, cauliflower, bent nose) first, then age / skin cosmetics
	local budget = { wear = full and 8 or (detail == "medium" and 2 or 0), skin = full and 8 or (detail == "medium" and 2 or 0) }
	local function spend(kind, n)
		if budget[kind] < n then
			return false
		end
		budget[kind] -= n
		return true
	end

	-- ears: shell + helix rim + lobe; cauliflower lumps fill the upper rim
	local earS = 1 + 0.2 * (face.earSize or 0)
	for side = -1, 1, 2 do
		local ecf = at(side * 0.5 * s.X, 0.02 * s.Y, 0.04 * s.Z) * ANG(0, side * rad(6 + 10 * cauli), 0)
		add("Ear", V3(0.08 * s.X, 0.25 * s.Y * earS, 0.17 * s.Z * earS), ecf, skin, "Ellipsoid")
		if full then
			add("EarHelix", V3(0.045 * s.X, 0.26 * s.Y * earS, 0.06 * s.Z * earS), ecf * CF(side * 0.03 * s.X, 0.015 * s.Y, 0.055 * s.Z * earS), darken(skin, 0.96), "Ellipsoid")
		end
		if full then
			add("EarLobe", V3(0.05 * s.X, 0.065 * s.Y * earS, 0.06 * s.Z * earS), ecf * CF(side * 0.012 * s.X, -0.115 * s.Y * earS, -0.015 * s.Z), lerpColor(skin, under, 0.12), "Ellipsoid")
		end
		if cauli > 0.15 then
			local lumps = full and math.min(2, 1 + math.floor(cauli * 2)) or 1
			for i = 1, (not low and spend("wear", lumps)) and lumps or 0 do
				local sz = (0.05 + 0.045 * cauli) * s.X * (1 - 0.15 * (i - 1))
				add("Cauliflower", V3(sz * 0.9, sz, sz), ecf * CF(side * 0.03 * s.X, (0.08 - 0.06 * (i - 1)) * s.Y * earS, (0.02 + 0.02 * i) * s.Z),
					lerpColor(skin, Color3.fromRGB(150, 100, 100), 0.12 + 0.1 * cauli), "Ellipsoid")
			end
		end
	end
	-- jaw (square / wide jaws stand out from the round head) and the jaw angles that make a jawline
	if jawW > 0.1 then
		local w = (0.82 + 0.2 * jawW) * s.X
		add("Jaw", V3(w, 0.3 * s.Y, 0.86 * s.Z), at(0, -0.36 * s.Y, 0.02 * s.Z), skin, jawDef > 0.55 and "Block" or "Ellipsoid")
	end
	if not low then
		local ja = (female and 0.75 or 1) * (0.8 + 0.4 * jawDef)
		for side = -1, 1, 2 do
			add("JawAngle", V3(0.16 * s.X * ja, 0.2 * s.Y, 0.3 * s.Z), at(side * (0.41 + 0.05 * math.max(jawW, -0.5)) * s.X, -0.32 * s.Y, 0.1 * s.Z) * ANG(0, 0, rad(side * 10)), skin, "Ellipsoid")
		end
	end
	-- chin
	-- sits on the front of the lower face (lower down it hangs under the head like a second chin)
	local chinSize = 0.2 + 0.07 * chin
	local chinY = (-0.385 - 0.025 * chin - chinDrop * 0.5) * s.Y
	add("Chin", V3(chinSize * (1 - chinNarrow) * s.X, (0.13 + 0.04 * chin + chinDrop) * s.Y, 0.14 * s.Z), at(0, chinY, L.front(0) * 0.9), skin, "Ellipsoid")
	if chinDrop > 0 then -- long face: extend the lower face
		add("LowerFace", V3(0.7 * s.X, chinDrop * 2 * s.Y, 0.7 * s.Z), at(0, -0.5 * s.Y, 0), skin, "Ellipsoid")
	end
	if (face.chinCleft or 0) > 0.15 and full and spend("skin", 1) then
		local c = face.chinCleft
		add("ChinCleft", V3(0.012 * s.X, (0.05 + 0.05 * c) * s.Y, 0.03 * s.Z), at(0, chinY + 0.005 * s.Y, L.front(0) * 0.9 - 0.062 * s.Z), darken(skin, 0.8), "Ellipsoid", SMOOTH, 0.75 - 0.35 * c)
	end
	if jowl > 0.05 and full and spend("skin", 2) then
		for side = -1, 1, 2 do
			add("Jowl", V3(0.2 * s.X, (0.14 + 0.06 * jowl) * s.Y, 0.24 * s.Z), at(side * 0.3 * s.X, -0.38 * s.Y, -0.24 * s.Z), skin, "Ellipsoid")
		end
	end
	if jowl > 0.3 and not low and spend("skin", 1) then
		add("DoubleChin", V3((0.42 + 0.12 * jowl) * s.X, (0.1 + 0.06 * jowl) * s.Y, 0.45 * s.Z), at(0, -0.5 * s.Y, -0.18 * s.Z), skin, "Ellipsoid")
	end
	-- cheekbones and cheeks (lean faces show more bone)
	if cheek > -0.5 then
		local bone = 1 + 0.25 * hollow
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			add("Cheekbone", V3(0.22 * s.X * bone, (0.1 + 0.04 * cheek) * s.Y, 0.1 * s.Z),
				at(x, -0.02 * s.Y, L.front(x) + 0.035 - 0.025 * cheek - 0.008 * hollow), skin, "Ellipsoid")
		end
	end
	if cheekFat > 0.05 and hollow <= 0.1 then
		for side = -1, 1, 2 do
			local x = side * 0.33 * s.X
			add("Cheek", V3(0.26 * s.X, 0.24 * s.Y, 0.16 * s.Z), at(x, -0.2 * s.Y, L.front(x) + 0.05 + 0.03 * (1 - math.min(cheekFat, 1))), skin, "Ellipsoid")
		end
	end
	if hollow > 0.1 and full then
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			add("Hollow", V3(0.16 * s.X, 0.14 * s.Y, 0.03 * s.Z), on(x, -0.13 * s.Y, 0.002), darken(skin, 0.8), "Ellipsoid", SMOOTH, 0.82 - 0.3 * hollow)
		end
	end
	-- brow ridge: two halves that follow the forehead curve (scar tissue thickens it on veterans)
	local ridge = math.max(browRidge, (face.forehead or 0) * 0.6, female and 0 or 0.25, math.min(scarCount, 3) * 0.15)
	if not low then
		for side = -1, 1, 2 do
			local x = side * 0.16 * s.X
			add("BrowRidge", V3((0.3 + 0.05 * ridge) * s.X, (0.05 + 0.03 * ridge) * s.Y, (0.035 + 0.025 * ridge) * s.Z),
				on(x, L.browY + 0.012 * s.Y, -0.004 + 0.006 * ridge), skin, "Ellipsoid")
		end
	end

	-- eyes
	local eyeColors = {
		[-1] = Looks.Color(Looks.EyeColors[face.eyeColor or 2]),
		[1] = Looks.Color(Looks.EyeColors[(face.eyeColor2 or 0) > 0 and face.eyeColor2 or (face.eyeColor or 2)]),
	}
	local lidColor = darken(skin, 0.92)
	-- whites of the eye are never pure white; they yellow slightly with age
	local scleraColor = lerpColor(Color3.fromRGB(238, 234, 226), Color3.fromRGB(230, 220, 200), clamp((age - 25) / 30, 0, 1))
	local heavy = clamp(face.lidHeavy or 0, 0, 1)
	local brow = BROWS[face.browStyle or "Natural"] or BROWS.Natural
	local browColor = darken(hairColor, 0.88)
	local bt = (0.028 + 0.02 * ((face.browThick or 0) + 1)) * s.Y * brow.thick
	local lashT = 1 - (0.35 + 0.6 * clamp(face.lashes or 0, 0, 1))
	local underEye = full and (wr > 0.3 or heavy > 0.6) and spend("skin", 2)
	for side = -1, 1, 2 do
		local roleSide = side == -1 and "L" or "R"
		local x = side * L.eyeX
		local y = L.eyeYS[side]
		local z = L.front(x)
		local w = 0.15 * L.eyeSize * s.X
		local h = 0.15 * L.eyeSize * L.eyeH * s.Y
		-- eye frame: canthal tilt raises the outer corner
		local ecf = at(x, y, z) * ANG(0, 0, side * L.eyeTilt)
		local function e(dx, dy, dz)
			return ecf * CF(dx, dy, dz)
		end
		local eyeColor = eyeColors[side]
		if full then
			add("Socket", V3(w * 1.55, h * 2.1, 0.03 * s.Z), e(0, h * 0.15, 0.006), darken(skin, 0.84), "Ellipsoid", SMOOTH, 0.6)
		end
		local sclera = add("Sclera", V3(w, h, 0.05 * s.Z), e(0, 0, -0.004), scleraColor, "Ellipsoid")
		sclera:SetAttribute("BaseColor", scleraColor)
		sclera:SetAttribute("Side", side)
		-- iris, limbal ring, collarette and pupil ride on an invisible EyeBall pivot behind the eye so
		-- the client can turn the gaze; the catchlights stay fixed to the head like real reflections
		local iris = 0.085 * L.eyeSize * s.X
		local holder = head
		if rigOn(detail, "Eye" .. roleSide) then
			holder = rig("Eye" .. roleSide, side, "EyeBall", V3(0.04, 0.04, 0.04), e(0, 0, 0.03), scleraColor, "Ball", SMOOTH, 1)
			holder:SetAttribute("Side", side)
		end
		if full then
			mk(folder, holder, "Limbal", V3(iris * 1.12, math.min(iris * 1.12, h * 0.98), 0.026 * s.Z), e(0, 0, -0.019), darken(eyeColor, 0.42), "Ellipsoid")
		end
		mk(folder, holder, "Iris", V3(iris, math.min(iris, h * 0.95), 0.03 * s.Z), e(0, 0, -0.022), eyeColor, "Ellipsoid")
		if full then
			mk(folder, holder, "IrisInner", V3(iris * 0.62, math.min(iris * 0.62, h * 0.66), 0.02 * s.Z), e(0, 0, -0.027),
				lerpColor(lerpColor(eyeColor, Color3.fromRGB(196, 150, 80), 0.32), WHITE, 0.08), "Ellipsoid", SMOOTH, 0.35)
		end
		mk(folder, holder, "Pupil", V3(iris * 0.46, math.min(iris * 0.46, h * 0.6), 0.02 * s.Z), e(0, 0, -0.032), Color3.fromRGB(8, 8, 10), "Ellipsoid")
		add("Glint", V3(iris * 0.18, iris * 0.18, 0.01), at(x + iris * 0.15, y + iris * 0.15, z - 0.04), WHITE, "Ellipsoid")
		if full then
			add("Glint2", V3(iris * 0.09, iris * 0.09, 0.01), at(x - iris * 0.2, y - iris * 0.16, z - 0.039), WHITE, "Ellipsoid", SMOOTH, 0.35)
			-- moist inner corner and the wet line along the lower lid
			add("Caruncle", V3(0.022 * s.X, 0.03 * s.Y, 0.02 * s.Z), e(-side * w * 0.46, -h * 0.05, -0.018), lerpColor(Color3.fromRGB(214, 128, 128), skin, 0.3), "Ellipsoid")
		end
		-- upper lid: shapes the eye (hooded lids cover more of it); damage swelling hides it
		local lidH = h * (0.32 + 0.22 * heavy)
		local lid = rig("Lid" .. roleSide, side, "Lid", V3(w * 1.08, lidH, 0.045 * s.Z), e(0, h * (0.42 - 0.08 * heavy), -0.012), lidColor, "Ellipsoid")
		lid:SetAttribute("Side", side)
		if not low then
			-- lash line (always: it defines the eye) welded to the lid so it follows a blink or squint
			local lashes = mk(folder, lid, "Lashes", V3(w * 1.04, 0.014 * s.Y, 0.03 * s.Z), e(0, h * (0.42 - 0.08 * heavy) - lidH * 0.42, -0.03) * ANG(0, 0, rad(side * -4)),
				Color3.fromRGB(15, 12, 10), "Ellipsoid", SMOOTH, math.max(0.08, lashT))
			lashes:SetAttribute("BaseT", lashes.Transparency)
			lashes:SetAttribute("Side", side)
		end
		if full then
			add("Crease", V3(w * 0.98, 0.008 * s.Y, 0.02 * s.Z), e(0, h * 0.42 + lidH * 0.52, -0.006), darken(skin, 0.74), "Ellipsoid", SMOOTH, 0.45 + 0.45 * heavy)
			local lower = rig("LowerLid" .. roleSide, side, "LowerLid", V3(w * 1.02, h * 0.24, 0.04 * s.Z), e(0, -h * 0.5, -0.01), lerpColor(lidColor, skin, 0.5), "Ellipsoid")
			lower:SetAttribute("Side", side)
			local tear = mk(folder, lower, "TearLine", V3(w * 0.78, 0.007 * s.Y, 0.012 * s.Z), e(0, -h * 0.38, -0.03), Color3.fromRGB(226, 160, 158), "Ellipsoid", SMOOTH, 0.2)
			tear.Reflectance = 0.1
		end
		if not low then
			-- the client shows this for a blink (never the Lid, which SetDamage hides)
			local blink = add("BlinkLid", V3(w * 1.12, h * 1.05, 0.05 * s.Z), e(0, 0, -0.03), lerpColor(lidColor, skin, 0.4), "Ellipsoid", SMOOTH, 1)
			blink:SetAttribute("Side", side)
		end
		if underEye then
			add("UnderEye", V3(w * 1.1, h * 0.5, 0.03 * s.Z), e(0, -h * 0.9, 0.004), darken(skin, 0.82), "Ellipsoid", SMOOTH, 0.82 - 0.3 * wr)
		end
		-- eyebrow: inner head, body and tail; the body is the rigged part, the others are welded to it
		local bx = side * L.eyeX * 1.02
		local by = L.browY + (L.eyeYS[side] - L.eyeY)
		local tilt = side * ((face.browAngle or 0) * rad(9)) + L.browTiltS[side]
		local blen = 0.21 * s.X * brow.len
		local bcf = hcf * CF(bx, by, L.front(bx) - 0.012) * ANG(0, 0, tilt)
		local browPart = rig("Brow" .. roleSide, side, "Brow", V3(blen * 0.46, bt, 0.035 * s.Z), bcf * ANG(0, -side * rad(8), 0), browColor, "Block", FABRIC)
		browPart:SetAttribute("Side", side)
		if full then
			local ix = bx - side * blen * 0.36
			mk(folder, browPart, "BrowInner", V3(blen * 0.36, bt * 1.12, 0.035 * s.Z),
				hcf * CF(ix, by - bt * 0.25 * brow.arch, L.front(ix) - 0.01) * ANG(0, 0, tilt + side * rad(4 + 8 * brow.arch)) * ANG(0, -side * rad(4), 0), browColor, "Ellipsoid", FABRIC)
			local ox = bx + side * blen * 0.36
			mk(folder, browPart, "BrowOuter", V3(blen * 0.38, bt * brow.taper, 0.03 * s.Z),
				hcf * CF(ox, by - bt * 0.45 * brow.arch, L.front(ox) - 0.01) * ANG(0, 0, tilt - side * rad(6 + 14 * brow.arch)) * ANG(0, -side * rad(16), 0), browColor, "Ellipsoid", FABRIC)
		end
	end

	-- nose: bridge, tip, alar wings and nostrils; a broken nose sits flatter, wider and bent
	local bend = (Random.new((face.seed or 7) + 303):NextNumber() < 0.5) and -1 or 1
	local nW = L.noseW * (1 + 0.2 * noseBreak)
	local nB = L.noseB * (1 - 0.25 * noseBreak)
	local dev = L.noseDev + 0.03 * noseBreak * bend * s.X
	local noseCol = darken(skin, 0.97)
	local nose = add("Nose", V3(nW, L.noseLen, nB),
		at(dev * 0.4, (L.noseTopY + L.noseBottomY) / 2, L.front(0) - nB / 2 + 0.012) * ANG(0, 0, rad(-7 * noseBreak * bend)), noseCol, "Wedge")
	nose:SetAttribute("Base", true)
	add("NoseTip", V3(nW * 0.9, nW * 0.7, nB * 0.7), at(dev, L.noseBottomY + nW * 0.25, L.front(0) - nB * 0.75), noseCol, "Ellipsoid")
	if full then
		for side = -1, 1, 2 do
			add("NoseWing", V3(nW * 0.4, nW * 0.5, nB * 0.55), at(dev + side * nW * 0.47, L.noseBottomY + nW * 0.24, L.front(0) - nB * 0.42), darken(skin, 0.95), "Ellipsoid")
		end
	end
	if not low then
		for side = -1, 1, 2 do
			add("Nostril", V3(0.03 * s.X, 0.02 * s.Y, 0.03 * s.Z), at(dev + side * nW * 0.28, L.noseBottomY + 0.006, L.front(0) - nB * 0.6), darken(skin, 0.45), "Ellipsoid")
		end
	end
	if noseBreak > 0.3 and full and spend("wear", 1) then
		add("NoseBump", V3(nW * 0.55, L.noseLen * 0.22, nB * 0.5), at(dev * 0.3, L.noseTopY - L.noseLen * 0.3, L.front(0) - nB * 0.62), noseCol, "Ellipsoid")
	end
	-- nasolabial folds: deepen with age, fat and a big smile line
	if full then
		local fold = clamp(0.3 + 0.5 * wr + 0.25 * faceFat, 0, 1)
		for side = -1, 1, 2 do
			line("Nasolabial", dev + side * nW * 0.62, L.noseBottomY + nW * 0.15, side * L.mouthW * 0.6, L.mouthY - 0.015 * s.Y,
				(0.012 + 0.008 * fold) * s.X, darken(skin, 0.78), 0.86 - 0.35 * fold, 0.002)
		end
	end

	-- mouth: lips (rigged), corners, interior and teeth; a mouthguard parts the lips at teeth depth
	local guard = opts.mouthguard and true or false
	local lt = face.lips or 0
	local mw = L.mouthW
	local upperH = (0.036 + 0.02 * lt + (female and 0.006 or 0)) * s.Y
	local lowerH = (0.046 + 0.026 * lt + (female and 0.006 or 0)) * s.Y
	local mz = L.front(0)
	local mcf = at(0, L.mouthY, 0) * ANG(0, 0, L.mouthTilt)
	local function m(dx, dy, dz)
		return mcf * CF(dx, dy, mz + dz)
	end
	local gap = guard and 0.016 * s.Y or 0
	local bulge = guard and 0.008 or 0
	-- pigmented lips: darker on deep skin tones, rosier on light ones
	local lipColor = lerpColor(darken(skin, 0.84 + 0.1 * skinL), under, 0.16 + 0.3 * skinL + (female and 0.06 or 0))
	if full then
		local inside = rig("MouthInside", nil, "MouthInside", V3(mw * 0.8, upperH + lowerH * 0.9, 0.012 * s.Z), m(0, -gap * 0.5, -0.008), Color3.fromRGB(62, 20, 24), "Ellipsoid")
		add("TeethUpper", V3(mw * 0.6, upperH * 0.6, 0.012 * s.Z), m(0, upperH * 0.05, -0.017), Color3.fromRGB(232, 226, 208), "Ellipsoid")
		mk(folder, inside, "TeethLower", V3(mw * 0.55, lowerH * 0.4, 0.012 * s.Z), m(0, -gap - lowerH * 0.12, -0.016), Color3.fromRGB(222, 214, 194), "Ellipsoid")
	end
	local upper = rig("UpperLip", nil, "UpperLip", V3(mw, upperH, 0.05 * s.Z), m(0, upperH * 0.55, -0.006 - bulge), lipColor, "Ellipsoid")
	local lower = rig("LowerLip", nil, "LowerLip", V3(mw * 0.92, lowerH, 0.055 * s.Z), m(0, -lowerH * 0.5 - gap, -0.004 - bulge), lerpColor(lipColor, WHITE, 0.03), "Ellipsoid")
	upper:SetAttribute("BaseSize", upper.Size)
	lower:SetAttribute("BaseSize", lower.Size)
	local mline = add("MouthLine", V3(mw * 0.85, 0.008 * s.Y, 0.03 * s.Z), m(0, -gap * 0.5, -0.022), darken(lipColor, 0.45), "Block", SMOOTH, guard and 0.7 or 0)
	mline:SetAttribute("BaseSize", mline.Size)
	if full then
		-- vermilion border: the pale rim that outlines the upper lip; a soft sheen on the lower lip
		mk(folder, upper, "LipBorder", V3(mw * 1.02, 0.01 * s.Y, 0.03 * s.Z), m(0, upperH * 1.02, -0.02), lerpColor(skin, WHITE, 0.16), "Ellipsoid", SMOOTH, 0.45)
		for side = -1, 1, 2 do
			local cx = side * mw * 0.5
			local corner = rig("MouthCorner" .. (side == -1 and "L" or "R"), side, "MouthCorner", V3(0.03 * s.X, 0.03 * s.Y, 0.03 * s.Z),
				m(cx, -gap * 0.5 - 0.002, L.front(cx) - mz - 0.008), darken(lipColor, 0.7), "Ellipsoid")
			corner:SetAttribute("Side", side)
		end
		-- philtrum groove and the fold under the lower lip
		local py0 = L.noseBottomY - 0.004 * s.Y
		local py1 = L.mouthY + upperH * 1.05
		if py0 > py1 then
			add("Philtrum", V3(0.055 * s.X, py0 - py1, 0.02 * s.Z), at(dev * 0.5, (py0 + py1) / 2, mz - 0.004), darken(skin, 0.88), "Ellipsoid", SMOOTH, 0.6)
		end
		line("LipFold", -mw * 0.28, L.mouthY - lowerH * 1.2 - gap, mw * 0.28, L.mouthY - lowerH * 1.2 - gap, 0.012 * s.Y, darken(skin, 0.8), 0.6, 0.002)
	end

	-- skin details (deterministic from the face seed; draw order is load-bearing, keep it)
	local rng = Random.new(face.seed or 7)
	local function spot(name, size, color, xMin, xMax, yMin, yMax, transparency, skip)
		local x = rng:NextNumber(xMin, xMax) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(yMin, yMax) * s.Y
		if skip then
			return nil
		end
		return add(name, size, at(x, y, L.front(x) - 0.004), color, "Ellipsoid", SMOOTH, transparency)
	end
	local freck = math.floor((face.freckles or 0) * 26)
	for i = 1, freck do
		local sz = rng:NextNumber(0.018, 0.03)
		spot("Freckle", V3(sz, sz, 0.01), darken(skin, 0.72), 0.06, 0.34, -0.1, 0.06, 0.25, i > (D.freckles or 26))
	end
	for _ = 1, math.floor(face.moles or 0) do
		spot("Mole", V3(0.035, 0.035, 0.015), darken(skin, 0.35), 0.1, 0.36, -0.32, 0.25)
	end
	for _ = 1, math.floor(face.scars or 0) do
		local x = rng:NextNumber(0.08, 0.32) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(-0.12, 0.3) * s.Y
		local a = math.rad(rng:NextNumber(-40, 40))
		add("Scar", V3(0.016, rng:NextNumber(0.1, 0.2) * s.Y, 0.012), at(x, y, L.front(x) - 0.006) * ANG(0, 0, a), lerpColor(skin, Color3.fromRGB(235, 190, 190), 0.55), "Block")
	end
	for _ = 1, math.floor((face.acne or 0) * 14) do
		spot("Acne", V3(0.024, 0.024, 0.012), lerpColor(skin, Color3.fromRGB(190, 60, 60), 0.5), 0.05, 0.36, -0.32, 0.32, nil, low)
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
			if i > 6 or not spend("wear", 1) then
				break
			end
			if type(sc) == "table" then
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
				line("BattleScar", x - dx, y - dy, x + dx, y + dy, (0.012 + 0.01 * size) * s.X, scarColor, 0.1, 0.004)
				if (kind == "brow" or kind == nil) and spend("wear", 1) then
					-- the hair never grows back through a brow scar
					local bp
					for _, c in ipairs(folder:GetChildren()) do
						if c.Name == "Brow" and c:GetAttribute("Side") == side then
							bp = c
						end
					end
					mk(folder, bp or head, "BrowGap", V3(0.018 * s.X, bt * 1.4, 0.04 * s.Z), hcf * CF(x, L.browY + (L.eyeYS[side] - L.eyeY), L.front(x) - 0.014), skin, "Block")
				end
			end
		end
	end
	-- wrinkles with age (forehead lines, crow's feet)
	if D.wrinkles and full and wr > 0.25 and spend("skin", 2) then
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
	end
	-- pores: textures are not possible here, so a pore-heavy skin gets a grainy material (above)
	-- plus a few sparse darker dots on the nose and cheeks at full detail
	if full and (face.pores or 0) > 0.3 then
		local n = math.min(5, math.floor((face.pores - 0.3) / 0.7 * 5 + 0.5))
		for _ = 1, n do
			if not spend("skin", 1) then
				break
			end
			local x = r2:NextNumber(-0.28, 0.28) * s.X
			local y = r2:NextNumber(-0.14, 0.02) * s.Y
			add("Pore", V3(0.014, 0.014, 0.008), on(x, y, 0.002), darken(skin, 0.8), "Ellipsoid", SMOOTH, 0.6)
		end
	end
	-- a living flush on the cheeks (reads on light and mid skin tones)
	if full and skinL > 0.35 and wr < 0.3 and spend("skin", 2) then
		for side = -1, 1, 2 do
			add("Blush", V3(0.2 * s.X, 0.12 * s.Y, 0.03 * s.Z), on(side * 0.27 * s.X, -0.06 * s.Y, 0.002), under, "Ellipsoid", SMOOTH, 0.9 - (female and 0.04 or 0))
		end
	end
	-- veins the client reveals during effort / anger / heavy sweat; leaner faces show them more
	if full then
		local veinColor = lerpColor(darken(skin, 0.86), Color3.fromRGB(70, 92, 140), 0.18)
		local vis = clamp(0.62 - 0.25 * clamp((FB.defZero - fat) / (FB.defZero - FB.defFull), 0, 1), 0.3, 0.7)
		-- one temple (seeded side) and the classic diagonal forehead vein on the other
		local vs = (r2:NextNumber() < 0.5) and -1 or 1
		local veins = {
			line("TempleVein", vs * 0.36 * s.X, L.browY + 0.02 * s.Y, vs * 0.33 * s.X, L.browY + 0.14 * s.Y, 0.014 * s.X, veinColor, 1, 0.006),
			line("ForeheadVein", -vs * 0.07 * s.X, L.browY + 0.05 * s.Y, -vs * 0.1 * s.X, L.browY + 0.19 * s.Y, 0.014 * s.X, veinColor, 1, 0.006),
		}
		for _, v in ipairs(veins) do
			v:SetAttribute("BaseTransparency", vis)
		end
	end
	-- dirt from roadwork / floor drills
	local grime = clamp(tonumber(opts.grime) or tonumber(model:GetAttribute("Grime")) or 0, 0, 1)
	local dirt = Color3.fromRGB(110, 90, 70)
	if grime > 0.1 and full then
		add("Grime", V3(0.26 * s.X, 0.1 * s.Y, 0.03 * s.Z), on(-0.1 * s.X, L.browY + 0.08 * s.Y, 0.003), dirt, "Ellipsoid", SMOOTH, 0.88 - 0.22 * grime)
	end
	if grime > 0.5 and full then
		add("Grime", V3(0.16 * s.X, 0.12 * s.Y, 0.03 * s.Z), on(0.3 * s.X, -0.15 * s.Y, 0.003), dirt, "Ellipsoid", SMOOTH, 0.9 - 0.22 * grime)
	end
	-- mouthguard sits at teeth depth, showing between the parted lips (bloodied after a split lip)
	if guard then
		local mg = Looks.Color(app.attire and app.attire.mouthguard, Color3.fromRGB(40, 80, 200))
		local dmg = type(opts.damage) == "table" and opts.damage or nil
		if dmg and (tonumber(dmg.lip) or 0) > 0.6 then
			mg = lerpColor(mg, Color3.fromRGB(140, 10, 16), 0.3)
		end
		add("Mouthguard", V3(mw * 0.92, (0.05 + 0.01 * lt) * s.Y, 0.03 * s.Z), m(0, -gap * 0.5, -0.02), mg, "Ellipsoid")
	end
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
		hpart(H, "Curl", V3(r, r, r), CF(x, y, z), H.colorFn(i, yN, x), "Ball", H.mat, nil, anchor)
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
		strands = 0, maxStrands = D.strands or 0, skin = skinOf(app),
	}
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
		local bands = lod(H, 3, 2, 1)
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
				add("Wave", V3(s.X * 0.9, 0.025 * s.Y, 0.12 * s.Z), at(0, (0.3 + i * 0.045) * s.Y, (-0.35 + i * 0.16) * s.Z) * ANG(math.rad(-20 + i * 10), 0, 0), darken(base, 0.85), "Ellipsoid", mat)
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
		elseif kind == "Straight" and H.detail ~= "low" then
			surfacePath(H.folder, head, head, Lay, "HairlineEdge", { { -0.28 * sx, hlY - 0.005 * s.Y }, { 0, hlY - 0.012 * s.Y }, { 0.28 * sx, hlY - 0.005 * s.Y } }, 0.045 * s.Y, 0.03 * s.Z, base, 0, 0.01, mat)
		end
		-- the line-up: barber-sharp edges at the hairline, temple corners and sideburns (gone in ~2 weeks)
		if (kind == "Line-Up" or (shaved and kind == "Straight")) and growth < 0.35 and H.detail == "full" then
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
		if p ~= "None" and H.capC and H.detail == "full" then
			local f = p == "Left" and -0.32 or (p == "Right" and 0.32 or 0)
			local col = lerpColor(base, skin, shaved and 0.75 or 0.45)
			pathLine(H, "HairPart", { hairlinePoint(H, f * 0.5 * sx, 0.016), combPoint(H, f, -0.45, 0.005), combPoint(H, f * 0.95, 0.1, 0.005) },
				(shaved and 0.02 or 0.013) * sx, col, 0)
		end
	end
	-- growth stages: hair creeps down the nape and over the ears as a cut grows out
	local function grownOut()
		if growth > 0.6 and H.detail ~= "low" then
			add("Nape", V3(0.78 * s.X, (0.16 + 0.12 * grow) * s.Y, 0.3 * s.Z), at(0, -0.12 * s.Y, 0.42 * s.Z), lerpColor(base, skin, 0.15), "Ellipsoid", mat)
			if growth > 0.9 then
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
			if H.detail ~= "low" then
				add("NapeTaper", V3(0.8 * s.X, 0.22 * s.Y, 0.3 * s.Z), at(0, -0.08 * s.Y, 0.42 * s.Z), lerpColor(base, skin, 0.7 * (1 - 0.8 * grow)), "Ellipsoid", SMOOTH)
				for side = -1, 1, 2 do
					add("SideburnTaper", V3(0.05 * s.X, 0.2 * s.Y, 0.12 * s.Z), at(side * 0.5 * s.X, 0.02 * s.Y, -0.06 * s.Z), lerpColor(base, skin, 0.5 * (1 - 0.8 * grow)), "Ellipsoid", SMOOTH)
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
				add("Texture", V3(0.13 * s.X, (0.09 + L * 0.06) * s.Y, 0.5 * s.Z), at(x, 0.55 * s.Y, -0.05 * s.Z) * ANG(math.rad(-10), 0, math.rad((i % 2 == 0) and 6 or -6)),
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
				add("Tuft", V3(0.11 * s.X, (0.1 + 0.06 * L) * s.Y, 0.12 * s.Z), at(x, (0.55 - 0.15 * (z / s.Z + 0.38) * 0.4) * s.Y, z) * ANG(rng:NextNumber(-0.9, -0.4), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.3, 0.3)),
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
			if H.detail ~= "low" then
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
		bumps(H, math.floor(lod(H, 30, 16, 8) * (0.6 + 0.5 * density)), (0.1 + 0.05 * thick + 0.04 * L * TT.shrink) * TT.radius * s.X, 0.55, H.seed + 23, pivot)
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
				add("Curl", V3(r, r, r), at(px, py, pz), colorFn(i, (u + 1) / 2, px), "Ball", hm, nil, pivot)
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
			add("Curl", V3(r, r * 0.6, r), at(x, (0.45 + hgt) * s.Y, z), colorFn(i, 1, x), "Ball", hm, nil, pivot)
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
				add("Groove", V3(0.02 * s.X, 0.02 * s.Y, 0.7 * s.Z), at(x, 0.56 * s.Y, 0.02 * s.Z), darken(base, 0.6), "Block", SMOOTH)
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
			add("Sweep", V3(0.16 * s.X, (0.1 + L * 0.06) * s.Y, 0.6 * s.Z), at(x + 0.05 * s.X, 0.5 * s.Y + topH * 0.3, -0.12 * s.Z) * ANG(math.rad(-14), 0, math.rad(-12)),
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
			add("Tuft", V3(0.12 * s.X, (0.15 + L * 0.2 * T.shrink) * s.Y, 0.12 * s.Z),
				at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.7, 0.7), 0, rng:NextNumber(-0.7, 0.7)), colorFn(i, 0.3, x), "Wedge", mat)
		end
		flyaways(H, lod(H, 20, 8, 0), 0.5 + 0.4 * L, 0.05, 1.3)
		hairline(false)
	elseif style == "Cornrows" then
		add("Scalp", V3(s.X * 1.03, s.Y * 0.5, s.Z * 1.05), at(0, 0.36 * s.Y, 0.03 * s.Z), lerpColor(base, skin, 0.25), "Ellipsoid", SMOOTH)
		setShell(V3(0, 0.36 * s.Y, 0.03 * s.Z), V3(s.X * 1.03, s.Y * 0.5, s.Z * 1.05))
		local rows = lod(H, 5 + math.floor(density * 3), 5, 3)
		for i = 1, rows do
			local x = (i - (rows + 1) / 2) * (0.85 / rows) * s.X
			for j = 0, lod(H, 4, 3, 2) - 1 do
				local a = math.rad(-50 + j * (152 / lod(H, 4, 3, 2)))
				local y = 0.3 * s.Y + math.cos(a) * 0.25 * s.Y
				local z = math.sin(a) * 0.58 * s.Z
				-- alternate a slight twist so each row reads as plaited
				add("Row", V3(0.07 * s.X * (0.8 + thick * 0.5), 0.07 * s.Y, 0.24 * s.Z), at(x, y, z) * ANG(a, 0, math.rad((j % 2 == 0) and 8 or -8)), colorFn(i, j / 3, x), "Ellipsoid", mat)
			end
			if hang > 0.45 and i % 2 == 0 and H.detail ~= "low" then
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
		local n = math.floor(lod(H, box and 14 or 10, 8, 5) + density * lod(H, box and 4 or 6, 2, 1))
		local segs = twists and 1 or ((hang > 0.7 or L > 0.7) and lod(H, 3, 1, 1) or lod(H, 2, 1, 1))
		local segLen = (twists and 0.22 or 0.28 + 0.2 * L) * s.Y
		if segs == 1 and not twists then
			segLen *= 1.6
		end
		local w = (box and 0.06 or (braided and 0.07 or 0.1)) * s.X * (0.8 + 0.5 * thick)
		-- keep the chains inside the part budget (hero ~50, NPC ~22 segments)
		local crownSegs = segs >= 3 and 1 or segs
		n = math.min(n, math.floor(lod(H, 50, 22, 10) / (segs + 0.5 * crownSegs)))
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
				add("Shag", V3(0.16 * s.X, 0.2 * s.Y, 0.16 * s.Z), at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)), colorFn(i, 0.2, x), "Wedge", mat)
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
		add("HairTie", V3(0.14 * s.X, 0.14 * s.Y, 0.1 * s.Z), CF(tie), Looks.Color(app.attire and app.attire.trim, WHITE), "Ellipsoid", SMOOTH)
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
	Head.ApplyHairHidden(model)
end

------------------------------------------------------------------------
-- Hair under headgear / a robe hood
------------------------------------------------------------------------
-- hides every hair part / strand the shell or hood would swallow and restores them afterwards.
-- Parts get attribute HGHidden (and HGBaseT, the transparency to restore); strands are disabled.
function Head.ApplyHairHidden(model)
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
function Head.SetHairHidden(model, region, on)
	model:SetAttribute(region == "hood" and "HairHiddenHood" or "HairHiddenHeadgear", on and true or nil)
	Head.ApplyHairHidden(model)
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
	local beard = app.beard or { style = "None", growth = 0 }
	if app.gender == 2 then
		return
	end
	local style = beard.style or "None"
	if not table.find(Looks.BeardStyles, style) then
		style = Looks.BeardStyleBase[style] or "None"
	end
	local g = clamp(tonumber(beard.growth) or 0, 0, 1)
	-- growth stages without a chosen style: shadow -> stubble -> a short natural beard
	local shadow = false
	if style == "None" then
		if g < 0.2 then
			return
		elseif g < 0.45 then
			style, shadow = "Stubble", true
		elseif g < 0.8 then
			style = "Stubble"
		else
			style, g = "Short Boxed", (g - 0.8) * 2
		end
	end
	local detail = Config.DetailLevel(opts)
	local s = head.Size
	local hcf = head.CFrame
	local L = Head.FaceLayout(head, app.face or {})
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
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	local function add(name, size, cf, col, shape, material, transparency)
		return mk(folder, head, name, size, cf, col or color, shape or "Ellipsoid", material or mat, transparency)
	end
	local mw = L.mouthW
	local function moustache(width, drop)
		-- two halves angled down toward the mouth corners
		for side = -1, 1, 2 do
			add("Moustache", V3((width or 0.17) * s.X, (0.045 + 0.03 * g) * s.Y, 0.06 * s.Z),
				at(side * 0.075 * s.X, L.mouthY + 0.062 * s.Y, L.front(side * 0.075 * s.X) - 0.025) * ANG(0, 0, L.mouthTilt + side * math.rad(-(drop or 10))))
		end
	end
	local function chinPatch(w, h, y)
		add("Goatee", V3(w * s.X, (h + 0.08 * g) * s.Y, 0.16 * s.Z), at(0, (y or -0.44) * s.Y, L.front(0) * 0.82))
	end
	local function sideburns(t)
		for side = -1, 1, 2 do
			add("Sideburn", V3(0.05 * s.X, 0.26 * s.Y, 0.14 * s.Z), at(side * 0.5 * s.X, -0.02 * s.Y, -0.06 * s.Z), color, "Ellipsoid", mat, t)
		end
	end
	local function neck(t)
		if detail ~= "low" then
			add("NeckBeard", V3(0.72 * s.X, 0.12 * s.Y, 0.6 * s.Z), at(0, -0.49 * s.Y, -0.12 * s.Z), color, "Ellipsoid", mat, t)
		end
	end
	if style == "Stubble" then
		-- front-biased shell: covers the jaw, chin and upper lip but never the back of the head
		local t = shadow and 0.9 or (0.8 - 0.12 * g)
		add("Stubble", V3(s.X * 1.06, s.Y * 0.46, s.Z * 1.0), at(0, -0.3 * s.Y, -0.07 * s.Z), color, "Ellipsoid", SMOOTH, t)
		neck(math.min(0.95, t + 0.05))
	elseif style == "Goatee" then
		chinPatch(0.24, 0.2)
		moustache()
	elseif style == "Van Dyke" then
		-- pointed chin beard and a moustache that does not connect to it
		add("Goatee", V3(0.2 * s.X, (0.22 + 0.08 * g) * s.Y, 0.15 * s.Z), at(0, -0.46 * s.Y, L.front(0) * 0.8), color, "Ellipsoid")
		add("SoulPatch", V3(0.06 * s.X, 0.06 * s.Y, 0.05 * s.Z), at(0, L.mouthY - 0.085 * s.Y, L.front(0) - 0.02))
		moustache(0.16, 18)
	elseif style == "Circle Beard" then
		chinPatch(0.26, 0.18)
		moustache()
		-- the ring around the mouth joining moustache and chin
		for side = -1, 1, 2 do
			local x = side * mw * 0.62
			add("CircleSide", V3(0.05 * s.X, 0.16 * s.Y, 0.05 * s.Z), at(x, L.mouthY - 0.03 * s.Y, L.front(x) - 0.012) * ANG(0, 0, side * math.rad(8)))
		end
	elseif style == "Moustache" then
		moustache()
	elseif style == "Chin Strap" then
		for side = -1, 1, 2 do
			add("Strap", V3(0.06 * s.X, 0.42 * s.Y, 0.5 * s.Z), at(side * 0.46 * s.X, -0.25 * s.Y, -0.05 * s.Z) * ANG(0, 0, math.rad(side * 12)), color, "Block")
		end
		add("StrapChin", V3(0.55 * s.X, 0.08 * s.Y, 0.3 * s.Z), at(0, -0.5 * s.Y, L.front(0) * 0.55))
	elseif style == "Mutton Chops" then
		-- broad sideburns down to the jaw, a clean chin
		for side = -1, 1, 2 do
			add("Chop", V3(0.12 * s.X, (0.36 + 0.06 * g) * s.Y, 0.42 * s.Z), at(side * 0.45 * s.X, -0.18 * s.Y, -0.08 * s.Z) * ANG(0, 0, math.rad(side * 8)))
		end
		moustache(0.18, 6)
	elseif style == "Short Boxed" then
		add("Beard", V3(s.X * 1.06, s.Y * (0.48 + 0.06 * g), s.Z * 1.02), at(0, -0.3 * s.Y, -0.06 * s.Z))
		neck()
		sideburns()
		moustache()
	else -- Full Beard
		add("Beard", V3(s.X * 1.1, s.Y * (0.58 + 0.16 * g), s.Z * 1.06), at(0, -0.36 * s.Y, -0.06 * s.Z))
		add("BeardChin", V3(0.5 * s.X, (0.2 + 0.1 * g) * s.Y, 0.3 * s.Z), at(0, (-0.55 - 0.05 * g) * s.Y, -0.3 * s.Z))
		neck()
		sideburns()
		moustache(0.18, 8)
	end
	-- grey flecks on older beards
	if grey > 0.15 and detail == "full" and style ~= "Stubble" then
		local rng = Random.new((app.face and app.face.seed or 7) + 404)
		for _ = 1, 2 + math.floor(grey * 4) do
			local x = rng:NextNumber(-0.12, 0.12) * s.X
			add("GreyFleck", V3(0.05 * s.X, 0.04 * s.Y, 0.03 * s.Z), at(x, rng:NextNumber(-0.47, -0.36) * s.Y, L.front(x) * 0.84 - 0.03), Color3.fromRGB(200, 198, 192), "Ellipsoid", mat, 0.3)
		end
	end
	-- keep the lips visible through the beard (from their base size: rebuilds never stack)
	if face and style ~= "Stubble" then
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
-- Headgear (toggled during sparring)
------------------------------------------------------------------------
function Head.SetHeadgear(model, color, on)
	local folder = getFolder(model, "Headgear")
	Head.SetHairHidden(model, "headgear", on)
	if not on then
		return
	end
	local head = part(model, "Head")
	if not head then
		return
	end
	local s = head.Size
	local mat = Enum.Material.Leather
	local hcf = head.CFrame
	mk(folder, head, "HGTop", V3(s.X * 1.18, s.Y * 0.62, s.Z * 1.18), hcf * CF(0, 0.36 * s.Y, 0.05 * s.Z), color, "Ellipsoid", mat)
	-- padded brow bar over the eyes
	mk(folder, head, "HGBrow", V3(s.X * 0.86, s.Y * 0.14, s.Z * 0.2), hcf * CF(0, 0.3 * s.Y, -0.5 * s.Z), darken(color, 0.92), "Ellipsoid", mat)
	for side = -1, 1, 2 do
		mk(folder, head, "HGCheek", V3(0.16 * s.X, 0.62 * s.Y, 0.75 * s.Z), hcf * CF(side * 0.52 * s.X, -0.08 * s.Y, 0.05 * s.Z), color, "Ellipsoid", mat)
	end
	mk(folder, head, "HGBack", V3(s.X * 1.1, s.Y * 0.7, 0.2 * s.Z), hcf * CF(0, 0.05 * s.Y, 0.55 * s.Z), color, "Ellipsoid", mat)
	mk(folder, head, "HGStrap", V3(s.X * 0.6, 0.06 * s.Y, 0.3 * s.Z), hcf * CF(0, -0.52 * s.Y, -0.1 * s.Z), darken(color, 0.6), "Block")
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
-- At most 20 parts; blood runs as Beams from one invisible DamageAnchor.
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
	local s = L.s
	local hcf = head.CFrame
	local skin = skinOf(app)
	local age = math.max(0, tonumber(dmg.age) or 0)
	-- old bruises fade toward the skin over about a week
	local fade = clamp(1 - age / 8, 0.15, 1)
	local bruise = bruiseColor(skin, age)
	local blood = Color3.fromRGB(128, 4, 8)
	local fresh = age < 0.5 -- blood only on fresh damage
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	local function add(name, size, cf, color, shape, transparency)
		return mk(folder, head, name, size, cf, color, shape or "Ellipsoid", SMOOTH, transparency)
	end
	local anchor
	local function bloodStreak(p0, p1, width)
		if not fresh then
			return
		end
		if not anchor then
			anchor = add("DamageAnchor", V3(0.05, 0.05, 0.05), hcf, blood, "Block", 1)
		end
		local a0 = Instance.new("Attachment")
		a0.CFrame = axisCF(p0, V3(0, -1, -0.15))
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.CFrame = axisCF(p1, V3(0, -1, 0.1))
		a1.Parent = anchor
		local b = Instance.new("Beam")
		b.Name = "Blood"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Width0 = width
		b.Width1 = width * 0.5
		b.CurveSize0 = (p1 - p0).Magnitude * 0.2
		b.CurveSize1 = (p1 - p0).Magnitude * 0.1
		b.Segments = 6
		b.FaceCamera = true
		b.LightInfluence = 1
		b.Color = ColorSequence.new(blood, Color3.fromRGB(96, 0, 6))
		b.Transparency = NumberSequence.new(0.05, 0.3)
		b.Parent = anchor
	end
	-- face parts the damage changes: restore first so a lighter state heals visually
	local faceFolder = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Face")
	local eyeV = { [-1] = n("leftEye"), [1] = n("rightEye") }
	local severe = stage >= 4
	if faceFolder then
		for _, c in ipairs(faceFolder:GetDescendants()) do
			if c:IsA("BasePart") then
				local side = c:GetAttribute("Side")
				if c.Name == "Lid" then
					c.Transparency = (side and math.clamp((eyeV[side] - 0.3) / 0.7, 0, 1) > 0) and 1 or 0
				elseif c.Name == "Lashes" then
					-- the lash line rides on its lid: hidden while the swollen lid replaces it
					local closed = side and eyeV[side] > 0.3
					c.Transparency = closed and 1 or (c:GetAttribute("BaseT") or c.Transparency)
				elseif c.Name == "Sclera" then
					local baseC = c:GetAttribute("BaseColor")
					if typeof(baseC) == "Color3" then
						local red = clamp((side and eyeV[side] or 0) * 0.5 + (severe and 0.35 or 0) + n("redness") * 0.15, 0, 0.8)
						c.Color = lerpColor(baseC, Color3.fromRGB(228, 150, 140), red)
					end
				end
			end
		end
	end
	-- swollen eyes: a puffy lid closes over the eye as swelling grows; a black eye around it
	for side = -1, 1, 2 do
		local v = eyeV[side]
		local w = 0.15 * L.eyeSize * s.X
		local h = 0.15 * L.eyeSize * L.eyeH * s.Y
		local x, y = side * L.eyeX, L.eyeYS[side]
		local closing = clamp((v - 0.3) / 0.7, 0, 1)
		if closing > 0 then
			local cover = 0.32 + 0.75 * closing
			add("SwollenLid", V3(w * (1.14 + 0.1 * closing), h * cover, (0.055 + 0.02 * closing) * s.Z),
				at(x, y + h * (0.5 - cover / 2), L.front(x) - 0.016), lerpColor(darken(skin, 0.92), bruise, v * 0.6 * fade), "Ellipsoid")
		end
		if v > 0.15 then
			local size = (0.18 + 0.12 * v) * s.X
			add("SwollenEye", V3(size, size * 0.8, (0.08 + 0.03 * v) * s.Z), at(x, y + 0.01 * s.Y, L.front(x) + 0.01), bruise, "Ellipsoid", math.clamp(0.75 - v * 0.6 * fade, 0.15, 0.85))
		end
		-- swelling under the eye on the cheekbone
		local ck = n(side == -1 and "cheekL" or "cheekR")
		if ck > 0.15 then
			local cx = side * 0.3 * s.X
			add("CheekSwell", V3((0.2 + 0.12 * ck) * s.X, (0.14 + 0.06 * ck) * s.Y, (0.1 + 0.06 * ck) * s.Z), at(cx, -0.03 * s.Y, L.front(cx) + 0.03 - 0.03 * ck),
				lerpColor(skin, bruise, 0.25 + 0.35 * ck * fade), "Ellipsoid")
		end
		-- swollen ear (the hematoma that becomes a cauliflower ear)
		local ear = n(side == -1 and "earL" or "earR")
		if ear > 0.25 then
			add("EarSwell", V3(0.08 * s.X, (0.12 + 0.08 * ear) * s.Y, (0.1 + 0.06 * ear) * s.Z), at(side * 0.54 * s.X, 0.08 * s.Y, 0.04 * s.Z), lerpColor(skin, bruise, 0.4 * fade + 0.2), "Ellipsoid")
		end
	end
	-- cuts above the eyes (the second cut opens on the other side by default)
	local cuts = { { n("cut"), tonumber(dmg.cutSide) or 1 }, { n("cut2"), tonumber(dmg.cutSide2) or -(tonumber(dmg.cutSide) or 1) } }
	for i, c in ipairs(cuts) do
		local v, side = c[1], c[2] < 0 and -1 or 1
		if v > 0.05 then
			local x = side * L.eyeX * (i == 1 and 1 or 0.7)
			local y = L.browY + (i == 1 and 0.025 or 0.05) * s.Y
			add("Cut", V3((0.1 + 0.12 * math.min(v, 1)) * s.X, 0.025 * s.Y, 0.02), at(x, y, L.front(x) - 0.02) * ANG(0, 0, math.rad(-side * 15)), Color3.fromRGB(120, 0, 0), "Block")
			if v > 0.35 then
				local p0 = surfPoint(L, x + side * 0.04, y - 0.01 * s.Y, 0.012)
				local p1 = surfPoint(L, x + side * 0.06, L.browY - (0.08 + 0.2 * math.min(v, 1)) * s.Y, 0.012)
				bloodStreak(p0, p1, 0.03)
			end
		end
	end
	-- nose
	if dmg.nose == true then
		add("NoseBruise", V3(L.noseW * 1.5, L.noseLen * 0.95, 0.05), at(0.01, (L.noseTopY + L.noseBottomY) / 2, L.front(0) - L.noseB * 0.55) * ANG(0, 0, math.rad(10)), bruise, "Ellipsoid", 0.35 + 0.3 * (1 - fade))
	end
	local bleed = n("noseBleed")
	if bleed > 0.2 then
		for side = -1, 1, 2 do
			local x = side * L.noseW * 0.28
			bloodStreak(V3(x, L.noseBottomY, L.front(0) - L.noseB * 0.6), surfPoint(L, x * 1.2, L.mouthY + (0.06 - 0.06 * bleed) * s.Y, 0.014), 0.025 + 0.01 * bleed)
		end
	end
	-- bruised face (or a red flush when only lightly marked)
	local br = n("bruise")
	if br > 0.2 then
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			add("Bruise", V3(0.22 * s.X, 0.16 * s.Y, 0.04), at(x, -0.06 * s.Y, L.front(x)), bruise, "Ellipsoid", math.clamp(0.85 - br * 0.55 * fade, 0.3, 0.88))
		end
	elseif stage >= 1 or n("redness") > 0.1 then
		local r = math.max(n("redness"), 0.3)
		for side = -1, 1, 2 do
			add("Flush", V3(0.24 * s.X, 0.16 * s.Y, 0.03 * s.Z), hcf * surfCF(L, side * 0.28 * s.X, -0.05 * s.Y, 0.003), Color3.fromRGB(200, 60, 60), "Ellipsoid", 0.92 - 0.2 * r)
		end
	end
	-- forehead lump
	local lump = n("forehead")
	if lump > 0.2 then
		local x = 0.12 * s.X * (tonumber(dmg.cutSide) or 1)
		add("Lump", V3((0.12 + 0.08 * lump) * s.X, (0.1 + 0.06 * lump) * s.Y, (0.06 + 0.06 * lump) * s.Z), hcf * surfCF(L, x, L.browY + 0.1 * s.Y, -0.01), lerpColor(skin, bruise, 0.3 * fade), "Ellipsoid")
	end
	-- split and swollen lip
	local lip = n("lip")
	if lip > 0.25 then
		add("SplitLip", V3(0.06 * s.X, 0.05 * s.Y, 0.03), at(0.05 * s.X, L.mouthY - 0.035 * s.Y, L.front(0) - 0.035), Color3.fromRGB(130, 0, 10), "Ellipsoid")
		if lip > 0.45 then
			local lipColor = lerpColor(darken(skin, 0.86), Color3.fromRGB(150, 60, 70), 0.3)
			add("SwollenLip", V3(L.mouthW * (0.9 + 0.2 * lip), (0.05 + 0.04 * lip) * s.Y, 0.07 * s.Z), at(0.02 * s.X, L.mouthY - 0.03 * s.Y, L.front(0) - 0.012), lerpColor(lipColor, bruise, 0.3 * fade), "Ellipsoid")
		end
		if lip > 0.6 then
			bloodStreak(V3(0.05 * s.X, L.mouthY - 0.05 * s.Y, L.front(0) - 0.035), surfPoint(L, 0.06 * s.X, -0.4 * s.Y, 0.014), 0.025)
		end
	end
	-- severe: blood smeared over the chin and dripping on the chest
	if severe and fresh and (n("cut") > 0.3 or bleed > 0.3 or lip > 0.5) then
		add("BloodSmear", V3(0.2 * s.X, 0.1 * s.Y, 0.04 * s.Z), hcf * surfCF(L, 0.02 * s.X, -0.36 * s.Y, 0.006), Color3.fromRGB(110, 6, 10), "Ellipsoid", 0.35)
		local torso = part(model, "UpperTorso")
		if torso then
			mk(folder, torso, "BloodChest", V3(0.18, 0.3, 0.02), torso.CFrame * CF(0.1, 0.25, -torso.Size.Z * 0.5 - 0.005), Color3.fromRGB(110, 6, 10), "Ellipsoid", SMOOTH, 0.4)
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

-- wet hair darkens and (except coils) gains a slight sheen; strands darken too
local function wetHair(model, q)
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
	local key = string.format("%.2f|%s|%.3f", q, tostring(detail), head.Size.X)
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
	local L = Head.FaceLayout(head, app.face or {})
	local s = L.s
	local hcf = head.CFrame
	local anchor = mk(folder, head, "SweatAnchor", V3(0.05, 0.05, 0.05), hcf, WHITE, "Block", SMOOTH, 1)
	-- specular highlights where a wet face catches the light (transparent parts, not Reflectance)
	local spots = {
		{ 0, L.browY + 0.08 * s.Y, 0.24, 0.1 }, { 0, L.noseTopY - L.noseLen * 0.4, 0.06, 0.12 },
		{ -0.28 * s.X, -0.02 * s.Y, 0.12, 0.07 }, { 0.28 * s.X, -0.02 * s.Y, 0.12, 0.07 }, { 0, -0.36 * s.Y, 0.12, 0.06 },
	}
	for i, sp in ipairs(spots) do
		if detail == "full" or i <= 3 then
			mk(folder, head, "Sheen", V3(sp[3] * s.X, sp[4] * s.Y, 0.02 * s.Z), hcf * surfCF(L, sp[1], sp[2], 0.004), WHITE, "Ellipsoid", SMOOTH, 0.94 - 0.18 * q)
		end
	end
	if detail ~= "full" then
		return
	end
	if q >= 0.35 then
		local rng = Random.new(((app.face and app.face.seed) or 7) + 505)
		for _ = 1, math.floor(3 + 7 * q) do
			local x = rng:NextNumber(-0.3, 0.3) * s.X
			local y = L.browY + rng:NextNumber(-0.02, 0.18) * s.Y
			local sz = rng:NextNumber(0.018, 0.03)
			local bead = mk(folder, head, "SweatBead", V3(sz, sz * 1.3, sz * 0.7), hcf * surfCF(L, x, y, 0.004), lerpColor(skinOf(app), WHITE, 0.55), "Ellipsoid", SMOOTH, 0.4)
			bead.Reflectance = 0.08
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
			p.Reflectance = r
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
	wetHair(model, q)
	faceSweat(model, app, q)
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics)
------------------------------------------------------------------------
Head.Face = faceBuild -- (model, app, opts, build)
Head.Hair = hairBuild -- (model, app, opts)
Head.Beard = beardBuild -- (model, app, opts)

return Head
