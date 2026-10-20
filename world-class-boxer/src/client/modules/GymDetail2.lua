-- GymDetail2: the training complex's second detail pass (client-only, on DetailKit's Streamer like GymDetail, which
-- registers it). The lived-in championship gym: walls of print, kit on every wall, worn floors, a weigh-in corner.
-- Same rules as GymDetail: every piece anchored, no collision / queries / touches, against a wall, on the ceiling,
-- flat on the floor or in a corner the stations, their cameras, the members and the walkways leave free
-- (tools/sim/test_worlddetail.luau checks the keep-out boxes). Repeated props are templates (built once, cloned);
-- print is uploaded textures (WorldAssetData) with part-built fallbacks.
--   tier 1  painted block-wall texture on the zone dividers, the fight-bill wall and the clippings board, stencilled
--           slogans, the Hall of Champions wall, the training whiteboard, rubber mats round the ring
--   tier 2  the coach's corner cart, the speed-bag wall, wall-bracket uppercut and water bags, the glove wall,
--           hand wraps drying on a line, kettlebell row, medicine-ball wall rack, dip station, rope climb, plyo
--           box stacks, the weigh-in corner (backdrop, scale, height chart, table), a drinks machine, the locker
--           room TV (a looping fight broadcast: Ambience TVLoop), boombox, jackets on hooks, laundry bin, mop and
--           bucket, bag piles, first-aid kit and extinguisher by the desk, a desk radio, towel bin; floor wear,
--           puddles by the water coolers and showers, chipped paint
--   tier 3  caged work lamps on chains, column knee braces with gusset plates and bolts, purlin clips, the round
--           timer's cable
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local GymDetail2 = {}

local FLOOR_Y = 0.5 -- top of the zone floors (boxing, weights, cardio, services)
local LOBBY_Y = 0.4 -- the lobby's plank floor
local TRUSS_Y = 28.1 -- under the roof trusses' bottom chord (trusses at x = -90, -60 .. 90)
local DIVIDER = rgb(70, 72, 80)

local onWall -- GymDetail.OnWall (set in Register)

