-- HairFX: hair that moves like hair. Client-only, driven by the Animator every frame.
--  * HairSway Motor6Ds (hair chains, braids, locs, ponytails, boot lace tails, frayed wrap ends):
--    a damped spring per joint, excited by the joint pivot's real motion (finite differences of
--    its world frame, so it sees Transform-driven head snaps, slips and rolls, anchored trainees
--    and knockdowns, not just the physics velocity), with angular lag when the head turns and a
--    gravity bias so hair hangs towards the floor when the head tilts (bench, pull-up, canvas).
--    Stiff (0..1), Mass (0.5..2) and the owner's Sweat (wet hair is heavier and clumps) shape it.
--  * HairBounce clusters (afros, curls): a vertical / lateral jiggle of the whole mass
--  * HairStrand Beams: curve sway from the head's motion (Beam properties only)
--  * HairFX.Impulse(model, x, z, amount): an extra whip when the head is hit
-- LOD: every frame under 25 studs, every 2nd frame to 60, frozen (eased back to rest) beyond,
-- skipped off screen. No per-frame allocation (CFrames are values).
local CollectionService = game:GetService("CollectionService")

local K = require(script.Parent:WaitForChild("AnimKit"))

local HairFX = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local sin, abs, min, max, sqrt = math.sin, math.abs, math.min, math.max, math.sqrt
local clamp = math.clamp
local DOWN = Vector3.new(0, -1, 0)

local NEAR, MID = 25, 60
local MAXA = 1.15 -- rad: a hair joint never swings further than this
local owners = {} -- model -> { joints = {}, strands = {}, head, ... }

local function ownerOf(inst)
	return inst:FindFirstAncestorOfClass("Model")
end

local function getOwner(model)
	local o = owners[model]
	if not o then
		o = {
			model = model, joints = {}, strands = {}, head = nil, nextAttr = 0, sweat = 0,
			hx = 0, hz = 0, hy = 0, lastPos = nil, vel = Vector3.zero, frame = 0, rest = true,
			kick = 0,
		}
		owners[model] = o
	end
	return o
end

-- the part the chain hangs from (head, shoe, hand): walk up through hair segments
local function chainAnchor(m)
	local p = m.Part0
	for _ = 1, 40 do
		if not p then
			return nil
		end
		local up
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("Motor6D") and c.Part1 == p and CollectionService:HasTag(c, "HairSway") then
				up = c
				break
			end
		end
		if not up then
			return p
		end
		p = up.Part0
	end
	return p
end

