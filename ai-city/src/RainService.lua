-- RainService (ModuleScript) — ServerScriptService.Modules.RainService
-- Rain. On a 🌧️ rainy day (about one day in eight, see Atmosphere) it pours in
-- the morning (8:00-12:30) and again in the late afternoon (15:00-19:30), and
-- an overcast day can get a shower around 17:00. While it rains:
--   • workspace's "Raining" attribute is on, so every screen draws the rain,
--     darkens the sky and hands out umbrellas (see the client's Ambient and
--     Poses)
--   • people out walking hurry along, and plans to be somewhere outdoors (the
--     park, the beach, Funland, the plaza) turn into ducking into a café, the
--     mall, the library or the cinema until it passes (see CitizenService)
--   • when the first drops fall, a few people say so
-- Config.FORCE_RAIN = true makes it rain all the time (for testing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RainService = {}
local S

local LINES = { "Ugh, it's starting to rain!", "Oh no, I didn't bring an umbrella!", "Here comes the rain...", "Rain again? Seriously?", "Run for it!", "I love the smell of rain." }

function RainService.ShouldRain(weather, hour)
	if Config.FORCE_RAIN then
		return true
	end
	if weather == "Rainy" then
		return (hour >= 8 and hour < 12.5) or (hour >= 15 and hour < 19.5)
	elseif weather == "Overcast" then
		return hour >= 17 and hour < 18.25
	end
	return false
end

function RainService.IsRaining()
	return workspace:GetAttribute("Raining") == true
end

local function update()
	local state = ReplicatedStorage:FindFirstChild("CityState")
	local weather = state and state:GetAttribute("Weather") or "Fair"
	local raining = RainService.ShouldRain(weather, S.City.Hour())
	if raining == RainService.IsRaining() then
		return
	end
	workspace:SetAttribute("Raining", raining)
	if raining then
		S.City.News("🌧️ It's raining in AI City. Grab an umbrella!", "Weather", true)
		-- a few people out walking say something
		local said = 0
		for _, brain in ipairs(S.Citizens and S.Citizens.List or {}) do
			if said < 6 and brain.State == "walk" and not brain.Temp and math.random() < 0.15 then
				said += 1
				S.Citizens.Say(brain, LINES[math.random(1, #LINES)], "surprised", 3)
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			S.City.Toast(p, "🌧️", "It's raining", "People are hurrying for cover. Everyone outside has an umbrella up.", Color3.fromRGB(110, 150, 210))
		end
	else
		S.City.News("🌤️ The rain has stopped.", "Weather", true)
	end
end
RainService.Update = update

function RainService.Start(services)
	S = services
	task.spawn(function()
		while true do
			pcall(update)
			task.wait(2)
		end
	end)
end

return RainService
