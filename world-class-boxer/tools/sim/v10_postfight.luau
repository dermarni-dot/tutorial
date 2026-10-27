--!nocheck
-- tools/sim/v10_postfight.luau: the judging UI at chosen moments, built by the real client code (guisim) and dumped as
-- layout JSON for tools/ui/render_mock.py:
--   scorecard       between rounds: the round's unofficial scorecard and the punch stats (BoxerClient.Scorecards)
--   scorecard_kd    the same after a knockdown round, the opponent ahead on one card
--   announce        the post-fight scene's banner mid-script (BoxerClient.Ceremony: a judge's card being read)
--   announce_win    the banner on the winner's line (the gold ramp, the stripe)
--   results_ud      the results screen: a unanimous-decision win (BoxerClient.PostFightUI)
--   results_ko      a knockout loss in the 7th: the cards at the stoppage, two knockdowns, the damage report
--   results_title   a championship win on a split decision: the belt kicker, the title notes
--
--   lune run tools/sim/v10_postfight.luau --out tools/sim/out/postfight [--only scorecard,results_ud] [--devices desktop,phone]
--   python3 tools/ui/render_mock.py --all tools/sim/out/postfight --out previews/final/v10/postfight
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local args = process.args
local outDir, only, devices, prefix = nil, nil, { "desktop", "phone" }, ""
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--out" then
		outDir = args[i + 1]
		i += 1
	elseif a == "--only" then
		only = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			only[s] = true
		end
		i += 1
	elseif a == "--devices" then
		devices = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			table.insert(devices, s)
		end
		i += 1
	elseif a == "--prefix" then
		prefix = args[i + 1]
		i += 1
	end
	i += 1
end
local root = Host.FindRoot()
outDir = outDir or (root .. "/tools/sim/out/postfight")
Host.MkDir(root .. "/tools/sim/out")
Host.MkDir(outDir)

local function serverFolder(S)
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

local YOU, OPP = "Marcus Reed-Okonkwo", "Dmitri Volkovsky"
local TAPE = {
	you = { name = YOU, record = { w = 18, l = 2, d = 1, ko = 12 }, nick = "The Hammer", nat = "USA" },
	opp = { name = OPP, record = { w = 27, l = 3, d = 1, ko = 19 }, nick = "Siberian Express", nat = "Russia" },
}

local function client(dev, withMain)
	local S = GS.new(dev)
	local folder = serverFolder(S)
	local Career = S.host.requireNode(folder._kids.Career)
	local Judging = S.host.requireNode(folder._kids.Judging)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = YOU, nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	prof.record = { w = 18, l = 2, d = 1, ko = 12 }
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	P.ranks = { WBC = 4, WBA = 7 }
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	if withMain then
		S.loadScript("client/ClientMain.client.lua")
	end
	S.loadScript("client/FightClient.client.lua")
	S.settle(0.6)
	return S, Judging, P
end

------------------------------------------------------------------------
-- a fight's rounds through the real judges (the server's Judging), so the cards and the stats are the real shapes
------------------------------------------------------------------------
local function side(Judging, o)
	local s = Judging.NewSide()
	for k, v in pairs(o) do
		if type(v) == "table" then
			for t, n in pairs(v) do
				s[k][t] = n
			end
		else
			s[k] = v
		end
	end
	return s
end

