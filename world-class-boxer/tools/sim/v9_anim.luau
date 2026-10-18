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

------------------------------------------------------------------------
-- host: fake engine, virtual clock, the asset simulator (Content)
------------------------------------------------------------------------
local root = Host.FindRoot()
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
local REAL = BodyTiers.Data()
BodyTiers.SetData(REAL)

-- mesh id -> file (tier parts and gear): through tools/body/uploaded.json
local MESH_FILES = {}
do
	local up = root .. "/tools/body/uploaded.json"
	if fs.isFile(up) then
		for _, e in pairs(serde.decode("json", fs.readFile(up))) do
			if type(e.file) == "string" and type(e.id) == "number" then
				MESH_FILES[e.id] = root .. "/tools/body/" .. e.file
			end
		end
	end
end
local FACE_FILES = {}
for _, f in ipairs(REAL.faces or {}) do
	if f.id and f.id ~= 0 then
		FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/face_" .. f.key .. ".png"
	end
end
do
	local path = srcDir .. "/shared/GearAssetData.lua"
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
	local _, b = buildFor(app, tier)
	local sc = Builder.Scales(app, b)
	local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	model.Parent = E.workspace
	currentModel = model
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = spec.hands or "gloves", detail = "full" })
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
		return string.format("%s/tools/body/out/tier%d/%s.mesh", root, tier, p.Name)
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

------------------------------------------------------------------------
-- walking clips
------------------------------------------------------------------------
local SPEEDS = { walk = 5, jog = 11, run = 16 }
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
		for _, key in ipairs({ "LeftThighInPelvis", "RightThighInPelvis" }) do
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
	local file = string.format("%s_t%d.json", clip, tier)
	Host.WriteJSON(OUT .. "/" .. file, out)
	table.insert(index.clips, { id = string.format("%s_t%d", clip, tier), file = file, clip = clip, tier = tier, n = #out.frames })
	table.insert(metrics, rec)
	print(string.format("%-5s T%d v=%4.1f period %.3f  pelvis sway %.3f  chest sway %.3f  head sway %.3f  pelvis roll %.1f deg  hip %.3f  worst thigh-in-pelvis %d verts %.3f (%s @%.2f)",
		clip, tier, speed, period, rec.pelvisSwayX, rec.chestSwayX, rec.headSwayX, rec.pelvisRollDeg, rec.hipHeight, worst.n, worst.deep,
		tostring(worst.key), worst.phase or 0))
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
	local GAP = 3.4
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
			if (d.ClassName == "MeshPart" or d.ClassName == "Part") and d:GetAttribute("GearSlot") == "gloves" and d.Name:find(hand == "L" and "_L" or "_R") then
				glove = d
			end
		end
		glove = glove or handPart
		actId += 1
		a:SetAttribute("Act", act)
		a:SetAttribute("ActId", actId)
		local best, bestK, samples = -math.huge, 0, {}
		local nF = 60
		for k = 1, nF do
			frame({ a, b })
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
		local capture = { [math.max(1, math.floor(bestK * 0.35))] = "windup", [math.max(1, math.floor(bestK * 0.7))] = "mid", [bestK] = "peak" }
		local peakPen
		for k = 1, nF do
			frame({ a, b })
			if capture[k] then
				local fr = NOMESH and { t = r4(VT) } or exportFrame(a, VT)
				fr.label = name .. " " .. capture[k]
				fr.opp = (capture[k] == "peak" and not NOMESH) and exportFrame(b, VT) or nil
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

for _, tier in ipairs(TIERS) do
	for _, clip in ipairs({ "walk", "jog", "run" }) do
		if CLIPS[clip] then
			walkClip(clip, tier)
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
