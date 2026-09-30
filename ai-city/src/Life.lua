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
--   pop:SchoolFor(citizen) / pop:WeekdayName(day) / pop:IsWeekend(day)
--   pop:Serialize() / pop:Load(data)            -- for saving
--
-- Every citizen also has a personality (cheerful, shy, grumpy...), values
-- (what they care about in elections), a favorite spot and a few friends.

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

-- Personalities change how people talk, walk and spend free time
Life.Personalities = { "cheerful", "shy", "grumpy", "chatty", "bookish", "sporty", "artsy", "curious", "calm", "funny", "brave", "anxious", "romantic", "ambitious", "lazy", "sarcastic", "kind", "nosy", "adventurous", "proud" }
Life.PersonalityInfo = {
	cheerful = { Emoji = "😊", Walk = 1.05, Chat = 0.7, Expression = "happy" },
	shy = { Emoji = "😳", Walk = 0.95, Chat = 0.2, Expression = "neutral" },
	grumpy = { Emoji = "😒", Walk = 1.0, Chat = 0.25, Expression = "focused" },
	chatty = { Emoji = "🗣️", Walk = 0.97, Chat = 0.95, Expression = "happy" },
	bookish = { Emoji = "🤓", Walk = 0.95, Chat = 0.35, Expression = "neutral" },
	sporty = { Emoji = "💪", Walk = 1.12, Chat = 0.5, Expression = "happy" },
	artsy = { Emoji = "🎨", Walk = 0.97, Chat = 0.55, Expression = "neutral" },
	curious = { Emoji = "🧐", Walk = 1.0, Chat = 0.65, Expression = "neutral" },
	calm = { Emoji = "😌", Walk = 0.92, Chat = 0.45, Expression = "neutral" },
	funny = { Emoji = "😄", Walk = 1.03, Chat = 0.8, Expression = "grin" },
	brave = { Emoji = "🦁", Walk = 1.06, Chat = 0.5, Expression = "focused" },
	anxious = { Emoji = "😰", Walk = 1.08, Chat = 0.25, Expression = "neutral" },
	romantic = { Emoji = "💘", Walk = 0.95, Chat = 0.7, Expression = "happy" },
	ambitious = { Emoji = "📈", Walk = 1.12, Chat = 0.45, Expression = "focused" },
	lazy = { Emoji = "🥱", Walk = 0.85, Chat = 0.4, Expression = "neutral" },
	sarcastic = { Emoji = "🙄", Walk = 1.0, Chat = 0.55, Expression = "neutral" },
	kind = { Emoji = "🤗", Walk = 0.98, Chat = 0.7, Expression = "happy" },
	nosy = { Emoji = "👀", Walk = 1.0, Chat = 0.9, Expression = "neutral" },
	adventurous = { Emoji = "🧭", Walk = 1.1, Chat = 0.6, Expression = "happy" },
	proud = { Emoji = "👑", Walk = 1.0, Chat = 0.5, Expression = "neutral" },
}
Life.Weekdays = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }

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

function Life:WeekdayName(day)
	return Life.Weekdays[((day or self.Day) % 7) + 1]
end

-- Saturdays and Sundays: no school, and offices, banks and the town hall are closed
function Life:IsWeekend(day)
	return self.Config.WEEKENDS ~= false and ((day or self.Day) % 7) >= 5
end