-- n rounds of a competitive fight: you the busier, cleaner man, the opponent the heavier puncher; kdRounds = { [r] =
-- "you" | "opp" } knockdowns scored by
local function fightRounds(Judging, n, kdRounds, swing)
	local rng = nil
	local rounds, cards, totals = {}, { { 0, 0 }, { 0, 0 }, { 0, 0 } }, { red = Judging.NewSide(), blue = Judging.NewSide() }
	for r = 1, n do
		local tilt = math.sin(r * 1.3) * 0.25 + (swing or 0.12)
		local yl = math.floor(16 + 7 * tilt + (r % 3)) -- landed
		local ol = math.floor(13 - 5 * tilt + (r % 2))
		local red = side(Judging, {
			landed = yl, thrown = yl + 28 + r, power = math.floor(yl * 0.55), body = 2 + r % 3, counters = r % 2, heavy = r % 4 == 0 and 1 or 0,
			byType = { jab = math.floor(yl * 0.45), cross = math.floor(yl * 0.25), leadhook = math.floor(yl * 0.15), rearhook = math.floor(yl * 0.05), uppercut = math.floor(yl * 0.06), overhand = math.floor(yl * 0.04) },
			thrownByType = { jab = math.floor(yl * 0.45) + 14, cross = math.floor(yl * 0.25) + 7, leadhook = math.floor(yl * 0.15) + 4, rearhook = math.floor(yl * 0.05) + 2, uppercut = math.floor(yl * 0.06) + 2, overhand = math.floor(yl * 0.04) + 1 },
			blocked = 6 + r % 4, evaded = 3 + r % 3, parried = 1, missed = 20, kd = kdRounds and kdRounds[r] == "you" and 1 or 0, liveT = 180, centreT = 110 + 20 * tilt, pressT = 60 + 30 * tilt, mom = tilt,
		})
		local blue = side(Judging, {
			landed = ol, thrown = ol + 22, power = math.floor(ol * 0.7), body = 1 + r % 2, counters = 1 + r % 2, heavy = r % 3 == 0 and 1 or 0,
			byType = { jab = math.floor(ol * 0.3), cross = math.floor(ol * 0.3), leadhook = math.floor(ol * 0.15), rearhook = math.floor(ol * 0.1), uppercut = math.floor(ol * 0.08), overhand = math.floor(ol * 0.07) },
			thrownByType = { jab = math.floor(ol * 0.3) + 9, cross = math.floor(ol * 0.3) + 6, leadhook = math.floor(ol * 0.15) + 3, rearhook = math.floor(ol * 0.1) + 2, uppercut = math.floor(ol * 0.08) + 1, overhand = math.floor(ol * 0.07) + 1 },
			blocked = 9 + r % 3, evaded = 2, parried = 2, missed = 28, kd = kdRounds and kdRounds[r] == "opp" and 1 or 0, liveT = 180, centreT = 70 - 20 * tilt, pressT = 30 - 10 * tilt, mom = -tilt,
		})
		local detail = Judging.Score({ red = red, blue = blue, seconds = 180 }, rng)
		detail.stats = { red = red, blue = blue }
		rounds[r] = detail
		for j = 1, 3 do
			cards[j][1] += detail.cards[j][1]
			cards[j][2] += detail.cards[j][2]
		end
		Judging.AddSide(totals.red, red)
		Judging.AddSide(totals.blue, blue)
	end
	return rounds, cards, totals
end

local function scorecardMsg(Judging, rounds, cards, totals, n)
	local d = rounds[n]
	local msg = { t = "scorecard", n = n, rounds = 12, cards = {}, round = {}, judges = {}, kd = { d.kd[1], d.kd[2] } }
	for j = 1, 3 do
		msg.cards[j] = { cards[j][1], cards[j][2] }
		msg.round[j] = { d.cards[j][1], d.cards[j][2] }
		msg.judges[j] = { id = d.judges[j].id, reason = d.judges[j].reason, diff = d.judges[j].diff }
	end
	msg.stats = { you = d.stats.red, opp = d.stats.blue }
	msg.totals = { you = totals.red, opp = totals.blue }
	return msg
end

local function resultMsg(Judging, rounds, cards, totals, over)
	local res = Judging.Decide(cards)
	res.round = #rounds
	res.reason = "Decision"
	res.cards = cards
	res.judging = Judging.Report(rounds, cards, totals, false)
	res.kdFor, res.kdAgainst = 0, 0
	res.knockdowns = {}
	for r, d in ipairs(rounds) do
		if d.kd[1] > 0 then
			res.kdFor += d.kd[1]
			table.insert(res.knockdowns, { who = "opp", severity = "flash", round = r, cause = "right hand" })
		end
		if d.kd[2] > 0 then
			res.kdAgainst += d.kd[2]
			table.insert(res.knockdowns, { who = "you", severity = "heavy", round = r, cause = "left hook to the body" })
		end
	end
	res.landed, res.thrown, res.oppLanded, res.oppThrown = totals.red.landed, totals.red.thrown, totals.blue.landed, totals.blue.thrown
	res.combos = { chains = 14, landed = 6, best = 4, bestName = "One-Two-Hook", named = {} }
	res.oppCombos = { landed = 3, best = 3 }
	res.dodges, res.evades, res.feints, res.feintBites, res.secondWinds = 22, 11, 6, 2, 1
	res.face = { cut = 0.45, cut2 = 0, cutSide = 1, leftEye = 0.35, rightEye = 0.1, nose = false, noseBleed = 0.5, redness = 0.4, ribsL = 0.2, ribsR = 0.5 }
	res.oppFace = { cut = 0, cut2 = 0, leftEye = 0.1, rightEye = 0.8, nose = true, noseBleed = 0.7, redness = 0.6, ribsL = 0.1, ribsR = 0.1 }
	res.headTaken, res.bodyTaken, res.concPeak, res.damageDealt, res.damageTaken = 38.4, 22, 0.31, 61.2, 44.5
	for k, v in pairs(over or {}) do
		res[k] = v
	end
	return { t = "result", result = res, opp = OPP, kind = "Pro Fight", venue = "Arena",
		earnings = 48500, notes = { "Purse $40,000  Sponsors $6,500  Endorsements $0  TV $4,000  Team salaries -$2,000", "WBC ranking: #4 -> #2.", "Rivalry: Dmitri Volkovsky 1-0-0 (you-them-draws)." } }
