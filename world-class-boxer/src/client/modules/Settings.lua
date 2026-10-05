-- Settings: the player's options, applied on this client straight away.
--   uiScale     0.8 .. 1.25  multiplier on the responsive UI scale (UI.SetUserScale)
--   screenFx    0 .. 1.5     blur / colour drain / flashes in fights (Config.ScreenFX, read by FightClient + VenueFX)
--   shake       0 .. 1.5     camera shake and kicks (FightClient, training camera, main menu)
--   music       0 .. 1       music volume (sounds named *Music*, walkout music)
--   sfx         0 .. 1       every other sound (all SoundGroups: gym, fight mix)
--   detail      Auto | High | Medium | Low   graphics detail (AnatomyClient budget when it exposes one,
--                                           client attribute GfxDetail for everyone else)
--   menuAtStart bool         open the main menu when you join
-- Saved with the profile through the "SaveSettings" request (R-ui integration request for Main); a
-- server without that handler simply keeps them for the session.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))

local Settings = {}
local player = Players.LocalPlayer

Settings.Defaults = { uiScale = 1, screenFx = 1, shake = 1, music = 0.8, sfx = 1, detail = "Auto", menuAtStart = true }
Settings.Details = { "Auto", "High", "Medium", "Low" }
local RANGES = { uiScale = { 0.8, 1.25 }, screenFx = { 0, 1.5 }, shake = { 0, 1.5 }, music = { 0, 1 }, sfx = { 0, 1 } }

-- pure: a clean settings table from anything (saved data, client input); unknown keys dropped
function Settings.Sanitize(t)
	local out = table.clone(Settings.Defaults)
	if type(t) ~= "table" then
		return out
	end
	for k, r in pairs(RANGES) do
		local v = tonumber(t[k])
		if v and v == v then
			out[k] = math.floor(math.clamp(v, r[1], r[2]) * 100 + 0.5) / 100
		end
	end
	if table.find(Settings.Details, t.detail) then
		out.detail = t.detail
	end
	if type(t.menuAtStart) == "boolean" then
		out.menuAtStart = t.menuAtStart
	end
	return out
end

Settings.Values = Settings.Sanitize(nil)
local changed = Instance.new("BindableEvent")
Settings.Changed = changed.Event

function Settings.Get(k)
	return Settings.Values[k]
end

------------------------------------------------------------------------
-- Audio: SoundGroups scale with sfx; music sounds with music
------------------------------------------------------------------------
local function isMusic(s)
	return s.Name:find("Music") ~= nil or (s.Parent ~= nil and s.Parent.Name:find("Music") ~= nil)
end

local function applyGroup(g)
	if not g:IsA("SoundGroup") then
		return
	end
	local base = g:GetAttribute("BaseVolume")
	if base == nil then
		base = g.Volume
		g:SetAttribute("BaseVolume", base)
	end
	g.Volume = base * Settings.Values.sfx
end

local function applyMusic(s)
	if not (s:IsA("Sound") and isMusic(s)) then
		return
	end
	local base = s:GetAttribute("BaseVolume")
	if base == nil then
		base = s.Volume
		s:SetAttribute("BaseVolume", base)
	end
	s.Volume = base * Settings.Values.music
end

local musicWatch = {}
local function watchMusic(container)
	if musicWatch[container] then
		return
	end
	musicWatch[container] = container.DescendantAdded:Connect(function(d)
		if d.ClassName == "Sound" then
			-- the name is set before parenting by every module that makes music
			task.defer(applyMusic, d)
		end
	end)
end

function Settings.ApplyAudio()
	for _, g in ipairs(SoundService:GetChildren()) do
		applyGroup(g)
	end
	for _, s in ipairs(SoundService:GetDescendants()) do
		applyMusic(s)
	end
end

-- the volume a music Sound should play at (for modules that create their own music)
function Settings.MusicVolume(base)
	return (base or 1) * Settings.Values.music
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------
local Modules = script.Parent
local anatomy
local function anatomyModule()
	if anatomy == nil then
		local m = Modules:FindFirstChild("AnatomyClient")
		local ok, mod = false, nil
		if m then
			ok, mod = pcall(require, m)
		end
		anatomy = (ok and type(mod) == "table") and mod or false
	end
	return anatomy or nil
end

function Settings.ApplyDetail()
	local d = Settings.Values.detail
	player:SetAttribute("GfxDetail", d) -- client-local: any visual module may read it
	local ac = anatomyModule()
	if ac then
		-- whichever knob the anatomy module exposes (names checked, every call guarded)
		local level = ({ Auto = nil, High = "full", Medium = "medium", Low = "low" })[d]
		for _, fn in ipairs({ "SetDetail", "SetQuality", "SetBudget" }) do
			if type(ac[fn]) == "function" then
				pcall(ac[fn], level or "auto")
				break
			end
		end
	end
end

function Settings.Apply()
	local v = Settings.Values
	UI.SetUserScale(v.uiScale)
	Config.ScreenFX = v.screenFx -- read every frame by FightClient / VenueFX
	player:SetAttribute("CamShake", v.shake) -- client-local: FightClient / training / menu cameras
	Settings.ApplyAudio()
	Settings.ApplyDetail()
end

local saveToken = 0
local State
function Settings.Set(k, value)
	local t = table.clone(Settings.Values)
	t[k] = value
	Settings.Values = Settings.Sanitize(t)
	Settings.Apply()
	changed:Fire(k, Settings.Values[k])
	-- save a moment after the last change (one request per burst of slider drags)
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken and State then
			task.spawn(State.req, "SaveSettings", Settings.Values)
		end
	end)
end

-- the server's copy (P.settings.ui once Main stores it); local edits this session win
local loaded = false
function Settings.Load(P)
	if loaded or type(P) ~= "table" then
		return
	end
	local s = type(P.settings) == "table" and P.settings.ui or nil
	if type(s) == "table" then
		loaded = true
		Settings.Values = Settings.Sanitize(s)
		Settings.Apply()
		changed:Fire(nil, nil)
	end
end

function Settings.Start(state)
	State = state
	Settings.Apply()
	SoundService.ChildAdded:Connect(function(c)
		task.defer(function()
			if c.Parent then
				applyGroup(c)
			end
		end)
	end)
	watchMusic(SoundService)
	watchMusic(workspace)
	state.Changed:Connect(Settings.Load)
	Settings.Load(state.P)
end

return Settings
