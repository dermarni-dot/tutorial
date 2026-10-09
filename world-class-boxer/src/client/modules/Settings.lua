-- Settings: the player's options, applied on this client straight away.
--   uiScale     0.8 .. 1.25  multiplier on the responsive UI scale (UI.SetUserScale)
--   screenFx    0 .. 1.5     blur / colour drain / flashes in fights (Config.ScreenFX, read by FightClient + VenueFX)
--   shake       0 .. 1.5     camera shake and kicks (FightClient, training camera, main menu)
--   music       0 .. 1       music volume (SoundService.MusicMix: every Sound named *Music*, walkout music)
--   sfx         0 .. 1       every other sound (all other SoundGroups: gym, fight mix)
--   detail      Auto | High | Medium | Low   graphics detail (AnatomyClient.Settings: full-detail count,
--                                           ranges, build budget, textures; client attribute GfxDetail)
--   brightness  0.5 .. 1.6   overall exposure (player attribute Brightness, read by LightLevels)
--   menuAtStart bool         open the main menu when you join
--   controlHints bool        keep the fight's key-cap strip on screen (otherwise it fades after round 1)
-- Saved with the profile through the "SaveSettings" request (R-ui integration request for Main). The
-- server's summary carries P.settings (a table) once it supports that; until then nothing is sent and
-- the settings last for the session.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))

local Settings = {}
local player = Players.LocalPlayer

Settings.Defaults = { uiScale = 1, screenFx = 1, shake = 1, music = 0.8, sfx = 1, brightness = 1, detail = "Auto", menuAtStart = true, controlHints = false }
Settings.Details = { "Auto", "High", "Medium", "Low" }
local RANGES = { uiScale = { 0.8, 1.25 }, screenFx = { 0, 1.5 }, shake = { 0, 1.5 }, music = { 0, 1 }, sfx = { 0, 1 }, brightness = { 0.5, 1.6 } }

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
	for _, k in ipairs({ "menuAtStart", "controlHints" }) do
		if type(t[k]) == "boolean" then
			out[k] = t[k]
		end
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
-- Audio: music plays through SoundService.MusicMix (volume = the music setting); every other
-- SoundGroup (gym, FightMix...) scales with the sfx setting
------------------------------------------------------------------------
local function isMusic(s)
	return s.Name:find("Music") ~= nil or (s.Parent ~= nil and s.Parent.Name:find("Music") ~= nil)
end

local MUSIC_MIX = "MusicMix"
local function musicMix()
	local g = SoundService:FindFirstChild(MUSIC_MIX)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = MUSIC_MIX
		g.Parent = SoundService
	end
	g.Volume = Settings.Values.music
	return g
end

local function applyGroup(g)
	if not g:IsA("SoundGroup") or g.Name == MUSIC_MIX then
		return
	end
	local base = g:GetAttribute("BaseVolume")
	if base == nil then
		base = g.Volume
		g:SetAttribute("BaseVolume", base)
	end
	g.Volume = base * Settings.Values.sfx
end

-- a music Sound (walkout, arena, the gym speakers, anywhere in the game) is routed through MusicMix:
-- the music setting reaches it live, its own Volume stays whatever its module sets, and the sfx
-- setting no longer touches it
local function applyMusic(s)
	if not (s:IsA("Sound") and isMusic(s)) then
		return
	end
	local mix = musicMix()
	if s.SoundGroup ~= mix then
		s.SoundGroup = mix
	end
end

local musicWatch = {}
local function watchMusic(container)
	if musicWatch[container] then
		return
	end
	musicWatch[container] = container.DescendantAdded:Connect(function(d)
		if d.ClassName == "Sound" then
			-- deferred: the module that made it names it and picks its group first
			task.defer(applyMusic, d)
		end
	end)
	for _, d in ipairs(container:GetDescendants()) do
		if d.ClassName == "Sound" then
			applyMusic(d)
		end
	end
end

function Settings.ApplyAudio()
	musicMix()
	for _, g in ipairs(SoundService:GetChildren()) do
		applyGroup(g)
	end
end

-- the SoundGroup music plays through (a module making its own music may set it directly; any Sound
-- named *Music* is routed there automatically)
function Settings.MusicGroup()
	return musicMix()
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

-- AnatomyClient's public Settings table (mesh rework): how many characters get full-detail meshes,
-- how far away, how much build time per frame and whether colour textures are made. "Auto" puts
-- back whatever the module had before this menu first changed it.
local DETAIL_KNOBS = {
	High = { maxFull = 10, fullRange = 90, lodRange = 200, frameBudget = 0.004, textures = true },
	Medium = { maxFull = 4, fullRange = 50, lodRange = 120, frameBudget = 0.002, textures = true },
	Low = { maxFull = 1, fullRange = 30, lodRange = 80, frameBudget = 0.0015, textures = false },
}
local anatomyBase -- the module's own values, captured the first time a level is forced
function Settings.ApplyDetail()
	local d = Settings.Values.detail
	player:SetAttribute("GfxDetail", d) -- client-local: any visual module may read it
	local ac = anatomyModule()
	if not ac then
		return
	end
	-- a dedicated setter wins if the module ever exposes one (names checked, every call guarded)
	local level = ({ High = "full", Medium = "medium", Low = "low" })[d]
	for _, fn in ipairs({ "SetDetail", "SetQuality", "SetBudget" }) do
		if type(ac[fn]) == "function" then
			pcall(ac[fn], level or "auto")
			return
		end
	end
	local cfg = type(ac.Settings) == "table" and ac.Settings or nil
	if not cfg then
		return
	end
	local knobs = DETAIL_KNOBS[d]
	if knobs and not anatomyBase then
		anatomyBase = {}
		for k in pairs(DETAIL_KNOBS.High) do
			anatomyBase[k] = cfg[k]
		end
	end
	knobs = knobs or anatomyBase
	for k, v in pairs(knobs or {}) do
		if cfg[k] ~= nil and type(cfg[k]) == type(v) then
			cfg[k] = v
		end
	end
end

function Settings.Apply()
	local v = Settings.Values
	UI.SetUserScale(v.uiScale)
	Config.ScreenFX = v.screenFx -- read every frame by FightClient / VenueFX
	player:SetAttribute("CamShake", v.shake) -- client-local: FightClient / training / menu cameras
	player:SetAttribute("ControlHints", v.controlHints == true) -- FightClient: keep the key strip up
	player:SetAttribute("Brightness", v.brightness) -- client-local: LightLevels exposure
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
		if token == saveToken and Settings.Supported() then
			task.spawn(State.req, "SaveSettings", Settings.Values)
		end
	end)
end

-- does the server store settings? (its summary carries P.settings; older servers answer
-- "Unknown action", so nothing is sent to them)
function Settings.Supported()
	local P = State and State.P
	return P ~= nil and type(P.settings) == "table"
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
