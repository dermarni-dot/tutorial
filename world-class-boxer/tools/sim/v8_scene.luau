--!nocheck
-- v8_scene.luau: COMPLETE v8 boxers as the game draws them, exported in world space for tools/sim/v8_render.py.
-- Nothing is placed by hand: for every look below
--   * the server's Builder.Cosmetics runs on a fake R15 rig (fakeengine Instances; the rig, the fake Humanoid and the
--     fake AssetService as in test_bodytiers.luau): the muscle-tier swap (BuilderTiers), the classic head and its face
--     decal (BuilderHead), the gloves / trunks / boots (BuilderBody). The rig's joints are solved here the way the
--     engine does (Motor6D: Part1 = Part0 * C0 * Transform * C1^-1; Weld the same; WeldConstraint keeps the offset it
--     was made with), after every step that moves a joint, so each layer is built on the parts where they really are
--   * the client's HairAssets.For / HairAssets.Build run on the look the server published (LookData.Get), with the
--     local hair manifest served by assetsim.luau (as after_scene.luau): the pieces' meshes, sizes, Head-space centres
--     and tinted textures are the module's own
-- Then every visible part is written out:
--   * tier MeshParts: tools/body/out/tier<n>/<Part>.mesh recentred on its bbox, scaled to Size, by the part CFrame
--   * the classic head: { shape = "classichead", cf, size, classic = AnatomyHairKit.CLASSIC } (the renderer revolves
--     the same rounded cylinder AnatomyHairKit.ClassicField measures), its face decal { file } on the front
--   * the gear meshes (BuilderGear, GearAssetData): tools/body/out/gear/<file>.mesh recentred on its bbox, scaled to
--     Size, by the piece's CFrame (the weld solved like the joints), { gear = true, slot }
--   * Kit.mk gear (the part-built fallback, text patches): { shape = Block | Ball | Cylinder | Ellipsoid | Wedge, cf,
--     size, color, material, reflectance }
--   * hair pieces: world-space triangles + the tinted texture (.rgba) per piece (the round-1 BoxerLook/Hair parts are
--     left out: AnatomyClient hides them once the asset hair is built)
-- and the hair's fit on the classic head is measured per region (the field AnatomyHairKit.Scalp uses).
--
--   lune run tools/sim/v8_scene.luau [--out DIR] [--only id,id] [--manifest PATH] [--no-regen] [--gear PATH]
--
-- --gear: the gear manifest (default src/shared/GearAssetData.lua when it has uploaded ids, else the local one
-- publish_gear.py --local writes, /tmp/claude-0/GearAssetData_local.lua); mesh ids map to their files through
-- tools/body/uploaded.json (real ids) or the local manifest's .ids.json sidecar (fake ids)
--
-- Output: <out>/index.json { looks = [...] }, <out>/<id>.json, <out>/<id>_<tex>.rgba
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
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
		if k == "--no-regen" then
			args.noRegen = true
			i += 1
		else
			args[k:gsub("^%-%-", "")] = a[i + 1]
			i += 2
		end
	end
end
local OUT = (args.out or (SCRATCH .. "/v8scene")):gsub("/$", "")
local MANIFEST = args.manifest or AssetSim.LOCAL_MANIFEST
local only
if args.only then
	only = {}
	for id in args.only:gmatch("[^,]+") do
		only[id] = true
	end
end

