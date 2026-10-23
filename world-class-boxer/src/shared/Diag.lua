-- Diag: the in-game rig diagnostic ("/wcbdiag" in chat, Settings -> GAME -> COPY DIAGNOSTIC TO OUTPUT). Pure: given a
-- character model (and what the caller knows about it: the Animator's rig table on a client, a motion sample) it
-- returns the lines the caller prints, one block per model, every line prefixed [WCBDIAG]. Nothing here runs unless
-- invoked. It reports what the engine really built so a Studio report carries numbers, not impressions:
--  * every body part: class, Size, OriginalSize, mesh id, BodyTier / BodyLite / BodyRatio; the Head's class, its
--    SpecialMesh or MeshId and the face decal
--  * the Humanoid: HipHeight (against the legs' own, BuilderTiers.HipHeight), RigType, AutomaticScalingEnabled, the
--    applied description's scales, the scale values, the Animate script, the playing tracks
--  * every Motor6D: Part0 / Part1, C0 / C1 next to the RigAttachments they should equal, the live Transform, and -
--    for a tier part - the attachment position BodyAssetData expects (OriginalPosition x the part's scale)
--  * the bind-pose joint heights above the sole, next to BodyAssetData.unit's (x the height scale)
--  * BoxerLook: the headgear / cap parts (size, offset from the head), the attire pieces (part, size, offset)
--  * the Animator's view (client): AnimRig geo, LOD, state, and a motion sample (DiagClient takes it)
--  * a VERDICT line per check, OK or a plain description of what is off
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))
local BuilderTiers = require(Shared:WaitForChild("BuilderTiers"))

local Diag = {}
Diag.PREFIX = "[WCBDIAG] "
Diag.VERSION = 1

local PARTS = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
	"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local MOTORS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local MOTOR_PARENT = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head", LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand", RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand", LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot", RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot" }
local SCALE_VALUES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale", "BodyProportionScale", "BodyTypeScale" }

local function f2(x)
	return string.format("%.2f", x)
