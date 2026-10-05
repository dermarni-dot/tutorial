-- AnatomyClient: organic anatomy meshes on every character, generated on this client from the LookData
-- the server publishes (EditableMeshes do not replicate). The round-1 part-built look stays underneath
-- as the fallback and is hidden LOCALLY only once its replacement exists.
-- * watches models tagged "Anatomy" (Builder.Cosmetics tags every model it publishes LookData on),
--   Fighter / Trainee / Ambient / Referee / Preview models and player characters
-- * sections ("Body", "Head", "Hair") are generators registered by the shared modules AnatomyBody /
--   AnatomyHead / AnatomyHair (found automatically) or AnatomyClient.Register; with none registered it
--   does nothing at all
-- * per section: generate (pure MeshKit data, cached by section signature + level of detail), write
--   EditableMeshes, AssetService:CreateMeshPartAsync, weld the MeshParts to their parts, optional
--   EditableImage colour texture, then hide what the section replaces (LocalTransparencyModifier);
--   a rebuild swaps geometry in place with MeshPart:ApplyMesh
-- * level of detail: full for the local player, the fight opponent and the Config.Anatomy.maxFull
--   nearest within fullRange; medium / low further out; round-1 parts beyond lodRange
-- * one serial worker, time-sliced (Config.Anatomy.frameBudget per frame through MeshKit's tick), so
--   building never hitches; cancelled when the model goes away or its look changes again
-- * any Editable API failure (not enabled for the experience, memory budget) disables meshes for the
--   session, restores every character and warns once; a generator error disables that section only
-- Start: AnatomyClient.Start() (idempotent, client only). Any other public call starts it too, so the
-- first module that touches it (ClientMain, FaceFX, the Creator) brings it up. ANATOMY_CONTRACTS.md has
-- the generator contract (piece / landmark / replace rule shapes, budgets, coordinate conventions).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnatomyClient = {}

-- defaults; Start() overlays Config.Anatomy, then whatever a caller set here before Start wins
AnatomyClient.Settings = {
	enabled = true,
	maxFull = 6, -- full-detail characters besides the local player and the fight opponent
	fullRange = 70, -- studs
	lodRange = 160, -- studs; beyond: round-1 parts only
	frameBudget = 0.0025, -- seconds of work per frame
	textures = true, -- EditableImage colour textures for pieces that ask for one
	meshCentered = true, -- a MeshPart made from an EditableMesh is centred on the mesh's bounding box
	flipV = false, -- flip texture v if textures show upside down
	cacheSize = 12, -- generated sections kept for re-use (NPCs walking back into range, LOD flips)
	holdTime = 4, -- seconds a model keeps its level of detail before it may change again
	debug = false,
}

local TRACK_TAGS = { "Anatomy", "Fighter", "Trainee", "Ambient", "Referee", "Preview" }
local SECTION_ORDER = { Body = 1, Head = 2, Hair = 3 }
local GENERATORS = { AnatomyBody = "Body", AnatomyHead = "Head", AnatomyHair = "Hair" }
local LOD_RANK = { full = 3, medium = 2, low = 1 }
local CANCEL = "\0AnatomyCancelled"

-- round-1 geometry each section hides when its generator gives no `replaces` rules
local DEFAULT_REPLACES = {
	Body = {
		{ r15 = "UpperTorso" }, { r15 = "LowerTorso" }, { r15 = "LeftUpperArm" }, { r15 = "RightUpperArm" },
		{ r15 = "LeftLowerArm" }, { r15 = "RightLowerArm" }, { r15 = "LeftUpperLeg" }, { r15 = "RightUpperLeg" },
		{ r15 = "LeftLowerLeg" }, { r15 = "RightLowerLeg" }, { folder = "Muscles" },
	},
	Head = {
		{ r15 = "Head" },
		{ folder = "Face", names = {
			"Ear", "EarHelix", "Cauliflower", "Jaw", "JawAngle", "Chin", "LowerFace", "ChinCleft", "Jowl", "DoubleChin",
			"Cheekbone", "Cheek", "Hollow", "BrowRidge", "Nose", "NoseTip", "Nostril", "NoseBump", "Nasolabial", "Philtrum",
			"LipFold", "Freckle", "Mole", "Scar", "AcneScar", "Acne", "Birthmark", "BattleScar", "BrowGap", "SurgicalScar",
			"Suture", "ForeheadLine", "CrowFeet", "Pore", "Blush", "Crease", "UnderEye",
		} },
	},
	Hair = { { folder = "Hair" } },
}

local started = false
local running = false
local Shared, MeshKit, LookData, Config
local AssetService
local registry = {} -- section -> def
local records = {} -- model -> rec
local cache = {} -- key -> { result, used }
local cacheCount = 0
local api = { state = "unknown", reason = nil, probed = false, textures = true }
local warned = {}
local listeners = { built = {}, restored = {} }
local conns = {}
local workerBusy = false
local lastEval = 0
local localHidden = false

local function log(...)
	if AnatomyClient.Settings.debug then
		print("[Anatomy]", ...)
	end
end

local function warnOnce(key, ...)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Anatomy]", ...)
end

------------------------------------------------------------------------
-- Signals (plain Lua: tables pass through without being copied)
------------------------------------------------------------------------
local function makeSignal(list)
	local sig = {}
	function sig:Connect(fn)
		local entry = { fn = fn }
		table.insert(list, entry)
		return {
			Connected = true,
			Disconnect = function(c)
				c.Connected = false
				local i = table.find(list, entry)
				if i then
					table.remove(list, i)
				end
			end,
		}
	end
	return sig
