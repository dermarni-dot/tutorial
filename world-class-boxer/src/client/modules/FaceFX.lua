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
--    (morphs) and colours (bruises, cuts, blood painted into the head's texture, or its vertex colours
--    when textures are off), sweat sheen, a worn mouthguard colours the teeth
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
local BRUISE_STOPS
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local m = shared and shared:FindFirstChild("Config")
	local ok, Config = false, nil
	if m then
		ok, Config = pcall(require, m)
	end
	BRUISE_STOPS = ok and type(Config) == "table" and Config.FaceDamage and Config.FaceDamage.bruiseColors
	BRUISE_STOPS = BRUISE_STOPS or { { day = 0, rgb = { 95, 25, 40 } }, { day = 1, rgb = { 70, 45, 95 } }, { day = 4, rgb = { 150, 150, 70 } }, { day = 8 } }
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
	confident = { 0.12, 0, 0, 0.14, 0.1, 0, 0.25, 0.28, 0, 0.05, 0.7, 0 },
	determined = { -0.1, -0.45, 0.45, 0.16, 0.3, 0, 0.6, -0.1, 0, 0.05, 0, 0.05 },
	anger = { -0.2, -0.9, 0.85, 0.05, 0.5, 0.12, 0.2, -0.35, 0.65, 0.4, 0.2, 0.15 },
	fear = { 0.65, 0.85, 0.3, -0.28, 0, 0.25, 0, -0.3, 0.1, 0.35, 0, 0.3 },
	fatigue = { 0.1, 0.45, 0.1, 0.42, 0.05, 0.35, 0, -0.2, 0, 0.1, 0, 0 },
	pain = { 0.1, 0.55, 0.75, 0.55, 0.8, 0.3, 0, -0.6, 0.35, 0.6, 0.2, 0.2 },
	dazed = { 0.2, 0.3, 0, 0.45, 0, 0.22, 0, -0.15, 0, 0, 0.3, 0.1 },
	effort = { -0.1, -0.4, 0.6, 0.2, 0.6, 0.1, 0.15, -0.25, 0.5, 0.55, 0, 0.12 },
	happy = { 0.3, 0.1, 0, 0.1, 0.4, 0.3, 0, 0.95, 0.1, 0.45, 0.1, 0.05 },
	ko = { 0, 0.15, 0, 0.62, 0, 0.42, 0, -0.1, 0, 0, 0.4, 0.35 },
	shout = { 0.15, -0.5, 0.5, 0.1, 0.35, 0.75, 0, -0.1, 0.5, 0.5, 0, 0.1 },
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
local TEXTURED = { full = { Head = true, EyeL = true, EyeR = true, Beard = true }, medium = { Head = true, Beard = true } }

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
		dmgStr = false, swell = {}, refl = -1, guardKey = false, nextGuard = 0,
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
-- Damage on the mesh: swelling (morphs), bruises / cuts / blood (texture pixels or vertex colours)
------------------------------------------------------------------------
local function bruiseRGB(sr, sg, sb, age)
	local function col(stop)
		if stop and stop.rgb then
			return stop.rgb[1] / 255, stop.rgb[2] / 255, stop.rgb[3] / 255
		end
		return sr, sg, sb
	end
	local r, g, b = col(BRUISE_STOPS[1])
	for i = 1, #BRUISE_STOPS - 1 do
		local a, c = BRUISE_STOPS[i], BRUISE_STOPS[i + 1]
		if age >= a.day and age <= c.day then
			local t = (age - a.day) / max(0.01, c.day - a.day)
			local r0, g0, b0 = col(a)
			local r1, g1, b1 = col(c)
			r, g, b = r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t
			break
		elseif age > c.day then
			r, g, b = col(c)
		end
	end
	-- deep skin bruises darker rather than purple
	local dark = clamp((0.45 - (0.299 * sr + 0.587 * sg + 0.114 * sb)) / 0.3, 0, 1)
	local k = dark * 0.55
	return r + (sr * 0.55 - r) * k, g + (sg * 0.55 - g) * k, b + (sb * 0.55 - b) * k
