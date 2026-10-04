-- BuilderHead: everything built on the head (server side), split out of Builder.
-- * procedural face (6 shapes, feature sliders, eyes, skin details, mouthguard) on the R15 head
-- * 24 hairstyles x 5 hair types, highlights/dye, growth; long styles get sway joints
-- * beards: stubble grows in, goatee, moustache, chin strap, boxed and full beards
-- * fight damage: swollen eyes, cuts, bloody nose, bruises, split lip; sweat shine; sparring headgear
-- Builder.Cosmetics runs Face, Hair and Beard (in that order) and forwards FaceLayout, SetDamage,
-- SetSweat and SetHeadgear to this module.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))

local Head = {}

local V3, CF, ANG, SMOOTH = Kit.V3, Kit.CF, Kit.ANG, Kit.SMOOTH
local lerpColor, darken = Kit.lerpColor, Kit.darken
local mk, getFolder, part = Kit.mk, Kit.getFolder, Kit.part

------------------------------------------------------------------------
-- Face
------------------------------------------------------------------------
-- returns head-local positions for face features (shared with damage visuals)
function Head.FaceLayout(head, face)
	local s = head.Size
	local function front(x)
		local k = math.clamp(x / (s.X * 0.5), -0.97, 0.97)
		return -s.Z * 0.5 * math.sqrt(1 - k * k)
	end
	local eyeX = (0.19 + 0.035 * (face.eyeDist or 0)) * s.X
	local eyeY = 0.1 * s.Y
	local mouthY = -0.21 * s.Y
	local L = {
		s = s, front = front, eyeX = eyeX, eyeY = eyeY, mouthY = mouthY,
		eyeSize = 1 + 0.25 * (face.eyeSize or 0),
		eyeH = 1 - 0.45 * (face.eyeShape or 0.5),
		browY = eyeY + (0.13 + 0.025 * (face.forehead or 0)) * s.Y,
		noseLen = (0.2 + 0.07 * (face.noseLength or 0)) * s.Y,
		noseW = (0.11 + 0.05 * (face.noseWidth or 0)) * s.X,
		noseB = (0.085 + 0.05 * (face.noseBridge or 0)) * s.Z,
	}
	L.noseTopY = eyeY - 0.02 * s.Y
	L.noseBottomY = L.noseTopY - L.noseLen
	return L
end

