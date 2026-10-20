--!nocheck
-- v9_anim.luau: the REAL client Animator (src/client/Animator.client.lua and its Anim* modules) driving complete
-- tier boxers built by the server's Builder.Cosmetics (as v8_scene.luau: the fake R15 rig, the tier swap, the classic
-- head, the mesh gear), on a virtual clock, recorded frame by frame in world space for tools/sim/v9_render.py, plus
-- numbers the eye cannot read off a frame (pelvis sway, thigh / pelvis interpenetration, glove reach).
--
--   lune run tools/sim/v9_anim.luau [--out DIR] [--tiers 1,3,5] [--clips walk,jog,punch] [--frames N]
--                                   [--src DIR] (another commit's src: the "before" set)
--
-- Clips
--   walk / jog / run: a player character (Players.LocalPlayer.Character) whose HumanoidRootPart glides along -Z at
--     5 / 11 / 16 studs/s on a flat floor (workspace:Raycast hits Y = 0), Humanoid state Running; recorded after a
--     settle, `frames` evenly spaced over one full gait cycle (two steps)
--   punch: two "Fighter" models 3.4 studs apart facing each other; jab, cross, lead hook, rear hook, uppercut and a
--     body jab (Act / ActId as FightEngine sends them), recorded at the punch's peak (the frame of the glove's
--     furthest reach) plus a few in-between frames
-- Output: <out>/index.json { clips = [...] }, <out>/<clip>_t<tier>.json { frames = [{ t, meshes, head, parts }] },
-- <out>/metrics.json
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
local PI = math.pi
local SCRATCH = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad"

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k = a[i]
		if k == "--no-regen" or k == "--no-mesh" then
			args[k:gsub("^%-%-", "")] = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local OUT = (args.out or (SCRATCH .. "/v9anim")):gsub("/$", "")
local TIERS = {}
for s in (args.tiers or "1,3,5"):gmatch("[^,]+") do
	table.insert(TIERS, tonumber(s))
end
local CLIPS = {}
for s in (args.clips or "walk,jog,punch"):gmatch("[^,]+") do
	CLIPS[s] = true
