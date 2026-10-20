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
-- Tests: BuilderGear.Services = { AssetService = fake, Content = fake }, BuilderGear.SetData(t), BuilderGear.Reset().
local BuilderGear = {}

local Shared = script.Parent
local BuilderTiers = require(Shared:WaitForChild("BuilderTiers"))
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))

local V3 = Vector3.new
BuilderGear.RETRY = 120
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
-- for an id (CreateMeshPartAsync); later calls are free
function BuilderGear.Template(id, size)
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
	elseif c and c.failed and os.clock() - c.failed < BuilderGear.RETRY then
		return nil, "failed"
	end
	cache[id] = { loading = true }
	stats.loads += 1
	local ok, mp = pcall(function()
		return assetService():CreateMeshPartAsync(contentOf("rbxassetid://" .. id), {
			CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if ok and mp then
		ok = pcall(function()
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
		cache[id] = { failed = os.clock() }
		warn(string.format("[Gear] mesh %d did not load (%s); the part-built gear stays", id, tostring(mp)))
		return nil, "failed"
	end
	cache[id] = { part = mp }
	return mp
end

-- load every uploaded gear mesh in the background (server start)
function BuilderGear.Preload()
	task.spawn(function()
		local d = load()
		local seen = {}
		for _, lite in ipairs({ false, true }) do
			for tier, t in pairs(type(d.tiers) == "table" and d.tiers or {}) do
				for name in pairs(type(t) == "table" and t or {}) do
					local e = BuilderGear.Entry(tier, name, d, lite)
					if e and not seen[e.id] then
						seen[e.id] = true
						BuilderGear.Template(e.id, e.size)
					end
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
local function onPart(e, partName, tier, own, lite)
	if tier == own then
		return e
	end
	local a = BodyTiers.PartEntry(own, partName, nil, lite)
	local b = BodyTiers.PartEntry(tier, partName, nil, lite)
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
		e = onPart(e, p.part, tier, own, lite)
		local template = BuilderGear.Template(e.id, e.size)
		if not template then
			return nil, "failed: " .. name
		end
		local ratio = BuilderTiers.RatioOf(body) or V3(1, 1, 1)
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
		if c and c.failed and os.clock() - c.failed < BuilderGear.RETRY then
			return false
		end
	end
	return true
end

return BuilderGear