-- a flat overlay over a wall face carrying a tiled Texture (the overlay part itself is invisible)
local function wallTexture(m, id, along, y, w, h, key, tile, color, transp)
	local p = Part(m, "WallTexture", V3(w, h, 0.04), onWall(id, along, y, 0.025), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Texture(p, FACE.Front, key, tile, tile, { Color3 = color, Transparency = transp or 0 })
	return p
end

-- a decal on an invisible wall patch (stencils, chips): nil when the image is not available
local function wallDecal(m, name, id, along, y, w, h, key, color, transp, out)
	if not K.Asset(key) then
		return nil
	end
	local p = Part(m, name, V3(w, h, 0.04), onWall(id, along, y, out or 0.035), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Decal(p, FACE.Front, key, { Color3 = color or Color3.new(1, 1, 1), Transparency = transp or 0 })
	return p
end

-- a printed board on a wall (an uploaded image on its front; without it the fallback text on a colour)
local function wallPrint(m, name, id, along, y, w, h, key, fallback, out)
	local p = Part(m, name, V3(w, h, 0.08), onWall(id, along, y, (out or 0.06) + 0.04), C.paper, M.SmoothPlastic, { shadow = false })
	if not K.Decal(p, FACE.Front, key) then
		local fb = fallback or {}
		K.Sign(p, FACE.Front, fb.text or "WCB", fb.fg or C.gold, fb.bg or C.ink, 16, Enum.Font.GothamBlack)
	end
	return p
end

-- the tint that brings a mid-grey (0.6) texture back to a surface colour
local function tintFor(col, base)
	local k = 1 / (base or 0.6)
	return Color3.new(math.min(1, col.R * k), math.min(1, col.G * k), math.min(1, col.B * k))
end

-- a flat floor decal (wear, puddles) on the zone floor at (x, z)
local function floorPatch(m, key, x, z, w, l, yaw, floorY, transp)
	return K.Patch(m, key == "puddle" and "Puddle" or "FloorWear", w, l, CF(x, floorY or FLOOR_Y, z) * A(0, yaw or 0, 0), key, nil, transp or 0)
end

------------------------------------------------------------------------
-- templates
------------------------------------------------------------------------
-- a kettlebell: bell, flat base, handle (two posts and the grip); s = scale (1 = 16 kg)
local function kettlebellTpl(name, s, col)
	return K.Template(name, function(t)
		Ball(t, "KBBell", V3(1.0 * s, 0.92 * s, 1.0 * s), CF(0, 0.46 * s, 0), col, M.Metal)
		for _, x in ipairs({ -0.3, 0.3 }) do
			Part(t, "KBPost", V3(0.14 * s, 0.38 * s, 0.14 * s), CF(x * s, 0.98 * s, 0) * A(0, 0, RAD(x > 0 and -12 or 12)), col, M.Metal, { shadow = false })
		end
		Cyl(t, "KBGrip", 0.66 * s, 0.14 * s, CF(0, 1.16 * s, 0), col, M.Metal, { shadow = false })
	end)
end
local KB = {
	kettlebellTpl("KB_S", 0.8, rgb(40, 140, 80)), kettlebellTpl("KB_M", 1.0, rgb(200, 150, 40)),
	kettlebellTpl("KB_L", 1.2, rgb(190, 40, 40)), kettlebellTpl("KB_XL", 1.35, rgb(60, 60, 66)),
}

-- a stack of three soft plyo boxes (foam, a coloured top band each)
local PLYO = K.Template("PlyoStack", function(t)
	local boxes = { { V3(3.2, 2.0, 2.6), C.black, C.red }, { V3(2.8, 1.6, 2.2), C.ink2, C.blue }, { V3(2.3, 1.2, 1.8), C.black, C.gold } }
	local y = 0
	for i, b in ipairs(boxes) do
		local cf = CF(0, y + b[1].Y / 2, 0) * A(0, RAD((i - 2) * 7), 0)
		Part(t, "PlyoBox", b[1], cf, b[2], M.Fabric)
		Part(t, "PlyoBand", V3(b[1].X + 0.04, 0.22, b[1].Z + 0.04), cf * CF(0, b[1].Y / 2 - 0.2, 0), b[3], M.Fabric, { shadow = false })
		y += b[1].Y
	end
end)

-- a duffel bag lying on the floor (body, end panels, strap, zip)
local DUFFEL = K.Template("Duffel2", function(t)
	Part(t, "BagBody", V3(2.3, 1.0, 1.0), CF(0, 0.5, 0), C.ink2, M.Fabric, { shape = "Cylinder" })
	for _, s in ipairs({ -1, 1 }) do
		Part(t, "BagEnd", V3(0.08, 1.02, 1.02), CF(s * 1.13, 0.5, 0), C.gold, M.Fabric, { shape = "Cylinder" })
	end
	Part(t, "BagStrap", V3(1.5, 0.06, 0.2), CF(0, 1.04, 0), C.black, M.Fabric)
end)

-- a caged work lamp on a chain from a truss: chain, shade, wire cage, a warm bulb (a fixture: no light of its own)
local WORKLAMP = K.Template("WorkLamp", function(t)
	Rod(t, "LampChain", V3(0, 0, 0), V3(0, -8.6, 0), 0.08, C.steelLight, M.Metal)
	VCyl(t, "LampShade", 0.7, 1.7, V3(0, -9.3, 0), rgb(46, 70, 52), M.Metal, { shadow = false })
	Ball(t, "LampCage", V3(1.3, 1.0, 1.3), CF(0, -9.7, 0), C.ink, M.Metal, { t = 0.62, shadow = false })
	Ball(t, "LampBulb", 0.6, CF(0, -9.65, 0), rgb(255, 222, 160), M.Neon, { shadow = false })
end)

-- a knee brace from a wall column to the truss with a gusset plate and its bolts (column at the origin, the truss
-- running toward local -Z)
local KNEE = K.Template("KneeBrace", function(t)
	Rod(t, "KneeBrace", V3(0, 23.6, -0.8), V3(0, 27.9, -4.6), 0.34, rgb(58, 60, 66), M.Metal)
	Part(t, "Gusset", V3(0.1, 1.8, 2.0), CF(0, 27.2, -1.55), rgb(66, 68, 74), M.Metal, { shadow = false })
	for _, p in ipairs({ { 26.7, -0.8 }, { 26.7, -1.9 }, { 27.7, -0.8 }, { 27.7, -1.9 } }) do
		Cyl(t, "Bolt", 0.34, 0.16, CF(0, p[1], p[2]), C.steelLight, M.Metal, { shadow = false })
	end
end)

-- a purlin clip where a purlin crosses a truss: an angle cleat and a bolt through
local CLIP = K.Template("PurlinClip", function(t)
	Part(t, "PurlinCleat", V3(0.5, 0.7, 0.7), CF(0, 0, 0), rgb(66, 68, 74), M.Metal, { shadow = false })
	Cyl(t, "Bolt", 0.9, 0.14, CF(0, 0.1, 0), C.steelLight, M.Metal, { shadow = false })
end)

------------------------------------------------------------------------
-- boxing area
------------------------------------------------------------------------
-- rubber mats round the ring's apron (the apron spans x -13.1..13.1, z -63.1..-36.9): under the corner kit
local function ringMats(m)
	local col = rgb(22, 22, 26)
	local strips = {
		{ -14.35, -50, 2.5, 31.2 }, { 14.35, -50, 2.5, 31.2 }, { 0, -64.35, 26.2, 2.5 }, { 0, -35.65, 26.2, 2.5 },
	}
	for _, s in ipairs(strips) do
		local p = Part(m, "RingMat", V3(s[3], 0.04, s[4]), CF(s[1], FLOOR_Y - 0.011, s[2]), col, M.Rubber, { shadow = false })
		K.Texture(p, FACE.Top, "rubberTiles", 5, 5, { Color3 = tintFor(col, 0.55), Transparency = 0.2 })
	end
end

local function boxing1(m)
	-- painted block on both dividers' boxing faces (behind the server's posters and racks)
	local tint = tintFor(DIVIDER)
	wallTexture(m, "DWb", -48, 4.75, 60, 8.5, "blockWall", 4, tint, 0.15)
	wallTexture(m, "DEb", -48, 4.75, 60, 8.5, "blockWall", 4, tint, 0.15)
	-- the fight-bill wall over the painted slogan east of the zone sign, the clippings board by the bottles
	wallPrint(m, "FightBillWall", "N", 30, 14.0, 20, 5, "posterWall", { text = "FIGHT NIGHTS" }, 0.06)
	wallPrint(m, "ClippingsBoard", "N", -39.4, 4.3, 7.4, 3.7, "clippings", { text = "IN THE NEWS", fg = C.ink, bg = C.paper }, 0.1)
	-- stencilled slogan between the painted wall text and the round timer
	wallDecal(m, "Stencil", "N", -30.5, 12.6, 15, 1.85, "stencilOutwork", rgb(236, 232, 222), 0.3)
	ringMats(m)
end

-- the coach's corner by the red corner: a cutman's cart with the bucket, sponge, Vaseline, an ice pack on a towel,
-- an enswell, gauze, and the spit bucket and a spare towel on the lower shelf
local function coachCorner(m)
	local base = CF(-17.3, FLOOR_Y, -61.3) * A(0, RAD(12), 0)
	for _, y in ipairs({ 0.9, 2.6 }) do
		Part(m, "CartShelf", V3(1.7, 0.12, 1.1), base * CF(0, y, 0), C.steelLight, M.Metal)
	end
	for _, x in ipairs({ -0.78, 0.78 }) do
		for _, z in ipairs({ -0.48, 0.48 }) do
			Part(m, "CartLeg", V3(0.1, 2.6, 0.1), base * CF(x, 1.4, z), C.steelLight, M.Metal, { shadow = false })
			Ball(m, "CartWheel", 0.22, base * CF(x, 0.11, z), C.black, M.Rubber, { shadow = false })
		end
	end
	Cyl(m, "CartHandle", 1.5, 0.08, base * CF(0, 3.05, 0.55), C.chrome, M.Metal)
	-- top: water bucket with a sponge, Vaseline, ice pack on a towel, enswell, gauze
	local top = base * CF(0, 2.66, 0)
	VCyl(m, "CornerBucket", 0.75, 0.8, top * CF(-0.42, 0, -0.1), rgb(30, 90, 200), M.Plastic)
	VCyl(m, "BucketWater", 0.04, 0.7, top * CF(-0.42, 0.62, -0.1), rgb(120, 170, 220), M.Glass, { t = 0.3, shadow = false })
	Part(m, "Sponge", V3(0.42, 0.22, 0.3), top * CF(-0.42, 0.72, -0.1) * A(0, RAD(30), 0), rgb(240, 210, 80), M.Fabric, { shadow = false })
	VCyl(m, "Vaseline", 0.22, 0.34, top * CF(0.25, 0, -0.32), rgb(60, 110, 200), M.Plastic, { shadow = false })
	VCyl(m, "VaselineLid", 0.06, 0.36, top * CF(0.25, 0.22, -0.32), C.white, M.Plastic, { shadow = false })
	Part(m, "IceTowel", V3(0.8, 0.05, 0.6), top * CF(0.4, 0.03, 0.2) * A(0, RAD(-15), 0), C.white, M.Fabric, { shadow = false })
	Part(m, "IcePack", V3(0.5, 0.14, 0.38), top * CF(0.4, 0.12, 0.2) * A(0, RAD(10), 0), rgb(90, 180, 240), M.Plastic, { shadow = false })
	Part(m, "Enswell", V3(0.32, 0.08, 0.2), top * CF(0.05, 0.04, 0.35), C.chrome, M.Metal, { shadow = false })
	VCyl(m, "Gauze", 0.16, 0.22, top * CF(0.72, 0, -0.3), C.white, M.Fabric, { shadow = false })
	-- lower shelf: the spit bucket with its funnel, a folded towel
	local low = base * CF(0, 0.96, 0)
	VCyl(m, "SpitBucket", 0.6, 0.7, low * CF(-0.4, 0, 0), C.redDeep, M.Plastic)
	VCyl(m, "SpitFunnel", 0.3, 0.86, low * CF(-0.4, 0.6, 0), C.white, M.Plastic, { shadow = false })
	Part(m, "CartTowel", V3(0.8, 0.2, 0.7), low * CF(0.4, 0.1, 0), C.red, M.Fabric, { shadow = false })
end

-- a speed-bag wall: a backboard with three platforms, bags hanging under each
local function speedBagWall(m, id, along)
	local cf = onWall(id, along, 7.0, 0.0)
	Part(m, "SpeedBackboard", V3(7.6, 4.0, 0.18), cf * CF(0, 0.2, -0.09), C.woodDark, M.Wood)
	for k = -1, 1 do
		local p = cf * CF(k * 2.5, 0, 0)
		Part(m, "SpeedPlatform", V3(2.2, 0.24, 1.9), p * CF(0, 0.9, -1.15), C.wood, M.WoodPlanks)
		Part(m, "SpeedRim", V3(2.24, 0.1, 1.94), p * CF(0, 0.75, -1.15), C.black, M.Metal, { shadow = false })
		Rod(m, "SpeedBrace", (p * CF(-0.8, -0.6, -0.2)).Position, (p * CF(-0.8, 0.7, -1.6)).Position, 0.12, C.steelDark, M.Metal)
		Rod(m, "SpeedBrace", (p * CF(0.8, -0.6, -0.2)).Position, (p * CF(0.8, 0.7, -1.6)).Position, 0.12, C.steelDark, M.Metal)
		Ball(m, "SpeedSwivel", 0.18, p * CF(0, 0.6, -1.3), C.chrome, M.Metal, { shadow = false })
		Ball(m, "SpeedBag", V3(0.52, 0.78, 0.52), p * CF(0, 0.1, -1.3), k == 0 and C.red or C.black, M.Leather, { shadow = false })
	end
end

-- wall-bracket bags on the west divider: an uppercut bag (horizontal, chest high) and a water bag on an arm
local function bracketBags(m)
	local up = onWall("DWb", -76.4, 4.6, 0.0)
	Part(m, "UppercutPlate", V3(3.0, 3.4, 0.15), up * CF(0, 0.6, -0.08), C.steelDark, M.Metal)
	for _, x in ipairs({ -1.2, 1.2 }) do
		Rod(m, "UppercutArm", (up * CF(x, 2.0, -0.15)).Position, (up * CF(x, 1.4, -1.1)).Position, 0.14, C.steelDark, M.Metal)
		Part(m, "UppercutStrap", V3(0.16, 0.9, 0.14), up * CF(x, 0.95, -1.1), C.black, M.Leather, { shadow = false })
	end
	Part(m, "UppercutBag", V3(2.8, 1.5, 1.5), up * CF(0, 0, -1.1), C.redDeep, M.Leather, { shape = "Cylinder" })
	for _, x in ipairs({ -1.4, 1.4 }) do
		Part(m, "UppercutCap", V3(0.1, 1.54, 1.54), up * CF(x, 0, -1.1), C.black, M.Leather, { shape = "Cylinder", shadow = false })
	end
	local w = onWall("DWb", -73.4, 8.3, 0.0)
	Part(m, "BracketPlate", V3(0.9, 1.6, 0.15), w * CF(0, -0.3, -0.08), C.steelDark, M.Metal)
	Rod(m, "BracketArm", (w * CF(0, 0, -0.1)).Position, (w * CF(0, 0, -2.3)).Position, 0.22, C.steelDark, M.Metal)
	Rod(m, "BracketStrut", (w * CF(0, -1.0, -0.1)).Position, (w * CF(0, -0.05, -1.7)).Position, 0.14, C.steelDark, M.Metal)
	Rod(m, "WaterBagChain", (w * CF(0, -0.1, -2.1)).Position, (w * CF(0, -1.7, -2.1)).Position, 0.08, C.steelLight, M.Metal)
	Ball(m, "WaterBag", V3(2.0, 2.4, 2.0), w * CF(0, -2.9, -2.1), rgb(30, 60, 140), M.Plastic, { refl = 0.05 })
	VCyl(m, "WaterBagCap", 0.25, 0.6, w * CF(0, -1.75, -2.1), C.black, M.Plastic, { shadow = false })
end

-- the glove wall: a pegboard with a dozen pairs hanging by their laces in many colours
local GLOVE_COLS = { C.red, C.blue, C.black, C.gold, C.white, rgb(240, 120, 170), C.green, C.redDeep, rgb(120, 60, 160), C.ink2, rgb(255, 140, 40), C.blueDeep }
local function gloveWall(m, cf)
	Part(m, "GlovePegboard", V3(6.6, 4.6, 0.15), cf * CF(0, 0, -0.08), rgb(150, 120, 86), M.Wood)
	local hdr = Part(m, "GloveHeader", V3(6.6, 0.6, 0.06), cf * CF(0, 2.6, -0.1), C.ink, M.SmoothPlastic, { shadow = false })
	K.Sign(hdr, FACE.Front, "GLOVES - PUT THEM BACK", C.gold, C.ink, 30, Enum.Font.GothamBold)
	local i = 0
	for r = 0, 2 do
		for c = 0, 3 do
			i += 1
			local col = GLOVE_COLS[i]
			local peg = cf * CF(-2.4 + c * 1.6, 1.75 - r * 1.5, -0.15)
			Part(m, "GlovePeg", V3(0.1, 0.1, 0.35), peg * CF(0, 0, -0.1), C.chrome, M.Metal, { shadow = false })
			for _, s in ipairs({ -1, 1 }) do
				local g = peg * CF(s * 0.3, -0.62, -0.42) * A(RAD(-8), 0, RAD(s * 8))
				Ball(m, "Glove", V3(0.55, 0.72, 0.62), g, col, M.Leather, { shadow = false })
				Part(m, "GloveCuff", V3(0.44, 0.26, 0.48), g * CF(0, 0.42, 0), col == C.white and C.red or C.white, M.Leather, { shadow = false })
			end
		end
	end
end

-- hand wraps drying on a line between two hooks
local function wrapLine(m, x1, x2, y)
	local a, b = onWall("N", x1, y, 0.35), onWall("N", x2, y, 0.35)
	Part(m, "LineHook", V3(0.14, 0.3, 0.4), onWall("N", x1, y, 0.2), C.chrome, M.Metal, { shadow = false })
	Part(m, "LineHook", V3(0.14, 0.3, 0.4), onWall("N", x2, y, 0.2), C.chrome, M.Metal, { shadow = false })
	Rod(m, "DryLine", a.Position, b.Position - V3(0, 0.15, 0), 0.05, C.white, M.Fabric)
	local cols = { C.red, C.black, C.white, C.blue, rgb(240, 120, 170), C.yellow }
	for k = 1, 6 do
		local t = k / 7
		local p = a.Position:Lerp(b.Position, t) - V3(0, 0.15 * t, 0)
		local len = 1.6 + (k % 3) * 0.35
		local cf = CFrame.lookAt(p, p + Vector3.new(0, 0, 1)) * A(0, 0, RAD((k % 2 == 0) and 4 or -5))
		Part(m, "HandWrap", V3(0.26, len, 0.03), cf * CF(0, -len / 2, 0), cols[k], M.Fabric, { shadow = false })
	end
end

local function boxing2(m)
	coachCorner(m)
	speedBagWall(m, "DEb", -74.2)
	bracketBags(m)
	gloveWall(m, onWall("N", 39.9, 5.9, 0.0))
	wrapLine(m, 15.3, 22.6, 7.7)
	-- worn paths: round the ring mats, along the station row, under the bag members' feet
	for i, p in ipairs({ { -16, -66 }, { 16, -66 }, { -16, -34 }, { 16, -34 }, { -16, -50 }, { 16, -50 }, { 0, -33.5 }, { 0, -66.5 } }) do
		floorPatch(m, "floorWear", p[1], p[2], 5, 6, i * 0.7, nil, 0.25)
	end
	for i, x in ipairs({ -34, -18, -2, 14, 32 }) do
		floorPatch(m, "floorWear", x, -9.6, 6, 5, i * 1.1, nil, 0.15)
	end
	floorPatch(m, "floorWear", -30, -26.4, 16, 5, 0.1, nil, 0.2)
	floorPatch(m, "puddle", 20.6, -10.6, 2.2, 1.8, 0.6, nil, 0.15)
	-- chipped paint low on the dividers and the north wall
	for _, c in ipairs({ { "DWb", -20, 1.8 }, { "DWb", -56, 1.4 }, { "DEb", -20.5, 1.6 }, { "DEb", -64, 1.3 }, { "N", -6, 2.2 }, { "N", 44, 9.0 } }) do
		wallDecal(m, "PaintChips", c[1], c[2], c[3], 3.2, 2.2, "paintChips", rgb(196, 190, 180), 0.2, 0.03)
	end
end

------------------------------------------------------------------------
-- weight room
------------------------------------------------------------------------
-- a medicine-ball wall rack: two shelves of three balls
local function medBallRack(m, id, along)
	local cf = onWall(id, along, 0.5, 0)
	local cols = { rgb(40, 140, 80), C.red, C.gold, C.blue, C.black, rgb(120, 60, 160) }
	for _, x in ipairs({ -2.6, 2.6 }) do
		Part(m, "BallRackSide", V3(0.2, 5.2, 1.4), cf * CF(x, 2.6, -0.7), C.black, M.Metal)
	end
	for r = 0, 1 do
		Part(m, "BallRackShelf", V3(5.2, 0.15, 1.3), cf * CF(0, 0.5 + r * 2.4, -0.7), C.steelDark, M.Metal)
		for c = 0, 2 do
			local d = 1.4 - r * 0.2
			Ball(m, "MedBall2", d, cf * CF(-1.7 + c * 1.7, 0.58 + r * 2.4 + d / 2, -0.7), cols[r * 3 + c + 1], M.Rubber)
		end
	end
end

-- a free-standing dip station (two parallel bars, posts, feet) facing local -Z
local function dipStation(m, cf)
	for _, x in ipairs({ -0.95, 0.95 }) do
		Part(m, "DipFoot", V3(0.4, 0.2, 3.2), cf * CF(x, 0.1, 0), C.black, M.Metal)
		for _, z in ipairs({ -1.2, 1.2 }) do
			Part(m, "DipPost", V3(0.24, 4.2, 0.24), cf * CF(x, 2.2, z), C.black, M.Metal)
		end
		Part(m, "DipBar", V3(0.24, 0.24, 3.0), cf * CF(x, 4.35, 0), C.steelLight, M.Metal)
		Part(m, "DipGrip", V3(0.3, 0.3, 1.2), cf * CF(x, 4.35, -0.6), C.rubber, M.Rubber, { shadow = false })
	end
	Part(m, "DipBrace", V3(2.1, 0.2, 0.2), cf * CF(0, 0.6, 1.2), C.black, M.Metal)
end

-- a climbing rope from a truss: clamp, rope, knot, whipped end, a crash mat under it
local function ropeClimb(m, x, z)
	Part(m, "RopeClamp", V3(1.2, 0.5, 0.8), CF(x, TRUSS_Y - 0.15, z), C.steelDark, M.Metal)
	VCyl(m, "ClimbRopeEye", 0.6, 0.6, V3(x, TRUSS_Y - 1.0, z), C.chrome, M.Metal, { shadow = false })
	Rod(m, "ClimbRope", V3(x, TRUSS_Y - 0.9, z), V3(x + 0.15, FLOOR_Y + 1.4, z + 0.1), 0.45, rgb(196, 160, 104), M.Fabric)
	Ball(m, "ClimbKnot", 0.75, CF(x + 0.14, 3.4, z + 0.09), rgb(176, 140, 90), M.Fabric)
	Rod(m, "ClimbTail", V3(x + 0.15, FLOOR_Y + 1.4, z + 0.1), V3(x + 1.1, FLOOR_Y + 0.25, z + 0.6), 0.45, rgb(196, 160, 104), M.Fabric)
	Part(m, "CrashMat", V3(4.4, 0.1, 4.4), CF(x, FLOOR_Y + 0.05, z), rgb(30, 60, 140), M.Fabric, { shadow = false })
end

-- the training whiteboard: the board (uploaded schedule), a marker tray, markers and an eraser
local function trainingBoard(m, id, along, y)
	wallPrint(m, "Whiteboard", id, along, y, 9.2, 4.6, "whiteboard", { text = "TRAINING\nSCHEDULE", fg = C.ink, bg = C.white }, 0.06)
	local tray = onWall(id, along, y - 2.45, 0.0)
	Part(m, "MarkerTray", V3(8.0, 0.14, 0.45), tray * CF(0, 0, -0.3), C.steelLight, M.Metal, { shadow = false })
	local cols = { C.red, C.blue, C.black }
	for k = 1, 3 do
		Part(m, "Marker", V3(0.6, 0.12, 0.12), tray * CF(-2.4 + k * 0.6, 0.13, -0.32) * A(0, RAD(k * 6), 0), cols[k], M.Plastic, { shadow = false })
	end
	Part(m, "Eraser", V3(0.8, 0.22, 0.32), tray * CF(2.4, 0.18, -0.3), C.ink2, M.Fabric, { shadow = false })
end

local function weights1(m)
	local tint = tintFor(DIVIDER)
	wallTexture(m, "DWw", -48, 4.75, 60, 8.5, "blockWall", 4, tint, 0.15)
	wallTexture(m, "DZn", -88, 4.75, 40, 8.5, "blockWall", 4, tint, 0.15)
	wallDecal(m, "Stencil", "DWw", -53, 7.3, 15, 1.9, "stencilShortcuts", rgb(240, 236, 226), 0.12)
	trainingBoard(m, "W", 8, 6.3)
end

local function weights2(m)
	-- kettlebell row along the divider, light to heavy
	for k = 0, 7 do
		local t = KB[math.min(4, math.floor(k / 2) + 1)]
		K.Place(t, m, CF(-52.4, FLOOR_Y, -61.5 + k * 2.1) * A(0, RAD(90 + (k % 3) * 9), 0))
	end
	medBallRack(m, "DWw", -34.2)
	dipStation(m, CF(-104.6, FLOOR_Y, 12) * A(0, RAD(90), 0))
	ropeClimb(m, -60, -68)
	K.Place(PLYO, m, CF(-99.6, FLOOR_Y, 15.4) * A(0, RAD(20), 0))
	floorPatch(m, "puddle", -101.6, -1.2, 2.6, 2.2, 0.4, nil, 0.1)
	for i, p in ipairs({ { -92, -24 }, { -72, -24.3 }, { -92, -52 }, { -72, -51.5 }, { -58, -60 }, { -56, -40 } }) do
		floorPatch(m, "floorWear", p[1], p[2], 5, 5, i * 0.9, nil, 0.3)
	end
	for _, c in ipairs({ { "DWw", -22, 1.6 }, { "DWw", -66, 1.2 }, { "W", 16, 2.0 }, { "DZn", -100, 1.5 } }) do
		wallDecal(m, "PaintChips", c[1], c[2], c[3], 3.2, 2.2, "paintChips", rgb(190, 186, 178), 0.25, 0.03)
	end
end

------------------------------------------------------------------------
-- cardio room
------------------------------------------------------------------------
-- the Hall of Champions: the photo wall (uploaded print) in a dark wood frame, three picture lamps over it
local function hallOfChampions(m, id, along, y)
	local w, h = 14, 7
	Part(m, "HallFrame", V3(w + 0.7, h + 0.7, 0.12), onWall(id, along, y, 0.06), C.woodDark, M.Wood, { shadow = false })
	wallPrint(m, "HallOfChampions", id, along, y, w, h, "hallChampions", { text = "HALL OF CHAMPIONS" }, 0.12)
	local top = onWall(id, along, y + h / 2 + 0.75, 0.0)
	Part(m, "PictureLightBar", V3(w - 1, 0.14, 0.14), top * CF(0, 0, -0.5), C.brass, M.Metal, { shadow = false })
	for k = -1, 1 do
		Part(m, "PictureLightArm", V3(0.1, 0.1, 0.6), top * CF(k * 4.6, 0, -0.25), C.brass, M.Metal, { shadow = false })
		Part(m, "PictureLightHood", V3(1.6, 0.3, 0.4), top * CF(k * 4.6, -0.1, -0.6) * A(RAD(-25), 0, 0), C.brass, M.Metal, { shadow = false })
		Part(m, "PictureLightGlow", V3(1.4, 0.06, 0.26), top * CF(k * 4.6, -0.26, -0.62) * A(RAD(-25), 0, 0), rgb(255, 232, 190), M.Neon, { shadow = false })
	end
end

-- the weigh-in corner on the divider: a step-and-repeat backdrop, the header board on the divider cap, a height chart,
-- a platform scale with its readout, a table with the clipboard and a tape measure, a folding chair
local function weighIn(m, along)
	local w, h = 10, 8.3
	local bd = Part(m, "WeighInBackdrop", V3(w, h, 0.08), onWall("DZn", along, 0.6 + h / 2, 0.08), C.ink, M.Fabric, { shadow = false })
	if not K.Texture(bd, FACE.Front, "backdropWCB", 3.4, 3.4) then
		K.Sign(bd, FACE.Front, "WCB", C.gold, C.ink, 12)
	end
	local hdrCF = onWall("DZn", along, 10.65, -1.0)
	local hdr = Part(m, "WeighInHeader", V3(w, 1.9, 0.25), hdrCF, C.ink, M.SmoothPlastic, { shadow = false })
	local sg = K.Gui(hdr, FACE.Front, 30, 0.6)
	K.Frame(sg, { BackgroundColor3 = C.ink })
	K.Frame(sg, { BackgroundColor3 = C.gold, Size = UDim2.fromScale(1, 0.06), Position = UDim2.fromScale(0, 0.94) })
	K.Emblem(sg, 0.02, 0.08, 0.16, 0.84)
	K.Text(sg, "OFFICIAL WEIGH-IN", { TextColor3 = C.gold, Size = UDim2.fromScale(0.78, 0.7), Position = UDim2.fromScale(0.2, 0.15) })
	-- height chart down the backdrop's left edge
	local hc = Part(m, "HeightChart", V3(0.9, 7.2, 0.04), onWall("DZn", along - w / 2 + 0.7, 4.4, 0.15), C.white, M.SmoothPlastic, { shadow = false })
	local hg = K.Gui(hc, FACE.Front, 20, 1)
	K.Frame(hg, { BackgroundColor3 = C.white })
	for k = 0, 14 do
		K.Frame(hg, { BackgroundColor3 = C.ink, Size = UDim2.fromScale(k % 2 == 0 and 0.6 or 0.35, 0.008), Position = UDim2.fromScale(0, k / 14) })
	end
	-- the scale
	local sc = onWall("DZn", along + 0.6, FLOOR_Y, 2.8)
	Part(m, "ScaleBase", V3(2.3, 0.3, 2.3), sc * CF(0, 0.15, 0), C.steelDark, M.Metal)
	Part(m, "ScaleMat", V3(2.0, 0.05, 2.0), sc * CF(0, 0.32, 0), C.black, M.Rubber, { shadow = false })
	Part(m, "ScaleColumn", V3(0.3, 4.0, 0.3), sc * CF(0, 2.3, 1.05), C.steelLight, M.Metal)
	local head = Part(m, "ScaleHead", V3(1.1, 0.7, 0.4), sc * CF(0, 4.5, 1.0), C.ink2, M.Metal)
	local hgui = K.Gui(head, FACE.Front, 60, 0)
	K.Frame(hgui, { BackgroundColor3 = rgb(16, 30, 20), Size = UDim2.fromScale(0.86, 0.6), Position = UDim2.fromScale(0.07, 0.2) })
	K.Text(hgui, "160.4", { TextColor3 = rgb(120, 255, 140), Font = Enum.Font.Code, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25) })
	-- the officials' table and chair to the left
	local tb = onWall("DZn", along - 5.6, FLOOR_Y, 2.6)
	Part(m, "WeighTable", V3(3.2, 0.15, 1.6), tb * CF(0, 2.9, 0), C.wood, M.Wood)
	for _, x in ipairs({ -1.45, 1.45 }) do
		Part(m, "WeighTableLeg", V3(0.15, 2.85, 1.3), tb * CF(x, 1.42, 0), C.steelDark, M.Metal, { shadow = false })
	end
	local clip = Part(m, "Clipboard", V3(0.85, 0.05, 1.15), tb * CF(-0.5, 3.0, 0) * A(0, RAD(10), 0), C.wood, M.Wood, { shadow = false })
	Part(m, "ClipSheet", V3(0.75, 0.02, 0.95), clip.CFrame * CF(0, 0.035, 0.05), C.white, M.SmoothPlastic, { shadow = false })
	Part(m, "ClipClamp", V3(0.4, 0.06, 0.12), clip.CFrame * CF(0, 0.05, 0.5), C.chrome, M.Metal, { shadow = false })
	VCyl(m, "TapeMeasure", 0.18, 0.5, tb * CF(0.8, 2.98, 0.2), C.yellow, M.Plastic, { shadow = false })
	local ch = tb * CF(0.2, 0, -1.6) * A(0, RAD(170), 0)
	Part(m, "ChairSeat", V3(1.4, 0.12, 1.3), ch * CF(0, 1.75, 0), C.steelDark, M.Metal)
	Part(m, "ChairBack", V3(1.4, 1.0, 0.1), ch * CF(0, 2.6, 0.65) * A(RAD(-8), 0, 0), C.steelDark, M.Metal)
	for _, x in ipairs({ -0.6, 0.6 }) do
		Rod(m, "ChairLeg", (ch * CF(x, 0, -0.6)).Position, (ch * CF(x, 1.7, 0.5)).Position, 0.08, C.steelLight, M.Metal)
		Rod(m, "ChairLeg", (ch * CF(x, 0, 0.6)).Position, (ch * CF(x, 1.7, -0.5)).Position, 0.08, C.steelLight, M.Metal)
	end
