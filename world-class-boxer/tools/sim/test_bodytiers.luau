--!nocheck
-- tools/sim/test_bodytiers.luau: the standard R15 body under lune.
--   * BodyTiers: tier selection from builds (levels, bands, hysteresis, hands / feet following their limb, frames,
--     women), the face list / sanitiser / textures, the expression moods
--   * BuilderTiers: the part swap on a fake rig (fakeengine Instances, a fake Humanoid whose ReplaceBodyPartR15
--     either keeps the given size like the simulator or scales from OriginalSize like the engine, a fake
--     AssetService): success (size = OriginalSize x the default part's ratio, attachments, joints re-aimed, welds
--     moved, HipHeight, the BodyTiers attribute, change-only), a failed load (the default part kept, the failure
--     cached), every id 0 (nothing loaded, nothing swapped)
--   * Looks: the face key sanitised (creator faces only), old saves migrated to the smile, NPC faces
--   * face styles (look.face.style): the drawn Boxer faces offered / sanitised / kept off face.key, old saves built,
--     the mood set; decal mode on the classic head (one white opaque front decal, no built eyes / brows / nose / lips
--     or rig, ears kept, damage / sweat / grime at the drawn features, the decal restored when served from cache),
--     FaceFX swapping the four by mood, back to the built face unchanged
--   * the built face on the classic head (BuilderHead, the v7 face): no decal, the FaceFX rig, the part budget per
--     detail level; FaceFX animates it (expressions, blinks on a hit); the post-workout flow (Grime, a tier-up rebuild,
--     SetSweat) and the damage presets never darken the face (no near-black part over the skin but the features)
--   * the asset hair on the classic head (HK.Fit with CLASSIC_FIT): cards clear the head, the cap's worst point
--   lune run tools/sim/test_bodytiers.luau
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
local function near(a, b, tol)
	return math.abs(a - b) <= (tol or 1e-6)
end
local function vnear(a, b, tol)
	return (a - b).Magnitude <= (tol or 1e-4)
end

local E = FE.new()
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
E.install(H)
local BodyTiers = H.require("BodyTiers")
local REAL = BodyTiers.Data()

local function build(v)
	local b = { fat = 14 }
	for _, id in ipairs({ "pecs", "upperChest", "frontDelt", "sideDelt", "rearDelt", "biceps", "triceps", "forearms", "lats", "traps",
		"upperBack", "lowerBack", "abs", "lowerAbs", "obliques", "serratus", "quads", "hamstrings", "glutes", "calves", "neckSCM" }) do
		b[id] = v
	end
	return b
end

