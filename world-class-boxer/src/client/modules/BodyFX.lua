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
--    tense (core bracing, body-shot jiggle, Strain), raiseL / raiseR / reachL / reachR (the shoulder
--    girdle following the upper arm's angle), hipLxx .. hipRzz (the trunks' seat skinned to each hip: the
--    thigh's rotation in the pelvis's frame) and hipLqxx .. hipRqzz (its rows bent on the arc past 30 degrees).
--    Writes are low rate and budgeted (MORPH_BUDGET vertex writes
--    per frame across every character, round-robin, only when a weight changes by a 0.1 step). Sweat shows
--    as the pieces' Reflectance; rib bruises (LookFx ribsL / ribsR) and road grime (LookFx grime / the Grime
--    attribute) are painted into the pieces: their vertex colours, or their colour textures (a few
--    thousand texels per frame, time-sliced); the trunks' waistband text / sponsor patch and the gear's
--    glove logo, cuff wordmark, boot wordmark and heel mark (hidden with the round-1 parts they sat on)
--    come back as client text plates on the mesh (landmarks).
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

-- (the trunks' seat's bend shapes' weights: AnatomyBodyTorso.HipBendWeights, the generator's own)
local Torso
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local m = shared and shared:FindFirstChild("AnatomyBodyTorso")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	Torso = ok and type(mod) == "table" and type(mod.HipBendWeights) == "function" and mod or nil
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
-- the blend shapes BodyFX drives (a piece has the ones its mesh carries)
local SHAPES = { "flex", "breathe", "tense", "raiseL", "raiseR", "reachL", "reachR" }
-- the trunks' seat's hip shapes (AnatomyBodyTorso.HipShapes): per side the nine entries of the thigh's rotation
-- in the pelvis's frame, row-major (HIP_NAMES[side][a * 3 + b - 3] = "hip" .. side .. a .. b), then the nine
-- bend shapes' ("hip" .. side .. "q" .. a .. b: the arc the seat's rows turn on, not the chord)
local HIP_NAMES = {}
for _, s in ipairs({ "L", "R" }) do
	local list = {}
	for _, q in ipairs({ "", "q" }) do
		for _, a in ipairs({ "x", "y", "z" }) do
			for _, b in ipairs({ "x", "y", "z" }) do
				list[#list + 1] = "hip" .. s .. q .. a .. b
				SHAPES[#SHAPES + 1] = "hip" .. s .. q .. a .. b
			end
		end
	end
	HIP_NAMES[s] = list
end
-- vertex writes per frame, every character together: FaceFX writes about 1000 more (one Head SetMorphs per
-- frame), and the contract caps every FX module together at 2000 (ANATOMY_CONTRACTS section 11)
local MORPH_BUDGET = 1000
local PAINT_BUDGET = 4096 -- texels per frame recomposed into piece textures (bruises / grime)
local MORPH_STEP = 0.1 -- weights move in these steps (a flex step is a millimetre or two: no write below it)
local MORPH_RATE = 1 / 20 -- per character: blend shapes at most this often (near), half as often far
local BREATH_RATE = 1 / 10 -- breathing (slow, tiny) at most this often
local BREATH_RANGE = 30 -- studs: breathing only this close (it rewrites the chest continuously)

local function quant(x)
	return floor(x / MORPH_STEP + 0.5) * MORPH_STEP
end
-- the seat's hip shapes in finer steps (a 0.1 step of a rotation entry is ~6 degrees of thigh swing: the
-- seat's rim stepped off the satin leg's rim ring by centimetres; at this step by a few millimetres)
local HIP_STEP = 0.0125
local function quantHip(x)
	return floor(x / HIP_STEP + 0.5) * HIP_STEP
end
-- how far the seat follows a hip's turn: all of it up to HIP_KNEE, then easing toward HIP_MAX (the seat's box
-- holds 110 degrees: AnatomyBodyTorso HIP_RANGE). The corner stool, a knockdown sit, a kneel swing a thigh 85 -
-- 100 degrees: with the bend shapes the seat's rows turn on the arc about the hip with it (on the chord they
-- had cut in toward the hip, through the back of the satin leg's top, and the seat stopped following at 60:
-- the leg's top stood a lid out of it). Without them (no Torso module) the old 45 -> 60 cap
local HIP_KNEE, HIP_MAX = math.rad(95), math.rad(110)
local HIP_KNEE0, HIP_MAX0 = math.rad(45), math.rad(60)
-- (the bend shapes only past this turn: under it the arc and the chord part by a millimetre or two, and the
-- nine more shapes' writes are not worth it; eased in over HIP_BEND_EASE)
local HIP_BEND0, HIP_BEND_EASE = math.rad(30), math.rad(10)
local bendR, bendW = table.create(9, 0), table.create(9, 0)

local stats = { morphWrites = 0, vertexWrites = 0, plates = 0, bruises = 0, grime = 0, texJobs = 0, texWrites = 0, texels = 0, sweat = 0, maxFrame = 0 }
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

local function sstep(e0, e1, x)
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

------------------------------------------------------------------------
-- Skin paint layers (rib bruises, road grime) on the mesh pieces: per piece, layers of per-vertex weights
-- toward a colour, composed over the generated colour. A vertex-coloured piece gets them through
-- SetVertexColors; a textured piece (its EditableImage, AnatomyClient view .image) is recomposed texel by
-- texel from its original texels through the mesh's texMap (each texel's four lattice vertices), a few
-- thousand texels per frame. Garment vertices (the mesh group "cloth") are never painted.
------------------------------------------------------------------------
local paintJobs = {} -- queue of texture recompose jobs
local LAYER_ORDER = { "bruiseL", "bruiseR", "grime" }

