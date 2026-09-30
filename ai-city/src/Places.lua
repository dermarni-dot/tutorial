-- Places (ModuleScript) — ServerScriptService.Modules.Places
-- What stands on each city block: the plaza, town hall, bank, towers, shops,
-- three schools, parks with playgrounds and ponds, the sports field, homes...
-- Every builder registers its places and the spots where people do things
-- through the `ctx` object that MapBuilder passes in.

local MapKit = require(script.Parent:WaitForChild("MapKit"))
local Buildings = require(script.Parent:WaitForChild("Buildings"))
local Interiors = require(script.Parent:WaitForChild("Interiors"))
local Streets = require(script.Parent:WaitForChild("Streets"))

local Places = {}

local part, deco, wedge, column, rgb = MapKit.part, MapKit.deco, MapKit.wedge, MapKit.column, MapKit.rgb
local WHITE, BLACK, GOLD, WOOD, STONE = MapKit.WHITE, MapKit.BLACK, MapKit.GOLD, MapKit.WOOD, MapKit.STONE
local HALF, SIDEWALK, FLOOR_H = MapKit.HALF, MapKit.SIDEWALK, MapKit.FLOOR_H

local function flag(parent, pos, color, height)
	height = height or 18
	deco(parent, "FlagPole", Vector3.new(0.4, height, 0.4), CFrame.new(pos + Vector3.new(0, height / 2, 0)), rgb(220, 220, 225), Enum.Material.Metal)
	MapKit.ball(parent, "FlagTop", 0.8, CFrame.new(pos + Vector3.new(0, height + 0.3, 0)), GOLD, Enum.Material.Metal)
	deco(parent, "Flag", Vector3.new(0.1, 3, 5), CFrame.new(pos + Vector3.new(0, height - 1.8, 2.6)), color, Enum.Material.Fabric)
end
Places.flag = flag

local function outSpot(cf, action, role)
	return { CFrame = cf, Action = action, Role = role or "visit", Floor = 1 }
end

-- ground-level CFrame facing a point
local function facing(pos, target)
	return CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
end

--------------------------------------------------------------------------------
-- Outdoor bits used in several places
--------------------------------------------------------------------------------
local function playground(ctx, parent, center, rotY, spots, big)
	local cf = CFrame.new(center) * CFrame.Angles(0, rotY or 0, 0)
	part(parent, "PlaygroundSand", Vector3.new(26, 0.2, 22), cf * CFrame.new(0, 0.1, 0), rgb(232, 200, 140), Enum.Material.Sand)
	-- swing set with two swings
	local red = rgb(220, 70, 60)
	deco(parent, "SwingBar", Vector3.new(12, 0.6, 0.6), cf * CFrame.new(-5, 9, 5), red, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, lz in ipairs({ -1.5, 1.5 }) do
			deco(parent, "SwingLeg", Vector3.new(0.5, 9.4, 0.5), cf * CFrame.new(-5 + sx * 6, 4.6, 5 + lz) * CFrame.Angles(math.rad(lz * 5), 0, 0), red, Enum.Material.Metal)
		end
		local seatPos = cf * CFrame.new(-5 + sx * 2.6, 2.4, 5)
		-- a real seat (players can sit on it too) hanging from two chains; every
		-- client swings the seat and chains with whoever is sitting on it
		local swing = Instance.new("Model")
		swing.Name = "Swing"
		swing.Parent = parent
		local seat = MapKit.seat(swing, "SwingSeat", Vector3.new(2, 0.3, 1.2), seatPos, rgb(40, 40, 46), Enum.Material.SmoothPlastic)
		for _, cx in ipairs({ -0.9, 0.9 }) do
			deco(swing, "SwingChain", Vector3.new(0.1, 6.4, 0.1), seatPos * CFrame.new(cx, 3.3, 0), rgb(160, 160, 166), Enum.Material.Metal)
		end
		local pivot = (seatPos * CFrame.new(0, 6.6, 0)).Position
		swing:SetAttribute("Pivot", pivot)
		swing:SetAttribute("Axis", seatPos.RightVector)
		MapKit.tag(swing, "Swing")
		local s = outSpot(seatPos * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, math.pi, 0), "swing", "kid")
		s.SwingPivot = pivot
		s.SwingAxis = seatPos.RightVector
		s.Seat = seat
		table.insert(spots, s)
	end
	-- slide tower
	local blue = rgb(70, 150, 230)
	deco(parent, "SlideTower", Vector3.new(5, 0.6, 5), cf * CFrame.new(6, 6, -4), WOOD, Enum.Material.WoodPlanks)
	for _, px in ipairs({ -2.3, 2.3 }) do
		for _, pz in ipairs({ -2.3, 2.3 }) do
			deco(parent, "TowerPost", Vector3.new(0.5, 9, 0.5), cf * CFrame.new(6 + px, 4.5, -4 + pz), blue, Enum.Material.Metal)
		end
	end
	wedge(parent, "TowerRoof", Vector3.new(5.6, 2.4, 2.8), cf * CFrame.new(6, 10.2, -5.4), rgb(250, 200, 60))
	wedge(parent, "TowerRoof", Vector3.new(5.6, 2.4, 2.8), cf * CFrame.new(6, 10.2, -2.6) * CFrame.Angles(0, math.pi, 0), rgb(250, 200, 60))
	wedge(parent, "Slide", Vector3.new(2.6, 6, 8), cf * CFrame.new(6, 3, 2.3) * CFrame.Angles(0, math.pi, 0), rgb(250, 200, 60), Enum.Material.SmoothPlastic, true)
	for n = 0, 5 do
		deco(parent, "Ladder", Vector3.new(2, 0.3, 0.3), cf * CFrame.new(6, 0.8 + n, -7), blue, Enum.Material.Metal)
	end
	table.insert(spots, outSpot(cf * CFrame.new(6, 0.2, 7.5) * CFrame.Angles(0, math.pi, 0), "play", "kid"))
	table.insert(spots, outSpot(cf * CFrame.new(6, 0.2, -8.5), "play", "kid"))
	-- seesaw and sandbox
	deco(parent, "SeesawBase", Vector3.new(1, 1.4, 1), cf * CFrame.new(-6, 0.9, -5), red, Enum.Material.Metal)
	deco(parent, "Seesaw", Vector3.new(10, 0.4, 1.2), cf * CFrame.new(-6, 1.6, -5) * CFrame.Angles(0, 0, math.rad(12)), rgb(250, 200, 60))
	table.insert(spots, outSpot(cf * CFrame.new(-10.5, 0.2, -5) * CFrame.Angles(0, math.rad(-90), 0), "play", "kid"))
	table.insert(spots, outSpot(cf * CFrame.new(-1.5, 0.2, -5) * CFrame.Angles(0, math.rad(90), 0), "play", "kid"))
	if big then
		part(parent, "Sandbox", Vector3.new(8, 0.8, 8), cf * CFrame.new(-6, 0.4, -12 + 20), rgb(150, 110, 70), Enum.Material.Wood)
	end
	-- a bench for parents
	local seat, sit = Streets.bench(parent, cf * CFrame.new(0, 0, -10.5) * CFrame.Angles(0, math.pi, 0), nil)
	table.insert(spots, outSpot(sit, "sit", "visit"))
end

local function hoop(parent, cf)
	deco(parent, "HoopPost", Vector3.new(0.6, 10, 0.6), cf * CFrame.new(0, 5, 0), rgb(50, 50, 55), Enum.Material.Metal)
	deco(parent, "Backboard", Vector3.new(6, 4, 0.3), cf * CFrame.new(0, 10, -0.5), WHITE)
	deco(parent, "BoardSquare", Vector3.new(2.2, 1.6, 0.35), cf * CFrame.new(0, 9.6, -0.5), rgb(220, 60, 50))
	MapKit.cylinder(parent, "Hoop", 0.3, 2.4, cf * CFrame.new(0, 9, -1.8) * CFrame.Angles(0, 0, math.rad(90)), rgb(240, 90, 30), Enum.Material.Metal)
end

local function court(parent, cf, spots, w, d)
	w, d = w or 26, d or 34
	part(parent, "Court", Vector3.new(w, 0.15, d), cf * CFrame.new(0, 0.1, 0), rgb(196, 110, 64), Enum.Material.Concrete)
	deco(parent, "CourtLine", Vector3.new(w, 0.16, 0.3), cf * CFrame.new(0, 0.12, 0), WHITE)
	MapKit.disc(parent, "CenterCircle", 0.17, 6, (cf * CFrame.new(0, 0.1, 0)).Position, rgb(230, 230, 230))
	for _, sz in ipairs({ -1, 1 }) do
		local hcf = cf * CFrame.new(0, 0, sz * (d / 2 - 1)) * CFrame.Angles(0, if sz > 0 then 0 else math.pi, 0)
		hoop(parent, hcf)
		for k = -1, 1 do
			local s = outSpot(cf * CFrame.new(k * 5, 0.2, sz * (d / 2 - 9)) * CFrame.Angles(0, if sz > 0 then math.pi else 0, 0), "hoops", "kid")
			s.Hoop = (hcf * CFrame.new(0, 9, -1.8)).Position
			table.insert(spots, s)
		end
	end
end