end

-- a cold drinks machine against a wall (body, lit glass front with bottle rows, header, slot, coin panel)
local function drinksMachine(m, id, along)
	local cf = onWall(id, along, FLOOR_Y, 1.3)
	Part(m, "DrinksBody", V3(3.6, 7.2, 2.6), cf * CF(0, 3.6, 0), C.redDeep, M.SmoothPlastic)
	local glass = Part(m, "DrinksGlass", V3(2.5, 4.6, 0.05), cf * CF(-0.45, 3.9, -1.32), rgb(30, 34, 44), M.SmoothPlastic, { shadow = false })
	local sg = K.Gui(glass, FACE.Front, 24, 0)
	K.Frame(sg, { BackgroundColor3 = rgb(200, 220, 240) })
	local cols = { C.blue, C.gold, C.green, C.red, rgb(250, 130, 30) }
	for r = 0, 4 do
		K.Frame(sg, { BackgroundColor3 = rgb(150, 160, 170), Size = UDim2.fromScale(1, 0.02), Position = UDim2.fromScale(0, 0.19 + r * 0.2) })
		for c = 0, 5 do
			K.Frame(sg, { BackgroundColor3 = cols[(r + c) % 5 + 1], Size = UDim2.fromScale(0.1, 0.13), Position = UDim2.fromScale(0.05 + c * 0.155, 0.055 + r * 0.2) })
		end
	end
	local hdr = Part(m, "DrinksHeader", V3(3.4, 1.0, 0.05), cf * CF(0, 6.7, -1.32), C.ink, M.SmoothPlastic, { shadow = false })
	K.Sign(hdr, FACE.Front, "COLD DRINKS", C.white, C.ink, 30, Enum.Font.GothamBlack, 0)
	Part(m, "DrinksPanel", V3(0.7, 1.6, 0.06), cf * CF(1.25, 4.6, -1.32), C.steelLight, M.Metal, { shadow = false })
	Part(m, "DrinksSlot", V3(2.4, 0.6, 0.06), cf * CF(-0.45, 0.9, -1.32), C.black, M.SmoothPlastic, { shadow = false })
