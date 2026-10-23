-- PostFight: the scene after the final bell of every fight (FightEngine.Run calls PostFight.Run(fight, res, opts) once
-- the "final" message is out; not for sparring or the practice tutorial). The server owns it:
--   * both men to the centre of the ring facing the hard camera's side, the referee between them holding a wrist
--     each (a man still down from a knockout stays where he fell)
--   * the ring announcer's script (Judging.Announce: the cards read one by one for a decision, the time and the
--     round for a stoppage, "...and NEW" for a title) sent to every viewer once (t = "postfight") with the shared
--     beats; the client (BoxerClient.Ceremony) runs the camera, the banner and the crowd on the same clock
--   * on the winner's beat the referee raises his hand (AnimCeremony's pf* poses as Pose on a "Trainee" / the
--     "Referee", played by the Animator), the loser drops his head; a draw raises both
--   * the crowd's cue: the "FightResult" RemoteEvent (ReplicatedStorage.Remotes, made here when missing) fired to
--     every client with the result, and the same table as the arena's "FightResult" attribute, so a crowd / venue
--     module can hook it without this module knowing it
--   * SKIP (the client's ceremonySkip input, as the belt ceremony's) ends it early; "postfightEnd" closes it
-- Nothing is awarded or recorded here: Career does that from the result after Run returns.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Judging
do
	local ok, mod = pcall(require, script.Parent:FindFirstChild("Judging"))
	Judging = ok and type(mod) == "table" and mod or nil
end

local PostFight = {}

-- the scene's fixed beats (seconds; the announcer's lines come from Judging.Announce on top)
PostFight.BEATS = {
	gather = 0.0, -- the men and the referee in the centre
	hold = 3.0, -- after the hand goes up: how long the picture holds
	titleHold = 4.5, -- (a championship: a longer hold before the belt ceremony)
	maxDur = 32, -- failsafe
}

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function standHeight(hum, root)
	if hum and root and hum.HipHeight > 0.5 then
		return hum.HipHeight + root.Size.Y / 2 + 0.05
	end
	return 3.2
end

local function setPose(model, pose)
	if model and model.Parent then
		model:SetAttribute("Pose", pose)
	end
end

local function partOf(model, name)
	local p = model and model.Parent and model:FindFirstChild(name)
	return (p and p:IsA("BasePart")) and p or nil
end

-- the "FightResult" remote (made once, next to the Fight remote)
local resultRemote
local function remote()
	if resultRemote and resultRemote.Parent then
		return resultRemote
	end
	local ok, r = pcall(function()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			return nil
		end
		local ev = folder:FindFirstChild("FightResult")
		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = "FightResult"
			ev.Parent = folder
		end
		return ev
	end)
	resultRemote = ok and r or nil
	return resultRemote
end
PostFight.Remote = remote

-- stand a model at pos facing look (flat), point its facing constraint the same way so it is not fought, and
-- anchor its root for the scene (the Humanoids' own physics, a push from the other body, a client walking its
-- character cannot slide him out of the picture); held lists the roots to free at the end
local function stand(fight, F, model, pos, look, center, held)
	local root = partOf(model, "HumanoidRootPart")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not root then
		return
	end
	local y = center.Y + standHeight(hum, root)
	model:PivotTo(CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(look.X, y, look.Z)))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if hum then
		pcall(function()
			hum.WalkSpeed = 0
			hum.AutoRotate = false
		end)
	end
	local align = F and F.align
	if align then
		pcall(function()
			align.CFrame = CFrame.lookAt(Vector3.zero, flat(look - pos).Unit)
			align.Enabled = true
		end)
	end
	if held and not root.Anchored then
		local ok = pcall(function()
			root.Anchored = true
		end)
		if ok then
			table.insert(held, root)
		end
	end
end

-- the frames the scene is spaced on (HitGeometry: shoulderHalf = half the shoulder width off the live rig,
-- torsoHalfD half the chest's depth; the unit frame when a rig cannot be read)
local HitGeometry
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HitGeometry"))
	end)
	HitGeometry = ok and type(mod) == "table" and mod or nil
end
local UNIT_FRAME = { shoulderHalf = 0.955, torsoHalfD = 0.485, torsoHalfW = 0.795, arm = 2.578, glove = 0.32, hScale = 1 }
local function frameOf(fight, F, model)
	if F and fight and fight.Geo then
		local ok, g = pcall(fight.Geo, fight, F)
		if ok and type(g) == "table" and g.shoulderHalf then
			return g
		end
	end
	if HitGeometry and model then
		local root = partOf(model, "HumanoidRootPart")
		local hum = model:FindFirstChildOfClass("Humanoid")
		local soleY = root and (root.Position.Y - standHeight(hum, root)) or nil
		local ok, fr = pcall(HitGeometry.Frame, model, soleY, HitGeometry.Unit())
		if ok and type(fr) == "table" then
			return fr
		end
	end
	return UNIT_FRAME
