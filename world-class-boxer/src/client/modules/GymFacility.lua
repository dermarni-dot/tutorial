-- GymFacility: what YOUR gym looks like as a whole, drawn on your client only (everyone shares
-- the server shell; tier dressing is local, so one player's tier never overwrites another's).
-- Driven by the facility tier (Catalog.GymTier, Config.GymTiers) and your career:
--  * Beginner        water stains under the windows, grimy floor, drip buckets under roof leaks,
--                    flickering, dimmer and warmer pendant lamps, taped / peeling posters
--  * Intermediate    clean walls, sponsor banners over the floor, LED strips, an extra round timer
--  * Elite           cool LED accents, analytics screens with your training numbers and the Elite
--                    Performance Wing opens: cryotherapy cabin, hot & cold plunge pools, sports
--                    science lab with force plates and a body scanner, a motion-capture stage with
--                    tracking cameras, glass partitions, staff
--  * World Champion  gold trim, champion banners, a media backdrop with a camera crew, a red
--                    carpet, fans behind barriers at the door (more with popularity), title photos
-- Always: the career wall next to the Fight Board (your real fights), the trophy case with the
-- titles you actually won, the "YOURS" plates under the belts you hold and the sparring ring
-- (rope Beams with sag and physics, corner pads, apron, steps) matched to your ring level.
-- A tier going up plays a facility-upgrade reveal.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local GymSound = require(script.Parent:WaitForChild("GymSound"))

local GymFacility = {}
local player = Players.LocalPlayer

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local GOLD = rgb(255, 196, 40)
local GOLD_DEEP = rgb(212, 160, 40)
local WHITE = rgb(236, 236, 240)
local BLACK = rgb(24, 24, 28)
local DARK = rgb(14, 14, 18)
local STEEL = rgb(150, 153, 160)
local CHROME = rgb(215, 218, 225)
local RED = rgb(196, 30, 36)
local BLUE = rgb(30, 60, 170)
local ICE = rgb(150, 215, 255)
local TAPE = rgb(170, 172, 178)

