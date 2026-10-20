-- Builder: turns a boxer's look data into a 3D character (server side). Public facade.
-- * Scales / Description / ScaleKey: the standard R15 body's HumanoidDescription (height, frame, gender)
-- * Tiers: the muscle tier of every body part from the build (BodyTiers); BuilderTiers swaps the parts
-- * Cosmetics / Apply / CreateNPC: build every layer on a character, in order, with per-folder rebuild
--   caching, detail levels and the CONTRACTS section 4 opts
-- The layers live in sub-modules that share the part helpers in BuilderKit:
-- * BuilderTiers: the 14 muscle-tier body parts (Humanoid:ReplaceBodyPartR15, only on a tier change)
-- * BuilderHead: the classic head and the face built on it (Parts, a FaceFX rig), beard, fight damage, sweat, headgear
--   (every boxer wears it while Config.AlwaysHeadgear: a Cosmetics step, recoloured by SetHeadgear while sparring)
-- * BuilderHair: hair styles x hair types, strands, sway joints, hair under headgear / hoods, wet hair
-- * BuilderBody: skin/trunks/shoe colours, attire, gloves and wraps, robe, body sweat / bruises
-- FaceLayout, SetDamage, SetSweat, SetHeadgear, SetHairHidden and SetRobe are forwarded from them.
-- Every Cosmetics run also publishes LookData (+ LookSig and the section sigs) on the model, change-only, and
-- SetDamage publishes LookFx: the inputs the client-side asset hair is built from (LookData.lua).
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
local BodyTiers = require(script.Parent:WaitForChild("BodyTiers"))
local BuilderTiers = require(script.Parent:WaitForChild("BuilderTiers"))
local AvatarLook = require(script.Parent:WaitForChild("AvatarLook"))

local Builder = {}

local frameOf = Body.frameOf
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
-- The standard R15 body (tools/body/CONTRACT.md): the description has empty body-part ids (the engine's default
-- parts), BodyTypeScale 0 and ProportionScale 0, and BuilderTiers then swaps the 14 non-head parts for their
-- muscle-tier MeshParts. The tiers are modelled at the game's proportions (the athletic 70-inch Athletic man the
-- old Rthro blend made: about 6.2 studs, 7 heads), so Height / Width / Depth only carry the boxer's height, his
-- frame's build (BodyTypes width / depth) and the women's narrower shoulders; training never widens the frame
-- (the tiers carry the muscle). The head is the standard head at the frame's head share: FRAME_PROPORTIONS'
-- head x RTHRO_HEAD (what BodyTypeScale 1 used to take off it), so it stays the size it was (0.927 studs).
-- With every id 0 the default parts stay: the classic block body at these scales.
local FRAME_PROPORTIONS = {
	Lean = { head = 0.81 },
	Athletic = { head = 0.82 },
	Muscular = { head = 0.83 },
	["Power Build"] = { head = 0.84 },
	["Heavyweight Build"] = { head = 0.85 },
}
Builder.FRAME_PROPORTIONS = FRAME_PROPORTIONS
local RTHRO_HEAD = 0.942

