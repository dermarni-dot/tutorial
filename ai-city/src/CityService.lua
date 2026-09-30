-- CityService (ModuleScript) — ServerScriptService.Modules.CityService
-- The city itself: the clock and calendar, city stats (economy, safety,
-- happiness) and the city's mood, the mayor, elections, speeches, policies,
-- coins, what citizens remember about players (and gossip about), the news,
-- and saving everything.
--
-- Talks to players through ReplicatedStorage.CityRemotes:
--   Event   (RemoteEvent)    server -> client: { Type = "Toast"/"News"/"Speech"/"Election"/... }
--   Request (RemoteFunction) client -> server: { Action = "Speech"/"Vote"/"Policy"/... }
-- and keeps ReplicatedStorage.CityState's attributes up to date for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Atmosphere = require(Shared:WaitForChild("Atmosphere"))

local CityService = {}
local S -- the shared services table (see Main)

local state = {
	Economy = 55,
	Safety = 62,
	Happiness = 58,
	Day = 0,
	Mayor = nil, -- { Name, Kind = "player"/"citizen", UserId, CitizenId, Stances = { ids } }
	Policies = {}, -- the last few passed: { Id, Label, Day, By }
	News = {}, -- newest first: { Text, Kind, Day, Hour }
	Heat = 0, -- recent crime (decays)
	Crimes = 0, -- crimes today
	Births = 0,
}
CityService.State = state
local playerData = {} -- [player] = { Coins, Stances, LastSpeech, LastPolicyDay, Vote, Crimes, Talks }
local votes = {} -- [player] = candidate key
local candidates = {} -- key -> { Key, Name, Kind, UserId, CitizenId, Stances }
local nextElection = 0
local handlers = {}
local stanceById = {}
for _, s in ipairs(Config.Stances or {}) do
	stanceById[s.id] = s
end
CityService.StanceById = stanceById

local stateFolder, remotes

-- For your own scripts: CityService.Event.Event:Connect(function(kind, ...) end)
-- kinds: "NewDay" (day), "Expecting" / "GrewUp" / "Retired" (text, citizen or household),
-- "Born" (baby), "Crime" (severity), "Speech" (player, stances), "Election" (winner, results),
-- "Policy" (stanceId, byName), "News" (text, kind)
local event = Instance.new("BindableEvent")
event.Name = "CityEvent"
CityService.Event = event
function CityService.Fire(kind, ...)
	event:Fire(kind, ...)