------------------------------------------------------------------------
-- helpers (same conventions as GymVisuals: anchored, no collisions unless asked)
------------------------------------------------------------------------
local function part(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.wedge and "WedgePart" or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.collide == true
	p.CanQuery = opts.collide == true
	p.CanTouch = false
	p.CastShadow = opts.shadow ~= false
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflect then
		p.Reflectance = opts.reflect
	end
	if opts.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function cyl(parent, name, length, d, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return part(parent, name, V3(length, d, d), cf, color, material, opts)
end

local function vcyl(parent, name, h, d, baseCF, color, material, opts)
	return cyl(parent, name, h, d, baseCF * CF(0, h / 2, 0) * ANG(0, 0, RAD(90)), color, material, opts)
end

local function rod(parent, name, a, b, d, color, material, opts)
	local dir = b - a
	local up = math.abs(dir.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	return cyl(parent, name, dir.Magnitude, d, CFrame.lookAt((a + b) / 2, b, up) * ANG(0, RAD(90), 0), color, material, opts)
end

local function gui(p, face, ppu, lightInfluence)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 40
	sg.LightInfluence = lightInfluence or 0.4
	sg.MaxDistance = 200
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

local function sign(p, face, text, fg, bg, ppu, font)
	local sg = gui(p, face, ppu or 40, 0.3)
	if bg then
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
	end
	label(sg, text, { TextColor3 = fg or Color3.new(1, 1, 1), Font = font or Enum.Font.GothamBlack, Size = UDim2.fromScale(0.92, 0.84), Position = UDim2.fromScale(0.04, 0.08) })
	return sg
end

local function point(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

local function spot(p, face, color, range, brightness, angle)
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Angle = angle or 60
	l.Shadows = false
	l.Parent = p
	return l
end

local function newModel(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function c3(t, fallback)
	if type(t) == "table" and #t >= 3 then
		return rgb(t[1], t[2], t[3])
	end
	return fallback
end

local function gym()
	return workspace:FindFirstChild("Gym")
end

------------------------------------------------------------------------
-- keyed sub-builds: a sub-model is rebuilt only when its key changes
------------------------------------------------------------------------
local keys = {}
local function rebuild(root, name, key, builder, ...)
	local cur = root:FindFirstChild(name)
	if keys[name] == key and cur then
		return cur
	end
	if cur then
		cur:Destroy()
	end
	keys[name] = key
	local m = newModel(root, name)
	local ok, err = pcall(builder, m, ...)
	if not ok then
		warn("[GymFacility] " .. name .. ": " .. tostring(err))
	end
	return m
end

------------------------------------------------------------------------
-- 1. The pendant lamps: brightness / colour per tier, flicker in the Beginner gym
------------------------------------------------------------------------
local lampCache
local TIER_LIGHT = {
	{ mult = 0.78, tint = rgb(255, 196, 140), amt = 0.35 }, -- tired old tubes: dim and orange
	{ mult = 1.0, tint = nil, amt = 0 },
	{ mult = 1.08, tint = rgb(232, 242, 255), amt = 0.3 }, -- crisp daylight LEDs
	{ mult = 1.14, tint = rgb(255, 228, 182), amt = 0.22 }, -- warm, rich, gold
}
-- three pendants that flicker in a Beginner gym (one per zone, away from the stations' faces)
local FLICKER_AT = { V3(-30, 0, 0), V3(60, 0, -30), V3(-60, 0, 30) }

local function applyLamps(idx)
	local g = gym()
	local decor = g and g:FindFirstChild("Decor")
	local rig = decor and decor:FindFirstChild("Lighting")
	if not rig then
		return
	end
	if not lampCache or not lampCache.root or lampCache.root ~= rig then
		lampCache = { root = rig, lamps = {} }
		for _, m in ipairs(rig:GetChildren()) do
			if m.Name == "PendantLamp" then
				local entry = { model = m, lights = {} }
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("Light") then
						table.insert(entry.lights, { l = d, b = d.Brightness, c = d.Color })
					elseif d:IsA("BasePart") and d.Name == "LampBulb" then
						entry.bulb, entry.bulbC = d, d.Color
						entry.pos = d.Position
					end
				end
				table.insert(lampCache.lamps, entry)
			end
		end
	end
	local t = TIER_LIGHT[idx] or TIER_LIGHT[2]
	for _, e in ipairs(lampCache.lamps) do
		for _, li in ipairs(e.lights) do
			if li.l.Parent then
				li.l.Brightness = li.b * t.mult
				li.l.Color = t.tint and li.c:Lerp(t.tint, t.amt) or li.c
			end
		end
		if e.bulb and e.bulb.Parent then
			e.bulb.Color = t.tint and e.bulbC:Lerp(t.tint, t.amt * 0.8) or e.bulbC
		end
		-- flicker: tag locally (Ambience's NeonFlicker blinks the bulb and its lights)
		local flick = false
		if idx <= 1 and e.pos then
			for _, f in ipairs(FLICKER_AT) do
				if math.abs(e.pos.X - f.X) < 1 and math.abs(e.pos.Z - f.Z) < 1 then
					flick = true
				end
			end
		end
		local tagged = CollectionService:HasTag(e.model, "NeonFlicker")
		if flick and not tagged then
			CollectionService:AddTag(e.model, "NeonFlicker")
		elseif not flick and tagged then
			CollectionService:RemoveTag(e.model, "NeonFlicker")
		end
	end
end

-- the server's racks (loaner gloves, kettlebells, wall med balls) restyled per tier: rusty and
-- mismatched in a Beginner gym, a matched set at Elite, black and gold for the champion
local rackCache
local RACK_PARTS = { Glove = "glove", GloveCuff = "cuff", Kettlebell = "kb", KBHandle = "kbh", KBHandlePost = "kbh", MedBall = "ball" }
local function restyleRacks(idx)
	local g = gym()
	local decor = g and g:FindFirstChild("Decor")
	if not decor then
		return
	end
	if not rackCache or rackCache.root ~= decor then
		rackCache = { root = decor, parts = {} }
		for _, sec in ipairs({ "Boxing", "Weights" }) do
			local f = decor:FindFirstChild(sec)
			for _, p in ipairs(f and f:GetChildren() or {}) do
				local kind = RACK_PARTS[p.Name]
				if kind and p:IsA("BasePart") then
					table.insert(rackCache.parts, { p = p, kind = kind, c = p.Color, m = p.Material })
				end
			end
		end
	end
	local champ = idx >= 4
	local rust = rgb(120, 80, 52)
	for i, e in ipairs(rackCache.parts) do
		local p = e.p
		if p.Parent then
			local c, mat = e.c, e.m
			if idx <= 1 then
				-- worn: faded leather, rusty bells
				c = (e.kind == "kb" or e.kind == "kbh") and e.c:Lerp(rust, 0.45) or e.c:Lerp(rgb(110, 100, 90), 0.3)
			elseif idx >= 3 then
				if e.kind == "glove" then
					c = champ and ((i % 2 == 0) and GOLD or BLACK) or ((i % 2 == 0) and rgb(30, 60, 170) or BLACK)
				elseif e.kind == "cuff" then
					c = champ and GOLD or WHITE
				elseif e.kind == "kb" then
					c, mat = rgb(40, 40, 46), M.Metal
				elseif e.kind == "kbh" then
					c, mat = champ and GOLD or CHROME, M.Metal
				elseif e.kind == "ball" then
					c = champ and BLACK or rgb(30, 30, 36)
				end
			end
			p.Color = c
			p.Material = mat
		end
	end
end

------------------------------------------------------------------------
-- 2. Tier dressing in the main hall
------------------------------------------------------------------------
-- a stain / patch flat on a wall: wall = "N" | "S" | "W" | "E", along = coordinate along it
local WALL = {
	N = { axis = "X", plane = -78.95, n = V3(0, 0, 1) },
	S = { axis = "X", plane = 78.95, n = V3(0, 0, -1) },
	W = { axis = "Z", plane = -108.95, n = V3(1, 0, 0) },
	E = { axis = "Z", plane = 108.95, n = V3(-1, 0, 0) },
}
local function onWall(parent, name, wall, along, y, w, h, color, material, opts, out)
	local d = WALL[wall]
	local pos = d.axis == "X" and V3(along, y, d.plane) or V3(d.plane, y, along)
	pos += d.n * (out or 0)
	local cf = CFrame.lookAt(pos, pos + d.n)
	return part(parent, name, V3(w, h, (opts and opts.depth) or 0.04), cf, color, material, opts), cf
end

-- the round timer prop (same structure Ambience animates for the server's timers)
local function roundTimer(parent, cf, width)
	local m = newModel(parent, "RoundTimer")
	local h = width * 0.36
	local box = part(m, "TimerBox", V3(width, h, 0.9), cf, BLACK, M.SmoothPlastic)
	local sg = gui(box, Enum.NormalId.Front, 30, 0)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 8, 10) })
	label(sg, "ROUND 1", { Name = "Phase", TextColor3 = GOLD, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.5, 0.26), Position = UDim2.fromScale(0.25, 0.04) })
	label(sg, "3:00", { Name = "Time", TextColor3 = rgb(255, 60, 50), Font = Enum.Font.Code, Size = UDim2.fromScale(0.86, 0.66), Position = UDim2.fromScale(0.07, 0.3) })
	for i, colr in ipairs({ rgb(40, 220, 80), rgb(250, 200, 40), rgb(240, 50, 40) }) do
		local lamp = part(m, ({ "LampGo", "LampWarn", "LampRest" })[i], V3(0.8, 0.8, 0.8), cf * CF((i - 2) * 1.1, h / 2 + 0.45, 0), colr, M.Neon, { shape = Enum.PartType.Ball, shadow = false })
		lamp.Transparency = 0.6
	end
	m.PrimaryPart = box
	CollectionService:AddTag(m, "RoundTimer")
	return m
end

local function sponsorBanner(parent, cf, sp)
	local logo = sp and sp.logo or {}
	local bg, fg = c3(logo.bg, BLACK), c3(logo.fg, GOLD)
	local p = part(parent, "SponsorBanner", V3(5, 9, 0.1), cf, bg, M.Fabric, { shadow = false })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = gui(p, face, 30, 0.6)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
		frame(sg, { Size = UDim2.new(1, 0, 0.04, 0), Position = UDim2.fromScale(0, 0.06), BackgroundColor3 = fg })
		frame(sg, { Size = UDim2.new(1, 0, 0.04, 0), Position = UDim2.fromScale(0, 0.9), BackgroundColor3 = fg })
		label(sg, logo.glyph or "WCB", { TextColor3 = fg, Size = UDim2.fromScale(0.8, 0.3), Position = UDim2.fromScale(0.1, 0.16) })
		label(sg, logo.text or (sp and sp.name) or "WORLD CLASS BOXING", { TextColor3 = fg, Size = UDim2.fromScale(0.86, 0.22), Position = UDim2.fromScale(0.07, 0.5) })
		label(sg, "OFFICIAL PARTNER", { TextColor3 = fg, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.8, 0.07), Position = UDim2.fromScale(0.1, 0.78) })
	end
	cyl(parent, "BannerPole", 5.4, 0.16, cf * CF(0, 4.6, 0), STEEL, M.Metal)
	part(parent, "BannerWeight", V3(5.1, 0.18, 0.18), cf * CF(0, -4.55, 0), fg, M.Metal)
	for _, x in ipairs({ -2.4, 2.4 }) do
		local top = (cf * CF(x, 4.6, 0)).Position
		part(parent, "BannerCord", V3(0.05, 29.6 - top.Y, 0.05), CF(top.X, (29.6 + top.Y) / 2, top.Z), BLACK, M.Fabric, { shadow = false })
	end
	return p
end

local function buildDressing(m, idx, P)
	local rng = Random.new(77)
	if idx <= 1 then
		-- water stains streaking down from the windows, grimy patches and cracked plaster
		local stain = rgb(78, 58, 40)
		for _, e in ipairs({ { "N", -100 }, { "N", -75 }, { "N", 45 }, { "N", 75 }, { "N", 100 }, { "S", 45 }, { "S", 75 }, { "S", -75 }, { "W", -66 }, { "W", 22 }, { "E", -66 }, { "E", -3 } }) do
			local w, h = rng:NextNumber(3, 6), rng:NextNumber(4, 8)
			onWall(m, "WaterStain", e[1], e[2] + rng:NextNumber(-2, 2), 17 - h / 2 + 0.6, w, h, stain, M.SmoothPlastic, { ellipsoid = true, transparency = 0.62, shadow = false })
			onWall(m, "WaterStreak", e[1], e[2] + rng:NextNumber(-1.5, 1.5), 17 - h - 1.2, 0.5, 3, stain, M.SmoothPlastic, { ellipsoid = true, transparency = 0.7, shadow = false })
		end
		for _, e in ipairs({ { "S", 16, 4.2 }, { "S", -16, 6 }, { "W", -40, 9 }, { "E", 30, 11 } }) do
			onWall(m, "PlasterPatch", e[1], e[2], e[3], rng:NextNumber(1.6, 3), rng:NextNumber(1, 2), rgb(150, 140, 128), M.Concrete, { transparency = 0.15, shadow = false })
		end
		for _ = 1, 12 do
			local x, z = rng:NextNumber(-44, 44), rng:NextNumber(-68, 2)
			if math.abs(x) > 14 or math.abs(z + 50) > 14 then -- not under the ring
				part(m, "Grime", V3(rng:NextNumber(1.5, 4), 0.02, rng:NextNumber(1, 3)), CF(x, 0.515, z) * ANG(0, rng:NextNumber(0, 3), 0), rgb(26, 24, 22), M.SmoothPlastic, { ellipsoid = true, transparency = 0.6, shadow = false })
			end
		end
		for _ = 1, 6 do
			part(m, "Grime", V3(rng:NextNumber(2, 4), 0.02, rng:NextNumber(1, 2.5)), CF(rng:NextNumber(-104, -54), 0.515, rng:NextNumber(-74, 14)) * ANG(0, rng:NextNumber(0, 3), 0), rgb(18, 16, 14), M.SmoothPlastic, { ellipsoid = true, transparency = 0.55, shadow = false })
		end
		-- roof leaks: buckets catching drips (drip particles fall from just under the roof)
		for i, pos in ipairs({ V3(38, 0.5, -58), V3(-58, 0.5, -14) }) do
			local b = CF(pos)
			vcyl(m, "DripBucket", 1.2, 1.1, b, i == 1 and rgb(220, 110, 30) or rgb(60, 90, 160), M.SmoothPlastic)
			vcyl(m, "BucketWater", 0.05, 0.95, b * CF(0, 0.7, 0), rgb(110, 140, 160), M.Glass, { transparency = 0.25, reflect = 0.2 })
			local src = part(m, "LeakDrip", V3(0.3, 0.3, 0.3), CF(pos.X, 28.4, pos.Z), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
			src:SetAttribute("Drip", true)
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(rgb(170, 200, 225))
			pe.Size = NumberSequence.new(0.09)
			pe.Transparency = NumberSequence.new(0.25)
			pe.Lifetime = NumberRange.new(0.62, 0.66)
			pe.Rate = 1.3
			pe.Speed = NumberRange.new(2)
			pe.Acceleration = V3(0, -120, 0)
			pe.EmissionDirection = Enum.NormalId.Bottom
			pe.SpreadAngle = Vector2.zero
			pe.LightInfluence = 1
			pe.Parent = src
			part(m, "LeakStain", V3(3, 0.05, 3), CF(pos.X, 28.0, pos.Z), stain, M.SmoothPlastic, { ellipsoid = true, transparency = 0.5, shadow = false })
			if i == 1 then
				-- a yellow wet-floor A-frame
				local a = CF(pos + V3(2.2, 0, 0.6)) * ANG(0, RAD(25), 0)
				for _, s in ipairs({ -1, 1 }) do
					local panel = part(m, "WetFloorSign", V3(1.3, 2.4, 0.08), a * CF(0, 1.15, s * 0.32) * ANG(RAD(s * 14), 0, 0), rgb(250, 210, 30), M.SmoothPlastic)
					sign(panel, s < 0 and Enum.NormalId.Front or Enum.NormalId.Back, "CAUTION\nWET FLOOR", BLACK, nil, 40)
				end
			end
		end
		-- hand-written cardboard signs taped to the walls
		local c1 = onWall(m, "Cardboard", "N", 10, 5.6, 3.6, 2.2, rgb(180, 150, 110), M.Fabric, { depth = 0.06 }, 0.05)
		sign(c1, Enum.NormalId.Front, "DUES: $20 / MONTH\nPAY OLD PETE", rgb(40, 30, 25), nil, 40, Enum.Font.Cartoon)
		local c2 = onWall(m, "Cardboard", "W", -30, 5.2, 3, 1.8, rgb(185, 155, 112), M.Fabric, { depth = 0.06 }, 0.05)
		sign(c2, Enum.NormalId.Front, "RE-RACK YOUR\nWEIGHTS!!", rgb(160, 20, 20), nil, 40, Enum.Font.Cartoon)
		for _, cdata in ipairs({ { c1, 1.6 }, { c2, 1.3 } }) do
			local cp, half = cdata[1], cdata[2]
			for _, s in ipairs({ -1, 1 }) do
				part(m, "Tape", V3(0.7, 0.22, 0.02), cp.CFrame * CF(s * half, cp.Size.Y / 2 - 0.1, -0.04) * ANG(0, 0, RAD(s * 30)), TAPE, M.Foil, { shadow = false })
			end
		end
		-- the old fight posters on the dividers: torn corners and tape
		local decor = gym() and gym():FindFirstChild("Decor")
		local boxing = decor and decor:FindFirstChild("Boxing")
		local n = 0
		if boxing then
			for _, p in ipairs(boxing:GetChildren()) do
				if p.Name == "Poster" and p:IsA("BasePart") and n < 8 then
					n += 1
					local face = p.Position.X < 0 and 1 or -1 -- DWb faces +X, DEb faces -X
					local front = p.CFrame * CF(face * (p.Size.X / 2 + 0.03), 0, 0)
					local half = p.Size.Z / 2
					part(m, "PosterTape", V3(0.02, 0.24, 0.8), front * CF(0, p.Size.Y / 2 - 0.15, -half + 0.3) * ANG(RAD(35), 0, 0), TAPE, M.Foil, { shadow = false })
					if n % 2 == 0 then
						-- a peeled corner curling off the wall
						part(m, "PosterCurl", V3(0.03, 0.9, 0.9), front * CF(face * 0.18, -p.Size.Y / 2 + 0.35, half - 0.35) * ANG(0, 0, RAD(face * 28)), rgb(225, 220, 205), M.SmoothPlastic, { wedge = true, shadow = false })
					end
				end
			end
		end
		return
	end
	-- Intermediate and up: sponsor banners, LED strips, a round timer in the weight room
	local sponsors = Catalog.Sponsors or {}
	local pool = {}
	for _, sp in ipairs(sponsors) do
		if (idx >= 3) or sp.scope == "Local" then
			table.insert(pool, sp)
		end
	end
	local spots = { CF(-15, 23.5, -20), CF(15, 23.5, -20), CF(-80, 23.5, -20), CF(80, 23.5, -20) }
	for i, cf in ipairs(spots) do
		local sp = pool[(i + idx) % math.max(1, #pool) + 1]
		sponsorBanner(m, cf, sp)
	end
	local ledColor = ({ nil, rgb(255, 236, 200), rgb(150, 210, 255), GOLD })[idx] or rgb(255, 236, 200)
	for _, seg in ipairs({ { -44, -8 }, { 8, 44 } }) do
		local mid, len = (seg[1] + seg[2]) / 2, seg[2] - seg[1]
		onWall(m, "LEDStrip", "N", mid, 4.98, len, 0.12, ledColor, M.Neon, { shadow = false, depth = 0.1 }, 0.17)
	end
	-- (the west strip stops short of the weight-room mirror)
	onWall(m, "LEDStrip", "W", -12.5, 4.98, 55, 0.12, ledColor, M.Neon, { shadow = false, depth = 0.1 }, 0.17)
	onWall(m, "LEDStrip", "E", -30, 4.98, 90, 0.12, ledColor, M.Neon, { shadow = false, depth = 0.1 }, 0.17)
	roundTimer(m, CF(-108.3, 12, -30) * ANG(0, RAD(-90), 0), 7)
	if idx >= 3 then
		-- cool LED on top of the dividers, analytics screens fed by your training records
		for _, d in ipairs({ { V3(0.25, 0.08, 60), CF(-50, 9.45, -48) }, { V3(40, 0.08, 0.25), CF(-88, 9.45, 20) }, { V3(40, 0.08, 0.25), CF(88, 9.45, 20) } }) do
			part(m, "DividerLED", d[1], d[2], rgb(140, 205, 255), M.Neon, { shadow = false })
		end
		GymFacility.AnalyticsScreen(m, (onWall(m, "AnalyticsScreen", "N", 30, 14.8, 12, 4, DARK, M.SmoothPlastic, { depth = 0.2 }, 0.12)), Enum.NormalId.Front, P, "PERFORMANCE ANALYTICS")
		local wscr = part(m, "AnalyticsScreen", V3(0.2, 3.6, 6), CF(-51.25, 6, -42), DARK, M.SmoothPlastic)
		GymFacility.AnalyticsScreen(m, wscr, Enum.NormalId.Left, P, "STRENGTH LAB", { "Bench", "Dumbbells", "Barbell", "Squat", "PullUps", "MedBall" })
	end
	if idx >= 4 then
		-- gold trim along the red wall stripe, all the way round the hall
		for _, e in ipairs({ { "N", -58.5, 101 }, { "N", 58.5, 101 }, { "S", -59.5, 99 }, { "S", 59.5, 99 }, { "W", 0, 158 }, { "E", -17.75, 122.5 }, { "E", 67.75, 22.5 } }) do
			onWall(m, "GoldTrim", e[1], e[2], 4.3, e[3], 0.16, GOLD, M.Metal, { shadow = false, depth = 0.08, reflect = 0.15 }, 0.17)
		end
	end
end

------------------------------------------------------------------------
-- analytics screen (Elite+): your best session quality per drill as animated bars
------------------------------------------------------------------------
local DRILLS = { "HeavyBag", "SpeedBag", "DoubleEnd", "MittWork", "Shadow", "Bench", "Squat", "Treadmill" }
function GymFacility.AnalyticsScreen(_m, screen, face, P, title, list)
	if not screen then
		return
	end
	local sg = gui(screen, face, 30, 0)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 12, 20) })
	label(sg, title or "ANALYTICS", { TextColor3 = rgb(120, 210, 255), Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.03) })
	local recs = type(P) == "table" and type(P.records) == "table" and P.records or {}
	local ids = list or DRILLS
	local n = #ids
	for i, id in ipairs(ids) do
		local r = recs[id]
		local best = type(r) == "table" and tonumber(r.best) or 0
		local pct = math.clamp(Config.QualityPct and Config.QualityPct(best) or best * 70, 0, 100)
		local act = Config.FindById and Config.FindById(Config.Activities, id)
		local y = 0.2 + (i - 1) * (0.76 / n)
		label(sg, (act and act.name or id):upper(), { TextColor3 = rgb(200, 210, 225), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.3, 0.6 / n), Position = UDim2.fromScale(0.04, y) })
		local track = frame(sg, { Size = UDim2.fromScale(0.5, 0.45 / n), Position = UDim2.fromScale(0.36, y + 0.08 / n), BackgroundColor3 = rgb(30, 40, 56) })
		local fill = frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = pct >= 85 and GOLD or rgb(80, 200, 255) })
		TweenService:Create(fill, TweenInfo.new(1.2 + i * 0.12, Enum.EasingStyle.Quart), { Size = UDim2.fromScale(pct / 100, 1) }):Play()
		label(sg, best > 0 and (math.floor(pct) .. "%") or "--", { TextColor3 = WHITE, Font = Enum.Font.Code, Size = UDim2.fromScale(0.1, 0.55 / n), Position = UDim2.fromScale(0.88, y) })
	end
	point(screen, rgb(90, 170, 255), 9, 0.4)
