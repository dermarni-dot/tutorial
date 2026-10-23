-- CityKit: the pieces the town is built from, at real-world scale for the R15 rig (Config.City:
-- 1 stud = 0.28 m). Roads with kerbs, gutters, markings and sidewalks; street lights (8-9 m) and
-- traffic signals (5 m) with mast arms; cars, vans, pickups and a bus at 4.5 x 1.6 x 1.5 m; trees
-- of six kinds (8-15 m); street furniture (benches, bins, hydrants, planters, bollards, bus
-- shelters, bike racks, vendor carts); fences and walls; parking lots with 2.7 x 5 m bays;
-- generic buildings (storefront, storeys, cornice, roof units) and skyline towers; billboards;
-- the invisible anchors (sites, prompts, light zones) the client and the travel code find by name.
-- Every builder takes its parent first and returns the model or the main part.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymDecor = require(script.Parent:WaitForChild("GymDecor"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signage = require(Shared:WaitForChild("Signage"))

local K = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local part = GymDecor.Part
local cyl = GymDecor.Cyl
local vcyl = GymDecor.VCyl
local ball = GymDecor.Ball
local blob = GymDecor.Blob
local label = GymDecor.Label
local frame = GymDecor.Frame
local spot = GymDecor.Spot
local point = GymDecor.Point
local emitter = GymDecor.Emitter
local tag = GymDecor.Tag
local C = GymDecor.Colors

K.part, K.cyl, K.vcyl, K.ball, K.blob, K.label, K.frame, K.spot, K.point, K.emitter, K.tag = part, cyl, vcyl, ball, blob, label, frame, spot, point, emitter, tag
K.rod = GymDecor.Rod
K.sign = GymDecor.Sign
K.C = C
K.V3, K.CF, K.ANG, K.RAD, K.M = V3, CF, ANG, RAD, M

local CITY = Config.City
K.CITY = CITY
K.ROAD_Y = CITY.RoadY -- 0.3
K.SW_H = CITY.SidewalkY -- 0.8
K.MARK_Y = CITY.RoadY + 0.012 -- road paint

K.ASPHALT = Color3.fromRGB(56, 56, 60)
K.ASPHALT_OLD = Color3.fromRGB(74, 74, 78)
K.SIDEWALK = Color3.fromRGB(178, 176, 168)
K.PAVING = Color3.fromRGB(196, 186, 170)
K.KERB = Color3.fromRGB(200, 198, 190)
K.GUTTER = Color3.fromRGB(44, 44, 48)
K.LINE_YELLOW = Color3.fromRGB(240, 204, 74)
K.LINE_WHITE = Color3.fromRGB(236, 236, 230)
K.POLE = Color3.fromRGB(46, 48, 54)
K.LENS_DAY = Color3.fromRGB(200, 200, 196)
K.GRASS = Color3.fromRGB(94, 140, 72)
K.GRASS_DRY = Color3.fromRGB(118, 146, 74)
K.GRASS_DARK = Color3.fromRGB(78, 124, 64)
K.SOIL = Color3.fromRGB(78, 58, 40)
K.WATER = Color3.fromRGB(52, 120, 168)

local ASPHALT, SIDEWALK, KERB, LINE_YELLOW, LINE_WHITE, POLE, LENS_DAY = K.ASPHALT, K.SIDEWALK, K.KERB, K.LINE_YELLOW, K.LINE_WHITE, K.POLE, K.LENS_DAY
local ROAD_Y, SW_H, MARK_Y = K.ROAD_Y, K.SW_H, K.MARK_Y

function K.folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function K.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local folder, model = K.folder, K.model

function K.gui(p, face, ppu, light, maxDist)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 20
	sg.LightInfluence = light or 0
	sg.MaxDistance = maxDist or 600
	sg.Parent = p
	return sg
end
local gui = K.gui

------------------------------------------------------------------------
-- anchors: sites (client builds and travel targets), prompts, light zones, lights
------------------------------------------------------------------------
local sitesFolder
K.Sites = {} -- name -> CFrame
function K.Init(sites)
	sitesFolder = sites
end

-- City/Sites/Site_<name> with attribute Site = name (CityVisuals.siteCF, CityMap.TravelCFrame)
function K.site(name, cf, attrs)
	local p = part(sitesFolder, "Site_" .. name, V3(1, 1, 1), cf, Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	p:SetAttribute("Site", name)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	K.Sites[name] = cf
	return p
end

-- a prompt on an invisible part with a floating label (MapBuilder.buildAction's contract: attribute
-- Action on the ProximityPrompt, dispatched by the client)
function K.promptPart(parent, name, pos, actionText, objectText, attrs, labelColor)
	local p = part(parent, name, V3(1, 1, 1), CF(pos), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	for k, v in pairs(attrs or {}) do
		pp:SetAttribute(k, v)
	end
	pp.Parent = p
	local bb = Instance.new("BillboardGui")
	bb.Name = "PromptLabel"
	bb.Size = UDim2.fromOffset(220, 40)
	bb.StudsOffset = V3(0, 2.6, 0)
	bb.MaxDistance = 50
	bb.Adornee = p
	label(bb, actionText, { TextColor3 = labelColor or Color3.fromRGB(120, 220, 255), TextStrokeTransparency = 0.3 })
	bb.Parent = p
	return p, pp
end

-- invisible boxes tagged LightZone: the client grades the picture for the zone the camera is in
function K.lightZone(parent, name, size, cf, profile)
	local p = part(parent, name, size, cf, Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	p.CanQuery = false
	p:SetAttribute("Profile", profile)
	tag(p, "LightZone")
	return p
end

-- a light that is always on (interiors are under a roof: Future lighting leaves them dark by day)
function K.roomLight(parent, cf, color, range, brightness)
	return point(emitter(parent, cf), color or Color3.fromRGB(255, 236, 210), (range or 18) * 1.15, (brightness or 1.1) * 1.3)
end

-- a light that comes on at dusk (Ambience switches every NightLight)
function K.nightPoint(parent, cf, color, range, brightness)
	local l = point(emitter(parent, cf), color or Color3.fromRGB(255, 214, 160), range or 14, brightness or 1)
	l.Enabled = false
	tag(l, "NightLight")
	return l
end

-- glowing neon outline around a rectangle (cf faces the viewer with its -Z)
function K.neonOutline(parent, cf, w, h, color)
	local m = model(parent, "NeonOutline")
	local t = 0.22
	for _, e in ipairs({ { 0, h / 2, w + t, t }, { 0, -h / 2, w + t, t }, { -w / 2, 0, t, h }, { w / 2, 0, t, h } }) do
		part(m, "NeonTube", V3(e[3], e[4], t), cf * CF(e[1], e[2], 0), color, M.Neon, { shadow = false })
	end
	tag(m, "NeonFlicker")
	return m
end

-- window grid spec on one face (drawn by the client: CityVisuals.windowGrids / CityDetail); rows/cols
-- fill the band y0..y1 of a face faceH tall. range = the client's draw range (nil: its default)
function K.windowGrid(p, face, faceH, y0, y1, rows, cols, rng, litChance, range)
	p:SetAttribute("WinFace", face.Name)
	if range then
		p:SetAttribute("WinRange", range)
	end
	p:SetAttribute("WinTop", 1 - y1 / faceH)
	p:SetAttribute("WinSpan", (y1 - y0) / faceH)
	p:SetAttribute("WinRows", rows)
	p:SetAttribute("WinCols", cols)
	p:SetAttribute("WinLit", litChance or 0.35)
	p:SetAttribute("WinSeed", rng:NextInteger(1, 1000000))
	return p
end

------------------------------------------------------------------------
-- ground: slabs, lawns, water
------------------------------------------------------------------------
-- flat slab x1..x2, z1..z2 from y bottom (0) to top
function K.slab(parent, name, x1, x2, z1, z2, top, color, material, collide, bottom)
	bottom = bottom or 0
	return part(parent, name, V3(x2 - x1, top - bottom, z2 - z1), CF((x1 + x2) / 2, (top + bottom) / 2, (z1 + z2) / 2), color, material, { collide = collide ~= false })
end
local slab = K.slab

-- a lawn a hair above the ground, with a couple of tone patches and (opts.beds) flower beds
function K.lawn(parent, x1, x2, z1, z2, rng, opts)
	opts = opts or {}
	local top = opts.top or 0.14
	local base = slab(parent, "Lawn", x1, x2, z1, z2, top, opts.color or K.GRASS, opts.material or M.Grass, true)
	if rng then
		local w, d = x2 - x1, z2 - z1
		for _ = 1, opts.patches or 2 do
			local pw, pd = rng:NextNumber(w * 0.2, w * 0.45), rng:NextNumber(d * 0.2, d * 0.45)
			local px, pz = rng:NextNumber(x1 + pw / 2, x2 - pw / 2), rng:NextNumber(z1 + pd / 2, z2 - pd / 2)
			local tone = ({ K.GRASS_DRY, K.GRASS_DARK, Color3.fromRGB(104, 150, 78) })[rng:NextInteger(1, 3)]
			part(parent, "LawnPatch", V3(pw, 0.06, pd), CF(px, top + 0.04, pz), tone, M.Grass, { shadow = false })
		end
	end
	return base
end

-- a flower bed: soil strip with a row of blooms
function K.flowerBed(parent, cf, len, w, rng)
	part(parent, "BedSoil", V3(len, 0.3, w), cf * CF(0, 0.15, 0), K.SOIL, M.Ground)
	local cols = { Color3.fromRGB(230, 70, 90), Color3.fromRGB(250, 200, 60), Color3.fromRGB(240, 120, 160), Color3.fromRGB(240, 240, 240), Color3.fromRGB(200, 80, 200) }
	local n = math.max(2, math.floor(len / 3))
	for k = 0, n - 1 do
		local x = -len / 2 + (k + 0.5) * len / n
		blob(parent, "Blooms", V3(len / n * 0.9, 1.1, w * 0.85), cf * CF(x, 0.75, 0), cols[(rng and rng:NextInteger(1, #cols)) or (k % #cols + 1)], M.Grass, { shadow = false })
	end
end

-- a hedge along local X of cf (centre at the base)
function K.hedge(parent, cf, len, h, w, color)
	return blob(parent, "Hedge", V3(len, h or 3.2, w or 2.6), cf * CF(0, (h or 3.2) / 2, 0), color or Color3.fromRGB(50, 110, 55), M.Grass)
end

-- water: Terrain water where the engine has it, a surface part where it does not (the simulator)
function K.water(parent, x1, x2, z1, z2, surfaceY, depth)
	depth = depth or 7
	slab(parent, "RiverBed", x1, x2, z1, z2, surfaceY - depth, Color3.fromRGB(40, 60, 54), M.Mud, true, surfaceY - depth - 1)
	local ok = pcall(function()
		workspace.Terrain:FillBlock(CF((x1 + x2) / 2, surfaceY - depth / 2, (z1 + z2) / 2), V3(x2 - x1, depth, z2 - z1), Enum.Material.Water)
	end)
	if not ok then
		part(parent, "WaterSurface", V3(x2 - x1, 0.4, z2 - z1), CF((x1 + x2) / 2, surfaceY - 0.2, (z1 + z2) / 2), K.WATER, M.Glass, { transparency = 0.15, reflect = 0.25, shadow = false })
	end
end

------------------------------------------------------------------------
-- roads: asphalt with kerbs and gutters, centre lines, sidewalks; markings
------------------------------------------------------------------------
-- a run of dashes along X at z (len / gap in studs)
function K.dashesX(parent, x1, x2, z, color, len, gap, w, name)
	len, gap, w = len or 10, gap or 20, w or 0.5
	local x = x1 + gap / 2
	while x + len <= x2 do
		part(parent, name or "LaneDash", V3(len, 0.03, w), CF(x + len / 2, MARK_Y, z), color or LINE_YELLOW, M.SmoothPlastic, { shadow = false })
		x += len + gap
	end
end

function K.dashesZ(parent, z1, z2, x, color, len, gap, w, name)
	len, gap, w = len or 10, gap or 20, w or 0.5
	local z = z1 + gap / 2
	while z + len <= z2 do
		part(parent, name or "LaneDash", V3(w, 0.03, len), CF(x, MARK_Y, z + len / 2), color or LINE_YELLOW, M.SmoothPlastic, { shadow = false })
		z += len + gap
	end
end

function K.lineX(parent, x1, x2, z, color, w, name)
	return part(parent, name or "LaneLine", V3(x2 - x1, 0.03, w or 0.5), CF((x1 + x2) / 2, MARK_Y, z), color or LINE_WHITE, M.SmoothPlastic, { shadow = false })
end

function K.lineZ(parent, z1, z2, x, color, w, name)
	return part(parent, name or "LaneLine", V3(w or 0.5, 0.03, z2 - z1), CF(x, MARK_Y, (z1 + z2) / 2), color or LINE_WHITE, M.SmoothPlastic, { shadow = false })
end

-- zebra crossing: 2-stud bars with 2-stud gaps, stacked across the road (bars run with the traffic)
function K.crosswalk(parent, center, alongX, roadWidth, bandWidth)
	bandWidth = bandWidth or 8
	local n = math.floor((roadWidth - 1) / 4)
	for i = 0, n - 1 do
		local o = -(n - 1) * 2 + i * 4
		if alongX then
			part(parent, "Crosswalk", V3(bandWidth, 0.03, 2.0), CF(center.X, MARK_Y + 0.004, center.Z + o), LINE_WHITE, M.SmoothPlastic, { shadow = false })
		else
			part(parent, "Crosswalk", V3(2.0, 0.03, bandWidth), CF(center.X + o, MARK_Y + 0.004, center.Z), LINE_WHITE, M.SmoothPlastic, { shadow = false })
		end
	end
end

-- a stop bar across one lane: at pos, across = the lane's width direction (unit vector)
function K.stopBar(parent, pos, across, laneW)
	local a = across * (laneW or 12) / 2
	local cf = CFrame.lookAt(pos - a, pos + a)
	return part(parent, "StopBar", V3(1.2, 0.03, (laneW or 12)), CF(pos.X, MARK_Y + 0.004, pos.Z) * (cf - cf.Position), LINE_WHITE, M.SmoothPlastic, { shadow = false })
end

-- a lane arrow at pos pointing along dir (unit vector): shaft + head
function K.laneArrow(parent, pos, dir)
	local cf = CFrame.lookAt(V3(pos.X, MARK_Y + 0.004, pos.Z), V3(pos.X, MARK_Y + 0.004, pos.Z) + dir)
	part(parent, "LaneArrow", V3(0.6, 0.03, 7), cf * CF(0, 0, 1.5), LINE_WHITE, M.SmoothPlastic, { shadow = false })
	part(parent, "LaneArrowHead", V3(2.6, 0.03, 0.8), cf * CF(0, 0, -2.2), LINE_WHITE, M.SmoothPlastic, { shadow = false })
	part(parent, "LaneArrowHead", V3(1.6, 0.03, 0.8), cf * CF(0, 0, -3.0), LINE_WHITE, M.SmoothPlastic, { shadow = false })
	part(parent, "LaneArrowHead", V3(0.8, 0.03, 0.8), cf * CF(0, 0, -3.8), LINE_WHITE, M.SmoothPlastic, { shadow = false })
end

-- splits [a, b] by the gaps { {g1, g2}, ... } into the kept intervals
local function cutRanges(a, b, gaps)
	local out = { { a, b } }
	for _, g in ipairs(gaps or {}) do
		local nxt = {}
		for _, r in ipairs(out) do
			if g[2] <= r[1] or g[1] >= r[2] then
				table.insert(nxt, r)
			else
				if g[1] > r[1] + 0.05 then
					table.insert(nxt, { r[1], g[1] })
				end
				if g[2] < r[2] - 0.05 then
					table.insert(nxt, { g[2], r[2] })
				end
			end
		end
		out = nxt
	end
	return out
end
K.cutRanges = cutRanges

-- the gaps of both lists together (either may be nil)
function K.joinGaps(a, b)
	local out = {}
	for _, g in ipairs(a or {}) do
		table.insert(out, g)
	end
	for _, g in ipairs(b or {}) do
		table.insert(out, g)
	end
	return out
end

-- a road along X: centre z, width w, from x1 to x2.
-- opts: kerbs (default true), sw = { n = width, s = width } sidewalks on the north (-Z) / south (+Z) side,
-- center = "dash" | "double" | "none" (default dash, yellow), lanes (default 2: white dashes between
-- same-direction lanes when 4), gaps = { {x, x} } where the kerbs, sidewalks and lines break (junctions),
-- swGaps (sidewalk-only breaks), y (asphalt top, default ROAD_Y), color, name, lineColor
function K.roadX(parent, name, x1, x2, zc, w, opts)
	opts = opts or {}
	local y = opts.y or ROAD_Y
	local f = parent
	slab(f, name or "Road", x1, x2, zc - w / 2, zc + w / 2, y, opts.color or ASPHALT, M.Asphalt)
	local gaps = opts.gaps or {}
	local kerbs = opts.kerbs ~= false
	for _, side in ipairs({ -1, 1 }) do
		local edge = zc + side * w / 2
		local swW = opts.sw and (side < 0 and opts.sw.n or opts.sw.s) or 0
		local sideGaps = K.joinGaps(gaps, side < 0 and opts.gapsN or opts.gapsS)
		for _, r in ipairs(cutRanges(x1, x2, sideGaps)) do
			if kerbs then
				part(f, "Kerb", V3(r[2] - r[1], SW_H - y, 0.6), CF((r[1] + r[2]) / 2, (SW_H + y) / 2, edge + side * 0.3), KERB, M.Concrete, { collide = true })
				part(f, "Gutter", V3(r[2] - r[1], 0.02, 1.4), CF((r[1] + r[2]) / 2, y + 0.01, edge - side * 0.7), K.GUTTER, M.Asphalt, { shadow = false })
			end
		end
		if swW > 0 then
			for _, r in ipairs(cutRanges(x1, x2, opts.swGaps or sideGaps)) do
				local z1, z2 = edge + side * 0.6, edge + side * (0.6 + swW)
				slab(f, "Sidewalk", r[1], r[2], math.min(z1, z2), math.max(z1, z2), SW_H, opts.swColor or SIDEWALK, M.Concrete)
			end
		end
	end
	local center = opts.center or "dash"
	local lineColor = opts.lineColor or LINE_YELLOW
	for _, r in ipairs(cutRanges(x1, x2, gaps)) do
		if center == "dash" then
			K.dashesX(f, r[1], r[2], zc, lineColor)
		elseif center == "double" then
			K.lineX(f, r[1], r[2], zc - 0.5, lineColor, 0.4, "CenterLine")
			K.lineX(f, r[1], r[2], zc + 0.5, lineColor, 0.4, "CenterLine")
		end
		if (opts.lanes or 2) >= 4 then
			local lw = w / opts.lanes
			K.dashesX(f, r[1], r[2], zc - lw, LINE_WHITE, 8, 16, 0.4)
			K.dashesX(f, r[1], r[2], zc + lw, LINE_WHITE, 8, 16, 0.4)
		end
	end
end

function K.roadZ(parent, name, z1, z2, xc, w, opts)
	opts = opts or {}
	local y = opts.y or ROAD_Y
	local f = parent
	slab(f, name or "Road", xc - w / 2, xc + w / 2, z1, z2, y, opts.color or ASPHALT, M.Asphalt)
	local gaps = opts.gaps or {}
	local kerbs = opts.kerbs ~= false
	for _, side in ipairs({ -1, 1 }) do
		local edge = xc + side * w / 2
		local swW = opts.sw and (side < 0 and opts.sw.w or opts.sw.e) or 0
		local sideGaps = K.joinGaps(gaps, side < 0 and opts.gapsW or opts.gapsE)
		for _, r in ipairs(cutRanges(z1, z2, sideGaps)) do
			if kerbs then
				part(f, "Kerb", V3(0.6, SW_H - y, r[2] - r[1]), CF(edge + side * 0.3, (SW_H + y) / 2, (r[1] + r[2]) / 2), KERB, M.Concrete, { collide = true })
				part(f, "Gutter", V3(1.4, 0.02, r[2] - r[1]), CF(edge - side * 0.7, y + 0.01, (r[1] + r[2]) / 2), K.GUTTER, M.Asphalt, { shadow = false })
			end
		end
		if swW > 0 then
			for _, r in ipairs(cutRanges(z1, z2, opts.swGaps or sideGaps)) do
				local xa, xb = edge + side * 0.6, edge + side * (0.6 + swW)
				slab(f, "Sidewalk", math.min(xa, xb), math.max(xa, xb), r[1], r[2], SW_H, opts.swColor or SIDEWALK, M.Concrete)
			end
		end
	end
	local center = opts.center or "dash"
	local lineColor = opts.lineColor or LINE_YELLOW
	for _, r in ipairs(cutRanges(z1, z2, gaps)) do
		if center == "dash" then
			K.dashesZ(f, r[1], r[2], xc, lineColor)
		elseif center == "double" then
			K.lineZ(f, r[1], r[2], xc - 0.5, lineColor, 0.4, "CenterLine")
			K.lineZ(f, r[1], r[2], xc + 0.5, lineColor, 0.4, "CenterLine")
		end
		if (opts.lanes or 2) >= 4 then
			local lw = w / opts.lanes
			K.dashesZ(f, r[1], r[2], xc - lw, LINE_WHITE, 8, 16, 0.4)
			K.dashesZ(f, r[1], r[2], xc + lw, LINE_WHITE, 8, 16, 0.4)
		end
	end
end

-- a kerb ramp (dropped kerb) is just a gap: the sidewalk and road meet flush through a short wedge
function K.kerbRamp(parent, pos, dir, w)
	local cf = CFrame.lookAt(V3(pos.X, (ROAD_Y + SW_H) / 2, pos.Z), V3(pos.X, (ROAD_Y + SW_H) / 2, pos.Z) + dir)
	return part(parent, "KerbRamp", V3(w or 6, SW_H - ROAD_Y, 2.4), cf, SIDEWALK, M.Concrete, { class = "WedgePart", collide = true })
end

------------------------------------------------------------------------
-- street lights and traffic signals
------------------------------------------------------------------------
-- street light standing at base; dir = horizontal unit vector from the pole out over the road
-- h: pole height (default Config.City.StreetLight = 30 = 8.4 m)
function K.streetLight(parent, base, dir, withLight, h)
	h = h or CITY.StreetLight
	local arm = h > 25 and 9 or 6.5
	local m = model(parent, "StreetLight")
	part(m, "LightBase", V3(1.6, 0.9, 1.6), CF(base + V3(0, 0.45, 0)), C.steel, M.Concrete, { collide = true })
	vcyl(m, "LightPole", h * 0.55, 0.8, CF(base), POLE, M.Metal, { collide = true })
	vcyl(m, "LightPoleUpper", h * 0.45 + 0.2, 0.6, CF(base + V3(0, h * 0.55 - 0.2, 0)), POLE, M.Metal)
	local a = base + V3(0, h - 0.6, 0)
	local armEnd = a + dir * arm + V3(0, 0.9, 0)
	K.rod(m, "LightArm", a, armEnd, 0.42, POLE, M.Metal)
	local head = part(m, "LightHead", V3(1.4, 0.7, 3.2), CFrame.lookAt(armEnd + dir * 0.6, armEnd + dir * 1.6), POLE, M.Metal)
	local lens = part(m, "LightLens", V3(1.1, 0.1, 2.6), head.CFrame * CF(0, -0.38, 0), LENS_DAY, M.SmoothPlastic, { shadow = false })
	tag(lens, "NightLens")
	if withLight then
		local l = spot(emitter(m, head.CFrame * CF(0, -1.0, 0)), Enum.NormalId.Bottom, Color3.fromRGB(255, 224, 180), h * 2.2, 2.4, 135)
		l.Enabled = false
		tag(l, "NightLight")
	end
	return m
end

-- a small park / garden lamp (3.5 m): pole, lantern head, a warm pool after dark
function K.parkLamp(parent, base, withLight)
	local m = model(parent, "ParkLamp")
	vcyl(m, "LampPole", 11, 0.5, CF(base), Color3.fromRGB(30, 32, 36), M.Metal, { collide = true })
	part(m, "LampHead", V3(1.6, 1.8, 1.6), CF(base + V3(0, 11.9, 0)), Color3.fromRGB(30, 32, 36), M.Metal)
	local lens = part(m, "LampLens", V3(1.2, 1.2, 1.2), CF(base + V3(0, 11.7, 0)), LENS_DAY, M.SmoothPlastic, { shadow = false })
	tag(lens, "NightLens")
	part(m, "LampCap", V3(2.0, 0.4, 2.0), CF(base + V3(0, 12.9, 0)), Color3.fromRGB(30, 32, 36), M.Metal)
	if withLight then
		K.nightPoint(m, CF(base + V3(0, 11.2, 0)), Color3.fromRGB(255, 220, 170), 30, 1.2)
	end
	return m
end

-- a traffic signal on a mast arm: pole at base, arm `reach` along dir over the road, two heads facing
-- `face` (towards the traffic they govern), a walk signal, a street-name blade, a controller cabinet
function K.trafficSignal(parent, base, dir, reach, face, streetName)
	local m = model(parent, "TrafficSignal")
	local h = CITY.Signal + 2 -- 20 studs = 5.6 m to the arm
	vcyl(m, "SignalPole", h, 0.9, CF(base), POLE, M.Metal, { collide = true })
	vcyl(m, "SignalFoot", 0.6, 1.6, CF(base), POLE, M.Metal, { collide = true })
	local armY = base.Y + h - 0.6
	local top = V3(base.X, armY, base.Z)
	local tip = top + dir * reach
	K.rod(m, "SignalArm", top, tip, 0.55, POLE, M.Metal)
	K.rod(m, "SignalBrace", V3(base.X, armY - 3.5, base.Z), top + dir * (reach * 0.45), 0.22, POLE, M.Metal)
	for _, fr in ipairs({ 0.55, 0.95 }) do
		local at = top:Lerp(tip, fr) - V3(0, 3.0, 0)
		local cf = CFrame.lookAt(at, at + face)
		part(m, "SignalHead", V3(1.5, 4.6, 1.3), cf, Color3.fromRGB(40, 40, 36), M.Metal)
		part(m, "SignalBack", V3(2.3, 5.4, 0.12), cf * CF(0, 0, 0.72), C.black, M.SmoothPlastic)
		part(m, "SignalHanger", V3(0.2, 0.8, 0.2), CF(at + V3(0, 2.65, 0)), POLE, M.Metal, { shadow = false })
		for _, l in ipairs({ { 1.45, Color3.fromRGB(110, 20, 20), M.SmoothPlastic }, { 0, Color3.fromRGB(110, 86, 20), M.SmoothPlastic }, { -1.45, Color3.fromRGB(60, 255, 120), M.Neon } }) do
			cyl(m, "SignalLens", 0.1, 1.05, cf * CF(0, l[1], -0.68) * ANG(0, RAD(90), 0), l[2], l[3], { shadow = false })
			part(m, "SignalVisor", V3(1.2, 0.12, 0.7), cf * CF(0, l[1] + 0.6, -0.95), Color3.fromRGB(40, 40, 36), M.Metal, { shadow = false })
		end
	end
	-- the walk signal facing along the crosswalk, the blade and the push button
	local ped = CFrame.lookAt(base + V3(0, 10.5, 0) - face * 0.8, base + V3(0, 10.5, 0) - face * 3)
	part(m, "WalkSignal", V3(1.4, 1.6, 0.8), ped, Color3.fromRGB(40, 40, 36), M.Metal)
	part(m, "WalkLens", V3(1.0, 1.1, 0.06), ped * CF(0, 0, -0.43), Color3.fromRGB(240, 240, 230), M.Neon, { transparency = 0.2, shadow = false })
	if streetName then
		local blade = part(m, "StreetBlade", V3(7, 1.3, 0.12), CFrame.lookAt(base + V3(0, 15.6, 0), base + V3(0, 15.6, 0) + face) * CF(2.6, 0, 0), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
		GymDecor.Sign(blade, Enum.NormalId.Front, streetName, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
		GymDecor.Sign(blade, Enum.NormalId.Back, streetName, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
	end
	part(m, "WalkButton", V3(0.5, 0.8, 0.4), CFrame.lookAt(base + V3(0, 4.2, 0), base + V3(0, 4.2, 0) - face) * CF(0, 0, -0.6), C.gold, M.Metal)
	return m
end

-- a street-name sign on its own pole (two blades when `cross` is given)
function K.streetSign(parent, pos, name, yaw, cross)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	vcyl(parent, "StreetSignPole", 11.5, 0.35, base, C.steel, M.Metal, { collide = true })
	local s = part(parent, "StreetSign", V3(7, 1.3, 0.12), base * CF(0, 10.8, 0), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
	GymDecor.Sign(s, Enum.NormalId.Front, name, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
	GymDecor.Sign(s, Enum.NormalId.Back, name, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
	if cross then
		local s2 = part(parent, "StreetSign", V3(7, 1.3, 0.12), base * CF(0, 9.4, 0) * ANG(0, RAD(90), 0), Color3.fromRGB(30, 110, 60), M.SmoothPlastic)
		GymDecor.Sign(s2, Enum.NormalId.Front, cross, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
		GymDecor.Sign(s2, Enum.NormalId.Back, cross, C.white, Color3.fromRGB(30, 110, 60), 40, nil, "signSub")
	end
	return s
end

-- a regulatory / warning sign on a pole: kind = "stop" | "speed" | "ped" | "noparking" | "oneway"
function K.roadSign(parent, pos, yaw, kind, text)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	vcyl(parent, "SignPole", 9, 0.3, base, C.steel, M.Metal, { collide = true })
	local s
	if kind == "stop" then
		s = part(parent, "StopSign", V3(3.2, 3.2, 0.1), base * CF(0, 8, 0) * ANG(0, 0, RAD(22.5)), Color3.fromRGB(190, 24, 30), M.SmoothPlastic)
		local s2 = part(parent, "StopSignFace", V3(3.2, 3.2, 0.12), base * CF(0, 8, 0), Color3.fromRGB(190, 24, 30), M.SmoothPlastic)
		GymDecor.Sign(s2, Enum.NormalId.Front, "STOP", C.white, Color3.fromRGB(190, 24, 30), 40)
	elseif kind == "speed" then
		s = part(parent, "SpeedSign", V3(2.6, 3.2, 0.1), base * CF(0, 7.8, 0), C.white, M.SmoothPlastic)
		GymDecor.Sign(s, Enum.NormalId.Front, "SPEED\nLIMIT\n" .. (text or "25"), C.black, C.white, 40, nil, "signSub")
	elseif kind == "ped" then
		s = part(parent, "PedSign", V3(3.0, 3.0, 0.1), base * CF(0, 7.9, 0) * ANG(0, 0, RAD(45)), Color3.fromRGB(250, 200, 40), M.SmoothPlastic)
		local s2 = part(parent, "PedSignFace", V3(2.0, 2.0, 0.12), base * CF(0, 7.9, 0), Color3.fromRGB(250, 200, 40), M.SmoothPlastic)
		GymDecor.Sign(s2, Enum.NormalId.Front, "XING", C.black, Color3.fromRGB(250, 200, 40), 40, nil, "signSub")
	elseif kind == "oneway" then
		s = part(parent, "OneWaySign", V3(4.2, 1.4, 0.1), base * CF(0, 8.2, 0), C.black, M.SmoothPlastic)
		GymDecor.Sign(s, Enum.NormalId.Front, "ONE WAY  >", C.white, C.black, 40, nil, "signSub")
	else
		s = part(parent, "NoParkingSign", V3(2.2, 3.0, 0.1), base * CF(0, 7.8, 0), C.white, M.SmoothPlastic)
		GymDecor.Sign(s, Enum.NormalId.Front, text or "NO\nPARKING", Color3.fromRGB(190, 24, 30), C.white, 40, nil, "signSub")
	end
	return s
end

------------------------------------------------------------------------
-- vehicles. cf = ground centre, nose towards local -Z. About 20 parts a car.
------------------------------------------------------------------------
K.CAR_COLORS = {
	Color3.fromRGB(190, 30, 36), Color3.fromRGB(235, 235, 238), Color3.fromRGB(28, 28, 32), Color3.fromRGB(40, 80, 170),
	Color3.fromRGB(150, 152, 158), Color3.fromRGB(30, 110, 70), Color3.fromRGB(230, 170, 40), Color3.fromRGB(120, 124, 132),
	Color3.fromRGB(80, 40, 30), Color3.fromRGB(200, 90, 40), Color3.fromRGB(60, 130, 170),
}
-- kind: length, width, body height, cabin height, cabin length, cabin offset (+ = back), bed (pickup)
local VEHICLES = {
	sedan = { L = 16, W = 5.7, B = 2.0, CH = 1.9, CL = 8.2, CO = 0.6 },
	hatch = { L = 14.5, W = 5.6, B = 2.0, CH = 2.0, CL = 8.6, CO = 1.2 },
	suv = { L = 17, W = 6.3, B = 2.7, CH = 2.4, CL = 9.6, CO = 0.9 },
	pickup = { L = 19, W = 6.6, B = 2.8, CH = 2.4, CL = 6.2, CO = -3.2, bed = true },
	van = { L = 18, W = 6.6, B = 3.2, CH = 3.6, CL = 13.5, CO = 1.6, box = true },
	taxi = { L = 16, W = 5.7, B = 2.0, CH = 1.9, CL = 8.2, CO = 0.6, taxi = true },
}
K.VEHICLES = VEHICLES

function K.car(parent, cf, color, kind)
	local s = VEHICLES[kind or "sedan"] or VEHICLES.sedan
	local L, W, B, CH, CL, CO = s.L, s.W, s.B, s.CH, s.CL, s.CO
	local m = model(parent, "Car")
	m:SetAttribute("Kind", kind or "sedan")
	local glass = Color3.fromRGB(40, 54, 70)
	local dark = Color3.fromRGB(22, 22, 26)
	local wheelR = 1.25
	local bodyY0 = 1.0 -- body underside
	color = color or K.CAR_COLORS[1]
	if s.taxi then
		color = Color3.fromRGB(245, 200, 30)
	end
	part(m, "CarBody", V3(W, B, L), cf * CF(0, bodyY0 + B / 2, 0), color, M.SmoothPlastic, { collide = true, reflect = 0.06 })
	-- cabin: windscreen wedge, box, rear wedge (a van is a box all the way up)
	local cabY = bodyY0 + B + CH / 2
	local cw = W * 0.9
	if s.box then
		part(m, "CarCabin", V3(cw, CH, CL), cf * CF(0, cabY, CO), color, M.SmoothPlastic, { reflect = 0.06 })
		part(m, "CarGlassSide", V3(cw + 0.04, CH * 0.5, CL * 0.45), cf * CF(0, cabY + CH * 0.1, CO - CL * 0.2), glass, M.Glass, { reflect = 0.15, shadow = false })
		part(m, "Windscreen", V3(cw * 0.96, CH * 0.7, 0.1), cf * CF(0, cabY + CH * 0.05, CO - CL / 2 - 0.02), glass, M.Glass, { reflect = 0.15, shadow = false })
	else
		part(m, "Windscreen", V3(cw, CH, CH * 1.2), cf * CF(0, cabY, CO - CL / 2 + CH * 0.6), glass, M.Glass, { class = "WedgePart", reflect = 0.15 })
		part(m, "CarCabin", V3(cw, CH, CL - CH * 2.1), cf * CF(0, cabY, CO + CH * 0.15), glass, M.Glass, { reflect = 0.15 })
		part(m, "RearGlass", V3(cw, CH, CH * 0.9), cf * CF(0, cabY, CO + CL / 2 - CH * 0.45) * ANG(0, RAD(180), 0), glass, M.Glass, { class = "WedgePart", reflect = 0.15 })
		part(m, "CarRoof", V3(cw * 0.98, 0.2, CL - CH * 2.0), cf * CF(0, cabY + CH / 2 + 0.1, CO + CH * 0.15), color, M.SmoothPlastic, { reflect = 0.06 })
		-- pillars read as dark bands: one thin frame along the roof edge each side
		for _, x in ipairs({ -1, 1 }) do
			part(m, "CarPillar", V3(0.2, CH * 0.5, CL - CH * 2.0), cf * CF(x * (cw / 2 - 0.05), cabY + CH * 0.2, CO + CH * 0.15), dark, M.SmoothPlastic, { shadow = false })
		end
	end
	if s.bed then
		part(m, "BedSide", V3(0.3, 1.6, L * 0.42), cf * CF(-W / 2 + 0.15, bodyY0 + B + 0.8, L * 0.27), color, M.SmoothPlastic)
		part(m, "BedSide", V3(0.3, 1.6, L * 0.42), cf * CF(W / 2 - 0.15, bodyY0 + B + 0.8, L * 0.27), color, M.SmoothPlastic)
		part(m, "Tailgate", V3(W, 1.6, 0.3), cf * CF(0, bodyY0 + B + 0.8, L / 2 - 0.15), color, M.SmoothPlastic)
	end
	for _, x in ipairs({ -(W / 2 - 0.5), W / 2 - 0.5 }) do
		for _, z in ipairs({ -L * 0.31, L * 0.3 }) do
			cyl(m, "Wheel", 1.0, wheelR * 2, cf * CF(x, wheelR, z), dark, M.Rubber)
		end
	end
	for _, x in ipairs({ -W * 0.32, W * 0.32 }) do
		part(m, "Headlight", V3(1.3, 0.6, 0.12), cf * CF(x, bodyY0 + B * 0.7, -L / 2 - 0.04), Color3.fromRGB(255, 250, 230), M.Neon, { shadow = false })
		part(m, "Taillight", V3(1.3, 0.55, 0.12), cf * CF(x, bodyY0 + B * 0.7, L / 2 + 0.04), Color3.fromRGB(220, 30, 30), M.Neon, { shadow = false })
	end
	part(m, "BumperF", V3(W + 0.2, 0.7, 0.5), cf * CF(0, bodyY0 + 0.4, -L / 2 - 0.1), dark, M.SmoothPlastic)
	part(m, "BumperB", V3(W + 0.2, 0.7, 0.5), cf * CF(0, bodyY0 + 0.4, L / 2 + 0.1), dark, M.SmoothPlastic)
	part(m, "Plate", V3(1.8, 0.6, 0.06), cf * CF(0, bodyY0 + 0.95, L / 2 + 0.38), C.white, M.SmoothPlastic, { shadow = false })
	if s.taxi then
		local ts = part(m, "TaxiSign", V3(3.0, 0.9, 1.0), cf * CF(0, cabY + CH / 2 + 0.65, CO), Color3.fromRGB(250, 240, 200), M.Neon, { shadow = false })
		GymDecor.Sign(ts, Enum.NormalId.Left, "TAXI", C.black, Color3.fromRGB(250, 240, 200), 40)
		GymDecor.Sign(ts, Enum.NormalId.Right, "TAXI", C.black, Color3.fromRGB(250, 240, 200), 40)
	end
	return m
end

-- a city bus (12 m): cf = ground centre, nose towards local -Z
function K.bus(parent, cf, color, line)
	local L, W, H = 42, 8.6, 11
	local m = model(parent, "Bus")
	color = color or Color3.fromRGB(235, 235, 232)
	local glass = Color3.fromRGB(40, 54, 70)
	part(m, "BusBody", V3(W, H - 2.4, L), cf * CF(0, 1.6 + (H - 2.4) / 2, 0), color, M.SmoothPlastic, { collide = true })
	part(m, "BusStripe", V3(W + 0.04, 1.4, L), cf * CF(0, 4.6, 0), Color3.fromRGB(30, 90, 190), M.SmoothPlastic, { shadow = false })
	part(m, "BusWindows", V3(W + 0.06, 3.4, L * 0.78), cf * CF(0, 7.4, 1.2), glass, M.Glass, { reflect = 0.15, shadow = false })
	part(m, "BusWindscreen", V3(W * 0.92, 4.6, 0.1), cf * CF(0, 6.9, -L / 2 - 0.02), glass, M.Glass, { reflect = 0.15, shadow = false })
	part(m, "BusRoof", V3(W * 0.98, 0.5, L * 0.98), cf * CF(0, H - 0.25 + 1.2, 0), color:Lerp(Color3.new(0, 0, 0), 0.15), M.SmoothPlastic)
	part(m, "BusDoor", V3(0.1, 7.6, 3.4), cf * CF(W / 2 + 0.03, 5.4, -L / 2 + 5), glass, M.Glass, { reflect = 0.1, shadow = false })
	part(m, "BusDoor", V3(0.1, 7.6, 3.4), cf * CF(W / 2 + 0.03, 5.4, L * 0.15), glass, M.Glass, { reflect = 0.1, shadow = false })
	for _, x in ipairs({ -(W / 2 - 0.6), W / 2 - 0.6 }) do
		for _, z in ipairs({ -L * 0.36, L * 0.3 }) do
			cyl(m, "Wheel", 1.2, 3.4, cf * CF(x, 1.7, z), Color3.fromRGB(22, 22, 26), M.Rubber)
		end
	end
	for _, x in ipairs({ -W * 0.34, W * 0.34 }) do
		part(m, "Headlight", V3(1.6, 0.8, 0.12), cf * CF(x, 3.0, -L / 2 - 0.04), Color3.fromRGB(255, 250, 230), M.Neon, { shadow = false })
		part(m, "Taillight", V3(1.4, 1.2, 0.12), cf * CF(x, 3.4, L / 2 + 0.04), Color3.fromRGB(220, 30, 30), M.Neon, { shadow = false })
	end
	local dest = part(m, "BusDestination", V3(W * 0.7, 1.3, 0.12), cf * CF(0, 10.0, -L / 2 - 0.04), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
	GymDecor.Sign(dest, Enum.NormalId.Front, line or "12  DOWNTOWN", Color3.fromRGB(255, 190, 40), Color3.fromRGB(20, 20, 24), 40, nil, "screen")
	part(m, "BumperF", V3(W, 0.8, 0.5), cf * CF(0, 1.5, -L / 2 - 0.2), Color3.fromRGB(22, 22, 26), M.SmoothPlastic)
	return m
end

------------------------------------------------------------------------
-- trees and planting
------------------------------------------------------------------------
local LEAF = {
	Color3.fromRGB(56, 118, 54), Color3.fromRGB(70, 132, 58), Color3.fromRGB(48, 106, 50), Color3.fromRGB(86, 140, 62), Color3.fromRGB(64, 124, 70),
}
local AUTUMN = { Color3.fromRGB(200, 110, 40), Color3.fromRGB(214, 140, 50), Color3.fromRGB(170, 70, 40), Color3.fromRGB(226, 170, 60) }

-- kinds: oak (round crown), maple (autumn), poplar (tall narrow), pine (tiered), palm, birch (white
-- trunk, light crown), cherry (pink). h = height in studs (a street tree ~30, a park oak 40-48)
function K.tree(parent, pos, kind, h, rng)
	kind = kind or "oak"
	local m = model(parent, "Tree")
	m:SetAttribute("Kind", kind)
	local function pick(list)
		return list[rng and rng:NextInteger(1, #list) or 1]
	end
	if kind == "pine" then
		vcyl(m, "PineTrunk", h * 0.38, h * 0.07, CF(pos), Color3.fromRGB(88, 60, 40), M.Wood, { collide = true })
		local col = pick({ Color3.fromRGB(36, 86, 50), Color3.fromRGB(42, 96, 54), Color3.fromRGB(30, 78, 46) })
		for i = 0, 3 do
			local t = i / 3
			blob(m, "PineTier", V3(h * (0.52 - t * 0.3), h * 0.3, h * (0.52 - t * 0.3)), CF(pos + V3(0, h * (0.36 + t * 0.52), 0)), col, M.Grass)
		end
		blob(m, "PineTop", V3(h * 0.14, h * 0.22, h * 0.14), CF(pos + V3(0, h * 0.98, 0)), col, M.Grass)
	elseif kind == "palm" then
		local lean = V3(rng and rng:NextNumber(-0.16, 0.16) or 0.08, 1, rng and rng:NextNumber(-0.16, 0.16) or 0)
		local p = pos
		for k = 0, 2 do
			local top = p + lean * (h / 3)
			GymDecor.Rod(m, "PalmTrunk", p, top, 1.6 - k * 0.3, Color3.fromRGB(128, 102, 70), M.Wood, { collide = k == 0 })
			p = top
		end
		for k = 0, 6 do
			local a = k * RAD(51) + (rng and rng:NextNumber(-0.2, 0.2) or 0)
			blob(m, "PalmFrond", V3(2.4, 0.6, 11), CF(p) * ANG(0, a, 0) * CF(0, -0.8, -4.6) * ANG(RAD(-24), 0, 0), Color3.fromRGB(52, 128, 56), M.Grass)
		end
		ball(m, "Coconuts", 1.6, CF(p + V3(0, -1.0, 0)), Color3.fromRGB(90, 70, 40), M.Wood)
	elseif kind == "poplar" then
		vcyl(m, "TreeTrunk", h * 0.34, h * 0.05, CF(pos), Color3.fromRGB(100, 80, 56), M.Wood, { collide = true })
		local col = pick(LEAF)
		blob(m, "Canopy", V3(h * 0.3, h * 0.78, h * 0.3), CF(pos + V3(0, h * 0.58, 0)), col, M.Grass)
		blob(m, "Canopy", V3(h * 0.22, h * 0.4, h * 0.22), CF(pos + V3(h * 0.04, h * 0.84, 0)), col:Lerp(Color3.new(1, 1, 1), 0.08), M.Grass)
	else
		local trunkCol = kind == "birch" and Color3.fromRGB(222, 220, 212) or Color3.fromRGB(96, 66, 42)
		local cols = kind == "maple" and AUTUMN or LEAF
		local col = pick(cols)
		if kind == "cherry" then
			col = pick({ Color3.fromRGB(236, 150, 180), Color3.fromRGB(246, 180, 200), Color3.fromRGB(228, 130, 160) })
		elseif kind == "birch" then
			col = pick({ Color3.fromRGB(120, 170, 80), Color3.fromRGB(140, 184, 90) })
		end
		vcyl(m, "TreeTrunk", h * 0.5, h * 0.075, CF(pos), trunkCol, M.Wood, { collide = true })
		local r = h * 0.74
		blob(m, "Canopy", V3(r, h * 0.56, r), CF(pos + V3(0, h * 0.68, 0)), col, M.Grass)
		blob(m, "Canopy", V3(r * 0.7, h * 0.44, r * 0.7), CF(pos + V3(r * 0.22, h * 0.84, r * 0.12)), col:Lerp(Color3.new(1, 1, 1), 0.1), M.Grass)
		blob(m, "Canopy", V3(r * 0.62, h * 0.4, r * 0.62), CF(pos + V3(-r * 0.2, h * 0.62, -r * 0.16)), col:Lerp(Color3.new(0, 0, 0), 0.1), M.Grass)
	end
	return m
end

-- a sidewalk tree in a pit with a grate
function K.streetTree(parent, pos, rng, h)
	part(parent, "TreePit", V3(4, 0.06, 4), CF(pos + V3(0, 0.03, 0)), K.SOIL, M.Ground, { shadow = false })
	part(parent, "TreeGrate", V3(4.2, 0.08, 4.2), CF(pos + V3(0, 0.04, 0)), Color3.fromRGB(50, 50, 54), M.DiamondPlate, { shadow = false })
	local m = K.tree(parent, pos, (rng and rng:NextNumber() < 0.25) and "cherry" or "oak", h or (rng and rng:NextNumber(24, 30) or 27), rng)
	-- a street tree is pruned up: a narrower crown than a park oak, clear of the awnings
	for _, d in ipairs(m:GetChildren()) do
		if d.Name == "Canopy" then
			d.Size = d.Size * Vector3.new(0.8, 0.9, 0.8)
		end
	end
	return m
end

-- a shrub / bush
function K.shrub(parent, pos, d, rng)
	d = d or 3
	return blob(parent, "Shrub", V3(d, d * 0.7, d * 0.9), CF(pos + V3(0, d * 0.32, 0)), LEAF[rng and rng:NextInteger(1, #LEAF) or 2], M.Grass)
end

------------------------------------------------------------------------
-- street furniture
------------------------------------------------------------------------
-- park bench along local X (yaw rotates it): slatted seat at 0.45 m, backrest, cast-iron ends
function K.bench(parent, pos, yaw, length, color)
	length = length or 6.4
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	local m = model(parent, "Bench")
	part(m, "BenchSeat", V3(length, 0.3, 1.9), base * CF(0, 1.55, 0), color or C.wood, M.WoodPlanks, { collide = true })
	part(m, "BenchBack", V3(length, 1.5, 0.28), base * CF(0, 2.55, 0.9) * ANG(RAD(-10), 0, 0), color or C.wood, M.WoodPlanks)
	for _, x in ipairs({ -length / 2 + 0.6, length / 2 - 0.6 }) do
		part(m, "BenchEnd", V3(0.3, 1.5, 1.8), base * CF(x, 0.75, 0), POLE, M.Metal)
		part(m, "BenchArm", V3(0.3, 0.2, 1.6), base * CF(x, 2.3, -0.1), POLE, M.Metal, { shadow = false })
	end
	return m
end

function K.bin(parent, pos, color)
	local m = model(parent, "TrashCan")
	vcyl(m, "BinBody", 3.4, 2.2, CF(pos), color or Color3.fromRGB(36, 70, 52), M.Metal, { collide = true })
	vcyl(m, "BinBand", 0.3, 2.26, CF(pos + V3(0, 2.4, 0)), C.gold, M.Metal, { shadow = false })
	vcyl(m, "BinLid", 0.4, 2.4, CF(pos + V3(0, 3.4, 0)), Color3.fromRGB(30, 60, 44), M.Metal)
	return m
end

function K.hydrant(parent, pos)
	local m = model(parent, "Hydrant")
	vcyl(m, "HydrantBarrel", 2.6, 1.0, CF(pos), Color3.fromRGB(200, 34, 34), M.Metal, { collide = true })
	ball(m, "HydrantBonnet", 1.1, CF(pos + V3(0, 2.8, 0)), Color3.fromRGB(200, 34, 34), M.Metal)
	cyl(m, "HydrantNozzles", 1.8, 0.5, CF(pos + V3(0, 1.8, 0)), Color3.fromRGB(200, 200, 205), M.Metal)
	return m
end

-- a concrete planter with shrubs (len along local X)
function K.planter(parent, cf, len, w)
	len, w = len or 6, w or 2.4
	local m = model(parent, "Planter")
	part(m, "PlanterBox", V3(len, 1.8, w), cf * CF(0, 0.9, 0), Color3.fromRGB(150, 146, 138), M.Concrete, { collide = true })
	part(m, "PlanterSoil", V3(len - 0.4, 0.1, w - 0.4), cf * CF(0, 1.75, 0), K.SOIL, M.Ground, { shadow = false })
	local n = math.max(1, math.floor(len / 2.6))
	for k = 0, n - 1 do
		local x = -len / 2 + (k + 0.5) * len / n
		blob(m, "Shrub", V3(len / n * 0.95, 2.0, w * 0.9), cf * CF(x, 2.6, 0), LEAF[(k % #LEAF) + 1], M.Grass)
	end
	return m
end

function K.bollard(parent, pos, color)
	vcyl(parent, "Bollard", 3.2, 0.9, CF(pos), color or Color3.fromRGB(60, 62, 68), M.Metal, { collide = true })
	return vcyl(parent, "BollardBand", 0.3, 0.94, CF(pos + V3(0, 2.6, 0)), C.gold, M.SmoothPlastic, { shadow = false })
end

function K.bikeRack(parent, cf)
	local m = model(parent, "BikeRack")
	for k = 0, 2 do
		local x = -2.4 + k * 2.4
		GymDecor.Rod(m, "RackLoop", (cf * CF(x, 0, -0.8)).Position, (cf * CF(x, 2.8, -0.8)).Position, 0.18, C.steelLight, M.Metal)
		GymDecor.Rod(m, "RackLoop", (cf * CF(x, 0, 0.8)).Position, (cf * CF(x, 2.8, 0.8)).Position, 0.18, C.steelLight, M.Metal)
		GymDecor.Rod(m, "RackLoop", (cf * CF(x, 2.8, -0.8)).Position, (cf * CF(x, 2.8, 0.8)).Position, 0.18, C.steelLight, M.Metal)
	end
	return m
end

-- picnic table (top along local X)
function K.picnicTable(parent, pos, yaw)
	local base = CF(pos) * ANG(0, yaw or 0, 0)
	local m = model(parent, "PicnicTable")
	part(m, "PicnicTop", V3(7.5, 0.3, 3), base * CF(0, 2.7, 0), C.wood, M.WoodPlanks, { collide = true })
	for _, z in ipairs({ -2.5, 2.5 }) do
		part(m, "PicnicSeat", V3(7.5, 0.25, 1.2), base * CF(0, 1.6, z), C.wood, M.WoodPlanks, { collide = true })
	end
	for _, x in ipairs({ -2.8, 2.8 }) do
		part(m, "PicnicLeg", V3(0.3, 2.7, 5.6), base * CF(x, 1.35, 0), C.woodDark, M.Wood)
	end
	return m
end

-- a bus shelter facing the road at local -Z: pad, glass back and side, roof, bench, an ad panel
-- (tagged CityScreen / BusAd so CityVisuals can put the player's promo on it), a stop sign
function K.busStop(parent, cf, line)
	local m = model(parent, "BusStop")
	local w, d = 16, 6
	part(m, "BusPad", V3(w + 4, 0.06, d + 2), cf * CF(0, SW_H + 0.03, 0.4), K.PAVING, M.Pavement, { shadow = false })
	part(m, "BusRoof", V3(w, 0.4, d), cf * CF(0, SW_H + 9.6, 0.4), Color3.fromRGB(40, 44, 52), M.Metal)
	part(m, "BusBack", V3(w - 0.6, 8.2, 0.2), cf * CF(0, SW_H + 4.9, d / 2 + 0.3), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false, collide = true })
	part(m, "BusSide", V3(0.2, 8.2, d - 0.6), cf * CF(-w / 2 + 0.2, SW_H + 4.9, 0.4), Color3.fromRGB(180, 210, 230), M.Glass, { transparency = 0.5, shadow = false, collide = true })
	for _, x in ipairs({ -w / 2 + 0.3, w / 2 - 0.3 }) do
		part(m, "BusPost", V3(0.35, 9.4, 0.35), cf * CF(x, SW_H + 4.7, d / 2 + 0.3), Color3.fromRGB(40, 44, 52), M.Metal, { collide = true })
		part(m, "BusPost", V3(0.35, 9.4, 0.35), cf * CF(x, SW_H + 4.7, -d / 2 + 0.5), Color3.fromRGB(40, 44, 52), M.Metal, { collide = true })
	end
	K.bench(m, (cf * CF(-2.2, SW_H, d / 2 - 1.3)).Position, 0, 7, C.wood)
	local ad = part(m, "BusAd", V3(4.6, 6.6, 0.25), cf * CF(w / 2 - 3.2, SW_H + 4.6, d / 2 + 0.05), C.black, M.SmoothPlastic)
	GymDecor.PosterGui(ad, Enum.NormalId.Front, GymDecor.Posters[3])
	ad:SetAttribute("Kind", "BusAd")
	tag(ad, "CityScreen")
	vcyl(m, "BusSignPole", 12, 0.35, cf * CF(w / 2 + 2.2, SW_H, -d / 2 + 0.6), C.steel, M.Metal, { collide = true })
	local bsign = part(m, "BusSign", V3(2.6, 2.0, 0.15), cf * CF(w / 2 + 2.2, SW_H + 11.2, -d / 2 + 0.6), Color3.fromRGB(30, 90, 190), M.SmoothPlastic)
	GymDecor.Sign(bsign, Enum.NormalId.Front, line or "BUS 12", C.white, Color3.fromRGB(30, 90, 190), 40)
	GymDecor.Sign(bsign, Enum.NormalId.Back, line or "BUS 12", C.white, Color3.fromRGB(30, 90, 190), 40)
	return m
end

-- a street vendor's cart (hot dogs / coffee / fruit / ice cream), facing local -Z, with its umbrella
function K.vendorCart(parent, cf, kind)
	local spec = ({
		hotdog = { name = "HOT DOGS", body = Color3.fromRGB(220, 222, 226), canopy = Color3.fromRGB(230, 60, 60), stripe = C.white },
		coffee = { name = "COFFEE", body = Color3.fromRGB(80, 56, 40), canopy = Color3.fromRGB(60, 40, 30), stripe = Color3.fromRGB(240, 220, 190) },
		fruit = { name = "FRESH FRUIT", body = Color3.fromRGB(70, 130, 70), canopy = Color3.fromRGB(250, 200, 50), stripe = Color3.fromRGB(60, 140, 70) },
		icecream = { name = "ICE CREAM", body = Color3.fromRGB(245, 240, 236), canopy = Color3.fromRGB(240, 130, 170), stripe = C.white },
		pretzel = { name = "PRETZELS", body = Color3.fromRGB(200, 60, 50), canopy = Color3.fromRGB(240, 200, 60), stripe = Color3.fromRGB(200, 60, 50) },
	})[kind or "hotdog"]
	local m = model(parent, "VendorCart")
	part(m, "CartBody", V3(6.4, 3.4, 3.2), cf * CF(0, 2.4, 0), spec.body, M.SmoothPlastic, { collide = true })
	part(m, "CartTop", V3(6.6, 0.25, 3.4), cf * CF(0, 4.2, 0), Color3.fromRGB(200, 204, 210), M.Metal)
	for _, x in ipairs({ -2.4, 2.4 }) do
		cyl(m, "CartWheel", 0.5, 2.2, cf * CF(x, 1.1, 0.4), Color3.fromRGB(26, 26, 28), M.Rubber)
	end
	local cs = part(m, "CartSign", V3(5.6, 1.1, 0.1), cf * CF(0, 3.2, -1.66), spec.canopy, M.SmoothPlastic)
	GymDecor.Sign(cs, Enum.NormalId.Front, spec.name, C.white, spec.canopy, 40)
	vcyl(m, "UmbrellaPole", 8.6, 0.25, cf * CF(1.6, 4.3, 0.2), C.steelLight, M.Metal)
	blob(m, "Umbrella", V3(9, 2.0, 9), cf * CF(1.6, 12.4, 0.2), spec.canopy, M.Fabric, { shadow = true })
	blob(m, "UmbrellaStripe", V3(6.2, 1.6, 6.2), cf * CF(1.6, 12.9, 0.2), spec.stripe, M.Fabric, { shadow = false })
	if kind == "hotdog" or kind == "pretzel" then
		part(m, "Griddle", V3(2.2, 0.15, 1.6), cf * CF(-1.4, 4.4, 0), Color3.fromRGB(40, 40, 44), M.Metal)
		blob(m, "Buns", V3(1.6, 0.6, 1.1), cf * CF(1.2, 4.6, -0.4), Color3.fromRGB(220, 170, 100), M.SmoothPlastic, { shadow = false })
	elseif kind == "fruit" then
		for k, col in ipairs({ Color3.fromRGB(230, 60, 50), Color3.fromRGB(250, 170, 40), Color3.fromRGB(120, 200, 60) }) do
			blob(m, "FruitCrate", V3(1.8, 0.9, 1.6), cf * CF(-2 + k * 1.3, 4.7, -0.3), col, M.SmoothPlastic, { shadow = false })
		end
	else
		vcyl(m, "Urn", 1.8, 1.0, cf * CF(-1.6, 4.3, 0.2), Color3.fromRGB(200, 204, 210), M.Metal)
	end
	return m
end

-- a flag on a pole (h studs), the cloth printed both sides when text is given
function K.flagPole(parent, base, h, color, text, textColor)
	h = h or 36
	vcyl(parent, "FlagPole", h, 0.5, CF(base), C.steelLight, M.Metal, { collide = true })
	ball(parent, "FlagPoleTop", 0.9, CF(base + V3(0, h + 0.2, 0)), C.gold, M.Metal)
	local fl = part(parent, "Flag", V3(0.1, h * 0.17, h * 0.27), CF(base + V3(0, h - h * 0.11, -h * 0.14)), color, M.Fabric, { shadow = false })
	if text then
		GymDecor.Sign(fl, Enum.NormalId.Right, text, textColor or C.white, nil, 30)
		GymDecor.Sign(fl, Enum.NormalId.Left, text, textColor or C.white, nil, 30)
	end
	return fl
end

------------------------------------------------------------------------
-- fences and walls (between two ground points a and b)
------------------------------------------------------------------------
local function run(a, b)
	local d = b - a
	local len = d.Magnitude
	return CFrame.lookAt((a + b) / 2, b) * ANG(0, RAD(90), 0), len
end

-- chain-link: a see-through panel with posts every 12 studs and a top rail
function K.fenceChain(parent, a, b, h)
	h = h or 7
	local cf, len = run(a, b)
	part(parent, "ChainLink", V3(len, h - 0.3, 0.1), cf * CF(0, 0.3 + (h - 0.3) / 2, 0), Color3.fromRGB(150, 155, 160), M.DiamondPlate, { transparency = 0.72, shadow = false, collide = true })
	part(parent, "FenceRail", V3(len, 0.2, 0.2), cf * CF(0, h, 0), Color3.fromRGB(120, 124, 130), M.Metal)
	local n = math.max(1, math.floor(len / 12))
	for k = 0, n do
		part(parent, "FencePost", V3(0.3, h + 0.2, 0.3), cf * CF(-len / 2 + k * len / n, (h + 0.2) / 2, 0), Color3.fromRGB(110, 114, 120), M.Metal)
	end
end

-- white picket fence (1.1 m): two rails, pickets read through a slotted panel
function K.fencePicket(parent, a, b)
	local cf, len = run(a, b)
	part(parent, "PicketPanel", V3(len, 3.6, 0.2), cf * CF(0, 1.9, 0), C.white, M.Wood, { transparency = 0.4, shadow = false, collide = true })
	for _, y in ipairs({ 1.4, 3.0 }) do
		part(parent, "FenceRail", V3(len, 0.3, 0.3), cf * CF(0, y, 0), C.white, M.Wood)
	end
	local n = math.max(1, math.floor(len / 8))
	for k = 0, n do
		part(parent, "FencePost", V3(0.45, 4.0, 0.45), cf * CF(-len / 2 + k * len / n, 2.0, 0), C.white, M.Wood)
	end
end

-- wrought-iron railing (h studs): dark panel, top rail, posts
function K.fenceIron(parent, a, b, h)
	h = h or 5
	local cf, len = run(a, b)
	part(parent, "IronPanel", V3(len, h - 0.4, 0.12), cf * CF(0, 0.2 + (h - 0.4) / 2, 0), Color3.fromRGB(26, 26, 30), M.Metal, { transparency = 0.55, shadow = false, collide = true })
	part(parent, "IronRail", V3(len, 0.25, 0.25), cf * CF(0, h, 0), Color3.fromRGB(26, 26, 30), M.Metal)
	local n = math.max(1, math.floor(len / 10))
	for k = 0, n do
		part(parent, "IronPost", V3(0.4, h + 0.3, 0.4), cf * CF(-len / 2 + k * len / n, (h + 0.3) / 2, 0), Color3.fromRGB(26, 26, 30), M.Metal)
	end
end

-- a brick / stone wall with coping
function K.wall(parent, a, b, h, color, material, copingColor)
	h = h or 5
	local cf, len = run(a, b)
	part(parent, "Wall", V3(len, h, 1.2), cf * CF(0, h / 2, 0), color or Color3.fromRGB(150, 128, 104), material or M.Brick, { collide = true })
	part(parent, "WallCoping", V3(len + 0.3, 0.35, 1.5), cf * CF(0, h + 0.17, 0), copingColor or Color3.fromRGB(214, 206, 190), M.Limestone)
end

-- a guard rail / promenade railing (1.1 m): posts and two rails
function K.railing(parent, a, b, color)
	local cf, len = run(a, b)
	color = color or Color3.fromRGB(40, 44, 52)
	part(parent, "RailTop", V3(len, 0.3, 0.3), cf * CF(0, 3.9, 0), color, M.Metal, { collide = true })
	part(parent, "RailMid", V3(len, 0.15, 0.15), cf * CF(0, 2.2, 0), color, M.Metal, { shadow = false })
	part(parent, "RailPanel", V3(len, 3.4, 0.08), cf * CF(0, 2.0, 0), color, M.Metal, { transparency = 0.7, shadow = false, collide = true })
	local n = math.max(1, math.floor(len / 8))
	for k = 0, n do
		part(parent, "RailPost", V3(0.3, 3.9, 0.3), cf * CF(-len / 2 + k * len / n, 1.95, 0), color, M.Metal)
	end
end

------------------------------------------------------------------------
-- parking lots: x1..x2, z1..z2; rows of 2.7 x 5 m bays along X (cars nose +-Z) with aisles between
-- opts: rng, fill (0..1 of bays with a car), rows ("auto"), reserved = bay index left empty
-- returns the list of bay CFrames (ground centre, nose into the bay)
------------------------------------------------------------------------
function K.parkingLot(parent, x1, x2, z1, z2, opts)
	opts = opts or {}
	local f = parent
	local rng = opts.rng or Random.new(7)
	local BAY_W, BAY_D, AISLE = 9.6, 18, 24
	slab(f, "ParkingLot", x1, x2, z1, z2, ROAD_Y - 0.02, opts.color or K.ASPHALT_OLD, M.Asphalt)
	local bays = {}
	local depth = z2 - z1
	-- rows: a bay row against each long edge, double rows in between as the depth allows
	local rows = {}
	if depth < BAY_D * 2 + AISLE then
		rows = { { z1, 1 } } -- one row at the z1 edge, cars nose -Z (towards z1)
	else
		local cursor = z1
		table.insert(rows, { cursor, -1 })
		cursor += BAY_D + AISLE
		while cursor + BAY_D * 2 + AISLE <= z2 - BAY_D do
			table.insert(rows, { cursor, 1 })
			table.insert(rows, { cursor + BAY_D, -1 })
			cursor += BAY_D * 2 + AISLE
		end
		table.insert(rows, { z2 - BAY_D, 1 })
	end
	local n = math.floor((x2 - x1 - 4) / BAY_W)
	local idx = 0
	for _, r in ipairs(rows) do
		local rz, dir = r[1], r[2]
		local lineZ = dir < 0 and rz or rz
		for k = 0, n do
			local x = x1 + 2 + k * BAY_W
			part(f, "BayLine", V3(0.35, 0.03, BAY_D), CF(x, MARK_Y, lineZ + BAY_D / 2), LINE_WHITE, M.SmoothPlastic, { shadow = false })
		end
		for k = 0, n - 1 do
			idx += 1
			local cx = x1 + 2 + (k + 0.5) * BAY_W
			local nose = dir < 0 and (rz + 1) or (rz + BAY_D - 1)
			local cf = CF(cx, ROAD_Y - 0.02, rz + BAY_D / 2) * ANG(0, dir < 0 and 0 or RAD(180), 0)
			table.insert(bays, cf)
			local _ = nose
			if opts.stops then
				part(f, "WheelStop", V3(6, 0.5, 0.7), CF(cx, ROAD_Y + 0.23, dir < 0 and rz + 2.2 or rz + BAY_D - 2.2), Color3.fromRGB(196, 192, 184), M.Concrete, { collide = true })
			end
			if idx ~= opts.reserved and rng:NextNumber() < (opts.fill or 0.5) then
				local kinds = { "sedan", "sedan", "hatch", "suv", "pickup", "van" }
				K.car(f, cf * ANG(0, RAD(rng:NextNumber(-2, 2)), 0), K.CAR_COLORS[rng:NextInteger(1, #K.CAR_COLORS)], kinds[rng:NextInteger(1, #kinds)])
			end
		end
	end
	if opts.lights ~= false then
		local step = 60
		local x = x1 + 30
		while x < x2 - 10 do
			K.streetLight(f, V3(x, ROAD_Y - 0.02, (z1 + z2) / 2), V3(0, 0, 1), true, 26)
			x += step
		end
	end
	return bays
end

------------------------------------------------------------------------
-- billboards and signs
------------------------------------------------------------------------
K.ADS = {
	{ title = "TONY'S PIZZA", sub = "SLICE OF CHAMPIONS - MAIN ST", bg = Color3.fromRGB(200, 30, 30), fg = Color3.fromRGB(255, 240, 200) },
	{ title = "IRON SUPPLEMENTS", sub = "BUILT IN THE GYM. FUELED BY IRON.", bg = Color3.fromRGB(26, 26, 28), fg = Color3.fromRGB(240, 110, 20) },
	{ title = "FIGHT NIGHT LIVE", sub = "GRAND ARENA - TICKETS ON MAIN ST", bg = Color3.fromRGB(150, 16, 24), fg = Color3.fromRGB(255, 220, 90) },
	{ title = "APEX ATHLETICS", sub = "OUTWORK EVERYONE", bg = Color3.fromRGB(20, 20, 20), fg = Color3.fromRGB(0, 170, 190) },
	{ title = "PRESTIGE MOTORS", sub = "DRIVE LIKE A CHAMPION", bg = Color3.fromRGB(16, 18, 24), fg = Color3.fromRGB(220, 220, 230) },
	{ title = "RIVERSIDE REALTY", sub = "LIVE WHERE THE CHAMPIONS LIVE", bg = Color3.fromRGB(20, 60, 110), fg = Color3.fromRGB(240, 240, 245) },
	{ title = "SUMMIT SPORTSWEAR", sub = "NEW SEASON - DOWNTOWN", bg = Color3.fromRGB(240, 236, 226), fg = Color3.fromRGB(30, 30, 34) },
	{ title = "WCB SPORTS NETWORK", sub = "EVERY FIGHT. LIVE.", bg = Color3.fromRGB(14, 14, 18), fg = Color3.fromRGB(255, 205, 83) },
}

-- Billboard on two steel legs with a catwalk and flood lights (w x h face; legs reach the ground
-- unless legH is given). Tagged CityBillboard (attribute Slot): CityVisuals swaps the ad locally.
function K.billboard(parent, cf, w, h, slot, ad, legH)
	local m = model(parent, "Billboard")
	legH = legH or (cf.Position.Y - h / 2)
	for _, x in ipairs({ -w * 0.3, w * 0.3 }) do
		if legH > 0.5 then
			part(m, "BillboardLeg", V3(1.2, legH + h / 2, 1.2), cf * CF(x, -(legH + h / 2) / 2, 1.2), POLE, M.Metal, { collide = true })
		end
		part(m, "BillboardBrace", V3(0.35, h * 0.9, 0.35), cf * CF(x, 0, 1.1), POLE, M.Metal)
	end
	part(m, "BillboardFrame", V3(w + 1.2, h + 1.2, 0.8), cf * CF(0, 0, 0.5), Color3.fromRGB(30, 32, 36), M.Metal)
	local face = part(m, "BillboardFace", V3(w, h, 0.2), cf * CF(0, 0, -0.05), Color3.fromRGB(240, 240, 240), M.SmoothPlastic)
	part(m, "Catwalk", V3(w, 0.25, 2.0), cf * CF(0, -h / 2 - 0.8, -0.8), C.steel, M.DiamondPlate)
	part(m, "CatwalkRail", V3(w, 0.15, 0.15), cf * CF(0, -h / 2 + 2.2, -1.75), C.steel, M.Metal, { shadow = false })
	for _, x in ipairs({ -w * 0.3, w * 0.3 }) do
		local arm = part(m, "FloodArm", V3(0.25, 0.25, 3.4), cf * CF(x, -h / 2 - 0.6, -2.2), POLE, M.Metal)
		local l = spot(emitter(m, arm.CFrame * CF(0, 0, -1.6)), Enum.NormalId.Top, Color3.fromRGB(255, 244, 220), h * 2.2, 1.4, 70)
		l.Enabled = false
		tag(l, "NightLight")
	end
	local sg = gui(face, Enum.NormalId.Front, 10, 0.2, 1200)
	sg.Name = "Ad"
	frame(sg, { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = ad.bg })
	label(sg, ad.title, { Name = "Title", TextColor3 = ad.fg, Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.08) })
	label(sg, ad.sub, { Name = "Sub", TextColor3 = ad.fg, Face = "signSub", Size = UDim2.fromScale(0.9, 0.26), Position = UDim2.fromScale(0.05, 0.64) })
	face:SetAttribute("Slot", slot)
	tag(face, "CityBillboard")
	return m, face
end

-- a free-standing double-sided sign on two posts (w x h board, its bottom edge at y)
function K.postSign(parent, cf, w, h, y, text, fg, bg, lockup)
	local m = model(parent, "PostSign")
	for _, x in ipairs({ -w / 2 + 0.6, w / 2 - 0.6 }) do
		part(m, "SignPost", V3(0.5, y + h, 0.5), cf * CF(x, (y + h) / 2, 0), bg or Color3.fromRGB(60, 40, 26), M.Wood, { collide = true })
	end
	local board = part(m, "SignBoard", V3(w, h, 0.4), cf * CF(0, y + h / 2, 0), bg or Color3.fromRGB(60, 40, 26), M.Wood)
	if lockup then
		Signage.Boards(board, { Enum.NormalId.Front, Enum.NormalId.Back }, lockup, { maxDist = 500 })
	else
		GymDecor.Sign(board, Enum.NormalId.Front, text, fg or Color3.fromRGB(255, 230, 170), bg or Color3.fromRGB(60, 40, 26), 30)
		GymDecor.Sign(board, Enum.NormalId.Back, text, fg or Color3.fromRGB(255, 230, 170), bg or Color3.fromRGB(60, 40, 26), 30)
	end
	return board
end

------------------------------------------------------------------------
-- buildings
------------------------------------------------------------------------
-- a generic street building. cf = ground centre of the FRONT face, its -Z towards the street; w along
-- local X, d back along +Z. floors = storeys above the ground floor (0 = a one-storey shop).
-- st: color, mat, trim (cornice colour), roof (colour), retail (ground-floor storefront: glass, door,
-- sign band with st.sign text / st.lockup), awning (colour), signBg / signFg, cols (window columns),
-- lit, rng, range (window draw range), corner (a second storefront on the local +X side), units (roof)
function K.building(parent, cf, w, d, floors, st)
	st = st or {}
	local rng = st.rng or Random.new(w * 7 + d)
	local G, S = CITY.GroundFloor, CITY.Storey
	local H = G + floors * S
	local m = model(parent, st.name or "Building")
	local color = st.color or Color3.fromRGB(176, 160, 140)
	local mat = st.mat or M.Brick
	local body = part(m, "BuildingBody", V3(w, H, d), cf * CF(0, H / 2, d / 2), color, mat, { collide = true })
	if floors >= 1 then
		K.windowGrid(body, Enum.NormalId.Front, H, G + 2.4, H - 2.0, floors, st.cols or math.max(2, math.floor(w / 9)), rng, st.lit or 0.35, st.range)
	end
	-- cornice and parapet
	part(m, "Cornice", V3(w + 1.0, 1.1, d + 1.0), cf * CF(0, H + 0.55, d / 2), st.trim or Color3.fromRGB(70, 66, 62), M.Concrete)
	part(m, "Parapet", V3(w, 1.6, 0.8), cf * CF(0, H + 1.9, 0.4), color, mat)
	-- storefront
	if st.retail ~= false then
		local glassTop = G - 3.4
		part(m, "ShopInterior", V3(w - 3, glassTop - 0.8, 0.12), cf * CF(0, 0.8 + (glassTop - 0.8) / 2, 0.07), Color3.fromRGB(36, 40, 48), M.SmoothPlastic)
		local win = part(m, "ShopWindow", V3(w - 3, glassTop - 0.8, 0.1), cf * CF(0, 0.8 + (glassTop - 0.8) / 2, -0.2), Color3.fromRGB(170, 205, 230), M.Glass, { transparency = 0.55, reflect = 0.12, shadow = false })
		win:SetAttribute("Shop", st.sign or "")
		local n = math.max(1, math.floor((w - 3) / 8))
		for k = 0, n do
			part(m, "Mullion", V3(0.3, glassTop - 0.8, 0.3), cf * CF(-(w - 3) / 2 + k * (w - 3) / n, 0.8 + (glassTop - 0.8) / 2, -0.2), Color3.fromRGB(30, 30, 34), M.Metal)
		end
		local doorX = st.doorAt and (w * st.doorAt) or (w * 0.3)
		part(m, "ShopDoor", V3(CITY.Door.w, CITY.Door.h, 0.15), cf * CF(doorX, 0.8 + CITY.Door.h / 2, -0.32), Color3.fromRGB(28, 28, 32), M.Metal)
		part(m, "Kickplate", V3(w - 3, 0.9, 0.3), cf * CF(0, 0.8 + 0.45, -0.15), Color3.fromRGB(40, 40, 44), M.Metal)
		for _, x in ipairs({ -w / 2 + 0.75, w / 2 - 0.75 }) do
			part(m, "ShopPier", V3(1.5, G, 0.5), cf * CF(x, G / 2, -0.25), color, mat, { collide = true })
		end
		if st.awning then
			part(m, "ShopAwning", V3(w - 2, 0.35, 5.4), cf * CF(0, glassTop + 1.4, -2.6) * ANG(RAD(-14), 0, 0), st.awning, M.Fabric)
		end
		local signPart = part(m, "ShopSign", V3(w - 2.6, 3.2, 0.4), cf * CF(0, G - 1.7, -0.25), st.signBg or Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
		if st.lockup then
			Signage.Board(signPart, Enum.NormalId.Front, st.lockup, { maxDist = 700 })
		elseif st.sign then
			local sg = gui(signPart, Enum.NormalId.Front, Signage.PPS(3.2, 0.8), 0, 700)
			frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = st.signBg or Color3.fromRGB(20, 20, 24) })
			label(sg, st.sign, { TextColor3 = st.signFg or C.gold, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
		end
		local glow = point(emitter(m, cf * CF(0, 6, -1.6)), Color3.fromRGB(255, 214, 160), 18, 0.9)
		glow.Enabled = false
		tag(glow, "NightLight")
	else
		-- a lobby: tall glass with a revolving-door bay
		part(m, "LobbyGlass", V3(w * 0.7, G - 1.5, 0.15), cf * CF(0, 0.8 + (G - 1.5) / 2, -0.1), Color3.fromRGB(150, 190, 220), M.Glass, { transparency = 0.45, reflect = 0.15, shadow = false })
		part(m, "LobbyDoor", V3(CITY.Door.w * 2.2, CITY.Door.h + 0.6, 0.3), cf * CF(0, 0.8 + (CITY.Door.h + 0.6) / 2, -0.3), Color3.fromRGB(30, 30, 34), M.Metal)
		part(m, "LobbyCanopy", V3(w * 0.5, 0.6, 7), cf * CF(0, G - 2.6, -3.5), Color3.fromRGB(30, 30, 34), M.Metal)
		if st.sign then
			local nameplate = part(m, "LobbySign", V3(w * 0.5, 2.2, 0.3), cf * CF(0, G - 1.0, -0.2), st.signBg or Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
			GymDecor.Sign(nameplate, Enum.NormalId.Front, st.sign, st.signFg or C.gold, st.signBg or Color3.fromRGB(20, 20, 24), 30)
		end
	end
	-- roof units
	local units = st.units or (floors >= 1 and 2 or 1)
	for _ = 1, units do
		part(m, "RoofUnit", V3(6, 3, 5), cf * CF(rng:NextNumber(-w / 3, w / 3), H + 1.5, d * rng:NextNumber(0.3, 0.7)), Color3.fromRGB(196, 198, 202), M.Metal)
	end
	if st.tank then
		local tp = cf * CF(w * 0.3, H + 1.1, d * 0.6)
		for _, o in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
			part(m, "TankLeg", V3(0.35, 5, 0.35), tp * CF(o[1], 2.5, o[2]), Color3.fromRGB(40, 42, 48), M.Metal)
		end
		vcyl(m, "WaterTank", 7, 6, tp * CF(0, 5, 0), Color3.fromRGB(120, 86, 60), M.WoodPlanks)
		part(m, "TankRoof", V3(6.4, 1.8, 6.4), tp * CF(0, 12.5, 0) * ANG(0, RAD(45), 0), Color3.fromRGB(60, 50, 44), M.Slate)
	end
	return m, body, H
end

-- a skyline / downtown tower: w x d footprint, h tall, facing `look` with its window grid; a setback cap,
-- an antenna on the tall ones. tone picks the facade.
function K.tower(parent, pos, w, d, h, look, rng, opts)
	opts = opts or {}
	local cf = CFrame.lookAt(pos + V3(0, h / 2, 0), pos + V3(0, h / 2, 0) + look)
	local tone = opts.tone or rng:NextInteger(0, 4)
	local palette = {
		{ Color3.fromRGB(70, 78, 92), M.Concrete, 0 }, { Color3.fromRGB(120, 122, 130), M.Concrete, 0 }, { Color3.fromRGB(62, 84, 110), M.SmoothPlastic, 0.18 },
		{ Color3.fromRGB(156, 144, 128), M.Concrete, 0 }, { Color3.fromRGB(44, 58, 76), M.SmoothPlastic, 0.2 },
	}
	local p = palette[tone + 1]
	local m = model(parent, opts.name or "Tower")
	local body = part(m, "Tower", V3(w, h, d), cf, p[1], p[2], { reflect = p[3], collide = true })
	local rows = math.max(2, math.floor(h / CITY.Storey))
	K.windowGrid(body, Enum.NormalId.Front, h, 6, h - 4, rows, math.max(3, math.floor(w / 8)), rng, opts.lit or 0.32, opts.range or 2500)
	if opts.allFaces then
		K.windowGrid(body, Enum.NormalId.Front, h, 6, h - 4, rows, math.max(3, math.floor(w / 8)), rng, opts.lit or 0.32, opts.range or 2500)
	end
	part(m, "TowerCap", V3(w * 0.62, 5, d * 0.62), cf * CF(0, h / 2 + 2.5, 0), p[1]:Lerp(Color3.new(0, 0, 0), 0.2), M.Concrete)
	if opts.crown then
		part(m, "TowerCrown", V3(w * 0.4, 4, d * 0.4), cf * CF(0, h / 2 + 7, 0), Color3.fromRGB(230, 220, 190), M.Neon, { shadow = false })
	end
	if h > 150 then
		part(m, "Antenna", V3(0.8, 26, 0.8), cf * CF(0, h / 2 + 17, 0), C.steelLight, M.Metal)
		ball(m, "AntennaLight", 1.6, cf * CF(0, h / 2 + 30.5, 0), Color3.fromRGB(255, 40, 40), M.Neon, { shadow = false })
	end
	return m, body
end

-- a house: W x D footprint, two storeys with a gable roof, porch, garage, door, windows
K.HOUSE_COLORS = {
	Color3.fromRGB(220, 206, 180), Color3.fromRGB(176, 196, 214), Color3.fromRGB(214, 180, 170), Color3.fromRGB(200, 214, 180),
	Color3.fromRGB(238, 236, 228), Color3.fromRGB(190, 170, 200), Color3.fromRGB(150, 168, 190), Color3.fromRGB(226, 200, 150),
}

------------------------------------------------------------------------
-- industrial / construction props
------------------------------------------------------------------------
function K.container(parent, cf, color, stackLabel)
	local c = part(parent, "Container", V3(43, 8.7, 8.7), cf * CF(0, 4.35, 0), color or Color3.fromRGB(150, 50, 40), M.DiamondPlate, { collide = true })
	part(parent, "ContainerDoors", V3(0.2, 8.0, 8.0), cf * CF(21.6, 4.35, 0), (color or Color3.fromRGB(150, 50, 40)):Lerp(Color3.new(0, 0, 0), 0.25), M.Metal, { shadow = false })
	if stackLabel then
		GymDecor.Sign(c, Enum.NormalId.Front, stackLabel, C.white, nil, 20, nil, "signSub")
	end
	return c
end

function K.dumpster(parent, cf, color)
	part(parent, "Dumpster", V3(8, 5, 4.6), cf * CF(0, 2.5, 0), color or Color3.fromRGB(40, 90, 50), M.Metal, { collide = true })
	part(parent, "DumpsterLid", V3(8.1, 0.25, 4.7), cf * CF(0, 5.1, 0) * ANG(RAD(-6), 0, 0), C.black, M.Plastic)
end

-- a traffic cone
function K.cone(parent, pos)
	part(parent, "ConeBase", V3(1.6, 0.15, 1.6), CF(pos + V3(0, 0.08, 0)), Color3.fromRGB(240, 110, 20), M.SmoothPlastic, { shadow = false })
	return blob(parent, "Cone", V3(1.0, 2.6, 1.0), CF(pos + V3(0, 1.3, 0)), Color3.fromRGB(240, 110, 20), M.SmoothPlastic)
end

-- a construction hoarding panel between a and b (2.2 m plywood with a printed notice)
function K.hoarding(parent, a, b, color)
	local cf, len = run(a, b)
	local p = part(parent, "Hoarding", V3(len, 7.8, 0.3), cf * CF(0, 3.9, 0), color or Color3.fromRGB(40, 90, 170), M.Wood, { collide = true })
	local n = math.max(1, math.floor(len / 12))
	for k = 0, n do
		part(parent, "HoardingPost", V3(0.5, 8.2, 0.5), cf * CF(-len / 2 + k * len / n, 4.1, 0.3), Color3.fromRGB(60, 50, 40), M.Wood)
	end
	return p
end

return K
