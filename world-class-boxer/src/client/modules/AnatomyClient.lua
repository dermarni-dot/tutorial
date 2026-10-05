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
--   a rebuild builds the new MeshParts first and swaps them in within one frame (no flicker)
-- * level of detail: full for the local player, the fight opponent and the Config.Anatomy.maxFull
--   nearest within fullRange; medium / low further out; round-1 parts beyond lodRange
-- * one serial worker, time-sliced (Config.Anatomy.frameBudget per frame through MeshKit's tick), so
--   building never hitches; cancelled when the model goes away or its look changes again
-- * the Editable API not working at all (not enabled for the experience, unverified creator: the
--   one-time probe fails) disables meshes for the session, restores every character and warns once;
--   a creation failing later (the per-device memory budget) only lowers how much is built: a cap on
--   the estimated Editable memory, the farthest characters back to round-1 parts, a cool-down, and
--   only after repeated failures the session switch-off; a generator error disables that section only
-- Start: AnatomyClient.Start() (idempotent, client only). Any other public call starts it too, so the
-- first module that touches it (ClientMain, FaceFX, the Creator) brings it up. Settings: SetEnabled(on),
-- SetDetail("full" | "medium" | "low" | "auto"), the Settings table. FX modules: OnBuilt / OnRestored,
-- GetPieces, GetLandmarks / GetLandmarkWorld, SetMorphs (blend shapes), SetVertexOffsets / SetVertexColors,
-- SetPieceTransform (rigid lids / jaw / hair clumps), IsReplaced (leave hidden round-1 parts alone).
-- ANATOMY_CONTRACTS.md has the generator contract (piece / landmark / morph / replace rule shapes,
-- budgets, coordinate conventions).
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
	cacheSize = 24, -- generated sections kept for re-use (NPCs walking back into range, LOD flips)
	cacheMB = 32, -- ... and at most this much Lua memory of mesh data (estimate) in that cache
	promoteHold = 1.5, -- seconds a model must want a higher level of detail before it is rebuilt
	demoteHold = 12, -- ... and a lower one (or out of range): lowering only saves memory, so it waits
	debug = false,
}

-- the module's own values (Start() puts Config.Anatomy over every setting still equal to these)
local DEFAULTS = table.clone(AnatomyClient.Settings)

local TRACK_TAGS = { "Anatomy", "Fighter", "Trainee", "Ambient", "Referee", "Preview" }
local SECTION_ORDER = { Body = 1, Head = 2, Hair = 3 }
local GENERATORS = { AnatomyBody = "Body", AnatomyHead = "Head", AnatomyHair = "Hair" }
local LOD_RANK = { full = 3, medium = 2, low = 1 }
-- raised through MeshKit's tick to abandon a build (printable: it shows up in logs as a caught error)
local CANCEL = "[AnatomyClient: build cancelled]"

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
local workerGen = 0 -- a Stop() + Start() never leaves two workers running
local lastEval = 0
local localHidden = false
local userSet = {} -- Settings keys SetDetail forced (Config.Anatomy does not overwrite them at boot)
-- Editable memory pressure: the budget per device is not documented, so a creation failure after a
-- working probe sets a cap on the estimated live Editable bytes (85 % of what was alive then), sheds
-- the lowest-priority characters to fit and pauses building for a few seconds. MAX_PRESSURE failures
-- (or one with nothing alive) switch meshes off for the session.
local pressure = { cap = math.huge, fails = 0, untilT = 0 }
local MAX_PRESSURE = 4
local PRESSURE_COOLDOWN = 6
-- rough EditableMesh / EditableImage memory per element (bytes): only ratios matter (the cap is set
-- from the same estimate)
local BYTES_PER_VERT, BYTES_PER_TRI = 64, 48

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