end

local function cardio1(m)
	local tint = tintFor(DIVIDER)
	wallTexture(m, "DEc", -48, 4.75, 60, 8.5, "blockWall", 4, tint, 0.15)
	wallTexture(m, "DZn", 88, 4.75, 40, 8.5, "blockWall", 4, tint, 0.15)
	wallDecal(m, "Stencil", "DEc", -51, 7.3, 14, 1.75, "stencilNoDays", rgb(240, 236, 226), 0.12)
	hallOfChampions(m, "E", -3.5, 6.3)
end

local function cardio2(m)
	weighIn(m, 101)
	drinksMachine(m, "E", -18.2)
	K.Place(PLYO, m, CF(55.6, FLOOR_Y, -42) * A(0, RAD(-15), 0))
	floorPatch(m, "puddle", 101.8, 1.8, 2.8, 2.2, 1.2, nil, 0.1)
	for i, p in ipairs({ { 70, -51.6 }, { 90, -51.2 }, { 70, -24.4 }, { 92, -26 }, { 80, 8.5 } }) do
		floorPatch(m, "floorWear", p[1], p[2], 5, 6, i * 0.8, nil, 0.3)
	end
	for _, c in ipairs({ { "DEc", -22, 1.5 }, { "DEc", -70, 1.3 }, { "DZn", 74, 1.6 } }) do
		wallDecal(m, "PaintChips", c[1], c[2], c[3], 3.2, 2.2, "paintChips", rgb(190, 186, 178), 0.25, 0.03)
	end
