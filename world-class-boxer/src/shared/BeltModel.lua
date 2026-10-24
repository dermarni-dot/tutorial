-- BeltModel: a championship belt built from Parts (no assets): a leather strap, a centre plate in the design's
-- shape with a rim, an emblem and a name bar, side plates along the strap. One builder for every place a belt
-- shows: the trophy case (GymFacility), the ring walk (FightEngine: worn), the celebration cutscene (Ceremony:
-- strapped round the waist, then lifted overhead).
--
--   local m = BeltModel.Build(design, opts)
--     design = Tournaments.Design(key) (strap / plate / trim / jewel colours as {r, g, b}, shape, emblem, sides, label)
--     opts = {
--       mode = "display" (default: laid out in a gentle arc, the plate facing -Z) | "worn" (a loop round a waist),
--       waist = Vector3 (worn: the LowerTorso's size; the loop is fitted round it),
--       scale = number (display: 1 = a 1.4-stud plate; worn: picked from the waist),
--       cframe = CFrame (where BeltRoot goes), anchored = bool (default true), name = string,
--     }
--   -> Model with PrimaryPart "BeltRoot" (invisible, at the plate's centre / the loop's centre). Every other part is
--      welded to it (WeldConstraint): move the root (or weld it to a body part with anchored = false) and the belt
--      follows. Non-colliding, non-querying, massless.
local BeltModel = {}

local Typography = require(script.Parent:WaitForChild("Typography"))

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad

local function rgb(t, d)
	if typeof(t) == "Color3" then
		return t
	end
	if type(t) == "table" and tonumber(t[1]) then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return d
end

-- the design's colours with defaults (a plain gold-on-black belt)
local function colours(design)
	design = type(design) == "table" and design or {}
	return {
		strap = rgb(design.strap, Color3.fromRGB(20, 20, 22)),
		plate = rgb(design.plate, Color3.fromRGB(255, 208, 84)),
		trim = rgb(design.trim, Color3.fromRGB(180, 130, 30)),
		jewel = rgb(design.jewel, Color3.fromRGB(196, 30, 36)),
	}
end

local Builder = {}
Builder.__index = Builder

local function newBuilder(model, root, anchored)
	return setmetatable({ model = model, root = root, anchored = anchored, n = 0 }, Builder)
end

-- one part at `cf` (in the belt's local frame)
function Builder:part(name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.class or "Part")
	p.Name = name
	if opts.shape then
		p.Shape = opts.shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = opts.reflect or 0
	p.Transparency = opts.transparency or 0
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = opts.shadow ~= false
	p.Massless = true
	p.Anchored = self.anchored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = self.root.CFrame * cf
	p.Parent = self.model
	if not self.anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0 = self.root
		w.Part1 = p
		w.Parent = p
	end
	self.n += 1
	return p
end

-- a flat plate of `shape`, diameter d, thickness t, facing -Z at cf
function Builder:plate(name, shape, d, t, cf, color, material, reflect)
	local r = d / 2
	local o = { reflect = reflect }
	if shape == "hexagon" or shape == "octagon" then
		-- a regular 2n-gon = the union of n rectangles whose corners sit on its circle, turned 180/n apart
		local n = shape == "hexagon" and 3 or 4
		local half = math.pi / (2 * n)
		local w, h = 2 * r * math.cos(half), 2 * r * math.sin(half)
		for k = 0, n - 1 do
			self:part(name, V3(w, h, t), cf * ANG(0, 0, RAD(90) + k * math.pi / n), color, material, o)
		end
	elseif shape == "shield" then
		-- a square top and a diamond under it (its lower half is the point; a hair thinner, so the top's face wins)
		local top = d * 0.62
		self:part(name, V3(d * 0.92, top, t), cf * CF(0, d * 0.19, 0), color, material, o)
		local s = d * 0.92 / math.sqrt(2)
		self:part(name, V3(s, s, t * 0.96), cf * CF(0, d * 0.19 - top / 2, t * 0.02) * ANG(0, 0, RAD(45)), color, material, o)
	else
		-- round (and the crown's disc): a cylinder turned to face -Z
		self:part(name, V3(t, d, d), cf * ANG(0, RAD(90), 0), color, material, { shape = Enum.PartType.Cylinder, reflect = reflect })
	end
end

-- the emblem on the plate's face (cf = the face centre, facing -Z), size d
function Builder:emblem(kind, d, cf, c)
	local e = 0.04 * d
	local front = cf * CF(0, 0, -e)
	local metal = Enum.Material.Metal
	if kind == "glove" then
		self:part("Emblem", V3(d * 0.34, d * 0.34, d * 0.34), front * CF(0, d * 0.06, d * 0.08), c.jewel, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
		self:part("Emblem", V3(d * 0.22, d * 0.12, d * 0.1), front * CF(0, -d * 0.15, 0), c.trim, metal)
		self:part("Emblem", V3(d * 0.12, d * 0.14, d * 0.12), front * CF(d * 0.15, d * 0.02, -d * 0.02) * ANG(0, 0, RAD(-25)), c.jewel, Enum.Material.SmoothPlastic)
	elseif kind == "tower" then
		-- a city skyline: five towers of different heights on a base strip
		local hs = { 0.26, 0.4, 0.52, 0.34, 0.22 }
		for i, h in ipairs(hs) do
			local x = (i - 3) * d * 0.105
			self:part("Emblem", V3(d * 0.085, d * h, e * 2), front * CF(x, -d * 0.16 + d * h / 2, 0), c.trim, metal)
		end
		self:part("Emblem", V3(d * 0.6, d * 0.05, e * 2.4), front * CF(0, -d * 0.17, 0), c.jewel, Enum.Material.Neon)
	elseif kind == "star" then
		for k = 0, 4 do
			local a = RAD(90 + k * 72)
			self:part("Emblem", V3(d * 0.28, d * 0.09, e * 2), front * CF(math.cos(a) * d * 0.12, math.sin(a) * d * 0.12, 0) * ANG(0, 0, a), c.trim, metal, { reflect = 0.15 })
		end
		self:part("Emblem", V3(d * 0.16, d * 0.16, d * 0.16), front * CF(0, 0, 0), c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.2 })
	elseif kind == "laurel" then
		-- a wreath: two arcs of leaves round a jewel
		for _, side in ipairs({ -1, 1 }) do
			for k = 0, 5 do
				local a = RAD(-70 + k * 26)
				local x, y = side * math.cos(a) * d * 0.3, math.sin(a) * d * 0.3
				self:part("Emblem", V3(d * 0.06, d * 0.15, e * 2), front * CF(x, y, 0) * ANG(0, 0, side * (a - RAD(15))), c.trim, metal)
			end
		end
		self:part("Emblem", V3(d * 0.2, d * 0.2, d * 0.2), front, c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.25 })
	elseif kind == "globe" then
		self:part("Emblem", V3(d * 0.42, d * 0.42, d * 0.42), front * CF(0, 0, d * 0.1), c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.3 })
		self:part("Emblem", V3(d * 0.5, d * 0.035, e * 2), front * CF(0, 0, -d * 0.1), c.trim, metal)
		self:part("Emblem", V3(d * 0.035, d * 0.46, e * 2), front * CF(0, 0, -d * 0.1), c.trim, metal)
		self:part("Emblem", V3(d * 0.44, d * 0.03, e * 2), front * CF(0, d * 0.12, -d * 0.08), c.trim, metal)
		self:part("Emblem", V3(d * 0.44, d * 0.03, e * 2), front * CF(0, -d * 0.12, -d * 0.08), c.trim, metal)
	end
end

-- the centre plate: rim, plate, emblem, name bar (and the crown's points); cf = its centre, facing -Z
function Builder:centre(design, c, d, t, cf)
	local shape = design.shape or "round"
	local metal = Enum.Material.Metal
	local disc = shape == "crown" and "round" or shape
	-- the rim: the same shape, larger and behind
	self:plate("PlateRim", disc, d * 1.12, t * 0.7, cf * CF(0, 0, t * 0.4), c.trim, metal, 0.1)
	self:plate("Plate", disc, d, t, cf, c.plate, metal, 0.22)
	if shape == "crown" then
		-- the crown's points above the disc, a jewel on each
		for i = -1, 1 do
			local x = i * d * 0.3
			local s = d * (i == 0 and 0.3 or 0.22)
			local y = d * 0.5 + s * 0.2
			self:part("CrownPoint", V3(s, s, t * 0.9), cf * CF(x, y, t * 0.05) * ANG(0, 0, RAD(45)), c.plate, metal, { reflect = 0.22 })
			self:part("CrownJewel", V3(d * 0.08, d * 0.08, d * 0.08), cf * CF(x, y + s * 0.5, -t * 0.4), c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.3 })
		end
	end
	local face = cf * CF(0, 0, -t / 2)
	self:emblem(design.emblem or "star", d, face * CF(0, d * 0.06, 0), c)
	-- the name bar across the plate's lower part
	local bar = self:part("NameBar", V3(d * 0.66, d * 0.12, t * 0.3), face * CF(0, -d * 0.32, -t * 0.12), c.strap, Enum.Material.SmoothPlastic)
	if design.label and design.label ~= "" then
		local ok = pcall(function()
			local sg = Instance.new("SurfaceGui")
			sg.Name = "Label"
			sg.Face = Enum.NormalId.Front
			sg.CanvasSize = Vector2.new(220, 40)
			sg.LightInfluence = 0.4
			sg.Parent = bar
			local tl = Instance.new("TextLabel")
			tl.BackgroundTransparency = 1
			tl.Size = UDim2.fromScale(1, 1)
			Typography.Apply(tl, "plate")
			tl.TextScaled = true
			tl.TextColor3 = c.plate
			tl.Text = tostring(design.label)
			tl.Parent = sg
		end)
		if not ok then
			bar.Name = "NameBar"
		end
	end
	-- jewels at the plate's four quarters
	for k = 0, 3 do
		local a = RAD(45 + k * 90)
		self:part("PlateJewel", V3(d * 0.07, d * 0.07, d * 0.07), face * CF(math.cos(a) * d * 0.4, math.sin(a) * d * 0.4, -t * 0.05), c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.3 })
	end
end

-- a side plate (cf = its centre, facing -Z)
function Builder:side(design, c, s, t, cf)
	local shape = design.shape == "crown" and "round" or (design.shape or "round")
	self:plate("SidePlate", shape, s, t * 0.8, cf, c.trim, Enum.Material.Metal, 0.12)
	self:part("SideJewel", V3(s * 0.28, s * 0.28, s * 0.28), cf * CF(0, 0, -t * 0.4), c.jewel, Enum.Material.Glass, { shape = Enum.PartType.Ball, reflect = 0.3 })
end

-- a strap segment along the X axis of cf: leather with piping (the trim colour, a touch taller, behind it)
function Builder:strap(c, len, h, t, cf)
	self:part("Strap", V3(len, h, t), cf, c.strap, Enum.Material.Leather)
	self:part("Piping", V3(len, h * 1.12, t * 0.6), cf * CF(0, 0, t * 0.35), c.trim, Enum.Material.Metal)
end

function BeltModel.Build(design, opts)
	opts = type(opts) == "table" and opts or {}
	design = type(design) == "table" and design or {}
	local c = colours(design)
	local anchored = opts.anchored ~= false
	local model = Instance.new("Model")
	model.Name = opts.name or "Belt"
	local root = Instance.new("Part")
	root.Name = "BeltRoot"
	root.Size = V3(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Anchored = anchored
	root.CFrame = typeof(opts.cframe) == "CFrame" and opts.cframe or CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	local B = newBuilder(model, root, anchored)
	local sides = math.clamp(math.floor(tonumber(design.sides) or 2), 0, 4)
	if opts.mode == "worn" then
		local waist = typeof(opts.waist) == "Vector3" and opts.waist or V3(1.6, 0.52, 0.97)
		local w, dd = waist.X, waist.Z
		local h = math.clamp(waist.Y * 0.9, 0.36, 0.62)
		local t = 0.07
		local gap = 0.025
		local d = math.clamp(w * 0.62, 0.7, 1.15)
		local zf = -(dd / 2 + gap + t / 2)
		-- the loop: front (either side of the plate), back, sides
		local frontLen = (w + 2 * (gap + t)) / 2
		for _, sx in ipairs({ -1, 1 }) do
			B:strap(c, frontLen, h, t, CF(sx * frontLen / 2, 0, zf))
			B:strap(c, dd + 2 * gap, h, t, CF(sx * (w / 2 + gap + t / 2), 0, 0) * ANG(0, RAD(90 * sx), 0))
		end
		B:strap(c, w + 2 * (gap + t), h, t, CF(0, 0, -zf) * ANG(0, RAD(180), 0))
		local pt = 0.09
		B:centre(design, c, d, pt, CF(0, 0, zf - t / 2 - pt / 2))
		local s = math.min(h * 0.85, d * 0.42)
		for k = 1, math.min(sides, 2) do
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (d * 0.55 + s * (k - 0.5) * 1.1)
				if math.abs(x) + s / 2 < w / 2 + gap + t then
					B:side(design, c, s, pt * 0.8, CF(x, 0, zf - t / 2 - pt * 0.4))
				end
			end
		end
	else
		local k = tonumber(opts.scale) or 1
		local d = 1.4 * k
		local t = 0.14 * k
		local h = 0.82 * k
		local st = 0.1 * k
		-- the strap: a gentle arc bending back from the plate, eight segments a side
		local arcR = 4.2 * k
		local seg = 0.46 * k
		local n = 8
		local function along(x)
			local a = x / arcR
			return CF(math.sin(a) * arcR, 0, (1 - math.cos(a)) * arcR + st / 2) * ANG(0, -a, 0)
		end
		for _, sx in ipairs({ -1, 1 }) do
			for i = 1, n do
				local x = sx * (d * 0.3 + (i - 0.5) * seg)
				B:strap(c, seg * 1.04, h, st, along(x))
			end
		end
		B:centre(design, c, d, t, CF(0, 0, -t / 2))
		local s = h * 0.8
		for i = 1, sides do
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (d * 0.62 + (i - 0.5) * s * 1.25)
				B:side(design, c, s, t, along(x) * CF(0, 0, -st / 2 - t * 0.4))
			end
		end
		-- the buckle end and a few strap holes at the far ends
		for _, sx in ipairs({ -1, 1 }) do
			B:part("StrapEnd", V3(seg * 0.5, h * 0.96, st * 1.1), along(sx * (d * 0.3 + n * seg + seg * 0.1)), c.trim, Enum.Material.Metal)
		end
	end
	model:SetAttribute("Parts", B.n + 1)
	return model
end

-- the part count a design builds (tests / budgets)
function BeltModel.Count(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return BeltModel