-- a part matched by a rule with guis = true takes its Surface / BillboardGuis with it (text patches: the part
-- itself is invisible, its gui is what shows)
local function hideMatched(rec, rule, inst, section)
	hideInst(rec, inst, section)
	if rule.guis and inst:IsA("BasePart") then
		local h = rec.hidden[inst]
		if h then
			h.guis = true
		end
		for _, g in ipairs(inst:GetChildren()) do
			if g:IsA("SurfaceGui") or g:IsA("BillboardGui") then
				hideInst(rec, g, section)
			end
		end
	end
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
						hideMatched(rec, rule, d, section)
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
					hideMatched(rec, rule, inst, section)
					break
				end
			end
		end
	end
	-- a decal added to a hidden R15 part, a gui added to a part hidden with its guis
	local parent = inst.Parent
	local h = parent and rec.hidden[parent]
	if h and (inst:IsA("Decal") or (h.guis and (inst:IsA("SurfaceGui") or inst:IsA("BillboardGui")))) then
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
	for part in pairs(rec.covered) do
		if part.Parent == nil then
			rec.covered[part] = nil
		elseif part.LocalTransparencyModifier < 1 then
			part.LocalTransparencyModifier = 1
		end
	end
end

local function updateLocalBinding()
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local rec = char and records[char]
	local want = rec ~= nil and (next(rec.hidden) ~= nil or next(rec.covered) ~= nil)
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
-- headgear / robe hood: Builder sets HairHiddenHeadgear / HairHiddenHood on the model (BuilderHair.SetHairHidden).
-- Pieces with hideUnder (default: every Hair piece) are hidden locally while the matching one is on.
local COVER_DEFAULT = { headgear = true, hood = true }
local function applyCovers(rec)
	local model = rec.model
	local hg = model:GetAttribute("HairHiddenHeadgear") == true
	local hood = model:GetAttribute("HairHiddenHood") == true
	for section, st in pairs(rec.sections) do
		for _, pr in pairs(st.pieces or {}) do
			local part = pr.part
			if part then
				local rule = pr.hideUnder
				if rule == nil and section == "Hair" then
					rule = COVER_DEFAULT
				end
				local hide = type(rule) == "table" and ((hg and rule.headgear ~= false) or (hood and rule.hood ~= false))
				if hide then
					rec.covered[part] = true
					part.LocalTransparencyModifier = 1
				elseif rec.covered[part] then
					rec.covered[part] = nil
					part.LocalTransparencyModifier = 0
				end
			end
		end
	end
	for part in pairs(rec.covered) do
		if part.Parent == nil then
			rec.covered[part] = nil
		end
	end
	updateLocalBinding()
end

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

-- Lua heap a generated result holds (16 bytes per array slot: P N C 3 each, U 2, A / W 1, T 3 per triangle)
local function resultBytes(result)
	local n = 0
	for _, piece in pairs(result.pieces or {}) do
		local m = piece.mesh
		if type(m) == "table" and m.nv then
			n += (m.nv * 12 + m.nt * 3) * 16
		end
	end
	return n
end

