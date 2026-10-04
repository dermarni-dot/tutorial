-- Ambience: brings the gym and the town to life on the client.
--  * SpinFan     - models whose "Hub"/"Blade" parts spin about the hub's local X (Speed attr, rad/s)
--  * RoundTimer  - gym round clocks run a shared 3:00 round / 1:00 rest cycle with their lamps,
--                  and the nearest one rings the bell (three dings) when a round starts or ends
--  * TVTicker    - TV screens scroll their headline ticker
--  * NeonFlicker - neon signs flicker now and then (a tagged Model blinks only its Neon parts and
--                  switches its lights with them: failing pendant tubes in a Beginner gym)
--  * NightLight / NightLens - street, shop and monument lights switch on at dusk
--  * LightZone   - invisible boxes with a Profile attribute: the picture is graded for the zone the
--                  camera is in (client ColorCorrectionEffect "ZoneGrade", off during fights)
--  * the gym's sound: an air-handling bed, people training (treadmill footfalls, plates, ropes,
--    shadow-boxing), hangar reverb inside the hall, optional uploaded gym music / ambience
--  * coaches who shout instructions (speech bubbles + optional CoachShout upload), react to your
--    work (Ambience.React) and turn to watch you train (client-local LookAt attribute)
--  * dust motes hanging in the light and sun shafts through the windows and skylights
-- Everything is tag / name driven, so pieces streamed in later are picked up too. Movers only update
-- near the camera and at most ~30 times a second; the heavier systems run at 4 Hz or slower.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GymSound = require(script.Parent:WaitForChild("GymSound"))

local Ambience = {}

local NEAR = 160 -- studs: fans, timers and tickers further away than this stay still
local FLICKER_NEAR = 420
local ROUND, REST = 180, 60
local LENS_DAY = Color3.fromRGB(200, 200, 196)
local LENS_NIGHT = Color3.fromRGB(255, 236, 200)

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function watch(tagName, onAdd, onRemove)
	for _, inst in ipairs(CollectionService:GetTagged(tagName)) do
		task.spawn(onAdd, inst)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(onAdd)
	if onRemove then
		CollectionService:GetInstanceRemovedSignal(tagName):Connect(onRemove)
	end
end

------------------------------------------------------------------------
-- Fans and the barber pole
------------------------------------------------------------------------
local fans = {}

local function addFan(m)
	if not m:IsA("Model") or fans[m] then
		return
	end
	local hub = m.PrimaryPart or m:FindFirstChild("Hub")
	if not hub then
		return
	end
	local entry = { model = m, hub0 = hub.CFrame, angle = math.random() * math.pi * 2, parts = {}, rel = {} }
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Hub" or d.Name == "Blade") then
			table.insert(entry.parts, d)
			table.insert(entry.rel, entry.hub0:ToObjectSpace(d.CFrame))
		end
	end
	if #entry.parts > 0 then
		fans[m] = entry
	end
end

local function updateFans(dt, cam)
	local bulkParts, bulkCFrames = {}, {}
	for m, e in pairs(fans) do
		if not m.Parent then
			fans[m] = nil
		elseif (e.hub0.Position - cam).Magnitude < NEAR then
			e.angle = (e.angle + (m:GetAttribute("Speed") or 6) * dt) % (math.pi * 2)
			local hubCF = e.hub0 * CFrame.Angles(e.angle, 0, 0)
			for i, p in ipairs(e.parts) do
				table.insert(bulkParts, p)
				table.insert(bulkCFrames, hubCF * e.rel[i])
			end
		end
	end
	if #bulkParts > 0 then
		local ok = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for i, p in ipairs(bulkParts) do
				p.CFrame = bulkCFrames[i]
			end
		end
	end
end

------------------------------------------------------------------------
-- Round timers: everyone in the server sees the same clock
------------------------------------------------------------------------
local timers = {}
local lastPhase

local function addTimer(m)
	if not m:IsA("Model") or timers[m] then
		return
	end
	local box = m:FindFirstChild("TimerBox")
	if not box then
		return
	end
	local entry = { model = m, pos = box.Position, phases = {}, times = {}, lamps = {} }
	for _, sg in ipairs(box:GetChildren()) do
		if sg:IsA("SurfaceGui") then
			local ph = sg:FindFirstChild("Phase", true)
			local tm = sg:FindFirstChild("Time", true)
			if ph then
				table.insert(entry.phases, ph)
			end
			if tm then
				table.insert(entry.times, tm)
			end
		end
	end
	for _, n in ipairs({ "LampGo", "LampWarn", "LampRest" }) do
		entry.lamps[n] = m:FindFirstChild(n)
	end
	timers[m] = entry
