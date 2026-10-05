-- BodyMap: an anatomical body-map silhouette (front + back views) drawn from frames, one region per
-- Config.MuscleParts id. Training shows the muscles an exercise works (Config.ExerciseTargets /
-- act.parts, brighter = worked harder) and, after the session, the growth each muscle got.
--   local map = BodyMap.new(parent, { Size = UDim2.fromOffset(240, 250), views = "both" })
--   map:SetTargets(act.parts, color)       map:SetGrowth(result.parts)      map:Pulse()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"))
local T = UI.Theme

local BodyMap = {}
BodyMap.__index = BodyMap

local SKIN = Color3.fromRGB(46, 51, 64) -- the silhouette
local MUSCLE = Color3.fromRGB(70, 77, 96) -- an idle muscle
local EDGE = Color3.fromRGB(96, 104, 126)

-- silhouette pieces: { x, y, w, h, rot } in view fractions (x of width, y of height); corner = round
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
	-- volume: lit from above
	UI.Gradient(f, { Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170) }, 90)
	return f
end

local function view(self, parent, list, x, W, H, label)
	local v = UI.New("Frame", { Name = label, BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(W, H), Parent = parent })
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
	UI.Text(v, label, { Font = T.semi, TextSize = 10, TextColor3 = T.dim, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(W, 12),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	return v
end

-- opts: Size (offset UDim2), views = "both" | "front" | "back", Position, AnchorPoint, LayoutOrder
function BodyMap.new(parent, opts)
	opts = opts or {}
	local self = setmetatable({ regions = {}, weights = {} }, BodyMap)
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
	local vh = H - 2
	if views == "both" then
		local vw = math.floor(W / 2)
		view(self, frame, FRONT, 0, vw, vh, "FRONT")
		view(self, frame, BACK, W - vw, vw, vh, "BACK")
	elseif views == "back" then
		view(self, frame, BACK, 0, W, vh, "BACK")
	else
		view(self, frame, FRONT, 0, W, vh, "FRONT")
	end
	return self
end

local function eachRegion(self, fn)
	for id, list in pairs(self.regions) do
		for _, f in ipairs(list) do
			fn(id, f)
		end
	end
end

-- weights: { [partId] = number } (any scale; normalised to the biggest); color = the highlight
function BodyMap:SetTargets(weights, color)
	color = color or T.red
	local max = 0
	for _, w in pairs(weights or {}) do
		max = math.max(max, tonumber(w) or 0)
	end
	self.weights = {}
	eachRegion(self, function(id, f)
		local w = weights and tonumber(weights[id]) or 0
		local k = max > 0 and w / max or 0
		self.weights[id] = k
		local stroke = f:FindFirstChild("Glow")
		if k > 0.01 then
			f.BackgroundColor3 = MUSCLE:Lerp(color, 0.35 + 0.65 * k)
			if not stroke then
				stroke = UI.New("UIStroke", { Name = "Glow", Color = color, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
			end
			stroke.Transparency = 1 - 0.7 * k
		else
			f.BackgroundColor3 = MUSCLE
			if stroke then
				stroke:Destroy()
			end
		end
	end)
end

-- growth after a session: { [partId] = gain }; the biggest gains glow green (returns the sorted list)
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

-- a short breathing pulse on the highlighted regions
function BodyMap:Pulse(times)
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

-- the edge colour, exposed for legends
BodyMap.Colors = { skin = SKIN, muscle = MUSCLE, edge = EDGE }

return BodyMap