local cacheBytes = 0
local function cachePut(key, result)
	local old = cache[key]
	if old then
		cacheBytes -= old.bytes
	else
		cacheCount += 1
	end
	useCounter += 1
	local bytes = resultBytes(result)
	cache[key] = { result = result, used = useCounter, bytes = bytes }
	cacheBytes += bytes
	local S = AnatomyClient.Settings
	while cacheCount > 1 and (cacheCount > S.cacheSize or cacheBytes > (S.cacheMB or 32) * 1048576) do
		local oldKey, oldUse = nil, math.huge
		for k, c in pairs(cache) do
			if c.used < oldUse and k ~= key then
				oldKey, oldUse = k, c.used
			end
		end
		if not oldKey then
			break
		end
		cacheBytes -= cache[oldKey].bytes
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
	for _, r in ipairs(type(base) == "table" and base or LookData.DEFAULT_REPLACES[def.section] or {}) do
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
local makePiece
function makePiece(rec, name, piece, bodyLod)
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
	-- the colour texture first: when it exists the mesh is written WITHOUT vertex colours (the texture,
	-- rasterised from them, carries the colour), so the look never depends on how the engine combines the
	-- two; when it cannot be made the mesh keeps its vertex colours
	local img
	local texBytes = 0
	local tex = piece.texture
	if tex and AnatomyClient.Settings.textures and api.textures then
		local w, h = tex.w or (tex.size and tex.size[1]) or 256, tex.h or (tex.size and tex.size[2]) or 256
		local buf = tex.buffer
		if not buf then
			local okR, res = pcall(MeshKit.RasterizeUV, mesh, w, h, tex.shade, { pad = tex.pad })
			if not okR then
				if isCancel(res) then
					error(res, 0)
				end
				warnOnce("tex" .. name, "texture for " .. name .. " failed:", res)
			else
				buf = res
			end
		end
		if buf then
			local im, err = MeshKit.ToEditableImage(w, h, buf, { assetService = AssetService })
			if im then
				img = im
				texBytes = w * h * 4
			else
				-- textures are optional: keep the vertex colours, stop asking for images this session
				api.textures = false
				warnOnce("teximg", "EditableImage textures are off for this session:", err)
			end
		end
	end
	local em, info = MeshKit.ToEditableMesh(mesh, { assetService = AssetService, flipV = AnatomyClient.Settings.flipV, noColors = img ~= nil })
	if not em then
		if img then
			pcall(img.Destroy, img)
		end
		-- the writer's own pcall also catches a cancellation raised by the tick inside it: not an API fault
		if isCancel(info) then
			error(CANCEL, 0)
		end
		return nil, info, "api"
	end
	local okMP, mp = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(em), {
			CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	sliceStart = os.clock()
	if not okMP or not mp or (currentJob and currentJob.cancelled) then
		-- (CreateMeshPartAsync yields: the job may have been cancelled meanwhile)
		pcall(em.Destroy, em)
		if img then
			pcall(img.Destroy, img)
		end
		if okMP and mp then
			mp:Destroy()
			error(CANCEL, 0)
		end
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
	if img then
		local okT, errT = pcall(function()
			mp.TextureContent = Content.fromObject(img)
		end)
		if not okT then
			-- the mesh was written without vertex colours (the texture carried them): drop this one and
			-- make the piece again with its vertex colours, textures off for the session
			pcall(img.Destroy, img)
			pcall(em.Destroy, em)
			mp:Destroy()
			api.textures = false
			warnOnce("texset", "TextureContent refused (" .. tostring(errT) .. "): textures are off for this session")
			return makePiece(rec, name, piece, bodyLod)
		end
	end
	-- a MeshPart is centred on its mesh's bounding box: the weld puts that centre where it sits in the
	-- attach part's space
	local centre = AnatomyClient.Settings.meshCentered and CFrame.new(cx, cy, cz) or CFrame.identity
	local cost = mesh.nv * BYTES_PER_VERT + mesh.nt * BYTES_PER_TRI + (img and texBytes or 0)
	local pr = { name = name, attach = attachName, attachPart = attach, part = mp, em = em, info = info, mesh = mesh, img = img,
		centre = centre, size = Vector3.new(sx, sy, sz), lod = bodyLod, bounds = { MeshKit.Bounds(mesh) }, hideUnder = piece.hideUnder,
		cost = cost }
	return pr
end

local function attachPiece(rec, pr)
	local attach = pr.attachPart
	local mp = pr.part
	local c0 = (pr.xform or CFrame.identity) * pr.centre
	mp.CFrame = attach.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Name = "AnatomyWeld"
	weld.Part0 = attach
	weld.Part1 = mp
	weld.C0 = c0
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

-- estimated Editable bytes alive right now (every built piece on every model)
local function liveCost()
	local total = 0
	for _, rec in pairs(records) do
		for _, st in pairs(rec.sections) do
			for _, pr in pairs(st.pieces or {}) do
				total += pr.cost or 0
			end
		end
	end
	return total
end

-- estimated bytes of one section at one level: the cached generation if there is one, else the budget
local function sectionCost(section, sig, lod)
	local c = cache[section .. "|" .. tostring(sig) .. "|" .. lod]
	if c then
		local total = 0
		for _, piece in pairs(c.result.pieces or {}) do
			local m = piece.mesh
			if m then
				total += m.nv * BYTES_PER_VERT + m.nt * BYTES_PER_TRI
			end
		end
		return total
	end
	local tris = Config and Config.Anatomy and Config.Anatomy.tris and Config.Anatomy.tris[section]
	tris = tris and tris[lod] or 5000
	return tris * (0.6 * BYTES_PER_VERT + BYTES_PER_TRI)
end

-- a creation failed although the probe worked: the device's Editable memory is full. Returns true when
-- meshes stay on (with a lower cap), false when they were switched off for the session.
local function onCreateFailed(err)
	pressure.fails += 1
	local live = liveCost()
	if pressure.fails >= MAX_PRESSURE or live <= 0 then
		disableEditables(err)
		return false
	end
	pressure.cap = math.min(pressure.cap, live * 0.85)
	pressure.untilT = os.clock() + PRESSURE_COOLDOWN
	warnOnce("pressure", "Editable memory is full (" .. tostring(err) .. "): fewer / lower-detail mesh characters from now on")
	lastEval = 0
	return true
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
	-- the look this job was queued with: the generation is cached under job.sig, so it must come from
	-- exactly that look even if a newer one arrived meanwhile (the newer one gets its own job)
	local look = job.look
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
				-- retried after the cool-down (at whatever level the lower cap allows)
				if onCreateFailed(err) then
					job.retry = true
				end
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
	-- 3) swap in within this frame: the new MeshParts (welded, parented) replace the old ones, which are
	-- destroyed right after, so the character never shows a gap or a doubled piece. A rigid transform
	-- (SetPieceTransform) carries over to the same-named piece. (No MeshPart:ApplyMesh: whether a part
	-- that took another's mesh stays live-linked to that EditableMesh is not documented.)
	if job.cancelled or not model.Parent or rec.dead then
		abandon()
		return
	end
	local st = rec.sections[section] or { pieces = {} }
	local old = st.pieces or {}
	if next(made) == nil then
		-- the generator drew nothing for this look (e.g. clothes it does not model): keep the round-1
		-- parts, remember the decision so the same look and level are not generated again
		local had = st.active
		unhideSection(rec, section)
		for _, prev in pairs(old) do
			destroyPiece(prev)
		end
		st.pieces, st.rules, st.landmarks = {}, nil, nil
		st.sig, st.lod, st.active, st.skipped, st.job = job.sig, lod, false, true, nil
		rec.sections[section] = st
		applyCovers(rec)
		if had then
			fire(listeners.restored, model, section)
		end
		return
	end
	local pieces = {}
	for name, pr in pairs(made) do
		local prev = old[name]
		if prev and prev.xform then
			pr.xform = prev.xform
		end
		attachPiece(rec, pr)
		pieces[name] = pr
	end
	for _, prev in pairs(old) do
		destroyPiece(prev)
	end
	-- 4) hide what the new meshes replace (and stop hiding what they no longer replace)
	unhideSection(rec, section)
	st.pieces = pieces
	st.sig, st.lod, st.active, st.skipped = job.sig, lod, true, nil
	st.rules = rulesFor(def, look, lod, result)
	st.landmarks = landmarksOf(result, section)
	st.builtAt = os.clock()
	st.job = nil
	rec.sections[section] = st
	applyRules(rec, section, st.rules)
	applyCovers(rec)
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
	if api.state == "disabled" or not running or next(registry) == nil then
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
	local now = os.clock()
	-- levels with hysteresis, so characters walking around do not flip (each flip is a rebuild):
	-- a model already at full keeps it with some slack (rank <= maxFull + 2, 15% past fullRange); new
	-- full slots only fill up to maxFull; the distance bands get +-12% margins around the current level
	local want = {}
	local fullKept = 0
	for _, rec in ipairs(list) do
		if not S.enabled then
			want[rec] = false
		elseif rec.priority <= 1 then
			want[rec] = "full"
		elseif rec.lod == "full" and rec.dist <= S.fullRange * 1.15 and fullKept < S.maxFull + 2 then
			want[rec] = "full"
			fullKept += 1
		end
	end
	local fulls = fullKept
	for _, rec in ipairs(list) do
		if want[rec] == nil then
			local d = rec.dist
			local function band(limit, current)
				return d <= limit * ((rec.lod == current) and 1.12 or 0.88)
			end
			if d <= S.fullRange and fulls < S.maxFull then
				want[rec] = "full"
				fulls += 1
			elseif band(S.fullRange * 1.6, "medium") or (rec.lod == "full" and d <= S.fullRange * 1.6) then
				want[rec] = "medium"
			elseif band(S.lodRange, "low") or ((rec.lod == "full" or rec.lod == "medium") and d <= S.lodRange) then
				want[rec] = "low"
			else
				want[rec] = false
			end
		end
	end
	-- Editable memory cap (after a budget failure): walk the characters in priority order and give each
	-- the best level that still fits; the rest keep their round-1 parts. Applied at once (no hold).
	local forced = {}
	if pressure.cap < math.huge then
		local used = 0
		local LEVELS = { "full", "medium", "low" }
		for _, rec in ipairs(list) do
			local w = want[rec]
			if w then
				local got = false
				for li = LOD_RANK[w] and (4 - LOD_RANK[w]) or 3, 3 do
					local lvl = LEVELS[li]
					local c = 0
					for section, def in pairs(registry) do
						if not def.failed and not (def.lods and not def.lods[lvl]) then
							c += sectionCost(section, rec.sigs[section], lvl)
						end
					end
					if used + c <= pressure.cap then
						used += c
						got = lvl
						break
					end
				end
				if got ~= w then
					want[rec] = got
					if rec.lod and (not got or LOD_RANK[got] < LOD_RANK[rec.lod]) then
						forced[rec] = true
					end
				end
			end
		end
	end
	for _, rec in ipairs(list) do
		local wanted = want[rec] or nil
		-- promotions after promoteHold, demotions (and leaving range) only after demoteHold of wanting
		-- the lower level without a break: camera jumps (menus, training views) never cost a rebuild
		if wanted ~= rec.lod then
			if rec.pendingLod ~= (wanted or "none") then
				rec.pendingLod = wanted or "none"
				rec.pendingAt = now
			end
			local up = rec.lod == nil or (wanted ~= nil and LOD_RANK[wanted] > LOD_RANK[rec.lod])
			local hold = up and S.promoteHold or S.demoteHold
			if rec.lod == nil or forced[rec] or now - rec.pendingAt >= hold then
				rec.lod = wanted
				rec.pendingLod = nil
				if forced[rec] then
					-- over the memory cap: free the old meshes first (a swap would hold old + new at once)
					for section in pairs(rec.sections) do
						restoreSection(rec, section, "memory cap")
					end
				end
			end
		else
			rec.pendingLod = nil
		end
		local want = rec.lod
		for section, def in pairs(registry) do
			local st = rec.sections[section]
			if def.failed or not want or (def.lods and not def.lods[want]) then
				if st then
					restoreSection(rec, section, want and "lod unsupported" or "out of range")
				end
			else
				local sig = rec.sigs[section]
				local busy = st and st.job and not st.job.cancelled
				local fresh = st and (st.active or st.skipped) and st.sig == sig and st.lod == want
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
	if os.clock() < pressure.untilT then
		return nil
	end
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

