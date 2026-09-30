-- BrawlService (ModuleScript) — ServerScriptService.Modules.BrawlService
-- Street fights between citizens. Every now and then two strangers on the
-- street get into it:
--   1. an argument ("Hey! You bumped into me!" / "Wanna go?!")
--   2. a fist fight: swings, blocks, health bars, getting knocked back
--   3. a crowd gathers: people cheer, film it on their phones, or yell for
--      someone to stop them, and somebody calls the police
--   4. it ends when someone is knocked out (off to the hospital), one of them
--      runs for it, they get tired, or the police break it up and take the
--      one who started it to the station
-- Players can watch, or hold E on a fighter to BREAK IT UP (coins, and the
-- people watching like you more). Hitting a fighter yourself is a crime like
-- any other, and they'll turn on you.
--
-- Grumpy and sporty people, and people in a bad mood, start fights more often.
-- More fights at night and when the city's Safety is low.
-- Config.STREET_FIGHTS = false turns them off; Config.FIGHT_COOLDOWN sets the
-- average seconds between fights near a player (default 140).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local BrawlService = {}
local S

local WATCH = 120 -- fights only start this close to a player (so someone sees them)
local CROWD = 34 -- people this close stop to watch
local MAX_TIME = 45 -- seconds before they get tired of it

local brawls = {} -- active fights
local inBrawl = {} -- [brain] = brawl (fighters, crowd and the officer)
local nextFight = 0
local grudges = {} -- ["a:b"] = true: they've fought before (and might again)