------------------------------------------------------------------------
-- the looks
------------------------------------------------------------------------
-- tier = the muscle tier wanted on every part (the build value is searched for it through BodyTiers);
-- hair colour = a Looks.HairColors index; pose = "rest" | "guard"
local LOOKS = {
	{ id = "m1_buzz", label = "Male tier 1, Buzz Cut, black", g = 1, tier = 1, skin = 3, frame = "Lean",
		hair = { style = "Buzz Cut", type = "Straight", color = 1 }, face = "smile", gloves = 1, trunks = 3, trim = 1, trunkStyle = "Classic" },
	{ id = "m3_highfade", label = "Male tier 3, High Fade, kinky", g = 1, tier = 3, skin = 9, frame = "Athletic",
		hair = { style = "High Fade", type = "Kinky", color = 1 }, face = "confident", gloves = 2, trunks = 4, trim = 2, trunkStyle = "Striped" },
	{ id = "m5_shortdreads", label = "Male tier 5, Short Dreads (default style)", g = 1, tier = 5, skin = 6, frame = "Athletic",
		hair = nil, face = "smile", gloves = 1, trunks = 3, trim = 1 },
	{ id = "m4_afro", label = "Male tier 4, Afro", g = 1, tier = 4, skin = 10, frame = "Power Build",
		hair = { style = "Afro", type = "Kinky", color = 2 }, face = "grin", gloves = 5, trunks = 7, trim = 5, trunkStyle = "Long", shoeStyle = "Low-Top", hands = "wraps" },
	{ id = "f2_boxbraids", label = "Female tier 2, Box Braids", g = 2, tier = 2, skin = 8, frame = "Athletic",
		hair = { style = "Box Braids", type = "Kinky", color = 1 }, face = "smirk", gloves = 10, trunks = 3, trim = 10 },
	{ id = "f3_long", label = "Female tier 3, Long Hair straight brown", g = 2, tier = 3, skin = 2, frame = "Athletic",
		hair = { style = "Long Hair", type = "Straight", color = 3 }, face = "smile", gloves = 2, trunks = 2, trim = 4, trunkStyle = "Classic", shoeStyle = "Low-Top" },
	{ id = "m5_guard", label = "Male tier 5, guard pose (default look)", g = 1, tier = 5, skin = 6, frame = "Athletic",
		hair = nil, face = "determined", gloves = 1, trunks = 3, trim = 1, pose = "guard" },
}

------------------------------------------------------------------------
-- host: fake engine + the asset hair simulator
------------------------------------------------------------------------
local root = Host.FindRoot()
if not args.noRegen then
	AssetSim.EnsureManifest(root, MANIFEST)
