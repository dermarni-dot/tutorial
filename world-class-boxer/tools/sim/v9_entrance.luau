--!nocheck
-- v9_entrance.luau: the pre-fight ring walk as the game plays it, for tools/sim/v9_entrance_render.py
-- (previews/final/v9/entrance). Nothing is posed by hand:
--   * the boxer is built by the server's Builder.Cosmetics on the fake R15 rig of v8_scene / v9_anim (tier body, classic
--     head with its drawn face decal, headgear, gloves, trunks) with his robe on (Builder.SetRobe, off on the robe beat);
--     the coach is Officials.Look "cornerman" in the red corner's polo (the server's entourage)
--   * the plan and the beats are Shared.Entrance's (Entrance.Plan / Timeline); the fighter is moved the way RingWalk +
--     the walker's client move him (Place on the steps / ropes beats, a walk to the steps and to the corner)
--   * the poses are the REAL client Animator (src/client/Animator.client.lua with its AnimEntrance hook) on a virtual
--     clock; the carriers and the belt are BoxerClient.EntranceFX's own figures; every shot's camera is EntranceFX.Shot
--   * the venue is the Grand Arena of tools/sim/world_scene.luau (--world: its scene.json), the anchors read from it
-- Output: <out>/index.json { shots = [{ id, label, file, camera = { cf, fov }, focus }], gifs = [{ id, label, frames }] },
-- <out>/<id>.json { figures = [{ name, role, meshes, head, parts }], camera, focus }.
--
--   lune run tools/sim/v9_entrance.luau --world DIR/scene.json [--out DIR] [--src DIR] [--only story,gif]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local ltask = require("@lune/task")
local Host = require("./host")
local AssetSim = require("./assetsim")
local FE = require("./fakeengine")
local MeshV2 = require("./meshv2")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad"

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		args[a[i]:gsub("^%-%-", "")] = a[i + 1]
		i += 2
	end
end
local OUT = (args.out or (SCRATCH .. "/v9entrance")):gsub("/$", "")
local ONLY = {}
for s in (args.only or "story,gif"):gmatch("[^,]+") do
	ONLY[s] = true
end

------------------------------------------------------------------------
-- host (as v9_anim.luau)
------------------------------------------------------------------------
local root = Host.FindRoot()
local srcDir = args.src or (root .. "/src")
local MANIFEST = AssetSim.LOCAL_MANIFEST
AssetSim.EnsureManifest(root, MANIFEST)
local E = FE.new()
local sim = AssetSim.new({ root = root, manifest = MANIFEST, newPart = function()
	return E.new("MeshPart")
end })
local VT = 1000
local fakeOs = setmetatable({ clock = function()
	return VT
end }, { __index = os })
local RaycastParams = { new = function()
	return { FilterDescendantsInstances = {} }
end }
local H = Host.new({ root = root, src = srcDir, globals = { Content = sim.Content, Instance = E.Instance, workspace = E.workspace,
	Workspace = E.workspace, os = fakeOs, RaycastParams = RaycastParams, OverlapParams = RaycastParams,
	time = function()
		return VT
	end } })
E.install(H)
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)

local floorPart = E.new("Part", E.workspace)
floorPart.Name = "Floor"
floorPart.Size = Vector3.new(200, 1, 200)
floorPart.CFrame = CFrame.new(0, -0.5, 0)
floorPart.Anchored = true
E.workspace.Raycast = function(_, origin, dir)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 and dir.Y < 0 then
		local k = origin.Y / -dir.Y
		return { Position = origin + dir * k, Normal = Vector3.new(0, 1, 0), Instance = floorPart, Material = roblox.Enum.Material.Plastic,
			Distance = (dir * k).Magnitude }
	end
	return nil
end
E.workspace.GetPartBoundsInRadius = function()
	return {}
end
E.workspace.GetPartBoundsInBox = function()
	return {}
end
E.workspace.GetPartsInPart = function()
	return {}
end
E.camera.WorldToViewportPoint = function()
	return Vector3.new(400, 300, 5), true
end
E.camera.ViewportSize = roblox.Vector2.new(800, 600)
E.camera.FieldOfView = 70

local Looks = H.require("Looks")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderBody = H.require("BuilderBody")
local BuilderHair = H.require("BuilderHair")
local Builder = H.require("Builder")
local BuilderGear = H.require("BuilderGear")
local Kit = H.require("AnatomyHairKit")
local okOff, Officials = pcall(H.require, "Officials")
if not okOff then
	Officials = nil
end
local REAL = BodyTiers.Data()

