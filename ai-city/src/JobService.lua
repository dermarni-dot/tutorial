-- JobService (ModuleScript) — ServerScriptService.Modules.JobService
-- Real jobs for players: clock in, work a shift, get paid by the hour.
--
--   • Clock in at the workplace (J, or the phone's Jobs app) during its
--     opening hours. You put on the uniform, and tasks come one after another
--     for as long as you stay: each is a glowing marker to walk to and hold E.
--   • Paid by the hour: every in-game hour on the clock is a paycheck (your
--     wage × your rank), as long as you actually worked that hour (no pay for
--     standing around). Past closing time you can do up to two hours of
--     overtime at 1.5×, then you're sent home. Clocking out pays the part of
--     the hour you worked.
--   • Each task has a deadline: on time keeps your rating up (★ 1-5). Good
--     service earns tips (baristas, cashiers, cooks, waiters), and your rating
--     sets the bonus at the end of the shift.
--   • Promotions: every task is experience for that job. Trainee → Junior →
--     Senior → Manager, each with a raise (saved between visits).
--
--   📬 Mail Carrier   🌱 Gardener   ☕ Barista   🧽 Janitor   📦 Warehouse Worker
--   🛒 Shelf Stocker   🧾 Cashier (serve real customers at your till)
--   🍳 Line Cook   🩺 Nurse   🔧 Mechanic   📚 Librarian   🚒 Firefighter (put out
--   fires around the city)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local JobService = {}
local S
local shifts = {} -- [player] = shift

local RANKS = {
	{ Name = "Trainee", XP = 0, Mult = 1 },
	{ Name = "Junior", XP = 40, Mult = 1.25 },
	{ Name = "Senior", XP = 120, Mult = 1.55 },
	{ Name = "Manager", XP = 300, Mult = 2 },
}
JobService.Ranks = RANKS
local OVERTIME_HOURS = 2
local ACTIVE_WINDOW = 50 -- real seconds: you must have finished a task this recently to be "working"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- find parts by name inside a place's model
local function partsNamed(place, names)
	local out = {}
	if place and place.Model then
		for _, d in ipairs(place.Model:GetDescendants()) do
			if d:IsA("BasePart") and names[d.Name] then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- where people do a kind of work at a place (its spots)
local function spotsOf(place, actions)
	local out = {}
	for _, s in ipairs(place.Spots or {}) do
		if actions[s.Action] then
			table.insert(out, s.CFrame.Position)
		end
	end
	return out
end

local function pick(list, n, rng)
	local copy = table.clone(list)
	local out = {}
	for _ = 1, math.min(n, #copy) do
		table.insert(out, table.remove(copy, rng:NextInteger(1, #copy)))
	end
	return out
end

local function any(list, rng, fallback)
	return if #list > 0 then list[rng:NextInteger(1, #list)] else fallback
end

local function posOf(p, fallback)
	return if p then (if typeof(p) == "Vector3" then p else p.Position) else fallback
end

--------------------------------------------------------------------------------
-- The jobs. Each: Emoji, Place, Wage (coins an in-game hour at Trainee),
-- Open / Close (hours), Desc, Duties (what you'll do), Uniform ({ color, hat
-- color or nil }), Tips (range for good service), Tasks(place, rng) = a batch
-- of tasks: { Pos, Text, Action (animation), Carry, Hold (seconds to hold E),
-- Time (seconds before it's late), Tip = true, Customer = true, Fire = true }
--------------------------------------------------------------------------------
local JOBS = {}
JobService.Jobs = JOBS
JobService.Order = { "Cashier", "Barista", "Line Cook", "Mail Carrier", "Nurse", "Mechanic", "Firefighter", "Librarian", "Gardener", "Janitor", "Warehouse Worker", "Shelf Stocker" }

JOBS["Mail Carrier"] = { Emoji = "📬", Place = "PostOffice", Wage = 9, Open = 7, Close = 18,
	Desc = "Sort the mail and deliver it door to door.", Duties = { "Sort letters at the post office", "Deliver to houses on the route" },
	Uniform = { rgb(40, 70, 140), rgb(40, 70, 140) },
	Tasks = function(place, rng)
		local list = {}
		local shelf = partsNamed(place, { SortingShelf = true, POBoxes = true })[1]
		table.insert(list, { Pos = if shelf then shelf.Position else place.Inside, Text = "Sort the mail", Action = "sort", Carry = "MailBag", Hold = 1.5, Time = 30 })
		local houses = {}
		for _, home in ipairs(S.Map.Homes) do
			local b = home.Building
			local box = b and b.Model and b.Model:FindFirstChild("Mailbox")
			if box and (home.Door - place.Door).Magnitude < 320 then
				table.insert(houses, { Box = box, Home = home, D = (home.Door - place.Door).Magnitude })
			end
		end
		table.sort(houses, function(a, b)
			return a.D < b.D
		end)
		for _, h in ipairs(pick({ table.unpack(houses, 1, math.min(14, #houses)) }, 4, rng)) do
			table.insert(list, { Pos = h.Box.Position, Text = "Deliver to " .. (h.Home.Address or "this house"), Action = "deliver", Carry = "MailBag", Hold = 1, Time = 60 })
		end
		return list
	end,
}
JOBS["Gardener"] = { Emoji = "🌱", Place = "Park", Wage = 7, Open = 6, Close = 18,
	Desc = "Keep Central Park beautiful.", Duties = { "Water the flowerbeds and trees", "Rake the paths", "Weed the beds" },
	Uniform = { rgb(70, 120, 60), rgb(200, 180, 110) },
	Tasks = function(place, rng)
		local list = {}
		local plants = partsNamed(place, { FlowerBed = true, Bush = true, Trunk = true })
		local kinds = { { "water", "Water the %s", "WateringCan" }, { "rake", "Rake around the %s", false }, { "garden", "Weed the %s", false } }
		for k, p in ipairs(pick(plants, 4, rng)) do
			local kind = kinds[(k - 1) % #kinds + 1]
			local what = if p.Name == "Trunk" then "tree" elseif p.Name == "Bush" then "bushes" else "flowerbed"
			table.insert(list, { Pos = p.Position, Text = string.format(kind[2], what), Action = kind[1], Carry = kind[3], Hold = 2, Time = 40 })
		end
		return list
	end,
}
JOBS["Barista"] = { Emoji = "☕", Place = "Cafe", Wage = 8, Open = 6, Close = 19, Tips = { 1, 4 },
	Desc = "Make drinks to order and serve them with a smile.", Duties = { "Take the order at the till", "Pull shots at the espresso machine", "Hand it over (tips for fast service)" },
	Uniform = { rgb(90, 60, 40), nil },
	Tasks = function(place, rng)
		local list = {}
		local machine = partsNamed(place, { EspressoMachine = true })[1]
		local till = partsNamed(place, { Register = true })[1]
		local drinks = { "a latte", "an espresso", "a cappuccino", "a hot chocolate", "an iced coffee", "a flat white", "a caramel macchiato" }
		for k = 1, 3 do
			local drink = drinks[rng:NextInteger(1, #drinks)]
			table.insert(list, { Pos = posOf(till, place.Inside), Text = "Take order #" .. k .. ": " .. drink, Action = "counter", Carry = false, Hold = 0.8, Time = 25 })
			table.insert(list, { Pos = posOf(machine, place.Inside), Text = "Make " .. drink, Action = "brew", Carry = "Cup", Hold = 2, Time = 25 })
			table.insert(list, { Pos = posOf(till, place.Inside), Text = "Serve " .. drink, Action = "pay", Carry = false, Hold = 0.6, Time = 20, Tip = true })
		end
		return list
	end,
}
JOBS["Janitor"] = { Emoji = "🧽", Place = "Office", Wage = 7, Open = 16, Close = 24,
	Desc = "Keep the office tower spotless.", Duties = { "Mop up spills", "Empty the trash", "Wipe down the desks" },
	Uniform = { rgb(60, 110, 150), nil },
	Tasks = function(place, rng)
		local list = {}
		local desks = partsNamed(place, { Desk = true })
		local bins = partsNamed(place, { TrashBin = true })
		local low = {}
		local base = place.Inside and place.Inside.Y or 0
		for _, d in ipairs(desks) do
			if d.Position.Y - base < 30 then
				table.insert(low, d)
			end
		end
		for _, d in ipairs(pick(if #low > 0 then low else desks, 3, rng)) do
			local pos = d.Position - d.CFrame.LookVector * 3
			table.insert(list, { Pos = Vector3.new(pos.X, d.Position.Y - d.Size.Y / 2 - 2.5, pos.Z), Text = "Mop the spill", Action = "mop", Carry = false, Hold = 2.2, Time = 40, Spill = true })
		end
		for _, b in ipairs(pick(bins, 1, rng)) do
			table.insert(list, { Pos = b.Position, Text = "Empty the trash", Action = "carrybox", Carry = false, Hold = 1.2, Time = 40 })
		end
		return list
	end,
}
JOBS["Warehouse Worker"] = { Emoji = "📦", Place = "Warehouse", Wage = 8, Open = 5, Close = 17,
	Desc = "Move stock from the loading bay to the racking.", Duties = { "Unload crates", "Stack them on the racking" },
	Uniform = { rgb(240, 180, 40), rgb(240, 200, 40) },
	Tasks = function(place, rng)
		local list = {}
		local crates = partsNamed(place, { Crate = true, Pallet = true })
		local racks = partsNamed(place, { Racking = true })
		for _ = 1, 3 do
			table.insert(list, { Pos = posOf(any(crates, rng), place.Inside), Text = "Pick up a crate", Action = "carrybox", Carry = "Box", Hold = 1, Time = 30 })
			table.insert(list, { Pos = posOf(any(racks, rng), place.Inside), Text = "Stack it on the racking", Action = "shelve", Carry = false, Hold = 1.4, Time = 30 })
		end
		return list
	end,
}
JOBS["Shelf Stocker"] = { Emoji = "🛒", Place = "Shop", Wage = 7, Open = 7, Close = 21,
	Desc = "Keep the Market's shelves full.", Duties = { "Grab stock from the back", "Fill the shelves", "Face the products" },
	Uniform = { rgb(200, 60, 60), nil },
	Tasks = function(place, rng)
		local list = {}
		local boxes = partsNamed(place, { StockBox = true })
		local shelves = partsNamed(place, { Shelf = true })
		for _ = 1, 3 do
			table.insert(list, { Pos = posOf(any(boxes, rng), place.Inside), Text = "Grab a stock box", Action = "carrybox", Carry = "Box", Hold = 1, Time = 25 })
			table.insert(list, { Pos = posOf(any(shelves, rng), place.Inside), Text = "Stock the shelf", Action = "shelve", Carry = false, Hold = 1.6, Time = 25 })
		end
		return list
	end,
}
JOBS["Cashier"] = { Emoji = "🧾", Place = "Shop", Wage = 8, Open = 7, Close = 21, Tips = { 0, 3 },
	Desc = "Run a till at the Market: customers line up and you ring them up.", Duties = { "Greet the customer at your till", "Scan every item and bag it", "Take the payment (keep the line moving for tips)" },
	Uniform = { rgb(200, 60, 60), nil },
	Tasks = function(place, rng)
		local list = {}
		local tills = partsNamed(place, { Register = true })
		local till = any(tills, rng)
		for k = 1, 4 do
			table.insert(list, { Pos = posOf(till, place.Inside), Till = till, Text = "Ring up customer #" .. k, Action = "cashier", Carry = false, Hold = 0.6, Time = 30, Customer = true, Tip = true })
		end
		return list
	end,
}
JOBS["Line Cook"] = { Emoji = "🍳", Place = "Diner", Wage = 9, Open = 6, Close = 22, Tips = { 1, 3 },
	Desc = "Cook orders on the Diner's grill and get them out hot.", Duties = { "Read the ticket", "Cook it on the stove", "Plate it and run it to the table" },
	Uniform = { rgb(245, 245, 240), rgb(245, 245, 240) },
	Tasks = function(place, rng)
		local list = {}
		local stoves = partsNamed(place, { Stove = true })
		local pass = partsNamed(place, { Counter = true, FoodCounter = true })
		local tables = partsNamed(place, { TableTop = true })
		local dishes = { "a cheeseburger", "a stack of pancakes", "bacon and eggs", "a grilled cheese", "a chili dog", "a patty melt" }
		for _ = 1, 2 do
			local dish = dishes[rng:NextInteger(1, #dishes)]
			table.insert(list, { Pos = posOf(any(pass, rng), place.Inside), Text = "Read the ticket: " .. dish, Action = "counter", Carry = false, Hold = 0.6, Time = 20 })
			table.insert(list, { Pos = posOf(any(stoves, rng), place.Inside), Text = "Cook " .. dish, Action = "cook", Carry = false, Hold = 3, Time = 30 })
			table.insert(list, { Pos = posOf(any(pass, rng), place.Inside), Text = "Plate it up", Action = "counter", Carry = "Tray", Hold = 1, Time = 15 })
			table.insert(list, { Pos = posOf(any(tables, rng), place.Inside), Text = "Serve " .. dish, Action = "serve", Carry = false, Hold = 0.8, Time = 20, Tip = true })
		end
		return list
	end,
}
JOBS["Nurse"] = { Emoji = "🩺", Place = "Hospital", Wage = 12, Open = 0, Close = 24,
	Desc = "Look after the patients on the ward.", Duties = { "Check vitals", "Give medicine", "Change IV bags" },
	Uniform = { rgb(120, 190, 200), nil },
	Tasks = function(place, rng)
		local list = {}
		local beds = partsNamed(place, { BedFrame = true })
		local base = place.Inside and place.Inside.Y or 0
		local low = {}
		for _, b in ipairs(beds) do
			if b.Position.Y - base < 14 then
				table.insert(low, b)
			end
		end
		local jobs = { "Check the vitals of the patient in bed %d", "Give medicine to bed %d", "Change the IV bag at bed %d", "Take bed %d's temperature" }
		for k, b in ipairs(pick(if #low > 0 then low else beds, 4, rng)) do
			table.insert(list, { Pos = b.Position, Text = string.format(jobs[rng:NextInteger(1, #jobs)], k + rng:NextInteger(1, 20)), Action = "nurse", Carry = false, Hold = 2.2, Time = 35 })
		end
		return list
	end,
}
JOBS["Mechanic"] = { Emoji = "🔧", Place = "GasStation", Wage = 11, Open = 7, Close = 19,
	Desc = "Fix up the cars at the Gas Station.", Duties = { "Change the oil", "Swap a tire", "Tune the engine", "Fill up a customer's tank" },
	Uniform = { rgb(60, 70, 90), rgb(200, 60, 40) },
	Tasks = function(place, rng)
		local list = {}
		local cars = spotsOf(place, { fixcar = true })
		local pumps = partsNamed(place, { Pump = true })
		local jobs = { "Change the oil", "Swap a flat tire", "Tune the engine", "Replace the brake pads", "Check the battery" }
		for _ = 1, 2 do
			table.insert(list, { Pos = any(cars, rng, place.Inside), Text = jobs[rng:NextInteger(1, #jobs)], Action = "fixcar", Carry = false, Hold = 3, Time = 45 })
		end
		table.insert(list, { Pos = posOf(any(pumps, rng), place.Door), Text = "Fill up a customer's tank", Action = "wait", Carry = false, Hold = 2, Time = 30, Tip = true })
		return list
	end,
}
JOBS["Librarian"] = { Emoji = "📚", Place = "Library", Wage = 8, Open = 8, Close = 20,
	Desc = "Keep the library running.", Duties = { "Check in returned books", "Reshelve them", "Help readers find a book" },
	Uniform = { rgb(120, 60, 70), nil },
	Tasks = function(place, rng)
		local list = {}
		local desk = partsNamed(place, { Counter = true })
		local shelves = partsNamed(place, { Bookshelf = true })
		local tables = partsNamed(place, { ReadingTable = true, StudyTable = true })
		table.insert(list, { Pos = posOf(any(desk, rng), place.Inside), Text = "Check in the returned books", Action = "sort", Carry = "Box", Hold = 1.5, Time = 25 })
		for _ = 1, 2 do
			table.insert(list, { Pos = posOf(any(shelves, rng), place.Inside), Text = "Reshelve the books", Action = "shelve", Carry = false, Hold = 2, Time = 30 })
		end
		table.insert(list, { Pos = posOf(any(tables, rng), place.Inside), Text = "Help a reader find a book", Action = "point", Carry = false, Hold = 1.2, Time = 25 })
		return list
	end,
}
JOBS["Firefighter"] = { Emoji = "🚒", Place = "FireStation", Wage = 13, Open = 0, Close = 24,
	Desc = "Answer the calls: fires break out around the city and you put them out.", Duties = { "Check the truck", "Race to the fire", "Hose it down" },
	Uniform = { rgb(60, 40, 30), rgb(200, 40, 30) },
	Tasks = function(place, rng)
		local list = {}
		local truck = spotsOf(place, { fixcar = true })
		table.insert(list, { Pos = any(truck, rng, place.Inside), Text = "Check the truck and the hoses", Action = "fixcar", Carry = false, Hold = 1.5, Time = 25 })
		-- a fire somewhere on the streets near the station
		local near = {}
		for _, n in ipairs(S.Map.Nodes or {}) do
			local d = (n - place.Door).Magnitude
			if d > 50 and d < 260 then
				table.insert(near, n)
			end
		end
		for _, n in ipairs(pick(near, 2, rng)) do
			table.insert(list, { Pos = n, Text = "Put out the fire!", Action = "hose", Carry = false, Hold = 3.5, Time = 60, Fire = true })
		end
		return list
	end,
}

--------------------------------------------------------------------------------
-- Ranks and experience (saved per job)
--------------------------------------------------------------------------------
local function xpOf(player, jobName)
	local pd = S.City.Data(player)
	return pd and pd.JobXP and pd.JobXP[jobName] or 0
end

local function rankOf(xp)
	local r, index = RANKS[1], 1
	for k, rank in ipairs(RANKS) do
		if xp >= rank.XP then
			r, index = rank, k
		end
	end
	return r, index, RANKS[index + 1]
end
JobService.RankOf = rankOf

local function wageOf(player, jobName)
	local rank = rankOf(xpOf(player, jobName))
	return math.floor(JOBS[jobName].Wage * rank.Mult + 0.5)
end

local function addXP(player, shift, amount)
	local pd = S.City.Data(player)
	if not pd then
		return
	end
	pd.JobXP = pd.JobXP or {}
	local before = rankOf(pd.JobXP[shift.Job] or 0)
	pd.JobXP[shift.Job] = (pd.JobXP[shift.Job] or 0) + amount
	local after = rankOf(pd.JobXP[shift.Job])
	if after ~= before then
		local job = JOBS[shift.Job]
		S.City.Toast(player, "🎉", "Promoted: " .. after.Name .. " " .. shift.Job .. "!", "Your wage is now 🪙 " .. wageOf(player, shift.Job) .. " an hour.", rgb(250, 200, 60))
		S.City.News(job.Emoji .. " " .. player.DisplayName .. " was promoted to " .. after.Name .. " " .. shift.Job .. ".", "City")
	end
end

--------------------------------------------------------------------------------
-- Hours: is the workplace open? (overnight hours wrap around midnight)
--------------------------------------------------------------------------------
local function openAt(job, hour)
	if job.Open <= job.Close then
		return hour >= job.Open and hour < job.Close
	end
	return hour >= job.Open or hour < job.Close
end
local function hoursPast(job, hour)
	-- how long after closing it is (0 while open)
	if openAt(job, hour) then
		return 0
	end
	return (hour - job.Close) % 24
end
local function fmtHour(h)
	h = h % 24
	return string.format("%d:%02d", math.floor(h), math.floor((h % 1) * 60))
end

--------------------------------------------------------------------------------
-- The marker, customers and fires
--------------------------------------------------------------------------------
local function clearMarker(shift)
	if shift.Marker then
		shift.Marker:Destroy()
		shift.Marker = nil
	end
	if shift.Customer and shift.Customer.Model.Parent and not shift.Serving then
		S.Citizens.Despawn(shift.Customer)
	end
	if not shift.Serving then
		shift.Customer = nil
	end
	if shift.FirePart then
		shift.FirePart:Destroy()
		shift.FirePart = nil
	end
end

local function rating(shift)
	if shift.Scores == 0 then
		return 5
	end
	return math.clamp(shift.ScoreSum / shift.Scores, 1, 5)
end

local function status(player, shift, extra)
	local job = JOBS[shift.Job]
	local step = shift.Tasks[shift.Index]
	local rank = rankOf(xpOf(player, shift.Job))
	S.City.Send(player, {
		Type = "Job", Job = shift.Job, Emoji = job.Emoji, Task = step and step.Text,
		Step = shift.Done + 1, Done = shift.Done, Earned = shift.Earned, Paid = extra and extra.Paid,
		Rank = rank.Name, Wage = wageOf(player, shift.Job), Hours = shift.Hours, Rating = rating(shift),
		Due = step and step.DueIn, Limit = step and step.Time, Overtime = shift.Overtime, Closes = fmtHour(job.Close), Tips = shift.Tips,
	})
	player:SetAttribute("JobTask", step and step.Text or nil)
end

local showTask -- forward

-- the uniform: a work shirt over your own (front and back), and a cap for some jobs
local function dress(player, job)
	local character = player.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	local head = character and character:FindFirstChild("Head")
	if not torso then
		return
	end
	local old = character:FindFirstChild("JobUniform")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "JobUniform"
	folder.Parent = character
	local function piece(part, name, size, offset, color, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		if shape then
			p.Shape = shape
		end
		p.CFrame = part.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, p
		w.Parent = p
		p.Parent = folder
		return p
	end
	local s = torso.Size
	local color = job.Uniform and job.Uniform[1] or rgb(80, 80, 90)
	piece(torso, "WorkShirtFront", Vector3.new(s.X * 0.8, s.Y * 0.9, 0.06), CFrame.new(0, -s.Y * 0.03, -s.Z / 2 - 0.04), color)
	piece(torso, "WorkShirtBack", Vector3.new(s.X * 0.8, s.Y * 0.9, 0.06), CFrame.new(0, -s.Y * 0.03, s.Z / 2 + 0.04), color)
	piece(torso, "NameTag", Vector3.new(0.4, 0.2, 0.05), CFrame.new(s.X * 0.22, s.Y * 0.2, -s.Z / 2 - 0.09), rgb(245, 245, 240))
	if head and job.Uniform and job.Uniform[2] then
		local h = head.Size.Y
		piece(head, "WorkCap", Vector3.new(1.05, 0.35, 1.05) * h, CFrame.new(0, h * 0.45, 0), job.Uniform[2])
		piece(head, "WorkCapBrim", Vector3.new(0.8, 0.08, 0.45) * h, CFrame.new(0, h * 0.3, -h * 0.65), job.Uniform[2]:Lerp(Color3.new(0, 0, 0), 0.2))
	end
end
local function undress(player)
	local character = player.Character
	local old = character and character:FindFirstChild("JobUniform")
	if old then
		old:Destroy()
	end
end

-- a customer walks up to the till (Cashier)
local function spawnCustomer(shift, step)
	local till = step.Till
	if not till or not S.Citizens or not S.Citizens.SpawnExtra then
		return
	end
	local look = till.CFrame.LookVector
	local front = till.Position + look * 4.6
	local names = { "Mrs. Patel", "Mr. Rossi", "Jo", "Sam", "Dana", "Mr. Kim", "Grandma Lee", "Theo", "Ms. Okafor" }
	local name = names[math.random(1, #names)]
	local brain = S.Citizens.SpawnExtra({ Name = name, First = name, Job = "", Age = math.random(20, 70), Activity = "🛒 Waiting to pay" }, CFrame.lookAt(front + Vector3.new(0, 3, 0), till.Position + Vector3.new(0, 3, 0)))
	S.Citizens.Control(brain, true)
	brain.Model:SetAttribute("Carry", "Bag")
	brain.Model:SetAttribute("Action", "wait")
	shift.Customer = brain
	task.delay(0.5, function()
		if brain.Model.Parent then
			S.Citizens.Say(brain, ({ "Hi! Just these, please.", "Morning!", "Hello there!", "Busy day, huh?" })[math.random(1, 4)], "happy", 2)
		end
	end)
end

-- a fire on the street (Firefighter)
local function spawnFire(shift, step)
	local p = Instance.new("Part")
	p.Name = "StreetFire"
	p.Anchored, p.CanCollide = true, false
	p.Size = Vector3.new(3, 1.4, 3)
	p.Color = rgb(40, 34, 30)
	p.Material = Enum.Material.CorrodedMetal
	p.CFrame = CFrame.new(step.Pos + Vector3.new(0, 0.7, 0))
	local f = Instance.new("Fire")
	f.Size = 10
	f.Heat = 16
	f.Parent = p
	local smoke = Instance.new("Smoke")
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 8
	smoke.Color = rgb(70, 70, 70)
	smoke.Parent = p
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 150, 60)
	light.Range = 24
	light.Brightness = 2
	light.Parent = p
	p.Parent = workspace
	shift.FirePart = p
end

local function finish(player, shift, reason)
	local job = JOBS[shift.Job]
	-- the part of the hour you worked
	local now = os.clock()
	local partial = 0
	if shift.HourFraction > 0 and now - (shift.LastTask or 0) < ACTIVE_WINDOW then
		partial = math.floor(wageOf(player, shift.Job) * shift.HourFraction * (if shift.Overtime then 1.5 else 1) + 0.5)
	end
	local stars = rating(shift)
	local bonus = if shift.Done >= 3 then math.floor(shift.Hours * 2 * (stars / 5) + (if stars >= 4.5 then 10 else 0) + 0.5) else 0
	clearMarker(shift)
	if shift.Customer and shift.Customer.Model.Parent then
		S.Citizens.Despawn(shift.Customer)
	end
	if shift.Folder then
		shift.Folder:Destroy()
	end
	shifts[player] = nil
	undress(player)
	if partial > 0 then
		S.City.AddCoins(player, partial, job.Emoji .. " Last paycheck")
		shift.Earned += partial
	end
	if bonus > 0 then
		S.City.AddCoins(player, bonus, job.Emoji .. " Shift bonus (" .. string.format("%.1f", stars) .. "★)")
		shift.Earned += bonus
	end
	local summary = string.format("%.1f hours · %d tasks · %.1f★ · 🪙 %d earned (wages %d, tips %d, bonus %d)", shift.Hours + shift.HourFraction, shift.Done, stars, shift.Earned, shift.Wages + partial, shift.Tips, bonus)
	S.City.Toast(player, job.Emoji, (reason or "Shift over") .. "", summary, rgb(90, 200, 120))
	S.City.Send(player, { Type = "Job", Job = shift.Job, Emoji = job.Emoji, Finished = true, Earned = shift.Earned, Summary = summary })
	S.City.Send(player, { Type = "Waypoint", Clear = true })
	player:SetAttribute("Job", nil)
	player:SetAttribute("JobTask", nil)
	if player.Character then
		player.Character:SetAttribute("Carry", nil)
		player.Character:SetAttribute("WorkAction", nil)
	end
	if S.City.Progress and shift.Done >= 3 then
		pcall(S.City.Progress, player, "work", 1)
	end
end

local function complete(player, shift, step)
	local job = JOBS[shift.Job]
	local character = player.Character
	local now = os.clock()
	if character then
		-- everyone sees you do it (see Poses: WorkAction)
		character:SetAttribute("WorkAction", step.Action)
		task.delay(1.4, function()
			if character.Parent and character:GetAttribute("WorkAction") == step.Action then
				character:SetAttribute("WorkAction", nil)
			end
		end)
		if step.Carry ~= nil then
			character:SetAttribute("Carry", step.Carry or nil)
		end
	end
	-- on time? (5★ on time, 3★ late, 1★ very late)
	local took = now - (shift.TaskStart or now)
	local limit = step.Time or 40
	local score = if took <= limit then 5 elseif took <= limit * 2 then 3 else 1
	shift.ScoreSum += score
	shift.Scores += 1
	shift.Done += 1
	shift.LastTask = now
	shift.WorkedThisHour = true
	addXP(player, shift, if score == 5 then 3 else 2)
	local tip = 0
	if step.Tip and job.Tips and score >= 3 then
		tip = math.random(job.Tips[1], job.Tips[2]) + (if score == 5 then 1 else 0)
		if tip > 0 then
			S.City.AddCoins(player, tip, job.Emoji .. " Tip")
			shift.Tips += tip
			shift.Earned += tip
		end
	end
	if step.Fire and shift.FirePart then
		shift.FirePart:Destroy()
		shift.FirePart = nil
		S.City.News("🚒 " .. player.DisplayName .. " put out a fire on " .. (S.Map.StreetNear and S.Map.StreetNear(step.Pos) or "the street") .. ".", "City")
	end
	shift.Index += 1
	if shift.Index > #shift.Tasks then
		-- the next batch of work
		local place = S.Map.Places[job.Place]
		shift.Tasks = job.Tasks(place, Random.new())
		shift.Index = 1
	end
	showTask(player, shift)
	status(player, shift, { Paid = tip })
end

-- the cashier's till: the customer and you do the whole checkout, then they pay
local function serveCustomer(player, shift, step)
	local customer = shift.Customer
	local character = player.Character
	if not customer or not customer.Model.Parent or not character or not step.Till then
		complete(player, shift, step)
		return
	end
	shift.Serving = true
	local till = step.Till
	local dur = 5.5
	local now = workspace:GetServerTimeNow()
	local look = till.CFrame.LookVector
	local items = math.random(2, 6)
	for _, m in ipairs({ character, customer.Model }) do
		m:SetAttribute("CheckoutStart", now)
		m:SetAttribute("CheckoutKind", "shop")
		m:SetAttribute("CheckoutDur", dur)
		m:SetAttribute("CheckoutItems", items)
		m:SetAttribute("CheckoutTill", till.Position)
		m:SetAttribute("CheckoutLook", look)
		m:SetAttribute("CheckoutRole", if m == character then "clerk" else "customer")
	end
	local price = items * math.random(2, 4)
	task.delay(dur * 0.6, function()
		if customer.Model.Parent then
			S.Citizens.Say(customer, "That's " .. price .. "? Here you go.", "happy", 2)
		end
	end)
	task.delay(dur + 0.2, function()
		for _, m in ipairs({ character, customer.Model }) do
			if m.Parent and m:GetAttribute("CheckoutStart") == now then
				for _, a in ipairs({ "CheckoutStart", "CheckoutKind", "CheckoutDur", "CheckoutItems", "CheckoutTill", "CheckoutLook", "CheckoutRole" }) do
					m:SetAttribute(a, nil)
				end
			end
		end
		shift.Serving = false
		if customer.Model.Parent then
			S.Citizens.Say(customer, ({ "Thanks! Have a good one!", "Bye now!", "Thank you, dear." })[math.random(1, 3)], "happy", 2)
			customer.Model:SetAttribute("Action", "")
			S.Citizens.SetGait(customer, 8, "walk")
			local place = S.Map.Places[JOBS[shift.Job].Place]
			if place and place.Door then
				customer.Humanoid:MoveTo(place.Door)
			end
			task.delay(6, function()
				if customer.Model.Parent then
					S.Citizens.Despawn(customer)
				end
			end)
		end
		if shift.Customer == customer then
			shift.Customer = nil
		end
		if shifts[player] == shift then
			complete(player, shift, step)
		end
	end)
end

showTask = function(player, shift)
	clearMarker(shift)
	local step = shift.Tasks[shift.Index]
	shift.TaskStart = os.clock()
	step.DueIn = step.Time
	if step.Customer then
		spawnCustomer(shift, step)
	elseif step.Fire then
		spawnFire(shift, step)
	end
	local ground = step.Pos
	local marker = Instance.new("Part")
	marker.Name = "JobMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Material = Enum.Material.Neon
	marker.Color = rgb(255, 200, 60)
	marker.Transparency = 0.35
	if step.Spill then
		-- a puddle on the floor
		marker.Size = Vector3.new(0.1, 3.2, 3.2)
		marker.Color = rgb(120, 180, 230)
		marker.Material = Enum.Material.Glass
		marker.Transparency = 0.2
		marker.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	else
		marker.Size = Vector3.new(0.3, 2.2, 2.2)
		marker.CFrame = CFrame.new(ground + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	marker:SetAttribute("Owner", player.UserId)
	local light = Instance.new("PointLight")
	light.Color = marker.Color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = marker
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JobPrompt"
	prompt.ActionText = step.Text
	prompt.ObjectText = JOBS[shift.Job].Emoji .. " " .. shift.Job
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = step.Hold or 1
	prompt.MaxActivationDistance = if step.Fire then 14 else 11
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Job")
	prompt.Parent = marker
	prompt.Triggered:Connect(function(who)
		if who == player and shifts[player] == shift and shift.Tasks[shift.Index] == step and not shift.Serving then
			if step.Customer then
				prompt.Enabled = false
				serveCustomer(player, shift, step)
			else
				complete(player, shift, step)
			end
		end
	end)
	-- only your own markers show up for you (see World: job prompts)
	marker.Parent = shift.Folder
	shift.Marker = marker
	S.City.Send(player, { Type = "Waypoint", Position = ground, Label = step.Text, Emoji = JOBS[shift.Job].Emoji })
end

--------------------------------------------------------------------------------
-- The clock: paychecks every in-game hour, the deadline countdown, overtime
--------------------------------------------------------------------------------
local function clockTick(player, shift, dHours)
	local job = JOBS[shift.Job]
	local hour = S.City.Hour()
	shift.HourFraction += dHours
	local step = shift.Tasks[shift.Index]
	if step and step.Time and shift.TaskStart then
		step.DueIn = math.max(0, math.floor(step.Time - (os.clock() - shift.TaskStart)))
	end
	-- past closing: overtime, then home
	local past = hoursPast(job, hour)
	if past > 0 and not shift.Overtime then
		shift.Overtime = true
		S.City.Toast(player, "⏰", "Closing time", "Overtime pays 1.5×. You can stay " .. OVERTIME_HOURS .. " more hours, or clock out.", rgb(240, 170, 60))
	end
	if past >= OVERTIME_HOURS then
		finish(player, shift, "Overtime's over: time to go home")
		return
	end
	if shift.HourFraction >= 1 then
		shift.HourFraction -= 1
		shift.Hours += 1
		if shift.WorkedThisHour then
			local pay = math.floor(wageOf(player, shift.Job) * (if shift.Overtime then 1.5 else 1) + 0.5)
			S.City.AddCoins(player, pay, job.Emoji .. " Hourly wage")
			shift.Earned += pay
			shift.Wages += pay
			S.City.Send(player, { Type = "Toast", Icon = "💵", Title = "Paycheck: +" .. pay .. " coins", Text = "1 hour as a " .. rankOf(xpOf(player, shift.Job)).Name .. " " .. shift.Job .. (if shift.Overtime then " (overtime 1.5×)" else ""), Color = rgb(90, 200, 120) })
		else
			shift.Idle += 1
			S.City.Toast(player, "😒", "No pay this hour", "The boss saw you standing around. Finish tasks to get paid.", rgb(200, 120, 80))
			if shift.Idle >= 3 then
				finish(player, shift, "Sent home for slacking")
				return
			end
		end
		shift.WorkedThisHour = false
	end
	status(player, shift)
end

--------------------------------------------------------------------------------
-- Clocking in and out
--------------------------------------------------------------------------------
function JobService.Begin(player, jobName)
	local job = JOBS[jobName or ""]
	local place = job and S.Map.Places[job.Place]
	if not place then
		return { Ok = false, Error = "No such job." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "You can't work from jail." }
	end
	if (player:GetAttribute("Wanted") or 0) > 0 then
		return { Ok = false, Error = "Nobody hires someone the police are after!" }
	end
	local hour = S.City.Hour()
	if not openAt(job, hour) then
		return { Ok = false, Error = "The " .. jobName .. " shift runs " .. fmtHour(job.Open) .. " to " .. fmtHour(job.Close) .. ". Come back then." }
	end
	JobService.Quit(player, true)
	local rng = Random.new()
	local tasks = job.Tasks(place, rng)
	if #tasks == 0 then
		return { Ok = false, Error = "There's no work here right now." }
	end
	local folder = Instance.new("Folder")
	folder.Name = "JobMarkers_" .. player.UserId
	folder.Parent = workspace
	local shift = {
		Job = jobName, Tasks = tasks, Index = 1, Earned = 0, Wages = 0, Tips = 0, Folder = folder,
		Hours = 0, HourFraction = 0, Done = 0, ScoreSum = 0, Scores = 0, Idle = 0, WorkedThisHour = false,
		LastTask = os.clock(), LastHour = hour,
	}
	shifts[player] = shift
	player:SetAttribute("Job", jobName)
	dress(player, job)
	showTask(player, shift)
	status(player, shift)
	local rank = rankOf(xpOf(player, jobName))
	S.City.Toast(player, job.Emoji, "Clocked in: " .. rank.Name .. " " .. jobName, "🪙 " .. wageOf(player, jobName) .. " an hour until " .. fmtHour(job.Close) .. ". " .. job.Desc .. " Follow the marker.", rgb(240, 190, 60))
	return { Ok = true }
end

function JobService.Quit(player, quiet)
	local shift = shifts[player]
	if not shift then
		return { Ok = true }
	end
	if quiet then
		clearMarker(shift)
		if shift.Customer and shift.Customer.Model.Parent then
			S.Citizens.Despawn(shift.Customer)
		end
		if shift.Folder then
			shift.Folder:Destroy()
		end
		shifts[player] = nil
		undress(player)
		player:SetAttribute("Job", nil)
		player:SetAttribute("JobTask", nil)
		return { Ok = true }
	end
	finish(player, shift, "Clocked out")
	S.City.Send(player, { Type = "Job", Quit = true, Earned = shift.Earned, Job = shift.Job })
	return { Ok = true }
end

function JobService.Current(player)
	local shift = shifts[player]
	return shift and shift.Job
end
JobService.Shifts = shifts

-- the Jobs app
local function listJobs(player)
	local out = {}
	local hour = S.City.Hour()
	for _, name in ipairs(JobService.Order) do
		local job = JOBS[name]
		local place = S.Map.Places[job.Place]
		if place then
			local info = Config.PlaceById and Config.PlaceById[job.Place]
			local xp = xpOf(player, name)
			local rank, _, nextRank = rankOf(xp)
			table.insert(out, {
				Name = name, Emoji = job.Emoji, Desc = job.Desc, Duties = job.Duties, Place = (info and info.label) or job.Place, Position = place.Door,
				Wage = wageOf(player, name), Hours = fmtHour(job.Open) .. "–" .. fmtHour(job.Close), Open = openAt(job, hour),
				Rank = rank.Name, XP = xp, NextXP = nextRank and nextRank.XP, NextRank = nextRank and nextRank.Name, Tips = job.Tips ~= nil,
			})
		end
	end
	return { Ok = true, Jobs = out, Current = JobService.Current(player) }
end

-- a time clock at every workplace
local function clockIn(jobName)
	local job = JOBS[jobName]
	local place = S.Map.Places[job.Place]
	if not place then
		return
	end
	local post = Instance.new("Part")
	post.Name = "TimeClock"
	post.Anchored = true
	post.CanCollide = false
	post.Size = Vector3.new(1.2, 1.6, 0.4)
	post.Color = rgb(60, 64, 74)
	post.Material = Enum.Material.Metal
	local at = place.Inside or place.Door
	-- (two jobs at the same place: their clocks sit side by side)
	local n = 0
	for _, other in ipairs(JobService.Order) do
		if other == jobName then
			break
		end
		if JOBS[other].Place == job.Place then
			n += 1
		end
	end
	post.CFrame = CFrame.new(at + Vector3.new(n * 3, 4, 0))
	post.Transparency = 1
	post.Parent = place.Model or workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClockInPrompt"
	prompt.ActionText = "Work as " .. jobName
	prompt.ObjectText = job.Emoji .. " 🪙 " .. job.Wage .. "+ an hour · " .. fmtHour(job.Open) .. "–" .. fmtHour(job.Close)
	prompt.KeyboardKeyCode = Enum.KeyCode.J
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Job")
	prompt.Parent = post
	prompt.Triggered:Connect(function(player)
		if JobService.Current(player) == jobName then
			S.City.Toast(player, job.Emoji, "Already on shift", "Follow the marker to your next task.", rgb(240, 190, 60))
			return
		end
		local r = JobService.Begin(player, jobName)
		if not r.Ok then
			S.City.Toast(player, "🚫", "Can't clock in", r.Error, rgb(200, 90, 90))
		end
	end)
end

function JobService.Start(services)
	S = services
	for _, name in ipairs(JobService.Order) do
		clockIn(name)
	end
	S.City.Handle("Jobs", listJobs)
	S.City.Handle("StartJob", function(player, data)
		return JobService.Begin(player, data.Job)
	end)
	S.City.Handle("QuitJob", function(player)
		return JobService.Quit(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		JobService.Quit(player, true)
	end)
	-- the shift clock (in-game hours from the city clock)
	task.spawn(function()
		local last = S.City.Hour()
		while true do
			task.wait(1)
			local hour = S.City.Hour()
			local d = (hour - last) % 24
			last = hour
			if d > 6 then
				d = 0 -- (the clock was set: don't count it)
			end
			for player, shift in pairs(shifts) do
				local ok, err = pcall(clockTick, player, shift, d)
				if not ok then
					warn("[JobService] " .. tostring(err))
				end
			end
		end
	end)
end

return JobService