end

------------------------------------------------------------------------
-- lobby and desk, locker room
------------------------------------------------------------------------
local function lobby2(m)
	-- first-aid kit and an extinguisher on the wall behind the desk
	local fa = onWall("S", 32.6, 5.2, 0.0)
	local box = Part(m, "FirstAidKit", V3(1.7, 1.4, 0.5), fa * CF(0, 0, -0.25), C.white, M.Plastic)
	local sg = K.Gui(box, FACE.Front, 40, 1)
	K.Frame(sg, { BackgroundColor3 = C.white })
	K.Frame(sg, { BackgroundColor3 = rgb(30, 150, 70), Size = UDim2.fromScale(0.16, 0.5), Position = UDim2.fromScale(0.42, 0.12) })
	K.Frame(sg, { BackgroundColor3 = rgb(30, 150, 70), Size = UDim2.fromScale(0.4, 0.2), Position = UDim2.fromScale(0.3, 0.27) })
	K.Text(sg, "FIRST AID", { TextColor3 = rgb(30, 150, 70), Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.7) })
	Part(m, "FirstAidLatch", V3(0.3, 0.14, 0.08), fa * CF(0, -0.55, -0.52), C.steelDark, M.Metal, { shadow = false })
	local ex = onWall("S", 35.7, LOBBY_Y, 0.0)
	Part(m, "ExtBracket", V3(0.6, 0.3, 0.3), ex * CF(0, 3.1, -0.15), C.steelDark, M.Metal, { shadow = false })
	VCyl(m, "Extinguisher2", 2.2, 0.6, ex * CF(0, 1.2, -0.42), rgb(200, 20, 24), M.SmoothPlastic)
	VCyl(m, "ExtValve", 0.35, 0.3, ex * CF(0, 3.4, -0.42), C.ink, M.Metal, { shadow = false })
	Rod(m, "ExtHose", (ex * CF(0.15, 3.55, -0.42)).Position, (ex * CF(0.32, 2.0, -0.7)).Position, 0.1, C.ink, M.Rubber)
	local sign = Part(m, "ExtSign", V3(1.0, 1.0, 0.04), ex * CF(0, 4.6, -0.03), rgb(200, 20, 24), M.SmoothPlastic, { shadow = false })
	K.Sign(sign, FACE.Front, "FIRE", C.white, rgb(200, 20, 24), 40)
	-- a radio on the desk return, a towel bin by it
	local r = CF(35.0, 4.3, 65.0) * A(0, RAD(-100), 0)
	Part(m, "RadioBody", V3(1.6, 0.8, 0.5), r * CF(0, 0.4, 0), C.ink2, M.Plastic)
	for _, x in ipairs({ -0.45, 0.45 }) do
		Part(m, "RadioSpeaker", V3(0.04, 0.55, 0.55), r * CF(x, 0.4, -0.26) * A(0, math.pi / 2, 0), C.steelDark, M.Metal, { shape = "Cylinder", shadow = false })
	end
	Part(m, "RadioHandle", V3(1.2, 0.1, 0.12), r * CF(0, 0.92, 0), C.chrome, M.Metal, { shadow = false })
	Rod(m, "RadioAntenna", (r * CF(0.65, 0.85, 0)).Position, (r * CF(1.1, 2.0, 0.2)).Position, 0.04, C.chrome, M.Metal)
	VCyl(m, "TowelBin", 2.2, 1.6, V3(38.6, LOBBY_Y, 65.6), rgb(50, 60, 80), M.Plastic)
	Ball(m, "BinTowels", V3(1.4, 0.7, 1.4), CF(38.6, LOBBY_Y + 2.2, 65.6), C.white, M.Fabric, { shadow = false })
	-- a pile of bags by the lounge, a puddle by the water cooler, the worn way in from the door
	K.Place(DUFFEL, m, CF(-47.8, LOBBY_Y, 40.2) * A(0, RAD(80), 0))
	K.Place(DUFFEL, m, CF(-47.0, LOBBY_Y, 38.0) * A(0, RAD(110), 0))
	K.Place(DUFFEL, m, CF(-47.4, LOBBY_Y + 0.95, 39.1) * A(0, RAD(95), 0))
	floorPatch(m, "puddle", 16.6, 37.4, 2.4, 2.0, 0.3, LOBBY_Y, 0.15)
	for i, p in ipairs({ { 0, 74 }, { 0, 68 }, { 6, 66 }, { 14, 66 }, { 22, 65 }, { 0, 46 }, { 0, 38 }, { 0, 24 } }) do
		floorPatch(m, "floorWear", p[1], p[2], 6, 6, i * 0.7, LOBBY_Y, 0.35)
	end