local MESH_FILES = {}
do
	local up = root .. "/tools/body/uploaded.json"
	for _, e in pairs(serde.decode("json", fs.readFile(up))) do
		if type(e.file) == "string" and type(e.id) == "number" then
			MESH_FILES[e.id] = root .. "/tools/body/" .. e.file
		end
	end
	local side = (args.gear or ""):gsub("%.lua$", "") .. ".ids.json"
	if args.gear and fs.isFile(side) then
		for id, f in pairs(serde.decode("json", fs.readFile(side)).ids or {}) do
			MESH_FILES[tonumber(id)] = f
		end
	end
end
local FACE_FILES = {}
do
	local FACE_JSON = {}
	local fj = root .. "/tools/body/out/faces/faces.json"
	if fs.isFile(fj) then
		for _, e in ipairs(serde.decode("json", fs.readFile(fj)).faces or {}) do
			FACE_JSON[e.key] = e.file
		end
	end
	for _, f in ipairs(REAL.faces or {}) do
		if f.id and f.id ~= 0 then
			FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/" .. (FACE_JSON[f.key] or ("face_" .. f.key .. ".png"))
		end
	end
end
do
	local path = args.gear or (srcDir .. "/shared/GearAssetData.lua")
	BuilderGear.SetData(luau.load(fs.readFile(path), { debugName = path })())
end

------------------------------------------------------------------------
-- the fake R15 rig (v9_anim.luau's)
------------------------------------------------------------------------
local BLOCK = {
	UpperTorso = { size = { 2, 1.6, 1 }, att = { NeckRigAttachment = { 0, 0.8, 0 }, WaistRigAttachment = { 0, -0.8, 0 }, LeftShoulderRigAttachment = { -1, 0.563, 0 }, RightShoulderRigAttachment = { 1, 0.563, 0 } } },
	LowerTorso = { size = { 2, 0.4, 1 }, att = { WaistRigAttachment = { 0, 0.2, 0 }, LeftHipRigAttachment = { -0.5, -0.2, 0 }, RightHipRigAttachment = { 0.5, -0.2, 0 }, RootRigAttachment = { 0, -0.2, 0 } } },
}
for _, side in ipairs({ "Left", "Right" }) do
	local sx = side == "Left" and -1 or 1
	BLOCK[side .. "UpperArm"] = { size = { 1, 1.169, 1 }, att = { [side .. "ShoulderRigAttachment"] = { -0.5 * sx, 0.394, 0 }, [side .. "ElbowRigAttachment"] = { 0, -0.334, 0 } } }
	BLOCK[side .. "LowerArm"] = { size = { 1, 1.052, 1 }, att = { [side .. "ElbowRigAttachment"] = { 0, 0.192, 0 }, [side .. "WristRigAttachment"] = { 0, -0.501, 0 } } }
	BLOCK[side .. "Hand"] = { size = { 1, 0.3, 1 }, att = { [side .. "WristRigAttachment"] = { 0, 0.125, 0 } } }
	BLOCK[side .. "UpperLeg"] = { size = { 1, 1.217, 1 }, att = { [side .. "HipRigAttachment"] = { 0, 0.421, 0 }, [side .. "KneeRigAttachment"] = { 0, -0.408, 0 } } }
	BLOCK[side .. "LowerLeg"] = { size = { 1, 1.193, 1 }, att = { [side .. "KneeRigAttachment"] = { 0, 0.2, 0 }, [side .. "AnkleRigAttachment"] = { 0, -0.547, 0 } } }
	BLOCK[side .. "Foot"] = { size = { 1, 0.3, 1 }, att = { [side .. "AnkleRigAttachment"] = { 0, 0.085, 0 } } }
end
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" }, Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" }, RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" }, RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" }, RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" }, RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" }, RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" }, RightAnkle = { "RightLowerLeg", "RightFoot" },
}
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

