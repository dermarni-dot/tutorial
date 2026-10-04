-- BuilderKit: part and colour helpers shared by the character builder modules.
-- Builder (facade: scales, HumanoidDescription, Cosmetics/Apply/CreateNPC), BuilderHead (face, hair,
-- beard, damage, sweat, headgear) and BuilderBody (colours, muscles, attire, hands, robe) all make their
-- extra parts with these, so every layer is welded, named and foldered the same way.
-- * V3 / CF / ANG / SMOOTH short aliases; lerpColor / darken / contrast colour maths
-- * weld, mk (part factory), textPatch (SurfaceGui text), getFolder (fresh BoxerLook sub-folder), part
-- Requires none of the other builder modules, so they can all require it without a cycle.
local Kit = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local SMOOTH = Enum.Material.SmoothPlastic

local function lerpColor(a, b, t)
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function darken(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function contrast(c)
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return lum > 0.55 and Color3.fromRGB(20, 20, 24) or Color3.fromRGB(245, 245, 245)
end

------------------------------------------------------------------------
-- Part helpers
------------------------------------------------------------------------
local function weld(part, anchor)
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = part
	w.Parent = part
end

-- shape: "Block" (default), "Ball", "Cylinder", "Ellipsoid", "Wedge"
local function mk(folder, anchor, name, size, cf, color, shape, material, transparency)
	local p = (shape == "Wedge") and Instance.new("WedgePart") or Instance.new("Part")
	p.Name = name
	p.Size = V3(math.max(size.X, 0.02), math.max(size.Y, 0.02), math.max(size.Z, 0.02))
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ellipsoid" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	if transparency then
		p.Transparency = transparency
	end
	p.CFrame = cf
	if anchor then
		weld(p, anchor)
	end
	p.Parent = folder
	return p
end

local function textPatch(folder, anchor, name, size, cf, text, textColor, face)
	local p = mk(folder, anchor, name, size, cf, Color3.new(0, 0, 0), "Block", SMOOTH, 1)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 120
	sg.LightInfluence = 0.6
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = textColor
	t.Parent = sg
	sg.Parent = p
	return p
end

local function getFolder(model, name)
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		look = Instance.new("Folder")
		look.Name = "BoxerLook"
		look.Parent = model
	end
	local f = look:FindFirstChild(name)
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = look
	return f
end

local function part(model, name)
	return model:FindFirstChild(name)
end

Kit.V3 = V3
Kit.CF = CF
Kit.ANG = ANG
Kit.SMOOTH = SMOOTH
Kit.lerpColor = lerpColor
Kit.darken = darken
Kit.contrast = contrast
Kit.weld = weld
Kit.mk = mk
Kit.textPatch = textPatch
Kit.getFolder = getFolder
Kit.part = part

return Kit
