-- WorldLOD: the Graphics level (Perf) applied to the world's own lights, signs, particles and shadow
-- casters - the server-built gym and city (workspace.Gym), your client-side gym and city dressing
-- (LocalGym, LocalCity, WorldDetail) and, during a fight, the arena (signs and shadow casters only: VenueFX drives
-- the arena's lights and effects itself). Ambience keeps its dust and sun shafts (GymAmbienceFX).
--   High    today's look. Lights whose pool can no longer be told apart switch off: accent lights (range < 16)
--           beyond 200 studs, mid lights beyond 450, big fills beyond 900 (the lamps' Neon bulbs and lenses
--           stay lit, so the street still reads lit; a fight venue is ~5,700 studs from the gym, whose lights
--           otherwise stayed on through the whole fight); light shadows only from the 4 nearest shadowed
--           lights within 240 studs (the ring's cans while you are in the gym, none from the street)
--   Medium  shadows only from lights marked ShadowKeep (two of the ring's four cans), the 2 nearest within
--           160 studs; small accent lights (range < 16) beyond 90 studs, mid lights beyond 220 and fills beyond
--           700 off; signs drawn out to 3/4 of their distance at 3/4 resolution; continuous particles at 55%
--           (none beyond 260 studs)
--   Low     no light shadows; accent lights off; mid lights beyond 110 and big fills beyond 170 off;
--           signs drawn out to half their distance at half resolution; particles at 25% (none beyond
--           150 studs); small parts (under 4 studs) cast no shadow
-- Behind the main menu's set (LocalPlayer MenuStage) every world light is off; behind the character creator
-- (CreatorOpen) only the lights within CREATOR_REACH of its camera stay on (the gym hall around the boxer).
-- Resolution only drops on signs whose layout is all scale (sizes, positions, TextScaled), so nothing
-- moves or overflows. Owners that switch a light at runtime (night lights, flickering neon, gates)
-- call WorldLOD.SetLight so the culling never fights them. Work is spread over frames: a level change
-- re-applies under ~0.5 ms per frame, the light sweep visits 4 (High) to 12 lights a frame.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WorldLOD = {}

-- Perf is the core module; without it everything stays at High
local Perf
do
	local m = script.Parent:FindFirstChild("Perf")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	Perf = (ok and type(mod) == "table") and mod or nil
end

-- light cull distances per level: { accent (< 16), mid (16..39), fill (>= 40) }; 0 = always off. High's are
-- ~13-20x the light's range: past that a pool is a few pixels under the haze (the city at night had ~470
-- lights on within the old 2,000-stud reach, about 340 within these)
local CULL = {
	{ 0, 110, 170 },
	{ 90, 220, 700 },
	{ 200, 450, 900 },
}
-- shadow-casting lights: only the nearest SHADOW_MAX within SHADOW_NEAR studs of the camera keep their shadows
-- (a spot's shadow map is re-drawn whenever something moves in its cone: the ring's cans over the sparring
-- members, seen from the street). Re-ranked every SHADOW_EVERY seconds (a handful of lights).
local SHADOW_NEAR = { 0, 160, 240 }
local SHADOW_MAX = { 0, 2, 4 }
local SHADOW_EVERY = 0.5
local FX = { 0.25, 0.55, 1 } -- continuous particle rate multiplier
local EMIT_FAR = { 150, 260, math.huge } -- continuous emitters further than this from the camera stop
local SIGN_DIST = { 0.5, 0.75, 1 } -- SurfaceGui / BillboardGui MaxDistance multiplier
local SIGN_SIZE = { 25, 40 } -- an unlimited sign's distance per stud of its face's size (Low, Medium)
local SIGN_RES = { 0.5, 0.75, 1 } -- PixelsPerStud multiplier (scale-only layouts)
local SMALL_PART = 4 -- Low: parts smaller than this (largest side) cast no shadow
local BUDGET = 0.0005 -- seconds of queued work per frame

local level = 3
local function lv()
	return Perf and Perf.Level() or 3
end

function WorldLOD.Level()
	return level
end

-- multiplier for burst counts / rates of ambient effects (1 at High)
function WorldLOD.FX()
	return FX[level] or 1
end

-- Perf.Pick passthrough (High when Perf is missing)
function WorldLOD.Pick(low, medium, high)
	if level <= 1 then
		return low
	elseif level == 2 then
		return medium
	end
	return high
end

local listeners = {}
-- fn(level) on every level change (after WorldLOD's own state switched)
function WorldLOD.OnChanged(fn)
	table.insert(listeners, fn)
end

------------------------------------------------------------------------
-- registries
------------------------------------------------------------------------
local roots = {} -- root -> { conn, opts }
local lights = {} -- light -> { cls = 1..3, shadow = base Shadows }
local lightList = {} -- for the round-robin sweep
local culled = {} -- light -> the Enabled state to give back when it comes back into range
local wanted = {} -- light -> the owner's last SetLight (runtime-switched lights)
local guis = {} -- SurfaceGui / BillboardGui -> { dist = base MaxDistance, pps = base PixelsPerStud }
local emitters = {} -- ParticleEmitter -> base Rate
local shadowOff = {} -- part -> true (Low turned its CastShadow off)
local queue, qHead = {}, 1 -- instances waiting for registration / a re-apply

local function lightClass(l)
	local r = l.Range
	return r < 16 and 1 or (r < 40 and 2 or 3)
end

local shadowList = {} -- the lights whose own Shadows was on (the ranking's candidates)
local shadowNear = {} -- light -> true while it ranks among the nearest (the last ranking)
local shadowAcc = SHADOW_EVERY -- seconds since the last ranking (a level change ranks on the next frame)

-- the level's rule alone (the ranking adds the distance and the count)
local function shadowLevelAllows(l, e)
	if not e.shadow then
		return false
	end
	if level >= 3 then
		return true
	end
	return level == 2 and l:GetAttribute("ShadowKeep") == true
end

local function shadowAllowed(l, e)
	return shadowNear[l] == true and shadowLevelAllows(l, e)
end

local function applyLightShadow(l, e)
	local want = shadowAllowed(l, e)
	if l.Shadows ~= want then
		l.Shadows = want
	end
end

-- the face a SurfaceGui draws on, in square studs
local function faceArea(sg)
	local p = sg.Adornee or sg.Parent
	if not (p and p:IsA("BasePart")) then
		return 4
	end
	local s, f = p.Size, sg.Face
	if f == Enum.NormalId.Front or f == Enum.NormalId.Back then
		return s.X * s.Y
	elseif f == Enum.NormalId.Left or f == Enum.NormalId.Right then
		return s.Z * s.Y
	end
	return s.X * s.Z
end

-- a layout that does not change with resolution: only scale sizes / positions and scaled text
local SAFE = { Frame = true, TextLabel = true, ImageLabel = true, UIGradient = true, UIAspectRatioConstraint = true, UICorner = true }
local function scaleOnly(sg)
	for _, d in ipairs(sg:GetDescendants()) do
		if not SAFE[d.ClassName] then
			return false
		end
		if d:IsA("GuiObject") then
			local s, p = d.Size, d.Position
			if s.X.Offset ~= 0 or s.Y.Offset ~= 0 or p.X.Offset ~= 0 or p.Y.Offset ~= 0 then
				return false
			end
			if d:IsA("TextLabel") and not d.TextScaled then
				return false
			end
		elseif d:IsA("UICorner") and d.CornerRadius.Offset ~= 0 then
			return false
		end
	end
	return true
end

local function applyGui(g, e)
	if g:IsA("SurfaceGui") then
		local dist = e.dist
		-- (LodFixedDist: the owner culls the sign by its own range, e.g. CityVisuals' window grids)
		if level < 3 and not g:GetAttribute("LodFixedDist") then
			if dist > 0 then
				dist = math.max(25, dist * SIGN_DIST[level])
			else
				dist = math.clamp(math.sqrt(faceArea(g)) * SIGN_SIZE[level], 40, 600)
			end
		end
		if g.MaxDistance ~= dist then
			g.MaxDistance = dist
		end
		if g.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud then
			local pps = e.pps
			if level < 3 and scaleOnly(g) then
				pps = math.max(2, e.pps * SIGN_RES[level])
			end
			if g.PixelsPerStud ~= pps then
				g.PixelsPerStud = pps
			end
		end
	else
		local dist = e.dist
		if level < 3 and dist > 0 and dist < math.huge then
			dist = math.max(20, dist * SIGN_DIST[level])
		end
		if g.MaxDistance ~= dist then
			g.MaxDistance = dist
		end
	end
end

local emitterList = {} -- for the distance sweep
local emitFar = {} -- emitter -> true while it is beyond EMIT_FAR

local function applyEmitter(pe, base)
	local r = emitFar[pe] and 0 or base * (FX[level] or 1)
	if pe.Rate ~= r then
		pe.Rate = r
	end
end

local function applyPartShadow(p)
	if level <= 1 then
		if p.CastShadow and not shadowOff[p] and p.Transparency < 1 then
			local s = p.Size
			if math.max(s.X, s.Y, s.Z) < SMALL_PART then
				p.CastShadow = false
				shadowOff[p] = true
			end
		end
	elseif shadowOff[p] then
		shadowOff[p] = nil
		p.CastShadow = true
	end
end

local function rootOpts(inst)
	for r, rec in pairs(roots) do
		if inst:IsDescendantOf(r) then
			return rec.opts
		end
	end
	return nil
end

-- register (or re-apply) one instance
local function visit(inst)
	if inst.Parent == nil then
		return
	end
	if inst:IsA("BasePart") then
		applyPartShadow(inst)
	elseif inst:IsA("Light") then
		local e = lights[inst]
		if not e then
			local o = rootOpts(inst)
			if not o or o.lights == false then
				return
			end
			local holder = inst.Parent
			e = {
				cls = lightClass(inst), shadow = inst.Shadows,
				part = holder:IsA("BasePart") and holder or nil, att = holder:IsA("Attachment") and holder or nil,
			}
			lights[inst] = e
			table.insert(lightList, inst)
			if e.shadow then
				table.insert(shadowList, inst)
				shadowAcc = SHADOW_EVERY -- ranked on the next frame
			end
		end
		applyLightShadow(inst, e)
	elseif inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
		local e = guis[inst]
		if not e then
			e = { dist = inst.MaxDistance, pps = inst:IsA("SurfaceGui") and inst.PixelsPerStud or 0 }
			guis[inst] = e
		end
		applyGui(inst, e)
	elseif inst:IsA("ParticleEmitter") then
		local base = emitters[inst]
		if base == nil then
			local o = rootOpts(inst)
			if not o or o.emitters == false then
				return
			end
			base = inst.Rate
			emitters[inst] = base
			if base > 0 then
				table.insert(emitterList, inst)
			end
		end
		if base > 0 then
			applyEmitter(inst, base)
		end
	elseif inst:IsA("GuiObject") or inst:IsA("UIComponent") then
		-- new content on a sign whose resolution was lowered: check its layout again
		local sg = level < 3 and inst:FindFirstAncestorOfClass("SurfaceGui")
		local e = sg and guis[sg]
		if e then
			applyGui(sg, e)
		end
	end
end

-- what a new descendant needs: parts only matter on Low (shadow casters), sign content only while
-- a sign's resolution may be lowered
local function cares(inst)
	if inst:IsA("BasePart") then
		return level <= 1
	end
	if inst:IsA("Light") or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") or inst:IsA("ParticleEmitter") then
		return true
	end
	return level < 3 and (inst:IsA("GuiObject") or inst:IsA("UIComponent"))
end

local function push(inst)
	queue[#queue + 1] = inst
end

-- the owners' runtime switch for a light under a watched root (night lights, neon, gates):
-- it is kept off while culled and comes back in the owner's state
function WorldLOD.SetLight(l, on)
	wanted[l] = on
	if culled[l] ~= nil then
		culled[l] = on
	elseif l.Enabled ~= on then
		l.Enabled = on
	end
end

-- the state the owner wants for a light (what it shows once back in range)
function WorldLOD.Wanted(l)
	local w = wanted[l]
	if w ~= nil then
		return w
	end
	local c = culled[l]
	if c ~= nil then
		return c
	end
	return l.Enabled
end

------------------------------------------------------------------------
-- roots
------------------------------------------------------------------------
-- opts: { lights = false } (signs / particles / shadow casters only), { emitters = false }
function WorldLOD.Watch(root, opts)
	if typeof(root) ~= "Instance" or roots[root] then
		return
	end
	local rec = { opts = opts or {} }
	roots[root] = rec
	rec.conn = root.DescendantAdded:Connect(function(d)
		if cares(d) then
			push(d)
		end
	end)
	for _, d in ipairs(root:GetDescendants()) do
		if cares(d) then
			push(d)
		end
	end
end

function WorldLOD.Unwatch(root)
	local rec = roots[root]
	if rec then
		rec.conn:Disconnect()
		roots[root] = nil
	end
end

------------------------------------------------------------------------
-- level changes
------------------------------------------------------------------------
local function reapplyAll()
	for l in pairs(lights) do
		push(l)
	end
	for g in pairs(guis) do
		push(g)
	end
	for pe in pairs(emitters) do
		push(pe)
	end
	if level <= 1 then
		for r in pairs(roots) do
			for _, d in ipairs(r:GetDescendants()) do
				if d:IsA("BasePart") then
					push(d)
				end
			end
		end
	else
		for p in pairs(shadowOff) do
			push(p)
		end
	end
end

local function setLevel(l)
	l = math.clamp(tonumber(l) or 3, 1, 3)
	if l == level then
		return
	end
	level = l
	shadowAcc = SHADOW_EVERY
	reapplyAll()
	for _, fn in ipairs(listeners) do
		task.spawn(fn, level)
	end
end

------------------------------------------------------------------------
-- the per-frame worker: queued registrations first, then a slice of the light sweep
------------------------------------------------------------------------
local sweepIdx = 0
local emitIdx = 0
-- lights visited per frame: ~200 lights come round every ~0.3 s on Low / Medium (the culling there
-- is within 90-220 studs); High's starts at 200 studs, so the ~470 of the city at night come round in ~1 s.
-- A camera jump (a travel, a cut) sweeps them all at the fast rate, so the new place is lit at once
local SWEEP_PER_FRAME = { 12, 12, 8 }
local JUMP = 100 -- studs the camera moves in one frame that count as a jump
local menuSweep = 0 -- lights left to visit at the fast rate after the menu hold changed
local purgeAcc = 0

local lastCamPos -- the camera's position last frame (a jump re-sweeps at the fast rate)
local menuHold = false -- the main menu's set is up (LocalPlayer attribute MenuStage): every world light is culled
-- the character creator is open (LocalPlayer attribute CreatorOpen): its camera stays on the boxer at the gym's spawn,
-- so no light further than this from it is drawn (the whole hall is within ~180 studs of the spawn: the street and
-- the town beyond its walls go dark until the creator closes)
WorldLOD.CREATOR_REACH = 220
local creatorHold = false
local function sweepLight(l, camPos)
	local e = lights[l]
	local holder = l.Parent
	if not e or holder == nil then
		return false
	end
	if holder ~= e.part and holder ~= e.att then
		e.part = holder:IsA("BasePart") and holder or nil
		e.att = holder:IsA("Attachment") and holder or nil
	end
	local pos
	if e.part then
		pos = e.part.Position
	elseif e.att then
		pos = e.att.WorldPosition
	else
		return false
	end
	local limit = CULL[level][e.cls]
	if creatorHold then
		limit = math.min(limit, WorldLOD.CREATOR_REACH)
	end
	local off = menuHold or limit <= 0 or (pos - camPos).Magnitude > limit
	local was = culled[l]
	if off and was == nil then
		local keep = wanted[l]
		if keep == nil then
			keep = l.Enabled
		end
		culled[l] = keep
		if l.Enabled then
			l.Enabled = false
		end
	elseif not off and was ~= nil then
		culled[l] = nil
		if l.Enabled ~= was then
			l.Enabled = was
		end
	end
	return true
end

local function purge()
	-- drop what was destroyed (Parent nil); a hidden LocalGym keeps its descendants parented
	local n = #lightList
	local i = 1
	while i <= n do
		local l = lightList[i]
		if l.Parent == nil then
			lights[l], culled[l], wanted[l], shadowNear[l] = nil, nil, nil, nil
			lightList[i] = lightList[n]
			lightList[n] = nil
			n -= 1
		else
			i += 1
		end
	end
	for i = #shadowList, 1, -1 do
		if shadowList[i].Parent == nil then
			table.remove(shadowList, i)
		end
	end
	for g in pairs(guis) do
		if g.Parent == nil then
			guis[g] = nil
		end
	end
	for pe in pairs(emitters) do
		if pe.Parent == nil then
			emitters[pe], emitFar[pe] = nil, nil
		end
	end
	for i = #emitterList, 1, -1 do
		if emitterList[i].Parent == nil then
			table.remove(emitterList, i)
		end
	end
	for p in pairs(shadowOff) do
		if p.Parent == nil then
			shadowOff[p] = nil
		end
	end
	for r, rec in pairs(roots) do
		if r.Parent == nil and not rec.opts.keep then
			rec.conn:Disconnect()
			roots[r] = nil
		end
	end
end

-- the shadowed lights re-ranked: the nearest SHADOW_MAX the level allows within SHADOW_NEAR keep their shadows
local shadowRank = {} -- reused: { light, distance } pairs
local function rankShadows(camPos)
	table.clear(shadowRank)
	local near = SHADOW_NEAR[level] or 0
	for _, l in ipairs(shadowList) do
		local e = lights[l]
		local holder = l.Parent
		if e and holder and shadowLevelAllows(l, e) then
			local pos = (holder:IsA("BasePart") and holder.Position) or (holder:IsA("Attachment") and holder.WorldPosition) or nil
			local d = pos and (pos - camPos).Magnitude
			if d and d <= near then
				table.insert(shadowRank, { l, d })
			end
		end
	end
	table.sort(shadowRank, function(a, b)
		return a[2] < b[2]
	end)
	table.clear(shadowNear)
	for i = 1, math.min(#shadowRank, SHADOW_MAX[level] or 0) do
		shadowNear[shadowRank[i][1]] = true
	end
	for _, l in ipairs(shadowList) do
		local e = lights[l]
		if e and l.Parent then
			applyLightShadow(l, e)
		end
	end
end

local function step(dt)
	-- queued registrations / re-applies under a time budget
	if qHead <= #queue then
		local t0 = os.clock()
		local n = #queue
		while qHead <= n do
			local inst = queue[qHead]
			queue[qHead] = nil
			qHead += 1
			visit(inst)
			if os.clock() - t0 > BUDGET then
				break
			end
		end
		if qHead > #queue then
			table.clear(queue)
			qHead = 1
		end
	end
	-- light shadows: the nearest few (a handful of candidates, twice a second)
	shadowAcc += dt
	if shadowAcc >= SHADOW_EVERY and #shadowList > 0 then
		shadowAcc = 0
		local cam = workspace.CurrentCamera
		rankShadows(cam and cam.CFrame.Position or Vector3.zero)
	end
	-- light culling: a slice per frame
	local count = #lightList
	if count > 0 then
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		-- behind the main menu (its set floats ~1400 studs over the town) the gym's and the city's lights are all
		-- off, whatever their reach; the sweep runs faster while it switches them (off, then back on)
		local p = Players.LocalPlayer
		local hold = p ~= nil and p:GetAttribute("MenuStage") == true
		local creating = p ~= nil and p:GetAttribute("CreatorOpen") == true
		local per = SWEEP_PER_FRAME[level] or 4
		if hold ~= menuHold or creating ~= creatorHold then
			menuHold, creatorHold = hold, creating
			menuSweep = count
		end
		if lastCamPos and (camPos - lastCamPos).Magnitude > JUMP then
			menuSweep = count
			shadowAcc = SHADOW_EVERY
		end
		lastCamPos = camPos
		if menuSweep > 0 then
			per = math.max(per, 32)
			menuSweep -= per
		end
		for _ = 1, math.min(per, count) do
			sweepIdx = sweepIdx % count + 1
			sweepLight(lightList[sweepIdx], camPos)
		end
	end
	-- continuous emitters (a few dozen): two a frame, stopped beyond EMIT_FAR on Low / Medium
	local ne = #emitterList
	if ne > 0 then
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local far = EMIT_FAR[level] or math.huge
		for _ = 1, math.min(2, ne) do
			emitIdx = emitIdx % ne + 1
			local pe = emitterList[emitIdx]
			local holder = pe.Parent
			local pos = holder and (holder:IsA("BasePart") and holder.Position or (holder:IsA("Attachment") and holder.WorldPosition))
			if pos then
				local isFar = (pos - camPos).Magnitude > far or nil
				if isFar ~= emitFar[pe] then
					emitFar[pe] = isFar
					applyEmitter(pe, emitters[pe] or 0)
				end
			end
		end
	end
	purgeAcc += dt
	if purgeAcc > 10 then
		purgeAcc = 0
		purge()
	end
end

------------------------------------------------------------------------
-- start: the named world roots, now and whenever they appear
------------------------------------------------------------------------
local ROOT_NAMES = { Gym = { keep = true }, LocalGym = { keep = true }, LocalCity = { keep = true }, WorldDetail = { keep = true } }
local started = false

function WorldLOD.Start()
	if started then
		return
	end
	started = true
	level = lv()
	for name, opts in pairs(ROOT_NAMES) do
		local r = workspace:FindFirstChild(name)
		if r then
			WorldLOD.Watch(r, opts)
		end
	end
	workspace.ChildAdded:Connect(function(c)
		local opts = ROOT_NAMES[c.Name]
		if opts then
			WorldLOD.Watch(c, opts)
		end
	end)
	if Perf and Perf.Changed then
		Perf.Changed:Connect(setLevel)
	end
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not WorldLOD.warned then
			WorldLOD.warned = true
			warn("[WorldLOD]", err)
		end
	end)
end

-- for tests / the profiler
function WorldLOD.Stats()
	local nl, nc, ng, ne, ns = #lightList, 0, 0, 0, 0
	for _ in pairs(culled) do
		nc += 1
	end
	for _ in pairs(guis) do
		ng += 1
	end
	for _ in pairs(emitters) do
		ne += 1
	end
	for _ in pairs(shadowOff) do
		ns += 1
	end
	local nsh = 0
	for _ in pairs(shadowNear) do
		nsh += 1
	end
	return { level = level, lights = nl, culled = nc, guis = ng, emitters = ne, shadowOff = ns, shadowLights = nsh, queued = #queue - qHead + 1 }
end

return WorldLOD