local function worker(gen)
	-- a previous worker (Stop() then Start()) finishes its cancelled job first: MeshKit's tick is global
	while workerBusy and gen == workerGen do
		task.wait()
	end
	while running and gen == workerGen do
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
		-- the server took the look away (or it no longer decodes): back to the part-built body
		rec.look = nil
		rec.sigs = {}
		restoreAll(rec, "look removed")
		return
	end
	rec.look = look
	rec.sigs = LookData.Sigs(look)
	-- jobs for a section whose inputs changed are stale: drop them now (evaluate queues the new ones)
	for section, st in pairs(rec.sections) do
		if st.job and st.job.sig ~= rec.sigs[section] then
			st.job.cancelled = true
		end
	end
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
	local rec = { model = model, sections = {}, hidden = {}, covered = {}, conns = {}, sigs = {}, priority = 2, dist = math.huge }
	records[model] = rec
	for _, attr in ipairs({ "HairHiddenHeadgear", "HairHiddenHood" }) do
		table.insert(rec.conns, model:GetAttributeChangedSignal(attr):Connect(function()
			applyCovers(rec)
		end))
	end
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

-- welds whose attach part was replaced (head swap, respawned limb): re-attach to the new part; pieces
-- something else destroyed: give the section back to the round-1 parts (and rebuild it); hidden
-- round-1 instances that were destroyed (Builder rebuilds its folders) are forgotten
local function maintain()
	for model, rec in pairs(records) do
		for inst in pairs(rec.hidden) do
			if inst.Parent == nil then
				rec.hidden[inst] = nil
			end
		end
		for section, st in pairs(rec.sections) do
			local lost = false
			for _, pr in pairs(st.pieces or {}) do
				if pr.part and not pr.part:IsDescendantOf(model) then
					lost = true
					break
				end
			end
			if lost then
				restoreSection(rec, section, "piece removed")
				lastEval = 0
				continue
			end
			for _, pr in pairs(st.pieces or {}) do
				if pr.part and pr.weld and (pr.weld.Part0 == nil or not pr.weld.Part0:IsDescendantOf(model)) then
					local p = resolveAttach(model, pr.attach)
					if p then
						if pr.ancestry then
							pr.ancestry:Disconnect()
						end
						pr.attachPart = p
						pr.part.CFrame = p.CFrame * (pr.xform or CFrame.identity) * pr.centre
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
	local cfg = Config and Config.Anatomy or {}
	for k, v in pairs(cfg) do
		if DEFAULTS[k] ~= nil and not userSet[k] and AnatomyClient.Settings[k] == DEFAULTS[k] then
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
	workerGen += 1
	task.spawn(worker, workerGen)
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

