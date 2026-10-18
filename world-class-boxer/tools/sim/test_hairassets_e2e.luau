--!nocheck
-- test_hairassets_e2e.luau: the asset hair end to end on a simulated client. AnatomyClient (unchanged) is started
-- for real: boot, the CollectionService tracking, the Heartbeat scheduler (evaluate: levels of detail, focus,
-- jobs), the serial worker (probe, runJob, assetHair -> HairAssets.Build, the generated fallback through
-- AnatomyHair + makePiece, attachPiece's welds, the swap) and Stop. The assets are the REAL tools/hair outputs
-- (publish.py --local manifest; meshes and textures served by assetsim.luau), the Instances fake ones
-- (fakeengine.luau: hierarchy, attributes, signals, tags).
--
--   lune run tools/sim/test_hairassets_e2e.luau [--manifest PATH] [--no-regen]
--
-- Simulated: the engine (Instances, welds as records, CreateMeshPartAsync / Create*Editable* as fakes that
-- answer at once, a camera, Heartbeat stepped by this script). Body and Head are registered as empty
-- generators (they would be skipped) so only the Hair section builds; Perf, State and AnatomyStatus are left
-- out (Graphics presets, the profile gate (profileWait 0 instead) and the status notice: not on this path).
-- Not simulated: rendering, physics, the engine's own memory budget, real asset permissions, network delays.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Host = require("./host")
local AssetSim = require("./assetsim")
local FE = require("./fakeengine")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local args = {}
for i, a in ipairs(process.args) do
	if a == "--no-regen" then
		args.noRegen = true
	elseif a == "--manifest" then
		args.manifest = process.args[i + 1]
	end
end
local MANIFEST = args.manifest or AssetSim.LOCAL_MANIFEST
local root = Host.FindRoot()
if not args.noRegen then
	AssetSim.EnsureManifest(root, MANIFEST)
end

local E = FE.new()
local sim = AssetSim.new({
	root = root, manifest = MANIFEST,
	newPart = function()
		return E.new("MeshPart")
	end,
})
sim.Preload()
local H = Host.new({ root = root, globals = { Content = sim.Content, Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)
-- modules boot would load that are not on the asset hair's path
for _, name in ipairs({ "Perf", "State", "AnatomyStatus" }) do
	local n = H.client._kids[name]
	if n then
		H.client._kids[name] = nil
		table.remove(H.client._order, table.find(H.client._order, n))
	end
end

-- the hair path under test: the shipping Config may have every boxer bald for now (Config.BaldMode)
H.require("Config").BaldMode = false
local LookData = H.require("LookData")
local HK = H.require("HairAssetKit")
local Kit = H.require("AnatomyHairKit")
local HA = H.require("Client/HairAssets")
local AC = H.require("Client/AnatomyClient")
local Data = HA._data

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-4)
end

-- the client, as the game starts it (only Hair builds: see the header)
AC.Settings.profileWait = 0
AC.Settings.frameBudget = 0.02
AC.Settings.debug = false
AC.Settings.generatedHair = "all" -- (the NPCs' generated fallback is tested too; the game's default is "focus")
local EMPTY = function()
	return { pieces = {}, landmarks = {} }
end
AC.Register("Body", { generate = EMPTY })
AC.Register("Head", { generate = EMPTY })
AC.Start()
E.step(5)

local models = {}
local function boxer(name, spec, z, tag)
	local m = E.new("Model")
	m.Name = name
	local hrp = E.new("Part", m)
	hrp.Name = "HumanoidRootPart"
	hrp.CFrame = CFrame.new(0, 3, z or -10)
	local head = E.new("Part", m)
	head.Name = "Head"
	head.CFrame = CFrame.new(0, 5.5, z or -10)
	local look = H.Look(spec)
	head.Size = Vector3.new(look.rig.parts.Head[1], look.rig.parts.Head[2], look.rig.parts.Head[3])
	m.Parent = E.workspace
	if tag then
		E.CollectionService:AddTag(m, tag)
	end
	LookData.Publish(m, look)
	models[name] = m
	return m, look
end

local function hair(m)
	return AC.GetPieces(m, "Hair")
end
local function isAsset(view)
	if not view or next(view) == nil then
		return nil
	end
	for _, v in pairs(view) do
		if not v.asset then
			return false
		end
	end
	return true
end
local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end

-- nothing made and not shown: every live part / EditableMesh / EditableImage belongs to a built piece (or is a
-- shared tint the pieces hold)
local function noLeaks(label)
	local parts, ems, imgs = 0, 0, {}
	for _, m in pairs(models) do
		if m.Parent then
			local view = hair(m)
			for _, v in pairs(view or {}) do
				if v.part then
					parts += 1
					check(label .. ": " .. m.Name .. " piece part is live", not rawget(v.part, "_simDead") and v.part:IsDescendantOf(m))
				end
				if v.image then
					imgs[v.image] = true
				end
			end
		end
	end
	local st = HA.Stats()
	check(label .. ": live parts == built pieces", sim.live.parts == parts, sim.live.parts .. " vs " .. parts)
	local nImg = count(imgs) + st.sharedTints
	check(label .. ": live images == pieces' + shared tints", sim.live.images == nImg, sim.live.images .. " vs " .. nImg)
	ems = sim.live.meshes
	local wantEms = 0
	for _, m in pairs(models) do
		for _, v in pairs(m.Parent and hair(m) or {}) do
			if not v.asset then
				wantEms += 1
			end
		end
	end
	check(label .. ": live EditableMeshes == generated pieces", ems == wantEms, ems .. " vs " .. wantEms)
end

-- the pieces as the engine would hold them: welded to Head at the placement HairAssetKit computes for this look
local function checkPlacement(label, m, look)
	local view = hair(m)
	local entry = HA.For(look, "full", true)
	check(label .. ": has an entry", entry ~= nil)
	if not (view and entry) then
		return
	end
	local placed = HK.Place(Data, entry, look, Kit.Scalp(look))
	check(label .. ": every placed piece built", count(view) == count(placed), count(view) .. " vs " .. count(placed))
	local head = m:FindFirstChild("Head")
	local folder = m:FindFirstChild("Anatomy")
	for name, v in pairs(view) do
		local pl = placed[name]
		local part = v.part
		local weld = part and part:FindFirstChild("AnatomyWeld")
		check(label .. "/" .. name .. ": placed", pl ~= nil)
		check(label .. "/" .. name .. ": asset, textured, on Head", v.asset == true and v.textured == true and v.attach == "Head")
		check(label .. "/" .. name .. ": in the Anatomy folder", folder ~= nil and part.Parent == folder)
		if pl and weld then
			check(label .. "/" .. name .. ": weld Head -> part", weld.Part0 == head and weld.Part1 == part)
			local c0 = weld.C0.Position
			check(label .. "/" .. name .. ": C0 = placement centre", near(c0.X, pl.centre[1]) and near(c0.Y, pl.centre[2]) and near(c0.Z, pl.centre[3]),
				string.format("%.4f %.4f %.4f vs %.4f %.4f %.4f", c0.X, c0.Y, c0.Z, pl.centre[1], pl.centre[2], pl.centre[3]))
			local s = part.Size
			check(label .. "/" .. name .. ": Size = placement size", near(s.X, math.max(pl.size[1], 0.001)) and near(s.Y, math.max(pl.size[2], 0.001))
				and near(s.Z, math.max(pl.size[3], 0.001)))
			local want = head.CFrame * weld.C0
			check(label .. "/" .. name .. ": part CFrame = Head * C0", (part.CFrame.Position - want.Position).Magnitude < 1e-4)
			-- the mesh as drawn there lies around the head (inside 1.6 head sizes of its centre)
			local mesh = sim.MeshOf(rawget(part, "_meshId"))
			local P = AssetSim.Placed(mesh, { s.X, s.Y, s.Z }, { c0.X, c0.Y, c0.Z })
			local far = 0
			local hs = head.Size.Y
			for i = 1, #P, 3 do
				far = math.max(far, math.sqrt(P[i] ^ 2 + P[i + 1] ^ 2 + P[i + 2] ^ 2) / hs)
			end
			check(label .. "/" .. name .. ": mesh around the head", far < 1.6 or (name:find("Loc") or name:find("Braid") or name:find("Tail")) and far < 3.5,
				string.format("%.2f head sizes", far))
		else
			check(label .. "/" .. name .. ": welded", weld ~= nil)
		end
		-- what HairFX reads
		local mesh = v.mesh
		check(label .. "/" .. name .. ": HairFX points", mesh and mesh.nv and mesh.nv >= 1 and #mesh.P >= 3 * mesh.nv, mesh and mesh.nv)
		local ap = name == "HairCap" and not entry.pieces[name] and Data.cap or entry.pieces[name]
		if ap and ap.hairfx then
			check(label .. "/" .. name .. ": hairfx pivot / tip", mesh.hairfx and #mesh.hairfx.pivot == 3 and #mesh.hairfx.tip == 3
				and mesh.hairfx.kind == (ap.hairfx.kind == "bounce" and "bounce" or "swing"))
		end
	end
	local lms = AC.GetLandmarks(m)
	local nHair = 0
	for _, lm in pairs(lms) do
		if lm.section == "Hair" then
			nHair += 1
		end
	end
	check(label .. ": hair landmarks", nHair > 0, nHair)
end

local function waitBuilt(m, pred, seconds)
	return E.waitFor(function()
		local v = hair(m)
		return v ~= nil and next(v) ~= nil and (pred == nil or pred(v))
	end, seconds or 40)
end

local function entryOf(spec)
	return HA.For(H.Look(spec), "full", true)
end

------------------------------------------------------------------------
-- 1) several looks: asset hair where an entry exists, generated hair where none
------------------------------------------------------------------------
local LOOKS = {
	{ name = "Fade", spec = { g = 1, hair = { style = "High Fade", type = "Kinky", color = 1 } } },
	{ name = "Afro", spec = { g = 1, hair = { style = "Afro", type = "Kinky", color = 2 } } },
	{ name = "Locs", spec = { g = 1, hair = { style = "Dreadlocks", type = "Kinky", color = 1 } } },
	{ name = "Long", spec = { g = 2, hair = { style = "Long Hair", type = "Straight", color = 3 } } },
	{ name = "PreviewAfro", spec = { g = 2, hair = { style = "Afro", type = "Coiled", color = 1 } }, tag = "Preview" },
	{ name = "Afro2", spec = { g = 1, hair = { style = "Afro", type = "Kinky", color = 2 } } }, -- an NPC sharing Afro's tint
}
-- a style no entry draws yet (builders keep adding them): its generated hair, built by the same worker
local noEntry
for _, style in ipairs(H.require("Looks").HairStyles) do
	for _, htype in ipairs({ "Straight", "Wavy" }) do
		local spec = { g = 1, hair = { style = style, type = htype, color = 3 } }
		if not noEntry and style ~= "Bald" and entryOf(spec) == nil then
			noEntry = spec
		end
	end
end
if noEntry then
	table.insert(LOOKS, { name = "NoEntry", spec = noEntry })
	print("no-entry look: " .. noEntry.hair.style .. " / " .. noEntry.hair.type)
else
	print("every style has an asset entry: the no-entry look is skipped (the failure cases still build generated hair)")
end
local looks = {}
for i, L in ipairs(LOOKS) do
	local _, look = boxer(L.name, L.spec, -6 - i * 2, L.tag)
	looks[L.name] = look
end
local t0 = os.clock()
for _, L in ipairs(LOOKS) do
	local m = models[L.name]
	local want = HA.For(looks[L.name], "full", true) ~= nil
	local ok = waitBuilt(m, function(v)
		local a = isAsset(v)
		-- (a preview's first build is the low level: wait for full)
		local lod
		for _, x in pairs(v) do
			lod = x.lod
		end
		return a == want and lod == "full"
	end, 60)
	check(L.name .. ": built (" .. (want and "asset" or "generated") .. ")", ok, ok or tostring(isAsset(hair(m))))
	if want and ok then
		checkPlacement(L.name, m, LookData.Get(m))
	end
end
print(string.format("initial builds: %.1f s wall", os.clock() - t0))
if noEntry then
	check("no entry -> generated pieces", isAsset(hair(models.NoEntry)) == false)
	-- the game's default (generatedHair "focus"): an NPC with no asset hair keeps its round-1 hair, no EditableMesh
	AC.Settings.generatedHair = "focus"
	local meshes0 = sim.made.meshes
	local npc = boxer("NoEntryFocus", noEntry, -40)
	-- (with "all" it is built within a few seconds: waitBuilt would succeed)
	local built = waitBuilt(npc, nil, 20)
	local v = hair(npc)
	check("focus: an NPC without asset hair builds no generated hair", not built and (v == nil or next(v) == nil), v and count(v))
	check("focus: no EditableMesh made for it", sim.made.meshes == meshes0, sim.made.meshes - meshes0)
	local pv = boxer("NoEntryPreview", noEntry, -42, "Preview")
	local okP = waitBuilt(pv, function(view)
		return isAsset(view) == false
	end, 60)
	check("focus: a preview without asset hair still gets the generated hair", okP)
	for _, m in ipairs({ npc, pv }) do
		models[m.Name] = nil
		m:Destroy()
	end
	E.step(5)
	AC.Settings.generatedHair = "all"
end
do
	-- NPCs of one colour share the tinted card texture; a preview keeps its own image (HairFX may wet it)
	local a, b = hair(models.Afro), hair(models.Afro2)
	local function texOf(view, name)
		return view and view[name] and view[name].part.TextureContent and view[name].part.TextureContent.object
	end
	local cardName
	for name in pairs(a or {}) do
		if name ~= "HairCap" then
			cardName = name
			break
		end
	end
	check("NPC tints shared", cardName ~= nil and texOf(a, cardName) ~= nil and texOf(a, cardName) == texOf(b, cardName))
	local pv = hair(models.PreviewAfro)
	local owners = 0
	for _, v in pairs(pv or {}) do
		owners += v.image and 1 or 0
	end
	check("preview: private images carried for HairFX", owners >= 1, owners)
end
noLeaks("after the first builds")

-- an idle scheduler: no job running (the failure tests count engine calls)
local function idle()
	return E.waitFor(function()
		for _, m in pairs(models) do
			if m.Parent and hair(m) == nil then
				return false
			end
		end
		return true
	end, 30)
end
idle()
E.step(30)

------------------------------------------------------------------------
-- 2) a look change mid-build cancels the job: nothing kept, the new look built
------------------------------------------------------------------------
do
	local m, look = boxer("Cancel", { g = 1, hair = { style = "Afro", type = "Kinky", color = 4 } }, -30)
	local calls, fired = 0, false
	local newLook = H.Look({ g = 1, hair = { style = "Afro", type = "Kinky", color = 6 } })
	sim.onCall = function(kind)
		if kind == "mesh" then
			calls += 1
			if calls == 3 and not fired then
				fired = true
				LookData.Publish(m, newLook)
			end
		end
	end
	local ok = waitBuilt(m, function(v)
		local any = next(v)
		local part = any and v[any].part
		local r, g, b = HK.MidColor(HK.Palette(newLook, select(2, H.require("AnatomyHair").Resolve(newLook))))
		return isAsset(v) and part and near(part.Color.R, r, 0.01) and near(part.Color.G, g, 0.01) and near(part.Color.B, b, 0.01)
	end, 40)
	sim.onCall = nil
	check("cancel: the look change hit mid-build", fired)
	check("cancel: the new look's asset hair built", ok)
	noLeaks("after a cancelled build")
	if ok then
		checkPlacement("Cancel", m, LookData.Get(m))
	end
	local _ = look
end

------------------------------------------------------------------------
-- 3) the model goes away mid-build: everything made is destroyed
------------------------------------------------------------------------
do
	local m = boxer("Gone", { g = 1, hair = { style = "Dreadlocks", type = "Kinky", color = 3 } }, -32)
	local calls, fired = 0, false
	sim.onCall = function(kind)
		if kind == "mesh" then
			calls += 1
			if calls == 4 and not fired then
				fired = true
				m:Destroy()
			end
		end
	end
	E.waitFor(function()
		return fired
	end, 30)
	E.step(20)
	sim.onCall = nil
	check("removed: destroyed mid-build", fired and m.Parent == nil)
	check("removed: no pieces", hair(m) == nil)
	noLeaks("after a model removed mid-build")
end

------------------------------------------------------------------------
-- 4) a mesh that 404s: the same job draws the generated hair; the id is skipped from then on
------------------------------------------------------------------------
local twists = { g = 1, hair = { style = "Twists", type = "Kinky", color = 1 } }
do
	local entry = entryOf(twists)
	check("twists: has an entry", entry ~= nil)
	if entry then
		local names = {}
		for name in pairs(entry.pieces) do
			names[#names + 1] = name
		end
		table.sort(names)
		local id = HK.Id(entry.pieces[names[#names]].mesh)
		sim.fail.mesh[id] = "HTTP 404 (Not Found)"
		local before = sim.made.parts
		local m = boxer("Twists404", twists, -34)
		local ok = waitBuilt(m, function(v)
			return isAsset(v) == false
		end, 60)
		check("404: generated hair built instead", ok, tostring(isAsset(hair(m))))
		check("404: asset parts were attempted", sim.made.parts - before > 1)
		check("404: id marked failed (not transient)", HA._failed[id] ~= nil and HA._failed[id].transient == false)
		check("404: entry skipped now", entryOf(twists) == nil)
		check("404: no retry waits", HA.Waiting(H.Look(twists), "full", true) == nil)
		noLeaks("after a 404")
		sim.fail.mesh[id] = nil
	end
end

------------------------------------------------------------------------
-- 5) every id 0 (nothing uploaded yet): no entry is usable, the generated hair everywhere
------------------------------------------------------------------------
do
	local saved = {}
	local function zero(t, key)
		saved[#saved + 1] = { t, key, t[key] }
		t[key] = 0
	end
	for _, e in ipairs(Data.entries) do
		for _, p in pairs(e.pieces) do
			zero(p, "mesh")
		end
	end
	if Data.cap then
		zero(Data.cap, "mesh")
	end
	for _, t in pairs(Data.textures) do
		zero(t, "id")
	end
	check("ids 0: nothing usable", HA.Stats().usable == 0, HA.Stats().usable)
	local spec = { g = 1, hair = { style = "Afro", type = "Kinky", color = 5 } }
	check("ids 0: no entry for an afro", entryOf(spec) == nil)
	local calls0 = sim.calls.image
	local m = boxer("Zero", spec, -36)
	local ok = waitBuilt(m, function(v)
		return isAsset(v) == false
	end, 60)
	check("ids 0: generated hair", ok)
	check("ids 0: no asset image loaded", sim.calls.image == calls0)
	noLeaks("with every id 0")
	for i = #saved, 1, -1 do
		local s = saved[i]
		s[1][s[2]] = s[3]
	end
	check("ids restored", HA.Stats().usable > 0)
end

------------------------------------------------------------------------
-- 6) the EditableImage budget: CreateEditableImage returns nil -> kind "tex": textures pause, generated hair
------------------------------------------------------------------------
do
	sim.nilImage = true
	local spec = { g = 1, hair = { style = "Afro", type = "Kinky", color = 3 } }
	local m = boxer("NoImage", spec, -38)
	local ok = waitBuilt(m, function(v)
		return isAsset(v) == false
	end, 60)
	sim.nilImage = false
	check("image budget: generated hair built", ok, tostring(isAsset(hair(m))))
	local anyImg = false
	for _, v in pairs(hair(m) or {}) do
		anyImg = anyImg or v.image ~= nil
	end
	check("image budget: textures paused (vertex colours)", not anyImg)
	check("image budget: no asset id blamed", #HA.Stats().failedIds == 1, table.concat(HA.Stats().failedIds, ","))
	noLeaks("after the image budget")
end

------------------------------------------------------------------------
-- the asset hair already built is untouched by all of it; Stop frees everything
------------------------------------------------------------------------
check("afro still asset hair", isAsset(hair(models.Afro)) == true)
check("fade still asset hair", isAsset(hair(models.Fade)) == true)
local st = HA.Stats()
print(string.format("HairAssets: built %d, failed builds %d, failed ids [%s], shared tints %d, private %d; engine: %d parts, %d images, %d meshes made",
	st.built, st.failedBuilds, table.concat(st.failedIds, ","), st.sharedTints, st.privateTints, sim.made.parts, sim.made.images, sim.made.meshes))
AC.Stop()
E.step(5)
check("stop: no parts left", sim.live.parts == 0, sim.live.parts)
check("stop: no images left", sim.live.images == 0, sim.live.images)
check("stop: no EditableMeshes left", sim.live.meshes == 0, sim.live.meshes)
check("stop: no shared tints left", HA.SharedBytes() == 0)

print(string.format("test_hairassets_e2e: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_hairassets_e2e failed")
end