end
AnatomyClient.OnBuilt = makeSignal(listeners.built) -- fn(model, section, pieces, landmarks)
AnatomyClient.OnRestored = makeSignal(listeners.restored) -- fn(model, section): round-1 look is back

local function fire(list, ...)
	for _, e in ipairs(list) do
		task.spawn(function(...)
			local ok, err = pcall(e.fn, ...)
			if not ok then
				warnOnce("listener" .. tostring(e.fn), "listener error:", err)
			end
		end, ...)
	end
end

------------------------------------------------------------------------
-- Hiding the round-1 geometry (local only, reference counted per section)
------------------------------------------------------------------------
local function hideKind(inst)
	if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Beam") or inst:IsA("ParticleEmitter") or inst:IsA("Trail") then
		return "ltm"
	elseif inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
		return "enabled"
	end
	return nil
end

local function applyHidden(inst, h)
	if h.kind == "ltm" then
		if inst.LocalTransparencyModifier ~= 1 then
			inst.LocalTransparencyModifier = 1
		end
	elseif inst.Enabled then
		inst.Enabled = false
	end
end

local function hideInst(rec, inst, section)
	if inst:GetAttribute("AnatomyKeep") == true then
		return
	end
	local h = rec.hidden[inst]
	if not h then
		local kind = hideKind(inst)
		if not kind then
			return
		end
		h = { kind = kind, sections = {}, n = 0 }
		h.orig = kind == "ltm" and inst.LocalTransparencyModifier or inst.Enabled
		rec.hidden[inst] = h
	end
	if not h.sections[section] then
		h.sections[section] = true
		h.n += 1
	end
	applyHidden(inst, h)
end

local function unhideSection(rec, section)
	for inst, h in pairs(rec.hidden) do
		if h.sections[section] then
			h.sections[section] = nil
			h.n -= 1
			if h.n <= 0 then
				rec.hidden[inst] = nil
				pcall(function()
					if h.kind == "ltm" then
						inst.LocalTransparencyModifier = (type(h.orig) == "number" and h.orig < 1) and h.orig or 0
					else
						inst.Enabled = h.orig ~= false
					end
				end)
			end
		end
	end
end

-- the BoxerLook folder an instance sits in (nil outside BoxerLook) and the R15 part it is, if any
local function folderOf(model, inst)
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		return nil
	end
	local cur = inst
	while cur and cur.Parent ~= look do
		cur = cur.Parent
		if cur == model or cur == nil then
			return nil
		end
	end
	return cur and cur.Name or nil
end

local function ruleMatches(model, rule, inst, folder)
	if rule.r15 or rule.part then
		return inst.Parent == model and inst.Name == (rule.r15 or rule.part)
	elseif rule.tag then
		return CollectionService:HasTag(inst, rule.tag) and inst:IsDescendantOf(model)
	elseif rule.folder then
		if folder ~= rule.folder then
			return false
		end
		if rule.names then
			return table.find(rule.names, inst.Name) ~= nil
		elseif rule.except then
			return table.find(rule.except, inst.Name) == nil
		end
		return true
	end
	return false
end

local function applyRules(rec, section, rules)
	local model = rec.model
	for _, rule in ipairs(rules) do
		if rule.r15 or rule.part then
			local p = model:FindFirstChild(rule.r15 or rule.part)
			if p then
				hideInst(rec, p, section)
				for _, d in ipairs(p:GetChildren()) do
					if d:IsA("Decal") then
						hideInst(rec, d, section) -- face decals and the like ride on the part
					end
				end
			end
		elseif rule.tag then
			for _, inst in ipairs(CollectionService:GetTagged(rule.tag)) do
				if inst:IsDescendantOf(model) then
					hideInst(rec, inst, section)
				end
			end
		elseif rule.folder then
			local look = model:FindFirstChild("BoxerLook")
			local f = look and look:FindFirstChild(rule.folder)
			if f then
				for _, d in ipairs(f:GetDescendants()) do
					if ruleMatches(model, rule, d, rule.folder) then
						hideInst(rec, d, section)
					end
				end
			end
		end
	end
end

-- a part / beam the server just added: hide it if an active section replaces it
local function onDescendantAdded(rec, inst)
	if not hideKind(inst) then
		return
	end
	local folder = folderOf(rec.model, inst)
	for section, st in pairs(rec.sections) do
		if st.rules and st.active then
			for _, rule in ipairs(st.rules) do
				if ruleMatches(rec.model, rule, inst, folder) then
					hideInst(rec, inst, section)
					break
				end
			end
		end
	end
	-- a decal added to a hidden R15 part
	local parent = inst.Parent
	local h = parent and rec.hidden[parent]
	if h and inst:IsA("Decal") then
		for section in pairs(h.sections) do
			hideInst(rec, inst, section)
		end
	end
end

-- the local character's parts get their LocalTransparencyModifier rewritten by the camera's
-- TransparencyController whenever parts are added: re-assert after the camera every frame
local function reassertLocal()
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local rec = char and records[char]
	if not rec then
		return
	end
	for inst, h in pairs(rec.hidden) do
		if h.kind == "ltm" and inst.LocalTransparencyModifier < 1 then
			inst.LocalTransparencyModifier = 1
		end
	end
