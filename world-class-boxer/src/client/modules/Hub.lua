-- Hub: the Career Hub window.
-- Career (offers, camp, fight night), Training (condition, food, sleep, every activity),
-- Body (physique & muscle groups), Stats, Gym (upgrade / repair equipment), Gear
-- (gloves, shoes, wraps, mouthguards, robes), Coaches, Rankings, Rivals, Shop, Legacy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme
local rec = State.rec

local Hub = {}
local shade, win, content
local tab = "Career"
local TABS = { "Career", "Training", "Body", "Stats", "Gym", "Gear", "Coaches", "Rankings", "Rivals", "Shop", "Legacy" }
local tabButtons = {}

local function money(n)
	return Config.Money(n)
end

local function rankText(ranks)
	local parts = {}
	for _, org in ipairs(Config.Orgs) do
		local r = ranks and ranks[org]
		if r then
			table.insert(parts, org .. " " .. (r == "C" and "CHAMP" or ("#" .. r)))
		end
	end
	return #parts > 0 and table.concat(parts, "  ") or "Unranked"
end

local function stakesText(o)
	local s = {}
	for _, x in ipairs(o.stakes or {}) do
		table.insert(s, x)
	end
	for _, x in ipairs(o.playerStakes or {}) do
		if not table.find(s, x) then
			table.insert(s, x)
		end
	end
	return s
end

local function act(text, color, fn, width)
	return function(parent)
		return UI.Button(parent, text, { Size = UDim2.new(0, width or 170, 1, 0), BackgroundColor3 = color or T.panel2, TextColor3 = (color == T.gold) and T.bg or T.text, TextSize = 14 }, fn)
	end
end

local function buttons(parent, list, h)
	local row = UI.Row(parent, h or 36)
	for _, make in ipairs(list) do
		make(row)
	end
	return row
end

local function result(r, okText)
	if r.ok then
		if okText then
			State.toast(okText, T.green)
		end
	else
		State.toast(r.err or "Can't do that", T.red)
	end
	return r.ok
end

------------------------------------------------------------------------
-- Boxer scouting card
------------------------------------------------------------------------
local function showBoxer(id)
	local res = State.req("GetBoxer", id)
	if not res.ok then
		return
	end
	local b = res.boxer
	local s
	local function close()
		if s then
			s:Destroy()
		end
	end
	local _, _, body
	s, _, body = UI.Window(State.gui, "BoxerCard", 480, 560, b.name, { onClose = close, z = 20 })
	s.ZIndex = 20
	UI.Line(body, string.format("\"%s\"  -  %s  -  Age %d", b.nick, b.nat, b.age), { TextColor3 = T.gold })
	UI.Line(body, string.format("Record %s   Overall %d", rec(b.record), b.overall))
	UI.Line(body, string.format("Style: %s  -  %s", b.style, b.archetype ~= "" and b.archetype or "?"), { TextColor3 = T.sub })
	UI.Line(body, "Personality: " .. b.personality, { TextColor3 = T.sub })
	UI.Line(body, "Rankings: " .. rankText(b.ranks))
	if b.belts and #b.belts > 0 then
		UI.Line(body, "Belts: " .. table.concat(b.belts, ", "), { TextColor3 = T.gold, Font = T.bold })
	end
	if b.h2h.w + b.h2h.l + b.h2h.d > 0 then
		UI.Line(body, string.format("Head-to-head: you %d - %d them (%d draws)   Rivalry heat %d", b.h2h.w, b.h2h.l, b.h2h.d, math.floor(b.heat)), { TextColor3 = T.red })
	end
	for _, k in ipairs(Config.StatKeys) do
		UI.StatRow(body, Config.StatNames[k], b.stats[k], 99, T.red)
	end
end

local function oppBlock(parent, o)
	UI.Line(parent, string.format("%s \"%s\"", o.name, o.nick), { Font = T.bold, TextSize = 19 })
	UI.Line(parent, "Record " .. rec(o.record) .. "    " .. rankText(o.ranks), { TextColor3 = T.sub, TextSize = 14 })
	UI.Line(parent, string.format("%s  -  %s  -  OVR %d  -  %s  -  Age %d", o.style, o.archetype or "", o.overall, o.nat, o.age), { TextColor3 = T.sub, TextSize = 14 })
	if o.h2h and (o.h2h.w + o.h2h.l + o.h2h.d) > 0 then
		UI.Line(parent, string.format("RIVALRY: you %d - %d them (%d draws)  Heat %d", o.h2h.w, o.h2h.l, o.h2h.d, math.floor(o.heat or 0)), { TextColor3 = T.red, Font = T.bold, TextSize = 14 })
	end
	if o.belts and #o.belts > 0 then
		UI.Line(parent, "Holds: " .. table.concat(o.belts, ", "), { TextColor3 = T.gold, TextSize = 14 })
	end
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local R = {}

