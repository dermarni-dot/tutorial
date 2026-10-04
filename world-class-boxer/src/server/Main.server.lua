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
local PROP_FOR = { bench = "bench", deadlift = "deadlift", squat = "squat", curl = "curl", rope = "rope", row = "row" }
-- shortest believable time for each minigame (anything faster is treated as a sloppy session)
local MIN_TIME = { combo = 9, rhythm = 9, reaction = 9, mitts = 9, shadow = 9, reps = 9, pace = 11, ladder = 7, rope = 9, hold = 5 }
local SPAR_SCALE = { Light = 0.7, Medium = 1.0, Hard = 1.35 }
local SPAR_RISK = { Light = 0, Medium = 0.01, Hard = 0.035 }
local SPAR_RANGE = { Light = { -12, -4 }, Medium = { -5, 3 }, Hard = { 0, 8 } }
local PREVIEW_BUILD = { chest = 8, shoulders = 8, arms = 8, back = 8, legs = 8, core = 8, neck = 8, fat = 14 }
local PREVIEW_GEAR = { gloves = "Worn", glovesCond = 55, wrapsCond = 50 }

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
		return { created = false, loading = true }
	end
	local s = Career.Summary(profile, DataManager.StoreAvailable)
	s.busy = busy[player]
	s.studio = RunService:IsStudio()
	return s
end

local function push(player)
	if player.Parent then
		ProfileRemote:FireClient(player, summary(player))
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
local function applyLook(player, previewApp, hands)
	local st = lookState[player]
	if not st then
		st = {}
		lookState[player] = st
	end
	st.app = previewApp
	st.hands = hands
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
				local gear = profile.created and Career.GearView(profile) or PREVIEW_GEAR
				local opts = profile.created and Career.LookOpts(profile, { hands = st.hands or "wraps" })
					or { hands = st.hands or "wraps", name = "", nick = "", waistText = "" }
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
	applyLook(player)
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

------------------------------------------------------------------------
-- Fight night
------------------------------------------------------------------------
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
	local arena = Venues.New(offer.venue or "Arena")
	local pData = Career.FighterFromProfile(profile)
	local oData = Career.FighterFromBoxer(b)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local diedConn
	if hum then
		diedConn = hum.Died:Connect(function()
			FightEngine.Abort(player)
		end)
	end
	local ok, res = pcall(FightEngine.Run, player, FightRemote, offer, pData, oData, arena)
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
	setBusy(player, nil)
	if not player.Parent then
		return
	end
	if player.Character then
		player.Character:PivotTo(gymSpawnCFrame())
	end
	if res and DataManager.Get(player) == profile and profile.camp then
		local out = Career.ApplyResult(profile, res)
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
	local arena = Venues.New("Gym", { ringLevel = math.max(1, profile.gym.levels.ring or 1) })
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
local GLOVE_FIELDS = { color = "color", trim = "trim", finish = "finish", logo = "logo", stitching = "stitching", embName = "embroidery", embNick = "embroidery" }

local function customLook(profile, section, input)
	local old = profile.appearance
	local san = Looks.Sanitize(input, old)
	local out = table.clone(old)
	if section == "barber" then
		out.hair = san.hair
		out.beard = old.gender == 2 and old.beard or san.beard
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

local function barberPrice(old, new)
	local price = 30
	local h1, h2 = old.hair, new.hair
	if h2.hl ~= h1.hl or h2.dye ~= h1.dye or (h2.hl or h2.dye ~= "None") and table.concat(h2.hcolor, ",") ~= table.concat(h1.hcolor, ",") then
		price += 60
	end
	if table.concat(h2.color, ",") ~= table.concat(h1.color, ",") then
		price += 40
	end
	return price
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
function handlers.PreviewLook(player, profile, look, hands)
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
	applyLook(player, app, hands == "gloves" and "gloves" or "wraps")
	return { ok = true }
end

function handlers.BeginCustomize(player, profile, section)
	if section ~= "barber" and section ~= "locker" then
		return { ok = false }
	end
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
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
	local ok, info = Training.Eat(profile, mealId)
	if not ok then
		return { ok = false, err = info }
	end
	return { ok = true, info = info }
end

function handlers.Sleep(player, profile)
	if busy[player] then
		return { ok = false, err = "Finish what you're doing first." }
	end
	local res = Training.Sleep(profile)
	applyLook(player) -- hair and beard keep growing
	task.spawn(DataManager.Save, player)
	return { ok = true, sleep = res }
end

function handlers.Buy(player, profile, id)
	local ok, err = Career.Buy(profile, id)
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

function handlers.GetRankings(player, profile, classIdx, org)
	classIdx = math.clamp(tonumber(classIdx) or profile.physical.weightClass, 1, #Config.WeightClasses)
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

local PRE_CREATE = { GetProfile = true, CreateBoxer = true, NewCareer = true, PreviewLook = true, GetLegacy = true }
local READ_ONLY = { GetProfile = true, GetRankings = true, GetBoxer = true, PreviewLook = true, GetOffers = true, GetRivals = true, GetLegacy = true }
local DURING_ACTIVITY = { FinishActivity = true, CancelActivity = true, Eat = true }

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
	if (b == "fight" or b == "spar") and not READ_ONLY[action] then
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
	if not READ_ONLY[action] then
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
	FightEngine.Abort(player)
	endSession(player, true)
	busy[player] = nil
	customizing[player] = nil
	lookState[player] = nil
	lastPreview[player] = nil
	for id, p in pairs(occupied) do
		if p == player then
			occupied[id] = nil
		end
	end
	DataManager.Release(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		DataManager.Save(player, true)
	end
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
