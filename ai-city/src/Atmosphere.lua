-- Atmosphere (ModuleScript) — ReplicatedStorage.Shared.Atmosphere
-- The look of the sky and light through the day: soft pink dawns, bright
-- clear noons, golden evenings, purple dusks and deep blue nights.
-- The server calls Setup once; the client calls Apply every frame with the
-- current hour so the colors glide smoothly.

local Atmosphere = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Keyframes by hour. Everything between two keyframes is blended.
local KEYS = {
	{ Hour = 0, Ambient = rgb(92, 100, 136), Outdoor = rgb(112, 124, 168), Brightness = 1.6, Exposure = 0.3, AtmoColor = rgb(60, 74, 120), AtmoDecay = rgb(34, 40, 80), Density = 0.26, Haze = 0.8, Glare = 0, Tint = rgb(206, 216, 255), Saturation = -0.01, Contrast = 0.08, Bloom = 0.9, Rays = 0, Cloud = rgb(70, 76, 100) },
	{ Hour = 4.8, Ambient = rgb(94, 98, 136), Outdoor = rgb(114, 120, 166), Brightness = 1.6, Exposure = 0.28, AtmoColor = rgb(76, 82, 132), AtmoDecay = rgb(50, 46, 96), Density = 0.27, Haze = 0.95, Glare = 0, Tint = rgb(198, 206, 255), Saturation = 0.02, Contrast = 0.18, Bloom = 0.8, Rays = 0, Cloud = rgb(90, 90, 120) },
	{ Hour = 6.2, Ambient = rgb(64, 54, 62), Outdoor = rgb(89, 72, 77), Brightness = 1.04, Exposure = -0.2, AtmoColor = rgb(236, 170, 160), AtmoDecay = rgb(170, 110, 140), Density = 0.27, Haze = 1.1, Glare = 0.36, Tint = rgb(255, 226, 214), Saturation = 0.16, Contrast = 0.16, Bloom = 0.5, Rays = 0.14, Cloud = rgb(255, 196, 180) },
	{ Hour = 8, Ambient = rgb(70, 70, 74), Outdoor = rgb(84, 86, 92), Brightness = 1.52, Exposure = -0.3, AtmoColor = rgb(190, 212, 240), AtmoDecay = rgb(96, 136, 200), Density = 0.22, Haze = 0.61, Glare = 0.12, Tint = rgb(255, 248, 240), Saturation = 0.16, Contrast = 0.2, Bloom = 0.25, Rays = 0.06, Cloud = rgb(250, 250, 255) },
	{ Hour = 12.5, Ambient = rgb(72, 74, 78), Outdoor = rgb(87, 90, 97), Brightness = 1.76, Exposure = -0.37, AtmoColor = rgb(180, 210, 245), AtmoDecay = rgb(84, 128, 200), Density = 0.2, Haze = 0.44, Glare = 0.06, Tint = rgb(255, 252, 248), Saturation = 0.16, Contrast = 0.21, Bloom = 0.2, Rays = 0.04, Cloud = rgb(255, 255, 255) },
	{ Hour = 16.5, Ambient = rgb(75, 70, 65), Outdoor = rgb(90, 84, 79), Brightness = 1.6, Exposure = -0.32, AtmoColor = rgb(230, 204, 176), AtmoDecay = rgb(150, 132, 150), Density = 0.24, Haze = 0.83, Glare = 0.24, Tint = rgb(255, 240, 220), Saturation = 0.2, Contrast = 0.2, Bloom = 0.3, Rays = 0.1, Cloud = rgb(255, 238, 214) },
	{ Hour = 18.2, Ambient = rgb(77, 56, 54), Outdoor = rgb(105, 69, 61), Brightness = 1.2, Exposure = -0.24, AtmoColor = rgb(255, 150, 110), AtmoDecay = rgb(170, 90, 120), Density = 0.27, Haze = 1.32, Glare = 0.54, Tint = rgb(255, 214, 186), Saturation = 0.24, Contrast = 0.18, Bloom = 0.55, Rays = 0.18, Cloud = rgb(255, 160, 120) },
	{ Hour = 19.4, Ambient = rgb(90, 76, 110), Outdoor = rgb(108, 90, 136), Brightness = 1.3, Exposure = 0.1, AtmoColor = rgb(150, 100, 160), AtmoDecay = rgb(70, 50, 110), Density = 0.34, Haze = 1.8, Glare = 0.2, Tint = rgb(228, 204, 255), Saturation = 0.12, Contrast = 0.2, Bloom = 0.8, Rays = 0.04, Cloud = rgb(170, 120, 170) },
	{ Hour = 21, Ambient = rgb(92, 100, 136), Outdoor = rgb(112, 124, 168), Brightness = 1.6, Exposure = 0.3, AtmoColor = rgb(62, 76, 122), AtmoDecay = rgb(36, 42, 84), Density = 0.26, Haze = 0.8, Glare = 0, Tint = rgb(206, 216, 255), Saturation = 0, Contrast = 0.08, Bloom = 0.9, Rays = 0, Cloud = rgb(80, 84, 110) },
}
Atmosphere.Keys = KEYS

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- The blended look at any hour (0-24)
function Atmosphere.Sample(hour)
	hour = hour % 24
	local a, b = KEYS[#KEYS], KEYS[1]
	local span, t
	for k = 1, #KEYS do
		local nextKey = KEYS[k + 1]
		if nextKey and hour >= KEYS[k].Hour and hour < nextKey.Hour then
			a, b = KEYS[k], nextKey
			break
		end
	end
	if a == KEYS[#KEYS] then
		span = (24 - a.Hour) + b.Hour
		t = ((hour - a.Hour) % 24) / span
	else
		span = b.Hour - a.Hour
		t = (hour - a.Hour) / span
	end
	-- smooth the blend so changes ease in and out
	t = t * t * (3 - 2 * t)
	local out = {}
	for key, value in pairs(a) do
		local other = b[key]
		if typeof(value) == "Color3" then
			out[key] = value:Lerp(other, t)
		elseif type(value) == "number" then
			out[key] = lerp(value, other, t)
		end
	end
	return out
end

-- Creates the sky and post effects in Lighting (safe to call more than once)
function Atmosphere.Setup(lighting)
	local function ensure(className, name)
		local existing = lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local obj = Instance.new(className)
		obj.Name = name
		obj.Parent = lighting
		return obj
	end
	local sky = ensure("Sky", "CitySky")
	sky.StarCount = 4000
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 11
	sky.MoonAngularSize = 9
	local atmo = ensure("Atmosphere", "CityAtmosphere")
	atmo.Offset = 0.18
	local bloom = ensure("BloomEffect", "CityBloom")
	bloom.Size = 24
	bloom.Threshold = 1.4 -- neon signs, lit windows and lamps glow (not the whole sky)
	ensure("ColorCorrectionEffect", "CityColor")
	local rays = ensure("SunRaysEffect", "CitySunRays")
	rays.Spread = 0.75
	local depth = ensure("DepthOfFieldEffect", "CityDepth")
	depth.FarIntensity = 0.08
	depth.FocusDistance = 80
	depth.InFocusRadius = 140
	depth.NearIntensity = 0
	lighting.EnvironmentDiffuseScale = 0.55 -- (full sky light flattens and washes everything out)
	lighting.EnvironmentSpecularScale = 1 -- (real reflections on glass, metal, paint and wet streets)
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.12 -- crisp, realistic sun shadows
	lighting.GeographicLatitude = 32
	-- real moving clouds in the sky
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChild("CityClouds") then
		pcall(function()
			local clouds = Instance.new("Clouds")
			clouds.Name = "CityClouds"
			clouds.Cover = 0.52
			clouds.Density = 0.62
			clouds.Color = Color3.fromRGB(255, 255, 255)
			clouds.Parent = terrain
		end)
	end
	Atmosphere.Apply(lighting, lighting.ClockTime or 12)
end

-- Applies the look for this hour
function Atmosphere.Apply(lighting, hour)
	local s = Atmosphere.Sample(hour)
	lighting.Ambient = s.Ambient
	lighting.OutdoorAmbient = s.Outdoor
	lighting.Brightness = s.Brightness
	lighting.ExposureCompensation = s.Exposure
	local atmo = lighting:FindFirstChild("CityAtmosphere")
	if atmo then
		atmo.Color = s.AtmoColor
		atmo.Decay = s.AtmoDecay
		atmo.Density = s.Density
		atmo.Haze = s.Haze
		atmo.Glare = s.Glare
	end
	local color = lighting:FindFirstChild("CityColor")
	if color then
		color.TintColor = s.Tint
		color.Saturation = s.Saturation
		color.Contrast = s.Contrast
	end
	local bloom = lighting:FindFirstChild("CityBloom")
	if bloom then
		bloom.Intensity = s.Bloom
	end
	local rays = lighting:FindFirstChild("CitySunRays")
	if rays then
		rays.Intensity = s.Rays
	end
	-- the clouds take the color of the sky (golden at sunrise, pink at sunset,
	-- dark at night) and the day's weather sets how many there are
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChild("CityClouds")
	if clouds then
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("CityState")
		local w = Atmosphere.WEATHER[(shared and shared:GetAttribute("Weather")) or Atmosphere.Weather] or Atmosphere.WEATHER.Fair
		clouds.Color = s.Cloud:Lerp(Color3.fromRGB(150, 154, 164), w.Gray)
		clouds.Cover = w.Cover
		clouds.Density = w.Density
		if w.Dim > 0 then
			lighting.Brightness = s.Brightness * (1 - w.Dim)
			local color = lighting:FindFirstChild("CityColor")
			if color then
				color.Saturation = s.Saturation - w.Dim * 0.3
			end
		end
	end
end

-- The day's weather (CityService picks one each morning)
Atmosphere.WEATHER = {
	Clear = { Cover = 0.3, Density = 0.4, Gray = 0, Dim = 0, Label = "☀️ Clear skies" },
	Fair = { Cover = 0.5, Density = 0.55, Gray = 0, Dim = 0, Label = "🌤️ Fair weather" },
	Cloudy = { Cover = 0.72, Density = 0.7, Gray = 0.25, Dim = 0.12, Label = "⛅ Cloudy" },
	Overcast = { Cover = 0.88, Density = 0.85, Gray = 0.45, Dim = 0.25, Label = "☁️ Overcast" },
	-- showers in the morning and the late afternoon (see RainService)
	Rainy = { Cover = 0.95, Density = 0.9, Gray = 0.55, Dim = 0.3, Label = "🌧️ Showers on and off" },
}
Atmosphere.Weather = "Fair"
function Atmosphere.PickWeather(rng)
	local roll = rng:NextNumber()
	Atmosphere.Weather = if roll < 0.27 then "Clear" elseif roll < 0.6 then "Fair" elseif roll < 0.78 then "Cloudy" elseif roll < 0.88 then "Overcast" else "Rainy"
	return Atmosphere.Weather
end

-- Night is when street lamps and windows light up
function Atmosphere.IsNight(hour)
	return hour >= 18.6 or hour < 6.3
end

return Atmosphere
