-- Ambience: brings the gym and the town to life on the client.
--  * SpinFan     - models whose "Hub"/"Blade" parts spin about the hub's local X (Speed attr, rad/s)
--  * RoundTimer  - gym round clocks run a shared 3:00 round / 1:00 rest cycle with their lamps
--  * TVTicker    - TV screens scroll their headline ticker
--  * NeonFlicker - neon signs flicker now and then
--  * NightLight / NightLens - street, shop and monument lights switch on at dusk
-- Everything is tag driven (CollectionService), so pieces streamed in later are picked up too.
-- Movers only update near the camera and at most ~30 times a second.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

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
		end
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
	local parts = {}
	if inst:IsA("BasePart") then
		parts = { inst }
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	if #parts == 0 then
		return
	end
	local base = {}
	for i, p in ipairs(parts) do
		base[i] = p.Transparency
	end
	neons[inst] = { parts = parts, base = base, pos = parts[1].Position, nextAt = os.clock() + 2 + math.random() * 10, busy = false }
end

local function flicker(e)
	e.busy = true
	task.spawn(function()
		local steps = math.random(3, 6)
		for s = 1, steps do
			local off = s % 2 == 1
			for i, p in ipairs(e.parts) do
				if p.Parent then
					p.Transparency = off and math.max(e.base[i], 0.85) or e.base[i]
				end
			end
			task.wait(0.04 + math.random() * 0.09)
		end
		for i, p in ipairs(e.parts) do
			if p.Parent then
				p.Transparency = e.base[i]
			end
		end
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
function Ambience.Start()
	if Ambience.started then
		return
	end
	Ambience.started = true
	watch("SpinFan", addFan)
	watch("RoundTimer", addTimer)
	watch("TVTicker", addTicker)
	watch("NeonFlicker", addNeon)
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
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
		updateNight(false)
	end)

	local acc, slowAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		slowAcc += dt
		if acc < 1 / 30 then
			return
		end
		local step = math.min(acc, 0.1)
		acc = 0
		local cam = camPos()
		updateFans(step, cam)
		updateTickers(step, cam)
		if slowAcc >= 0.25 then
			slowAcc = 0
			updateTimers(cam)
			updateNeons(cam)
		end
	end)
end

return Ambience
