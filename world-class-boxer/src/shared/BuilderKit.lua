-- BuilderKit: part and colour helpers shared by the character builder modules.
-- Builder (facade: scales, HumanoidDescription, Cosmetics/Apply/CreateNPC), BuilderHead (face, hair,
-- beard, damage, sweat, headgear) and BuilderBody (colours, muscles, attire, hands, robe) all make their
-- extra parts with these, so every layer is welded, named and foldered the same way.
-- * V3 / CF / ANG / SMOOTH short aliases; lerpColor / darken / contrast / rgb colour maths
-- * weld, mk (part factory), textPatch (SurfaceGui text), getFolder (fresh BoxerLook sub-folder), part
-- * joint (animatable Motor6D, CONTRACTS section 5), font (safe Enum.Font lookup), setAttr (change-only)
-- * sig / cached / seal: per-folder rebuild caching (skip rebuilding a layer whose inputs did not change)
-- Requires none of the other builder modules, so they can all require it without a cycle.
local Kit = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local SMOOTH = Enum.Material.SmoothPlastic

-- false = always rebuild every layer (debug switch for the per-folder signature cache)
Kit.CACHE = true

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

-- {r,g,b} (0..255, the save / Catalog format) -> Color3; anything else -> fallback
local function rgb(t, fallback)
	if type(t) == "table" and type(t[1]) == "number" then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return fallback or Color3.new(1, 1, 1)
end

-- Enum.Font by NAME (Catalog brand fonts); unknown names fall back to GothamBlack instead of erroring
local fontCache = {}
local function font(name)
	if type(name) ~= "string" or name == "" then
		return Enum.Font.GothamBlack
	end
	local f = fontCache[name]
	if f == nil then
		local ok, res = pcall(function()
			return Enum.Font[name]
		end)
		f = ok and res or Enum.Font.GothamBlack
		fontCache[name] = f
	end
	return f
end

-- attributes replicate on every write, so only write real changes
local function setAttr(inst, key, value)
	if inst:GetAttribute(key) ~= value then
		inst:SetAttribute(key, value)
	end
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

-- fontName (optional) = an Enum.Font name; bg (optional Color3) = a filled label (sponsor patches)
local function textPatch(folder, anchor, name, size, cf, text, textColor, face, fontName, bg)
	local p = mk(folder, anchor, name, size, cf, Color3.new(0, 0, 0), "Block", SMOOTH, 1)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 120
	sg.LightInfluence = 0.6
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then
		t.BackgroundColor3 = bg
		t.BorderSizePixel = 0
	end
	t.Text = text
	t.TextScaled = true
	t.Font = fontName and font(fontName) or Enum.Font.GothamBlack
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

-- animatable cosmetic joint (CONTRACTS section 5): the moving part has no WeldConstraint, the
-- client animates Motor6D.Transform. C0 = where part1 sits in part0's space, C1 = identity.
local function joint(part0, part1, name)
	local m = Instance.new("Motor6D")
	m.Name = name or "Joint"
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * part1.CFrame
	m.C1 = CF()
	m.Parent = part1
	return m
end

------------------------------------------------------------------------
-- Rebuild caching. Builder.Cosmetics runs after every session, sleep, purchase and fight; a layer
-- whose inputs did not change keeps its parts instead of destroying and re-replicating ~50 of them.
------------------------------------------------------------------------
-- stable text signature of any mix of numbers (rounded), strings, booleans and nested tables
local function sigInto(out, v)
	local t = typeof(v)
	if t == "number" then
		out[#out + 1] = string.format("%.3f", v)
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			sigInto(out, v[k])
		end
		out[#out + 1] = "}"
	elseif t == "Vector3" then
		out[#out + 1] = string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z)
	elseif t == "Color3" then
		out[#out + 1] = string.format("%.3f,%.3f,%.3f", v.R, v.G, v.B)
	else
		out[#out + 1] = tostring(v)
	end
	out[#out + 1] = ";"
end

local function sig(...)
	local out = {}
	for i = 1, select("#", ...) do
		sigInto(out, (select(i, ...)))
	end
	return table.concat(out)
end

-- every weld / motor in the folder still holds on to a part of this model (a respawn, a head swap or
-- a rescale through ApplyDescription replaces or moves the anchors, so the old parts are stale)
local function intact(model, folder)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			local p0 = d.Part0
			if not (p0 and p0:IsDescendantOf(model)) or not d.Part1 then
				return false
			end
		end
	end
	return true
end

-- true when BoxerLook/<name> was built from exactly this signature and is still attached
local function cached(model, name, key)
	if not Kit.CACHE then
		return false
	end
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild(name)
	return f ~= nil and f:GetAttribute("Sig") == key and intact(model, f)
end

-- stamp a finished folder with the signature it was built from (set last: a build that errors
-- half way never gets a signature, so the next call rebuilds it)
local function seal(model, name, key)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild(name)
	if f then
		f:SetAttribute("Sig", key)
	end
end

Kit.V3 = V3
Kit.CF = CF
Kit.ANG = ANG
Kit.SMOOTH = SMOOTH
Kit.lerpColor = lerpColor
Kit.darken = darken
Kit.contrast = contrast
Kit.rgb = rgb
Kit.font = font
Kit.setAttr = setAttr
Kit.weld = weld
Kit.mk = mk
Kit.textPatch = textPatch
Kit.getFolder = getFolder
Kit.part = part
Kit.joint = joint
Kit.sig = sig
Kit.intact = intact
Kit.cached = cached
Kit.seal = seal

return Kit
