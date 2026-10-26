--!nocheck
-- tools/sim/test_strayparts.luau: every built NPC variant scanned for pieces that are not where they belong.
--   * the NPCs the game builds with Builder.CreateNPC: every gym / town member of Ambient.MEMBERS (at low and medium
--     detail) and the gym template's athletes (Venues.ATHLETES: their own seeds, genders, physiques, hands, details,
--     headgear), referees and cornermen / cutmen (Officials.Look), fight-night opponents (gloves, mouthguard, full
--     detail), the same in sparring headgear and in each walkout robe; every face shape at every detail (the lower
--     jaw's Long / heavy pieces); a sweep over every frame (Lean .. Heavyweight Build) x muscle tier x detail level x
--     height x gender x hands. All of it twice: the mesh gear, and the part-built gear (every gear mesh failing, as
--     Studio's "Asset type does not match" loads do)
--   * the rig is posed as the engine poses it (each body part at Part0.CFrame * C0 * C1:Inverse() down the Motor6D
--     chain from the root, after every swap and again after the build; the pieces follow their welds), and a mesh piece
--     is measured by its uploaded mesh's own vertices (tools/body/uploaded.json maps the id to the file)
--   * asserted for every piece (a BasePart under BoxerLook, an accessory handle, a prop):
--       - welded (Weld / WeldConstraint / Motor6D) to a part of the model, the chain ending on a body part
--       - on its host: its centre within its own half extent (+ slack) of the host's box (nothing off the silhouette,
--         at the origin or far away), and not several times the host's size
--       - no MeshFallback stand-in sphere on the server build
--       - a head-worn piece (face, headgear, cap) never reaches under the head's base (the neck)
--       - nothing but skin on the NECK: no non-skin point in the column round the neck axis between the shoulders and
--         the head's lower surface (collars ring it, under the base), none of the body's gear up beside the jaw
--     and the neck seam: the head's base sits inside the tier torso's neck stub (no gap under the classic head)
--   lune run tools/sim/test_strayparts.luau [--dump] [--gear MANIFEST.lua] [--src DIR] [--scene DIR --only a,b]
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Host = require("./host")
local FE = require("./fakeengine")
local MeshV2 = require("./meshv2")

local Vector3, Color3, CFrame = roblox.Vector3, roblox.Color3, roblox.CFrame
local DUMP = table.find(process.args, "--dump") ~= nil
-- --scene DIR --only a,b: the scanned models whose label contains one of the words also written as a v8 scene
-- (tools/sim/v8_render.py DIR OUT --no-lineup --no-hairfit renders them)
-- --gear PATH: a gear manifest instead of src/shared/GearAssetData.lua (publish_gear.py --local PATH writes one, its
-- PATH.ids.json naming each fake id's mesh file): the meshes as rebuilt, before they are uploaded
-- --src DIR: the game's sources from DIR (another commit's: git archive <rev> src | tar -x -C DIR/..)
local SCENE, ONLY, GEAR_PATH, SRC
for i, a in ipairs(process.args) do
	if a == "--src" then
		SRC = process.args[i + 1]
	elseif a == "--gear" then
		GEAR_PATH = process.args[i + 1]
	elseif a == "--scene" then
		SCENE = process.args[i + 1]
	elseif a == "--only" then
		ONLY = {}
		for w in process.args[i + 1]:gmatch("[^,]+") do
			table.insert(ONLY, w)
		end
	end
end

local pass, fail = 0, 0
local fails = {}
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		local line = "FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "")
		if #fails < 80 then
			print(line)
		end
		table.insert(fails, line)
	end
end

local E = FE.new()
local H = Host.new({ server = true, src = SRC, globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace, warn = function() end } })
E.install(H)
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local BuilderGear = H.require("BuilderGear")
local Builder = H.require("Builder")
local Looks = H.require("Looks")
local Officials = H.require("Officials")

