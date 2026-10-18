-- BodyTiers: the pure half of the standard R15 body (tools/body/CONTRACT.md). No Instances, deterministic, so
-- the server (BuilderTiers swaps the parts), the client (FaceFX swaps the face texture), the Creator and the
-- lune tests read the same rules.
-- * the muscle tiers: every one of the 14 non-head body parts shows one of 5 Blender-modelled tiers (1 lean,
--   2 toned, 3 athletic, 4 muscular, 5 elite) picked from the boxer's build: the muscles that part carries
--   (MAP), each read as Body.Resolve reads it (the value against the frame's potential), averaged into a
--   level, and the level cut into tiers (BANDS) with a little hysteresis so a part never flickers at a
--   boundary. Hands follow their forearm, feet their calf (FOLLOW)
-- * the classic faces: BodyAssetData.faces (a key, a name, an Image id, creator = shown in the picker), the
--   default smile, the face key sanitiser (look.face.key) and the texture a key draws (rbxassetid, or the
--   engine's own smile while an id is 0)
-- * the expressions: the game's mood drivers (the Expr attribute names, the transient hit / effort / shout
--   layers) -> BodyAssetData.expressions moods -> a face key; nil = the boxer's own face
-- BodyAssetData is generated (tools/body/publish_body.py); every id 0 means "not uploaded" and every path
-- here then falls back to the default body part / the default smile.
local BodyTiers = {}

BodyTiers.PARTS = {
	"UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
BodyTiers.TIERS = 5
BodyTiers.TIER_NAMES = { "Lean", "Toned", "Athletic", "Muscular", "Elite" }

-- the muscles each body part carries (Config.MuscleParts ids, weights sum to 1); Left / Right share a group
BodyTiers.MAP = {
	UpperTorso = { pecs = 0.22, upperChest = 0.14, lats = 0.18, upperBack = 0.1, traps = 0.1, abs = 0.14, obliques = 0.06, serratus = 0.06 },
	LowerTorso = { lowerAbs = 0.25, obliques = 0.15, glutes = 0.4, lowerBack = 0.2 },
	UpperArm = { biceps = 0.34, triceps = 0.34, frontDelt = 0.1, sideDelt = 0.16, rearDelt = 0.06 },
	LowerArm = { forearms = 1 },
	UpperLeg = { quads = 0.55, hamstrings = 0.3, glutes = 0.15 },
	LowerLeg = { calves = 1 },
}
-- parts with no muscle group of their own take their limb's tier
BodyTiers.FOLLOW = { Hand = "LowerArm", Foot = "LowerLeg" }
-- level (0 .. ~1.15) where tier 2, 3, 4 and 5 begin. An untrained boxer (8 in every muscle) reads ~0.08: tier 1;
-- a muscle at half its frame's cap ~0.5: tier 3; tier 5 from ~80 % of the cap (Athletic: 76 of 95)
BodyTiers.BANDS = { 0.18, 0.36, 0.56, 0.78 }
-- a part keeps its tier until its level leaves the band by this much (no flicker on a 0.04 level step)
BodyTiers.HYST = 0.03
-- women's levels (the tiers are modelled on the men's default rig): elite needs more work
BodyTiers.FEMALE_K = 0.8
-- the untrained value Config.PartValue gives a missing muscle
local UNTRAINED = 8

-- "LeftUpperArm" -> "UpperArm", "UpperTorso" -> "UpperTorso"
function BodyTiers.Group(name)
	local g = string.match(name, "^Left(.+)$") or string.match(name, "^Right(.+)$") or name
	return g
end

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return d
	end
	return v
end

-- a sub-muscle's value (Config.PartValue's rule without needing Config: the part, else its group, else 8)
local GROUP_OF = {
	pecs = "chest", upperChest = "chest", frontDelt = "shoulders", sideDelt = "shoulders", rearDelt = "shoulders",
	biceps = "arms", triceps = "arms", forearms = "arms", lats = "back", traps = "back", upperBack = "back",
	lowerBack = "back", abs = "core", lowerAbs = "core", obliques = "core", serratus = "core", quads = "legs",
	hamstrings = "legs", glutes = "legs", calves = "legs", neckSCM = "neck",
}
local function partValue(build, id)
	if type(build) ~= "table" then
		return UNTRAINED
	end
	local v = tonumber(build[id])
	if v == nil then
		v = tonumber(build[GROUP_OF[id] or id])
	end
	return num(v, UNTRAINED)
