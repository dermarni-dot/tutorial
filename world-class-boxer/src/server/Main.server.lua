-- Main server script for "Become a World Class Boxer"
-- Wires the career, training, fights, sparring, gym services and the client UI together.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Modules = script.Parent:WaitForChild("BoxerModules")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local Looks = require(Shared.Looks)
local Builder = require(Shared.Builder)
local DataManager = require(Modules.DataManager)
local World = require(Modules.World)
local Training = require(Modules.Training)
local Career = require(Modules.Career)
local FightEngine = require(Modules.FightEngine)
local MapBuilder = require(Modules.MapBuilder)
local Venues = require(Modules.Venues)
local Poser = require(Modules.Poser)
local Ambient = require(Modules.Ambient)
local CityMap = require(Modules.CityMap) -- same instance MapBuilder built the city with (travel targets, home interiors)

pcall(function()
	StarterPlayer.LoadCharacterAppearance = false
end)

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local Request = Instance.new("RemoteFunction")
Request.Name = "Request"
Request.Parent = remotes
local FightRemote = Instance.new("RemoteEvent")
FightRemote.Name = "Fight"
FightRemote.Parent = remotes
local ProfileRemote = Instance.new("RemoteEvent")
ProfileRemote.Name = "Profile"
ProfileRemote.Parent = remotes
local Notify = Instance.new("RemoteEvent")
Notify.Name = "Notify"
Notify.Parent = remotes
remotes.Parent = ReplicatedStorage

MapBuilder.BuildGym()
Venues.BuildTemplates()
task.spawn(Ambient.Start)

local V3 = Vector3.new
local rng = Random.new()

local busy = {} -- player -> "fight" | "spar" | "activity"
local sessions = {} -- player -> training session
local occupied = {} -- stationId -> player
local customizing = {} -- player -> "barber" | "locker"

local STATION = {}
for _, def in ipairs(MapBuilder.StationDefs) do
	STATION[def.id] = def
end
local PROP_FOR = { bench = "bench", deadlift = "deadlift", squat = "squat", curl = "curl", rope = "rope", row = "row", medball = "medball" }
-- shortest believable time for each minigame (anything faster is treated as a sloppy session)
local MIN_TIME = { combo = 9, rhythm = 9, reaction = 9, mitts = 9, shadow = 9, reps = 9, pace = 11, ladder = 7, rope = 9, hold = 5, medball = 9 }
local SPAR_SCALE = { Light = 0.7, Medium = 1.0, Hard = 1.35 }
local SPAR_RISK = { Light = 0, Medium = 0.01, Hard = 0.035 }
local SPAR_RANGE = { Light = { -12, -4 }, Medium = { -5, 3 }, Hard = { 0, 8 } }
local PREVIEW_BUILD = { chest = 8, shoulders = 8, arms = 8, back = 8, legs = 8, core = 8, neck = 8, fat = 14 }
-- the creator preview wears the real starter kit: worn gloves, old frayed wraps, sneakers, boil-and-bite guard
local PREVIEW_GEAR = { gloves = "Worn", glovesCond = 55, wraps = "OldWraps", wrapsCond = 50, shoes = "Sneakers", shoesCond = 60, mouthguard = "BoilBite" }

-- Creator "Peak" preview: what this frame / physique looks like fully trained (never saved)
local function peakBuild(app)
	local body = type(app) == "table" and type(app.body) == "table" and app.body or {}
	-- FindById(list, nil) would match the first entry without a name: default explicitly
	local frame = Config.FindById(Config.BodyTypes, type(body.frame) == "string" and body.frame or "Athletic") or Config.BodyTypes[2]
	local cap = 100 * ((frame and frame.potential) or 1)
	local ph = type(body.physique) == "string" and body.physique ~= "Auto" and Config.FindById(Config.Physiques, body.physique) or nil
	ph = ph or Config.FindById(Config.Physiques, "Balanced")
	local b = { fat = 10 }
	for _, g in ipairs(Config.MuscleKeys) do
		b[g] = 0.9 * cap * ((ph and ph.shape and ph.shape[g]) or 1)
	end
	Config.FillParts(b)
	-- the shape it was built from is the physique it is drawn as: left to classification, a fully
	-- trained Balanced build reads as a Power Puncher ("Auto" would preview a different body than "Balanced")
	return b, ph and ph.id or "Balanced"
end

-- gym facility tier 1..4 (CONTRACTS section 9: never saved, always derived)
local function gymTierOf(profile)
	local ok, idx = pcall(Catalog.GymTier, profile.gym and profile.gym.levels, profile.owned, profile.tier)
	return ok and tonumber(idx) or 1
end

local function flatDist(a, b)
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function stationModel(id)
	local gym = workspace:FindFirstChild("Gym")
	return gym and gym:FindFirstChild("Station_" .. id)
end

------------------------------------------------------------------------
-- Profile summary & pushes
------------------------------------------------------------------------
local function summary(player)
	local profile = DataManager.Get(player)
	if not profile then
		-- also while a failed DataStore read is being retried: the client waits on its loading state
		return { created = false, loading = true, loadRetry = DataManager.LoadPending(player) or nil }
	end
	local s = Career.Summary(profile, DataManager.CanSave(player))
	s.busy = busy[player]
	s.studio = RunService:IsStudio()
	-- R-ui: always a table (Settings.Supported() checks it); ui = the saved values, or nil before the first save
	s.settings = type(s.settings) == "table" and s.settings or {}
	if type(profile.settings) == "table" and type(profile.settings.ui) == "table" then
		s.settings.ui = profile.settings.ui
	end
	return s
end

