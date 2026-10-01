-- World (ModuleScript) — StarterPlayerScripts.CityClient.World
-- Everything drawn in the 3D world: nameplates over citizens and players,
-- speech bubbles, the interaction prompts (talk, elevators, crimes), the
-- waypoint beam, hit effects, alarms, confetti, the sky and the traffic lights.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Atmosphere = require(Shared:WaitForChild("Atmosphere"))
local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.C

local World = {}
World.ShowPlates = true
local player = Players.LocalPlayer
local ctx

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------
local plates = {} -- [model] = { Gui, Name, Activity, Mood, Badge }

local function plateOffset(model)
	local s = model:GetAttribute("Scale") or 1
	return Vector3.new(0, 2.2 * s + 0.6, 0) -- (a little clear of the head)
end

local function makePlate(model, isPlayer)
	local head = model:FindFirstChild("Head") or model:WaitForChild("Head", 5)
	if not head or plates[model] then
		return
	end
	local gui = UI.new("BillboardGui", {
		Name = "CityPlate",
		Size = UDim2.fromOffset(240, 58),
		StudsOffset = plateOffset(model),
		MaxDistance = if isPlayer then 120 else 55,
		LightInfluence = 0,
		-- drawn on top so counters, shelves and ceilings never slice through it;
		-- a line-of-sight check (below) hides it when a wall is in the way
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		Adornee = head,
	})
	local nameRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Parent = gui })
	UI.list(nameRow, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local mood = UI.text(nameRow, "", 16, UI.Font, C.Text, { Size = UDim2.fromOffset(20, 22), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	local name = UI.text(nameRow, "", 17, UI.Bold, C.White, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), LayoutOrder = 2 })
	UI.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.6, Transparency = 0.3, Parent = name })
	local badge = UI.chip(nameRow, "", C.Pink, { LayoutOrder = 3, Visible = false, TextSize = 12, Size = UDim2.fromOffset(0, 20) })
	local activity = UI.text(gui, "", 13, UI.Font, Color3.fromRGB(235, 238, 250), { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.05 })
	UI.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 0.45, Parent = activity })
	-- a health bar when they're hurt
	local hpBack = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(90, 7), Visible = false, Parent = gui })
	UI.corner(hpBack, 3)
	local hpFill = UI.new("Frame", { BackgroundColor3 = C.Red, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = hpBack })
	UI.corner(hpFill, 3)
	-- tags shrink with distance (see declutter) so a crowd isn't a wall of text
	local scale = UI.new("UIScale", { Scale = 1, Parent = gui })
	gui.Parent = head
	local entry = { Gui = gui, Name = name, Mood = mood, Badge = badge, Activity = activity, Model = model, IsPlayer = isPlayer, Scale = scale }
	local function refreshHP()
		local hp, maxHp = model:GetAttribute("HP"), model:GetAttribute("MaxHP")
		if isPlayer then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			hp, maxHp = humanoid and humanoid.Health, humanoid and humanoid.MaxHealth
			if hp and maxHp and hp >= maxHp then
				hp = nil
			end
		end
		hpBack.Visible = hp ~= nil and maxHp ~= nil and hp > 0
		if hpBack.Visible then
			local f = math.clamp(hp / maxHp, 0, 1)
			UI.tween(hpFill, 0.2, { Size = UDim2.fromScale(f, 1) })
			hpFill.BackgroundColor3 = if f > 0.5 then C.Gold else C.Red
		end
	end
	model:GetAttributeChangedSignal("HP"):Connect(refreshHP)
	if isPlayer then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.HealthChanged:Connect(refreshHP)
		end
	end
	plates[model] = entry
	local function refresh()
		if isPlayer then
			local p = Players:GetPlayerFromCharacter(model)
			if not p then
				return
			end
			name.Text = p.DisplayName
			local title = p:GetAttribute("Title")
			local stars = p:GetAttribute("Wanted") or 0
			mood.Text = if title == "Mayor" then "🏛️" else "🙂"
			activity.Text = if stars > 0 then string.rep("⭐", stars) .. " WANTED" elseif title == "Mayor" then "Mayor of AI City" else ""
			activity.TextColor3 = if stars > 0 then C.Red else C.Gold
			badge.Visible = false
			return
		end
		name.Text = model:GetAttribute("DisplayName") or model.Name
		mood.Text = UI.moodEmoji(model:GetAttribute("Mood") or 60)
		activity.Text = model:GetAttribute("Activity") or ""
		local due = model:GetAttribute("Expecting") or -1
		local team = model:GetAttribute("Team")
		if due >= 0 then
			badge.Visible = true
			badge.Text = "🍼 " .. (if due == 0 then "due today!" elseif due == 1 then "1 day" else due .. " days")
			badge.BackgroundColor3 = C.Pink
		elseif team then
			badge.Visible = true
			badge.Text = if team == 1 then "⚽ Blue" else "⚽ Red"
			badge.BackgroundColor3 = if team == 1 then C.Blue else C.Red
		elseif model:GetAttribute("Jailed") then
			badge.Visible = true
			badge.Text = "🔒 IN JAIL"
			badge.BackgroundColor3 = C.Panel3
		elseif model:GetAttribute("Arrested") then
			badge.Visible = true
			badge.Text = "🚓 ARRESTED"
			badge.BackgroundColor3 = C.Blue
		elseif model:GetAttribute("Criminal") then
			badge.Visible = true
			badge.Text = "🦹 THIEF"
			badge.BackgroundColor3 = C.Red
		elseif model:GetAttribute("Fighting") or model:GetAttribute("Brawling") then
			badge.Visible = true
			badge.Text = "👊 FIGHTING"
			badge.BackgroundColor3 = C.Red
		elseif model:GetAttribute("Chasing") then
			badge.Visible = true
			local searching = model:GetAttribute("ChaseState") == "searching"
			badge.Text = if searching then "🔎 SEARCHING" else "🚨 CHASING"
			badge.BackgroundColor3 = if searching then C.Orange else C.Red
		else
			badge.Visible = false
		end
		gui.StudsOffset = plateOffset(model)
	end
	for _, attr in ipairs({ "Activity", "Mood", "Expecting", "Team", "DisplayName", "Scale", "Chasing", "ChaseState", "Fighting", "Brawling", "Watching", "Criminal", "Arrested", "Jailed" }) do
		model:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	if isPlayer then
		local p = Players:GetPlayerFromCharacter(model)
		if p then
			p:GetAttributeChangedSignal("Title"):Connect(refresh)
			p:GetAttributeChangedSignal("Wanted"):Connect(refresh)
		end
	end
	refresh()
	gui.Enabled = World.ShowPlates
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			plates[model] = nil
		end
	end)
