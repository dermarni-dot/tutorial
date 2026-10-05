-- LookData: the exact inputs the anatomy mesh generators read, published by the server on every
-- character model so each client can build the same meshes (EditableMeshes do not replicate).
-- * Model attributes (server writes them change-only in Builder.Cosmetics / Builder.SetDamage):
--     LookData  compact deterministic JSON of the look table below (slow-changing: look, build, rig)
--     LookSig   digest of LookData;  BodySig / HeadSig / HairSig  digests of each section's inputs, so a
--               client only regenerates the section that changed
--     LookFx    JSON of the fight damage table (CONTRACTS section 8), separate because it changes per hit;
--               sweat and grime stay in the existing Sweat / Grime attributes
--   and the CollectionService tag "Anatomy" (AnatomyClient watches it).
-- * Numbers are quantised to 0.001 before encoding and printed with 3 decimals, so
--   Decode(Encode(look)) is bit-identical to look: server (Builder placing face parts at landmarks) and
--   client (meshes) compute from the same doubles. Always compute from LookData.Get(model) / Decode.
-- * Pure functions (Encode / Decode / Digest / Select / Sigs) run anywhere (luaurun tests, renderer);
--   ReadRig / FromBuilder / Publish / PublishFx / Get / Fx take Instances.
--
-- look = {
--   v = 1, g = 1 | 2 (2 = female), skin = Looks.SkinTones index, skinRGB = { r, g, b } (0..255),
--   height (inches), age (years or nil), detail ("full" | "medium" | "low": the server build's detail),
--   scale = { h, w, d } (HumanoidDescription Height / Width / DepthScale),
--   rig = { parts = { [R15 part] = { sx, sy, sz } }, joints = { [Motor6D name] = { p0, p1, c0 = {x,y,z},
--           c1 = {x,y,z} [, r0 = 9 numbers, r1] } } }  -- C0 in Part0 space, C1 in Part1 space (bind pose)
--   face = { shape, every Looks.FaceKeys number, eyeColor, eyeColor2, seed, undertone, browStyle, noseType },
--   battle = { ears, nose, scars = { { kind, side, at, size } } },
--   hair = { style, type, length, density, thickness, growth (preview growth applied), color, hl, hcolor,
--            dye, hairline, part, clump, frizz, volume, curlSize },
--   beard = { style, growth, color },
--   body = { frame, physique (resolved id), arms, chest, shoulders, waist, legs, neck (sliders),
--            lv = { [Config.MuscleParts id] = 0..1.35 level after physique shaping (0.04 steps) },
--            fat (%, 0.5 steps), def (0..1), vein (0..1), bulk (0..1), dry (0..1), vasc (0..100),
--            pv = { elong, flat, groove, waist, taper }, potential },
--   build = { [Config.MuscleParts id] = raw value (whole units), fat, vasc },
--   attire = { trunks, trim (also the female sports top), trunkStyle, outfit, hands },
-- }
local LookData = {}

LookData.VERSION = 1
LookData.ATTR = "LookData"
LookData.SIG_ATTR = "LookSig"
LookData.FX_ATTR = "LookFx"
LookData.TAG = "Anatomy"
LookData.SECTION_ATTR = { Body = "BodySig", Head = "HeadSig", Hair = "HairSig" }
LookData.SECTION_ORDER = { "Body", "Head", "Hair" }

-- the inputs each section's generator may read (dotted paths into the look table). A generator that
-- reads anything else must have it added here, or its meshes go stale when that input changes.
LookData.SECTIONS = {
	Body = { "v", "g", "skin", "skinRGB", "height", "age", "detail", "scale", "rig", "body", "build", "attire" },
	Head = {
		"v", "g", "skin", "skinRGB", "age", "detail", "rig.parts.Head", "rig.joints.Neck", "face", "battle", "beard",
		"hair.color", "body.fat", "body.dry",
	},
	Hair = {
		"v", "g", "skinRGB", "age", "detail", "rig.parts.Head", "hair", "face.seed", "face.shape", "face.forehead",
		"face.skullWidth", "face.skullLength", "face.crown", "face.browRidge", "face.asym",
	},
}

-- round-1 geometry each section hides (locally, once its meshes exist) when its generator gives no
-- Replaces rules; AnatomyClient and the offline renderer both apply these. Rule shapes: { r15 = part },
-- { folder = BoxerLook folder [, names = {...} | except = {...}] }, { tag = CollectionService tag }.
LookData.DEFAULT_REPLACES = {
	Body = {
		{ r15 = "UpperTorso" }, { r15 = "LowerTorso" }, { r15 = "LeftUpperArm" }, { r15 = "RightUpperArm" },
		{ r15 = "LeftLowerArm" }, { r15 = "RightLowerArm" }, { r15 = "LeftUpperLeg" }, { r15 = "RightUpperLeg" },
		{ r15 = "LeftLowerLeg" }, { r15 = "RightLowerLeg" }, { folder = "Muscles" },
	},
	Head = {
		{ r15 = "Head" },
		{ folder = "Face", names = {
			"Ear", "EarHelix", "Cauliflower", "Jaw", "JawAngle", "Chin", "LowerFace", "ChinCleft", "Jowl", "DoubleChin",
			"Cheekbone", "Cheek", "Hollow", "BrowRidge", "Nose", "NoseTip", "Nostril", "NoseBump", "Nasolabial", "Philtrum",
			"LipFold", "Freckle", "Mole", "Scar", "AcneScar", "Acne", "Birthmark", "BattleScar", "BrowGap", "SurgicalScar",
			"Suture", "ForeheadLine", "CrowFeet", "Pore", "Blush", "Crease", "UnderEye",
		} },
	},
	Hair = { { folder = "Hair" } },
}

LookData.R15 = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
-- R15 Motor6D name -> the part it lives in (Part1)
LookData.JOINTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
}

