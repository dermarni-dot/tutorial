-- BuilderGear: the Blender-modelled boxing gear on the server (tools/body/build_gear.py, uploaded by
-- tools/body/publish_gear.py into the generated GearAssetData). Every piece is fitted to ONE body part of ONE muscle
-- tier (the waistband and the seat to the LowerTorso, a shorts leg to its UpperLeg, the cuff to the LowerArm, the
-- boot shaft to the LowerLeg...; the glove, wrap and boot foot are the same at every tier) and is welded to it:
-- * templates: one MeshPart per mesh id, made once per server with AssetService:CreateMeshPartAsync (pcall;
--   concurrent callers wait for the same load; a failed id is retried after RETRY seconds), like BuilderTiers
-- * Resolve(model, group, style): the pieces a style wears (GearAssetData.sets) for the tiers the model's parts show
--   (their BodyTier attribute; a piece with tierOf - the trunks' band and seat - takes the highest tier among those
--   parts, its offset moved onto the part's own tier: PieceTier). Nothing is half built: when a part is not a tier part, an id is 0 or a load failed,
--   it returns nil and the caller builds its part-built gear (BuilderBody's blocks)
-- * Build(folder, pieces, paint): a clone per piece, sized ONCE to the template's size x the body part's scale
--   ratio (Size / OriginalSize: the ratio BuilderTiers gave the part, so the gear scales exactly with the mesh under
--   it), welded at part.CFrame * CFrame.new(offset x ratio) (a Weld: it follows the part through every pose), and
--   painted per colour slot: paint(slot, piece name) -> colour, material, reflectance
-- * a tier change swaps the body part; the caller's cache signature carries Key(pieces) (the mesh ids and the
--   parts' sizes), so the gear is rebuilt for the new tier on the next Cosmetics
-- * checks for Studio: a template whose engine box (CreateMeshPartAsync's Size = the uploaded mesh's bounding box) is
--   not the manifest's size warns once (the upload and GearAssetData disagree); BuilderBody writes each group's state on
--   the Attire folder ("Trunks = mesh" / "blocks: <reason>"); Audit(model, true) prints every piece's mesh, part,
--   tier, ratio and size against the manifest - from the Studio command bar (server side, while playing):
--   require(game.ReplicatedStorage.Shared.BuilderGear).Audit(workspace.<Name>, true)
-- Tests: BuilderGear.Services = { AssetService = fake, Content = fake }, BuilderGear.SetData(t), BuilderGear.Reset().
local BuilderGear = {}

local Shared = script.Parent
local BuilderTiers = require(Shared:WaitForChild("BuilderTiers"))
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))
local Kit = require(Shared:WaitForChild("BuilderKit"))

local V3 = Vector3.new
BuilderGear.RETRY = 120 -- seconds between on-demand retries once the backoff schedule (Kit.ASSET_BACKOFF) is spent
-- every built gear piece carries this CollectionService tag: the clients watch its mesh arrive (BoxerClient.MeshGuard)
-- and show a rounded stand-in instead of the engine's box while it cannot be drawn
BuilderGear.TAG = "WCBGearMesh"
BuilderGear.BBOX_TOL = 0.02 -- the uploaded mesh's box may differ from the manifest's size by this fraction before a warning
BuilderGear.Services = {}

------------------------------------------------------------------------
-- GearAssetData
------------------------------------------------------------------------
local data
local function load()
	if data == nil then
		local ok, res = false, nil
		local m = Shared:FindFirstChild("GearAssetData")
		if m then
			ok, res = pcall(require, m)
		end
		data = (ok and type(res) == "table") and res or {}
	end
	return data
end
function BuilderGear.Data()
	return load()
end
-- tests / tools: use this table instead of the module (nil: load the module again)
function BuilderGear.SetData(d)
	data = d
end

local function idOf(v)
	local n = tonumber(v)
	return (n and n > 0) and math.floor(n) or nil
end
local function vec(t)
	if type(t) ~= "table" or type(t[1]) ~= "number" or type(t[2]) ~= "number" or type(t[3]) ~= "number" then
		return nil
	end
	return V3(t[1], t[2], t[3])
end

