-- SocialService (ModuleScript) — ServerScriptService.Modules.SocialService
-- Emotes, and people noticing what you do.
--
-- 💃 Emotes (press T, or the Emote app on your phone): wave, dance, cheer,
--    point, clap, laugh, salute, flex, shrug and sit down. Everyone sees them.
--    They stop when you walk off (a wave or a laugh stops by itself).
--
-- The people around you react, if they're free and they can see you:
--   👋 wave      the nearest person waves back (by name, if they know you)
--   💃 dance     people stop to watch and clap; a cheerful one joins in
--   🙌 cheer     a few cheer with you
--   😂 laugh     it's catching
--   🫡 salute    police officers salute back
--   💪 flex      sporty people flex back, others are impressed (or not)
--   👉 point     people look where you're pointing ("What? Where?")
-- And without being asked:
--   🐾 your pet: "Aww, what a cute puppy!", a GIANT one gets a "WHOA."
--   🚗 your car: "Nice ride!" (the sports car especially); driving too fast
--      past people gets you "SLOW DOWN!"
--   🌧️ (see RainService)

local Players = game:GetService("Players")

local SocialService = {}
local S

SocialService.EMOTES = {
	wave = { Emoji = "👋", Name = "Wave", Len = 2.5 },
	dance = { Emoji = "💃", Name = "Dance", Loop = true },
	cheer = { Emoji = "🙌", Name = "Cheer", Len = 3 },
	point = { Emoji = "👉", Name = "Point", Len = 3 },
	clap = { Emoji = "👏", Name = "Clap", Len = 3 },
	laugh = { Emoji = "😂", Name = "Laugh", Len = 3 },
	salute = { Emoji = "🫡", Name = "Salute", Len = 3 },
	flex = { Emoji = "💪", Name = "Flex", Loop = true },
	shrug = { Emoji = "🤷", Name = "Shrug", Len = 2.5 },
	sit = { Emoji = "🧘", Name = "Sit", Loop = true },
}
SocialService.ORDER = { "wave", "dance", "cheer", "point", "clap", "laugh", "salute", "flex", "shrug", "sit" }

local emoting = {} -- [player] = { Id, Start, Pos }
local cooldown = {} -- [player .. kind] = time
local PET_LINES = { "Aww, what a cute %s!", "Is that your %s? Adorable!", "Look at that little %s!", "Can I pet your %s?", "Hi, %s! Who's a good one?" }
local BIG_PET = { "WHOA. That's the biggest %s I've ever seen!", "Is that a %s or a horse?!", "Good grief, look at the size of that %s!" }
local TINY_PET = { "Oh my gosh, that %s is TINY!", "The tiniest %s! I can't!" }
local CAR_LINES = { "Nice ride!", "Ooh, I like your car!", "Sweet wheels!", "Is that yours? Nice!" }
local SPORTS_LINES = { "Whoa, a sports car!", "Now THAT is a car.", "Vroom vroom! Nice!" }
local SPEED_LINES = { "SLOW DOWN!", "Hey! Watch it!", "This isn't a race track!", "Are you crazy?!", "There are people walking here!" }

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function ready(player, kind, seconds)
	local key = player.UserId .. kind
	local now = os.clock()
	if now < (cooldown[key] or 0) then
		return false
	end
	cooldown[key] = now + seconds
	return true
end

-- people near a spot who could react (free, grown up enough, not asleep)
local function audience(pos, radius, max)
	local out = {}
	for _, brain in ipairs(S.Citizens.Nearby(pos, radius)) do
		local action = brain.Model:GetAttribute("Action") or ""
		if S.Citizens.CanReact(brain) and not brain.ReactToken and action ~= "sleep" and action ~= "nap" and action ~= "ride" and not brain.Model:GetAttribute("Fighting") then
			table.insert(out, brain)
		end
	end
	table.sort(out, function(a, b)
		return (a.Root.Position - pos).Magnitude < (b.Root.Position - pos).Magnitude
	end)
	while #out > (max or #out) do
		table.remove(out)
	end
	return out
