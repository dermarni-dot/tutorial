--!nocheck
-- tools/sim/test_ui_layout.luau: the game's main screens built by the real client code (guisim) at phone,
-- small phone, tablet, desktop and console sizes (the fight also on a phone with a controller and a short laptop
-- window): the fight HUD in a round (all 14 special moves), with the key strip and stance chips up, between rounds
-- and knocked down; the gym HUD; the title screen, its settings and career screens; the Career Hub; Moves &
-- Controls; the creator; barber, locker, nutrition, sleep, store; a fight result. Their layout is checked:
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

local function profileFor(S)
	local Career = S.host.requireNode(serverModules(S)._kids.Career)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	prof.record = { w = 18, l = 2, d = 1, ko = 12 }
	prof.money = 1250000
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	return P
end

-- a fresh client on device `dev` with the profile pushed (the gym HUD up; the menu not opened at start)
local function client(dev, opts)
	opts = opts or {}
	local S = GS.new(dev)
	local P = profileFor(S)
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
			landed = 143, oppLanded = 88, thrown = 402, oppThrown = 377, kdFor = 2, kdAgainst = 0 },
	})
	S.settle(0.6)
	return S
end)

local DEVICES = { "phone", "phone_small", "tablet", "desktop", "console" }
local PAD_SELECT = { hub = true, hub_training = true, controls = true, result = true, menu_career = true, tutorial_offer = true, tutorial_done = true }
-- (the tutorial's step card is checked with the fight HUD's pieces: on the screen, below the top bar, finger-sized
-- on touch, apart from the scoreboard, the touch pads, the key strip and the stance chips)
-- the fight HUD also on a phone with a controller and a short laptop window (the key strip on small canvases)
local EXTRA = { fight = { "phone_pad", "laptop" }, fight_strip = { "phone_pad", "laptop" }, fight_down = { "phone_pad" }, menu = { "laptop" }, gym = { "laptop" },
	fight_tutorial = { "phone_pad", "laptop" }, fight_tutorial_keys = { "phone_pad", "laptop" }, tutorial_offer = { "phone_pad" } }

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
			"FightUI.HUDRoot.GetUp", "TutorialUI.Root.Prompt",
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
		if name:find("^fight_tutorial") then
			local card = rectOf(S, "TutorialUI.Root.Prompt")
			check(name .. "@" .. dev .. " the tutorial step card is shown", card ~= nil and card.visibleW > 1, card and describe(card))
		end
		local strip = rectOf(S, "FightUI.HUDRoot.Controls")
		if strip then
			check(name .. "@" .. dev .. " key strip within the screen width", strip.x >= -1 and strip.x + strip.w <= S.W + 1, describe(strip))
			check(name .. "@" .. dev .. " key strip under 40% of the screen height", strip.h <= S.H * 0.4, describe(strip))
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
	local f = run(name, dev)
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
