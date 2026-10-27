--!nocheck
-- tools/sim/careersim.luau: 100 in-game days of training by three kinds of player, on the REAL server
-- Training / Career code (tools/sim/trainhost.luau), headless. Every 21 days the boxer takes a fight with a
-- 5-day camp (the fight itself is not boxed: the fight-night modifiers are read, then the post-fight
-- suspension passes). Players:
--   planner  sets the Balanced Week plan; 3-4 varied sessions a day led by the day's focus block, the camp's
--            build / peak / taper, ice bath or stretching after hard days, balanced meals and a protein shake
--   grinder  the Heavy Bag until the energy runs out, every day, fast food, no recovery
--   casual   five days a week, two random drills, fast food, a bit sloppier (quality ~0.95)
-- Quality per session is drawn around the player's skill (an overloaded drill is a little harder to ace).
--
--   lune run tools/sim/careersim.luau                       # the current code
--   lune run tools/sim/careersim.luau --src /tmp/old/src    # another tree (e.g. git archive <rev> src)
--   lune run tools/sim/careersim.luau --days 100 --csv out.csv --seeds 3
local TH = require("./trainhost")
local process = require("@lune/process")
local fs = require("@lune/fs")

local args = process.args
local function arg(name, default)
	local i = table.find(args, name)
	return i and args[i + 1] or default
end
local SRC = arg("--src", nil)
local DAYS = tonumber(arg("--days", "100"))
local CSV = arg("--csv", nil)
local SEEDS = tonumber(arg("--seeds", "3"))
local FIGHT_EVERY, CAMP_DAYS, SUSPENSION = 21, 5, 7

