--!nocheck
-- tools/sim/test_ui_layout.luau: the game's main screens built by the real client code (guisim) at phone,
-- small phone, tablet, desktop and console sizes (the fight also on a phone with a controller and a short laptop
-- window): the fight HUD in a round (all 14 special moves), with the key strip and stance chips up, between rounds
-- and knocked down; the gym HUD; the title screen, its settings and career screens; the Career Hub; Moves &
-- Controls; the creator (its Face and Skin steps with Advanced open: the drawn face chips, no Built chip, no
-- built-face-only control, RESET back to Boxer Neutral); the "detailed characters are off" notice; barber, locker, nutrition, sleep, store; a fight result; every training drill's own screen
-- mid-session (drill_*: the weight room, the cardio machines, the recovery stations, the numbered heavy bag
-- combos, the double-end rebounds, the shadow footwork). Their layout is checked:
--   * nothing that draws or takes input runs off the screen
--   * no text or button under the Roblox top bar's buttons (ScreenGuis that ignore the inset)
--   * on touch screens every button is at least GS.TOUCH_PX (44) px both ways
--   * no single-line label is clearly wider than its box (no truncation, scaling or wrapping set)
--   * no text under 10.5 px on the screen
--   * the fight HUD: the touch pads, the special moves, the key strip, the stance chips and the scoreboard
--     keep apart, and the key strip with all 14 special moves fits (at most two special rows, one on a
--     short canvas; the rest behind the "+N MORE" cap), and a phone's special pads stay two rows (paged)
--   * a controller has a selection on the screens Roblox's selection drives
-- Objects drawn under a modal shade (a UI.Window's) are skipped. The box dumps land in tools/sim/out/ui/.
--
--   lune run tools/sim/test_ui_layout.luau                       # the checks
--   lune run tools/sim/test_ui_layout.luau --previews DIR        # also rough layout previews (PNG) into DIR
--   lune run tools/sim/test_ui_layout.luau --only fight,menu --devices phone
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local args = process.args
local previewDir, only, onlyDevices, verbose
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--previews" then
		previewDir = args[i + 1]
		i += 1
	elseif a == "--only" then
		only = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			only[s] = true
		end
		i += 1
	elseif a == "--devices" then
		onlyDevices = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			onlyDevices[s] = true
		end
		i += 1
	elseif a == "-v" then
		verbose = true
	end
	i += 1
end

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local root = Host.FindRoot()
local outDir = root .. "/tools/sim/out/ui"
Host.MkDir(root .. "/tools/sim/out")
Host.MkDir(outDir)

------------------------------------------------------------------------
-- a profile as the server sends it (Career.CreateProfile + Career.Summary, the real server code)
------------------------------------------------------------------------
local function serverModules(S)
	local H = S.host
	local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
	for _, f in ipairs(fs.readDir(H.src .. "/server")) do
		local base = f:match("^(.-)%.lua$")
		if base and not f:find("%.server%.") then
			local n = Host.NewNode(base, "ModuleScript", folder)
			rawset(n, "_file", H.src .. "/server/" .. f)
		end
	end
	return folder
end

local function profileFor(S, opts)
	opts = opts or {}
	local folder = serverModules(S)
	local Career = S.host.requireNode(folder._kids.Career)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	prof.record = { w = 18, l = 2, d = 1, ko = 12 }
	prof.money = 1250000
	if opts.tourney then
		-- the Tournaments tab: a local pro with two belts won, inside the City Championship's entry window; with
		-- opts.tourney == "run" he is in its bracket (the semi-final booked, the quarter-finals decided)
		local Tourney = S.host.requireNode(folder._kids.Tourney)
		local TD = S.require("Tournaments")
		local def = TD.ById.city
		prof.tier = 2
		prof.day = def.offset + def.every - def.window + 1
		Tourney.Tick(prof)
		local st = Tourney.State(prof)
		st.belts.novice = { n = 2, last = 3 }
		st.belts.regional = { n = 1, last = 9 }
		st.wear = "novice"
		st.history = { { id = "novice", ed = 4, place = 4, day = 5, prize = 1200, how = "won" }, { id = "city", ed = 9, place = 2, day = 11, prize = 3000, how = "lost" } }
		if opts.tourney == "run" then
			assert(Tourney.Enter(prof, "city"))
			prof.day = prof.tourney.run.ed
			prof.camp.daysLeft = 0
			Career.ApplyResult(prof, { outcome = "win", method = "KO", round = 2, cards = { { 20, 18 }, { 20, 18 }, { 20, 18 } }, kdFor = 1, kdAgainst = 0, landed = 40, oppLanded = 20,
				punches = {}, damageTaken = 30, headTaken = 24, bodyTaken = 16 })
		end
	end
	-- the training programme (opts.program(prof, Training, Career): a plan, a camp, sessions done today)
	local Training = S.host.requireNode(folder._kids.Training)
	if opts.program then
		opts.program(prof, Training, Career)
	end
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	-- (Main's summary adds the programme view)
	P.training = Training.ProgramView(prof)
	return P
end

-- a fresh client on device `dev` with the profile pushed (the gym HUD up; the menu not opened at start)
local function client(dev, opts)
	opts = opts or {}
	local S = GS.new(dev)
	local P = profileFor(S, opts)
	if opts.debut then
		-- a boxer just out of the creator: the guided debut is offered (Main's summary field)
		P.debut = { offer = true, rounds = 3, venue = "Community Center" }
		P.record = { w = 0, l = 0, d = 0, ko = 0 }
	end
	S.P = P
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	if opts.fightOnly then
		S.loadScript("client/FightClient.client.lua")
	else
		S.loadScript("client/ClientMain.client.lua")
		S.loadScript("client/FightClient.client.lua")
	end
	S.settle(0.6)
	return S
end

------------------------------------------------------------------------
-- the screens
------------------------------------------------------------------------
local TAPE = {
	you = { name = "Marcus Reed-Okonkwo", record = { w = 18, l = 2, d = 1, ko = 12 }, nick = "The Hammer", nat = "USA" },
	opp = { name = "Dmitri Volkovsky", record = { w = 27, l = 3, d = 1, ko = 19 }, nick = "Siberian Express", nat = "Russia" },
}
local function startFight(S, moves)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = 12, tape = TAPE, kind = "World Title Fight", venue = "Arena", venueName = "Grand Arena", moves = moves, stakes = { "WBC", "WBA" } })
	S.settle(0.2)
	fire:Fire({ t = "round", n = 1, total = 12 })
	fire:Fire({ t = "countdown", n = 0, round = 1 })
	fire:Fire({ t = "state", time = 170, me = { hp = 80, cap = 100, body = 70, bodyCap = 100, stam = 60, max = 100, stamCap = 100, conc = 0, tier = 1, bal = 80 },
		opp = { hp = 60, cap = 90, body = 50, bodyCap = 100, stam = 40, max = 100, stamCap = 100, conc = 0, tier = 1 } })
	S.settle(1.2)
end

local function find(S, path)
	local n = S.playerGui
	for part in path:gmatch("[^%.]+") do
		n = n and n:FindFirstChild(part)
	end
	return n
end

local SCREENS = {}
local ORDER = {}
local function screen(name, fn)
	SCREENS[name] = fn
	table.insert(ORDER, name)
end

-- the fight HUD in a live round, all 14 special moves unlocked
screen("fight", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	return S
end)
-- the same with the guard and the body shot armed (the stance chips) and the key strip held up
screen("fight_strip", function(dev)
	local S = client(dev, { fightOnly = true })
	S.player:SetAttribute("ControlHints", true)
	startFight(S, S.require("Moves").List)
	for _, n in ipairs({ "FightUI.HUDRoot.StanceChips.GuardChip", "FightUI.HUDRoot.StanceChips.BodyChip" }) do
		local c = find(S, n)
		if c then
			c.Visible = true
		end
	end
	S.settle(0.2)
	return S
end)
-- between rounds: the scorecard overlay
screen("fight_rest", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	S.remotes.FightEvent:Fire({ t = "bell", n = 1 })
	S.remotes.FightEvent:Fire({ t = "rest", n = 1, card = { 10, 9 }, unofficial = { 10, 9 },
		stats = { landed = 14, thrown = 40, oppLanded = 9, oppThrown = 37 },
		cond = { notes = { "Small cut over the left eye" } }, advice = { "Double up the jab, he's dropping his right after the cross.", "Work the body." } })
	S.settle(1.2)
	return S
end)
-- knocked down: the count and the get-up panel
screen("fight_down", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	S.remotes.FightEvent:Fire({ t = "kd", who = "you", severity = "hard" })
	S.remotes.FightEvent:Fire({ t = "getupStart", who = "you", target = 12, ability = 0.6, severity = "hard" })
	S.remotes.FightEvent:Fire({ t = "count", n = 4, who = "you" })
	S.settle(1.2)
	return S
end)
-- the knockdown screen (Client/KnockFX: its ScreenGui, KnockBlur / KnockGrade on the camera) and the get-up
-- panel's own count; the panel is one tap target as big as itself
local function knockOn(S)
	local cam = S.host.globals.workspace.CurrentCamera
	return find(S, "KnockFX") ~= nil, cam and cam:FindFirstChild("KnockBlur") ~= nil
end
local function downTo(S, mash, counts)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "kd", who = "you", severity = "heavy" })
	fire:Fire({ t = "getupStart", who = "you", target = 12, ability = 0.6, severity = "heavy" })
	for n = 1, counts do
		fire:Fire({ t = "count", n = n, who = "you", mash = mash, target = 12 })
	end
	S.settle(0.6)