------------------------------------------------------------------------
-- tier selection
------------------------------------------------------------------------
do
	local athletic = { potential = 0.95 }
	local function all(t, want)
		for _, n in ipairs(BodyTiers.PARTS) do
			if t[n] ~= want then
				return false, n .. "=" .. tostring(t[n])
			end
		end
		return true
	end
	check("14 parts", #BodyTiers.PARTS == 14)
	local ok, why = all(BodyTiers.Tiers(build(8), athletic), 1)
	check("untrained (8) -> tier 1 everywhere", ok, why)
	ok, why = all(BodyTiers.Tiers({}, athletic), 1)
	check("empty build (old save / NPC) -> tier 1", ok, why)
	ok, why = all(BodyTiers.Tiers(build(95), athletic), 5)
	check("maxed Athletic (95) -> tier 5", ok, why)
	ok, why = all(BodyTiers.Tiers(build(50), athletic), 3)
	check("half the cap (50) -> tier 3", ok, why)
	-- the bands by level
	check("TierOf bands", BodyTiers.TierOf(0.1) == 1 and BodyTiers.TierOf(0.2) == 2 and BodyTiers.TierOf(0.4) == 3
		and BodyTiers.TierOf(0.6) == 4 and BodyTiers.TierOf(0.9) == 5)
	-- hysteresis: a part at tier 2 stays until the level is HYST past the band
	check("hysteresis keeps the tier just over the band", BodyTiers.TierOf(0.37, 2) == 2)
	check("hysteresis keeps the tier just under the band", BodyTiers.TierOf(0.34, 3) == 3)
	check("hysteresis lets go past HYST", BodyTiers.TierOf(0.40, 2) == 3 and BodyTiers.TierOf(0.31, 3) == 2)
	check("a jump of several tiers is one step", BodyTiers.TierOf(0.9, 1) == 5)
	-- one group trained: only its parts move; hands follow the forearm, feet the calf
	local b = build(8)
	b.forearms, b.calves = 90, 90
	local t = BodyTiers.Tiers(b, athletic)
	check("forearms trained -> lower arms tier 5", t.LeftLowerArm == 5 and t.RightLowerArm == 5, t.LeftLowerArm)
	check("hands follow the forearm", t.LeftHand == 5 and t.RightHand == 5, t.LeftHand)
	check("feet follow the calf", t.LeftFoot == 5 and t.RightFoot == 5 and t.LeftLowerLeg == 5, t.LeftFoot)
	check("untrained groups stay tier 1", t.UpperTorso == 1 and t.LeftUpperArm == 1 and t.LeftUpperLeg == 1 and t.LowerTorso == 1)
	-- chest / back training builds the upper torso, squats the thighs (and the glutes the lower torso)
	b = build(8)
	for _, id in ipairs({ "pecs", "upperChest", "lats", "upperBack", "traps", "abs" }) do
		b[id] = 80
	end
	t = BodyTiers.Tiers(b, athletic)
	check("chest + back -> UpperTorso up", t.UpperTorso >= 4 and t.LowerTorso == 1, t.UpperTorso)
	b = build(8)
	b.quads, b.hamstrings, b.glutes = 85, 85, 85
	t = BodyTiers.Tiers(b, athletic)
	check("squats -> thighs up, lower torso a little", t.LeftUpperLeg == 5 and t.LowerTorso >= 2 and t.LowerTorso < 5, t.LowerTorso)
	-- groups fall back to their coarse group (old saves): Config.PartValue's rule
	t = BodyTiers.Tiers({ arms = 90, shoulders = 90, chest = 8 }, athletic)
	check("group values (old saves) feed the parts", t.LeftUpperArm == 5 and t.LeftLowerArm == 5 and t.UpperTorso == 1, t.LeftUpperArm)
	-- frames: the same value reads bigger on a Lean frame (its cap is lower), women need more
	local lean = BodyTiers.Tiers(build(75), { potential = 0.8 })
	local heavy = BodyTiers.Tiers(build(75), { potential = 1.25 })
	check("Lean frame at 75 -> tier 5, Heavyweight frame -> tier 4", lean.UpperTorso == 5 and heavy.UpperTorso == 4,
		lean.UpperTorso .. "/" .. heavy.UpperTorso)
	local man = BodyTiers.Tiers(build(65), athletic)
	local woman = BodyTiers.Tiers(build(65), { potential = 0.95, female = true })
	check("women read lower at the same value", woman.UpperTorso < man.UpperTorso, man.UpperTorso .. "/" .. woman.UpperTorso)
	-- previous tiers feed the hysteresis per part
	local prev = {}
	for _, n in ipairs(BodyTiers.PARTS) do
		prev[n] = 3
	end
	t = BodyTiers.Tiers(build(34), athletic, prev) -- level ~0.35: tier 2 by the bands, 3 kept
	check("Tiers keeps the shown tier inside HYST", t.UpperTorso == 3, t.UpperTorso)
	check("Key", BodyTiers.Key(BodyTiers.Tiers(build(8), athletic)) == string.rep("1", 14))
	-- the real manifest: every tier part has a mesh id, a size and its rig attachments
	local missing = {}
	for tier = 1, 5 do
		for _, n in ipairs(BodyTiers.PARTS) do
			local e = BodyTiers.PartEntry(tier, n, REAL)
			if not (e and e.attachments[(n:match("^(%u%l+)") == "Left" or n:match("^Right")) and nil or ""] == nil) then
				-- (the entry exists; attachments checked below)
			end
			if not e then
				table.insert(missing, tier .. n)
			else
				local rig = 0
				for an in pairs(e.attachments) do
					if an:find("RigAttachment") then
						rig += 1
					end
				end
				if rig < 1 then
					table.insert(missing, tier .. n .. "(no rig attachments)")
				end
			end
		end
	end
	check("manifest: 70 tier parts with ids and rig attachments", #missing == 0, table.concat(missing, ","))
	check("PartEntry: id 0 -> nil", BodyTiers.PartEntry(1, "UpperTorso", { tiers = { { parts = { UpperTorso = { mesh = 0, size = { 1, 1, 1 } } } } } }) == nil)
	local fit = BodyTiers.Fit(3, "forearm", REAL)
	check("tier fit measures", fit ~= nil and fit.width > 0.2 and fit.width < 1, fit and fit.width)
end

------------------------------------------------------------------------
-- faces and expressions
------------------------------------------------------------------------
do
	local ZERO = { faces = {
		{ key = "smile", name = "Smile", id = 0, creator = true }, { key = "grin", name = "Grin", id = 0, creator = true },
		{ key = "hurt", name = "Hurt", id = 0, creator = false },
	}, expressions = { hurt = "hurt", happy = "grin" } }
	check("smile always first", BodyTiers.Faces({})[1].key == "smile")
	check("ids 0: texture = the engine smile", BodyTiers.FaceTexture("grin", ZERO) == BodyTiers.DEFAULT_TEXTURE)
	check("unknown key: texture = the smile", BodyTiers.FaceTexture("nope", ZERO) == BodyTiers.DEFAULT_TEXTURE)
	local smile = BodyTiers.Face("smile", REAL)
	check("real smile has an id", smile and smile.id ~= nil)
	check("real texture", BodyTiers.FaceTexture("grin", REAL) == "rbxassetid://" .. BodyTiers.Face("grin", REAL).id)
	check("sanitise: creator key kept", BodyTiers.SanitizeFace("cool", nil, REAL) == "cool")
	check("sanitise: mood-only key refused", BodyTiers.SanitizeFace("ko", nil, REAL) == "smile")
	check("sanitise: bad input keeps the saved key", BodyTiers.SanitizeFace({}, "wink", REAL) == "wink")
	check("sanitise: junk -> smile", BodyTiers.SanitizeFace(12, "nope", REAL) == "smile")
	local pick = BodyTiers.Pickable(REAL)
	local picks = {}
	for _, f in ipairs(pick) do
		table.insert(picks, f.key)
	end
	check("10 creator faces, smile first", #pick == 10 and pick[1].key == "smile", table.concat(picks, ","))
	-- moods
	check("Expr pain -> hurt", BodyTiers.MoodOf("pain") == "hurt")
	check("Expr dazed -> dazed", BodyTiers.MoodOf("dazed") == "dazed")
	check("Expr ko -> ko", BodyTiers.MoodOf("ko") == "ko")
	check("Expr effort -> effort", BodyTiers.MoodOf("effort") == "effort")
	check("Expr happy -> happy", BodyTiers.MoodOf("happy") == "happy")
	check("nil / unknown -> neutral", BodyTiers.MoodOf(nil) == "neutral" and BodyTiers.MoodOf("zzz") == "neutral")
	check("mood face: hurt -> hurt (real)", BodyTiers.MoodFace("hurt", "cool", REAL) == "hurt")
	check("mood face: effort -> grit (real)", BodyTiers.MoodFace("effort", "cool", REAL) == "grit")
	check("mood face: stunned -> dazed (real)", BodyTiers.MoodFace("stunned", "cool", REAL) == "dazed")
	check("mood face: neutral -> his own", BodyTiers.MoodFace("neutral", "cool", REAL) == "cool")
	check("mood face: ids 0 -> his own", BodyTiers.MoodFace("hurt", "grin", ZERO) == "grin")
	check("mood texture: ids 0 -> the engine smile", BodyTiers.MoodTexture("hurt", "grin", ZERO) == BodyTiers.DEFAULT_TEXTURE)
	-- damage layers
	local s = BodyTiers.DamageStrengths({ leftEye = 1, cut = 0.8, cutSide = -1, bruise = 0.6 })
	check("damage: left black eye, left cut, bruise", s.blackEyeL > 0.9 and s.blackEyeR == 0 and s.cutL > 0.7 and s.cutR == 0 and s.bruise > 0.4)
	check("damage: no uploads -> no decal ids", BodyTiers.DamageId("blackEyeL", REAL) == nil)
	-- the drawn face styles
	local styles = BodyTiers.FaceStyles(REAL)
	local sk = {}
	for _, st in ipairs(styles) do
		table.insert(sk, st.key .. "=" .. st.name)
	end
	check("styles: Built + the 4 Boxer faces (uploaded)", table.concat(sk, ",")
		== "built=Built,wcb_neutral=Boxer Neutral,wcb_focused=Boxer Focused,wcb_smirk=Boxer Smirk,wcb_grit=Boxer Grit", table.concat(sk, ","))
	local allIds = true
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		local f = BodyTiers.Face(k, REAL)
		allIds = allIds and f ~= nil and f.id ~= nil and f.creator and BodyTiers.FaceTexture(k, REAL) == "rbxassetid://" .. f.id
	end
	check("styles: every Boxer face has a real id and texture", allIds)
	check("styles: ids 0 -> only Built offered", #BodyTiers.FaceStyles({ faces = { { key = "wcb_grit", name = "G", id = 0 } } }) == 1)
	check("styles: never a classic face key", BodyTiers.SanitizeFace("wcb_smirk", nil, REAL) == "smile" and BodyTiers.SanitizeFace({}, "wcb_grit", REAL) == "smile")
	check("styles: kept off the classic picker", not table.find(picks, "wcb_neutral") and not table.find(picks, "wcb_grit"))
	check("style sanitise: a drawn face kept", BodyTiers.SanitizeFaceStyle("wcb_grit", nil, REAL) == "wcb_grit")
	check("style sanitise: built kept", BodyTiers.SanitizeFaceStyle("built", "wcb_grit", REAL) == "built")
	check("style sanitise: junk keeps the saved style", BodyTiers.SanitizeFaceStyle("cool", "wcb_focused", REAL) == "wcb_focused")
	check("style sanitise: nothing -> built", BodyTiers.SanitizeFaceStyle(nil, nil, REAL) == "built" and BodyTiers.SanitizeFaceStyle(5, "x", REAL) == "built")
	check("style sanitise: not uploaded -> built", BodyTiers.SanitizeFaceStyle("wcb_grit", nil, ZERO) == "built")
	local moodWant = { guard = "wcb_focused", attack = "wcb_focused", train = "wcb_focused", effort = "wcb_grit", hurt = "wcb_grit",
		angry = "wcb_grit", taunt = "wcb_smirk", happy = "wcb_smirk", confident = "wcb_smirk", ko = "wcb_neutral", dazed = "wcb_neutral",
		stunned = "wcb_neutral", neutral = "wcb_smirk", rest = "wcb_smirk" }
	local moodBad = {}
	for mood, want in pairs(moodWant) do
		local got = BodyTiers.StyleMoodFace(mood, "wcb_smirk", REAL)
		if got ~= want then
			table.insert(moodBad, mood .. "->" .. tostring(got))
		end
	end
	check("style moods: the set by mood, the chosen face at rest", #moodBad == 0, table.concat(moodBad, ", "))
	check("style moods: not uploaded -> the chosen face", BodyTiers.StyleMoodFace("guard", "wcb_grit", ZERO) == "wcb_grit")
	check("drawn style of a look", BodyTiers.DrawnStyleOf({ face = { style = "wcb_focused" } }, REAL) == "wcb_focused"
		and BodyTiers.DrawnStyleOf({ face = { style = "built" } }, REAL) == nil and BodyTiers.DrawnStyleOf({ face = {} }, REAL) == nil)
end

------------------------------------------------------------------------
-- Looks: the face key
------------------------------------------------------------------------
do
	local Looks = H.require("Looks")
	check("defaults: smile", Looks.Defaults(1).face.key == "smile")
	local old = Looks.Defaults(1)
	old.face.key = nil
	Looks.Fill(old)
	check("old save -> smile (Fill)", old.face.key == "smile")
	local saved = Looks.Defaults(1)
	saved.face.key = "stern"
	check("Sanitize keeps a creator face", Looks.Sanitize({ face = { key = "wink" } }, saved).face.key == "wink")
	check("Sanitize refuses a mood face (keeps the saved one)", Looks.Sanitize({ face = { key = "ko" } }, saved).face.key == "stern")
	check("Sanitize: no key in the input keeps the saved one", Looks.Sanitize({ face = {} }, saved).face.key == "stern")
	check("Sanitize: no old save, junk -> smile", Looks.Sanitize({ face = { key = "x" } }).face.key == "smile")
	local keys, valid = {}, true
	for seed = 1, 60 do
		local k = Looks.Random(seed * 7919, 1).face.key
		keys[k] = true
		valid = valid and BodyTiers.SanitizeFace(k) == k
	end
	local n = 0
	for _ in pairs(keys) do
		n += 1
	end
	check("NPC faces: creator faces only, varied", valid and n >= 5, n)
	check("NPC face is deterministic", Looks.Random(42, 1).face.key == Looks.Random(42, 1).face.key)
	-- the face style
	check("defaults: built face style", Looks.Defaults(1).face.style == "built" and Looks.Defaults(2).face.style == "built")
	local oldS = Looks.Defaults(1)
	oldS.face.style = nil
	Looks.Fill(oldS)
	check("old save -> built (Fill)", oldS.face.style == "built")
	check("old save -> built (Sanitize)", Looks.Sanitize({ face = {} }, { gender = 1, face = { key = "cool" } }).face.style == "built")
	check("Sanitize keeps a drawn style", Looks.Sanitize({ face = { style = "wcb_smirk" } }, saved).face.style == "wcb_smirk")
	local savedS = Looks.Defaults(1)
	savedS.face.style = "wcb_grit"
	check("Sanitize: no style in the input keeps the saved one", Looks.Sanitize({ face = { key = "wink" } }, savedS).face.style == "wcb_grit")
	check("Sanitize: junk style keeps the saved one", Looks.Sanitize({ face = { style = "ko" } }, savedS).face.style == "wcb_grit")
	check("Sanitize: built chosen again", Looks.Sanitize({ face = { style = "built" } }, savedS).face.style == "built")
	check("Sanitize round trip", Looks.Sanitize(Looks.Sanitize({ face = { style = "wcb_focused" } })).face.style == "wcb_focused")
	local npcBuilt = true
	for seed = 1, 30 do
		npcBuilt = npcBuilt and Looks.Random(seed * 131, 1).face.style == "built"
	end
	check("NPCs keep the built face", npcBuilt)
end

------------------------------------------------------------------------
-- BuilderTiers: the swap on a fake rig
------------------------------------------------------------------------
local BuilderTiers = H.require("BuilderTiers")

-- a fake R15 rig at the description's scale: every part a default part (OriginalSize = the block rig's, Size =
-- that x scale), its rig attachments (with OriginalPosition), the Motor6Ds; the Humanoid's ReplaceBodyPartR15 in
-- one of two modes: "keep" (the given part as is) or "engine" (scaled from its OriginalSize x the humanoid scale)
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

local function newRig(scale, mode)
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
		p.Color = roblox.Color3.new(1, 1, 1)
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
	local function motors()
		for jn, pp in pairs(JOINTS) do
			local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
			local m = p1:FindFirstChild(jn)
			if not m then
				m = E.new("Motor6D", p1)
				m.Name = jn
			end
			m.Part0, m.Part1 = p0, p1
			m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
			m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		end
	end
	motors()
	local hum = E.new("Humanoid", model)
	hum.HipHeight = 2
	local calls = { n = 0 }
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		calls.n += 1
		local name = enum.Name
		local old = model:FindFirstChild(name)
		if mode == "engine" then
			local o = part:FindFirstChild("OriginalSize")
			part.Size = o.Value * scale
			for _, a in ipairs(part:GetChildren()) do
				if a:IsA("Attachment") then
					local op = a:FindFirstChild("OriginalPosition")
					if op then
						a.Position = op.Value * scale -- (the engine keeps the attachment's orientation)
					end
				end
			end
		end
		-- the motors move over to the new part (their C0 / C1 left for the caller to check)
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
		return true
	end
	return model, hum, calls
end

-- a fake AssetService: CreateMeshPartAsync -> a MeshPart (Size = the mesh bbox as the engine sets it), or an error
local function fakeAssets(failIds)
	local AS = { calls = 0 }
	function AS.CreateMeshPartAsync(_, content, _opts)
		AS.calls += 1
		local id = tonumber(tostring(content):match("(%d+)$"))
		if failIds and failIds[id] then
			error("HTTP 403 (Forbidden)")
		end
		local mp = E.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. id
		return mp
	end
	return AS
end
local Content = { fromUri = function(u)
	return u
end }

local function joinedOK(model)
	local bad = {}
	for jn, pp in pairs(JOINTS) do
		local p1 = model:FindFirstChild(pp[2])
		local m = p1 and p1:FindFirstChild(jn)
		local p0 = model:FindFirstChild(pp[1])
		if not (m and m.Part0 == p0 and m.Part1 == p1) then
			table.insert(bad, jn .. "(parts)")
		else
			local a0, a1 = p0:FindFirstChild(jn .. "RigAttachment"), p1:FindFirstChild(jn .. "RigAttachment")
			if not (a0 and a1 and vnear(m.C0.Position, a0.CFrame.Position) and vnear(m.C1.Position, a1.CFrame.Position)) then
				table.insert(bad, jn)
			end
		end
	end
	return #bad == 0, table.concat(bad, ",")
end

for _, mode in ipairs({ "keep", "engine" }) do
	BodyTiers.SetData(REAL)
	BuilderTiers.Reset()
	local AS = fakeAssets()
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	local scale = Vector3.new(0.92, 1.05, 0.94)
	local model, hum, calls = newRig(scale, mode)
	-- a cosmetic welded to the upper torso (a robe, a damage mark): must follow the swap
	local robe = E.new("Part", model)
	local w = E.new("WeldConstraint", robe)
	w.Part0, w.Part1 = model:FindFirstChild("UpperTorso"), robe
	local tiers = BodyTiers.Tiers(build(50), { potential = 0.95 })
	local n, key = BuilderTiers.Apply(model, tiers, scale)
	check(mode .. ": 14 parts swapped", n == 14 and calls.n == 14, n)
	check(mode .. ": key = tier 3 everywhere", key == string.rep("3", 14), key)
	check(mode .. ": BodyTiers attribute", model:GetAttribute("BodyTiers") == key)
	local ut = model:FindFirstChild("UpperTorso")
	local e = BodyTiers.PartEntry(3, "UpperTorso", REAL)
	check(mode .. ": the new part is the tier mesh", ut:GetAttribute("BodyTier") == 3 and ut:GetAttribute("BodyMesh") == e.id)
	check(mode .. ": scaled once: Size = OriginalSize x the default part's ratio", vnear(ut.Size, v3(e.size) * scale, 1e-3), tostring(ut.Size))
	check(mode .. ": OriginalSize = the mesh bbox", vnear(ut:FindFirstChild("OriginalSize").Value, v3(e.size)))
	local na = ut:FindFirstChild("NeckRigAttachment")
	check(mode .. ": attachments scaled once", na and vnear(na.Position, v3(e.attachments.NeckRigAttachment) * scale), na and tostring(na.Position))
	check(mode .. ": accessory attachments added", ut:FindFirstChild("BodyFrontAttachment") ~= nil and ut:FindFirstChild("NeckAttachment") ~= nil)
	local grip = model:FindFirstChild("RightHand"):FindFirstChild("RightGripAttachment")
	check(mode .. ": grip turned down the fist", grip ~= nil and vnear(grip.CFrame.UpVector, Vector3.new(0, 0, -1), 1e-3), grip and tostring(grip.CFrame.UpVector))
	local ok, why = joinedOK(model)
	check(mode .. ": every joint aimed at its attachments", ok, why)
	check(mode .. ": the robe's weld moved to the new torso", w.Part0 == ut, tostring(w.Part0))
	-- HipHeight from the legs: root -> hips -> knees -> ankles -> soles (R15: height = HipHeight + root / 2)
	local hh = BuilderTiers.HipHeight(model)
	local U = REAL.unit
	local expect = (U.rootHeight * scale.Y) - model:FindFirstChild("HumanoidRootPart").Size.Y / 2
	check(mode .. ": HipHeight set from the tier legs", near(hum.HipHeight, hh, 1e-6) and near(hh, expect, 0.06), string.format("%.3f vs %.3f", hh, expect))
	check(mode .. ": colour copied from the default part", ut.Color == roblox.Color3.new(1, 1, 1))
	-- change-only: the same tiers again swap nothing, load nothing
	local loads = AS.calls
	n = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 0.95 }, BuilderTiers.Current(model)), scale)
	check(mode .. ": same tiers -> no swap", n == 0 and calls.n == 14 and AS.calls == loads, n)
	-- one group trains past the band: only its parts swap; templates are cached per (tier, part)
	local b = build(50)
	b.forearms = 90
	n = BuilderTiers.Apply(model, BodyTiers.Tiers(b, { potential = 0.95 }, BuilderTiers.Current(model)), scale)
	check(mode .. ": forearms -> 4 parts swapped (lower arms + hands)", n == 4, n)
	check(mode .. ": a hand is tier 5", model:FindFirstChild("LeftHand"):GetAttribute("BodyTier") == 5)
	check(mode .. ": a second rig reuses the templates", (function()
		local before = AS.calls
		local m2 = newRig(scale, mode)
		BuilderTiers.Apply(m2, tiers, scale)
		return AS.calls == before
	end)())
	ok, why = joinedOK(model)
	check(mode .. ": joints still aimed after the second swap", ok, why)
end

-- a failed load: the default part stays, the failure is cached (no retry within RETRY)
do
	BodyTiers.SetData(REAL)
	BuilderTiers.Reset()
	local failIds = {}
	local e = BodyTiers.PartEntry(2, "UpperTorso", REAL)
	failIds[e.id] = true
	local AS = fakeAssets(failIds)
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	local scale = Vector3.new(1, 1, 1)
	local model, _, calls = newRig(scale, "engine")
	local ut0 = model:FindFirstChild("UpperTorso")
	local n = BuilderTiers.Apply(model, BodyTiers.Tiers(build(28), { potential = 0.95 }), scale)
	check("failure: 13 of 14 swapped", n == 13 and calls.n == 13, n)
	check("failure: the default UpperTorso kept", model:FindFirstChild("UpperTorso") == ut0 and ut0:GetAttribute("BodyTier") == nil)
	check("failure: key shows the default part (0)", model:GetAttribute("BodyTiers"):sub(1, 1) == "0", model:GetAttribute("BodyTiers"))
	local ok, why = joinedOK(model)
	check("failure: the rig stays joined", ok, why)
	local before = AS.calls
	BuilderTiers.Apply(model, BodyTiers.Tiers(build(28), { potential = 0.95 }), scale)
	check("failure: not retried at once", AS.calls == before, AS.calls - before)
	check("failure: counted", BuilderTiers.Stats().failed == 1)
end

-- every id 0: nothing loaded, nothing swapped, the default body
do
	local zero = { tiers = {} }
	for t = 1, 5 do
		local parts = {}
		for _, n in ipairs(BodyTiers.PARTS) do
			local e = REAL.tiers[t].parts[n]
			parts[n] = { mesh = 0, size = e.size, attachments = e.attachments }
		end
		zero.tiers[t] = { parts = parts }
	end
	BodyTiers.SetData(zero)
	BuilderTiers.Reset()
	local AS = fakeAssets()
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	local model, hum, calls = newRig(Vector3.new(1, 1, 1), "engine")
	local n, key = BuilderTiers.Apply(model, BodyTiers.Tiers(build(60), { potential = 0.95 }), Vector3.new(1, 1, 1))
	check("ids 0: nothing swapped or loaded", n == 0 and calls.n == 0 and AS.calls == 0)
	check("ids 0: key all default", key == string.rep("0", 14), key)
	check("ids 0: HipHeight left to the engine", hum.HipHeight == 2, hum.HipHeight)
	BodyTiers.SetData(REAL)
end

------------------------------------------------------------------------
-- the asset hair on the classic head
------------------------------------------------------------------------
do
	local HK = H.require("HairAssetKit")
	local Kit = H.require("AnatomyHairKit")
	local Data = H.require("HairAssetData")
	local lk = H.Look({ g = 1, headShape = "classic" })
	local S = Kit.Scalp(lk)
	check("classic scalp flagged", S.classic == true)
	local W, T, Fz, Bz = HK.Measure(S)
	check("classic head extents 0.6", near(W, 0.6, 0.002) and near(T, 0.6, 0.002) and near(Fz, -0.6, 0.002) and near(Bz, 0.6, 0.002))
	local worstCap, worstCard = math.huge, math.huge
	for _, e in ipairs(Data.entries) do
		local l = H.Look({ g = 1, headShape = "classic", hair = { style = e.styles[1], type = (e.types and e.types[1]) or "Straight" } })
		local Sx = Kit.Scalp(l)
		local placed = HK.Place(Data, e, l, Sx)
		for name, pl in pairs(placed) do
			local d = {}
			for i = 1, #pl.P - 2, 3 do
				table.insert(d, Sx.f(pl.P[i] / Sx.kx, pl.P[i + 1] / Sx.ky, pl.P[i + 2] / Sx.kz))
			end
			table.sort(d)
			if name == "HairCap" then
				worstCap = math.min(worstCap, d[math.max(1, math.floor(#d * 0.02))])
			else
				worstCard = math.min(worstCard, d[math.max(1, math.floor(#d * 0.1))])
			end
		end
	end
	-- (v7 meshes: HK.CLASSIC_FIT on the organic fit0; v9 meshes, modelled on the classic head: a classic fit0, the
	-- cap 0.02 above the head)
	local v9 = type(Data.fit0) == "table" and Data.fit0.shape == "classic"
	check("classic: cap's 2nd percentile within 0.025 of the head" .. (v9 and " (v9 classic fit0)" or " (HK.CLASSIC_FIT)"),
		worstCap > (v9 and 0.01 or -0.025), worstCap)
	check("classic: cards' 10th percentile outside the head", worstCard > 0, worstCard)
	-- the organic skull keeps its identity fit against the organic fit0 (the old looks / tests)
	local f0 = HK.Fit(Kit.Scalp(H.Look({ g = 1 })), HK.FIT0)
	check("organic fit untouched", near(f0.ax, 1, 0.006) and f0.dy == 0)
	-- a classic fit0 on the classic head: the identity, nothing on top
	local fc = HK.Fit(S, HK.FIT0_CLASSIC)
	check("classic fit0: identity on the classic head", near(fc.ax, 1, 0.003) and near(fc.ay, 1, 0.003) and near(fc.az, 1, 0.003)
		and near(fc.dz, 0, 0.002) and fc.dy == 0 and fc.shape == "classic")
end

------------------------------------------------------------------------
-- Builder: the description's scales (BodyTypeScale 0, the frame and the height only; training never widens)
------------------------------------------------------------------------
do
	local Builder = H.require("Builder")
	local Looks = H.require("Looks")
	local man = Looks.Defaults(1)
	local sc = Builder.Scales(man, build(8))
	check("Athletic 70-inch man: 1 / 1 / 1, head 0.7724, BodyType 0", near(sc.height, 1) and near(sc.width, 1) and near(sc.depth, 1)
		and near(sc.head, 0.7724, 1e-4) and sc.bodyType == 0 and sc.proportion == 0,
		string.format("%.3f %.3f %.3f %.4f", sc.height, sc.width, sc.depth, sc.head))
	local trained = Builder.Scales(man, build(95))
	check("training never widens the frame", near(trained.width, sc.width) and near(trained.depth, sc.depth))
	check("ScaleKey p3 and training-independent", Builder.ScaleKey(man, build(8)) == Builder.ScaleKey(man, build(95))
		and Builder.ScaleKey(man, build(8)):sub(-2) == "p3")
	local woman = Looks.Defaults(2)
	local ws = Builder.Scales(woman, build(8))
	check("women: narrower shoulders, smaller head", near(ws.width, 0.92) and near(ws.depth, 0.94) and near(ws.head, 0.7724 * 0.97, 1e-4))
	man.body.frame = "Heavyweight Build"
	local hs = Builder.Scales(man, build(8))
	check("Heavyweight frame: wider and deeper, bigger head", near(hs.width, 1.18) and near(hs.depth, 1.14) and near(hs.head, 0.85 * 0.942, 1e-4))
	man.height = 76
	check("height scales with inches / 70", near(Builder.Scales(man, build(8)).height, 76 / 70))
	check("Builder.Tiers", Builder.Tiers(Looks.Defaults(1), build(95)).UpperTorso == 5)
end

------------------------------------------------------------------------
-- Builder.Cosmetics on the fake rig: the tiers, the classic head and its decal, the gear on the tier parts
------------------------------------------------------------------------
do
	local Builder = H.require("Builder")
	local Looks = H.require("Looks")
	BodyTiers.SetData(REAL)
	BuilderTiers.Reset()
	BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
	local model, hum = newRig(Vector3.new(1, 1, 1), "keep")
	local head = E.new("MeshPart", model)
	head.Name = "Head"
	head.Size = Vector3.new(0.927, 0.927, 0.927)
	local na = E.new("Attachment", head)
	na.Name = "NeckRigAttachment"
	na.Position = Vector3.new(0, -0.6, 0)
	local neck = E.new("Motor6D", head)
	neck.Name = "Neck"
	neck.Part0, neck.Part1 = model:FindFirstChild("UpperTorso"), head
	neck.C0, neck.C1 = CFrame.new(0, 0.8, 0), CFrame.new(0, -0.6, 0)
	hum.ReplaceBodyPartR15 = (function(inner)
		return function(self, enum, part)
			if enum.Name == "Head" then
				local old = model:FindFirstChild("Head")
				neck.Part1 = part
				neck.Parent = part
				part.Parent = model
				old:Destroy()
				return true
			end
			return inner(self, enum, part)
		end
	end)(hum.ReplaceBodyPartR15)
	local app = Looks.Defaults(1)
	app.face.key = "cool"
	local ok, err = pcall(Builder.Cosmetics, model, app, build(60), nil, { hands = "gloves" })
	local ok2, err2 = pcall(Builder.Cosmetics, model, app, build(60), nil, { hands = "wraps" })
	check("Cosmetics runs", ok and ok2, tostring(err) .. " " .. tostring(err2))
	local h = model:FindFirstChild("Head")
	local decal = h and h:FindFirstChild("face")
	check("classic head swapped in", h and h.ClassName == "Part" and h:FindFirstChildOfClass("SpecialMesh") ~= nil)
	check("no decal face: the built face", decal == nil and h and h:FindFirstChildOfClass("Decal") == nil)
	check("no FaceKey attribute", model:GetAttribute("FaceKey") == nil)
	check("head seated on the neck pivot", h and near(h:FindFirstChild("NeckRigAttachment").Position.Y, -0.5 * h.Size.Y, 1e-4))
	check("tier 4 body (60)", model:GetAttribute("BodyTiers") == string.rep("4", 14), model:GetAttribute("BodyTiers"))
	local look = model:FindFirstChild("BoxerLook")
	local hands = look and look:FindFirstChild("Hands")
	local wrapWrist = hands and hands:FindFirstChild("WrapWrist")
	local la = model:FindFirstChild("LeftLowerArm")
	local wa = la:FindFirstChild("LeftWristRigAttachment")
	check("wraps follow the tier wrist joint", wrapWrist ~= nil and (function()
		-- the left wrap's centre is 0.14 x the forearm above its wrist joint
		for _, p in ipairs(hands:GetChildren()) do
			if p.Name == "WrapWrist" and (p.Position - (la.CFrame * CFrame.new(wa.Position)).Position).Magnitude < 0.3 then
				return true
			end
		end
		return false
	end)())
	check("lower torso has the waistband over the waist", look and look:FindFirstChild("Attire") and look.Attire:FindFirstChild("Waistband") ~= nil)
	check("no round-1 muscles", look and look:FindFirstChild("Muscles") == nil)
	local ld = model:GetAttribute("LookData")
	check("LookData says classic head", type(ld) == "string" and ld:find('"headShape":"classic"', 1, true) ~= nil)
end


------------------------------------------------------------------------
-- The built face: rig, budget, FaceFX, workouts and damage
------------------------------------------------------------------------
do
	local Builder = H.require("Builder")
	local Looks = H.require("Looks")
	BodyTiers.SetData(REAL)
	local function rigWithHead()
		BuilderTiers.Reset()
		BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
		local model, hum = newRig(Vector3.new(1, 1, 1), "keep")
		local head = E.new("MeshPart", model)
		head.Name = "Head"
		head.Size = Vector3.new(0.927, 0.927, 0.927)
		head.CFrame = CFrame.new(0, 6, 0)
		local na = E.new("Attachment", head)
		na.Name = "NeckRigAttachment"
		na.Position = Vector3.new(0, -0.46, 0)
		local neck = E.new("Motor6D", head)
		neck.Name = "Neck"
		neck.Part0, neck.Part1 = model:FindFirstChild("UpperTorso"), head
		neck.C0, neck.C1 = CFrame.new(0, 0.8, 0), CFrame.new(0, -0.46, 0)
		hum.ReplaceBodyPartR15 = (function(inner)
			return function(self, enum, part)
				if enum.Name == "Head" then
					local old = model:FindFirstChild("Head")
					neck.Part1 = part
					neck.Parent = part
					part.Parent = model
					old:Destroy()
					return true
				end
				return inner(self, enum, part)
			end
		end)(hum.ReplaceBodyPartR15)
		return model
	end
	local function faceParts(model)
		local look = model:FindFirstChild("BoxerLook")
		local f = look and look:FindFirstChild("Face")
		local n, roles = 0, {}
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				n += 1
			elseif d.ClassName == "Motor6D" and d.Name == "FaceJoint" then
				roles[d:GetAttribute("Role")] = d
			end
		end
		return n, roles, f
	end
	local app = Looks.Defaults(1)
	app.face.shape = "Square"
	app.face.jawWidth = 0.5
	local counts = {}
	for _, detail in ipairs({ "full", "medium", "low" }) do
		local model = rigWithHead()
		local ok, err = pcall(Builder.Cosmetics, model, app, build(30), nil, { hands = "gloves", detail = detail })
		check("built face (" .. detail .. ") builds", ok, err)
		local n, roles, f = faceParts(model)
		counts[detail] = n
		check("built face (" .. detail .. "): Extra within A's cap", f and (f:GetAttribute("Extra") or 99) <= ({ full = 38, medium = 6, low = -2 })[detail] + 0.5,
			f and f:GetAttribute("Extra"))
		if detail == "full" then
			for _, role in ipairs({ "EyeL", "EyeR", "BrowL", "BrowR", "LidL", "LidR", "LowerLidL", "LowerLidR", "UpperLip", "LowerLip", "MouthCornerL", "MouthCornerR", "MouthInside" }) do
				check("full rig role " .. role, roles[role] ~= nil)
			end
		elseif detail == "medium" then
			check("medium rig: eyes and brows only", roles.EyeL ~= nil and roles.BrowR ~= nil and roles.LidL == nil)
		else
			check("low: no rig", next(roles) == nil)
		end
		model:Destroy()
	end
	check("part count falls with detail", counts.full > counts.medium and counts.medium > counts.low, string.format("%d %d %d", counts.full, counts.medium, counts.low))

	-- FaceFX animates the rig: an expression moves the brows, a hit blinks
	local model = rigWithHead()
	model.Parent = E.workspace
	pcall(Builder.Cosmetics, model, app, build(30), nil, { hands = "gloves", detail = "full" })
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "SpecialMesh" then
			d.Scale = d.Scale or Vector3.new(1, 1, 1)
			d.Offset = d.Offset or Vector3.zero
		end
	end
	local FaceFX = H.require("FaceFX")
	local _, roles = faceParts(model)
	local head = model:FindFirstChild("Head")
	local cam = head.Position + Vector3.new(0, 0, -3)
	model:SetAttribute("Expr", "anger")
	for i = 1, 40 do
		FaceFX.Update(1 / 30, i / 30, cam, nil, 99)
	end
	local dbg = FaceFX.Debug(model)
	check("FaceFX tracks the rig", dbg ~= nil and dbg.roles and dbg.active, dbg and dbg.roleCount)
	local bt = roles.BrowL and roles.BrowL.Transform
	check("anger moves the brows", bt ~= nil and (bt.Position.Magnitude > 1e-4 or bt.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.99999), bt)
	local lip = roles.UpperLip and roles.UpperLip.Transform
	check("anger lifts the upper lip (snarl)", lip ~= nil and lip.Position.Y > 0, lip and lip.Position)
	FaceFX.Hit(model, 1)
	FaceFX.Update(1 / 30, 2, cam, nil, 99)
	FaceFX.Update(1 / 30, 2.03, cam, nil, 99)
	local blinked = false
	for i = 1, 6 do
		task.wait(0.02)
		FaceFX.Update(1 / 30, 2.05 + i / 30, cam, nil, 99)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "BlinkLid" and d.Transparency < 1 then
				blinked = true
			end
		end
	end
	check("a hit squeezes the eyes shut (BlinkLid shown)", blinked)

	-- after a workout: road grime, a tier-up rebuild (applyLook), the session's sweat: the face stays a face
	local DARK_OK = { Pupil = true, Lashes = true, Brow = true, BrowInner = true, BrowOuter = true, Nostril = true, MouthLine = true,
		MouthInside = true, Limbal = true, Iris = true, MouthCorner = true }
	local function lumOf(c)
		return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	end
	local function darkOverSkin(m)
		local bad = {}
		local look = m:FindFirstChild("BoxerLook")
		for _, fname in ipairs({ "Face", "FaceSweat", "FaceGrime", "Damage", "Beard" }) do
			local f = look and look:FindFirstChild(fname)
			for _, p in ipairs(f and f:GetDescendants() or {}) do
				if p:IsA("BasePart") and p.Transparency < 0.6 and not DARK_OK[p.Name] and lumOf(p.Color) < 0.12 then
					table.insert(bad, fname .. "/" .. p.Name)
				end
			end
		end
		return bad
	end
	local skin0 = head.Color
	model:SetAttribute("Grime", 0.8)
	pcall(Builder.Cosmetics, model, app, build(60), nil, { hands = "wraps", detail = "full" })
	Builder.SetSweat(model, app, 0.85)
	head = model:FindFirstChild("Head")
	check("workout: the head keeps its skin colour", head.Color == skin0)
	check("workout: the head's sheen stays subtle", head.Reflectance <= 0.08 + 1e-6, head.Reflectance)
	check("workout: no decal on the head", head:FindFirstChildOfClass("Decal") == nil)
	local bad = darkOverSkin(model)
	check("workout: nothing near-black over the skin", #bad == 0, table.concat(bad, ", "))
	local n = faceParts(model)
	check("workout: the face is still built", n > 30, n)
	-- the damage presets (the Creator's): black eyes are translucent and lie behind the eye's own parts
	local severe = { leftEye = 1, rightEye = 0.85, cut = 1.1, cutSide = -1, cut2 = 0.6, bruise = 0.9, lip = 1, noseBleed = 1, nose = true, cheekL = 1, cheekR = 0.7, forehead = 0.8, earL = 0.6 }
	Builder.SetDamage(model, app, severe)
	local look = model:FindFirstChild("BoxerLook")
	local dmgF = look and look:FindFirstChild("Damage")
	-- the classic head's surface (AnatomyHairKit.CLASSIC, scaled to the head): signed distance, < 0 inside
	local HK = H.require("AnatomyHairKit")
	local function sdHead(hd, wp)
		local lp = hd.CFrame:PointToObjectSpace(wp)
		local k = hd.Size.X / 1.2
		return HK.ClassicField(lp.X / k, lp.Y / k, lp.Z / k) * k
	end
	-- a part's innermost and outermost points along its own Z (the built face's parts: -Z out of the skin)
	-- (the lines laid along the skin, BuilderHead surfaceLine, have the normal on their Y)
	local LINES = { Nasolabial = true, LipFold = true, ForeheadLine = true, CrowFeet = true, TempleVein = true, ForeheadVein = true,
		BattleScar = true, SurgicalScar = true, Suture = true }
	local function standOff(hd, p)
		local lv = LINES[p.Name] and p.CFrame.UpVector * (p.Size.Y / 2) or p.CFrame.LookVector * (p.Size.Z / 2)
		return sdHead(hd, p.Position - lv), sdHead(hd, p.Position + lv)
	end
	local be, beOk = 0, true
	for _, p in ipairs(dmgF and dmgF:GetChildren() or {}) do
		if p.Name == "BlackEye" or p.Name == "BlackEyeLow" then
			be += 1
			local inner, outer = standOff(head, p)
			beOk = beOk and p.Transparency >= 0.3 and inner < 0 and outer < 0.012
		end
	end
	check("severe: black eyes on both sides, translucent, lying on the skin", be == 4 and beOk, be)
	-- every face / damage part hugs the head: it reaches into the skin (nothing floats) and stands at most a nose's
	-- height off it (the parts hung under the jaw and the ears' cauliflower lumps aside)
	local loose = {}
	local HANG = { Jowl = true, DoubleChin = true, LowerFace = true, Cauliflower = true, EyeBall = true, DamageAnchor = true }
	for _, fname in ipairs({ "Face", "Damage" }) do
		for _, p in ipairs(look[fname] and look[fname]:GetDescendants() or {}) do
			if p:IsA("BasePart") and not HANG[p.Name] and p.Parent and p.Parent.Name ~= "UpperTorso" and p.Name ~= "BloodChest" then
				local inner, outer = standOff(head, p)
				if inner > 0.002 or outer > 0.065 then
					table.insert(loose, string.format("%s/%s %.3f %.3f", fname, p.Name, inner, outer))
				end
			end
		end
	end
	check("severe: every face and damage part lies on the head", #loose == 0, table.concat(loose, ", "))
	check("BuilderHead's classic head is AnatomyHairKit.CLASSIC", (function()
		local a, b = H.require("BuilderHead").CLASSIC, HK.CLASSIC
		return a.r == b.r and a.h == b.h and a.round == b.round
	end)())
	check("severe: no ball over the eyes (SwollenEye retired)", dmgF and dmgF:FindFirstChild("SwollenEye") == nil)
	bad = darkOverSkin(model)
	check("severe: nothing near-black over the skin", #bad == 0, table.concat(bad, ", "))
	local lidDark
	for _, p in ipairs(look.Face:GetChildren()) do
		if p.Name == "Lid" then
			lidDark = lidDark or (p.Transparency >= 1 or p.Color ~= p:GetAttribute("BaseColor"))
		end
	end
	check("severe: the lids swell shut / take the bruise", lidDark == true)
	Builder.SetDamage(model, app, {})
	local healed = true
	for _, p in ipairs(look.Face:GetChildren()) do
		if p.Name == "Lid" then
			healed = healed and p.Transparency == 0 and p.Color == p:GetAttribute("BaseColor")
		end
	end
	check("healed: the lids are back", healed)
	check("healed: no damage marks", #look.Damage:GetChildren() == 0)
	Builder.SetSweat(model, app, 0)
	check("dry: no face sweat folder", look:FindFirstChild("FaceSweat") == nil)
	model:Destroy()

	-- every creator slider and option still changes the built face (its min against its max; every option value
	-- against the default): a signature of every face part (name, place, size, colour, transparency) and the skin
	local function sig(a)
		local m = rigWithHead()
		pcall(Builder.Cosmetics, m, a, build(30), nil, { hands = "gloves", detail = "full" })
		local hd = m:FindFirstChild("Head")
		local f = m:FindFirstChild("BoxerLook") and m.BoxerLook:FindFirstChild("Face")
		local out = { tostring(hd.Material), string.format("%.4f", hd.Reflectance) }
		for _, p in ipairs(f and f:GetDescendants() or {}) do
			if p:IsA("BasePart") then
				local lp = hd.CFrame:PointToObjectSpace(p.Position)
				table.insert(out, string.format("%s %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %.2f", p.Name, lp.X, lp.Y, lp.Z, p.Size.X, p.Size.Y, p.Size.Z,
					p.Color.R, p.Color.G, p.Color.B, p.Transparency))
			end
		end
		m:Destroy()
		table.sort(out)
		return table.concat(out, "|")
	end
	local base = Looks.Defaults(1)
	local dead = {}
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders, Looks.WearSliders }) do
		for _, sl in ipairs(list) do
			local lo, hi = table.clone(base), table.clone(base)
			lo.face, hi.face = table.clone(base.face), table.clone(base.face)
			lo.face[sl.key], hi.face[sl.key] = sl.min, sl.max
			if sig(lo) == sig(hi) then
				table.insert(dead, sl.key)
			end
		end
	end
	local d0 = sig(base)
	for _, opt in ipairs({ { "shape", Looks.FaceShapes }, { "browStyle", Looks.BrowStyles }, { "undertone", Looks.Undertones } }) do
		for _, v in ipairs(opt[2]) do
			if v ~= base.face[opt[1]] then
				local a = table.clone(base)
				a.face = table.clone(base.face)
				a.face[opt[1]] = v
				if sig(a) == d0 then
					table.insert(dead, opt[1] .. "=" .. v)
				end
			end
		end
	end
	for _, ec in ipairs({ { "eyeColor", 5 }, { "eyeColor2", 4 } }) do
		local a = table.clone(base)
		a.face = table.clone(base.face)
		a.face[ec[1]] = ec[2]
		if sig(a) == d0 then
			table.insert(dead, ec[1])
		end
	end
	check("every face slider / option changes the built face", #dead == 0, table.concat(dead, ", "))

	------------------------------------------------------------------------
	-- face styles: a drawn Boxer face (decal mode)
	------------------------------------------------------------------------
	local Head = H.require("BuilderHead")
	local BUILT_PARTS = { Sclera = true, Limbal = true, Iris = true, Pupil = true, Glint = true, EyeBall = true, Lid = true, Lashes = true,
		LowerLid = true, BlinkLid = true, Crease = true, UnderEye = true, Brow = true, BrowInner = true, BrowOuter = true, BrowRidge = true,
		BrowGap = true, Nose = true, NoseTip = true, NoseWing = true, Nostril = true, NoseBump = true, Nasolabial = true, UpperLip = true,
		LowerLip = true, MouthLine = true, MouthCorner = true, MouthInside = true, TeethUpper = true, TeethLower = true, Philtrum = true,
		LipFold = true, Mouthguard = true }
	local function decals(hd)
		local out = {}
		for _, d in ipairs(hd:GetChildren()) do
			if d:IsA("Decal") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function builtLeft(m)
		local f = m:FindFirstChild("BoxerLook") and m.BoxerLook:FindFirstChild("Face")
		local out, ears = {}, 0
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") and BUILT_PARTS[d.Name] then
				table.insert(out, d.Name)
			elseif d:IsA("BasePart") and d.Name == "Ear" then
				ears += 1
			elseif d.ClassName == "Motor6D" and d.Name == "FaceJoint" then
				table.insert(out, "FaceJoint")
			end
		end
		return out, ears
	end
	local dapp = Looks.Defaults(1)
	dapp.face.style = "wcb_smirk"
	dapp.face.freckles, dapp.face.moles, dapp.face.scars, dapp.face.acne = 1, 3, 2, 0.6
	local smirkTex = "rbxassetid://" .. BodyTiers.Face("wcb_smirk", REAL).id
	for _, detail in ipairs({ "full", "medium", "low" }) do
		local m = rigWithHead()
		local okD, errD = pcall(Builder.Cosmetics, m, dapp, build(30), nil, { hands = "gloves", detail = detail, mouthguard = true })
		check("decal mode (" .. detail .. ") builds", okD, errD)
		local hd = m:FindFirstChild("Head")
		local ds = decals(hd)
		local dec = ds[1]
		check("decal mode (" .. detail .. "): exactly one face decal, front, white, opaque, the chosen face", #ds == 1 and dec.Name == "face"
			and dec.Face == roblox.Enum.NormalId.Front and dec.Color3 == roblox.Color3.new(1, 1, 1) and dec.Transparency == 0 and dec.Texture == smirkTex,
			#ds .. " " .. tostring(dec and dec.Texture))
		local left, ears = builtLeft(m)
		check("decal mode (" .. detail .. "): no built eye / brow / nose / lip parts or rig", #left == 0, table.concat(left, ","))
		check("decal mode (" .. detail .. "): ears kept", ears == 2, ears)
		check("decal mode (" .. detail .. "): Face folder records the style", Head.FaceStyle(m) == "wcb_smirk")
		if detail == "full" then
			-- skin spots keep off the drawn ink
			local L = Head.DecalLayout(Head.FaceLayout(hd, dapp.face))
			local onInk = {}
			for _, p in ipairs(m.BoxerLook.Face:GetDescendants()) do
				if p:IsA("BasePart") and (p.Name == "Freckle" or p.Name == "Mole" or p.Name == "Acne" or p.Name == "AcneScar" or p.Name == "Scar" or p.Name == "Pore") then
					local lp = hd.CFrame:PointToObjectSpace(p.Position)
					if Head.DecalInkHit(L, lp.X, lp.Y, 0, 0) then
						table.insert(onInk, p.Name)
					end
				end
			end
			check("decal mode: skin spots keep off the drawn ink", #onInk == 0, table.concat(onInk, ","))
		end
		m:Destroy()
	end
	-- damage, sweat and grime on the drawn face; cache and restore; FaceFX; back to built
	local dm = rigWithHead()
	dm.Parent = E.workspace
	dm:SetAttribute("Grime", 0.8)
	pcall(Builder.Cosmetics, dm, dapp, build(30), nil, { hands = "gloves", detail = "full" })
	local dh = dm:FindFirstChild("Head")
	Builder.SetSweat(dm, dapp, 0.85)
	Builder.SetDamage(dm, dapp, severe)
	local dlook = dm:FindFirstChild("BoxerLook")
	local dk = dh.Size
	local eyeMarks, eyeOk, swollen = 0, true, 0
	for _, p in ipairs(dlook.Damage:GetChildren()) do
		local lp = dh.CFrame:PointToObjectSpace(p.Position)
		if p.Name == "BlackEye" then
			eyeMarks += 1
			-- over the drawn eye (x +-0.145, y +0.0415 of the head): the patch's centre within its own size of it
			eyeOk = eyeOk and math.abs(math.abs(lp.X) - 0.145 * dk.X) < 0.02 * dk.X and math.abs(lp.Y - 0.0415 * dk.Y) < 0.015 * dk.Y
		elseif p.Name == "SwollenLid" then
			swollen += 1
		end
	end
	check("decal damage: black eyes over the drawn eyes", eyeMarks == 2 and eyeOk, eyeMarks)
	check("decal damage: the swollen lids fall back to surface patches", swollen == 2, swollen)
	local dloose = {}
	for _, fname in ipairs({ "Face", "Damage", "FaceSweat", "FaceGrime" }) do
		for _, p in ipairs(dlook[fname] and dlook[fname]:GetDescendants() or {}) do
			if p:IsA("BasePart") and not HANG[p.Name] and p.Name ~= "BloodChest" and p.Name ~= "SweatAnchor" then
				local inner, outer = standOff(dh, p)
				if inner > 0.002 or outer > 0.065 then
					table.insert(dloose, string.format("%s/%s %.3f %.3f", fname, p.Name, inner, outer))
				end
			end
		end
	end
	check("decal damage / sweat / grime lie on the head", #dloose == 0, table.concat(dloose, ", "))
	check("decal damage: nothing near-black over the skin", #darkOverSkin(dm) == 0, table.concat(darkOverSkin(dm), ", "))
	check("decal sweat and grime drawn", dlook:FindFirstChild("FaceSweat") ~= nil and dlook:FindFirstChild("FaceGrime") ~= nil)
	local beadsOnInk = 0
	local dL = Head.DecalLayout(Head.FaceLayout(dh, dapp.face))
	for _, p in ipairs(dlook.FaceSweat:GetChildren()) do
		local lp = dh.CFrame:PointToObjectSpace(p.Position)
		if p.Name == "SweatBead" and Head.DecalInkHit(dL, lp.X, lp.Y, 0, 0) then
			beadsOnInk += 1
		end
	end
	check("decal sweat: no bead on the drawn ink", beadsOnInk == 0, beadsOnInk)
	check("decal damage: still one decal", #decals(dh) == 1)
	-- served from cache: the same look again keeps the folder and the one decal; a lost decal comes back
	local sig0 = dlook.Face:GetAttribute("Sig")
	pcall(Builder.Cosmetics, dm, dapp, build(30), nil, { hands = "gloves", detail = "full" })
	check("decal mode: cached rebuild keeps the face", dlook:FindFirstChild("Face") and dlook.Face:GetAttribute("Sig") == sig0 and #decals(dh) == 1)
	dh:FindFirstChild("face"):Destroy()
	local junk = E.new("Decal", dh)
	junk.Name = "face"
	junk.Texture = "rbxasset://textures/face.png"
	pcall(Builder.Cosmetics, dm, dapp, build(30), nil, { hands = "gloves", detail = "full" })
	local ds2 = decals(dh)
	check("decal mode: a replaced decal is restored from cache", #ds2 == 1 and ds2[1].Texture == smirkTex and ds2[1]:GetAttribute("FaceStyle") == "wcb_smirk",
		#ds2 .. " " .. tostring(ds2[1] and ds2[1].Texture))
	-- FaceFX: the four swap by mood; the chosen face at rest
	Builder.SetDamage(dm, dapp, {})
	local dcam = dh.Position + Vector3.new(0, 0, -3)
	local tclock = 0
	local function run(attrs)
		for k, v in pairs(attrs) do
			dm:SetAttribute(k, v)
		end
		task.wait(0.3) -- (the swap is held 0.25 s of real time)
		for _ = 1, 10 do
			tclock += 1 / 30
			FaceFX.Update(1 / 30, tclock, dcam, nil, 99)
		end
		local db = FaceFX.Debug(dm)
		return db and db.decal and db.decal.texture, db
	end
	local function tex(k)
		return "rbxassetid://" .. BodyTiers.Face(k, REAL).id
	end
	local t0, db0 = run({})
	check("FaceFX decal: tracked without a rig", db0 ~= nil and db0.decal ~= nil and not db0.roles, db0 and db0.roleCount)
	check("FaceFX decal: at rest the chosen face", t0 == tex("wcb_smirk"), t0)
	check("FaceFX decal: guard up -> focused", run({ Guard = "up" }) == tex("wcb_focused"))
	check("FaceFX decal: effort -> grit", run({ Expr = "effort" }) == tex("wcb_grit"))
	check("FaceFX decal: anger -> grit", run({ Expr = "anger" }) == tex("wcb_grit"))
	check("FaceFX decal: happy -> smirk", run({ Expr = "happy" }) == tex("wcb_smirk"))
	check("FaceFX decal: KO -> neutral", run({ Expr = "ko", Guard = "down" }) == tex("wcb_neutral"))
	dm:SetAttribute("Guard", nil) -- (out of the ring: no Guard attribute)
	check("FaceFX decal: back at rest -> the chosen face", run({ Expr = "neutral" }) == tex("wcb_smirk"))
	FaceFX.Hit(dm, 1)
	task.wait(0.06) -- (the pain layer's 0.05 s attack; the swap itself skips the hold)
	tclock += 1 / 30
	FaceFX.Update(1 / 30, tclock, dcam, nil, 99)
	check("FaceFX decal: a hit flashes grit at once", FaceFX.Debug(dm).decal.texture == tex("wcb_grit"))
	check("FaceFX decal: the server's texture is the chosen face", BodyTiers.FaceTexture(Head.FaceStyle(dm)) == tex("wcb_smirk"))
	-- back to the built face: the decal goes, the rig is back
	local bapp = table.clone(dapp)
	bapp.face = table.clone(dapp.face)
	bapp.face.style = "built"
	pcall(Builder.Cosmetics, dm, bapp, build(30), nil, { hands = "gloves", detail = "full" })
	local _, broles = faceParts(dm)
	check("built again: no decal, the built rig back", #decals(dm:FindFirstChild("Head")) == 0 and broles.EyeL ~= nil and broles.UpperLip ~= nil
		and Head.FaceStyle(dm) == nil)
	dm:Destroy()
	-- built mode is unchanged by the face style code: the same parts as a look with no style at all (an old save)
	local plain = Looks.Defaults(1)
	local nostyle = table.clone(plain)
	nostyle.face = table.clone(plain.face)
	nostyle.face.style = nil
	check("built mode: an old save (no style) builds the same face", sig(plain) == sig(nostyle))
end

print(string.format("test_bodytiers: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_bodytiers failed")
end