end

-- the locker-room TV on a ceiling pole from the truss, showing the fight broadcast (four frames, Ambience TVLoop)
local function lockerTV(m, x, z)
	Rod(m, "TVPole", V3(x, TRUSS_Y, z), V3(x, 15.3, z), 0.24, C.steelDark, M.Metal)
	Part(m, "TVMount", V3(1.4, 0.5, 0.3), CF(x, 15.1, z), C.steelDark, M.Metal, { shadow = false })
	Part(m, "TVBody", V3(6.4, 3.8, 0.35), CF(x, 13.2, z + 0.2), C.black, M.SmoothPlastic)
	local screen = Part(m, "TVScreen2", V3(6.0, 3.4, 0.04), CF(x, 13.2, z + 0.4), rgb(10, 10, 14), M.SmoothPlastic, { shadow = false })
	local sg = K.Gui(screen, FACE.Back, 40, 0)
	local id = K.Asset("tvFight")
	if id then
		local im = Instance.new("ImageLabel")
		im.Name = "TVImage"
		im.BackgroundColor3 = C.black
		im.BorderSizePixel = 0
		im.Size = UDim2.fromScale(1, 1)
		im.Image = id
		im.ImageRectSize = Vector2.new(512, 256)
		im.ImageRectOffset = Vector2.new(0, 0)
		im.ScaleType = Enum.ScaleType.Stretch
		im:SetAttribute("Cols", 2)
		im:SetAttribute("Rows", 2)
		im:SetAttribute("FrameW", 512)
		im:SetAttribute("FrameH", 256)
		im:SetAttribute("Period", 2.4)
		im.Parent = sg
		pcall(function()
			im:AddTag("TVLoop")
		end)
	else
		K.Frame(sg, { BackgroundColor3 = C.ink })
		K.Text(sg, "FIGHT NIGHT LIVE", { TextColor3 = C.gold, Size = UDim2.fromScale(0.8, 0.3), Position = UDim2.fromScale(0.1, 0.35) })
	end
