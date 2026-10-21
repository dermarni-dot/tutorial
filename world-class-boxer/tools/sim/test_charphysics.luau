--!nocheck
-- tools/sim/test_charphysics.luau: what the Humanoid's physics sees of a built boxer (the body wobble checks).
--   * every part Builder.Cosmetics welds on (gear, attire, headgear / caps, face, hair, belts, sweat...) is Massless,
--     never collides, queries or touches: the Humanoid balances the R15 body alone, nothing hangs off-centre
--   * the body's centre of mass (the 15 R15 parts + root, box volumes x the material's density) stays on the root's
--     axis: no lateral offset, a small forward one, at every tier / height / gender
--   * HipHeight is exactly the tier legs' length (root -> hip -> knee -> ankle -> sole: the soles stand on the floor
--     when the root floats HipHeight + root / 2 above it), at every tier / height / gender, and it is put back when
--     the engine rescaled the character (ApplyDescription) without a tier change
--   lune run tools/sim/test_charphysics.luau
local roblox = require("@lune/roblox")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

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

------------------------------------------------------------------------
-- the fake R15 rig (test_bodytiers.luau's), the engine's ReplaceBodyPartR15 (scales from OriginalSize)
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
local BODY = { HumanoidRootPart = true, Head = true }
for _, n in ipairs(BodyTiers.PARTS) do
	BODY[n] = true
end

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- the engine's joint solve from the root out (bind pose: Transform identity)
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
	root.Material = roblox.Enum.Material.Plastic
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
		p.Color = roblox.Color3.new(1, 1, 1)
		p.Material = roblox.Enum.Material.Plastic
		p.CanCollide = name == "UpperTorso" or name == "LowerTorso"
		p.CanQuery = true
		p.CanTouch = true
		p.Massless = false
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
	head.Material = roblox.Enum.Material.Plastic
	head.CanCollide = true
	head.Massless = false
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

-- Roblox's density by material (mass = volume x density; the box fidelity MeshParts' volume is their box)
local DENSITY = { Plastic = 0.7, SmoothPlastic = 0.7, Fabric = 0.7, Metal = 7.85, Wood = 0.35, Neon = 0.7, Glass = 2.4, Concrete = 2.4 }
local function massOf(p)
	local m = p.Material
	local name = m and (m.Name or tostring(m):match("([^%.]+)$")) or "Plastic"
	local s = p.Size
	return s.X * s.Y * s.Z * (DENSITY[name] or 0.7)
end

local function describe(p)
	local path = p.Name
	local q = p.Parent
	while q and q.ClassName ~= "Model" do
		path = q.Name .. "." .. path
		q = q.Parent
	end
	return path
end

-- the bind pose's leg bottom in root space (BuilderTiers.HipHeight's rule), from the solved parts
local function soleY(model, side)
	local ft = model:FindFirstChild(side .. "Foot")
	local root = model:FindFirstChild("HumanoidRootPart")
	return (root.CFrame:PointToObjectSpace(ft.CFrame.Position)).Y - ft.Size.Y / 2
end

local worstCom = 0
for _, g in ipairs({ 1, 2 }) do
	for _, tier in ipairs({ 1, 3, 5 }) do
		for _, height in ipairs({ 60, 70, 84 }) do
			local tag = string.format("g%d T%d h%d", g, tier, height)
			local app = Looks.Defaults(g)
			app.height = height
			local b = buildFor(app, tier)
			local sc = Builder.Scales(app, b)
			local model, hum = newRig(Vector3.new(sc.width, sc.height, sc.depth), 1.2 * sc.head)
			model.Parent = E.workspace
			local ok, err = pcall(Builder.Cosmetics, model, app, b, nil, { hands = "gloves", detail = "full", robe = true })
			check(tag .. ": Cosmetics runs", ok, err)
			solve(model)
			-- every tier part is in
			local key = model:GetAttribute("BodyTiers")
			check(tag .. ": all 14 parts at tier " .. tier, key == string.rep(tostring(tier), 14), key)
			-- cosmetics: massless, never collide / query / touch; welded (never loose)
			local bad = {}
			local nCos = 0
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and not BODY[p.Name] then
					nCos += 1
					local why = {}
					if p.Massless ~= true then
						table.insert(why, "mass")
					end
					if p.CanCollide ~= false then
						table.insert(why, "collide")
					end
					if p.CanQuery ~= false then
						table.insert(why, "query")
					end
					if p.CanTouch ~= false then
						table.insert(why, "touch")
					end
					if p.Anchored == true then
						table.insert(why, "anchored")
					end
					if #why > 0 then
						table.insert(bad, describe(p) .. "(" .. table.concat(why, ",") .. ")")
					end
				end
			end
			check(tag .. ": " .. nCos .. " cosmetic parts massless and non-colliding", #bad == 0, table.concat(bad, " "))
			-- body parts keep their mass (the Humanoid is tuned for an R15 body's mass); the limbs stay non-colliding
			local badBody = {}
			for name in pairs(BODY) do
				local p = model:FindFirstChild(name)
				if not p then
					table.insert(badBody, name .. "(missing)")
				elseif p.Massless == true then
					table.insert(badBody, name .. "(massless)")
				elseif p.CanCollide ~= false and name ~= "HumanoidRootPart" and name ~= "Head" and name ~= "UpperTorso" and name ~= "LowerTorso" then
					table.insert(badBody, name .. "(collides)")
				end
			end
			check(tag .. ": body parts keep their mass, limbs never collide", #badBody == 0, table.concat(badBody, " "))
			-- the centre of mass (box volumes) in root space: on the root's axis
			local root = model:FindFirstChild("HumanoidRootPart")
			local mTot, com = 0, Vector3.zero
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and p.Massless ~= true then
					local m = massOf(p)
					mTot += m
					com += root.CFrame:PointToObjectSpace(p.CFrame.Position) * m
				end
			end
			com = com / mTot
			worstCom = math.max(worstCom, math.abs(com.X), math.abs(com.Z))
			check(tag .. string.format(": centre of mass on the root's axis (x %.3f z %.3f, mass %.1f)", com.X, com.Z, mTot),
				math.abs(com.X) < 0.02 and math.abs(com.Z) < 0.15)
			-- HipHeight = the legs' length: the soles on the floor when the root floats HipHeight + root / 2 above it
			local want = -math.min(soleY(model, "Left"), soleY(model, "Right")) - root.Size.Y / 2
			check(tag .. string.format(": HipHeight %.3f = legs %.3f", hum.HipHeight, want), math.abs(hum.HipHeight - want) < 0.005)
			check(tag .. ": HipHeight is BuilderTiers.HipHeight", math.abs((BuilderTiers.HipHeight(model) or -1) - hum.HipHeight) < 1e-6)
			-- the engine's own HipHeight after a rescale (ApplyDescription puts the default body's back): a Cosmetics
			-- run with the same tiers corrects it again
			hum.HipHeight = 2 * sc.height
			local ok2, err2 = pcall(Builder.Cosmetics, model, app, b, nil, { hands = "gloves", detail = "full", robe = true })
			check(tag .. ": rebuild runs", ok2, err2)
			check(tag .. string.format(": HipHeight put back after the engine's rescale (%.3f)", hum.HipHeight), math.abs(hum.HipHeight - want) < 0.005)
			-- no Animate script, no loose part
			model:Destroy()
		end
	end
end
print(string.format("worst centre-of-mass offset %.3f studs", worstCom))

print(string.format("test_charphysics: %d passed, %d failed", pass, fail))
if fail > 0 then
	require("@lune/process").exit(1)
end