end
SocialService.Audience = audience

local function react(brain, action, line, expression, seconds, lookAt)
	S.Citizens.Pause(brain, seconds)
	S.Citizens.React(brain, action, line, expression, seconds, lookAt)
end

local function knows(brain, player)
	if brain.C.Temp then
		return false
	end
	local ok, opinion = pcall(S.City.Opinion, brain.C, player)
	return ok and type(opinion) == "number" and opinion > 5
end

--------------------------------------------------------------------------------
-- Emotes
--------------------------------------------------------------------------------
local REACTIONS = {
	wave = function(player, pos, crowd)
		local b = crowd[1]
		if b then
			react(b, "wave", if knows(b, player) then "Hey, " .. player.DisplayName .. "! 👋" else ({ "Hi there!", "Hello!", "Hey! 👋" })[math.random(1, 3)], "happy", 3, pos)
		end
	end,
	dance = function(player, pos, crowd)
		for k, b in ipairs(crowd) do
			if k > 5 then
				break
			end
			local p = b.C.Personality
			if k == 1 and (p == "cheerful" or p == "chatty" or p == "funny" or p == "sporty") then
				react(b, "dance", ({ "Dance party!", "Ooh, I love this song!", "Dance-off!" })[math.random(1, 3)], "happy", 8, pos)
			elseif p == "grumpy" then
				react(b, "boo", "Ugh. Please stop.", "angry", 3, pos)
			else
				react(b, if k % 2 == 0 then "cheer" else "clap", if math.random() < 0.5 then ({ "Go, go, go!", "Nice moves!", "Woo!" })[math.random(1, 3)] else nil, "happy", 5, pos)
			end
		end
	end,
	cheer = function(player, pos, crowd)
		for k, b in ipairs(crowd) do
			if k <= 3 then
				react(b, "cheer", if k == 1 then "Yeah!" else nil, "happy", 3, pos)
			end
		end
	end,
	clap = function(player, pos, crowd)
		if crowd[1] then
			react(crowd[1], "wave", "Thank you, thank you!", "happy", 3, pos)
		end
	end,
	laugh = function(player, pos, crowd)
		for k, b in ipairs(crowd) do
			if k <= 3 and b.C.Personality ~= "grumpy" then
				react(b, "laugh", if k == 1 then "Hahaha! What's so funny?" else "Haha!", "happy", 3, pos)
			end
		end
	end,
	salute = function(player, pos, crowd)
		for _, b in ipairs(crowd) do
			local job = b.C.Job or ""
			if string.find(job, "Police") or string.find(job, "Officer") or string.find(job, "Guard") then
				react(b, "salute", "Citizen.", "focused", 3, pos)
				return
			end
		end
		if crowd[1] then
			react(crowd[1], "salute", "Uh... at ease?", "surprised", 3, pos)
		end
	end,
	flex = function(player, pos, crowd)
		local b = crowd[1]
		if b then
			if b.C.Personality == "sporty" then
				react(b, "flex", "Oh yeah? Check THESE out!", "happy", 4, pos)
			elseif b.C.Personality == "grumpy" then
				react(b, "boo", "Show-off.", "angry", 3, pos)
			else
				react(b, "clap", "Wow, look at those arms!", "surprised", 3, pos)
			end
		end
	end,
	point = function(player, pos, crowd, root)
		local at = pos + root.CFrame.LookVector * 30
		for k, b in ipairs(crowd) do
			if k <= 2 then
				react(b, "point", if k == 1 then "What? Where?" else nil, "surprised", 3, at)
			end
		end
	end,
	shrug = function(player, pos, crowd)
		if crowd[1] and math.random() < 0.6 then
			react(crowd[1], nil, "¯\\_(ツ)_/¯", "neutral", 2.5, pos)
		end
	end,
}