end

local function services2(m)
	lockerTV(m, -60, 26.4)
	-- a boombox on the lockers
	local bb = CF(-73.8, 8.0, 25.0)
	Part(m, "BoomboxBody", V3(2.0, 0.95, 0.65), bb * CF(0, 0.48, 0), rgb(40, 40, 46), M.Plastic)
	for _, x in ipairs({ -0.6, 0.6 }) do
		Part(m, "BoomboxSpeaker", V3(0.05, 0.7, 0.7), bb * CF(x, 0.48, 0.33) * A(0, math.pi / 2, 0), C.black, M.Fabric, { shape = "Cylinder", shadow = false })
	end
	Part(m, "BoomboxDeck", V3(0.45, 0.4, 0.04), bb * CF(0, 0.5, 0.34), C.steelLight, M.Metal, { shadow = false })
	Part(m, "BoomboxHandle", V3(1.6, 0.1, 0.12), bb * CF(0, 1.1, 0), C.chrome, M.Metal, { shadow = false })
	-- jackets on hooks on the end locker's side
	for i, z in ipairs({ 24.55, 25.45 }) do
		Part(m, "LockerHook", V3(0.35, 0.12, 0.12), CF(-56.6, 6.7, z), C.chrome, M.Metal, { shadow = false })
		local col = i == 1 and C.ink2 or C.redDeep
		Part(m, i == 1 and "Jacket" or "Hoodie", V3(0.45, 2.6, 0.85), CF(-56.3, 5.3, z) * A(0, 0, RAD(i == 1 and 3 or -2)), col, M.Fabric)
		if i == 2 then
			Ball(m, "HoodieHood", V3(0.4, 0.6, 0.7), CF(-56.3, 6.7, z), col, M.Fabric, { shadow = false })
		end
	end
	-- laundry bin, mop and bucket by the towel cart; a pile of bags west of the lockers
	VCyl(m, "LaundryBin", 2.4, 1.7, V3(-53.6, FLOOR_Y, 24.6), C.steelLight, M.Metal, { t = 0.35 })
	for k = 0, 2 do
		Ball(m, "LaundryTowel", V3(1.0, 0.6, 0.9), CF(-53.6 + (k - 1) * 0.35, FLOOR_Y + 2.3 + (k % 2) * 0.2, 24.6 + (k - 1) * 0.25), k == 1 and C.red or C.white, M.Fabric, { shadow = false })
	end
	local mb = V3(-53.8, FLOOR_Y, 27.3)
	VCyl(m, "MopBucket", 1.2, 1.5, mb, C.yellow, M.Plastic)
	Part(m, "MopWringer", V3(0.9, 0.5, 0.7), CF(mb + V3(0, 1.4, 0)), rgb(40, 40, 46), M.Plastic, { shadow = false })
	Rod(m, "MopHandle", mb + V3(0.1, 0.6, 0), mb + V3(-0.9, 5.6, 0.6), 0.12, rgb(60, 110, 200), M.Plastic)
	Ball(m, "MopHead", V3(0.9, 0.5, 0.9), CF(mb + V3(0.1, 0.8, 0)), rgb(200, 196, 180), M.Fabric, { shadow = false })
	K.Place(DUFFEL, m, CF(-83.4, FLOOR_Y, 24.6) * A(0, RAD(10), 0))
	K.Place(DUFFEL, m, CF(-83.0, FLOOR_Y, 26.4) * A(0, RAD(-15), 0))
	K.Place(DUFFEL, m, CF(-83.2, FLOOR_Y + 0.95, 25.5) * A(0, RAD(5), 0))
	floorPatch(m, "puddle", -105.4, 55, 2.8, 3.4, 0.2, nil, 0.05)
	floorPatch(m, "puddle", -103.2, 51.6, 1.6, 1.4, 1.0, nil, 0.2)