R.Career = function(body, P)
	local head = UI.Card(body)
	UI.Line(head, string.format("%s \"%s\"", P.identity.name, P.identity.nickname), { Font = T.bold, TextSize = 22, TextColor3 = T.gold })
	UI.Line(head, string.format("%s  -  %s  -  Age %d  -  Day %d  -  %s", P.tierName, P.className, P.identity.age, P.day, P.identity.nationality))
	UI.Line(head, string.format("Pro record %s    Amateur %s", rec(P.record), rec(P.amateurRecord)))
	UI.Line(head, string.format("Money %s    Popularity %d    Overall %d    Style %s", money(P.money), P.popularity, P.overall, P.style))
	if P.tier >= 2 then
		UI.Line(head, "Rankings: " .. rankText(P.ranks), { TextColor3 = T.sub })
	end
	local belts = {}
	for _, org in ipairs(Config.Orgs) do
		if P.belts[org] then
			table.insert(belts, org)
		end
	end
	if P.regional.regional then
		table.insert(belts, "Regional")
	end
	if P.regional.national then
		table.insert(belts, "National")
	end
	if #belts > 0 then
		UI.Line(head, "Titles: " .. table.concat(belts, " - ") .. string.format("   Defenses: %d", P.defenses), { TextColor3 = T.gold, Font = T.bold })
	end
	if not P.storeOk then
		UI.Line(head, "Saving is off in this session (enable Studio API access or publish the game to save progress).", { TextColor3 = T.red, TextSize = 13 })
	end

	if P.camp then
		local c = UI.Card(body, { stroke = T.gold })
		local o = P.camp.offer
		UI.Line(c, string.format("FIGHT CAMP  -  %s  -  %d rounds  -  %s", o.kind:upper(), o.rounds, o.venueName or ""), { Font = T.bold, TextColor3 = T.gold })
		oppBlock(c, o.opp)
		UI.Line(c, "\"" .. (o.talk or "") .. "\"", { TextColor3 = Color3.fromRGB(255, 160, 160), TextSize = 15 })
		local stakes = stakesText(o)
		if #stakes > 0 then
			UI.Line(c, "ON THE LINE: " .. table.concat(stakes, " - ") .. " world title" .. (#stakes > 1 and "s" or ""), { Font = T.bold, TextColor3 = T.gold })
		end
		local wcol = P.overWeight > 0 and T.red or T.green
		UI.Line(c, string.format("Purse %s    Camp: %d of %d days left    Weight %.1f / %d lbs", money(o.purse), P.camp.daysLeft, P.camp.daysTotal, P.weight, P.weightLimit), { TextSize = 14 })
		if P.overWeight > 0 then
			UI.Line(c, string.format("You're %.1f lbs over the limit! Burn fat with cardio or cut water in the sauna before fight night - missing weight costs stamina and %s.", P.overWeight, P.overWeight > 2 and "20% of your purse" or "no fine yet"), { TextColor3 = wcol, TextSize = 13 })
		end
		if #P.camp.log > 0 then
			UI.Line(c, "Camp so far: " .. table.concat(P.camp.log, ", "):sub(1, 220), { TextColor3 = T.sub, TextSize = 12 })
		end
		local ready = P.camp.daysLeft <= 0
		UI.Line(c, ready and "Camp is complete. It's FIGHT NIGHT." or "Train at the gym, eat, sleep: each night is a camp day. You can also fight early (fewer camp days).", { TextColor3 = ready and T.gold or T.sub, TextSize = 13 })
		local confirmEarly = false
		local fightBtn
		buttons(c, {
			function(row)
				fightBtn = UI.Button(row, ready and "FIGHT NIGHT (LIVE)" or "FIGHT NOW (EARLY)", { Size = UDim2.new(0, 210, 1, 0), BackgroundColor3 = T.red, TextSize = 14 }, function()
					if not ready and not confirmEarly then
						confirmEarly = true
						fightBtn.Text = "CONFIRM: FIGHT EARLY"
						return
					end
					local r = State.req("StartFight", "live")
					if r.ok then
						Hub.Close()
					else
						State.toast(r.err or "Can't start", T.red)
					end
				end)
			end,
			act("SIMULATE FIGHT", T.panel2, function()
				local r = State.req("StartFight", "sim")
				if r.ok then
					Hub.Close()
					if State.open.Result then
						State.open.Result(r)
					end
				else
					State.toast(r.err or "Can't simulate", T.red)
				end
			end, 170),
			act("SCOUT", T.panel2, function()
				showBoxer(o.oppId)
			end, 100),
		}, 40)
	else
		UI.Header(body, "FIGHT OFFERS")
		local res = State.req("GetOffers")
		if not res.ok then
			UI.Line(body, res.err or "No offers", { TextColor3 = T.red })
		else
			for i, o in ipairs(res.offers or {}) do
				local c = UI.Card(body)
				local special = o.kind ~= "Pro Fight" and o.kind ~= "Amateur Bout"
				UI.Line(c, string.format("%s  -  %d rounds  -  Purse %s  -  %s", o.kind:upper(), o.rounds, money(o.purse), o.venueName or ""), { Font = T.bold, TextColor3 = special and T.gold or T.sub })
				oppBlock(c, o.opp)
				UI.Line(c, "\"" .. (o.talk or "") .. "\"", { TextColor3 = Color3.fromRGB(255, 160, 160), TextSize = 14 })
				local stakes = stakesText(o)
				if #stakes > 0 then
					UI.Line(c, "On the line: " .. table.concat(stakes, " - "), { TextColor3 = T.gold, TextSize = 14 })
				end
				buttons(c, {
					act("ACCEPT FIGHT", T.gold, function()
						if result(State.req("AcceptOffer", i), "Fight signed! Training camp begins.") then
							Hub.Render()
						end
					end, 170),
					act("SCOUT", T.panel2, function()
						showBoxer(o.oppId)
					end, 100),
				})
			end
			UI.Line(body, "Offers refresh every week (7 days). Rivals with heat call you out for rematches and trilogies.", { TextColor3 = T.sub, TextSize = 13 })
		end
		local wc = UI.Card(body)
		UI.Line(wc, "WEIGHT CLASS: " .. P.className .. string.format("  (limit %d lbs, you weigh %.1f)", P.weightLimit, P.weight), { Font = T.bold })
		UI.Line(wc, "Moving divisions vacates any world titles you hold.", { TextColor3 = T.sub, TextSize = 13 })
		buttons(wc, {
			act("MOVE DOWN", T.panel2, function()
				result(State.req("ChangeWeightClass", -1), "Moved down a division.")
			end, 140),
			act("MOVE UP", T.panel2, function()
				result(State.req("ChangeWeightClass", 1), "Moved up a division.")
			end, 140),
		})
	end
	if #P.history > 0 then
		UI.Header(body, "RECENT FIGHTS")
		for i = 1, math.min(8, #P.history) do
			local h = P.history[i]
			local col = h.outcome == "win" and T.green or (h.outcome == "loss" and T.red or T.sub)
			UI.Line(body, string.format("Day %d  %s vs %s - %s R%d  (%s%s)", h.day or 0, h.outcome:upper(), h.opp, h.method, h.round, h.kind, h.venue and (", " .. h.venue) or ""), { TextColor3 = col, TextSize = 14 })
		end
	end
end

local AREAS = { "Boxing Area", "Weight Room", "Cardio Room", "Outdoors", "Pool", "Recovery Area" }
local function gainsText(a)
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local w = a.gains and a.gains[k]
		if w then
			table.insert(parts, Config.StatNames[k] .. (w >= 0.9 and " ++" or " +"))
		end
	end
	return table.concat(parts, ", ")
end

-- "Best A (87%) · 12 sessions · last 71%" for an activity's training record
local function recordText(r)
	if type(r) ~= "table" or (tonumber(r.sessions) or 0) <= 0 then
		return nil
	end
	local grade = Config.GradeFor(r.best)
	local rgb = Config.GradeInfo(grade).rgb
	return string.format('<font color="#%02X%02X%02X">Best %s (%d%%)</font>  ·  %d session%s  ·  last %d%%', rgb[1], rgb[2], rgb[3],
		grade, Config.QualityPct(r.best), r.sessions, r.sessions == 1 and "" or "s", Config.QualityPct(r.last))
end

R.Training = function(body, P)
	local c = P.condition
	local card = UI.Card(body)
	UI.Line(card, string.format("CONDITION  -  Day %d", P.day), { Font = T.bold, TextColor3 = T.gold })
	UI.StatRow(card, "Energy", c.energy, 100, c.energy < 25 and T.red or T.gold)
	UI.StatRow(card, "Hydration", c.hydration, 100, c.hydration < 30 and T.red or T.blue)
	UI.StatRow(card, "Nutrition", c.nutrition, 100, c.nutrition < 30 and T.red or T.green)
	UI.StatRow(card, "Fatigue", c.fatigue, 100, c.fatigue > 70 and T.red or (c.fatigue > 40 and T.orange or T.green))
	UI.Line(card, string.format("Sleep quality %d%%   Weight %.1f / %d lbs   Body fat %.1f%%", math.floor(c.sleepQ * 100), P.weight, P.weightLimit, P.body.fat or 14), { TextSize = 13, TextColor3 = T.sub })
	if c.fatigue > 70 then
		UI.Line(card, "OVERTRAINING: gains are cut in half and injury risk is high. Recover (ice bath, massage, stretching) or sleep.", { TextColor3 = T.red, TextSize = 13 })
	elseif c.fatigue > 40 then
		UI.Line(card, "Fatigue is building - gains are dropping. Mix in recovery.", { TextColor3 = T.orange, TextSize = 13 })
	end
	for _, inj in ipairs(c.injuries or {}) do
		UI.Line(card, string.format("INJURED: %s (%d days)", inj.name, inj.days), { TextColor3 = T.red, TextSize = 14, Font = T.semi })
	end
	local buffs = {}
	if c.buffs and c.buffs.gains then
		table.insert(buffs, string.format("+%d%% gains", c.buffs.gains * 100))
	end
	if c.buffs and c.buffs.muscle then
		table.insert(buffs, string.format("+%d%% muscle", c.buffs.muscle * 100))
	end
	if c.flexible then
		table.insert(buffs, "limber (lower injury risk)")
	end
	if #buffs > 0 then
		UI.Line(card, "Today: " .. table.concat(buffs, ", "), { TextColor3 = T.green, TextSize = 13 })
	end
	buttons(card, {
		act("NUTRITION BAR", T.panel2, function()
			Hub.Close()
			State.open.Nutrition()
		end, 150),
		act("DRINK WATER", T.panel2, function()
			State.open.Water()
		end, 130),
		act("SLEEP (END DAY)", T.gold, function()
			Hub.Close()
			State.open.Sleep()
		end, 160),
	})
	for _, area in ipairs(AREAS) do
		local list = {}
		for _, a in ipairs(Config.Activities) do
			if a.area == area then
				table.insert(list, a)
			end
		end
		if #list > 0 then
			UI.Header(body, area:upper())
			for _, a in ipairs(list) do
				local row = UI.Card(body)
				local st = Catalog.Stations[a.station]
				local lv = math.max(1, P.gym.levels[a.station] or 1)
				local lvName = st and st.levels[math.min(lv, #st.levels)].name or ""
				local cost = a.recovery and (a.price and (P.gym.levels.massage or 1) < 2 and money(a.price) or "free") or ("energy " .. (a.id == "Sparring" and "25-45" or tostring(a.energy)))
				UI.Line(row, string.format("%s   (%s)", a.name, cost), { Font = T.bold, TextSize = 15 })
				local detail = a.recovery and a.desc or (gainsText(a) .. "   -   " .. a.desc)
				UI.Line(row, detail .. (lvName ~= "" and ("   [" .. lvName .. "]") or ""), { TextSize = 12, TextColor3 = T.sub })
				local best = recordText(P.records and P.records[a.id])
				if best then
					UI.Line(row, best, { TextSize = 12, Font = T.semi, TextColor3 = T.sub, RichText = true })
				end
				buttons(row, {
					act("GO", T.gold, function()
						Hub.Close()
						if a.id == "Sparring" then
							State.open.Spar()
							return
						end
						local r = State.req("TravelTo", a.station)
						if r.ok then
							task.wait(0.35)
							State.open.Activity(a.id)
						else
							State.toast(r.err or "Can't go there", T.red)
						end
					end, 90),
				}, 30)
			end
		end
	end
end

R.Body = function(body, P)
	local c = UI.Card(body)
	UI.Line(c, "PHYSIQUE: " .. P.physique:upper(), { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	UI.Line(c, string.format("Height %s  -  Reach %d in  -  Weight %.1f lbs  -  Body fat %.1f%%  -  Frame: %s",
		Config.HeightText(P.physical.height), P.physical.reach, P.weight, P.body.fat or 14, P.appearance.body.frame), { TextSize = 14 })
	local frame = Config.FindById(Config.BodyTypes, P.appearance.body.frame) or Config.BodyTypes[2]
	local cap = 100 * frame.potential
	local m = UI.Card(body)
	UI.Line(m, string.format("MUSCLE DEVELOPMENT  (your frame's potential: %d)", math.floor(cap)), { Font = T.bold, TextColor3 = T.gold })
	for _, k in ipairs(Config.MuscleKeys) do
		UI.StatRow(m, Config.MuscleNames[k], P.body[k] or 0, cap, Color3.fromRGB(150, 200, 255), string.format("%.1f", P.body[k] or 0))
	end
	UI.StatRow(m, "Body fat", (P.body.fat or 14) - 6, 24, T.orange, string.format("%.1f%%", P.body.fat or 14))
	UI.Line(body, "Your body changes as you train: bench, dumbbells, deadlifts, squats and pull-ups build chest, arms, shoulders, back and legs. Running, swimming, rope and bike burn fat. Muscle adds punching power and weight; fat costs stamina and makes weight harder to make. Bulk up and you may need to move up a division.", { TextColor3 = T.sub, TextSize = 13 })
end

R.Stats = function(body, P)
	local c = UI.Card(body)
	UI.Line(c, string.format("%s \"%s\"  -  OVERALL %d", P.identity.name, P.identity.nickname, P.overall), { Font = T.bold, TextSize = 20, TextColor3 = T.gold })
	UI.Line(c, string.format("%s  -  %s specialty  -  %d training sessions", P.style, P.specialty, P.sessions or 0), { TextSize = 14, TextColor3 = T.sub })
	local s = UI.Card(body)
	UI.Line(s, "CORE STATS", { Font = T.bold, TextColor3 = T.gold })
	for _, k in ipairs(Config.StatKeys) do
		local v = P.stats[k] or 0
		UI.StatRow(s, Config.StatNames[k], v, 99, T.green, string.format("%.2f", v))
	end
	local m = UI.Card(body)
	UI.Line(m, "MENTAL", { Font = T.bold, TextColor3 = T.gold })
	for _, k in ipairs(Config.MentalKeys) do
		UI.StatRow(m, k, P.mental[k] or 0, 100, T.blue)
	end
	UI.Line(body, "Confidence boosts power, Focus improves accuracy, Composure helps you beat the count, Discipline speeds up training, Aggression adds pop. Stats gain less as they get higher - and age catches up with everyone after 30.", { TextColor3 = T.sub, TextSize = 13 })
end

R.Gym = function(body, P)
	UI.Line(body, "Money " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 18 })
	UI.Line(body, "Better equipment = faster gains (and it looks the part). Equipment wears down with use: below 30% condition gains drop - repair it.", { TextColor3 = T.sub, TextSize = 13 })
	local lastArea
	for _, id in ipairs(Catalog.StationOrder) do
		local st = Catalog.Stations[id]
		if st.area ~= lastArea then
			lastArea = st.area
			UI.Header(body, st.area:upper())
		end
		local lv = math.max(1, P.gym.levels[id] or 1)
		local cur = st.levels[math.min(lv, #st.levels)]
		local nxt = st.levels[lv + 1]
		local cond = P.gym.cond[id] or 100
		local c = UI.Card(body)
		UI.Line(c, string.format("%s  -  Lv.%d %s  (x%.2f gains)", st.name, lv, cur.name, cur.mult), { Font = T.bold, TextSize = 15, TextColor3 = cur.elite and T.gold or T.text })
		UI.StatRow(c, "Condition", cond, 100, cond < 30 and T.red or (cond < 60 and T.orange or T.green))
		local list = {}
		if cond < 99 and #st.levels > 0 then
			local cost = math.floor(60 + (cur.cost or 0) * 0.04)
			table.insert(list, act("REPAIR " .. money(cost), T.panel2, function()
				result(State.req("RepairStation", id), st.name .. " repaired.")
			end, 160))
		end
		if nxt then
			local locked = nxt.requiresTier and P.tier < nxt.requiresTier
			UI.Line(c, string.format("Next: %s - %s  (x%.2f)%s", nxt.name, nxt.desc, nxt.mult, locked and "  [World Champions only]" or ""), { TextSize = 13, TextColor3 = locked and T.sub or T.text })
			table.insert(list, act(locked and "LOCKED" or ("UPGRADE " .. money(nxt.cost)), locked and T.panel2 or (P.money >= nxt.cost and T.gold or Color3.fromRGB(70, 40, 40)), function()
				if locked then
					return
				end
				result(State.req("UpgradeStation", id), "Upgraded: " .. nxt.name)
			end, 190))
		else
			UI.Line(c, "Top level reached.", { TextSize = 13, TextColor3 = T.gold })
		end
		if #list > 0 then
			buttons(c, list, 32)
		end
	end
end

local GEAR_KINDS = {
	{ kind = "gloves", title = "GLOVES", list = Catalog.Gloves },
	{ kind = "shoes", title = "BOXING SHOES", list = Catalog.Shoes },
	{ kind = "wraps", title = "HAND WRAPS", list = Catalog.Wraps },
	{ kind = "mouthguard", title = "MOUTHGUARDS", list = Catalog.Mouthguards },
	{ kind = "robe", title = "ROBES", list = Catalog.Robes },
}

local function gearStats(kind, item)
	local p = {}
	if kind == "gloves" then
		table.insert(p, string.format("power %+d%%", item.power * 100))
		table.insert(p, string.format("speed %+d%%", item.speed * 100))
		table.insert(p, string.format("durability x%.1f", item.durability))
	elseif kind == "shoes" then
		table.insert(p, string.format("footwork %+d%%", item.footwork * 100))
		table.insert(p, string.format("durability x%.1f", item.durability))
	elseif kind == "wraps" then
		table.insert(p, string.format("hand injury risk x%.2f", item.injury))
	elseif kind == "mouthguard" then
		table.insert(p, string.format("chin %+d", item.chin))
	elseif kind == "robe" then
		table.insert(p, string.format("popularity +%d", item.pop))
	end
	return table.concat(p, "  -  ")
end

R.Gear = function(body, P)
	UI.Line(body, "Money " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 18 })
	buttons(body, {
		act("OPEN LOCKER ROOM (customize)", T.gold, function()
			Hub.Close()
			State.open.Locker()
		end, 280),
	})
	for _, g in ipairs(GEAR_KINDS) do
		UI.Header(body, g.title)
		local eq = P.gear.equipped[g.kind]
		local cond = P.gear.cond[g.kind .. ":" .. tostring(eq)]
		if cond and g.kind ~= "mouthguard" and g.kind ~= "robe" then
			local item = Catalog.Find(g.list, eq)
			local c = UI.Card(body)
			UI.StatRow(c, "Equipped condition", cond, 100, cond < 30 and T.red or (cond < 60 and T.orange or T.green))
			if cond < 40 then
				UI.Line(c, g.kind == "gloves" and "Your gloves are cracking - less power and more hand injuries." or (g.kind == "shoes" and "Worn-out shoes slow your footwork." or "Dirty, loose wraps - more hand injuries."), { TextColor3 = T.red, TextSize = 13 })
			end
			if cond < 99 and item then
				local cost = math.floor(25 + (item.price or 0) * (g.kind == "gloves" and 0.06 or 0.08))
				buttons(c, {
					act("REPAIR " .. money(cost), T.panel2, function()
						result(State.req("RepairGear", g.kind), "Repaired.")
					end, 170),
				}, 30)
			end
		end
		for _, item in ipairs(g.list) do
			local owned = P.gear.owned[g.kind] and P.gear.owned[g.kind][item.id]
			local equipped = eq == item.id
			local locked = item.requiresTier and P.tier < item.requiresTier
			local c = UI.Card(body, { stroke = equipped and T.gold or nil })
			UI.Line(c, item.name .. (item.tier and ("  (" .. item.tier .. ")") or "") .. (equipped and "  - EQUIPPED" or ""), { Font = T.bold, TextSize = 15, TextColor3 = equipped and T.gold or T.text })
			UI.Line(c, gearStats(g.kind, item), { TextSize = 13, TextColor3 = T.sub })
			local list = {}
			if owned and not equipped then
				table.insert(list, act("EQUIP", T.panel2, function()
					result(State.req("Equip", g.kind, item.id))
				end, 110))
			end
			if not owned or (g.kind ~= "mouthguard" and g.kind ~= "robe" and item.price > 0) then
				local label = locked and "WORLD CHAMPS ONLY" or ((owned and "BUY NEW " or "BUY ") .. money(item.price))
				if not owned or (cond and cond < 50 and equipped) then
					table.insert(list, act(label, locked and T.panel2 or (P.money >= item.price and T.gold or Color3.fromRGB(70, 40, 40)), function()
						if locked then
							return
						end
						result(State.req("BuyGear", g.kind, item.id), "Bought " .. item.name .. ".")
					end, 200))
				end
			end
			if #list > 0 then
				buttons(c, list, 30)
			end
		end
	end
end

R.Coaches = function(body, P)
	UI.Line(body, string.format("Money %s    Team salary per fight: %s", money(P.money), money(P.salary or 0)), { Font = T.bold, TextColor3 = T.green, TextSize = 16 })
	UI.Line(body, "Each coach boosts the stats of their specialty in training. Salaries come out of every purse. An elite Ring IQ or Defense coach also reads your opponents between rounds.", { TextColor3 = T.sub, TextSize = 13 })
	for _, spec in ipairs(Catalog.CoachSpecialties) do
		local tier = P.coaches[spec.id] or 0
		local c = UI.Card(body, { stroke = tier > 0 and T.gold or nil })
		local statNames = {}
		for _, k in ipairs(spec.stats) do
			table.insert(statNames, Config.StatNames[k])
		end
		UI.Line(c, string.format("%s COACH  -  %s", (spec.name or spec.id):upper(), table.concat(statNames, ", ")), { Font = T.bold, TextColor3 = T.gold })
		if tier > 0 then
			local def = Catalog.CoachTiers[tier]
			UI.Line(c, string.format("Hired: %s (%s, +%d%% gains, %s per fight)", Catalog.CoachNames[spec.id][tier], def.name, def.boost * 100, money(def.salary)), { TextSize = 14 })
		else
			UI.Line(c, "No coach hired.", { TextSize = 14, TextColor3 = T.sub })
		end
		local list = {}
		for t, def in ipairs(Catalog.CoachTiers) do
			if t > tier then
				table.insert(list, act(string.format("%s %s", def.name:upper(), money(def.cost)), P.money >= def.cost and T.gold or Color3.fromRGB(70, 40, 40), function()
					result(State.req("HireCoach", spec.id, t), "Hired " .. Catalog.CoachNames[spec.id][t] .. "!")
				end, 150))
			end
		end
		if tier > 0 then
			table.insert(list, act("RELEASE", T.red, function()
				result(State.req("FireCoach", spec.id), "Coach released.")
			end, 100))
		end
		buttons(c, list, 32)
	end
end

local rankClass, rankOrg = nil, "WBA"
R.Rankings = function(body, P)
	rankClass = rankClass or P.physical.weightClass
	local top = UI.Row(body, 38)
	UI.Button(top, "<", { Size = UDim2.fromOffset(36, 34) }, function()
		rankClass = math.max(1, rankClass - 1)
		Hub.Render()
	end)
	UI.Text(top, Config.WeightClasses[rankClass].name, { Font = T.bold, Size = UDim2.fromOffset(170, 34), TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.None })
	UI.Button(top, ">", { Size = UDim2.fromOffset(36, 34) }, function()
		rankClass = math.min(#Config.WeightClasses, rankClass + 1)
		Hub.Render()
	end)
	for _, org in ipairs(Config.Orgs) do
		UI.Button(top, org, { Size = UDim2.fromOffset(66, 34), BackgroundColor3 = org == rankOrg and T.gold or T.panel2, TextColor3 = org == rankOrg and T.bg or T.text }, function()
			rankOrg = org
			Hub.Render()
		end)
	end
	local res = State.req("GetRankings", rankClass, rankOrg)
	if not res.ok then
		return
	end
	if P.tier < 2 then
		UI.Line(body, "You're an amateur - win 4 amateur bouts to turn pro and enter the world rankings.", { TextColor3 = T.sub, TextSize = 14 })
	end
	for _, e in ipairs(res.list) do
		local b = UI.Button(body, "", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = e.isPlayer and Color3.fromRGB(70, 55, 15) or T.panel }, function()
			if not e.isPlayer then
				showBoxer(e.id)
			end
		end)
		local rk = e.rank == "C" and "CHAMP" or ("#" .. e.rank)
		UI.Text(b, rk, { Font = T.bold, TextColor3 = e.rank == "C" and T.gold or T.text, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 70, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(b, string.format("%s \"%s\"", e.name, e.nick), { Position = UDim2.fromOffset(84, 0), Size = UDim2.new(0.5, 0, 1, 0), TextSize = 15, AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(b, string.format("%s   OVR %d   %s", rec(e.record), e.overall, e.nat), { Position = UDim2.new(0.55, 0, 0, 0), Size = UDim2.new(0.45, -10, 1, 0), TextColor3 = T.sub, TextSize = 13, AutomaticSize = Enum.AutomaticSize.None })
	end
end

R.Rivals = function(body, P)
	local res = State.req("GetRivals")
	if not res.ok or #res.list == 0 then
		UI.Line(body, "No rivals yet. Every opponent remembers you - rematches, revenge missions and trilogies appear as offers when rivalries heat up.", { TextColor3 = T.sub })
		return
	end
	for _, r in ipairs(res.list) do
		local c = UI.Card(body)
		UI.Line(c, string.format("%s \"%s\"%s", r.name, r.nick, r.retired and "  (retired)" or ""), { Font = T.bold })
		UI.Line(c, string.format("Head-to-head: you %d - %d them, %d draws   -   %s   -   OVR %d", r.h2h.w, r.h2h.l, r.h2h.d, r.personality, r.overall), { TextSize = 14, TextColor3 = T.sub })
		UI.StatRow(c, "Rivalry heat", r.heat, 100, T.red)
		local total = r.h2h.w + r.h2h.l + r.h2h.d
		local status = r.heat >= 70 and "HEATED RIVALRY" or (r.heat >= 40 and "Rivalry" or "Old foe")
		if total == 2 and r.heat >= 40 then
			status = status .. " - TRILOGY BREWING"
		end
		UI.Line(c, status, { TextColor3 = T.red, TextSize = 13 })
	end
end

R.Shop = function(body, P)
	UI.Line(body, "Money: " .. money(P.money), { Font = T.bold, TextColor3 = T.green, TextSize = 20 })
	if P.studio then
		buttons(body, {
			act("STUDIO TEST: +$1,000,000", T.panel2, function()
				result(State.req("DebugMoney"), "Test money added (Studio only).")
			end, 260),
		})
	end
	local lastCat
	for _, item in ipairs(Catalog.Shop) do
		if item.cat ~= lastCat then
			lastCat = item.cat
			UI.Header(body, item.cat:upper())
		end
		local owned = P.owned[item.id]
		local locked = item.requiresTier and P.tier < item.requiresTier
		local c = UI.Card(body, { stroke = owned and T.gold or nil })
		UI.Line(c, item.name, { Font = T.bold })
		UI.Line(c, item.desc, { TextSize = 13, TextColor3 = T.sub })
		buttons(c, {
			act(owned and "OWNED" or (locked and "WORLD CHAMPS ONLY" or money(item.price)), owned and T.panel2 or (locked and T.panel2 or (P.money >= item.price and T.gold or Color3.fromRGB(70, 40, 40))), function()
				if owned or locked then
					return
				end
				result(State.req("Buy", item.id), "Purchased: " .. item.name)
			end, 200),
		}, 32)
	end
end

local function legacyBody(body, lg, past)
	local c = UI.Card(body)
	UI.Line(c, "LEGACY SCORE  " .. lg.score, { Font = T.bold, TextSize = 26, TextColor3 = T.gold })
	UI.Line(c, lg.hallOfFame and "HALL OF FAME: INDUCTED" or string.format("Hall of Fame needs %d legacy", Config.HallOfFameScore), { Font = T.bold, TextColor3 = lg.hallOfFame and T.gold or T.sub })
	UI.Line(c, "GOAT RANKING: #" .. lg.goatRank .. " of all time", { Font = T.bold, TextSize = 20 })
	for _, p in ipairs(lg.parts) do
		if p[2] ~= 0 then
			UI.Line(c, string.format("%s: %s%d", p[1], p[2] > 0 and "+" or "", math.floor(p[2])), { TextSize = 14, TextColor3 = T.sub })
		end
	end
	local g = UI.Card(body)
	UI.Line(g, "ALL-TIME GREATS", { Font = T.bold, TextColor3 = T.gold })
	for i, e in ipairs(lg.goatList) do
		if i <= 12 or e.you then
			UI.Line(g, string.format("%d. %s  (%d)", i, e.name, e.score), { TextSize = 14, TextColor3 = e.you and T.gold or T.text, Font = e.you and T.bold or T.font })
		end
	end
	if #lg.greatest > 0 then
		local f = UI.Card(body)
		UI.Line(f, "GREATEST FIGHTS", { Font = T.bold, TextColor3 = T.gold })
		for _, h in ipairs(lg.greatest) do
			UI.Line(f, string.format("%.1f/10  %s vs %s - %s R%d (%s)", h.rating, h.outcome:upper(), h.opp, h.method, h.round, h.kind), { TextSize = 14 })
		end
	end
	if past and #past > 0 then
		local pc = UI.Card(body)
		UI.Line(pc, "PAST CAREERS", { Font = T.bold, TextColor3 = T.gold })
		for _, x in ipairs(past) do
			UI.Line(pc, string.format("%s \"%s\"  %s  -  %d titles  -  Legacy %d  -  GOAT #%d%s", x.name, x.nick, rec(x.record), x.titles, x.score, x.goatRank, x.hof and "  - HOF" or ""), { TextSize = 13 })
		end
	end
end
Hub.LegacyBody = legacyBody

R.Legacy = function(body, P)
	local res = State.req("GetLegacy")
	if not res.ok then
		return
	end
	legacyBody(body, res.legacy, res.pastCareers)
	local c = UI.Card(body)
	UI.Line(c, "Retiring ends this career for good: Hall of Fame induction, career stats, greatest fights and your final GOAT ranking.", { TextColor3 = T.sub, TextSize = 14 })
	local confirm = false
	local b
	b = UI.Button(c, "RETIRE", { Size = UDim2.new(0, 220, 0, 40), BackgroundColor3 = T.red }, function()
		if not confirm then
			confirm = true
			b.Text = "CONFIRM RETIREMENT"
			return
		end
		local r = State.req("Retire")
		if r.ok then
			Hub.Close()
		else
			State.toast(r.err or "Can't retire now", T.red)
		end
	end)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function Hub.Render()
	local P = State.P
	if not (shade and shade.Parent and P and P.created) then
		return
	end
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == tab and T.gold or T.panel2
		b.TextColor3 = name == tab and T.bg or T.text
	end
	local y = content.CanvasPosition
	UI.Clear(content)
	local ok, err = pcall(R[tab], content, P)
	if not ok then
		warn("[Hub]", tab, err)
	end
	task.defer(function()
		if content and content.Parent then
			content.CanvasPosition = y
		end
	end)
end

function Hub.Close()
	State.windows.Hub = nil
	if shade then
		shade:Destroy()
		shade = nil
	end
end

function Hub.IsOpen()
	return shade ~= nil and shade.Parent ~= nil
end

function Hub.Open(which)
	local P = State.P
	if State.inFight() or not P or not P.created or P.retired then
		return
	end
	if which then
		tab = which
	end
	if Hub.IsOpen() then
		Hub.Render()
		return
	end
	State.closeAll("Hub")
	local body
	shade, win, body = UI.Window(State.gui, "Hub", 980, 660, "CAREER HUB", { onClose = Hub.Close, scroll = false })
	State.windows.Hub = Hub.Close
	local side = UI.Scroll(body, { Size = UDim2.new(0, 140, 1, 0) })
	UI.List(side, 5)
	tabButtons = {}
	for i, name in ipairs(TABS) do
		tabButtons[name] = UI.Button(side, name, { Size = UDim2.new(1, -8, 0, 36), LayoutOrder = i, TextSize = 14 }, function()
			tab = name
			content.CanvasPosition = Vector2.zero
			Hub.Render()
		end)
	end
	content = UI.Scroll(body, { Position = UDim2.new(0, 150, 0, 0), Size = UDim2.new(1, -150, 1, 0) })
	UI.List(content, 8)
	UI.Pad(content, 2, 4)
	Hub.Render()
end

function Hub.Toggle()
	if Hub.IsOpen() then
		Hub.Close()
	else
		Hub.Open()
	end
end

State.open.Hub = Hub.Open
return Hub
