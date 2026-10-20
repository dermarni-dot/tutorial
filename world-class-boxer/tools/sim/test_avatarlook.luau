--!nocheck
-- tools/sim/test_avatarlook.luau: a player's own Roblox avatar hair & face on the boxer (AvatarLook, Builder).
--   * AvatarLook: id parsing / normalising, FromDescription (only HairAccessory / Face / Head, maxHair, the
--     Config switches), Key / State, Enabled (appearance.avatar), the background fetch through a fake
--     Players:GetHumanoidDescriptionFromUserId (no block, a failure retried, onReady once, Forget, ApplyFailed)
--   * Builder: Description copies the ids and leaves the body alone, ScaleKey (game look unchanged; re-apply only
--     when the avatar choice changes), Builder.Apply on a fake R15 rig whose Humanoid:ApplyDescription attaches
--     fake hair accessories / a dynamic head / the face: AvatarLook / AvatarHair / AvatarFace attributes, no
--     round-1 hair, LookData hair.avatar + HairSig, no classic head swap or FaceKey on an avatar face,
--     accessories re-welded after the classic head swap, a failed apply -> the game look, the setting off ->
--     the game look again, hair accessories hidden under headgear / a hood and restored
--   * NPC / game-look rigs unchanged, Looks.Sanitize / Fill keep the setting, FaceFX leaves an avatar face alone,
--     AnatomyHair / HairAssetKit draw nothing for avatar hair
--   lune run tools/sim/test_avatarlook.luau
local roblox = require("@lune/roblox")
local task = require("@lune/task")
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
local Config = H.require("Config")
-- the feature under test, whatever the shipping Config has switched off for now (BaldMode, avatar hair / face off)
Config.BaldMode = false
Config.AvatarLook.hair = true
Config.AvatarLook.face = true
local AvatarLook = H.require("AvatarLook")
local Builder = H.require("Builder")
local Looks = H.require("Looks")
local LookData = H.require("LookData")
local BodyTiers = H.require("BodyTiers")
local BuilderTiers = H.require("BuilderTiers")

------------------------------------------------------------------------
-- ids
------------------------------------------------------------------------
do
	local function same(a, b)
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end
	local P = AvatarLook.ParseIds
	check("ids: a number", same(P(4819740796), { 4819740796 }))
	check("ids: a numeric string", same(P(" 123 "), { 123 }))
	check("ids: rbxassetid://", same(P("rbxassetid://62234425"), { 62234425 }))
	check("ids: catalog URL", same(P("https://www.roblox.com/catalog/4819740796/Lavender-Updo"), { 4819740796 }))
	check("ids: asset URL", same(P("http://www.roblox.com/asset/?id=555"), { 555 }))
	check("ids: creator store URL", same(P("https://create.roblox.com/store/asset/777/Hair"), { 777 }))
	check("ids: comma list (HairAccessory)", same(P("11,22, 33"), { 11, 22, 33 }))
	check("ids: a list of mixed", same(P({ 5, "rbxassetid://6", "7,8" }), { 5, 6, 7, 8 }))
	check("ids: repeats dropped", same(P("9,9,10"), { 9, 10 }))
	check("ids: junk / 0 / negative / fractions skipped", same(P({ "", "abc", 0, -4, 1.5, "rbxassetid://", 0 / 0 }), {}))
	check("ids: nil", same(P(nil), {}))
end

