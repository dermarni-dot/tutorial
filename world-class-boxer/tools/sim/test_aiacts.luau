--!nocheck
-- tools/sim/test_aiacts.luau: the AI ACTS in a career fight built the way Main.server.lua builds one - through
-- FightEngine.Run (the entrance, the tape, the countdown, the round loop on RunService.Heartbeat, Fight:Now), not
-- fightsim's S.Fight - on stub rigs whose parts carry the REAL frame part sizes (BodyAssetData: the frame's mesh
-- family at its tier, Builder.Scales applied, the mesh glove, the feet at the sole), so Fight:Geo reads the frames
-- off the parts as it does in Studio (source "rig", no fallback). Pinned:
--   * Heavyweight vs Lean and Power vs Athletic (both corners): the AI throws its first punch within 6 s of the bell
--     and lands within 20 s; its frames come off the parts; MinSep + 0.3 < PunchRange(jab) and HitTest(jab) at the
--     distance it walks to succeeds (head or body)
--   * against a passive player (he never moves or punches: the Studio report's "it never fights you") the AI's work
--     rate stays over the floor of its level (Config.FightAI.Tier(level).floor punches a minute) at 20 / 40 / 60 / 80
--   * the NPC's punches resolve on the server alone (Punch -> task.delay -> Resolve): no client message is waited on
--   lune run tools/sim/test_aiacts.luau
local process = require("@lune/process")
local FS = require("./fightsim")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local S = FS.new()
local H = S.H
local FightEngine, Config = S.FightEngine, S.Config
local Fight = FightEngine._Fight
local BAD = H.require("BodyAssetData")
local Builder = H.require("Builder")
local HG = H.require("HitGeometry")
local V3, CF = H.globals.Vector3, H.globals.CFrame
local fakeTask = H.globals.task
local Random = H.globals.Random

------------------------------------------------------------------------
-- the harness: the engine's clock and the Heartbeat on fightsim's scheduler, the rig builder and the services Run
-- touches (Builder's cosmetics are not the point here: stubbed)
------------------------------------------------------------------------
Fight.Now = function()
	return S.now()
end
Fight.Wait = function(self, t)
	local t0 = S.now()
	while S.now() - t0 < t and not self.finished and not self.aborted do
		fakeTask.wait(math.min(0.25, t))
	end
end
local HB_DT = 1 / 30
H.Service("RunService")._props.Heartbeat = {
	Wait = function()
		fakeTask.wait(HB_DT)
		return HB_DT
	end,
	Connect = function()
		return { Connected = true, Disconnect = function(c)
			c.Connected = false
		end }
	end,
}
-- the ring walk on the scheduler too (RingWalk.Env: the tests' clock and wait)
do
	local server = H.Service("ServerScriptService"):FindFirstChild("Server")
	local node = server and server:FindFirstChild("RingWalk")
	local ok, RingWalk = pcall(H.requireNode, node)
	if ok and type(RingWalk) == "table" then
		RingWalk.Env = { clock = function()
			return S.now()
		end, wait = function(t)
			return fakeTask.wait(t)
		end, noEntourage = true }
	end
end
-- the shared clock the client stamps its presses with (FightEngine.ServerTime): the scheduler's
H.Service("Workspace")._props.GetServerTimeNow = function()
	return S.now()
end

local GLOVE = { 0.5994, 0.95, 0.8074 } -- the mesh glove (GearAssetData Glove_L)
-- a stub rig with the frame's real part sizes: parts with Size / Position in the rest pose over the sole (the unit's
-- joint heights x the height scale), the feet on the sole, a root that follows its CFrame, a Humanoid that walks
local function rig(frameId, hIn, tier, pos, look, name)
	local app = { gender = 1, height = hIn, body = { frame = frameId } }
	local sc = Builder.Scales(app, nil, nil)
	local fam = BAD.frames[frameId]
	local tiers = fam and fam.tiers or BAD.tiers
	local unit = fam and fam.unit or BAD.unit
	local parts = tiers[tier].parts
	local hs, ws, ds, hd = sc.height, sc.width, sc.depth, sc.head
	local J = unit.joints
	local rootY = unit.rootHeight * hs
	local root = setmetatable({ _cf = CF.lookAt(pos + V3.new(0, rootY, 0), look + V3.new(0, rootY, 0)), Size = V3.new(2, 2, 1), Parent = true, AssemblyLinearVelocity = V3.zero, Name = "HumanoidRootPart" }, {
		__index = function(t, k)
			if k == "CFrame" then
				return rawget(t, "_cf")
			elseif k == "Position" then
				return rawget(t, "_cf").Position
			elseif k == "SetNetworkOwner" then
				return function() end
			elseif k == "IsA" then
				return function(_, c)
					return c == "BasePart" or c == "Part" or c == "PVInstance"
				end
			end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "CFrame" then
				rawset(t, "_cf", v)
			else
				rawset(t, k, v)
			end
		end,
	})
	-- the body parts, at their rest heights over the root's own sole (the root sits at rootY over it)
	local body = {}
	local soleW = pos.Y -- the sole in world space (the rig is built standing on pos)
	local function add(pname, sz, cy, k)
		k = k or { ws, hs, ds }
		body[pname] = { Name = pname, Size = V3.new(sz[1] * k[1], sz[2] * k[2], sz[3] * k[3]), Position = V3.new(pos.X, soleW + cy, pos.Z), FindFirstChild = function()
			return nil
		end, IsA = function(_, c)
			return c == "BasePart" or c == "Part" or c == "PVInstance"
		end }
	end
	local headSz = 1.2 * hd
	add("Head", { 1.2, 1.2, 1.2 }, unit.neckHeight * hs + (0.5 + 0.26) * headSz, { hd, hd, hd })
	add("UpperTorso", parts.UpperTorso.size, (J.Waist[2] + J.Neck[2]) / 2 * hs)
	add("LowerTorso", parts.LowerTorso.size, (unit.hipHeight + J.Waist[2]) / 2 * hs)
	add("LeftUpperArm", parts.LeftUpperArm.size, (J.RightShoulder[2] + J.RightElbow[2]) / 2 * hs)
	add("LeftLowerArm", parts.LeftLowerArm.size, (J.RightElbow[2] + J.RightWrist[2]) / 2 * hs)
	add("LeftHand", parts.LeftHand.size, J.RightWrist[2] * hs - parts.LeftHand.size[2] * hs / 2)
	add("GloveL", GLOVE, J.RightWrist[2] * hs - GLOVE[2] / 2, { 1, 1, 1 })
	local foot = parts.LeftFoot and parts.LeftFoot.size or { 0.44, 0.52, 0.91 }
	add("LeftFoot", foot, foot[2] * hs / 2)
	add("RightFoot", foot, foot[2] * hs / 2)
	local hum = { WalkSpeed = 0, MoveDirection = V3.zero, HipHeight = unit.hipHeight * hs, Parent = true, target = nil, AutoRotate = true, JumpHeight = 7.2, UseJumpPower = false, RequiresNeck = true }
	function hum:MoveTo(p)
		self.target = p
	end
	function hum:ChangeState() end
	function hum:FindFirstChild()
		return nil
	end
	function hum:IsA(c)
		return c == "Humanoid"
	end
	local attrs = {}
	local model = { attrs = attrs, Parent = true, Name = name or "Rig" }
	function model:SetAttribute(k, v)
		attrs[k] = v
	end
	function model:GetAttribute(k)
		return attrs[k]
	end
	function model:FindFirstChildOfClass(c)
		return c == "Humanoid" and hum or nil
	end
	function model:FindFirstChild(n)
		if n == "HumanoidRootPart" then
			return root
		end
		return body[n]
	end
	function model:GetDescendants()
		return {}
	end
	function model:PivotTo(cf)
		root.CFrame = cf
	end
	function model:GetPivot()
		return root.CFrame
	end
	hum.Parent = model
	root.Parent = model
	return model, root, hum
end

-- Builder's cosmetics are not under test: the NPC is the stub rig, everything else a no-op
local pendingNPC = nil
Builder.CreateNPC = function(app, build, gear, name, opts)
	if name == "Referee" or not pendingNPC then
		return nil
	end
	local m = pendingNPC
	pendingNPC = nil
	return m
end
for _, k in ipairs({ "Cosmetics", "SetHeadgear", "OnPlaced", "SetDamage", "SetRobe" }) do
	Builder[k] = function() end
end

-- the stub rigs' walking (the Humanoid's MoveTo at its WalkSpeed) and facing
local function walk(fight, dt)
	for _, F in ipairs(fight.pair or { fight.P, fight.O }) do
		local hum, root = F.hum, F.root
		local O = fight:Other(F)
		local p = root.Position
		local mv = V3.zero
		if hum.target and hum.WalkSpeed > 0 and F.state ~= "down" then
			local d = V3.new(hum.target.X - p.X, 0, hum.target.Z - p.Z)
			local m = d.Magnitude
			if m > 0.05 then
				local step = math.min(m, hum.WalkSpeed * dt)
				mv = d.Unit * step
				hum.MoveDirection = d.Unit
			else
				hum.MoveDirection = V3.zero
			end
		else
			hum.MoveDirection = V3.zero
		end
		local np = p + mv
		local lookAt = V3.new(O.root.Position.X, np.Y, O.root.Position.Z)
		if (lookAt - np).Magnitude > 0.05 then
			root.CFrame = CF.lookAt(np, lookAt)
		else
			root.CFrame = CF.new(np)
		end
	end
end

local ARCH = { Swarmer = "Pressure", CounterPuncher = "Counter", BoxerPuncher = "Technician", Slugger = "KO", OutBoxer = "Defensive" }
local function boxer(spec, rng)
	local d = S.Boxer({ style = spec.style, level = spec.level, frame = spec.frame }, rng)
	d.height, d.reach = spec.height or 70, spec.height or 70
	d.app = { gender = 1, height = spec.height or 70, body = { frame = spec.frame or "Athletic" } }
	d.archetype = ARCH[spec.style or "BoxerPuncher"]
	return d
end

-- a career fight through FightEngine.Run: red = the (passive) player, blue = the AI. Runs `seconds` of the first
-- round after the bell, then aborts the bout (Run unwinds through Cleanup). Returns what happened.
local function career(spec)
	local rng = Random.new(spec.seed or 1)
	S.setClock(5000)
	local pData = boxer(spec.red, rng)
	pData.isPlayer = true
	local oData = boxer(spec.blue, rng)
	local ringY = 0
	local center = V3.new(0, ringY, 0)
	local char = rig(spec.red.frame or "Athletic", spec.red.height or 70, spec.red.tier or 3, V3.new(-8, ringY, -8), center, "Player")
	local npc = rig(spec.blue.frame or "Athletic", spec.blue.height or 70, spec.blue.tier or 3, V3.new(8, ringY, 8), center, oData.name)
	pendingNPC = npc
	local player = { Character = char, Parent = true, Name = "Tester", UserId = 1 }
	local msgs = {}
	local remote = { FireClient = function(_, plr, msg)
		table.insert(msgs, msg)
	end }
	local function anchor(n, x, z)
		return { Name = n, Position = V3.new(x, ringY, z) }
	end
	local anchors = { anchor("RingCenter", 0, 0), anchor("RedCorner", -8, -8), anchor("BlueCorner", 8, 8), anchor("RedNeutral", -8, 8), anchor("BlueNeutral", 8, -8),
		anchor("RedEntrance", 0, -30), anchor("BlueEntrance", 0, 30), anchor("RedSteps", 0, -20), anchor("BlueSteps", 0, 20) }
	local arena = { Name = "Arena", Parent = true, Destroy = function() end, GetAttribute = function(_, k)
		return k == "RingHalf" and 11 or nil
	end, WaitForChild = function(_, n)
		return { GetChildren = function()
			return anchors
		end }
	end, FindFirstChild = function()
		return nil
	end }
	local offer = { kind = "Pro", rounds = spec.rounds or 4, venue = "Arena", stakes = {}, playerStakes = {} }
	local out = { msgs = msgs, firstThrow = nil, firstLand = nil, err = nil, thrown = 0, landed = 0, liveFor = 0 }
	local done = false
	fakeTask.spawn(function()
		local ok, err = pcall(function()
			FightEngine.Run(player, remote, offer, pData, oData, arena, spec.opts)
		end)
		if not ok then
			out.err = err
		end
		done = true
	end)
	local dt = HB_DT
	local liveAt = nil
	local guard = 0
	while not done and guard < 20000 do
		guard += 1
		S.advance(dt)
		local fight = FightEngine.Active[player]
		if fight and fight.P and fight.O then
			out.fight = fight
			walk(fight, dt)
			if fight.live and not fight.paused then
				liveAt = liveAt or S.now()
				out.liveFor = S.now() - liveAt
				local O = fight.O
				if not out.firstThrow and O.totals.thrown > 0 then
					out.firstThrow = out.liveFor
				end
				if not out.firstLand and O.totals.landed > 0 then
					out.firstLand = out.liveFor
				end
				out.thrown, out.landed = O.totals.thrown, O.totals.landed
				if spec.onTick then
					spec.onTick(fight, out.liveFor)
				end
				if out.liveFor >= (spec.seconds or 25) and not fight.aborted then
					fight.aborted = true
					fight.finished = true
				end
			end
		end
	end
	out.done = done
	if not done and process.env.AIACTS_DEBUG then
		local f = FightEngine.Active[player]
		local last = {}
		for i = math.max(1, #msgs - 4), #msgs do
			table.insert(last, tostring(msgs[i] and msgs[i].t))
		end
		print(string.format("DEBUG stuck: now=%.1f msgs=%d last=[%s] round=%s live=%s inCountdown=%s guard=%d", S.now(), #msgs, table.concat(last, ","), tostring(f and f.round), tostring(f and f.live), tostring(f and f.inCountdown), guard))
	end
	return out
end

------------------------------------------------------------------------
-- the pairings: the AI throws and lands, off frames read from the parts
------------------------------------------------------------------------
local PAIRS = {
	{ red = { frame = "Heavyweight Build", height = 78, style = "Slugger", level = 50 }, blue = { frame = "Lean", height = 70, style = "OutBoxer", level = 50 } },
	{ red = { frame = "Lean", height = 70, style = "OutBoxer", level = 50 }, blue = { frame = "Heavyweight Build", height = 78, style = "Slugger", level = 50 } },
	{ red = { frame = "Power Build", height = 72, style = "BoxerPuncher", level = 50 }, blue = { frame = "Athletic", height = 70, style = "BoxerPuncher", level = 50 } },
	{ red = { frame = "Athletic", height = 70, style = "BoxerPuncher", level = 50 }, blue = { frame = "Power Build", height = 72, style = "BoxerPuncher", level = 50 } },
}
for i, pr in ipairs(PAIRS) do
	local tag = string.format("%s(%d) vs AI %s(%d)", pr.red.frame, pr.red.height, pr.blue.frame, pr.blue.height)
	local r = career({ red = pr.red, blue = pr.blue, seed = 100 + i, seconds = 25 })
	check("run: " .. tag .. " ran without an error", r.err == nil and r.done, r.err)
	local f = r.fight
	check("run: " .. tag .. " went live (and boxed on, or ended by a stoppage)", f ~= nil and (r.liveFor > 20 or f.finished), r.liveFor)
	if f then
		local P, O = f.P, f.O
		check("geo: " .. tag .. " both frames come off the parts", P.geo and O.geo and P.geo.source == "rig" and O.geo.source == "rig" and not P.geoFallback and not O.geoFallback,
			tostring(P.geo and P.geo.source) .. "/" .. tostring(O.geo and O.geo.source) .. " " .. tostring(P.geoFallback) .. " " .. tostring(O.geoFallback))
		check("geo: " .. tag .. " the AI has a brain built by Run", O.ai ~= nil and O.ai.tier ~= nil)
		local sep, jabO, jabP = f:MinSep(), f:PunchRange(O, "jab"), f:PunchRange(P, "jab")
		check("invariant: " .. tag .. " MinSep + 0.3 < PunchRange(jab) both ways", sep + 0.3 < jabO and sep + 0.3 < jabP, string.format("sep %.2f jabO %.2f jabP %.2f", sep, jabO, jabP))
		local rest = math.max(sep, O.ai:Range())
		local hj, hc = f:HitTest(O, P, "jab", false, rest), f:HitTest(O, P, "cross", false, rest)
		check("invariant: " .. tag .. " the AI's jab and cross land from where it stands", hj.ok and hc.ok, string.format("rest %.2f jab %s cross %s", rest, tostring(hj.why), tostring(hc.why)))
		check("acts: " .. tag .. " the AI throws within 6 s of the bell", r.firstThrow ~= nil and r.firstThrow <= 6, r.firstThrow)
		check("acts: " .. tag .. " the AI lands within 20 s", r.firstLand ~= nil and r.firstLand <= 20, r.firstLand)
		check("acts: " .. tag .. " the AI's decisions are logged", O.ai.log and #O.ai.log > 0)
	end
end

------------------------------------------------------------------------
-- the passive player: the AI's work rate over its floor at every level (never passive)
------------------------------------------------------------------------
for _, lvl in ipairs({ 20, 40, 60, 80 }) do
	local T = Config.FightAI.Tier(lvl)
	local r = career({ red = { frame = "Athletic", height = 70, style = "BoxerPuncher", level = lvl }, blue = { frame = "Athletic", height = 70, style = "BoxerPuncher", level = lvl }, seed = 200 + lvl, seconds = 30 })
	local ppm = r.liveFor > 0 and r.thrown / r.liveFor * 60 or 0
	check(string.format("work: L%d AI vs a passive player throws %.0f/min (floor %.0f)", lvl, ppm, T.floor), r.err == nil and ppm >= T.floor * 0.8, string.format("%.1f/min thrown %d in %.1fs %s", ppm, r.thrown, r.liveFor, tostring(r.err)))
	check(string.format("work: L%d AI first punch within 6 s", lvl), r.firstThrow ~= nil and r.firstThrow <= 6, r.firstThrow)
end
-- the work floor grows with the level, and a debut's AI is easier but still throws
check("work: the floor grows with the level", Config.FightAI.Tier(20).floor < Config.FightAI.Tier(50).floor and Config.FightAI.Tier(50).floor < Config.FightAI.Tier(80).floor)
check("work: the debut floor is well over the minimum", Config.FightAI.Tier(0).floor >= 2 * Config.FightAI.floorMin)
check("work: the elite reacts quicker and reads more", Config.FightAI.Tier(90).react < Config.FightAI.Tier(20).react and Config.FightAI.Tier(90).read > Config.FightAI.Tier(20).read)

------------------------------------------------------------------------
-- the brain: reads and openings (FightAI on a fightsim fight: the stub rigs, the scheduler's clock)
------------------------------------------------------------------------
do
	local FightAI = S.FightAI
	local Random = H.globals.Random
	local function newFight(blueStyle, level)
		S.setClock(9000)
		local rng = Random.new(3)
		local red = S.Boxer({ style = "BoxerPuncher", level = level or 60 }, rng)
		local blue = S.Boxer({ style = blueStyle or "BoxerPuncher", level = level or 60 }, rng)
		local f = S.NewFight(red, blue, 3, 5)
		f.live, f.round = true, 1
		f.roundEnd = S.now() + 60
		for _, F in ipairs({ f.P, f.O }) do
			F.health, F.body, F.stamina, F.balance, F.traits = 100, 100, F.maxStam, 100, {}
		end
		local ai = FightAI.new(f.O, f.P, f)
		ai.rng = Random.new(7)
		f.O.ai = ai
		return f, ai
	end
	-- (a fixed-roll rng: every chance passes)
	local function always(ai)
		ai.rng = { NextNumber = function(_, a, b)
			return a and (a + (b - a) * 0.0) or 0
		end, NextInteger = function(_, a)
			return a
		end }
	end
	-- his miss: the opening is fired into a perception delay later
	do
		local f, ai = newFight("CounterPuncher", 70)
		always(ai)
		ai:OnOppMiss("cross", "evaded")
		check("brain: his miss opens a window a perception delay later", ai.openAt > S.now() and ai.openUntil > ai.openAt and ai.openWhy:find("cross") ~= nil, ai.openWhy)
		local g, ai2 = newFight("CounterPuncher", 70)
		always(ai2)
		ai2:OnOppMiss("jab", "short")
		check("brain: a punch that fell short opens nothing", ai2.openUntil == 0)
	end
	-- the exploits: a covering man gets the body hooks or the uppercut up the middle; a hurt man the head
	do
		local f, ai = newFight("BoxerPuncher", 70)
		always(ai)
		local c = ai:ExploitCombo("covering", 3.6)
		local body, upper = 0, 0
		for _, step in ipairs(c or {}) do
			if step.body then
				body += 1
			end
			if step.p == "uppercut" then
				upper += 1
			end
		end
		check("brain: a man shelled up gets the body (or the uppercut through the middle)", c ~= nil and (body > 0 or upper > 0), c and #c)
		local h = ai:ExploitCombo("hurt", 3.6)
		local headOnly = h ~= nil
		for _, step in ipairs(h or {}) do
			headOnly = headOnly and not step.body
		end
		check("brain: a hurt man is finished upstairs", headOnly)
		check("brain: nothing fits from across the ring", ai:ExploitCombo("hurt", 12) == nil)
	end
	-- survival is for a dazed head; the other man dazed is the finish; low on health but clear-headed it fights on
	do
		local f, ai = newFight("BoxerPuncher", 60)
		f.O.health, f.O.tier = 25, 1
		ai:UpdateMode()
		check("brain: dazed it survives (holds, covers, moves, still throws at its survival floor)", ai.mode == "survive", ai.mode)
		local g, ai2 = newFight("BoxerPuncher", 60)
		g.O.health = 31
		ai2:UpdateMode()
		check("brain: low on health but clear-headed it keeps fighting", ai2.mode ~= "survive", ai2.mode)
		g.P.tier, g.P.health = 1, 25
		ai2.nextMode = 0
		ai2:UpdateMode()
		check("brain: him dazed, it goes for the finish", ai2.mode == "finish", ai2.mode)
	end
	-- the read of his feet: a man who keeps backing away
	do
		local f, ai = newFight("Swarmer", 60)
		local V3, CF = H.globals.Vector3, H.globals.CFrame
		for i = 1, 60 do
			f.P.root.CFrame = CF.new(V3.new(-3 - i * 0.05, 3.2, 0))
			ai:Observe(1 / 30)
		end
		check("brain: it reads a man backing away (his retreat speed)", ai.oBack > 1, ai.oBack)
	end
	-- the prediction it trusts only while it works: wrong guesses against a man with no pattern switch it off
	do
		local f, ai = newFight("CounterPuncher", 80)
		ai.predAcc = 0.5
		for i = 1, 12 do
			ai.expect = { p = "cross", conf = 0.9, at = S.now() }
			ai:OnOppPunch("leadhook", false, 0.3, { hand = "L" })
		end
		check("brain: its guesses keep missing, its prediction rate falls", ai.predAcc < 0.3, ai.predAcc)
	end
	-- the punch for the distance: the jab and the cross from range, the hooks and the uppercut from inside (the
	-- animation's hook lunges out past the jab and registers where it lands, but a boxer does not choose it there)
	do
		local f, ai = newFight("BoxerPuncher", 60)
		local jab = f:PunchRange(f.O, "jab")
		check("brain: from out at its jab's reach it throws the jab, not the hook", ai:Fits("jab", jab * 0.9) and not ai:Fits("leadhook", jab * 0.9) and not ai:Fits("uppercut", jab * 0.9))
		check("brain: inside, the hooks and the uppercut", ai:Fits("leadhook", jab * 0.6) and ai:Fits("uppercut", jab * 0.6))
	end
	-- the guard between its punches (the defence that keeps a busier AI's fights going the rounds); an out-boxer's
	-- defence is his feet
	do
		local f, ai = newFight("BoxerPuncher", 60)
		always(ai)
		f.O.state, f.O.blocking = "idle", false
		check("brain: in his reach and not punching, its hands are up", ai:HandsUp(S.now(), f:PunchRange(f.P, "jab") - 0.5) and f.O.blocking == true)
		check("brain: out of his reach it keeps them free", not ai:HandsUp(S.now(), f:PunchRange(f.P, "jab") + 1.5))
		local g, ob = newFight("OutBoxer", 60)
		always(ob)
		g.O.state, g.O.blocking = "idle", false
		check("brain: an out-boxer moves rather than shells (his body sound)", not ob:HandsUp(S.now(), g:PunchRange(g.P, "jab") - 0.5))
		g.O.body = 40
		check("brain: ...and keeps his elbows in once his body is going", ob:HandsUp(S.now(), g:PunchRange(g.P, "jab") - 0.5))
	end
	-- the style's brain: a counter-puncher counters and punishes more than a swarmer, a swarmer presses harder
	do
		local T = FightAI.TACTICS
		check("brain: a counter-puncher counters most", T.CounterPuncher.counter > T.BoxerPuncher.counter and T.BoxerPuncher.counter > T.Swarmer.counter)
		check("brain: a swarmer presses and works inside", T.Swarmer.press > T.OutBoxer.press and T.Swarmer.inside > T.OutBoxer.inside)
		check("brain: an out-boxer's volume is at range", T.OutBoxer.volume > T.OutBoxer.inside)
	end
	-- the harder default: every level's work floor, the tiers' reaction and read
	do
		local C = Config.FightAI
		check("tiers: the debut floor is a real work rate (>= 12 a minute)", C.Tier(0).floor >= 12, C.Tier(0).floor)
		check("tiers: the elite floor is a champion's (>= 30 a minute)", C.Tier(99).floor >= 30, C.Tier(99).floor)
		check("tiers: the floor never drops with the level", (function()
			for l = 0, 98 do
				if C.Tier(l + 1).floor < C.Tier(l).floor then
					return false
				end
			end
			return true
		end)())
	end
end

------------------------------------------------------------------------
-- the act pipeline: an NPC punch resolves on the server alone
------------------------------------------------------------------------
do
	local src = require("@lune/fs").readFile(H.src .. "/server/FightEngine.lua")
	local punchBody = src:match("function Fight:Punch%(F, ptype, body, counter, fromBuffer, pressAt%)(.-)\nend\n")
	check("pipeline: Punch schedules Resolve itself (task.delay(windup))", punchBody ~= nil and punchBody:find("task.delay(windup, function()", 1, true) ~= nil and punchBody:find("self:Resolve(F, O, ptype, body, stamPct, opts)", 1, true) ~= nil)
	check("pipeline: nothing in Punch waits on the client (no remote, no ack)", punchBody ~= nil and not punchBody:find("remote", 1, true) and not punchBody:find("ack", 1, true))
	check("pipeline: the client's press stamp is optional (an AI punch has none)", src:find("if F.isPlayer and type(pressAt) == \"number\"", 1, true) ~= nil)
end

print(string.format("test_aiacts: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