end

function World.SetPlates(on)
	World.ShowPlates = on
	for _, entry in pairs(plates) do
		entry.Gui.Enabled = on
	end
end

-- Name tags never pile up: when two tags would cover each other on screen
-- (coworkers side by side at a counter, a crowd), only the nearer one shows.
-- And a tag only shows when you can actually see the person (not through walls).
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true
local function visible(camPos, target)
	local filter = { workspace:FindFirstChild("Citizens"), workspace:FindFirstChild("CityWaypoint") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	sightParams.FilterDescendantsInstances = filter
	local d = target - camPos
	local hit = workspace:Raycast(camPos, d, sightParams)
	-- see-through things (windows) don't count
	return hit == nil or (hit.Position - camPos).Magnitude > d.Magnitude - 1.5 or (hit.Instance and hit.Instance.Transparency > 0.3)
end
local function declutter()
	if not World.ShowPlates then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local list = {}
	for model, entry in pairs(plates) do
		local gui = entry.Gui
		local head = gui.Adornee
		if head and head.Parent then
			local world = head.Position + gui.StudsOffset
			local dist = (world - camPos).Magnitude
			if dist <= gui.MaxDistance then
				-- smaller further away; what they're doing only shows up close
				local sc = math.clamp(1.12 - dist / 70, 0.6, 1)
				if entry.Scale and math.abs(entry.Scale.Scale - sc) > 0.02 then
					entry.Scale.Scale = sc
				end
				entry.Activity.Visible = entry.IsPlayer or dist < 26
				local p, onScreen = camera:WorldToViewportPoint(world)
				if onScreen and p.Z > 0 then
					if visible(camPos, world) then
						local w = ((entry.Name.TextBounds and entry.Name.TextBounds.X) or 100) + 44
						local h = if entry.Activity.Visible and entry.Activity.Text ~= "" then 46 else 26
						table.insert(list, { Entry = entry, X = p.X, Y = p.Y, D = dist, W = w * sc, H = h * sc })
					else
						gui.Enabled = false
					end
				else
					gui.Enabled = true
				end
			else
				gui.Enabled = true
			end
		end
	end
	table.sort(list, function(a, b)
		return a.D < b.D
	end)
	local shown = {}
	for _, item in ipairs(list) do
		local free = true
		for _, other in ipairs(shown) do
			-- (boxes, with a little breathing room between them)
			if math.abs(item.X - other.X) < (item.W + other.W) / 2 + 8 and math.abs(item.Y - other.Y) < (item.H + other.H) / 2 + 6 then
				free = false
				break
			end
		end
		-- players' own tags always show
		if free or item.Entry.IsPlayer then
			table.insert(shown, item)
		end
		item.Entry.Gui.Enabled = free or item.Entry.IsPlayer
	end
end

--------------------------------------------------------------------------------
-- Speech bubbles
--------------------------------------------------------------------------------
local bubbles = {} -- [model] = gui
function World.Bubble(model, text, seconds, style)
	if not model or not model.Parent then
		return
	end
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = bubbles[model]
	if old then
		old:Destroy()
	end
	seconds = seconds or 3
	local s = model:GetAttribute("Scale") or 1
	local big = style == "speech"
	local gui = UI.new("BillboardGui", {
		Name = "CityBubble",
		Size = UDim2.fromOffset(if big then 360 else 250, 120),
		StudsOffset = Vector3.new(0, 1.9 * s + 3.2, 0),
		MaxDistance = if big then 220 else 90,
		LightInfluence = 0,
		AlwaysOnTop = big,
		Adornee = head,
	})
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local box = UI.new("Frame", {
		BackgroundColor3 = if big then C.Gold else C.White,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = holder,
	})
	UI.corner(box, 14)
	UI.pad(box, 8, 7, 12, 7, 12)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(if big then 350 else 240, 200), Parent = box })
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = C.Bg,
		Font = if big then UI.Bold else UI.Font,
		TextSize = if big then 17 else 15,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		RichText = false,
		Parent = box,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(if big then 326 else 216, 190), Parent = label })
	-- the little tail under the bubble
	local tail = UI.new("Frame", { BackgroundColor3 = box.BackgroundColor3, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -11), Size = UDim2.fromOffset(14, 14), Rotation = 45, BorderSizePixel = 0, Parent = holder })
	gui.Parent = head
	bubbles[model] = gui
	-- pop in and type the words out
	local scale = UI.new("UIScale", { Scale = 0.6, Parent = box })
	UI.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.spawn(function()
		local shown = 0
		local total = utf8.len(text) or #text
		while shown < total and gui.Parent do
			shown = math.min(total, shown + 2)
			local ok, cut = pcall(function()
				return string.sub(text, 1, (utf8.offset(text, shown + 1) or (#text + 1)) - 1)
			end)
			label.Text = if ok then cut else text
			task.wait(0.022)
		end
		label.Text = text
	end)
	task.delay(seconds, function()
		if bubbles[model] == gui then
			UI.tween(box, 0.3, { BackgroundTransparency = 1 })
			UI.tween(label, 0.3, { TextTransparency = 1 })
			UI.tween(tail, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.3)
			if bubbles[model] == gui then
				bubbles[model] = nil
			end
			gui:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Interaction prompts (our own look for Talk / Elevator / crime prompts)
--------------------------------------------------------------------------------
local PROMPT_COLORS = { Talk = C.Blue, Elevator = C.Teal, Crime = C.Red, Hide = C.Purple, Shop = C.Gold, Stop = C.Orange, Train = C.Green }
local promptGuis = {}

local function keyName(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return string.gsub(tostring(prompt.GamepadKeyCode), "Enum.KeyCode.Button", "")
	end
	return string.gsub(tostring(prompt.KeyboardKeyCode), "Enum.KeyCode.", "")
end

local function showPrompt(prompt, inputType)
	local kind = prompt:GetAttribute("Kind") or "Talk"
	local color = PROMPT_COLORS[kind] or C.Blue
	local adornee = prompt.Parent
	if not adornee then
		return
	end
	local gui = UI.new("BillboardGui", {
		Name = "CityPrompt",
		Size = UDim2.fromOffset(230, 56),
		StudsOffset = if kind == "Talk" then Vector3.new(0, -0.6, 0) elseif kind == "Crime" and adornee.Name == "HumanoidRootPart" then Vector3.new(0, -2, 0) else Vector3.new(0, 1.5, 0),
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Adornee = adornee,
		MaxDistance = 40,
	})
	local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, Size = UDim2.new(1, 0, 0, 46), Parent = gui })
	UI.corner(card, 12)
	UI.stroke(card, color, 1.5, 0.2)
	local key = UI.new("TextLabel", { BackgroundColor3 = color, Text = keyName(prompt, inputType), TextColor3 = C.White, Font = UI.Black, TextSize = 18, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(6, 6), Parent = card })
	UI.corner(key, 9)
	UI.text(card, prompt.ActionText, 16, UI.Bold, C.White, { Position = UDim2.fromOffset(48, 4), Size = UDim2.new(1, -54, 0, 20) })
	UI.text(card, prompt.ObjectText, 12, UI.Font, C.Sub, { Position = UDim2.fromOffset(48, 23), Size = UDim2.new(1, -54, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local barBack = UI.new("Frame", { BackgroundColor3 = C.Bg, Size = UDim2.new(1, -12, 0, 4), Position = UDim2.fromOffset(6, 50), Visible = prompt.HoldDuration > 0, Parent = gui })
	UI.corner(barBack, 2)
	local bar = UI.new("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(0, 1), Parent = barBack })
	UI.corner(bar, 2)
	local scale = UI.new("UIScale", { Scale = 0.7, Parent = card })
	UI.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	card.MouseButton1Down:Connect(function()
		prompt:InputHoldBegin()
	end)
	card.MouseButton1Up:Connect(function()
		prompt:InputHoldEnd()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	promptGuis[prompt] = { Gui = gui, Bar = bar }
end

local function hidePrompt(prompt)
	local entry = promptGuis[prompt]
	if entry then
		entry.Gui:Destroy()
		promptGuis[prompt] = nil
	end
end

--------------------------------------------------------------------------------
-- Waypoints
--------------------------------------------------------------------------------
local waypoint
-- citizenId: only clear the marker if it's following that citizen
function World.ClearWaypoint(citizenId)
	if waypoint and (citizenId == nil or waypoint.CitizenId == citizenId) then
		waypoint.Folder:Destroy()
		waypoint = nil
	end
end

-- a citizen's model, found by id (it may stream in after the message arrives)
local function citizenModel(id)
	local folder = workspace:FindFirstChild("Citizens")
	if not folder or id == nil then
		return nil
	end
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("CitizenId") == id then
			return m
		end
	end
	return nil
end

function World.Waypoint(position, label, emoji, model, citizenId)
	World.ClearWaypoint()
	local folder = Instance.new("Folder")
	folder.Name = "CityWaypoint"
	folder.Parent = workspace
	local anchor = UI.new("Part", { Name = "WaypointAnchor", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(position + Vector3.new(0, 3, 0)), Parent = folder })
	local a1 = Instance.new("Attachment")
	a1.Parent = anchor
	local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(200, 70), AlwaysOnTop = true, LightInfluence = 0, StudsOffset = Vector3.new(0, 3, 0), Adornee = anchor, Parent = folder })
	local pin = UI.text(gui, emoji or "📍", 30, UI.Font, C.White, { Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center })
	local text = UI.text(gui, label or "", 14, UI.Bold, C.White, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	UI.new("UIStroke", { Thickness = 1.5, Transparency = 0.3, Parent = text })
	local dist = UI.text(gui, "", 12, UI.Font, C.Gold, { Position = UDim2.fromOffset(0, 51), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	UI.new("UIStroke", { Thickness = 1.2, Transparency = 0.4, Parent = dist })
	local beam = UI.new("Beam", { Attachment1 = a1, Color = ColorSequence.new(C.Gold), Width0 = 0.35, Width1 = 0.35, FaceCamera = true, LightEmission = 1, Transparency = NumberSequence.new(0.35, 0.1), Segments = 1, Parent = folder })
	waypoint = { Folder = folder, Anchor = anchor, Beam = beam, Dist = dist, Model = model, Label = label, Pin = pin, CitizenId = citizenId, Since = os.clock() }
	ctx.Hud.Toast("🧭", "Waypoint set", (label or "") .. " — follow the golden line!", C.Gold)
end

local function updateWaypoint()
	if not waypoint then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local a0 = root:FindFirstChild("WaypointFrom")
	if not a0 then
		a0 = Instance.new("Attachment")
		a0.Name = "WaypointFrom"
		a0.Parent = root
	end
	waypoint.Beam.Attachment0 = a0
	if waypoint.CitizenId ~= nil then
		-- following someone: find their model if it wasn't streamed in yet
		if not (waypoint.Model and waypoint.Model.Parent) then
			waypoint.Model = citizenModel(waypoint.CitizenId)
		end
		if waypoint.Model then
			waypoint.Seen = os.clock()
		elseif os.clock() - (waypoint.Seen or waypoint.Since) > 8 then
			-- they're gone: don't leave a marker pointing at nothing
			ctx.Hud.Toast("❔", "Lost them", (waypoint.Label or "They") .. " is nowhere to be seen.", C.Gold)
			World.ClearWaypoint()
			return
		end
	end
	if waypoint.Model then
		local r = waypoint.Model:FindFirstChild("HumanoidRootPart")
		if r then
			waypoint.Anchor.CFrame = CFrame.new(r.Position + Vector3.new(0, 1, 0))
		end
	end
	local d = (waypoint.Anchor.Position - root.Position).Magnitude
	waypoint.Dist.Text = math.floor(d) .. " studs"
	waypoint.Pin.Position = UDim2.fromOffset(0, math.sin(os.clock() * 4) * 3)
	if d < 12 and waypoint.CitizenId == nil then
		ctx.Hud.Toast("✅", "You made it!", waypoint.Label or "", C.Green)
		World.ClearWaypoint()
	end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------
-- a gunshot: a flash at the muzzle, a streak to where the bullet went, a bang
local bang
-- a balloon popping: bits of rubber fly out
function World.Pop(pos, color)
	if typeof(pos) ~= "Vector3" then
		return
	end
	for k = 1, 6 do
		local bit = Instance.new("Part")
		bit.Name = "PopBit"
		bit.Size = Vector3.new(0.3, 0.3, 0.08)
		bit.Color = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 80, 100)
		bit.Anchored, bit.CanCollide, bit.CanQuery, bit.CanTouch = true, false, false, false
		local dir = Vector3.new(math.cos(k), math.sin(k * 2.3) * 0.6, math.sin(k))
		bit.CFrame = CFrame.new(pos)
		bit.Parent = workspace
		task.spawn(function()
			for i = 1, 8 do
				task.wait(0.03)
				if not bit.Parent then
					return
				end
				bit.CFrame = CFrame.new(pos + dir * i * 0.3 - Vector3.new(0, i * i * 0.01, 0)) * CFrame.Angles(i, i * 0.7, 0)
				bit.Transparency = i / 8
			end
			bit:Destroy()
		end)
	end
end

function World.Shot(from, to, weapon)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local heavy = weapon == "Shotgun"
	local d = to - from
	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored, tracer.CanCollide, tracer.CanQuery, tracer.CanTouch, tracer.CastShadow = true, false, false, false, false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 226, 150)
	tracer.Size = Vector3.new(if heavy then 0.14 else 0.08, if heavy then 0.14 else 0.08, math.max(0.1, d.Magnitude))
	tracer.CFrame = CFrame.lookAt(from + d / 2, to)
	tracer.Transparency = 0.2
	tracer.Parent = workspace
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = true, false, false, false, false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 90)
	flash.Size = Vector3.one * (if heavy then 1.2 else 0.7)
	flash.CFrame = CFrame.new(from + (if d.Magnitude > 0 then d.Unit * 1.4 else Vector3.zero))
	flash.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 14
	light.Brightness = 3
	light.Parent = flash
	task.delay(0.05, function()
		flash:Destroy()
	end)
	task.delay(0.08, function()
		tracer:Destroy()
	end)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - from).Magnitude < 260 then
		if not bang then
			bang = Instance.new("Sound")
			bang.Name = "Gunshot"
			bang.SoundId = "rbxasset://sounds/swordlunge.wav"
			bang.Parent = workspace
		end
		local s = bang:Clone()
		s.Volume = if heavy then 0.9 else 0.6
		s.PlaybackSpeed = if heavy then 0.35 else 0.55
		s.Parent = workspace
		pcall(function()
			s:Play()
		end)
		task.delay(1.5, function()
			s:Destroy()
		end)
		if (camera.CFrame.Position - from).Magnitude < 20 then
			World.Shake(if heavy then 0.5 else 0.25, 0.12)
		end
	end
end

-- where you're aiming a gun: the mouse (or the middle of the screen on a
-- controller or phone, and in first person)
local UIS = game:GetService("UserInputService")
local function aimDirection(root)
	local camera = workspace.CurrentCamera
	if not camera then
		return root.CFrame.LookVector
	end
	local ray
	local ok = pcall(function()
		local pad = ctx and ctx.Gamepad and ctx.Gamepad.Active()
		local touch = UIS.TouchEnabled and not UIS.MouseEnabled
		if pad or touch or UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then
			local vp = camera.ViewportSize
			ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		else
			local m = UIS:GetMouseLocation()
			ray = camera:ViewportPointToRay(m.X, m.Y)
		end
	end)
	if not ok or not ray then
		return camera.CFrame.LookVector
	end
	-- the point the ray reaches, then the direction to it from the gun
	local target = ray.Origin + ray.Direction * 150
	local from = root.Position + Vector3.new(0, 1.5, 0)
	local dir = target - from
	return if dir.Magnitude > 0.1 then dir.Unit else camera.CFrame.LookVector
end

function World.Hit(position, damage, ko, isPlayer, blocked, weapon)
	local anchor = UI.new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(position), Parent = workspace })
	local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(220, 60), AlwaysOnTop = true, LightInfluence = 0, Adornee = anchor, Parent = anchor })
	local icon = if weapon == "Knife" then "🔪" elseif weapon == "Bat" or weapon == "Hammer" then "💢" else "💥"
	local text = if ko then "💀 DOWN!" elseif blocked then "🛡️ -" .. tostring(damage) else icon .. " -" .. tostring(damage)
	local color = if ko then C.Gold elseif blocked then C.Blue elseif isPlayer then C.Pink else C.Red
	local label = UI.text(gui, text, if ko then 26 else 22, UI.Black, color, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	UI.new("UIStroke", { Thickness = 2, Transparency = 0.2, Parent = label })
	local scale = UI.new("UIScale", { Scale = 0.4, Parent = label })
	UI.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	UI.tween(gui, 1, { StudsOffset = Vector3.new(0, 3, 0) })
	task.delay(0.6, function()
		UI.tween(label, 0.4, { TextTransparency = 1 })
	end)
	task.delay(1.1, function()
		anchor:Destroy()
	end)
end

function World.Shake(power, seconds)
	local camera = workspace.CurrentCamera
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - start) / (seconds or 0.25)
		if k >= 1 then
			conn:Disconnect()
			return
		end
		local p = (power or 0.4) * (1 - k)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * p * 4), math.rad((math.random() - 0.5) * p * 4), 0)
	end)