local floor, abs = math.floor, math.abs

------------------------------------------------------------------------
-- Quantising
------------------------------------------------------------------------
local function q(x, step)
	if x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	local v
	if step == nil or step == 0.001 then
		-- k / 1000 is the double nearest to the 3-decimal text the encoder prints: decode is exact
		v = floor(x * 1000 + 0.5) / 1000
	else
		v = floor(x / step + 0.5) * step
	end
	if v == 0 then
		return 0 -- no -0
	end
	return v
end
LookData.Q = q

-- deep copy of plain data with every number quantised (non-data values dropped)
local function quantize(v)
	local t = type(v)
	if t == "number" then
		return q(v)
	elseif t == "string" or t == "boolean" then
		return v
	elseif t == "table" then
		local out = {}
		for k, x in pairs(v) do
			if type(k) == "string" or type(k) == "number" then
				local c = quantize(x)
				if c ~= nil then
					out[k] = c
				end
			end
		end
		return out
	end
	return nil
end
LookData.Quantize = quantize

------------------------------------------------------------------------
-- Deterministic JSON
------------------------------------------------------------------------
local function numStr(v)
	if v ~= v or v == math.huge or v == -math.huge then
		return "0"
	end
	if v == floor(v) and abs(v) < 1e15 then
		return string.format("%d", v)
	end
	local s = string.format("%.3f", v)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then
		return "0"
	end
	return s
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function isArray(t, n)
	local count = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
			return false
		end
		count += 1
	end
	return count == n
end

