-- Conversation (ModuleScript) — ServerScriptService.Modules.Conversation
-- The deeper side of talking to citizens (used by DialogueService):
--   • every personality has its own voice: how they say hello, little verbal
--     habits, their dreams and fears, their advice, favorite food and places
--   • follow-up questions: ask *why* someone is having a good or bad day, if
--     they like their job, what their dream job is, about their family and
--     their hobby
--   • "Let's really talk": dreams, fears, advice, favorite food and spot in
--     the city, a favorite memory, and what they honestly think of you (they
--     bring up things you actually did)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Conversation = {}
local S

function Conversation.Init(services)
	S = services
end

local function pick(list)
	return list[math.random(1, #list)]
end

--------------------------------------------------------------------------------
-- Personalities (see Life.Personalities)
--------------------------------------------------------------------------------
local P = {}
Conversation.Personas = P

P.cheerful = {
	Tics = { "", " :)", " Isn't that great?" },
	Dream = { "I want to open a little flower shop and give everyone a free daisy on Mondays!", "Honestly? I'd love to throw the biggest street party this city has ever seen." },
	Fear = { "Rainy days that last a whole week. I need my sunshine!", "People being sad and me not noticing. That would break my heart." },
	Advice = { "Smile at a stranger today. It's free and it works!", "Bad days end. Good days start. Keep going!" },
	Food = { "Pancakes with way too much syrup!", "Anything from the Bakery. Their croissants are pure happiness." },
	Place = { "The fountain at the plaza! Everyone's always so happy there.", "Central Park at sunset. Gorgeous." },
}
P.shy = {
	Tics = { "", " ...um.", " *looks away*" },
	Dream = { "I... I'd like to write a book someday. Don't tell anyone.", "Maybe sing in front of people. Just once. Without fainting." },
	Fear = { "Crowds. And being asked to speak at the plaza.", "Phone calls. Why can't everyone just text?" },
	Advice = { "It's okay to go slow. You don't have to be loud to matter.", "Find one good friend. That's enough." },
	Food = { "Tea and a quiet muffin in the corner of the Cafe.", "Soup. Soup is safe." },
	Place = { "The Library. Nobody expects you to talk there.", "The far side of Mirror Lake. It's so peaceful." },
}
P.grumpy = {
	Tics = { "", " Hmph.", " Happy now?" },
	Dream = { "A day where nobody asks me anything. Present company included.", "Fixing every pothole in this city myself. Nobody else will." },
	Fear = { "Fear? I don't do fear. ...Okay, dentists.", "Running out of coffee. Now THAT'S scary." },
	Advice = { "Don't trust anyone who's cheerful before 9 AM.", "Mind your own business. Works every time." },
	Food = { "Black coffee. Food is for people with time.", "A plain burger. No fancy sauces." },
	Place = { "My own couch. Door locked.", "The Diner. They leave you alone there." },
}
P.chatty = {
	Tics = { "", " Anyway, where was I?", " Oh, and— never mind, later!" },
	Dream = { "Hosting my own talk show! I'd interview EVERYONE in town.", "Knowing every single person in this city by name. I'm about halfway!" },
	Fear = { "Silence. Awkward, awful silence.", "Losing my voice. Can you imagine?!" },
	Advice = { "Talk to people! Everyone's got a story, you just have to ask!", "Always say yes to lunch invites. ALWAYS." },
	Food = { "Whatever's being served at a party!", "Pizza, because you share it, and sharing means talking!" },
	Place = { "The plaza! You meet someone new every five minutes.", "The Cafe. Best gossip in town." },
}
P.bookish = {
	Tics = { "", " Fascinating, really.", " I read about that once." },
	Dream = { "Reading every book in the city library. I'm on shelf twelve.", "Discovering something nobody knew before. Even something small." },
	Fear = { "Libraries closing. Or spilling coffee on a first edition.", "Forgetting everything I've ever read." },
	Advice = { "Read a little every day. It adds up to a whole other life.", "Ask 'why' more often. Then look it up." },
	Food = { "Anything I can eat with one hand while reading.", "Tea and biscuits. Very literary." },
	Place = { "The Library, obviously. Third floor, by the window.", "The Museum. The dinosaur and I are old friends." },
}
P.sporty = {
	Tics = { "", " Let's go!", " No pain, no gain!" },
	Dream = { "Running a marathon in every city in the world.", "Coaching a team that wins the city championship." },
	Fear = { "Pulling a hamstring before a big game.", "Stairs being replaced by elevators everywhere." },
	Advice = { "Move every day. Your future self will thank you.", "Drink water. More than that. MORE." },
	Food = { "Grilled chicken and a big salad. And one donut. Cheat day.", "Protein shakes. So many protein shakes." },
	Place = { "The Gym, first thing in the morning.", "The running track at the Sports Field." },
}
P.artsy = {
	Tics = { "", " It's all about the colors.", " Very inspiring." },
	Dream = { "Painting a mural on the side of the Town Hall.", "My own gallery at the Museum. One day!" },
	Fear = { "Beige. A whole city painted beige.", "Running out of ideas." },
	Advice = { "Make something every day, even if it's bad. Especially if it's bad.", "Look up. The city is beautiful from different angles." },
	Food = { "Colorful food! Rainbow salad, berry smoothies.", "Ice cream. It looks like art and tastes like joy." },
	Place = { "Willow Park, by the easels.", "The rooftops at golden hour." },
}
P.curious = {
	Tics = { "", " Why do you think that is?", " Interesting!" },
	Dream = { "Figuring out how the whole city works. The pipes, the power, everything.", "Traveling somewhere nobody's ever mapped." },
	Fear = { "Never finding out the answer to something.", "Being bored. Truly bored." },
	Advice = { "Ask questions. The dumber they sound, the better the answers.", "Take a different street home every day." },
	Food = { "Whatever I haven't tried yet!", "The strangest thing on the Diner menu." },
	Place = { "The Factory. Have you seen those machines?", "The Museum. There's always something new." },
}
P.calm = {
	Tics = { "", " No rush.", " Breathe." },
	Dream = { "A little garden, a hammock, and nowhere to be.", "Teaching yoga by the lake at sunrise." },
	Fear = { "Losing my patience. It takes a lot, but it's happened.", "Loud alarms. They rattle me." },
	Advice = { "Breathe in for four, out for six. Works every time.", "Most things matter less than they seem right now." },
	Food = { "Green tea and a bowl of rice.", "A slow breakfast. The meal matters less than the pace." },
	Place = { "Mirror Lake, early morning. Mist on the water.", "The gazebo in Central Park." },
}
P.funny = {
	Tics = { "", " Get it?", " I'm here all week!" },
	Dream = { "Stand-up comedy at the Cinema. Sold out. Standing ovation. Mayor laughing so hard they cry.", "Making the grumpiest person in town laugh. I'm working on it." },
	Fear = { "Telling a joke and hearing crickets.", "Clowns. Ironic, I know." },
	Advice = { "If you can laugh at it, you can survive it.", "Never trust stairs. They're always up to something." },
	Food = { "Anything shaped like a face.", "Pie. Especially in someone else's face. Kidding! Mostly." },
	Place = { "The Arcade. The claw machine and I have a rivalry.", "The plaza, where the audience is!" },
}
-- the ten new personalities
P.brave = {
	Tics = { "", " Bring it on.", " I'm not scared." },
	Dream = { "Joining the fire department and running INTO the burning building.", "Standing up to every bully in this city." },
	Fear = { "Standing by while someone gets hurt.", "Honestly? Heights. Don't tell anyone." },
	Advice = { "Do the scary thing first. Everything after is easy.", "If someone needs help, help. Don't wait for someone else." },
	Food = { "The spiciest thing on any menu.", "Steak. Big one." },
	Place = { "The Fire Station. Those people are heroes.", "Anywhere there's trouble, honestly." },
}
P.anxious = {
	Tics = { "", " ...is that okay?", " Sorry, I'm rambling." },
	Dream = { "One whole week without worrying about anything.", "Being the kind of person who just... relaxes." },
	Fear = { "Everything? Crime, being late, forgetting the stove on...", "That I said something weird three days ago and everyone remembers." },
	Advice = { "Check the stove twice. Then once more.", "It's okay to leave early if you're overwhelmed." },
	Food = { "Chamomile tea. Very calming. Supposedly.", "Comfort food. Mac and cheese." },
	Place = { "Home, with the door locked.", "The Library. Quiet, safe, no surprises." },
}
P.romantic = {
	Tics = { "", " How lovely.", " *sighs dreamily*" },
	Dream = { "Finding my true love under the stars at Mirror Lake.", "A wedding at the plaza fountain with the whole city invited." },
	Fear = { "Growing old without someone to hold hands with.", "Missing my soulmate because I was looking at my phone." },
	Advice = { "Tell people you love them. Today. You never know.", "Write letters. Real ones, with ink." },
	Food = { "Candlelit dinner at the Restaurant. Pasta for two.", "Chocolate-dipped strawberries." },
	Place = { "The pier at Mirror Lake at sunset.", "The gazebo in the park. So romantic!" },
}
P.ambitious = {
	Tics = { "", " Time is money.", " Big plans." },
	Dream = { "Being mayor. Then maybe more.", "Owning half the shops on the shopping street." },
	Fear = { "Being ordinary.", "Someone else getting the promotion I deserve." },
	Advice = { "Work while they sleep. Win while they wonder.", "Network. Every conversation is an opportunity. Like this one!" },
	Food = { "Whatever's fastest. Lunch is for closing deals.", "Fancy dinners at the Restaurant. Business, of course." },
	Place = { "The top floor of the office towers. Great view of my future.", "The Bank. I like being near money." },
}
P.lazy = {
	Tics = { "", " *yawns*", " ...eventually." },
	Dream = { "A nap that lasts a whole weekend.", "Being paid to test sofas." },
	Fear = { "Alarm clocks.", "Being asked to help someone move house." },
	Advice = { "Why do today what you can do tomorrow?", "Sit down whenever you can. Standing is overrated." },
	Food = { "Whatever gets delivered.", "Cold pizza. No cooking required." },
	Place = { "Any bench. Seriously, any bench.", "My bed." },
}
P.sarcastic = {
	Tics = { "", " Obviously.", " Wow. Shocking." },
	Dream = { "Oh, you know. World peace. And a sandwich.", "One day without anyone asking me my dream. Oh wait." },
	Fear = { "Being sincere in public.", "Running out of witty comebacks. Never happened. Yet." },
	Advice = { "Expect nothing. Then everything is a pleasant surprise.", "Nod and smile. It confuses people." },
	Food = { "Anything that doesn't talk back.", "Burnt toast. It's a lifestyle." },
	Place = { "Wherever you're not. Kidding. Mostly. The Arcade's alright.", "The Diner. The coffee's as bitter as I am." },
}
P.kind = {
	Tics = { "", " Take care of yourself, okay?", " You're doing great." },
	Dream = { "Making sure nobody in this city ever goes hungry.", "Volunteering at the Community Center every day." },
	Fear = { "Someone needing help and me not being there.", "People being unkind to each other for no reason." },
	Advice = { "Be gentle with people. Everyone's carrying something.", "Share what you have. It comes back around." },
	Food = { "Home cooking, shared with friends.", "Soup I made for a sick neighbor. The best kind." },
	Place = { "The Community Center. Everyone's welcome there.", "The hospital garden. I visit patients sometimes." },
}
P.nosy = {
	Tics = { "", " Don't tell anyone I told you.", " Ooh, interesting..." },
	Dream = { "Knowing every secret in this city. For safekeeping, of course.", "Running the city news board." },
	Fear = { "Missing the big news because I was asleep.", "Someone keeping a secret from ME." },
	Advice = { "Watch people. You learn everything by watching.", "Always look out the window when you hear a noise." },
	Food = { "Whatever my neighbors are cooking. I peek.", "The Cafe's pastries. And the Cafe's gossip." },
	Place = { "My front window. Best view on the street.", "The plaza bench by the news board." },
}
P.adventurous = {
	Tics = { "", " Let's go explore!", " What an adventure!" },
	Dream = { "Climbing the mountains past the city limits.", "Sailing across Mirror Lake on a raft I built myself." },
	Fear = { "A boring life. Same street, same day, forever.", "Being stuck indoors." },
	Advice = { "Say yes to things. Especially the weird ones.", "Get lost on purpose sometimes." },
	Food = { "Campfire food! Burnt marshmallows included.", "Whatever the locals eat." },
	Place = { "The woods at the edge of town.", "The top of the tallest office tower. The view!" },
}
P.proud = {
	Tics = { "", " Naturally.", " I'm rather good at it, you know." },
	Dream = { "A statue of me at the plaza. Tasteful. Bronze.", "Being remembered as the best in this city at what I do." },
	Fear = { "Being laughed at.", "Losing. At anything." },
	Advice = { "Carry yourself like you already won.", "Never let them see you sweat." },
	Food = { "Only the finest from the Restaurant.", "I make an excellent lasagna. Everyone says so." },
	Place = { "The Town Hall steps. Very distinguished.", "The Grand Hotel lobby. Classy." },
}

-- the personality's verbal habit, now and then
function Conversation.Tic(c)
	local persona = P[c.Personality or ""]
	if persona and math.random() < 0.45 then
		return pick(persona.Tics)
	end
	return ""
end

--------------------------------------------------------------------------------
-- Follow-up questions
--------------------------------------------------------------------------------
local HARD = {
	Hospital = "the long shifts, and the patients you can't help.", Bakery = "waking up at 4 AM. Every. Single. Day.", Cafe = "the morning rush. Forty lattes before 8!",
	PoliceStation = "the paperwork. And people running from me.", School = "thirty kids and one of me.", Factory = "the noise. My ears ring all night.",
	Shop = "customers who can't find the milk that's right in front of them.", TownHall = "forms. So many forms.", Park = "the geese. They're vicious.",
	Bank = "counting other people's money all day.", FireStation = "the waiting. Then the running.", Library = "people who talk loudly on the phone.",
	Restaurant = "the dinner rush. Total chaos.", Office = "meetings that could have been emails.", Gym = "people who don't wipe down the machines.",
	Warehouse = "heavy boxes and sore backs.", GasStation = "grease. Everywhere. Forever.", PostOffice = "dogs. Every dog in town hates the mail carrier.",
}
local DREAM_JOBS = { "astronaut", "rock star", "chef with my own restaurant", "detective", "zookeeper", "pilot", "game designer", "marine biologist", "movie star", "inventor", "mayor", "professional napper" }

local FOLLOW = {}
FOLLOW.howday = function(c)
	local mood = S.City.MoodOf(c)
	return {
		{ Key = "why", Text = if mood >= 55 then "😊 What's got you in a good mood?" else "😟 Why's it a rough day?" },
		{ Key = "helpout", Text = "🤝 Anything I can do?" },
	}
end
FOLLOW.job = function(c)
	local stage = S.Life:Stage(c)
	if stage ~= "Adult" then
		return { { Key = "dreamjob", Text = "🌠 What do you want to be when you grow up?" } }
	end
	return {
		{ Key = "likejob", Text = "❤️ Do you like it?" },
		{ Key = "hardest", Text = "😓 What's the hardest part?" },
		{ Key = "dreamjob", Text = "🌠 Dream job?" },
	}
end
FOLLOW.family = function(c)
	return {
		{ Key = "hobby", Text = "🎨 What do you do for fun?" },
		{ Key = "deep", Text = "💭 Let's really talk..." },
	}
end
FOLLOW.gossip = function()
	return { { Key = "gossip", Text = "👂 Anyone else?" } }
end

function Conversation.FollowUps(topic, c)
	local fn = FOLLOW[topic]
	return fn and fn(c) or nil
end

-- the "let's really talk" menu
function Conversation.DeepMenu(c)
	return {
		{ Key = "dream", Text = "🌠 What's your dream?" },
		{ Key = "fear", Text = "😨 What scares you?" },
		{ Key = "advice", Text = "🦉 Any advice for me?" },
		{ Key = "food", Text = "🍕 Favorite food?" },
		{ Key = "place", Text = "📍 Favorite spot in the city?" },
		{ Key = "memory", Text = "📸 Best memory?" },
		{ Key = "aboutme", Text = "🪞 What do you think of me?" },
	}
end

--------------------------------------------------------------------------------
-- Answers: returns text, expression, then an optional opinion change
--------------------------------------------------------------------------------
local A = {}

A.why = function(c, player, brain)
	local mood = S.City.MoodOf(c)
	local reasons = {}
	local mems = S.City.MemoriesOf(c, player)
	if mems[1] and mems[1].d == S.City.Day() then
		table.insert(reasons, (if mems[1].f > 0 then "Well, you " .. mems[1].t .. " today! That helped." else "You " .. mems[1].t .. ". Remember?"))
	end
	if (c.MoodBoost or 0) < -20 then
		table.insert(reasons, "Someone attacked me earlier. I keep looking over my shoulder.")
	end
	local stateId = S.City.CityState()
	if stateId == "Celebrating" or stateId == "Prosperous" then
		table.insert(reasons, "The whole city's doing great! You can feel it.")
	elseif stateId == "Chaos" or stateId == "Unrest" or stateId == "Tense" then
		table.insert(reasons, "The city's on edge. Crime, fights... it gets to you.")
	end
	if S.Life:Stage(c) == "Adult" and not c.Job then
		table.insert(reasons, "I still haven't found a job. The bills don't care.")
	end
	local h = S.Life.Households[c.Household]
	if h and h.Expecting then
		table.insert(reasons, "We're having a baby! I can't stop smiling.")
	end
	if #reasons == 0 then
		table.insert(reasons, if mood >= 55 then pick({ "Just one of those days where everything goes right.", "Good weather, good coffee. Simple.", "I finally finished something I'd been putting off!" }) else pick({ "Didn't sleep well. That's all.", "Just tired, I think.", "Nothing in particular. Just gray inside." }))
	end
	return reasons[1], if mood >= 55 then "happy" else "sad"
end

A.helpout = function(c, player)
	local mood = S.City.MoodOf(c)
	if mood < 50 then
		S.City.Boost(c, 6)
		return pick({ "...You know what? Just asking helps. Thank you.", "That's really kind. I feel a little better already.", "Nobody's asked me that in a while. Thanks." }), "love", 5
	end
	return pick({ "Ha, I'm fine! But thanks for asking.", "You're sweet. I'm good, really!", "Just keep being you!" }), "happy", 2
end

A.likejob = function(c)
	local mood = S.City.MoodOf(c)
	local p = c.Personality
	if p == "lazy" then
		return "Like it? I like the lunch breaks.", "neutral"
	elseif p == "ambitious" then
		return "It's a stepping stone. I'll be running the place in two years.", "grin"
	elseif mood >= 60 or p == "cheerful" or p == "kind" then
		return pick({ "I really do! I get to help people every day.", "Love it. Wouldn't trade it.", "Most days, yes! The people make it." }), "happy"
	end
	return pick({ "It pays the bills.", "It's... a job.", "Some days. Not today." }), "neutral"
end

A.hardest = function(c)
	local job = S.Life.Jobs(Config, c.Job or "")
	local hard = job and HARD[job.place]
	return "The hardest part? " .. (if hard then string.upper(string.sub(hard, 1, 1)) .. string.sub(hard, 2) else "Honestly, getting up in the morning."), "focused"
end

A.dreamjob = function(c)
	local stage = S.Life:Stage(c)
	local dream = DREAM_JOBS[(c.Id * 7) % #DREAM_JOBS + 1]
	if stage == "Child" then
		return "A " .. dream .. "! Or a dinosaur. Can you be a dinosaur?", "grin"
	elseif stage == "Teen" then
		return "Probably a " .. dream .. ". Or something with computers. I don't know, don't ask my parents.", "neutral"
	end
	return "If I could do anything? " .. string.upper(string.sub(dream, 1, 1)) .. string.sub(dream, 2) .. ". Don't laugh!", "happy"
end

A.hobby = function(c)
	local hobby = c.Hobby or "reading"
	local lines = {
		"I'm really into " .. hobby .. ". It's how I unwind.",
		"Oh, " .. hobby .. "! I try to do it at least twice a week. You should come sometime!",
		"You'll usually find me " .. hobby .. " when I'm not busy.",
	}
	return pick(lines), "happy"
end

local function persona(c)
	return P[c.Personality or ""] or P.cheerful
end
A.dream = function(c)
	return pick(persona(c).Dream), "love"
end
A.fear = function(c)
	return pick(persona(c).Fear), "scared"
end
A.advice = function(c)
	return pick(persona(c).Advice), "happy"
end
A.food = function(c)
	return pick(persona(c).Food), "grin"
end
A.place = function(c)
	return pick(persona(c).Place), "happy"
end

A.memory = function(c, player)
	-- a good memory with you, if there is one
	for _, m in ipairs(S.City.MemoriesOf(c, player)) do
		if m.f >= 5 then
			return "Honestly? The time you " .. m.t .. ". That meant a lot.", "love"
		end
	end
	local h = S.Life.Households[c.Household]
	local lines = {
		"The day I moved to this city. Everything felt new.",
		"Watching fireworks from the pier at Mirror Lake.",
		"My first day at work. I was so nervous I wore my shirt inside out!",
		"A snowball fight in Central Park that got completely out of hand.",
	}
	if h and #h.Members > 1 then
		table.insert(lines, "Family dinners. Nothing fancy, just all of us laughing.")
	end
	return pick(lines), "happy"
end

A.aboutme = function(c, player)
	local op = S.City.Opinion(c, player)
	local mems = S.City.MemoriesOf(c, player)
	local good, bad
	for _, m in ipairs(mems) do
		if not good and m.f >= 4 then
			good = m
		elseif not bad and m.f <= -4 then
			bad = m
		end
	end
	local p = c.Personality
	if op >= 50 then
		return "You're one of my favorite people in this city." .. (if good then " You " .. good.t .. ", remember? I won't forget that." else ""), "love"
	elseif op >= 15 then
		return "I like you! " .. (if good then "You " .. good.t .. ". That was nice." else "You seem like a good person."), "happy"
	elseif op <= -30 then
		return (if bad then "You " .. bad.t .. ". So... not great, honestly." else "I don't trust you. Sorry."), "angry"
	elseif op < 0 then
		return (if bad then "Well... you " .. bad.t .. ". I'm trying to get past it." else "I'm still making up my mind about you."), "focused"
	end
	if p == "sarcastic" then
		return "You? You're... a person. Congratulations.", "neutral"
	elseif p == "nosy" then
		return "I don't know much about you yet. Which is a problem. Tell me EVERYTHING.", "grin"
	end
	return "We don't really know each other yet. But I'd like to!", "neutral"
end

function Conversation.Has(key)
	return A[key] ~= nil
end

-- text, expression, opinion change
function Conversation.Answer(key, c, player, brain)
	local fn = A[key]
	if not fn then
		return nil
	end
	local text, expr, feeling = fn(c, player, brain)
	return text .. Conversation.Tic(c), expr, feeling
end

return Conversation