end

function World.Alarm(position, seconds)
	local anchor = UI.new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(position + Vector3.new(0, 6, 0)), Parent = workspace })
	local light = UI.new("PointLight", { Range = 40, Brightness = 4, Color = C.Red, Parent = anchor })
	local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(80, 80), AlwaysOnTop = true, Adornee = anchor, Parent = anchor })
	local siren = UI.text(gui, "🚨", 48, UI.Font, C.White, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < (seconds or 10) do
			local red = math.floor((os.clock() - start) * 4) % 2 == 0
			light.Color = if red then C.Red else C.Blue
			siren.Rotation = if red then -8 else 8
			task.wait(0.12)
		end
		anchor:Destroy()
	end)
end

function World.Confetti(screen)
	local colors = { C.Gold, C.Pink, C.Blue, C.Green, C.Purple, C.Orange }
	for k = 1, 90 do
		local x = math.random()
		local spin = math.random(0, 360)
		local piece = UI.new("Frame", {
			BackgroundColor3 = colors[k % #colors + 1],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 16)),
			Position = UDim2.new(x, 0, -0.05, -math.random(0, 200)),
			Rotation = spin,
			ZIndex = 50,
			Parent = screen,
		})
		local t = math.random(25, 45) / 10
		UI.tween(piece, t, { Position = UDim2.new(x + (math.random() - 0.5) * 0.2, 0, 1.05, 0), Rotation = spin + math.random(-540, 540) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(t, function()
			piece:Destroy()
		end)
	end
end

-- a quick fade to black and back (elevators)
function World.Fade(screen, seconds)
	local cover = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = screen })
	local ding = UI.text(cover, "🛗 Ding!", 28, UI.Title, C.White, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, ZIndex = 61 })
	UI.tween(cover, 0.3, { BackgroundTransparency = 0 })
	UI.tween(ding, 0.3, { TextTransparency = 0 })
	task.delay((seconds or 0.9) - 0.35, function()
		UI.tween(cover, 0.35, { BackgroundTransparency = 1 })
		UI.tween(ding, 0.35, { TextTransparency = 1 })
		task.wait(0.4)
		cover:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Punching
--------------------------------------------------------------------------------
local Weapons = require(Shared:WaitForChild("Weapons"))
local lastAttack = 0
local fistSide = false

-- which weapon you're holding ("Fists" if none)
-- fishing (see FishingService): cast, then click again when the bobber dips
local function holdingRod()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("Rod") == true
end
local lastFish = 0
function World.Fish()
	if os.clock() - lastFish < 0.35 then
		return
	end
	lastFish = os.clock()
	local character = player.Character
	if character and not character:GetAttribute("Fishing") then
		character:SetAttribute("Casting", os.clock()) -- (the swing starts right away on our screen)
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return ctx.Remotes.Request:InvokeServer({ Action = "Fish" })
		end)
		if ok and result and result.Caught then
			World.Shake(0.3, 0.2)
			UI.sound("splash", 0.5, 1.3)
			UI.sound("coin", 0.5, 1)
		elseif ok and result and result.Cast then
			task.delay(0.55, function()
				UI.sound("splash", 0.4, 1.1)
			end)
		end
	end)