end
screen("fight_getup", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	downTo(S, 5, 5)
	local tag = "fight_getup@" .. dev
	local gui, blur = knockOn(S)
	check(tag .. ": the knockdown screen is up", gui and blur, tostring(gui) .. " / " .. tostring(blur))
	local num = find(S, "FightUI.HUDRoot.GetUp.Body.CountBox.Number")
	check(tag .. ": the panel carries the count", num ~= nil and num.Text == "5", num and num.Text)
	local box = find(S, "FightUI.HUDRoot.Count")
	check(tag .. ": the count box stands aside", box ~= nil and box.Visible == false)
	return S
end)
-- the get-up panel's STAND UP! and COUNTED OUT states
screen("fight_getup_up", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	downTo(S, 12, 6)
	S.remotes.FightEvent:Fire({ t = "getup", who = "you" })
	S.settle(0.3)
	local t = find(S, "FightUI.HUDRoot.GetUp.Body.Main.Callout")
	check("fight_getup_up@" .. dev .. ": STAND UP!", t ~= nil and t.Text == "STAND UP!", t and t.Text)
	return S
end)
screen("fight_getup_out", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	downTo(S, 3, 10)
	local t = find(S, "FightUI.HUDRoot.GetUp.Body.Main.Callout")
	check("fight_getup_out@" .. dev .. ": COUNTED OUT", t ~= nil and t.Text == "COUNTED OUT", t and t.Text)
	return S
end)
-- knocked out cold, then the result: the knockdown screen is all gone afterwards (no lingering blur)
screen("fight_ko", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "kd", who = "you", severity = "out" })
	S.settle(0.6)
	local gui, blur = knockOn(S)
	check("fight_ko@" .. dev .. ": the knockout screen is up", gui and blur)
	if dev == "desktop" then
		-- (a second client: the clean-up after the result)
		local S2 = client(dev, { fightOnly = true })
		startFight(S2, S2.require("Moves").List)
		S2.remotes.FightEvent:Fire({ t = "kd", who = "you", severity = "out" })
		S2.settle(0.3)
		S2.remotes.FightEvent:Fire({ t = "result", result = { outcome = "loss", method = "KO" } })
		S2.settle(0.3)
		local g2, b2 = knockOn(S2)
		check("fight_ko@" .. dev .. ": nothing lingers after the result", not g2 and not b2, tostring(g2) .. " / " .. tostring(b2))
	end
	return S