local function faceBuild(model, app, opts)
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
	local folder = getFolder(model, "Face")
	local L = Head.FaceLayout(head, face)
	local s = L.s
	local hcf = head.CFrame
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local hairColor = Looks.Color(app.hair and app.hair.color, Color3.fromRGB(30, 22, 18))
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	-- skin finish
	head.Material = (face.smooth or 0.5) >= 0.5 and SMOOTH or Enum.Material.Plastic
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

	-- ears
	for side = -1, 1, 2 do
		mk(folder, head, "Ear", V3(0.08 * s.X, 0.25 * s.Y, 0.17 * s.Z), at(side * 0.5 * s.X, 0.02 * s.Y, 0.04 * s.Z), skin, "Ellipsoid")
	end
	-- jaw (square / wide jaws stand out from the round head)
	if jawW > 0.1 then
		local w = (0.82 + 0.2 * jawW) * s.X
		mk(folder, head, "Jaw", V3(w, 0.3 * s.Y, 0.86 * s.Z), at(0, -0.36 * s.Y, 0.02 * s.Z), skin, jawDef > 0.55 and "Block" or "Ellipsoid")
	end
	-- chin
	-- sits on the front of the lower face (lower down it hangs under the head like a second chin)
	local chinSize = 0.2 + 0.07 * chin
	mk(folder, head, "Chin", V3(chinSize * (1 - chinNarrow) * s.X, (0.13 + 0.04 * chin + chinDrop) * s.Y, 0.14 * s.Z),
		at(0, (-0.385 - 0.025 * chin - chinDrop * 0.5) * s.Y, L.front(0) * 0.9), skin, "Ellipsoid")
	if chinDrop > 0 then -- long face: extend the lower face
		mk(folder, head, "LowerFace", V3(0.7 * s.X, chinDrop * 2 * s.Y, 0.7 * s.Z), at(0, -0.5 * s.Y, 0), skin, "Ellipsoid")
	end
	-- cheekbones and cheeks
	if cheek > -0.5 then
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			mk(folder, head, "Cheekbone", V3(0.22 * s.X, (0.1 + 0.04 * cheek) * s.Y, 0.1 * s.Z),
				at(x, -0.02 * s.Y, L.front(x) + 0.035 - 0.025 * cheek), skin, "Ellipsoid")
		end
	end
	if cheekFat > 0 then
		for side = -1, 1, 2 do
			local x = side * 0.33 * s.X
			mk(folder, head, "Cheek", V3(0.26 * s.X, 0.24 * s.Y, 0.16 * s.Z), at(x, -0.2 * s.Y, L.front(x) + 0.05), skin, "Ellipsoid")
		end
	end
	-- brow ridge (heavy forehead / heart shape)
	local ridge = math.max(browRidge, (face.forehead or 0) * 0.6)
	if ridge > 0.2 then
		mk(folder, head, "BrowRidge", V3((0.62 + 0.12 * ridge) * s.X, 0.06 * s.Y, 0.06 * s.Z), at(0, L.browY + 0.02 * s.Y, L.front(0) + 0.015), skin, "Ellipsoid")
	end

	-- eyes
	local eyeColor = Looks.Color(Looks.EyeColors[face.eyeColor or 2])
	local lidColor = darken(skin, 0.92)
	for side = -1, 1, 2 do
		local x = side * L.eyeX
		local z = L.front(x)
		local w = 0.15 * L.eyeSize * s.X
		local h = 0.15 * L.eyeSize * L.eyeH * s.Y
		mk(folder, head, "Sclera", V3(w, h, 0.05 * s.Z), at(x, L.eyeY, z - 0.004), Color3.fromRGB(245, 244, 238), "Ellipsoid")
		local iris = 0.085 * L.eyeSize * s.X
		mk(folder, head, "Iris", V3(iris, math.min(iris, h * 0.95), 0.03 * s.Z), at(x, L.eyeY, z - 0.022), eyeColor, "Ellipsoid")
		mk(folder, head, "Pupil", V3(iris * 0.48, math.min(iris * 0.48, h * 0.6), 0.02 * s.Z), at(x, L.eyeY, z - 0.032), Color3.fromRGB(10, 10, 12), "Ellipsoid")
		mk(folder, head, "Glint", V3(iris * 0.18, iris * 0.18, 0.01), at(x + iris * 0.15, L.eyeY + iris * 0.15, z - 0.04), Color3.new(1, 1, 1), "Ellipsoid")
		-- upper lid: shapes the eye; damage swelling lowers it
		local lid = mk(folder, head, "Lid", V3(w * 1.08, h * 0.32, 0.045 * s.Z), at(x, L.eyeY + h * 0.42, z - 0.012), lidColor, "Ellipsoid")
		lid:SetAttribute("Side", side)
		if (face.lashes or 0) > 0.15 then
			mk(folder, head, "Lashes", V3(w * 1.05, 0.014 * s.Y, 0.03 * s.Z),
				at(x, L.eyeY + h * 0.52, z - 0.03) * ANG(0, 0, math.rad(side * -6)), Color3.fromRGB(15, 12, 10), "Block", SMOOTH, 1 - math.clamp(face.lashes, 0, 1) * 0.9)
		end
		-- eyebrow
		local bt = (0.028 + 0.02 * ((face.browThick or 0) + 1)) * s.Y
		mk(folder, head, "Brow", V3(0.21 * s.X, bt, 0.035 * s.Z), at(x, L.browY, L.front(x) - 0.012) * ANG(0, 0, math.rad(side * -7)), darken(hairColor, 0.9), "Block", Enum.Material.Fabric)
	end

	-- nose
	local nose = mk(folder, head, "Nose", V3(L.noseW, L.noseLen, L.noseB),
		at(0, (L.noseTopY + L.noseBottomY) / 2, L.front(0) - L.noseB / 2 + 0.012), darken(skin, 0.97), "Wedge")
	nose:SetAttribute("Base", true)
	mk(folder, head, "NoseTip", V3(L.noseW * 0.9, L.noseW * 0.7, L.noseB * 0.7), at(0, L.noseBottomY + L.noseW * 0.25, L.front(0) - L.noseB * 0.75), darken(skin, 0.97), "Ellipsoid")
	for side = -1, 1, 2 do
		mk(folder, head, "Nostril", V3(0.03 * s.X, 0.02 * s.Y, 0.03 * s.Z), at(side * L.noseW * 0.28, L.noseBottomY + 0.006, L.front(0) - L.noseB * 0.6), darken(skin, 0.45), "Ellipsoid")
	end

	-- mouth
	local lipColor = lerpColor(skin, Color3.fromRGB(165, 72, 78), 0.38)
	local lt = face.lips or 0
	local upperH = (0.034 + 0.018 * lt) * s.Y
	local lowerH = (0.042 + 0.024 * lt) * s.Y
	mk(folder, head, "UpperLip", V3((0.26 + 0.02 * lt) * s.X, upperH, 0.05 * s.Z), at(0, L.mouthY + upperH * 0.55, L.front(0) - 0.006), lipColor, "Ellipsoid")
	mk(folder, head, "LowerLip", V3((0.24 + 0.02 * lt) * s.X, lowerH, 0.055 * s.Z), at(0, L.mouthY - lowerH * 0.5, L.front(0) - 0.004), lipColor, "Ellipsoid")
	mk(folder, head, "MouthLine", V3(0.22 * s.X, 0.008 * s.Y, 0.03 * s.Z), at(0, L.mouthY, L.front(0) - 0.022), darken(lipColor, 0.45), "Block")

	-- skin details (deterministic from the face seed)
	local rng = Random.new(face.seed or 7)
	local function spot(name, size, color, xMin, xMax, yMin, yMax, transparency)
		local x = rng:NextNumber(xMin, xMax) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(yMin, yMax) * s.Y
		return mk(folder, head, name, size, at(x, y, L.front(x) - 0.004), color, "Ellipsoid", SMOOTH, transparency)
	end
	local freck = math.floor((face.freckles or 0) * 26)
	for _ = 1, freck do
		local sz = rng:NextNumber(0.018, 0.03)
		spot("Freckle", V3(sz, sz, 0.01), darken(skin, 0.72), 0.06, 0.34, -0.1, 0.06, 0.25)
	end
	for _ = 1, math.floor(face.moles or 0) do
		spot("Mole", V3(0.035, 0.035, 0.015), darken(skin, 0.35), 0.1, 0.36, -0.32, 0.25)
	end
	for _ = 1, math.floor(face.scars or 0) do
		local x = rng:NextNumber(0.08, 0.32) * s.X * (rng:NextNumber() < 0.5 and -1 or 1)
		local y = rng:NextNumber(-0.12, 0.3) * s.Y
		mk(folder, head, "Scar", V3(0.016, rng:NextNumber(0.1, 0.2) * s.Y, 0.012),
			at(x, y, L.front(x) - 0.006) * ANG(0, 0, math.rad(rng:NextNumber(-40, 40))), lerpColor(skin, Color3.fromRGB(235, 190, 190), 0.55))
	end
	for _ = 1, math.floor((face.acne or 0) * 14) do
		spot("Acne", V3(0.024, 0.024, 0.012), lerpColor(skin, Color3.fromRGB(190, 60, 60), 0.5), 0.05, 0.36, -0.32, 0.32)
	end
	if (face.marks or 0) > 0.05 then
		local sz = 0.08 + 0.14 * face.marks
		spot("Birthmark", V3(sz, sz * 0.7, 0.01), lerpColor(skin, Color3.fromRGB(150, 70, 70), 0.35), 0.15, 0.32, -0.2, 0.25, 0.35)
	end
	if opts and opts.mouthguard then
		local mg = Looks.Color(app.attire and app.attire.mouthguard, Color3.fromRGB(40, 80, 200))
		mk(folder, head, "Mouthguard", V3(0.25 * s.X, 0.07 * s.Y, 0.05 * s.Z), at(0, L.mouthY - 0.005, L.front(0) - 0.03), mg, "Ellipsoid")
	end
