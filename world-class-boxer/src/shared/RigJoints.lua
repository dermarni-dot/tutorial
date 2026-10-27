-- RigJoints: one way to find and read an R15 rig's joints whatever class the engine gave them.
-- [Studio] StarterPlayer.AvatarJointUpgrade (the Avatar Joint Upgrade rollout; NOT a Workspace property, and
-- RobloxScriptSecurity: no game script can read or set it - only the place file / Studio's Properties panel can) builds
-- player characters, NPCs made by CreateHumanoidModelFromDescription and ApplyDescription'd rigs with an
-- AnimationConstraint per joint instead of a Motor6D: the constraint sits under the CHILD part (Head.Neck,
-- LeftUpperLeg.LeftHip...), its Part0 / Part1 / C0 / C1 are read-only deprecated aliases, Attachment0 (in the parent
-- part) / Attachment1 (in the child part) are the two RigAttachments, and Transform reads as a Motor6D's:
-- child = parent * A0.CFrame * Transform * A1.CFrame^-1 (a Motor6D's Part1 = Part0 * C0 * Transform * C1^-1 with
-- C0 = A0.CFrame, C1 = A1.CFrame), so a pose written to either reads the same.
-- [Studio] but writing it does not move the limbs in the user's place (their video: the character walks in the bind pose,
-- no error), while the Motor6D path is the one Roblox documents and every build before the upgrade animated with
-- (Motor6D.Transform is NotReplicated and local to the client that writes it; AnimationConstraint.Transform is a
-- saved, replicated property of a Constraint). So EnsureMotors rebuilds an upgraded rig's joints as the Motor6Ds the
-- upgrade replaced (same parts, C0 / C1 = the attachments' CFrames: the pose is unchanged): the server does it for
-- every character and NPC (Main, Builder), the client Animator for any rig still carrying them. Everything that touches
-- a joint (the Animator, AnimRig, the client Ragdoll, Diag) goes through here, and still reads either class.
local RigJoints = {}

-- the part each R15 joint drives (where the Motor6D / AnimationConstraint lives) and the part it hangs from
RigJoints.CHILD = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}
RigJoints.PARENT = {
	Root = "HumanoidRootPart", Waist = "LowerTorso", Neck = "UpperTorso",
	RightShoulder = "UpperTorso", RightElbow = "RightUpperArm", RightWrist = "RightLowerArm",
	LeftShoulder = "UpperTorso", LeftElbow = "LeftUpperArm", LeftWrist = "LeftLowerArm",
	RightHip = "LowerTorso", RightKnee = "RightUpperLeg", RightAnkle = "RightLowerLeg",
	LeftHip = "LowerTorso", LeftKnee = "LeftUpperLeg", LeftAnkle = "LeftLowerLeg",
}
RigJoints.NAMES = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }

local I = CFrame.identity

-- is this instance a joint the rig can be posed through?
function RigJoints.IsJoint(inst)
	return inst ~= nil and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint"))
end

-- the joint's parent and child parts (Motor6D: Part0 / Part1; AnimationConstraint: the attachments' parts)
function RigJoints.Parts(j)
	if not j then
		return nil, nil
	end
	if j:IsA("Motor6D") then
		return j.Part0, j.Part1
	end
	local a0, a1 = j.Attachment0, j.Attachment1
	local p0 = a0 and a0.Parent
	local p1 = a1 and a1.Parent
	return (p0 and p0:IsA("BasePart")) and p0 or nil, (p1 and p1:IsA("BasePart")) and p1 or nil
end
function RigJoints.Part0(j)
	local p0 = RigJoints.Parts(j)
	return p0
end
function RigJoints.Part1(j)
	local _, p1 = RigJoints.Parts(j)
	return p1
end

-- the rest pose: the joint's frame in the parent part (C0) and in the child part (C1)
function RigJoints.C0(j)
	if j:IsA("Motor6D") then
		return j.C0
	end
	local a = j.Attachment0
	return a and a.CFrame or I
end
function RigJoints.C1(j)
	if j:IsA("Motor6D") then
		return j.C1
	end
	local a = j.Attachment1
	return a and a.CFrame or I
end

-- the Transform the joint shows between its parts right now (child = parent * C0 * T * C1^-1), or nil
function RigJoints.Measure(j)
	local p0, p1 = RigJoints.Parts(j)
	if not (p0 and p1) then
		return nil
	end
	return RigJoints.C0(j):Inverse() * p0.CFrame:Inverse() * p1.CFrame * RigJoints.C1(j)
