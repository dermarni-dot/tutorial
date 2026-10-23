--!nocheck
-- v10_postfight_scene.luau: the post-fight scene's places (src/server/PostFight.lua: both men to the centre, the referee
-- between them, the hand raised) staged on real rigs, for tools/sim/v10_postfight_render.py (previews/final/v10/
-- postfight_scene). v9_ceremony.luau's harness (the fake R15 rig, Builder.Cosmetics, the REAL client Animator on a
-- virtual clock): two Heavyweight Build men at tier 5 (the widest frames) and a referee from Officials.Look, placed by
-- the game's own PostFight.Layout from HitGeometry.Frame read off these rigs, the poses the server sets (pfWait /
-- pfHold, then pfRaiseL + pfHandUpR + pfLose) played by the Animator. Per frame: the figures (v9_referee's format),
-- two cameras (top: straight down on the centre; hard: BoxerClient.Ceremony's result shot from the camera side) and
-- the body clearances (the smallest gap between any two bodies' meshes, pairwise).
--
--   lune run tools/sim/v10_postfight_scene.luau [--out DIR] [--frames heavy,mixed,down] [--times 1.2,4.0]
--
-- Output: <out>/index.json { frames = [{ id, t, file, layout }] }, <out>/<id>.json { t, pose, cameras = { top, hard },
-- figures = [...], layout = { red, ref, blue } }
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
local OUT = (args.out or (SCRATCH .. "/v10pf")):gsub("/$", "")
local only
if args.only then
	only = {}
	for s in args.only:gmatch("[^,]+") do
		only[s] = true
	end
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

-- what an official wears: outfit pieces (mesh / part-built), boxing gear found on him, face decals
local BOXING = { "Glove", "Wrap", "Trunk", "Waistband", "Boot", "Sole_", "ShoeLaces", "AnkleSock", "ShoeCollar", "Mouthguard" }
local function audit(model)
	local rec = { tiers = model:GetAttribute("BodyTiers"), mesh = {}, parts = {}, boxing = {}, decals = 0, headgear = false }
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Decal" and d.Parent and d.Parent.Name == "Head" then
			rec.decals += 1
		end
		if (d.ClassName == "Part" or d.ClassName == "MeshPart") and d.Parent and d.Parent.Name ~= model.Name then
			local folder = d.Parent.Name
			if folder == "Headgear" then
				rec.headgear = true
			elseif d:GetAttribute("GearMesh") then
				table.insert(rec.mesh, d.Name)
			elseif folder == "Attire" or folder == "Hands" then
				table.insert(rec.parts, d.Name)
			end
			for _, k in ipairs(BOXING) do
				if d.Name:sub(1, 3) ~= "Off" and d.Name:find(k, 1, true) and folder ~= "Headgear" then
					table.insert(rec.boxing, folder .. "/" .. d.Name)
				end
			end
		end
	end
	table.sort(rec.mesh)
	table.sort(rec.parts)
	return rec
end



------------------------------------------------------------------------
-- the scene
------------------------------------------------------------------------
Host.MkDir(OUT)
local HitGeometry = H.require("HitGeometry")
-- (installs the scene's poses into AnimGym's table, the one the Animator plays; the Animator's own requires may
-- still be under way in its thread: wait for them)
for _ = 1, 50 do
	if pcall(H.require, "AnimCeremony") then
		break
	end
	ltask.wait(0.1)
end
-- the server's PostFight (its Layout: pure in the frames)
local PostFight
do
	local SSS = H.Service("ServerScriptService")
	local folder = Host.NewNode("Server", "Folder", SSS)
	for _, f in ipairs(fs.readDir(srcDir .. "/server")) do
		local base = f:match("^(.-)%.lua$")
		if base and not f:find("%.server%.") then
			local n = Host.NewNode(base, "ModuleScript", folder)
			rawset(n, "_file", srcDir .. "/server/" .. f)
		end
	end
	local ok, mod = pcall(H.requireNode, folder._kids.PostFight)
	if not (ok and type(mod) == "table" and mod.Layout) then
		error("PostFight did not load: " .. tostring(mod))
	end
	PostFight = mod
end

local center = Vector3.new(0, 0, 0)
local face = Vector3.new(0, 0, -1)
local right = face:Cross(Vector3.new(0, 1, 0))
local UP = Vector3.new(0, 1, 0)
local function lookCF(pos, look)
	return CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
end
local function fighter(frameId, tier, spec, at)
	local app = Looks.Defaults(1)
	app.skin = spec.skin
	app.body.frame = frameId
	app.height = spec.height or 74
	app.gloves.color = pal(spec.gloves)
	app.attire.trunks = pal(spec.trunks)
	app.attire.trim = pal(spec.trim)
	local m = makeFigure(app, buildFor(app, tier), nil, { hands = "gloves", detail = "full", fightNight = true }, at)
	m.Name = spec.name
	return m
end
local function official(seed, at)
	local app, b, gear, opts = officialLook(seed, "referee", false)
	local m = makeFigure(app, b, gear, opts, at)
	m.Name = "Referee"
	m:SetAttribute("Loop", "referee")
	CS:AddTag(m, "Referee")
	return m
end
local function standHeightOf(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum.HipHeight + hrp.Size.Y / 2 + 0.05
end
local function frameFor(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	return HitGeometry.Frame(model, hrp.Position.Y - standHeightOf(model), HitGeometry.Unit())
end
local function standAt(model, pos, look)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y = standHeightOf(model)
	hrp.CFrame = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(look.X, y, look.Z))
	hrp.AssemblyLinearVelocity = Vector3.zero
	model:FindFirstChildOfClass("Humanoid").MoveDirection = Vector3.zero
end
local function run(models, seconds)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		frame(models)
	end
end

-- the smallest gap between two figures' body meshes (world space; the gear left out), from the exported figures;
-- core = true: the trunks and heads only (the referee's held-out hands MEET the men's wrists by design)
local CORE = { UpperTorso = true, LowerTorso = true, Head = true }
local function nearest(fa, fb, core)
	local best = math.huge
	local A, B = {}, {}
	for _, m in ipairs(fa.meshes) do
		if not m.gear and (not core or CORE[m.name]) then
			for i = 1, #m.p, 9 do -- (every third vertex)
				table.insert(A, { m.p[i], m.p[i + 1], m.p[i + 2] })
			end
		end
	end
	for _, m in ipairs(fb.meshes) do
		if not m.gear and (not core or CORE[m.name]) then
			for i = 1, #m.p, 9 do
				table.insert(B, { m.p[i], m.p[i + 1], m.p[i + 2] })
			end
		end
	end
	for _, a in ipairs(A) do
		for _, b in ipairs(B) do
			local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
			local d = dx * dx + dy * dy + dz * dz
			if d < best then
				best = d
			end
		end
	end
	return math.sqrt(best)
end

-- how deep two figures' body meshes sink into each other: the deepest axis-aligned box overlap over the pairs of
-- their (non-gear) meshes, as the smallest extent of the boxes' intersection (0 = clear; a hand on a wrist reads a
-- few tenths; an arm through a chest a stud)
local function boxOf(m)
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for i = 1, #m.p, 3 do
		for a = 0, 2 do
			local v = m.p[i + a]
			if v < lo[a + 1] then
				lo[a + 1] = v
			end
			if v > hi[a + 1] then
				hi[a + 1] = v
			end
		end
	end
	return lo, hi
end
local function penetration(fa, fb)
	local worst, pair = 0, ""
	for _, ma in ipairs(fa.meshes) do
		if not ma.gear then
			local la, ha = boxOf(ma)
			for _, mb in ipairs(fb.meshes) do
				if not mb.gear then
					local lb, hb = boxOf(mb)
					local depth = math.huge
					for a = 1, 3 do
						depth = math.min(depth, math.min(ha[a], hb[a]) - math.max(la[a], lb[a]))
					end
					if depth > worst then
						worst, pair = depth, ma.name .. "/" .. mb.name
					end
				end
			end
		end
	end
	return worst, pair
end

local SCENES = {
	heavy = { red = { frame = "Heavyweight Build", tier = 5, skin = 6, gloves = 1, trunks = 3, trim = 1, height = 76 }, blue = { frame = "Heavyweight Build", tier = 5, skin = 10, gloves = 2, trunks = 4, trim = 2, height = 77 }, winner = "red" },
	mixed = { red = { frame = "Lean", tier = 3, skin = 4, gloves = 1, trunks = 5, trim = 1, height = 70 }, blue = { frame = "Heavyweight Build", tier = 5, skin = 8, gloves = 2, trunks = 2, trim = 3, height = 78 }, winner = "blue" },
	down = { red = { frame = "Heavyweight Build", tier = 5, skin = 6, gloves = 1, trunks = 3, trim = 1, height = 76 }, blue = { frame = "Heavyweight Build", tier = 4, skin = 12, gloves = 3, trunks = 1, trim = 2, height = 75 }, winner = "blue", redDown = true },
}
local ORDER = { "heavy", "mixed", "down" }
local wantScenes
if args.frames then
	wantScenes = {}
	for s in args.frames:gmatch("[^,]+") do
		wantScenes[s] = true
	end
end
local TIMES = {}
for s in (args.times or "1.2,4.0"):gmatch("[^,]+") do
	table.insert(TIMES, tonumber(s))
end
table.sort(TIMES)
local RAISE_AT = 2.5

local index = { about = "v10 post-fight scene (world space, studs, +Y up, canvas y = 0; the picture faces -Z)", frames = {}, gaps = {} }
for _, sid in ipairs(ORDER) do
	if not wantScenes or wantScenes[sid] then
		local sc = SCENES[sid]
		local far = lookCF(Vector3.new(-6, 0, 6), center)
		local red = fighter(sc.red.frame, sc.red.tier, { name = "Red", skin = sc.red.skin, gloves = sc.red.gloves, trunks = sc.red.trunks, trim = sc.red.trim, height = sc.red.height }, far)
		local blue = fighter(sc.blue.frame, sc.blue.tier, { name = "Blue", skin = sc.blue.skin, gloves = sc.blue.gloves, trunks = sc.blue.trunks, trim = sc.blue.trim, height = sc.blue.height }, lookCF(Vector3.new(6, 0, 6), center))
		local ref = official(7, lookCF(Vector3.new(0, 0, 8), center))
		local all = { red, blue, ref }
		CS:AddTag(red, "Fighter")
		CS:AddTag(blue, "Fighter")
		red:SetAttribute("Style", "Slugger")
		blue:SetAttribute("Style", "BoxerPuncher")
		run(all, 0.5) -- (into the rest)
		local frames = { red = frameFor(red), blue = frameFor(blue), ref = frameFor(ref) }
		-- (a man still down lies where he fell: here right by the centre, the worst case - PostFight.Run passes his
		-- root as downAt and the group steps off him)
		local downAt = sc.redDown and (center + right * 0.6 + face * 0.4) or nil
		local L = PostFight.Layout(center, face, frames, sc.redDown == true, false, { downAt = downAt })
		print(string.format("%s: red shoulderHalf %.2f  blue %.2f  ref %.2f  -> red %.2f  ref %.2f  blue %.2f along the line", sid,
			frames.red.shoulderHalf, frames.blue.shoulderHalf, frames.ref.shoulderHalf, (L.red - center):Dot(right), (L.ref - center):Dot(right), (L.blue - center):Dot(right)))
		-- the server's staging: the men to their places (PostFight.Run's stand), the poses from the Trainee path
		for _, X in ipairs({ { red, L.red, sc.redDown }, { blue, L.blue, false } }) do
			local m, at, down = X[1], X[2], X[3]
			if not down then
				standAt(m, at, at + face * 10)
				CS:RemoveTag(m, "Fighter")
				CS:AddTag(m, "Trainee")
				m:SetAttribute("Pose", "pfWait")
			else
				-- (a man still down: AnimFight's down pose where he fell, by the centre)
				standAt(m, downAt, downAt - right * 10)
				m:SetAttribute("Guard", "down")
				m:SetAttribute("DownPose", "back")
			end
		end
		standAt(ref, L.ref, L.ref + face * 10)
		ref:SetAttribute("Pose", sc.redDown and "pfWait" or "pfHold")
		local winner, loser = sc.winner == "red" and red or blue, sc.winner == "red" and blue or red
		local t, ti, raised = 0, 1, false
		while ti <= #TIMES do
			if not raised and t >= RAISE_AT then
				raised = true
				-- (PostFight.Run's raise: the referee's arm on the winner's side, the winner's arm nearest him)
				ref:SetAttribute("Pose", sc.winner == "red" and "pfRaiseL" or "pfRaiseR")
				winner:SetAttribute("Pose", sc.winner == "red" and "pfHandUpR" or "pfHandUpL")
				if not (sc.redDown and loser == red) then
					loser:SetAttribute("Pose", "pfLose")
				end
			end
			if t >= TIMES[ti] - 1e-6 then
				local id = string.format("%s_t%d", sid, math.floor(TIMES[ti] * 10 + 0.5))
				local figs = { exportFigure(red, "red"), exportFigure(blue, "blue"), exportFigure(ref, "referee") }
				local gaps = { red_ref = nearest(figs[1], figs[3]), blue_ref = nearest(figs[2], figs[3]), red_blue = nearest(figs[1], figs[2]),
					core_red_ref = nearest(figs[1], figs[3], true), core_blue_ref = nearest(figs[2], figs[3], true) }
				local penRR, pairRR = penetration(figs[1], figs[3])
				local penBR, pairBR = penetration(figs[2], figs[3])
				gaps.pen_red_ref, gaps.pen_blue_ref, gaps.pen_pairs = penRR, penBR, pairRR .. " " .. pairBR
				-- the cameras: straight down on the centre; the result shot from the camera side (Ceremony.resultShot)
				local eye = center + UP * 2.2
				local hardFrom, hardAt, fov
				if not raised then
					local a = math.rad(-22 + 44 * 0.2)
					local dir = face * math.cos(a) + right * math.sin(a)
					hardFrom, hardAt, fov = center + dir * 9.26 + UP * 3.52, eye, 48
				else
					-- (the root's own height, as BoxerClient.Ceremony's resultShot reads it: the chest, not the shorts)
					local wp = winner:FindFirstChild("HumanoidRootPart").Position
					local toW = Vector3.new(wp.X, 0, wp.Z) - center
					local side = toW.Magnitude > 0.1 and toW.Unit or right
					local k = 0.6
					hardFrom, hardAt, fov = wp + face * (6.2 - 1.6 * k) + side * (1.4 - 0.4 * k) + UP * (2.4 + 1.0 * k), wp + UP * (1.9 + 0.5 * k), 44 - 4 * k
				end
				local out = {
					id = id, scene = sid, t = t, pose = tostring(winner:GetAttribute("Pose")), raised = raised,
					cameras = { top = { cf = cfList(CFrame.lookAt(center + UP * 16 + face * 0.01, center, face)), fov = 40 }, hard = { cf = cfList(CFrame.lookAt(hardFrom, hardAt)), fov = fov } },
					layout = { red = { L.red.X, L.red.Y, L.red.Z }, ref = { L.ref.X, L.ref.Y, L.ref.Z }, blue = { L.blue.X, L.blue.Y, L.blue.Z } },
					frames = { red = { shoulderHalf = frames.red.shoulderHalf, torsoHalfD = frames.red.torsoHalfD }, blue = { shoulderHalf = frames.blue.shoulderHalf, torsoHalfD = frames.blue.torsoHalfD }, ref = { shoulderHalf = frames.ref.shoulderHalf } },
					gaps = gaps, figures = figs, center = { 0, 0, 0 }, face = { face.X, face.Y, face.Z },
				}
				Host.WriteJSON(OUT .. "/" .. id .. ".json", out)
				table.insert(index.frames, { id = id, scene = sid, t = t, file = id .. ".json", pose = out.pose, gaps = gaps })
				index.gaps[id] = gaps
				print(string.format("frame %s t=%.1f pose %s  gaps: red-ref %.2f  blue-ref %.2f  red-blue %.2f  (trunks+heads: red-ref %.2f  blue-ref %.2f)  box overlap: red-ref %.2f blue-ref %.2f (%s)", id, t, out.pose, gaps.red_ref, gaps.blue_ref, gaps.red_blue, gaps.core_red_ref, gaps.core_blue_ref, penRR, penBR, gaps.pen_pairs))
				ti += 1
			end
			frame(all)
			t += DT
		end
		for _, m in ipairs(all) do
			m:Destroy()
		end
	end
end
Host.WriteJSON(OUT .. "/index.json", index, true)
print("out:", OUT)
process.exit(0)