local weldOffsets = setmetatable({}, { __mode = "k" })
local jointCache = setmetatable({}, { __mode = "k" })
local homeCF = setmetatable({}, { __mode = "k" })
local function solve(model, keepRoot)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not keepRoot then
		hrp.CFrame = (homeCF[model] or CFrame.new()) * CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
	end
	local joints = jointCache[model]
	if not joints or not keepRoot then
		joints = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.ClassName == "Motor6D" or d.ClassName == "Weld" or (d.ClassName == "WeldConstraint" and weldOffsets[d]) then
				table.insert(joints, d)
			end
		end
		jointCache[model] = joints
	end
	local done = { [hrp] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(joints) do
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 and done[p0] and not done[p1] then
				if j.ClassName == "WeldConstraint" then
					p1.CFrame = p0.CFrame * weldOffsets[j]
				else
					local t = j.ClassName == "Motor6D" and j.Transform or nil
					p1.CFrame = p0.CFrame * j.C0 * (t or CFrame.new()) * j.C1:Inverse()
				end
				done[p1] = true
				progress = true
			end
		end
	end
end
local function recordWelds(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "WeldConstraint" and d.Part0 and d.Part1 then
			weldOffsets[d] = d.Part0.CFrame:Inverse() * d.Part1.CFrame
		end
	end
	jointCache[model] = nil
end

local STATE = { Running = roblox.Enum.HumanoidStateType.Running }
local function newRig(scale, headSize)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.Transparency = 1
	hrp.AssemblyLinearVelocity = Vector3.zero
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(name, size, orig, atts)
		local p = E.new("MeshPart", model)
		p.Name = name
		p.Size = size
		p.Color = roblox.Color3.new(1, 1, 1)
		local o = E.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = orig
		for an, pos in pairs(atts) do
			local a = E.new("Attachment", p)
			a.Name = an
			a.Position = pos.cur
			local op = E.new("Vector3Value", a)
			op.Name = "OriginalPosition"
			op.Value = pos.orig
		end
		return p
	end
	for name, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = { cur = v3(pos) * scale, orig = v3(pos) }
		end
		addPart(name, v3(b.size) * scale, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(headSize, headSize, headSize), Vector3.new(1.2, 1.2, 1.2),
		{ NeckRigAttachment = { cur = Vector3.new(0, -0.5 * headSize, 0), orig = Vector3.new(0, -0.6, 0) } })
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		m.Transform = CFrame.new()
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	hum.Sit = false
	hum.MoveDirection = Vector3.zero
	hum.WalkSpeed = 16
	hum.GetState = function()
		return STATE.Running
	end
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local name = enum.Name
		local old = model:FindFirstChild(name)
		if name ~= "Head" then
			local o = part:FindFirstChild("OriginalSize")
			if o then
				part.Size = o.Value * scale
			end
			for _, a in ipairs(part:GetChildren()) do
				if a.ClassName == "Attachment" then
					local op = a:FindFirstChild("OriginalPosition")
					if op then
						a.Position = op.Value * scale
					end
				end
			end
		end
		for _, m in ipairs(model:GetDescendants()) do
			if m.ClassName == "Motor6D" then
				if m.Part0 == old then
					m.Part0 = part
				end
				if m.Part1 == old then
					m.Part1 = part
					m.Parent = part
				end
			end
		end
		part.Parent = model
		old:Destroy()
		solve(model)
		return true
	end
	solve(model)
	return model, hum
end

BuilderTiers.Reset()
BuilderTiers.Services = {
	AssetService = { CreateMeshPartAsync = function(_, content)
		local u = type(content) == "table" and (content.uri or content.Uri) or tostring(content)
		local id = tonumber(tostring(u):match("(%d+)%s*$"))
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. tostring(id)
		return mp
	end },
	Content = sim.Content,
}
BuilderGear.Reset()
BuilderGear.Services = BuilderTiers.Services

local currentModel
local function solving(mod, key)
	local f = mod[key]
	mod[key] = function(model, ...)
		if model == currentModel then
			solve(model)
		end
		return f(model, ...)
	end
end
solving(BuilderBody, "Colors")
solving(BuilderBody, "Muscles")
solving(BuilderBody, "Attire")
solving(BuilderBody, "Hands")
solving(BuilderHair, "Build")

local function buildOf(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
local function buildFor(app, tier)
	for v = 0, 100 do
		local t = Builder.Tiers(app, buildOf(v))
		if BodyTiers.Key(t) == string.rep(tostring(tier), 14) then
			return buildOf(v + (tier > 1 and 2 or 0))
		end
	end
	error("no build gives tier " .. tier)
end
local function pal(i)
	local c = Looks.Palette[i]
	return { c[1], c[2], c[3] }
end

-- build a figure on the fake rig with Builder.Cosmetics (exactly as Builder.CreateNPC does after the description)
local function makeFigure(app, b, gear, opts, at)
	local sc = Builder.Scales(app, b, opts)
	local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	homeCF[model] = at
	model.Parent = E.workspace
	currentModel = model
	local ok, err = pcall(Builder.Cosmetics, model, app, b, gear, opts)
	if not ok then
		error("Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	recordWelds(model)
	currentModel = nil
	return model, hum
end

local function boxer(tier, spec, at)
	local app = Looks.Defaults(1)
	app.skin = spec.skin
	app.body.frame = "Athletic"
	app.gloves.color = pal(spec.gloves)
	app.attire.trunks = pal(spec.trunks)
	app.attire.trim = pal(spec.trim)
	local m = makeFigure(app, buildFor(app, tier), nil, { hands = "gloves", detail = "full" }, at)
	m.Name = spec.name
	return m
end

-- the official's look: the game's (Officials.Look) or FightEngine's SpawnReferee before it existed
local function officialLook(seed, kind, champ)
	if Officials and Officials.Look then
		return Officials.Look(seed, kind, { championship = champ, venue = champ and "Stadium" or "ClubArena" })
	end
	local rng = (H.globals.Random or roblox.Random).new(seed)
	local spar = kind == "cornerman"
	local s = 9000 + rng:NextInteger(1, 50000)
	local age = spar and rng:NextInteger(45, 62) or rng:NextInteger(38, 58)
	local app = Looks.Random(s, 1, {})
	local b = Looks.RandomBuild(s, spar and 0.35 or 0.2, age)
	return app, b, {}, { detail = "medium", outfit = kind, hands = "bare", age = age, name = "", nick = "", waistText = "" }
end

-- the ring walk's modules, loaded before the Animator's thread starts (it requires AnimEntrance itself: one load)
local Entrance = H.require("Entrance")
local AE = H.require("AnimEntrance")
-- (EntranceFX loads the UI kit for its overlay: the tween types it reads at load time)
H.globals.TweenInfo = H.globals.TweenInfo or { new = function(...)
	return { ... }
end }
local okFX, FX = pcall(H.require, "EntranceFX")
if not okFX then
	error("EntranceFX failed to load: " .. tostring(FX))
end
local TOOLS = FX._tools

------------------------------------------------------------------------
-- the Animator
------------------------------------------------------------------------
local CS = E.CollectionService
local player = E.localPlayer
H.Service("Players")._props.GetPlayers = function()
	return { player }
end
H.Service("Players")._props.GetPlayerFromCharacter = function()
	return nil
end
player.CharacterAdded = FE.Signal()
local PreSim = FE.Signal()
H.Service("RunService")._props.PreSimulation = PreSim
do
	local file = srcDir .. "/client/Animator.client.lua"
	local env = table.clone(H.globals)
	env.script = { Parent = H.client.Parent, Name = "Animator" }
	ltask.spawn(luau.load(fs.readFile(file), { debugName = "Animator.client.lua", environment = env }))
end
local DT = 1 / 60
local function frame(models)
	VT += DT
	PreSim:Fire(DT)
	for _, m in ipairs(models) do
		solve(m, true)
	end
	ltask.wait()
end

------------------------------------------------------------------------
-- export
------------------------------------------------------------------------
local function r4(x)
	return math.floor(x * 10000 + 0.5) / 10000
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
local function cfList(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r4(x), r4(y), r4(z), r4(r00), r4(r01), r4(r02), r4(r10), r4(r11), r4(r12), r4(r20), r4(r21), r4(r22) }
end
local function color(c)
	return c and { r4(c.R), r4(c.G), r4(c.B) } or { 0.8, 0.8, 0.8 }
end
local meshCache = {}
local function meshOf(file)
	local m = meshCache[file]
	if not m then
		m = MeshV2.Read(file)
		local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
		m.b = { cx, cy, cz, bx, by, bz }
		meshCache[file] = m
	end
	return m
end
local function worldMesh(p, file)
	local m = meshOf(file)
	local cx, cy, cz, bx, by, bz = table.unpack(m.b)
	local s = p.Size
	local kx, ky, kz = s.X / bx, s.Y / by, s.Z / bz
	local cf = p.CFrame
	local P, N = table.create(#m.P), table.create(#m.N)
	for i = 1, #m.P, 3 do
		local w = cf * Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz)
		P[i], P[i + 1], P[i + 2] = r4(w.X), r4(w.Y), r4(w.Z)
		local n = cf:VectorToWorldSpace(Vector3.new(m.N[i] / kx, m.N[i + 1] / ky, m.N[i + 2] / kz)).Unit
		N[i], N[i + 1], N[i + 2] = r4(n.X), r4(n.Y), r4(n.Z)
	end
	return P, N, m.T
end
local function fileOf(p)
	local gid = p:GetAttribute("GearMesh")
	if gid then
		return MESH_FILES[gid]
	end
	local tier = p:GetAttribute("BodyTier")
	if tier then
		local lite = p:GetAttribute("BodyLite") == true
		return string.format("%s/tools/body/out/%stier%d/%s.mesh", root, lite and "lite/" or "", tier, p.Name)
	end
	return nil
end
local function exportFigure(model, role)
	local fr = { name = model.Name, role = role, meshes = {}, parts = {} }
	for _, p in ipairs(model:GetDescendants()) do
		local cls = p.ClassName
		if not (cls == "Part" or cls == "MeshPart" or cls == "WedgePart") or p.Name == "HumanoidRootPart" then
			continue
		end
		if (p.Transparency or 0) >= 0.99 then
			continue
		end
		local file = cls == "MeshPart" and fileOf(p)
		if file then
			local P, N, T = worldMesh(p, file)
			table.insert(fr.meshes, { name = p.Name, gear = p:GetAttribute("GearMesh") ~= nil, slot = p:GetAttribute("GearSlot"), p = P, n = N,
				t = T, color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0 })
		elseif cls == "MeshPart" and p:GetAttribute("GearMesh") then
			error("no mesh file for gear id " .. tostring(p:GetAttribute("GearMesh")) .. " (" .. p.Name .. ")")
		elseif p.Name == "Head" and p:FindFirstChildOfClass("SpecialMesh") then
			local decal = p:FindFirstChild("face")
			fr.head = { cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color),
				material = enumName(p.Material), classic = Kit.CLASSIC,
				decal = decal and { texture = decal.Texture, file = FACE_FILES[decal.Texture], face = enumName(decal.Face) } or nil }
		else
			local shape = cls == "WedgePart" and "Wedge" or "Block"
			if p:FindFirstChildOfClass("SpecialMesh") then
				local mt = enumName(p:FindFirstChildOfClass("SpecialMesh").MeshType)
				shape = mt == "Sphere" and "Ellipsoid" or mt
			elseif p.Shape then
				shape = enumName(p.Shape)
			end
			table.insert(fr.parts, { name = p.Name, folder = p.Parent and p.Parent.Name or "?", shape = shape, cf = cfList(p.CFrame),
				size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color), material = enumName(p.Material),
				reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
		end
	end
	return fr
end

------------------------------------------------------------------------
-- the venue: the Grand Arena's anchors from the world dump (floor moved to y = 0: the renderer moves the venue the
-- same way), the ring's canvas a surface the feet stand on
------------------------------------------------------------------------
assert(args.world, "--world <scene.json of tools/sim/world_scene.luau --only venues>")
local world = serde.decode("json", fs.readFile(args.world))
local VROOT = world.roots.venue_Arena
local ANCH = {}
for _, p in ipairs(VROOT.parts) do
	if p.n and (p.n:find("Entrance$") or p.n:find("Steps$") or p.n:find("Corner$") or p.n == "RingCenter") and p.s[1] == 1 then
		ANCH[p.n] = Vector3.new(p.cf[1], p.cf[2], p.cf[3])
	end
end
local FLOOR_Y = ANCH.RedEntrance.Y
for k, v in pairs(ANCH) do
	ANCH[k] = v - Vector3.new(0, FLOOR_Y, 0)
end
local CENTRE = ANCH.RingCenter
local HALF, RH = 12, CENTRE.Y
local function surfaceY(x, z)
	if math.abs(x - CENTRE.X) <= HALF + 3.2 and math.abs(z - CENTRE.Z) <= HALF + 3.2 then
		return RH
	end
	return 0
end
E.workspace.Raycast = function(_, origin, dir)
	local y = surfaceY(origin.X, origin.Z)
	if origin.Y >= y and origin.Y + dir.Y <= y and dir.Y < 0 then
		local k = (origin.Y - y) / -dir.Y
		return { Position = origin + dir * k, Normal = Vector3.new(0, 1, 0), Instance = floorPart, Material = roblox.Enum.Material.Plastic, Distance = (dir * k).Magnitude }
	end
	return nil
end
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
-- RingWalk.Points for the red corner
local function points(corner)
	local steps, cornerPos = ANCH[corner .. "Steps"], ANCH[corner .. "Corner"]
	local dir = flat(steps - CENTRE).Unit
	local diag = flat(cornerPos - CENTRE)
	return {
		centre = CENTRE, entrance = ANCH[corner .. "Entrance"], steps = steps, corner = cornerPos,
		apron = CENTRE + dir * (HALF + 1.7), inside = CENTRE + dir * (HALF - 1.6), post = CENTRE + diag.Unit * (HALF * math.sqrt(2)), half = HALF,
	}
end
local PTS = points("Red")

local function run(models, seconds)
	if models[1] then
		E.camera.CFrame = CFrame.new(models[1]:FindFirstChild("HumanoidRootPart").Position + Vector3.new(0, 4, 9))
	end
	for _ = 1, math.floor(seconds / DT + 0.5) do
		frame(models)
	end
end

------------------------------------------------------------------------
-- the cast
------------------------------------------------------------------------
local Builder2 = H.require("Builder")
local function boxer(tier, at)
	local app = Looks.Defaults(1)
	app.skin = 6
	app.body.frame = "Athletic"
	app.gloves.color = pal(1)
	app.attire.trunks = pal(1)
	app.attire.trim = pal(5)
	app.attire.robe = pal(1)
	app.attire.robeTrim = { 240, 240, 240 }
	local opts = { hands = "gloves", detail = "full", name = "Marcus Reed", nick = "The Hammer", robe = "Classic", fightNight = true }
	local m = makeFigure(app, buildFor(app, tier), nil, opts, at)
	m.Name = "Walker"
	currentModel = m
	pcall(Builder2.SetRobe, m, app, true, opts)
	solve(m)
	recordWelds(m)
	currentModel = nil
	m:SetAttribute("Guard", "walkout")
	m:SetAttribute("Style", "BoxerPuncher")
	CS:AddTag(m, "Fighter")
	return m, app, opts
end
local function coach(at)
	local app, b, gear, opts = officialLook(7, "cornerman", false)
	if Officials and Officials.Look then
		app, b, gear, opts = Officials.Look(7, "cornerman", { team = { 150, 26, 32 }, venue = "Arena" })
	end
	local m = makeFigure(app, b, gear, opts, at)
	m.Name = "Coach"
	m:SetAttribute("Loop", "walk")
	CS:AddTag(m, "Ambient")
	return m
end

------------------------------------------------------------------------
-- moving them as RingWalk and the walker's client do
------------------------------------------------------------------------
local function standOf(model)
	return AE.Geom(model).stand
end
local function placeAt(model, pos, lookAt)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y = pos.Y + standOf(model)
	local p = Vector3.new(pos.X, y, pos.Z)
	local l = Vector3.new(lookAt.X, y, lookAt.Z)
	hrp.CFrame = CFrame.lookAt(p, l)
	hrp.AssemblyLinearVelocity = Vector3.zero
	model:FindFirstChildOfClass("Humanoid").MoveDirection = Vector3.zero
end
-- one frame of a MoveTo: glide toward the target at the speed, facing the way it goes
local function walkStep(model, target, speed)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not target then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hum.MoveDirection = Vector3.zero
		return
	end
	local pos = hrp.Position
	local d = flat(target - pos)
	local m = d.Magnitude
	local y = surfaceY(pos.X, pos.Z) + standOf(model)
	if m < 0.08 then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hum.MoveDirection = Vector3.zero
		hrp.CFrame = CFrame.new(pos.X, y, pos.Z) * (hrp.CFrame - hrp.CFrame.Position)
		return
	end
	local u = d / m
	local step = math.min(m, speed * DT)
	local np = Vector3.new(pos.X + u.X * step, y, pos.Z + u.Z * step)
	hrp.CFrame = CFrame.lookAt(np, np + u)
	hrp.AssemblyLinearVelocity = u * speed
	hum.MoveDirection = u
end

local index = { about = "v9 entrance: the ring walk (Shared.Entrance beats, the client Animator + AnimEntrance, EntranceFX's camera / carriers / belt), world space, studs, +Y up",
	shots = {}, gifs = {}, venue = { root = "venue_Arena", floorY = FLOOR_Y } }
Host.MkDir(OUT)

local function exportParts(folderName)
	local out = {}
	local f = E.workspace:FindFirstChild(folderName)
	if not f then
		return out
	end
	for _, p in ipairs(f:GetDescendants()) do
		if p.ClassName == "Part" and (p.Transparency or 0) < 0.99 then
			table.insert(out, { name = p.Name, folder = folderName, shape = p.Shape and enumName(p.Shape) or "Block", cf = cfList(p.CFrame),
				size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0, transparency = 0 })
		end
	end
	return out
end

local function shoot(id, label, figs, cam, focus, extra)
	local out = { id = id, label = label, figures = {}, camera = { cf = cfList(cam), fov = 70 }, focus = { focus.X, focus.Y, focus.Z } }
	for _, f in ipairs(figs) do
		table.insert(out.figures, exportFigure(f[1], f[2]))
	end
	local props = { name = "Props", role = "props", meshes = {}, parts = {} }
	for _, fname in ipairs({ "EntranceCarriers", "EntranceBelt" }) do
		for _, p in ipairs(exportParts(fname)) do
			table.insert(props.parts, p)
		end
	end
	if #props.parts > 0 then
		table.insert(out.figures, props)
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	Host.WriteJSON(OUT .. "/" .. id .. ".json", out)
	table.insert(index.shots, { id = id, label = label, file = id .. ".json" })
	print("shot", id, label)
end

-- one walk, beat by beat: shots = { [beatId] = { { at = s into the beat, id, label } } }; gif = { beat, from, to, every }
local function runWalk(walker, team, plan, shots, gif)
	local beats, total = Entrance.Timeline(plan)
	local t0 = VT
	local st = AE.Start(walker, plan, t0)
	local w = { plan = plan, model = walker, you = true, t0 = t0, beats = beats, total = total }
	local models = { walker }
	for _, m in ipairs(team) do
		table.insert(models, m)
	end
	local lastBeat
	local target, speed
	local gifFrames = {}
	local nFrames = math.floor((total + 0.2) / DT)
	for i = 1, nFrames do
		local now = VT + DT
		local el = now - t0
		local beat, _, bt = Entrance.BeatAt(beats, el)
		local id = beat and beat.id or "end"
		if id ~= lastBeat then
			lastBeat = id
			w.camKey = nil
			-- the server's Place and the walker's MoveTo on the beat
			if id == "aisle" then
				target, speed = plan.pts.steps, plan.speed
			elseif id == "setdown" then
				placeAt(walker, plan.pts.steps, CENTRE)
				target, speed = nil, plan.speed
			elseif id == "steps" then
				placeAt(walker, plan.pts.apron, CENTRE)
				target = nil
				for k, m in ipairs(team) do
					local side = flat(plan.pts.steps - CENTRE):Cross(Vector3.yAxis).Unit
					placeAt(m, plan.pts.steps + side * (k == 1 and -3.2 or 3.2), CENTRE)
					m:SetAttribute("Loop", "coachwatch")
				end
			elseif id == "ropes" then
				placeAt(walker, plan.pts.inside, CENTRE)
				target = nil
			elseif id == "ring" then
				target, speed = plan.pts.corner, Entrance.SPEED.ring
			elseif id == "robe" then
				target = nil
			end
		end
		if id == "robe" and bt >= 0.5 and not w.robeOff then
			w.robeOff = true
			currentModel = walker
			pcall(Builder2.SetRobe, walker, walker:GetAttribute("App") or {}, false)
			local robe = walker:FindFirstChild("Robe", true)
			if robe then
				robe:Destroy()
			end
			solve(walker)
			recordWelds(walker)
			currentModel = nil
		end
		walkStep(walker, target, speed or plan.speed)
		-- the team behind him through the aisle
		if id == "tunnel" or id == "aisle" or id == "crowd" or id == "setdown" then
			local cf = walker:FindFirstChild("HumanoidRootPart").CFrame
			for k, m in ipairs(team) do
				local slot = ({ Vector3.new(-2.1, 0, 2.6), Vector3.new(2.1, 0, 2.9) })[k]
				local goal = cf:PointToWorldSpace(slot)
				walkStep(m, (flat(goal - m:FindFirstChild("HumanoidRootPart").Position).Magnitude > 0.4) and goal or nil, (speed or plan.speed) * 1.1)
			end
		else
			for _, m in ipairs(team) do
				walkStep(m, nil, 0)
			end
		end
		-- (the Animator culls by the distance to the camera: the camera rides with the walk, as EntranceFX's shot does)
		E.camera.CFrame = CFrame.new(walker:FindFirstChild("HumanoidRootPart").Position + Vector3.new(0, 4, 9))
		frame(models)
		-- EntranceFX's carriers and belt from the same frame
		local fr = AE.Frame(st, VT)
		local r = walker:FindFirstChild("HumanoidRootPart")
		local geo = AE.Geom(walker)
		if plan.carry and (fr.mode == "carried" or fr.mode == "setdown") then
			TOOLS.ensureCarriers(w, geo, 4)
			local down = fr.mode == "setdown" and AE.smooth(fr.bt / ((fr.dur or 1) * 0.8)) or 0
			TOOLS.updateCarriers(w, r.CFrame, geo, DT, 1 - down, AE.bump(down, 0, 1) * 0.5, fr.mode == "setdown" and AE.smooth((fr.bt - 0.5) / 0.5) or 0)
		elseif w.carriers then
			TOOLS.dropCarriers(w)
		end
		local g = fr.gesture
		TOOLS.updateBelt(w, g ~= nil and g.id == "beltlift" and g.u > 0.15 and g.u < g.dur - 0.15)
		local list = shots[id]
		if list then
			for _, s in ipairs(list) do
				if not s.done and bt >= s.at then
					s.done = true
					local cam = FX.Shot(w, VT)
					if args.debug then
						local rs = walker:FindFirstChild("RightShoulder", true)
						local R = H.require("AnimRig")
						local rg = R.rigs and R.rigs[walker]
						local j = rg and rg.joints.RS
						print("dbg", s.id, AE.active[walker] ~= nil, j and tostring(j.motor.Transform), j and j.motor.Name, rg and rg.outT and tostring(rg.outT.RS), fr.mode, g and g.id)
					end
					local figs = { { walker, "boxer" } }
					for _, m in ipairs(team) do
						table.insert(figs, { m, "coach" })
					end
					shoot(s.id, s.label, figs, cam, r.Position, { beat = id, mode = fr.mode, gesture = g and g.id or nil, carry = plan.carry })
				end
			end
		end
		if gif and id == gif.beat and bt >= gif.from and bt <= gif.to and (i % gif.every == 0) then
			local fid = string.format("%s_%03d", gif.id, #gifFrames + 1)
			local out = { id = fid, figures = { exportFigure(walker, "boxer") }, focus = { r.Position.X, r.Position.Y, r.Position.Z },
				yaw = math.atan2(-r.CFrame.LookVector.X, -r.CFrame.LookVector.Z) }
			local props = { name = "Props", role = "props", meshes = {}, parts = exportParts("EntranceBelt") }
			if #props.parts > 0 then
				table.insert(out.figures, props)
			end
			Host.WriteJSON(OUT .. "/" .. fid .. ".json", out)
			table.insert(gifFrames, fid .. ".json")
		end
	end
	TOOLS.dropCarriers(w)
	if w.belt then
		w.belt.model:Destroy()
	end
	AE.active[walker] = nil
	return gifFrames
end

local function storyPlan(carry)
	local p = Entrance.Plan({ corner = "Red", choice = { walk1 = "fistpump", walk2 = carry and "turnitup" or "shadowbox", ring = "turnbuckle", carry = true },
		popularity = carry and 90 or 20, venue = "Arena", last = true, belts = 1 })
	p.pts = PTS
	return p
end

if ONLY.story then
	local walker = boxer(3, CFrame.new(PTS.entrance))
	placeAt(walker, PTS.entrance, CENTRE)
	local team = { coach(CFrame.new(PTS.entrance + Vector3.new(-2, 0, -3))) }
	placeAt(team[1], PTS.entrance + Vector3.new(-2.1, 0, -2.6), CENTRE)
	run({ walker, team[1] }, 1.0)
	runWalk(walker, team, storyPlan(false), {
		tunnel = { { at = 0.95, id = "01_tunnel", label = "the tunnel: the reveal at the stage, a fist pump for the crowd" } },
		aisle = { { at = 1.55, id = "02_tracking", label = "tracking down the aisle: shadowboxing, the coach behind him" } },
		crowd = { { at = 0.7, id = "03_crowd", label = "the crowd shot from the walkway rail" } },
		steps = { { at = 0.75, id = "04b_steps", label = "the ring shot: up the ring steps" } },
		ropes = { { at = 0.45, id = "04c_ropes", label = "ducking through the ropes" } },
		ring = { { at = Entrance.RING_WALK + 0.95, id = "05_turnbuckle", label = "the turnbuckle salute in his corner" } },
		robe = { { at = 0.85, id = "06_robe", label = "the robe comes off in his corner" } },
	})
	-- the carried walk: a favourite on the crowd's shoulders (the robe back on, back to the tunnel)
	CS:RemoveTag(walker, "Fighter")
	walker:Destroy()
	for _, m in ipairs(team) do
		CS:RemoveTag(m, "Ambient")
		m:Destroy()
	end
	run({}, 0.1)
	local w2 = boxer(3, CFrame.new(PTS.entrance))
	placeAt(w2, PTS.entrance, CENTRE)
	run({ w2 }, 1.0)
	runWalk(w2, {}, storyPlan(true), {
		tunnel = { { at = 1.2, id = "04a_carried_tunnel", label = "carried out of the tunnel on the fans' shoulders" } },
		aisle = { { at = 1.4, id = "04_carried", label = "carried down the aisle: four fans in the red corner's colours" } },
		setdown = { { at = 0.55, id = "04d_setdown", label = "set down at the ring steps" } },
	})
	CS:RemoveTag(w2, "Fighter")
	w2:Destroy()
	run({}, 0.1)
end

if ONLY.gif then
	-- three celebrations, each the tunnel beat of a walk that opens with it (standing on the stage), a frame every 1/12 s
	for _, c in ipairs({ { "fistpump", "Fist Pump" }, { "chestbeat", "Chest Beat" }, { "beltlift", "Belt Lift" } }) do
		local walker = boxer(3, CFrame.new(PTS.entrance))
		placeAt(walker, PTS.entrance, CENTRE)
		run({ walker }, 1.0)
		local p = Entrance.Plan({ corner = "Red", choice = { walk1 = c[1], walk2 = "none", ring = "fistpump" }, popularity = 10, venue = "Arena", belts = 1 })
		p.pts = PTS
		local frames = runWalk(walker, {}, p, {}, { id = "gif_" .. c[1], beat = "tunnel", from = 0.05, to = 1.6, every = 5 })
		table.insert(index.gifs, { id = "gif_" .. c[1], label = c[2], frames = frames })
		print("gif", c[1], #frames)
		CS:RemoveTag(walker, "Fighter")
		walker:Destroy()
		run({}, 0.1)
	end
end
Host.WriteJSON(OUT .. "/index.json", index, true)
print("out:", OUT)
process.exit(0)