end

-- the marks a damage table leaves, in the Head part's space: ellipses { x, y, rx, ry, rot } and lines
-- { x, y, x1, y1, w }, each with a colour and an opacity
local function damageBlobs(model, v, dmg, tier)
	local lms = v.lms
	local function p(name)
		local l = lms[name]
		return l and l.pos
	end
	local eL, eR = p("EyeL"), p("EyeR")
	if not (eL and eR) then
		return {}, {}, {}
	end
	local k = v.eyeR / 0.06
	local function n(key)
		return clamp(tonumber(dmg[key]) or 0, 0, 1.5)
	end
	local look = LookData and LookData.Get(model)
	local rgb = look and type(look.skinRGB) == "table" and look.skinRGB or { 200, 150, 110 }
	local sr, sg, sb = (rgb[1] or 200) / 255, (rgb[2] or 150) / 255, (rgb[3] or 110) / 255
	local age = max(0, tonumber(dmg.age) or 0)
	local fade = clamp(1 - age / 8, 0.15, 1)
	local fresh = age < 0.5
	local br, bg, bb = bruiseRGB(sr, sg, sb, age)
	local blobs = {}
	local function ell(x, y, rx, ry, rot, r, g, b, a)
		if a > 0.01 then
			blobs[#blobs + 1] = { kind = 1, x = x, y = y, rx = rx, ry = ry, rot = rot or 0, r = r, g = g, b = b, a = a }
		end
	end
	local function line(x, y, x1, y1, w, r, g, b, a)
		if a > 0.01 then
			blobs[#blobs + 1] = { kind = 2, x = x, y = y, x1 = x1, y1 = y1, rx = w, ry = w, r = r, g = g, b = b, a = a }
		end
	end
	local swell = {}
	local lid = {}
	local eyes = { [-1] = { eL, n("leftEye"), n("cheekL"), n("earL") }, [1] = { eR, n("rightEye"), n("cheekR"), n("earR") } }
	for s = -1, 1, 2 do
		local e, ev, ck, ear = eyes[s][1], eyes[s][2], eyes[s][3], eyes[s][4]
		local tag = s < 0 and "L" or "R"
		if ev > 0.08 then
			-- a black eye: round the orbit on the skin the lids leave visible (under the eye deepest, the lid
			-- crease, the outer corner; the eye opening itself is no paintable skin)
			local a0 = clamp(0.15 + 0.6 * ev, 0, 0.8) * fade
			local r0 = (0.045 + 0.02 * ev) * k
			ell(e[1] + s * 0.01 * k, e[2] - 0.058 * k, r0 * 1.5, r0, 0, br, bg, bb, a0)
			ell(e[1], e[2] + 0.062 * k, r0 * 1.4, r0 * 0.75, 0, br, bg, bb, a0 * 0.8)
			ell(e[1] + s * 0.075 * k, e[2] + 0.004 * k, r0 * 0.8, r0 * 1.2, 0, br, bg, bb, a0 * 0.75)
			ell(e[1] - s * 0.062 * k, e[2] - 0.01 * k, r0 * 0.6, r0, 0, br, bg, bb, a0 * 0.6)
			-- the lids themselves (separate vertex-coloured pieces) take most of the colour
			lid[s] = { br, bg, bb, a0 * 0.85 }
		end
		if ck > 0.1 then
			ell(s * 0.25 * k, e[2] - 0.085 * k, (0.07 + 0.03 * ck) * k, (0.055 + 0.02 * ck) * k, s * 0.3, br, bg, bb, clamp(0.1 + 0.45 * ck, 0, 0.6) * fade)
		end
		swell["swellEye" .. tag] = clamp(ev * 0.9, 0, 1.2)
		swell["swellCheek" .. tag] = clamp(ck * 0.85, 0, 1.2)
		swell["swellEar" .. tag] = clamp(ear, 0, 1.2)
	end
	local bru = n("bruise")
	if bru > 0.2 then
		for s = -1, 1, 2 do
			ell(s * 0.27 * k, eL[2] - 0.07 * k, 0.09 * k, 0.07 * k, 0, br, bg, bb, clamp(0.08 + 0.3 * bru, 0, 0.45) * fade)
		end
	elseif tier >= 1 or n("redness") > 0.1 then
		local r = max(n("redness"), 0.3)
		for s = -1, 1, 2 do
			ell(s * 0.27 * k, eL[2] - 0.07 * k, 0.1 * k, 0.075 * k, 0, 0.8, 0.25, 0.25, 0.06 + 0.12 * r)
		end
	end
	local tip, nas = p("NoseTip"), p("Nasion")
	if dmg.nose == true and tip and nas then
		ell((tip[1] + nas[1]) * 0.5, (tip[2] + nas[2]) * 0.5, 0.035 * k, 0.075 * k, 0.15, br, bg, bb, 0.35 * fade)
		swell.swellNose = 0.6
	end
	local cutSide = (tonumber(dmg.cutSide) or 1) < 0 and -1 or 1
	local lump = n("forehead")
	if lump > 0.2 then
		ell(cutSide * 0.12 * k, eL[2] + 0.19 * k, (0.04 + 0.02 * lump) * k, (0.035 + 0.015 * lump) * k, 0, br, bg, bb, 0.3 * fade)
		swell[cutSide < 0 and "swellBrowL" or "swellBrowR"] = clamp(lump, 0, 1.2)
	end
	-- cuts over the eyes (the second on the other side by default), bleeding while fresh
	local cuts = { { n("cut"), cutSide, 0 }, { n("cut2"), (tonumber(dmg.cutSide2) or -cutSide) < 0 and -1 or 1, 0.025 } }
	for _, c in ipairs(cuts) do
		local cv, s, up = c[1], c[2], c[3]
		if cv > 0.05 then
			local mid = p(s < 0 and "BrowMidL" or "BrowMidR")
			local outer = p(s < 0 and "BrowOuterL" or "BrowOuterR")
			if mid and outer then
				local y0 = mid[2] + (0.02 + up) * k
				local len = (0.05 + 0.05 * min(cv, 1)) * k
				local x0 = mid[1] + s * 0.012 * k
				local x1, y1 = x0 + s * len, y0 + 0.008 * k
				-- fresh: open and red; after a day a dark scab; after a week a pink healing line
				local cr, cg, cb = 0.42, 0.02, 0.03
				if age > 1 then
					local h = clamp((age - 1) / 6, 0, 1)
					cr, cg, cb = 0.28 + 0.5 * h, 0.08 + 0.4 * h, 0.07 + 0.38 * h
				end
				line(x0, y0, x1, y1, (0.004 + 0.003 * min(cv, 1)) * k, cr, cg, cb, 0.95 * (1 - 0.4 * clamp((age - 4) / 6, 0, 1)))
				if cv > 0.35 and fresh then
					line(x1, y1, x1 + s * 0.012 * k, y1 - (0.08 + 0.18 * min(cv, 1)) * k, 0.008 * k, 0.5, 0.02, 0.04, 0.8)
				end
			end
		end
	end
	local bleed = n("noseBleed")
	if bleed > 0.2 and fresh then
		for s = -1, 1, 2 do
			local ns = p(s < 0 and "NostrilL" or "NostrilR")
			local lu = p("LipUpper")
			if ns and lu then
				line(ns[1], ns[2], ns[1] * 1.25, lu[2] + (0.03 - 0.03 * bleed) * k, (0.007 + 0.004 * bleed) * k, 0.5, 0.02, 0.04, 0.85)
			end
		end
	end
	local lip = n("lip")
	local ll = p("LipLower")
	if lip > 0.25 and ll then
		ell(ll[1] + 0.045 * k, ll[2] - 0.004 * k, (0.012 + 0.008 * lip) * k, (0.009 + 0.004 * lip) * k, 0, 0.45, 0.02, 0.05, 0.9)
		ell(ll[1] + 0.03 * k, ll[2], 0.045 * k, 0.02 * k, 0, br, bg, bb, clamp(0.3 * lip, 0, 0.4) * fade)
		swell.swellLip = clamp((lip - 0.25) * 1.3, 0, 1.2)
		if lip > 0.6 and fresh then
			line(ll[1] + 0.05 * k, ll[2] - 0.01 * k, ll[1] + 0.055 * k, ll[2] - 0.11 * k, 0.008 * k, 0.48, 0.02, 0.04, 0.8)
		end
	end
	local chin = p("Chin")
	if tier >= 4 and fresh and chin and (n("cut") > 0.3 or bleed > 0.3 or lip > 0.5) then
		ell(chin[1] + 0.02 * k, chin[2] + 0.04 * k, 0.09 * k, 0.045 * k, 0, 0.43, 0.02, 0.04, 0.5)
	end
	return blobs, swell, lid
end

-- (x, y) on the face front -> texture (u, v), from the Head mesh's own vertices (front-facing grid only)
local function uvLookup(mesh)
	local P, U = mesh.P, mesh.U
	local cell = 0.025
	local bins = {}
	for i = 1, mesh.nv do
		local z = P[i * 3]
		local v = U[i * 2]
		if z < -0.05 and v < 0.9 then
			local cx, cy = math.floor(P[i * 3 - 2] / cell), math.floor(P[i * 3 - 1] / cell)
			local key = cy * 4096 + cx
			local b = bins[key]
			if not b then
				b = {}
				bins[key] = b
			end
			b[#b + 1] = i
		end
	end
	local function uvAt(x, y)
		local cx, cy = math.floor(x / cell), math.floor(y / cell)
		-- the three nearest (x, y) vertices, the most forward wins ties (nose over cheek)
		local b1, b2, b3, d1, d2, d3 = 0, 0, 0, math.huge, math.huge, math.huge
		for oy = -1, 1 do
			for ox = -1, 1 do
				local b = bins[(cy + oy) * 4096 + cx + ox]
				if b then
					for _, i in ipairs(b) do
						local dx, dy = P[i * 3 - 2] - x, P[i * 3 - 1] - y
						local d = dx * dx + dy * dy
						if d < d1 then
							b3, d3, b2, d2, b1, d1 = b2, d2, b1, d1, i, d
						elseif d < d2 then
							b3, d3, b2, d2 = b2, d2, i, d
						elseif d < d3 then
							b3, d3 = i, d
						end
					end
				end
			end
		end
		if b1 == 0 then
			return nil
		end
		local w1, w2, w3 = 1 / (d1 + 1e-7), b2 > 0 and 1 / (d2 + 1e-7) or 0, b3 > 0 and 1 / (d3 + 1e-7) or 0
		local sw = w1 + w2 + w3
		local u = (U[b1 * 2 - 1] * w1 + (b2 > 0 and U[b2 * 2 - 1] * w2 or 0) + (b3 > 0 and U[b3 * 2 - 1] * w3 or 0)) / sw
		local v = (U[b1 * 2] * w1 + (b2 > 0 and U[b2 * 2] * w2 or 0) + (b3 > 0 and U[b3 * 2] * w3 or 0)) / sw
		return u, v
	end
	return uvAt
end

-- the blob's opacity at head-space offset (dx, dy) from its anchor
local function blobAlpha(b, dx, dy)
	if b.kind == 1 then
		local c, s = math.cos(b.rot), math.sin(b.rot)
		local qx, qy = (dx * c + dy * s) / b.rx, (-dx * s + dy * c) / b.ry
		local q = qx * qx + qy * qy
		if q >= 1 then
			return 0
		end
		local w = 1 - q
		return w * w * b.a
	end
	local vx, vy = b.x1 - b.x, b.y1 - b.y
	local l2 = vx * vx + vy * vy
	local t = l2 > 0 and clamp((dx * vx + dy * vy) / l2, 0, 1) or 0
	local ex, ey = dx - vx * t, dy - vy * t
	local d = math.sqrt(ex * ex + ey * ey) / b.rx
	if d >= 1 then
		return 0
	end
	-- a streak thins toward its end
	return (1 - d * d) * b.a * (1 - 0.5 * t)
end

-- paint the blobs into the Head's texture (from the pixels AnatomyClient made: never accumulates)
local function paintImage(v, blobs)
	local img = v.headImg
	local mesh = v.pieces.Head.mesh
	v.uvAt = v.uvAt or uvLookup(mesh)
	local size = img.Size
	local W, H = size.X, size.Y
	if not v.orig then
		local ok, buf = pcall(img.ReadPixelsBuffer, img, Vector2.zero, size)
		if not ok then
			v.headImg = nil
			return false
		end
		v.orig = buf
	end
	local uvAt = v.uvAt
	local hstep = 0.02
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, b in ipairs(blobs) do
		local u, vv = uvAt(b.x, b.y)
		local ux, vx = uvAt(b.x + hstep, b.y)
		local uy, vy = uvAt(b.x, b.y + hstep)
		if u and ux and uy then
			-- the local map from head-space offsets to UV, inverted for the texel loop
			local a11, a12, a21, a22 = (ux - u) / hstep, (uy - u) / hstep, (vx - vv) / hstep, (vy - vv) / hstep
			local det = a11 * a22 - a12 * a21
			if math.abs(det) > 1e-9 then
				b.u, b.v = u, vv
				b.i11, b.i12, b.i21, b.i22 = a22 / det, -a12 / det, -a21 / det, a11 / det
				local ext = b.kind == 1 and max(b.rx, b.ry) or (math.sqrt((b.x1 - b.x) ^ 2 + (b.y1 - b.y) ^ 2) + b.rx)
				local cxA, cyA = b.kind == 1 and 0 or (b.x1 - b.x) * 0.5, b.kind == 1 and 0 or (b.y1 - b.y) * 0.5
				local cu = u + a11 * cxA + a12 * cyA
				local cv = vv + a21 * cxA + a22 * cyA
				local eu = (math.abs(a11) + math.abs(a12)) * ext
				local ev = (math.abs(a21) + math.abs(a22)) * ext
				b.px0, b.px1 = max(0, math.floor((cu - eu) * W)), min(W - 1, math.ceil((cu + eu) * W))
				b.py0, b.py1 = max(0, math.floor((cv - ev) * H)), min(H - 1, math.ceil((cv + ev) * H))
				x0, y0, x1, y1 = min(x0, b.px0), min(y0, b.py0), max(x1, b.px1), max(y1, b.py1)
			end
		end
	end
	-- repaint where marks are now and where they were
	local last = v.lastRect
	if last then
		x0, y0, x1, y1 = min(x0, last[1]), min(y0, last[2]), max(x1, last[3]), max(y1, last[4])
	end
	if x1 < x0 or y1 < y0 then
		return true
	end
	local rw, rh = x1 - x0 + 1, y1 - y0 + 1
	local out = buffer.create(rw * rh * 4)
	local orig = v.orig
	for py = y0, y1 do
		for px = x0, x1 do
			local o = (py * W + px) * 4
			local r, g, b = readu8(orig, o) / 255, readu8(orig, o + 1) / 255, readu8(orig, o + 2) / 255
			for _, bl in ipairs(blobs) do
				if bl.u and px >= bl.px0 and px <= bl.px1 and py >= bl.py0 and py <= bl.py1 then
					local du, dv = (px + 0.5) / W - bl.u, (py + 0.5) / H - bl.v
					local a = blobAlpha(bl, bl.i11 * du + bl.i12 * dv, bl.i21 * du + bl.i22 * dv)
					if a > 0 then
						r, g, b = r + (bl.r - r) * a, g + (bl.g - g) * a, b + (bl.b - b) * a
					end
				end
			end
			local q = ((py - y0) * rw + (px - x0)) * 4
			writeu8(out, q, math.floor(clamp(r, 0, 1) * 255 + 0.5))
			writeu8(out, q + 1, math.floor(clamp(g, 0, 1) * 255 + 0.5))
			writeu8(out, q + 2, math.floor(clamp(b, 0, 1) * 255 + 0.5))
			writeu8(out, q + 3, readu8(orig, o + 3))
		end
	end
	local ok = pcall(img.WritePixelsBuffer, img, V2(x0, y0), V2(rw, rh), out)
	if not ok then
		v.headImg = nil
		return false
	end
	v.lastRect = #blobs > 0 and { x0, y0, x1, y1 } or nil
	return true
end

-- the same marks as vertex colours (the Head piece without a texture)
local function paintVertices(model, v, blobs)
	local mesh = v.pieces.Head.mesh
	local P, C = mesh.P, mesh.C
	local ids, cols = {}, {}
	local touched = v.touched or {}
	local now = {}
	for i = 1, mesh.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		if z < -0.05 then
			local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
			local hit = false
			for _, bl in ipairs(blobs) do
				local a = blobAlpha(bl, x - bl.x, y - bl.y)
				if a > 0 then
					r, g, b = r + (bl.r - r) * a, g + (bl.g - g) * a, b + (bl.b - b) * a
					hit = true
				end
			end
			if hit or touched[i] then
				ids[#ids + 1] = i
				cols[#cols + 1] = { r, g, b }
				if hit then
					now[i] = true
				end
			end
		end
	end
	v.touched = now
	if #ids > 0 then
		Anatomy.SetVertexColors(model, "Head", "Head", ids, cols)
	end
end

-- the lids are vertex-coloured pieces beside the (textured) head: their skin (the generator's LidSkin group,
-- never the lash line or the lashes) takes a black eye's colour plus any mark under it. Always from the
-- generated colours, so a healed eye goes back exactly
local LID_PIECES = { "LidL", "LidR", "LidLow", "LidUpper", "Eyes" }
local function paintLids(model, v, blobs, lid)
	v.lidTouched = v.lidTouched or {}
	for _, name in ipairs(LID_PIECES) do
		local pc = v.pieces[name]
		local ids = pc and pc.groups and pc.groups.LidSkin
		local mesh = pc and pc.mesh
		if type(ids) == "table" and type(mesh) == "table" and mesh.C then
			local P, C = mesh.P, mesh.C
			local was = v.lidTouched[name]
			local out, cols, any = {}, {}, false
			for _, i in ipairs(ids) do
				local x, y = P[i * 3 - 2], P[i * 3 - 1]
				local r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
				local hit = false
				local side = x < 0 and -1 or 1
				local t = lid[side]
				local e = v.eye[side]
				if t and e then
					-- deepest along the lash line, lighter toward the crease (generated, open-lid positions)
					local a = t[4] * (1 - 0.35 * clamp((math.abs(y - e.Y) / v.eyeR - 0.35) / 0.6, 0, 1))
					r, g, b = r + (t[1] - r) * a, g + (t[2] - g) * a, b + (t[3] - b) * a
					hit = true
				end
				for _, bl in ipairs(blobs) do
					local a = blobAlpha(bl, x - bl.x, y - bl.y)
					if a > 0 then
						r, g, b = r + (bl.r - r) * a, g + (bl.g - g) * a, b + (bl.b - b) * a
						hit = true
					end
				end
				if hit or was then
					out[#out + 1] = i
					cols[#cols + 1] = { r, g, b }
					any = any or hit
				end
			end
			v.lidTouched[name] = any
			if #out > 0 then
				Anatomy.SetVertexColors(model, "Head", name, out, cols)
			end
		end
	end
end

-- sclera redness on textured eyeballs (the polar map: the sclera is beyond radius 0.27 of the texture)
local function paintEyes(v, red)
	for s = -1, 1, 2 do
		local img = v.eyeImg and v.eyeImg[s]
		if img then
			local size = img.Size
			local W, H = size.X, size.Y
			v.eyeOrig = v.eyeOrig or {}
			if not v.eyeOrig[s] then
				local ok, buf = pcall(img.ReadPixelsBuffer, img, Vector2.zero, size)
				if not ok then
					v.eyeImg[s] = nil
					continue
				end
				v.eyeOrig[s] = buf
			end
			local orig = v.eyeOrig[s]
			local out = buffer.create(W * H * 4)
			buffer.copy(out, 0, orig, 0, W * H * 4)
			local k = red[s]
			if k > 0.01 then
				for py = 0, H - 1 do
					for px = 0, W - 1 do
						local du, dv = (px + 0.5) / W - 0.5, (py + 0.5) / H - 0.5
						local r = math.sqrt(du * du + dv * dv)
						if r > 0.25 then
							local a = k * clamp((r - 0.25) / 0.05, 0, 1)
							local o = (py * W + px) * 4
							writeu8(out, o, math.floor(readu8(orig, o) + (232 - readu8(orig, o)) * a + 0.5))
							writeu8(out, o + 1, math.floor(readu8(orig, o + 1) + (140 - readu8(orig, o + 1)) * a + 0.5))
							writeu8(out, o + 2, math.floor(readu8(orig, o + 2) + (132 - readu8(orig, o + 2)) * a + 0.5))
						end
					end
				end
			end
			pcall(img.WritePixelsBuffer, img, Vector2.zero, size, out)
		end
	end
end

-- damage state -> swell weights (into v.swell) + marks; only when the LookFx string / tier changed
local function applyDamage(model, v, tier)
	local fx = LookData and LookData.Fx(model)
	local dmg = fx and fx.dmg or {}
	local key = (model:GetAttribute(LookData and LookData.FX_ATTR or "LookFx") or "") .. "|" .. tostring(tier)
	if key == v.dmgStr then
		return
	end
	v.dmgStr = key
	local blobs, swell, lid = damageBlobs(model, v, dmg, tier)
	table.clear(v.swell)
	for k, w in pairs(swell) do
		if w > 0.005 then
			v.swell[k] = w
		end
	end
	v.closing = {
		[-1] = clamp(((tonumber(dmg.leftEye) or 0) - 0.3) / 0.7, 0, 1),
		[1] = clamp(((tonumber(dmg.rightEye) or 0) - 0.3) / 0.7, 0, 1),
	}
	if v.headImg then
		paintImage(v, blobs)
	elseif v.lod ~= "low" then
		paintVertices(model, v, blobs)
	end
	paintLids(model, v, blobs, lid)
	if v.eyeImg then
		local severe = tier >= 4
		local red = {}
		for s = -1, 1, 2 do
			local ev = tonumber(s < 0 and dmg.leftEye or dmg.rightEye) or 0
			red[s] = clamp(ev * 0.5 + (severe and 0.35 or 0) + (tonumber(dmg.redness) or 0) * 0.15, 0, 0.8)
		end
		if (red[-1] > 0.01 or red[1] > 0.01) or v.eyeRed then
			paintEyes(v, red)
			v.eyeRed = red[-1] > 0.01 or red[1] > 0.01
		end
	end
	v.sent.__dmg = nil
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
	local r = clamp(sweat * 0.05, 0, 0.08)
	if math.abs(r - v.refl) > 0.002 then
		v.refl = r
		part.Reflectance = r
	end
end

------------------------------------------------------------------------
-- Mesh update (per frame for models in range)
------------------------------------------------------------------------
local MORPHS = { "browUp", "browIn", "knit", "lid", "squint", "open", "press", "smile", "snarl", "wide", "asym", "breathe", "puff" }

local function q50(x)
	return math.floor(x * 50 + 0.5) / 50
end

local function meshUpdate(model, rec, v, ch, blinkC, lidC, gaze, near, now, a, breathe)
	v.active = true
	-- upper lids: closure (expression / blink / swollen shut) turns them about the hinge axis
	local closing = v.closing or { [-1] = 0, [1] = 0 }
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
		-- breathing through the mouth when spent
		local stam = type(a.Stam) == "number" and a.Stam or 1
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
			local rec = faces[model]
			if rec then
				rec.mvDirty = true
			end
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
		morphs = mv and mv.hasMorphs or false,
	}
end

FaceFX.Expressions = EXPR
return FaceFX