end

------------------------------------------------------------------------
-- Hair
------------------------------------------------------------------------
local SHORT = { ["Buzz Cut"] = 0.035, ["Crew Cut"] = 0.06, Fade = 0.08, ["Low Fade"] = 0.08, ["Mid Fade"] = 0.08, ["High Fade"] = 0.09, ["Caesar Cut"] = 0.06, ["Modern Athlete"] = 0.08 }

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
	if htype == "Kinky" or htype == "Coiled" then
		return Enum.Material.Sand
	elseif htype == "Curly" then
		return Enum.Material.Fabric
	end
	return Enum.Material.SmoothPlastic
end

-- a swinging chain of segments (dreads, braids, long hair, ponytail)
local function chain(folder, head, startLocal, dir, segs, segLen, width, depth, colorFn, idx, htype, beads)
	local parent = head
	local jointWorld = head.CFrame * CF(startLocal)
	local look = head.CFrame:VectorToWorldSpace((dir.Magnitude > 0.01) and dir.Unit or V3(0, -1, 0))
	local mat = hairMaterial(htype)
	for i = 1, segs do
		local t = i / segs
		local color = colorFn(idx, t, startLocal.X)
		-- frame whose -Y axis points along the hanging direction
		local orient = CFrame.lookAt(jointWorld.Position, jointWorld.Position + look) * ANG(math.rad(90), 0, 0)
		local segCF = orient * CF(0, -segLen / 2, 0)
		local p
		local w = width * (1 - 0.18 * t)
		if htype == "Curly" or htype == "Coiled" or htype == "Kinky" or beads then
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
		m.Parent = p
		CollectionService:AddTag(m, "HairSway")
		parent = p
		jointWorld = orient * CF(0, -segLen, 0)
		look = (look + V3(0, -0.6, 0)).Unit -- gravity pulls lower segments down
	end
end

local function bumps(folder, head, count, radius, yMin, colorFn, htype, seed, s)
	local rng = Random.new(seed)
	local mat = hairMaterial(htype)
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
		mk(folder, head, "Curl", V3(r, r, r), head.CFrame * CF(x, y, z), colorFn(i, yN, x), "Ball", mat)
	end
end

