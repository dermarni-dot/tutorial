-- JobService (ModuleScript) — ServerScriptService.Modules.JobService
-- Jobs for players. Walk into a workplace and clock in (or pick a job in the
-- phone's Jobs app, which shows you the way), then work a shift: a list of
-- tasks, each a glowing marker to walk to and hold E (or X on a controller)
-- to do. Every task pays; finishing the shift pays a bonus. Your character
-- does the work (delivering letters, watering, mopping, carrying boxes...)
-- with the same animations the citizens use.
--
--   📬 Mail Carrier (Post Office)  pick up the mail, deliver to 5 houses
--   🌱 Gardener (Central Park)      water the flowerbeds and trees
--   ☕ Barista (Cafe)               make coffees and serve them at the till
--   🧽 Janitor (Offices)            mop up spills around the office
--   📦 Warehouse Worker             carry crates to the racking
--   🛒 Shelf Stocker (Market)       carry stock boxes to the shelves

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local JobService = {}
local S
local shifts = {} -- [player] = { Job, Tasks, Index, Earned, Folder, Marker }

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

local function pick(list, n, rng)
	local copy = table.clone(list)
	local out = {}
	for _ = 1, math.min(n, #copy) do
		table.insert(out, table.remove(copy, rng:NextInteger(1, #copy)))
	end
	return out
end

-- a task: { Pos, Text, Action (animation), Carry (prop after), Hold (seconds), Label }
local JOBS = {}
JobService.Jobs = JOBS
JobService.Order = { "Mail Carrier", "Gardener", "Barista", "Janitor", "Warehouse Worker", "Shelf Stocker" }

JOBS["Mail Carrier"] = { Emoji = "📬", Place = "PostOffice", Pay = 8, Bonus = 20, Desc = "Pick up the mail and deliver it to five houses.",
	Tasks = function(place, rng)
		local list = {}
		local shelf = partsNamed(place, { SortingShelf = true, POBoxes = true })[1]
		table.insert(list, { Pos = if shelf then shelf.Position else place.Inside, Text = "Pick up the mail", Action = "sort", Carry = "MailBag", Hold = 1 })
		local houses = {}
		for _, home in ipairs(S.Map.Homes) do
			local b = home.Building
			local box = b and b.Model and b.Model:FindFirstChild("Mailbox")
			if box and (home.Door - place.Door).Magnitude < 300 then
				table.insert(houses, { Box = box, Home = home, D = (home.Door - place.Door).Magnitude })
			end
		end
		table.sort(houses, function(a, b) return a.D < b.D end)
		for _, h in ipairs(pick({ table.unpack(houses, 1, math.min(12, #houses)) }, 5, rng)) do
			table.insert(list, { Pos = h.Box.Position, Text = "Deliver to " .. (h.Home.Address or "this house"), Action = "deliver", Carry = "MailBag", Hold = 1 })
		end
		return list
	end,
}
JOBS["Gardener"] = { Emoji = "🌱", Place = "Park", Pay = 6, Bonus = 15, Desc = "Water the flowerbeds, bushes and trees in Central Park.",
	Tasks = function(place, rng)
		local list = {}
		local plants = partsNamed(place, { FlowerBed = true, Bush = true, Trunk = true })
		for _, p in ipairs(pick(plants, 5, rng)) do
			table.insert(list, { Pos = p.Position, Text = "Water the " .. (if p.Name == "Trunk" then "tree" elseif p.Name == "Bush" then "bush" else "flowers"), Action = "water", Carry = "WateringCan", Hold = 1.5 })
		end
		return list
	end,
}
JOBS["Barista"] = { Emoji = "☕", Place = "Cafe", Pay = 7, Bonus = 15, Desc = "Make coffees at the espresso machine and serve them at the till.",
	Tasks = function(place, rng)
		local list = {}
		local machine = partsNamed(place, { EspressoMachine = true })[1]
		local till = partsNamed(place, { Register = true })[1]
		local drinks = { "a latte", "an espresso", "a cappuccino", "a hot chocolate", "an iced coffee" }
		for k = 1, 4 do
			table.insert(list, { Pos = if machine then machine.Position else place.Inside, Text = "Make " .. drinks[rng:NextInteger(1, #drinks)], Action = "brew", Carry = "Cup", Hold = 1.5 })
			table.insert(list, { Pos = if till then till.Position else place.Inside, Text = "Serve order #" .. k, Action = "pay", Carry = false, Hold = 0.6, Paid = true })
		end
		return list
	end,
}
JOBS["Janitor"] = { Emoji = "🧽", Place = "Office", Pay = 6, Bonus = 15, Desc = "Mop up the spills around the office floors.",
	Tasks = function(place, rng)
		local list = {}
		local desks = partsNamed(place, { Desk = true })
		local low = {}
		local base = place.Inside and place.Inside.Y or 0
		for _, d in ipairs(desks) do
			if d.Position.Y - base < 30 then -- the first few floors
				table.insert(low, d)
			end
		end
		for _, d in ipairs(pick(if #low > 0 then low else desks, 5, rng)) do
			local pos = d.Position - d.CFrame.LookVector * 3
			table.insert(list, { Pos = Vector3.new(pos.X, d.Position.Y - d.Size.Y / 2 - 2.5, pos.Z), Text = "Mop the spill", Action = "mop", Carry = false, Hold = 2, Spill = true })
		end
		return list
	end,
}
JOBS["Warehouse Worker"] = { Emoji = "📦", Place = "Warehouse", Pay = 7, Bonus = 15, Desc = "Carry crates from the loading area to the racking.",
	Tasks = function(place, rng)
		local list = {}
		local crates = partsNamed(place, { Crate = true, Pallet = true })
		local racks = partsNamed(place, { Racking = true })
		for _ = 1, 4 do
			local c = crates[rng:NextInteger(1, math.max(1, #crates))]
			local r = racks[rng:NextInteger(1, math.max(1, #racks))]
			table.insert(list, { Pos = if c then c.Position else place.Inside, Text = "Pick up a crate", Action = "carrybox", Carry = "Box", Hold = 1 })
			table.insert(list, { Pos = if r then r.Position else place.Inside, Text = "Stack it on the racking", Action = "shelve", Carry = false, Hold = 1.2, Paid = true })
		end
		return list
	end,
}
JOBS["Shelf Stocker"] = { Emoji = "🛒", Place = "Shop", Pay = 6, Bonus = 15, Desc = "Carry stock boxes from the back to the Market's shelves.",
	Tasks = function(place, rng)
		local list = {}
		local boxes = partsNamed(place, { StockBox = true })
		local shelves = partsNamed(place, { Shelf = true })
		for _ = 1, 4 do
			local b = boxes[rng:NextInteger(1, math.max(1, #boxes))]
			local sh = shelves[rng:NextInteger(1, math.max(1, #shelves))]
			table.insert(list, { Pos = if b then b.Position else place.Inside, Text = "Grab a stock box", Action = "carrybox", Carry = "Box", Hold = 1 })
			table.insert(list, { Pos = if sh then sh.Position else place.Inside, Text = "Stock the shelf", Action = "shelve", Carry = false, Hold = 1.5, Paid = true })
		end
		return list
	end,
}
-- pay on every task unless the job pays per finished order (Paid = true on those)
local function pays(shift, step)
	local any = false
	for _, t in ipairs(shift.Tasks) do
		if t.Paid then
			any = true
		end
	end
	return if any then step.Paid == true else true
end

--------------------------------------------------------------------------------
-- The marker for the current task
--------------------------------------------------------------------------------
local function clearMarker(shift)
	if shift.Marker then
		shift.Marker:Destroy()
		shift.Marker = nil
	end
end

local function status(player, shift, extra)
	local job = JOBS[shift.Job]
	local step = shift.Tasks[shift.Index]
	S.City.Send(player, { Type = "Job", Job = shift.Job, Emoji = job.Emoji, Step = shift.Index, Steps = #shift.Tasks, Task = step and step.Text, Earned = shift.Earned, Done = extra and extra.Done, Paid = extra and extra.Paid })
	player:SetAttribute("JobTask", step and step.Text or nil)
end

local showTask -- forward

local function finish(player, shift)
	local job = JOBS[shift.Job]
	clearMarker(shift)
	if shift.Folder then
		shift.Folder:Destroy()
	end
	shifts[player] = nil
	S.City.AddCoins(player, job.Bonus, job.Emoji .. " Shift bonus")
	shift.Earned += job.Bonus
	S.City.Toast(player, job.Emoji, "Shift complete!", "You earned " .. shift.Earned .. " coins as a " .. shift.Job .. ". Clock in again any time.", rgb(90, 200, 120))
	S.City.Send(player, { Type = "Job", Job = shift.Job, Emoji = job.Emoji, Finished = true, Earned = shift.Earned })
	S.City.Send(player, { Type = "Waypoint", Clear = true })
	player:SetAttribute("Job", nil)
	player:SetAttribute("JobTask", nil)
	if player.Character then
		player.Character:SetAttribute("Carry", nil)
	end
	if S.City.Progress then
		pcall(S.City.Progress, player, "work", 1)
	end
end

local function complete(player, shift)
	local job = JOBS[shift.Job]
	local step = shift.Tasks[shift.Index]
	local character = player.Character
	if character then
		-- everyone sees you do it (see Poses: WorkAction)
		character:SetAttribute("WorkAction", step.Action)
		task.delay(1.2, function()
			if character.Parent and character:GetAttribute("WorkAction") == step.Action then
				character:SetAttribute("WorkAction", nil)
			end
		end)
		if step.Carry ~= nil then
			character:SetAttribute("Carry", step.Carry or nil)
		end
	end
	local paid = 0
	if pays(shift, step) then
		paid = job.Pay
		S.City.AddCoins(player, paid, job.Emoji .. " " .. shift.Job)
		shift.Earned += paid
	end
	shift.Index += 1
	if shift.Index > #shift.Tasks then
		finish(player, shift)
	else
		showTask(player, shift)
		status(player, shift, { Paid = paid })
	end
end

showTask = function(player, shift)
	clearMarker(shift)
	local step = shift.Tasks[shift.Index]
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
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Job")
	prompt.Parent = marker
	prompt.Triggered:Connect(function(who)
		if who == player and shifts[player] == shift and shift.Tasks[shift.Index] == step then
			complete(player, shift)
		end
	end)
	-- only your own markers show up for you (see World: job prompts)
	marker.Parent = shift.Folder
	shift.Marker = marker
	S.City.Send(player, { Type = "Waypoint", Position = ground, Label = step.Text, Emoji = JOBS[shift.Job].Emoji })
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
	JobService.Quit(player, true)
	local rng = Random.new()
	local tasks = job.Tasks(place, rng)
	if #tasks == 0 then
		return { Ok = false, Error = "There's no work here right now." }
	end
	local folder = Instance.new("Folder")
	folder.Name = "JobMarkers_" .. player.UserId
	folder.Parent = workspace
	local shift = { Job = jobName, Tasks = tasks, Index = 1, Earned = 0, Folder = folder }
	shifts[player] = shift
	player:SetAttribute("Job", jobName)
	showTask(player, shift)
	status(player, shift)
	S.City.Toast(player, job.Emoji, "Clocked in: " .. jobName, job.Desc .. " Follow the marker.", rgb(240, 190, 60))
	return { Ok = true }
end

function JobService.Quit(player, quiet)
	local shift = shifts[player]
	if not shift then
		return { Ok = true }
	end
	clearMarker(shift)
	if shift.Folder then
		shift.Folder:Destroy()
	end
	shifts[player] = nil
	player:SetAttribute("Job", nil)
	player:SetAttribute("JobTask", nil)
	if player.Character then
		player.Character:SetAttribute("Carry", nil)
	end
	if not quiet then
		S.City.Send(player, { Type = "Job", Quit = true, Earned = shift.Earned, Job = shift.Job })
		S.City.Send(player, { Type = "Waypoint", Clear = true })
		S.City.Toast(player, "🕒", "Clocked out", "You earned " .. shift.Earned .. " coins this shift.", rgb(150, 150, 170))
	end
	return { Ok = true }
end

function JobService.Current(player)
	local shift = shifts[player]
	return shift and shift.Job
end

-- the Jobs app
local function listJobs(player)
	local out = {}
	for _, name in ipairs(JobService.Order) do
		local job = JOBS[name]
		local place = S.Map.Places[job.Place]
		local info = Config.PlaceById and Config.PlaceById[job.Place]
		table.insert(out, { Name = name, Emoji = job.Emoji, Pay = job.Pay, Bonus = job.Bonus, Desc = job.Desc, Place = (info and info.label) or job.Place, Position = place and place.Door })
	end
	return { Ok = true, Jobs = out, Current = JobService.Current(player) }
end

-- a "Clock in" prompt at every workplace
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
	post.CFrame = CFrame.new(at + Vector3.new(0, 4, 0))
	post.Transparency = 1
	post.Parent = place.Model or workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClockInPrompt"
	prompt.ActionText = "Work here"
	prompt.ObjectText = job.Emoji .. " " .. jobName .. " · " .. job.Pay .. " coins a task"
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
end

return JobService