-- (build, opts: kept for the callers; the physique and training no longer change the scales)
function Builder.Scales(app, build, opts)
	local frame = frameOf(app)
	local female = app.gender == 2
	local pr = FRAME_PROPORTIONS[frame.id] or FRAME_PROPORTIONS.Athletic
	return {
		height = math.clamp((app.height or 70) / 70, 0.86, 1.2),
		width = math.clamp(frame.width * (female and 0.92 or 1), 0.7, 1.4),
		depth = math.clamp(frame.depth * (female and 0.94 or 1), 0.7, 1.4),
		bodyType = 0,
		proportion = 0,
		head = pr.head * RTHRO_HEAD * (female and 0.97 or 1),
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
	-- a player's own avatar hair and face (opts.avatar = an AvatarLook record; players only, never NPCs): the
	-- engine loads and attaches the hair accessories and puts on the face / Dynamic Head. Nothing else of the
	-- avatar is copied: the body stays the muscle-tier body
	local av = opts and opts.avatar
	if type(av) == "table" then
		if av.useHair then
			desc.HairAccessory = av.hair or ""
		end
		desc.Face = av.face or 0
		desc.Head = av.head or 0
	end
	return desc
end

-- quantised to 0.01 so only real changes re-apply the description (which yields); "p3" = the standard R15
-- body at BodyTypeScale 0 (characters scaled under an older key re-apply once)
-- body at BodyTypeScale 0 (characters scaled under an older key re-apply once). A player's avatar hair / face
-- (opts.avatar) adds its AvatarLook.Key: a new avatar, the setting turned on / off re-apply once; the game
-- look's key is exactly the old one
function Builder.ScaleKey(app, build, opts)
	local sc = Builder.Scales(app, build, opts)
	local av = AvatarLook.Key(opts and opts.avatar)
	return string.format("%.2f|%.2f|%.2f|%d|%.2f|%.2f|%.2f|%sp3", sc.height, sc.width, sc.depth, app.gender or 1, sc.bodyType, sc.proportion, sc.head,
		av ~= "" and (av .. "|") or "")
end

-- the avatar hair / face this rig carries (what the last ApplyDescription put on: the AvatarLook attribute
-- Builder.Apply writes), as AvatarHair / AvatarFace attributes the hair and face steps, FaceFX and the clients
-- read. Every Cosmetics caller (fights included) follows the rig, not its own opts
local function avatarState(model)
	local st = AvatarLook.State(model:GetAttribute("AvatarLook"))
	setAttr(model, "AvatarHair", st.hair or nil)
	setAttr(model, "AvatarFace", st.face or nil)
	return st
end
Builder.AvatarState = avatarState

-- the muscle tier of every body part from the build (BodyTiers) and the swap (BuilderTiers, change-only)
function Builder.Tiers(app, build, sp)
	local frame = sp and sp.frame or frameOf(app)
	return BodyTiers.Tiers(build, { potential = frame.potential, female = app.gender == 2 })
end

local function tiersStep(model, app, build, opts, sp)
	local tiers = BodyTiers.Tiers(build, { potential = sp.frame.potential, female = sp.female }, BuilderTiers.Current(model))
	local sc = Builder.Scales(app, build, opts)
	-- (the detail level's mesh set: the low level's crowd NPCs wear the lighter v9 meshes, Config.Detail.meshes)
	BuilderTiers.Apply(model, tiers, Vector3.new(sc.width, sc.height, sc.depth), sp.cfg ~= nil and sp.cfg.meshes == "lite")
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

------------------------------------------------------------------------
-- Headgear: every boxer's own (Config.AlwaysHeadgear), a Cosmetics step
------------------------------------------------------------------------
-- The model carries HeadgearColor (Color3: the boxer's own, Looks.HeadgearColor, written by Cosmetics) and, while
-- sparring, HeadgearCorner (the corner's colour SetHeadgear put on). The folder is cached on its colour, the head's
-- size and the detail level, so a rebuild, a tier swap or a respawn keeps (or rebuilds) it and a clone copies it.
local function wantsHeadgear(opts)
	return Config.AlwaysHeadgear == true and (opts == nil or opts.outfit == nil or Config.HeadgearOfficials ~= false)
end
Builder.WantsHeadgear = wantsHeadgear

local function headgearStep(model, detail)
	local corner, own = model:GetAttribute("HeadgearCorner"), model:GetAttribute("HeadgearColor")
	local col = (typeof(corner) == "Color3" and corner) or (typeof(own) == "Color3" and own) or Looks.Color(Looks.Palette[1])
	detail = Config.DetailLevel(detail)
	local head = model:FindFirstChild("Head")
	local key = Kit.sig("HG1", col, head and head.Size or false, detail)
	if Kit.cached(model, "Headgear", key) then
		return
	end
	local ok = step("Headgear", Head.SetHeadgear, model, col, true, detail)
	if ok then
		Kit.seal(model, "Headgear", key)
	end
end

-- a boxer's headgear (own colour from the look; no headgear when Config.AlwaysHeadgear is off or he is an exempt
-- official: the folder goes unless a spar put a corner's on)
local function headgearLook(model, app, opts, detail)
	if wantsHeadgear(opts) then
		setAttr(model, "HeadgearColor", Looks.Color(Looks.HeadgearColor(app)))
		headgearStep(model, detail)
	elseif model:GetAttribute("HeadgearColor") ~= nil then
		-- (switched off since the last build)
		setAttr(model, "HeadgearColor", nil)
		if model:GetAttribute("HeadgearCorner") == nil then
			Head.SetHeadgear(model, nil, false)
		end
	end
end

-- Sparring: on = the corner's colour over the boxer's own headgear, off = his own colour back. A model without its
-- own headgear (Config.AlwaysHeadgear off, an exempt official) gets the old toggle: built on, removed off
function Builder.SetHeadgear(model, color, on)
	if model:GetAttribute("HeadgearColor") ~= nil then
		setAttr(model, "HeadgearCorner", (on and typeof(color) == "Color3") and color or nil)
		local look = model:FindFirstChild("BoxerLook")
		local f = look and look:FindFirstChild("Headgear")
		step("Headgear", headgearStep, model, (f and f:GetAttribute("Detail")) or model:GetAttribute("Detail"))
		return
	end
	setAttr(model, "HeadgearCorner", nil)
	step("SetHeadgear", Head.SetHeadgear, model, color, on, model:GetAttribute("Detail"))
end

-- true while the model wears its own all-the-time headgear (fight cleanup keeps that folder)
function Builder.HasOwnHeadgear(model)
	return model:GetAttribute("HeadgearColor") ~= nil
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
-- opts keys the head steps never read; everything else that is a plain value goes in the signature
local HEAD_SIG_SKIP = {
	sweat = true, hands = true, robe = true, waistText = true, name = true, nick = true, nat = true,
	fightNight = true, physique = true, tier = true, sponsorTrunks = true, sponsorRobe = true, grime = true,
	mouthguard = true, damage = true,
}
-- Inputs the head steps read beyond the plain opts. Face = the built face's sliders, face fat, opts.grime (stored
-- on the face folder as OptGrime), the mouthguard colour and its bloodied tint (opts.damage.lip > 0.6), the fight
-- wear (app.battle) and only the hair / beard fields it really uses (Head.FaceSigParts: brow colour, lips
-- covered), so a barber visit never rebuilds the face. The Grime ATTRIBUTE (CONTRACTS section 7: set after
-- roadwork, cleared by the shower) is deliberately not in the key: BuilderHead draws face dirt in its own
-- FaceGrime folder from it on every Head.SetSweat, which Cosmetics always runs last, so roadwork and the shower
-- never cost a face rebuild. HD4: the built face is back (folders sealed under HD3's decal face rebuild once).
local function headSig(model, app, build, opts, name)
	local head = model:FindFirstChild("Head")
	local avHair, avFace = model:GetAttribute("AvatarHair") == true, model:GetAttribute("AvatarFace") == true
	local o = {}
	for k, v in pairs(opts) do
		local t = type(v)
		if (t == "number" or t == "string" or t == "boolean") and not HEAD_SIG_SKIP[k] then
			o[k] = v
		end
	end
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
			avatar = avFace,
			-- the face style (look.face.style): the drawn Boxer face decal every boxer wears (built only in the
			-- emergency fallback with no drawn face uploaded)
			style = BodyTiers.DrawnStyleOf(app) or BodyTiers.BUILT_STYLE,
		}
		if type(Head.FaceSigParts) == "function" then
			local ok, parts = pcall(Head.FaceSigParts, app)
			if ok and type(parts) == "table" then
				hair, beard = parts, false
			end
		end
	end
	-- (the beard sits its moustache over the mouth of the face style: the drawn style keys it too)
	return Kit.sig("HD4", name, app.gender, app.skin, app.height, app.face, hair, beard, app.battle, o,
		math.floor(fat + 0.5), head and head.Size or false, Config.BaldMode, extra, name == "Hair" and avHair or false,
		name == "Beard" and (BodyTiers.DrawnStyleOf(app) or BodyTiers.BUILT_STYLE) or false)
end

-- The head is scaled (HeadScale), and BuilderHead swaps the engine's default head (a MeshPart) for the classic
-- head (a plain Part with the Head SpecialMesh, the built face sits on it) of the same size once. Humanoid:ReplaceBodyPartR15 scales the new part "as
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

-- the neck: the classic head sits on the Neck pivot (the tiers' UpperTorso ends just above it), its base at the
-- pivot whatever head the engine or the swap left: the Head's NeckRigAttachment (and Neck.C1) at -half its
-- height. Absolute (from the head's size): idempotent across rebuilds, rescales and head swaps.
local function seatHead(model)
	local head = model:FindFirstChild("Head")
	local na = head and head:FindFirstChild("NeckRigAttachment")
	if not (head and head:IsA("BasePart") and na and na:IsA("Attachment")) then
		return
	end
	local y = -0.5 * head.Size.Y
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
		if model:GetAttribute("AvatarFace") == true then
			ok = step("Face", Head.AvatarFace, model, app, opts)
		else
			ok = step("Face", Head.Face, model, app, opts, build)
		end
	elseif name == "Hair" then
		ok = step("Hair", Hair.Build, model, app, opts)
	else
		ok = step(name, Head[name], model, app, opts)
	end
	if ok then
		Kit.seal(model, name, key)
	end
end

-- the Face step (the classic head swap and the built face), kept at the engine's head scale; the face is rebuilt
-- once on the corrected head (its size is in the Face cache key) when the swap changed it
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
	pcall(seatHead, model)
	-- a drawn face style's decal stays on the head when the face is served from cache (an ApplyDescription or a
	-- head swap since may have replaced it); a built face: nothing
	step("FaceDecal", Head.EnsureFaceDecal, model)
	-- avatar hair accessories put on before a head swap hang on the old head: weld them to the new one
	step("Accessories", Hair.FixAccessories, model)
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
function Builder.Cosmetics(model, app, build, gear, opts)
	opts = opts or {}
	app = app or Looks.Defaults(1)
	avatarState(model)
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
		-- (the headgear follows the head: a head swap or a colour change in the Creator rebuilds it)
		step("Headgear", headgearLook, model, app, opts, opts.detail)
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
	-- the muscle-tier body parts first: every layer below is built on (and coloured over) the final parts
	step("Tiers", tiersStep, model, app, build, opts, sp)
	step("Colors", Body.Colors, model, app, gear, opts)
	faceStep(model, app, build, opts)
	headStep(model, app, build, opts, "Hair")
	headStep(model, app, build, opts, "Beard")
	-- the headgear every boxer wears (on the final head; its own cache)
	step("Headgear", headgearLook, model, app, opts, sp.detail)
	-- avatar hair accessories (re)attached by ApplyDescription stay hidden under a headgear / hood
	if model:GetAttribute("AvatarHair") == true then
		step("HairHidden", Hair.ApplyHairHidden, model)
	end
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
		local av = opts and opts.avatar
		if not ok and type(av) == "table" then
			-- the avatar's items would not load (offsale, deleted, moderated, a web hiccup): the game look,
			-- and the avatar again only after AvatarLook's back-off
			warn("[Boxer] ApplyDescription with the avatar look failed (game look instead):", err)
			if opts.avatarUser then
				AvatarLook.ApplyFailed(opts.avatarUser)
			end
			av = nil
			local plain = table.clone(opts)
			plain.avatar = nil
			key = Builder.ScaleKey(app, build, plain)
			ok, err = pcall(function()
				hum:ApplyDescription(Builder.Description(app, build, plain))
			end)
		end
		if not ok then
			warn("[Boxer] ApplyDescription failed:", err)
		end
		character:SetAttribute("ScaleKey", key)
		local avKey = AvatarLook.Key(av)
		character:SetAttribute("AvatarLook", avKey ~= "" and avKey or nil)
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
	-- nothing in the game listens for touches: an NPC's parts that report none cost the physics less (the
	-- built layers' parts already have it off; this is the R15 body itself)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanTouch = false
		end
	end
	return model
end

return Builder