end
BodyTiers.PartValue = partValue

-- one muscle's level as Body.Resolve reads it: value / 100, half of the frame's potential normalised back out
-- (a maxed Lean frame still looks trained, a maxed Heavyweight frame still out-sizes it)
function BodyTiers.MuscleLevel(build, id, potential, female)
	local pot = math.max(num(potential, 0.95), 0.2)
	local v = partValue(build, id) / 100 * (0.55 + 0.45 / pot)
	if female then
		v *= BodyTiers.FEMALE_K
	end
	return math.clamp(v, 0, 1.5)
end

-- { [group] = level } for the six muscle groups of MAP; opts = { potential = BodyTypes potential, female }
function BodyTiers.GroupLevels(build, opts)
	opts = type(opts) == "table" and opts or {}
	local out = {}
	for g, w in pairs(BodyTiers.MAP) do
		local t = 0
		for id, k in pairs(w) do
			t += k * BodyTiers.MuscleLevel(build, id, opts.potential, opts.female)
		end
		out[g] = t
	end
	return out
end

-- level -> tier 1..5; prev (optional) = the tier the part shows now (hysteresis)
function BodyTiers.TierOf(level, prev)
	level = num(level, 0)
	local B, H = BodyTiers.BANDS, BodyTiers.HYST
	local t = 1
	for i, b in ipairs(B) do
		if level >= b then
			t = i + 1
		end
	end
	prev = tonumber(prev)
	if prev and prev >= 1 and prev <= BodyTiers.TIERS and prev ~= t then
		prev = math.floor(prev)
		-- the band prev covers: [lo, hi); stay while the level is within HYST of it
		local lo = prev > 1 and B[prev - 1] or -math.huge
		local hi = prev <= #B and B[prev] or math.huge
		if level >= lo - H and level < hi + H then
			return prev
		end
	end
	return t
end