end

-- The scene's places, from the frames (pure: tools/sim/test_spacing.luau reads it). center = the ring centre, face
-- = the way the picture faces (toward the hard camera), frames = { red, blue, ref } (HitGeometry frames), and
-- redDown / blueDown for a man still on the canvas. Returns { red, blue, ref } (flat positions at center's height).
--   * the referee stands in the middle, SIDE_BACK behind the men's line (his arms reach forward to their wrists)
--   * each man stands a shoulder width of his own plus a shoulder width of the referee's plus SIDE_GAP of air to
--     the side: the raised arms (the referee's up at 2.6 rad, the winner's inside arm at 2.72 rad, both past
--     vertical and away from the other body) and the referee's held-out hands never cross into a body, and a
--     Heavyweight Build (1.17 x the unit shoulder) stands his own width further out than a Lean man
--   * one man down: the standing man and the referee share the centre, the same spacing between them
PostFight.SIDE_GAP, PostFight.SIDE_BACK, PostFight.SIDE_FWD = 0.9, 0.45, 0.1
function PostFight.Layout(center, face, frames, redDown, blueDown)
	frames = frames or {}
	local red, blue, ref = frames.red or UNIT_FRAME, frames.blue or UNIT_FRAME, frames.ref or UNIT_FRAME
	local right = face:Cross(Vector3.yAxis)
	local sideRed = red.shoulderHalf + ref.shoulderHalf + PostFight.SIDE_GAP
	local sideBlue = blue.shoulderHalf + ref.shoulderHalf + PostFight.SIDE_GAP
	local refAt = center - face * PostFight.SIDE_BACK
	local redAt = center - right * sideRed + face * PostFight.SIDE_FWD
	local blueAt = center + right * sideBlue + face * PostFight.SIDE_FWD
	if redDown and not blueDown then
		blueAt = center + right * (sideBlue / 2) + face * PostFight.SIDE_FWD
		refAt = center - right * (sideBlue / 2) - face * PostFight.SIDE_BACK
	elseif blueDown and not redDown then
		redAt = center - right * (sideRed / 2) + face * PostFight.SIDE_FWD
		refAt = center + right * (sideRed / 2) - face * PostFight.SIDE_BACK
	end
	return { red = redAt, blue = blueAt, ref = refAt, sideRed = sideRed, sideBlue = sideBlue }
end

-- the crowd's table: who won, how, the names, the bout
local function resultTable(fight, res, opts)
	local P, O = fight.P, fight.O
	local winner = res.outcome == "win" and P or (res.outcome == "loss" and O or nil)
	local loser = winner and fight:Other(winner) or nil
	local offer = fight.offer or {}
	return {
		outcome = res.outcome, method = res.method, round = res.round, reason = res.reason,
		winner = winner and winner.data.name or nil, loser = loser and loser.data.name or nil,
		red = P.data.name, blue = O.data.name, redWon = res.outcome == "win", draw = res.outcome == "draw",
		kind = offer.kind, venue = fight.venue, title = type(opts.ceremony) == "table" and opts.ceremony.title or nil,
		pvp = fight.pvp == true, scores = res.scores,
	}
end

function PostFight.Run(fight, res, opts)
	opts = opts or {}
	local P, O = fight.P, fight.O
	local anchors = fight.anchors
	if not (P and O and anchors and anchors.RingCenter and P.model and P.model.Parent) then
		return false
	end
	local B = PostFight.BEATS
	local center = anchors.RingCenter.Position
	local toRed = anchors.RedCorner and flat(anchors.RedCorner.Position - center) or Vector3.new(0, 0, -1)
	toRed = toRed.Magnitude > 0.1 and toRed.Unit or Vector3.new(0, 0, -1)
	-- they face a ring side (between the red corner and the next post), the hard camera's side
	local face = CFrame.Angles(0, math.rad(45), 0):VectorToWorldSpace(toRed)
	local names = { P.data.name, O.data.name }
	local title = type(opts.ceremony) == "table" and opts.ceremony or nil
	local endSeconds = nil
	if fight.roundSeconds and res.method ~= "UD" and res.method ~= "SD" and res.method ~= "MD" and res.method ~= "Draw" then
		-- (the round clock at the engine's last live event: FightEngine's judge observer keeps it)
		local left = tonumber(fight.judgeRoundLeft) or 0
		endSeconds = math.clamp(fight.roundSeconds - left, 0, fight.roundSeconds)
	end
	local script_ = Judging and Judging.Announce(res, names, { rounds = fight.rounds, time = endSeconds, title = title, kind = fight.offer and fight.offer.kind })
		or { lines = { { at = 0.5, text = "The decision...", kind = "intro" } }, dur = 6, raiseAt = 2.5, winner = res.outcome == "win" and "red" or (res.outcome == "loss" and "blue" or nil) }
	local winner = script_.winner == "red" and P or (script_.winner == "blue" and O or nil)
	local loser = winner and fight:Other(winner) or nil

	-- places: red at the referee's left, blue at his right (a man still down stays down), spaced from the rigs
	local redDown, blueDown = P.state == "down", O.state == "down"
	local refModel = fight.ref and fight.ref.model
	local L = PostFight.Layout(center, face, { red = frameOf(fight, P, P.model), blue = frameOf(fight, O, O.model), ref = frameOf(nil, nil, refModel) }, redDown, blueDown)
	local redAt, blueAt, refAt = L.red, L.blue, L.ref
	local held = {} -- the roots anchored for the scene
	local tagged = {}
	for _, X in ipairs({ { P, redAt, redDown }, { O, blueAt, blueDown } }) do
		local F, at, down = X[1], X[2], X[3]
		if F.model and F.model.Parent and not down then
			-- (a walk in progress - a glide, the AI's last MoveTo - is cancelled: the placement wins)
			F.glideId = (F.glideId or 0) + 1
			F.aiTarget = nil
			if F.hum then
				pcall(function()
					F.hum:MoveTo(at)
				end)
			end
			stand(fight, F, F.model, at, at + face * 10, center, held)
			-- the poses come from the Animator's Trainee path (a Fighter plays guards only)
			CollectionService:RemoveTag(F.model, "Fighter")
			CollectionService:AddTag(F.model, "Trainee")
			setPose(F.model, "pfWait")
			table.insert(tagged, F)
		end
	end
	if refModel and refModel.Parent then
		if fight.ref.hum then
			pcall(function()
				fight.ref.hum:MoveTo(refAt)
			end)
		end
		stand(fight, fight.ref, refModel, refAt, refAt + face * 10, center, held)
		setPose(refModel, (redDown or blueDown) and "pfWait" or "pfHold")
	end

	-- the viewers' side of it (camera, banner, crowd), once
	fight.ceremonySkip = false
	local payload = {
		t = "postfight", lines = script_.lines, dur = script_.dur, raiseAt = script_.raiseAt, hold = title and B.titleHold or B.hold,
		winner = winner and winner.model or nil, loser = loser and loser.model or nil, ref = refModel, center = center, face = face,
		method = res.method, outcome = res.outcome, names = names, scores = res.scores, title = title, stoppage = script_.stoppage,
		downs = { red = redDown, blue = blueDown }, kind = fight.offer and fight.offer.kind or nil,
	}
	fight:SendEach(function(V)
		local m = table.clone(payload)
		m.you = V == P and "red" or "blue"
		return m
	end)

	-- the hand goes up: the referee raises the arm on the winner's side, the winner the arm nearest him
	local raised = false
	local function raise()
		if raised then
			return
		end
		raised = true
		if winner == nil then
			setPose(refModel, "pfRaiseBoth")
			setPose(P.model, "pfHandUpR")
			setPose(O.model, "pfHandUpL")
		else
			local redWon = winner == P
			setPose(refModel, redWon and "pfRaiseL" or "pfRaiseR")
			setPose(winner.model, redWon and "pfHandUpR" or "pfHandUpL")
			if loser and loser.state ~= "down" then
				setPose(loser.model, "pfLose")
			end
		end
		-- the crowd's cue
		local tbl = resultTable(fight, res, opts)
		pcall(function()
			if fight.arena then
				fight.arena:SetAttribute("FightResult", HttpService:JSONEncode(tbl))
			end
		end)
		local ev = remote()
		if ev then
			pcall(function()
				ev:FireAllClients(tbl)
			end)
		end
	end

	local dur = math.min(B.maxDur, script_.dur + (title and B.titleHold or B.hold))
	-- the fight's clock (os.clock in the game; the simulator's fake clock under lune, where a real-time wait
	-- would spin for the whole scene on every simulated bout)
	local now = function()
		return fight.Now and fight:Now() or os.clock()
	end
	local t0 = now()
	local function alive()
		return not fight.aborted and P.model.Parent and (not fight.player or fight.player.Parent)
	end
	while now() - t0 < dur and not fight.ceremonySkip and alive() do
		local t = now() - t0
		if t >= script_.raiseAt then
			raise()
		end
		task.wait(0.05)
	end
	raise() -- (skipped early: the result still goes out to the crowd)
	fight:SendEach(function()
		return { t = "postfightEnd", skipped = fight.ceremonySkip == true }
	end)
	fight.ceremonySkip = false
	-- hand the rigs back (Cleanup takes the Fighter attributes off; the belt ceremony re-tags its winner): the
	-- roots freed first, so nothing is left anchored
	for _, root in ipairs(held) do
		pcall(function()
			root.Anchored = false
		end)
	end
	for _, F in ipairs(tagged) do
		setPose(F.model, nil)
		CollectionService:RemoveTag(F.model, "Trainee")
		CollectionService:AddTag(F.model, "Fighter")
	end
	setPose(refModel, nil)
	task.wait(0.1)
	return true
end

return PostFight