end

local function updateLocalBinding()
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local rec = char and records[char]
	local want = rec ~= nil and next(rec.hidden) ~= nil
	if want == localHidden then
		return
	end
	localHidden = want
	if want then
		pcall(function()
			RunService:BindToRenderStep("AnatomyLocalHide", Enum.RenderPriority.Camera.Value + 1, reassertLocal)
		end)
	else
		pcall(function()
			RunService:UnbindFromRenderStep("AnatomyLocalHide")
		end)
	end
end

------------------------------------------------------------------------
-- Pieces (MeshParts) on a model
------------------------------------------------------------------------
-- the part a piece is welded to: an R15 part name, or a dotted path from the model ("BoxerLook.Hair.Pivot")
local function resolveAttach(model, attach)
	local cur = model
	for name in string.gmatch(attach, "[^%.]+") do
		cur = cur and cur:FindFirstChild(name)
	end
	if cur and cur:IsA("BasePart") then
		return cur
	end
	return nil
end

local function materialOf(name)
	local ok, m = pcall(function()
		return Enum.Material[name]
	end)
	return ok and m or Enum.Material.SmoothPlastic
end

local function destroyPiece(p)
	if p.ancestry then
		p.ancestry:Disconnect()
		p.ancestry = nil
	end
	if p.part then
		pcall(function()
			p.part:Destroy()
		end)
	end
	if p.em then
		pcall(p.em.Destroy, p.em)
	end
	if p.img then
		pcall(p.img.Destroy, p.img)
	end
	p.part, p.em, p.img = nil, nil, nil
end

local function restoreSection(rec, section, why)
	local st = rec.sections[section]
	if not st then
		return
	end
	if st.job then
		st.job.cancelled = true
	end
	local had = st.active
	unhideSection(rec, section)
	for _, p in pairs(st.pieces or {}) do
		destroyPiece(p)
	end
	rec.sections[section] = nil
	if had then
		log("restored", rec.model.Name, section, why or "")
		fire(listeners.restored, rec.model, section)
	end
	updateLocalBinding()
end

local function restoreAll(rec, why)
	for section in pairs(rec.sections) do
		restoreSection(rec, section, why)
	end
	if rec.folder then
		pcall(function()
			rec.folder:Destroy()
		end)
		rec.folder = nil
	end
end

local function disableEditables(reason)
	if api.state == "disabled" then
		return
	end
	api.state = "disabled"
	api.reason = tostring(reason)
	warnOnce("api", "EditableMesh characters are off for this session (" .. api.reason .. "); every character keeps the part-built look.",
		"Published games need the experience's 'Allow Mesh / Image APIs' setting and an ID-verified creator.")
	for _, rec in pairs(records) do
		restoreAll(rec, "editables disabled")
	end
end

------------------------------------------------------------------------
-- Generation cache (generated MeshKit data; EditableMeshes are always per model)
------------------------------------------------------------------------
local useCounter = 0
local function cacheGet(key)
	local c = cache[key]
	if c then
		useCounter += 1
		c.used = useCounter
		return c.result
	end
	return nil
end

local function cachePut(key, result)
	if not cache[key] then
		cacheCount += 1
	end
	useCounter += 1
	cache[key] = { result = result, used = useCounter }
	while cacheCount > AnatomyClient.Settings.cacheSize do
		local oldKey, oldUse = nil, math.huge
		for k, c in pairs(cache) do
			if c.used < oldUse then
				oldKey, oldUse = k, c.used
			end
		end
		cache[oldKey] = nil
		cacheCount -= 1
	end
end

------------------------------------------------------------------------
-- Building one section of one model (inside the worker thread)
------------------------------------------------------------------------
local sliceStart = 0
local currentJob = nil
local function tick()
	if currentJob and currentJob.cancelled then
		error(CANCEL, 0)
	end
	if os.clock() - sliceStart > AnatomyClient.Settings.frameBudget then
		task.wait()
		sliceStart = os.clock()
		if currentJob and currentJob.cancelled then
			error(CANCEL, 0)
		end
	end
end

local function isCancel(err)
	return type(err) == "string" and err:find(CANCEL, 1, true) ~= nil
end

-- the Editable pipeline works at all here (once per session): one tiny mesh end to end
local function probe()
	if api.probed then
		return api.state ~= "disabled"
	end
	api.probed = true
	local m = MeshKit.New("probe")
	MeshKit.Vertex(m, 0, 0, 0)
	MeshKit.Vertex(m, 0.1, 0, 0)
	MeshKit.Vertex(m, 0, 0.1, 0)
	MeshKit.Vertex(m, 0, 0, 0.1)
	MeshKit.Tri(m, 1, 3, 2)
	MeshKit.Tri(m, 1, 2, 4)
	MeshKit.Tri(m, 1, 4, 3)
	MeshKit.Tri(m, 2, 3, 4)
	MeshKit.ComputeNormals(m, { weld = false })
	local em, err = MeshKit.ToEditableMesh(m, { assetService = AssetService })
	if not em then
		disableEditables(err)
		return false
	end
	local ok, mp = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	pcall(em.Destroy, em)
	if not ok or not mp then
		disableEditables("CreateMeshPartAsync: " .. tostring(mp))
		return false
	end
	mp:Destroy()
	api.state = "ok"
	return true
end