end

local function serverNow()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.clock()
end

local function updateTimers(cam)
	local now = serverNow()
	local cycle = ROUND + REST
	local t = now % cycle
	local round = math.floor(now / cycle) % 12 + 1
	local phase, left, lamp, color
	if t < ROUND then
		left = ROUND - t
		phase = "ROUND " .. round
		lamp = left <= 10 and "LampWarn" or "LampGo"
		color = left <= 10 and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 60, 50)
	else
		left = cycle - t
		phase = "REST"
		lamp = "LampRest"
		color = Color3.fromRGB(80, 200, 255)
	end
	local secs = math.ceil(left)
	local text = string.format("%d:%02d", secs // 60, secs % 60)
	local phaseKind = t < ROUND and "round" or "rest"
	local ring = lastPhase ~= nil and phaseKind ~= lastPhase
	lastPhase = phaseKind
	local nearest, nearestD
	for m, e in pairs(timers) do
		if not m.Parent then
			timers[m] = nil
		elseif (e.pos - cam).Magnitude < NEAR then
			for _, l in ipairs(e.phases) do
				l.Text = phase
			end
			for _, l in ipairs(e.times) do
				l.Text = text
				l.TextColor3 = color
			end
			for n, p in pairs(e.lamps) do
				p.Transparency = (n == lamp) and 0 or 0.65
			end
			local d = (e.pos - cam).Magnitude
			if not nearestD or d < nearestD then
				nearest, nearestD = e, d
			end
		end
	end
	if ring and nearest then
		Ambience.Bell(nearest.pos, phaseKind)
	end
end

-- the round bell: three quick dings (an uploaded RingBell plays once instead), and a coach calls it
function Ambience.Bell(pos, phaseKind)
	if Config.SoundId and Config.SoundId("RingBell") then
		GymSound.Play("bell", pos, { volume = 1 })
	else
		for i = 0, 2 do
			task.delay(i * 0.16, function()
				GymSound.Play("bell", pos, { volume = 1 - i * 0.12 })
			end)
		end
	end
	if phaseKind then
		task.delay(0.6, function()
			Ambience.React(phaseKind == "rest" and "TIME! Breathe, shake it out." or "WORK! Hands up!", "bell")
		end)
	end
end

------------------------------------------------------------------------
-- TV tickers
------------------------------------------------------------------------
local tickers = {}

local function addTicker(screen)
	if not screen:IsA("BasePart") or tickers[screen] then
		return
	end
	for _, sg in ipairs(screen:GetChildren()) do
		if sg:IsA("SurfaceGui") then
			local fr = sg:FindFirstChild("Ticker")
			local txt = fr and fr:FindFirstChild("Text")
			if txt then
				tickers[screen] = { frame = fr, text = txt, offset = math.random() * 400 }
				return
			end
		end
	end
end

local function updateTickers(dt, cam)
	for screen, e in pairs(tickers) do
		if not screen.Parent then
			tickers[screen] = nil
		elseif (screen.Position - cam).Magnitude < NEAR then
			local w = e.frame.AbsoluteSize.X
			local tw = e.text.TextBounds.X
			if w > 0 and tw > 0 then
				e.offset = (e.offset + 70 * dt) % (tw + w)
				e.text.Position = UDim2.new(0, math.floor(w - e.offset), 0, 0)
			end
		end
	end
end

------------------------------------------------------------------------
-- Neon flicker
------------------------------------------------------------------------
local neons = {}

local function addNeon(inst)
	if neons[inst] then
		return
	end
	local parts, lights = {}, {}
	if inst:IsA("BasePart") then
		parts = { inst }
	else
		-- a tagged model blinks its Neon parts (bulbs, tubes) and switches its lights with them
		local all = {}
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(all, d)
				if d.Material == Enum.Material.Neon then
					table.insert(parts, d)
				end
			elseif d:IsA("Light") then
				table.insert(lights, d)
			end
		end
		if #parts == 0 then
			parts = all
		end
	end
	if #parts == 0 then
		return
	end
	local base = {}
	for i, p in ipairs(parts) do
		base[i] = p.Transparency
	end
	local lightOn = {}
	for i, l in ipairs(lights) do
		lightOn[i] = l.Enabled
	end
	neons[inst] = { parts = parts, base = base, lights = lights, lightOn = lightOn, pos = parts[1].Position, nextAt = os.clock() + 2 + math.random() * 10, busy = false }
end

local function restoreNeon(e)
	for i, p in ipairs(e.parts) do
		if p.Parent then
			p.Transparency = e.base[i]
		end
	end
	for i, l in ipairs(e.lights) do
		if l.Parent then
			l.Enabled = e.lightOn[i]
		end
	end
end

local function removeNeon(inst)
	local e = neons[inst]
	if e then
		neons[inst] = nil
		e.removed = true
		restoreNeon(e)
	end
end

local function flicker(e)
	e.busy = true
	task.spawn(function()
		local steps = math.random(3, 6)
		for s = 1, steps do
			if e.removed then
				break
			end
			local off = s % 2 == 1
			for i, p in ipairs(e.parts) do
				if p.Parent then
					p.Transparency = off and math.max(e.base[i], 0.85) or e.base[i]
				end
			end
			for i, l in ipairs(e.lights) do
				if l.Parent then
					l.Enabled = (not off) and e.lightOn[i]
				end
			end
			task.wait(0.04 + math.random() * 0.09)
		end
		restoreNeon(e)
		e.busy = false
		e.nextAt = os.clock() + 4 + math.random() * 12
	end)
end

local function updateNeons(cam)
	local now = os.clock()
	for inst, e in pairs(neons) do
		if not inst.Parent then
			neons[inst] = nil
		elseif not e.busy and now >= e.nextAt then
			if (e.pos - cam).Magnitude < FLICKER_NEAR then
				flicker(e)
			else
				e.nextAt = now + 5
			end
		end
	end
end

------------------------------------------------------------------------
-- Night lights
------------------------------------------------------------------------
local nightLights, nightLenses = {}, {}
local isNight = nil

local function nightNow()
	local h = Lighting.ClockTime
	return h >= 17.8 or h < 6.3
end

local function applyLight(l, on)
	if l:IsA("Light") then
		l.Enabled = on
	end
end

local function applyLens(p, on)
	if p:IsA("BasePart") then
		p.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		p.Color = on and LENS_NIGHT or LENS_DAY
	end
end

local function updateNight(force)
	local n = nightNow()
	if n == isNight and not force then
		return
	end
	isNight = n
	for l in pairs(nightLights) do
		if l.Parent then
			applyLight(l, n)
		else
			nightLights[l] = nil
		end
	end
	for p in pairs(nightLenses) do
		if p.Parent then
			applyLens(p, n)
		else
			nightLenses[p] = nil
		end
	end
end

------------------------------------------------------------------------
-- Zone grading (tag LightZone, attribute Profile)
------------------------------------------------------------------------
local player = Players.LocalPlayer
local tier = 1
local zones = {}
-- ColorCorrection targets per profile; the gym's warm grade follows the facility tier
local GRADES = {
	GymWarm = {
		{ b = -0.025, c = 0.09, s = -0.14, tint = Color3.fromRGB(255, 232, 206) }, -- tired, yellowed
		{ b = 0, c = 0.05, s = 0, tint = Color3.fromRGB(255, 246, 236) },
		{ b = 0.012, c = 0.06, s = 0.02, tint = Color3.fromRGB(246, 249, 255) }, -- crisp
		{ b = 0.02, c = 0.08, s = 0.07, tint = Color3.fromRGB(255, 240, 214) }, -- rich and golden
	},
	GymElite = { b = 0.02, c = 0.06, s = -0.03, tint = Color3.fromRGB(236, 244, 255) },
	Barbershop = { b = 0.01, c = 0.05, s = 0.06, tint = Color3.fromRGB(255, 236, 214) },
	Apartment = { b = 0, c = 0.03, s = -0.04, tint = Color3.fromRGB(255, 240, 226) },
	Store = { b = 0.03, c = 0.04, s = 0.03, tint = Color3.fromRGB(246, 250, 255) },
	Mansion = { b = 0.02, c = 0.08, s = 0.07, tint = Color3.fromRGB(255, 238, 210) },
	Street = { b = 0, c = 0.02, s = 0, tint = Color3.fromRGB(255, 255, 255) },
}
local NEUTRAL = { b = 0, c = 0, s = 0, tint = Color3.new(1, 1, 1) }
local grade -- the client-only ZoneGrade effect
local gradeNow = { b = 0, c = 0, s = 0, tint = Color3.new(1, 1, 1) }

local function profileGrade(name)
	local g = GRADES[name]
	if g and g[1] then
		return g[math.clamp(tier, 1, #g)]
	end
	return g
end

local function addZone(p)
	if p:IsA("BasePart") then
		zones[p] = true
	end
end

-- the smallest LightZone box containing the camera (nil = none)
local function zoneAt(pos)
	local best, bestVol
	for p in pairs(zones) do
		if not p.Parent then
			zones[p] = nil
		else
			local l = p.CFrame:PointToObjectSpace(pos)
			local s = p.Size
			if math.abs(l.X) <= s.X / 2 and math.abs(l.Y) <= s.Y / 2 + 4 and math.abs(l.Z) <= s.Z / 2 then
				local vol = s.X * s.Y * s.Z
				if not bestVol or vol < bestVol then
					best, bestVol = p, vol
				end
			end
		end
	end
	return best
end

local function updateGrade(dt, cam)
	if not grade or not grade.Parent then
		grade = Lighting:FindFirstChild("ZoneGrade")
		if not grade then
			grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "ZoneGrade"
			grade.Parent = Lighting
		end
	end
	-- fight nights own the picture (VenueFX / FightClient grade it)
	if player:GetAttribute("InFight") == true then
		grade.Enabled = false
		return
	end
	local z = zoneAt(cam)
	local target = (z and profileGrade(z:GetAttribute("Profile"))) or NEUTRAL
	local k = math.clamp(dt * 1.6, 0, 1)
	gradeNow.b += (target.b - gradeNow.b) * k
	gradeNow.c += (target.c - gradeNow.c) * k
	gradeNow.s += (target.s - gradeNow.s) * k
	gradeNow.tint = gradeNow.tint:Lerp(target.tint, k)
	grade.Enabled = true
	grade.Brightness = gradeNow.b
	grade.Contrast = gradeNow.c
	grade.Saturation = gradeNow.s
	grade.TintColor = gradeNow.tint
end

------------------------------------------------------------------------
-- Where the camera is: the main hall, the elite wing, or outside
------------------------------------------------------------------------
local function inHall(p)
	return math.abs(p.X) < 110 and math.abs(p.Z) < 80 and p.Y > -2 and p.Y < 30
end
local function inWing(p)
	return p.X > 111 and p.X < 153 and p.Z > 30 and p.Z < 66 and p.Y > -2 and p.Y < 21
end

-- hangar reverb inside the hall, a smaller room in the wing; only written on transitions so a fight
-- venue (or anyone else) can set its own reverb while we are away
local reverbState, reverbBefore
local function updateReverb(cam)
	local want = inHall(cam) and "hall" or (inWing(cam) and "wing" or nil)
	if want == reverbState then
		return
	end
	pcall(function()
		if want and not reverbState then
			reverbBefore = SoundService.AmbientReverb
		end
		if want == "hall" then
			SoundService.AmbientReverb = Enum.ReverbType.Hangar
		elseif want == "wing" then
			SoundService.AmbientReverb = Enum.ReverbType.Room
		else
			SoundService.AmbientReverb = reverbBefore or Enum.ReverbType.NoReverb
		end
	end)
	reverbState = want
end

------------------------------------------------------------------------
-- The gym's sound bed and the sounds of people training
------------------------------------------------------------------------
local bedParts = {}
local function bedSource(name, pos)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.CFrame = CFrame.new(pos)
	p.Parent = Ambience.fxFolder
	table.insert(bedParts, p)
	return p
end

local function startBed()
	-- air handling: the wind loop slowed right down is a low ventilation rumble from the ducts
	local wind = Config.BuiltinSounds and Config.BuiltinSounds.Falling or "rbxasset://sounds/action_falling.ogg"
	for _, pos in ipairs({ Vector3.new(-45, 25, -40), Vector3.new(45, 25, 40) }) do
		local snd = GymSound.Loop(bedSource("HVAC", pos), wind, 0.035, 0.45, "GymBed")
		if snd then
			snd.RollOffMaxDistance = 140
		end
	end
	local ambience = Config.SoundId and Config.SoundId("GymAmbience")
	if ambience then
		local snd = GymSound.Loop(bedSource("GymAmbience", Vector3.new(0, 8, -20)), ambience, 0.35, 1, "GymBed")
		if snd then
			snd.RollOffMaxDistance = 160
		end
	end
	local music = Config.SoundId and Config.SoundId("GymMusic")
	if music then
		-- the wall speakers in the hall play the gym's music
		for _, pos in ipairs({ Vector3.new(-37, 21.5, -78), Vector3.new(37, 21.5, -78), Vector3.new(-66, 21, 78), Vector3.new(66, 21, 78) }) do
			local snd = GymSound.Loop(bedSource("GymMusic", pos), music, 0.18, 1, "GymBed")
			if snd then
				snd.RollOffMaxDistance = 120
			end
		end
	end
end

-- members' training noises, timed to what they are visibly doing
local MEMBER_SOUNDS = {
	["Leon Price"] = { name = "footfall", every = 0.38, vol = 0.7 }, -- treadmill strides
	["Tasha Brooks"] = { name = "ropetick", every = 0.45, vol = 0.8, also = "footfall", alsoVol = 0.25 },
	["Hank Duro"] = { name = "plate", every = 2.6, vol = 0.8, jitter = 0.6 }, -- bench reps
	["Andre Cole"] = { name = "rack", every = 2.3, vol = 0.6, jitter = 0.5 }, -- dumbbells touching
	["Marco Silva"] = { name = "whoosh", every = 0.7, vol = 1, jitter = 0.5 }, -- shadow-boxing
	["Sofia Marin"] = { name = "footfall", every = 0.55, vol = 0.25 },
}
local memberNext = {}
local EVENT_NEAR = 75

local function updateMemberSounds(cam, now)
	local members = workspace:FindFirstChild("GymMembers")
	if not members then
		return
	end
	for name, def in pairs(MEMBER_SOUNDS) do
		local m = members:FindFirstChild(name)
		local root = m and m:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - cam).Magnitude < EVENT_NEAR then
			local at = memberNext[name] or 0
			if now >= at then
				memberNext[name] = now + def.every + (def.jitter or 0.05) * math.random()
				GymSound.Play(def.name, root.Position - Vector3.new(0, 2, 0), { volume = def.vol })
				if def.also and math.random() < 0.5 then
					GymSound.Play(def.also, root.Position - Vector3.new(0, 3, 0), { volume = def.alsoVol })
				end
			end
		end
	end
end

-- now and then: a dropped dumbbell, a rack clank or a grunt somewhere in the hall
local nextRandomAt = 0
local function updateRandomNoises(cam, now)
	if now < nextRandomAt or not inHall(cam) then
		return
	end
	nextRandomAt = now + 4 + math.random() * 6
	local pick = math.random()
	local pos
	if pick < 0.45 then
		pos = Vector3.new(-80 + math.random(-20, 20), 2, -30 + math.random(-30, 30))
		GymSound.Play(math.random() < 0.5 and "plate" or "rack", pos, { volume = 0.9 })
	elseif pick < 0.7 then
		pos = Vector3.new(math.random(-40, 40), 2, math.random(-60, -10))
		GymSound.Play("grunt", pos, { volume = 0.7, speed = 0.9 + math.random() * 0.25 })
	else
		pos = Vector3.new(-80 + math.random(-15, 15), 1, -30 + math.random(-25, 25))
		GymSound.Play("drop", pos, { volume = 0.8 })
	end
end

------------------------------------------------------------------------
-- Coaches: they shout, react to your work and watch you train
------------------------------------------------------------------------
local COACHES = { "Coach Ray", "Old Pete", "Coach Benny", "Coach Dre", "Sal Romano" }
local LINES = {
	general = {
		"Hands up! Chin down!", "Breathe out on every shot!", "Turn that hip over!", "Snap it back to your face!",
		"Move your head after you punch!", "Double up the jab!", "Stay on the balls of your feet!", "Sit down on your punches!",
		"Work the body, the head will come!", "Don't stop now - finish the round!", "Feet under you, stay balanced!", "Eyes up, always!",
	},
	["Old Pete"] = { "Forty years I've run this gym. Keep going!", "Champions are built when nobody's watching.", "Back in my day we trained with no gloves!", "That's it, kid. That's it." },
	["Coach Ray"] = { "That's how champions train!", "Tighter! Tighter!", "Use your legs, not just your arms!", "Another round. You've got another round." },
	["Coach Dre"] = { "Jay! Jab, then move!", "Kofi, work the body!", "Cut the ring off!", "Don't lean on the ropes!", "Throw in combinations!" },
	["Sal Romano"] = { "Stay off the ropes!", "Keep that guard up, you're bleeding points!", "Breathe! Use the rest!" },
	["Coach Benny"] = { "Pads are up, who's next?", "Sharp and snappy!", "Hit the target, not the air!" },
	good = { "THAT'S IT!", "Beautiful!", "Yes! Again!", "Now you're punching!", "That's championship stuff!", "Perfect - do it again!" },
	bad = { "Sloppy! Reset!", "Too slow! Snap it!", "Concentrate!", "Tighten it up!", "Don't drop your hands!", "Come on, you're better than that!" },
}
local lastShout = {}
local nextChatterAt = os.clock() + 6

local function coachModel(name)
	local members = workspace:FindFirstChild("GymMembers")
	return members and members:FindFirstChild(name)
end

local function say(model, text)
	local head = model and model:FindFirstChild("Head")
	if not head or not text then
		return false
	end
	lastShout[model.Name] = os.clock()
	pcall(function()
		TextChatService:DisplayBubble(head, text)
	end)
	GymSound.Play("shout", head.Position, { volume = 1 }) -- silent unless a CoachShout upload is set
	return true
end

local function pickLine(list)
	return list and list[math.random(1, #list)]
end

-- a coach near YOU reacts to your work: kind = "good" | "bad" | "bell" | anything (generic).
-- text = the exact line (nil -> one picked for the kind). Returns true if somebody shouted.
function Ambience.React(text, kind)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	local from = (root and root.Position) or (cam and cam.CFrame.Position)
	if not from then
		return false
	end
	local best, bestD
	for _, name in ipairs(COACHES) do
		local m = coachModel(name)
		local head = m and m:FindFirstChild("Head")
		-- the mitt coach is busy calling your combos when his pads are up
		local busy = m and m:GetAttribute("Loop") == "mitts"
		if head and not busy and os.clock() - (lastShout[name] or 0) > 1.2 then
			local d = (head.Position - from).Magnitude
			if d < 45 and (not bestD or d < bestD) then
				best, bestD = m, d
			end
		end
	end
	if not best then
		return false
	end
	local line = text or pickLine(LINES[kind]) or pickLine(LINES.general)
	task.delay(0.12 + math.random() * 0.18, function()
		if best.Parent then
			say(best, line)
		end
	end)
	return true
end

-- every 8-15 s a coach in earshot shouts something fitting
local function updateChatter(cam, now)
	if now < nextChatterAt then
		return
	end
	nextChatterAt = now + 8 + math.random() * 7
	local options = {}
	for _, name in ipairs(COACHES) do
		local m = coachModel(name)
		local head = m and m:FindFirstChild("Head")
		if head and m:GetAttribute("Loop") ~= "mitts" and (head.Position - cam).Magnitude < 60 and now - (lastShout[name] or 0) > 6 then
			table.insert(options, m)
		end
	end
	if #options == 0 then
		return
	end
	local m = options[math.random(1, #options)]
	local own = LINES[m.Name]
	say(m, (own and math.random() < 0.55) and pickLine(own) or pickLine(LINES.general))
end

-- coaches turn to watch you while you train near them (client-local LookAt, Animator reads it)
local WATCHERS = { "Coach Ray", "Old Pete", "Coach Dre" }
local function updateLookAt()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local training = char and (char:GetAttribute("Pose") ~= nil or CollectionService:HasTag(char, "Trainee"))
	for _, name in ipairs(WATCHERS) do
		local m = coachModel(name)
		local mr = m and m:FindFirstChild("HumanoidRootPart")
		if mr then
			local want = nil
			if training and root and (root.Position - mr.Position).Magnitude < 30 then
				want = root.Position + Vector3.new(0, 1.5, 0)
			end
			local cur = m:GetAttribute("LookAt")
			if want == nil then
				if cur ~= nil then
					m:SetAttribute("LookAt", nil)
				end
			elseif typeof(cur) ~= "Vector3" or (cur - want).Magnitude > 0.5 then
				m:SetAttribute("LookAt", want)
			end
		end
	end
end

------------------------------------------------------------------------
-- Dust motes hanging in the air (catch the light: LightInfluence 1)
------------------------------------------------------------------------
local DUST_ZONES = {
	{ "Boxing", -45, -70, 45, 4 }, { "Weights", -108, -78, -50, 18 }, { "Cardio", 50, -78, 108, 18 },
	{ "Recovery", 50, 22, 108, 78 }, { "Services", -108, 22, -50, 78 }, { "Lobby", -45, 4, 45, 78 },
	{ "Wing", 112, 31, 152, 65, true }, -- 6th field: a clean room (fewer motes)
}
local DUST_RATE = { 7, 4.5, 2.2, 2.6 } -- per 6000 square studs, by facility tier (old gyms are dusty)
local dust = {}

local function buildDust()
	for _, z in ipairs(DUST_ZONES) do
		local w, d = z[4] - z[2], z[5] - z[3]
		local p = Instance.new("Part")
		p.Name = "Dust" .. z[1]
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(w, 18, d)
		p.CFrame = CFrame.new((z[2] + z[4]) / 2, 11, (z[3] + z[5]) / 2)
		p.Parent = Ambience.fxFolder
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Motes"
		pe.Enabled = false
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 244, 222))
		pe.LightInfluence = 1
		pe.LightEmission = 0.35
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.04), NumberSequenceKeypoint.new(0.5, 0.08), NumberSequenceKeypoint.new(1, 0.05) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(8, 14)
		pe.Speed = NumberRange.new(0.05, 0.2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -0.02, 0)
		pe.RotSpeed = NumberRange.new(-20, 20)
		pe.Drag = 0.5
		pcall(function()
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		end)
		pe.Parent = p
		table.insert(dust, { part = p, pe = pe, area = w * d, clean = z[6] == true, center = p.Position })
	end
end

local function updateDust(cam)
	for _, e in ipairs(dust) do
		local near = (Vector3.new(e.center.X, cam.Y, e.center.Z) - cam).Magnitude < 90 + math.max(e.part.Size.X, e.part.Size.Z) / 2
		e.pe.Enabled = near
		if near then
			local rate = (DUST_RATE[tier] or 4) * e.area / 6000 * (e.clean and 0.4 or 1)
			e.pe.Rate = rate
		end
	end
end

------------------------------------------------------------------------
-- Sun shafts through the windows and skylights
------------------------------------------------------------------------
local shafts = {} -- { glass, inward, beams = {b1, b2}, a0, a1, spot }
local WING_CENTER = Vector3.new(132, 10, 48)

local function addShaft(glass)
	if shafts[glass] then
		return
	end
	local inward
	if glass.Name == "SkylightGlass" then
		inward = Vector3.new(0, -1, 0)
	else
		-- the glass's thin axis, pointed into the building
		local s = glass.Size
		local axis = s.X <= s.Y and s.X <= s.Z and glass.CFrame.RightVector or (s.Z <= s.Y and glass.CFrame.LookVector or glass.CFrame.UpVector)
		local inWingShell = glass.Position.X > 110.5
		local center = inWingShell and WING_CENTER or Vector3.new(0, glass.Position.Y, 0)
		inward = axis * (axis:Dot(center - glass.Position) >= 0 and 1 or -1)
		inward = Vector3.new(inward.X, 0, inward.Z).Unit
	end
	local holder = Instance.new("Part")
	holder.Name = "Shaft"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(glass.Position)
	holder.Parent = Ambience.fxFolder
	local e = { glass = glass, inward = inward, holder = holder, beams = {}, atts = {} }
	local width = math.max(glass.Size.X, glass.Size.Z)
	for k = 1, 2 do
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = false
		b.Segments = 1
		b.Width0 = (glass.Name == "SkylightGlass" and math.min(glass.Size.X, glass.Size.Z) or width) * 0.9
		b.Width1 = b.Width0 * 1.25
		b.LightEmission = 0.6
		b.LightInfluence = 0
		b.Color = ColorSequence.new(Color3.fromRGB(255, 236, 200))
		b.Transparency = NumberSequence.new(1)
		b.Enabled = false
		b.Parent = holder
		e.beams[k] = b
		e.atts[k] = { a0, a1 }
	end
	shafts[glass] = e
end

local function scanWindows()
	local g = workspace:FindFirstChild("Gym")
	if not g then
		return
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "WindowGlass" or d.Name == "SkylightGlass") then
			addShaft(d)
		end
	end
end

-- place every shaft along the current sun direction (called when the time of day changes)
local function updateShafts(cam)
	local ok, sun = pcall(function()
		return Lighting:GetSunDirection()
	end)
	if not ok then
		return
	end
	local h = Lighting.ClockTime
	local day = h > 6.8 and h < 18.6 and sun.Y > 0.06
	-- strongest around midday, gone at dusk
	local strength = day and math.clamp(math.min(h - 6.8, 18.6 - h) / 2.5, 0, 1) or 0
	local spotsLeft = {}
	for glass, e in pairs(shafts) do
		if not glass.Parent then
			e.holder:Destroy()
			shafts[glass] = nil
		else
			local into = -sun:Dot(e.inward)
			local visible = day and into > 0.12 and (glass.Position - cam).Magnitude < 170
			for _, b in ipairs(e.beams) do
				b.Enabled = visible
			end
			if visible then
				local c = glass.Position + e.inward * 0.4
				local t = (c.Y - 0.6) / math.max(sun.Y, 0.05)
				t = math.min(t, 70)
				local finish = c - sun * t
				local dir = (finish - c).Unit
				local up = math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
				local base = CFrame.lookAt(Vector3.zero, dir, up)
				-- Attachment X axis along the shaft; the two ribbons are rolled 90 degrees apart
				local f0 = CFrame.fromMatrix(Vector3.zero, dir, base.UpVector)
				local f1 = CFrame.fromMatrix(Vector3.zero, dir, base.RightVector)
				e.holder.CFrame = CFrame.new(c)
				for k, pr in ipairs(e.atts) do
					local rot = k == 1 and f0 or f1
					pr[1].CFrame = rot
					pr[2].CFrame = rot + (finish - c)
				end
				local a = 1 - 0.13 * strength * math.clamp(into * 1.4, 0.3, 1)
				local seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.min(1, a)), NumberSequenceKeypoint.new(0.75, math.min(1, a + 0.04)), NumberSequenceKeypoint.new(1, 1) })
				for _, b in ipairs(e.beams) do
					b.Transparency = seq
				end
				table.insert(spotsLeft, { e = e, d = (glass.Position - cam).Magnitude, dir = dir, len = t })
			end
		end
	end
	-- a warm bounce light only on the shafts nearest the camera (Future lighting budget)
	table.sort(spotsLeft, function(p, q)
		return p.d < q.d
	end)
	for i, s in ipairs(spotsLeft) do
		local e = s.e
		if i <= 6 then
			if not e.spot then
				-- the light sits in its own little part, aimed down the shaft
				local sp = Instance.new("Part")
				sp.Name = "ShaftSpot"
				sp.Anchored, sp.CanCollide, sp.CanQuery, sp.CanTouch, sp.CastShadow = true, false, false, false, false
				sp.Transparency = 1
				sp.Size = Vector3.new(0.2, 0.2, 0.2)
				sp.Parent = e.holder
				e.spot = Instance.new("SpotLight")
				e.spot.Shadows = false
				e.spot.Angle = 35
				e.spot.Color = Color3.fromRGB(255, 226, 180)
				e.spot.Face = Enum.NormalId.Front
				e.spot.Parent = sp
			end
			e.spot.Parent.CFrame = CFrame.lookAt(e.holder.Position, e.holder.Position + s.dir)
			e.spot.Range = math.min(60, s.len + 6)
			e.spot.Brightness = 0.55 * strength
			e.spot.Enabled = true
		elseif e.spot then
			e.spot.Enabled = false
		end
	end
	for _, e in pairs(shafts) do
		if e.spot and not e.beams[1].Enabled then
			e.spot.Enabled = false
		end
	end
