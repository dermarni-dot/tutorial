--!nocheck
-- tools/sim/test_heightaim.luau: the punches across heights, through the REAL client Animator (src/client/Animator.client.lua
-- and its Anim* modules) on two R15 block rigs with the joints of the tier-3 Athletic boxer (test_punchanim's, gloves on the
-- hands as Builder fits them), each scaled to his height as Builder.Scales builds him (the body's HeightScale; the head is
-- not height-scaled), and the server's hit test (Shared.HitGeometry) on the frames HitGeometry.Frame reads off the same rigs.
-- Every pairing of 5'4", 5'10", 6'3" and 6'8" (64 / 70 / 75 / 80 in), both ways:
--   * where the server lands a punch (HitGeometry.Test, the redirect included: a head shot it puts on the body is thrown at
--     the body, as Fight:Punch throws it), the glove visibly lands there: within CONTACT of the target's surface at its
--     closest and close to it at the contact frame (the windup, when the server resolves it), on the HEAD for a head shot -
--     a straight on the chin / face, a hook and an uppercut at the jaw (the glove's centre under the head's centre, not
--     at the crown, not down at the throat) - and on the TORSO for a body shot (between the waist and the chest's top)
--   * where the server calls it out of reach (past its range), the glove visibly misses
--   * the arm at contact stays a boxer's: the shoulder-to-glove line and the upper arm never thrown up overhead or straight
--     down, the elbow never locked past straight or folded shut (AnimFight.ARM_HEIGHT)
--   * the reach: proportional to the arm (the taller man's jab reaches further, by about his longer arm), a real but fair
--     edge (never more than a stud and a half of jab range between 5'4" and 6'8"), and the shorter man's inside game (his
--     uppercut and his body shots still land on the taller man)
--   * the AI (tools/sim/fightsim, whole AI-vs-AI fights at the extreme pairings): both men land, the shorter one mostly to
--     the body and with the uppercut, neither throwing most of his punches from out of reach
--   lune run tools/sim/test_heightaim.luau [--report] [--only 64-80,80-64] [--reps 3]
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

local Builder = H.require("Builder")
local HG = H.require("HitGeometry")
local Config = H.require("Config")

------------------------------------------------------------------------
-- the rig: the tier-3 Athletic boxer's R15 joints at 70 in (part sizes and rig attachments measured off Builder.Cosmetics'
-- build: v9_anim --clips reach --probe 1), its gloves (BoxerLook.Hands.GloveL / R, where the Animator's contact spheres
-- read them), scaled to a height by the body's HeightScale against the 70-inch one's (width and depth are the frame's)
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
local CORE = { 1.723, 2.4858, 0.8874 }
local GLOVE = { size = { 0.6012, 0.9645, 0.8295 }, off = { 0.0307, -0.1256, -0.0091 } }
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" }, Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" }, RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" }, RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" }, RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" }, RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" }, RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" }, RightAnkle = { "RightLowerLeg", "RightFoot" },
}
local function scaleK(hIn)
	local function hs(h)
		return Builder.Scales({ gender = 1, height = h, body = { frame = "Athletic" } }, nil, nil).height
	end
	return hs(hIn) / hs(70)
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
	-- (the gloves ride on the hands: Builder's weld)
	local gl = rawget(model, "_gloves")
	if gl then
		for _, g in ipairs(gl) do
			g.part.CFrame = g.hand.CFrame * g.off
		end
	end
end
local STATE = { Running = roblox.Enum.HumanoidStateType.Running }
local function newRig(name, hIn, at)
	local k = scaleK(hIn)
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
	local function v3k(t)
		return Vector3.new(t[1], t[2] * k, t[3])
	end
	for pname, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = v3k(pos)
		end
		addPart(pname, v3k(b.size), atts)
	end
	addPart("Head", Vector3.new(HEAD, HEAD, HEAD), { NeckRigAttachment = Vector3.new(0, -HEAD / 2, 0) })
	-- (the torso's own size under the shoulder caps, as BuilderTiers marks the tier mesh: HitGeometry.Frame reads it)
	model:FindFirstChild("UpperTorso"):SetAttribute("BodyCoreSize", Vector3.new(CORE[1], CORE[2] * k, CORE[3]))
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		m.Transform = CFrame.new()
	end
	local look = E.new("Folder", model)
	look.Name = "BoxerLook"
	local hands = E.new("Folder", look)
	hands.Name = "Hands"
	local gloves = {}
	for _, s in ipairs({ "L", "R" }) do
		local g = E.new("Part", hands)
		g.Name = "Glove" .. s
		g.Size = Vector3.new(GLOVE.size[1], GLOVE.size[2] * k, GLOVE.size[3])
		local sx = s == "L" and 1 or -1
		table.insert(gloves, { part = g, hand = model:FindFirstChild(s == "L" and "LeftHand" or "RightHand"),
			off = CFrame.new(GLOVE.off[1] * sx, GLOVE.off[2] * k, GLOVE.off[3]) })
	end
	rawset(model, "_gloves", gloves)
	local hum = E.new("Humanoid", model)
	hum.HipHeight = HIP_HEIGHT * k
	hum.Sit = false
	hum.MoveDirection = Vector3.zero
	hum.WalkSpeed = 16
	hum.GetState = function()
		return STATE.Running
	end
	hrp.CFrame = at or CFrame.new(0, HIP_HEIGHT * k + 1, 0)
	solve(model)
	return model, hum, k
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
	assert(rigsReady(), "test_heightaim: the Animator did not finish loading")
end
local AnimFight = H.require("AnimFight")
local DT = 1 / 60
local function frame(models)
	VT += DT
	PreSim:Fire(DT)
	for _, m in ipairs(models) do
		solve(m)
	end
	ltask.wait()
end

------------------------------------------------------------------------
-- one throw: the glove against the target over the punch, and at the contact frame
------------------------------------------------------------------------
local function boxGap(p, part)
	local lp = part.CFrame:PointToObjectSpace(p)
	local s = part.Size / 2
	local q = Vector3.new(math.clamp(lp.X, -s.X, s.X), math.clamp(lp.Y, -s.Y, s.Y), math.clamp(lp.Z, -s.Z, s.Z))
	return (lp - q).Magnitude
end
local PUNCHES = {
	{ "jab", "jab|L|%s|0.16|0.8" }, { "cross", "cross|R|%s|0.2|0.9" }, { "leadhook", "leadhook|L|%s|0.2|0.9" },
	{ "rearhook", "rearhook|R|%s|0.22|0.9" }, { "uppercut", "uppercut|R|%s|0.22|0.9" }, { "overhand", "overhand|R|%s|0.24|0.9" },
}
local actId = 0
local function place(a, b, gap)
	local ha, hb = a:FindFirstChild("HumanoidRootPart"), b:FindFirstChild("HumanoidRootPart")
	ha.CFrame = CFrame.new(0, ha.CFrame.Y, gap / 2)
	hb.CFrame = CFrame.new(0, hb.CFrame.Y, -gap / 2) * CFrame.Angles(0, math.pi, 0)
end
-- (REPS throws from the gap, the median one by its closest: the client picks a variant per throw - a long jab, a tight or
-- a wide hook - which reach a few tenths apart, as tools/sim/anim_reach.json measures them)
local REPS = tonumber(args.reps) or 3
-- (how far inside the server's reach the "lands" throw is made, studs)
local INSIDE = tonumber(args.inside) or 0.35
local throwOnce
local function throw(a, b, gap, act, body)
	local rs = {}
	for _ = 1, REPS do
		table.insert(rs, throwOnce(a, b, gap, act, body))
	end
	table.sort(rs, function(x, y)
		return x.best < y.best
	end)
	return rs[math.floor((#rs + 1) / 2)]
end
function throwOnce(a, b, gap, act, body)
	place(a, b, gap)
	for _ = 1, 30 do
		frame({ a, b })
	end
	local hand = act:match("^[^|]*|(%a)")
	local glove = a:FindFirstChild("BoxerLook"):FindFirstChild("Hands"):FindFirstChild("Glove" .. hand)
	local gr = math.max(glove.Size.X, glove.Size.Z) / 2
	local windup = tonumber(act:match("^[^|]*|%a|%a+|([%d%.]+)"))
	actId += 1
	a:SetAttribute("Act", act)
	a:SetAttribute("ActId", actId)
	local r = { best = math.huge }
	local hd, ut, lt = b:FindFirstChild("Head"), b:FindFirstChild("UpperTorso"), b:FindFirstChild("LowerTorso")
	for k = 1, 34 do
		frame({ a, b })
		local gp = glove.Position
		local s, dy
		if body then
			s = math.min(boxGap(gp, ut), boxGap(gp, lt)) - gr
			dy = gp.Y
		else
			s = (gp - hd.Position).Magnitude - HEAD / 2 - gr
			dy = gp.Y - hd.Position.Y
		end
		if s < r.best then
			r.best, r.bestY = s, dy
		end
		if not r.csurf and k * DT >= windup - 1e-6 then
			r.csurf, r.cY = s, dy
			local side = hand == "L" and "Left" or "Right"
			local ua, la = a:FindFirstChild(side .. "UpperArm"), a:FindFirstChild(side .. "LowerArm")
			local sp = ua.CFrame:PointToWorldSpace(ua:FindFirstChild(side .. "ShoulderRigAttachment").Position)
			local v = gp - sp
			r.line = deg(math.asin(math.clamp(v.Unit.Y, -1, 1)))
			r.upper = deg(math.asin(math.clamp(-ua.CFrame.UpVector.Y, -1, 1)))
			r.bend = deg(math.acos(math.clamp(ua.CFrame.UpVector:Dot(la.CFrame.UpVector), -1, 1)))
		end
	end
	a:SetAttribute("Act", "idle")
	for _ = 1, 40 do
		frame({ a, b })
	end
	return r
end

------------------------------------------------------------------------
-- the height matrix
------------------------------------------------------------------------
local HEIGHTS = { 64, 70, 75, 80 }
-- (visible contact: the glove's surface within CONTACT of the head sphere; a body shot's glove rests on the organic torso up
-- to a quarter stud off the R15 boxes while it reaches - tools/sim/anim_reach.json's contactBody)
local CONTACT = HG.CONTACT
local CONTACT_BODY = 0.35
-- (and a jab, a cross or a hook to the head 0.2, as anim_reach.json measures them: a straight lands a touch under a tall
-- man's chin, a hook's glove meets the jaw from the side, beside the head sphere)
local CONTACT_HEAD = 0.2
local function contactOf(zone, p)
	if zone == "body" then
		return CONTACT_BODY
	end
	return (p == "uppercut" or p == "overhand") and CONTACT or CONTACT_HEAD
end
local results = {}
local only = args.only and ("," .. args.only .. ",") or nil
local agree, disagree = 0, 0
for _, hA in ipairs(HEIGHTS) do
	for _, hB in ipairs(HEIGHTS) do
		local tag = hA .. "-" .. hB
		if only and not only:find("," .. tag .. ",", 1, true) then
			continue
		end
		local a = newRig("BoxerA", hA)
		local b = newRig("BoxerB", hB)
		-- (the frames the server reads off the rigs at rest, the soles on the floor)
		local GA, GB = HG.Frame(a, 0), HG.Frame(b, 0)
		a.Parent, b.Parent = E.workspace, E.workspace
		for _, m in ipairs({ a, b }) do
			m:SetAttribute("Guard", "stance")
			m:SetAttribute("Style", "BoxerPuncher")
			m:SetAttribute("Stam", 1)
			m:SetAttribute("Daze", 0)
			CS:AddTag(m, "Fighter")
		end
		local sep = HG.MinSep(GA, GB)
		if REPORT then
			print(string.format("%s A: %s", tag, HG.Describe(GA)))
			print(string.format("%s B: %s", tag, HG.Describe(GB)))
		end
		place(a, b, sep + 0.5)
		for _ = 1, 60 do
			frame({ a, b })
		end
		if REPORT then
			local ua = a:FindFirstChild("LeftUpperArm")
			local sp = ua.CFrame:PointToWorldSpace(ua:FindFirstChild("LeftShoulderRigAttachment").Position)
			print(string.format("%s stance: A shoulder %.3f UT %.3f head %.3f root %.3f", tag, sp.Y, a:FindFirstChild("UpperTorso").Position.Y, a:FindFirstChild("Head").Position.Y,
				a:FindFirstChild("HumanoidRootPart").Position.Y))
		end
		local hdB, utB, ltB = b:FindFirstChild("Head"), b:FindFirstChild("UpperTorso"), b:FindFirstChild("LowerTorso")
		local headY = hdB.Position.Y
		local waistY = ltB.Position.Y - ltB.Size.Y / 2
		local chestTop = utB.Position.Y + utB.Size.Y / 2
		local pr = { tag = tag, hA = hA, hB = hB, GA = GA, GB = GB, sep = sep, rows = {} }
		table.insert(results, pr)
		for _, pd in ipairs(PUNCHES) do
			local p, fmt = pd[1], pd[2]
			for _, zone in ipairs(p == "overhand" and { "head" } or { "head", "body" }) do
				local body = zone == "body"
				-- the server's verdict as Fight:Punch throws it: a head shot that lands on the body from here is thrown there
				local range = HG.Range(GA, GB, p, body, { noRedirect = true })
				local row = { p = p, zone = zone, range = range }
				table.insert(pr.rows, row)
				-- inside: a third of a stud inside the server's reach, never inside the bodies' separation (a punch the server
				-- lands only from about as close as the bodies get is judged by the far side alone)
				if range >= sep + 0.4 then
					local g = math.max(sep + 0.05, range - INSIDE)
					local v = HG.Test(GA, GB, p, body, g, { noRedirect = true })
					local r = throw(a, b, g, string.format(fmt, zone), body)
					row.inGap, row.inOk, row.inR = g, v.ok, r
					-- (on the head: the glove's centre under the head's centre - the chin, the jaw - never at the crown or
					-- down at the throat; on the torso: between the waist and the chest's top)
					local spotOk
					if body then
						spotOk = r.cY >= waistY - 0.1 and r.cY <= chestTop + 0.05
					else
						spotOk = r.cY <= HEAD * 0.3 and r.cY >= -(HEAD * 0.5 + 0.55)
					end
					row.spotOk = spotOk
					if v.ok then
						if r.best <= contactOf(zone, p) + 0.05 then
							agree += 1
						else
							disagree += 1
						end
					end
				end
				-- outside: past the server's reach (or from the separation when it never lands), the glove misses
				local go = math.max(range, sep) + 0.45
				local vo = HG.Test(GA, GB, p, body, go, { noRedirect = true })
				local ro = throw(a, b, go, string.format(fmt, zone), body)
				row.outGap, row.outOk, row.outR = go, vo.ok, ro
				if not vo.ok then
					if ro.best > contactOf(zone, p) - 0.05 then
						agree += 1
					else
						disagree += 1
					end
				end
				if REPORT then
					local ir = row.inR
					print(string.format("%-6s %-9s %-4s range %.2f sep %.2f | in %s %s best %+.2f c %+.2f y %+.2f line %5.1f upper %5.1f bend %5.1f | out %.2f %s best %+.2f",
						tag, p, zone, range, sep, row.inGap and string.format("%.2f", row.inGap) or "  -  ", row.inGap and (row.inOk and "hit " or "miss") or "    ",
						ir and ir.best or 0, ir and ir.csurf or 0, ir and ir.cY or 0, ir and ir.line or 0, ir and ir.upper or 0, ir and ir.bend or 0,
						go, vo.ok and "hit " or "miss", ro.best))
				end
			end
		end
		for _, m in ipairs({ a, b }) do
			CS:RemoveTag(m, "Fighter")
			m:Destroy()
		end
		for _ = 1, 3 do
			frame({})
		end
	end
end

------------------------------------------------------------------------
-- the checks
------------------------------------------------------------------------
local ARM = AnimFight.ARM_HEIGHT
check("the IK height limits are there (AnimFight.ARM_HEIGHT)", type(ARM) == "table" and ARM.straight and ARM.hook and ARM.upper and ARM.over)
for _, pr in ipairs(results) do
	for _, row in ipairs(pr.rows) do
		local name = string.format("%s in %s %s", pr.tag:gsub("-", " -> "), row.p, row.zone)
		if row.inGap then
			local r = row.inR
			-- (a straight up at a head a foot and more above his own - 5'4" at 6'8" - meets the chin from underneath, the glove
			-- brushing it a tenth or two further off the head sphere on these block rigs than on the tier rig's measure)
			local slack = (row.zone == "head" and (row.p == "jab" or row.p == "cross") and pr.hB - pr.hA >= 12) and 0.2 or 0.05
			check(name .. string.format(": the server lands it %.2f inside its reach", row.range - row.inGap), row.inOk)
			check(name .. string.format(": the glove visibly lands (closest %.2f of the surface)", r.best), r.best <= contactOf(row.zone, row.p) + slack)
			check(name .. string.format(": there at the contact frame (%.2f off)", r.csurf), r.csurf <= contactOf(row.zone, row.p) + 0.15 + slack)
			check(name .. string.format(": on the %s (glove at %+.2f)", row.zone == "body" and "torso" or "chin / jaw", r.cY), row.spotOk)
			-- the arm: never overhead, never hanging, never locked out past straight or folded shut
			local lineMax = row.p == "overhand" and 62 or 52
			check(name .. string.format(": a natural arm (line %.0f, upper arm %.0f, elbow %.0f deg)", r.line, r.upper, r.bend),
				r.line <= lineMax and r.line >= -68 and r.upper <= (row.p == "overhand" and 55 or 42) and r.bend <= 150)
		end
		check(name .. string.format(": past the server's reach (%.2f) the glove misses (closest %.2f)", row.outGap, row.outR.best),
			row.outOk or row.outR.best > contactOf(row.zone, row.p) - 0.05)
	end
end
print(string.format("  server hit / visual agreement: %d of %d throws", agree, agree + disagree))

-- the reach: proportional to the arm, the taller man's edge real but fair, the shorter man's inside game
do
	local by = {}
	for _, pr in ipairs(results) do
		by[pr.tag] = pr
	end
	local function rangeOf(tag, p, zone)
		local pr = by[tag]
		if not pr then
			return nil
		end
		for _, row in ipairs(pr.rows) do
			if row.p == p and row.zone == zone then
				return row.range, pr
			end
		end
	end
	local j64, p64 = rangeOf("64-70", "jab", "head")
	local j80, p80 = rangeOf("80-70", "jab", "head")
	if j64 and j80 then
		local armK = (p80.GA.arm + p80.GA.glove) / (p64.GA.arm + p64.GA.glove)
		local reachK = (j80 - p80.GB.headR) / (j64 - p64.GB.headR)
		check(string.format("reach: the jab at the same man grows with the arm (6'8\" / 5'4\": reach x %.2f, arm x %.2f)", reachK, armK), reachK > 1.05 and math.abs(reachK - armK) <= 0.12)
	end
	local tall, short = rangeOf("80-64", "jab", "head"), rangeOf("64-80", "jab", "head")
	local shortB = rangeOf("64-80", "jab", "body")
	if tall and short and shortB then
		local shortBest = math.max(short, shortB)
		check(string.format("reach: the 6'8\" man's jab outreaches the 5'4\" man's (%.2f vs %.2f to the body)", tall, shortBest), tall > shortBest + 0.4)
		check(string.format("reach: by a fair margin (%.2f stud)", tall - shortBest), tall - shortBest <= 1.5)
	end
	-- (up to about a foot taller: two feet - 5'4" at 6'8" - and the chin is out of every punch's reach, the uppercut's too)
	for _, tag in ipairs({ "64-75", "70-80", "64-70" }) do
		local up = rangeOf(tag, "uppercut", "head")
		local sep = by[tag] and by[tag].sep
		if up and sep then
			check(string.format("reach: the shorter man's uppercut lands on the taller chin (%s: %.2f, separation %.2f)", tag, up, sep), up >= sep + 0.2)
		end
		local bj = rangeOf(tag, "jab", "body")
		if bj and sep then
			check(string.format("reach: the shorter man's jab to the body lands (%s: %.2f)", tag, bj), bj >= sep + 0.4)
		end
	end
	-- (same heights: the head and body jab land from out at range for every height)
	for _, h in ipairs(HEIGHTS) do
		local tag = h .. "-" .. h
		local j = rangeOf(tag, "jab", "head")
		if j then
			check(string.format("reach: %s the jab lands from range (%.2f, separation %.2f)", tag, j, by[tag].sep), j >= by[tag].sep + 0.8)
		end
	end
end

------------------------------------------------------------------------
-- the AI at a height gap (whole fights, AI vs AI: tools/sim/fightsim)
------------------------------------------------------------------------
do
	local FS = require("./fightsim")
	local S = FS.new()
	-- (every punch's reach verdict, per man: Fight:Resolve leaves it in F.lastHit)
	local Fight = S.FightEngine._Fight
	local tally = {}
	local resolve = Fight.Resolve
	Fight.Resolve = function(self, F, O, ptype, body, ...)
		local before = F.lastHit
		local r = table.pack(resolve(self, F, O, ptype, body, ...))
		local h = F.lastHit
		local t = tally[F]
		if t and h and h ~= before then
			t.thrown += 1
			if h.ok then
				t.landed += 1
				if h.zone == "body" then
					t.body += 1
				end
				if ptype == "uppercut" then
					t.upper += 1
				end
			elseif h.why == "short" or h.why == "high" or h.why == "low" then
				t.out += 1
			end
		end
		return table.unpack(r, 1, r.n)
	end
	for _, pair in ipairs({ { 64, 80 }, { 80, 64 }, { 64, 75 }, { 70, 80 } }) do
		local hS, hT = pair[1], pair[2]
		local sum = { { thrown = 0, landed = 0, body = 0, upper = 0, out = 0 }, { thrown = 0, landed = 0, body = 0, upper = 0, out = 0 } }
		for seed = 1, 4 do
			S.Fight({ red = { style = "BoxerPuncher", level = 60, height = hS }, blue = { style = "BoxerPuncher", level = 60, height = hT }, rounds = 3, seed = seed,
				onTick = function(f)
					if not tally[f.P] then
						tally[f.P], tally[f.O] = sum[1], sum[2]
					end
				end })
		end
		local tagP = string.format("AI %s vs %s", Config.HeightText(hS), Config.HeightText(hT))
		if REPORT then
			for i = 1, 2 do
				print(string.format("  %s #%d: %d thrown, %d land (%d to the body, %d uppercuts), %d out of reach", tagP, i, sum[i].thrown, sum[i].landed, sum[i].body,
					sum[i].upper, sum[i].out))
			end
		end
		check(tagP .. string.format(": both men land (%d / %d)", sum[1].landed, sum[2].landed), sum[1].landed > 20 and sum[2].landed > 20)
		for i = 1, 2 do
			local who = i == 1 and "the first" or "the second"
			check(tagP .. string.format(": %s seldom throws from out of reach (%d of %d)", who, sum[i].out, sum[i].thrown), sum[i].out <= sum[i].thrown * 0.25)
		end
		if hS < hT - 8 then
			check(tagP .. string.format(": the much shorter man works the body and the uppercut (%d body, %d uppercuts of %d landed)", sum[1].body, sum[1].upper,
				sum[1].landed), sum[1].body + sum[1].upper >= sum[1].landed * 0.35)
		end
	end
	Fight.Resolve = resolve
end

print(string.format("test_heightaim: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