local function rulesFor(def, look, lod, result)
	local rules = {}
	local base = def.replaces
	if type(base) == "function" then
		local ok, r = pcall(base, look, lod)
		base = ok and r or nil
	end
	for _, r in ipairs(type(base) == "table" and base or DEFAULT_REPLACES[def.section] or {}) do
		rules[#rules + 1] = r
	end
	for _, piece in pairs(result.pieces or {}) do
		if type(piece.replaces) == "table" then
			for _, r in ipairs(piece.replaces) do
				rules[#rules + 1] = r
			end
		end
	end
	return rules
end

local function sectionFailed(section, err)
	local def = registry[section]
	if def then
		def.failed = true
	end
	warnOnce("gen" .. section, section .. " generator failed; that section stays part-built this session:", err)
	for _, rec in pairs(records) do
		restoreSection(rec, section, "generator failed")
	end
end

-- MeshPart for one piece (not parented yet); returns piece record or nil, err, fatal
local function makePiece(rec, name, piece, bodyLod)
	local model = rec.model
	local attachName = piece.attach or name
	local attach = resolveAttach(model, attachName)
	if not attach then
		return nil, "attach part " .. attachName .. " missing"
	end
	local mesh = piece.mesh
	local ok, rep = MeshKit.Validate(mesh)
	if not ok then
		return nil, "invalid mesh " .. name .. ": " .. rep.msg, "gen"
	end
	local em, info = MeshKit.ToEditableMesh(mesh, { assetService = AssetService, flipV = AnatomyClient.Settings.flipV })
	if not em then
		return nil, info, "api"
	end
	tick()
	local okMP, mp = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(em), {
			CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	sliceStart = os.clock()
	if not okMP or not mp then
		pcall(em.Destroy, em)
		return nil, "CreateMeshPartAsync: " .. tostring(mp), "api"
	end
	local cx, cy, cz, sx, sy, sz = MeshKit.BoxCenter(mesh)
	mp.Name = "Anatomy" .. name
	mp.Anchored = false
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.Massless = true
	mp.CastShadow = piece.castShadow ~= false
	mp.Material = materialOf(piece.material or "SmoothPlastic")
	local col = piece.color
	mp.Color = type(col) == "table" and Color3.new(col[1], col[2], col[3]) or Color3.new(1, 1, 1)
	mp.Transparency = piece.transparency or 0
	mp.Reflectance = piece.reflectance or 0
	if piece.doubleSided then
		pcall(function()
			mp.DoubleSided = true
		end)
	end
	-- a MeshPart is centred on its mesh's bounding box: the weld puts that centre where it sits in the
	-- attach part's space
	local centre = AnatomyClient.Settings.meshCentered and CFrame.new(cx, cy, cz) or CFrame.identity
	local pr = { name = name, attach = attachName, attachPart = attach, part = mp, em = em, info = info, mesh = mesh,
		centre = centre, size = Vector3.new(sx, sy, sz), lod = bodyLod, bounds = { MeshKit.Bounds(mesh) } }
	-- colour texture
	local tex = piece.texture
	if tex and AnatomyClient.Settings.textures and api.textures then
		local w, h = tex.w or (tex.size and tex.size[1]) or 256, tex.h or (tex.size and tex.size[2]) or 256
		local buf = tex.buffer
		if not buf then
			local okR, res = pcall(MeshKit.RasterizeUV, mesh, w, h, tex.shade, { pad = tex.pad })
			if not okR then
				if isCancel(res) then
					destroyPiece(pr)
					error(res, 0)
				end
				warnOnce("tex" .. name, "texture for " .. name .. " failed:", res)
			else
				buf = res
			end
		end
		if buf then
			local img, err = MeshKit.ToEditableImage(w, h, buf, { assetService = AssetService })
			if img then
				pr.img = img
				local okT = pcall(function()
					mp.TextureContent = Content.fromObject(img)
				end)
				if not okT then
					pcall(img.Destroy, img)
					pr.img = nil
				end
			else
				-- textures are optional: keep the vertex colours, stop asking for images
				api.textures = false
				warnOnce("teximg", "EditableImage textures are off for this session:", err)
			end
		end
	end
	return pr
end

local function attachPiece(rec, pr)
	local attach = pr.attachPart
	local mp = pr.part
	mp.CFrame = attach.CFrame * pr.centre
	local weld = Instance.new("Weld")
	weld.Name = "AnatomyWeld"
	weld.Part0 = attach
	weld.Part1 = mp
	weld.C0 = pr.centre
	weld.C1 = CFrame.identity
	weld.Parent = mp
	pr.weld = weld
	-- the server replaced this part (head swap, respawned limb): re-attach on the next maintenance pass
	pr.ancestry = attach.AncestryChanged:Connect(function()
		lastEval = 0
	end)
	if not rec.folder or rec.folder.Parent ~= rec.model then
		local f = Instance.new("Folder")
		f.Name = "Anatomy"
		f.Parent = rec.model
		rec.folder = f
	end
	mp.Parent = rec.folder
end

local function landmarksOf(result, section)
	local out = {}
	for name, piece in pairs(result.pieces or {}) do
		local lm = piece.mesh and piece.mesh.landmarks
		if lm then
			for k, p in pairs(lm) do
				out[k] = { section = section, part = piece.attach or name, pos = p }
			end
		end
	end
	for k, v in pairs(result.landmarks or {}) do
		if type(v) == "table" then
			if v.pos then
				out[k] = { section = section, part = v.part or "Head", pos = v.pos }
			elseif type(v[1]) == "number" then
				out[k] = { section = section, part = "Head", pos = v }
			end
		end
	end
	return out
end

local function runJob(job)
	local rec, section, lod = job.rec, job.section, job.lod
	local def = registry[section]
	if not def or def.failed or api.state == "disabled" then
		return
	end
	if not probe() then
		return
	end
	local model = rec.model
	local look = rec.look
	if not look or not model.Parent then
		return
	end
	local t0 = os.clock()
	sliceStart = os.clock()
	currentJob = job
	MeshKit.SetTick(tick)
	-- 1) generate (or reuse)
	local key = section .. "|" .. tostring(job.sig) .. "|" .. lod
	local result = cacheGet(key)
	if not result then
		local budget = Config.Anatomy and Config.Anatomy.tris and Config.Anatomy.tris[section] and Config.Anatomy.tris[section][lod]
		local ctx = { section = section, lod = lod, tick = tick, budget = budget, settings = AnatomyClient.Settings }
		local ok, res = pcall(def.generate, look, lod, ctx)
		if not ok then
			MeshKit.SetTick(nil)
			currentJob = nil
			if isCancel(res) then
				return
			end
			sectionFailed(section, res)
			return
		end
		if type(res) ~= "table" or type(res.pieces) ~= "table" then
			MeshKit.SetTick(nil)
			currentJob = nil
			sectionFailed(section, "generate() must return { pieces = {...}, landmarks = {...} }")
			return
		end
		result = res
		local tris = 0
		for _, piece in pairs(result.pieces) do
			tris += piece.mesh and piece.mesh.nt or 0
		end
		if budget and tris > budget * 1.1 then
			warnOnce("budget" .. section .. lod, string.format("%s %s meshes use %d triangles (budget %d)", section, lod, tris, budget))
		end
		cachePut(key, result)
	end
	-- 2) MeshParts (unparented until every piece exists)
	local made = {}
	local function abandon()
		for _, pr in pairs(made) do
			destroyPiece(pr)
		end
		MeshKit.SetTick(nil)
		currentJob = nil
	end
	local names = {}
	for name in pairs(result.pieces) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local okP, pr, err, kind = pcall(makePiece, rec, name, result.pieces[name], lod)
		if not okP then
			abandon()
			if isCancel(pr) then
				return
			end
			sectionFailed(section, pr)
			return
		end
		if not pr then
			abandon()
			if kind == "api" then
				disableEditables(err)
			elseif kind == "gen" then
				sectionFailed(section, err)
			else
				log("skip", model.Name, section, err)
				job.retry = true
			end
			return
		end
		made[name] = pr
		if job.cancelled then
			abandon()
			return
		end
	end
	MeshKit.SetTick(nil)
	currentJob = nil
	-- 3) swap in atomically: same-named pieces take the new geometry in place (ApplyMesh)
	if job.cancelled or not model.Parent or rec.dead then
		abandon()
		return
	end
	local st = rec.sections[section] or { pieces = {} }
	local old = st.pieces or {}
	local pieces = {}
	for name, pr in pairs(made) do
		local prev = old[name]
		local swapped = false
		if prev and prev.part and prev.part.Parent and prev.attachPart == pr.attachPart then
			swapped = pcall(function()
				local a, b = prev.part, pr.part
				a:ApplyMesh(b)
				a.Size = b.Size
				a.TextureContent = b.TextureContent
				a.Material, a.Color, a.Transparency, a.Reflectance, a.CastShadow = b.Material, b.Color, b.Transparency, b.Reflectance, b.CastShadow
				a.DoubleSided = b.DoubleSided
				prev.weld.C0 = pr.centre
			end)
		end
		if swapped then
			local keepPart, keepWeld, keepConn = prev.part, prev.weld, prev.ancestry
			pcall(prev.em.Destroy, prev.em)
			if prev.img then
				pcall(prev.img.Destroy, prev.img)
			end
			pr.part:Destroy()
			pr.part, pr.weld, pr.ancestry = keepPart, keepWeld, keepConn
			old[name] = nil
		else
			attachPiece(rec, pr)
		end
		pieces[name] = pr
	end
	for _, prev in pairs(old) do
		destroyPiece(prev)
	end
	-- 4) hide what the new meshes replace (and stop hiding what they no longer replace)
	unhideSection(rec, section)
	st.pieces = pieces
	st.sig, st.lod, st.active = job.sig, lod, true
	st.rules = rulesFor(def, look, lod, result)
	st.landmarks = landmarksOf(result, section)
	st.builtAt = os.clock()
	st.job = nil
	rec.sections[section] = st
	applyRules(rec, section, st.rules)
	updateLocalBinding()
	log(string.format("built %s %s %s in %.0f ms", model.Name, section, lod, (os.clock() - t0) * 1000))
	local view = AnatomyClient.GetPieces(model, section)
	fire(listeners.built, model, section, view, st.landmarks)
