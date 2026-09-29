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

local CrimeService = {}
local S

local PUNCH_DAMAGE = 34
local PUNCH_RANGE = 6
local PUNCH_COOLDOWN = 0.5
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

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function isPolice(brain)
	local job = brain.C and brain.C.Job
	return job == "Police Officer" or job == "Night Officer"
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
local function canSee(brain, target, ignore)
	local head = brain.Model:FindFirstChild("Head")
	if not head then
		return false
	end
	local from = head.Position
	local d = target - from
	if d.Magnitude <= HEAR then
		return true
	end
	if d.Magnitude > SIGHT then
		return false
	end
	-- people see what's roughly in front of them (not behind)
	local look = brain.Root.CFrame.LookVector
	if look:Dot(d.Unit) < -0.35 and brain.State ~= "walk" then
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
end

function CrimeService.AddStars(player, n, reason)
	local w = wanted[player]
	local stars = (w and w.Stars or 0) + n
	setStars(player, stars)
	if reason then
		S.City.Toast(player, "🚨", "Wanted! " .. string.rep("⭐", math.min(stars, MAX_STARS)), reason, Color3.fromRGB(230, 60, 60))
	end
end

-- a crime happened: witnesses react, remember and report it
local function report(player, position, victim, severity, what, gossip, stars)
	local seen = witnesses(position, victim)
	local reported = false
	for _, brain in ipairs(seen) do
		if isPolice(brain) and brain.State ~= "police" and not brain.C.Temp then
			reported = true
			S.Citizens.Say(brain, COP_LINES[math.random(1, #COP_LINES)], "angry", 2)
		elseif not brain.C.Temp then
			reported = true
			S.City.Remember(brain.C, player, "saw them " .. what, -10 - severity * 8, gossip)
			S.City.Boost(brain.C, -12)
			if S.Life:Age(brain.C) < 13 or brain.C.Personality == "shy" or brain.C.Personality == "calm" or math.random() < 0.6 then
				S.Citizens.Flee(brain, position, math.random(7, 11), if math.random() < 0.6 then HELP_LINES[math.random(1, #HELP_LINES)] else nil)
			else
				S.Citizens.React(brain, "boo", ({ "Hey! I saw that!", "I'm calling the police!", "What is WRONG with you?!", "Somebody stop them!" })[math.random(1, 4)], "angry", 3, position)
			end
		end
	end
	if victim and victim.State ~= "ko" and not victim.C.Temp then
		reported = true
	end
	S.City.Crime(severity)
	local pd = S.City.Data(player)
	if pd then
		pd.Crimes += 1
	end
	if reported then
		CrimeService.AddStars(player, stars, #seen .. (if #seen == 1 then " person saw" else " people saw") .. " you " .. what .. "!")
	else
		S.City.Toast(player, "🤫", "Nobody saw that...", "But the city feels a little less safe.", Color3.fromRGB(120, 120, 140))
	end
	return #seen
end

--------------------------------------------------------------------------------
-- Punching
--------------------------------------------------------------------------------
local function punch(player, data)
	local root, character = rootOf(player)
	if not root or jailed[player] or hiding[player] then
		return { Ok = false }
	end
	local now = os.clock()
	if (lastPunch[player] or 0) + PUNCH_COOLDOWN > now then
		return { Ok = false }
	end
	lastPunch[player] = now
	-- who's in front of us?
	local best, bestScore = nil, math.huge
	local look = root.CFrame.LookVector
	for _, brain in ipairs(S.Citizens.Nearby(root.Position, PUNCH_RANGE + 2)) do
		local d = brain.Root.Position - root.Position
		local flatD = Vector3.new(d.X, 0, d.Z)
		if flatD.Magnitude <= PUNCH_RANGE and (flatD.Magnitude < 2 or look:Dot(flatD.Unit) > 0.2) then
			local score = flatD.Magnitude - look:Dot(flatD.Unit) * 2
			if data.Target == brain.Model then
				score -= 5
			end
			if score < bestScore then
				best, bestScore = brain, score
			end
		end
	end
	if not best then
		return { Ok = true, Hit = false }
	end
	local brain = best
	if not canBeHurt(brain) then
		if brain.State ~= "ko" and brain.State ~= "hospital" then
			S.City.Toast(player, "🚫", "Not a chance", "You can't hurt kids.", Color3.fromRGB(200, 90, 90))
		end
		return { Ok = true, Hit = false }
	end
	brain.HP = (brain.HP or (if brain.C.Temp or isPolice(brain) then 150 else 100)) - PUNCH_DAMAGE
	brain.LastHit = now
	local c = brain.C
	S.City.SendNear(brain.Root.Position, 120, { Type = "Hit", Position = brain.Root.Position + Vector3.new(0, 2, 0), Damage = PUNCH_DAMAGE, KO = brain.HP <= 0 })
	if brain.HP <= 0 then
		brain.HP = nil
		local name = c.Name
		S.Citizens.KnockOut(brain, player.DisplayName)
		if not c.Temp then
			S.City.Remember(c, player, "knocked me out!", -60, "knocked out " .. c.First)
			S.City.News("💫 " .. name .. " was knocked out on " .. streetNear(brain.Root.Position) .. "! Paramedics took them to the hospital.", "Crime")
		end
		report(player, brain.Root.Position, brain, 3, "knock out " .. c.First, "knocked out " .. c.First .. " in the street", if isPolice(brain) then 3 else 2)
		return { Ok = true, Hit = true, KO = true, Name = c.First }
	end
	-- a hit: flinch, then fight back or run
	local line = VICTIM_LINES[math.random(1, #VICTIM_LINES)]
	if not c.Temp then
		S.City.Remember(c, player, "punched me", -22, "punched " .. c.First)
	end
	S.Citizens.Hurt(brain, root.Position, line)
	local brave = isPolice(brain) or c.Temp or c.Personality == "grumpy" or c.Personality == "sporty"
	if brave then
		-- shove back
		root.AssemblyLinearVelocity = (root.Position - brain.Root.Position).Unit * 40 + Vector3.new(0, 15, 0)
		S.Citizens.React(brain, "boo", FIGHT_LINES[math.random(1, #FIGHT_LINES)], "angry", 2, root.Position)
		if isPolice(brain) or c.Temp then
			CrimeService.AddStars(player, 1, "You attacked a police officer!")
		end
	else
		task.delay(0.4, function()
			S.Citizens.Flee(brain, root.Position, 9, HELP_LINES[math.random(1, #HELP_LINES)])
		end)
	end
	if (brain.Hits or 0) == 0 or now - (brain.ReportedAt or 0) > 6 then
		brain.ReportedAt = now
		report(player, brain.Root.Position, brain, 1, "attack " .. c.First, "attacked " .. c.First .. " in broad daylight", 1)
	end
	brain.Hits = (brain.Hits or 0) + 1
	return { Ok = true, Hit = true, Name = c.First, HP = brain.HP }
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
	S.City.Send(player, { Type = "Busted", Seconds = seconds, Fine = fine, Stars = stars })
	S.City.News("🚔 " .. player.DisplayName .. " was arrested and thrown in jail!", "Crime")
	S.City.Adjust("Safety", 2 + stars)
end

local function spawnBackup(player, root)
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
	local name = officerNames[math.random(1, #officerNames)]
	local brain = S.Citizens.SpawnExtra({ Name = name, First = name, Job = "Police Officer", Age = math.random(25, 50), Activity = "🚓 Chasing a suspect" }, CFrame.new(best + Vector3.new(0, 3, 0)))
	S.Citizens.Control(brain, true)
	return brain
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
		local want = math.min(w.Stars, 4)
		if #w.Chasers < want then
			for _, brain in ipairs(S.Citizens.List) do
				if #w.Chasers >= want then
					break
				end
				if isPolice(brain) and not brain.C.Temp and brain.State ~= "police" and brain.State ~= "ko" and brain.State ~= "hospital" and brain.Plan and brain.Plan.Kind == "Work" and (brain.Root.Position - root.Position).Magnitude < 320 then
					S.Citizens.Control(brain, true)
					brain.Searching, brain.SearchPoint = nil, nil
					brain.Model:SetAttribute("Chasing", player.UserId)
					S.Citizens.Say(brain, "On my way!", "angry", 1.5)
					table.insert(w.Chasers, brain)
				end
			end
			if #w.Chasers < want and (w.Stars >= 2 or #w.Chasers == 0) and (w.NextBackup or 0) < os.clock() then
				w.NextBackup = os.clock() + 6
				local b = spawnBackup(player, root)
				b.Model:SetAttribute("Chasing", player.UserId)
				table.insert(w.Chasers, b)
			end
		end
		-- where are they? The police only know what someone has SEEN.
		local h = hiding[player]
		local seen = false
		if not h then
			for _, brain in ipairs(w.Chasers) do
				if (brain.Root.Position - root.Position).Magnitude < 95 and canSee(brain, root.Position) then
					seen = true
					break
				end
			end
			-- citizens who spot you call it in
			if not seen then
				for _, brain in ipairs(S.Citizens.Nearby(root.Position, 40)) do
					if not brain.C.Temp and brain.State ~= "ko" and brain.State ~= "police" and canSee(brain, root.Position) and math.random() < 0.06 then
						seen = true
						S.Citizens.Say(brain, "Officer! They went that way!", "scared", 2)
						break
					end
				end
			end
		end
		local now = os.clock()
		if seen then
			w.LastSeen = now
			w.LastKnown = root.Position
			w.SawHide = false
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
				S.Citizens.SetGait(brain, 18 + w.Stars * 0.8, "run")
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
					S.Citizens.SetGait(brain, 17, "run")
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
								if (spot.Position - w.LastKnown).Magnitude < 35 then
									table.insert(spots, spot)
								end
							end
							if #spots > 0 then
								target = spots[math.random(1, #spots)].Position
							end
						end
						if not target then
							local a = math.random() * math.pi * 2
							local r = math.random(8, 30)
							target = w.LastKnown + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
						end
						brain.SearchPoint = target
						brain.SearchUntil = now + math.random(4, 7)
						if math.random() < 0.3 then
							S.Citizens.Say(brain, SEARCH_LINES[math.random(1, #SEARCH_LINES)], "focused", 1.8)
						end
					end
					S.Citizens.SetGait(brain, 10, "walk")
					brain.Humanoid:MoveTo(brain.SearchPoint)
				end
				-- checking a hiding spot up close
				if h and (brain.Root.Position - h.Spot.Position).Magnitude < 5.5 and math.random() < (if w.SawHide then 0.35 else 0.08) then
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
		local hideTime = (18 + w.Stars * 4) * (if hiding[player] and not w.SawHide then 0.6 else 1)
		if os.clock() - w.LastSeen > hideTime then
			w.LastSeen = os.clock() - hideTime + 8
			setStars(player, w.Stars - 1)
			if w.Stars == 0 then
				S.City.Toast(player, "😮‍💨", "You lost the police", "They gave up the search. Keep your head down for a while.", Color3.fromRGB(90, 180, 120))
				freeChasers(w)
				w.LastKnown, w.Mode, w.SawHide = nil, nil, nil
				player:SetAttribute("PoliceState", nil)
				player:SetAttribute("PoliceNear", nil)
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
	S.City.Handle("Punch", punch)
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
			if not ok then
				warn("[CrimeService] " .. tostring(err))
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
				end
			end
		end
	end)
end

function CrimeService.IsJailed(player)
	return jailed[player] ~= nil
end

return CrimeService
