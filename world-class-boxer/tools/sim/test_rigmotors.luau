--!nocheck
-- tools/sim/test_rigmotors.luau: the Avatar Joint Upgrade's rig back on Motor6Ds (Shared.RigJoints.EnsureMotors) and
-- the diagnostic's written-vs-shown joint report (Diag.SampleTick / SampleLines).
--   * an AnimationConstraint rig (a constraint per R15 joint under the child part, between the two RigAttachments, the
--     attachments turned so C0 / C1 are not plain offsets): every joint becomes a Motor6D of the same name under the
--     same part, Part0 / Part1 = the attachments' parts, C0 / C1 = the attachments' CFrames, no constraint left, and the
--     limbs read the same pose through the new joint as through the old one
--   * the Neck Motor6D exists before its constraint goes (a Humanoid with RequiresNeck never sees a neckless rig)
--   * a second call converts nothing; a joint that already has a Motor6D just loses its constraint (no loop of two)
--   * a constraint with no attachments to build from stays (never a limb that falls off), and nothing throws
--   * localOnly marks the Motor6D; the server's own Motor6D replicating in later replaces it (Dedupe)
--   * WatchMotors converts a constraint the engine adds later (ApplyDescription, ReplaceBodyPartR15)
--   * Kind / Count; Diag's sample: written bend vs the bend the limb shows -> "NOT taking effect" / "take effect"
--   lune run tools/sim/test_rigmotors.luau
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local E = FE.new()
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local RigJoints = H.require("RigJoints")

local function near(a, b, tol)
	tol = tol or 1e-4
	local d = a:Inverse() * b
	return d.Position.Magnitude < tol and RigJoints.Angle(d) < tol * 100
end