end
local E = FE.new()
local sim = AssetSim.new({ root = root, manifest = MANIFEST, newPart = function()
	return E.new("MeshPart")
end })
sim.Preload()
local H = Host.new({ root = root, globals = { Content = sim.Content, Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
H.Service("AssetService")._props = sim.AssetService
AssetSim.UseManifest(H, MANIFEST)

local Looks = H.require("Looks")
local LookData = H.require("LookData")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderBody = H.require("BuilderBody")
local BuilderHair = H.require("BuilderHair")
local Builder = H.require("Builder")
local HA = H.require("Client/HairAssets")
local HK = H.require("HairAssetKit")
local Kit = H.require("AnatomyHairKit")
local REAL = BodyTiers.Data()
BodyTiers.SetData(REAL)

-- face texture id -> png
local FACE_FILES = {}
-- (the drawn faces' files carry their revision: faces.json names each key's file, e.g. face_wcb_grit_v2.png)
local FACE_JSON = {}
do
	local fj = root .. "/tools/body/out/faces/faces.json"
	if fs.isFile(fj) then
		for _, e in ipairs(require("@lune/serde").decode("json", fs.readFile(fj)).faces or {}) do
			FACE_JSON[e.key] = e.file
		end
	end
end
for _, f in ipairs(REAL.faces or {}) do
	if f.id and f.id ~= 0 then
		FACE_FILES["rbxassetid://" .. f.id] = root .. "/tools/body/out/faces/" .. (FACE_JSON[f.key] or ("face_" .. f.key .. ".png"))
	end
end

------------------------------------------------------------------------
-- the fake R15 rig (test_bodytiers.luau's, plus the default head)
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

-- the engine's joint solve: every Motor6D / Weld from the root out, WeldConstraints by their recorded offsets
local weldOffsets = setmetatable({}, { __mode = "k" })
local function solve(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	hrp.CFrame = CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
	local done = { [hrp] = true }
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" or d.ClassName == "Weld" or (d.ClassName == "WeldConstraint" and weldOffsets[d]) then
			table.insert(joints, d)
		end
	end
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
-- WeldConstraints keep the offset their parts had when they were made: recorded on the solved rest pose
local function recordWelds(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "WeldConstraint" and d.Part0 and d.Part1 then
			weldOffsets[d] = d.Part0.CFrame:Inverse() * d.Part1.CFrame
		end
	end
end

local function newRig(scale, headSize)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.Transparency = 1
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
	-- the engine's default head (a MeshPart; BuilderHead swaps in the classic head of the same size)
	addPart("Head", Vector3.new(headSize, headSize, headSize), Vector3.new(1.2, 1.2, 1.2),
		{ NeckRigAttachment = { cur = Vector3.new(0, -0.5 * headSize, 0), orig = Vector3.new(0, -0.6, 0) } })
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
	end
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	-- the engine's ReplaceBodyPartR15: the new part scaled from its OriginalSize x the description's scale, the
	-- joints moved over to it (C0 / C1 left as they were: BuilderTiers / Builder re-aim them), the old part gone
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

-- a fake AssetService for the tier meshes: CreateMeshPartAsync -> a MeshPart remembering its id
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

-- the gear meshes: the same fake AssetService, the gear manifest, id -> mesh file
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local BuilderGear = H.require("BuilderGear")
local GEAR_FILES = {}
local GEAR_MANIFEST
do
	local function loadLua(path)
		return luau.load(fs.readFile(path), { debugName = path })()
	end
	local function hasIds(t)
		for _, tier in ipairs(t.tiers or {}) do
			for _, e in pairs(tier) do
				if (e.mesh or 0) > 0 then
					return true
				end
			end
		end
		return false
	end
	local srcPath = root .. "/src/shared/GearAssetData.lua"
	local path = args.gear
	if not path then
		path = (fs.isFile(srcPath) and hasIds(loadLua(srcPath))) and srcPath or "/tmp/claude-0/GearAssetData_local.lua"
	end
	if path:find("_local") and not args.noRegen then
		process.exec("python3", { root .. "/tools/body/publish_gear.py", "--local", path })
	end
	GEAR_MANIFEST = path
	BuilderGear.SetData(loadLua(path))
	local up = root .. "/tools/body/uploaded.json"
	if fs.isFile(up) then
		for _, e in pairs(serde.decode("json", fs.readFile(up))) do
			if type(e.file) == "string" and e.file:find("^out/gear/") then
				GEAR_FILES[e.id] = root .. "/tools/body/" .. e.file
			end
		end
	end
	local side = path:gsub("%.lua$", "") .. ".ids.json"
	if fs.isFile(side) then
		for id, f in pairs(serde.decode("json", fs.readFile(side)).ids or {}) do
			GEAR_FILES[tonumber(id)] = f
		end
	end
end
BuilderGear.Reset()
BuilderGear.Services = BuilderTiers.Services
print("gear manifest:", GEAR_MANIFEST)

-- the steps after a joint moved (the tier swap re-aims C0 / C1; the face step swaps and seats the head) see the
-- parts where the engine would have put them
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

------------------------------------------------------------------------
-- helpers
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

local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end
-- the lowest build value that shows `tier` on every part
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

-- per-region distances of points (Head space, real studs) to the classic head (nominal studs, as fit_classic_hair)
local function regionOf(x, y, z)
	-- nominal coordinates: x, z around the cylinder axis, y up
	local C = Kit.CLASSIC
	local rho = math.sqrt(x * x + z * z)
	local inner = C.r - C.round
	local yTop = C.h - C.round
	if y > yTop and rho > inner then
		return "corner"
	elseif y > yTop then
		return "top"
	elseif y < -yTop then
		return "below"
	elseif z < -0.25 then
		return "front"
	elseif z > 0.25 then
		return "back"
	else
		return "side"
	end
end
local function quant(list)
	table.sort(list)
	local n = #list
	if n == 0 then
		return nil
	end
	local function at(q)
		return list[math.clamp(math.floor(q * (n - 1) + 1.5), 1, n)]
	end
	return { n = n, min = r4(list[1]), p10 = r4(at(0.1)), med = r4(at(0.5)), p90 = r4(at(0.9)), max = r4(list[n]) }
end

------------------------------------------------------------------------
-- one look
------------------------------------------------------------------------
Host.MkDir(OUT)
local index = { about = "v8 boxers: Builder.Cosmetics on a fake rig + HairAssets.Build (local manifest), world space, studs, +Y up, face -Z",
	looks = {} }
local report = {}

for _, L in ipairs(LOOKS) do
	if only and not only[L.id] then
		continue
	end
	local app = Looks.Defaults(L.g)
	app.skin = L.skin
	app.body.frame = L.frame
	if L.hair then
		app.hair.style = L.hair.style
		app.hair.type = L.hair.type
		app.hair.color = table.clone(Looks.HairColors[L.hair.color])
	end
	app.face.key = L.face
	app.gloves.color = pal(L.gloves)
	app.attire.trunks = pal(L.trunks)
	app.attire.trim = pal(L.trim)
	app.attire.trunkStyle = L.trunkStyle or app.attire.trunkStyle
	app.attire.shoeStyle = L.shoeStyle or app.attire.shoeStyle
	local bv, b = buildFor(app, L.tier)
	local sc = Builder.Scales(app, b)
	local headSize = 1.2 * sc.head
	local model = newRig(Vector3.new(sc.width, sc.height, sc.depth), headSize)
	model.Parent = E.workspace
	currentModel = model
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = L.hands or "gloves", detail = "full" })
	if not ok then
		error(L.id .. ": Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	recordWelds(model)
	local key = model:GetAttribute("BodyTiers")
	-- the pose: Motor6D.Transform as the Animator writes it
	if L.pose == "guard" then
		local function tr(name, cf)
			for _, d in ipairs(model:GetDescendants()) do
				if d.ClassName == "Motor6D" and d.Name == name then
					d.Transform = cf
				end
			end
		end
		local R = math.rad
		-- orthodox guard: left hand forward at chin height, right hand at the cheek, elbows in, chin down, knees soft
		-- (fromEulerAnglesYXZ = Ry * Rx * Rz: the limb flares (Z), pitches forward (X), then turns (Y))
		local function ypr(pitch, yaw, roll)
			return CFrame.fromEulerAnglesYXZ(R(pitch), R(yaw), R(roll))
		end
		tr("LeftShoulder", ypr(42, -22, 6))
		tr("LeftElbow", ypr(112, 0, 0))
		tr("LeftWrist", ypr(-12, 0, 0))
		tr("RightShoulder", ypr(30, 30, -6))
		tr("RightElbow", ypr(132, 0, 0))
		tr("RightWrist", ypr(-12, 0, 0))
		tr("Waist", ypr(5, -10, 0))
		tr("Neck", ypr(-8, 10, 0))
		tr("Root", CFrame.new(0, -0.14, 0) * ypr(0, 14, 0))
		tr("LeftHip", ypr(16, 6, -4))
		tr("LeftKnee", ypr(-20, 0, 0))
		tr("LeftAnkle", ypr(4, 0, 0))
		tr("RightHip", ypr(-8, -16, 6))
		tr("RightKnee", ypr(-18, 0, 0))
		tr("RightAnkle", ypr(26, 0, 0))
		solve(model)
	end

	local scene = { id = L.id, label = L.label, tierKey = key, build = bv, frame = L.frame, g = L.g, parts = {}, meshes = {}, hair = {} }
	local look = LookData.Get(model)
	local head = model:FindFirstChild("Head")
	local hcf = head.CFrame
	local lookFolder = model:FindFirstChild("BoxerLook")
	local hairFolder = lookFolder and lookFolder:FindFirstChild("Hair")
	local counts = { tier = 0, gear = 0, hidden = 0 }
	for _, p in ipairs(model:GetDescendants()) do
		local cls = p.ClassName
		if not (cls == "Part" or cls == "MeshPart" or cls == "WedgePart") or p.Name == "HumanoidRootPart" then
			continue
		end
		if hairFolder and p:IsDescendantOf(hairFolder) then
			continue -- the round-1 hair: hidden under the asset hair
		end
		if (p.Transparency or 0) >= 0.99 then
			counts.hidden += 1
			continue
		end
		local tier = p:GetAttribute("BodyTier")
		local gearId = p:GetAttribute("GearMesh")
		if cls == "MeshPart" and gearId then
			local file = GEAR_FILES[gearId]
			if not file then
				error("no mesh file for gear id " .. tostring(gearId) .. " (" .. p.Name .. ")")
			end
			local m = MeshV2.Read(file)
			local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
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
			table.insert(scene.meshes, { name = p.Name, gear = true, slot = p:GetAttribute("GearSlot"), p = P, n = N, t = m.T,
				color = color(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0 })
			counts.gearMeshes = (counts.gearMeshes or 0) + 1
			counts.gearTris = (counts.gearTris or 0) + #m.T // 3
		elseif cls == "MeshPart" and tier then
			local m = MeshV2.Read(string.format("%s/tools/body/out/tier%d/%s.mesh", root, tier, p.Name))
			local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
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
			table.insert(scene.meshes, { name = p.Name, tier = tier, p = P, n = N, t = m.T, color = color(p.Color),
				material = enumName(p.Material), reflectance = p.Reflectance or 0 })
			counts.tier += 1
		elseif p.Name == "Head" and p:FindFirstChildOfClass("SpecialMesh") then
			local decal = p:FindFirstChild("face")
			scene.head = { cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color),
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
			local folder = p.Parent and p.Parent.Name or "?"
			table.insert(scene.parts, { name = p.Name, folder = folder, shape = shape, cf = cfList(p.CFrame),
				size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = color(p.Color), material = enumName(p.Material),
				reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
			counts.gear += 1
		end
	end

	-- the asset hair, as the client builds it on this look
	local entry = HA.For(look, "full", true)
	local hairRec = { entry = entry and entry.key or nil, pieces = 0, tris = 0 }
	local fit = { cap = {}, cards = {} }
	if entry then
		local made, result, kind = HA.Build(model, entry, look, "full", { priority = 0, sig = L.id, mpOptions = true, resume = function() end })
		if not made then
			hairRec.error = tostring(kind) .. ": " .. tostring(result)
		else
			local S = Kit.Scalp(look)
			local imgFiles = {}
			local names = {}
			for name in pairs(made) do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local pr = made[name]
				local part = pr.part
				local m = sim.MeshOf(rawget(part, "_meshId") or part.MeshId and tonumber(tostring(part.MeshId):match("(%d+)$")))
				local size = { part.Size.X, part.Size.Y, part.Size.Z }
				local c = pr.centre.Position
				local Pl, k = AssetSim.Placed(m, size, { c.X, c.Y, c.Z })
				-- fit on the classic head, per region (nominal studs; < 0 = inside the head)
				local bucket = name == "HairCap" and fit.cap or fit.cards
				for i = 1, #Pl, 3 do
					local x, y, z = Pl[i] / S.kx, Pl[i + 1] / S.ky, Pl[i + 2] / S.kz
					local d = S.f(x, y, z)
					local reg = regionOf(x, y, z)
					bucket[reg] = bucket[reg] or {}
					table.insert(bucket[reg], d)
					bucket.all = bucket.all or {}
					table.insert(bucket.all, d)
				end
				local P, N = table.create(#Pl), table.create(#m.N)
				for i = 1, #Pl, 3 do
					local w = hcf * Vector3.new(Pl[i], Pl[i + 1], Pl[i + 2])
					P[i], P[i + 1], P[i + 2] = r4(w.X), r4(w.Y), r4(w.Z)
					local n = Vector3.new(m.N[i] / k[1], m.N[i + 1] / k[2], m.N[i + 2] / k[3])
					n = n.Magnitude > 1e-12 and hcf:VectorToWorldSpace(n.Unit) or Vector3.new(0, 1, 0)
					N[i], N[i + 1], N[i + 2] = r4(n.X), r4(n.Y), r4(n.Z)
				end
				local tc = part.TextureContent
				local img = type(tc) == "table" and (tc.object or tc.Object) or nil
				local tex
				if img then
					local file = imgFiles[img]
					if not file then
						file = string.format("%s_hair%d_%dx%d.rgba", L.id, #scene.hair + 1, img.Size.X, img.Size.Y)
						Host.WriteRGBA(OUT .. "/" .. file, img.buf)
						imgFiles[img] = file
					end
					tex = { file = file, w = img.Size.X, h = img.Size.Y }
				end
				local U = table.create(#m.U)
				for i, u in ipairs(m.U) do
					U[i] = r4(u)
				end
				table.insert(scene.hair, { name = name, p = P, n = N, uv = U, t = m.T, texture = tex, material = enumName(part.Material),
					doubleSided = part.DoubleSided, transparency = part.Transparency or 0, mesh = m.file:match("[^/]+/[^/]+$"),
					size = { r4(size[1]), r4(size[2]), r4(size[3]) }, centre = { r4(c.X), r4(c.Y), r4(c.Z) } })
				hairRec.pieces += 1
				hairRec.tris += m.nt
			end
			for _, pr in pairs(made) do
				if pr.release then
					pr.release()
				end
				if pr.part then
					pr.part:Destroy()
				end
			end
		end
	end
	local fitOut = {}
	for kind, regions in pairs(fit) do
		fitOut[kind] = {}
		for reg, list in pairs(regions) do
			fitOut[kind][reg] = quant(list)
		end
	end
	scene.fit = fitOut
	scene.headShape = look.headShape
	scene.lookHair = look.hair and { style = look.hair.style, type = look.hair.type } or nil
	hairRec.fit = fitOut
	Host.WriteJSON(OUT .. "/" .. L.id .. ".json", scene)
	table.insert(index.looks, { id = L.id, file = L.id .. ".json", label = L.label, tierKey = key, build = bv, frame = L.frame,
		headSize = r4(headSize), hair = hairRec, counts = counts, pose = L.pose or "rest", hipHeight = r4(model:FindFirstChildOfClass("Humanoid").HipHeight) })
	local function fmt(q)
		return q and string.format("min %+.3f p10 %+.3f med %+.3f p90 %+.3f (%d)", q.min, q.p10, q.med, q.p90, q.n) or "-"
	end
	table.insert(report, string.format("%-15s tiers %s build %d  head %.3f  headShape %s  hair %s (%d pieces, %d tris)%s  gear %d parts, %d hidden",
		L.id, tostring(key), bv, headSize, tostring(look.headShape), tostring(hairRec.entry), hairRec.pieces, hairRec.tris,
		hairRec.error and (" ERROR " .. hairRec.error) or "", counts.gear, counts.hidden)
		.. string.format("  gear meshes %d (%d tris)", counts.gearMeshes or 0, counts.gearTris or 0))
	for _, kind in ipairs({ "cap", "cards" }) do
		for _, reg in ipairs({ "all", "top", "corner", "front", "side", "back", "below" }) do
			local q = fitOut[kind] and fitOut[kind][reg]
			if q then
				table.insert(report, string.format("    %-5s %-6s %s", kind, reg, fmt(q)))
			end
		end
	end
	model:Destroy()
end
-- (--only: the other looks of an earlier run stay in the index, in LOOKS order)
if only and fs.isFile(OUT .. "/index.json") then
	local serde = require("@lune/serde")
	local prev = serde.decode("json", fs.readFile(OUT .. "/index.json"))
	local byId = {}
	for _, l in ipairs(prev.looks or {}) do
		byId[l.id] = l
	end
	for _, l in ipairs(index.looks) do
		byId[l.id] = l
	end
	index.looks = {}
	for _, L in ipairs(LOOKS) do
		if byId[L.id] then
			table.insert(index.looks, byId[L.id])
		end
	end
end
Host.WriteJSON(OUT .. "/index.json", index, true)
for _, l in ipairs(report) do
	print(l)
end
print("scene:", OUT)
