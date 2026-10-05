-- GymVisuals: draws YOUR gym's equipment (client side) at every station, matched to
-- your upgrade level and its condition: worn canvas bags with duct tape and tears,
-- leather and smart bags, speed-bag platforms, double-end bags on elastic cords,
-- benches, racks, plates, the medicine-ball station, treadmills, bikes, rowers, ice baths,
-- sauna, massage table, the elite recovery chamber, pool upgrades and the sparring-ring styling.
-- Every level reads at a glance: level 1 is worn, rusty, taped and mismatched, the middle
-- levels are clean pro gear, the top levels get gold trim, LED accents and smart screens.
-- Hanging bags are real pendulums (swing, twist, shock-spring bob, segment dents, stand shake,
-- chain jingle, per-material sound) and react to YOUR punches, to other players training and to
-- the gym members working the members' bags (Animator's client-local AutoAct, CONTRACTS s.7).
-- The speed bag rebounds, the double-end bag springs back, belts, flywheels, pedals and fans
-- spin while someone trains, smart displays show your numbers, sweat drips onto the floor,
-- and the bar / dumbbells / rope / ball you pick up leave the rack. An upgrade is revealed with
-- a fade-in, confetti and a chime. Refresh(P) also hands the facility tier to GymFacility (tier
-- dressing, elite wing, career wall, trophies) and Ambience (dust, grade).
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local GymSound = require(script.Parent:WaitForChild("GymSound"))

local GymVisuals = {}
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer

-- optional companions: if one of them fails to load the stations still work
local function optional(name)
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild(name, 10))
	end)
	if not ok then
		warn("[GymVisuals] " .. name .. " unavailable: " .. tostring(mod))
		return nil
	end
	return mod
end

-- built-in Roblox sounds (no uploaded assets needed); played through GymSound's pool
local THUD = "rbxasset://sounds/action_jump_land.mp3"
function GymVisuals.Sound(pos, speed, volume, id)
	if typeof(pos) ~= "Vector3" then
		return
	end
	GymSound.Play("raw", pos, { id = id or THUD, speed = speed or 1, volume = volume or 0.5, maxDistance = 70 })
end

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local M = Enum.Material

local folder -- workspace.LocalGym
local built = {} -- id -> { key, model, dyn }
local dynamics = {} -- id -> dynamic state (swing etc.)

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function part(model, name, size, cf, color, material, opts)
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
	p.Parent = model
	return p
end