end

-- "BITE!" in big letters for a moment: click now!
local biteLabel
function World.FishBite(position)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	if not biteLabel then
		local screen = Instance.new("ScreenGui")
		screen.Name = "FishBite"
		screen.ResetOnSpawn = false
		screen.Parent = gui
		biteLabel = Instance.new("TextLabel")
		biteLabel.BackgroundTransparency = 1
		biteLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		biteLabel.Position = UDim2.fromScale(0.5, 0.35)
		biteLabel.Size = UDim2.fromOffset(420, 90)
		biteLabel.Font = Enum.Font.FredokaOne
		biteLabel.TextScaled = true
		biteLabel.TextColor3 = Color3.fromRGB(255, 230, 80)
		biteLabel.TextStrokeTransparency = 0
		biteLabel.TextStrokeColor3 = Color3.fromRGB(120, 40, 20)
		biteLabel.Parent = screen
	end
	local pad = ctx.Gamepad and ctx.Gamepad.Active()
	biteLabel.Text = "❗ BITE! " .. (if pad then "Press R2!" elseif UIS.TouchEnabled and not UIS.MouseEnabled then "Tap!" else "Click!")
	biteLabel.Visible = true
	UI.sound("click", 0.6, 1.6)
	local token = os.clock()
	biteLabel:SetAttribute("Token", token)
	task.delay(1.3, function()
		if biteLabel and biteLabel:GetAttribute("Token") == token then
			biteLabel.Visible = false
		end
	end)
