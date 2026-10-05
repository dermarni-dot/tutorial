-- State: shared client state and helpers (latest profile, server requests, toasts,
-- the root ScreenGui) plus a tiny registry so the client modules can call each other.
-- State.gui is the scaled root frame inside the "BoxerUI" ScreenGui (UI.MountRoot): every window
-- is built in design pixels (1600 x 900 canvas) and scales to phone / tablet / desktop screens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local State = {}
State.player = player
State.P = nil -- latest profile summary from the server
State.Remotes = Remotes
State.Request = Remotes:WaitForChild("Request")
State.FightRemote = Remotes:WaitForChild("Fight")
State.ProfileRemote = Remotes:WaitForChild("Profile")
State.Notify = Remotes:WaitForChild("Notify")
-- registry: Hub, Creator, Activity, Spar, Barber, Locker, Nutrition, Water, Sleep, Store, Result,
-- Menu (main menu), Rankings, Settings, Career (fighter card)
State.open = {}
State.activity = nil -- the running training session (client side)

State.screen = UI.New("ScreenGui", {
	Name = "BoxerUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 2,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})
State.gui = UI.MountRoot(State.screen)
-- toasts get their own layer above every full-screen UI (the main menu is DisplayOrder 30, the fight
-- HUD 5): feedback raised while the menu is open is not buried under its backdrop
State.toastScreen = UI.New("ScreenGui", {
	Name = "BoxerToasts", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 35,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})
State.toastRoot = UI.MountRoot(State.toastScreen)

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event

function State.SetProfile(p)
	State.P = p
	changed:Fire(p)
end

-- re-run every Changed listener with the current profile (HUD visibility after a menu closes)
function State.Refresh()
	if State.P then
		changed:Fire(State.P)
	end
end

function State.req(action, ...)
	local args = table.pack(...)
	local ok, res = pcall(function()
		return State.Request:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not ok then
		return { ok = false, err = "Connection error" }
	end
	return res or { ok = false }
end

function State.toast(text, color, duration)
	UI.Toast(State.toastRoot, text, color, duration)
end

function State.busy()
	return player:GetAttribute("Busy")
end

function State.inFight()
	return player:GetAttribute("InFight") == true
end

function State.rec(r)
	if not r then
		return "0-0-0"
	end
	return string.format("%d-%d-%d (%d KO)", r.w, r.l, r.d, r.ko)
end

function State.char()
	local c = player.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

-- pause the default idle animation (it turns the head away) while previewing the look up close
function State.SetAnimate(on)
	local char = player.Character
	if not char then
		return
	end
	local animate = char:FindFirstChild("Animate")
	if animate then
		animate.Disabled = not on
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and not on then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0.2)
		end
	end
end

-- gym prompts hide while busy (server) or while a full-screen session is open (client)
local promptHolds = {}
function State.UpdatePrompts()
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.Enabled = State.busy() == nil and next(promptHolds) == nil
end
function State.HidePrompts(key, on)
	promptHolds[key] = on and true or nil
	State.UpdatePrompts()
end

-- the gym HUD hides while a full-screen screen (main menu, fighter card) is up
local hudHolds = {}
function State.HideHud(key, on)
	hudHolds[key] = on and true or nil
	State.Refresh()
end
function State.HudHidden()
	return next(hudHolds) ~= nil
end

-- open windows that should close when another big window opens
State.windows = {}
function State.closeAll(except)
	for name, closeFn in pairs(State.windows) do
		if name ~= except then
			pcall(closeFn)
		end
	end
end

return State
