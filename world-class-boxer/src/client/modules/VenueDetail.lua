-- VenueDetail: the fight venues' extra detail layer, built by VenueFX.Start on the fighting client only (inside
-- the arena clone, so it goes with it; nothing replicates) and gated by the Graphics level:
--   tier 1 (every level)  canvas weave on the ring, EXIT signs over doors, the tier's hanging banners (a few on
--                         Low), the suites band round the bowl (arena, stadium), the sparring room's posters,
--                         banners, mat tiles and bench
--   tier 2 (Medium+)      aisle step nosings with row letters and step lights, aisle hand rails, apron piping,
--                         ring step treads, a round-card easel, judges' table kit (bottles, name cards, pens),
--                         line-array speakers and an LED halo on the rig, tunnel drapes and LED pillars, walkway
--                         stanchions, perimeter ad boards (club), security staff, wall panels, stadium rim flags
--   tier 3 (High)         taped floor cable runs, wall sconces, the rest of the banners
-- The crowd is the server's and VenueFX's (Venues.CrowdFill scales it with the fight's importance): untouched.
-- Every piece uses DetailKit's defaults (no collision, no queries, no touches: the fight camera, follow spots and
-- FightClient's fades never see it) and keeps clear of the ring's ropes, the walkways' lanes, the cornermen's and
-- stools' corners and the camera positions. Names start with "VD" so no VenueFX / FightClient scan matches them.
--   VenueDetail.Build(arena, { venue = kind, level = 1..3 }) -> model | nil
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local VenueDetail = {}

-- the venue geometry this layer dresses (mirrors src/server/Venues.lua SPECS; tools/sim/test_worlddetail.luau
-- checks the two agree)
VenueDetail.Specs = {
	CommunityCenter = { tier = 1, size = 110, height = 24, roof = true, half = 10, ringH = 2, rows = 2, rowStart = 18, rowGap = 4.5, rowRise = 0 },
	ClubArena = { tier = 2, size = 150, height = 36, roof = true, half = 11, ringH = 3, rows = 4, rowStart = 22, rowGap = 5, rowRise = 2.2, rigY = 28 },
	Arena = { tier = 3, size = 220, height = 70, roof = true, half = 12, ringH = 4, rows = 6, rowStart = 26, rowGap = 5, rowRise = 2.5, rigY = 40 },
	Stadium = { tier = 4, size = 330, height = 90, roof = false, half = 13, ringH = 4.5, rows = 11, rowStart = 30, rowGap = 5.5, rowRise = 3.2, rigY = 52 },
	Gym = { tier = 0, size = 70, height = 22, roof = true, half = 10, ringH = 2.5, rows = 0, rowStart = 18, rowGap = 4, rowRise = 0 },
}
local SPECS = VenueDetail.Specs

local ORGS = {
	{ "WBA", rgb(20, 20, 20), rgb(255, 200, 40) },
	{ "WBC", rgb(20, 110, 55), rgb(255, 215, 90) },
	{ "IBF", rgb(140, 18, 28), rgb(255, 215, 90) },
	{ "WBO", rgb(20, 36, 110), rgb(230, 230, 235) },
}

------------------------------------------------------------------------
-- pieces (b = the arena's floor-centre CFrame: everything is placed in venue space)
------------------------------------------------------------------------
local function at(b, x, y, z)
	return b * CF(x, y, z)
end

-- EXIT signs over doors on the walls (green, glowing)
local function exitSigns(m, b, sp)
	local S = sp.size
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		for _, x in ipairs({ -S * 0.3, S * 0.3 }) do
			local cf = b * rot * CF(x, math.min(sp.height - 4, 12), S / 2 - 1.3) * A(0, math.pi, 0)
			local s = Part(m, "VDExit", V3(3.2, 1.1, 0.3), cf, C.ink, M.SmoothPlastic, { shadow = false })
			local sg = K.Gui(s, FACE.Front, 40, 0)
			K.Frame(sg, { BackgroundColor3 = rgb(20, 140, 60) })
			K.Text(sg, "EXIT", { TextColor3 = C.white, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) })
			-- the door frame under it
			Part(m, "VDDoorFrame", V3(6, 8, 0.3), cf * CF(0, -6.5, 0.1), C.steelDark, M.Metal, { shadow = false })
			Part(m, "VDDoor", V3(5.4, 7.6, 0.2), cf * CF(0, -6.6, 0.05), rgb(60, 62, 70), M.Metal, { shadow = false })
			Part(m, "VDDoorBar", V3(4.2, 0.25, 0.25), cf * CF(0, -6.9, -0.12), C.chrome, M.Metal, { shadow = false })
		end
	end
end

-- a vertical cloth banner: either the WCB banner image or a printed org / tier banner
local function banner(m, cf, w, h, kind, org)
	local cloth = Part(m, "VDBanner", V3(w, h, 0.08), cf, C.ink, M.Fabric, { shadow = false })
	if kind == "wcb" and K.Decal(cloth, FACE.Front, "bannerWCB") then
		K.Decal(cloth, FACE.Back, "bannerWCB")
	else
		for _, face in ipairs({ FACE.Front, FACE.Back }) do
			local sg = K.Gui(cloth, face, 16, 1)
			local bg = org and org[2] or C.ink
			local fg = org and org[3] or C.gold
			K.Frame(sg, { BackgroundColor3 = bg })
			K.Frame(sg, { BackgroundColor3 = fg, Size = UDim2.fromScale(0.9, 0.012), Position = UDim2.fromScale(0.05, 0.03) })
			K.Frame(sg, { BackgroundColor3 = fg, Size = UDim2.fromScale(0.9, 0.012), Position = UDim2.fromScale(0.05, 0.955) })
			if org then
				K.Text(sg, org[1], { TextColor3 = fg, Size = UDim2.fromScale(0.86, 0.16), Position = UDim2.fromScale(0.07, 0.08) })
				K.Text(sg, "WORLD\nCHAMPION", { TextColor3 = C.white, Face = "signSub", Size = UDim2.fromScale(0.86, 0.14), Position = UDim2.fromScale(0.07, 0.27) })
				-- the belt: strap and plate
				K.Frame(sg, { BackgroundColor3 = rgb(16, 16, 18), Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.52) })
				local plate = K.Frame(sg, { BackgroundColor3 = fg, Size = UDim2.fromScale(0.42, 0.13), Position = UDim2.fromScale(0.29, 0.49) })
				local cr = Instance.new("UICorner")
				cr.CornerRadius = UDim.new(0.5, 0)
				cr.Parent = plate
				K.Text(sg, "WCB", { TextColor3 = C.white, Size = UDim2.fromScale(0.6, 0.1), Position = UDim2.fromScale(0.2, 0.74) })
			else
				K.Emblem(sg, 0.1, 0.06, 0.8, 0.3)
				K.Text(sg, kind == "club" and "CITY\nCLUB" or "WCB\nBOXING", { TextColor3 = fg, Size = UDim2.fromScale(0.84, 0.36), Position = UDim2.fromScale(0.08, 0.42) })
				K.Frame(sg, { BackgroundColor3 = C.red, Size = UDim2.fromScale(0.84, 0.05), Position = UDim2.fromScale(0.08, 0.84) })
			end
		end
	end
	Cyl(m, "VDBannerRod", w + 0.6, 0.22, cf * CF(0, h / 2 + 0.12, 0), C.goldDeep, M.Metal)
	Cyl(m, "VDBannerRod", w, 0.16, cf * CF(0, -h / 2 - 0.06, 0), C.goldDeep, M.Metal)
	return cloth
