--!nocheck
-- tools/sim/test_punchanim.luau: the punches' arm motion and the stance's life, through the REAL client Animator
-- (src/client/Animator.client.lua and its Anim* modules) on two plain R15 block rigs (no cosmetics: the joints are
-- what is measured), on a virtual clock whose frame times wander (30 and 60 fps, +-35 %, a hitch now and then).
-- Every frame the parts are solved from the Motor6D Transforms the Animator wrote and the punching arm is measured in
-- the puncher's UpperTorso frame: the shoulder's swing, the elbow's bend (0 = straight; the LE joint's own pitch
-- for hyperextension), the wrist's flex (the hand's axis against the forearm's, the corkscrew twist about the
-- forearm left out), the fist's spot against the guard spot it left from.
--   per punch (jab, cross, lead / rear hook, uppercut, overhand; head and body) at each frame timing:
--     * no overshoot: the elbow opens and the shoulder swings no more than a few degrees past where they are at contact
--     * the elbow never hyperextends (LE pitch never negative) and locks just short of straight on a straight
--     * the wrist stays aligned (no flex beyond a few degrees)
--     * hooks land with the elbow at about 90 degrees, the upper arm about level
--     * the uppercut is driven from the legs: the pelvis rises into contact
--     * the crosses and hooks turn the hips and the waist into the punch
--     * the off hand stays at the guard (it may tuck tighter, never drop or wander)
--     * the fist is back at the guard by the end of the spec's recovery (Combos.Recovery: windup x 1.9) and then
--       still: no droop, no bounce, no ringing
--   the stance (no punches) and the town idle: the secondary motion (breathing, weight shift, the head's lag, the
--   guard's bounce) is there but small, and smooth (no frame-to-frame jitter)
--   lune run tools/sim/test_punchanim.luau [--report] [--src DIR] (another commit's src: the "before" numbers)
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local ltask = require("@lune/task")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local deg = math.deg

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k = a[i]
		if k == "--report" then
			args.report = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local REPORT = args.report == true

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local root = Host.FindRoot()
local srcDir = args.src or (root .. "/src")
local E = FE.new()
local VT = 1000
local fakeOs = setmetatable({ clock = function()
	return VT
end }, { __index = os })
local RaycastParams = { new = function()
	return { FilterDescendantsInstances = {} }
end }
local H = Host.new({ root = root, src = srcDir, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace, os = fakeOs,
	RaycastParams = RaycastParams, OverlapParams = RaycastParams, time = function()
		return VT
	end } })
E.install(H)

-- the floor at Y = 0
local floorPart = E.new("Part", E.workspace)
floorPart.Name = "Floor"
floorPart.Size = Vector3.new(200, 1, 200)
floorPart.CFrame = CFrame.new(0, -0.5, 0)
floorPart.Anchored = true
E.workspace.Raycast = function(_, origin, dir)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 and dir.Y < 0 then
		local k = origin.Y / -dir.Y
		return { Position = origin + dir * k, Normal = Vector3.new(0, 1, 0), Instance = floorPart, Material = roblox.Enum.Material.Plastic,
			Distance = (dir * k).Magnitude }
	end
	return nil
end
E.workspace.GetPartBoundsInRadius = function()
	return {}
end
E.workspace.GetPartBoundsInBox = function()
	return {}
end
E.workspace.GetPartsInPart = function()
	return {}
end
E.camera.WorldToViewportPoint = function()
	return Vector3.new(400, 300, 5), true
end
E.camera.ViewportSize = roblox.Vector2.new(800, 600)
E.camera.FieldOfView = 70
E.camera.CFrame = CFrame.new(0, 5, 14)

------------------------------------------------------------------------
-- the rig: the R15 joints of v9_anim.luau's tier-3 Athletic boxer as Builder.Cosmetics leaves it (part sizes and
-- rig attachments measured off it; plain blocks here - the joints are what is measured) and the engine's joint solve
------------------------------------------------------------------------
local BLOCK = {
	UpperTorso = { size = { 2.5445, 2.4858, 0.8836 }, att = { NeckRigAttachment = { 0, 1.1395, -0.0163 }, WaistRigAttachment = { 0, -0.9549, -0.0163 },
		LeftShoulderRigAttachment = { -1.0215, 0.7702, -0.0163 }, RightShoulderRigAttachment = { 1.0215, 0.7702, -0.0163 } } },
	LowerTorso = { size = { 1.4231, 1.2043, 0.8555 }, att = { WaistRigAttachment = { 0, 0.25, -0.0288 }, LeftHipRigAttachment = { -0.3977, -0.2736, -0.0288 },
		RightHipRigAttachment = { 0.3977, -0.2736, -0.0288 }, RootRigAttachment = { 0, -0.0118, -0.0288 } } },
}
for _, side in ipairs({ "Left", "Right" }) do
	local sx = side == "Left" and 1 or -1
	BLOCK[side .. "UpperArm"] = { size = { 0.7121, 1.5083, 0.7134 }, att = { [side .. "ShoulderRigAttachment"] = { -0.0066 * sx, 0.4103, 0.0111 },
		[side .. "ElbowRigAttachment"] = { -0.0066 * sx, -0.5076, 0.0111 } } }
	BLOCK[side .. "LowerArm"] = { size = { 0.505, 1.3262, 0.5285 }, att = { [side .. "ElbowRigAttachment"] = { -0.0016 * sx, 0.419, 0.0012 },
		[side .. "WristRigAttachment"] = { -0.0016 * sx, -0.511, 0.0012 } } }
	BLOCK[side .. "Hand"] = { size = { 0.3213, 0.6094, 0.5465 }, att = { [side .. "WristRigAttachment"] = { -0.0087 * sx, 0.1638, 0.0458 } } }
	BLOCK[side .. "UpperLeg"] = { size = { 0.6185, 1.8051, 0.7119 }, att = { [side .. "HipRigAttachment"] = { 0.0048 * sx, 0.5805, -0.0125 },
		[side .. "KneeRigAttachment"] = { 0.0048 * sx, -0.668, -0.0125 } } }
	BLOCK[side .. "LowerLeg"] = { size = { 0.4529, 1.6306, 0.5042 }, att = { [side .. "KneeRigAttachment"] = { 0, 0.5807, -0.0155 },
		[side .. "AnkleRigAttachment"] = { 0, -0.5442, -0.0155 } } }
	BLOCK[side .. "Foot"] = { size = { 0.3871, 0.4682, 0.8156 }, att = { [side .. "AnkleRigAttachment"] = { 0, 0.0636, 0.0759 } } }
