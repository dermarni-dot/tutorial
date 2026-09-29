-- DialogueService (ModuleScript) — ServerScriptService.Modules.DialogueService
-- Talking to citizens. Walk up to anyone and press E to talk: they stop what
-- they're doing, turn to you and answer in their own voice. What they say
-- depends on their personality (cheerful, shy, grumpy, chatty, bookish,
-- sporty, artsy, curious, calm, funny), their mood, their job or school, what
-- they're doing right now, the city's mood, the mayor, and what they remember
-- about you (gifts, speeches, jokes... and crimes).
--
-- Also writes the little conversations citizens have with each other
-- (SmallTalk) and their greetings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DialogueService = {}
local S
local sessions = {} -- [player] = { Brain, Last, Depth, Used = {} }
local chattedToday = {} -- ["citizenId:userId"] = day

local function pick(list, rng)
	if rng then
		return list[rng:NextInteger(1, #list)]
	end
	return list[math.random(1, #list)]
end

local function fill(text, vars)
	return (string.gsub(text, "{(%w+)}", function(k)
		return tostring(vars[k] or "")
	end))
end

local function lower(s)
	return string.lower(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- the text after an emoji ("💼 Working" -> "working")
local function activityText(activity)
	local text = string.match(activity or "", "^[^%w]*(.-)$") or ""
	return if text == "" then "just hanging around" else lower(text)
end

local function placeLabel(id)
	local info = Config.PlaceById[id]
	return info and info.label or id
end

local function formatHour(h)
	h = h % 24
	local suffix = if h >= 12 then "pm" else "am"
	local shown = h % 12
	if shown == 0 then
		shown = 12
	end
	return shown .. suffix
end

--------------------------------------------------------------------------------
-- Voices: the same idea said ten different ways
--------------------------------------------------------------------------------
local GREET = {
	cheerful = { "Oh, hi there! I'm {first}! Isn't it a lovely day?", "Hiii! I'm {first}. So nice to meet you!", "Well hello! I'm {first}. What a nice surprise!" },
	shy = { "Oh! Um... hi. I'm {first}.", "H-hello... I'm {first}.", "...Hi. Sorry, I didn't see you there." },
	grumpy = { "What.", "Yeah? What do you want?", "Hmph. Make it quick, I'm {first}." },
	chatty = { "Hi hi! I'm {first}! Have we met? I feel like we've met. I love meeting people!", "Oh hey! I'm {first}! Pull up a chair, I've got SO much to tell you.", "Hello, hello! {first}'s the name, talking's the game!" },
	bookish = { "Hello. Sorry, I was lost in thought. I'm {first}.", "Oh, hello. I'm {first}. Did you know this city has 40 buildings? Fascinating.", "Greetings. I'm {first}." },
	sporty = { "Hey! I'm {first}! Can't stand still long, gotta keep moving!", "Yo! {first} here. You look like you could use a jog!", "Hey hey! I'm {first}. Nice day for a run!" },
	artsy = { "Oh, hello! I'm {first}. You have a very interesting... aura.", "Hi! I'm {first}. The light is gorgeous today, isn't it?", "Hello, stranger. I'm {first}. Have you ever really LOOKED at a sunset?" },
	curious = { "Oh, hello! I'm {first}. Who are you? Where are you from? What do you do?", "Hi! I'm {first}. You're new around here, aren't you?", "Hello! I'm {first}. What brings you my way?" },
	calm = { "Hello, friend. I'm {first}. Peaceful day, isn't it?", "Hi there. I'm {first}. Take a breath, enjoy the moment.", "Good to meet you. I'm {first}." },
	funny = { "Well hello! I'm {first}. You look like someone who needs a good laugh.", "Hey! I'm {first}. I'd tell you a joke about construction, but I'm still working on it.", "Hi! {first} here. Warning: I'm hilarious." },
}
local GREET_FRIEND = {
	"Hey {player}! Good to see you!", "{player}! How are you doing?", "Oh, it's {player}! Hi!", "Hey you! Nice to see a friendly face.",
}
local GREET_LOVE = {
	"{player}!! My favorite person in the whole city! 😄", "{player}! I was just thinking about you!", "Look who it is! {player}! Come here!",
}
local GREET_DISLIKE = {
	"Oh. It's you.", "Hmm. {player}. What do you want?", "I'm kind of busy, {player}.", "You again...",
}
local GREET_HATE = {
	"Ugh. Get away from me, {player}.", "I've heard all about you, {player}. Keep walking.", "Not you. Anyone but you.",
}
local GREET_AFRAID = {
	"W-what do you want?! Please don't hurt me!", "Stay back! I'll call the police!", "P-please... I don't want any trouble!",
}

local VALUE_PHRASES = {
	wealth = "making a good living", community = "people looking out for each other", safety = "feeling safe on the streets",
	freedom = "being free to live my own way", nature = "parks, trees and fresh air", tradition = "keeping our city's traditions alive",
}

local JOB_LINES = {
	["Baker"] = "The first croissants come out of the oven at six. Best smell in the world!",
	["Barista"] = "I can make a latte with a heart on top. Want to see?",
	["Doctor"] = "Long shifts, but helping people get better makes it worth it.",
	["Nurse"] = "Doctors get the credit, but nurses keep the hospital running!",
	["Police Officer"] = "Keeping the streets safe. Don't make me chase you, okay?",
	["Night Officer"] = "The city's a different place after dark. Somebody has to watch it.",
	["Teacher"] = "The little ones keep me on my toes. Recess is their favorite subject!",
	["Middle School Teacher"] = "Middle schoolers! Half kid, half teenager, all energy.",
	["High School Teacher"] = "Getting teenagers excited about algebra is my superpower.",
	["Coach"] = "After school the whole field fills up. Those kids can really play!",
	["Factory Worker"] = "The machines never sleep, and neither does the factory floor.",
	["Shopkeeper"] = "Fresh fruit every morning. Come by the market!",
	["City Clerk"] = "I stamp forms. So many forms. You wouldn't believe the forms.",
	["Gardener"] = "Every flower in Central Park? Planted by me and my team.",
	["Street Musician"] = "I play by the fountain. Tips welcome!",
	["Bank Teller"] = "Deposits, withdrawals, and way too many coin jars.",
	["Bank Manager"] = "The vault is perfectly safe. Perfectly. Don't get any ideas.",
	["Firefighter"] = "Mostly we rescue cats and do drills. Not complaining!",
	["Librarian"] = "Shh! ...Sorry, habit. The library is my happy place.",
	["Chef"] = "My pasta sauce recipe is a secret. Don't even ask.",
	["Waiter"] = "I can carry six plates at once. It's a gift.",
	["Pharmacist"] = "If you ever feel sick, come see me at the pharmacy.",
	["Office Worker"] = "Meetings about meetings. Spreadsheets. Coffee. Repeat.",
	["Programmer"] = "I write code on the 9th floor. It works on my machine!",
	["Accountant"] = "Numbers never lie. People do, but numbers don't.",
	["Night Janitor"] = "The towers are so quiet at night. I like it that way.",
	["Hotel Receptionist"] = "Welcome to the Grand Hotel! ...Sorry, work voice.",
	["Cinema Clerk"] = "Free popcorn refills if you smile. Company policy. Probably.",
	["Fitness Coach"] = "Drop and give me twenty! ...Just kidding. Unless?",
	["Store Clerk"] = "That shirt would look great on you. I say that to everyone, but I mean it this time.",
	["Mechanic"] = "If it has wheels, I can fix it.",
	["Warehouse Worker"] = "Boxes. So many boxes. I dream about boxes.",
	["Daycare Worker"] = "Nap time is the most peaceful hour of my whole day.",
	["Museum Guide"] = "Have you seen the dinosaur yet? He's my favorite coworker.",
	["Mail Carrier"] = "Rain or shine, the mail gets through!",
	["Arcade Attendant"] = "I've seen every high score in this city. Most of them are mine.",
	["Cook"] = "Best burgers in town, right at the diner.",
	["Community Organizer"] = "I bring people together. Come to the community center sometime!",
}

local SCHOOL_LINES = {
	"My favorite subject is art! We painted the whole city last week.", "Recess is the best part. We play tag every single day!",
	"I got a gold star on my spelling test!", "My teacher says I ask too many questions. Is that bad?",
	"We have a science fair next week. I'm making a volcano!", "I'm the fastest runner in my class. Probably.",
}
local TEEN_LINES = {
	"High school is fine, I guess. Homework is not.", "I'm trying out for the soccer team!", "My friends and I hang out at the arcade after school.",
	"Can't wait to turn 18 and get a job. Or not. Probably not.", "Everyone's talking about who's going to be mayor. Kinda cool.",
}

local JOKES = {
	"Why did the scarecrow win an award? Because he was outstanding in his field!",
	"What do you call a fake noodle? An impasta!",
	"Why don't skeletons fight each other? They don't have the guts.",
	"What did the ocean say to the beach? Nothing, it just waved.",
	"Why can't a bicycle stand up by itself? It's two tired!",
	"What do you call a bear with no teeth? A gummy bear!",
	"Why did the math book look sad? It had too many problems.",
	"What do you call cheese that isn't yours? Nacho cheese!",
}
local NPC_JOKES = {
	"Why did the bank teller quit? She lost interest!", "I told my boss a joke about the elevator. It works on so many levels.",
	"Why did the bakery close? It was a crummy business!", "I'm reading a book about gravity. I can't put it down!",
	"What's a mayor's favorite dance? The ballot!", "Why do bees have sticky hair? They use honeycombs!",
}

--------------------------------------------------------------------------------
-- Who someone is to a player
--------------------------------------------------------------------------------
local function tier(c, player)
	local op = S.City.Opinion(c, player)
	local wanted = (player:GetAttribute("Wanted") or 0) > 0
	-- did they see this player commit a crime lately?
	for _, m in ipairs(S.City.MemoriesOf(c, player)) do
		if m.f <= -20 and (S.City.Day() - (m.d or 0)) <= 1 and (m.h or 0) == 0 then
			return "afraid", op
		end
	end
	if wanted and op < 20 then
		return "afraid", op
	elseif op <= -45 then
		return "hate", op
	elseif op <= -12 then
		return "dislike", op
	elseif op >= 50 then
		return "love", op
	elseif op >= 15 then
		return "friend", op
	end
	return "neutral", op
end

local function vars(c, player)
	local stage = S.Life:Stage(c)
	return { first = c.First, player = player and player.DisplayName or "friend", name = c.Name, job = c.Job or "", age = S.Life:Age(c), stage = lower(stage) }
end

local function greetingFor(c, player)
	local t, op = tier(c, player)
	local v = vars(c, player)
	if t == "afraid" then
		return fill(pick(GREET_AFRAID), v), "scared"
	elseif t == "hate" then
		return fill(pick(GREET_HATE), v), "angry"
	elseif t == "dislike" then
		return fill(pick(GREET_DISLIKE), v), "focused"
	elseif t == "love" then
		return fill(pick(GREET_LOVE), v), "love"
	elseif t == "friend" then
		return fill(pick(GREET_FRIEND), v), "happy"
	end
	return fill(pick(GREET[c.Personality] or GREET.calm), v), if c.Personality == "grumpy" then "focused" elseif c.Personality == "shy" then "neutral" else "happy"
end

--------------------------------------------------------------------------------
-- Answers
--------------------------------------------------------------------------------
local ANSWERS = {}

ANSWERS.howday = function(c, player, brain)
	local mood = S.City.MoodOf(c)
	local plan = brain.Plan or {}
	local doing
	if plan.Kind == "Work" then
		doing = "working at the " .. placeLabel(plan.Place)
	elseif plan.Kind == "School" then
		doing = if plan.Recess then "on my break" else "at school"
	else
		doing = activityText(brain.Model:GetAttribute("Activity"))
	end
	local stateId = S.City.CityState()
	local reason = ""
	if (c.MoodBoost or 0) < -20 then
		reason = " Someone attacked me earlier... I'm still shaken up."
	elseif stateId == "Chaos" or stateId == "Unrest" then
		reason = " The city's a mess lately. Crime everywhere."
	elseif S.Life:Stage(c) == "Adult" and not c.Job then
		reason = " Still looking for a job, though."
	end
	local line
	if mood >= 78 then
		line = pick({ "Honestly? Amazing! I'm " .. doing .. " and loving every minute.", "Fantastic! Right now I'm " .. doing .. ". Life is good!", "Best day ever! Well, today anyway. I'm " .. doing .. "." })
	elseif mood >= 55 then
		line = pick({ "Pretty good! Just " .. doing .. ".", "Not bad, not bad. I'm " .. doing .. ".", "Can't complain! I'm " .. doing .. "." })
	elseif mood >= 35 then
		line = pick({ "Meh. I'm " .. doing .. ". It's fine.", "Could be better. Just " .. doing .. ".", "It's one of those days. I'm " .. doing .. "." })
	else
		line = pick({ "Honestly? Terrible.", "Don't ask.", "Bad. Really bad." })
	end
	if c.Personality == "grumpy" and mood < 70 then
		line = "Why does everyone keep asking me that? " .. line
	elseif c.Personality == "chatty" then
		line ..= " Oh, and did I tell you about my " .. c.Hobby .. "? I'm SO into it lately!"
	end
	local expr = if mood >= 70 then "happy" elseif mood >= 45 then "neutral" elseif mood >= 30 then "sad" else "angry"
	return line .. reason, expr
end

ANSWERS.job = function(c, player, brain)
	local stage = S.Life:Stage(c)
	local age = S.Life:Age(c)
	if stage == "Child" or stage == "Teen" then
		local school, label = S.Life:SchoolFor(c)
		local grade = if school == "School" then age - 5 elseif school == "MiddleSchool" then age - 5 else age - 5
		local intro = "I'm in " .. (if grade == 1 then "1st" elseif grade == 2 then "2nd" elseif grade == 3 then "3rd" else grade .. "th") .. " grade at the " .. (label or "school") .. "! "
		return intro .. pick(if stage == "Teen" then TEEN_LINES else SCHOOL_LINES), "happy"
	elseif stage == "Toddler" then
		return "I go to daycare! We have blocks! 🧸", "grin"
	elseif stage == "Retired" then
		return "Me? I'm retired! Now I spend my days " .. c.Hobby .. ". Best job I ever had!", "happy"
	end
	local job = S.Life.Jobs(Config, c.Job or "")
	if not job then
		return pick({ "I'm between jobs right now. If you hear of anything, let me know!", "Looking for work. It's tough out there.", "Nothing right now. I'm spending a lot of time " .. c.Hobby .. " while I look." }), "sad"
	end
	local closed = if job.place == "Office" or job.place == "Bank" or job.place == "TownHall" then " Weekends off, thank goodness." else ""
	return "I'm a " .. job.title .. " at the " .. placeLabel(job.place) .. ", " .. formatHour(job.start) .. " to " .. formatHour(job.stop) .. "." .. closed .. " " .. (JOB_LINES[job.title] or "It's good work."), "happy"
end

ANSWERS.city = function(c)
	local stateId = S.City.CityState()
	local info = Config.CityStates[stateId] or {}
	local value = S.City.TopValue(c)
	local best, bestScore = nil, -2
	for _, s in ipairs(Config.Stances) do
		local a = S.City.Appeal(c, s.id)
		if a > bestScore then
			best, bestScore = s, a
		end
	end
	local feel = {
		Celebrating = "This city is PARTYING right now! I love it!",
		Prosperous = "Business is booming. Things are going well.",
		Peaceful = "It's calm and happy around here. I like it.",
		Stable = "It's fine. Nothing special, but fine.",
		Tense = "People seem on edge lately. I'm a little worried.",
		Unrest = "People are angry. There's talk of protests.",
		Chaos = "It's chaos out there! Crime, fights... I barely leave home.",
	}
	local line = (feel[stateId] or "It's alright.") .. " What I care about most is " .. (VALUE_PHRASES[value] or "my neighbors") .. "."
	if best then
		line ..= " If I were mayor, I'd " .. lower(best.label) .. "."
	end
	local expr = if stateId == "Celebrating" or stateId == "Prosperous" or stateId == "Peaceful" then "happy" elseif stateId == "Stable" then "neutral" else "sad"
	return line, expr
end

ANSWERS.mayor = function(c, player)
	local mayor = S.City.State.Mayor
	if not mayor then
		return "We don't have a mayor yet! Somebody should give a speech on the plaza stage.", "neutral"
	end
	if mayor.Kind == "citizen" and mayor.CitizenId == c.Id then
		return "That's me! 😎 Mayor " .. c.Name .. ". I'm doing my best, I promise!", "grin"
	end
	if mayor.Kind == "player" and mayor.UserId == player.UserId then
		local op = S.City.Opinion(c, player)
		if op >= 20 then
			return "You're the mayor! And honestly? You're doing great.", "happy"
		elseif op <= -20 then
			return "You're the mayor, and I'm not happy about it. At all.", "angry"
		end
		return "You're the mayor! We'll see how it goes.", "neutral"
	end
	local score = 0
	if mayor.Kind == "player" then
		score = S.City.Opinion(c, mayor.UserId) / 40
	else
		for _, id in ipairs(mayor.Stances or {}) do
			score += S.City.Appeal(c, id)
		end
	end
	local first = string.match(mayor.Name, "^(%S+)") or mayor.Name
	if score > 0.4 then
		return pick({ "Mayor " .. first .. "? Best mayor we've ever had!", "I voted for " .. first .. " and I'd do it again.", first .. " gets it. They really get it." }), "happy"
	elseif score < -0.4 then
		return pick({ "Don't get me started on " .. first .. ".", "Mayor " .. first .. "? Next election can't come soon enough.", first .. " has NO idea what this city needs." }), "angry"
	end
	return pick({ "Mayor " .. first .. " is okay, I guess.", "Some good ideas, some bad ones. Like every mayor.", "I don't really follow politics." }), "neutral"
end

ANSWERS.gossip = function(c, player)
	local lines = {}
	-- things they've heard about other players
	for _, m in ipairs(c.Memories or {}) do
		if m.u ~= tostring(player.UserId) and math.abs(m.f) >= 5 then
			table.insert(lines, { "Have you met " .. m.n .. "? They " .. m.g .. ".", if m.f > 0 then "happy" else "surprised" })
		elseif m.u == tostring(player.UserId) and (m.h or 0) > 0 then
			table.insert(lines, { "People say you " .. m.g .. ". Is that true?", if m.f > 0 then "happy" else "focused" })
		end
		if #lines >= 4 then
			break
		end
	end
	-- family news around town
	for _, h in ipairs(S.Life.Households) do
		if h.Expecting and #lines < 7 and math.random() < 0.3 then
			local names = {}
			for _, id in ipairs(h.Partners) do
				table.insert(names, S.Life.Citizens[id].First)
			end
			table.insert(lines, { "Did you hear? " .. table.concat(names, " and ") .. " " .. h.Last .. " are having a baby! 🍼", "grin" })
		end
	end
	for k = 1, math.min(4, #S.City.State.News) do
		local n = S.City.State.News[k]
		if n.Kind ~= "Day" and n.Kind ~= "Welcome" then
			table.insert(lines, { "Did you see the news? " .. string.gsub(n.Text, "^[^%w]*", ""), "surprised" })
		end
	end
	if #lines == 0 then
		return pick({ "Gossip? Me? Never! ...Okay, I just haven't heard anything good lately.", "Quiet week. Nothing to report!", "My lips are sealed. Mostly because I don't know anything." }), "neutral"
	end
	local l = pick(lines)
	return l[1], l[2]
end

ANSWERS.family = function(c)
	local h = S.Life.Households[c.Household]
	if not h then
		return "It's just me.", "neutral"
	end
	local parts = {}
	for _, id in ipairs(h.Members) do
		local m = S.Life.Citizens[id]
		if m and m ~= c then
			local stage = S.Life:Stage(m)
			local isPartner = table.find(h.Partners, id) and table.find(h.Partners, c.Id)
			if isPartner then
				table.insert(parts, "my partner " .. m.First .. (if m.Job and stage == "Adult" then " (a " .. string.lower(m.Job) .. ")" else ""))
			elseif stage == "Baby" or stage == "Toddler" or stage == "Child" or stage == "Teen" then
				table.insert(parts, (if table.find(h.Partners, c.Id) then "my kid " else "my sibling ") .. m.First .. " (" .. S.Life:Age(m) .. ")")
			else
				table.insert(parts, m.First)
			end
		end
	end
	local line
	if #parts == 0 then
		line = "It's just me for now. I like my own space!"
	else
		line = "I live with " .. table.concat(parts, ", ") .. "."
	end
	local home = h.Home and S.Map.Homes[h.Home]
	if home then
		line ..= " We're at " .. home.Address .. "."
	end
	if h.Expecting then
		local days = S.Life:DaysToGo(h)
		line ..= " And we're expecting a baby " .. (if days <= 0 then "TODAY" elseif days == 1 then "tomorrow" else "in " .. days .. " days") .. "! 🍼"
	end
	local friend = c.Friends and c.Friends[1] and S.Life.Citizens[c.Friends[1]]
	if friend then
		line ..= " My best friend is " .. friend.Name .. "."
	end
	return line, "happy"
end

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------
local DIRECTIONS = { "Hospital", "PoliceStation", "Bank", "TownHall", "Plaza", "Gym", "Cafe", "Arcade", "Park", "Library", "HighSchool", "Lake" }

local function compass(from, to)
	local d = to - from
	local dirs = {}
	if d.Z < -20 then
		table.insert(dirs, "north")
	elseif d.Z > 20 then
		table.insert(dirs, "south")
	end
	if d.X > 20 then
		table.insert(dirs, "east")
	elseif d.X < -20 then
		table.insert(dirs, "west")
	end
	return if #dirs == 0 then "right around here" else table.concat(dirs, "-")
end

local function streetOf(pos)
	local sp = S.Map.Spacing or 100
	local k = math.floor(pos.Z / sp + 0.5)
	return S.Map.StreetName and S.Map.StreetName(k) or "Main Street"
end

local function options(c, player, brain, submenu)
	local stage = S.Life:Stage(c)
	if submenu == "directions" then
		local list = {}
		for _, id in ipairs(DIRECTIONS) do
			if S.Map.Places[id] then
				table.insert(list, { Key = "go:" .. id, Text = (Config.PlaceById[id] and Config.PlaceById[id].emoji or "📍") .. " " .. placeLabel(id) })
			end
		end
		table.insert(list, { Key = "back", Text = "↩️ Never mind" })
		return list
	end
	if stage == "Baby" or stage == "Toddler" then
		return { { Key = "peekaboo", Text = "🙈 Peekaboo!" }, { Key = "bye", Text = "👋 Bye bye!" } }
	end
	local list = {
		{ Key = "howday", Text = "👋 How's your day going?" },
		{ Key = "job", Text = if stage == "Child" or stage == "Teen" then "🎒 How's school?" else "💼 What do you do?" },
		{ Key = "family", Text = "👨‍👩‍👧 Tell me about yourself" },
		{ Key = "gossip", Text = "👂 Heard any gossip?" },
	}
	if stage ~= "Child" then
		table.insert(list, { Key = "city", Text = "🏙️ What do you think of the city?" })
		table.insert(list, { Key = "mayor", Text = "🏛️ What do you think of the mayor?" })
	end
	local pd = S.City.Data(player)
	if pd and pd.Stances and #pd.Stances > 0 and S.Life:Age(c) >= (Config.ADULT_AGE or 18) then
		table.insert(list, { Key = "vote", Text = "🗳️ Will you vote for me?" })
	end
	table.insert(list, { Key = "joke", Text = "😂 Tell a joke" })
	table.insert(list, { Key = "compliment", Text = "😊 Give a compliment" })
	table.insert(list, { Key = "gift", Text = "🎁 Give a gift (" .. (Config.GIFT_AMOUNT or 10) .. " coins)" })
	table.insert(list, { Key = "directions", Text = "🧭 Where can I find...?" })
	table.insert(list, { Key = "follow", Text = "🚶 Come with me!" })
	table.insert(list, { Key = "insult", Text = "😠 Insult them" })
	table.insert(list, { Key = "bye", Text = "👋 Goodbye" })
	return list
end

local function header(c, player, brain)
	local stage = S.Life:Stage(c)
	local title
	if stage == "Adult" then
		title = c.Job or "Looking for work"
	elseif stage == "Retired" then
		title = "Retired"
	else
		local _, label = S.Life:SchoolFor(c)
		title = label or stage
	end
	local info = S.Life.PersonalityInfo[c.Personality] or {}
	return {
		Name = c.Name,
		Title = title,
		Age = S.Life:Age(c),
		Personality = c.Personality,
		PersonalityEmoji = info.Emoji or "🙂",
		Mood = math.floor(S.City.MoodOf(c)),
		Opinion = math.floor(S.City.Opinion(c, player)),
		Activity = brain.Model:GetAttribute("Activity"),
	}
end

local function remember(c, player, text, feeling, gossip)
	S.City.Remember(c, player, text, feeling, gossip)
end

local function respond(player, session, key)
	local brain = session.Brain
	local c = brain.C
	local v = vars(c, player)
	local text, expr, playerLine, action
	local submenu
	local done = false
	local t = tier(c, player)
	session.Used[key] = (session.Used[key] or 0) + 1
	local repeated = session.Used[key] > 1

	if t == "afraid" and key ~= "bye" and key ~= "gift" then
		return { Text = pick({ "P-please just leave me alone!", "I don't want any trouble!", "*backs away slowly*" }), Expression = "scared", Options = { { Key = "gift", Text = "🎁 Give a gift to say sorry (" .. (Config.GIFT_AMOUNT or 10) .. " coins)" }, { Key = "bye", Text = "👋 Leave them alone" } } }
	end

	if key == "howday" or key == "job" or key == "city" or key == "mayor" or key == "gossip" or key == "family" then
		text, expr = ANSWERS[key](c, player, brain)
		if repeated and key ~= "gossip" then
			text = pick({ "Like I said... ", "Didn't you just ask me that? ", "Again? Okay: " }) .. text
		end
	elseif key == "peekaboo" then
		text, expr = pick({ "*giggles* 👶", "Hehehe! Again! Again!", "*claps happily*", "Boo! 😄" }), "laugh"
		remember(c, player, "played peekaboo with me", 4, "played peekaboo with little " .. c.First)
	elseif key == "joke" then
		playerLine = pick(JOKES)
		local p = c.Personality
		local roll = math.random()
		if p == "funny" or (p == "cheerful" and roll < 0.8) or (p ~= "grumpy" and roll < 0.45) then
			text, expr, action = pick({ "HAHAHA! Oh that's a good one!", "Hahaha! I'm stealing that one!", "😂 Stop, stop, my sides!", "Haha! Okay, okay, my turn: " .. pick(NPC_JOKES) }), "laugh", "cheer"
			remember(c, player, "told me a great joke", if repeated then 1 else 5, "told " .. c.First .. " a hilarious joke")
		elseif p == "grumpy" then
			text, expr = pick({ "...Was that supposed to be funny?", "*stares blankly*", "I've heard better jokes from a parking meter." }), "focused"
			remember(c, player, "told me a terrible joke", -1, "told a terrible joke")
		else
			text, expr = pick({ "Heh. Cute.", "*polite chuckle*", "Ha... I don't get it.", "Oh no. Oh no, that's so bad. I love it." }), "happy"
			remember(c, player, "told me a joke", 1)
		end
	elseif key == "compliment" then
		local times = session.Used[key]
		local p = c.Personality
		if times > 2 then
			text, expr = "Okay, okay, now you're just buttering me up!", "focused"
		elseif p == "shy" then
			text, expr = pick({ "O-oh! Thank you... *blushes*", "Me? Really? Oh my..." }), "love"
			remember(c, player, "said something really nice to me", 7, "made " .. c.First .. " blush with a compliment")
		elseif p == "grumpy" then
			text, expr = pick({ "Hmph. ...Thanks, I guess.", "Flattery won't get you anywhere. ...But thanks." }), "neutral"
			remember(c, player, "complimented me", 3)
		else
			text, expr = pick({ "Aww, thank you! You just made my day!", "That's so sweet of you!", "Right back at you, " .. player.DisplayName .. "!" }), "grin"
			remember(c, player, "complimented me", 5, "is really nice to " .. c.First)
		end
	elseif key == "insult" then
		local p = c.Personality
		if p == "grumpy" or p == "sporty" then
			text, expr, action = pick({ "Excuse me?! Say that again, I dare you!", "Wow. Real mature.", "Get lost before I lose my temper!" }), "angry", "boo"
		elseif p == "shy" or p == "calm" then
			text, expr = pick({ "...That was really mean.", "Why would you say that?", "*looks down sadly*" }), "sad"
		else
			text, expr = pick({ "Rude! I'm telling everyone about this!", "Wow. Okay. Bye then!", "Well, someone woke up on the wrong side of the bed." }), "angry"
		end
		remember(c, player, "insulted me", -14, "was really rude to " .. c.First)
		S.City.Boost(c, -8)
	elseif key == "gift" then
		local amount = Config.GIFT_AMOUNT or 10
		if not S.City.Spend(player, amount, "🎁 Gift to " .. c.First) then
			text, expr = "That's sweet, but... you don't have enough coins!", "neutral"
		else
			local p = c.Personality
			local times = session.Used[key]
			text = if t == "afraid" then "...Oh. Um. Thank you. I guess you're not all bad." elseif p == "grumpy" then "Hm. Coins? ...Fine. Thanks." elseif p == "shy" then "F-for me? Thank you so much!" elseif times > 2 then "You're too generous! Really, it's fine!" else pick({ "For me?! Oh, you shouldn't have! Thank you!", "Wow, thank you so much! 😊", "You're the best, " .. player.DisplayName .. "!" })
			expr, action = "love", "cheer"
			remember(c, player, "gave me a gift", if times > 2 then 3 else 12, "gave " .. c.First .. " a gift")
			S.City.Boost(c, 10)
		end
	elseif key == "vote" then
		local pd = S.City.Data(player)
		local appeal = 0
		for _, id in ipairs(pd.Stances or {}) do
			appeal += S.City.Appeal(c, id)
		end
		local op = S.City.Opinion(c, player)
		local stance = S.City.StanceById[pd.Stances[1]]
		local score = op / 30 + appeal + (if repeated then -0.5 else 0)
		if score > 0.8 then
			text, expr = pick({ "You've got my vote! " .. (stance and stance.label .. "? Yes please!" or ""), "Absolutely. I'm with you all the way!", "Count me in! I'll tell my friends too." }), "grin"
			remember(c, player, "asked for my vote (I'm in!)", 3, "is running for mayor")
		elseif score > 0 then
			text, expr = pick({ "Maybe! I like some of your ideas.", "I'm thinking about it. Convince me!", "Hmm... you might have my vote. Might." }), "neutral"
			remember(c, player, "asked for my vote", 1, "is running for mayor")
		else
			text, expr = pick({ "Sorry, I don't agree with you on " .. (stance and string.lower(stance.label) or "much") .. ".", "Not a chance.", "I'm voting for someone else." }), "focused"
			remember(c, player, "asked for my vote (no way)", if repeated then -4 else -1, "keeps begging for votes")
		end
	elseif key == "directions" then
		text, expr, submenu = pick({ "Sure! Where do you want to go?", "I know this city like the back of my hand. Where to?", "Lost? Happens to everyone. Where are you headed?" }), "happy", "directions"
	elseif string.sub(key, 1, 3) == "go:" then
		local id = string.sub(key, 4)
		local place = S.Map.Places[id]
		if place then
			local from = brain.Root.Position
			local dist = (place.Door - from).Magnitude
			local near = if dist < 60 then "It's right around here! " else ""
			text = near .. "The " .. placeLabel(id) .. " is " .. compass(from, place.Door) .. " of here, on " .. streetOf(place.Door) .. ". About " .. math.floor(dist / 10 + 0.5) * 10 .. " studs. I've marked it for you!"
			expr, action = "happy", "point"
			S.City.Send(player, { Type = "Waypoint", Position = place.Door, Label = placeLabel(id), Emoji = Config.PlaceById[id] and Config.PlaceById[id].emoji or "📍" })
			remember(c, player, "asked me for directions", 1)
		end
	elseif key == "back" then
		text, expr = "Anything else?", "neutral"
	elseif key == "follow" then
		local op = S.City.Opinion(c, player)
		local plan = brain.Plan or {}
		if plan.Kind == "Work" or plan.Kind == "School" then
			text, expr = if plan.Kind == "Work" then "I'd love to, but I'm working! Catch me after my shift." else "I can't, I'm at school!", "neutral"
		elseif op < 25 then
			text, expr = pick({ "Uh... I don't really know you that well.", "Where? Why? No thanks.", "Maybe when we're better friends!" }), "focused"
		else
			text, expr = pick({ "Sure! Lead the way!", "An adventure? I'm in!", "Okay, let's go!" }), "grin"
			done = true
			session.Follow = true
		end
	elseif key == "bye" then
		local t2 = tier(c, player)
		text = if t2 == "love" or t2 == "friend" then pick({ "See you around, " .. player.DisplayName .. "!", "Bye! Come find me again soon!", "Take care, friend!" }) elseif t2 == "hate" or t2 == "dislike" then pick({ "Finally.", "Bye.", "Don't come back." }) else pick({ "Bye! Nice talking to you.", "See you around!", "Have a good one!" })
		expr, action = if t2 == "hate" or t2 == "dislike" then "focused" else "happy", "wave"
		done = true
	else
		text, expr = "Hmm?", "neutral"
	end

	-- a friendly chat once a day counts for something
	local k = c.Id .. ":" .. player.UserId
	if chattedToday[k] ~= S.City.Day() and key ~= "insult" then
		chattedToday[k] = S.City.Day()
		remember(c, player, "stopped to chat with me", 2)
		local pd = S.City.Data(player)
		if pd then
			pd.Talks += 1
		end
	end
	return {
		Text = fill(text or "...", v),
		PlayerLine = playerLine,
		Expression = expr or "neutral",
		Action = action,
		Options = if done then {} else options(c, player, brain, submenu),
		Done = done,
	}
end

--------------------------------------------------------------------------------
-- Conversations with players
--------------------------------------------------------------------------------
local function finish(player, silent)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	local brain = session.Brain
	if session.Follow and brain.Model.Parent then
		-- they walk along with the player for a while
		S.Citizens.Release(brain)
		S.Citizens.Control(brain, true)
		brain.Model:SetAttribute("Activity", "🚶 Walking with " .. player.DisplayName)
		brain.Model:SetAttribute("Following", player.UserId)
		task.spawn(function()
			local untilT = os.clock() + 45
			while os.clock() < untilT and brain.State == "police" and brain.Model.Parent do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not root then
					break
				end
				local offset = root.CFrame.RightVector * 3 - root.CFrame.LookVector * 2
				local d = (root.Position - brain.Root.Position).Magnitude
				if d > 90 then
					break
				end
				S.Citizens.SetGait(brain, if d > 12 then 16 else 9, if d > 12 then "run" else "walk")
				brain.Humanoid:MoveTo(root.Position + offset)
				task.wait(0.3)
			end
			if brain.Model.Parent and brain.State == "police" then
				brain.Model:SetAttribute("Following", nil)
				S.Citizens.Say(brain, "That was fun! I should get going though. Bye!", "happy", 2.5)
				S.Citizens.Control(brain, false)
			end
		end)
	else
		S.Citizens.Release(brain)
	end
	if not silent then
		S.City.Send(player, { Type = "DialogueEnd" })
	end
end

function DialogueService.Begin(player, brain)
	if not brain or not brain.C or brain.C.Temp then
		return
	end
	if brain.State == "ko" or brain.State == "hospital" then
		S.City.Toast(player, "💫", brain.C.First .. " can't talk right now", if brain.State == "ko" then "They're knocked out." else "They're resting in the hospital.")
		return
	end
	if brain.State == "police" then
		return
	end
	for other, s in pairs(sessions) do
		if s.Brain == brain and other ~= player then
			S.City.Toast(player, "💬", brain.C.First .. " is busy", "They're talking to " .. other.DisplayName .. ".")
			return
		end
	end
	finish(player, true)
	if not S.Citizens.Hold(brain, player) then
		return
	end
	local c = brain.C
	local session = { Brain = brain, Last = os.clock(), Used = {} }
	sessions[player] = session
	local line, expr = greetingFor(c, player)
	-- context: busy at work, asleep, in class
	local action = brain.Model:GetAttribute("Action") or ""
	if action == "sleep" or action == "nap" then
		line = pick({ "Zzz... huh? Wha-? Oh! You woke me up. ", "*yawn* ...Is it morning already? " }) .. line
		expr = "sleepy"
	elseif brain.Plan and brain.Plan.Kind == "Work" and c.Personality ~= "chatty" then
		line ..= " I'm on shift, but I've got a minute."
	elseif brain.Plan and brain.Plan.Kind == "School" and not brain.Plan.Recess then
		line ..= " Shh, we're in class!"
	end
	local stage = S.Life:Stage(c)
	if stage == "Baby" then
		line, expr = pick({ "Goo goo! 👶", "*babbles happily*", "Ba! Ba ba!" }), "grin"
	elseif stage == "Toddler" then
		line, expr = pick({ "Hi! I'm " .. c.First .. "! I'm " .. S.Life:Age(c) .. "!", "Wanna see my toy? 🧸" }), "grin"
	end
	brain.Model:SetAttribute("Expression", expr)
	S.Citizens.Say(brain, line, expr, 3)
	local h = header(c, player, brain)
	h.Type = "Dialogue"
	h.Model = brain.Model
	h.Id = c.Id
	h.Text = line
	h.Expression = expr
	h.Options = options(c, player, brain)
	h.Memories = {}
	for k, m in ipairs(S.City.MemoriesOf(c, player)) do
		if k > 3 then
			break
		end
		table.insert(h.Memories, m.t)
	end
	S.City.Send(player, h)
end

local function onChoose(player, data)
	local session = sessions[player]
	if not session or type(data.Option) ~= "string" then
		return { Ok = false }
	end
	session.Last = os.clock()
	local brain = session.Brain
	local result = respond(player, session, data.Option)
	result.Ok = true
	result.Opinion = math.floor(S.City.Opinion(brain.C, player))
	result.Mood = math.floor(S.City.MoodOf(brain.C))
	brain.Model:SetAttribute("Expression", result.Expression)
	S.Citizens.Say(brain, result.Text, result.Expression)
	if result.Action then
		local token = {}
		session.ActionToken = token
		brain.Model:SetAttribute("Action", result.Action)
		task.delay(2, function()
			if session.ActionToken == token and brain.State == "talk" then
				brain.Model:SetAttribute("Action", "listen")
			end
		end)
	end
	if result.Done then
		task.delay(1.2, function()
			if sessions[player] == session then
				finish(player, true)
			end
		end)
	end
	return result
end

--------------------------------------------------------------------------------
-- Citizens talking to each other
--------------------------------------------------------------------------------
function DialogueService.Greeting(a, b)
	local p = a.Personality
	local name = b.First
	if p == "shy" then
		return pick({ "Oh, hi " .. name .. "...", "*small wave*" })
	elseif p == "grumpy" then
		return pick({ name .. ".", "Hey.", "*nods*" })
	elseif p == "chatty" or p == "cheerful" then
		return pick({ "Hiii " .. name .. "!!", "Hey " .. name .. "! Love the outfit!", name .. "! Hi hi!" })
	elseif p == "funny" then
		return pick({ "Well if it isn't " .. name .. "!", "Hey " .. name .. ", nice face! Wait..." })
	end
	return pick({ "Hi " .. name .. "!", "Hey " .. name .. "!", "Morning, " .. name .. "!", "Oh hey, " .. name .. "!" })
end

function DialogueService.GreetPlayer(c, player, opinion)
	if opinion >= 50 then
		return pick({ "Hi " .. player.DisplayName .. "!! 😄", "Hey, it's " .. player.DisplayName .. "! My favorite!", player.DisplayName .. "! Come say hi!" })
	elseif opinion >= 25 then
		return pick({ "Hi " .. player.DisplayName .. "!", "Hey " .. player.DisplayName .. "!", "Oh, hello " .. player.DisplayName .. "!" })
	elseif opinion <= -50 then
		return pick({ "Ugh, it's " .. player.DisplayName .. ".", "Keep walking, " .. player.DisplayName .. ".", "*glares*" })
	end
	return pick({ "Hmph.", "Oh. It's you.", "*looks away*" })
end

local TOPICS_ADULT = {
	function(a, b)
		local h = S.City.Hour()
		if h < 11 then
			return { { 1, "Morning! Sleep well?" }, { 2, pick({ "Like a baby!", "Not really, the neighbors were loud.", "Barely. I need coffee.", "Best sleep ever!" }) } }
		elseif h > 17 then
			return { { 1, "Long day, huh?" }, { 2, pick({ "The longest.", "Not too bad actually!", "I'm exhausted.", "Glad it's over!" }) } }
		end
		return { { 1, "Nice weather today!" }, { 2, pick({ "Perfect for a walk.", "A bit warm for me.", "Couldn't be better!" }) } }
	end,
	function(a, b)
		if not b.Job then
			return nil
		end
		local job = S.Life.Jobs(Config, b.Job)
		return { { 1, "How's work at the " .. (job and placeLabel(job.place) or "job") .. "?" }, { 2, pick({ "Busy, busy, busy!", "Same old, same old.", "My boss is driving me crazy.", "Honestly? I love it.", "Could use a vacation." }) }, { 1, pick({ "Hang in there!", "I hear you.", "Ha! Lucky you." }) } }
	end,
	function(a, b)
		return { { 1, "Still into " .. b.Hobby .. "?" }, { 2, pick({ "Every single day! I'm getting good.", "Taking a break, honestly.", "You should join me sometime!" }) } }
	end,
	function(a, b)
		local mayor = S.City.State.Mayor
		if not mayor then
			return nil
		end
		local first = string.match(mayor.Name, "^(%S+)") or mayor.Name
		local like = 0
		for _, id in ipairs(mayor.Stances or {}) do
			like += S.City.Appeal(b, id)
		end
		return { { 1, "What do you think of Mayor " .. first .. "?" }, { 2, if like > 0.3 then pick({ "Love them!", "Best mayor in years.", "Great ideas!" }) elseif like < -0.3 then pick({ "Don't get me started.", "Worst. Mayor. Ever.", "Next election, they're OUT." }) else pick({ "They're okay.", "Meh.", "Could be worse!" }) }, { 1, pick({ "Fair enough.", "Hmm, I see it differently.", "Totally agree." }) } }
	end,
	function(a, b)
		local news = S.City.State.News[1]
		if not news or news.Kind == "Day" or news.Kind == "Welcome" then
			return nil
		end
		local text = string.gsub(news.Text, "^[^%w]*", "")
		return { { 1, "Did you see the news? " .. text }, { 2, pick({ "No way!", "Wow, really?!", "I heard! Crazy, right?", "Typical." }) } }
	end,
	function(a, b)
		local stateId = S.City.CityState()
		if stateId == "Tense" or stateId == "Unrest" or stateId == "Chaos" then
			return { { 1, "Things are getting scary around here." }, { 2, "I know. I lock my door twice now." }, { 1, "Someone needs to fix this city." } }
		elseif stateId == "Celebrating" then
			return { { 1, "Can you feel it? The whole city's celebrating!" }, { 2, "Let's go dance at the plaza!" } }
		end
		return nil
	end,
}
local TOPICS_KID = {
	function()
		return { { 1, "Wanna play tag?" }, { 2, "You're IT!" } }
	end,
	function()
		return { { 1, "Did you do the homework?" }, { 2, pick({ "What homework?!", "Yeah, it was easy!", "My dog ate it. We don't have a dog." }) } }
	end,
	function()
		return { { 1, "Soccer after school?" }, { 2, "You're on! I'm gonna score SO many goals." } }
	end,
	function()
		return { { 1, "My mom said I can get ice cream later!" }, { 2, "No fair! Can I come?" } }
	end,
	function()
		return { { 1, "What do you want to be when you grow up?" }, { 2, pick({ "A firefighter!", "The mayor!", "A chef!", "An astronaut!", "A doctor!" }) } }
	end,
}

function DialogueService.SmallTalk(a, b)
	local kids = S.Life:Age(a) < 13 and S.Life:Age(b) < 13
	local topics = if kids then TOPICS_KID else TOPICS_ADULT
	local lines = { { 1, DialogueService.Greeting(a, b), "happy" }, { 2, DialogueService.Greeting(b, a), "happy" } }
	for _ = 1, 4 do
		local topic = topics[math.random(1, #topics)](a, b)
		if topic then
			for _, l in ipairs(topic) do
				table.insert(lines, { l[1], l[2], l[3] })
			end
			break
		end
	end
	return lines
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
local function attach(model)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or root:FindFirstChild("TalkPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = model:GetAttribute("DisplayName") or model.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom -- CityClient draws it
	prompt:SetAttribute("Kind", "Talk")
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		local brain = S.Citizens.BrainOf(model)
		if brain then
			DialogueService.Begin(player, brain)
		end
	end)
end

function DialogueService.Start(services)
	S = services
	S.City.Handle("Dialogue", onChoose)
	S.City.Handle("DialogueEnd", function(player)
		finish(player, true)
		return { Ok = true }
	end)
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		task.spawn(attach, model)
	end
	CollectionService:GetInstanceAddedSignal("Citizen"):Connect(function(model)
		task.spawn(attach, model)
	end)
	Players.PlayerRemoving:Connect(function(player)
		finish(player, true)
	end)
	-- walking away ends the conversation
	task.spawn(function()
		while true do
			task.wait(1)
			for player, session in pairs(sessions) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local brain = session.Brain
				if not root or not brain.Model.Parent or (root.Position - brain.Root.Position).Magnitude > (Config.TALK_RADIUS or 16) or os.clock() - session.Last > 60 or brain.State ~= "talk" then
					finish(player)
				end
			end
		end
	end)
end

return DialogueService
