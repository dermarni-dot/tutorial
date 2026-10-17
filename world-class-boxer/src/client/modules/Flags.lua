-- Flags: simplified national flags drawn from frames (no image assets) for every Config.Nationalities
-- entry - fighter cards, rankings, the tale of the tape. Stripes, discs, crosses; diagonals and hoist
-- triangles come from hard-edged UIGradients (a gradient's rotation works in the frame's own
-- normalised space, so 45 degrees always runs corner to corner).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"))

local Flags = {}

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local RED, WHITE, BLUE, GREEN = c(206, 17, 38), c(255, 255, 255), c(0, 56, 147), c(0, 135, 81)
local YELLOW, BLACK, NAVY, SKY = c(252, 209, 22), c(20, 20, 20), c(1, 33, 105), c(117, 170, 219)

local function rect(f, x, y, w, h, color, z)
	return UI.New("Frame", { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or f.ZIndex, Parent = f })
end
local function hstripes(f, colors, ratios)
	local total = 0
	for i = 1, #colors do
		total += ratios and ratios[i] or 1
	end
	local y = 0
	for i, col in ipairs(colors) do
		local h = (ratios and ratios[i] or 1) / total
		rect(f, 0, y, 1, h + 0.002, col)
		y += h
	end
end
local function vstripes(f, colors, ratios)
	local total = 0
	for i = 1, #colors do
		total += ratios and ratios[i] or 1
	end
	local x = 0
	for i, col in ipairs(colors) do
		local w = (ratios and ratios[i] or 1) / total
		rect(f, x, 0, w + 0.002, 1, col)
		x += w
	end
end
-- the flag being drawn, in pixels (discs and diamonds are sized from its height)
local curH = 20
-- a disc centred at (x, y) with diameter d (fraction of the flag height; nested discs use their parent)
local function disc(f, x, y, d, color, ofH)
	local px = math.max(1, d * (ofH or curH))
	local o = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(px, px), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = f })
	UI.Corner(o, math.ceil(px / 2))
	return o
end
local function diamond(f, x, y, side, color)
	local px = side * curH
	return UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(px, px), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = f })
end
-- a frame filled only on one side of its own diagonal (rot 45: corner (0,0)->(1,1) split; keep = "low"|"high")
local function half(f, x, y, w, h, color, rot, keep)
	local o = rect(f, x, y, w, h, color)
	local seq = keep == "low" and NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1) })
		or NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.501, 0), NumberSequenceKeypoint.new(1, 0) })
	UI.New("UIGradient", { Rotation = rot, Transparency = seq, Parent = o })
	return o
end
-- a band along a diagonal of the frame (width as a fraction of the gradient length)
local function band(f, color, rot, width)
	local o = rect(f, 0, 0, 1, 1, color)
	local a, b = 0.5 - width / 2, 0.5 + width / 2
	UI.New("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(a, 1), NumberSequenceKeypoint.new(a + 0.002, 0),
		NumberSequenceKeypoint.new(b - 0.002, 0), NumberSequenceKeypoint.new(b, 1), NumberSequenceKeypoint.new(1, 1),
	}), Parent = o })
	return o
end
-- an isosceles triangle on the hoist (left edge), apex at depth d
local function hoist(f, color, d)
	half(f, 0, 0, d, 0.5, color, 135, "high")
	half(f, 0, 0.5, d, 0.5, color, 45, "low")
end
local function union(f, x, y, w, h)
	local u = rect(f, x, y, w, h, NAVY)
	band(u, WHITE, 34, 0.2)
	band(u, WHITE, -34, 0.2)
	band(u, RED, 34, 0.07)
	band(u, RED, -34, 0.07)
	rect(u, 0.42, 0, 0.16, 1, WHITE)
	rect(u, 0, 0.36, 1, 0.28, WHITE)
	rect(u, 0.455, 0, 0.09, 1, RED)
	rect(u, 0, 0.41, 1, 0.18, RED)
	return u
end