local function flowerBed(parent, cf, w, d, rng)
	part(parent, "FlowerBed", Vector3.new(w, 0.8, d), cf * CFrame.new(0, 0.4, 0), rgb(110, 76, 50), Enum.Material.Ground)
	for n = 0, math.floor(w * d / 5) do
		MapKit.ball(parent, "Flower", rng:NextNumber(0.9, 1.4), cf * CFrame.new(rng:NextNumber(-w / 2 + 0.6, w / 2 - 0.6), 1.1, rng:NextNumber(-d / 2 + 0.6, d / 2 - 0.6)), MapKit.FLOWERS[rng:NextInteger(1, #MapKit.FLOWERS)])
	end
end

local function statue(parent, pos, color)
	part(parent, "StatuePlinth", Vector3.new(5, 4, 5), CFrame.new(pos + Vector3.new(0, 2, 0)), STONE, Enum.Material.Marble)
	deco(parent, "StatueLegs", Vector3.new(2, 3, 1), CFrame.new(pos + Vector3.new(0, 5.5, 0)), color, Enum.Material.Metal)
	deco(parent, "StatueBody", Vector3.new(2.4, 3, 1.2), CFrame.new(pos + Vector3.new(0, 8.5, 0)), color, Enum.Material.Metal)
	MapKit.ball(parent, "StatueHead", 1.6, CFrame.new(pos + Vector3.new(0, 10.8, 0)), color, Enum.Material.Metal)
	deco(parent, "StatueArm", Vector3.new(0.8, 3, 0.8), CFrame.new(pos + Vector3.new(1.6, 10.3, 0)) * CFrame.Angles(0, 0, math.rad(-20)), color, Enum.Material.Metal)
	deco(parent, "StatueTorch", Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos + Vector3.new(2.2, 12, 0)), rgb(255, 180, 60), Enum.Material.Neon)
end

--------------------------------------------------------------------------------
-- Builders by block kind
--------------------------------------------------------------------------------
local B = {}

function B.Plaza(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local model = Instance.new("Model")
	model.Name = "Plaza"
	model.Parent = parent
	local spots = {}
	ctx.lot(model, c, rgb(226, 214, 192), Enum.Material.Cobblestone)
	-- a ring pattern in the paving
	for r = 1, 3 do
		MapKit.disc(model, "PavingRing", 0.12, 20 + r * 12, c + Vector3.new(0, 0.12 + r * 0.001, 0), if r % 2 == 0 then rgb(236, 226, 206) else rgb(206, 192, 170), Enum.Material.Slate)
	end
	-- fountain
	local f = Instance.new("Model")
	f.Name = "Fountain"
	f.Parent = model
	column(f, "FountainBase", 2, 26, c + Vector3.new(0, 1, 0), STONE, Enum.Material.Marble)
	column(f, "FountainRim", 0.6, 27, c + Vector3.new(0, 2.2, 0), rgb(236, 230, 218), Enum.Material.Marble)
	local water = column(f, "Water", 0.4, 23, c + Vector3.new(0, 2.05, 0), rgb(80, 170, 240), Enum.Material.Glass, false)
	water.Transparency = 0.25
	column(f, "FountainPillar", 6, 3, c + Vector3.new(0, 4, 0), STONE, Enum.Material.Marble)
	column(f, "FountainBowl", 1, 11, c + Vector3.new(0, 6.5, 0), STONE, Enum.Material.Marble)
	local bowlWater = column(f, "BowlWater", 0.3, 9.6, c + Vector3.new(0, 6.9, 0), rgb(80, 170, 240), Enum.Material.Glass, false)
	bowlWater.Transparency = 0.25
	local top = column(f, "FountainTop", 3, 1.6, c + Vector3.new(0, 8.5, 0), STONE, Enum.Material.Marble)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(rgb(200, 235, 255))
	spray.LightEmission = 0.4
	spray.Size = NumberSequence.new(0.6, 0.2)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Rate = 45
	spray.Speed = NumberRange.new(10, 12)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.EmissionDirection = Enum.NormalId.Right
	spray.Parent = top
	local glow = MapKit.nightLight(bowlWater, rgb(120, 200, 255), 18, 1.2)
	glow.Name = "FountainGlow"
	-- the speech stage on the north side
	local stageCf = facing(c + Vector3.new(0, 0, -28), c)
	part(model, "Stage", Vector3.new(30, 2, 12), stageCf * CFrame.new(0, 1, 0), WOOD, Enum.Material.WoodPlanks)
	part(model, "StageStep", Vector3.new(8, 1, 3), stageCf * CFrame.new(0, 0.5, -7.5), WOOD:Lerp(BLACK, 0.1), Enum.Material.WoodPlanks)
	local backdrop = part(model, "Backdrop", Vector3.new(30, 12, 1), stageCf * CFrame.new(0, 8, 5.5), rgb(150, 40, 60), Enum.Material.Fabric)
	MapKit.signText(backdrop, Enum.NormalId.Front, "SPEAK TO THE CITY", GOLD)
	for _, sx in ipairs({ -1, 1 }) do
		column(model, "StagePillar", 12, 1.6, (stageCf * CFrame.new(sx * 15, 8, 5.2)).Position, GOLD, Enum.Material.Metal)
		flag(model, (stageCf * CFrame.new(sx * 12, 2, 4)).Position, rgb(60, 110, 220), 14)
		local spotlight = deco(model, "StageLight", Vector3.new(1.2, 1.2, 1.6), stageCf * CFrame.new(sx * 10, 13.4, 4.6), rgb(40, 40, 44), Enum.Material.Metal)
		MapKit.spot(spotlight, Enum.NormalId.Front, rgb(255, 240, 210), 30, 50, 1.5)
	end
	local podium = part(model, "Podium", Vector3.new(3.4, 4, 2.4), stageCf * CFrame.new(0, 4, -3), rgb(90, 60, 40), Enum.Material.Wood)
	deco(model, "PodiumTop", Vector3.new(4, 0.4, 3), stageCf * CFrame.new(0, 6.1, -3) * CFrame.Angles(math.rad(-15), 0, 0), rgb(70, 45, 30), Enum.Material.Wood)
	deco(model, "Microphone", Vector3.new(0.3, 1.4, 0.3), stageCf * CFrame.new(0, 7, -3.2), rgb(40, 40, 45), Enum.Material.Metal)
	MapKit.signText(podium, Enum.NormalId.Front, "SPEAK", WHITE)
	ctx.map.Podium = podium
	ctx.map.SpeechSpot = (stageCf * CFrame.new(0, 2, -1)).Position
	ctx.map.StageCFrame = stageCf * CFrame.new(0, 2, -1)
	-- ballot box and the city news board
	local ballot = part(model, "BallotBox", Vector3.new(4, 4, 4), facing(c + Vector3.new(22, 2, -16), c + Vector3.new(0, 2, 0)), rgb(60, 90, 200))
	deco(model, "BallotSlot", Vector3.new(2.4, 0.2, 0.5), ballot.CFrame * CFrame.new(0, 2.05, 0), BLACK)
	MapKit.signText(ballot, Enum.NormalId.Front, "VOTE", WHITE)
	ctx.map.BallotBox = ballot
	local board = part(model, "NewsBoard", Vector3.new(14, 8, 0.8), facing(c + Vector3.new(-22, 6, -16), c + Vector3.new(0, 6, 0)), rgb(40, 36, 50))
	for _, sx in ipairs({ -1, 1 }) do
		deco(model, "BoardPost", Vector3.new(0.6, 10, 0.6), board.CFrame * CFrame.new(sx * 6.5, -1, 0.6), WOOD, Enum.Material.Wood)
	end
	ctx.map.NewsBoard = MapKit.signText(board, Enum.NormalId.Front, "CITY NEWS\nWelcome to AI City!", WHITE, Enum.Font.GothamBold)
	-- benches around the fountain, facing it
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + math.pi / 8
		local pos = c + Vector3.new(math.cos(a) * 19, 0, math.sin(a) * 19)
		if pos.Z > c.Z - 17 then
			local seat, sit = Streets.bench(model, facing(pos, c) * CFrame.Angles(0, math.pi, 0), "Plaza")
			local s = outSpot(sit, if k % 3 == 0 then "read" elseif k % 3 == 1 then "sit" else "phone", "visit")
			s.Seat = seat
			table.insert(spots, s)
		end
	end
	-- chess tables with stools, and a dance floor
	for _, sx in ipairs({ -1, 1 }) do
		local p = c + Vector3.new(sx * 26, 0, 22)
		column(model, "ChessTable", 3, 4, p + Vector3.new(0, 1.5, 0), STONE, Enum.Material.Marble)
		MapKit.chessBoard(model, CFrame.new(p + Vector3.new(0, 3.05, 0)), 3)
		for _, sz in ipairs({ -1, 1 }) do
			local stool = MapKit.seat(model, "Stool", Vector3.new(1.6, 0.4, 1.6), CFrame.new(p + Vector3.new(0, 1.9, sz * 2.8)), STONE, Enum.Material.Marble, "Plaza")
			column(model, "StoolLeg", 1.7, 1, p + Vector3.new(0, 0.85, sz * 2.8), STONE, Enum.Material.Marble)
			local s = outSpot(facing(p + Vector3.new(0, 0, sz * 2.8), p), "chess", "visit")
			s.Seat = stool
			table.insert(spots, s)
			ctx.hobby("playing chess", s)
		end
	end
	local danceAt = c + Vector3.new(0, 0, 27)
	local floorPart = deco(model, "DanceFloor", Vector3.new(16, 0.15, 12), CFrame.new(danceAt + Vector3.new(0, 0.2, 0)), rgb(80, 60, 140), Enum.Material.Neon, { Transparency = 0.5 })
	MapKit.tag(floorPart, "DanceFloor")
	for k = 0, 5 do
		local s = outSpot(CFrame.new(danceAt + Vector3.new((k % 3 - 1) * 5, 0, (k // 3 - 0.5) * 5)) * CFrame.Angles(0, k * 1.1, 0), "dance", "visit")
		table.insert(spots, s)
		ctx.hobby("dancing", s)
	end
	-- musicians' corners
	for _, sx in ipairs({ -1, 1 }) do
		local s = outSpot(facing(c + Vector3.new(sx * 14, 0, 16), c), "music", "work")
		table.insert(spots, s)
		ctx.hobby("playing guitar", outSpot(facing(c + Vector3.new(sx * 9, 0, 18), c), "guitar", "visit"))
	end
	-- corner planters with trees, a statue of the founder, pigeons
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = c + Vector3.new(sx * 32, 0, sz * 32)
			part(model, "Planter", Vector3.new(7, 1.6, 7), CFrame.new(p + Vector3.new(0, 0.8, 0)), STONE, Enum.Material.Brick)
			Streets.tree(model, p + Vector3.new(0, 1.6, 0), 0.9, rng)
		end
	end
	statue(model, c + Vector3.new(0, 0, 36), rgb(120, 150, 130))
	for k = 1, 8 do
		local p = c + Vector3.new(rng:NextNumber(-20, 20), 0.4, rng:NextNumber(4, 24))
		local pigeon = MapKit.ball(model, "Pigeon", 0.7, CFrame.new(p), rgb(140, 140, 150))
		MapKit.tag(pigeon, "Pigeon")
	end
	ctx.outdoor("Plaza", model, i, j, c + Vector3.new(0, 0, 36), Vector3.new(0, 0, 1), spots)
end

-- A park: pond, gazebo, gardens, easels, picnic blankets, a playground and paths
local function park(ctx, parent, i, j, rng, id, withPlayground)
	local c = ctx.blockCenter(i, j)
	local model = Instance.new("Model")
	model.Name = id
	model.Parent = parent
	local spots = {}
	ctx.lot(model, c, MapKit.DARK_GRASS, Enum.Material.Grass)
	local path = rgb(214, 196, 154)
	deco(model, "Path", Vector3.new(74, 0.14, 5), CFrame.new(c + Vector3.new(0, 0.12, 0)), path, Enum.Material.Sand)
	deco(model, "Path", Vector3.new(5, 0.14, 74), CFrame.new(c + Vector3.new(0, 0.12, 0)), path, Enum.Material.Sand)
	-- thick bushes by the entrances (somewhere to hide)
	for _, e in ipairs({ { 33, 6 }, { -33, -6 }, { 6, -33 }, { -6, 33 } }) do
		local bush = MapKit.ball(model, "Bush", 5.5, CFrame.new(c + Vector3.new(e[1], 2.2, e[2])), MapKit.LEAVES[2], Enum.Material.Grass)
		bush.CanCollide = false
		bush:SetAttribute("HideName", "a bush")
		MapKit.tag(bush, "HideSpot")
	end
	-- pond with lily pads and ducks
	local pondC = c + Vector3.new(-18, 0, 18)
	column(model, "PondEdge", 0.6, 26, pondC + Vector3.new(0, 0.3, 0), STONE, Enum.Material.Pebble)
	local pond = column(model, "Pond", 0.5, 23, pondC + Vector3.new(0, 0.4, 0), rgb(60, 140, 200), Enum.Material.Glass, false)
	pond.Transparency = 0.15
	for k = 0, 3 do
		MapKit.disc(model, "LilyPad", 0.1, 2, pondC + Vector3.new(k * 3 - 4.5, 0.7, (k % 2) * 4 - 2), rgb(80, 170, 70), Enum.Material.Grass)
	end
	for k = 0, 2 do
		local duck = MapKit.ball(model, "Duck", 1.2, CFrame.new(pondC + Vector3.new(k * 4 - 4, 0.9, -3 + k)), WHITE)
		MapKit.tag(duck, "Duck")
		MapKit.ball(model, "DuckHead", 0.7, CFrame.new(pondC + Vector3.new(k * 4 - 4, 1.6, -3.5 + k)), rgb(60, 140, 70))
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + 0.4
		local p = pondC + Vector3.new(math.cos(a) * 14.5, 0, math.sin(a) * 14.5)
		local s = outSpot(facing(p, pondC), "fish", "visit")
		table.insert(spots, s)
		ctx.hobby("fishing", s)
	end
	-- gazebo with a bench ring
	local g = c + Vector3.new(18, 0, -18)
	column(model, "GazeboFloor", 1, 16, g + Vector3.new(0, 0.5, 0), rgb(236, 230, 220), Enum.Material.WoodPlanks)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		deco(model, "GazeboPost", Vector3.new(0.8, 9, 0.8), CFrame.new(g + Vector3.new(math.cos(a) * 7, 5, math.sin(a) * 7)), WHITE, Enum.Material.Wood)
	end
	column(model, "GazeboRoof", 1.2, 18, g + Vector3.new(0, 10, 0), rgb(180, 70, 60), Enum.Material.Slate, false)
	column(model, "GazeboRoofTop", 2, 10, g + Vector3.new(0, 11.4, 0), rgb(160, 60, 55), Enum.Material.Slate, false)
	local s = outSpot(facing(g + Vector3.new(0, 1, 0), g + Vector3.new(0, 0, -5)), "guitar", "visit")
	table.insert(spots, s)
	ctx.hobby("playing guitar", s)
	local bw = outSpot(facing(g + Vector3.new(4, 1, 0), g + Vector3.new(20, 0, 0)), "birdwatch", "visit")
	table.insert(spots, bw)
	ctx.hobby("birdwatching", bw)
	-- garden beds: the gardeners work here, and gardeners-at-heart visit
	for k = 0, 3 do
		local p = c + Vector3.new(10 + (k % 2) * 12, 0, 12 + (k // 2) * 10)
		flowerBed(model, CFrame.new(p), 9, 5, rng)
		local gs = outSpot(facing(p + Vector3.new(0, 0, -4), p), "garden", if k < 2 then "work" else "visit")
		table.insert(spots, gs)
		if k >= 2 then
			ctx.hobby("gardening", gs)
		end
	end
	-- easels for painters
	for k = 0, 1 do
		local p = c + Vector3.new(-26 + k * 8, 0, -22)
		deco(model, "Easel", Vector3.new(3, 4, 0.3), CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(math.rad(-10), 0, 0), rgb(245, 240, 230))
		deco(model, "EaselLeg", Vector3.new(0.3, 5, 0.3), CFrame.new(p + Vector3.new(0, 2.5, 0.8)) * CFrame.Angles(math.rad(15), 0, 0), WOOD)
		local ps = outSpot(facing(p + Vector3.new(0, 0, 2.5), p), "paint", "visit")
		table.insert(spots, ps)
		ctx.hobby("painting", ps)
	end
	-- picnic blankets
	for k = 0, 1 do
		local p = c + Vector3.new(-8 - k * 8, 0, -14)
		deco(model, "PicnicBlanket", Vector3.new(5, 0.08, 5), CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, k * 0.4, 0), ({ rgb(220, 70, 70), rgb(70, 130, 220) })[k + 1], Enum.Material.Fabric)
		deco(model, "Basket", Vector3.new(1.6, 1.2, 1.2), CFrame.new(p + Vector3.new(1.4, 0.7, 1.4)), rgb(170, 120, 70), Enum.Material.Wood)
		table.insert(spots, outSpot(facing(p + Vector3.new(-1, 0, 0), p + Vector3.new(1, 0, 0)), "eat", "visit"))
	end
	-- benches along the paths
	for _, b in ipairs({ { -8, -3.2, 0 }, { 8, 3.2, 180 }, { -30, -3.2, 0 }, { 3.2, -30, 90 } }) do
		local seat, sit = Streets.bench(model, CFrame.new(c + Vector3.new(b[1], 0, b[2])) * CFrame.Angles(0, math.rad(b[3]), 0), id)
		local bs = outSpot(sit, ({ "read", "knit", "sit", "phone" })[rng:NextInteger(1, 4)], "visit")
		bs.Seat = seat
		table.insert(spots, bs)
		if bs.Action == "read" then
			ctx.hobby("reading", bs)
		elseif bs.Action == "knit" then
			ctx.hobby("knitting", bs)
		end
	end
	if withPlayground then
		playground(ctx, model, c + Vector3.new(20, 0, 20), math.pi, spots, false)
	end
	-- trees around the edge
	for k = 1, 12 do
		local a = k / 12 * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 33, 0, math.sin(a) * 33)
		Streets.tree(model, p, rng:NextNumber(0.9, 1.3), rng)
	end
	-- a jogging loop around the park
	local loop = {}
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		table.insert(loop, c + Vector3.new(math.cos(a) * 28, 0, math.sin(a) * 28))
	end
	local place = ctx.outdoor(id, model, i, j, c + Vector3.new(-35, 0, 0), Vector3.new(-1, 0, 0), spots)
	place.JoggingLoop = loop
	table.insert(ctx.map.JoggingLoops, loop)
	return place
end

function B.Park(ctx, parent, i, j, rng)
	park(ctx, parent, i, j, rng, "Park", true)
end

function B.WillowPark(ctx, parent, i, j, rng)
	park(ctx, parent, i, j, rng, "WillowPark", true)
end

function B.SportsField(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local model = Instance.new("Model")
	model.Name = "SportsField"
	model.Parent = parent
	local spots = {}
	ctx.lot(model, c, rgb(176, 90, 70), Enum.Material.Concrete) -- running track color
	local fieldC = c + Vector3.new(0, 0, 4)
	local L, Wd = 58, 36
	part(model, "Field", Vector3.new(L, 0.14, Wd), CFrame.new(fieldC + Vector3.new(0, 0.12, 0)), rgb(70, 160, 70), Enum.Material.Grass)
	for s = -5, 5 do
		deco(model, "Stripe", Vector3.new(5, 0.15, Wd), CFrame.new(fieldC + Vector3.new(s * 5.3, 0.125, 0)), if s % 2 == 0 then rgb(76, 168, 76) else rgb(66, 152, 66), Enum.Material.Grass)
	end
	deco(model, "Line", Vector3.new(0.4, 0.17, Wd), CFrame.new(fieldC + Vector3.new(0, 0.14, 0)), WHITE)
	MapKit.disc(model, "CenterCircle", 0.16, 10, fieldC + Vector3.new(0, 0.13, 0), rgb(240, 240, 240))
	MapKit.disc(model, "CenterCircleInner", 0.17, 9.2, fieldC + Vector3.new(0, 0.13, 0), rgb(70, 160, 70), Enum.Material.Grass)
	local goals = {}
	for _, sx in ipairs({ -1, 1 }) do
		deco(model, "Line", Vector3.new(L, 0.17, 0.4), CFrame.new(fieldC + Vector3.new(0, 0.14, sx * Wd / 2)), WHITE)
		deco(model, "Line", Vector3.new(0.4, 0.17, Wd), CFrame.new(fieldC + Vector3.new(sx * L / 2, 0.14, 0)), WHITE)
		deco(model, "Box", Vector3.new(0.4, 0.17, 16), CFrame.new(fieldC + Vector3.new(sx * (L / 2 - 8), 0.14, 0)), WHITE)
		for _, bz in ipairs({ -8, 8 }) do
			deco(model, "Box", Vector3.new(8, 0.17, 0.4), CFrame.new(fieldC + Vector3.new(sx * (L / 2 - 4), 0.14, bz)), WHITE)
		end
		-- goal frame and net
		local gx = sx * (L / 2 + 0.5)
		for _, gz in ipairs({ -5, 5 }) do
			deco(model, "GoalPost", Vector3.new(0.5, 6, 0.5), CFrame.new(fieldC + Vector3.new(gx, 3, gz)), WHITE, Enum.Material.Metal)
		end
		deco(model, "GoalBar", Vector3.new(0.5, 0.5, 10.5), CFrame.new(fieldC + Vector3.new(gx, 6, 0)), WHITE, Enum.Material.Metal)
		local net = deco(model, "GoalNet", Vector3.new(3, 6, 10), CFrame.new(fieldC + Vector3.new(gx + sx * 1.6, 3, 0)), rgb(240, 240, 240), Enum.Material.Fabric)
		net.Transparency = 0.6
		table.insert(goals, fieldC + Vector3.new(gx, 0, 0))
	end
	-- bleachers with seats
	for row = 0, 2 do
		part(model, "Bleacher", Vector3.new(40, 1, 3), CFrame.new(c + Vector3.new(0, 0.5 + row * 1.5, -24 - row * 3)), rgb(70, 110, 200), Enum.Material.Metal)
		for k = -2, 2 do
			local s = outSpot(CFrame.new(c + Vector3.new(k * 7, 1 + row * 1.5, -24 - row * 3)), "cheer", "visit")
			s.Raise = 1 + row * 1.5
			table.insert(spots, s)
		end
	end
	-- floodlights
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = c + Vector3.new(sx * 38, 0, sz * 26)
			deco(model, "FloodPole", Vector3.new(0.8, 24, 0.8), CFrame.new(p + Vector3.new(0, 12, 0)), rgb(80, 84, 90), Enum.Material.Metal)
			local head = deco(model, "Floodlight", Vector3.new(3, 2, 1), facing(p + Vector3.new(0, 24, 0), fieldC), rgb(250, 250, 240), Enum.Material.SmoothPlastic)
			MapKit.nightNeon(head)
			local l = MapKit.spot(head, Enum.NormalId.Front, rgb(255, 250, 235), 60, 70, 2)
			l.Enabled = false
			table.insert(MapKit.Registry.NightLights, l)
		end
	end
	local place = ctx.outdoor("SportsField", model, i, j, c + Vector3.new(0, 0, -36), Vector3.new(0, 0, -1), spots)
	place.Field = { Center = fieldC, Length = L, Width = Wd, Goals = goals }
	table.insert(ctx.map.SoccerFields, place.Field)
	-- the running track around the field for joggers
	local loop = {}
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		table.insert(loop, fieldC + Vector3.new(math.cos(a) * 34, 0, math.sin(a) * 22))
	end
	table.insert(ctx.map.JoggingLoops, loop)
	for k = 1, 4 do
		ctx.hobby("jogging", outSpot(CFrame.new(loop[k * 3]), "run", "visit"))
	end
end

function B.TownHall(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "TownHall", Label = ctx.label("TownHall"), Center = ctx.frontLot(c, face, 44) - face * 5, Face = face, W = 60, D = 44, Floors = 2, Wall = rgb(236, 230, 214), Trim = rgb(190, 176, 150), Material = Enum.Material.Marble, DoorW = 10, SignColor = rgb(60, 50, 40), SignText = GOLD, Stairs = true })
	local at = b.At
	for s = 0, 2 do
		part(b.Model, "Steps", Vector3.new(40 - s * 4, 0.6, 3), at(0, 0.3 + s * 0.6, -b.D / 2 - 7 + s * 1.6), rgb(222, 216, 206), Enum.Material.Marble)
	end
	for k = -3, 3 do
		if k ~= 0 then
			column(b.Model, "Column", 20, 2.4, at(k * 6, 11, -b.D / 2 - 3).Position, WHITE, Enum.Material.Marble)
		end
	end
	wedge(b.Model, "Pediment", Vector3.new(46, 5, 6), at(0, b.H + 2.5, -b.D / 2 - 3), rgb(236, 230, 214), Enum.Material.Marble)
	part(b.Model, "Portico", Vector3.new(46, 1, 7), at(0, 21.5, -b.D / 2 - 3), rgb(226, 218, 200), Enum.Material.Marble)
	part(b.Model, "Tower", Vector3.new(12, 16, 12), at(0, b.H + 8, 2), rgb(236, 230, 214), Enum.Material.Marble)
	local clock = deco(b.Model, "Clock", Vector3.new(7, 7, 0.4), at(0, b.H + 9, -4.2), WHITE)
	ctx.map.ClockFace = MapKit.signText(clock, Enum.NormalId.Front, "12:00", BLACK, Enum.Font.GothamBold)
	MapKit.light(clock, rgb(255, 240, 200), 12, 0.6)
	local dome = MapKit.ball(b.Model, "Dome", 13, at(0, b.H + 16, 2), rgb(120, 170, 150), Enum.Material.Metal)
	dome.CanCollide = true
	flag(b.Model, at(0, b.H + 21, 2).Position, rgb(60, 110, 220), 10)
	for _, sx in ipairs({ -1, 1 }) do
		flag(b.Model, at(sx * 24, 0, -b.D / 2 - 9).Position, rgb(220, 60, 60), 20)
		flowerBed(b.Model, at(sx * 16, 0, -b.D / 2 - 9), 8, 3, rng)
	end
	local spots = Interiors.furnish(b, { "townhall", "office" }, rng, "TownHall")
	local place = ctx.place("TownHall", b, i, j, face, spots)
	place.MayorOffice = b.MayorOffice
end

function B.Bank(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "Bank", Label = ctx.label("Bank"), Center = ctx.frontLot(c, face, 40) - face * 3, Face = face, W = 56, D = 40, Floors = 4, Wall = rgb(212, 206, 196), Trim = rgb(150, 140, 120), Material = Enum.Material.Granite, DoorW = 9, SignColor = rgb(30, 60, 50), SignText = GOLD, RoofKit = { "ac", "antenna" } })
	local at = b.At
	for k = -2, 2 do
		if k ~= 0 then
			column(b.Model, "Column", 11, 1.8, at(k * 6.5, 5.5, -b.D / 2 - 2).Position, rgb(240, 238, 230), Enum.Material.Marble)
		end
	end
	part(b.Model, "Portico", Vector3.new(30, 1, 5), at(0, 11.5, -b.D / 2 - 2), rgb(226, 220, 210), Enum.Material.Marble)
	local vault = MapKit.cylinder(b.Model, "VaultDoor", 1, 9, at(0, 5, b.D / 2 - 1.2) * CFrame.Angles(0, math.rad(90), 0), rgb(150, 155, 165), Enum.Material.DiamondPlate)
	MapKit.cylinder(b.Model, "VaultWheel", 0.6, 4, at(0, 5, b.D / 2 - 1.9) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
	local atm = part(b.Model, "ATM", Vector3.new(3, 6, 2), at(b.W / 2 - 5, 3, -b.D / 2 - 1.2), rgb(60, 70, 80), Enum.Material.Metal)
	deco(b.Model, "ATMScreen", Vector3.new(2, 1.4, 0.2), atm.CFrame * CFrame.new(0, 1.2, -1.05), rgb(100, 220, 160), Enum.Material.Neon)
	local spots = Interiors.furnish(b, { "bank", Upper = "office" }, rng, "Bank")
	local place = ctx.place("Bank", b, i, j, face, spots)
	place.Vault = at(0, 0.4, b.D / 2 - 5).Position
	place.ATM = atm
end

function B.Police(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "PoliceStation", Label = ctx.label("PoliceStation"), Center = ctx.frontLot(c, face, 38) - face * 6, Face = face, W = 54, D = 38, Floors = 2, Wall = rgb(70, 95, 160), Trim = rgb(230, 230, 235), Material = Enum.Material.Brick, SignColor = rgb(25, 40, 90), Stairs = true })
	local at = b.At
	-- a white stripe around the outside of the station (with a gap for the doors)
	MapKit.ring(b.Model, "Stripe", at(0, 4, 0), b.W, b.D, 1.2, 0.12, WHITE, nil, (b.Spec.DoorW or 8) + 1)
	local siren = deco(b.Model, "Siren", Vector3.new(3, 1.2, 1.5), at(0, b.H + 1.8, -b.D / 2 + 2), rgb(255, 60, 60), Enum.Material.Neon)
	MapKit.tag(siren, "Siren")
	MapKit.light(siren, rgb(255, 60, 60), 14, 1)
	flag(b.Model, at(-b.W / 2 + 3, 0, -b.D / 2 - 5).Position, rgb(60, 110, 220))
	for k = 0, 1 do
		local cf = at(b.W / 2 - 6 - k * 9, 0, -b.D / 2 - 8) * CFrame.Angles(0, math.rad(90), 0)
		local m = Streets.car(b.Model, cf, WHITE)
		m.Name = "PoliceCar"
		deco(m, "Stripe", Vector3.new(6.1, 0.8, 11.1), cf * CFrame.new(0, 2.3, 0), rgb(40, 60, 140))
		local bar = deco(m, "LightBar", Vector3.new(3.6, 0.6, 1), cf * CFrame.new(0, 5.4, 0.6), rgb(80, 120, 255), Enum.Material.Neon)
		MapKit.tag(bar, "Siren")
	end
	local spots = Interiors.furnish(b, { "police", "office" }, rng, "PoliceStation")
	local place = ctx.place("PoliceStation", b, i, j, face, spots)
	place.Jail = b.Jail
	ctx.map.Jail = b.Jail
end

function B.FireStation(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "FireStation", Label = ctx.label("FireStation"), Center = ctx.frontLot(c, face, 40) - face * 6, Face = face, W = 52, D = 40, Floors = 2, Wall = rgb(190, 55, 45), Trim = rgb(240, 235, 225), Material = Enum.Material.Brick, DoorW = 8, SignColor = rgb(70, 20, 20) })
	local at = b.At
	for _, sx in ipairs({ -1, 1 }) do
		deco(b.Model, "GarageDoor", Vector3.new(12, 10, 0.4), at(sx * 16, 5, -b.D / 2 - 0.2), rgb(230, 230, 235), Enum.Material.DiamondPlate)
		for n = 0, 3 do
			deco(b.Model, "GarageWindow", Vector3.new(2.4, 1, 0.45), at(sx * 16 - 4.2 + n * 2.8, 8.4, -b.D / 2 - 0.2), MapKit.GLASS, Enum.Material.Glass)
		end
	end
	part(b.Model, "HoseTower", Vector3.new(8, 36, 8), at(b.W / 2 - 4, 18, b.D / 2 - 4), rgb(175, 50, 40), Enum.Material.Brick)
	local truck = Instance.new("Model")
	truck.Name = "FireTruck"
	truck.Parent = b.Model
	local tcf = at(-12, 0, -b.D / 2 - 8) * CFrame.Angles(0, math.rad(90), 0)
	deco(truck, "Body", Vector3.new(7, 5, 18), tcf * CFrame.new(0, 3.5, 0), rgb(215, 40, 35))
	deco(truck, "Cab", Vector3.new(7, 3, 5), tcf * CFrame.new(0, 7, -6), rgb(215, 40, 35))
	deco(truck, "CabWindow", Vector3.new(6.4, 2, 0.2), tcf * CFrame.new(0, 7.2, -8.55), MapKit.GLASS, Enum.Material.Glass)
	deco(truck, "Ladder", Vector3.new(1.6, 0.6, 16), tcf * CFrame.new(0, 6.4, 1), rgb(220, 220, 225), Enum.Material.Metal)
	local beacon = deco(truck, "Beacon", Vector3.new(4, 0.7, 1), tcf * CFrame.new(0, 8.8, -6), rgb(255, 60, 60), Enum.Material.Neon)
	MapKit.tag(beacon, "Siren")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			MapKit.cylinder(truck, "Wheel", 1, 3, tcf * CFrame.new(sx * 3.3, 1.5, sz * 6), rgb(25, 25, 28), Enum.Material.Rubber)
		end
	end
	local spots = Interiors.furnish(b, { "garage" }, rng, "FireStation")
	-- firefighters also wash and check the truck
	table.insert(spots, { CFrame = facing(at(-12, 0, -b.D / 2 - 3).Position, at(-12, 0, -b.D / 2 - 8).Position), Action = "sweep", Role = "work", Floor = 1, Outside = true })
	table.insert(spots, { CFrame = facing(at(-4, 0, -b.D / 2 - 8).Position, at(-12, 0, -b.D / 2 - 8).Position), Action = "fixcar", Role = "work", Floor = 1, Outside = true })
	ctx.place("FireStation", b, i, j, face, spots)
end

function B.Hospital(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "Hospital", Label = ctx.label("Hospital"), Center = ctx.frontLot(c, face, 46) - face * 3, Face = face, W = 64, D = 46, Floors = 5, Wall = rgb(244, 246, 250), Trim = rgb(120, 180, 220), Material = Enum.Material.SmoothPlastic, DoorW = 10, SignColor = rgb(200, 40, 50), RoofKit = { "helipad", "ac" } })
	local at = b.At
	for _, s in ipairs({ { 8, 2.4 }, { 2.4, 8 } }) do
		local cross = deco(b.Model, "Cross", Vector3.new(s[1], s[2], 0.4), at(b.W / 2 - 8, b.H - 6, -b.D / 2 - 0.4), rgb(220, 40, 50), Enum.Material.Neon)
		cross.Name = "Cross"
	end
	part(b.Model, "Canopy", Vector3.new(20, 1, 10), at(-b.W / 2 + 12, 11, -b.D / 2 - 5), rgb(120, 180, 220), Enum.Material.Metal)
	local ambCf = at(-b.W / 2 + 12, 0, -b.D / 2 - 6) * CFrame.Angles(0, math.rad(90), 0)
	local amb = Streets.car(b.Model, ambCf, WHITE, "van")
	amb.Name = "Ambulance"
	deco(amb, "Stripe", Vector3.new(6.1, 0.8, 13.1), ambCf * CFrame.new(0, 3, 0), rgb(220, 40, 50))
	local spots = Interiors.furnish(b, { "hospital", Upper = "hospital" }, rng, "Hospital")
	local place = ctx.place("Hospital", b, i, j, face, spots)
	place.Beds = {}
	for _, s in ipairs(spots) do
		if s.HospitalBed then
			table.insert(place.Beds, s)
		end
	end
end

-- Schools: classrooms on every floor and a yard for recess
local function school(ctx, parent, i, j, rng, id, floors, yard, colors)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = id, Label = ctx.label(id), Center = ctx.frontLot(c, face, 34, -14), Face = face, W = 44, D = 34, Floors = floors, Wall = colors[1], Trim = colors[2], Material = Enum.Material.Brick, SignColor = colors[3], Stairs = floors == 2, Elevator = floors >= 3 })
	local at = b.At
	deco(b.Model, "BellTower", Vector3.new(6, 6, 6), at(0, b.H + 3, 0), colors[2])
	wedge(b.Model, "BellRoof", Vector3.new(7, 3, 3.5), at(0, b.H + 7.5, -1.75), rgb(150, 50, 40))
	wedge(b.Model, "BellRoof", Vector3.new(7, 3, 3.5), at(0, b.H + 7.5, 1.75) * CFrame.Angles(0, math.pi, 0), rgb(150, 50, 40))
	local bell = MapKit.ball(b.Model, "Bell", 2, at(0, b.H + 3.6, 0), GOLD, Enum.Material.Metal)
	MapKit.tag(bell, "SchoolBell")
	flag(b.Model, at(-b.W / 2 + 3, 0, -b.D / 2 - 4).Position, rgb(60, 110, 220))
	local spots = Interiors.furnish(b, function()
		return "classroom"
	end, rng, id)
	-- the yard beside the school
	local yardC = ctx.frontLot(c, face, 34, 25)
	local model = b.Model
	if yard == "playground" then
		playground(ctx, model, yardC, math.atan2(-face.X, -face.Z), spots, true)
	elseif yard == "court" then
		court(model, CFrame.lookAt(yardC, yardC + face) * CFrame.Angles(0, math.pi / 2, 0), spots, 24, 30)
	else
		part(model, "Yard", Vector3.new(24, 0.15, 30), CFrame.new(yardC + Vector3.new(0, 0.1, 0)), rgb(90, 160, 80), Enum.Material.Grass)
		hoop(model, CFrame.lookAt(yardC + face * -12, yardC))
		for k = 0, 3 do
			local s = outSpot(facing(yardC + Vector3.new((k - 1.5) * 4, 0, 0), yardC + face * -12), if k % 2 == 0 then "hoops" else "play", "kid")
			s.Hoop = (CFrame.lookAt(yardC + face * -12, yardC) * CFrame.new(0, 9, -1.8)).Position
			table.insert(spots, s)
		end
	end
	for _, s in ipairs(spots) do
		if s.Role == "kid" then
			s.Recess = true
			s.Role = "student"
		end
	end
	local place = ctx.place(id, b, i, j, face, spots)
	place.Yard = yardC
	return place
end

function B.School(ctx, parent, i, j, rng)
	school(ctx, parent, i, j, rng, "School", 2, "playground", { rgb(206, 112, 82), rgb(246, 236, 210), rgb(40, 70, 130) })
end
function B.MiddleSchool(ctx, parent, i, j, rng)
	school(ctx, parent, i, j, rng, "MiddleSchool", 2, "yard", { rgb(120, 140, 190), rgb(240, 236, 220), rgb(40, 60, 120) })
end
function B.HighSchool(ctx, parent, i, j, rng)
	school(ctx, parent, i, j, rng, "HighSchool", 3, "court", { rgb(150, 60, 60), rgb(240, 232, 210), rgb(90, 20, 30) })
end

function B.Daycare(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "Daycare", Label = ctx.label("Daycare"), Center = ctx.frontLot(c, face, 28, -16), Face = face, W = 36, D = 28, Floors = 1, Wall = rgb(255, 214, 120), Trim = rgb(90, 170, 220), Material = Enum.Material.SmoothPlastic, Awning = { rgb(90, 170, 220), WHITE }, Roof = "gable", RoofColor = rgb(230, 90, 90) })
	local spots = Interiors.furnish(b, "daycare", rng, "Daycare")
	playground(ctx, b.Model, ctx.frontLot(c, face, 30, 22), math.atan2(-face.X, -face.Z), spots, false)
	ctx.place("Daycare", b, i, j, face, spots)
	-- two houses share the block
	ctx.houseRow(parent, i, j, rng, { { 1, -1 } })
end

-- a generic building with one room type (and an optional second building)
local function simple(ctx, parent, i, j, rng, id, spec, rooms, lateral, depth)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	spec.Name = spec.Name or id
	spec.Label = spec.Label or ctx.label(id)
	spec.Center = ctx.frontLot(c, face, depth or spec.D, lateral or 0)
	spec.Face = face
	local b = Buildings.shell(parent, spec)
	local spots = Interiors.furnish(b, rooms, rng, id)
	return ctx.place(id, b, i, j, face, spots), b
end

function B.Hotel(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "Hotel", { W = 52, D = 36, Floors = 8, Wall = rgb(236, 216, 186), Trim = rgb(150, 110, 70), Material = Enum.Material.Sandstone, DoorW = 10, SignColor = rgb(120, 30, 40), SignText = GOLD, RoofKit = { "garden", "ac" } }, { "hotel", Upper = "hotel" })
	part(b.Model, "Canopy", Vector3.new(16, 0.8, 9), b.At(0, 10.4, -b.D / 2 - 4.5), rgb(120, 30, 40), Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		deco(b.Model, "CanopyPost", Vector3.new(0.5, 10, 0.5), b.At(sx * 7.5, 5, -b.D / 2 - 8.6), GOLD, Enum.Material.Metal)
		deco(b.Model, "Topiary", Vector3.new(2, 4, 2), b.At(sx * 11, 2, -b.D / 2 - 2), MapKit.LEAVES[1], Enum.Material.Grass)
	end
	deco(b.Model, "RedCarpet", Vector3.new(6, 0.12, 9), b.At(0, 0.1, -b.D / 2 - 4.5), rgb(170, 30, 40), Enum.Material.Fabric)
end

-- Office towers: two glass towers per block, desks on every floor
function B.Offices(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local tints = { { rgb(110, 170, 210), rgb(60, 70, 86) }, { rgb(90, 190, 170), rgb(40, 60, 70) }, { rgb(150, 170, 200), rgb(70, 76, 90) } }
	for k, lateral in ipairs({ -18, 18 }) do
		local tint = tints[(k + math.abs(i) + math.abs(j)) % #tints + 1]
		local floors = if k == 1 then 12 + (math.abs(i + j) % 3) * 2 else 16
		local b = Buildings.shell(parent, { Name = "OfficeTower", Label = "🏢 " .. (if i < 0 then "West" else "East") .. " Tower " .. k, Center = ctx.frontLot(c, face, 34, lateral), Face = face, W = 34, D = 34, Floors = floors, Wall = tint[1], Trim = tint[2], WindowColor = tint[1], CurtainWall = true, DoorW = 8, RoofKit = { "antenna", if k == 1 then "tower" else "helipad" } })
		local spots = Interiors.furnish(b, function(f)
			if f == 1 then
				return "lobby"
			elseif f <= 5 then
				return "office"
			end
			return "officeLight"
		end, rng, "Office")
		ctx.place("Office", b, i, j, face, spots)
	end
end

function B.Apartments(ctx, parent, i, j, rng, name)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local colors = { rgb(214, 180, 150), rgb(170, 190, 210), rgb(206, 206, 172), rgb(190, 150, 140) }
	local b = Buildings.shell(parent, { Name = name, Label = "🏢 " .. name, Center = ctx.frontLot(c, face, 36), Face = face, W = 64, D = 36, Floors = 6, Wall = colors[(math.abs(i * 3 + j) % #colors) + 1], Trim = rgb(110, 90, 80), Material = Enum.Material.Brick, Awning = { rgb(60, 110, 90), WHITE }, RoofKit = { "garden", "solar" } })
	for f = 1, 5 do
		for k = -2, 2 do
			if k ~= 0 then
				deco(b.Model, "Balcony", Vector3.new(6, 0.5, 2.6), b.At(k * 12, f * FLOOR_H + 0.3, -b.D / 2 - 1.3), rgb(200, 200, 205), Enum.Material.Concrete)
				deco(b.Model, "BalconyRail", Vector3.new(6, 2, 0.2), b.At(k * 12, f * FLOOR_H + 1.5, -b.D / 2 - 2.5), rgb(60, 60, 66), Enum.Material.Metal)
				if (k + f) % 3 == 0 then
					deco(b.Model, "BalconyPlant", Vector3.new(1.2, 1.4, 1.2), b.At(k * 12 + 2, f * FLOOR_H + 1.3, -b.D / 2 - 1.5), MapKit.LEAVES[2], Enum.Material.Grass)
				end
			end
		end
	end
	local spots = Interiors.furnish(b, function(f)
		return if f == 1 then "lobby" else "apartment"
	end, rng, nil)
	-- the lobby is shared; each upper floor has two flats (left and right)
	local node = ctx.hookDoor(i, j, b.Door, face)
	for f = 2, b.Floors do
		for side = 0, 1 do
			local mine = {}
			for _, s in ipairs(spots) do
				if s.Floor == f then
					local x = b.CFrame:PointToObjectSpace(s.CFrame.Position).X
					if (x < 0) == (side == 0) then
						s.Building = b
						table.insert(mine, s)
					end
				end
			end
			ctx.addHome({
				Model = b.Model,
				Building = b,
				Door = b.Door,
				Inside = b.Inside,
				Address = "Apt " .. f .. (if side == 0 then "A" else "B") .. ", " .. name,
				Capacity = 4,
				Kind = "apartment",
				Node = node,
				Floor = f,
				Spots = mine,
			})
		end
	end
end

function B.Cinema(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "Cinema", { W = 56, D = 46, Floors = 2, Wall = rgb(60, 40, 80), Trim = GOLD, Material = Enum.Material.Brick, NoSign = true }, "cinema")
	local marquee = part(b.Model, "Marquee", Vector3.new(34, 6, 3), b.At(0, 13, -b.D / 2 - 1.8), rgb(30, 25, 40))
	MapKit.signText(marquee, Enum.NormalId.Front, "CINEMA - NOW SHOWING", rgb(255, 225, 120))
	for k = -8, 8 do
		local bulb = MapKit.ball(b.Model, "Bulb", 0.7, b.At(k * 2, 16.3, -b.D / 2 - 3.2), rgb(255, 230, 150), Enum.Material.Neon)
		MapKit.tag(bulb, "MarqueeBulb")
	end
	MapKit.light(marquee, rgb(255, 220, 150), 18, 1)
	for _, sx in ipairs({ -1, 1 }) do
		local poster = deco(b.Model, "Poster", Vector3.new(6, 9, 0.3), b.At(sx * 20, 6, -b.D / 2 - 0.3), rgb(30, 30, 40))
		MapKit.signText(poster, Enum.NormalId.Front, if sx < 0 then "SPACE\nPUPS" else "DINO\nDAYS", MapKit.FLOWERS[if sx < 0 then 6 else 2])
	end
end

function B.Gym(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "Gym", Label = ctx.label("Gym"), Center = ctx.frontLot(c, face, 36, -12), Face = face, W = 46, D = 36, Floors = 2, Wall = rgb(40, 45, 55), Trim = rgb(250, 120, 40), WindowColor = rgb(180, 230, 255), Material = Enum.Material.Metal, Storefront = true, Awning = { rgb(250, 120, 40), rgb(40, 45, 55) } })
	local spots = Interiors.furnish(b, "gym", rng, "Gym")
	court(b.Model, CFrame.lookAt(ctx.frontLot(c, face, 34, 26), ctx.frontLot(c, face, 34, 26) + face) * CFrame.Angles(0, math.pi / 2, 0), spots, 22, 30)
	local place = ctx.place("Gym", b, i, j, face, spots)
end

function B.Factory(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "Factory", { W = 68, D = 52, Floors = 2, Wall = rgb(150, 150, 155), Trim = rgb(90, 95, 100), Material = Enum.Material.CorrodedMetal, DoorW = 12, SignColor = rgb(50, 50, 55), WindowColor = rgb(190, 200, 170) }, "factory")
	for k = 0, 2 do
		local stackAt = b.At(-18 + k * 12, b.H + 12, b.D / 2 - 8).Position
		local stack = column(b.Model, "Smokestack", 24, 4, stackAt, rgb(120, 70, 60), Enum.Material.Brick)
		MapKit.cylinder(b.Model, "StackBand", 1, 4.4, CFrame.new(stackAt + Vector3.new(0, 10, 0)) * CFrame.Angles(0, 0, math.rad(90)), WHITE)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Color = ColorSequence.new(rgb(150, 150, 150), rgb(210, 210, 210))
		smoke.Size = NumberSequence.new(3, 10)
		smoke.Transparency = NumberSequence.new(0.35, 1)
		smoke.Lifetime = NumberRange.new(4, 7)
		smoke.Rate = 4
		smoke.Speed = NumberRange.new(4, 6)
		smoke.SpreadAngle = Vector2.new(12, 12)
		smoke.EmissionDirection = Enum.NormalId.Right
		smoke.Parent = stack
	end
	for k = 0, 5 do
		deco(b.Model, "Crate", Vector3.new(4, 4, 4), b.At(-b.W / 2 + 4 + (k % 3) * 4.5, 2 + (k // 3) * 4, -b.D / 2 - 3), rgb(170, 125, 75), Enum.Material.WoodPlanks)
	end
end

function B.Warehouse(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "Warehouse", { W = 60, D = 44, Floors = 2, Wall = rgb(170, 140, 100), Trim = rgb(110, 90, 65), Material = Enum.Material.CorrodedMetal, DoorW = 14, Roof = "gable", RoofColor = rgb(110, 115, 120) }, "warehouse")
	local truck = Streets.car(b.Model, b.At(18, 0, -b.D / 2 - 5) * CFrame.Angles(0, math.rad(90), 0), WHITE, "van")
	truck.Name = "DeliveryTruck"
end

function B.GasStation(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "GasStation", Label = ctx.label("GasStation"), Center = ctx.frontLot(c, face, 24) - face * 10, Face = face, W = 36, D = 24, Floors = 1, Wall = WHITE, Trim = rgb(230, 60, 50), Awning = { rgb(230, 60, 50), WHITE }, Storefront = true })
	local at = b.At
	local cpos = at(0, 0, -b.D / 2 - 9)
	part(b.Model, "PumpCanopy", Vector3.new(34, 1.4, 14), cpos * CFrame.new(0, 12, 0), rgb(230, 60, 50), Enum.Material.Metal)
	local canopyLight = deco(b.Model, "CanopyLight", Vector3.new(30, 0.2, 10), cpos * CFrame.new(0, 11.2, 0), rgb(250, 250, 240), Enum.Material.Neon)
	MapKit.light(canopyLight, rgb(255, 250, 240), 24, 0.8)
	for _, sx in ipairs({ -1, 1 }) do
		deco(b.Model, "CanopyPost", Vector3.new(1, 12, 1), cpos * CFrame.new(sx * 12, 6, 0), WHITE, Enum.Material.Metal)
		part(b.Model, "Pump", Vector3.new(2, 5, 2), cpos * CFrame.new(sx * 6, 2.5, 0), rgb(240, 240, 240), Enum.Material.Metal)
		deco(b.Model, "PumpScreen", Vector3.new(1.4, 1, 0.2), cpos * CFrame.new(sx * 6, 3.6, -1.05), rgb(90, 220, 130), Enum.Material.Neon)
	end
	Streets.car(b.Model, cpos * CFrame.new(-6, 0, -5) * CFrame.Angles(0, math.rad(90), 0), Streets.CAR_COLORS[2])
	local spots = Interiors.furnish(b, "garage", rng, "GasStation")
	table.insert(spots, { CFrame = facing((cpos * CFrame.new(-6, 0, -1.5)).Position, (cpos * CFrame.new(-6, 0, -5)).Position), Action = "fixcar", Role = "work", Floor = 1, Outside = true })
	local price = deco(b.Model, "PriceSign", Vector3.new(6, 8, 0.6), at(b.W / 2 - 2, 8, -b.D / 2 - 16), rgb(30, 30, 36))
	MapKit.signText(price, Enum.NormalId.Front, "GAS\n$3.99", rgb(255, 210, 80))
	ctx.place("GasStation", b, i, j, face, spots)
end

function B.Museum(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "Museum", { W = 60, D = 40, Floors = 2, Wall = rgb(236, 230, 216), Trim = rgb(200, 190, 170), Material = Enum.Material.Marble, DoorW = 10, SignColor = rgb(60, 50, 40), SignText = GOLD, Stairs = true }, { "museum", "museum" })
	for k = -3, 3 do
		if k ~= 0 then
			column(b.Model, "Column", 22, 2.2, b.At(k * 6.5, 11, -b.D / 2 - 3).Position, WHITE, Enum.Material.Marble)
		end
	end
	wedge(b.Model, "Pediment", Vector3.new(48, 5, 7), b.At(0, b.H + 2.5, -b.D / 2 - 3), rgb(236, 230, 216), Enum.Material.Marble)
	part(b.Model, "Portico", Vector3.new(48, 1, 7), b.At(0, 22.5, -b.D / 2 - 3), rgb(226, 218, 200), Enum.Material.Marble)
	for s = 0, 2 do
		part(b.Model, "Steps", Vector3.new(44 - s * 4, 0.6, 3), b.At(0, 0.3 + s * 0.6, -b.D / 2 - 7 + s * 1.6), rgb(222, 216, 206), Enum.Material.Marble)
	end
	local banner = deco(b.Model, "Banner", Vector3.new(4, 10, 0.2), b.At(-b.W / 2 + 5, 12, -b.D / 2 - 0.4), rgb(140, 40, 60), Enum.Material.Fabric)
	MapKit.signText(banner, Enum.NormalId.Front, "DINOS", GOLD)
end

function B.PostOffice(ctx, parent, i, j, rng)
	local place, b = simple(ctx, parent, i, j, rng, "PostOffice", { W = 40, D = 30, Floors = 1, Wall = rgb(220, 210, 190), Trim = rgb(40, 70, 140), Material = Enum.Material.Brick, Awning = { rgb(40, 70, 140), WHITE }, SignColor = rgb(40, 70, 140) }, "postoffice", -10)
	local box = part(b.Model, "Mailbox", Vector3.new(2, 4, 2), b.At(b.W / 2 - 3, 2, -b.D / 2 - 3), rgb(40, 70, 160), Enum.Material.Metal)
	MapKit.signText(box, Enum.NormalId.Front, "MAIL", WHITE)
	local van = Streets.car(b.Model, b.At(-b.W / 2 + 6, 0, -b.D / 2 - 6) * CFrame.Angles(0, math.rad(90), 0), rgb(240, 240, 240), "van")
	van.Name = "MailVan"
end

function B.ArcadeDiner(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local a = Buildings.shell(parent, { Name = "Arcade", Label = ctx.label("Arcade"), Center = ctx.frontLot(c, face, 32, -19), Face = face, W = 34, D = 32, Floors = 1, Wall = rgb(40, 30, 70), Trim = rgb(240, 60, 200), Storefront = true, WindowColor = rgb(200, 120, 255), SignColor = rgb(20, 10, 40), SignText = rgb(255, 120, 240), SignTrim = rgb(80, 220, 255) })
	for k = 0, 5 do
		local strip = deco(a.Model, "NeonStrip", Vector3.new(34, 0.4, 0.3), a.At(0, 12.4 - k * 0.001, -a.D / 2 - 0.5), MapKit.FLOWERS[k % #MapKit.FLOWERS + 1], Enum.Material.Neon)
		strip.Name = "NeonStrip"
		break
	end
	ctx.place("Arcade", a, i, j, face, Interiors.furnish(a, "arcade", rng, "Arcade"))
	local d = Buildings.shell(parent, { Name = "Diner", Label = ctx.label("Diner"), Center = ctx.frontLot(c, face, 30, 19), Face = face, W = 34, D = 30, Floors = 1, Wall = rgb(240, 240, 236), Trim = rgb(220, 50, 60), Storefront = true, Awning = { rgb(220, 50, 60), WHITE }, SignColor = rgb(220, 50, 60) })
	local dspots = Interiors.furnish(d, "restaurant", rng, "Diner")
	for _, s in ipairs(dspots) do
		if s.Action == "cook" then
			s.Action = "cook"
		end
	end
	ctx.place("Diner", d, i, j, face, dspots)
end

function B.CommunityCenter(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local b = Buildings.shell(parent, { Name = "CommunityCenter", Label = ctx.label("CommunityCenter"), Center = ctx.frontLot(c, face, 34, -14), Face = face, W = 44, D = 34, Floors = 1, Wall = rgb(200, 170, 130), Trim = rgb(90, 130, 90), Material = Enum.Material.WoodPlanks, Roof = "gable", RoofColor = rgb(80, 110, 80), Awning = { rgb(90, 130, 90), WHITE } })
	local spots = Interiors.furnish(b, "community", rng, "CommunityCenter")
	court(b.Model, CFrame.lookAt(ctx.frontLot(c, face, 34, 25), ctx.frontLot(c, face, 34, 25) + face) * CFrame.Angles(0, math.pi / 2, 0), spots, 22, 30)
	ctx.place("CommunityCenter", b, i, j, face, spots)
end

-- two buildings side by side on one block
local function pair(ctx, parent, i, j, rng, left, right)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	for k, spec in ipairs({ left, right }) do
		spec.Name = spec.Id
		spec.Label = ctx.label(spec.Id)
		spec.Center = ctx.frontLot(c, face, spec.D, if k == 1 then -19 else 19)
		spec.Face = face
		local b = Buildings.shell(parent, spec)
		if spec.Extra then
			spec.Extra(b)
		end
		ctx.place(spec.Id, b, i, j, face, Interiors.furnish(b, spec.Rooms, rng, spec.Id))
	end
end

function B.BakeryCafe(ctx, parent, i, j, rng)
	pair(ctx, parent, i, j, rng,
		{ Id = "Bakery", W = 34, D = 30, Floors = 2, Wall = rgb(246, 226, 190), Trim = rgb(150, 90, 50), Awning = { rgb(220, 90, 80), WHITE }, Material = Enum.Material.Brick, Storefront = true, Rooms = "bakery" },
		{ Id = "Cafe", W = 34, D = 30, Floors = 1, Wall = rgb(110, 80, 60), Trim = rgb(240, 225, 200), Awning = { rgb(40, 120, 90), rgb(240, 225, 200) }, Material = Enum.Material.Wood, Storefront = true, Rooms = "cafe", Extra = function(b)
			for k = -1, 1, 2 do
				local p = b.At(k * 9, 0, -b.D / 2 - 5)
				MapKit.disc(b.Model, "OutdoorTable", 0.25, 3.4, (p * CFrame.new(0, 3, 0)).Position, WHITE, Enum.Material.Metal)
				deco(b.Model, "TableLeg", Vector3.new(0.3, 3, 0.3), p * CFrame.new(0, 1.5, 0), rgb(60, 60, 64), Enum.Material.Metal)
				deco(b.Model, "UmbrellaPole", Vector3.new(0.3, 7, 0.3), p * CFrame.new(0, 3.5, 0), WHITE)
				local u = MapKit.cylinder(b.Model, "Umbrella", 0.6, 8, p * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(40, 120, 90), Enum.Material.Fabric)
			end
		end }
	)
end

function B.MarketPharmacy(ctx, parent, i, j, rng)
	pair(ctx, parent, i, j, rng,
		{ Id = "Shop", W = 36, D = 34, Floors = 1, Wall = rgb(236, 236, 226), Trim = rgb(60, 140, 80), Awning = { rgb(60, 140, 80), WHITE }, Material = Enum.Material.Brick, DoorW = 10, Storefront = true, Rooms = "store", Extra = function(b)
			for k = -1, 1, 2 do
				local p = b.At(k * 11, 0, -b.D / 2 - 4)
				deco(b.Model, "FruitStall", Vector3.new(6, 3, 3), p * CFrame.new(0, 1.5, 0), rgb(150, 105, 65), Enum.Material.Wood)
				for n = 0, 3 do
					MapKit.ball(b.Model, "Fruit", 1, p * CFrame.new(n * 1.3 - 2, 3.4, 0), ({ rgb(230, 50, 50), rgb(255, 170, 40), rgb(120, 200, 60), rgb(250, 220, 60) })[n + 1])
				end
			end
		end },
		{ Id = "Pharmacy", W = 32, D = 30, Floors = 2, Wall = WHITE, Trim = rgb(60, 170, 110), Awning = { rgb(60, 170, 110), WHITE }, Material = Enum.Material.SmoothPlastic, Storefront = true, Rooms = "store", Extra = function(b)
			for _, s in ipairs({ { 4, 1.2 }, { 1.2, 4 } }) do
				local cross = deco(b.Model, "GreenCross", Vector3.new(s[1], s[2], 0.3), b.At(b.W / 2 - 4, 18, -b.D / 2 - 0.4), rgb(60, 220, 120), Enum.Material.Neon)
				cross.Name = "GreenCross"
			end
		end }
	)
end

function B.LibraryRestaurant(ctx, parent, i, j, rng)
	pair(ctx, parent, i, j, rng,
		{ Id = "Library", W = 36, D = 34, Floors = 2, Wall = rgb(180, 150, 120), Trim = rgb(240, 230, 210), Material = Enum.Material.Sandstone, DoorW = 8, Rooms = "library", Extra = function(b)
			for k = -1, 1, 2 do
				column(b.Model, "Column", 10, 1.4, b.At(k * 7, 5, -b.D / 2 - 1.5).Position, WHITE, Enum.Material.Marble)
			end
		end },
		{ Id = "Restaurant", W = 34, D = 30, Floors = 1, Wall = rgb(150, 50, 45), Trim = rgb(245, 230, 200), Awning = { rgb(245, 230, 200), rgb(150, 50, 45) }, Material = Enum.Material.Brick, Storefront = true, Rooms = "restaurant" }
	)
end

-- a block of four small shops, two facing each road the block touches
local function shopBlock(ctx, parent, i, j, rng, shops)
	local c = ctx.blockCenter(i, j)
	local face = ctx.faceFor(i, j)
	local palette = { rgb(240, 200, 120), rgb(140, 200, 230), rgb(236, 150, 150), rgb(170, 216, 150), rgb(210, 180, 236), rgb(246, 236, 210) }
	local awnings = { rgb(220, 60, 70), rgb(40, 120, 200), rgb(60, 160, 90), rgb(240, 150, 40), rgb(150, 70, 190), rgb(230, 90, 150) }
	for k, id in ipairs(shops) do
		local f = if k <= 2 then face else -face
		local b = Buildings.shell(parent, { Name = id, Label = ctx.label(id), Center = ctx.frontLot(c, f, 28, if k % 2 == 1 then -18 else 18), Face = f, W = 32, D = 28, Floors = if k % 3 == 0 then 2 else 1, Wall = palette[(k + i + 6) % #palette + 1], Trim = WHITE, Awning = { awnings[(k + j + 6) % #awnings + 1], WHITE }, Material = Enum.Material.Brick, DoorW = 7, Storefront = true })
		ctx.place(id, b, i, j, f, Interiors.furnish(b, "store", rng, id))
	end
end

function B.ShopsWest(ctx, parent, i, j, rng)
	shopBlock(ctx, parent, i, j, rng, { "Mall", "ToyStore", "Electronics", "Florist" })
end
function B.ShopsEast(ctx, parent, i, j, rng)
	shopBlock(ctx, parent, i, j, rng, { "PetShop", "Bookstore", "IceCream", "Hardware" })
end

-- woods: a patch of forest with a trail and a campfire circle
function B.Woods(ctx, parent, i, j, rng)
	local c = ctx.blockCenter(i, j)
	local model = Instance.new("Model")
	model.Name = "Woods"
	model.Parent = parent
	ctx.lot(model, c, rgb(84, 132, 64), Enum.Material.Grass)
	for n = 1, 22 do
		local p = c + Vector3.new(rng:NextNumber(-34, 34), 0, rng:NextNumber(-34, 34))
		if math.abs(p.X - c.X) > 6 and (p - c).Magnitude > 9 then
			Streets.pine(model, p, rng:NextNumber(0.9, 1.5))
		end
	end
	deco(model, "Trail", Vector3.new(4, 0.14, 74), CFrame.new(c + Vector3.new(0, 0.12, 0)), rgb(150, 120, 80), Enum.Material.Ground)
	MapKit.disc(model, "FirePit", 0.6, 4, c + Vector3.new(0, 0.3, 0), rgb(90, 90, 96), Enum.Material.Slate)
	local fire = deco(model, "Fire", Vector3.new(1.4, 1.4, 1.4), CFrame.new(c + Vector3.new(0, 1, 0)), rgb(255, 140, 40), Enum.Material.Neon)
	MapKit.light(fire, rgb(255, 150, 60), 16, 1.2)
	local flames = Instance.new("Fire")
	flames.Size = 3
	flames.Heat = 5
	flames.Parent = fire
	local spots = {}
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
		MapKit.cylinder(model, "Log", 4, 1.2, facing(p + Vector3.new(0, 0.6, 0), c) * CFrame.Angles(0, math.pi / 2, 0), MapKit.WOOD, Enum.Material.Wood)
		table.insert(spots, outSpot(facing(p, c), if k % 2 == 0 then "guitar" else "sit", "visit"))
	end
	local place = ctx.outdoor("Woods" .. i .. "_" .. j, model, i, j, c + Vector3.new(0, 0, HALF - 4), Vector3.new(0, 0, 1), spots)
	local ns = if j < 0 then "North" elseif j > 0 then "South" else ""
	local ew = if i < 0 then "West" elseif i > 0 then "East" else ""
	place.Label = "🌲 " .. ns .. (if ns ~= "" and ew ~= "" then "-" else "") .. ew .. " Woods"
	place.Emoji = "🌲"
	place.Kind = "fun"
end

function B.Houses(ctx, parent, i, j, rng)
	ctx.houseRow(parent, i, j, rng, { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } })
end

-- suburbs on the edge: two big houses per block with gardens
function B.Suburb(ctx, parent, i, j, rng)
	ctx.houseRow(parent, i, j, rng, { { 0, -1 }, { 0, 1 } }, true)
end

Places.Builders = B
Places.playground = playground

return Places
