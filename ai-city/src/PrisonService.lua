-- PrisonService (ModuleScript) — ServerScriptService.Modules.PrisonService
-- Life inside AI City State Prison (the building is made by Prison.lua).
--
-- About twenty inmates in orange jumpsuits live there, two to a cell, each with
-- a name, a crime and a sentence. They keep the prison's daily schedule:
--   22:00-6:00  lights out: asleep in their bunks, the cell doors locked
--   6:00        the doors slide open; wake up, stretch, wash
--   7, 12, 17   chow (an hour and a half): a line at the serving counter,
--               then the mess tables
--   8:30-12, 16 yard time: hoops, the weight pit, laps around the track,
--               cards and chess at the picnic tables, hanging out by the wall
--   13:30-16    work detail: mopping the hall, sweeping the yard, the kitchen
--   18:30-21    rec time: TV, chess in the hall, reading in their cells
--   21:00       count time: "Back to your cells!"; the doors slam at 21:30
-- They talk to each other, size up anyone new ("Fresh fish!"), and now and
-- then a fight breaks out in the yard until the guards break it up and send
-- both of them to their cells. Guards walk the hall and the yard, one sits at
-- the desk by the yard door, one mans the gate, and there's a guard in every
-- tower; at night the searchlights sweep the yard.
--
-- When YOU are arrested (CrimeService) you're booked in here: your own cell,
-- your sentence on the clock, and the same schedule as everyone else. When the
-- doors are locked you stay in your cell; when they're open you can go to the
-- mess hall and the yard, but not past the walls. Street criminals the police
-- catch (StreetCrimeService) serve their time here too.
--
-- Config.PRISON = false turns it off; Config.PRISON_INMATES (default 20).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PrisonService = {}
local S, P

local inmates = {} -- every inmate: { Brain, Name, Crime, Years, Cell, Bunk, ... }
local byBrain = {}
local guards = {}
local jailedPlayers = {} -- [player] = { Cell }
local doorsOpen = nil
local lastPeriod
local nextFight = 0
local nextChat = 0

local FIRST = { "Marcus", "Tony", "Dre", "Big Lou", "Sal", "Ray", "Tyrell", "Vic", "Manny", "Duke", "Eddie", "Tre", "Jimmy", "Hector", "Ozzie", "Frank", "Deshawn", "Carlos", "Mikey", "Ronnie", "Bishop", "Shorty", "Luis", "Terrence", "Gus" }
local LAST = { "Brooks", "Rivera", "Kowalski", "Jenkins", "Moreno", "O'Neil", "Price", "Vance", "Castillo", "Doyle", "Hayes", "Romano", "Grant", "Pierce", "Ortiz" }
local CRIMES = { "armed robbery", "car theft", "burglary", "running a card game", "assault", "breaking and entering", "tax fraud", "smuggling", "a bank job", "arson", "pickpocketing", "vandalism", "forgery", "a bar fight", "shoplifting (a lot)" }
local GUARD_NAMES = { "Officer Hale", "Officer Diaz", "Officer Brandt", "Officer Kim", "Officer Moss", "Officer Pruitt", "Sgt. Walker", "Officer Tate", "Officer Ruiz" }

