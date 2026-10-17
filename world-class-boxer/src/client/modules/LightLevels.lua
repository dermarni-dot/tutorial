-- LightLevels: the game's exposure targets in one place, plus the player's brightness preference.
--   LightLevels.User()            the brightness preference, 0.5 .. 1.6 (1 = as designed)
--   LightLevels.UserExposure()    that preference as an ExposureCompensation offset (stops)
--   LightLevels.Zone(name)        the base exposure for a place (Ambience adds the user offset)
--   LightLevels.OnChanged(fn)     fn() when the preference changes
--   LightLevels.PostAllowed(e)    false when the Graphics level leaves this post effect (or class name) out
--   LightLevels.StartPostGate()   once (CharacterLight.Start): keeps every post effect under Lighting / the camera
--                                 to PostAllowed, whoever made it
-- The preference is read from the client attribute "Brightness" on the LocalPlayer (Settings sets it
-- when it has a brightness slider: Settings key "brightness", default 1), else Settings.Values.brightness.
-- Every module that writes Lighting.ExposureCompensation (Ambience out of fights, VenueFX in them) adds
-- UserExposure(), so one slider brightens the gym, the city and every venue alike.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer

local LightLevels = {}

-- base ExposureCompensation per place (the scene's lights do the shaping; this only sets the level)
LightLevels.Zones = {
	GymWarm = 0.18, -- the main hall: warm lamps, a touch of lift so faces read at mid grey
	GymElite = 0.1,
	Barbershop = 0.12,
	Apartment = 0.15,
	Store = 0.08,
	Mansion = 0.1,
	Street = 0,
	Outside = 0,
}
LightLevels.NightOutside = 0.35 -- after dark the street lights carry the city: lift the picture

local settingsMod
local function settingsValue()
	if settingsMod == nil then
		settingsMod = false
		local m = script.Parent:FindFirstChild("Settings")
		if m then
			local ok, s = pcall(require, m)
			if ok and type(s) == "table" then
				settingsMod = s
			end
		end
	end
	local v = settingsMod and type(settingsMod.Values) == "table" and settingsMod.Values.brightness
	return tonumber(v)
end

local function normalise(v)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	-- a percent slider (50 .. 160) works as well as a factor (0.5 .. 1.6)
	if v > 4 then
		v /= 100
	end
	return math.clamp(v, 0.5, 1.6)
end

function LightLevels.User()
	return normalise(player:GetAttribute("Brightness")) or normalise(settingsValue()) or 1
end

-- one stop brighter at 1.6, about one stop darker at 0.5
function LightLevels.UserExposure()
	return math.clamp(math.log(LightLevels.User()) / math.log(2), -1, 0.7)
end

function LightLevels.Zone(name)
	return LightLevels.Zones[name] or 0
end

function LightLevels.OnChanged(fn)
	return player:GetAttributeChangedSignal("Brightness"):Connect(fn)
end

------------------------------------------------------------------------
-- Post effects per Graphics level (the client attribute GfxLevel that Perf publishes: 1 Low, 2 Medium, 3 High)
------------------------------------------------------------------------
-- the lowest level that still draws each costly full-screen pass. Depth of field (a multi-pass blur: the main
-- menu's backdrop, the walkout's focus) goes first, at Medium; bloom and sun rays at Low. The colour grades
-- (ColorCorrection: the look of every place), Blur (menu backdrops, a concussion: gameplay information) and the
-- Atmosphere stay at every level.
LightLevels.PostMin = { DepthOfFieldEffect = 3, BloomEffect = 2, SunRaysEffect = 2 }

local function gfxLevel()
	return math.clamp(tonumber(player:GetAttribute("GfxLevel")) or 3, 1, 3)
end

function LightLevels.PostAllowed(e)
	local class = typeof(e) == "Instance" and e.ClassName or e
	local need = LightLevels.PostMin[class]
	return need == nil or gfxLevel() >= need
end

-- The gate: an effect a lower level leaves out is switched off where it stands, whoever made it (the server's
-- GymBloom / GymSunRays, VenueFX's, the main menu's), and switched back on when the level allows it again - only
-- the ones the gate itself switched off (forced), so an owner's own choice is never undone. An owner that turns a
-- left-out effect on (VenueFX's walkout focus every frame, a fight restoring the gym's look) is switched off again
-- at once. The gym's own effects are put back only outside fight nights (VenueFX / FightClient switch them off for
-- a venue and restore them afterwards: a level change in between waits for the fight to end).
local gate = nil
local function inFight()
	return player:GetAttribute("InFight") == true or workspace:FindFirstChild("VenueFX_Local") ~= nil
end
local function gateApply(e, g)
	if not e.Parent then
		return
	end
	if LightLevels.PostAllowed(e) then
		if g.forced and not (inFight() and string.sub(e.Name, 1, 3) == "Gym") then
			g.forced = false
			e.Enabled = true
		end
	elseif e.Enabled then
		g.forced = true
		e.Enabled = false
	end
end
local function gateWatch(e)
	if not (e:IsA("PostEffect") and LightLevels.PostMin[e.ClassName]) or gate.watched[e] then
		return
	end
	local g = { forced = false }
	gate.watched[e] = g
	g.conn = e:GetPropertyChangedSignal("Enabled"):Connect(function()
		if e.Enabled and not LightLevels.PostAllowed(e) then
			g.forced = true
			e.Enabled = false
		elseif e.Enabled then
			g.forced = false -- the owner has it on again: nothing of ours to put back
		end
	end)
	g.anc = e.AncestryChanged:Connect(function()
		local p = e.Parent
		if p ~= Lighting and not (p and p:IsA("Camera")) then
			g.conn:Disconnect()
			g.anc:Disconnect()
			gate.watched[e] = nil
		end
	end)
	gateApply(e, g)
end
local function gateAll()
	for e, g in pairs(gate.watched) do
		gateApply(e, g)
	end
end
local function gateCamera(cam)
	if gate.camConn then
		gate.camConn:Disconnect()
		gate.camConn = nil
	end
	if cam then
		gate.camConn = cam.ChildAdded:Connect(gateWatch)
		for _, c in ipairs(cam:GetChildren()) do
			gateWatch(c)
		end
	end
end

function LightLevels.StartPostGate()
	if gate then
		return
	end
	gate = { watched = {} }
	Lighting.ChildAdded:Connect(gateWatch)
	for _, c in ipairs(Lighting:GetChildren()) do
		gateWatch(c)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		gateCamera(workspace.CurrentCamera)
	end)
	gateCamera(workspace.CurrentCamera)
	player:GetAttributeChangedSignal("GfxLevel"):Connect(gateAll)
	-- a fight night over: the gym's effects VenueFX / FightClient restored get the level's say again
	player:GetAttributeChangedSignal("InFight"):Connect(function()
		task.delay(2, gateAll)
	end)
	workspace.ChildRemoved:Connect(function(c)
		if c.Name == "VenueFX_Local" then
			task.delay(2, gateAll)
		end
	end)
end

return LightLevels
