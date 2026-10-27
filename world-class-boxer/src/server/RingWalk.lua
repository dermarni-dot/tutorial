-- RingWalk: the pre-fight entrance on the server (FightEngine's Fight:Entrance hands over to RingWalk.Run).
-- Each walk follows Shared.Entrance.Timeline beat by beat - the clients film the same beats from the plan the
-- "entrance" message carries, so the server never waits longer than the walk it sends:
--   tunnel  he stands on the stage at the tunnel mouth (the reveal, his first celebration)
--   aisle   / crowd: he walks the aisle to the ring steps (an NPC by the server's MoveTo, a player by his own client),
--           his coach (the Officials "cornerman" polo + towel) and, at the big rooms, a cutman walking behind him
--   setdown (carried by the crowd: put down at the foot of the steps; the carriers are the clients' own figures)
--   steps   placed on the apron outside his side's ropes (the clients show the climb up the steps)
--   ropes   placed just inside the ropes (the clients show him ducking through)
--   ring    he walks to his corner and does his ring celebration (or climbs the turnbuckle: client visual)
--   robe    the night's last walk: both robes come off
-- Positions are the server's own (Place / MoveTo); every lift, climb and duck the clients draw is a visual offset on
-- the rig, never a move of the fighter. A skip ("entranceSkip": the player, in PvP both) ends the walk at once.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Entrance = require(Shared:WaitForChild("Entrance"))
local Config = require(Shared:WaitForChild("Config"))

local RingWalk = {}

local function optional(fn)
	local ok, mod = pcall(fn)
	return ok and type(mod) == "table" and mod or nil
end
local Builder = optional(function()
	return require(Shared:WaitForChild("Builder", 5))
end)
local Officials = optional(function()
	return require(Shared:WaitForChild("Officials", 5))
end)
local DataManager = optional(function()
	return require(script.Parent:WaitForChild("DataManager", 5))
end)

local TEAM = { Red = { 150, 26, 32 }, Blue = { 30, 56, 150 } }
-- where the entourage walks, in the walker's frame (studs: x right, z back)
local ENTOURAGE_SLOTS = { Vector3.new(-2.1, 0, 2.6), Vector3.new(2.1, 0, 2.9) }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function attr(inst, name)
	local ok, v = pcall(function()
		return inst:GetAttribute(name)
	end)
	return ok and v or nil
end

------------------------------------------------------------------------
-- The context of one walk
------------------------------------------------------------------------
local function profileOf(F)
	if F.player and DataManager and DataManager.Get then
		local ok, p = pcall(DataManager.Get, F.player)
		return ok and type(p) == "table" and p or nil
	end
	return nil
end

-- an AI boxer's belts: his world record (the player's save holds the world) or a champion's robe
local function aiBelts(fight, F)
	local P = fight.P
	local prof = P and profileOf(P)
	local id = F.data and F.data.id
	local world = prof and prof.world
	local b = world and type(world.boxers) == "table" and id and world.boxers[id]
	if type(b) == "table" and type(b.belts) == "table" then
		return #b.belts
	end
	local lo = F.data and F.data.lookOpts
	return (type(lo) == "table" and lo.robe == "Champion") and 1 or 0
end

function RingWalk.Context(fight, F, corner, last)
	local arena = fight.arena
	local stakes = arena and attr(arena, "Stakes")
	local title = (type(stakes) == "string" and stakes ~= "") or (Officials and Officials.TITLE_KINDS and Officials.TITLE_KINDS[fight.offerKind or ""] == true) or false
	local ctx = {
		corner = corner, last = last, venue = fight.venue, spar = fight.spar ~= nil and fight.spar ~= false,
		tutorial = fight.tutorial ~= nil and not fight.debut, title = title,
		importance = tonumber(arena and attr(arena, "Importance")) or 0, pyro = fight.venue == "Stadium",
		seed = (F.data and type(F.data.name) == "string") and #F.data.name * 131 + (tonumber(F.data.id) or 0) or 0,
	}
	if F.isPlayer then
		local prof = profileOf(F)
		ctx.choice = prof and prof.entrance or nil
		ctx.belts = Entrance.BeltCount(prof)
		ctx.popularity = prof and tonumber(prof.popularity) or 0
	else
		ctx.ai = true
		ctx.personality = F.data and F.data.personality
		ctx.belts = aiBelts(fight, F)
		ctx.popularity = 0
	end
	return ctx
end

-- the world points of one corner's walk (on the surfaces a fighter stands on)
function RingWalk.Points(fight, corner)
	local A = fight.anchors
	local centre = A.RingCenter.Position
	local entrance = A[corner .. "Entrance"].Position
	local steps = A[corner .. "Steps"].Position
	local cornerPos = A[corner .. "Corner"].Position
	local half = fight.ringHalf or 11
	local dir = flat(steps - centre)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, corner == "Red" and -1 or 1)
	local diag = flat(cornerPos - centre)
	diag = diag.Magnitude > 0.1 and diag or dir
	return {
		centre = centre, entrance = entrance, steps = steps, corner = cornerPos,
		apron = centre + dir * (half + 1.7), inside = centre + dir * (half - 1.6),
		post = centre + diag.Unit * (half * math.sqrt(2)), half = half,
	}
end

------------------------------------------------------------------------
-- The entourage: the coach in his corner polo and towel (Officials "cornerman"), a cutman at the big rooms
------------------------------------------------------------------------
-- the team's collision group: it collides with nothing (the boxers, the referee, each other, the world), so nobody
-- is pushed by the team without a per-step CanCollide rewrite of every part (the Humanoid turns its torso parts'
-- collisions back on in its own step; the group makes that moot). nil until tried, false when unavailable
local TEAM_GROUP = "Entourage"
local teamGroupReady = nil
local function teamGroup()
	if teamGroupReady == nil then
		teamGroupReady = pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(TEAM_GROUP) then
				PhysicsService:RegisterCollisionGroup(TEAM_GROUP)
			end
			local names = { [TEAM_GROUP] = true, Default = true }
			for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
				names[g.name] = true
			end
			for name in pairs(names) do
				PhysicsService:CollisionGroupSetCollidable(TEAM_GROUP, name, false)
			end
		end)
	end
	return teamGroupReady