end
local HEAD = 0.9269
local HIP_HEIGHT = 1.9329
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" }, Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" }, RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" }, RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" }, RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" }, RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" }, RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" }, RightAnkle = { "RightLowerLeg", "RightFoot" },
}
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end
local function solve(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" then
			table.insert(motors, d)
		end
	end
	local done = { [hrp] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(motors) do
			if j.Part0 and j.Part1 and done[j.Part0] and not done[j.Part1] then
				j.Part1.CFrame = j.Part0.CFrame * j.C0 * j.Transform * j.C1:Inverse()
				done[j.Part1] = true
				progress = true
			end
		end
	end
end
local STATE = { Running = roblox.Enum.HumanoidStateType.Running }
local function newRig(name, at)
	local model = E.new("Model")
	model.Name = name
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.AssemblyLinearVelocity = Vector3.zero
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(pname, size, atts)
		local p = E.new("MeshPart", model)
		p.Name = pname
		p.Size = size
		p.Color = roblox.Color3.new(1, 1, 1)
		local o = E.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = size
		for an, pos in pairs(atts) do
			local a = E.new("Attachment", p)
			a.Name = an
			a.Position = pos
			local op = E.new("Vector3Value", a)
			op.Name = "OriginalPosition"
			op.Value = pos
		end
		return p
	end
	for pname, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = v3(pos)
		end
		addPart(pname, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(HEAD, HEAD, HEAD), { NeckRigAttachment = Vector3.new(0, -HEAD / 2, 0) })
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		m.Transform = CFrame.new()
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = HIP_HEIGHT
	hum.Sit = false
	hum.MoveDirection = Vector3.zero
	hum.WalkSpeed = 16
	hum.GetState = function()
		return STATE.Running
	end
	hrp.CFrame = at
	solve(model)
	model.Parent = E.workspace
	return model, hum
end

------------------------------------------------------------------------
-- the Animator, on PreSimulation
------------------------------------------------------------------------
local CS = E.CollectionService
local player = E.localPlayer
local playersProps = H.Service("Players")._props
playersProps.GetPlayers = function()
	return { player }
end
playersProps.GetPlayerFromCharacter = function(_, m)
	return (m ~= nil and m == player.Character) and player or nil
end
player.CharacterAdded = FE.Signal()
local PreSim = FE.Signal()
H.Service("RunService")._props.PreSimulation = PreSim
do
	local env = table.clone(H.globals)
	env.script = { Parent = H.client.Parent, Name = "Animator" }
	local chunk = luau.load(fs.readFile(srcDir .. "/client/Animator.client.lua"), { debugName = "Animator.client.lua", environment = env })
	ltask.spawn(chunk)
	local function rigsReady()
		local c = H.cache[H.files.AnimRig]
		return c ~= nil and type(c.value) == "table" and c.value.rigs ~= nil
	end
	local guard = 0
	while not rigsReady() and guard < 600 do
		guard += 1
		ltask.wait()
	end
	assert(rigsReady(), "test_punchanim: the Animator did not finish loading")
end
local Combos = H.require("Combos")
local Config = H.require("Config")

-- frame timings: wandering frame times (+-35 %, no period) with a 2.5x hitch every 53 frames
local function timing(fps)
	local n = 0
	return function()
		n += 1
		local h = (math.sin(n * 12.9898 + 78.233) * 43758.5453) % 1
		local dt = (1 / fps) * (0.65 + 0.7 * h)
		if n % 53 == 0 then
			dt = 2.5 / fps
		end
		return dt
	end
end
local function frame(models, dt)
	VT += dt
	PreSim:Fire(dt)
	for _, m in ipairs(models) do
		solve(m)
	end
	ltask.wait()
end

------------------------------------------------------------------------
-- measurements (the puncher's UpperTorso frame)
------------------------------------------------------------------------
local function angleBetween(a, b)
	return deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end
local function armSample(model, s)
	local side = s == "L" and "Left" or "Right"
	local ut = model:FindFirstChild("UpperTorso").CFrame
	local ua = model:FindFirstChild(side .. "UpperArm").CFrame
	local la = model:FindFirstChild(side .. "LowerArm").CFrame
	local hd = model:FindFirstChild(side .. "Hand").CFrame
	local el = model:FindFirstChild(side .. "LowerArm"):FindFirstChild(side .. "Elbow")
	local ex = el.Transform:ToEulerAnglesXYZ()
	-- (the wrist's flex: the hand's long axis against the forearm's; the corkscrew turns about that axis and is no flex)
	local flex = angleBetween(la.UpVector, hd.UpVector)
	local upDir = ut:VectorToObjectSpace(-ua.UpVector)
	local fist = ut:PointToObjectSpace(hd.Position)
	local elbowP = ut:PointToObjectSpace(ua:PointToWorldSpace(model:FindFirstChild(side .. "UpperArm"):FindFirstChild(side .. "ElbowRigAttachment").Position))
	local shoulder = ut:PointToObjectSpace(ua:PointToWorldSpace(model:FindFirstChild(side .. "UpperArm"):FindFirstChild(side .. "ShoulderRigAttachment").Position))
	return { shoulder = shoulder, bend = angleBetween(ua.UpVector, la.UpVector), lePitch = deg(ex), wrist = flex, up = upDir, fist = fist, elbow = elbowP,
		-- (the upper arm's elevation and the elbow's height under the fist in the world: how level a hook reads)
		elev = deg(math.asin(math.clamp(-ua.UpVector.Y, -1, 1))),
		fistUp = hd.Position.Y - ua:PointToWorldSpace(model:FindFirstChild(side .. "UpperArm"):FindFirstChild(side .. "ShoulderRigAttachment").Position).Y,
		elbowDy = ua:PointToWorldSpace(model:FindFirstChild(side .. "UpperArm"):FindFirstChild(side .. "ElbowRigAttachment").Position).Y - hd.Position.Y }
end

local function rigOf(model)
	return H.require("AnimRig").rigs[model]
end
-- the stance's glove target this frame (rig.guardL / guardR, standard UpperTorso units), in the UpperTorso's studs
local function guardSpot(s, model)
	local rg = rigOf(model)
	local gt = rg and (s == "L" and rg.guardL or rg.guardR)
	local sc = rg and rg.geo and rg.geo.utScale or Vector3.one
	if not gt then
		return Vector3.zero
	end
	return Vector3.new(gt[1] * sc.X, gt[2] * sc.Y, gt[3] * sc.Z)
end
local ROOT_Y = HIP_HEIGHT + 1
local A_AT = CFrame.new(0, ROOT_Y, 2)
local B_AT = CFrame.new(0, ROOT_Y, -2) * CFrame.Angles(0, math.pi, 0)
-- (the gap, root to root, a punch is thrown at: the straights at their range, the hooks and uppercuts closer -
-- Config.Punches' range shares of the jab's)
local GAP = { jab = 4.0, cross = 4.0, overhand = 4.0, leadhook = 3.5, rearhook = 3.5, uppercut = 3.3 }
local a = newRig("BoxerA", A_AT)
local b = newRig("BoxerB", B_AT)
for _, m in ipairs({ a, b }) do
	m:SetAttribute("Guard", "stance")
	m:SetAttribute("Style", "BoxerPuncher")
	m:SetAttribute("Stam", 1)
	m:SetAttribute("Daze", 0)
	CS:AddTag(m, "Fighter")
end

local PUNCHES = {
	{ id = "jab", act = "jab|L|head|%.2f|0.80", kind = "jab", hand = "L" },
	{ id = "cross", act = "cross|R|head|%.2f|0.90", kind = "cross", hand = "R" },
	{ id = "leadhook", act = "leadhook|L|head|%.2f|0.90", kind = "leadhook", hand = "L" },
	{ id = "rearhook", act = "rearhook|R|head|%.2f|0.90", kind = "rearhook", hand = "R" },
	{ id = "uppercut", act = "uppercut|R|head|%.2f|0.90", kind = "uppercut", hand = "R" },
	{ id = "overhand", act = "overhand|R|head|%.2f|0.90", kind = "overhand", hand = "R" },
	{ id = "bodyjab", act = "jab|L|body|%.2f|0.80", kind = "jab", hand = "L" },
	{ id = "bodyhook", act = "leadhook|L|body|%.2f|0.90", kind = "leadhook", hand = "L" },
}
local FPS = { 60, 30 }
local results = {}

local function settle(tick, secs)
	local t = 0
	while t < secs do
		local dt = tick()
		t += dt
		frame({ a, b }, dt)
	end
end

local actId = 0
for _, fps in ipairs(FPS) do
	local tick = timing(fps)
	settle(tick, 1.5)
	for rep = 1, 2 do
		for _, pd in ipairs(PUNCHES) do
			-- (a fresh stance between punches: well past the last one's recovery)
			b:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(0, ROOT_Y, 2 - GAP[pd.kind]) * CFrame.Angles(0, math.pi, 0)
			settle(tick, 1.0)
			local w = Config.Punches[pd.kind].windup
			local busy = Combos.Recovery(w)
			local s, o = pd.hand, pd.hand == "L" and "R" or "L"
			local m0, n0 = armSample(a, s), armSample(a, o)
			local e0, f0 = m0.fist - guardSpot(s, a), n0.fist - guardSpot(o, a)
			local lt0 = a:FindFirstChild("LowerTorso").CFrame
			actId += 1
			a:SetAttribute("Act", string.format(pd.act, w))
			a:SetAttribute("ActId", actId)
			local rows = {}
			local t = 0
			while t < busy + 0.9 do
				local dt = tick()
				t += dt
				frame({ a, b }, dt)
				local m = armSample(a, s)
				local off = armSample(a, o)
				local lt = a:FindFirstChild("LowerTorso").CFrame
				local rel = lt0:ToObjectSpace(lt)
				local _, hipYaw = rel:ToEulerAnglesYXZ()
				local wrel = lt:ToObjectSpace(a:FindFirstChild("UpperTorso").CFrame)
				local _, waistYaw = wrel:ToEulerAnglesYXZ()
				if args.dbg == pd.id and rep == (tonumber(args.rep) or 1) and fps == (tonumber(args.fps) or 60) then
					local rg = rigOf(a)
					local rt = a:FindFirstChild("LowerTorso"):FindFirstChild("Root").Transform
					local pu = rg.pun[s]
					print(string.format("dbg t %.3f pun %s fidget %s act %s armDrop %.3f drop %.3f rootT %+.3f %+.3f %+.3f lunge %s swingL %s swingR %s", t,
						tostring(pu ~= nil), tostring(rg.fidget and rg.fidget.kind), tostring(rg.act and rg.act.kind), rg.sx and (rg.sx[11] + rg.sx[12]) or 0,
						rg.loco.drop or -1, rt.X, rt.Y, rt.Z, tostring(pu and pu.lunge), tostring(rg.foot.L.swing), tostring(rg.foot.R.swing)))
				end
				-- (the fist against the stance's own guard spot this frame, less where it sat on it before the punch: the
				-- guard's own life - its bounce, breathing, the hands' circles - is not the punch's)
				table.insert(rows, { t = t, dt = dt, m = m, off = off, e = m.fist - guardSpot(s, a) - e0, f = off.fist - guardSpot(o, a) - f0, gs = guardSpot(o, a),
					pelvisY = lt.Y - lt0.Y, hipYaw = deg(hipYaw), waistYaw = deg(waistYaw) })
			end
			table.insert(results, { id = pd.id, kind = pd.kind, fps = fps, rep = rep, w = w, busy = busy, m0 = m0, rows = rows })
		end
	end
end

------------------------------------------------------------------------
-- the numbers per punch
------------------------------------------------------------------------
local function at(rows, tt)
	local best, bd = rows[1], math.huge
	for _, r in ipairs(rows) do
		local d = math.abs(r.t - tt)
		if d < bd then
			best, bd = r, d
		end
	end
	return best
end
local summary = {}
for _, res in ipairs(results) do
	local rows, w = res.rows, res.w
	local c = at(rows, w)
	local ext = function(m)
		return (m.fist - m.shoulder).Magnitude
	end
	-- overshoot (contact .. contact + 0.07 s: the contact hold and the first frames home): the elbow opening past its bend at contact,
	-- the fist reaching further from the shoulder than at contact, the upper arm swinging on further from its guard
	-- line than at contact
	local minBend, maxExt, maxSwing = c.m.bend, ext(c.m), angleBetween(c.m.up, res.m0.up)
	local peakBendT, peakBend = 0, -math.huge
	local maxWrist, minLE = 0, math.huge
	local offDev, offDrop = 0, 0
	local riseMax, hipMax, waistMax, lowMin = 0, 0, 0, 0
	for _, r in ipairs(rows) do
		local m = r.m
		if r.t >= w - 1e-6 and r.t <= w + 0.07 then
			minBend = math.min(minBend, m.bend)
			maxExt = math.max(maxExt, ext(m))
			maxSwing = math.max(maxSwing, angleBetween(m.up, res.m0.up))
		end
		if r.t <= w + 0.15 and ext(m) > peakBend then
			peakBend = ext(m)
		end
		if r.t <= w + 0.02 then
			lowMin = math.min(lowMin, r.pelvisY)
			riseMax = math.max(riseMax, r.pelvisY - lowMin)
			hipMax = math.max(hipMax, math.abs(r.hipYaw))
			waistMax = math.max(waistMax, math.abs(r.waistYaw))
		end
		maxWrist = math.max(maxWrist, m.wrist)
		minLE = math.min(minLE, m.lePitch)
		-- (the off hand may tuck in tighter to the chin while the other is out - back and in - never drop or wander)
		offDev = math.max(offDev, r.f.Magnitude)
		offDrop = math.max(offDrop, -r.f.Y)
	end
	-- (on time: the first frame the fist is within 0.03 studs of its farthest from the shoulder)
	for _, r in ipairs(rows) do
		if ext(r.m) >= peakBend - 0.03 then
			peakBendT = r.t
			break
		end
	end
	local bendOver = c.m.bend - minBend
	local extOver = maxExt - ext(c.m)
	local swingOver = maxSwing - angleBetween(c.m.up, res.m0.up)
	-- back at the guard by the spec's recovery, then still: the largest offset after it, and the reversals of its motion
	local backD = at(rows, res.busy).e.Magnitude
	local after, rev, lastV, prevE = 0, 0, nil, nil
	-- (over the 0.45 s after it: later the stance's own fidgets move the guard spot)
	for _, r in ipairs(rows) do
		if r.t >= res.busy and r.t <= res.busy + 0.45 then
			after = math.max(after, r.e.Magnitude)
			if prevE then
				local v = (r.e - prevE) * ((1 / 60) / r.dt)
				if v.Magnitude > 0.01 then
					if lastV and v:Dot(lastV) < 0 then
						rev += 1
					end
					lastV = v
				end
			end
			prevE = r.e
		end
	end
	-- the droop: how far the fist sinks on the way home (after the contact hold) under both the spot it landed on and
	-- its guard spot - a body shot comes up from low, an uppercut down from the chin; neither hangs under them
	local droop = 0
	local low = math.min(c.e.Y, 0)
	for _, r in ipairs(rows) do
		if r.t > w + 0.05 then
			droop = math.max(droop, low - r.e.Y)
		end
	end
	local sm = { id = res.id, kind = res.kind, fps = res.fps, rep = res.rep, contactBend = c.m.bend, bendOver = bendOver, extOver = extOver,
		swingOver = swingOver, lateT = peakBendT - w, wrist = maxWrist, minLE = minLE, offDev = offDev, offDrop = offDrop, backD = backD, after = after,
		rev = rev, droop = droop, elev = c.m.elev, elbowDy = c.m.elbowDy, rise = riseMax, hip = hipMax, waist = waistMax }
	table.insert(summary, sm)
	if REPORT then
		print(string.format(
			"%-9s %2dfps r%d bend@hit %5.1f open+ %4.1f ext+ %4.2f swing+ %4.1f late %+.3f wrist %4.1f LEmin %5.1f off %4.2f/%4.2f back %4.2f after %4.3f rev %d droop %4.2f elev %5.1f elbowDy %+5.2f rise %4.2f hip %4.1f waist %4.1f",
			res.id, res.fps, res.rep, sm.contactBend, sm.bendOver, sm.extOver, sm.swingOver, sm.lateT, sm.wrist, sm.minLE, sm.offDev, sm.offDrop, sm.backD,
			sm.after, sm.rev, sm.droop, sm.elev, sm.elbowDy, sm.rise, sm.hip, sm.waist))
	end
	if args.dump == res.id and res.rep == (tonumber(args.rep) or 1) and res.fps == (tonumber(args.fps) or 60) then
		for _, r in ipairs(rows) do
			print(string.format("  t %.3f dt %.3f bend %5.1f up %5.2f fist %+.2f %+.2f %+.2f elbow %+.2f %+.2f %+.2f elev %5.1f e %+.2f %+.2f %+.2f f %+.2f %+.2f %+.2f pel %+.3f hip %5.1f waist %5.1f gs %+.2f %+.2f %+.2f",
				r.t, r.dt, r.m.bend, r.m.fistUp, r.m.fist.X, r.m.fist.Y, r.m.fist.Z, r.m.elbow.X, r.m.elbow.Y, r.m.elbow.Z, r.m.elev, r.e.X, r.e.Y, r.e.Z,
				r.f.X, r.f.Y, r.f.Z, r.pelvisY, r.hipYaw, r.waistYaw, r.gs.X, r.gs.Y, r.gs.Z))
		end
	end
end

for _, sm in ipairs(summary) do
	local tag = string.format("%s %dfps #%d", sm.id, sm.fps, sm.rep)
	-- (the shoulder's swing past contact is printed, not capped: the trunk's follow-through turns on while the fist rests
	-- on the spot it hit, and the arm turns back against it in the torso's frame)
	local body = sm.id:find("^body") ~= nil
	check(tag .. string.format(": no overshoot past contact (elbow opens %.1f deg, fist %.2f studs further; shoulder %.1f deg)", sm.bendOver, sm.extOver,
		sm.swingOver), sm.bendOver <= (body and 8 or 4) and sm.extOver <= 0.06)
	check(tag .. string.format(": extended on time (the fist reaches out %.3f s after contact)", sm.lateT), sm.lateT <= 0.04)
	check(tag .. string.format(": the elbow never hyperextends (LE pitch min %.1f)", sm.minLE), sm.minLE >= -0.5)
	check(tag .. string.format(": the wrist stays aligned (flex max %.1f)", sm.wrist), sm.wrist <= 6)
	check(tag .. string.format(": the off hand stays at the guard (moves %.2f, drops %.2f)", sm.offDev, sm.offDrop), sm.offDev <= 0.4 and sm.offDrop <= 0.1)
	check(tag .. string.format(": back at the guard by the recovery (%.2f studs off)", sm.backD), sm.backD <= 0.12)
	check(tag .. string.format(": still after it (%.3f studs, %d reversals)", sm.after, sm.rev), sm.after <= 0.12 and sm.rev <= 1)
	check(tag .. string.format(": no droop on the way home (%.2f under the guard)", sm.droop), sm.droop <= 0.12)
	if sm.kind == "jab" or sm.kind == "cross" then
		if not sm.id:find("^body") then
			check(tag .. string.format(": locks just short of straight (bend at contact %.1f)", sm.contactBend), sm.contactBend >= 3 and sm.contactBend <= 30)
		end
	end
	if sm.kind == "leadhook" or sm.kind == "rearhook" then
		if not sm.id:find("^body") then
			check(tag .. string.format(": the hook's elbow at about 90 (%.1f) and level (upper arm %.1f deg, elbow %+.2f over the fist)", sm.contactBend, sm.elev, sm.elbowDy),
				sm.contactBend >= 70 and sm.contactBend <= 110 and math.abs(sm.elev) <= 35 and sm.elbowDy >= -0.62 and sm.elbowDy <= 0.25)
		end
	end
	if sm.kind == "cross" or sm.kind == "leadhook" or sm.kind == "rearhook" then
		check(tag .. string.format(": the hips (%.1f) and the waist (%.1f) turn into it", sm.hip, sm.waist), sm.hip >= 12 and sm.waist >= 6)
	end
	if sm.kind == "uppercut" then
		check(tag .. string.format(": driven from the legs (the pelvis rises %.2f out of the dip into contact)", sm.rise), sm.rise >= 0.25)
	end
end

------------------------------------------------------------------------
-- the stance's life and the town idle: present, bounded, smooth
------------------------------------------------------------------------
local function lifeOf(model, fps, secs)
	local tick = timing(fps)
	local rows = {}
	local t = 0
	while t < secs do
		local dt = tick()
		t += dt
		frame({ a, b }, dt)
		local ut = model:FindFirstChild("UpperTorso").CFrame
		local hd = model:FindFirstChild("Head").CFrame
		local hrp = model:FindFirstChild("HumanoidRootPart").CFrame
		local lp = hrp:ToObjectSpace(ut)
		local hp = ut:ToObjectSpace(hd)
		local px, py, pz = lp:ToEulerAnglesYXZ()
		local hx, hy = hp:ToEulerAnglesYXZ()
		local fl = ut:PointToObjectSpace(model:FindFirstChild("LeftHand").Position)
		local fr = ut:PointToObjectSpace(model:FindFirstChild("RightHand").Position)
		local sl = ut:VectorToObjectSpace(-model:FindFirstChild("LeftUpperArm").CFrame.UpVector)
		local rg = rigOf(model)
		table.insert(rows, { t = t, dt = dt, chest = Vector3.new(deg(px), deg(py), deg(pz)), chestP = lp.Position, head = Vector3.new(deg(hx), deg(hy), 0),
			fl = fl, fr = fr, sl = sl, what = rg and rg.fidget and rg.fidget.kind or "" })
	end
	-- ranges (after a settle) and the roughness: the largest change of the per-frame velocity, per 1/60 s
	local lo, hi = {}, {}
	local function span(k, v)
		lo[k] = math.min(lo[k] or math.huge, v)
		hi[k] = math.max(hi[k] or -math.huge, v)
	end
	local rough = { chest = 0, head = 0, hands = 0 }
	-- (the stance's fidgets - a feint, a shoulder roll, a shake-out - are deliberate moves, not its idle life: the frames
	-- in one and the 0.4 s after it are left out)
	local lastF = -math.huge
	for i, r in ipairs(rows) do
		if r.what ~= "" then
			lastF = r.t
		end
		if r.t > 1 and r.t - lastF > 0.4 then
			span("chestPitch", r.chest.X)
			span("chestYaw", r.chest.Y)
			span("chestRoll", r.chest.Z)
			span("chestY", r.chestP.Y)
			span("chestX", r.chestP.X)
			span("headPitch", r.head.X)
			span("headYaw", r.head.Y)
			span("handLY", r.fl.Y)
			span("handRY", r.fr.Y)
			span("handLZ", r.fl.Z)
			span("shoulderL", deg(math.asin(math.clamp(r.sl.Y, -1, 1))))
			local p1, p2 = rows[i - 1], rows[i - 2]
			if p1 and p2 then
				local k = (1 / 60) / r.dt
				local k2 = (1 / 60) / p1.dt
				local function acc(f)
					return ((f(r) - f(p1)) * k - (f(p1) - f(p2)) * k2)
				end
				if args.life then
					local ay = acc(function(x)
						return x.chest.Y
					end)
					if math.abs(ay) > 0.25 then
						print(string.format("life t %.3f dt %.3f yaw %.2f acc %.3f %s", r.t, r.dt, r.chest.Y, ay, r.what))
					end
				end
				rough.chest = math.max(rough.chest, math.abs(acc(function(x)
					return x.chest.X
				end)), math.abs(acc(function(x)
					return x.chest.Y
				end)))
				rough.head = math.max(rough.head, math.abs(acc(function(x)
					return x.head.X
				end)))
				rough.hands = math.max(rough.hands, math.abs(acc(function(x)
					return x.fl.Y
				end)), math.abs(acc(function(x)
					return x.fr.Y
				end)))
			end
		end
	end
	local rg = {}
	for k, v in pairs(lo) do
		rg[k] = hi[k] - v
	end
	return rg, rough
end

local stance60, stanceRough60 = lifeOf(a, 60, 6)
local stance30, stanceRough30 = lifeOf(a, 30, 6)
-- the town idle: a player character standing (no tags)
for _, m in ipairs({ a, b }) do
	CS:RemoveTag(m, "Fighter")
end
for _ = 1, 3 do
	frame({ a, b }, 1 / 60)
end
player.Character = a
player.CharacterAdded:Fire(a)
local idle60, idleRough60 = lifeOf(a, 60, 6)
local idle30, idleRough30 = lifeOf(a, 30, 6)
if REPORT then
	for _, it in ipairs({ { "stance 60", stance60, stanceRough60 }, { "stance 30", stance30, stanceRough30 }, { "idle 60", idle60, idleRough60 },
		{ "idle 30", idle30, idleRough30 } }) do
		local rg, ro = it[2], it[3]
		print(string.format(
			"%-9s chest pitch %.2f yaw %.2f roll %.2f  y %.3f x %.3f  head pitch %.2f yaw %.2f  hands y %.3f/%.3f z %.3f  shoulder %.2f | rough chest %.3f head %.3f hands %.4f",
			it[1], rg.chestPitch, rg.chestYaw, rg.chestRoll, rg.chestY, rg.chestX, rg.headPitch, rg.headYaw, rg.handLY, rg.handRY, rg.handLZ, rg.shoulderL,
			ro.chest, ro.head, ro.hands))
	end
end
for _, it in ipairs({ { "stance 60fps", stance60, stanceRough60, true }, { "stance 30fps", stance30, stanceRough30, true },
	{ "town idle 60fps", idle60, idleRough60, false }, { "town idle 30fps", idle30, idleRough30, false } }) do
	local name, rg, ro, fight = it[1], it[2], it[3], it[4]
	-- present: the chest breathes and shifts, the hands move with it
	check(name .. string.format(": the chest breathes / shifts (pitch %.2f roll %.2f deg, rise %.3f)", rg.chestPitch, rg.chestRoll, rg.chestY),
		rg.chestPitch >= 0.6 and rg.chestY >= 0.006)
	check(name .. string.format(": the hands are alive (y %.3f / %.3f)", rg.handLY, rg.handRY), rg.handLY >= 0.015 and rg.handRY >= 0.015)
	check(name .. string.format(": the shoulders roll a little (%.2f deg)", rg.shoulderL), rg.shoulderL >= 0.4)
	-- bounded: subtle
	check(name .. string.format(": the chest's life is subtle (pitch %.2f yaw %.2f roll %.2f)", rg.chestPitch, rg.chestYaw, rg.chestRoll),
		rg.chestPitch <= (fight and 9 or 5) and rg.chestYaw <= (fight and 12 or 6) and rg.chestRoll <= (fight and 9 or 5))
	check(name .. string.format(": the head is steady (pitch %.2f yaw %.2f)", rg.headPitch, rg.headYaw), rg.headPitch <= 8 and rg.headYaw <= (fight and 14 or 10))
	check(name .. string.format(": the hands' life is subtle (y %.3f / %.3f)", rg.handLY, rg.handRY), rg.handLY <= (fight and 0.35 or 0.25) and rg.handRY <= (fight and 0.35 or 0.25))
	-- smooth: no frame-to-frame jitter (the change of the per-frame step, per 1/60 s)
	check(name .. string.format(": smooth (roughness chest %.3f head %.3f deg, hands %.4f studs)", ro.chest, ro.head, ro.hands),
		ro.chest <= 0.35 and ro.head <= 0.35 and ro.hands <= 0.012)
end

print(string.format("test_punchanim: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