end
local NFRAMES = tonumber(args.frames) or 8
local NOMESH = args["no-mesh"] == true
local BARE = args.bare ~= nil and args.bare ~= "0" -- hide the gear (the body's own surfaces)
local HANDS = args.hands or "gloves" -- gloves | wraps | bare
-- --height IN: the boxer's height in inches (Looks: 60..84; Builder.Scales clamps the scale to 0.86..1.2); the clip
-- ids carry it (walk_t3_h84)
local HEIGHT = tonumber(args.height)
local HTAG = HEIGHT and ("_h" .. tostring(HEIGHT)) or ""

------------------------------------------------------------------------
-- host: fake engine, virtual clock, the asset simulator (Content)
------------------------------------------------------------------------
local root = Host.FindRoot()
-- --meshroot DIR: the folder holding out/tier<N>/ and out/gear/ (default tools/body: a copy of an older build for the
-- "before" set, with that commit's --src)
local MESHROOT = (args.meshroot or (root .. "/tools/body")):gsub("/$", "")
local srcDir = args.src or (root .. "/src")
local MANIFEST = AssetSim.LOCAL_MANIFEST
if not args["no-regen"] then
	AssetSim.EnsureManifest(root, MANIFEST)
end
local E = FE.new()
local sim = AssetSim.new({ root = root, manifest = MANIFEST, newPart = function()
	return E.new("MeshPart")
end })
local VT = 1000 -- the virtual clock (s)
local fakeOs = setmetatable({ clock = function()
	return VT
end }, { __index = os })
local RaycastParams = { new = function()
	return { FilterDescendantsInstances = {} }
end }
local OverlapParams = RaycastParams
local H = Host.new({ root = root, src = srcDir, globals = { Content = sim.Content, Instance = E.Instance, workspace = E.workspace,
	Workspace = E.workspace, os = fakeOs, RaycastParams = RaycastParams, OverlapParams = OverlapParams,
	time = function()
		return VT
	end } })
E.install(H)
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)

-- the floor: a ray down crossing Y = 0 hits it
local floorPart = E.new("Part", E.workspace)
floorPart.Name = "Floor"
floorPart.Size = Vector3.new(200, 1, 200)
floorPart.CFrame = CFrame.new(0, -0.5, 0)
floorPart.CanCollide = true
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
E.camera.WorldToViewportPoint = function(_, p)
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
-- --body PATH / --gear PATH: a local manifest (publish_body.py / publish_gear.py --local: fake ids + an .ids.json sidecar
-- mapping each id to its file) instead of src/shared's: the rebuilt meshes before they are uploaded
local REAL = args.body and luau.load(fs.readFile(args.body), { debugName = args.body })() or BodyTiers.Data()
BodyTiers.SetData(REAL)

-- mesh id -> file (tier parts and gear): through tools/body/uploaded.json
local MESH_FILES = {}
do
	local up = root .. "/tools/body/uploaded.json"
	if fs.isFile(up) then
		for _, e in pairs(serde.decode("json", fs.readFile(up))) do
			if type(e.file) == "string" and type(e.id) == "number" then
				MESH_FILES[e.id] = MESHROOT .. "/" .. e.file
			end
		end
	end
end
for _, path in ipairs({ args.body or "", args.gear or "" }) do
	local side = path:gsub("%.lua$", "") .. ".ids.json"
	if path ~= "" and fs.isFile(side) then
		for id, f in pairs(serde.decode("json", fs.readFile(side)).ids or {}) do
			MESH_FILES[tonumber(id)] = f
		end
	end
end
local FACE_FILES = {}
-- (the drawn faces' files carry their revision: faces.json names each key's file, e.g. face_wcb_grit_v2.png)
local FACE_JSON = {}
do
	local fj = root .. "/tools/body/out/faces/faces.json"
	if fs.isFile(fj) then
		for _, e in ipairs(serde.decode("json", fs.readFile(fj)).faces or {}) do
			FACE_JSON[e.key] = e.file
		end
	end
end
for _, f in ipairs(REAL.faces or {}) do
	if f.id and f.id ~= 0 then
		FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/" .. (FACE_JSON[f.key] or ("face_" .. f.key .. ".png"))
	end
end
do
	local path = args.gear or (srcDir .. "/shared/GearAssetData.lua")
	BuilderGear.SetData(luau.load(fs.readFile(path), { debugName = path })())
end

------------------------------------------------------------------------
-- the fake R15 rig (v8_scene.luau's)
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

-- the engine's joint solve from the HumanoidRootPart out (Motor6D: Part1 = Part0 * C0 * Transform * C1^-1)
local weldOffsets = setmetatable({}, { __mode = "k" })
local jointCache = setmetatable({}, { __mode = "k" })
local function solve(model, keepRoot)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not keepRoot then
		hrp.CFrame = CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
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
	local function addPart(name, size, orig, atts, cls)
		local p = E.new(cls or "MeshPart", model)
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

local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
local function buildFor(app, tier)
	for v = 0, 100 do
		local t = Builder.Tiers(app, build(v))
		if BodyTiers.Key(t) == string.rep(tostring(tier), 14) then
			return v + (tier > 1 and 2 or 0), build(v + (tier > 1 and 2 or 0))
		end
	end
	error("no build gives tier " .. tier)
end
local function pal(i)
	local c = Looks.Palette[i]
	return { c[1], c[2], c[3] }
end

-- a complete boxer of `tier` (male, Athletic frame): returns model, hum, app
local function makeBoxer(tier, spec)
	spec = spec or {}
	local app = Looks.Defaults(spec.g or 1)
	app.skin = spec.skin or 6
	app.body.frame = spec.frame or "Athletic"
	app.face.key = "determined"
	app.gloves.color = pal(spec.gloves or 1)
	app.attire.trunks = pal(spec.trunks or 3)
	app.attire.trim = pal(spec.trim or 1)
	app.attire.trunkStyle = spec.trunkStyle or app.attire.trunkStyle
	app.attire.shoeStyle = spec.shoeStyle or app.attire.shoeStyle
	app.height = spec.height or HEIGHT or app.height
	local _, b = buildFor(app, tier)
	local sc = Builder.Scales(app, b)
	local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	model.Parent = E.workspace
	currentModel = model
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = spec.hands or HANDS, detail = "full" })
	if not ok then
		error("Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	recordWelds(model)
	currentModel = nil
	return model, hum, app
end

------------------------------------------------------------------------
-- export (world space, as v8_scene)
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
-- the part's mesh in world space (recentred on the bbox, scaled to Size, by its CFrame)
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
	local id = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
	local tier = p:GetAttribute("BodyTier")
	if p:GetAttribute("GearMesh") then
		return MESH_FILES[id]
	elseif tier then
		return string.format("%s/out/tier%d/%s.mesh", MESHROOT, tier, p.Name)
	end
	return nil
end

local function exportFrame(model, t)
	local fr = { t = r4(t), meshes = {}, parts = {} }
	for _, p in ipairs(model:GetDescendants()) do
		local cls = p.ClassName
		if not (cls == "Part" or cls == "MeshPart" or cls == "WedgePart") or p.Name == "HumanoidRootPart" then
			continue
		end
		if (p.Transparency or 0) >= 0.99 then
			continue
		end
		if BARE and not p:GetAttribute("BodyTier") and p.Name ~= "Head" then
			continue
		end
		local file = cls == "MeshPart" and fileOf(p)
		if file then
			local P, N, T = worldMesh(p, file)
			table.insert(fr.meshes, { name = p.Name, gear = p:GetAttribute("GearMesh") ~= nil, slot = p:GetAttribute("GearSlot"), p = P, n = N,
				t = T, color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0 })
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
			table.insert(fr.parts, { name = p.Name, shape = shape, cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) },
				color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
		end
	end
	return fr
end

------------------------------------------------------------------------
-- interpenetration: how deep the thigh meshes go into the LowerTorso mesh (and the trunks), per frame
------------------------------------------------------------------------
-- part-space triangles of a part's mesh, scaled to its Size
local function localTris(p)
	local file = fileOf(p)
	if not file then
		return nil
	end
	local m = meshOf(file)
	local cx, cy, cz, bx, by, bz = table.unpack(m.b)
	local s = p.Size
	local kx, ky, kz = s.X / bx, s.Y / by, s.Z / bz
	local V = {}
	for i = 1, #m.P, 3 do
		table.insert(V, Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz))
	end
	return V, m.T
end
-- point inside a closed mesh: parity of a +X ray's crossings
local function inside(V, T, q)
	local n = 0
	for i = 1, #T, 3 do
		local a, b, c = V[T[i]], V[T[i + 1]], V[T[i + 2]]
		-- (Moller-Trumbore against direction +X)
		local e1, e2 = b - a, c - a
		local h = Vector3.new(0, -e2.Z, e2.Y) -- dir x e2 with dir = (1, 0, 0)
		local det = e1:Dot(h)
		if math.abs(det) > 1e-12 then
			local f = 1 / det
			local s = q - a
			local u = f * s:Dot(h)
			if u >= 0 and u <= 1 then
				local qv = s:Cross(e1)
				local v = f * qv.X
				if v >= 0 and u + v <= 1 then
					local tt = f * e2:Dot(qv)
					if tt > 0 then
						n += 1
					end
				end
			end
		end
	end
	return n % 2 == 1
end
-- distance from q to the mesh surface (approximate: nearest vertex)
local function nearestV(V, q)
	local best = math.huge
	for _, v in ipairs(V) do
		local d = (v - q).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end
