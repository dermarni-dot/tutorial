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
--   * face styles (look.face.style): the drawn Boxer faces offered (no Built option) / sanitised / kept off face.key,
--     every boxer on a drawn face (new boxers, old and "built" saves -> Boxer Neutral, NPCs one of the four by seed),
--     the mood set; decal mode on the classic head (one white opaque front decal, no built eyes / brows / nose / lips
--     or rig, ears kept, damage / sweat / grime at the drawn features, the decal restored when served from cache),
--     FaceFX swapping the four by mood, a "built" look still on the drawn face, workouts / tier rebuilds keeping one
--     decal; no built face part on any player / NPC look; every face control the Creator shows changes the drawn face
--   * the built face on the classic head (BuilderHead, the v7 face; only the emergency fallback with no drawn face
--     uploaded, reached here through BodyTiers.SetData(NODRAWN)): no decal, the FaceFX rig, the part budget per
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
-- the real data with the drawn Boxer faces not uploaded (ids 0): the emergency fallback where the built face is
-- still built. The test-only path to the dormant built face (the game never has it while the pack is uploaded)
local NODRAWN = table.clone(REAL)
NODRAWN.faces = {}
for _, f in ipairs(REAL.faces or {}) do
	local c = table.clone(f)
	if BodyTiers.STYLE_INDEX[c.key] then
		c.id = 0
	end
	table.insert(NODRAWN.faces, c)
