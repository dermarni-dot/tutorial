-- DetailKit: the building blocks of the world's client-side detail layer (WorldDetail: the gym and the city;
-- VenueDetail: the fight venues; MenuStage's extra set dressing).
--   * part builders with the detail layer's defaults: anchored, no collision, no queries (camera / mouse rays
--     and the fight camera pass straight through), no touches, and no shadow unless the piece is big (>= 4
--     studs) or asked for. Detail never changes what anyone can walk into, stand on or click.
--   * SurfaceGui text / frames, the WCB emblem (IconData.logo) and the uploaded textures (WorldAssetData)
--   * templates: a prop built once and cloned (Clone + PivotTo) wherever it repeats
--   * Streamer: cells of detail, each with up to three tiers, shown by the Graphics level and the camera's
--     distance (see Streamer below), built lazily the first time they are wanted and kept for re-use
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Typography = require(Shared:WaitForChild("Typography"))

local function optionalShared(name)
	local m = Shared:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and type(mod) == "table" and mod or nil
end
local WorldAssetData = optionalShared("WorldAssetData")
local IconData = optionalShared("IconData")

local K = {}

local V3, CF = Vector3.new, CFrame.new
K.V3, K.CF, K.A = V3, CF, CFrame.Angles
K.RAD = math.rad
K.M = Enum.Material
K.FACE = Enum.NormalId

function K.rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local rgb = K.rgb

-- the WCB palette (src/shared/UI.lua Theme) and the world's common colours
K.C = {
	ink = rgb(11, 15, 23), ink2 = rgb(22, 28, 39), gold = rgb(255, 205, 83), goldDeep = rgb(208, 148, 43), goldLight = rgb(255, 232, 160),
	red = rgb(243, 65, 76), redDeep = rgb(150, 18, 30), blue = rgb(58, 142, 255), blueDeep = rgb(24, 80, 190), white = rgb(242, 244, 248),
	steel = rgb(120, 124, 132), steelDark = rgb(60, 62, 68), steelLight = rgb(178, 182, 190), chrome = rgb(205, 208, 214),
	black = rgb(18, 18, 22), rubber = rgb(30, 30, 33), wood = rgb(122, 88, 60), woodDark = rgb(78, 54, 36), brass = rgb(196, 160, 80),
	paper = rgb(236, 230, 214), concrete = rgb(150, 148, 142), yellow = rgb(250, 200, 40), green = rgb(40, 150, 80),
}
local C = K.C

-- shadows: a detail part casts one only when it is big enough to read in a shadow map
K.SHADOW_MIN = 4

