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
	return Vector3.new(0, 1.9 * s + 0.3, 0)
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
		AlwaysOnTop = false,
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
	gui.Parent = head
	local entry = { Gui = gui, Name = name, Mood = mood, Badge = badge, Activity = activity, Model = model, IsPlayer = isPlayer }
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
	for _, attr in ipairs({ "Activity", "Mood", "Expecting", "Team", "DisplayName", "Scale", "Chasing", "ChaseState" }) do
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
local PROMPT_COLORS = { Talk = C.Blue, Elevator = C.Teal, Crime = C.Red, Hide = C.Purple }
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
function World.ClearWaypoint()
	if waypoint then
		waypoint.Folder:Destroy()
		waypoint = nil
	end
end

function World.Waypoint(position, label, emoji, model)
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
	waypoint = { Folder = folder, Anchor = anchor, Beam = beam, Dist = dist, Model = model, Label = label, Pin = pin }
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
	if waypoint.Model then
		local r = waypoint.Model:FindFirstChild("HumanoidRootPart")
		if r then
			waypoint.Anchor.CFrame = CFrame.new(r.Position + Vector3.new(0, 1, 0))
		end
	end
	local d = (waypoint.Anchor.Position - root.Position).Magnitude
	waypoint.Dist.Text = math.floor(d) .. " studs"
	waypoint.Pin.Position = UDim2.fromOffset(0, math.sin(os.clock() * 4) * 3)
	if d < 12 then
		ctx.Hud.Toast("✅", "You made it!", waypoint.Label or "", C.Green)
		World.ClearWaypoint()
	end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------
function World.Hit(position, damage, ko)
	local anchor = UI.new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(position), Parent = workspace })
	local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(220, 60), AlwaysOnTop = true, LightInfluence = 0, Adornee = anchor, Parent = anchor })
	local label = UI.text(gui, if ko then "💫 KNOCKED OUT!" else "💥 -" .. tostring(damage), if ko then 24 else 22, UI.Black, if ko then C.Gold else C.Red, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
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
local punchTrack
local lastPunch = 0
function World.Punch()
	if os.clock() - lastPunch < 0.5 then
		return
	end
	lastPunch = os.clock()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if not punchTrack or punchTrack.Parent == nil then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://522635514"
			local ok, track = pcall(animator.LoadAnimation, animator, anim)
			punchTrack = ok and track or nil
		end
	end
	if punchTrack then
		punchTrack:Play(0.05, 1, 1.6)
	end
	UI.sound("punch", 0.4, 1.3)
	task.spawn(function()
		local ok, result = pcall(function()
			return ctx.Remotes.Request:InvokeServer({ Action = "Punch" })
		end)
		if ok and result and result.Hit then
			World.Shake(if result.KO then 0.9 else 0.4, 0.25)
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
		end
	end)
end

return World