local REASONS = {
	{ "Hey! You bumped into me!", "So what? Watch where YOU'RE going!" },
	{ "What did you just say about me?!", "You heard me!" },
	{ "You spilled my coffee!", "Maybe don't stand in the middle of the sidewalk!" },
	{ "Stop staring at me!", "Oh, you want a problem?" },
	{ "You still owe me money!", "I don't owe you anything!" },
	{ "That was MY parking spot!", "Didn't see your name on it!" },
	{ "You cut in line!", "And what are you gonna do about it?" },
	{ "Your dog dug up my garden!", "Your garden was ugly anyway!" },
}
local REMATCH = { "YOU again?!", "Round two, huh?", "I told you to stay away from me!" }
local TAUNTS = { "Come on!", "Is that all you got?!", "Hyah!", "Take that!", "You asked for it!", "Ow! Why you...!" }
local CHEERS = { "Fight! Fight! Fight!", "Ooooh!", "Get 'em!", "Did you see that?!", "Whoa!!" }
local FILMING = { "I'm filming this!", "This is going online!", "Wait, let me get my phone!" }
local WORRIED = { "Someone stop them!", "Stop it, both of you!", "Somebody call the police!", "This is scary..." }
local OFFICER = { "Break it up! BREAK IT UP!", "Police! Hands where I can see them!", "That's enough, both of you!" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function isPolice(brain)
	local job = brain.C and brain.C.Job
	return job == "Police Officer" or job == "Night Officer" or job == "SWAT Officer"
end

local function streetNear(pos)
	local sp = S.Map.Spacing or 100
	return S.Map.StreetName and S.Map.StreetName(math.floor(pos.Z / sp + 0.5)) or "downtown"
end

local function key(a, b)
	return math.min(a.Id, b.Id) .. ":" .. math.max(a.Id, b.Id)
end

local function nearestPlayer(pos)
	local best, bestD = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = player, d
			end
		end
	end
	return best, bestD
end

local function center(b)
	return (b.A.Root.Position + b.B.Root.Position) / 2
end

local function busy(brain)
	return inBrawl[brain] ~= nil or brain.State == "ko" or brain.State == "hospital" or brain.State == "police" or brain.State == "talk" or brain.State == "chat" or brain.Held ~= nil or brain.Model:GetAttribute("Fighting") ~= nil or brain.Model:GetAttribute("Chasing") ~= nil
end

-- how likely someone is to start something
local function temper(brain)
	local base = ({ grumpy = 1, sporty = 0.6, funny = 0.25, chatty = 0.2, curious = 0.2, cheerful = 0.1, artsy = 0.15, bookish = 0.08, calm = 0.04, shy = 0.03 })[brain.C.Personality] or 0.15
	local mood = S.City.MoodOf(brain.C)
	if mood < 40 then
		base += 0.45
	elseif mood > 75 then
		base *= 0.5
	end
	return base
end

local function canFight(brain)
	if brain.Temp or busy(brain) or isPolice(brain) then
		return false
	end
	local age = S.Life:Age(brain.C)
	if age < (Config.ADULT_AGE or 18) or age > 72 then
		return false
	end
	-- out on the street (walking) or hanging around outdoors, not at work or school
	if brain.State == "walk" then
		return (brain.Floor or 1) == 1
	end
	if brain.State == "act" then
		local place = brain.Target and brain.Target.Place
		return place ~= nil and place.Outdoor == true and not (brain.Plan and (brain.Plan.Kind == "Work" or brain.Plan.Kind == "School"))
	end
	return false
end

-- the prompts on a fighter: hide their usual ones (talk, pickpocket) and add "Break it up"
local function setPrompts(b, brain, on)
	if on then
		b.Saved[brain] = {}
		for _, d in ipairs(brain.Model:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then
				b.Saved[brain][d] = true
				d.Enabled = false
			end
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BreakUpPrompt"
		prompt.ActionText = "Break it up"
		prompt.ObjectText = "👊 Street fight"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt:SetAttribute("Kind", "Stop")
		prompt.Parent = brain.Root
		prompt.Triggered:Connect(function(player)
			BrawlService.BreakUp(b, player)
		end)
	else
		local p = brain.Root and brain.Root:FindFirstChild("BreakUpPrompt")
		if p then
			p:Destroy()
		end
		for prompt in pairs(b.Saved[brain] or {}) do
			if prompt.Parent then
				prompt.Enabled = true
			end
		end
		b.Saved[brain] = nil
	end
end

local function release(b, brain)
	if inBrawl[brain] ~= b then
		return
	end
	inBrawl[brain] = nil
	if not brain.Model.Parent then
		return
	end
	if brain.Model:GetAttribute("Watching") then
		brain.Model:SetAttribute("Action", "")
	end
	brain.Model:SetAttribute("Brawling", nil)
	brain.Model:SetAttribute("Watching", nil)
	if b.Saved[brain] then
		setPrompts(b, brain, false)
	end
	if brain.C.Temp then
		S.Citizens.Despawn(brain)
	elseif brain.State == "police" and not brain.Model:GetAttribute("Fighting") and not brain.Model:GetAttribute("Chasing") then
		S.Citizens.Control(brain, false)
	end
end

local function sendNear(b, data)
	S.City.SendNear(center(b), 130, data)
end

--------------------------------------------------------------------------------
-- Ending a fight
--------------------------------------------------------------------------------
local function finish(b, outcome, info)
	if b.Done then
		return
	end
	b.Done = true
	b.Outcome = outcome
	local index = table.find(brawls, b)
	if index then
		table.remove(brawls, index)
	end
	local street = streetNear(center(b))
	local a, c = b.A, b.B
	local crowd = b.Crowd
	b.Crowd = {}
	for _, w in ipairs(crowd) do
		release(b, w)
	end
	if outcome == "ko" then
		local winner, loser = info.Winner, info.Loser
		S.City.News("👊 Street fight on " .. street .. ": " .. winner.C.Name .. " knocked out " .. loser.C.Name .. ".", "Crime")
		S.Citizens.Say(winner, ({ "And STAY down!", "Had enough?!", "Don't mess with me!" })[math.random(1, 3)], "angry", 2.5)
		winner.Model:SetAttribute("Won", os.clock()) -- a fist pump (see Poses)
		release(b, loser)
		task.delay(1.5, function()
			release(b, winner)
		end)
	elseif outcome == "fled" then
		local winner, loser = info.Winner, info.Loser
		S.City.News("👊 Street fight on " .. street .. ": " .. loser.C.Name .. " ran away from " .. winner.C.Name .. ".", "Crime")
		winner.Model:SetAttribute("Won", os.clock()) -- a fist pump (see Poses)
		release(b, loser)
		if loser.Model.Parent and loser.State ~= "ko" then
			S.Citizens.Flee(loser, winner.Root.Position, 10, "Okay, okay! I'm done!")
		end
		S.Citizens.Say(winner, "Yeah, you better run!", "angry", 2.5)
		release(b, winner)
	elseif outcome == "tired" then
		S.Citizens.Say(a, "Pff... you're not worth it.", "angry", 2.5)
		S.Citizens.Say(c, "Whatever. Get lost.", "angry", 2.5)
		release(b, a)
		release(b, c)
	elseif outcome == "police" then
		-- the one who started it (sometimes both of them) gets arrested
		local starter, other = b.A, b.B
		local officer = b.Officer
		local both = math.random() < 0.35
		for _, f in ipairs({ starter, other }) do
			inBrawl[f] = nil
			f.Model:SetAttribute("Brawling", nil)
			setPrompts(b, f, false)
		end
		if officer then
			inBrawl[officer] = nil
		end
		if both then
			S.Citizens.Say(officer or starter, "Both of you! You're coming with me!", "angry", 2.5)
		else
			S.Citizens.Control(other, false)
			S.Citizens.Say(other, "Finally...", "sad", 2)
			S.Citizens.Say(starter, "Hey! THEY started it!", "angry", 2.5)
		end
		if S.StreetCrime then
			S.StreetCrime.Arrest(officer, if both then { starter, other } else { starter }, "fighting in the street")
		else
			S.City.News("🚓 Police broke up a street fight on " .. street .. ".", "Crime")
			S.Citizens.Control(starter, false)
			if both then
				S.Citizens.Control(other, false)
			end
			if officer then
				if officer.C.Temp then
					S.Citizens.Despawn(officer)
				else
					S.Citizens.Control(officer, false)
				end
			end
		end
		return
	elseif outcome == "player" then
		local player = info.Player
		S.City.News("🤝 " .. player.DisplayName .. " broke up a street fight on " .. street .. ".", "City")
		S.City.Adjust("Safety", 1)
		S.Citizens.Say(a, "Fine! But this isn't over.", "angry", 2.5)
		S.Citizens.Say(c, "...Thanks. That guy's crazy.", "neutral", 2.5)
		S.City.Remember(c.C, player, "stopped a fight I was in", 12, "broke up a street fight")
		S.City.Remember(a.C, player, "got in the middle of my fight", -4)
		for _, w in ipairs(S.Citizens.Nearby(center(b), CROWD + 10)) do
			if w ~= a and w ~= c and not w.Temp then
				S.City.Remember(w.C, player, "broke up a street fight", 8, "broke up a street fight")
			end
		end
		release(b, a)
		release(b, c)
	elseif outcome == "interrupted" then
		-- someone else (a player) got involved: the other fighter backs off
		for _, f in ipairs({ a, c }) do
			if f ~= info.Brain then
				release(b, f)
				S.Citizens.Say(f, "Whoa! I'm out of here!", "scared", 2)
			else
				inBrawl[f] = nil
				f.Model:SetAttribute("Brawling", nil)
				setPrompts(b, f, false)
			end
		end
	end
	-- the officer on the way: never mind
	if b.Officer and inBrawl[b.Officer] == b then
		if outcome ~= "police" then
			S.Citizens.Say(b.Officer, "Aw, I missed it. Everyone move along!", "focused", 2)
		end
		release(b, b.Officer)
	end
end

function BrawlService.BreakUp(b, player)
	if b.Done or b.Phase == "argue" and os.clock() - b.Started < 1 then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - center(b)).Magnitude > 16 then
		return
	end
	if (player:GetAttribute("Wanted") or 0) > 0 then
		S.City.Toast(player, "🙄", "They won't listen to you", "Not while you're wanted by the police!", rgb(200, 90, 90))
		return
	end
	finish(b, "player", { Player = player })
	S.City.AddCoins(player, 20, "🤝 Broke up a fight")
	S.City.Toast(player, "🤝", "You broke up the fight!", "+20 coins. Everyone who saw it thinks a little better of you.", rgb(90, 180, 120))
	S.City.Progress(player, "peace", 1)
end

-- a player hit one of the fighters: that one turns on the player instead
function BrawlService.Interrupt(brain)
	local b = inBrawl[brain]
	if not b then
		return
	end
	if b.A == brain or b.B == brain then
		finish(b, "interrupted", { Brain = brain })
	elseif b.Officer == brain then
		b.Officer = nil
		inBrawl[brain] = nil
	else
		local i = table.find(b.Crowd, brain)
		if i then
			table.remove(b.Crowd, i)
		end
		inBrawl[brain] = nil
		brain.Model:SetAttribute("Watching", nil)
	end
end

function BrawlService.IsBrawling(brain)
	local b = inBrawl[brain]
	return b ~= nil and (b.A == brain or b.B == brain)
end

--------------------------------------------------------------------------------
-- Starting a fight
--------------------------------------------------------------------------------
-- start a fight between two citizens (a starts it)
function BrawlService.Fight(a, c)
	if busy(a) or busy(c) then
		return nil
	end
	local b = { A = a, B = c, Phase = "argue", Started = os.clock(), Crowd = {}, Saved = {}, Next = {}, Called = false, Id = os.clock() }
	table.insert(brawls, b)
	local rematch = grudges[key(a, c)]
	grudges[key(a, c)] = true
	for _, f in ipairs({ a, c }) do
		inBrawl[f] = b
		S.Citizens.Control(f, true)
		f.HP = f.HP or Weapons.CITIZEN_HP
		f.Model:SetAttribute("Brawling", (if f == a then c else a).C.First)
		f.Model:SetAttribute("Expression", "angry")
		f.Model:SetAttribute("Activity", "👊 In a street fight!")
		setPrompts(b, f, true)
	end
	local reason = REASONS[math.random(1, #REASONS)]
	S.Citizens.Say(a, if rematch then REMATCH[math.random(1, #REMATCH)] else reason[1], "angry", 2.6)
	task.delay(1.8, function()
		if not b.Done then
			S.Citizens.Say(c, if rematch then "You wanna go again?!" else reason[2], "angry", 2.4)
		end
	end)
	task.delay(3.8, function()
		if not b.Done then
			b.Phase = "fight"
			b.FightStart = os.clock()
			-- somebody calls the police after a few seconds (sometimes everyone's too busy filming)
			b.CallAt = if math.random() < 0.75 then os.clock() + math.random(50, 90) / 10 else nil
			S.Citizens.Say(a, "That's it!", "angry", 1.6)
		end
	end)
	-- players nearby hear about it
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - center(b)).Magnitude < 130 then
			S.City.Toast(player, "👊", "Street fight!", a.C.First .. " and " .. c.C.First .. " are fighting on " .. streetNear(center(b)) .. ". Hold E on one of them to break it up, or just watch.", rgb(255, 140, 60))
		end
	end
	sendNear(b, { Type = "Brawl", Position = center(b), Names = { a.C.First, c.C.First } })
	return b
end

local function pickFight()
	local now = os.clock()
	if now < nextFight or #brawls >= 2 then
		return
	end
	-- more fights at night and when the city feels unsafe
	local hour = S.City.Hour()
	local night = if hour >= 20 or hour < 3 then 1.8 elseif hour >= 6 and hour < 12 then 0.5 else 1
	local safety = S.City.State.Safety or 60
	local chance = 0.3 * night * math.clamp((110 - safety) / 60, 0.4, 1.8)
	if math.random() > chance then
		return
	end
	-- who's out on the street near a player?
	local pool = {}
	for _, brain in ipairs(S.Citizens.List) do
		if brain.Model.Parent and canFight(brain) then
			local _, d = nearestPlayer(brain.Root.Position)
			if d < WATCH then
				table.insert(pool, brain)
			end
		end
	end
	if #pool < 2 then
		return
	end
	-- two strangers close to each other (not family, not friends); the more
	-- hot-headed they are, the likelier it's them
	local pairs_, total = {}, 0
	for i = 1, #pool do
		local x = pool[i]
		for j = i + 1, #pool do
			local y = pool[j]
			if x.C.Household ~= y.C.Household and not table.find(x.C.Friends or {}, y.C.Id) and (x.Root.Position - y.Root.Position).Magnitude < 40 then
				local w = temper(x) + temper(y) + (if grudges[key(x, y)] then 1 else 0)
				table.insert(pairs_, { x, y, w })
				total += w
			end
		end
	end
	if #pairs_ == 0 then
		return
	end
	local roll = math.random() * total
	local chosen = pairs_[#pairs_]
	for _, pr in ipairs(pairs_) do
		roll -= pr[3]
		if roll <= 0 then
			chosen = pr
			break
		end
	end
	-- the hothead of the two starts it
	local starter, target = chosen[1], chosen[2]
	if temper(target) > temper(starter) then
		starter, target = target, starter
	end
	local every = Config.FIGHT_COOLDOWN or 140
	nextFight = now + every * (0.6 + math.random() * 0.8)
	BrawlService.Fight(starter, target)
end

--------------------------------------------------------------------------------
-- Each tick of a fight
--------------------------------------------------------------------------------
local function callPolice(b)
	b.Called = true
	local pos = center(b)
	local caller
	for _, w in ipairs(b.Crowd) do
		if w.Model.Parent then
			caller = w
			break
		end
	end
	if caller then
		S.Citizens.Say(caller, "Hello, police? There's a fight on " .. streetNear(pos) .. "!", "scared", 3)
	end
	-- an officer on duty, or a patrol car from nearby
	local officer, bestD = nil, 450
	for _, brain in ipairs(S.Citizens.List) do
		if isPolice(brain) and not brain.Temp and not busy(brain) and brain.Plan and brain.Plan.Kind == "Work" then
			local d = (brain.Root.Position - pos).Magnitude
			if d < bestD then
				officer, bestD = brain, d
			end
		end
	end
	if officer then
		S.Citizens.Control(officer, true)
		S.Citizens.Say(officer, "On my way!", "focused", 1.5)
	else
		local spot
		for _ = 1, 20 do
			local node = S.Map.Nodes[math.random(1, #S.Map.Nodes)]
			local d = (node - pos).Magnitude
			if d > 90 and d < 150 then
				spot = node
				break
			end
		end
		spot = spot or (pos + Vector3.new(70, 0, 0))
		officer = S.Citizens.SpawnExtra({ Name = "Officer Brooks", First = "Officer Brooks", Job = "Police Officer", Age = 34, Activity = "🚓 Responding to a fight" }, CFrame.new(spot + Vector3.new(0, 3, 0)))
		officer.HP = Weapons.POLICE_HP
		S.Citizens.Control(officer, true)
	end
	officer.Model:SetAttribute("Activity", "🚓 Responding to a fight")
	inBrawl[officer] = b
	b.Officer = officer
end

local function gatherCrowd(b)
	local pos = center(b)
	local now = os.clock()
	for _, w in ipairs(S.Citizens.Nearby(pos, 60)) do
		if w ~= b.A and w ~= b.B and not w.Temp and not inBrawl[w] and w.Model.Parent and w.Model:GetAttribute("Action") ~= "sleep" then
			local age = S.Life:Age(w.C)
			local dist = (w.Root.Position - pos).Magnitude
			local free = w.State == "act" and w.Target and w.Target.Place and w.Target.Place.Outdoor and not (w.Plan and (w.Plan.Kind == "Work" or w.Plan.Kind == "School"))
			-- people walking by (and people hanging around outside) come over and form a ring
			if (w.State == "walk" or (free and dist < 45)) and (w.Floor or 1) == 1 and #b.Crowd < 6 and not busy(w) and age >= 6 then
				inBrawl[w] = b
				table.insert(b.Crowd, w)
				S.Citizens.Control(w, true)
				w.Model:SetAttribute("Watching", true)
				local a = math.random() * math.pi * 2
				w.RingSpot = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(8, 11)
				w.NextLine = now + math.random(10, 40) / 10
				w.Mood = if age < 13 or w.C.Personality == "shy" or w.C.Personality == "calm" or w.C.Personality == "anxious" or w.C.Personality == "kind" then "worried" elseif age >= 13 and math.random() < 0.35 then "film" else "cheer"
				S.Citizens.SetGait(w, 12, "run")
				w.Humanoid:MoveTo(w.RingSpot)
			elseif dist < CROWD and S.Citizens.CanReact(w) and (w.WatchedUntil or 0) < now then
				-- people sitting or standing nearby turn and watch
				w.WatchedUntil = now + 6
				local r = math.random()
				if age < 13 or w.C.Personality == "shy" then
					S.Citizens.React(w, "scared", if r < 0.5 then WORRIED[math.random(1, #WORRIED)] else nil, "scared", 5, pos)
				elseif r < 0.4 then
					S.Citizens.React(w, "cheer", CHEERS[math.random(1, #CHEERS)], "surprised", 5, pos)
				else
					S.Citizens.React(w, nil, if r < 0.6 then WORRIED[math.random(1, #WORRIED)] else nil, "surprised", 5, pos)
				end
			end
		end
	end
	-- the ring: stand, face the fight, cheer / film / worry
	for _, w in ipairs(b.Crowd) do
		if w.Model.Parent and w.State == "police" and w.RingSpot then
			local d = flat(w.Root.Position - w.RingSpot).Magnitude
			if d > 2.5 then
				w.Humanoid:MoveTo(w.RingSpot)
			else
				w.Humanoid:MoveTo(w.Root.Position)
				S.Citizens.SetGait(w, 10, "idle")
				w.Root.CFrame = CFrame.lookAt(w.Root.Position, Vector3.new(pos.X, w.Root.Position.Y, pos.Z))
				w.Model:SetAttribute("Action", if w.Mood == "film" then "phone" elseif w.Mood == "cheer" then "cheer" else "scared")
				w.Model:SetAttribute("Activity", if w.Mood == "film" then "📱 Filming a fight" elseif w.Mood == "cheer" then "📣 Watching a fight" else "😟 Watching a fight")
				if now >= (w.NextLine or 0) then
					w.NextLine = now + math.random(40, 90) / 10
					local lines = if w.Mood == "film" then FILMING elseif w.Mood == "cheer" then CHEERS else WORRIED
					S.Citizens.Say(w, lines[math.random(1, #lines)], if w.Mood == "worried" then "scared" else "surprised", 2.2)
				end
			end
		end
	end
end

local function swing(b, f, other, now)
	f.Model:SetAttribute("SwingSide", (f.Model:GetAttribute("SwingSide") or 0) + 1)
	f.Model:SetAttribute("Swing", now)
	local strong = f.C.Personality == "sporty" or f.C.Job == "Fitness Coach" or f.C.Job == "Coach"
	local damage = math.random(8, 15) + (if strong then 4 else 0)
	local blocked = math.random() < 0.22
	if blocked then
		damage = math.floor(damage * 0.3 + 0.5)
		other.Model:SetAttribute("Block", now)
	end
	other.HP = (other.HP or Weapons.CITIZEN_HP) - damage
	other.LastHit = now
	f.LastHit = now
	other.Model:SetAttribute("MaxHP", Weapons.CITIZEN_HP)
	other.Model:SetAttribute("HP", math.max(0, other.HP))
	S.Citizens.Hurt(other, f.Root.Position, if math.random() < 0.3 then ({ "Ow!", "Oof!", "Argh!" })[math.random(1, 3)] else nil, if blocked then 6 else 16)
	if math.random() < 0.2 then
		S.Citizens.Say(f, TAUNTS[math.random(1, #TAUNTS)], "angry", 1.4)
	end
	sendNear(b, { Type = "Hit", Position = other.Root.Position + Vector3.new(0, 2, 0), Damage = damage, KO = other.HP <= 0, Blocked = blocked, Weapon = "Fists" })
	if other.HP <= 0 then
		other.HP = nil
		other.Model:SetAttribute("HP", nil)
		S.Citizens.KnockOut(other, f.C.First)
		finish(b, "ko", { Winner = f, Loser = other })
		return true
	end
	-- losing badly: they might run for it
	if other.HP < 35 and math.random() < 0.35 then
		finish(b, "fled", { Winner = f, Loser = other })
		return true
	end
	return false
end

local function tick(b, now)
	local a, c = b.A, b.B
	-- someone got knocked out or taken away by something else
	for _, f in ipairs({ a, c }) do
		if not f.Model.Parent or f.State == "ko" or f.State == "hospital" or inBrawl[f] ~= b then
			finish(b, "tired")
			return
		end
	end
	local _, playerD = nearestPlayer(center(b))
	if now - b.Started > MAX_TIME or playerD > 400 then
		finish(b, "tired")
		return
	end
	-- the two of them: square up, circle, swing
	for _, f in ipairs({ a, c }) do
		local other = if f == a then c else a
		local d = flat(other.Root.Position - f.Root.Position)
		local dist = d.Magnitude
		local dir = if dist > 0.1 then d.Unit else Vector3.new(1, 0, 0)
		if b.Phase == "argue" then
			S.Citizens.SetGait(f, 10, "walk")
			if dist > 4.5 then
				f.Humanoid:MoveTo(other.Root.Position - dir * 4)
			else
				f.Humanoid:MoveTo(f.Root.Position)
			end
		else
			b.Next[f] = b.Next[f] or (now + math.random(2, 8) / 10)
			local side = f.Root.CFrame.RightVector * (if math.floor(now / 1.7 + f.Id) % 2 == 0 then 1 else -1)
			S.Citizens.SetGait(f, if dist > 5 then 14 else 7, "run")
			if dist > 4 then
				f.Humanoid:MoveTo(other.Root.Position - dir * 3.2)
			else
				f.Humanoid:MoveTo(f.Root.Position + flat(side) * 2 - dir * 0.5)
			end
			if dist < 5.2 and now >= b.Next[f] then
				b.Next[f] = now + math.random(8, 14) / 10
				if swing(b, f, other, now) then
					return
				end
			end
		end
	end
	gatherCrowd(b)
	-- someone calls the police
	if not b.Called and b.Phase == "fight" and b.CallAt and now >= b.CallAt then
		callPolice(b)
	end
	local officer = b.Officer
	if officer and officer.Model.Parent and inBrawl[officer] == b then
		local pos = center(b)
		S.Citizens.SetGait(officer, 16, "run")
		officer.Humanoid:MoveTo(pos)
		if (officer.Root.Position - pos).Magnitude < 8 then
			S.Citizens.Say(officer, OFFICER[math.random(1, #OFFICER)], "angry", 2.5)
			finish(b, "police")
		end
	end
end

function BrawlService.Active()
	return brawls
end

function BrawlService.Start(services)
	S = services
	nextFight = os.clock() + (Config.FIGHT_COOLDOWN or 140) * 0.4
	task.spawn(function()
		local lastPick = 0
		while true do
			task.wait(0.3)
			local now = os.clock()
			for _, b in ipairs(table.clone(brawls)) do
				if not b.Done then
					tick(b, now)
				end
			end
			if Config.STREET_FIGHTS ~= false and now - lastPick > 5 then
				lastPick = now
				pickFight()
			end
		end
	end)
end

return BrawlService
