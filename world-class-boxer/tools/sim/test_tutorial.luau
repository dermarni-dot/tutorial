--!nocheck
-- tools/sim/test_tutorial.luau: the first-time tutorial fight (src/shared/Tutorial.lua, src/server/TutorialFight.lua,
-- src/client/modules/Tutorial.lua) under lune.
--   * trigger: Tutorial.ShouldOffer (a new player only: no career, no past careers, no flag), Tutorial.Backfill
--     (DataManager's load: an existing career or an older save counts as done; a first join does not)
--   * the career untouched: TutorialFight.Build on a real career (Career.CreateProfile) leaves the profile, its
--     record, money, rankings, injuries, the move unlocks (Moves.Info / Moves.Unlocked) and the saved look as they
--     were; the fighters are random boxers (World.RandomBoxer + Looks.Random through Career.FighterFromBoxer), the
--     opponent weaker, the venue a fight venue with a modest crowd; MarkDone writes only tutorialDone
--   * the steps: every step in order, each advancing only on its own input, the round clock (hold / break / run),
--     knockdowns only at the last step, the stamina step's drain / refill and timeout, the idle safety
--   * the prompts' keys: the control map's keyboard / gamepad bindings (a remapped key follows), the touch pads
--   * skip: the offer's SKIP TUTORIAL (SkipTutorial, then the title screen) and the step card's (the Fight remote's
--     tutorialSkip), driven through the real client module on guisim; the wrap-up's way on (creator / menu)
--   lune run tools/sim/test_tutorial.luau
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local H = Host.new()
local Tutorial = H.require("Tutorial")
local Config = H.require("Config")
local Keymap = H.require("Keymap")
local Moves = H.require("Moves")
local Looks = H.require("Looks")
local Random = H.globals.Random

local function serverModule(name)
	local folder = rawget(H, "_serverFolder")
	if not folder then
		folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
		for _, f in ipairs(fs.readDir(H.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", H.src .. "/server/" .. f)
			end
		end
		rawset(H, "_serverFolder", folder)
	end
	return H.requireNode(folder._kids[name])
end

local function deepEq(a, b, path, seen)
	path = path or "profile"
	if type(a) ~= type(b) then
		return false, path .. " type " .. type(a) .. " vs " .. type(b)
	end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then
			return false, path .. " " .. tostring(a) .. " vs " .. tostring(b)
		end
		return true
	end
	seen = seen or {}
	if seen[a] then
		return true
	end
	seen[a] = true
	for k, v in pairs(a) do
		local ok, why = deepEq(v, b[k], path .. "." .. tostring(k), seen)
		if not ok then
			return false, why
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false, path .. "." .. tostring(k) .. " appeared"
		end
	end
	return true
end
local function deepCopy(t, seen)
	if type(t) ~= "table" then
		return t
	end
	seen = seen or {}
	if seen[t] then
		return seen[t]
	end
	local c = {}
	seen[t] = c
	for k, v in pairs(t) do
		c[deepCopy(k, seen)] = deepCopy(v, seen)
	end
	return c
end

------------------------------------------------------------------------
-- trigger
------------------------------------------------------------------------
check("offer: no profile", Tutorial.ShouldOffer(nil) == false)
check("offer: a first join's blank profile", Tutorial.ShouldOffer({ v = Config.DataVersion, created = false, pastCareers = {} }) == true)
check("offer: not with the flag", Tutorial.ShouldOffer({ created = false, pastCareers = {}, tutorialDone = true }) == false)
check("offer: not with a boxer", Tutorial.ShouldOffer({ created = true, pastCareers = {} }) == false)
check("offer: not after a career (past careers)", Tutorial.ShouldOffer({ created = false, pastCareers = { { name = "Old" } } }) == false)
check("offer: not while retired", Tutorial.ShouldOffer({ created = true, retired = true, pastCareers = {} }) == false)
check("offer: not on the retired screen (final)", Tutorial.ShouldOffer({ created = false, final = {}, pastCareers = {} }) == false)
-- Backfill: what DataManager's prepare() does with the stored value
local V = Config.DataVersion
local function loaded(stored)
	-- DataManager.prepare: a blank for nothing / an older version, the stored career itself otherwise
	local data
	if type(stored) ~= "table" then
		data = { v = V, created = false, pastCareers = {} }
	elseif stored.v ~= V then
		data = { v = V, created = false, pastCareers = stored.pastCareers or {} }
	else
		data = stored
	end
	return Tutorial.Backfill(stored, data, V)
end
check("first join: offered", Tutorial.ShouldOffer(loaded(nil)) == true and loaded(nil).tutorialDone == nil)
check("blank current save: offered", Tutorial.ShouldOffer(loaded({ v = V, created = false, pastCareers = {} })) == true)
local old = loaded({ v = V - 1, created = true, pastCareers = {} })
check("an older version's save: done (an existing player)", old.tutorialDone == true and Tutorial.ShouldOffer(old) == false)
local career = loaded({ v = V, created = true, pastCareers = {} })
check("a saved career: done", career.tutorialDone == true and Tutorial.ShouldOffer(career) == false)
check("a retired player's blank (NewCareer): not offered", Tutorial.ShouldOffer(loaded({ v = V, created = false, pastCareers = { {} } })) == false)
check("the flag survives a load", loaded({ v = V, created = false, pastCareers = {}, tutorialDone = true }).tutorialDone == true)
-- the real DataManager and Main call these
local dmSrc = fs.readFile(H.src .. "/server/DataManager.lua")
check("DataManager's load backfills", dmSrc:find("Tutorial.Backfill, stored, data, Config.DataVersion", 1, true) ~= nil)
local mainSrc = fs.readFile(H.src .. "/server/Main.server.lua")
check("Main's summary carries the offer", mainSrc:find("s.tutorial = { offer = Tutorial.ShouldOffer(profile)", 1, true) ~= nil)
check("CreateBoxer / NewCareer keep the flag", select(2, mainSrc:gsub("tutorialDone = true", "")) >= 2)
check("StartTutorial / SkipTutorial before a boxer exists", mainSrc:find("StartTutorial = true, SkipTutorial = true", 1, true) ~= nil)

------------------------------------------------------------------------
-- the career untouched, the random fighters
------------------------------------------------------------------------
local Career = serverModule("Career")
local World = serverModule("World")
local TF = serverModule("TutorialFight")
local prof = Career.CreateProfile(nil, {
	first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24, nationality = "USA",
	weightClass = 5, style = "boxer", look = Looks.Defaults(1),
}, 1)
prof.record = { w = 7, l = 1, d = 0, ko = 4 }
prof.amateurRecord = prof.amateurRecord or { w = 3, l = 0, d = 0, ko = 1 }
prof.money = 4321
prof.condition.injuries = { { id = "cut", days = 3 } }
prof.settings = { ui = { aimAssist = "High" } }
local before = deepCopy(prof)
local movesBefore = Moves.Unlocked(Moves.Info(prof))
local names, venues, genders = {}, {}, {}
for seed = 1, 40 do
	local b = TF.Build(Random.new(seed), { assist = 2 })
	local p, o = b.pData, b.oData
	names[p.name] = true
	venues[b.venue] = true
	check("seed " .. seed .. " player is not the career's boxer", p.name ~= prof.identity.name and p.app ~= prof.appearance and p.build ~= prof.body)
	check("seed " .. seed .. " a player fighter", p.isPlayer == true and type(p.app) == "table" and type(p.build) == "table" and type(p.gear) == "table")
	check("seed " .. seed .. " one special move", p.moves[Tutorial.SPECIAL] == true and next(p.moves, Tutorial.SPECIAL) == nil and next(o.moves) == nil)
	check("seed " .. seed .. " opponent weaker", Config.Overall(o.stats) < Config.Overall(p.stats), Config.Overall(o.stats) .. " vs " .. Config.Overall(p.stats))
	check("seed " .. seed .. " same gender, other name", (p.app.gender or 1) == (o.app.gender or 1) and p.name ~= o.name)
	check("seed " .. seed .. " not a defensive / counter opponent", o.archetype ~= "Defensive" and o.archetype ~= "Counter", o.archetype)
	check("seed " .. seed .. " a fight venue", table.find(TF.Venues, b.venue) ~= nil and b.venue ~= "Stadium" and b.venue ~= "Gym")
	local imp, pop = b.venueOpts.importance, b.venueOpts.popularity
	-- (Venues.CrowdFill's formula: the house this night fills)
	local fill = math.clamp(0.16 + 0.84 * imp + 0.2 * pop / 100, 0.15, 1)
	check("seed " .. seed .. " a modest crowd", fill >= 0.25 and fill <= 0.55, fill)
	check("seed " .. seed .. " the tutorial's offer", b.offer.tutorial == true and b.offer.rounds == Tutorial.ROUNDS and #b.offer.stakes == 0)
	check("seed " .. seed .. " assist from the settings", p.assist == 2)
	if seed % 2 == 0 then
		genders[p.app.gender or 1] = true
	end
end
local nNames, nVenues = 0, 0
for _ in pairs(names) do
	nNames += 1
end
for _ in pairs(venues) do
	nVenues += 1
end
check("random boxers (names vary)", nNames >= 30, nNames)
check("random venues", nVenues >= 2, nVenues)
local same, why = deepEq(before, prof)
check("Build leaves the career exactly as it was", same, why)
local movesAfter = Moves.Unlocked(Moves.Info(prof))
check("the move unlocks unchanged", deepEq(movesBefore, movesAfter))
check("TutorialFight never reads the career", fs.readFile(H.src .. "/server/TutorialFight.lua"):find("FighterFromProfile", 1, true) == nil)
-- World.RandomBoxer stores nothing
local w0 = deepCopy(prof.world)
World.RandomBoxer(Random.new(5), 4, 50)
check("RandomBoxer leaves the world alone", deepEq(w0, prof.world))
-- the end: only the flag
for _, how in ipairs({ "completed", "skipped", "crashed" }) do
	local p2 = deepCopy(before)
	check("Finish(" .. how .. ") sets the flag", TF.Finish(p2, how) == true and p2.tutorialDone == true)
	p2.tutorialDone = nil
	local s2, w2 = deepEq(before, p2)
	check("Finish(" .. how .. ") writes nothing else", s2, w2)
end
for _, how in ipairs({ "left", "aborted" }) do
	local p3 = deepCopy(before)
	check("Finish(" .. how .. ") writes nothing", TF.Finish(p3, how) == false and deepEq(before, p3))
end
local blank = { v = V, created = false, pastCareers = {} }
TF.Finish(blank, "skipped")
check("skipped: not offered again", Tutorial.ShouldOffer(blank) == false)
-- Main's tutorial path never reaches the career's result / training / face code
local runTut = mainSrc:match("local function runTutorial%(.-\nend\n")
check("runTutorial found", runTut ~= nil)
if runTut then
	for _, bad in ipairs({ "Career.ApplyResult", "settleFight", "fightWatch", "Training.", "AddFaceDamage", "fightExtras", "FighterFromProfile", "PvP.Apply" }) do
		check("runTutorial does not call " .. bad, runTut:find(bad, 1, true) == nil)
	end
	check("runTutorial writes the flag only through Finish", runTut:find("TutorialFight.Finish(profile, how)", 1, true) ~= nil and runTut:find("profile%.[%w_]+%s*=[^=]") == nil)
end
check("leaving mid-tutorial aborts the bout", mainSrc:find("tw.left = true", 1, true) ~= nil)

------------------------------------------------------------------------
-- the steps
------------------------------------------------------------------------
check("ten steps", #Tutorial.STEPS == 10)
local ids = {}
for i, s in ipairs(Tutorial.STEPS) do
	ids[i] = s.id
	for _, a in ipairs(s.actions) do
		check("step " .. s.id .. " action " .. a .. " is a control", Keymap.ById[a] ~= nil)
	end
	check("step " .. s.id .. " has goals", #s.goals > 0)
end
check("the order", table.concat(ids, ",") == "move,jab,cross,power,body,block,slip,stamina,special,finish", table.concat(ids, ","))
check("the special exists", Moves.Data[Tutorial.SPECIAL] ~= nil and Keymap.ById["special_" .. Tutorial.SPECIAL] ~= nil)
check("only the last step is final", Tutorial.STEPS[#Tutorial.STEPS].final == true)

local tr = Tutorial.NewTracker()
local now = 0
local function feed(ev)
	now += 0.1
	ev.now = now
	return Tutorial.Feed(tr, ev)
end
local function at(id)
	return Tutorial.Current(tr).id == id
end
check("starts at move, clock held", at("move") and Tutorial.Phase(tr, 1, now) == "hold")
check("no knockdown before the end", Tutorial.CanDrop(tr) == false)
feed({ k = "punch", p = "jab" })
check("a jab does not skip move", at("move"))
feed({ k = "move", dist = 1.5 })
feed({ k = "move", dist = 1.5 })
check("not yet (3 studs)", at("move"))
feed({ k = "move", dist = 1.5 })
check("move -> jab", at("jab"))
feed({ k = "punch", p = "cross" })
check("a cross does not count for the jab", at("jab"))
feed({ k = "punch", p = "jab" })
check("jab -> cross", at("cross"))
feed({ k = "punch", p = "cross" })
check("cross -> power", at("power"))
feed({ k = "punch", p = "leadhook" })
check("a hook alone is not enough", at("power") and tr.goals.hook == true)
local v = Tutorial.View(tr)
check("the view shows the hook done", v.t == "tutorial" and v.goals.hook == true and v.id == "power" and v.total == 10)
feed({ k = "punch", p = "uppercut" })
check("power -> body", at("body"))
check("round 1 still held", Tutorial.Phase(tr, 1, now) == "hold")
feed({ k = "punch", p = "jab", body = false })
check("a head jab is no body shot", at("body"))
feed({ k = "punch", p = "jab", body = true })
check("body -> block", at("block"))
check("round 1 breaks after the body shots", Tutorial.Phase(tr, 1, now) == "break")
check("round 2 holds at block", Tutorial.Phase(tr, 2, now) == "hold")
check("the opponent works harder for the block", Tutorial.AiWork(tr) > 1)
feed({ k = "block", dt = 0.5 })
check("half a second of guard: not yet", at("block"))
feed({ k = "block", dt = 0.6 })
check("block -> slip", at("slip"))
feed({ k = "roll" })
check("slip / dodge -> stamina", at("stamina"))
feed({ k = "stamina", pct = 0.9 })
check("full tank: nothing", at("stamina") and not tr.goals.drain)
feed({ k = "stamina", pct = 0.7 })
check("drained", tr.goals.drain == true and at("stamina"))
feed({ k = "stamina", pct = 0.6 })
feed({ k = "stamina", pct = 0.68 })
check("not refilled yet (from the low)", at("stamina"))
feed({ k = "stamina", pct = 0.73 })
check("stamina -> special", at("special"))
feed({ k = "punch", p = "jab" })
check("a jab is not the special", at("special"))
feed({ k = "special", id = Tutorial.SPECIAL })
check("special -> finish", at("finish"))
check("the finish runs the clock", Tutorial.Phase(tr, 2, now) == "run")
check("knockdowns allowed at the end", Tutorial.CanDrop(tr) == true)
feed({ k = "kd" })
check("a knockdown finishes it", tr.done == true and Tutorial.View(tr).done == true)
check("nothing after done", Tutorial.Feed(tr, { k = "punch", p = "jab", now = now }) == false)
-- the bell also finishes the last step; the stamina step times out
local tr2 = Tutorial.NewTracker()
tr2.step = Tutorial.ById.finish.index
check("the bell finishes the last step", Tutorial.Feed(tr2, { k = "bell", now = 1 }) and tr2.done)
local tr3 = Tutorial.NewTracker()
tr3.step = Tutorial.ById.stamina.index
Tutorial.Feed(tr3, { k = "tick", now = 10 })
Tutorial.Feed(tr3, { k = "tick", now = 10 + Tutorial.STAM_TIMEOUT - 1 })
check("stamina: not timed out early", Tutorial.Current(tr3).id == "stamina")
Tutorial.Feed(tr3, { k = "tick", now = 10 + Tutorial.STAM_TIMEOUT + 0.1 })
check("stamina: times out", Tutorial.Current(tr3).id == "special")
-- the idle safety: the clock runs after MAX_HOLD
local tr4 = Tutorial.NewTracker()
Tutorial.Feed(tr4, { k = "tick", now = 5 })
check("held at first", Tutorial.Phase(tr4, 1, 6) == "hold")
check("an idle player's bout ends", Tutorial.Phase(tr4, 1, 5 + Tutorial.MAX_HOLD + 1) == "run")
-- the engine applies the rules (source checks: the round loop, the knockdowns, the stoppage)
local feSrc = fs.readFile(H.src .. "/server/FightEngine.lua")
check("FightEngine holds the clock", feSrc:find('tphase == "hold"', 1, true) ~= nil)
check("FightEngine keeps the player up", feSrc:find("Tutorial.CanDrop(self.tutorial)", 1, true) ~= nil)
check("FightEngine feeds the punches", feSrc:find('TutorialNote({ k = "punch"', 1, true) ~= nil)
check("FightEngine aborts a held bout whose player left", feSrc:find("the player left: nothing would ever move a held clock on", 1, true) ~= nil)

------------------------------------------------------------------------
-- the prompts' keys
------------------------------------------------------------------------
local map = Keymap.Resolve(nil)
for _, s in ipairs(Tutorial.STEPS) do
	local kb = Tutorial.Caps(s, "keyboard", map, Keymap, nil)
	local pad = Tutorial.Caps(s, "gamepad", map, Keymap, nil)
	local touch = Tutorial.Caps(s, "touch", map, Keymap, nil)
	check("caps " .. s.id .. " one per action", #kb == #s.actions and #pad == #s.actions and #touch == #s.actions)
	for i, a in ipairs(s.actions) do
		check("caps " .. s.id .. " kbd " .. a, kb[i].key == Keymap.ActionText(map, a, "kbd"), kb[i].key)
		check("caps " .. s.id .. " pad " .. a, pad[i].key == Keymap.ActionText(map, a, "pad"), pad[i].key)
		check("caps " .. s.id .. " touch " .. a, type(touch[i].key) == "string" and touch[i].key ~= "-" and touch[i].key ~= "", touch[i].key)
		check("caps " .. s.id .. " caption " .. a, type(kb[i].label) == "string" and kb[i].label ~= "")
	end
end
local jab = Tutorial.Caps("jab", "keyboard", map, Keymap, nil)[1]
check("jab on a keyboard: LMB / J", jab.key == "LMB / J", jab.key)
check("jab on touch: TAP JAB", Tutorial.Caps("jab", "touch", map, Keymap, nil)[1].key == "TAP JAB")
check("move on touch: LEFT STICK", Tutorial.Caps("move", "touch", map, Keymap, nil)[1].key == "LEFT STICK")
check("move on a keyboard: W/A/S/D", Tutorial.Caps("move", "keyboard", map, Keymap, nil)[1].key == "W/A/S/D")
check("slip on touch: the swipe", Tutorial.Caps("slip", "touch", map, Keymap, nil)[1].key == "SWIPE BLOCK LEFT")
local custom = Keymap.Resolve({ kbd = { jab = { "N" } }, pad = { jab = "ButtonY", cross = "ButtonX" } })
check("a remapped jab follows (keyboard)", Tutorial.Caps("jab", "keyboard", custom, Keymap, nil)[1].key == "N")
check("a remapped jab follows (pad)", Tutorial.Caps("jab", "gamepad", custom, Keymap, nil)[1].key == Keymap.ActionText(custom, "jab", "pad"))
check("the special's chord", Tutorial.Caps("special", "keyboard", map, Keymap, nil)[1].key == "0")

------------------------------------------------------------------------
-- skip, through the real client module (guisim)
------------------------------------------------------------------------
local S = GS.new("phone")
local P = { created = false, pastCareers = {}, tutorial = { offer = true, done = false }, settings = {} }
local invoked, fired = {}, {}
S.onInvokeServer = function(_, action, ...)
	table.insert(invoked, action)
	if action == "GetProfile" then
		return P
	end
	return { ok = true }
end
S.onFireServer = function(_, msg)
	table.insert(fired, msg)
end
local TC = S.require("Client/Tutorial")
TC.Start()
local State = S.require("Client/State")
local afterSkip, creatorOpened, menuOpened = 0, 0, 0
State.open.Creator = function()
	creatorOpened += 1
end
State.open.Menu = function()
	menuOpened += 1
end
local function findIn(node, name)
	for _, d in ipairs(node:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function click(btn)
	S.signal(btn, "MouseButton1Click"):Fire()
	S.settle(0.1)
end
local pg = S.playerGui
TC.Offer(function()
	afterSkip += 1
end)
S.settle(0.3)
check("the offer is up and busy", findIn(pg, "TutorialOffer") ~= nil and TC.Busy())
local skipBtn = findIn(pg, "SkipTutorial")
check("the offer has SKIP TUTORIAL", skipBtn ~= nil)
if skipBtn then
	click(skipBtn)
end
check("skip: SkipTutorial asked", table.find(invoked, "SkipTutorial") ~= nil, table.concat(invoked, ","))
check("skip: on to the title screen", afterSkip == 1 and not TC.Busy() and findIn(pg, "TutorialOffer") == nil)
-- START, the bout's card and its SKIP
TC.Offer(function()
	afterSkip += 1
end)
S.settle(0.2)
click(findIn(pg, "Start"))
check("start: StartTutorial asked", table.find(invoked, "StartTutorial") ~= nil)
S.loadScript("client/FightClient.client.lua")
S.settle(0.3)
local fight = S.remotes.FightEvent
fight:Fire({ t = "start", rounds = 2, tape = { you = { name = "Rafael Ortiz", record = { w = 5, l = 2, d = 0, ko = 3 } }, opp = { name = "Tommy Banks", record = { w = 3, l = 4, d = 0, ko = 1 } } },
	kind = "Tutorial Fight", venue = "ClubArena", venueName = "City Club Arena", moves = { Tutorial.SPECIAL }, tutorial = { total = 10, special = Tutorial.SPECIAL } })
local t1 = Tutorial.NewTracker()
fight:Fire(Tutorial.View(t1))
S.settle(0.4)
local promptCard = findIn(pg, "Prompt")
check("the step card is up", promptCard ~= nil and promptCard.Visible)
local stepLabel = promptCard and findIn(promptCard, "Step")
check("the card names the step", stepLabel ~= nil and stepLabel.Text:find("STEP 1 OF 10", 1, true) ~= nil, stepLabel and stepLabel.Text)
-- the next step's card
Tutorial.Feed(t1, { k = "move", dist = 5, now = 1 })
fight:Fire(Tutorial.View(t1))
S.settle(0.2)
local title = findIn(findIn(pg, "Prompt"), "Title")
check("the card follows the step", title ~= nil and title.Text == "THE JAB", title and title.Text)
local cardSkip = findIn(findIn(pg, "Prompt"), "Skip")
check("the card has SKIP TUTORIAL", cardSkip ~= nil)
if cardSkip then
	click(cardSkip)
end
local sent = false
for _, m in ipairs(fired) do
	if type(m) == "table" and m.t == "tutorialSkip" then
		sent = true
	end
end
check("the card's skip tells the server (tutorialSkip)", sent)
fight:Fire({ t = "tutorialEnd", how = "skipped", created = false })
S.settle(1.0)
check("skipped bout: on to the creator", creatorOpened == 1 and not TC.Busy(), creatorOpened)
-- a completed bout: the wrap-up, then the creator (new player) / the menu (a replay)
fight:Fire({ t = "start", rounds = 2, tape = { you = { name = "A B", record = {} }, opp = { name = "C D", record = {} } }, kind = "Tutorial Fight", venue = "Arena",
	moves = {}, tutorial = { total = 10 } })
S.settle(0.2)
fight:Fire({ t = "tutorialEnd", how = "completed", created = false, you = "A B", opp = "C D", venue = "Grand Arena",
	result = { outcome = "win", method = "Tutorial", landed = 40, thrown = 70, kdFor = 1 } })
S.settle(0.8)
check("the wrap-up is up", findIn(pg, "TutorialDone") ~= nil and TC.Busy())
local cont = findIn(pg, "Continue")
check("the wrap-up's button: CREATE YOUR BOXER", cont ~= nil and cont.Text == "CREATE YOUR BOXER", cont and cont.Text)
if cont then
	click(cont)
end
check("then the creator", creatorOpened == 2 and not TC.Busy())
fight:Fire({ t = "start", rounds = 2, tape = { you = { name = "A B", record = {} }, opp = { name = "C D", record = {} } }, kind = "Tutorial Fight", venue = "Arena",
	moves = {}, tutorial = { total = 10 } })
S.settle(0.2)
fight:Fire({ t = "tutorialEnd", how = "completed", created = true })
S.settle(0.8)
local cont2 = findIn(pg, "Continue")
check("a replay's wrap-up: BACK TO THE MENU", cont2 ~= nil and cont2.Text == "BACK TO THE MENU", cont2 and cont2.Text)
if cont2 then
	click(cont2)
end
check("then the main menu", menuOpened == 1)

print(string.format("test_tutorial: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
