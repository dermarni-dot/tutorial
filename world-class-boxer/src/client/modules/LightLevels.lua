-- LightLevels: the game's exposure targets in one place, plus the player's brightness preference.
--   LightLevels.User()            the brightness preference, 0.5 .. 1.6 (1 = as designed)
--   LightLevels.UserExposure()    that preference as an ExposureCompensation offset (stops)
--   LightLevels.Zone(name)        the base exposure for a place (Ambience adds the user offset)
--   LightLevels.OnChanged(fn)     fn() when the preference changes
-- The preference is read from the client attribute "Brightness" on the LocalPlayer (Settings sets it
-- when it has a brightness slider: Settings key "brightness", default 1), else Settings.Values.brightness.
-- Every module that writes Lighting.ExposureCompensation (Ambience out of fights, VenueFX in them) adds
-- UserExposure(), so one slider brightens the gym, the city and every venue alike.
local Players = game:GetService("Players")
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

return LightLevels