end

------------------------------------------------------------------------
-- Scheduling
------------------------------------------------------------------------
local function rootPos(model)
	local p = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model.PrimaryPart
	if p and p:IsA("BasePart") then
		return p.Position
	end
	local ok, cf = pcall(model.GetPivot, model)
	return ok and cf.Position or nil
end

local function isOpponent(model)
	local lp = Players.LocalPlayer
	return lp ~= nil and lp:GetAttribute("InFight") == true and CollectionService:HasTag(model, "Fighter") and lp.Character ~= model
end

-- decide every model's level of detail and queue the sections that need (re)building
local function evaluate()
	if api.state == "disabled" or not running then
		return
	end
	local S = AnatomyClient.Settings
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local lp = Players.LocalPlayer
	local list = {}
	for model, rec in pairs(records) do
		if rec.look and not rec.dead then
			local pos = rootPos(model)
			rec.dist = pos and (pos - camPos).Magnitude or math.huge
			if lp and lp.Character == model then
				rec.priority = 0
			elseif isOpponent(model) or CollectionService:HasTag(model, "Preview") then
				rec.priority = 1
			else
				rec.priority = 2
			end
			list[#list + 1] = rec
		end
	end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.dist < b.dist
	end)
	local fulls = 0
	local now = os.clock()
	for _, rec in ipairs(list) do
		local want
		if not S.enabled then
			want = nil
		elseif rec.priority <= 1 then
			want = "full"
		elseif rec.dist <= S.fullRange and fulls < S.maxFull then
			want = "full"
			fulls += 1
		elseif rec.dist <= S.fullRange * 1.6 then
			want = "medium"
		elseif rec.dist <= S.lodRange then
			want = "low"
		end
		-- hysteresis: keep the current level for holdTime unless the model left range entirely
		if rec.lod and want ~= rec.lod and want ~= nil and now - (rec.lodAt or 0) < S.holdTime then
			want = rec.lod
		end
		if want ~= rec.lod then
			rec.lod = want
			rec.lodAt = now
		end
		for section, def in pairs(registry) do
			local st = rec.sections[section]
			if def.failed or not want or (def.lods and not def.lods[want]) then
				if st then
					restoreSection(rec, section, want and "lod unsupported" or "out of range")
				end
			else
				local sig = rec.sigs[section]
				local busy = st and st.job and not st.job.cancelled
				local fresh = st and st.active and st.sig == sig and st.lod == want
				if not fresh and not (busy and st.job.sig == sig and st.job.lod == want) then
					if busy then
						st.job.cancelled = true
					end
					rec.sections[section] = st or { pieces = {} }
					rec.sections[section].job = { rec = rec, section = section, lod = want, sig = sig, look = rec.look, queued = now }
				end
			end
		end
	end