end

-- find the joint `name` ("Neck", "LeftHip"...) of an R15 model: the Motor6D or AnimationConstraint under the child part
-- (where both rig flavours keep it), else one under the parent part, else anywhere in the model by name and class
-- (an AnimationConstraint only when its attachments join the right two parts: a Ragdoll's or a gear's constraints never)
function RigJoints.Find(model, name)
	if not model then
		return nil
	end
	local childName, parentName = RigJoints.CHILD[name], RigJoints.PARENT[name]
	local child = childName and model:FindFirstChild(childName)
	local j = child and child:FindFirstChild(name)
	if RigJoints.IsJoint(j) then
		return j
	end
	local parent = parentName and model:FindFirstChild(parentName)
	j = parent and parent:FindFirstChild(name)
	if RigJoints.IsJoint(j) then
		return j
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == name and RigJoints.IsJoint(d) then
			if d:IsA("Motor6D") then
				return d
			end
			local p0, p1 = RigJoints.Parts(d)
			if p0 and p1 and (p0.Name == parentName or parentName == nil) and (p1.Name == childName or childName == nil) then
				return d
			end
		end
	end
	return nil
end

-- every R15 joint of the model by name (missing ones absent)
function RigJoints.All(model)
	local out = {}
	for _, name in ipairs(RigJoints.NAMES) do
		out[name] = RigJoints.Find(model, name)
	end
	return out
end

------------------------------------------------------------------------
-- EnsureMotors: an upgraded rig back on Motor6Ds
------------------------------------------------------------------------
-- the joint's rig attachment in a part ("LeftKnee" -> "LeftKneeRigAttachment"), when it is one
local function rigAttachment(part, name)
	local a = part and part:FindFirstChild(name .. "RigAttachment")
	return (a and a:IsA("Attachment")) and a or nil
end

-- does this Motor6D join p0 -> p1?
local function joins(m, p0, p1)
	return m:IsA("Motor6D") and m.Part0 == p0 and m.Part1 == p1
end

-- RigJoints.EnsureMotors(model, opts) -> converted, kept: every R15 joint of the model that is an AnimationConstraint
-- is replaced by a Motor6D of the same name under the same (child) part, Part0 / Part1 = the attachments' parts,
-- C0 / C1 = the attachments' CFrames, so the limbs stay exactly where they are. The new Motor6D is made and parented
-- BEFORE the constraint is destroyed (a Humanoid with RequiresNeck never sees the rig without a Neck). A joint that
-- already has a Motor6D joining the same two parts just loses the constraint (two rigid joints in a loop: one of them
-- would be ignored by the solver - maybe the one written). opts.localOnly (a client converting a replicated rig): the
-- Motor6D carries the attribute RigJointsLocal, and when the server's own Motor6D for the joint replicates in later
-- the local one is dropped (Dedupe). Safe to call any number of times; never throws for a half-built rig.
function RigJoints.EnsureMotors(model, opts)
	if not model then
		return 0, 0
	end
	local converted, kept = 0, 0
	for _, name in ipairs(RigJoints.NAMES) do
		local ok = pcall(function()
			local childName, parentName = RigJoints.CHILD[name], RigJoints.PARENT[name]
			local child, parent = model:FindFirstChild(childName), model:FindFirstChild(parentName)
			if not (child and parent and child:IsA("BasePart") and parent:IsA("BasePart")) then
				return
			end
			-- every AnimationConstraint of this joint (under the child part, the usual place, or the parent part)
			local acs, motor = {}, nil
			for _, holder in ipairs({ child, parent }) do
				for _, c in ipairs(holder:GetChildren()) do
					if c.Name == name and c:IsA("AnimationConstraint") then
						table.insert(acs, c)
					elseif c.Name == name and joins(c, parent, child) and not motor then
						motor = c
					end
				end
			end
			if #acs == 0 then
				if motor then
					kept += 1
				end
				return
			end
			if not motor then
				local ac = acs[1]
				local a0, a1 = ac.Attachment0, ac.Attachment1
				if not (a0 and a0.Parent == parent) then
					a0 = rigAttachment(parent, name)
				end
				if not (a1 and a1.Parent == child) then
					a1 = rigAttachment(child, name)
				end
				if not (a0 and a1) then
					return -- nothing to build the joint from: the constraint stays (better than a limb that falls off)
				end
				local m = Instance.new("Motor6D")
				m.Name = name
				m.Part0 = parent
				m.Part1 = child
				m.C0 = a0.CFrame
				m.C1 = a1.CFrame
				if opts and opts.localOnly then
					m:SetAttribute("RigJointsLocal", true)
				end
				m.Parent = child
			end
			for _, ac in ipairs(acs) do
				ac:Destroy()
			end
			converted += 1
		end)
		if not ok then
			-- (a part mid-replacement: the next call - the watcher's, the Animator's - finishes it)
			continue
		end
	end
	RigJoints.Dedupe(model)
	return converted, kept
