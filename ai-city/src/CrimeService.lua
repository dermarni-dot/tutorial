-- CrimeService (ModuleScript) — ServerScriptService.Modules.CrimeService
-- Crime and punishment. Players can:
--   👊 punch people (F / the punch button). Three or four hits knock them out:
--      they fall down, see stars, and wake up later in a hospital bed.
--   🫳 pickpocket people (hold G next to them) for a few coins
--   💰 rob a store's register or the bank vault (hold the prompt)
-- If anyone SEES it (they need a clear line of sight, or to be right next to
-- you), they scream, run, remember it, gossip about it, and call the police:
-- you get wanted stars ⭐. Police officers on duty (and backup cars for 2+
-- stars) chase you. If they catch you: BUSTED, a fine and some time in the
-- police station's jail cell.
--
-- Getting away: the police only know where they LAST SAW you. Break their line
-- of sight (duck around a corner, into a building) and they run to that spot
-- and search around it. Hide in a trash can, a hedge or a park bush (press Q)
-- and they can't see you at all, unless they search right next to your
-- hiding spot. Stay hidden and the stars fade one by one.
-- Kids and babies can't be hurt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local CrimeService = {}
local S

local SIGHT = 70 -- how far witnesses can see
local HEAR = 14 -- anyone this close notices, line of sight or not
local MAX_STARS = 5

local wanted = {} -- [player] = { Stars, LastSeen, LastKnown, Chasers = { brain }, Progress, SawHide }
local hiding = {} -- [player] = { Spot, Saved = { [part] = transparency }, Since, From }
local jailed = {} -- [player] = { Until, Cell }
local lastPunch = {}
local robbed = {} -- [part] = time it can be robbed again
local officerNames = { "Officer Reyes", "Officer Park", "Officer Brooks", "Officer Novak", "Officer Mensah", "Officer Walsh", "Officer Chen", "Officer Duarte" }

local HELP_LINES = { "HELP!!", "Somebody help!", "Police! POLICE!", "Aaah!", "Call the cops!", "Run!!" }
local VICTIM_LINES = { "Ow!", "Hey!", "Ouch! What was that for?!", "Stop it!", "Ow! Are you crazy?!" }
local FIGHT_LINES = { "Back off!", "You want a piece of me?!", "Try that again!", "Big mistake!" }
local COP_LINES = { "Stop! Police!", "Freeze!", "You're under arrest!", "Don't make this hard!", "Get back here!" }
local SEARCH_LINES = { "Where'd they go?", "Check behind the bins!", "They can't have gone far...", "Spread out!", "I lost visual!", "Search the area!" }
local FOUND_LINES = { "Found you!", "Gotcha!", "Come on out of there!", "Nice try!" }