end

-- next job: best priority, then nearest, then section order
local function nextJob()
	local best, bestKey
	for _, rec in pairs(records) do
		if not rec.dead then
			for section, st in pairs(rec.sections) do
				local job = st.job
				if job and not job.cancelled and not job.running and os.clock() - (job.retryAt or -10) >= 2 then
					local k = (rec.priority or 2) * 1e6 + math.min(rec.dist or 1e5, 99999) * 10 + (SECTION_ORDER[section] or 5)
					if not bestKey or k < bestKey then
						best, bestKey = job, k
					end
				end
			end
		end
	end
	return best
end

local function worker()
	while running do
		local job = (api.state ~= "disabled") and nextJob() or nil
		if not job then
			task.wait(0.15)
		else
			job.running = true
			workerBusy = true
			local ok, err = pcall(runJob, job)
			workerBusy = false
			MeshKit.SetTick(nil)
			currentJob = nil
			if not ok and not isCancel(err) then
				warnOnce("job" .. tostring(err), "build error:", err)
			end
			local st = job.rec.sections[job.section]
			if st and st.job == job then
				if job.retry and not job.cancelled then
					job.running = false
					job.retry = nil
					job.retryAt = os.clock()
					job.retries = (job.retries or 0) + 1
					if job.retries > 5 then
						st.job = nil
					end
				else
					st.job = nil
				end
			end
			task.wait()
		end
	end
end

------------------------------------------------------------------------
-- Tracking models
------------------------------------------------------------------------
local function readLook(rec)
	local look = LookData.Get(rec.model)
	if not look then
		rec.look = nil
		return
	end
	rec.look = look
	rec.sigs = LookData.Sigs(look)
end

local function untrack(model)
	local rec = records[model]
	if not rec then
		return
	end
	rec.dead = true
	restoreAll(rec, "untracked")
	for _, c in ipairs(rec.conns) do
		c:Disconnect()
	end
	records[model] = nil
	updateLocalBinding()
end

local function track(model)
	if not started or records[model] or not model:IsA("Model") then
		return
	end
	if model:GetAttribute(LookData.ATTR) == nil and not CollectionService:HasTag(model, LookData.TAG) then
		-- a tagged rig without a look yet: wait for one
		local c
		c = model:GetAttributeChangedSignal(LookData.ATTR):Connect(function()
			c:Disconnect()
			track(model)
		end)
		return
	end
	local rec = { model = model, sections = {}, hidden = {}, conns = {}, sigs = {}, priority = 2, dist = math.huge }
	records[model] = rec
	readLook(rec)
	table.insert(rec.conns, model:GetAttributeChangedSignal(LookData.ATTR):Connect(function()
		readLook(rec)
		lastEval = 0 -- re-evaluate on the next heartbeat
	end))
	table.insert(rec.conns, model.DescendantAdded:Connect(function(inst)
		if next(rec.hidden) ~= nil or next(rec.sections) ~= nil then
			onDescendantAdded(rec, inst)
		end
	end))
	table.insert(rec.conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			untrack(model)
		end
	end))
	table.insert(rec.conns, model.Destroying:Connect(function()
		untrack(model)
	end))
	lastEval = 0
