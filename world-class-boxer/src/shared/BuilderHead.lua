-- BuilderHead: everything built on the head (server side; the Creator also calls SetDamage locally).
-- * the classic head: the engine's default head is swapped once for the classic head (a Part with the Head
--   SpecialMesh) and the face is a Decal "face" on its front: the boxer's chosen classic face (look.face.key,
--   BodyAssetData.faces through BodyTiers; the engine's smile while an id is 0). FaceFX (client) swaps that
--   texture for the moods (BodyAssetData.expressions). The model attribute FaceKey names the chosen face.
-- * FaceLayout: where the classic faces draw their features on the head (the eyes, brows, mouth of
--   tools/body/faces.py), shared with the damage marks, the sweat, the grime and the beard
-- * part budget: A's share of Config.Detail partBudget; the round-1 hair (BuilderHair) and the beard use it
-- * hair: in BuilderHair (Head.Hair, SetHairHidden and ApplyHairHidden forward there and Head.Shared lends it
--   the budget and head-surface helpers below)
-- * beards: growth stages, own colour, salt & pepper with age, 10 styles, material by hair type: 3D shells on the
--   classic head around the face decal (a beard accessory's way), kept from the part-built look
-- * fight damage light .. severe: black eyes, cuts, bruises, swelling and blood as simple overlays on the head
--   (translucent marks on its surface at the classic face's features, blood as Beams), or, for the layers
--   BodyAssetData.damage uploads, full-face Decals faded by the damage; sweat (skin sheen, beads, drips, wet hair)
-- Builder.Cosmetics runs Face, Hair (BuilderHair) and Beard (in that order) and forwards FaceLayout,
-- SetDamage, SetSweat and SetHeadgear here. Level of detail: opts.detail through Config.DetailLevel.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))
local BodyTiers = require(script.Parent:WaitForChild("BodyTiers"))
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
-- the classic faces' features on the head (tools/body/faces.py draws every face on one layout: the eyes at
-- x 0.40 / 0.60, y 0.405 of the image, the mouth line at 0.555; the Decal spans the head's front face). The face
-- sliders of the old procedural face no longer move anything: face is accepted and ignored
function Head.FaceLayout(head, face)
	local s = head.Size
	-- the classic head is round seen from above: the front surface at x
	local function front(x)
		local k = clamp(x / (s.X * 0.5), -0.97, 0.97)
		return -s.Z * 0.5 * math.sqrt(1 - k * k)
	end
	-- ... and rounds back over its top and bottom edges (the Head mesh's bevel)
	local function vround(y)
		local e = (math.abs(y) / s.Y - 0.3) / 0.28
		if e <= 0 then
			return 1
		end
		e = math.min(e, 0.97)
		return math.sqrt(1 - e * e)
	end
	local eyeX, eyeY, mouthY = 0.1 * s.X, 0.095 * s.Y, -0.07 * s.Y
	local L = {
		s = s, front = front, eyeX = eyeX, eyeY = eyeY, mouthY = mouthY,
		eyeSize = 1, eyeH = 1,
		browY = eyeY + 0.1 * s.Y,
		noseLen = 0.09 * s.Y, noseW = 0.06 * s.X, noseB = 0.02 * s.Z,
	}
	L.surf = function(x, y)
		return front(x) * vround(y)
	end
	L.noseTopY = eyeY - 0.04 * s.Y
	L.noseBottomY = L.noseTopY - L.noseLen
	L.mouthW = 0.21 * s.X
	L.eyeTilt = 0
	L.eyeYS = { [-1] = eyeY, [1] = eyeY }
	L.browTiltS = { [-1] = 0, [1] = 0 }
	L.mouthTilt = 0
	L.noseDev = 0
	return L
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

-- the classic head: the engine's default head (a MeshPart; a dynamic head bakes its face into the mesh, and that
-- texture cannot be removed while the game runs) is swapped once for a plain Part of the same size with the
-- Head SpecialMesh: the classic Roblox head, which takes the face Decal. Builder keeps it at the engine's scale.
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
	local swapped = hum and pcall(function()
		hum:ReplaceBodyPartR15(Enum.BodyPartR15.Head, clean)
	end)
	if swapped and model:FindFirstChild("Head") == clean then
		return clean
	end
	clean:Destroy()
	pcall(function()
		head.TextureID = ""
	end)
	return head
end
Head.ClassicHead = classicHead