end

------------------------------------------------------------------------
-- 3. Elite Performance Wing (interior is local; MapBuilder built the shell)
------------------------------------------------------------------------
local gateState -- "open" | "locked"
local function setGate(open)
	local g = gym()
	local wing = g and g:FindFirstChild("EliteWing")
	if not wing then
		return
	end
	local state = open and "open" or "locked"
	if gateState == state then
		return
	end
	gateState = state
	for _, p in ipairs(wing:GetChildren()) do
		if p.Name == "EliteGate" and p:IsA("BasePart") then
			local home = p:GetAttribute("HomeCF")
			if typeof(home) ~= "CFrame" then
				home = p.CFrame
				p:SetAttribute("HomeCF", home)
			end
			local s = p:GetAttribute("Side") or 1
			local target = open and home * CF(0, 0, s * (p.Size.Z * 0.92)) or home
			-- local only: the doors slide open for you, other players see their own state
			p.CanCollide = not open
			TweenService:Create(p, TweenInfo.new(open and 1.4 or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = target, Transparency = open and 0.7 or 0.45 }):Play()
		elseif p:IsA("BasePart") and p.Name == "EliteLightPanel" then
			p.Material = open and M.Neon or M.SmoothPlastic
			for _, l in ipairs(p:GetChildren()) do
				if l:IsA("Light") then
					l.Enabled = open
				end
			end
		end
	end
end

local function glassWall(m, a, b, h, champ)
	-- frosted band, posts and a glass pane between two floor points
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid + V3(0, h / 2 + 0.5, 0), mid + V3(0, h / 2 + 0.5, 0) + (b - a).Unit:Cross(Vector3.yAxis))
	part(m, "GlassPartition", V3(len, h, 0.12), cf, rgb(200, 225, 240), M.Glass, { transparency = 0.72, collide = true, shadow = false })
	part(m, "FrostBand", V3(len, 1.2, 0.14), cf * CF(0, -h / 2 + 3.4, 0), rgb(235, 240, 245), M.SmoothPlastic, { transparency = 0.35, shadow = false })
	part(m, "PartitionTop", V3(len, 0.18, 0.22), cf * CF(0, h / 2, 0), champ and GOLD or CHROME, M.Metal)
	part(m, "PartitionBase", V3(len, 0.25, 0.25), cf * CF(0, -h / 2 + 0.12, 0), champ and GOLD or CHROME, M.Metal)
	for _, x in ipairs({ -len / 2, len / 2 }) do
		part(m, "PartitionPost", V3(0.22, h, 0.25), cf * CF(x, 0, 0), champ and GOLD or CHROME, M.Metal)
	end
	part(m, "PartitionGlow", V3(len, 0.06, 0.3), CF(mid + V3(0, 0.53, 0)) * (cf - cf.Position), rgb(170, 220, 255), M.Neon, { shadow = false })
end

local function plungePool(m, x0, z0, w, d, hot)
	local wallC = rgb(232, 236, 240)
	local hgt = 3
	local base = V3(x0, 0.5, z0)
	for _, e in ipairs({ { 0, -d / 2, w + 0.6, 0.5 }, { 0, d / 2, w + 0.6, 0.5 }, { -w / 2, 0, 0.5, d }, { w / 2, 0, 0.5, d } }) do
		part(m, "PoolWall", V3(e[3], hgt, e[4]), CF(base + V3(e[1], hgt / 2, e[2])), wallC, M.Marble, { collide = true })
	end
	part(m, "PoolRim", V3(w + 1, 0.2, d + 1), CF(base + V3(0, hgt + 0.1, 0)), hot and rgb(200, 190, 175) or rgb(205, 215, 225), M.Slate)
	-- the rim is a frame: punch the water through with a darker inner floor and the water surface
	part(m, "PoolFloor", V3(w - 0.4, 0.1, d - 0.4), CF(base + V3(0, 0.06, 0)), hot and rgb(40, 120, 125) or rgb(30, 100, 160), M.SmoothPlastic)
	local water = part(m, "PoolWater", V3(w - 0.5, 0.1, d - 0.5), CF(base + V3(0, hgt - 0.35, 0)), hot and rgb(110, 205, 200) or rgb(120, 190, 240), M.Glass, { transparency = 0.38, reflect = 0.18, shadow = false })
	point(part(m, "PoolLight", V3(0.3, 0.3, 0.3), CF(base + V3(0, 0.6, 0)), Color3.new(), M.SmoothPlastic, { transparency = 1 }), hot and rgb(255, 170, 90) or rgb(80, 170, 255), 12, 1.2)
	-- steps and a chrome handrail on the near (corridor) side
	for k = 1, 2 do
		part(m, "PoolStep", V3(2.6, 0.9 * k, 1.1), CF(base + V3(-w / 2 + 1.8, 0.45 * k, -d / 2 - 1.1 * (2 - k) - 0.85)), wallC, M.Marble, { collide = true })
	end
	rod(m, "Handrail", base + V3(-w / 2 + 0.6, 0, -d / 2 - 2.6), base + V3(-w / 2 + 0.6, hgt + 1.6, -d / 2 + 0.2), 0.14, CHROME, M.Metal)
	local stand = part(m, "PoolSign", V3(2.6, 1.2, 0.12), CF(base + V3(w / 2 - 1.4, hgt + 1.4, -d / 2 - 0.4)), DARK, M.SmoothPlastic)
	sign(stand, Enum.NormalId.Front, hot and "HOT PLUNGE  39°C" or "COLD PLUNGE  4°C", hot and rgb(255, 170, 90) or ICE, DARK, 40)
	part(m, "SignPost", V3(0.12, hgt + 0.8, 0.12), CF(base + V3(w / 2 - 1.4, (hgt + 0.8) / 2, -d / 2 - 0.4)), CHROME, M.Metal)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(hot and rgb(240, 240, 240) or rgb(220, 240, 255))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, hot and 0.75 or 0.85), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	mist.Lifetime = NumberRange.new(3, 5)
	mist.Rate = hot and 5 or 2
	mist.Speed = NumberRange.new(0.3, 0.8)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Acceleration = V3(0, hot and 0.6 or -0.2, 0)
	mist.LightInfluence = 1
	mist.Parent = water
	return water
end

local function cryoCabin(m, pos, champ)
	local b = CF(pos)
	vcyl(m, "CryoBase", 0.45, 5.2, b, DARK, M.Metal, { collide = true })
	vcyl(m, "CryoFloorGlow", 0.06, 4.4, b * CF(0, 0.45, 0), ICE, M.Neon, { transparency = 0.3, shadow = false })
	vcyl(m, "CryoGlass", 7, 4.2, b * CF(0, 0.45, 0), rgb(200, 230, 250), M.Glass, { transparency = 0.6, collide = true, shadow = false })
	vcyl(m, "CryoCap", 0.6, 4.6, b * CF(0, 7.45, 0), champ and GOLD or WHITE, M.SmoothPlastic)
	for _, y in ipairs({ 0.9, 7.2 }) do
		vcyl(m, "CryoRing", 0.12, 4.35, b * CF(0, y, 0), rgb(90, 190, 255), M.Neon, { shadow = false })
	end
	-- frosted door panel facing the room (-Z) and the nitrogen fog inside
	part(m, "CryoDoor", V3(1.8, 6.4, 0.14), b * CF(0, 3.8, -2.12), rgb(235, 245, 252), M.SmoothPlastic, { transparency = 0.25, shadow = false })
	part(m, "CryoHandle", V3(0.1, 1.4, 0.12), b * CF(0.65, 3.8, -2.24), CHROME, M.Metal)
	local fogSrc = part(m, "CryoFog", V3(3, 0.2, 3), b * CF(0, 1.2, 0), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	local fog = Instance.new("ParticleEmitter")
	fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fog.Color = ColorSequence.new(rgb(220, 240, 255))
	fog.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(1, 1) })
	fog.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.6) })
	fog.Lifetime = NumberRange.new(3, 5)
	fog.Rate = 16
	fog.Speed = NumberRange.new(0.4, 1)
	fog.SpreadAngle = Vector2.new(180, 30)
	fog.Acceleration = V3(0, -1.2, 0)
	fog.LightEmission = 0.3
	fog.Parent = fogSrc
	point(fogSrc, rgb(90, 190, 255), 13, 1.4)
	-- control console
	local c = b * CF(-3.4, 0, -2.6) * ANG(0, RAD(30), 0)
	part(m, "CryoConsolePost", V3(0.3, 3.4, 0.3), c * CF(0, 1.7, 0), WHITE, M.Metal)
	local scr = part(m, "CryoConsole", V3(1.6, 1.0, 0.12), c * CF(0, 3.6, 0) * ANG(RAD(-15), 0, 0), DARK, M.SmoothPlastic)
	sign(scr, Enum.NormalId.Front, "CRYO  -110°C\nSESSION 3:00", ICE, DARK, 50)
	local plate = part(m, "CryoPlate", V3(3, 0.7, 0.1), b * CF(0, 8.2, -2.0), DARK, M.SmoothPlastic)
	sign(plate, Enum.NormalId.Front, "CRYOTHERAPY", ICE, DARK, 40)
end

local function camRig(m, pos, aim)
	local cf = CFrame.lookAt(pos, aim)
	part(m, "MocapCam", V3(0.55, 0.45, 0.8), cf, DARK, M.SmoothPlastic)
	cyl(m, "MocapLens", 0.1, 0.36, cf * CF(0, 0, -0.42) * ANG(0, RAD(90), 0), rgb(40, 40, 50), M.Glass)
	cyl(m, "MocapRing", 0.05, 0.46, cf * CF(0, 0, -0.45) * ANG(0, RAD(90), 0), rgb(255, 40, 40), M.Neon, { shadow = false })
	part(m, "MocapTally", V3(0.1, 0.1, 0.1), cf * CF(0.18, 0.25, -0.3), rgb(255, 30, 30), M.Neon, { shadow = false })
	return cf
end