------------------------------------------------------------------------
-- records, keys, the setting
------------------------------------------------------------------------
do
	local rec = AvatarLook.FromDescription({ HairAccessory = "100,200,rbxassetid://300", Face = 86487700, Head = 0, Shirt = 999, Torso = 27112025 })
	check("FromDescription: hair ids", rec.hair == "100,200,300" and rec.useHair == true, rec.hair)
	check("FromDescription: face, no dynamic head", rec.face == 86487700 and rec.head == 0)
	check("FromDescription: only hair / face / head", rec.Shirt == nil and rec.Torso == nil and rec.shirt == nil)
	local many = {}
	for i = 1, 12 do
		many[i] = tostring(i)
	end
	check("FromDescription: at most maxHair", #AvatarLook.ParseIds(AvatarLook.FromDescription({ HairAccessory = table.concat(many, ",") }).hair) == Config.AvatarLook.maxHair)
	local bald = AvatarLook.FromDescription({ HairAccessory = "", Face = 0, Head = 0 })
	check("an avatar without hair: useHair with no ids (bald)", bald.useHair and bald.hair == "")
	Config.AvatarLook.hair = false
	local nh = AvatarLook.FromDescription({ HairAccessory = "1,2", Face = 5 })
	check("Config hair = false: no hair", nh.useHair == false and nh.hair == "" and nh.face == 5)
	Config.AvatarLook.hair = true
	Config.AvatarLook.face = false
	local nf = AvatarLook.FromDescription({ HairAccessory = "1", Face = 5, Head = 6 })
	check("Config face = false: no face / head", nf.face == 0 and nf.head == 0 and nf.hair == "1")
	Config.AvatarLook.face = true
	-- keys
	check("Key(nil) = ''", AvatarLook.Key(nil) == "")
	local k = AvatarLook.Key(rec)
	local st = AvatarLook.State(k)
	check("State: hair + classic face", st.hair and st.face and not st.dynamic, k)
	st = AvatarLook.State(AvatarLook.Key({ useHair = true, hair = "", face = 0, head = 9 }))
	check("State: bald + dynamic head", st.hair and st.face and st.dynamic)
	st = AvatarLook.State(AvatarLook.Key({ useHair = true, hair = "1", face = 0, head = 0 }))
	check("State: hair, no face (keeps the classic face)", st.hair and not st.face)
	st = AvatarLook.State(AvatarLook.Key({ useHair = false, hair = "", face = 3, head = 0 }))
	check("State: face only", not st.hair and st.face)
	st = AvatarLook.State(nil)
	check("State(nil): the game look", not st.hair and not st.face and not st.dynamic)
	check("Key differs by hair / face / head", AvatarLook.Key({ useHair = true, hair = "1", face = 0, head = 0 }) ~= AvatarLook.Key({ useHair = true, hair = "2", face = 0, head = 0 })
		and AvatarLook.Key({ useHair = true, hair = "1", face = 1, head = 0 }) ~= AvatarLook.Key({ useHair = true, hair = "1", face = 0, head = 1 }))
	-- the setting
	check("Enabled: default look", AvatarLook.Enabled(Looks.Defaults(1)))
	local off = Looks.Defaults(1)
	off.avatar = false
	check("Enabled: appearance.avatar = false", not AvatarLook.Enabled(off))
	Config.AvatarLook.enabled = false
	check("Enabled: Config off", not AvatarLook.Enabled(Looks.Defaults(1)))
	Config.AvatarLook.enabled = true
	local old = Looks.Defaults(1)
	old.avatar = nil
	check("Fill: old save -> on", Looks.Fill(old).avatar == true)
	check("Sanitize: off kept", Looks.Sanitize({ avatar = false }, Looks.Defaults(1)).avatar == false)
	check("Sanitize: missing -> the saved choice", Looks.Sanitize({}, off).avatar == false and Looks.Sanitize({}, Looks.Defaults(1)).avatar == true)
	check("Sanitize: junk -> false", Looks.Sanitize({ avatar = "yes" }, Looks.Defaults(1)).avatar == false)
end

------------------------------------------------------------------------
-- fetching
------------------------------------------------------------------------
do
	AvatarLook.Reset()
	local calls, failNext = 0, 1
	local fakePlayers = {}
	function fakePlayers.GetHumanoidDescriptionFromUserId(_, userId)
		calls += 1
		task.wait(0.02) -- (the web call yields)
		if failNext > 0 then
			failNext -= 1
			error("HTTP 500 (Internal Server Error)")
		end
		return { HairAccessory = "4001,4002", Face = 0, Head = 0, UserId = userId }
	end
	AvatarLook.Services.Players = fakePlayers
	Config.AvatarLook.retry, Config.AvatarLook.maxRetry = 0.05, 0.4
	local ready = 0
	local function onReady(rec)
		ready += 1
		check("onReady gets the record", rec.hair == "4001,4002")
	end
	local t0 = os.clock()
	local r = AvatarLook.Request(42, onReady)
	check("Request: nil at once (never blocks)", r == nil and os.clock() - t0 < 0.01)
	check("Request: a Studio / NPC id never fetches", AvatarLook.Request(-1, onReady) == nil and AvatarLook.Request(0) == nil)
	AvatarLook.Request(42, onReady) -- (pending: no second call, no second waiter)
	task.wait(0.03)
	check("the first fetch failed: still nil", AvatarLook.Get(42) == nil and calls == 1, calls)
	task.wait(0.2)
	check("retried after the back-off and cached", AvatarLook.Get(42) ~= nil and calls == 2, calls)
	check("onReady once", ready == 1, ready)
	check("Request after: the cached record, no call", AvatarLook.Request(42, onReady) ~= nil and calls == 2)
	AvatarLook.ApplyFailed(42)
	check("ApplyFailed: the game look for a while", AvatarLook.Get(42) == nil and AvatarLook.Request(42) == nil)
	task.wait(0.45)
	check("ApplyFailed: the avatar again after maxRetry", AvatarLook.Get(42) ~= nil)
	-- a player who leaves while the fetch is out: nothing cached, no callback
	failNext = 0
	local late = 0
	AvatarLook.Request(77, function()
		late += 1
	end)
	AvatarLook.Forget(77)
	task.wait(0.05)
	check("Forget: the late answer is dropped", AvatarLook.Get(77) == nil and late == 0)
	Config.AvatarLook.retry, Config.AvatarLook.maxRetry = 20, 600
	AvatarLook.Reset()
end

------------------------------------------------------------------------
-- Description / ScaleKey
------------------------------------------------------------------------
local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end

local AV = { useHair = true, hair = "4001,4002", face = 0, head = 0 }
local AVF = { useHair = true, hair = "4001", face = 0, head = 15093053680 } -- a dynamic head
do
	local app = Looks.Defaults(1)
	local plain = Builder.Description(app, build(40), {})
	local d = Builder.Description(app, build(40), { avatar = AVF })
	check("Description: HairAccessory", d.HairAccessory == "4001", d.HairAccessory)
	check("Description: Head (dynamic) and Face", d.Head == 15093053680 and d.Face == 0)
	check("Description: no avatar -> no hair / face / head set", plain.HairAccessory == nil and plain.Face == nil and plain.Head == nil)
	local same = true
	for _, k in ipairs({ "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale", "TorsoColor", "HeadColor" }) do
		same = same and d[k] == plain[k]
	end
	check("Description: the body (scales, colours) untouched", same)
	check("Description: no body parts / clothes copied", d.Torso == nil and d.LeftArm == nil and d.Shirt == nil and d.Pants == nil and d.HatAccessory == nil)
	local k0 = Builder.ScaleKey(app, build(40), {})
	check("ScaleKey: game look = the old key", k0:sub(-3) == "|p3" and not k0:find("A", 1, true), k0)
	local k1 = Builder.ScaleKey(app, build(40), { avatar = AV })
	check("ScaleKey: the avatar changes it", k1 ~= k0 and k1:sub(-2) == "p3", k1)
	check("ScaleKey: the same avatar, the same key (no re-apply per Cosmetics)", Builder.ScaleKey(app, build(90), { avatar = table.clone(AV) }) == k1)
	check("ScaleKey: new hair -> new key", Builder.ScaleKey(app, build(40), { avatar = AVF }) ~= k1)
end

------------------------------------------------------------------------
-- a fake R15 rig with an engine-like ApplyDescription
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

local fakeAssets = { calls = 0 }
function fakeAssets.CreateMeshPartAsync(_, content)
	fakeAssets.calls += 1
	local mp = E.new("MeshPart")
	mp.MeshId = "rbxassetid://" .. tostring(content):match("(%d+)$")
	return mp
end

-- engine: an R15 rig (default MeshPart head with HairAttachment / face decal), ReplaceBodyPartR15, and an
-- ApplyDescription that attaches one Hair accessory per HairAccessory id (to the current head), sets the face
-- decal from Face, swaps in a dynamic head for Head ~= 0 and errors on an id in failIds
local function newRig(failIds)
	local model = E.new("Model", E.workspace) -- (Builder.Apply builds only a character in the world)
	model.Name = "Boxer"
	local root = E.new("Part", model)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	local ra = E.new("Attachment", root)
	ra.Name = "RootRigAttachment"
	ra.CFrame = CFrame.new()
	for name, b in pairs(BLOCK) do
		local p = E.new("MeshPart", model)
		p.Name = name
		p.Size = v3(b.size)
		p.Color = roblox.Color3.new(1, 1, 1)
		local o = E.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = v3(b.size)
		for an, pos in pairs(b.att) do
			local a = E.new("Attachment", p)
			a.Name = an
			a.Position = v3(pos)
			a.CFrame = CFrame.new(v3(pos))
		end
	end
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = E.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
	end
	local function newHead(dynamic)
		local head = E.new("MeshPart")
		head.Name = "Head"
		head.Size = Vector3.new(0.927, 0.927, 0.927)
		head.CFrame = CFrame.new(0, 4.5, 0)
		local na = E.new("Attachment", head)
		na.Name = "NeckRigAttachment"
		na.Position = Vector3.new(0, -0.6, 0)
		na.CFrame = CFrame.new(0, -0.6, 0)
		local ha = E.new("Attachment", head)
		ha.Name = "HairAttachment"
		ha.Position = Vector3.new(0, 0.6, 0)
		ha.CFrame = CFrame.new(0, 0.6, 0)
		if dynamic then
			head:SetAttribute("DynamicHead", dynamic)
			E.new("FaceControls", head)
		else
			local decal = E.new("Decal", head)
			decal.Name = "face"
			decal.Texture = "rbxasset://textures/face.png"
		end
		return head
	end
	local function seatHead(head)
		local neck = model:FindFirstChild("Neck", true)
		if not neck then
			neck = E.new("Motor6D")
			neck.Name = "Neck"
			neck.C0, neck.C1 = CFrame.new(0, 0.8, 0), CFrame.new(0, -0.6, 0)
		end
		neck.Part0, neck.Part1 = model:FindFirstChild("UpperTorso"), head
		neck.Parent = head
		head.Parent = model
	end
	local h0 = newHead(nil)
	seatHead(h0)
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2
	local stats = { applies = 0, last = nil }
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local old = model:FindFirstChild(enum.Name)
		if enum.Name == "Head" then
			local neck = old:FindFirstChild("Neck")
			neck.Part1 = part
			neck.Parent = part
		else
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
		end
		part.Parent = model
		old:Destroy()
		return true
	end
	hum.ApplyDescription = function(_, desc)
		stats.applies += 1
		stats.last = desc
		for _, n in ipairs(AvatarLook.ParseIds(desc.HairAccessory or "")) do
			if failIds and failIds[n] then
				error("Failed to load asset " .. n)
			end
		end
		-- accessories: the description's (the old ones go)
		for _, c in ipairs(model:GetChildren()) do
			if c:IsA("Accessory") then
				c:Destroy()
			end
		end
		-- the head: a dynamic head for Head ~= 0, else the default head back when it was dynamic
		local head = model:FindFirstChild("Head")
		local want = (desc.Head or 0) ~= 0 and desc.Head or nil
		if head:GetAttribute("DynamicHead") ~= want then
			local nh = newHead(want)
			nh.Size = head.Size
			local neck = head:FindFirstChild("Neck")
			neck.Part1 = nh
			neck.Parent = nh
			nh.Parent = model
			head:Destroy()
			head = nh
		end
		local decal = head:FindFirstChild("face")
		if decal then
			decal.Texture = (desc.Face or 0) ~= 0 and ("avatarface://" .. desc.Face) or "rbxasset://textures/face.png"
		end
		for _, n in ipairs(AvatarLook.ParseIds(desc.HairAccessory or "")) do
			local acc = E.new("Accessory")
			acc.Name = "Hair" .. n
			acc.AccessoryType = roblox.Enum.AccessoryType.Hair
			local handle = E.new("Part", acc)
			handle.Name = "Handle"
			handle.Transparency = n == 4002 and 0.2 or 0
			local a = E.new("Attachment", handle)
			a.Name = "HairAttachment"
			a.CFrame = CFrame.new(0, -0.3, 0)
			local w = E.new("Weld", handle)
			w.Name = "AccessoryWeld"
			w.Part0, w.Part1 = handle, head
			w.C0, w.C1 = a.CFrame, head:FindFirstChild("HairAttachment").CFrame
			acc.Parent = model
		end
	end
	return model, hum, stats
end

local function setup()
	BodyTiers.SetData(BodyTiers.Data())
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets, Content = { fromUri = function(u)
		return u
	end } }
