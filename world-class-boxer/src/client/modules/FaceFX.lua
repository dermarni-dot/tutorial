-- FaceFX: the classic face's expressions. Client-only, driven by the Animator (FaceFX.Update every frame, Hit /
-- Effort / Shout from the fight and gym animation). Every boxer's head carries the server's Decal "face" with his
-- chosen classic face (the model attribute FaceKey, BuilderHead); FaceFX swaps that Decal's texture, locally, for
-- the face of his mood (BodyAssetData.expressions through BodyTiers.MoodFace) and back to his own face when the
-- mood is neutral. Nothing else on the face moves: the organic face (lids, eyes, blend shapes, painted damage) is
-- retired, and the fight damage is the server's head overlays (BuilderHead.SetDamage).
-- The mood, strongest first:
--   KO (Guard "down" and Expr "ko") > down / stunned (Guard "down") > hurt (a Hit, for 0.4 .. 0.9 s by severity)
--   > the expression drivers (ExprPreview on the local character in the Creator, the Animator's rig.exprHint, the
--   server's Expr attribute: Config.Expressions through BodyTiers.MOODS) > a shout (angry) > effort (an Effort
--   call, or the Effort attribute over 0.55) > spent in a fight (Stam under 0.3: tired) > neutral (his own face).
-- A mood whose face is not uploaded keeps his own face. Cost: a texture compare per tracked head at RATE Hz within
-- RANGE studs (the opponent and the local character at every distance); a swap is one local property write.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BodyTiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BodyTiers"))

local FaceFX = {}

FaceFX.RANGE = 60 -- studs: past this a face keeps whatever it shows (a dozen pixels)
FaceFX.RATE = 12 -- mood checks a second per face
local HIT_MIN, HIT_MAX = 0.4, 0.9 -- seconds a hit shows the hurt face (light .. heavy)
local player = Players.LocalPlayer

local recs = setmetatable({}, { __mode = "k" }) -- model -> { hitUntil, effortUntil, shoutUntil, next, tex }

local function recOf(model)
	local r = recs[model]
	if not r then
		r = { hitUntil = 0, effortUntil = 0, shoutUntil = 0, nextT = 0, tex = nil }
		recs[model] = r
	end
	return r
end

------------------------------------------------------------------------
-- Events from the Animator
------------------------------------------------------------------------
function FaceFX.Hit(model, sev)
	if model then
		local r = recOf(model)
		r.hitUntil = math.max(r.hitUntil, os.clock() + HIT_MIN + (HIT_MAX - HIT_MIN) * math.clamp(tonumber(sev) or 0.5, 0, 1))
		r.nextT = 0
	end
end

function FaceFX.Effort(model, amount, dur)
	if model and (tonumber(amount) or 0.6) >= 0.3 then
		local r = recOf(model)
		r.effortUntil = math.max(r.effortUntil, os.clock() + math.max(0.1, tonumber(dur) or 0.4))
	end
end

function FaceFX.Shout(model, dur)
	if model then
		local r = recOf(model)
		r.shoutUntil = os.clock() + (tonumber(dur) or 0.8)
	end
end

------------------------------------------------------------------------
-- The mood
------------------------------------------------------------------------
-- (model, rig?, now) -> the mood (a BodyAssetData.expressions key or "neutral")
function FaceFX.MoodOf(model, rig, now, r)
	r = r or recOf(model)
	local guard = model:GetAttribute("Guard")
	local expr = model:GetAttribute("Expr")
	if guard == "down" then
		return expr == "ko" and "ko" or "stunned"
	end
	if now < r.hitUntil then
		return "hurt"
	end
	local e = rig and rig.exprHint or nil
	if player and model == player.Character and type(model:GetAttribute("ExprPreview")) == "string" then
		e = model:GetAttribute("ExprPreview")
	end
	e = e or expr
	if type(e) == "string" and e ~= "neutral" then
		return BodyTiers.MoodOf(e)
	end
	if now < r.shoutUntil then
		return BodyTiers.MoodOf("shout")
	end
	local eff = tonumber(model:GetAttribute("Effort")) or 0
	if now < r.effortUntil or eff > 0.55 then
		return "effort"
	end
	local stam = tonumber(model:GetAttribute("Stam"))
	if guard ~= nil and stam and stam < 0.3 then
		return "tired"
	end
	return "neutral"
end

local function faceDecal(model)
	local head = model:FindFirstChild("Head")
	local d = head and head:FindFirstChild("face")
	return (d and d:IsA("Decal")) and d or nil, head
end

local function step(model, rig, now, camPos)
	local r = recOf(model)
	if now < r.nextT then
		return
	end
	r.nextT = now + 1 / FaceFX.RATE
	-- a player's avatar face (Dynamic Head / the avatar's decal face, Builder's AvatarFace attribute): ours to
	-- leave alone (its texture is the avatar's, not a BodyTiers face)
	if model:GetAttribute("AvatarFace") == true then
		return
	end
	local decal, head = faceDecal(model)
	if not decal then
		return
	end
	local near = (player and model == player.Character) or (rig and rig.isFighter) or (head.Position - camPos).Magnitude <= FaceFX.RANGE
	if not near then
		return
	end
	local chosen = model:GetAttribute("FaceKey")
	local tex = BodyTiers.MoodTexture(FaceFX.MoodOf(model, rig, now, r), type(chosen) == "string" and chosen or nil)
	if decal.Texture ~= tex then
		decal.Texture = tex
	end
	r.tex = tex
end

-- rigs = the Animator's rig table (model -> rig: exprHint, isFighter), may be nil; budget is unused (kept for the
-- Animator's call)
function FaceFX.Update(_dt, _t, camPos, rigs, _budget)
	local now = os.clock()
	camPos = camPos or Vector3.zero
	if rigs then
		for model, rig in pairs(rigs) do
			if model.Parent then
				step(model, rig, now, camPos)
			end
		end
	end
	-- the local character and the previews (the Creator, the main menu stage) are not always animated rigs
	local char = player and player.Character
	if char and not (rigs and rigs[char]) then
		step(char, nil, now, camPos)
	end
	for _, m in ipairs(CollectionService:GetTagged("Preview")) do
		if m:IsA("Model") and not (rigs and rigs[m]) then
			step(m, nil, now, camPos)
		end
	end
end

-- tests / tools: what FaceFX shows on a model (nil = not tracked)
function FaceFX.Debug(model)
	local r = recs[model]
	return r and { texture = r.tex, hit = os.clock() < r.hitUntil } or nil
end

return FaceFX