------------------------------------------------------------------------
-- the fake rig (test_npcbuild's), posed down the Motor6D chain like the engine's
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
local BODY = { HumanoidRootPart = true, Head = true }
for n in pairs(BLOCK) do
	BODY[n] = true
end
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

local function jointOf(p)
	for _, c in ipairs(p:GetChildren()) do
		if c.ClassName == "Weld" or c.ClassName == "WeldConstraint" or c.ClassName == "Motor6D" then
			return c
		end
	end
	return nil
end

-- the engine's bind pose: the root where it is, every Motor6D's Part1 at Part0.CFrame * C0 * C1:Inverse(); the pieces
-- welded to a part that moved move with it (a WeldConstraint keeps its offset, a Weld / Motor6D its C0 / C1)
local function pose(model)
	local before = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			before[d] = d.CFrame
		end
	end
	local done = { [model:FindFirstChild("HumanoidRootPart") or false] = true }
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" and d.Part0 and d.Part1 and BODY[d.Part1.Name] and d.Part1.Parent == model then
			table.insert(motors, d)
		end
	end
	local moved = true
	while moved do
		moved = false
		for _, m in ipairs(motors) do
			if done[m.Part0] and not done[m.Part1] then
				m.Part1.CFrame = m.Part0.CFrame * m.C0 * m.C1:Inverse()
				done[m.Part1] = true
				moved = true
			end
		end
	end
	-- the pieces: follow their joints (to a fixed point: a piece welded to a piece)
	local pieces = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not (BODY[d.Name] and d.Parent == model) then
			table.insert(pieces, d)
		end
	end
	for _ = 1, 5 do
		for _, p in ipairs(pieces) do
			if not done[p] then
				local j = jointOf(p)
				local other = j and ((j.Part0 == p and j.Part1) or j.Part0)
				if other and done[other] then
					if j.ClassName == "WeldConstraint" then
						local rel = (before[other] or other.CFrame):Inverse() * (before[p] or p.CFrame)
						p.CFrame = other.CFrame * rel
					elseif j.Part1 == p then
						p.CFrame = other.CFrame * j.C0 * j.C1:Inverse()
					else
						p.CFrame = other.CFrame * j.C1 * j.C0:Inverse()
					end
					done[p] = true
				end
			end
		end
	end
end

local function newRig(scale)
	local model = E.new("Model")
	model.Name = "Boxer"
	local hrp = E.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.CFrame = CFrame.new(0, 3 * scale.Y, 0)
	local ra = E.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	local function addPart(name, size, orig, atts)
		local p = E.new("MeshPart", model)
		p.Name = name
		p.Size = size
		p.Color = Color3.new(1, 1, 1)
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
	end
	for name, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = { cur = v3(pos) * scale, orig = v3(pos) }
		end
		addPart(name, v3(b.size) * scale, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(0.927, 0.927, 0.927), Vector3.new(1.2, 1.2, 1.2),
		{ NeckRigAttachment = { cur = Vector3.new(0, -0.46, 0), orig = Vector3.new(0, -0.6, 0) } })
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
	hum.ApplyDescription = function() end
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
		pose(model)
		return true
	end
	pose(model)
	return model, hum
end
H.Service("Players")._props.CreateHumanoidModelFromDescription = function(_, desc)
	return (newRig(Vector3.new(desc.WidthScale or 1, desc.HeightScale or 1, desc.DepthScale or 1)))
end
local stage = E.new("Folder", E.workspace)
stage.Name = "BoxerStaging"
Builder.Services.Stage = stage

-- every mesh loads (mode "mesh"), or every gear mesh fails (the part-built gear: "parts")
local gearFails = false
local gearIds = {}
local AS = {}
function AS.CreateMeshPartAsync(_, content)
	local id = tonumber(tostring(content):match("(%d+)%s*$"))
	if gearFails and gearIds[id] then
		error("ContentId: rbxassetid://" .. id .. " failed due to: Asset type does not match requested type", 0)
	end
	local mp = E.new("MeshPart")
	mp.MeshId = "rbxassetid://" .. tostring(id)
	return mp
end
local Content = { fromUri = function(u)
	return u
end }
local Kit = H.require("BuilderKit")
Kit.Services.schedule = function()
	return true
end
local function reset(failGear)
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	BuilderGear.Reset()
	BuilderGear.Services = { AssetService = AS, Content = Content }
	gearFails = failGear == true
end
if GEAR_PATH then
	BuilderGear.SetData(luau.load(fs.readFile(GEAR_PATH))())
end
for _, q in ipairs(BuilderGear.PreloadList()) do
	gearIds[q.id] = true
end
Builder.RETRY_SETTLE = 0

------------------------------------------------------------------------
-- mesh geometry: the uploaded meshes' own vertices (tools/body/uploaded.json maps an id to its file), placed as the
-- engine draws a MeshPart (the mesh recentred on its box, stretched to Size, at the CFrame)
------------------------------------------------------------------------
local MESH_FILES = {}
do
	local up = Host.FindRoot() .. "/tools/body/uploaded.json"
	if fs.isFile(up) then
		for _, e in pairs(serde.decode("json", fs.readFile(up))) do
			if type(e.id) == "number" and type(e.file) == "string" and e.file:find("%.mesh$") then
				MESH_FILES[e.id] = Host.FindRoot() .. "/tools/body/" .. e.file
			end
		end
	end
	local side = GEAR_PATH and (GEAR_PATH:gsub("%.lua$", "") .. ".ids.json")
	if side and fs.isFile(side) then
		for id, f in pairs(serde.decode("json", fs.readFile(side)).ids or {}) do
			MESH_FILES[tonumber(id)] = f
		end
	end
end
local meshCache = {}
local function meshOf(id)
	local c = meshCache[id]
	if c == nil then
		c = false
		local f = MESH_FILES[id]
		if f and fs.isFile(f) then
			local ok, m = pcall(MeshV2.Read, f)
			if ok then
				c = m
			end
		end
		meshCache[id] = c
	end
	return c or nil
end
-- world vertices of a MeshPart with a known mesh (nil when its file is not here)
local function vertsOf(p)
	local id = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
	local m = id and meshOf(tonumber(id))
	if not m then
		return nil
	end
	local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
	local s = p.Size
	local kx, ky, kz = s.X / math.max(bx, 1e-6), s.Y / math.max(by, 1e-6), s.Z / math.max(bz, 1e-6)
	local cf = p.CFrame
	local out = table.create(#m.P // 3)
	for i = 1, #m.P, 3 do
		out[#out + 1] = cf * Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz)
	end
	return out
end

-- the model as tools/sim/v8_render.py reads a look (world space)
local sceneLooks = {}
local function r4(x)
	return math.floor(x * 10000 + 0.5) / 10000
end
local function cfList(cf)
	local t = { cf:GetComponents() }
	for i, v in ipairs(t) do
		t[i] = r4(v)
	end
	return t
end
local function col(c)
	return c and { r4(c.R), r4(c.G), r4(c.B) } or { 0.8, 0.8, 0.8 }
end
local function enumName(v)
	local ok, n = pcall(function()
		return v.Name
	end)
	return ok and n or tostring(v):match("([^%.]+)$")
end
local function exportScene(model, label)
	if not SCENE then
		return
	end
	local want = ONLY == nil
	for _, w in ipairs(ONLY or {}) do
		if label:find(w, 1, true) then
			want = true
		end
	end
	if not want then
		return
	end
	local id = label:gsub("[^%w]+", "_")
	local d = { id = id, label = label, tierKey = tostring(model:GetAttribute("BodyTiers")), frame = tostring(model:GetAttribute("Frame")),
		hair = {}, meshes = {}, parts = {} }
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and (p.Transparency or 0) < 0.99 then
			local id2 = p:GetAttribute("GearMesh") or p:GetAttribute("BodyMesh")
			local m = id2 and meshOf(tonumber(id2))
			if p.ClassName == "MeshPart" and m then
				local cx, cy, cz, bx, by, bz = MeshV2.Bounds(m)
				local sz = p.Size
				local kx, ky, kz = sz.X / bx, sz.Y / by, sz.Z / bz
				local P, N = table.create(#m.P), table.create(#m.N)
				for i = 1, #m.P, 3 do
					local w = p.CFrame * Vector3.new((m.P[i] - cx) * kx, (m.P[i + 1] - cy) * ky, (m.P[i + 2] - cz) * kz)
					P[i], P[i + 1], P[i + 2] = r4(w.X), r4(w.Y), r4(w.Z)
					local n = p.CFrame:VectorToWorldSpace(Vector3.new(m.N[i] / kx, m.N[i + 1] / ky, m.N[i + 2] / kz)).Unit
					N[i], N[i + 1], N[i + 2] = r4(n.X), r4(n.Y), r4(n.Z)
				end
				table.insert(d.meshes, { name = p.Name, gear = p:GetAttribute("GearMesh") ~= nil or nil, tier = p:GetAttribute("BodyTier"), p = P, n = N, t = m.T,
					color = col(p.Color), material = enumName(p.Material), reflectance = p.Reflectance or 0 })
			elseif p.Name == "Head" and p.Parent == model and p:FindFirstChildOfClass("SpecialMesh") then
				d.head = { cf = cfList(p.CFrame), size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = col(p.Color), material = enumName(p.Material),
					classic = H.require("AnatomyHairKit").CLASSIC }
			else
				local shape = p.ClassName == "WedgePart" and "Wedge" or "Block"
				local sm = p:FindFirstChildOfClass("SpecialMesh")
				if sm then
					local mt = enumName(sm.MeshType)
					shape = mt == "Sphere" and "Ellipsoid" or mt
				elseif p.Shape then
					shape = enumName(p.Shape)
				end
				table.insert(d.parts, { name = p.Name, folder = p.Parent and p.Parent.Name or "?", shape = shape, cf = cfList(p.CFrame),
					size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) }, color = col(p.Color), material = enumName(p.Material),
					reflectance = p.Reflectance or 0, transparency = p.Transparency or 0 })
			end
		end
	end
	if d.head then
		fs.writeDir(SCENE)
		fs.writeFile(SCENE .. "/" .. id .. ".json", serde.encode("json", d))
		table.insert(sceneLooks, { id = id, file = id .. ".json", label = label, tierKey = d.tierKey, frame = d.frame, hair = {} })
	end
end

------------------------------------------------------------------------
-- the scan
------------------------------------------------------------------------
local function boxDistance(rel, half)
	local dx = math.max(math.abs(rel.X) - half.X, 0)
	local dy = math.max(math.abs(rel.Y) - half.Y, 0)
	local dz = math.max(math.abs(rel.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
-- the body part at the end of a piece's weld chain (a piece welded to a built piece: that piece's anchor), or nil + why
local function anchorOf(model, p)
	local cur, hops = p, 0
	while cur and hops < 6 do
		local j = jointOf(cur)
		local other = j and ((j.Part0 == cur and j.Part1) or j.Part0)
		if not other then
			return nil, cur == p and "not welded" or ("chain ends at " .. cur.Name)
		end
		if not other:IsDescendantOf(model) then
			return nil, "welded to a part outside the model"
		end
		if BODY[other.Name] and other.Parent == model then
			return other
		end
		cur, hops = other, hops + 1
	end
	return nil, "weld chain does not reach a body part"
end
local function pieceName(model, p)
	local path = {}
	local c = p
	while c and c ~= model do
		table.insert(path, 1, c.Name)
		c = c.Parent
	end
	return table.concat(path, "/")
end
local function near(c1, c2)
	return math.abs(c1.R - c2.R) + math.abs(c1.G - c2.G) + math.abs(c1.B - c2.B) < 0.03
end

-- points on a piece's drawn surface (world): an ellipsoid / ball's by direction, a block's corners, edges and faces
local DIRS = {}
for _, x in ipairs({ -1, 0, 1 }) do
	for _, y in ipairs({ -1, 0, 1 }) do
		for _, z in ipairs({ -1, 0, 1 }) do
			if x ~= 0 or y ~= 0 or z ~= 0 then
				table.insert(DIRS, Vector3.new(x, y, z))
			end
		end
	end
end
local function surfacePoints(p)
	local out = {}
	local half = p.Size * 0.5
	local sm = p:FindFirstChildOfClass("SpecialMesh")
	local round = (sm and tostring(sm.MeshType):find("Sphere")) or tostring(p.Shape):find("Ball")
	for _, d in ipairs(DIRS) do
		local l = round and (d.Unit * half) or (d * half)
		if sm and typeof(sm.Scale) == "Vector3" then
			l = l * sm.Scale
		end
		table.insert(out, p.CFrame * l)
	end
	return out
end
-- what a piece draws: a mesh piece's own vertices (when its file is here), else its shape's surface points
local function drawnPoints(p)
	return (p.ClassName == "MeshPart" and vertsOf(p)) or surfacePoints(p)
end

-- slack: how far a piece may reach past its host's box (studs, on top of its own half extent); the walkout robe hangs
-- loose round the body (its belt knot sits on the robe, in front of the LowerTorso)
local SLACK = 0.25
local SLACK_FOLDER = { Robe = 0.5 }
-- the neck (in head spans, the classic head's smallest axis; the head's base sits on the Neck pivot): the column round
-- the neck axis out to NECK_R, from NECK_DROP under the base up to the base
local NECK_R, NECK_DROP = 0.38, 0.25
-- beside the neck (out to BESIDE_R) the body's gear may lie on the trapezius up to BESIDE_RISE over the head's base
-- (the lite set's trapezius crest reaches the base), never up beside the jaw; a collar up to COLLAR_RISE (it stands
-- up against the nape under the head's rounded edge)
local BESIDE_R, BESIDE_RISE, COLLAR_RISE = 0.62, 0.03, 0.07
-- (the coach's towel folds over the trapezius beside the neck, its roll a little higher)
local RISE = { OffTowel = 0.12, Towel = 0.12 }
-- the classic head's lower surface over its base at radius r (head spans): flat to 0.3, the rounded edge to 0.5
local function headSurface(r)
	if r <= 0.3 then
		return 0
	elseif r < 0.5 then
		return 0.2 - math.sqrt(math.max(0.04 - (r - 0.3) ^ 2, 0))
	end
	return math.huge
end
-- what rings the base of the neck by design (the officials' shirt and polo collars, the bow tie, the coach's towel,
-- the walkout robe's neckline): kept under the head's base and out from beside it, not out of the column
local COLLARS = { OffCollar = true, OffShirt = true, OffPolo = true, OffTowel = true, OffPlacket = true, OffBowTie = true, OffPoloButtons = true,
	OffButtons = true, Collar = true, BowTie = true, BowKnot = true, Placket = true, Towel = true }
local COLLAR_FOLDERS = { Robe = true }
local stats = { models = 0, pieces = 0, meshPieces = 0 }

local function scan(model, label)
	stats.models += 1
	pose(model)
	exportScene(model, label)
	local head, ut = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso")
	if not (head and ut) then
		check(label .. ": has a Head and an UpperTorso", false)
		return
	end
	local skin = head.Color
	local span = math.min(head.Size.X, head.Size.Y, head.Size.Z)
	local hcf = head.CFrame
	local base = (hcf * Vector3.new(0, -head.Size.Y / 2, 0)).Y
	-- the neck seam: the head's base sits inside the tier torso's neck stub (its top above the base round the axis):
	-- no gap the classic head floats over, no seam piece needed
	local tv = vertsOf(ut)
	if tv then
		local stubTop = -math.huge
		for _, v in ipairs(tv) do
			local r = Vector3.new(v.X - hcf.X, 0, v.Z - hcf.Z).Magnitude
			if r < 0.3 * span then
				stubTop = math.max(stubTop, v.Y)
			end
		end
		check(label .. ": the head's base sits inside the torso's neck (no gap under the classic head)", stubTop - base >= 0.03,
			string.format("the neck stub's top %.3f studs over the head's base", stubTop - base))
	end
	if DUMP then
		print(string.format("== %s  head %.3f  tiers %s frame %s", label, span, tostring(model:GetAttribute("BodyTiers")), tostring(model:GetAttribute("Frame"))))
	end
	for _, p in ipairs(model:GetDescendants()) do
		if not p:IsA("BasePart") or (BODY[p.Name] and p.Parent == model) then
			continue
		end
		stats.pieces += 1
		local name = pieceName(model, p)
		local visible = (p.Transparency or 0) < 0.99
		check(label .. ": " .. name .. ": no stand-in sphere on a server build", p.Name ~= "MeshFallback")
		local host, why = anchorOf(model, p)
		check(label .. ": " .. name .. " is welded to a body part", host ~= nil, why)
		if not host then
			continue
		end
		-- on its host: the piece's centre within its own half extent (+ slack) of the host's box (nothing floating
		-- off the silhouette, at the origin or far away), and not several times the host's size
		local rel = host.CFrame:PointToObjectSpace(p.Position)
		local slack = SLACK_FOLDER[p.Parent and p.Parent.Name or ""] or SLACK
		local reach = 0.5 * math.max(p.Size.X, p.Size.Y, p.Size.Z) + slack
		local off = boxDistance(rel, host.Size * 0.5)
		check(label .. ": " .. name .. " is on its host " .. host.Name, off <= reach, string.format("%.2f studs off %s's box (allowed %.2f)", off, host.Name, reach))
		local hostBig = math.max(host.Size.X, host.Size.Y, host.Size.Z, host == head and span or 0)
		check(label .. ": " .. name .. " is sized for its host " .. host.Name, math.max(p.Size.X, p.Size.Y, p.Size.Z) <= 3 * hostBig + 0.5,
			string.format("%s vs %s", tostring(p.Size), tostring(host.Size)))
		if not visible then
			continue
		end
		local pts = drawnPoints(p)
		if p.ClassName == "MeshPart" and pts ~= nil and p:GetAttribute("GearMesh") then
			stats.meshPieces += 1
		end
		if host == head then
			-- a head-worn piece (face, headgear, cap) never reaches under the head's base: below it is the neck
			local lo = math.huge
			for _, w in ipairs(pts) do
				lo = math.min(lo, hcf:PointToObjectSpace(w).Y / span)
			end
			check(label .. ": " .. name .. " stays on the head (nothing under its base, on the neck)", lo >= -0.505,
				string.format("reaches %.3f head spans (the base is -0.5)", lo))
		elseif not near(p.Color, skin) then
			-- the neck: nothing but skin in the column round the neck axis between the shoulders and the head's lower
			-- surface (a strap running up the neck stub, a collar up round the jaw); and nothing of the body's gear
			-- rising beside the head past its base (up to the jaw). A collar rings the column, under the head's base
			local collar = COLLARS[p.Name] or COLLAR_FOLDERS[p.Parent and p.Parent.Name or ""]
			local inNeck, beside, worst = 0, 0, nil
			for _, w in ipairs(pts) do
				local l = hcf:PointToObjectSpace(w) / span
				local r = math.sqrt(l.X * l.X + l.Z * l.Z)
				local y = l.Y + 0.5 -- over the base
				if r < NECK_R and y > -NECK_DROP and y < headSurface(r) and (not collar or y > COLLAR_RISE) then
					inNeck += 1
					worst = worst or l
				elseif r >= NECK_R and r < BESIDE_R and y > (RISE[p.Name] or (collar and COLLAR_RISE) or BESIDE_RISE) and y < headSurface(r) then
					beside += 1
					worst = worst or l
				end
			end
			check(label .. ": nothing but skin on the neck: " .. name, inNeck == 0 and beside == 0,
				worst and string.format("%d points in the neck column, %d up beside the jaw (e.g. %.2f, %.2f, %.2f head spans)", inNeck, beside, worst.X, worst.Y, worst.Z))
		end
		if DUMP then
			print(string.format("  %-44s host=%-14s off=%.2f size=%.2f,%.2f,%.2f", name, host.Name, off, p.Size.X, p.Size.Y, p.Size.Z))
		end
	end
end

------------------------------------------------------------------------
-- the game's NPC tables (read from the server files: their seeds, physiques, hands, details)
------------------------------------------------------------------------
local root = Host.FindRoot()
local function tableFrom(file, name)
	local src = fs.readFile(root .. "/" .. file)
	local s = src:find("local " .. name .. " = {", 1, true)
	local e = src:find("\n}\n", s, true)
	local chunk = "return " .. src:sub(s + #("local " .. name .. " = "), e + 1)
	local fn = luau.load(chunk, { environment = { V3 = Vector3.new, Vector3 = Vector3, Color3 = Color3 } })
	return fn()
end
local MEMBERS = tableFrom("src/server/Ambient.lua", "MEMBERS")
local ATHLETES = tableFrom("src/server/Venues.lua", "ATHLETES")

local function member(def, detail)
	local app = Looks.Random(def.seed, def.gender or 1, { age = def.age or 26, class = 5 })
	if def.age and def.age > 50 then
		app.hair.color = { 160, 160, 160 }
		app.beard.growth = 0.8
	end
	local fit = def.fit or (def.loop == "sitwatch" and 0.15 or 0.55)
	if def.physique and app.body then
		app.body.physique = def.physique
	end
	local build = Looks.RandomBuild(def.seed, fit, def.age or 26, app.body.frame, def.physique)
	local gear = { gloves = "Competition", glovesCond = 70, wraps = "OldWraps", wrapsCond = 80, shoes = def.coach and "Sneakers" or nil, shoesCond = 70 }
	local npc = Builder.CreateNPC(app, build, gear, def.name, {
		hands = def.hands or "wraps", name = def.name, nick = "", waistText = "",
		detail = detail or def.detail or "low", physique = def.physique, age = def.age or 26, sweat = def.sweat,
	})
	if npc then
		npc.Parent = E.workspace
		if def.headgear then
			Builder.SetHeadgear(npc, def.headgear, true)
		end
		if def.sweat and def.sweat > 0 then
			pcall(Builder.SetSweat, npc, app, def.sweat)
		end
	end
	return npc, app, build
end

local function run(gearMode)
	reset(gearMode == "parts")
	local tag = gearMode == "parts" and " [part-built gear]" or ""
	-- the gym and town members at the details the game builds them (Ambient: low under BaldMode; the template's own)
	for _, def in ipairs(MEMBERS) do
		for _, detail in ipairs({ "low", "medium" }) do
			local m = member(def, detail)
			check(def.name .. " builds", m ~= nil)
			if m then
				scan(m, def.name .. " (" .. detail .. ")" .. tag)
				m:Destroy()
			end
		end
	end
	for _, def in ipairs(ATHLETES) do
		local m = member(def)
		if m then
			scan(m, "athlete " .. def.name .. tag)
			m:Destroy()
		end
	end
	-- the officials
	for i, kind in ipairs({ "referee", "cornerman" }) do
		for _, seed in ipairs({ 11, 31, 77, 2024 }) do
			local a, b, g, o = Officials.Look(seed + i, kind, { venue = "ClubArena", team = { 230, 200, 30 } })
			local m = Builder.CreateNPC(a, b, g, kind, o)
			if m then
				m.Parent = E.workspace
				scan(m, kind .. " " .. seed .. tag)
				m:Destroy()
			end
		end
	end
	-- fight-night opponents and sparring partners
	for _, seed in ipairs({ 5150, 6262, 7373, 8484 }) do
		for _, g in ipairs({ 1, 2 }) do
			local app = Looks.Random(seed, g, { age = 28, class = 5 })
			local build = Looks.RandomBuild(seed, 0.8, 28, app.body.frame)
			local m = Builder.CreateNPC(app, build, { gloves = "Competition", wraps = "OldWraps" }, "Opp" .. seed,
				{ hands = "gloves", mouthguard = true, detail = "full", fightNight = true, name = "Opp", nick = "The Opp", nat = "USA", waistText = "OPP" })
			if m then
				m.Parent = E.workspace
				scan(m, "opponent " .. seed .. "/" .. g .. tag)
				Builder.SetHeadgear(m, Color3.fromRGB(170, 25, 30), true)
				scan(m, "sparring " .. seed .. "/" .. g .. tag)
				Builder.SetHeadgear(m, nil, false)
				for _, robe in ipairs({ "Classic", "Hooded", "Champion" }) do
					pcall(Builder.SetRobe, m, app, true, { detail = "full", name = "Opp", nick = "The Opp", robe = robe })
					scan(m, "walkout robe " .. robe .. " " .. seed .. "/" .. g .. tag)
				end
				m:Destroy()
			end
		end
	end
end

-- the faces whose lower jaw is drawn below the eyes' line: a Long face (LowerFace), a heavy one (Jowl, DoubleChin)
local function faces(gearMode)
	reset(gearMode == "parts")
	for _, shape in ipairs({ "Long", "Round", "Square", "Diamond", "Heart", "Oval" }) do
		for _, detail in ipairs({ "low", "medium", "full" }) do
			for _, g in ipairs({ 1, 2 }) do
				local app = Looks.Random(7100 + g, g, { age = 50, class = 5 })
				app.face = app.face or {}
				app.face.shape = shape
				local build = Looks.RandomBuild(7100 + g, 0.3, 50, app.body.frame)
				build.fat = 30
				local m = Builder.CreateNPC(app, build, { gloves = "Competition" }, "Face", { hands = "gloves", detail = detail, age = 50, name = "Face" })
				if m then
					m.Parent = E.workspace
					scan(m, string.format("face %s g%d %s%s", shape, g, detail, gearMode == "parts" and " [part-built gear]" or ""))
					m:Destroy()
				end
			end
		end
	end
end

local function sweep(gearMode)
	reset(gearMode == "parts")
	local tag = gearMode == "parts" and " [part-built gear]" or ""
	local frames = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
	local n = 0
	for fi, frame in ipairs(frames) do
		for _, fit in ipairs({ 0.05, 0.4, 0.75, 1 }) do
			for _, g in ipairs({ 1, 2 }) do
				n += 1
				local seed = 9000 + fi * 101 + math.floor(fit * 100) + g
				local app = Looks.Random(seed, g, { age = 27, class = 5 })
				app.body.frame = frame
				-- the height range (inches): short to tall for the gender
				local hs = g == 1 and { 64, 70, 78 } or { 59, 65, 72 }
				app.height = hs[(n % 3) + 1]
				local build = Looks.RandomBuild(seed, fit, 27, frame)
				local detail = ({ "low", "medium", "full" })[(n % 3) + 1]
				local hands = ({ "gloves", "wraps", "bare" })[((n // 3) % 3) + 1]
				local m = Builder.CreateNPC(app, build, { gloves = "Competition", wraps = "OldWraps" }, "Sweep" .. n,
					{ hands = hands, detail = detail, name = "Sweep", mouthguard = hands == "gloves" })
				if m then
					m.Parent = E.workspace
					local label = string.format("%s fit %.2f g%d %din %s %s%s", frame, fit, g, app.height, detail, hands, tag)
					scan(m, label)
					m:Destroy()
				else
					check("sweep " .. n .. " builds", false)
				end
			end
		end
	end
end

for _, mode in ipairs({ "mesh", "parts" }) do
	run(mode)
	faces(mode)
	sweep(mode)
end

if SCENE then
	fs.writeFile(SCENE .. "/index.json", serde.encode("json", { looks = sceneLooks }))
	print("scene: " .. SCENE .. " (" .. #sceneLooks .. " looks)")
end
print(string.format("test_strayparts: %d models, %d pieces scanned (%d gear meshes by their vertices)", stats.models, stats.pieces, stats.meshPieces))
print(string.format("test_strayparts: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
