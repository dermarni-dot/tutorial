--!nocheck
-- v9_referee.luau: the ring officials as the game builds and animates them, for tools/sim/v9_referee_render.py
-- (previews/final/v9/referee). Nothing is placed by hand:
--   * the referee's look comes from the server's own code (Officials.Look when the src has it, else FightEngine's old
--     SpawnReferee inline: Looks.Random + Looks.RandomBuild, opts outfit = "referee", detail = "medium", bare hands),
--     built by Builder.Cosmetics on the fake R15 rig of v8_scene / v9_anim (the tier swap, the classic head and its
--     drawn face decal, the headgear, the outfit: mesh pieces through BuilderGear or the part-built fallback)
--   * the spar coach (outfit "cornerman") the same way, and two boxers for scale (gloves, trunks, boots)
--   * the poses are the REAL client Animator (src/client/Animator.client.lua + Anim*) on a virtual clock: the referee
--     tagged "Referee" (Loop = referee: his stance), walking (the root glides, AssemblyLinearVelocity set, as the
--     Humanoid's MoveTo would), the count (Act refcount|n), the catch (catch|t), the wave-off (waveoff); the boxers
--     tagged "Fighter" (Guard up)
-- Each shot is written with every figure's visible parts in world space (the v9_anim / v8_scene frame format).
--
--   lune run tools/sim/v9_referee.luau [--out DIR] [--src DIR] [--gear PATH] [--seeds 1,2,3] [--only stand,count]
--
-- Output: <out>/index.json { shots = [{ id, label, file, ref = { tiers, outfit pieces, decals, gear } }] }, <out>/<id>.json
-- { figures = [{ name, role, meshes, head, parts }] }; it also prints a check of each official's outfit (the pieces it
-- wears, boxing gear found on it, face decals).
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
local OUT = (args.out or (SCRATCH .. "/v9ref")):gsub("/$", "")
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
-- the scene: two boxers behind the referee (ring centre at the origin, the referee facing -Z, toward the camera's
-- front view), each shot a few seconds of the Animator
------------------------------------------------------------------------
Host.MkDir(OUT)
local R = math.rad
local A = boxer(3, { name = "Red", skin = 6, gloves = 1, trunks = 3, trim = 1 }, CFrame.new(-2.3, 0, 2.6) * CFrame.Angles(0, -R(90), 0))
local B = boxer(4, { name = "Blue", skin = 10, gloves = 2, trunks = 4, trim = 2 }, CFrame.new(2.3, 0, 2.6) * CFrame.Angles(0, R(90), 0))
for _, m in ipairs({ A, B }) do
	m:SetAttribute("Guard", "up")
	m:SetAttribute("Style", "BoxerPuncher")
	CS:AddTag(m, "Fighter")
end

local SEEDS = {}
for s in (args.seeds or "1,3"):gmatch("[^,]+") do
	table.insert(SEEDS, tonumber(s))
end

local index = { about = "v9 ring officials: Builder.Cosmetics + the client Animator, world space, studs, +Y up", shots = {} }
local function shoot(id, label, figs, refRec)
	if only and not only[id:match("^[^_]+")] and not only[id] then
		return
	end
	local out = { id = id, label = label, figures = {} }
	for _, f in ipairs(figs) do
		table.insert(out.figures, exportFigure(f[1], f[2]))
	end
	Host.WriteJSON(OUT .. "/" .. id .. ".json", out)
	table.insert(index.shots, { id = id, label = label, file = id .. ".json", ref = refRec })
	print("shot", id)
end