local function ensureStarted()
	if not started then
		task.defer(AnatomyClient.Start)
	end
end

-- the graphics setting's master switch (also starts the module: the Settings screen is one way it comes up)
function AnatomyClient.SetEnabled(on)
	ensureStarted()
	AnatomyClient.Settings.enabled = on and true or false
	lastEval = 0
	if not on then
		for _, rec in pairs(records) do
			restoreAll(rec, "disabled by setting")
		end
	end
end

-- graphics detail presets: SetDetail("full" | "medium" | "low") writes these knobs; "auto" (or anything
-- else) puts back Config.Anatomy's values. Takes effect on the next evaluation (a fraction of a second);
-- pieces keep the texture choice they were built with until they are rebuilt.
AnatomyClient.DETAIL = {
	full = { maxFull = 10, fullRange = 90, lodRange = 200, frameBudget = 0.004, textures = true },
	medium = { maxFull = 4, fullRange = 50, lodRange = 120, frameBudget = 0.002, textures = true },
	low = { maxFull = 1, fullRange = 30, lodRange = 80, frameBudget = 0.0015, textures = false },
}
function AnatomyClient.SetDetail(level)
	ensureStarted()
	local preset = AnatomyClient.DETAIL[level]
	local S = AnatomyClient.Settings
	for k in pairs(AnatomyClient.DETAIL.full) do
		local v
		if preset then
			v = preset[k]
		else
			local cfg = Config and Config.Anatomy
			v = cfg and cfg[k]
			if v == nil then
				v = DEFAULTS[k]
			end
		end
		if v ~= nil then
			S[k] = v
		end
		userSet[k] = preset ~= nil or nil
	end
	lastEval = 0
	return true
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
	local rec = records[model]
	local lm
	for _, st in pairs(rec and rec.sections or {}) do
		if st.active and st.landmarks and st.landmarks[name] then
			lm = st.landmarks[name]
			break
		end
	end
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