local DRAW = {
	USA = function(f)
		hstripes(f, { RED, WHITE, RED, WHITE, RED, WHITE, RED, WHITE, RED, WHITE, RED, WHITE, RED })
		local canton = rect(f, 0, 0, 0.42, 7 / 13, c(60, 59, 110))
		for row = 0, 3 do
			for col = 0, 4 do
				disc(canton, 0.12 + col * 0.19, 0.16 + row * 0.23, 0.09, WHITE)
			end
		end
	end,
	Mexico = function(f)
		vstripes(f, { c(0, 104, 71), WHITE, c(206, 17, 38) })
		disc(f, 0.5, 0.5, 0.3, c(140, 90, 40))
	end,
	["United Kingdom"] = function(f)
		union(f, 0, 0, 1, 1)
	end,
	Ireland = function(f)
		vstripes(f, { c(22, 155, 98), WHITE, c(255, 136, 62) })
	end,
	Philippines = function(f)
		hstripes(f, { c(0, 56, 168), c(206, 17, 38) })
		hoist(f, WHITE, 0.45)
		disc(f, 0.16, 0.5, 0.22, YELLOW)
	end,
	Japan = function(f)
		rect(f, 0, 0, 1, 1, WHITE)
		disc(f, 0.5, 0.5, 0.6, c(188, 0, 45))
	end,
	Cuba = function(f)
		hstripes(f, { c(0, 42, 143), WHITE, c(0, 42, 143), WHITE, c(0, 42, 143) })
		hoist(f, c(207, 20, 43), 0.45)
		disc(f, 0.15, 0.5, 0.2, WHITE)
	end,
	["Puerto Rico"] = function(f)
		hstripes(f, { c(237, 0, 0), WHITE, c(237, 0, 0), WHITE, c(237, 0, 0) })
		hoist(f, c(0, 80, 240), 0.45)
		disc(f, 0.15, 0.5, 0.2, WHITE)
	end,
	Ukraine = function(f)
		hstripes(f, { c(0, 87, 183), c(255, 215, 0) })
	end,
	Kazakhstan = function(f)
		rect(f, 0, 0, 1, 1, c(0, 175, 202))
		disc(f, 0.5, 0.45, 0.42, c(254, 197, 0))
		rect(f, 0.04, 0, 0.05, 1, c(254, 197, 0))
	end,
	Russia = function(f)
		hstripes(f, { WHITE, c(0, 57, 166), c(213, 43, 30) })
	end,
	Nigeria = function(f)
		vstripes(f, { c(0, 135, 81), WHITE, c(0, 135, 81) })
	end,
	Ghana = function(f)
		hstripes(f, { c(206, 17, 38), c(252, 209, 22), c(0, 107, 63) })
		disc(f, 0.5, 0.5, 0.26, BLACK)
	end,
	["South Africa"] = function(f)
		hstripes(f, { c(224, 60, 49), c(0, 122, 77), c(0, 35, 149) }, { 1, 0.6, 1 })
		rect(f, 0.3, 0.37, 0.7, 0.26, WHITE)
		rect(f, 0.3, 0.41, 0.7, 0.18, c(0, 122, 77))
		hoist(f, c(255, 184, 28), 0.42)
		hoist(f, BLACK, 0.34)
	end,
	Brazil = function(f)
		rect(f, 0, 0, 1, 1, c(0, 151, 57))
		diamond(f, 0.5, 0.5, 0.6, c(254, 221, 0))
		disc(f, 0.5, 0.5, 0.42, c(0, 39, 118))
	end,
	Argentina = function(f)
		hstripes(f, { c(116, 172, 223), WHITE, c(116, 172, 223) })
		disc(f, 0.5, 0.5, 0.24, c(246, 180, 14))
	end,
	Canada = function(f)
		vstripes(f, { c(216, 6, 33), WHITE, c(216, 6, 33) }, { 1, 2, 1 })
		diamond(f, 0.5, 0.46, 0.34, c(216, 6, 33))
		rect(f, 0.485, 0.5, 0.03, 0.3, c(216, 6, 33))
	end,
	Australia = function(f)
		rect(f, 0, 0, 1, 1, c(1, 33, 105))
		union(f, 0, 0, 0.5, 0.5)
		disc(f, 0.25, 0.76, 0.2, WHITE)
		for _, p in ipairs({ { 0.75, 0.25 }, { 0.62, 0.48 }, { 0.86, 0.45 }, { 0.75, 0.8 } }) do
			disc(f, p[1], p[2], 0.12, WHITE)
		end
	end,
	France = function(f)
		vstripes(f, { c(0, 85, 164), WHITE, c(239, 65, 53) })
	end,
	Germany = function(f)
		hstripes(f, { BLACK, c(221, 0, 0), c(255, 206, 0) })
	end,
	Italy = function(f)
		vstripes(f, { c(0, 146, 70), WHITE, c(206, 43, 55) })
	end,
	Spain = function(f)
		hstripes(f, { c(170, 21, 27), c(241, 191, 0), c(170, 21, 27) }, { 1, 2, 1 })
	end,
	["Dominican Republic"] = function(f)
		rect(f, 0, 0, 0.5, 0.5, c(0, 45, 98))
		rect(f, 0.5, 0, 0.5, 0.5, c(206, 17, 38))
		rect(f, 0, 0.5, 0.5, 0.5, c(206, 17, 38))
		rect(f, 0.5, 0.5, 0.5, 0.5, c(0, 45, 98))
		rect(f, 0.44, 0, 0.12, 1, WHITE)
		rect(f, 0, 0.4, 1, 0.2, WHITE)
	end,
	Jamaica = function(f)
		rect(f, 0, 0, 1, 1, c(0, 155, 58))
		half(f, 0, 0, 0.5, 1, BLACK, 45, "low")
		half(f, 0, 0, 0.5, 1, BLACK, 135, "high")
		half(f, 0.5, 0, 0.5, 1, BLACK, 45, "high")
		half(f, 0.5, 0, 0.5, 1, BLACK, 135, "low")
		band(f, c(254, 209, 0), 34, 0.16)
		band(f, c(254, 209, 0), -34, 0.16)
	end,
	Haiti = function(f)
		hstripes(f, { c(0, 32, 159), c(210, 16, 52) })
		rect(f, 0.38, 0.32, 0.24, 0.36, WHITE)
	end,
	Venezuela = function(f)
		hstripes(f, { c(255, 204, 0), c(0, 36, 125), c(207, 20, 43) })
		for i = 0, 6 do
			local a = math.rad(200 + i * 23.3)
			disc(f, 0.5 + math.cos(a) * 0.2, 0.62 + math.sin(a) * 0.32, 0.08, WHITE)
		end
	end,
	Colombia = function(f)
		hstripes(f, { c(252, 209, 22), c(0, 56, 147), c(206, 17, 38) }, { 2, 1, 1 })
	end,
	Thailand = function(f)
		hstripes(f, { c(165, 25, 49), WHITE, c(45, 42, 74), WHITE, c(165, 25, 49) }, { 1, 1, 2, 1, 1 })
	end,
	["South Korea"] = function(f)
		rect(f, 0, 0, 1, 1, WHITE)
		local t = disc(f, 0.5, 0.5, 0.5, c(0, 71, 160))
		local top = UI.New("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = c(205, 46, 58), BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = t })
		UI.Corner(top, math.ceil(curH * 0.25))
		for _, p in ipairs({ { 0.17, 0.22, 35 }, { 0.83, 0.22, -35 }, { 0.17, 0.78, -35 }, { 0.83, 0.78, 35 } }) do
			local g = rect(f, p[1] - 0.06, p[2] - 0.1, 0.12, 0.2, BLACK)
			g.Rotation = p[3]
		end
	end,
	China = function(f)
		rect(f, 0, 0, 1, 1, c(238, 28, 37))
		disc(f, 0.17, 0.28, 0.3, c(255, 255, 0))
		for _, p in ipairs({ { 0.33, 0.12 }, { 0.4, 0.24 }, { 0.4, 0.4 }, { 0.33, 0.52 } }) do
			disc(f, p[1], p[2], 0.08, c(255, 255, 0))
		end
	end,
	India = function(f)
		hstripes(f, { c(255, 153, 51), WHITE, c(19, 136, 8) })
		local w = disc(f, 0.5, 0.5, 0.28, c(0, 0, 128))
		disc(w, 0.5, 0.5, 0.72, WHITE, 0.28 * curH)
	end,
	Uzbekistan = function(f)
		hstripes(f, { c(0, 153, 181), c(206, 17, 38), WHITE, c(206, 17, 38), c(30, 181, 58) }, { 10, 1, 9, 1, 10 })
		disc(f, 0.16, 0.17, 0.2, WHITE)
		disc(f, 0.19, 0.17, 0.18, c(0, 153, 181))
	end,
	Cameroon = function(f)
		vstripes(f, { c(0, 122, 94), c(206, 17, 38), c(252, 209, 22) })
		disc(f, 0.5, 0.5, 0.26, c(252, 209, 22))
	end,
	Kenya = function(f)
		hstripes(f, { BLACK, WHITE, c(187, 0, 0), WHITE, c(0, 102, 0) }, { 6, 1, 6, 1, 6 })
		local s = UI.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0.32 * curH, 0.8 * curH), BackgroundColor3 = c(187, 0, 0), BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = f })
		UI.Corner(s, math.ceil(0.16 * curH))
		UI.Stroke(s, BLACK, 1)
	end,
	["New Zealand"] = function(f)
		rect(f, 0, 0, 1, 1, c(1, 33, 105))
		union(f, 0, 0, 0.5, 0.5)
		for _, p in ipairs({ { 0.75, 0.22 }, { 0.65, 0.5 }, { 0.85, 0.46 }, { 0.75, 0.8 } }) do
			disc(f, p[1], p[2], 0.12, c(204, 20, 43))
		end
	end,
	Poland = function(f)
		hstripes(f, { WHITE, c(220, 20, 60) })
	end,
	Sweden = function(f)
		rect(f, 0, 0, 1, 1, c(0, 106, 167))
		rect(f, 0.31, 0, 0.13, 1, c(254, 204, 0))
		rect(f, 0, 0.4, 1, 0.2, c(254, 204, 0))
	end,
	Turkey = function(f)
		rect(f, 0, 0, 1, 1, c(227, 10, 23))
		disc(f, 0.4, 0.5, 0.5, WHITE)
		disc(f, 0.44, 0.5, 0.4, c(227, 10, 23))
		disc(f, 0.62, 0.5, 0.16, WHITE)
	end,
	Egypt = function(f)
		hstripes(f, { c(206, 17, 38), WHITE, BLACK })
		disc(f, 0.5, 0.5, 0.2, c(192, 147, 0))
	end,
	Morocco = function(f)
		rect(f, 0, 0, 1, 1, c(193, 39, 45))
		local ring = disc(f, 0.5, 0.5, 0.36, c(193, 39, 45))
		UI.Stroke(ring, c(0, 98, 51), 2)
	end,
}

-- the flag in a w x h frame (default 30 x 20); props are applied to the holder frame
function Flags.Draw(parent, nationality, props)
	props = props or {}
	local f = UI.New("Frame", {
		Name = "Flag", Size = props.Size or UDim2.fromOffset(30, 20), BackgroundColor3 = c(60, 64, 76), BorderSizePixel = 0, ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder or 0, ZIndex = props.ZIndex or 1, Parent = parent,
	})
	if props.Position then
		f.Position = props.Position
	end
	if props.AnchorPoint then
		f.AnchorPoint = props.AnchorPoint
	end
	local draw = DRAW[nationality]
	local sz = f.Size
	curH = sz.Y.Offset > 0 and sz.Y.Offset or 20
	if draw then
		local ok = pcall(draw, f)
		if not ok then
			for _, ch in ipairs(f:GetChildren()) do
				ch:Destroy()
			end
		end
	end
	UI.Corner(f, props.radius or 2)
	UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.75, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	-- a soft sheen so the flat colours read as cloth
	local sheen = UI.New("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = f })
	UI.New("UIGradient", { Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.82) }), Parent = sheen })
	return f
end

function Flags.Has(nationality)
	return DRAW[nationality] ~= nil
end

return Flags