local function clothSet(pv)
	if pv.cloth == nil then
		local set = false
		local g = pv.groups and pv.groups.cloth
		if type(g) == "table" and #g > 0 then
			set = {}
			for _, i in ipairs(g) do
				set[i] = true
			end
		end
		pv.cloth = set
	end
	return pv.cloth
end

-- texture recompose: rows of texels from the original, blended toward each layer's colour by the
-- bilinear weight of the texel's lattice vertices
local function startTexJob(model, pv)
	local img, map = pv.image, pv.mesh and pv.mesh.texMap
	if not (img and map) then
		return
	end
	for i = #paintJobs, 1, -1 do
		if paintJobs[i].pv == pv then
			table.remove(paintJobs, i)
		end
	end
	local layers = {}
	for _, key in ipairs(LAYER_ORDER) do
		local L = pv.layers and pv.layers[key]
		if L and L.any then
			layers[#layers + 1] = L
		end
	end
	table.insert(paintJobs, { model = model, pv = pv, img = img, map = map, layers = layers, py = 0, r0 = 1, out = nil })
	stats.texJobs += 1
end

local function texJobStep(job, budget)
	local pv, map, img = job.pv, job.map, job.img
	local w, h = map.w, map.h
	if not job.out then
		if not pv.orig then
			local ok, buf = pcall(function()
				return img:ReadPixelsBuffer(Vector2.zero, Vector2.new(w, h))
			end)
			if not ok or type(buf) ~= "buffer" or buffer.len(buf) ~= w * h * 4 then
				pv.image = nil -- not paintable: this piece keeps its generated texture
				return true, 0
			end
			pv.orig = buf
		end
		job.out = buffer.create(w * h * 4)
		buffer.copy(job.out, 0, pv.orig, 0, w * h * 4)
	end
	local layers = job.layers
	local nL = #layers
	local out, orig = job.out, pv.orig
	local rv, rs, rn = map.v, map.s, map.n
	local nr = #rv
	local sides, uA, uB = map.sides, map.uA, map.uB
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	local used = 0
	while job.py < h and used < budget do
		local py = job.py
		job.py += 1
		used += 16 -- a row's fixed cost
		if nL > 0 then
			local v = (py + 0.5) / h
			local r0 = job.r0
			while r0 < nr - 1 and rv[r0 + 1] < v do
				r0 += 1
			end
			job.r0 = r0
			local va, vb = rv[r0], rv[r0 + 1]
			local t = vb > va and math.clamp((v - va) / (vb - va), 0, 1) or 0
			local sa, sb, na, nb = rs[r0], rs[r0 + 1], rn[r0], rn[r0 + 1]
			-- rows whose lattice vertices carry no weight stay the original texels
			local live = false
			for q = 1, nL do
				local W = layers[q].W
				for j = 0, na - 1 do
					if W[sa + j] > 0 then
						live = true
						break
					end
				end
				if not live then
					for j = 0, nb - 1 do
						if W[sb + j] > 0 then
							live = true
							break
						end
					end
				end
				if live then
					break
				end
			end
			if live then
				for px = 0, w - 1 do
					local jf = math.clamp(((px + 0.5) / w - uA) / (uB - uA), 0, 1) * sides
					local j = floor(jf)
					if j > sides - 1 then
						j = sides - 1
					end
					local f = jf - j
					local i1, i2 = sa + min(j, na - 1), sa + min(j + 1, na - 1)
					local i3, i4 = sb + min(j, nb - 1), sb + min(j + 1, nb - 1)
					local w1, w2, w3, w4 = (1 - f) * (1 - t), f * (1 - t), (1 - f) * t, f * t
					local o = (py * w + px) * 4
					local r, g, b
					for q = 1, nL do
						local L = layers[q]
						local W = L.W
						local k = W[i1] * w1 + W[i2] * w2 + W[i3] * w3 + W[i4] * w4
						if k > 0.004 then
							if not r then
								r, g, b = readu8(orig, o) / 255, readu8(orig, o + 1) / 255, readu8(orig, o + 2) / 255
							end
							r, g, b = r + (L.r - r) * k, g + (L.g - g) * k, b + (L.b - b) * k
						end
					end
					if r then
						writeu8(out, o, floor(math.clamp(r, 0, 1) * 255 + 0.5))
						writeu8(out, o + 1, floor(math.clamp(g, 0, 1) * 255 + 0.5))
						writeu8(out, o + 2, floor(math.clamp(b, 0, 1) * 255 + 0.5))
					end
				end
				used += w
				stats.texels += w
			end
		end
	end
	if job.py >= h then
		local ok = pcall(function()
			img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), job.out)
		end)
		if ok then
			stats.texWrites += 1
		else
			pv.image = nil
		end
		return true, used
	end
	return false, used
