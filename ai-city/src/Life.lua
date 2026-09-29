-- Life (ModuleScript) — ServerScriptService.Modules.Life
-- Who lives in AI City: families with children, jobs, ages, couples expecting
-- babies and births, plus where each person should be at any hour.
-- Pure logic (no parts, no Humanoids), so it can be saved and tested on its own.
-- CitizenService uses it to spawn and move the actual NPCs.
--
--   local pop = Life.new(Config, homes)   -- homes = map.Homes
--   pop:Generate()                              -- the starting families (same every server)
--   local events = pop:NewDay(day)              -- ages, retirements, new jobs, pregnancies
--   pop:Birth(household, day)                   -- a baby is born (returns the baby)
--   pop:Plan(citizen, hour, day)                -- where they should be right now
--   pop:Serialize() / pop:Load(data)            -- for saving

local Life = {}
Life.__index = Life

-- Small deterministic random numbers (same results everywhere)
local function newRng(seed)
	local state = (seed % 2147483646) + 1
	local rng = {}
	function rng:Next()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function rng:Int(a, b)
		return a + math.floor(self:Next() * (b - a + 1))
	end
	function rng:Pick(list)
		return list[self:Int(1, #list)]
	end
	return rng
end

local function hash(...)
	local h = 5381
	for _, v in ipairs({ ... }) do
		local s = tostring(v)
		for k = 1, #s do
			h = (h * 33 + string.byte(s, k)) % 2147483647
		end
	end
	return h
end

function Life.new(config, homes)
	local self = setmetatable({}, Life)
	self.Config = config
	self.Homes = homes or {}
	self.Citizens = {} -- [id] = citizen
	self.List = {} -- citizens in order
	self.Households = {} -- [id] = { Id, Home, Last, Members = { ids }, Partners = { id, id }, Expecting = { DueDay, Carrier } }
	self.NextId = 1
	self.Day = 0
	self.JobsTaken = {} -- [job title] = count
	self.HomeUse = {} -- [home index] = household id
	self.rng = newRng(config.SEED or 1776)
	return self
end

--------------------------------------------------------------------------------
-- People
--------------------------------------------------------------------------------
function Life:Age(c, day)
	return math.max(0, math.floor(((day or self.Day) - c.BirthDay) / (self.Config.DAYS_PER_YEAR or 2)))
end

-- "Baby", "Toddler", "Child", "Teen", "Adult" or "Retired"
function Life:Stage(c, day)
	local age = self:Age(c, day)
	if age < 3 then
		return "Baby"
	elseif age < 6 then
		return "Toddler"
	elseif age < 13 then
		return "Child"
	elseif age < (self.Config.ADULT_AGE or 18) then
		return "Teen"
	elseif age < (self.Config.RETIRE_AGE or 67) then
		return "Adult"
	end
	return "Retired"
end

local function jobByTitle(config, title)
	for _, job in ipairs(config.Jobs) do
		if job.title == title then
			return job
		end
	end
	return nil
end

-- Gives an adult a job with a free slot (or leaves them unemployed).
function Life:AssignJob(c, rng)
	rng = rng or self.rng
	c.Job = nil
	if rng:Next() < (self.Config.UNEMPLOYED_CHANCE or 0) then
		return nil
	end
	local open, total = {}, 0
	for _, job in ipairs(self.Config.Jobs) do
		local free = job.slots - (self.JobsTaken[job.title] or 0)
		if free > 0 then
			table.insert(open, { job, free })
			total += free
		end
	end
	if total == 0 then
		return nil
	end
	local r = rng:Next() * total
	for _, entry in ipairs(open) do
		r -= entry[2]
		if r <= 0 then
			c.Job = entry[1].title
			self.JobsTaken[c.Job] = (self.JobsTaken[c.Job] or 0) + 1
			-- which of the place's work spots is theirs
			local n = 0
			for _, other in ipairs(self.List) do
				if other ~= c and other.Job and jobByTitle(self.Config, other.Job) and jobByTitle(self.Config, other.Job).place == entry[1].place then
					n += 1
				end
			end
			c.WorkSpot = n + 1
			return c.Job
		end
	end
	return nil
end

function Life:LeaveJob(c)
	if c.Job then
		self.JobsTaken[c.Job] = math.max(0, (self.JobsTaken[c.Job] or 1) - 1)
		c.Job = nil
		c.WorkSpot = nil
	end
end

function Life:AddCitizen(household, first, age, day, rng)
	rng = rng or self.rng
	local config = self.Config
	local c = {
		Id = self.NextId,
		First = first,
		Last = household.Last,
		Name = first .. " " .. household.Last,
		BirthDay = (day or self.Day) - age * (config.DAYS_PER_YEAR or 2) - rng:Int(0, (config.DAYS_PER_YEAR or 2) - 1),
		Household = household.Id,
		Hobby = rng:Pick(config.Hobbies),
		Punctual = rng:Next() * 0.15, -- a few extra in-game minutes some people leave early
	}
	self.NextId += 1
	self.Citizens[c.Id] = c
	table.insert(self.List, c)
	table.insert(household.Members, c.Id)
	local stage = self:Stage(c, day)
	if stage == "Adult" then
		self:AssignJob(c, rng)
	end
	return c
end

--------------------------------------------------------------------------------
-- Families and homes
--------------------------------------------------------------------------------
local function capacityOf(home)
	return home and (home.Capacity or 3) or 3
end

function Life:FindHome(size, rng)
	local best
	for index, home in ipairs(self.Homes) do
		if not self.HomeUse[index] and capacityOf(home) >= size then
			best = index
			if rng:Next() < 0.35 then
				break
			end
		end
	end
	if not best then
		-- city full: squeeze into any free home
		for index in ipairs(self.Homes) do
			if not self.HomeUse[index] then
				best = index
				break
			end
		end
	end
	return best
end

function Life:NewHousehold(last, rng)
	local h = { Id = #self.Households + 1, Last = last, Members = {}, Partners = {} }
	self.Households[h.Id] = h
	return h
end

-- The starting city: singles, couples, families with kids and retirees.
function Life:Generate()
	local config = self.Config
	local rng = newRng((config.SEED or 1776) * 7 + 3)
	local target = config.POPULATION or 42
	local usedNames = {}
	local function firstName()
		for _ = 1, 20 do
			local n = rng:Pick(config.FirstNames)
			if not usedNames[n] then
				usedNames[n] = true
				return n
			end
		end
		return rng:Pick(config.FirstNames)
	end
	local lasts = table.clone and table.clone(config.LastNames) or { table.unpack(config.LastNames) }
	local lastIndex = 0
	local function lastName()
		lastIndex += 1
		return lasts[((lastIndex - 1) % #lasts) + 1]
	end
	local adultMax = (config.RETIRE_AGE or 67) - 1
	while #self.List < target do
		local roll = rng:Next()
		local h = self:NewHousehold(lastName(), rng)
		local left = target - #self.List
		if roll < 0.25 or left < 2 then
			-- single adult
			self:AddCitizen(h, firstName(), rng:Int(19, adultMax), 0, rng)
		elseif roll < 0.5 then
			-- a couple
			local a = rng:Int(22, 60)
			local p1 = self:AddCitizen(h, firstName(), a, 0, rng)
			local p2 = self:AddCitizen(h, firstName(), math.clamp(a + rng:Int(-5, 5), 20, 65), 0, rng)
			h.Partners = { p1.Id, p2.Id }
		elseif roll < 0.88 then
			-- a family with kids
			local a = rng:Int(26, 48)
			local p1 = self:AddCitizen(h, firstName(), a, 0, rng)
			local p2 = self:AddCitizen(h, firstName(), math.clamp(a + rng:Int(-4, 4), 22, 55), 0, rng)
			h.Partners = { p1.Id, p2.Id }
			local kids = math.min(rng:Int(1, 3), math.max(0, target - #self.List))
			for _ = 1, kids do
				self:AddCitizen(h, firstName(), rng:Int(0, math.min(17, a - 20)), 0, rng)
			end
		else
			-- retirees
			local a = rng:Int(config.RETIRE_AGE or 67, 85)
			local p1 = self:AddCitizen(h, firstName(), a, 0, rng)
			if rng:Next() < 0.6 and target - #self.List >= 1 then
				local p2 = self:AddCitizen(h, firstName(), a + rng:Int(-3, 3), 0, rng)
				h.Partners = { p1.Id, p2.Id }
			end
		end
		h.Home = self:FindHome(#h.Members + 1, rng) -- room for a baby
		if h.Home then
			self.HomeUse[h.Home] = h.Id
		end
	end
	return self.List
end

--------------------------------------------------------------------------------
-- Time passing
--------------------------------------------------------------------------------
local function namesOf(self, ids)
	local out = {}
	for _, id in ipairs(ids) do
		table.insert(out, self.Citizens[id].First)
	end
	return table.concat(out, " & ")
end

-- Call once when a new in-game day starts. Returns a list of events:
-- { Kind = "Expecting"/"GrewUp"/"Retired"/"Birthday", Citizen/Household, Text }
function Life:NewDay(day)
	local config = self.Config
	self.Day = day
	local events = {}
	local rng = newRng(hash(config.SEED, "day", day))
	-- ages: new adults get jobs, retirees leave theirs
	for _, c in ipairs(self.List) do
		local stage = self:Stage(c, day)
		if stage ~= c.LastStage then
			if c.LastStage ~= nil then
				if stage == "Adult" then
					local job = self:AssignJob(c, rng)
					table.insert(events, { Kind = "GrewUp", Citizen = c, Text = "🎓 " .. c.Name .. " grew up" .. (if job then " and started work as a " .. job else "") .. "!" })
				elseif stage == "Retired" then
					self:LeaveJob(c)
					table.insert(events, { Kind = "Retired", Citizen = c, Text = "🎉 " .. c.Name .. " retired!" })
				else
					table.insert(events, { Kind = "GrewUp", Citizen = c, Text = "🎂 " .. c.Name .. " is now a " .. string.lower(stage) .. "!" })
				end
			end
			c.LastStage = stage
		end
	end
	-- couples may start expecting a baby
	if #self.List < (config.MAX_POPULATION or 100) then
		for _, h in ipairs(self.Households) do
			if not h.Expecting and #h.Partners == 2 then
				local a, b = self.Citizens[h.Partners[1]], self.Citizens[h.Partners[2]]
				local kids = #h.Members - 2
				local ok = true
				for _, p in ipairs({ a, b }) do
					local age = self:Age(p, day)
					if age < (config.PARENT_AGE_MIN or 21) or age > (config.PARENT_AGE_MAX or 45) then
						ok = false
					end
				end
				if ok and kids < (config.MAX_KIDS or 4) and rng:Next() < (config.BABY_CHANCE or 0.2) then
					h.Expecting = { StartDay = day, DueDay = day + (config.PREGNANCY_DAYS or 2), Carrier = h.Partners[rng:Int(1, 2)] }
					table.insert(events, { Kind = "Expecting", Household = h, Text = "🍼 " .. namesOf(self, h.Partners) .. " " .. h.Last .. " are expecting a baby!" })
				end
			end
		end
	end
	return events
end

-- Days until the baby arrives (nil if the household isn't expecting)
function Life:DaysToGo(household, day)
	if not household or not household.Expecting then
		return nil
	end
	return math.max(0, household.Expecting.DueDay - (day or self.Day))
end

-- Is it time? (the due day has come)
function Life:IsDue(household, day)
	return household.Expecting ~= nil and (day or self.Day) >= household.Expecting.DueDay
end

-- A baby is born into a household. Returns the baby.
function Life:Birth(household, day)
	day = day or self.Day
	local rng = newRng(hash(self.Config.SEED, "baby", household.Id, day, #household.Members))
	local taken = {}
	for _, c in ipairs(self.List) do
		taken[c.First] = true
	end
	local first
	for _ = 1, 30 do
		first = rng:Pick(self.Config.FirstNames)
		if not taken[first] then
			break
		end
	end
	local baby = self:AddCitizen(household, first, 0, day, rng)
	baby.BirthDay = day
	baby.LastStage = "Baby"
	household.Expecting = nil
	return baby
end

--------------------------------------------------------------------------------
-- Daily routine: where someone should be right now
-- Returns { Kind = "Home"/"Work"/"School"/"Place"/"Hobby"/"Hospital",
--           Place = place id (Work/School/Place/Hospital), Hobby = name,
--           Activity = short text for the nameplate }
--------------------------------------------------------------------------------
local ERRANDS = { "Shop", "Bakery", "Cafe", "Pharmacy", "Mall", "ToyStore", "Electronics", "Florist", "PetShop", "Bookstore", "IceCream", "Hardware", "Restaurant", "Library", "Cinema", "Gym", "Plaza", "Park", "Bank" }
local OUTINGS = { "Park", "Plaza", "Library", "Cafe", "IceCream", "SportsField", "Bookstore" }

local function inShift(hour, start, stop)
	if stop > start then
		return hour >= start and hour < stop
	end
	return hour >= start or hour < stop -- shifts past midnight
end

function Life:Plan(c, hour, day)
	local config = self.Config
	day = day or self.Day
	local stage = self:Stage(c, day)
	local h = self.Households[c.Household]
	local rng = newRng(hash(c.Id, day, "plan"))
	local errand = rng:Pick(ERRANDS)
	local outing = rng:Pick(OUTINGS)
	local hobbyOut = config.OutdoorHobbies and config.OutdoorHobbies[c.Hobby] and rng:Next() < 0.6

	-- the baby is due: the parents go to the hospital during the day
	if h and h.Expecting and self:IsDue(h, day) and (c.Id == h.Partners[1] or c.Id == h.Partners[2]) and hour >= 7 then
		return { Kind = "Hospital", Place = "Hospital", Activity = "🏥 Having a baby!" }
	end

	if stage == "Baby" or stage == "Toddler" then
		return { Kind = "Home", Activity = if stage == "Baby" then "🍼 Napping" else "🧸 Playing at home" }
	end

	-- under-13s go to bed early; teens stay up until the adult bedtime
	local bedtime = if stage == "Child" then (config.KIDS_BEDTIME or 20) else (config.ADULT_BEDTIME or 22)
	local wake = config.WAKE_UP or 6.5
	-- how long before a start time to leave home: the walk plus spare time
	local leave = (c.CommuteHours or 0.5) + (config.COMMUTE_BUFFER or 0.25) + (c.Punctual or 0)
	if stage == "Child" or stage == "Teen" then
		local s, e = config.SCHOOL_START or 8, config.SCHOOL_END or 15
		if hour >= s - leave and hour < e then
			-- morning recess and lunch on the playground
			if (hour >= s + 2 and hour < s + 2.5) or (hour >= s + 4 and hour < s + 4.75) then
				return { Kind = "School", Place = "School", Recess = true, Activity = "🛝 Recess" }
			end
			return { Kind = "School", Place = "School", Activity = "📚 At school" }
		elseif hour >= e and hour < e + 3 and rng:Next() < 0.7 then
			local where = if stage == "Child" then "Park" else outing
			return { Kind = "Place", Place = where, Activity = "🛝 Hanging out" }
		end
		return { Kind = "Home", Activity = if hour >= bedtime or hour < wake then "💤 Sleeping" else "🏠 At home" }
	end

	-- work comes first: early bakers and night officers keep their hours
	local job = stage == "Adult" and c.Job and jobByTitle(config, c.Job)
	if job then
		if inShift(hour, (job.start - leave) % 24, math.min(job.stop, 24) % 24) then
			return { Kind = "Work", Place = job.place, Activity = "💼 Working (" .. c.Job .. ")" }
		end
	end

	if hour >= bedtime or hour < wake then
		return { Kind = "Home", Activity = "💤 Sleeping" }
	end

	if job then
		do
			-- free time: before or after the shift
			if hour < job.start then
				if hour < 9 then
					return { Kind = "Home", Activity = "☕ Getting ready" }
				end
				if hobbyOut then
					return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
				end
				return { Kind = "Place", Place = errand, Activity = "🛍️ Running errands" }
			end
			if hour < job.stop + 3 then
				if hobbyOut then
					return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
				end
				return { Kind = "Place", Place = errand, Activity = "🛍️ After work" }
			end
			return { Kind = "Home", Activity = "🏠 Relaxing at home" }
		end
	end

	-- no job (unemployed or retired): a relaxed day around town
	if hour < 9.5 then
		return { Kind = "Home", Activity = "☕ Slow morning" }
	elseif hour < 12.5 then
		return { Kind = "Place", Place = errand, Activity = "🛍️ Running errands" }
	elseif hour < 17 then
		if hobbyOut then
			return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
		end
		return { Kind = "Place", Place = if stage == "Retired" then rng:Pick({ "Park", "Library", "Plaza", "Cafe" }) else outing, Activity = "🌳 Out and about" }
	elseif hour < 20 then
		return { Kind = "Place", Place = rng:Pick({ "Plaza", "Restaurant", "Cinema", "Park" }), Activity = "🌆 Evening out" }
	end
	return { Kind = "Home", Activity = "🏠 At home" }
end

--------------------------------------------------------------------------------
-- Saving
--------------------------------------------------------------------------------
function Life:Serialize()
	local data = { Day = self.Day, NextId = self.NextId, Citizens = {}, Households = {} }
	for _, c in ipairs(self.List) do
		table.insert(data.Citizens, { c.Id, c.First, c.Last, c.BirthDay, c.Household, c.Job or false, c.Hobby, c.WorkSpot or 0, c.Punctual })
	end
	for _, h in ipairs(self.Households) do
		table.insert(data.Households, { h.Id, h.Last, h.Home or 0, h.Members, h.Partners, h.Expecting or false })
	end
	return data
end

function Life:Load(data)
	if type(data) ~= "table" or type(data.Citizens) ~= "table" then
		return false
	end
	self.Citizens, self.List, self.Households, self.JobsTaken, self.HomeUse = {}, {}, {}, {}, {}
	self.Day = data.Day or 0
	self.NextId = data.NextId or 1
	for _, row in ipairs(data.Households) do
		local h = { Id = row[1], Last = row[2], Home = if row[3] ~= 0 then row[3] else nil, Members = row[4] or {}, Partners = row[5] or {}, Expecting = row[6] or nil }
		self.Households[h.Id] = h
		if h.Home then
			self.HomeUse[h.Home] = h.Id
		end
	end
	for _, row in ipairs(data.Citizens) do
		local c = { Id = row[1], First = row[2], Last = row[3], BirthDay = row[4], Household = row[5], Job = row[6] or nil, Hobby = row[7], WorkSpot = if row[8] ~= 0 then row[8] else nil, Punctual = row[9] or 0.3 }
		c.Name = c.First .. " " .. c.Last
		if c.Job and not jobByTitle(self.Config, c.Job) then
			c.Job = nil -- that job was removed from Config
		end
		if c.Job then
			self.JobsTaken[c.Job] = (self.JobsTaken[c.Job] or 0) + 1
		end
		c.LastStage = self:Stage(c, self.Day)
		self.Citizens[c.Id] = c
		table.insert(self.List, c)
	end
	return true
end

Life.Jobs = jobByTitle
return Life