end

function World.Equipped()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and tool:GetAttribute("Weapon") or "Fists"
end

-- Attack with whatever you're holding (F, click with a weapon, or the button)
function World.Attack()
	if holdingRod() then
		World.Fish()
		return
	end
	local weapon = World.Equipped()
	local w = Weapons.Get(weapon)
	if os.clock() - lastAttack < w.Cooldown then
		return
	end
	lastAttack = os.clock()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or player:GetAttribute("Hiding") then
		return
	end
	-- the swing plays right away on our screen (jabs alternate left and right;
	-- the server sets the same attributes so everyone else sees it too)
	character:SetAttribute("SwingSide", (character:GetAttribute("SwingSide") or 0) + 1)
	character:SetAttribute("SwingWeapon", weapon)
	character:SetAttribute("Swing", os.clock())
	if not w.Ranged then
		UI.sound("punch", 0.4, if weapon == "Knife" then 1.6 elseif weapon == "Fists" then 1.3 else 0.9)
	end
	-- guns: turn to face where you're aiming, and send the aim
	local aim
	if w.Ranged then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			aim = aimDirection(root)
			local flat = Vector3.new(aim.X, 0, aim.Z)
			if flat.Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			end
		end
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return ctx.Remotes.Request:InvokeServer({ Action = "Attack", Aim = aim })
		end)
		if ok and result and result.Hit then
			World.Shake(if result.KO then 0.9 elseif weapon == "Fists" then 0.35 else 0.55, 0.25)
			if ctx.Gamepad then
				ctx.Gamepad.Rumble(if result.KO then 0.9 else 0.4, if result.KO then 0.3 else 0.12)
			end
		end
	end)