local count = 0 -- parts made (the sim's counter; cheap)
function K.Count()
	return count
end

-- a Streamer tier built in a job of the client's time slicer (FrameBudget): the builders below hand the frame back
-- between pieces in that job's thread only ([thread] = the slicer; everywhere else they run straight through)
local slicing = setmetatable({}, { __mode = "k" })
local function tick()
	local fb = slicing[coroutine.running()]
	if fb then
		fb.Tick()
	end
end
K.Tick = tick -- (a tier's own long loops: a scan of the server's street)

-- p = K.Part(parent, name, size, cf, color, material, opts)
-- opts: shape ("Ball" | "Cylinder"), t (Transparency), refl, shadow (true / false; default by size),
-- collide (true: the rare detail piece that must block), class ("WedgePart"), attrs
function K.Part(parent, name, size, cf, color, material, opts)
	tick()
	local cls = opts and opts.class or "Part"
	local p = Instance.new(cls)
	p.Name = name
	p.Anchored = true
	p.CanCollide = opts ~= nil and opts.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts and opts.shape and cls == "Part" then
		p.Shape = Enum.PartType[opts.shape]
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color or C.steel
	p.Material = material or Enum.Material.SmoothPlastic
	local shadow = opts and opts.shadow
	if shadow == nil then
		shadow = math.max(size.X, size.Y, size.Z) >= K.SHADOW_MIN
	end
	p.CastShadow = shadow
	if opts then
		if opts.t then
			p.Transparency = opts.t
		end
		if opts.refl then
			p.Reflectance = opts.refl
		end
		if opts.attrs then
			for k, v in pairs(opts.attrs) do
				p:SetAttribute(k, v)
			end
		end
	end
	p.Parent = parent
	count += 1
	return p
end
local Part = K.Part

-- a cylinder along cf's X axis
function K.Cyl(parent, name, len, dia, cf, color, material, opts)
	opts = opts or {}
	opts.shape = "Cylinder"
	return Part(parent, name, V3(len, dia, dia), cf, color, material, opts)
end

-- an upright cylinder whose base centre is at pos (Vector3) or a CFrame (its rotation kept)
function K.VCyl(parent, name, h, dia, at, color, material, opts)
	local base = typeof(at) == "CFrame" and at or CF(at)
	opts = opts or {}
	opts.shape = "Cylinder"
	return Part(parent, name, V3(h, dia, dia), base * CF(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material, opts)
end

-- a cylinder (or a box with opts.box) between two points
function K.Rod(parent, name, a, b, dia, color, material, opts)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local up = math.abs(d.Unit.Y) > 0.99 and V3(0, 0, 1) or V3(0, 1, 0)
	local cf = CFrame.lookAt(mid, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	if opts and opts.box then
		return Part(parent, name, V3(len, dia, opts.depth or dia), cf, color, material, opts)
	end
	return K.Cyl(parent, name, len, dia, cf, color, material, opts)
end

function K.Ball(parent, name, d, cf, color, material, opts)
	opts = opts or {}
	opts.shape = "Ball"
	local size = typeof(d) == "Vector3" and d or V3(d, d, d)
	if typeof(d) == "Vector3" then
		-- an ellipsoid: a block with a sphere mesh
		opts.shape = nil
		local p = Part(parent, name, size, typeof(cf) == "CFrame" and cf or CF(cf), color, material, opts)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		return p
	end
	return Part(parent, name, size, typeof(cf) == "CFrame" and cf or CF(cf), color, material, opts)
end

function K.Wedge(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	opts.class = "WedgePart"
	return Part(parent, name, size, cf, color, material, opts)
end

function K.Model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function K.Folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

------------------------------------------------------------------------
-- signs, emblem, textures
------------------------------------------------------------------------
-- a SurfaceGui on a face. light = LightInfluence (0 = glows), pps = pixels per stud (scale-only layouts, so
-- WorldLOD may lower it on the low levels)
function K.Gui(p, face, pps, light, maxDist)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DetailSign"
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or 30
	sg.LightInfluence = light or 1
	sg.MaxDistance = maxDist or 0
	sg.Parent = p
	return sg
end

function K.Frame(parent, props)
	tick()
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function K.Text(parent, text, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Size = UDim2.fromScale(1, 1)
	Typography.Apply(t, "sign")
	t.TextScaled = true
	t.TextColor3 = C.white
	t.Text = text
	for k, v in pairs(props or {}) do
		if k == "Face" then
			Typography.Apply(t, v)
		else
			t[k] = v
		end
	end
	t.Parent = parent
	return t
end

-- a whole face as a sign: background colour + one line (or \n lines) of text
function K.Sign(p, face, text, fg, bg, pps, font, light)
	local sg = K.Gui(p, face, pps or 30, light)
	if bg then
		K.Frame(sg, { BackgroundColor3 = bg })
	end
	K.Text(sg, text, { TextColor3 = fg or C.white, Face = font or "sign", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) })
	return sg
end

-- the WCB emblem (the gold-framed glove badge of the title logo) as an ImageLabel; nil when the logo is not
-- uploaded. x, y, w, h = where on the parent (scale)
local EMBLEM_RECT = { 14, 112, 292, 292 } -- inside the logo's colour rect (1024 x 512)
function K.Emblem(parent, x, y, w, h, transp)
	local logo = IconData and IconData.logo
	if not (logo and type(logo.id) == "number" and logo.id > 0) then
		return nil
	end
	local im = Instance.new("ImageLabel")
	im.Name = "Emblem"
	im.BackgroundTransparency = 1
	im.Image = "rbxassetid://" .. logo.id
	im.ImageRectOffset = Vector2.new(logo.colour.x + EMBLEM_RECT[1], logo.colour.y + EMBLEM_RECT[2])
	im.ImageRectSize = Vector2.new(EMBLEM_RECT[3], EMBLEM_RECT[4])
	im.ScaleType = Enum.ScaleType.Fit
	im.Size = UDim2.fromScale(w or 1, h or 1)
	im.Position = UDim2.fromScale(x or 0, y or 0)
	im.ImageTransparency = transp or 0
	im.Parent = parent
	return im
end

-- an uploaded image (WorldAssetData key) -> "rbxassetid://..." or nil (not uploaded / not approved)
function K.Asset(key)
	return WorldAssetData and WorldAssetData.Id and WorldAssetData.Id(key) or nil
end

-- a Decal of an uploaded image on a face (nil when the image is not available: callers keep a fallback)
function K.Decal(p, face, key, props)
	local id = K.Asset(key)
	if not id then
		return nil
	end
	local d = Instance.new("Decal")
	d.Name = "DetailDecal"
	d.Face = face or Enum.NormalId.Top
	d.Texture = id
	for k, v in pairs(props or {}) do
		d[k] = v
	end
	d.Parent = p
	return d
end

-- a tiled Texture of an uploaded image on a face (studs per tile u, v)
function K.Texture(p, face, key, su, sv, props)
	local id = K.Asset(key)
	if not id then
		return nil
	end
	local t = Instance.new("Texture")
	t.Name = "DetailTexture"
	t.Face = face or Enum.NormalId.Top
	t.Texture = id
	t.StudsPerTileU = su or 8
	t.StudsPerTileV = sv or su or 8
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	t.Parent = p
	return t
end

-- a flat decal patch lying on a surface: an invisible thin part carrying the Decal on its top face.
-- cf = the patch centre on the surface, its Y axis the surface normal
function K.Patch(parent, name, w, l, cf, key, color, transp)
	local id = K.Asset(key)
	if not id then
		return nil
	end
	local p = Part(parent, name, V3(w, 0.05, l), cf * CF(0, 0.03, 0), C.black, Enum.Material.SmoothPlastic, { t = 1, shadow = false })
	K.Decal(p, Enum.NormalId.Top, key, { Color3 = color or Color3.new(1, 1, 1), Transparency = transp or 0 })
	return p
end

-- a poster of an uploaded image on a wall (cf: the poster's centre, its -Z facing the room); w x h studs.
-- Without the image a printed fallback (title text on a colour) stands in
function K.Poster(parent, key, w, h, cf, fallback, frameColor)
	local p = Part(parent, "DetailPoster", V3(w, h, 0.06), cf, C.paper, Enum.Material.SmoothPlastic, { shadow = false })
	if not K.Decal(p, Enum.NormalId.Front, key) then
		local fb = fallback or {}
		K.Sign(p, Enum.NormalId.Front, fb.text or "WCB", fb.fg or C.gold, fb.bg or C.ink, 24, "sign")
	end
	if frameColor then
		Part(parent, "PosterFrame", V3(w + 0.3, h + 0.3, 0.05), cf * CF(0, 0, 0.05), frameColor, Enum.Material.Metal, { shadow = false })
	end
	return p
end

------------------------------------------------------------------------
-- templates
------------------------------------------------------------------------
local templates = {}
-- K.Template(name, build) -> a Model built once by build(model) (pivot at its origin) and kept out of the world
function K.Template(name, build)
	local t = templates[name]
	if t then
		return t
	end
	t = Instance.new("Model")
	t.Name = name
	build(t)
	t.WorldPivot = CF()
	templates[name] = t
	return t
end

-- a copy of a template at cf, parented
function K.Place(template, parent, cf, name)
	tick()
	local c = template:Clone()
	if not c then
		return nil
	end
	c:PivotTo(cf)
	if name then
		c.Name = name
	end
	c.Parent = parent
	-- (each clone's parts count as made)
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return c
end

------------------------------------------------------------------------
-- Streamer: detail cells by Graphics level and camera distance
------------------------------------------------------------------------
-- A cell = { name, centre (Vector3), radius, tiers = { [1] = fn(model), [2] = fn, [3] = fn } }. Tier 1 holds
-- the pieces that read from afar and are cheap (textures, big signs, a few props), tier 2 the main dressing,
-- tier 3 the fine detail. A tier shows when the level allows it (Low: tier 1, Medium: 1-2, High: 1-3) and the
-- camera is within DIST[tier][level] studs of the cell's edge; it hides again past that distance x 1.2. A tier is
-- built the first time it is wanted (spread over frames: at most BUDGET seconds a step) and kept while hidden
-- (unparented), so walking back and forth costs nothing.
local Streamer = {}
Streamer.__index = Streamer
K.Streamer = Streamer

Streamer.DIST = {
	{ 260, 420, 600 }, -- tier 1 at Low, Medium, High
	{ 0, 200, 320 }, -- tier 2
	{ 0, 0, 170 }, -- tier 3
}
Streamer.BUDGET = 0.004 -- seconds of building per step

function Streamer.new(root)
	return setmetatable({ root = root, cells = {}, level = 3 }, Streamer)
end

function Streamer:Add(name, centre, radius, tiers)
	local cell = { name = name, centre = centre, radius = radius or 30, tiers = tiers, models = {}, shown = {} }
	table.insert(self.cells, cell)
	return cell
end

local function build(self, cell, t)
	local m = Instance.new("Model")
	m.Name = cell.name .. "_T" .. t
	local ok, err = pcall(cell.tiers[t], m)
	if not ok then
		warn("[DetailKit] " .. cell.name .. " tier " .. t .. ": " .. tostring(err))
	end
	cell.models[t] = m
	return m
end

local function wantedDist(self, t)
	local row = Streamer.DIST[t]
	return row and row[math.clamp(self.level, 1, 3)] or 0
end

-- budget (Step's): the tiers to build go into one job of the client's time slicer (FrameBudget), built a piece at a
-- time in its shared frame budget (one tier is up to ~40 ms of building: a whole one in a pass was a hitch) and shown
-- by the pass after they are done
local function queueBuild(self, cell, t, budget)
	cell.queued = cell.queued or {}
	if cell.queued[t] then
		return
	end
	cell.queued[t] = true
	self.pending = self.pending or {}
	table.insert(self.pending, { cell, t })
	if self.job and budget.Busy(self.job) then
		return
	end
	-- one tier a job, the next one queued behind whatever else waits (the Creator's pages, a venue): the streaming
	-- never holds the slicer's queue for long
	local function run()
		local co = coroutine.running()
		slicing[co] = budget
		local q = table.remove(self.pending, 1)
		if q then
			local c, tier = q[1], q[2]
			if not c.models[tier] and wantedDist(self, tier) > 0 then
				build(self, c, tier)
			end
			if c.queued then
				c.queued[tier] = nil
			end
		end
		slicing[co] = nil
		if self.pending[1] then
			self.job = budget.Run(run, false, "WorldDetail " .. self.root.Name)
		end
	end
	self.job = budget.Run(run, false, "WorldDetail " .. self.root.Name)
end

-- one pass: camPos = the camera position (nil = everything in range); returns the number of tiers built. budget
-- (optional): FrameBudget, the tiers not built yet are built behind the frames (queueBuild) instead of in the pass
function Streamer:Step(camPos, level, budget)
	self.level = level or self.level
	local t0 = os.clock()
	local built = 0
	for _, cell in ipairs(self.cells) do
		local d = camPos and math.max(0, (camPos - cell.centre).Magnitude - cell.radius) or 0
		for t = 1, 3 do
			if cell.tiers[t] then
				local maxD = wantedDist(self, t)
				local want
				if cell.shown[t] then
					want = maxD > 0 and d <= maxD * 1.2
				else
					want = maxD > 0 and d <= maxD
				end
				if want and not cell.shown[t] then
					local m = cell.models[t]
					if not m then
						if budget then
							queueBuild(self, cell, t, budget)
							want = false
						elseif os.clock() - t0 > Streamer.BUDGET and built > 0 then
							-- out of time this step: the rest comes next step
							want = false
						else
							m = build(self, cell, t)
							built += 1
						end
					end
					if want then
						m.Parent = self.root
						cell.shown[t] = true
					end
				elseif not want and cell.shown[t] then
					local m = cell.models[t]
					if m then
						m.Parent = nil
					end
					cell.shown[t] = false
				end
			end
		end
	end
	return built
end

-- everything the level allows, at once (the simulator and the previews)
function Streamer:BuildAll(level)
	self.level = level or self.level
	for _, cell in ipairs(self.cells) do
		for t = 1, math.clamp(self.level, 1, 3) do
			if cell.tiers[t] then
				local m = cell.models[t] or build(self, cell, t)
				m.Parent = self.root
				cell.shown[t] = true
			end
		end
	end
end

-- drop every built tier (a level change that frees memory, Stop)
function Streamer:Clear()
	if self.job and self.pending then
		table.clear(self.pending)
	end
	for _, cell in ipairs(self.cells) do
		cell.queued = nil
		for t, m in pairs(cell.models) do
			m:Destroy()
			cell.models[t] = nil
			cell.shown[t] = false
		end
	end
end

-- parts / instances currently shown (for the profiler and tests)
function Streamer:Stats()
	local parts, inst, shown = 0, 0, 0
	for _, cell in ipairs(self.cells) do
		for t, m in pairs(cell.models) do
			if cell.shown[t] and m.Parent then
				shown += 1
				for _, d in ipairs(m:GetDescendants()) do
					inst += 1
					if d:IsA("BasePart") then
						parts += 1
					end
				end
			end
		end
	end
	return { parts = parts, instances = inst, tiers = shown, cells = #self.cells }
end

return K
