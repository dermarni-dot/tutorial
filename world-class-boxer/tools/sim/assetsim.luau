--!nocheck
-- assetsim.luau: a fake AssetService that serves the asset hair's REAL outputs offline, for the lune host.
-- `python3 tools/hair/publish.py --local` writes a manifest with fake ids (HairAssetData_local.lua) and a
-- sidecar (HairAssetData_local.ids.json: fake id -> local .mesh / .png file); this module answers the engine
-- calls HairAssets makes with those files:
--   CreateEditableImageAsync(Content.fromUri("rbxassetid://<id>")) -> an EditableImage-like object holding the
--     decoded pixels of the PNG the id maps to (decoded once by tools/hair/png2rgba.py, cached as .rgba)
--   CreateEditableImage({ Size }) -> an empty one (WritePixelsBuffer / ReadPixelsBuffer / Destroy)
--   CreateMeshPartAsync(Content.fromUri("rbxassetid://<id>")) -> a MeshPart-like stub (opts.newPart builds it:
--     the e2e test gives fake Instances) remembering its mesh id; MeshOf(id) reads that .mesh (meshv2.luau)
--   CreateEditableMesh() -> an EditableMesh-like recorder (AnatomyClient's probe and the generated hair)
-- Failure injection: sim.fail.mesh[id] / sim.fail.image[id] = "error text" (raised), sim.nilImage (the
-- CreateEditableImage budget: returns nil), sim.onCall(kind, id) (called before each async call: a yield point).
--
--   local AssetSim = require("./assetsim")
--   local sim = AssetSim.new({ manifest = "/tmp/claude-0/HairAssetData_local.lua" })
--   local H = Host.new({ globals = { Content = sim.Content } })
--   H.Service("AssetService")._props = sim.AssetService
--   AssetSim.UseManifest(H, sim.manifest)      -- Shared.HairAssetData -> the local manifest
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local MeshV2 = require("./meshv2")

local Vector2 = roblox.Vector2

local AssetSim = {}

AssetSim.PYTHON = "/opt/bpyenv/bin/python"
AssetSim.LOCAL_MANIFEST = "/tmp/claude-0/HairAssetData_local.lua"

local function dirname(p)
	return (p:gsub("/[^/]*$", ""))
end
local function exists(p)
	local ok, r = pcall(fs.isFile, p)
	return ok and r
end
local function mtime(p)
	local ok, m = pcall(fs.metadata, p)
	return ok and m.modifiedAt and m.modifiedAt.unixTimestampMillis or 0
end

-- Content as the engine's (fromUri / fromObject), plain tables
AssetSim.Content = {
	fromUri = function(u)
		return { Uri = u, uri = u }
	end,
	fromObject = function(o)
		return { Object = o, object = o }
	end,
	none = {},
}

local function idOf(content)
	local u = type(content) == "table" and (content.uri or content.Uri) or tostring(content)
	return tonumber(tostring(u):match("(%d+)%s*$"))
end
AssetSim.IdOf = idOf

-- (re)writes the local manifest when it is missing or older than any tools/hair/out/*/style.json (builders keep
-- adding styles): python3 tools/hair/publish.py --local PATH. Returns true when it ran
function AssetSim.EnsureManifest(root, path, force)
	path = path or AssetSim.LOCAL_MANIFEST
	local side = path:gsub("%.lua$", "") .. ".ids.json"
	local stale = force or not exists(path) or not exists(side)
	if not stale then
		local t = mtime(path)
		local okD, keys = pcall(fs.readDir, root .. "/tools/hair/out")
		for _, k in ipairs(okD and keys or {}) do
			local sj = root .. "/tools/hair/out/" .. k .. "/style.json"
			if exists(sj) and mtime(sj) > t then
				stale = true
				break
			end
		end
		local okT, texs = pcall(fs.readDir, root .. "/tools/hair/textures")
		for _, f in ipairs(okT and texs or {}) do
			if not stale and f:match("^hair_.*%.png$") and mtime(root .. "/tools/hair/textures/" .. f) > t then
				stale = true
			end
		end
	end
	if not stale then
		return false
	end
	local r = process.exec("python3", { root .. "/tools/hair/publish.py", "--local", path }, { cwd = root .. "/tools/hair" })
	if not r.ok then
		error("publish.py --local failed:\n" .. r.stdout .. r.stderr)
	end
	print((r.stdout:gsub("%s+$", "")))
	return true
end

-- Shared.HairAssetData -> the manifest file at path (the host's node for it, or a new one)
function AssetSim.UseManifest(H, path)
	local node = H.shared._kids.HairAssetData
	if not node then
		local Host = require("./host")
		node = Host.NewNode("HairAssetData", "ModuleScript", H.shared)
	end
	rawset(node, "_file", path)
	H.files.HairAssetData = node
	H.cache[node] = nil
	return node
end

-- opts: manifest (path, default LOCAL_MANIFEST), ids (sidecar path, default next to it), cache (dir for decoded
-- .rgba, default <root>/tools/sim/out/rgba), root, newPart (fn(id) -> a MeshPart-like object)
function AssetSim.new(opts)
	opts = opts or {}
	local root = opts.root or require("./host").FindRoot()
	local manifest = opts.manifest or AssetSim.LOCAL_MANIFEST
	local side = opts.ids or (manifest:gsub("%.lua$", "") .. ".ids.json")
	local idmap = serde.decode("json", fs.readFile(side)).ids
	local cacheDir = opts.cache or (root .. "/tools/sim/out/rgba")
	if not pcall(fs.isDir, cacheDir) or not fs.isDir(cacheDir) then
		fs.writeDir(cacheDir)
	end

	local sim = {
		root = root, manifest = manifest, ids = idmap, Content = AssetSim.Content,
		fail = { mesh = {}, image = {} }, nilImage = false, onCall = nil,
		live = { parts = 0, images = 0, meshes = 0 }, made = { parts = 0, images = 0, meshes = 0 },
		calls = { mesh = 0, image = 0 }, decodeMs = 0,
	}
	local meshes, pixels = {}, {}

	function sim.FileOf(id)
		return idmap[tostring(id)]
	end

	function sim.MeshOf(id)
		local m = meshes[id]
		if not m then
			local f = sim.FileOf(id)
			if not f then
				error("assetsim: no file for mesh id " .. tostring(id))
			end
			m = MeshV2.Read(f)
			m.file = f
			meshes[id] = m
		end
		return m
	end

	-- every image file of the sidecar decoded to .rgba once (one python call for all that are out of date)
	function sim.Preload()
		local args, todo = { root .. "/tools/hair/png2rgba.py" }, {}
		for id, f in pairs(idmap) do
			if f:match("%.png$") then
				local out = cacheDir .. "/" .. f:match("([^/]+)%.png$") .. "_" .. id .. ".rgba"
				local meta = out .. ".json"
				if not (exists(out) and exists(meta) and mtime(out) >= mtime(f)) then
					args[#args + 1] = f
					args[#args + 1] = out
					todo[out] = meta
				end
			end
		end
		if #args > 1 then
			local t0 = os.clock()
			local r = process.exec(AssetSim.PYTHON, args)
			if not r.ok then
				error("png2rgba failed:\n" .. r.stdout .. r.stderr)
			end
			for line in r.stdout:gmatch("[^\n]+") do
				local w, h, out = line:match("^(%d+) (%d+) (.+)$")
				if out and todo[out] then
					fs.writeFile(todo[out], serde.encode("json", { w = tonumber(w), h = tonumber(h) }))
				end
			end
			sim.decodeMs += (os.clock() - t0) * 1000
		end
	end

	function sim.PixelsOf(id)
		local p = pixels[id]
		if p then
			return p
		end
		local f = sim.FileOf(id)
		if not f or not f:match("%.png$") then
			return nil
		end
		local out = cacheDir .. "/" .. f:match("([^/]+)%.png$") .. "_" .. id .. ".rgba"
		if not exists(out .. ".json") or mtime(out) < mtime(f) then
			sim.Preload()
		end
		local meta = serde.decode("json", fs.readFile(out .. ".json"))
		p = { str = fs.readFile(out), w = meta.w, h = meta.h, file = f }
		pixels[id] = p
		return p
	end

	local function newImage(w, h, str)
		sim.live.images += 1
		sim.made.images += 1
		local img = { ClassName = "EditableImage", Size = Vector2.new(w, h), destroyed = false }
		img.buf = str and buffer.fromstring(str) or buffer.create(w * h * 4)
		function img.ReadPixelsBuffer(self, pos, size)
			assert(pos.X == 0 and pos.Y == 0 and size.X == self.Size.X and size.Y == self.Size.Y, "assetsim: whole-image reads only")
			return buffer.fromstring(buffer.tostring(self.buf))
		end
		function img.WritePixelsBuffer(self, pos, size, b)
			assert(pos.X == 0 and pos.Y == 0 and size.X == self.Size.X and size.Y == self.Size.Y, "assetsim: whole-image writes only")
			assert(buffer.len(b) == size.X * size.Y * 4, "assetsim: WritePixelsBuffer size mismatch")
			self.buf = b
		end
		function img.Destroy(self)
			if not self.destroyed then
				self.destroyed = true
				sim.live.images -= 1
			end
		end
		return img
	end
	sim.NewImage = newImage

	local function defaultPart(id)
		local p = { ClassName = "MeshPart", Name = "MeshPart", destroyed = false }
		function p.Destroy(self)
			self.destroyed = true
		end
		function p.IsA(_, c)
			return c == "MeshPart" or c == "BasePart" or c == "Instance"
		end
		return p
	end
	local newPart = opts.newPart or defaultPart

	local svc = {}
	function svc.CreateMeshPartAsync(_, content, _opts)
		sim.calls.mesh += 1
		local id = idOf(content)
		if sim.onCall then
			sim.onCall("mesh", id)
		end
		if id and sim.fail.mesh[id] then
			error(sim.fail.mesh[id], 0)
		end
		local obj = type(content) == "table" and (content.object or content.Object)
		if not id and not obj then
			error("assetsim: CreateMeshPartAsync with no asset id / object", 0)
		end
		if id and not sim.FileOf(id) then
			error("HTTP 404 (Not Found): asset " .. id, 0)
		end
		local p = newPart(id, obj)
		p.MeshId = id and ("rbxassetid://" .. id) or ""
		rawset(p, "_meshId", id)
		rawset(p, "_editable", obj)
		sim.live.parts += 1
		sim.made.parts += 1
		local destroy = p.Destroy
		rawset(p, "Destroy", function(self)
			if not rawget(self, "_simDead") then
				rawset(self, "_simDead", true)
				sim.live.parts -= 1
			end
			destroy(self)
		end)
		return p
	end
	function svc.CreateEditableImageAsync(_, content)
		sim.calls.image += 1
		local id = idOf(content)
		if sim.onCall then
			sim.onCall("image", id)
		end
		if id and sim.fail.image[id] then
			error(sim.fail.image[id], 0)
		end
		local px = id and sim.PixelsOf(id)
		if not px then
			error("HTTP 404 (Not Found): image asset " .. tostring(id), 0)
		end
		return newImage(px.w, px.h, px.str)
	end
	function svc.CreateEditableImage(_, o)
		if sim.nilImage then
			return nil
		end
		local s = o and o.Size or Vector2.new(512, 512)
		return newImage(s.X, s.Y)
	end
	function svc.CreateEditableMesh(_, _o)
		sim.live.meshes += 1
		sim.made.meshes += 1
		local em = { ClassName = "EditableMesh", nv = 0, nt = 0, destroyed = false }
		local n = 0
		local function nextId()
			n += 1
			return n
		end
		function em.AddVertex(self)
			self.nv += 1
			return nextId()
		end
		em.AddNormal, em.AddUV, em.AddColor = nextId, nextId, nextId
		function em.AddTriangle(self)
			self.nt += 1
			return nextId()
		end
		function em.SetFaceNormals() end
		function em.SetFaceUVs() end
		function em.SetFaceColors() end
		function em.SetPosition() end
		function em.SetNormal() end
		function em.SetColor() end
		function em.Destroy(self)
			if not self.destroyed then
				self.destroyed = true
				sim.live.meshes -= 1
			end
		end
		return em
	end
	sim.AssetService = svc
	return sim
end

-- where the engine draws an uploaded mesh on a MeshPart of this Size welded at centre (Head space; the part's
-- rotation is identity in HairAssets): the mesh is recentred on its bounding box and scaled to Size per axis.
-- Returns P (a new flat array) and the per-axis scale used
function AssetSim.Placed(m, size, centre)
	local cx, cy, cz, sx, sy, sz = MeshV2.Bounds(m)
	local function k(s, b)
		return b > 1e-9 and s / b or 1
	end
	local kx, ky, kz = k(size[1], sx), k(size[2], sy), k(size[3], sz)
	local P, Q = m.P, table.create(#m.P)
	for i = 1, #P, 3 do
		Q[i] = centre[1] + (P[i] - cx) * kx
		Q[i + 1] = centre[2] + (P[i + 1] - cy) * ky
		Q[i + 2] = centre[3] + (P[i + 2] - cz) * kz
	end
	return Q, { kx, ky, kz }
end

AssetSim.dirname = dirname
return AssetSim