-- the chosen face's Decal on the head (and the FaceKey attribute FaceFX reads)
local function faceBuild(model, app, opts, build)
	opts = opts or {}
	app = app or {}
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	head = classicHead(model, head)
	-- an engine face, an older build's face controls / surface appearance: only the classic decal stays
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("FaceControls") or d:IsA("SurfaceAppearance") or (d:IsA("Decal") and d.Name ~= "face" and d:GetAttribute("DamageLayer") == nil) then
			d:Destroy()
		end
	end
	local key = BodyTiers.SanitizeFace(type(app.face) == "table" and app.face.key or nil)
	local decal = head:FindFirstChild("face")
	if not (decal and decal:IsA("Decal")) then
		if decal then
			decal:Destroy()
		end
		decal = Instance.new("Decal")
		decal.Name = "face"
		decal.Parent = head
	end
	decal.Face = Enum.NormalId.Front
	local tex = BodyTiers.FaceTexture(key)
	if decal.Texture ~= tex then
		decal.Texture = tex
	end
	Kit.setAttr(model, "FaceKey", key)
	head.Material = SMOOTH
	-- the (empty) Face folder carries the build's detail and seals the step's cache
	local folder = getFolder(model, "Face")
	folder:SetAttribute("Detail", (Config.DetailLevel(opts)))
	folder:SetAttribute("Extra", 0)
end

local function beardBuild(model, app, opts)
	opts = opts or {}
	app = app or {}
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local folder = getFolder(model, "Beard")
	local detail = Config.DetailLevel(opts)
	local full, low = detail == "full", detail == "low"
	-- growth stages without a chosen style: shadow -> stubble -> a short natural beard (beardStyle)
	local style, shadow, g, grown = beardStyle(app)
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
	-- the moustache sits in the gap the classic faces leave between the eyes and the mouth (the eyes end ~0.03
	-- above the centre, the smile's corners ~0.02 below it), so it never hides the face's own mouth
	local function moustache(width, drop)
		local my, mh = L.mouthY + 0.075 * s.Y, (0.03 + 0.015 * g) * s.Y
		if full and fits(2) then
			-- two halves angled down toward the mouth corners
			for side = -1, 1, 2 do
				add("Moustache", V3((width or 0.17) * s.X, mh, 0.06 * s.Z),
					at(side * 0.075 * s.X, my, L.front(side * 0.075 * s.X) - 0.025) * ANG(0, 0, L.mouthTilt + side * math.rad(-(drop or 10))))
			end
		else
			-- one centred bar (medium / low detail, or no room left)
			add("Moustache", V3(((width or 0.17) + 0.13) * s.X, mh, 0.06 * s.Z),
				at(0, my, L.front(0) - 0.025) * ANG(0, 0, L.mouthTilt))
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

-- the uploaded damage layers as Decals on the head's front (named <folder>_<layer>, attribute DamageLayer), faded
-- by BodyTiers.DamageStrengths; a layer without an upload (or at 0) has none. Returns { [layer] = true } shown
local function damageDecals(head, dmg, folderName)
	local on = {}
	local strengths = BodyTiers.DamageStrengths(dmg)
	for _, layer in ipairs(BodyTiers.DAMAGE_LAYERS) do
		local name = folderName .. "_" .. layer
		local d = head:FindFirstChild(name)
		local id = BodyTiers.DamageId(layer)
		local k = strengths[layer] or 0
		if id and k > 0.02 then
			if not (d and d:IsA("Decal")) then
				d = Instance.new("Decal")
				d.Name = name
				d.Face = Enum.NormalId.Front
				d:SetAttribute("DamageLayer", layer)
				d.Parent = head
			end
			d.Texture = "rbxassetid://" .. id
			d.Transparency = 1 - math.clamp(k, 0, 1)
			on[layer] = true
		elseif d then
			d:Destroy()
		end
	end
	return on
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
	local eyeV = { [-1] = n("leftEye"), [1] = n("rightEye") }
	local severe = stage >= 4
	-- the uploaded damage decals (BodyAssetData.damage): full-face layers faded by the damage; a layer that has
	-- one is not drawn again as a part overlay below
	local decalOn = damageDecals(head, dmg, folderName or "Damage")
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
		if v > 0.15 and not decalOn[side < 0 and "blackEyeL" or "blackEyeR"] then
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
	end
	-- cuts above the eyes (the second cut opens on the other side by default)
	local cuts = { { n("cut"), tonumber(dmg.cutSide) or 1 }, { n("cut2"), tonumber(dmg.cutSide2) or -(tonumber(dmg.cutSide) or 1) } }
	for i, c in ipairs(cuts) do
		local v, side = c[1], c[2] < 0 and -1 or 1
		if v > 0.05 and not decalOn[side < 0 and "cutL" or "cutR"] then
			local x = side * L.eyeX * (i == 1 and 1 or 0.7)
			local y = L.browY + (i == 1 and 0.025 or 0.05) * s.Y
			add("Cut", V3((0.1 + 0.12 * math.min(v, 1)) * s.X, 0.025 * s.Y, 0.02), at(x, y, L.front(x) - 0.02) * ANG(0, 0, math.rad(-side * 15)), Color3.fromRGB(120, 0, 0), "Ellipsoid")
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
	if decalOn.bruise then
		-- (the bruise decal)
	elseif br > 0.2 then
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
	if lump > 0.2 and not decalOn.swelling then
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
