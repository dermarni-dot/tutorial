-- BodyFX: muscles that move. Client-only, driven by the Animator every frame.
--  * contraction: the Animator writes how hard each muscle works this frame (rig.cxL / rig.cxR,
--    keyed by Config.MuscleParts id, 0..1); a contracting muscle shortens and bulges
--  * pump: the server's Pump / PumpParts / PumpAt attributes (Training.ApplyPump) fade over
--    Config.Pump.duration; the local LivePump attribute (Activities) pumps the exercise's muscles
--  * jiggle: damped springs per body region, kicked by impacts (punches landing, body shots,
--    rope hops, bar lockouts)
--  * veins (Beams tagged Vein, attribute BaseTransparency set by the Builder from VeinLevel) show
--    more with pump, contraction and Strain
-- Two paths, picked per character:
--  * anatomy meshes (AnatomyClient built the "Body" section): the pieces' blend shapes are driven
--    instead of part scales: flex (contraction + pump + jiggle), breathe (rig.breath / breathPhase),
--    tense (core bracing, body-shot jiggle, Strain). Writes are low rate and budgeted (a few thousand
--    vertex writes per frame across every character, round-robin, only when a weight changes by a
--    0.05 step). Sweat shows as the pieces' Reflectance, rib bruises (LookFx ribsL / ribsR) are painted
--    into the UpperTorso piece's vertex colours, and the trunks' waistband text / sponsor patch (hidden
--    with the round-1 trunk blocks) come back as client text plates on the mesh trunks (landmarks).
--  * round-1 parts (no meshes, or meshes off): only SpecialMesh.Scale (from the BaseScale attribute) and
--    Beam.Transparency are written, never Size, so no physics is recomputed (CONTRACTS section 5).
-- Nothing allocates per frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local K = require(script.Parent:WaitForChild("AnimKit"))
local okConfig, Config = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end)
if not okConfig then
	Config = {}
end
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

local BodyFX = {}

local PUMP = Config.Pump or {}
local PUMP_DURATION = PUMP.duration or 150
local PUMP_SCALE = PUMP.scale or 0.08
local FLEX_SCALE = PUMP.flexScale or 0.12
local VEIN_BOOST = PUMP.veinBoost or 0.4
local NEAR = 45 -- studs: closer than this the muscles are animated
local exp, abs, min, max, floor = math.exp, math.abs, math.min, math.max, math.floor
local V3 = Vector3.new

-- body regions that jiggle together: 1 chest, 2 core, 3 arms, 4 legs
local REGION = { chest = 1, back = 1, neck = 1, core = 2, shoulders = 3, arms = 3, legs = 4 }
local REGION_ID = { chest = 1, core = 2, arms = 3, legs = 4 }
local JIG_K, JIG_C = 210, 9 -- soft tissue: fast, lightly damped

-- per exercise: weight / max weight, so the main movers contract fully (Config.ExerciseTargets)
local TARGETS = {}
for actId, parts in pairs(Config.ExerciseTargets or {}) do
	local top = 0
	for _, w in pairs(parts) do
		top = max(top, w)
	end
	local norm = {}
	for id, w in pairs(parts) do
		norm[id] = top > 0 and w / top or 0
	end
	TARGETS[actId] = norm
end
BodyFX.Targets = TARGETS

------------------------------------------------------------------------
-- Anatomy mesh path: which muscles drive which piece's blend shapes
------------------------------------------------------------------------
local SECTION = "Body"
-- per piece kind: muscle id -> share of its contraction / pump the piece's shape follows
local FLEX_OF = {
	UpperTorso = { pecs = 1, upperChest = 1, lats = 0.9, traps = 0.8, upperBack = 0.6, serratus = 0.5, abs = 0.6, obliques = 0.5, frontDelt = 0.3, neckSCM = 0.4 },
	LowerTorso = { glutes = 1, lowerAbs = 0.3, lowerBack = 0.4 },
	UpperArm = { biceps = 1, triceps = 0.9, frontDelt = 0.6, sideDelt = 0.6, rearDelt = 0.5 },
	LowerArm = { forearms = 1, biceps = 0.25 },
	UpperLeg = { quads = 1, hamstrings = 0.8, glutes = 0.3 },
	LowerLeg = { calves = 1 },
}
local TENSE_OF = { abs = 1, lowerAbs = 1, obliques = 0.8, serratus = 0.4 }
-- piece -> { kind, side (-1 left, 1 right, 0 both), jiggle region }
local PIECES = {
	UpperTorso = { "UpperTorso", 0, 1 }, LowerTorso = { "LowerTorso", 0, 2 },
	LeftUpperArm = { "UpperArm", -1, 3 }, RightUpperArm = { "UpperArm", 1, 3 },
	LeftLowerArm = { "LowerArm", -1, 3 }, RightLowerArm = { "LowerArm", 1, 3 },
	LeftUpperLeg = { "UpperLeg", -1, 4 }, RightUpperLeg = { "UpperLeg", 1, 4 },
	LeftLowerLeg = { "LowerLeg", -1, 4 }, RightLowerLeg = { "LowerLeg", 1, 4 },
}
-- vertex writes per frame, every character together: FaceFX writes about 1000 more (one Head SetMorphs per
-- frame), and the contract caps every FX module together at 2000 (ANATOMY_CONTRACTS section 11)
local MORPH_BUDGET = 1000
local MORPH_STEP = 0.1 -- weights move in these steps (a flex step is a millimetre or two: no write below it)
local MORPH_RATE = 1 / 20 -- per character: blend shapes at most this often (near), half as often far
local BREATH_RATE = 1 / 10 -- breathing (slow, tiny) at most this often
local BREATH_RANGE = 30 -- studs: breathing only this close (it rewrites the chest continuously)