end)
-- the first-time tutorial bout: the step card (TutorialUI.Root.Prompt) over the real fight HUD, at the step with the
-- longest text and its checklist (stamina) and at the one with the most key caps (finish, the key strip held up)
local function tutorialFight(dev, stepId, strip)
	local S = client(dev, { fightOnly = true })
	if strip then
		S.player:SetAttribute("ControlHints", true)
	end
	local Steps = S.require("Tutorial")
	S.require("Client/Tutorial").Start()
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = 2, tape = TAPE, kind = "Tutorial Fight", venue = "ClubArena", venueName = "City Club Arena", moves = { Steps.SPECIAL },
		tutorial = { total = #Steps.STEPS, special = Steps.SPECIAL } })
	S.settle(0.2)
	fire:Fire({ t = "round", n = 2, total = 2 })
	fire:Fire({ t = "countdown", n = 0, round = 2 })
	fire:Fire({ t = "state", time = 60, me = { hp = 95, cap = 100, body = 90, bodyCap = 100, stam = 70, max = 100, stamCap = 100, conc = 0, tier = 0, bal = 90 },
		opp = { hp = 60, cap = 90, body = 50, bodyCap = 100, stam = 40, max = 100, stamCap = 100, conc = 0, tier = 1 } })
	local tr = Steps.NewTracker()
	tr.step = Steps.ById[stepId].index
	if stepId == "stamina" then
		tr.goals.drain = true
	end
	fire:Fire(Steps.View(tr))
	S.settle(1.2)
	return S
end
screen("fight_tutorial", function(dev)
	return tutorialFight(dev, "stamina")
end)
-- the fight HUD's combo counter: a named combo just landed (the counter and its call-out up)
local function fireCombo(S)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "combo", who = "you", hits = 2, n = 2 })
	fire:Fire({ t = "combo", who = "you", hits = 4, n = 4, name = "1-2-3-2", id = "onetwothreetwo" })
	fire:Fire({ t = "combo", who = "opp", hits = 2, n = 2, name = "LEFT-RIGHT HOOKS", id = "hookhook" })
	S.settle(0.3)
end
screen("fight_combo", function(dev)
	local S = client(dev, { fightOnly = true })
	startFight(S, S.require("Moves").List)
	fireCombo(S)
	local meter = find(S, "FightUI.HUDRoot.ComboMeter.Card")
	check("fight_combo@" .. dev .. ": the combo counter is up", meter ~= nil and meter.Visible == true)
	local callout = find(S, "FightUI.HUDRoot.ComboMeter.Card.Callout")
	check("fight_combo@" .. dev .. ": the call-out", callout ~= nil and (callout.Text == "OPP  LEFT-RIGHT HOOKS" or callout.Text == "1-2-3-2!"), callout and callout.Text)
	return S
end)
-- the guided debut's step card (the combo step) with the combo counter up beside it
screen("fight_debut", function(dev)
	local S = client(dev, { fightOnly = true })
	local Steps = S.require("Tutorial")
	S.require("Client/Tutorial").Start()
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = 3, tape = TAPE, kind = "Amateur Bout", venue = "CommunityCenter", venueName = "Community Center", moves = { "overhand" },
		tutorial = { total = 12, special = "overhand", debut = true } })
	S.settle(0.2)
	fire:Fire({ t = "round", n = 1, total = 3 })
	fire:Fire({ t = "countdown", n = 0, round = 1 })
	fire:Fire({ t = "state", time = 60, me = { hp = 95, cap = 100, body = 90, bodyCap = 100, stam = 70, max = 100, stamCap = 100, conc = 0, tier = 0, bal = 90 },
		opp = { hp = 80, cap = 100, body = 80, bodyCap = 100, stam = 60, max = 100, stamCap = 100, conc = 0, tier = 0 } })
	local tr = Steps.NewTracker({ debut = true, special = "overhand", specialName = "Loaded overhand", rounds = 3 })
	tr.step = Steps.IndexOf(tr, "counter")
	fire:Fire(Steps.View(tr))
	fireCombo(S)
	S.settle(1.2)
	return S