-- the vertices of part a inside part b's mesh: count and the deepest (studs)
local function penetration(pa, pb)
	local Va = localTris(pa)
	local Vb, Tb = localTris(pb)
	if not (Va and Vb) then
		return 0, 0
	end
	local rel = pb.CFrame:Inverse() * pa.CFrame
	local n, deep = 0, 0
	local bmin, bmax = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, v in ipairs(Vb) do
		bmin, bmax = bmin:Min(v), bmax:Max(v)
	end
	for _, v in ipairs(Va) do
		local q = rel * v
		if q.X > bmin.X and q.Y > bmin.Y and q.Z > bmin.Z and q.X < bmax.X and q.Y < bmax.Y and q.Z < bmax.Z and inside(Vb, Tb, q) then
			n += 1
			deep = math.max(deep, nearestV(Vb, q))
		end
	end
	return n, deep
end

------------------------------------------------------------------------
-- the Animator under the fake engine
------------------------------------------------------------------------
local CS = E.CollectionService
local player = E.localPlayer
local playersProps = H.Service("Players")._props
playersProps.GetPlayers = function()
	return { player }
end
playersProps.GetPlayerFromCharacter = function(_, m)
	return (m ~= nil and m == player.Character) and player or nil
end
player.CharacterAdded = FE.Signal()
local PreSim = FE.Signal()
H.Service("RunService")._props.PreSimulation = PreSim
do
	local file = srcDir .. "/client/Animator.client.lua"
	local env = table.clone(H.globals)
	local SPS = H.client.Parent
	env.script = { Parent = SPS, Name = "Animator" }
	local chunk = luau.load(fs.readFile(file), { debugName = "Animator.client.lua", environment = env })
	ltask.spawn(chunk)
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

local metrics = {}
local index = { about = "v9: the client Animator on tier boxers (Builder.Cosmetics, fake rig), world space, studs, +Y up, face -Z", clips = {} }
Host.MkDir(OUT)

