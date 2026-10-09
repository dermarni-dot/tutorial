-- Builder: turns a boxer's look data into a 3D character (server side). Public facade.
-- * Scales / Description / ScaleKey: frame + physique scaling through a HumanoidDescription
-- * Cosmetics / Apply / CreateNPC: build every procedural layer on a character, in order, with
--   per-folder rebuild caching, detail levels and the CONTRACTS section 4 opts
-- The layers live in sub-modules that share the part helpers in BuilderKit:
-- * BuilderHead: procedural face, beard, fight damage, sweat shine, sparring headgear
-- * BuilderHair: hair styles x hair types, strands, sway joints, hair under headgear / hoods, wet hair
-- * BuilderBody: skin/trunks/shoe colours, muscles, attire, gloves and wraps, robe, body sweat / bruises
-- FaceLayout, SetDamage, SetSweat, SetHeadgear, SetHairHidden and SetRobe are forwarded from them.
-- Every Cosmetics run also publishes LookData (+ LookSig and the Body / Head / Hair section sigs) on the
-- model, change-only, and SetDamage publishes LookFx: the inputs the client-side anatomy meshes are
-- generated from (LookData.lua, ANATOMY_CONTRACTS.md).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))
local Head = require(script.Parent:WaitForChild("BuilderHead"))
local Hair = require(script.Parent:WaitForChild("BuilderHair"))
local Body = require(script.Parent:WaitForChild("BuilderBody"))
local LookData = require(script.Parent:WaitForChild("LookData"))

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
-- Athletic proportions. The default R15 body is Roblox's "Classic" block: about 4.5 heads tall, the hip
-- pivot at 38 % of the height. Humanoid scaling blends every part toward Rthro as BodyTypeScale goes to 1
-- (legs x 1.5, torso x 1.31, arms x 1.34, head x 0.94 tall) and ProportionScale blends Rthro Normal toward
-- Slender (narrower shoulders and limbs, slightly shorter legs). With the head brought down to a real
-- head's share a 70-inch boxer stands about 6.5 studs and 7.3 heads, hip pivot at 45 %, shoulders at 81 %,
-- wrists at 50 % (a real athlete: 7-7.5 heads, about 47 / 82 / 48 %). The meshes and the round-1 parts all
-- follow the rig the engine builds; HipHeight follows automatically.
-- Per frame (bone structure, never the trained physique: legs do not grow from bench pressing): lean frames
-- take the full Rthro length, heavier frames keep a little of the Classic block (shorter legs, a heavier
-- head and neck) on top of their extra width. Women: a touch of Slender (shoulders narrower than the hips).
local FRAME_PROPORTIONS = {
	Lean = { bodyType = 1, head = 0.81 },
	Athletic = { bodyType = 1, head = 0.82 },
	Muscular = { bodyType = 0.96, head = 0.83 },
	["Power Build"] = { bodyType = 0.92, head = 0.84 },
	["Heavyweight Build"] = { bodyType = 0.87, head = 0.85 },
}
Builder.FRAME_PROPORTIONS = FRAME_PROPORTIONS
-- The R15 boxes are fat for their length (a Classic limb is nearly as wide as it is long, the torso box 2 studs
-- across with the arms hung outside it): at Rthro length an untouched width still reads as a toy. Every
-- frame's width and depth are taken down so the shoulders land at about a quarter of the height, the limbs
-- and the chest at an athlete's thickness; the frame, the physique and training still widen from there.
local SLIM_W, SLIM_D = 0.77, 0.84

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
	local pr = FRAME_PROPORTIONS[frame.id] or FRAME_PROPORTIONS.Athletic
	return {
		height = math.clamp((app.height or 70) / 70, 0.86, 1.2),
		width = math.clamp(width, 0.75, 1.4) * SLIM_W,
		depth = math.clamp(depth, 0.75, 1.4) * SLIM_D,
		bodyType = pr.bodyType,
		proportion = female and 0.25 or 0,
		head = pr.head * (female and 0.97 or 1),
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
	desc.HeadScale = sc.head
	desc.BodyTypeScale = sc.bodyType
	desc.ProportionScale = sc.proportion
	return desc
end

-- quantised to 0.01 so training only re-applies the description (which yields) on real changes; "p2" =
-- the athletic-proportions rig (characters scaled under the old Classic key re-apply once)
function Builder.ScaleKey(app, build, opts)
	local sc = Builder.Scales(app, build, opts)
	return string.format("%.2f|%.2f|%.2f|%d|%.2f|%.2f|%.2f|p2", sc.height, sc.width, sc.depth, app.gender or 1, sc.bodyType, sc.proportion, sc.head)
end

------------------------------------------------------------------------
-- Head / body API (implemented in BuilderHead / BuilderBody)
------------------------------------------------------------------------
-- returns head-local positions for face features (shared with damage visuals)
Builder.FaceLayout = Head.FaceLayout -- (head, face)

-- dmg = the CONTRACTS section 8 table (every field optional): face damage (Head) + rib bruises (Body);
-- also published as the LookFx attribute for the anatomy meshes (change-only)
function Builder.SetDamage(model, app, dmg)
	dmg = type(dmg) == "table" and dmg or {}
	step("SetDamage", Head.SetDamage, model, app, dmg)
	step("Body.SetDamage", Body.SetDamage, model, app, dmg)
	step("LookFx", LookData.PublishFx, model, dmg)
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
	step("SetHairHidden", Hair.SetHairHidden, model, region, on)
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

-- The head is scaled (HeadScale x the body-type factor), and BuilderHead swaps the default dynamic head (a
-- MeshPart) for a plain Part of the same size once. Humanoid:ReplaceBodyPartR15 scales the new part "as
-- normal", so the engine may take that already-scaled size as unscaled and scale it a second time (with the
-- old Classic HeadScale 1 that was harmless). headRecord / keepHeadScale put back the size, the OriginalSize
-- record and the attachments the engine gave the original head, and re-aim the neck: the head is scaled
-- exactly once. A no-op when the swap kept the size (the simulator's ReplaceBodyPartR15 does).
local function headRecord(model)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local orig = head:FindFirstChild("OriginalSize")
	local rec = { part = head, size = head.Size, orig = orig and orig:IsA("Vector3Value") and orig.Value or nil, att = {} }
	for _, c in ipairs(head:GetChildren()) do
		if c:IsA("Attachment") then
			rec.att[c.Name] = c.CFrame
		end
	end
	return rec
end

-- true when the head had to be corrected (its folders were built on the wrong size: rebuild them)
local function keepHeadScale(model, rec)
	local head = model:FindFirstChild("Head")
	if not (rec and head and head ~= rec.part and head:IsA("BasePart")) then
		return false
	end
	local fixed = false
	if (head.Size - rec.size).Magnitude > 1e-3 then
		head.Size = rec.size
		fixed = true
	end
	if rec.orig then
		local o = head:FindFirstChild("OriginalSize")
		if not (o and o:IsA("Vector3Value")) then
			o = Instance.new("Vector3Value")
			o.Name = "OriginalSize"
			o.Parent = head
		end
		if o.Value ~= rec.orig then
			o.Value = rec.orig
		end
	end
	for name, cf in pairs(rec.att) do
		local a = head:FindFirstChild(name)
		if a and a:IsA("Attachment") and (a.CFrame.Position - cf.Position).Magnitude > 1e-4 then
			a.CFrame = cf
			fixed = true
		end
	end
	local neck, na = head:FindFirstChild("Neck"), head:FindFirstChild("NeckRigAttachment")
	if neck and neck:IsA("Motor6D") and na and na:IsA("Attachment") and (neck.C1.Position - na.CFrame.Position).Magnitude > 1e-4 then
		neck.C1 = na.CFrame
		fixed = true
	end
	return fixed
end

-- the neck: the engine's R15 rig puts the Neck pivot at the base of the head, so the chin sits on the
-- trapezius. The Head's NeckRigAttachment (and Neck.C1) go lower in head space by a share of the head's
-- height: the head rides higher on the same torso (HipHeight, the torso and every other joint unchanged) and
-- the Head mesh's own neck (AnatomySkull.Neck follows rig.joints.Neck C1) runs from the jaw down to the
-- pivot. Absolute (from the head's size): idempotent across rebuilds, rescales and head swaps.
local NECK_LIFT = { 0.26, 0.22 } -- x the head's height: men, women
local function liftHead(model, app)
	local head = model:FindFirstChild("Head")
	local na = head and head:FindFirstChild("NeckRigAttachment")
	if not (head and head:IsA("BasePart") and na and na:IsA("Attachment")) then
		return
	end
	local hy = head.Size.Y
	local y = -0.5 * hy - NECK_LIFT[app and app.gender == 2 and 2 or 1] * hy
	local p = na.Position
	if math.abs(p.Y - y) > 1e-4 then
		na.Position = Vector3.new(p.X, y, p.Z)
	end
	local neck = head:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") and (neck.C1.Position - na.CFrame.Position).Magnitude > 1e-4 then
		neck.C1 = na.CFrame
	end
end

-- Head.Face(model, app, opts, build) / Hair.Build(model, app, opts) / Head.Beard(model, app, opts)
local function headStep(model, app, build, opts, name)
	local key = headSig(model, app, build, opts, name)
	if Kit.cached(model, name, key) then
		return
	end
	local ok
	if name == "Face" then
		ok = step("Face", Head.Face, model, app, opts, build)
	elseif name == "Hair" then
		ok = step("Hair", Hair.Build, model, app, opts)
	else
		ok = step(name, Head[name], model, app, opts)
	end
	if ok then
		Kit.seal(model, name, key)
	end
end

-- the Face step (which may swap the head), kept at the engine's head scale; the face is rebuilt once on the
-- corrected head (its size is in the Face cache key) when the swap changed it
local function faceStep(model, app, build, opts)
	-- quiet pcalls: the guard is a safety net, it must never cost a face
	local okR, rec = pcall(headRecord, model)
	headStep(model, app, build, opts, "Face")
	local okK, fixed = pcall(keepHeadScale, model, okR and rec or nil)
	if okK and fixed then
		-- the face was sealed under the key taken before the swap (the original head's size, which the corrected
		-- head has again): drop the seal so the folder really is rebuilt on the corrected head
		local look = model:FindFirstChild("BoxerLook")
		local face = look and look:FindFirstChild("Face")
		if face then
			face:SetAttribute("Sig", nil)
		end
		headStep(model, app, build, opts, "Face")
	end
	pcall(liftHead, model, app)
end

------------------------------------------------------------------------
-- LookData (anatomy meshes): what the clients build each character's meshes from
------------------------------------------------------------------------
-- cheap and change-only: the encoded look is compared with the attribute before anything is written.
-- look.attire.gear: what the boxer wears on the hands and feet (the Body meshes draw the gloves / wraps /
-- shoes); a head-only preview rebuild (gear = nil) keeps the gear the last full build published
local function publishLook(model, app, build, opts, sp, gear)
	sp = sp or Body.Resolve(app, build, opts, model)
	local look = LookData.FromBuilder(model, app, build, opts, sp, Builder.Scales(app, build, opts))
	if type(look.attire) == "table" then
		if gear ~= nil then
			local ok, g = pcall(Body.GearLook, app, gear, opts)
			if ok and type(g) == "table" then
				look.attire.gear = LookData.Quantize(g)
			end
		else
			local prev = LookData.Get(model)
			local g = prev and type(prev.attire) == "table" and prev.attire.gear
			if type(g) == "table" then
				look.attire.gear = g
			end
		end
	end
	LookData.Publish(model, look)
end

------------------------------------------------------------------------
-- Public entry points
------------------------------------------------------------------------
-- opts (all optional, CONTRACTS section 4): hands = "gloves"|"wraps"|"bare", mouthguard, name, nick,
-- nat, waistText, robe, detail ("full"|"medium"|"low"), damage, sweat, grime, age, tier, physique,
-- fightNight, sponsorTrunks / sponsorRobe ({ text, fg, bg }), dry, outfit ("referee"|"cornerman"),
-- only ({ Face, Hair, Beard }), previewGrowth. gear = { gloves, glovesCond, wraps, wrapsCond, shoes,
-- shoesCond, mouthguard, robe } (missing ids default to the starter kit).
-- An NPC marked HullOnly (CreateNPC, medium detail with the anatomy meshes on) drops the tagged muscle
-- domes of its Muscles folder (part + weld + SpecialMesh each) and keeps the hull, neck, fat and the
-- female bust (the shape under the sports top): the Body meshes replace the whole layer on every capable
-- client, and the hull alone still reads as a rounded body on a client without them. The folder's
-- envelope attributes (what Attire fits) stay. Change-only: a cached (sealed) folder was trimmed when
-- it was built.
local function hullOnly(model)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Muscles")
	if not (f and f:GetAttribute("Hull") == true) then
		return -- low detail has no hull: its few domes are all the body it has
	end
	for _, p in ipairs(f:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("Layer") ~= nil and p.Name ~= "Bust" then
			p:Destroy()
		end
	end
end

function Builder.Cosmetics(model, app, build, gear, opts)
	opts = opts or {}
	app = app or Looks.Defaults(1)
	-- preview path: rebuild only the requested head folders, in order
	if type(opts.only) == "table" then
		for _, name in ipairs({ "Face", "Hair", "Beard" }) do
			if opts.only[name] then
				if name == "Face" then
					faceStep(model, app, build, opts)
				else
					headStep(model, app, build, opts, name)
				end
			end
		end
		-- a rebuilt face reopens swollen lids and clears the sclera / mouthguard tint: redraw the damage
		if opts.only.Face and type(opts.damage) == "table" then
			Builder.SetDamage(model, app, opts.damage)
		end
		Builder.SetSweat(model, app, opts.sweat or model:GetAttribute("Sweat") or 0)
		-- previews (Creator / barber) change the look too: the meshes follow
		step("LookData", publishLook, model, app, build, opts, nil)
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
	faceStep(model, app, build, opts)
	headStep(model, app, build, opts, "Hair")
	headStep(model, app, build, opts, "Beard")
	local _, env = step("Muscles", Body.Muscles, model, app, build, opts, sp, gear)
	if model:GetAttribute("HullOnly") == true then
		step("HullOnly", hullOnly, model)
	end
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
		step("LookFx", LookData.PublishFx, model, nil)
		look = model:FindFirstChild("BoxerLook")
		local dmg = look and look:FindFirstChild("Damage")
		if dmg then
			dmg:Destroy()
		end
	end
	Builder.SetSweat(model, app, opts.sweat or model:GetAttribute("Sweat") or 0)
	-- last: the rig is final (head swap, rescale) and every attribute above is set
	step("LookData", publishLook, model, app, build, opts, sp, gear)
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
	-- gym members / officials: hull-only muscle layer (see hullOnly); players and opponents are full
	local anatomy = Config.Anatomy
	if anatomy and anatomy.enabled and anatomy.npcHullOnly and Config.DetailLevel(opts) == "medium" then
		model:SetAttribute("HullOnly", true)
	end
	Builder.Cosmetics(model, app, build, gear, opts)
	return model
end

return Builder