-- the piece `name` for a body part of tier `tier`: { id, offset, size, part, slot, group, name } or nil. lite = true:
-- the piece's `lite` mesh (the v9 set worn on lite body parts, Config.Detail.meshes), the full one when it has none
function BuilderGear.Entry(tier, name, d, lite)
	d = d or load()
	local tiers = type(d.tiers) == "table" and d.tiers or nil
	local t = tiers and (tiers[tier] or tiers[tostring(tier)])
	local e = type(t) == "table" and t[name] or nil
	local p = type(d.pieces) == "table" and d.pieces[name] or nil
	if type(e) ~= "table" or type(p) ~= "table" then
		return nil
	end
	local isLite = false
	if lite and type(e.lite) == "table" and idOf(e.lite.mesh) and vec(e.lite.offset) and vec(e.lite.size) then
		e, isLite = e.lite, true
	end
	local id, offset, size = idOf(e.mesh), vec(e.offset), vec(e.size)
	if not (id and offset and size) or size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return nil
	end
	return { id = id, offset = offset, size = size, part = p.part, slot = p.slot, group = p.group, name = name, tier = tier,
		lite = isLite }
end

-- the piece names a style wears (sided names expanded to _L / _R), or nil when the manifest has no such set
function BuilderGear.SetPieces(group, style, d)
	d = d or load()
	local g = type(d.sets) == "table" and d.sets[group] or nil
	local list = type(g) == "table" and g[style] or nil
	if type(list) ~= "table" then
		return nil
	end
	local out = {}
	for _, base in ipairs(list) do
		local pieces = type(d.pieces) == "table" and d.pieces or {}
		if pieces[base .. "_R"] or pieces[base .. "_L"] then
			table.insert(out, base .. "_L")
			table.insert(out, base .. "_R")
		else
			table.insert(out, base)
		end
	end
	return out
end

------------------------------------------------------------------------
-- Templates
------------------------------------------------------------------------
local cache = {} -- id -> { part = template } | { loading = true } | { failed = os.clock() }
local stats = { loads = 0, failed = 0, built = 0 }

function BuilderGear.Reset()
	for _, e in pairs(cache) do
		if e.part then
			pcall(function()
				e.part:Destroy()
			end)
		end
	end
	table.clear(cache)
	stats.loads, stats.failed, stats.built = 0, 0, 0
end

function BuilderGear.Stats()
	return table.clone(stats)
end

local function assetService()
	return BuilderGear.Services.AssetService or game:GetService("AssetService")
end

local function contentOf(uri)
	local C = BuilderGear.Services.Content or Content
	if C and C.fromUri then
		return C.fromUri(uri)
	end
	return uri
end