end)
-- the debut's offer, right after the creator (ClientMain puts it up from the summary)
screen("debut_offer", function(dev)
	local S = client(dev, { debut = true })
	S.settle(0.8)
	check("debut_offer@" .. dev .. ": ClientMain offers the debut", find(S, "TutorialUI.Root.DebutOffer") ~= nil)
	return S
end)
screen("fight_tutorial_keys", function(dev)
	return tutorialFight(dev, "finish", true)
end)
-- the tutorial's offer (a new player, before the title screen) and its wrap-up
screen("tutorial_offer", function(dev)
	local S = client(dev)
	local TC = S.require("Client/Tutorial")
	TC.Start()
	TC.Offer(function() end)
	S.settle(0.8)
	return S
end)
screen("tutorial_done", function(dev)
	local S = client(dev)
	local TC = S.require("Client/Tutorial")
	TC.Start()
	S.loadScript("client/FightClient.client.lua")
	S.settle(0.2)
	S.remotes.FightEvent:Fire({ t = "start", rounds = 2, tape = TAPE, kind = "Tutorial Fight", venue = "Arena", venueName = "Grand Arena", moves = {}, tutorial = { total = 10 } })
	S.settle(0.2)
	S.remotes.FightEvent:Fire({ t = "tutorialEnd", how = "completed", created = false, you = "Rafael Ortiz-Delgado", opp = "Tommy Banks", venue = "Grand Arena",
		result = { outcome = "win", method = "Tutorial", landed = 41, thrown = 77, kdFor = 1 } })
	S.settle(1.2)
	return S
end)
-- the gym HUD (plate, meters, quick actions)
screen("gym", function(dev)
	return client(dev)
end)
-- the gym with the "Detailed characters are off" notice up (AnatomyStatus; shown at once here instead of after
-- its 6 s, which on a slow run lands on whatever screen is being built then). The notice is only for a fault (the
-- engine refusing the Editable APIs, no generators): with every boxer bald (Config.BaldMode) AnatomyClient reports
-- meshes OFF as a setting and no notice shows, so the fault is forced (AnatomyClient.MeshState stubbed as the
-- API refusal) to keep checking the notice's layout and its 44 px close button
screen("anatomy_notice", function(dev)
	local S = client(dev)
	local Status = S.require("Client/AnatomyStatus")
	local AC = S.require("Client/AnatomyClient")
	Status.NOTICE_DELAY = 0
	if S.require("Config").BaldMode then
		S.settle(1.2)
		local line, up, shown = Status.Last()
		check("anatomy_notice@" .. dev .. ": BaldMode is a setting, not a fault (no notice)",
			not up and not shown and tostring(line):find("BaldMode", 1, true) ~= nil, tostring(line))
	end
	AC.MeshState = function()
		return "off", "EditableMesh is not enabled for this experience", "api"
	end
	for _ = 1, 8 do
		S.settle(0.6)
		if find(S, "AnatomyStatusNotice.Notice.Close") then
			break
		end
	end
	assert(find(S, "AnatomyStatusNotice.Notice.Close"), "the AnatomyStatus notice did not show: " .. tostring((Status.Last())))
	return S
end)
-- the title screen (main menu home) and its sub screens
screen("menu", function(dev)
	local S = client(dev)
	S.require("Client/MainMenu").Open()
	S.settle(1.6)
	return S
end)
screen("menu_settings", function(dev)
	local S = client(dev)
	S.require("Client/MainMenu").Open("settings")
	S.settle(1.6)
	return S
end)
screen("menu_career", function(dev)
	local S = client(dev)
	S.require("Client/MainMenu").Open("career")
	S.settle(1.6)
	return S
end)
-- the Career Hub
screen("hub", function(dev)
	local S = client(dev)
	S.require("Client/Hub").Open("Career")
	S.settle(0.6)
	return S
end)
-- the Tournaments tab: the calendar (an open entry, the rules, prizes, holders), the belts won with WEAR IN RING
-- WALKS, the results; and with a bracket being fought (the semi-final booked): the bracket on top
screen("hub_tournaments", function(dev)
	local S = client(dev, { tourney = true })
	S.require("Client/Hub").Open("Tournaments")
	S.settle(0.6)
	check("hub_tournaments@" .. dev .. ": an event to enter", find(S, "BoxerUI.Root.Hub") ~= nil)
	return S
end)
-- scroll the hub's content so the named section is at the top of the view (the checks see what is on the screen)
local function scrollTo(S, name)
	local obj
	local function walk(n)
		for _, c in ipairs(n:GetChildren()) do
			if obj then
				return
			end
			if c.Name == name then
				obj = c
				return
			end
			walk(c)
		end
	end
	walk(S.playerGui)
	assert(obj, "no " .. name .. " on the screen")
	local sc = obj.Parent
	while sc and not sc:IsA("ScrollingFrame") do
		sc = sc.Parent
	end
	assert(sc, name .. " is not in a scrolling list")
	local y = obj.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
	sc.CanvasPosition = require("@lune/roblox").Vector2.new(0, math.max(0, y - 8))
	S.settle(0.2)
	return obj
end
screen("hub_bracket", function(dev)
	local S = client(dev, { tourney = "run" })
	S.require("Client/Hub").Open("Tournaments")
	S.settle(0.6)
	local b = scrollTo(S, "Bracket")
	local n = 0
	for _, d in ipairs(b:GetDescendants()) do
		if d.Name:match("^Match%d_%d$") then
			n += 1
		end
	end
	check("hub_bracket@" .. dev .. ": 7 matches drawn", n == 7, n)
	return S
end)
-- the bracket's run card on top (WITHDRAW, the wear) and the belts won section
screen("hub_bracket_card", function(dev)
	local S = client(dev, { tourney = "run" })
	S.require("Client/Hub").Open("Tournaments")
	S.settle(0.6)
	scrollTo(S, "RunName")
	return S
end)
screen("hub_tourney_belts", function(dev)
	local S = client(dev, { tourney = true })
	S.require("Client/Hub").Open("Tournaments")
	S.settle(0.6)
	scrollTo(S, "Belts")
	return S
end)
-- the celebration cutscene's banner, letterbox and SKIP over the fight's final scene (BoxerClient.Ceremony)
screen("ceremony", function(dev)
	local S = client(dev)
	startFight(S, {})
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "final", result = { outcome = "win", method = "KO", round = 7 }, oppName = "Dmitri Volkovsky" })
	S.settle(0.3)
	local TD = S.require("Tournaments")
	fire:Fire({ t = "ceremony", spec = { belt = "world", kicker = "AND THE NEW...", title = TD.ById.world.champion, event = TD.ById.world.name, name = "Marcus Reed-Okonkwo" },
		beats = TD.Ceremony })
	S.settle(2.6)
	check("ceremony@" .. dev .. ": the banner is up", find(S, "CeremonyUI.Root.Banner") ~= nil)
	check("ceremony@" .. dev .. ": SKIP", find(S, "CeremonyUI.Root.Skip") ~= nil)
	return S
end)
screen("hub_training", function(dev)
	local S = client(dev)
	S.require("Client/Hub").Open("Training")
	S.settle(0.6)
	return S
end)
-- Moves & Controls
screen("controls", function(dev)
	local S = client(dev)
	S.require("Client/ControlsMenu").Open({})
	S.settle(0.6)
	return S
end)
-- the character creator (a new career) and the gym services
screen("creator", function(dev)
	local S = client(dev)
	S.require("Client/Creator").Open()
	S.settle(0.8)
	return S
end)
-- the creator's Face and Skin steps with Advanced open (the drawn Boxer faces: the style chips, no Built chip, no
-- built-face-only control)
local function named(S, name)
	for _, d in ipairs(S.playerGui:GetDescendants()) do
		if d.Name == name and d.Visible ~= false then
			return d
		end
	end
	return nil
end
local function press(S, name)
	local b = assert(named(S, name), "no button " .. name)
	S.signal(b, "MouseButton1Click"):Fire()
	S.settle(0.4)
end
-- the training programme: the Balanced Week plan with a morning's sessions behind it (goals ticking, a repeat
-- on the heavy bag, personal records), the template picker open, a fight camp in its peak days, the records
local function trainedToday(prof, Training)
	prof.money = 1250000
	Training.SetPlan(prof, "balanced")
	for _, s in ipairs({ { "HeavyBag", 1.3, { punches = 64, maxPower = 812 } }, { "HeavyBag", 1.1, { punches = 58 } }, { "SpeedBag", 1.25, { hitsPerMin = 212, bestStreak = 31 } }, { "Squat", 1.0, { goodReps = 7, load = 185 } } }) do
		local act = Training.Activity(s[1])
		Training.Perform(prof, act, s[2])
		Training.Record(prof, act.id, s[2], s[3])
	end
	Training.Eat(prof, "Balanced")
