-- RigJoints: one way to find and read an R15 rig's joints whatever class the engine gave them.
-- [Studio] Workspace.AvatarJointUpgrade (the Avatar Joint Upgrade rollout) builds player characters, NPCs made by
-- CreateHumanoidModelFromDescription and ApplyDescription'd rigs with an AnimationConstraint per joint instead of a
-- Motor6D: the constraint sits under the CHILD part (Head.Neck, LeftUpperLeg.LeftHip...), has no Part0 / Part1 / C0 / C1
-- but Attachment0 (in the parent part) / Attachment1 (in the child part) - the two RigAttachments - and a Transform
-- written exactly as a Motor6D's: child = parent * A0.CFrame * Transform * A1.CFrame^-1 (a Motor6D's
-- Part1 = Part0 * C0 * Transform * C1^-1 with C0 = A0.CFrame, C1 = A1.CFrame), so a pose written to either reads the
-- same. Reading .Part1 on an AnimationConstraint throws, and did: the Animator's rig measurement failed on every
-- upgraded rig in Studio (in setup, outside its per-frame pcall) and those rigs were never driven - feet sliding,
-- knees straight. Everything that touches a joint (the Animator, AnimRig, the client Ragdoll, Diag) goes through here.
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

return RigJoints