end
local store = nil
local SAVE_KEY = "City_v3"

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local function makeRemotes()
	remotes = ReplicatedStorage:FindFirstChild("CityRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "CityRemotes"
		remotes.Parent = ReplicatedStorage
	end
	local event = remotes:FindFirstChild("Event") or Instance.new("RemoteEvent")
	event.Name = "Event"
	event.Parent = remotes
	local request = remotes:FindFirstChild("Request") or Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = remotes
	CityService.Remotes = { Event = event, Request = request }

	-- one entry point for every client request, with a simple rate limit
	local budget = {}
	request.OnServerInvoke = function(player, data)
		if type(data) ~= "table" or type(data.Action) ~= "string" then
			return { Ok = false, Error = "Bad request" }
		end
		local now = os.clock()
		local b = budget[player] or { Tokens = 15, At = now }
		b.Tokens = math.min(15, b.Tokens + (now - b.At) * 8)
		b.At = now
		budget[player] = b
		if b.Tokens < 1 then
			return { Ok = false, Error = "Slow down!" }
		end
		b.Tokens -= 1
		local handler = handlers[data.Action]
		if not handler then
			return { Ok = false, Error = "Unknown action" }
		end
		local ok, result = pcall(handler, player, data)
		if not ok then
			warn("[CityService] " .. data.Action .. ": " .. tostring(result))
			return { Ok = false, Error = "Something went wrong" }
		end
		return result
	end
	event.OnServerEvent:Connect(function(player, data)
		if type(data) == "table" and type(data.Action) == "string" and handlers[data.Action] then
			local ok, err = pcall(handlers[data.Action], player, data)
			if not ok then
				warn("[CityService] " .. data.Action .. ": " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
	end)
end

-- Register a client request handler: fn(player, data) -> result table
function CityService.Handle(action, fn)
	handlers[action] = fn
end

function CityService.Send(player, data)
	CityService.Remotes.Event:FireClient(player, data)
end

function CityService.Broadcast(data)
	CityService.Remotes.Event:FireAllClients(data)
end

-- Send to every player within radius of a position
function CityService.SendNear(position, radius, data)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			CityService.Remotes.Event:FireClient(player, data)
		end
	end
end

function CityService.Toast(player, icon, title, text, color)
	CityService.Send(player, { Type = "Toast", Icon = icon, Title = title, Text = text, Color = color })
end

--------------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------------
function CityService.Hour()
	return Lighting.ClockTime
end

function CityService.Day()
	return state.Day
end

local function weekday(day)
	return S.Life:WeekdayName(day)
end

local function onNewDay()
	state.Day += 1
	state.Crimes = 0
	local events = S.Life:NewDay(state.Day)
	CityService.Fire("NewDay", state.Day)
	for _, e in ipairs(events) do
		if e.Kind == "Expecting" or e.Kind == "GrewUp" or e.Kind == "Retired" then
			CityService.News(e.Text, e.Kind)
		end
		CityService.Fire(e.Kind, e.Text, e.Citizen or e.Household)
	end
	-- today's weather (everyone sees the same sky)
	local weather = Atmosphere.PickWeather(Random.new(state.Day * 977 + 13))
	if stateFolder then
		stateFolder:SetAttribute("Weather", weather)
	end
	local w = Atmosphere.WEATHER[weather]
	CityService.News("☀️ Good morning, AI City! It's " .. weekday(state.Day) .. ", day " .. state.Day .. ". " .. (w and w.Label or "") .. " today.", "Day", true)
	for player in pairs(playerData) do
		CityService.Send(player, { Type = "Goals", Goals = CityService.Goals(player), NewDay = true })
	end
	if S.Citizens and S.Citizens.OnNewDay then
		S.Citizens.OnNewDay(state.Day, events)
	end
end

-- Runs the day/night cycle (1 in-game day = Config.DAY_LENGTH real seconds)
function CityService.StartClock(startHour, runCycle)
	if runCycle ~= false then
		Lighting.ClockTime = startHour or 8
	end
	Atmosphere.Setup(Lighting)
	local hoursPerSecond = 24 / (Config.DAY_LENGTH or 480)
	local lastHour = Lighting.ClockTime
	local lastSlow = 0
	RunService.Heartbeat:Connect(function(dt)
		if runCycle ~= false then
			Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		end
		local h = Lighting.ClockTime
		if h < lastHour - 12 then
			onNewDay()
		end
		lastHour = h
		local now = os.clock()
		if now - lastSlow >= 1 then
			lastSlow = now
			Atmosphere.Apply(Lighting, h)
			S.MapBuilder.SetNight(Atmosphere.IsNight(h))
			-- empty houses get their furniture when a player comes near (so every
			-- house you walk into is furnished, without building them all at once)
			if S.MapBuilder.FurnishNear then
				for _, player in ipairs(Players:GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						pcall(S.MapBuilder.FurnishNear, root.Position, 80)
					end
				end
			end
			if S.Map.ClockFace then
				S.Map.ClockFace.Text = string.format("%02d:%02d", math.floor(h), math.floor((h % 1) * 60))
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- City stats and mood
--------------------------------------------------------------------------------
local function clamp(x)
	return math.clamp(x, 0, 100)
end

function CityService.Adjust(stat, amount)
	if state[stat] then
		state[stat] = clamp(state[stat] + amount)
	end
end

-- Records a crime: lowers safety and raises "heat" (which makes the city tense)
function CityService.Crime(severity)
	CityService.Fire("Crime", severity)
	state.Crimes += 1
	state.Heat = math.min(100, state.Heat + severity * 6)
	CityService.Adjust("Safety", -severity * 1.5)
	CityService.Adjust("Happiness", -severity * 0.5)
end

function CityService.CityState()
	local e, s, h = state.Economy, state.Safety - state.Heat * 0.25, state.Happiness
	local avg = (e + s + h) / 3
	if avg < 22 or s < 12 then
		return "Chaos"
	elseif avg < 32 or s < 24 then
		return "Unrest"
	elseif avg < 42 then
		return "Tense"
	elseif h >= 76 and avg >= 64 then
		return "Celebrating"
	elseif e >= 72 then
		return "Prosperous"
	elseif s >= 64 and h >= 60 then
		return "Peaceful"
	end
	return "Stable"
end

-- How a citizen feels right now (0-100)
local PERSONALITY_MOOD = { cheerful = 14, funny = 10, chatty = 6, calm = 5, sporty = 5, artsy = 2, curious = 3, bookish = 0, shy = -2, grumpy = -14, brave = 4, anxious = -8, romantic = 6, ambitious = 0, lazy = 2, sarcastic = -6, kind = 10, nosy = 3, adventurous = 8, proud = 2 }
function CityService.MoodOf(c)
	local mood = 58 + (state.Happiness - 50) * 0.35 + (state.Safety - 50) * 0.15 + (PERSONALITY_MOOD[c.Personality] or 0)
	local stage = S.Life:Stage(c)
	if stage == "Adult" and not c.Job then
		mood -= 8
	end
	mood += c.MoodBoost or 0
	return clamp(mood)
end

function CityService.Boost(c, amount)
	c.MoodBoost = math.clamp((c.MoodBoost or 0) + amount, -60, 40)
end

function CityService.ExpressionFor(c)
	local mood = CityService.MoodOf(c)
	if mood >= 78 then
		return if c.Personality == "funny" then "grin" else "happy"
	elseif mood >= 55 then
		return if c.Personality == "grumpy" then "focused" else "neutral"
	elseif mood >= 35 then
		return "focused"
	elseif mood >= 20 then
		return "sad"
	end
	return "angry"
end

-- Every in-game hour: stats drift back toward normal, heat and mood boosts fade
local function hourlyDrift()
	for _, stat in ipairs({ "Economy", "Safety", "Happiness" }) do
		local target = 55
		state[stat] += (target - state[stat]) * 0.03
	end
	state.Heat *= 0.8
	for _, c in ipairs(S.Life.List) do
		if c.MoodBoost then
			c.MoodBoost *= 0.85
			if math.abs(c.MoodBoost) < 0.5 then
				c.MoodBoost = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Memories and opinions: what citizens think of each player
--------------------------------------------------------------------------------
local function key(player)
	return tostring(if typeof(player) == "Instance" then player.UserId else player)
end

function CityService.Opinion(c, player)
	return (c.Opinions and c.Opinions[key(player)]) or 0
end

-- text: first person ("gave me a gift"); gossip: third person ("gave Maria a gift")
function CityService.Remember(c, player, text, feeling, gossip)
	c.Memories = c.Memories or {}
	c.Opinions = c.Opinions or {}
	local k = key(player)
	table.insert(c.Memories, 1, { u = k, n = player.DisplayName or player.Name, t = text, g = gossip or text, f = feeling, d = state.Day, h = 0 })
	while #c.Memories > (Config.MEMORY_LIMIT or 30) do
		table.remove(c.Memories)
	end
	c.Opinions[k] = math.clamp((c.Opinions[k] or 0) + feeling, -100, 100)
end

-- What c remembers about a player (newest first)
function CityService.MemoriesOf(c, player)
	local out = {}
	local k = key(player)
	for _, m in ipairs(c.Memories or {}) do
		if m.u == k then
			table.insert(out, m)
		end
	end
	return out
end

-- a tells b something they remember about a player. Returns a line for a's
-- speech bubble (or nil if a has nothing interesting to share).
local lastGossip = {}
function CityService.Gossip(a, b)
	local now = os.clock()
	if lastGossip[a.Id] and now - lastGossip[a.Id] < (Config.GOSSIP_COOLDOWN or 22) then
		return nil
	end
	for _, m in ipairs(a.Memories or {}) do
		if math.abs(m.f) >= 5 and (m.h or 0) < 2 then
			-- b hasn't heard this one yet?
			local known = false
			for _, other in ipairs(b.Memories or {}) do
				if other.u == m.u and other.g == m.g then
					known = true
					break
				end
			end
			if not known then
				lastGossip[a.Id] = now
				b.Memories = b.Memories or {}
				b.Opinions = b.Opinions or {}
				table.insert(b.Memories, 1, { u = m.u, n = m.n, t = "heard from " .. a.First .. " that " .. m.n .. " " .. m.g, g = m.g, f = m.f * 0.5, d = state.Day, h = (m.h or 0) + 1 })
				while #b.Memories > (Config.MEMORY_LIMIT or 30) do
					table.remove(b.Memories)
				end
				b.Opinions[m.u] = math.clamp((b.Opinions[m.u] or 0) + m.f * 0.5, -100, 100)
				local opener = if m.f > 0 then "Did you hear? " else "Ugh, did you hear? "
				return opener .. m.n .. " " .. m.g .. "!"
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- News
--------------------------------------------------------------------------------
function CityService.News(text, kind, quiet)
	table.insert(state.News, 1, { Text = text, Kind = kind or "News", Day = state.Day, Hour = CityService.Hour() })
	while #state.News > 30 do
		table.remove(state.News)
	end
	S.MapBuilder.SetNews(text)
	CityService.Fire("News", text, kind or "News")
	if not quiet then
		CityService.Broadcast({ Type = "News", Text = text, Kind = kind or "News" })
	end
end

--------------------------------------------------------------------------------
-- Players: coins and data
--------------------------------------------------------------------------------
function CityService.Data(player)
	return playerData[player]
end

function CityService.Coins(player)
	return playerData[player] and playerData[player].Coins or 0
end

function CityService.AddCoins(player, amount, reason)
	local data = playerData[player]
	if not data then
		return false
	end
	data.Coins = math.max(0, math.floor(data.Coins + amount))
	player:SetAttribute("Coins", data.Coins)
	if reason then
		CityService.Send(player, { Type = "Coins", Amount = amount, Reason = reason })
	end
	return true
end

function CityService.Spend(player, amount, reason)
	local data = playerData[player]
	if not data or data.Coins < amount then
		return false
	end
	return CityService.AddCoins(player, -amount, reason)
end

local playerStore
local function loadPlayer(player)
	local saved
	if playerStore then
		local ok, result = pcall(function()
			return playerStore:GetAsync("p_" .. player.UserId)
		end)
		if ok then
			saved = result
		end
	end
	saved = type(saved) == "table" and saved or {}
	local data = {
		Coins = tonumber(saved.Coins) or Config.STARTING_COINS or 100,
		Stances = {},
		LastSpeech = -math.huge,
		LastPolicyDay = -1,
		Crimes = tonumber(saved.Crimes) or 0,
		Notoriety = tonumber(saved.Notoriety) or 0,
		Weapons = type(saved.Weapons) == "table" and saved.Weapons or {},
		Outfits = type(saved.Outfits) == "table" and saved.Outfits or {},
		Wearing = type(saved.Wearing) == "table" and saved.Wearing or {},
		Fitness = type(saved.Fitness) == "table" and { Level = tonumber(saved.Fitness.Level) or 1, XP = tonumber(saved.Fitness.XP) or 0 } or { Level = 1, XP = 0 },
		Talks = tonumber(saved.Talks) or 0,
		Arrests = tonumber(saved.Arrests) or 0,
		Terms = tonumber(saved.Terms) or 0,
		Home = type(saved.Home) == "string" and saved.Home or nil,
	}
	playerData[player] = data
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Title", if state.Mayor and state.Mayor.UserId == player.UserId then "Mayor" else "Citizen")
	player:SetAttribute("Wanted", 0)
	player:SetAttribute("Notoriety", math.floor(data.Notoriety))
	CityService.Send(player, { Type = "Goals", Goals = CityService.Goals(player) })
	CityService.Send(player, { Type = "Welcome", Day = state.Day, Weekday = weekday(state.Day), Mayor = state.Mayor and state.Mayor.Name, State = CityService.CityState() })
end

local function savePlayer(player)
	local data = playerData[player]
	if data and playerStore then
		pcall(function()
			playerStore:SetAsync("p_" .. player.UserId, { Coins = data.Coins, Crimes = data.Crimes, Notoriety = data.Notoriety, Weapons = data.Weapons, Outfits = data.Outfits, Wearing = data.Wearing, Fitness = data.Fitness, Talks = data.Talks, Arrests = data.Arrests, Terms = data.Terms, Home = data.Home })
		end)
	end
end

--------------------------------------------------------------------------------
-- Values: how much an idea appeals to a citizen (-1 .. 1)
--------------------------------------------------------------------------------
function CityService.Appeal(c, stanceId)
	local stance = stanceById[stanceId]
	if not stance then
		return 0
	end
	local score = 0
	for v, weight in pairs(stance.values or {}) do
		score += weight * ((c.Values and c.Values[v]) or 0)
	end
	return math.clamp(score, -1, 1)
end

-- the value a citizen cares about most (for dialogue)
function CityService.TopValue(c)
	local best, bestV = nil, -math.huge
	for v, x in pairs(c.Values or {}) do
		if x > bestV then
			best, bestV = v, x
		end
	end
	return best, bestV
end

--------------------------------------------------------------------------------
-- Speeches (on the plaza stage)
--------------------------------------------------------------------------------
local REACT_YES = { "Yes!", "Now we're talking!", "I like that!", "Finally!", "👏👏👏", "That's what we need!", "Count me in!" }
local REACT_NO = { "Boo!", "No way!", "Not in my city!", "Ugh...", "👎", "Terrible idea!", "Hmm, no." }

handlers.Speech = function(player, data)
	local pd = playerData[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not pd or not root then
		return { Ok = false, Error = "You need to be in the city." }
	end
	if not S.Map.SpeechSpot or (root.Position - S.Map.SpeechSpot).Magnitude > 16 then
		return { Ok = false, Error = "Step up to the podium on the plaza stage first." }
	end
	local wait = (Config.SPEECH_COOLDOWN or 45) - (os.clock() - pd.LastSpeech)
	if wait > 0 then
		return { Ok = false, Error = string.format("Catch your breath! You can speak again in %d seconds.", math.ceil(wait)) }
	end
	if player:GetAttribute("Wanted") and player:GetAttribute("Wanted") > 0 then
		return { Ok = false, Error = "Nobody listens to a wanted criminal. Lose the police first!" }
	end
	local picked = {}
	for _, id in ipairs(type(data.Stances) == "table" and data.Stances or {}) do
		if stanceById[id] and #picked < 2 and not table.find(picked, id) then
			table.insert(picked, id)
		end
	end
	if #picked == 0 then
		return { Ok = false, Error = "Pick at least one idea to talk about." }
	end
	pd.LastSpeech = os.clock()
	CityService.Progress(player, "speech", 1)
	pd.Stances = picked
	candidates["p" .. player.UserId] = { Key = "p" .. player.UserId, Name = player.DisplayName, Kind = "player", UserId = player.UserId, Stances = picked }
	local lines = {}
	for _, id in ipairs(picked) do
		local s = stanceById[id]
		table.insert(lines, s.label .. "! " .. s.pitch)
	end
	local speechText = table.concat(lines, "  ")
	CityService.Fire("Speech", player, picked)
	CityService.Broadcast({ Type = "Speech", Name = player.DisplayName, UserId = player.UserId, Text = speechText, Stances = picked, Character = player.Character })
	-- everyone in earshot reacts
	local liked, disliked, meh = 0, 0, 0
	local quotes = {}
	local rng = Random.new()
	for _, brain in ipairs(S.Citizens.Nearby(S.Map.SpeechSpot, Config.SPEECH_RADIUS or 75)) do
		local c = brain.C
		if S.Life:Age(c) >= 13 and S.Citizens.CanReact(brain) then
			local score = 0
			for _, id in ipairs(picked) do
				score += CityService.Appeal(c, id)
			end
			score /= #picked
			local mult = if c.Personality == "curious" or c.Personality == "chatty" or c.Personality == "nosy" then 1.25 elseif c.Personality == "grumpy" then 0.8 else 1
			local delta = math.clamp(score * 22 * mult + rng:NextNumber(-3, 3), -18, 18)
			local label = string.lower(stanceById[picked[1]].label)
			CityService.Remember(c, player, if delta >= 0 then "promised to " .. label .. " (I liked it)" else "wants to " .. label .. " (bad idea)", delta, "gave a speech about how we should " .. label)
			local line
			if delta > 5 then
				liked += 1
				line = REACT_YES[rng:NextInteger(1, #REACT_YES)]
				S.Citizens.React(brain, "cheer", line, "grin", 3, root.Position)
			elseif delta < -5 then
				disliked += 1
				line = REACT_NO[rng:NextInteger(1, #REACT_NO)]
				S.Citizens.React(brain, "boo", line, "angry", 3, root.Position)
			else
				meh += 1
				S.Citizens.React(brain, "watch", nil, "neutral", 3, root.Position)
			end
			if line and #quotes < 4 then
				table.insert(quotes, c.First .. ": \"" .. line .. "\"")
			end
		end
	end
	if liked + disliked + meh > 0 then
		CityService.News("🎤 " .. player.DisplayName .. " gave a speech: \"" .. stanceById[picked[1]].label .. "!\" (" .. liked .. " cheered, " .. disliked .. " booed)", "Speech")
	end
	return { Ok = true, Liked = liked, Disliked = disliked, Neutral = meh, Quotes = quotes }
end

--------------------------------------------------------------------------------
-- Elections
--------------------------------------------------------------------------------
local function citizenCandidate(c, rng)
	-- a platform: the two ideas that fit their values best
	local scored = {}
	for _, s in ipairs(Config.Stances or {}) do
		table.insert(scored, { s.id, CityService.Appeal(c, s.id) + rng:NextNumber(0, 0.2) })
	end
	table.sort(scored, function(a, b)
		return a[2] > b[2]
	end)
	return { Key = "c" .. c.Id, Name = c.Name, Kind = "citizen", CitizenId = c.Id, Stances = { scored[1][1], scored[2][1] } }
end

local function refreshCitizenCandidates()
	for k, cand in pairs(candidates) do
		if cand.Kind == "citizen" then
			candidates[k] = nil
		end
	end
	local rng = Random.new(state.Day * 13 + 5)
	local adults = {}
	for _, c in ipairs(S.Life.List) do
		local stage = S.Life:Stage(c)
		if stage == "Adult" or stage == "Retired" then
			table.insert(adults, c)
		end
	end
	if #adults == 0 then
		return
	end
	-- the citizen mayor runs again; one or two challengers join
	if state.Mayor and state.Mayor.Kind == "citizen" and S.Life.Citizens[state.Mayor.CitizenId] then
		local c = S.Life.Citizens[state.Mayor.CitizenId]
		candidates["c" .. c.Id] = { Key = "c" .. c.Id, Name = c.Name, Kind = "citizen", CitizenId = c.Id, Stances = state.Mayor.Stances or citizenCandidate(c, rng).Stances }
	end
	local wanted = if state.Mayor and state.Mayor.Kind == "citizen" then 1 else 2
	for _ = 1, 30 do
		if wanted <= 0 then
			break
		end
		local c = adults[rng:NextInteger(1, #adults)]
		if not candidates["c" .. c.Id] and (c.Personality == "chatty" or c.Personality == "curious" or c.Personality == "cheerful" or c.Personality == "funny" or c.Job == "City Clerk" or c.Job == "Community Organizer" or rng:NextNumber() < 0.2) then
			candidates["c" .. c.Id] = citizenCandidate(c, rng)
			wanted -= 1
		end
	end
end

function CityService.Candidates()
	local list = {}
	for _, cand in pairs(candidates) do
		local stances = {}
		for _, id in ipairs(cand.Stances or {}) do
			local s = stanceById[id]
			if s then
				table.insert(stances, { Id = id, Label = s.label, Pitch = s.pitch })
			end
		end
		table.insert(list, { Key = cand.Key, Name = cand.Name, Kind = cand.Kind, UserId = cand.UserId, CitizenId = cand.CitizenId, Stances = stances })
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- how much citizen c likes a candidate
local function support(c, cand, rng)
	local score = 0
	for _, id in ipairs(cand.Stances or {}) do
		score += CityService.Appeal(c, id) * 18
	end
	if cand.Kind == "player" then
		score += CityService.Opinion(c, cand.UserId) * 0.55
	else
		local other = S.Life.Citizens[cand.CitizenId]
		if other then
			if other.Id == c.Id then
				score += 100
			elseif other.Household == c.Household then
				score += 40
			elseif table.find(c.Friends or {}, other.Id) then
				score += 18
			end
		end
		if state.Mayor and state.Mayor.CitizenId == cand.CitizenId then
			score += (state.Happiness - 50) * 0.3 -- incumbents ride the city's mood
		end
	end
	return score + rng:NextNumber(0, 10)
end

local function runElection()
	-- the same ballot players have been looking at (only fill it if it's empty)
	local any = false
	for _, cand in pairs(candidates) do
		if cand.Kind == "citizen" then
			any = true
		end
	end
	if not any then
		refreshCitizenCandidates()
	end
	local list = {}
	for _, cand in pairs(candidates) do
		cand.Votes = 0
		table.insert(list, cand)
	end
	if #list == 0 then
		return
	end
	local rng = Random.new()
	for _, c in ipairs(S.Life.List) do
		if S.Life:Age(c) >= (Config.ADULT_AGE or 18) then
			local best, bestScore = nil, -math.huge
			for _, cand in ipairs(list) do
				local sc = support(c, cand, rng)
				if sc > bestScore then
					best, bestScore = cand, sc
				end
			end
			if best then
				best.Votes += 1
			end
		end
	end
	for player, choice in pairs(votes) do
		if candidates[choice] and player.Parent then
			candidates[choice].Votes += 1
		end
	end
	table.sort(list, function(a, b)
		return a.Votes > b.Votes
	end)
	local winner = list[1]
	local previous = state.Mayor
	state.Mayor = { Name = winner.Name, Kind = winner.Kind, UserId = winner.UserId, CitizenId = winner.CitizenId, Stances = winner.Stances, Since = state.Day }
	local results = {}
	for _, cand in ipairs(list) do
		table.insert(results, { Name = cand.Name, Votes = cand.Votes, Kind = cand.Kind, UserId = cand.UserId })
	end
	CityService.Fire("Election", winner.Name, results)
	CityService.Broadcast({ Type = "Election", Winner = winner.Name, WinnerKind = winner.Kind, WinnerUserId = winner.UserId, Results = results, Reelected = previous and previous.Name == winner.Name })
	CityService.News("🗳️ " .. winner.Name .. (if previous and previous.Name == winner.Name then " was re-elected mayor" else " is the new mayor") .. " with " .. winner.Votes .. " votes!", "Election")
	for _, player in ipairs(Players:GetPlayers()) do
		local isMayor = winner.Kind == "player" and winner.UserId == player.UserId
		player:SetAttribute("Title", if isMayor then "Mayor" else "Citizen")
		if isMayor and playerData[player] then
			playerData[player].Terms += 1
			CityService.AddCoins(player, 100, "🏛️ Mayor's salary")
		end
	end
	-- a citizen mayor passes their first idea right away
	if winner.Kind == "citizen" and winner.Stances and winner.Stances[1] then
		CityService.PassPolicy(winner.Stances[1], winner.Name)
	end
	-- a fresh race: players must give a new speech to run again
	votes = {}
	for k, cand in pairs(candidates) do
		if cand.Kind == "player" then
			candidates[k] = nil
		end
	end
	refreshCitizenCandidates()
end

handlers.Vote = function(player, data)
	if type(data.Candidate) ~= "string" or not candidates[data.Candidate] then
		return { Ok = false, Error = "That person isn't running." }
	end
	votes[player] = data.Candidate
	CityService.Progress(player, "vote", 1)
	return { Ok = true, Text = "You voted for " .. candidates[data.Candidate].Name .. "! Results at the next election." }
end

--------------------------------------------------------------------------------
-- Policies (the mayor's decisions)
--------------------------------------------------------------------------------
function CityService.PassPolicy(stanceId, byName)
	local stance = stanceById[stanceId]
	if not stance then
		return false
	end
	for stat, amount in pairs(stance.city or {}) do
		local name = string.upper(string.sub(stat, 1, 1)) .. string.sub(stat, 2)
		CityService.Adjust(name, amount)
	end
	table.insert(state.Policies, 1, { Id = stanceId, Label = stance.label, Day = state.Day, By = byName })
	CityService.Fire("Policy", stanceId, byName)
	while #state.Policies > 6 do
		table.remove(state.Policies)
	end
	-- citizens feel it
	for _, c in ipairs(S.Life.List) do
		CityService.Boost(c, CityService.Appeal(c, stanceId) * 10)
	end
	CityService.News("🏛️ Mayor " .. byName .. " passed a new policy: " .. stance.label .. "!", "Policy")
	return true
end

handlers.Policy = function(player, data)
	local pd = playerData[player]
	if not (state.Mayor and state.Mayor.Kind == "player" and state.Mayor.UserId == player.UserId) then
		return { Ok = false, Error = "Only the mayor can pass policies. Win an election first!" }
	end
	if pd.LastPolicyDay == state.Day then
		return { Ok = false, Error = "You already passed a policy today. Try again tomorrow." }
	end
	if not stanceById[data.Stance] then
		return { Ok = false, Error = "Unknown policy." }
	end
	pd.LastPolicyDay = state.Day
	CityService.PassPolicy(data.Stance, player.DisplayName)
	return { Ok = true, Text = "Policy passed: " .. stanceById[data.Stance].label }
end

handlers.CityInfo = function(player)
	return {
		Ok = true,
		News = state.News,
		Candidates = CityService.Candidates(),
		Policies = state.Policies,
		Mayor = state.Mayor,
		MyVote = votes[player],
		ElectionIn = math.max(0, nextElection - os.clock()),
		IsMayor = state.Mayor and state.Mayor.UserId == player.UserId or false,
		CanPass = playerData[player] and playerData[player].LastPolicyDay ~= state.Day,
		Stances = Config.Stances,
		Me = playerData[player] and { Coins = playerData[player].Coins, Crimes = playerData[player].Crimes, Talks = playerData[player].Talks, Arrests = playerData[player].Arrests, Terms = playerData[player].Terms },
	}
end

--------------------------------------------------------------------------------
-- Daily goals: four little things to do each in-game day, for coins
--------------------------------------------------------------------------------
local GOALS = {
	{ Id = "talk", Text = "Chat with 3 citizens", Emoji = "💬", Need = 3, Reward = 20 },
	{ Id = "gift", Text = "Give someone a gift", Emoji = "🎁", Need = 1, Reward = 25 },
	{ Id = "laugh", Text = "Make someone laugh with a joke", Emoji = "😂", Need = 1, Reward = 20 },
	{ Id = "speech", Text = "Give a speech on the plaza", Emoji = "🎤", Need = 1, Reward = 30 },
	{ Id = "vote", Text = "Vote in the election", Emoji = "🗳️", Need = 1, Reward = 20 },
	{ Id = "tower", Text = "Ride an elevator to floor 8 or higher", Emoji = "🏢", Need = 1, Reward = 20 },
	{ Id = "directions", Text = "Ask someone for directions", Emoji = "🧭", Need = 1, Reward = 15 },
	{ Id = "friend", Text = "Make a friend (❤️❤️❤️ or more)", Emoji = "🤝", Need = 1, Reward = 40 },
	{ Id = "lake", Text = "Visit Mirror Lake", Emoji = "🎣", Need = 1, Reward = 20 },
	{ Id = "compliment", Text = "Compliment 2 people", Emoji = "😊", Need = 2, Reward = 20 },
	{ Id = "places", Text = "Visit 4 different places", Emoji = "🗺️", Need = 4, Reward = 30 },
	{ Id = "peace", Text = "Break up a street fight", Emoji = "🤝", Need = 1, Reward = 30 },
	{ Id = "thief", Text = "Catch a thief", Emoji = "🦸", Need = 1, Reward = 40 },
	{ Id = "train", Text = "Work out on a gym treadmill", Emoji = "💪", Need = 1, Reward = 25 },
	{ Id = "food", Text = "Buy something to eat", Emoji = "🍔", Need = 2, Reward = 15 },
}
local goalById = {}
for _, g in ipairs(GOALS) do
	goalById[g.Id] = g
end

-- Today's goals for a player: { { Id, Text, Emoji, Need, Have, Reward, Done } }
function CityService.Goals(player)
	local pd = playerData[player]
	if not pd then
		return {}
	end
	if not pd.Goals or pd.Goals.Day ~= state.Day then
		local rng = Random.new(state.Day * 7919 + player.UserId % 100000)
		local pool = table.clone(GOALS)
		local list = {}
		for _ = 1, 4 do
			local g = table.remove(pool, rng:NextInteger(1, #pool))
			table.insert(list, { Id = g.Id, Text = g.Text, Emoji = g.Emoji, Need = g.Need, Have = 0, Reward = g.Reward, Done = false })
		end
		pd.Goals = { Day = state.Day, List = list, Visited = {} }
	end
	return pd.Goals.List
end

-- Something happened that might count toward a goal
function CityService.Progress(player, id, amount)
	local list = CityService.Goals(player)
	for _, g in ipairs(list) do
		if g.Id == id and not g.Done then
			g.Have = math.min(g.Need, g.Have + (amount or 1))
			if g.Have >= g.Need then
				g.Done = true
				CityService.AddCoins(player, g.Reward, g.Emoji .. " Goal complete")
				CityService.Send(player, { Type = "Goals", Goals = list, Done = g })
			else
				CityService.Send(player, { Type = "Goals", Goals = list })
			end
		end
	end
end

handlers.Goals = function(player)
	return { Ok = true, Goals = CityService.Goals(player) }
end

-- where players are: visiting places and the lake
local function visitTick()
	for player, pd in pairs(playerData) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			CityService.Goals(player)
			for _, place in ipairs(S.Map.PlaceList) do
				if place.Door and (place.Door - root.Position).Magnitude < 22 and not pd.Goals.Visited[place.Id] then
					pd.Goals.Visited[place.Id] = true
					CityService.Progress(player, "places", 1)
					if place.Id == "Lake" then
						CityService.Progress(player, "lake", 1)
					end
				end
			end
			if S.Map.Lake and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(S.Map.Lake.X, 0, S.Map.Lake.Z)).Magnitude < 150 and not pd.Goals.Visited.Lake then
				pd.Goals.Visited.Lake = true
				CityService.Progress(player, "lake", 1)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The HUD's live numbers (ReplicatedStorage.CityState attributes)
--------------------------------------------------------------------------------
local function publish()
	local h = CityService.Hour()
	local cityState = CityService.CityState()
	local info = Config.CityStates and Config.CityStates[cityState] or {}
	stateFolder:SetAttribute("Hour", h)
	stateFolder:SetAttribute("Day", state.Day)
	stateFolder:SetAttribute("Weekday", weekday(state.Day))
	stateFolder:SetAttribute("Weekend", S.Life:IsWeekend(state.Day))
	stateFolder:SetAttribute("Economy", math.floor(state.Economy + 0.5))
	stateFolder:SetAttribute("Safety", math.floor(state.Safety + 0.5))
	stateFolder:SetAttribute("Happiness", math.floor(state.Happiness + 0.5))
	stateFolder:SetAttribute("State", cityState)
	stateFolder:SetAttribute("StateLabel", info.label or cityState)
	stateFolder:SetAttribute("StateEmoji", info.emoji or "🙂")
	stateFolder:SetAttribute("StateDesc", info.desc or "")
	if info.color then
		stateFolder:SetAttribute("StateColor", info.color)
	end
	stateFolder:SetAttribute("Mayor", state.Mayor and state.Mayor.Name or "Nobody yet")
	stateFolder:SetAttribute("MayorKind", state.Mayor and state.Mayor.Kind or "")
	stateFolder:SetAttribute("MayorUserId", state.Mayor and state.Mayor.UserId or 0)
	stateFolder:SetAttribute("ElectionIn", math.max(0, math.floor(nextElection - os.clock())))
	stateFolder:SetAttribute("Population", #S.Life.List)
	stateFolder:SetAttribute("CrimesToday", state.Crimes)
	local mood = 0
	for _, c in ipairs(S.Life.List) do
		mood += CityService.MoodOf(c)
	end
	stateFolder:SetAttribute("AverageMood", math.floor(mood / math.max(1, #S.Life.List)))
end

--------------------------------------------------------------------------------
-- Saving the city
--------------------------------------------------------------------------------
function CityService.Save()
	if not store or Config.SAVE_POPULATION == false then
		return
	end
	local minds = {}
	for _, c in ipairs(S.Life.List) do
		if (c.Memories and #c.Memories > 0) or c.Opinions then
			minds[tostring(c.Id)] = { m = c.Memories, o = c.Opinions }
		end
	end
	local data = {
		Life = S.Life:Serialize(),
		Minds = minds,
		City = { Economy = state.Economy, Safety = state.Safety, Happiness = state.Happiness, Day = state.Day, Mayor = state.Mayor, Policies = state.Policies },
	}
	local ok, err = pcall(function()
		store:SetAsync(SAVE_KEY, data)
	end)
	if not ok then
		warn("[CityService] Couldn't save the city: " .. tostring(err))
	end
end

-- Loads the saved city (call before the citizens spawn). Returns true if it loaded.
function CityService.Load()
	if Config.SAVE_POPULATION == false then
		return false
	end
	local ok = pcall(function()
		store = DataStoreService:GetDataStore(Config.DATASTORE_NAME or "AICity_v1")
		playerStore = store
	end)
	if not ok then
		store, playerStore = nil, nil
		return false
	end
	local okGet, data = pcall(function()
		return store:GetAsync(SAVE_KEY)
	end)
	if not okGet then
		-- Studio without API access: play without saving
		store, playerStore = nil, nil
		return false
	end
	if type(data) ~= "table" or not data.Life or not S.Life:Load(data.Life) then
		return false
	end
	for id, mind in pairs(data.Minds or {}) do
		local c = S.Life.Citizens[tonumber(id)]
		if c then
			c.Memories, c.Opinions = mind.m, mind.o
		end
	end
	local city = data.City or {}
	state.Economy = city.Economy or state.Economy
	state.Safety = city.Safety or state.Safety
	state.Happiness = city.Happiness or state.Happiness
	state.Day = city.Day or S.Life.Day
	state.Mayor = city.Mayor
	state.Policies = city.Policies or {}
	return true
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function CityService.Init(services)
	S = services
	makeRemotes()
	stateFolder = ReplicatedStorage:FindFirstChild("CityState") or Instance.new("Folder")
	stateFolder.Name = "CityState"
	stateFolder.Parent = ReplicatedStorage
	CityService.StateFolder = stateFolder
end

function CityService.Start()
	state.Day = math.max(state.Day, S.Life.Day)
	nextElection = os.clock() + (Config.ELECTION_INTERVAL or 480)
	refreshCitizenCandidates()
	if not state.Mayor then
		-- the city starts with a citizen mayor so there's always someone to beat
		for _, cand in pairs(candidates) do
			state.Mayor = { Name = cand.Name, Kind = "citizen", CitizenId = cand.CitizenId, Stances = cand.Stances, Since = state.Day }
			break
		end
	end
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		playerData[player] = nil
		votes[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
		CityService.Save()
	end)
	-- the slow loop: HUD numbers, coins, drift, elections, autosave
	task.spawn(function()
		local lastCoins, lastSave, lastHour = os.clock(), os.clock(), math.floor(CityService.Hour())
		local lastVisit = 0
		local warned = false
		while true do
			task.wait(1)
			local now = os.clock()
			publish()
			if now - lastVisit >= 3 then
				lastVisit = now
				pcall(visitTick)
			end
			if now - lastCoins >= 60 then
				lastCoins = now
				for player in pairs(playerData) do
					local bonus = if state.Mayor and state.Mayor.UserId == player.UserId then 10 else 0
					CityService.AddCoins(player, (Config.COIN_TICK or 10) + bonus, "💰 Paycheck")
				end
			end
			local hour = math.floor(CityService.Hour())
			if hour ~= lastHour then
				lastHour = hour
				hourlyDrift()
			end
			local left = nextElection - now
			if left <= 60 and not warned then
				warned = true
				CityService.Broadcast({ Type = "Toast", Icon = "🗳️", Title = "Election in 1 minute!", Text = "Open the vote panel (V) and pick the next mayor.", Color = Color3.fromRGB(90, 140, 240) })
			end
			if left <= 0 then
				warned = false
				nextElection = now + (Config.ELECTION_INTERVAL or 480)
				runElection()
			end
			if now - lastSave >= 180 then
				lastSave = now
				task.spawn(CityService.Save)
			end
		end
	end)
end

CityService.Handlers = handlers
return CityService