end
World.Punch = World.Attack

-- how much of the current weapon's cooldown is left (0..1), for the hotbar
function World.Cooldown()
	local id = World.Equipped()
	local w = Weapons.Get(id)
	return { Id = id, Left = math.clamp(1 - (os.clock() - lastAttack) / w.Cooldown, 0, 1) }
end

local blockingNow = false
function World.SetBlock(on)
	if on == blockingNow then
		return
	end
	blockingNow = on
	if player.Character then
		player.Character:SetAttribute("Blocking", if on then true else nil)
	end
	task.spawn(function()
		pcall(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Block", On = on })
		end)
	end)
end

-- clicking with a weapon in hand attacks
local function watchTools(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("Rod") then
			child.Activated:Connect(World.Fish)
			ctx.Hud.Toast("🎣", "Fishing rod", "Face the water and click (or F) to cast. When the bobber dips, click fast!", C.Blue or C.Gold)
		elseif child:IsA("Tool") and child:GetAttribute("Weapon") then
			child.Activated:Connect(World.Attack)
			local w = Weapons.Get(child:GetAttribute("Weapon"))
			ctx.Hud.Toast(w.Emoji, w.Name .. " equipped", "Click (or F) to attack. Hold X to block.", C.Red)
		end
	end)
end

--------------------------------------------------------------------------------
-- The sky and the traffic lights
--------------------------------------------------------------------------------
local LAMP_ON = { Red = Color3.fromRGB(255, 60, 50), Yellow = Color3.fromRGB(255, 200, 40), Green = Color3.fromRGB(60, 240, 110) }
local function trafficTick()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local t = workspace:GetServerTimeNow() % 16
	for _, model in ipairs(CollectionService:GetTagged("TrafficLight")) do
		local pivot = model:GetPivot().Position
		if (pivot - camPos).Magnitude < 350 then
			local axis = model:GetAttribute("Axis") or "X"
			local phase = if axis == "X" then t else (t + 8) % 16
			local state = if phase < 6 then "Green" elseif phase < 8 then "Yellow" else "Red"
			-- the walk signal: walk while this traffic is green and there's time to
			-- cross, then a flashing hand, then a steady hand
			local walkOn = phase < 4.5
			local flash = phase >= 4.5 and phase < 6.5 and (t * 2) % 1 < 0.5
			for _, lamp in ipairs(model:GetChildren()) do
				if lamp.Name == "WalkSignal" then
					lamp.Material = if walkOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
					lamp.Color = if walkOn then Color3.fromRGB(240, 245, 255) else Color3.fromRGB(50, 50, 55)
				elseif lamp.Name == "DontWalkSignal" then
					local on = not walkOn and (phase >= 6.5 or flash)
					lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
					lamp.Color = if on then Color3.fromRGB(255, 140, 40) else Color3.fromRGB(50, 50, 55)
				end
			end
			for _, name in ipairs({ "Red", "Yellow", "Green" }) do
				for _, lamp in ipairs(model:GetChildren()) do
					if lamp.Name == name and lamp:IsA("BasePart") then
						local on = name == state
						lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
						lamp.Color = if on then LAMP_ON[name] else LAMP_ON[name]:Lerp(Color3.new(0.1, 0.1, 0.1), 0.8)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
