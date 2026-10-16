-- HairFX: hair that moves like hair. Client-only, driven by the Animator every frame (HairFX.Update) and on
-- hits / punches (HairFX.Impulse).
-- Mesh hair (AnatomyHair pieces built by AnatomyClient; ANATOMY_CONTRACTS section 11): every moving piece's
-- mesh carries mesh.hairfx = { kind = "swing" | "bounce", chain, seg, parent, stiff, mass, pivot, tip } (head
-- space). Rigid motion only: one AnatomyClient.SetPieceTransform (a Weld.C0 write) per piece per frame.
--  * swing (long hair, locs, braids, twists, ponytails, long curls): a 2-axis damped spring per piece about its
--    pivot, excited by the pivot's real acceleration (finite differences of its world position: head snaps,
--    slips, running, knockdowns), pulled toward gravity when the head tilts, with a light wind and idle drift;
--    a group's lower segment ("b") hangs from the upper one (chain composition) and lags it
--  * bounce (afros, coily volumes, curls, short locs, mohawks, puffs): a vertical spring (compress / spring
--    back) plus a small tilt, driven by vertical / lateral acceleration and impulses
--  * swinging hair stays out of the body: with the organic body (AnatomyClient's Body section) a few sample
--    points of each segment (its outermost vertices along and across it) are tested against radial maps of the
--    upper torso, upper arms, forearms and gloves made from their own meshes, and a hit swings the segment about
--    its pivot (the smallest swing that clears it). A part-built body: the tips against a proxy of its boxes
--  * hair rests on the canvas: near the floor (knockdowns, get-ups) each segment's lowest point keeps above it,
--    curl and coil clusters lift off it a little
--  * wet hair (the model's Sweat attribute): heavier and more damped, darker and a touch shinier. Vertex
--    coloured pieces darken through MeshPart.Color; a textured piece (the cap) through its own texture (a
--    part's Color does not tint a texture): its original pixels are read once and each wetness step rewrites
--    the image from them, a few rows per frame
-- Round-1 hair (the part-built fallback, CONTRACTS section 5) keeps its behaviour:
--  * HairSway Motor6Ds (hair chains, braids, locs, ponytails, boot lace tails, frayed wrap ends): a damped
--    spring per joint, excited by the joint pivot's motion, gravity bias, Stiff / Mass / Sweat
--  * HairBounce clusters: a vertical / lateral jiggle; HairStrand Beams: curve sway from the head's motion
--  * only what a mesh hides rests: BoxerLook.Hair while the model has mesh hair, any other chain whose
--    segment AnatomyClient replaced (a mesh beard); boot laces and wrap ends keep swinging
-- HairFX.Impulse(model, x, z, amount): an extra whip ((x, z) = the direction the hair is flung in head space,
-- +x = the head's right, +z = backwards).
-- LOD: every frame under 25 studs, every 2nd frame to 60, frozen (eased back to rest) beyond, skipped off
-- screen (the motion history is dropped there, so a model coming back on screen gets no false whip). No
-- per-frame allocation: the pivot frames are built once per piece; CFrame products are the only temporaries.
-- Round-1 cost (a default Short Dreads head is ~50 joints, two fighters ~100): Part0 / C0 / spring constants
-- are cached per joint (refreshed twice a second), each chain's anchor is read once per model step, deeper
-- segments step at half rate, settled joints under a still anchor idle at a lower rate, at most SIM_ROOTS
-- roots + SIM_DEEP deeper head-hair joints are simulated per model (the rest follow a simulated neighbour /
-- their parent segment) and sub-0.1 degree changes are not written.
local CollectionService = game:GetService("CollectionService")

local K = require(script.Parent:WaitForChild("AnimKit"))

-- AnatomyClient is optional: without it (or with meshes off) only the round-1 hair moves
local Anatomy
do
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild("AnatomyClient", 5))
	end)
	if ok and type(mod) == "table" then
		Anatomy = mod
	end
end

local HairFX = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local sin, cos, abs, min, max, sqrt, exp, floor = math.sin, math.cos, math.abs, math.min, math.max, math.sqrt, math.exp, math.floor
local clamp = math.clamp
local DOWN = Vector3.new(0, -1, 0)

local NEAR, MID = 25, 60
-- per Graphics level (BoxerClient.Perf: 1 Low, 2 Medium, 3 High): hair moves at full rate inside near, at half
-- rate up to mid, rests beyond; your own hair and the fighters' keep High's at every level
local LEVELS = { { near = 15, mid = 30 }, { near = 20, mid = 45 }, { near = NEAR, mid = MID } }
local HIGH = LEVELS[3]
local lv = HIGH
do
	local m = script.Parent:FindFirstChild("Perf")
	local ok, Perf = false, nil
	if m then
		ok, Perf = pcall(require, m)
	end
	if ok and type(Perf) == "table" and Perf.Level and Perf.Changed then
		local function pick()
			lv = LEVELS[math.clamp(tonumber(Perf.Level()) or 3, 1, 3)]
		end
		pick()
		Perf.Changed:Connect(pick)
	end
end
local MAXA = 1.15 -- rad: a hair joint never swings further than this
local FWD = 0.35 -- rad: a mesh hair segment never swings further toward the face than this
local WET_ROWS = 16 -- texture rows rewritten per frame for the wet look (256 / 128 are multiples)
local SIM_ROOTS = 16 -- head-hair chain roots simulated per model; the others follow a simulated neighbour
local SIM_DEEP = 12 -- deeper head-hair segments simulated per model; the others bend with their parent
local QUIET_ACC, QUIET_ROT = 3, 0.35 -- an anchor this still (studs/s^2, rad/s) lets settled joints idle slower
local WRITE_EPS = 0.0015 -- rad: a joint whose swing changed less than this keeps last frame's Transform
local owners = {} -- model -> { joints = {}, strands = {}, head, ... } (round-1 hair)
local meshes = {} -- model -> { pieces = { list }, byName = {}, head, sweat, ... } (mesh hair)
local bodies = {} -- model -> { shapes = { list } } (the organic body's radial maps)

------------------------------------------------------------------------
-- Round-1 hair (part-built fallback)
------------------------------------------------------------------------
local function ownerOf(inst)
	return inst:FindFirstAncestorOfClass("Model")
end

local function getOwner(model)
	local o = owners[model]
	if not o then
		o = {
			model = model, joints = {}, strands = {}, head = nil, nextAttr = 0, sweat = 0,
			hx = 0, hz = 0, hy = 0, lastPos = nil, vel = Vector3.zero, frame = 0, rest = true,
			kick = 0, tick = 0, dirty = true, fresh = true, nextScan = 0, sweatK = -1,
			-- the parts chains hang from (head, shoe, hand): read once per step for every joint on them
			anchors = {}, anchorList = {},
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
		-- in BoxerLook.Hair: hidden (and left at rest) while the model has mesh hair
		inHair = m:FindFirstAncestor("Hair") ~= nil,
		-- its segment is hidden by another mesh (AnatomyClient.IsReplaced, refreshed twice a second)
		replaced = false,
		-- cached (refreshed twice a second): the parent part, the static joint offset, spring constants
		p0 = m.Part0, c0 = m.C0, kk = 0, cc = 0, gain = 0, idle = 0, gw = 0,
		-- last written swing, last target, update slot (spreads the slower joints over frames)
		wx = 0, wz = 0, wy = 0, tx = 0, tz = 0, slot = #o.joints % 4,
		-- nil = simulated; else the joint record this one copies (scaled by followK)
		leader = nil, followK = 1,
	}
	local anchor = chainAnchor(m)
	j.anchor = anchor
	if anchor then
		local a = o.anchors[anchor]
		if not a then
			a = { part = anchor, ok = false, cf = I, down = DOWN, pos = nil, vel = Vector3.zero, look = nil, up = nil, quiet = false,
				tick = -1 }
			o.anchors[anchor] = a
			table.insert(o.anchorList, a)
		end
		j.arec = a
	end
	table.insert(o.joints, j)
	o.dirty = true
	o.fresh = true
end

-- spring constants for a joint at this wetness (cached: they change only with Sweat)
local function jointConsts(j, sweat)
	local mass = j.mass * (1 + sweat * 0.8) -- wet hair: heavier, damped
	local d = j.depth
	j.kk = (70 + 180 * j.stiff) / mass / (1 + 0.18 * (d - 1))
	j.cc = K.damping(j.kk, 0.22 + 0.35 * j.stiff + 0.25 * sweat)
	j.gain = 0.0045 / (0.6 + 0.4 * j.stiff) * min(1.6, 0.7 + 0.2 * d)
	-- a light idle drift so long hair is never perfectly frozen
	j.idle = (0.02 + 0.015 * d) * (1 - j.stiff)
	-- every joint measures the full gravity deviation in its own frame, so the root joint takes most of it and
	-- deeper joints only add a little curve (otherwise long chains over-rotate)
	j.gw = (d <= 1 and 0.62 or 0.5 / (d * d)) * (1 - 0.65 * j.stiff)
end

-- which head-hair joints are simulated: up to SIM_ROOTS roots and SIM_DEEP deeper segments, spread evenly over
-- the build order (locs are built in sweeps across the head, so a follower's neighbour hangs next to it). A root
-- that is not simulated copies the previous simulated root; a deeper segment its parent segment, softened.
-- Boot laces, wrap ends and bounce clusters are few and always simulated.
local function assignLeaders(o)
	o.dirty = false
	local roots, deep, byPart1 = {}, {}, {}
	for _, j in ipairs(o.joints) do
		j.leader = nil
		local p1 = j.m.Part1
		if p1 then
			byPart1[p1] = j
		end
		if j.hair and not j.bounce then
			table.insert(j.depth <= 1 and roots or deep, j)
		end
	end
	-- shallower segments first: a depth-2 segment matters more than a tip
	table.sort(deep, function(a, b)
		return a.depth < b.depth
	end)
	local function spread(list, cap, follow)
		local n = #list
		if n <= cap then
			return
		end
		local last
		for i, j in ipairs(list) do
			-- i is simulated where the even spacing cap / n passes an integer (the first one always is)
			if floor((i - 1) * cap / n) ~= floor((i - 2) * cap / n) then
				last = j
			else
				follow(j, last)
			end
		end
	end
	spread(roots, SIM_ROOTS, function(j, last)
		j.leader, j.followK = last, 0.9
	end)
	spread(deep, SIM_DEEP, function(j)
		local parent = j.p0 and byPart1[j.p0]
		if parent and parent ~= j then
			j.leader, j.followK = parent, 0.35
		end
	end)
end

-- an anchor's frame for this step (one CFrame read for all the joints hanging from it; a chain root's pivot
-- builds on it) and whether it is still enough that settled joints may idle at a lower rate
local function anchorStep(a, dt, tick)
	local part = a.part
	-- the motion history only holds across consecutive steps
	if a.tick ~= tick - 1 then
		a.pos = nil
	end
	a.tick = tick
	if not part.Parent then
		a.ok = false
		return
	end
	local cf = part.CFrame
	local pos, look, up = cf.Position, cf.LookVector, cf.UpVector
	a.ok = true
	a.cf = cf
	a.down = -up
	local quiet = false
	if a.pos then
		local vel = (pos - a.pos) / dt
		local acc = (vel - a.vel).Magnitude / dt
		a.vel = vel
		-- small-angle turn rate from how far the look / up axes moved
		local turn = max((look - a.look).Magnitude, (up - a.up).Magnitude) / dt
		quiet = acc < QUIET_ACC and turn < QUIET_ROT
	end
	a.pos, a.look, a.up = pos, look, up
	a.quiet = quiet
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
	o.fresh = true
end

-- cumulative counters (diagnostics; read-only for callers): simulated joint steps, follower copies, writes
local jointStats = { steps = 0, follows = 0, writes = 0 }
HairFX.JointStats = jointStats

local function restJoint(j)
	j.x, j.z, j.y, j.vx, j.vz, j.vy = 0, 0, 0, 0, 0, 0
	j.prevCF = nil
	j.prevVel = Vector3.zero
	if j.written and j.m.Parent then
		j.m.Transform = I
	end
	j.written = false
	j.wx, j.wz, j.wy = 0, 0, 0
end

-- write a joint's swing (skipped when it moved less than WRITE_EPS since the last write)
local function writeJoint(j)
	local x, z = j.x, j.z
	if j.bounce then
		local y = j.y
		if j.written and abs(x - j.wx) + abs(z - j.wz) + abs(y - j.wy) * 10 < WRITE_EPS then
			return
		end
		j.wy = y
		j.m.Transform = CF(z * -0.04, y, x * -0.04) * A(x * 0.25, 0, z * 0.25)
	else
		if j.written and abs(x - j.wx) + abs(z - j.wz) < WRITE_EPS then
			return
		end
		j.m.Transform = A(x, 0, z)
	end
	j.wx, j.wz = x, z
	j.written = true
	jointStats.writes += 1
end

local function restStrands(o)
	for _, s in ipairs(o.strands) do
		if s.last0 and s.b.Parent then
			s.b.CurveSize0 = s.c0
			s.b.CurveSize1 = s.c1
		end
		s.last0, s.last1 = nil, nil
	end
	o.lastPos = nil
end

local function relax(o)
	for _, j in ipairs(o.joints) do
		restJoint(j)
	end
	restStrands(o)
	o.rest = true
end

local atan2 = math.atan2

local function stepJoint(j, dt, t)
	local p0 = j.p0
	if not p0 then
		return
	end
	jointStats.steps += 1
	-- the joint pivot in world space (its parent segment already carries last frame's swing); a chain root
	-- hangs from the anchor, whose frame this step already read
	local a = j.arec
	local pivot = ((a and a.ok and p0 == a.part) and a.cf or p0.CFrame) * j.c0
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
	-- gravity bias: how far gravity pulls away from the built shape (built with the anchor upright).
	-- K.gravityAngles inlined (atan2(-z, -y), atan2(x, -y)) for world down and for the anchor's down
	local gx, gz = 0, 0
	if a and a.ok then
		local g = pivot:VectorToObjectSpace(DOWN)
		local gu = pivot:VectorToObjectSpace(a.down)
		gx = clamp(K.wrap(atan2(-g.Z, -g.Y) - atan2(-gu.Z, -gu.Y)), -1.4, 1.4) * j.gw
		gz = clamp(K.wrap(atan2(g.X, -g.Y) - atan2(gu.X, -gu.Y)), -1.4, 1.4) * j.gw
	end
	local kk, cc, gain, idle = j.kk, j.cc, j.gain, j.idle
	local tx = gx + idle * sin(t * 1.6 + j.phase)
	local tz = gz + idle * 0.7 * sin(t * 1.1 + j.phase * 1.7)
	j.tx, j.tz = tx, tz
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
	end
	writeJoint(j)
end

-- a settled joint (at its target, barely moving): under a still anchor only its idle drift is left to integrate
local function settled(j)
	return abs(j.vx) + abs(j.vz) + abs(j.vy) < 0.08 and abs(j.x - j.tx) + abs(j.z - j.tz) < 0.02
end

------------------------------------------------------------------------
-- Mesh hair
------------------------------------------------------------------------
-- slow, smooth wind (world space, studs/s^2-ish forcing): two incommensurate gust cycles
local function windAt(t, seed)
	local gx = 0.6 * sin(t * 0.31 + seed) + 0.4 * sin(t * 0.83 + seed * 2.3) + 0.25 * sin(t * 1.9 + seed * 0.7)
	local gz = 0.5 * cos(t * 0.27 + seed * 1.4) + 0.35 * sin(t * 0.71 + seed * 0.4)
	return gx, gz
end

-- texture rows rewritten for the wet look so far (diagnostics; read-only for callers)
local wetStats = { rows = 0 }
HairFX.WetStats = wetStats

-- a textured piece's wet look: start rewriting its image at wetness q (the original pixels are read once)
local function wetTexture(e, q)
	local img = e.image
	if not img then
		return
	end
	if not e.orig then
		if q <= 0.001 then
			return
		end
		local ok, buf = pcall(function()
			return img:ReadPixelsBuffer(Vector2.zero, img.Size)
		end)
		local size = ok and img.Size
		if not ok or typeof(buf) ~= "buffer" or size.X < 1 or size.Y % WET_ROWS ~= 0 then
			e.image = nil
			return
		end
		e.orig, e.tw, e.th = buf, size.X, size.Y
		e.rows = buffer.create(size.X * WET_ROWS * 4)
		e.rowSize = Vector2.new(size.X, WET_ROWS)
		e.rowPos = {}
		for r = 0, size.Y - WET_ROWS, WET_ROWS do
			e.rowPos[#e.rowPos + 1] = Vector2.new(0, r)
		end
		e.lut = table.create(256, 0)
	end
	-- a darker multiplier (wet hair loses its scattered light), as a lookup table for this level
	local k = 1 - 0.28 * q
	for i = 0, 255 do
		e.lut[i + 1] = math.floor(i * k + 0.5)
	end
	e.wetQ, e.wetChunk = q, 1
end

-- rewrite the next WET_ROWS rows of a piece's texture from its original pixels (one chunk per frame)
local function stepWetTexture(e)
	local chunk = e.wetChunk
	local pos = e.rowPos and e.rowPos[chunk]
	if not pos then
		e.wetChunk = nil
		return
	end
	local src, dst, lut = e.orig, e.rows, e.lut
	local base = (chunk - 1) * WET_ROWS * e.tw * 4
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	for o = 0, e.tw * WET_ROWS * 4 - 4, 4 do
		writeu8(dst, o, lut[readu8(src, base + o) + 1])
		writeu8(dst, o + 1, lut[readu8(src, base + o + 1) + 1])
		writeu8(dst, o + 2, lut[readu8(src, base + o + 2) + 1])
		writeu8(dst, o + 3, readu8(src, base + o + 3))
	end
	local ok = pcall(e.image.WritePixelsBuffer, e.image, pos, e.rowSize, dst)
	if not ok then
		-- the image went away with its piece (a rebuild): stop
		e.image, e.wetChunk = nil, nil
		return
	end
	wetStats.rows += WET_ROWS
	e.wetChunk = chunk + 1
	if chunk + 1 > #e.rowPos then
		e.wetChunk = nil
		if e.wetQ <= 0.001 then
			-- dry again: the original pixels are back, drop the copy
			e.orig, e.rows, e.rowPos = nil, nil, nil
		end
	end
end

local function setWet(rec, q)
	rec.wetApplied = q
	for _, p in ipairs(rec.list) do
		local part = p.part
		if part and part.Parent then
			-- a touch shinier, never mirror-like
			part.Reflectance = min(0.08, p.baseRefl + 0.05 * q)
			if p.image then
				wetTexture(p, q)
				rec.wetBusy = true
			elseif not p.textured then
				-- darker: a multiplier on the hair's own vertex colours
				local c = 1 - 0.3 * q
				part.Color = Color3.new(c, c, c)
			end
		end
	end
end

-- the body long hair must stay out of: the generator's body proxy (AnatomyHairKit S.body: the trapezius
-- ellipsoid and the upper torso's rounded box, both in the UpperTorso's space) and a deltoid sphere per arm
-- round its shoulder pivot (it moves with the arm: a guard raises it). Sizes from the parts, the head scale k.
local function bodyOf(model, head)
	local torso = model:FindFirstChild("UpperTorso")
	if not (torso and torso:IsA("BasePart") and head) then
		return nil
	end
	local k = head.Size.Y / 1.2
	local ts = torso.Size
	-- a little clearance over the proxy: the visible body (meshes) is fuller than it
	local c = 0.035 * k
	local b = {
		torso = torso, tcf = CFrame.identity, arms = {}, k = k,
		ex = 0.94 * ts.X / 2 + c, ey = 0.25 * k + c, ez = 0.92 * ts.Z / 2 + c, ecy = ts.Y / 2 - 0.17 * k,
		bx = 0.88 * ts.X / 2 + c, by = ts.Y / 2 + c, bz = 0.96 * ts.Z / 2 + c, br = 0.2 * k + c,
	}
	b.emin = min(b.ex, b.ey, b.ez)
	-- the bind pose (Transform identity): the torso in head space is Neck.C1 * Neck.C0^-1, an arm in torso space
	-- Shoulder.C0 * Shoulder.C1^-1. What the built hair already touches there is not a collision
	local neck = head:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		b.bind = neck.C1 * neck.C0:Inverse()
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local arm = model:FindFirstChild(side .. "UpperArm")
		local m = arm and arm:FindFirstChild(side .. "Shoulder")
		if arm and arm:IsA("BasePart") and m and m:IsA("Motor6D") then
			local at = m.C1.Position * 0.7
			local a = { part = arm, at = at, c = Vector3.zero, r = 0.24 * min(arm.Size.X, arm.Size.Z) + c }
			if b.bind then
				a.c0 = b.bind:PointToWorldSpace((m.C0 * m.C1:Inverse()):PointToWorldSpace(at))
			end
			table.insert(b.arms, a)
		end
	end
	return b
end

local function sgn(v)
	return v < 0 and -1 or 1
end

-- how deep a head-space point is inside the body: depth, push direction (head space, unit) or nil.
-- bind: measured in the bind pose instead of this frame's
local function bodyDepth(b, tip, bind)
	local tcf = bind and b.bind or b.tcf
	local p = tcf:PointToObjectSpace(tip)
	local px, py, pz = p.X, p.Y, p.Z
	local best, gx, gy, gz = 0, 0, 0, 0
	-- trapezius
	local qx, qy, qz = px / b.ex, (py - b.ecy) / b.ey, pz / b.ez
	local l = sqrt(qx * qx + qy * qy + qz * qz)
	if l < 1 and l > 1e-4 then
		best = (1 - l) * b.emin
		gx, gy, gz = qx / b.ex, qy / b.ey, qz / b.ez
	end
	-- upper torso (rounded box)
	local r = b.br
	local ax, ay, az = abs(px) - (b.bx - r), abs(py) - (b.by - r), abs(pz) - (b.bz - r)
	local ox, oy, oz = max(ax, 0), max(ay, 0), max(az, 0)
	local d = sqrt(ox * ox + oy * oy + oz * oz) + min(max(ax, max(ay, az)), 0) - r
	if d < 0 and -d > best then
		best = -d
		if ox + oy + oz > 0 then
			gx, gy, gz = ox * sgn(px), oy * sgn(py), oz * sgn(pz)
		elseif ax >= ay and ax >= az then
			gx, gy, gz = sgn(px), 0, 0
		elseif ay >= az then
			gx, gy, gz = 0, sgn(py), 0
		else
			gx, gy, gz = 0, 0, sgn(pz)
		end
	end
	local n
	if best > 0 then
		n = tcf:VectorToWorldSpace(V3(gx, gy, gz))
		local m = n.Magnitude
		n = m > 1e-6 and n / m or nil
	end
	-- deltoids (head space already)
	for _, a in ipairs(b.arms) do
		local dv = tip - (bind and a.c0 or a.c)
		local dl = dv.Magnitude
		if dl < a.r and a.r - dl > best and dl > 1e-5 then
			best, n = a.r - dl, dv / dl
		end
	end
	if n then
		return best, n
	end
	return 0, nil
end

-- the body in the head's frame this frame
local function bodyFrame(rec, hcf)
	local b = rec.body
	if not b.torso.Parent then
		rec.body = nil
		return
	end
	b.tcf = hcf:ToObjectSpace(b.torso.CFrame)
	for _, a in ipairs(b.arms) do
		if a.part.Parent then
			a.c = hcf:PointToObjectSpace(a.part.CFrame:PointToWorldSpace(a.at))
		end
	end
end

-- keep a swinging segment's tip (head space) out of the body: rotate it about its pivot, small-angle
-- (Angles(+x) moves a tip by X x r, Angles(0, 0, +z) by Z x r; r = the pivot-to-tip arm), and stop the
-- motion into the body. True when it moved the segment.
-- how often the body pushed hair out, and the deepest push (diagnostics; read-only for callers)
local colStats = { pushes = 0, deepest = 0, ground = 0 }
HairFX.CollisionStats = colStats

local function collide(rec, e, tip, piv)
	local depth, n = bodyDepth(rec.body, tip)
	-- only what goes deeper than the hair was built (a group's mean tip can sit just inside the proxy)
	depth -= e.depth0 or 0
	if not n or depth <= 0 then
		return false
	end
	colStats.pushes += 1
	if depth > colStats.deepest then
		colStats.deepest = depth
	end
	local r = tip - piv
	local ax, ay, az = 0, -r.Z, r.Y -- X x r
	local bx, by = -r.Y, r.X -- Z x r (its z component is 0)
	local la, lb = ay * ay + az * az, bx * bx + by * by
	local dx, dy, dz = n.X * depth, n.Y * depth, n.Z * depth
	if la > 1e-4 then
		local k = (dy * ay + dz * az) / la
		e.x += k
		if k > 0 then
			e.vx = max(e.vx, 0)
		else
			e.vx = min(e.vx, 0)
		end
	end
	if lb > 1e-4 then
		local k = (dx * bx + dy * by) / lb
		-- the generator's rule (Kit.Grow): hair on a shoulder slides off it to the back (front, for hair in
		-- front of the neck), never swings out sideways like a wire. The sideways swing a push may add stays
		-- under ~0.04 studs of tip travel a step; the rest of the push swings the segment back instead
		local cap = 0.04 * (rec.body.k or 1) / max(sqrt(lb), 0.05)
		if abs(k) > cap then
			local rest = abs(k) - cap
			k = cap * sgn(k)
			e.x += tip.Z > -0.06 * (rec.body.k or 1) and -rest or rest
			e.vx = 0
		end
		e.z += k
		if k > 0 then
			e.vz = max(e.vz, 0)
		else
			e.vz = min(e.vz, 0)
		end
	end
	return true
end

------------------------------------------------------------------------
-- The organic body and the canvas
------------------------------------------------------------------------
-- The body from its own meshes (AnatomyClient OnBuilt "Body"): the upper torso and each arm part as a radial
-- map from the mesh's centre, a cube map of n x n cells a face, each holding how far the mesh reaches in that
-- direction and its outward normal there (the furthest of the vertices, triangle centres and edge midpoints that
-- fall in it). Checked against the heavyweight's and the lean woman's real meshes: no point more than half a
-- centimetre inside the mesh falls outside its map, which is a centimetre or two fuller than the mesh (BODY_PAD
-- covers what the blend shapes - pump, flex, breathing - add). The R15 boxes miss most of it: the heavyweight's
-- chest stands 0.3 studs out of its box, the trapezius and neck column well above it.
local BODY_PARTS = { UpperTorso = 10, LeftUpperArm = 6, RightUpperArm = 6, LeftLowerArm = 6, RightLowerArm = 6, LeftHand = 5,
	RightHand = 5 }
local BODY_PAD = 0.012
local MAXPUSH = 0.3 -- rad: the most one push swings a segment (a deep contact clears over a few frames, no pop)
local GROUND_CLEAR = 0.012 -- studs: hair lies on the canvas this far above it
local CONTACT_DRAG = 0.7 -- what is left of a pushed segment's swing speed (friction on the body / canvas)
local UP = Vector3.new(0, 1, 0)

-- the cube-map cell (1-based) of the direction (x, y, z)
local function cubeCell(x, y, z, n)
	local ax, ay, az = abs(x), abs(y), abs(z)
	local face, m, u, w
	if ax >= ay and ax >= az then
		face, m, u, w = x < 0 and 1 or 0, ax, y, z
	elseif ay >= az then
		face, m, u, w = y < 0 and 3 or 2, ay, x, z
	else
		face, m, u, w = z < 0 and 5 or 4, az, x, y
	end
	if m < 1e-9 then
		return 1
	end
	local iu = min(n - 1, floor((u / m + 1) * 0.5 * n))
	local iw = min(n - 1, floor((w / m + 1) * 0.5 * n))
	return face * n * n + iu * n + iw + 1
end

-- a mesh's radial map (its own part's space), or nil
local function radialMap(mesh, n)
	local P, T, nv, nt = mesh.P, mesh.T, mesh.nv or 0, mesh.nt or 0
	if type(P) ~= "table" or type(T) ~= "table" or nv < 4 or nt < 4 then
		return nil
	end
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for i = 1, nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		x0, x1, y0, y1, z0, z1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y), min(z0, z), max(z1, z)
	end
	local cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
	local cells = 6 * n * n
	local R, NX, NY, NZ = table.create(cells, 0), table.create(cells, 0), table.create(cells, 0), table.create(cells, 0)
	local function add(x, y, z, fx, fy, fz)
		local dx, dy, dz = x - cx, y - cy, z - cz
		local i = cubeCell(dx, dy, dz, n)
		local r = sqrt(dx * dx + dy * dy + dz * dz)
		if r > R[i] then
			-- (outward whatever the winding: the outermost surface faces away from the centre)
			local s = (fx * dx + fy * dy + fz * dz) < 0 and -1 or 1
			R[i], NX[i], NY[i], NZ[i] = r, fx * s, fy * s, fz * s
		end
	end
	-- (each vertex once, with the normal of the first triangle that has it)
	local seen = table.create(nv, false)
	local function vert(v, fx, fy, fz)
		local i = v // 3
		if not seen[i] then
			seen[i] = true
			add(P[v - 2], P[v - 1], P[v], fx, fy, fz)
		end
	end
	for t = 1, nt do
		local a, b, c = T[t * 3 - 2] * 3, T[t * 3 - 1] * 3, T[t * 3] * 3
		local ax, ay, az = P[a - 2], P[a - 1], P[a]
		local bx, by, bz = P[b - 2], P[b - 1], P[b]
		local qx, qy, qz = P[c - 2], P[c - 1], P[c]
		if ax and bx and qx then
			local ux, uy, uz = bx - ax, by - ay, bz - az
			local vx, vy, vz = qx - ax, qy - ay, qz - az
			local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
			local fl = sqrt(fx * fx + fy * fy + fz * fz)
			if fl > 1e-9 then
				fx, fy, fz = fx / fl, fy / fl, fz / fl
				vert(a, fx, fy, fz)
				vert(b, fx, fy, fz)
				vert(c, fx, fy, fz)
				add((ax + bx + qx) / 3, (ay + by + qy) / 3, (az + bz + qz) / 3, fx, fy, fz)
				add((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, fx, fy, fz)
				add((bx + qx) / 2, (by + qy) / 2, (bz + qz) / 2, fx, fy, fz)
				add((qx + ax) / 2, (qy + ay) / 2, (qz + az) / 2, fx, fy, fz)
			end
		end
	end
	-- a cell nothing fell in (a sparse patch) takes the furthest of its face neighbours, facing straight out
	local rmax = 0
	for i = 1, cells do
		rmax = max(rmax, R[i])
	end
	if rmax <= 0 then
		return nil
	end
	local n2 = n * n
	for i = 1, cells do
		if R[i] <= 0 then
			local f, k = (i - 1) // n2, (i - 1) % n2
			local iu, iw = k // n, k % n
			local r = 0
			for du = -1, 1 do
				for dw = -1, 1 do
					local u, w = iu + du, iw + dw
					if u >= 0 and u < n and w >= 0 and w < n then
						r = max(r, R[f * n2 + u * n + w + 1])
					end
				end
			end
			-- the cell's centre direction
			local cu, cw = (iu + 0.5) / n * 2 - 1, (iw + 0.5) / n * 2 - 1
			local s = (f % 2 == 1) and -1 or 1
			local ax = f // 2
			local dx, dy, dz
			if ax == 0 then
				dx, dy, dz = s, cu, cw
			elseif ax == 1 then
				dx, dy, dz = cu, s, cw
			else
				dx, dy, dz = cu, cw, s
			end
			local l = sqrt(dx * dx + dy * dy + dz * dz)
			R[i], NX[i], NY[i], NZ[i] = r > 0 and r or rmax, dx / l, dy / l, dz / l
		end
		R[i] += BODY_PAD
	end
	rmax += BODY_PAD
	return {
		n = n, cx = cx, cy = cy, cz = cz, R = R, NX = NX, NY = NY, NZ = NZ, rmax = rmax, r2max = rmax * rmax,
		-- this step's frame in head space as numbers (setFrame): position, rotation, the map's centre
		x = 0, y = 0, z = 0, r00 = 1, r01 = 0, r02 = 0, r10 = 0, r11 = 1, r12 = 0, r20 = 0, r21 = 0, r22 = 1, hx = 0, hy = 0, hz = 0,
	}
end

-- a shape's part frame in head space for this step (numbers: no CFrame per tested point)
local function setFrame(s, cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	s.x, s.y, s.z = x, y, z
	s.r00, s.r01, s.r02, s.r10, s.r11, s.r12, s.r20, s.r21, s.r22 = r00, r01, r02, r10, r11, r12, r20, r21, r22
	local cx, cy, cz = s.cx, s.cy, s.cz
	s.hx = r00 * cx + r01 * cy + r02 * cz + x
	s.hy = r10 * cx + r11 * cy + r12 * cz + y
	s.hz = r20 * cx + r21 * cy + r22 * cz + z
end

-- how deep a head-space point is inside a shape (0 = outside) and the surface normal there (the shape's part
-- space). Reach and normal blend between the face's four nearest cells, so a contact sliding over the body
-- moves smoothly (no step from one cell's reach to the next, which made lying hair flicker), and the depth is
-- measured along the normal (a radial depth overstates contacts struck at a slant)
local function shapeDepth(s, px, py, pz)
	local dx, dy, dz = px - s.x, py - s.y, pz - s.z
	local qx = s.r00 * dx + s.r10 * dy + s.r20 * dz - s.cx
	local qy = s.r01 * dx + s.r11 * dy + s.r21 * dz - s.cy
	local qz = s.r02 * dx + s.r12 * dy + s.r22 * dz - s.cz
	local d2 = qx * qx + qy * qy + qz * qz
	if d2 >= s.r2max then
		return 0
	end
	local ax, ay, az = abs(qx), abs(qy), abs(qz)
	local face, m, u, w
	if ax >= ay and ax >= az then
		face, m, u, w = qx < 0 and 1 or 0, ax, qy, qz
	elseif ay >= az then
		face, m, u, w = qy < 0 and 3 or 2, ay, qx, qz
	else
		face, m, u, w = qz < 0 and 5 or 4, az, qx, qy
	end
	if m < 1e-9 then
		return 0
	end
	local n = s.n
	local fu = clamp((u / m + 1) * 0.5 * n - 0.5, 0, n - 1.0001)
	local fw = clamp((w / m + 1) * 0.5 * n - 0.5, 0, n - 1.0001)
	local iu, iw = floor(fu), floor(fw)
	local tu, tw = fu - iu, fw - iw
	local i00 = face * n * n + iu * n + iw + 1
	local i10, i01, i11 = i00 + n, i00 + 1, i00 + n + 1
	local k00, k10, k01, k11 = (1 - tu) * (1 - tw), tu * (1 - tw), (1 - tu) * tw, tu * tw
	local R = s.R
	local r = R[i00] * k00 + R[i10] * k10 + R[i01] * k01 + R[i11] * k11
	if d2 >= r * r then
		return 0
	end
	local NX, NY, NZ = s.NX, s.NY, s.NZ
	local nx = NX[i00] * k00 + NX[i10] * k10 + NX[i01] * k01 + NX[i11] * k11
	local ny = NY[i00] * k00 + NY[i10] * k10 + NY[i01] * k01 + NY[i11] * k11
	local nz = NZ[i00] * k00 + NZ[i10] * k10 + NZ[i01] * k01 + NZ[i11] * k11
	local d = sqrt(d2)
	local nl = sqrt(nx * nx + ny * ny + nz * nz)
	if nl < 1e-3 then
		-- (the cells' normals cancel out: straight out from the centre)
		if d < 1e-6 then
			return 0
		end
		nx, ny, nz, nl = qx, qy, qz, d
	end
	nx, ny, nz = nx / nl, ny / nl, nz / nl
	local k = d > 1e-6 and (qx * nx + qy * ny + qz * nz) / d or 1
	return (r - d) * max(k, 0.3), nx, ny, nz
end

-- the Body section was (re)built: radial maps of the parts long hair can meet
-- (a few milliseconds a part: one part a frame, and a newer build of the same body wins)
local bodyBuilds = {}
local function onBodyBuilt(model, pieces)
	local gen = (bodyBuilds[model] or 0) + 1
	bodyBuilds[model] = gen
	local shapes = {}
	for name, pr in pairs(type(pieces) == "table" and pieces or {}) do
		local n = BODY_PARTS[name]
		local part = n and model:FindFirstChild(type(pr.attach) == "string" and pr.attach or name)
		if part and part:IsA("BasePart") and type(pr.mesh) == "table" then
			local s = radialMap(pr.mesh, n)
			if s then
				s.name, s.part = name, part
				table.insert(shapes, s)
			end
			task.wait()
			if bodyBuilds[model] ~= gen or not model.Parent then
				return false
			end
		end
	end
	bodies[model] = #shapes > 0 and { shapes = shapes } or nil
	return true
end

-- a swinging piece's sample points (its rest mesh, head space): the outermost vertices across it (both ways
-- along the head's X made square to it, and along the axis square to both) in four slabs from pivot to tip,
-- plus the vertex furthest along it (the body test); and its support vertices, the furthest along 26
-- directions (where it touches a plane however it is turned: the canvas)
local SLAB = { 0.35, 0.6, 0.85 }
local function samplePiece(e, mesh)
	local P, nv = mesh and mesh.P, mesh and mesh.nv or 0
	if type(P) ~= "table" or nv < 1 or not e.pivot then
		return
	end
	local pv = e.pivot
	local px, py, pz = pv.X, pv.Y, pv.Z
	local ax, ay, az = 0, -1, 0
	if e.len > 1e-4 then
		local a = (e.tip - pv) / e.len
		ax, ay, az = a.X, a.Y, a.Z
	end
	-- across: the head's X square to the axis (its Z for a piece lying along X)
	local ux, uy, uz = 1 - ax * ax, -ax * ay, -ax * az
	local ul = sqrt(ux * ux + uy * uy + uz * uz)
	if ul < 0.3 then
		ux, uy, uz = -az * ax, -az * ay, 1 - az * az
		ul = sqrt(ux * ux + uy * uy + uz * uz)
	end
	ux, uy, uz = ux / ul, uy / ul, uz / ul
	local vx, vy, vz = ay * uz - az * uy, az * ux - ax * uz, ax * uy - ay * ux
	local len = max(e.len, 0.05)
	-- [slab * 4 + k] = best value / vertex (k: +u, -u, +v, -v), [17] = furthest along the axis
	local bv, bi = table.create(17, -math.huge), table.create(17, 0)
	-- supports: 13 axes, each both ways
	local smin, smax, imin, imax = table.create(13, math.huge), table.create(13, -math.huge), table.create(13, 0), table.create(13, 0)
	local function ext(k, d, i)
		if d < smin[k] then
			smin[k], imin[k] = d, i
		end
		if d > smax[k] then
			smax[k], imax[k] = d, i
		end
	end
	local rad2 = 0
	for i = 1, nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		local dx, dy, dz = x - px, y - py, z - pz
		rad2 = max(rad2, dx * dx + dy * dy + dz * dz)
		local t = (dx * ax + dy * ay + dz * az) / len
		local s = t < SLAB[1] and 0 or (t < SLAB[2] and 1 or (t < SLAB[3] and 2 or 3))
		local u = dx * ux + dy * uy + dz * uz
		local v = dx * vx + dy * vy + dz * vz
		local o = s * 4
		if u > bv[o + 1] then
			bv[o + 1], bi[o + 1] = u, i
		end
		if -u > bv[o + 2] then
			bv[o + 2], bi[o + 2] = -u, i
		end
		if v > bv[o + 3] then
			bv[o + 3], bi[o + 3] = v, i
		end
		if -v > bv[o + 4] then
			bv[o + 4], bi[o + 4] = -v, i
		end
		if t > bv[17] then
			bv[17], bi[17] = t, i
		end
		-- (the 13 axes: x, y, z, the six face diagonals, the four body diagonals)
		ext(1, x, i)
		ext(2, y, i)
		ext(3, z, i)
		ext(4, x + y, i)
		ext(5, x - y, i)
		ext(6, y + z, i)
		ext(7, y - z, i)
		ext(8, x + z, i)
		ext(9, x - z, i)
		ext(10, x + y + z, i)
		ext(11, x + y - z, i)
		ext(12, x - y + z, i)
		ext(13, -x + y + z, i)
	end
	e.rad = sqrt(rad2)
	-- (its bounding sphere: the body test's first, cheap check)
	local bx, by, bz = smax[1] - smin[1], smax[2] - smin[2], smax[3] - smin[3]
	e.cen = V3((smax[1] + smin[1]) / 2, (smax[2] + smin[2]) / 2, (smax[3] + smin[3]) / 2)
	e.crad = 0.5 * sqrt(bx * bx + by * by + bz * bz)
	local smp, seen = {}, {}
	for k = 1, 17 do
		local i = bi[k]
		if i > 0 and not seen[i] then
			seen[i] = true
			table.insert(smp, P[i * 3 - 2])
			table.insert(smp, P[i * 3 - 1])
			table.insert(smp, P[i * 3])
		end
	end
	e.smp, e.ns, e.d0 = smp, #smp // 3, table.create(#smp // 3, 0)
	local sup = {}
	seen = {}
	for _, list in ipairs({ imin, imax }) do
		for k = 1, 13 do
			local i = list[k]
			if i > 0 and not seen[i] then
				seen[i] = true
				table.insert(sup, P[i * 3 - 2])
				table.insert(sup, P[i * 3 - 1])
				table.insert(sup, P[i * 3])
			end
		end
	end
	e.sup = sup
end

-- the contact each sample point already has with the body as built (the bind pose): what the hair touches
-- there is not a collision (the generator lays hair on the body's shoulders and back)
local function bindDepths(rec)
	local mb = bodies[rec.model]
	rec.boundTo = mb
	local head = rec.head
	local neck = head and head:FindFirstChild("Neck")
	if not (mb and rec.swings and neck and neck:IsA("Motor6D")) then
		return
	end
	-- each part's bind frame in head space: the torso is Neck.C1 * Neck.C0^-1, a limb its parent's * C0 * C1^-1
	local binds = {}
	local function bindOf(part, depth)
		if binds[part] then
			return binds[part]
		end
		if part == neck.Part0 then
			binds[part] = neck.C1 * neck.C0:Inverse()
			return binds[part]
		end
		if depth > 4 then
			return nil
		end
		for _, m in ipairs(part:GetChildren()) do
			if m:IsA("Motor6D") and m.Part1 == part and m.Part0 then
				local up = bindOf(m.Part0, depth + 1)
				if up then
					binds[part] = up * m.C0 * m.C1:Inverse()
				end
				return binds[part]
			end
		end
		return nil
	end
	for _, s in ipairs(mb.shapes) do
		s.bind = s.part.Parent and bindOf(s.part, 0) or nil
	end
	for _, e in ipairs(rec.list) do
		local smp = e.smp
		if smp and not e.bounce then
			for i = 1, e.ns do
				e.d0[i] = 0
			end
			for _, s in ipairs(mb.shapes) do
				if s.bind then
					setFrame(s, s.bind)
					for i = 1, e.ns do
						local d = shapeDepth(s, smp[i * 3 - 2], smp[i * 3 - 1], smp[i * 3])
						if d > e.d0[i] then
							e.d0[i] = d
						end
					end
				end
			end
		end
	end
end

-- swing a segment about its pivot so that one of its points (head space, as posed now) moves `depth` along the
-- unit direction n (head space): the smallest swing of its two angles that does it (their columns in the
-- parent's frame: d(point)/dx = X x r, d(point)/dz = (Rx(x) Z) x r, r = pivot to point). Motion into the
-- obstacle stops. free = false (the body): the generator's rule (Kit.Grow) - hair on a shoulder slides off it to
-- the back (front, for hair in front of the neck), never swings out sideways like a wire. True when it moved.
local function swingPush(rec, e, parentCF, px, py, pz, depth, nx, ny, nz, free)
	local piv = parentCF:PointToWorldSpace(e.pivot)
	local r = parentCF:VectorToObjectSpace(V3(px, py, pz) - piv)
	local n = parentCF:VectorToObjectSpace(V3(nx, ny, nz))
	local rx, ry, rz = r.X, r.Y, r.Z
	local sx, cx = sin(e.x), cos(e.x)
	local ay, az = -rz, ry
	local bx, by, bz = -sx * rz - cx * ry, cx * rx, sx * rx
	local gx = ay * n.Y + az * n.Z
	local gz = bx * n.X + by * n.Y + bz * n.Z
	local g2 = gx * gx + gz * gz
	-- (a point on the pivot, or a push the swing cannot make: along the lever)
	if g2 < 1e-4 or g2 < 0.01 * (rx * rx + ry * ry + rz * rz) then
		return false
	end
	local dx, dz = depth * gx / g2, depth * gz / g2
	if not free then
		local k = rec.k or 1
		local lb = sqrt(bx * bx + by * by + bz * bz)
		local cap = 0.04 * k / max(lb, 0.05)
		if abs(dz) > cap then
			local rest = abs(dz) - cap
			dz = cap * sgn(dz)
			dx += pz > -0.06 * k and -rest or rest
		end
	end
	local m = sqrt(dx * dx + dz * dz)
	if m > MAXPUSH then
		dx, dz = dx * MAXPUSH / m, dz * MAXPUSH / m
	end
	e.x += dx
	e.z += dz
	if dx > 0 then
		e.vx = max(e.vx, 0)
	elseif dx < 0 then
		e.vx = min(e.vx, 0)
	end
	if dz > 0 then
		e.vz = max(e.vz, 0)
	elseif dz < 0 then
		e.vz = min(e.vz, 0)
	end
	-- and some friction along it: hair resting on a shoulder or the canvas does not skate over it
	e.vx *= CONTACT_DRAG
	e.vz *= CONTACT_DRAG
	e.cf = parentCF * e.pcf * A(e.x, 0, e.z) * e.pinv
	colStats.pushes += 1
	if depth > colStats.deepest then
		colStats.deepest = depth
	end
	return true
end

-- the deepest of a segment's sample points in the organic body this step (beyond its bind contact), pushed out:
-- how deep it was (0: clear)
local function meshCollide(rec, e, parentCF, shapes)
	local smp, cen = e.smp, e.cen
	if not (smp and cen) then
		return 0
	end
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = e.cf:GetComponents()
	local cx, cy, cz = cen.X, cen.Y, cen.Z
	local pcx = r00 * cx + r01 * cy + r02 * cz + x
	local pcy = r10 * cx + r11 * cy + r12 * cz + y
	local pcz = r20 * cx + r21 * cy + r22 * cz + z
	local best, bs, bpx, bpy, bpz, bnx, bny, bnz = 0.004, nil, 0, 0, 0, 0, 0, 0
	local d0 = e.d0
	for _, s in ipairs(shapes) do
		-- (the piece's bounding sphere against the shape's)
		local gx, gy, gz = pcx - s.hx, pcy - s.hy, pcz - s.hz
		local rr = e.crad + s.rmax
		if s.live and gx * gx + gy * gy + gz * gz < rr * rr then
			for i = 1, e.ns do
				local sx, sy, sz = smp[i * 3 - 2], smp[i * 3 - 1], smp[i * 3]
				local px = r00 * sx + r01 * sy + r02 * sz + x
				local py = r10 * sx + r11 * sy + r12 * sz + y
				local pz = r20 * sx + r21 * sy + r22 * sz + z
				local d, nx, ny, nz = shapeDepth(s, px, py, pz)
				d -= d0[i]
				if d > best then
					best, bs, bpx, bpy, bpz, bnx, bny, bnz = d, s, px, py, pz, nx, ny, nz
				end
			end
		end
	end
	if not bs then
		return 0
	end
	-- the surface normal into head space
	local hx = bs.r00 * bnx + bs.r01 * bny + bs.r02 * bnz
	local hy = bs.r10 * bnx + bs.r11 * bny + bs.r12 * bnz
	local hz = bs.r20 * bnx + bs.r21 * bny + bs.r22 * bnz
	return swingPush(rec, e, parentCF, bpx, bpy, bpz, best, hx, hy, hz, false) and best or 0
end

-- how far a piece's lowest support vertex is under the canvas this step (rec.gn = up in head space, rec.gh =
-- the canvas' height in head space), and that vertex (head space), or 0
local function underCanvas(rec, e)
	local sup = e.sup
	if not sup then
		return 0
	end
	local n = rec.gn
	local nx, ny, nz = n.X, n.Y, n.Z
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = e.cf:GetComponents()
	local low, lx, ly, lz = math.huge, 0, 0, 0
	for i = 1, #sup, 3 do
		local sx, sy, sz = sup[i], sup[i + 1], sup[i + 2]
		local px = r00 * sx + r01 * sy + r02 * sz + x
		local py = r10 * sx + r11 * sy + r12 * sz + y
		local pz = r20 * sx + r21 * sy + r22 * sz + z
		local h = px * nx + py * ny + pz * nz
		if h < low then
			low, lx, ly, lz = h, px, py, pz
		end
	end
	return rec.gh - low, lx, ly, lz
end

-- a swinging segment near the canvas swings up onto it (its pivot's reach first: most segments are clear)
local function groundSwing(rec, e, parentCF)
	local pv = parentCF:PointToWorldSpace(e.pivot)
	if pv:Dot(rec.gn) - (e.rad or 0) > rec.gh then
		return false
	end
	local depth, lx, ly, lz = underCanvas(rec, e)
	if depth <= 0.002 then
		return false
	end
	local n = rec.gn
	colStats.ground += 1
	return swingPush(rec, e, parentCF, lx, ly, lz, depth, n.X, n.Y, n.Z, true)
end

-- (re)read the moving pieces of a model's built hair (OnBuilt hands us the pieces)
local function onBuilt(model, section, pieces)
	if section == "Body" then
		if onBodyBuilt(model, pieces) and meshes[model] then
			bindDepths(meshes[model])
		end
		return
	end
	if section ~= "Hair" then
		return
	end
	local rec = meshes[model]
	local old = rec and rec.byName or {}
	rec = { model = model, list = {}, byName = {}, head = model:FindFirstChild("Head"), sweat = 0, nextAttr = 0, frame = 0,
		rest = true, wetApplied = -1, seed = (#model.Name * 1.37) % 6.28, gap = true, reach = 0 }
	rec.body = bodyOf(model, rec.head)
	rec.k = rec.head and rec.head.Size.Y / 1.2 or 1
	for name, pr in pairs(type(pieces) == "table" and pieces or {}) do
		local mesh = pr.mesh
		local fx = mesh and mesh.hairfx
		local part = pr.part
		local entry = {
			name = name, part = part, baseRefl = part and part.Reflectance or 0, fx = fx,
			-- a textured piece (the image AnatomyClient made for it): wetness darkens the texture itself
			image = pr.image, textured = pr.image ~= nil,
			-- spring state: swing angles (x about the head's X, z about its Z) / bounce height y
			x = 0, z = 0, y = 0, vx = 0, vz = 0, vy = 0, prevPos = nil, prevVel = Vector3.zero, written = false,
			cf = I,
		}
		if fx and type(fx.pivot) == "table" then
			entry.pivot = V3(fx.pivot[1], fx.pivot[2], fx.pivot[3])
			local tp = type(fx.tip) == "table" and fx.tip or fx.pivot
			entry.tip = V3(tp[1], tp[2], tp[3])
			entry.len = (entry.tip - entry.pivot).Magnitude
			-- the swing about the pivot is CF(p) * rotation * CF(-p): the two constant frames are built once
			entry.pcf, entry.pinv = CF(entry.pivot), CF(-entry.pivot)
			entry.stiff = clamp(tonumber(fx.stiff) or 0.3, 0, 1)
			entry.mass = clamp(tonumber(fx.mass) or 1, 0.3, 3)
			entry.seg = tonumber(fx.seg) or 1
			entry.bounce = fx.kind == "bounce"
			entry.phase = (#rec.list * 1.618) % 6.28
			entry.slot = #rec.list % 2
			-- every lock its own spring: +-15 % mass and +-0.08 stiffness from its name (deterministic), so locs,
			-- braids and clumps bounce and settle out of step instead of moving as one sheet
			local hsh = 0
			for i = 1, #name do
				hsh = (hsh * 31 + string.byte(name, i)) % 9973
			end
			local jit = (hsh % 101) / 100
			entry.mass = clamp(entry.mass * (0.85 + 0.3 * jit), 0.3, 3)
			entry.stiff = clamp(entry.stiff + (((hsh // 101) % 17) / 16 - 0.5) * 0.16, 0, 1)
			-- keep the motion state across a rebuild of the same piece (LOD flips) so nothing pops
			local prev = old[name]
			if prev and prev.fx then
				entry.x, entry.z, entry.y, entry.vx, entry.vz, entry.vy = prev.x, prev.z, prev.y, prev.vx, prev.vz, prev.vy
			end
			-- what the body and the canvas test (and how far from the head the piece can reach: the canvas test
			-- only runs for a head that low)
			samplePiece(entry, mesh)
			rec.reach = max(rec.reach, entry.pivot.Magnitude + (entry.rad or entry.len))
			-- (hair without a swinging piece - short cuts, curls - never needs the body's frames)
			rec.swings = rec.swings or (not entry.bounce and entry.smp ~= nil)
		end
		table.insert(rec.list, entry)
		rec.byName[name] = entry
	end
	-- parents (a chain's lower segment hangs from its upper one), then a stable order: parents first
	for _, e in ipairs(rec.list) do
		if e.fx and e.fx.parent then
			e.parent = rec.byName[e.fx.parent]
		end
	end
	table.sort(rec.list, function(a, b)
		local sa, sb = a.seg or 0, b.seg or 0
		if sa ~= sb then
			return sa < sb
		end
		return a.name < b.name
	end)
	-- the body contact each swinging piece's tip already has as built (the bind pose)
	local b = rec.body
	if b and b.bind then
		for _, e in ipairs(rec.list) do
			if e.tip and not e.bounce then
				e.depth0 = bodyDepth(b, e.tip, true)
			end
		end
	end
	meshes[model] = rec
	bindDepths(rec)
	rec.sweat = model:GetAttribute("Sweat")
	rec.sweat = type(rec.sweat) == "number" and clamp(rec.sweat, 0, 1) or 0
	local q = math.floor(rec.sweat * 4 + 0.5) / 4
	if q > 0 then
		setWet(rec, q)
	end
end

local function onRestored(model, section)
	if section == "Hair" then
		meshes[model] = nil
	elseif section == "Body" then
		bodies[model] = nil
		bodyBuilds[model] = (bodyBuilds[model] or 0) + 1
	end
end

local function relaxMesh(rec)
	for _, e in ipairs(rec.list) do
		e.x, e.z, e.y, e.vx, e.vz, e.vy = 0, 0, 0, 0, 0, 0
		e.prevPos = nil
		e.prevVel = Vector3.zero
		if e.written and Anatomy then
			Anatomy.SetPieceTransform(rec.model, "Hair", e.name, I)
		end
		e.written = false
		e.cf = I
	end
	rec.rest = true
end

-- one moving piece: forcing from its pivot's acceleration (head space), gravity bias, wind, idle; spring
local function stepPiece(rec, e, dt, t, hcf, g, wx, wz)
	local fx = e.fx
	if not fx or not e.pivot then
		return
	end
	local parentCF = e.parent and e.parent.cf or I
	-- the pivot where it is now (the parent segment's swing included), in world space
	local pw = hcf:PointToWorldSpace(parentCF:PointToWorldSpace(e.pivot))
	local la = Vector3.zero
	if e.prevPos then
		local vel = (pw - e.prevPos) / dt
		local acc = (vel - e.prevVel) / dt
		e.prevVel = vel
		if acc.Magnitude > 4000 or vel.Magnitude > 200 then
			acc = Vector3.zero
			e.prevVel = Vector3.zero
		end
		la = hcf:VectorToObjectSpace(acc)
	end
	e.prevPos = pw
	local wet = 1 + rec.sweat * 0.8
	local mass = e.mass * wet
	local stiff = e.stiff
	if e.bounce then
		-- a springy mass: compresses under a downward jolt and springs back, tilts a little with sideways ones
		local kk = (160 + 260 * stiff) / mass
		local cc = K.damping(kk, 0.18 + 0.25 * stiff + 0.25 * rec.sweat)
		e.vy += -la.Y * 0.0011 * kk * dt
		e.vx += la.Z * 0.0009 * kk * dt
		e.vz += -la.X * 0.0009 * kk * dt
		e.y, e.vy = K.spring(e.y, e.vy, 0, kk, cc, dt)
		e.x, e.vx = K.spring(e.x, e.vx, 0, kk * 0.8, cc, dt)
		e.z, e.vz = K.spring(e.z, e.vz, 0, kk * 0.8, cc, dt)
		local lim = 0.012 + 0.03 * min(e.len, 0.6)
		e.y = clamp(e.y, -lim, lim * 0.6)
		e.x = clamp(e.x, -0.1, 0.1)
		e.z = clamp(e.z, -0.1, 0.1)
		e.cf = CF(0, e.y, 0) * e.pcf * A(e.x, 0, e.z) * e.pinv
		-- on the canvas a cluster gives a little (it lifts off it, a few centimetres at most) instead of sinking in
		if rec.gnd then
			local depth = underCanvas(rec, e)
			if depth > 0.002 then
				e.cf = CF(rec.gn * min(depth, 0.06 * (rec.k or 1))) * e.cf
			end
		end
		return
	end
	-- swing: gravity bias first (the hair keeps hanging down when the head tilts), weaker for stiff hair
	local gx, gz = K.gravityAngles(g.X, g.Y, g.Z)
	local gw = (e.seg <= 1 and 0.7 or 0.35) * (1 - 0.6 * stiff)
	local kk = (40 + 160 * stiff) / mass / (e.seg <= 1 and 1 or 1.25)
	local cc = K.damping(kk, 0.2 + 0.3 * stiff + 0.25 * rec.sweat)
	local gain = 0.004 * (e.seg <= 1 and 1 or 1.4) / (0.6 + 0.4 * stiff)
	-- inertia: the tip lags the pivot's acceleration; wind and an idle drift
	local idle = (0.012 + 0.012 * e.seg) * (1 - stiff)
	local wind = (1 - 0.6 * stiff) / mass * (rec.windK or 0.035)
	local tx = clamp(K.wrap(gx), -1.2, 1.2) * gw + idle * sin(t * 1.4 + e.phase) + wz * wind
	local tz = clamp(K.wrap(gz), -1.2, 1.2) * gw + idle * 0.7 * sin(t * 0.9 + e.phase * 1.7) + wx * wind
	e.vx += la.Z * gain * kk * dt
	e.vz += -la.X * gain * kk * dt
	e.x, e.vx = K.spring(e.x, e.vx, tx, kk, cc, dt)
	e.z, e.vz = K.spring(e.z, e.vz, tz, kk, cc, dt)
	local lim = e.seg <= 1 and 0.6 or 0.8
	-- Angles(+x) swings the tip forward: toward the face / chest, never far
	if e.x > FWD or e.x < -lim then
		e.x = clamp(e.x, -lim, FWD)
		e.vx *= -0.3
	end
	if abs(e.z) > lim then
		e.z = clamp(e.z, -lim, lim)
		e.vz *= -0.3
	end
	-- the lower segment swings about its own pivot inside its parent's motion
	e.cf = parentCF * e.pcf * A(e.x, 0, e.z) * e.pinv
	-- out of the body: the organic body's maps (a second pass when the first pushed: the push can bring another
	-- point in), else the tip against the part-built body's proxy
	-- (a segment clear of it last time is tested every second step, half the segments on each; a resting contact
	-- - the spring's few millimetres a step into a shoulder - needs no second look)
	local mb = rec.mb
	if mb and (e.hit or (rec.frame + e.slot) % 2 == 0) then
		local d = meshCollide(rec, e, parentCF, mb.shapes)
		e.hit = d > 0
		if d > 0.01 then
			meshCollide(rec, e, parentCF, mb.shapes)
		end
	elseif rec.body and collide(rec, e, e.cf:PointToWorldSpace(e.tip), parentCF:PointToWorldSpace(e.pivot)) then
		e.cf = parentCF * e.pcf * A(e.x, 0, e.z) * e.pinv
	end
	-- then onto the canvas: last, because hair pressed between the body and the canvas is hidden there, hair
	-- through the canvas is not
	if rec.gnd and groundSwing(rec, e, parentCF) then
		groundSwing(rec, e, parentCF)
	end
end

-- outdoors (open sky above the head) the breeze gusts; indoors only a fan's gentle draught. One upward ray
-- per model every 2 s while it moves (characters only, the model itself excluded)
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude
local skyCount = 0
local function windScale(rec, t, hcf)
	if t < (rec.nextSky or 0) then
		return rec.windK or 0.035
	end
	-- (every model at its own phase: models that came in together never cast their rays on one frame again)
	if not rec.skyK then
		skyCount += 1
		rec.skyK = (skyCount * 0.618034) % 1
		rec.nextSky = t + 2 * rec.skyK
	else
		rec.nextSky = t + 2
	end
	-- (a model still within a couple of studs of its last ray is under the same roof, or the same sky)
	local pos = hcf.Position
	if rec.windK and rec.skyPos and (pos - rec.skyPos).Magnitude < 2 then
		return rec.windK
	end
	rec.skyPos = pos
	local roofed = false
	pcall(function()
		skyParams.FilterDescendantsInstances = { rec.model }
		roofed = workspace:Raycast(hcf.Position, Vector3.new(0, 60, 0), skyParams) ~= nil
	end)
	rec.windK = roofed and 0.03 or 0.075
	return rec.windK
end

local function stepMesh(rec, dt, t, hcf)
	local g = hcf:VectorToObjectSpace(DOWN)
	windScale(rec, t, hcf)
	local wx, wz = windAt(t, rec.seed)
	-- wind in the head's frame (a world-space breeze)
	local wv = hcf:VectorToObjectSpace(V3(wx, 0, wz))
	if rec.body then
		bodyFrame(rec, hcf)
	end
	-- the organic body in the head's frame this step (its maps' bind contact measured again after a rebuild).
	-- Inside the level's near distance only (High 25 studs, Medium 20, Low 15; your own hair and the fighters' at
	-- High's at every level): further out the tips keep to the part-built proxy, a few centimetres being a pixel.
	-- Only for hair that swings (rec.swings)
	local mb = bodies[rec.model]
	if mb and rec.boundTo ~= mb then
		bindDepths(rec)
	end
	if not (rec.near and rec.swings) then
		mb = nil
	end
	rec.mb = mb
	if mb then
		for _, s in ipairs(mb.shapes) do
			local part = s.part
			s.live = part.Parent ~= nil
			if s.live then
				setFrame(s, hcf:ToObjectSpace(part.CFrame))
			end
		end
	end
	-- the canvas, when the head is low enough for the hair to reach it (knockdowns, get-ups, floor work): its
	-- height and up in head space
	rec.gnd = false
	local fy = rec.floorY
	if fy and hcf.Y - fy < rec.reach + 0.3 then
		rec.gnd = true
		rec.gn = hcf:VectorToObjectSpace(UP)
		rec.gh = fy + GROUND_CLEAR - hcf.Y
	end
	for _, e in ipairs(rec.list) do
		if e.fx then
			stepPiece(rec, e, dt, t, hcf, g, wv.X, wv.Z)
		end
	end
	if not Anatomy then
		return
	end
	for _, e in ipairs(rec.list) do
		if e.fx then
			Anatomy.SetPieceTransform(rec.model, "Hair", e.name, e.cf)
			e.written = true
		end
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
-- whip the hair: (x, z) = the direction the hair is flung in head space (+x = the head's right,
-- +z = backwards), e.g. forward when a jab snaps the head back
function HairFX.Impulse(model, x, z, amount)
	amount = amount or 1
	local o = owners[model]
	if o then
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
	local rec = meshes[model]
	if rec then
		for _, e in ipairs(rec.list) do
			if e.fx then
				local k = amount / e.mass
				if e.bounce then
					-- curls and coily volumes are tossed up and spring back
					e.vy += 0.35 * k
					e.vx -= (z or 0) * 1.2 * k
					e.vz += (x or 0) * 1.2 * k
				else
					local s = e.seg <= 1 and 1 or 1.5
					e.vx -= (z or 0) * 4.5 * k * s
					e.vz += (x or 0) * 4.5 * k * s
				end
			end
		end
	end
end

local frame = 0
-- rigs = the Animator's rig table (rig.isFighter / rig.isLocal pick High's distances), may be nil
local function levelOf(rigs, model)
	local rig = rigs and rigs[model]
	return (rig and (rig.isFighter or rig.isLocal)) and HIGH or lv
end
-- the root's distance when it is clearly past mid (the Animator measured it this frame; the head is within a few
-- studs of the root), else false: a far model's head is not read at all
local function farByRoot(rigs, model, t, L)
	local rig = rigs and rigs[model]
	local cd = rig and rig.camT == t and rig.camDist
	return (cd and cd > L.mid + 5) and cd or false
end
-- the canvas under a model (world Y): the Animator measured where its soles stand in its root's space (the root
-- stays upright whatever the body does on the canvas); nil without a rig
local function floorOf(rigs, model)
	local rig = rigs and rigs[model]
	local g = rig and rig.geo
	local root = rig and rig.root
	if not (g and g.ok and type(g.groundY) == "number" and root and root.Parent) then
		return nil
	end
	return root.Position.Y + g.groundY
end
function HairFX.Update(dt, t, camPos, cam, rigs)
	frame += 1
	-- the body maps of models that went away (a bald model has no hair record to drop them with), now and then
	if frame % 120 == 0 then
		for model in pairs(bodies) do
			if not model.Parent then
				bodies[model], bodyBuilds[model] = nil, nil
			end
		end
	end
	-- mesh hair
	for model, rec in pairs(meshes) do
		if not model.Parent then
			meshes[model] = nil
			continue
		end
		local head = rec.head
		if not head or not head.Parent then
			head = model:FindFirstChild("Head")
			rec.head = head
			if not head then
				continue
			end
		end
		local L = levelOf(rigs, model)
		local far = farByRoot(rigs, model, t, L)
		local hp = (not far) and head.Position
		local dist = far or (hp - camPos).Magnitude
		if dist > L.mid then
			if not rec.rest then
				relaxMesh(rec)
			end
			rec.gap = true
			continue
		end
		local onScreen = true
		if cam and dist > 6 then
			local _, vis = cam:WorldToViewportPoint(hp)
			onScreen = vis
		end
		if not onScreen then
			-- paused: the pivots' motion history is stale when it comes back (no false whip then)
			rec.gap = true
			continue
		end
		local stepN = dist < L.near and 1 or 2
		rec.near = stepN == 1
		rec.frame += 1
		if rec.frame % stepN ~= 0 then
			continue
		end
		local sdt = min(dt * stepN, 1 / 15)
		rec.rest = false
		if rec.gap then
			rec.gap = false
			for _, e in ipairs(rec.list) do
				e.prevPos = nil
				e.prevVel = Vector3.zero
			end
		end
		if t >= rec.nextAttr then
			rec.nextAttr = t + 0.5
			local sw = model:GetAttribute("Sweat")
			rec.sweat = type(sw) == "number" and clamp(sw, 0, 1) or 0
			-- wetness in steps (a textured piece rewrites its image for each one)
			local q = math.floor(rec.sweat * 4 + 0.5) / 4
			if q ~= rec.wetApplied then
				setWet(rec, q)
			end
		end
		if rec.wetBusy then
			-- one chunk of rows per frame for every texture still being rewritten
			local busy = false
			for _, e in ipairs(rec.list) do
				if e.wetChunk then
					stepWetTexture(e)
					busy = busy or e.wetChunk ~= nil
				end
			end
			rec.wetBusy = busy
		end
		rec.floorY = floorOf(rigs, model)
		stepMesh(rec, sdt, t, head.CFrame)
	end
	-- round-1 hair
	for model, o in pairs(owners) do
		if not model.Parent then
			owners[model] = nil
			continue
		end
		-- drop joints / strands whose parts were rebuilt: twice a second, or at once when new ones arrived (a
		-- rebuild). Not every frame: that is a property read per joint of every model in the place, near or
		-- not, and a destroyed joint stepped a moment longer is harmless
		local js = o.joints
		local ss = o.strands
		if t >= o.nextScan or o.fresh then
			o.nextScan = t + 0.5
			o.fresh = false
			for i = #js, 1, -1 do
				if not js[i].m.Parent then
					table.remove(js, i)
					o.dirty = true
				end
			end
			for i = #ss, 1, -1 do
				if not ss[i].b.Parent then
					table.remove(ss, i)
				end
			end
			if #js == 0 and #ss == 0 then
				owners[model] = nil
				continue
			end
		end
		-- mesh hair replaces BoxerLook.Hair only: those joints and strands rest (hidden); boot-lace tails, wrap
		-- ends and the beard are not the Hair section's and keep swinging
		local meshHair = meshes[model] ~= nil
		if meshHair ~= (o.meshHair or false) then
			o.meshHair = meshHair
			for _, j in ipairs(js) do
				if j.inHair then
					restJoint(j)
				end
			end
			restStrands(o)
		end
		local head = o.head
		if not head or not head.Parent then
			head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
			o.head = head
			if not head then
				continue
			end
		end
		local L = levelOf(rigs, model)
		local far = farByRoot(rigs, model, t, L)
		local hp = (not far) and head.Position
		local dist = far or (hp - camPos).Magnitude
		if dist > L.mid then
			if not o.rest then
				relax(o)
			end
			continue
		end
		local onScreen = true
		if cam and dist > 6 then
			local _, vis = cam:WorldToViewportPoint(hp)
			onScreen = vis
		end
		if not onScreen then
			continue
		end
		local step = dist < L.near and 1 or 2
		o.frame += 1
		if o.frame % step ~= 0 then
			continue
		end
		local sdt = min(dt * step, 1 / 15)
		o.rest = false
		if t >= o.nextAttr or o.dirty then
			o.nextAttr = t + 0.5
			local sw = model:GetAttribute("Sweat")
			o.sweat = type(sw) == "number" and clamp(sw, 0, 1) or 0
			local consts = o.dirty or o.sweat ~= o.sweatK
			o.sweatK = o.sweat
			for _, j in ipairs(js) do
				-- the cached joint data (a rebuilt chain brings new joints; this only catches edits in place)
				local m = j.m
				j.p0, j.c0 = m.Part0, m.C0
				if consts then
					jointConsts(j, o.sweat)
				end
				-- a chain another mesh hides (a mesh beard): at rest while hidden
				if not j.inHair and Anatomy and Anatomy.IsReplaced then
					local p1 = m.Part1
					local rep = p1 ~= nil and Anatomy.IsReplaced(p1) == true
					if rep and not j.replaced then
						restJoint(j)
					end
					j.replaced = rep
				end
			end
			if o.dirty then
				assignLeaders(o)
			end
			-- forget anchors that went away with their parts
			local al = o.anchorList
			for i = #al, 1, -1 do
				if not al[i].part.Parent then
					o.anchors[al[i].part] = nil
					table.remove(al, i)
				end
			end
		end
		o.tick += 1
		local tick = o.tick
		-- deeper segments at half rate; settled joints under a still anchor slower still (never under 15 Hz,
		-- the LOD step included); followers copy their leader at half rate
		local slow = step == 1 and 4 or 2
		for _, j in ipairs(js) do
			if j.replaced or (meshHair and j.inHair) then
				continue
			end
			local leader = j.leader
			if leader then
				if (tick + j.slot) % 2 == 0 then
					jointStats.follows += 1
					j.x, j.z = leader.x * j.followK, leader.z * j.followK
					writeJoint(j)
				end
				continue
			end
			-- each anchor is read once per step, by the first joint that needs it (hair resting under a mesh
			-- costs no read)
			local a = j.arec
			if a and a.tick ~= tick then
				anchorStep(a, sdt, tick)
			end
			local rate = j.depth >= 2 and 2 or 1
			if a and a.quiet and settled(j) then
				rate = slow
			end
			if (tick + j.slot) % rate == 0 then
				stepJoint(j, sdt * rate, t)
			end
		end
		-- strands (all in BoxerLook.Hair): sway from the head's own motion (head space), only up close
		if #ss > 0 and dist < L.near and not meshHair then
			local hv = Vector3.zero
			if o.lastPos then
				hv = head.CFrame:VectorToObjectSpace((hp - o.lastPos) / sdt)
			end
			o.lastPos = hp
			local a = 1 - exp(-sdt * 6)
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

-- counters for tools and tests: mesh models / moving pieces, round-1 models / joints
function HairFX.Status()
	local s = { meshModels = 0, meshPieces = 0, swing = 0, bounce = 0, models = 0, joints = 0, followers = 0 }
	for _, rec in pairs(meshes) do
		s.meshModels += 1
		for _, e in ipairs(rec.list) do
			if e.fx then
				s.meshPieces += 1
				if e.bounce then
					s.bounce += 1
				else
					s.swing += 1
				end
			end
		end
	end
	for _, o in pairs(owners) do
		s.models += 1
		s.joints += #o.joints
		for _, j in ipairs(o.joints) do
			if j.leader then
				s.followers += 1
			end
		end
	end
	return s
end

CollectionService:GetInstanceAddedSignal("HairSway"):Connect(addJoint)
CollectionService:GetInstanceAddedSignal("HairStrand"):Connect(addStrand)
for _, m in ipairs(CollectionService:GetTagged("HairSway")) do
	addJoint(m)
end
for _, b in ipairs(CollectionService:GetTagged("HairStrand")) do
	addStrand(b)
end
if Anatomy and Anatomy.OnBuilt and Anatomy.OnRestored then
	Anatomy.OnBuilt:Connect(onBuilt)
	Anatomy.OnRestored:Connect(onRestored)
end

return HairFX
