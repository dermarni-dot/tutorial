-- FaceFX: a face that is alive. Client-only, driven by the Animator every frame.
-- Works on every character with a face rig (BuilderHead: Motor6D "FaceJoint", tag FaceRig,
-- attribute Role; BlinkLid parts), tagged by the Animator or not (players walking around blink too).
--  * blinking: natural intervals, double blinks, slower / heavier when tired or dazed, reflex
--    squeeze on hits; BlinkLid shown locally while closed (never the Lid SetDamage hides)
--  * eyes: gaze at a target (opponent, coach's athlete, camera in the Creator) with saccades and
--    micro-saccades, idle glances, dazed drift (Daze / Conc), rolled up when knocked out, pupil
--    dilation (fear / effort / pain) and a blown pupil when badly concussed
--  * expressions: Config.Expressions from the Expr attribute (ExprPreview wins on the local
--    character), blended smoothly; transient pain / effort / shout layers from the Animator;
--    mouth breathing from Stam / Effort; temple / forehead veins on anger, effort and strain
--  * anatomy meshes (AnatomyClient built the "Head" section, AnatomyHead.lua): the same channels drive
--    the mesh instead of the round-1 rig (which is hidden under it): lids turn about their hinge
--    (blinks, closure, swollen shut), eyeballs turn (gaze), the jaw piece swings (MouthLower), the Head
--    piece's blend shapes take the expression (10-15 Hz, one model per frame), fight damage swells
--    (morphs) and colours: AnatomyHeadDamage turns LookFx damage + the Grime attribute into 3D marks
--    (bruise blots weighted by surface distance and facing, curved tapered cuts, trickles running down
--    the surface) and a time-sliced job paints them into the head's texture (the head's triangles
--    rasterised into strips over several frames, at most PAINT_BUDGET of CPU per frame for all heads
--    together; the strips are written together when the job ends, so the face changes in one step; a
--    newer damage state is queued, never restarts a running job), or
--    into the vertex colours when the head has no texture; eye whites redden, the lids take the
--    bruise. Sweat sheen; a worn mouthguard colours the teeth. Mesh heads get a record from
--    Anatomy.OnBuilt even without a round-1 face rig (server detail "low")
-- Round-1 path writes only Motor6D.Transform, SpecialMesh.Scale/Offset and the Transparency of BlinkLid
-- and the face veins (client-toggled parts, CONTRACTS section 5); the mesh path writes only through
-- AnatomyClient (SetPieceTransform / SetMorphs / SetVertexColors), the Head pieces' Reflectance and the
-- pixels of the textures AnatomyClient made for them.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local K = require(script.Parent:WaitForChild("AnimKit"))


local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- optional: the anatomy meshes and the damage table (both absent = the round-1 path only)
local Anatomy
do
	local m = script.Parent:FindFirstChild("AnatomyClient")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	Anatomy = ok and type(mod) == "table" and mod or nil
end
local LookData
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local m = shared and shared:FindFirstChild("LookData")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	LookData = ok and type(mod) == "table" and mod or nil
end
-- the damage marks (AnatomyHeadDamage: pure, shared with tools); absent = swelling / marks off
local Damage
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local m = shared and shared:FindFirstChild("AnatomyHeadDamage")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	Damage = ok and type(mod) == "table" and mod or nil
end

local FaceFX = {}

local A = CFrame.Angles
local CF = CFrame.new
local I = CFrame.identity
local V3 = Vector3.new
local sin, abs, max, min, exp, atan2, sqrt = math.sin, math.abs, math.max, math.min, math.exp, math.atan2, math.sqrt
local clamp = math.clamp

local NEAR = 34 -- full face animation inside this distance
local MID = 60 -- blinking only up to here
local player = Players.LocalPlayer

------------------------------------------------------------------------
-- Expression channels
------------------------------------------------------------------------
-- 1 browUp, 2 browIn (+ inner up / - inner down), 3 knit, 4 lid (upper lid closure, - = wide),
-- 5 squint (lower lid up), 6 open (mouth), 7 press (lips), 8 smile (+ corners up, - down),
-- 9 snarl (upper lip up), 10 wide (corners out), 11 asym (one-sided smirk), 12 dilate (pupils)
local NCH = 12
local EXPR = {
	neutral = { 0, 0, 0, 0.05, 0, 0, 0.05, 0, 0, 0, 0, 0 },
	confident = { 0.1, 0, 0, 0.12, 0.15, 0, 0.2, 0.35, 0, 0.05, 0.8, 0 },
	determined = { -0.1, -0.5, 0.55, 0.15, 0.3, 0, 0.6, -0.1, 0, 0.05, 0, 0.05 },
	anger = { -0.3, -1.0, 1.0, -0.18, 0.45, 0.08, 0.65, -0.35, 0.6, 0.3, 0.15, 0.15 },
	fear = { 0.95, 1.0, 0.35, -0.5, 0, 0.32, 0, -0.35, 0.1, 0.85, 0, 0.3 },
	fatigue = { 0.1, 0.45, 0.1, 0.42, 0.05, 0.35, 0, -0.2, 0, 0.1, 0, 0 },
	pain = { 0.1, 0.55, 0.85, 0.55, 0.85, 0.3, 0, -0.6, 0.45, 0.6, 0.2, 0.2 },
	dazed = { 0.2, 0.3, 0, 0.45, 0, 0.22, 0, -0.15, 0, 0, 0.3, 0.1 },
	effort = { -0.1, -0.5, 0.7, 0.2, 0.6, 0.1, 0.3, -0.25, 0.5, 0.55, 0, 0.12 },
	happy = { 0.2, 0.1, 0, 0.12, 0.55, 0.12, 0, 1.0, 0.1, 0.2, 0.1, 0.05 },
	ko = { 0, 0.15, 0, 0.62, 0, 0.42, 0, -0.1, 0, 0, 0.4, 0.35 },
	shout = { 0.15, -0.5, 0.6, 0.05, 0.35, 0.85, 0, -0.1, 0.5, 0.5, 0, 0.1 },
}
local EXPR_NAMES = {}
for name in pairs(EXPR) do
	table.insert(EXPR_NAMES, name)
end
table.sort(EXPR_NAMES)
local EXPR_INDEX = {}
for i, name in ipairs(EXPR_NAMES) do
	EXPR_INDEX[name] = i
end
local NEXPR = #EXPR_NAMES

local ATTRS = { "Expr", "ExprPreview", "Stam", "Daze", "Conc", "Sweat", "Strain", "Effort", "FaceDmgTier", "Guard", "DownPose", "HeadHP" }
local ATTR_SET = {}
for _, k in ipairs(ATTRS) do
	ATTR_SET[k] = true
