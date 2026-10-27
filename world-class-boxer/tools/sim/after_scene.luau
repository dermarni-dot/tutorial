--!nocheck
-- after_scene.luau: the "after" preview scenes: every look of a "before" set (export_ref.luau --before) drawn with
-- the ASSET hair exactly as the client builds it. The real client module (src/client/modules/HairAssets.lua) runs
-- HairAssets.For (HairAssetKit.Select) and HairAssets.Build (HK.Place, the cap's CapGrid / PaintCap, the cards'
-- Tint, image sharing) against a fake AssetService (assetsim.luau) serving the local outputs of tools/hair
-- (publish.py --local: fake ids -> out/<key>/*.mesh, textures/hair_*.png). Each built MeshPart is then drawn
-- where the engine would draw it: its .mesh recentred on the mesh's bounding box and scaled to the part's Size,
-- at its weld centre in Head space; its texture is the tinted EditableImage's pixels.
--
--   lune run tools/sim/after_scene.luau [--before DIR] [--out DIR] [--manifest PATH] [--only id,id]
--                                      [--lod full|medium|low] [--npc] [--no-regen]
--
--   --before   the before set (index.json + <id>.json; default the session scratchpad's before/)
--   --out      where the after set goes (default: before's sibling after/)
--   --manifest the local manifest (default /tmp/claude-0/HairAssetData_local.lua); rewritten first with
--              python3 tools/hair/publish.py --local when missing or older than an out/*/style.json
--              (--no-regen: use it as it is)
--   --lod      the level of detail built (default full, as the before set); --npc builds as an NPC
--              (priority 2: shared tinted images) instead of as you (priority 0: private ones)
--
-- Output (same format as before, previews.py reads both): <out>/<id>.json = { id, look, entry, fallback,
-- pieces = { name = { p, n, uv, c, t (1-based), nv, nt, texture = { file, w, h }, material, castShadow,
-- doubleSided, alpha = true, mesh (the .mesh file), size, centre } }, head = (the before scene's, unchanged),
-- landmarks }, <id>_<image>.rgba, index.json { looks = [{ id, file, style, type, g, entry, fallback, reason,
-- hairPieces, hairVerts, hairTris, images, paintMs, tintMs, buildMs }] }. A look whose style has no asset
-- entry (or whose build fails) gets the before scene's generated hair, fallback = true: what the game draws.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Host = require("./host")
local AssetSim = require("./assetsim")

local SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad"

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k = a[i]
		if k == "--no-regen" or k == "--npc" then
			args[k:sub(3)] = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local BEFORE = (args.before or (SCRATCH .. "/before")):gsub("/$", "")
local OUT = (args.out or (BEFORE:gsub("/[^/]*$", "") .. "/after")):gsub("/$", "")
local MANIFEST = args.manifest or AssetSim.LOCAL_MANIFEST
local LOD = args.lod or "full"
local PRIORITY = args.npc and 2 or 0
local only
if args.only then
	only = {}
	for id in args.only:gmatch("[^,]+") do
		only[id] = true
	end
end

local root = Host.FindRoot()
if not args["no-regen"] then
	AssetSim.EnsureManifest(root, MANIFEST)
elseif not fs.isFile(MANIFEST) then
	error("no manifest at " .. MANIFEST .. " (run python3 tools/hair/publish.py --local, or drop --no-regen)")
end

local sim = AssetSim.new({ root = root, manifest = MANIFEST })
sim.Preload()
local H = Host.new({ root = root, globals = { Content = sim.Content } })
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)
local HA = H.require("Client/HairAssets")
local HK = H.require("HairAssetKit")
local Data = HA._data

-- CPU of the texture work, by wrapping the kit's functions (HairAssets calls them through the HK table)
local timing = { paint = 0, tint = 0 }
for name, bucket in pairs({ CapGrid = "paint", PaintCap = "paint", Tint = "tint", Colors = "tint" }) do
	local f = HK[name]
	HK[name] = function(...)
		local t0 = os.clock()
		local r = table.pack(f(...))
		timing[bucket] += os.clock() - t0
		return table.unpack(r, 1, r.n)
	end
end

local function r5(x)
	return math.floor(x * 100000 + 0.5) / 100000
end
local function rounded(t)
	local o = table.create(#t)
	for i, v in ipairs(t) do
		o[i] = r5(v)
	end
	return o
end

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

-- the before scene's file (texture) copied into OUT
local function copyFile(name)
	local src, dst = BEFORE .. "/" .. name, OUT .. "/" .. name
	if fs.isFile(src) then
		fs.writeFile(dst, fs.readFile(src))
		return true
	end
	return false
end
local function copyMeshes(set)
	for _, md in pairs(set or {}) do
		if type(md.texture) == "table" and md.texture.file then
			copyFile(md.texture.file)
		end
	end
	return set
end

local function fakeModel()
	local head = { Name = "Head", ClassName = "Part" }
	function head.IsA(_, c)
		return c == "BasePart" or c == "Part" or c == "Instance"
	end
	return { Name = "Boxer", FindFirstChild = function(_, n)
		return n == "Head" and head or nil
	end }
end

local function enumName(v)
	if v == nil then
		return nil
	end
	local ok, n = pcall(function()
		return v.Name
	end)
	return ok and n or tostring(v):match("([^%.]+)$")
end

Host.MkDir(OUT)
local index = serde.decode("json", fs.readFile(BEFORE .. "/index.json"))
local outIndex = {
	about = "asset hair (tools/hair outputs through src/client/modules/HairAssets.lua, " .. LOD .. ", priority " .. PRIORITY
		.. ") placed where the engine draws each MeshPart, REAL Head part space (studs); head = the before scene's",
	manifest = MANIFEST, looks = {},
}
local lines = {}
local problems = {}

for _, L in ipairs(index.looks) do
	if only and not only[L.id] then
		continue
	end
	local before = serde.decode("json", fs.readFile(BEFORE .. "/" .. L.file))
	local look = L.look or before.look
	if not look then
		look = H.Look({ g = L.g, hair = { style = L.style, type = L.type } })
	end
	local scene = { id = L.id, look = look, pieces = {}, head = copyMeshes(before.head), landmarks = before.landmarks }
	local rec = { id = L.id, file = L.id .. ".json", style = L.style, type = L.type, g = L.g, images = {} }
	timing.paint, timing.tint = 0, 0
	local entry = HA.For(look, LOD, true)
	local made, result, kind
	local t0 = os.clock()
	if entry then
		made, result, kind = HA.Build(fakeModel(), entry, look, LOD, { priority = PRIORITY, sig = L.id, mpOptions = true, resume = function() end })
	end
	local buildMs = (os.clock() - t0) * 1000
	if not made then
		-- what the game draws then: the generated hair (the before scene's pieces)
		scene.fallback = true
		scene.pieces = copyMeshes(before.pieces)
		rec.fallback = true
		rec.reason = entry and string.format("build failed (%s): %s", tostring(kind), tostring(result)) or "no usable asset entry for this style / type"
		local nv, nt, n = 0, 0, 0
		for _, md in pairs(scene.pieces) do
			n += 1
			nv += md.nv or 0
			nt += md.nt or 0
		end
		rec.hairPieces, rec.hairVerts, rec.hairTris = n, nv, nt
		lines[#lines + 1] = string.format("%-14s FALLBACK (generated hair, %d pieces, %d tris): %s", L.id, n, nt, rec.reason)
		if entry then
			problems[#problems + 1] = L.id .. ": " .. rec.reason
		end
	else
		scene.entry = entry.key
		rec.entry = entry.key
		local imgFiles = {} -- image object -> file
		local nv, nt, n = 0, 0, 0
		local sizes = {}
		for _, name in ipairs(sortedKeys(made)) do
			local pr = made[name]
			local part = pr.part
			local id = rawget(part, "_meshId")
			local m = sim.MeshOf(id)
			local size = { part.Size.X, part.Size.Y, part.Size.Z }
			local c = pr.centre.Position
			local P, k = AssetSim.Placed(m, size, { c.X, c.Y, c.Z })
			-- normals under the per-axis scale: by the inverse scale, renormalised
			local N = table.create(#m.N)
			for i = 1, #m.N, 3 do
				local x, y, z = m.N[i] / k[1], m.N[i + 1] / k[2], m.N[i + 2] / k[3]
				local l = math.sqrt(x * x + y * y + z * z)
				l = l > 1e-12 and l or 1
				N[i], N[i + 1], N[i + 2] = x / l, y / l, z / l
			end
			-- the manifest's bbox (what Place sized the part from) against the mesh file's own (what the engine scales)
			local isCap = name == "HairCap" and not (entry.pieces and entry.pieces[name])
			local ap = isCap and Data.cap or entry.pieces[name]
			local bb, mb = ap.bbox, m.bbox
			local dev = 0
			for i = 1, 6 do
				dev = math.max(dev, math.abs(bb[i] - mb[i]))
			end
			if tonumber(ap.nt) and ap.nt ~= m.nt then
				problems[#problems + 1] = string.format("%s/%s: manifest nt %d, %s has %d (stale manifest: re-run without --no-regen)", L.id, name,
					ap.nt, m.file:match("[^/]+/[^/]+$"), m.nt)
			end
			if dev > 2e-4 then
				problems[#problems + 1] = string.format("%s/%s: manifest bbox differs from %s by %.4f (stale manifest or mesh)", L.id, name,
					m.file:match("[^/]+/[^/]+$"), dev)
			end
			local tc = part.TextureContent
			local img = type(tc) == "table" and (tc.object or tc.Object) or nil
			local tex
			if img then
				local file = imgFiles[img]
				if not file then
					local key = (isCap or ap.tex == "cap") and "cap" or tostring(ap.tex)
					file = string.format("%s_%s_%dx%d.rgba", L.id, key, img.Size.X, img.Size.Y)
					Host.WriteRGBA(OUT .. "/" .. file, img.buf)
					imgFiles[img] = file
					rec.images[#rec.images + 1] = { file = file, w = img.Size.X, h = img.Size.Y }
					sizes[#sizes + 1] = string.format("%s %dx%d", key, img.Size.X, img.Size.Y)
				end
				tex = { file = file, w = img.Size.X, h = img.Size.Y, format = "rgba8, rows top to bottom, straight alpha" }
			end
			local C = m.C
			scene.pieces[name] = {
				p = rounded(P), n = rounded(N), uv = rounded(m.U), c = C and rounded(C) or nil, t = m.T, nv = m.nv, nt = m.nt,
				texture = tex, material = enumName(part.Material), castShadow = part.CastShadow, doubleSided = part.DoubleSided,
				transparency = part.Transparency, alpha = true, attach = "Head", mesh = m.file:match("[^/]+/[^/]+$"),
				size = rounded(size), centre = rounded({ c.X, c.Y, c.Z }), hairfx = pr.mesh and pr.mesh.hairfx or nil,
			}
			n += 1
			nv += m.nv
			nt += m.nt
		end
		scene.landmarks = { hair = result and result.landmarks or {}, head = before.landmarks and before.landmarks.head }
		for _, pr in pairs(made) do
			if pr.release then
				pr.release()
			end
			if pr.part then
				pr.part:Destroy()
			end
		end
		rec.hairPieces, rec.hairVerts, rec.hairTris = n, nv, nt
		rec.paintMs, rec.tintMs, rec.buildMs = r5(timing.paint * 1000), r5(timing.tint * 1000), r5(buildMs)
		lines[#lines + 1] = string.format("%-14s %-14s %2d pieces %6d tris  images [%s]  paint %4.0f ms  tint %4.0f ms  build %4.0f ms", L.id,
			entry.key, n, nt, table.concat(sizes, ", "), timing.paint * 1000, timing.tint * 1000, buildMs)
	end
	Host.WriteJSON(OUT .. "/" .. rec.file, scene)
	table.insert(outIndex.looks, rec)
end
Host.WriteJSON(OUT .. "/index.json", outIndex, true)

for _, l in ipairs(lines) do
	print(l)
end
local st = HA.Stats()
print(string.format("entries %d (usable %d), built %d, failed builds %d, live images %d, live parts %d, png decode %.0f ms",
	st.entries, st.usable, st.built, st.failedBuilds, sim.live.images, sim.live.parts, sim.decodeMs))
for _, p in ipairs(problems) do
	print("WARN " .. p)
end
print("after:", OUT)