local function official(seed, kind, champ, at, tier)
	local app, b, gear, opts = officialLook(seed, kind, champ)
	if tier then
		b = buildFor(app, tier) -- (a forced muscle tier: the outfit is fitted per tier)
	end
	local m = makeFigure(app, b, gear, opts, at)
	m.Name = kind == "referee" and "Referee" or "Coach"
	m:SetAttribute("Loop", "referee")
	CS:AddTag(m, "Referee")
	local rec = audit(m)
	rec.kind = kind
	rec.seed = seed
	rec.face = app.face and app.face.style
	print(string.format("%s seed %d: tiers %s  face %s  decals %d  headgear %s\n  mesh   %s\n  parts  %s\n  BOXING %s", kind, seed,
		tostring(rec.tiers), tostring(rec.face), rec.decals, tostring(rec.headgear), table.concat(rec.mesh, " "), table.concat(rec.parts, " "),
		#rec.boxing > 0 and table.concat(rec.boxing, " ") or "none"))
	return m, rec
end

local function run(models, seconds, each)
	local n = math.floor(seconds / DT + 0.5)
	for i = 1, n do
		if each then
			each(i * DT)
		end
		frame(models)
	end
end

local function act(m, s, id)
	m:SetAttribute("Act", s)
	m:SetAttribute("ActId", id)
end

local actId = 0
for si, seed in ipairs(SEEDS) do
	local champ = si == 2
	local tag = string.format("s%d", seed)
	local ref, rec = official(seed, "referee", champ, CFrame.new(0, 0, 0))
	local all = { A, B, ref }
	run(all, 2.5)
	local figs = { { A, "boxer" }, { B, "boxer" }, { ref, "referee" } }
	shoot("stand_" .. tag, "stance (Loop referee)" .. (champ and ", championship" or ""), figs, rec)
	-- separate: he steps in between them (the catch's reach is the widest the arms go when he breaks a clinch)
	actId += 1
	act(ref, "catch|2.5", actId)
	run(all, 0.9)
	shoot("separate_" .. tag, "separate / catch (arms out)", figs, rec)
	run(all, 2.2)
	-- the count: arm up, then the chop
	for k, at in ipairs({ { 0.33, "up" }, { 0.62, "down" } }) do
		actId += 1
		act(ref, "refcount|" .. (k + 4), actId)
		run(all, at[1])
		shoot("count" .. at[2] .. "_" .. tag, "the count (arm " .. at[2] .. ")", figs, rec)
		run(all, 1.2)
	end
	actId += 1
	act(ref, "waveoff", actId)
	run(all, 0.62)
	shoot("waveoff_" .. tag, "the wave-off", figs, rec)
	run(all, 1.6)
	-- walking: the root glides along -Z at the referee's WalkSpeed (11)
	local hrp = ref:FindFirstChild("HumanoidRootPart")
	local hum = ref:FindFirstChildOfClass("Humanoid")
	local y0 = hrp.CFrame.Y
	local z = 0
	run(all, 1.6, function(t)
		local v = math.min(11, t * 11 / 0.4)
		z -= v * DT
		hrp.CFrame = CFrame.new(0, y0, z)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -v)
		hum.MoveDirection = Vector3.new(0, 0, -1)
	end)
	for k = 1, 2 do
		run(all, 0.17, function()
			z -= 11 * DT
			hrp.CFrame = CFrame.new(0, y0, z)
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -11)
		end)
		shoot("walk" .. k .. "_" .. tag, "walking (11 studs/s)", { { ref, "referee" } }, rec)
	end
	CS:RemoveTag(ref, "Referee")
	ref:Destroy()
	run({ A, B }, 0.1)
end
-- the lean and the elite tier (every outfit piece is fitted per tier): stance and the count
for _, tier in ipairs({ 1, 5 }) do
	local ref, rec = official(5, "referee", false, CFrame.new(0, 0, 0), tier)
	local all = { A, B, ref }
	local figs = { { A, "boxer" }, { B, "boxer" }, { ref, "referee" } }
	run(all, 2.5)
	shoot("tier" .. tier .. "_stand", "tier " .. tier .. " body, stance", figs, rec)
	actId += 1
	act(ref, "refcount|2", actId)
	run(all, 0.33)
	shoot("tier" .. tier .. "_count", "tier " .. tier .. " body, the count", figs, rec)
	CS:RemoveTag(ref, "Referee")
	ref:Destroy()
	run({ A, B }, 0.1)
end
-- the spar coach (outfit cornerman: the gym's spar official)
do
	local coach, rec = official(3, "cornerman", false, CFrame.new(0, 0, 0))
	local all = { A, B, coach }
	run(all, 2.5)
	shoot("coach_s3", "spar coach (outfit cornerman), stance", { { A, "boxer" }, { B, "boxer" }, { coach, "cornerman" } }, rec)
	actId += 1
	act(coach, "refcount|3", actId)
	run(all, 0.33)
	shoot("coachcount_s3", "spar coach, count", { { A, "boxer" }, { B, "boxer" }, { coach, "cornerman" } }, rec)
end
Host.WriteJSON(OUT .. "/index.json", index, true)
print("out:", OUT)
process.exit(0)