------------------------------------------------------------------------
-- an upgraded R15 rig: parts at their rest places, an AnimationConstraint per joint
------------------------------------------------------------------------
local ATT = {
	Root = { V = { 0, -1, 0 }, W = { 0, 0.2, 0 } }, Waist = { V = { 0, 0.2, 0 }, W = { 0, -0.8, 0 } }, Neck = { V = { 0, 0.8, 0 }, W = { 0, -0.6, 0 } },
	LeftShoulder = { V = { -1, 0.56, 0 }, W = { 0.5, 0.39, 0 } }, RightShoulder = { V = { 1, 0.56, 0 }, W = { -0.5, 0.39, 0 } },
	LeftElbow = { V = { 0, -0.33, 0 }, W = { 0, 0.19, 0 } }, RightElbow = { V = { 0, -0.33, 0 }, W = { 0, 0.19, 0 } },
	LeftWrist = { V = { 0, -0.5, 0 }, W = { 0, 0.12, 0 } }, RightWrist = { V = { 0, -0.5, 0 }, W = { 0, 0.12, 0 } },
	LeftHip = { V = { -0.5, -0.2, 0 }, W = { 0, 0.42, 0 } }, RightHip = { V = { 0.5, -0.2, 0 }, W = { 0, 0.42, 0 } },
	LeftKnee = { V = { 0, -0.41, 0 }, W = { 0, 0.2, 0 } }, RightKnee = { V = { 0, -0.41, 0 }, W = { 0, 0.2, 0 } },
	LeftAnkle = { V = { 0, -0.55, 0 }, W = { 0, 0.085, 0 } }, RightAnkle = { V = { 0, -0.55, 0 }, W = { 0, 0.085, 0 } },
}
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end
-- (each attachment turned a little: C0 / C1 carry a rotation, as a real rig's shoulder / hip attachments do)
local TURN0 = CFrame.Angles(0.05, 0.1, -0.03)
local TURN1 = CFrame.Angles(-0.02, 0.07, 0.04)

local function newRig(jointClass)
	local model = E.new("Model", E.workspace)
	model.Name = "Upgraded"
	local parts = {}
	local function part(name)
		local p = parts[name]
		if not p then
			p = E.new("Part", model)
			p.Name = name
			parts[name] = p
		end
		return p
	end
	part("HumanoidRootPart").CFrame = CFrame.new(0, 3, 0)
	E.new("Humanoid", model)
	-- parents before children (NAMES is in that order)
	for _, name in ipairs(RigJoints.NAMES) do
		local p0, p1 = part(RigJoints.PARENT[name]), part(RigJoints.CHILD[name])
		local a0 = E.new("Attachment", p0)
		a0.Name = name .. "RigAttachment"
		a0.CFrame = CFrame.new(v3(ATT[name].V)) * TURN0
		local a1 = E.new("Attachment", p1)
		a1.Name = name .. "RigAttachment"
		a1.CFrame = CFrame.new(v3(ATT[name].W)) * TURN1
		-- the child at rest: child = parent * A0 * A1^-1
		p1.CFrame = p0.CFrame * a0.CFrame * a1.CFrame:Inverse()
		if jointClass == "Motor6D" then
			local m = E.new("Motor6D", p1)
			m.Name = name
			m.Part0, m.Part1, m.C0, m.C1 = p0, p1, a0.CFrame, a1.CFrame
		else
			local ac = E.new("AnimationConstraint", p1)
			ac.Name = name
			ac.Attachment0, ac.Attachment1 = a0, a1
			ac.IsKinematic = true
			ac.Transform = CFrame.new()
		end
	end
	return model, parts
end

------------------------------------------------------------------------
-- conversion
------------------------------------------------------------------------
do
	local model, parts = newRig("AnimationConstraint")
	local kind, nm, na = RigJoints.Kind(model)
	check("upgraded rig reads as AnimationConstraint (15)", kind == "AnimationConstraint" and nm == 0 and na == 15, string.format("%s %d %d", kind, nm, na))
	-- the pose each joint shows before
	local before = {}
	for _, name in ipairs(RigJoints.NAMES) do
		before[name] = RigJoints.Measure(RigJoints.Find(model, name))
	end
	-- the Neck: a Motor6D must already be there when its constraint goes
	local neckOk = nil
	local neckAC = parts.Head:FindFirstChild("Neck")
	neckAC.Destroying:Connect(function()
		local m = parts.Head:FindFirstChild("Neck")
		local found = false
		for _, c in ipairs(parts.Head:GetChildren()) do
			if c.Name == "Neck" and c:IsA("Motor6D") then
				found = true
			end
		end
		neckOk = found and m ~= nil
	end)
	local conv, kept = RigJoints.EnsureMotors(model)
	check("EnsureMotors converts all 15 joints", conv == 15 and kept == 0, string.format("%d converted, %d kept", conv, kept))
	check("the Neck Motor6D exists before its constraint is destroyed", neckOk == true, tostring(neckOk))
	local acLeft = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			acLeft += 1
		end
	end
	check("no AnimationConstraint left", acLeft == 0, acLeft)
	for _, name in ipairs(RigJoints.NAMES) do
		local m = RigJoints.Find(model, name)
		local p0, p1 = parts[RigJoints.PARENT[name]], parts[RigJoints.CHILD[name]]
		local ok = m ~= nil and m:IsA("Motor6D") and m.Parent == p1 and m.Part0 == p0 and m.Part1 == p1
		check(name .. ": a Motor6D under the child part joining parent -> child", ok)
		if ok then
			check(name .. ": C0 / C1 = the RigAttachments' CFrames", near(m.C0, p0:FindFirstChild(name .. "RigAttachment").CFrame)
				and near(m.C1, p1:FindFirstChild(name .. "RigAttachment").CFrame))
			check(name .. ": the limb's pose reads the same through the new joint", near(RigJoints.Measure(m), before[name], 1e-3))
			check(name .. ": not marked local (a server conversion)", m:GetAttribute("RigJointsLocal") == nil)
		end
	end
	kind, nm, na = RigJoints.Kind(model)
	check("rig reads as Motor6D (15) afterwards", kind == "Motor6D" and nm == 15 and na == 0, string.format("%s %d %d", kind, nm, na))
	-- idempotent
	local conv2, kept2 = RigJoints.EnsureMotors(model)
	check("a second call converts nothing", conv2 == 0 and kept2 == 15, string.format("%d / %d", conv2, kept2))
	local motors = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors += 1
		end
	end
	check("still exactly 15 Motor6Ds", motors == 15, motors)
end

-- a joint with both a Motor6D and a constraint (the head swap's rebuilt Neck next to an upgrade constraint): the
-- constraint goes, no second Motor6D
do
	local model, parts = newRig("Motor6D")
	local a0, a1 = parts.UpperTorso:FindFirstChild("NeckRigAttachment"), parts.Head:FindFirstChild("NeckRigAttachment")
	local ac = E.new("AnimationConstraint", parts.Head)
	ac.Name = "Neck"
	ac.Attachment0, ac.Attachment1 = a0, a1
	local conv = RigJoints.EnsureMotors(model)
	local n = 0
	for _, c in ipairs(parts.Head:GetChildren()) do
		if c.Name == "Neck" then
			n += 1
			check("mixed Neck: what stays is the Motor6D", c:IsA("Motor6D"))
		end
	end
	check("mixed Neck: the constraint removed, one joint left", conv == 1 and n == 1, string.format("conv %d, %d Neck joints", conv, n))
end

-- a constraint with nothing to build from (its attachments and the part's RigAttachment gone): left alone, no throw
do
	local model, parts = newRig("AnimationConstraint")
	local ac = parts.LeftFoot:FindFirstChild("LeftAnkle")
	ac.Attachment1 = nil
	parts.LeftFoot:FindFirstChild("LeftAnkleRigAttachment"):Destroy()
	local ok, conv = pcall(RigJoints.EnsureMotors, model)
	check("unbuildable joint: no throw", ok, conv)
	check("unbuildable joint: the other 14 converted", conv == 14, conv)
	check("unbuildable joint: its constraint stays", parts.LeftFoot:FindFirstChild("LeftAnkle") ~= nil
		and parts.LeftFoot:FindFirstChild("LeftAnkle"):IsA("AnimationConstraint"))
	-- a half-built rig (no LowerTorso at all) never throws either
	parts.LowerTorso.Parent = nil
	local ok2 = pcall(RigJoints.EnsureMotors, model)
	check("a rig missing a torso: no throw", ok2)
end

-- localOnly + Dedupe: a client's conversion, then the server's Motor6D replicating in
do
	local model, parts = newRig("AnimationConstraint")
	RigJoints.EnsureMotors(model, { localOnly = true })
	local knee = RigJoints.Find(model, "LeftKnee")
	check("localOnly: the Motor6D is marked RigJointsLocal", knee and knee:GetAttribute("RigJointsLocal") == true)
	local server = E.new("Motor6D", parts.LeftLowerLeg)
	server.Name = "LeftKnee"
	server.Part0, server.Part1 = parts.LeftUpperLeg, parts.LeftLowerLeg
	server.C0 = knee.C0
	server.C1 = knee.C1
	RigJoints.Dedupe(model)
	local n, kept = 0, nil
	for _, c in ipairs(parts.LeftLowerLeg:GetChildren()) do
		if c.Name == "LeftKnee" then
			n += 1
			kept = c
		end
	end
	check("Dedupe: one LeftKnee left, the server's", n == 1 and kept == server, n)
end

-- WatchMotors: a constraint the engine adds later is converted (deferred)
do
	local model, parts = newRig("AnimationConstraint")
	RigJoints.WatchMotors(model)
	local _, _, na0 = RigJoints.Kind(model)
	check("WatchMotors converts at once", na0 == 0, na0)
	-- (ReplaceBodyPartR15 on an upgraded place: a new part with a new constraint)
	local old = RigJoints.Find(model, "RightKnee")
	old:Destroy()
	local ac = E.new("AnimationConstraint", parts.RightLowerLeg)
	ac.Name = "RightKnee"
	ac.Attachment0 = parts.RightUpperLeg:FindFirstChild("RightKneeRigAttachment")
	ac.Attachment1 = parts.RightLowerLeg:FindFirstChild("RightKneeRigAttachment")
	ltask.wait()
	ltask.wait()
	local j = RigJoints.Find(model, "RightKnee")
	check("WatchMotors: the late constraint became a Motor6D", j ~= nil and j:IsA("Motor6D"), j and j.ClassName)
	-- a second WatchMotors on the same model makes no second watcher (and still converts)
	RigJoints.WatchMotors(model)
	check("WatchMotors twice: still 15 Motor6Ds", select(2, RigJoints.Count(model)) == 0 and RigJoints.Count(model) == 15)
end

-- an engine that puts a constraint back every time: the watcher gives up after MAX_ROUNDS (no endless churn)
do
	local model, parts = newRig("AnimationConstraint")
	local saved = RigJoints.MAX_ROUNDS
	RigJoints.MAX_ROUNDS = 3
	RigJoints.WatchMotors(model)
	local function readd()
		local ac = E.new("AnimationConstraint", parts.LeftLowerLeg)
		ac.Name = "LeftKnee"
		ac.Attachment0 = parts.LeftUpperLeg:FindFirstChild("LeftKneeRigAttachment")
		ac.Attachment1 = parts.LeftLowerLeg:FindFirstChild("LeftKneeRigAttachment")
		ltask.wait()
		ltask.wait()
	end
	for _ = 1, 3 do
		local m = RigJoints.Find(model, "LeftKnee")
		if m then
			m:Destroy()
		end
		readd()
	end
	local converted3 = RigJoints.Find(model, "LeftKnee")
	check("churn: converted while under the limit", converted3 and converted3:IsA("Motor6D"), converted3 and converted3.ClassName)
	converted3:Destroy()
	readd()
	local after = RigJoints.Find(model, "LeftKnee")
	check("churn: past MAX_ROUNDS the watcher stops (the constraint stays)", after and after:IsA("AnimationConstraint"), after and after.ClassName)
	RigJoints.MAX_ROUNDS = saved
end

------------------------------------------------------------------------
-- Diag's sample: written vs shown
------------------------------------------------------------------------
do
	local Diag = H.require("Diag")
	local model, parts = newRig("Motor6D")
	E.new("Part", model).Name = "LeftFoot_dummy"
	local KNEE = CFrame.Angles(math.rad(-45), 0, 0)
	local HIP = CFrame.Angles(math.rad(30), 0, 0)
	local ELBOW = CFrame.Angles(math.rad(-35), 0, 0)
	local WRITE = { RightKnee = KNEE, RightHip = HIP, RightElbow = ELBOW }
	RigJoints.Written = function(m, name)
		return m == model and WRITE[name] or nil
	end
	RigJoints.Status = function()
		return "procedural, joints Motor6D (test)"
	end
	local function run(shows)
		local S = Diag.NewSample()
		for i = 1, 12 do
			local root = parts.HumanoidRootPart
			root.CFrame = CFrame.new(0, 3, -i * 0.6)
			root.AssemblyLinearVelocity = Vector3.new(0, 0, -6)
			-- the limbs from the root out, with the written pose applied or not (the engine honouring the writes or not)
			for _, name in ipairs(RigJoints.NAMES) do
				local m = RigJoints.Find(model, name)
				local T = shows and WRITE[name] or CFrame.new()
				m.Part1.CFrame = m.Part0.CFrame * m.C0 * T * m.C1:Inverse()
			end
			Diag.SampleTick(S, model, i * 0.1)
		end
		return Diag.SampleLines(S)
	end
	local function has(res, pat)
		for _, v in ipairs(res.verdicts) do
			if v:find(pat, 1, true) then
				return true
			end
		end
		return false
	end
	local bad = run(false)
	check("diag: writes ignored -> 'NOT taking effect'", has(bad, "joint writes are NOT taking effect"), table.concat(bad.verdicts, " | "))
	check("diag: writes ignored -> the knees 'wrote a bend' verdict", has(bad, "although the Animator wrote a bend"), table.concat(bad.verdicts, " | "))
	local good = run(true)
	check("diag: writes shown -> 'joint writes take effect'", has(good, "OK   joint writes take effect"), table.concat(good.verdicts, " | "))
	check("diag: writes shown -> no knee verdict", not has(good, "knees never bent"), table.concat(good.verdicts, " | "))
	local joined = table.concat(good.lines, "\n")
	check("diag: the sample prints written next to shown (knee=-45(w-45))", joined:find("knee=-45(w-45)", 1, true) ~= nil, good.lines[2])
	check("diag: the sample names the rig's joints and the Animator's mode", joined:find("joints: Motor6D (Motor6D 15 / AnimationConstraint 0); Animator: procedural", 1, true) ~= nil,
		good.lines[1])
	RigJoints.Written, RigJoints.Status = nil, nil
	-- the server's view (no Written provider): no write verdict at all, the old knee verdict
	local srv = run(false)
	check("diag (server view): no written-vs-shown verdict without the Animator", not has(srv, "joint writes"), table.concat(srv.verdicts, " | "))
end

print(string.format("test_rigmotors: %d passed, %d failed", pass, fail))
if fail > 0 then
	require("@lune/process").exit(1)
end
