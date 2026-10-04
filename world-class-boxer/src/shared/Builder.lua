-- Builder: turns a boxer's look data into a 3D character (server side). Public facade.
-- * Scales / Description / ScaleKey: frame scaling through a HumanoidDescription
-- * Cosmetics / Apply / CreateNPC: build every procedural layer on a character, in order
-- The layers live in sub-modules that share the part helpers in BuilderKit:
-- * BuilderHead: procedural face, hair, beard, fight damage, sweat shine, sparring headgear
-- * BuilderBody: skin/trunks/shoe colours, muscle overlays, attire, gloves and wraps, robe
-- FaceLayout, SetDamage, SetSweat, SetHeadgear and SetRobe are forwarded from them unchanged.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local Head = require(script.Parent:WaitForChild("BuilderHead"))
local Body = require(script.Parent:WaitForChild("BuilderBody"))

local Builder = {}

local frameOf, avgDev = Body.frameOf, Body.avgDev
-- build steps, in the order Cosmetics runs them
local colorBody = Body.Colors
local faceBuild, hairBuild, beardBuild = Head.Face, Head.Hair, Head.Beard
local musclesBuild, attireBuild, handsBuild = Body.Muscles, Body.Attire, Body.Hands

------------------------------------------------------------------------
-- Scales / HumanoidDescription
------------------------------------------------------------------------
function Builder.Scales(app, build)
	local frame = frameOf(app)
	local b = app.body or {}
	local female = app.gender == 2
	local fat = build and build.fat or 14
	local upper = avgDev(build, { "shoulders", "back", "chest" })
	local width = frame.width * (1 + 0.12 * upper + 0.05 * (b.shoulders or 0)) * (female and 0.92 or 1)
	local depth = frame.depth * (1 + 0.08 * avgDev(build, { "chest" }) + 0.012 * (fat - 14) + 0.04 * (b.chest or 0)) * (female and 0.94 or 1)
	return {
		height = math.clamp((app.height or 70) / 70, 0.86, 1.2),
		width = math.clamp(width, 0.75, 1.4),
		depth = math.clamp(depth, 0.75, 1.4),
	}
end

function Builder.Description(app, build)
	local desc = Instance.new("HumanoidDescription")
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	desc.HeadColor = skin
	desc.TorsoColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	-- legs are skin: the trunks are separate loose shells built over the thighs
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	local sc = Builder.Scales(app, build)
	desc.HeightScale = sc.height
	desc.WidthScale = sc.width
	desc.DepthScale = sc.depth
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	return desc
end

function Builder.ScaleKey(app, build)
	local sc = Builder.Scales(app, build)
	return string.format("%.2f|%.2f|%.2f|%d", sc.height, sc.width, sc.depth, app.gender or 1)
end

------------------------------------------------------------------------
-- Head / body API (implemented in BuilderHead / BuilderBody)
------------------------------------------------------------------------
-- returns head-local positions for face features (shared with damage visuals)
Builder.FaceLayout = Head.FaceLayout -- (head, face)
-- dmg = { leftEye, rightEye (0..1 swelling), cut (0..1.2), cutSide, noseBleed (0..1), nose (broken bool), bruise (0..1), lip (0..1) }
Builder.SetDamage = Head.SetDamage -- (model, app, dmg)
Builder.SetSweat = Head.SetSweat -- (model, app, level)
Builder.SetHeadgear = Head.SetHeadgear -- (model, color, on)
Builder.SetRobe = Body.SetRobe -- (model, app, on, opts)

------------------------------------------------------------------------
-- Public entry points
------------------------------------------------------------------------
-- opts: { hands = "gloves"|"wraps"|"bare", mouthguard = bool, name, nick, nat, waistText }
function Builder.Cosmetics(model, app, build, gear, opts)
	opts = opts or {}
	colorBody(model, app, gear)
	faceBuild(model, app, opts)
	hairBuild(model, app)
	beardBuild(model, app)
	musclesBuild(model, app, build)
	attireBuild(model, app, opts, gear)
	handsBuild(model, app, gear, opts)
	local dmg = model:FindFirstChild("BoxerLook") and model.BoxerLook:FindFirstChild("Damage")
	if dmg then
		dmg:Destroy()
	end
	model:SetAttribute("Female", app.gender == 2)
end

-- Apply to a live player character (yields). Re-scales only when the body changed.
function Builder.Apply(character, app, build, gear, opts)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local key = Builder.ScaleKey(app, build)
	if character:GetAttribute("ScaleKey") ~= key then
		local ok, err = pcall(function()
			hum:ApplyDescription(Builder.Description(app, build))
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
		model = Players:CreateHumanoidModelFromDescription(Builder.Description(app, build), Enum.HumanoidRigType.R15)
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
