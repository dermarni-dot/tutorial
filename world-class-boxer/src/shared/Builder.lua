-- Builder: turns a boxer's look data into a 3D character (server side). Public facade.
-- * Scales / Description / ScaleKey: frame + physique scaling through a HumanoidDescription
-- * Cosmetics / Apply / CreateNPC: build every procedural layer on a character, in order, with
--   per-folder rebuild caching, detail levels and the CONTRACTS section 4 opts
-- The layers live in sub-modules that share the part helpers in BuilderKit:
-- * BuilderHead: procedural face, hair, beard, fight damage, sweat shine, sparring headgear
-- * BuilderBody: skin/trunks/shoe colours, muscles, attire, gloves and wraps, robe, body sweat / bruises
-- FaceLayout, SetDamage, SetSweat, SetHeadgear, SetHairHidden and SetRobe are forwarded from them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))
local Head = require(script.Parent:WaitForChild("BuilderHead"))
local Body = require(script.Parent:WaitForChild("BuilderBody"))

local Builder = {}

local frameOf, avgDev = Body.frameOf, Body.avgDev
local setAttr = Kit.setAttr

-- run one build step; a failing layer warns instead of taking the whole character down with it
local function step(name, fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		warn("[Boxer] " .. name .. " failed:", res)
	end
	return ok, res
end

------------------------------------------------------------------------
-- Scales / HumanoidDescription
------------------------------------------------------------------------
-- opts (optional) carries the physique (Career.LookOpts): archetypes widen / narrow the frame
function Builder.Scales(app, build, opts)
	local frame = frameOf(app)
	local b = app.body or {}
	local female = app.gender == 2
	local fat = build and tonumber(build.fat) or 14
	local upper = avgDev(build, { "shoulders", "back", "chest" })
	local ph = Body.Resolve(app, build, opts).ph
	local width = frame.width * (1 + 0.12 * upper + 0.05 * (b.shoulders or 0)) * (female and 0.92 or 1) + (ph.width or 0)
	local depth = frame.depth * (1 + 0.08 * avgDev(build, { "chest" }) + 0.012 * (fat - 14) + 0.04 * (b.chest or 0)) * (female and 0.94 or 1) + (ph.depth or 0)
	return {
		height = math.clamp((app.height or 70) / 70, 0.86, 1.2),
		width = math.clamp(width, 0.75, 1.4),
		depth = math.clamp(depth, 0.75, 1.4),
	}
end

function Builder.Description(app, build, opts)
	local desc = Instance.new("HumanoidDescription")
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	desc.HeadColor = skin
	desc.TorsoColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	-- legs are skin: the trunks are separate loose shells built over the thighs
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	local sc = Builder.Scales(app, build, opts)
	desc.HeightScale = sc.height
	desc.WidthScale = sc.width
	desc.DepthScale = sc.depth
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	return desc
end

-- quantised to 0.01 so training only re-applies the description (which yields) on real changes
function Builder.ScaleKey(app, build, opts)
	local sc = Builder.Scales(app, build, opts)
	return string.format("%.2f|%.2f|%.2f|%d", sc.height, sc.width, sc.depth, app.gender or 1)
end

------------------------------------------------------------------------
-- Head / body API (implemented in BuilderHead / BuilderBody)
------------------------------------------------------------------------
-- returns head-local positions for face features (shared with damage visuals)
Builder.FaceLayout = Head.FaceLayout -- (head, face)

-- dmg = the CONTRACTS section 8 table (every field optional): face damage (Head) + rib bruises (Body)
function Builder.SetDamage(model, app, dmg)
	dmg = type(dmg) == "table" and dmg or {}
	step("SetDamage", Head.SetDamage, model, app, dmg)
	step("Body.SetDamage", Body.SetDamage, model, app, dmg)
end

-- level 0..1: skin / hair / beard (Head, writes the Sweat attribute) then muscles / gloves / wraps (Body)
function Builder.SetSweat(model, app, level)
	level = math.clamp(tonumber(level) or 0, 0, 1)
	step("SetSweat", Head.SetSweat, model, app, level)
	step("Body.SetSweat", Body.SetSweat, model, app, level)
	-- belt and braces: the attribute is the single source of truth, quantised (0.05) and change-only
	setAttr(model, "Sweat", math.floor(level * 20 + 0.5) / 20)
end

function Builder.SetHeadgear(model, color, on)
	step("SetHeadgear", Head.SetHeadgear, model, color, on)
end

-- region = "hood" | "headgear"
function Builder.SetHairHidden(model, region, on)
	step("SetHairHidden", Head.SetHairHidden, model, region, on)
end

Builder.SetRobe = Body.SetRobe -- (model, app, on, opts)

-- face damage stage 0..4 (the Config thresholds; never re-implemented here)
function Builder.DamageLevel(dmg)
	return (Config.FaceDamageStage(dmg))
end

-- visual archetype id the body is drawn with (opts.physique > app.body.physique > classification)
function Builder.Physique(app, build, opts)
	return Body.Resolve(app, build, opts).ph.id
end
Builder.Resolve = Body.Resolve -- (app, build, opts) -> body spec (levels, fat, definition, veins, detail)

------------------------------------------------------------------------
-- Rebuild caching for the head steps (the body steps cache themselves in BuilderBody)
------------------------------------------------------------------------
-- opts keys the head steps never read (grime is keyed below as the quantised value the face really uses);
-- everything else that is a plain value goes in the signature
local HEAD_SIG_SKIP = {
	sweat = true, hands = true, robe = true, waistText = true, name = true, nick = true, nat = true,
	fightNight = true, physique = true, tier = true, sponsorTrunks = true, sponsorRobe = true, grime = true,
}
-- Inputs the head steps read beyond the plain opts. Face = face fat, opts.grime (stored on the face
-- folder as OptGrime), the mouthguard colour and its bloodied tint (opts.damage.lip > 0.6), and only the
-- hair / beard fields it really uses (Head.FaceSigParts: brow colour, lips covered), so a barber visit
-- never rebuilds the face. The Grime ATTRIBUTE (CONTRACTS section 7: I sets it after roadwork, the
-- shower clears it) is deliberately not in the key: BuilderHead draws face dirt in its own FaceGrime
-- folder from that attribute on every Head.SetSweat, which Cosmetics always runs last, so roadwork and
-- the shower never cost a full face rebuild.
local function headSig(model, app, build, opts, name)
	local o = {}
	for k, v in pairs(opts) do
		local t = type(v)
		if (t == "number" or t == "string" or t == "boolean") and not HEAD_SIG_SKIP[k] then
			o[k] = v
		end
	end
	local head = model:FindFirstChild("Head")
	local fat, extra = 0, false
	local hair, beard = app.hair, app.beard
	if name == "Face" then
		-- whole percent steps are plenty for cheeks / jowls
		fat = build and tonumber(build.fat) or 0
		local at = type(app.attire) == "table" and app.attire or {}
		local og = tonumber(opts.grime)
		local dmg = type(opts.damage) == "table" and opts.damage or nil
		extra = {
			grime = og and math.floor(math.clamp(og, 0, 1) * 10 + 0.5) or "attr",
			guard = opts.mouthguard and (at.mouthguard or true) or false,
			guardBlood = opts.mouthguard and dmg ~= nil and (tonumber(dmg.lip) or 0) > 0.6 or false,
		}
		if type(Head.FaceSigParts) == "function" then
			local ok, parts = pcall(Head.FaceSigParts, app)
			if ok and type(parts) == "table" then
				hair, beard = parts, false
			end
		end
	end
	-- HD2: folders sealed under the old key rebuild once
	return Kit.sig("HD2", name, app.gender, app.skin, app.height, app.face, hair, beard, app.battle, o,
		math.floor(fat + 0.5), head and head.Size or false, Config.BaldMode, extra)
end

-- Head.Face(model, app, opts, build) / Head.Hair(model, app, opts) / Head.Beard(model, app, opts)
local function headStep(model, app, build, opts, name)
	local key = headSig(model, app, build, opts, name)
	if Kit.cached(model, name, key) then
		return
	end
	local ok
	if name == "Face" then
		ok = step("Face", Head.Face, model, app, opts, build)
	else
		ok = step(name, Head[name], model, app, opts)
	end
	if ok then
		Kit.seal(model, name, key)
	end
end

------------------------------------------------------------------------
-- Public entry points
------------------------------------------------------------------------
-- opts (all optional, CONTRACTS section 4): hands = "gloves"|"wraps"|"bare", mouthguard, name, nick,
-- nat, waistText, robe, detail ("full"|"medium"|"low"), damage, sweat, grime, age, tier, physique,
-- fightNight, sponsorTrunks / sponsorRobe ({ text, fg, bg }), dry, outfit ("referee"|"cornerman"),
-- only ({ Face, Hair, Beard }), previewGrowth. gear = { gloves, glovesCond, wraps, wrapsCond, shoes,
-- shoesCond, mouthguard, robe } (missing ids default to the starter kit).
function Builder.Cosmetics(model, app, build, gear, opts)
	opts = opts or {}
	app = app or Looks.Defaults(1)
	-- preview path: rebuild only the requested head folders, in order
	if type(opts.only) == "table" then
		for _, name in ipairs({ "Face", "Hair", "Beard" }) do
			if opts.only[name] then
				headStep(model, app, build, opts, name)
			end
		end
		Builder.SetSweat(model, app, opts.sweat or model:GetAttribute("Sweat") or 0)
		return
	end
	gear = Body.Gear(gear)
	local sp = Body.Resolve(app, build, opts, model)
	-- hair hidden under a headgear / hood that is gone (fight cleanup destroys those folders directly)
	local look = model:FindFirstChild("BoxerLook")
	local hg = look and look:FindFirstChild("Headgear")
	if model:GetAttribute("HairHiddenHeadgear") and not (hg and #hg:GetChildren() > 0) then
		Builder.SetHairHidden(model, "headgear", false)
	end
	local robe = look and look:FindFirstChild("Robe")
	if model:GetAttribute("HairHiddenHood") and not (robe and robe:FindFirstChild("Hood")) then
		Builder.SetHairHidden(model, "hood", false)
	end
	step("Colors", Body.Colors, model, app, gear, opts)
	headStep(model, app, build, opts, "Face")
	headStep(model, app, build, opts, "Hair")
	headStep(model, app, build, opts, "Beard")
	local _, env = step("Muscles", Body.Muscles, model, app, build, opts, sp, gear)
	step("Attire", Body.Attire, model, app, opts, gear, sp, type(env) == "table" and env or nil)
	step("Hands", Body.Hands, model, app, gear, opts, sp)
	-- body attributes the client reads (stance, veins, LOD); change-only
	setAttr(model, "Female", app.gender == 2)
	setAttr(model, "Frame", sp.frame.id)
	setAttr(model, "Physique", sp.ph.id)
	setAttr(model, "Bulk", sp.bulk)
	setAttr(model, "Definition", sp.def)
	setAttr(model, "VeinLevel", sp.vein)
	setAttr(model, "Detail", sp.detail)
	-- damage and sweat go on last: rebuilt layers reset materials and eyelids
	if type(opts.damage) == "table" then
		Builder.SetDamage(model, app, opts.damage)
	else
		-- the face may be cached: reopen eyes an earlier SetDamage swelled shut, then drop the folder
		step("SetDamage", Head.SetDamage, model, app, {})
		look = model:FindFirstChild("BoxerLook")
		local dmg = look and look:FindFirstChild("Damage")
		if dmg then
			dmg:Destroy()
		end
	end
	Builder.SetSweat(model, app, opts.sweat or model:GetAttribute("Sweat") or 0)
end

-- Apply to a live player character (yields). Re-scales only when the body changed.
function Builder.Apply(character, app, build, gear, opts)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local key = Builder.ScaleKey(app, build, opts)
	if character:GetAttribute("ScaleKey") ~= key then
		local ok, err = pcall(function()
			hum:ApplyDescription(Builder.Description(app, build, opts))
		end)
		if not ok then
			warn("[Boxer] ApplyDescription failed:", err)
		end
		character:SetAttribute("ScaleKey", key)
	end
	if character.Parent then
		Builder.Cosmetics(character, app, build, gear, opts)
	end
end

function Builder.CreateNPC(app, build, gear, displayName, opts)
	local model
	local ok, err = pcall(function()
		model = Players:CreateHumanoidModelFromDescription(Builder.Description(app, build, opts), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Boxer] CreateHumanoidModelFromDescription failed:", err)
		return nil
	end
	model.Name = displayName or "Boxer"
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = displayName or "Boxer"
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	Builder.Cosmetics(model, app, build, gear, opts)
	return model
end

return Builder