local function buildWing(m, idx, P, frac, needs)
	local W = { x1 = 111, x2 = 153, z1 = 30, z2 = 66 }
	if idx < 3 then
		-- LOCKED: caution tape over the doorway, a progress sign, construction inside
		for _, a in ipairs({ 18, -18 }) do
			local tape = part(m, "CautionTape", V3(0.04, 0.5, 13), CF(108.85, 7, 50) * ANG(RAD(a), 0, 0), rgb(250, 210, 30), M.SmoothPlastic, { shadow = false })
			local sg = gui(tape, Enum.NormalId.Left, 40, 0.5)
			label(sg, "DO NOT ENTER  -  DO NOT ENTER  -  DO NOT ENTER", { TextColor3 = BLACK, Font = Enum.Font.GothamBold })
		end
		local easel = CF(105.5, 0.5, 42.2) * ANG(0, RAD(105), 0) -- faces the people walking over from the recovery area
		local board = part(m, "WingSign", V3(4.2, 3.2, 0.15), easel * CF(0, 3.6, 0) * ANG(RAD(-8), 0, 0), DARK, M.SmoothPlastic)
		local need = needs and needs[1]
		sign(board, Enum.NormalId.Front, string.format("ELITE PERFORMANCE WING\nCOMING SOON\nUnlocks at the ELITE tier\nFacility %d%%%s", math.floor((frac or 0) * 100), need and ("\n" .. need) or ""), rgb(150, 220, 255), DARK, 40)
		for _, x in ipairs({ -1.6, 1.6 }) do
			part(m, "EaselLeg", V3(0.14, 5.4, 0.14), easel * CF(x, 2.6, 0.2) * ANG(RAD(-8), 0, 0), rgb(120, 90, 60), M.Wood)
		end
		-- inside: plastic sheet behind the doors, dust sheets, sawhorses, paint, a ladder
		part(m, "PlasticSheet", V3(0.05, 13.5, 12), CF(112.6, 7.2, 50), rgb(235, 240, 245), M.SmoothPlastic, { transparency = 0.45, shadow = false })
		local rng = Random.new(31)
		for i = 1, 5 do
			local x, z = rng:NextNumber(118, 148), rng:NextNumber(34, 62)
			local s = V3(rng:NextNumber(2.5, 5), rng:NextNumber(1.6, 3.4), rng:NextNumber(2.5, 5))
			part(m, "DustSheet", s, CF(x, 0.5 + s.Y / 2, z) * ANG(0, rng:NextNumber(0, 3), 0), rgb(225, 222, 214), M.Fabric, { collide = true })
			if i <= 2 then
				local sh = CF(x + 4, 0.5, z) * ANG(0, rng:NextNumber(0, 3), 0)
				part(m, "SawhorseBeam", V3(3.2, 0.3, 0.3), sh * CF(0, 2.2, 0), rgb(200, 160, 100), M.Wood)
				for _, sx in ipairs({ -1.3, 1.3 }) do
					for _, sz in ipairs({ -1, 1 }) do
						part(m, "SawhorseLeg", V3(0.15, 2.3, 0.15), sh * CF(sx, 1.1, sz * 0.3) * ANG(RAD(sz * 12), 0, 0), rgb(200, 160, 100), M.Wood)
					end
				end
			end
		end
		for k = 0, 2 do
			vcyl(m, "PaintBucket", 0.9, 0.8, CF(116 + k * 0.9, 0.5, 33), k == 1 and rgb(60, 120, 200) or WHITE, M.SmoothPlastic)
		end
		local lad = CF(150, 0.5, 63) * ANG(0, RAD(30), 0)
		for _, x in ipairs({ -0.7, 0.7 }) do
			part(m, "LadderRail", V3(0.14, 9, 0.14), lad * CF(x, 4.4, 0) * ANG(RAD(-12), 0, 0), rgb(200, 200, 205), M.Metal)
		end
		for k = 1, 7 do
			part(m, "LadderRung", V3(1.4, 0.1, 0.12), lad * CF(0, k * 1.1, -k * 0.23), rgb(200, 200, 205), M.Metal)
		end
		part(m, "FloorPaper", V3(30, 0.03, 24), CF(132, 0.52, 48), rgb(200, 185, 160), M.Fabric, { shadow = false })
		return
	end
	-- OPEN: the Elite Performance Wing
	local champ = idx >= 4
	local accent = champ and GOLD or rgb(140, 205, 255)
	-- entry: floor crest, wall lettering
	local crest = part(m, "WingCrest", V3(7, 0.02, 7), CF(122, 0.52, 48), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local csg = gui(crest, Enum.NormalId.Top, 20, 1)
	local ring = frame(csg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent, BackgroundTransparency = 0.1 })
	Instance.new("UICorner", ring).CornerRadius = UDim.new(0.5, 0)
	local inner = frame(csg, { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), BackgroundColor3 = rgb(20, 24, 32) })
	Instance.new("UICorner", inner).CornerRadius = UDim.new(0.5, 0)
	label(csg, champ and "CHAMPION'S\nWING" or "WCB\nELITE", { TextColor3 = accent, Size = UDim2.fromScale(0.62, 0.42), Position = UDim2.fromScale(0.19, 0.29) })
	local lettering = part(m, "WingLettering", V3(0.1, 2, 14), CF(152.05 - 0.2, 14, 48), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local lsg = gui(lettering, Enum.NormalId.Left, 30, 0)
	label(lsg, champ and "CHAMPION'S WING" or "ELITE PERFORMANCE", { TextColor3 = accent })
	-- glass partitions with doorways: lab / mocap to the north, recovery to the south
	for _, z in ipairs({ 42.5, 53.5 }) do
		glassWall(m, V3(118, 0, z), V3(130, 0, z), 9, champ)
		glassWall(m, V3(134, 0, z), V3(152, 0, z), 9, champ)
	end
	-- NORTH: sports science lab + motion capture
	-- lab desk with three monitors along the north wall
	part(m, "LabDesk", V3(8, 0.25, 2), CF(123, 3.4, 32.4), WHITE, M.SmoothPlastic, { collide = true })
	for _, x in ipairs({ 119.4, 126.6 }) do
		part(m, "LabDeskLeg", V3(0.25, 2.9, 1.8), CF(x, 1.95, 32.4), CHROME, M.Metal)
	end
	local charts = { "POWER CURVE\n▁▂▄▆█▆▄", "HEART RATE\n142 bpm  Z4", "REACTION\n0.21 s  ▲" }
	for i, x in ipairs({ 120.4, 123, 125.6 }) do
		local mon = part(m, "LabMonitor", V3(2.2, 1.4, 0.12), CF(x, 4.55, 32.0) * ANG(RAD(-6), 0, 0), DARK, M.SmoothPlastic)
		sign(mon, Enum.NormalId.Back, charts[i], rgb(110, 220, 255), rgb(8, 12, 20), 50, Enum.Font.Code)
	end
	-- force plates with glowing edges
	for _, x in ipairs({ 122, 126.5 }) do
		part(m, "ForcePlateGlow", V3(2.7, 0.08, 2.7), CF(x, 0.54, 37.5), accent, M.Neon, { shadow = false })
		part(m, "ForcePlate", V3(2.4, 0.16, 2.4), CF(x, 0.6, 37.5), rgb(60, 62, 70), M.DiamondPlate, { collide = true })
	end
	local fpSign = part(m, "ForcePlateSign", V3(4.6, 0.8, 0.1), CF(124.3, 1.4, 39.2), DARK, M.SmoothPlastic)
	sign(fpSign, Enum.NormalId.Back, "FORCE PLATES  -  JUMP & PUNCH LOAD", accent, DARK, 40)
	-- body scanner: a ring of light bars that orbits the athlete (Ambience spins SpinFan models)
	local scan = CF(131.5, 0.5, 36.5)
	vcyl(m, "ScanBase", 0.35, 4.4, scan, WHITE, M.SmoothPlastic, { collide = true })
	vcyl(m, "ScanTop", 0.5, 4.6, scan * CF(0, 7.6, 0), WHITE, M.SmoothPlastic)
	vcyl(m, "ScanTopGlow", 0.1, 4.0, scan * CF(0, 7.55, 0), accent, M.Neon, { shadow = false })
	for _, a in ipairs({ 45, 225 }) do
		part(m, "ScanPillar", V3(0.3, 7.3, 0.3), scan * ANG(0, RAD(a), 0) * CF(0, 3.9, 2.15), WHITE, M.SmoothPlastic)
	end
	local fanM = newModel(m, "BodyScanner")
	local hubCF = scan * CF(0, 4, 0) * ANG(0, 0, RAD(90)) -- hub's local X points up: spins about vertical
	local hub = part(fanM, "Hub", V3(0.2, 0.2, 0.2), hubCF, Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	for _, a in ipairs({ 0, 180 }) do
		local pos = (scan * ANG(0, RAD(a), 0) * CF(0, 4, 1.7)).Position
		part(fanM, "Blade", V3(0.16, 6.4, 0.16), CF(pos), accent, M.Neon, { shadow = false })
	end
	fanM.PrimaryPart = hub
	fanM:SetAttribute("Speed", 1.6)
	CollectionService:AddTag(fanM, "SpinFan")
	-- motion-capture stage: a grid floor, a tracking-camera rail, a dotted mannequin
	local stage = part(m, "MocapFloor", V3(14, 0.04, 9.5), CF(143.5, 0.52, 36.8), rgb(16, 22, 36), M.SmoothPlastic, { shadow = false })
	local msg = gui(stage, Enum.NormalId.Top, 10, 1)
	for k = 0, 14 do
		frame(msg, { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(k / 14, 0), BackgroundColor3 = rgb(60, 160, 220) })
	end
	for k = 0, 9 do
		frame(msg, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, k / 9), BackgroundColor3 = rgb(60, 160, 220) })
	end
	local aim = V3(143.5, 3, 36.8)
	part(m, "CamRail", V3(14.5, 0.2, 0.2), CF(143.5, 13, 31.4), DARK, M.Metal)
	part(m, "CamRail", V3(0.2, 0.2, 10), CF(151.6, 13, 36.5), DARK, M.Metal)
	local cams = {}
	for _, x in ipairs({ 137.5, 141.5, 145.5, 149.5 }) do
		table.insert(cams, camRig(m, V3(x, 12.4, 31.8), aim))
	end
	for _, z in ipairs({ 33.5, 37, 40.5 }) do
		table.insert(cams, camRig(m, V3(151.2, 12.4, z), aim))
	end
	for i = 1, 2 do
		local src = part(m, "MocapSpot", V3(0.2, 0.2, 0.2), cams[i * 3 - 1] * CF(0, 0, -0.5), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
		spot(src, Enum.NormalId.Front, rgb(255, 60, 60), 18, 0.3, 40)
	end
	-- the mocap suit on a stand: black suit, white marker dots
	local mq = CF(143.5, 0.5, 37)
	local suit = rgb(20, 20, 24)
	part(m, "MocapStand", V3(0.2, 1.4, 0.2), mq * CF(0, 0.7, 0), CHROME, M.Metal)
	part(m, "MocapTorso", V3(1.6, 2.2, 0.8), mq * CF(0, 4.5, 0), suit, M.Fabric)
	part(m, "MocapHips", V3(1.5, 0.8, 0.8), mq * CF(0, 3.1, 0), suit, M.Fabric)
	part(m, "MocapHead", V3(0.9, 1.0, 0.9), mq * CF(0, 6.2, 0), suit, M.Fabric, { ellipsoid = true })
	for _, s in ipairs({ -1, 1 }) do
		part(m, "MocapArm", V3(0.45, 2.4, 0.45), mq * CF(s * 1.15, 4.4, -0.2) * ANG(RAD(-25), 0, RAD(s * 12)), suit, M.Fabric)
		part(m, "MocapLeg", V3(0.55, 2.8, 0.55), mq * CF(s * 0.45, 1.5, 0), suit, M.Fabric)
	end
	for _, d in ipairs({ { 0, 6.7, 0 }, { -0.7, 5.4, -0.42 }, { 0.7, 5.4, -0.42 }, { 0, 4.4, -0.42 }, { -1.5, 3.4, -0.7 }, { 1.5, 3.4, -0.7 }, { -0.45, 3.0, -0.42 }, { 0.45, 3.0, -0.42 }, { -0.45, 1.5, -0.3 }, { 0.45, 1.5, -0.3 } }) do
		part(m, "MocapDot", V3(0.18, 0.18, 0.18), mq * CF(d[1], d[2], d[3]), WHITE, M.Neon, { shape = Enum.PartType.Ball, shadow = false })
	end
	-- MIDDLE: analytics wall, compression-boot recliners, a bench and plants
	local wall = part(m, "AnalyticsWall", V3(0.2, 5, 9), CF(151.75, 6.5, 48), DARK, M.SmoothPlastic)
	GymFacility.AnalyticsScreen(m, wall, Enum.NormalId.Left, P, "ATHLETE DASHBOARD")
	for i, z in ipairs({ 45.6, 50.4 }) do
		local base = CF(142, 0.5, z) * ANG(0, RAD(-90), 0)
		part(m, "ReclinerBase", V3(2.2, 1.2, 4.4), base * CF(0, 0.6, 0), DARK, M.Leather, { collide = true })
		part(m, "ReclinerBack", V3(2.2, 2.6, 0.6), base * CF(0, 2, -2.1) * ANG(RAD(-25), 0, 0), DARK, M.Leather)
		for _, s in ipairs({ -0.5, 0.5 }) do
			part(m, "CompressionBoot", V3(0.7, 0.7, 2.6), base * CF(s, 1.55, 1.2), i == 1 and rgb(40, 40, 46) or rgb(30, 30, 36), M.Rubber)
			cyl(m, "BootHose", 1.6, 0.12, base * CF(s, 1.2, -0.4) * ANG(0, RAD(90), 0), rgb(200, 200, 205), M.SmoothPlastic)
		end
		local unit = part(m, "BootUnit", V3(1, 1.3, 0.8), base * CF(1.8, 0.65, -1.2), WHITE, M.SmoothPlastic)
		sign(unit, Enum.NormalId.Front, "RECOVERY\n12:00", accent, DARK, 50)
	end
	part(m, "WingBench", V3(5, 0.4, 1.6), CF(127, 1.7, 51.6), champ and rgb(60, 40, 30) or rgb(200, 200, 205), M.Wood, { collide = true })
	part(m, "WingBenchBase", V3(4.4, 1.2, 1.2), CF(127, 0.9, 51.6), DARK, M.Metal)
	for _, pos in ipairs({ V3(117, 0.5, 44), V3(117, 0.5, 52) }) do
		vcyl(m, "PlanterTall", 2.6, 1.6, CF(pos), WHITE, M.SmoothPlastic)
		part(m, "PlanterGrass", V3(1.8, 3.4, 1.8), CF(pos + V3(0, 3.8, 0)), rgb(70, 140, 70), M.Grass, { ellipsoid = true })
	end
	-- SOUTH: hot & cold plunge pools and the cryotherapy cabin
	plungePool(m, 125, 60.5, 8, 7.5, false)
	plungePool(m, 138, 60.5, 8, 7.5, true)
	cryoCabin(m, V3(147.5, 0.5, 59.5), champ)
	for k = 0, 2 do
		part(m, "RobeHook", V3(0.2, 0.2, 0.4), CF(113.6 + k * 1.4, 7, 64.6), CHROME, M.Metal)
		part(m, "Robe", V3(1.1, 3.4, 0.4), CF(113.6 + k * 1.4, 5.2, 64.5), champ and rgb(20, 20, 24) or WHITE, M.Fabric)
	end
	-- floor-edge light lines that lead you in from the doorway
	for _, z in ipairs({ 43.6, 52.4 }) do
		part(m, "FloorLine", V3(36, 0.03, 0.12), CF(130, 0.53, z), accent, M.Neon, { shadow = false })
	end
	if champ then
		-- gold everywhere a champion would put it
		part(m, "GoldCornice", V3(0.15, 0.4, 34), CF(151.85, 18.5, 48), GOLD, M.Metal)
		part(m, "GoldCornice", V3(40, 0.4, 0.15), CF(132, 18.5, 31.15), GOLD, M.Metal)
		part(m, "GoldCornice", V3(40, 0.4, 0.15), CF(132, 18.5, 64.85), GOLD, M.Metal)
	end
end

------------------------------------------------------------------------
-- 4. Career wall: your fights as posters next to the Fight Board
------------------------------------------------------------------------
local function resultText(e)
	local out = e.outcome == "win" and "WIN" or (e.outcome == "loss" and "LOSS" or "DRAW")
	local how = tostring(e.method or "")
	if (how == "KO" or how == "TKO") and e.round then
		how ..= " R" .. tostring(e.round)
	end
	return out, how
end

local function poster(parent, cf, w, h, e, style, P)
	local nick = P.identity and P.identity.nickname or ""
	local me = (P.identity and P.identity.name or "YOU"):upper()
	local opp = tostring(e.opp or "UNKNOWN"):upper()
	local out, how = resultText(e)
	local win = e.outcome == "win"
	if style == "paper" then
		-- a printed results sheet pinned to the corkboard
		local p = part(parent, "ResultSheet", V3(w, h, 0.03), cf * ANG(0, 0, RAD(math.random(-4, 4))), rgb(238, 234, 222), M.SmoothPlastic, { shadow = false })
		local sg = gui(p, Enum.NormalId.Back, 40, 0.8)
		label(sg, string.format("DAY %s\n%s\nvs %s\n%s %s", tostring(e.day or "?"), tostring(e.kind or "BOUT"):upper(), opp, out, how), { TextColor3 = rgb(40, 40, 50), Font = Enum.Font.Code, Size = UDim2.fromScale(0.9, 0.86), Position = UDim2.fromScale(0.05, 0.07) })
		part(parent, "Pin", V3(0.2, 0.2, 0.2), cf * CF(0, h / 2 - 0.25, 0.08), win and rgb(40, 150, 70) or RED, M.SmoothPlastic, { shape = Enum.PartType.Ball, shadow = false })
		return
	end
	local bg = win and rgb(18, 18, 24) or rgb(40, 16, 18)
	local accent = style == "gold" and GOLD or (win and rgb(255, 200, 40) or rgb(230, 70, 60))
	if style == "gold" then
		part(parent, "PosterFrame", V3(w + 0.35, h + 0.35, 0.08), cf * CF(0, 0, -0.04), GOLD, M.Metal, { reflect = 0.1 })
	end
	local p = part(parent, "CareerPoster", V3(w, h, 0.05), cf, bg, M.SmoothPlastic, { shadow = false })
	local sg = gui(p, Enum.NormalId.Back, 40, 0.5)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg })
	frame(sg, { Size = UDim2.new(1, 0, 0.13, 0), BackgroundColor3 = accent })
	label(sg, tostring(e.kind or "FIGHT NIGHT"):upper(), { TextColor3 = bg, Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.015) })
	label(sg, string.format("%s\n\"%s\"", me, tostring(nick):upper()), { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.16) })
	label(sg, "vs", { TextColor3 = accent, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.3, 0.08), Position = UDim2.fromScale(0.35, 0.39) })
	label(sg, opp, { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.48) })
	local stamp = frame(sg, { Size = UDim2.fromScale(0.62, 0.14), Position = UDim2.fromScale(0.19, 0.66), BackgroundColor3 = win and rgb(30, 140, 70) or (e.outcome == "loss" and rgb(170, 30, 30) or rgb(90, 90, 100)), Rotation = -6 })
	label(stamp, out .. (how ~= "" and ("  " .. how) or ""), { TextColor3 = WHITE })
	label(sg, string.format("%s  -  DAY %s", tostring(e.venue or "WCB ARENA"):upper(), tostring(e.day or "?")), { TextColor3 = rgb(190, 190, 200), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.88) })
