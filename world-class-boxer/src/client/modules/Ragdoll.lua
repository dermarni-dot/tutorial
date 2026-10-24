-- Ragdoll (client): the Animator's side of a knockout's physics ragdoll (server Ragdoll: the limbs' Motor6Ds
-- disabled, ball sockets with human limits, collision boxes; the pelvis on the anchored root).
--  * sync(rig, t): called every frame a fighter is down / getting up (AnimDown). While any body joint is released
--    the joint's filtered state follows the limb's measured pose (in Motor6D Transform space), so the Animator's
--    output, the face / hair FX and the KO camera read where physics really put the limbs, and when the motors
--    come back (Restore: the end of the fight, a get-up) the Animator's filter blends from the ragdoll's last pose
--    into the animated one instead of popping. The local player's own Humanoid goes to the Physics state while
--    released (the client owns its Humanoid state) and gets up when it ends. Returns true while released.
--  * limp(rig, p): the limbs' measured poses into a pose table (the get-up's capture).
--  * released(rig): the ragdoll state, nil when the limbs are the Animator's
-- No physics is simulated here; nothing is created. A rig outside Workspace, or an engine without the
-- constraints (tools/sim), never releases: the procedural fall is all there is.
local Ragdoll = {}

local I = CFrame.identity
local HST = Enum.HumanoidStateType
-- [Studio] Motor6D or AnimationConstraint joints (Workspace.AvatarJointUpgrade): Shared.RigJoints reads either
local RigJoints = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RigJoints"))

-- the limb's pose as the joint would show it: child = parent * C0 * Transform * C1^-1
local function measure(m)
	return RigJoints.Measure(m)
end

local function isReleased(m)
	return m ~= nil and m.Parent ~= nil and RigJoints.IsJoint(m) and m.Enabled == false
end

function Ragdoll.released(rig)
	return rig.ragdoll
end

function Ragdoll.sync(rig, t)
	local joints = rig.joints
	if not joints then
		return false
	end
	local any = false
	for k, j in pairs(joints) do
		if k ~= "Root" and isReleased(j.motor) then
			local cf = measure(j.motor)
			if cf then
				any = true
				j.cur = cf
				j.base = cf
			end
		end
	end
	local st = rig.ragdoll
	if any then
		if not st then
			st = { since = t }
			rig.ragdoll = st
			if rig.isLocal and rig.hum then
				pcall(function()
					rig.hum:ChangeState(HST.Physics)
				end)
			end
		end
	elseif st then
		rig.ragdoll = nil
		rig.ragdollEnd = t
		if rig.isLocal and rig.hum then
			pcall(function()
				rig.hum:ChangeState(HST.GettingUp)
			end)
		end
	end
	return any
end

function Ragdoll.limp(rig, p)
	local joints = rig.joints
	if not joints then
		return p
	end
	for k, j in pairs(joints) do
		if k ~= "Root" and isReleased(j.motor) then
			p[k] = measure(j.motor) or p[k] or I
		end
	end
	return p
end

function Ragdoll.clear(rig)
	rig.ragdoll = nil
end

return Ragdoll