local function addJoint(m)
	if not m:IsA("Motor6D") then
		return
	end
	local model = ownerOf(m)
	if not model then
		return
	end
	local o = getOwner(model)
	local depth = m:GetAttribute("Depth") or 1
	local stiff = m:GetAttribute("Stiff")
	local mass = m:GetAttribute("Mass")
	local j = {
		m = m, depth = depth, stiff = type(stiff) == "number" and clamp(stiff, 0, 1) or 0.35,
		mass = type(mass) == "number" and clamp(mass, 0.3, 3) or 1, bounce = m:GetAttribute("Bounce") == true,
		x = 0, z = 0, y = 0, vx = 0, vz = 0, vy = 0, anchor = nil, prevCF = nil, prevVel = Vector3.zero,
		phase = (#o.joints * 1.37) % 6.28, written = false,
		-- head hair / beard only: B's boot-lace tails and wrap ends share the HairSway tag but must not
		-- be whipped by a punch to the head (they keep their motion-driven sway)
		hair = m:FindFirstAncestor("Hair") ~= nil or m:FindFirstAncestor("Beard") ~= nil,
	}
	j.anchor = chainAnchor(m)
	table.insert(o.joints, j)
end

local function addStrand(b)
	if not b:IsA("Beam") then
		return
	end
	local model = ownerOf(b)
	if not model then
		return
	end
	local o = getOwner(model)
	local c0 = b:GetAttribute("BaseCurve0")
	local c1 = b:GetAttribute("BaseCurve1")
	table.insert(o.strands, {
		b = b, c0 = type(c0) == "number" and c0 or b.CurveSize0, c1 = type(c1) == "number" and c1 or b.CurveSize1,
		depth = b:GetAttribute("Depth") or 1, phase = (#o.strands * 2.11) % 6.28, last0 = nil, last1 = nil,
	})
end

-- whip the hair: (x, z) = the direction the hair is flung in head space (+x = the head's right,
-- +z = backwards), e.g. forward when a jab snaps the head back
function HairFX.Impulse(model, x, z, amount)
	local o = owners[model]
	if not o then
		return
	end
	amount = amount or 1
	for _, j in ipairs(o.joints) do
		if j.hair then
			local k = amount * (0.6 + 0.25 * j.depth) / j.mass
			-- Angles(+x) swings a segment's tip forward (-Z), Angles(0, 0, +z) to the right (+X)
			j.vx -= (z or 0) * 6 * k
			j.vz += (x or 0) * 6 * k
			if j.bounce then
				j.vy += 3 * k
			end
		end
	end
	o.kick = amount
end

local function relax(o)
	for _, j in ipairs(o.joints) do
		j.x, j.z, j.y, j.vx, j.vz, j.vy = 0, 0, 0, 0, 0, 0
		j.prevCF = nil
		if j.written and j.m.Parent then
			j.m.Transform = I
		end
		j.written = false
	end
	for _, s in ipairs(o.strands) do
		if s.last0 and s.b.Parent then
			s.b.CurveSize0 = s.c0
			s.b.CurveSize1 = s.c1
		end
		s.last0, s.last1 = nil, nil
	end
	o.lastPos = nil
	o.rest = true
end

local function stepJoint(j, dt, sweat, t)
	local m = j.m
	local p0 = m.Part0
	if not p0 then
		return
	end
	-- the joint pivot in world space (its parent segment already carries last frame's swing)
	local pivot = p0.CFrame * m.C0
	local pos = pivot.Position
	local ax, az, ay = 0, 0, 0
	if j.prevCF then
		local vel = (pos - j.prevCF.Position) / dt
		local acc = (vel - j.prevVel) / dt
		j.prevVel = vel
		if acc.Magnitude > 4000 or vel.Magnitude > 200 then
			-- teleport (Poser.Place, respawn): start over
			acc = Vector3.zero
			j.prevVel = Vector3.zero
		end
		local la = pivot:VectorToObjectSpace(acc)
		-- inertia: the tip lags behind the pivot's acceleration (see AnimKit tests for signs)
		ax, az, ay = la.Z, -la.X, -la.Y
		-- angular lag: when the frame turns, the hair wants to stay where it was
		local rel = j.prevCF:ToObjectSpace(pivot)
		local rx, _, rz = rel:ToEulerAnglesXYZ()
		if abs(rx) < 0.5 and abs(rz) < 0.5 then
			j.vx -= rx / dt * 0.35
			j.vz -= rz / dt * 0.35
		end
	end
	j.prevCF = pivot
	-- gravity bias: how far gravity pulls away from the built shape (built with the anchor upright)
	local gx, gz = 0, 0
	local anchor = j.anchor
	if anchor and anchor.Parent then
		local g = pivot:VectorToObjectSpace(DOWN)
		local gu = pivot:VectorToObjectSpace(-anchor.CFrame.UpVector)
		local a1, b1 = K.gravityAngles(g.X, g.Y, g.Z)
		local a2, b2 = K.gravityAngles(gu.X, gu.Y, gu.Z)
		-- every joint measures the full deviation in its own frame, so the root joint takes most of
		-- it and deeper joints only add a little curve (otherwise long chains over-rotate)
		local gw = (j.depth <= 1 and 0.62 or 0.5 / (j.depth * j.depth)) * (1 - 0.65 * j.stiff)
		gx = clamp(K.wrap(a1 - a2), -1.4, 1.4) * gw
		gz = clamp(K.wrap(b1 - b2), -1.4, 1.4) * gw
	end
	local wet = 1 + sweat * 0.8 -- wet hair: heavier, damped
	local mass = j.mass * wet
	local kk = (70 + 180 * j.stiff) / mass / (1 + 0.18 * (j.depth - 1))
	local cc = K.damping(kk, 0.22 + 0.35 * j.stiff + 0.25 * sweat)
	local gain = 0.0045 / (0.6 + 0.4 * j.stiff) * min(1.6, 0.7 + 0.2 * j.depth)
	-- a light idle drift so long hair is never perfectly frozen
	local idle = (0.02 + 0.015 * j.depth) * (1 - j.stiff)
	local tx = gx + idle * sin(t * 1.6 + j.phase)
	local tz = gz + idle * 0.7 * sin(t * 1.1 + j.phase * 1.7)
	j.vx += ax * gain * kk * dt
	j.vz += az * gain * kk * dt
	j.x, j.vx = K.spring(j.x, j.vx, tx, kk, cc, dt)
	j.z, j.vz = K.spring(j.z, j.vz, tz, kk, cc, dt)
	if abs(j.x) > MAXA then
		j.x = clamp(j.x, -MAXA, MAXA)
		j.vx *= -0.3
	end
	if abs(j.z) > MAXA then
		j.z = clamp(j.z, -MAXA, MAXA)
		j.vz *= -0.3
	end
	if j.bounce then
		-- a curl cluster jiggles as one mass (mostly up and down)
		j.vy += ay * 0.0016 * kk * dt
		j.y, j.vy = K.spring(j.y, j.vy, 0, kk * 1.6, cc * 1.2, dt)
		j.y = clamp(j.y, -0.12, 0.12)
		m.Transform = CF(j.z * -0.04, j.y, j.x * -0.04) * A(j.x * 0.25, 0, j.z * 0.25)
	else
		m.Transform = A(j.x, 0, j.z)
	end
	j.written = true
end

local frame = 0
function HairFX.Update(dt, t, camPos, cam)
	frame += 1
	for model, o in pairs(owners) do
		if not model.Parent then
			owners[model] = nil
			continue
		end
		-- drop joints / strands whose parts were rebuilt
		local js = o.joints
		for i = #js, 1, -1 do
			if not js[i].m.Parent then
				table.remove(js, i)
			end
		end
		local ss = o.strands
		for i = #ss, 1, -1 do
			if not ss[i].b.Parent then
				table.remove(ss, i)
			end
		end
		if #js == 0 and #ss == 0 then
			owners[model] = nil
			continue
		end
		local head = o.head
		if not head or not head.Parent then
			head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
			o.head = head
			if not head then
				continue
			end
		end
		local hp = head.Position
		local dist = (hp - camPos).Magnitude
		local onScreen = true
		if cam and dist > 6 then
			local _, vis = cam:WorldToViewportPoint(hp)
			onScreen = vis
		end
		if dist > MID or not onScreen then
			if not o.rest and dist > MID then
				relax(o)
			end
			continue
		end
		local step = dist < NEAR and 1 or 2
		o.frame += 1
		if o.frame % step ~= 0 then
			continue
		end
		local sdt = min(dt * step, 1 / 15)
		o.rest = false
		if t >= o.nextAttr then
			o.nextAttr = t + 0.5
			local sw = model:GetAttribute("Sweat")
			o.sweat = type(sw) == "number" and clamp(sw, 0, 1) or 0
		end
		for _, j in ipairs(js) do
			stepJoint(j, sdt, o.sweat, t)
		end
		-- strands: sway from the head's own motion (head space), only up close
		if #ss > 0 and dist < NEAR then
			local hv = Vector3.zero
			if o.lastPos then
				hv = head.CFrame:VectorToObjectSpace((hp - o.lastPos) / sdt)
			end
			o.lastPos = hp
			local a = 1 - math.exp(-sdt * 6)
			o.hx += (clamp(hv.X, -12, 12) - o.hx) * a
			o.hz += (clamp(hv.Z, -12, 12) - o.hz) * a
			o.hy += (clamp(hv.Y, -12, 12) - o.hy) * a
			local motion = (abs(o.hx) + abs(o.hz) + abs(o.hy)) * 0.04 + o.kick
			o.kick = max(0, o.kick - sdt * 2)
			local wet = 1 - 0.5 * o.sweat
			for _, s in ipairs(ss) do
				local amp = (0.06 + min(motion, 0.6)) * (0.5 + 0.25 * s.depth) * wet
				local wob = sin(t * (2.2 + 0.4 * s.depth) + s.phase)
				local k0 = 1 + amp * 0.25 * wob
				local k1 = 1 + amp * (0.6 * wob + 0.02 * o.hy)
				local v0 = math.floor(s.c0 * k0 * 200 + 0.5) / 200
				local v1 = math.floor(s.c1 * k1 * 200 + 0.5) / 200
				if v0 ~= s.last0 or v1 ~= s.last1 then
					s.last0, s.last1 = v0, v1
					s.b.CurveSize0 = v0
					s.b.CurveSize1 = v1
				end
			end
		end
	end
end

CollectionService:GetInstanceAddedSignal("HairSway"):Connect(addJoint)
CollectionService:GetInstanceAddedSignal("HairStrand"):Connect(addStrand)
for _, m in ipairs(CollectionService:GetTagged("HairSway")) do
	addJoint(m)
end
for _, b in ipairs(CollectionService:GetTagged("HairStrand")) do
	addStrand(b)
end

return HairFX