local function hairBuild(model, app)
	-- BALD MODE: every boxer (players, AI boxers, gym NPCs) is bald.
	-- Delete this block to bring hair back.
	do
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
	if style == "Bald" then
		return
	end
	local s = head.Size
	local hcf = head.CFrame
	local htype = hair.type or "Straight"
	local colorFn = hairPalette(hair)
	local base = colorFn(1, 0, 0)
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local L = math.clamp((hair.length or 0.5) + (hair.growth or 0) * 0.6, 0, 1.5)
	local density = hair.density or 0.7
	local thick = hair.thickness or 0.5
	local mat = hairMaterial(htype)
	local fore = (app.face and app.face.forehead or 0)
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end

	-- snug hair shell: covers the crown, sides and back with the hairline above the forehead
	local function cap(t, backDrop)
		local lift = 0.03 * fore
		mk(folder, head, "HairCap", V3(s.X * (1.04 + t * 0.7), s.Y * (0.9 + t * 1.2), s.Z * (0.98 + t * 0.7)), at(0, (0.16 + lift) * s.Y, 0.12 * s.Z), base, "Ellipsoid", mat)
		if backDrop and backDrop > 0 then
			mk(folder, head, "HairBack", V3(s.X * 1.0, s.Y * (0.5 + backDrop), s.Z * 0.62), at(0, (-0.02 - backDrop * 0.35) * s.Y, 0.24 * s.Z), base, "Ellipsoid", mat)
		end
	end
	local function fadeColor(k)
		return lerpColor(base, skin, k)
	end
	-- short top with faded sides; level 0 = low fade .. 1 = high fade
	local function fadeCut(t, level, k)
		local lift = 0.03 * fore
		mk(folder, head, "HairTop", V3(s.X * (0.98 + t), s.Y * (0.66 + t - level * 0.1), s.Z * (0.96 + t)), at(0, (0.24 + level * 0.06 + lift) * s.Y, 0.1 * s.Z), base, "Ellipsoid", mat)
		mk(folder, head, "FadeSides", V3(s.X * 1.03, s.Y * (0.62 - level * 0.12), s.Z * 0.92), at(0, (0.06 + level * 0.05) * s.Y, 0.16 * s.Z), fadeColor(k), "Ellipsoid", SMOOTH)
	end
	local function texture(count, radius)
		if htype == "Curly" or htype == "Kinky" or htype == "Coiled" then
			local r = radius * (htype == "Curly" and 1.2 or (htype == "Kinky" and 0.9 or 0.75))
			bumps(folder, head, math.floor(count * (0.5 + density)), r * s.X * (0.8 + 0.4 * thick), 0.25, colorFn, htype, (app.face and app.face.seed or 7) + 3, s)
		elseif htype == "Wavy" then
			for i = 1, 4 do
				mk(folder, head, "Wave", V3(s.X * 0.9, 0.025 * s.Y, 0.12 * s.Z), at(0, (0.3 + i * 0.045) * s.Y, (-0.35 + i * 0.16) * s.Z) * ANG(math.rad(-20 + i * 10), 0, 0),
					darken(base, 0.85), "Ellipsoid", mat)
			end
		end
	end

	if SHORT[style] then
		local t = SHORT[style] + L * 0.05
		if style == "Fade" or style == "Mid Fade" then
			fadeCut(t, 0.5, 0.45)
		elseif style == "Low Fade" then
			fadeCut(t, 0, 0.3)
		elseif style == "High Fade" then
			fadeCut(t, 1, 0.65)
		elseif style == "Buzz Cut" then
			cap(t)
			for _, p in ipairs(folder:GetChildren()) do
				p.Transparency = 0.3
			end
		elseif style == "Caesar Cut" then
			cap(t)
			-- short, straight-cut fringe brushed forward at the hairline
			mk(folder, head, "Fringe", V3(s.X * 0.62, 0.05 * s.Y, 0.12 * s.Z), at(0, 0.41 * s.Y, -0.43 * s.Z), base, "Ellipsoid", mat)
		elseif style == "Modern Athlete" then
			fadeCut(t, 0.7, 0.55)
			for i = 1, 7 do
				local x = (i - 4) * 0.12 * s.X
				mk(folder, head, "Texture", V3(0.13 * s.X, (0.09 + L * 0.06) * s.Y, 0.5 * s.Z), at(x, 0.55 * s.Y, -0.05 * s.Z) * ANG(math.rad(-10), 0, math.rad((i % 2 == 0) and 6 or -6)),
					colorFn(i, 0.2, x), "Ellipsoid", mat)
			end
		else -- Crew Cut
			cap(t)
			mk(folder, head, "CrewTop", V3(s.X * 0.8, (0.12 + L * 0.06) * s.Y, s.Z * 0.6), at(0, 0.55 * s.Y, -0.12 * s.Z), base, "Ellipsoid", mat)
		end
		texture(18, 0.08)
	elseif style == "Afro" then
		-- a big round crown that sits above and behind the hairline, leaving the face clear
		local size = 1.25 + 0.45 * L
		local htex = htype == "Straight" and "Kinky" or htype
		local hm = hairMaterial(htex)
		local hx, hy, hz = 0.5 * size * s.X, 0.425 * size * s.Y, 0.475 * size * s.Z
		local cy = 0.3 * s.Y + 0.4 * hy -- the front edge meets the hairline at 0.3 of the head height
		local cz = -0.48 * s.Z + 0.9165 * hz
		mk(folder, head, "Afro", V3(hx * 2, hy * 2, hz * 2), at(0, cy, cz), base, "Ellipsoid", hm)
		cap(0.06)
		local rng = Random.new((app.face and app.face.seed or 7) + 11)
		for i = 1, math.floor(34 * (0.5 + density)) do
			local u = rng:NextNumber(-0.45, 1)
			local a = rng:NextNumber(0, math.pi * 2)
			local ring = math.sqrt(1 - u * u)
			local px, py, pz = math.cos(a) * ring * hx * 0.96, cy + u * hy * 0.96, cz + math.sin(a) * ring * hz * 0.96
			if not (pz < -0.2 * s.Z and py < 0.34 * s.Y) then
				local r = (0.15 + 0.05 * thick) * s.X * rng:NextNumber(0.8, 1.25)
				mk(folder, head, "Curl", V3(r, r, r), at(px, py, pz), colorFn(i, (u + 1) / 2, px), "Ball", hm)
			end
		end
	elseif style == "High Top" then
		local hgt = 0.5 + 0.55 * L
		mk(folder, head, "HighTop", V3(s.X * 0.92, s.Y * hgt, s.Z * 0.92), at(0, (0.45 + hgt / 2) * s.Y, 0.03 * s.Z), base, "Block", hairMaterial(htype == "Straight" and "Kinky" or htype))
		mk(folder, head, "FadeSides", V3(s.X * 1.02, s.Y * 0.5, s.Z * 1.02), at(0, 0.2 * s.Y, 0.08 * s.Z), lerpColor(base, skin, 0.5), "Ellipsoid", SMOOTH, 0.2)
	elseif style == "Mohawk" then
		mk(folder, head, "ShavedSides", V3(s.X * 1.02, s.Y * 0.55, s.Z * 1.03), at(0, 0.28 * s.Y, 0.05 * s.Z), lerpColor(base, skin, 0.75), "Ellipsoid", SMOOTH, 0.35)
		local n = 6
		for i = 1, n do
			local z = (-0.45 + (i - 1) * 0.18) * s.Z
			local hgt = (0.18 + 0.4 * L) * s.Y * (1 - math.abs(i - n / 2) * 0.06)
			mk(folder, head, "Spike", V3(0.14 * s.X, hgt, 0.2 * s.Z), at(0, 0.5 * s.Y + hgt * 0.4, z), colorFn(i, i / n, 0), "Block", mat)
		end
	elseif style == "Slick Back" then
		cap(0.05 + L * 0.04, 0.1)
		for _, p in ipairs(folder:GetChildren()) do
			-- wet-look gel: a soft sheen (strong reflectance mirrors the sky and turns the hair blue)
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0.05
		end
		for i = 1, 4 do
			local x = (i - 2.5) * 0.18 * s.X
			mk(folder, head, "Groove", V3(0.02 * s.X, 0.02 * s.Y, 0.7 * s.Z), at(x, 0.56 * s.Y, 0.02 * s.Z), darken(base, 0.6), "Block")
		end
		if L > 0.6 then
			chain(folder, head, V3(0, 0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.4), 2, 0.25 * s.Y * L, 0.5 * s.X, 0.1 * s.Z, colorFn, 1, htype)
		end
	elseif style == "Undercut" then
		mk(folder, head, "ShavedSides", V3(s.X * 1.02, s.Y * 0.55, s.Z * 1.03), at(0, 0.2 * s.Y, 0.06 * s.Z), lerpColor(base, skin, 0.6), "Ellipsoid", SMOOTH, 0.3)
		-- a full top section swept to one side, sitting on the crown rather than floating like a cap
		local topH = (0.34 + L * 0.2) * s.Y
		mk(folder, head, "TopSweep", V3(s.X * 0.9, topH, s.Z * 1.04), at(0.04 * s.X, 0.5 * s.Y - topH * 0.18, 0.0), base, "Ellipsoid", mat)
		for i = 1, 5 do
			local x = (i - 3) * 0.15 * s.X
			mk(folder, head, "Sweep", V3(0.16 * s.X, (0.1 + L * 0.06) * s.Y, 0.6 * s.Z), at(x + 0.05 * s.X, 0.5 * s.Y + topH * 0.3, -0.12 * s.Z) * ANG(math.rad(-14), 0, math.rad(-12)),
				colorFn(i, 0.2, x), "Ellipsoid", mat)
		end
		texture(10, 0.08)
	elseif style == "Messy Hair" then
		cap(0.08)
		local rng = Random.new(app.face and app.face.seed or 5)
		for i = 1, math.floor(10 + density * 10) do
			local a = rng:NextNumber(0, math.pi * 2)
			local x, z = math.cos(a) * 0.35 * s.X, math.sin(a) * 0.35 * s.Z
			mk(folder, head, "Tuft", V3(0.12 * s.X, (0.15 + L * 0.2) * s.Y, 0.12 * s.Z),
				at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.7, 0.7), 0, rng:NextNumber(-0.7, 0.7)), colorFn(i, 0.3, x), "Wedge", mat)
		end
	elseif style == "Cornrows" then
		mk(folder, head, "Scalp", V3(s.X * 1.03, s.Y * 0.5, s.Z * 1.05), at(0, 0.36 * s.Y, 0.03 * s.Z), lerpColor(base, skin, 0.25), "Ellipsoid", SMOOTH)
		local rows = 5 + math.floor(density * 3)
		for i = 1, rows do
			local x = (i - (rows + 1) / 2) * (0.85 / rows) * s.X
			for j = 0, 3 do
				local a = math.rad(-50 + j * 38)
				local y = 0.3 * s.Y + math.cos(a) * 0.25 * s.Y
				local z = math.sin(a) * 0.58 * s.Z
				mk(folder, head, "Row", V3(0.07 * s.X * (0.8 + thick * 0.5), 0.07 * s.Y, 0.24 * s.Z), at(x, y, z) * ANG(a, 0, 0), colorFn(i, j / 3, x), "Ellipsoid", mat)
			end
			if L > 0.45 and i % 2 == 0 then
				chain(folder, head, V3(x, -0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.2), 2, 0.25 * s.Y * L, 0.07 * s.X, 0.07 * s.Z, colorFn, i, htype, true)
			end
		end
	elseif style == "Dreadlocks" or style == "Twists" or style == "Braids" then
		cap(0.07)
		local n = math.floor(8 + density * 12)
		local segs = style == "Twists" and 1 or (L > 0.7 and 3 or 2)
		local segLen = (style == "Twists" and 0.22 or 0.28 + 0.2 * L) * s.Y
		local w = (style == "Braids" and 0.07 or 0.1) * s.X * (0.8 + 0.5 * thick)
		for i = 1, n do
			local a = math.rad(-150 + (i - 1) * (300 / math.max(1, n - 1)))
			local x = math.sin(a) * 0.5 * s.X
			local z = math.cos(a) * 0.5 * s.Z
			if z > -0.3 * s.Z then
				local y = (0.05 + math.abs(math.cos(a)) * 0.15) * s.Y
				chain(folder, head, V3(x, y, z), V3(x * 0.4, -1, z * 0.4 + 0.2), segs, segLen, w, w, colorFn, i, style == "Braids" and htype or "Coiled", style == "Braids")
			end
		end
		-- locs from the crown fall back over the head
		for i = 1, math.floor(n / 2) do
			local x = (i - n / 4) * 0.14 * s.X
			chain(folder, head, V3(x, 0.5 * s.Y, 0.1 * s.Z), V3(x * 0.3, -0.35, 1), 2, segLen * 0.6, w, w, colorFn, i + 50, style == "Braids" and htype or "Coiled", style == "Braids")
		end
	elseif style == "Short Dreads" then
		-- short freeform locs: a crown of locs that spring up and out before drooping, a fringe that
		-- falls over the forehead (stopping above the brows so the face stays clear) and locs
		-- hanging over the sides and back - a spiky silhouette wider than the head
		cap(0.08)
		local smoothMat = SMOOTH
		local w = 0.085 * s.X * (0.85 + 0.5 * thick)
		local len = (0.22 + 0.12 * L) * s.Y
		local rng = Random.new((app.face and app.face.seed or 7) + 31)
		local idx = 0
		local function loc(x, y, z, dir, segs, segLen, width)
			idx += 1
			chain(folder, head, V3(x, y, z), dir, segs, segLen, width or w, width or w, colorFn, idx, "Coiled")
		end
		local nf = 6 + math.floor(density * 3)
		for i = 1, nf do
			local x = (i - (nf + 1) / 2) * (0.7 / nf) * s.X
			local k = math.clamp(x / (s.X * 0.5), -0.97, 0.97)
			local z = -0.5 * s.Z * math.sqrt(1 - k * k) + 0.05 * s.Z
			loc(x, 0.5 * s.Y, z, V3(x * 0.35 + rng:NextNumber(-0.08, 0.08), -1, -0.25), 1, (0.2 + 0.05 * L) * s.Y * rng:NextNumber(0.9, 1.1))
		end
		local nc = 12 + math.floor(density * 6)
		for i = 1, nc do
			local a = (i - 0.5) / nc * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
			local dx, dz = math.sin(a), math.cos(a) -- dz < 0 is towards the face
			if dz > -0.8 then
				local r0 = rng:NextNumber(0.12, 0.3)
				loc(dx * r0 * s.X, 0.56 * s.Y, dz * r0 * s.Z + 0.04 * s.Z, V3(dx, rng:NextNumber(-0.05, 0.25), dz), 2, len * rng:NextNumber(0.85, 1.15))
			end
		end
		local ns = 10 + math.floor(density * 6)
		for i = 1, ns do
			local a = math.rad(-118 + (i - 1) * (236 / math.max(1, ns - 1)))
			local dx, dz = math.sin(a), math.cos(a)
			loc(dx * 0.5 * s.X, 0.3 * s.Y, dz * 0.5 * s.Z, V3(dx * 0.5, -1, dz * 0.5), 2, len * rng:NextNumber(0.8, 1.0))
		end
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Material = smoothMat
			end
		end
	elseif style == "Short Curly" then
		cap(0.08)
		bumps(folder, head, math.floor(28 * (0.6 + density)), (0.11 + 0.05 * thick) * s.X, 0.3, colorFn, htype == "Straight" and "Curly" or htype, 21, s)
	elseif style == "Long Curly" then
		cap(0.1, 0.1)
		bumps(folder, head, math.floor(26 * (0.6 + density)), (0.13 + 0.05 * thick) * s.X, 0.2, colorFn, htype == "Straight" and "Curly" or htype, 22, s)
		local n = math.floor(6 + density * 6)
		for i = 1, n do
			local a = math.rad(-120 + (i - 1) * (240 / math.max(1, n - 1)))
			local x, z = math.sin(a) * 0.52 * s.X, math.cos(a) * 0.52 * s.Z
			chain(folder, head, V3(x, 0.05 * s.Y, z), V3(x * 0.3, -1, z * 0.3 + 0.2), L > 0.6 and 3 or 2, (0.25 + 0.15 * L) * s.Y, 0.18 * s.X, 0.18 * s.Z, colorFn, i, htype == "Straight" and "Curly" or htype)
		end
	elseif style == "Long Hair" or style == "Wolf Cut" then
		cap(0.09, 0.12)
		local isWolf = style == "Wolf Cut"
		local segs = isWolf and 1 or (L > 0.75 and 3 or 2)
		local segLen = (isWolf and 0.25 or 0.3 + 0.25 * L) * s.Y
		-- back curtain
		chain(folder, head, V3(0, 0.05 * s.Y, 0.5 * s.Z), V3(0, -1, 0.3), segs, segLen, 0.9 * s.X, (0.12 + 0.08 * thick) * s.Z, colorFn, 1, htype)
		-- side curtains
		for side = -1, 1, 2 do
			chain(folder, head, V3(side * 0.5 * s.X, 0.15 * s.Y, 0.05 * s.Z), V3(side * 0.2, -1, 0.1), segs, segLen * 0.9, 0.12 * s.X, 0.5 * s.Z, colorFn, side + 3, htype)
		end
		if isWolf then
			local rng = Random.new(app.face and app.face.seed or 9)
			for i = 1, 9 do
				local a = rng:NextNumber(0, math.pi * 2)
				local x, z = math.cos(a) * 0.38 * s.X, math.sin(a) * 0.38 * s.Z
				mk(folder, head, "Shag", V3(0.16 * s.X, 0.2 * s.Y, 0.16 * s.Z), at(x, 0.52 * s.Y, z) * ANG(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)), colorFn(i, 0.2, x), "Wedge", mat)
			end
			-- choppy fringe: separate strands that follow the curve of the forehead
			for i = 1, 5 do
				local x = (i - 3) * 0.14 * s.X
				local k = math.clamp(x / (s.X * 0.5), -0.97, 0.97)
				local z = -0.5 * s.Z * math.sqrt(1 - k * k) * 0.93
				mk(folder, head, "Bangs", V3(0.15 * s.X, (0.2 + 0.06 * L) * s.Y, 0.07 * s.Z), at(x, 0.38 * s.Y, z) * ANG(math.rad(-10), 0, math.rad((i - 3) * -6)),
					colorFn(i, 0.1, x), "Ellipsoid", mat)
			end
		end
		texture(12, 0.08)
	elseif style == "Ponytail" then
		cap(0.06, 0.05)
		for _, p in ipairs(folder:GetChildren()) do
			if htype == "Straight" then
				p.Reflectance = 0.08
			end
		end
		mk(folder, head, "HairTie", V3(0.14 * s.X, 0.14 * s.Y, 0.1 * s.Z), at(0, 0.28 * s.Y, 0.56 * s.Z), Looks.Color(app.attire and app.attire.trim, Color3.new(1, 1, 1)), "Ellipsoid")
		chain(folder, head, V3(0, 0.28 * s.Y, 0.6 * s.Z), V3(0, -0.8, 0.6), L > 0.6 and 4 or 3, (0.22 + 0.12 * L) * s.Y, (0.2 + 0.1 * thick) * s.X, (0.2 + 0.1 * thick) * s.Z, colorFn, 1, htype)
	else
		cap(0.08)
		texture(14, 0.08)
	end