-- fame on the Player (CONTRACTS section 7; CityVisuals / GymVisuals / venues read other players' values).
-- SetAttribute with an unchanged value fires nothing, so this is cheap on every push.
local FAME_ATTRS = { "Tier", "Fame", "Belts", "Nick", "GymTier" }
local function publishFame(player)
	local profile = DataManager.Get(player)
	if not (profile and profile.created) or profile.retired then
		for _, k in ipairs(FAME_ATTRS) do
			player:SetAttribute(k, nil)
		end
		return
	end
	player:SetAttribute("Tier", profile.tier)
	player:SetAttribute("Fame", math.floor(tonumber(profile.popularity) or 0))
	player:SetAttribute("Belts", table.concat(Career.PlayerBelts(profile), ","))
	player:SetAttribute("Nick", tostring(profile.identity and profile.identity.nickname or ""))
	player:SetAttribute("GymTier", gymTierOf(profile))
end

local function push(player)
	if player.Parent then
		ProfileRemote:FireClient(player, summary(player))
		local ok, err = pcall(publishFame, player)
		if not ok then
			warn("[Boxer] fame attributes:", err)
		end
	end
end

local function setBusy(player, what)
	busy[player] = what
	player:SetAttribute("Busy", what)
end

local function filter(text, userId, maxLen)
	text = tostring(text or ""):sub(1, maxLen or 20):gsub("^%s+", ""):gsub("%s+$", "")
	text = text:gsub("[%c]", "")
	if text == "" then
		return nil
	end
	local ok, res = pcall(function()
		local result = TextService:FilterStringAsync(text, userId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if ok and res and res ~= "" then
		return res
	end
	if not ok and RunService:IsStudio() then
		return text -- the filter service isn't reachable from an unpublished place
	end
	return nil
end

------------------------------------------------------------------------
-- Character look (serialized per player; previews use a temporary look)
------------------------------------------------------------------------
local lookState = {}
local function applyLook(player, previewApp, hands, popts)
	local st = lookState[player]
	if not st then
		st = { needFull = true } -- the first build of a character is always a full one
		lookState[player] = st
	end
	st.app = previewApp
	st.hands = hands
	st.popts = previewApp and popts or nil -- preview-only: growth / peak / head-only rebuild
	-- any queued request that needs the whole character wins over head-only previews
	if not (st.popts and st.popts.only) then
		st.needFull = true
	end
	if st.running then
		st.again = true
		return
	end
	st.running = true
	task.spawn(function()
		repeat
			st.again = false
			local profile = DataManager.Get(player)
			local char = player.Character
			local b = busy[player]
			if profile and char and char.Parent and b ~= "fight" and b ~= "spar" and (profile.created or st.app) then
				local app = st.app or profile.appearance
				local build = profile.created and profile.body or PREVIEW_BUILD
				local peakPhysique
				if st.app and st.popts and st.popts.peak then
					build, peakPhysique = peakBuild(app)
				end
				local gear = profile.created and Career.GearView(profile) or PREVIEW_GEAR
				local opts = profile.created and Career.LookOpts(profile, { hands = st.hands or "wraps", detail = "full" })
					or { hands = st.hands or "wraps", name = "", nick = "", waistText = "", detail = "full" }
				if st.app and st.popts then
					opts.previewGrowth = st.popts.growth
					opts.physique = peakPhysique or opts.physique
					if not st.needFull then
						opts.only = st.popts.only
					end
				end
				st.needFull = false
				local ok, err = pcall(Builder.Apply, char, app, build, gear, opts)
				if not ok then
					warn("[Boxer] look error:", err)
				end
				local s = sessions[player]
				if s and s.prop and char.Parent then
					Poser.AttachProps(char, s.prop, s.level)
				end
			end
		until not st.again
		st.running = false
	end)
end

local function gymSpawnCFrame()
	local spawn = workspace:FindFirstChild("Gym") and workspace.Gym:FindFirstChild("GymSpawn")
	local p = spawn and spawn.Position or V3(0, 1, 60)
	return CFrame.new(p + V3(rng:NextInteger(-4, 4), 4, rng:NextInteger(-4, 4)))
end

------------------------------------------------------------------------
-- Sweat & road grime (CONTRACTS section 7). Builder.SetSweat is the only writer of the Sweat
-- attribute (quantised to 0.05); the exact level is tracked here so slow build-up still adds up.
-- Training raises it, idling dries it, the shower (locker room), ice bath and a night's sleep wash it
-- off. Grime comes from roadwork and needs water to come off.
------------------------------------------------------------------------
local sweatState = {} -- player -> { char = Model, level = exact 0..1 }
local GRIME_WASH = { Swimming = true, IceBath = true } -- sessions in the water rinse the road dirt off
local SWEAT_RECOVERY = { Sauna = true } -- recovery sessions that still make you sweat (the weight-cut sauna)
local SWEAT_TICK = 2 -- seconds between build-up / drying steps
local SWEAT_GAIN = 0.15 / 60 -- per second of a session at fatigue 12 (CONTRACTS: about +0.15 a minute)
local SWEAT_TRAIN_CAP = 0.85 -- build-up stops here; the finished session's own sweat can still go higher
local SWEAT_DRY = 0.08 / 60 -- per second while idle

local function quantSweat(level)
	return math.floor(math.clamp(level, 0, 1) * 20 + 0.5) / 20
end

local function setSweat(player, char, level, force)
	local profile = DataManager.Get(player)
	if not (profile and profile.created and char and char.Parent) then
		return
	end
	level = math.clamp(tonumber(level) or 0, 0, 1)
	sweatState[player] = { char = char, level = level }
	local q = quantSweat(level)
	if not force and q == (tonumber(char:GetAttribute("Sweat")) or 0) then
		return
	end
	local ok, err = pcall(Builder.SetSweat, char, profile.appearance, q)
	if not ok then
		warn("[Boxer] sweat:", err)
	end
end

-- shower / ice bath / new day: clean skin; body grime is drawn by Cosmetics, so a grimy boxer is rebuilt
local function wash(player)
	local char = player.Character
	if not (char and char.Parent) then
		return
	end
	local grimy = (tonumber(char:GetAttribute("Grime")) or 0) > 0
	char:SetAttribute("Grime", nil)
	-- forced: Head.SetSweat also refreshes the face dirt (FaceGrime) from the attribute just cleared
	setSweat(player, char, 0, true)
	if grimy then
		applyLook(player)
	end
end

------------------------------------------------------------------------
-- Training sessions
------------------------------------------------------------------------
local function endSession(player, keepPosition)
	local s = sessions[player]
	sessions[player] = nil
	if busy[player] == "activity" then
		setBusy(player, nil)
	end
	if not s then
		return
	end
	if s.station and occupied[s.station] == player then
		occupied[s.station] = nil
		local m = stationModel(s.station)
		if m then
			m:SetAttribute("InUse", false)
		end
	end
	if s.station == "mitts" then
		Ambient.SetLoop("MittCoach", "mittidle")
	elseif s.station == "massage" then
		Ambient.SetLoop("Masseuse", "idle")
	end
	local char = player.Character
	if char then
		-- cleared before the early return so a kept-position end (e.g. handing over to sparring) leaves no stale station
		char:SetAttribute("Station", nil)
		if char:GetAttribute("Expr") == "effort" then
			char:SetAttribute("Expr", nil)
		end
	end
	if keepPosition or not (char and char.Parent) then
		return
	end
	CollectionService:RemoveTag(char, "Trainee")
	char:SetAttribute("Pose", nil)
	char:SetAttribute("PoseLevel", nil)
	Poser.ClearProps(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if s.use and root then
		local def = STATION[s.station]
		local p = s.use.Position + (def and def.exit or V3(0, 0, 3))
		Poser.Place(char, p.X, p.Z, s.yaw or 0, { floor = MapBuilder.FloorY })
		root.Anchored = false
	end
	if hum then
		hum.WalkSpeed = 16
		hum.AutoRotate = true
		hum.UseJumpPower = false
		hum.JumpHeight = 7.2
	end
end

local function trackCheckpoints()
	local gym = workspace:FindFirstChild("Gym")
	local folder = gym and gym:FindFirstChild("TrackCheckpoints")
	local list = {}
	if folder then
		for i = 2, 8 do
			local cp = folder:FindFirstChild("CP" .. i)
			if cp then
				table.insert(list, cp.Position)
			end
		end
		local first = folder:FindFirstChild("CP1")
		if first then
			table.insert(list, first.Position) -- finish back at the start arch
		end
	end
	return list
end

local function poolEnds()
	local gym = workspace:FindFirstChild("Gym")
	local ends = gym and gym:FindFirstChild("PoolEnds")
	local a = ends and ends:FindFirstChild("EndA")
	local b = ends and ends:FindFirstChild("EndB")
	return a and a.Position, b and b.Position
end

local function startActivity(player, profile, actId)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local act = Training.Activity(actId)
	if not act or act.id == "Sparring" then
		return { ok = false, err = "Unknown activity" }
	end
	local ok, err = Training.CanDo(profile, act)
	if not ok then
		return { ok = false, err = err }
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum and hum.Health > 0) then
		return { ok = false, err = "Your character isn't ready." }
	end
	local level = Training.StationLevel(profile, act.station)
	local s = { token = HttpService:GenerateGUID(false), act = act, start = os.clock(), kind = act.minigame, station = act.station, level = level }
	local def = STATION[act.station]
	if def then
		local m = stationModel(def.id)
		local use = m and m:FindFirstChild("UsePoint")
		if not use then
			return { ok = false, err = "Station missing" }
		end
		if flatDist(root.Position, use.Position) > 18 then
			return { ok = false, err = "Walk over to the " .. act.name .. " first (or press GO in the Training tab)." }
		end
		local holder = occupied[def.id]
		if holder and holder ~= player and holder.Parent and sessions[holder] then
			return { ok = false, err = "Someone is using the " .. act.name .. ". Try another station." }
		end
		occupied[def.id] = player
		m:SetAttribute("InUse", true)
		local _, yaw = use.CFrame:ToOrientation()
		s.use, s.yaw, s.pose = use, yaw, def.pose
		Poser.Place(char, use.Position.X, use.Position.Z, yaw, { floor = MapBuilder.FloorY, stand = def.stand, seat = def.seat, lie = def.lie })
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		hum.UseJumpPower = false
		hum.JumpHeight = 0
		char:SetAttribute("Pose", def.pose)
		char:SetAttribute("PoseLevel", level)
		char:SetAttribute("Station", def.id) -- other clients' GymVisuals react to this player's punches
		CollectionService:AddTag(char, "Trainee")
		s.prop = PROP_FOR[def.pose]
		if s.prop then
			Poser.AttachProps(char, s.prop, level)
		end
		if def.id == "mitts" then
			Ambient.SetLoop("MittCoach", "mitts")
		elseif def.id == "massage" then
			Ambient.SetLoop("Masseuse", "massage")
		end
	elseif act.minigame == "course" then
		local m = stationModel("track")
		local base = m and m:FindFirstChild("Base")
		if base and flatDist(root.Position, base.Position) > 30 then
			return { ok = false, err = "Head to the ROADWORK START arch outside the gym first." }
		end
		s.cps = trackCheckpoints()
		s.cp = 1
		hum.WalkSpeed = math.floor(18 + profile.stats.Stamina * 0.06)
	elseif act.minigame == "swim" then
		local m = stationModel("pool")
		local base = m and m:FindFirstChild("Base")
		if base and flatDist(root.Position, base.Position) > 30 then
			return { ok = false, err = "Head to the swimming pool first (north end of the gym)." }
		end
		s.lengths = 0
		s.target = 4
		local a, b = poolEnds()
		s.endA, s.endB = a, b
		if a and b then
			s.nextEnd = flatDist(root.Position, a) < flatDist(root.Position, b) and "B" or "A"
		end
		hum.WalkSpeed = math.floor(16 + profile.stats.Stamina * 0.04)
	end
	sessions[player] = s
	setBusy(player, "activity")
	if not act.recovery then
		char:SetAttribute("Expr", "effort") -- the Animator's face strains through the set (cleared in endSession)
	end
	return {
		ok = true, token = s.token, minigame = act.minigame, params = Training.MinigameParams(profile, act), level = level,
		pose = s.pose, act = act.id, energy = Training.EnergyCost(profile, act), cps = s.cps and #s.cps or nil, lengths = s.target,
	}
end

-- stats = the client's drill numbers (punches, max power, reps...): display / personal bests only
local function finishActivity(player, profile, token, score, stats)
	local s = sessions[player]
	if not s or s.token ~= token then
		return { ok = false, err = "No activity running." }
	end
	local act = s.act
	local elapsed = os.clock() - s.start
	local quality = tonumber(score) or 0.8
	if quality ~= quality then
		quality = 0.8
	end
	quality = math.clamp(quality, 0.4, 1.5)
	local tooFast = false
	local opts = {}
	if s.kind == "course" then
		local done = math.clamp((s.cp - 1) / math.max(1, #s.cps), 0, 1)
		if done < 0.25 then
			endSession(player)
			return { ok = false, err = "You barely left the start line - session cancelled." }
		end
		local par = 1260 / 20
		local pace = s.doneAt and (par / math.max(1, s.doneAt - s.start)) or 0.8
		quality = math.clamp(0.55 + pace * 0.55, 0.5, 1.4)
		opts.scale = done
		opts.energyScale = done
	elseif s.kind == "swim" then
		local done = math.clamp(s.lengths / s.target, 0, 1)
		if done < 0.25 then
			endSession(player)
			return { ok = false, err = "Swim at least one length - session cancelled." }
		end
		local par = s.target * 56 / 15
		local pace = s.doneAt and (par / math.max(1, s.doneAt - s.start)) or 0.8
		quality = math.clamp(0.55 + pace * 0.5, 0.5, 1.35)
		opts.scale = done
		opts.energyScale = done
	elseif elapsed < (MIN_TIME[s.kind] or 6) then
		quality = 0.4
		tooFast = true -- counts as a sloppy session, but never as a record
	end
	local result
	if act.recovery then
		result = Training.Recover(profile, act, quality)
	else
		result = Training.Perform(profile, act, quality, opts)
	end
	local record = Training.Record(profile, act.id, quality, Training.SanitizeStats(stats), tooFast)
	endSession(player)
	-- road grime / a rinse go on the model BEFORE the rebuild, which draws the shin & forearm dirt from it
	local trainedChar = player.Character
	if trainedChar and GRIME_WASH[act.id] then
		trainedChar:SetAttribute("Grime", nil)
	elseif trainedChar and s.kind == "course" then
		local grime = (tonumber(trainedChar:GetAttribute("Grime")) or 0) + 0.25 + 0.45 * (opts.scale or 1)
		trainedChar:SetAttribute("Grime", math.floor(math.clamp(grime, 0, 1) * 20 + 0.5) / 20)
	end
	applyLook(player)
	-- pump & sweat are attributes on the character model: they survive the rebuild applyLook starts
	-- (Cosmetics re-applies the Sweat attribute) and E/B animate them client-side
	if trainedChar and type(result) == "table" then
		if not act.recovery then
			Training.ApplyPump(trainedChar, result)
		end
		if act.id == "IceBath" then
			setSweat(player, trainedChar, 0, true)
		elseif not act.recovery or SWEAT_RECOVERY[act.id] then
			-- the session result's sweat (C: act.fatigue / 24 * quality), never drier than the build-up so far;
			-- the Sauna has no fatigue of its own and no result.sweat, so it falls back to 18 (about 0.75 at full quality)
			local sweat = tonumber(result.sweat) or math.clamp((act.fatigue or 18) / 24 * quality, 0, 1)
			local st = sweatState[player]
			local cur = st and st.char == trainedChar and st.level or tonumber(trainedChar:GetAttribute("Sweat")) or 0
			setSweat(player, trainedChar, math.max(cur, sweat))
		end
	end
	task.spawn(DataManager.Save, player)
	return { ok = true, result = result, quality = quality, act = act.id, record = record }
end

-- roadwork checkpoints and swim lengths are measured on the server
RunService.Heartbeat:Connect(function()
	for player, s in pairs(sessions) do
		if s.kind == "course" or s.kind == "swim" then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				if s.kind == "course" and s.cp <= #s.cps then
					if flatDist(root.Position, s.cps[s.cp]) < 11 then
						s.cp += 1
						Notify:FireClient(player, { t = "checkpoint", n = s.cp - 1, total = #s.cps })
						if s.cp > #s.cps then
							s.doneAt = os.clock()
						end
					end
				elseif s.kind == "swim" and s.endA and s.lengths < s.target then
					local inWater = root.Position.Y < 1.2
					local target = s.nextEnd == "A" and s.endA or s.endB
					if inWater and math.abs(root.Position.X - target.X) < 4.5 and math.abs(root.Position.Z - target.Z) < 13 then
						s.lengths += 1
						s.nextEnd = s.nextEnd == "A" and "B" or "A"
						Notify:FireClient(player, { t = "length", n = s.lengths, total = s.target })
						if s.lengths >= s.target then
							s.doneAt = os.clock()
						end
					end
				end
			end
		end
	end
end)

-- one build-up / drying step of the exact sweat level (act = the running session's activity or nil)
local function sweatStep(level, act, dt)
	if act and (not act.recovery or SWEAT_RECOVERY[act.id]) then
		if level >= SWEAT_TRAIN_CAP then
			return level
		end
		return math.min(SWEAT_TRAIN_CAP, level + SWEAT_GAIN * math.clamp((tonumber(act.fatigue) or 12) / 12, 0.4, 2) * dt)
	end
	return math.max(0, level - SWEAT_DRY * dt)
end

-- training sweat heartbeat: builds up through a session, dries off while idle. Fights and spars are
-- FightEngine's (per round); look rebuilds and barber / locker previews are left alone.
task.spawn(function()
	while true do
		task.wait(SWEAT_TICK)
		for _, player in ipairs(Players:GetPlayers()) do
			local b = busy[player]
			local char = player.Character
			local look = lookState[player]
			if char and char.Parent and b ~= "fight" and b ~= "spar" and not customizing[player] and not (look and look.running) then
				local cur = tonumber(char:GetAttribute("Sweat")) or 0
				local st = sweatState[player]
				-- keep the exact level unless someone else (a fight round) wrote the attribute since
				local level = (st and st.char == char and quantSweat(st.level) == cur) and st.level or cur
				local sess = sessions[player]
				local nextLevel = sweatStep(level, sess and sess.act, SWEAT_TICK)
				if nextLevel ~= level then
					setSweat(player, char, nextLevel)
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Fight night
------------------------------------------------------------------------
-- A career bout the player walks out of after the opening bell (reset, leaving) is a loss: retired in
-- the corner. Otherwise a losing fighter could reset or rejoin and get the same fight again, fresh.
-- Before the bell nothing has happened yet, so the fight is just called off (camp kept); an engine
-- crash also only calls it off. fightWatch[player] = { profile, offer, decided = the engine's result
-- once it announced it, quit = the forfeit to record, settled = the result was applied }.
local fightWatch = {}
local shuttingDown = false

-- the result of a fight the player is leaving right now, or nil when there is nothing to record
local function quitResult(player)
	local fight = FightEngine.Active[player]
	if type(fight) ~= "table" or fight.spar then
		return nil
	end
	local round = tonumber(fight.round) or 0
	local P, O = fight.P, fight.O
	local res
	if fight.finished and fight.winner and not fight.aborted then
		-- the stoppage was already called this frame: that is the result, not a forfeit
		res = { outcome = fight.winner == P and "win" or "loss", method = fight.method, reason = fight.reason, round = fight.endRound or round }
	elseif round >= 1 then
		res = { outcome = "loss", method = "RTD", reason = "Did not continue", round = round }
	else
		return nil
	end
	res.kdFor, res.kdAgainst = 0, 0
	-- what the engine would hand Career (FightEngine's result fields); guarded, the engine is the source
	pcall(function()
		res.cards = fight.cards
		res.knockdowns = fight.knockdowns
		res.kdFor, res.kdAgainst = O.kdTotal or 0, P.kdTotal or 0
		res.landed, res.thrown = P.totals.landed, P.totals.thrown
		res.oppLanded, res.oppThrown = O.totals.landed, O.totals.thrown
		res.punches = P.punchesUsed
		res.damageDealt, res.damageTaken = P.damageDealt, P.damageTaken
		res.weighIn = P.data.mods and P.data.mods.weighIn
		res.concPeak = math.floor((tonumber(P.concPeak) or 0) * 100) / 100
		res.headTaken = math.floor((tonumber(P.headTaken) or 0) * 10) / 10
		res.bodyTaken = math.floor(100 - (tonumber(P.bodyCap) or 100))
		if type(P.dmg) == "table" then
			res.face = table.clone(P.dmg)
			res.face.age = 0
			res.noseBroken = P.dmg.nose == true and not P.noseAtStart
			res.face.nose = res.noseBroken
		end
	end)
	return res
end

-- apply a fight result to the career exactly once (the fight thread and PlayerRemoving can both get here)
local function settleFight(player, watch, res)
	if watch.settled or not res then
		return nil
	end
	local profile = watch.profile
	if DataManager.Get(player) ~= profile or not (profile.camp and profile.camp.offer == watch.offer) then
		return nil
	end
	watch.settled = true
	return Career.ApplyResult(profile, res)
end

local function runFight(player, profile)
	local offer = profile.camp.offer
	local b = profile.world.boxers[offer.oppId]
	if not b then
		return
	end
	endSession(player)
	setBusy(player, "fight")
	push(player)
	offer.myLine = Career.PlayerLine(profile, b.name)
	-- per-fight venue dressing (CONTRACTS section 7): title stakes, crowd from popularity, supporters with fan
	-- signs, your sponsors on the corner / apron, the gym tier. Every field is optional for Venues.New.
	local popularity = tonumber(profile.popularity) or 0
	local venueOpts = {
		stakes = offer.stakes, playerStakes = offer.playerStakes, kind = offer.kind, popularity = popularity,
		nick = type(profile.identity) == "table" and profile.identity.nickname or nil,
		gymTier = gymTierOf(profile),
		supporters = math.clamp(popularity / 100, 0, 1),
	}
	local okSponsors, sponsors = pcall(Career.ActiveSponsors, profile)
	if okSponsors and type(sponsors) == "table" then
		venueOpts.sponsors = sponsors
	end
	local arena = Venues.New(offer.venue or "Arena", venueOpts)
	local pData = Career.FighterFromProfile(profile)
	local oData = Career.FighterFromBoxer(b)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local watch = { profile = profile, offer = offer }
	fightWatch[player] = watch
	-- the engine announces its result ("final") a few seconds before Run returns: remember it, so a
	-- player who leaves during the closing scene still gets the real result recorded
	local remote = {}
	function remote.FireClient(_, plr, msg)
		if type(msg) == "table" and msg.t == "final" and type(msg.result) == "table" then
			watch.decided = msg.result
		end
		FightRemote:FireClient(plr, msg)
	end
	local diedConn
	if hum then
		diedConn = hum.Died:Connect(function()
			if not watch.decided then
				watch.quit = quitResult(player)
			end
			FightEngine.Abort(player)
		end)
	end
	local ok, res = pcall(FightEngine.Run, player, remote, offer, pData, oData, arena)
	if not ok then
		warn("[Boxer] fight crashed:", res)
		res = nil
		if arena.Parent then
			arena:Destroy()
		end
	end
	if diedConn then
		diedConn:Disconnect()
	end
	if fightWatch[player] == watch then
		fightWatch[player] = nil
	end
	setBusy(player, nil)
	if not player.Parent then
		return -- PlayerRemoving settled the bout before the leave save
	end
	if player.Character then
		player.Character:PivotTo(gymSpawnCFrame())
	end
	res = res or watch.quit
	local out = settleFight(player, watch, res)
	if out then
		FightRemote:FireClient(player, { t = "result", result = res, notes = out.notes, earnings = out.earnings, opp = b.name, kind = offer.kind, venue = offer.venueName })
		task.spawn(DataManager.Save, player, true)
	else
		FightRemote:FireClient(player, { t = "aborted" })
	end
	applyLook(player)
	push(player)
end

------------------------------------------------------------------------
-- Sparring
------------------------------------------------------------------------
local function runSpar(player, profile, intensity)
	endSession(player)
	setBusy(player, "spar")
	push(player)
	local ci = profile.physical.weightClass
	local range = SPAR_RANGE[intensity]
	local exclude = {}
	for _, org in ipairs(Config.Orgs) do
		local champ = profile.world.champions[org][ci]
		if champ then
			exclude[champ] = true
		end
	end
	local b = World.Pick(profile, ci, profile.overall + range[1], profile.overall + range[2], exclude, rng)
	if not b then
		setBusy(player, nil)
		push(player)
		return
	end
	local oData = Career.FighterFromBoxer(b)
	oData.lookOpts.robe = "None"
	local pData = Career.FighterFromProfile(profile)
	if pData.mods.weighIn then
		-- no weigh-in for sparring
		pData.mods.staminaMul = math.clamp(pData.mods.staminaMul + pData.mods.weighIn.penalty, 0.5, 1.1)
		pData.mods.weighIn = nil
	end
	-- the sparring room follows the gym facility tier (Venues dresses it from the GymTier attribute)
	local arena = Venues.New("Gym", {
		ringLevel = math.max(1, profile.gym.levels.ring or 1), popularity = tonumber(profile.popularity) or 0,
		nick = type(profile.identity) == "table" and profile.identity.nickname or nil, gymTier = gymTierOf(profile),
	})
	local offer = { kind = "Sparring", rounds = 1, venue = "Gym", venueName = "Sparring Ring", talk = "", stakes = {}, playerStakes = {} }
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local diedConn
	if hum then
		diedConn = hum.Died:Connect(function()
			FightEngine.Abort(player)
		end)
	end
	local ok, res = pcall(FightEngine.Run, player, FightRemote, offer, pData, oData, arena, { spar = intensity })
	if not ok then
		warn("[Boxer] sparring crashed:", res)
		res = nil
		if arena.Parent then
			arena:Destroy()
		end
	end
	if diedConn then
		diedConn:Disconnect()
	end
	setBusy(player, nil)
	if not player.Parent then
		return
	end
	if player.Character then
		player.Character:PivotTo(CFrame.new(MapBuilder.RingCenter + V3(rng:NextNumber(-3, 3), 4, 17)))
	end
	if res and DataManager.Get(player) == profile then
		local thrown = res.thrown or 0
		local acc = thrown > 0 and (res.landed or 0) / thrown or 0
		local q = 0.55 + acc * 0.7 + (res.outcome == "win" and 0.15 or 0) - ((res.kdAgainst or 0) > 0 and 0.1 or 0)
		q += math.clamp(((res.damageDealt or 0) - (res.damageTaken or 0)) / 80, -0.15, 0.15)
		if thrown < 6 then
			q = 0.4 -- you have to actually spar
		end
		local act = Training.Activity("Sparring")
		local out = Training.Perform(profile, act, q, { intensity = intensity, scale = SPAR_SCALE[intensity], extraRisk = SPAR_RISK[intensity] })
		-- sparring marks follow the player home (CONTRACTS 8.3: res.face is already scaled by the session's
		-- damage level; SPAR_SCALE above is the training-gain scale, unrelated)
		if type(res.face) == "table" and type(Training.AddFaceDamage) == "function" then
			local carry = Config.FaceDamage and Config.FaceDamage.sparCarry or 0.5
			local okFace, errFace = pcall(Training.AddFaceDamage, profile, res.face, carry)
			if not okFace then
				warn("[Boxer] spar face damage:", errFace)
			end
		end
		-- the rounds pump the shoulders / arms / neck worked (Pump / PumpParts / PumpAt attributes, BodyFX reads them)
		if player.Character then
			local okPump, errPump = pcall(Training.ApplyPump, player.Character, out)
			if not okPump then
				warn("[Boxer] spar pump:", errPump)
			end
		end
		if intensity == "Hard" and res.cutTaken and not out.injury and rng:NextNumber() < 0.5 then
			local def = Config.Injuries.cut
			table.insert(profile.condition.injuries, { id = "cut", days = rng:NextInteger(def.days[1], def.days[2]) })
			out.injury = def.name
			table.insert(out.notes, "INJURY: " .. def.name .. " from hard sparring. No sparring until it heals.")
		end
		FightRemote:FireClient(player, { t = "sparResult", result = res, training = out, intensity = intensity, partner = b.name, quality = q })
		task.spawn(DataManager.Save, player)
	else
		FightRemote:FireClient(player, { t = "aborted", spar = true })
	end
	applyLook(player)
	push(player)
end

------------------------------------------------------------------------
-- Look customization (barber / locker room)
------------------------------------------------------------------------
local GLOVE_FIELDS = { color = "color", trim = "trim", finish = "finish", logo = "logo", stitching = "stitching", embName = "embroidery", embNick = "embroidery", brand = "brand" }

local function customLook(profile, section, input)
	local old = profile.appearance
	local san = Looks.Sanitize(input, old)
	local out = table.clone(old)
	if section == "barber" then
		out.hair = san.hair
		out.beard = old.gender == 2 and old.beard or san.beard
		-- "Beard matches hair colour": the client sends no beard.color; Sanitize would keep the old one
		if out.beard == san.beard and type(input) == "table" and type(input.beard) == "table" and input.beard.color == nil then
			out.beard.color = nil
		end
	elseif section == "locker" then
		out.attire = san.attire
		local glove = Catalog.Find(Catalog.Gloves, profile.gear.equipped.gloves) or Catalog.Gloves[1]
		local custom = glove.custom or {}
		local g = table.clone(old.gloves)
		for field, flag in pairs(GLOVE_FIELDS) do
			if custom[flag] then
				g[field] = san.gloves[field]
			end
		end
		if g.finish == "Metallic" and not custom.metallic then
			g.finish = old.gloves.finish
		end
		out.gloves = g
	end
	return out
end

-- one shared price: the Barber UI quotes the same Looks.BarberPrice
local function barberPrice(old, new)
	return Looks.BarberPrice(old, new)
end

------------------------------------------------------------------------
-- Requests from the client
------------------------------------------------------------------------
local handlers = {}

function handlers.GetProfile(player)
	return summary(player)
end

function handlers.CreateBoxer(player, profile, data)
	if profile.created and not profile.retired then
		return { ok = false, err = "You already have a boxer." }
	end
	if type(data) ~= "table" then
		return { ok = false, err = "Bad data" }
	end
	local first = filter(data.first, player.UserId, 14)
	local last = filter(data.last, player.UserId, 16)
	if not first or not last then
		return { ok = false, err = "Please enter a valid first and last name." }
	end
	data.first, data.last = first, last
	data.name = first .. " " .. last
	data.nickname = filter(data.nickname, player.UserId, 20) or "The Prospect"
	local newProfile = Career.CreateProfile(profile, data, player.UserId)
	DataManager.Set(player, newProfile)
	customizing[player] = nil
	applyLook(player)
	task.spawn(DataManager.Save, player, true)
	return { ok = true }
end

local lastPreview = {}
-- preview-only options from the Creator / Barber (never saved): sanitize every field.
-- { peak = Starting/Peak body toggle (creator only), growth = hair growth stage, only = head-only rebuild }
local function previewOpts(popts, creating)
	if type(popts) ~= "table" then
		return nil
	end
	local g = tonumber(popts.growth)
	local only = type(popts.only) == "table" and popts.only or nil
	return {
		peak = (popts.peak == true and creating) or nil,
		growth = (g and g == g) and math.clamp(g, 0, 1.5) or nil,
		only = (only and (only.Face == true or only.Hair == true or only.Beard == true))
			and { Face = only.Face == true, Hair = only.Hair == true, Beard = only.Beard == true } or nil,
	}
end

function handlers.PreviewLook(player, profile, look, hands, popts)
	if type(look) ~= "table" then
		return { ok = false }
	end
	local section = customizing[player]
	local creating = not profile.created or profile.retired
	if not creating and not section then
		return { ok = false }
	end
	local now = os.clock()
	if lastPreview[player] and now - lastPreview[player] < 0.2 then
		return { ok = false, throttled = true }
	end
	lastPreview[player] = now
	local app
	if creating then
		app = Looks.Sanitize(look)
	else
		app = customLook(profile, section, look)
	end
	applyLook(player, app, hands == "gloves" and "gloves" or "wraps", previewOpts(popts, creating))
	return { ok = true }
end

function handlers.BeginCustomize(player, profile, section)
	if section ~= "barber" and section ~= "locker" then
		return { ok = false }
	end
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	if section == "locker" then
		wash(player) -- the locker room has the showers
	end
	customizing[player] = section
	if section == "barber" then
		Ambient.SetLoop("Barber", "barber")
	end
	return { ok = true }
end

function handlers.EndCustomize(player, profile)
	if customizing[player] == "barber" then
		Ambient.SetLoop("Barber", "idle")
	end
	customizing[player] = nil
	applyLook(player)
	return { ok = true }
end

function handlers.CustomizeLook(player, profile, section, look, opts)
	if customizing[player] ~= section or type(look) ~= "table" then
		return { ok = false, err = "Open the barber or the locker room first." }
	end
	opts = type(opts) == "table" and opts or {}
	local new = customLook(profile, section, look)
	local price = 0
	if section == "barber" then
		price = barberPrice(profile.appearance, new)
		if opts.cut ~= false then
			new.hair.growth = 0
		end
		if opts.shave then
			new.beard.growth = 0
		end
		if profile.money < price then
			return { ok = false, err = "The barber charges " .. Config.Money(price) .. "." }
		end
		profile.money -= price
	end
	profile.appearance = new
	if section == "barber" then
		Ambient.SetLoop("Barber", "idle")
	end
	customizing[player] = nil
	applyLook(player)
	task.spawn(DataManager.Save, player)
	return { ok = true, price = price }
end

function handlers.GetOffers(player, profile)
	return { ok = true, offers = Career.GetOffers(profile), camp = profile.camp ~= nil }
end

function handlers.AcceptOffer(player, profile, index)
	local ok, err = Career.AcceptOffer(profile, tonumber(index))
	return { ok = ok, err = err }
end

function handlers.StartFight(player, profile, mode)
	if not profile.camp then
		return { ok = false, err = "No fight booked." }
	end
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	if mode == "sim" then
		local offer = profile.camp.offer
		local res = Career.SimFight(profile, offer)
		local out = Career.ApplyResult(profile, res)
		applyLook(player)
		task.spawn(DataManager.Save, player, true)
		return { ok = true, sim = true, result = res, notes = out.notes, earnings = out.earnings, opp = offer.opp.name, kind = offer.kind, venue = offer.venueName }
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and char:FindFirstChild("HumanoidRootPart") and hum and hum.Health > 0) then
		return { ok = false, err = "Your character isn't ready." }
	end
	task.spawn(runFight, player, profile)
	return { ok = true }
end

function handlers.StartActivity(player, profile, actId)
	return startActivity(player, profile, actId)
end

function handlers.FinishActivity(player, profile, token, score, stats)
	return finishActivity(player, profile, token, score, stats)
end

function handlers.CancelActivity(player)
	endSession(player)
	return { ok = true }
end

-- FLEX (Hub Body tab / training result screen / gym mirror prompt): the Animator plays Pose = kind for
-- 3.2 s and contracts the matching muscles (BodyFX); pump from the last session shows through PumpParts
local FLEX_POSES = {}
for _, k in ipairs((Config.Pump and Config.Pump.poses) or {}) do
	FLEX_POSES[k] = true
end
function handlers.Flex(player, profile, kind)
	if type(kind) ~= "string" or not FLEX_POSES[kind] then
		return { ok = false, err = "Unknown pose" }
	end
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return { ok = false, err = "Your character isn't ready." }
	end
	setBusy(player, "flex")
	local speed = hum.WalkSpeed
	hum.WalkSpeed = 0
	char:SetAttribute("Pose", kind)
	CollectionService:AddTag(char, "Trainee")
	task.delay(3.2, function()
		if busy[player] ~= "flex" then
			return -- something else took over (fight, session): it owns Pose / Trainee now
		end
		setBusy(player, nil)
		if char.Parent then
			CollectionService:RemoveTag(char, "Trainee")
			char:SetAttribute("Pose", nil)
			if hum.Parent then
				hum.WalkSpeed = speed > 0 and speed or 16
			end
		end
		push(player)
	end)
	return { ok = true }
end

function handlers.StartSparring(player, profile, intensity)
	if not SPAR_SCALE[intensity] then
		intensity = "Medium"
	end
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local act = Training.Activity("Sparring")
	local ok, err = Training.CanDo(profile, act, intensity)
	if not ok then
		return { ok = false, err = err }
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum and hum.Health > 0) then
		return { ok = false, err = "Your character isn't ready." }
	end
	task.spawn(runSpar, player, profile, intensity)
	return { ok = true }
end

function handlers.TravelTo(player, profile, stationId)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false }
	end
	local m = stationModel(tostring(stationId))
	if not m then
		return { ok = false, err = "Unknown station" }
	end
	local def = STATION[stationId]
	local target
	if def then
		local use = m:FindFirstChild("UsePoint")
		local p = use.Position + (def.exit or V3(0, 0, 3))
		target = CFrame.lookAt(V3(p.X, 4.5, p.Z), V3(use.Position.X, 4.5, use.Position.Z))
	else
		local base = m:FindFirstChild("Base")
		target = CFrame.new(base.Position + V3(0, 3.5, 0))
	end
	char:PivotTo(target)
	return { ok = true }
end

function handlers.Eat(player, profile, mealId)
	if busy[player] == "fight" or busy[player] == "spar" then
		return { ok = false, err = "Not now!" }
	end
	-- the Hub badge and the rendered body must agree (CONTRACTS section 2): rebuild when a meal moves the
	-- physique class or the body fat by a step the Builder draws (it quantises fat to 0.5)
	local function fatStep()
		return math.floor((tonumber(profile.body and profile.body.fat) or 14) * 2 + 0.5)
	end
	local okBefore, before = pcall(Training.PhysiqueInfo, profile)
	local f0 = fatStep()
	local ok, info = Training.Eat(profile, mealId)
	if not ok then
		return { ok = false, err = info }
	end
	local okAfter, after = pcall(Training.PhysiqueInfo, profile)
	if fatStep() ~= f0 or not (okBefore and okAfter and before.id == after.id) then
		applyLook(player)
	end
	return { ok = true, info = info }
end

function handlers.Sleep(player, profile)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local res = Training.Sleep(profile)
	-- a new day starts showered: no sweat, no road dirt (the rebuild below draws the clean body)
	local char = player.Character
	if char then
		char:SetAttribute("Grime", nil)
		setSweat(player, char, 0)
	end
	applyLook(player) -- hair and beard keep growing
	-- wake up at home / at the gym when the player chose it in the Life tab (behind the client's fade to black)
	local wake = type(profile.settings) == "table" and profile.settings.wakeAt or nil
	if wake == "home" or wake == "gym" then
		task.delay(1.1, function()
			if busy[player] or not player.Parent or DataManager.Get(player) ~= profile then
				return
			end
			local c = player.Character
			if not (c and c:FindFirstChild("HumanoidRootPart")) then
				return
			end
			local cf
			if wake == "gym" then
				cf = gymSpawnCFrame()
			else
				local ok, homeCF = pcall(CityMap.TravelCFrame, player, profile, "home")
				cf = ok and homeCF or nil
			end
			if typeof(cf) == "CFrame" then
				c:PivotTo(cf)
			end
		end)
	end
	task.spawn(DataManager.Save, player)
	return { ok = true, sleep = res }
end

-- city travel: home interiors / estate / Elite Performance Center / Main Street / training camp
local function travel(player, profile, where, kind)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, err = "Your character isn't ready." }
	end
	local cf, err
	if where == "gym" then
		cf = gymSpawnCFrame()
	else
		local ok, a, b = pcall(CityMap.TravelCFrame, player, profile, where, kind)
		if ok then
			cf, err = a, b
		else
			warn("[Boxer] travel:", a)
			err = "Can't go there right now."
		end
	end
	if typeof(cf) ~= "CFrame" then
		return { ok = false, err = type(err) == "string" and err or "Can't go there." }
	end
	char:PivotTo(cf)
	return { ok = true, where = where }
end

function handlers.TravelHome(player, profile, kind)
	return travel(player, profile, "home", type(kind) == "string" and kind or nil)
end

function handlers.LeaveHome(player, profile)
	return travel(player, profile, "outside")
end

local TRAVEL_PLACES = { gym = true, city = true, elite = true, estate = true, camp = true, outside = true }
function handlers.TravelPlace(player, profile, where)
	if not TRAVEL_PLACES[where] then
		return { ok = false, err = "Unknown place" }
	end
	return travel(player, profile, where)
end

function handlers.SignSponsor(player, profile, id, replace)
	local ok, info = Career.SignSponsor(profile, tostring(id), replace == true)
	if ok then
		task.spawn(DataManager.Save, player)
		applyLook(player) -- the logo goes on the trunks / robe
	end
	return { ok = ok, err = not ok and info or nil, name = ok and info or nil }
end

function handlers.DropSponsor(player, profile, key)
	local ok, info = Career.DropSponsor(profile, tostring(key))
	if ok then
		applyLook(player)
	end
	return { ok = ok, err = not ok and info or nil }
end

function handlers.Autograph(player, profile)
	local ok, err = Career.Autograph(profile)
	return { ok = ok, err = err }
end

function handlers.SetWakeAt(player, profile, where)
	local ok, err = Career.SetWakeAt(profile, where)
	return { ok = ok, err = err }
end

function handlers.Buy(player, profile, id)
	local ok, err = Career.Buy(profile, tostring(id))
	if ok then
		-- homes, cars and facility items are big purchases: save now (the push re-publishes GymTier / Fame)
		task.spawn(DataManager.Save, player)
	end
	return { ok = ok, err = err }
end

function handlers.UpgradeStation(player, profile, id)
	local ok, info = Training.UpgradeStation(profile, tostring(id))
	if ok then
		task.spawn(DataManager.Save, player)
	end
	return { ok = ok, err = not ok and info or nil, name = ok and info or nil }
end

function handlers.RepairStation(player, profile, id)
	local ok, info = Training.RepairStation(profile, tostring(id))
	return { ok = ok, err = not ok and info or nil, cost = ok and info or nil }
end

function handlers.BuyGear(player, profile, kind, id)
	local ok, err = Training.BuyGear(profile, kind, id)
	if ok then
		applyLook(player)
		task.spawn(DataManager.Save, player)
	end
	return { ok = ok, err = err }
end

function handlers.Equip(player, profile, kind, id)
	local ok, err = Training.Equip(profile, kind, id)
	if ok then
		applyLook(player)
	end
	return { ok = ok, err = err }
end

function handlers.RepairGear(player, profile, kind)
	local ok, info = Training.RepairGear(profile, kind)
	if ok then
		applyLook(player)
	end
	return { ok = ok, err = not ok and info or nil, cost = ok and info or nil }
end

function handlers.HireCoach(player, profile, spec, tier)
	local ok, info = Training.HireCoach(profile, spec, tier)
	return { ok = ok, err = not ok and info or nil, name = ok and info or nil }
end

function handlers.FireCoach(player, profile, spec)
	local ok, err = Training.FireCoach(profile, spec)
	return { ok = ok, err = err }
end

function handlers.ChangeWeightClass(player, profile, dir)
	local ok, info, vacated = Career.ChangeWeightClass(profile, tonumber(dir))
	return { ok = ok, err = not ok and info or nil, class = ok and info or nil, vacated = vacated }
end

-- R-ui Settings screen: UI scale, screen FX, camera shake, music / sfx volume, graphics detail, menu at start,
-- the fight's control strip (same ranges as Settings.Sanitize on the client; unknown keys dropped)
local UI_SETTING_RANGES = { uiScale = { 0.8, 1.25 }, screenFx = { 0, 1.5 }, shake = { 0, 1.5 }, music = { 0, 1 }, sfx = { 0, 1 } }
local UI_DETAILS = { Auto = true, High = true, Medium = true, Low = true }
local UI_FLAGS = { "menuAtStart", "controlHints" }
function handlers.SaveSettings(player, profile, t)
	if type(t) ~= "table" then
		return { ok = false, err = "Bad settings" }
	end
	local clean = {}
	for k, r in pairs(UI_SETTING_RANGES) do
		local v = tonumber(t[k])
		if v and v == v then
			clean[k] = math.floor(math.clamp(v, r[1], r[2]) * 100 + 0.5) / 100
		end
	end
	if type(t.detail) == "string" and UI_DETAILS[t.detail] then
		clean.detail = t.detail
	end
	for _, k in ipairs(UI_FLAGS) do
		if type(t[k]) == "boolean" then
			clean[k] = t[k]
		end
	end
	if type(profile.settings) ~= "table" then
		profile.settings = {}
	end
	profile.settings.ui = clean
	return { ok = true }
end

function handlers.GetRankings(player, profile, classIdx, org)
	-- integer class index only: 1.5 / NaN / "nan" would index no class list
	local ci = tonumber(classIdx)
	if not ci or ci ~= ci then
		ci = profile.physical.weightClass
	end
	classIdx = math.clamp(math.floor(ci), 1, #Config.WeightClasses)
	if not table.find(Config.Orgs, org) then
		org = "WBA"
	end
	local list = World.Rankings(profile, classIdx, org)
	local out = {}
	for i, e in ipairs(list) do
		if i <= 25 or e.isPlayer then
			table.insert(out, { rank = e.rank, name = e.name, nick = e.nick, record = e.record, overall = e.overall, nat = e.nat, isPlayer = e.isPlayer, id = e.id })
		end
	end
	return { ok = true, list = out, class = Config.WeightClasses[classIdx].name, org = org }
end

function handlers.GetBoxer(player, profile, id)
	local b = profile.world.boxers[tostring(id)]
	if not b then
		return { ok = false }
	end
	local v = Career.OppView(profile, b)
	local stats = {}
	for k, val in pairs(b.stats) do
		stats[k] = math.floor(val)
	end
	v.stats = stats
	v.height = b.height
	return { ok = true, boxer = v }
end

function handlers.GetRivals(player, profile)
	local list = {}
	for _, b in pairs(profile.world.boxers) do
		local total = b.h2h.w + b.h2h.l + b.h2h.d
		if total > 0 then
			table.insert(list, { id = b.id, name = b.name, nick = b.nick, h2h = b.h2h, heat = math.floor(b.heat), personality = b.personality, overall = b.overall, record = b.record, retired = b.retired })
		end
	end
	table.sort(list, function(a, c)
		return a.heat > c.heat
	end)
	return { ok = true, list = list }
end

function handlers.GetLegacy(player, profile)
	if not profile.created and not profile.final then
		-- the creator / a fresh career after retiring: no record to score yet, only the hall of past careers
		return { ok = true, legacy = nil, pastCareers = profile.pastCareers }
	end
	local lg = profile.final or Career.Legacy(profile)
	return { ok = true, legacy = lg, pastCareers = profile.pastCareers }
end

function handlers.Retire(player, profile)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	Career.Retire(profile)
	task.spawn(DataManager.Save, player, true)
	return { ok = true, legacy = profile.final }
end

function handlers.NewCareer(player, profile)
	if not profile.retired then
		return { ok = false, err = "Retire first." }
	end
	DataManager.Set(player, DataManager.Blank(profile.pastCareers))
	return { ok = true }
end

function handlers.DebugMoney(player, profile)
	if not RunService:IsStudio() then
		return { ok = false }
	end
	profile.money += 1000000
	return { ok = true }
end

local PRE_CREATE = { GetProfile = true, CreateBoxer = true, NewCareer = true, PreviewLook = true, GetLegacy = true, SaveSettings = true }
local READ_ONLY = { GetProfile = true, GetRankings = true, GetBoxer = true, PreviewLook = true, GetOffers = true, GetRivals = true, GetLegacy = true }
local DURING_ACTIVITY = { FinishActivity = true, CancelActivity = true, Eat = true, SaveSettings = true }
-- actions that change nothing the summary shows: no push afterwards (R-ui)
local NO_PUSH = { SaveSettings = true }
-- allowed in the ring too: the Settings screen opens mid-fight and its save is never retried
local IN_RING = { SaveSettings = true }

Request.OnServerInvoke = function(player, action, ...)
	local profile = DataManager.Get(player)
	if not profile then
		return { ok = false, err = "Loading..." }
	end
	local h = type(action) == "string" and handlers[action]
	if not h then
		return { ok = false, err = "Unknown action" }
	end
	if not PRE_CREATE[action] and not profile.created then
		return { ok = false, err = "Create your boxer first." }
	end
	local b = busy[player]
	if (b == "fight" or b == "spar") and not READ_ONLY[action] and not IN_RING[action] then
		return { ok = false, err = "You're in the ring!" }
	end
	if b == "activity" and not READ_ONLY[action] and not DURING_ACTIVITY[action] then
		return { ok = false, err = "Finish your current exercise first." }
	end
	local ok, res = pcall(h, player, profile, ...)
	if not ok then
		warn("[Boxer] handler error", action, res)
		return { ok = false, err = "Server error" }
	end
	if not READ_ONLY[action] and not NO_PUSH[action] then
		task.defer(push, player)
	end
	return res
end

FightRemote.OnServerEvent:Connect(function(player, msg)
	FightEngine.Input(player, msg)
end)

------------------------------------------------------------------------
-- Players
------------------------------------------------------------------------
local function onCharacter(player, char)
	endSession(player, true)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			if sessions[player] then
				endSession(player, true)
			end
		end)
	end
	task.wait(0.3)
	local profile = DataManager.Get(player)
	if profile and profile.created and not profile.retired then
		applyLook(player)
	elseif profile then
		applyLook(player, Looks.Defaults(1)) -- a lean starter look while the creator is open
	end
end

-- a career whose load failed at join arrived on a retry: show it and dress the character
DataManager.OnLoaded = function(player)
	if not player.Parent then
		return
	end
	push(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	player.CharacterRemoving:Connect(function()
		endSession(player, true)
	end)
	DataManager.Load(player)
	if not player.Parent then
		return
	end
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	push(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- leaving a career bout: record it (the real result if it was already announced, else a forfeit
	-- after the opening bell) BEFORE the leave save. A server shutdown is not the player's doing.
	local watch = fightWatch[player]
	if watch then
		local ok, err = pcall(function()
			local res = watch.decided or (not shuttingDown and quitResult(player)) or nil
			settleFight(player, watch, res)
		end)
		if not ok then
			warn("[Boxer] fight settle on leave:", err)
		end
	end
	FightEngine.Abort(player)
	endSession(player, true)
	busy[player] = nil
	if customizing[player] == "barber" then
		Ambient.SetLoop("Barber", "idle") -- the shared barber NPC stops cutting for an empty chair
	end
	customizing[player] = nil
	lookState[player] = nil
	lastPreview[player] = nil
	sweatState[player] = nil
	for id, p in pairs(occupied) do
		if p == player then
			occupied[id] = nil
		end
	end
	DataManager.Release(player)
end)

game:BindToClose(function()
	shuttingDown = true
	-- save everyone in parallel so the retries fit the shutdown budget, then wait for the leave saves
	local left = 0
	for _, player in ipairs(Players:GetPlayers()) do
		left += 1
		task.spawn(function()
			DataManager.Save(player, true)
			left -= 1
		end)
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 25 do
		task.wait(0.25)
	end
	DataManager.WaitForReleases(25 - (os.clock() - t0))
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			if not busy[player] then
				DataManager.Save(player)
			end
		end
	end
end)

print("[Boxer] " .. Config.GameName .. " server ready")