end

------------------------------------------------------------------------
-- Facility tier (from GymVisuals.Refresh): dust amounts and the hall's grade follow it
------------------------------------------------------------------------
function Ambience.SetTier(idx)
	tier = math.clamp(tonumber(idx) or 1, 1, 4)
end

------------------------------------------------------------------------
-- run one optional system; report its first error only (it runs 4 times a second)
local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not Ambience.warned then
		Ambience.warned = true
		warn("[Ambience]", err)
	end
end

function Ambience.Start()
	if Ambience.started then
		return
	end
	Ambience.started = true
	local fx = Instance.new("Folder")
	fx.Name = "GymAmbienceFX"
	fx.Parent = workspace
	Ambience.fxFolder = fx
	watch("SpinFan", addFan)
	watch("RoundTimer", addTimer)
	watch("TVTicker", addTicker)
	watch("NeonFlicker", addNeon, removeNeon)
	watch("LightZone", addZone, function(p)
		zones[p] = nil
	end)
	watch("NightLight", function(l)
		nightLights[l] = true
		applyLight(l, isNight == true)
	end, function(l)
		nightLights[l] = nil
	end)
	watch("NightLens", function(p)
		nightLenses[p] = true
		applyLens(p, isNight == true)
	end, function(p)
		nightLenses[p] = nil
	end)
	updateNight(true)
	-- optional systems: any of them failing must never stop the fans and clocks
	for _, fn in ipairs({ startBed, buildDust }) do
		local ok, err = pcall(fn)
		if not ok then
			warn("[Ambience]", err)
		end
	end
	task.spawn(function()
		-- windows: now, and again once the gym has finished building / streaming in
		for _ = 1, 3 do
			pcall(scanWindows)
			task.wait(4)
		end
	end)
	local shaftsDirty = true
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
		updateNight(false)
		shaftsDirty = true
	end)

	local acc, slowAcc, shaftAcc = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		slowAcc += dt
		shaftAcc += dt
		if acc < 1 / 30 then
			return
		end
		local step = math.min(acc, 0.1)
		acc = 0
		local cam = camPos()
		updateFans(step, cam)
		updateTickers(step, cam)
		if slowAcc >= 0.25 then
			local slowStep = slowAcc
			slowAcc = 0
			local now = os.clock()
			updateTimers(cam)
			updateNeons(cam)
			safe(updateGrade, slowStep, cam)
			safe(updateReverb, cam)
			safe(updateMemberSounds, cam, now)
			safe(updateRandomNoises, cam, now)
			safe(updateChatter, cam, now)
			safe(updateLookAt)
			safe(updateDust, cam)
		end
		-- shafts follow the sun: on a time-of-day change, and every few seconds for the camera cull
		if shaftsDirty or shaftAcc >= 3 then
			shaftsDirty = false
			shaftAcc = 0
			pcall(updateShafts, cam)
		end
	end)
end

return Ambience
