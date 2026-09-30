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
	{ Hour = 0, Ambient = rgb(58, 64, 100), Outdoor = rgb(66, 78, 122), Brightness = 1.1, Exposure = 0, AtmoColor = rgb(40, 52, 96), AtmoDecay = rgb(22, 26, 60), Density = 0.36, Haze = 1.2, Glare = 0, Tint = rgb(185, 200, 255), Saturation = -0.05, Contrast = 0.12, Bloom = 1.1, Rays = 0 },
	{ Hour = 4.8, Ambient = rgb(62, 66, 104), Outdoor = rgb(74, 80, 126), Brightness = 1.15, Exposure = 0, AtmoColor = rgb(60, 66, 116), AtmoDecay = rgb(40, 36, 80), Density = 0.37, Haze = 1.4, Glare = 0, Tint = rgb(195, 205, 255), Saturation = -0.02, Contrast = 0.1, Bloom = 1, Rays = 0 },
	{ Hour = 6.2, Ambient = rgb(110, 90, 104), Outdoor = rgb(150, 120, 128), Brightness = 1.6, Exposure = 0, AtmoColor = rgb(236, 170, 160), AtmoDecay = rgb(170, 110, 140), Density = 0.34, Haze = 2.2, Glare = 0.6, Tint = rgb(255, 222, 214), Saturation = 0.12, Contrast = 0.08, Bloom = 0.8, Rays = 0.14 },
	{ Hour = 8, Ambient = rgb(128, 124, 124), Outdoor = rgb(150, 150, 150), Brightness = 2.4, Exposure = 0.05, AtmoColor = rgb(200, 214, 236), AtmoDecay = rgb(120, 150, 196), Density = 0.3, Haze = 1.6, Glare = 0.25, Tint = rgb(255, 246, 236), Saturation = 0.18, Contrast = 0.1, Bloom = 0.55, Rays = 0.08 },
	{ Hour = 12.5, Ambient = rgb(136, 136, 140), Outdoor = rgb(158, 158, 162), Brightness = 3, Exposure = 0.08, AtmoColor = rgb(196, 220, 250), AtmoDecay = rgb(106, 146, 206), Density = 0.26, Haze = 1.2, Glare = 0.12, Tint = rgb(255, 252, 246), Saturation = 0.2, Contrast = 0.1, Bloom = 0.45, Rays = 0.05 },
	{ Hour = 16.5, Ambient = rgb(138, 128, 118), Outdoor = rgb(160, 148, 136), Brightness = 2.6, Exposure = 0.05, AtmoColor = rgb(236, 208, 176), AtmoDecay = rgb(160, 140, 150), Density = 0.3, Haze = 1.8, Glare = 0.4, Tint = rgb(255, 238, 214), Saturation = 0.22, Contrast = 0.1, Bloom = 0.55, Rays = 0.1 },
	{ Hour = 18.2, Ambient = rgb(128, 92, 88), Outdoor = rgb(170, 110, 96), Brightness = 1.9, Exposure = 0.02, AtmoColor = rgb(255, 150, 110), AtmoDecay = rgb(170, 90, 120), Density = 0.34, Haze = 2.6, Glare = 0.9, Tint = rgb(255, 210, 180), Saturation = 0.2, Contrast = 0.1, Bloom = 0.8, Rays = 0.18 },
	{ Hour = 19.4, Ambient = rgb(84, 66, 104), Outdoor = rgb(100, 78, 130), Brightness = 1.2, Exposure = -0.02, AtmoColor = rgb(150, 100, 160), AtmoDecay = rgb(70, 50, 110), Density = 0.36, Haze = 2, Glare = 0.2, Tint = rgb(226, 200, 255), Saturation = 0.08, Contrast = 0.12, Bloom = 1, Rays = 0.04 },
	{ Hour = 21, Ambient = rgb(60, 66, 102), Outdoor = rgb(68, 80, 124), Brightness = 1.1, Exposure = 0, AtmoColor = rgb(44, 56, 100), AtmoDecay = rgb(24, 28, 64), Density = 0.36, Haze = 1.2, Glare = 0, Tint = rgb(190, 204, 255), Saturation = -0.04, Contrast = 0.12, Bloom = 1.1, Rays = 0 },
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
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	local atmo = ensure("Atmosphere", "CityAtmosphere")
	atmo.Offset = 0.18
	local bloom = ensure("BloomEffect", "CityBloom")
	bloom.Size = 24
	bloom.Threshold = 1.25 -- neon signs, lit windows and lamps glow
	ensure("ColorCorrectionEffect", "CityColor")
	local rays = ensure("SunRaysEffect", "CitySunRays")
	rays.Spread = 0.75
	local depth = ensure("DepthOfFieldEffect", "CityDepth")
	depth.FarIntensity = 0.12
	depth.FocusDistance = 80
	depth.InFocusRadius = 140
	depth.NearIntensity = 0
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 1
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.25
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
end

-- Night is when street lamps and windows light up
function Atmosphere.IsNight(hour)
	return hour >= 18.6 or hour < 6.3
end

return Atmosphere