end

local faces = {} -- model -> rec

local function sideOf(part)
	local s = part:GetAttribute("Side")
	if type(s) == "number" then
		return s < 0 and -1 or 1
	end
	return nil
end

local function newRec(model)
	local seed = model:GetAttribute("AmbientSeed") or (#model.Name * 131 + 7)
	local rec = {
		model = model, dirty = true, folder = false, head = nil, a = {}, conn = nil,
		roles = {}, blink = {}, lids = {}, pupils = {}, veins = {}, rng = Random.new(seed),
		w = table.create(NEXPR, 0), ch = table.create(NCH, 0),
		nextBlink = 0, blinkT = -1, blinkLen = 0.16, double = false, closed = false,
		gy = 0, gp = 0, sy = 0, sp = 0, nextSac = 0, glanceY = 0, glanceP = 0, nextGlance = 0,
		painAmt = 0, painT = -10, effortAmt = 0, effortT = -10, effortDur = 0.4, shoutUntil = 0,
		breathPhase = 0, veinOn = false, active = false, h = 0.1, mw = 0.3, bt = 0.03,
		mv = nil, mvDirty = true, lidC = { [-1] = 0, [1] = 0 }, gazeOut = { [-1] = { 0, 0 }, [1] = { 0, 0 } },
	}
	rec.w[EXPR_INDEX.neutral] = 1
	for _, k in ipairs(ATTRS) do
		rec.a[k] = model:GetAttribute(k)
	end
	rec.conn = model.AttributeChanged:Connect(function(name)
		if ATTR_SET[name] then
			rec.a[name] = model:GetAttribute(name)
		end
	end)
	return rec
end

local function markModel(inst)
	local model = inst:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end
	local rec = faces[model]
	if not rec then
		rec = newRec(model)
		faces[model] = rec
	end
	rec.dirty = true
end

local function dropRec(model)
	local rec = faces[model]
	if rec then
		if rec.conn then
			rec.conn:Disconnect()
		end
		faces[model] = nil
	end
end

local function roleRec(m)
	local part = m.Part1
	local mesh = part and part:FindFirstChildOfClass("SpecialMesh")
	return {
		m = m, part = part, mesh = mesh, base = mesh and mesh.Scale or V3(1, 1, 1), off = mesh and mesh.Offset or Vector3.zero,
		side = sideOf(part) or (m:GetAttribute("Side") and (m:GetAttribute("Side") < 0 and -1 or 1)) or 0, last = nil,
	}
end

-- index the Face folder (destroyed and rebuilt by every Builder rebuild)
local function scan(rec)
	rec.dirty = false
	local model = rec.model
	local look = model:FindFirstChild("BoxerLook")
	local folder = look and look:FindFirstChild("Face")
	rec.folder = folder or false
	rec.head = model:FindFirstChild("Head")
	table.clear(rec.roles)
	table.clear(rec.blink)
	table.clear(rec.lids)
	table.clear(rec.pupils)
	table.clear(rec.veins)
	rec.closed = false
	if not folder then
		return
	end
	local head = rec.head
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "FaceJoint" then
			local role = d:GetAttribute("Role")
			if type(role) == "string" then
				rec.roles[role] = roleRec(d)
			end
		elseif d:IsA("BasePart") then
			local n = d.Name
			if n == "BlinkLid" then
				local s = sideOf(d)
				if s then
					rec.blink[s] = d
					d.Transparency = 1
				end
			elseif n == "Lid" then
				local s = sideOf(d)
				if s then
					rec.lids[s] = d
				end
			elseif n == "Pupil" and head then
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					local x = head.CFrame:PointToObjectSpace(d.Position).X
					rec.pupils[x < 0 and -1 or 1] = { mesh = mesh, base = mesh.Scale, last = 1 }
				end
			elseif n == "TempleVein" or n == "ForeheadVein" then
				local base = d:GetAttribute("BaseTransparency")
				table.insert(rec.veins, { part = d, base = type(base) == "number" and base or 0.5 })
			elseif n == "Sclera" then
				rec.h = d.Size.Y
				rec.ew = d.Size.X
			elseif n == "Iris" then
				rec.iw, rec.ih = d.Size.X, d.Size.Y
			elseif n == "UpperLip" then
				rec.mw = d.Size.X
			elseif n == "Brow" then
				rec.bt = d.Size.Y
			end
		end
	end
	rec.veinOn = false
	-- gaze slide: the EyeBall pivot sits only ~0.05 studs behind the iris, so turning it alone moves
	-- the iris ~10% of the eye's width. Slide it too, so a full look (yaw 0.35 / pitch 0.2) carries
	-- the iris ~85% of the way to the corner of the white (the lids cover the rest vertically)
	local ew, iw = rec.ew, rec.iw
	if ew and iw and ew > iw then
		rec.slideX = clamp((0.85 * (ew - iw) / 2 - 0.052 * sin(0.35)) / 0.35, 0, 0.12)
	else
		rec.slideX = 0.05
	end
	local eh, ih = rec.h, rec.ih
	if eh and ih and eh > ih then
		rec.slideY = clamp((0.85 * (eh - ih) / 2 - 0.052 * sin(0.2)) / 0.2, 0, 0.08)
	else
		rec.slideY = 0.03
	end
end

local function reset(rec)
	for _, r in pairs(rec.roles) do
		if r.m.Parent then
			r.m.Transform = I
			if r.mesh and (r.last or r.lo) then
				r.mesh.Scale = r.base
				r.mesh.Offset = r.off
			end
		end
		r.last = nil
		r.lc = nil
		r.lo, r.lw = nil, nil
	end
	for _, b in pairs(rec.blink) do
		if b.Parent then
			b.Transparency = 1
		end
	end
	for _, p in pairs(rec.pupils) do
		if p.mesh.Parent then
			p.mesh.Scale = p.base
		end
		p.last = 1
	end
	for _, v in ipairs(rec.veins) do
		if v.part.Parent then
			v.part.Transparency = 1
		end
	end
	rec.veinOn = false
	rec.closed = false
	rec.active = false
end

------------------------------------------------------------------------
-- Events from the Animator
------------------------------------------------------------------------
function FaceFX.Hit(model, sev)
	local rec = faces[model]
	if rec then
		rec.painAmt = clamp(0.45 + (sev or 0.5) * 0.6, 0, 1.2)
		rec.painT = os.clock()
		-- reflex squeeze: an immediate blink
		rec.blinkT = os.clock()
		rec.blinkLen = 0.22
		rec.double = false
	end
end

function FaceFX.Effort(model, amount, dur)
	local rec = faces[model]
	if rec then
		local now = os.clock()
		local cur = rec.effortAmt * clamp(1 - (now - rec.effortT) / max(0.05, rec.effortDur or 0.4), 0, 1)
		rec.effortAmt = max(cur, amount or 0.6)
		rec.effortT = now
		rec.effortDur = dur or 0.4
	end
end

function FaceFX.Shout(model, dur)
	local rec = faces[model]
	if rec then
		rec.shoutUntil = os.clock() + (dur or 0.8)
	end
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------
local function setT(r, cf)
	if r and r.m.Parent then
		r.m.Transform = cf
		r.last = true
	end
end

local function gazeTarget(rec, rig, model, camPos)
	if CollectionService:HasTag(model, "Preview") and model == player.Character then
		return camPos -- the Creator: look at the player
	end
	if rig then
		return rig.lookPos
	end
	return nil
end

-- rigs = the Animator's rig table (lookPos, exprHint, poseAct ...), may be nil

-- gaze: target / idle glances, micro-saccades, fast saccade smoothing, dazed drift; per eye { yaw, pitch }
-- (+ yaw looks left (-X), + pitch looks up (+Y)), shared by the round-1 rig and the mesh
local function gazeStep(rec, rig, model, camPos, head, dt, t, now, daze, conc, ko)
	local tgt = gazeTarget(rec, rig, model, camPos)
	local ty, tp = 0, 0
	if tgt then
		local lp = head.CFrame:PointToObjectSpace(tgt)
		ty = atan2(-lp.X, -lp.Z)
		tp = atan2(lp.Y, sqrt(lp.X * lp.X + lp.Z * lp.Z))
		if abs(ty) > 1.6 then
			ty, tp = 0, 0 -- behind the head: look ahead instead
		end
	else
		-- idle: glance around now and then
		if now >= rec.nextGlance then
			rec.nextGlance = now + rec.rng:NextNumber(1.2, 4.5)
			if rec.rng:NextNumber() < 0.55 then
				rec.glanceY, rec.glanceP = 0, 0
			else
				rec.glanceY = rec.rng:NextNumber(-0.28, 0.28)
				rec.glanceP = rec.rng:NextNumber(-0.12, 0.08)
			end
		end
		ty, tp = rec.glanceY, rec.glanceP
	end
	-- micro-saccades: tiny jumps every 0.3-1.2 s
	if now >= rec.nextSac then
		rec.nextSac = now + rec.rng:NextNumber(0.3, 1.2)
		rec.sy = rec.rng:NextNumber(-0.035, 0.035)
		rec.sp = rec.rng:NextNumber(-0.025, 0.025)
	end
	ty = clamp(ty + rec.sy, -0.35, 0.35)
	tp = clamp(tp + rec.sp, -0.2, 0.2)
	if ko then
		ty, tp = 0.05 * sin(t * 0.5), 0.2 -- eyes rolled up
	end
	-- saccades are fast (~30 ms), smooth pursuit slower
	local ga = 1 - exp(-dt * 32)
	rec.gy += (ty - rec.gy) * ga
	rec.gp += (tp - rec.gp) * ga
	local drift = clamp(daze / 3 + conc * 0.6, 0, 1)
	local out = rec.gazeOut
	for s = -1, 1, 2 do
		local dy = drift * 0.13 * K.noise(t * 0.6, s * 3)
		local dp = drift * 0.07 * K.noise(t * 0.5, s * 7 + 1)
		out[s][1], out[s][2] = rec.gy + dy, rec.gp + dp
	end
	return out
end

------------------------------------------------------------------------
-- Anatomy mesh path (AnatomyHead pieces: Head, EyeL/R, LidL/R, LidLow, MouthUpper/Lower, Beard at full;
-- Head, Eyes, LidUpper, Beard at medium; Head, Beard at low)
------------------------------------------------------------------------
local JAW_OPEN = math.rad(13) -- AnatomyHeadRig.JAW_OPEN: MouthLower's turn and the `open` morph at 1
local LID_SHUT = math.rad(48) -- the upper lid's turn that meets the lower lid
local MORPH_HZ = 14
local V2 = Vector2.new
local readu8, writeu8 = buffer.readu8, buffer.writeu8

-- one SetMorphs per frame across every model (each rewrites ~1000 vertices)
local morphFrame = 0
local morphFrameUsed = -1

local function vec(lms, name)
	local l = lms[name]
	local p = l and l.pos
	if type(p) ~= "table" then
		return nil
	end
	return V3(p[1], p[2], p[3])
end

-- the pieces AnatomyHead gives a colour texture (others never have one: no need to look)
local TEXTURED = {
	full = { Head = true, EyeL = true, EyeR = true, Beard = true }, medium = { Head = true, Beard = true }, low = { Head = true },
}

local function imageOf(part)
	if not part then
		return nil
	end
	local ok, img = pcall(function()
		local c = part.TextureContent
		return c and c.Object
	end)
	if not ok or img == nil then
		return nil
	end
	local okS, size = pcall(function()
		return img.Size
	end)
	if not okS or typeof(size) ~= "Vector2" then
		return nil
	end
	return img
end

-- what FaceFX drives on one model's Head section (rebuilt after every AnatomyClient build)
local function buildView(model)
	if not Anatomy then
		return nil
	end
	local ok, pieces = pcall(Anatomy.GetPieces, model, "Head")
	if not ok or type(pieces) ~= "table" or not pieces.Head then
		return nil
	end
	local okL, lms = pcall(Anatomy.GetLandmarks, model)
	lms = okL and type(lms) == "table" and lms or {}
	local v = {
		pieces = pieces, lod = pieces.Head.lod, lms = lms, active = false,
		eye = { [-1] = vec(lms, "EyeL"), [1] = vec(lms, "EyeR") },
		pivot = { [-1] = vec(lms, "LidPivotL"), [1] = vec(lms, "LidPivotR") },
		jaw = vec(lms, "JawPivot"),
		eyeR = lms.EyeRadius and lms.EyeRadius.pos and lms.EyeRadius.pos[1] or 0.06,
		w = {}, sent = {}, nextMorph = 0, hasMorphs = false,
		dmgSeen = false, dmgRaw = nil, dmgTier = 0, dmgGrime = 0, swell = {}, refl = -1, guardKey = false, nextGuard = 0,
		job = nil, jobArgs = nil,
	}
	local axis = {}
	for s = -1, 1, 2 do
		local a = vec(lms, s < 0 and "LidAxisL" or "LidAxisR")
		local p = v.pivot[s]
		if a and p and (a - p).Magnitude > 1e-6 then
			axis[s] = (a - p).Unit
		else
			axis[s] = V3(s, 0, 0)
		end
	end
	v.axis = axis
	local head = pieces.Head
	v.hasMorphs = v.lod == "full" and type(head.mesh) == "table" and type(head.mesh.morphs) == "table"
	-- textures: only where the generator made one and this client shows them
	local texOn = false
	pcall(function()
		texOn = Anatomy.Settings.textures ~= false and Anatomy.Status().textures ~= false
	end)
	local tex = texOn and TEXTURED[v.lod] or {}
	-- (AnatomyClient may hand the image out directly; else it is the part's TextureContent object)
	v.headImg = tex.Head and (head.image or imageOf(head.part)) or nil
	if pieces.EyeL and pieces.EyeR and tex.EyeL then
		v.eyeImg = { [-1] = pieces.EyeL.image or imageOf(pieces.EyeL.part), [1] = pieces.EyeR.image or imageOf(pieces.EyeR.part) }
	end
	return v
end

-- change-gated rigid motion: a Weld.C0 write only when the pose moved
local function setPiece(model, v, name, cf)
	if v.pieces[name] then
		local last = v.lastCF and v.lastCF[name]
		if last and last:FuzzyEq(cf, 1e-5) then
			return
		end
		v.lastCF = v.lastCF or {}
		v.lastCF[name] = cf
		Anatomy.SetPieceTransform(model, "Head", name, cf)
	end
end

-- back to the generated pose (out of range)
local function meshReset(model, v)
	for _, name in ipairs({ "LidL", "LidR", "LidLow", "LidUpper", "EyeL", "EyeR", "MouthLower" }) do
		setPiece(model, v, name, I)
	end
	if v.hasMorphs then
		table.clear(v.w)
		Anatomy.SetMorphs(model, "Head", "Head", v.w)
		table.clear(v.sent)
	end
	if v.pieces.Beard then
		Anatomy.SetMorphs(model, "Head", "Beard", v.w)
	end
	v.active = false
end

------------------------------------------------------------------------
-- Damage on the mesh: swelling (morphs, at once) and the marks AnatomyHeadDamage places on the surface (bruises,
-- cuts, blood, grime), painted by a time-sliced job: into the Head texture (one write when done) or its vertex
-- colours, the lids' skin, the eyeballs' whites
------------------------------------------------------------------------
local PAINT_BUDGET = 0.0015 -- seconds of damage painting per frame, every model together
local paintT0, paintLeft = 0, 0
-- called by AnatomyHeadDamage inside a job every few units of work: past this frame's budget -> next frame
local function paintStep()
	if os.clock() - paintT0 > paintLeft then
		coroutine.yield()
	end
end

-- the lids are vertex-coloured pieces beside the head: their skin (the generator's LidSkin group, never the lash
-- line or the lashes) takes a black eye's tint (multiplied into its own colour: deepest along the lash line)
-- plus any mark over it. Always from the generated colours, so a healed eye goes back exactly
local LID_PIECES = { "LidL", "LidR", "LidLow", "LidUpper", "Eyes" }
local function paintLids(model, v, marks, lid)
	v.lidTouched = v.lidTouched or {}
	for _, name in ipairs(LID_PIECES) do
		local pc = v.pieces[name]
		local ids = pc and pc.groups and pc.groups.LidSkin
		local mesh = pc and pc.mesh
		if type(ids) == "table" and type(mesh) == "table" and mesh.C then
			local P, C, N = mesh.P, mesh.C, mesh.N
			local was = v.lidTouched[name]
			local out, cols, any = {}, {}, false
			for n, i in ipairs(ids) do
				local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
				local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
				local hit = false
				local side = x < 0 and -1 or 1
				local t = lid[side]
				local e = v.eye[side]
				if t and e then
					local a = t[4] * (1 - 0.35 * clamp((abs(y - e.Y) / v.eyeR - 0.35) / 0.6, 0, 1))
					r, g, b = r * (1 + (t[1] - 1) * a), g * (1 + (t[2] - 1) * a), b * (1 + (t[3] - 1) * a)
					hit = true
				end
				if #marks > 0 then
					local nx, ny, nz = 0, 0, -1
					if N then
						nx, ny, nz = N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
					end
					local hm
					r, g, b, hm = Damage.Shade(marks, x, y, z, nx, ny, nz, 0.006, r, g, b)
					hit = hit or hm
				end
				if hit or was then
					out[#out + 1] = i
					cols[#cols + 1] = { clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1) }
					any = any or hit
				end
				if n % 64 == 0 then
					paintStep()
				end
			end
			v.lidTouched[name] = any
			if #out > 0 then
				pcall(Anatomy.SetVertexColors, model, "Head", name, out, cols)
			end
		end
	end
end

-- a job: the marks of one damage state, painted over the next frames (FaceFX.Update resumes it)
local function damageJob(model, v, dmg, tier, grime, red)
	local mesh = v.pieces.Head.mesh
	if not v.surf then
		v.surf = Damage.Surface(mesh, paintStep)
	end
	local marks, lid = Damage.Marks(v.lms, v.eyeR, dmg, tier, grime, v.surf, paintStep)
	local img = v.headImg
	if img and not v.orig then
		local okS, size = pcall(function()
			return img.Size
		end)
		local ok, buf = false, nil
		if okS and typeof(size) == "Vector2" then
			ok, buf = pcall(img.ReadPixelsBuffer, img, Vector2.zero, size)
		end
		if ok and type(buf) == "buffer" then
			v.orig, v.texW, v.texH = buf, size.X, size.Y
		else
			v.headImg, img = nil, nil
		end
	end
	if img then
		local strips, now = Damage.PaintTexture(mesh, v.texW, v.texH, v.orig, marks, v.painted, paintStep)
		-- every strip in the same frame: the face changes in one step
		for _, st in ipairs(strips or {}) do
			if not pcall(img.WritePixelsBuffer, img, V2(st[1], st[2]), V2(st[3], st[4]), st[5]) then
				v.headImg = nil
				break
			end
		end
		v.painted = now
	elseif type(mesh.C) == "table" then
		local ids, cols, now = Damage.PaintVertices(mesh, marks, v.touched, paintStep, nil, v.eyeR * 0.2)
		if #ids > 0 then
			pcall(Anatomy.SetVertexColors, model, "Head", "Head", ids, cols)
		end
		v.touched = now
	end
	paintLids(model, v, marks, lid)
	-- bloodshot whites (textured eyeballs)
	if v.eyeImg then
		v.eyeRed = v.eyeRed or { [-1] = 0, [1] = 0 }
		v.eyeOrig = v.eyeOrig or {}
		for s = -1, 1, 2 do
			local eimg = v.eyeImg[s]
			local k = red[s] or 0
			if eimg and abs(k - v.eyeRed[s]) > 0.005 then
				if not v.eyeOrig[s] then
					local okS, size = pcall(function()
						return eimg.Size
					end)
					local ok, buf = false, nil
					if okS and typeof(size) == "Vector2" then
						ok, buf = pcall(eimg.ReadPixelsBuffer, eimg, Vector2.zero, size)
					end
					if ok and type(buf) == "buffer" then
						v.eyeOrig[s] = { buf, size.X, size.Y }
					else
						v.eyeImg[s] = nil
					end
				end
				local o = v.eyeOrig[s]
				if o and v.eyeImg[s] then
					local pix = Damage.Sclera(o[2], o[3], o[1], k, s, paintStep)
					if pcall(eimg.WritePixelsBuffer, eimg, Vector2.zero, V2(o[2], o[3]), pix) then
						v.eyeRed[s] = k
					else
						v.eyeImg[s] = nil
					end
				end
			end
		end
	end
end

local warnedJob = false
local function runJob(v)
	local co = v.job
	paintT0 = os.clock()
	local ok, err = true, nil
	local args = v.jobArgs
	if args then
		v.jobArgs = nil
		ok, err = coroutine.resume(co, args[1], args[2], args[3], args[4], args[5], args[6])
	else
		ok, err = coroutine.resume(co)
	end
	if not ok then
		if not warnedJob then
			warnedJob = true
			warn("FaceFX: damage painting failed:", err)
		end
		-- this view paints no more (swelling still works)
		v.paintOff, v.nextArgs = true, nil
	end
	if coroutine.status(co) == "dead" then
		v.job = nil
		-- the newest state that came in meanwhile (coalesced: a job always finishes, so marks always show)
		if v.nextArgs then
			v.job, v.jobArgs, v.nextArgs = coroutine.create(damageJob), v.nextArgs, nil
		end
	end
	paintLeft -= os.clock() - paintT0
end

-- damage state -> swell weights (into v.swell), lids closing and a paint job; only when the LookFx string, the
-- damage tier or the (0.1-quantised) Grime attribute changed: no allocation on the frames between
local FX_ATTR = LookData and LookData.FX_ATTR or "LookFx"
local NO_DMG = {}
local function applyDamage(model, v, tier)
	local raw = model:GetAttribute(FX_ATTR)
	local grime = model:GetAttribute("Grime")
	grime = type(grime) == "number" and math.floor(clamp(grime, 0, 1) * 10 + 0.5) / 10 or 0
	if v.dmgSeen and raw == v.dmgRaw and tier == v.dmgTier and grime == v.dmgGrime then
		return
	end
	local first = not v.dmgSeen
	v.dmgSeen, v.dmgRaw, v.dmgTier, v.dmgGrime = true, raw, tier, grime
	local fx = LookData and LookData.Fx(model)
	local dmg = fx and fx.dmg or NO_DMG
	if not Damage then
		return
	end
	local swell, closing, red = Damage.Swell(dmg, tier)
	table.clear(v.swell)
	for k, w in pairs(swell) do
		v.swell[k] = w
	end
	v.closing = closing
	v.sent.__dmg = nil
	-- nothing to paint on a clean face that was never painted
	if v.paintOff or first and not Damage.Any(dmg, tier, grime) and red[-1] <= 0.01 and red[1] <= 0.01 then
		return
	end
	local args = { model, v, dmg, tier, grime, red }
	if v.job then
		-- a job is running: the newest state waits for it (it starts when that one is done)
		v.nextArgs = args
	else
		v.job, v.jobArgs = coroutine.create(damageJob), args
	end
end

-- a worn mouthguard (the round-1 part, hidden under the mesh) colours the upper teeth
local function applyGuard(model, v, now)
	if now < v.nextGuard then
		return
	end
	v.nextGuard = now + 1
	local up = v.pieces.MouthUpper
	local ids = up and up.groups and up.groups.Teeth
	if not ids then
		return
	end
	local look = model:FindFirstChild("BoxerLook")
	local face = look and look:FindFirstChild("Face")
	local mg = face and face:FindFirstChild("Mouthguard")
	local col = mg and mg:IsA("BasePart") and mg.Color or nil
	local key = col and string.format("%.3f%.3f%.3f", col.R, col.G, col.B) or "none"
	if key == v.guardKey then
		return
	end
	v.guardKey = key
	local C = up.mesh.C
	local cols = table.create(#ids)
	for k, i in ipairs(ids) do
		if col then
			-- keep the mesh's shading (gaps, the back teeth in shadow)
			local sh = clamp((C[i * 3 - 2] + C[i * 3 - 1] + C[i * 3]) / 2.55, 0.35, 1)
			cols[k] = { col.R * sh, col.G * sh, col.B * sh }
		else
			cols[k] = { C[i * 3 - 2], C[i * 3 - 1], C[i * 3] }
		end
	end
	Anatomy.SetVertexColors(model, "Head", "MouthUpper", ids, cols)
end

-- sweat: the same sheen BodyFX gives the body pieces
local function applySweat(v, sweat)
	local part = v.pieces.Head.part
	if not part or not part.Parent then
		return
	end
	local r = clamp(sweat * 0.06, 0, 0.08)
	if math.abs(r - v.refl) > 0.002 then
		v.refl = r
		part.Reflectance = r
	end
	-- wet skin is glossier: past a light sweat the face takes SmoothPlastic's tighter highlight (dry skin
	-- stays Plastic, matte); the build's own material comes back when it dries
	local wet = sweat > 0.35
	if wet ~= (v.wetMat == true) then
		if wet then
			v.dryMat = v.dryMat or part.Material
			part.Material = Enum.Material.SmoothPlastic
		elseif v.dryMat then
			part.Material = v.dryMat
		end
		v.wetMat = wet
	end
end

------------------------------------------------------------------------
-- Mesh update (per frame for models in range)
------------------------------------------------------------------------
local MORPHS = { "browUp", "browIn", "knit", "lid", "squint", "open", "press", "smile", "snarl", "wide", "asym", "breathe", "puff" }

local function q50(x)
	return math.floor(x * 50 + 0.5) / 50
end

local NO_CLOSING = { [-1] = 0, [1] = 0 }
local function meshUpdate(model, rec, v, ch, blinkC, lidC, gaze, near, now, a, breathe)
	v.active = true
	-- upper lids: closure (expression / blink / swollen shut) turns them about the hinge axis
	local closing = v.closing or NO_CLOSING
	for s = -1, 1, 2 do
		local c = max(lidC[s], blinkC)
		if closing[s] > 0 then
			c = max(c, 0.35 + 0.65 * closing[s])
		end
		c = clamp(c, -0.35, 1)
		local name = s < 0 and "LidL" or "LidR"
		local p, ax = v.pivot[s], v.axis[s]
		if v.pieces[name] and p then
			setPiece(model, v, name, CF(p) * CFrame.fromAxisAngle(ax, -s * c * LID_SHUT) * CF(-p))
		end
	end
	if v.pieces.LidUpper and v.pivot[-1] and v.pivot[1] then
		-- medium: both lids are one piece turning about the line through both eyes
		local c = clamp(max((lidC[-1] + lidC[1]) * 0.5, blinkC, closing[-1], closing[1]), -0.35, 1)
		local p = (v.pivot[-1] + v.pivot[1]) * 0.5
		setPiece(model, v, "LidUpper", CF(p) * A(-c * LID_SHUT, 0, 0) * CF(-p))
	end
	if not near then
		return
	end
	-- lower lids rise with the squint
	local sq = clamp(ch[5], 0, 1)
	setPiece(model, v, "LidLow", CF(0, sq * 0.2 * v.eyeR, -0.03 * v.eyeR * sq))
	-- eyeballs
	for s = -1, 1, 2 do
		local name = s < 0 and "EyeL" or "EyeR"
		local e = v.eye[s]
		if e and v.pieces[name] then
			local g = gaze[s]
			setPiece(model, v, name, CF(e) * A(g[2], g[1], 0) * CF(-e))
		end
	end
	-- the jaw
	local open = clamp(ch[6], 0, 1)
	if v.jaw and v.pieces.MouthLower then
		setPiece(model, v, "MouthLower", CF(v.jaw) * A(-JAW_OPEN * open, 0, 0) * CF(-v.jaw))
	end
	applyGuard(model, v, now)
	-- blend shapes at a low rate, one model per frame
	if not v.hasMorphs or now < v.nextMorph or morphFrameUsed == morphFrame then
		return
	end
	local w = v.w
	w.browUp, w.browIn, w.knit = q50(ch[1]), q50(ch[2]), q50(clamp(ch[3], 0, 1.2))
	w.lid = q50(clamp((lidC[-1] + lidC[1]) * 0.5 + blinkC * 0.6, -0.35, 1))
	w.squint, w.open, w.press = q50(sq), q50(open), q50(clamp(ch[7], -0.5, 1))
	w.smile, w.snarl, w.wide, w.asym = q50(clamp(ch[8], -1, 1)), q50(clamp(ch[9], 0, 1)), q50(clamp(ch[10], -0.5, 1)), q50(clamp(ch[11], -1, 1))
	w.breathe = q50(breathe)
	w.puff = q50(rec.puff or 0)
	for k, sw in pairs(v.swell) do
		w[k] = q50(sw)
	end
	-- drop swell weights that healed
	for k in pairs(w) do
		if string.sub(k, 1, 5) == "swell" and not v.swell[k] then
			w[k] = nil
		end
	end
	local same = true
	for k, x in pairs(w) do
		if v.sent[k] ~= x then
			same = false
			break
		end
	end
	if same then
		for k in pairs(v.sent) do
			if w[k] == nil then
				same = false
				break
			end
		end
	end
	if same then
		return
	end
	v.nextMorph = now + 1 / MORPH_HZ
	morphFrameUsed = morphFrame
	Anatomy.SetMorphs(model, "Head", "Head", w)
	if v.pieces.Beard then
		Anatomy.SetMorphs(model, "Head", "Beard", { open = w.open })
	end
	table.clear(v.sent)
	for k, x in pairs(w) do
		v.sent[k] = x
	end
end

function FaceFX.Update(dt, t, camPos, rigs, budget)
	local rescans = 0
	morphFrame += 1
	paintLeft = PAINT_BUDGET
	for model, rec in pairs(faces) do
		if not model.Parent then
			dropRec(model)
			continue
		end
		local head = rec.head
		if rec.dirty or not head or not head.Parent then
			if rescans >= (budget or 3) then
				continue
			end
			rescans += 1
			scan(rec)
			head = rec.head
			if not head then
				continue
			end
		end
		-- the anatomy mesh (rebuilt view after every AnatomyClient build of the Head section)
		if rec.mvDirty then
			rec.mvDirty = false
			rec.mv = buildView(model)
			if rec.mv and rec.active then
				reset(rec) -- the round-1 rig rests under the mesh
				rec.active = false
			end
		end
		local mv = rec.mv
		if mv and not (mv.pieces.Head.part and mv.pieces.Head.part.Parent) then
			mv, rec.mv, rec.mvDirty = nil, nil, true
		end
		if not mv and not next(rec.roles) and not next(rec.blink) then
			continue
		end
		local dist = (head.Position - camPos).Magnitude
		if dist > MID then
			if rec.active then
				reset(rec)
			end
			if mv and mv.active then
				meshReset(model, mv)
			end
			continue
		end
		if not mv then
			rec.active = true
		end
		local a = rec.a
		local rig = rigs and rigs[model]
		local near = dist < NEAR

		-- target expression
		local expr = a.Expr
		if model == player.Character and type(a.ExprPreview) == "string" then
			expr = a.ExprPreview
		end
		if rig and rig.exprHint then
			expr = rig.exprHint
		end
		local down = a.Guard == "down"
		if down and not expr then
			expr = "dazed"
		end
		local ti = EXPR_INDEX[expr or "neutral"] or EXPR_INDEX.neutral
		local rate = 1 - exp(-dt * 5)
		local w = rec.w
		for i = 1, NEXPR do
			w[i] += ((i == ti and 1 or 0) - w[i]) * rate
		end
		local ch = rec.ch
		for c = 1, NCH do
			ch[c] = 0
		end
		for i = 1, NEXPR do
			local wi = w[i]
			if wi > 0.002 then
				local e = EXPR[EXPR_NAMES[i]]
				for c = 1, NCH do
					ch[c] += e[c] * wi
				end
			end
		end
		-- transient layers
		local now = os.clock()
		local pain = rec.painAmt * K.attackDecay(now - rec.painT, 0.05, 0.75)
		if pain > 0.01 then
			local e = EXPR.pain
			for c = 1, NCH do
				ch[c] += (e[c] - ch[c]) * clamp(pain, 0, 1)
			end
		end
		local effort = rec.effortAmt * K.attackDecay(now - rec.effortT, 0.06, max(0.1, rec.effortDur or 0.4))
		local effAttr = type(a.Effort) == "number" and a.Effort or 0
		effort = max(effort, effAttr > 0.55 and (effAttr - 0.55) * 1.6 or 0)
		if effort > 0.01 then
			local e = EXPR.effort
			for c = 1, NCH do
				ch[c] += (e[c] - ch[c]) * clamp(effort, 0, 1) * 0.8
			end
		end
		if now < rec.shoutUntil then
			local e = EXPR.shout
			local k = clamp((rec.shoutUntil - now) * 4, 0, 1)
			for c = 1, NCH do
				ch[c] += (e[c] - ch[c]) * k
			end
		end
		local stam = type(a.Stam) == "number" and a.Stam or 1
		-- in a fight (a Guard attribute) the face carries the state of the exchange on top of the server's
		-- expression: spent (low stamina) sags into fatigue, a boxer who keeps landing (own punches in the last
		-- 2.5 s) without being hit for 5 s sets a confident half-smile; neither while hurt or down
		if a.Guard ~= nil and not down then
			local fat = clamp((0.45 - stam) / 0.35, 0, 1) * 0.65
			if fat > 0.01 and expr ~= "fatigue" then
				local e = EXPR.fatigue
				for c = 1, NCH do
					ch[c] += (e[c] - ch[c]) * fat
				end
			end
			local conf = (now - rec.effortT < 2.5 and now - rec.painT > 5 and stam > 0.4) and 0.35 or 0
			rec.confK = (rec.confK or 0) + (conf - (rec.confK or 0)) * clamp(dt * 1.5, 0, 1)
			if rec.confK > 0.01 and expr ~= "confident" then
				local e = EXPR.confident
				for c = 1, NCH do
					ch[c] += (e[c] - ch[c]) * rec.confK
				end
			end
		end
		-- breathing through the mouth when spent
		local breathe = clamp((1 - stam) * 1.3 + effAttr * 0.5 + (rig and rig.breath or 0), 0, 1)
		rec.breathPhase += dt * (0.25 + 0.45 * breathe)
		ch[6] += breathe * (0.12 + 0.22 * K.breath(rec.breathPhase))
		-- dazed / concussed: heavy lids, drifting gaze
		local daze = type(a.Daze) == "number" and a.Daze or 0
		local conc = type(a.Conc) == "number" and a.Conc or 0
		local tier = type(a.FaceDmgTier) == "number" and a.FaceDmgTier or 0
		ch[4] += 0.08 * daze + 0.03 * tier + (1 - stam) * 0.12
		local ko = down and expr == "ko"

		-- blink timing
		if rec.blinkT < 0 or now - rec.blinkT > rec.blinkLen + 0.05 then
			if now >= rec.nextBlink then
				rec.blinkT = now
				local slow = daze >= 2 or ko
				rec.blinkLen = slow and 0.35 or (0.13 + rec.rng:NextNumber() * 0.05)
				if not rec.double and rec.rng:NextNumber() < 0.15 then
					-- a quick second blink right after this one
					rec.double = true
					rec.nextBlink = now + rec.blinkLen + 0.1
				else
					rec.double = false
					-- tired or dazed people blink more often
					local tired = clamp(1 - stam + daze * 0.25, 0, 1)
					rec.nextBlink = now + rec.rng:NextNumber(2.4, 6.0) * (1 - 0.4 * tired)
				end
			end
		end
		local bel = now - rec.blinkT
		local blinkC = 0
		if rec.blinkT >= 0 and bel < rec.blinkLen then
			local L = rec.blinkLen
			if bel < L * 0.35 then
				blinkC = bel / (L * 0.35)
			elseif bel < L * 0.55 then
				blinkC = 1
			else
				blinkC = 1 - (bel - L * 0.55) / (L * 0.45)
			end
		end
		if ko then
			blinkC = max(blinkC, 0.55 + 0.1 * sin(t * 0.7))
		end
		if mv then
			-- the mesh: the same channels, lids / eyes / jaw / blend shapes / damage on the pieces
			local lidC = rec.lidC
			for s = -1, 1, 2 do
				lidC[s] = clamp(ch[4] + (daze >= 2 and 0.1 * s or 0) + ch[11] * 0.04 * s, -0.35, 1)
			end
			local gz = rec.gazeOut
			if near then
				gz = gazeStep(rec, rig, model, camPos, head, dt, t, now, daze, conc, ko)
			end
			applyDamage(model, mv, tier)
			if mv.job and paintLeft > 0 then
				runJob(mv)
			end
			applySweat(mv, type(a.Sweat) == "number" and a.Sweat or 0)
			local flare = breathe * (0.35 + 0.65 * max(0, K.breath(rec.breathPhase)))
			meshUpdate(model, rec, mv, ch, blinkC, lidC, gz, near, now, a, flare)
			continue
		end
		local closed = blinkC > 0.82
		if closed ~= rec.closed then
			rec.closed = closed
			for s, b in pairs(rec.blink) do
				local lid = rec.lids[s]
				local shut = lid and lid.Transparency >= 1 -- swollen shut: SetDamage owns that eye
				if b.Parent then
					b.Transparency = (closed and not shut) and 0 or 1
				end
			end
		end
		if not near then
			continue
		end
		local roles = rec.roles
		local h, mw = rec.h, rec.mw

		-- gaze
		local gz = gazeStep(rec, rig, model, camPos, head, dt, t, now, daze, conc, ko)
		for s = -1, 1, 2 do
			local r = roles[s < 0 and "EyeL" or "EyeR"]
			if r then
				local gy, gp = gz[s][1], gz[s][2]
				-- + yaw looks left (-X), + pitch looks up (+Y): the iris slides with the turn
				setT(r, CF(-gy * rec.slideX, gp * rec.slideY, 0) * A(gp, gy, 0))
			end
		end

		-- brows
		local browUp, browIn, knit = ch[1], ch[2], ch[3]
		for s = -1, 1, 2 do
			local r = roles[s < 0 and "BrowL" or "BrowR"]
			if r then
				local asymK = 1 + ch[11] * 0.35 * s
				local y = (browUp * 0.42 + max(browIn, 0) * 0.12 - max(-browIn, 0) * 0.1) * h * asymK
				setT(r, CF(-s * knit * h * 0.16, y, 0) * A(0, 0, -s * browIn * 0.2))
			end
		end
		-- upper lids (partial closure) and lower lids (squint)
		local lidBase = ch[4]
		for s = -1, 1, 2 do
			local r = roles[s < 0 and "LidL" or "LidR"]
			local lidPart = rec.lids[s]
			if r and lidPart and lidPart.Transparency < 1 then
				local c = clamp(lidBase + (daze >= 2 and 0.1 * s or 0) + ch[11] * 0.04 * s, -0.35, 1)
				c = max(c, blinkC * 0.9)
				if c >= 0 then
					setT(r, CF(0, -c * h * 0.3, -c * 0.006))
				else
					setT(r, CF(0, -c * h * 0.16, 0))
				end
				-- a closing lid also grows downwards over the eye (mesh only, never Size)
				local q = math.floor(max(c, 0) * 50 + 0.5) / 50
				if r.mesh and q ~= r.lc then
					r.lc = q
					r.mesh.Scale = V3(r.base.X, r.base.Y * (1 + 0.9 * q), r.base.Z)
				end
			end
			local lr = roles[s < 0 and "LowerLidL" or "LowerLidR"]
			if lr then
				setT(lr, CF(0, clamp(ch[5], 0, 1) * h * 0.17, -0.002 * ch[5]))
			end
		end
		-- mouth
		local open, press, smile, snarl, wide = clamp(ch[6], 0, 1), ch[7], ch[8], clamp(ch[9], 0, 1), ch[10]
		setT(roles.UpperLip, CF(0, (snarl * 0.3 + open * 0.1 - press * 0.03) * mw * 0.25, 0))
		setT(roles.LowerLip, CF(0, (-open * 0.34 + press * 0.04) * mw, -press * 0.004))
		for s = -1, 1, 2 do
			local r = roles[s < 0 and "MouthCornerL" or "MouthCornerR"]
			if r then
				local sm = smile * (1 + ch[11] * 0.8 * s)
				setT(r, CF(s * wide * mw * 0.07, sm * mw * 0.085 - open * mw * 0.14, 0))
			end
		end
		local inside = roles.MouthInside
		if inside then
			setT(inside, CF(0, -open * mw * 0.15, 0))
			if inside.mesh then
				-- quantized + change-gated like every other mesh write (each write re-meshes the part)
				local qo, qw = math.floor(open * 40 + 0.5) / 40, math.floor(wide * 40 + 0.5) / 40
				if qo ~= inside.lo or qw ~= inside.lw then
					inside.lo, inside.lw = qo, qw
					inside.mesh.Scale = V3(inside.base.X * (1 + qw * 0.15), inside.base.Y * (1 + qo * 2.4), inside.base.Z)
				end
			end
		end
		-- pupils: dilate with fear / effort / pain; anisocoria when badly concussed
		local dil = 1 + clamp(ch[12], -0.2, 0.5) + pain * 0.15
		for s, p in pairs(rec.pupils) do
			local d = dil
			if daze >= 2 or conc > 0.7 then
				d *= s < 0 and 1.28 or 0.94
			end
			d = math.floor(d * 40 + 0.5) / 40
			if d ~= p.last and p.mesh.Parent then
				p.last = d
				p.mesh.Scale = V3(p.base.X * d, p.base.Y * d, p.base.Z)
			end
		end
		-- veins: anger, effort, strain or a heavy sweat
		local strain = type(a.Strain) == "number" and a.Strain or 0
		local sweat = type(a.Sweat) == "number" and a.Sweat or 0
		local angerW = w[EXPR_INDEX.anger] + w[EXPR_INDEX.effort] + effort * 0.8 + (now < rec.shoutUntil and 0.6 or 0)
		local veinOn = angerW > 0.5 or strain > 0.5 or sweat > 0.6
		if veinOn ~= rec.veinOn then
			rec.veinOn = veinOn
			for _, v in ipairs(rec.veins) do
				if v.part.Parent then
					v.part.Transparency = veinOn and v.base or 1
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Discovery: face rig joints come and go with every Builder rebuild
------------------------------------------------------------------------
CollectionService:GetInstanceAddedSignal("FaceRig"):Connect(markModel)
CollectionService:GetInstanceRemovedSignal("FaceRig"):Connect(markModel)
for _, m in ipairs(CollectionService:GetTagged("FaceRig")) do
	markModel(m)
end
-- preview clones (the main menu's stage boxer) lose their tags but keep the rig: tracked by the model's
-- Preview tag (scan finds the FaceJoint motors by name)
local function markPreview(inst)
	if inst:IsA("Model") and inst:FindFirstChild("Head") then
		local rec = faces[inst]
		if not rec then
			rec = newRec(inst)
			faces[inst] = rec
		end
		rec.dirty = true
	end
end
CollectionService:GetInstanceAddedSignal("Preview"):Connect(markPreview)
for _, m in ipairs(CollectionService:GetTagged("Preview")) do
	markPreview(m)
end

-- the anatomy meshes come and go with AnatomyClient builds / restores
if Anatomy and Anatomy.OnBuilt and Anatomy.OnRestored then
	Anatomy.OnBuilt:Connect(function(model, section)
		if section == "Head" then
			-- every built head gets a record: crowd / low-detail characters carry no round-1 face rig (never
			-- tagged FaceRig) but still blink their lids, swell and show their damage on the mesh
			local rec = faces[model]
			if not rec then
				rec = newRec(model)
				faces[model] = rec
			end
			rec.mvDirty = true
		end
	end)
	Anatomy.OnRestored:Connect(function(model, section)
		if section == "Head" then
			local rec = faces[model]
			if rec then
				rec.mv, rec.mvDirty = nil, false
			end
		end
	end)
end

-- tests / tools: what FaceFX knows about a model (nil = not tracked)
function FaceFX.Debug(model)
	local rec = faces[model]
	if not rec then
		return nil
	end
	local mv = rec.mv
	return {
		mesh = mv ~= nil, meshActive = mv and mv.active or false, lod = mv and mv.lod, roles = next(rec.roles) ~= nil,
		active = rec.active, dirty = rec.dirty, mvDirty = rec.mvDirty, headImage = mv and mv.headImg ~= nil or false,
		morphs = mv and mv.hasMorphs or false, painting = mv and mv.job ~= nil or false,
		painted = mv and (next(mv.painted or {}) ~= nil or next(mv.touched or {}) ~= nil) or false,
	}
end

FaceFX.Expressions = EXPR
return FaceFX
