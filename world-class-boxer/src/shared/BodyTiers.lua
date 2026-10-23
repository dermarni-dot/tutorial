-- BodyTiers: the pure half of the standard R15 body (tools/body/CONTRACT.md). No Instances, deterministic, so
-- the server (BuilderTiers swaps the parts), the client (FaceFX swaps the face texture), the Creator and the
-- lune tests read the same rules.
-- * the muscle tiers: every one of the 14 non-head body parts shows one of 5 Blender-modelled tiers (1 lean,
--   2 toned, 3 athletic, 4 muscular, 5 elite) picked from the boxer's build: the muscles that part carries
--   (MAP), each read as Body.Resolve reads it (the value against the frame's potential), averaged into a
--   level, and the level cut into tiers (BANDS) with a little hysteresis so a part never flickers at a
--   boundary. Hands follow their forearm, feet their calf (FOLLOW)
-- * the body frames (v12): every Config.BodyTypes frame has its own family of the 5 tiers (BodyAssetData.frames,
--   keyed by the frame id; the Athletic frame is the default family, BodyAssetData.tiers): a Lean frame's narrow
--   shoulders and a Power Build's traps are in the meshes, not only in the description's Width / Depth. The tiers
--   table a build gives carries the frame (tiers.frame, FrameOf: the opts' frame id, else the BodyTypes entry whose
--   potential the caller passed), and PartEntry(tier, name, d, lite, frame) picks that family's part (the default
--   family's when the frame has none uploaded; the lite set is one per tier, the default family's)
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
-- the frame whose family BodyAssetData.tiers holds (the gear is fitted on it)
BodyTiers.DEFAULT_FRAME = "Athletic"

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

-- Config (lazily; the client and the tests load this module without it)
local cfgMod
local function config()
	if cfgMod == nil then
		local here = script and script.Parent
		local m = here and here:FindFirstChild("Config")
		local ok, cfg = false, nil
		if m then
			ok, cfg = pcall(require, m)
		end
		cfgMod = (ok and type(cfg) == "table") and cfg or false
	end
	return cfgMod or nil
end
-- tests / tools: the Config table to read BodyTypes from (nil: the module again)
function BodyTiers.SetConfig(c)
	cfgMod = c
end

