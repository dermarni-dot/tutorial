-- MenuDetail: the title-screen set's extra dressing (MenuStage). Built into the set's folder, in the set's own
-- frame (st.base: the canvas top under the boxer's feet, the lens on the +Z side), by Graphics level:
--   tier 1 (every level)  rubber tile floor, canvas weave, a hanging WCB banner, two printed posters
--   tier 2 (Medium+)      the heavy bags' swivels, chains, caps, seams and labels (they swing with the bags), a
--                         row of lockers with a round timer over them, a wall clock, a bench with a gym bag and
--                         towels, a double-end bag on its cords, the speed bag's brackets and swivel, turnbuckles
--   tier 3 (High)         pipes and conduit along the walls, floor scuffs and wall grime, a chalk bucket, a plate
--                         stack, gloves and jump ropes on hooks
-- Everything stays at the walls and behind the ropes: the boxer's spot, the space between him and the lens and
-- the key / rim / fill light paths are left as they were. DetailKit defaults: no collision, queries or touches.
--   MenuDetail.Apply(st, level)   builds the tiers the level shows (once each) and hides the ones it does not
--   MenuDetail.Step(st)           moves the bag pieces with their bags (MenuStage.Step calls it)
local DetailKit = require(script.Parent:WaitForChild("DetailKit"))

local K = DetailKit
local V3, CF, A, RAD = K.V3, K.CF, K.A, K.RAD
local M, FACE, C, rgb = K.M, K.FACE, K.C, K.rgb
local Part, Cyl, VCyl, Rod, Ball = K.Part, K.Cyl, K.VCyl, K.Rod, K.Ball

local MenuDetail = {}

local GYM_Y = -3.6 -- the gym floor (MenuStage)
local BACK, LEFT, RIGHT = -30, -34, 30 -- the inner faces of the back, left and right walls
local CEIL = GYM_Y + 30

-- a wall CFrame in set space: front (-Z) facing into the room
local function back(x, y, out)
	return CF(x, y, BACK + (out or 0)) * A(0, math.pi, 0)
end
local function left(z, y, out)
	return CF(LEFT + (out or 0), y, z) * A(0, -math.pi / 2, 0)
end
local function right(z, y, out)
	return CF(RIGHT - (out or 0), y, z) * A(0, math.pi / 2, 0)
end

------------------------------------------------------------------------
-- tiers (m = the tier's model, b = st.base: every CFrame below is set space, b * cf in the world)
------------------------------------------------------------------------
local function tier1(m, b, st)
	local floor = Part(m, "MDFloorTiles", V3(64, 0.05, 56), b * CF(-2, GYM_Y + 0.01, -2), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Texture(floor, FACE.Top, "rubberTiles", 6, 6, { Color3 = rgb(120, 96, 76), Transparency = 0.35 })
	local canvas = st.folder:FindFirstChild("Canvas")
	local weave = Part(m, "MDCanvasWeave", V3(24.8, 0.05, 24.8), b * CF(0, 0.004, 4), C.black, M.Fabric, { t = 1, shadow = false })
	K.Texture(weave, FACE.Top, "canvasWeave", 5, 5, { Color3 = canvas and canvas.Color or rgb(178, 186, 198), Transparency = 0.3 })
	-- the WCB banner on the left wall, and two printed posters
	local cloth = Part(m, "MDBanner", V3(4.4, 13, 0.08), b * left(-20, GYM_Y + 15.5, 0.15), C.ink, M.Fabric, { shadow = false })
	if not K.Decal(cloth, FACE.Front, "bannerWCB") then
		K.Sign(cloth, FACE.Front, "W\nC\nB", C.gold, C.ink, 20)
	end
	Cyl(m, "MDBannerRod", 5.0, 0.22, b * left(-20, GYM_Y + 22.15, 0.25), C.goldDeep, M.Metal)
	K.Poster(m, "posterFightNight", 3.6, 5.4, b * back(-27.5, GYM_Y + 9.5, 0.1), { text = "FIGHT\nNIGHT" }, C.black)
	K.Poster(m, "posterUndisputed", 3.6, 5.4, b * back(-3.5, GYM_Y + 6.4, 0.1), { text = "UNDISPUTED" }, C.black)
end

-- the pieces that hang on a heavy bag (relative to the bag's top: MenuDetail.Step moves them with it)
local function bagKit(m, st)
	for _, bg in ipairs(st.bags or {}) do
		bg.extra = {}
		local col = bg.bag.Color
		local function add(p, rel)
			table.insert(bg.extra, { p = p, rel = rel })
		end
		local function piece(name, size, rel, color, mat, shape)
			local p = Part(m, name, size, CF(), color, mat, { shape = shape, shadow = false })
			add(p, rel)
			return p
		end
		piece("MDSwivel", V3(0.5, 0.5, 0.5), CF(0, 1.0, 0), C.chrome, M.Metal, "Ball")
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local from, to = V3(0, 0.9, 0), V3(math.cos(a) * 0.9, 0.05, math.sin(a) * 0.9)
			local mid = (from + to) / 2
			local cf = CFrame.lookAt(mid, to) * A(0, math.pi / 2, 0)
			piece("MDBagChain", V3((to - from).Magnitude, 0.07, 0.07), cf, C.steelLight, M.Metal, "Cylinder")
		end
		piece("MDBagCap", V3(0.35, 2.36, 2.36), CF(0, -0.15, 0) * A(0, 0, math.pi / 2), col:Lerp(C.black, 0.4), M.Leather, "Cylinder")
		piece("MDBagBase", V3(0.3, 2.36, 2.36), CF(0, -5.6, 0) * A(0, 0, math.pi / 2), col:Lerp(C.black, 0.4), M.Leather, "Cylinder")
		for _, y in ipairs({ -2.0, -3.4, -4.7 }) do
			piece("MDBagSeam", V3(0.06, 2.34, 2.34), CF(0, y, 0) * A(0, 0, math.pi / 2), col:Lerp(C.black, 0.55), M.Fabric, "Cylinder")
		end
		local label = piece("MDBagLabel", V3(1.0, 1.7, 0.05), CF(0, -3.0, 1.16), C.gold, M.SmoothPlastic)
		K.Sign(label, FACE.Back, "WCB", C.ink, C.gold, 30)
	end
	MenuDetail.Step(st)
end

local function lockers(m, b)
	for i = 0, 3 do
		local cf = b * back(20 + i * 2.5, GYM_Y + 3.6, 1.0)
		Part(m, "MDLocker", V3(2.4, 7.2, 2), cf, i % 2 == 0 and rgb(40, 70, 150) or rgb(35, 60, 130), M.DiamondPlate)
		for k = 0, 2 do
			Part(m, "MDLockerVent", V3(1.6, 0.08, 0.04), cf * CF(0, 2.6 - k * 0.3, -1.01), rgb(20, 20, 26), M.SmoothPlastic, { shadow = false })
		end
		Part(m, "MDLockerHandle", V3(0.14, 0.8, 0.14), cf * CF(0.85, 0.2, -1.08), C.chrome, M.Metal, { shadow = false })
		local num = Part(m, "MDLockerNumber", V3(0.7, 0.35, 0.04), cf * CF(0, 3.2, -1.02), C.chrome, M.Metal, { shadow = false })
		K.Sign(num, FACE.Front, string.format("%02d", 11 + i), C.ink, C.chrome, 40, Enum.Font.GothamBold)
	end
	-- the round timer over the lockers
	local t = b * back(24, GYM_Y + 11.6, 0.35)
	local box = Part(m, "MDTimerBox", V3(6.4, 2.4, 0.7), t, C.ink, M.SmoothPlastic)
	local sg = K.Gui(box, FACE.Front, 30, 0)
	K.Frame(sg, { BackgroundColor3 = rgb(8, 8, 10) })
	K.Text(sg, "3:00", { TextColor3 = rgb(255, 60, 50), Font = Enum.Font.Code, Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.36, 0.1) })
	for k, col in ipairs({ rgb(60, 255, 120), rgb(255, 200, 40), rgb(255, 60, 50) }) do
		Part(m, "MDTimerLamp", V3(0.5, 0.5, 0.1), t * CF(-2.7 + (k - 1) * 0.7, 0, -0.38), col, k == 1 and M.Neon or M.SmoothPlastic, { shadow = false })
	end
end

local function clock(m, b)
	local cf = b * back(-9, GYM_Y + 14, 0.1)
	Part(m, "MDClockBody", V3(0.3, 2.6, 2.6), cf * CF(0, 0, 0.1) * A(0, math.pi / 2, 0), C.ink, M.SmoothPlastic, { shape = "Cylinder" })
	Part(m, "MDClockFace", V3(0.06, 2.3, 2.3), cf * CF(0, 0, -0.08) * A(0, math.pi / 2, 0), C.white, M.SmoothPlastic, { shape = "Cylinder", shadow = false })
	Part(m, "MDClockHour", V3(0.1, 0.6, 0.03), cf * CF(0.18, 0.2, -0.13) * A(0, 0, RAD(-40)), C.ink, M.SmoothPlastic, { shadow = false })
	Part(m, "MDClockMinute", V3(0.07, 0.9, 0.03), cf * CF(-0.25, 0.25, -0.14) * A(0, 0, RAD(50)), C.ink, M.SmoothPlastic, { shadow = false })
	Ball(m, "MDClockPin", 0.14, cf * CF(0, 0, -0.16), C.red, M.Metal, { shadow = false })
end

local function bench(m, b)
	local cf = b * left(-12, GYM_Y, 1.4)
	Part(m, "MDBenchSeat", V3(6, 0.45, 1.3), cf * CF(0, 1.4, 0), C.black, M.Leather)
	Part(m, "MDBenchSeam", V3(6.02, 0.05, 1.32), cf * CF(0, 1.36, 0), C.red, M.Fabric, { shadow = false })
	for _, x in ipairs({ -2.5, 2.5 }) do
		Part(m, "MDBenchLeg", V3(0.25, 1.1, 1.1), cf * CF(x, 0.55, 0), C.steelDark, M.Metal)
	end
	Part(m, "MDGymBag", V3(2.2, 1.0, 1.0), cf * CF(-1.4, 2.12, 0), C.black, M.Fabric, { shape = "Cylinder" })
	Part(m, "MDGymBagEnd", V3(0.08, 1.02, 1.02), cf * CF(-2.5, 2.12, 0), C.red, M.Fabric, { shape = "Cylinder", shadow = false })
	for k = 0, 2 do
		Part(m, "MDTowel", V3(1.5, 0.2, 1.0), cf * CF(1.6, 1.73 + k * 0.21, 0) * A(0, RAD(k * 7), 0), k == 1 and C.red or C.white, M.Fabric)
	end
	VCyl(m, "MDBottle", 0.8, 0.32, cf * CF(2.7, 1.62, 0.2), rgb(60, 140, 230), M.Plastic, { t = 0.2 })
end

-- a double-end bag on its floor and ceiling cords, back left behind the ropes
local function doubleEnd(m, b)
	local p = V3(-12, GYM_Y + 5.6, -21)
	Ball(m, "MDDoubleEnd", V3(1.0, 1.2, 1.0), b * CF(p), C.redDeep, M.Leather)
	Rod(m, "MDCordTop", (b * CF(p + V3(0, 0.6, 0))).Position, (b * CF(p.X, CEIL, p.Z)).Position, 0.06, C.ink, M.Rubber)
	Rod(m, "MDCordBottom", (b * CF(p - V3(0, 0.6, 0))).Position, (b * CF(p.X, GYM_Y + 0.2, p.Z)).Position, 0.06, C.ink, M.Rubber)
	Part(m, "MDFloorEye", V3(0.6, 0.2, 0.6), b * CF(p.X, GYM_Y + 0.1, p.Z), C.steelDark, M.Metal)
end

local function speedBagKit(m, b)
	-- brackets under the existing board on the right wall (MenuStage: board at x 29.8, y GYM_Y + 8.5, z -10)
	for _, z in ipairs({ -11.6, -8.4 }) do
		Part(m, "MDSpeedBracket", V3(1.6, 0.25, 0.25), b * CF(29.2, GYM_Y + 8.0, z) * A(0, 0, RAD(30)), C.steelDark, M.Metal)
	end
	Ball(m, "MDSpeedSwivel", 0.3, b * CF(29.2, GYM_Y + 8.25, -10), C.chrome, M.Metal, { shadow = false })
	Part(m, "MDSpeedRebound", V3(0.1, 0.5, 3.4), b * CF(29.5, GYM_Y + 8.75, -10), C.red, M.SmoothPlastic, { shadow = false })
end

-- turnbuckle hardware where the ropes meet the posts (MenuStage's ropes are static parts)
local function turnbuckles(m, b)
	local posts = { { -10, -6 }, { 10, -6 }, { -10, 14 }, { 10, 14 } }
	for _, p in ipairs(posts) do
		for _, h in ipairs({ 4.5, 3.5, 2.5, 1.5 }) do
			local c = V3(p[1], h, p[2])
			local dirs = { V3(-math.sign(p[1]), 0, 0) }
			if p[2] < 0 then
				table.insert(dirs, V3(0, 0, 1))
			end
			for _, d in ipairs(dirs) do
				Rod(m, "MDTurnbuckle", (b * CF(c + d * 0.3)).Position, (b * CF(c + d * 0.85)).Position, 0.14, C.chrome, M.Metal, { shadow = false })
			end
		end
	end
end

local function tier2(m, b, st)
	bagKit(m, st)
	lockers(m, b)
	clock(m, b)
	bench(m, b)
	doubleEnd(m, b)
	speedBagKit(m, b)
	turnbuckles(m, b)
end

local function tier3(m, b)
	-- pipes along the top of the back and left walls on brackets, a conduit down to a switch
	for k, y in ipairs({ CEIL - 1.6, CEIL - 2.3 }) do
		Rod(m, "MDPipe", (b * back(-33.5, y, 0.6 + k * 0.1)).Position, (b * back(29.5, y, 0.6 + k * 0.1)).Position, k == 1 and 0.42 or 0.28, k == 1 and rgb(150, 154, 160) or rgb(170, 120, 60), M.Metal)
		Rod(m, "MDPipe", (b * left(-29.5, y, 0.6 + k * 0.1)).Position, (b * left(20, y, 0.6 + k * 0.1)).Position, k == 1 and 0.42 or 0.28, k == 1 and rgb(150, 154, 160) or rgb(170, 120, 60), M.Metal)
	end
	for x = -30, 28, 9 do
		Part(m, "MDPipeBracket", V3(0.18, 1.6, 1.0), b * back(x, CEIL - 1.95, 0.45), C.steelDark, M.Metal, { shadow = false })
	end
	Rod(m, "MDConduit", (b * back(-16, CEIL - 3.2, 0.2)).Position, (b * back(-16, GYM_Y + 4.2, 0.2)).Position, 0.16, C.steelLight, M.Metal)
	Part(m, "MDSwitch", V3(0.6, 0.9, 0.25), b * back(-16, GYM_Y + 3.8, 0.12), C.white, M.Plastic, { shadow = false })
	-- scuffs on the floor, grime under the window
	local rng = Random.new(77)
	for _ = 1, 6 do
		K.Patch(m, "MDScuff", rng:NextNumber(3, 5), rng:NextNumber(3, 5), b * CF(rng:NextNumber(-30, 26), GYM_Y, rng:NextNumber(-28, -9)) * A(0, rng:NextNumber(0, 6.28), 0), "scuffs", nil, 0.35)
	end
	local grime = Part(m, "MDGrime", V3(8, 10, 0.05), b * back(7, GYM_Y + 6.3, 0.03), C.black, M.SmoothPlastic, { t = 1, shadow = false })
	K.Decal(grime, FACE.Front, "grime", { Transparency = 0.3 })
	-- a chalk bucket and a plate stack by the right wall, gloves and ropes on hooks on the left wall
	VCyl(m, "MDChalkBucket", 1.2, 1.3, b * CF(27, GYM_Y, -24), C.white, M.Plastic)
	VCyl(m, "MDChalk", 0.1, 1.1, b * CF(27, GYM_Y + 1.15, -24), rgb(250, 250, 246), M.Sand)
	for k = 0, 3 do
		VCyl(m, "MDPlate", 0.35, 2.6 - k * 0.3, b * CF(26, GYM_Y + k * 0.36, -19.5), C.black, M.Rubber)
	end
	local board = b * left(-4, GYM_Y + 6.6, 0.1)
	Part(m, "MDHookBoard", V3(6, 0.8, 0.15), board, C.woodDark, M.Wood)
	for k = -2, 2 do
		local hook = board * CF(k * 1.2, 0, -0.3)
		Part(m, "MDHook", V3(0.12, 0.12, 0.45), board * CF(k * 1.2, 0, -0.2), C.chrome, M.Metal, { shadow = false })
		if k % 2 == 0 then
			Ball(m, "MDGlove", V3(0.8, 1.0, 0.9), hook * CF(0, -0.75, 0), k == 0 and C.red or C.blue, M.Leather)
			Part(m, "MDGloveCuff", V3(0.65, 0.45, 0.7), hook * CF(0, -0.15, 0), C.white, M.Leather, { shadow = false })
		else
			Part(m, "MDRopeHandle", V3(0.18, 0.75, 0.18), hook * CF(0, -0.5, 0), C.gold, M.Plastic, { shadow = false })
			Rod(m, "MDRopeCord", (hook * CF(0, -0.9, 0)).Position, (hook * CF(0.2, -2.8, 0)).Position, 0.05, C.ink, M.Plastic, { shadow = false })
		end
	end
end

local TIERS = { tier1, tier2, tier3 }

function MenuDetail.Apply(st, level)
	if not (st and st.folder) then
		return
	end
	st.extra = st.extra or {}
	for t, fn in ipairs(TIERS) do
		local want = level >= t
		local m = st.extra[t]
		if want and not m then
			m = Instance.new("Model")
			m.Name = "MenuDetail" .. t
			local ok, err = pcall(fn, m, st.base, st)
			if not ok then
				warn("[MenuDetail] tier " .. t .. ": " .. tostring(err))
			end
			st.extra[t] = m
		end
		if m then
			m.Parent = want and st.folder or nil
		end
	end
end

-- the bag pieces follow their bag (after MenuStage.Step has swung it)
function MenuDetail.Step(st)
	for _, bg in ipairs(st.bags or {}) do
		local ex = bg.extra
		if ex and #ex > 0 and bg.bag and bg.bag.Parent then
			-- the bag's top (MenuStage: bag = bagTop * CF(0, -2.9, 0) * A(0, 0, pi / 2))
			local top = bg.bag.CFrame * A(0, 0, -math.pi / 2) * CF(0, 2.9, 0)
			for _, e in ipairs(ex) do
				if e.p.Parent then
					e.p.CFrame = top * e.rel
				end
			end
		end
	end
end

return MenuDetail
