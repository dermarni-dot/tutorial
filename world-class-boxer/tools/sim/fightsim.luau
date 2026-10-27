--!nocheck
-- tools/sim/fightsim.luau: whole fights, headless, under lune. FightEngine's real Fight methods (Update, Resolve,
-- Knockdown, Count, Rest, ScoreRound...) on stub rigs in a 22-stud ring, with a fake clock and a coroutine
-- scheduler (task.delay / task.spawn / task.wait run on it, so the knockdown count really counts). The red corner
-- is either a second FightAI (AI vs AI) or a scripted player (FightSim.Bot: a policy that plays fair - it only
-- reacts to the AI's punches after a human reaction time). Used by tools/sim/balance.luau (the balance tables)
-- and tools/sim/test_fightai.luau (the tests and the balance bounds).
--
--   local FS = require("./fightsim")
--   local S = FS.new()                                      -- loads the game once
--   local res = S.Fight({ red = { bot = "spam" }, blue = { style = "Slugger", level = 60, traits = { { id = "IronChin", s = 1 } } },
--                         rounds = 6, seed = 7 })
--   -- res = { winner = "red" | "blue" | "draw", method, round, seconds, kd = { red, blue }, landed / thrown, fight, P, O }
local Host = require("./host")
local fs = require("@lune/fs")

local FightSim = {}

function FightSim.new(opts)
	opts = opts or {}
	local S = {}
	-- the scheduler
	local clock = 0
	local queue = {}
	local seq = 0
	local function push(item)
		seq += 1
		item.seq = seq
		table.insert(queue, item)
	end
	local fakeTask = {}
	function fakeTask.delay(t, fn, ...)
		push({ at = clock + (t or 0), fn = fn, args = table.pack(...) })
	end
	function fakeTask.spawn(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(err)
		end
		return co
	end
	fakeTask.defer = fakeTask.spawn
	function fakeTask.wait(t)
		if not coroutine.isyieldable() then
			return 0
		end
		push({ at = clock + (t or 0), co = coroutine.running() })
		return coroutine.yield()
	end
	fakeTask.cancel = function() end
	local function runItem(it)
		if it.co then
			local ok, err = coroutine.resume(it.co, 0)
			if not ok then
				error(err)
			end
		else
			local co = coroutine.create(it.fn)
			local ok, err = coroutine.resume(co, table.unpack(it.args, 1, it.args.n))
			if not ok then
				error(err)
			end
		end
	end
	local function advance(dt)
		local goal = clock + dt
		while true do
			local bi, best = nil, nil
			for i, it in ipairs(queue) do
				if it.at <= goal and (not best or it.at < best.at or (it.at == best.at and it.seq < best.seq)) then
					bi, best = i, it
				end
			end
			if not best then
				break
			end
			table.remove(queue, bi)
			clock = math.max(clock, best.at)
			runItem(best)
		end
		clock = goal
	end
	S.advance = advance
	S.now = function()
		return clock
	end
	S.setClock = function(t)
		clock = t
		table.clear(queue)
	end

	-- (opts.root: another checkout's src - the balance tables' "before" run on an export of an older commit)
	local H = Host.new({ root = opts.root, server = true, globals = { task = fakeTask } })
	S.H = H
	local Config = H.require("Config")
	S.Config = Config
	S.Traits = H.require("Traits")
	S.FightRead = H.require("FightRead")
	local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
	for _, f in ipairs(fs.readDir(H.src .. "/server")) do
		local base = f:match("^(.-)%.lua$")
		if base and not f:find("%.server%.") then
			local n = Host.NewNode(base, "ModuleScript", folder)
			rawset(n, "_file", H.src .. "/server/" .. f)
		end
	end
	local FightEngine = H.requireNode(folder._kids.FightEngine)
	local FightAI = H.requireNode(folder._kids.FightAI)
	local Career = H.requireNode(folder._kids.Career)
	local World = H.requireNode(folder._kids.World)
	S.FightEngine, S.FightAI, S.Career, S.World = FightEngine, FightAI, Career, World
	S.server = folder -- (the server folder's nodes: H.requireNode(S.server._kids.PostFight) loads another module)
	local Fight = FightEngine._Fight
	local V3, CF = H.globals.Vector3, H.globals.CFrame
	local Random = H.globals.Random

	-- a stub rig: a root whose Position follows its CFrame, a Humanoid that walks to its MoveTo at WalkSpeed
	local function rig(pos, look)
		local root = setmetatable({ _cf = CF.lookAt(pos, look), Size = V3.new(2, 2, 1), Parent = true, AssemblyLinearVelocity = V3.zero }, {
			__index = function(t, k)
				if k == "CFrame" then
					return rawget(t, "_cf")
				elseif k == "Position" then
					return rawget(t, "_cf").Position
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
		local hum = { WalkSpeed = 0, MoveDirection = V3.zero, HipHeight = 0, Parent = true, target = nil }
		function hum:MoveTo(p)
			self.target = p
		end
		function hum:ChangeState() end
		local attrs = {}
		local model = { attrs = attrs, Parent = true }
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
			return n == "HumanoidRootPart" and root or nil
		end
		function model:GetDescendants()
			return {}
		end
		function model:PivotTo(cf)
			root.CFrame = cf
		end
		return model, root, hum
	end

	S.StubRig = rig

	local ARCH_OF = { Swarmer = "Pressure", CounterPuncher = "Counter", BoxerPuncher = "Technician", Slugger = "KO", OutBoxer = "Defensive" }
	local simId = 0
	-- a boxer's data at a level (overall ~ level): World.MakeStats as the world makes them
	function S.Boxer(spec, rng)
		spec = spec or {}
		simId += 1
		local style = spec.style or "BoxerPuncher"
		local level = spec.level or 60
		local stats = World.MakeStats(rng, level, style)
		for k, v in pairs(spec.stats or {}) do
			stats[k] = v
		end
		local frac = math.clamp((level - 26) / 64, 0, 1)
		return {
			id = spec.id or ("sim" .. simId), name = spec.name or (style .. " " .. simId), style = style, archetype = spec.archetype or ARCH_OF[style],
			stats = stats, class = 5, record = spec.record or { w = 10, l = 3, d = 0, ko = 5 }, isPlayer = spec.bot ~= nil or nil,
			mental = { Confidence = 40 + frac * 40, Discipline = 60, Aggression = math.floor((Config.FindById(Config.Styles, style).ai.aggression) * 100), Focus = spec.focus or (40 + frac * 40), Composure = 35 + frac * 45 },
			-- (spec.frame: the body frame, Shared.FrameTraits; the engine reads data.app.body.frame; spec.height: the tape's
			-- height in inches, and the reach with it - the stub rigs' hit geometry is built from them)
			app = { gender = 1, body = { frame = spec.frame or "Athletic" }, height = spec.height }, moves = spec.moves, h2h = spec.h2h,
			height = spec.height, reach = spec.reach or spec.height,
		}
	end

	-- the fight: two stub rigs in the ring, the real engine
	function S.NewFight(red, blue, rounds, seed)
		local self = setmetatable({}, Fight)
		self.id = (seed or 1) * 7 + 1
		self.rng = Random.new(seed or 1)
		self.rounds, self.round = rounds or 6, 0
		self.roundSeconds = Config.RoundSeconds
		self.damageScale, self.allowKD = 1, true
		self.aiWork, self.aiRange = 1, 1
		self.cutRisk = {}
		self.cards = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
		self.roundCards, self.knockdowns = {}, {}
		self.offer = { kind = "Pro", rounds = self.rounds }
		self.ringHalf = 11
		local function anchor(x, z)
			return { Position = V3.new(x, 0, z) }
		end
		self.anchors = { RingCenter = anchor(0, 0), RedCorner = anchor(-8, -8), BlueCorner = anchor(8, 8), RedNeutral = anchor(-8, 8), BlueNeutral = anchor(8, -8) }
		self.msgs = { trait = {}, intel = 0, counts = {} }
		local mP, rP, hP = rig(V3.new(-3, 3.2, 0), V3.new(3, 3.2, 0))
		local mO, rO, hO = rig(V3.new(3, 3.2, 0), V3.new(-3, 3.2, 0))
		self.P = FightEngine._makeFighter(red, mP, nil)
		self.O = FightEngine._makeFighter(blue, mO, nil)
		self.pair = { self.P, self.O }
		self.rigK = 1
		self.Now = function()
			return clock
		end
		local msgs = self.msgs
		local function note(m)
			msgs.counts[m.t] = (msgs.counts[m.t] or 0) + 1
			if m.t == "trait" then
				table.insert(msgs.trait, m)
			end
		end
		self.Send = function(_, m)
			note(m)
		end
		self.SendTo = function(_, _, m)
			note(m)
		end
		self.SendEach = function(fight, fn)
			for _, F in ipairs({ fight.P, fight.O }) do
				local m = fn(F)
				if m then
					note(m)
				end
			end
		end
		self.Comment = function() end
		self.RefreshDamage = function() end
		self.SetSweat = function() end
		self.Glide = function(fight, F, goal, speed, onArrive)
			local p = F.root.Position
			F.root.CFrame += V3.new(goal.X - p.X, 0, goal.Z - p.Z)
			if onArrive then
				onArrive()
			end
		end
		return self
	end

	-- the stub rigs' walking (the Humanoid's MoveTo at its WalkSpeed) and their facing (the AlignOrientation);
	-- the stub referee (spec.ref) walks the same way, facing the midpoint
	local function walk(fight, dt)
		local list = fight.pair
		if fight.ref then
			list = { fight.pair[1], fight.pair[2], fight.ref }
		end
		for _, F in ipairs(list) do
			local hum, root = F.hum, F.root
			local O = F ~= fight.ref and fight:Other(F) or nil
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
			local lp = O and O.root.Position or (fight.P.root.Position + fight.O.root.Position) / 2
			local look = V3.new(lp.X, np.Y, lp.Z)
			if (look - np).Magnitude > 0.05 then
				root.CFrame = CF.lookAt(np, look)
			else
				root.CFrame = CF.new(np)
			end
		end
	end

	------------------------------------------------------------------------
	-- the scripted players (fair: a human reaction time to the AI's punches, no peeking)
	------------------------------------------------------------------------
	local Bot = {}
	Bot.__index = Bot
	S.Bot = Bot
	-- policy: { range (share of the jab range), rate (chance per decision to attack), combo { n min, n max },
	-- pool { punch weights }, body (share to the body), react (chance to defend a seen punch), defend (what with),
	-- feint (chance per decision), clinch (when hurt), adapt (reads the trait hints and switches) }
	Bot.Policies = {
		-- one punch, over and over (the AI should learn it and slip it)
		spam = { range = 0.85, rate = 0.55, combo = { 1, 1 }, pool = { jab = 1 }, body = 0, react = 0.15, defend = { "block" } },
		-- 1-2s to the head and nothing else
		onetwo = { range = 0.85, rate = 0.5, combo = { 2, 2 }, seqs = { { "jab", "cross" } }, body = 0, react = 0.25, defend = { "block", "slip" } },
		headhunter = { range = 0.8, rate = 0.45, combo = { 1, 3 }, pool = { cross = 1, leadhook = 1.2, rearhook = 1, uppercut = 0.6, overhand = 0.5 }, body = 0.03, react = 0.3, defend = { "block", "slip", "roll" } },
		body = { range = 0.78, rate = 0.45, combo = { 1, 3 }, pool = { jab = 0.6, cross = 0.8, leadhook = 1.2, rearhook = 1, uppercut = 0.5 }, body = 0.7, react = 0.3, defend = { "block", "slip" } },
		volume = { range = 0.84, rate = 0.7, combo = { 3, 5 }, pool = { jab = 1, cross = 1, leadhook = 0.7, rearhook = 0.5, uppercut = 0.3 }, body = 0.2, react = 0.25, defend = { "block", "slip" } },
		power = { range = 0.8, rate = 0.35, combo = { 1, 2 }, pool = { cross = 0.6, rearhook = 1.2, uppercut = 1, overhand = 1.2 }, body = 0.1, react = 0.3, defend = { "block", "roll" } },
		counter = { range = 0.95, rate = 0.18, combo = { 1, 2 }, pool = { jab = 0.6, cross = 1, leadhook = 0.8 }, body = 0.15, react = 0.55, defend = { "slip", "pull", "weave", "parry", "block" }, counters = true, guard = 0.5, pace = true },
		pressure = { range = 0.68, rate = 0.6, combo = { 2, 4 }, pool = { jab = 0.6, cross = 0.8, leadhook = 1, rearhook = 0.8, uppercut = 0.6 }, body = 0.35, react = 0.25, defend = { "block", "weave" }, cut = 0.7 },
		-- the thinking player: mixes it up, feints, reads the trait hints and switches to the counter; he works where his
		-- hooks and uppercuts land (since the reach was fitted to the animation's glove the hooks reach about 0.75 of the
		-- jab, not 0.97: 0.72 of it, the share FightAI throws its own hooks inside)
		smart = { range = 0.72, rate = 0.42, combo = { 1, 4 }, pool = { jab = 1, cross = 1, leadhook = 0.9, rearhook = 0.7, uppercut = 0.6, overhand = 0.3 }, body = 0.3, react = 0.45, defend = { "slip", "block", "weave", "pull" }, feint = 0.08, counters = true, adapt = true, clinch = true, guard = 0.5, pace = true },
		-- a beginner: wild, slow to react, never defends well
		novice = { range = 0.8, rate = 0.4, combo = { 1, 3 }, pool = { jab = 1, cross = 1, leadhook = 0.8, rearhook = 0.8, uppercut = 0.4, overhand = 0.4 }, body = 0.15, react = 0.1, defend = { "block" }, guard = 0.2 },
	}
	-- how the smart bot answers a trait hint (Traits.Data counters, as a player would play them)
	local ADAPT = {
		IronChin = { body = 0.65, pool = { jab = 1.2, cross = 0.6, leadhook = 1, rearhook = 0.8, uppercut = 0.3 } },
		BodyArmor = { body = 0.05, pool = { jab = 1.2, cross = 1, uppercut = 1, leadhook = 0.6 } },
		Slick = { body = 0.45, pool = { leadhook = 1.2, rearhook = 1, uppercut = 0.6, jab = 0.3, cross = 0.3 }, feint = 0.25 },
		Weaver = { body = 0.25, pool = { jab = 1, cross = 1.2, uppercut = 1.2, leadhook = 0.2 } },
		CounterSpecialist = { combo = { 1, 2 }, feint = 0.3 },
		Granite = { rate = 0.62, combo = { 2, 4 }, pool = { jab = 1.2, cross = 1, leadhook = 0.6 } },
		PressureProof = { range = 0.95, cut = 0, pool = { jab = 1.4, cross = 1 } },
		RingGeneral = { body = 0.5, cut = 0.9, feint = 0.2 },
	}
	S.ADAPT = ADAPT

	function Bot.new(policy, F, O, engine, rng)
		local self = setmetatable({}, Bot)
		self.pol = table.clone(Bot.Policies[policy] or Bot.Policies.smart)
		self.name = policy
		self.F, self.O, self.engine, self.rng = F, O, engine, rng
		self.nextThink, self.queue, self.reaction = 0, {}, 0.2
		self.seen = 0
		self.obs = { slips = 0 } -- (an older engine counts the AI's misses here)
		return self
	end
	function Bot:Observe() end
	function Bot:UpdateMode() end
	function Bot:OnOppComboEnd() end
	-- a human sees the AI's punch after its reaction time and does what he was going to do
	function Bot:OnOppPunch(ptype, body, windup, info)
		local F, engine = self.F, self.engine
		if self.rng:NextNumber() > self.pol.react or engine:Now() < F.busyUntil then
			return
		end
		local react = self.reaction + self.rng:NextNumber() * 0.08
		if react >= windup then
			return
		end
		local kind = S.Config.Punches[ptype].kind
		local list = self.pol.defend
		local move = list[self.rng:NextInteger(1, #list)]
		-- (a sensible player: the slip for straights, the weave for hooks, the guard for the body)
		if body then
			move = "block"
		elseif move == "slip" and (kind == "hook" or kind == "overhand") then
			move = self.rng:NextNumber() < 0.5 and "weave" or "slip"
		elseif (move == "weave" or move == "roll") and kind == "straight" then
			move = "slip"
		elseif move == "parry" and kind ~= "straight" then
			move = "block"
		end
		local hand = (info and info.hand) or S.Config.Punches[ptype].hand
		fakeTask.delay(react, function()
			if engine.finished or F.state == "down" then
				return
			end
			if move == "slip" then
				engine:Slip(F, hand == "L" and -1 or 1)
			elseif move == "parry" then
				engine:Parry(F)
			elseif move == "roll" then
				engine:Roll(F)
			elseif move == "block" then
				engine:SetBlock(F, true)
				self.blockUntil = engine:Now() + 0.5
			else
				engine:Dodge(F, move, self.rng:NextNumber() < 0.5 and -1 or 1)
			end
		end)
	end
	function Bot:Adapt()
		if not self.pol.adapt then
			return
		end
		local tr = self.engine.msgs.trait
		if #tr > (self.seen or 0) then
			for i = self.seen + 1, #tr do
				local a = ADAPT[tr[i].id]
				if a then
					for k, v in pairs(a) do
						self.pol[k] = v
					end
				end
			end
			self.seen = #tr
		end
	end
	-- the punch he actually throws: a player reads the HUD's range read-out (FightClient's KM.rangeTag: the server's
	-- HitGeometry test on the same frames - JAB RANGE, INSIDE, OUT OF RANGE) and the press's OUT OF RANGE flash, so a
	-- hook or an uppercut that cannot reach from here (the hooks land about a stud inside the jab since the reach was
	-- fitted to the animation's glove) goes out as the jab instead; a punch nothing reaches with is thrown anyway
	-- (he is walking in)
	function Bot:Throw(p, body)
		local F, O, engine = self.F, self.O, self.engine
		if p ~= "jab" and engine.HitTest then
			local dist = engine:Distance(F, O)
			local hit = engine:HitTest(F, O, p, body, dist)
			if not hit.ok and hit.why == "short" and engine:HitTest(F, O, "jab", body, dist).ok then
				p = "jab"
			end
		end
		engine:Punch(F, p, body)
	end
	function Bot:Pick()
		local pool = self.pol.pool
		local total = 0
		for _, w in pairs(pool) do
			total += w
		end
		local pick = self.rng:NextNumber() * total
		local keys = {}
		for k in pairs(pool) do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			pick -= pool[k]
			if pick <= 0 then
				return k
			end
		end
		return "jab"
	end
	function Bot:Think(now)
		local F, O, engine = self.F, self.O, self.engine
		if now < self.nextThink then
			return
		end
		self.nextThink = now + 0.25 + self.rng:NextNumber() * 0.1
		self:Adapt()
		if F.state == "down" or O.state == "down" then
			self.queue = {}
			return
		end
		if F.state == "clinch" then
			if self.pol.clinch and self.rng:NextNumber() < 0.4 then
				engine:Punch(F, "leadhook", true)
			end
			return
		end
		local dist = engine:Distance(F, O)
		local jab = engine:PunchRange(F, "jab")
		local hurt = (F.tier or 0) >= 1
		engine:MoveAI(F, jab * (hurt and 1.6 or self.pol.range), (self.rng:NextNumber() < 0.5 and -0.25 or 0.25), self.pol.cut or 0.2)
		if F.blocking and now >= (self.blockUntil or 0) then
			engine:SetBlock(F, false)
		end
		if now < F.busyUntil then
			return
		end
		if hurt and self.pol.clinch and engine:CanClinch(F) and self.rng:NextNumber() < 0.3 then
			engine:Clinch(F)
			return
		end
		if self.pol.counters and now < F.counterUntil and dist <= engine:PunchRange(F, "cross") then
			engine:Punch(F, "cross", false)
			return
		end
		if #self.queue > 0 then
			local nx = table.remove(self.queue, 1)
			self:Throw(nx.p, nx.body)
			self.nextThink = math.min(self.nextThink, F.busyUntil + 0.05)
			return
		end
		if now < (F.feintOpenUntil or 0) then
			self:Throw(self:Pick(), self.rng:NextNumber() < self.pol.body)
			return
		end
		if dist > jab + 0.3 then
			return
		end
		if self.pol.feint and self.rng:NextNumber() < self.pol.feint then
			engine:Feint(F)
			self.nextThink = math.min(self.nextThink, F.busyUntil + 0.05)
			return
		end
		-- (a player who manages his gas eases off as the tank empties; a novice punches himself out)
		local stam = F.stamina / F.maxStam
		local pace = self.pol.pace and math.clamp((stam - 0.2) / 0.4, 0.25, 1) or (stam < 0.25 and 0.5 or 1)
		if self.rng:NextNumber() < self.pol.rate * pace then
			local seqs = self.pol.seqs
			local list = {}
			if seqs then
				for _, p in ipairs(seqs[self.rng:NextInteger(1, #seqs)]) do
					table.insert(list, { p = p, body = false })
				end
			else
				local n = self.rng:NextInteger(self.pol.combo[1], self.pol.combo[2])
				for _ = 1, n do
					local p = self:Pick()
					table.insert(list, { p = p, body = p ~= "overhand" and self.rng:NextNumber() < self.pol.body })
				end
			end
			local first = table.remove(list, 1)
			self.queue = list
			self:Throw(first.p, first.body)
			self.nextThink = math.min(self.nextThink, F.busyUntil + 0.05)
		elseif self.rng:NextNumber() < (self.pol.guard or 0.3) then
			-- (a player keeps his hands up between his punches: the guard, held a moment)
			engine:SetBlock(F, true)
			self.blockUntil = now + 0.45
		end
	end

	------------------------------------------------------------------------
	-- a whole fight
	------------------------------------------------------------------------
	-- spec = { red = boxer spec (+ bot = policy name, or an AI), blue = boxer spec (+ traits = { {id, s} } to force,
	-- noTraits), rounds, seed, dt }
	function S.Fight(spec)
		local rng = Random.new(spec.seed or 1)
		S.setClock(1000)
		local red = S.Boxer(spec.red, rng)
		local blue = S.Boxer(spec.blue, rng)
		local fight = S.NewFight(red, blue, spec.rounds or 6, spec.seed or 1)
		local P, O = fight.P, fight.O
		-- the ring traits: forced, none, or the seed's (as a career bout would have them)
		for _, X in ipairs({ { P, spec.red }, { O, spec.blue } }) do
			local F, sp = X[1], X[2]
			if sp.traits then
				F.traits = sp.traits
			elseif sp.noTraits or sp.bot then
				F.traits = {}
			else
				F.traits = F.traitsAll or {}
			end
		end
		-- (the seeded generator replaces the AI's own, and the draw FightAI.new made from that unseeded one - the way it
		-- circles - is made again off the seed: the same seed is the same fight, run after run. The stub Random's first
		-- draw barely moves with a small seed: the second one)
		local function seedAI(ai, seed)
			ai.rng = Random.new(seed)
			local dir = Random.new(seed * 3 + 1)
			dir:NextNumber()
			ai.circleDir = dir:NextNumber() < 0.5 and -1 or 1
		end
		O.ai = FightAI.new(O, P, fight)
		seedAI(O.ai, (spec.seed or 1) * 31 + 5)
		-- (spec.ref: a stub referee the engine's UpdateReferee moves, as SpawnReferee's R; walk() walks him)
		if spec.ref then
			local mR, rR, hR = rig(V3.new(0, 3.2, 7), V3.new(0, 3.2, 0))
			hR.WalkSpeed = 9
			fight.ref = { model = mR, root = rR, hum = hR, actId = 0, nextMove = 0, state = "idle" }
		end
		if spec.red.bot then
			P.ai = Bot.new(spec.red.bot, P, O, fight, Random.new((spec.seed or 1) * 17 + 3))
		else
			P.ai = FightAI.new(P, O, fight)
			seedAI(P.ai, (spec.seed or 1) * 13 + 11)
		end
		local dt = spec.dt or 0.05
		local t0 = clock
		local fightTime = 0
		for r = 1, fight.rounds do
			if fight.finished then
				break
			end
			if fight.StartRound then
				fight:StartRound(r)
			else
				-- (an older engine: the round's fresh start as its Run did it, and only the blue corner's AI thinks)
				fight.round = r
				for _, F in ipairs(fight.pair) do
					F.tally = { landed = 0, power = 0, body = 0, thrown = 0, kd = 0, clinches = 0 }
				end
				O.ai:UpdateMode()
			end
			fight.live, fight.paused, fight.kdHold, fight.menuHold = true, false, false, false
			fight.resumedAt = clock
			for _, F in ipairs(fight.pair) do
				F.root.CFrame = CF.lookAt(V3.new(F == P and -3 or 3, 3.2, 0), V3.new(F == P and 3 or -3, 3.2, 0))
				F.hum.target = nil
			end
			local remaining = fight.roundSeconds
			fight.roundEnd = clock + remaining
			while remaining > 0 and not fight.finished do
				advance(dt)
				if fight.paused then
					fight.roundEnd += dt
				else
					remaining -= dt
					fightTime += dt
				end
				fight:Update(dt)
				if not fight.StartRound and fight.live and not fight.paused then
					P.ai:Observe(dt)
					P.ai:Think(clock)
				end
				walk(fight, dt)
				if spec.onTick then
					spec.onTick(fight, clock)
				end
			end
			fight.live = false
			-- (a knockdown's count may still be running at the bell: let it finish)
			local guard = 0
			while (P.state == "down" or O.state == "down") and not fight.finished and guard < 400 do
				advance(dt)
				guard += 1
			end
			if fight.finished then
				break
			end
			fight:ScoreRound()
			fight:CloseChain(P)
			fight:CloseChain(O)
			if r < fight.rounds then
				fight:Rest()
				fight:DoctorCheck()
			end
		end
		local res = { fight = fight, P = P, O = O, seconds = fightTime, kd = { red = O.kdTotal, blue = P.kdTotal } }
		if fight.finished then
			res.winner = fight.winner == P and "red" or "blue"
			res.method = fight.method
			res.round = fight.endRound or fight.round
		else
			local d = Career.DecideCards(fight.cards)
			res.winner = d.outcome == "win" and "red" or (d.outcome == "loss" and "blue" or "draw")
			res.method = d.method
			res.round = fight.rounds
		end
		res.landed = { red = P.totals.landed, blue = O.totals.landed }
		res.thrown = { red = P.totals.thrown, blue = O.totals.thrown }
		res.traitMsgs = fight.msgs.trait
		return res
	end

	return S
end

return FightSim
