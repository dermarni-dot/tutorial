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
-- Writes only Motor6D.Transform, SpecialMesh.Scale/Offset and the Transparency of BlinkLid and
-- the face veins (client-toggled parts, CONTRACTS section 5). No per-frame allocation.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local K = require(script.Parent:WaitForChild("AnimKit"))

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
			elseif n == "UpperLip" then
				rec.mw = d.Size.X
			elseif n == "Brow" then
				rec.bt = d.Size.Y
			end
		end
	end
	rec.veinOn = false
end

local function reset(rec)
	for _, r in pairs(rec.roles) do
		if r.m.Parent then
			r.m.Transform = I
			if r.mesh and r.last then
				r.mesh.Scale = r.base
				r.mesh.Offset = r.off
			end
		end
		r.last = nil
		r.lc = nil
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
function FaceFX.Update(dt, t, camPos, rigs, budget)
	local rescans = 0
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
		if not next(rec.roles) and not next(rec.blink) then
			continue
		end
		local dist = (head.Position - camPos).Magnitude
		if dist > MID then
			if rec.active then
				reset(rec)
			end
			continue
		end
		rec.active = true
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
		for s = -1, 1, 2 do
			local r = roles[s < 0 and "EyeL" or "EyeR"]
			if r then
				local dy = drift * 0.13 * K.noise(t * 0.6, s * 3)
				local dp = drift * 0.07 * K.noise(t * 0.5, s * 7 + 1)
				setT(r, A(rec.gp + dp, rec.gy + dy, 0))
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
				inside.mesh.Scale = V3(inside.base.X * (1 + wide * 0.15), inside.base.Y * (1 + open * 2.4), inside.base.Z)
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
		local veinOn = angerW > 0.5 or strain > 0.5 or (sweat > 0.6 and effAttr > 0.4)
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

FaceFX.Expressions = EXPR
return FaceFX
