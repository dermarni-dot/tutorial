--!nocheck
-- tools/sim/test_frameheight.luau: the frame changes the build, not the height (v13).
--   * every frame (Lean, Athletic, Muscular, Power Build, Heavyweight Build) built by Builder.Cosmetics on the fake R15
--     rig at the Builder.Scales of 5'6", 6'0" and 6'6" stands the SAME height (sole to the crown of the head), has
--     the same eye line and the same HipHeight as the Athletic frame at those inches, within 1 %; the standing height
--     is Builder.StandingHeight(inches) (the Athletic unit's x inches / 70)
--   * HipHeight is the tier legs' own (BuilderTiers.HipHeight) at every frame and height
--   * the frames still differ in build: the shoulder span climbs Lean < Athletic < Muscular < Power Build and
--     Athletic < Heavyweight Build < Power Build at the same tier and height
--   lune run tools/sim/test_frameheight.luau [--body MANIFEST.lua]   (a publish_body.py --local manifest: the rebuilt
--                                                                     meshes before they are uploaded)
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local args = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		args[a[i]:gsub("^%-%-", "")] = a[i + 1]
		i += 2
	end
end

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local E = FE.new()
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")
local Builder = H.require("Builder")
local Looks = H.require("Looks")
local REAL = args.body and luau.load(fs.readFile(args.body), { debugName = args.body })() or BodyTiers.Data()
BodyTiers.SetData(REAL)

------------------------------------------------------------------------
-- the fake R15 rig (test_charphysics.luau's), the engine's ReplaceBodyPartR15 (scales from OriginalSize)
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
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" },
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

-- the engine's joint solve from the root out (bind pose: Transform identity); the root floats HipHeight + root / 2
local function solve(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	hrp.CFrame = CFrame.new(0, hum.HipHeight + hrp.Size.Y / 2, 0)
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" or d.ClassName == "Weld" then
			table.insert(joints, d)
		end
	end
	local done = { [hrp] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(joints) do
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 and done[p0] and not done[p1] then
				p1.CFrame = p0.CFrame * j.C0 * j.C1:Inverse()
				done[p1] = true
				progress = true
			end
		end
	end
end

local function newRig(scale, headSize)
	local model = E.new("Model")
	model.Name = "Boxer"
	local root = E.new("Part", model)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	local ra = E.new("Attachment", root)
	ra.Name = "RootRigAttachment"
	ra.Position = Vector3.zero
	ra.CFrame = CFrame.new()
	local function setAtt(a, pos)
		a.Position = pos
		a.CFrame = CFrame.new(pos)
	end
	for name, b in pairs(BLOCK) do
		local p = E.new("MeshPart", model)
		p.Name = name
		p.Size = v3(b.size) * scale
		local o = E.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = v3(b.size)
		for an, pos in pairs(b.att) do
			local a = E.new("Attachment", p)
			a.Name = an
			setAtt(a, v3(pos) * scale)
			local op = E.new("Vector3Value", a)
			op.Name = "OriginalPosition"
			op.Value = v3(pos)
		end
	end
	local head = E.new("MeshPart", model)
	head.Name = "Head"
	head.Size = Vector3.new(headSize, headSize, headSize)
	local na = E.new("Attachment", head)
	na.Name = "NeckRigAttachment"
	setAtt(na, Vector3.new(0, -0.5 * headSize, 0))
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
	end
	local neck = E.new("Motor6D", head)
	neck.Name = "Neck"
	neck.Part0, neck.Part1 = model:FindFirstChild("UpperTorso"), head
	neck.C0, neck.C1 = CFrame.new(0, 0.8 * scale.Y, 0), na.CFrame
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local name = enum.Name
		local old = model:FindFirstChild(name)
		if name ~= "Head" then
			local o = part:FindFirstChild("OriginalSize")
			part.Size = o.Value * scale
			for _, a in ipairs(part:GetChildren()) do
				if a:IsA("Attachment") then
					local op = a:FindFirstChild("OriginalPosition")
					if op then
						a.Position = op.Value * scale
						a.CFrame = CFrame.new(a.Position)
					end
				end
			end
		end
		for _, m in ipairs(model:GetDescendants()) do
			if m:IsA("Motor6D") then
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

local function fakeAssets()
	local AS = {}
	function AS.CreateMeshPartAsync(_, content)
		local id = tonumber(tostring(content):match("(%d+)$"))
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. id
		return mp
	end
	return AS
end
local Content = { fromUri = function(u)
	return u
end }
BuilderTiers.Reset()
BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
local BuilderGear = H.require("BuilderGear")
BuilderGear.Reset()
BuilderGear.Services = BuilderTiers.Services

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
			return build(v + (tier > 1 and 2 or 0))
		end
	end
	error("no build gives tier " .. tier)
end

------------------------------------------------------------------------
-- the measure: a built boxer's standing height, eye line, hip height and shoulder span (world space, bind pose)
------------------------------------------------------------------------
local FRAMES = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }
local HEIGHTS = { { 66, "5'6\"" }, { 72, "6'0\"" }, { 78, "6'6\"" } }

local function measure(frameId, inches, tier, gender)
	local app = Looks.Defaults(gender or 1)
	app.height = inches
	app.body.frame = frameId
	local b = buildFor(app, tier)
	local sc = Builder.Scales(app, b)
	local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
	model.Parent = E.workspace
	local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = "bare", detail = "full" })
	if not ok then
		error(frameId .. " " .. inches .. ": Cosmetics failed: " .. tostring(err))
	end
	solve(model)
	local function p(n)
		return model:FindFirstChild(n)
	end
	local sole = math.huge
	for _, side in ipairs({ "Left", "Right" }) do
		local ft = p(side .. "Foot")
		sole = math.min(sole, ft.CFrame.Position.Y - ft.Size.Y / 2)
	end
	local head = p("Head")
	local ra, la = p("RightUpperArm"), p("LeftUpperArm")
	local m = {
		frame = frameId, inches = inches, tier = tier,
		stand = head.CFrame.Position.Y + head.Size.Y / 2 - sole,
		eye = head.CFrame.Position.Y + 0.1 * head.Size.Y - sole, -- BuilderHead.FaceLayout: eyeY = 0.1 x the head
		hip = hum.HipHeight,
		legs = BuilderTiers.HipHeight(model),
		soleUnderRoot = hum.HipHeight + p("HumanoidRootPart").Size.Y / 2 - (p("HumanoidRootPart").CFrame.Position.Y - sole),
		span = (ra.CFrame.Position.X + ra.Size.X / 2) - (la.CFrame.Position.X - la.Size.X / 2),
		headSize = head.Size.Y,
		heightScale = sc.height,
		tiers = model:GetAttribute("BodyTiers"),
		bodyFrame = model:GetAttribute("BodyFrame"),
	}
	model:Destroy()
	return m
end

local function pct(a, b)
	return 100 * (a / b - 1)
end

print(string.format("%-18s %-6s T  %-7s %-7s %-7s %-7s %-7s %-7s %s", "frame", "height", "stand", "want", "eye", "hip", "span", "head", "HeightScale"))
for _, tier in ipairs({ 1, 3, 5 }) do
	for _, hh in ipairs(HEIGHTS) do
		local inches, label = hh[1], hh[2]
		local want = Builder.StandingHeight(inches)
		local M = {}
		for _, fid in ipairs(FRAMES) do
			M[fid] = measure(fid, inches, tier)
		end
		local A = M.Athletic
		for _, fid in ipairs(FRAMES) do
			local m = M[fid]
			local tag = string.format("%s %s T%d", fid, label, tier)
			print(string.format("%-18s %-6s %d  %7.3f %7.3f %7.3f %7.3f %7.3f %7.3f %.4f", fid, label, tier, m.stand, want, m.eye, m.hip, m.span, m.headSize, m.heightScale))
			check(tag .. ": all 14 parts of the frame's family at tier " .. tier, m.tiers == string.rep(tostring(tier), 14) and m.bodyFrame == fid,
				tostring(m.tiers) .. " " .. tostring(m.bodyFrame))
			check(tag .. string.format(": stands the chosen height (%.3f vs %.3f)", m.stand, want), math.abs(pct(m.stand, want)) < 0.5)
			check(tag .. string.format(": standing height within 1 %% of the Athletic's (%+.2f %%)", pct(m.stand, A.stand)), math.abs(pct(m.stand, A.stand)) < 1)
			check(tag .. string.format(": eye line within 1 %% of the Athletic's (%+.2f %%)", pct(m.eye, A.eye)), math.abs(pct(m.eye, A.eye)) < 1)
			check(tag .. string.format(": HipHeight within 1 %% of the Athletic's (%+.2f %%)", pct(m.hip, A.hip)), math.abs(pct(m.hip, A.hip)) < 1)
			check(tag .. ": HipHeight is the tier legs' own", math.abs(m.hip - m.legs) < 1e-6 and math.abs(m.soleUnderRoot) < 0.005,
				string.format("%.4f vs %.4f (soles %+.4f)", m.hip, m.legs, m.soleUnderRoot))
		end
		check(string.format("%s T%d: the shoulder span climbs Lean < Athletic < Muscular < Power Build", label, tier),
			M.Lean.span < A.span and A.span < M.Muscular.span and M.Muscular.span < M["Power Build"].span,
			string.format("%.2f %.2f %.2f %.2f", M.Lean.span, A.span, M.Muscular.span, M["Power Build"].span))
		check(string.format("%s T%d: Athletic < Heavyweight Build < Power Build", label, tier),
			A.span < M["Heavyweight Build"].span and M["Heavyweight Build"].span < M["Power Build"].span,
			string.format("%.2f %.2f %.2f", A.span, M["Heavyweight Build"].span, M["Power Build"].span))
		check(string.format("%s T%d: the head climbs Lean < Athletic < Muscular < Power Build < Heavyweight Build", label, tier),
			M.Lean.headSize < A.headSize and A.headSize < M.Muscular.headSize and M.Muscular.headSize < M["Power Build"].headSize
				and M["Power Build"].headSize < M["Heavyweight Build"].headSize)
	end
end
-- the standing height follows the inches: 6'6" / 5'6" = 78 / 66 on every frame
for _, fid in ipairs(FRAMES) do
	local a, b = measure(fid, 66, 3), measure(fid, 78, 3)
	check(fid .. ": 6'6\" stands 78 / 66 x 5'6\"", math.abs(pct(b.stand / a.stand, 78 / 66)) < 0.5, string.format("%.3f / %.3f", b.stand, a.stand))
end
-- women: the same rule (a smaller head, the same chosen height)
do
	local a, l = measure("Athletic", 66, 3, 2), measure("Lean", 66, 3, 2)
	check("women 5'6\": Lean stands the Athletic's height", math.abs(pct(l.stand, a.stand)) < 1 and math.abs(pct(a.stand, Builder.StandingHeight(66))) < 0.5,
		string.format("%.3f %.3f", l.stand, a.stand))
end

print(string.format("test_frameheight: %d passed, %d failed", pass, fail))
if fail > 0 then
	process.exit(1)
end