end

-- the game's face (BuilderHead): the drawn Boxer face every boxer wears (one front Decal "face" with its FaceStyle,
-- a drawn texture), no built eye / brow / nose / lip part or rig, no FaceKey of the retired classic faces
local BUILT_PARTS = { Sclera = true, Iris = true, Pupil = true, EyeBall = true, Lid = true, Lashes = true, LowerLid = true, BlinkLid = true,
	Brow = true, BrowInner = true, BrowOuter = true, Nose = true, NoseTip = true, Nostril = true, UpperLip = true, LowerLip = true,
	MouthLine = true, MouthCorner = true, MouthInside = true, TeethUpper = true, Mouthguard = true }
local function gameFace(model)
	local BodyTiers = H.require("BodyTiers")
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Face")
	for _, d in ipairs(f and f:GetDescendants() or {}) do
		if (d:IsA("BasePart") and BUILT_PARTS[d.Name]) or (d.ClassName == "Motor6D" and d.Name == "FaceJoint") then
			return false
		end
	end
	local head = model:FindFirstChild("Head")
	local n = 0
	for _, d in ipairs(head and head:GetChildren() or {}) do
		if d:IsA("Decal") then
			n += 1
		end
	end
	local dec = head and head:FindFirstChild("face")
	local st = dec and dec:GetAttribute("FaceStyle")
	return n == 1 and BodyTiers.IsDrawnStyle(st) and dec.Texture == BodyTiers.FaceTexture(st) and model:GetAttribute("FaceKey") == nil
		and f ~= nil and f:GetAttribute("FaceStyle") == st