end
local function inCamp(prof, Training)
	trainedToday(prof, Training)
	local cls = prof.world.classes[prof.physical.weightClass]
	local b = prof.world.boxers[cls[2]]
	prof.camp = { offer = { oppId = b.id, kind = "Pro Fight", opp = { name = b.name, style = b.style } }, daysLeft = 2, daysTotal = 6, log = {},
		-- (four camp days behind him: three solid build days, a sharp peak day)
		prep = { days = { { n = 3, q = 3.5, hard = 1 }, { n = 3, q = 3.4, hard = 1 }, { n = 2, q = 2.6, hard = 2 }, { n = 2, q = 2.5, hard = 2 }, { n = 0, q = 0, hard = 0 }, { n = 0, q = 0, hard = 0 } }, over = 0 } }
	prof.condition.fatigue = 30
	Training.Perform(prof, Training.Activity("DoubleEnd"), 1.25)
end
screen("hub_plan", function(dev)
	local S = client(dev, { program = trainedToday })
	S.require("Client/Hub").Open("Training")
	S.settle(0.6)
	scrollTo(S, "Programme")
	check("hub_plan@" .. dev .. ": the week strip shows seven days", named(S, "PlanDay7") ~= nil and named(S, "PlanDay1") ~= nil)
	check("hub_plan@" .. dev .. ": goals listed", named(S, "Goal") ~= nil)
	return S
end)
screen("hub_plan_edit", function(dev)
	local S = client(dev, { program = trainedToday })
	S.require("Client/Hub").Open("Training")
	S.settle(0.6)
	press(S, "PlanEdit")
	scrollTo(S, "Programme")
	check("hub_plan_edit@" .. dev .. ": the templates", named(S, "Template_balanced") ~= nil and named(S, "Template_none") ~= nil)
	return S
end)
screen("hub_camp", function(dev)
	local S = client(dev, { program = inCamp })
	S.require("Client/Hub").Open("Training")
	S.settle(0.6)
	scrollTo(S, "Programme")
	check("hub_camp@" .. dev .. ": the camp strip and the readiness", named(S, "CampStrip") ~= nil and named(S, "Readiness") ~= nil)
	return S
end)
screen("hub_records", function(dev)
	local S = client(dev, { program = trainedToday })
	S.require("Client/Hub").Open("Training")
	S.settle(0.6)
	scrollTo(S, "Records")
	return S
end)
screen("hub_coaches", function(dev)
	local S = client(dev)
	S.require("Client/Hub").Open("Coaches")
	S.settle(0.6)
	check("hub_coaches@" .. dev .. ": the coach personas", named(S, "CoachPersona") ~= nil)
	return S
end)
local function creatorStep(dev, step)
	local S = client(dev)
	S.require("Client/Creator").Open()
	S.settle(0.8)
	press(S, "Step" .. step)
	press(S, "AdvancedToggle")
	return S
