-- Builder: turns a boxer's look data into a 3D character (server side). Public facade.
-- * Scales / Description / ScaleKey: the standard R15 body's HumanoidDescription (height, frame, gender)
-- * Tiers: the muscle tier of every body part from the build (BodyTiers); BuilderTiers swaps the parts
-- * Cosmetics / Apply / CreateNPC: build every layer on a character, in order, with per-folder rebuild
--   caching, detail levels and the CONTRACTS section 4 opts
-- The layers live in sub-modules that share the part helpers in BuilderKit:
-- * BuilderTiers: the 14 muscle-tier body parts (Humanoid:ReplaceBodyPartR15, only on a tier change)
-- * BuilderHead: the classic head and the face built on it (Parts, a FaceFX rig), beard, fight damage, sweat, headgear
--   (every boxer wears it while Config.AlwaysHeadgear: a Cosmetics step, recoloured by SetHeadgear while sparring),
--   and the officials' caps instead of it (Config.OfficialCaps: the Hat step, Head.SetCap)
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
-- head x RTHRO_HEAD (what BodyTypeScale 1 used to take off it): 0.927 studs on the Athletic frame, a little
-- smaller on the Lean, bigger on the Power Build / Heavyweight (tools/body/build_body.py FRAMES[id].head is the
-- same table: the neck column is modelled under that head). With every id 0 the default parts stay: the classic
-- block body at these scales.
--
-- THE HEIGHT (v13): the frame changes the build, never the height. Every frame's mesh family has its own unit rig
-- (BodyAssetData.frames[id].unit: the neck pivot's height neckHeight with the frame's skeleton, its head), so the
-- HeightScale is normalised per frame: the chosen height in inches is the standing height of the Athletic unit x
-- inches / 70 (the 70-inch Athletic man stands unit.standingHeight = 6.2161 studs, the game's inch), and
--   HeightScale = (standing - head) / unit[frame].neckHeight     (head = 1.2 x HeadScale: the head is not height-scaled)
-- so the sole-to-crown height, and with it the eye line, is the same for every frame at the same inches (the frames'
-- skeletons are tuned so the hip line follows within 1 %: BuilderTiers.FixHipHeight follows the scaled legs anyway).
-- A missing unit (no neckHeight) falls back to inches / 70.
local FRAME_PROPORTIONS = {
	Lean = { head = 0.79 },
	Athletic = { head = 0.82 },
	Muscular = { head = 0.835 },
	["Power Build"] = { head = 0.85 },
	["Heavyweight Build"] = { head = 0.865 },
}
Builder.FRAME_PROPORTIONS = FRAME_PROPORTIONS
local RTHRO_HEAD = 0.942
Builder.RTHRO_HEAD = RTHRO_HEAD
-- the classic head's nominal size the HeadScale scales (the plain head Part BuilderHead swaps in)
local HEAD_NOMINAL = 1.2
-- the share of Config.BodyTypes' width / depth that still goes into the description: the frames' mesh families carry
-- the build (a Lean frame's narrow shoulders, the heavyweight's wide pelvis are IN the meshes, v12), so the whole-body
-- Width / Depth is only the fine-tune on top; at the full BodyTypes values the pelvis of a Heavyweight came out 1.16
-- (mesh) x 1.17 (description) = 1.36 x the Athletic one, and every hand, foot and shin with it
local FRAME_WIDTH_SHARE = 0.5
Builder.FRAME_WIDTH_SHARE = FRAME_WIDTH_SHARE

-- the inches the creator / the records carry (Looks: 60..84), the Athletic unit's studs per 70 inches
local HEIGHT_MIN, HEIGHT_MAX = 60, 84
local UNIT_STAND_FALLBACK = 6.2161

-- the frame's unit rig heights (BodyTiers.Unit) and the Athletic unit's standing height: nil, nil without data
local function unitOf(frameId)
	local ok, u = pcall(BodyTiers.Unit, frameId)
	return ok and type(u) == "table" and u or nil
end

-- the standing height in studs a boxer of `inches` is built to (every frame): the Athletic unit's x inches / 70
function Builder.StandingHeight(inches)
	local ath = unitOf(BodyTiers.DEFAULT_FRAME)
	local unitStand = ath and type(ath.standingHeight) == "number" and ath.standingHeight or UNIT_STAND_FALLBACK
	return math.clamp(tonumber(inches) or 70, HEIGHT_MIN, HEIGHT_MAX) / 70 * unitStand
end

-- (build, opts: kept for the callers; the physique and training no longer change the scales)
function Builder.Scales(app, build, opts)
	local frame = frameOf(app)
	local female = app.gender == 2
	local pr = FRAME_PROPORTIONS[frame.id] or FRAME_PROPORTIONS.Athletic
	local headScale = pr.head * RTHRO_HEAD * (female and 0.97 or 1)
	local inches = math.clamp(tonumber(app.height) or 70, HEIGHT_MIN, HEIGHT_MAX)
	-- the frame's own neck height: the height scale that puts the crown of its head at the chosen height
	local u = unitOf(frame.id)
	local height = inches / 70
	if u and type(u.neckHeight) == "number" and u.neckHeight > 1 then
		height = (Builder.StandingHeight(inches) - HEAD_NOMINAL * headScale) / u.neckHeight
	end
	local wk = (female and 0.92 or 1)
	local dk = (female and 0.94 or 1)
	return {
		height = math.clamp(height, 0.8, 1.3),
		width = math.clamp((1 + (frame.width - 1) * FRAME_WIDTH_SHARE) * wk, 0.7, 1.4),
		depth = math.clamp((1 + (frame.depth - 1) * FRAME_WIDTH_SHARE) * dk, 0.7, 1.4),
		bodyType = 0,
		proportion = 0,
		head = headScale,
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

-- quantised to 0.01 so only real changes re-apply the description (which yields); "p4" = the standard R15
-- body at BodyTypeScale 0 with the frame-normalised height (characters scaled under an older key re-apply once).
-- A player's avatar hair / face
-- (opts.avatar) adds its AvatarLook.Key: a new avatar, the setting turned on / off re-apply once; the game
-- look's key is exactly the old one
function Builder.ScaleKey(app, build, opts)
	local sc = Builder.Scales(app, build, opts)
	local av = AvatarLook.Key(opts and opts.avatar)
	return string.format("%.2f|%.2f|%.2f|%d|%.2f|%.2f|%.2f|%sp4", sc.height, sc.width, sc.depth, app.gender or 1, sc.bodyType, sc.proportion, sc.head,
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

------------------------------------------------------------------------
-- Officials' caps (Config.OfficialCaps): a Cosmetics step after the headgear
------------------------------------------------------------------------
-- the referee (opts.outfit "referee") wears his peaked referee cap, the spar coach ("cornerman") a team baseball cap,
-- whenever he wears no headgear (Config.HeadgearOfficials off). Colours from opts.officialColors (Officials.Colors:
-- cap / capTrim / capBadge). BoxerLook/Hat is cached on the style, colours, head size and detail (Kit.cached checks
-- the welds still hold the current head), so a rebuild, a tier swap or a respawn keeps or rebuilds it, a clone
-- copies it; anyone else (a boxer, a switched-off flag) has the folder removed.
local CAP_STYLE = { referee = "referee", cornerman = "baseball" }
local function capStyle(opts)
	if Config.OfficialCaps == false or type(opts) ~= "table" or wantsHeadgear(opts) then
		return nil
	end
	return CAP_STYLE[opts.outfit or ""]
end
Builder.CapStyle = capStyle

local function capLook(model, opts, detail)
	local style = capStyle(opts)
	local look = model:FindFirstChild("BoxerLook")
	if not style then
		local f = look and look:FindFirstChild("Hat")
		if f then
			f:Destroy()
		end
		return
	end
	local oc = type(opts.officialColors) == "table" and opts.officialColors or {}
	local function col(t)
		return type(t) == "table" and Looks.Color(t) or nil
	end
	local colors = { cap = col(oc.cap), trim = col(oc.capTrim), badge = col(oc.capBadge) }
	detail = Config.DetailLevel(detail)
	local head = model:FindFirstChild("Head")
	local key = Kit.sig("CAP1", style, colors, head and head.Size or false, detail)
	if Kit.cached(model, "Hat", key) then
		return
	end
	local ok = step("Hat", Head.SetCap, model, style, colors, detail)
	if ok then
		Kit.seal(model, "Hat", key)
	end
end

-- The late re-fit (BuilderHead.RefitHeadgear): the gear folders checked against the live head (its instance, Size,
-- class, mesh; welds still there) and rebuilt from their own record when they no longer fit, each rebuild warned as
-- "[Boxer] headgear refit <name>: ..."; a rebuilt folder is re-sealed under the key its step would have used, so the
-- next Cosmetics keeps it. The Neck is checked too (Head.EnsureNeck: a rig the swap left without one is dead on
-- RequiresNeck). Change-only: nil while everything fits.
function Builder.RefitHeadgear(model)
	if not (model and model.Parent) then
		return nil
	end
	local okN, neck = pcall(Head.EnsureNeck, model)
	if okN and neck == "rebuilt" then
		warn("[Boxer] headgear refit " .. tostring(model.Name) .. ": no Neck joint on the rig; a Motor6D Neck was rebuilt from the RigAttachments")
	end
	local ok, res = pcall(Head.RefitHeadgear, model)
	if not ok then
		warn("[Boxer] headgear refit failed:", res)
		return nil
	end
	if type(res) ~= "table" then
		return nil
	end
	local head = model:FindFirstChild("Head")
	local look = model:FindFirstChild("BoxerLook")
	if res.Headgear then
		local f = look and look:FindFirstChild("Headgear")
		local col = f and f:GetAttribute("Color")
		if f and typeof(col) == "Color3" then
			Kit.seal(model, "Headgear", Kit.sig("HG1", col, head and head.Size or false, f:GetAttribute("Detail")))
		end
	end
	if res.Hat then
		local f = look and look:FindFirstChild("Hat")
		if f then
			local colors = { cap = f:GetAttribute("CapColor"), trim = f:GetAttribute("CapTrim"), badge = f:GetAttribute("CapBadge") }
			Kit.seal(model, "Hat", Kit.sig("CAP1", f:GetAttribute("Style"), colors, head and head.Size or false, f:GetAttribute("Detail")))
		end
	end
	return res
end

-- A model placed in Workspace (an NPC parented in by Ambient / Venues / FightEngine, a player after Builder.Apply):
-- the engine's deferred passes (the Humanoid's scaling, the MeshPart head conversion, a death on a missing Neck)
-- run after the parent, so the gear is re-fitted 0.3 s and 2 s later (Builder.RefitHeadgear; a no-op while it
-- fits). One schedule per model at a time.
Builder.REFIT_DELAYS = { 0.3, 2 }
local refitPending = setmetatable({}, { __mode = "k" })
function Builder.OnPlaced(model)
	if model == nil or refitPending[model] then
		return
	end
	refitPending[model] = true
	local last = Builder.REFIT_DELAYS[#Builder.REFIT_DELAYS]
	for _, delay in ipairs(Builder.REFIT_DELAYS) do
		task.delay(delay, function()
			if delay == last then
				refitPending[model] = nil
			end
			if model.Parent then
				Builder.RefitHeadgear(model)
			end
		end)
	end
end

-- Every built character / NPC keeps its joints and its gear whatever happens to its Neck: the rigs the engine hands
-- out now carry AnimationConstraint joints (the avatar joint upgrade) or lose the Neck in a head swap, and with
-- RequiresNeck on the Humanoid dies and BreakJointsOnDeath then drops every weld (the headgear lying studs away,
-- every motor gone: the Studio diagnostic). FightEngine / Ragdoll set these per fight already; this is the baseline.
local function hardenHumanoid(model)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	pcall(function()
		if hum.RequiresNeck ~= false then
			hum.RequiresNeck = false
		end
		if hum.BreakJointsOnDeath ~= false then
			hum.BreakJointsOnDeath = false
		end
	end)
end
Builder.HardenHumanoid = hardenHumanoid

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
-- what the rig measured when its layers were built (attributes the diagnostic compares with the live rig: a head the
-- engine rescaled after the headgear was fitted to it, a HipHeight the engine's deferred scaling pass put back), and
-- the tier legs' HipHeight checked again a moment later (BuilderTiers.FixHipHeight: change-only, see there)
local function buildRecord(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		setAttr(model, "HeadSizeAtBuild", head.Size)
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		setAttr(model, "HipHeightAtBuild", hum.HipHeight)
		-- [Studio] a Neck joint missing for a frame (a head swap, a headgear rebuild, a ragdoll) must never kill the rig
		pcall(function()
			hum.RequiresNeck = false
		end)
	end
	for _, delay in ipairs({ 0.25, 1.5 }) do
		task.delay(delay, function()
			if model.Parent then
				local h = BuilderTiers.FixHipHeight(model)
				if h then
					model:SetAttribute("HipHeightRefixed", h)
				end
			end
		end)
	end
end

-- opts (all optional, CONTRACTS section 4): hands = "gloves"|"wraps"|"bare", mouthguard, name, nick,
-- nat, waistText, robe, detail ("full"|"medium"|"low"), damage, sweat, grime, age, tier, physique,
-- fightNight, sponsorTrunks / sponsorRobe ({ text, fg, bg }), dry, outfit ("referee"|"cornerman"),
-- only ({ Face, Hair, Beard }), previewGrowth. gear = { gloves, glovesCond, wraps, wrapsCond, shoes,
-- shoesCond, mouthguard, robe } (missing ids default to the starter kit).
function Builder.Cosmetics(model, app, build, gear, opts)
	opts = opts or {}
	app = app or Looks.Defaults(1)
	hardenHumanoid(model)
	avatarState(model)
	-- preview path: rebuild only the requested head folders, in order. only.Colors (a colour swatch in the Creator /
	-- locker room: skin, trunks, gloves, shoes, headgear ...) recolours instead of running the whole Cosmetics: the
	-- body colours, then the coloured layers (attire, hands; the face and beard for a skin tone), each kept when its
	-- signature did not move. No tier swap, no hair, no muscles, no damage reset: none of them take a colour
	if type(opts.only) == "table" then
		local colors = opts.only.Colors == true
		local cgear, csp
		if colors then
			cgear = Body.Gear(gear)
			csp = Body.Resolve(app, build, opts, model)
			step("Colors", Body.Colors, model, app, cgear, opts)
			faceStep(model, app, build, opts)
			headStep(model, app, build, opts, "Beard")
		end
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
		if (opts.only.Face or colors) and type(opts.damage) == "table" then
			Builder.SetDamage(model, app, opts.damage)
		end
		-- (the headgear follows the head: a head swap or a colour change in the Creator rebuilds it)
		step("Headgear", headgearLook, model, app, opts, colors and csp.detail or opts.detail)
		step("Hat", capLook, model, opts, colors and csp.detail or opts.detail)
		if colors then
			step("Attire", Body.Attire, model, app, opts, cgear, csp, nil)
			step("Hands", Body.Hands, model, app, cgear, opts, csp)
		end
		Builder.SetSweat(model, app, opts.sweat or model:GetAttribute("Sweat") or 0)
		-- previews (Creator / barber) change the look too: the meshes follow (a colour preview: the gloves' too)
		step("LookData", publishLook, model, app, build, opts, csp, colors and cgear or nil)
		buildRecord(model)
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
	-- the officials' caps (the referee's, the coach's) when they wear no headgear
	step("Hat", capLook, model, opts, sp.detail)
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
	buildRecord(model)
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
		-- the engine's deferred passes after the description (scaling, the head conversion) run after this returns
		Builder.OnPlaced(character)
	end
end

-- The staging container an NPC is built in. CreateHumanoidModelFromDescription hands back a model OUTSIDE the
-- DataModel, and the Humanoid's rig operations the Cosmetics run on it (ReplaceBodyPartR15 for the tier parts and the
-- classic head, the body scaling they trigger) read engine state through the model's DataModel: outside it the
-- engine logs "Instance outside of DataModel; could not read property Workspace.MeshPartHeadsAndAccessories" and a
-- swap can be refused or come out at the wrong size / class (the default MeshPart head under a headgear built for
-- the classic one). So the model is parented into ServerStorage first (inside the DataModel, no replication, no
-- physics), built, then handed back unparented as before (every caller parents it where it goes).
-- Builder.Services.Stage: an override (tests) or any container; nil when no container could be made (the old,
-- unparented build, warned once).
Builder.Services = Builder.Services or {}
local stageWarned = false
local function stageFolder()
	local s = Builder.Services.Stage
	if s ~= nil then
		return s or nil
	end
	local ok, f = pcall(function()
		local ss = game:GetService("ServerStorage")
		local f = ss:FindFirstChild("BoxerStaging")
		if not f then
			f = Instance.new("Folder")
			f.Name = "BoxerStaging"
			f.Parent = ss
		end
		return f
	end)
	if ok and f then
		Builder.Services.Stage = f
		return f
	end
	if not stageWarned then
		stageWarned = true
		warn("[Boxer] no staging container for NPC builds (rigs are built outside the DataModel):", f)
	end
	Builder.Services.Stage = false
	return nil
end
Builder.StageFolder = stageFolder

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
	-- inside the DataModel for every rig operation (see stageFolder); the root held still while the build yields
	local stage = stageFolder()
	local root = model:FindFirstChild("HumanoidRootPart")
	local wasAnchored = root and root:IsA("BasePart") and root.Anchored
	if stage then
		if root and root:IsA("BasePart") then
			root.Anchored = true
		end
		model.Parent = stage
	end
	local okC, errC = pcall(Builder.Cosmetics, model, app, build, gear, opts)
	if stage then
		model.Parent = nil
		if root and root.Parent and wasAnchored ~= nil then
			root.Anchored = wasAnchored
		end
	end
	if not okC then
		-- (as before the staging: the error is the caller's - SpawnReferee's pcall, Ambient's spawn thread)
		error(errC, 0)
	end
	-- nothing in the game listens for touches: an NPC's parts that report none cost the physics less (the
	-- built layers' parts already have it off; this is the R15 body itself)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanTouch = false
		end
	end
	-- the late re-fit once the caller places it in Workspace (Builder.OnPlaced; the callers' own hook covers a clone,
	-- which carries no connection)
	pcall(function()
		local conn
		conn = model.AncestryChanged:Connect(function()
			if model:FindFirstAncestorWhichIsA("Workspace") then
				conn:Disconnect()
				Builder.OnPlaced(model)
			end
		end)
	end)
	return model
end

return Builder