local function quant(x)
	return floor(x / MORPH_STEP + 0.5) * MORPH_STEP
end

local stats = { morphWrites = 0, vertexWrites = 0, plates = 0, bruises = 0, sweat = 0, maxFrame = 0 }
local tracked = {} -- model -> rec
local restore -- (rec) round-1 muscle scales and veins back to the Builder's values (defined below)
local views = setmetatable({}, { __mode = "k" }) -- model -> AnatomyClient piece view of the Body section
local landmarksOf = setmetatable({}, { __mode = "k" }) -- model -> Body landmarks
local queue = {} -- flat list of mesh piece states (round-robin writes)
local draining = {} -- piece states of untracked characters still relaxing (flushMorphs writes them within the budget)
local queueDirty = true
local cursor = 1

local function newRec(model)
	return {
		model = model, folder = false, list = {}, veins = {}, nextScan = 0, nextAttr = 0,
		pump = 0, pumpStr = nil, pumpSet = {}, live = 0, strain = 0, sweat = -1,
		jx = { 0, 0, 0, 0 }, jv = { 0, 0, 0, 0 }, dirty = false, awake = false,
		-- mesh path: smoothed contraction per muscle id and side, piece states, last morph time
		cL = {}, cR = {}, mesh = nil, nextMorph = 0, nextBreath = 0, breath = 0, meshAwake = false,
	}
end

