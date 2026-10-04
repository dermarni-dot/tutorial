-- CityProps: small procedural props shared by the server city (CityMap) and the client's
-- per-player city dressing (CityVisuals): sports cars, the bronze statue, walk-of-fame stars and
-- low-poly fan proxies. Everything is plain Parts / SpecialMeshes / SurfaceGuis (no assets), so the
-- same builder looks identical in the Prestige Motors showroom and in your own driveway.
local CollectionService = game:GetService("CollectionService")

local CityProps = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

------------------------------------------------------------------------
-- helpers (same conventions as GymDecor: anchored, no collision unless asked, cylinders along X)
------------------------------------------------------------------------
local function part(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.class or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local collide = opts.collide == true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflect then
		p.Reflectance = opts.reflect
	end
	if opts.shadow == false then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

local function cyl(parent, name, length, diameter, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return part(parent, name, V3(length, diameter, diameter), cf, color, material, opts)
end

local function ball(parent, name, d, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Ball
	return part(parent, name, V3(d, d, d), cf, color, material, opts)
end

local function blob(parent, name, size, cf, color, material, opts)
	local p = part(parent, name, size, cf, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function wedge(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	opts.class = "WedgePart"
	return part(parent, name, size, cf, color, material, opts)
end

local function gui(p, face, ppu, light, maxDist)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 30
	sg.LightInfluence = light or 0
	sg.MaxDistance = maxDist or 250
	sg.Parent = p
	return sg
end

local function label(parent, text, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = text
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	t.Parent = parent
	return t
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function tag(inst, name)
	CollectionService:AddTag(inst, name)
	return inst
end

local function rgb(t, fallback)
	if typeof(t) == "Color3" then
		return t
	end
	if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]) then
		return Color3.fromRGB(math.clamp(t[1], 0, 255), math.clamp(t[2], 0, 255), math.clamp(t[3], 0, 255))
	end
	return fallback or Color3.new(1, 1, 1)
end

CityProps.Part = part
CityProps.Cyl = cyl
CityProps.Ball = ball
CityProps.Blob = blob
CityProps.Wedge = wedge
CityProps.Gui = gui
CityProps.Label = label
CityProps.Frame = frame
CityProps.Tag = tag
CityProps.RGB = rgb

------------------------------------------------------------------------
-- Sports cars. cf = ground centre, nose towards local -Z.
-- kind: "SportsCar" (red coupe), "Supercar" (low wedge, scissor stance, big wing), "Hypercar"
-- (longtail, gold rims, neon underglow tagged NightLight-free: the glow strip is Neon, its light
-- is tagged NightLight so it only shines at night). About 25-32 parts.
------------------------------------------------------------------------
CityProps.CarSpecs = {
	SportsCar = { color = Color3.fromRGB(190, 24, 32), len = 10.4, width = 5.0, body = 1.25, cabin = 1.25, cabinLen = 4.2, rim = Color3.fromRGB(200, 202, 208), wing = false, glow = nil, name = "Sports Car" },
	Supercar = { color = Color3.fromRGB(245, 190, 20), len = 11.2, width = 5.4, body = 1.05, cabin = 1.1, cabinLen = 3.8, rim = Color3.fromRGB(30, 30, 34), wing = true, glow = nil, name = "Supercar" },
	Hypercar = { color = Color3.fromRGB(20, 22, 30), len = 12.0, width = 5.6, body = 1.0, cabin = 1.05, cabinLen = 3.6, rim = Color3.fromRGB(230, 180, 40), wing = true, glow = Color3.fromRGB(0, 200, 255), name = "Hypercar" },
}
CityProps.CarOrder = { "Hypercar", "Supercar", "SportsCar" } -- best first

function CityProps.SportsCar(parent, cf, kind, color, plate)
	local s = CityProps.CarSpecs[kind] or CityProps.CarSpecs.SportsCar
	local m = Instance.new("Model")
	m.Name = kind or "SportsCar"
	local col = color or s.color
	local L, W, B = s.len, s.width, s.body
	local glass = Color3.fromRGB(26, 34, 44)
	local dark = Color3.fromRGB(18, 18, 20)
	-- tub, sloped nose and tail (a WedgePart is low at its -Z end, tall at +Z), side intakes,
	-- glass canopy with a roof skin
	local bodyLen, noseLen, tailLen = L * 0.56, L * 0.26, L * 0.18
	local noseFront = 0.4 - bodyLen / 2 - noseLen
	local tailEnd = 0.4 + bodyLen / 2 + tailLen
	local slope = math.atan(B / noseLen)
	part(m, "CarBody", V3(W, B, bodyLen), cf * CF(0, 0.55 + B / 2, 0.4), col, M.SmoothPlastic, { collide = true, reflect = 0.08 })
	wedge(m, "CarNose", V3(W, B, noseLen), cf * CF(0, 0.55 + B / 2, noseFront + noseLen / 2), col, M.SmoothPlastic, { reflect = 0.08 })
	wedge(m, "CarTail", V3(W, B * 0.8, tailLen), cf * CF(0, 0.55 + B * 0.4, tailEnd - tailLen / 2) * ANG(0, RAD(180), 0), col, M.SmoothPlastic, { reflect = 0.08 })
	part(m, "CarTailPanel", V3(W, B * 0.55, 0.3), cf * CF(0, 0.55 + B * 0.28, tailEnd - 0.1), dark, M.SmoothPlastic)
	local cabinY = 0.55 + B + s.cabin / 2
	wedge(m, "Windscreen", V3(W * 0.82, s.cabin, 2.0), cf * CF(0, cabinY, 0.4 - (s.cabinLen - 0.8) / 2 - 1.0), glass, M.Glass, { reflect = 0.25 })
	part(m, "CarCabin", V3(W * 0.82, s.cabin, s.cabinLen - 0.8), cf * CF(0, cabinY, 0.4), glass, M.Glass, { reflect = 0.2 })
	wedge(m, "RearGlass", V3(W * 0.82, s.cabin, 2.4), cf * CF(0, cabinY, 0.4 + (s.cabinLen - 0.8) / 2 + 1.2) * ANG(0, RAD(180), 0), glass, M.Glass, { reflect = 0.2 })
	part(m, "CarRoof", V3(W * 0.8, 0.12, s.cabinLen - 1.2), cf * CF(0, cabinY + s.cabin / 2 + 0.04, 0.4), col, M.SmoothPlastic, { reflect = 0.08 })
	for _, x in ipairs({ -1, 1 }) do
		part(m, "SideIntake", V3(0.12, B * 0.55, 1.6), cf * CF(x * (W / 2 + 0.02), 0.55 + B * 0.5, 1.6), dark, M.SmoothPlastic)
		part(m, "Mirror", V3(0.5, 0.25, 0.35), cf * CF(x * (W * 0.45), cabinY - 0.2, 0.4 - (s.cabinLen - 0.8) / 2 + 0.2), col, M.SmoothPlastic)
		-- headlights sit on the slope of the nose, taillights across the tail panel
		part(m, "Headlight", V3(1.1, 0.1, 0.55), cf * CF(x * (W * 0.32), 0.55 + B * 0.42 + 0.04, noseFront + noseLen * 0.42) * ANG(-slope, 0, 0), Color3.fromRGB(250, 250, 240), M.Neon, { shadow = false })
		part(m, "Taillight", V3(1.4, 0.18, 0.1), cf * CF(x * (W * 0.3), 0.55 + B * 0.42, tailEnd + 0.08), Color3.fromRGB(230, 20, 30), M.Neon, { shadow = false })
		-- wheels with a rim and five spokes (thin plates turned about the axle)
		for _, z in ipairs({ -L * 0.31, L * 0.3 }) do
			local wcf = cf * CF(x * (W / 2 - 0.15), 1.0, z)
			cyl(m, "Wheel", 0.95, 2.0, wcf, dark, M.Rubber)
			cyl(m, "Rim", 0.98, 1.35, wcf, s.rim, M.Metal, { reflect = 0.2 })
			for k = 0, 1 do
				part(m, "Spoke", V3(1.0, 1.25, 0.16), wcf * ANG(RAD(k * 36 + 18), 0, 0), s.rim:Lerp(dark, 0.35), M.Metal)
			end
		end
	end
	part(m, "Splitter", V3(W + 0.1, 0.12, 0.8), cf * CF(0, 0.5, noseFront + 0.3), dark, M.SmoothPlastic)
	part(m, "Diffuser", V3(W * 0.8, 0.3, 0.6), cf * CF(0, 0.55, tailEnd - 0.2), dark, M.SmoothPlastic)
	if s.wing then
		part(m, "Wing", V3(W * 0.95, 0.12, 1.1), cf * CF(0, 0.55 + B + 1.0, tailEnd - 0.9), dark, M.SmoothPlastic)
		for _, x in ipairs({ -1, 1 }) do
			part(m, "WingStrut", V3(0.12, 1.0, 0.4), cf * CF(x * W * 0.3, 0.55 + B * 0.8 + 0.5, tailEnd - 0.9), dark, M.Metal)
		end
	end
	if s.glow then
		local strip = part(m, "Underglow", V3(W * 0.9, 0.08, L * 0.7), cf * CF(0, 0.38, 0.2), s.glow, M.Neon, { transparency = 0.4, shadow = false })
		local l = Instance.new("PointLight")
		l.Color = s.glow
		l.Range = 8
		l.Brightness = 1.4
		l.Shadows = false
		l.Enabled = false
		l.Parent = strip
		tag(l, "NightLight")
	end
	local pl = part(m, "Plate", V3(1.5, 0.45, 0.06), cf * CF(0, 0.55 + B * 0.28, tailEnd + 0.08), Color3.fromRGB(240, 240, 235), M.SmoothPlastic)
	if plate and plate ~= "" then
		local sg = gui(pl, Enum.NormalId.Back, 60, 0, 60)
		label(sg, plate, { TextColor3 = Color3.fromRGB(20, 20, 60), Font = Enum.Font.GothamBold })
	end
	m.Parent = parent
	return m
end

------------------------------------------------------------------------
-- Walk of Fame star: a granite tile with a gold star and the title. cf = tile centre on the
-- pavement (top face up). About 2 parts.
------------------------------------------------------------------------
function CityProps.Star(parent, cf, title, name, gold)
	local tile = part(parent, "FameStar", V3(2.6, 0.06, 2.6), cf, Color3.fromRGB(60, 40, 52), M.Granite)
	local sg = gui(tile, Enum.NormalId.Top, 60, 0.4, 70)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 44, 60) })
	local edge = frame(sg, { Size = UDim2.fromScale(0.94, 0.94), Position = UDim2.fromScale(0.03, 0.03), BackgroundTransparency = 1 })
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(200, 160, 60)
	st.Thickness = 3
	st.Parent = edge
	label(sg, "★", { TextColor3 = gold or Color3.fromRGB(255, 200, 60), Size = UDim2.fromScale(0.7, 0.5), Position = UDim2.fromScale(0.15, 0.02), Font = Enum.Font.SourceSansBold })
	label(sg, name or "", { TextColor3 = Color3.fromRGB(255, 230, 170), Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.54) })
	label(sg, title or "", { TextColor3 = Color3.fromRGB(230, 210, 200), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.78) })
	return tile
