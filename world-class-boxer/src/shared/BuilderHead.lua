-- BuilderHead: everything built on the head (server side; the Creator also calls SetDamage locally).
-- * procedural face on the R15 head: sculpted planes (brow ridge, cheekbones, jaw angles, nasolabial
--   folds, philtrum, chin, lip fold), layered eyes (tinted sclera, iris with limbal ring and collarette,
--   pupil, catchlight, lids with thickness, a wet lower lid and a crease on hooded / ageing lids,
--   under-eye shadow), full lips with a vermilion border, teeth + mouth interior (mouthguard at teeth
--   depth), ears with a helix rim, 6 brow styles, heterochromia, asymmetry, undertone
-- * boxer wear and skin: cauliflower ear, bent nose, permanent fight scars (app.battle), a stitched
--   surgical repair scar, acne (active spots when young, pitted scars on adult skin), wrinkles by age,
--   pore texture (an honest approximation: material + sparse dots), temple/forehead veins, face fat
--   (full cheeks, jowls) and weight-cut hollows, grime (own folder, refreshed by SetSweat)
-- * part budget: A's share of Config.Detail partBudget (+60 / +10 / 0 over the old face, hair and beard);
--   optional face details and hair decorations are drawn in priority order while it lasts
-- * face rig the client animates (Motor6D "FaceJoint", tag FaceRig, attribute Role): brows, lids,
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
	mk(folder, head, "Grime", V3(0.26 * s.X, 0.1 * s.Y, 0.03 * s.Z), hcf * surfCF(L, -0.1 * s.X, L.browY + 0.08 * s.Y, 0.003), dirt, "Ellipsoid", SMOOTH, 0.88 - 0.22 * g)
	if g > 0.5 then
		mk(folder, head, "Grime", V3(0.16 * s.X, 0.12 * s.Y, 0.03 * s.Z), hcf * surfCF(L, 0.3 * s.X, -0.15 * s.Y, 0.003), dirt, "Ellipsoid", SMOOTH, 0.9 - 0.22 * g)
	end
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

	-- ears: shell + helix rim; cauliflower lumps fill the upper rim
	local earS = 1 + 0.2 * (face.earSize or 0)
	for side = -1, 1, 2 do
		local ecf = at(side * 0.5 * s.X, 0.02 * s.Y, 0.04 * s.Z) * ANG(0, side * rad(6 + 10 * cauli), 0)
		add("Ear", V3(0.08 * s.X, 0.25 * s.Y * earS, 0.17 * s.Z * earS), ecf, skin, "Ellipsoid")
		if full then
			add("EarHelix", V3(0.045 * s.X, 0.26 * s.Y * earS, 0.06 * s.Z * earS), ecf * CF(side * 0.03 * s.X, 0.015 * s.Y, 0.055 * s.Z * earS), darken(skin, 0.96), "Ellipsoid")
		end
		if cauli > 0.15 and not low then
			local lumps = full and math.min(2, 1 + math.floor(cauli * 2)) or 1
			side2("cauli", "wear", lumps, function()
				for i = 1, lumps do
					local sz = (0.05 + 0.045 * cauli) * s.X * (1 - 0.15 * (i - 1))
					add("Cauliflower", V3(sz * 0.9, sz, sz), ecf * CF(side * 0.03 * s.X, (0.08 - 0.06 * (i - 1)) * s.Y * earS, (0.02 + 0.02 * i) * s.Z),
						lerpColor(skin, Color3.fromRGB(150, 100, 100), 0.12 + 0.1 * cauli), "Ellipsoid")
				end
			end)
		end
	end
	-- jaw (square / wide jaws stand out from the round head) and the jaw angles that make a jawline
	if jawW > 0.1 then
		local w = (0.82 + 0.2 * jawW) * s.X
		add("Jaw", V3(w, 0.3 * s.Y, 0.86 * s.Z), at(0, -0.36 * s.Y, 0.02 * s.Z), skin, jawDef > 0.55 and "Block" or "Ellipsoid")
	end
	if full then
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
	if (face.chinCleft or 0) > 0.15 and full then
		opt("skin", 1, function()
			local c = face.chinCleft
			add("ChinCleft", V3(0.012 * s.X, (0.05 + 0.05 * c) * s.Y, 0.03 * s.Z), at(0, chinY + 0.005 * s.Y, L.front(0) * 0.9 - 0.062 * s.Z), darken(skin, 0.8), "Ellipsoid", SMOOTH, 0.75 - 0.35 * c)
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
	-- cheekbones and cheeks (lean faces show more bone); below full detail full cheeks replace the bone
	local fullCheeks = cheekFat > 0.05 and hollow <= 0.1
	if cheek > -0.5 and (full or not fullCheeks) then
		local bone = 1 + 0.25 * hollow
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			add("Cheekbone", V3(0.22 * s.X * bone, (0.1 + 0.04 * cheek) * s.Y, 0.1 * s.Z),
				at(x, -0.02 * s.Y, L.front(x) + 0.035 - 0.025 * cheek - 0.008 * hollow), skin, "Ellipsoid")
		end
	end
	if fullCheeks then
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
	if full then
		for side = -1, 1, 2 do
			local x = side * 0.16 * s.X
			add("BrowRidge", V3((0.3 + 0.05 * ridge) * s.X, (0.05 + 0.03 * ridge) * s.Y, (0.035 + 0.025 * ridge) * s.Z),
				on(x, L.browY + 0.012 * s.Y, -0.004 + 0.006 * ridge), skin, "Ellipsoid")
		end
	elseif detail == "medium" and math.max(browRidge, (face.forehead or 0) * 0.6) > 0.2 then
		-- one bar across both brows (a heavy forehead / heart face reads from a distance)
		add("BrowRidge", V3((0.62 + 0.12 * ridge) * s.X, 0.06 * s.Y, 0.06 * s.Z), on(0, L.browY + 0.012 * s.Y, 0.002), skin, "Ellipsoid")
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
	local underEye = full and (wr > 0.3 or heavy > 0.6)
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
			-- the lid crease shows on hooded and ageing lids
			if heavy > 0.3 or wr > 0.4 then
				side2("crease", "skin", 1, function()
					add("Crease", V3(w * 0.98, 0.008 * s.Y, 0.02 * s.Z), e(0, h * 0.42 + lidH * 0.52, -0.006), darken(skin, 0.74), "Ellipsoid", SMOOTH, 0.45 + 0.45 * heavy)
				end)
			end
			-- lower lid with the wet rim (tear line) in its colour: one part, rigged for squints
			local lower = rig("LowerLid" .. roleSide, side, "LowerLid", V3(w * 1.02, h * 0.24, 0.04 * s.Z), e(0, -h * 0.5, -0.01),
				lerpColor(lerpColor(lidColor, skin, 0.5), Color3.fromRGB(226, 160, 158), 0.18), "Ellipsoid")
			lower:SetAttribute("Side", side)
		end
		if not low then
			-- the client shows this for a blink (never the Lid, which SetDamage hides)
			local blink = add("BlinkLid", V3(w * 1.12, h * 1.05, 0.05 * s.Z), e(0, 0, -0.03), lerpColor(lidColor, skin, 0.4), "Ellipsoid", SMOOTH, 1)
			blink:SetAttribute("Side", side)
		end
		if underEye then
			-- under-eye shadow (also the socket depth the eye loses without a socket part)
			side2("underEye", "skin", 1, function()
				add("UnderEye", V3(w * 1.1, h * 0.5, 0.03 * s.Z), e(0, -h * 0.9, 0.004), darken(skin, 0.82), "Ellipsoid", SMOOTH, 0.82 - 0.3 * wr)
			end)
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
	-- at full the tip also spans the alar wings (one wide, flatter part instead of three)
	add("NoseTip", V3(nW * (full and 1.12 or 0.9), nW * 0.7, nB * (full and 0.66 or 0.7)), at(dev, L.noseBottomY + nW * 0.25, L.front(0) - nB * 0.75), noseCol, "Ellipsoid")
	if full then
		for side = -1, 1, 2 do
			add("Nostril", V3(0.03 * s.X, 0.02 * s.Y, 0.03 * s.Z), at(dev + side * nW * 0.28, L.noseBottomY + 0.006, L.front(0) - nB * 0.6), darken(skin, 0.45), "Ellipsoid")
		end
	end
	if noseBreak > 0.3 and full then
		opt("wear", 1, function()
			add("NoseBump", V3(nW * 0.55, L.noseLen * 0.22, nB * 0.5), at(dev * 0.3, L.noseTopY - L.noseLen * 0.3, L.front(0) - nB * 0.62), noseCol, "Ellipsoid")
		end)
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
			opt("skin", 1, function()
				add("Philtrum", V3(0.055 * s.X, py0 - py1, 0.02 * s.Z), at(dev * 0.5, (py0 + py1) / 2, mz - 0.004), darken(skin, 0.88), "Ellipsoid", SMOOTH, 0.6)
			end)
		end
		opt("skin", 1, function()
			line("LipFold", -mw * 0.28, L.mouthY - lowerH * 1.2 - gap, mw * 0.28, L.mouthY - lowerH * 1.2 - gap, 0.012 * s.Y, darken(skin, 0.8), 0.6, 0.002)
		end)
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
	-- acne: inflamed spots on a young face; from the mid twenties (or with heavy acne) what is left are
	-- pitted scars, slightly darker shallow dents rather than red bumps. Same rng draws either way. An
	-- unknown age (Creator preview) keeps the spots the player is choosing.
	local acneScars = (tonumber(opts.age) or 0) >= 25 or (face.acne or 0) > 0.6
	for i = 1, math.floor((face.acne or 0) * 14) do
		if acneScars and i % 3 ~= 0 then
			spot("AcneScar", V3(0.03, 0.026, 0.008), darken(skin, 0.86), 0.05, 0.36, -0.32, 0.32, 0.55, low)
		else
			spot("Acne", V3(0.024, 0.024, 0.012), lerpColor(skin, Color3.fromRGB(190, 60, 60), 0.5), 0.05, 0.36, -0.32, 0.32, nil, low)
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
			line("SurgicalScar", x0, y0, x1, y1, 0.011 * s.X, scarColor, 0.05, 0.004)
			local dx, dy = x1 - x0, y1 - y0
			local len = math.sqrt(dx * dx + dy * dy)
			local nx, ny = -dy / len * 0.016 * s.Y, dx / len * 0.016 * s.Y
			for k = 1, 3 do
				local px, py = x0 + dx * k / 4, y0 + dy * k / 4
				line("Suture", px - nx, py - ny, px + nx, py + ny, 0.006 * s.X, lerpColor(scarColor, WHITE, 0.15), 0.15, 0.005)
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
				add("Pore", V3(0.014, 0.014, 0.008), on(x, y, 0.002), darken(skin, 0.8), "Ellipsoid", SMOOTH, 0.6)
			end
		end)
	end
	-- a living flush on the cheeks (reads on light and mid skin tones)
	if full and skinL > 0.35 and wr < 0.3 then
		opt("skin", 2, function()
			for side = -1, 1, 2 do
				add("Blush", V3(0.2 * s.X, 0.12 * s.Y, 0.03 * s.Z), on(side * 0.27 * s.X, -0.06 * s.Y, 0.002), under, "Ellipsoid", SMOOTH, 0.9 - (female and 0.04 or 0))
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
			line("TempleVein", vs * 0.36 * s.X, L.browY + 0.02 * s.Y, vs * 0.33 * s.X, L.browY + 0.14 * s.Y, 0.014 * s.X, veinColor, 1, 0.006),
			line("ForeheadVein", -vs * 0.07 * s.X, L.browY + 0.05 * s.Y, -vs * 0.1 * s.X, L.browY + 0.19 * s.Y, 0.014 * s.X, veinColor, 1, 0.006),
		}
		for _, v in ipairs(veins) do
			v:SetAttribute("BaseTransparency", vis)
		end
	end
	-- mouthguard sits at teeth depth, showing between the parted lips. Head.SetDamage tints it after a
	-- split lip (from BaseColor), so in-fight damage shows without a face rebuild.
	if guard then
		local mg = Looks.Color(app.attire and app.attire.mouthguard, Color3.fromRGB(40, 80, 200))
		local mgPart = add("Mouthguard", V3(mw * 0.92, (0.05 + 0.01 * lt) * s.Y, 0.03 * s.Z), m(0, -gap * 0.5, -0.02), mg, "Ellipsoid")
		mgPart:SetAttribute("BaseColor", mg)
	end

	-- optional details, in priority order, while the budget lasts
	for _, q in ipairs(queued) do
		if spend(q[1], q[2]) then
			q[3]()
		end
	end
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
		add("Stubble", V3(s.X * 1.06, s.Y * 0.46, s.Z * 1.0), at(0, -0.3 * s.Y, -0.07 * s.Z), color, "Ellipsoid", SMOOTH, t)
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
		moustache()
		wantSideburns, wantNeck = true, true
	else -- Full Beard
		add("Beard", V3(s.X * 1.1, s.Y * (0.58 + 0.16 * g), s.Z * 1.06), at(0, -0.36 * s.Y, -0.06 * s.Z))
		if not low then
			add("BeardChin", V3(0.5 * s.X, (0.2 + 0.1 * g) * s.Y, 0.3 * s.Z), at(0, (-0.55 - 0.05 * g) * s.Y, -0.3 * s.Z))
		end
		moustache(0.18, 8)
		wantSideburns, wantNeck = true, true
	end
	-- sideburns joining the beard to the hair, then the neck line (full detail only)
	if wantSideburns and full and fits(2) then
		for side = -1, 1, 2 do
			add("Sideburn", V3(0.05 * s.X, 0.26 * s.Y, 0.14 * s.Z), at(side * 0.5 * s.X, -0.02 * s.Y, -0.06 * s.Z), color, "Ellipsoid", mat)
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
	-- the chin strap: from the foot of each cheek pad along the underside of the jaw to a cup under the
	-- chin (a strap straight across under the head would hang in front of the neck like a choker)
	local strapC = darken(color, 0.6)
	for side = -1, 1, 2 do
		local a = hcf * V3(side * 0.43 * s.X, -0.32 * s.Y, -0.02 * s.Z)
		local b = hcf * V3(side * 0.08 * s.X, -0.46 * s.Y, -0.29 * s.Z)
		local mid = (a + b) * 0.5
		local out = mid - hcf * V3(0, -0.2 * s.Y, -0.1 * s.Z)
		mk(folder, head, "HGStrap", V3(0.07 * s.Y, 0.025 * s.Y, (b - a).Magnitude), CFrame.lookAt(mid, b, out.Unit), strapC, "Block")
	end
	mk(folder, head, "HGChin", V3(0.24 * s.X, 0.09 * s.Y, 0.16 * s.Z), hcf * CF(0, -0.46 * s.Y, -0.31 * s.Z), strapC, "Ellipsoid", mat)
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
				elseif c.Name == "Mouthguard" then
					-- bloodied after a split lip; SetDamage(model, app, {}) cleans it again
					local baseC = c:GetAttribute("BaseColor")
					if typeof(baseC) == "Color3" then
						c.Color = n("lip") > 0.6 and lerpColor(baseC, Color3.fromRGB(140, 10, 16), 0.3) or baseC
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
	-- the face sliders move the brow / nose the sheen follows: they are part of the key too
	local key = string.format("%.2f|%s|%.3f|%.3f|%.3f", q, tostring(detail), head.Size.X, L.browY, L.noseTopY)
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