end

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
-- body frames (v12): every Config.BodyTypes frame has a mesh family of its own
------------------------------------------------------------------------
do
	local Config = H.require("Config")
	local ids = {}
	for _, bt in ipairs(Config.BodyTypes) do
		ids[bt.id] = bt
	end
	check("Config.BodyTypes: Lean, Muscular, Power Build and Heavyweight Build exist (and Athletic, the default family)",
		ids.Lean and ids.Muscular and ids["Power Build"] and ids["Heavyweight Build"] and ids.Athletic)
	-- the frame a Tiers() call is for: from the frame id, else from the potential Builder passes
	check("FrameOf: an explicit frame id", BodyTiers.FrameOf({ frame = "Lean", potential = 1.25 }) == "Lean")
	check("FrameOf: the BodyTypes entry with that potential", BodyTiers.FrameOf({ potential = ids["Power Build"].potential }) == "Power Build"
		and BodyTiers.FrameOf({ potential = 0.8 }) == "Lean" and BodyTiers.FrameOf({ potential = 0.95 }) == "Athletic")
	check("FrameOf: unknown -> the default family", BodyTiers.FrameOf({ potential = 0.123 }) == BodyTiers.DEFAULT_FRAME
		and BodyTiers.FrameOf(nil) == "Athletic")
	local t = BodyTiers.Tiers(build(50), { potential = 1.15 })
	check("Tiers carries the frame", t.frame == "Power Build" and BodyTiers.Key(t) == string.rep("3", 14), t.frame)
	-- the manifest: every frame family complete (ids, sizes, rig attachments), the same part names and attachment names
	-- as the default family; the default family itself answers for an unknown frame
	local frames = BodyTiers.Frames(REAL)
	local hasFrames = type(REAL.frames) == "table" and next(REAL.frames) ~= nil
	check("Frames(): the default family first", frames[1] == "Athletic")
	if hasFrames then
		local missing = {}
		for _, fid in ipairs({ "Lean", "Muscular", "Power Build", "Heavyweight Build" }) do
			if not BodyTiers.HasFrame(fid, REAL) then
				table.insert(missing, fid .. " (no family)")
			end
			for tier = 1, 5 do
				for _, n in ipairs(BodyTiers.PARTS) do
					local e = BodyTiers.PartEntry(tier, n, REAL, false, fid)
					local base = BodyTiers.PartEntry(tier, n, REAL)
					if not (e and base) then
						table.insert(missing, fid .. tier .. n)
					else
						if e.frame ~= fid then
							table.insert(missing, fid .. tier .. n .. "(default family)")
						end
						-- (the hands and feet are the same part on every frame: gloves, wraps and boots are one mesh; under the
						-- trunks the LowerTorso and thighs keep the Athletic section the trunks are fitted to, so the bigger frames
						-- share them too - their lower body differs by the description's Width / Depth)
						if e.id == base.id then
							table.insert(missing, fid .. tier .. n .. "(same mesh as Athletic)")
						end
						for an in pairs(base.attachments) do
							if not e.attachments[an] then
								table.insert(missing, fid .. tier .. n .. "(no " .. an .. ")")
							end
						end
					end
				end
			end
		end
		check("manifest: 4 x 70 frame parts with their own ids and the rig attachments", #missing == 0,
			table.concat(missing, ",", 1, math.min(#missing, 8)))
		-- the frames read as different silhouettes: the shoulder span (BodyAssetData fit) climbs Lean < Athletic <
		-- Muscular < Power Build, and the thighs / hips under the trunks stay what the gear was fitted to
		local function fit(fid, tier, key)
			return BodyTiers.Fit(tier, key, REAL, fid)
		end
		for _, tier in ipairs({ 1, 5 }) do
			local sp = {}
			for _, fid in ipairs({ "Lean", "Athletic", "Muscular", "Power Build" }) do
				local f = REAL.frames[fid] and REAL.frames[fid].tiers[tier] or REAL.tiers[tier]
				table.insert(sp, f.fit.shoulderSpan)
			end
			check(string.format("tier %d shoulder span: Lean %.2f < Athletic %.2f < Muscular %.2f < Power %.2f", tier, sp[1], sp[2], sp[3], sp[4]),
				sp[1] < sp[2] and sp[2] < sp[3] and sp[3] < sp[4] and sp[4] / sp[1] > 1.2)
			-- (v12 second pass: the frame's pelvis / thighs / wrist are the Athletic ones scaled by its gear scale, which
			-- BuilderGear puts on the trunks, gloves and boots; so each measure is the Athletic one x that factor)
			for _, fid in ipairs({ "Lean", "Muscular", "Power Build", "Heavyweight Build" }) do
				local gl, gt, ga = BodyTiers.GearScale(fid, "LowerTorso", REAL), BodyTiers.GearScale(fid, "UpperLeg", REAL), BodyTiers.GearScale(fid, "LowerArm", REAL)
				local a, b = fit(fid, tier, "hips"), fit("Athletic", tier, "hips")
				local c, d = fit(fid, tier, "thigh"), fit("Athletic", tier, "thigh")
				local w, x = fit(fid, tier, "wrist"), fit("Athletic", tier, "wrist")
				check(fid .. " tier " .. tier .. ": hips / thigh / wrist = the Athletic ones x the frame's gear scale",
					math.abs(a.width - b.width * gl[1]) < 0.015 and math.abs(c.width - d.width * gt[1]) < 0.015
					and math.abs(w.width - x.width * ga[1]) < 0.012,
					string.format("%.3f/%.3f %.3f/%.3f %.3f/%.3f", a.width, b.width * gl[1], c.width, d.width * gt[1], w.width, x.width * ga[1]))
			end
		end
		-- the frames' own rig heights and gear scales
		local lu, pu = BodyTiers.Unit("Lean", REAL), BodyTiers.Unit("Power Build", REAL)
		-- (v13: every frame's unit carries its own neck height and head; the skeletons differ (Lean's longer shins,
		-- Power Build's shorter legs) but Builder.Scales normalises the height, so the units stand within 3 % of each
		-- other and the hip share of the standing height within 1 %)
		check("frame units: own neck height, head and standing height per frame", lu and pu and lu.neckHeight > pu.neckHeight
			and lu.head < pu.head and math.abs(lu.standingHeight - pu.standingHeight) < 0.2 and lu.hipHeight > pu.hipHeight, lu and lu.standingHeight)
		local au = REAL.unit
		for _, fid in ipairs({ "Lean", "Muscular", "Power Build", "Heavyweight Build" }) do
			local u = BodyTiers.Unit(fid, REAL)
			local share = u.hipHeight / u.neckHeight
			check(fid .. ": the hip's share of the neck height within 1 % of the Athletic's", math.abs(share / (au.hipHeight / au.neckHeight) - 1) < 0.0125,
				string.format("%.4f vs %.4f", share, au.hipHeight / au.neckHeight))
		end
		check("Unit(): the default family's for Athletic / unknown", BodyTiers.Unit("Athletic", REAL) == REAL.unit and BodyTiers.Unit("x", REAL) == REAL.unit)
		local gs = BodyTiers.GearScale("Heavyweight Build", "LowerTorso", REAL)
		check("GearScale: the heavyweight's pelvis is wider, the default family's is 1", gs[1] > 1.1 and BodyTiers.GearScale("Athletic", "LowerTorso", REAL)[1] == 1)
		-- lite: the frames wear the default family's lite set
		local le = BodyTiers.PartEntry(3, "UpperTorso", REAL, true, "Power Build")
		local lb = BodyTiers.PartEntry(3, "UpperTorso", REAL, true)
		check("a frame's lite part is the default family's", le and lb and le.id == lb.id and le.lite == lb.lite, le and le.id)
	else
		print("  (no frame families in the manifest yet: frame checks on the data skipped)")
	end
	local unknown = BodyTiers.PartEntry(3, "UpperTorso", REAL, false, "No Such Frame")
	local base = BodyTiers.PartEntry(3, "UpperTorso", REAL)
	check("an unknown frame wears the default family", unknown and base and unknown.id == base.id and unknown.frame == "Athletic")
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
	check("styles: the 12 resting Boxer faces in order, no Built option (uploaded)", table.concat(sk, ",")
		== "wcb_neutral=Boxer Neutral,wcb_focused=Boxer Focused,wcb_smirk=Boxer Smirk,wcb_grit=Boxer Grit,wcb_confident=Boxer Confident,"
			.. "wcb_grin=Boxer Grin,wcb_cool=Boxer Cool,wcb_wink=Boxer Wink,wcb_stern=Boxer Stern,wcb_determined=Boxer Determined,"
			.. "wcb_toothy=Boxer Toothy Grin,wcb_scarred=Boxer Scarred", table.concat(sk, ","))
	local allIds = true
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		local f = BodyTiers.Face(k, REAL)
		allIds = allIds and f ~= nil and f.id ~= nil and f.creator and BodyTiers.FaceTexture(k, REAL) == "rbxassetid://" .. f.id
	end
	check("styles: every Boxer face has a real id and texture", allIds)
	check("styles: ids 0 -> nothing offered (the built fallback has no UI)", #BodyTiers.FaceStyles({ faces = { { key = "wcb_grit", name = "G", id = 0 } } }) == 0
		and #BodyTiers.FaceStyles(NODRAWN) == 0)
	check("default style: Boxer Neutral", BodyTiers.DefaultStyle(REAL) == "wcb_neutral" and BodyTiers.DrawnFaces(REAL))
	check("default style: neutral not uploaded -> the first uploaded drawn face",
		BodyTiers.DefaultStyle({ faces = { { key = "wcb_neutral", name = "N", id = 0 }, { key = "wcb_smirk", name = "S", id = 5 } } }) == "wcb_smirk")
	check("default style: none uploaded -> the built fallback", BodyTiers.DefaultStyle(NODRAWN) == "built" and not BodyTiers.DrawnFaces(NODRAWN))
	check("styles: never a classic face key", BodyTiers.SanitizeFace("wcb_smirk", nil, REAL) == "smile" and BodyTiers.SanitizeFace({}, "wcb_grit", REAL) == "smile")
	check("styles: kept off the classic picker", not table.find(picks, "wcb_neutral") and not table.find(picks, "wcb_grit"))
	check("style sanitise: a drawn face kept", BodyTiers.SanitizeFaceStyle("wcb_grit", nil, REAL) == "wcb_grit")
	check("style sanitise: built refused, the saved drawn face kept", BodyTiers.SanitizeFaceStyle("built", "wcb_grit", REAL) == "wcb_grit")
	check("style sanitise: a built save -> Boxer Neutral", BodyTiers.SanitizeFaceStyle("built", nil, REAL) == "wcb_neutral"
		and BodyTiers.SanitizeFaceStyle("built", "built", REAL) == "wcb_neutral" and BodyTiers.SanitizeFaceStyle(nil, "built", REAL) == "wcb_neutral")
	check("style sanitise: junk keeps the saved style", BodyTiers.SanitizeFaceStyle("cool", "wcb_focused", REAL) == "wcb_focused")
	check("style sanitise: nothing -> Boxer Neutral", BodyTiers.SanitizeFaceStyle(nil, nil, REAL) == "wcb_neutral" and BodyTiers.SanitizeFaceStyle(5, "x", REAL) == "wcb_neutral")
	check("style sanitise: not uploaded -> built", BodyTiers.SanitizeFaceStyle("wcb_grit", nil, ZERO) == "built")
	local moodWant = { guard = "wcb_focused", attack = "wcb_determined", train = "wcb_determined", effort = "wcb_grit", hurt = "wcb_hurt",
		angry = "wcb_shout", taunt = "wcb_smirk", happy = "wcb_grin", confident = "wcb_confident", celebrate = "wcb_toothy", ko = "wcb_ko",
		dazed = "wcb_dazed", stunned = "wcb_dazed", tired = "wcb_tired", surprised = "wcb_surprised", neutral = "wcb_smirk", rest = "wcb_smirk" }
	local moodBad = {}
	for mood, want in pairs(moodWant) do
		local got = BodyTiers.StyleMoodFace(mood, "wcb_smirk", REAL)
		if got ~= want then
			table.insert(moodBad, mood .. "->" .. tostring(got))
		end
	end
	check("style moods: the set by mood, the chosen face at rest", #moodBad == 0, table.concat(moodBad, ", "))
	check("style moods: not uploaded -> the chosen face", BodyTiers.StyleMoodFace("guard", "wcb_grit", ZERO) == "wcb_grit")
	check("drawn style of a look", BodyTiers.DrawnStyleOf({ face = { style = "wcb_focused" } }, REAL) == "wcb_focused")
	check("drawn style: never nil while drawn faces are uploaded (built / missing / junk / no face -> Boxer Neutral)",
		BodyTiers.DrawnStyleOf({ face = { style = "built" } }, REAL) == "wcb_neutral" and BodyTiers.DrawnStyleOf({ face = {} }, REAL) == "wcb_neutral"
		and BodyTiers.DrawnStyleOf({ face = { style = "ko" } }, REAL) == "wcb_neutral" and BodyTiers.DrawnStyleOf({}, REAL) == "wcb_neutral"
		and BodyTiers.DrawnStyleOf(nil, REAL) == "wcb_neutral")
	check("drawn style: none uploaded -> nil (the built fallback)", BodyTiers.DrawnStyleOf({ face = { style = "wcb_grit" } }, NODRAWN) == nil)
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
	check("defaults: Boxer Neutral face style", Looks.Defaults(1).face.style == "wcb_neutral" and Looks.Defaults(2).face.style == "wcb_neutral")
	local oldS = Looks.Defaults(1)
	oldS.face.style = nil
	Looks.Fill(oldS)
	check("old save -> Boxer Neutral (Fill)", oldS.face.style == "wcb_neutral")
	local builtS = Looks.Defaults(2)
	builtS.face.style = "built"
	Looks.Fill(builtS)
	check("built save -> Boxer Neutral (Fill)", builtS.face.style == "wcb_neutral")
	local keptS = Looks.Defaults(1)
	keptS.face.style = "wcb_grit"
	check("Fill keeps a drawn style", Looks.Fill(keptS).face.style == "wcb_grit")
	check("old save -> Boxer Neutral (Sanitize)", Looks.Sanitize({ face = {} }, { gender = 1, face = { key = "cool" } }).face.style == "wcb_neutral")
	check("built save -> Boxer Neutral (Sanitize)", Looks.Sanitize({ face = {} }, { gender = 1, face = { key = "cool", style = "built" } }).face.style == "wcb_neutral"
		and Looks.Sanitize({ face = { style = "built" } }).face.style == "wcb_neutral")
	check("Sanitize keeps a drawn style", Looks.Sanitize({ face = { style = "wcb_smirk" } }, saved).face.style == "wcb_smirk")
	local savedS = Looks.Defaults(1)
	savedS.face.style = "wcb_grit"
	check("Sanitize: no style in the input keeps the saved one", Looks.Sanitize({ face = { key = "wink" } }, savedS).face.style == "wcb_grit")
	check("Sanitize: junk style keeps the saved one", Looks.Sanitize({ face = { style = "ko" } }, savedS).face.style == "wcb_grit")
	check("Sanitize: built refused, the saved drawn face kept", Looks.Sanitize({ face = { style = "built" } }, savedS).face.style == "wcb_grit")
	check("Sanitize round trip", Looks.Sanitize(Looks.Sanitize({ face = { style = "wcb_focused" } })).face.style == "wcb_focused")
	-- NPCs: a resting face among the twelve from their own stream (neutral about a third), the same per seed; never
	-- a mood-only face
	local npcCount, npcOk, npcSame = {}, true, true
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		npcCount[k] = 0
	end
	local N = 600
	for seed = 1, N do
		local g = seed % 2 + 1
		local st = Looks.Random(seed * 131, g).face.style
		npcOk = npcOk and npcCount[st] ~= nil
		if npcCount[st] then
			npcCount[st] += 1
		end
		npcSame = npcSame and Looks.Random(seed * 131, g).face.style == st
	end
	local seen = 0
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		if npcCount[k] > 0 then
			seen += 1
		end
	end
	local mix = string.format("neutral %d focused %d stern %d seen %d", npcCount.wcb_neutral, npcCount.wcb_focused, npcCount.wcb_stern, seen)
	check("NPCs: always one of the resting drawn faces", npcOk, mix)
	check("NPCs: the face is deterministic per seed", npcSame)
	check("NPCs: mostly neutral, then focused, and a spread of the others", npcCount.wcb_neutral > npcCount.wcb_focused
		and npcCount.wcb_focused > npcCount.wcb_wink and seen >= 10 and math.abs(npcCount.wcb_neutral / N - 0.34) < 0.1, mix)
	check("mood faces are never a look's style", not BodyTiers.IsDrawnStyle("wcb_ko", REAL) and BodyTiers.IsDrawnFace("wcb_ko", REAL)
		and BodyTiers.SanitizeFaceStyle("wcb_hurt", nil, REAL) == BodyTiers.DEFAULT_STYLE)
	check("the Creator offers the twelve resting faces", #BodyTiers.FaceStyles(REAL) == #BodyTiers.STYLE_KEYS, #BodyTiers.FaceStyles(REAL))
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
-- detail sets (Config.Detail.meshes): the low level's lite meshes (the v9 set), swapped both ways
------------------------------------------------------------------------
do
	BodyTiers.SetData(REAL)
	BuilderTiers.Reset()
	local AS = fakeAssets()
	BuilderTiers.Services = { AssetService = AS, Content = Content }
	local full, lite = BodyTiers.PartEntry(3, "UpperTorso"), BodyTiers.PartEntry(3, "UpperTorso", nil, true)
	check("lite entry: its own mesh, size and attachments", full and lite and lite.lite == true and not full.lite and lite.id ~= full.id
		and lite.attachments.WaistRigAttachment ~= nil, lite and lite.id)
	local Config = H.require("Config")
	check("Config.Detail.meshes: full / medium detailed, low lite", Config.Detail.full.meshes == "full"
		and Config.Detail.medium.meshes == "full" and Config.Detail.low.meshes == "lite")
	local model = newRig(Vector3.new(1, 1, 1), "engine")
	local tiers = BodyTiers.Tiers(build(50), { potential = 0.95 })
	local n1, key1 = BuilderTiers.Apply(model, tiers, Vector3.new(1, 1, 1))
	local ut = model:FindFirstChild("UpperTorso")
	check("detailed set first", n1 == 14 and ut:GetAttribute("BodyMesh") == full.id and ut:GetAttribute("BodyLite") == nil, n1)
	local n2, key2 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 0.95 }, BuilderTiers.Current(model)),
		Vector3.new(1, 1, 1), true)
	ut = model:FindFirstChild("UpperTorso")
	check("lite: every part swapped to its tier's lite mesh", n2 == 14 and ut:GetAttribute("BodyMesh") == lite.id
		and ut:GetAttribute("BodyLite") == true and key2 == key1, tostring(n2) .. " " .. tostring(key2))
	check("lite: the part's size is the lite mesh's", ut.Size.Y > 0 and math.abs(ut.Size.Y - lite.size[2]) < 1e-3, ut.Size.Y)
	local n3 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 0.95 }, BuilderTiers.Current(model)), Vector3.new(1, 1, 1), true)
	check("lite again: nothing to swap", n3 == 0, n3)
	local n4 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 0.95 }, BuilderTiers.Current(model)), Vector3.new(1, 1, 1))
	ut = model:FindFirstChild("UpperTorso")
	check("back to the detailed set", n4 == 14 and ut:GetAttribute("BodyMesh") == full.id and ut:GetAttribute("BodyLite") == nil, n4)
	-- the triangles a body wears per set (BodyAssetData: tris / liteTris)
	local t3 = REAL.tiers[3]
	print(string.format("body triangles: %d detailed, %d lite", t3.tris or 0, t3.liteTris or 0))
	check("lite set lighter than the detailed one", (t3.liteTris or 0) > 0 and t3.liteTris < t3.tris)
	-- (v12) the frame families on the swap
	local hasFrames = type(REAL.frames) == "table" and next(REAL.frames) ~= nil
	-- the swap: a frame change swaps the parts of an unchanged tier (BuilderTiers.Apply follows tiers.frame)
	if hasFrames then
		BuilderTiers.Reset()
		local model = newRig(Vector3.new(1, 1, 1), "keep")
		local scale = Vector3.new(1, 1, 1)
		local n1 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 0.95 }), scale)
		local ut = model:FindFirstChild("UpperTorso")
		check("frame swap: the default family first", n1 == 14 and ut:GetAttribute("BodyFrame") == "Athletic" and model:GetAttribute("BodyFrame") == "Athletic", n1)
		-- (the parts whose mesh differs between the two families: the hands and feet are shared, so they stay)
		local function differing(fa, fb)
			local k = 0
			for _, n in ipairs(BodyTiers.PARTS) do
				if BodyTiers.PartEntry(3, n, REAL, false, fa).id ~= BodyTiers.PartEntry(3, n, REAL, false, fb).id then
					k += 1
				end
			end
			return k
		end
		local want2 = differing("Athletic", "Power Build")
		local n2 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 1.15 }, BuilderTiers.Current(model)), scale)
		ut = model:FindFirstChild("UpperTorso")
		local pe = BodyTiers.PartEntry(3, "UpperTorso", REAL, false, "Power Build")
		check("frame swap: a new frame swaps every part of the same tier whose mesh differs (" .. want2 .. ")", n2 == want2 and want2 >= 10
			and ut:GetAttribute("BodyFrame") == "Power Build"
			and ut:GetAttribute("BodyMesh") == pe.id and ut:GetAttribute("BodyTier") == 3 and model:GetAttribute("BodyFrame") == "Power Build", n2)
		local n3 = BuilderTiers.Apply(model, BodyTiers.Tiers(build(50), { potential = 1.15 }, BuilderTiers.Current(model)), scale)
		check("frame swap: change-only", n3 == 0, n3)
		-- the model's Frame attribute stands in when the tiers table carries none
		model:SetAttribute("Frame", "Lean")
		local plain = BodyTiers.Tiers(build(50), { potential = 1.15 })
		plain.frame = nil
		local n4 = BuilderTiers.Apply(model, plain, scale)
		check("frame swap: the model's Frame attribute", n4 == differing("Power Build", "Lean") and model:FindFirstChild("UpperTorso"):GetAttribute("BodyFrame") == "Lean", n4)
	end
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
	check("ScaleKey p4 and training-independent", Builder.ScaleKey(man, build(8)) == Builder.ScaleKey(man, build(95))
		and Builder.ScaleKey(man, build(8)):sub(-2) == "p4")
	local woman = Looks.Defaults(2)
	local ws = Builder.Scales(woman, build(8))
	check("women: narrower shoulders, smaller head", near(ws.width, 0.92) and near(ws.depth, 0.94) and near(ws.head, 0.7724 * 0.97, 1e-4))
	man.body.frame = "Heavyweight Build"
	local hs = Builder.Scales(man, build(8))
	-- (v13: half of Config.BodyTypes' width / depth, the mesh family carries the rest; the frame's own head share)
	check("Heavyweight frame: wider and deeper (half the BodyTypes value), bigger head", near(hs.width, 1 + 0.17 * Builder.FRAME_WIDTH_SHARE)
		and near(hs.depth, 1 + 0.16 * Builder.FRAME_WIDTH_SHARE) and near(hs.head, Builder.FRAME_PROPORTIONS["Heavyweight Build"].head * 0.942, 1e-4))
	check("the frame's head share is the one its meshes were modelled under (BodyAssetData.frames[id].unit.head)", (function()
		for _, fid in ipairs({ "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }) do
			man.body.frame = fid
			local u = BodyTiers.Unit(fid, REAL)
			if not (u and near(1.2 * Builder.Scales(man, build(8)).head, u.head, 1e-3)) then
				return false
			end
		end
		man.body.frame = "Athletic"
		return true
	end)())
	check("Heavyweight / Lean: the height scale differs from inches / 70 by the frame's own neck height (same standing height)", (function()
		local tot = {}
		for _, fid in ipairs({ "Lean", "Athletic", "Heavyweight Build" }) do
			man.body.frame = fid
			local s, u = Builder.Scales(man, build(8)), BodyTiers.Unit(fid, REAL)
			tot[fid] = u.neckHeight * s.height + 1.2 * s.head
		end
		man.body.frame = "Athletic"
		return near(tot.Lean, tot.Athletic, 1e-3) and near(tot["Heavyweight Build"], tot.Athletic, 1e-3) and near(tot.Athletic, REAL.unit.standingHeight, 1e-3)
	end)())
	man.body.frame = "Lean"
	local ls = Builder.Scales(man, build(8))
	check("Lean frame: narrower, smaller head", ls.width < 0.95 and ls.depth < 0.95 and ls.head < sc.head)
	check("the four frames' scales climb Lean < Muscular < Power Build < Heavyweight Build", (function()
		local last = 0
		for _, id in ipairs({ "Lean", "Muscular", "Power Build", "Heavyweight Build" }) do
			man.body.frame = id
			local w = Builder.Scales(man, build(8)).width
			if w <= last then
				return false
			end
			last = w
		end
		return true
	end)())
	man.body.frame = "Athletic"
	man.height = 76
	-- (v13: the standing height scales with the inches; the head is not height-scaled, so the body's scale is a
	-- little more than inches / 70 above 70 and a little less below)
	local s76 = Builder.Scales(man, build(8))
	check("standing height scales with the inches (76 in = 76 / 70 x the unit's)", near(REAL.unit.neckHeight * s76.height + 1.2 * s76.head, REAL.unit.standingHeight * 76 / 70, 1e-3)
		and near(Builder.StandingHeight(76), REAL.unit.standingHeight * 76 / 70, 1e-6) and s76.height > 76 / 70)
	man.height = 70
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
	-- the default look wears the drawn Boxer Neutral (a classic face.key is no decal of its own); two builds (gloves,
	-- then wraps) leave exactly the one decal
	local nDecals = 0
	for _, d in ipairs(h and h:GetChildren() or {}) do
		if d:IsA("Decal") then
			nDecals += 1
		end
	end
	check("default look: the drawn Boxer Neutral, one decal after a rebuild", decal ~= nil and nDecals == 1
		and decal.Texture == "rbxassetid://" .. BodyTiers.Face("wcb_neutral", REAL).id, nDecals .. " " .. tostring(decal and decal.Texture))
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
-- The built face: rig, budget, FaceFX, workouts and damage. Dormant in the game (every boxer wears a drawn face);
-- built here only through the test-only path: the data with no drawn face uploaded (NODRAWN, the emergency fallback)
------------------------------------------------------------------------
do
	local Builder = H.require("Builder")
	local Looks = H.require("Looks")
	BodyTiers.SetData(NODRAWN)
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

	-- the face controls on the drawn face (the game's): every one the Creator still shows changes the drawn head (its
	-- min against its max, every option value against the default, on any of a few skin-detail seeds), and every one
	-- it hides (BodyTiers.BUILT_ONLY) does not. A signature of the head (size, colour, material) and every BoxerLook
	-- part (name, place, size, colour, transparency)
	BodyTiers.SetData(REAL)
	local LookKit = { FaceShown = BodyTiers.FaceControlShown } -- (LookKit.FaceShown forwards here; LookKit needs the GUI)
	local function sig(a)
		local m = rigWithHead()
		pcall(Builder.Cosmetics, m, a, build(30), nil, { hands = "gloves", detail = "full" })
		local hd = m:FindFirstChild("Head")
		local out = { tostring(hd.Material), string.format("%.4f %.3f %.3f %.3f %.4f %.4f %.4f", hd.Reflectance, hd.Color.R, hd.Color.G, hd.Color.B,
			hd.Size.X, hd.Size.Y, hd.Size.Z) }
		for _, p in ipairs(m:FindFirstChild("BoxerLook") and m.BoxerLook:GetDescendants() or {}) do
			if p:IsA("BasePart") then
				local lp = hd.CFrame:PointToObjectSpace(p.Position)
				table.insert(out, string.format("%s %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %.2f", p.Name, lp.X, lp.Y, lp.Z, p.Size.X, p.Size.Y, p.Size.Z,
					p.Color.R, p.Color.G, p.Color.B, p.Transparency))
			end
		end
		for _, d in ipairs(hd:GetChildren()) do
			if d:IsA("Decal") then
				table.insert(out, "Decal " .. tostring(d.Texture))
			end
		end
		m:Destroy()
		table.sort(out)
		return table.concat(out, "|")
	end
	local function changes(key, v0, v1)
		for _, seed in ipairs({ 7, 4242, 90001 }) do
			local lo, hi = Looks.Defaults(1), Looks.Defaults(1)
			lo.face.seed, hi.face.seed = seed, seed
			lo.face[key], hi.face[key] = v0, v1
			if sig(lo) ~= sig(hi) then
				return true
			end
		end
		return false
	end
	local base = Looks.Defaults(1)
	local deadShown, liveHidden = {}, {}
	local function judge(key, label, live)
		if LookKit.FaceShown(key) and not live then
			table.insert(deadShown, label)
		elseif not LookKit.FaceShown(key) and live then
			table.insert(liveHidden, label)
		end
	end
	for _, list in ipairs({ Looks.FaceSliders, Looks.EyeSliders, Looks.SkinSliders, Looks.WearSliders }) do
		for _, sl in ipairs(list) do
			judge(sl.key, sl.key, changes(sl.key, sl.min, sl.max))
		end
	end
	for _, opt in ipairs({ { "shape", Looks.FaceShapes }, { "browStyle", Looks.BrowStyles }, { "undertone", Looks.Undertones }, { "noseType", Looks.NoseTypes } }) do
		for _, v in ipairs(opt[2]) do
			if v ~= base.face[opt[1]] then
				judge(opt[1], opt[1] .. "=" .. v, changes(opt[1], base.face[opt[1]], v))
			end
		end
	end
	judge("eyeColor", "eyeColor", changes("eyeColor", base.face.eyeColor, 5))
	judge("eyeColor2", "eyeColor2", changes("eyeColor2", 0, 4))
	check("drawn face: every face control the Creator shows changes it", #deadShown == 0, table.concat(deadShown, ", "))
	check("drawn face: every control the Creator hides (built-face only) changes nothing on it", #liveHidden == 0, table.concat(liveHidden, ", "))
	check("drawn face: the built-only controls are hidden", not LookKit.FaceShown("eyeSize") and not LookKit.FaceShown("browStyle")
		and not LookKit.FaceShown("eyeColor") and LookKit.FaceShown("jawWidth") and LookKit.FaceShown("freckles") and LookKit.FaceShown("shape"))
	-- the hair-only controls (BodyTiers.HAIR_ONLY: the forehead places the generated hairline): hidden while every boxer is
	-- bald (Config.BaldMode, when they change nothing visible), shown again with hair on, when they move it
	do
		local Config = H.require("Config")
		local wasBald = Config.BaldMode
		Config.BaldMode = true
		check("drawn face, BaldMode: the hair-only forehead control is hidden", not LookKit.FaceShown("forehead") and BodyTiers.HAIR_ONLY.forehead == true)
		check("drawn face, BaldMode: the forehead changes nothing on it", not changes("forehead", -1, 1))
		Config.BaldMode = false
		check("drawn face, hair on: the forehead control is shown", LookKit.FaceShown("forehead"))
		check("drawn face, hair on: the forehead moves the hair", changes("forehead", -1, 1))
		Config.BaldMode = wasBald
	end
	BodyTiers.SetData(NODRAWN)
	check("built fallback (no drawn face uploaded): the controls show again", LookKit.FaceShown("eyeSize") and LookKit.FaceShown("browStyle"))
	BodyTiers.SetData(REAL)

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
	check("FaceFX decal: anger -> shout", run({ Expr = "anger" }) == tex("wcb_shout"))
	check("FaceFX decal: happy -> grin", run({ Expr = "happy" }) == tex("wcb_grin"))
	check("FaceFX decal: KO -> KO", run({ Expr = "ko", Guard = "down" }) == tex("wcb_ko"))
	dm:SetAttribute("Guard", nil) -- (out of the ring: no Guard attribute)
	check("FaceFX decal: back at rest -> the chosen face", run({ Expr = "neutral" }) == tex("wcb_smirk"))
	FaceFX.Hit(dm, 1)
	task.wait(0.06) -- (the pain layer's 0.05 s attack; the swap itself skips the hold)
	tclock += 1 / 30
	FaceFX.Update(1 / 30, tclock, dcam, nil, 99)
	check("FaceFX decal: a hit flashes hurt at once", FaceFX.Debug(dm).decal.texture == tex("wcb_hurt"))
	check("FaceFX decal: the server's texture is the chosen face", BodyTiers.FaceTexture(Head.FaceStyle(dm)) == tex("wcb_smirk"))
	-- after a workout on the drawn face: road grime, a tier-up rebuild (applyLook: the 14 body parts swapped, the
	-- face built again), the session's sweat, then a tier-down rebuild: exactly one face decal, no built part or rig
	local DRAWN_TEX0 = {}
	for _, list in ipairs({ BodyTiers.STYLE_KEYS, BodyTiers.STYLE_MOOD_KEYS }) do
		for _, k in ipairs(list) do
			DRAWN_TEX0[tex(k)] = true
		end
	end
	dm:SetAttribute("Grime", 0.8)
	local tiers0 = dm:GetAttribute("BodyTiers")
	pcall(Builder.Cosmetics, dm, dapp, build(95), nil, { hands = "wraps", detail = "full" })
	local tiers1 = dm:GetAttribute("BodyTiers")
	Builder.SetSweat(dm, dapp, 0.85)
	local wl = builtLeft(dm)
	local wd = decals(dm:FindFirstChild("Head"))
	check("drawn workout: the tier rebuild happened", tiers1 ~= nil and tiers1 ~= tiers0, tostring(tiers0) .. " -> " .. tostring(tiers1))
	-- (the decal's Texture is FaceFX's mood swap on this client, the grit of the hit above: the decal's FaceStyle is
	-- the chosen face the server put on; the Texture may be any drawn face, mood faces included)
	check("drawn workout: exactly one face decal (the chosen face), no built parts or rig", #wd == 1 and wd[1]:GetAttribute("FaceStyle") == "wcb_smirk"
		and DRAWN_TEX0[wd[1].Texture] and #wl == 0, #wd .. " " .. tostring(wd[1] and wd[1].Texture) .. " " .. table.concat(wl, ","))
	pcall(Builder.Cosmetics, dm, dapp, build(8), nil, { hands = "gloves", detail = "medium" })
	Builder.SetSweat(dm, dapp, 0)
	wl, wd = builtLeft(dm), decals(dm:FindFirstChild("Head"))
	check("drawn tier-down + detail change: one decal, no built parts", #wd == 1 and wd[1]:GetAttribute("FaceStyle") == "wcb_smirk"
		and DRAWN_TEX0[wd[1].Texture] and #wl == 0, #wd .. " " .. table.concat(wl, ","))
	-- a "built" look (an old save that skipped Sanitize) still wears the drawn face: the default Boxer Neutral
	local bapp = table.clone(dapp)
	bapp.face = table.clone(dapp.face)
	bapp.face.style = "built"
	pcall(Builder.Cosmetics, dm, bapp, build(30), nil, { hands = "gloves", detail = "full" })
	local bl, bd = builtLeft(dm), decals(dm:FindFirstChild("Head"))
	check("a built look: the drawn Boxer Neutral, no built rig", #bd == 1 and bd[1].Texture == tex("wcb_neutral") and #bl == 0
		and Head.FaceStyle(dm) == "wcb_neutral", #bd .. " " .. table.concat(bl, ","))
	dm:Destroy()
	-- a look with no style (an old save) and a "built" look build the same face as Boxer Neutral
	local plain = Looks.Defaults(1)
	local nostyle = table.clone(plain)
	nostyle.face = table.clone(plain.face)
	nostyle.face.style = nil
	local builtOne = table.clone(plain)
	builtOne.face = table.clone(plain.face)
	builtOne.face.style = "built"
	local sNeutral = sig(plain)
	check("an old save (no style) and a built save build the Boxer Neutral face", plain.face.style == "wcb_neutral" and sig(nostyle) == sNeutral
		and sig(builtOne) == sNeutral)

	-- no built face part on any boxer: the player's looks (new, old save, built save, a woman), NPC looks
	-- (Looks.Random, both genders: the gym crowd, opponents, the tutorial boxer) at every detail level, the Creator's
	-- RANDOM look; every one wears exactly one drawn face decal of the four
	local looks = {}
	local function add(name, a)
		table.insert(looks, { name, a })
	end
	add("new", Looks.Defaults(1))
	add("new woman", Looks.Defaults(2))
	local old1 = Looks.Defaults(1)
	old1.face.style = nil
	add("old save", Looks.Fill(old1))
	add("built save (sanitized)", Looks.Sanitize({ face = { style = "built" } }, { gender = 2, face = { style = "built" } }))
	for seed = 1, 10 do
		add("NPC " .. seed, Looks.Random(seed * 977, seed % 2 + 1, { age = 20 + seed, class = 5 }))
	end
	local DRAWN_TEX = {}
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		DRAWN_TEX[tex(k)] = true
	end
	local bad = {}
	for i, e in ipairs(looks) do
		local detail = ({ "full", "medium", "low" })[i % 3 + 1]
		local m = rigWithHead()
		local okB, errB = pcall(Builder.Cosmetics, m, e[2], build(20 + i * 4), nil, { hands = "gloves", detail = detail, mouthguard = true })
		local left = builtLeft(m)
		local ds = decals(m:FindFirstChild("Head"))
		if not okB or #left > 0 or #ds ~= 1 or not DRAWN_TEX[ds[1].Texture] or Head.FaceStyle(m) == nil then
			table.insert(bad, string.format("%s/%s: %s %d decals %s", e[1], detail, tostring(errB), #ds, table.concat(left, ",")))
		end
		m:Destroy()
	end
	check("no built face part on any player / NPC boxer: one drawn face each", #bad == 0, table.concat(bad, "; "))
end

------------------------------------------------------------------------
-- Headgear on every boxer (Config.AlwaysHeadgear): built by Cosmetics for players, NPCs, the Creator's head-only
-- preview and kept by clones, tier swaps and the sparring recolour; the drawn face stays unobstructed
------------------------------------------------------------------------
do
	local Builder = H.require("Builder")
	local Looks = H.require("Looks")
	local Head = H.require("BuilderHead")
	local Config = H.require("Config")
	local Color3 = roblox.Color3
	BodyTiers.SetData(REAL)
	check("headgear: Config.AlwaysHeadgear on", Config.AlwaysHeadgear == true)
	local function rig()
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
					part.CFrame = old.CFrame
					neck.Part1 = part
					neck.Parent = part
					part.Parent = model
					old:Destroy()
					return true
				end
				return inner(self, enum, part)
			end
		end)(hum.ReplaceBodyPartR15)
		model.Parent = E.workspace
		return model
	end
	local function hg(model)
		local look = model:FindFirstChild("BoxerLook")
		return look and look:FindFirstChild("Headgear")
	end
	local function hgParts(model)
		local out = {}
		for _, d in ipairs(hg(model) and hg(model):GetDescendants() or {}) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function shellColor(model)
		local f = hg(model)
		local p = f and f:FindFirstChild("HGShell")
		return p and p.Color
	end
	-- every part welded to the model's current head
	-- (a Weld under the part, Part0 the head: a JointInstance the engine re-points on a head swap; no WeldConstraint)
	local function welded(model)
		local head = model:FindFirstChild("Head")
		for _, p in ipairs(hgParts(model)) do
			local w = p:FindFirstChildOfClass("Weld")
			if not (w and w.Part0 == head and w.Part1 == p and p:FindFirstChildOfClass("WeldConstraint") == nil) then
				return false, p.Name
			end
		end
		return true
	end
	local function cnear(a, b)
		return a ~= nil and b ~= nil and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
	end

	-- the player: a new boxer at full detail (red gloves -> red headgear, hair hidden under it)
	local app = Looks.Defaults(1)
	local m = rig()
	local ok, err = pcall(Builder.Cosmetics, m, app, build(30), nil, { hands = "gloves", detail = "full" })
	check("headgear: player Cosmetics runs", ok, err)
	check("headgear: player wears it (full set)", #hgParts(m) == Head.HEADGEAR_PARTS.full, #hgParts(m))
	check("headgear: player colour = the gloves' (no attire.headgear)", cnear(shellColor(m), Looks.Color(app.gloves.color)))
	check("headgear: HeadgearColor attribute + hair hidden", typeof(m:GetAttribute("HeadgearColor")) == "Color3" and m:GetAttribute("HairHiddenHeadgear") == true)
	local okW, why = welded(m)
	check("headgear: welded to the classic head", okW, why)
	-- the creator's colour (attire.headgear, sanitised) wins
	local picked = Looks.Sanitize({ attire = { headgear = { 20, 140, 60 } } }, app)
	check("headgear: Sanitize keeps attire.headgear", picked.attire.headgear and picked.attire.headgear[2] == 140)
	check("headgear: Sanitize leaves it unset (gloves' colour)", Looks.Sanitize({}, Looks.Defaults(1)).attire.headgear == nil)
	pcall(Builder.Cosmetics, m, picked, build(30), nil, { hands = "gloves", detail = "full" })
	check("headgear: the picked colour rebuilds it", cnear(shellColor(m), Color3.fromRGB(20, 140, 60)))
	-- a rebuild with nothing changed keeps the parts (cache), a tier swap keeps it on the head
	local before = hgParts(m)[1]
	pcall(Builder.Cosmetics, m, picked, build(30), nil, { hands = "wraps", detail = "full" })
	check("headgear: an unchanged rebuild keeps the same parts", hgParts(m)[1] == before)
	pcall(Builder.Cosmetics, m, picked, build(95), nil, { hands = "gloves", detail = "full" })
	okW, why = welded(m)
	check("headgear: survives a tier swap", #hgParts(m) == Head.HEADGEAR_PARTS.full and okW, why)
	-- sparring: the corner's colour over it, a Cosmetics mid-spar keeps the corner's, off = his own back, never stripped
	local blue = Color3.fromRGB(30, 60, 160)
	Builder.SetHeadgear(m, blue, true)
	check("headgear: sparring on recolours it", cnear(shellColor(m), blue) and #hgParts(m) == Head.HEADGEAR_PARTS.full)
	pcall(Builder.Cosmetics, m, picked, build(95), nil, { hands = "gloves", detail = "full" })
	check("headgear: a rebuild mid-spar keeps the corner's colour", cnear(shellColor(m), blue))
	Builder.SetHeadgear(m, Color3.new(), false)
	check("headgear: sparring off gives his own colour back (still on)", cnear(shellColor(m), Color3.fromRGB(20, 140, 60)) and #hgParts(m) == Head.HEADGEAR_PARTS.full
		and m:GetAttribute("HairHiddenHeadgear") == true)
	check("headgear: fight cleanup keeps it (HasOwnHeadgear)", Builder.HasOwnHeadgear(m) == true)
	-- a clone (FighterCard / GymMirror / the menu stage copy the model) carries it, welded to the clone's head
	local c = m:Clone()
	c.Parent = E.workspace
	okW, why = welded(c)
	check("headgear: a clone carries it", #hgParts(c) == Head.HEADGEAR_PARTS.full and okW, why)
	c:Destroy()
	-- the Creator's head-only preview (opts.only) builds it on a fresh rig and keeps it on the next one
	local pm = rig()
	pcall(Builder.Cosmetics, pm, app, build(30), nil, { hands = "wraps", detail = "full", only = { Face = true } })
	check("headgear: the Creator's head-only preview wears it", #hgParts(pm) == Head.HEADGEAR_PARTS.full)
	pcall(Builder.Cosmetics, pm, picked, build(30), nil, { hands = "wraps", detail = "full", only = { Hair = true } })
	check("headgear: a preview colour change follows", cnear(shellColor(pm), Color3.fromRGB(20, 140, 60)))
	-- a colour within a hair of the skin (Looks.Palette's brown on SkinTones[9]) is nudged off it, so the headgear never
	-- reads as a bare head; the asked colour is kept on the folder, every other colour passes through untouched
	do
		local brown, skin9 = Looks.Color(Looks.Palette[11]), Looks.Color(Looks.SkinTones[9])
		local nudged, adj = Head.OffSkin(brown, skin9)
		check("headgear: Palette brown on skin 9 is nudged off the skin", adj == true and not cnear(nudged, skin9)
			and math.abs(nudged.R - skin9.R) + math.abs(nudged.G - skin9.G) + math.abs(nudged.B - skin9.B) > 0.2)
		local same, adj2 = Head.OffSkin(Looks.Color(Looks.Palette[1]), skin9)
		check("headgear: a distinct colour passes through", adj2 == false and cnear(same, Looks.Color(Looks.Palette[1])))
		local sm9 = rig()
		local a9 = Looks.Defaults(1)
		a9.skin = 9
		a9.attire.headgear = table.clone(Looks.Palette[11])
		pcall(Builder.Cosmetics, sm9, a9, build(30), nil, { hands = "gloves", detail = "full" })
		local h9 = sm9:FindFirstChild("Head")
		local f9 = hg(sm9)
		local allOff = #hgParts(sm9) == Head.HEADGEAR_PARTS.full
		for _, p in ipairs(hgParts(sm9)) do
			if cnear(p.Color, h9.Color) then
				allOff = false
			end
		end
		check("headgear: a brown headgear on skin 9 builds every part off the skin's colour", allOff and f9 and f9:GetAttribute("ColorAdjusted") == true
			and cnear(f9:GetAttribute("Color"), brown), f9 and tostring(f9:GetAttribute("ColorAdjusted")))
		check("headgear: the folder records the head size it was built for", f9 and typeof(f9:GetAttribute("HeadSize")) == "Vector3"
			and (f9:GetAttribute("HeadSize") - h9.Size).Magnitude < 1e-6)
		sm9:Destroy()
	end
	-- sized from the head's live size: the same look on a head scaled after the rig was made builds every part at
	-- the new scale (the relative geometry in head spans is identical); Builder's cache key carries the head size
	do
		local function geomOf(m)
			local head = m:FindFirstChild("Head")
			local hs = Head.HeadSpan(head)
			local out = {}
			for _, p in ipairs(hgParts(m)) do
				local rel = head.CFrame:ToObjectSpace(p.CFrame)
				out[#out + 1] = { p.Name, rel.Position / hs, p.Size / hs }
			end
			table.sort(out, function(x, y)
				return x[1] .. tostring(x[2]) < y[1] .. tostring(y[2])
			end)
			return out, hs
		end
		local a1 = Looks.Defaults(1)
		local m1 = rig()
		pcall(Builder.Cosmetics, m1, a1, build(30), nil, { hands = "gloves", detail = "full" })
		local g1, hs1 = geomOf(m1)
		local m2 = rig()
		m2:FindFirstChild("Head").Size = Vector3.new(1.3, 1.3, 1.3)
		pcall(Builder.Cosmetics, m2, a1, build(30), nil, { hands = "gloves", detail = "full" })
		local g2, hs2 = geomOf(m2)
		local same = #g1 == #g2 and #g1 == Head.HEADGEAR_PARTS.full and math.abs(hs2 - 1.3) < 1e-6 and hs1 < 1
		for i = 1, math.min(#g1, #g2) do
			if g1[i][1] ~= g2[i][1] or (g1[i][2] - g2[i][2]).Magnitude > 1e-3 or (g1[i][3] - g2[i][3]).Magnitude > 1e-3 then
				same = false
			end
		end
		check("headgear: the same geometry in head spans on a 0.93 and a 1.3 head (sized from the live head)", same, string.format("%.3f / %.3f", hs1, hs2))
		-- the head rescaled after the build: the next Cosmetics rebuilds (the size is in the cache key)
		local before = hgParts(m2)[1]
		m2:FindFirstChild("Head").Size = Vector3.new(1.0, 1.0, 1.0)
		pcall(Builder.Cosmetics, m2, a1, build(30), nil, { hands = "gloves", detail = "full" })
		local g3, hs3 = geomOf(m2)
		check("headgear: a head rescaled after the build is rebuilt to the new size", hgParts(m2)[1] ~= before and math.abs(hs3 - 1) < 1e-6 and #g3 == #g1)
		m1:Destroy()
		m2:Destroy()
	end
	pm:Destroy()
	m:Destroy()

	-- NPCs: varied colours from their seed, the medium / low sets, the referee too ("all characters")
	local colours = {}
	local nColours = 0
	for seed = 1, 12 do
		local a = Looks.Random(seed * 977, seed % 2 + 1, { age = 24, class = 5 })
		local key = table.concat(Looks.HeadgearColor(a), ",")
		if not colours[key] then
			colours[key] = true
			nColours += 1
		end
	end
	check("headgear: NPC colours vary by seed", nColours >= 5, nColours)
	check("headgear: Looks.Random is stable", table.concat(Looks.HeadgearColor(Looks.Random(4242, 1)), ",") == table.concat(Looks.HeadgearColor(Looks.Random(4242, 1)), ","))
	for _, detail in ipairs({ "medium", "low" }) do
		local nm = rig()
		local a = Looks.Random(31337, 1, { age = 24, class = 5 })
		pcall(Builder.Cosmetics, nm, a, build(30), nil, { hands = "wraps", detail = detail })
		check("headgear: NPC at " .. detail .. " wears the " .. detail .. " set", #hgParts(nm) == Head.HEADGEAR_PARTS[detail], #hgParts(nm))
		check("headgear: NPC colour from its seed", cnear(shellColor(nm), Looks.Color(Looks.HeadgearColor(a))))
		nm:Destroy()
	end
	check("headgear: the sets shrink with detail", Head.HEADGEAR_PARTS.full > Head.HEADGEAR_PARTS.medium and Head.HEADGEAR_PARTS.medium > Head.HEADGEAR_PARTS.low)
	-- the officials: no headgear (Config.HeadgearOfficials off), their caps instead (BoxerLook/Hat, Head.SetCap)
	local function hatParts(model)
		local look = model:FindFirstChild("BoxerLook")
		local f = look and look:FindFirstChild("Hat")
		local out = {}
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function hatWelded(model)
		local head = model:FindFirstChild("Head")
		for _, p in ipairs(hatParts(model)) do
			local w = p:FindFirstChildOfClass("WeldConstraint")
			if not (w and w.Part0 == head and w.Part1 == p) then
				return false, p.Name
			end
		end
		return true
	end
	check("headgear: officials wear none (Config.HeadgearOfficials off)", Config.HeadgearOfficials == false)
	for _, o in ipairs({ { "referee", "referee" }, { "cornerman", "baseball" } }) do
		for _, detail in ipairs({ "full", "medium", "low" }) do
			local ref = rig()
			pcall(Builder.Cosmetics, ref, Looks.Random(77, 1), build(10), nil, { hands = "bare", detail = detail, outfit = o[1] })
			check("headgear: the " .. o[1] .. " has none (" .. detail .. ")", #hgParts(ref) == 0 and ref:GetAttribute("HeadgearColor") == nil)
			check("cap: the " .. o[1] .. " wears the " .. o[2] .. " cap, " .. detail .. " set", #hatParts(ref) == Head.CAP_PARTS[o[2]][detail], #hatParts(ref))
			local okH, whyH = hatWelded(ref)
			check("cap: welded to the " .. o[1] .. "'s head (" .. detail .. ")", okH, whyH)
			if detail == "medium" then
				-- an unchanged rebuild keeps the parts; a tier swap (a new head) rebuilds it on the new head
				local first = hatParts(ref)[1]
				pcall(Builder.Cosmetics, ref, Looks.Random(77, 1), build(10), nil, { hands = "bare", detail = detail, outfit = o[1] })
				check("cap: an unchanged rebuild keeps the " .. o[1] .. "'s cap", hatParts(ref)[1] == first)
				local oldHead = ref:FindFirstChild("Head")
				pcall(Builder.Cosmetics, ref, Looks.Random(77, 1), build(95), nil, { hands = "bare", detail = detail, outfit = o[1] })
				okH, whyH = hatWelded(ref)
				check("cap: survives a tier swap (" .. o[1] .. ")", #hatParts(ref) == Head.CAP_PARTS[o[2]][detail] and okH, whyH)
				-- a respawn: a fresh head (the old one gone) rebuilds it, welded to the new head
				local nh = oldHead and ref:FindFirstChild("Head")
				if nh then
					local fresh = nh:Clone()
					for _, ch in ipairs(fresh:GetChildren()) do
						if ch.ClassName ~= "SpecialMesh" and ch.ClassName ~= "Attachment" then
							ch:Destroy()
						end
					end
					fresh.Parent = ref
					nh:Destroy()
				end
				pcall(Builder.Cosmetics, ref, Looks.Random(77, 1), build(95), nil, { hands = "bare", detail = detail, outfit = o[1] })
				okH, whyH = hatWelded(ref)
				check("cap: a new head rebuilds it on that head (" .. o[1] .. ")", #hatParts(ref) == Head.CAP_PARTS[o[2]][detail] and okH, whyH)
				local c = ref:Clone()
				c.Parent = E.workspace
				okH, whyH = hatWelded(c)
				check("cap: a clone carries it (" .. o[1] .. ")", #hatParts(c) == Head.CAP_PARTS[o[2]][detail] and okH, whyH)
				c:Destroy()
				-- a boxer built on the same rig afterwards: the cap goes, the headgear comes back
				pcall(Builder.Cosmetics, ref, Looks.Random(77, 1), build(95), nil, { hands = "gloves", detail = detail })
				check("cap: a boxer has none and wears his headgear again", #hatParts(ref) == 0 and #hgParts(ref) == Head.HEADGEAR_PARTS[detail], #hatParts(ref))
			end
			ref:Destroy()
		end
	end
	check("cap: the sets shrink with detail", Head.CAP_PARTS.referee.full > Head.CAP_PARTS.referee.low and Head.CAP_PARTS.referee.low <= 2
		and Head.CAP_PARTS.baseball.low <= 2)

	-- the switch: off = no headgear after Cosmetics, the old sparring toggle (built on, removed off)
	Config.AlwaysHeadgear = false
	local om = rig()
	pcall(Builder.Cosmetics, om, app, build(30), nil, { hands = "gloves", detail = "full" })
	check("headgear: AlwaysHeadgear off -> none", #hgParts(om) == 0 and om:GetAttribute("HeadgearColor") == nil)
	Builder.SetHeadgear(om, blue, true)
	check("headgear: off: sparring builds it", #hgParts(om) > 0 and cnear(shellColor(om), blue))
	Builder.SetHeadgear(om, Color3.new(), false)
	check("headgear: off: sparring off removes it", #hgParts(om) == 0 and om:GetAttribute("HairHiddenHeadgear") == nil)
	om:Destroy()
	Config.AlwaysHeadgear = true
	-- a boxer built while it was on keeps nothing stale when it goes off (and back on)
	local sm = rig()
	pcall(Builder.Cosmetics, sm, app, build(30), nil, { hands = "gloves", detail = "full" })
	Config.AlwaysHeadgear = false
	pcall(Builder.Cosmetics, sm, app, build(30), nil, { hands = "gloves", detail = "full" })
	check("headgear: switched off since the last build -> removed", #hgParts(sm) == 0)
	Config.AlwaysHeadgear = true
	pcall(Builder.Cosmetics, sm, app, build(30), nil, { hands = "gloves", detail = "full" })
	check("headgear: and back on", #hgParts(sm) == Head.HEADGEAR_PARTS.full)
	sm:Destroy()

	-- the drawn face stays unobstructed: rays from the drawn ink (Head.DECAL_INK, which covers every drawn face's
	-- measured ink: |x| <= 0.237, y -0.231 .. 0.183 of the head) to the camera in front and at 3/4 (+-32 deg) hit no
	-- headgear part, at every detail level, on the smallest / default / largest head; and no headgear part's
	-- footprint reaches into the opening (Head.HEADGEAR_OPENING) round the ink
	local INK_MEASURED = { x = 0.237, yLo = -0.231, yHi = 0.183 }
	local inkCovers = false
	for _, b in ipairs(Head.DECAL_INK) do
		if b[2] >= INK_MEASURED.x - 0.03 and b[4] >= INK_MEASURED.yHi then
			inkCovers = true
		end
	end
	check("headgear: DECAL_INK covers the drawn faces' measured ink", inkCovers and Head.DECAL_INK[3][3] <= INK_MEASURED.yLo)
	local O = Head.HEADGEAR_OPENING
	check("headgear: the opening clears the padded ink", O.top >= 0.21 and O.side >= 0.285 and O.sideLow >= 0.2)
	local CL = Head.CLASSIC
	local function classicSdf(q)
		local r, h, rr = CL.r, CL.h, CL.round
		local qx = math.sqrt(q.X * q.X + q.Z * q.Z) - (r - rr)
		local qy = math.abs(q.Y) - (h - rr)
		return math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2) + math.min(math.max(qx, qy), 0) - rr
	end
	-- the first t in (0, tmax) where the ray o + t d (world) enters part p
	local function hits(p, o, d, tmax)
		local lo, ld = p.CFrame:PointToObjectSpace(o), p.CFrame:VectorToObjectSpace(d)
		local sz = p.Size
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		local mt = sm and tostring(sm.MeshType)
		if mt and mt:find("Sphere") then
			local k = Vector3.new(2 / sz.X, 2 / sz.Y, 2 / sz.Z)
			local a, b = lo * k, ld * k
			local A, B, C = b:Dot(b), 2 * a:Dot(b), a:Dot(a) - 1
			local disc = B * B - 4 * A * C
			if disc < 0 then
				return false
			end
			local t1, t2 = (-B - math.sqrt(disc)) / (2 * A), (-B + math.sqrt(disc)) / (2 * A)
			return (t1 > 0 and t1 < tmax) or (t2 > 0 and t1 < tmax)
		elseif mt and mt:find("Head") then
			-- the engine scales the Head mesh uniformly by the part's smallest axis (it never stretches it per axis)
			local k = Vector3.new(1, 1, 1) * (1.2 / math.min(sz.X, sz.Y, sz.Z))
			for t = 0, tmax, 0.004 do
				if classicSdf((lo + ld * t) * k) < 0 then
					return true
				end
			end
			return false
		end
		local t0, t1 = 0, tmax
		for _, ax in ipairs({ "X", "Y", "Z" }) do
			local h = sz[ax] / 2
			if math.abs(ld[ax]) < 1e-9 then
				if math.abs(lo[ax]) > h then
					return false
				end
			else
				local ta, tb = (-h - lo[ax]) / ld[ax], (h - lo[ax]) / ld[ax]
				if ta > tb then
					ta, tb = tb, ta
				end
				t0, t1 = math.max(t0, ta), math.min(t1, tb)
				if t0 > t1 then
					return false
				end
			end
		end
		return true
	end
	local function blocked(model, hx, hy, views, label, partsOf, pitch)
		partsOf = partsOf or hgParts
		local head = model:FindFirstChild("Head")
		local L = Head.FaceLayout(head, {})
		local s = head.Size
		local x, y = hx * s.X, hy * s.Y
		local lp = Vector3.new(x, y, L.surf(x, y))
		local n = L.normal(x, y)
		for _, yaw in ipairs(views) do
			local cp = math.cos(math.rad(pitch or 0))
			local dirL = Vector3.new(math.sin(math.rad(yaw)) * cp, math.sin(math.rad(pitch or 0)), -math.cos(math.rad(yaw)) * cp)
			if n:Dot(dirL) > 0.25 then
				local o = head.CFrame * (lp + n * 0.004)
				local d = head.CFrame:VectorToWorldSpace(dirL)
				for _, p in ipairs(partsOf(model)) do
					if p.Transparency < 0.99 and hits(p, o, d, 3) then
						return string.format("%s (%.3f, %.3f) yaw %d pitch %d: %s", label, hx, hy, yaw, pitch or 0, p.Name)
					end
				end
			end
		end
		return nil
	end
	local bad = {}
	-- Geometry without any model of the head mesh: each part's exact head-local AABB (an ellipsoid's, a drum's or a
	-- block's extents along the head's axes) in head spans. Forbidden: any part whose AABB reaches z < -0.35 while
	-- its centre lies below the brow line (O.top), any whose AABB covers an eye point (+-0.2, 0, -0.5); an
	-- unrotated ellipsoid reaching z <= -0.45 must keep its skin above the brow line there. The head-hugging pads
	-- (crown cap, brow roll, back shell, ear pads) stand >= 0.03 off the side planes |x| = 0.5, the crown cap
	-- >= 0.03 above y = 0.5. Also: no Head mesh anywhere, no part coloured like the skin, no cap on a fighter.
	local geomBad, geomNote = {}, {}
	local function extents(p, rel, hs)
		local sz = p.Size / hs
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		local shape = sm and tostring(sm.MeshType):match("(%w+)$") or (p.Shape and tostring(p.Shape):match("(%w+)$")) or "Block"
		local R = { rel.RightVector, rel.UpVector, rel.LookVector * -1 }
		local a = { sz.X / 2, sz.Y / 2, sz.Z / 2 }
		local ext = {}
		for ai, e in ipairs({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }) do
			local v = 0
			if shape == "Sphere" then
				for i = 1, 3 do
					v += (a[i] * R[i]:Dot(e)) ^ 2
				end
				v = math.sqrt(v)
			elseif shape == "Cylinder" then
				local d = R[1]:Dot(e)
				v = a[1] * math.abs(d) + math.min(a[2], a[3]) * math.sqrt(math.max(1 - d * d, 0))
			else
				for i = 1, 3 do
					v += a[i] * math.abs(R[i]:Dot(e))
				end
			end
			ext[ai] = v
		end
		return shape, ext, a
	end
	local function hgGeom(model, label, detail)
		local head = model:FindFirstChild("Head")
		local hs = Head.HeadSpan(head)
		local look = model:FindFirstChild("BoxerLook")
		local hat = look and look:FindFirstChild("Hat")
		if hat and #hat:GetChildren() > 0 then
			table.insert(geomNote, label .. ": a fighter wears a cap")
		end
		local parts = hgParts(model)
		if #parts ~= Head.HEADGEAR_PARTS[detail] then
			table.insert(geomNote, label .. ": " .. #parts .. " parts")
		end
		for _, p in ipairs(parts) do
			local rel = head.CFrame:ToObjectSpace(p.CFrame)
			local c = rel.Position / hs
			local shape, ext, a = extents(p, rel, hs)
			local lo = { c.X - ext[1], c.Y - ext[2], c.Z - ext[3] }
			local hi = { c.X + ext[1], c.Y + ext[2], c.Z + ext[3] }
			local function flag(why)
				table.insert(geomBad, string.format("%s %s: %s (x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f)", label, p.Name, why, lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
			end
			if shape == "Head" then
				table.insert(geomNote, label .. " " .. p.Name .. ": a Head mesh")
			end
			if cnear(p.Color, head.Color) then
				table.insert(geomNote, label .. " " .. p.Name .. ": the skin's colour")
			end
			if c.Y < O.top and lo[3] < -0.35 then
				flag("reaches in front of the face below the brow line")
			end
			for _, ex in ipairs({ -0.2, 0.2 }) do
				if lo[1] <= ex and hi[1] >= ex and lo[2] <= 0 and hi[2] >= 0 and lo[3] <= -0.5 and hi[3] >= -0.5 then
					flag("covers an eye point")
				end
			end
			local unrotated = math.abs(rel.RightVector.X) > 0.999 and math.abs(rel.UpVector.Y) > 0.999
			if shape == "Sphere" and unrotated and lo[3] < -0.45 then
				local zz = math.min(-0.45, c.Z)
				local f = 1 - ((zz - c.Z) / a[3]) ^ 2
				local lowY = c.Y - a[2] * math.sqrt(math.max(f, 0))
				if lowY < O.top then
					flag(string.format("its skin comes down to y %.3f on the forehead", lowY))
				end
			end
			if p.Name == "HGTop" or p.Name == "HGBrow" or p.Name == "HGShell" or p.Name == "HGSide" or p.Name == "HGEars" then
				if math.max(math.abs(lo[1]), math.abs(hi[1])) < 0.53 then
					flag("grazes the side planes")
				end
			end
			if p.Name == "HGTop" and hi[2] < 0.53 then
				flag("the crown cap is not above the head's top")
			end
		end
	end
	for _, hd in ipairs({ { 2, "Lean", "smallest" }, { 1, "Athletic", "default" }, { 1, "Heavyweight Build", "largest" } }) do
		for _, detail in ipairs({ "full", "medium", "low" }) do
			local a = Looks.Defaults(hd[1])
			a.body.frame = hd[2]
			local fm = rig()
			local sc = Builder.Scales(a, build(30))
			local head = fm:FindFirstChild("Head")
			head.Size = Vector3.new(1, 1, 1) * 1.2 * sc.head
			pcall(Builder.Cosmetics, fm, a, build(30), nil, { hands = "gloves", detail = detail })
			check("headgear: built (" .. hd[3] .. ", " .. detail .. ")", #hgParts(fm) == Head.HEADGEAR_PARTS[detail], #hgParts(fm))
			for _, b in ipairs(Head.DECAL_INK) do
				for i = 0, 6 do
					for j = 0, 6 do
						local ax = b[1] + (b[2] - b[1]) * i / 6
						local ay = b[3] + (b[4] - b[3]) * j / 6
						for _, sx in ipairs({ -1, 1 }) do
							local w = blocked(fm, sx * ax, ay, { 0, 32, -32 }, hd[3] .. "/" .. detail)
							if w then
								table.insert(bad, w)
							end
						end
					end
				end
			end
			-- damage and sweat on the face show where they lie inside the opening
			Builder.SetDamage(fm, a, { leftEye = 1, rightEye = 0.85, cut = 1.1, cutSide = -1, bruise = 0.9, lip = 1, noseBleed = 1, cheekL = 1, cheekR = 0.7 })
			Builder.SetSweat(fm, a, 0.9)
			local look = fm:FindFirstChild("BoxerLook")
			local s = head.Size
			local nMarks = 0
			for _, fname in ipairs({ "Damage", "FaceSweat" }) do
				local f = look and look:FindFirstChild(fname)
				for _, p in ipairs(f and f:GetDescendants() or {}) do
					if p:IsA("BasePart") and p.Transparency < 0.95 then
						local lp = head.CFrame:PointToObjectSpace(p.Position)
						local hx, hy = lp.X / s.X, lp.Y / s.Y
						if lp.Z < 0 and math.abs(hx) < O.sideLow - 0.02 and hy > -0.3 and hy < O.top - 0.02 then
							nMarks += 1
							local w = blocked(fm, hx, hy, { 0 }, hd[3] .. "/" .. detail .. " " .. fname .. "." .. p.Name)
							if w then
								table.insert(bad, w)
							end
						end
					end
				end
			end
			check("headgear: face marks to check (" .. hd[3] .. ", " .. detail .. ")", nMarks >= 4, nMarks)
			hgGeom(fm, hd[3] .. "/" .. detail, detail)
			fm:Destroy()
		end
	end
	check("headgear: the drawn face, its damage and sweat unobstructed", #bad == 0, table.concat(bad, "; ", 1, math.min(#bad, 8)))
	check("headgear: every part clear of the forbidden front region, the eye points, the side planes and the top (no head-mesh model)",
		#geomBad == 0, table.concat(geomBad, "; ", 1, math.min(#geomBad, 8)))
	check("headgear: no Head-mesh part, no part coloured like the skin, no cap on a fighter", #geomNote == 0, table.concat(geomNote, "; ", 1, math.min(#geomNote, 8)))

	-- the officials' caps leave the drawn face unobstructed: the same rays from the drawn ink to a camera in front and
	-- at 3/4, level (the padded ink) and from above (the measured ink: 10 deg in front, 8 at the 3/4), hit no cap part (every style, detail and head size), and no visible cap part
	-- comes down below Head.CAP_CLEAR in front of the face (|x| < 0.3), which is above the padded brow ink
	check("cap: the clearance sits above the padded brow ink", Head.CAP_CLEAR > Head.DECAL_INK[2][4] + 0.02)
	local capBad, low = {}, {}
	for _, hd in ipairs({ { 2, "Lean", "smallest" }, { 1, "Athletic", "default" }, { 1, "Heavyweight Build", "largest" } }) do
		for _, outfit in ipairs({ "referee", "cornerman" }) do
			for _, detail in ipairs({ "full", "medium", "low" }) do
				local a = Looks.Defaults(hd[1])
				a.body.frame = hd[2]
				local fm = rig()
				local sc = Builder.Scales(a, build(30))
				local head = fm:FindFirstChild("Head")
				head.Size = Vector3.new(1, 1, 1) * 1.2 * sc.head
				pcall(Builder.Cosmetics, fm, a, build(30), nil, { hands = "bare", detail = detail, outfit = outfit })
				head = fm:FindFirstChild("Head")
				local label = hd[3] .. "/" .. outfit .. "/" .. detail
				check("cap: built (" .. label .. ")", #hatParts(fm) > 0, #hatParts(fm))
				for _, b in ipairs(Head.DECAL_INK) do
					for i = 0, 6 do
						for j = 0, 6 do
							local ax = b[1] + (b[2] - b[1]) * i / 6
							local ay = b[3] + (b[4] - b[3]) * j / 6
							for _, sx in ipairs({ -1, 1 }) do
								-- level: the padded ink at the front and the 3/4; from above (the game's camera, the
								-- renders' 6 / 8 deg): the measured ink, 10 deg at the front and 8 at the 3/4
								local w = blocked(fm, sx * ax, ay, { 0, 32, -32 }, label, hatParts, 0)
								if not w and ay <= INK_MEASURED.yHi then
									w = blocked(fm, sx * ax, ay, { 0 }, label, hatParts, 10)
										or blocked(fm, sx * ax, ay, { 32, -32 }, label, hatParts, 8)
								end
								if w then
									table.insert(capBad, w)
								end
							end
						end
					end
				end
				-- the lowest visible point of every cap part in front of the face (sampled over the part's box, outside
				-- the head)
				local s = head.Size
				local L = Head.FaceLayout(head, {})
				for _, p in ipairs(hatParts(fm)) do
					if p.Transparency < 0.99 then
						local sz = p.Size
						local sm = p:FindFirstChildOfClass("SpecialMesh")
						local isEll = sm and tostring(sm.MeshType):find("Sphere")
						local isHead = sm and tostring(sm.MeshType):find("Head")
						if isHead then
							-- the engine's Head mesh: uniform at the part's smallest axis
							sz = Vector3.new(1, 1, 1) * math.min(sz.X, sz.Y, sz.Z)
						end
						for i = -4, 4 do
							for j = -4, 4 do
								for k = -4, 4 do
									local q = Vector3.new(i / 8, j / 8, k / 8)
									if (isEll and q.Magnitude <= 0.5) or (isHead and classicSdf(q * 1.2) <= 0) or not (isEll or isHead) then
										local hp = head.CFrame:PointToObjectSpace(p.CFrame * Vector3.new(q.X * sz.X, q.Y * sz.Y, q.Z * sz.Z))
										if hp.Z < 0 and math.abs(hp.X) < 0.3 * s.X and L.outside(hp) > 0.002 and hp.Y / s.Y < Head.CAP_CLEAR - 0.012 then
											table.insert(low, string.format("%s %s y %.3f", label, p.Name, hp.Y / s.Y))
										end
									end
								end
							end
						end
					end
				end
				fm:Destroy()
			end
		end
	end
	check("cap: the drawn face's brows and eyes unobstructed (front, 3/4, level and from above)", #capBad == 0,
		#capBad .. ": " .. table.concat(capBad, "; ", 1, math.min(#capBad, 8)))
	check("cap: nothing visible below Head.CAP_CLEAR in front of the face", #low == 0, table.concat(low, "; ", 1, math.min(#low, 8)))
end

print(string.format("test_bodytiers: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_bodytiers failed")
end
