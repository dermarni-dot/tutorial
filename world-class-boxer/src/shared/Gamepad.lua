-- Gamepad: which device the player is using right now (keyboard and mouse, gamepad or touch), the names
-- of the controller's buttons for on-screen prompts and a thumbstick flick detector.
--   Gamepad.Mode()          "keyboard" | "gamepad" | "touch" (follows UserInputService's last input type)
--   Gamepad.IsPad()         Mode() == "gamepad"
--   Gamepad.Changed         fires (mode) when the player picks up another device
--   Gamepad.Brand()         "xbox" | "ps" | "generic" (read from the connected controller's button names)
--   Gamepad.Label(keyCode)  "X" / "SQUARE" / "RT" / "R2" / "D-PAD UP" / "RS LEFT" ... and keyboard keys
--                           ("SPACE", "1", "SHIFT") for the hint texts
--   Gamepad.Short(keyCode)  the same for tight key caps (the D-pad as "D-UP" ...)
--   Gamepad.IsPadKey(k)     a gamepad KeyCode (buttons, D-pad, thumbsticks)
--   Gamepad.Flick()         a flick detector: f:Update(x, y, now) returns "L" / "R" / "U" / "D" once per flick
--   Gamepad.Rumble(large, small, dur)  controller vibration through HapticService (0..1 each motor, dur s),
--                           scaled by Gamepad.SetVibration(k) (0 = off; the Settings toggle / strength)
-- Client-side; the server never needs it (it loads there and stays in "keyboard" mode).
local UserInputService = game:GetService("UserInputService")
local K = Enum.KeyCode
local IT = Enum.UserInputType

local Gamepad = {}

local PAD_TYPES = {
	[IT.Gamepad1] = true, [IT.Gamepad2] = true, [IT.Gamepad3] = true, [IT.Gamepad4] = true,
	[IT.Gamepad5] = true, [IT.Gamepad6] = true, [IT.Gamepad7] = true, [IT.Gamepad8] = true,
}
-- mouse movement alone does not switch the prompts back to keys: a desk bump while playing on a pad
-- would flicker every hint on screen (a click or a key press does)
local KEYBOARD_TYPES = {
	[IT.Keyboard] = true, [IT.MouseButton1] = true, [IT.MouseButton2] = true, [IT.MouseButton3] = true,
	[IT.MouseWheel] = true, [IT.TextInput] = true,
}

local function modeOf(t)
	if PAD_TYPES[t] then
		return "gamepad"
	elseif t == IT.Touch then
		return "touch"
	elseif KEYBOARD_TYPES[t] then
		return "keyboard"
	end
	return nil
end

local function initialMode()
	local ok, t = pcall(UserInputService.GetLastInputType, UserInputService)
	local m = ok and modeOf(t) or nil
	if m then
		return m
	end
	local okPad, pad = pcall(function()
		return UserInputService.GamepadEnabled
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	elseif okPad and pad and not UserInputService.KeyboardEnabled then
		return "gamepad" -- a console
	end
	return "keyboard"
end

local mode = initialMode()
local brand = nil -- resolved on first use, again after a controller connects
local changed = Instance.new("BindableEvent")
Gamepad.Changed = changed.Event

function Gamepad.Mode()
	return mode
end

function Gamepad.IsPad()
	return mode == "gamepad"
end

UserInputService.LastInputTypeChanged:Connect(function(t)
	local m = modeOf(t)
	if m and m ~= mode then
		mode = m
		changed:Fire(mode)
	end
end)
UserInputService.GamepadConnected:Connect(function()
	brand = nil
end)

-- GetStringForKeyCode names the face buttons after the connected controller: "ButtonA" on an Xbox pad,
-- "ButtonCross" on a PlayStation one
function Gamepad.Brand()
	if brand then
		return brand
	end
	local ok, s = pcall(UserInputService.GetStringForKeyCode, UserInputService, K.ButtonA)
	if ok and type(s) == "string" and s:find("Cross", 1, true) then
		brand = "ps"
	elseif ok and s == "ButtonA" then
		brand = "xbox"
	else
		brand = "generic"
	end
	return brand
end

local XBOX = {
	[K.ButtonA] = "A", [K.ButtonB] = "B", [K.ButtonX] = "X", [K.ButtonY] = "Y",
	[K.ButtonL1] = "LB", [K.ButtonR1] = "RB", [K.ButtonL2] = "LT", [K.ButtonR2] = "RT",
	[K.ButtonL3] = "LS CLICK", [K.ButtonR3] = "RS CLICK", [K.ButtonSelect] = "VIEW", [K.ButtonStart] = "MENU",
	[K.Thumbstick1] = "LS", [K.Thumbstick2] = "RS",
}
local PS = {
	[K.ButtonA] = "CROSS", [K.ButtonB] = "CIRCLE", [K.ButtonX] = "SQUARE", [K.ButtonY] = "TRIANGLE",
	[K.ButtonL1] = "L1", [K.ButtonR1] = "R1", [K.ButtonL2] = "L2", [K.ButtonR2] = "R2",
	[K.ButtonL3] = "L3", [K.ButtonR3] = "R3", [K.ButtonSelect] = "SHARE", [K.ButtonStart] = "OPTIONS",
	[K.Thumbstick1] = "LS", [K.Thumbstick2] = "RS",
}
local COMMON = {
	[K.DPadUp] = "D-PAD UP", [K.DPadDown] = "D-PAD DOWN", [K.DPadLeft] = "D-PAD LEFT", [K.DPadRight] = "D-PAD RIGHT",
	-- the right-stick flicks (slips, rolls) ride on these KeyCodes in the key maps
	[K.Thumbstick2Left] = "RS LEFT", [K.Thumbstick2Right] = "RS RIGHT", [K.Thumbstick2Up] = "RS UP", [K.Thumbstick2Down] = "RS DOWN",
	[K.Thumbstick1Left] = "LS LEFT", [K.Thumbstick1Right] = "LS RIGHT", [K.Thumbstick1Up] = "LS UP", [K.Thumbstick1Down] = "LS DOWN",
}
local KEYS = {
	[K.Space] = "SPACE", [K.LeftShift] = "SHIFT", [K.RightShift] = "SHIFT", [K.Return] = "ENTER", [K.Backspace] = "BACKSPACE",
	[K.One] = "1", [K.Two] = "2", [K.Three] = "3", [K.Four] = "4", [K.Five] = "5", [K.Six] = "6", [K.Semicolon] = ";",
	[K.Seven] = "7", [K.Eight] = "8", [K.Nine] = "9", [K.Zero] = "0", [K.Tab] = "TAB", [K.LeftControl] = "CTRL", [K.RightControl] = "CTRL",
	[K.LeftAlt] = "ALT", [K.RightAlt] = "ALT", [K.Comma] = ",", [K.Period] = ".", [K.CapsLock] = "CAPS",
	[K.Up] = "UP", [K.Down] = "DOWN", [K.Left] = "LEFT", [K.Right] = "RIGHT",
}

function Gamepad.Label(k)
	if typeof(k) ~= "EnumItem" then
		return ""
	end
	local t = (Gamepad.Brand() == "ps" and PS or XBOX)[k] or COMMON[k] or KEYS[k]
	return t or string.upper(k.Name)
end

-- a short name for tight key caps (HUD buttons): the D-pad as "D-UP" / "D-DOWN" / ...
local SHORT = { [K.DPadUp] = "D-UP", [K.DPadDown] = "D-DOWN", [K.DPadLeft] = "D-LEFT", [K.DPadRight] = "D-RIGHT" }
function Gamepad.Short(k)
	return SHORT[k] or Gamepad.Label(k)
end

function Gamepad.IsPadKey(k)
	if typeof(k) ~= "EnumItem" or k.EnumType ~= Enum.KeyCode then
		return false
	end
	local n = k.Name
	return n:sub(1, 6) == "Button" or n:sub(1, 4) == "DPad" or n:sub(1, 10) == "Thumbstick"
end

-- the flick detector: the stick has to travel from near rest (inside INNER) to the edge (OUTER) within
-- WINDOW seconds of leaving the middle; it fires once, then re-arms when the stick comes back toward the
-- middle. A slow push or a held stick never repeats. Plain fields only: Update allocates nothing.
local Flick = {}
Flick.__index = Flick
local INNER, OUTER, WINDOW = 0.3, 0.72, 0.3

function Gamepad.Flick()
	return setmetatable({ armed = true, leftAt = nil }, Flick)
end

function Flick:Update(x, y, now)
	x, y = tonumber(x) or 0, tonumber(y) or 0
	local m = math.sqrt(x * x + y * y)
	if m < INNER then
		self.armed = true
		self.leftAt = nil
		return nil
	end
	if not self.leftAt then
		self.leftAt = now
	end
	if self.armed and m >= OUTER then
		self.armed = false
		if now - self.leftAt > WINDOW then
			return nil
		end
		if math.abs(x) >= math.abs(y) then
			return x < 0 and "L" or "R"
		end
		return y < 0 and "D" or "U"
	end
	return nil
end

function Flick:Reset()
	self.armed = true
	self.leftAt = nil
end

------------------------------------------------------------------------
-- Vibration (HapticService): every call is guarded, a controller without motors is a silent no-op.
-- Pulses overlap sanely: a stronger pulse replaces a weaker one, each motor idles once its own pulse ends.
------------------------------------------------------------------------
local vibration = 1
local rumble = { token = 0 }
local HapticService
function Gamepad.SetVibration(k)
	vibration = math.clamp(tonumber(k) or 0, 0, 1)
	if vibration <= 0 then
		Gamepad.Rumble(0, 0, 0)
	end
end

function Gamepad.Vibration()
	return vibration
end

local function motor(name, k)
	if not HapticService then
		local ok, svc = pcall(game.GetService, game, "HapticService")
		HapticService = ok and svc or false
	end
	if not HapticService then
		return false
	end
	local ok = pcall(HapticService.SetMotor, HapticService, IT.Gamepad1, Enum.VibrationMotor[name], k)
	return ok
end

-- large / small = 0..1 motor strengths, dur = seconds (default 0.15); returns true when a call went through
function Gamepad.Rumble(large, small, dur)
	large = math.clamp((tonumber(large) or 0) * vibration, 0, 1)
	small = math.clamp((tonumber(small) or 0) * vibration, 0, 1)
	if large <= 0 and small <= 0 then
		rumble.token += 1
		motor("Large", 0)
		motor("Small", 0)
		return false
	end
	if mode ~= "gamepad" then
		return false
	end
	local ok = motor("Large", large)
	motor("Small", small)
	rumble.token += 1
	local token = rumble.token
	task.delay(dur or 0.15, function()
		if rumble.token == token then
			motor("Large", 0)
			motor("Small", 0)
		end
	end)
	return ok
end

return Gamepad