end

------------------------------------------------------------------------
-- the screens
------------------------------------------------------------------------
local function startFight(S, rounds)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = rounds or 12, tape = TAPE, kind = "Pro Fight", venue = "Arena", venueName = "Grand Arena", moves = { "overhand" }, stakes = {} })
	S.settle(0.2)
	fire:Fire({ t = "round", n = 3, total = rounds or 12 })
	fire:Fire({ t = "countdown", n = 0, round = 3 })
	local me = { hp = 72, cap = 96, body = 80, bodyCap = 100, stam = 64, max = 100, stamCap = 100, conc = 0, tier = 0, bal = 80 }
	local opp = { hp = 61, cap = 90, body = 70, bodyCap = 100, stam = 58, max = 100, stamCap = 100, conc = 0, tier = 0, bal = 80 }
	fire:Fire({ t = "state", time = 0, me = me, opp = opp })
	S.settle(0.3)
	return fire
end

local SCREENS, ORDER = {}, {}
local function screen(name, fn)
	SCREENS[name] = fn
	table.insert(ORDER, name)
end

local function restScreen(dev, kdRounds)
	local S, Judging = client(dev)
	local rounds, cards, totals = fightRounds(Judging, 3, kdRounds)
	local fire = startFight(S, 12)
	fire:Fire(scorecardMsg(Judging, rounds, cards, totals, 3))
	fire:Fire({ t = "bell", n = 3 })
	S.settle(0.2)
	local u = { math.floor((cards[1][1] + cards[2][1] + cards[3][1]) / 3 + 0.5), math.floor((cards[1][2] + cards[2][2] + cards[3][2]) / 3 + 0.5) }
	fire:Fire({ t = "rest", n = 3, advice = { "Double up the jab - he's walking straight in. Turn him and go downstairs.", "Breathe. You're winning the rounds." }, card = rounds[3].cards[1], unofficial = u,
		stats = { landed = totals.red.landed, thrown = totals.red.thrown, oppLanded = totals.blue.landed, oppThrown = totals.blue.thrown, combos = 4, oppCombos = 2 }, seconds = 60,
		cond = { head = 72, cap = 96, body = 80, bodyCap = 100, conc = 0.1, face = 1, notes = { "Cut over the right eye (bleeding)" } } })
	S.settle(0.6)
	return S
end
screen("scorecard", function(dev)
	return restScreen(dev, nil)
end)
screen("scorecard_kd", function(dev)
	return restScreen(dev, { [2] = "opp", [3] = "you" })
end)

local function announceScreen(dev, atWinner)
	local S, Judging = client(dev, true)
	local rounds, cards, totals = fightRounds(Judging, 12, { [5] = "you" })
	local fire = startFight(S, 12)
	local res = Judging.Decide(cards)
	res.round, res.cards = 12, cards
	fire:Fire({ t = "final", result = res, oppName = OPP })
	S.settle(0.3)
	local a = Judging.Announce(res, { YOU, OPP }, { rounds = 12 })
	-- (the lines are on timers: the ones before the moment are pulled forward)
	local moment = atWinner and a.raiseAt or (a.lines[3] and a.lines[3].at or 3)
	local lines = {}
	for _, l in ipairs(a.lines) do
		if l.at <= moment + 0.01 then
			table.insert(lines, { at = math.max(0, l.at - moment), text = l.text, kind = l.kind })
		end
	end
	fire:Fire({ t = "postfight", lines = lines, dur = a.dur, raiseAt = math.max(0, a.raiseAt - moment), hold = 3, center = S.host.globals.Vector3.new(0, 3, 0), face = S.host.globals.Vector3.new(0, 0, -1),
		method = res.method, outcome = res.outcome, names = { YOU, OPP }, scores = res.scores, you = "red", kind = "Pro Fight" })
	S.settle(0.5)
	return S
end
screen("announce", function(dev)
	return announceScreen(dev, false)
end)
screen("announce_win", function(dev)
	return announceScreen(dev, true)
end)