local function cyl(model, name, length, diameter, cf, color, material, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return part(model, name, V3(length, diameter, diameter), cf, color, material, opts)
end

-- vertical cylinder standing on its base centre
local function vcyl(model, name, height, diameter, baseCF, color, material, opts)
	return cyl(model, name, height, diameter, baseCF * CF(0, height / 2, 0) * ANG(0, 0, RAD(90)), color, material, opts)
end

local function surfaceText(p, face, text, fg, bg, ppu)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 50
	sg.LightInfluence = 0.2
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	t.BackgroundTransparency = bg and 0 or 1
	t.TextColor3 = fg or Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = true
	t.Text = text
	t.Parent = sg
	sg.Parent = p
	return t
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 10
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = p
	return l
end

local function wear(color, cond, amount)
	local t = math.clamp((85 - (cond or 100)) / 85, 0, 1) * (amount or 0.4)
	return color:Lerp(Color3.fromRGB(70, 55, 40), t)
end

local GOLD = Color3.fromRGB(255, 196, 40)
local STEEL = Color3.fromRGB(175, 178, 185)
local CHROME = Color3.fromRGB(215, 218, 225)
local BLACK = Color3.fromRGB(28, 28, 32)
local RUST = Color3.fromRGB(125, 78, 48)
local WOOD = Color3.fromRGB(140, 100, 65)
local WHITE = Color3.fromRGB(235, 235, 240)

local function plaque(model, O, offset, title, levelName, lv, cond, elite)
	local p = part(model, "Plaque", V3(2.6, 1.2, 0.15), O * offset, BLACK, M.SmoothPlastic)
	vcyl(model, "PlaquePost", (O * offset).Position.Y - O.Position.Y - 0.6, 0.15, CF((O * offset).Position.X, O.Position.Y, (O * offset).Position.Z), STEEL, M.Metal)
	local text = string.format("%s\nLv.%d  %s\nCondition %d%%", title:upper(), lv, levelName, math.floor(cond))
	surfaceText(p, Enum.NormalId.Front, text, elite and GOLD or Color3.new(1, 1, 1), BLACK, 60)
	surfaceText(p, Enum.NormalId.Back, text, elite and GOLD or Color3.new(1, 1, 1), BLACK, 60)
	return p
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local RED = rgb(190, 30, 35)
local BLUE = rgb(30, 70, 170)
local YELLOW = rgb(240, 200, 40)
local GREEN = rgb(40, 140, 70)
local IRON = rgb(52, 52, 58)
local RUBBER = rgb(36, 36, 40)
local TAPE = rgb(170, 172, 178)
local NEONBLUE = rgb(40, 170, 255)
local DARK = rgb(14, 14, 18)
local KNURL = rgb(118, 120, 126)
local CHAMP = rgb(205, 165, 60) -- champagne-gold frames on elite gear
local FOAM = rgb(30, 30, 34)

-- an up vector for CFrame.lookAt that is never parallel to the direction
local function upFor(dir)
	return math.abs(dir.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
end

-- block stretched between two world points (its local Y runs along a..b)
local function beam(model, name, a, b, w, d, color, material, opts)
	local dir = b - a
	return part(model, name, V3(w, dir.Magnitude, d or w), CFrame.lookAt((a + b) / 2, b, upFor(dir)) * ANG(RAD(90), 0, 0), color, material, opts)
end

-- cylinder stretched between two world points (hoses, cords, rods)
local function rod(model, name, a, b, d, color, material, opts)
	local dir = b - a
	return cyl(model, name, dir.Magnitude, d, CFrame.lookAt((a + b) / 2, b, upFor(dir)) * ANG(0, RAD(90), 0), color, material, opts)
end

-- small text label on one face (transparent background); x, y, w, h are fractions of the face
local function tag(p, face, text, fg, w, h, x, y)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.6
	sg.MaxDistance = 90
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(x or 0.5, y or 0.5)
	t.Size = UDim2.fromScale(w or 0.9, h or 0.8)
	t.BackgroundTransparency = 1
	t.TextColor3 = fg
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.Parent = sg
	sg.Parent = p
	return t
end

-- evenly spaced holes / tick marks painted on one face (no extra parts). Sizes are in studs;
-- marks run from `from` to `to` (fractions of the face) top to bottom, or left to right if `across`
local function marks(p, face, n, color, sw, sh, from, to, across)
	local ppu = 25
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu
	sg.LightInfluence = 1
	sg.MaxDistance = 70
	for i = 1, n do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		local t = from + (to - from) * (i - 0.5) / n
		f.Position = across and UDim2.fromScale(t, 0.5) or UDim2.fromScale(0.5, t)
		f.Size = UDim2.fromOffset(sw * ppu, sh * ppu)
		f.Parent = sg
	end
	sg.Parent = p
	return sg
end

-- chain of alternating links between two world points (links go into `group` when given)
local function chain(model, a, b, n, color, w, group)
	local dir = b - a
	local up = upFor(dir)
	local seg = dir.Magnitude / n
	for i = 1, n do
		local c = a + dir * ((i - 0.5) / n)
		local p = part(model, "ChainLink", V3(w or 0.18, seg * 1.3, 0.05), CFrame.lookAt(c, b, up) * ANG(RAD(90), (i % 2) * math.pi / 2, 0), color, M.Metal)
		if group then
			table.insert(group, p)
		end
	end
end

-- weight plate on an axis along local X of cf (bar, horn or peg): disc, optional steel hub,
-- optional weight number near the rim of its +X face
local function weightPlate(model, cf, d, t, color, mat, hub, label, labelColor)
	local p = cyl(model, "Plate", t, d, cf, color, mat or M.SmoothPlastic)
	if hub then
		cyl(model, "PlateHub", t + 0.03, math.min(0.6, d * 0.4), cf, hub, M.Metal)
	end
	if label then
		tag(p, Enum.NormalId.Right, label, labelColor or WHITE, 0.42, 0.15, 0.5, 0.17)
	end
	return p
end

-- Olympic bar along local X of c (its centre): shaft, knurling, sleeves with collars, plates
-- loaded from the inside out and clips. plates = list of { d, t, c, mat, hub, label, lc } for the
-- +X side (the side the station camera sees; only those get weight labels); left = optional
-- different load for the -X side (mismatched junk plates)
local function olympicBar(model, c, len, lv, plates, left, bent)
	local steel = lv >= 3 and CHROME or STEEL
	local sleeve = 1.05
	local inner = len / 2 - sleeve
	if bent then
		-- a bar bent in the middle: two shaft halves meeting a little low
		for _, s in ipairs({ -1, 1 }) do
			rod(model, "Bar", (c * CF(s * (inner + 0.05), 0, 0)).Position, (c * CF(0, -0.1, 0)).Position, 0.2, wear(steel, 0, 0.5), M.Metal)
		end
	else
		cyl(model, "Bar", inner * 2 + 0.1, 0.2, c, steel, M.Metal, { reflect = lv >= 3 and 0.15 or 0 })
	end
	local kl = inner - 0.8
	for _, s in ipairs({ -1, 1 }) do
		if not bent then
			cyl(model, "Knurl", kl, 0.215, c * CF(s * (0.42 + kl / 2), 0, 0), KNURL, M.DiamondPlate)
		end
		cyl(model, "Sleeve", sleeve, 0.3, c * CF(s * (inner + sleeve / 2), 0, 0), lv == 1 and wear(steel, 0, 0.6) or steel, M.Metal, { reflect = lv >= 3 and 0.2 or 0 })
		cyl(model, "BarCollar", 0.09, 0.44, c * CF(s * inner, 0, 0), lv == 1 and RUST or steel, M.Metal)
		local list = (s < 0 and left) or plates
		local x = inner + 0.06
		for _, pl in ipairs(list) do
			x += pl.t / 2
			weightPlate(model, c * CF(s * x, 0, 0), pl.d, pl.t, pl.c, pl.mat, pl.hub, s > 0 and pl.label or nil, pl.lc)
			x += pl.t / 2 + 0.015
		end
		if #list > 0 then
			cyl(model, "Clip", 0.14, 0.38, c * CF(s * (x + 0.07), 0, 0), lv >= 3 and DARK or STEEL, M.Metal)
			if lv >= 3 then
				part(model, "ClipLever", V3(0.1, 0.32, 0.1), c * CF(s * (x + 0.07), 0.3, 0), lv >= 4 and RED or BLUE, M.SmoothPlastic)
			end
		end
	end
end

-- dents, tape, a tear and stuffing on the side of the bag you hit (+Z, facing the boxer)
local function bagWear(model, bagCF, radius, length, cond, rng, group)
	local n = 0
	if cond < 75 then
		n = 2
	end
	if cond < 50 then
		n = 4
	end
	for i = 1, n do
		local a = rng:NextNumber(-1.1, 1.1)
		local y = rng:NextNumber(-length * 0.35, length * 0.35)
		local cf = bagCF * CF(0, y, 0) * ANG(0, a, 0) * CF(0, 0, radius - 0.02)
		table.insert(group, part(model, "Dent", V3(rng:NextNumber(0.5, 0.9), rng:NextNumber(0.5, 0.9), 0.06), cf, Color3.fromRGB(20, 20, 20), M.SmoothPlastic, { transparency = 0.55, ellipsoid = true }))
		if i % 2 == 0 then
			table.insert(group, part(model, "DuctTape", V3(0.75, 0.32, 0.05), bagCF * CF(0, y + 0.5, 0) * ANG(0, a + 0.3, 0) * CF(0, 0, radius + 0.01), TAPE, M.Foil))
		end
	end
	if cond < 30 then
		local cf = bagCF * CF(0, length * 0.1, 0) * ANG(0, -0.2, 0) * CF(0, 0, radius)
		table.insert(group, part(model, "Tear", V3(0.12, length * 0.3, 0.08), cf, Color3.fromRGB(10, 8, 6), M.SmoothPlastic))
		for k = 1, 3 do
			table.insert(group, part(model, "Stuffing", V3(0.18, 0.18, 0.18), cf * CF(0, (k - 2) * 0.35, 0.05), Color3.fromRGB(230, 225, 210), M.Fabric, { ellipsoid = true }))
		end
	end
end

-- floor scuffs / sweat marks (flat translucent ovals) scattered in a box around (x, z)
local function scuffs(model, O, n, x, z, w, d, y, rng)
	for _ = 1, n do
		part(model, "Scuff", V3(rng:NextNumber(0.6, 1.3), 0.01, rng:NextNumber(0.25, 0.55)), O * CF(x + rng:NextNumber(-w, w), y, z + rng:NextNumber(-d, d)) * ANG(0, rng:NextNumber(0, math.pi), 0), Color3.fromRGB(12, 12, 14), M.SmoothPlastic, { transparency = 0.7, ellipsoid = true, shadow = false })
	end
end

-- water bottle standing at cf (base)
local function bottle(model, cf, color, h)
	h = h or 0.9
	vcyl(model, "Bottle", h, 0.36, cf, color, M.SmoothPlastic)
	vcyl(model, "BottleCap", 0.18, 0.22, cf * CF(0, h, 0), BLACK, M.SmoothPlastic)
end

-- folded / draped towel (block) at cf
local function towel(model, cf, color, w, d)
	return part(model, "Towel", V3(w or 1.4, 0.12, d or 0.9), cf, color or WHITE, M.Fabric)
end

------------------------------------------------------------------------
-- Hanging-bag physics (heavy bag station and the members' bags)
------------------------------------------------------------------------
-- A real pendulum about the hook: angular acceleration -(g / L) * sin(angle) on two axes, with
-- g = real gravity at 0.28 m per stud so a bag on a short chain swings with a heavy bag's ~2.4 s
-- period and the members' long-chain bags sway slowly. Plus a torsional twist about the chain,
-- a bob on the shock spring, per-segment dents and a stand shake. Masses differ per level: the
-- old canvas bag flies around, the champion bag barely moves.
local SEGS = 5
local G = 35 -- studs / s^2
local TWIST_K, TWIST_C = 6, 1.6 -- chain / swivel torsion spring and its damping
local DENT_W = 28 -- dent spring: angular frequency and damping (zeta ~0.35)
local DENT_W2, DENT_C = DENT_W * DENT_W, 2 * 0.35 * DENT_W
-- the stand pieces near the hook that shake on a hit
local STAND_SHAKE = { StandArm = true, ArmCap = true, ArmBrace = true, MountPlate = true, Bolt = true, EyeShank = true, EyeBolt = true }

-- how each punch moves the bag: forward swing, sideways push and twist (both x hand side) and the
-- shock-spring bob (uppercuts lift it, overhands drive it down)
local SWING = { jab = 1, cross = 1.05, leadhook = 0.55, rearhook = 0.6, uppercut = 0.4, overhand = 0.95 }
local LATERAL = { jab = 0.05, cross = 0.05, leadhook = -0.55, rearhook = -0.55, uppercut = 0, overhand = -0.2 }
local TWIST = { jab = 0.3, cross = 0.35, leadhook = -0.95, rearhook = -1.0, uppercut = 0.12, overhand = -0.5 }
local BOB = { uppercut = 1, overhand = -0.45 }
-- where on the bag a punch lands (segment 1 = bottom .. 5 = top)
local function dentSegment(ptype, zone)
	if zone == "body" then
		return ptype == "uppercut" and 3 or 2
	end
	return ptype == "uppercut" and 3 or 4
end

-- hook: CFrame of the pivot; group: every part that swings; o = { L, mass, bagCF, len, segL, radius,
-- topDepth, springParts, spring, bulges, standParts, standGain, material, fx, damp }
local function newPendulum(hook, group, o)
	local d = {
		kind = "pendulum", hook = hook, parts = {}, rels = {}, segOf = {}, twistW = {}, bobW = {},
		L = o.L or 5, mass = o.mass or 1, damp = o.damp or 0.42, ax = 0, az = 0, vx = 0, vz = 0, yaw = 0, vyaw = 0, bob = 0, vbob = 0,
		segs = {}, segDir = V3(0, 0, -1), dentSeg = 3, bulges = o.bulges or {}, fx = o.fx, material = o.material or "leather",
		hits = 0, shake = 0, shakeT = 0, shakeDir = V3(0, 0, -1), standGain = o.standGain or 1, spring = o.spring == true,
		len = o.len, segL = o.segL, radius = o.radius or 1, lastSign = 0, chainAt = 0, settled = true,
	}
	for i = 1, SEGS do
		d.segs[i] = { off = 0, v = 0 }
	end
	local topDepth = o.topDepth or 2.45
	local springParts = o.springParts or {}
	local bagCF = o.bagCF
	d.bagRel = bagCF and hook:ToObjectSpace(bagCF) or CF(0, -d.L, 0)
	d.home = bagCF and bagCF.Position or (hook * CF(0, -d.L, 0)).Position
	for _, p in ipairs(group) do
		local rel = hook:ToObjectSpace(p.CFrame)
		local depth = -rel.Position.Y
		local seg, tw, bw = 0, 1, 1
		if depth < topDepth then
			-- chain between the hook and the top of the bag: winds up progressively, never dents
			tw = math.clamp(depth / topDepth, 0, 1)
		elseif bagCF and o.len and o.segL then
			local ly = bagCF:PointToObjectSpace(p.Position).Y
			if ly < -o.len / 2 - 0.25 then
				seg = 1
			elseif ly <= o.len / 2 + 0.25 then
				seg = math.clamp(math.floor((ly + o.len / 2) / o.segL) + 1, 1, SEGS)
			else
				seg = SEGS
			end
		end
		if d.spring then
			-- only what hangs below the shock spring bobs; the coils squash progressively
			bw = springParts[p] or (depth >= 1.2 and 1 or 0)
		end
		table.insert(d.parts, p)
		table.insert(d.rels, rel)
		table.insert(d.segOf, seg)
		table.insert(d.twistW, tw)
		table.insert(d.bobW, bw)
	end
	d.standParts, d.standBase = {}, {}
	for _, p in ipairs(o.standParts or {}) do
		table.insert(d.standParts, p)
		table.insert(d.standBase, p.CFrame)
	end
	return d
end


-- advance one bag by dt and queue its parts' CFrames for one BulkMoveTo
local function stepPendulum(d, dt, now, bulkP, bulkC)
	local w2 = G / d.L
	local damp = math.exp(-dt * d.damp)
	d.vx = (d.vx - w2 * math.sin(d.ax) * dt) * damp
	d.vz = (d.vz - w2 * math.sin(d.az) * dt) * damp
	d.ax = math.clamp(d.ax + d.vx * dt, -0.7, 0.7)
	d.az = math.clamp(d.az + d.vz * dt, -0.7, 0.7)
	d.vyaw = (d.vyaw - TWIST_K * d.yaw * dt) * math.exp(-dt * TWIST_C)
	d.yaw = math.clamp(d.yaw + d.vyaw * dt, -1.3, 1.3)
	if d.spring then
		d.vbob = (d.vbob - 170 * d.bob * dt) * math.exp(-dt * 7)
		d.bob = math.clamp(d.bob + d.vbob * dt, -0.22, 0.22)
	end
	-- chain jingle when the swing turns around with some speed behind it
	local sign = d.vx > 0.02 and 1 or (d.vx < -0.02 and -1 or 0)
	if sign ~= 0 and sign ~= d.lastSign then
		if d.lastSign ~= 0 and math.abs(d.ax) > 0.045 and now - d.chainAt > 0.4 then
			d.chainAt = now
			GymSound.Play("chain", d.hook.Position - V3(0, 1, 0), { volume = math.clamp(math.abs(d.ax) * 8, 0.3, 1.2) })
		end
		d.lastSign = sign
	end
	-- dents: stiff, so sub-stepped
	local denting = false
	if d.dentT then
		if now - d.dentT < 1.4 then
			local n = math.max(1, math.ceil(dt * 240))
			local h = dt / n
			for _ = 1, n do
				for _, s in ipairs(d.segs) do
					s.v += (-DENT_W2 * s.off - DENT_C * s.v) * h
					s.off += s.v * h
				end
			end
		else
			for _, s in ipairs(d.segs) do
				s.off, s.v = 0, 0
			end
			d.dentT = nil
		end
		denting = true
	end
	-- stand shake (the hook rides on the arm, so the bag shakes with it)
	local shakeOff = Vector3.zero
	if d.shake > 0 then
		local el = now - d.shakeT
		local amp = d.shake * math.exp(-el * 8)
		if amp < 0.0015 then
			d.shake = 0
		else
			shakeOff = d.shakeDir * (amp * math.sin(el * 70))
		end
		for i, p in ipairs(d.standParts) do
			table.insert(bulkP, p)
			table.insert(bulkC, d.standBase[i] + shakeOff)
		end
	end
	local moving = math.abs(d.ax) + math.abs(d.az) + math.abs(d.vx) + math.abs(d.vz) + math.abs(d.yaw) + math.abs(d.vyaw) + math.abs(d.bob) + math.abs(d.vbob) > 0.0015
	if not (moving or denting or d.shake > 0) then
		if d.settled then
			return
		end
		d.settled = true -- one last write puts everything exactly home
	else
		d.settled = false
	end
	local base = (d.hook + shakeOff) * CFrame.Angles(d.ax, 0, d.az)
	for i, p in ipairs(d.parts) do
		local cf = base
		local seg = d.segOf[i]
		if seg > 0 then
			local off = d.segs[seg].off
			if off ~= 0 then
				cf = cf * CF(d.segDir * off)
			end
		end
		local tw = d.twistW[i] * d.yaw
		if tw ~= 0 then
			cf = cf * CFrame.Angles(0, tw, 0)
		end
		local by = d.bobW[i] * d.bob
		if by ~= 0 then
			cf = cf * CF(0, by, 0)
		end
		table.insert(bulkP, p)
		table.insert(bulkC, cf * d.rels[i])
	end
	-- side bulges ride on the dented segment and swell while it is compressed
	if #d.bulges > 0 and d.segL then
		local s = d.segs[d.dentSeg]
		local amt = math.clamp(math.abs(s and s.off or 0) / 0.12, 0, 1)
		local segY = -d.len / 2 + (d.dentSeg - 0.5) * d.segL
		local twisted = base * CF(d.segDir * (s and s.off or 0) * 0.5) * CFrame.Angles(0, d.yaw, 0) * CF(0, d.bob, 0) * d.bagRel
		for _, b in ipairs(d.bulges) do
			b.mesh.Scale = V3(0.6 + amt * 1.25, 1 - amt * 0.08, 1 + amt * 0.1)
			table.insert(bulkP, b.part)
			table.insert(bulkC, twisted * CF(b.side * (d.radius - 0.22), segY, 0))
		end
	end
end

-- a punch lands on a hanging bag. power 0..1.5 (negative = toward the boxer), side -1 L / 1 R
local function hitPendulum(d, power, side, ptype, zone, opts)
	local p = math.abs(power)
	local dir = power < 0 and -1 or 1
	local zoneMul = zone == "body" and 0.85 or 1
	-- a punch gives the bag ~0.5 m/s (1.8 studs/s) at full power; as an angular velocity that is
	-- v / L, so a long-chain bag moves further but slower, like the real thing
	local k = 1.8 * p / d.mass / d.L
	ptype = SWING[ptype] and ptype or "cross"
	d.vx += k * SWING[ptype] * zoneMul * dir
	d.vz += k * LATERAL[ptype] * side
	d.vyaw += 0.75 * p / d.mass * TWIST[ptype] * side
	if d.spring then
		d.vbob += (BOB[ptype] or 0.12) * p * 1.7
	end
	d.settled = false
	local now = os.clock()
	-- dent: the hit segment is shoved in, the neighbours follow a little
	if d.segL then
		local seg = dentSegment(ptype, zone)
		local soft = d.material == "canvas" and 1.3 or (d.material == "smart" and 0.9 or 1)
		local amp = math.min(0.2, 0.12 * p * soft)
		local lateral = (LATERAL[ptype] or 0) * side
		d.segDir = V3(-lateral * 1.1, 0, -1).Unit * dir
		d.dentSeg = seg
		for i, s in ipairs(d.segs) do
			local f = i == seg and 1 or (math.abs(i - seg) == 1 and 0.35 or 0)
			if f > 0 then
				s.off = s.off * 0.3 + amp * f
				s.v = 0
			end
		end
		d.dentT = now
	end
	-- the stand rocks
	d.shake = math.min(0.08, d.shake * 0.5 + 0.022 * p * d.standGain)
	d.shakeT = now
	d.shakeDir = V3(LATERAL[ptype] * side * 0.5, 0, -1).Unit * dir
	-- sound: the material of the bag, deeper for body shots; smart bags add a sensor ping
	local segY = d.segL and (-d.len / 2 + (dentSegment(ptype, zone) - 0.5) * d.segL) or 0
	-- face: which side of the bag the glove met (+1 = the rig's +Z face, where a station's boxer
	-- stands; a members' bag can be worked from either side, see onAutoAct)
	local face = opts and opts.face or 1
	local hitPos = (d.hook * d.bagRel * CF(0, segY, d.radius * face)).Position
	local vol = (0.55 + p * 0.45) * (opts and opts.remote and 0.6 or 1)
	local prof = zone == "body" and "bag_body"
		or ({ canvas = "bag_canvas", leather = "bag_leather", premium = "bag_premium", smart = "bag_leather" })[d.material] or "bag_leather"
	GymSound.Play(prof, hitPos, { volume = vol, speed = 1 - math.clamp(d.mass - 1, 0, 0.4) * 0.15 })
	if zone == "body" and d.material ~= "canvas" then
		GymSound.Play(d.material == "premium" and "bag_premium" or "bag_leather", hitPos, { volume = vol * 0.35, speed = 1.15 })
	end
	if d.material == "smart" then
		task.delay(0.09, function()
			GymSound.Play("bag_smartping", hitPos, { volume = opts and opts.remote and 0.5 or 1 })
		end)
	end
	if p > 0.95 and now - d.chainAt > 0.3 then
		d.chainAt = now
		GymSound.Play("chain", d.hook.Position - V3(0, 0.8, 0), { volume = 0.8 + p * 0.3 })
	end
	-- dust / sweat burst off the face that was hit
	local fx = d.fx
	if fx and fx.att and fx.att.Parent then
		pcall(function()
			-- the emitters fire out of the attachment's +Z (NormalId.Back): turn them to the hit face
			fx.att.WorldCFrame = face < 0 and CF(hitPos) * CFrame.Angles(0, math.pi, 0) or CF(hitPos)
			if fx.dust then
				fx.dust:Emit(math.floor(2 + p * 5))
			end
			if fx.spray and (opts and opts.sweat or 0) > 0.25 then
				fx.spray:Emit(math.floor(1 + p * 3 * (opts.sweat or 0)))
			end
		end)
	end
end

-- the burst emitters a hanging bag throws on a hit (never enabled: hitPendulum Emit()s them).
-- dust off the bag face, sweat spray off the glove; the attachment is moved to the hit point.
local function impactFX(parent, dustColor)
	local fxAtt = Instance.new("Attachment")
	fxAtt.Name = "ImpactFX"
	fxAtt.Parent = parent
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Enabled = false
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(dustColor)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
	dust.Lifetime = NumberRange.new(0.6, 1.3)
	dust.Speed = NumberRange.new(1, 2.4)
	dust.SpreadAngle = Vector2.new(40, 40)
	dust.Acceleration = V3(0, -0.6, 0)
	dust.Drag = 3
	dust.LightInfluence = 1
	dust.EmissionDirection = Enum.NormalId.Back
	dust.Parent = fxAtt
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Enabled = false
	spray.Color = ColorSequence.new(rgb(200, 225, 240))
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Size = NumberSequence.new(0.06)
	spray.Lifetime = NumberRange.new(0.3, 0.55)
	spray.Speed = NumberRange.new(4, 7)
	spray.SpreadAngle = Vector2.new(30, 30)
	spray.Acceleration = V3(0, -40, 0)
	spray.LightEmission = 0.2
	spray.LightInfluence = 1
	spray.EmissionDirection = Enum.NormalId.Back
	spray.Parent = fxAtt
	return fxAtt, dust, spray
end

------------------------------------------------------------------------
-- builders: B[id](model, O, level, cond, rng, ctx) -> dynamic state (optional)
------------------------------------------------------------------------
local B = {}

B.heavybag = function(m, O, lv, cond, rng)
	local styles = {
		{ color = rgb(150, 135, 105), mat = M.Fabric, cap = rgb(118, 102, 76), rim = rgb(105, 90, 66), seam = rgb(92, 78, 56), chain = RUST, d = 2.2 },
		{ color = rgb(32, 32, 36), mat = M.Leather, cap = rgb(22, 22, 26), rim = rgb(60, 60, 66), seam = rgb(64, 64, 70), chain = STEEL, d = 2.3, band = WHITE, patch = "WCB", patchC = rgb(22, 22, 26), patchT = WHITE },
		{ color = rgb(110, 60, 35), mat = M.Leather, cap = rgb(72, 40, 24), rim = rgb(60, 32, 18), seam = rgb(58, 30, 16), chain = STEEL, d = 2.35, band = rgb(72, 40, 24), patch = "WCB\nPRO", patchC = rgb(60, 32, 18), patchT = GOLD },
		{ color = rgb(150, 20, 25), mat = M.Leather, cap = rgb(20, 20, 24), rim = GOLD, seam = rgb(95, 10, 14), chain = CHROME, d = 2.4, band = GOLD, patch = "WCB\nELITE", patchC = rgb(20, 20, 24), patchT = GOLD },
		{ color = rgb(18, 18, 22), mat = M.SmoothPlastic, cap = rgb(30, 30, 36), rim = NEONBLUE, rimMat = M.Neon, seam = rgb(52, 52, 60), chain = CHROME, d = 2.4, patch = "SMART\nIMPACT", patchC = rgb(10, 12, 16), patchT = NEONBLUE },
		{ color = WHITE, mat = M.Leather, cap = GOLD, capMat = M.Metal, rim = GOLD, rimMat = M.Metal, seam = rgb(205, 205, 210), chain = GOLD, d = 2.5, band = GOLD, patch = "♛\nCHAMPION", patchC = rgb(20, 20, 24), patchT = GOLD },
	}
	local st = styles[math.clamp(lv, 1, #styles)]
	local frame = ({ RUST, BLACK, BLACK, BLACK, rgb(40, 42, 48), CHAMP })[lv] or BLACK
	local trim = ({ RUST, STEEL, RED, GOLD, NEONBLUE, DARK })[lv] or STEEL
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- floor: rubber mat with a contrasting border, scuffed where you move (bare floor on L1)
	if lv == 1 then
		part(m, "OldCarpet", V3(4.4, 0.04, 3.2), at(0.3, 0.02, 3.4) * ANG(0, RAD(4), 0), wear(rgb(100, 62, 55), cond, 0.5), M.Fabric)
		for _, a in ipairs({ 35, -35 }) do
			part(m, "TapeX", V3(0.25, 0.05, 1.0), at(-0.6, 0.03, 3.6) * ANG(0, RAD(a), 0), TAPE, M.Foil)
		end
		scuffs(m, O, 3, 0, 3.4, 1.2, 0.9, 0.045, rng)
	else
		if lv >= 3 then
			part(m, "MatBorder", V3(7.3, 0.05, 10.8), at(0, 0.025, -0.25), lv >= 6 and GOLD or trim, M.SmoothPlastic)
		end
		part(m, "FloorMat", V3(7, 0.06, 10.5), at(0, 0.03, -0.25), wear(lv >= 5 and rgb(24, 26, 32) or RUBBER, cond, 0.25), M.Rubber)
		scuffs(m, O, 1 + math.floor((100 - cond) / 25), 0, 3.4, 1.4, 1.0, 0.065, rng)
		if lv >= 4 then
			local logo = part(m, "MatLogo", V3(3.2, 0.02, 1.4), at(0, 0.07, 1.9), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			surfaceText(logo, Enum.NormalId.Top, lv >= 6 and "CHAMPION" or "WCB", GOLD, nil, 40)
		end
	end
	-- stand: H-frame base, square post with welded gussets, braced arm over the bag
	local pz = -3.3
	part(m, "StandPost", V3(0.6, 10.55, 0.6), at(0, 5.575, pz), frame, M.Metal, { collide = true })
	part(m, "BaseCross", V3(3.6, 0.3, 0.6), at(0, 0.15, pz), frame, M.Metal, { collide = true })
	for _, x in ipairs({ -1.6, 1.6 }) do
		part(m, "BaseRail", V3(0.4, 0.3, 4.0), at(x, 0.15, pz), frame, M.Metal, { collide = true })
		if lv >= 2 then
			for _, s in ipairs({ -1, 1 }) do
				part(m, "EndCap", V3(0.42, 0.32, 0.06), at(x, 0.15, pz + s * 2.0), BLACK, M.SmoothPlastic)
			end
		end
	end
	for k = 0, 3 do
		part(m, "Gusset", V3(0.1, 0.9, 0.9), at(0, 0.75, pz) * ANG(0, k * math.pi / 2, 0) * CF(0, 0, -0.75), frame, M.Metal, { wedge = true })
	end
	if lv == 1 then
		-- old sandbags thrown on the base to stop it walking, tape holding the post together
		part(m, "Sandbag", V3(3.4, 0.7, 1.1), at(0, 0.6, pz - 1.2) * ANG(0, RAD(3), 0), wear(rgb(112, 102, 72), cond, 0.4), M.Fabric, { ellipsoid = true })
		part(m, "Sandbag", V3(1.2, 0.6, 1.0), at(-1.6, 0.55, pz + 1.3) * ANG(0, RAD(-20), RAD(6)), wear(rgb(96, 104, 78), cond, 0.4), M.Fabric, { ellipsoid = true })
		cyl(m, "PostTape", 0.5, 0.66, at(0, 4.2, pz) * ANG(RAD(4), 0, RAD(90)), TAPE, M.Foil)
	else
		-- rear weight horns loaded with plates
		local hz = pz - 1.6
		cyl(m, "WeightHorn", 4.6, 0.26, at(0, 0.78, hz), frame, M.Metal)
		for _, x in ipairs({ -1.6, 1.6 }) do
			part(m, "HornBracket", V3(0.4, 0.5, 0.3), at(x, 0.55, hz), frame, M.Metal)
		end
		local pc = ({ IRON, IRON, IRON, RUBBER, rgb(28, 30, 38), GOLD })[lv] or IRON
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, (lv >= 3 and 2 or 1) do
				weightPlate(m, at(s * (1.95 + (i - 1) * 0.22), 0.78, hz), 1.5 - (i - 1) * 0.25, 0.2, pc, lv == 6 and M.Metal or M.SmoothPlastic, lv >= 4 and CHROME or nil)
			end
		end
	end
	local arm = part(m, "StandArm", V3(0.5, 0.5, 4.05), at(0, 10.6, -1.575), frame, M.Metal)
	part(m, "ArmCap", V3(0.52, 0.52, 0.05), at(0, 10.6, 0.47), lv == 1 and RUST or BLACK, M.SmoothPlastic)
	beam(m, "ArmBrace", o + V3(0, 8.3, pz + 0.3), o + V3(0, 10.38, -1.6), 0.26, 0.26, frame, M.Metal)
	if lv >= 3 then
		tag(arm, Enum.NormalId.Right, ({ "", "", "PRO", "ELITE", "SMART", "CHAMPION" })[lv] or "", trim, 0.9, 0.7)
		tag(arm, Enum.NormalId.Left, ({ "", "", "PRO", "ELITE", "SMART", "CHAMPION" })[lv] or "", trim, 0.9, 0.7)
	end
	-- ceiling-style mount under the arm end: plate, bolts and an eye bolt for the hook
	part(m, "MountPlate", V3(0.8, 0.1, 0.8), at(0, 10.3, 0), lv == 1 and RUST or STEEL, M.Metal)
	if lv >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				vcyl(m, "Bolt", 0.06, 0.11, at(sx * 0.28, 10.19, sz * 0.28), CHROME, M.Metal)
			end
		end
	end
	vcyl(m, "EyeShank", 0.12, 0.08, at(0, 10.13, 0), STEEL, M.Metal)
	cyl(m, "EyeBolt", 0.05, 0.2, at(0, 10.07, 0) * ANG(0, RAD(90), 0), lv == 1 and RUST or STEEL, M.Metal)

	-- the stand's top pieces shake a little on every hit (the hook rides on them)
	local standParts = {}
	for _, p in ipairs(m:GetChildren()) do
		if STAND_SHAKE[p.Name] and p:IsA("BasePart") then
			table.insert(standParts, p)
		end
	end

	-- everything below the hook swings with the bag. The bag body is five stacked segments so a
	-- punch can dent it: the hit segment is shoved in and springs back, its neighbours follow,
	-- and two hidden side bulges push out while it is compressed
	local hook = at(0, 10.05, 0)
	local group = {}
	local function g(p)
		table.insert(group, p)
		return p
	end
	local function H(x, y, z)
		return hook * CF(x, y, z)
	end
	local chainC = st.chain
	g(cyl(m, "Shackle", 0.05, 0.22, H(0, -0.06, 0), chainC, M.Metal))
	g(vcyl(m, "Swivel", 0.3, 0.2, H(0, -0.42, 0), chainC, M.Metal))
	local springParts = {}
	if lv >= 3 then
		-- shock spring between the swivel and the spreader chains (compresses on uppercuts)
		g(vcyl(m, "SpringCore", 0.78, 0.07, H(0, -1.18, 0), STEEL, M.Metal))
		for k = 0, 4 do
			local coil = g(cyl(m, "SpringCoil", 0.045, 0.34, H(0, -0.5 - k * 0.15, 0) * ANG(RAD(k % 2 == 0 and 9 or -9), 0, RAD(90)), chainC, M.Metal))
			springParts[coil] = k / 4
		end
	else
		chain(m, H(0, -0.42, 0).Position, H(0, -1.0, 0).Position, 2, chainC, 0.18, group)
	end
	local ringY = -1.2
	g(cyl(m, "MasterRing", 0.07, 0.42, H(0, ringY, 0) * ANG(0, RAD(90), 0), chainC, M.Metal))
	g(cyl(m, "RingEye", 0.09, 0.24, H(0, ringY, 0) * ANG(0, RAD(90), 0), DARK, M.SmoothPlastic))
	local r = st.d / 2
	local len = 5
	local a = r * 0.55 / math.sqrt(2)
	local capTop = -2.26
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			chain(m, H(0, ringY - 0.17, 0).Position, H(sx * a, capTop + 0.04, sz * a).Position, 3, chainC, 0.16, group)
			if lv >= 2 then
				g(part(m, "DRing", V3(0.2, 0.14, 0.05), H(sx * a, capTop + 0.06, sz * a) * ANG(0, math.atan2(sx, sz), 0), chainC, M.Metal))
			end
		end
	end
	local bagCF = H(0, -2.45 - len / 2, 0)
	local up = ANG(0, 0, RAD(90))
	local segL = len / SEGS
	local bagColor = wear(st.color, cond, 0.35)
	local bag
	for s = 1, SEGS do
		local y = -len / 2 + (s - 0.5) * segL
		-- a hair longer than its slot so a dented segment never opens a visible gap
		local seg = g(cyl(m, s == 3 and "Bag" or "BagSeg", segL + 0.05, st.d, bagCF * CF(0, y, 0) * up, bagColor, st.mat))
		if s == 3 then
			bag = seg
		end
	end
	local capMat = st.capMat or (lv == 1 and M.Fabric or M.Leather)
	g(cyl(m, "BagTop", 0.22, st.d * 0.98, bagCF * CF(0, len / 2 + 0.08, 0) * up, st.cap, capMat))
	g(cyl(m, "BagBottom", 0.22, st.d * 0.98, bagCF * CF(0, -len / 2 - 0.08, 0) * up, st.cap, capMat))
	for _, s in ipairs({ -1, 1 }) do
		g(cyl(m, "Piping", 0.08, st.d * 1.03, bagCF * CF(0, s * (len / 2 - 0.02), 0) * up, st.rim, st.rimMat or M.Leather))
	end
	-- vertical seams between the panels (one piece per segment so they dent with it), stitch lines near the caps
	for k = 0, 3 do
		for s = 1, SEGS do
			local y = -len / 2 + (s - 0.5) * segL
			g(part(m, "Seam", V3(0.05, segL - 0.02, 0.05), bagCF * CF(0, y, 0) * ANG(0, RAD(45 + k * 90), 0) * CF(0, 0, r), st.seam, M.Fabric))
		end
	end
	if lv >= 2 then
		for _, s in ipairs({ -1, 1 }) do
			g(cyl(m, "Stitch", 0.04, st.d * 1.008, bagCF * CF(0, s * (len / 2 - 0.32), 0) * up, st.seam, M.Fabric))
		end
	end
	if st.band then
		local bw = lv == 6 and 0.07 or (lv == 4 and 0.18 or 0.3)
		for _, y in ipairs({ 1.55, -1.55 }) do
			g(cyl(m, "Band", bw, st.d * 1.01, bagCF * CF(0, y, 0) * up, st.band, lv >= 4 and M.Metal or M.Leather))
		end
	end
	if st.patch then
		-- brand patch on the side you hit (thick so it sits flush on the curve)
		local patch = g(part(m, "BrandPatch", V3(0.95, 0.62, 0.22), bagCF * CF(0, 0.45, r - 0.08), st.patchC, M.Leather))
		surfaceText(patch, Enum.NormalId.Back, st.patch, st.patchT, st.patchC, 60)
	end
	if lv == 1 then
		-- sagging bottom, sewn-on patches and tape wraps
		g(cyl(m, "Sag", 0.9, st.d * 1.05, bagCF * CF(0, -len / 2 + 0.6, 0) * up, wear(st.color, cond, 0.5), M.Fabric))
		for i = 1, 3 do
			g(part(m, "Patch", V3(0.7, 0.6, 0.06), bagCF * CF(0, -1.2 + i * 0.7, 0) * ANG(0, i * 0.8 - 1.6, 0) * CF(0, 0, r + 0.01), rgb(120, 105, 75), M.Fabric))
		end
		for _, y in ipairs({ 1.2, -0.4 }) do
			g(cyl(m, "TapeWrap", 0.3, st.d * 1.012, bagCF * CF(0, y, 0) * ANG(RAD(4), 0, RAD(90)), TAPE, M.Foil))
		end
	elseif lv == 5 then
		for _, y in ipairs({ -1.6, -0.55, 1.5 }) do
			g(cyl(m, "Sensor", 0.12, st.d * 1.02, bagCF * CF(0, y, 0) * up, NEONBLUE, M.Neon))
		end
	elseif lv >= 6 then
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = GOLD
		sp.Parent = bag
	end
	-- carry handle loop under the bottom cap
	local by = -len / 2 - 0.19
	if lv >= 2 then
		g(part(m, "HandleStrap", V3(0.7, 0.08, 0.16), bagCF * CF(0, by - 0.22, 0), st.cap, capMat))
		for _, sx in ipairs({ -1, 1 }) do
			g(part(m, "HandleLeg", V3(0.08, 0.26, 0.16), bagCF * CF(sx * 0.31, by - 0.1, 0), st.cap, capMat))
		end
	end
	if lv >= 5 then
		-- unclipped bungee for the floor anchor
		g(part(m, "AnchorStrap", V3(0.12, 0.7, 0.04), bagCF * CF(0, by - 0.6, 0), BLACK, M.Fabric))
		g(part(m, "AnchorClip", V3(0.16, 0.22, 0.08), bagCF * CF(0, by - 1.0, 0), CHROME, M.Metal))
		part(m, "FloorAnchor", V3(0.7, 0.05, 0.7), at(0, 0.085, 0), STEEL, M.DiamondPlate)
		cyl(m, "AnchorRing", 0.06, 0.32, at(0, 0.24, 0) * ANG(0, RAD(90), 0), CHROME, M.Metal)
	end
	bagWear(m, bagCF, r, len, cond, rng, group)
	-- the side bulges: hidden inside the bag until a hit squashes the segment they sit at
	local bulges = {}
	for _, sx in ipairs({ -1, 1 }) do
		local b = part(m, "BagBulge", V3(0.5, segL * 0.9, st.d * 0.55), bagCF * CF(sx * (r - 0.22), 0, 0), bagColor, st.mat, { ellipsoid = true, shadow = false })
		local mesh = b:FindFirstChildOfClass("SpecialMesh")
		mesh.Scale = V3(0.6, 1, 1)
		table.insert(bulges, { part = b, mesh = mesh, side = sx })
	end
	-- impact effects: dust from an old canvas bag, sweat spray off any bag (emitted in bursts only)
	local fxAtt, dust, spray = impactFX(bag, lv <= 1 and rgb(200, 182, 150) or rgb(170, 165, 158))
	-- smart impact screen on a side arm (level 5+), angled at the boxer
	local display
	if lv >= 5 then
		local scf = at(-2.6, 6.3, -2.4) * ANG(0, RAD(24), 0)
		beam(m, "ScreenArm", o + V3(-0.3, 6.3, pz), (scf * CF(0, 0, -0.1)).Position, 0.18, 0.18, frame, M.Metal)
		part(m, "ScreenBezel", V3(2.4, 1.5, 0.14), scf, DARK, M.SmoothPlastic)
		local screen = part(m, "SmartScreen", V3(2.2, 1.3, 0.04), scf * CF(0, 0, 0.08), rgb(8, 10, 14), M.SmoothPlastic)
		display = surfaceText(screen, Enum.NormalId.Back, "IMPACT\n-- lbs", rgb(80, 200, 255), rgb(8, 10, 14), 60)
		light(screen, rgb(80, 200, 255), 6, 0.35)
	end
	local dyn = newPendulum(hook, group, {
		L = 2.45 + len / 2, mass = ({ 0.8, 1.0, 1.1, 1.2, 1.25, 1.4 })[lv] or 1, bagCF = bagCF, len = len, segL = segL,
		radius = r, springParts = springParts, spring = lv >= 3, bulges = bulges, standParts = standParts,
		standGain = lv == 1 and 1.6 or 1, material = ({ "canvas", "leather", "leather", "premium", "smart", "premium" })[lv] or "leather",
		fx = { att = fxAtt, dust = lv <= 2 and dust or nil, spray = spray },
	})
	dyn.display = display
	dyn.plaque = O * CF(2.6, 2.4, 1.2)
	return dyn
end

B.speedbag = function(m, O, lv, cond, rng)
	local plat = ({ WOOD, BLACK, BLACK, WHITE })[lv] or WOOD
	local bagC = ({ rgb(120, 75, 45), rgb(170, 25, 30), rgb(25, 25, 28), WHITE })[lv] or rgb(120, 75, 45)
	local laceC = ({ rgb(70, 45, 25), WHITE, GOLD, GOLD })[lv] or WHITE
	local trim = lv >= 3 and GOLD or STEEL
	local frame = ({ WOOD, BLACK, BLACK, rgb(235, 235, 240) })[lv] or BLACK
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local pz = -2.4
	-- post and base
	if lv == 1 then
		part(m, "Post", V3(0.6, 9, 0.6), at(0, 4.5, pz), wear(WOOD, cond, 0.4), M.Wood, { collide = true })
		for _, a in ipairs({ 0, 90 }) do
			part(m, "CrossFoot", V3(2.8, 0.3, 0.5), at(0, 0.15, pz) * ANG(0, RAD(a), 0), wear(WOOD, cond, 0.5), M.Wood, { collide = true })
		end
		part(m, "Brace", V3(0.3, 1.4, 0.3), at(0, 0.9, pz + 0.75) * ANG(RAD(-40), 0, 0), WOOD, M.Wood)
		part(m, "CinderBlock", V3(1.2, 0.6, 0.6), at(0.3, 0.6, pz - 0.9), rgb(140, 140, 135), M.Concrete)
	else
		local post = part(m, "Post", V3(0.5, 8.75, 0.5), at(0, 0.25 + 8.75 / 2, pz), frame, M.Metal, { collide = true })
		part(m, "PostBase", V3(2.6, 0.25, 2.6), at(0, 0.125, pz), BLACK, M.Metal, { collide = true })
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				vcyl(m, "Bolt", 0.08, 0.16, at(sx * 1.05, 0.25, pz + sz * 1.05), CHROME, M.Metal)
			end
		end
		for k = 0, 1 do
			part(m, "Gusset", V3(0.08, 0.8, 0.8), at(0, 0.65, pz) * ANG(0, k * math.pi, 0) * CF(0, 0, -0.65), frame, M.Metal, { wedge = true })
		end
		-- sliding height carriage with an adjuster wheel, height holes below it
		marks(post, Enum.NormalId.Back, 9, DARK, 0.14, 0.14, 0.38, 0.7)
		part(m, "Carriage", V3(0.66, 1.3, 0.66), at(0, 7.25, pz), trim, M.Metal)
		cyl(m, "AdjustWheel", 0.12, 0.5, at(0.4, 7.0, pz), BLACK, M.SmoothPlastic)
		part(m, "WheelHandle", V3(0.08, 0.08, 0.3), at(0.48, 7.0, pz + 0.18), trim, M.Metal)
	end
	-- two arms reaching over the platform, with diagonal braces
	for _, x in ipairs({ -0.6, 0.6 }) do
		part(m, "Arm", V3(0.25, 0.3, 2.35), at(x, 7.62, -0.875), lv == 1 and WOOD or trim, lv == 1 and M.Wood or M.Metal)
		beam(m, "ArmBrace", o + V3(x, 6.65, pz + 0.3), o + V3(x, 7.48, -1.15), 0.18, 0.18, lv == 1 and WOOD or frame, lv == 1 and M.Wood or M.Metal)
	end
	-- rebound platform: board, rim, padded underside
	cyl(m, "Platform", 0.34, 2.95, at(0, 7.3, 0) * ANG(0, 0, RAD(90)), wear(plat, cond, 0.3), lv == 1 and M.Wood or M.SmoothPlastic)
	if lv >= 2 then
		cyl(m, "PlatformRim", 0.32, 3.1, at(0, 7.3, 0) * ANG(0, 0, RAD(90)), trim, M.Metal)
		cyl(m, "ReboundPad", 0.05, 2.4, at(0, 7.105, 0) * ANG(0, 0, RAD(90)), lv >= 3 and rgb(60, 32, 18) or rgb(40, 40, 44), M.Leather)
		if lv >= 3 then
			-- stitched leather board: a thread ring shows between pad and inner panel
			cyl(m, "PadStitch", 0.055, 2.25, at(0, 7.1, 0) * ANG(0, 0, RAD(90)), rgb(230, 220, 200), M.Fabric)
			cyl(m, "PadInner", 0.06, 2.2, at(0, 7.095, 0) * ANG(0, 0, RAD(90)), rgb(60, 32, 18), M.Leather)
		end
	else
		-- plywood edge with nails
		for k = 0, 5 do
			vcyl(m, "Nail", 0.03, 0.07, at(math.cos(k * math.pi / 3) * 1.3, 7.47, math.sin(k * math.pi / 3) * 1.3), rgb(80, 80, 85), M.Metal)
		end
	end
	local plateY = lv >= 2 and 7.06 or 7.11
	part(m, "SwivelPlate", V3(0.5, 0.04, 0.5), at(0, plateY, 0), lv == 1 and RUST or STEEL, M.Metal)
	if lv == 1 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				vcyl(m, "Nail", 0.02, 0.06, at(sx * 0.18, plateY - 0.04, sz * 0.18), rgb(70, 70, 75), M.Metal)
			end
		end
	end
	part(m, "SwivelBall", V3(0.16, 0.16, 0.16), at(0, 7.0, 0), CHROME, M.Metal, { ellipsoid = true })
	if lv >= 4 then
		-- LED edge ring: a neon disc that only shows as a thin line outside the rim
		local led = cyl(m, "LEDRing", 0.06, 3.16, at(0, 7.3, 0) * ANG(0, 0, RAD(90)), rgb(255, 210, 90), M.Neon)
		light(led, rgb(255, 210, 120), 6, 0.45)
		local sign = part(m, "EliteSign", V3(2.0, 0.55, 0.08), at(0, 8.55, pz + 0.29), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, "OLYMPIC GRADE", GOLD, BLACK, 60)
	elseif lv == 3 then
		local sign = part(m, "Badge", V3(1.4, 0.4, 0.06), at(0, 8.55, pz + 0.28), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, "CHAMPIONSHIP", GOLD, BLACK, 60)
	end
	-- bag gloves hanging on a peg
	if lv >= 2 then
		cyl(m, "GlovePeg", 0.4, 0.1, at(0.45, 5.3, pz), STEEL, M.Metal)
		for i, dz in ipairs({ -0.18, 0.2 }) do
			part(m, "BagGlove", V3(0.42, 0.62, 0.36), at(0.62, 4.95 - i * 0.06, pz + dz) * ANG(0, 0, RAD(8)), i == 1 and RED or BLACK, M.Leather, { ellipsoid = true })
		end
		part(m, "Mat", V3(4, 0.05, 3), at(0, 0.025, 2.4), wear(RUBBER, cond, 0.3), M.Rubber)
		scuffs(m, O, 1 + math.floor((100 - cond) / 30), 0, 2.4, 1.0, 0.8, 0.055, rng)
	end
	-- teardrop bag: body, neck, loop, lace and seam all rebound together
	local swivel = at(0, 7.05, 0)
	local rel = {}
	local function b(p)
		rel[p] = swivel:ToObjectSpace(p.CFrame)
		return p
	end
	local bc = wear(bagC, cond, 0.3)
	b(part(m, "SpeedBag", V3(0.78, 1.0, 0.78), at(0, 6.2, 0), bc, M.Leather, { ellipsoid = true }))
	b(part(m, "Neck", V3(0.42, 0.5, 0.42), at(0, 6.72, 0), bc, M.Leather, { ellipsoid = true }))
	b(part(m, "Knot", V3(0.2, 0.22, 0.2), at(0, 6.95, 0), bagC, M.Leather, { ellipsoid = true }))
	b(cyl(m, "BagSeam", 0.03, 0.8, at(0, 6.2, 0) * ANG(0, 0, RAD(90)), laceC, M.Fabric))
	b(part(m, "Lace", V3(0.06, 0.38, 0.05), at(0, 6.55, 0.27) * ANG(RAD(-37), 0, 0), laceC, M.Fabric))
	b(part(m, "LaceTie", V3(0.12, 0.1, 0.08), at(0, 6.72, 0.2), laceC, M.Fabric, { ellipsoid = true }))
	return { kind = "rebound", pivot = swivel, rel = rel, amp = 0, t0 = 0, freq = 9 + lv * 2.5, plaque = O * CF(2.4, 2.4, 0.5) }
end

B.doubleend = function(m, O, lv, cond, rng)
	local bagC = ({ rgb(120, 75, 45), rgb(180, 25, 30), rgb(25, 25, 28), rgb(240, 220, 30) })[lv] or rgb(180, 25, 30)
	local frame = ({ RUST, STEEL, BLACK, BLACK })[lv] or STEEL
	local cordC = ({ rgb(110, 90, 60), BLACK, BLACK, rgb(240, 200, 30) })[lv] or BLACK
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- frame: two posts on feet, crossbar with corner braces
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(m, "FramePost", V3(0.4, 11.15, 0.4), at(x, 5.825, -0.4), frame, M.Metal, { collide = true })
		part(m, "FrameFoot", V3(0.5, 0.25, 2.8), at(x, 0.125, -0.4), frame, M.Metal, { collide = true })
		for k = 0, 1 do
			part(m, "Gusset", V3(0.08, 0.7, 0.7), at(x, 0.6, -0.4) * ANG(0, k * math.pi, 0) * CF(0, 0, -0.55), frame, M.Metal, { wedge = true })
		end
		if lv >= 2 then
			for _, s in ipairs({ -1, 1 }) do
				part(m, "EndCap", V3(0.52, 0.27, 0.05), at(x, 0.125, -0.4 + s * 1.42), BLACK, M.SmoothPlastic)
			end
		end
		local sx = x > 0 and 1 or -1
		beam(m, "CornerBrace", o + V3(sx * 2.45, 9.9, -0.4), o + V3(sx * 1.5, 11.02, -0.4), 0.2, 0.2, frame, M.Metal)
	end
	part(m, "FrameTop", V3(5.6, 0.4, 0.4), at(0, 11.2, -0.4), frame, M.Metal)
	if lv >= 3 then
		local sign = part(m, "FrameSign", V3(2.4, 0.42, 0.06), at(0, 11.2, -0.17), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, lv >= 4 and "LIGHTNING REFLEX" or "PRO REFLEX", lv >= 4 and rgb(240, 220, 30) or WHITE, BLACK, 60)
	end
	-- top rigging: eye plate, adjustable strap with buckle, carabiner
	part(m, "EyePlate", V3(0.4, 0.06, 0.4), at(0, 10.97, -0.4), STEEL, M.Metal)
	part(m, "TopStrap", V3(0.12, 0.84, 0.04), at(0, 10.52, -0.4), lv == 1 and rgb(110, 90, 60) or BLACK, M.Fabric)
	part(m, "Buckle", V3(0.2, 0.14, 0.07), at(0, 10.45, -0.4), lv == 1 and RUST or CHROME, M.Metal)
	part(m, "Carabiner", V3(0.12, 0.3, 0.05), at(0, 9.98, -0.4), lv == 1 and RUST or CHROME, M.Metal)
	-- floor anchor: round plate, bolts, eye, strap, buckle, carabiner
	vcyl(m, "Anchor", 0.12, 1.2, at(0, 0, 0), lv == 1 and RUST or STEEL, M.DiamondPlate)
	if lv >= 2 then
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			vcyl(m, "Bolt", 0.06, 0.14, at(math.cos(a) * 0.45, 0.12, math.sin(a) * 0.45), CHROME, M.Metal)
		end
	end
	cyl(m, "AnchorEye", 0.06, 0.3, at(0, 0.27, 0), STEEL, M.Metal)
	part(m, "BottomStrap", V3(0.12, 0.7, 0.04), at(0, 0.75, 0), lv == 1 and rgb(110, 90, 60) or BLACK, M.Fabric)
	part(m, "Buckle", V3(0.2, 0.14, 0.07), at(0, 0.7, 0), lv == 1 and RUST or CHROME, M.Metal)
	part(m, "Carabiner", V3(0.12, 0.3, 0.05), at(0, 1.18, 0), lv == 1 and RUST or CHROME, M.Metal)
	if lv >= 4 then
		-- LED ring glowing around the floor plate
		vcyl(m, "LEDRing", 0.04, 1.42, at(0, 0.02, 0), rgb(255, 225, 60), M.Neon)
	end
	if lv >= 2 then
		part(m, "Mat", V3(4, 0.05, 3.2), at(0, 0.025, 3.4), wear(RUBBER, cond, 0.3), M.Rubber)
		scuffs(m, O, 1 + math.floor((100 - cond) / 30), 0, 3.4, 1.0, 0.8, 0.055, rng)
	end
	-- the ball, its seam band, cord loops and logo move together on the springs
	local d = lv >= 3 and 0.85 or 1.0
	local home = at(0, 5.7, 0)
	local bag = part(m, "Ball", V3(d, d * 1.15, d), home, wear(bagC, cond, 0.3), M.Leather, { ellipsoid = true })
	local extras = {}
	local function ride(p)
		table.insert(extras, { p, CF(home.Position):ToObjectSpace(p.CFrame) })
		return p
	end
	ride(cyl(m, "BallSeam", 0.035, d * 1.03, home * ANG(0, 0, RAD(90)), lv == 4 and BLACK or wear(rgb(235, 235, 235), cond, 0.4), M.Fabric))
	for _, s in ipairs({ -1, 1 }) do
		ride(part(m, "CordLoop", V3(0.2, 0.18, 0.2), home * CF(0, s * d * 0.58, 0), BLACK, M.Leather, { ellipsoid = true }))
	end
	if lv == 1 then
		ride(part(m, "BallTape", V3(0.34, 0.16, 0.05), home * CF(0.1, -0.15, d / 2 - 0.02) * ANG(0, RAD(15), RAD(20)), TAPE, M.Foil))
	else
		local logo = ride(part(m, "BallLogo", V3(0.34, 0.2, 0.05), home * CF(0, 0.1, d / 2 - 0.015), lv == 4 and BLACK or WHITE, M.SmoothPlastic))
		tag(logo, Enum.NormalId.Back, "WCB", lv == 4 and rgb(240, 220, 30) or BLACK, 0.9, 0.8)
	end
	local top = part(m, "CordTop", V3(0.08, 1, 0.08), home, cordC, M.Fabric)
	local bottom = part(m, "CordBottom", V3(0.08, 1, 0.08), home, cordC, M.Fabric)
	if lv >= 4 then
		light(bag, rgb(255, 230, 60), 6, 0.6)
	end
	return {
		kind = "spring", home = home, bag = bag, top = top, bottom = bottom, d = d, extras = extras, cordW = 0.08,
		topAnchor = (O * CF(0, 9.88, -0.4)).Position, bottomAnchor = (O * CF(0, 1.28, 0)).Position,
		x = 0, z = 0, vx = 0, vz = 0, k = 30 + lv * 14, plaque = O * CF(3.6, 2.4, 0.5),
	}
end

B.mitts = function(m, O, lv, cond, rng)
	local matC = ({ rgb(60, 60, 64), rgb(30, 60, 150), rgb(150, 20, 25), rgb(20, 20, 24), rgb(20, 20, 24) })[lv] or rgb(30, 60, 150)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	if lv == 1 then
		-- taped square on the bare floor, half peeled away, an upturned bucket for a seat
		local tc = wear(rgb(230, 200, 60), cond, 0.4)
		for _, e in ipairs({
			{ -2.25, -3.5, 3.5, 0.25 }, { 2.15, -3.5, 3.7, 0.25 }, { -2.1, 4.5, 3.8, 0.25 }, { 2.4, 4.5, 3.2, 0.25 },
			{ -4, -1.65, 0.25, 3.7 }, { -4, 2.75, 0.25, 3.5 }, { 4, -1.45, 0.25, 4.1 }, { 4, 2.95, 0.25, 3.1 },
		}) do
			part(m, "Tape", V3(e[3], 0.04, e[4]), at(e[1], 0.02, e[2]), tc, M.SmoothPlastic)
		end
		part(m, "PeeledTape", V3(0.25, 0.04, 0.7), at(-0.25, 0.05, -3.2) * ANG(RAD(8), RAD(30), 0), tc, M.SmoothPlastic)
		vcyl(m, "UpturnedBucket", 1.3, 1.0, at(4.8, 0, 1.2), wear(rgb(230, 120, 30), cond, 0.4), M.SmoothPlastic)
		towel(m, at(4.8, 1.36, 1.2) * ANG(0, RAD(20), 0), wear(WHITE, cond, 0.6), 1.0, 0.7)
		vcyl(m, "WaterJug", 0.9, 0.6, at(5.7, 0, 2.2), rgb(200, 215, 230), M.SmoothPlastic)
		scuffs(m, O, 3, 0, 2.5, 2.0, 1.5, 0.005, rng)
	else
		part(m, "Mat", V3(8, 0.08, 8), at(0, 0.04, 0.5), wear(matC, cond, 0.3), M.Rubber)
		-- ring tape boundary and stance marks
		for _, e in ipairs({ { 0, -3.15, 7.3, 0.12 }, { 0, 4.15, 7.3, 0.12 }, { -3.65, 0.5, 0.12, 7.42 }, { 3.65, 0.5, 0.12, 7.42 } }) do
			part(m, "Line", V3(e[3], 0.02, e[4]), at(e[1], 0.085, e[2]), WHITE, M.SmoothPlastic)
		end
		for _, f in ipairs({ { -0.45, 3.4, -12 }, { 0.5, 4.2, 18 } }) do
			part(m, "FootMark", V3(0.45, 0.02, 0.95), at(f[1], 0.087, f[2]) * ANG(0, RAD(f[3]), 0), lv >= 3 and GOLD or WHITE, M.SmoothPlastic)
		end
		scuffs(m, O, 1 + math.floor((100 - cond) / 25), 0, 2.2, 1.5, 1.8, 0.088, rng)
		if lv >= 4 then
			local logo = part(m, "MatLogo", V3(3, 0.02, 3), at(0, 0.09, 0.5), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			surfaceText(logo, Enum.NormalId.Top, "WCB", GOLD, nil, 40)
		end
		-- round timer on a stand with indicator lights (and the bell from level 3)
		local tp = at(-4.4, 0, -4.2)
		part(m, "TimerFoot", V3(1.2, 0.12, 1.2), tp * CF(0, 0.06, 0), BLACK, M.Metal)
		part(m, "TimerPost", V3(0.22, 6.2, 0.22), tp * CF(0, 3.1, 0), BLACK, M.Metal)
		local tcf = tp * CF(0, 6.6, 0) * ANG(0, RAD(34), 0)
		local box = part(m, "Timer", V3(1.9, 1.05, 0.35), tcf, BLACK, M.SmoothPlastic)
		surfaceText(box, Enum.NormalId.Back, "3:00", rgb(255, 60, 50), BLACK, 60)
		part(m, "TimerLight", V3(0.3, 0.14, 0.3), tcf * CF(-0.55, 0.59, 0), rgb(60, 220, 90), M.Neon)
		part(m, "TimerLight", V3(0.3, 0.14, 0.3), tcf * CF(0.55, 0.59, 0), rgb(240, 50, 40), M.Neon)
		if lv >= 3 then
			local bcf = tp * CF(0, 5.0, 0) * ANG(0, RAD(34), 0)
			part(m, "BellPlate", V3(0.6, 0.6, 0.06), bcf * CF(0, 0, 0.14), WOOD, M.Wood)
			part(m, "Bell", V3(0.56, 0.56, 0.3), bcf * CF(0, 0, 0.3), GOLD, M.Metal, { ellipsoid = true, reflect = 0.2 })
			part(m, "Clapper", V3(0.1, 0.1, 0.1), bcf * CF(0.32, -0.25, 0.3), BLACK, M.Metal, { ellipsoid = true })
		end
		-- pad rack: focus mitts on pegs, belly pad and Thai pads at the top levels, bottles on the shelf
		local rk = at(-5.0, 0, -1.2)
		for _, x in ipairs({ -1.2, 1.2 }) do
			part(m, "RackUpright", V3(0.18, 4.6, 0.18), rk * CF(x, 2.3, 0), BLACK, M.Metal)
			part(m, "RackFoot", V3(0.25, 0.14, 1.3), rk * CF(x, 0.07, 0), BLACK, M.Metal)
		end
		part(m, "RackTop", V3(2.6, 0.16, 0.16), rk * CF(0, 4.45, 0), BLACK, M.Metal)
		part(m, "RackShelf", V3(2.6, 0.1, 0.8), rk * CF(0, 1.4, 0.1), lv >= 4 and rgb(60, 60, 66) or WOOD, lv >= 4 and M.Metal or M.Wood)
		for _, x in ipairs({ -0.8, 0, 0.8 }) do
			cyl(m, "Peg", 0.4, 0.08, rk * CF(x, 4.45, 0.25) * ANG(0, RAD(90), 0), CHROME, M.Metal)
		end
		local function mitt(cf, c, target)
			part(m, "FocusMitt", V3(0.55, 0.72, 0.26), cf, c, M.Leather)
			cyl(m, "MittTarget", 0.04, 0.38, cf * CF(0, 0.02, 0.14) * ANG(0, RAD(90), 0), target, M.SmoothPlastic)
		end
		local pairs_ = { { -0.8, RED, WHITE } }
		if lv >= 3 then
			table.insert(pairs_, { 0, BLACK, lv >= 5 and GOLD or RED })
		end
		for _, pr in ipairs(pairs_) do
			mitt(rk * CF(pr[1] - 0.06, 3.95, 0.3) * ANG(0, 0, RAD(6)), pr[2], pr[3])
			mitt(rk * CF(pr[1] + 0.06, 3.9, 0.56) * ANG(0, 0, RAD(-6)), pr[2], pr[3])
		end
		if lv >= 4 then
			part(m, "BellyPad", V3(0.75, 1.0, 0.3), rk * CF(0.7, 3.75, 0.36), BLACK, M.Leather)
			cyl(m, "BellyTarget", 0.04, 0.45, rk * CF(0.7, 3.75, 0.52) * ANG(0, RAD(90), 0), GOLD, M.SmoothPlastic)
		end
		if lv >= 5 then
			for _, x in ipairs({ -0.4, 0.4 }) do
				part(m, "ThaiPad", V3(0.55, 0.26, 1.1), rk * CF(x, 1.58, 0.1), RED, M.Leather)
				part(m, "ThaiStrap", V3(0.58, 0.06, 0.12), rk * CF(x, 1.73, 0.1), BLACK, M.Fabric)
			end
		end
		bottle(m, rk * CF(0.88, 1.45, 0.3), rgb(40, 120, 220))
		-- corner stool, spit bucket with towel, water bottles
		local sc = at(4.8, 0, 1.0)
		vcyl(m, "StoolSeat", 0.16, 1.2, sc * CF(0, 1.64, 0), lv >= 4 and RED or BLACK, M.Leather)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			beam(m, "StoolLeg", (sc * CF(math.cos(a) * 0.36, 1.66, math.sin(a) * 0.36)).Position, (sc * CF(math.cos(a) * 0.55, 0, math.sin(a) * 0.55)).Position, 0.1, 0.1, CHROME, M.Metal)
		end
		local bk = at(5.8, 0, 2.1)
		vcyl(m, "SpitBucket", 0.9, 0.85, bk, lv >= 4 and RED or WHITE, M.SmoothPlastic)
		vcyl(m, "BucketRim", 0.08, 0.92, bk * CF(0, 0.86, 0), lv >= 4 and RED or WHITE, M.SmoothPlastic)
		towel(m, bk * CF(-0.3, 0.86, 0) * ANG(0, 0, RAD(35)), WHITE, 0.7, 0.9)
		bottle(m, at(4.2, 0, 2.0), rgb(230, 230, 235))
		if lv >= 3 then
			-- combo whiteboard on an easel, angled at the boxer
			local wb = at(4.9, 0, -3.9) * ANG(0, RAD(-31), 0)
			part(m, "BoardFrame", V3(4.2, 2.8, 0.1), wb * CF(0, 4.5, -0.04), STEEL, M.Metal)
			local board = part(m, "Whiteboard", V3(4, 2.6, 0.08), wb * CF(0, 4.5, 0.02), WHITE, M.SmoothPlastic)
			local combos = ({
				"PRO DRILLS\n1-2  |  1-2-3\nSLIP-2-3\nROLL-3-2",
				"ELITE ROUNDS\n1-2-3-2  |  1-1-2\nSLIP-SLIP-2\nROLL-PIVOT-3",
				"CHAMPIONSHIP\n1-2-3-2-3\nSLIP-ROLL-3-2\nFEINT-1-2-PIVOT",
			})[lv - 2] or "1-2\n1-2-3"
			surfaceText(board, Enum.NormalId.Back, combos, rgb(30, 60, 160), WHITE, 40)
			part(m, "MarkerTray", V3(3.4, 0.08, 0.25), wb * CF(0, 3.2, 0.14), STEEL, M.Metal)
			part(m, "Marker", V3(0.4, 0.07, 0.07), wb * CF(-0.8, 3.27, 0.14), RED, M.SmoothPlastic)
			for _, x in ipairs({ -1.9, 1.9 }) do
				part(m, "BoardLeg", V3(0.14, 5.9, 0.14), wb * CF(x, 2.95, -0.12), STEEL, M.Metal)
			end
		end
	end
	if lv >= 5 then
		-- Hall of Fame banner hanging from the roof
		local bcf = at(0, 9.5, -6)
		local banner = part(m, "HOFBanner", V3(5, 1.6, 0.08), bcf, rgb(20, 20, 24), M.Fabric)
		surfaceText(banner, Enum.NormalId.Back, "HALL OF FAME TRAINING", GOLD, rgb(20, 20, 24), 50)
		cyl(m, "BannerPole", 5.5, 0.14, bcf * CF(0, 0.86, 0), WOOD, M.Wood)
		part(m, "Fringe", V3(5, 0.16, 0.1), bcf * CF(0, -0.86, 0), GOLD, M.Fabric)
		for _, x in ipairs({ -2.2, 2.2 }) do
			part(m, "BannerCord", V3(0.05, 19, 0.05), bcf * CF(x, 0.86 + 9.5, 0), rgb(40, 40, 40), M.Fabric)
		end
	end
	return { plaque = O * CF(-3.4, 2.4, 2.2) }
end

B.mirror = function(m, O, lv, cond, rng)
	local w = lv == 1 and 4 or 14
	local h = lv == 1 and 6 or 8
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	part(m, "MirrorBack", V3(w + 0.6, h + 0.6, 0.2), at(0, h / 2 + 1, -0.15), lv == 1 and WOOD or BLACK, lv == 1 and M.Wood or M.Metal, { collide = true })
	local glass = part(m, "Mirror", V3(w, h, 0.1), at(0, h / 2 + 1, 0), rgb(205, 225, 240), M.Glass, { reflect = 0.65 })
	if lv == 1 then
		-- an old framed mirror leaning on bricks, cracked and taped
		for _, e in ipairs({ { 0, h + 1.05, w + 0.3, 0.22 }, { 0, 0.95, w + 0.3, 0.22 } }) do
			part(m, "Frame", V3(e[3], e[4], 0.18), at(e[1], e[2], 0.04), wear(WOOD, cond, 0.4), M.Wood)
		end
		for _, x in ipairs({ -w / 2 - 0.05, w / 2 + 0.05 }) do
			part(m, "Frame", V3(0.22, h + 0.3, 0.18), at(x, h / 2 + 1, 0.04), wear(WOOD, cond, 0.4), M.Wood)
		end
		for _, x in ipairs({ -1.4, 1.4 }) do
			part(m, "Brick", V3(0.6, 0.7, 0.8), at(x, 0.35, -0.15), rgb(150, 70, 55), M.Brick)
		end
		beam(m, "Strut", o + V3(0, 5, -0.3), o + V3(0, 0.05, -1.8), 0.25, 0.25, WOOD, M.Wood)
		for i = 1, 4 do
			part(m, "Crack", V3(0.05, rng:NextNumber(1.2, 2.6), 0.02), at(0.6, h / 2 + 1.4, 0.07) * ANG(0, 0, RAD(i * 50)) * CF(0, 0.8, 0), rgb(90, 100, 110), M.SmoothPlastic)
		end
		for _, a in ipairs({ 40, -40 }) do
			part(m, "CrackTape", V3(1.3, 0.22, 0.02), at(0.6, h / 2 + 1.4, 0.07) * ANG(0, 0, RAD(a)), TAPE, M.Foil)
		end
	else
		-- studio mirror wall: plinth, rear struts, J-channel rails, dividers with bolts
		part(m, "Plinth", V3(w + 0.6, 0.7, 0.5), at(0, 0.35, -0.15), BLACK, M.Metal)
		for _, x in ipairs({ -5, 0, 5 }) do
			beam(m, "RearStrut", o + V3(x, 7, -0.3), o + V3(x, 0.05, -2.4), 0.2, 0.2, BLACK, M.Metal)
		end
		part(m, "TopRail", V3(w + 0.1, 0.12, 0.16), at(0, h + 1.0, 0.06), CHROME, M.Metal)
		part(m, "BottomRail", V3(w + 0.1, 0.12, 0.16), at(0, 1.0, 0.06), CHROME, M.Metal)
		for x = -w / 2 + 3.5, w / 2 - 3.5, 3.5 do
			part(m, "Divider", V3(0.15, h, 0.14), at(x, h / 2 + 1, 0.02), BLACK, M.Metal)
			for _, y in ipairs({ 1.6, h + 0.4 }) do
				cyl(m, "Bolt", 0.04, 0.14, at(x, y, 0.1) * ANG(0, RAD(90), 0), CHROME, M.Metal)
			end
		end
		-- ballet bar on wall brackets
		cyl(m, "BalletBar", w - 1, 0.18, at(0, 3.6, 0.75), lv >= 3 and CHROME or WOOD, lv >= 3 and M.Metal or M.Wood)
		for _, x in ipairs({ -5.25, 0, 5.25 }) do
			part(m, "BarBracket", V3(0.12, 0.12, 0.7), at(x, 3.6, 0.42), CHROME, M.Metal)
			part(m, "BracketPlate", V3(0.3, 0.4, 0.04), at(x, 3.6, 0.07), CHROME, M.Metal)
		end
		-- footwork marks: stance box, centre line and foot positions
		for _, e in ipairs({ { 0, 4.9, 3.2, 0.1 }, { 0, 8.1, 3.2, 0.1 }, { -1.6, 6.5, 0.1, 3.3 }, { 1.6, 6.5, 0.1, 3.3 }, { 0, 3.3, 0.08, 2.4 } }) do
			part(m, "FloorTape", V3(e[3], 0.03, e[4]), at(e[1], 0.015, e[2]), WHITE, M.SmoothPlastic)
		end
		for i = 0, 3 do
			part(m, "FootMark", V3(0.6, 0.03, 1.1), at(-1.2 + (i % 2) * 2.4, 0.03, 3 + math.floor(i / 2) * 2), rgb(240, 200, 60), M.SmoothPlastic)
		end
		-- small accessory stand: shadow-boxing weights and rolled hand wraps
		local st = at(8.1, 0, 0.6)
		vcyl(m, "StandBase", 0.08, 1.0, st, BLACK, M.Metal)
		vcyl(m, "StandPost", 3.0, 0.16, st, BLACK, M.Metal)
		part(m, "Shelf", V3(1.4, 0.08, 0.9), st * CF(0, 2.6, 0), lv >= 3 and rgb(60, 60, 66) or WOOD, lv >= 3 and M.Metal or M.Wood)
		part(m, "LowShelf", V3(1.2, 0.08, 0.8), st * CF(0, 1.3, 0), lv >= 3 and rgb(60, 60, 66) or WOOD, lv >= 3 and M.Metal or M.Wood)
		for _, x in ipairs({ -0.35, 0.35 }) do
			local c = st * CF(x, 2.79, 0) * ANG(0, RAD(90), 0)
			cyl(m, "ShadowWeightGrip", 0.6, 0.12, c, BLACK, M.Rubber)
			for _, s in ipairs({ -1, 1 }) do
				cyl(m, "ShadowWeight", 0.16, 0.3, c * CF(s * 0.32, 0, 0), lv >= 3 and CHROME or RED, lv >= 3 and M.Metal or M.SmoothPlastic)
			end
			cyl(m, "HandWraps", 0.3, 0.32, st * CF(x, 1.5, 0), x < 0 and RED or BLUE, M.Fabric)
		end
	end
	local display
	if lv >= 3 then
		local screen = part(m, "SmartPanel", V3(3, 1.8, 0.05), at(w / 2 - 2, h - 0.2, 0.1), rgb(8, 12, 18), M.SmoothPlastic, { transparency = 0.15 })
		display = surfaceText(screen, Enum.NormalId.Back, "FORM 0%", rgb(80, 220, 255), nil, 60)
		local strip = part(m, "LED", V3(w, 0.1, 0.1), at(0, 0.86, 0.12), rgb(60, 160, 255), M.Neon)
		light(strip, rgb(60, 160, 255), 8, 0.6)
		part(m, "LEDTop", V3(w, 0.08, 0.08), at(0, h + 1.1, 0.06), rgb(60, 160, 255), M.Neon)
		part(m, "CameraPod", V3(0.7, 0.3, 0.2), at(0, h + 0.75, 0.1), DARK, M.SmoothPlastic)
		part(m, "CameraLens", V3(0.2, 0.2, 0.08), at(0, h + 0.75, 0.22), rgb(40, 120, 255), M.Neon, { ellipsoid = true })
	end
	glass.CastShadow = false
	return { display = display, plaque = O * CF(w / 2 + 1.8, 2.4, 2) }
end

-- plate tree: crossed feet, post and two pegs (+X and -X) holding spare plates.
-- spares = { { d, color, mat, hub, label, labelColor, side } } (side 1 = +X peg, -1 = -X peg)
local function plateTree(m, base, frame, h, pegY, spares)
	for _, a in ipairs({ 0, 90 }) do
		part(m, "TreeFoot", V3(1.6, 0.12, 0.3), base * CF(0, 0.06, 0) * ANG(0, RAD(a), 0), frame, M.Metal)
	end
	vcyl(m, "PlateTree", h, 0.24, base, frame, M.Metal)
	local filled = { [1] = 0, [-1] = 0 }
	for _, s in ipairs({ -1, 1 }) do
		cyl(m, "Peg", 0.75, 0.14, base * CF(s * 0.45, pegY, 0), frame, M.Metal)
	end
	for _, e in ipairs(spares) do
		local s = e[7] or 1
		local x = 0.24 + filled[s] + 0.1
		filled[s] += 0.22
		weightPlate(m, base * CF(s * x, pegY, 0), e[1], 0.2, e[2], e[3], e[4], s > 0 and e[5] or nil, e[6])
	end
end

B.bench = function(m, O, lv, cond, rng)
	local pad = ({ rgb(110, 75, 50), BLACK, rgb(150, 20, 25), rgb(150, 20, 25) })[lv] or BLACK
	local frame = ({ RUST, BLACK, STEEL, CHROME })[lv] or BLACK
	local stitch = ({ rgb(80, 55, 35), rgb(70, 70, 76), WHITE, GOLD })[lv] or WHITE
	local top = 1.6
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local padC = wear(pad, cond, 0.35)
	-- bench: pads on boards over a steel beam (split seat/back from level 2), two legs with wide feet
	if lv == 1 then
		part(m, "Pad", V3(1.3, 0.35, 3.9), at(0, top - 0.175, 1.3), padC, M.Fabric, { collide = true })
		for _, z in ipairs({ 0.4, 2.3 }) do
			part(m, "PadTape", V3(1.34, 0.37, 0.3), at(0, top - 0.175, z), TAPE, M.Foil)
		end
		part(m, "Foam", V3(0.45, 0.02, 0.35), at(0.2, top + 0.005, 1.4) * ANG(0, RAD(15), 0), rgb(230, 200, 90), M.Fabric)
		part(m, "Shim", V3(0.4, 0.08, 0.3), at(0.85, 0.04, -0.75) * ANG(0, RAD(25), 0), WOOD, M.Wood)
	else
		for _, e in ipairs({ { -0.05, 1.15 }, { 1.95, 2.6 } }) do
			part(m, "Pad", V3(1.3, 0.35, e[2]), at(0, top - 0.175, e[1]), padC, M.Leather, { collide = true })
			part(m, "PadBoard", V3(1.2, 0.08, e[2] - 0.05), at(0, top - 0.39, e[1]), lv >= 3 and BLACK or WOOD, lv >= 3 and M.Metal or M.Wood)
			for _, x in ipairs({ -0.645, 0.645 }) do
				part(m, "Piping", V3(0.05, 0.05, e[2] - 0.04), at(x, top - 0.02, e[1]), stitch, M.Fabric)
			end
		end
	end
	part(m, "Beam", V3(0.35, 0.3, 4.2), at(0, top - 0.58, 1.3), frame, M.Metal)
	for _, z in ipairs({ -0.5, 3.0 }) do
		part(m, "Leg", V3(0.3, top - 0.73, 0.3), at(0, 0.2 + (top - 0.73) / 2, z), frame, M.Metal, { collide = true })
		part(m, "Foot", V3(1.5, 0.2, 0.35), at(0, 0.1, z), frame, M.Metal, { collide = true })
		if lv >= 2 then
			for _, x in ipairs({ -0.78, 0.78 }) do
				part(m, "EndCap", V3(0.06, 0.22, 0.37), at(x, 0.1, z), BLACK, M.Rubber)
			end
		end
	end
	-- rack uprights with hole pattern and J-hooks, spotter arms from level 2
	for _, x in ipairs({ -1.95, 1.95 }) do
		local u = part(m, "Upright", V3(0.3, 4.7, 0.3), at(x, 2.35, 2.5), frame, M.Metal, { collide = true })
		marks(u, Enum.NormalId.Front, 12, DARK, 0.11, 0.11, 0.08, 0.62)
		part(m, "HookPlate", V3(0.4, 0.55, 0.08), at(x, 4.3, 2.31), frame, M.Metal)
		part(m, "HookArm", V3(0.3, 0.12, 0.42), at(x, 4.33, 2.08), frame, M.Metal)
		part(m, "HookLip", V3(0.3, 0.28, 0.07), at(x, 4.46, 1.88), frame, M.Metal)
		if lv >= 3 then
			part(m, "HookLiner", V3(0.31, 0.03, 0.36), at(x, 4.39, 2.1), BLACK, M.SmoothPlastic)
		end
		if lv >= 2 then
			part(m, "SpotterArm", V3(0.22, 0.22, 1.75), at(x, 2.2, 1.475), frame, M.Metal)
			part(m, "SpotterCap", V3(0.24, 0.24, 0.05), at(x, 2.2, 0.58), lv >= 3 and RED or BLACK, M.SmoothPlastic)
		end
	end
	part(m, "RackFoot", V3(4.4, 0.25, 1.2), at(0, 0.125, 2.5), frame, M.Metal)
	local spare = ({ RUST, IRON, BLUE, RED })[lv] or IRON
	if lv >= 3 then
		local cm = part(m, "Crossmember", V3(3.6, 0.25, 0.3), at(0, 4.58, 2.5), frame, M.Metal)
		tag(cm, Enum.NormalId.Back, lv >= 4 and "ELITE POWER" or "OLYMPIC", lv >= 4 and GOLD or WHITE, 0.9, 0.85)
		-- plate horns on the outside of the uprights with stored plates
		for _, s in ipairs({ -1, 1 }) do
			cyl(m, "PlateHorn", 0.75, 0.24, at(s * 2.475, 1.0, 2.5), frame, M.Metal)
			for i = 1, 2 do
				weightPlate(m, at(s * (2.2 + (i - 0.5) * 0.24), 1.0, 2.5), i == 1 and 1.85 or 1.55, 0.22, spare, M.SmoothPlastic, CHROME, (s > 0 and i == 2) and (lv >= 4 and "25" or "20") or nil)
			end
		end
	end
	-- plate tree with spares
	plateTree(m, at(-3.4, 0, 0.2), frame, 3.0, 1.0, {
		{ 1.8, spare, lv <= 2 and M.Metal or M.SmoothPlastic, lv >= 2 and STEEL or nil, nil, nil, 1 },
		{ 1.5, spare, lv <= 2 and M.Metal or M.SmoothPlastic, lv >= 2 and STEEL or nil, ({ nil, "25", "15", "20" })[lv], WHITE, 1 },
		{ 1.8, spare, lv <= 2 and M.Metal or M.SmoothPlastic, lv >= 2 and STEEL or nil, nil, nil, -1 },
	})
	-- resting barbell (hidden while someone lifts it)
	local bar = Instance.new("Model")
	bar.Name = "RackBar"
	bar.Parent = m
	local loads = {
		{ { d = 1.8, t = 0.26, c = RUST, mat = M.Metal } },
		{ { d = 1.95, t = 0.26, c = IRON, mat = M.Metal, hub = STEEL }, { d = 1.7, t = 0.22, c = IRON, mat = M.Metal, hub = STEEL, label = "35" } },
		{ { d = 2.15, t = 0.28, c = BLUE, hub = CHROME }, { d = 2.15, t = 0.18, c = GREEN, hub = CHROME, label = "10" } },
		{ { d = 2.3, t = 0.26, c = RED, hub = CHROME }, { d = 2.3, t = 0.22, c = BLUE, hub = CHROME }, { d = 2.3, t = 0.18, c = YELLOW, hub = CHROME, label = "15", lc = BLACK }, { d = 0.95, t = 0.08, c = WHITE } },
	}
	local left = lv == 1 and { { d = 1.6, t = 0.3, c = IRON, mat = M.Metal }, { d = 1.0, t = 0.2, c = RUST, mat = M.Metal } } or nil
	olympicBar(bar, O * CF(0, 4.5, 2.2), 6.6, lv, loads[lv] or loads[2], left)
	return { rackBar = bar, plaque = O * CF(3.2, 2.4, -1.5) }
end

B.dumbbells = function(m, O, lv, cond, rng)
	local frame = ({ RUST, BLACK, CHROME, BLACK })[lv] or BLACK
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- two-tier tray rack: feet, front legs, tall back legs (mirror frame from level 2), tilted trays
	for _, x in ipairs({ -4.0, 4.0 }) do
		part(m, "RackFoot", V3(0.4, 0.2, 2.6), at(x, 0.1, 0), frame, M.Metal, { collide = true })
		part(m, "FrontLeg", V3(0.3, 1.35, 0.3), at(x, 0.875, 0.95), frame, M.Metal, { collide = true })
		local backH = lv == 1 and 2.9 or 7.4
		part(m, "BackLeg", V3(0.3, backH, 0.3), at(x, 0.2 + backH / 2, -0.95), frame, M.Metal, { collide = true })
	end
	local trays = { at(0, 1.55, 0.45) * ANG(RAD(12), 0, 0), at(0, 2.75, -0.45) * ANG(RAD(12), 0, 0) }
	for _, t in ipairs(trays) do
		part(m, "Tray", V3(7.7, 0.1, 1.3), t, frame, M.Metal, { collide = true })
		part(m, "TrayLip", V3(7.7, 0.18, 0.06), t * CF(0, 0.09, 0.62), frame, M.Metal)
		part(m, "TrayLip", V3(7.7, 0.24, 0.06), t * CF(0, 0.12, -0.62), frame, M.Metal)
		for _, x in ipairs({ -3.76, 3.76 }) do
			part(m, "SideRail", V3(0.18, 0.18, 1.3), t * CF(x, -0.14, 0), frame, M.Metal)
		end
	end
	-- the pair you train with lives in its own model so it can vanish from the rack while in use
	local held = Instance.new("Model")
	held.Name = "RackPair"
	held.Parent = m
	local headC = ({ RUST, rgb(30, 30, 33), CHROME, rgb(45, 45, 52) })[lv] or BLACK
	local junk = { RUST, IRON, rgb(95, 95, 100) }
	local function dumbbell(model, t, x, s, label)
		local th = 0.26
		local c = t * CF(x, 0.05 + s / 2, 0) * ANG(0, RAD(-90), 0) -- local X points at the user
		cyl(model, "DBHandle", 0.74, 0.14, c, lv == 1 and wear(STEEL, 0, 0.5) or (lv >= 3 and CHROME or STEEL), M.DiamondPlate)
		for _, side in ipairs({ -1, 1 }) do
			local hc = c * CF(side * (0.37 + th / 2), 0, 0)
			local face
			if lv == 1 then
				-- spin-lock handles loaded with odd plates
				local col = junk[rng:NextInteger(1, #junk)]
				face = cyl(model, "DBPlate", th, s * rng:NextNumber(0.85, 1.12), hc, col, M.Metal)
				cyl(model, "SpinLock", 0.1, 0.24, hc * CF(side * (th / 2 + 0.05), 0, 0), RUST, M.Metal)
			elseif lv == 2 then
				-- rubber hex head: three blocks make a hexagon
				for k = 0, 2 do
					local p = part(model, "DBHead", V3(th, s, s / math.sqrt(3)), hc * ANG(k * math.pi / 3, 0, 0), headC, M.Rubber)
					face = face or p
				end
			else
				face = cyl(model, "DBHead", th, s, hc, headC, lv == 3 and M.Metal or M.SmoothPlastic, { reflect = lv == 3 and 0.25 or 0 })
				if lv >= 4 then
					face = cyl(model, "DBCap", 0.03, s * 0.62, hc * CF(side * (th / 2 + 0.01), 0, 0), side > 0 and RED or GOLD, M.SmoothPlastic)
				end
			end
			if label and side > 0 then
				tag(face, Enum.NormalId.Right, label, lv == 3 and BLACK or WHITE, 0.8, 0.42)
			end
		end
	end
	local rows = {
		{ t = trays[2], set = { { -2.6, 0.5, "15" }, { 0, 0.56, "20" }, { 2.6, 0.62, "25" } } },
		{ t = trays[1], set = { { -2.6, 0.68, "30" }, { 0, 0.76, "40" }, { 2.6, 0.84, "50" } } },
	}
	for ri, row in ipairs(rows) do
		for pi, pr in ipairs(row.set) do
			for k, dx in ipairs({ -0.5, 0.5 }) do
				-- the old rack is missing a couple of dumbbells
				local missing = lv == 1 and ((ri == 1 and pi == 1 and k == 2) or (ri == 2 and pi == 3 and k == 1))
				if not missing then
					local s = lv == 4 and pr[2] * 0.95 or pr[2]
					dumbbell((ri == 1 and pi == 2) and held or m, row.t, pr[1] + dx, s, ri == 2 and pr[3] or nil)
				end
			end
		end
	end
	if lv == 1 then
		for i, e in ipairs({ { -2.4, 1.3 }, { -1.9, 1.15 } }) do
			cyl(m, "LoosePlate", 0.16, e[2], at(e[1] + i * 0.1, e[2] / 2, 1.25) * ANG(RAD(-10), 0, 0) * ANG(0, RAD(90), 0), junk[i], M.Metal)
		end
	else
		-- mirror between the back legs, rubber floor where you stand
		local y0 = lv >= 4 and 4.85 or 3.3
		part(m, "WallMirror", V3(7.7, 7.3 - y0, 0.08), at(0, (y0 + 7.3) / 2, -0.95), rgb(205, 225, 240), M.Glass, { reflect = 0.5, shadow = false })
		part(m, "MirrorCap", V3(8.4, 0.3, 0.4), at(0, 7.45, -0.95), frame, M.Metal)
		part(m, "Mat", V3(9, 0.06, 4.6), at(0, 0.03, 3.7), wear(RUBBER, cond, 0.3), M.Rubber)
	end
	if lv >= 4 then
		-- top shelf with two adjustable dumbbells in their cradles
		local sh = at(0, 3.75, -0.75)
		part(m, "TopShelf", V3(7.7, 0.12, 0.9), sh, frame, M.Metal)
		for _, x in ipairs({ -1.6, 1.6 }) do
			part(m, "Cradle", V3(1.3, 0.3, 0.8), sh * CF(x, 0.21, 0), DARK, M.SmoothPlastic)
			local c = sh * CF(x, 0.6, 0)
			cyl(m, "AdjHandle", 0.5, 0.15, c, CHROME, M.DiamondPlate)
			for _, s in ipairs({ -1, 1 }) do
				cyl(m, "AdjStack", 0.36, 0.85, c * CF(s * 0.43, 0, 0), rgb(30, 30, 34), M.SmoothPlastic)
				cyl(m, "AdjDial", 0.06, 0.5, c * CF(s * 0.64, 0, 0), rgb(255, 140, 30), M.SmoothPlastic)
			end
		end
		local sign = part(m, "Sign", V3(3, 0.6, 0.1), at(0, 7.45, -0.72), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, "ELITE ADJUSTABLE", GOLD, BLACK, 50)
	end
	return { rackBar = held, plaque = O * CF(5.2, 2.4, 2) }
end

B.barbell = function(m, O, lv, cond, rng)
	local platC = ({ rgb(60, 60, 64), rgb(40, 40, 44), rgb(30, 30, 34), rgb(25, 25, 28) })[lv] or rgb(40, 40, 44)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	if lv == 1 then
		-- four mismatched stall mats, one cracked
		for i, e in ipairs({ { -2, -2, 0 }, { 2, -2, 8 }, { -2, 2, -6 }, { 2, 2, 4 } }) do
			part(m, "StallMat", V3(3.96, 0.3, 3.96), at(e[1], 0.15, e[2]) * ANG(0, RAD(e[3] * 0.25), 0), wear(platC:Lerp(rgb(80, 70, 60), i * 0.08), cond, 0.3), M.Rubber, { collide = true })
		end
		part(m, "Crack", V3(0.06, 0.02, 2.4), at(1.4, 0.305, 1.6) * ANG(0, RAD(25), 0), DARK, M.SmoothPlastic)
	else
		part(m, "Platform", V3(8, 0.3, 8), at(0, 0.15, 0), wear(platC, cond, 0.3), M.Rubber, { collide = true })
		part(m, "PlatformWood", V3(4, 0.32, 8), at(0, 0.16, 0), wear(WOOD, cond, 0.3), M.WoodPlanks, { collide = true })
		if lv >= 4 then
			for _, e in ipairs({ { 0, -4.05, 8.2, 0.1 }, { 0, 4.05, 8.2, 0.1 }, { -4.05, 0, 0.1, 8.0 }, { 4.05, 0, 0.1, 8.0 } }) do
				part(m, "PlatformFrame", V3(e[3], 0.32, e[4]), at(e[1], 0.16, e[2]), STEEL, M.Metal)
			end
			local logo = part(m, "PlatLogo", V3(3, 0.02, 3), at(0, 0.33, 2.2), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			surfaceText(logo, Enum.NormalId.Top, "WCB", GOLD, nil, 40)
			-- chalk bowl on a pedestal
			local cb = at(5, 0, 2.5)
			vcyl(m, "ChalkBase", 0.1, 1.2, cb, CHROME, M.Metal)
			vcyl(m, "ChalkColumn", 2.25, 0.35, cb, CHROME, M.Metal)
			vcyl(m, "ChalkBowl", 0.35, 1.5, cb * CF(0, 2.25, 0), CHROME, M.Metal, { reflect = 0.2 })
			vcyl(m, "Chalk", 0.06, 1.3, cb * CF(0, 2.56, 0), WHITE, M.Sand)
			part(m, "ChalkBlock", V3(0.35, 0.18, 0.25), cb * CF(0.2, 2.68, 0.1) * ANG(0, RAD(20), 0), WHITE, M.Sand)
		end
		-- plate tree with spares
		local bump = lv >= 3
		plateTree(m, at(-5.6, 0, -2.6), BLACK, 2.6, 1.3, {
			{ 2.5, bump and YELLOW or IRON, bump and M.Rubber or M.Metal, bump and CHROME or STEEL, nil, nil, 1 },
			{ bump and 2.5 or 2.0, bump and RED or IRON, bump and M.Rubber or M.Metal, bump and CHROME or STEEL, bump and "25" or "35", WHITE, 1 },
			{ 2.5, bump and GREEN or IRON, bump and M.Rubber or M.Metal, bump and CHROME or STEEL, nil, nil, -1 },
		})
	end
	-- resting barbell on the platform (hidden while someone lifts it)
	local bar = Instance.new("Model")
	bar.Name = "RackBar"
	bar.Parent = m
	local loads = {
		{ { d = 2.5, t = 0.3, c = RUST, mat = M.Metal }, { d = 1.6, t = 0.2, c = IRON, mat = M.Metal } },
		{ { d = 2.5, t = 0.28, c = IRON, mat = M.Metal, hub = STEEL }, { d = 2.5, t = 0.28, c = IRON, mat = M.Metal, hub = STEEL, label = "45" } },
		{ { d = 2.5, t = 0.3, c = BLUE, mat = M.Rubber, hub = CHROME }, { d = 2.5, t = 0.2, c = GREEN, mat = M.Rubber, hub = CHROME, label = "10" } },
		{ { d = 2.5, t = 0.26, c = RED, mat = M.Rubber, hub = CHROME }, { d = 2.5, t = 0.26, c = RED, mat = M.Rubber, hub = CHROME }, { d = 2.5, t = 0.22, c = BLUE, mat = M.Rubber, hub = CHROME, label = "20" }, { d = 1.0, t = 0.08, c = WHITE } },
	}
	local left = lv == 1 and { { d = 2.5, t = 0.36, c = IRON, mat = M.Metal } } or nil
	olympicBar(bar, O * CF(0, 0.3 + 1.25, -0.7), 7, lv, loads[lv] or loads[2], left, lv == 1)
	return { rackBar = bar, plaque = O * CF(-5, 2.4, 3) }
end

local function chalkBucket(m, cf)
	vcyl(m, "ChalkBucket", 0.75, 0.8, cf, rgb(40, 40, 44), M.SmoothPlastic)
	vcyl(m, "Chalk", 0.05, 0.7, cf * CF(0, 0.68, 0), WHITE, M.Sand)
	part(m, "ChalkBlock", V3(0.3, 0.16, 0.22), cf * CF(0.1, 0.78, 0.05) * ANG(0, RAD(30), 0), WHITE, M.Sand)
end

B.squat = function(m, O, lv, cond, rng)
	local frame = ({ RUST, BLACK, BLACK, rgb(170, 20, 25) })[lv] or BLACK
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- lifting floor (you stand on it: top at 0.2)
	part(m, "Floor", V3(6, 0.2, 5), at(0, 0.1, 0), wear(lv == 1 and rgb(55, 55, 58) or rgb(35, 35, 38), cond, 0.3), M.Rubber, { collide = true })
	if lv == 1 then
		part(m, "FloorCrack", V3(0.06, 0.02, 1.8), at(-1.6, 0.205, 1.2) * ANG(0, RAD(-30), 0), DARK, M.SmoothPlastic)
	elseif lv >= 3 then
		for _, x in ipairs({ -1.2, 1.2 }) do
			part(m, "StanceLine", V3(0.08, 0.02, 3.2), at(x, 0.205, 0.2), lv >= 4 and GOLD or WHITE, M.SmoothPlastic)
		end
	end
	-- J-hook on an upright face: plate, arm under the bar, lip in front of it (dir 1 = points +Z)
	local function jhook(x, zFace, dir)
		part(m, "HookPlate", V3(0.42, 0.6, 0.08), at(x, 5.2, zFace + dir * 0.04), frame, M.Metal)
		part(m, "HookArm", V3(0.26, 0.12, 0.42), at(x, 5.24, zFace + dir * 0.25), frame, M.Metal)
		part(m, "HookLip", V3(0.26, 0.3, 0.07), at(x, 5.37, zFace + dir * 0.49), frame, M.Metal)
		if lv >= 3 then
			part(m, "HookLiner", V3(0.27, 0.03, 0.38), at(x, 5.31, zFace + dir * 0.26), BLACK, M.SmoothPlastic)
		end
	end
	local stored = ({ nil, { { 1.8, IRON, M.Metal, "45" } }, { { 2.0, BLUE, M.Rubber }, { 2.0, GREEN, M.Rubber, "10" } }, { { 2.0, RED, M.Rubber }, { 2.0, YELLOW, M.Rubber, "15", BLACK } } })[lv]
	local function horn(x, z)
		local s = x > 0 and 1 or -1
		cyl(m, "PlateHorn", 0.85, 0.24, at(x + s * 0.425, 1.25, z), frame, M.Metal)
		for i, e in ipairs(stored or {}) do
			weightPlate(m, at(x + s * (0.31 + (i - 0.5) * 0.24), 1.25, z), e[1], 0.22, e[2], e[3], CHROME, s > 0 and e[4] or nil, e[5])
		end
	end
	if lv == 1 then
		-- two separate stands with U-cradles and braced feet
		for _, x in ipairs({ -2.2, 2.2 }) do
			part(m, "StandFoot", V3(1.6, 0.2, 1.6), at(x, 0.3, 0), frame, M.Metal)
			part(m, "Upright", V3(0.35, 4.8, 0.35), at(x, 2.8, 0), frame, M.Metal, { collide = true })
			for _, s in ipairs({ -1, 1 }) do
				beam(m, "StandBrace", o + V3(x, 0.4, s * 0.7), o + V3(x, 1.6, s * 0.15), 0.14, 0.14, frame, M.Metal)
				part(m, "CradleLip", V3(0.4, 0.3, 0.06), at(x, 5.37, s * 0.22), frame, M.Metal)
			end
			part(m, "Cradle", V3(0.4, 0.08, 0.5), at(x, 5.26, 0), frame, M.Metal)
		end
	elseif lv == 2 then
		-- squat rack: two uprights with rear braces, J-hooks, safety pins, plate horns
		for _, x in ipairs({ -2.2, 2.2 }) do
			local u = part(m, "Upright", V3(0.35, 8.2, 0.35), at(x, 4.3, -1.25), frame, M.Metal, { collide = true })
			marks(u, Enum.NormalId.Back, 20, DARK, 0.12, 0.12, 0.1, 0.75)
			part(m, "Foot", V3(0.4, 0.2, 2.9), at(x, 0.3, -0.95), frame, M.Metal)
			beam(m, "RearBrace", o + V3(x, 2.4, -1.4), o + V3(x, 0.4, -2.35), 0.18, 0.18, frame, M.Metal)
			jhook(x, -1.075, 1)
			part(m, "SafetyPin", V3(0.2, 0.2, 1.75), at(x, 2.6, -0.25), CHROME, M.Metal)
			part(m, "PinKnob", V3(0.3, 0.3, 0.12), at(x, 2.6, 0.64), BLACK, M.SmoothPlastic)
			horn(x + (x > 0 and 0.175 or -0.175), -1.25)
		end
		part(m, "TopBar", V3(4.75, 0.3, 0.3), at(0, 8.25, -1.25), frame, M.Metal)
	else
		-- power rack: four uprights, base rails, top frame, pull-up bar, safeties, band pegs, horns
		for _, p in ipairs({ { -2.3, -1.8 }, { 2.3, -1.8 }, { -2.3, 1.4 }, { 2.3, 1.4 } }) do
			local u = part(m, "Upright", V3(0.35, 8.2, 0.35), at(p[1], 4.3, p[2]), frame, M.Metal, { collide = true })
			marks(u, p[2] < 0 and Enum.NormalId.Back or Enum.NormalId.Front, 20, DARK, 0.12, 0.12, 0.1, 0.75)
			if p[2] > 0 then
				cyl(m, "BandPeg", 0.4, 0.14, at(p[1] + (p[1] > 0 and 0.37 or -0.37), 0.75, p[2]), CHROME, M.Metal)
			else
				jhook(p[1], -1.625, 1)
				horn(p[1] + (p[1] > 0 and 0.175 or -0.175), p[2])
			end
		end
		for _, x in ipairs({ -2.3, 2.3 }) do
			part(m, "BaseRail", V3(0.4, 0.2, 3.55), at(x, 0.3, -0.2), frame, M.Metal)
			part(m, "TopSide", V3(0.3, 0.3, 3.55), at(x, 8.25, -0.2), frame, M.Metal)
			if lv >= 4 then
				-- competition safety straps
				part(m, "SafetyStrap", V3(0.3, 0.06, 3.25), at(x * 0.92, 2.7, -0.2), BLACK, M.Fabric)
				for _, z in ipairs({ -1.6, 1.2 }) do
					part(m, "StrapBracket", V3(0.42, 0.3, 0.14), at(x * 0.92, 2.75, z), frame, M.Metal)
				end
			else
				part(m, "SafetyPin", V3(0.2, 0.2, 3.6), at(x, 2.6, -0.2), CHROME, M.Metal)
				for _, z in ipairs({ -2.0, 1.6 }) do
					part(m, "PinKnob", V3(0.3, 0.3, 0.12), at(x, 2.6, z), BLACK, M.SmoothPlastic)
				end
			end
		end
		for _, z in ipairs({ -1.8, 1.4 }) do
			part(m, "TopBar", V3(4.95, 0.3, 0.3), at(0, 8.25, z), frame, M.Metal)
		end
		cyl(m, "PullBar", 4.6, 0.2, at(0, 8.25, 1.75), CHROME, M.Metal)
		cyl(m, "PullKnurl", 2.6, 0.21, at(0, 8.25, 1.75), KNURL, M.DiamondPlate)
		for _, x in ipairs({ -1.6, 1.6 }) do
			part(m, "PullBracket", V3(0.2, 0.2, 0.3), at(x, 8.25, 1.62), frame, M.Metal)
		end
		if lv >= 4 then
			local logo = part(m, "LogoPlate", V3(2.6, 0.7, 0.1), at(0, 7.75, -1.6), BLACK, M.Metal)
			surfaceText(logo, Enum.NormalId.Back, "ELITE RACK", GOLD, BLACK, 50)
			-- landmine pivot on the back of the rack, its bar stored upright against the top bar
			part(m, "LandmineBase", V3(0.5, 0.3, 0.5), at(-1.2, 0.35, -2.3), frame, M.Metal)
			local piv = o + V3(-1.2, 0.55, -2.3)
			local tip = o + V3(-1.0, 7.95, -2.0)
			rod(m, "LandmineSleeve", piv, piv + (tip - piv).Unit * 0.9, 0.3, CHROME, M.Metal)
			rod(m, "LandmineBar", piv, tip, 0.2, STEEL, M.Metal)
			cyl(m, "LandmineCollar", 0.2, 0.36, CFrame.lookAt(tip, piv, upFor(piv - tip)) * ANG(0, RAD(90), 0) * CF(0.4, 0, 0), RED, M.SmoothPlastic)
		end
	end
	-- resting barbell (hidden while someone lifts it)
	local bar = Instance.new("Model")
	bar.Name = "RackBar"
	bar.Parent = m
	local zb = ({ 0, -0.9, -1.4, -1.4 })[lv] or -1.4
	local loads = {
		{ { d = 2.1, t = 0.28, c = RUST, mat = M.Metal } },
		{ { d = 2.2, t = 0.26, c = IRON, mat = M.Metal, hub = STEEL }, { d = 1.7, t = 0.2, c = IRON, mat = M.Metal, hub = STEEL, label = "25" } },
		{ { d = 2.3, t = 0.28, c = BLUE, mat = M.Rubber, hub = CHROME }, { d = 2.3, t = 0.18, c = GREEN, mat = M.Rubber, hub = CHROME, label = "10" } },
		{ { d = 2.45, t = 0.26, c = RED, mat = M.Rubber, hub = CHROME }, { d = 2.45, t = 0.22, c = BLUE, mat = M.Rubber, hub = CHROME }, { d = 2.45, t = 0.18, c = YELLOW, mat = M.Rubber, hub = CHROME, label = "15", lc = BLACK } },
	}
	local left = lv == 1 and { { d = 1.9, t = 0.3, c = IRON, mat = M.Metal }, { d = 1.2, t = 0.2, c = RUST, mat = M.Metal } } or nil
	olympicBar(bar, O * CF(0, 5.4, zb), 7, lv, loads[lv] or loads[2], left)
	return { rackBar = bar, plaque = O * CF(3.8, 2.4, 2.6) }
end

B.pullup = function(m, O, lv, cond, rng)
	local frame = ({ WOOD, BLACK, BLACK, rgb(170, 20, 25) })[lv] or BLACK
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local barY = 7.15
	if lv == 1 then
		-- a doorway: jambs, header, painted casing, threshold and a cheap bar on screwed-on blocks
		local woodC = wear(frame, cond, 0.4)
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(m, "Jamb", V3(0.6, 8.6, 0.6), at(x, 4.3, 0), woodC, M.Wood, { collide = true })
			part(m, "Casing", V3(0.8, 8.9, 0.08), at(x, 4.45, 0.34), wear(rgb(225, 220, 205), cond, 0.5), M.Wood)
			part(m, "BarBlock", V3(0.35, 0.5, 0.45), at(x * 0.815, barY, 0), WOOD, M.Wood)
		end
		part(m, "Lintel", V3(5.8, 0.6, 0.6), at(0, 8.6, 0), woodC, M.Wood)
		part(m, "HeadCasing", V3(6.0, 0.4, 0.08), at(0, 9.1, 0.34), wear(rgb(225, 220, 205), cond, 0.5), M.Wood)
		part(m, "Threshold", V3(4.6, 0.06, 0.8), at(0, 0.03, 0), woodC, M.Wood)
		for _, e in ipairs({ { -2.5, 5.6 }, { 2.7, 3.1 } }) do
			part(m, "PaintChip", V3(0.3, 0.45, 0.02), at(e[1], e[2], 0.39), woodC, M.Wood)
		end
		cyl(m, "Bar", 3.9, 0.2, at(0, barY, 0), STEEL, M.Metal)
		for _, x in ipairs({ -1.0, 1.0 }) do
			cyl(m, "FoamGrip", 0.9, 0.3, at(x, barY, 0), FOAM, M.Rubber)
		end
		part(m, "Towel", V3(0.1, 1.4, 0.7), at(2.95, 5.2, 0), wear(rgb(200, 60, 60), cond, 0.5), M.Fabric)
		return { plaque = O * CF(3.8, 2.4, 1.5) }
	end
	if lv == 2 then
		-- wall-mounted station on a free-standing partition
		part(m, "WallPanel", V3(6.0, 9.0, 0.3), at(0, 4.5, -1.1), rgb(70, 72, 80), M.Concrete, { collide = true })
		part(m, "PanelCap", V3(6.1, 0.15, 0.4), at(0, 9.07, -1.1), BLACK, M.Metal)
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(m, "PanelFoot", V3(0.5, 0.25, 1.6), at(x, 0.125, -1.8), BLACK, M.Metal, { collide = true })
		end
		for _, x in ipairs({ -2.4, 2.4 }) do
			part(m, "WallPlate", V3(0.5, 1.6, 0.06), at(x, barY - 0.6, -0.92), frame, M.Metal)
			part(m, "WallBracket", V3(0.25, 0.25, 1.05), at(x, barY, -0.43), frame, M.Metal)
			beam(m, "BracketBrace", o + V3(x, barY - 1.2, -0.92), o + V3(x, barY - 0.1, -0.3), 0.18, 0.18, frame, M.Metal)
		end
		cyl(m, "Bar", 5.2, 0.22, at(0, barY, 0), STEEL, M.Metal)
		local poster = part(m, "Poster", V3(1.4, 1.8, 0.04), at(1.6, 3.6, -0.93), WHITE, M.SmoothPlastic)
		surfaceText(poster, Enum.NormalId.Back, "PULL-UPS\n3 x MAX\nCHIN-UPS\n3 x 8", rgb(30, 30, 34), WHITE, 40)
	elseif lv == 3 then
		-- power tower: posts on long feet, top crossbar, braced dip bars, back pad
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(m, "Post", V3(0.4, 8.6, 0.4), at(x, 4.3, 0), frame, M.Metal, { collide = true })
			part(m, "Foot", V3(0.45, 0.3, 4.2), at(x, 0.15, 0), frame, M.Metal, { collide = true })
			for _, s in ipairs({ -1, 1 }) do
				part(m, "EndCap", V3(0.47, 0.32, 0.05), at(x, 0.15, s * 2.1), BLACK, M.SmoothPlastic)
			end
			part(m, "PadArm", V3(0.25, 0.25, 1.42), at(x, 4.8, -0.91), frame, M.Metal)
		end
		local cb = part(m, "TopCrossbar", V3(5.6, 0.35, 0.4), at(0, 8.43, 0), frame, M.Metal)
		tag(cb, Enum.NormalId.Back, "POWER TOWER", WHITE, 0.6, 0.8)
		part(m, "PadCrossbar", V3(5.2, 0.25, 0.25), at(0, 4.8, -1.62), frame, M.Metal)
		cyl(m, "Bar", 5.2, 0.22, at(0, barY, 0), CHROME, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			beam(m, "DipArm", o + V3(sx * 2.4, 4.2, 0.1), o + V3(sx * 0.9, 4.2, 0.65), 0.2, 0.2, frame, M.Metal)
			part(m, "DipBar", V3(0.18, 0.18, 2.2), at(sx * 0.9, 4.2, 1.6), CHROME, M.Metal)
			cyl(m, "DipFoam", 0.7, 0.28, at(sx * 0.9, 4.2, 2.3) * ANG(0, RAD(90), 0), FOAM, M.Rubber)
		end
	else
		-- elite rig: four uprights, top frame, multi-grip bar, dip station, back pad
		for _, p in ipairs({ { -2.6, -1.5 }, { 2.6, -1.5 }, { -2.6, 1.5 }, { 2.6, 1.5 } }) do
			local u = part(m, "Upright", V3(0.4, 8.8, 0.4), at(p[1], 4.4, p[2]), frame, M.Metal, { collide = true })
			marks(u, p[1] > 0 and Enum.NormalId.Left or Enum.NormalId.Right, 18, DARK, 0.12, 0.12, 0.12, 0.7)
		end
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(m, "Foot", V3(0.5, 0.25, 4.4), at(x, 0.125, 0), frame, M.Metal, { collide = true })
			for _, s in ipairs({ -1, 1 }) do
				part(m, "EndCap", V3(0.52, 0.27, 0.05), at(x, 0.125, s * 2.2), BLACK, M.SmoothPlastic)
			end
			part(m, "TopSide", V3(0.4, 0.3, 3.4), at(x, 8.65, 0), frame, M.Metal)
			part(m, "DropPlate", V3(0.12, 1.5, 0.5), at(x * 0.942, 7.75, 0), frame, M.Metal)
		end
		for _, z in ipairs({ -1.5, 1.5 }) do
			part(m, "TopBeam", V3(5.6, 0.3, 0.4), at(0, 8.65, z), frame, M.Metal)
		end
		local logo = part(m, "LogoPlate", V3(2.4, 0.5, 0.06), at(0, 8.65, -1.27), BLACK, M.Metal)
		surfaceText(logo, Enum.NormalId.Back, "ELITE RIG", GOLD, BLACK, 50)
		cyl(m, "Bar", 4.9, 0.22, at(0, barY, 0), CHROME, M.Metal)
		for _, x in ipairs({ -1.0, 1.0 }) do
			cyl(m, "BarKnurl", 0.9, 0.225, at(x, barY, 0), KNURL, M.DiamondPlate)
		end
		-- multi-grip bar under the front beam: straight middle, angled wide grips
		cyl(m, "MultiGrip", 2.0, 0.18, at(0, 8.05, 1.5), CHROME, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "GripHanger", V3(0.12, 0.45, 0.12), at(sx * 0.6, 8.27, 1.5), frame, M.Metal)
			rod(m, "AngledGrip", o + V3(sx * 0.98, 8.05, 1.5), o + V3(sx * 2.0, 8.48, 1.5), 0.18, CHROME, M.Metal)
		end
		-- dip station on the front uprights
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "DipArm", V3(1.5, 0.22, 0.22), at(sx * 1.65, 4.2, 1.5), frame, M.Metal)
			part(m, "DipBar", V3(0.18, 0.18, 1.8), at(sx * 0.9, 4.2, 2.1), CHROME, M.Metal)
			cyl(m, "DipFoam", 0.6, 0.28, at(sx * 0.9, 4.2, 2.7) * ANG(0, RAD(90), 0), FOAM, M.Rubber)
		end
		part(m, "PadCrossbar", V3(4.8, 0.3, 0.3), at(0, 4.8, -1.5), frame, M.Metal)
	end
	if lv >= 3 then
		local pz = lv >= 4 and -1.15 or -1.2
		part(m, "BackPad", V3(1.6, 2.4, 0.4), at(0, 4.8, pz), rgb(150, 20, 25), M.Leather)
		part(m, "PadBoard", V3(1.5, 2.3, 0.1), at(0, 4.8, pz - 0.25), BLACK, M.Metal)
		-- ab straps hanging from the bar ends / front beam
		for _, sx in ipairs({ -1, 1 }) do
			local sx2, top, z = sx * 2.1, barY, 0
			if lv >= 4 then
				sx2, top, z = sx * 2.25, 8.5, 1.5
			end
			part(m, "AbStrap", V3(0.22, 1.3, 0.04), at(sx2, top - 0.7, z), BLACK, M.Fabric)
			part(m, "AbSling", V3(0.5, 0.42, 0.16), at(sx2, top - 1.45, z), lv >= 4 and RED or BLACK, M.Leather)
		end
	end
	chalkBucket(m, at(-3.4, 0, 1.4))
	return { plaque = O * CF(3.8, 2.4, 1.5) }
end

-- MEDICINE BALL: slams onto a pad in front of the athlete, Russian twists, wall-ball target from level 3.
-- Level 1: a cracked old leather ball and a scrap of plywood on the bare floor. Level 2: a rubber
-- ball set on a rack. Level 3: slam balls, a thick slam pad and a wall-ball target board.
-- Level 4: the elite core station with a rep-counting screen and an LED target ring.
B.medball = function(m, O, lv, cond, rng)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local o = O.Position
	local frame = ({ RUST, BLACK, BLACK, BLACK })[lv] or BLACK
	local trim = ({ RUST, STEEL, RED, GOLD })[lv] or STEEL
	local slamZ = 2.2 -- where the ball hits the floor (between the target and the athlete at z 3.8)
	-- a medicine ball: leather / rubber sphere with seams, grip panels and a weight label
	local function ball(cf, d, color, mat, label, labelColor, style)
		local b = part(m, "MedBall", V3(d, d * (style == "cracked" and 0.94 or 1), d), cf, color, mat, { ellipsoid = true })
		cyl(m, "BallSeam", 0.04, d * 1.02, cf * ANG(0, 0, RAD(90)), style == "cracked" and rgb(60, 40, 25) or DARK, M.Fabric)
		cyl(m, "BallSeam", 0.04, d * 1.02, cf * ANG(0, RAD(90), 0), style == "cracked" and rgb(60, 40, 25) or DARK, M.Fabric)
		if style == "slam" then
			-- textured slam ball: a grip band round the equator
			cyl(m, "GripBand", d * 0.28, d * 1.01, cf * ANG(0, 0, RAD(90)) * ANG(RAD(90), 0, 0), rgb(40, 40, 44), M.Rubber)
		end
		if label then
			-- on the side facing the athlete / the station camera (+Z)
			local plate = part(m, "BallLabel", V3(d * 0.42, d * 0.24, 0.04), cf * CF(0, 0, d / 2 - 0.03), labelColor or WHITE, M.SmoothPlastic)
			tag(plate, Enum.NormalId.Back, label, style == "elite" and GOLD or BLACK, 0.95, 0.85)
		end
		return b
	end
	if lv == 1 then
		-- bare floor: a cracked plywood offcut to slam on, a taped X, chalk marks and scuffs
		part(m, "Plywood", V3(3.0, 0.08, 2.6), at(0.2, 0.04, slamZ) * ANG(0, RAD(6), 0), wear(rgb(170, 135, 90), cond, 0.5), M.WoodPlanks)
		part(m, "PlyCrack", V3(0.05, 0.09, 1.6), at(0.6, 0.045, slamZ - 0.1) * ANG(0, RAD(30), 0), rgb(60, 45, 30), M.SmoothPlastic)
		for _, a in ipairs({ 40, -40 }) do
			part(m, "TapeX", V3(0.22, 0.05, 1.2), at(0.1, 0.09, slamZ) * ANG(0, RAD(a), 0), TAPE, M.Foil)
		end
		scuffs(m, O, 4, 0, slamZ, 1.6, 1.2, 0.012, rng)
		-- the old ball, cracked and taped, resting by a crate
		local rest = at(-2.6, 0.62, 0.4)
		local held = Instance.new("Model")
		held.Name = "RestBall"
		held.Parent = m
		local bm = ball(rest, 1.15, wear(rgb(120, 78, 44), cond, 0.4), M.Leather, nil, nil, "cracked")
		bm.Parent = held
		for _, c in ipairs(m:GetChildren()) do
			if c.Name == "BallSeam" then
				c.Parent = held
			end
		end
		part(held, "BallTape", V3(0.5, 0.18, 0.05), rest * CF(0.2, 0.25, -0.52) * ANG(0, 0, RAD(20)), TAPE, M.Foil)
		part(m, "Crate", V3(1.6, 1.2, 1.4), at(-3.0, 0.6, -1.2) * ANG(0, RAD(-8), 0), wear(rgb(150, 115, 70), cond, 0.4), M.WoodPlanks, { collide = true })
		local cardboard = part(m, "Cardboard", V3(1.4, 0.9, 0.05), at(-3.0, 1.55, -1.22) * ANG(RAD(-6), RAD(-8), 0), rgb(180, 150, 110), M.Fabric)
		tag(cardboard, Enum.NormalId.Back, "CORE\nOR\nNOTHING", rgb(40, 30, 25), 0.9, 0.85)
		return { kind = "medball", rackBar = held, slam = at(0.2, 0.1, slamZ), level = lv, plaque = O * CF(3.2, 2.4, 1.6) }
	end
	-- rubber slam mat (thick pad from level 3) with a painted target
	local padH = lv >= 3 and 0.28 or 0.07
	part(m, "SlamMat", V3(3.6, padH, 3.0), at(0, padH / 2, slamZ), wear(lv >= 4 and rgb(22, 22, 26) or RUBBER, cond, 0.3), M.Rubber, { collide = lv >= 3 })
	if lv >= 3 then
		part(m, "MatEdge", V3(3.7, padH * 0.6, 3.1), at(0, padH * 0.3, slamZ), trim, M.SmoothPlastic)
	end
	local tgt = part(m, "MatTarget", V3(1.4, 0.02, 1.4), at(0, padH + 0.012, slamZ), Color3.new(), M.SmoothPlastic, { transparency = 1 })
	local tsg = Instance.new("SurfaceGui")
	tsg.Face = Enum.NormalId.Top
	tsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tsg.PixelsPerStud = 40
	tsg.LightInfluence = 1
	tsg.Parent = tgt
	for i, f in ipairs({ 1, 0.66, 0.33 }) do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(f, f)
		ring.BackgroundColor3 = i % 2 == 1 and (lv >= 4 and GOLD or RED) or (lv >= 4 and DARK or WHITE)
		ring.BackgroundTransparency = 0.15
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		ring.Parent = tsg
	end
	scuffs(m, O, 1 + math.floor((100 - cond) / 30), 0, slamZ, 1.4, 1.0, padH + 0.015, rng)
	-- ball rack: A-frame shelves on the athlete's left with the set, lightest on top
	local rk = at(-3.6, 0, 0.4)
	local rackH = lv >= 3 and 3.6 or 2.6
	for _, z in ipairs({ -0.9, 0.9 }) do
		for _, s in ipairs({ -1, 1 }) do
			beam(m, "RackLeg", (rk * CF(s * 0.55, 0, z)).Position, (rk * CF(s * 0.15, rackH, z)).Position, 0.14, 0.14, frame, M.Metal)
		end
	end
	part(m, "RackTop", V3(0.4, 0.12, 2.0), rk * CF(0, rackH, 0), trim, M.Metal)
	local balls = lv == 2 and { { 1.0, "6" }, { 1.1, "10" }, { 1.2, "14" } }
		or (lv == 3 and { { 1.0, "10" }, { 1.08, "15" }, { 1.15, "20" }, { 1.22, "25" }, { 1.3, "30" } })
		or { { 1.0, "8" }, { 1.06, "12" }, { 1.12, "16" }, { 1.18, "20" }, { 1.24, "25" }, { 1.3, "30" } }
	local shelves = lv >= 3 and 3 or 2
	for sIdx = 1, shelves do
		local y = 0.35 + (sIdx - 1) * (rackH - 0.6) / math.max(1, shelves - 1)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "Shelf", V3(0.12, 0.1, 2.0), rk * CF(sx * 0.32, y, 0), frame, M.Metal)
		end
	end
	local held = Instance.new("Model")
	held.Name = "RestBall"
	held.Parent = m
	local colors = lv >= 4 and { DARK, rgb(40, 40, 46), DARK } or { RED, BLUE, BLACK, YELLOW, GREEN }
	for i, b in ipairs(balls) do
		local sIdx = math.min(shelves, math.floor((i - 1) / 2) + 1)
		local y = 0.35 + (sIdx - 1) * (rackH - 0.6) / math.max(1, shelves - 1)
		local z = ((i - 1) % 2 == 0) and -0.48 or 0.48
		local c = colors[(i - 1) % #colors + 1]
		ball(rk * CF(0, y + b[1] / 2 + 0.04, z), b[1], c, lv >= 3 and M.Rubber or M.SmoothPlastic, b[2] .. " LB", lv >= 4 and DARK or WHITE, lv >= 4 and "elite" or (lv >= 3 and "slam" or nil))
	end
	-- the working ball waits on the mat edge (it vanishes while you hold your own)
	local restCF = at(1.9, 0.6, slamZ + 0.4)
	ball(restCF, 1.2, lv >= 4 and DARK or rgb(40, 40, 46), M.Rubber, lv >= 4 and "PRO 20" or "20 LB", lv >= 4 and GOLD or WHITE, lv >= 3 and "slam" or nil).Parent = held
	for _, c in ipairs(m:GetChildren()) do
		if (c.Name == "BallSeam" or c.Name == "GripBand" or c.Name == "BallLabel") and (c.Position - restCF.Position).Magnitude < 1 then
			c.Parent = held
		end
	end
	local display, ledRing
	if lv >= 3 then
		-- wall-ball target: a freestanding board behind the pad with a target ring 9 studs up
		local bz = -1.6
		for _, x in ipairs({ -2.0, 2.0 }) do
			part(m, "TargetPost", V3(0.3, 11, 0.3), at(x, 5.5, bz), frame, M.Metal, { collide = true })
			part(m, "TargetFoot", V3(0.4, 0.2, 2.4), at(x, 0.1, bz + 0.4), frame, M.Metal, { collide = true })
		end
		local board = part(m, "TargetBoard", V3(3.8, 9, 0.16), at(0, 6, bz), lv >= 4 and rgb(26, 26, 30) or WHITE, M.SmoothPlastic)
		part(m, "TargetRing", V3(1.7, 1.7, 0.05), at(0, 9, bz + 0.1), lv >= 4 and GOLD or RED, M.SmoothPlastic, { ellipsoid = true })
		part(m, "TargetInner", V3(1.1, 1.1, 0.06), at(0, 9, bz + 0.12), lv >= 4 and DARK or WHITE, M.SmoothPlastic, { ellipsoid = true })
		tag(board, Enum.NormalId.Back, lv >= 4 and "ELITE CORE" or "WALL BALL", lv >= 4 and GOLD or RED, 0.9, 0.08, 0.5, 0.06)
		if lv >= 4 then
			ledRing = part(m, "TargetLED", V3(2.0, 2.0, 0.04), at(0, 9, bz + 0.08), rgb(255, 200, 70), M.Neon, { ellipsoid = true, transparency = 0.35 })
			-- rep-counting screen on the board, sensor strip on the pad
			local screen = part(m, "CoreScreen", V3(2.6, 1.5, 0.05), at(0, 4.4, bz + 0.12), rgb(8, 10, 14), M.SmoothPlastic)
			display = surfaceText(screen, Enum.NormalId.Back, "CORE STATION\nREADY", rgb(255, 210, 90), rgb(8, 10, 14), 60)
			light(screen, rgb(255, 210, 120), 6, 0.3)
			part(m, "PadSensor", V3(3.0, 0.03, 0.12), at(0, padH + 0.02, slamZ - 1.3), rgb(255, 200, 70), M.Neon)
			local logo = part(m, "MatLogo", V3(2.4, 0.02, 0.8), at(0, padH + 0.015, slamZ + 1.1), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			surfaceText(logo, Enum.NormalId.Top, "WCB CORE", GOLD, nil, 40)
			-- ab wheel and a gold-trim towel for the twists
			cyl(m, "AbWheel", 0.3, 0.8, at(2.6, 0.4, 0.2), DARK, M.Rubber)
			cyl(m, "AbHandle", 1.2, 0.1, at(2.6, 0.4, 0.2), GOLD, M.Metal)
		else
			cyl(m, "AbWheel", 0.3, 0.8, at(2.6, 0.4, 0.2), RED, M.Rubber)
			cyl(m, "AbHandle", 1.2, 0.1, at(2.6, 0.4, 0.2), STEEL, M.Metal)
		end
		towel(m, at(2.3, 0.06, 2.6) * ANG(0, RAD(15), 0), lv >= 4 and DARK or WHITE, 1.4, 0.9)
	end
	bottle(m, at(2.9, 0, -0.8), lv >= 4 and GOLD or rgb(40, 120, 220))
	-- chalk / dust puff on a slam
	local fxAtt = Instance.new("Attachment")
	fxAtt.Name = "SlamFX"
	fxAtt.Parent = tgt
	local puff = Instance.new("ParticleEmitter")
	puff.Enabled = false
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = ColorSequence.new(lv == 1 and rgb(190, 175, 150) or rgb(225, 225, 225))
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.4) })
	puff.Lifetime = NumberRange.new(0.5, 1.1)
	puff.Speed = NumberRange.new(2, 4)
	puff.SpreadAngle = Vector2.new(80, 80)
	puff.Drag = 4
	puff.Acceleration = V3(0, -1, 0)
	puff.Parent = fxAtt
	return {
		kind = "medball", rackBar = held, display = display, led = ledRing, puff = puff, slam = at(0, padH + 0.1, slamZ),
		level = lv, plaque = O * CF(3.4, 2.4, 2.2),
	}
end

B.treadmill = function(m, O, lv, cond, rng)
	local body = ({ rgb(205, 195, 170), BLACK, rgb(40, 40, 46), BLACK })[lv] or BLACK
	local accent = ({ rgb(150, 140, 120), STEEL, rgb(200, 30, 35), NEONBLUE })[lv] or STEEL
	local bodyC = wear(body, cond, 0.3)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- deck, belt (its stripes animate), side foot rails, rear end cap, motor hood over the front roller
	part(m, "Deck", V3(3, 0.55, 7), at(0, 0.3, 0.2), bodyC, M.SmoothPlastic, { collide = true })
	part(m, "Belt", V3(2.3, 0.06, 6.6), at(0, 0.6, 0.2), rgb(25, 25, 25), M.Rubber)
	local stripes = {}
	for i = 0, 5 do
		table.insert(stripes, part(m, "BeltStripe", V3(2.3, 0.07, 0.12), at(0, 0.61, -3 + i * 1.1), rgb(55, 55, 58), M.Rubber))
	end
	for _, x in ipairs({ -1.33, 1.33 }) do
		part(m, "FootRail", V3(0.34, 0.12, 5.6), at(x, 0.635, 0.7), lv == 1 and wear(rgb(170, 160, 140), cond, 0.3) or rgb(70, 72, 78), lv == 1 and M.SmoothPlastic or M.DiamondPlate)
	end
	part(m, "RearCap", V3(3.0, 0.42, 0.25), at(0, 0.36, 3.82), lv == 1 and bodyC or rgb(30, 30, 34), M.SmoothPlastic)
	part(m, "MotorHood", V3(3.1, 0.7, 1.35), at(0, 0.55, -2.75), bodyC, M.SmoothPlastic)
	part(m, "HoodVent", V3(2.0, 0.02, 0.5), at(0, 0.91, -2.85), DARK, M.SmoothPlastic)
	-- uprights, side handrails with grips (pulse sensors from level 2), front bar from level 3
	for _, x in ipairs({ -1.4, 1.4 }) do
		part(m, "Upright", V3(0.25, 4.4, 0.25), at(x, 2.5, -3) * ANG(RAD(-10), 0, 0), accent, M.Metal)
		part(m, "Rail", V3(0.18, 0.18, 2.2), at(x, 4.1, -2.0), accent, M.Metal)
		part(m, "RailGrip", V3(0.24, 0.24, 1.0), at(x, 4.1, -1.45), lv == 1 and wear(rgb(60, 55, 50), cond, 0.4) or FOAM, M.Rubber)
		if lv >= 2 then
			part(m, "PulseSensor", V3(0.26, 0.05, 0.4), at(x, 4.23, -2.2), CHROME, M.Metal)
		end
	end
	if lv >= 3 then
		cyl(m, "FrontBar", 2.8, 0.16, at(0, 3.72, -3.05), accent, M.Metal)
	end
	-- console: screen, keypad, stop button, safety key on its cord, cup holder
	local ccf = at(0, 4.6, -3.3) * ANG(RAD(-25), 0, 0)
	local console = part(m, "Console", V3(3.2, 1.2, 0.5), ccf, lv == 1 and bodyC or BLACK, M.SmoothPlastic)
	local display
	if lv >= 4 then
		display = surfaceText(console, Enum.NormalId.Back, "PACE --\n0.00 mi", rgb(80, 220, 255), rgb(8, 10, 14), 50)
		local led = part(m, "LED", V3(3, 0.1, 0.1), at(0, 0.6, 3.7), NEONBLUE, M.Neon)
		light(led, NEONBLUE, 6, 0.5)
		part(m, "HoodLED", V3(3.1, 0.05, 0.05), at(0, 0.89, -2.07), NEONBLUE, M.Neon)
	else
		local screen = part(m, "Screen", V3(lv == 1 and 1.2 or 2.0, lv == 1 and 0.45 or 0.7, 0.04), ccf * CF(0, 0.12, 0.26), rgb(10, 12, 10), M.SmoothPlastic)
		local fg = ({ rgb(255, 60, 40), rgb(120, 230, 140), rgb(255, 180, 60) })[lv] or WHITE
		display = surfaceText(screen, Enum.NormalId.Back, ({ "0.0 MPH", "SPEED 0.0\nTIME 0:00", "INCLINE 4%\nPROGRAM 3" })[lv] or "0.0", fg, rgb(10, 12, 10), 50)
		local keys = part(m, "Keypad", V3(2.4, 0.22, 0.03), ccf * CF(0, -0.38, 0.26), rgb(40, 40, 44), M.SmoothPlastic)
		tag(keys, Enum.NormalId.Back, lv == 1 and "-   +" or "- 2 4 6 8 10 +", WHITE, 0.9, 0.8)
	end
	cyl(m, "StopButton", 0.06, 0.3, ccf * CF(1.3, -0.32, 0.27) * ANG(0, RAD(90), 0), RED, M.SmoothPlastic)
	local key = part(m, "SafetyKey", V3(0.2, 0.12, 0.12), ccf * CF(-1.3, -0.4, 0.3), RED, M.SmoothPlastic)
	local k = key.Position
	rod(m, "KeyCord", k, k + V3(0.05, -0.95, 0.3), 0.04, RED, M.Fabric)
	part(m, "KeyClip", V3(0.12, 0.16, 0.06), CF(k + V3(0.05, -1.0, 0.31)), BLACK, M.Plastic)
	vcyl(m, "CupHolder", 0.3, 0.42, at(1.68, 3.8, -2.4), BLACK, M.SmoothPlastic)
	if lv >= 2 then
		bottle(m, at(1.68, 3.84, -2.4), rgb(40, 120, 220), 0.7)
	end
	if lv == 1 then
		part(m, "Crack", V3(0.05, 0.8, 0.02), at(0.6, 4.7, -3.05) * ANG(RAD(-25), 0, RAD(30)), rgb(60, 60, 60), M.SmoothPlastic)
		cyl(m, "RailTape", 0.4, 0.26, at(-1.4, 4.1, -2.6) * ANG(0, RAD(90), 0), TAPE, M.Foil)
		local note = part(m, "StickyNote", V3(0.5, 0.5, 0.02), ccf * CF(0.95, 0.3, 0.26) * ANG(0, 0, RAD(8)), rgb(250, 230, 90), M.SmoothPlastic)
		tag(note, Enum.NormalId.Back, "SQUEAKS!", rgb(40, 40, 40), 0.9, 0.5)
	elseif lv == 3 then
		part(m, "TabletLedge", V3(1.4, 0.06, 0.25), ccf * CF(0, 0.66, 0.3), BLACK, M.SmoothPlastic)
	end
	return { kind = "belt", stripes = stripes, beltCF = O * CF(0, 0.61, 0.2), offset = 0, display = display, plaque = O * CF(2.6, 2.4, 3.8) }
end

B.bike = function(m, O, lv, cond, rng)
	local frameC = wear(({ rgb(215, 210, 200), BLACK, rgb(40, 40, 46) })[lv] or BLACK, cond, 0.3)
	local accent = ({ RUST, rgb(200, 30, 35), rgb(240, 180, 30) })[lv] or STEEL
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- feet, spine rail, seat tube and post, saddle
	local fz = lv == 3 and -3.3 or -2.7
	for _, z in ipairs({ fz, 1.7 }) do
		part(m, "Foot", V3(2.6, 0.25, 0.45), at(0, 0.125, z), frameC, M.Metal, { collide = true })
		for _, x in ipairs({ -1.32, 1.32 }) do
			part(m, "FootCap", V3(0.06, 0.27, 0.47), at(x, 0.125, z), BLACK, M.Rubber)
		end
	end
	part(m, "BaseRail", V3(0.35, 0.3, 1.7 - fz), at(0, 0.4, (1.7 + fz) / 2), frameC, M.Metal, { collide = true })
	beam(m, "SeatTube", o + V3(0, 0.5, 1.35), o + V3(0, 2.15, 1.0), 0.3, 0.3, frameC, M.Metal, { collide = true })
	beam(m, "SeatPost", o + V3(0, 2.0, 1.03), o + V3(0, 2.5, 0.95), 0.2, 0.2, lv == 1 and RUST or CHROME, M.Metal)
	cyl(m, "PopPin", 0.25, 0.18, at(0, 1.95, 1.27) * ANG(0, RAD(90), 0), accent, M.SmoothPlastic)
	part(m, "Seat", V3(1.0, 0.25, 0.8), at(0, 2.58, 1.25), lv == 1 and wear(rgb(70, 50, 40), cond, 0.4) or BLACK, M.Leather)
	part(m, "SeatNose", V3(0.45, 0.24, 0.7), at(0, 2.58, 0.55), lv == 1 and wear(rgb(70, 50, 40), cond, 0.4) or BLACK, M.Leather)
	if lv == 1 then
		part(m, "SeatTape", V3(1.02, 0.26, 0.2), at(0, 2.58, 1.3), TAPE, M.Foil)
	end
	-- column and handlebar (the air bike swaps the bar for moving arms)
	beam(m, "Column", o + V3(0, 0.5, -1.15), o + V3(0, 3.55, -1.85), 0.3, 0.3, frameC, M.Metal, { collide = true })
	beam(m, "Stem", o + V3(0, 3.5, -1.82), o + V3(0, 3.75, -1.95), 0.2, 0.2, frameC, M.Metal)
	local parts = {}
	if lv < 3 then
		cyl(m, "Handlebar", 2.2, 0.2, at(0, 3.75, -1.95), accent, M.Metal)
		for _, x in ipairs({ -0.85, 0.85 }) do
			cyl(m, "Grip", 0.5, 0.27, at(x, 3.75, -1.95), FOAM, M.Rubber)
		end
	end
	-- crank: housing, arms that spin, pedals orbiting the axle (toe cages from level 2)
	local axle = at(0, 1.25, -0.35)
	cyl(m, "CrankHousing", 0.75, 0.4, axle, frameC, M.Metal)
	for _, x in ipairs({ -0.45, 0.45 }) do
		local arm = part(m, "CrankArm", V3(0.1, 1.3, 0.14), axle * CF(x, 0, 0), accent, M.Metal)
		table.insert(parts, { p = arm, base = arm.CFrame, speed = 7 })
		local py = x > 0 and -0.6 or 0.6
		local pedal = part(m, "Pedal", V3(0.4, 0.1, 0.26), axle * CF(x * 1.45, py, 0), BLACK, M.SmoothPlastic)
		table.insert(parts, { p = pedal, base = axle, rel = axle:ToObjectSpace(pedal.CFrame), speed = 7 })
		if lv >= 2 then
			local cage = part(m, "ToeCage", V3(0.42, 0.14, 0.08), axle * CF(x * 1.45, py + 0.1, -0.12), BLACK, M.SmoothPlastic)
			table.insert(parts, { p = cage, base = axle, rel = axle:ToObjectSpace(cage.CFrame), speed = 7 })
		end
	end
	-- resistance: bare flywheel (old bike), weighted spin flywheel, or the air bike's fan
	local display
	if lv < 3 then
		local fc = at(0, 1.3, -2.35)
		local wheel = cyl(m, "Flywheel", 0.3, 1.9, fc, lv == 1 and RUST or CHROME, M.Metal, { reflect = lv == 2 and 0.25 or 0 })
		table.insert(parts, { p = wheel, base = wheel.CFrame, speed = 14 })
		for k = 0, 1 do
			local spoke = part(m, "Spoke", V3(0.34, 1.8, 0.14), fc * ANG(k * math.pi / 2, 0, 0), lv == 1 and rgb(90, 60, 40) or DARK, M.Metal)
			table.insert(parts, { p = spoke, base = spoke.CFrame, speed = 14 })
		end
		for _, x in ipairs({ -0.22, 0.22 }) do
			beam(m, "Fork", o + V3(x, 0.9, -1.3), o + V3(x, 1.3, -2.35), 0.12, 0.12, frameC, M.Metal)
		end
		if lv == 1 then
			part(m, "FrictionStrap", V3(0.12, 0.06, 1.1), at(0, 2.27, -2.35), rgb(60, 45, 35), M.Fabric)
			beam(m, "Chain", o + V3(0.32, 1.25, -0.35), o + V3(0.32, 1.3, -2.35), 0.05, 0.08, RUST, M.Metal)
			local dial = cyl(m, "Speedometer", 0.1, 0.6, at(0, 4.0, -1.9) * ANG(RAD(-25), 0, 0) * ANG(0, RAD(90), 0), WHITE, M.SmoothPlastic)
			display = surfaceText(dial, Enum.NormalId.Left, "0 MPH", BLACK, nil, 50)
		else
			part(m, "FlywheelGuard", V3(0.45, 0.25, 1.6), at(0, 2.18, -2.35), accent, M.SmoothPlastic)
			cyl(m, "ResistanceKnob", 0.18, 0.35, at(0, 2.05, -1.62) * ANG(0, 0, RAD(90)), accent, M.SmoothPlastic)
		end
	else
		-- air bike: fan blades behind see-through guards, swinging arms
		local fc = at(0, 1.6, -2.85)
		local hub = cyl(m, "FanHub", 0.7, 0.5, fc, DARK, M.Metal)
		table.insert(parts, { p = hub, base = hub.CFrame, speed = 14 })
		for k = 0, 2 do
			local blade = part(m, "FanBlade", V3(0.5, 2.4, 0.12), fc * ANG(k * math.pi / 3, 0, 0), STEEL, M.Metal)
			table.insert(parts, { p = blade, base = blade.CFrame, speed = 14 })
		end
		for _, x in ipairs({ -0.4, 0.4 }) do
			cyl(m, "FanGuard", 0.06, 2.7, fc * CF(x, 0, 0), DARK, M.DiamondPlate, { transparency = 0.55 })
		end
		part(m, "FanFrame", V3(0.25, 0.25, 2.2), at(0, 2.98, -2.85), frameC, M.Metal)
		local pivot = at(0, 1.5, -1.55)
		for _, sx in ipairs({ -1, 1 }) do
			local lever = rod(m, "ArmLever", o + V3(sx * 0.45, 1.5, -1.55), o + V3(sx * 0.9, 3.5, -1.92), 0.16, frameC, M.Metal)
			local grip = rod(m, "ArmGrip", o + V3(sx * 0.9, 3.45, -1.92), o + V3(sx * 0.92, 4.15, -1.96), 0.24, FOAM, M.Rubber)
			for _, p in ipairs({ lever, grip }) do
				table.insert(parts, { p = p, base = pivot, rel = pivot:ToObjectSpace(p.CFrame), speed = 7, swing = 0.32, phase = sx > 0 and 0 or math.pi })
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			cyl(m, "FootPeg", 0.5, 0.14, at(sx * 0.62, 1.6, -2.85), frameC, M.Metal)
		end
	end
	if lv >= 2 then
		local mount = lv == 3 and at(0, 3.95, -2.25) or at(0, 4.05, -1.95)
		if lv == 3 then
			beam(m, "ConsoleArm", o + V3(0, 3.55, -1.85), o + V3(0, 3.85, -2.2), 0.18, 0.18, frameC, M.Metal)
		end
		local con = part(m, "Console", V3(0.9, 0.6, 0.18), mount * ANG(RAD(-30), 0, 0), BLACK, M.SmoothPlastic)
		display = surfaceText(con, Enum.NormalId.Back, lv == 3 and "CAL 0\nRPM 0" or "RPM 0\nWATTS 0", rgb(120, 230, 255), rgb(8, 10, 14), 50)
	end
	return { kind = "spinner", parts = parts, angle = 0, display = display, plaque = O * CF(2.4, 2.4, 2) }
end

B.rower = function(m, O, lv, cond, rng)
	local frameC = ({ rgb(180, 180, 175), BLACK, WOOD })[lv] or BLACK
	local accent = ({ RUST, rgb(40, 120, 220), GOLD })[lv] or STEEL
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	-- monorail on front/rear feet with a measuring scale along its top
	local r0 = lv == 3 and -2.15 or -2.6
	local rail = part(m, "Rail", V3(0.5, 0.25, 4.5 - r0), at(0, 0.495, (4.5 + r0) / 2), wear(frameC, cond, 0.3), lv == 3 and M.Wood or M.Metal, { collide = true })
	marks(rail, Enum.NormalId.Top, 16, lv == 3 and rgb(60, 40, 25) or DARK, 0.3, 0.03, 0.04, 0.96)
	part(m, "FrontFoot", V3(2.6, 0.25, 0.5), at(0, 0.125, -3.6), lv == 3 and WOOD or frameC, lv == 3 and M.Wood or M.Metal)
	part(m, "RearFoot", V3(2.0, 0.25, 0.45), at(0, 0.125, 4.3), lv == 3 and WOOD or frameC, lv == 3 and M.Wood or M.Metal)
	part(m, "RearPad", V3(0.4, 0.12, 0.4), at(0, 0.31, 4.3), BLACK, M.Rubber)
	-- seat on a rolling carriage (top stays at 0.9)
	part(m, "Carriage", V3(0.7, 0.12, 0.9), at(0, 0.68, 1.6), DARK, M.Metal)
	for _, x in ipairs({ -0.36, 0.36 }) do
		for _, z in ipairs({ 1.3, 1.9 }) do
			cyl(m, "Roller", 0.08, 0.18, at(x, 0.66, z), BLACK, M.Rubber)
		end
	end
	part(m, "Seat", V3(1.1, 0.16, 1.0), at(0, 0.82, 1.6), lv == 1 and wear(rgb(60, 50, 45), cond, 0.4) or BLACK, M.Leather)
	if lv == 1 then
		part(m, "SeatTape", V3(1.12, 0.02, 0.22), at(0, 0.905, 1.4), TAPE, M.Foil)
	end
	-- foot stretcher: angled plates with heel cups and straps
	part(m, "FootFrame", V3(1.2, 0.15, 0.3), at(0, 0.62, -1.6), wear(frameC, cond, 0.3), M.Metal)
	for _, x in ipairs({ -0.32, 0.32 }) do
		local fcf = at(x, 0.95, -1.6) * ANG(RAD(55), 0, 0)
		part(m, "FootPlate", V3(0.45, 0.06, 1.0), fcf, BLACK, M.Rubber)
		part(m, "HeelCup", V3(0.45, 0.2, 0.1), fcf * CF(0, 0.08, 0.45), BLACK, M.Rubber)
		part(m, "FootStrap", V3(0.5, 0.1, 0.22), fcf * CF(0, 0.07, -0.05), lv >= 2 and accent or BLACK, M.Fabric)
	end
	-- resistance: rusty flywheel, air fan behind a grille, or a water tank with paddles
	local parts = {}
	if lv == 1 then
		local fc = at(0, 1.3, -3.6)
		local wheel = cyl(m, "Flywheel", 0.3, 1.8, fc, RUST, M.Metal)
		table.insert(parts, { p = wheel, base = wheel.CFrame, speed = 12 })
		for k = 0, 1 do
			local spoke = part(m, "Spoke", V3(0.34, 1.7, 0.14), fc * ANG(k * math.pi / 2, 0, 0), rgb(90, 60, 40), M.Metal)
			table.insert(parts, { p = spoke, base = spoke.CFrame, speed = 12 })
		end
		for _, x in ipairs({ -0.25, 0.25 }) do
			beam(m, "WheelStay", o + V3(x, 0.25, -3.6), o + V3(x, 1.3, -3.6), 0.12, 0.12, frameC, M.Metal)
		end
	elseif lv == 2 then
		local fc = at(0, 1.4, -3.6)
		cyl(m, "FanHousing", 1.0, 2.6, fc, BLACK, M.Metal)
		cyl(m, "Grille", 0.04, 2.0, fc * CF(0.52, 0, 0), rgb(60, 60, 66), M.DiamondPlate)
		for k = 0, 2 do
			local blade = part(m, "FanBlade", V3(0.05, 1.8, 0.2), fc * CF(0.56, 0, 0) * ANG(k * math.pi / 3, 0, 0), STEEL, M.Metal)
			table.insert(parts, { p = blade, base = blade.CFrame, speed = 12 })
		end
		part(m, "DamperLever", V3(0.08, 0.5, 0.12), fc * CF(0.6, 0.8, 0) * ANG(RAD(20), 0, 0), accent, M.SmoothPlastic)
		for _, x in ipairs({ -0.45, 0.45 }) do
			beam(m, "HousingLeg", o + V3(x, 0.25, -3.3), o + V3(x, 0.9, -3.4), 0.15, 0.15, frameC, M.Metal)
		end
	else
		local tc = at(0, 1.0, -3.6)
		part(m, "TankBase", V3(3.0, 0.2, 3.0), at(0, 0.3, -3.6), WOOD, M.Wood)
		cyl(m, "WaterTank", 1.2, 2.8, tc * ANG(0, 0, RAD(90)), rgb(90, 160, 220), M.Glass, { transparency = 0.45 })
		cyl(m, "Water", 0.8, 2.6, at(0, 0.85, -3.6) * ANG(0, 0, RAD(90)), rgb(60, 140, 210), M.Glass, { transparency = 0.35 })
		cyl(m, "TankLid", 0.08, 2.9, at(0, 1.62, -3.6) * ANG(0, 0, RAD(90)), DARK, M.SmoothPlastic)
		for k = 0, 1 do
			local blade = part(m, "Paddle", V3(2.3, 0.55, 0.1), tc * ANG(0, k * math.pi / 2, 0), WHITE, M.SmoothPlastic)
			table.insert(parts, { p = blade, base = blade.CFrame, speed = 5, axis = "Y" })
		end
	end
	-- resting handle and its chain/strap (hidden while you row: you hold your own handle)
	local handle = Instance.new("Model")
	handle.Name = "RowHandle"
	handle.Parent = m
	local hy, hz = 1.25, -2.25
	if lv == 3 then
		hy, hz = 1.45, -2.05
	end
	cyl(handle, "Handle", 1.5, 0.2, at(0, hy, hz), lv == 3 and WOOD or BLACK, lv == 3 and M.Wood or M.SmoothPlastic)
	for _, x in ipairs({ -0.55, 0.55 }) do
		cyl(handle, "HandleGrip", 0.45, 0.24, at(x, hy, hz), FOAM, M.Rubber)
	end
	rod(handle, lv == 1 and "Chain" or "Strap", o + V3(0, hy, hz - 0.1), o + V3(0, 1.3, lv == 3 and -2.3 or -2.95), 0.07, lv == 1 and RUST or BLACK, lv == 1 and M.Metal or M.Fabric)
	-- monitor on its arm
	local armA = ({ V3(0, 0.6, -2.55), V3(0, 2.6, -3.3), V3(0, 1.62, -2.4) })[lv] or V3(0, 0.6, -2.55)
	local monY = lv == 2 and 3.1 or 2.9
	beam(m, "MonitorArm", o + armA, o + V3(0, monY - 0.3, -3.05), 0.14, 0.14, frameC, lv == 3 and M.Wood or M.Metal)
	local mon = part(m, "Monitor", V3(1.2, 0.9, 0.2), at(0, monY, -3.0) * ANG(RAD(-20), 0, 0), BLACK, M.SmoothPlastic)
	local display = surfaceText(mon, Enum.NormalId.Back, ({ "0:00\n0 m", "500m 2:00\nSPM 24", "WATER\n0 m" })[lv] or "0 m", rgb(120, 230, 255), rgb(8, 10, 14), 50)
	return { kind = "spinner", parts = parts, angle = 0, display = display, rackBar = handle, plaque = O * CF(2.4, 2.4, 3.2) }
end

B.rope = function(m, O, lv, cond, rng)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	if lv == 1 then
		cyl(m, "ChalkCircle", 0.02, 6, at(0, 0.02, 0) * ANG(0, 0, RAD(90)), WHITE, M.SmoothPlastic, { transparency = 0.5 })
		scuffs(m, O, 3, 0, 0, 1.2, 1.2, 0.035, rng)
	else
		local matC = ({ BLACK, BLACK, rgb(30, 60, 150), rgb(20, 20, 24) })[lv] or BLACK
		if lv >= 3 then
			part(m, "MatBorder", V3(6.3, 0.09, 6.3), at(0, 0.045, 0), lv >= 4 and GOLD or WHITE, M.SmoothPlastic)
		end
		part(m, "Mat", V3(6, 0.1, 6), at(0, 0.05, 0), wear(matC, cond, 0.3), M.Rubber)
		if lv >= 3 then
			-- painted jump zone ring
			cyl(m, "JumpZone", 0.01, 3.2, at(0, 0.105, 0) * ANG(0, 0, RAD(90)), lv >= 4 and GOLD or rgb(240, 120, 20), M.SmoothPlastic)
			cyl(m, "JumpZoneInner", 0.012, 3.0, at(0, 0.106, 0) * ANG(0, 0, RAD(90)), wear(matC, cond, 0.3), M.Rubber)
		end
		scuffs(m, O, 1 + math.floor((100 - cond) / 30), 0, 0, 1.0, 1.0, 0.11, rng)
		if lv >= 4 then
			local logo = part(m, "MatLogo", V3(3, 0.02, 3), at(0, 0.11, 0), Color3.new(), M.SmoothPlastic, { transparency = 1 })
			surfaceText(logo, Enum.NormalId.Top, "WCB", GOLD, nil, 40)
		end
		bottle(m, at(1.5, 0, -3.1), rgb(40, 120, 220))
		towel(m, at(-1.3, 0.07, -3.0) * ANG(0, RAD(12), 0), WHITE, 1.0, 0.7)
	end
	-- rope hanger: foot, post, bar with pegs (and a round timer on top from level 2)
	local hz = -3.6
	part(m, "HangerFoot", V3(1.8, 0.12, 1.0), at(0, 0.06, hz), BLACK, M.Metal)
	part(m, "HangerPost", V3(0.25, 6.0, 0.25), at(0, 3.0, hz), BLACK, M.Metal)
	part(m, "Hanger", V3(2.8, 0.2, 0.2), at(0, 6.0, hz), BLACK, M.Metal)
	if lv >= 2 then
		local t = part(m, "RoundTimer", V3(1.2, 0.6, 0.25), at(0, 6.45, hz), BLACK, M.SmoothPlastic)
		surfaceText(t, Enum.NormalId.Back, "0:30", rgb(255, 60, 50), BLACK, 60)
	end
	local kinds = { -- handle colour, rope colours (beads alternate), rope thickness
		{ WHITE, { rgb(40, 140, 60) }, 0.05 },
		{ rgb(60, 60, 66), { BLACK }, 0.035 },
		{ BLACK, { rgb(200, 30, 35) }, 0.08 },
		{ GOLD, { RED, WHITE, RED, WHITE }, 0.06 },
	}
	-- the middle rope is yours: it leaves the hanger while you skip
	local held = Instance.new("Model")
	held.Name = "RopeSet"
	held.Parent = m
	local function hangRope(model, x, kind)
		local k = kinds[kind] or kinds[1]
		cyl(m, "Peg", 0.35, 0.08, at(x, 5.95, hz + 0.27) * ANG(0, RAD(90), 0), CHROME, M.Metal)
		for _, dx in ipairs({ -0.12, 0.12 }) do
			cyl(model, "RopeHandle", 0.75, 0.16, at(x + dx, 5.55, hz + 0.22) * ANG(0, 0, RAD(90)), k[1], M.SmoothPlastic)
			local n = #k[2]
			local seg = 2.3 / n
			for j = 1, n do
				part(model, "RopeStrand", V3(k[3], seg, k[3]), at(x + dx * 0.8, 5.18 - (j - 0.5) * seg, hz + 0.22), k[2][j], M.Fabric)
			end
		end
		part(model, "RopeLoop", V3(0.26, k[3], k[3]), at(x, 2.88, hz + 0.22), k[2][#k[2]], M.Fabric)
	end
	hangRope(held, 0, lv)
	if lv >= 2 then
		hangRope(m, -0.9, lv - 1)
	end
	if lv >= 3 then
		hangRope(m, 0.9, 1)
		-- technique chart on a stand, angled at you
		local wc = at(-3.7, 0, -2.4) * ANG(0, RAD(55), 0)
		local board = part(m, "WallChart", V3(2.2, 2.8, 0.08), wc * CF(0, 3.7, 0), WHITE, M.SmoothPlastic)
		surfaceText(board, Enum.NormalId.Back, "JUMP ROPE\nBASIC BOUNCE\nBOXER SKIP\nHIGH KNEES\nDOUBLE UNDER\nCRISS-CROSS", rgb(30, 30, 34), WHITE, 40)
		for _, x in ipairs({ -0.95, 0.95 }) do
			part(m, "ChartLeg", V3(0.1, 5.1, 0.1), wc * CF(x, 2.55, -0.08), BLACK, M.Metal)
		end
	end
	return { rackBar = held, plaque = O * CF(3.8, 2.4, 1) }
end

B.ladder = function(m, O, lv, cond, rng)
	-- the smart level shortens the ladder so the reaction pods can sit around you
	local L = lv >= 4 and 10 or 12
	local c = O * CF(0, 0.03, lv >= 4 and -2 or 0)
	local orange = rgb(240, 120, 20)
	if lv == 1 then
		for i = 0, 8 do
			part(m, "ChalkLine", V3(2.2, 0.03, 0.12), c * CF(rng:NextNumber(-0.1, 0.1), 0, -L / 2 + i * (L / 8)) * ANG(0, RAD(rng:NextNumber(-3, 3)), 0), WHITE, M.SmoothPlastic, { transparency = 0.3 })
		end
		for _, x in ipairs({ -1.1, 1.1 }) do
			part(m, "ChalkSide", V3(0.1, 0.03, L), c * CF(x, 0, 0), WHITE, M.SmoothPlastic, { transparency = 0.55 })
		end
		part(m, "ChalkStick", V3(0.4, 0.12, 0.12), O * CF(1.8, 0.06, 6.4) * ANG(0, RAD(30), 0), WHITE, M.Sand)
	else
		local rungC = lv >= 3 and orange or rgb(240, 210, 40)
		for _, x in ipairs({ -1.1, 1.1 }) do
			part(m, "Strap", V3(0.12, 0.05, L), c * CF(x, 0, 0), BLACK, M.Fabric)
			for _, s in ipairs({ -1, 1 }) do
				part(m, "StrapEnd", V3(0.22, 0.07, 0.3), c * CF(x, 0.01, s * (L / 2 + 0.1)), BLACK, M.SmoothPlastic)
			end
		end
		for i = 0, 8 do
			part(m, "Rung", V3(2.2, 0.08, 0.2), c * CF(0, 0, -L / 2 + i * (L / 8)), rungC, M.SmoothPlastic)
		end
	end
	if lv >= 3 then
		-- stepped training cones and a lane of mini hurdles
		for _, z in ipairs({ -4.4, -0.4, 3.4 }) do
			for _, x in ipairs({ -2.6, 2.6 }) do
				local b = O * CF(x, 0, z)
				part(m, "ConeBase", V3(0.75, 0.06, 0.75), b * CF(0, 0.03, 0), orange, M.SmoothPlastic)
				vcyl(m, "Cone", 0.45, 0.52, b * CF(0, 0.06, 0), orange, M.SmoothPlastic)
				vcyl(m, "ConeStripe", 0.12, 0.4, b * CF(0, 0.51, 0), WHITE, M.SmoothPlastic)
				vcyl(m, "ConeTip", 0.35, 0.26, b * CF(0, 0.63, 0), orange, M.SmoothPlastic)
			end
		end
		for _, z in ipairs({ -4, -1.5, 1 }) do
			local h = O * CF(-4.0, 0, z)
			local hc = lv >= 4 and YELLOW or orange
			for _, x in ipairs({ -0.5, 0.5 }) do
				part(m, "HurdleLeg", V3(0.08, 0.5, 0.35), h * CF(x, 0.25, 0), hc, M.SmoothPlastic)
			end
			part(m, "HurdleBar", V3(1.08, 0.08, 0.08), h * CF(0, 0.5, 0), hc, M.SmoothPlastic)
		end
	end
	local lights = {}
	if lv >= 4 then
		-- plyo box, and the reaction-light controller on a tripod
		local pb = O * CF(3.9, 0, -5.0)
		part(m, "PlyoBox", V3(2.0, 1.6, 1.6), pb * CF(0, 0.8, 0), WOOD, M.Wood)
		part(m, "PlyoTop", V3(2.04, 0.08, 1.64), pb * CF(0, 1.6, 0), BLACK, M.Rubber)
		part(m, "PlyoHandle", V3(0.6, 0.2, 0.02), pb * CF(0, 1.15, 0.8), DARK, M.SmoothPlastic)
		local tp = O * CF(-3.6, 0, 7.6)
		vcyl(m, "TripodPost", 3.4, 0.1, tp, BLACK, M.Metal)
		for k = 0, 2 do
			local a = k * math.pi * 2 / 3
			beam(m, "TripodLeg", (tp * CF(0, 1.2, 0)).Position, (tp * CF(math.cos(a) * 0.6, 0, math.sin(a) * 0.6)).Position, 0.06, 0.06, BLACK, M.Metal)
		end
		local tab = part(m, "Tablet", V3(0.9, 0.6, 0.06), tp * CF(0, 3.5, 0) * ANG(0, RAD(107), 0), DARK, M.SmoothPlastic)
		surfaceText(tab, Enum.NormalId.Back, "REACT\nREADY", rgb(80, 220, 255), DARK, 50)
		-- reaction pods around where you stand: forward, right, left, back (matches the drill's cues)
		local spots = { { 0, 4.3 }, { 2.3, 6.5 }, { -2.3, 6.5 }, { 0, 8.7 } }
		for i, s in ipairs(spots) do
			cyl(m, "PodBase", 0.08, 1.4, O * CF(s[1], 0.04, s[2]) * ANG(0, 0, RAD(90)), DARK, M.SmoothPlastic)
			lights[i] = cyl(m, "LightPad", 0.12, 1.1, O * CF(s[1], 0.1, s[2]) * ANG(0, 0, RAD(90)), rgb(40, 40, 46), M.Neon)
		end
	end
	return { lights = lights, plaque = O * CF(3.6, 2.4, 6) }
end

B.icebath = function(m, O, lv, cond, rng)
	local tubC = ({ rgb(60, 120, 200), CHROME, WHITE })[lv] or CHROME
	local W, L, H = 3.2, 4.8, 2.4
	local cz = -0.4
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local mat = lv == 2 and M.Metal or M.SmoothPlastic
	part(m, "TubFloor", V3(W, 0.35, L), at(0, 0.18, cz), tubC, mat, { collide = true })
	for _, s in ipairs({ { 0, -1, W, 0.25 }, { 0, 1, W, 0.25 }, { -1, 0, 0.25, L }, { 1, 0, 0.25, L } }) do
		part(m, "TubWall", V3(s[3], H, s[4]), at(s[1] * (W / 2 - 0.12), H / 2, cz + s[2] * (L / 2 - 0.12)), tubC, mat, { collide = true, reflect = lv >= 2 and 0.15 or 0 })
	end
	-- rolled rim around the top edge
	local rimC = lv == 1 and wear(rgb(50, 105, 180), cond, 0.3) or (lv == 2 and CHROME or rgb(220, 225, 232))
	for _, s in ipairs({ { 0, -1, W + 0.2, 0.4 }, { 0, 1, W + 0.2, 0.4 }, { -1, 0, 0.4, L - 0.6 }, { 1, 0, 0.4, L - 0.6 } }) do
		part(m, "TubRim", V3(s[3], 0.16, s[4]), at(s[1] * (W / 2 - 0.1), H + 0.08, cz + s[2] * (L / 2 - 0.1)), rimC, lv == 2 and M.Metal or M.SmoothPlastic)
	end
	part(m, "Water", V3(W - 0.5, 1.6, L - 0.5), at(0, 1.15, cz), rgb(120, 190, 235), M.Glass, { transparency = 0.55 })
	for _ = 1, ({ 9, 7, 3 })[lv] or 5 do
		part(m, "Ice", V3(0.4, 0.3, 0.4), at(rng:NextNumber(-1, 1), 1.95, cz + rng:NextNumber(-1.8, 1.8)) * ANG(0, rng:NextNumber(0, 3), 0.2), rgb(230, 245, 255), M.Ice, { transparency = 0.25 })
	end
	-- floating thermometer
	part(m, "Thermometer", V3(0.18, 0.5, 0.18), at(-1.0, 1.98, cz - 1.85) * ANG(RAD(10), 0, 0), WHITE, M.SmoothPlastic, { ellipsoid = true })
	part(m, "ThermoLine", V3(0.04, 0.28, 0.02), at(-1.0, 2.0, cz - 1.76) * ANG(RAD(10), 0, 0), RED, M.Neon)
	if lv == 1 then
		part(m, "IceBag", V3(1.2, 0.5, 0.8), at(2.4, 0.25, -1.5), WHITE, M.Plastic)
		part(m, "IceBag", V3(1.1, 0.45, 0.75), at(2.5, 0.72, -1.4) * ANG(0, RAD(25), RAD(5)), WHITE, M.Plastic)
		vcyl(m, "Bucket", 0.9, 0.85, at(2.4, 0, 0.6), rgb(230, 120, 30), M.SmoothPlastic)
		return { plaque = O * CF(-3, 2.4, 2) }
	end
	-- drain valve, step stool on the exit side, towel rack behind
	cyl(m, "Drain", 0.08, 0.3, at(W / 2 + 0.02, 0.5, cz + 1.6), CHROME, M.Metal)
	part(m, "DrainHandle", V3(0.06, 0.3, 0.08), at(W / 2 + 0.08, 0.6, cz + 1.6), RED, M.SmoothPlastic)
	local stepC = lv == 2 and WOOD or WHITE
	part(m, "StepHigh", V3(0.5, 1.1, 1.1), at(1.87, 0.55, 0.6), stepC, lv == 2 and M.WoodPlanks or M.SmoothPlastic)
	part(m, "StepLow", V3(0.6, 0.55, 1.1), at(2.42, 0.275, 0.6), stepC, lv == 2 and M.WoodPlanks or M.SmoothPlastic)
	for _, x in ipairs({ -1.2, 1.2 }) do
		part(m, "RackPost", V3(0.15, 3.2, 0.15), at(x, 1.6, -3.6), lv == 2 and CHROME or WHITE, M.Metal)
	end
	for _, y in ipairs({ 2.2, 3.0 }) do
		cyl(m, "RackBar", 2.6, 0.1, at(0, y, -3.6), lv == 2 and CHROME or WHITE, M.Metal)
	end
	part(m, "Towel", V3(1.4, 1.1, 0.1), at(-0.3, 2.5, -3.6), lv == 2 and rgb(40, 90, 170) or WHITE, M.Fabric)
	if lv >= 3 then
		-- LED strips inside the rim, chiller unit with display and hoses
		for _, s in ipairs({ { 0, -1, W - 0.5, 0.06 }, { 0, 1, W - 0.5, 0.06 }, { -1, 0, 0.06, L - 0.5 }, { 1, 0, 0.06, L - 0.5 } }) do
			local strip = part(m, "LEDStrip", V3(s[3], 0.06, s[4]), at(s[1] * (W / 2 - 0.27), H - 0.15, cz + s[2] * (L / 2 - 0.27)), rgb(80, 200, 255), M.Neon)
			if s[2] == 1 then
				light(strip, rgb(80, 200, 255), 10, 0.8)
			end
		end
		local ch = at(-2.7, 0, -1.8)
		part(m, "Chiller", V3(1.4, 2.6, 1.6), ch * CF(0, 1.3, 0), WHITE, M.SmoothPlastic)
		part(m, "ChillerVent", V3(0.04, 1.2, 1.2), ch * CF(-0.72, 1.1, 0), DARK, M.DiamondPlate)
		part(m, "ChillerLED", V3(0.12, 0.12, 0.04), ch * CF(0.45, 2.45, 0.81), rgb(60, 230, 120), M.Neon)
		local d = part(m, "TempDisplay", V3(0.9, 0.5, 0.04), ch * CF(-0.1, 2.1, 0.81), BLACK, M.SmoothPlastic)
		surfaceText(d, Enum.NormalId.Back, "3.0°C\nCRYO", rgb(80, 220, 255), BLACK, 50)
		rod(m, "Hose", o + V3(-2.0, 0.6, -2.2), o + V3(-1.55, 0.6, -2.2), 0.15, BLACK, M.Rubber)
		rod(m, "Hose", o + V3(-2.3, 2.6, -1.5), o + V3(-1.4, 2.75, -1.5), 0.15, BLACK, M.Rubber)
		rod(m, "Hose", o + V3(-1.4, 2.75, -1.5), o + V3(-1.2, 1.8, -1.5), 0.15, BLACK, M.Rubber)
	end
	return { plaque = O * CF(-3, 2.4, 2) }
end

B.stretch = function(m, O, lv, cond, rng)
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	part(m, "Mat", V3(3, 0.08, 6), at(0, 0.04, 0), wear(lv >= 2 and rgb(110, 60, 160) or rgb(70, 90, 110), cond, 0.3), M.Rubber)
	if lv == 1 then
		-- thin old mat with a curled corner, rolled towel for a pillow
		part(m, "CurledCorner", V3(0.6, 0.18, 0.5), at(1.2, 0.09, -2.75) * ANG(0, RAD(180), 0), wear(rgb(70, 90, 110), cond, 0.3), M.Rubber, { wedge = true })
		cyl(m, "RolledTowel", 1.2, 0.4, at(0, 0.28, -2.4), wear(WHITE, cond, 0.5), M.Fabric)
		bottle(m, at(2.0, 0, 1.6), rgb(200, 215, 230))
		return { plaque = O * CF(-2.6, 2.4, 3) }
	end
	-- yoga studio: wood floor, two mats and a rolled spare, rollers, ball, blocks, bands, wall bars, plant
	part(m, "StudioFloor", V3(10.2, 0.04, 8.4), at(1.0, 0.02, -0.4), rgb(176, 132, 86), M.WoodPlanks)
	part(m, "Mat2", V3(3, 0.08, 6), at(3.6, 0.04, 0), rgb(40, 140, 120), M.Rubber)
	cyl(m, "RolledMat", 3.0, 0.5, at(3.6, 0.29, -3.7), rgb(240, 120, 60), M.Rubber)
	cyl(m, "FoamRoller", 2, 0.6, at(-2.6, 0.34, 1), rgb(30, 80, 160), M.Rubber)
	cyl(m, "GridRoller", 1.4, 0.5, at(-2.6, 0.29, 2.0), rgb(240, 120, 20), M.DiamondPlate)
	part(m, "Ball", V3(2.2, 2.2, 2.2), at(-2.8, 1.14, -2), rgb(200, 60, 60), M.SmoothPlastic, { shape = Enum.PartType.Ball })
	part(m, "YogaBlock", V3(0.9, 0.45, 0.6), at(1.95, 0.265, 2.5), rgb(150, 110, 190), M.SmoothPlastic)
	part(m, "YogaBlock", V3(0.9, 0.45, 0.6), at(1.95, 0.715, 2.5) * ANG(0, RAD(14), 0), rgb(200, 160, 110), M.Wood)
	-- resistance bands on a rack with posts
	part(m, "BandRack", V3(2.6, 0.2, 0.2), at(5.6, 5, -3), BLACK, M.Metal)
	for _, x in ipairs({ 4.4, 6.8 }) do
		part(m, "BandPost", V3(0.18, 5.1, 0.18), at(x, 2.55, -3), BLACK, M.Metal)
	end
	for i = 0, 2 do
		part(m, "Band", V3(0.12, 2.4, 0.06), at(4.8 + i * 0.8, 3.8, -2.92), ({ rgb(240, 200, 40), rgb(200, 40, 40), rgb(40, 120, 220) })[i + 1], M.Rubber)
	end
	-- Swedish wall bars behind the main mat
	for _, x in ipairs({ -1.4, 1.4 }) do
		part(m, "WallBarSide", V3(0.25, 7.5, 0.3), at(x, 3.75, -3.95), WOOD, M.Wood)
	end
	for i = 0, 7 do
		cyl(m, "WallBarRung", 2.6, 0.16, at(0, 0.8 + i * 0.85, -3.95), rgb(190, 150, 100), M.Wood)
	end
	vcyl(m, "PlantPot", 0.9, 0.9, at(5.4, 0, 2.6), rgb(235, 235, 230), M.SmoothPlastic)
	part(m, "Plant", V3(1.6, 1.8, 1.6), at(5.4, 1.75, 2.6), rgb(60, 130, 60), M.Grass, { ellipsoid = true })
	return { plaque = O * CF(-2.6, 2.4, 3) }
end

B.sauna = function(m, O, lv, cond, rng)
	local seat = 1.6
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local dark = rgb(95, 66, 42)
	-- bench along the back wall (the boxer sits facing the door)
	part(m, "Bench", V3(6.4, 0.3, 1.6), at(0, seat - 0.15, -2.9), WOOD, M.WoodPlanks, { collide = true })
	for _, x in ipairs({ -2.8, 2.8 }) do
		part(m, "BenchLeg", V3(0.3, seat - 0.3, 1.4), at(x, (seat - 0.3) / 2, -2.9), WOOD, M.Wood)
	end
	if lv == 1 then
		local heater = part(m, "SpaceHeater", V3(1.2, 1.6, 0.8), at(2.6, 0.8, -0.6), WHITE, M.SmoothPlastic)
		local glow = part(m, "Coil", V3(0.9, 1.0, 0.05), at(2.6, 0.9, -0.19), rgb(255, 120, 40), M.Neon)
		light(glow, rgb(255, 140, 60), 8, 0.8)
		local sign = part(m, "Sign", V3(3, 0.8, 0.1), at(0, 4.2, -3.8), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, "SAUNA SUIT CORNER", rgb(255, 160, 80), BLACK, 50)
		part(m, "BackWall", V3(7, 4.8, 0.3), at(0, 2.4, -4), WOOD, M.WoodPlanks, { collide = true })
		part(m, "WallTrim", V3(7.2, 0.25, 0.4), at(0, 4.9, -4), dark, M.Wood)
		-- silver sauna suit on a hook, scale on the floor, jug and towel on the bench
		part(m, "Hook", V3(0.15, 0.15, 0.3), at(-2.2, 3.85, -3.75), STEEL, M.Metal)
		part(m, "SuitTorso", V3(1.2, 1.4, 0.3), at(-2.2, 3.05, -3.7), rgb(190, 192, 200), M.Foil)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "SuitSleeve", V3(0.35, 1.1, 0.28), at(-2.2 + sx * 0.72, 2.95, -3.7) * ANG(0, 0, RAD(sx * 12)), rgb(180, 182, 190), M.Foil)
		end
		part(m, "Scale", V3(1.0, 0.12, 1.0), at(-2.4, 0.06, 0.6), WHITE, M.SmoothPlastic)
		cyl(m, "ScaleDial", 0.02, 0.4, at(-2.4, 0.13, 0.35) * ANG(0, 0, RAD(90)), BLACK, M.SmoothPlastic)
		vcyl(m, "WaterJug", 0.8, 0.5, at(-2.9, seat, -3.3), rgb(200, 215, 230), M.SmoothPlastic)
		towel(m, at(2.0, seat + 0.06, -2.8), wear(WHITE, cond, 0.5))
		return { plaque = O * CF(4.4, 2.4, 2), heater = heater }
	end
	local H = 8
	part(m, "Wall", V3(8.4, H, 0.3), at(0, H / 2, -4.1), WOOD, M.WoodPlanks, { collide = true })
	part(m, "Wall", V3(0.3, H, 8.4), at(4.1, H / 2, 0), WOOD, M.WoodPlanks, { collide = true })
	-- the -X wall has a big window (a full glass wall on the infrared sauna)
	if lv >= 3 then
		part(m, "GlassWall", V3(0.1, 7.6, 8.0), at(-4.1, 4.0, 0), rgb(200, 220, 230), M.Glass, { collide = true, transparency = 0.6 })
		part(m, "GlassRail", V3(0.36, 0.3, 8.4), at(-4.1, 0.15, 0), BLACK, M.Metal, { collide = true })
		part(m, "GlassRail", V3(0.36, 0.3, 8.4), at(-4.1, H - 0.15, 0), BLACK, M.Metal)
		for _, z in ipairs({ -4.05, 0, 4.05 }) do
			part(m, "GlassPost", V3(0.36, H, 0.3), at(-4.1, H / 2, z), BLACK, M.Metal)
		end
	else
		part(m, "Wall", V3(0.3, 2.5, 8.4), at(-4.1, 1.25, 0), WOOD, M.WoodPlanks, { collide = true })
		part(m, "Wall", V3(0.3, 1.2, 8.4), at(-4.1, 7.4, 0), WOOD, M.WoodPlanks, { collide = true })
		part(m, "Wall", V3(0.3, 4.3, 0.6), at(-4.1, 4.65, -3.9), WOOD, M.WoodPlanks, { collide = true })
		part(m, "Wall", V3(0.3, 4.3, 3.4), at(-4.1, 4.65, 2.5), WOOD, M.WoodPlanks, { collide = true })
		part(m, "Window", V3(0.08, 4.3, 4.4), at(-4.1, 4.65, -1.4), rgb(200, 220, 230), M.Glass, { collide = true, transparency = 0.5 })
		for _, e in ipairs({ { 2.43, 4.6, 0.15 }, { 6.87, 4.6, 0.15 } }) do
			part(m, "WindowFrame", V3(0.36, e[3], e[2]), at(-4.1, e[1], -1.4), dark, M.Wood)
		end
		for _, z in ipairs({ -3.67, 0.87 }) do
			part(m, "WindowFrame", V3(0.36, 4.5, 0.15), at(-4.1, 4.65, z), dark, M.Wood)
		end
		for _, x in ipairs({ -4.1, 4.1 }) do
			part(m, "CornerPost", V3(0.4, H, 0.4), at(x, H / 2, -4.1), dark, M.Wood)
		end
	end
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(m, "FrontWall", V3(3.2, H, 0.3), at(x, H / 2, 4.1), WOOD, M.WoodPlanks, { collide = true })
	end
	part(m, "Lintel", V3(2, 1.6, 0.3), at(0, H - 0.8, 4.1), WOOD, M.WoodPlanks)
	part(m, "Roof", V3(8.6, 0.3, 8.6), at(0, H + 0.15, 0), WOOD, M.WoodPlanks)
	part(m, "RoofTrim", V3(8.9, 0.2, 8.9), at(0, H + 0.4, 0), dark, M.Wood)
	-- door frame and the door standing open (with a small glass window)
	for _, x in ipairs({ -1.05, 1.05 }) do
		part(m, "DoorJamb", V3(0.2, 6.4, 0.4), at(x, 3.2, 4.1), dark, M.Wood)
	end
	part(m, "DoorHead", V3(2.3, 0.2, 0.4), at(0, 6.4, 4.1), dark, M.Wood)
	local door = at(1.0, 3.2, 4.3) * ANG(0, RAD(100), 0) * CF(-0.95, 0, 0)
	part(m, "Door", V3(1.9, 6.3, 0.15), door, WOOD, M.WoodPlanks)
	part(m, "DoorWindow", V3(0.8, 1.6, 0.17), door * CF(0, 1.4, 0), rgb(200, 220, 230), M.Glass, { transparency = 0.4 })
	part(m, "DoorHandle", V3(0.08, 0.6, 0.3), door * CF(-0.75, 0, 0), dark, M.Wood)
	-- upper bench on legs, slatted backrest under its front edge
	part(m, "UpperBench", V3(6.4, 0.25, 0.8), at(0, 3.6, -3.6), WOOD, M.WoodPlanks)
	for _, x in ipairs({ -2.8, 2.8 }) do
		part(m, "UpperLeg", V3(0.25, 3.475, 0.25), at(x, 3.475 / 2, -3.7), WOOD, M.Wood)
	end
	for _, y in ipairs({ 2.05, 2.5, 2.95 }) do
		part(m, "Backrest", V3(6.2, 0.3, 0.08), at(0, y, -3.25), rgb(160, 118, 78), M.Wood)
	end
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(m, "BackrestBatten", V3(0.15, 1.875, 0.1), at(x, seat + 0.9375, -3.34), dark, M.Wood)
	end
	-- stove: steel body, glowing coals under a pile of stones, wooden guard rails
	part(m, "StoveBody", V3(1.4, 1.5, 1.4), at(-3, 0.75, 2.6), rgb(50, 50, 55), M.Metal)
	local glow = part(m, "HeaterGlow", V3(1.3, 0.06, 1.3), at(-3, 1.52, 2.6), rgb(255, 110, 40), M.Neon)
	light(glow, rgb(255, 150, 80), 12, 1.0)
	local stones
	for i = 1, 6 do
		local a = i * math.pi / 3
		local s = part(m, "Stones", V3(0.55, 0.42, 0.5), at(-3 + math.cos(a) * 0.38, 1.68 + (i % 2) * 0.12, 2.6 + math.sin(a) * 0.38) * ANG(0, a, 0), ({ rgb(80, 80, 85), rgb(105, 100, 98), rgb(70, 68, 72) })[i % 3 + 1], M.Slate, { ellipsoid = true })
		stones = stones or s
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Rate = 6
	steam.Lifetime = NumberRange.new(2, 3.5)
	steam.Speed = NumberRange.new(1, 2)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.Transparency = NumberSequence.new(0.7, 1)
	steam.Size = NumberSequence.new(1, 3)
	steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	steam.Parent = stones
	part(m, "StoveGuard", V3(0.12, 0.12, 1.9), at(-2.05, 1.25, 2.6), dark, M.Wood)
	part(m, "StoveGuard", V3(1.9, 0.12, 0.12), at(-3, 1.25, 1.65), dark, M.Wood)
	-- bucket and ladle
	vcyl(m, "Bucket", 0.7, 0.8, at(-1.6, 0, 3.1), WOOD, M.Wood)
	for _, y in ipairs({ 0.12, 0.52 }) do
		vcyl(m, "BucketBand", 0.06, 0.84, at(-1.6, y, 3.1), STEEL, M.Metal)
	end
	beam(m, "Ladle", o + V3(-1.6, 0.6, 3.1), o + V3(-1.05, 1.15, 3.35), 0.07, 0.07, dark, M.Wood)
	vcyl(m, "LadleCup", 0.16, 0.26, at(-1.6, 0.52, 3.1), STEEL, M.Metal)
	-- thermometer / hygrometer on the side wall, lamp on the back wall
	part(m, "GaugeBoard", V3(0.06, 1.4, 0.8), at(3.92, 4.6, 1.5), dark, M.Wood)
	for i, e in ipairs({ { 5.0, "90°C" }, { 4.25, "10%" } }) do
		local dial = cyl(m, "Gauge", 0.06, i == 1 and 0.6 or 0.5, at(3.87, e[1], 1.5), rgb(240, 236, 225), M.SmoothPlastic)
		tag(dial, Enum.NormalId.Left, e[2], BLACK, 0.7, 0.4)
	end
	part(m, "LampShade", V3(1.2, 0.5, 0.3), at(2.2, 6.7, -3.88), dark, M.Wood)
	part(m, "LampGlow", V3(1.0, 0.06, 0.2), at(2.2, 6.44, -3.86), rgb(255, 190, 120), M.Neon)
	if lv >= 3 then
		local panels = { { V3(0.1, 3, 2.4), at(3.9, 3.4, -1.4) }, { V3(2.4, 1.6, 0.1), at(-1.2, 5.5, -3.9) } }
		for _, pnl in ipairs(panels) do
			local panel = part(m, "Infrared", pnl[1], pnl[2], rgb(255, 50, 30), M.Neon, { transparency = 0.2 })
			light(panel, rgb(255, 60, 40), 10, 1.2)
		end
	end
	local sign = part(m, "Sign", V3(2.6, 0.7, 0.1), at(0, H + 0.8, 4.3), BLACK, M.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Back, lv >= 3 and "INFRARED SAUNA" or "SAUNA", rgb(255, 160, 80), BLACK, 50)
	return { plaque = O * CF(5.4, 2.4, 4.6) }
end

B.massage = function(m, O, lv, cond, rng)
	local top = 2.4
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	local padC = lv >= 2 and rgb(40, 30, 28) or wear(rgb(235, 232, 222), cond, 0.3)
	if lv == 1 then
		-- folding table: two hinged halves on aluminium legs, paper sheet, price board
		for _, s in ipairs({ -1, 1 }) do
			part(m, "Table", V3(2.3, 0.3, 3.15), at(0, top - 0.15, s * 1.625), padC, M.SmoothPlastic, { collide = true })
		end
		for _, x in ipairs({ -1.05, 1.05 }) do
			part(m, "SideRail", V3(0.1, 0.15, 6.2), at(x, top - 0.37, 0), STEEL, M.Metal)
		end
		for _, x in ipairs({ -0.9, 0.9 }) do
			for _, z in ipairs({ -2.8, 2.8 }) do
				part(m, "Leg", V3(0.2, top - 0.35, 0.2), at(x, (top - 0.35) / 2, z), CHROME, M.Metal, { collide = true })
				part(m, "LegFoot", V3(0.26, 0.08, 0.26), at(x, 0.04, z), BLACK, M.Rubber)
			end
			beam(m, "LegBrace", o + V3(x, 0.4, -2.7), o + V3(x, 1.9, 2.7), 0.08, 0.08, STEEL, M.Metal)
		end
		part(m, "PaperSheet", V3(1.6, 0.02, 5.0), at(0, top + 0.01, 0.2), WHITE, M.SmoothPlastic)
		local board = part(m, "PriceBoard", V3(1.4, 1.0, 0.06), at(2.8, 2.6, 2.4) * ANG(0, RAD(-20), 0), rgb(205, 170, 120), M.Wood)
		surfaceText(board, Enum.NormalId.Back, "MASSAGE\n$100 / SESSION", rgb(40, 30, 25), rgb(205, 170, 120), 40)
		for _, x in ipairs({ -0.5, 0.5 }) do
			part(m, "BoardLeg", V3(0.08, 2.2, 0.08), at(2.8, 0, 2.4) * ANG(0, RAD(-20), 0) * CF(x, 1.1, -0.06), WOOD, M.Wood)
		end
		bottle(m, at(2.2, 0, -2.2), rgb(240, 240, 235), 0.6)
	else
		-- therapist's table: thick stitched leather top on a wooden pedestal base
		part(m, "Table", V3(2.3, 0.35, 6.4), at(0, top - 0.18, 0), padC, M.Leather, { collide = true })
		for _, x in ipairs({ -1.13, 1.13 }) do
			part(m, "Piping", V3(0.05, 0.05, 6.36), at(x, top - 0.02, 0), rgb(150, 120, 80), M.Fabric)
		end
		for _, z in ipairs({ -2.6, 2.6 }) do
			part(m, "EndPanel", V3(1.8, top - 0.4, 0.3), at(0, (top - 0.4) / 2, z), WOOD, M.Wood, { collide = true })
		end
		part(m, "CentreBeam", V3(0.4, 0.3, 5.2), at(0, 0.6, 0), WOOD, M.Wood)
		part(m, "ArmShelf", V3(1.6, 0.1, 0.5), at(0, 1.55, -3.3), padC, M.Leather)
		for _, x in ipairs({ -0.3, 0.3 }) do
			part(m, "ShelfStrap", V3(0.05, 0.58, 0.05), at(x, 1.86, -3.3), BLACK, M.Fabric)
		end
	end
	part(m, "Towel", V3(2.0, 0.08, 1.6), at(0, top + 0.04, 2.4), WHITE, M.Fabric)
	-- face cradle: padded ring on two rods
	cyl(m, "FaceRest", 0.3, 1.0, at(0, top - 0.05, -3.5) * ANG(0, 0, RAD(90)), padC, M.Leather)
	cyl(m, "FaceHole", 0.32, 0.42, at(0, top - 0.05, -3.5) * ANG(0, 0, RAD(90)), DARK, M.SmoothPlastic)
	for _, x in ipairs({ -0.3, 0.3 }) do
		beam(m, "CradleRod", o + V3(x, top - 0.3, -3.0), o + V3(x, top - 0.22, -3.5), 0.08, 0.08, lv >= 2 and WOOD or CHROME, M.Metal)
	end
	if lv >= 2 then
		-- wooden cart: two shelves on legs, oils, candle, rolled towels, diffuser
		local cart = at(2.6, 0, -2.4)
		for _, y in ipairs({ 0.6, 2.35 }) do
			part(m, "CartShelf", V3(1.4, 0.1, 1.2), cart * CF(0, y, 0), WOOD, M.Wood)
		end
		for _, sx in ipairs({ -0.62, 0.62 }) do
			for _, sz in ipairs({ -0.52, 0.52 }) do
				part(m, "CartLeg", V3(0.1, 2.4, 0.1), cart * CF(sx, 1.2, sz), WOOD, M.Wood)
			end
		end
		vcyl(m, "OilBottle", 0.6, 0.3, cart * CF(-0.2, 2.4, -0.2), rgb(230, 170, 60), M.Glass, { transparency = 0.3 })
		vcyl(m, "OilBottle", 0.5, 0.26, cart * CF(0.15, 2.4, -0.35), rgb(150, 200, 120), M.Glass, { transparency = 0.3 })
		local candle = vcyl(m, "Candle", 0.35, 0.35, cart * CF(0.3, 2.4, 0.2), WHITE, M.SmoothPlastic)
		light(candle, rgb(255, 190, 120), 8, 0.6)
		vcyl(m, "Diffuser", 0.4, 0.4, cart * CF(-0.3, 2.4, 0.3), rgb(235, 230, 220), M.SmoothPlastic)
		for i = 0, 2 do
			cyl(m, "RolledTowel", 1.1, 0.34, cart * CF(0, 0.82, -0.36 + i * 0.36), WHITE, M.Fabric)
		end
		-- floor lamp with a warm shade
		local lamp = at(-3.8, 0, -3.6)
		vcyl(m, "LampBase", 0.08, 0.8, lamp, BLACK, M.Metal)
		vcyl(m, "LampPole", 4.6, 0.1, lamp, BLACK, M.Metal)
		vcyl(m, "LampShade", 0.8, 1.0, lamp * CF(0, 4.4, 0), rgb(240, 225, 195), M.Fabric)
		local bulb = part(m, "LampBulb", V3(0.4, 0.3, 0.4), lamp * CF(0, 4.5, 0), rgb(255, 210, 150), M.Neon, { ellipsoid = true })
		light(bulb, rgb(255, 200, 140), 12, 0.5)
		-- folding privacy screen behind the head end
		for i, x in ipairs({ -2.0, 0, 2.0 }) do
			part(m, "PrivacyScreen", V3(1.95, 5.0, 0.1), at(x, 2.5, -5.3) * ANG(0, RAD(i % 2 == 0 and 12 or -12), 0), rgb(225, 215, 195), M.Fabric)
		end
		vcyl(m, "PlantPot", 0.9, 0.9, at(3.6, 0, 2.8), rgb(120, 85, 60), M.SmoothPlastic)
		part(m, "Plant", V3(1.5, 1.9, 1.5), at(3.6, 1.8, 2.8), rgb(60, 130, 60), M.Grass, { ellipsoid = true })
	end
	return { plaque = O * CF(3.2, 2.4, 3) }
end

B.chamber = function(m, O, lv, cond, rng, ctx)
	local o = O.Position
	local function at(x, y, z)
		return O * CF(x, y, z)
	end
	if not ctx.ownsChamber then
		part(m, "Pedestal", V3(4, 1, 7), at(0, 0.5, 0.6), rgb(40, 40, 46), M.Marble, { collide = true })
		local sign = part(m, "LockedSign", V3(5, 2, 0.15), at(0, 3.2, -3), BLACK, M.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Back, "ELITE RECOVERY CHAMBER\nLOCKED - Shop > Elite Equipment\n(World Champions)", rgb(80, 200, 255), BLACK, 50)
		-- velvet rope in front, like a showroom exhibit
		for _, x in ipairs({ -2.0, 2.0 }) do
			local s = at(x, 0, 4.7)
			vcyl(m, "StanchionBase", 0.1, 0.8, s, GOLD, M.Metal)
			vcyl(m, "Stanchion", 2.7, 0.15, s, GOLD, M.Metal)
			part(m, "StanchionTop", V3(0.3, 0.3, 0.3), s * CF(0, 2.8, 0), GOLD, M.Metal, { shape = Enum.PartType.Ball })
		end
		rod(m, "VelvetRope", o + V3(-2.0, 2.6, 4.7), o + V3(0, 2.1, 4.7), 0.14, rgb(150, 20, 30), M.Fabric)
		rod(m, "VelvetRope", o + V3(0, 2.1, 4.7), o + V3(2.0, 2.6, 4.7), 0.14, rgb(150, 20, 30), M.Fabric)
		return {}
	end
	part(m, "PodBase", V3(3.4, 1.3, 7.2), at(0, 0.65, 0.6), WHITE, M.SmoothPlastic, { collide = true })
	part(m, "Bed", V3(2.4, 0.1, 6.6), at(0, 1.33, 0.6), rgb(60, 70, 90), M.Fabric)
	part(m, "Headrest", V3(1.6, 0.18, 0.9), at(0, 1.47, 3.4), rgb(70, 80, 105), M.Fabric)
	local dome = cyl(m, "Dome", 6.8, 3.2, at(0, 1.4, 0.6) * ANG(0, RAD(90), 0), rgb(160, 220, 255), M.Glass, { transparency = 0.7, shadow = false })
	dome.Size = V3(6.8, 3.2, 3.2)
	for _, s in ipairs({ -1, 1 }) do
		part(m, "DomeCap", V3(3.2, 3.2, 1.0), at(0, 1.4, 0.6 + s * 3.4), rgb(160, 220, 255), M.Glass, { transparency = 0.7, shadow = false, ellipsoid = true })
	end
	part(m, "DomeSpine", V3(0.3, 0.1, 6.8), at(0, 3.0, 0.6), WHITE, M.SmoothPlastic)
	for _, x in ipairs({ -1.75, 1.75 }) do
		local strip = part(m, "Neon", V3(0.08, 0.1, 6.8), at(x, 1.32, 0.6), rgb(60, 200, 255), M.Neon)
		light(strip, rgb(60, 200, 255), 8, 0.8)
	end
	-- glowing floor outline and status lights on the side of the pod
	for _, e in ipairs({ { 0, -3.15, 4.0, 0.08 }, { 0, 4.35, 4.0, 0.08 }, { -2.0, 0.6, 0.08, 7.5 }, { 2.0, 0.6, 0.08, 7.5 } }) do
		part(m, "FloorGlow", V3(e[3], 0.03, e[4]), at(e[1], 0.015, e[2]), rgb(60, 200, 255), M.Neon)
	end
	for i, c in ipairs({ rgb(60, 230, 120), rgb(60, 230, 120), rgb(60, 200, 255) }) do
		part(m, "StatusLight", V3(0.04, 0.14, 0.3), at(1.72, 0.95, -1.2 + i * 0.45), c, M.Neon)
	end
	-- life-support tower behind the pod, hoses into the pod
	part(m, "Tower", V3(2.2, 3.6, 1.0), at(0, 1.8, -4.8), WHITE, M.SmoothPlastic)
	local tscreen = part(m, "TowerScreen", V3(1.4, 0.8, 0.04), at(0, 2.7, -4.28), rgb(8, 12, 18), M.SmoothPlastic)
	surfaceText(tscreen, Enum.NormalId.Back, "O2 98%\nHR 52", rgb(80, 220, 255), rgb(8, 12, 18), 50)
	for i = 0, 2 do
		part(m, "TowerLight", V3(0.18, 0.18, 0.04), at(-0.4 + i * 0.4, 1.9, -4.28), i == 2 and rgb(60, 200, 255) or rgb(60, 230, 120), M.Neon)
	end
	for _, e in ipairs({ { -0.6, 0.8 }, { 0.6, 1.1 } }) do
		rod(m, "Hose", o + V3(e[1], e[2], -4.3), o + V3(e[1] * 0.7, e[2] - 0.1, -2.95), 0.18, rgb(200, 205, 212), M.SmoothPlastic)
	end
	-- control console on a pedestal, angled to the room, with buttons
	local cp = at(2.6, 0, -2.2)
	vcyl(m, "ConsoleBase", 0.08, 0.8, cp, WHITE, M.SmoothPlastic)
	vcyl(m, "ConsolePost", 2.2, 0.2, cp, WHITE, M.Metal)
	local scf = cp * CF(0, 2.55, 0) * ANG(0, RAD(45), 0) * ANG(RAD(-20), 0, 0)
	local screen = part(m, "ControlScreen", V3(1.6, 1.0, 0.1), scf, BLACK, M.SmoothPlastic)
	surfaceText(screen, Enum.NormalId.Back, "RECOVERY\nOPTIMAL", rgb(80, 220, 255), BLACK, 50)
	for i, c in ipairs({ rgb(60, 230, 120), rgb(255, 190, 40), RED }) do
		cyl(m, "Button", 0.05, 0.16, scf * CF(-0.4 + (i - 1) * 0.4, -0.62, 0.02) * ANG(0, RAD(90), 0), c, M.Neon)
	end
	part(m, "ButtonPanel", V3(1.4, 0.3, 0.08), scf * CF(0, -0.62, -0.02), rgb(30, 30, 36), M.SmoothPlastic)
	return { plaque = O * CF(3.4, 2.4, 3.6) }
end

------------------------------------------------------------------------
-- Pool and ring upgrades (decorate existing builds)
------------------------------------------------------------------------
local function buildPool(m, lv)
	local PZ, PW, PL = -112, 56, 22
	if lv >= 2 then
		for i = -2, 2 do
			if i ~= 0 or true then
				local z = PZ + i * 4 + 2
				if math.abs(z - PZ) < PL / 2 - 0.5 then
					for k = 0, 13 do
						local x = -PW / 2 + 2 + k * ((PW - 4) / 13)
						cyl(m, "LaneFloat", 0.6, 0.35, CF(x, 0.05, z), (k % 2 == 0) and (lv >= 3 and Color3.fromRGB(240, 200, 40) or Color3.fromRGB(200, 30, 35)) or (lv >= 3 and Color3.fromRGB(40, 90, 200) or WHITE), M.SmoothPlastic, { shadow = false })
					end
				end
			end
		end
		for _, x in ipairs({ -PW / 2 - 1.2, PW / 2 + 1.2 }) do
			for i = -2, 2 do
				local blk = part(m, "StartBlock", V3(1.4, 1.2, 1.6), CF(x, 1.1, PZ + i * 4), WHITE, M.SmoothPlastic, { collide = true })
				surfaceText(blk, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left, tostring(i + 3), BLACK, nil, 40)
			end
		end
	end
	if lv >= 3 then
		for _, x in ipairs({ -PW / 2 + 5, PW / 2 - 5 }) do
			part(m, "FlagLine", V3(0.06, 0.06, PL + 6), CF(x, 7, PZ), WHITE, M.Fabric, { shadow = false })
			for i = -5, 5 do
				part(m, "Flag", V3(0.05, 0.6, 0.8), CF(x, 6.65, PZ + i * 2.1), (i % 2 == 0) and Color3.fromRGB(200, 30, 35) or Color3.fromRGB(40, 90, 200), M.Fabric, { shadow = false })
			end
		end
		local board = part(m, "Scoreboard", V3(14, 4, 0.4), CF(0, 14, PZ - 33.5), BLACK, M.SmoothPlastic)
		surfaceText(board, Enum.NormalId.Back, "OLYMPIC POOL  50M", GOLD, BLACK, 30)
	end
end

local ringOriginal
local function styleGymRing(lv)
	local gym = workspace:FindFirstChild("Gym")
	local ring = gym and gym:FindFirstChild("GymRing")
	if not ring then
		return
	end
	if not ringOriginal then
		ringOriginal = {}
		for _, p in ipairs(ring:GetChildren()) do
			if p:IsA("BasePart") then
				ringOriginal[p] = p.Color
			end
		end
	end
	lv = math.clamp(lv, 1, 3)
	local canvas = ({ Color3.fromRGB(150, 146, 136), Color3.fromRGB(40, 70, 170), Color3.fromRGB(235, 235, 240) })[lv] or Color3.fromRGB(40, 70, 170)
	local ropes = ({ { Color3.fromRGB(200, 200, 200), Color3.fromRGB(170, 170, 170) }, { Color3.fromRGB(200, 30, 35), Color3.fromRGB(240, 240, 240) }, { GOLD, WHITE } })[lv]
	local i = 0
	for _, p in ipairs(ring:GetChildren()) do
		if p.Name == "Canvas" then
			p.Color = canvas
		elseif p.Name == "Rope" then
			i += 1
			p.Color = (math.floor((i - 1) / 4) == 1) and ropes[2] or ropes[1]
		end
	end
end

------------------------------------------------------------------------
-- Build / refresh
------------------------------------------------------------------------
local TITLES = {}
for id, st in pairs(Catalog.Stations) do
	TITLES[id] = st.name
end

local function stationOrigin(id)
	local gym = workspace:FindFirstChild("Gym")
	local m = gym and gym:FindFirstChild("Station_" .. id)
	local base = m and m:FindFirstChild("Base")
	if not base then
		return nil, nil
	end
	return CF(base.Position - V3(0, 0.5, 0)), m
end

-- the upgrade reveal: the new equipment fades in, gold confetti bursts over it, a banner names the
-- level and a chime plays. Only when a level actually went UP (not on condition-only rebuilds).
local function reveal(m, O, title, levelDef)
	local targets = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			targets[p] = p.Transparency
			p.Transparency = 1
		end
	end
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for p, tr in pairs(targets) do
		local delay = math.clamp((p.Position.Y - O.Position.Y) / 12, 0, 0.5) -- builds up from the floor
		task.delay(delay, function()
			if p.Parent then
				TweenService:Create(p, info, { Transparency = tr }):Play()
			end
		end)
	end
	local holder = Instance.new("Part")
	holder.Name = "RevealFX"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = V3(1, 1, 1)
	holder.CFrame = O * CF(0, 7, 0)
	holder.Parent = m
	local conf = Instance.new("ParticleEmitter")
	conf.Enabled = false
	conf.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, GOLD) })
	conf.Size = NumberSequence.new(0.18)
	conf.Lifetime = NumberRange.new(1.4, 2.4)
	conf.Speed = NumberRange.new(8, 16)
	conf.SpreadAngle = Vector2.new(70, 70)
	conf.Acceleration = V3(0, -18, 0)
	conf.Drag = 1.5
	conf.Rotation = NumberRange.new(0, 360)
	conf.RotSpeed = NumberRange.new(-300, 300)
	conf.LightEmission = 0.4
	conf.Parent = holder
	conf:Emit(60)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(300, 70)
	bb.StudsOffset = V3(0, 1.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = holder
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = GOLD
	t.TextStrokeTransparency = 0.2
	t.Text = string.format("UPGRADED!\n%s: %s", (title or ""):upper(), (levelDef and levelDef.name or ""):upper())
	t.TextTransparency = 1
	t.Parent = bb
	TweenService:Create(t, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	task.delay(3.4, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(holder, 4.5)
	GymSound.Play("reveal", holder.Position, { volume = 1.2 })
	task.delay(0.18, function()
		GymSound.Play("reveal", holder.Position, { volume = 1, speed = 1.26 })
	end)
	task.delay(0.36, function()
		GymSound.Play("reveal", holder.Position, { volume = 1, speed = 1.5 })
	end)
end

local function buildStation(id, lv, cond, ctx)
	local O, stationModel = stationOrigin(id)
	local builder = B[id]
	if not (O and builder) then
		return
	end
	local old = built[id]
	if old and old.model then
		old.model:Destroy()
	end
	if old and old.conn then
		old.conn:Disconnect()
	end
	local m = Instance.new("Model")
	m.Name = "Visual_" .. id
	m.Parent = folder
	local rng = Random.new(#id * 131 + lv)
	local ok, dyn = pcall(builder, m, O, lv, cond, rng, ctx)
	if not ok then
		warn("[GymVisuals]", id, dyn)
		dyn = {}
	end
	dyn = dyn or {}
	local st = Catalog.Stations[id]
	local levelDef = st and st.levels[math.clamp(lv, 1, #st.levels)]
	if dyn.plaque and levelDef then
		plaque(m, CF(), dyn.plaque, TITLES[id] or id, levelDef.name, lv, cond, levelDef.elite)
	end
	dyn.model = m
	dyn.station = stationModel
	dyn.level = lv
	dyn.origin = O
	built[id] = { key = ctx.key, model = m, lv = lv }
	dynamics[id] = dyn
	if dyn.rackBar and stationModel then
		-- the resting bar / dumbbells / rope / handle / ball vanish while you hold your own
		local function sync()
			local inUse = stationModel:GetAttribute("InUse") == true
			for _, p in ipairs(dyn.rackBar:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = inUse and 1 or 0
				elseif p:IsA("SurfaceGui") then
					p.Enabled = not inUse
				end
			end
		end
		sync()
		built[id].conn = stationModel:GetAttributeChangedSignal("InUse"):Connect(sync)
	end
	if old and old.lv and lv > old.lv and ctx.reveal ~= false then
		pcall(reveal, m, O, TITLES[id] or id, levelDef)
	end
end

------------------------------------------------------------------------
-- Members' hanging bags (server rigs tagged MemberBag; swung locally)
------------------------------------------------------------------------
local memberBags = {} -- rig -> dynamics id
local function addMemberBag(rig)
	if not rig:IsA("Model") or memberBags[rig] then
		return
	end
	local hookPos = rig:GetAttribute("Hook")
	if typeof(hookPos) ~= "Vector3" then
		return
	end
	local parts = {}
	local bagPart
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			if p.Name == "MemberBag" then
				bagPart = p
			end
		end
	end
	if #parts == 0 or not bagPart then
		return
	end
	-- the body is SEGS stacked cylinders around the middle "MemberBag" (MapBuilder, attribute
	-- BagLen = body length), so it dents where it is hit and springs back like the station bag;
	-- a single-cylinder rig (no BagLen) still swings, its body then dents as one piece
	local len = tonumber(rig:GetAttribute("BagLen")) or bagPart.Size.X
	local segL = len / SEGS
	local radius = bagPart.Size.Y / 2
	local bagCF = CF(hookPos.X, bagPart.Position.Y, hookPos.Z)
	local hook = CF(hookPos)
	local L = hookPos.Y - bagPart.Position.Y
	-- dust / sweat bursts and the two side bulges are client-only additions to the server rig
	local fx
	local bulges = {}
	pcall(function()
		local fxAtt, dust, spray = impactFX(bagPart, rgb(170, 165, 158))
		fx = { att = fxAtt, dust = dust, spray = spray }
		for _, sx in ipairs({ -1, 1 }) do
			local b = part(rig, "BagBulge", V3(0.5, segL * 0.9, radius * 1.1), bagCF * CF(sx * (radius - 0.22), 0, 0), bagPart.Color, bagPart.Material, { ellipsoid = true, shadow = false })
			local mesh = b:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.Scale = V3(0.6, 1, 1)
				table.insert(bulges, { part = b, mesh = mesh, side = sx })
			end
		end
	end)
	local d = newPendulum(hook, parts, {
		L = L, mass = 1.5, damp = 0.3, topDepth = hookPos.Y - (bagPart.Position.Y + len / 2) - 0.1,
		material = "leather", radius = radius, bagCF = bagCF, len = len, segL = segL, bulges = bulges, fx = fx,
	})
	d.home = bagPart.Position
	d.model = rig
	d.member = true
	local id = "memberbag_" .. tostring(rig:GetAttribute("Index") or (#memberBags + 1))
	memberBags[rig] = id
	dynamics[id] = d
end

-- the members' bag closest to pos (within maxDist studs, flat distance)
local function nearestMemberBag(pos, maxDist)
	local best, bestD
	for rig, id in pairs(memberBags) do
		local d = dynamics[id]
		if not rig.Parent then
			memberBags[rig] = nil
			-- a rebuilt gym re-registers its rig under the same id: only drop OUR dynamics entry
			if d and d.model == rig then
				dynamics[id] = nil
			end
		elseif d then
			local dist = V3(d.home.X - pos.X, 0, d.home.Z - pos.Z).Magnitude
			if dist <= (maxDist or 6) and (not bestD or dist < bestD) then
				best, bestD = id, dist
			end
		end
	end
	return best
end

------------------------------------------------------------------------
-- Build / refresh
------------------------------------------------------------------------
local GymFacility, GymMirror, Ambience
local poolKey, ringKey, tierIdx
function GymVisuals.Refresh(P)
	if not P or not P.created or not P.gym then
		return
	end
	if not folder or not (folder.Parent or GymVisuals.hidden) then
		folder = Instance.new("Folder")
		folder.Name = "LocalGym"
		folder.Parent = workspace
		GymVisuals.hidden = false
	end
	local owns = P.owned and P.owned.RecoveryChamber == true
	local first = next(built) == nil
	for id in pairs(B) do
		local lv = math.max(1, P.gym.levels[id] or 1)
		local cond = P.gym.cond[id] or 100
		local key = string.format("%d|%d|%s", lv, math.floor(cond / 5), tostring(id == "chamber" and owns))
		if not built[id] or built[id].key ~= key then
			buildStation(id, lv, cond, { key = key, ownsChamber = owns, reveal = not first })
		end
	end
	local plv = math.max(1, P.gym.levels.pool or 1)
	if poolKey ~= plv then
		poolKey = plv
		local old = folder:FindFirstChild("PoolUpgrades")
		if old then
			old:Destroy()
		end
		local m = Instance.new("Model")
		m.Name = "PoolUpgrades"
		m.Parent = folder
		buildPool(m, plv)
	end
	local rlv = math.max(1, P.gym.levels.ring or 1)
	if ringKey ~= rlv then
		ringKey = rlv
		styleGymRing(rlv)
	end
	-- facility tier (derived, never saved): tier dressing, elite wing, career wall, trophies
	local ok, idx, def, frac, needs = pcall(Catalog.GymTier, P.gym.levels, P.owned, P.tier)
	if not ok then
		idx, def, frac, needs = 1, nil, 0, nil
	end
	local prevTier = tierIdx
	tierIdx = idx
	GymVisuals.Tier = idx
	GymFacility = GymFacility or optional("GymFacility")
	if GymFacility then
		local okF, err = pcall(GymFacility.Refresh, P, folder, { idx = idx, def = def, frac = frac, needs = needs, prev = prevTier, ringLevel = rlv })
		if not okF then
			warn("[GymVisuals] facility:", err)
		end
	end
	Ambience = Ambience or optional("Ambience")
	if Ambience and Ambience.SetTier then
		pcall(Ambience.SetTier, idx)
	end
	GymMirror = GymMirror or optional("GymMirror")
	if GymMirror and GymMirror.Start then
		pcall(GymMirror.Start, function()
			local d = dynamics.mirror
			return d and d.model and d.model:FindFirstChild("Mirror")
		end)
	end
end

------------------------------------------------------------------------
-- Interaction effects
------------------------------------------------------------------------
-- power 0..1.5 (negative = toward the boxer: the double-end bag springs at you), side -1 (left
-- hand) .. 1 (right hand); ptype / zone (optional) = Config.Punches id and "head" | "body";
-- opts (optional) = { remote = true (someone else's punch: quieter), sweat = 0..1 }
function GymVisuals.Impact(id, power, side, ptype, zone, opts)
	local d = dynamics[id]
	if not d then
		return
	end
	power = tonumber(power) or 1
	side = tonumber(side) or 0
	local lv = d.level or 1
	if d.kind == "pendulum" then
		if opts == nil then
			-- your own punch: your sweat flies off the bag
			local c = player.Character
			opts = { sweat = c and c:GetAttribute("Sweat") or 0 }
		end
		hitPendulum(d, power, side, ptype, zone, opts)
		if not (opts and opts.remote) then
			d.hits = (d.hits or 0) + 1
			if d.display then
				d.display.Text = string.format("IMPACT\n%d lbs\n%d hits", math.floor(350 + math.abs(power) * 900 + math.random(-40, 40)), d.hits)
			end
		end
	elseif d.kind == "rebound" then
		d.amp = math.min(1.2, 0.55 + math.abs(power) * 0.5)
		d.t0 = os.clock()
		-- the speed bag's rattle: front board, back board, front board
		GymSound.Burst("speedbag", d.pivot.Position, 3, 0.042, { speed = 1 + lv * 0.06, volume = (0.8 + lv * 0.1) * (opts and opts.remote and 0.6 or 1) })
	elseif d.kind == "spring" then
		d.vz -= 7 * power
		d.vx += 3 * power * side
		if power > 0 then
			GymSound.Play("doubleend", d.home.Position, { speed = 1 + lv * 0.05, volume = opts and opts.remote and 0.6 or 1 })
		end
	elseif d.kind == "medball" then
		-- a slam (power > 0) or a catch / twist touch (power <= 0)
		local pos = d.slam and d.slam.Position or (d.origin and d.origin.Position) or Vector3.zero
		if power > 0 then
			GymSound.Play("slam", pos, { volume = 0.7 + power * 0.4 })
			GymSound.Play("ballcatch", pos, { volume = 0.4, speed = 0.8 })
			if d.puff then
				pcall(function()
					d.puff:Emit(math.floor(4 + power * 8))
				end)
			end
			if d.led then
				d.led.Transparency = 0
				task.delay(0.15, function()
					if d.led.Parent then
						d.led.Transparency = 0.35
					end
				end)
			end
		else
			GymSound.Play("ballcatch", pos + V3(0, 3, 0), { volume = 0.5 })
		end
	end
end

-- sweat dripping onto the floor at a station: a small wet patch that evaporates over ~90 s
local SWEAT_CAP = 8
local sweatPatches = {} -- station id -> { parts (FIFO) }
function GymVisuals.SweatDrop(id)
	local gym = workspace:FindFirstChild("Gym")
	local m = gym and gym:FindFirstChild("Station_" .. tostring(id))
	local use = m and m:FindFirstChild("UsePoint")
	if not (use and folder) then
		return
	end
	local f = folder:FindFirstChild("Sweat")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Sweat"
		f.Parent = folder
	end
	local list = sweatPatches[id] or {}
	sweatPatches[id] = list
	while #list >= SWEAT_CAP do
		local oldest = table.remove(list, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	local floorY = (m:FindFirstChild("Base") and m.Base.Position.Y - 0.5) or 0.5
	local pos = V3(use.Position.X + (math.random() * 2 - 1) * 1.2, floorY + 0.012, use.Position.Z + (math.random() * 2 - 1) * 1.2)
	local size = 0.4 + math.random() * 0.5
	local p = part(f, "SweatDrop", V3(size, 0.02, size * (0.7 + math.random() * 0.5)), CF(pos) * ANG(0, math.random() * math.pi, 0), rgb(150, 170, 185), M.Glass, { ellipsoid = true, shadow = false, transparency = 0.55, reflect = 0.25 })
	table.insert(list, p)
	TweenService:Create(p, TweenInfo.new(90, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(p, 91)
end

function GymVisuals.SetDisplay(id, text)
	local d = dynamics[id]
	if d and d.display then
		d.display.Text = text
	end
end

-- smart reaction lights on the agility ladder
function GymVisuals.Light(id, index, color)
	local d = dynamics[id]
	if not (d and d.lights) then
		return
	end
	for i, pad in ipairs(d.lights) do
		pad.Color = (i == index and color) or Color3.fromRGB(40, 40, 46)
	end
end

function GymVisuals.Origin(id)
	return stationOrigin(id)
end

------------------------------------------------------------------------
-- Other people's punches (client-local AutoAct / AutoActId published by the Animator on other
-- players' Trainee rigs and on the members working bags or sparring). Nothing replicates.
------------------------------------------------------------------------
local POWER = { jab = 0.55, cross = 0.9, leadhook = 0.95, rearhook = 1.05, uppercut = 1.0, overhand = 1.25 }
local REMOTE_NEAR = 140
local watched = {} -- model -> connection

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function onAutoAct(model)
	local act = model:GetAttribute("AutoAct")
	local root = model:FindFirstChild("HumanoidRootPart")
	if type(act) ~= "string" or not root or (root.Position - camPos()).Magnitude > REMOTE_NEAR then
		return
	end
	local ptype, hand, zone, windup, pw = string.match(act, "^([^|]+)|?([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)$")
	local base = POWER[ptype or ""]
	if not base then
		return -- slips, rolls and other moves hit nothing
	end
	local side = hand == "L" and -1 or 1
	local power = base * 0.8 * math.clamp(tonumber(pw) or 1, 0.3, 1.6)
	local sweat = model:GetAttribute("Sweat") or 0
	task.delay(math.clamp(tonumber(windup) or 0.2, 0, 0.6), function()
		if not model.Parent then
			return
		end
		local station = model:GetAttribute("Station")
		if station and dynamics[station] and CollectionService:HasTag(model, "Trainee") then
			GymVisuals.Impact(station, power, side, ptype, zone ~= "" and zone or nil, { remote = true, sweat = sweat })
			return
		end
		if model:GetAttribute("Loop") == "spar" then
			-- the partner's glove / headgear pops
			local partnerName = model:GetAttribute("SparPartner")
			local members = workspace:FindFirstChild("GymMembers")
			local partner = members and partnerName and members:FindFirstChild(partnerName)
			local head = partner and partner:FindFirstChild("Head")
			GymSound.Play("glove", head and head.Position or root.Position, { volume = 0.5 + power * 0.25 })
			return
		end
		local bag = nearestMemberBag(root.Position, 6)
		local bd = bag and dynamics[bag]
		if bd then
			-- the members' rigs hang square to the world: a punch from the +Z side drives the bag to -Z
			-- (positive power), one from the other side swings it back the other way
			local from = (root.Position.Z >= bd.home.Z) and 1 or -1
			GymVisuals.Impact(bag, power * from, side * from, ptype, zone ~= "" and zone or nil, { remote = true, sweat = sweat, face = from })
		end
	end)
end

local function watchModel(model)
	if watched[model] or not model:IsA("Model") or model == player.Character then
		return
	end
	watched[model] = model:GetAttributeChangedSignal("AutoActId"):Connect(function()
		onAutoAct(model)
	end)
end

-- The removed signal also fires when a tagged model leaves the DataModel (Destroy, a player
-- leaving, a crew rebuild), and Destroy does not clear tags, so "still tagged" alone would keep
-- the entry (and the dead Model) forever. Deferred so the ancestry change has landed; a model
-- that was only hidden and comes back (LocalGym unparent) is re-watched by the added signal.
local function unwatchModel(model)
	task.defer(function()
		local inWorld = model:IsDescendantOf(workspace)
		if inWorld and (CollectionService:HasTag(model, "Trainee") or CollectionService:HasTag(model, "Ambient")) then
			return -- still tagged the other way
		end
		local c = watched[model]
		if c then
			c:Disconnect()
			watched[model] = nil
		end
	end)
end

for _, tagName in ipairs({ "Trainee", "Ambient" }) do
	for _, m in ipairs(CollectionService:GetTagged(tagName)) do
		watchModel(m)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(watchModel)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(unwatchModel)
end
for _, rig in ipairs(CollectionService:GetTagged("MemberBag")) do
	addMemberBag(rig)
end
CollectionService:GetInstanceAddedSignal("MemberBag"):Connect(addMemberBag)

------------------------------------------------------------------------
-- Per-frame motion
------------------------------------------------------------------------
-- stretch a cord part between two points
local function cord(cp, a, b, w)
	w = w or 0.06
	cp.Size = V3(w, (a - b).Magnitude, w)
	cp.CFrame = CFrame.lookAt((a + b) / 2, b, upFor(b - a)) * CFrame.Angles(math.pi / 2, 0, 0)
end

local MOTION_NEAR = 150 -- equipment further from the camera than this freezes
local FAR_GYM = 420 -- the whole local gym is unparented beyond this (fight venues, the far city)
local bulkP, bulkC = {}, {}
local hideAcc = 0

local function flush()
	if #bulkP == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(bulkP, bulkC, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(bulkP) do
			p.CFrame = bulkC[i]
		end
	end
	table.clear(bulkP)
	table.clear(bulkC)
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.05)
	local t = os.clock()
	local cam = camPos()
	-- perf: stop drawing the whole local gym while the camera is far away (fight venues sit at
	-- x/z 4000+, the city edges ~400 studs out); it comes back the moment you return
	hideAcc += dt
	if hideAcc > 0.5 and folder then
		hideAcc = 0
		local far = V3(cam.X, 0, cam.Z).Magnitude > FAR_GYM
		if far and folder.Parent then
			GymVisuals.hidden = true
			folder.Parent = nil
		elseif not far and not folder.Parent and GymVisuals.hidden then
			folder.Parent = workspace
			GymVisuals.hidden = false
		end
	end
	if GymVisuals.hidden then
		-- members' bags outside the gym (the sparring room's MemberBag rigs) still swing: they are
		-- server rigs, not inside the hidden folder
		for id, d in pairs(dynamics) do
			if d.member then
				if not (d.model and d.model.Parent) then
					dynamics[id] = nil
				elseif d.kind == "pendulum" and (d.home - cam).Magnitude <= MOTION_NEAR then
					stepPendulum(d, dt, t, bulkP, bulkC)
				end
			end
		end
		flush()
		return
	end
	for id, d in pairs(dynamics) do
		if not (d.model and d.model.Parent) then
			if d.member then
				dynamics[id] = nil
			end
			continue
		end
		local anchor = d.home or d.hook or d.pivot or d.origin
		if typeof(anchor) == "CFrame" then
			anchor = anchor.Position
		end
		if typeof(anchor) == "Vector3" and (anchor - cam).Magnitude > MOTION_NEAR then
			continue
		end
		local inUse = d.station and d.station:GetAttribute("InUse") == true
		if d.kind == "pendulum" then
			stepPendulum(d, dt, t, bulkP, bulkC)
		elseif d.kind == "rebound" then
			local el = t - d.t0
			local a = d.amp * math.exp(-el * 3.2) * math.sin(el * d.freq * 2)
			if math.abs(a) > 0.001 or el < 2 then
				local rot = d.pivot * CFrame.Angles(a * 0.9, 0, 0)
				for p, rel in pairs(d.rel) do
					table.insert(bulkP, p)
					table.insert(bulkC, rot * rel)
				end
			end
		elseif d.kind == "spring" then
			if d.placed and math.abs(d.x) + math.abs(d.z) + math.abs(d.vx) + math.abs(d.vz) < 1e-4 then
				continue -- at rest: nothing to move
			end
			d.vx += (-d.k * d.x) * dt
			d.vz += (-d.k * d.z) * dt
			d.vx *= math.exp(-dt * 2.2)
			d.vz *= math.exp(-dt * 2.2)
			d.x = math.clamp(d.x + d.vx * dt, -1.6, 1.6)
			d.z = math.clamp(d.z + d.vz * dt, -1.6, 1.6)
			local pos = (d.home * CF(d.x, 0, d.z)).Position
			local ballCF = CF(pos)
			d.bag.CFrame = ballCF
			if d.extras then
				for _, e in ipairs(d.extras) do
					e[1].CFrame = ballCF * e[2]
				end
			end
			cord(d.top, d.topAnchor, pos + V3(0, d.d * 0.55, 0), d.cordW)
			cord(d.bottom, pos - V3(0, d.d * 0.55, 0), d.bottomAnchor, d.cordW)
			d.placed = true
		elseif d.kind == "belt" then
			if inUse then
				d.offset = (d.offset + dt * 6) % 1.1
				for i, s in ipairs(d.stripes) do
					local z = -3 + ((i - 1) * 1.1 + d.offset) % 6.6
					table.insert(bulkP, s)
					table.insert(bulkC, d.beltCF * CF(0, 0, z - 0.2))
				end
			end
		elseif d.kind == "spinner" then
			if inUse then
				d.angle += dt
				for _, s in ipairs(d.parts) do
					local cf
					if s.rel then
						-- orbits / swings about a pivot (pedals, air-bike arms)
						local a = s.swing and math.sin(d.angle * s.speed + (s.phase or 0)) * s.swing or d.angle * s.speed
						cf = s.base * CFrame.Angles(a, 0, 0) * s.rel
					elseif s.axis == "Y" then
						cf = s.base * CFrame.Angles(0, d.angle * s.speed, 0)
					else
						cf = s.base * CFrame.Angles(d.angle * s.speed, 0, 0)
					end
					table.insert(bulkP, s.p)
					table.insert(bulkC, cf)
				end
			end
		end
	end
	flush()
end)

return GymVisuals
