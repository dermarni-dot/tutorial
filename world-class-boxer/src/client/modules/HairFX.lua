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
--  * wet hair (the model's Sweat attribute): heavier and more damped, darker and a touch shinier
-- Round-1 hair (the part-built fallback, CONTRACTS section 5) keeps its behaviour, and is skipped while a model's
-- mesh hair replaces it:
--  * HairSway Motor6Ds (hair chains, braids, locs, ponytails, boot lace tails, frayed wrap ends): a damped
--    spring per joint, excited by the joint pivot's motion, gravity bias, Stiff / Mass / Sweat
--  * HairBounce clusters: a vertical / lateral jiggle; HairStrand Beams: curve sway from the head's motion
-- HairFX.Impulse(model, x, z, amount): an extra whip ((x, z) = the direction the hair is flung in head space,
-- +x = the head's right, +z = backwards).
-- LOD: every frame under 25 studs, every 2nd frame to 60, frozen (eased back to rest) beyond, skipped off
-- screen. No per-frame allocation (CFrames are values).
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
local sin, cos, abs, min, max, sqrt, exp = math.sin, math.cos, math.abs, math.min, math.max, math.sqrt, math.exp
local clamp = math.clamp
local DOWN = Vector3.new(0, -1, 0)

local NEAR, MID = 25, 60
local MAXA = 1.15 -- rad: a hair joint never swings further than this
local owners = {} -- model -> { joints = {}, strands = {}, head, ... } (round-1 hair)
local meshes = {} -- model -> { pieces = { list }, byName = {}, head, sweat, ... } (mesh hair)

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

------------------------------------------------------------------------
-- Mesh hair
------------------------------------------------------------------------
-- slow, smooth wind (world space, studs/s^2-ish forcing): two incommensurate gust cycles
local function windAt(t, seed)
	local gx = 0.6 * sin(t * 0.31 + seed) + 0.4 * sin(t * 0.83 + seed * 2.3) + 0.25 * sin(t * 1.9 + seed * 0.7)
	local gz = 0.5 * cos(t * 0.27 + seed * 1.4) + 0.35 * sin(t * 0.71 + seed * 0.4)
	return gx, gz
end

local function setWet(rec, q)
	rec.wetApplied = q
	for _, p in ipairs(rec.list) do
		local part = p.part
		if part and part.Parent then
			-- darker (a multiplier on the hair's own colours) and a touch shinier; never mirror-like
			local c = 1 - 0.3 * q
			part.Color = Color3.new(c, c, c)
			part.Reflectance = min(0.08, p.baseRefl + 0.05 * q)
		end
	end
end

-- (re)read the moving pieces of a model's built hair (OnBuilt hands us the pieces)
local function onBuilt(model, section, pieces)
	if section ~= "Hair" then
		return
	end
	local rec = meshes[model]
	local old = rec and rec.byName or {}
	rec = { model = model, list = {}, byName = {}, head = model:FindFirstChild("Head"), sweat = 0, nextAttr = 0, frame = 0,
		rest = true, wetApplied = -1, seed = (#model.Name * 1.37) % 6.28 }
	for name, pr in pairs(type(pieces) == "table" and pieces or {}) do
		local mesh = pr.mesh
		local fx = mesh and mesh.hairfx
		local part = pr.part
		local entry = {
			name = name, part = part, baseRefl = part and part.Reflectance or 0, fx = fx,
			-- spring state: swing angles (x about the head's X, z about its Z) / bounce height y
			x = 0, z = 0, y = 0, vx = 0, vz = 0, vy = 0, prevPos = nil, prevVel = Vector3.zero, written = false,
			cf = I,
		}
		if fx and type(fx.pivot) == "table" then
			entry.pivot = V3(fx.pivot[1], fx.pivot[2], fx.pivot[3])
			local tp = type(fx.tip) == "table" and fx.tip or fx.pivot
			entry.tip = V3(tp[1], tp[2], tp[3])
			entry.len = (entry.tip - entry.pivot).Magnitude
			entry.stiff = clamp(tonumber(fx.stiff) or 0.3, 0, 1)
			entry.mass = clamp(tonumber(fx.mass) or 1, 0.3, 3)
			entry.seg = tonumber(fx.seg) or 1
			entry.bounce = fx.kind == "bounce"
			entry.phase = (#rec.list * 1.618) % 6.28
			-- keep the motion state across a rebuild of the same piece (LOD flips) so nothing pops
			local prev = old[name]
			if prev and prev.fx then
				entry.x, entry.z, entry.y, entry.vx, entry.vz, entry.vy = prev.x, prev.z, prev.y, prev.vx, prev.vz, prev.vy
			end
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
	meshes[model] = rec
	rec.sweat = model:GetAttribute("Sweat")
	rec.sweat = type(rec.sweat) == "number" and clamp(rec.sweat, 0, 1) or 0
	if rec.sweat > 0.02 then
		setWet(rec, rec.sweat)
	end
end

local function onRestored(model, section)
	if section == "Hair" then
		meshes[model] = nil
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
		local p = e.pivot
		e.cf = CF(0, e.y, 0) * CF(p) * A(e.x, 0, e.z) * CF(-p)
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
	local wind = (1 - 0.6 * stiff) / mass * 0.035
	local tx = clamp(K.wrap(gx), -1.2, 1.2) * gw + idle * sin(t * 1.4 + e.phase) + wz * wind
	local tz = clamp(K.wrap(gz), -1.2, 1.2) * gw + idle * 0.7 * sin(t * 0.9 + e.phase * 1.7) + wx * wind
	e.vx += la.Z * gain * kk * dt
	e.vz += -la.X * gain * kk * dt
	e.x, e.vx = K.spring(e.x, e.vx, tx, kk, cc, dt)
	e.z, e.vz = K.spring(e.z, e.vz, tz, kk, cc, dt)
	local lim = e.seg <= 1 and 0.6 or 0.8
	if abs(e.x) > lim then
		e.x = clamp(e.x, -lim, lim)
		e.vx *= -0.3
	end
	if abs(e.z) > lim then
		e.z = clamp(e.z, -lim, lim)
		e.vz *= -0.3
	end
	local p = e.pivot
	-- the lower segment swings about its own pivot inside its parent's motion
	e.cf = parentCF * CF(p) * A(e.x, 0, e.z) * CF(-p)
end

local function stepMesh(rec, dt, t, hcf)
	local g = hcf:VectorToObjectSpace(DOWN)
	local wx, wz = windAt(t, rec.seed)
	-- wind in the head's frame (a world-space breeze)
	local wv = hcf:VectorToObjectSpace(V3(wx, 0, wz))
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
function HairFX.Update(dt, t, camPos, cam)
	frame += 1
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
		local hp = head.Position
		local dist = (hp - camPos).Magnitude
		local onScreen = true
		if cam and dist > 6 then
			local _, vis = cam:WorldToViewportPoint(hp)
			onScreen = vis
		end
		if dist > MID or not onScreen then
			if not rec.rest and dist > MID then
				relaxMesh(rec)
			end
			continue
		end
		local stepN = dist < NEAR and 1 or 2
		rec.frame += 1
		if rec.frame % stepN ~= 0 then
			continue
		end
		local sdt = min(dt * stepN, 1 / 15)
		rec.rest = false
		if t >= rec.nextAttr then
			rec.nextAttr = t + 0.5
			local sw = model:GetAttribute("Sweat")
			rec.sweat = type(sw) == "number" and clamp(sw, 0, 1) or 0
			if abs(rec.sweat - rec.wetApplied) >= 0.05 then
				setWet(rec, rec.sweat)
			end
		end
		stepMesh(rec, sdt, t, head.CFrame)
	end
	-- round-1 hair
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
		-- mesh hair replaces this model's round-1 hair: those parts are hidden, leave them at rest
		if meshes[model] then
			if not o.rest then
				relax(o)
			end
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
	local s = { meshModels = 0, meshPieces = 0, swing = 0, bounce = 0, models = 0, joints = 0 }
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
