-- BodyMap: an anatomical body map (front + back views), one region per Config.MuscleParts id.
-- Training shows the muscles an exercise works (Config.ExerciseTargets / act.parts), the session
-- result the growth each muscle got, the Body tab how far each muscle is developed toward the
-- frame's potential (dark = untrained, gold = at the potential).
--
-- The figure is painted into an EditableImage: a smooth silhouette (a soft union of the body's
-- pieces, anti-aliased) with shaded muscle bellies. Where EditableImage is unavailable (the
-- experience's mesh / image APIs off, the memory budget spent) it falls back to plain Frames.
--   local map = BodyMap.new(parent, { Size = UDim2.fromOffset(300, 340), views = "both", legend = true })
--   map:SetTargets(act.parts, color)   map:SetGrowth(result.parts)   map:SetDevelopment(P.body, cap)
--   map:Lit() -> { { id, w } } strongest first      map:Pulse()      BodyMap.Short(id) -> "Pecs"
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local UI = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"))
local T = UI.Theme

local BodyMap = {}
BodyMap.__index = BodyMap

local SKIN = Color3.fromRGB(46, 51, 64) -- the silhouette
local MUSCLE = Color3.fromRGB(70, 77, 96) -- an idle muscle
local EDGE = Color3.fromRGB(96, 104, 126)

-- short names for labels and lists (Config's names are long: "Chest (Lower/Mid Pecs)")
BodyMap.ShortNames = {
	pecs = "Pecs", upperChest = "Upper Chest", frontDelt = "Front Delts", sideDelt = "Side Delts", rearDelt = "Rear Delts",
	biceps = "Biceps", triceps = "Triceps", forearms = "Forearms", lats = "Lats", traps = "Traps", upperBack = "Upper Back",
	lowerBack = "Lower Back", abs = "Abs", lowerAbs = "Lower Abs", obliques = "Obliques", serratus = "Serratus",
	quads = "Quads", hamstrings = "Hamstrings", glutes = "Glutes", calves = "Calves", neckSCM = "Neck",
}
function BodyMap.Short(id)
	return BodyMap.ShortNames[id] or tostring(id)
end

-- development colour: dark slate (untrained) through muscle red to gold at the frame's potential
local DEV_STOPS = {
	{ 0, Color3.fromRGB(52, 57, 72) }, { 0.25, Color3.fromRGB(112, 64, 70) }, { 0.5, Color3.fromRGB(196, 84, 64) },
	{ 0.75, Color3.fromRGB(240, 140, 70) }, { 1, Color3.fromRGB(255, 212, 118) },
}
function BodyMap.DevColor(f)
	f = math.clamp(tonumber(f) or 0, 0, 1)
	for i = 2, #DEV_STOPS do
		local a, b = DEV_STOPS[i - 1], DEV_STOPS[i]
		if f <= b[1] then
			return a[2]:Lerp(b[2], (f - a[1]) / (b[1] - a[1]))
		end
	end
	return DEV_STOPS[#DEV_STOPS][2]
end

-- silhouette pieces: { x, y, w, h, rot } in view fractions (x of width, y of height)
local BODY = {
	{ 0.5, 0.075, 0.2, 0.1, 0, "head" }, { 0.5, 0.145, 0.13, 0.05, 0 },
	{ 0.5, 0.235, 0.56, 0.15, 0 }, { 0.5, 0.35, 0.4, 0.12, 0 }, { 0.5, 0.455, 0.42, 0.1, 0 },
	{ 0.235, 0.27, 0.11, 0.17, 4 }, { 0.765, 0.27, 0.11, 0.17, -4 }, -- upper arms
	{ 0.2, 0.405, 0.09, 0.14, 6 }, { 0.8, 0.405, 0.09, 0.14, -6 }, -- forearms
	{ 0.185, 0.5, 0.08, 0.06, 6, "hand" }, { 0.815, 0.5, 0.08, 0.06, -6, "hand" },
	{ 0.41, 0.61, 0.17, 0.24, 2 }, { 0.59, 0.61, 0.17, 0.24, -2 }, -- thighs
	{ 0.405, 0.825, 0.12, 0.2, 0 }, { 0.595, 0.825, 0.12, 0.2, 0 }, -- shins
	{ 0.4, 0.95, 0.12, 0.04, 0, "foot" }, { 0.6, 0.95, 0.12, 0.04, 0, "foot" },
}

-- muscle regions per view: { part, x, y, w, h, rot }
local FRONT = {
	{ "neckSCM", 0.46, 0.15, 0.04, 0.045, 18 }, { "neckSCM", 0.54, 0.15, 0.04, 0.045, -18 },
	{ "traps", 0.385, 0.172, 0.13, 0.03, -16 }, { "traps", 0.615, 0.172, 0.13, 0.03, 16 },
	{ "frontDelt", 0.285, 0.205, 0.1, 0.075, 0 }, { "frontDelt", 0.715, 0.205, 0.1, 0.075, 0 },
	{ "sideDelt", 0.215, 0.215, 0.065, 0.08, 6 }, { "sideDelt", 0.785, 0.215, 0.065, 0.08, -6 },
	{ "upperChest", 0.42, 0.203, 0.15, 0.04, 0 }, { "upperChest", 0.58, 0.203, 0.15, 0.04, 0 },
	{ "pecs", 0.42, 0.248, 0.16, 0.062, 0 }, { "pecs", 0.58, 0.248, 0.16, 0.062, 0 },
	{ "serratus", 0.34, 0.3, 0.045, 0.06, 0 }, { "serratus", 0.66, 0.3, 0.045, 0.06, 0 },
	{ "biceps", 0.232, 0.29, 0.08, 0.1, 4 }, { "biceps", 0.768, 0.29, 0.08, 0.1, -4 },
	{ "forearms", 0.198, 0.405, 0.072, 0.12, 6 }, { "forearms", 0.802, 0.405, 0.072, 0.12, -6 },
	{ "abs", 0.465, 0.298, 0.06, 0.03, 0 }, { "abs", 0.535, 0.298, 0.06, 0.03, 0 },
	{ "abs", 0.465, 0.334, 0.06, 0.03, 0 }, { "abs", 0.535, 0.334, 0.06, 0.03, 0 },
	{ "abs", 0.465, 0.37, 0.06, 0.03, 0 }, { "abs", 0.535, 0.37, 0.06, 0.03, 0 },
	{ "obliques", 0.39, 0.36, 0.05, 0.1, 6 }, { "obliques", 0.61, 0.36, 0.05, 0.1, -6 },
	{ "lowerAbs", 0.5, 0.42, 0.11, 0.05, 0 },
	{ "quads", 0.41, 0.6, 0.14, 0.2, 2 }, { "quads", 0.59, 0.6, 0.14, 0.2, -2 },
	{ "calves", 0.395, 0.82, 0.07, 0.13, 0 }, { "calves", 0.605, 0.82, 0.07, 0.13, 0 },
}
local BACK = {
	{ "traps", 0.5, 0.18, 0.3, 0.06, 0 }, { "traps", 0.5, 0.235, 0.1, 0.07, 0 },
	{ "rearDelt", 0.25, 0.208, 0.1, 0.07, 0 }, { "rearDelt", 0.75, 0.208, 0.1, 0.07, 0 },
	{ "upperBack", 0.4, 0.24, 0.12, 0.045, -10 }, { "upperBack", 0.6, 0.24, 0.12, 0.045, 10 },
	{ "lats", 0.375, 0.305, 0.13, 0.15, 10 }, { "lats", 0.625, 0.305, 0.13, 0.15, -10 },
	{ "lowerBack", 0.465, 0.4, 0.05, 0.1, 0 }, { "lowerBack", 0.535, 0.4, 0.05, 0.1, 0 },
	{ "triceps", 0.232, 0.29, 0.08, 0.1, 4 }, { "triceps", 0.768, 0.29, 0.08, 0.1, -4 },
	{ "forearms", 0.198, 0.405, 0.072, 0.12, 6 }, { "forearms", 0.802, 0.405, 0.072, 0.12, -6 },
	{ "glutes", 0.43, 0.5, 0.14, 0.085, 0 }, { "glutes", 0.57, 0.5, 0.14, 0.085, 0 },
	{ "hamstrings", 0.41, 0.625, 0.13, 0.17, 2 }, { "hamstrings", 0.59, 0.625, 0.13, 0.17, -2 },
	{ "calves", 0.408, 0.815, 0.1, 0.14, 0 }, { "calves", 0.592, 0.815, 0.1, 0.14, 0 },
}

-- every part of the figure (ids)
local ALL_IDS = {}
do
	local seen = {}
	for _, list in ipairs({ FRONT, BACK }) do
		for _, spec in ipairs(list) do
			if not seen[spec[1]] then
				seen[spec[1]] = true
				table.insert(ALL_IDS, spec[1])
			end
		end
	end
end
BodyMap.Parts = ALL_IDS

------------------------------------------------------------------------
-- The painted figure (EditableImage)
------------------------------------------------------------------------
-- A mask per image size is computed once (signed distances: the body as a smooth union of its
-- pieces, every muscle region an ellipse) and kept: per pixel the body coverage, the region on top,
-- its coverage and a shade (lit from above, darker at the muscle's edge). Colouring is one pass over it.
local DENSITY = 1.25 -- image pixels per design pixel (crisp at 1080p)
local MAX_SIDE = 1024
local masks = {} -- [key] = mask

local function smin(a, b, k)
	local h = math.clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b + (a - b) * h - k * h * (1 - h)
end

-- the axis-aligned box a rotated w x h rectangle centred at (cx, cy) covers, plus a margin
local function bbox(cx, cy, hw, hh, rot, margin, W, H)
	local c, s = math.abs(math.cos(rot)), math.abs(math.sin(rot))
	local ex, ey = hw * c + hh * s + margin, hw * s + hh * c + margin
	return math.max(0, math.floor(cx - ex)), math.min(W - 1, math.ceil(cx + ex)), math.max(0, math.floor(cy - ey)), math.min(H - 1, math.ceil(cy + ey))
end

-- builds (or returns the cached) mask for a W x H image px figure; views = "both" | "front" | "back".
-- yielding = true spreads the work over frames (about 6 ms a frame); a second caller for the same
-- size waits for the first build instead of starting another
local BUILDING = {}
local computeMask
local function buildMask(W, H, views, yielding)
	local key = string.format("%dx%d:%s", W, H, views)
	while masks[key] == BUILDING do
		task.wait()
	end
	if masks[key] then
		return masks[key]
	end
	masks[key] = BUILDING
	local t0 = os.clock()
	local function breathe()
		if yielding and os.clock() - t0 > 0.006 then
			task.wait()
			t0 = os.clock()
		end
	end
	local ok, mask = pcall(computeMask, W, H, views, breathe)
	masks[key] = ok and mask or nil
	if not ok then
		error(mask, 0)
	end
	return mask
end

function computeMask(W, H, views, breathe)
	local n = W * H
	local dist = buffer.create(n * 4)
	for i = 0, n - 1 do
		buffer.writef32(dist, i * 4, 1e6)
	end
	local regionId = buffer.create(n)
	local regionCov = buffer.create(n)
	local shade = buffer.create(n)
	local regions = {} -- index -> part id
	local list = {}
	if views == "both" then
		local vw = math.floor(W / 2)
		list = { { FRONT, 0, vw }, { BACK, W - vw, vw } }
	elseif views == "back" then
		list = { { BACK, 0, W } }
	else
		list = { { FRONT, 0, W } }
	end
	local vh = H
	-- the silhouette: a soft union of the pieces (k = how much they melt together)
	for _, v in ipairs(list) do
		local vx, vw = v[2], v[3]
		local k = 0.045 * vw
		for _, b in ipairs(BODY) do
			local cx, cy = vx + b[1] * vw, b[2] * vh
			local hw, hh = b[3] * vw / 2, b[4] * vh / 2
			local r = math.min(hw, hh)
			local rot = math.rad(b[5] or 0)
			local cr, sr = math.cos(rot), math.sin(rot)
			local x0, x1, y0, y1 = bbox(cx, cy, hw, hh, rot, k + 1, W, H)
			for y = y0, y1 do
				local dy = y + 0.5 - cy
				for x = x0, x1 do
					local dx = x + 0.5 - cx
					-- into the piece's frame
					local lx, ly = math.abs(dx * cr + dy * sr), math.abs(-dx * sr + dy * cr)
					local qx, qy = lx - hw + r, ly - hh + r
					local d = math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2) + math.min(math.max(qx, qy), 0) - r
					local o = (y * W + x) * 4
					buffer.writef32(dist, o, smin(buffer.readf32(dist, o), d, k))
				end
			end
			breathe()
		end
	end
	-- muscle bellies: ellipses inside the silhouette, the strongest coverage wins a pixel
	for _, v in ipairs(list) do
		local vx, vw = v[2], v[3]
		for _, spec in ipairs(v[1]) do
			table.insert(regions, spec[1])
			local idx = #regions
			local cx, cy = vx + spec[2] * vw, spec[3] * vh
			local a, b = math.max(1, spec[4] * vw / 2), math.max(1, spec[5] * vh / 2)
			local rot = math.rad(spec[6] or 0)
			local cr, sr = math.cos(rot), math.sin(rot)
			local minor = math.min(a, b)
			local x0, x1, y0, y1 = bbox(cx, cy, a, b, rot, 1.5, W, H)
			for y = y0, y1 do
				local dy = y + 0.5 - cy
				for x = x0, x1 do
					local dx = x + 0.5 - cx
					local lx, ly = dx * cr + dy * sr, -dx * sr + dy * cr
					-- approximate ellipse distance (k0 (k0 - 1) / k1)
					local px, py = lx / a, ly / b
					local k0 = math.sqrt(px * px + py * py)
					local k1 = math.sqrt((lx / (a * a)) ^ 2 + (ly / (b * b)) ^ 2)
					local d = k1 > 1e-6 and k0 * (k0 - 1) / k1 or -minor
					local cov = math.clamp(0.5 - d, 0, 1)
					if cov > 0 then
						local i = y * W + x
						local c8 = math.floor(cov * 255 + 0.5)
						if c8 > buffer.readu8(regionCov, i) then
							buffer.writeu8(regionCov, i, c8)
							buffer.writeu8(regionId, i, idx)
							-- volume: bright in the middle, dark at the edge, lit from above
							local depth = math.clamp(-d / (0.55 * minor), 0, 1)
							local light = 0.82 - 0.18 * math.clamp(py, -1, 1)
							buffer.writeu8(shade, i, math.floor(math.clamp((0.5 + 0.5 * depth) * light, 0, 1) * 255 + 0.5))
						end
					end
				end
			end
			breathe()
		end
	end
	-- the body's coverage (1 px anti-aliasing) and a soft rim light along the outline
	local body = buffer.create(n)
	local rim = buffer.create(n)
	for i = 0, n - 1 do
		local d = buffer.readf32(dist, i * 4)
		buffer.writeu8(body, i, math.floor(math.clamp(0.5 - d, 0, 1) * 255 + 0.5))
		if d < 0 and d > -2.5 then
			buffer.writeu8(rim, i, math.floor((1 - (-d / 2.5)) * 255 + 0.5))
		end
	end
	return { W = W, H = H, body = body, rim = rim, regionId = regionId, regionCov = regionCov, shade = shade, regions = regions }
end

-- paints the mask into a pixel buffer: colors[part] = Color3 (nil = idle muscle), glow = weights for
-- the pulse layer (nil: no glow buffer)
local function paint(mask, colors, glowWeights)
	local W, H = mask.W, mask.H
	local n = W * H
	local out = buffer.create(n * 4)
	local glow = glowWeights and buffer.create(n * 4) or nil
	-- per region index: r, g, b (0..255) and glow weight
	local rr, gg, bb, ww = {}, {}, {}, {}
	for i, id in ipairs(mask.regions) do
		local c = colors[id] or MUSCLE
		rr[i], gg[i], bb[i] = c.R * 255, c.G * 255, c.B * 255
		ww[i] = glowWeights and (glowWeights[id] or 0) or 0
	end
	local sr, sg, sb = SKIN.R * 255, SKIN.G * 255, SKIN.B * 255
	local body, rim, rid, rcov, shade = mask.body, mask.rim, mask.regionId, mask.regionCov, mask.shade
	for i = 0, n - 1 do
		local a = buffer.readu8(body, i)
		if a > 0 then
			local y = i // W
			-- the skin: a touch lighter at the top, a rim light at the outline
			local lift = 1.08 - 0.16 * (y / H) + buffer.readu8(rim, i) / 255 * 0.35
			local r, g, b = sr * lift, sg * lift, sb * lift
			local idx = buffer.readu8(rid, i)
			if idx > 0 then
				local k = buffer.readu8(rcov, i) / 255
				local s = buffer.readu8(shade, i) / 255 * 1.25
				r = r + (rr[idx] * s - r) * k
				g = g + (gg[idx] * s - g) * k
				b = b + (bb[idx] * s - b) * k
				if glow and ww[idx] > 0.01 then
					local o = i * 4
					buffer.writeu8(glow, o, 255)
					buffer.writeu8(glow, o + 1, 255)
					buffer.writeu8(glow, o + 2, 255)
					buffer.writeu8(glow, o + 3, math.floor(math.clamp(ww[idx] * k, 0, 1) * a * 0.9))
				end
			end
			local o = i * 4
			buffer.writeu8(out, o, math.clamp(math.floor(r + 0.5), 0, 255))
			buffer.writeu8(out, o + 1, math.clamp(math.floor(g + 0.5), 0, 255))
			buffer.writeu8(out, o + 2, math.clamp(math.floor(b + 0.5), 0, 255))
			buffer.writeu8(out, o + 3, a)
		end
	end
	return out, glow
end

-- once a creation fails (the experience's Image APIs are off, or the editable budget is spent) every
-- later map draws with frames for a while instead of retrying: a Hub tour would otherwise make dozens of
-- failing calls at once. Disabled APIs stay off for the session; a spent budget is tried again later.
local IMAGE_RETRY = 60
local imagesOffUntil = nil
local function newImage(W, H)
	if imagesOffUntil and os.clock() < imagesOffUntil then
		return nil
	end
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)
	if ok and img then
		imagesOffUntil = nil
		return img
	end
	local msg = (not ok) and tostring(img) or ""
	local disabled = msg:find("not enabled") or msg:find("not available") or msg:find("permission")
	imagesOffUntil = disabled and math.huge or os.clock() + IMAGE_RETRY
	return nil
end

local function imageLabel(parent, name, img, z)
	local l = UI.New("ImageLabel", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z or 1, Parent = parent })
	local ok = pcall(function()
		l.ImageContent = Content.fromObject(img)
	end)
	if not ok then
		l:Destroy()
		return nil
	end
	return l
end

------------------------------------------------------------------------
-- The Frame figure (fallback)
------------------------------------------------------------------------
local function piece(parent, spec, W, H, color, z)
	local x, y, w, h, rot = spec[1], spec[2], spec[3], spec[4], spec[5]
	local pw, ph = w * W, h * H
	local f = UI.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x * W, y * H), Size = UDim2.fromOffset(pw, ph),
		Rotation = rot or 0, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Parent = parent,
	})
	UI.Corner(f, math.ceil(math.min(pw, ph) / 2))
	return f