end

local function hairParts(model)
	local look = model:FindFirstChild("BoxerLook")
	local hair = look and look:FindFirstChild("Hair")
	local n = 0
	if hair then
		for _, d in ipairs(hair:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
	end
	return n, hair
end
local function accessories(model)
	local out = {}
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Accessory") then
			table.insert(out, c)
		end
	end
	return out
end
local function weldedToHead(model)
	local head = model:FindFirstChild("Head")
	for _, acc in ipairs(accessories(model)) do
		local w = acc.Handle:FindFirstChild("AccessoryWeld")
		if not (w and w.Part1 == head and w.Part0 == acc.Handle) then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- the game look (an NPC, or a player with the setting off): exactly as before
------------------------------------------------------------------------
local gameSigs
do
	setup()
	local model, _, stats = newRig()
	local app = Looks.Defaults(1)
	local ok, err = pcall(Builder.Apply, model, app, build(40), nil, { hands = "wraps" })
	check("game look: Apply runs", ok, err)
	check("game look: one ApplyDescription without avatar fields", stats.applies == 1 and stats.last.HairAccessory == nil and stats.last.Face == nil)
	check("game look: no avatar attributes", model:GetAttribute("AvatarLook") == nil and model:GetAttribute("AvatarHair") == nil and model:GetAttribute("AvatarFace") == nil)
	check("game look: round-1 hair built", hairParts(model) > 0, hairParts(model))
	local head = model:FindFirstChild("Head")
	check("game look: classic head + the drawn Boxer face", head.ClassName == "Part" and gameFace(model))
	local look = LookData.Get(model)
	check("game look: LookData hair has no avatar flag", look and look.hair and look.hair.avatar == nil)
	gameSigs = model:GetAttribute("HairSig")
	-- an NPC built the same way (no opts.avatar) never fetches nor carries the flags
	Builder.Cosmetics(model, app, build(40), nil, { hands = "wraps" })
	check("game look: a second Cosmetics re-applies nothing", stats.applies == 1)
end

------------------------------------------------------------------------
-- avatar hair, the game face
------------------------------------------------------------------------
do
	setup()
	local model, _, stats = newRig()
	local app = Looks.Defaults(1)
	local opts = { hands = "wraps", avatar = AV, avatarUser = 42 }
	local ok, err = pcall(Builder.Apply, model, app, build(40), nil, opts)
	check("avatar hair: Apply runs", ok, err)
	check("avatar hair: the description carries the ids", stats.last.HairAccessory == "4001,4002", stats.last.HairAccessory)
	check("avatar hair: attributes", model:GetAttribute("AvatarLook") == AvatarLook.Key(AV) and model:GetAttribute("AvatarHair") == true
		and model:GetAttribute("AvatarFace") == nil)
	local n, folder = hairParts(model)
	check("avatar hair: no round-1 hair parts (empty sealed folder)", n == 0 and folder ~= nil and folder:GetAttribute("Avatar") == true and folder:GetAttribute("Sig") ~= nil)
	check("avatar hair: two accessories", #accessories(model) == 2)
	check("avatar hair: game face kept (classic head swapped in)", model:FindFirstChild("Head").ClassName == "Part" and gameFace(model))
	check("avatar hair: accessories re-welded to the classic head", weldedToHead(model))
	local look = LookData.Get(model)
	check("avatar hair: LookData hair.avatar", look and look.hair.avatar == true)
	check("avatar hair: HairSig moved", model:GetAttribute("HairSig") ~= nil and model:GetAttribute("HairSig") ~= gameSigs)
	check("avatar hair: body tiers unaffected", model:GetAttribute("BodyTiers") == BodyTiers.Key(BodyTiers.Tiers(build(40), { potential = 0.95 })), model:GetAttribute("BodyTiers"))
	-- cosmetics runs (training, a fight's Cosmetics without opts.avatar) do not re-apply and keep the avatar hair
	Builder.Apply(model, app, build(45), nil, opts)
	Builder.Cosmetics(model, app, build(45), nil, { hands = "gloves" })
	check("avatar hair: no re-apply, still avatar hair", stats.applies == 1 and model:GetAttribute("AvatarHair") == true and hairParts(model) == 0)
	-- every boxer's own headgear (Config.AlwaysHeadgear): the avatar hair stays under it, through a spar too
	local function allHidden()
		local hid = #accessories(model) > 0
		for _, acc in ipairs(accessories(model)) do
			hid = hid and acc.Handle.Transparency == 1 and acc.Handle:GetAttribute("HGHidden") == true
		end
		return hid
	end
	check("always headgear: avatar hair under it", Config.AlwaysHeadgear ~= true or allHidden())
	Builder.SetHeadgear(model, roblox.Color3.new(0, 0, 1), true)
	Builder.SetHeadgear(model, roblox.Color3.new(0, 0, 1), false)
	check("always headgear: still under it after a spar", Config.AlwaysHeadgear ~= true or allHidden())
	-- the old rule (Config.AlwaysHeadgear off: headgear only while sparring); a rebuild takes the boxer's own off
	local always = Config.AlwaysHeadgear
	Config.AlwaysHeadgear = false
	Builder.Cosmetics(model, app, build(45), nil, { hands = "gloves" })
	-- headgear: the accessories hide whole and come back with their own transparency
	Builder.SetHeadgear(model, roblox.Color3.new(0, 0, 1), true)
	local hidden = true
	for _, acc in ipairs(accessories(model)) do
		hidden = hidden and acc.Handle.Transparency == 1 and acc.Handle:GetAttribute("HGHidden") == true
	end
	check("headgear: hair accessories hidden", hidden)
	Builder.SetHeadgear(model, roblox.Color3.new(0, 0, 1), false)
	local h4001, h4002 = model:FindFirstChild("Hair4001").Handle, model:FindFirstChild("Hair4002").Handle
	check("headgear off: restored (0 and 0.2)", h4001.Transparency == 0 and math.abs(h4002.Transparency - 0.2) < 1e-6 and h4001:GetAttribute("HGHidden") == nil)
	Builder.SetHairHidden(model, "hood", true)
	check("hood: hidden", h4001.Transparency == 1)
	Builder.SetHairHidden(model, "hood", false)
	check("hood off: restored", h4001.Transparency == 0)
	-- a non-hair accessory is never touched
	local hat = E.new("Accessory")
	hat.AccessoryType = roblox.Enum.AccessoryType.Hat
	local hh = E.new("Part", hat)
	hh.Name = "Handle"
	hat.Parent = model
	Builder.SetHairHidden(model, "headgear", true)
	check("headgear: a hat accessory is left alone", hh.Transparency == 0 and h4001.Transparency == 1)
	Builder.SetHairHidden(model, "headgear", false)
	hat:Destroy()
	Config.AlwaysHeadgear = always
	-- the setting turned off: re-applied once without the avatar, the game hair back
	Builder.Apply(model, app, build(45), nil, { hands = "wraps" })
	check("setting off: re-applied once", stats.applies == 2 and (stats.last.HairAccessory or "") == "")
	check("setting off: attributes cleared, hair parts back", model:GetAttribute("AvatarLook") == nil and model:GetAttribute("AvatarHair") == nil and hairParts(model) > 0)
	check("setting off: no accessories", #accessories(model) == 0)
	check("setting off: HairSig back to the game look's", model:GetAttribute("HairSig") == gameSigs)
end

------------------------------------------------------------------------
-- avatar hair + a Dynamic Head (the avatar face)
------------------------------------------------------------------------
do
	setup()
	local model, _, stats = newRig()
	local app = Looks.Defaults(1)
	app.face.key = "cool"
	-- first build on the game look (the avatar still being fetched), then the avatar arrives
	Builder.Apply(model, app, build(40), nil, { hands = "wraps" })
	check("dynamic: first the classic head", model:FindFirstChild("Head").ClassName == "Part")
	Builder.Apply(model, app, build(40), nil, { hands = "wraps", avatar = AVF, avatarUser = 42 })
	local head = model:FindFirstChild("Head")
	check("dynamic: re-applied with the avatar", stats.applies == 2 and stats.last.Head == AVF.head)
	check("dynamic: the engine's dynamic head kept (no classic swap)", head.ClassName == "MeshPart" and head:GetAttribute("DynamicHead") == AVF.head
		and head:FindFirstChildOfClass("FaceControls") ~= nil)
	check("dynamic: no face decal of ours, no FaceKey", head:FindFirstChild("face") == nil and model:GetAttribute("FaceKey") == nil)
	check("dynamic: AvatarFace + AvatarHair", model:GetAttribute("AvatarFace") == true and model:GetAttribute("AvatarHair") == true)
	check("dynamic: accessory on the dynamic head", #accessories(model) == 1 and weldedToHead(model))
	check("dynamic: body tiers kept", model:GetAttribute("BodyTiers") ~= nil and model:FindFirstChild("UpperTorso"):GetAttribute("BodyTier") ~= nil)
	-- FaceFX leaves an avatar face alone
	local FaceFX = H.require("FaceFX")
	head.CFrame = CFrame.new(0, 5, -3)
	local decal = E.new("Decal", head)
	decal.Name = "face"
	decal.Texture = "avatarface://1"
	FaceFX.Hit(model, 1)
	FaceFX.Update(1 / 60, 0, Vector3.new(0, 5, 0), { [model] = { isFighter = true } })
	check("FaceFX: an avatar face is never swapped", decal.Texture == "avatarface://1", decal.Texture)
	decal:Destroy()
	-- off again: the default head comes back from the engine, then the classic head and the chosen face
	Builder.Apply(model, app, build(40), nil, { hands = "wraps" })
	head = model:FindFirstChild("Head")
	check("dynamic off: classic head + the drawn Boxer face back", head.ClassName == "Part" and gameFace(model) and model:GetAttribute("AvatarFace") == nil)
end

------------------------------------------------------------------------
-- a classic avatar face (Face id, no dynamic head): the engine's decal face stays
------------------------------------------------------------------------
do
	setup()
	local model = newRig()
	local app = Looks.Defaults(1)
	Builder.Apply(model, app, build(40), nil, { hands = "wraps", avatar = { useHair = true, hair = "", face = 86487700, head = 0 }, avatarUser = 42 })
	local head = model:FindFirstChild("Head")
	check("classic avatar face: the engine's face decal kept", head.face and head.face.Texture == "avatarface://86487700", head.face and head.face.Texture)
	check("classic avatar face: no FaceKey, AvatarFace", model:GetAttribute("FaceKey") == nil and model:GetAttribute("AvatarFace") == true)
	check("an avatar without hair: bald (no hair parts, no accessories)", hairParts(model) == 0 and #accessories(model) == 0 and model:GetAttribute("AvatarHair") == true)
end

------------------------------------------------------------------------
-- the avatar's items fail to load: the game look, ApplyFailed
------------------------------------------------------------------------
do
	setup()
	AvatarLook.Reset()
	local model, _, stats = newRig({ [4002] = true })
	local app = Looks.Defaults(1)
	local fakePlayers = {}
	function fakePlayers.GetHumanoidDescriptionFromUserId()
		return { HairAccessory = "4001,4002", Face = 0, Head = 0 }
	end
	AvatarLook.Services.Players = fakePlayers
	AvatarLook.Request(42)
	task.wait()
	local rec = AvatarLook.Get(42)
	check("failure: record cached", rec ~= nil)
	local ok = pcall(Builder.Apply, model, app, build(40), nil, { hands = "wraps", avatar = rec, avatarUser = 42 })
	check("failure: Apply survives", ok)
	check("failure: applied again without the avatar", stats.applies == 2 and (stats.last.HairAccessory or "") == "")
	check("failure: the game look", model:GetAttribute("AvatarLook") == nil and model:GetAttribute("AvatarHair") == nil and hairParts(model) > 0
		and gameFace(model))
	check("failure: the avatar is held back (ApplyFailed)", AvatarLook.Get(42) == nil)
	check("failure: the next Apply (no avatar) re-applies nothing", (function()
		Builder.Apply(model, app, build(40), nil, { hands = "wraps", avatar = AvatarLook.Get(42), avatarUser = 42 })
		return stats.applies == 2
	end)())
	AvatarLook.Reset()
end

------------------------------------------------------------------------
-- the clients draw no hair for avatar hair
------------------------------------------------------------------------
do
	local Gen = H.require("AnatomyHair")
	local HK = H.require("HairAssetKit")
	local Data = H.require("HairAssetData")
	-- (H.Look goes through LookData.FromBuilder without a model: the flag as a model with AvatarHair publishes it)
	local lk = H.Look({ g = 1, headShape = "classic", hair = { style = "Afro", type = "Kinky", growth = 0.6 } })
	lk.hair.avatar = true
	local res = Gen.Generate(lk, "low", H.Ctx("Hair", "low"))
	local n = 0
	for _ in pairs(res.pieces or {}) do
		n += 1
	end
	check("AnatomyHair: avatar hair -> no pieces (no stubble either)", n == 0, n)
	check("HairAssetKit: no asset entry for avatar hair", HK.Select(Data, lk) == nil)
	local lk2 = H.Look({ g = 1, headShape = "classic", hair = { style = "Afro", type = "Kinky" } })
	check("the same look without the flag still has an entry or pieces", HK.Select(Data, lk2) ~= nil or next(Gen.Generate(lk2, "low", H.Ctx("Hair", "low")).pieces) ~= nil)
	check("HairSig differs with the flag", LookData.SectionSig(lk, "Hair") ~= LookData.SectionSig(lk2, "Hair"))
end

print(string.format("test_avatarlook: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_avatarlook failed")
end
