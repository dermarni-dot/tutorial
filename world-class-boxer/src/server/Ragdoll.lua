-- Ragdoll (server): the physics side of a knockdown / knockout. The Animator (AnimDown) draws the fall on every
-- client with Motor6D Transforms laid on the canvas; this module makes sure the physics under it never lets the
-- body float, hover or slide, and hands the limbs to physics for the settle of an out-cold knockout.
--
--  * Hold(model, hum, root): the moment the knockdown starts. The root stops dead where he stands and holds its
--    height: velocity zeroed, the HumanoidRootPart anchored (no hover corrections, no residual walk, no push from
--    the other man), the Humanoid platform-standing with AutoRotate off, HipHeight untouched. Server-authoritative
--    for the player's own character too (an anchored part is simulated by the server). FightEngine's root walk
--    into the ropes / the corner (Glide: CFrame shifts) still works on it. Released when Guard leaves "down" (the
--    get-up, the end of the fight, Cleanup clearing the attributes) or the model goes.
--  * Release(model, opts): once the animated fall has landed (FightEngine waits FightMotion.KOFallWall), the
--    limbs go to physics: every body Motor6D but Root is replaced by a BallSocketConstraint with human limits
--    (a cone about the bone and a twist range per joint), invisible collision boxes are welded to the limbs (the
--    Humanoid keeps the R15 limbs themselves from colliding), the limbs start from rest where the animation left
--    them (within the limits, so nothing pops) and the punch's last push (opts.dir, opts.power) flops the head
--    and the gloves. The Root motor stays: the pelvis rests on the anchored root where the fall laid it, so
--    nothing falls through the canvas or drifts. Ownership: the server for an NPC, the player for his own
--    character (opts.owner).
--  * Restore(model): motors back on (the client Animator blends from the measured limb poses: client Ragdoll),
--    constraints / colliders gone, the root free, the Humanoid standing.
-- Everything is pcall-guarded: a stub rig (tools/sim/fightsim) or a rig without parts is a no-op.
local PhysicsService = game:GetService("PhysicsService")

local Ragdoll = {}

local held = {} -- model -> state

local GROUP = "BoxerRagdoll"
local groupReady = false
local function ensureGroup()
	if groupReady then
		return
	end
	groupReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
		-- the limbs of one body (and of two bodies) pass through each other: box colliders jostling each other
		-- jitter; the canvas is what they must not go through
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", true)
	end)
end