end
screen("creator_face", function(dev)
	local S = creatorStep(dev, 2)
	local Creator = S.require("Client/Creator")
	local chipsOk = named(S, "Chip_built") == nil
	for _, k in ipairs({ "wcb_neutral", "wcb_focused", "wcb_smirk", "wcb_grit" }) do
		chipsOk = chipsOk and named(S, "Chip_" .. k) ~= nil
	end
	check("creator_face@" .. dev .. ": the 4 Boxer face chips, no Built chip", chipsOk)
	local T = S.require("UI").Theme
	local function picked()
		for _, k in ipairs({ "wcb_neutral", "wcb_focused", "wcb_smirk", "wcb_grit" }) do
			local c = named(S, "Chip_" .. k)
			if c and c.BackgroundColor3 == T.gold then
				return k
			end
		end
		return nil
	end
	check("creator_face@" .. dev .. ": a new boxer starts on Boxer Neutral", picked() == "wcb_neutral", picked())
	press(S, "Chip_wcb_grit")
	check("creator_face@" .. dev .. ": a chip picks the face", picked() == "wcb_grit", picked())
	press(S, "ResetStep")
	check("creator_face@" .. dev .. ": RESET goes back to Boxer Neutral", picked() == "wcb_neutral", picked())
	local hidden = true
	for _, n in ipairs({ "Nose Width", "Lip Thickness", "Eyebrow Thickness", "Mouth Width", "Broken Nose" }) do
		for _, d in ipairs(S.playerGui:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == n then
				hidden = false
			end
		end
	end
	check("creator_face@" .. dev .. ": no built-face-only slider", hidden)
	assert(Creator.IsOpen(), "the creator closed")
	return S
end)
screen("creator_skin", function(dev)
	local S = creatorStep(dev, 3)
	local hidden = true
	for _, d in ipairs(S.playerGui:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and (d.Text == "Eye colour" or d.Text == "Eyebrow style" or d.Text == "Skin undertone"
			or d.Text == "Right eye (heterochromia)" or d.Text == "Eye Size") then
			hidden = false
		end
	end
	check("creator_skin@" .. dev .. ": no eye / brow / undertone control", hidden)
	return S
end)
for _, svc in ipairs({ "Barber", "Locker", "Nutrition", "Sleep", "Store" }) do
	screen(string.lower(svc), function(dev)
		local S = client(dev)
		S.require("Client/State").open[svc]()
		S.settle(0.8)
		return S
	end)
end
-- a fight result
screen("result", function(dev)
	local S = client(dev)
	local State = S.require("Client/State")
	State.open.Result({
		venue = "Grand Arena", opp = "Dmitri Volkovsky", earnings = 250000,
		notes = { "WORLD CHAMPION: you won the WBC belt", "NEW SPECIAL MOVE: Liver Shot" },
		result = { outcome = "win", method = "KO", round = 7, reason = "Left hook to the liver", cards = { { 59, 55 }, { 58, 56 }, { 60, 54 } },
			landed = 143, oppLanded = 88, thrown = 402, oppThrown = 377, kdFor = 2, kdAgainst = 0,
			combos = { chains = 31, landed = 12, best = 6, bestName = "DEMPSEY FINISH", named = {} }, oppCombos = { landed = 7, best = 4 } },
	})
	S.settle(0.6)
	return S
end)
-- [Entrance] the Locker Room's ENTRANCE picker (BoxerClient.EntrancePicker) on an old save's defaults, the belt lift noted
screen("entrance", function(dev)
	local S = client(dev)
	-- (ClientMain loads the picker in a thread of its own: wait for it before requiring the same modules here)
	local State = S.require("Client/State")
	for _ = 1, 20 do
		if State.open.Entrance then
			break
		end
		S.settle(0.1)
	end
	S.P.entrance = S.require("Entrance").View({})
	State.open.Entrance()
	S.settle(0.6)
	check("entrance@" .. dev .. ": the picker is up", find(S, "BoxerUI.Root.Entrance") ~= nil)
	return S
end)
-- [Entrance] the ring walk's overlay (BoxerClient.EntranceFX: the name reveal and SKIP) over the fight HUD
screen("entrance_walk", function(dev)
	local S = client(dev, { fightOnly = true })
	local FX = S.require("Client/EntranceFX")
	FX.Start()
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = 12, tape = TAPE, kind = "World Title Fight", venue = "Arena", venueName = "Grand Arena", moves = {}, stakes = { "WBC" } })
	S.settle(0.2)
	local Inst = S.host.globals.Instance
	local m = Inst.new("Model")
	local hrp = Inst.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = require("@lune/roblox").Vector3.new(2, 2, 1)
	hrp.Parent = m
	local hum = Inst.new("Humanoid")
	hum.HipHeight = 2
	hum.Parent = m
	local Entrance = S.require("Entrance")
	local plan = Entrance.Plan({ corner = "Red", choice = {}, popularity = 20, venue = "Arena" })
	plan.model, plan.name, plan.nick, plan.record, plan.nat = m, "Marcus Reed-Okonkwo", "The Hammer", { w = 18, l = 2, d = 1, ko = 12 }, "USA"
	fire:Fire({ t = "entrance", phase = "you", plan = plan })
	S.settle(0.6)
	return S
end)
-- the training drills mid-session (tools/sim/drillsim.luau: the real client drill, the server's real plan, a
-- virtual clock run up to the moment the drill's own screen is up): the panel, its stage, its buttons and the
-- metrics strip / muscles card at the drill's widest point
local DrillSim = require("./drillsim")
local DRILLS = {
	-- { screen, activity, the segment judge to stop in, frames into it, extra predicate }
	{ "drill_combo_numbers", "HeavyBag", "seq", 30, function(seg)
		return seg.call == "numbers"
	end, 5 },
	{ "drill_rebound", "DoubleEnd", "rebound", 30 },
	{ "drill_footwork", "Shadow", "notes", 150 },
	{ "drill_bench", "Bench", "bench", 60 },
	{ "drill_deadlift", "Barbell", "deadlift", 60 },
	{ "drill_squat", "Squat", "squat", 60 },
	{ "drill_pullup", "PullUps", "pullup", 60 },
	{ "drill_curls", "Dumbbells", "tempo", 150 },
	{ "drill_treadmill", "Treadmill", "treadmill", 200 },
	{ "drill_bike", "Bike", "bike", 200 },
	{ "drill_rower", "Rower", "rower", 120 },
	{ "drill_icebath", "IceBath", "icebath", 120 },
	{ "drill_stretch", "Stretch", "stretch", 90 },
	{ "drill_massage", "Massage", "massage", 60 },
	{ "drill_massage_work", "Massage", "massage", 60 * 9 },
	{ "drill_chamber", "Chamber", "chamber", 300 },
	{ "drill_sauna", "Sauna", "sauna", 300 },
}
for _, d in ipairs(DRILLS) do
	screen(d[1], function(dev)
		local S = client(dev)
		DrillSim.SeedRandom(S.host)
		local Config = S.require("Config")
		local act = Config.FindById(Config.Activities, d[2])
		local params = { level = d[6] or 3 }
		if act.minigame == "massage" then
			params.sore = { back = 0.7, legs = 0.45, shoulders = 0.2, core = 0.3, neck = 0.15 }
		elseif act.minigame == "stretch" then
			params.stretchNames = { "HAMSTRINGS", "HIP FLEXORS", "SHOULDERS", "CALVES" }
		end
		local D = DrillSim.Attach(S, { act = act, lv = d[6] or 3, params = params, P = S.P })
		D.start()
		local reached = D.until_(function(ctx)
			local seg = ctx.plan.segs[ctx.segI]
			return seg ~= nil and seg.j == d[3] and ctx.judges[ctx.segI] ~= nil and not ctx.resting and (d[5] == nil or d[5](seg))
		end, 60 * 240)
		assert(reached, "the drill never reached its " .. d[3] .. " segment")
		for _ = 1, d[4] do
			D.frame()
		end
		return S
	end)
end

-- a drill's report card: the real client drill played idle to its end, the server's real result for a session
-- graded A after a morning of training (the coach's report: the multipliers, well / fix, mastery, goals, the
-- soreness map)
screen("drill_report", function(dev)
	local S = client(dev)
	DrillSim.SeedRandom(S.host)
	local Config = S.require("Config")
	local act = Config.FindById(Config.Activities, "SpeedBag")
	local Training = DrillSim.ServerModule(S.host, "Training")
	local Career = DrillSim.ServerModule(S.host, "Career")
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
	prof.money = 50000
	Training.SetPlan(prof, "speed")
	for _, id in ipairs({ "SpeedBag", "HeavyBag", "Bench" }) do
		Training.Perform(prof, Training.Activity(id), 1.25)
		Training.Record(prof, id, 1.25, { punches = 40 })
	end
	local D = DrillSim.Attach(S, { act = act, lv = 3, params = { level = 3 }, P = S.P, finish = function(_, stats)
		local q = 1.28
		local result = Training.Perform(prof, act, q)
		local record = Training.Record(prof, act.id, q, Training.SanitizeStats(stats) or { hitsPerMin = 230 })
		return { ok = true, result = result, quality = q, act = act.id, record = record }
	end })
	D.start()
	local shown = false
	for _ = 1, 60 * 240 do
		D.frame()
		if named(S, "ReportKicker") then
			shown = true
			break
		end
	end
	assert(shown, "the report card never showed")
	for _ = 1, 90 do
		D.frame()
	end
	check("drill_report@" .. dev .. ": what went well and the mastery bar", named(S, "Well") ~= nil and named(S, "Mastery") ~= nil)
	return S
end)

local DEVICES = { "phone", "phone_small", "tablet", "desktop", "console" }
local PAD_SELECT = { entrance = true, hub = true, hub_training = true, hub_plan = true, hub_tournaments = true, hub_bracket = true, controls = true, result = true, menu_career = true, tutorial_offer = true, tutorial_done = true, debut_offer = true }
-- (the tutorial's step card is checked with the fight HUD's pieces: on the screen, below the top bar, finger-sized
-- on touch, apart from the scoreboard, the touch pads, the key strip and the stance chips)
-- the fight HUD also on a phone with a controller and a short laptop window (the key strip on small canvases)
local EXTRA = { entrance_walk = { "phone_pad", "laptop" }, drill_bench = { "laptop" }, drill_massage = { "laptop", "phone_pad" }, drill_bike = { "laptop" }, fight = { "phone_pad", "laptop" }, fight_strip = { "phone_pad", "laptop" }, fight_down = { "phone_pad" }, menu = { "laptop" }, gym = { "laptop" },
	fight_tutorial = { "phone_pad", "laptop" }, fight_tutorial_keys = { "phone_pad", "laptop" }, tutorial_offer = { "phone_pad" },
	fight_combo = { "phone_pad", "laptop" }, fight_debut = { "phone_pad", "laptop" }, debut_offer = { "phone_pad" } }

------------------------------------------------------------------------
-- checks
------------------------------------------------------------------------
-- decoration that is meant to bleed off the screen or sit anywhere (full-bleed light, the menu's dust, the
-- broadcast vignette / letterbox / flash layers, shadows)
local function decorative(it)
	local p = it.path
	return p:find("%.Backdrop%.") ~= nil or p:find("^FightFX%.") ~= nil or it.name == "Shadow" or p:find("%.Shadow") ~= nil
		or p:find("Wipe") ~= nil or p:find("%.Dust%.") ~= nil
end

local function describe(it)
	return string.format("%s [%d,%d %dx%d]", it.path or "?", it.x, it.y, it.w, it.h)
end

local function rectOf(S, path)
	local o = find(S, path)
	if not o then
		return nil
	end
	local items = S.lastItems
	for _, it in ipairs(items) do
		if it.obj == o then
			return it
		end
	end
	return nil
end

local function run(name, dev)
	local okBuild, S = pcall(SCREENS[name], dev)
	check(name .. "@" .. dev .. " builds", okBuild, S)
	if not okBuild then
		return
	end
	local items = S.collect()
	S.lastItems = items
	local c = S.checks(items, { ignore = decorative })
	local bad = {}
	local function report(kind, list, fmt)
		local names = {}
		for _, e in ipairs(list) do
			bad[e.item.obj] = kind
			table.insert(names, describe(e.item) .. (fmt and fmt(e) or ""))
		end
		check(string.format("%s@%s %s", name, dev, kind), #list == 0, #list > 0 and ("\n      " .. table.concat(names, "\n      ")) or nil)
	end
	report("off screen", c.offscreen, function(e)
		return string.format(" over %.0f px", e.over)
	end)
	report("under the top bar", c.topbar)
	report("touch target < 44 px", c.touch, function(e)
		return string.format(" %.0f px", e.size)
	end)
	report("text wider than its box", c.text, function(e)
		return string.format(" needs %.0f of %.0f px", e.need, e.room)
	end)
	report("text under 10.5 px", c.small, function(e)
		return string.format(" %.1f px", e.px)
	end)
	-- every icon on the screen is one the icon set (or the kit's Frame drawing) knows: an unknown name draws
	-- UI.Icon's first-letter stand-in ("Letter")
	local unknown = {}
	for _, it in ipairs(items) do
		if it.name == "Letter" and it.path:find("%.Glyph%.Letter$") then
			table.insert(unknown, { item = it })
		end
	end
	report("unknown icon name", unknown)
	-- the fight HUD's pieces keep apart
	if name:find("^fight") then
		local pieces = {
			"FightUI.HUDRoot.Scoreboard", "FightUI.HUDRoot.TouchPad", "FightUI.HUDRoot.TouchPad.Specials", "FightUI.HUDRoot.DefencePad", "FightUI.HUDRoot.MovesPad", "FightUI.HUDRoot.SprintPad",
			"FightUI.HUDRoot.Controls", "FightUI.HUDRoot.StanceChips", "FightUI.HUDRoot.Ticker", "FightUI.HUDRoot.Overlay", "FightUI.HUDRoot.Count",
			"FightUI.HUDRoot.GetUp", "TutorialUI.Root.Prompt", "FightUI.HUDRoot.ComboMeter",
		}
		-- a piece's extent: what it and its descendants draw (or take input with) on the screen
		local function extent(path)
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, it in ipairs(items) do
				if (it.path == path or it.path:sub(1, #path + 1) == path .. ".") and (it.draws or it.button) and it.visibleW > 0.5 and it.visibleH > 0.5 then
					x0, y0 = math.min(x0, it.x), math.min(y0, it.y)
					x1, y1 = math.max(x1, it.x + it.w), math.max(y1, it.y + it.h)
				end
			end
			if x0 == math.huge then
				return nil
			end
			return { x = x0, y = y0, w = x1 - x0, h = y1 - y0, path = path }
		end
		local seen = {}
		for _, p in ipairs(pieces) do
			local it = extent(p)
			if it and it.w > 1 and it.h > 1 then
				table.insert(seen, { p = p, it = it })
			end
		end
		for a = 1, #seen do
			for b = a + 1, #seen do
				local A, B = seen[a], seen[b]
				local nested = B.p:sub(1, #A.p + 1) == A.p .. "." or A.p:sub(1, #B.p + 1) == B.p .. "."
				if not nested then
					check(string.format("%s@%s %s clear of %s", name, dev, A.p:match("[^.]+$"), B.p:match("[^.]+$")), not GS.Overlap(A.it, B.it, 1),
						describe(A.it) .. " / " .. describe(B.it))
				end
			end
		end
		-- the special moves on touch: a phone keeps them to two rows next to the punches (paged past that)
		local sp = rectOf(S, "FightUI.HUDRoot.TouchPad.Specials")
		if sp and dev:find("^phone") then
			check(name .. "@" .. dev .. " special pads at most two rows", sp.h <= 2 * 57 * sp.unit + 6 * sp.unit + 2, describe(sp))
		end
		-- the tutorial's step card is up where the screen has one
		if name:find("^fight_tutorial") or name == "fight_debut" then
			local card = rectOf(S, "TutorialUI.Root.Prompt")
			check(name .. "@" .. dev .. " the tutorial step card is shown", card ~= nil and card.visibleW > 1, card and describe(card))
		end
		local strip = rectOf(S, "FightUI.HUDRoot.Controls")
		if strip then
			check(name .. "@" .. dev .. " key strip within the screen width", strip.x >= -1 and strip.x + strip.w <= S.W + 1, describe(strip))
			check(name .. "@" .. dev .. " key strip under 40% of the screen height", strip.h <= S.H * 0.4, describe(strip))
		end
	end
	-- [Entrance] the walk's overlay: the reveal and SKIP are up and keep clear of each other and of the ticker
	if name == "entrance_walk" then
		local rv, sk = rectOf(S, "EntranceUI.Root.Reveal"), rectOf(S, "EntranceUI.Root.Skip")
		check(name .. "@" .. dev .. " the reveal and SKIP are up", rv ~= nil and sk ~= nil and rv.visibleW > 1 and sk.visibleW > 1)
		if rv and sk then
			check(name .. "@" .. dev .. " reveal clear of SKIP", not GS.Overlap(rv, sk, 1), describe(rv) .. " / " .. describe(sk))
			local tk = rectOf(S, "FightUI.HUDRoot.Ticker")
			if tk and tk.visibleW > 1 then
				check(name .. "@" .. dev .. " reveal clear of the ticker", not GS.Overlap(rv, tk, 1), describe(rv) .. " / " .. describe(tk))
				check(name .. "@" .. dev .. " SKIP clear of the ticker", not GS.Overlap(sk, tk, 1), describe(sk) .. " / " .. describe(tk))
			end
		end
	end
	-- a controller gets a selection on the screens Roblox's selection drives (UI.Window's start selection, the
	-- menu's sub screens), on a button that is on the screen and not behind a modal shade
	if (dev == "console" or dev == "phone_pad") and PAD_SELECT[name] then
		local sel = rawget(S.host.Service("GuiService"), "SelectedObject")
		local shownSel = nil
		for _, it in ipairs(items) do
			if it.obj == sel then
				shownSel = it
			end
		end
		check(string.format("%s@%s a pad selection on screen", name, dev), shownSel ~= nil and not shownSel.blocked and shownSel.visibleW > 1,
			sel and S.pathOf(sel) or "nothing selected")
	end
	local file = string.format("%s/%s_%s.json", outDir, name, dev)
	GS.WriteBoxes(file, S, items, { bad = bad, title = name .. "  ·  " .. dev })
	if verbose then
		print(string.format("%s@%s: %d objects", name, dev, #items))
	end
	return file
end

-- each screen on each device in a process of its own (a client leaves threads and instances behind; a few
-- dozen in one process run out of memory), four at a time; --child NAME DEVICE is one of them
local childAt = table.find(args, "--child")
if childAt then
	local name, dev = args[childAt + 1], args[childAt + 2]
	-- (an error ends the child too: a drill screen leaves threads running that would keep it alive)
	local okRun, f = pcall(run, name, dev)
	if not okRun then
		check(name .. "@" .. dev .. " lays out", false, f)
		f = nil
	end
	print(string.format("CHILD %d %d %s", pass, fail, f or ""))
	process.exit(0)
end

local jobs = {}
for _, name in ipairs(ORDER) do
	if not only or only[name] then
		local devs = table.clone(DEVICES)
		for _, d in ipairs(EXTRA[name] or {}) do
			table.insert(devs, d)
		end
		for _, dev in ipairs(devs) do
			if not onlyDevices or onlyDevices[dev] then
				table.insert(jobs, { name, dev })
			end
		end
	end
end
local files = {}
local self = root .. "/tools/sim/test_ui_layout.luau"
local nextJob, running = 1, 0
local function worker()
	while nextJob <= #jobs do
		local job = jobs[nextJob]
		nextJob += 1
		local r = process.exec("lune", { "run", self, "--child", job[1], job[2] })
		local out = r.stdout or ""
		local p, f, file = out:match("CHILD (%d+) (%d+) ([^\n]*)")
		if not p then
			fail += 1
			print(string.format("FAIL %s@%s: the child process did not finish (%s)", job[1], job[2], (r.stderr or ""):sub(-300)))
		else
			pass += tonumber(p)
			fail += tonumber(f)
			if file ~= "" then
				table.insert(files, file)
			end
			-- its FAIL lines (and their detail lines)
			local keep = false
			for line in out:gmatch("[^\n]+") do
				if line:match("^FAIL ") then
					keep = true
				elseif not line:match("^      ") then
					keep = false
				end
				if keep then
					print(line)
				end
			end
			if verbose then
				print(string.format("%s@%s: %s passed, %s failed", job[1], job[2], p, f))
			end
		end
	end
	running -= 1
end
for _ = 1, 4 do
	running += 1
	task.spawn(worker)
end
while running > 0 do
	task.wait(0.1)
end
table.sort(files)

if previewDir then
	Host.MkDir(previewDir)
	local cmd = { root .. "/tools/sim/ui_preview.py" }
	for _, f in ipairs(files) do
		table.insert(cmd, f)
	end
	table.insert(cmd, "--out")
	table.insert(cmd, previewDir)
	local r = process.exec("python3", cmd)
	check("previews rendered", r.ok, r.stderr)
end

print(string.format("test_ui_layout: %d passed, %d failed", pass, fail))
process.exit(fail == 0 and 0 or 1)