end

-- welds whose attach part was replaced (head swap, respawned limb): re-attach to the new part
local function maintain()
	for model, rec in pairs(records) do
		for _, st in pairs(rec.sections) do
			for _, pr in pairs(st.pieces or {}) do
				if pr.part and pr.weld and (pr.weld.Part0 == nil or not pr.weld.Part0:IsDescendantOf(model)) then
					local p = resolveAttach(model, pr.attach)
					if p then
						if pr.ancestry then
							pr.ancestry:Disconnect()
						end
						pr.attachPart = p
						pr.part.CFrame = p.CFrame * pr.centre
						pr.weld.Part0 = p
						pr.ancestry = p.AncestryChanged:Connect(function()
							lastEval = 0
						end)
					end
				end
			end
		end
	end
end

local function heartbeat()
	local now = os.clock()
	if now - lastEval < 0.5 then
		return
	end
	lastEval = now
	local ok, err = pcall(evaluate)
	if not ok then
		warnOnce("eval", "scheduler error:", err)
	end
	pcall(maintain)
end

------------------------------------------------------------------------
-- Generators
------------------------------------------------------------------------
-- def = { generate = fn(look, lod, ctx) -> { pieces, landmarks }, replaces = rules | fn(look, lod),
--         lods = { full = true, medium = true, low = true } (optional) }
function AnatomyClient.Register(section, def)
	if type(section) ~= "string" or type(def) ~= "table" or type(def.generate) ~= "function" then
		warn("[Anatomy] Register(section, { generate = fn }) expected")
		return false
	end
	def.section = section
	def.failed = false
	registry[section] = def
	for _, rec in pairs(records) do
		if rec.sections[section] then
			restoreSection(rec, section, "re-registered")
		end
	end
	lastEval = 0
	task.defer(AnatomyClient.Start)
	return true
end

local function findGenerators()
	for modName, section in pairs(GENERATORS) do
		local ms = Shared and Shared:FindFirstChild(modName)
		if ms and ms:IsA("ModuleScript") and not registry[section] then
			local ok, mod = pcall(require, ms)
			if ok and type(mod) == "table" and type(mod.Generate) == "function" then
				AnatomyClient.Register(mod.Section or section, {
					generate = mod.Generate, replaces = mod.Replaces, lods = mod.LODs, module = modName,
				})
				log("registered", modName)
			elseif not ok then
				warnOnce("req" .. modName, modName .. " failed to load:", mod)
			end
		end
	end
end

------------------------------------------------------------------------
-- Start / stop
------------------------------------------------------------------------
local function boot()
	local ok, err = pcall(function()
		Shared = ReplicatedStorage:WaitForChild("Shared", 30)
		MeshKit = require(Shared:WaitForChild("MeshKit", 30))
		LookData = require(Shared:WaitForChild("LookData", 30))
		Config = require(Shared:WaitForChild("Config", 30))
		AssetService = game:GetService("AssetService")
	end)
	if not ok or not MeshKit or not LookData then
		warnOnce("start", "not started:", err)
		return
	end
	-- Config.Anatomy defaults under any setting a caller already changed
	local defaults = {
		enabled = true, maxFull = 6, fullRange = 70, lodRange = 160, frameBudget = 0.0025, textures = true,
		meshCentered = true, flipV = false, cacheSize = 12, holdTime = 4, debug = false,
	}
	local cfg = Config and Config.Anatomy or {}
	for k, v in pairs(cfg) do
		if defaults[k] ~= nil and AnatomyClient.Settings[k] == defaults[k] then
			AnatomyClient.Settings[k] = v
		end
	end
	findGenerators()
	if next(registry) == nil then
		-- nothing to build: register nothing, change nothing (Register() later starts the machinery)
		log("no generators registered")
	end
	running = true
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
	for _, tag in ipairs(TRACK_TAGS) do
		table.insert(conns, CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("Model") then
				track(inst)
			end
		end))
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("Model") then
				track(inst)
			end
		end
	end
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(LookData.TAG):Connect(function(inst)
		if records[inst] and not inst:GetAttribute(LookData.ATTR) then
			untrack(inst)
		end
	end))
	local function watchPlayer(plr)
		table.insert(conns, plr.CharacterAdded:Connect(track))
		if plr.Character then
			track(plr.Character)
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayer(plr)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watchPlayer))
	task.spawn(worker)
end

-- idempotent; never yields (the module waits for its shared modules in its own thread). Client only.
function AnatomyClient.Start()
	if started then
		return true
	end
	if not RunService:IsClient() then
		return false
	end
	started = true
	task.spawn(boot)
	return true
end

-- stop building and restore every character (settings toggle / tests)
function AnatomyClient.Stop()
	running = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	conns = {}
	for model in pairs(records) do
		untrack(model)
	end
	started = false
end

function AnatomyClient.SetEnabled(on)
	AnatomyClient.Settings.enabled = on and true or false
	lastEval = 0
	if not on then
		for _, rec in pairs(records) do
			restoreAll(rec, "disabled by setting")
		end
	end
end

local function ensureStarted()
	if not started then
		task.defer(AnatomyClient.Start)
	end
end