end

local function beardBuild(model, app)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local folder = getFolder(model, "Beard")
	local beard = app.beard or { style = "None", growth = 0 }
	if app.gender == 2 then
		return
	end
	local style = beard.style or "None"
	local g = math.clamp(beard.growth or 0, 0, 1)
	if style == "None" then
		if g < 0.45 then
			return
		end
		style = "Stubble" -- five o'clock shadow grows in
	end
	local s = head.Size
	local hcf = head.CFrame
	local L = Head.FaceLayout(head, app.face or {})
	local color = Looks.Color(app.hair and app.hair.color, Color3.fromRGB(25, 20, 18))
	local mat = Enum.Material.Fabric
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	local function moustache()
		mk(folder, head, "Moustache", V3(0.3 * s.X, (0.045 + 0.03 * g) * s.Y, 0.06 * s.Z), at(0, L.mouthY + 0.065 * s.Y, L.front(0) - 0.025), color, "Ellipsoid", mat)
	end
	if style == "Stubble" then
		-- an even, translucent shadow over the whole jaw (a tighter shell only pokes through the cheeks in patches)
		mk(folder, head, "Stubble", V3(s.X * 1.1, s.Y * 0.52, s.Z * 1.12), at(0, -0.28 * s.Y, -0.01 * s.Z), color, "Ellipsoid", SMOOTH, 0.76 - 0.14 * g)
	elseif style == "Goatee" then
		mk(folder, head, "Goatee", V3(0.24 * s.X, (0.2 + 0.08 * g) * s.Y, 0.16 * s.Z), at(0, -0.44 * s.Y, L.front(0) * 0.82), color, "Ellipsoid", mat)
		moustache()
	elseif style == "Moustache" then
		moustache()
	elseif style == "Chin Strap" then
		for side = -1, 1, 2 do
			mk(folder, head, "Strap", V3(0.06 * s.X, 0.42 * s.Y, 0.5 * s.Z), at(side * 0.46 * s.X, -0.25 * s.Y, -0.05 * s.Z) * ANG(0, 0, math.rad(side * 12)), color, "Block", mat)
		end
		mk(folder, head, "StrapChin", V3(0.55 * s.X, 0.08 * s.Y, 0.3 * s.Z), at(0, -0.5 * s.Y, L.front(0) * 0.55), color, "Ellipsoid", mat)
	elseif style == "Short Boxed" then
		mk(folder, head, "Beard", V3(s.X * 1.05, s.Y * (0.5 + 0.06 * g), s.Z * 1.04), at(0, -0.3 * s.Y, 0.0), color, "Ellipsoid", mat)
		moustache()
	else -- Full Beard
		mk(folder, head, "Beard", V3(s.X * 1.08, s.Y * (0.62 + 0.16 * g), s.Z * 1.08), at(0, -0.36 * s.Y, -0.03 * s.Z), color, "Ellipsoid", mat)
		moustache()
	end
	-- keep the lips visible through the beard
	local mouth = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Face")
	if mouth then
		for _, n in ipairs({ "UpperLip", "LowerLip", "MouthLine" }) do
			local p = mouth:FindFirstChild(n)
			if p then
				p.Size = p.Size + V3(0, 0, 0.03)
			end
		end
	end