-- { [part name] = tier } for all 14 parts. prev (optional): { [part name] = current tier } or a function
-- (name) -> current tier
function BodyTiers.Tiers(build, opts, prev)
	local lv = BodyTiers.GroupLevels(build, opts)
	local function prevOf(name)
		if type(prev) == "function" then
			return prev(name)
		elseif type(prev) == "table" then
			return prev[name]
		end
		return nil
	end
	local out = {}
	-- the muscle groups first, then the parts that follow them (a hand with its forearm's tier)
	for _, name in ipairs(BodyTiers.PARTS) do
		local g = BodyTiers.Group(name)
		if lv[g] then
			out[name] = BodyTiers.TierOf(lv[g], prevOf(name))
		end
	end
	for _, name in ipairs(BodyTiers.PARTS) do
		local g = BodyTiers.Group(name)
		local f = BodyTiers.FOLLOW[g]
		if f then
			local side = string.match(name, "^(Left)") or string.match(name, "^(Right)") or ""
			out[name] = out[side .. f] or 1
		end
	end
	return out, lv
end

-- compact signature of a tier table (the model attribute BodyTiers): one digit per part in PARTS order
function BodyTiers.Key(tiers)
	local s = table.create(#BodyTiers.PARTS)
	for i, name in ipairs(BodyTiers.PARTS) do
		s[i] = tostring(math.clamp(math.floor(num(tiers and tiers[name], 0)), 0, 9))
	end
	return table.concat(s)
end

------------------------------------------------------------------------
-- BodyAssetData
------------------------------------------------------------------------
local data -- the loaded table (or a test's)
local function load()
	if data == nil then
		local ok, res = false, nil
		local here = script and script.Parent
		local m = here and here:FindFirstChild("BodyAssetData")
		if m then
			ok, res = pcall(require, m)
		end
		data = (ok and type(res) == "table") and res or {}
	end
	return data
end
function BodyTiers.Data()
	return load()
end
-- tests / tools: use this table instead of the module (nil: load the module again)
function BodyTiers.SetData(d)
	data = d
end

local function idOf(v)
	local n = tonumber(v)
	return (n and n > 0) and math.floor(n) or nil
end
BodyTiers.Id = idOf

local function vec3(t)
	if type(t) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(t[1] or t.x or t.X), tonumber(t[2] or t.y or t.Y), tonumber(t[3] or t.z or t.Z)
	if not (x and y and z) then
		return nil
	end
	return { x, y, z }
end
BodyTiers.Vec3 = vec3

-- a tier part's entry: { id, size = {x,y,z}, attachments = { [name] = {x,y,z} } }, or nil when the mesh is not
-- uploaded (id 0) or the entry is malformed (the default body part stays)
function BodyTiers.PartEntry(tier, name, d)
	d = d or load()
	local tiers = type(d) == "table" and type(d.tiers) == "table" and d.tiers or nil
	local t = tiers and (tiers[tier] or tiers[tostring(tier)])
	local parts = type(t) == "table" and type(t.parts) == "table" and t.parts or nil
	local e = parts and parts[name]
	if type(e) ~= "table" then
		return nil
	end
	local id = idOf(e.mesh)
	local size = vec3(e.size)
	if not (id and size) or size[1] <= 0 or size[2] <= 0 or size[3] <= 0 then
		return nil
	end
	local atts = {}
	if type(e.attachments) == "table" then
		for k, v in pairs(e.attachments) do
			local p = type(k) == "string" and vec3(v)
			if p then
				atts[k] = p
			end
		end
	end
	return { id = id, size = size, attachments = atts, tier = tier, name = name }
end

-- a tier's gear-fit measure (BodyAssetData tiers[n].fit[key]: { width, depth, girth, y }, unscaled studs), or nil
function BodyTiers.Fit(tier, key, d)
	d = d or load()
	local tiers = type(d) == "table" and type(d.tiers) == "table" and d.tiers or nil
	local t = tiers and (tiers[tier] or tiers[tostring(tier)])
	local f = type(t) == "table" and type(t.fit) == "table" and t.fit[key] or nil
	if type(f) == "table" and tonumber(f.width) and tonumber(f.depth) then
		return f
	end
	return nil
end

------------------------------------------------------------------------
-- Faces
------------------------------------------------------------------------
BodyTiers.DEFAULT_FACE = "smile" -- (BodyAssetData.defaultFace)
-- the engine's own classic smile (what an id 0 draws)
BodyTiers.DEFAULT_TEXTURE = "rbxasset://textures/face.png"

-- the face list (always starts with the smile, even when the data has none)
function BodyTiers.Faces(d)
	d = d or load()
	local out, seen = {}, {}
	local list = type(d) == "table" and type(d.faces) == "table" and d.faces or {}
	for _, f in ipairs(list) do
		if type(f) == "table" and type(f.key) == "string" and f.key ~= "" and not seen[f.key] then
			seen[f.key] = true
			table.insert(out, { key = f.key, name = type(f.name) == "string" and f.name or f.key, id = idOf(f.id), creator = f.creator ~= false })
		end
	end
	if not seen[BodyTiers.DEFAULT_FACE] then
		table.insert(out, 1, { key = BodyTiers.DEFAULT_FACE, name = "Smile", id = nil, creator = true })
	end
	return out
end

function BodyTiers.Face(key, d)
	for _, f in ipairs(BodyTiers.Faces(d)) do
		if f.key == key then
			return f
		end
	end
	return nil
end

-- the faces a player picks from in the Creator (creator ~= false); the smile first
function BodyTiers.Pickable(d)
	local out = {}
	for _, f in ipairs(BodyTiers.Faces(d)) do
		if f.creator then
			table.insert(out, f)
		end
	end
	return out
end

-- look.face.key from untrusted input: a pickable key, else the old (saved) key when that is valid, else the smile
function BodyTiers.SanitizeFace(key, old, d)
	local function ok(k)
		if type(k) ~= "string" then
			return false
		end
		local f = BodyTiers.Face(k, d)
		return f ~= nil and f.creator
	end
	if ok(key) then
		return key
	elseif ok(old) then
		return old
	end
	return BodyTiers.DEFAULT_FACE
end

-- the Decal texture of a face key: its uploaded image, else the engine's smile
function BodyTiers.FaceTexture(key, d)
	local f = type(key) == "string" and BodyTiers.Face(key, d) or nil
	if f and f.id then
		return "rbxassetid://" .. f.id
	end
	if key ~= BodyTiers.DEFAULT_FACE then
		local s = BodyTiers.Face(BodyTiers.DEFAULT_FACE, d)
		if s and s.id then
			return "rbxassetid://" .. s.id
		end
	end
	return BodyTiers.DEFAULT_TEXTURE
end

------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------
-- the game's expression drivers (Config.Expressions: the server's Expr attribute, ExprPreview, the Animator's
-- hints, and FaceFX's transient layers hit / effort / shout) -> a BodyAssetData.expressions mood
BodyTiers.MOODS = {
	neutral = "neutral", confident = "confident", determined = "attack", anger = "angry", fear = "surprised",
	fatigue = "tired", pain = "hurt", dazed = "dazed", effort = "effort", happy = "happy", ko = "ko",
	-- FaceFX's transient layers
	hit = "hurt", shout = "angry", down = "stunned",
}

function BodyTiers.MoodOf(expr)
	if type(expr) ~= "string" then
		return "neutral"
	end
	return BodyTiers.MOODS[expr] or (type((load().expressions or {})[expr]) == "string" and expr) or "neutral"
end

-- the face key a mood shows: the expressions table's face (when it exists and is uploaded), else the boxer's own
function BodyTiers.MoodFace(mood, chosen, d)
	d = d or load()
	chosen = type(chosen) == "string" and chosen or BodyTiers.DEFAULT_FACE
	local ex = type(d) == "table" and type(d.expressions) == "table" and d.expressions or {}
	local k = mood ~= "neutral" and ex[mood] or nil
	if type(k) == "string" then
		local f = BodyTiers.Face(k, d)
		if f and f.id then
			return k
		end
	end
	return chosen
end

-- the texture a mood shows on this boxer (FaceFX): MoodFace's key through FaceTexture
function BodyTiers.MoodTexture(mood, chosen, d)
	return BodyTiers.FaceTexture(BodyTiers.MoodFace(mood, chosen, d), d)
end

------------------------------------------------------------------------
-- Fight damage overlays (optional uploaded decals: BodyAssetData.damage = { blackEyeL = id, ... })
------------------------------------------------------------------------
-- each layer is a full-face texture in the faces' layout, shown with Decal.Transparency = 1 - strength
BodyTiers.DAMAGE_LAYERS = { "blackEyeL", "blackEyeR", "cutL", "cutR", "bruise", "swelling" }

-- the damage table (CONTRACTS section 8) -> { [layer] = strength 0..1 } (0 = hidden)
function BodyTiers.DamageStrengths(dmg)
	dmg = type(dmg) == "table" and dmg or {}
	local function n(k)
		return math.clamp(num(dmg[k], 0), 0, 1.5)
	end
	local fade = math.clamp(1 - math.max(0, num(dmg.age, 0)) / 8, 0.15, 1)
	local function s(v, from)
		return math.clamp((v - from) / (1 - from), 0, 1) * fade
	end
	local cutSide = num(dmg.cutSide, 1) < 0 and -1 or 1
	local cut2Side = num(dmg.cutSide2, -cutSide) < 0 and -1 or 1
	local cutL = math.max(cutSide < 0 and n("cut") or 0, cut2Side < 0 and n("cut2") or 0)
	local cutR = math.max(cutSide > 0 and n("cut") or 0, cut2Side > 0 and n("cut2") or 0)
	return {
		blackEyeL = s(n("leftEye"), 0.15),
		blackEyeR = s(n("rightEye"), 0.15),
		cutL = cutL > 0.05 and math.clamp(cutL, 0, 1) or 0,
		cutR = cutR > 0.05 and math.clamp(cutR, 0, 1) or 0,
		bruise = s(math.max(n("bruise"), 0.6 * math.max(n("cheekL"), n("cheekR"))), 0.2),
		swelling = s(math.max(n("forehead"), n("lip")), 0.25),
	}
end

-- the uploaded id of a damage layer (nil: not uploaded, the part-built overlays draw it)
function BodyTiers.DamageId(layer, d)
	d = d or load()
	local dm = type(d) == "table" and type(d.damage) == "table" and d.damage or nil
	return dm and idOf(dm[layer]) or nil
end

return BodyTiers