end

------------------------------------------------------------------------
-- Bronze statue of a boxer raising a glove (proxy figure, never a Builder character).
-- cf = ground centre, the figure faces local -Z. opts = { name, title, color }. About 16 parts.
------------------------------------------------------------------------
function CityProps.Statue(parent, cf, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Statue"
	local bronze = opts.color or Color3.fromRGB(150, 104, 54)
	local stone = Color3.fromRGB(70, 70, 76)
	local mt = { reflect = 0.12 }
	part(m, "StatueBase", V3(5, 1, 5), cf * CF(0, 0.5, 0), stone, M.Granite, { collide = true })
	part(m, "StatuePlinth", V3(3.8, 3.4, 3.8), cf * CF(0, 2.7, 0), Color3.fromRGB(56, 56, 62), M.Granite, { collide = true })
	local plaque = part(m, "StatuePlaque", V3(3, 1.4, 0.1), cf * CF(0, 2.7, -1.95), Color3.fromRGB(200, 160, 60), M.Metal)
	local sg = gui(plaque, Enum.NormalId.Front, 50, 0.3, 80)
	label(sg, (opts.name or "CHAMPION") .. "\n" .. (opts.title or ""), { TextColor3 = Color3.fromRGB(40, 28, 10), Size = UDim2.fromScale(0.92, 0.84), Position = UDim2.fromScale(0.04, 0.08) })
	local top = cf * CF(0, 4.4, 0)
	-- legs in a stance, trunks, torso, chest, head, raised right arm with a glove, left guard
	for _, x in ipairs({ -0.55, 0.55 }) do
		part(m, "StatueLeg", V3(0.8, 3.0, 0.9), top * CF(x, 1.5, x * 0.4) * ANG(0, 0, RAD(x * 8)), bronze, M.Metal, mt)
	end
	blob(m, "StatueTrunks", V3(2.2, 1.3, 1.3), top * CF(0, 3.2, 0), bronze:Lerp(Color3.new(0, 0, 0), 0.15), M.Metal, mt)
	blob(m, "StatueTorso", V3(2.4, 2.6, 1.4), top * CF(0, 4.7, 0), bronze, M.Metal, mt)
	blob(m, "StatueChest", V3(2.7, 1.2, 1.5), top * CF(0, 5.5, -0.05), bronze, M.Metal, mt)
	part(m, "StatueNeck", V3(0.6, 0.5, 0.6), top * CF(0, 6.25, 0), bronze, M.Metal, mt)
	blob(m, "StatueHead", V3(1.0, 1.2, 1.1), top * CF(0, 6.9, 0), bronze, M.Metal, mt)
	-- right arm up (victory), left arm bent at the guard
	local sh = top * CF(1.35, 5.8, 0)
	part(m, "StatueArmUp", V3(0.6, 2.2, 0.6), sh * ANG(0, 0, RAD(-20)) * CF(0, 1.1, 0), bronze, M.Metal, mt)
	blob(m, "StatueGloveUp", V3(1.0, 1.15, 1.0), sh * ANG(0, 0, RAD(-20)) * CF(0, 2.5, 0), bronze, M.Metal, mt)
	local shL = top * CF(-1.35, 5.7, 0)
	part(m, "StatueArmL", V3(0.6, 1.5, 0.6), shL * ANG(RAD(-40), 0, RAD(10)) * CF(0, -0.7, 0), bronze, M.Metal, mt)
	blob(m, "StatueGloveL", V3(1.0, 1.1, 1.0), shL * CF(0.3, -0.5, -1.1), bronze, M.Metal, mt)
	part(m, "StatueBelt", V3(2.3, 0.45, 1.45), top * CF(0, 3.65, 0), Color3.fromRGB(230, 180, 40), M.Metal, { reflect = 0.25 })
	m.Parent = parent
	return m
end

------------------------------------------------------------------------
-- Fan proxy: torso + head + sign (3 parts). Returns { torso, head, sign, rel } for animation.
-- cf = ground position, facing local -Z. text on the sign (nil = no sign).
------------------------------------------------------------------------
function CityProps.Fan(parent, cf, shirt, skin, text, signColor, textColor)
	local torso = part(parent, "FanTorso", V3(1.6, 2.4, 0.9), cf * CF(0, 2.1, 0), shirt, M.Fabric)
	local head = ball(parent, "FanHead", 1.1, cf * CF(0, 3.85, 0), skin, M.SmoothPlastic)
	local sign
	if text then
		sign = part(parent, "FanSign", V3(1.9, 1.1, 0.06), cf * CF(0, 4.7, -0.55) * ANG(RAD(-10), 0, 0), signColor or Color3.new(1, 1, 1), M.SmoothPlastic, { shadow = false })
		local sg = gui(sign, Enum.NormalId.Front, 40, 0.2, 90)
		label(sg, text, { TextColor3 = textColor or Color3.fromRGB(200, 20, 30), Size = UDim2.fromScale(0.94, 0.86), Position = UDim2.fromScale(0.03, 0.07) })
	end
	return { torso = torso, head = head, sign = sign }
end

return CityProps