end

local function region(parent, spec, W, H, z)
	local x, y, w, h, rot = spec[2], spec[3], spec[4], spec[5], spec[6]
	local f = piece(parent, { x, y, w, h, rot }, W, H, MUSCLE, z)
	f.Name = spec[1]
	f:SetAttribute("Part", spec[1])
	UI.Gradient(f, { Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170) }, 90)
	return f
end

local function frameView(self, parent, list, x, W, H)
	local v = UI.New("Frame", { Name = "View", BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(W, H), Parent = parent })
	for _, b in ipairs(BODY) do
		local p = piece(v, b, W, H, SKIN, 1)
		if b[6] == "head" then
			UI.Gradient(p, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 90)
		end
	end
	for _, spec in ipairs(list) do
		local f = region(v, spec, W, H, 2)
		local id = spec[1]
		self.regions[id] = self.regions[id] or {}
		table.insert(self.regions[id], f)
	end
	return v
end

------------------------------------------------------------------------
-- The map
------------------------------------------------------------------------
-- opts: Size (offset UDim2), views = "both" | "front" | "back", Position, AnchorPoint, LayoutOrder,
-- legend (true: a development legend 0 / 50 / potential under the figure), labels (default true:
-- FRONT / BACK captions), glow (default true: the pulse layer), frames (true: skip the painted figure)
function BodyMap.new(parent, opts)
	opts = opts or {}
	local self = setmetatable({ regions = {}, weights = {}, colors = {} }, BodyMap)
	local size = opts.Size or UDim2.fromOffset(220, 230)
	local W, H = size.X.Offset, size.Y.Offset
	local frame = UI.New("Frame", { Name = "BodyMap", BackgroundTransparency = 1, Size = size, LayoutOrder = opts.LayoutOrder or 0, Parent = parent })
	if opts.Position then
		frame.Position = opts.Position
	end
	if opts.AnchorPoint then
		frame.AnchorPoint = opts.AnchorPoint
	end
	self.frame = frame
	local views = opts.views or "both"
	self.views = views
	local labels = opts.labels ~= false
	local legendH = opts.legend and 30 or 0
	local labelH = labels and 16 or 0
	local figH = math.max(20, H - legendH - labelH)
	self.figW, self.figH = W, figH
	local fig = UI.New("Frame", { Name = "Figure", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, figH), Parent = frame })
	self.fig = fig
	-- the painted figure (its mask builds over a few frames the first time a size is used), or frames
	local iw, ih = math.min(MAX_SIDE, math.ceil(W * DENSITY)), math.min(MAX_SIDE, math.ceil(figH * DENSITY))
	local img = (not opts.frames) and newImage(iw, ih) or nil
	local label = img and imageLabel(fig, "Paint", img, 1) or nil
	if label then
		self.image, self.paintLabel = img, label
		local glowImg = opts.glow ~= false and newImage(iw, ih) or nil
		local gl = glowImg and imageLabel(fig, "Glow", glowImg, 2) or nil
		if gl then
			gl.ImageTransparency = 1
			self.glowImage, self.glowLabel = glowImg, gl
		elseif glowImg then
			pcall(function()
				glowImg:Destroy()
			end)
		end
		frame.Destroying:Connect(function()
			self:_releaseImages()
		end)
		task.spawn(function()
			local ok, mask = pcall(buildMask, iw, ih, views, true)
			if not frame.Parent then
				return
			end
			if ok then
				self.mask = mask
				self:Paint()
			else
				warn("[BodyMap] painted figure unavailable, using frames:", mask)
				self:_fallback()
			end
		end)
	elseif img then
		pcall(function()
			img:Destroy()
		end)
	end
	if not self.image then
		self:_buildFrames()
	end
	if labels then
		local function caption(text, x, w)
			UI.Text(frame, text, { Font = T.semi, TextSize = 11, TextColor3 = T.dim, Position = UDim2.fromOffset(x, figH), Size = UDim2.fromOffset(w, 14),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		end
		if views == "both" then
			local vw = math.floor(W / 2)
			caption("FRONT", 0, vw)
			caption("BACK", W - vw, vw)
		else
			caption(views == "back" and "BACK" or "FRONT", 0, W)
		end
	end
	if opts.legend then
		self.legend = UI.Frame(frame, { Name = "Legend", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, H - legendH + 2), Size = UDim2.fromOffset(W, legendH - 2), Visible = false })
	end
	self:Paint()
	return self
end

function BodyMap:_buildFrames()
	local fig, W, H = self.fig, self.figW, self.figH
	if self.views == "both" then
		local vw = math.floor(W / 2)
		frameView(self, fig, FRONT, 0, vw, H)
		frameView(self, fig, BACK, W - vw, vw, H)
	elseif self.views == "back" then
		frameView(self, fig, BACK, 0, W, H)
	else
		frameView(self, fig, FRONT, 0, W, H)
	end
end

function BodyMap:_releaseImages()
	for _, img in ipairs({ self.image, self.glowImage }) do
		pcall(function()
			img:Destroy()
		end)
	end
end

-- the painted figure failed: frames instead, with the colours already set
function BodyMap:_fallback()
	self:_releaseImages()
	for _, l in ipairs({ self.paintLabel, self.glowLabel }) do
		if l then
			l:Destroy()
		end
	end
	self.image, self.glowImage, self.paintLabel, self.glowLabel, self.mask = nil, nil, nil, nil, nil
	self:_buildFrames()
	local colors, weights = self.colors, self.weights
	self.colors, self.weights = {}, {}
	self:_apply(colors, weights)
end

-- painted pixels are kept by size + colours (a thumbnail per exercise is painted once per session)
local paintCache, paintBytes = {}, 0
local PAINT_CACHE_MAX = 8 * 1024 * 1024
local function colorSig(mask, colors)
	local t = { tostring(mask.W), "x", tostring(mask.H), ":", tostring(#mask.regions) }
	for _, id in ipairs(ALL_IDS) do
		local c = colors[id]
		t[#t + 1] = c and string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "-"
	end
	return table.concat(t)
end

-- writes the current colours (painted mode; waits for the mask)
function BodyMap:Paint()
	if not (self.image and self.mask) then
		return
	end
	local ok, err = pcall(function()
		local out, glow
		if self.glowImage then
			out, glow = paint(self.mask, self.colors, self.weights)
		else
			local sig = colorSig(self.mask, self.colors)
			out = paintCache[sig]
			if not out then
				out = paint(self.mask, self.colors, nil)
				if paintBytes > PAINT_CACHE_MAX then
					table.clear(paintCache)
					paintBytes = 0
				end
				paintCache[sig] = out
				paintBytes += buffer.len(out)
			end
		end
		local size = Vector2.new(self.mask.W, self.mask.H)
		self.image:WritePixelsBuffer(Vector2.zero, size, out)
		if glow then
			self.glowImage:WritePixelsBuffer(Vector2.zero, size, glow)
		end
	end)
	if not ok then
		warn("[BodyMap] paint failed:", err)
	end
end

local function eachRegion(self, fn)
	for id, list in pairs(self.regions) do
		for _, f in ipairs(list) do
			fn(id, f)
		end
	end
end

-- per part: colour + glow weight (both modes)
function BodyMap:_apply(colors, weights)
	self.colors, self.weights = colors, weights
	if self.image then
		self:Paint()
		return
	end
	eachRegion(self, function(id, f)
		local c = colors[id]
		local k = weights[id] or 0
		local stroke = f:FindFirstChild("Glow")
		f.BackgroundColor3 = c or MUSCLE
		if c and k > 0.01 then
			if not stroke then
				stroke = UI.New("UIStroke", { Name = "Glow", Color = c, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
			end
			stroke.Color = c
			stroke.Transparency = 1 - 0.7 * k
		elseif stroke then
			stroke:Destroy()
		end
	end)
end


-- weights: { [partId] = number } (any scale; normalised to the biggest, or to scaleMax when given);
-- color = the highlight
function BodyMap:SetTargets(weights, color, scaleMax)
	color = color or T.red
	local max = 0
	for _, w in pairs(weights or {}) do
		max = math.max(max, tonumber(w) or 0)
	end
	if scaleMax then
		max = scaleMax
	end
	local colors, ks = {}, {}
	for _, id in ipairs(ALL_IDS) do
		local w = weights and tonumber(weights[id]) or 0
		local k = max > 0 and math.clamp(w / max, 0, 1) or 0
		if k > 0.01 then
			colors[id] = MUSCLE:Lerp(color, 0.35 + 0.65 * k)
			ks[id] = k
		end
	end
	if self.legend then
		self.legend.Visible = false
	end
	self:_apply(colors, ks)
end

-- growth after a session: { [partId] = gain }; the biggest gains glow brightest (returns the sorted list)
function BodyMap:SetGrowth(gains, color)
	color = color or T.green
	local list = {}
	for id, g in pairs(gains or {}) do
		g = tonumber(g)
		if g and g > 0.0005 then
			table.insert(list, { id = id, g = g })
		end
	end
	table.sort(list, function(a, b)
		return a.g > b.g
	end)
	local w = {}
	for _, e in ipairs(list) do
		w[e.id] = e.g
	end
	self:SetTargets(w, color)
	return list
end

-- development toward the frame's potential: dev = { [partId] = 0..100 }, cap = 100 * frame potential.
-- Untrained muscles stay dark; the legend reads 0 / 50 / potential
function BodyMap:SetDevelopment(dev, cap)
	cap = math.max(1, tonumber(cap) or 100)
	local colors, ks = {}, {}
	for _, id in ipairs(ALL_IDS) do
		local v = tonumber(dev and dev[id]) or 0
		local f = math.clamp(v / cap, 0, 1)
		colors[id] = BodyMap.DevColor(f)
		ks[id] = 0
	end
	self:_apply(colors, ks)
	if self.legend then
		local lg = self.legend
		UI.Clear(lg)
		lg.Visible = true
		local bar = UI.Frame(lg, { Name = "Ramp", Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 0, 8), BackgroundColor3 = Color3.new(1, 1, 1) })
		UI.Corner(bar, 4)
		local seq = {}
		for _, s in ipairs(DEV_STOPS) do
			table.insert(seq, ColorSequenceKeypoint.new(s[1], s[2]))
		end
		UI.New("UIGradient", { Color = ColorSequence.new(seq), Parent = bar })
		local function tick(f, text, align)
			UI.Frame(bar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(f, 0, 0, -2), Size = UDim2.fromOffset(2, 12), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2 })
			UI.Text(lg, text, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(align, 0), Position = UDim2.new(0, 4 + f * (lg.Size.X.Offset - 8), 0, 11),
				Size = UDim2.fromOffset(110, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = align == 0 and Enum.TextXAlignment.Left or (align == 1 and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center), TextWrapped = false })
		end
		local W = lg.Size.X.Offset - 8
		local potText = string.format("POTENTIAL %d", math.floor(cap + 0.5))
		-- the labels must not run into each other on a narrow map (text grows to the floor on a phone)
		local px = 9.5
		tick(0, "0", 0)
		local f50 = math.clamp(50 / cap, 0, 1)
		if cap > 60 and f50 * W + 2 * px < W - #potText * px then
			tick(f50, "50", 0.5)
		elseif cap > 60 then
			UI.Frame(bar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(f50, 0, 0, -2), Size = UDim2.fromOffset(2, 12), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2 })
		end
		tick(1, potText, 1)
	end
end

-- the lit parts, strongest first: { { id = "pecs", w = 0..1 } }
function BodyMap:Lit()
	local list = {}
	for id, k in pairs(self.weights or {}) do
		if k > 0.01 then
			table.insert(list, { id = id, w = k })
		end
	end
	table.sort(list, function(a, b)
		if a.w ~= b.w then
			return a.w > b.w
		end
		return a.id < b.id
	end)
	return list
end

-- a short breathing pulse on the highlighted regions
function BodyMap:Pulse(times)
	if self.image then
		local gl = self.glowLabel
		if not gl then
			return
		end
		task.spawn(function()
			for _ = 1, times or 2 do
				if not gl.Parent then
					return
				end
				UI.Tween(gl, { ImageTransparency = 0.45 }, 0.25)
				task.wait(0.28)
				UI.Tween(gl, { ImageTransparency = 1 }, 0.35)
				task.wait(0.4)
			end
		end)
		return
	end
	eachRegion(self, function(id, f)
		if (self.weights[id] or 0) > 0.01 then
			local base = f.BackgroundColor3
			task.spawn(function()
				for _ = 1, times or 2 do
					if not f.Parent then
						return
					end
					UI.Tween(f, { BackgroundColor3 = UI.Shade(base, 0.35) }, 0.25)
					task.wait(0.28)
					UI.Tween(f, { BackgroundColor3 = base }, 0.35)
					task.wait(0.4)
				end
			end)
		end
	end)
end

-- true when the figure is painted (EditableImage), false on the Frame fallback
function BodyMap:IsPainted()
	return self.image ~= nil
end

BodyMap.Colors = { skin = SKIN, muscle = MUSCLE, edge = EDGE }
-- the painter's internals (unit tests)
BodyMap._buildMask, BodyMap._paint = buildMask, paint

return BodyMap