function World.Start(context)
	-- job markers are only for whoever is on that shift (see JobService)
	local function jobMarker(d)
		if d.Name == "JobMarker" and d:IsA("BasePart") and d:GetAttribute("Owner") ~= player.UserId then
			d.LocalTransparencyModifier = 1
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("ProximityPrompt") or c:IsA("Light") then
					c.Enabled = false
				end
			end
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		task.defer(jobMarker, d)
	end)
	ctx = context
	for _, model in ipairs(CollectionService:GetTagged("Citizen")) do
		task.spawn(makePlate, model, false)
	end
	CollectionService:GetInstanceAddedSignal("Citizen"):Connect(function(model)
		task.spawn(makePlate, model, false)
	end)
	local function watchPlayer(p)
		if p == player then
			return
		end
		p.CharacterAdded:Connect(function(character)
			task.spawn(makePlate, character, true)
		end)
		if p.Character then
			task.spawn(makePlate, p.Character, true)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	player.CharacterAdded:Connect(watchTools)
	if player.Character then
		watchTools(player.Character)
	end
	ProximityPromptService.PromptShown:Connect(showPrompt)
	ProximityPromptService.PromptHidden:Connect(hidePrompt)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local entry = promptGuis[prompt]
		if entry then
			entry.Bar.Size = UDim2.fromScale(0, 1)
			UI.tween(entry.Bar, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local entry = promptGuis[prompt]
		if entry then
			UI.tween(entry.Bar, 0.15, { Size = UDim2.fromScale(0, 1) })
		end
	end)

	local slow = 0
	RunService.RenderStepped:Connect(function(dt)
		Atmosphere.Apply(Lighting, Lighting.ClockTime)
		updateWaypoint()
		slow += dt
		if slow >= 0.25 then
			slow = 0
			pcall(trafficTick)
			pcall(declutter)
		end
	end)
end

return World