end

-- two Motor6Ds for one joint (a client's local conversion, then the server's replicated one): the local one goes
function RigJoints.Dedupe(model)
	for _, name in ipairs(RigJoints.NAMES) do
		local child = model:FindFirstChild(RigJoints.CHILD[name])
		if child then
			local motors = {}
			for _, c in ipairs(child:GetChildren()) do
				if c.Name == name and c:IsA("Motor6D") then
					table.insert(motors, c)
				end
			end
			if #motors > 1 then
				local keep
				for _, m in ipairs(motors) do
					if m:GetAttribute("RigJointsLocal") ~= true then
						keep = m
						break
					end
				end
				keep = keep or motors[1]
				for _, m in ipairs(motors) do
					if m ~= keep and m:GetAttribute("RigJointsLocal") == true then
						m:Destroy()
					end
				end
			end
		end
	end
end

-- how many of the model's R15 joints are Motor6Ds / AnimationConstraints right now
function RigJoints.Count(model)
	local nm, na = 0, 0
	for _, name in ipairs(RigJoints.NAMES) do
		local j = RigJoints.Find(model, name)
		if j then
			if j:IsA("Motor6D") then
				nm += 1
			else
				na += 1
			end
		end
	end
	return nm, na
end

-- "Motor6D" / "AnimationConstraint" / "mixed" / "none": the rig's joint class, for Output lines
function RigJoints.Kind(model)
	local nm, na = RigJoints.Count(model)
	if nm > 0 and na > 0 then
		return "mixed", nm, na
	elseif na > 0 then
		return "AnimationConstraint", nm, na
	elseif nm > 0 then
		return "Motor6D", nm, na
	end
	return "none", nm, na
end

-- RigJoints.WatchMotors(model, opts): EnsureMotors now and again (deferred, coalesced) whenever an AnimationConstraint
-- named as an R15 joint arrives in the model later (ApplyDescription, ReplaceBodyPartR15 on a tier / head swap, a
-- respawn's parts). Once per model; the connection dies with the model.
local watched = setmetatable({}, { __mode = "k" })
RigJoints.MAX_ROUNDS = 40
function RigJoints.WatchMotors(model, opts)
	if not model or watched[model] then
		if model then
			RigJoints.EnsureMotors(model, opts)
		end
		return
	end
	watched[model] = true
	RigJoints.EnsureMotors(model, opts)
	local pending = false
	-- (an engine that put a constraint back every time one went would make this churn: past MAX_ROUNDS conversions in a
	-- model the watcher stops and says so - the client Animator's self-check still guards the animation)
	local rounds = 0
	local conn
	conn = model.DescendantAdded:Connect(function(d)
		-- (by class only: a constraint is often parented before it is named - EnsureMotors checks the names)
		if pending or not d:IsA("AnimationConstraint") then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			local conv = RigJoints.EnsureMotors(model, opts)
			if conv > 0 then
				rounds += 1
				if rounds >= RigJoints.MAX_ROUNDS then
					conn:Disconnect()
					warn(string.format("[RigJoints] %s: the engine keeps re-creating AnimationConstraint joints (%d rounds); no longer rebuilding them as Motor6Ds. "
						.. "Set StarterPlayer > AvatarJointUpgrade = Disabled in the place's Properties", model.Name, rounds))
				end
			end
		end)
	end)
end

-- the Animator's side for the diagnostic (client): Written(model, jointName) -> the Transform it last wrote, or nil;
-- Status(model) -> how it drives the rig ("procedural", "fallback: ..."). Set by Animator.client.lua; nil elsewhere
RigJoints.Written = nil
RigJoints.Status = nil

-- the angle (degrees) of a rotation
function RigJoints.Angle(cf)
	local _, ang = cf:ToAxisAngle()
	local a = math.abs(ang) % (2 * math.pi)
	if a > math.pi then
		a = 2 * math.pi - a
	end
	return math.deg(a)
end

return RigJoints