end

local function buildCareer(m, P, idx)
	local hist = type(P.history) == "table" and P.history or {}
	local style = idx <= 1 and "paper" or (idx >= 4 and "gold" or "print")
	for i, x in ipairs({ -13.5, 13.5 }) do
		local base = CF(x, 0.5, 32.2) * ANG(0, RAD(180), 0) -- faces +Z: towards the spawn and the door
		local board = part(m, idx <= 1 and "Corkboard" or "CareerPanel", V3(8, 8.6, 0.3), base * CF(0, 5.4, 0), idx <= 1 and rgb(170, 125, 80) or rgb(22, 22, 28), idx <= 1 and M.Fabric or M.SmoothPlastic, { collide = true })
		part(m, "PanelFrame", V3(8.4, 9, 0.24), base * CF(0, 5.4, 0.04), idx >= 4 and GOLD or (idx <= 1 and rgb(110, 80, 50) or BLACK), idx >= 4 and M.Metal or M.Wood)
		for _, sx in ipairs({ -3.4, 3.4 }) do
			part(m, "PanelLeg", V3(0.3, 1.1, 0.6), base * CF(sx, 0.55, 0), BLACK, M.Metal)
		end
		local head = part(m, "PanelHeader", V3(8, 0.9, 0.1), base * CF(0, 10.1, -0.12), idx <= 1 and rgb(240, 236, 225) or DARK, M.SmoothPlastic)
		sign(head, Enum.NormalId.Front, i == 1 and (idx <= 1 and "FIGHT RESULTS" or "FIGHT HISTORY") or (idx <= 1 and "MEMBER NEWS" or "CAREER HIGHLIGHTS"), idx <= 1 and rgb(40, 40, 50) or GOLD, nil, 40, idx <= 1 and Enum.Font.Code or Enum.Font.GothamBlack)
		for k = 1, 4 do
			local e = hist[(i - 1) * 4 + k]
			local cx = (k % 2 == 1) and -1.95 or 1.95
			local cy = k <= 2 and 7.45 or 3.35
			local cf = base * CF(cx, cy, -0.2) * ANG(0, RAD(180), 0) -- poster's Back face points at the viewer
			if e then
				poster(m, cf, 3.4, 3.8, e, style, P)
			elseif k == 1 and i == 1 and #hist == 0 then
				local p = part(m, "FirstFight", V3(3.4, 3.8, 0.05), cf, idx <= 1 and rgb(238, 234, 222) or DARK, M.SmoothPlastic)
				sign(p, Enum.NormalId.Back, "YOUR FIRST FIGHT\nIS WAITING\n- FIGHT BOARD -", idx <= 1 and rgb(40, 40, 50) or GOLD, nil, 40)
			end
		end
	end
	-- record and titles strip under the right panel
	local rec = P.record or {}
	local arec = P.amateurRecord or {}
	local plate = part(m, "RecordPlate", V3(7.6, 0.8, 0.1), CF(13.5, 1.9, 32.45), DARK, M.SmoothPlastic)
	sign(plate, Enum.NormalId.Back, string.format("PRO %d-%d-%d  |  AMATEUR %d-%d", rec.w or 0, rec.l or 0, rec.d or 0, arec.w or 0, arec.l or 0), WHITE, DARK, 40)
end

------------------------------------------------------------------------
-- 5. Titles: trophy case, belt display plates, title photos
------------------------------------------------------------------------
local ORG_COLOR = { WBA = rgb(20, 20, 22), WBC = rgb(40, 140, 70), IBF = rgb(196, 30, 36), WBO = rgb(30, 60, 170) }

local function titleList(P)
	local list = {}
	local reg = type(P.regional) == "table" and P.regional or {}
	local belts = type(P.belts) == "table" and P.belts or {}
	for _, org in ipairs(Config.Orgs or {}) do
		if belts[org] then
			table.insert(list, { kind = "belt", org = org, name = org .. " WORLD CHAMPION", color = ORG_COLOR[org] or BLACK })
		end
	end
	if reg.national then
		table.insert(list, { kind = "cup", name = "NATIONAL CHAMPION", color = rgb(205, 127, 50) })
	end
	if reg.regional then
		table.insert(list, { kind = "cup", name = "REGIONAL CHAMPION", color = rgb(205, 210, 220) })
	end
	return list
end

local function trophyCup(parent, baseCF, h, color)
	part(parent, "TrophyBase", V3(0.9, 0.45, 0.9) * h, baseCF * CF(0, 0.225 * h, 0), BLACK, M.Marble)
	vcyl(parent, "TrophyStem", 0.7 * h, 0.22 * h, baseCF * CF(0, 0.45 * h, 0), color, M.Metal)
	vcyl(parent, "TrophyCup", 0.85 * h, 0.9 * h, baseCF * CF(0, 1.1 * h, 0), color, M.Metal, { reflect = 0.25 })
	for _, s in ipairs({ -1, 1 }) do
		part(parent, "TrophyHandle", V3(0.12, 0.55, 0.12) * h, baseCF * CF(s * 0.52 * h, 1.55 * h, 0), color, M.Metal)
	end
end

local function beltModel(parent, cf, strap, scale)
	scale = scale or 1
	part(parent, "BeltStrap", V3(3.8, 0.9, 0.12) * scale, cf, strap, M.Leather)
	part(parent, "BeltPlate", V3(1.5, 1.35, 0.18) * scale, cf * CF(0, 0, -0.06 * scale), GOLD, M.Metal, { reflect = 0.2 })
	cyl(parent, "BeltJewel", 0.08, 0.5 * scale, cf * CF(0, 0.05 * scale, -0.16 * scale) * ANG(0, RAD(90), 0), RED, M.Glass)
	for _, x in ipairs({ -1.25, 1.25 }) do
		part(parent, "BeltSidePlate", V3(0.6, 0.75, 0.16) * scale, cf * CF(x * scale, 0, -0.05 * scale), GOLD_DEEP, M.Metal)
	end
end

local hiddenDecor = {}
local function setCaseDecorHidden(hide)
	local g = gym()
	local lobby = g and g:FindFirstChild("Decor") and g.Decor:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	for _, p in ipairs(lobby:GetChildren()) do
		if p:IsA("BasePart") then
			local pos = p.Position
			if pos.X > -33.5 and pos.X < -14.5 and pos.Z > 69.5 and pos.Z < 74.6 and pos.Y > 2.9 and pos.Y < 8 and p.Name ~= "LightSource" then
				if hide and hiddenDecor[p] == nil then
					hiddenDecor[p] = p.Transparency
					p.Transparency = 1
				elseif not hide and hiddenDecor[p] ~= nil then
					p.Transparency = hiddenDecor[p]
					hiddenDecor[p] = nil
				end
			end
		end
	end
end