local CHAT = {
	{ "How long you got left?", "Two years, three months, eleven days. Not that I'm counting." },
	{ "Chow's garbage today.", "Chow's garbage every day." },
	{ "I didn't even do it, man.", "Yeah. Nobody in here did." },
	{ "You hear about the new guy?", "Heard he's in for tax fraud. Tax fraud!" },
	{ "When I get out I'm opening a bakery.", "You? A bakery?" },
	{ "My lawyer says I got a shot at parole.", "Your lawyer said that last year." },
	{ "Spot me on the bench?", "Yeah, go." },
	{ "You got any stamps?", "What you gonna trade?" },
	{ "My kid's got a birthday next week.", "Call 'em. It'll mean a lot." },
	{ "Guard's in a mood today.", "Keep your head down." },
	{ "Bet you two soups I make this shot.", "You're on." },
	{ "Check. Your move.", "Hmm..." },
}
local FRESH = { "Fresh fish!", "Look what the bus dragged in.", "What you in for?", "Keep your head down, new guy.", "Don't sit at my table.", "Welcome to the neighborhood." }
local VISITOR = { "You visiting somebody?", "Got a smoke?", "Tell my mom I said hi.", "Nice shoes. Real nice." }
local FIGHT_LINES = {
	{ "You took my spot, man!", "Your spot? Says who?" },
	{ "You owe me two soups!", "I don't owe you nothing!" },
	{ "Stop looking at me!", "Or what?!" },
	{ "You cheated at cards!", "Prove it!" },
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function W(v)
	return P.World(v)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function hour()
	return S.City.Hour()
end

--------------------------------------------------------------------------------
-- The schedule
--------------------------------------------------------------------------------
local function periodAt(h)
	if h >= 22 or h < 6 then
		return "night"
	elseif h < 7 then
		return "wake"
	elseif h < 8.5 or (h >= 12 and h < 13.5) or (h >= 17 and h < 18.5) then
		return "meal"
	elseif h < 12 or (h >= 16 and h < 17) then
		return "yard"
	elseif h < 16 then
		return "work"
	elseif h < 21 then
		return "rec"
	end
	return "lockup"
end
PrisonService.PeriodAt = periodAt

local function doorsShouldBeOpen(h)
	return h >= 6 and h < 21.5
end

local PERIOD_LABEL = {
	night = "💤 Lights out", wake = "⏰ Wake-up", meal = "🍲 Chow time", yard = "🏀 Yard time",
	work = "🧽 Work detail", rec = "📺 Rec time", lockup = "🔔 Count time",
}

--------------------------------------------------------------------------------
-- Cells and spots
--------------------------------------------------------------------------------
local function setDoors(open)
	if doorsOpen == open then
		return
	end
	doorsOpen = open
	for _, door in ipairs(P.Doors) do
		door.Open = open
		for _, d in ipairs(door.Parts) do
			d.Part.CFrame = if open then d.Opened else d.Closed
			if d.Part.Name == "CellDoor" then
				d.Part.CanCollide = not open
			end
		end
	end
end

local function taken(spot)
	return spot.TakenBy ~= nil and spot.TakenBy.Brain and spot.TakenBy.Brain.Model.Parent ~= nil
end

local function freeSpot(list, rng)
	local free = {}
	for _, s in ipairs(list) do
		if not taken(s) then
			table.insert(free, s)
		end
	end
	return if #free > 0 then free[math.random(1, #free)] else nil
end

local function cellOccupants(cell)
	local n = 0
	for _, i in ipairs(inmates) do
		if i.Cell == cell then
			n += 1
		end
	end
	for _, j in pairs(jailedPlayers) do
		if j.Cell == cell then
			n += 2
		end
	end
	return n
end

local function freeBunk()
	for _, cell in ipairs(P.Cells) do
		local n = cellOccupants(cell)
		if n < 2 then
			local used = {}
			for _, i in ipairs(inmates) do
				if i.Cell == cell then
					used[i.Bunk] = true
				end
			end
			return cell, if used[1] then 2 else 1
		end
	end
	return nil
end

local function emptyCell()
	-- players get a cell to themselves (from the far end, away from the crowd)
	for k = #P.Cells, 1, -1 do
		local cell = P.Cells[k]
		if cellOccupants(cell) == 0 then
			return cell
		end
	end
	return P.Cells[#P.Cells]
end

local function inCell(cell, lp)
	local b = cell.Bounds
	return lp.X >= b[1] - 0.6 and lp.X <= b[2] + 0.6 and lp.Z >= b[3] - 0.6 and lp.Z <= b[4] + 0.6
end

local function inCompound(lp)
	return math.abs(lp.X) < 84 and math.abs(lp.Z) < 74 and lp.Y > -5 and lp.Y < 30
end

--------------------------------------------------------------------------------
-- Moving around inside
--------------------------------------------------------------------------------
-- a path (in the prison's own coordinates) from where someone is to a spot
local function route(i, to, toZone, toCell)
	local pts = {}
	local from, fromZone, fromCell = i.Local, i.Zone, i.AtCell
	local spine = P.Spine
	local lanes = P.Lanes
	if fromZone == "cell" and fromCell then
		if toZone == "cell" and toCell == fromCell then
			return { to }
		end
		table.insert(pts, fromCell.DoorIn)
		table.insert(pts, fromCell.DoorOut)
		table.insert(pts, Vector3.new(fromCell.DoorOut.X, 0, spine))
	elseif fromZone == "hall" then
		if toZone == "hall" then
			return { Vector3.new(from.X, 0, spine), Vector3.new(to.X, 0, spine), to }
		end
		table.insert(pts, Vector3.new(from.X, 0, spine))
	elseif fromZone == "yard" then
		if toZone == "yard" then
			return { to }
		end
		table.insert(pts, lanes.YardHub)
		table.insert(pts, lanes.DoorOut)
		table.insert(pts, lanes.HallEast)
	end
	if toZone == "yard" then
		if fromZone ~= "yard" then
			table.insert(pts, lanes.HallEast)
			table.insert(pts, lanes.DoorOut)
			table.insert(pts, lanes.YardHub)
		end
		table.insert(pts, to)
	elseif toZone == "hall" then
		table.insert(pts, Vector3.new(to.X, 0, spine))
		table.insert(pts, to)
	elseif toZone == "cell" and toCell then
		table.insert(pts, Vector3.new(toCell.DoorOut.X, 0, spine))
		table.insert(pts, toCell.DoorOut)
		table.insert(pts, toCell.DoorIn)
		table.insert(pts, to)
	else
		table.insert(pts, to)
	end
	return pts
end

local function release(i)
	if i.Spot and i.Spot.TakenBy == i then
		i.Spot.TakenBy = nil
	end
	i.Spot = nil
end

-- send someone to a spot to do something there (for `seconds`)
local function goDo(i, spot, zone, cell, action, seconds, activity)
	release(i)
	if spot then
		spot.TakenBy = i
	end
	i.Spot = spot
	i.Next = { Spot = spot, Zone = zone, Cell = cell, Action = action, Activity = activity }
	i.Until = os.clock() + (seconds or 30)
	local to = if spot then spot.Local else i.Local
	i.Path = route(i, to, zone, cell)
	i.PathI = 1
	i.Walking = true
	i.MoveAt = 0
	i.Progress = os.clock()
	i.LastPos = i.Brain.Root.Position
	S.Citizens.StandUp(i.Brain)
	-- (a brisk walk to chow and to count; an amble otherwise)
	local brisk = i.Hurry or action == "eat" or (zone == "hall" and action == "wait") or lastPeriod == "lockup"
	S.Citizens.SetGait(i.Brain, if brisk then 11 else 9, "walk")
	i.Brain.Model:SetAttribute("Action", "")
end

local function arrive(i)
	i.Walking = false
	local n = i.Next
	if not n then
		i.Until = 0
		return
	end
	i.Zone, i.AtCell = n.Zone, n.Cell
	if n.Spot then
		i.Local = n.Spot.Local
		S.Citizens.PlaceAt(i.Brain, n.Spot, n.Action or "wait")
	else
		S.Citizens.PlaceAt(i.Brain, { CFrame = i.Brain.Root.CFrame - Vector3.new(0, 3, 0) }, n.Action or "wait")
	end
	if n.Activity then
		i.Brain.Model:SetAttribute("Activity", n.Activity)
	end
end

-- walking laps: the track is a loop, around and around
local function goLaps(i, seconds)
	release(i)
	i.Next = nil
	i.Laps = true
	i.Until = os.clock() + seconds
	local path = route(i, P.Laps[1], "yard")
	for k = 2, #P.Laps do
		table.insert(path, P.Laps[k])
	end
	i.Path, i.PathI, i.Walking = path, 1, true
	i.MoveAt, i.Progress, i.LastPos = 0, os.clock(), i.Brain.Root.Position
	S.Citizens.StandUp(i.Brain)
	S.Citizens.SetGait(i.Brain, 9, "walk")
	i.Brain.Model:SetAttribute("Activity", "🚶 Walking laps in the yard")
end

local function walkStep(i, now)
	local brain = i.Brain
	local target = i.Path[i.PathI]
	if not target then
		if i.Laps then
			i.PathI = 1
			local loop = {}
			for k = 1, #P.Laps do
				loop[k] = P.Laps[k]
			end
			i.Path = loop
			return
		end
		arrive(i)
		return
	end
	local world = W(target)
	local d = flat(brain.Root.Position - world).Magnitude
	if d < 1.6 then
		i.Local = target
		i.PathI += 1
		i.MoveAt = 0
		return
	end
	if now - i.MoveAt > 2 then
		i.MoveAt = now
		brain.Humanoid:MoveTo(world)
	end
	-- stuck on something? step through to the next point
	if (brain.Root.Position - i.LastPos).Magnitude > 1 then
		i.LastPos = brain.Root.Position
		i.Progress = now
	elseif now - i.Progress > 4 then
		brain.Root.CFrame = CFrame.new(world + Vector3.new(0, 3, 0))
		i.Progress = now
	end
end

--------------------------------------------------------------------------------
-- What an inmate does next
--------------------------------------------------------------------------------
local function cellActivity(i, seconds)
	local cell = i.Cell
	local r = math.random()
	if i.Bunk == 2 and r < 0.35 then
		goDo(i, cell.Bunks[2], "cell", cell, "sleep", seconds, "🛏️ Lying on their bunk")
	elseif r < 0.55 then
		if taken(cell.Seat) then
			goDo(i, cell.Desk, "cell", cell, "study", seconds, "✏️ Writing a letter home")
		else
			goDo(i, cell.Seat, "cell", cell, "read", seconds, "📖 Reading in their cell")
		end
	elseif r < 0.75 then
		goDo(i, if taken(cell.Stand) then cell.Seat else cell.Stand, "cell", cell, if taken(cell.Stand) then "read" else "stretch", seconds, "🤸 Passing the time")
	else
		if taken(cell.Stand) then
			goDo(i, cell.Desk, "cell", cell, "study", seconds, "✏️ Writing a letter home")
		else
			goDo(i, cell.Stand, "cell", cell, "wait", seconds, "🔒 In their cell")
		end
	end
end

local function yardActivity(i, seconds)
	local r = math.random()
	local spot
	if r < 0.22 then
		spot = freeSpot(P.Hoops)
		if spot then
			return goDo(i, spot, "yard", nil, "hoops", seconds, "🏀 Shooting hoops in the yard")
		end
	elseif r < 0.44 then
		spot = freeSpot(P.Weights)
		if spot then
			return goDo(i, spot, "yard", nil, spot.Action or "lift", seconds, "💪 Pumping iron in the yard")
		end
	elseif r < 0.62 then
		spot = freeSpot(P.Tables)
		if spot then
			return goDo(i, spot, "yard", nil, if math.random() < 0.5 then "chess" else "sit", seconds, "🃏 Playing cards in the yard")
		end
	elseif r < 0.76 then
		return goLaps(i, seconds)
	end
	spot = freeSpot(P.Hangout)
	if spot then
		return goDo(i, spot, "yard", nil, if spot.Lean then "wait" elseif math.random() < 0.4 then "stretch" else "wait", seconds, "😎 Hanging out in the yard")
	end
	return goLaps(i, seconds)
end

local function choose(i, period)
	local left = 20 * (math.ceil(hour() + 0.001) - hour()) -- until the hour's up
	local seconds = math.random(18, 40)
	if period == "night" then
		return goDo(i, i.Cell.Bunks[i.Bunk], "cell", i.Cell, "sleep", 60, "💤 Asleep in their bunk")
	end
	if i.CellUntil and os.clock() < i.CellUntil then
		return cellActivity(i, math.min(seconds, i.CellUntil - os.clock() + 1))
	end
	if period == "wake" or period == "lockup" then
		return cellActivity(i, seconds)
	elseif period == "meal" then
		-- through the line first, then find a seat
		if not i.GotTray then
			i.GotTray = true
			local at = P.Cook.Local + Vector3.new(4.5, 0, math.random(-6, 6))
			local line = { CFrame = CFrame.lookAt(W(at), W(at - Vector3.new(4, 0, 0))), Local = at }
			return goDo(i, line, "hall", nil, "wait", 3, "🍲 In the chow line")
		end
		local seat = freeSpot(P.MessSeats)
		if seat then
			return goDo(i, seat, "hall", nil, "eat", math.max(left, 20), "🍲 Eating in the mess hall")
		end
		return cellActivity(i, seconds)
	elseif period == "yard" then
		return yardActivity(i, seconds)
	elseif period == "work" then
		local r = math.random()
		if r < 0.25 then
			local spot = freeSpot(P.MopSpots)
			if spot then
				return goDo(i, spot, "hall", nil, "mop", seconds, "🧽 Mopping the cell block")
			end
		elseif r < 0.4 then
			local spot = freeSpot(P.Sweep)
			if spot then
				return goDo(i, spot, "yard", nil, "sweep", seconds, "🧹 Sweeping the yard")
			end
		elseif r < 0.48 and not taken(P.Cook) then
			return goDo(i, P.Cook, "hall", nil, "cook", seconds, "🍳 Kitchen duty")
		end
		return yardActivity(i, seconds)
	elseif period == "rec" then
		local r = math.random()
		if r < 0.3 then
			local seat = freeSpot(P.TVSeats)
			if seat then
				return goDo(i, seat, "hall", nil, "tv", seconds, "📺 Watching TV")
			end
		elseif r < 0.6 then
			local seat = freeSpot(P.MessSeats)
			if seat then
				return goDo(i, seat, "hall", nil, if math.random() < 0.6 then "chess" else "sit", seconds, "♟️ Playing chess in the hall")
			end
		end
		return cellActivity(i, seconds)
	end
end

--------------------------------------------------------------------------------
-- People
--------------------------------------------------------------------------------
local function spawnInmate(cell, bunk, info)
	local name = info and info.Name or (FIRST[math.random(1, #FIRST)] .. " " .. LAST[math.random(1, #LAST)])
	local first = string.match(name, "^(%S+)") or name
	local spot = cell.Bunks[bunk]
	local brain = S.Citizens.SpawnExtra({ Name = name, First = first, Job = "Inmate", Age = math.random(20, 58), Activity = "🔒 Serving time" }, CFrame.new(W(cell.Stand.Local) + Vector3.new(0, 3, 0)))
	local i = {
		Brain = brain, Name = name, Cell = cell, Bunk = bunk, Zone = "cell", AtCell = cell, Local = cell.Stand.Local,
		Crime = info and info.Crime or CRIMES[math.random(1, #CRIMES)], Years = info and info.Years or math.random(1, 15),
		Until = 0,
	}
	brain.Inmate = true
	brain.Model:SetAttribute("Inmate", true)
	brain.Model:SetAttribute("Crime", i.Crime)
	brain.Model:SetAttribute("Bio", "Inmate #" .. (4000 + math.random(100, 999)) .. " · in for " .. i.Crime .. " · " .. i.Years .. (if i.Years == 1 then " year" else " years"))
	byBrain[brain] = i
	table.insert(inmates, i)
	return i, spot
end

local function spawnGuard(role, spot, patrol)
	local name = GUARD_NAMES[#guards % #GUARD_NAMES + 1]
	local brain = S.Citizens.SpawnExtra({ Name = name, First = name, Job = "Prison Guard", Age = math.random(28, 55), Activity = "👮 On duty" }, CFrame.new((if spot then spot.CFrame.Position else W(patrol[1])) + Vector3.new(0, 3, 0)))
	brain.Model:SetAttribute("Activity", if role == "tower" then "🔭 Watching from the tower" elseif role == "gate" then "🚧 Manning the gate" elseif role == "desk" then "👮 At the guard desk" else "👮 Walking the " .. role)
	local g = { Brain = brain, Role = role, Spot = spot, Patrol = patrol, PatrolI = 1, Until = 0 }
	if spot then
		S.Citizens.PlaceAt(brain, spot, "guard")
	end
	table.insert(guards, g)
	return g
end

-- a new inmate walks in from the gate (a street criminal, say)
local function admit(cell, bunk, info, fromGate)
	local i = spawnInmate(cell, bunk, info)
	if fromGate then
		i.Brain.Root.CFrame = CFrame.new(P.GateInside + Vector3.new(0, 3, 0))
		i.Zone, i.Local = "yard", P.Lanes.YardHub
		i.New = true
	end
	return i
end

local function respawnMissing(now)
	for k = #inmates, 1, -1 do
		local i = inmates[k]
		if not i.Brain.Model.Parent and not i.Street then
			-- knocked out and taken to the infirmary: back in a little while
			i.GoneAt = i.GoneAt or now
			if now - i.GoneAt > 45 then
				table.remove(inmates, k)
				byBrain[i.Brain] = nil
				release(i)
				admit(i.Cell, i.Bunk, { Name = i.Name, Crime = i.Crime, Years = i.Years }, false)
			end
		elseif not i.Brain.Model.Parent then
			table.remove(inmates, k)
			byBrain[i.Brain] = nil
			release(i)
		end
	end
end

--------------------------------------------------------------------------------
-- Guards
--------------------------------------------------------------------------------
local function guardTick(g, now)
	local brain = g.Brain
	if not brain.Model.Parent or g.Busy then
		return
	end
	if g.Patrol then
		if g.Walking then
			local target = W(g.Patrol[g.PatrolI])
			if flat(brain.Root.Position - target).Magnitude < 2 then
				g.Walking = false
				g.Until = now + math.random(4, 9)
				local dir = flat(target - brain.Root.Position)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
				S.Citizens.PlaceAt(brain, { CFrame = CFrame.lookAt(target, target + dir) }, "guard")
			elseif now - (g.MoveAt or 0) > 2 then
				g.MoveAt = now
				brain.Humanoid:MoveTo(target)
			end
		elseif now > g.Until then
			g.PatrolI = g.PatrolI % #g.Patrol + 1
			g.Walking = true
			S.Citizens.StandUp(brain)
			S.Citizens.SetGait(brain, 7.5, "walk")
			brain.Model:SetAttribute("Action", "patrol")
			brain.Humanoid:MoveTo(W(g.Patrol[g.PatrolI]))
			g.MoveAt = now
		end
	end
end

local function guardSay(text, near)
	local best, bestD
	for _, g in ipairs(guards) do
		if g.Patrol and g.Brain.Model.Parent then
			local d = if near then (g.Brain.Root.Position - near).Magnitude else 0
			if not bestD or d < bestD then
				best, bestD = g, d
			end
		end
	end
	if best then
		S.Citizens.Say(best.Brain, text, "angry", 3)
	end
	return best
end

--------------------------------------------------------------------------------
-- Fights in the yard
--------------------------------------------------------------------------------
local function playersNear(radius)
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - P.Center).Magnitude < radius then
			table.insert(out, player)
		end
	end
	return out
end

local function startFight(now)
	if not S.Brawl or not S.Brawl.Fight then
		return
	end
	local pool = {}
	for _, i in ipairs(inmates) do
		if i.Brain.Model.Parent and not i.Walking and not i.Fighting and (i.Zone == "yard" or i.Zone == "hall") and i.Brain.State ~= "ko" then
			table.insert(pool, i)
		end
	end
	for a = 1, #pool do
		for b = a + 1, #pool do
			local x, y = pool[a], pool[b]
			if (x.Brain.Root.Position - y.Brain.Root.Position).Magnitude < 30 then
				release(x)
				release(y)
				x.Laps, y.Laps = nil, nil
				S.Citizens.StandUp(x.Brain)
				S.Citizens.StandUp(y.Brain)
				-- (let go of them so the brawl can take over)
				S.Citizens.Control(x.Brain, false)
				S.Citizens.Control(y.Brain, false)
				local fight = S.Brawl.Fight(x.Brain, y.Brain, { Quiet = true, NoPolice = true, Gang = true, Lines = FIGHT_LINES[math.random(1, #FIGHT_LINES)] })
				if fight then
					x.Fighting, y.Fighting = fight, fight
					for _, player in ipairs(playersNear(200)) do
						S.City.Toast(player, "🥊", "Fight in the " .. x.Zone .. "!", x.Name .. " and " .. y.Name .. " are going at it. The guards are on their way.", rgb(255, 120, 60))
					end
					-- the nearest guard runs over and breaks it up
					local spot = x.Brain.Root.Position
					local g = guardSay("HEY! BREAK IT UP!", spot)
					if g then
						g.Busy = true
						S.Citizens.StandUp(g.Brain)
						S.Citizens.SetGait(g.Brain, 17, "run")
						task.spawn(function()
							local t0 = os.clock()
							while os.clock() - t0 < 25 and fight and not fight.Done and g.Brain.Model.Parent and x.Brain.Model.Parent do
								g.Brain.Humanoid:MoveTo(x.Brain.Root.Position)
								if (g.Brain.Root.Position - x.Brain.Root.Position).Magnitude < 7 and os.clock() - t0 > 6 then
									S.Citizens.Say(g.Brain, "That's ENOUGH! Both of you, back to your cells!", "angry", 3)
									S.Brawl.Stop(fight)
									break
								end
								task.wait(0.3)
							end
							g.Busy = false
							g.Walking = true
							if g.Brain.Model.Parent then
								S.Citizens.SetGait(g.Brain, 7.5, "walk")
							end
						end)
					end
					return true
				end
			end
		end
	end
	return false
end

local function afterFight(i, now)
	if i.Fighting and (i.Fighting.Done or not (S.Brawl.FightOf and S.Brawl.FightOf(i.Brain))) then
		i.Fighting = nil
		i.CellUntil = now + 50
		i.Hurry = false
		-- the brawl let go of them; take them back
		S.Citizens.Control(i.Brain, true)
		i.Zone = if flat(P.Local(i.Brain.Root.Position)).X > P.BlockX[2] then "yard" else "hall"
		i.Local = P.Local(i.Brain.Root.Position)
		i.Until = 0
		return true
	end
	return i.Fighting ~= nil
end

--------------------------------------------------------------------------------
-- Talking
--------------------------------------------------------------------------------
local function chatter(now)
	if now < nextChat then
		return
	end
	nextChat = now + math.random(5, 9)
	local idle = {}
	for _, i in ipairs(inmates) do
		if i.Brain.Model.Parent and not i.Walking and not i.Fighting and i.Brain.Model:GetAttribute("Action") ~= "sleep" then
			table.insert(idle, i)
		end
	end
	for _ = 1, 6 do
		local a = idle[math.random(1, math.max(1, #idle))]
		if not a then
			return
		end
		for _, b in ipairs(idle) do
			if b ~= a and (b.Brain.Root.Position - a.Brain.Root.Position).Magnitude < 9 then
				local pair = CHAT[math.random(1, #CHAT)]
				S.Citizens.Say(a.Brain, pair[1], "neutral", 3)
				task.delay(2.4, function()
					if b.Brain.Model.Parent then
						S.Citizens.Say(b.Brain, pair[2], "neutral", 3)
					end
				end)
				return
			end
		end
	end
end

local function greetPlayers(now)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - P.Center).Magnitude < 130 then
			for _, i in ipairs(inmates) do
				if i.Brain.Model.Parent and not i.Fighting and now > (i.NextGreet or 0) and i.Brain.Model:GetAttribute("Action") ~= "sleep" and (i.Brain.Root.Position - root.Position).Magnitude < 9 then
					i.NextGreet = now + math.random(40, 80)
					local lines = if jailedPlayers[player] then FRESH else VISITOR
					S.Citizens.Say(i.Brain, lines[math.random(1, #lines)], "neutral", 3)
					break
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Players doing time
--------------------------------------------------------------------------------
local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- CrimeService books an arrested player in: returns where they're held
function PrisonService.AdmitPlayer(player, seconds)
	if not P then
		return nil
	end
	local cell = emptyCell()
	jailedPlayers[player] = { Cell = cell }
	local root = rootOf(player)
	if root then
		root.CFrame = CFrame.new(W(cell.Stand.Local) + Vector3.new(0, 3.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local period = periodAt(hour())
	S.City.Toast(player, "🔒", "Welcome to AI City State Prison", "Cell A-" .. string.format("%02d", cell.Id) .. ". You'll be out in " .. math.floor(seconds) .. "s. " .. (if doorsOpen then "The doors are open: the mess hall and the yard are yours. Don't try the walls." else "Lights out, so you stay in your cell until the doors open."), rgb(240, 140, 60))
	player:SetAttribute("PrisonCell", "A-" .. string.format("%02d", cell.Id))
	player:SetAttribute("PrisonPeriod", PERIOD_LABEL[period])
	guardSay("Got a new one! Cell A-" .. string.format("%02d", cell.Id) .. ".", root and root.Position)
	return W(cell.Stand.Local)
end

-- every tick while they're inside: keep them where they're allowed to be
function PrisonService.Confine(player, root)
	local j = jailedPlayers[player]
	if not j or not root then
		return
	end
	local lp = P.Local(root.Position)
	local ok = if doorsOpen then inCompound(lp) else inCell(j.Cell, lp)
	if not ok then
		root.CFrame = CFrame.new(W(j.Cell.Stand.Local) + Vector3.new(0, 3.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		S.City.Toast(player, "🚨", if doorsOpen then "Nice try" else "Lights out", if doorsOpen then "The guards caught you at the wall and walked you back to your cell." else "You're locked in your cell until 6:00.", rgb(220, 90, 80))
	end
end

-- time's up: out through the gate, onto Prison Road
function PrisonService.ReleasePlayer(player)
	jailedPlayers[player] = nil
	player:SetAttribute("PrisonCell", nil)
	player:SetAttribute("PrisonPeriod", nil)
	local root = rootOf(player)
	if root and P then
		root.CFrame = CFrame.new(P.Release + Vector3.new(0, 3.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		return true
	end
	return false
end

function PrisonService.IsInmate(brain)
	return byBrain[brain] ~= nil
end

-- StreetCrimeService: a street criminal serves their time here. The police
-- "bus them over": they turn up at the gate and are walked to a bunk.
function PrisonService.Admit(brain, reason)
	if not P then
		return false
	end
	local cell, bunk = freeBunk()
	if not cell then
		return false
	end
	local i = {
		Brain = brain, Name = brain.C.Name, Cell = cell, Bunk = bunk, Zone = "yard", Local = P.Lanes.YardHub,
		Crime = reason, Years = 0, Until = 0, Street = true, New = true,
	}
	S.Citizens.Control(brain, true)
	brain.Inmate = true
	brain.Root.Anchored = false
	brain.Root.CFrame = CFrame.new(P.GateInside + Vector3.new(0, 3.2, 0))
	brain.Model:SetAttribute("Jailed", true)
	brain.Model:SetAttribute("Activity", "🔒 In prison: " .. reason)
	byBrain[brain] = i
	table.insert(inmates, i)
	return true
end

function PrisonService.Release(brain)
	local i = byBrain[brain]
	if not i then
		return
	end
	byBrain[brain] = nil
	brain.Inmate = nil
	release(i)
	local k = table.find(inmates, i)
	if k then
		table.remove(inmates, k)
	end
	if brain.Model.Parent then
		S.Citizens.StandUp(brain)
	end
end

--------------------------------------------------------------------------------
-- Every tick
--------------------------------------------------------------------------------
local function searchlights(t, night, anyone)
	for k, tower in ipairs(P.Towers) do
		tower.Light.Enabled = night
		if night and anyone then
			local a = t * 0.4 + k * 1.7
			local aim = W(Vector3.new(30 + math.cos(a) * 45, 0, math.sin(a * 0.8) * 60))
			local cf = CFrame.lookAt(tower.Base, aim)
			tower.Head.CFrame = cf
			tower.Lens.CFrame = cf * CFrame.new(0, 0, -1.15)
		end
	end
end

local function tick(now)
	local h = hour()
	local period = periodAt(h)
	-- the doors
	local open = doorsShouldBeOpen(h)
	if open ~= doorsOpen then
		if not open then
			-- lights out: anyone not in their cell is put there
			for _, i in ipairs(inmates) do
				if i.Brain.Model.Parent and not i.Fighting and not inCell(i.Cell, P.Local(i.Brain.Root.Position)) then
					S.Citizens.StandUp(i.Brain)
					i.Brain.Root.CFrame = CFrame.new(W(i.Cell.Stand.Local) + Vector3.new(0, 3, 0))
					i.Zone, i.AtCell, i.Local, i.Walking, i.Laps = "cell", i.Cell, i.Cell.Stand.Local, false, nil
					i.Until = 0
				end
			end
			for player, j in pairs(jailedPlayers) do
				local root = rootOf(player)
				if root and not inCell(j.Cell, P.Local(root.Position)) then
					root.CFrame = CFrame.new(W(j.Cell.Stand.Local) + Vector3.new(0, 3.5, 0))
				end
				S.City.Toast(player, "🔒", "Lights out", "The cell doors are locked until 6:00.", rgb(120, 130, 170))
			end
		else
			for player in pairs(jailedPlayers) do
				S.City.Toast(player, "🔓", "Doors open", "Breakfast is at 7:00, then yard time.", rgb(90, 180, 120))
			end
		end
		setDoors(open)
	end
	-- the schedule changes: everyone moves on
	if period ~= lastPeriod then
		local was = lastPeriod
		lastPeriod = period
		for _, i in ipairs(inmates) do
			i.Until = 0
			i.GotTray = false
			if i.Laps and i.Brain.Model.Parent then
				-- off the track: carry on from wherever they are
				i.Laps, i.Walking = nil, false
				i.Zone, i.Local = "yard", P.Local(i.Brain.Root.Position)
			end
		end
		if was then
			local line = ({ meal = "Chow time! Line up!", yard = "Yard time! Let's go, let's go!", work = "Work detail! Grab a mop!", rec = "Rec time.", lockup = "COUNT TIME! Everybody back to your cells!", wake = "Rise and shine! Doors are opening!" })[period]
			if line then
				guardSay(line)
			end
		end
		for player in pairs(jailedPlayers) do
			player:SetAttribute("PrisonPeriod", PERIOD_LABEL[period])
		end
	end
	for _, i in ipairs(inmates) do
		local brain = i.Brain
		if brain.Model.Parent and brain.State ~= "ko" and brain.State ~= "hospital" and not afterFight(i, now) and not brain.Model:GetAttribute("Fighting") then
			if brain.State ~= "police" then
				-- something else had them for a moment (a fight with a player):
				-- pick up from wherever they are now
				S.Citizens.Control(brain, true)
				i.Walking, i.Laps, i.Until = false, nil, 0
				i.Local = P.Local(brain.Root.Position)
				i.Zone = if inCell(i.Cell, i.Local) then "cell" elseif i.Local.X > P.BlockX[2] then "yard" else "hall"
				i.AtCell = if i.Zone == "cell" then i.Cell else nil
			end
			if i.Walking then
				walkStep(i, now)
				if i.Laps and now > i.Until then
					i.Walking, i.Laps = false, nil
					i.Zone, i.Local = "yard", P.Local(brain.Root.Position)
				end
			elseif now > i.Until then
				if i.New then
					i.New = nil
					S.Citizens.Say(brain, ({ "So this is it, huh...", "I want my lawyer!", "This place is huge." })[math.random(1, 3)], "sad", 3)
				end
				-- locked doors: whoever's out of their cell stays put
				if not doorsOpen and i.Zone ~= "cell" then
					brain.Root.CFrame = CFrame.new(W(i.Cell.Stand.Local) + Vector3.new(0, 3, 0))
					i.Zone, i.AtCell, i.Local = "cell", i.Cell, i.Cell.Stand.Local
				end
				choose(i, period)
			end
		end
	end
	for _, g in ipairs(guards) do
		guardTick(g, now)
	end
	-- yard fights (only with somebody around to see them)
	if (period == "yard" or period == "work" or period == "meal") and now > nextFight then
		nextFight = now + math.random(100, 200)
		if #playersNear(220) > 0 then
			startFight(now)
		end
	end
	if #playersNear(260) > 0 then
		chatter(now)
		greetPlayers(now)
	end
end

function PrisonService.Start(services)
	S = services
	P = S.Map and S.Map.Prison
	if not P or Config.PRISON == false then
		P = nil
		return
	end
	Players.PlayerRemoving:Connect(function(player)
		jailedPlayers[player] = nil
	end)
	task.spawn(function()
		-- (the citizens folder has to exist before anyone is spawned)
		local t0 = os.clock()
		while not workspace:FindFirstChild("Citizens") and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		local count = Config.PRISON_INMATES or 20
		for k = 1, count do
			local cell = P.Cells[math.floor((k - 1) / 2) + 1]
			if not cell then
				break
			end
			local ok, err = pcall(spawnInmate, cell, (k - 1) % 2 + 1)
			if not ok then
				warn("[PrisonService] " .. tostring(err))
			end
			if k % 4 == 0 then
				task.wait()
			end
		end
		-- the guards
		pcall(function()
			spawnGuard("hall", nil, P.HallPatrol)
			spawnGuard("yard", nil, P.YardPatrol)
			spawnGuard("yard", nil, { P.YardPatrol[3], P.YardPatrol[4], P.YardPatrol[1], P.YardPatrol[2] })
			spawnGuard("desk", P.DeskGuard)
			spawnGuard("gate", P.Booth)
			for _, tower in ipairs(P.Towers) do
				spawnGuard("tower", tower.Guard)
			end
			-- the nurse in the medical bay
			if P.NurseSpot then
				local ok, nurse = pcall(S.Citizens.SpawnExtra, { Name = "Nurse Okafor", First = "Nurse Okafor", Job = "Nurse", Age = 44, Activity = "🩺 On duty in the medical bay" }, CFrame.new(P.NurseSpot.CFrame.Position + Vector3.new(0, 3, 0)))
				if ok and nurse then
					S.Citizens.Control(nurse, true)
					S.Citizens.PlaceAt(nurse, P.NurseSpot, "nurse")
					nurse.Model:SetAttribute("Activity", "🩺 On duty in the medical bay")
					nurse.Staff = true
					PrisonService.Nurse = nurse
				end
			end
		end)
		nextFight = os.clock() + 90
		local t = 0
		while true do
			local dt = task.wait(0.25)
			t += dt
			local now = os.clock()
			local ok, err = pcall(tick, now)
			if not ok then
				warn("[PrisonService] " .. tostring(err))
				task.wait(2)
			end
			local h = hour()
			pcall(searchlights, t, h >= 19 or h < 6, #playersNear(500) > 0)
			if math.floor(t) % 5 == 0 then
				respawnMissing(now)
			end
		end
	end)
end

function PrisonService.Active()
	return P ~= nil
end

-- for tests and your own scripts: start a fight in the yard right now
function PrisonService.StartFight()
	return startFight(os.clock())
end

PrisonService.Inmates = inmates
PrisonService.Guards = guards
PrisonService.Players = jailedPlayers

return PrisonService
