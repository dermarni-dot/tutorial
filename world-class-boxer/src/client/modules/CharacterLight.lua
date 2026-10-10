-- CharacterLight: a camera-aware fill and rim light for the boxers on screen (client only).
-- Roblox lights the world, not the subject: under a ceiling lamp a face is lit from straight above
-- and the side toward the camera falls into shadow. Like a film set we add two small local lights
-- that follow the camera:
--   * fill: a soft, shadowless SpotLight between the camera and the boxer, a little to one side and
--     aimed at the chest, so the face and chest toward the camera always read (never a black
--     silhouette); a cone rather than a point so it does not drag a lit pool across the floor
--   * rim: a SpotLight behind and above the boxer, opposite the camera, aimed at the head and
--     shoulders, so hair, traps and delts get a bright edge that separates them from the room
-- Both are short-range (the room around barely changes) and cast no shadows (cheap under Future).
--   CharacterLight.Start()             once (Ambience.Start calls it)
--   CharacterLight.SetExtra(models)    extra subjects (VenueFX: the opponent in a fight); {} clears
--   CharacterLight.SetProfile(name)    "world" | "night" | "fight" | nil (nil = automatic)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local LightLevels = require(script.Parent:WaitForChild("LightLevels"))

local CharacterLight = {}
local player = Players.LocalPlayer

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- fill: brightness / range / colour; rim: brightness / range / angle / colour
local PROFILES = {
	world = { fill = 0.5, fillRange = 12, fillColor = rgb(255, 238, 220), rim = 1.5, rimRange = 13, rimAngle = 60, rimColor = rgb(255, 226, 188) },
	night = { fill = 0.65, fillRange = 12, fillColor = rgb(226, 232, 255), rim = 1.4, rimRange = 13, rimAngle = 60, rimColor = rgb(180, 205, 255) },
	-- in the ring the venue's angled key lights do the modelling: less fill, a stronger, cooler rim
	fight = { fill = 0.32, fillRange = 12, fillColor = rgb(255, 240, 226), rim = 2.2, rimRange = 14, rimAngle = 55, rimColor = rgb(210, 226, 255) },
}

local folder
local subjects = {} -- model -> entry
local extra = {}
local forced

local function lightPart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = folder
	return p
end

local function makeEntry()
	local e = { fillPart = lightPart("CharFill"), rimPart = lightPart("CharRim") }
	e.fill = Instance.new("SpotLight")
	e.fill.Shadows = false
	e.fill.Face = Enum.NormalId.Front
	e.fill.Angle = 52
	e.fill.Parent = e.fillPart
	e.rim = Instance.new("SpotLight")
	e.rim.Shadows = false
	e.rim.Face = Enum.NormalId.Front
	e.rim.Parent = e.rimPart
	return e
end

local function dropEntry(m)
	local e = subjects[m]
	if e then
		e.fillPart:Destroy()
		e.rimPart:Destroy()
		subjects[m] = nil
	end
end

local function isNight()
	local h = Lighting.ClockTime
	return h >= 18.2 or h < 6.2
end

local function profileNow()
	if forced and PROFILES[forced] then
		return PROFILES[forced]
	end
	if player:GetAttribute("InFight") == true or workspace:FindFirstChild("VenueFX_Local") then
		return PROFILES.fight
	end
	return isNight() and PROFILES.night or PROFILES.world
end

local UP = Vector3.new(0, 1, 0)
local function place(e, root, camPos, prof, user, rimOn)
	local r = root.Position
	local head = r + Vector3.new(0, 1.6, 0)
	local toCam = camPos - r
	toCam = Vector3.new(toCam.X, 0, toCam.Z)
	if toCam.Magnitude < 0.1 then
		toCam = -root.CFrame.LookVector
	end
	toCam = toCam.Unit
	local side = toCam:Cross(UP)
	-- fill: in front of the boxer on the camera side, a little high and to the left of the lens
	e.fillPart.CFrame = CFrame.lookAt(r + toCam * 5.5 + UP * 2.6 - side * 1.8, r + UP * 1.1)
	e.fill.Brightness = prof.fill * user
	e.fill.Range = prof.fillRange
	e.fill.Color = prof.fillColor
	e.fill.Enabled = true
	-- rim: behind and above, opposite the camera, a touch to the right
	if rimOn then
		local rp = r - toCam * 5 + UP * 5.2 + side * 2.2
		e.rimPart.CFrame = CFrame.lookAt(rp, head - UP * 0.4)
		e.rim.Brightness = prof.rim * math.sqrt(user)
		e.rim.Range = prof.rimRange
		e.rim.Angle = prof.rimAngle
		e.rim.Color = prof.rimColor
		e.rim.Enabled = true
	else
		e.rim.Enabled = false
	end
end

local function hide(e)
	e.fill.Enabled = false
	e.rim.Enabled = false
end

local wanted = {}
local function step()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	table.clear(wanted)
	local ch = player.Character
	if ch then
		wanted[ch] = true
	end
	for _, m in ipairs(extra) do
		if typeof(m) == "Instance" and m.Parent then
			wanted[m] = true
		end
	end
	for m in pairs(subjects) do
		if not wanted[m] or not m.Parent then
			dropEntry(m)
		end
	end
	local prof = profileNow()
	local user = LightLevels.User()
	local low = player:GetAttribute("GfxDetail") == "Low"
	for m in pairs(wanted) do
		local root = m:FindFirstChild("HumanoidRootPart")
		local hum = m:FindFirstChildOfClass("Humanoid")
		local e = subjects[m]
		if root and root:IsA("BasePart") and (not hum or hum.Health > 0) then
			if not e then
				e = makeEntry()
				subjects[m] = e
			end
			-- only when the boxer is on screen and close enough to matter
			local d = (root.Position - camPos).Magnitude
			if d < 70 then
				place(e, root, camPos, prof, user, not low)
			else
				hide(e)
			end
		elseif e then
			hide(e)
		end
	end
end

function CharacterLight.SetExtra(models)
	extra = type(models) == "table" and models or {}
end

function CharacterLight.SetProfile(name)
	forced = name
end

function CharacterLight.Start()
	if CharacterLight.started then
		return
	end
	CharacterLight.started = true
	folder = Instance.new("Folder")
	folder.Name = "CharacterLights"
	folder.Parent = workspace
	-- after the camera moved this frame, so the lights sit where the picture is taken from
	RunService:BindToRenderStep("BoxerCharacterLight", Enum.RenderPriority.Camera.Value + 2, function()
		local ok, err = pcall(step)
		if not ok and not CharacterLight.warned then
			CharacterLight.warned = true
			warn("[CharacterLight]", err)
		end
	end)
end

return CharacterLight