end

local function buildMember(fight, corner, i)
	if not (Builder and Builder.CreateNPC and Officials and Officials.Look) then
		return nil
	end
	local ok, model = pcall(function()
		local seed = (fight.rng and fight.rng:NextInteger(1, 2 ^ 30)) or (i * 7919)
		local app, build, gear, opts = Officials.Look(seed, "cornerman", { team = TEAM[corner], venue = fight.venue })
		return Builder.CreateNPC(app, build, gear, i == 1 and "Coach" or "Cutman", opts)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = (i == 1 and "Coach" or "Cutman") .. corner
	local parts = {}
	local grouped = teamGroup()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			if grouped then
				d.CollisionGroup = TEAM_GROUP
			end
			table.insert(parts, d)
		end
	end
	model:SetAttribute("Loop", "walk")
	model:SetAttribute("Role", i == 1 and "Coach" or "Cutman")
	model:SetAttribute("Corner", corner)
	model:SetAttribute("Entourage", true)
	local m = { model = model, root = model:FindFirstChild("HumanoidRootPart"), hum = model:FindFirstChildOfClass("Humanoid"), slot = ENTOURAGE_SLOTS[i], parts = parts }
	if m.hum then
		m.hum.WalkSpeed = 10
		m.hum.AutoRotate = true
	end
	-- fallback without the group: the Humanoid turns collisions back on for its torso parts in its own step, so they
	-- are cleared before every physics step (nobody is pushed by the team)
	if not grouped then
		m.noclip = RunService.Stepped:Connect(function()
			for _, p in ipairs(parts) do
				p.CanCollide = false
			end
		end)
	end
	return m
end

local function dropMember(m)
	if m.noclip then
		m.noclip:Disconnect()
	end
	if m.model then
		m.model:Destroy()
	end
end

local function placeMember(m, pos, lookAt)
	if not (m.root and m.model.Parent) then
		return
	end
	local hh = (m.hum and m.hum.HipHeight > 0.5) and (m.hum.HipHeight + m.root.Size.Y / 2 + 0.05) or 3.2
	local p = Vector3.new(pos.X, pos.Y + hh, pos.Z)
	m.model:PivotTo(CFrame.lookAt(p, Vector3.new(lookAt.X, p.Y, lookAt.Z)))
	if m.hum then
		m.hum:MoveTo(p)
	end
end

------------------------------------------------------------------------
-- Skip
------------------------------------------------------------------------
-- a player asks to skip (FightEngine.Input "entranceSkip"); vs the AI his word ends it, in PvP both must ask
function RingWalk.Skip(fight, F)
	local st = fight and fight.ringWalk
	if not st or st.done then
		return false
	end
	st.skips[F] = true
	if not fight.pvp or (st.skips[fight.P] and st.skips[fight.O]) then
		st.skipped = true
	end
	return st.skipped
end

------------------------------------------------------------------------
-- The run
------------------------------------------------------------------------
-- env (tests): { clock = fn -> s, wait = fn(s), noEntourage = bool }; RingWalk.Env is the default (nil in the game)
RingWalk.Env = nil
function RingWalk.Run(fight, env)
	env = env or RingWalk.Env or {}
	local clock = env.clock or os.clock
	local wait = env.wait or task.wait
	local P, O = fight.P, fight.O
	local st = { skips = {}, skipped = false, done = false, entourage = {}, log = {} }
	fight.ringWalk = st
	local function stop()
		return st.skipped or fight.aborted or fight.finished
	end
	local function log(what, F)
		table.insert(st.log, { t = clock() - st.t0, what = what, who = F and (F == P and "P" or "O") or nil })
	end
	st.t0 = clock()
	-- robes on, both at their tunnels (the walkout guard animates the warm-up)
	for _, X in ipairs({ { O, "Blue" }, { P, "Red" } }) do
		local F = X[1]
		if Builder and F.model then
			pcall(Builder.SetRobe, F.model, F.data.app, true, F.data.lookOpts)
		end
		fight:Place(F, fight.anchors[X[2] .. "Entrance"].Position, fight.anchors.RingCenter.Position)
		F.guardOverride = "walkout"
		F.exprOverride = ((F.data.mental and F.data.mental.Confidence) or 50) > 60 and "confident" or "determined"
		if fight.UpdateGuard then
			fight:UpdateGuard(F)
		end
		if fight.SyncAttrs then
			fight:SyncAttrs(F)
		end
	end
	local walks = {
		{ F = O, corner = "Blue", plan = Entrance.Plan(RingWalk.Context(fight, O, "Blue", false)) },
		{ F = P, corner = "Red", plan = Entrance.Plan(RingWalk.Context(fight, P, "Red", true)) },
	}
	st.walks = walks
	-- the entourage is built while the lead-in runs (CreateNPC yields); a team not ready by its walk stays home.
	-- One member after another, the first walker's team first (four CreateNPCs at once were one long server hitch at
	-- the start of the walk, on top of the clients' own venue build)
	if not env.noEntourage then
		local queue = {}
		for _, w in ipairs(walks) do
			local n = (fight.venue == "Arena" or fight.venue == "Stadium" or w.plan.title) and 2 or 1
			st.entourage[w.F] = {}
			for i = 1, n do
				table.insert(queue, { w = w, i = i })
			end
		end
		task.spawn(function()
			for qi, job in ipairs(queue) do
				if st.done or stop() then
					return
				end
				if qi > 1 then
					task.wait()
				end
				local w, i = job.w, job.i
				local m = buildMember(fight, w.corner, i)
				if not m then
					continue
				end
				-- (a team built after its man has left the tunnel would pop in behind him: it stays home)
				if st.done or stop() or (w.started and clock() - w.started > 1.2) then
					dropMember(m)
					continue
				end
				m.model.Parent = fight.arena
				local pts = RingWalk.Points(fight, w.corner)
				placeMember(m, pts.entrance + (pts.entrance - pts.centre).Unit * 3 + Vector3.new(i == 1 and -2 or 2, 0, 0), pts.centre)
				if m.root then
					pcall(function()
						m.root:SetNetworkOwner(nil)
					end)
				end
				CollectionService:AddTag(m.model, "Ambient")
				table.insert(st.entourage[w.F], m)
			end
		end)
	end
	local function hold(tEnd, each)
		while clock() < tEnd and not stop() do
			if each then
				each()
			end
			wait(math.min(0.2, math.max(0.02, tEnd - clock())))
		end
	end
	hold(st.t0 + Entrance.LEAD)
	if not stop() then
		fight:Comment("Making the walk now... " .. tostring(O.data.name) .. "!", true)
	end
	for wi, w in ipairs(walks) do
		if stop() then
			break
		end
		local W, plan = w.F, w.plan
		local pts = RingWalk.Points(fight, w.corner)
		local beats, total = Entrance.Timeline(plan)
		w.beats, w.total = beats, total
		local wire = table.clone(plan)
		wire.pts = pts
		wire.model = W.model
		wire.arena = fight.arena
		wire.name, wire.nick, wire.record, wire.nat = W.data.name, W.data.nick, W.data.record, W.data.nat
		wire.index = wi
		fight:SendEach(function(V)
			if V == W then
				return { t = "entrance", phase = "you", music = W.data.music, pyro = plan.pyro, plan = wire,
					intro = Config.AnnouncerIntro and (Config.AnnouncerIntro[W.data.voice or "Calm"] or Config.AnnouncerIntro.Calm) or nil }
			end
			return { t = "entrance", phase = "opp", pyro = plan.pyro, plan = wire }
		end)
		if plan.carry then
			fight:Comment("The crowd is carrying " .. tostring(W.data.name) .. " to the ring!", true)
		end
		local w0 = clock()
		w.started = w0
		log("walk", W)
		local team = st.entourage[W] or {}
		local nextFollow = 0
		local function follow()
			-- the team keeps its places behind him (re-aimed five times a second)
			local now = clock()
			if now < nextFollow or not W.root then
				return
			end
			nextFollow = now + 0.2
			local cf = W.root.CFrame
			for _, m in ipairs(team) do
				if m.hum and m.root and m.model.Parent then
					m.hum:MoveTo(cf:PointToWorldSpace(m.slot))
				end
			end
		end
		local function moveNPC(pos, speed)
			if not W.isPlayer and W.hum then
				W.hum.WalkSpeed = speed
				W.hum:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z))
				-- [Studio] the intended velocity for the clients' Animator (its gait on a replicated root follows this)
				if W.root then
					local d = Vector3.new(pos.X - W.root.Position.X, 0, pos.Z - W.root.Position.Z)
					W.model:SetAttribute("Gait", d.Magnitude > 0.5 and d.Unit * speed or nil)
				end
			end
		end
		for _, b in ipairs(beats) do
			if stop() then
				break
			end
			hold(w0 + b.t0, follow)
			if stop() then
				break
			end
			log(b.id, W)
			if b.id == "aisle" then
				moveNPC(pts.steps, plan.speed)
			elseif b.id == "setdown" then
				-- (the jump cut to the steps: the crowd sets him down at the foot of them)
				fight:Place(W, pts.steps, pts.centre)
				moveNPC(pts.steps, plan.speed)
			elseif b.id == "steps" then
				fight:Place(W, pts.apron, pts.centre)
				moveNPC(pts.apron, plan.speed)
				-- the team waits at the foot of the steps
				for i, m in ipairs(team) do
					local side = (pts.steps - pts.centre):Cross(Vector3.yAxis)
					side = side.Magnitude > 0.1 and side.Unit or Vector3.xAxis
					placeMember(m, pts.steps + side * (i == 1 and -3.2 or 3.2), pts.centre)
					m.model:SetAttribute("Loop", "coachwatch")
				end
			elseif b.id == "ropes" then
				fight:Place(W, pts.inside, pts.centre)
				moveNPC(pts.inside, plan.speed)
			elseif b.id == "ring" then
				moveNPC(pts.corner, Entrance.SPEED.ring)
				task.delay(6, function()
					if W.model and W.model.Parent then
						W.model:SetAttribute("Gait", nil)
					end
				end)
			elseif b.id == "robe" then
				hold(w0 + b.t0 + 0.5)
				if Builder then
					for _, F in ipairs({ P, O }) do
						pcall(Builder.SetRobe, F.model, F.data.app, false)
					end
				end
				st.robesOff = true
			end
		end
		hold(w0 + total, follow)
		if not stop() then
			fight:Place(W, pts.corner)
		end
		log("done", W)
	end
	-- the end (or the skip): both in their corners, robes off, the team gone
	st.done = true
	if not (fight.aborted or fight.finished) then
		fight:Place(O, fight.anchors.BlueCorner.Position)
		fight:Place(P, fight.anchors.RedCorner.Position)
		if Builder and not st.robesOff then
			for _, F in ipairs({ P, O }) do
				pcall(Builder.SetRobe, F.model, F.data.app, false)
			end
		end
		fight:Send({ t = "entranceEnd", skipped = st.skipped })
	end
	for _, team in pairs(st.entourage) do
		for _, m in ipairs(team) do
			dropMember(m)
		end
	end
	log("end")
	st.elapsed = clock() - st.t0
	return st
end

return RingWalk
