-- Errands (ModuleScript) — ServerScriptService.Modules.Errands
-- Gives what citizens do a real purpose. A plan ("go shopping", "work at the
-- post office") becomes a chain of tasks, each a place to walk to and
-- something to do there, with a prop in hand:
--   • shopping: browse the shelves, pay at the register, walk out with a
--     shopping bag, and unpack it in the kitchen at home
--   • cafes, bakeries, diners, ice cream: order and pay at the counter, then
--     sit down to eat (or take it to go)
--   • mail carriers sort the mail, then walk house to house putting letters
--     in mailboxes
--   • gardeners water and rake the park, police officers patrol the streets
--     and check in at the station, waiters carry plates from the kitchen to
--     the tables, store clerks restock shelves from the stockroom, the night
--     janitor mops the office floors
--   • on the way to work people carry a briefcase, kids a backpack, gym-goers
--     a gym bag
-- Each task is an ordinary CitizenService target ({ Spot or Pos, Place,
-- Building, Floor, Action... }) plus Duration (seconds), Carry (a prop to
-- hold, false to put it down), Look (what to face) and Say (a line).

local Errands = {}
local api -- set by CitizenService: { Map, Free, PickSpot, StandNear, HomeOf, Rng }

function Errands.Init(helpers)
	api = helpers
end

local SHOPS = { Shop = true, Mall = true, Pharmacy = true, Hardware = true, Bookstore = true, ToyStore = true, Electronics = true, Florist = true, PetShop = true }
local FOOD = { Cafe = "Cup", Bakery = "Pastry", Diner = "Cup", IceCream = "Cone", Restaurant = false }
local OFFICE_WORK = { Office = true, Bank = true, TownHall = true }

local PAY_LINES = { "Just these, please.", "Card is fine.", "Thanks!", "Keep the change.", "Have a nice day!" }
local ORDER_LINES = { "A coffee, please!", "One of those, please.", "What's good today?", "I'll have the usual.", "To go, please." }

-- spots at a place with one of these actions
local function spotsWith(place, actions)
	local out = {}
	for _, s in ipairs(place.Spots or {}) do
		if actions[s.Action] then
			table.insert(out, s)
		end
	end
	return out
end

-- standing across the counter from someone who works there (a cashier spot):
-- the customer's side is in front of them
local function counterFront(spot, dist)
	local cf = spot.CFrame
	local pos = cf.Position + cf.LookVector * (dist or 4.6)
	return pos, cf.Position
end

local function task(base, fields)
	local t = { Plan = base.Plan, Place = base.Place, Door = base.Door, Building = base.Building, Floor = base.Floor or 1, IsTask = true }
	for k, v in pairs(fields) do
		t[k] = v
	end
	return t
end

-- a spot's building and floor (spots inside buildings know where they are)
local function atSpot(base, spot, fields)
	fields.Spot = spot
	fields.Building = spot.Building or base.Building
	fields.Floor = spot.Floor or 1
	return task(base, fields)
end

local function nearbyPos(spot, side)
	local cf = spot.CFrame
	return cf.Position + cf.RightVector * (side or 2.4) + cf.LookVector * 1.2
end

--------------------------------------------------------------------------------
-- Errands at a place (shopping, ordering food)
--------------------------------------------------------------------------------
local function shopping(brain, plan, t, rng)
	local place = t.Place
	local list = {}
	-- 1. look around the shelves (the spot the plan picked, if it's a browse spot)
	local browse = spotsWith(place, { browse = true })
	local first = if t.Spot and t.Spot.Action == "browse" then t.Spot else api.PickSpot(browse, brain, "browse", nil, rng)
	if first then
		table.insert(list, atSpot(t, first, { Action = "browse", Duration = rng:NextInteger(10, 16) }))
	end
	-- 2. pay at the register
	local tills = spotsWith(place, { cashier = true, counter = true })
	if #tills > 0 then
		local till = tills[rng:NextInteger(1, #tills)]
		local pos, look = counterFront(till)
		table.insert(list, task(t, { Pos = pos, Look = look, Building = till.Building or t.Building, Floor = till.Floor or 1, Action = "pay", Duration = 5, Say = if rng:NextNumber() < 0.5 then PAY_LINES[rng:NextInteger(1, #PAY_LINES)] else nil }))
	end
	-- 3. a last look around with the bag in hand (until it's time to go)
	local last = api.PickSpot(browse, brain, "browse", nil, rng)
	if last then
		table.insert(list, atSpot(t, last, { Action = "browse", Carry = "Bag", Duration = 999 }))
	else
		table.insert(list, task(t, { Pos = api.StandNear(place, rng), Action = "wait", Carry = "Bag", Duration = 999 }))
	end
	return list
end

local function eatingOut(brain, plan, t, rng)
	local place = t.Place
	local list = {}
	local tills = spotsWith(place, { cashier = true, counter = true, brew = true })
	if #tills > 0 and place.Id ~= "Restaurant" then
		local till = tills[rng:NextInteger(1, #tills)]
		local pos, look = counterFront(till)
		table.insert(list, task(t, { Pos = pos, Look = look, Building = till.Building or t.Building, Floor = till.Floor or 1, Action = "pay", Duration = 6, Say = if rng:NextNumber() < 0.6 then ORDER_LINES[rng:NextInteger(1, #ORDER_LINES)] else nil }))
	end
	-- then the seat the plan picked (eating, having a coffee...)
	local final = task(t, { Spot = t.Spot, Pos = t.Pos, Action = t.Action, Duration = 999, Carry = false })
	if t.Spot then
		final.Building, final.Floor = t.Spot.Building or t.Building, t.Spot.Floor or 1
	end
	-- nowhere to sit: take it to go
	if not t.Spot and FOOD[place.Id] then
		final.Carry = FOOD[place.Id]
		final.Action = "wait"
	end
	table.insert(list, final)
	return list
end

--------------------------------------------------------------------------------
-- Rounds: jobs that move around (loops for as long as the shift lasts)
--------------------------------------------------------------------------------
local ROUNDS = {}

-- the mail carrier: sort the mail, then four houses, then back
ROUNDS["Mail Carrier"] = function(brain, plan, t, rng)
	local list = {}
	if t.Spot then
		table.insert(list, atSpot(t, t.Spot, { Action = "sort", Duration = 14, Carry = false }))
	end
	local origin = t.Place.Door
	local houses = {}
	for _, home in ipairs(api.Map.Homes) do
		local b = home.Building
		if b and b.Model and b.Model:FindFirstChild("Mailbox") and b.At and (home.Door - origin).Magnitude < 260 then
			table.insert(houses, home)
		end
	end
	-- four houses, each the nearest to the last (a sensible route)
	local at = origin
	for k = 1, 4 do
		if #houses == 0 then
			break
		end
		-- a little randomness so every round is different
		local best, bestD = nil, math.huge
		for i, home in ipairs(houses) do
			local d = (home.Door - at).Magnitude + rng:NextNumber(0, 60)
			if d < bestD then
				best, bestD = i, d
			end
		end
		local home = table.remove(houses, best)
		local b = home.Building
		local pos = b.At(4, 0, -b.D / 2 - 10.6).Position
		local box = b.At(4, 0, -b.D / 2 - 9).Position
		table.insert(list, { Plan = plan, Pos = pos, Door = pos, Look = box, Floor = 1, Action = "deliver", Carry = "MailBag", Duration = 4, IsTask = true, Say = if k == 1 and rng:NextNumber() < 0.3 then "Mail's here!" else nil })
		at = home.Door
	end
	return list
end

-- the gardener: watering, raking and weeding around the park
ROUNDS["Gardener"] = function(brain, plan, t, rng)
	local list = {}
	local place = t.Place
	local jobs = { { "water", "WateringCan" }, { "rake", false }, { "garden", false } }
	for k = 1, 4 do
		local s = place.Spots and place.Spots[rng:NextInteger(1, math.max(1, #place.Spots))]
		local pos = if s then nearbyPos(s, if rng:NextNumber() < 0.5 then 3 else -3) else api.StandNear(place, rng)
		local job = jobs[(k - 1) % #jobs + 1]
		table.insert(list, task(t, { Pos = pos, Building = nil, Action = job[1], Carry = job[2], Duration = rng:NextInteger(10, 16) }))
	end
	return list
end

-- police: out on patrol around the station's streets, then check in at the desk
local function patrol(brain, plan, t, rng)
	local list = {}
	local origin = t.Place.Door
	local near = {}
	for _, n in ipairs(api.Map.Nodes or {}) do
		local d = (n - origin).Magnitude
		if d > 30 and d < 220 then
			table.insert(near, n)
		end
	end
	for _ = 1, 3 do
		if #near == 0 then
			break
		end
		local n = table.remove(near, rng:NextInteger(1, #near))
		table.insert(list, { Plan = plan, Pos = n, Door = n, Floor = 1, Action = "patrol", Carry = false, Duration = rng:NextInteger(6, 10), IsTask = true })
	end
	if t.Spot then
		table.insert(list, atSpot(t, t.Spot, { Action = t.Spot.Action, Duration = rng:NextInteger(25, 40) }))
	end
	return list
end
ROUNDS["Police Officer"] = patrol
ROUNDS["Night Officer"] = patrol

-- waiters: pick up plates at the kitchen, serve them at a table
ROUNDS["Waiter"] = function(brain, plan, t, rng)
	local list = {}
	local place = t.Place
	local kitchen = spotsWith(place, { cook = true })
	local tables = spotsWith(place, { eat = true })
	for _ = 1, 3 do
		if #kitchen > 0 then
			local k = kitchen[rng:NextInteger(1, #kitchen)]
			local pos, look = counterFront(k, 3)
			table.insert(list, task(t, { Pos = pos, Look = look, Building = k.Building or t.Building, Floor = k.Floor or 1, Action = "wait", Carry = false, Duration = 3 }))
		end
		if #tables > 0 then
			local s = tables[rng:NextInteger(1, #tables)]
			table.insert(list, task(t, { Pos = nearbyPos(s, 2.2), Look = s.CFrame.Position, Building = s.Building or t.Building, Floor = s.Floor or 1, Action = "serve", Carry = false, Duration = 5 }))
		end
	end
	return list
end

-- store clerks and shopkeepers: carry stock from the back to the shelves, then the till
local function restock(brain, plan, t, rng)
	local list = {}
	local place = t.Place
	local stock = spotsWith(place, { carrybox = true })
	local shelves = spotsWith(place, { browse = true, shelve = true })
	if #stock > 0 and #shelves > 0 then
		local s = stock[rng:NextInteger(1, #stock)]
		table.insert(list, task(t, { Pos = s.CFrame.Position, Look = s.CFrame.Position + s.CFrame.LookVector, Building = s.Building or t.Building, Floor = s.Floor or 1, Action = "carrybox", Carry = false, Duration = 4 }))
		local shelf = shelves[rng:NextInteger(1, #shelves)]
		table.insert(list, task(t, { Pos = shelf.CFrame.Position, Look = shelf.CFrame.Position + shelf.CFrame.LookVector * 2, Building = shelf.Building or t.Building, Floor = shelf.Floor or 1, Action = "shelve", Carry = false, Duration = rng:NextInteger(9, 14) }))
	end
	if t.Spot then
		table.insert(list, atSpot(t, t.Spot, { Action = t.Spot.Action, Duration = rng:NextInteger(30, 50) }))
	end
	return list
end
ROUNDS["Shopkeeper"] = restock
ROUNDS["Store Clerk"] = restock

-- the night janitor: mopping around the office floors
ROUNDS["Night Janitor"] = function(brain, plan, t, rng)
	local list = {}
	local place = t.Place
	local desks = spotsWith(place, { type = true })
	for _ = 1, 4 do
		if #desks == 0 then
			break
		end
		local s = desks[rng:NextInteger(1, #desks)]
		table.insert(list, task(t, { Pos = s.CFrame.Position - s.CFrame.LookVector * 3, Building = s.Building or t.Building, Floor = s.Floor or 1, Action = "mop", Carry = false, Duration = rng:NextInteger(10, 15) }))
	end
	return list
end

--------------------------------------------------------------------------------
-- The task list for a plan (nil: just go to the target and stay)
--------------------------------------------------------------------------------
function Errands.Tasks(brain, plan, t, rng)
	if not plan or not t then
		return nil
	end
	local list
	if plan.Kind == "Work" and t.Place then
		local fn = ROUNDS[brain.C.Job or ""]
		list = fn and fn(brain, plan, t, rng)
	elseif plan.Kind == "Home" then
		-- back from the shops: unpack the bag in the kitchen first
		if brain.Model:GetAttribute("Carry") == "Bag" and t.Home then
			local kitchen = api.PickSpot(t.Home.Spots, brain, "cook", nil, rng)
			if kitchen then
				local pos = kitchen.CFrame.Position
				list = {
					task(t, { Pos = pos, Look = pos + kitchen.CFrame.LookVector * 2, Building = kitchen.Building or t.Building, Floor = kitchen.Floor or 1, Action = "unpack", Duration = 6, Carry = "Bag", Say = nil }),
					task(t, { Spot = t.Spot, Pos = t.Pos, Action = t.Action, Building = t.Building, Floor = t.Floor, Home = t.Home, Duration = 999, Carry = false }),
				}
			end
		end
	elseif plan.Kind == "Place" and t.Place and not plan.Family then
		local id = t.Place.Id
		local age = api.Age(brain.C)
		if SHOPS[id] and age >= 13 and (plan.Want == nil or plan.Want == "browse") then
			list = shopping(brain, plan, t, rng)
		elseif FOOD[id] ~= nil and age >= 10 and (plan.Want == "eat" or plan.Want == "coffee" or plan.Want == nil or plan.Want == "chat") then
			list = eatingOut(brain, plan, t, rng)
		end
	end
	if list and #list > 0 then
		return list
	end
	return nil
end

-- rounds start over when they're done (for as long as the plan lasts)
function Errands.Loops(brain, plan)
	return plan and plan.Kind == "Work" and ROUNDS[brain.C.Job or ""] ~= nil
end

-- what someone carries on the way somewhere
function Errands.CommuteProp(brain, plan, t)
	if not plan then
		return nil
	end
	local age = api.Age(brain.C)
	if plan.Kind == "School" and not plan.Recess and age >= 6 then
		return "Backpack"
	elseif plan.Kind == "Work" and t and t.Place and OFFICE_WORK[t.Place.Id] then
		return "Briefcase"
	elseif t and t.Place and t.Place.Id == "Gym" and age >= 13 then
		return "GymBag"
	end
	return nil
end

return Errands