local function encodeInto(v, out)
	local t = type(v)
	if t == "number" then
		out[#out + 1] = numStr(v)
	elseif t == "string" then
		out[#out + 1] = quote(v)
	elseif t == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif t == "table" then
		local n = #v
		if n > 0 and isArray(v, n) then
			out[#out + 1] = "["
			for i = 1, n do
				if i > 1 then
					out[#out + 1] = ","
				end
				encodeInto(v[i], out)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k, x in pairs(v) do
				local tk = type(k)
				local tx = type(x)
				if (tk == "string" or tk == "number") and (tx == "number" or tx == "string" or tx == "boolean" or tx == "table") then
					keys[#keys + 1] = tostring(k)
				end
			end
			table.sort(keys)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then
					out[#out + 1] = ","
				end
				local x = v[k]
				if x == nil then
					x = v[tonumber(k)]
				end
				out[#out + 1] = quote(k)
				out[#out + 1] = ":"
				encodeInto(x, out)
			end
			out[#out + 1] = "}"
		end
	else
		out[#out + 1] = "null"
	end
end

-- same input -> same text on every machine (sorted keys, fixed number format)
function LookData.Encode(v)
	local out = {}
	encodeInto(v, out)
	return table.concat(out)
end

-- JSON text -> table; returns nil, err on malformed input (never throws)
function LookData.Decode(s)
	if type(s) ~= "string" or s == "" then
		return nil, "no data"
	end
	local pos = 1
	local len = #s
	local function ws()
		pos = s:find("[^ \t\r\n]", pos) or len + 1
	end
	local value
	local function str()
		-- pos at the opening quote
		local out = {}
		local i = pos + 1
		while true do
			local c = s:sub(i, i)
			if c == "" then
				error("unterminated string")
			elseif c == '"' then
				break
			elseif c == "\\" then
				local e = s:sub(i + 1, i + 1)
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if map[e] then
					out[#out + 1] = map[e]
					i += 2
				elseif e == "u" then
					local hex = s:sub(i + 2, i + 5)
					local code = tonumber(hex, 16)
					if not code then
						error("bad \\u escape")
					end
					out[#out + 1] = code < 128 and string.char(code) or utf8.char(code)
					i += 6
				else
					error("bad escape")
				end
			else
				local j = s:find('["\\]', i) or len + 1
				out[#out + 1] = s:sub(i, j - 1)
				i = j
			end
		end
		pos = i + 1
		return table.concat(out)
	end
	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			ws()
			if s:sub(pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				ws()
				if s:sub(pos, pos) ~= '"' then
					error("expected key at " .. pos)
				end
				local k = str()
				ws()
				if s:sub(pos, pos) ~= ":" then
					error("expected ':' at " .. pos)
				end
				pos += 1
				obj[k] = value()
				ws()
				local d = s:sub(pos, pos)
				pos += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					error("expected ',' or '}' at " .. pos)
				end
			end
		elseif c == "[" then
			pos += 1
			local arr = {}
			ws()
			if s:sub(pos, pos) == "]" then
				pos += 1
				return arr
			end
			while true do
				arr[#arr + 1] = value()
				ws()
				local d = s:sub(pos, pos)
				pos += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					error("expected ',' or ']' at " .. pos)
				end
			end
		elseif c == '"' then
			return str()
		elseif s:sub(pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif s:sub(pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif s:sub(pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not num or num == "" then
			error("unexpected '" .. c .. "' at " .. pos)
		end
		pos += #num
		local n = tonumber(num)
		if not n then
			error("bad number " .. num)
		end
		return n
	end
	local ok, res = pcall(function()
		local v = value()
		ws()
		if pos <= len then
			error("trailing data at " .. pos)
		end
		return v
	end)
	if not ok then
		return nil, tostring(res)
	end
	return res
end

-- 16 hex chars (two 32-bit rolling hashes, exact in doubles); the same digest as BuilderKit's
function LookData.Digest(s)
	local h1, h2 = 5381, 0
	for i = 1, #s do
		local c = string.byte(s, i)
		h1 = (h1 * 33 + c) % 4294967296
		h2 = (h2 * 65599 + c) % 4294967296
	end
	return string.format("%08x%08x", h1, h2)
end

------------------------------------------------------------------------
-- Sections
------------------------------------------------------------------------
-- copy of just the given dotted paths (nesting kept)
function LookData.Select(look, paths)
	local out = {}
	for _, path in ipairs(paths) do
		local src, dst = look, out
		local keys = string.split and string.split(path, ".") or {}
		if #keys == 0 then
			for k in path:gmatch("[^%.]+") do
				keys[#keys + 1] = k
			end
		end
		for i, k in ipairs(keys) do
			if type(src) ~= "table" then
				break
			end
			local v = src[k]
			if v == nil then
				break
			end
			if i == #keys then
				dst[k] = v
			else
				if type(dst[k]) ~= "table" then
					dst[k] = {}
				end
				dst = dst[k]
				src = v
			end
		end
	end
	return out
end

function LookData.SectionSig(look, section)
	local paths = LookData.SECTIONS[section]
	if not paths then
		return nil
	end
	return LookData.Digest(LookData.Encode(LookData.Select(look, paths)))
end

function LookData.Sigs(look)
	local out = {}
	for _, name in ipairs(LookData.SECTION_ORDER) do
		out[name] = LookData.SectionSig(look, name)
	end
	return out
end

------------------------------------------------------------------------
-- Server: building and publishing the look
------------------------------------------------------------------------
local function q3(v)
	return { q(v.X), q(v.Y), q(v.Z) }
end

local function rotList(cf)
	local _, _, _, a, b, c, d, e, f, g, h, k = cf:GetComponents()
	if abs(a - 1) + abs(e - 1) + abs(k - 1) + abs(b) + abs(c) + abs(d) + abs(f) + abs(g) + abs(h) < 1e-4 then
		return nil
	end
	return { q(a), q(b), q(c), q(d), q(e), q(f), q(g), q(h), q(k) }
end

-- R15 part sizes and joint offsets as built (scaled by the HumanoidDescription)
function LookData.ReadRig(model)
	local parts, joints = {}, {}
	for _, name in ipairs(LookData.R15) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			parts[name] = q3(p.Size)
		end
	end
	for jname, pname in pairs(LookData.JOINTS) do
		local p = model:FindFirstChild(pname)
		local m = p and p:FindFirstChild(jname)
		if m and m:IsA("Motor6D") and m.Part0 and m.Part1 then
			joints[jname] = {
				p0 = m.Part0.Name, p1 = m.Part1.Name, c0 = q3(m.C0.Position), c1 = q3(m.C1.Position),
				r0 = rotList(m.C0), r1 = rotList(m.C1),
			}
		end
	end
	return { parts = parts, joints = joints }
end

local function copyRGB(c)
	if type(c) == "table" and type(c[1]) == "number" then
		return { c[1], c[2] or 0, c[3] or 0 }
	end
	return nil
end

-- the look table for a model being built by Builder.Cosmetics. sp = Builder.Resolve(app, build, opts)
-- (BuilderBody's body spec), scales = Builder.Scales(app, build, opts). Returns a quantised table.
function LookData.FromBuilder(model, app, build, opts, sp, scales)
	local Shared = script.Parent
	local Looks = require(Shared:WaitForChild("Looks"))
	local Config = require(Shared:WaitForChild("Config"))
	app = type(app) == "table" and app or {}
	opts = type(opts) == "table" and opts or {}
	build = type(build) == "table" and build or {}
	sp = type(sp) == "table" and sp or {}
	local face = type(app.face) == "table" and app.face or {}
	local hair = type(app.hair) == "table" and app.hair or {}
	local beard = type(app.beard) == "table" and app.beard or {}
	local bodyApp = type(app.body) == "table" and app.body or {}
	local attire = type(app.attire) == "table" and app.attire or {}
	local battle = type(app.battle) == "table" and app.battle or {}
	local skin = math.clamp(math.floor(tonumber(app.skin) or 5), 1, #Looks.SkinTones)
	local look = {
		v = LookData.VERSION,
		g = app.gender == 2 and 2 or 1,
		skin = skin,
		skinRGB = copyRGB(Looks.SkinTones[skin]),
		height = tonumber(app.height) or 70,
		age = tonumber(opts.age),
		detail = sp.detail or Config.DetailLevel(opts),
		scale = scales and { h = scales.height, w = scales.width, d = scales.depth } or nil,
		rig = model and LookData.ReadRig(model) or { parts = {}, joints = {} },
	}
	local f = {}
	for _, k in ipairs(Looks.FaceKeys) do
		local v = tonumber(face[k])
		if v then
			f[k] = v
		end
	end
	f.shape, f.undertone, f.browStyle, f.noseType = face.shape, face.undertone, face.browStyle, face.noseType
	f.eyeColor, f.eyeColor2, f.seed = tonumber(face.eyeColor), tonumber(face.eyeColor2), tonumber(face.seed)
	look.face = f
	local scars = {}
	if type(battle.scars) == "table" then
		for i, sc in ipairs(battle.scars) do
			if i <= 6 and type(sc) == "table" then
				scars[#scars + 1] = { kind = tostring(sc.kind or "brow"), side = (tonumber(sc.side) or 1) < 0 and -1 or 1, at = tonumber(sc.at) or 0.5, size = tonumber(sc.size) or 0.5 }
			end
		end
	end
	look.battle = { ears = tonumber(battle.ears) or 0, nose = tonumber(battle.nose) or 0, scars = scars }
	local hr = {}
	for _, k in ipairs({ "style", "type", "dye", "hairline", "part" }) do
		if type(hair[k]) == "string" then
			hr[k] = hair[k]
		end
	end
	for _, k in ipairs({ "length", "density", "thickness", "clump", "frizz", "volume", "curlSize" }) do
		hr[k] = tonumber(hair[k])
	end
	hr.growth = tonumber(opts.previewGrowth) or tonumber(hair.growth) or 0
	hr.color, hr.hcolor, hr.hl = copyRGB(hair.color), copyRGB(hair.hcolor), hair.hl == true
	look.hair = hr
	look.beard = { style = type(beard.style) == "string" and beard.style or "None", growth = tonumber(beard.growth) or 0, color = copyRGB(beard.color) }
	local body = {
		frame = sp.frame and sp.frame.id or bodyApp.frame, physique = sp.ph and sp.ph.id or nil,
		fat = sp.fat, def = sp.def, vein = sp.vein, bulk = sp.bulk, dry = sp.dry,
		vasc = tonumber(build.vasc) or 0, potential = sp.frame and sp.frame.potential or nil,
	}
	for _, k in ipairs({ "arms", "chest", "shoulders", "waist", "legs", "neck" }) do
		body[k] = tonumber(bodyApp[k]) or 0
	end
	if type(sp.lv) == "table" then
		body.lv = table.clone(sp.lv)
	end
	if type(sp.pv) == "table" then
		body.pv = { elong = sp.pv.elong, flat = sp.pv.flat, groove = sp.pv.groove, waist = sp.pv.waist, taper = sp.pv.taper }
	end
	look.body = body
	local bd = { fat = q(tonumber(build.fat) or Config.BodyFat.default, 0.5), vasc = q(tonumber(build.vasc) or 0, 1) }
	for _, p in ipairs(Config.MuscleParts) do
		bd[p.id] = q(Config.PartValue(build, p.id), 1)
	end
	look.build = bd
	look.attire = {
		trunks = copyRGB(attire.trunks), trim = copyRGB(attire.trim), trunkStyle = attire.trunkStyle,
		outfit = opts.outfit, hands = opts.hands or "gloves",
	}
	return quantize(look)
end

local function setAttr(inst, key, value)
	if inst:GetAttribute(key) ~= value then
		inst:SetAttribute(key, value)
	end
end

-- writes LookData / LookSig / section sigs (change-only) and tags the model; returns the encoded string
-- and whether anything changed
function LookData.Publish(model, look)
	local str = LookData.Encode(look)
	local changed = model:GetAttribute(LookData.ATTR) ~= str
	if changed then
		-- section sigs first: a client that sees the new LookSig already sees which sections moved
		local sigs = LookData.Sigs(look)
		for name, attr in pairs(LookData.SECTION_ATTR) do
			setAttr(model, attr, sigs[name])
		end
		model:SetAttribute(LookData.ATTR, str)
		setAttr(model, LookData.SIG_ATTR, LookData.Digest(str))
	end
	pcall(function()
		local CollectionService = game:GetService("CollectionService")
		if not CollectionService:HasTag(model, LookData.TAG) then
			CollectionService:AddTag(model, LookData.TAG)
		end
	end)
	return str, changed
end

local DMG_KEYS = {
	"leftEye", "rightEye", "cut", "cutSide", "cut2", "cutSide2", "noseBleed", "bruise", "lip", "cheekL", "cheekR",
	"forehead", "earL", "earR", "redness", "ribsL", "ribsR", "age",
}
-- the fight damage table (0.01 steps) as the LookFx attribute; nil / {} clears it
function LookData.PublishFx(model, dmg)
	local out = {}
	local any = false
	if type(dmg) == "table" then
		for _, k in ipairs(DMG_KEYS) do
			local v = tonumber(dmg[k])
			if v and v ~= 0 then
				out[k] = q(v, 0.01)
				any = true
			end
		end
		if dmg.nose == true then
			out.nose = true
			any = true
		end
	end
	setAttr(model, LookData.FX_ATTR, any and LookData.Encode(quantize(out)) or nil)
end

------------------------------------------------------------------------
-- Either side: reading
------------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "k" })
-- decoded look of a model (cached until its LookData string changes); nil when absent / malformed
function LookData.Get(model)
	local str = model:GetAttribute(LookData.ATTR)
	if type(str) ~= "string" then
		return nil
	end
	local c = cache[model]
	if c and c.str == str then
		return c.look, str
	end
	local look = LookData.Decode(str)
	if type(look) ~= "table" then
		return nil
	end
	cache[model] = { str = str, look = look }
	return look, str
end

-- the fast-changing extras: { dmg = {...}, sweat = 0..1, grime = 0..1, tier = 0..4 }
function LookData.Fx(model)
	local dmg = LookData.Decode(model:GetAttribute(LookData.FX_ATTR) or "")
	return {
		dmg = type(dmg) == "table" and dmg or {},
		sweat = tonumber(model:GetAttribute("Sweat")) or 0,
		grime = tonumber(model:GetAttribute("Grime")) or 0,
		tier = tonumber(model:GetAttribute("FaceDmgTier")) or 0,
	}
end

return LookData