local function resultsScreen(dev, build)
	local S, Judging = client(dev, true)
	local fire = startFight(S, 12)
	local msg = build(Judging)
	fire:Fire({ t = "final", result = msg.result, oppName = OPP })
	S.settle(0.2)
	fire:Fire(msg)
	S.settle(1.6)
	return S
end
screen("results_ud", function(dev)
	return resultsScreen(dev, function(Judging)
		local rounds, cards, totals = fightRounds(Judging, 12, { [5] = "you" })
		return resultMsg(Judging, rounds, cards, totals)
	end)
end)
screen("results_ko", function(dev)
	return resultsScreen(dev, function(Judging)
		local rounds, cards, totals = fightRounds(Judging, 6, { [4] = "opp" }, -0.3)
		local msg = resultMsg(Judging, rounds, cards, totals, { outcome = "loss", method = "KO", round = 7, reason = "Counted out", scores = nil, decisionText = nil })
		table.insert(msg.result.knockdowns, { who = "you", severity = "out", round = 7, cause = "overhand right" })
		msg.result.kdAgainst += 1
		msg.result.headTaken, msg.result.concPeak = 74.2, 0.82
		msg.result.face.cut, msg.result.face.rightEye = 0.8, 0.6
		msg.earnings = 22000
		msg.notes = { "Purse $20,000  Sponsors $2,000  Endorsements $0  TV $1,500  Team salaries -$1,500", "INJURY: Concussion - 21 days out.", "WBC ranking: #4 -> #9." }
		return msg
	end)
end)
screen("results_title", function(dev)
	return resultsScreen(dev, function(Judging)
		local rounds, cards, totals = fightRounds(Judging, 12, nil, 0.02)
		-- a split decision: the third card the other way
		cards[3] = { 113, 115 }
		local msg = resultMsg(Judging, rounds, cards, totals)
		msg.kind = "World Title Fight"
		msg.earnings = 1250000
		msg.notes = { "NEW WBC WORLD CHAMPION!", "Purse $1,000,000  Sponsors $180,000  Endorsements $50,000  TV $70,000  Team salaries -$50,000", "You are the WBC WORLD CHAMPION!" }
		return msg
	end)
end)

-- the camera's post effects for the renderer
local function postOf(S)
	local cam = S.host.globals.workspace.CurrentCamera
	local post = { blur = 0, sat = 0, bri = 0, con = 0, tint = { 255, 255, 255 } }
	if not cam then
		return post
	end
	for _, c in ipairs(cam:GetChildren()) do
		local ok, cls = pcall(function()
			return c.ClassName
		end)
		if ok and cls == "BlurEffect" then
			post.blur += tonumber(c.Size) or 0
		end
	end
	return post
end

local childAt = table.find(args, "--child")
if childAt then
	local name, dev = args[childAt + 1], args[childAt + 2]
	local ok, err = pcall(function()
		local S = SCREENS[name](dev)
		local items = S.collect()
		local file = string.format("%s/%s%s_%s.json", outDir, prefix, name, dev)
		GS.WriteBoxes(file, S, items, { title = prefix .. name .. "  ·  " .. dev })
		local doc = serde.decode("json", fs.readFile(file))
		doc.post = postOf(S)
		fs.writeFile(file, serde.encode("json", doc, false))
		local checks = S.checks(items, {})
		local flagged = 0
		for _, list in pairs(checks) do
			flagged += #list
		end
		print(string.format("WROTE %s  (%d items, %d flagged)", file, #items, flagged))
		for kind, list in pairs(checks) do
			for _, it in ipairs(list) do
				print(string.format("  %s: %s need=%s room=%s", kind, tostring(it.item and (it.item.path or it.item.text) or it.path), tostring(it.need), tostring(it.room)))
			end
		end
	end)
	if not ok then
		print("FAIL " .. name .. "@" .. dev .. ": " .. tostring(err))
	end
	process.exit(0)
end

local self = root .. "/tools/sim/v10_postfight.luau"
local bad = 0
for _, name in ipairs(ORDER) do
	if not only or only[name] then
		for _, dev in ipairs(devices) do
			local cmd = { "run", self, "--child", name, dev, "--out", outDir }
			if prefix ~= "" then
				table.insert(cmd, "--prefix")
				table.insert(cmd, prefix)
			end
			local r = process.exec("lune", cmd)
			local out = (r.stdout or "") .. (r.stderr or "")
			if not out:find("WROTE") then
				bad += 1
				print(string.format("FAIL %s@%s: %s", name, dev, out:sub(-900)))
			else
				print(out:match("WROTE [^\n]+"))
				for line in out:gmatch("\n(  [^\n]+)") do
					print(line)
				end
			end
		end
	end
end
process.exit(bad == 0 and 0 or 1)