-- The MeshPart was sized to the generated bounding box. A deformation that moved the box (a vertex past
-- it, or the vertex that defines a face of it moved inward) would change the mesh's bounds and the
-- engine would rescale / recentre the whole piece. So every deformed position is clamped into the box,
-- and the vertices lying ON a face of the box keep that coordinate (pinned per axis): the box never
-- changes. Built once per piece, on the first deformation.
local function pinsOf(pr)
	local pin = pr.pin
	if pin then
		return pin
	end
	local P, b = pr.mesh.P, pr.bounds
	local ex = 1e-6 + 1e-6 * math.max(b[4] - b[1], b[5] - b[2], b[6] - b[3])
	local px, py, pz = {}, {}, {}
	for i = 1, pr.mesh.nv do
		local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
		if x <= b[1] + ex or x >= b[4] - ex then
			px[i] = true
		end
		if y <= b[2] + ex or y >= b[5] - ex then
			py[i] = true
		end
		if z <= b[3] + ex or z >= b[6] - ex then
			pz[i] = true
		end
	end
	pin = { x = px, y = py, z = pz }
	pr.pin = pin
	return pin
end

-- the deformed position of mesh vertex i (offset ox, oy, oz from its generated position), kept in the box
local function boxed(pr, pin, i, ox, oy, oz)
	local P, b = pr.mesh.P, pr.bounds
	local x, y, z = P[i * 3 - 2], P[i * 3 - 1], P[i * 3]
	if not pin.x[i] then
		x = math.clamp(x + ox, b[1], b[4])
	end
	if not pin.y[i] then
		y = math.clamp(y + oy, b[2], b[5])
	end
	if not pin.z[i] then
		z = math.clamp(z + oz, b[3], b[6])
	end
	return Vector3.new(x, y, z)