-- The more crime, the harder they come: what each wanted level sends after you.
--   Cops: how many chase you · Speed: how fast they run · Sight: how far they see
--   Check: chance per tick to check a hiding spot they're standing next to
--   Search: how wide they search · Fade: seconds out of sight to lose a star
--   Backup: seconds between backup units · Reach: how far on-duty cops respond from
local LEVELS = {
	{ Cops = 2, Speed = 17, Sight = 85, Check = 0.06, Search = 25, Fade = 22, Backup = 9, Reach = 320, Label = "🚓 A patrol is after you" },
	{ Cops = 3, Speed = 18.5, Sight = 95, Check = 0.08, Search = 30, Fade = 28, Backup = 7, Reach = 420, Label = "🚓🚓 Police units are after you" },
	{ Cops = 5, Speed = 20, Sight = 110, Check = 0.11, Search = 38, Fade = 36, Backup = 5, Reach = 900, Label = "🚨 Every cop in the city is after you" },
	{ Cops = 7, Speed = 21.5, Sight = 125, Check = 0.15, Search = 46, Fade = 46, Backup = 4, Reach = 900, Swat = 0.5, Label = "🛡️ SWAT is on the way" },
	{ Cops = 10, Speed = 23, Sight = 140, Check = 0.2, Search = 55, Fade = 58, Backup = 3, Reach = 900, Swat = 1, Heli = true, Label = "🚁 SWAT and a police helicopter" },
}
local function levelOf(w)
	return LEVELS[math.clamp(w.Stars, 1, #LEVELS)]
end
CrimeService.Levels = LEVELS

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function isPolice(brain)
	local job = brain.C and brain.C.Job
	return job == "Police Officer" or job == "Night Officer" or job == "SWAT Officer"
end

local function canBeHurt(brain)
	if brain.State == "ko" or brain.State == "hospital" then
		return false
	end
	if brain.C.Temp then
		return true
	end
	return S.Life:Age(brain.C) >= (Config.ADULT_AGE or 18)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- can this citizen see that spot? (walls block the view)
local function canSee(brain, target, ignore, range)
	local head = brain.Model:FindFirstChild("Head")
	if not head then
		return false
	end
	local from = head.Position
	local d = target - from
	if d.Magnitude > (range or SIGHT) then
		return false
	end
	-- people see what's roughly in front of them (not behind); anyone very
	-- close notices whichever way they face, but walls still block the view
	local look = brain.Root.CFrame.LookVector
	if d.Magnitude > HEAR and look:Dot(d.Unit) < -0.35 and brain.State ~= "walk" then
		return false
	end
	local filter = { workspace:FindFirstChild("Citizens") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	if ignore then
		table.insert(filter, ignore)
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(from, d, rayParams)
	return hit == nil or (hit.Position - target).Magnitude < 3
end

-- everyone who saw it happen (excluding the victim)
local function witnesses(position, victim)
	local out = {}
	for _, brain in ipairs(S.Citizens.Nearby(position, SIGHT)) do
		if brain ~= victim and brain.State ~= "ko" and brain.State ~= "hospital" and brain.Model:GetAttribute("Action") ~= "sleep" then
			if canSee(brain, position) then
				table.insert(out, brain)
			end
		end
	end
	return out
end

local function streetNear(pos)
	local sp = S.Map.Spacing or 100
	return S.Map.StreetName and S.Map.StreetName(math.floor(pos.Z / sp + 0.5)) or "downtown"
end

--------------------------------------------------------------------------------
-- Wanted level
--------------------------------------------------------------------------------
local function setStars(player, stars)
	local w = wanted[player]
	stars = math.clamp(stars, 0, MAX_STARS)
	if not w then
		w = { Stars = 0, LastSeen = os.clock(), Chasers = {}, Progress = 0 }
		wanted[player] = w
	end
	local before = w.Stars
	w.Stars = stars
	w.LastSeen = os.clock()
	player:SetAttribute("Wanted", stars)
	if stars > before then
		S.City.Send(player, { Type = "Wanted", Stars = stars, Up = true })
	elseif stars == 0 and before > 0 then
		S.City.Send(player, { Type = "Wanted", Stars = 0, Lost = true })
	end
	if stars == 0 then
		w.Look, w.LookText, w.Recognized = nil, nil, nil
		player:SetAttribute("PoliceLook", nil)
	end
end

function CrimeService.AddStars(player, n, reason)
	local w = wanted[player]
	local stars = (w and w.Stars or 0) + n
	setStars(player, stars)
	if reason then
		S.City.Toast(player, "🚨", "Wanted! " .. string.rep("⭐", math.min(stars, MAX_STARS)), reason, Color3.fromRGB(230, 60, 60))
	end
end

-- how hidden a player is by what they wear (hoodie, ski mask, disguise; better at night)
local function hiddenOf(player)
	return if S.Disguise then S.Disguise.Hidden(player) else 0
end

-- does anyone recognize the player? Hoodies, masks and disguises (and the
-- dark) make it harder. The closest witness matters most (up close it's
-- easier); every extra pair of eyes adds a little.
local function recognized(people, position, hidden)
	if #people == 0 then
		return false
	end
	if hidden <= 0 then
		return true
	end
	local nearest = math.huge
	for _, brain in ipairs(people) do
		local head = brain.Model:FindFirstChild("Head")
		nearest = math.min(nearest, if head then (head.Position - position).Magnitude else 30)
	end
	local best = 1 - hidden * (if nearest < 8 then 0.85 else 1)
	local chance = 1 - (1 - best) * 0.9 ^ (#people - 1)
	return math.random() < chance
end
CrimeService.Recognized = recognized

-- a crime happened: witnesses react, remember and report it
-- did the victim get a look at who did it? (a hit from behind, or while they
-- were asleep or knocked out, and they have no idea who it was)
local function victimSaw(victim, player)
	if not victim or victim.C.Temp or victim.State == "ko" or victim.Model:GetAttribute("Action") == "sleep" then
		return false
	end
	local root = rootOf(player)
	if not root then
		return false
	end
	local d = root.Position - victim.Root.Position
	local flatD = Vector3.new(d.X, 0, d.Z)
	if flatD.Magnitude > 0.1 and victim.Root.CFrame.LookVector:Dot(flatD.Unit) < 0.1 then
		return false -- you were behind them
	end
	return canSee(victim, root.Position + Vector3.new(0, 1.5, 0))
end

local function report(player, position, victim, severity, what, gossip, stars)
	local seen = witnesses(position, victim)
	local victimKnows = victimSaw(victim, player)
	local reported = false
	-- did anyone recognize who did it?
	local hidden = hiddenOf(player)
	local people = {}
	for _, brain in ipairs(seen) do
		if not brain.C.Temp then
			table.insert(people, brain)
		end
	end
	if victimKnows then
		table.insert(people, victim)
	end
	local known = recognized(people, position, hidden)
	local looks = S.Disguise and S.Disguise.Describe(player)
	for _, brain in ipairs(seen) do
		if isPolice(brain) and brain.State ~= "police" and not brain.C.Temp then
			reported = true
			S.Citizens.Say(brain, COP_LINES[math.random(1, #COP_LINES)], "angry", 2)
		elseif not brain.C.Temp then
			reported = true
			if known then
				S.City.Remember(brain.C, player, "saw them " .. what, -10 - severity * 8, gossip)
			end
			S.City.Boost(brain.C, -12)
			if S.Life:Age(brain.C) < 13 or brain.C.Personality == "shy" or brain.C.Personality == "calm" or math.random() < 0.6 then
				S.Citizens.Flee(brain, position, math.random(7, 11), if math.random() < 0.6 then HELP_LINES[math.random(1, #HELP_LINES)] else nil)
			else
				S.Citizens.React(brain, "boo", ({ "Hey! I saw that!", "I'm calling the police!", "What is WRONG with you?!", "Somebody stop them!" })[math.random(1, 4)], "angry", 3, position)
			end
		end
	end
	-- the victim calls the police only if they saw who it was
	if victimKnows then
		reported = true
	end
	S.City.Crime(severity)
	local pd = S.City.Data(player)
	if pd then
		pd.Crimes += 1
		-- notoriety: every crime makes the police remember your face a bit more
		-- (unless nobody could tell it was you)
		if known or not reported then
			pd.Notoriety = (pd.Notoriety or 0) + (if reported then severity else severity * 0.5)
			player:SetAttribute("Notoriety", math.floor(pd.Notoriety))
		end
	end
	if reported then
		local w = wanted[player]
		local extra, why = 0, nil
		if w and w.Stars > 0 and w.Mode == "chasing" then
			-- right in front of the police!
			extra, why = 1, "Right in front of the police! "
		elseif known and pd and pd.Notoriety >= 8 and (not w or w.Stars == 0) then
			extra, why = 1, "The police know your face. "
		end
		if w then
			w.Crimes = (w.Crimes or 0) + 1
		end
		local nSeen = #seen + (if victimKnows then 1 else 0)
		local count = nSeen .. (if nSeen == 1 then " person saw" else " people saw")
		if known then
			CrimeService.AddStars(player, stars + extra, (why or "") .. count .. " you " .. what .. "!")
		else
			-- nobody could tell who it was: fewer stars, and the police are looking for an outfit, not a face
			CrimeService.AddStars(player, math.max(1, stars - 1) + extra, (why or "") .. count .. " " .. (looks or "someone") .. ", but nobody recognized you!")
			S.City.Toast(player, "🥷", "Nobody knows it was you", "The police are looking for " .. (looks or "someone") .. ". Change or take it off (C) where nobody can see you.", Color3.fromRGB(150, 110, 220))
		end
		w = wanted[player]
		if w then
			w.Recognized = known or w.Recognized == true
			w.Look = if S.Disguise then S.Disguise.Signature(player) else ""
			w.LookText = looks
		end
	else
		S.City.Toast(player, "🤫", "Nobody saw that...", if victim and victim.State ~= "ko" then victim.C.First .. " didn't see who did it. No police this time." else "No witnesses, no police. But the city feels a little less safe.", Color3.fromRGB(120, 120, 140))
	end
	return #seen, reported
end

--------------------------------------------------------------------------------
-- Punching
--------------------------------------------------------------------------------
local function hpFor(brain)
	if brain.C.Job == "SWAT Officer" then
		return Weapons.SWAT_HP
	elseif brain.C.Temp or isPolice(brain) then
		return Weapons.POLICE_HP
	end
	return Weapons.CITIZEN_HP
end

-- Damage to a player (from a citizen fighting back, or another player)
local function hurtPlayer(fromPos, victim, damage, knock)
	local root, character = rootOf(victim)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or jailed[victim] then
		return false
	end
	if S.Combat and S.Combat.IsBlocking(victim) then
		damage *= Weapons.BLOCK
		knock = (knock or 10) * 0.3
	end
	humanoid:TakeDamage(damage)
	-- everyone sees the hit land (see Poses: the head snaps, they stagger back)
	character:SetAttribute("HitFrom", fromPos)
	character:SetAttribute("HitPower", knock or 10)
	character:SetAttribute("Hit", os.clock())
	local dir = Vector3.new(root.Position.X - fromPos.X, 0, root.Position.Z - fromPos.Z)
	if dir.Magnitude > 0.1 then
		root.AssemblyLinearVelocity = dir.Unit * (knock or 10) + Vector3.new(0, 6, 0)
	end
	S.City.SendNear(root.Position, 120, { Type = "Hit", Position = root.Position + Vector3.new(0, 2, 0), Damage = math.floor(damage + 0.5), Player = true, Blocked = S.Combat and S.Combat.IsBlocking(victim) })
	return humanoid.Health <= 0
end

--------------------------------------------------------------------------------
-- Citizens who fight back
--------------------------------------------------------------------------------
local fighters = {} -- [brain] = { Player, Until, Next }
local FIGHT_HITS = { "Take that!", "Had enough?!", "You asked for it!", "Come on then!", "Hyah!" }

local function stopFight(brain)
	fighters[brain] = nil
	if brain.Model.Parent then
		brain.Model:SetAttribute("Fighting", nil)
		if brain.State == "police" and not brain.Model:GetAttribute("Chasing") then
			S.Citizens.Control(brain, false)
		end
	end
end

local function startFight(brain, player)
	if brain.State == "ko" or brain.State == "hospital" or brain.Model:GetAttribute("Chasing") then
		return
	end
	local f = fighters[brain]
	if f then
		f.Until = os.clock() + 14
		return
	end
	S.Citizens.Control(brain, true)
	brain.Model:SetAttribute("Fighting", player.UserId)
	fighters[brain] = { Player = player, Until = os.clock() + 14, Next = os.clock() + 0.7 }
	S.Citizens.Say(brain, FIGHT_LINES[math.random(1, #FIGHT_LINES)], "angry", 2)
end

local function fightTick()
	local now = os.clock()
	for brain, f in pairs(fighters) do
		local player = f.Player
		local root, character = rootOf(player)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local d = root and (root.Position - brain.Root.Position).Magnitude or math.huge
		if not brain.Model.Parent or brain.State == "ko" or brain.State == "hospital" or not player.Parent or not humanoid or humanoid.Health <= 0 or jailed[player] or hiding[player] or now > f.Until or d > 60 then
			if brain.Model.Parent and humanoid and humanoid.Health <= 0 then
				S.Citizens.Say(brain, "And STAY down!", "angry", 2)
			end
			stopFight(brain)
		elseif brain.HP and brain.HP < 30 and not brain.C.Temp then
			-- losing: run for it
			stopFight(brain)
			S.Citizens.Flee(brain, root.Position, 10, "Okay, okay! I give up!")
		else
			S.Citizens.SetGait(brain, if d > 5 then 16 else 8, "run")
			brain.Humanoid:MoveTo(root.Position)
			if d < 4.8 and now >= f.Next then
				f.Next = now + math.random(9, 13) / 10
				brain.Model:SetAttribute("SwingSide", (brain.Model:GetAttribute("SwingSide") or 0) + 1)
				brain.Model:SetAttribute("Swing", now)
				local strong = brain.C.Personality == "sporty" or brain.C.Job == "Fitness Coach" or brain.C.Job == "Coach"
				hurtPlayer(brain.Root.Position, player, math.random(7, 11) + (if strong then 4 else 0), 18)
				if math.random() < 0.25 then
					S.Citizens.Say(brain, FIGHT_HITS[math.random(1, #FIGHT_HITS)], "angry", 1.4)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Attacking: fists or a weapon, at a citizen or another player
--------------------------------------------------------------------------------
local lastHitOn = {} -- ["attacker:victim"] = time the last hit was reported

local function attack(player, data)
	local root, character = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or jailed[player] or hiding[player] then
		return { Ok = false }
	end
	local id = if S.Combat then S.Combat.Equipped(player) else "Fists"
	local w = Weapons.Get(id)
	local now = os.clock()
	if (lastPunch[player] or 0) + w.Cooldown > now then
		return { Ok = false }
	end
	lastPunch[player] = now
	-- everyone sees the swing (left and right jabs take turns)
	character:SetAttribute("SwingSide", (character:GetAttribute("SwingSide") or 0) + 1)
	character:SetAttribute("SwingWeapon", id)
	character:SetAttribute("Swing", now)
	-- who's in front of us? (citizens and other players)
	local best, bestScore, bestPlayer = nil, math.huge, nil
	local look = root.CFrame.LookVector
	local function consider(pos, target, isPlayer)
		local d = pos - root.Position
		local flatD = Vector3.new(d.X, 0, d.Z)
		if flatD.Magnitude <= w.Range and math.abs(d.Y) < 6 and (flatD.Magnitude < 2 or look:Dot(flatD.Unit) > 0.2) then
			local score = flatD.Magnitude - look:Dot(flatD.Unit) * 2
			if score < bestScore then
				best, bestScore, bestPlayer = target, score, isPlayer
			end
		end
	end
	for _, brain in ipairs(S.Citizens.Nearby(root.Position, w.Range + 3)) do
		if brain.State ~= "ko" and brain.State ~= "hospital" then
			consider(brain.Root.Position, brain, false)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local oroot, och = rootOf(other)
		local ohum = och and och:FindFirstChildOfClass("Humanoid")
		if other ~= player and oroot and ohum and ohum.Health > 0 and not jailed[other] and not hiding[other] then
			consider(oroot.Position, other, true)
		end
	end
	if not best then
		return { Ok = true, Hit = false, Weapon = id }
	end

	-- another player
	if bestPlayer then
		local victim = best
		local vroot = rootOf(victim)
		local down = hurtPlayer(root.Position, victim, w.Damage * 0.6, w.Knock)
		S.City.Toast(victim, "⚠️", player.DisplayName .. " " .. w.Verb .. " you!", "Fight back (F), block (hold X) or run!", Color3.fromRGB(230, 60, 60))
		local key = player.UserId .. ":" .. victim.UserId
		if down then
			character:SetAttribute("Won", os.clock())
			S.City.News("💀 " .. victim.DisplayName .. " was " .. w.Down .. " by " .. player.DisplayName .. " on " .. streetNear(vroot.Position) .. "!", "Crime")
			report(player, vroot.Position, nil, w.Severity + 2, w.Down:gsub(" with a %w+$", "") .. " " .. victim.DisplayName, w.Down .. " " .. victim.DisplayName, w.Severity + 1)
		elseif now - (lastHitOn[key] or 0) > 6 then
			lastHitOn[key] = now
			report(player, vroot.Position, nil, w.Severity, "attack " .. victim.DisplayName, "attacked " .. victim.DisplayName, 1)
		end
		return { Ok = true, Hit = true, KO = down, Name = victim.DisplayName, Weapon = id }
	end

	-- a citizen
	local brain = best
	if not canBeHurt(brain) then
		S.City.Toast(player, "🚫", "Not a chance", "You can't hurt kids.", Color3.fromRGB(200, 90, 90))
		return { Ok = true, Hit = false, Weapon = id }
	end
	-- jumping into a street fight: this one turns on you
	if S.Brawl then
		S.Brawl.Interrupt(brain)
	end
	-- catching a thief isn't a crime: they give up
	if S.StreetCrime and S.StreetCrime.IsCriminal(brain) then
		return S.StreetCrime.PlayerHit(player, brain, w, id, root.Position)
	end
	brain.HP = (brain.HP or hpFor(brain)) - w.Damage
	brain.LastHit = now
	brain.Model:SetAttribute("MaxHP", hpFor(brain))
	brain.Model:SetAttribute("HP", math.max(0, brain.HP))
	local c = brain.C
	S.City.SendNear(brain.Root.Position, 120, { Type = "Hit", Position = brain.Root.Position + Vector3.new(0, 2, 0), Damage = w.Damage, KO = brain.HP <= 0, Weapon = id })
	if brain.HP <= 0 then
		brain.HP = nil
		brain.Model:SetAttribute("HP", nil)
		stopFight(brain)
		local name = c.Name
		S.Citizens.KnockOut(brain, player.DisplayName)
		task.delay(0.35, function()
			-- a fist pump once the punch lands (see Poses)
			if character.Parent then
				character:SetAttribute("Won", os.clock())
			end
		end)
		local downText = w.Down
		if not c.Temp then
			S.City.Remember(c, player, (if id == "Fists" then "knocked me out!" else w.Down .. " me!"), -40 - w.Severity * 15, w.Down .. " " .. c.First)
			S.City.News("💀 " .. name .. " was " .. downText .. " on " .. streetNear(brain.Root.Position) .. "! Paramedics rushed them to the hospital.", "Crime")
		end
		local pd = S.City.Data(player)
		if pd then
			pd.Notoriety = (pd.Notoriety or 0) + (w.Severity - 1) * 2 -- weapons make the police remember you faster
		end
		report(player, brain.Root.Position, brain, w.Severity + 2, (if id == "Fists" then "knock out " else "take down ") .. c.First, w.Down .. " " .. c.First .. " in the street", (if isPolice(brain) then 2 else 1) + (if w.Severity >= 3 then 1 else 0))
		return { Ok = true, Hit = true, KO = true, Name = c.First, Weapon = id }
	end
	-- a hit: flinch, then fight back or run
	local line = VICTIM_LINES[math.random(1, #VICTIM_LINES)]
	if not c.Temp then
		S.City.Remember(c, player, w.Verb .. " me", -15 - w.Severity * 8, w.Verb .. " " .. c.First)
	end
	S.Citizens.Hurt(brain, root.Position, line, w.Knock)
	local armed = w.Severity >= 3
	local brave = isPolice(brain) or c.Temp or ((c.Personality == "grumpy" or c.Personality == "sporty") and (not armed or math.random() < 0.3)) or (not armed and math.random() < 0.15)
	if isPolice(brain) or c.Temp then
		CrimeService.AddStars(player, 1, "You attacked a police officer!")
		if not brain.Model:GetAttribute("Chasing") then
			startFight(brain, player)
		end
	elseif brave then
		task.delay(0.3, function()
			startFight(brain, player)
		end)
	else
		task.delay(0.4, function()
			S.Citizens.Flee(brain, root.Position, 9, HELP_LINES[math.random(1, #HELP_LINES)])
		end)
	end
	-- (a hit nobody saw doesn't count: the next one might be seen)
	if now - (brain.ReportedAt or -99) > 6 then
		local _, reported = report(player, brain.Root.Position, brain, w.Severity, (if armed then "stab " else "attack ") .. c.First, w.Verb .. " " .. c.First .. " in broad daylight", if armed then 2 else 1)
		if reported then
			brain.ReportedAt = now
		end
	end
	brain.Hits = (brain.Hits or 0) + 1
	return { Ok = true, Hit = true, Name = c.First, HP = brain.HP, Weapon = id }
end

--------------------------------------------------------------------------------
-- Pickpocketing
--------------------------------------------------------------------------------
local function pickpocket(player, brain)
	local root = rootOf(player)
	if not root or jailed[player] or not brain or brain.State == "ko" or brain.State == "hospital" or brain.C.Temp then
		return
	end
	if (root.Position - brain.Root.Position).Magnitude > 8 then
		return
	end
	local c = brain.C
	if S.Life:Age(c) < (Config.ADULT_AGE or 18) then
		S.City.Toast(player, "🚫", "Not a chance", "You can't steal from kids.", Color3.fromRGB(200, 90, 90))
		return
	end
	if (brain.PickedAt or 0) > os.clock() - 120 then
		S.City.Toast(player, "🫳", "Empty pockets", c.First .. " has nothing left to steal.")
		return
	end
	brain.PickedAt = os.clock()
	-- did they notice? (easier to notice if they're facing you)
	local d = (root.Position - brain.Root.Position)
	local facing = brain.Root.CFrame.LookVector:Dot(Vector3.new(d.X, 0, d.Z).Unit)
	local notice = 0.25 + math.max(0, facing) * 0.45 + (if c.Personality == "curious" then 0.15 else 0) - (if brain.Model:GetAttribute("Action") == "sleep" then 0.4 else 0)
	local rich = c.Job == "Bank Manager" or c.Job == "Doctor" or c.Job == "Programmer"
	local amount = math.random(5, if rich then 40 else 20)
	S.City.AddCoins(player, amount, "🫳 Pickpocketed " .. c.First)
	if math.random() < notice then
		S.City.Remember(c, player, "stole from me!", -30, "picked " .. c.First .. "'s pocket")
		S.Citizens.React(brain, "boo", "HEY! THIEF! Give that back!", "angry", 2.5, root.Position)
		report(player, root.Position, brain, 1, "steal from " .. c.First, "picked " .. c.First .. "'s pocket", 1)
	else
		-- nobody noticed... unless someone else was watching
		local seen = 0
		for _, w in ipairs(witnesses(root.Position, brain)) do
			if math.random() < 0.35 then
				seen += 1
				S.City.Remember(w.C, player, "saw them pick " .. c.First .. "'s pocket", -18, "picked " .. c.First .. "'s pocket")
				S.Citizens.React(w, "boo", "I saw that! Thief!", "angry", 2.5, root.Position)
			end
		end
		S.City.Crime(0.5)
		if seen > 0 then
			CrimeService.AddStars(player, 1, "Someone saw you pickpocket " .. c.First .. "!")
		else
			S.City.Toast(player, "🤫", "Smooth.", c.First .. " didn't notice a thing. +" .. amount .. " coins")
		end
	end
end

--------------------------------------------------------------------------------
-- Robberies: store registers and the bank vault
--------------------------------------------------------------------------------
local function rob(player, part, isVault)
	local root = rootOf(player)
	if not root or jailed[player] or not part.Parent then
		return
	end
	if (robbed[part] or 0) > os.clock() then
		S.City.Toast(player, "💰", "Already cleaned out", "Come back later.")
		return
	end
	robbed[part] = os.clock() + (if isVault then 600 else 300)
	local placeId = part:GetAttribute("PlaceId") or "the store"
	local label = Config.PlaceById[placeId] and Config.PlaceById[placeId].label or placeId
	local amount = if isVault then math.random(150, 320) else math.random(35, 90)
	if S.Combat and Weapons.Get(S.Combat.Equipped(player)).FastRob then
		amount = math.floor(amount * 1.5) -- smashed open with the hammer
	end
	S.City.AddCoins(player, amount, "💰 Robbed the " .. label)
	S.City.News("🚨 The " .. label .. " was robbed" .. (if isVault then "! The vault is empty!" else "!"), "Crime")
	local seen = report(player, part.Position, nil, if isVault then 5 else 3, "rob the " .. label, "robbed the " .. label, if isVault then 3 else 2)
	if seen == 0 and isVault then
		CrimeService.AddStars(player, 2, "The bank's silent alarm went off!")
	end
	-- everyone inside panics
	for _, brain in ipairs(S.Citizens.Nearby(part.Position, 30)) do
		if brain.State ~= "ko" and not isPolice(brain) then
			S.Citizens.Flee(brain, part.Position, 10, if math.random() < 0.5 then "It's a robbery!!" else nil)
		end
	end
	S.City.SendNear(part.Position, 150, { Type = "Alarm", Position = part.Position, Seconds = 12 })
end

local function addRobPrompt(part, isVault)
	if part:FindFirstChild("RobPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RobPrompt"
	prompt.ActionText = if isVault then "Crack the vault" else "Rob the register"
	prompt.ObjectText = if isVault then "💰 Bank vault" else "🧾 Register"
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = if isVault then 6 else 3
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Crime")
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		rob(player, part, isVault)
	end)
end

--------------------------------------------------------------------------------
-- Hiding: trash cans, hedges and park bushes (CollectionService tag "HideSpot")
--------------------------------------------------------------------------------
local function setInvisible(character, on, saved)
	for _, d in ipairs(character:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			if on then
				saved[d] = d.Transparency
				d.Transparency = 1
			elseif saved[d] ~= nil then
				d.Transparency = saved[d]
			end
		end
	end
end

local function hidePrompt(spot)
	return spot:FindFirstChild("HidePrompt")
end

function CrimeService.Unhide(player, found)
	local h = hiding[player]
	if not h then
		return
	end
	hiding[player] = nil
	local root, character = rootOf(player)
	if character then
		setInvisible(character, false, h.Saved)
	end
	if root then
		-- step out on the side you climbed in from
		local out = Vector3.new(h.From.X - h.Spot.Position.X, 0, h.From.Z - h.Spot.Position.Z)
		out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, 1)
		root.Anchored = false
		root.CFrame = CFrame.new(h.Spot.Position + out * (h.Spot.Size.Magnitude / 2 + 2) + Vector3.new(0, 3, 0))
	end
	player:SetAttribute("Hiding", nil)
	local prompt = hidePrompt(h.Spot)
	if prompt then
		prompt.ActionText = "Hide"
	end
	if found then
		S.City.Toast(player, "👮", "Found you!", "The police checked your hiding spot. RUN!", Color3.fromRGB(230, 60, 60))
	end
end

function CrimeService.IsHiding(player)
	return hiding[player] ~= nil
end

local function hide(player, spot)
	if hiding[player] then
		if hiding[player].Spot == spot then
			CrimeService.Unhide(player)
		end
		return
	end
	local root, character = rootOf(player)
	if not root or jailed[player] or not spot.Parent then
		return
	end
	if (root.Position - spot.Position).Magnitude > 12 then
		return
	end
	for other, h in pairs(hiding) do
		if h.Spot == spot and other ~= player then
			S.City.Toast(player, "🙅", "Taken!", "Someone's already hiding in there.")
			return
		end
	end
	-- did a police officer see you climb in?
	local w = wanted[player]
	if w and w.Stars > 0 then
		w.SawHide = false
		for _, cop in ipairs(w.Chasers) do
			if (cop.Root.Position - root.Position).Magnitude < 70 and canSee(cop, root.Position) then
				w.SawHide = true
				w.LastKnown = spot.Position
			end
		end
	end
	local h = { Spot = spot, Saved = {}, Since = os.clock(), From = root.Position }
	hiding[player] = h
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(spot.Position + Vector3.new(0, 0.5, 0))
	setInvisible(character, true, h.Saved)
	local name = spot:GetAttribute("HideName") or "hiding"
	player:SetAttribute("Hiding", name)
	local prompt = hidePrompt(spot)
	if prompt then
		prompt.ActionText = "Get out"
	end
	if w and w.SawHide then
		S.City.Toast(player, "👀", "They saw you go in!", "The police know where you are. Maybe make a run for it...", Color3.fromRGB(230, 140, 40))
	else
		S.City.Toast(player, "🫥", "Hiding in " .. name, "The police can't see you here, unless they search right next to you. Press Q or Space to get out.", Color3.fromRGB(150, 110, 255))
	end
end

local function addHidePrompt(spot)
	if hidePrompt(spot) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HidePrompt"
	prompt.ActionText = "Hide"
	prompt.ObjectText = "🫥 " .. (spot:GetAttribute("HideName") or "Hiding spot")
	prompt.KeyboardKeyCode = Enum.KeyCode.Q
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Hide")
	prompt.Parent = spot
	prompt.Triggered:Connect(function(player)
		hide(player, spot)
	end)
end

--------------------------------------------------------------------------------
-- Police chases and arrests
--------------------------------------------------------------------------------
local function freeChasers(w)
	for _, brain in ipairs(w.Chasers) do
		if brain.Model.Parent then
			brain.Model:SetAttribute("Chasing", nil)
			brain.Model:SetAttribute("ChaseState", nil)
			if brain.C.Temp then
				S.Citizens.Despawn(brain)
			elseif brain.State == "police" then
				S.Citizens.Say(brain, "Lost them...", "focused", 2)
				S.Citizens.Control(brain, false)
			end
		end
	end
	w.Chasers = {}
	if w.Heli then
		w.Heli.Model:Destroy()
		w.Heli = nil
	end
end

local function arrest(player)
	CrimeService.Unhide(player)
	local w = wanted[player]
	local stars = w and w.Stars or 1
	if w then
		freeChasers(w)
	end
	setStars(player, 0)
	local pd = S.City.Data(player)
	local fine = math.min(S.City.Coins(player), 25 * stars)
	if fine > 0 then
		S.City.AddCoins(player, -fine, "🚔 Fine")
	end
	if pd then
		pd.Arrests += 1
	end
	local seconds = 18 + stars * 10
	local cell = S.Map.Jail or (S.Map.Places.PoliceStation and S.Map.Places.PoliceStation.Inside) or Vector3.new(0, 5, 0)
	jailed[player] = { Until = os.clock() + seconds, Cell = cell }
	player:SetAttribute("JailUntil", workspace:GetServerTimeNow() + seconds)
	local root = rootOf(player)
	if root then
		root.CFrame = CFrame.new(cell + Vector3.new(0, 3.5, 0))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if S.Combat then
		S.Combat.Confiscate(player)
	end
	if S.Disguise then
		S.Disguise.Confiscate(player)
	end
	S.City.Send(player, { Type = "Busted", Seconds = seconds, Fine = fine, Stars = stars })
	S.City.News("🚔 " .. player.DisplayName .. " was arrested and thrown in jail!", "Crime")
	S.City.Adjust("Safety", 2 + stars)
end

local swatNames = { "Carter", "Okafor", "Tanaka", "Silva", "Haddad", "Larsen", "Brooks", "Mensah" }
local function spawnBackup(player, root, swat)
	-- backup arrives from a sidewalk out of sight
	local best
	for _ = 1, 20 do
		local node = S.Map.Nodes[math.random(1, #S.Map.Nodes)]
		local d = (node - root.Position).Magnitude
		if d > 55 and d < 110 then
			best = node
			break
		end
	end
	best = best or (root.Position + Vector3.new(60, 0, 0))
	local name = if swat then "SWAT " .. swatNames[math.random(1, #swatNames)] else officerNames[math.random(1, #officerNames)]
	local brain = S.Citizens.SpawnExtra({ Name = name, First = name, Job = if swat then "SWAT Officer" else "Police Officer", Age = math.random(25, 45), Activity = if swat then "🛡️ SWAT: moving in" else "🚓 Chasing a suspect" }, CFrame.new(best + Vector3.new(0, 3, 0)))
	brain.HP = if swat then 250 else 150
	S.Citizens.Control(brain, true)
	return brain
end

--------------------------------------------------------------------------------
-- The police helicopter (5 stars): circles where you were last seen and
-- lights you up with its searchlight. It can't see you indoors or hidden.
--------------------------------------------------------------------------------
local function makeHelicopter(pos)
	local model = Instance.new("Model")
	model.Name = "PoliceHelicopter"
	local function piece(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("Offset", offset)
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(6, 5, 11), CFrame.new(), Color3.fromRGB(30, 40, 90))
	piece("Window", Vector3.new(5.6, 3, 3), CFrame.new(0, 0.6, -4.8), Color3.fromRGB(150, 200, 240), Enum.Material.Glass)
	piece("Stripe", Vector3.new(6.1, 1, 11.1), CFrame.new(0, -0.8, 0), Color3.fromRGB(240, 240, 240))
	piece("Tail", Vector3.new(1.4, 1.4, 11), CFrame.new(0, 0.8, 10), Color3.fromRGB(30, 40, 90))
	piece("TailFin", Vector3.new(0.4, 3, 2), CFrame.new(0, 2, 15), Color3.fromRGB(30, 40, 90))
	piece("Skid", Vector3.new(0.5, 0.5, 10), CFrame.new(-2.6, -3.4, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	piece("Skid", Vector3.new(0.5, 0.5, 10), CFrame.new(2.6, -3.4, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	piece("Rotor", Vector3.new(24, 0.3, 1.2), CFrame.new(0, 3, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	piece("Rotor2", Vector3.new(1.2, 0.3, 24), CFrame.new(0, 3, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	local lamp = piece("Searchlight", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, -3, -3), Color3.fromRGB(255, 250, 220), Enum.Material.Neon, Enum.PartType.Ball)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 40
	light.Range = 120
	light.Brightness = 6
	light.Color = Color3.fromRGB(255, 250, 230)
	light.Shadows = true
	light.Parent = lamp
	model.PrimaryPart = body
	model.Parent = workspace
	local heli = { Model = model, Pos = pos, Yaw = 0, Spin = 0 }
	return heli
end

local function moveHelicopter(heli, target, dt)
	local goal = Vector3.new(target.X, target.Y + 70, target.Z)
	local d = goal - heli.Pos
	local step = math.min(d.Magnitude, 34 * dt)
	if d.Magnitude > 0.1 then
		heli.Pos += d.Unit * step
		heli.Yaw = math.atan2(-d.X, -d.Z)
	end
	heli.Spin += dt * 25
	local base = CFrame.new(heli.Pos) * CFrame.Angles(0, heli.Yaw, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	for _, p in ipairs(heli.Model:GetChildren()) do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("Offset") or CFrame.new()
			if p.Name == "Rotor" or p.Name == "Rotor2" then
				p.CFrame = base * offset * CFrame.Angles(0, heli.Spin, 0)
			else
				p.CFrame = base * offset
			end
		end
	end
end

local indoorParams = RaycastParams.new()
indoorParams.FilterType = Enum.RaycastFilterType.Exclude
local function heliSees(heli, player, root)
	if hiding[player] then
		return false
	end
	local flat = Vector3.new(root.Position.X - heli.Pos.X, 0, root.Position.Z - heli.Pos.Z)
	if flat.Magnitude > 38 then
		return false
	end
	-- a roof over your head blocks the searchlight
	indoorParams.FilterDescendantsInstances = { player.Character, heli.Model, workspace:FindFirstChild("Citizens") }
	return workspace:Raycast(root.Position + Vector3.new(0, 3, 0), Vector3.new(0, 60, 0), indoorParams) == nil
end

local function chaseTick(dt)
	for player, w in pairs(wanted) do
		local root = rootOf(player)
		if not player.Parent then
			freeChasers(w)
			wanted[player] = nil
			continue
		end
		if w.Stars <= 0 or not root or jailed[player] then
			if #w.Chasers > 0 then
				freeChasers(w)
			end
			player:SetAttribute("PoliceState", nil)
			continue
		end
		-- clean up knocked-out chasers
		for k = #w.Chasers, 1, -1 do
			local b = w.Chasers[k]
			if not b.Model.Parent or b.State == "ko" or b.State == "hospital" then
				table.remove(w.Chasers, k)
			end
		end
		-- enough police on the case? (on-duty officers first, then backup)
		local level = levelOf(w)
		local want = level.Cops
		if #w.Chasers < want then
			for _, brain in ipairs(S.Citizens.List) do
				if #w.Chasers >= want then
					break
				end
				if isPolice(brain) and not brain.C.Temp and brain.State ~= "police" and brain.State ~= "ko" and brain.State ~= "hospital" and brain.Plan and brain.Plan.Kind == "Work" and (brain.Root.Position - root.Position).Magnitude < level.Reach then
					S.Citizens.Control(brain, true)
					brain.Searching, brain.SearchPoint = nil, nil
					brain.Model:SetAttribute("Chasing", player.UserId)
					S.Citizens.Say(brain, "On my way!", "angry", 1.5)
					table.insert(w.Chasers, brain)
				end
			end
			if #w.Chasers < want and (w.NextBackup or 0) < os.clock() then
				w.NextBackup = os.clock() + level.Backup
				local b = spawnBackup(player, root, level.Swat and math.random() < level.Swat)
				b.Model:SetAttribute("Chasing", player.UserId)
				table.insert(w.Chasers, b)
			end
		end
		-- where are they? The police only know what someone has SEEN.
		-- What you wear matters: a hoodie or a mask (especially at night) means
		-- they have to be closer to spot you. And if you changed your look where
		-- nobody could see, they're looking for the wrong outfit.
		local h = hiding[player]
		local seen = false
		local hidden = hiddenOf(player)
		local suspicious = if S.Disguise then S.Disguise.Suspicious(player) else 0
		local changed = w.Look ~= nil and S.Disguise ~= nil and S.Disguise.Signature(player) ~= w.Look
		local sight = level.Sight * (1 - hidden * 0.6)
		if changed then
			-- they only know you up close (a bit further if they know your face and it's showing)
			sight = math.min(sight, if w.Recognized and not S.Disguise.FaceCovered(player) then 30 else 16)
		end
		player:SetAttribute("PoliceLook", if changed then w.LookText or "someone else" else nil)
		if not h then
			for _, brain in ipairs(w.Chasers) do
				if (brain.Root.Position - root.Position).Magnitude < sight and canSee(brain, root.Position, nil, sight) then
					seen = true
					break
				end
			end
			-- citizens who spot you call it in (not if they don't know it's you)
			local tip = if changed and not w.Recognized then 0 else 0.06 * (1 - hidden) * (1 + suspicious)
			if not seen and tip > 0 then
				for _, brain in ipairs(S.Citizens.Nearby(root.Position, 40 * (1 - hidden * 0.5))) do
					if not brain.C.Temp and brain.State ~= "ko" and brain.State ~= "police" and canSee(brain, root.Position) and math.random() < tip then
						seen = true
						S.Citizens.Say(brain, "Officer! They went that way!", "scared", 2)
						break
					end
				end
			end
		end
		-- the helicopter
		if level.Heli then
			if not w.Heli then
				w.Heli = makeHelicopter(root.Position + Vector3.new(140, 70, 0))
				S.City.Toast(player, "🚁", "Police helicopter!", "Get indoors or hide. Its searchlight can spot you from the sky.", Color3.fromRGB(230, 60, 60))
			end
			local target = if seen then root.Position else (w.LastKnown or root.Position) + Vector3.new(math.cos(os.clock() * 0.6) * 30, 0, math.sin(os.clock() * 0.6) * 30)
			moveHelicopter(w.Heli, target, dt)
			if not seen and heliSees(w.Heli, player, root) then
				seen = true
			end
		elseif w.Heli then
			w.Heli.Model:Destroy()
			w.Heli = nil
		end
		local now = os.clock()
		if seen then
			w.LastSeen = now
			w.LastKnown = root.Position
			w.SawHide = false
			-- they can see what you're wearing now
			if S.Disguise then
				w.Look = S.Disguise.Signature(player)
				w.LookText = S.Disguise.Describe(player)
			end
		end
		w.LastKnown = w.LastKnown or root.Position
		local mode = if seen then "chasing" else "searching"
		if w.Mode ~= mode then
			w.Mode = mode
			if mode == "searching" and #w.Chasers > 0 then
				S.Citizens.Say(w.Chasers[1], SEARCH_LINES[math.random(1, #SEARCH_LINES)], "focused", 2)
			elseif mode == "chasing" and #w.Chasers > 0 then
				S.Citizens.Say(w.Chasers[1], "There they are!", "angry", 1.6)
			end
		end
		local close = false
		local nearest = math.huge
		for _, brain in ipairs(w.Chasers) do
			local d = (brain.Root.Position - root.Position).Magnitude
			nearest = math.min(nearest, d)
			brain.Model:SetAttribute("ChaseState", mode)
			if seen then
				S.Citizens.SetGait(brain, level.Speed, "run")
				brain.Humanoid:MoveTo(root.Position)
				if d < 5 then
					close = true
				end
				if math.random() < 0.02 then
					S.Citizens.Say(brain, COP_LINES[math.random(1, #COP_LINES)], "angry", 1.6)
				end
			else
				-- run to where they were last seen, then search around it
				local toLast = (brain.Root.Position - w.LastKnown).Magnitude
				if toLast > 7 and not brain.Searching then
					S.Citizens.SetGait(brain, level.Speed - 1, "run")
					brain.Humanoid:MoveTo(w.LastKnown)
				else
					brain.Searching = true
					if not brain.SearchPoint or (brain.Root.Position - brain.SearchPoint).Magnitude < 3 or now > (brain.SearchUntil or 0) then
						-- look somewhere new: around the last known spot (hiding spots first)
						local target
						if w.SawHide and h then
							target = h.Spot.Position
						elseif math.random() < 0.5 then
							local spots = {}
							for _, spot in ipairs(CollectionService:GetTagged("HideSpot")) do
								if (spot.Position - w.LastKnown).Magnitude < level.Search then
									table.insert(spots, spot)
								end
							end
							if #spots > 0 then
								target = spots[math.random(1, #spots)].Position
							end
						end
						if not target then
							local a = math.random() * math.pi * 2
							local r = math.random(8, level.Search)
							target = w.LastKnown + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
						end
						brain.SearchPoint = target
						brain.SearchUntil = now + math.random(4, 7)
						if math.random() < 0.3 then
							S.Citizens.Say(brain, SEARCH_LINES[math.random(1, #SEARCH_LINES)], "focused", 1.8)
						end
					end
					S.Citizens.SetGait(brain, 8 + w.Stars * 1.5, if w.Stars >= 3 then "run" else "walk")
					brain.Humanoid:MoveTo(brain.SearchPoint)
				end
				-- checking a hiding spot up close
				if h and (brain.Root.Position - h.Spot.Position).Magnitude < 5.5 and math.random() < (if w.SawHide then math.max(0.35, level.Check * 2) else level.Check) then
					S.Citizens.Say(brain, FOUND_LINES[math.random(1, #FOUND_LINES)], "angry", 1.8)
					CrimeService.Unhide(player, true)
					w.LastSeen = now
					w.LastKnown = root.Position
					h = nil
				end
			end
			if seen then
				brain.Searching = nil
				brain.SearchPoint = nil
			end
			-- stuck behind something? jump
			if brain.Humanoid.MoveDirection.Magnitude < 0.1 and d > 6 then
				brain.Humanoid.Jump = true
			end
		end
		player:SetAttribute("WantedSeen", seen)
		player:SetAttribute("PoliceState", mode)
		player:SetAttribute("PoliceLevel", level.Label)
		player:SetAttribute("PoliceCount", #w.Chasers)
		player:SetAttribute("Helicopter", w.Heli ~= nil)
		player:SetAttribute("PoliceNear", if nearest < math.huge then math.floor(nearest) else nil)
		if close and not hiding[player] then
			w.Progress += dt
			if w.Progress >= 1.1 then
				w.Progress = 0
				arrest(player)
				continue
			end
		else
			w.Progress = math.max(0, w.Progress - dt * 0.5)
		end
		-- out of sight long enough: the stars fade one by one
		-- (hiding makes them give up faster)
		local pd = S.City.Data(player)
		local known = if w.Recognized == false then 0 else math.min(20, (pd and pd.Notoriety or 0) * 1.2) -- the police remember repeat offenders
		local hideTime = (level.Fade + known) * (if hiding[player] and not w.SawHide then 0.6 else 1)
		-- a disguise helps them lose track; a new look helps a lot
		hideTime *= (1 - hidden * 0.35) * (if changed then 0.5 else 1)
		if os.clock() - w.LastSeen > hideTime then
			w.LastSeen = os.clock() - hideTime + 8
			setStars(player, w.Stars - 1)
			if w.Stars == 0 then
				S.City.Toast(player, "😮‍💨", "You lost the police", "They gave up the search. Keep your head down for a while.", Color3.fromRGB(90, 180, 120))
				freeChasers(w)
				w.LastKnown, w.Mode, w.SawHide = nil, nil, nil
				player:SetAttribute("PoliceState", nil)
				player:SetAttribute("PoliceNear", nil)
				player:SetAttribute("PoliceLevel", nil)
				player:SetAttribute("PoliceCount", nil)
				player:SetAttribute("Helicopter", nil)
			end
		end
	end
	-- jail: stay in your cell until your time is up
	for player, j in pairs(jailed) do
		local root = rootOf(player)
		if not player.Parent then
			jailed[player] = nil
		elseif os.clock() >= j.Until then
			jailed[player] = nil
			player:SetAttribute("JailUntil", nil)
			local station = S.Map.Places.PoliceStation
			if root and station then
				root.CFrame = CFrame.new(station.Door + Vector3.new(0, 3.5, 0))
			end
			S.City.Toast(player, "🔓", "You're free!", "Behave yourself out there.", Color3.fromRGB(90, 180, 120))
		elseif root and (root.Position - j.Cell).Magnitude > 9 then
			root.CFrame = CFrame.new(j.Cell + Vector3.new(0, 3.5, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
local function attach(model)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or root:FindFirstChild("PickpocketPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickpocketPrompt"
	prompt.ActionText = "Pickpocket"
	prompt.ObjectText = "🫳"
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Crime")
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		pickpocket(player, S.Citizens.BrainOf(model))
	end)
end

function CrimeService.Start(services)
	S = services
	S.City.Handle("Punch", attack)
	S.City.Handle("Attack", attack)
	S.City.Handle("Unhide", function(player)
		CrimeService.Unhide(player)
		return { Ok = true }
	end)
	for _, spot in ipairs(CollectionService:GetTagged("HideSpot")) do
		addHidePrompt(spot)
	end
	CollectionService:GetInstanceAddedSignal("HideSpot"):Connect(addHidePrompt)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			hiding[player] = nil
			player:SetAttribute("Hiding", nil)
		end)
	end)
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		task.spawn(attach, model)
	end
	CollectionService:GetInstanceAddedSignal("Citizen"):Connect(function(model)
		task.spawn(attach, model)
	end)
	-- registers in stores and the bank's vault can be robbed
	for _, d in ipairs(S.Map.Root:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Register" or d.Name == "VaultDoor") then
			local building = d:FindFirstAncestorWhichIsA("Model")
			while building and not building:GetAttribute("PlaceId") and building.Parent and building.Parent:IsA("Model") do
				building = building.Parent
			end
			local placeId = building and building:GetAttribute("PlaceId")
			if placeId and placeId ~= "Home" then
				d:SetAttribute("PlaceId", placeId)
				addRobPrompt(d, d.Name == "VaultDoor")
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local w = wanted[player]
		if w then
			freeChasers(w)
		end
		wanted[player] = nil
		jailed[player] = nil
		lastPunch[player] = nil
		if hiding[player] then
			local prompt = hidePrompt(hiding[player].Spot)
			if prompt then
				prompt.ActionText = "Hide"
			end
			hiding[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(0.2)
			local ok, err = pcall(chaseTick, dt)
			if ok then
				ok, err = pcall(fightTick)
			end
			if not ok then
				warn("[CrimeService] " .. tostring(err))
			end
		end
	end)
	-- notoriety cools off slowly while you stay out of trouble
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local pd = S.City.Data(player)
				local w = wanted[player]
				if pd and (pd.Notoriety or 0) > 0 and not (w and w.Stars > 0) then
					pd.Notoriety = math.max(0, pd.Notoriety - 0.25)
					player:SetAttribute("Notoriety", math.floor(pd.Notoriety))
				end
			end
		end
	end)
	-- punched people heal if left alone
	task.spawn(function()
		while true do
			task.wait(5)
			for _, brain in ipairs(S.Citizens.List) do
				if brain.HP and os.clock() - (brain.LastHit or 0) > 20 then
					brain.HP = nil
					brain.Hits = 0
					brain.Model:SetAttribute("HP", nil)
				end
			end
		end
	end)
end

-- Knocked out while wanted: the chase is over
function CrimeService.ClearWanted(player)
	CrimeService.Unhide(player)
	local w = wanted[player]
	if w and w.Stars > 0 then
		freeChasers(w)
		setStars(player, 0)
		w.LastKnown, w.Mode, w.SawHide = nil, nil, nil
	end
	for brain, f in pairs(fighters) do
		if f.Player == player then
			stopFight(brain)
		end
	end
	for _, attr in ipairs({ "PoliceState", "PoliceNear", "PoliceLevel", "PoliceCount", "Helicopter", "WantedSeen" }) do
		player:SetAttribute(attr, nil)
	end
end

function CrimeService.IsJailed(player)
	return jailed[player] ~= nil
end

return CrimeService