------------------------------------------------------------------------
-- Public read / deform API (other client modules: FaceFX, HairFX, BodyFX, the Creator)
------------------------------------------------------------------------
-- true when meshes can be (or are being) built this session
function AnatomyClient.Enabled()
	ensureStarted()
	return running and api.state ~= "disabled" and AnatomyClient.Settings.enabled and next(registry) ~= nil
end

-- { [pieceName] = { part = MeshPart, attach = part name / path, mesh = MeshKit data (read-only),
--   groups = mesh.groups, lod } } or nil when the section is not built on this model
function AnatomyClient.GetPieces(model, section)
	ensureStarted()
	local rec = records[model]
	local st = rec and rec.sections[section]
	if not (st and st.active) then
		return nil
	end
	local out = {}
	for name, pr in pairs(st.pieces) do
		out[name] = { part = pr.part, attach = pr.attach, mesh = pr.mesh, groups = pr.mesh.groups, lod = pr.lod }
	end
	return out
end

-- { [landmark] = { section, part = attach part name / path, pos = { x, y, z } (part-local) } }
function AnatomyClient.GetLandmarks(model)
	ensureStarted()
	local rec = records[model]
	local out = {}
	if rec then
		for _, st in pairs(rec.sections) do
			if st.active and st.landmarks then
				for k, v in pairs(st.landmarks) do
					out[k] = v
				end
			end
		end
	end
	return out
end

-- world position of a landmark (nil when unknown)
function AnatomyClient.GetLandmarkWorld(model, name)
	local lm = AnatomyClient.GetLandmarks(model)[name]
	local part = lm and resolveAttach(model, lm.part)
	if not part then
		return nil
	end
	return part.CFrame:PointToWorldSpace(Vector3.new(lm.pos[1], lm.pos[2], lm.pos[3]))
end

local function pieceRec(model, section, piece)
	local rec = records[model]
	local st = rec and rec.sections[section]
	local pr = st and st.active and st.pieces[piece]
	if pr and pr.em then
		return pr
	end
	return nil
end

-- low-rate deformation (expressions, flex): vertex ids (MeshKit indices, e.g. from mesh.groups) move by
-- offsets (Vector3, piece-local studs) from their generated position. Clamped to the generated bounding
-- box so the MeshPart's size never has to change. Returns true when applied.
function AnatomyClient.SetVertexOffsets(model, section, piece, ids, offsets)
	ensureStarted()
	local pr = pieceRec(model, section, piece)
	if not pr or type(ids) ~= "table" or type(offsets) ~= "table" then
		return false
	end
	local P = pr.mesh.P
	local b = pr.bounds
	local x0, y0, z0, x1, y1, z1 = b[1], b[2], b[3], b[4], b[5], b[6]
	local vid = pr.info.vid
	local em = pr.em
	local ok = pcall(function()
		for k, i in ipairs(ids) do
			local o = offsets[k]
			local id = vid[i]
			if id and o then
				local x = math.clamp(P[i * 3 - 2] + o.X, x0, x1)
				local y = math.clamp(P[i * 3 - 1] + o.Y, y0, y1)
				local z = math.clamp(P[i * 3] + o.Z, z0, z1)
				em:SetPosition(id, Vector3.new(x, y, z))
			end
		end
	end)
	return ok
end

-- back to the generated shape (all vertices, or just ids)
function AnatomyClient.ResetVertexOffsets(model, section, piece, ids)
	local pr = pieceRec(model, section, piece)
	if not pr then
		return false
	end
	return (MeshKit.UpdatePositions(pr.em, pr.info, pr.mesh, ids))
end

-- low-rate recolouring (bruises, flush, sweat darkening): colors[k] = Color3 or { r, g, b [, a] }
function AnatomyClient.SetVertexColors(model, section, piece, ids, colors)
	ensureStarted()
	local pr = pieceRec(model, section, piece)
	if not pr or not pr.info.cid or type(ids) ~= "table" then
		return false
	end
	local cid, em = pr.info.cid, pr.em
	return (pcall(function()
		for k, i in ipairs(ids) do
			local c = colors[k]
			local id = cid[i]
			if id and c then
				if typeof(c) == "Color3" then
					em:SetColor(id, c)
				else
					em:SetColor(id, Color3.new(c[1], c[2], c[3]))
					if c[4] then
						em:SetColorAlpha(id, c[4])
					end
				end
			end
		end
	end))
end

-- force a rebuild of one model (all sections) on the next evaluation
function AnatomyClient.Rebuild(model)
	ensureStarted()
	local rec = records[model]
	if rec then
		readLook(rec)
		for _, st in pairs(rec.sections) do
			st.sig = nil
		end
		lastEval = 0
	end
end

-- counters for tools and tests
function AnatomyClient.Status()
	local s = { started = started, running = running, api = api.state, reason = api.reason, textures = api.textures,
		sections = {}, models = 0, built = { full = 0, medium = 0, low = 0 }, hidden = 0, queued = 0, busy = workerBusy, cache = cacheCount }
	for name, def in pairs(registry) do
		s.sections[name] = def.failed and "failed" or "ok"
	end
	for _, rec in pairs(records) do
		s.models += 1
		for _ in pairs(rec.hidden) do
			s.hidden += 1
		end
		for _, st in pairs(rec.sections) do
			if st.active and st.lod then
				s.built[st.lod] = (s.built[st.lod] or 0) + 1
			end
			if st.job and not st.job.cancelled then
				s.queued += 1
			end
		end
	end
	return s
end

return AnatomyClient