-- Which school a kid goes to (nil if they're too young or too old)
function Life:SchoolFor(c, day)
	local age = self:Age(c, day)
	for _, school in ipairs(self.Config.Schools or {}) do
		if age >= school.minAge and age <= school.maxAge then
			return school.place, school.label
		end
	end
	if age >= 6 and age < (self.Config.ADULT_AGE or 18) then
		return "School", "School"
	end
	return nil
end

-- Jobs that follow office hours and close on weekends
local WEEKDAY_ONLY = { Office = true, Bank = true, TownHall = true, School = true, MiddleSchool = true, HighSchool = true, Daycare = true, PostOffice = true, Factory = true, Warehouse = true }

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
	-- places with nobody working there yet come first (so every shop has
	-- someone behind the till, every school a teacher...)
	local staffed = {}
	for _, job in ipairs(self.Config.Jobs) do
		if (self.JobsTaken[job.title] or 0) > 0 then
			staffed[job.place] = true
		end
	end
	local open, total = {}, 0
	for _, job in ipairs(self.Config.Jobs) do
		local free = job.slots - (self.JobsTaken[job.title] or 0)
		if free > 0 then
			local weight = if staffed[job.place] then free else free * 4
			table.insert(open, { job, weight })
			total += weight
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
		Personality = rng:Pick(Life.Personalities),
		Values = {},
		Friends = {},
	}
	-- what they care about (-1..1 for each of Config.ValueNames)
	for _, v in ipairs(config.ValueNames or {}) do
		c.Values[v] = math.floor((rng:Next() * 2 - 1) * 100) / 100
	end
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

-- how far a home is from downtown (families prefer living closer in, so
-- nobody has an hour-long walk to work on a big map)
local function distanceOut(home)
	local d = home and home.Door
	if not d then
		return 0
	end
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

