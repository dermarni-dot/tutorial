-- GymDetail: the training complex's extra detail layer (client-only, WorldDetail streams it by Graphics level
-- and camera distance; DetailKit's defaults: no collision, no queries, no touches, small parts cast no shadow).
-- Nothing here moves a station, a prompt, a spawn, a wall or a path: every piece sits against a wall, on the
-- ceiling, flat on the floor or in a corner the stations, the members (Ambient) and the walkways leave free
-- (tools/sim/test_worlddetail.luau checks the keep-out boxes).
--   tier 1  rubber tile floors (one Texture per zone floor), canvas weave on the ring, hanging WCB banners,
--           printed posters (uploaded WorldAssetData images, part-built fallbacks)
--   tier 2  HVLS ceiling fans, pedestal fans, the ring's corner stools and kit, decorative bags on the trusses,
--           slip-rope line, maize bags, jump-rope hooks, gear bench with bags and towels, bottle crate, wall
--           clocks, bumper plates, a bar holder, belts on hooks, a spare bench, foam rollers, cleaning station,
--           yoga mats, locker handles / number plates / padlocks, robes on hooks, coat rack, floor scuffs
--   tier 3  sprinkler mains with heads and hangers, electrical conduit with junction boxes and outlets
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local GymDetail = {}

local FLOOR_Y = 0.5 -- top of the zone floors
local HALL = { x1 = -110, x2 = 110, z1 = -80, z2 = 80, h = 30 }

-- interior wall planes (MapBuilder / GymDecor): plane coordinate, axis, the normal into the room
local WALLS = {
	N = { axis = "X", plane = -79, n = V3(0, 0, 1) },
	S = { axis = "X", plane = 79, n = V3(0, 0, -1) },
	W = { axis = "Z", plane = -109, n = V3(1, 0, 0) },
	E = { axis = "Z", plane = 109, n = V3(-1, 0, 0) },
	DWb = { axis = "Z", plane = -49, n = V3(1, 0, 0) }, -- the x = -50 divider, boxing side
	DEb = { axis = "Z", plane = 49, n = V3(-1, 0, 0) }, -- the x = +50 divider, boxing side
	DEc = { axis = "Z", plane = 51, n = V3(1, 0, 0) }, -- the x = +50 divider, cardio side
	DZs = { axis = "X", plane = 21, n = V3(0, 0, 1) }, -- the z = 20 dividers, south face
}

-- a CFrame on a wall: `along` the wall, at height y, `out` studs into the room, its -Z (front) facing the room
local function onWall(id, along, y, out)
	local w = WALLS[id]
	local p
	if w.axis == "X" then
		p = V3(along, y, w.plane)
	else
		p = V3(w.plane, y, along)
	end
	p += w.n * (out or 0)
	return CFrame.lookAt(p, p + w.n)
end

local function gymFolder()
	return workspace:FindFirstChild("Gym")
end

-- a server part of the gym by name (nil while the gym streams in)
local function gymPart(name, under)
	local g = gymFolder()
	local root = g and (under and g:FindFirstChild(under, true) or g)
	return root and root:FindFirstChild(name, true) or nil
end

