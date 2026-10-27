--!nocheck
-- tools/sim/test_entrance.luau: the pre-fight ring walk (src/shared/Entrance.lua, src/server/RingWalk.lua, the client's
-- BoxerClient.AnimEntrance / EntranceFX / EntrancePicker) under lune.
--   * the profile choice: Entrance.Sanitize on junk, unknown and wrong-slot ids, "none", carry, old saves (nil), the
--     belt count read defensively, Main's SetEntrance handler (text) and the summary view
--   * the carried-in rules (Entrance.ShouldCarry) and the post-win carry (CarryAfterWin): popularity, importance, title,
--     venue, spar / tutorial / AI, the player's own "no"; the belt lift without a belt; the AI's picks by personality
--   * the timeline: beats in order and contiguous, carry adds the set-down, robe only on the last walk, the AI's walk
--     shorter than the player's, every celebration inside its beat
--   * the server (RingWalk.Run on stub fighters, a fake clock): the fight starts exactly Entrance.Total after the
--     entrance began, the beats place him where the clients show him, a skip ends it at once (vs the AI) and in PvP
--     only once both asked; FightEngine's Fight:Entrance runs RingWalk and its Input takes "entranceSkip"
--   * the client (guisim): an entrance message starts the walk (the reveal, SKIP, AnimEntrance state, a camera shot on
--     every beat, the carriers on a carried walk), SKIP sends "entranceSkip" and cuts to the wide shot, entranceEnd
--     clears it all; AnimEntrance's gestures and states give finite poses
--   lune run tools/sim/test_entrance.luau
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

local H = Host.new({ server = true })
local Entrance = H.require("Entrance")
local Config = H.require("Config")

------------------------------------------------------------------------
-- the profile choice
------------------------------------------------------------------------
local D = Entrance.DEFAULT
local function same(a, b)
	return a.walk1 == b.walk1 and a.walk2 == b.walk2 and a.ring == b.ring and a.carry == b.carry