end

-- low-rate deformation (expressions, flex): vertex ids (MeshKit indices, e.g. from mesh.groups) move by
-- offsets (Vector3, piece-local studs) from their generated position. Kept inside the generated bounding
-- box (pinsOf) so the MeshPart's size and centre never change. Normals stay as generated. Returns true
-- when applied.
function AnatomyClient.SetVertexOffsets(model, section, piece, ids, offsets)
	ensureStarted()
	local pr = pieceRec(model, section, piece)
	if not pr or type(ids) ~= "table" or type(offsets) ~= "table" then
		return false
	end
	local vid = pr.info.vid
	local em = pr.em
	local pin = pinsOf(pr)
	-- these vertices no longer sit where SetMorphs last put them: its next call must write
	pr.morphDirty = true
	local ok = pcall(function()
		for k, i in ipairs(ids) do
			local o = offsets[k]
			local id = vid[i]
			if id and o then
				em:SetPosition(id, boxed(pr, pin, i, o.X, o.Y, o.Z))
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
	pr.morphDirty = true
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

-- expressions / flex as blend shapes: a piece mesh may carry
--   mesh.morphs[name] = { ids = { MeshKit vertex ids }, d = { dx, dy, dz, ... } }  (full-strength offsets,
--   piece-local studs; seam duplicates must be listed with the same delta)
-- SetMorphs sums weight * delta over the named morphs and writes every vertex any morph touches (those
-- whose morphs are all at 0 go back to the generated position). Skips the write when the weights did
-- not change. Cost ~ the touched vertices: call at a low rate (10-20 Hz) and only for near characters.
function AnatomyClient.SetMorphs(model, section, piece, weights)
	ensureStarted()
	local pr = pieceRec(model, section, piece)
	local morphs = pr and pr.mesh.morphs
	if type(morphs) ~= "table" or type(weights) ~= "table" then
		return false
	end
	local ms = pr.morphState
	if not ms then
		-- union of every morph's vertices, a slot per vertex, and reusable accumulators
		local slot, ids = {}, {}
		for _, mo in pairs(morphs) do
			for _, i in ipairs(mo.ids or {}) do
				if not slot[i] then
					ids[#ids + 1] = i
					slot[i] = #ids
				end
			end
		end
		ms = { slot = slot, ids = ids, ox = table.create(#ids, 0), oy = table.create(#ids, 0), oz = table.create(#ids, 0), last = {},
			mark = table.create(#ids, 0), stamp = 0 }
		pr.morphState = ms
	end
	local same = true
	for name, w in pairs(weights) do
		if ms.last[name] ~= w then
			same = false
			break
		end
	end
	for name, w in pairs(ms.last) do
		if weights[name] ~= w then
			same = false
			break
		end
	end
	if same and not pr.morphDirty then
		return true
	end
	-- only the vertices of the blend shapes whose weight moved are rewritten (all of them after offsets
	-- were written elsewhere)
	local all = pr.morphDirty == true
	pr.morphDirty = nil
	ms.stamp += 1
	local stamp, mark = ms.stamp, ms.mark
	for name, mo in pairs(morphs) do
		local w0, w1 = ms.last[name], weights[name]
		w0 = type(w0) == "number" and w0 or 0
		w1 = type(w1) == "number" and w1 or 0
		if (all or w0 ~= w1) and mo.ids then
			for _, i in ipairs(mo.ids) do
				local sl = ms.slot[i]
				if sl then
					mark[sl] = stamp
				end
			end
		end
	end
	table.clear(ms.last)
	local ox, oy, oz, slot = ms.ox, ms.oy, ms.oz, ms.slot
	for k = 1, #ms.ids do
		ox[k], oy[k], oz[k] = 0, 0, 0
	end
	for name, w in pairs(weights) do
		ms.last[name] = w
		local mo = morphs[name]
		if mo and type(w) == "number" and w ~= 0 and mo.ids and mo.d then
			local d = mo.d
			for k, i in ipairs(mo.ids) do
				local sl = slot[i]
				ox[sl] += d[k * 3 - 2] * w
				oy[sl] += d[k * 3 - 1] * w
				oz[sl] += d[k * 3] * w
			end
		end
	end
	local vid, em = pr.info.vid, pr.em
	local pin = pinsOf(pr)
	return (pcall(function()
		for k, i in ipairs(ms.ids) do
			local id = vid[i]
			if id and mark[k] == stamp then
				em:SetPosition(id, boxed(pr, pin, i, ox[k], oy[k], oz[k]))
			end
		end
	end))
end

-- rigid motion of a whole piece (eyelids, jaw, hair clumps, locs): cf is applied to the generated geometry
-- in the attach part's space (CFrame.identity = as built). To swing about a pivot p (part-local):
-- CFrame.new(p) * rotation * CFrame.new(-p). Survives in-place rebuilds; costs one Weld.C0 write.
function AnatomyClient.SetPieceTransform(model, section, piece, cf)
	local rec = records[model]
	local st = rec and rec.sections[section]
	local pr = st and st.active and st.pieces[piece]
	if not (pr and pr.weld and typeof(cf) == "CFrame") then
		return false
	end
	pr.xform = cf
	pr.weld.C0 = cf * pr.centre
	return true
end

-- true while inst (a round-1 part / decal / beam) is hidden on this client because a mesh replaces it:
-- FX modules leave its LocalTransparencyModifier / Transparency / Enabled alone then
function AnatomyClient.IsReplaced(inst)
	local cur = inst and inst.Parent
	while cur do
		local rec = records[cur]
		if rec then
			return rec.hidden[inst] ~= nil
		end
		cur = cur.Parent
	end
	return false
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
		sections = {}, models = 0, built = { full = 0, medium = 0, low = 0 }, hidden = 0, queued = 0, busy = workerBusy, cache = cacheCount,
		pressure = { fails = pressure.fails, cap = pressure.cap < math.huge and math.floor(pressure.cap) or nil, live = math.floor(liveCost()) },
		skipped = 0, cacheMB = math.floor(cacheBytes / 104857.6) / 10 }
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
			elseif st.skipped then
				s.skipped += 1
			end
			if st.job and not st.job.cancelled then
				s.queued += 1
			end
		end
	end
	return s
end

return AnatomyClient