end

-- recompose the paint jobs within the frame's texel budget
local function paintStep()
	local budget = PAINT_BUDGET
	while budget > 0 and #paintJobs > 0 do
		local job = paintJobs[1]
		local done, used = true, 0
		if job.model.Parent and job.pv.image and job.pv.part and job.pv.part.Parent then
			done, used = texJobStep(job, budget)
		end
		budget -= math.max(used, 1)
		if done then
			table.remove(paintJobs, 1)
		end
	end
end

-- apply a piece's layers: vertex colours (untextured piece) or a texture job
local function composePiece(model, pv, name)
	if not (pv.mesh and pv.part and Anatomy) then
		return
	end
	if pv.image and pv.mesh.texMap then
		startTexJob(model, pv)
		return
	end
	local C = pv.mesh.C
	if type(C) ~= "table" then
		return
	end
	local ids, cols = {}, {}
	local now = {}
	local painted = pv.painted or {}
	for i = 1, pv.mesh.nv do
		local r, g, b
		for _, key in ipairs(LAYER_ORDER) do
			local L = pv.layers and pv.layers[key]
			local k = L and L.any and L.W[i] or 0
			if k > 0.004 then
				if not r then
					r, g, b = C[i * 3 - 2], C[i * 3 - 1], C[i * 3]
				end
				r, g, b = r + (L.r - r) * k, g + (L.g - g) * k, b + (L.b - b) * k
			end
		end
		if r then
			ids[#ids + 1] = i
			cols[#ids] = Color3.new(r, g, b)
			now[i] = true
		elseif painted[i] then
			-- back to the generated colour
			ids[#ids + 1] = i
			cols[#ids] = Color3.new(C[i * 3 - 2], C[i * 3 - 1], C[i * 3])
		end
	end
	if #ids > 0 then
		Anatomy.SetVertexColors(model, SECTION, name, ids, cols)
	end
	pv.painted = now
end

-- a weight layer on a piece (weights by vertex from fn(i, x, y, z, nx, ny, nz) -> 0..1); true when it changed
local function setLayer(pv, key, r, g, b, fn)
	pv.layers = pv.layers or {}
	local mesh = pv.mesh
	local P, N = mesh.P, mesh.N
	local cloth = clothSet(pv)
	local L = pv.layers[key]
	if not fn then
		if L and L.any then
			L.any = false
			table.clear(L.W)
			return true
		end
		return false
	end
	local W = table.create(mesh.nv, 0)
	local any = false
	for i = 1, mesh.nv do
		if not (cloth and cloth[i]) then
			local k = fn(i, P[i * 3 - 2], P[i * 3 - 1], P[i * 3], N[i * 3 - 2], N[i * 3 - 1], N[i * 3])
			if k > 0.004 then
				W[i] = math.min(k, 1)
				any = true
			end
		end
	end
	pv.layers[key] = { W = W, r = r, g = g, b = b, any = any }
	return any or (L ~= nil and L.any)
end

-- rib bruises (LookFx ribsL / ribsR, 0..1 each) on the UpperTorso piece where the round-1 RibBruise plates
-- sat (the lower ribs from the flank round toward the front)
local function applyBruise(model, view, rec, ribsL, ribsR, age)
	local pv = view.UpperTorso
	if not (pv and pv.mesh and pv.part and Anatomy) then
		return
	end
	age = floor((tonumber(age) or 0) * 10 + 0.5) / 10
	ribsL, ribsR = floor(ribsL * 20 + 0.5) / 20, floor(ribsR * 20 + 0.5) / 20
	if pv.bruiseL == ribsL and pv.bruiseR == ribsR and pv.bruiseAge == age then
		return
	end
	pv.bruiseL, pv.bruiseR, pv.bruiseAge = ribsL, ribsR, age
	-- mesh positions are in the R15 UpperTorso's space: place the bruise where the round-1 plates sat
	local ut = model:FindFirstChild("UpperTorso")
	local s = ut and ut:IsA("BasePart") and ut.Size or pv.part.Size
	local look = LookData and LookData.Get(model)
	local female = type(look) == "table" and look.g == 2
	local sk = LookData and type(look) == "table" and look.skinRGB
	local sr, sg, sb = 0.8, 0.6, 0.45
	if type(sk) == "table" and tonumber(sk[1]) then
		sr, sg, sb = sk[1] / 255, sk[2] / 255, sk[3] / 255
	end
	local br, bg, bb = bruiseRGB(sr, sg, sb, age)
	local changed = false
	for _, e in ipairs({ { -1, ribsL, "bruiseL" }, { 1, ribsR, "bruiseR" } }) do
		local side, v, key = e[1], e[2], e[3]
		local fn
		if v > 0.08 then
			local cx, cy = side * 0.36 * s.X, (female and -0.33 or -0.14) * s.Y
			local ax, ay = (0.17 + 0.06 * v) * s.X, (0.16 + 0.08 * v) * s.Y
			-- the round-1 plate: 75 % of the way from the skin to the bruise colour at its centre
			local alpha = math.clamp(0.22 + 0.45 * v, 0.2, 0.65) * 0.75
			fn = function(_, x, y)
				if x * side <= 0 then
					return 0
				end
				local dx, dy = (x - cx) / ax, (y - cy) / ay
				local d2 = dx * dx + dy * dy
				if d2 >= 1 then
					return 0
				end
				return (1 - d2) * (1 - d2) * alpha
			end
		end
		if setLayer(pv, key, br, bg, bb, fn) then
			changed = true
		end
	end
	if changed then
		composePiece(model, pv, "UpperTorso")
		stats.bruises += 1
	end
	return rec
end

-- road grime (LookFx grime / the Grime attribute, 0..1): dirt on the front of the shins and forearms (the
-- round-1 Grime patches live in the Muscles folder the meshes replace)
local GRIME_PIECES = { "LeftLowerLeg", "RightLowerLeg", "LeftLowerArm", "RightLowerArm" }
local DIRT_R, DIRT_G, DIRT_B = 96 / 255, 80 / 255, 60 / 255
local function applyGrime(model, view, grime)
	local g = floor(math.clamp(tonumber(grime) or 0, 0, 1) * 10 + 0.5) / 10
	for _, name in ipairs(GRIME_PIECES) do
		local pv = view[name]
		local mesh = pv and pv.mesh
		if mesh and pv.part and pv.grimeLevel ~= g then
			pv.grimeLevel = g
			local fn
			if g >= 0.1 then
				local P = mesh.P
				local ylo, yhi = math.huge, -math.huge
				for i = 1, mesh.nv do
					local y = P[i * 3 - 1]
					ylo, yhi = min(ylo, y), max(yhi, y)
				end
				local leg = string.find(name, "Leg") ~= nil
				local span = max(1e-6, yhi - ylo)
				fn = function(_, _x, y, _z, _nx, _ny, nz)
					local t = (y - ylo) / span
					local band = leg and sstep(0.33, 0.45, t) * (1 - sstep(0.8, 0.92, t)) or sstep(0.13, 0.25, t) * (1 - sstep(0.75, 0.87, t))
					return band * math.clamp(-nz * 1.4, 0, 1) * (0.25 + 0.35 * g)
				end
			end
			if setLayer(pv, "grime", DIRT_R, DIRT_G, DIRT_B, fn) then
				composePiece(model, pv, name)
				stats.grime += 1
			end
		end
	end
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

-- cf: the plate's frame in the attach part's space (a Vector3 = axis aligned, the gui facing -Z)
local function makePlate(folder, name, src, attach, cf, size)
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
	local c0 = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
	p.CFrame = attach.CFrame * c0
	local g = gui:Clone()
	g.Face = Enum.NormalId.Front
	g.Enabled = true
	g:SetAttribute("AnatomyHid", nil)
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

-- the round-1 patch's text area (its SurfaceGui face's two extents)
local function textArea(src)
	local gui = src:FindFirstChildOfClass("SurfaceGui")
	local face = gui and gui.Face or Enum.NormalId.Front
	local s = src.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	end
	return s.X, s.Y
end

-- "R" / "L" from the R15 part a patch is welded to
local function patchSide(src)
	local wc = src:FindFirstChildOfClass("WeldConstraint")
	local a = wc and wc.Part0
	local n = a and a.Name or ""
	if string.sub(n, 1, 5) == "Right" then
		return "R"
	elseif string.sub(n, 1, 4) == "Left" then
		return "L"
	end
	return nil
end

-- gear lettering: the source patches (by folder and name) and the landmark spot each goes to
local GEAR_PLATES = {
	{ folder = "Hands", name = "Logo", spot = "GloveLogo" },
	{ folder = "Hands", name = "Wordmark", spot = "CuffWord" },
	{ folder = "Attire", name = "Wordmark", spot = "BootWord" },
	{ folder = "Attire", name = "HeelMark", spot = "BootHeel" },
}

-- (re)make the plates for the current round-1 patches; returns a key of the sources used (to notice a
-- rebuild of the Attire / Hands folders)
local function applyPlates(model, lm)
	clearPlates(model)
	local look = model:FindFirstChild("BoxerLook")
	local attire = look and look:FindFirstChild("Attire")
	local hands = look and look:FindFirstChild("Hands")
	if not (look and lm) then
		return nil
	end
	local folder
	if attire then
		local waistSrc = attire:FindFirstChild("WaistText")
		local patchSrc = attire:FindFirstChild("SponsorPatch")
		-- only while the mesh trunks replace them (the Body section hides them then)
		local hiddenW = waistSrc and Anatomy and Anatomy.IsReplaced(waistSrc)
		local hiddenP = patchSrc and Anatomy and Anatomy.IsReplaced(patchSrc)
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
	end
	-- the gear's lettering (gloves, boots), each on its side's spot: a plate turned to the surface there
	for _, e in ipairs(GEAR_PLATES) do
		local f = e.folder == "Hands" and hands or attire
		if f then
			for _, src in ipairs(f:GetChildren()) do
				if src.Name == e.name and src:IsA("BasePart") and Anatomy and Anatomy.IsReplaced(src) then
					local L = patchSide(src)
					local key = L and e.spot .. L
					local entry = key and lm[key]
					local pos, n, up = lmVec(lm, key), key and lmVec(lm, key .. "N"), key and lmVec(lm, key .. "U")
					local attach = entry and type(entry.part) == "string" and model:FindFirstChild(entry.part)
					if pos and n and up and attach and attach:IsA("BasePart") then
						local dir = (n - pos).Unit
						local upv = (up - pos).Unit
						local cf = CFrame.lookAt(pos + dir * 0.012, pos + dir, upv)
						local aw, ah = textArea(src)
						folder = folder or plateFolder(model)
						makePlate(folder, e.spot .. L, src, attach, cf, V3(aw, ah, 0.02))
					end
				end
			end
		end
	end
	return attire or false, hands or false
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
			-- the shapes this piece carries, their vertex counts (AnatomyClient rewrites the vertices of the
			-- shapes whose weight moved: cost per shape, and the whole union as the cap)
			local names, n, w, sent = {}, {}, {}, {}
			for _, k in ipairs(SHAPES) do
				local mo = morphs[k]
				if mo then
					names[#names + 1] = k
					n[k] = mo.ids and #mo.ids or 0
					w[k], sent[k] = 0, 0
				end
			end
			st[name] = {
				rec = rec, name = name, kind = info[1], side = info[2], region = info[3],
				hasFlex = morphs.flex ~= nil, hasBreathe = morphs.breathe ~= nil, hasTense = morphs.tense ~= nil,
				hasShoulder = morphs.raiseL ~= nil or morphs.raiseR ~= nil or morphs.reachL ~= nil or morphs.reachR ~= nil,
				hasHip = morphs.hipLxx ~= nil or morphs.hipRxx ~= nil,
				names = names, n = n, cost = morphCost(pv.mesh), w = w, sent = sent, pending = false,
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
		rec.plateSrcW, rec.plateSrcP, rec.plateDue = nil, nil, nil
		queueDirty = true
	end
	if view then
		-- static extras for every model with meshes (tracked or not): sheen, bruises, grime, lettering
		local fx = LookData and LookData.Fx(model)
		applySweat(model, view, fx and fx.sweat or (tonumber(model:GetAttribute("Sweat")) or 0))
		if fx then
			applyBruise(model, view, rec, tonumber(fx.dmg.ribsL) or 0, tonumber(fx.dmg.ribsR) or 0, fx.dmg.age)
		end
		applyGrime(model, view, fx and fx.grime or model:GetAttribute("Grime"))
		local w, p = applyPlates(model, lm)
		if rec then
			rec.plateSrcW, rec.plateSrcP = w, p
		end
	else
		clearPlates(model)
		-- (a restored character's paint jobs go with its pieces)
		for i = #paintJobs, 1, -1 do
			if paintJobs[i].model == model then
				table.remove(paintJobs, i)
			end
		end
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
		applyGrime(m, view, fx and fx.grime or m:GetAttribute("Grime"))
		-- a rebuilt Attire / Hands folder (new lettering): re-plate a moment later, once AnatomyClient has
		-- hidden the new patches
		local look = m:FindFirstChild("BoxerLook")
		local attire = look and look:FindFirstChild("Attire") or false
		local hands = look and look:FindFirstChild("Hands") or false
		if attire ~= rec.plateSrcW or hands ~= rec.plateSrcP then
			if not rec.plateDue then
				rec.plateDue = now + 0.5
			elseif now >= rec.plateDue then
				rec.plateDue = nil
				applyPlates(m, landmarksOf[m])
				rec.plateSrcW, rec.plateSrcP = attire, hands
			end
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

-- the shoulder girdle follows the upper arm: raise (the arm lifted out / up: the trapezius and the top of the
-- shoulder lift) and reach (the arm forward: the shoulder comes forward round the ribs), from the arm's
-- direction in the torso's frame
local function shoulderShapes(model, side)
	local ut = model:FindFirstChild("UpperTorso")
	local ua = model:FindFirstChild(side .. "UpperArm")
	if not (ut and ua and ut:IsA("BasePart") and ua:IsA("BasePart")) then
		return 0, 0
	end
	local down = -ut.CFrame:VectorToObjectSpace(ua.CFrame.UpVector)
	local up = 1 + down.Y -- 0 hanging, 1 out to the side, 2 straight up
	return sstep(0.25, 1.6, up), sstep(0.15, 0.85, -down.Z)
end

-- the trunks' seat is skinned to each hip (AnatomyBodyTorso.HipShapes): the weights are the thigh's rotation in
-- the pelvis's frame less the identity (its axes there are the matrix's columns; at rest the thigh's frame is
-- the pelvis's), its angle capped (HIP_KNEE / HIP_MAX), and the bend shapes' (AnatomyBodyTorso.HipBendWeights)
local function hipShapes(model, side, list, w)
	local lt = model:FindFirstChild("LowerTorso")
	local ul = model:FindFirstChild(side .. "UpperLeg")
	if not (lt and ul and lt:IsA("BasePart") and ul:IsA("BasePart")) then
		-- (only the shapes this seat carries: a seat without the bend shapes keeps the old cap)
		for _, k in ipairs(list) do
			if w[k] ~= nil then
				w[k] = 0
			end
		end
		return
	end
	local lc, uc = lt.CFrame, ul.CFrame
	local cx, cy, cz = lc:VectorToObjectSpace(uc.RightVector), lc:VectorToObjectSpace(uc.UpVector), -lc:VectorToObjectSpace(uc.LookVector)
	-- (R's rows: R[a][b] is column b's component a)
	local xx, xy, xz = cx.X, cy.X, cz.X
	local yx, yy, yz = cx.Y, cy.Y, cz.Y
	local zx, zy, zz = cx.Z, cy.Z, cz.Z
	local th = math.acos(math.clamp((xx + yy + zz - 1) / 2, -1, 1))
	local bend = Torso ~= nil and list[10] ~= nil and w[list[10]] ~= nil
	local knee, top = bend and HIP_KNEE or HIP_KNEE0, bend and HIP_MAX or HIP_MAX0
	if th > knee then
		-- the same axis, the angle eased toward the top (Rodrigues)
		local nx, ny, nz = zy - yz, xz - zx, yx - xy
		local l = math.sqrt(nx * nx + ny * ny + nz * nz)
		if l > 1e-6 then
			nx, ny, nz = nx / l, ny / l, nz / l
			local a = knee + (top - knee) * math.tanh((th - knee) / (top - knee))
			th = a
			local c, s = math.cos(a), math.sin(a)
			local t = 1 - c
			xx, xy, xz = c + t * nx * nx, t * nx * ny - s * nz, t * nx * nz + s * ny
			yx, yy, yz = t * nx * ny + s * nz, c + t * ny * ny, t * ny * nz - s * nx
			zx, zy, zz = t * nx * nz - s * ny, t * ny * nz + s * nx, c + t * nz * nz
		end
	end
	w[list[1]], w[list[2]], w[list[3]] = quantHip(xx - 1), quantHip(xy), quantHip(xz)
	w[list[4]], w[list[5]], w[list[6]] = quantHip(yx), quantHip(yy - 1), quantHip(yz)
	w[list[7]], w[list[8]], w[list[9]] = quantHip(zx), quantHip(zy), quantHip(zz - 1)
	if bend then
		local e = th <= HIP_BEND0 and 0 or math.min(1, (th - HIP_BEND0) / HIP_BEND_EASE)
		if e > 0 then
			bendR[1], bendR[2], bendR[3] = xx, xy, xz
			bendR[4], bendR[5], bendR[6] = yx, yy, yz
			bendR[7], bendR[8], bendR[9] = zx, zy, zz
			Torso.HipBendWeights(bendR, bendW)
		end
		for i = 1, 9 do
			w[list[9 + i]] = e > 0 and quantHip(bendW[i] * e) or 0
		end
	end
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
		if st.hasShoulder then
			local rL, cL = shoulderShapes(rec.model, "Left")
			local rR, cR = shoulderShapes(rec.model, "Right")
			if w.raiseL then
				w.raiseL, w.reachL = quant(rL), quant(cL)
			end
			if w.raiseR then
				w.raiseR, w.reachR = quant(rR), quant(cR)
			end
		end
		if st.hasHip then
			if w.hipLxx then
				hipShapes(rec.model, "Left", HIP_NAMES.L, w)
			end
			if w.hipRxx then
				hipShapes(rec.model, "Right", HIP_NAMES.R, w)
			end
		end
		local s = st.sent
		for _, k in ipairs(st.names) do
			local v = w[k]
			if v ~= s[k] then
				st.pending = true
			end
			if v ~= 0 then
				any = true
			end
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
			local cost = 0
			for _, k in ipairs(st.names) do
				if w[k] ~= s[k] then
					cost += st.n[k]
				end
			end
			cost = min(st.cost, cost)
			if wrote and cost > budget then
				break
			end
			Anatomy.SetMorphs(st.rec.model, SECTION, st.name, w)
			for _, k in ipairs(st.names) do
				s[k] = w[k]
			end
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
	if #paintJobs > 0 then
		paintStep()
	end
end

-- counters for tools and tests: characters on each path, blend-shape writes, plates, bruises
function BodyFX.Status()
	local out = { tracked = 0, mesh = 0, parts = 0, queue = #queue, paintJobs = #paintJobs }
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