------------------------------------------------------------------------
-- Mesh extras: sweat sheen, rib bruises, trunk lettering
------------------------------------------------------------------------
-- sweat: a low reflectance on the skin pieces (the cloth pieces keep their own); Head.SetSweat does the
-- same for the round-1 parts
local function applySweat(model, view, q)
	local r = math.clamp(q * 0.05, 0, 0.08)
	for _, pv in pairs(view) do
		local part = pv.part
		if part and part.Parent then
			if pv.baseRefl == nil then
				pv.baseRefl = part.Reflectance
			end
			-- cloth (the satin trunks' seat) was built with its own sheen: leave it
			local want = pv.baseRefl > 0 and pv.baseRefl or r
			if abs(part.Reflectance - want) > 1e-4 then
				part.Reflectance = want
				stats.sweat += 1
			end
		end
	end
	return model
end

local BRUISE = (Config.FaceDamage and Config.FaceDamage.bruiseColors) or { { day = 0, rgb = { 95, 25, 40 } } }
local function bruiseRGB(sr, sg, sb, age)
	age = tonumber(age) or 0
	local function col(e)
		if e and e.rgb then
			return e.rgb[1] / 255, e.rgb[2] / 255, e.rgb[3] / 255
		end
		return sr, sg, sb
	end
	for i = #BRUISE, 1, -1 do
		if age >= BRUISE[i].day then
			local r0, g0, b0 = col(BRUISE[i])
			local nx = BRUISE[i + 1]
			if not nx then
				return r0, g0, b0
			end
			local r1, g1, b1 = col(nx)
			local t = math.clamp((age - BRUISE[i].day) / (nx.day - BRUISE[i].day), 0, 1)
			return r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t
		end
	end
	return col(BRUISE[1])
end

-- the lower ribs from the flank round toward the front (the round-1 RibBruise ellipsoids' place, which the
-- Body section hides), painted into the UpperTorso piece; v = 0..1 per side. Restores what it painted.
local function applyBruise(model, view, rec, ribsL, ribsR, age)
	local pv = view.UpperTorso
	local mesh = pv and pv.mesh
	local part = pv and pv.part
	if not (mesh and part and Anatomy) then
		return
	end
	age = floor((tonumber(age) or 0) * 10 + 0.5) / 10
	if pv.bruiseL == ribsL and pv.bruiseR == ribsR and pv.bruiseAge == age then
		return
	end
	pv.bruiseL, pv.bruiseR, pv.bruiseAge = ribsL, ribsR, age
	local P, C = mesh.P, mesh.C
	-- mesh positions are in the R15 UpperTorso's space: place the bruise where the round-1 plates sat
	local ut = model:FindFirstChild("UpperTorso")
	local s = ut and ut:IsA("BasePart") and ut.Size or part.Size
	local look = LookData and LookData.Get(model)
	local female = type(look) == "table" and look.g == 2
	local ids, cols = {}, {}
	local painted = pv.bruised or {}
	local seen = {}
	for _, e in ipairs({ { -1, ribsL }, { 1, ribsR } }) do
		local side, v = e[1], e[2]
		if v > 0.08 then
			local cx, cy = side * 0.36 * s.X, (female and -0.33 or -0.14) * s.Y
			local ax, ay = (0.17 + 0.06 * v) * s.X, (0.16 + 0.08 * v) * s.Y
			local alpha = math.clamp(0.22 + 0.45 * v, 0.2, 0.65)
			for i = 1, mesh.nv do
				local x, y = P[i * 3 - 2], P[i * 3 - 1]
				if x * side > 0 then
					local dx, dy = (x - cx) / ax, (y - cy) / ay
					local d2 = dx * dx + dy * dy
					if d2 < 1 then
						local w = (1 - d2) * (1 - d2) * alpha
						local r0, g0, b0 = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
						local br, bg, bb = bruiseRGB(r0, g0, b0, age)
						-- the round-1 plate: 75 % of the way from the skin to the bruise colour
						br, bg, bb = r0 + (br - r0) * 0.75, g0 + (bg - g0) * 0.75, b0 + (bb - b0) * 0.75
						local k = seen[i]
						if not k then
							k = #ids + 1
							ids[k] = i
							seen[i] = k
						end
						local c = cols[k]
						local cr, cg, cb = r0, g0, b0
						if c then
							cr, cg, cb = c.R, c.G, c.B
						end
						cols[k] = Color3.new(cr + (br - cr) * w, cg + (bg - cg) * w, cb + (bb - cb) * w)
					end
				end
			end
		end
	end
	-- vertices painted last time and not now: back to the generated colour
	for i in pairs(painted) do
		if not seen[i] then
			ids[#ids + 1] = i
			cols[#ids] = Color3.new(C[i * 3 - 2], C[i * 3 - 1], C[i * 3])
		end
	end
	if #ids > 0 then
		Anatomy.SetVertexColors(model, SECTION, "UpperTorso", ids, cols)
		stats.bruises += 1
	end
	pv.bruised = seen
	return rec
end

-- the trunks' lettering on the mesh: a client plate (an invisible part carrying a copy of the round-1
-- patch's SurfaceGui) welded to the R15 part, just in front of the mesh surface at the section's landmarks
local function plateFolder(model)
	local f = model:FindFirstChild("BodyFXText")
	if not f then
		f = Instance.new("Folder")
		f.Name = "BodyFXText"
		f.Parent = model
	end
	return f
end

local function clearPlates(model)
	local f = model:FindFirstChild("BodyFXText")
	if f then
		f:Destroy()
	end
end

local function makePlate(folder, name, src, attach, centre, size)
	local gui = src and src:FindFirstChildOfClass("SurfaceGui")
	if not (gui and attach) then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	local c0 = CFrame.new(centre)
	p.CFrame = attach.CFrame * c0
	local g = gui:Clone()
	g.Face = Enum.NormalId.Front
	g.Enabled = true
	g.Parent = p
	local w = Instance.new("Weld")
	w.Part0 = attach
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	p.Parent = folder
	stats.plates += 1
	return p
end

local function lmVec(lm, name)
	local e = lm and lm[name]
	local pos = e and e.pos
	if type(pos) ~= "table" then
		return nil
	end
	return V3(pos[1], pos[2], pos[3])
end

-- (re)make the plates for the current round-1 patches; returns the sources used (to notice a rebuild)
local function applyPlates(model, lm)
	clearPlates(model)
	local look = model:FindFirstChild("BoxerLook")
	local attire = look and look:FindFirstChild("Attire")
	if not (attire and lm) then
		return nil
	end
	local waistSrc = attire:FindFirstChild("WaistText")
	local patchSrc = attire:FindFirstChild("SponsorPatch")
	-- only while the mesh trunks replace them (the Body section hides them then)
	local hiddenW = waistSrc and Anatomy and Anatomy.IsReplaced(waistSrc)
	local hiddenP = patchSrc and Anatomy and Anatomy.IsReplaced(patchSrc)
	local folder
	local front, top, edge = lmVec(lm, "WaistFront"), lmVec(lm, "WaistBandTop"), lmVec(lm, "WaistFrontEdge")
	local lt = model:FindFirstChild("LowerTorso")
	if hiddenW and front and top and edge and lt then
		local half = abs(edge.X - front.X)
		local h = math.min(waistSrc.Size.Y, abs(top.Y - front.Y) * 2 * 0.85)
		-- a flat plate on a curved band: kept to the band's flatter middle so its ends do not stand off much
		local wdt = math.clamp(half * 1.8, 0.2, waistSrc.Size.X)
		folder = folder or plateFolder(model)
		makePlate(folder, "WaistText", waistSrc, lt, V3(front.X, front.Y, front.Z - 0.016), V3(wdt, h, 0.02))
	end
	local pc, pe = lmVec(lm, "TrunkPatchR"), lmVec(lm, "TrunkPatchREdge")
	local ul = model:FindFirstChild("RightUpperLeg")
	if hiddenP and pc and pe and ul then
		local half = abs(pe.X - pc.X)
		local wdt = math.clamp(half * 1.6, 0.2, patchSrc.Size.X)
		folder = folder or plateFolder(model)
		makePlate(folder, "SponsorPatch", patchSrc, ul, V3(pc.X, pc.Y, pc.Z - 0.016), V3(wdt, patchSrc.Size.Y, 0.02))
	end
	return (waistSrc or false), (patchSrc or false)
end

------------------------------------------------------------------------
-- Mesh views (AnatomyClient signals)
------------------------------------------------------------------------
local function morphCost(mesh)
	local morphs = mesh and mesh.morphs
	if type(morphs) ~= "table" then
		return 0
	end
	local seen, n = {}, 0
	for _, mo in pairs(morphs) do
		for _, i in ipairs(mo.ids or {}) do
			if not seen[i] then
				seen[i] = true
				n += 1
			end
		end
	end
	return n
end

-- per piece: what its mesh can do and what was written last
local function meshState(rec, view)
	local st = {}
	for name, pv in pairs(view) do
		local info = PIECES[name]
		local morphs = pv.mesh and pv.mesh.morphs
		if info and type(morphs) == "table" and next(morphs) ~= nil then
			local function n(mo)
				return mo and mo.ids and #mo.ids or 0
			end
			st[name] = {
				rec = rec, name = name, kind = info[1], side = info[2], region = info[3],
				hasFlex = morphs.flex ~= nil, hasBreathe = morphs.breathe ~= nil, hasTense = morphs.tense ~= nil,
				-- AnatomyClient rewrites the vertices of the shapes whose weight moved: cost per shape, and the
				-- whole union as the cap
				cost = morphCost(pv.mesh), nFlex = n(morphs.flex), nBreathe = n(morphs.breathe), nTense = n(morphs.tense),
				w = { flex = 0, breathe = 0, tense = 0 }, sent = { flex = 0, breathe = 0, tense = 0 }, pending = false,
			}
		end
	end
	return st
end

local function setView(model, view, lm)
	views[model] = view
	landmarksOf[model] = lm
	local rec = tracked[model]
	if rec then
		if view and rec.awake then
			-- the round-1 muscles go under the meshes: leave them as the Builder made them
			restore(rec)
			rec.awake = false
		end
		rec.mesh = view and meshState(rec, view) or nil
		rec.sweat = -1
		rec.plateSrcW, rec.plateSrcP = nil, nil
		queueDirty = true
	end
	if view then
		-- static extras for every model with meshes (tracked or not): sheen, bruises, lettering
		local fx = LookData and LookData.Fx(model)
		applySweat(model, view, fx and fx.sweat or (tonumber(model:GetAttribute("Sweat")) or 0))
		if fx then
			applyBruise(model, view, rec, tonumber(fx.dmg.ribsL) or 0, tonumber(fx.dmg.ribsR) or 0, fx.dmg.age)
		end
		local w, p = applyPlates(model, lm)
		if rec then
			rec.plateSrcW, rec.plateSrcP = w, p
		end
	else
		clearPlates(model)
	end
end

if Anatomy and Anatomy.OnBuilt and Anatomy.OnRestored then
	Anatomy.OnBuilt:Connect(function(model, section, pieces, landmarks)
		if section == SECTION and typeof(model) == "Instance" and type(pieces) == "table" then
			setView(model, pieces, landmarks)
		end
	end)
	Anatomy.OnRestored:Connect(function(model, section)
		if section == SECTION and typeof(model) == "Instance" and views[model] then
			setView(model, nil, nil)
		end
	end)
end

local function rebuildQueue()
	table.clear(queue)
	for _, rec in pairs(tracked) do
		if rec.mesh then
			for _, st in pairs(rec.mesh) do
				queue[#queue + 1] = st
			end
		end
	end
	for st in pairs(draining) do
		if st.pending then
			queue[#queue + 1] = st
		else
			draining[st] = nil
		end
	end
	cursor = 1
	queueDirty = false
end

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------
function BodyFX.Track(model)
	if model and not tracked[model] then
		local rec = newRec(model)
		tracked[model] = rec
		local view = views[model]
		if not view and Anatomy and Anatomy.GetPieces then
			-- built before this module was listening
			local ok, v = pcall(Anatomy.GetPieces, model, SECTION)
			if ok and type(v) == "table" then
				local okL, lm = pcall(Anatomy.GetLandmarks, model)
				setView(model, v, okL and lm or nil)
				return
			end
		end
		if view then
			rec.mesh = meshState(rec, view)
			queueDirty = true
		end
	end
end

-- every blend shape back to the generated shape: queued, so flushMorphs writes it within the frame budget (a
-- camera cut can send many characters out of range in the same frame)
local function relaxMesh(rec)
	if not rec.mesh then
		return
	end
	for _, st in pairs(rec.mesh) do
		local w, s = st.w, st.sent
		for k in pairs(w) do
			w[k] = 0
		end
		local moved = false
		for k, v in pairs(s) do
			if v ~= 0 then
				moved = true
			end
			if w[k] == nil then
				w[k] = 0
			end
		end
		st.pending = moved
	end
end

function BodyFX.Untrack(model)
	local rec = tracked[model]
	if not rec then
		return
	end
	-- leave the muscles exactly as the Builder made them
	for _, m in ipairs(rec.list) do
		if m.mesh.Parent then
			m.mesh.Scale = m.base
		end
	end
	for _, v in ipairs(rec.veins) do
		if v.beam.Parent then
			v.beam.Transparency = NumberSequence.new(v.base)
		end
	end
	-- the shapes relax over the next frames (the record leaves the round-robin, its piece states stay queued)
	relaxMesh(rec)
	for _, st in pairs(rec.mesh or {}) do
		if st.pending then
			draining[st] = true
		end
	end
	tracked[model] = nil
	queueDirty = true
end

-- region: "chest" | "core" | "arms" | "legs" | "all"; amount ~0..1.5 (velocity kick)
function BodyFX.Jiggle(model, region, amount)
	local rec = tracked[model]
	if not rec then
		return
	end
	local a = (amount or 0.5) * 2.2
	if region == "all" then
		for i = 1, 4 do
			rec.jv[i] += a * (i == 2 and 1 or 0.7)
		end
	else
		local i = REGION_ID[region]
		if i then
			rec.jv[i] += a
		end
	end
	rec.awake = true
	rec.meshAwake = true
end

-- index the Muscles folder (rebuilt by every Builder.Cosmetics, so re-scan when it changes)
local function scan(rec)
	local look = rec.model:FindFirstChild("BoxerLook")
	local folder = look and look:FindFirstChild("Muscles")
	if folder == rec.folder then
		return
	end
	rec.folder = folder or false
	table.clear(rec.list)
	table.clear(rec.veins)
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			local id = d:GetAttribute("Part")
			local mesh = id and d:FindFirstChildOfClass("SpecialMesh")
			if mesh and not d:GetAttribute("Groove") and not d:GetAttribute("Fat") then
				local base = d:GetAttribute("BaseScale")
				if typeof(base) ~= "Vector3" then
					base = mesh.Scale
				end
				-- the longest axis is the fibre direction: contraction shortens it and thickens the others
				local s = d.Size
				local long = (s.X >= s.Y and s.X >= s.Z) and 1 or ((s.Y >= s.Z) and 2 or 3)
				local group = d:GetAttribute("Group") or (Config.MusclePartGroup and Config.MusclePartGroup[id]) or ""
				table.insert(rec.list, {
					part = d, mesh = mesh, base = base, id = id, side = d:GetAttribute("Side") or 0,
					long = long, region = REGION[group] or 2, c = 0, wk = -1, wl = -1,
					peak = (d:GetAttribute("Layer") or 1) >= 2,
				})
			end
		elseif d:IsA("Beam") and d.Name == "Vein" then
			local base = d:GetAttribute("BaseTransparency")
			if type(base) ~= "number" then
				base = 0.6
			end
			table.insert(rec.veins, { beam = d, id = d:GetAttribute("Part") or "", base = base, last = base })
		end
	end
end

local function readAttrs(rec, now)
	local m = rec.model
	local pump = m:GetAttribute("Pump")
	local at = m:GetAttribute("PumpAt")
	local level = 0
	if type(pump) == "number" and pump > 0 then
		if type(at) == "number" then
			level = pump * K.clamp01(1 - (now - at) / PUMP_DURATION)
		else
			level = pump
		end
	end
	rec.pump = level
	local parts = m:GetAttribute("PumpParts")
	if parts ~= rec.pumpStr then
		rec.pumpStr = parts
		table.clear(rec.pumpSet)
		if type(parts) == "string" then
			for id in string.gmatch(parts, "[^,%s]+") do
				rec.pumpSet[id] = true
			end
		end
	end
	local live = m:GetAttribute("LivePump")
	rec.live = type(live) == "number" and K.clamp01(live) or 0
	local strain = m:GetAttribute("Strain")
	local effort = m:GetAttribute("Effort")
	rec.strain = max(type(strain) == "number" and strain or 0, type(effort) == "number" and effort * 0.6 or 0)
	-- mesh extras: sweat sheen, rib bruises, a rebuilt Attire (new lettering)
	local view = rec.mesh and views[m]
	if view then
		local fx = LookData and LookData.Fx(m)
		local q = fx and fx.sweat or (tonumber(m:GetAttribute("Sweat")) or 0)
		if q ~= rec.sweat then
			rec.sweat = q
			applySweat(m, view, q)
		end
		if fx then
			applyBruise(m, view, rec, tonumber(fx.dmg.ribsL) or 0, tonumber(fx.dmg.ribsR) or 0, fx.dmg.age)
		end
		local look = m:FindFirstChild("BoxerLook")
		local attire = look and look:FindFirstChild("Attire")
		local w = attire and attire:FindFirstChild("WaistText") or false
		local p = attire and attire:FindFirstChild("SponsorPatch") or false
		if w ~= rec.plateSrcW or p ~= rec.plateSrcP then
			rec.plateSrcW, rec.plateSrcP = applyPlates(m, landmarksOf[m])
		end
	end
end

function restore(rec)
	for _, m in ipairs(rec.list) do
		if m.wk ~= -1 and m.mesh.Parent then
			m.mesh.Scale = m.base
		end
		m.wk, m.wl, m.c = -1, -1, 0
	end
	for _, v in ipairs(rec.veins) do
		if v.last ~= v.base and v.beam.Parent then
			v.beam.Transparency = NumberSequence.new(v.base)
		end
		v.last = v.base
	end
end

------------------------------------------------------------------------
-- Mesh path: weights per piece
------------------------------------------------------------------------
-- smoothed contraction (muscles tense fast and relax slowly) for every muscle the rig names, one side
local function smoothSide(cur, src, upRate, downRate)
	local any = false
	-- muscles the rig contracts now
	if src then
		for id, want in pairs(src) do
			local c = cur[id] or 0
			c += (want - c) * (want > c and upRate or downRate)
			cur[id] = c
			if c > 1e-3 then
				any = true
			end
		end
	end
	-- muscles it no longer names relax
	for id, c in pairs(cur) do
		if not (src and src[id]) then
			c -= c * downRate
			if c < 1e-3 then
				c = 0
			else
				any = true
			end
			cur[id] = c
		end
	end
	return any
end

local function smoothContraction(rec, cxL, cxR, upRate, downRate)
	local a = smoothSide(rec.cL, cxL, upRate, downRate)
	local b = smoothSide(rec.cR, cxR, upRate, downRate)
	return a or b
end

local function pumpOf(rec, id, liveSet)
	local p = rec.pumpSet[id] and rec.pump or 0
	if liveSet and liveSet[id] then
		p = max(p, rec.live * liveSet[id])
	end
	return p
end

-- desired weights for every piece of one character; marks the pieces whose quantised weights changed
local function meshWeights(rec, rig, breathing, t)
	local liveSet = rec.live > 0 and rig and rig.poseAct and TARGETS[rig.poseAct] or nil
	local jx = rec.jx
	if not (breathing and rig) then
		rec.breath = 0
	elseif t >= rec.nextBreath then
		rec.nextBreath = t + BREATH_RATE
		local b = K.clamp01(rig.breath or 0)
		rec.breath = (0.35 + 0.65 * b) * K.breath(rig.breathPhase or 0)
	end
	local breath = rec.breath
	local any = false
	for _, st in pairs(rec.mesh) do
		local share = FLEX_OF[st.kind]
		local c, p = 0, 0
		for id, k in pairs(share) do
			local v
			if st.side < 0 then
				v = rec.cL[id] or 0
			elseif st.side > 0 then
				v = rec.cR[id] or 0
			else
				v = max(rec.cL[id] or 0, rec.cR[id] or 0)
			end
			c = max(c, v * k)
			p = max(p, pumpOf(rec, id, liveSet) * k)
		end
		local w = st.w
		if st.hasFlex then
			w.flex = quant(math.clamp(c + 0.6 * p + 0.45 * jx[st.region], -0.3, 1))
		end
		if st.hasBreathe then
			w.breathe = quant(breath)
		end
		if st.hasTense then
			local t = 0
			for id, k in pairs(TENSE_OF) do
				t = max(t, max(rec.cL[id] or 0, rec.cR[id] or 0) * k)
			end
			w.tense = quant(math.clamp(t + 0.5 * rec.strain + 0.6 * jx[2], -0.3, 1))
		end
		local s = st.sent
		if w.flex ~= s.flex or w.breathe ~= s.breathe or w.tense ~= s.tense then
			st.pending = true
		end
		if w.flex ~= 0 or w.breathe ~= 0 or w.tense ~= 0 then
			any = true
		end
	end
	return any
end

-- round-robin writes within the frame budget
local function flushMorphs()
	local n = #queue
	if n == 0 or not Anatomy then
		return
	end
	local budget = MORPH_BUDGET
	local wrote = false
	local before = stats.vertexWrites
	for _ = 1, n do
		if cursor > n then
			cursor = 1
		end
		local st = queue[cursor]
		cursor += 1
		if st.pending then
			local w, s = st.w, st.sent
			local cost = min(st.cost, (w.flex ~= s.flex and st.nFlex or 0) + (w.breathe ~= s.breathe and st.nBreathe or 0)
				+ (w.tense ~= s.tense and st.nTense or 0))
			if wrote and cost > budget then
				break
			end
			Anatomy.SetMorphs(st.rec.model, SECTION, st.name, w)
			s.flex, s.breathe, s.tense = w.flex, w.breathe, w.tense
			st.pending = false
			if draining[st] then
				-- an untracked character's shapes are back at rest: it leaves the round-robin
				draining[st] = nil
				queueDirty = true
			end
			budget -= cost
			wrote = true
			stats.morphWrites += 1
			stats.vertexWrites += cost
			if budget <= 0 then
				break
			end
		end
	end
	stats.maxFrame = max(stats.maxFrame, stats.vertexWrites - before)
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------
-- rigs = the Animator's rig table (rig.cxL / rig.cxR / rig.poseAct / rig.near), may be nil
function BodyFX.Update(dt, t, camPos, rigs)
	local now = workspace:GetServerTimeNow()
	if queueDirty then
		rebuildQueue()
	end
	for model, rec in pairs(tracked) do
		if not model.Parent then
			tracked[model] = nil
			queueDirty = true
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		if t >= rec.nextAttr then
			rec.nextAttr = t + 0.2
			readAttrs(rec, now)
		end
		local dist = (root.Position - camPos).Magnitude
		local far = dist > NEAR
		if far then
			if rec.awake then
				restore(rec)
				rec.awake = false
			end
			if rec.meshAwake then
				relaxMesh(rec)
				rec.meshAwake = false
			end
			continue
		end
		if t >= rec.nextScan then
			rec.nextScan = t + 0.5
			scan(rec)
		end
		local rig = rigs and rigs[model]
		local cxL = rig and rig.cxL
		local cxR = rig and rig.cxR
		-- jiggle springs
		local jig = false
		for i = 1, 4 do
			local x, v = K.spring(rec.jx[i], rec.jv[i], 0, JIG_K, JIG_C, dt)
			if abs(x) < 1e-4 and abs(v) < 1e-3 then
				x, v = 0, 0
			else
				jig = true
			end
			rec.jx[i], rec.jv[i] = x, v
		end
		local upRate, downRate = 1 - exp(-dt * 14), 1 - exp(-dt * 5)
		if rec.mesh then
			-- anatomy meshes: blend shapes (the round-1 muscle parts and veins are hidden under them)
			local anyC = smoothContraction(rec, cxL, cxR, upRate, downRate)
			local breathing = dist < BREATH_RANGE and rig ~= nil
			local active = anyC or jig or rec.pump > 0.005 or rec.live > 0.005 or rec.strain > 0.02 or breathing
			if (active or rec.meshAwake) and t >= rec.nextMorph then
				rec.nextMorph = t + (dist < 20 and MORPH_RATE or MORPH_RATE * 2)
				rec.meshAwake = meshWeights(rec, rig, breathing, t)
			end
			continue
		end
		local list = rec.list
		if #list == 0 then
			continue
		end
		local live = rec.live
		local liveSet = live > 0 and rig and rig.poseAct and TARGETS[rig.poseAct] or nil
		local anyC = false
		if cxL then
			for _, v in pairs(cxL) do
				if v > 0 then
					anyC = true
					break
				end
			end
		end
		if not anyC and cxR then
			for _, v in pairs(cxR) do
				if v > 0 then
					anyC = true
					break
				end
			end
		end
		local active = anyC or jig or rec.pump > 0.005 or live > 0.005
		if not active and not rec.awake then
			continue
		end
		local settled = true
		for _, m in ipairs(list) do
			local id = m.id
			local want = 0
			if cxL or cxR then
				local l = cxL and cxL[id] or 0
				local r = cxR and cxR[id] or 0
				if m.side < 0 then
					want = l
				elseif m.side > 0 then
					want = r
				else
					want = max(l, r)
				end
			end
			-- muscles tense fast and relax slowly
			m.c += (want - m.c) * (want > m.c and upRate or downRate)
			if m.c < 1e-3 then
				m.c = 0
			end
			local pump = rec.pumpSet[id] and rec.pump or 0
			if liveSet and liveSet[id] then
				pump = max(pump, live * liveSet[id])
			end
			local c = m.c * (m.peak and 1.25 or 1)
			local j = rec.jx[m.region]
			local thick = 1 + FLEX_SCALE * c + PUMP_SCALE * pump + j * 0.5
			local long = 1 - FLEX_SCALE * 0.35 * c + PUMP_SCALE * 0.4 * pump - j * 0.25
			if c > 0 or pump > 0 or j ~= 0 then
				settled = false
			end
			-- skip the write when nothing visible changed (Scale writes replicate to the renderer)
			if abs(thick - m.wk) > 0.002 or abs(long - m.wl) > 0.002 then
				m.wk, m.wl = thick, long
				local b = m.base
				if m.long == 1 then
					m.mesh.Scale = V3(b.X * long, b.Y * thick, b.Z * thick)
				elseif m.long == 2 then
					m.mesh.Scale = V3(b.X * thick, b.Y * long, b.Z * thick)
				else
					m.mesh.Scale = V3(b.X * thick, b.Y * thick, b.Z * long)
				end
			end
		end
		-- veins: pump, contraction of the host muscle and strain bring them out
		for _, v in ipairs(rec.veins) do
			local id = v.id
			local c = 0
			if cxL or cxR then
				c = max(cxL and cxL[id] or 0, cxR and cxR[id] or 0)
			end
			local pump = rec.pumpSet[id] and rec.pump or rec.pump * 0.3
			local level = K.clamp01(pump * (1 + VEIN_BOOST) * 0.8 + c * 0.45 + rec.strain * 0.35)
			-- conditioning sets how far they come out: the Builder's base (VeinLevel) drops by at most
			-- Config.Pump.veinBoost, so a beginner's pump shows faint veins, an athlete's clear ones,
			-- and nothing goes past the elite floor (0.15) or ever fades below its own base
			local target = min(v.base, max(0.15, v.base - VEIN_BOOST * level))
			target = floor(target * 20 + 0.5) / 20
			if target ~= v.last then
				v.last = target
				v.beam.Transparency = NumberSequence.new(target)
			end
			if target ~= v.base then
				settled = false
			end
		end
		rec.awake = not settled
	end
	flushMorphs()
end

-- counters for tools and tests: characters on each path, blend-shape writes, plates, bruises
function BodyFX.Status()
	local out = { tracked = 0, mesh = 0, parts = 0, queue = #queue }
	for k, v in pairs(stats) do
		out[k] = v
	end
	for _, rec in pairs(tracked) do
		out.tracked += 1
		if rec.mesh then
			out.mesh += 1
		elseif #rec.list > 0 then
			out.parts += 1
		end
	end
	return out
end

-- Track every player's character as well (pump shows on players walking around after training)
local function hookPlayer(plr)
	plr.CharacterAdded:Connect(function(char)
		BodyFX.Track(char)
	end)
	if plr.Character then
		BodyFX.Track(plr.Character)
	end
end
for _, plr in ipairs(Players:GetPlayers()) do
	hookPlayer(plr)
end
Players.PlayerAdded:Connect(hookPlayer)

return BodyFX