-- the frame id a Tiers() call is for: opts.frame when it is a string, else the Config.BodyTypes entry whose potential
-- is opts.potential (Builder passes the frame's potential), else the default frame
function BodyTiers.FrameOf(opts)
	opts = type(opts) == "table" and opts or {}
	if type(opts.frame) == "string" and opts.frame ~= "" then
		return opts.frame
	end
	local pot = tonumber(opts.potential)
	local cfg = config()
	if pot and cfg and type(cfg.BodyTypes) == "table" then
		for _, bt in ipairs(cfg.BodyTypes) do
			if type(bt) == "table" and tonumber(bt.potential) and math.abs(bt.potential - pot) < 1e-6 then
				return bt.id
			end
		end
	end
	return BodyTiers.DEFAULT_FRAME
end

-- { [part name] = tier } for all 14 parts, plus .frame = the frame id (FrameOf). prev (optional): { [part name] =
-- current tier } or a function (name) -> current tier
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
	out.frame = BodyTiers.FrameOf(opts)
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

-- the tier table of a frame's family: BodyAssetData.frames[frame].tiers, or the default family (BodyAssetData.tiers)
-- when the frame is the default one, unknown or has no meshes. Returns tiers, the frame id the family belongs to
local function familyOf(d, frame)
	local fr = type(d) == "table" and type(d.frames) == "table" and type(frame) == "string" and d.frames[frame] or nil
	if type(fr) == "table" and type(fr.tiers) == "table" then
		return fr.tiers, frame
	end
	return type(d) == "table" and type(d.tiers) == "table" and d.tiers or nil, BodyTiers.DEFAULT_FRAME
end
local function tierOf(tiers, tier)
	return tiers and (tiers[tier] or tiers[tostring(tier)]) or nil
end

-- the frame ids with a mesh family in the data (the default frame first, then BodyAssetData.frames' keys, sorted)
function BodyTiers.Frames(d)
	d = d or load()
	local out = { BodyTiers.DEFAULT_FRAME }
	local names = {}
	if type(d) == "table" and type(d.frames) == "table" then
		for k, v in pairs(d.frames) do
			if type(k) == "string" and k ~= BodyTiers.DEFAULT_FRAME and type(v) == "table" and type(v.tiers) == "table" then
				table.insert(names, k)
			end
		end
	end
	table.sort(names)
	for _, k in ipairs(names) do
		table.insert(out, k)
	end
	return out
end

-- true when the frame has its own mesh family (false: it wears the default family)
function BodyTiers.HasFrame(frame, d)
	local _, fid = familyOf(d or load(), frame)
	return fid == frame
end

-- the frame's folder key (tools/body/out/frames/<key>; nil for the default family)
function BodyTiers.FrameKey(frame, d)
	d = d or load()
	local fr = type(d) == "table" and type(d.frames) == "table" and type(frame) == "string" and d.frames[frame] or nil
	return type(fr) == "table" and type(fr.key) == "string" and fr.key or nil
end

-- a tier part's entry: { id, size = {x,y,z}, attachments = { [name] = {x,y,z} }, tier, name, frame, lite }, or nil
-- when the mesh is not uploaded (id 0) or the entry is malformed (the default body part stays). lite = true: the
-- part's `lite` mesh (the v9 set the low detail level wears, Config.Detail.meshes), its own size and attachments; the
-- full mesh when the entry has no usable lite one. frame = the frame id (BodyAssetData.frames): that family's part,
-- the default family's when the frame has none; the lite set is the default family's at every frame
function BodyTiers.PartEntry(tier, name, d, lite, frame)
	d = d or load()
	local tiers, fid = familyOf(d, frame)
	local t = tierOf(tiers, tier)
	local parts = type(t) == "table" and type(t.parts) == "table" and t.parts or nil
	local e = parts and parts[name]
	if type(e) ~= "table" then
		return nil
	end
	local isLite = false
	if lite then
		local le = e.lite
		if not (type(le) == "table" and idOf(le.mesh) and vec3(le.size)) and fid ~= BodyTiers.DEFAULT_FRAME then
			-- (the frames carry no lite set: the default family's lite part)
			local dt = tierOf(type(d) == "table" and d.tiers or nil, tier)
			local de = type(dt) == "table" and type(dt.parts) == "table" and dt.parts[name] or nil
			le = type(de) == "table" and de.lite or nil
		end
		if type(le) == "table" and idOf(le.mesh) and vec3(le.size) then
			e, isLite, fid = le, true, BodyTiers.DEFAULT_FRAME
		end
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
	return { id = id, size = size, attachments = atts, tier = tier, name = name, lite = isLite, frame = fid }
end

-- a tier's gear-fit measure (BodyAssetData tiers[n].fit[key]: { width, depth, girth, y }, unscaled studs), or nil;
-- frame (optional) = that frame's family's measure
function BodyTiers.Fit(tier, key, d, frame)
	d = d or load()
	local tiers = familyOf(d, frame)
	local t = tierOf(tiers, tier)
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

-- Face styles (look.face.style): one of the drawn Boxer faces (the user's pack, tools/body/faces.py PACK): the head
-- wears that drawn face as its front Decal, and FaceFX swaps it for a mood face by mood (STYLE_MOODS). Every boxer
-- has one (DefaultStyle). "built" = the face BuilderHead builds from parts: no longer a player option, only the
-- emergency fallback while no drawn face is uploaded (old "built" saves read as the default drawn face)
BodyTiers.BUILT_STYLE = "built"
-- the resting faces a boxer can wear (the Creator offers them, in this order): the user's four, then the faces
-- drawn after them in the same style (tools/body/wcb_faces_draw.py)
BodyTiers.STYLE_KEYS = {
	"wcb_neutral", "wcb_focused", "wcb_smirk", "wcb_grit",
	"wcb_confident", "wcb_grin", "wcb_cool", "wcb_wink", "wcb_stern", "wcb_determined", "wcb_toothy", "wcb_scarred",
}
-- faces only a mood shows (FaceFX, STYLE_MOODS): never a boxer's chosen face
BodyTiers.STYLE_MOOD_KEYS = { "wcb_shout", "wcb_hurt", "wcb_dazed", "wcb_ko", "wcb_tired", "wcb_surprised" }
-- every drawn face key (resting first); RESTING marks the ones a look may keep
BodyTiers.STYLE_INDEX = {}
BodyTiers.STYLE_RESTING = {}
for i, k in ipairs(BodyTiers.STYLE_KEYS) do
	BodyTiers.STYLE_INDEX[k] = i
	BodyTiers.STYLE_RESTING[k] = true
end
for i, k in ipairs(BodyTiers.STYLE_MOOD_KEYS) do
	BodyTiers.STYLE_INDEX[k] = #BodyTiers.STYLE_KEYS + i
end

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

-- the faces a player picks from in the Creator (creator ~= false); the smile first. The drawn face STYLES
-- (STYLE_KEYS below) are whole-face alternatives to the built face (look.face.style), never a face.key
function BodyTiers.Pickable(d)
	local out = {}
	for _, f in ipairs(BodyTiers.Faces(d)) do
		if f.creator and not BodyTiers.STYLE_INDEX[f.key] then
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
		return f ~= nil and f.creator and not BodyTiers.STYLE_INDEX[k]
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
-- Face styles (look.face.style; the keys are above)
------------------------------------------------------------------------
-- a drawn face key (resting or mood) that is uploaded (an id 0 = not offered)
function BodyTiers.IsDrawnFace(key, d)
	if type(key) ~= "string" or not BodyTiers.STYLE_INDEX[key] then
		return false
	end
	local f = BodyTiers.Face(key, d)
	return f ~= nil and f.id ~= nil
end

-- a drawn style a look may wear (a resting face, uploaded): mood-only faces are never anyone's chosen face
function BodyTiers.IsDrawnStyle(style, d)
	return BodyTiers.STYLE_RESTING[style] == true and BodyTiers.IsDrawnFace(style, d)
end

-- the face style every boxer gets when none was chosen (new boxers, old saves, a "built" save, NPCs without
-- one): the drawn Boxer Neutral, else the first uploaded drawn face, else (no drawn face uploaded at all, an
-- emergency fallback only) the built face
BodyTiers.DEFAULT_STYLE = "wcb_neutral"
function BodyTiers.DefaultStyle(d)
	if BodyTiers.IsDrawnStyle(BodyTiers.DEFAULT_STYLE, d) then
		return BodyTiers.DEFAULT_STYLE
	end
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		if BodyTiers.IsDrawnStyle(k, d) then
			return k
		end
	end
	return BodyTiers.BUILT_STYLE
end

-- true while any drawn face is uploaded: every boxer wears one, and the built face (its parts, its rig and the
-- Creator controls that only shape it) is out of the game
function BodyTiers.DrawnFaces(d)
	return BodyTiers.DefaultStyle(d) ~= BodyTiers.BUILT_STYLE
end

-- the Creator's choices: every uploaded drawn face in STYLE_KEYS order ({ key, name }). The built face is no
-- player option (empty when nothing is uploaded: the emergency built fallback has no UI)
function BodyTiers.FaceStyles(d)
	local out = {}
	for _, k in ipairs(BodyTiers.STYLE_KEYS) do
		if BodyTiers.IsDrawnStyle(k, d) then
			table.insert(out, { key = k, name = BodyTiers.Face(k, d).name })
		end
	end
	return out
end

-- look.face.style from untrusted input: an uploaded drawn style, else the old (saved) one when it is still one,
-- else the default (old saves with no style and "built" saves get the drawn Boxer Neutral)
function BodyTiers.SanitizeFaceStyle(style, old, d)
	if BodyTiers.IsDrawnStyle(style, d) then
		return style
	elseif BodyTiers.IsDrawnStyle(old, d) then
		return old
	end
	return BodyTiers.DefaultStyle(d)
end

-- the drawn style a boxer's head shows: app.face.style when it is drawn and uploaded, else the default drawn face
-- (a missing or "built" style, any look at all). nil only when no drawn face is uploaded (the built fallback)
function BodyTiers.DrawnStyleOf(app, d)
	local face = type(app) == "table" and type(app.face) == "table" and app.face or nil
	local st = face and face.style
	if BodyTiers.IsDrawnStyle(st, d) then
		return st
	end
	local def = BodyTiers.DefaultStyle(d)
	return def ~= BodyTiers.BUILT_STYLE and def or nil
end

-- the look's face keys and options that only shape the part-built face (its eyes, brows, nose and lips, the lip
-- tint the undertone gives): a drawn face draws its own features, so the look editors (LookKit.FaceShown) hide them
-- while drawn faces are in. (tools/sim/test_bodytiers checks each one changes nothing on the drawn face, and every
-- face control left shown changes it)
BodyTiers.BUILT_ONLY = {
	noseWidth = true, noseLength = true, noseBridge = true, lips = true, browThick = true, browHeight = true,
	browAngle = true, mouthWidth = true, asym = true, eyeShape = true, eyeSize = true, eyeDist = true, lashes = true,
	eyeTilt = true, lidHeavy = true, noseBreak = true,
	-- (the birthmark: on a drawn face it always lands on the padded ink, so it is never drawn)
	marks = true,
	browStyle = true, eyeColor = true, eyeColor2 = true, undertone = true, noseType = true,
}
-- the face keys that, on the drawn face, only place the hair (the forehead moves the generated hairline and the
-- built face's brow): with every boxer bald (Config.BaldMode) they change nothing the player can see, so the look
-- editors hide them too
BodyTiers.HAIR_ONLY = { forehead = true }
local function bald()
	local here = script and script.Parent
	local m = here and here:FindFirstChild("Config")
	local ok, cfg = false, nil
	if m then
		ok, cfg = pcall(require, m)
	end
	return ok and type(cfg) == "table" and cfg.BaldMode == true
end
function BodyTiers.FaceControlShown(key, d)
	if not BodyTiers.DrawnFaces(d) then
		return true
	end
	return not (BodyTiers.BUILT_ONLY[key] or (BodyTiers.HAIR_ONLY[key] and bald()))
end

-- the moods (BodyAssetData.expressions' names, MoodOf, plus FaceFX's "guard" / "train") -> a drawn face; nil = the
-- boxer's own chosen (resting) face. A mood whose face is not uploaded keeps the chosen face
BodyTiers.STYLE_MOODS = {
	neutral = nil, rest = nil,
	guard = "wcb_focused", block = "wcb_focused",
	attack = "wcb_determined", train = "wcb_determined",
	effort = "wcb_grit",
	hurt = "wcb_hurt",
	angry = "wcb_shout",
	taunt = "wcb_smirk",
	confident = "wcb_confident",
	happy = "wcb_grin",
	celebrate = "wcb_toothy",
	ko = "wcb_ko",
	stunned = "wcb_dazed", dazed = "wcb_dazed",
	tired = "wcb_tired", lose = "wcb_tired",
	surprised = "wcb_surprised",
}

-- the drawn face a mood shows on a boxer whose chosen style is `chosen` (the chosen face when the mood keeps it or
-- its face is not uploaded)
function BodyTiers.StyleMoodFace(mood, chosen, d)
	local k = type(mood) == "string" and BodyTiers.STYLE_MOODS[mood] or nil
	if k and BodyTiers.IsDrawnFace(k, d) then
		return k
	end
	return chosen
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
