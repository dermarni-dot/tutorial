-- HairAssets: the asset hair (tools/hair/CONTRACT.md): hair-card meshes modelled in Blender and uploaded as
-- Mesh / Image assets owned by the game's group (ids in Shared.HairAssetData, written by tools/hair/publish.py),
-- loaded on this client and fitted to each boxer. AnatomyClient tries it first for the Hair section; when a look
-- has no complete entry, or anything of it fails to load, the same job goes on to the generated hair
-- (AnatomyHair meshes; below them the round-1 BuilderHair parts), so a missing or broken asset never shows.
-- * For(look, lod, wantTex) -> entry | nil: AnatomyHair's own style / type routing (HairAssetKit.Select);
--   nil when Config.HairAssets is off, in BaldMode, without textures (NPCs on Low keep the generated low hair)
--   or when one of the entry's ids failed (retried once a minute later when the failure looked transient)
-- * Waiting(look, lod, wantTex) -> { ids, at } | nil: the entry the look would draw while its ids wait for
--   that retry (the caller drew the generated hair: Retry(w) -> "due" | "wait" | "never" says when to build
--   it again); Cost(look, lod, wantTex, priority) -> the Editable image bytes For's entry would take
-- * Build(model, entry, look, lod, ctx) -> made, result | nil, err, kind: MeshParts from the uploaded meshes
--   (AssetService:CreateMeshPartAsync, sized by the skull fit), each with its texture tinted to the look's
--   hair colour in an EditableImage (the greyscale cards x Kit.Palette's colours), plus the scalp cap painted
--   per boxer with the style's own coverage (fades, hairline, line-up, growth). `made` holds piece records of
--   makePiece's shape, `result` the pieces / landmarks runJob reads. kind: "asset" (an id failed: marked, the
--   caller generates), "tex" (an EditableImage could not be made or set: textures pause as in makePiece, the
--   caller generates), "api" (loading an image hit the Editable memory budget), "skip" (no Head yet)
-- * tinted images are shared between NPCs of one hair colour (refcounted: a piece's release()), never with
--   you, your opponent or a preview (theirs are their own, so HairFX's wet look may rewrite them)
-- ctx (from AnatomyClient): { resume = fn() after every yield (re-arms the time slice, raises the cancel),
--   priority, sig, mpOptions }
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HairAssets = {}

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MeshKit = require(Shared:WaitForChild("MeshKit"))
local Config = require(Shared:WaitForChild("Config"))
local HK = require(Shared:WaitForChild("HairAssetKit"))
local Gen = require(Shared:WaitForChild("AnatomyHair"))
local HairKit = require(Shared:WaitForChild("AnatomyHairKit"))
local Data
do
	local ok, d = pcall(function()
		return require(Shared:WaitForChild("HairAssetData", 10))
	end)
	Data = ok and type(d) == "table" and d or { entries = {}, textures = {} }
end
local AssetService = game:GetService("AssetService")

local step = MeshKit.Step
-- seconds before an id that failed with a transient-looking error is tried once more
local RETRY_AFTER = 60
-- original (greyscale) texture pixels kept in Lua for re-tinting, at most this many bytes (least recently used go)
local SOURCE_CACHE = 24 * 1048576

local failed = {} -- asset id -> { at, transient, retried, err }
local sources = {} -- texture id -> { buf, w, h, bytes, used }
local sourceBytes = 0
local tints = {} -- shared tinted images: key -> holder { img, refs, bytes, key }
local stats = { built = 0, failedBuilds = 0, privateLive = 0 }
local useN = 0
local warned = {}

local function warnOnce(key, ...)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[HairAssets]", ...)
end

local function cfg()
	return type(Config.HairAssets) == "table" and Config.HairAssets or {}
end

-- an error that is the device's Editable memory (not the asset)
local function isMemory(err)
	local e = tostring(err):lower()
	return e:find("budget", 1, true) ~= nil or e:find("memory", 1, true) ~= nil
end

-- worth one more try later: timeouts, throttling, server errors
local function isTransient(err)
	local e = tostring(err):lower()
	return e:find("timeout", 1, true) ~= nil or e:find("timed out", 1, true) ~= nil or e:find("throttl", 1, true) ~= nil
		or e:find("http 5", 1, true) ~= nil or e:find("503", 1, true) ~= nil or e:find("502", 1, true) ~= nil
		or e:find("500", 1, true) ~= nil or e:find("too many", 1, true) ~= nil or e:find("returned nil", 1, true) ~= nil
end

local function markFailed(id, err)
	local f = failed[id]
	if f and f.retried then
		f.transient = false -- failed its second try too: for the session
	elseif f then
		f.at = os.clock()
	else
		failed[id] = { at = os.clock(), transient = isTransient(err), retried = false, err = tostring(err) }
	end
	warnOnce("fail" .. id, "asset " .. id .. " did not load (" .. tostring(err) .. "); the generated hair is drawn instead."
		.. " Group-owned assets load only in a place the same group owns.")
end

-- true while an id is to be skipped: failed and not due for its one retry (a transient failure, RETRY_AFTER s
-- later). No side effect: the retry is used up only when a build really asks for the id again (attempt)
local function isFailed(id)
	local f = failed[id]
	if not f then
		return false
	end
	return not (f.transient and not f.retried and os.clock() - f.at >= RETRY_AFTER)
end

-- a build is about to load id: a failed one is on its retry now; loaded(id) clears the mark the moment it loads
local function attempt(id)
	local f = failed[id]
	if f then
		local was = f.retried
		f.retried = true
		return was
	end
	return nil
end
local function loaded(id)
	failed[id] = nil
end
-- after the engine call for id (attempt's was): the id is cleared when it loaded; a failure that is not the
-- asset's (blame false: the device's Editable memory, kind "api", which Build does not mark) gives the retry
-- back. Then ctx.resume, which may cancel the job (a first build waiting): a cancel after a failed retry also
-- gives it back (Build's error path marks nothing), so an id is never left "retrying" for the session
local function settle(id, was, ok, blame, obj, ctx)
	local f = failed[id]
	if ok then
		loaded(id)
	elseif not blame and f and was ~= nil then
		f.retried = was
	end
	local okC, err = pcall(ctx.resume, obj)
	if not okC then
		f = failed[id]
		if f and was ~= nil then
			f.retried = was
		end
		error(err, 0)
	end
end

-- every asset id an entry loads
local function idsOf(entry)
	local out = {}
	for _, p in pairs(entry.pieces or {}) do
		out[#out + 1] = HK.Id(p.mesh)
	end
	if HK.HasCap(entry) then
		out[#out + 1] = Data.cap and HK.Id(Data.cap.mesh)
	end
	for key in pairs(HK.TexturesOf(Data, entry)) do
		local t = Data.textures and Data.textures[key]
		out[#out + 1] = t and HK.Id(t.id)
	end
	return out
end

local function entryFailed(entry)
	for _, id in ipairs(idsOf(entry)) do
		if isFailed(id) then
			return true
		end
	end
	return false
end

local function active(wantTex)
	return cfg().enabled ~= false and not Config.BaldMode and wantTex
end

function HairAssets.For(look, lod, wantTex)
	if not active(wantTex) then
		return nil
	end
	local ok, entry = pcall(HK.Select, Data, look, entryFailed)
	if not ok then
		warnOnce("select", "entry selection failed:", entry)
		return nil
	end
	return entry
end

------------------------------------------------------------------------
-- Textures
------------------------------------------------------------------------
local function flipV()
	local c = cfg()
	if c.flipV ~= nil then
		return c.flipV == true
	end
	return Data.flipV == true
end

local function wantSize(kind, lod, src)
	local c = cfg()
	local t = kind == "cap" and c.capSize or c.textureSize
	local s = type(t) == "table" and tonumber(t[lod]) or nil
	s = s or ({ full = 1024, medium = 512, low = 256 })[lod] or 512
	return math.min(s, src or s)
end

-- the uploaded texture's pixels (loaded once, the source image destroyed after reading: kept as a buffer)
local function source(id, ctx)
	local s = sources[id]
	if s then
		useN += 1
		s.used = useN
		return s
	end
	local was = attempt(id)
	local okI, img = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri("rbxassetid://" .. id))
	end)
	settle(id, was, okI and img ~= nil, okI or not isMemory(img), okI and img or nil, ctx)
	if not okI or not img then
		-- (a nil is not taken for memory: an asset that never loads must not switch the meshes off)
		local err = okI and "CreateEditableImageAsync returned nil" or img
		return nil, err, (not okI and isMemory(err)) and "api" or "asset"
	end
	local okR, buf = pcall(function()
		return img:ReadPixelsBuffer(Vector2.zero, img.Size)
	end)
	local size = img.Size
	pcall(img.Destroy, img)
	if not okR or typeof(buf) ~= "buffer" then
		return nil, "ReadPixelsBuffer: " .. tostring(buf), "asset"
	end
	useN += 1
	s = { buf = buf, w = size.X, h = size.Y, bytes = buffer.len(buf), used = useN }
	sources[id] = s
	sourceBytes += s.bytes
	while sourceBytes > SOURCE_CACHE do
		local oldId, oldUse = nil, math.huge
		for k, v in pairs(sources) do
			if v.used < oldUse and k ~= id then
				oldId, oldUse = k, v.used
			end
		end
		if not oldId then
			break
		end
		sourceBytes -= sources[oldId].bytes
		sources[oldId] = nil
	end
	return s
end

local function newImage(w, h, buf)
	local img, err = MeshKit.ToEditableImage(w, h, buf, { assetService = AssetService })
	return img, err
end

-- a holder for an image the pieces use: shared (in tints) or private to this build
local function holder(img, bytes, key)
	return { img = img, refs = 0, bytes = bytes, key = key }
end

local function acquire(h)
	h.refs += 1
	local released = false
	return function()
		if released then
			return
		end
		released = true
		h.refs -= 1
		if h.refs <= 0 then
			if h.key and tints[h.key] == h then
				tints[h.key] = nil
			elseif not h.key then
				stats.privateLive -= 1
			end
			pcall(h.img.Destroy, h.img)
		end
	end
end

-- the tinted image for one texture key: shared -> from / into the shared table
local function tinted(key, look, htype, pal, lod, shared, ctx)
	local tex = Data.textures and Data.textures[key]
	local id = tex and HK.Id(tex.id)
	if not id then
		return nil, "texture " .. key .. " has no id", "asset", nil
	end
	local size = wantSize("tex", lod, tonumber(tex.size))
	local skey = table.concat({ key, id, HK.ColorKey(look, htype), size, flipV() and "f" or "" }, "|")
	if shared and tints[skey] then
		return tints[skey]
	end
	local src, err, kind = source(id, ctx)
	if not src then
		return nil, err, kind, id
	end
	local f = math.max(1, src.w // size)
	local colors = HK.Colors(pal, src.h // f, HK.IsFlat(key, tex), HK.BANDS)
	local buf, w, h = HK.Tint(src.buf, src.w, src.h, f, colors, flipV(), tonumber(tex.gain))
	local img, ierr = newImage(w, h, buf)
	if not img then
		return nil, ierr, "tex", nil
	end
	local hd = holder(img, w * h * 4, shared and skey or nil)
	if shared then
		-- (another build may have made it while this one yielded)
		if tints[skey] then
			pcall(img.Destroy, img)
			return tints[skey]
		end
		tints[skey] = hd
	else
		stats.privateLive += 1
	end
	return hd
end

-- the cap texture of this boxer: the short tile tinted with the root colour, alpha = the style's coverage
local function capImage(entry, look, htype, pal, lod, S, fit, shared, ctx)
	local tex = Data.textures and Data.textures.short
	local id = tex and HK.Id(tex.id)
	if not id then
		return nil, "texture short has no id", "asset", nil
	end
	local size = wantSize("cap", lod)
	local skey = shared and table.concat({ "cap", tostring(ctx.sig), entry.key or "?", lod, size, flipV() and "f" or "" }, "|") or nil
	if skey and tints[skey] then
		return tints[skey]
	end
	local src, err, kind = source(id, ctx)
	if not src then
		return nil, err, kind, id
	end
	local cap = Data.cap or {}
	local cov, S2, sharp = HK.CapCoverage(look, lod, entry.cap, S)
	local gw, gh = HK.GridSize(sharp)
	local grid = HK.CapGrid(S2, cov, pal, tonumber(cap.thetaMax) or 2.2, gw, gh, fit)
	local tile = type(cap.tile) == "table" and cap.tile or { 8, 4 }
	local buf = HK.PaintCap(grid, src.buf, src.w, src.h, tonumber(tile[1]) or 8, tonumber(tile[2]) or 4, size, flipV(), tonumber(tex.gain))
	local img, ierr = newImage(size, size, buf)
	if not img then
		return nil, ierr, "tex", nil
	end
	local hd = holder(img, size * size * 4, skey)
	if skey then
		if tints[skey] then
			pcall(img.Destroy, img)
			return tints[skey]
		end
		tints[skey] = hd
	else
		stats.privateLive += 1
	end
	return hd
end

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------
local function materialOf(name)
	local ok, m = pcall(function()
		return Enum.Material[name]
	end)
	return ok and m or Enum.Material.SmoothPlastic
end

-- one MeshPart from an uploaded mesh, sized and coloured; nil, err, kind
local function meshPart(id, pl, ap, mid, ctx)
	local was = attempt(id)
	local okMP, mp = pcall(function()
		local uri = Content.fromUri("rbxassetid://" .. id)
		if ctx.mpOptions == false then
			return AssetService:CreateMeshPartAsync(uri)
		end
		return AssetService:CreateMeshPartAsync(uri, {
			CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	settle(id, was, okMP and mp ~= nil, true, okMP and mp or nil, ctx)
	if not okMP or not mp then
		return nil, okMP and "CreateMeshPartAsync returned nil" or mp, "asset"
	end
	mp.Size = Vector3.new(math.max(pl.size[1], 0.001), math.max(pl.size[2], 0.001), math.max(pl.size[3], 0.001))
	mp.Name = "Anatomy" .. pl.name
	mp.Anchored = false
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.Massless = true
	mp.CastShadow = ap.castShadow ~= false
	mp.Material = materialOf(ap.material or "SmoothPlastic")
	-- (where a client would show the part's colour through the texture's alpha: at least the hair's tone)
	mp.Color = Color3.new(mid[1], mid[2], mid[3])
	-- a hair card's alpha cut-out: the texture's alpha is see-through only on a part that is itself a little
	-- transparent (Config.HairAssets.alphaTransparency; 0 = opaque cards over the part's colour)
	mp.Transparency = tonumber(ap.transparency) or tonumber(cfg().alphaTransparency) or 0
	mp.Reflectance = tonumber(ap.reflectance) or 0
	pcall(function()
		mp.DoubleSided = ap.doubleSided ~= false
	end)
	return mp
end

-- everything a build made so far, destroyed when it fails or is cancelled
local function cleanup(made, releases)
	for _, pr in pairs(made) do
		if pr.part then
			pcall(pr.part.Destroy, pr.part)
		end
		pr.part = nil
	end
	for _, rel in ipairs(releases) do
		pcall(rel)
	end
end

local function buildInner(model, entry, look, lod, ctx, made, releases)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil, "attach part Head missing", "skip"
	end
	local style, htype = Gen.Resolve(look)
	local S = HairKit.Scalp(look)
	local placed, fit = HK.Place(Data, entry, look, S)
	local pal = HK.Palette(look, htype)
	local mr, mg, mb = HK.MidColor(pal)
	local mid = { mr, mg, mb }
	-- you, your opponent, previews: their own images (HairFX's wet look rewrites them); NPCs share by colour
	local shared = cfg().shareTints ~= false and (ctx.priority or 2) > 1
	-- 1) the textures (one image per texture key, used by every piece drawing it)
	local images = {}
	local owner = {} -- private image -> the first piece given it (HairFX wets it once, its memory counts once)
	local keys = {}
	for _, ap in pairs(entry.pieces or {}) do
		if type(ap.tex) == "string" and not keys[ap.tex] then
			keys[ap.tex] = true
			keys[#keys + 1] = ap.tex
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local hd, err, kind, id = tinted(key, look, htype, pal, lod, shared, ctx)
		if not hd then
			return nil, "texture " .. key .. ": " .. tostring(err), kind, id
		end
		images[key] = hd
		releases[#releases + 1] = acquire(hd)
	end
	if placed.HairCap then
		local hd, err, kind, id = capImage(entry, look, htype, pal, lod, S, fit, shared, ctx)
		if not hd then
			return nil, "cap texture: " .. tostring(err), kind, id
		end
		images.__cap = hd
		releases[#releases + 1] = acquire(hd)
	end
	-- 2) the meshes, in name order
	local names = {}
	for name in pairs(placed) do
		names[#names + 1] = name
	end
	table.sort(names)
	local result = { pieces = {}, landmarks = {} }
	for _, name in ipairs(names) do
		local pl = placed[name]
		local isCap = name == "HairCap" and not (entry.pieces and entry.pieces.HairCap)
		local ap = isCap and (Data.cap or {}) or entry.pieces[name]
		local id = HK.Id(ap.mesh)
		local mp, err, kind = meshPart(id, pl, ap, mid, ctx)
		if not mp then
			return nil, name .. ": " .. tostring(err), kind, id
		end
		local hd = isCap and images.__cap or images[ap.tex]
		local img, textured = nil, false
		local cost = 0
		local rel
		if hd then
			local okT, errT = pcall(function()
				mp.TextureContent = Content.fromObject(hd.img)
			end)
			if not okT then
				mp:Destroy()
				return nil, "TextureContent refused: " .. tostring(errT), "tex", nil
			end
			textured = true
			rel = acquire(hd)
			releases[#releases + 1] = rel
			if not hd.key and owner[hd] == nil then
				-- a private image: one piece carries it for HairFX and counts its memory
				owner[hd] = name
				img = hd.img
				cost = hd.bytes
			end
		end
		local c = pl.centre
		local stub = { name = name, nv = pl.nv, nt = 0, P = pl.P, groups = {}, hairfx = pl.hairfx, landmarks = pl.landmarks }
		made[name] = {
			name = name, attach = "Head", attachPart = head, part = mp, em = nil, info = nil, mesh = stub, img = img,
			release = rel, textured = textured, asset = true, centre = CFrame.new(c[1], c[2], c[3]),
			size = mp.Size, lod = lod, bounds = pl.bounds, hideUnder = ap.hideUnder, cost = cost,
		}
		result.pieces[name] = { mesh = stub, attach = "Head", hideUnder = ap.hideUnder }
	end
	local okL, lms = pcall(Gen.Landmarks, look)
	result.landmarks = okL and lms or {}
	return made, result
end

-- see the header. The build's own references (the per-texture ones taken while it ran) are dropped at the
-- end: what stays is one per piece (its release, called by AnatomyClient's destroyPiece)
function HairAssets.Build(model, entry, look, lod, ctx)
	local made, releases = {}, {}
	local ok, res, result, kind, id = pcall(buildInner, model, entry, look, lod, ctx, made, releases)
	if not ok then
		-- a cancellation (re-raised for the caller) or a fault in this module: nothing it made survives
		for _, pr in pairs(made) do
			pr.release = nil
		end
		cleanup(made, releases)
		error(res, 0)
	end
	if not res then
		for _, pr in pairs(made) do
			pr.release = nil
		end
		cleanup(made, releases)
		stats.failedBuilds += 1
		if kind == "asset" and id then
			markFailed(id, result)
		end
		return nil, result, kind
	end
	-- keep the pieces' own references, drop the build's per-texture ones
	local keep = {}
	for _, pr in pairs(made) do
		if pr.release then
			keep[pr.release] = true
		end
	end
	for _, rel in ipairs(releases) do
		if not keep[rel] then
			rel()
		end
	end
	stats.built += 1
	return made, result
end

-- the entry this look draws while ids of it wait for their retry: { ids, at (os.clock() when the last is
-- due), key }; nil when none waits (nothing to draw, all loaded, or one failed for good)
function HairAssets.Waiting(look, lod, wantTex)
	if not active(wantTex) then
		return nil
	end
	local ok, entry = pcall(HK.Select, Data, look)
	if not ok or not entry then
		return nil
	end
	local ids, at = {}, 0
	for _, id in ipairs(idsOf(entry)) do
		local f = failed[id]
		if f then
			if not f.transient or f.retried then
				return nil
			end
			ids[#ids + 1] = id
			at = math.max(at, f.at + RETRY_AFTER)
		end
	end
	if #ids == 0 then
		return nil
	end
	return { ids = ids, at = at, key = entry.key }
end

-- a Waiting record now: "due" (every id loaded or may be tried again: build the look again), "wait" (not
-- yet, or another build is retrying one), "never" (one failed its retry too: the generated hair stays)
function HairAssets.Retry(w)
	local res = "due"
	for _, id in ipairs(type(w) == "table" and w.ids or {}) do
		local f = failed[id]
		if f then
			if not f.transient then
				return "never"
			elseif f.retried or os.clock() - f.at < RETRY_AFTER then
				res = "wait"
			end
		end
	end
	return res
end

-- the Editable image bytes the asset hair takes for this look at lod (nil: For picks no entry): each texture
-- key's tinted image at its wanted size (an NPC's are shared by colour: counted half, they are seldom alone)
-- and the cap's own. Its meshes are not Editable (uploaded): nothing for them
function HairAssets.Cost(look, lod, wantTex, priority)
	local entry = HairAssets.For(look, lod, wantTex)
	if not entry then
		return nil
	end
	local shared = cfg().shareTints ~= false and (priority or 2) > 1
	local n = 0
	local seen = {}
	for _, ap in pairs(entry.pieces or {}) do
		local key = ap.tex
		if type(key) == "string" and not seen[key] then
			seen[key] = true
			local tex = Data.textures and Data.textures[key]
			local sz = wantSize("tex", lod, tex and tonumber(tex.size))
			n += sz * sz * 4 * (shared and 0.5 or 1)
		end
	end
	if HK.HasCap(entry) and Data.cap then
		local sz = wantSize("cap", lod)
		n += sz * sz * 4
	end
	return n
end

-- Editable bytes of the shared tinted images alive (AnatomyClient adds them to its memory estimate once)
function HairAssets.SharedBytes()
	local n = 0
	for _, h in pairs(tints) do
		n += h.bytes
	end
	return n
end

-- counters for Status() / Diagnose()
function HairAssets.Stats()
	local ids = {}
	for id, f in pairs(failed) do
		ids[#ids + 1] = tostring(id) .. (f.transient and not f.retried and "(retry)" or "")
	end
	table.sort(ids)
	local shared = 0
	for _ in pairs(tints) do
		shared += 1
	end
	local usable = 0
	for _, e in ipairs(Data.entries or {}) do
		if HK.Usable(Data, e) then
			usable += 1
		end
	end
	return {
		enabled = cfg().enabled ~= false, entries = #(Data.entries or {}), usable = usable, built = stats.built,
		failedBuilds = stats.failedBuilds, failedIds = ids, sharedTints = shared, privateTints = stats.privateLive,
		sharedBytes = HairAssets.SharedBytes(), sourceBytes = sourceBytes,
	}
end

HairAssets._data = Data
HairAssets._failed = failed
return HairAssets