local function buildTrophies(m, P)
	local list = titleList(P)
	setCaseDecorHidden(#list > 0)
	local g = gym()
	local case = g and g:FindFirstChild("TrophyCase")
	if case and #list > 0 then
		-- your titles fill the case (the decorative pieces step aside for them)
		local n = math.min(6, #list)
		for i = 1, n do
			local t = list[i]
			local x = (case.Size.X - 4) * ((i - 0.5) / n - 0.5)
			local base = case.CFrame * CF(x, case.Size.Y / 2, -0.3)
			if t.kind == "cup" then
				trophyCup(m, base, 1.8, t.color)
			else
				part(m, "BeltStand", V3(0.25, 1.6, 0.25), base * CF(0, 0.8, 0.6), BLACK, M.Metal)
				beltModel(m, base * CF(0, 1.9, 0.45) * ANG(RAD(-10), 0, 0), t.color, 0.62)
			end
			local tagP = part(m, "TitlePlate", V3(2.6, 0.35, 0.06), case.CFrame * CF(x, case.Size.Y / 2 - 0.45, -case.Size.Z / 2 - 0.03), GOLD, M.Metal)
			sign(tagP, Enum.NormalId.Front, t.name, BLACK, nil, 50)
		end
		point(part(m, "CaseLight", V3(0.2, 0.2, 0.2), case.CFrame * CF(0, 5.6, 0), Color3.new(), M.SmoothPlastic, { transparency = 1 }), rgb(255, 228, 170), 9, 1.1)
	end
	-- "YOURS" plates under the belts you hold in the four-belt display over the Fight Board
	local belts = type(P.belts) == "table" and P.belts or {}
	local nick = P.identity and P.identity.nickname or ""
	for i, x in ipairs({ -5.6, -1.9, 1.9, 5.6 }) do
		local org = (Config.Orgs or {})[i]
		if org and belts[org] then
			local plate = part(m, "BeltYours", V3(3.2, 0.5, 0.06), CF(x, 10.75, 33.45), GOLD, M.Metal, { reflect = 0.15 })
			sign(plate, Enum.NormalId.Back, string.format("%s: \"%s\"", org, tostring(nick):upper()), BLACK, nil, 50)
			point(plate, rgb(255, 220, 140), 5, 0.8)
		end
	end
end

-- championship photos: a frozen clone of YOUR character (whatever pose it is in right now) in a
-- ViewportFrame with the belt on the shoulder, one per title (max 3), on a champions wall
local function stripTags(inst)
	for _, tg in ipairs(CollectionService:GetTags(inst)) do
		CollectionService:RemoveTag(inst, tg)
	end
end

local function photoClone(char)
	local ok, clone = pcall(function()
		local was = char.Archivable
		char.Archivable = true
		local c = char:Clone()
		char.Archivable = was
		return c
	end)
	if not ok or not clone then
		return nil
	end
	-- Clone copies CollectionService tags. A photo must stay frozen, so strip them all: otherwise
	-- FaceFX (FaceRig), HairFX (HairSway/HairStrand), BodyFX (Vein), the Animator and
	-- GymVisuals.watchModel (Trainee/Fighter) register the copy, animate it every frame and a
	-- Trainee+Station copy could even publish AutoAct and swing the real bag.
	stripTags(clone)
	for _, d in ipairs(clone:GetDescendants()) do
		stripTags(d)
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return clone
end

local function buildPhotos(m, P, idx)
	local list = titleList(P)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if #list == 0 then
		return
	end
	local champ = idx >= 4
	local base = CF(36, 0.5, 40) * ANG(0, RAD(180), 0) -- faces +Z (the entrance)
	part(m, "ChampWall", V3(14, 9, 0.4), base * CF(0, 5, 0), champ and rgb(16, 16, 20) or rgb(60, 44, 34), champ and M.SmoothPlastic or M.WoodPlanks, { collide = true })
	part(m, "ChampWallCap", V3(14.4, 0.3, 0.7), base * CF(0, 9.6, 0), champ and GOLD or rgb(110, 80, 50), champ and M.Metal or M.Wood)
	local head = part(m, "ChampWallTitle", V3(10, 0.9, 0.1), base * CF(0, 8.6, -0.26), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	sign(head, Enum.NormalId.Front, "CHAMPIONS OF THIS GYM", champ and GOLD or WHITE, nil, 40)
	local n = math.min(3, #list)
	local template = root and photoClone(char)
	if not template then
		keys.TitlePhotos = nil -- no character yet: try again on the next refresh
	end
	for i = 1, n do
		local t = list[i]
		local x = (i - (n + 1) / 2) * 4.3
		local fcf = base * CF(x, 4.7, -0.25)
		part(m, "PhotoFrame", V3(3.8, 4.6, 0.12), fcf, champ and GOLD or rgb(120, 90, 60), champ and M.Metal or M.Wood)
		local pic = part(m, "Photo", V3(3.4, 4.2, 0.05), fcf * CF(0, 0, -0.08), rgb(20, 20, 26), M.SmoothPlastic)
		local sg = gui(pic, Enum.NormalId.Front, 60, 0)
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.fromScale(1, 0.84)
		vp.BackgroundColor3 = t.kind == "belt" and rgb(28, 30, 40) or rgb(40, 34, 30)
		vp.Ambient = rgb(150, 150, 160)
		vp.LightColor = rgb(255, 240, 220)
		vp.LightDirection = V3(-0.4, -0.6, -1)
		vp.Parent = sg
		label(sg, t.name, { TextColor3 = GOLD, Size = UDim2.fromScale(0.94, 0.14), Position = UDim2.fromScale(0.03, 0.85) })
		if template then
			local c = template:Clone()
			c.Parent = vp
			local r = c:FindFirstChild("HumanoidRootPart")
			if r then
				-- move the frozen pose to the origin, facing the camera
				-- move the frozen pose so the root sits at the origin facing the camera (-Z)
				c:PivotTo(r.CFrame:Inverse() * c:GetPivot())
				local belt = newModel(c, "PhotoBelt")
				beltModel(belt, CF(0.9, 1.6, -0.6) * ANG(0, 0, RAD(-35)), t.color, 0.42)
			end
			local cam = Instance.new("Camera")
			cam.FieldOfView = 30
			cam.CFrame = CFrame.lookAt(V3(0, 1.8, -8.5), V3(0, 1.4, 0))
			cam.Parent = vp
			vp.CurrentCamera = cam
		end
		if champ then
			local src = part(m, "PhotoLight", V3(0.2, 0.2, 0.2), fcf * CF(0, 3, -1.4), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			spot(src, Enum.NormalId.Bottom, rgb(255, 235, 200), 6, 0.8, 70)
		end
	end
	if template then
		template:Destroy()
	end
end

------------------------------------------------------------------------
-- 6. World Champion: banners, media backdrop, red carpet, fans at the door
------------------------------------------------------------------------
local fans = {}
local function buildChampion(m, P, idx)
	fans = {}
	if idx < 4 then
		return
	end
	local name = (P.identity and P.identity.name or "THE CHAMP"):upper()
	local nick = (P.identity and P.identity.nickname or ""):upper()
	local belts = {}
	for _, org in ipairs(Config.Orgs or {}) do
		if type(P.belts) == "table" and P.belts[org] then
			table.insert(belts, org)
		end
	end
	local rec = P.record or {}
	-- hanging champion banner over the lobby and a strip under the ring canopy
	local b = part(m, "ChampionBanner", V3(14, 8, 0.12), CF(0, 23, 20), rgb(18, 14, 10), M.Fabric, { shadow = false })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = gui(b, face, 24, 0.5)
		frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(18, 14, 10) })
		frame(sg, { Size = UDim2.new(0.96, 0, 0.94, 0), Position = UDim2.fromScale(0.02, 0.03), BackgroundTransparency = 1 })
		label(sg, "HOME OF THE CHAMPION", { TextColor3 = GOLD, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.05) })
		label(sg, name, { TextColor3 = WHITE, Size = UDim2.fromScale(0.9, 0.26), Position = UDim2.fromScale(0.05, 0.2) })
		label(sg, "\"" .. nick .. "\"", { TextColor3 = GOLD, Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.47) })
		label(sg, (#belts > 0 and table.concat(belts, "  -  ") or "WORLD CHAMPION") .. string.format("\n%d-%d-%d", rec.w or 0, rec.l or 0, rec.d or 0), { TextColor3 = WHITE, Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.68) })
	end
	cyl(m, "BannerPole", 14.6, 0.2, CF(0, 27.1, 20), GOLD, M.Metal)
	part(m, "BannerFringe", V3(14, 0.3, 0.14), CF(0, 18.9, 20), GOLD, M.Fabric)
	for _, x in ipairs({ -6.8, 6.8 }) do
		part(m, "BannerCord", V3(0.06, 2.6, 0.06), CF(x, 28.4, 20), BLACK, M.Fabric, { shadow = false })
	end
	local strip = part(m, "CanopyChampion", V3(16, 1.8, 0.12), CF(0, 17.6, -59.35), rgb(18, 14, 10), M.Fabric, { shadow = false })
	sign(strip, Enum.NormalId.Front, "TRAINING CAMP OF " .. name, GOLD, nil, 30)
	sign(strip, Enum.NormalId.Back, "TRAINING CAMP OF " .. name, GOLD, nil, 30)
	-- media backdrop: step-and-repeat wall, softboxes, a TV camera on a tripod, a small podium
	local mb = CF(-19, 0.5, 36) * ANG(0, RAD(180), 0)
	local wall = part(m, "MediaBackdrop", V3(14, 8, 0.3), mb * CF(0, 4.3, 0), WHITE, M.SmoothPlastic, { collide = true })
	local sg = gui(wall, Enum.NormalId.Front, 20, 0.6)
	frame(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(245, 245, 248) })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.25, 0.2)
	grid.CellPadding = UDim2.fromScale(0, 0)
	grid.Parent = sg
	local names = { "WCB", "WCB SPORTS" }
	for _, sp in ipairs(Catalog.Sponsors or {}) do
		table.insert(names, sp.logo and sp.logo.text or sp.name)
	end
	for k = 1, 20 do
		local nm = names[(k - 1) % #names + 1]
		local cell = label(sg, nm, { TextColor3 = (k % 3 == 0) and RED or (k % 3 == 1 and DARK or rgb(30, 60, 160)), Font = Enum.Font.GothamBlack, LayoutOrder = k, Size = UDim2.fromScale(0.25, 0.2) })
		cell.TextScaled = true
	end
	for _, sx in ipairs({ -5.5, 5.5 }) do
		local st = mb * CF(sx, 0, -6)
		part(m, "LightStand", V3(0.14, 6, 0.14), st * CF(0, 3, 0), BLACK, M.Metal)
		local box = part(m, "Softbox", V3(2.2, 2.2, 0.8), CFrame.lookAt((st * CF(0, 6.4, 0)).Position, (mb * CF(0, 3.5, 0)).Position), BLACK, M.Fabric)
		local diff = part(m, "SoftboxFront", V3(2.0, 2.0, 0.05), box.CFrame * CF(0, 0, -0.42), WHITE, M.Neon, { shadow = false })
		spot(diff, Enum.NormalId.Front, rgb(255, 245, 235), 14, 0.8, 70)
	end
	local tri = mb * CF(0, 0, -12)
	for k = 0, 2 do
		local a = k * RAD(120)
		rod(m, "TripodLeg", (tri * CF(math.cos(a) * 1.0, 0, math.sin(a) * 1.0)).Position, (tri * CF(0, 4.2, 0)).Position, 0.12, BLACK, M.Metal)
	end
	local camCF = CFrame.lookAt((tri * CF(0, 4.6, 0)).Position, (mb * CF(0, 3.8, 0)).Position)
	part(m, "TVCamera", V3(1.0, 1.1, 2.4), camCF, rgb(40, 40, 46), M.SmoothPlastic)
	cyl(m, "TVLens", 0.9, 0.7, camCF * CF(0, 0, -1.5) * ANG(0, RAD(90), 0), DARK, M.Glass)
	local tally = part(m, "TVTally", V3(0.2, 0.2, 0.1), camCF * CF(0, 0.65, -1.0), rgb(255, 30, 30), M.Neon, { shadow = false })
	CollectionService:AddTag(tally, "NeonFlicker")
	local podium = part(m, "Podium", V3(2.2, 3.6, 1.4), mb * CF(0, 1.8, -2.2), rgb(20, 20, 24), M.SmoothPlastic, { collide = true })
	sign(podium, Enum.NormalId.Back, "WCB", GOLD, nil, 40)
	for k = 0, 1 do
		rod(m, "Mic", (mb * CF(-0.3 + k * 0.6, 3.6, -2.0)).Position, (mb * CF(-0.2 + k * 0.4, 4.3, -2.6)).Position, 0.1, BLACK, M.Metal)
	end
	-- red carpet from the door to the Fight Board (raised over the spawn pad)
	for _, seg in ipairs({ { 66.5, 78.4, 0.525 }, { 55, 65, 1.03 }, { 37, 54.5, 0.525 } }) do
		local mid, len = (seg[1] + seg[2]) / 2, seg[2] - seg[1]
		part(m, "RedCarpet", V3(6, 0.04, len), CF(0, seg[3], mid), rgb(150, 18, 26), M.Fabric, { shadow = false })
		for _, sx in ipairs({ -3.05, 3.05 }) do
			part(m, "CarpetEdge", V3(0.12, 0.05, len), CF(sx, seg[3], mid), GOLD, M.Fabric, { shadow = false })
		end
	end
	for _, z in ipairs({ 70, 75 }) do
		for _, sx in ipairs({ -4.2, 4.2 }) do
			local s = CF(sx, 0.5, z)
			vcyl(m, "StanchionBase", 0.1, 0.8, s, GOLD, M.Metal)
			vcyl(m, "Stanchion", 2.7, 0.15, s, GOLD, M.Metal)
		end
	end
	for _, sx in ipairs({ -4.2, 4.2 }) do
		rod(m, "VelvetRope", V3(sx, 3.0, 70), V3(sx, 2.5, 72.5), 0.14, rgb(150, 20, 30), M.Fabric)
		rod(m, "VelvetRope", V3(sx, 2.5, 72.5), V3(sx, 3.0, 75), 0.14, rgb(150, 20, 30), M.Fabric)
	end
	-- fans behind barriers outside the door: more of them the more famous you are
	local pop = tonumber(P.popularity) or 0
	local count = math.clamp(math.floor(pop * 0.4), 8, 40)
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 5 do
			local z = 91 + k * 3
			part(m, "Barrier", V3(0.2, 0.18, 2.9), CF(sx * 6.5, 3.1, z), CHROME, M.Metal)
			part(m, "Barrier", V3(0.2, 0.18, 2.9), CF(sx * 6.5, 1.0, z), CHROME, M.Metal)
			for _, dz in ipairs({ -1.3, 1.3 }) do
				part(m, "BarrierLeg", V3(0.14, 3.0, 0.14), CF(sx * 6.5, 1.65, z + dz), CHROME, M.Metal)
			end
		end
	end
	local rng = Random.new(4242)
	local shirts = { RED, rgb(240, 200, 40), WHITE, rgb(30, 30, 34), BLUE, rgb(40, 150, 70) }
	local skins = { rgb(240, 200, 170), rgb(200, 150, 110), rgb(150, 100, 70), rgb(100, 66, 44) }
	for i = 1, count do
		local sx = i % 2 == 0 and 1 or -1
		local row = math.floor((i - 1) / 24)
		local z = 90.5 + ((i * 7) % 24) * 0.75
		local x = sx * (7.6 + row * 1.6 + rng:NextNumber(0, 0.5))
		local baseCF = CFrame.lookAt(V3(x, 0, z), V3(0, 0, z - 2))
		local body = part(m, "Fan", V3(1.3, 2.2, 0.8), baseCF * CF(0, 1.1, 0), shirts[rng:NextInteger(1, #shirts)], M.Fabric)
		local headP = part(m, "FanHead", V3(0.95, 0.95, 0.95), baseCF * CF(0, 2.75, 0), skins[rng:NextInteger(1, #skins)], M.SmoothPlastic, { shape = Enum.PartType.Ball })
		local entry = { parts = { body, headP }, base = { body.CFrame, headP.CFrame }, phase = rng:NextNumber(0, 6.28), speed = rng:NextNumber(2.5, 5) }
		if i % 4 == 0 then
			local signP = part(m, "FanSign", V3(1.8, 1.2, 0.06), baseCF * CF(0, 4.2, -0.3), WHITE, M.SmoothPlastic)
			sign(signP, Enum.NormalId.Front, ({ "CHAMP!", nick .. "!", "GOAT", "#1 FAN", "SIGN MY GLOVE" })[(i // 4 - 1) % 5 + 1], RED, nil, 40, Enum.Font.Cartoon)
			table.insert(entry.parts, signP)
			table.insert(entry.base, signP.CFrame)
		elseif i % 3 == 0 then
			local arm = part(m, "FanArm", V3(0.35, 1.4, 0.35), baseCF * CF(0.75, 3.1, 0) * ANG(0, 0, RAD(-20)), body.Color, M.Fabric)
			table.insert(entry.parts, arm)
			table.insert(entry.base, arm.CFrame)
		end
		table.insert(fans, entry)
	end
	-- two photographers with flashes at the head of the line
	for _, sx in ipairs({ -1, 1 }) do
		local pcf = CFrame.lookAt(V3(sx * 4.5, 0.3, 92), V3(0, 3, 80))
		part(m, "Photographer", V3(1.3, 2.3, 0.8), pcf * CF(0, 1.45, 0), BLACK, M.Fabric)
		part(m, "PhotographerHead", V3(0.9, 0.9, 0.9), pcf * CF(0, 3.1, 0), skins[2], M.SmoothPlastic, { shape = Enum.PartType.Ball })
		part(m, "PressCamera", V3(0.6, 0.45, 0.5), pcf * CF(0, 3.1, -0.65), DARK, M.SmoothPlastic)
		local flash = part(m, "CameraFlash", V3(0.35, 0.2, 0.05), pcf * CF(0, 3.45, -0.75), WHITE, M.Neon, { shadow = false, transparency = 0.2 })
		CollectionService:AddTag(flash, "NeonFlicker")
	end
end

------------------------------------------------------------------------
-- 7. The sparring ring: rope Beams with sag and physics, corner pads, apron, steps
------------------------------------------------------------------------
local ropes = {} -- { beam, a0, a1, side, h, sag }
local sideState = {} -- side -> { off, v }
local ringCenter = V3(0, 0, -50)
local RING_HALF, RING_H = 11, 2.5

local function hideServerRopes(hide)
	local g = gym()
	local ring = g and g:FindFirstChild("GymRing")
	if not ring then
		return
	end
	for _, p in ipairs(ring:GetChildren()) do
		if p.Name == "Rope" and p:IsA("BasePart") then
			p.Transparency = hide and 1 or 0
		end
	end
end

local function attCF(localPos, dir, along)
	return CFrame.fromMatrix(localPos, dir, along)
end

local function buildRing(m, lv, idx)
	ropes = {}
	sideState = {}
	local g = gym()
	local ring = g and g:FindFirstChild("GymRing")
	local canvas = ring and ring:FindFirstChild("Canvas")
	if canvas then
		ringCenter = V3(canvas.Position.X, 0, canvas.Position.Z)
	end
	local c = ringCenter
	local top = RING_H + 0.3
	local anchor = part(m, "RopeAnchor", V3(0.2, 0.2, 0.2), CF(c), Color3.new(), M.SmoothPlastic, { transparency = 1, shadow = false })
	local corners = { { -RING_HALF, -RING_HALF }, { RING_HALF, -RING_HALF }, { RING_HALF, RING_HALF }, { -RING_HALF, RING_HALF } }
	local colors = ({ { rgb(205, 200, 190), rgb(170, 168, 160) }, { RED, WHITE }, { GOLD, WHITE } })[math.clamp(lv, 1, 3)]
	local sag = ({ 0.6, 0.3, 0.12 })[math.clamp(lv, 1, 3)]
	for ri, h in ipairs({ 1.4, 2.6, 3.8 }) do
		for side = 1, 4 do
			local a, b = corners[side], corners[side % 4 + 1]
			local pa = V3(a[1], RING_H + h, a[2])
			local pb = V3(b[1], RING_H + h, b[2])
			local along = (pb - pa).Unit
			local a0 = Instance.new("Attachment")
			a0.CFrame = attCF(pa, V3(0, -1, 0), along)
			a0.Parent = anchor
			local a1 = Instance.new("Attachment")
			a1.CFrame = attCF(pb, V3(0, -1, 0), along)
			a1.Parent = anchor
			local beam = Instance.new("Beam")
			beam.Attachment0, beam.Attachment1 = a0, a1
			beam.Width0, beam.Width1 = 0.24, 0.24
			beam.FaceCamera = true
			beam.Segments = 14
			beam.Color = ColorSequence.new(ri == 2 and colors[2] or colors[1])
			beam.LightInfluence = 1
			beam.Transparency = NumberSequence.new(0)
			beam.CurveSize0, beam.CurveSize1 = sag, -sag
			beam.Parent = anchor
			-- outward = away from the ring centre, perpendicular to this side
			local mid = (pa + pb) / 2
			local outward = V3(mid.X, 0, mid.Z).Unit
			table.insert(ropes, { beam = beam, a0 = a0, a1 = a1, side = side, h = h, sag = sag, pa = pa, pb = pb, along = along, out = outward })
		end
	end
	for side = 1, 4 do
		sideState[side] = { off = 0, v = 0 }
	end
	hideServerRopes(true)
	-- turnbuckle pads on the inside of each post
	for i, cr in ipairs(corners) do
		local dir = V3(-cr[1], 0, -cr[2]).Unit
		local pos = c + V3(cr[1], top + 2.2, cr[2]) + dir * 0.55
		local col = i == 1 and RED or (i == 3 and BLUE or WHITE)
		local pad = part(m, "TurnbucklePad", V3(1.0, 3.8, 1.0), CFrame.lookAt(pos, pos + dir), lv == 1 and TAPE or col, lv == 1 and M.Foil or M.Leather)
		if lv >= 2 then
			sign(pad, Enum.NormalId.Front, "WCB", col == WHITE and BLACK or WHITE, nil, 40)
		else
			for k = -1, 1 do
				part(m, "PadTape", V3(1.05, 0.25, 1.05), pad.CFrame * CF(0, k * 1.2, 0), rgb(40, 40, 44), M.Foil)
			end
		end
	end
	-- apron skirt with logos
	local half = RING_HALF + 2
	local skirtText = ({ "", "WCB BOXING CLUB", "WORLD CLASS BOXING" })[math.clamp(lv, 1, 3)]
	for k = 0, 3 do
		local yaw = k * math.pi / 2
		local cf = CF(c + V3(0, RING_H / 2, 0)) * ANG(0, yaw, 0) * CF(0, 0, half + 0.06)
		local skirt = part(m, "ApronSkirt", V3(half * 2 + 0.1, RING_H - 0.1, 0.08), cf, lv == 1 and rgb(40, 40, 44) or (lv >= 3 and DARK or BLUE), M.Fabric)
		if skirtText ~= "" then
			local sg = gui(skirt, Enum.NormalId.Back, 24, 0.6)
			label(sg, skirtText, { TextColor3 = lv >= 3 and GOLD or WHITE, Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.2, 0.1) })
			if idx >= 2 and Catalog.Sponsors and #Catalog.Sponsors > 0 then
				local sp = Catalog.Sponsors[(k + idx) % #Catalog.Sponsors + 1]
				local logo = sp.logo or {}
				for _, sx in ipairs({ 0.02, 0.82 }) do
					local f = frame(sg, { Size = UDim2.fromScale(0.16, 0.8), Position = UDim2.fromScale(sx, 0.1), BackgroundColor3 = c3(logo.bg, BLACK) })
					label(f, logo.text or sp.name, { TextColor3 = c3(logo.fg, WHITE) })
				end
			end
		else
			for t = 0, 1 do
				part(m, "SkirtTape", V3(1.6, 0.3, 0.02), cf * CF(-6 + t * 9, 0.4 - t * 0.6, 0.05) * ANG(0, 0, RAD(t == 0 and 12 or -20)), TAPE, M.Foil)
			end
		end
	end
	-- ring steps at the blue corner side
	for k = 1, 3 do
		part(m, "RingStep", V3(2.4, 0.8 * k, 0.9), CF(c + V3(9, 0.4 * k, half + 0.45 + (3 - k) * 0.9)), lv >= 3 and DARK or rgb(60, 60, 66), M.DiamondPlate, { collide = true })
	end
	if lv == 1 then
		-- patched canvas and old stains
		local rng = Random.new(9)
		for _ = 1, 4 do
			part(m, "CanvasTape", V3(rng:NextNumber(1.2, 2.6), 0.03, 0.4), CF(c + V3(rng:NextNumber(-8, 8), top + 0.02, rng:NextNumber(-8, 8))) * ANG(0, rng:NextNumber(0, 3), 0), TAPE, M.Foil, { shadow = false })
		end
		for _ = 1, 3 do
			part(m, "CanvasStain", V3(rng:NextNumber(0.8, 1.8), 0.02, rng:NextNumber(0.6, 1.4)), CF(c + V3(rng:NextNumber(-7, 7), top + 0.015, rng:NextNumber(-7, 7))), rgb(90, 30, 28), M.SmoothPlastic, { ellipsoid = true, transparency = 0.55, shadow = false })
		end
	end
end

-- ropes give where a body leans on them; they settle back with a little wobble.
-- Runs at 30 Hz near the ring, so it allocates nothing per tick (PLAN constraint 4): the push
-- slots, the side normals and the list of bodies near the ring are module-level and reused.
local ropePush = { 0, 0, 0, 0 }
local ROPE_SIDES = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local ropeBodies = {} -- HumanoidRootParts of Fighter/Ambient models, refreshed at 2 Hz
local ropeBodiesAt = -1
local ropeIdleAt = -1 -- last time settled ropes were redrawn (only the tiny sway moves them)

local function ropeLean(pos)
	local lx, lz = pos.X - ringCenter.X, pos.Z - ringCenter.Z
	if math.abs(lx) > RING_HALF + 2 or math.abs(lz) > RING_HALF + 2 or pos.Y < RING_H then
		return
	end
	for side = 1, 4 do
		local s = ROPE_SIDES[side]
		local dist = RING_HALF - (s[1] ~= 0 and lx * s[1] or lz * s[2])
		-- only a body INSIDE the ropes bows them out; the cutman and the ringside watchers stand
		-- on the apron outside the rope line (dist < 0) and just rest on them
		if dist > -0.4 and dist < 1.6 then
			ropePush[side] = math.max(ropePush[side], (1.6 - dist) * 0.5)
		end
	end
end

-- who can lean on the ropes: cached so the 30 Hz tick does not call GetTagged (two fresh
-- arrays, ~30 members) every time; bodies only need to be found within half a second
local function refreshRopeBodies(t)
	if t - ropeBodiesAt < 0.5 then
		return
	end
	ropeBodiesAt = t
	table.clear(ropeBodies)
	for _, tagName in ipairs({ "Fighter", "Ambient" }) do
		for _, mdl in ipairs(CollectionService:GetTagged(tagName)) do
			local r = mdl:FindFirstChild("HumanoidRootPart")
			if r then
				local lx, lz = r.Position.X - ringCenter.X, r.Position.Z - ringCenter.Z
				-- generous margin: a body walking up to the ropes is picked up within one refresh
				if math.abs(lx) < RING_HALF + 12 and math.abs(lz) < RING_HALF + 12 then
					table.insert(ropeBodies, r)
				end
			end
		end
	end
end

local function updateRopes(dt, t)
	if #ropes == 0 then
		return
	end
	ropePush[1], ropePush[2], ropePush[3], ropePush[4] = 0, 0, 0, 0
	refreshRopeBodies(t)
	for _, r in ipairs(ropeBodies) do
		if r.Parent then
			ropeLean(r.Position)
		end
	end
	local ch = player.Character
	local myRoot = ch and ch:FindFirstChild("HumanoidRootPart")
	if myRoot then
		ropeLean(myRoot.Position)
	end
	local settled = true
	for side = 1, 4 do
		local st = sideState[side]
		st.v += ((ropePush[side] - st.off) * 90 - st.v * 6) * dt
		st.off += st.v * dt
		if math.abs(st.off) > 1e-3 or math.abs(st.v) > 1e-3 or ropePush[side] > 0 then
			settled = false
		end
	end
	-- with nobody on the ropes only the 0.015-stud sway moves them: redraw that at ~6 Hz
	-- instead of rewriting 24 attachments and 12 beams 30 times a second
	if settled then
		if t - ropeIdleAt < 0.16 then
			return
		end
		ropeIdleAt = t
	end
	for _, r in ipairs(ropes) do
		local st = sideState[r.side]
		local sway = math.sin(t * 2.1 + r.side * 1.7 + r.h) * 0.015
		local bulge = st.off * (0.6 + r.h * 0.25)
		local dirV = V3(0, -(r.sag + sway), 0) + r.out * bulge
		local mag = dirV.Magnitude
		if mag > 1e-3 then
			local dir = dirV / mag
			r.a0.CFrame = attCF(r.pa, dir, r.along)
			r.a1.CFrame = attCF(r.pb, dir, r.along)
			r.beam.CurveSize0, r.beam.CurveSize1 = mag, -mag
		end
	end
end

------------------------------------------------------------------------
-- 8. Staff (Elite+): local clones of gym members re-cast as wing staff / a camera crew
------------------------------------------------------------------------
local CREW = {
	{ src = "Chef Ana", name = "Dr. Ines Vale", role = "Sports Scientist", at = V3(124.5, 0, 35), look = V3(124.5, 0, 38), minTier = 3, prop = "tablet" },
	{ src = "Kim Park", name = "Tomas Reed", role = "Physiotherapist", at = V3(131.4, 0, 58), look = V3(125, 0, 60.5), minTier = 3 },
	{ src = "Coach Benny", name = "Lou Marsh", role = "Camera Operator", at = V3(-19, 0, 49.6), look = V3(-19, 0, 36), minTier = 4 },
}

-- The source NPCs spawn one by one on the server (with yields), so on a fresh join they may not
-- exist yet. A missing source clears the key (the next Refresh rebuilds, like the title photos)
-- and schedules a few retries of its own, because an idle player may get no profile push soon.
local crewRetries = 0
local crewRetryPending = false
local scheduleCrewRetry -- defined after buildCrew below

local function buildCrew(m, idx)
	local members = workspace:FindFirstChild("GymMembers")
	local missing = members == nil and idx >= 3 -- no staff below Elite, nothing to wait for
	for _, def in ipairs(members and CREW or {}) do
		if idx >= def.minTier then
			local src = members:FindFirstChild(def.src)
			local root = src and src:FindFirstChild("HumanoidRootPart")
			if not root then
				missing = true
			end
			if root then
				local ok, clone = pcall(function()
					local was = src.Archivable
					src.Archivable = true
					local c = src:Clone()
					src.Archivable = was
					return c
				end)
				if ok and clone then
					for _, d in ipairs(clone:GetDescendants()) do
						if d:IsA("Script") or d:IsA("LocalScript") then
							d:Destroy()
						end
					end
					local look = clone:FindFirstChild("BoxerLook")
					local held = look and look:FindFirstChild("Held")
					if held then
						held:Destroy()
					end
					for _, a in ipairs({ "SparPartner", "MittCall", "MittCallT", "Pose", "AutoAct", "AutoActId" }) do
						clone:SetAttribute(a, nil)
					end
					clone.Name = def.name
					clone:SetAttribute("Loop", def.role == "Camera Operator" and "coachwatch" or "idle")
					clone:SetAttribute("AmbientSeed", (src:GetAttribute("AmbientSeed") or 1) + 5000)
					clone:SetAttribute("Expr", "neutral")
					local tagGui = clone:FindFirstChild("Head") and clone.Head:FindFirstChild("NameTag")
					if tagGui then
						for _, l in ipairs(tagGui:GetChildren()) do
							if l:IsA("TextLabel") then
								l.Text = l.Name == "Role" and def.role or def.name
							end
						end
					end
					local cr = clone:FindFirstChild("HumanoidRootPart")
					if cr then
						cr.Anchored = true
					end
					-- same height above its floor as the source (both stand on the 0.5 floor)
					local yaw = math.atan2(-(def.look.X - def.at.X), -(def.look.Z - def.at.Z))
					local target = CF(def.at.X, root.Position.Y, def.at.Z) * ANG(0, yaw, 0)
					clone.Parent = m
					clone:PivotTo(target * root.CFrame:Inverse() * clone:GetPivot())
					if def.prop == "tablet" then
						local hand = clone:FindFirstChild("LeftHand")
						if hand then
							local tab = part(m, "Tablet", V3(0.9, 1.2, 0.08), hand.CFrame * CF(0, -0.2, -0.3) * ANG(RAD(60), 0, 0), DARK, M.SmoothPlastic)
							tab.Anchored = false
							tab.Massless = true
							local w = Instance.new("WeldConstraint")
							w.Part0, w.Part1 = hand, tab
							w.Parent = tab
							tab.Parent = clone
							sign(tab, Enum.NormalId.Front, "VO2 58\nHRV 74", rgb(110, 220, 255), rgb(8, 12, 20), 60)
						end
					end
					CollectionService:AddTag(clone, "Ambient")
				end
			end
		end
	end
	if missing then
		keys.Crew = nil -- the next Refresh tries again
		scheduleCrewRetry(m.Parent) -- m.Parent is the Facility root
	else
		crewRetries = 0
	end
end

function scheduleCrewRetry(facility)
	if crewRetryPending or crewRetries >= 20 then
		return -- ~60 s of retries covers the server's member spawn; Refresh keeps retrying after
	end
	crewRetryPending = true
	crewRetries += 1
	task.delay(3, function()
		crewRetryPending = false
		-- only if nothing rebuilt the crew meanwhile and the tier still wants staff
		local tier = GymFacility.Tier or 0
		if keys.Crew == nil and facility and facility.Parent and tier >= 3 then
			rebuild(facility, "Crew", tostring(math.min(tier, 4)), buildCrew, tier)
		end
	end)
end

------------------------------------------------------------------------
-- 9. The facility-upgrade reveal (a tier went up while you were playing)
------------------------------------------------------------------------
local function revealTier(idx, def)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not (pg and def) then
		return
	end
	local old = pg:FindFirstChild("FacilityReveal")
	if old then
		old:Destroy()
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "FacilityReveal"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 40
	sg.Parent = pg
	local band = frame(sg, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.new(0, 0, 0, 150), BackgroundColor3 = rgb(10, 10, 14), BackgroundTransparency = 0.1, ClipsDescendants = true })
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = band
	label(band, "FACILITY UPGRADE", { TextColor3 = GOLD, Font = Enum.Font.GothamBold, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 10) })
	label(band, (def.name or "NEW TIER"):upper(), { TextColor3 = WHITE, Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 38) })
	local fac = {}
	for _, f in ipairs(def.facilities or {}) do
		table.insert(fac, Config.FacilityNames and Config.FacilityNames[f] or f)
	end
	label(band, (def.desc or "") .. (#fac > 0 and ("\nNEW: " .. table.concat(fac, "  -  ")) or ""), { TextColor3 = rgb(200, 205, 215), Font = Enum.Font.GothamMedium, Size = UDim2.new(1, -40, 0, 48), Position = UDim2.fromOffset(20, 92) })
	TweenService:Create(band, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.62, 0, 0, 150) }):Play()
	local cam = workspace.CurrentCamera
	local pos = cam and cam.CFrame.Position or Vector3.zero
	for k = 0, 2 do
		task.delay(k * 0.2, function()
			GymSound.Play("reveal", pos, { volume = 1.3, speed = 1 + k * 0.26 })
		end)
	end
	task.delay(0.8, function()
		GymSound.Play("bell", pos, { volume = 0.8 })
	end)
	task.delay(5.5, function()
		if band.Parent then
			TweenService:Create(band, TweenInfo.new(0.4), { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 150) }):Play()
			task.delay(0.5, function()
				sg:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------------
-- Refresh + per-frame
------------------------------------------------------------------------
local root -- LocalGym/Facility
function GymFacility.Refresh(P, localGym, info)
	if not (P and localGym and info) then
		return
	end
	local idx = math.clamp(tonumber(info.idx) or 1, 1, 4)
	if not root or root.Parent ~= localGym then
		root = localGym:FindFirstChild("Facility") or newModel(localGym, "Facility")
		keys = {}
	end
	pcall(applyLamps, idx)
	pcall(restyleRacks, idx)
	rebuild(root, "TierDressing", tostring(idx), buildDressing, idx, P)
	local needKey = info.needs and info.needs[1] or ""
	rebuild(root, "EliteWingLocal", string.format("%d|%d|%s", idx, idx < 3 and math.floor((info.frac or 0) * 100) or 0, idx < 3 and needKey or ""), buildWing, idx, P, info.frac, info.needs)
	pcall(setGate, idx >= 3)
	-- career wall: the newest fights (the summary sends newest first)
	local hist = type(P.history) == "table" and P.history or {}
	local h1 = hist[1]
	local careerKey = string.format("%d|%d|%s|%s|%s", idx >= 4 and 3 or (idx <= 1 and 1 or 2), #hist, h1 and tostring(h1.day) or "", h1 and tostring(h1.opp) or "", P.identity and tostring(P.identity.nickname) or "")
	rebuild(root, "CareerWall", careerKey, buildCareer, P, idx)
	local titles = titleList(P)
	local tkeys = {}
	for _, t in ipairs(titles) do
		table.insert(tkeys, t.name)
	end
	local titleKey = table.concat(tkeys, ",") .. "|" .. (P.identity and tostring(P.identity.nickname) or "")
	rebuild(root, "LocalTrophies", titleKey, buildTrophies, P)
	rebuild(root, "TitlePhotos", titleKey .. "|" .. (idx >= 4 and "c" or ""), buildPhotos, P, idx)
	rebuild(root, "ChampionDressing", string.format("%d|%d|%s", idx, math.floor((tonumber(P.popularity) or 0) / 10), titleKey), buildChampion, P, idx)
	rebuild(root, "RingUpgrades", string.format("%d|%d", info.ringLevel or 1, idx), buildRing, info.ringLevel or 1, idx)
	rebuild(root, "Crew", tostring(math.min(idx, 4)), buildCrew, idx)
	if info.prev and idx > info.prev then
		pcall(revealTier, idx, info.def)
	end
	GymFacility.Tier = idx
end

-- ropes at 30 Hz near the ring, fans bob at 10 Hz near the door, roof leaks drip
local acc, fanAcc, dripAt = 0, 0, 0
local fanBulkP, fanBulkC = {}, {} -- reused every bob (no per-tick allocation)
RunService.Heartbeat:Connect(function(dt)
	if not (root and root.Parent and root.Parent.Parent) then
		return
	end
	acc += dt
	fanAcc += dt
	if acc < 1 / 30 then
		return
	end
	local step = math.min(acc, 0.1)
	acc = 0
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	local t = os.clock()
	if (cp - ringCenter).Magnitude < 110 then
		updateRopes(step, t)
	end
	if fanAcc >= 0.1 and #fans > 0 and (cp - V3(0, 0, 98)).Magnitude < 170 then
		fanAcc = 0
		local bp, bc = fanBulkP, fanBulkC
		for _, f in ipairs(fans) do
			local lift = math.max(0, math.sin(t * f.speed + f.phase)) * 0.35
			for i, p in ipairs(f.parts) do
				if p.Parent then
					table.insert(bp, p)
					table.insert(bc, f.base[i] + V3(0, lift, 0))
				end
			end
		end
		pcall(workspace.BulkMoveTo, workspace, bp, bc, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(bp)
		table.clear(bc)
	end
	if GymFacility.Tier == 1 and t >= dripAt then
		dripAt = t + 1.6 + math.random() * 1.6
		for _, pos in ipairs({ V3(38, 1.2, -58), V3(-58, 1.2, -14) }) do
			if (cp - pos).Magnitude < 45 then
				GymSound.Play("drip", pos, { volume = 1 })
			end
		end
	end
end)

return GymFacility