end

------------------------------------------------------------------------
-- Headgear (toggled during sparring)
------------------------------------------------------------------------
function Head.SetHeadgear(model, color, on)
	local folder = getFolder(model, "Headgear")
	if not on then
		return
	end
	local head = part(model, "Head")
	if not head then
		return
	end
	local s = head.Size
	local mat = Enum.Material.Leather
	mk(folder, head, "HGTop", V3(s.X * 1.18, s.Y * 0.62, s.Z * 1.18), head.CFrame * CF(0, 0.36 * s.Y, 0.05 * s.Z), color, "Ellipsoid", mat)
	for side = -1, 1, 2 do
		mk(folder, head, "HGCheek", V3(0.16 * s.X, 0.62 * s.Y, 0.75 * s.Z), head.CFrame * CF(side * 0.52 * s.X, -0.08 * s.Y, 0.05 * s.Z), color, "Block", mat)
	end
	mk(folder, head, "HGBack", V3(s.X * 1.1, s.Y * 0.7, 0.2 * s.Z), head.CFrame * CF(0, 0.05 * s.Y, 0.55 * s.Z), color, "Block", mat)
	mk(folder, head, "HGStrap", V3(s.X * 0.6, 0.06 * s.Y, 0.3 * s.Z), head.CFrame * CF(0, -0.52 * s.Y, -0.1 * s.Z), darken(color, 0.6), "Block")