end

------------------------------------------------------------------------
-- ceiling (tier 3)
------------------------------------------------------------------------
local function ceiling3(m)
	for _, p in ipairs({ { -30, -24 }, { -30, -2 }, { 30, -24 }, { 30, -2 }, { -60, -46 }, { -90, -12 }, { 60, -46 }, { 90, -12 } }) do
		K.Place(WORKLAMP, m, CF(p[1], TRUSS_Y, p[2]))
	end
	for _, x in ipairs({ -90, -60, 60, 90 }) do
		-- (the template's brace runs toward its -Z: into the hall from the north and south wall columns)
		K.Place(KNEE, m, CF(x, 0, -78.4) * A(0, math.pi, 0))
		K.Place(KNEE, m, CF(x, 0, 78.4))
	end
	for _, x in ipairs({ -90, -60, -30, 0, 30, 60, 90 }) do
		for _, z in ipairs({ -60, -20, 20, 60 }) do
			K.Place(CLIP, m, CF(x + 0.75, 29.55, z))
		end
	end
	-- the north round timer's cable up to the wall pipes
	local a = onWall("N", -26.4, 16.6, 0.25).Position
	local b = onWall("N", -26.4, 26.6, 0.25).Position
	Rod(m, "TimerCable", a, b, 0.1, C.ink, M.Rubber)
	for _, y in ipairs({ 19, 22, 25 }) do
		Part(m, "CableClip", V3(0.3, 0.14, 0.3), onWall("N", -26.4, y, 0.15), C.steelLight, M.Metal, { shadow = false })
	end
end

------------------------------------------------------------------------
-- registration (GymDetail.Register calls this with itself)
------------------------------------------------------------------------
function GymDetail2.Register(streamer, GymDetail)
	onWall = GymDetail.OnWall
	local W = GymDetail.WALLS
	-- the dividers' other faces
	W.DWw = W.DWw or { axis = "Z", plane = -51, n = V3(-1, 0, 0) } -- the x = -50 divider, weight-room side
	W.DZn = W.DZn or { axis = "X", plane = 19, n = V3(0, 0, -1) } -- the z = 20 dividers, north face
	streamer:Add("Gym2Boxing", V3(0, 6, -48), 50, { boxing1, boxing2 })
	streamer:Add("Gym2Weights", V3(-79, 6, -30), 52, { weights1, weights2 })
	streamer:Add("Gym2Cardio", V3(79, 6, -30), 52, { cardio1, cardio2 })
	streamer:Add("Gym2Lobby", V3(0, 6, 55), 48, { nil, lobby2 })
	streamer:Add("Gym2Services", V3(-79, 8, 40), 40, { nil, services2 })
	streamer:Add("Gym2Ceiling", V3(0, 26, 0), 110, { nil, nil, ceiling3 })
end

return GymDetail2