-- the template MeshPart for a mesh id (unscaled: Size = the mesh bbox), or nil + reason. Yields on the first call
-- for an id (CreateMeshPartAsync); later calls are free. force: retry a failed id now (the background retry)
function BuilderGear.Template(id, size, force)
	if not idOf(id) then
		return nil, "not uploaded"
	end
	local c = cache[id]
	while c and c.loading do
		task.wait()
		c = cache[id]
	end
	if c and c.part then
		return c.part
	elseif c and c.failed and not force and os.clock() < (c.retryAt or c.failed + BuilderGear.RETRY) then
		return nil, "failed"
	end
	local prev = c
	cache[id] = { loading = true }
	stats.loads += 1
	local ok, mp = Kit.Load(function()
		return pcall(function()
			return assetService():CreateMeshPartAsync(contentOf("rbxassetid://" .. id), {
				CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
	end)
	if ok and mp then
		-- a part without geometry (an empty MeshId, a zero MeshSize) is drawn as its box: never a template
		local good, why = Kit.MeshLoaded(mp)
		if not good then
			pcall(function()
				mp:Destroy()
			end)
			ok, mp = false, why
		end
	end
	if ok and mp then
		ok = pcall(function()
			-- the engine's own Size for the loaded mesh = its bounding box: the manifest's `size` must be the same
			-- number (the mesh is drawn recentred on that box and scaled to Size per axis), else the uploaded mesh is
			-- not the one build_gear.py measured (a stale manifest, an id pointing at an older upload): say so
			-- (a 1 x 1 x 1 Size is a stub part that never loaded a mesh - the simulators' fakes - not a measurement)
			local bbox = mp.Size
			if typeof(bbox) == "Vector3" and bbox.X > 1e-4 and bbox.Y > 1e-4 and bbox.Z > 1e-4 and (bbox - V3(1, 1, 1)).Magnitude > 1e-6 then
				mp:SetAttribute("GearBBox", bbox)
				if size then
					local d = V3(math.abs(bbox.X / size.X - 1), math.abs(bbox.Y / size.Y - 1), math.abs(bbox.Z / size.Z - 1))
					if math.max(d.X, d.Y, d.Z) > BuilderGear.BBOX_TOL then
						warn(string.format("[Gear] mesh %d: the uploaded mesh's box %s is not the manifest's size %s (GearAssetData is "
							.. "out of step with the upload: rebuild and re-run publish_gear.py); drawn at the manifest's size", id,
							tostring(bbox), tostring(size)))
					end
				end
			end
			mp.Anchored = false
			mp.CanCollide = false
			mp.CanQuery = false
			mp.CanTouch = false
			mp.Massless = true
			mp.CastShadow = false
			if size then
				mp.Size = size
			end
			mp:SetAttribute("GearMesh", id)
		end)
	end
	if not (ok and mp) then
		stats.failed += 1
		-- retried in the background on a backoff (Kit.ASSET_BACKOFF: a fresh upload whose content is still being
		-- generated loads a few minutes later), then on demand every RETRY seconds
		local tries = (prev and prev.tries or 0) + 1
		local delay = Kit.RetryDelay(tries)
		local now = os.clock()
		cache[id] = { failed = now, tries = tries, retryAt = now + (delay or BuilderGear.RETRY), err = tostring(mp) }
		if tries == 1 or not delay then
			warn(string.format("[Gear] mesh %d did not load (%s); the part-built gear stays%s", id, tostring(mp),
				delay and string.format(" (retrying in %ds, then on a backoff for a few minutes)", delay) or ""))
		end
		if delay then
			Kit.Schedule(delay, function()
				local e = cache[id]
				if e and e.failed and e.tries == tries then
					BuilderGear.Template(id, size, true)
				end
			end)
		end
		return nil, "failed"
	end
	cache[id] = { part = mp }
	if prev and prev.failed then
		print(string.format("[Gear] mesh %d loaded after %d failed attempt(s); the boxers built without it are refitted", id, prev.tries or 1))
		Kit.AssetReady("gear", id)
	end
	return mp
end

-- true while any gear mesh is in its failed state (Builder keeps the boxers built meanwhile for a rebuild)
function BuilderGear.Failing()
	for _, e in pairs(cache) do
		if e.failed then
			return true
		end
	end
	return false
end

-- load every uploaded gear mesh in the background (server start). ~520 meshes: fired back to back at boot they held
-- the asset pipeline for the first minute (in Studio the client's too) while the player's own body and gear, the
-- menu's boxer and the gym's NPCs waited behind them. Now: nothing for PRELOAD_DEFER seconds (the first player's
-- build and the gym's NPCs ask for their own pieces on demand), then one load every PRELOAD_GAP seconds, the pieces
-- worn most first (gloves, wraps, shoes, trunks; the default tier before the others; the full set before the lite
-- one), each yielding to the player's own loads (Kit.Load). opts = { gap, defer } (tests / tools)
BuilderGear.PRELOAD_GAP = 0.1
BuilderGear.PRELOAD_DEFER = 8
local GROUP_ORDER = { gloves = 1, wraps = 2, shoes = 3, trunks = 4, top = 5, official = 6 }
function BuilderGear.PreloadList()
	local d = load()
	local seen, list = {}, {}
	for _, lite in ipairs({ false, true }) do
		for tier, t in pairs(type(d.tiers) == "table" and d.tiers or {}) do
			for name in pairs(type(t) == "table" and t or {}) do
				local e = BuilderGear.Entry(tier, name, d, lite)
				if e and not seen[e.id] then
					seen[e.id] = true
					local tn = tonumber(tier) or 9
					table.insert(list, { id = e.id, size = e.size, name = name, lite = lite,
						rank = (lite and 1000 or 0) + (GROUP_ORDER[e.group or ""] or 9) * 10 + (tn == 1 and 0 or tn) })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.id < b.id
	end)
	return list
end
function BuilderGear.Preload(opts)
	opts = type(opts) == "table" and opts or {}
	local gap = tonumber(opts.gap) or BuilderGear.PRELOAD_GAP
	local defer = tonumber(opts.defer) or BuilderGear.PRELOAD_DEFER
	task.spawn(function()
		if defer > 0 then
			task.wait(defer)
		end
		for _, q in ipairs(BuilderGear.PreloadList()) do
			if not cache[q.id] then
				BuilderGear.Template(q.id, q.size)
				if gap > 0 then
					task.wait(gap)
				end
			end
		end
	end)
end

------------------------------------------------------------------------
-- Resolve / build
------------------------------------------------------------------------
-- the tier whose piece a model wears and the body part it welds to: the part's own BodyTier, or for a piece with
-- tierOf (the trunks' band and seat: fitted round the LowerTorso, the UpperTorso's hem and both thighs) the highest
-- tier among those parts, the piece then fitted to them all. nil when a part is not a tier part
local function pieceTier(model, p)
	local body = model:FindFirstChild(p.part)
	local own = body and tonumber(body:GetAttribute("BodyTier"))
	if not own then
		return nil
	end
	local tier = own
	if type(p.tierOf) == "table" then
		for _, pn in ipairs(p.tierOf) do
			local o = model:FindFirstChild(pn)
			local t = o and tonumber(o:GetAttribute("BodyTier"))
			if not t then
				return nil
			end
			tier = math.max(tier, t)
		end
	end
	-- (the detail set: a lite body part wears the lite gear fitted to it)
	return tier, body, own, body:GetAttribute("BodyLite") == true
end
BuilderGear.PieceTier = pieceTier

-- a piece of tier `tier` worn on a body part of tier `own`: the offset is in the part's space of ITS tier; the
-- LowerTorso's rig attachments are the same rest-space points at every tier, so the difference of the RootRigAttachment's
-- part-space positions moves the offset onto the part the model really shows
local function onPart(e, partName, tier, own, lite, frame)
	if tier == own then
		return e
	end
	local a = BodyTiers.PartEntry(own, partName, nil, lite, frame)
	local b = BodyTiers.PartEntry(tier, partName, nil, lite, frame)
	local pa = a and a.attachments.RootRigAttachment
	local pb = b and b.attachments.RootRigAttachment
	if not (pa and pb) then
		return e
	end
	local out = table.clone(e)
	out.offset = e.offset + V3(pa[1] - pb[1], pa[2] - pb[2], pa[3] - pb[3])
	return out
end
-- the pieces `style` of `group` puts on this model: { { name, entry, body, template, ratio } ... }, or nil + reason
-- (the caller builds its part-built gear). Every body part must be a muscle-tier part (BodyTier attribute)
function BuilderGear.Resolve(model, group, style)
	local names = BuilderGear.SetPieces(group, style)
	if not names or #names == 0 then
		return nil, "no set"
	end
	local out = {}
	for _, name in ipairs(names) do
		local d = load()
		local p = type(d.pieces) == "table" and d.pieces[name] or nil
		local tier, body, own, lite
		if p then
			tier, body, own, lite = pieceTier(model, p)
		end
		if not tier then
			return nil, "not a tier part: " .. tostring(p and p.part or name)
		end
		local e = BuilderGear.Entry(tier, name, d, lite)
		if not e then
			return nil, "not uploaded: " .. name
		end
		-- (v12 frames: the piece is fitted on the default family; the body part of another frame is that part scaled by
		-- the frame's gear scale, so the piece takes the same scale on top of the engine's ratio)
		local frame = (not lite) and body:GetAttribute("BodyFrame") or nil
		e = onPart(e, p.part, tier, own, lite, frame)
		local template = BuilderGear.Template(e.id, e.size)
		if not template then
			return nil, "failed: " .. name
		end
		local ratio = BuilderTiers.RatioOf(body) or V3(1, 1, 1)
		local g = BodyTiers.GearScale(frame, BodyTiers.Group(p.part))
		ratio = V3(ratio.X * g[1], ratio.Y * g[2], ratio.Z * g[3])
		table.insert(out, { name = name, entry = e, body = body, template = template, ratio = ratio })
	end
	return out
end

-- a signature of resolved pieces (mesh ids + the body parts' sizes) for the callers' rebuild caches
function BuilderGear.Key(pieces)
	if not pieces then
		return "blocks"
	end
	local parts = {}
	for _, r in ipairs(pieces) do
		local s = r.body.Size
		table.insert(parts, string.format("%s:%d:%.3f,%.3f,%.3f", r.name, r.entry.id, s.X, s.Y, s.Z))
	end
	return table.concat(parts, "|")
end

-- clone, size, weld and paint every resolved piece into folder. paint(slot, name) -> Color3, Material, reflectance.
-- Returns { [name] = MeshPart }
function BuilderGear.Build(folder, pieces, paint, rename)
	local made = {}
	for _, r in ipairs(pieces) do
		local e, body, ratio = r.entry, r.body, r.ratio
		local p = r.template:Clone()
		p.Name = (rename and rename[r.name]) or r.name
		p.Size = e.size * ratio
		local c0 = CFrame.new(e.offset * ratio)
		p.CFrame = body.CFrame * c0
		local color, material, refl = paint(e.slot, r.name)
		if color then
			p.Color = color
		end
		if material then
			p.Material = material
		end
		p.Reflectance = refl or 0
		p:SetAttribute("GearPiece", r.name)
		p:SetAttribute("GearSlot", e.slot)
		pcall(function()
			p:AddTag(BuilderGear.TAG)
		end)
		local w = Instance.new("Weld")
		w.Name = "GearWeld"
		w.Part0 = body
		w.Part1 = p
		w.C0 = c0
		w.C1 = CFrame.new()
		w.Parent = p
		p.Parent = folder
		made[r.name] = p
		stats.built += 1
	end
	return made
end

-- what a model wears, for the Output / a Studio check (one line per mesh piece: the piece, its mesh id, the body part
-- it is welded to with that part's tier / set / scale ratio, the piece's Size against the manifest's size x ratio, and
-- the uploaded mesh's own box when it differs), then every look folder's group records (BuilderBody: "Trunks = mesh",
-- "Shoes = blocks: failed: BootFoot_L"...). Returns the lines and prints them when `print` is true
function BuilderGear.Audit(model, doPrint)
	local lines = {}
	local look = model and model:FindFirstChild("BoxerLook")
	if not look then
		table.insert(lines, "no BoxerLook folder (Cosmetics has not run)")
	else
		for _, f in ipairs(look:GetChildren()) do
			for _, p in ipairs(f:GetChildren()) do
				local name = p:IsA("BasePart") and p:GetAttribute("GearPiece")
				if name then
					local w = p:FindFirstChild("GearWeld")
					local body = w and w.Part0
					local ratio = BuilderTiers.RatioOf(body)
					local tier = body and body:GetAttribute("BodyTier")
					local e = tier and BuilderGear.Entry(tier, name, nil, body:GetAttribute("BodyLite") == true)
					local want = (e and ratio) and (e.size * ratio) or nil
					local c = cache[p:GetAttribute("GearMesh")]
					local bbox = c and c.part and c.part:GetAttribute("GearBBox")
					table.insert(lines, string.format("%s/%s mesh %s on %s (tier %s%s, ratio %s): size %s%s%s", f.Name, name,
						tostring(p:GetAttribute("GearMesh")), body and body.Name or "?", tostring(tier),
						(body and body:GetAttribute("BodyLite")) and " lite" or "", ratio and tostring(ratio) or "?", tostring(p.Size),
						(want and (p.Size - want).Magnitude > 1e-3) and (" EXPECTED " .. tostring(want)) or "",
						(bbox and e and (bbox - e.size).Magnitude > 1e-3) and (" UPLOADED BOX " .. tostring(bbox)) or ""))
				end
			end
			for k, v in pairs(f:GetAttributes()) do
				if k ~= "Sig" then
					table.insert(lines, string.format("%s.%s = %s", f.Name, k, tostring(v)))
				end
			end
		end
	end
	if doPrint then
		print("[Gear] audit of " .. tostring(model and model.Name) .. ":\n  " .. table.concat(lines, "\n  "))
	end
	return lines
end

-- true when the model shows tier parts for every piece of the style and every one of them is uploaded (no loads:
-- for colour decisions made before the gear is built, e.g. the women's top over the UpperTorso)
function BuilderGear.Available(model, group, style)
	local names = BuilderGear.SetPieces(group, style)
	if not names or #names == 0 then
		return false
	end
	local d = load()
	for _, name in ipairs(names) do
		local p = type(d.pieces) == "table" and d.pieces[name] or nil
		local tier, lite
		if p then
			local _b, _o
			tier, _b, _o, lite = pieceTier(model, p)
		end
		local e = tier and BuilderGear.Entry(tier, name, d, lite)
		if not e then
			return false
		end
		local c = cache[e.id]
		if c and c.failed and os.clock() < (c.retryAt or c.failed + BuilderGear.RETRY) then
			return false
		end
	end
	return true
end

return BuilderGear