------------------------------------------------------------------------
-- gait numbers: joint angles from the solved parts, the soles against the floor, the planted feet's slide
------------------------------------------------------------------------
local deg, atan2 = math.deg, math.atan2
-- the pieces drawn on a foot (the part itself and whatever is welded to it): part-space points relative to the foot
local function footPoints(model, side)
	local foot = model:FindFirstChild(side .. "Foot")
	local pts = {}
	local function add(p)
		local rel = foot.CFrame:Inverse() * p.CFrame
		local file = p.ClassName == "MeshPart" and fileOf(p)
		if file then
			local V = localTris(p)
			for i = 1, #V, 7 do
				table.insert(pts, rel * V[i])
			end
		else
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						table.insert(pts, rel * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					end
				end
			end
		end
	end
	local drawn = false
	for _, d in ipairs(model:GetDescendants()) do
		local cls = d.ClassName
		if (cls == "Weld" or cls == "WeldConstraint" or cls == "Motor6D") and d.Part0 == foot and d.Part1 and d.Part1 ~= foot
			and (d.Part1.Transparency or 0) < 0.99 and d.Name ~= (side .. "Ankle") then
			add(d.Part1)
			drawn = true
		end
	end
	if not drawn or (foot.Transparency or 0) < 0.99 then
		add(foot)
	end
	return foot, pts
end
local function soleOf(foot, pts)
	local cf = foot.CFrame
	local lo, loPt, loI = math.huge, nil, 1
	for i, q in ipairs(pts) do
		local w = cf * q
		if w.Y < lo then
			lo, loPt, loI = w.Y, w, i
		end
	end
	return lo, loPt, loI
end
-- the signed angle of a direction in a frame's sagittal plane (from straight down, + = forward / -Z)
local function sag(cf, v)
	local d = cf:VectorToObjectSpace(v)
	return deg(atan2(-d.Z, -d.Y))
end
local function yawOf(cf)
	local l = cf.LookVector
	return deg(atan2(-l.X, -l.Z))
end
local function gaitSampler(model)
	local P = {}
	for _, n in ipairs({ "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
		"RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand" }) do
		P[n] = model:FindFirstChild(n)
	end
	local feet = {}
	for _, s in ipairs({ "Left", "Right" }) do
		local f, pts = footPoints(model, s)
		feet[s] = { foot = f, pts = pts }
		if args.debugfoot then
			local mn, mx = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
			for _, q in ipairs(pts) do
				mn, mx = mn:Min(q), mx:Max(q)
			end
			local an = f:FindFirstChild(s .. "Ankle")
			print(string.format("foot %s size %s drawn min %s max %s ankle C1 %s", s, tostring(f.Size), tostring(mn), tostring(mx),
				an and tostring(an.C1.Position) or "?"))
		end
	end
	return function(t)
		local hrp = P.HumanoidRootPart.CFrame
		local lt, ut, head = P.LowerTorso.CFrame, P.UpperTorso.CFrame, P.Head.CFrame
		local s = { t = t, rootY = hrp.Y, rootZ = hrp.Z, rootX = hrp.X, rootYaw = yawOf(hrp) }
		s.pelvisY = lt.Y
		s.headY = head.Y
		s.headPitch = deg(math.asin(math.clamp(head.LookVector.Y, -1, 1)))
		s.headRoll = deg(math.asin(math.clamp(head.RightVector.Y, -1, 1)))
		s.pelvisYaw = ((yawOf(lt) - s.rootYaw + 540) % 360) - 180
		s.chestYaw = ((yawOf(ut) - s.rootYaw + 540) % 360) - 180
		s.trunkPitch = deg(math.asin(math.clamp(ut.LookVector.Y, -1, 1)))
		for _, sd in ipairs({ "Left", "Right" }) do
			local k = sd:sub(1, 1)
			local th, sh, ft = P[sd .. "UpperLeg"].CFrame, P[sd .. "LowerLeg"].CFrame, P[sd .. "Foot"].CFrame
			-- hip: the thigh against the pelvis (sagittal, + flexion) and against the vertical (the root's frame)
			s["hip" .. k] = sag(lt, -th.UpVector)
			s["thigh" .. k] = sag(hrp, -th.UpVector)
			-- knee: the shank against the thigh (+ = flexed back)
			s["knee" .. k] = -sag(th, -sh.UpVector)
			-- the foot's pitch in the world (+ = toes up) and against the shank (+ dorsiflexion, the rest pose's offset kept)
			s["footPitch" .. k] = deg(math.asin(math.clamp(ft.LookVector.Y, -1, 1)))
			s["ankle" .. k] = sag(sh, ft.LookVector) - 90
			local ua, la, hd = P[sd .. "UpperArm"].CFrame, P[sd .. "LowerArm"].CFrame, P[sd .. "Hand"].CFrame
			s["shoulder" .. k] = sag(ut, -ua.UpVector)
			s["elbow" .. k] = deg(math.acos(math.clamp(ua.UpVector:Dot(la.UpVector), -1, 1)))
			s["wrist" .. k] = deg(math.acos(math.clamp(la.UpVector:Dot(hd.UpVector), -1, 1)))
			s["handZ" .. k] = (hrp:PointToObjectSpace(hd.Position)).Z
			local F = feet[sd]
			local lo, pt, idx = soleOf(F.foot, F.pts)
			s["sole" .. k] = lo
			s["solePt" .. k] = pt
			s["soleI" .. k] = idx
			s["footCF" .. k] = ft
			s["pts" .. k] = F.pts
			s["ankleP" .. k] = ft.Position
		end
		return s
	end
end
-- summary of a sample run: ranges, the planted feet's slide (the lowest sole point while it is within 0.02 of the
-- floor, measured as the world travel of the foot's contact frame across consecutive frames), clearance
local function gaitSummary(S)
	local function range(key)
		local lo, hi = math.huge, -math.huge
		for _, s in ipairs(S) do
			lo, hi = math.min(lo, s[key]), math.max(hi, s[key])
		end
		return { r4(lo), r4(hi) }
	end
	local out = {}
	for _, k in ipairs({ "hipL", "hipR", "thighL", "kneeL", "kneeR", "ankleL", "footPitchL", "shoulderL", "shoulderR", "elbowL", "elbowR",
		"wristL", "handZL", "pelvisYaw", "chestYaw", "pelvisY", "headY", "headPitch", "headRoll", "trunkPitch", "soleL", "soleR" }) do
		out[k] = range(k)
	end
	-- the planted feet: each frame a foot's lowest point is on the floor (< 0.03), how far its ankle moved in the
	-- world since the frame before (a planted, rolling foot's ankle moves; its contact must not: the sole
	-- point that is lowest on both frames, i.e. the contact, is compared)
	local slide, slideMax, contact = { L = 0, R = 0 }, 0, { L = 0, R = 0 }
	local sink = 0
	for i = 2, #S do
		local a, b = S[i - 1], S[i]
		for _, k in ipairs({ "L", "R" }) do
			if a["sole" .. k] < 0.012 and b["sole" .. k] < 0.012 then
				-- the material point of the sole that touched the floor on the frame before: where it is now (rolling
				-- without slip leaves it where it was; a slide carries it along the floor)
				local q = a["pts" .. k][a["soleI" .. k]]
				local pa, pb = a["footCF" .. k] * q, b["footCF" .. k] * q
				local d = pb.Y < 0.012 and Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude or 0
				slide[k] += d
				slideMax = math.max(slideMax, d / DT)
				contact[k] += 1
			end
			sink = math.min(sink, b["sole" .. k])
		end
	end
	out.slideL, out.slideR, out.slideMaxSpeed = r4(slide.L), r4(slide.R), r4(slideMax)
	out.contactFramesL, out.contactFramesR = contact.L, contact.R
	out.sinkMin = r4(sink)
	return out
end

local function partPen(model, rec)
	local lt = model:FindFirstChild("LowerTorso")
	for _, s in ipairs({ "Left", "Right" }) do
		local ul = model:FindFirstChild(s .. "UpperLeg")
		local n, d = penetration(ul, lt)
		rec[s .. "ThighInPelvis"] = { n = n, deep = r4(d) }
		local n2, d2 = penetration(lt, ul)
		rec[s .. "PelvisInThigh"] = { n = n2, deep = r4(d2) }
	end
end

-- per-frame series of a clip's samples (for plots / the report)
local function seriesOf(SALL)
	local keys = { "t", "v", "rootZ", "rootYaw", "pelvisY", "headY", "headPitch", "hipL", "hipR", "thighL", "thighR", "kneeL", "kneeR", "ankleL", "ankleR",
		"footPitchL", "footPitchR", "shoulderL", "shoulderR", "elbowL", "elbowR", "wristL", "pelvisYaw", "chestYaw", "trunkPitch", "soleL",
		"soleR", "handZL", "handZR" }
	local ser = {}
	for _, x in ipairs(SALL) do
		local row = {}
		for _, k in ipairs(keys) do
			row[k] = r4(x[k])
		end
		row.ankleZL, row.ankleZR = r4(x.anklePL.Z), r4(x.anklePR.Z)
		local pv = SALL[#ser]
		for _, k in ipairs({ "L", "R" }) do
			local slip = 0
			if pv and pv["sole" .. k] < 0.012 and x["sole" .. k] < 0.012 then
				local q = pv["pts" .. k][pv["soleI" .. k]]
				local pa, pb = pv["footCF" .. k] * q, x["footCF" .. k] * q
				slip = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude
			end
			row["slip" .. k] = r4(slip)
		end
		table.insert(ser, row)
	end
	return ser
end

------------------------------------------------------------------------
-- walking clips
------------------------------------------------------------------------
-- walk = Config.TownWalkSpeed (StarterPlayer.CharacterWalkSpeed), jog = the ring's base pace, run = Config.TownRunSpeed
-- (Shift), sprint = the roadwork pace (Main: 18 + Stamina x 0.06); --speeds walk=5,run=16 overrides
local SPEEDS = { walk = 6.5, jog = 11, run = 16, sprint = 22 }
for kv in (args.speeds or ""):gmatch("[^,]+") do
	local k, v = kv:match("(%a+)=([%d%.]+)")
	if k then
		SPEEDS[k] = tonumber(v)
	end
end
local function walkClip(clip, tier)
	local model, hum = makeBoxer(tier)
	model.Name = "Walker"
	player.Character = model
	player.CharacterAdded:Fire(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y0 = hrp.CFrame.Y
	local speed = SPEEDS[clip]
	-- settle standing, then accelerate over 0.5 s, then a steady pace
	local z = 0
	local v = 0
	local trace = {}
	local frames = {}
	local tStart = 0
	local total = 4.5
	local nSteps = math.floor(total / DT)
	local hist = {}
	local sample = gaitSampler(model)
	local S, SALL = {}, {}
	for i = 1, nSteps do
		local t = i * DT
		if t > 1 then
			v = math.min(speed, v + speed / 0.5 * DT)
		end
		z -= v * DT
		hrp.CFrame = CFrame.new(0, y0, z)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -v)
		hum.MoveDirection = v > 0 and Vector3.new(0, 0, -1) or Vector3.zero
		frame({ model })
		local smp = sample(t)
		smp.v = v
		if args.debugrig and t > tonumber(args.debugrig) and t < tonumber(args.debugrig) + 0.4 then
			local rg = H.require("AnimRig").rigs[model]
			local f = rg and rg.foot.L
			if f then
				print(string.format("dbg %.3f L swing=%s plan=%s push=%s pushOn=%s u=%.2f kAct=%.1f kVel=%.1f sigma=%.2f pitch=%.2f knee=%.0f reachShort=%.3f k0=%s kpk?",
					t, tostring(f.swing), tostring(f.plan), tostring(f.push), tostring(f.pushOn), f.planU or -1, math.deg(f.kAct or 0), math.deg(f.kVel or 0),
					f.sigma or -1, f.pitchS or 0, smp.kneeL, f.reachShort or 0, tostring(f.k0 and math.deg(f.k0))))
				print(string.format("    curZ %.3f tgtZ %.3f PZ %.3f t0 %.3f dur %.3f uS %.3f kind %s", f.cur and f.cur.Z or 0, f.tgtW and f.tgtW.Z or 0,
					f.P and f.P.Z or 0, f.t0, f.dur, (t - f.t0) / f.dur, tostring(f.stepKind)))
			end
		end
		table.insert(SALL, smp)
		if t > 2.5 then
			table.insert(S, smp)
		end
		if t > 2.5 then
			local lt = model:FindFirstChild("LowerTorso")
			local ut = model:FindFirstChild("UpperTorso")
			local head = model:FindFirstChild("Head")
			local rel = hrp.CFrame:Inverse() * lt.CFrame
			local relU = hrp.CFrame:Inverse() * ut.CFrame
			local relH = hrp.CFrame:Inverse() * head.CFrame
			local rx, ry, rz = rel:ToOrientation()
			table.insert(trace, { t = t, ltX = rel.X, ltY = rel.Y, utX = relU.X, headX = relH.X, roll = rz, yaw = ry, pitch = rx,
				lf = model:FindFirstChild("LeftFoot").Position, rf = model:FindFirstChild("RightFoot").Position })
			table.insert(hist, { t = t, i = i })
		end
		if t > 2.5 and tStart == 0 then
			tStart = t
		end
	end
	-- one gait cycle: from the trace, the period of the left foot's height
	local rig
	for _, r in pairs(H.cache) do
		_ = r
	end
	-- (re-run: record NFRAMES frames over the last cycle; the cycle length from the left foot's lifts)
	local lifts = {}
	for k = 2, #trace do
		local a, b = trace[k - 1].lf.Y, trace[k].lf.Y
		local thr = 0.5 * (model:FindFirstChild("LeftFoot").Size.Y)
		if a <= thr + 0.06 and b > thr + 0.06 then
			table.insert(lifts, trace[k].t)
		end
	end
	local period = (#lifts >= 2) and (lifts[#lifts] - lifts[#lifts - 1]) or 1
	-- sway stats over the trace
	local minX, maxX, minR, maxR, minU, maxU, minH, maxH = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, s in ipairs(trace) do
		minX, maxX = math.min(minX, s.ltX), math.max(maxX, s.ltX)
		minR, maxR = math.min(minR, s.roll), math.max(maxR, s.roll)
		minU, maxU = math.min(minU, s.utX), math.max(maxU, s.utX)
		minH, maxH = math.min(minH, s.headX), math.max(maxH, s.headX)
	end
	local rec = { clip = clip, tier = tier, speed = speed, period = r4(period), pelvisSwayX = r4(maxX - minX), chestSwayX = r4(maxU - minU),
		headSwayX = r4(maxH - minH), pelvisRollDeg = r4(math.deg(maxR - minR)), hipHeight = r4(hum.HipHeight), worstPen = {} }
	-- record NFRAMES frames over one more cycle
	local out = { clip = clip, tier = tier, speed = speed, frames = {} }
	local nCycle = math.max(1, math.floor(period / DT + 0.5))
	local every = nCycle / NFRAMES
	local nextAt = 0
	local worst = { n = 0, deep = 0 }
	for k = 0, nCycle - 1 do
		local t = (nSteps + k + 1) * DT
		z -= v * DT
		hrp.CFrame = CFrame.new(0, y0, z)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, -v)
		frame({ model })
		local pr = {}
		partPen(model, pr)
		do
			local ltp = model:FindFirstChild("LowerTorso")
			for _, sd in ipairs({ "Left", "Right" }) do
				local ul = model:FindFirstChild(sd .. "UpperLeg")
				local d = ltp.CFrame:VectorToObjectSpace(-ul.CFrame.UpVector)
				local flex = math.deg(math.atan2(-d.Z, -d.Y)) -- + = knee forward
				local abd = math.deg(math.atan2(d.X * (sd == "Right" and 1 or -1), -d.Y))
				rec.hipFlexMin = math.min(rec.hipFlexMin or 999, flex)
				rec.hipFlexMax = math.max(rec.hipFlexMax or -999, flex)
				rec.hipAbdMin = math.min(rec.hipAbdMin or 999, abd)
				rec.hipAbdMax = math.max(rec.hipAbdMax or -999, abd)
			end
		end
		for _, key in ipairs({ "LeftPelvisInThigh", "RightPelvisInThigh" }) do
			if pr[key].deep > worst.deep then
				worst = { n = pr[key].n, deep = pr[key].deep, key = key, phase = r4(k / nCycle) }
			end
		end
		if k >= nextAt - 1e-6 and #out.frames < NFRAMES then
			nextAt += every
			local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
			fr.root = cfList(hrp.CFrame)
			fr.pen = pr
			table.insert(out.frames, fr)
		end
	end
	rec.worstPen = worst
	rec.gait = gaitSummary(S)
	rec.start = gaitSummary((function()
		local o = {}
		for _, x in ipairs(SALL) do
			if x.t > 0.9 and x.t <= 2.5 then
				table.insert(o, x)
			end
		end
		return o
	end)())
	do
		local g = rec.gait
		local function rg(k)
			return g[k][2] - g[k][1]
		end
		print(string.format("      knee %.0f..%.0f  hip %.0f..%.0f  thigh %.0f..%.0f  ankle %.0f..%.0f  footPitch %.0f..%.0f", g.kneeL[1], g.kneeL[2],
			g.hipL[1], g.hipL[2], g.thighL[1], g.thighL[2], g.ankleL[1], g.ankleL[2], g.footPitchL[1], g.footPitchL[2]))
		print(string.format("      shoulder %.0f..%.0f  elbow %.0f..%.0f  wrist %.0f..%.0f  pelvisYaw %.1f..%.1f  chestYaw %.1f..%.1f  trunkPitch %.1f..%.1f",
			g.shoulderL[1], g.shoulderL[2], g.elbowL[1], g.elbowL[2], g.wristL[1], g.wristL[2], g.pelvisYaw[1], g.pelvisYaw[2], g.chestYaw[1],
			g.chestYaw[2], g.trunkPitch[1], g.trunkPitch[2]))
		print(string.format("      bob pelvis %.3f head %.3f  head pitch %.1f..%.1f roll %.1f..%.1f  sole %.3f..%.3f  slide L %.3f R %.3f (max %.2f studs/s)  start slide %.3f/%.3f sink %.3f",
			rg("pelvisY"), rg("headY"), g.headPitch[1], g.headPitch[2], g.headRoll[1], g.headRoll[2], g.soleL[1], g.soleL[2], g.slideL, g.slideR,
			g.slideMaxSpeed, rec.start.slideL, rec.start.slideR, math.min(g.sinkMin, rec.start.sinkMin)))
	end
	do
		local ser = seriesOf(SALL)
		Host.WriteJSON(string.format("%s/gait_%s_t%d%s.json", OUT, clip, tier, HTAG), { clip = clip, tier = tier, speed = speed, height = HEIGHT,
			period = rec.period, summary = rec.gait, start = rec.start, series = ser })
	end
	print(string.format("      hip flex %.0f..%.0f deg, abduction %.0f..%.0f deg", rec.hipFlexMin, rec.hipFlexMax, rec.hipAbdMin, rec.hipAbdMax))
	local file = string.format("%s_t%d%s.json", clip, tier, HTAG)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("%s_t%d%s", clip, tier, HTAG), file = file, clip = clip, tier = tier, n = #out.frames })
	rec.height = HEIGHT
	table.insert(metrics, rec)
	print(string.format("%-5s T%d v=%4.1f period %.3f  pelvis sway %.3f  chest sway %.3f  head sway %.3f  pelvis roll %.1f deg  hip %.3f  worst pelvis-in-thigh %d verts %.3f (%s @%.2f)",
		clip, tier, speed, period, rec.pelvisSwayX, rec.chestSwayX, rec.headSwayX, rec.pelvisRollDeg, rec.hipHeight, worst.n, worst.deep,
		tostring(worst.key), worst.phase or 0))
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- scripted clips: start / stop, turning in place, a walking turn. The root moves along its own facing at
-- speed(t), turning at yawRate(t) (rad/s, + = left); every frame sampled, frames recorded at the given times
------------------------------------------------------------------------
local SCRIPTS = {
	startstop = { total = 4.6, shots = { 0.95, 1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.7, 2.95, 3.05, 3.15, 3.25, 3.35, 3.5, 3.7, 4.0, 4.5 }, speed = function(t)
		local W = SPEEDS.walk
		if t < 1 then
			return 0
		-- (a Humanoid on the ground gets to its WalkSpeed and back to rest in a few frames: a 0.12 s ramp)
		elseif t < 1.12 then
			return W * (t - 1) / 0.12
		elseif t < 3 then
			return W
		elseif t < 3.12 then
			return W * (1 - (t - 3) / 0.12)
		end
		return 0
	end, yaw = function()
		return 0
	end },
	turn = { total = 3.4, shots = { 0.95, 1.1, 1.25, 1.4, 1.55, 1.7, 1.85, 2.0, 2.2, 2.5, 2.9, 3.3 }, speed = function()
		return 0
	end, yaw = function(t)
		return (t > 1 and t < 1 + PI / 3.5) and 3.5 or 0
	end },
	curve = { total = 4.4, shots = { 1.8, 1.95, 2.1, 2.25, 2.4, 2.55, 2.7, 2.85, 3.0, 3.15, 3.3, 3.45 }, speed = function(t)
		return t < 1 and 0 or SPEEDS.walk * math.min(1, (t - 1) / 0.12)
	end, yaw = function(t)
		return (t > 1.8 and t < 1.8 + (PI / 2) / 1.6) and 1.6 or 0
	end },
}
local function scriptClip(clip, tier)
	local sc = SCRIPTS[clip]
	local model, hum = makeBoxer(tier)
	model.Name = "Walker"
	player.Character = model
	player.CharacterAdded:Fire(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local y0 = hrp.CFrame.Y
	local sample = gaitSampler(model)
	local x, z, yaw = 0, 0, 0
	local S = {}
	local out = { clip = clip, tier = tier, frames = {} }
	local shot = 1
	local maxJ = { knee = 0, hip = 0, shoulder = 0, elbow = 0, pelvisY = 0, headY = 0 }
	for i = 1, math.floor(sc.total / DT) do
		local t = i * DT
		local v, yr = sc.speed(t), sc.yaw(t)
		yaw += yr * DT
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		x += fx * v * DT
		z += fz * v * DT
		hrp.CFrame = CFrame.new(x, y0, z) * CFrame.Angles(0, yaw, 0)
		hrp.AssemblyLinearVelocity = Vector3.new(fx * v, 0, fz * v)
		hrp.AssemblyAngularVelocity = Vector3.new(0, yr, 0)
		hum.MoveDirection = v > 0.05 and Vector3.new(fx, 0, fz) or Vector3.zero
		frame({ model })
		local smp = sample(t)
		smp.v = v
		if args.debugrig and t > tonumber(args.debugrig) and t < tonumber(args.debugrig) + 0.3 then
			local rg = H.require("AnimRig").rigs[model]
			for _, sd in ipairs({ "L", "R" }) do
				local f = rg and rg.foot[sd]
				if f then
					print(string.format("dbg %.3f %s swing=%s push=%s sigma=%.2f pitch=%.2f knee=%.0f reachShort=%.3f excess=%.3f need=%.3f drop=%.3f run=%.2f",
						t, sd, tostring(f.swing), tostring(f.push), f.sigma or -1, f.pitchS or 0, smp["knee" .. sd], f.reachShort or 0, f.excess or 0,
						f.needDrop or -1, rg.loco.drop or 0, rg.loco.run))
				end
			end
		end
		local pv = S[#S]
		if pv then
			for k, key in pairs({ knee = "knee", hip = "hip", shoulder = "shoulder", elbow = "elbow" }) do
				for _, sd in ipairs({ "L", "R" }) do
					maxJ[k] = math.max(maxJ[k], math.abs(smp[key .. sd] - pv[key .. sd]))
				end
			end
			maxJ.pelvisY = math.max(maxJ.pelvisY, math.abs(smp.pelvisY - pv.pelvisY))
			maxJ.headY = math.max(maxJ.headY, math.abs(smp.headY - pv.headY))
		end
		table.insert(S, smp)
		local every = tonumber(args.shotevery)
		if every then
			-- (--shotevery N: a frame every N frames from 0.9 s on - an even clock for a GIF)
			if t > 0.9 and i % every == 0 then
				local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
				fr.root = cfList(hrp.CFrame)
				fr.label = string.format("%.2f s  v %.1f", t, v)
				table.insert(out.frames, fr)
			end
		elseif sc.shots[shot] and t >= sc.shots[shot] - 1e-6 then
			shot += 1
			local fr = NOMESH and { t = r4(t) } or exportFrame(model, t)
			fr.root = cfList(hrp.CFrame)
			fr.label = string.format("%.2f s  v %.1f", t, v)
			table.insert(out.frames, fr)
		end
	end
	local g = gaitSummary(S)
	local rec = { clip = clip, tier = tier, height = HEIGHT, gait = g, maxFrameStep = {} }
	Host.WriteJSON(string.format("%s/gait_%s_t%d%s.json", OUT, clip, tier, HTAG), { clip = clip, tier = tier, height = HEIGHT, summary = g,
		series = seriesOf(S) })
	for k, v in pairs(maxJ) do
		rec.maxFrameStep[k] = r4(v)
	end
	print(string.format("%-9s T%d  slide L %.3f R %.3f  sink %.3f  max per-frame step: knee %.1f hip %.1f shoulder %.1f elbow %.1f deg, pelvis %.3f head %.3f",
		clip, tier, g.slideL, g.slideR, g.sinkMin, maxJ.knee, maxJ.hip, maxJ.shoulder, maxJ.elbow, maxJ.pelvisY, maxJ.headY))
	local file = string.format("%s_t%d%s.json", clip, tier, HTAG)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("%s_t%d%s", clip, tier, HTAG), file = file, clip = clip, tier = tier, n = #out.frames })
	table.insert(metrics, rec)
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

------------------------------------------------------------------------
-- punches
------------------------------------------------------------------------
local PUNCH_LIST = {
	{ "jab", "jab|L|head|0.16|0.8" }, { "cross", "cross|R|head|0.2|0.9" }, { "leadhook", "leadhook|L|head|0.2|0.9" },
	{ "rearhook", "rearhook|R|head|0.22|0.9" }, { "uppercut", "uppercut|R|head|0.22|0.9" }, { "bodyjab", "jab|L|body|0.16|0.8" },
}
local function punchClip(tier)
	local a, humA = makeBoxer(tier)
	a.Name = "BoxerA"
	local b, humB = makeBoxer(3, { gloves = 2, trunks = 4 })
	b.Name = "BoxerB"
	local GAP = tonumber(args.gap) or 4.0
	local ha, hb = a:FindFirstChild("HumanoidRootPart"), b:FindFirstChild("HumanoidRootPart")
	ha.CFrame = CFrame.new(0, ha.CFrame.Y, GAP / 2) -- faces -Z (towards B)
	hb.CFrame = CFrame.new(0, hb.CFrame.Y, -GAP / 2) * CFrame.Angles(0, math.pi, 0)
	for _, m in ipairs({ a, b }) do
		m:SetAttribute("Guard", "up")
		m:SetAttribute("Style", "BoxerPuncher")
		CS:AddTag(m, "Fighter")
	end
	for _ = 1, 150 do
		frame({ a, b })
	end
	local out = { clip = "punch", tier = tier, frames = {} }
	local recs = {}
	local actId = 0
	for _, pd in ipairs(PUNCH_LIST) do
		local name, act = pd[1], pd[2]
		local hand = act:match("^[^|]*|(%a)")
		local handPart = a:FindFirstChild(hand == "L" and "LeftHand" or "RightHand")
		local glove
		for _, d in ipairs(a:GetDescendants()) do
			if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d.Name == "Glove" .. hand then
				glove = d
			end
		end
		glove = glove or handPart
		actId += 1
		a:SetAttribute("Act", act)
		a:SetAttribute("ActId", actId)
		local best, bestK, samples = -math.huge, 0, {}
		local nF = 60
		local wmax = { 0, 0, 0 }
		for k = 1, nF do
			frame({ a, b })
			do
				local rel = a:FindFirstChild("LowerTorso").CFrame:Inverse() * a:FindFirstChild("UpperTorso").CFrame
				local rx, ry, rz = rel:ToEulerAnglesYXZ()
				wmax[1] = math.max(wmax[1], math.abs(math.deg(rx)))
				wmax[2] = math.max(wmax[2], math.abs(math.deg(ry)))
				wmax[3] = math.max(wmax[3], math.abs(math.deg(rz)))
			end
			-- reach: how far the glove went toward B (along -Z from A's root)
			local reach = -(glove.Position.Z - ha.Position.Z)
			samples[k] = { reach = reach, t = VT, gp = glove.Position }
			if reach > best then
				best, bestK = reach, k
			end
		end
		-- replay to capture: windup / mid / peak frames
		actId += 1
		for _ = 1, 40 do
			frame({ a, b })
		end
		a:SetAttribute("Act", act)
		a:SetAttribute("ActId", actId)
		local capture = { [math.max(1, math.floor(bestK * 0.2))] = "start", [math.max(1, math.floor(bestK * 0.45))] = "windup",
			[math.max(1, math.floor(bestK * 0.7))] = "drive", [math.max(1, math.floor(bestK * 0.87))] = "extend", [bestK] = "peak",
			[math.min(nF, bestK + math.max(3, math.floor(bestK * 0.5)))] = "return" }
		local peakPen
		for k = 1, nF do
			frame({ a, b })
			if capture[k] then
				local fr = NOMESH and { t = r4(VT) } or exportFrame(a, VT)
				fr.label = name .. " " .. capture[k]
				fr.opp = (not NOMESH) and exportFrame(b, VT) or nil
				table.insert(out.frames, fr)
				if capture[k] == "peak" then
					local headB = b:FindFirstChild("Head")
					local ut = b:FindFirstChild("UpperTorso")
					local tgt = act:find("|body|") and ut.Position or headB.Position
					peakPen = { glove = { r4(glove.Position.X), r4(glove.Position.Y), r4(glove.Position.Z) },
						toTarget = r4((glove.Position - tgt).Magnitude), dy = r4(glove.Position.Y - tgt.Y),
						elbowDeg = nil }
					-- elbow angle (upper vs lower arm axis)
					local ua = a:FindFirstChild(hand == "L" and "LeftUpperArm" or "RightUpperArm")
					local la = a:FindFirstChild(hand == "L" and "LeftLowerArm" or "RightLowerArm")
					peakPen.elbowDeg = r4(math.deg(math.acos(math.clamp(ua.CFrame.UpVector:Dot(la.CFrame.UpVector), -1, 1))))
				end
			end
		end
		for _ = 1, 40 do
			frame({ a, b })
		end
		table.insert(recs, { punch = name, reach = r4(best), peakFrame = bestK, peak = peakPen })
		print(string.format("      waist max |pitch| %.0f |yaw| %.0f |roll| %.0f deg", wmax[1], wmax[2], wmax[3]))
		print(string.format("punch T%d %-9s reach %.3f (frame %d)  glove->target %.3f  dy %+.3f  elbow %.0f deg", tier, name, best, bestK,
			peakPen and peakPen.toTarget or -1, peakPen and peakPen.dy or 0, peakPen and peakPen.elbowDeg or -1))
	end
	local file = string.format("punch_t%d.json", tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("punch_t%d", tier), file = file, clip = "punch", tier = tier, n = #out.frames })
	table.insert(metrics, { clip = "punch", tier = tier, punches = recs })
	for _, m in ipairs({ a, b }) do
		CS:RemoveTag(m, "Fighter")
		m:Destroy()
	end
	for _ = 1, 3 do
		frame({})
	end
end

local function restClip(tier)
	local model = makeBoxer(tier)
	if args.debugfoot then
		gaitSampler(model)
		for _, d in ipairs(model:GetDescendants()) do
			if (d.ClassName == "Weld" or d.ClassName == "WeldConstraint") and d.Part0 and (d.Part0.Name == "LeftFoot") then
				local rel = d.Part0.CFrame:Inverse() * d.Part1.CFrame
				print("  on LeftFoot:", d.Part1.Name, d.Part1.ClassName, tostring(d.Part1.Size), tostring(rel.Position), d.Part1.Transparency)
			end
		end
	end
	model.Name = "Stander"
	player.Character = model
	player.CharacterAdded:Fire(model)
	for _ = 1, 120 do
		frame({ model })
	end
	local out = { clip = "rest", tier = tier, frames = { exportFrame(model, VT) } }
	out.frames[1].root = cfList(model:FindFirstChild("HumanoidRootPart").CFrame)
	local file = string.format("rest_t%d.json", tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("rest_t%d", tier), file = file, clip = "rest", tier = tier, n = 1 })
	player.Character = nil
	model:Destroy()
	for _ = 1, 3 do
		frame({})
	end
end

for _, tier in ipairs(TIERS) do
	if CLIPS.rest then
		restClip(tier)
	end
	for _, clip in ipairs({ "walk", "jog", "run", "sprint" }) do
		if CLIPS[clip] then
			walkClip(clip, tier)
		end
	end
	for _, clip in ipairs({ "startstop", "turn", "curve" }) do
		if CLIPS[clip] then
			scriptClip(clip, tier)
		end
	end
	if CLIPS.punch then
		punchClip(tier)
	end
end
Host.WriteJSON(OUT .. "/index.json", index, true)
Host.WriteJSON(OUT .. "/metrics.json", metrics, true)
print("out:", OUT)
process.exit(0)