------------------------------------------------------------------------
-- tier 1: surfaces and print
------------------------------------------------------------------------
-- a rubber tile Texture on an invisible overlay just above a zone floor (x1..x2, z1..z2). tint = the floor's
-- colour (the tile image is mid-grey: Color3 = tint / 0.55 brings it back to the floor's colour); tile = studs a
-- tile (the image holds 2 x 2)
local function tileFloor(m, name, x1, x2, z1, z2, tint, tile, transp)
	local w, l = x2 - x1, z2 - z1
	local p = Part(m, name, V3(w, 0.05, l), CF((x1 + x2) / 2, FLOOR_Y + 0.012, (z1 + z2) / 2), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	local k = 1 / 0.55
	local col = Color3.new(math.min(1, tint.R * k), math.min(1, tint.G * k), math.min(1, tint.B * k))
	K.Texture(p, FACE.Top, "rubberTiles", tile * 2, tile * 2, { Color3 = col, Transparency = transp or 0 })
	return p
end

-- a hanging WCB banner on a wall: rod, end caps, the cloth (uploaded banner, or a printed fallback)
local function wallBanner(m, cf, w, h)
	local cloth = Part(m, "BannerCloth", V3(w, h, 0.08), cf, C.ink, M.Fabric, { shadow = false })
	if not K.Decal(cloth, FACE.Front, "bannerWCB") then
		local sg = K.Gui(cloth, FACE.Front, 20, 1)
		K.Frame(sg, { BackgroundColor3 = C.ink })
		K.Emblem(sg, 0.1, 0.04, 0.8, 0.26)
		K.Text(sg, "W\nC\nB", { TextColor3 = C.gold, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.32) })
		K.Frame(sg, { BackgroundColor3 = C.red, Size = UDim2.fromScale(0.9, 0.06), Position = UDim2.fromScale(0.05, 0.86) })
	end
	local top = cf * CF(0, h / 2 + 0.15, 0.02)
	Cyl(m, "BannerRod", w + 0.4, 0.22, top, C.goldDeep, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Ball(m, "BannerFinial", 0.36, top * CF(s * (w / 2 + 0.2), 0, 0), C.gold, M.Metal)
	end
	Cyl(m, "BannerWeight", w, 0.14, cf * CF(0, -h / 2 - 0.05, 0.02), C.goldDeep, M.Metal)
end

-- a poster on a wall with a thin black frame
local function wallPoster(m, key, cf, w, fallback)
	K.Poster(m, key, w, w * 1.5, cf * CF(0, 0, -0.06), fallback, C.black)
end

-- the ring canvas weave, laid over the gym ring's canvas (top y 2.8)
local function canvasWeave(m)
	local canvas = gymPart("Canvas", "GymRing")
	local top = canvas and (canvas.Position.Y + canvas.Size.Y / 2) or 2.8
	local c = canvas and canvas.Position or V3(0, 2.65, -50)
	local s = canvas and canvas.Size or V3(26, 0.3, 26)
	local p = Part(m, "CanvasWeave", V3(s.X - 0.2, 0.05, s.Z - 0.2), CF(c.X, top + 0.004, c.Z), C.black, M.Fabric, { t = 1, shadow = false })
	local tex = K.Texture(p, FACE.Top, "canvasWeave", 6, 6, { Color3 = canvas and canvas.Color or C.white, Transparency = 0.35 })
	-- the ring's level restyles the canvas colour (GymVisuals): the weave follows it
	if tex and canvas then
		local conn
		conn = canvas:GetPropertyChangedSignal("Color"):Connect(function()
			if tex.Parent then
				tex.Color3 = canvas.Color
			elseif conn then
				conn:Disconnect()
			end
		end)
	end
end

------------------------------------------------------------------------
-- templates (built once, cloned)
------------------------------------------------------------------------
-- big industrial ceiling fan (HVLS): spins through Ambience's SpinFan tag (Hub + Blade parts about the hub's X
-- axis, which points up here)
local function hvlsFan(m, at, dropTo)
	local fan = K.Model(m, "CeilingFan")
	Rod(fan, "FanDownrod", at + V3(0, 0.6, 0), V3(at.X, dropTo, at.Z), 0.3, C.steelDark, M.Metal)
	VCyl(fan, "FanMotor", 1.0, 1.6, at + V3(0, 0.2, 0), C.ink2, M.Metal)
	local hub = Part(fan, "Hub", V3(0.5, 1.2, 1.2), CF(at) * A(0, 0, math.pi / 2), C.steelDark, M.Metal, { shape = "Cylinder" })
	for k = 0, 5 do
		local yaw = k * math.pi / 3
		Part(fan, "Blade", V3(1.0, 0.12, 7.0), CF(at) * A(0, yaw, 0) * CF(0, 0, 4.0) * A(0, 0, RAD(8)), C.steelLight, M.Metal, { shadow = false })
	end
	fan.PrimaryPart = hub
	fan:SetAttribute("Speed", 1.3)
	pcall(function()
		fan:AddTag("SpinFan")
	end)
	return fan
end

-- pedestal fan facing `dir` (horizontal): base, pole, motor, cage and blades (spins like the wall fans)
local function pedestalFan(m, pos, dir)
	local fan = K.Model(m, "PedestalFan")
	local cf = CFrame.lookAt(pos, pos + dir)
	VCyl(fan, "FanBase", 0.25, 2.4, pos, C.black, M.Metal)
	VCyl(fan, "FanPole", 5.2, 0.24, pos + V3(0, 0.2, 0), C.steelLight, M.Metal)
	local head = cf * CF(0, 5.8, 0)
	Part(fan, "FanMotor", V3(1.0, 1.0, 1.4), head * CF(0, 0, 0.7), C.ink2, M.SmoothPlastic)
	-- the hub's X axis along the facing direction (Ambience spins about X)
	local hubCF = head * CF(0, 0, -0.2) * A(0, math.pi / 2, 0)
	local hub = Part(fan, "Hub", V3(0.4, 0.7, 0.7), hubCF, C.ink2, M.SmoothPlastic, { shape = "Cylinder" })
	for k = 0, 2 do
		Part(fan, "Blade", V3(0.08, 1.4, 0.7), hubCF * A(k * 2 * math.pi / 3, 0, 0) * CF(0, 0.85, 0) * A(0, RAD(18), 0), C.steelLight, M.SmoothPlastic, { shadow = false, t = 0.05 })
	end
	-- the cage: front and back rings, a centre badge
	for _, z in ipairs({ -0.55, 0.2 }) do
		local ring = Part(fan, "FanCage", V3(0.06, 3.5, 3.5), head * CF(0, 0, z) * A(0, math.pi / 2, 0), C.chrome, M.Metal, { shape = "Cylinder", t = 0.65, shadow = false })
		ring.Name = "FanCage"
	end
	Part(fan, "FanBadge", V3(0.6, 0.6, 0.05), head * CF(0, 0, -0.6), C.red, M.SmoothPlastic, { shadow = false })
	fan.PrimaryPart = hub
	fan:SetAttribute("Speed", 9)
	pcall(function()
		fan:AddTag("SpinFan")
	end)
	return fan
end

-- a round wall clock (body, white face with hour marks, two hands) at cf (front facing the room)
local CLOCK = K.Template("GymClock", function(t)
	Part(t, "ClockBody", V3(2.6, 2.6, 0.3), CF(0, 0, 0.15) * A(0, math.pi / 2, 0), C.ink, M.SmoothPlastic, { shape = "Cylinder" })
	local face = Part(t, "ClockFace", V3(0.06, 2.3, 2.3), CF(0, 0, -0.02) * A(0, math.pi / 2, 0), C.white, M.SmoothPlastic, { shape = "Cylinder" })
	face.Name = "ClockFace"
	for k = 0, 11 do
		local a = k * math.pi / 6
		local long = k % 3 == 0
		Part(t, "ClockTick", V3(0.08, long and 0.32 or 0.18, 0.03), CF(math.sin(a) * 0.95, math.cos(a) * 0.95, -0.07) * A(0, 0, -a), C.ink, M.SmoothPlastic)
	end
	Part(t, "ClockHour", V3(0.1, 0.6, 0.03), CF(0.18, 0.2, -0.09) * A(0, 0, RAD(-40)) * CF(0, 0.05, 0), C.ink, M.SmoothPlastic)
	Part(t, "ClockMinute", V3(0.07, 0.88, 0.03), CF(-0.28, 0.24, -0.1) * A(0, 0, RAD(50)) * CF(0, 0.05, 0), C.ink, M.SmoothPlastic)
	Part(t, "ClockSecond", V3(0.03, 0.9, 0.02), CF(0, -0.3, -0.11) * A(0, 0, RAD(175)), C.red, M.SmoothPlastic)
	Ball(t, "ClockPin", 0.14, CF(0, 0, -0.12), C.red, M.Metal)
end)

-- a padded gym bench (seat with a seam line, steel legs) along local X, seat top at 1.6
local BENCH = K.Template("GymBench", function(t)
	Part(t, "BenchSeat", V3(6, 0.45, 1.3), CF(0, 1.4, 0), C.black, M.Leather)
	Part(t, "BenchSeam", V3(6.02, 0.05, 1.32), CF(0, 1.36, 0), C.red, M.Fabric)
	Part(t, "BenchFrame", V3(5.4, 0.18, 0.5), CF(0, 1.08, 0), C.steelDark, M.Metal)
	for _, x in ipairs({ -2.5, 2.5 }) do
		Part(t, "BenchLeg", V3(0.25, 1.05, 1.1), CF(x, 0.52, 0), C.steelDark, M.Metal)
		Part(t, "BenchFoot", V3(0.4, 0.1, 1.3), CF(x, 0.05, 0), C.rubber, M.Rubber)
	end
end)

-- a duffel gym bag (body, end caps, strap, logo band)
local GYMBAG = K.Template("GymBag", function(t)
	Part(t, "BagBody", V3(2.2, 1.0, 1.0), CF(0, 0.5, 0), C.black, M.Fabric, { shape = "Cylinder" })
	for _, s in ipairs({ -1, 1 }) do
		Part(t, "BagEnd", V3(0.08, 1.02, 1.02), CF(s * 1.08, 0.5, 0), C.red, M.Fabric, { shape = "Cylinder" })
	end
	Part(t, "BagStrap", V3(1.4, 0.06, 0.18), CF(0, 1.05, 0), C.ink2, M.Fabric)
	Part(t, "BagZip", V3(2.0, 0.03, 0.06), CF(0, 1.0, 0.0), C.steelLight, M.Metal)
	Part(t, "BagLogo", V3(0.8, 0.4, 0.02), CF(0, 0.55, -0.5), C.gold, M.SmoothPlastic)
end)

-- a folded towel stack (3 towels)
local TOWELS = K.Template("TowelStack", function(t)
	local cols = { C.white, rgb(220, 60, 60), C.white }
	for k = 0, 2 do
		Part(t, "Towel", V3(1.6, 0.22, 1.0), CF(0, 0.11 + k * 0.23, 0) * A(0, RAD(k * 6 - 6), 0), cols[k + 1], M.Fabric)
	end
end)

-- a water bottle (body, cap)
local BOTTLE = K.Template("Bottle", function(t)
	VCyl(t, "BottleBody", 0.8, 0.32, V3(0, 0, 0), rgb(60, 140, 230), M.Plastic, { t = 0.2 })
	VCyl(t, "BottleCap", 0.16, 0.22, V3(0, 0.8, 0), C.ink, M.Plastic)
end)

local function place(tpl, m, cf)
	return K.Place(tpl, m, cf)
end

------------------------------------------------------------------------
-- boxing area
------------------------------------------------------------------------
-- a slip-rope line: two posts and a rope at head height with tennis-ball markers (slip and roll drills)
local function slipRope(m, a, b)
	for _, p in ipairs({ a, b }) do
		VCyl(m, "SlipPostBase", 0.3, 1.6, p, C.black, M.Rubber)
		VCyl(m, "SlipPost", 6.6, 0.3, p + V3(0, 0.3, 0), C.steelDark, M.Metal)
		VCyl(m, "SlipPostCap", 0.25, 0.45, p + V3(0, 6.9, 0), C.red, M.Plastic)
	end
	local y = V3(0, 5.6, 0)
	Rod(m, "SlipRope", a + y, b + y, 0.1, C.yellow, M.Fabric)
	for k = 1, 3 do
		Ball(m, "SlipBall", 0.36, a:Lerp(b, k / 4) + y - V3(0, 0.22, 0), rgb(200, 230, 60), M.Fabric)
	end
end

-- maize bags: a frame with three small slip bags on cords at head height
local function maizeFrame(m, pos, along)
	local side = V3(-along.Z, 0, along.X)
	local w = 6
	for _, s in ipairs({ -1, 1 }) do
		local p = pos + along * (s * w / 2)
		Part(m, "MaizeFoot", V3(0.4, 0.2, 2.4), CFrame.lookAt(p + V3(0, 0.1, 0), p + V3(0, 0.1, 0) + side), C.steelDark, M.Metal)
		VCyl(m, "MaizeUpright", 8.6, 0.3, p + V3(0, 0.2, 0), C.steelDark, M.Metal)
	end
	local top = pos + V3(0, 8.8, 0)
	Rod(m, "MaizeBeam", top - along * (w / 2 + 0.2), top + along * (w / 2 + 0.2), 0.36, C.steelDark, M.Metal)
	for k = -1, 1 do
		local hook = top + along * (k * 1.8)
		local bag = hook - V3(0, 3.6, 0)
		Rod(m, "MaizeCord", hook, bag + V3(0, 0.35, 0), 0.05, C.ink2, M.Fabric)
		Ball(m, "MaizeBag", V3(0.7, 0.85, 0.7), CF(bag), k == 0 and C.red or C.black, M.Leather)
		Rod(m, "MaizeCordLow", bag - V3(0, 0.4, 0), bag - V3(0, 2.6, 0), 0.04, C.ink2, M.Fabric)
	end
end

-- jump ropes on a hook board on a wall
local function ropeHooks(m, cf)
	Part(m, "HookBoard", V3(4.4, 0.8, 0.15), cf, C.woodDark, M.Wood)
	local cols = { C.red, C.blue, C.gold }
	for k = -1, 1 do
		local hook = cf * CF(k * 1.4, 0.0, -0.3)
		Part(m, "Hook", V3(0.12, 0.12, 0.45), cf * CF(k * 1.4, 0, -0.2), C.chrome, M.Metal)
		-- the rope hangs in a loop: two handles and the cord between
		for _, s in ipairs({ -1, 1 }) do
			local h = hook * CF(s * 0.22, -0.55, 0)
			Part(m, "RopeHandle", V3(0.18, 0.75, 0.18), h, cols[k + 2], M.Plastic)
			Rod(m, "RopeCord", h.Position - V3(0, 0.38, 0), hook.Position - V3(0, 2.7, 0), 0.05, C.ink, M.Plastic)
		end
	end
end

-- a crate of water bottles on the floor
local function bottleCrate(m, cf)
	Part(m, "Crate", V3(2.2, 0.7, 1.5), cf * CF(0, 0.35, 0), C.blueDeep, M.Plastic)
	for i = 0, 3 do
		for j = 0, 1 do
			place(BOTTLE, m, cf * CF(-0.75 + i * 0.5, 0.45, -0.35 + j * 0.7))
		end
	end
end

-- floor scuffs (decal patches) around a station's use point
local function scuffsAt(m, pos, n, seed)
	local rng = Random.new(seed)
	for _ = 1, n do
		local p = pos + V3(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		K.Patch(m, "FloorScuff", rng:NextNumber(3, 5), rng:NextNumber(3, 5), CF(p.X, FLOOR_Y, p.Z) * A(0, rng:NextNumber(0, 6.28), 0), "scuffs", nil, rng:NextNumber(0.25, 0.5))
	end
end

-- a hanging canvas banner (printed both sides) on two cables from a purlin (along X at z, top y 29.5)
local function purlinBanner(m, x, z, w, h)
	local y = 27.0 - h / 2
	local cloth = Part(m, "HangingBanner", V3(w, h, 0.06), CF(x, y, z) * A(0, math.pi, 0), C.ink, M.Fabric, { shadow = false })
	local okF = K.Decal(cloth, FACE.Front, "bannerWCB")
	K.Decal(cloth, FACE.Back, "bannerWCB")
	if not okF then
		K.Sign(cloth, FACE.Front, "WCB", C.gold, C.ink, 20)
		K.Sign(cloth, FACE.Back, "WCB", C.gold, C.ink, 20)
	end
	Cyl(m, "BannerRod", w + 0.6, 0.2, CF(x, y + h / 2 + 0.1, z), C.goldDeep, M.Metal)
	Cyl(m, "BannerWeight", w, 0.14, CF(x, y - h / 2 - 0.05, z), C.goldDeep, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Rod(m, "BannerCable", V3(x + s * w * 0.4, y + h / 2 + 0.15, z), V3(x + s * w * 0.4, 29.5, z), 0.05, C.steelDark, M.Metal)
	end
end

-- a decorative heavy bag on a long chain from a roof truss (stitched panels, top cap, swivel, D-ring chains)
local function trussBag(m, x, z, col)
	local topY, bagTop, len = 28.1, 8.4, 5.2
	Part(m, "TrussClamp", V3(1.2, 0.4, 1.2), CF(x, topY - 0.2, z), C.steelDark, M.Metal)
	Rod(m, "BagChainLong", V3(x, topY - 0.4, z), V3(x, bagTop + 1.6, z), 0.16, C.steelLight, M.Metal)
	Ball(m, "BagSwivel", 0.42, CF(x, bagTop + 1.5, z), C.chrome, M.Metal)
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		Rod(m, "BagChain", V3(x, bagTop + 1.35, z), V3(x + math.cos(a) * 0.8, bagTop + 0.05, z + math.sin(a) * 0.8), 0.08, C.steelLight, M.Metal)
		Part(m, "BagDRing", V3(0.12, 0.3, 0.3), CF(x + math.cos(a) * 0.82, bagTop - 0.05, z + math.sin(a) * 0.82) * A(0, -a, 0), C.chrome, M.Metal)
	end
	VCyl(m, "DecoBag", len, 2.3, V3(x, bagTop - len, z), col, M.Leather)
	VCyl(m, "DecoBagCap", 0.3, 2.36, V3(x, bagTop - 0.3, z), col:Lerp(C.black, 0.4), M.Leather)
	VCyl(m, "DecoBagBase", 0.25, 2.34, V3(x, bagTop - len, z), col:Lerp(C.black, 0.4), M.Leather)
	for _, y in ipairs({ 0.33, 0.66 }) do
		VCyl(m, "DecoBagSeam", 0.06, 2.34, V3(x, bagTop - len * y, z), col:Lerp(C.black, 0.55), M.Fabric)
	end
	local label = Part(m, "DecoBagLabel", V3(1.1, 1.6, 0.05), CF(x, bagTop - len * 0.5, z + 1.16), C.gold, M.SmoothPlastic, { shadow = false })
	K.Sign(label, FACE.Back, "W\nC\nB", C.ink, C.gold, 30)
end

-- the ring's corner kit outside the red and blue corners: stools, bottles, towels, spit buckets
local function ringCornerKit(m)
	for _, k in ipairs({ { -1, C.red }, { 1, C.blue } }) do
		local s = k[1]
		local base = V3(s * 15.2, FLOOR_Y, -50 + s * 7)
		VCyl(m, "CornerStoolSeat", 0.3, 1.6, base + V3(0, 2.2, 0), k[2], M.Leather)
		for j = 0, 3 do
			local a = j * math.pi / 2 + math.pi / 4
			Rod(m, "CornerStoolLeg", base + V3(math.cos(a) * 0.55, 0, math.sin(a) * 0.55), base + V3(math.cos(a) * 0.4, 2.2, math.sin(a) * 0.4), 0.12, C.steelDark, M.Metal)
		end
		place(BOTTLE, m, CF(base + V3(1.4 * -s, 0, 0.6)))
		place(TOWELS, m, CF(base + V3(0.4 * -s, 2.5, 0)))
	end
end

-- artificial turf lane (sled pushes) with yard lines and a push sled at its end
local function turfLane(m, x1, x2, z1, z2)
	local turf = Part(m, "TurfLane", V3(x2 - x1, 0.06, z2 - z1), CF((x1 + x2) / 2, FLOOR_Y + 0.03, (z1 + z2) / 2), rgb(46, 110, 58), M.Grass, { shadow = false })
	turf.Material = M.Fabric
	for z = z1 + 5, z2 - 1, 5 do
		Part(m, "TurfLine", V3(x2 - x1 - 0.6, 0.07, 0.25), CF((x1 + x2) / 2, FLOOR_Y + 0.035, z), C.white, M.SmoothPlastic, { shadow = false })
	end
	Part(m, "TurfEdge", V3(0.3, 0.08, z2 - z1), CF(x1 + 0.15, FLOOR_Y + 0.04, (z1 + z2) / 2), C.white, M.SmoothPlastic, { shadow = false })
	Part(m, "TurfEdge", V3(0.3, 0.08, z2 - z1), CF(x2 - 0.15, FLOOR_Y + 0.04, (z1 + z2) / 2), C.white, M.SmoothPlastic, { shadow = false })
	-- the sled: skids, deck, two uprights with grips, a plate on the post
	local cx, cz = (x1 + x2) / 2, z1 + 2.5
	for _, s in ipairs({ -1, 1 }) do
		Part(m, "SledSkid", V3(0.3, 0.3, 3.4), CF(cx + s * 1.1, FLOOR_Y + 0.2, cz), C.black, M.Metal)
		Rod(m, "SledUpright", V3(cx + s * 0.9, FLOOR_Y + 0.4, cz + 1.2), V3(cx + s * 0.9, FLOOR_Y + 3.6, cz + 1.8), 0.22, C.black, M.Metal)
		Part(m, "SledGrip", V3(0.3, 0.9, 0.3), CF(cx + s * 0.9, FLOOR_Y + 3.3, cz + 1.75), C.redDeep, M.Rubber)
	end
	Part(m, "SledDeck", V3(2.4, 0.2, 2.6), CF(cx, FLOOR_Y + 0.42, cz), C.black, M.DiamondPlate)
	VCyl(m, "SledPost", 1.2, 0.3, V3(cx, FLOOR_Y + 0.5, cz - 0.4), C.steelLight, M.Metal)
	Part(m, "SledPlate", V3(0.3, 2.2, 2.2), CF(cx, FLOOR_Y + 0.85, cz - 0.4) * A(0, 0, math.pi / 2), C.black, M.Rubber, { shape = "Cylinder" })
end

-- plate storage pegs on a wall with plates hung on them
local function platePegs(m, id, a1, n)
	for k = 0, n - 1 do
		local cf = onWall(id, a1 + k * 2.6, 4.2, 0.05)
		Part(m, "PegPlate", V3(0.9, 0.9, 0.2), cf * CF(0, 0, -0.1), C.black, M.Metal)
		Part(m, "Peg", V3(0.24, 0.24, 1.2), cf * CF(0, 0, -0.75), C.chrome, M.Metal)
		local size = 2.6 - (k % 3) * 0.5
		Part(m, "WallPlate", V3(0.35, size, size), cf * CF(0, -size / 2 + 0.6, -0.5) * A(0, math.pi / 2, 0), (k % 2 == 0) and C.black or rgb(40, 40, 46), M.Rubber, { shape = "Cylinder" })
	end
end

-- water stains / grime running down a wall under a window (an invisible patch carrying the grime decal)
local function wallGrime(m, id, along, y, w, h)
	local p = Part(m, "WallGrime", V3(w, h, 0.05), onWall(id, along, y, 0.04), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Decal(p, FACE.Front, "grime", { Transparency = 0.35 })
end

-- floor scuffs spread over an area
local function scuffField(m, x1, x2, z1, z2, n, seed)
	local rng = Random.new(seed)
	for _ = 1, n do
		local x, z = rng:NextNumber(x1, x2), rng:NextNumber(z1, z2)
		K.Patch(m, "FloorScuff", rng:NextNumber(3, 6), rng:NextNumber(3, 6), CF(x, FLOOR_Y, z) * A(0, rng:NextNumber(0, 6.28), 0), "scuffs", nil, rng:NextNumber(0.35, 0.6))
	end
end

-- a gear shelf on a wall: headgear and focus mitts on two shelves
local function gearShelf(m, cf)
	for k = 0, 1 do
		Part(m, "GearShelf", V3(6, 0.2, 1.4), cf * CF(0, -1.2 + k * 2.2, -0.7), C.woodDark, M.Wood)
		for _, x in ipairs({ -2.6, 2.6 }) do
			Part(m, "GearBracket", V3(0.15, 0.6, 1.2), cf * CF(x, -1.5 + k * 2.2, -0.6), C.steelDark, M.Metal, { shadow = false })
		end
	end
	local cols = { C.red, C.blue, C.black }
	for i = 0, 2 do
		-- headgear: a padded shell with the face opening and cheek pads
		local hg = cf * CF(-1.8 + i * 1.8, 1.55, -0.75)
		Ball(m, "Headgear", V3(1.1, 1.2, 1.1), hg, cols[i + 1], M.Leather)
		Part(m, "HeadgearFace", V3(0.6, 0.5, 0.06), hg * CF(0, -0.05, -0.53), C.ink, M.SmoothPlastic, { shadow = false })
		Part(m, "HeadgearBrow", V3(0.8, 0.22, 0.2), hg * CF(0, 0.3, -0.5), cols[i + 1]:Lerp(C.black, 0.3), M.Leather, { shadow = false })
		-- a pair of focus mitts below
		for _, sx in ipairs({ -0.35, 0.35 }) do
			local mt = cf * CF(-1.8 + i * 1.8 + sx, -0.75, -0.75) * A(RAD(-70), 0, 0)
			Part(m, "FocusMitt", V3(0.6, 0.8, 0.3), mt, i == 1 and C.gold or C.ink2, M.Leather)
			Part(m, "MittTarget", V3(0.32, 0.32, 0.04), mt * CF(0, 0.05, -0.17), C.red, M.SmoothPlastic, { shadow = false })
		end
	end
end

-- a body-opponent bag (BOB): water base, the torso and the head on its column
local function bob(m, pos)
	VCyl(m, "BobBase", 1.6, 2.6, pos, C.black, M.Plastic)
	VCyl(m, "BobColumn", 1.2, 0.8, pos + V3(0, 1.6, 0), C.ink2, M.Plastic)
	Ball(m, "BobTorso", V3(2.2, 2.6, 1.3), CF(pos + V3(0, 4.0, 0)), rgb(196, 160, 130), M.Plastic)
	Ball(m, "BobHead", V3(1.1, 1.3, 1.1), CF(pos + V3(0, 5.9, 0)), rgb(196, 160, 130), M.Plastic)
	Part(m, "BobChest", V3(1.2, 0.8, 0.05), CF(pos + V3(0, 4.4, -0.66)), C.redDeep, M.SmoothPlastic, { shadow = false })
end

-- an agility ladder taped on the floor and a few cones
local function agility(m, x1, z, rungs)
	local len = rungs * 1.5
	for _, dz in ipairs({ -0.75, 0.75 }) do
		Part(m, "LadderTape", V3(len, 0.04, 0.12), CF(x1 + len / 2, FLOOR_Y + 0.02, z + dz), C.yellow, M.SmoothPlastic, { shadow = false })
	end
	for k = 0, rungs do
		Part(m, "LadderTape", V3(0.12, 0.04, 1.5), CF(x1 + k * 1.5, FLOOR_Y + 0.02, z), C.yellow, M.SmoothPlastic, { shadow = false })
	end
	for k = 0, 3 do
		local p = V3(x1 + len + 2 + k * 1.6, FLOOR_Y, z + (k % 2 == 0 and -0.8 or 0.8))
		Part(m, "ConeBase", V3(0.8, 0.08, 0.8), CF(p + V3(0, 0.04, 0)), rgb(255, 120, 30), M.Plastic, { shadow = false })
		Part(m, "Cone", V3(0.7, 0.45, 0.45), CF(p + V3(0, 0.3, 0)) * A(0, 0, math.pi / 2), rgb(255, 120, 30), M.Plastic, { shape = "Cylinder", shadow = false })
		Part(m, "ConeTip", V3(0.3, 0.25, 0.25), CF(p + V3(0, 0.75, 0)) * A(0, 0, math.pi / 2), rgb(255, 120, 30), M.Plastic, { shape = "Cylinder", shadow = false })
	end
end

-- caged wall lights between the windows (fixtures: the hall's real light comes from the pendants)
local function cageLights(m)
	local spots = {
		{ "N", -87.5 }, { "N", -66 }, { "N", -54 }, { "N", 54 }, { "N", 66 }, { "N", 87.5 }, { "S", -87.5 }, { "S", -54 }, { "S", 54 }, { "S", 87.5 },
		{ "W", -35 }, { "W", 47 }, { "E", -35 }, { "E", 38 },
	}
	for _, sp in ipairs(spots) do
		local cf = onWall(sp[1], sp[2], 14.6, 0.05)
		Part(m, "CageMount", V3(0.7, 0.7, 0.2), cf * CF(0, 0, -0.1), C.steelDark, M.Metal, { shadow = false })
		Rod(m, "CageArm", (cf * CF(0, 0, -0.2)).Position, (cf * CF(0, 0.3, -0.9)).Position, 0.1, C.steelDark, M.Metal)
		Ball(m, "CageBulb", 0.5, cf * CF(0, 0.15, -1.05), rgb(255, 226, 170), M.Neon, { shadow = false })
		Part(m, "CageGuard", V3(0.08, 0.8, 0.8), cf * CF(0, 0.15, -1.05) * A(0, math.pi / 2, 0), C.ink, M.Metal, { shape = "Cylinder", t = 0.6, shadow = false })
	end
end

local function boxing1(m)
	tileFloor(m, "BoxingTiles", -45, 45, -70, 4, rgb(46, 48, 56), 3)
	canvasWeave(m)
	-- (between the zone sign and the painted wall slogans, and under the slogans)
	wallBanner(m, onWall("N", -17.2, 15.2, 0.12), 3.2, 11)
	wallBanner(m, onWall("N", 17.2, 15.2, 0.12), 3.2, 11)
	wallPoster(m, "posterFightNight", onWall("N", -33, 3.9, 0.1), 3.4, { text = "FIGHT\nNIGHT" })
	wallPoster(m, "posterRules", onWall("N", -26, 3.9, 0.1), 3.4, { text = "GYM\nRULES" })
	wallPoster(m, "posterUndisputed", onWall("N", 26, 3.9, 0.1), 3.4, { text = "UNDISPUTED" })
	wallPoster(m, "posterChampion", onWall("N", 33, 3.9, 0.1), 3.4, { text = "WORLD\nCHAMPION" })
	for _, x in ipairs({ -45, -15, 15, 45 }) do
		purlinBanner(m, x, -20, 3.4, 10.2)
	end
	wallGrime(m, "S", -100, 13.6, 6, 7)
	wallGrime(m, "S", 100, 13.6, 6, 7)
	wallGrime(m, "W", -3, 13.6, 6, 7)
	wallGrime(m, "W", 72, 13.6, 6, 7)
	wallGrime(m, "E", 22, 13.6, 6, 7)
	wallGrime(m, "E", 72, 13.6, 6, 7)
end

local function boxing2(m)
	ringCornerKit(m)
	trussBag(m, -30, -64, C.redDeep)
	trussBag(m, -30, -72, C.black)
	trussBag(m, 30, -66, C.black)
	hvlsFan(m, V3(0, 23.6, -15), 28.1)
	pedestalFan(m, V3(41, FLOOR_Y, -32), V3(-1, 0, -0.6).Unit)
	pedestalFan(m, V3(-42, FLOOR_Y, -60), V3(1, 0, 0.3).Unit)
	slipRope(m, V3(26, FLOOR_Y, -72), V3(42, FLOOR_Y, -72))
	maizeFrame(m, V3(-36, FLOOR_Y, -73), V3(1, 0, 0))
	ropeHooks(m, onWall("DWb", -38, 6.4, 0.08))
end

-- (the boxing area's dressing in two cells: no tier builds more than ~200 parts in one go)
local function boxing2b(m)
	-- the gear bench along the north wall: bags, towels, bottles
	local bcf = CF(18, FLOOR_Y, -77.2)
	place(BENCH, m, bcf)
	place(GYMBAG, m, bcf * CF(-1.6, 1.62, 0) * A(0, RAD(8), 0))
	place(TOWELS, m, bcf * CF(1.4, 1.62, 0.1))
	place(BOTTLE, m, bcf * CF(2.6, 1.62, -0.2))
	place(GYMBAG, m, bcf * CF(-3.8, 0, -0.9) * A(0, RAD(-20), 0))
	bottleCrate(m, CF(-44, FLOOR_Y, -76.5))
	place(CLOCK, m, onWall("N", -11.5, 11.2, 0.05))
	for i, st in ipairs({ V3(-34, 0, -10.4), V3(-18, 0, -11.5), V3(-2, 0, -10.4), V3(14, 0, -10.2), V3(32, 0, -9.5) }) do
		scuffsAt(m, st, 2, 100 + i)
	end
	scuffsAt(m, V3(-30, 0, -26.4), 3, 120)
	scuffField(m, -40, 40, -70, 0, 10, 130)
	gearShelf(m, onWall("DEb", -36, 3.2, 0.05))
	bob(m, V3(40, FLOOR_Y, -50))
	-- a spectators' bench east of the ring, a double-end bag on its cords west of it
	place(BENCH, m, CF(19.5, FLOOR_Y, -64) * A(0, RAD(90), 0))
	place(TOWELS, m, CF(19.5, FLOOR_Y + 1.62, -62.4) * A(0, RAD(90), 0))
	Ball(m, "DoubleEndBag", V3(1.0, 1.2, 1.0), CF(-42, 5.6, -45), C.redDeep, M.Leather)
	Rod(m, "DoubleEndCord", V3(-42, 6.2, -45), V3(-42, 28.1, -45), 0.06, C.ink, M.Rubber)
	Rod(m, "DoubleEndCord", V3(-42, 5.0, -45), V3(-42, FLOOR_Y + 0.2, -45), 0.06, C.ink, M.Rubber)
	Part(m, "DoubleEndEye", V3(0.6, 0.2, 0.6), CF(-42, FLOOR_Y + 0.1, -45), C.steelDark, M.Metal)
	agility(m, 20, -1, 9)
end

------------------------------------------------------------------------
-- weight room
------------------------------------------------------------------------
local BUMPER = { rgb(200, 40, 40), rgb(40, 90, 200), rgb(240, 200, 40), rgb(50, 160, 80), C.black }

local function bumperStack(m, cf)
	Part(m, "BumperToast", V3(2.6, 0.3, 1.6), cf * CF(0, 0.15, 0), C.steelDark, M.Metal)
	for k, col in ipairs(BUMPER) do
		local x = -1.0 + (k - 1) * 0.5
		Part(m, "Bumper", V3(0.42, 2.9 - k * 0.12, 2.9 - k * 0.12), cf * CF(x, 0.3 + (2.9 - k * 0.12) / 2, 0), col, M.Rubber, { shape = "Cylinder" })
		Part(m, "BumperHub", V3(0.44, 0.7, 0.7), cf * CF(x, 0.3 + (2.9 - k * 0.12) / 2, 0), C.chrome, M.Metal, { shape = "Cylinder" })
	end
end

-- a vertical bar holder with four Olympic bars standing in it (knurled grips, chrome sleeves)
local function barHolder(m, cf)
	Part(m, "HolderBase", V3(3.2, 0.4, 1.2), cf * CF(0, 0.2, 0), C.black, M.Metal)
	Part(m, "HolderTop", V3(3.2, 0.25, 0.3), cf * CF(0, 5.2, 0.55), C.black, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Part(m, "HolderPost", V3(0.25, 5.2, 0.25), cf * CF(s * 1.5, 2.8, 0.55), C.black, M.Metal)
	end
	for k = 0, 3 do
		local x = -1.1 + k * 0.73
		local base = cf * CF(x, 0.4, 0)
		VCyl(m, "BarSleeve", 1.4, 0.32, base, C.chrome, M.Metal)
		VCyl(m, "BarShaft", 5.4, 0.18, base * CF(0, 1.4, 0), C.steelLight, M.Metal)
		VCyl(m, "BarKnurl", 1.4, 0.2, base * CF(0, 2.6, 0), C.steel, M.DiamondPlate)
		VCyl(m, "BarKnurl", 1.4, 0.2, base * CF(0, 4.4, 0), C.steel, M.DiamondPlate)
	end
end

-- lifting belts on wall hooks
local function beltHooks(m, cf)
	Part(m, "BeltBoard", V3(4.2, 0.7, 0.15), cf, C.black, M.Metal)
	local cols = { C.black, rgb(120, 70, 40), C.redDeep }
	for k = -1, 1 do
		local hook = cf * CF(k * 1.3, 0, -0.3)
		Part(m, "BeltHook", V3(0.12, 0.12, 0.45), cf * CF(k * 1.3, 0, -0.2), C.chrome, M.Metal)
		Part(m, "Belt", V3(0.9, 2.4, 0.12), hook * CF(0, -1.25, 0), cols[k + 2], M.Leather)
		Part(m, "BeltBuckle", V3(0.5, 0.45, 0.08), hook * CF(0, -2.2, -0.08), C.chrome, M.Metal)
	end
end

-- an adjustable bench (pad, back pad raised, frame, wheels)
local function adjustableBench(m, cf)
	Part(m, "AdjSeat", V3(1.3, 0.4, 1.8), cf * CF(0, 1.5, 1.2), C.black, M.Leather)
	Part(m, "AdjBack", V3(1.3, 0.4, 3.4), cf * CF(0, 2.3, -0.9) * A(RAD(-25), 0, 0), C.black, M.Leather)
	Part(m, "AdjSeam", V3(1.32, 0.05, 3.42), cf * CF(0, 2.26, -0.9) * A(RAD(-25), 0, 0) * CF(0, -0.12, 0), C.red, M.Fabric)
	Part(m, "AdjSpine", V3(0.4, 0.3, 4.8), cf * CF(0, 0.9, 0), C.steelDark, M.Metal)
	Part(m, "AdjFootF", V3(2.0, 0.3, 0.4), cf * CF(0, 0.15, 2.2), C.steelDark, M.Metal)
	Part(m, "AdjFootB", V3(2.0, 0.3, 0.4), cf * CF(0, 0.15, -2.2), C.steelDark, M.Metal)
	Part(m, "AdjPost", V3(0.3, 1.3, 0.3), cf * CF(0, 1.3, -0.5) * A(RAD(-25), 0, 0), C.steelDark, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		Part(m, "AdjWheel", V3(0.25, 0.5, 0.5), cf * CF(s * 0.85, 0.25, -2.35), C.rubber, M.Rubber, { shape = "Cylinder" })
	end
end

local function foamRollers(m, cf)
	Part(m, "RollerBin", V3(2.2, 1.6, 1.6), cf * CF(0, 0.8, 0), C.ink2, M.Plastic)
	local cols = { C.blue, C.black, C.red, C.gold }
	for k = 0, 3 do
		VCyl(m, "FoamRoller", 2.8, 0.6, cf * CF(-0.6 + (k % 2) * 1.2, 0.3, -0.35 + math.floor(k / 2) * 0.7), cols[k + 1], M.Fabric)
	end
end

local function weights1(m)
	-- (the weight room's floor already has 6-stud tile seams: same grid)
	tileFloor(m, "WeightTiles", -108, -50, -78, 18, rgb(30, 30, 32), 3)
	wallPoster(m, "posterRules", onWall("N", -84, 7.5, 0.1), 3.4, { text = "GYM\nRULES" })
	wallPoster(m, "posterUndisputed", onWall("N", -66, 7.5, 0.1), 3.4, { text = "UNDISPUTED" })
	wallPoster(m, "posterFightNight", onWall("W", -36, 9.5, 0.1), 3.4, { text = "FIGHT\nNIGHT" })
end

local function weights2(m)
	bumperStack(m, CF(-72, FLOOR_Y, -76.6))
	barHolder(m, CF(-80, FLOOR_Y, -77.4))
	beltHooks(m, onWall("W", -40, 7, 0.08))
	adjustableBench(m, CF(-104.5, FLOOR_Y, -70) * A(0, RAD(90), 0))
	foamRollers(m, CF(-67.5, FLOOR_Y, -76))
	turfLane(m, -59, -53, -36, -18.5)
	scuffField(m, -105, -55, -75, 15, 7, 230)
	platePegs(m, "W", -76, 5)
	place(CLOCK, m, onWall("W", -3, 12, 0.05))
	place(TOWELS, m, CF(-67.0, FLOOR_Y + 1.6, -76))
	for i, st in ipairs({ V3(-92, 0, -24), V3(-72, 0, -24.3), V3(-72, 0, -51.5) }) do
		scuffsAt(m, st, 2, 200 + i)
	end
end

------------------------------------------------------------------------
-- cardio room
------------------------------------------------------------------------
local function cleaningStation(m, cf)
	Part(m, "CleanShelf", V3(3.6, 0.2, 0.9), cf * CF(0, -0.6, -0.45), C.steelLight, M.Metal)
	Part(m, "TowelDispenser", V3(1.4, 1.8, 0.7), cf * CF(-0.9, 0.6, -0.35), C.white, M.Plastic)
	Part(m, "DispenserSlot", V3(1.0, 0.1, 0.02), cf * CF(-0.9, -0.1, -0.71), C.ink, M.SmoothPlastic)
	Part(m, "SanitizerBox", V3(0.8, 1.2, 0.5), cf * CF(0.9, 0.4, -0.25), C.blueDeep, M.Plastic)
	for k = 0, 1 do
		local b = cf * CF(0.4 + k * 0.7, -0.5, -0.45)
		VCyl(m, "SprayBottle", 0.7, 0.32, b, k == 0 and C.blue or C.green, M.Plastic)
		Part(m, "SprayHead", V3(0.18, 0.22, 0.32), b * CF(0, 0.8, -0.05), C.white, M.Plastic)
	end
	local sg = K.Gui(Part(m, "CleanSign", V3(2.4, 0.8, 0.04), cf * CF(0, 1.9, -0.03), C.white, M.SmoothPlastic), FACE.Front, 40, 1)
	K.Text(sg, "WIPE IT DOWN", { TextColor3 = C.redDeep, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15) })
end

local function matRack(m, cf)
	Part(m, "MatRackBack", V3(4.2, 2.6, 0.15), cf, C.steelDark, M.Metal)
	local cols = { C.blue, C.red, C.black, C.gold, rgb(120, 60, 160) }
	for k = 0, 4 do
		local p = cf * CF(-1.7 + k * 0.85, 0, -0.45)
		Part(m, "YogaMat", V3(2.4, 0.7, 0.7), p * A(0, 0, math.pi / 2), cols[k + 1], M.Rubber, { shape = "Cylinder" })
		Part(m, "MatStrap", V3(0.1, 0.75, 0.75), p * CF(0, 0.6, 0) * A(0, 0, math.pi / 2) * A(0, 0, math.pi / 2), C.ink, M.Fabric, { shape = "Cylinder" })
	end
end

local function cardio1(m)
	tileFloor(m, "CardioTiles", 50, 108, -78, 18, rgb(35, 50, 70), 3)
	wallPoster(m, "posterChampion", onWall("E", -38, 7.5, 0.1), 3.4, { text = "WORLD\nCHAMPION" })
	wallPoster(m, "posterUndisputed", onWall("N", 66, 9, 0.1), 3.4, { text = "UNDISPUTED" })
end

local function cardio2(m)
	cleaningStation(m, onWall("E", -46, 4.6, 0.05))
	matRack(m, onWall("E", -28, 4.2, 0.08))
	place(CLOCK, m, onWall("E", -22, 12.5, 0.05))
	place(BENCH, m, CF(104, FLOOR_Y, -74) * A(0, RAD(90), 0))
	place(TOWELS, m, CF(104.1, FLOOR_Y + 1.62, -72.4) * A(0, RAD(90), 0))
	place(BOTTLE, m, CF(104.0, FLOOR_Y + 1.62, -75.9))
	for i, st in ipairs({ V3(70, 0, -24.4), V3(92, 0, -26) }) do
		scuffsAt(m, st, 2, 300 + i)
	end
	scuffField(m, 55, 105, -75, 15, 5, 330)
end

------------------------------------------------------------------------
-- lobby, services, recovery
------------------------------------------------------------------------
local function coatRack(m, pos)
	VCyl(m, "CoatBase", 0.2, 1.6, pos, C.black, M.Metal)
	VCyl(m, "CoatPole", 6.4, 0.22, pos + V3(0, 0.2, 0), C.woodDark, M.Wood)
	for k = 0, 3 do
		local a = k * math.pi / 2
		local d = V3(math.cos(a), 0, math.sin(a))
		Rod(m, "CoatHook", pos + V3(0, 6.0, 0), pos + V3(0, 6.4, 0) + d * 0.6, 0.1, C.brass, M.Metal)
	end
	Part(m, "Hoodie", V3(1.4, 2.4, 0.6), CFrame.lookAt(pos + V3(0.55, 5.0, 0), pos + V3(2, 5.0, 0)), C.redDeep, M.Fabric)
	Part(m, "HoodieLogo", V3(0.6, 0.4, 0.02), CFrame.lookAt(pos + V3(0.86, 5.3, 0), pos + V3(2, 5.3, 0)), C.gold, M.SmoothPlastic)
	Part(m, "Jacket", V3(1.3, 2.6, 0.5), CFrame.lookAt(pos + V3(-0.5, 4.9, 0.2), pos + V3(-2, 4.9, 0.4)), C.ink2, M.Fabric)
end

local function lockerDetail(m)
	for i = 0, 7 do
		local x = -80 + i * 3.1
		Part(m, "LockerHandle", V3(0.14, 0.9, 0.14), CF(x + 1.0, 4.2, 26.1), C.chrome, M.Metal)
		local plate = Part(m, "LockerNumber", V3(0.8, 0.4, 0.04), CF(x, 7.3, 26.04), C.chrome, M.Metal)
		local sg = K.Gui(plate, FACE.Back, 40, 1)
		K.Text(sg, string.format("%02d", i + 1), { TextColor3 = C.ink, Font = Enum.Font.GothamBold })
		for k = 0, 2 do
			Part(m, "LockerSlot", V3(2.0, 0.08, 0.04), CF(x, 1.2 + k * 0.3, 26.04), rgb(20, 20, 26), M.SmoothPlastic)
		end
		if i % 3 == 1 then
			Part(m, "Padlock", V3(0.32, 0.36, 0.18), CF(x + 1.0, 3.55, 26.2), C.redDeep, M.Metal)
			Part(m, "PadlockShackle", V3(0.22, 0.2, 0.06), CF(x + 1.0, 3.82, 26.2), C.chrome, M.Metal)
		end
	end
	-- a towel stack at the locker bench (-69, z 32; the server put the bags and shoes there)
	place(TOWELS, m, CF(-69.5, 1.6, 32.1))
end

-- the barber's vanity light bar over the mirror, and a magazine table by the waiting chairs
local function barberDetail(m)
	Part(m, "VanityBar", V3(10.2, 0.4, 0.4), CF(-95, 9.4, 28.1), C.chrome, M.Metal, { shadow = false })
	for k = 0, 5 do
		Ball(m, "VanityBulb", 0.45, CF(-99.5 + k * 1.8, 9.2, 27.85), rgb(255, 236, 200), M.Neon, { shadow = false })
	end
	Part(m, "MagTable", V3(1.8, 0.15, 1.8), CF(-106.4, 2.0, 39.8), C.woodDark, M.Wood)
	VCyl(m, "MagTableLeg", 1.5, 0.2, V3(-106.4, FLOOR_Y, 39.8), C.steelDark, M.Metal)
	local cols = { C.red, C.blue, C.gold }
	for k = 0, 2 do
		local mag = Part(m, "Magazine", V3(0.9, 0.05, 1.2), CF(-106.4 + (k - 1) * 0.25, 2.1 + k * 0.05, 39.8) * A(0, RAD(k * 25 - 20), 0), C.white, M.SmoothPlastic, { shadow = false })
		Part(m, "MagazineCover", V3(0.86, 0.02, 0.6), mag.CFrame * CF(0, 0.03, -0.25), cols[k + 1], M.SmoothPlastic, { shadow = false })
	end
end

-- the nutrition bar's counter kit: coffee machine, shakers, napkins
local function barKit(m)
	local top = 4.4
	Part(m, "CoffeeBody", V3(1.4, 1.8, 1.2), CF(-78.4, top + 0.9, 70.3), C.ink2, M.Metal)
	Part(m, "CoffeeHead", V3(1.0, 0.3, 0.6), CF(-78.4, top + 1.2, 69.5), C.chrome, M.Metal, { shadow = false })
	VCyl(m, "CoffeeCup", 0.4, 0.35, V3(-78.4, top, 69.5), C.white, M.SmoothPlastic)
	Part(m, "CoffeeLED", V3(0.5, 0.18, 0.04), CF(-78.4, top + 1.55, 69.68), rgb(80, 200, 255), M.Neon, { shadow = false })
	local cols = { C.red, C.ink, C.gold }
	for k = 0, 2 do
		VCyl(m, "Shaker", 0.85, 0.42, V3(-62.6 + k * 0.6, top, 70.6), cols[k + 1], M.Plastic, { t = 0.1 })
		VCyl(m, "ShakerLid", 0.18, 0.44, V3(-62.6 + k * 0.6, top + 0.85, 70.6), C.ink, M.Plastic)
	end
	Part(m, "Napkins", V3(0.7, 0.6, 0.4), CF(-73.2, top + 0.3, 70.8), C.chrome, M.Metal, { shadow = false })
end

-- recovery extras: an ice machine, an oil shelf by the massage table
local function recoveryKit(m)
	Part(m, "IceMachine", V3(2.4, 4.6, 2.2), CF(106.6, FLOOR_Y + 2.3, 30.5), C.chrome, M.Metal)
	Part(m, "IceDoor", V3(0.06, 1.4, 1.6), CF(105.37, FLOOR_Y + 3.4, 30.5), rgb(160, 200, 230), M.Glass, { shadow = false })
	Part(m, "IceLogo", V3(0.04, 0.5, 1.4), CF(105.37, FLOOR_Y + 4.4, 30.5), C.blueDeep, M.SmoothPlastic, { shadow = false })
	local shelf = onWall("DZs", 60, 5.2, 0.05)
	Part(m, "OilShelf", V3(4, 0.2, 1.0), shelf * CF(0, 0, -0.5), C.woodDark, M.Wood)
	for k = 0, 4 do
		VCyl(m, "OilBottle", 0.7 + (k % 2) * 0.2, 0.3, (shelf * CF(-1.6 + k * 0.8, 0.1, -0.5)).Position, ({ C.gold, C.green, rgb(160, 90, 40) })[k % 3 + 1], M.Glass, { t = 0.15 })
	end
end

-- framed fight photos on the lobby's south wall (west of the hall of fame)
local PHOTOS = { "1987", "FIRST\nTITLE", "SPAR\nDAY", "OLD\nPETE", "GOLDEN\nGLOVES", "RIVERA", "ROAD\nWORK", "KOVAC", "CHAMPS" }
local function photoWall(m)
	for i, txt in ipairs(PHOTOS) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local cf = onWall("S", -54 + col * 3.1, 12.4 - row * 2.6, 0.06)
		Part(m, "PhotoFrame", V3(2.6, 2.1, 0.08), cf * CF(0, 0, 0.02), C.black, M.Wood, { shadow = false })
		local ph = Part(m, "Photo", V3(2.2, 1.7, 0.04), cf * CF(0, 0, -0.04), rgb(60, 56, 50), M.SmoothPlastic, { shadow = false })
		local sg = K.Gui(ph, FACE.Front, 30, 1)
		local f = K.Frame(sg, { BackgroundColor3 = rgb(70 + (i * 13) % 50, 60 + (i * 7) % 30, 50) })
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(80, 70, 60))
		g.Rotation = 90
		g.Parent = f
		K.Text(sg, txt, { TextColor3 = rgb(240, 230, 210), Font = Enum.Font.GothamBold, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.4) })
	end
end

local function robeHooks(m, cf)
	Part(m, "RobeBoard", V3(7.2, 0.8, 0.15), cf, C.woodDark, M.Wood)
	for k = -1, 1 do
		local hook = cf * CF(k * 2.3, 0, -0.3)
		Part(m, "RobeHook", V3(0.14, 0.14, 0.45), cf * CF(k * 2.3, 0, -0.2), C.brass, M.Metal)
		Part(m, "Robe", V3(1.8, 3.6, 0.5), hook * CF(0, -1.9, -0.05), k == 0 and C.ink or C.redDeep, M.Fabric)
		Part(m, "RobeTrim", V3(0.25, 3.6, 0.52), hook * CF(0, -1.9, -0.06), C.gold, M.Fabric)
		Part(m, "RobeBelt", V3(1.82, 0.22, 0.54), hook * CF(0, -2.2, -0.06), C.gold, M.Fabric)
	end
end

-- a merch display in the lobby: slat wall with WCB tees, gloves and a price strip
local function merchWall(m, cf)
	Part(m, "SlatWall", V3(8, 6, 0.2), cf, C.ink, M.Wood)
	for k = 0, 5 do
		Part(m, "Slat", V3(8, 0.08, 0.06), cf * CF(0, -2.6 + k * 1.0, -0.13), C.steelDark, M.Metal, { shadow = false })
	end
	local tees = { C.ink2, C.redDeep, C.white }
	for k = 0, 2 do
		local t = cf * CF(-2.6 + k * 2.6, 1.0, -0.4)
		Part(m, "TeeHanger", V3(1.6, 0.08, 0.08), t * CF(0, 1.15, 0), C.chrome, M.Metal, { shadow = false })
		Part(m, "Tee", V3(1.8, 2.1, 0.12), t, tees[k + 1], M.Fabric, { shadow = false })
		Part(m, "TeeSleeves", V3(2.8, 0.7, 0.1), t * CF(0, 0.7, 0), tees[k + 1], M.Fabric, { shadow = false })
		local logo = Part(m, "TeeLogo", V3(0.9, 0.6, 0.02), t * CF(0, 0.2, -0.07), C.gold, M.SmoothPlastic, { shadow = false })
		local sg = K.Gui(logo, FACE.Front, 40, 1)
		K.Text(sg, "WCB", { TextColor3 = k == 2 and C.redDeep or C.gold, Font = Enum.Font.GothamBlack })
		logo.Transparency = 1
	end
	for k = 0, 3 do
		local g = cf * CF(-3 + k * 2, -1.6, -0.55)
		Ball(m, "MerchGlove", V3(0.8, 1.0, 0.9), g, (k % 2 == 0) and C.red or C.blue, M.Leather)
		Part(m, "MerchGloveCuff", V3(0.65, 0.4, 0.7), g * CF(0, -0.6, 0), C.white, M.Leather)
	end
	local strip = Part(m, "PriceStrip", V3(8, 0.6, 0.05), cf * CF(0, -2.75, -0.15), C.gold, M.SmoothPlastic, { shadow = false })
	K.Sign(strip, FACE.Front, "WCB PRO SHOP  -  ASK AT THE DESK", C.ink, C.gold, 30, Enum.Font.GothamBold)
end

local function lobby2(m)
	hvlsFan(m, V3(0, 23.6, 48), 28.1)
	photoWall(m)
	coatRack(m, V3(-18.5, 0.4, 76))
	merchWall(m, onWall("S", 26.6, 4.2, 0.12))
	place(CLOCK, m, onWall("S", -48, 11, 0.05))
end

local function services2(m)
	lockerDetail(m)
	barberDetail(m)
	barKit(m)
	wallBanner(m, onWall("S", -97, 9.5, 0.12), 3.2, 9)
	wallPoster(m, "posterFightNight", onWall("S", -103, 7, 0.1), 3.4, { text = "FIGHT\nNIGHT" })
	place(CLOCK, m, onWall("DZs", -60, 7.5, 0.05))
	for k = 0, 2 do
		place(GYMBAG, m, CF(-100 + k * 7, FLOOR_Y, 71.6) * A(0, RAD(90 + k * 15), 0))
	end
end

local function recovery2(m)
	recoveryKit(m)
	robeHooks(m, onWall("E", 64, 7.6, 0.08))
	local san = onWall("DZs", 98, 4.6, 0.05)
	Part(m, "Sanitizer", V3(0.8, 1.2, 0.5), san * CF(0, 0, -0.25), C.white, M.Plastic)
	Part(m, "SanitizerPump", V3(0.3, 0.2, 0.4), san * CF(0, -0.7, -0.35), C.ink, M.Plastic)
	place(CLOCK, m, onWall("E", 18, 12.5, 0.05))
end

------------------------------------------------------------------------
-- ceiling services (tier 3): sprinklers and conduit
------------------------------------------------------------------------
local SPRINKLER_RED = rgb(180, 30, 32)

local function sprinklerMain(m, z, x1, x2)
	local y = 27.6
	Rod(m, "SprinklerMain", V3(x1, y, z), V3(x2, y, z), 0.45, SPRINKLER_RED, M.Metal)
	for x = -90, 90, 30 do
		if x > x1 and x < x2 then
			Rod(m, "PipeHanger", V3(x, y + 0.2, z), V3(x, 28.1, z), 0.08, C.steelDark, M.Metal)
		end
	end
	local x = x1 + 9
	while x < x2 - 3 do
		Rod(m, "SprinklerDrop", V3(x, y, z), V3(x, y - 0.7, z), 0.14, SPRINKLER_RED, M.Metal)
		VCyl(m, "SprinklerHead", 0.08, 0.42, V3(x, y - 0.82, z), C.brass, M.Metal)
		x += 18
	end
end

local function conduit(m, id, a1, a2, y, drops)
	local w = WALLS[id]
	local p1 = onWall(id, a1, y, 0.2).Position
	local p2 = onWall(id, a2, y, 0.2).Position
	Rod(m, "Conduit", p1, p2, 0.2, C.steelLight, M.Metal)
	for _, a in ipairs(drops) do
		local top = onWall(id, a, y, 0.2)
		Part(m, "JunctionBox", V3(0.7, 0.7, 0.35), top * CF(0, 0, 0.05), C.steelLight, M.Metal)
		local low = onWall(id, a, 1.6, 0.2)
		Rod(m, "ConduitDrop", top.Position, low.Position + V3(0, 0.3, 0), 0.16, C.steelLight, M.Metal)
		Part(m, "Outlet", V3(0.6, 0.9, 0.25), low * CF(0, 0, 0.05), C.white, M.Plastic)
		Part(m, "OutletFace", V3(0.3, 0.5, 0.02), low * CF(0, 0, -0.08), rgb(220, 220, 214), M.SmoothPlastic)
		local _ = w
	end
end

-- window blinds: a roller box over each window opening and a half-drawn slatted blind (inside face)
local WINDOWS = {
	N = { -100, -75, -45, 45, 75, 100 },
	S = { -100, -75, -45, 45, 75, 100 },
	W = { -66, -3, 22, 72 },
	E = { -66, -3, 22, 72 },
}
local function blinds(m)
	for id, list in pairs(WINDOWS) do
		for i, a in ipairs(list) do
			local drop = 2.2 + ((i * 7 + #id) % 3) * 0.9
			local top = onWall(id, a, 24.35, 1.35)
			Part(m, "BlindBox", V3(10.4, 0.5, 0.5), top, C.white, M.SmoothPlastic, { shadow = false })
			local slat = Part(m, "Blind", V3(9.8, drop, 0.05), top * CF(0, -drop / 2 - 0.2, 0), rgb(232, 228, 216), M.Fabric, { shadow = false, t = 0.08 })
			local sg = K.Gui(slat, FACE.Front, 8, 1)
			local n = math.floor(drop / 0.3)
			for k = 0, n - 1 do
				K.Frame(sg, { BackgroundColor3 = rgb(196, 192, 180), Size = UDim2.fromScale(1, 0.12 / n), Position = UDim2.fromScale(0, (k + 0.9) / n) })
			end
			Part(m, "BlindRail", V3(9.9, 0.12, 0.12), top * CF(0, -drop - 0.25, 0), rgb(200, 196, 186), M.Metal, { shadow = false })
			Part(m, "BlindCord", V3(0.04, drop + 2, 0.04), top * CF(4.6, -drop / 2 - 1.1, -0.06), C.white, M.Fabric, { shadow = false })
		end
	end
end

-- heating / water pipes along the top of the outer walls, on brackets
local function wallPipes(m)
	local runs = { { "N", -107, 107 }, { "S", -107, 107 }, { "W", -77, 77 }, { "E", -77, 77 } }
	for _, r in ipairs(runs) do
		for k, y in ipairs({ 27.2, 26.7 }) do
			local a = onWall(r[1], r[2], y, 1.55 + k * 0.05).Position
			local b = onWall(r[1], r[3], y, 1.55 + k * 0.05).Position
			Rod(m, "WallPipe", a, b, k == 1 and 0.42 or 0.28, k == 1 and rgb(150, 154, 160) or rgb(170, 120, 60), M.Metal)
		end
		local x = r[2] + 4
		while x < r[3] - 2 do
			local cf = onWall(r[1], x, 27.0, 0.85)
			Part(m, "PipeBracket", V3(0.18, 1.4, 1.7), cf, C.steelDark, M.Metal, { shadow = false })
			x += 12
		end
	end
end

-- cable trays along the roof trusses (z run, just under the bottom chord)
local function cableTrays(m)
	for _, x in ipairs({ -90, -60, -30, 0, 30, 60, 90 }) do
		Part(m, "CableTray", V3(1.2, 0.25, 156), CF(x + 1.2, 27.65, 0), C.steelLight, M.Metal, { shadow = false })
		Part(m, "TrayCables", V3(0.9, 0.18, 156), CF(x + 1.2, 27.8, 0), C.ink2, M.Rubber, { shadow = false })
		for z = -70, 70, 20 do
			Rod(m, "TrayHanger", V3(x + 1.2, 27.8, z), V3(x + 1.2, 28.1, z), 0.06, C.steelDark, M.Metal)
		end
	end
end

-- cast-iron radiators low on a wall
local function radiator(m, id, a)
	local cf = onWall(id, a, 1.9, 0.5)
	Part(m, "RadiatorTop", V3(4.4, 0.15, 0.7), cf * CF(0, 1.2, 0), rgb(214, 210, 200), M.Metal, { shadow = false })
	for k = 0, 9 do
		Part(m, "RadiatorFin", V3(0.26, 2.3, 0.6), cf * CF(-2.0 + k * 0.44, 0, 0), rgb(214, 210, 200), M.Metal, { shadow = false })
	end
	Rod(m, "RadiatorPipe", (cf * CF(2.3, -0.9, 0)).Position, (cf * CF(2.3, -1.4, 0)).Position, 0.16, C.chrome, M.Metal)
end

local function ceiling3(m)
	for _, z in ipairs({ -50, -10 }) do
		sprinklerMain(m, z, -107, 107)
	end
	conduit(m, "N", -45, -9, 10.3, { -44, -18 })
	conduit(m, "N", 9, 45, 10.3, { 16, 44 })
	conduit(m, "W", -76, -48, 13.5, { -74 })
	cableTrays(m)
end

local function ceiling3b(m)
	for _, z in ipairs({ 25, 52 }) do
		sprinklerMain(m, z, -107, 107)
	end
	wallPipes(m)
	cageLights(m)
	radiator(m, "W", 14)
	radiator(m, "E", 14)
	radiator(m, "E", 64)
end

------------------------------------------------------------------------
-- registration
------------------------------------------------------------------------
function GymDetail.Register(streamer)
	streamer:Add("GymBoxing", V3(0, 8, -38), 52, { boxing1, boxing2 })
	streamer:Add("GymBoxingKit", V3(0, 4, -38), 52, { nil, boxing2b })
	streamer:Add("GymWeights", V3(-79, 8, -30), 52, { weights1, weights2 })
	streamer:Add("GymCardio", V3(79, 8, -30), 52, { cardio1, cardio2 })
	streamer:Add("GymLobby", V3(0, 10, 55), 48, { nil, lobby2 })
	streamer:Add("GymServices", V3(-79, 8, 50), 40, { nil, services2 })
	streamer:Add("GymRecovery", V3(79, 8, 50), 40, { nil, recovery2 })
	streamer:Add("GymCeiling", V3(0, 26, 0), 110, { nil, blinds, ceiling3 })
	streamer:Add("GymCeilingWalls", V3(0, 22, 0), 110, { nil, nil, ceiling3b })
end

GymDetail.WALLS = WALLS
GymDetail.OnWall = onWall
GymDetail.Hall = HALL
return GymDetail