function Life:FindHome(size, rng)
	local best
	local fits = {}
	for index, home in ipairs(self.Homes) do
		if not self.HomeUse[index] and capacityOf(home) >= size then
			table.insert(fits, index)
		end
	end
	if #fits > 0 then
		table.sort(fits, function(a, b)
			return distanceOut(self.Homes[a]) < distanceOut(self.Homes[b])
		end)
		-- one of the closest few (not always the very closest)
		best = fits[math.min(#fits, 1 + math.floor(rng:Next() * math.min(6, #fits)))]
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
		if roll < 0.17 or left < 2 then
			-- single adult
			self:AddCitizen(h, firstName(), rng:Int(19, adultMax), 0, rng)
		elseif roll < 0.33 then
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
	self:MakeFriends(rng)
	return self.List
end

-- Friends: classmates, coworkers and people around the same age
function Life:MakeFriends(rng)
	rng = rng or newRng((self.Config.SEED or 1776) + 99)
	local function groupOf(c)
		local school = self:SchoolFor(c)
		if school then
			return "school:" .. school
		end
		local job = c.Job and jobByTitle(self.Config, c.Job)
		if job then
			return "work:" .. job.place
		end
		return "age:" .. math.floor(self:Age(c) / 15)
	end
	local groups = {}
	for _, c in ipairs(self.List) do
		if self:Age(c) >= 4 then
			local g = groupOf(c)
			groups[g] = groups[g] or {}
			table.insert(groups[g], c)
		end
	end
	for _, c in ipairs(self.List) do
		local g = groups[groupOf(c)]
		if g and #c.Friends < 3 then
			for _ = 1, 4 do
				local other = g[rng:Int(1, #g)]
				if other ~= c and other.Household ~= c.Household and #other.Friends < 4 and not table.find(c.Friends, other.Id) then
					table.insert(c.Friends, other.Id)
					table.insert(other.Friends, c.Id)
					if #c.Friends >= 3 then
						break
					end
				end
			end
		end
	end
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
	household.Newborn = day
	return baby
end

--------------------------------------------------------------------------------
-- Daily routine: where someone should be right now
-- Returns { Kind = "Home"/"Work"/"School"/"Place"/"Hobby"/"Hospital",
--           Place = place id, Hobby = name, Activity = text for the nameplate,
--           Want = the action they'd like to do there ("soccer", "lift", "swing"...),
--           Recess = true on the school playground, Family = true on family outings }
-- Everyone's day is a little different: it depends on the day, their
-- personality, their hobby and their age.
--------------------------------------------------------------------------------
local ERRANDS = { "Shop", "Bakery", "Cafe", "Pharmacy", "Mall", "ToyStore", "Electronics", "Florist", "PetShop", "Bookstore", "IceCream", "Hardware", "Bank", "PostOffice", "Library" }
local HANGOUTS = { "Cafe", "Diner", "Restaurant", "Plaza", "IceCream", "Bakery" }
local FAMILY_OUTINGS = {
	{ "Park", "🌳 Family day at the park", "play" },
	{ "WillowPark", "🌿 Picnic at Willow Park", "sit" },
	{ "Lake", "🎣 Fishing trip at the lake", "fish" },
	{ "Museum", "🏺 Family museum visit", "browse" },
	{ "Cinema", "🎬 Family movie", "watch" },
	{ "IceCream", "🍦 Ice cream with the family", "eat" },
	{ "SportsField", "⚽ Watching the kids play", "cheer" },
	{ "Plaza", "⛲ Family walk downtown", "chat" },
}

local function inShift(hour, start, stop)
	if stop > start then
		return hour >= start and hour < stop
	end
	return hour >= start or hour < stop -- shifts past midnight
end

local function home(activity, want)
	return { Kind = "Home", Activity = activity, Want = want }
end

-- a citizen's partner (the other half of their household's couple), unless they broke up
function Life:PartnerOf(c)
	local h = self.Households[c.Household]
	if not h or not h.Partners or #h.Partners ~= 2 then
		return nil
	end
	local other = if h.Partners[1] == c.Id then h.Partners[2] elseif h.Partners[2] == c.Id then h.Partners[1] else nil
	return other and self.Citizens[other] or nil
end

-- free in the evening? (not at work at that hour)
local function freeAt(self, c, hour, day)
	local stage = self:Stage(c, day)
	if stage ~= "Adult" and stage ~= "Retired" then
		return false
	end
	local job = stage == "Adult" and c.Job and jobByTitle(self.Config, c.Job)
	return not job or hour >= job.stop or hour < job.start - 1
end

local CHEATERS = { romantic = 1.4, adventurous = 1.3, sarcastic = 1.1, lazy = 1, proud = 1.1, funny = 0.8, chatty = 0.8 }
-- someone sneaking off with a friend behind their partner's back tonight?
-- (both of them work it out the same way, so they meet at the same place)
function Life:AffairTonight(c, hour, day)
	if (self.Config.CHEATING_CHANCE or 0.05) <= 0 then
		return nil
	end
	local slot = math.floor(hour / 1.5)
	for _, id in ipairs(c.Friends or {}) do
		local f = self.Citizens[id]
		if f and f.Household ~= c.Household and freeAt(self, c, hour, day) and freeAt(self, f, hour, day) then
			local pc, pf = self:PartnerOf(c), self:PartnerOf(f)
			local temper = math.max(CHEATERS[c.Personality or ""] or 0.3, CHEATERS[f.Personality or ""] or 0.3)
			if (pc or pf) and pc ~= f then
				local lo, hi = math.min(c.Id, id), math.max(c.Id, id)
				local r = newRng(hash(lo, hi, day, "affair", slot))
				if r:Next() < (self.Config.CHEATING_CHANCE or 0.05) * temper then
					return f, r:Pick({ "Park", "Lake", "Cafe", "WillowPark", "Plaza" })
				end
			end
		end
	end
	return nil
end

function Life:Plan(c, hour, day)
	local config = self.Config
	day = day or self.Day
	local stage = self:Stage(c, day)
	local age = self:Age(c, day)
	local h = self.Households[c.Household]
	local rng = newRng(hash(c.Id, day, "plan"))
	local weekend = self:IsWeekend(day)
	local personality = c.Personality or "calm"
	local sporty = personality == "sporty" or c.Hobby == "jogging"
	local bookish = personality == "bookish" or c.Hobby == "reading"
	local hobbyOut = config.OutdoorHobbies and config.OutdoorHobbies[c.Hobby] and rng:Next() < 0.6
	local wake = config.WAKE_UP or 6.5
	-- under-13s go to bed early; teens stay up until the adult bedtime
	local bedtime = if stage == "Child" or stage == "Toddler" or stage == "Baby" then (config.KIDS_BEDTIME or 20) else (config.ADULT_BEDTIME or 22)
	bedtime += if stage == "Adult" or stage == "Teen" then rng:Next() * 0.6 else 0
	-- how long before a start time to leave home: the walk plus spare time
	local leave = (c.CommuteHours or 0.5) + (config.COMMUTE_BUFFER or 0.25) + (c.Punctual or 0)
	-- the family's weekend outing (the whole household picks the same one)
	local familyRng = newRng(hash(c.Household, day, "outing"))
	local outing = familyRng:Pick(FAMILY_OUTINGS)
	local outingStart = 13 + familyRng:Int(0, 2)
	local isFamily = h and #h.Members > 1

	-- the baby is due: the parents go to the hospital during the day
	if h and h.Expecting and self:IsDue(h, day) and (c.Id == h.Partners[1] or c.Id == h.Partners[2]) and hour >= 7 then
		return { Kind = "Hospital", Place = "Hospital", Activity = "🏥 Having a baby!" }
	end

	-- sleeping
	if hour >= bedtime or hour < wake + (if weekend then 1 else 0) then
		-- early bakers and night officers are already (or still) at work
		local job = stage == "Adult" and c.Job and jobByTitle(config, c.Job)
		if job and weekend and WEEKDAY_ONLY[job.place] then
			job = nil
		end
		if not (job and inShift(hour, (job.start - leave) % 24, math.min(job.stop, 24) % 24)) then
			return home("💤 Sleeping", "sleep")
		end
	end

	-- family dinner, every evening
	local dinner = 18.25 + (hash(c.Household, day) % 4) * 0.25
	local function dinnerTime()
		return hour >= dinner and hour < dinner + 0.75
	end

	if stage == "Baby" then
		-- babies stay home (someone's always looking after them)
		if hour >= 12.5 and hour < 14.5 then
			return home("🍼 Napping", "nap")
		end
		return home(if age < 1 then "🍼 Being a baby" else "🧸 Playing at home", if age < 1 then "nap" else "crawl")
	end

	-- a new baby today: the parents take it home and stay in
	if h and h.Newborn == day and (c.Id == h.Partners[1] or c.Id == h.Partners[2]) then
		return home("👶 Home with the new baby", "sit")
	end

	if stage == "Toddler" then
		if not weekend and age >= (config.DAYCARE_AGE or 3) and hour >= 7.75 and hour < 16.5 then
			if hour >= 12.5 and hour < 14 then
				return { Kind = "Place", Place = "Daycare", Activity = "😴 Nap time at daycare", Want = "nap" }
			end
			return { Kind = "Place", Place = "Daycare", Activity = "🧸 At daycare", Want = "play" }
		end
		if weekend and isFamily and hour >= outingStart and hour < outingStart + 3 then
			return { Kind = "Place", Place = outing[1], Activity = outing[2], Family = true, Want = "play" }
		end
		if dinnerTime() then
			return home("🍽️ Family dinner", "eat")
		end
		return home("🧸 Playing at home", "crawl")
	end

	if stage == "Child" or stage == "Teen" then
		local teen = stage == "Teen"
		local school, label = self:SchoolFor(c, day)
		local s, e = config.SCHOOL_START or 8, config.SCHOOL_END or 15
		if not weekend and school then
			if hour >= s - leave and hour < e then
				-- morning recess and lunch on the playground or the court
				if (hour >= s + 2 and hour < s + 2.5) or (hour >= s + 4 and hour < s + 4.75) then
					return { Kind = "School", Place = school, Recess = true, Activity = if teen then "🏀 Lunch break" else "🛝 Recess", Want = if teen then "hoops" else "play" }
				end
				return { Kind = "School", Place = school, Activity = "📚 At " .. (label or "school"), Want = "study" }
			end
			-- after school: sports, the playground, the arcade, the library...
			if hour >= e and hour < e + 2.5 then
				local roll = rng:Next()
				if sporty or roll < 0.3 then
					if rng:Next() < 0.65 then
						return { Kind = "Place", Place = "SportsField", Activity = "⚽ Soccer after school", Want = "soccer" }
					end
					return { Kind = "Place", Place = if teen then "HighSchool" else "MiddleSchool", Activity = "🏀 Shooting hoops", Want = "hoops" }
				elseif bookish or roll < 0.42 then
					return { Kind = "Place", Place = "Library", Activity = "📖 Homework at the library", Want = "study" }
				elseif teen then
					local where = ({ "Arcade", "Diner", "IceCream", "Mall", "Plaza", "Arcade" })[rng:Int(1, 6)]
					return { Kind = "Place", Place = where, Activity = "😎 Hanging out with friends", Want = if where == "Arcade" then "game" else "chat" }
				end
				return { Kind = "Place", Place = if rng:Next() < 0.5 then "Park" else "WillowPark", Activity = "🛝 At the playground", Want = if rng:Next() < 0.5 then "swing" else "play" }
			end
			if hour >= e + 2.5 and hour < dinner then
				return home("📝 Homework", "study")
			end
		elseif weekend then
			-- weekend mornings: Saturday soccer, cartoons, sleeping in
			if hour < 12 then
				if (sporty or rng:Next() < 0.4) and hour >= 9 then
					return { Kind = "Place", Place = "SportsField", Activity = "⚽ Weekend soccer", Want = "soccer" }
				end
				return home(if teen then "📱 Sleeping in" else "📺 Weekend cartoons", if teen then "phone" else "tv")
			end
			if isFamily and hour >= outingStart and hour < outingStart + 3 then
				return { Kind = "Place", Place = outing[1], Activity = outing[2], Family = true, Want = outing[3] }
			end
			if teen and hour >= 12 and hour < 18 then
				local where = ({ "Arcade", "Mall", "Cinema", "Plaza", "Lake", "Gym" })[rng:Int(1, 6)]
				return { Kind = "Place", Place = where, Activity = "😎 Out with friends", Want = if where == "Arcade" then "game" elseif where == "Gym" then "lift" else nil }
			end
			if hour >= 12 and hour < 17 then
				return { Kind = "Place", Place = if rng:Next() < 0.5 then "Park" else "WillowPark", Activity = "🛝 Playing outside", Want = "play" }
			end
		end
		if dinnerTime() then
			return home("🍽️ Family dinner", "eat")
		end
		return home(if teen then "🎮 Gaming at home" else "🧸 Playing at home", if teen then "game" else "tv")
	end

	-- work comes first: early bakers and night officers keep their hours
	local job = stage == "Adult" and c.Job and jobByTitle(config, c.Job)
	if job and weekend and WEEKDAY_ONLY[job.place] then
		job = nil -- a day off
	end
	if job and inShift(hour, (job.start - leave) % 24, math.min(job.stop, 24) % 24) then
		-- a lunch break in the middle of long shifts
		local mid = job.start + (job.stop - job.start) / 2
		if job.stop - job.start >= 8 and hour >= mid and hour < mid + 0.5 and rng:Next() < 0.5 then
			return { Kind = "Place", Place = rng:Pick({ "Cafe", "Diner", "Bakery", "Plaza" }), Activity = "🥪 Lunch break", Want = "eat", Lunch = true, WorkPlace = job.place }
		end
		return { Kind = "Work", Place = job.place, Activity = "💼 " .. c.Job }
	end

	-- morning routine
	if hour < wake + 1 then
		if sporty and hour >= wake then
			return { Kind = "Hobby", Hobby = "jogging", Activity = "🏃 Morning jog", Want = "run" }
		end
		return home("☕ Breakfast", "eat")
	end

	if dinnerTime() and isFamily then
		return home("🍽️ Family dinner", "eat")
	end

	-- weekends: family time, errands, fun
	if weekend and stage == "Adult" then
		if isFamily and hour >= outingStart and hour < outingStart + 3 then
			return { Kind = "Place", Place = outing[1], Activity = outing[2], Family = true, Want = outing[3] }
		end
		if hour < 11 then
			return if rng:Next() < 0.5 then home("☕ Slow weekend morning", "coffee") else { Kind = "Place", Place = rng:Pick({ "Bakery", "Cafe", "Shop" }), Activity = "🥐 Weekend errands" }
		elseif hour < 17 then
			if hobbyOut then
				return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
			end
			if sporty then
				return { Kind = "Place", Place = if rng:Next() < 0.5 then "Gym" else "SportsField", Activity = "💪 Weekend workout", Want = if rng:Next() < 0.5 then "lift" else "run" }
			end
			return { Kind = "Place", Place = rng:Pick(ERRANDS), Activity = "🛍️ Shopping" }
		elseif hour < 21 then
			local where = rng:Pick({ "Restaurant", "Cinema", "Plaza", "Diner" })
			return { Kind = "Place", Place = where, Activity = if where == "Plaza" then "💃 Evening at the plaza" else "🌆 Night out", Want = if where == "Plaza" then "dance" else nil }
		end
		return home("📺 Relaxing at home", "tv")
	end

	if stage == "Retired" then
		-- a relaxed day: walks, chess, fishing, a nap, the community center
		if hour < 10 then
			return { Kind = "Place", Place = rng:Pick({ "Park", "WillowPark", "Bakery", "Cafe" }), Activity = "🚶 Morning walk", Want = "sit" }
		elseif hour < 12.5 then
			if hobbyOut then
				return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
			end
			return { Kind = "Place", Place = rng:Pick({ "Plaza", "Library", "CommunityCenter", "Museum" }), Activity = "☀️ Out and about" }
		elseif hour < 14 then
			return home("😴 Afternoon nap", "sleep")
		elseif hour < 17.5 then
			if rng:Next() < 0.35 then
				return { Kind = "Place", Place = "Lake", Activity = "🎣 Fishing", Want = "fish" }
			end
			return { Kind = "Place", Place = rng:Pick({ "Park", "CommunityCenter", "Plaza", "Cafe" }), Activity = "🌳 Afternoon out" }
		end
		return home("📺 Evening at home", "tv")
	end

	-- a working adult's free time: before or after the shift
	if job and hour < job.start then
		if hour < 9 then
			return home("☕ Getting ready", "coffee")
		end
		if hobbyOut then
			return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
		end
		return { Kind = "Place", Place = rng:Pick(ERRANDS), Activity = "🛍️ Running errands" }
	end
	if hour < 21 then
		-- plans change through the evening (a new choice every 1.5 hours)
		local evening = newRng(hash(c.Id, day, "evening", math.floor(hour / 1.5)))
		local roll = evening:Next()
		rng = evening
		-- just broke up: staying in
		if c.Heartbroken and day - c.Heartbroken <= 1 then
			return home("💔 Heartbroken", "sit")
		end
		-- an affair: sneaking off to meet someone
		local lover, loverPlace = self:AffairTonight(c, hour, day)
		if lover then
			return { Kind = "Place", Place = loverPlace, Activity = "🤫 Meeting " .. lover.First, Want = "chat", Affair = lover.Id }
		end
		local partner = self:PartnerOf(c)
		if partner and freeAt(self, partner, hour, day) then
			-- a hunch: following a partner who's been acting strange
			local theirLover, theirPlace = self:AffairTonight(partner, hour, day)
			if theirLover and (personality == "nosy" or personality == "anxious" or personality == "proud" or evening:Next() < 0.35) then
				return { Kind = "Place", Place = theirPlace, Activity = "🕵️ Following a hunch", Want = "sit", Suspect = partner.Id }
			end
			-- date night (the couple pick it together)
			if not theirLover then
				local dr = newRng(hash(c.Household, day, "date", math.floor(hour / 1.5)))
				local romantic = personality == "romantic" or partner.Personality == "romantic"
				if dr:Next() < (self.Config.DATE_CHANCE or 0.2) * (if romantic then 1.8 else 1) then
					local pick = dr:Pick({ { "Restaurant", "eat" }, { "Lake", nil }, { "Park", "sit" }, { "Cinema", "watch" }, { "Cafe", "coffee" } })
					return { Kind = "Place", Place = pick[1], Activity = "💕 Date night with " .. partner.First, Want = pick[2], Date = partner.Id }
				end
			end
		end
		-- personalities have their own habits
		if personality == "lazy" and roll < 0.7 then
			return home("🛋️ Lazing on the sofa", "tv")
		elseif personality == "kind" and roll < 0.35 then
			return { Kind = "Place", Place = "CommunityCenter", Activity = "🤗 Volunteering", Want = "chat" }
		elseif personality == "romantic" and roll < 0.35 then
			return { Kind = "Place", Place = rng:Pick({ "Restaurant", "Lake", "Park" }), Activity = "💘 A romantic evening", Want = if rng:Next() < 0.5 then "sit" else nil }
		elseif personality == "adventurous" and roll < 0.4 then
			return { Kind = "Place", Place = rng:Pick({ "Lake", "WillowPark", "Park", "Museum" }), Activity = "🧭 Exploring", Want = nil }
		elseif personality == "ambitious" and roll < 0.35 and job then
			return { Kind = "Place", Place = "Library", Activity = "📈 Studying for a promotion", Want = "study" }
		elseif personality == "nosy" and roll < 0.4 then
			return { Kind = "Place", Place = "Plaza", Activity = "👀 Keeping an eye on things", Want = "sit" }
		elseif personality == "anxious" and roll < 0.5 then
			return home("😰 Staying in where it's safe", "read")
		end
		if sporty and roll < 0.3 and age < 50 then
			-- pickup basketball at the community center (see SportsService)
			return { Kind = "Place", Place = "CommunityCenter", Activity = "🏀 Pickup basketball", Want = "hoops" }
		elseif sporty and roll < 0.6 then
			return { Kind = "Place", Place = "Gym", Activity = "🏋️ At the gym", Want = rng:Pick({ "run", "lift", "squat", "punch", "yoga" }) }
		elseif hobbyOut and roll < 0.7 then
			return { Kind = "Hobby", Hobby = c.Hobby, Activity = "🎨 " .. c.Hobby }
		elseif #c.Friends > 0 and roll < 0.85 then
			return { Kind = "Place", Place = rng:Pick(HANGOUTS), Activity = "☕ Meeting a friend", Want = "chat" }
		elseif roll < 0.95 then
			return { Kind = "Place", Place = rng:Pick(ERRANDS), Activity = "🛍️ After work" }
		end
		return home("📺 Relaxing at home", "tv")
	end
	return home(if bookish then "📖 Reading in bed" else "📺 Relaxing at home", if bookish then "read" else "tv")
end

--------------------------------------------------------------------------------
-- Saving
--------------------------------------------------------------------------------
function Life:Serialize()
	local data = { Day = self.Day, NextId = self.NextId, Citizens = {}, Households = {} }
	for _, c in ipairs(self.List) do
		table.insert(data.Citizens, { c.Id, c.First, c.Last, c.BirthDay, c.Household, c.Job or false, c.Hobby, c.WorkSpot or 0, c.Punctual, c.Personality, c.Values, c.Friends })
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
		local c = { Id = row[1], First = row[2], Last = row[3], BirthDay = row[4], Household = row[5], Job = row[6] or nil, Hobby = row[7], WorkSpot = if row[8] ~= 0 then row[8] else nil, Punctual = row[9] or 0.3, Personality = row[10], Values = row[11] or {}, Friends = row[12] or {} }
		if not c.Personality then
			local rng = newRng(hash(c.Id, c.First, "personality"))
			c.Personality = rng:Pick(Life.Personalities)
			for _, v in ipairs(self.Config.ValueNames or {}) do
				c.Values[v] = math.floor((rng:Next() * 2 - 1) * 100) / 100
			end
		end
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