end
local function v3(v)
	if typeof(v) ~= "Vector3" then
		return tostring(v)
	end
	return string.format("(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
end
local function v3f(v)
	return string.format("(%.3f,%.3f,%.3f)", v.X, v.Y, v.Z)
end
local function ang(cf)
	local x, y, z = cf:ToEulerAnglesXYZ()
	return string.format("%d/%d/%d", math.floor(math.deg(x) + 0.5), math.floor(math.deg(y) + 0.5), math.floor(math.deg(z) + 0.5))
end
local function cfs(cf)
	if typeof(cf) ~= "CFrame" then
		return tostring(cf)
	end
	return v3f(cf.Position) .. "r" .. ang(cf)
end
local function get(obj, k)
	local ok, v = pcall(function()
		return obj[k]
	end)
	if ok then
		return v
	end
	return nil
end
local function attr(obj, k)
	local ok, v = pcall(obj.GetAttribute, obj, k)
	return ok and v or nil
end
local function fullName(inst)
	local ok, n = pcall(inst.GetFullName, inst)
	return ok and n or tostring(inst)
end

------------------------------------------------------------------------
-- the pieces
------------------------------------------------------------------------
local function partLine(model, name)
	local p = model:FindFirstChild(name)
	if not (p and p:IsA("BasePart")) then
		return string.format("part %-16s MISSING", name)
	end
	local o = p:FindFirstChild("OriginalSize")
	local orig = (o and o:IsA("Vector3Value")) and o.Value or nil
	local mesh = ""
	if p:IsA("MeshPart") then
		mesh = " mesh=" .. tostring(get(p, "MeshId") or ""):gsub("rbxassetid://", "")
	else
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		if sm then
			mesh = string.format(" SpecialMesh=%s scale=%s meshId=%s", tostring(sm.MeshType and sm.MeshType.Name or sm.MeshType), v3(sm.Scale),
				tostring(sm.MeshId or ""):gsub("rbxassetid://", ""))
		end
	end
	local tier = attr(p, "BodyTier")
	local extra = ""
	if tier ~= nil then
		local okE, e = pcall(BodyTiers.PartEntry, tonumber(tier), name, nil, attr(p, "BodyLite") == true)
		local want = okE and e and tostring(e.id) or "?"
		local have = p:IsA("MeshPart") and tostring(get(p, "MeshId") or ""):gsub("rbxassetid://", "") or "-"
		extra = string.format(" tier=%s%s ratio=%s expectMesh=%s%s", tostring(tier), attr(p, "BodyLite") and " lite" or "", v3(attr(p, "BodyRatio")), want,
			(have == want or want == "?") and "" or " MISMATCH")
	end
	extra ..= " color=" .. (typeof(p.Color) == "Color3" and string.format("%d,%d,%d", p.Color.R * 255, p.Color.G * 255, p.Color.B * 255) or "?")
	if name == "Head" then
		local decals = {}
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("Decal") then
				table.insert(decals, d.Name .. ":" .. tostring(d.Texture or ""):gsub("rbxassetid://", ""))
			end
		end
		extra ..= " decals=[" .. table.concat(decals, " ") .. "]"
	end
	return string.format("part %-16s %-8s size=%s orig=%s%s%s anch=%s coll=%s massless=%s", name, p.ClassName, v3(p.Size), orig and v3(orig) or "-",
		mesh, extra, tostring(get(p, "Anchored")), tostring(get(p, "CanCollide")), tostring(get(p, "Massless")))
end

-- what BodyAssetData expects for an attachment on a tier part: OriginalPosition x the part's ratio (nil when unknown)
local function expectedAtt(part, attName)
	local tier = tonumber(attr(part, "BodyTier"))
	if not tier then
		return nil
	end
	local ok, e = pcall(BodyTiers.PartEntry, tier, part.Name, nil, attr(part, "BodyLite") == true)
	local pos = ok and e and e.attachments and e.attachments[attName]
	if not pos then
		return nil
	end
	local ratio = BuilderTiers.RatioOf(part) or attr(part, "BodyRatio")
	if typeof(ratio) ~= "Vector3" then
		return nil
	end
	return Vector3.new(pos[1] * ratio.X, pos[2] * ratio.Y, pos[3] * ratio.Z)
end

local function motorLine(model, name, verdicts)
	local holder = model:FindFirstChild(MOTOR_PARENT[name])
	local m = holder and holder:FindFirstChild(name)
	if not (m and m:IsA("Motor6D")) then
		-- (an AnimationConstraint rig, or a joint that is simply gone)
		local ac
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
				ac = d
				break
			end
		end
		if ac then
			return string.format("motor %-13s %s under %s (not where the R15 rig keeps it)", name, ac.ClassName, fullName(ac.Parent))
		end
		table.insert(verdicts, "BAD  Motor6D " .. name .. " is missing: the Animator cannot drive this joint")
		return string.format("motor %-13s MISSING", name)
	end
	local p0, p1 = m.Part0, m.Part1
	local an = name .. "RigAttachment"
	local a0 = p0 and p0:FindFirstChild(an)
	local a1 = p1 and p1:FindFirstChild(an)
	local s = string.format("motor %-13s %s->%s C0=%s C1=%s T=%s", name, p0 and p0.Name or "nil", p1 and p1.Name or "nil", cfs(m.C0), cfs(m.C1),
		cfs(m.Transform))
	if a0 and a0:IsA("Attachment") then
		local d = (m.C0.Position - a0.CFrame.Position).Magnitude
		s ..= string.format(" att0=%s d=%.3f", v3f(a0.CFrame.Position), d)
		if d > 0.02 then
			table.insert(verdicts, string.format("BAD  %s.C0 is %.3f studs off %s.%s: the joint is not aimed at its RigAttachment", name, d, p0.Name, an))
		end
		local e0 = p0 and expectedAtt(p0, an)
		if e0 then
			local de = (a0.CFrame.Position - e0).Magnitude
			s ..= string.format(" exp0=%s d=%.3f", v3f(e0), de)
			if de > 0.02 then
				table.insert(verdicts, string.format("BAD  %s.%s is %.3f studs from where BodyAssetData puts it (%s): the part was scaled differently from its attachments", p0.Name, an, de, v3f(e0)))
			end
		end
	else
		s ..= " att0=MISSING"
	end
	if a1 and a1:IsA("Attachment") then
		local d = (m.C1.Position - a1.CFrame.Position).Magnitude
		s ..= string.format(" att1=%s d=%.3f", v3f(a1.CFrame.Position), d)
		if d > 0.02 then
			table.insert(verdicts, string.format("BAD  %s.C1 is %.3f studs off %s.%s: the joint is not aimed at its RigAttachment", name, d, p1.Name, an))
		end
		local e1 = p1 and expectedAtt(p1, an)
		if e1 then
			local de = (a1.CFrame.Position - e1).Magnitude
			s ..= string.format(" exp1=%s d=%.3f", v3f(e1), de)
			if de > 0.02 then
				table.insert(verdicts, string.format("BAD  %s.%s is %.3f studs from where BodyAssetData puts it (%s): the part was scaled differently from its attachments", p1.Name, an, de, v3f(e1)))
			end
		end
	else
		s ..= " att1=MISSING"
	end
	return s
end

-- the bind pose (every Transform identity): each part's CFrame in HumanoidRootPart space, from the Motor6D chain
local function bindPose(model)
	local out = { HumanoidRootPart = CFrame.identity }
	local joints = {}
	for _, name in ipairs(MOTORS) do
		local holder = model:FindFirstChild(MOTOR_PARENT[name])
		local m = holder and holder:FindFirstChild(name)
		if m and m:IsA("Motor6D") and m.Part0 and m.Part1 then
			table.insert(joints, m)
		end
	end
	for _ = 1, #joints do
		for _, m in ipairs(joints) do
			local base = out[m.Part0.Name]
			if base and not out[m.Part1.Name] then
				out[m.Part1.Name] = base * m.C0 * m.C1:Inverse()
			end
		end
	end
	return out
end

local function lookLines(model, lines, verdicts)
	local look = model:FindFirstChild("BoxerLook")
	local head = model:FindFirstChild("Head")
	if not look then
		table.insert(lines, "look: no BoxerLook folder")
		return
	end
	local names = {}
	for _, f in ipairs(look:GetChildren()) do
		local n = 0
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		table.insert(names, string.format("%s(%d parts, Detail=%s)", f.Name, n, tostring(attr(f, "Detail"))))
	end
	table.insert(lines, "look folders: " .. table.concat(names, " ") .. " | Hands attr=" .. tostring(attr(model, "Hands")) .. " Outfit=" .. tostring(attr(model, "Outfit"))
		.. " HeadgearColor=" .. tostring(attr(model, "HeadgearColor")) .. " HeadgearCorner=" .. tostring(attr(model, "HeadgearCorner")))
	-- the hands: gloves / wraps, each welded to a hand or forearm
	local hands = look:FindFirstChild("Hands")
	if hands then
		local n, loose, kinds = 0, 0, {}
		for _, p in ipairs(hands:GetDescendants()) do
			if p:IsA("BasePart") then
				n += 1
				local w = p:FindFirstChildOfClass("WeldConstraint") or p:FindFirstChildOfClass("Weld")
				local to = w and ((w.Part0 == p and w.Part1) or w.Part0)
				if not (to and to.Parent) then
					loose += 1
				end
				local k = p.Name:gsub("[LR]$", "")
				kinds[k] = (kinds[k] or 0) + 1
				if n <= 10 then
					table.insert(lines, string.format("hands %-14s %-8s size=%s on=%s color=%d,%d,%d mesh=%s", p.Name, p.ClassName, v3(p.Size), to and to.Name or "NONE",
						p.Color.R * 255, p.Color.G * 255, p.Color.B * 255, p:IsA("MeshPart") and tostring(get(p, "MeshId") or ""):gsub("rbxassetid://", "") or "-"))
				end
			end
		end
		local kl = {}
		for k, c in pairs(kinds) do
			table.insert(kl, k .. "x" .. c)
		end
		table.sort(kl)
		table.insert(lines, string.format("hands: %d parts (%s), %d welded to nothing", n, table.concat(kl, " "), loose))
		if n == 0 then
			table.insert(verdicts, "BAD  the Hands folder is empty: no gloves / wraps built")
		elseif loose > 0 then
			table.insert(verdicts, string.format("BAD  %d hand pieces are welded to nothing (they fall or stay behind)", loose))
		else
			table.insert(verdicts, string.format("OK   hands: %d pieces (%s) welded", n, table.concat(kl, " ")))
		end
	else
		table.insert(verdicts, "BAD  no Hands folder: the gloves / wraps step never ran (or was removed)")
	end
	for _, fname in ipairs({ "Headgear", "Hat" }) do
		local f = look:FindFirstChild(fname)
		if f then
			local n, inside, shell = 0, 0, nil
			for _, p in ipairs(f:GetDescendants()) do
				if p:IsA("BasePart") then
					n += 1
					local rel = head and head:IsA("BasePart") and head.CFrame:ToObjectSpace(p.CFrame) or p.CFrame
					local w = p:FindFirstChildOfClass("WeldConstraint") or p:FindFirstChildOfClass("Weld")
					local to = w and ((w.Part0 == p and w.Part1) or w.Part0)
					if n <= 12 then
						table.insert(lines, string.format("%s %-12s %-8s size=%s relHead=%s color=%d,%d,%d massless=%s coll=%s weld->%s", fname:lower(), p.Name, p.ClassName,
							v3(p.Size), cfs(rel), p.Color.R * 255, p.Color.G * 255, p.Color.B * 255, tostring(p.Massless), tostring(p.CanCollide), to and to.Name or "NONE"))
					end
					if p.Name == "HGShell" or p.Name == "CapCrown" or p.Name == "Crown" then
						shell = p
					end
					if head and head:IsA("BasePart") and rel.Position.Magnitude < head.Size.X * 0.25 and p.Size.X < head.Size.X * 0.9 then
						inside += 1
					end
				end
			end
			table.insert(lines, string.format("%s: %d parts, %d of them small and centred in the head", fname:lower(), n, inside))
			if shell and head and head:IsA("BasePart") then
				local hs = math.min(head.Size.X, head.Size.Y, head.Size.Z)
				if shell.Size.X < hs * 0.98 then
					table.insert(verdicts, string.format("BAD  %s %s (%.2f wide) is narrower than the head (%.2f): the %s sits inside the skull", fname, shell.Name,
						shell.Size.X, hs, fname:lower()))
				else
					table.insert(verdicts, string.format("OK   %s %s %.2f wide over a %.2f head", fname, shell.Name, shell.Size.X, hs))
				end
			end
		end
	end
	local att = look:FindFirstChild("Attire")
	if att then
		local fa = {}
		for k, v in pairs(att:GetAttributes()) do
			table.insert(fa, k .. "=" .. tostring(v))
		end
		table.sort(fa)
		table.insert(lines, "attire attributes: " .. table.concat(fa, " "))
		local n = 0
		for _, p in ipairs(att:GetDescendants()) do
			if p:IsA("BasePart") then
				n += 1
				local w = p:FindFirstChildOfClass("WeldConstraint") or p:FindFirstChildOfClass("Weld")
				local to = w and ((w.Part0 == p and w.Part1) or w.Part0)
				local rel = to and to:IsA("BasePart") and to.CFrame:ToObjectSpace(p.CFrame) or nil
				if n <= 16 then
					table.insert(lines, string.format("attire %-14s %-8s size=%s on=%s off=%s", p.Name, p.ClassName, v3(p.Size), to and to.Name or "NONE",
						rel and v3f(rel.Position) or "-"))
				end
				if not to then
					table.insert(verdicts, "BAD  attire piece " .. p.Name .. " is welded to nothing")
				end
			end
		end
		table.insert(lines, string.format("attire: %d parts", n))
		if n == 0 then
			table.insert(verdicts, "BAD  the Attire folder is empty: no trunks / outfit built")
		end
	else
		table.insert(verdicts, "BAD  no Attire folder: the attire step never ran (or was removed)")
	end
end

local function humanoidLines(model, hum, lines, verdicts)
	if not hum then
		table.insert(lines, "humanoid: NONE")
		table.insert(verdicts, "BAD  no Humanoid")
		return
	end
	local hh = hum.HipHeight
	local root = model:FindFirstChild("HumanoidRootPart")
	local legs = BuilderTiers.HipHeight(model)
	local desc
	pcall(function()
		desc = hum:GetAppliedDescription()
	end)
	local ds = desc and string.format("H%.2f W%.2f D%.2f Head%.2f Prop%.2f Type%.2f", desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale,
		desc.ProportionScale, desc.BodyTypeScale) or "n/a"
	local sv = {}
	for _, n in ipairs(SCALE_VALUES) do
		local v = hum:FindFirstChild(n)
		if v and v:IsA("NumberValue") then
			table.insert(sv, n:gsub("Body", ""):gsub("Scale", "") .. "=" .. f2(v.Value))
		end
	end
	local animate = model:FindFirstChild("Animate")
	local tracks = {}
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		pcall(function()
			for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
				table.insert(tracks, (tr.Name ~= "" and tr.Name or (tr.Animation and tr.Animation.Name) or "?") .. ":" .. f2(tr.Weight or 0))
			end
		end)
	end
	table.insert(lines, string.format("humanoid HipHeight=%.3f legsSay=%s RigType=%s AutoScale=%s state=%s WalkSpeed=%.1f AutoRotate=%s PlatformStand=%s EvalSM=%s",
		hh, legs and f2(legs) or "n/a", tostring(hum.RigType and hum.RigType.Name), tostring(get(hum, "AutomaticScalingEnabled")),
		tostring(get(hum, "GetState") and hum:GetState().Name or "?"), hum.WalkSpeed, tostring(hum.AutoRotate), tostring(hum.PlatformStand),
		tostring(get(hum, "EvaluateStateMachine"))))
	table.insert(lines, string.format("description %s | values %s | Animate=%s Animator=%s tracks=[%s] ProcAnim=%s", ds, table.concat(sv, " "),
		animate and (animate.ClassName .. (get(animate, "Disabled") and " DISABLED" or " ENABLED")) or "none", animator and "yes" or "NO",
		table.concat(tracks, " "), tostring(attr(model, "ProcAnim"))))
	if root and root:IsA("BasePart") then
		table.insert(lines, string.format("root pos=%s vel=%s size=%s anchored=%s", v3(root.Position), v3(root.AssemblyLinearVelocity), v3(root.Size),
			tostring(root.Anchored)))
	end
	if legs then
		if math.abs(legs - hh) <= 0.05 then
			table.insert(verdicts, string.format("OK   HipHeight %.2f vs the legs' own %.2f", hh, legs))
		else
			table.insert(verdicts, string.format("BAD  HipHeight %.2f vs the legs' own %.2f: the body stands %.2f studs %s the floor", hh, legs, math.abs(legs - hh),
				hh > legs and "above" or "into"))
		end
	end
	if #tracks > 0 then
		table.insert(verdicts, "BAD  Animate track(s) playing [" .. table.concat(tracks, " ") .. "]: a second writer on the joints (the Animator stops them; they came back)")
	else
		table.insert(verdicts, "OK   no Animate tracks playing")
	end
	if animate and get(animate, "Disabled") == false and attr(model, "ProcAnim") == true then
		table.insert(verdicts, "BAD  the Animate script is ENABLED on a procedurally driven character")
	end
end

------------------------------------------------------------------------
-- Report
------------------------------------------------------------------------
-- ctx (all optional): label, side ("client" | "server"), rig (the Animator's rig table), sample (DiagClient's motion
-- sample lines), unit (BodyAssetData.unit for the height comparison; BodyTiers.Data().unit by default)
function Diag.Report(model, ctx)
	ctx = ctx or {}
	local lines, verdicts = {}, {}
	local hum = model:FindFirstChildOfClass("Humanoid")
	local inGame = false
	pcall(function()
		inGame = model:IsDescendantOf(game)
	end)
	local tags = {}
	pcall(function()
		tags = game:GetService("CollectionService"):GetTags(model)
	end)
	table.insert(lines, string.format("== %s %q at %s | side=%s inDataModel=%s tags=[%s] BodyTiers=%s Detail=%s ScaleKey=%s AvatarFace=%s", ctx.label or "MODEL",
		model.Name, fullName(model.Parent or model), ctx.side or "?", tostring(inGame), table.concat(tags, ","), tostring(attr(model, "BodyTiers")),
		tostring(attr(model, "Detail")), tostring(attr(model, "ScaleKey")), tostring(attr(model, "AvatarFace"))))
	humanoidLines(model, hum, lines, verdicts)
	for _, name in ipairs(PARTS) do
		table.insert(lines, partLine(model, name))
	end
	-- the head: the classic head (a Part with the Head SpecialMesh) unless the rig keeps a player's avatar face; its size now
	-- against the size the layers (headgear, face) were fitted to, and the HipHeight now against the build's
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local hb, hhb, refix = attr(model, "HeadSizeAtBuild"), attr(model, "HipHeightAtBuild"), attr(model, "HipHeightRefixed")
		local headScale = "?"
		pcall(function()
			local d = hum and hum:GetAppliedDescription()
			if d then
				headScale = f2(d.HeadScale)
			end
		end)
		table.insert(lines, string.format("head size now=%s atBuild=%s HeadScale=%s | HipHeight now=%s atBuild=%s refixedLater=%s", v3(head.Size),
			typeof(hb) == "Vector3" and v3(hb) or "n/a", headScale, hum and f2(hum.HipHeight) or "?", hhb and f2(hhb) or "n/a", refix and f2(refix) or "no"))
		if typeof(hb) == "Vector3" and (hb - head.Size).Magnitude > 1e-3 then
			table.insert(verdicts, string.format("BAD  the Head changed size after the layers were built (%s -> %s): the headgear / face were fitted to the old size",
				v3(hb), v3(head.Size)))
		elseif typeof(hb) == "Vector3" then
			table.insert(verdicts, "OK   the Head is the size the layers were built for")
		end
		if hum and type(hhb) == "number" and math.abs(hhb - hum.HipHeight) > 0.01 then
			table.insert(verdicts, string.format("BAD  HipHeight changed since the build (%.2f -> %.2f%s): something re-set it after Builder", hhb, hum.HipHeight,
				refix and ", re-fixed later to " .. f2(refix) or ""))
		end
		if refix then
			table.insert(verdicts, string.format("BAD  Builder had to put HipHeight back to %.2f after the build: the engine's scaling pass changed it", refix))
		end
		local sm = head:FindFirstChildOfClass("SpecialMesh")
		if attr(model, "AvatarFace") == true then
			table.insert(verdicts, "OK   Head kept as the avatar's (" .. head.ClassName .. ")")
		elseif head:IsA("MeshPart") then
			table.insert(verdicts, "BAD  Head is a MeshPart (expected Part + SpecialMesh Head): the classic head swap did not take; the face / headgear are built for the classic head")
		elseif not (sm and sm.MeshType == Enum.MeshType.Head) then
			table.insert(verdicts, "BAD  Head is a " .. head.ClassName .. " without the Head SpecialMesh")
		else
			table.insert(verdicts, string.format("OK   Head is a Part + SpecialMesh Head, %.2f studs", head.Size.Y))
		end
	end
	-- the tier parts: every part the key says is a tier part carries that tier, and is scaled exactly once
	local key = attr(model, "BodyTiers")
	local defaults, twice = {}, {}
	for _, name in ipairs(BodyTiers.PARTS) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local tier = attr(p, "BodyTier")
			if tier == nil then
				table.insert(defaults, name)
			else
				local okE, e = pcall(BodyTiers.PartEntry, tonumber(tier), name, nil, attr(p, "BodyLite") == true)
				local have = p:IsA("MeshPart") and tostring(get(p, "MeshId") or ""):gsub("rbxassetid://", "") or "-"
				if okE and e and have ~= tostring(e.id) then
					table.insert(verdicts, string.format("BAD  %s shows mesh %s, tier %s expects %s: not the tier part the attribute claims", name, have, tostring(tier), tostring(e.id)))
				end
				local r0 = attr(p, "BodyRatio")
				local r = BuilderTiers.RatioOf(p)
				if typeof(r0) == "Vector3" and r and (r - r0).Magnitude > 0.02 then
					table.insert(twice, string.format("%s %s vs %s", name, v3(r), v3(r0)))
				end
			end
		end
	end
	if type(key) == "string" and key:find("[1-9]") and #defaults > 0 then
		table.insert(verdicts, "BAD  default (untiered) parts on a tiered body: " .. table.concat(defaults, " ") .. " (their swaps did not take)")
	elseif #defaults == 0 then
		table.insert(verdicts, "OK   every body part is a tier part")
	else
		table.insert(verdicts, "OK   a body of default parts (no tiers asked for)")
	end
	if #twice > 0 then
		table.insert(verdicts, "BAD  tier parts whose Size / OriginalSize is not the ratio they were swapped at (scaled again since): " .. table.concat(twice, "; "))
	end
	for _, name in ipairs(MOTORS) do
		table.insert(lines, motorLine(model, name, verdicts))
	end
	-- the bind pose's joint heights above the lowest sole (HumanoidRootPart space), next to the unit rig's x the height scale
	local okB, pose = pcall(bindPose, model)
	if okB and pose.LowerTorso and pose.LeftFoot and pose.RightFoot then
		local lf, rf = model:FindFirstChild("LeftFoot"), model:FindFirstChild("RightFoot")
		local sole = math.min(pose.LeftFoot.Position.Y - (lf and lf.Size.Y or 0.3) / 2, pose.RightFoot.Position.Y - (rf and rf.Size.Y or 0.3) / 2)
		local function jy(holder, mname)
			local h = model:FindFirstChild(holder)
			local m = h and h:FindFirstChild(mname)
			local base = m and m:IsA("Motor6D") and m.Part0 and pose[m.Part0.Name]
			return base and (base * m.C0).Position.Y - sole or nil
		end
		local hs = { Root = jy("LowerTorso", "Root"), Waist = jy("UpperTorso", "Waist"), RightHip = jy("RightUpperLeg", "RightHip"),
			RightKnee = jy("RightLowerLeg", "RightKnee"), RightAnkle = jy("RightFoot", "RightAnkle"), Neck = jy("Head", "Neck"), RightShoulder = jy("RightUpperArm", "RightShoulder") }
		local unit = ctx.unit
		if unit == nil then
			-- (v12: the frame's own rig heights, BodyAssetData.frames[id].unit; the default family's otherwise)
			local okU, u = pcall(BodyTiers.Unit, model:GetAttribute("BodyFrame") or model:GetAttribute("Frame"))
			unit = okU and type(u) == "table" and u or nil
		end
		local hscale = 1
		pcall(function()
			local d = hum and hum:GetAppliedDescription()
			if d and d.HeightScale > 0 then
				hscale = d.HeightScale
			end
		end)
		local parts = {}
		for _, k in ipairs({ "Root", "Waist", "RightHip", "RightKnee", "RightAnkle", "RightShoulder", "Neck" }) do
			local u = unit and unit.joints and unit.joints[k]
			parts[#parts + 1] = string.format("%s=%s%s", k, hs[k] and f2(hs[k]) or "?", u and string.format("(unit %.2f)", u[2] * hscale) or "")
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local soleUnderRoot = -sole
		table.insert(lines, string.format("bindpose heights above the sole: %s | HRP centre %.2f above the sole (HipHeight+HRP/2 = %s) heightScale=%.2f", table.concat(parts, " "),
			soleUnderRoot, (hum and root) and f2(hum.HipHeight + root.Size.Y / 2) or "?", hscale))
		if hum and root then
			local d = soleUnderRoot - (hum.HipHeight + root.Size.Y / 2)
			if math.abs(d) > 0.05 then
				table.insert(verdicts, string.format("BAD  the soles hang %.2f studs %s where HipHeight puts the floor: the feet %s", math.abs(d), d > 0 and "below" or "above",
					d > 0 and "sink into the ground (the Humanoid floats on HipHeight)" or "float (or the legs are bent to reach the ground)"))
			else
				table.insert(verdicts, string.format("OK   soles at HipHeight (%.2f vs %.2f)", soleUnderRoot, hum.HipHeight + root.Size.Y / 2))
			end
		end
	else
		table.insert(lines, "bindpose: could not be chained (" .. tostring(okB and "parts missing" or pose) .. ")")
	end
	lookLines(model, lines, verdicts)
	-- the Animator's view (client only)
	local rig = ctx.rig
	if rig then
		local g = rig.geo or {}
		local missing = {}
		for _, k in ipairs({ "Root", "W", "Neck", "RS", "RE", "RW", "LS", "LE", "LW", "RH", "RK", "RA", "LH", "LK", "LA" }) do
			if not (rig.joints and rig.joints[k]) then
				table.insert(missing, k)
			end
		end
		local lo = rig.loco or {}
		table.insert(lines, string.format("animator geo.ok=%s legLen=%s hipW=%s floorH=%s rootY=%s groundY=%s utScale=%s footW=%s meshFeet=%s | lod=%s released=%s isPlayer=%s isLocal=%s fighter=%s ambient=%s trainee=%s ref=%s pose=%s loop=%s speed=%s camDist=%s missingJoints=[%s]",
			tostring(g.ok), g.legLen and f2(g.legLen) or "-", g.hipW and f2(g.hipW) or "-", g.floorH and f2(g.floorH) or "-", g.rootY and f2(g.rootY) or "-",
			g.groundY and f2(g.groundY) or "-", g.utScale and v3(g.utScale) or "-", g.footW and f2(g.footW) or "-", tostring(g.meshFeet), tostring(rig.lod),
			tostring(rig.released), tostring(rig.isPlayer), tostring(rig.isLocal), tostring(rig.isFighter), tostring(rig.isAmbient), tostring(rig.isTrainee),
			tostring(rig.isReferee), tostring(rig.a and rig.a.Pose), tostring(rig.a and rig.a.Loop), lo.speed and f2(lo.speed) or "-", rig.camDist and f2(rig.camDist) or "-",
			table.concat(missing, ",")))
		if not g.ok then
			table.insert(verdicts, "BAD  the Animator could not measure this rig (geo.ok false; joints missing: " .. table.concat(missing, ",") .. "): no gait, no IK on it")
		elseif hum and g.floorH and g.rootY then
			local root = model:FindFirstChild("HumanoidRootPart")
			local want = root and (hum.HipHeight + root.Size.Y / 2) or nil
			local have = g.floorH - g.rootY
			if want and math.abs(have - want) > 0.05 then
				table.insert(verdicts, string.format("BAD  Animator floor %.2f under the root vs HipHeight's %.2f: the planted feet and the Humanoid disagree about the ground", have, want))
			else
				table.insert(verdicts, string.format("OK   Animator floor %.2f under the root matches HipHeight", have))
			end
		end
	elseif ctx.side == "client" then
		table.insert(lines, "animator: this model is NOT in the Animator's rig registry (no tag / not a player character)")
		table.insert(verdicts, "BAD  the Animator does not drive this model")
	end
	if type(ctx.sample) == "table" then
		for _, s in ipairs(ctx.sample.lines or {}) do
			table.insert(lines, s)
		end
		for _, s in ipairs(ctx.sample.verdicts or {}) do
			table.insert(verdicts, s)
		end
	end
	for _, v in ipairs(verdicts) do
		table.insert(lines, "VERDICT " .. v)
	end
	table.insert(lines, "== end " .. model.Name)
	return lines, verdicts
end

-- the lines as one block (every line prefixed), ready for print / warn
function Diag.Block(lines)
	local out = table.create(#lines)
	for i, l in ipairs(lines) do
		out[i] = Diag.PREFIX .. l
	end
	return table.concat(out, "\n")
end

function Diag.Print(model, ctx)
	local ok, lines = pcall(Diag.Report, model, ctx)
	if ok then
		print(Diag.Block(lines))
	else
		print(Diag.PREFIX .. "report failed on " .. tostring(model) .. ": " .. tostring(lines))
	end
	return ok
end

-- the models worth reporting near a position: the player's own character first, then the nearest `n` other humanoid
-- models in workspace (NPCs, other players), nearest first
function Diag.Pick(center, own, n, root)
	root = root or workspace
	local list = {}
	local seen = {}
	if own then
		seen[own] = true
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Humanoid") then
			local m = d.Parent
			local hrp = m and m:FindFirstChild("HumanoidRootPart")
			if m and hrp and hrp:IsA("BasePart") and not seen[m] then
				seen[m] = true
				table.insert(list, { m = m, d = (hrp.Position - center).Magnitude })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	if own then
		table.insert(out, own)
	end
	for i = 1, math.min(n or 2, #list) do
		table.insert(out, list[i].m)
	end
	return out
end

------------------------------------------------------------------------
-- Motion sample (the caller feeds frames; pure here): per tick the root's velocity and height, each foot's world Y
-- and horizontal travel while it is down, the hip / knee / elbow bend from the live Transforms, and whether any
-- Animate track was playing. Diag.NewSample() -> S; Diag.SampleTick(S, model, t); Diag.SampleLines(S) -> { lines, verdicts }
------------------------------------------------------------------------
local function bend(model, holder, mname)
	local h = model:FindFirstChild(holder)
	local m = h and h:FindFirstChild(mname)
	if not (m and m:IsA("Motor6D")) then
		return nil
	end
	local x = m.Transform:ToEulerAnglesXYZ()
	return math.deg(x)
end

function Diag.NewSample()
	return { ticks = {}, lastL = nil, lastR = nil, slideL = 0, slideR = 0, downL = 0, downR = 0, tracks = 0 }
end

function Diag.SampleTick(S, model, t)
	local root = model:FindFirstChild("HumanoidRootPart")
	local lf, rf = model:FindFirstChild("LeftFoot"), model:FindFirstChild("RightFoot")
	if not (root and lf and rf) then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local an = hum and hum:FindFirstChildOfClass("Animator")
	local playing = false
	if an then
		pcall(function()
			playing = #an:GetPlayingAnimationTracks() > 0
		end)
	end
	if playing then
		S.tracks += 1
	end
	local vel = root.AssemblyLinearVelocity
	local tick = {
		t = t, vx = Vector3.new(vel.X, 0, vel.Z).Magnitude, rootY = root.Position.Y, lY = lf.Position.Y, rY = rf.Position.Y,
		lP = lf.Position, rP = rf.Position, hip = bend(model, "RightUpperLeg", "RightHip"), knee = bend(model, "RightLowerLeg", "RightKnee"),
		elbow = bend(model, "RightLowerArm", "RightElbow"), playing = playing,
	}
	table.insert(S.ticks, tick)
	-- a foot is "down" when it is within 0.12 of the lowest foot height seen so far; its travel then is slide
	local n = #S.ticks
	if n > 1 then
		local lo = math.huge
		for _, k in ipairs(S.ticks) do
			lo = math.min(lo, k.lY, k.rY)
		end
		local prev = S.ticks[n - 1]
		if tick.lY < lo + 0.12 and prev.lY < lo + 0.12 then
			local d = (Vector3.new(tick.lP.X, 0, tick.lP.Z) - Vector3.new(prev.lP.X, 0, prev.lP.Z)).Magnitude
			S.slideL += d
			S.downL += 1
		end
		if tick.rY < lo + 0.12 and prev.rY < lo + 0.12 then
			local d = (Vector3.new(tick.rP.X, 0, tick.rP.Z) - Vector3.new(prev.rP.X, 0, prev.rP.Z)).Magnitude
			S.slideR += d
			S.downR += 1
		end
	end
end

function Diag.SampleLines(S)
	local lines, verdicts = {}, {}
	local n = #S.ticks
	if n == 0 then
		table.insert(lines, "sample: no ticks")
		return { lines = lines, verdicts = verdicts }
	end
	local vmax, rootMin, rootMax, lo = 0, math.huge, -math.huge, math.huge
	for _, k in ipairs(S.ticks) do
		vmax = math.max(vmax, k.vx)
		rootMin, rootMax = math.min(rootMin, k.rootY), math.max(rootMax, k.rootY)
		lo = math.min(lo, k.lY, k.rY)
	end
	table.insert(lines, string.format("sample %d ticks over %.1fs: vmax=%.2f rootY %.2f..%.2f (bob %.2f) lowestFootY=%.2f animateTicks=%d slideL=%.2f/%d slideR=%.2f/%d",
		n, S.ticks[n].t - S.ticks[1].t, vmax, rootMin, rootMax, rootMax - rootMin, lo, S.tracks, S.slideL, S.downL, S.slideR, S.downR))
	for _, k in ipairs(S.ticks) do
		table.insert(lines, string.format("  t=%.1f v=%.2f rootY=%.2f footL=%.2f footR=%.2f hip=%s knee=%s elbow=%s%s", k.t, k.vx, k.rootY, k.lY, k.rY,
			k.hip and string.format("%d", k.hip) or "-", k.knee and string.format("%d", k.knee) or "-", k.elbow and string.format("%d", k.elbow) or "-",
			k.playing and " ANIMATE" or ""))
	end
	local moving = vmax > 2
	if not moving then
		table.insert(verdicts, "note the character did not move during the sample (walk while it runs for the gait numbers)")
	else
		local slide = (S.slideL + S.slideR) / math.max(1, S.downL + S.downR)
		if slide > 0.08 then
			table.insert(verdicts, string.format("BAD  the planted feet slide %.2f studs per tick while down: the gait and the root disagree (speed, HipHeight or a second writer)", slide))
		else
			table.insert(verdicts, string.format("OK   planted feet hold (%.2f studs per tick)", slide))
		end
		if rootMax - rootMin > 0.6 then
			table.insert(verdicts, string.format("BAD  the root bobs %.2f studs while walking", rootMax - rootMin))
		end
		local bentKnee = false
		for _, k in ipairs(S.ticks) do
			if k.knee and math.abs(k.knee) > 8 then
				bentKnee = true
			end
		end
		if not bentKnee then
			table.insert(verdicts, "BAD  the knees never bent while moving: the Animator is not writing this rig's legs (or its writes are overwritten)")
		end
	end
	if S.tracks > 0 then
		table.insert(verdicts, string.format("BAD  Animate tracks were playing on %d of %d ticks: a conflicting writer", S.tracks, n))
	end
	return { lines = lines, verdicts = verdicts }
end

return Diag