end

-- the tier's banners: hung from the roof over the seats (indoor) or on masts on the bowl rim (stadium)
local function banners(m, b, sp, first, last)
	local S, H = sp.size, sp.height
	local list = {}
	if sp.tier >= 3 then
		for i, o in ipairs(ORGS) do
			table.insert(list, { kind = "org", org = o, i = i })
		end
		for i = 1, 4 do
			table.insert(list, { kind = "wcb", i = 4 + i })
		end
	else
		for i = 1, 8 do
			table.insert(list, { kind = sp.tier == 2 and (i % 2 == 0 and "club" or "wcb") or "wcb", i = i })
		end
	end
	local w, h = sp.tier >= 3 and 7 or 4.5, sp.tier >= 3 and 20 or 11
	for k = first, math.min(last, #list) do
		local e = list[k]
		local side = (k - 1) % 4
		local slot = math.floor((k - 1) / 4)
		local rot = A(0, side * math.pi / 2, 0)
		local x = (slot == 0 and -1 or 1) * S * 0.16
		local r = sp.rowStart + sp.rows * sp.rowGap + 4
		local topY
		if sp.roof then
			topY = H - 1.5
		else
			topY = math.min(H - 6, 70)
		end
		local cf = b * rot * CF(x, topY - h / 2, math.min(r + 10, S / 2 - 6)) * A(0, math.pi, 0)
		banner(m, cf, w, h, e.kind, e.org)
		if sp.roof then
			for _, sx in ipairs({ -1, 1 }) do
				Rod(m, "VDBannerCable", (cf * CF(sx * w * 0.4, h / 2 + 0.2, 0)).Position, (cf * CF(sx * w * 0.4, h / 2 + 1.5, 0)).Position, 0.06, C.steelDark, M.Metal)
			end
		else
			Rod(m, "VDBannerMast", (cf * CF(0, h / 2 + 0.3, 0.5)).Position, (cf * CF(0, -h / 2 - 8, 0.5)).Position, 0.4, C.steelDark, M.Metal)
		end
	end
end

-- the ring canvas weave texture and the apron's rolled edge
local function canvasWeave(m, b, sp, arena)
	local half, RH = sp.half, sp.ringH
	local canvas = arena and arena:FindFirstChild("Canvas")
	local p = Part(m, "VDCanvasWeave", V3(half * 2 + 5.8, 0.05, half * 2 + 5.8), at(b, 0, RH + 0.006, 0), C.black, M.Fabric, { t = 1, shadow = false })
	-- the weave image is near white: tinted to the canvas colour it only adds the texture
	K.Texture(p, FACE.Top, "canvasWeave", 6, 6, { Color3 = canvas and canvas.Color or rgb(230, 230, 236), Transparency = 0.4 })
end

-- the suites / VIP boxes band round the top of the bowl (Arena, Stadium): glass with lit windows and mullions
local function suites(m, b, sp)
	if sp.tier < 3 then
		return
	end
	local S = sp.size
	local R0 = sp.rowStart + sp.rows * sp.rowGap + 1
	local y0 = (sp.rows - 1) * sp.rowRise + 3.5
	local R1 = S / 2 - 3
	local y1 = math.min(sp.height - 10, y0 + (R1 - R0) * 0.72)
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		local w = (R1 + 2) * 2
		local cf = b * rot * CF(0, y1 + 3.2, R1 + 1.2) * A(0, math.pi, 0)
		local band = Part(m, "VDSuites", V3(w, 5, 0.4), cf, rgb(14, 16, 22), M.Glass, { refl = 0.15 })
		local sg = K.Gui(band, FACE.Front, 3, 0.3)
		local n = math.floor(w / 9)
		for k = 0, n - 1 do
			local lit = ((k * 7 + side * 3) % 5) ~= 0
			K.Frame(sg, { BackgroundColor3 = lit and rgb(255, 214, 160) or rgb(30, 34, 44), BackgroundTransparency = lit and 0.25 or 0.1, Size = UDim2.fromScale(0.9 / n, 0.6), Position = UDim2.fromScale((k + 0.05) / n, 0.2) })
		end
		Part(m, "VDSuiteSill", V3(w, 0.5, 1.4), cf * CF(0, -2.75, -0.4), C.ink2, M.Metal)
		Part(m, "VDSuiteRoofline", V3(w, 0.8, 1.2), cf * CF(0, 2.9, -0.3), C.goldDeep, M.Metal)
	end
end

-- a square LED halo hung over the ring from the rig (Arena, Stadium)
local function halo(m, b, sp)
	if sp.tier < 3 or not sp.rigY then
		return
	end
	local r = sp.half + 6
	local y = sp.rigY - 7
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		Part(m, "VDHalo", V3(r * 2, 1.2, 0.4), b * rot * CF(0, y, r), C.ink, M.Metal)
		Part(m, "VDHaloLED", V3(r * 2 - 0.4, 0.5, 0.06), b * rot * CF(0, y, r - 0.24), side % 2 == 0 and C.gold or C.red, M.Neon, { shadow = false })
		Rod(m, "VDHaloCable", (b * rot * CF(r, y + 0.6, r)).Position, (b * rot * CF(r, sp.rigY - 1, r)).Position, 0.08, rgb(25, 25, 25), M.Metal)
	end
end

-- perimeter advertising boards between the ringside tables and the first row (the club: the community hall's
-- first row sits too close to its tables, the big shows have LED barriers)
local function perimeterBoards(m, b, sp)
	if sp.tier ~= 2 or sp.rows <= 0 then
		return
	end
	local rb = sp.rowStart - 2.2
	local words = { "WCB SPORTS", "FIGHT NIGHT", "WORLD CLASS BOXING", "HANDS UP" }
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		for _, sx in ipairs({ -1, 1 }) do
			local len = rb - 8
			-- (the walkway sides leave the lane and the floor cameras free: boards only beyond them)
			local x = sx * (8 + len / 2)
			local cf = b * rot * CF(x, 0, rb) * A(0, math.pi, 0)
			local board = Part(m, "VDAdBoard", V3(len, 2.0, 0.15), cf * CF(0, 1.1, 0) * A(RAD(-12), 0, 0), C.ink, M.SmoothPlastic)
			local sg = K.Gui(board, FACE.Front, 14, 0.4)
			K.Frame(sg, { BackgroundColor3 = side % 2 == 0 and C.redDeep or C.ink })
			K.Text(sg, words[(side * 2 + (sx > 0 and 1 or 0)) % #words + 1], { TextColor3 = side % 2 == 0 and C.white or C.gold, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15) })
			Part(m, "VDAdBoardLeg", V3(len, 0.12, 1.2), cf * CF(0, 0.06, 0.4), C.steelDark, M.Metal, { shadow = false })
		end
	end
end

-- security staff at the walkway ends (simple figures in black with yellow vests)
local function security(m, b, sp)
	if sp.tier < 2 or sp.rows <= 0 then
		return
	end
	local reach = sp.size / 2 - 4
	for _, z in ipairs({ -1, 1 }) do
		for _, sx in ipairs({ -1, 1 }) do
			-- at the tunnel end of the walkway (beside the big shows' walkout stage)
			local pos = V3(sx * (sp.tier >= 3 and 12.6 or 6.4), 0, z * (reach - (sp.tier >= 3 and 6 or 2.5)))
			local cf = b * CFrame.lookAt(pos, V3(0, 0, pos.Z * 2))
			Part(m, "VDGuardLegs", V3(1.3, 2.4, 0.8), cf * CF(0, 1.2, 0), C.ink, M.Fabric)
			Part(m, "VDGuardTorso", V3(1.6, 2.2, 0.9), cf * CF(0, 3.5, 0), C.ink2, M.Fabric)
			Part(m, "VDGuardVest", V3(1.66, 1.3, 0.95), cf * CF(0, 3.7, 0), C.yellow, M.Fabric, { shadow = false })
			local vestText = Part(m, "VDGuardBack", V3(1.2, 0.5, 0.02), cf * CF(0, 3.9, 0.49), C.ink, M.SmoothPlastic, { shadow = false })
			K.Sign(vestText, FACE.Back, "SECURITY", C.ink, C.yellow, 40)
			Ball(m, "VDGuardHead", 1.1, cf * CF(0, 5.2, 0), rgb(170, 120, 90), M.SmoothPlastic)
			for _, ax in ipairs({ -1, 1 }) do
				Part(m, "VDGuardArm", V3(0.45, 2.0, 0.5), cf * CF(ax * 1.02, 3.4, 0), C.ink2, M.Fabric)
			end
		end
	end
	local _ = reach
end



local function apron(m, b, sp)
	local half, RH = sp.half, sp.ringH
	local E = half + 3.2
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		-- the rolled edge between the corners (the corner areas stay clear for the stools and cornermen; the walkway
		-- sides leave the ring steps free) and a gold band low on the skirt
		local segs = side % 2 == 0 and { { -(E - 4.5), -2.8 }, { 2.8, E - 4.5 } } or { { -(E - 4.5), E - 4.5 } }
		for _, sg in ipairs(segs) do
			local w, cx = sg[2] - sg[1], (sg[1] + sg[2]) / 2
			Part(m, "VDApronPiping", V3(w, 0.26, 0.26), b * rot * CF(cx, RH - 0.38, E + 0.12), C.ink, M.Rubber, { shadow = false })
			Part(m, "VDSkirtBand", V3(w, 0.35, 0.04), b * rot * CF(cx, 0.45, E + 0.17), C.gold, M.Fabric, { shadow = false })
		end
	end
	-- treads on the ring steps (Venues: three steps on both walkway sides)
	for _, z in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local y = i * (RH / 3)
			local zz = z * (half + 2.25 + (4 - i) * 1.5)
			Part(m, "VDStepTread", V3(3.9, 0.06, 0.3), at(b, 0, y + 0.03, zz - z * 0.6), C.gold, M.SmoothPlastic, { shadow = false })
		end
	end
end

-- aisle step nosings (row numbers on their riser), step lights, hand rails: beside the walkways on the
-- two walkway sides, where every row's stand already forms the steps
local function aisles(m, b, sp)
	if sp.rows <= 0 then
		return
	end
	for _, side in ipairs({ 0, 2 }) do
		local rot = A(0, side * math.pi / 2, 0)
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * 5.3
			for row = 0, sp.rows - 1 do
				local dist = sp.rowStart + row * sp.rowGap
				local h = row * sp.rowRise
				local topY = h > 0 and h + 0.5 or 0.05
				local nose = h > 0 and Part(m, "VDNosing", V3(0.9, 0.12, 0.25), b * rot * CF(x, topY + 0.02, dist + 0.15), C.yellow, M.SmoothPlastic, { shadow = false })
				if h > 0 then
					local plate = Part(m, "VDRowPlate", V3(0.9, 0.45, 0.05), b * rot * CF(x, topY - 0.35, dist - 0.02), C.ink, M.SmoothPlastic, { shadow = false })
					local sg = K.Gui(plate, FACE.Back, 40, 0)
					K.Text(sg, string.char(64 + row + 1), { TextColor3 = C.gold })
					Part(m, "VDStepLight", V3(0.3, 0.12, 0.05), b * rot * CF(x - sx * 0.3, topY - 0.15, dist - 0.03), rgb(80, 160, 255), M.Neon, { shadow = false })
				end
				local _ = nose
			end
			if sp.rowRise > 0 then
				local d0, d1 = sp.rowStart + sp.rowGap, sp.rowStart + sp.rows * sp.rowGap
				local y0, y1 = sp.rowRise + 0.5, (sp.rows - 1) * sp.rowRise + 0.5
				local xr = sx * 4.4
				Rod(m, "VDAisleRail", (b * rot * CF(xr, y0 + 3, d0)).Position, (b * rot * CF(xr, y1 + 3, d1 - 0.5)).Position, 0.16, C.steelLight, M.Metal)
				for row = 1, sp.rows - 1, 2 do
					local dist = sp.rowStart + row * sp.rowGap + 0.6
					local y = row * sp.rowRise + 0.5
					Rod(m, "VDRailPost", (b * rot * CF(xr, y, dist)).Position, (b * rot * CF(xr, y + 3 + (dist - d0) / (d1 - d0) * 0.0, dist)).Position, 0.14, C.steelLight, M.Metal)
				end
			end
		end
	end
end

-- a round-card easel next to the officials' table (-X side), facing the ring
local function roundCard(m, b, sp)
	local E = sp.half + 3.2
	local cf = b * CF(-(E + 2.4), 0, -7.6) * A(0, -math.pi / 2, 0)
	for _, sx in ipairs({ -1, 1 }) do
		Rod(m, "VDEaselLeg", (cf * CF(sx * 0.9, 0, 0.4)).Position, (cf * CF(sx * 0.6, 5.2, 0)).Position, 0.12, C.woodDark, M.Wood)
	end
	Rod(m, "VDEaselLeg", (cf * CF(0, 0, 1.4)).Position, (cf * CF(0, 5.0, 0.05)).Position, 0.12, C.woodDark, M.Wood)
	local card = Part(m, "VDRoundCard", V3(2.4, 1.7, 0.08), cf * CF(0, 4.2, -0.05) * A(RAD(-8), 0, 0), C.white, M.SmoothPlastic, { shadow = false })
	local sg = K.Gui(card, FACE.Front, 40, 1)
	K.Frame(sg, { BackgroundColor3 = C.white })
	K.Text(sg, "ROUND", { TextColor3 = C.ink, Size = UDim2.fromScale(0.9, 0.25), Position = UDim2.fromScale(0.05, 0.06) })
	K.Text(sg, "1", { TextColor3 = C.redDeep, Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.34) })
	Part(m, "VDEaselLedge", V3(2.6, 0.12, 0.3), cf * CF(0, 3.3, -0.1), C.woodDark, M.Wood, { shadow = false })
end

-- the judges' tables (Venues.buildRingside): bottles, name cards, pens at every seat
local function judgesKit(m, b, sp)
	local E = sp.half + 3.2
	local tables = {
		{ CFrame.lookAt(V3(-(E + 2.2), 0, 0), V3(0, 0, 0)), { -2.4, 2.4 }, { "JUDGE", "TIME" } },
		{ CFrame.lookAt(V3(E + 2.2, 0, 0), V3(0, 0, 0)), { 0 }, { "JUDGE" } },
		{ CFrame.lookAt(V3(9, 0, E + 2.2), V3(9, 0, E + 2.2) - V3(0, 0, 1)), { 0 }, { "JUDGE" } },
	}
	for _, t in ipairs(tables) do
		local cf = b * t[1]
		for i, sx in ipairs(t[2]) do
			VCyl(m, "VDBottle", 0.75, 0.3, cf * CF(sx + 1.0, 2.6, -0.5), rgb(90, 160, 230), M.Plastic, { t = 0.25 })
			VCyl(m, "VDBottleCap", 0.14, 0.2, cf * CF(sx + 1.0, 3.35, -0.5), C.white, M.Plastic)
			local tent = Part(m, "VDNameCard", V3(1.4, 0.5, 0.05), cf * CF(sx + 0.1, 2.85, -1.06) * A(RAD(-15), 0, 0), C.white, M.SmoothPlastic, { shadow = false })
			local sg = K.Gui(tent, FACE.Front, 60, 1)
			K.Text(sg, t[3][i] or "JUDGE", { TextColor3 = C.ink, Face = "signSub" })
			Part(m, "VDPen", V3(0.06, 0.06, 0.6), cf * CF(sx - 0.8, 2.62, -0.1) * A(0, RAD(30), 0), C.ink, M.SmoothPlastic, { shadow = false })
		end
	end
end

-- line-array speakers hung on the rig's corners (indoor rigs)
local function lineArrays(m, b, sp)
	if not sp.rigY then
		return
	end
	local T = sp.half + 3
	-- one array off each side truss without a walkway (the corners carry the follow spots)
	for _, c in ipairs({ { -1, 0 }, { 1, 0 } }) do
		local p = V3(c[1] * (T + 2), sp.rigY - 1.5, 0)
		local face = CFrame.lookAt(p, V3(c[1] * (T + 30), sp.rigY - 9, 0))
		local cf = b * face
		Part(m, "VDArrayFrame", V3(2.8, 0.25, 1.8), cf, C.black, M.Metal)
		for k = 0, 3 do
			local box = cf * CF(0, -0.75 - k * 1.05, 0.05 * k) * A(RAD(-3 * k), 0, 0)
			Part(m, "VDArrayBox", V3(2.6, 0.95, 1.6), box, rgb(20, 20, 22), M.Metal)
			Part(m, "VDArrayGrille", V3(2.4, 0.75, 0.04), box * CF(0, 0, -0.81), rgb(40, 40, 44), M.DiamondPlate, { shadow = false })
		end
		if sp.roof then
			Rod(m, "VDArrayChain", (cf * CF(0, 0.1, 0)).Position, Vector3.new((cf * CF(0, 0, 0)).Position.X, (b * CF(0, sp.height - 1, 0)).Position.Y, (cf * CF(0, 0, 0)).Position.Z), 0.1, rgb(25, 25, 25), M.Metal)
		end
	end
end

-- the entrance tunnels: drapes either side of the opening, LED pillars (tier 2+), stanchions along the lane start
local function tunnels(m, b, sp)
	if sp.rows <= 0 then
		return
	end
	local S = sp.size
	local reach = S / 2 - 4
	for _, z in ipairs({ -1, 1 }) do
		local col = z < 0 and rgb(230, 40, 40) or rgb(60, 110, 255)
		for _, sx in ipairs({ -1, 1 }) do
			if sp.tier >= 3 then
				-- (the big shows' walkout stage dresses its own tunnel mouth)
				break
			end
			Part(m, "VDDrape", V3(4, 14, 0.3), at(b, sx * 10.2, 7, z * (reach - 0.4)), C.ink2, M.Fabric)
			if sp.tier >= 2 and sp.tier < 3 then
				Part(m, "VDTunnelPillar", V3(1.0, 14, 1.0), at(b, sx * 8.4, 7, z * (reach - 1.2)), C.black, M.Metal)
				Part(m, "VDTunnelLED", V3(0.25, 13, 0.25), at(b, sx * 7.85, 7, z * (reach - 1.75)), col, M.Neon, { shadow = false })
			end
			-- stanchions with a rope along the lane's first stretch (outside the walkway's 6-stud lane)
			for k = 0, 2 do
				local zz = z * (reach - 4 - k * 4)
				VCyl(m, "VDStanchion", 3.0, 0.2, at(b, sx * 4.6, 0, zz), C.chrome, M.Metal)
				VCyl(m, "VDStanchionBase", 0.2, 1.0, at(b, sx * 4.6, 0, zz), C.chrome, M.Metal)
				if k < 2 then
					Rod(m, "VDStanchionRope", at(b, sx * 4.6, 2.8, zz).Position, at(b, sx * 4.6, 2.8, zz + z * -4).Position, 0.16, col:Lerp(C.black, 0.3), M.Fabric)
				end
			end
		end
	end
end

-- feet and braces on the club's steel barricades, wall panels round the hall (indoor tiers 1-3)
local function wallPanels(m, b, sp)
	if not sp.roof or sp.tier == 0 then
		return
	end
	local S = sp.size
	local n = math.floor(S / 14)
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		for k = 0, n - 1 do
			local x = -S / 2 + 7 + k * 14
			if math.abs(x) > 12 or side % 2 == 1 then
				local cf = b * rot * CF(x, math.min(sp.height * 0.45, 18), S / 2 - 1.15) * A(0, math.pi, 0)
				Part(m, "VDWallPanel", V3(11, 6, 0.3), cf, sp.tier >= 3 and rgb(20, 20, 26) or rgb(70, 64, 60), M.Fabric)
				Part(m, "VDPanelTrim", V3(11, 0.25, 0.35), cf * CF(0, 3.1, 0), sp.tier >= 3 and C.goldDeep or C.steelDark, M.Metal, { shadow = false })
			end
		end
	end
end

local function stadiumFlags(m, b, sp)
	if sp.roof then
		return
	end
	local S = sp.size
	local cols = { C.red, C.gold, C.blue, C.white }
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		for k = -2, 2 do
			local x = k * S * 0.18
			local base = b * rot * CF(x, sp.height - 14, S / 2 - 2)
			VCyl(m, "VDFlagPole", 14, 0.35, base, C.steelLight, M.Metal)
			local flag = Part(m, "VDFlag", V3(5, 3.2, 0.06), base * CF(2.6, 12.2, 0), cols[(k + side) % 4 + 1], M.Fabric, { shadow = false })
			if (k + side) % 2 == 0 then
				K.Sign(flag, FACE.Front, "WCB", C.ink, nil, 12)
				K.Sign(flag, FACE.Back, "WCB", C.ink, nil, 12)
			end
		end
	end
end

-- High: taped cable runs from the broadcast positions, wall sconces, press-row microphones
local function cables(m, b, sp)
	local E = sp.half + 3.2
	for _, c in ipairs({ { V3(-(E + 7.5), 0, 4), V3(-(E + 7.5), 0, 30) }, { V3(E + 7, 0, -5), V3(E + 7, 0, 30) }, { V3(-(E + 2), 0, -3), V3(-(E + 12), 0, -3) } }) do
		local a, z = c[1], c[2]
		Part(m, "VDCableRun", V3(math.abs(z.X - a.X) + 0.5, 0.05, math.abs(z.Z - a.Z) + 0.5), at(b, (a.X + z.X) / 2, 0.03, (a.Z + z.Z) / 2), C.ink, M.Rubber, { shadow = false })
		Part(m, "VDCableTape", V3(math.abs(z.X - a.X) + 0.7, 0.055, math.abs(z.Z - a.Z) > 1 and 0.3 or 0.3), at(b, (a.X + z.X) / 2, 0.035, (a.Z + z.Z) / 2), C.yellow, M.SmoothPlastic, { shadow = false })
	end
end

local function sconces(m, b, sp)
	if not sp.roof or sp.tier < 2 then
		return
	end
	local S = sp.size
	for side = 0, 3 do
		local rot = A(0, side * math.pi / 2, 0)
		for k = -2, 2 do
			local cf = b * rot * CF(k * S * 0.2, math.min(sp.height - 5, 24), S / 2 - 1.3) * A(0, math.pi, 0)
			Part(m, "VDSconce", V3(1.4, 0.8, 0.6), cf, C.ink2, M.Metal, { shadow = false })
			Part(m, "VDSconceGlow", V3(1.1, 0.12, 0.4), cf * CF(0, 0.45, -0.05), rgb(255, 220, 170), M.Neon, { shadow = false })
		end
	end
end

-- the sparring room (Venue "Gym"): posters, banners, a clock, a bench with bags, chalk and towels
local function gymRoom(m, b, sp)
	local S = sp.size
	local back = S / 2 - 1.1
	-- (under and between the room's own posters at x -18 / 0 / 18, y 7.5 .. 14.5)
	for i, key in ipairs({ "posterFightNight", "posterRules", "posterUndisputed", "posterChampion" }) do
		local x = ({ -25, -9, 9, 25 })[i]
		K.Poster(m, key, 3.4, 5.1, b * CF(x, 4.2, -back + 0.06) * A(0, math.pi, 0), { text = "WCB" }, C.black)
	end
	-- a static bag in the far corner, a wall clock, a bottle crate
	local bag = V3(-27, 0, -27)
	Rod(m, "VDBagChain", (b * CF(bag + V3(0, sp.height - 1, 0))).Position, (b * CF(bag + V3(0, 9.6, 0))).Position, 0.14, C.steelLight, M.Metal)
	Ball(m, "VDBagSwivel", 0.4, b * CF(bag + V3(0, 9.4, 0)), C.chrome, M.Metal)
	VCyl(m, "VDCornerBag", 5.2, 2.2, b * CF(bag + V3(0, 3.8, 0)), C.redDeep, M.Leather)
	for _, y in ipairs({ 5.5, 7.2 }) do
		VCyl(m, "VDBagSeam", 0.06, 2.24, b * CF(bag + V3(0, y, 0)), C.ink, M.Fabric)
	end
	local clock = b * CF(-back + 0.12, 15, 0) * A(0, -math.pi / 2, 0)
	Part(m, "VDClockBody", V3(0.3, 2.6, 2.6), clock * A(0, math.pi / 2, 0), C.ink, M.SmoothPlastic, { shape = "Cylinder" })
	Part(m, "VDClockFace", V3(0.06, 2.3, 2.3), clock * CF(0, 0, -0.17) * A(0, math.pi / 2, 0), C.white, M.SmoothPlastic, { shape = "Cylinder", shadow = false })
	Part(m, "VDClockHand", V3(0.1, 0.9, 0.03), clock * CF(0.2, 0.2, -0.22) * A(0, 0, RAD(-40)), C.ink, M.SmoothPlastic, { shadow = false })
	Part(m, "VDCrate", V3(2.2, 0.7, 1.5), b * CF(-28, 0.35, 20), C.blueDeep, M.Plastic)
	for i = 0, 3 do
		VCyl(m, "VDCrateBottle", 0.8, 0.32, b * CF(-28.75 + i * 0.5, 0.45, 20), rgb(60, 140, 230), M.Plastic, { t = 0.2 })
	end
	banner(m, b * CF(-back + 0.1, 12, -22) * A(0, -math.pi / 2, 0), 3.6, 9, "wcb")
	banner(m, b * CF(-back + 0.1, 12, 22) * A(0, -math.pi / 2, 0), 3.6, 9, "wcb")
	local tile = Part(m, "VDMatTiles", V3(S - 4, 0.05, S - 4), at(b, 0, 0.02, 0), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Texture(tile, FACE.Top, "rubberTiles", 6, 6, { Color3 = rgb(110, 90, 70), Transparency = 0.55 })
	-- a bench along the right wall with a gym bag, towels and a chalk bucket
	local bench = b * CF(back - 1.2, 0, 10) * A(0, math.pi / 2, 0)
	Part(m, "VDBenchSeat", V3(6, 0.45, 1.3), bench * CF(0, 1.4, 0), C.black, M.Leather)
	for _, x in ipairs({ -2.5, 2.5 }) do
		Part(m, "VDBenchLeg", V3(0.25, 1.1, 1.1), bench * CF(x, 0.55, 0), C.steelDark, M.Metal)
	end
	Part(m, "VDGymBag", V3(2.2, 1.0, 1.0), bench * CF(-1.4, 2.12, 0), C.redDeep, M.Fabric, { shape = "Cylinder" })
	for k = 0, 2 do
		Part(m, "VDTowel", V3(1.5, 0.2, 1.0), bench * CF(1.5, 1.73 + k * 0.21, 0), k == 1 and C.red or C.white, M.Fabric)
	end
	VCyl(m, "VDChalkBucket", 1.2, 1.3, bench * CF(3.8, 0, 0.6), C.white, M.Plastic)
	VCyl(m, "VDChalk", 0.1, 1.1, bench * CF(3.8, 1.15, 0.6), rgb(250, 250, 246), M.Sand)
end

------------------------------------------------------------------------
-- build
------------------------------------------------------------------------
function VenueDetail.Build(arena, opts)
	opts = opts or {}
	local kind = opts.venue or arena:GetAttribute("Venue")
	local sp = SPECS[kind]
	if not sp then
		return nil
	end
	local anchors = arena:FindFirstChild("Anchors")
	local rc = anchors and anchors:FindFirstChild("RingCenter")
	if not rc then
		return nil
	end
	local level = math.clamp(math.floor(tonumber(opts.level) or 3), 1, 3)
	local b = rc.CFrame * CF(0, -sp.ringH, 0) -- the floor under the ring's centre, in the arena's frame
	local m = Instance.new("Model")
	m.Name = "VenueDetail"
	-- (opts.tick: called after every piece - VenueFX's time-sliced build yields there; the model is parented in whole)
	local tick = type(opts.tick) == "function" and opts.tick or nil
	local function run(fn, ...)
		local ok, err = pcall(fn, m, b, sp, ...)
		if not ok then
			warn("[VenueDetail] " .. tostring(kind) .. ": " .. tostring(err))
		end
		if tick then
			tick()
		end
	end
	-- tier 1
	run(canvasWeave, arena)
	run(suites)
	if sp.tier >= 1 then
		run(exitSigns)
		run(banners, 1, level == 1 and 2 or 4)
	end
	if sp.tier == 0 and level >= 1 then
		run(gymRoom)
	end
	-- tier 2
	if level >= 2 then
		run(apron)
		if sp.tier >= 1 then
			run(aisles)
			run(roundCard)
			run(judgesKit)
			run(lineArrays)
			run(tunnels)
			run(wallPanels)
			run(stadiumFlags)
			run(halo)
			run(perimeterBoards)
			run(security)
		end
	end
	-- tier 3
	if level >= 3 and sp.tier >= 1 then
		run(banners, 5, 8)
		run(cables)
		run(sconces)
	end
	m.Parent = arena
	return m
end

return VenueDetail