end
check("old save (nil) -> defaults", same(Entrance.Sanitize(nil), D))
check("junk types -> defaults", same(Entrance.Sanitize({ walk1 = 5, walk2 = {}, ring = true, carry = "no" }), D))
check("not a table -> defaults", same(Entrance.Sanitize("fistpump"), D))
check("unknown ids -> defaults", same(Entrance.Sanitize({ walk1 = "moonwalk", walk2 = "backflip", ring = "dab" }), D))
check("a long string is refused", Entrance.Sanitize({ walk1 = string.rep("a", 400) }).walk1 == D.walk1)
check("a ring-only celebration is no walk celebration", Entrance.Sanitize({ walk1 = "turnbuckle" }).walk1 == D.walk1)
check("the stare-walk is no ring celebration", Entrance.Sanitize({ ring = "stare" }).ring == D.ring)
do
	local c = Entrance.Sanitize({ walk1 = "chestbeat", walk2 = "none", ring = "victorylap", carry = false })
	check("a valid choice is kept", c.walk1 == "chestbeat" and c.walk2 == "none" and c.ring == "victorylap" and c.carry == false)
	local d = Entrance.Sanitize({ walk1 = "bow", walk2 = "bow" })
	check("the same celebration twice -> the aisle one is none", d.walk1 == "bow" and d.walk2 == "none")
	check("carry stays on unless explicitly false", Entrance.Sanitize({ carry = 0 }).carry == true and Entrance.Sanitize({ carry = false }).carry == false)
	local e = Entrance.Sanitize(Entrance.Sanitize({ walk1 = "shadowbox", ring = "beltlift" }))
	check("sanitize is idempotent", e.walk1 == "shadowbox" and e.ring == "beltlift")
	-- every id the picker lists sanitizes to itself in its slot
	local okAll = true
	for _, id in ipairs(Entrance.WALK) do
		okAll = okAll and Entrance.Sanitize({ walk1 = id }).walk1 == id
	end
	for _, id in ipairs(Entrance.RING) do
		okAll = okAll and Entrance.Sanitize({ ring = id }).ring == id
	end
	check("every listed celebration is valid in its slot", okAll)
	check("at least 12 celebrations", #Entrance.CELEBS >= 12, #Entrance.CELEBS)
end
check("belts: none", Entrance.BeltCount({ belts = { WBA = false, WBC = false } }) == 0)
check("belts: world + regional", Entrance.BeltCount({ belts = { WBA = true, WBC = false }, regional = { national = true } }) == 2)
check("belts: a tournament list", Entrance.BeltCount({ tournamentBelts = { "City Cup", "Golden Gloves" } }) == 2)
check("belts: tournaments.belts table entries", Entrance.BeltCount({ tournaments = { belts = { cup = { won = 3 } } } }) == 1)
check("belts: junk", Entrance.BeltCount({ belts = "WBA" }) == 0 and Entrance.BeltCount(nil) == 0)
do
	local v = Entrance.View({ popularity = 10 })
	check("summary view of an old save", same(v.choice, D) and v.belts == 0)
end
-- the server's handler sanitizes, saves and takes the walkout song / announcer as the creator does
do
	local src = fs.readFile(H.src .. "/server/Main.server.lua")
	check("Main: SetEntrance handler", src:find("function handlers.SetEntrance", 1, true) ~= nil)
	check("Main: SetEntrance sanitizes", src:find("profile.entrance = require(Shared.Entrance).Sanitize(data)", 1, true) ~= nil)
	check("Main: the summary carries the view", src:find("s.entrance = require(Shared.Entrance).View(profile)", 1, true) ~= nil)
end

------------------------------------------------------------------------
-- the carried-in rules
------------------------------------------------------------------------
local function carry(t)
	return Entrance.ShouldCarry(t)
end
check("fan favourite carried (club)", carry({ popularity = 80, venue = "ClubArena" }))
check("fan favourite carried (stadium)", carry({ popularity = 75, venue = "Stadium" }))
check("not at the community centre", not carry({ popularity = 95, venue = "CommunityCenter" }))
check("not in a gym spar", not carry({ popularity = 95, venue = "Gym", spar = true }))
check("not in the tutorial", not carry({ popularity = 95, venue = "Arena", tutorial = true }))
check("never the AI", not carry({ popularity = 95, venue = "Arena", ai = true }))
check("the player's no", not carry({ popularity = 95, venue = "Arena", pref = false }))
check("well known on a title night", carry({ popularity = 55, venue = "Stadium", title = true }))
check("well known on a big night", carry({ popularity = 50, venue = "Arena", importance = 0.85 }))
check("well known on a normal night: walks", not carry({ popularity = 60, venue = "Arena", importance = 0.5 }))
check("unknown on a title night: walks", not carry({ popularity = 30, venue = "Stadium", title = true }))
check("just under the favourite line: walks", not carry({ popularity = 74, venue = "Arena", importance = 0.2 }))
check("junk ctx: walks", not carry(nil) and not carry({ popularity = "lots" }))
-- after the bell
local function after(t)
	return Entrance.CarryAfterWin(t)
end
check("big KO win: carried round the ring", after({ won = true, method = "KO", popularity = 65, venue = "Arena" }))
check("TKO counts", after({ won = true, method = "TKO", popularity = 65, venue = "ClubArena" }))
check("a decision on a small night: no", not after({ won = true, method = "UD", popularity = 65, importance = 0.3, venue = "Arena" }))
check("a decision on a big night: yes", after({ won = true, method = "UD", popularity = 65, importance = 0.7, venue = "Arena" }))
check("a title win is the ceremony's", not after({ won = true, method = "KO", popularity = 90, title = true, venue = "Stadium" }))
check("a loss: no", not after({ won = false, method = "KO", popularity = 90, venue = "Arena" }))
check("not popular enough: no", not after({ won = true, method = "KO", popularity = 40, venue = "Arena" }))

------------------------------------------------------------------------
-- plans, the AI, the belt
------------------------------------------------------------------------
do
	local p = Entrance.Plan({ choice = { walk1 = "beltlift", ring = "beltlift" }, belts = 0, venue = "Arena" })
	check("belt lift without a belt -> fist pump", p.walk[1] == "fistpump" and p.ring == "fistpump" and not p.belt)
	local q = Entrance.Plan({ choice = { walk1 = "beltlift" }, belts = 1, venue = "Arena" })
	check("belt lift with a belt", q.walk[1] == "beltlift" and q.belt == true)
	for _, pers in ipairs(Config.Personalities) do
		local a = Entrance.Plan({ ai = true, personality = pers, venue = "Arena", popularity = 99, title = true })
		check("AI " .. pers .. ": valid picks", Entrance.Valid(a.walk[1], "walk") ~= nil and Entrance.Valid(a.ring, "ring") ~= nil, a.walk[1] .. "/" .. a.ring)
		check("AI " .. pers .. ": one walk celebration, never carried, short", #a.walk == 1 and a.carry == false and a.short == true)
	end
	local champ = Entrance.Plan({ ai = true, personality = "Showman", belts = 2, venue = "Stadium" })
	check("an AI champion lifts his belt", champ.walk[1] == "beltlift" and champ.belt)
	local hot = Entrance.AIPick("Hothead", 0, 0)
	local tech = Entrance.AIPick("Technician", 0, 0)
	check("personalities differ", hot.walk1 ~= tech.walk1 or hot.ring ~= tech.ring)
	check("unknown personality still picks", Entrance.Valid(Entrance.AIPick(nil, 0, 7).walk1, "walk") ~= nil)
	local fav = Entrance.Plan({ choice = {}, popularity = 90, venue = "Arena" })
	check("a favourite's plan is carried, at the carried pace", fav.carry and fav.speed == Entrance.SPEED.carried)
	check("a favourite is eligible for the post-win carry", fav.afterWin == true)
end

------------------------------------------------------------------------
-- the timeline
------------------------------------------------------------------------
local function ids(beats)
	local t = {}
	for _, b in ipairs(beats) do
		table.insert(t, b.id)
	end
	return table.concat(t, ",")
end
do
	local walk = Entrance.Plan({ choice = {}, popularity = 10, venue = "Arena" })
	local carried = Entrance.Plan({ choice = {}, popularity = 90, venue = "Arena", last = true })
	local ai = Entrance.Plan({ ai = true, personality = "Showman", venue = "Arena" })
	local b1, t1 = Entrance.Timeline(walk)
	local b2, t2 = Entrance.Timeline(carried)
	local b3, t3 = Entrance.Timeline(ai)
	check("walk beats", ids(b1) == "tunnel,aisle,crowd,steps,ropes,ring", ids(b1))
	check("carried beats (set-down at the steps, robe on the last walk)", ids(b2) == "tunnel,aisle,crowd,setdown,steps,ropes,ring,robe", ids(b2))
	check("AI beats (no crowd shot, no robe)", ids(b3) == "tunnel,aisle,steps,ropes,ring", ids(b3))
	check("the AI's walk is shorter", t3 < t1 and t3 < t2, string.format("%.2f vs %.2f", t3, t1))
	check("the AI's walk stays under 8 s", t3 <= 8, t3)
	check("a player's walk stays under 14 s", t1 <= 14 and t2 <= 14, string.format("%.2f %.2f", t1, t2))
	for _, set in ipairs({ { b1, t1 }, { b2, t2 }, { b3, t3 } }) do
		local ok, last = true, 0
		for _, b in ipairs(set[1]) do
			ok = ok and near(b.t0, last) and b.t1 > b.t0
			last = b.t1
		end
		check("beats contiguous " .. ids(set[1]), ok and near(last, set[2]))
	end
	for _, pl in ipairs({ walk, carried, ai }) do
		local beats = Entrance.Timeline(pl)
		local cs = Entrance.Celebrations(pl, beats)
		local ok = #cs >= 2
		for _, c in ipairs(cs) do
			ok = ok and c.t1 > c.t0
			local b = Entrance.BeatAt(beats, c.t0 + 1e-3)
			ok = ok and b ~= nil
		end
		check("celebrations inside the walk (" .. pl.walk[1] .. ")", ok)
	end
	check("Total = lead + both walks", near(Entrance.Total(ai, carried), Entrance.LEAD + t3 + t2))
	check("BeatAt past the end", Entrance.BeatAt(b1, t1 + 0.01) == nil)
	local tb = Entrance.Plan({ choice = { ring = "turnbuckle" }, venue = "Arena" })
	local cs = Entrance.Celebrations(tb, (Entrance.Timeline(tb)))
	check("the turnbuckle salute is the ring beat's celebration", cs[#cs].id == "turnbuckle" and cs[#cs].beat == "ring")
end

------------------------------------------------------------------------
-- the server: RingWalk.Run on stub fighters with a fake clock
------------------------------------------------------------------------
local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
for _, f in ipairs(fs.readDir(H.src .. "/server")) do
	local base = f:match("^(.-)%.lua$")
	if base and not f:find("%.server%.") then
		local n = Host.NewNode(base, "ModuleScript", folder)
		rawset(n, "_file", H.src .. "/server/" .. f)
	end
end
local RingWalk = H.requireNode(folder._kids.RingWalk)
local FightEngine = H.requireNode(folder._kids.FightEngine)
local Fight = FightEngine._Fight

local clock = 0
local function fakeClock()
	return clock
end
local onWait
local function fakeWait(dt)
	clock += dt or 0.03
	if onWait then
		onWait(clock)
	end
	return dt
end

local function stubModel(name)
	local m = { Name = name, _attrs = {}, cf = CFrame.new() }
	local root = { Size = Vector3.new(2, 2, 1), AssemblyLinearVelocity = Vector3.zero }
	root.Position = Vector3.zero
	root.CFrame = CFrame.new()
	m.root = root
	function m:PivotTo(cf)
		self.cf = cf
		root.CFrame = cf
		root.Position = cf.Position
	end
	function m:SetAttribute(k, v)
		self._attrs[k] = v
	end
	function m:GetAttribute(k)
		return self._attrs[k]
	end
	function m:FindFirstChild()
		return nil
	end
	return m
end
local function stubFighter(name, isPlayer, opts)
	local m = stubModel(name)
	local hum = { HipHeight = 2, WalkSpeed = 0, moves = {} }
	function hum:MoveTo(p)
		table.insert(self.moves, p)
	end
	local plr = { Name = name, Parent = true, UserId = 1 }
	return {
		model = m, root = m.root, hum = hum, isPlayer = isPlayer, player = (isPlayer or (opts and opts.pvp)) and plr or nil,
		data = { name = name, nick = "", app = {}, lookOpts = { robe = (opts and opts.robe) or "Classic" }, mental = { Confidence = 50 }, personality = "Showman", record = { w = 1, l = 0, d = 0, ko = 1 } },
	}
end
local function anchor(x, y, z)
	return { Position = Vector3.new(x, y, z) }
end
local function stubFight(opts)
	opts = opts or {}
	local half = 12
	local self = setmetatable({}, Fight)
	self.P = stubFighter("Red", true)
	self.O = stubFighter("Blue", opts.pvp == true, { pvp = opts.pvp })
	if opts.pvp then
		self.O.isPlayer = true
	end
	self.pvp = opts.pvp == true
	self.venue = opts.venue or "Arena"
	self.ringHalf = half
	self.sent = {}
	self.places = {}
	self.remote = { FireClient = function(_, plr, msg)
		table.insert(self.sent, { to = plr.Name, msg = msg })
	end }
	self.arena = { GetAttribute = function(_, k)
		if k == "Importance" then
			return opts.importance or 0.3
		elseif k == "Stakes" then
			return opts.stakes or ""
		end
		return nil
	end }
	local c = half - 2.5
	self.anchors = {
		RingCenter = anchor(0, 4, 0), RedCorner = anchor(-c, 4, -c), BlueCorner = anchor(c, 4, c),
		RedEntrance = anchor(0, 0, -102), BlueEntrance = anchor(0, 0, 102), RedSteps = anchor(0, 0, -(half + 9)), BlueSteps = anchor(0, 0, half + 9),
	}
	local place = Fight.Place
	self.Place = function(fself, F, pos, lookAt)
		table.insert(fself.places, { who = F == fself.P and "P" or "O", pos = pos, t = clock })
		return place(fself, F, pos, lookAt)
	end
	self.UpdateGuard = function() end
	self.SyncAttrs = function() end
	self.Now = function()
		return clock
	end
	return self
end
local function msgs(f, t)
	local out = {}
	for _, s in ipairs(f.sent) do
		if s.msg.t == t then
			table.insert(out, s)
		end
	end
	return out
end
local ENV = { clock = fakeClock, wait = fakeWait, noEntourage = true }

do
	clock = 0
	local f = stubFight()
	local st = RingWalk.Run(f, ENV)
	local planO, planP = st.walks[1].plan, st.walks[2].plan
	local total = Entrance.Total(planO, planP)
	check("the fight starts Entrance.Total after the entrance began", near(st.elapsed, total, 0.25), string.format("%.2f vs %.2f", st.elapsed, total))
	check("the opponent (AI) walks first, short", planO.short and planO.ai and not planP.short)
	check("only the last walk takes the robes off", not planO.last and planP.last)
	local ent = msgs(f, "entrance")
	-- one viewer (the player) gets both: his own as "you", the AI's as "opp"
	check("two entrance messages (opp, you)", #ent == 2 and ent[1].msg.phase == "opp" and ent[2].msg.phase == "you", #ent)
	local plan = ent[2] and ent[2].msg.plan
	check("the plan carries the points, the model and the name", plan and plan.pts and plan.pts.apron and plan.model == f.P.model and plan.name == "Red")
	check("no MoveTo target in the message (the client walks on the aisle beat)", ent[2] and ent[2].msg.target == nil)
	check("the entrance ends with entranceEnd (not skipped)", #msgs(f, "entranceEnd") == 1 and msgs(f, "entranceEnd")[1].msg.skipped == false)
	-- the player's beats place him where the clients draw him: the apron, inside the ropes, the corner
	local pts = RingWalk.Points(f, "Red")
	local seq = {}
	for _, p in ipairs(f.places) do
		if p.who == "P" then
			table.insert(seq, p.pos)
		end
	end
	local function has(pos)
		for _, q in ipairs(seq) do
			if (q - pos).Magnitude < 1e-3 then
				return true
			end
		end
		return false
	end
	check("placed on the apron (steps beat)", has(pts.apron))
	check("placed inside the ropes (ropes beat)", has(pts.inside))
	check("ends in his corner", (seq[#seq] - f.anchors.RedCorner.Position).Magnitude < 1e-3)
	check("apron outside the ropes, inside point inside", (pts.apron - pts.centre).Magnitude > pts.half and (pts.inside - pts.centre).Magnitude < pts.half)
	-- the AI walks the aisle by the server's MoveTo to the steps, then to his corner
	local mv = f.O.hum.moves
	local bluePts = RingWalk.Points(f, "Blue")
	check("the AI is walked to the steps and his corner", #mv >= 2 and (mv[1] - bluePts.steps).Magnitude < 1e-3 and (mv[#mv] - bluePts.corner).Magnitude < 1e-3)
	-- the log's beat times match the timeline
	local okLog = true
	local w0
	for _, e in ipairs(st.log) do
		if e.what == "walk" and e.who == "P" then
			w0 = e.t
		elseif w0 and e.who == "P" and e.what ~= "done" then
			for _, b in ipairs(st.walks[2].beats) do
				if b.id == e.what then
					okLog = okLog and near(e.t - w0, b.t0, 0.25)
				end
			end
		end
	end
	check("server beats on the timeline (within a tick)", okLog and w0 ~= nil)
end
-- a carried walk: the set-down beat places him at the steps
do
	clock = 0
	local f = stubFight({ venue = "Stadium", stakes = "WBC" })
	local orig = RingWalk.Context
	RingWalk.Context = function(fight, F, corner, last)
		local ctx = orig(fight, F, corner, last)
		if F == fight.P then
			ctx.popularity = 90
		end
		return ctx
	end
	local st = RingWalk.Run(f, ENV)
	RingWalk.Context = orig
	check("a popular boxer at the stadium is carried", st.walks[2].plan.carry == true)
	local sawSteps = false
	for _, p in ipairs(f.places) do
		if p.who == "P" and (p.pos - f.anchors.RedSteps.Position).Magnitude < 1e-3 then
			sawSteps = true
		end
	end
	check("set down at the foot of the steps", sawSteps)
	check("carried walk: total still the timeline's", near(st.elapsed, Entrance.Total(st.walks[1].plan, st.walks[2].plan), 0.25))
end
-- skip vs the AI: at once
do
	clock = 0
	local f = stubFight()
	onWait = function(t)
		if t > 3 and not f.ringWalk.skipped then
			RingWalk.Skip(f, f.P)
		end
	end
	local st = RingWalk.Run(f, ENV)
	onWait = nil
	check("a skip ends the entrance at once", st.elapsed < 3.5, st.elapsed)
	local endMsg = msgs(f, "entranceEnd")[1]
	check("entranceEnd says skipped", endMsg and endMsg.msg.skipped == true)
	local lastP, lastO
	for _, p in ipairs(f.places) do
		if p.who == "P" then
			lastP = p.pos
		else
			lastO = p.pos
		end
	end
	check("after a skip both are in their corners", (lastP - f.anchors.RedCorner.Position).Magnitude < 1e-3 and (lastO - f.anchors.BlueCorner.Position).Magnitude < 1e-3)
	check("a skip after the end changes nothing", RingWalk.Skip(f, f.P) == false)
end
-- PvP: both clients see both walks
do
	clock = 0
	local f = stubFight({ pvp = true })
	local st = RingWalk.Run(f, ENV)
	local you, opp = 0, 0
	for _, s in ipairs(msgs(f, "entrance")) do
		if s.msg.phase == "you" then
			you += 1
		else
			opp += 1
		end
	end
	check("PvP: both clients see both walks (one 'you' and one 'opp' each)", you == 2 and opp == 2, you .. "/" .. opp)
	check("PvP: the total is two player walks", near(st.elapsed, Entrance.Total(st.walks[1].plan, st.walks[2].plan), 0.25))
end
-- PvP: one skip is not enough, both are
do
	clock = 0
	local f = stubFight({ pvp = true })
	local skippedAt
	onWait = function(t)
		if t > 2 and not f.ringWalk.skips[f.P] then
			RingWalk.Skip(f, f.P)
		end
		if t > 6 and not f.ringWalk.skips[f.O] then
			RingWalk.Skip(f, f.O)
			skippedAt = t
		end
	end
	local st = RingWalk.Run(f, ENV)
	onWait = nil
	check("PvP: both walks are full player walks", not st.walks[1].plan.short and not st.walks[2].plan.short)
	check("PvP: one player's skip does not end it", skippedAt ~= nil and skippedAt > 5.9)
	check("PvP: both skips end it", st.elapsed < 6.5, st.elapsed)
end
-- FightEngine runs it: Fight:Entrance hands over to RingWalk; Input routes "entranceSkip"
do
	clock = 0
	RingWalk.Env = ENV
	local f = stubFight()
	local okE, errE = pcall(Fight.Entrance, f)
	check("Fight:Entrance runs RingWalk", okE and f.ringWalk ~= nil and f.ringWalk.done, errE)
	check("Fight:Entrance takes the timeline's time", f.ringWalk and near(f.ringWalk.elapsed, Entrance.Total(f.ringWalk.walks[1].plan, f.ringWalk.walks[2].plan), 0.25))
	clock = 0
	local g = stubFight()
	g.FighterOf = function(fself, plr)
		return plr == fself.P.player and fself.P or nil
	end
	FightEngine.Active[g.P.player] = g
	onWait = function(t)
		if t > 1.5 and not g.ringWalk.skipped then
			FightEngine.Input(g.P.player, { t = "entranceSkip" })
		end
	end
	pcall(Fight.Entrance, g)
	onWait = nil
	FightEngine.Active[g.P.player] = nil
	RingWalk.Env = nil
	check("FightEngine.Input 'entranceSkip' skips", g.ringWalk and g.ringWalk.skipped and g.ringWalk.elapsed < 2.2, g.ringWalk and g.ringWalk.elapsed)
end

------------------------------------------------------------------------
-- the client: AnimEntrance (pure) and EntranceFX in guisim
------------------------------------------------------------------------
local S = GS.new("phone")
local E = S.host
local AE = S.require("AnimEntrance")
-- (guisim's workspace is a plain host node: give it and its ancestors the signals parenting fires)
do
	local FE = require("./fakeengine")
	local n = E.globals.workspace
	while n do
		local props = rawget(n, "_props")
		for _, k in ipairs({ "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged" }) do
			if props and props[k] == nil then
				props[k] = FE.Signal()
			end
		end
		n = rawget(n, "_parent")
	end
end
do
	local ok = true
	for _, c in ipairs(Entrance.CELEBS) do
		for _, u in ipairs({ 0, 0.4, 0.9, 1.5 }) do
			local q, own, w = AE.Gesture(c.id, u, c.dur, {})
			ok = ok and w >= 0 and w <= 1 and next(own) ~= nil
			for k in pairs(own) do
				ok = ok and typeof(q[k]) == "CFrame"
			end
		end
	end
	check("every gesture gives finite owned joints and a 0..1 envelope", ok)
	local _, _, w0 = AE.Gesture("fistpump", 0, 1.6, {})
	local _, _, wm = AE.Gesture("fistpump", 0.8, 1.6, {})
	check("a gesture eases in", w0 < 0.05 and wm > 0.95)
end

local Inst = E.globals.Instance
local function rig(name, pos)
	local m = Inst.new("Model")
	m.Name = name
	local hrp = Inst.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)
	hrp.Parent = m
	local hum = Inst.new("Humanoid")
	hum.HipHeight = 2
	hum.Parent = m
	m.Parent = E.globals.workspace
	return m, hrp
end
local function planFor(model, carry)
	local half = 12
	local pts = {
		centre = Vector3.new(0, 4, 0), entrance = Vector3.new(0, 0, -102), steps = Vector3.new(0, 0, -21), corner = Vector3.new(-9.5, 4, -9.5),
		apron = Vector3.new(0, 4, -(half + 1.7)), inside = Vector3.new(0, 4, -(half - 1.6)), post = Vector3.new(-12, 4, -12), half = half,
	}
	local p = Entrance.Plan({ corner = "Red", choice = { walk1 = "beltlift", walk2 = "point", ring = "turnbuckle" }, belts = 1, popularity = carry and 90 or 10, venue = "Arena", last = true })
	p.pts, p.model, p.name, p.nick, p.record = pts, model, "Marcus Reed", "The Hammer", { w = 18, l = 2, d = 1, ko = 12 }
	return p
end
local FX = S.require("EntranceFX")
local fired = {}
S.onFireServer = function(remote, msg)
	table.insert(fired, msg)
end
FX.Start()
S.settle(0.1)
local me = rig("Me", Vector3.new(0, 3.05, -102))
S.remotes.FightEvent:Fire({ t = "entrance", phase = "you", plan = planFor(me, true) })
S.settle(0.15)
local function find(path)
	local n = S.playerGui
	for part in path:gmatch("[^%.]+") do
		n = n and n:FindFirstChild(part)
	end
	return n
end
check("client: the walk starts (AnimEntrance state)", AE.active[me] ~= nil)
check("client: the reveal is up", find("EntranceUI.Root.Reveal") ~= nil and find("EntranceUI.Root.Reveal").Visible == true)
check("client: the reveal names him", find("EntranceUI.Root.Reveal.Name") and find("EntranceUI.Root.Reveal.Name").Text == "MARCUS REED")
check("client: SKIP is up", find("EntranceUI.Root.Skip") ~= nil and find("EntranceUI.Root.Skip").Visible == true)
do
	-- a shot on every beat, and a hard cut (a new key) between them
	local w = FX.S.walk
	local keys, okShots = {}, true
	for _, b in ipairs(w.beats) do
		local cf, key = FX.Shot(w, w.t0 + (b.t0 + b.t1) / 2)
		okShots = okShots and typeof(cf) == "CFrame" and key ~= nil
		if key and keys[#keys] ~= key then
			table.insert(keys, key)
		end
	end
	check("client: a camera shot on every beat", okShots)
	check("client: the camera cuts between at least 6 shots", #keys >= 6, table.concat(keys, ","))
	check("client: Camera() gives the on-air shot", typeof(FX.Camera(os.clock())) == "CFrame")
	-- the carried frame: AnimEntrance says carried in the aisle and the carriers are built
	local st = AE.active[me]
	local fr = AE.Frame(st, st.t0 + w.beats[2].t0 + 0.5)
	check("client: carried down the aisle", fr.mode == "carried" and fr.lift == 1)
	S.settle(0.1)
	local folderC = E.globals.workspace:FindFirstChild("EntranceCarriers")
	check("client: the carriers are built for a carried walk", folderC ~= nil and #folderC:GetChildren() >= 2, folderC and #folderC:GetChildren())
	local frs = AE.Frame(st, st.t0 + w.beats[5].t0 + 0.3)
	check("client: climbing at the steps beat", frs.mode == "climb")
	local frr = AE.Frame(st, st.t0 + w.beats[6].t0 + 0.3)
	check("client: through the ropes", frr.mode == "duck")
	local frt = AE.Frame(st, st.t0 + w.beats[7].t0 + Entrance.RING_WALK + 0.5)
	check("client: the turnbuckle salute", frt.mode == "turnbuckle")
	local geo = AE.Geom(me)
	check("client: the seat lift is positive (on the shoulders)", geo.lift > 1.5 and geo.lift < 4.5, geo.lift)
end
-- SKIP: the server is asked, the camera goes wide, the walk stops
FX.Skip()
S.settle(0.1)
local asked = false
for _, m in ipairs(fired) do
	if type(m) == "table" and m.t == "entranceSkip" then
		asked = true
	end
end
check("client: SKIP asks the server", asked)
check("client: after SKIP the camera is the wide shot", typeof(FX.Camera(os.clock())) == "CFrame" and FX.S.skipped == true)
check("client: after SKIP no carriers", E.globals.workspace:FindFirstChild("EntranceCarriers") == nil)
S.remotes.FightEvent:Fire({ t = "entranceEnd", skipped = true })
S.settle(0.5)
check("client: entranceEnd clears the walk", FX.S.walk == nil and FX.S.skipped == false)
check("client: entranceEnd hides the overlay", find("EntranceUI") == nil or find("EntranceUI").Enabled == false)
-- an older server (no plan): nothing starts
S.remotes.FightEvent:Fire({ t = "entrance", phase = "opp", pyro = false })
S.settle(0.05)
check("client: an entrance without a plan is FightClient's alone", FX.S.walk == nil)
-- the post-win parade after a big KO (and never after a title win)
do
	local p = planFor(me, true)
	S.remotes.FightEvent:Fire({ t = "entrance", phase = "you", plan = p })
	S.settle(0.05)
	S.remotes.FightEvent:Fire({ t = "final", result = { outcome = "win", method = "KO" } })
	S.settle(0.1)
	check("client: a big KO win -> the parade", FX.S.parade ~= nil and AE.active[me] ~= nil and AE.active[me].parade == true)
	S.settle(0.1)
	local t = planFor(me, true)
	t.title = true
	FX.S.parade = nil
	AE.active[me] = nil
	S.remotes.FightEvent:Fire({ t = "entrance", phase = "you", plan = t })
	S.settle(0.05)
	S.remotes.FightEvent:Fire({ t = "final", result = { outcome = "win", method = "KO" } })
	S.settle(0.1)
	check("client: a title win -> no parade (the ceremony's)", FX.S.parade == nil)
end

-- the hooks in the shared files are in place
do
	local a = fs.readFile(H.src .. "/client/Animator.client.lua")
	check("Animator: the output hook", a:find("Entrance.output(rig, model, out, t, dt)", 1, true) ~= nil)
	local fc = fs.readFile(H.src .. "/client/FightClient.client.lua")
	check("FightClient: the camera hook", fc:find('KM.module("EntranceFX")', 1, true) ~= nil)
	local fe = fs.readFile(H.src .. "/server/FightEngine.lua")
	check("FightEngine: Input entranceSkip", fe:find('t == "entranceSkip"', 1, true) ~= nil)
end

print(string.format("test_entrance: %d passed, %d failed", pass, fail))
process.exit(fail > 0 and 1 or 0)