end

------------------------------------------------------------------------
-- Damage & sweat
------------------------------------------------------------------------
-- dmg = { leftEye, rightEye (0..1 swelling), cut (0..1.2), cutSide, noseBleed (0..1), nose (broken bool), bruise (0..1), lip (0..1) }
function Head.SetDamage(model, app, dmg)
	local head = part(model, "Head")
	if not head then
		return
	end
	local folder = getFolder(model, "Damage")
	local face = app.face or {}
	local L = Head.FaceLayout(head, face)
	local s = L.s
	local hcf = head.CFrame
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local bruiseColor = lerpColor(skin, Color3.fromRGB(80, 30, 90), 0.6)
	local blood = Color3.fromRGB(150, 0, 0)
	local function at(x, y, z)
		return hcf * CF(x, y, z)
	end
	-- swollen eyes: a puffy lid closes over the eye as swelling grows
	local faceFolder = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Face")
	for side = -1, 1, 2 do
		local v = side == -1 and (dmg.leftEye or 0) or (dmg.rightEye or 0)
		local w = 0.15 * L.eyeSize * s.X
		local h = 0.15 * L.eyeSize * L.eyeH * s.Y
		local closing = math.clamp((v - 0.3) / 0.7, 0, 1)
		if faceFolder then
			for _, lid in ipairs(faceFolder:GetChildren()) do
				if lid.Name == "Lid" and lid:GetAttribute("Side") == side then
					lid.Transparency = closing > 0 and 1 or 0
				end
			end
		end
		if closing > 0 then
			local cover = 0.32 + 0.75 * closing
			mk(folder, head, "SwollenLid", V3(w * 1.14, h * cover, 0.055 * s.Z),
				at(side * L.eyeX, L.eyeY + h * (0.5 - cover / 2), L.front(side * L.eyeX) - 0.016), lerpColor(darken(skin, 0.92), bruiseColor, v * 0.6), "Ellipsoid")
		end
		if v > 0.15 then
			local size = (0.18 + 0.12 * v) * s.X
			mk(folder, head, "SwollenEye", V3(size, size * 0.8, 0.08 * s.Z), at(side * L.eyeX, L.eyeY + 0.02 * s.Y, L.front(side * L.eyeX) + 0.01), bruiseColor, "Ellipsoid", SMOOTH, math.clamp(0.75 - v * 0.6, 0.15, 0.75))
		end
	end
	-- cut above the eye
	if (dmg.cut or 0) > 0.05 then
		local side = dmg.cutSide or 1
		local v = dmg.cut
		local x = side * L.eyeX
		mk(folder, head, "Cut", V3((0.1 + 0.12 * v) * s.X, 0.025 * s.Y, 0.02), at(x, L.browY + 0.025 * s.Y, L.front(x) - 0.02) * ANG(0, 0, math.rad(-side * 15)), Color3.fromRGB(120, 0, 0))
		if v > 0.35 then
			mk(folder, head, "Blood", V3(0.025, (0.1 + 0.25 * v) * s.Y, 0.02), at(x + side * 0.04, L.browY - (0.06 + 0.12 * v) * s.Y, L.front(x) - 0.018), blood)
		end
	end
	-- nose
	if dmg.nose then
		mk(folder, head, "NoseBruise", V3(L.noseW * 1.3, L.noseLen * 0.9, 0.04), at(0.01, (L.noseTopY + L.noseBottomY) / 2, L.front(0) - L.noseB * 0.55) * ANG(0, 0, math.rad(10)), bruiseColor, "Ellipsoid", SMOOTH, 0.35)
	end
	if (dmg.noseBleed or 0) > 0.2 then
		for side = -1, 1, 2 do
			mk(folder, head, "NoseBlood", V3(0.025, (0.06 + 0.12 * dmg.noseBleed) * s.Y, 0.02), at(side * L.noseW * 0.28, L.noseBottomY - 0.05 * dmg.noseBleed * s.Y, L.front(0) - L.noseB * 0.55), blood)
		end
	end
	-- bruised face
	if (dmg.bruise or 0) > 0.2 then
		for side = -1, 1, 2 do
			local x = side * 0.3 * s.X
			mk(folder, head, "Bruise", V3(0.22 * s.X, 0.16 * s.Y, 0.04), at(x, -0.06 * s.Y, L.front(x) + 0.0), bruiseColor, "Ellipsoid", SMOOTH, math.clamp(0.85 - dmg.bruise * 0.55, 0.3, 0.85))
		end
	end
	-- split lip
	if (dmg.lip or 0) > 0.25 then
		mk(folder, head, "SplitLip", V3(0.06 * s.X, 0.05 * s.Y, 0.03), at(0.05 * s.X, L.mouthY - 0.035 * s.Y, L.front(0) - 0.035), Color3.fromRGB(130, 0, 10), "Ellipsoid")
		if dmg.lip > 0.6 then
			mk(folder, head, "LipBlood", V3(0.02, 0.08 * s.Y, 0.02), at(0.05 * s.X, L.mouthY - 0.1 * s.Y, L.front(0) - 0.025), blood)
		end
	end
end

function Head.SetSweat(model, app, level)
	-- a subtle sheen: Reflectance mirrors the sky, so keep it low or skin glows white
	local base = (app.face and app.face.shine or 0) * 0.03
	local r = math.clamp(base + level * 0.05, 0, 0.08)
	for _, n in ipairs({ "Head", "UpperTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }) do
		local p = part(model, n)
		if p then
			p.Reflectance = r
			if level > 0.05 then
				p.Material = SMOOTH
			end
		end
	end
	local muscles = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Muscles")
	if muscles then
		for _, p in ipairs(muscles:GetChildren()) do
			if p:IsA("BasePart") then
				p.Reflectance = r
			end
		end
	end
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics)
------------------------------------------------------------------------
Head.Face = faceBuild -- (model, app, opts)
Head.Hair = hairBuild -- (model, app)
Head.Beard = beardBuild -- (model, app)

return Head