-- human joint ranges (degrees): { cone about the bone, twist about it }
Ragdoll.LIMITS = {
	Neck = { 35, 45 }, Waist = { 22, 25 },
	LeftShoulder = { 85, 45 }, RightShoulder = { 85, 45 },
	LeftElbow = { 70, 15 }, RightElbow = { 70, 15 },
	LeftWrist = { 35, 25 }, RightWrist = { 35, 25 },
	LeftHip = { 60, 25 }, RightHip = { 60, 25 },
	LeftKnee = { 70, 10 }, RightKnee = { 70, 10 },
	LeftAnkle = { 35, 15 }, RightAnkle = { 35, 15 },
}
-- the parts that get a collision box (the pelvis sits on the root: none)
local COLLIDE = {
	Head = true, UpperTorso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
-- the collider inside the drawn limb (the organic meshes are rounder than their part boxes: a box the part's size
-- would start inside the canvas the animation laid the mesh on, and the solver would throw the limb up)
local COL_SHRINK = Vector3.new(0.8, 0.82, 0.8)
-- the ball socket's cone is about the attachments' X axis; a limb's bone runs along its joint's Y
local AXIS = CFrame.Angles(0, 0, math.pi / 2)
-- the punch's last push, studs/s per unit of power, on the head and the gloves
local PUSH_HEAD, PUSH_HAND = 3.5, 2.5

local function motorsOf(model)
	local list = {}
	for _, m in ipairs(model:GetDescendants()) do
		-- only the R15 rig joints (cosmetic FaceJoint / HairJoint motors live deeper, under BoxerLook)
		if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Parent and m.Parent.Parent == model and Ragdoll.LIMITS[m.Name] then
			table.insert(list, m)
		end
	end
	return list
end

function Ragdoll.Hold(model, hum, root)
	if not model then
		return nil
	end
	local st = held[model]
	if st then
		return st
	end
	st = { model = model, hum = hum, root = root, conns = {}, made = {}, motors = {}, released = false }
	held[model] = st
	pcall(function()
		if root then
			st.wasAnchored = root.Anchored == true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
		end
	end)
	pcall(function()
		if hum then
			st.autoRotate = hum.AutoRotate == true
			st.platform = hum.PlatformStand == true
			hum.AutoRotate = false
			hum.PlatformStand = true
		end
	end)
	pcall(function()
		table.insert(st.conns, model:GetAttributeChangedSignal("Guard"):Connect(function()
			if model:GetAttribute("Guard") ~= "down" then
				Ragdoll.Restore(model)
			end
		end))
		table.insert(st.conns, model.Destroying:Connect(function()
			Ragdoll.Restore(model, true)
		end))
	end)
	return st
end

function Ragdoll.IsHeld(model)
	return held[model] ~= nil
end

function Ragdoll.IsReleased(model)
	local st = held[model]
	return st ~= nil and st.released
end

-- opts: dir (world, flat: the way the punch pushed him), power (0..1), owner (the Player for his own character)
function Ragdoll.Release(model, opts)
	opts = opts or {}
	local st = held[model]
	if not st then
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart")
		st = Ragdoll.Hold(model, hum, root)
	end
	if not st or st.released then
		return false
	end
	st.released = true
	ensureGroup()
	local ok, err = pcall(function()
		local hum = st.hum
		if hum then
			-- the Neck motor is disabled below: with RequiresNeck on the Humanoid would die, and BreakJointsOnDeath
			-- would then snap the cosmetic face / hair Motor6Ds under BoxerLook while the KO is on camera
			st.requiresNeck = hum.RequiresNeck
			hum.RequiresNeck = false
			hum.BreakJointsOnDeath = false
		end
		for _, m in ipairs(motorsOf(model)) do
			local lim = Ragdoll.LIMITS[m.Name]
			local a0 = Instance.new("Attachment")
			a0.Name = "RagA0"
			a0.CFrame = m.C0 * AXIS
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagA1"
			a1.CFrame = m.C1 * AXIS
			a1.Parent = m.Part1
			local bs = Instance.new("BallSocketConstraint")
			bs.Name = "Ragdoll"
			bs.Attachment0 = a0
			bs.Attachment1 = a1
			bs.LimitsEnabled = true
			bs.UpperAngle = lim[1]
			bs.TwistLimitsEnabled = true
			bs.TwistLowerAngle = -lim[2]
			bs.TwistUpperAngle = lim[2]
			bs.Restitution = 0
			bs.Parent = m.Part1
			table.insert(st.made, a0)
			table.insert(st.made, a1)
			table.insert(st.made, bs)
			table.insert(st.motors, m)
			m.Enabled = false
		end
		for name in pairs(COLLIDE) do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				local col = Instance.new("Part")
				col.Name = "RagCol"
				col.Size = part.Size * COL_SHRINK
				col.CFrame = part.CFrame
				col.Transparency = 1
				col.CanCollide = true
				col.CanQuery = false
				col.CanTouch = false
				col.Massless = true
				col.CastShadow = false
				col.CollisionGroup = GROUP
				local w = Instance.new("WeldConstraint")
				w.Part0 = part
				w.Part1 = col
				w.Parent = col
				col.Parent = part
				table.insert(st.made, col)
			end
		end
		-- from rest where the animation laid him, then the punch's last push: the head and the gloves flop
		local dir = opts.dir
		if dir and dir.Magnitude > 0.05 then
			dir = Vector3.new(dir.X, 0, dir.Z)
			dir = dir.Magnitude > 0.05 and dir.Unit or nil
		else
			dir = nil
		end
		local power = math.clamp(tonumber(opts.power) or 1, 0, 1.5)
		for _, m in ipairs(st.motors) do
			local p = m.Part1
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
		if dir then
			for _, m in ipairs(st.motors) do
				local p = m.Part1
				local k = (p.Name == "Head" and PUSH_HEAD) or ((p.Name == "LeftHand" or p.Name == "RightHand") and PUSH_HAND) or 0
				if k > 0 then
					p:ApplyImpulse(dir * (k * power * p:GetMass()))
				end
			end
		end
		-- ownership: the limbs are assemblies of their own now
		for _, m in ipairs(st.motors) do
			pcall(m.Part1.SetNetworkOwner, m.Part1, opts.owner)
		end
	end)
	if not ok then
		warn("[Ragdoll] release failed:", err)
	end
	return ok
end

function Ragdoll.Restore(model, gone)
	local st = held[model]
	if not st then
		return
	end
	held[model] = nil
	for _, c in ipairs(st.conns) do
		pcall(c.Disconnect, c)
	end
	if gone then
		return
	end
	pcall(function()
		for _, m in ipairs(st.motors) do
			if m.Parent then
				m.Enabled = true
			end
		end
		for _, inst in ipairs(st.made) do
			if inst.Parent then
				inst:Destroy()
			end
		end
		-- (RequiresNeck stays off: FightEngine.RestorePlayer requires the neck again later, once every client has the
		-- motors back; an NPC goes with the arena)
	end)
	pcall(function()
		local root = st.root
		if root then
			root.Anchored = st.wasAnchored == true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end)
	pcall(function()
		local hum = st.hum
		if hum then
			hum.PlatformStand = st.platform == true
			hum.AutoRotate = st.autoRotate == true
		end
	end)
end

return Ragdoll