function SocialService.Emote(player, id)
	local e = SocialService.EMOTES[id or ""]
	local root = rootOf(player)
	local character = player.Character
	if not root or not character then
		return { Ok = false, Error = "Not now." }
	end
	if id == "stop" or not e then
		emoting[player] = nil
		character:SetAttribute("Emote", nil)
		return { Ok = true }
	end
	emoting[player] = { Id = id, Start = os.clock(), Pos = root.Position }
	character:SetAttribute("Emote", id)
	character:SetAttribute("EmoteAt", os.clock())
	-- the people around react
	if ready(player, "emote" .. id, 6) then
		local crowd = audience(root.Position, if id == "dance" then 30 else 22, 6)
		local fn = REACTIONS[id]
		if fn then
			pcall(fn, player, root.Position, crowd, root)
		end
	end
	return { Ok = true }
end

--------------------------------------------------------------------------------
-- Noticing your pet and your car
--------------------------------------------------------------------------------
local function petWord(player)
	local id = player:GetAttribute("Pet")
	local word = ({ Dog = "dog", Cat = "cat", Hamster = "hamster", Fox = "fox", Duck = "duck", Bunny = "bunny", Parrot = "parrot", GoldenPup = "golden pup" })[id or ""] or "pet"
	if player:GetAttribute("PetStage") == "Baby" then
		word = ({ dog = "puppy", cat = "kitten", ["golden pup"] = "golden puppy" })[word] or ("baby " .. word)
	end
	return word
end

local function notice()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root then
			-- a pet at your heels
			if player:GetAttribute("Pet") and ready(player, "pet", 18) then
				local crowd = audience(root.Position, 11, 1)
				local b = crowd[1]
				if b and b.C.Personality ~= "grumpy" and math.random() < 0.6 then
					local size = player:GetAttribute("PetSize") or 1
					local grown = player:GetAttribute("PetStage") == "Adult"
					local lines = if grown and size >= 1.5 then BIG_PET elseif grown and size <= 0.7 then TINY_PET else PET_LINES
					react(b, "point", string.format(lines[math.random(1, #lines)], petWord(player)), "happy", 3, root.Position)
				else
					cooldown[player.UserId .. "pet"] = os.clock() + 6
				end
			end
			-- your car: parked nearby (admired) or speeding past (shouted at)
			local car = S.Cars and S.Cars.Spawned and S.Cars.Spawned[player]
			local chassis = car and car.Parent and car.PrimaryPart
			if chassis then
				local v = chassis.AssemblyLinearVelocity or Vector3.zero
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				if speed > 42 and ready(player, "speeding", 6) then
					local crowd = audience(chassis.Position, 22, 2)
					for k, b in ipairs(crowd) do
						react(b, if k == 1 then "boo" else "scared", if k == 1 then SPEED_LINES[math.random(1, #SPEED_LINES)] else nil, if k == 1 then "angry" else "scared", 2.5, chassis.Position)
					end
				elseif speed < 2 and ready(player, "car", 25) then
					local crowd = audience(chassis.Position, 14, 1)
					local b = crowd[1]
					if b and math.random() < 0.5 then
						local lines = if car:GetAttribute("CarId") == "Sports" then SPORTS_LINES else CAR_LINES
						react(b, "point", lines[math.random(1, #lines)], "happy", 3, chassis.Position)
					end
				end
			end
		end
	end
end
SocialService.Notice = notice

function SocialService.Start(services)
	S = services
	S.City.Handle("Emote", function(player, data)
		return SocialService.Emote(player, data and data.Id)
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.3)
			tick += 1
			-- emotes stop when you walk off (or after a while, the short ones)
			for player, e in pairs(emoting) do
				local root = rootOf(player)
				local info = SocialService.EMOTES[e.Id]
				local moved = root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(e.Pos.X, 0, e.Pos.Z)).Magnitude > 2
				if not player.Parent or not root or moved or (info and not info.Loop and os.clock() - e.Start > info.Len) then
					emoting[player] = nil
					if player.Character then
						player.Character:SetAttribute("Emote", nil)
					end
				end
			end
			if tick % 7 == 0 and S.Citizens then
				pcall(notice)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		emoting[player] = nil
	end)
end

SocialService.Emoting = emoting

return SocialService