local function run(kind, seed)
	local T = TH.new({ src = SRC, seed = seed })
	local Training, Config, TP = T.Training, T.Config, T.TP
	local P = T.profile(22)
	Training.Migrate(P)
	local rng = T.H.globals.Random.new(seed * 31 + #kind)
	local function q(skill, actId)
		local ov = 0
		if Training.Mastery then
			ov = select(3, Training.Mastery(P, actId))
		end
		return math.clamp(skill + rng:NextNumber(-0.12, 0.12) - 0.03 * ov, 0.4, 1.5)
	end
	local acts = {}
	for _, a in ipairs(Config.Activities) do
		acts[a.id] = a
	end
	local train = {}
	for _, a in ipairs(Config.Activities) do
		if not a.recovery and a.id ~= "Sparring" and not a.requires then
			table.insert(train, a.id)
		end
	end
	local function session(id, skill)
		local act = acts[id]
		if not act or not Training.CanDo(P, act) then
			return false
		end
		local qq = q(skill, id)
		if act.recovery then
			Training.Recover(P, act, qq)
		else
			Training.Perform(P, act, qq)
		end
		Training.Record(P, id, qq, nil)
		return true
	end
	local function eat(id)
		Training.Eat(P, id)
	end
	local function drink()
		if P.condition.hydration < 45 then
			eat("Water")
		end
	end
	if kind == "planner" and Training.SetPlan then
		Training.SetPlan(P, "balanced")
	end
	local curve = { [0] = Config.Overall(P.stats) }
	local fights = {}
	local nextFight = FIGHT_EVERY
	local campDay = 0
	local d = 0
	while d < DAYS do
		P.money = 1e6
		-- a fight is booked CAMP_DAYS before its night
		if d == nextFight - CAMP_DAYS and not P.camp then
			local cls = P.world.classes[P.physical.weightClass]
			P.camp = { offer = { oppId = cls[1], kind = "Pro Fight", opp = { name = "Opponent" } }, daysLeft = CAMP_DAYS, daysTotal = CAMP_DAYS, log = {} }
		end
		local phase = (TP and P.camp) and TP.CampPhase(P.camp) or nil
		if kind == "planner" then
			eat("Balanced")
			local focus = Training.TodayFocus and Training.TodayFocus(P) or nil
			local rest = (not P.camp) and focus and focus[1] == "rest"
			if rest or phase == "taper" then
				if phase == "taper" then
					-- one sharp session, then recovery
					session((focus and TP.FocusById[focus[1]].acts[1]) or "MittWork", 1.18)
				end
				session("Stretch", 1.1)
				session("IceBath", 1.1)
			else
				local wanted = phase == "peak" and 2 or (phase == "build" and 3 or 4)
				local done, used = 0, {}
				local pool = {}
				for _, f in ipairs(focus or {}) do
					for _, id in ipairs(TP and TP.FocusById[f] and TP.FocusById[f].acts or {}) do
						table.insert(pool, id)
					end
				end
				-- then the weakest stats' drills, then anything not done today
				local order = {}
				for _, k in ipairs(Config.StatKeys) do
					table.insert(order, k)
				end
				table.sort(order, function(a, b)
					return P.stats[a] < P.stats[b]
				end)
				for _, k in ipairs(order) do
					for _, id in ipairs(train) do
						if (acts[id].gains or {})[k] and (acts[id].gains[k] or 0) >= 0.5 then
							table.insert(pool, id)
						end
					end
				end
				for _, id in ipairs(train) do
					table.insert(pool, id)
				end
				for _, id in ipairs(pool) do
					if done >= wanted then
						break
					end
					if not used[id] and acts[id] and acts[id].id ~= "Sauna" then
						-- skip a drill whose main group is very sore
						local sore = 0
						for g, w in pairs(acts[id].muscle or {}) do
							if w >= 0.5 then
								sore = math.max(sore, P.condition.sore[g] or 0)
							end
						end
						if sore < 0.55 and session(id, 1.18) then
							used[id] = true
							done += 1
							drink()
							if done == 2 then
								eat("Protein")
							end
						end
					end
				end
				if P.condition.fatigue > 45 then
					session("IceBath", 1.1)
				end
				session("Stretch", 1.1)
			end
			eat("Balanced")
			drink()
		elseif kind == "grinder" then
			for _ = 1, 8 do
				drink()
				if P.condition.nutrition < 40 then
					eat("FastFood")
				end
				if not session("HeavyBag", 1.18) then
					break
				end
			end
			eat("FastFood")
			drink()
		else
			-- casual: weekends off
			if d % 7 < 5 then
				eat("FastFood")
				for _ = 1, 2 do
					drink()
					session(train[rng:NextInteger(1, #train)], 0.95)
				end
				drink()
			end
		end
		local res = Training.Sleep(P)
		d += 1
		if P.camp and (P.camp.daysLeft or 0) <= 0 then
			-- fight night: what the camp brings into the ring
			local mods = Training.FightModifiers(P)
			table.insert(fights, { day = d, readiness = mods.readiness and mods.readiness.score or nil, label = mods.readiness and mods.readiness.label or "-",
				stamina = mods.staminaMul, notes = table.concat(mods.notes, "; ") })
			P.camp = nil
			Training.PassDays(P, SUSPENSION)
			d += SUSPENSION
			nextFight = d + FIGHT_EVERY
		end
		curve[math.min(d, DAYS)] = Config.Overall(P.stats)
	end
	local muscle = 0
	for _, k in ipairs(Config.MuscleKeys) do
		muscle += P.body[k] or 0
	end
	return curve, fights, { muscle = muscle, stats = table.clone(P.stats), sessions = P.sessions, money = P.money, pop = P.popularity,
		streak = type(P.train) == "table" and type(P.train.goals) == "table" and P.train.goals.best or 0 }
end

local KINDS = { "planner", "grinder", "casual" }
local out = {}
local rows = {}
for _, kind in ipairs(KINDS) do
	local sum, fightsAll, ends = {}, {}, {}
	for s = 1, SEEDS do
		local curve, fights, fin = run(kind, s)
		local last = curve[0]
		for day = 0, DAYS do
			last = curve[day] or last
			sum[day] = (sum[day] or 0) + last / SEEDS
		end
		for _, f in ipairs(fights) do
			table.insert(fightsAll, f)
		end
		table.insert(ends, fin)
	end
	out[kind] = { curve = sum, fights = fightsAll, ends = ends }
end
print(string.format("career simulation (%s), %d days, %d seeds: average OVERALL", SRC or "current src", DAYS, SEEDS))
local head = { "day" }
for _, k in ipairs(KINDS) do
	table.insert(head, k)
end
print(table.concat(head, "\t"))
local csv = { table.concat(head, ",") }
for day = 0, DAYS, 10 do
	local row = { tostring(day) }
	for _, k in ipairs(KINDS) do
		table.insert(row, string.format("%.2f", out[k].curve[day]))
	end
	print(table.concat(row, "\t"))
end
for day = 0, DAYS do
	local row = { tostring(day) }
	for _, k in ipairs(KINDS) do
		table.insert(row, string.format("%.3f", out[k].curve[day]))
	end
	table.insert(csv, table.concat(row, ","))
end
for _, k in ipairs(KINDS) do
	local labels = {}
	local rsum, rn = 0, 0
	for _, f in ipairs(out[k].fights) do
		labels[f.label] = (labels[f.label] or 0) + 1
		if f.readiness then
			rsum += f.readiness
			rn += 1
		end
	end
	local parts = {}
	for l, n in pairs(labels) do
		table.insert(parts, l .. " x" .. n)
	end
	table.sort(parts)
	local m, st, ss = 0, 0, 0
	for _, e in ipairs(out[k].ends) do
		m += e.muscle / SEEDS
		st += e.streak / SEEDS
		ss += e.sessions / SEEDS
	end
	print(string.format("%-8s fights: %s  readiness avg %s  | muscle total %.0f  sessions %.0f  best goal streak %.1f", k, table.concat(parts, ", "),
		rn > 0 and string.format("%.0f", rsum / rn) or "-", m, ss, st))
end
if CSV then
	fs.writeFile(CSV, table.concat(csv, "\n") .. "\n")
end
