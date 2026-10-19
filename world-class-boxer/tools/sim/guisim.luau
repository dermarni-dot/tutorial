--!nocheck
-- guisim.luau: the game's 2D UI under lune, laid out at a chosen screen size, so a test can check what a phone,
-- a tablet or a desktop really gets: nothing off the screen, nothing under the Roblox top bar, every touch
-- target a fingertip, the fight HUD's pieces apart. Built on fakeengine (real Instance hierarchy) + host
-- (the project's modules and LocalScripts, unchanged).
--
--   local GS = require("./guisim")
--   local S = GS.new("phone")                 -- a device of GS.DEVICES (or { w, h, touch, keyboard, pad, safe })
--   S.loadScript("client/FightClient.client.lua")   -- a LocalScript of src/ (its own `script` node)
--   local Hub = S.require("Client/Hub")       -- a module (as H.require)
--   S.settle(0.5)                             -- let deferred / delayed threads run (seconds of wall time)
--   local items = S.collect()                 -- every visible GuiObject: { obj, x, y, w, h, clip, gui, path, ... }
--   S.checks(items, opts) -> { offscreen = {...}, topbar = {...}, touch = {...}, text = {...} }
--   GS.WriteBoxes(path, S, items)            -- JSON for tools/sim/ui_preview.py
--
-- The layout model (screen px; a ScreenGui's area is the screen less the device's safe insets and, unless
-- IgnoreGuiInset, the 58 px top bar): UDim2 Size / Position against the parent's content box, AnchorPoint,
-- UIScale (scales the object about its anchor, and everything under it), UIPadding, UIListLayout (fill
-- direction, padding, alignment, LayoutOrder / Name sort), UIGridLayout, AutomaticSize (children's extents,
-- list content and text bounds), UISizeConstraint, UIAspectRatioConstraint, ScrollingFrame canvases (their
-- content is clipped, not off-screen) and ClipsDescendants. Text is measured with per-glyph widths for Gotham
-- and the condensed Oswald (close to the engine's, a little generous). Tweens land on their goal at once.
-- Rotation is ignored.
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector2, UDim2, UDim, Enum = roblox.Vector2, roblox.UDim2, roblox.UDim, roblox.Enum

local GS = {}

-- the top bar (Roblox's 2023+ UI) is 58 px tall; its buttons sit at the left (menu, chat, backpack / unibar)
GS.TOPBAR = 58
GS.TOPBAR_BUTTONS_W = 200
GS.TOUCH_PX = 44

-- safe: the device's own insets (notch / home indicator) a ScreenGui's default ScreenInsets keep it out of
GS.DEVICES = {
	phone = { w = 844, h = 390, touch = true, keyboard = false, safe = { l = 47, r = 47, t = 0, b = 21 } }, -- iPhone 12-15 landscape
	phone_small = { w = 667, h = 375, touch = true, keyboard = false, safe = { l = 0, r = 0, t = 0, b = 0 } }, -- iPhone SE
	tablet = { w = 1024, h = 768, touch = true, keyboard = false, safe = { l = 0, r = 0, t = 0, b = 20 } }, -- iPad
	desktop = { w = 1920, h = 1080, touch = false, keyboard = true, safe = { l = 0, r = 0, t = 0, b = 0 } },
	console = { w = 1920, h = 1080, touch = false, keyboard = false, pad = true, safe = { l = 0, r = 0, t = 0, b = 0 } },
	-- a phone with a controller (the key strip instead of the touch pads), a small laptop window
	phone_pad = { w = 844, h = 390, touch = true, keyboard = false, pad = true, safe = { l = 47, r = 47, t = 0, b = 21 } },
	laptop = { w = 1366, h = 650, touch = false, keyboard = true, safe = { l = 0, r = 0, t = 0, b = 0 } },
}

------------------------------------------------------------------------
-- text metrics
------------------------------------------------------------------------
-- em widths of Gotham Bold-ish glyphs (generous: a check that passes here passes in the engine)
local function glyphW(c)
	if c == " " then
		return 0.28
	elseif c:match("%u") then
		if c == "I" then
			return 0.3
		elseif c == "M" or c == "W" then
			return 0.86
		end
		return 0.68
	elseif c:match("%l") then
		if c == "i" or c == "l" or c == "j" then
			return 0.26
		elseif c == "m" or c == "w" then
			return 0.84
		end
		return 0.56
	elseif c:match("%d") then
		return 0.6
	elseif c == "." or c == "," or c == ":" or c == ";" or c == "'" or c == "!" or c == "|" then
		return 0.26
	end
	return 0.5
end

local function isCondensed(obj)
	local ok, ff = pcall(function()
		return rawget(obj, "_props").FontFace
	end)
	if ok and ff and tostring(ff.Family or ""):find("Oswald") then
		return true
	end
	local f = rawget(obj, "_props").Font
	return f ~= nil and tostring(f):find("Oswald") ~= nil
end

-- width (px) of one line of text at `size`
function GS.LineWidth(text, size, condensed)
	local w = 0
	for _, cp in utf8.codes(text) do
		local ch = utf8.char(cp)
		w += glyphW(ch)
	end
	return w * size * (condensed and 0.72 or 1)
end

-- the text's bounds: (w, h) at `size`, wrapped at maxW when given
function GS.TextBounds(text, size, condensed, maxW)
	text = tostring(text or "")
	if text == "" then
		return 0, 0
	end
	local lineH = size * 1.2
	local lines, widest = 0, 0
	for para in (text .. "\n"):gmatch("(.-)\n") do
		if maxW and maxW > 0 then
			local cur = ""
			local paraLines = 0
			for word in para:gmatch("%S+") do
				local try = cur == "" and word or (cur .. " " .. word)
				if cur ~= "" and GS.LineWidth(try, size, condensed) > maxW then
					widest = math.max(widest, GS.LineWidth(cur, size, condensed))
					paraLines += 1
					cur = word
				else
					cur = try
				end
			end
			widest = math.max(widest, GS.LineWidth(cur, size, condensed))
			lines += paraLines + 1
		else
			widest = math.max(widest, GS.LineWidth(para, size, condensed))
			lines += 1
		end
	end
	return widest, lines * lineH
end

------------------------------------------------------------------------
-- defaults for new GUI instances (the engine's own)
------------------------------------------------------------------------
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }
local GUIOBJ = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true, VideoFrame = true,
}
GS.GUIOBJ, GS.TEXT = GUIOBJ, TEXT

local function defaults(cls)
	local d = {}
	if GUIOBJ[cls] then
		d.Visible = true
		d.Size = (TEXT[cls] and UDim2.fromOffset(200, 50)) or UDim2.fromOffset(100, 100)
		d.Position = UDim2.new()
		d.AnchorPoint = Vector2.zero
		d.BackgroundTransparency = 0
		d.BackgroundColor3 = roblox.Color3.fromRGB(163, 162, 165)
		d.BorderSizePixel = 1
		d.Rotation = 0
		d.ZIndex = 1
		d.LayoutOrder = 0
		d.AutomaticSize = Enum.AutomaticSize.None
		d.ClipsDescendants = cls == "ScrollingFrame"
		d.Active = cls == "TextButton" or cls == "ImageButton" or cls == "TextBox" or cls == "ScrollingFrame"
		d.Selectable = cls == "TextButton" or cls == "ImageButton" or cls == "TextBox"
		d.SelectionGroup = false
		if TEXT[cls] then
			d.Text = cls == "TextLabel" and "Label" or (cls == "TextButton" and "Button" or "")
			d.TextSize = 14
			d.TextWrapped = false
			d.TextScaled = false
			d.TextTransparency = 0
			d.TextStrokeTransparency = 1
			d.TextColor3 = roblox.Color3.new(0, 0, 0)
			d.TextXAlignment = Enum.TextXAlignment.Center
			d.TextYAlignment = Enum.TextYAlignment.Center
			d.TextTruncate = Enum.TextTruncate.None
			d.RichText = false
			d.Font = Enum.Font.Legacy
			d.LineHeight = 1
			d.MaxVisibleGraphemes = -1
		end
		if cls == "TextButton" or cls == "ImageButton" then
			d.AutoButtonColor = true
			d.Modal = false
		end
		if cls == "TextBox" then
			d.ClearTextOnFocus = true
			d.PlaceholderText = ""
			d.MultiLine = false
			d.TextEditable = true
		end
		if cls == "ImageLabel" or cls == "ImageButton" then
			d.Image = ""
			d.ImageTransparency = 0
			d.ImageColor3 = roblox.Color3.new(1, 1, 1)
			d.ScaleType = Enum.ScaleType.Stretch
		end
		if cls == "ScrollingFrame" then
			d.CanvasSize = UDim2.new(0, 0, 2, 0)
			d.CanvasPosition = Vector2.zero
			d.ScrollBarThickness = 12
			d.AutomaticCanvasSize = Enum.AutomaticSize.None
			d.ScrollingDirection = Enum.ScrollingDirection.XY
			d.ScrollingEnabled = true
			d.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		end
		if cls == "ViewportFrame" then
			d.Ambient = roblox.Color3.new(0.78, 0.78, 0.78)
			d.LightColor = roblox.Color3.new(0.55, 0.55, 0.55)
		end
		if cls == "CanvasGroup" then
			d.GroupTransparency = 0
		end
	elseif cls == "ScreenGui" then
		d.Enabled = true
		d.IgnoreGuiInset = false
		d.DisplayOrder = 0
		d.ResetOnSpawn = true
	elseif cls == "UIScale" then
		d.Scale = 1
	elseif cls == "UIListLayout" then
		d.Padding = UDim.new(0, 0)
		d.FillDirection = Enum.FillDirection.Vertical
		d.SortOrder = Enum.SortOrder.Name
		d.HorizontalAlignment = Enum.HorizontalAlignment.Left
		d.VerticalAlignment = Enum.VerticalAlignment.Top
	elseif cls == "UIGridLayout" then
		d.CellSize = UDim2.fromOffset(100, 100)
		d.CellPadding = UDim2.fromOffset(5, 5)
		d.FillDirection = Enum.FillDirection.Horizontal
		d.FillDirectionMaxCells = 0
		d.SortOrder = Enum.SortOrder.Name
		d.HorizontalAlignment = Enum.HorizontalAlignment.Left
		d.VerticalAlignment = Enum.VerticalAlignment.Top
	elseif cls == "UIPadding" then
		d.PaddingLeft, d.PaddingRight, d.PaddingTop, d.PaddingBottom = UDim.new(), UDim.new(), UDim.new(), UDim.new()
	elseif cls == "UISizeConstraint" then
		d.MinSize = Vector2.zero
		d.MaxSize = Vector2.new(math.huge, math.huge)
	elseif cls == "UITextSizeConstraint" then
		d.MinTextSize, d.MaxTextSize = 1, 100
	elseif cls == "UIAspectRatioConstraint" then
		d.AspectRatio = 1
		d.AspectType = Enum.AspectType.FitWithinMaxSize
		d.DominantAxis = Enum.DominantAxis.Width
	elseif cls == "UIStroke" then
		d.Thickness = 1
		d.Transparency = 0
	elseif cls == "UICorner" then
		d.CornerRadius = UDim.new(0, 8)
	elseif cls == "Sound" then
		d.Volume, d.PlaybackSpeed, d.TimePosition, d.IsPlaying, d.Playing, d.Looped, d.TimeLength = 0.5, 1, 0, false, false, false, 0
		d.IsLoaded = true
	elseif cls == "BlurEffect" then
		d.Size = 24
	elseif cls == "Highlight" then
		d.FillTransparency = 0.5
	end
	return d
end

-- the engine's events (any instance): signals made on first use
local EVENTS = {}
for _, n in ipairs({
	"MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up",
	"MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelForward", "MouseWheelBackward", "InputBegan", "InputChanged", "InputEnded",
	"Activated", "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard", "SelectionGained", "SelectionLost", "SelectionChanged",
	"TouchTap", "TouchLongPress", "TouchPan", "TouchPinch", "TouchSwipe", "TouchRotate", "Touched", "TouchEnded", "Event", "OnClientEvent",
	"OnClientInvoke", "Completed", "Ended", "Played", "Stopped", "Paused", "Resumed", "Loaded", "DidLoop", "Died", "HealthChanged",
	"Running", "StateChanged", "MoveToFinished", "AnimationPlayed", "KeyframeReached", "Triggered", "TriggerEnded", "PromptShown",
	"PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded",
	"Chatted", "Idle", "OnTeleport", "Equipped", "Unequipped", "ClickDetectorMouseClick", "MouseClick", "MouseHoverEnter", "MouseHoverLeave",
	"DescendantRemoving", "Error", "MessageOut",
}) do
	EVENTS[n] = true
end

------------------------------------------------------------------------
-- the simulation
------------------------------------------------------------------------
function GS.new(device, opts)
	opts = opts or {}
	local dev = type(device) == "table" and device or assert(GS.DEVICES[device], "guisim: no device " .. tostring(device))
	local S = { device = dev, name = type(device) == "string" and device or "custom", W = dev.w, H = dev.h }
	local E = FE.new()
	S.E = E
	local signals = setmetatable({}, { __mode = "k" }) -- [inst] = { [event] = Signal }
	local function sigOf(o, k)
		local t = signals[o]
		if not t then
			t = {}
			signals[o] = t
		end
		local s = t[k]
		if not s then
			s = FE.Signal()
			t[k] = s
		end
		return s
	end
	S.signal = sigOf

	local dirty = true
	local L = nil -- the last layout: [obj] = rect
	E.onSet = function()
		dirty = true
	end

	-- computed members of GUI objects (AbsoluteSize, TextBounds ...) and the engine's events / methods
	local layout -- forward
	local function rectOf(o)
		if dirty or not L then
			layout()
		end
		return L[o]
	end
	local METHODS = {
		Fire = function(o, ...)
			sigOf(o, "Event"):Fire(...)
		end,
		Invoke = function(o, ...)
			local f = rawget(o, "_props").OnInvoke
			return f and f(...)
		end,
		Play = function(o)
			rawget(o, "_props").Playing, rawget(o, "_props").IsPlaying = true, true
		end,
		Stop = function(o)
			rawget(o, "_props").Playing, rawget(o, "_props").IsPlaying = false, false
		end,
		Pause = function(o)
			rawget(o, "_props").Playing, rawget(o, "_props").IsPlaying = false, false
		end,
		Resume = function(o)
			rawget(o, "_props").Playing, rawget(o, "_props").IsPlaying = true, true
		end,
		CaptureFocus = function() end, ReleaseFocus = function() end,
		IsFocused = function()
			return false
		end,
		TweenPosition = function(o, pos)
			o.Position = pos
			return true
		end,
		TweenSize = function(o, size)
			o.Size = size
			return true
		end,
		TweenSizeAndPosition = function(o, size, pos)
			o.Size, o.Position = size, pos
			return true
		end,
		ScrollToTop = function() end,
		FireServer = function(o, ...)
			if S.onFireServer then
				S.onFireServer(o, ...)
			end
		end,
		InvokeServer = function(o, ...)
			if S.onInvokeServer then
				return S.onInvokeServer(o, ...)
			end
			return { ok = false }
		end,
		ApplyImpulse = function() end, ApplyAngularImpulse = function() end, BreakJoints = function() end,
		SetNetworkOwner = function() end, MoveTo = function() end, Move = function() end,
		PivotTo = function(o, cf)
			rawget(o, "_props").CFrame = cf
		end,
		LoadAnimation = function()
			return S.magic
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
		ChangeState = function() end, GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		SetStateEnabled = function() end, GetAppliedDescription = function()
			return S.magic
		end,
		ApplyDescription = function() end,
		AddTag = function() end, RemoveTag = function() end, HasTag = function()
			return false
		end,
		GetTags = function()
			return {}
		end,
		GetConnectedParts = function()
			return {}
		end,
		GetTouchingParts = function()
			return {}
		end,
		GetBoundingBox = function(o)
			return o:GetPivot(), roblox.Vector3.new(4, 6, 2)
		end,
		GetExtentsSize = function()
			return roblox.Vector3.new(4, 6, 2)
		end,
		ScaleTo = function() end, GetScale = function()
			return 1
		end,
		Emit = function() end, Clear = function() end,
		SetPrimaryPartCFrame = function(o, cf)
			rawget(o, "_props").CFrame = cf
		end,
		GetPrimaryPartCFrame = function(o)
			return o:GetPivot()
		end,
		GetMass = function()
			return 1
		end,
		GetRootPart = function(o)
			return o
		end,
		AdjustSpeed = function() end,
		GetMarkerReachedSignal = function()
			return FE.Signal()
		end,
	}
	local SCREEN_METHODS = {
		WorldToViewportPoint = function(_, p)
			return roblox.Vector3.new(S.W / 2, S.H / 2, 10), true
		end,
		WorldToScreenPoint = function(_, p)
			return roblox.Vector3.new(S.W / 2, S.H / 2, 10), true
		end,
		ViewportPointToRay = function()
			return roblox.Ray.new(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1))
		end,
		ScreenPointToRay = function()
			return roblox.Ray.new(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1))
		end,
		GetPartsObscuringTarget = function()
			return {}
		end,
		Interpolate = function() end,
	}
	E.lazyGet = function(o, k)
		local cls = rawget(o, "_class")
		if EVENTS[k] then
			return sigOf(o, k)
		end
		local m = METHODS[k]
		if m then
			return m
		end
		if cls == "Camera" then
			if k == "ViewportSize" then
				return Vector2.new(S.W, S.H)
			elseif k == "FieldOfView" then
				return 70
			elseif SCREEN_METHODS[k] then
				return SCREEN_METHODS[k]
			elseif k == "CameraType" then
				return Enum.CameraType.Custom
			elseif k == "Focus" then
				return roblox.CFrame.new()
			end
		end
		if k == "AbsoluteSize" or k == "AbsolutePosition" or k == "AbsoluteWindowSize" or k == "AbsoluteCanvasSize" then
			if not (GUIOBJ[cls] or cls == "ScreenGui") then
				return nil
			end
			local r = rectOf(o)
			if not r then
				return Vector2.zero
			end
			if k == "AbsoluteSize" or k == "AbsoluteWindowSize" then
				return Vector2.new(r.w, r.h)
			elseif k == "AbsoluteCanvasSize" then
				return Vector2.new(r.w, r.canvasH or r.h)
			end
			return Vector2.new(r.x, r.y - GS.TOPBAR)
		elseif k == "AbsoluteContentSize" then
			local p = rawget(o, "_parent")
			local r = p and rectOf(p)
			return r and r.content and Vector2.new(r.content[1] * r.unit, r.content[2] * r.unit) or Vector2.zero
		elseif k == "TextBounds" and TEXT[cls] then
			local r = rectOf(o)
			local size = rawget(o, "_props").TextSize or 14
			local w, h = GS.TextBounds(rawget(o, "_props").Text or "", size, isCondensed(o), (rawget(o, "_props").TextWrapped and r) and (r.w / math.max(r.unit, 1e-6)) or nil)
			local u = r and r.unit or 1
			return Vector2.new(w * u, h * u)
		elseif k == "TextFits" and TEXT[cls] then
			return true
		elseif k == "ContentText" and TEXT[cls] then
			return rawget(o, "_props").Text
		elseif k == "GuiState" then
			return Enum.GuiState.Idle
		end
		return nil
	end

	-- Instance.new with the engine's defaults
	local baseNew = E.Instance.new
	local Instance = {
		new = function(cls, parent)
			local o = baseNew(cls)
			local props = rawget(o, "_props")
			for k, v in pairs(defaults(cls)) do
				if props[k] == nil then
					props[k] = v
				end
			end
			if parent then
				o.Parent = parent
			end
			return o
		end,
	}
	S.Instance = Instance

	-- a member nobody stubbed: callable, indexable, connectable (reads as truthy; a call gives it back)
	local magic
	magic = setmetatable({}, {
		__index = function(_, k)
			if k == "Connect" or k == "Once" or k == "ConnectParallel" then
				return function()
					return { Connected = true, Disconnect = function() end }
				end
			elseif k == "Wait" then
				return function()
					return nil
				end
			end
			return magic
		end,
		__call = function()
			return magic
		end,
		__tostring = function()
			return "magic"
		end,
	})
	S.magic = magic
	local function permissive(t)
		return setmetatable(t, {
			__index = function(_, _k)
				return magic
			end,
		})
	end

	-- the world, the player and the services
	local H = Host.new({ globals = { Instance = Instance, workspace = E.workspace, Workspace = E.workspace } })
	S.host = H
	E.install(H)
	local lp = E.localPlayer
	local lprops = rawget(lp, "_props")
	lprops.UserId, lprops.DisplayName, lprops.AccountAge, lprops.MembershipType = 1, "Tester", 100, Enum.MembershipType.None
	lprops.Character = nil
	lprops.CharacterAdded = sigOf(lp, "CharacterAdded")
	lprops.GetMouse = function()
		return magic
	end
	lprops.Kick = function() end
	lprops.GetFriendsOnline = function()
		return {}
	end
	lprops.IsInGroup = function()
		return false
	end
	lprops.GetRankInGroup = function()
		return 0
	end
	lprops.HasAppearanceLoaded = function()
		return true
	end
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = lp
	S.playerGui = playerGui
	S.player = lp
	local backpack = Instance.new("Folder")
	backpack.Name = "Backpack"
	backpack.Parent = lp
	local camProps = rawget(E.camera, "_props")
	camProps.ViewportSize = nil -- (computed: S.W x S.H)
	local playersProps = H.Service("Players")._props
	playersProps.GetPlayerFromCharacter = function()
		return nil
	end
	playersProps.GetPlayerByUserId = function()
		return nil
	end
	playersProps.GetNameFromUserIdAsync = function()
		return "Tester"
	end
	playersProps.GetUserThumbnailAsync = function()
		return "", true
	end
	playersProps.GetHumanoidDescriptionFromUserId = function()
		return magic
	end
	playersProps.CreateHumanoidModelFromDescription = function()
		return nil
	end
	permissive(playersProps)

	local uis = {
		TouchEnabled = dev.touch == true, KeyboardEnabled = dev.keyboard == true, MouseEnabled = dev.keyboard == true,
		GamepadEnabled = dev.pad == true, VREnabled = false, AccelerometerEnabled = false, GyroscopeEnabled = false,
		MouseBehavior = Enum.MouseBehavior.Default, MouseIconEnabled = true, ModalEnabled = false, OnScreenKeyboardVisible = false,
		MouseDeltaSensitivity = 1,
		GetLastInputType = function()
			return dev.pad and Enum.UserInputType.Gamepad1 or (dev.touch and Enum.UserInputType.Touch or Enum.UserInputType.MouseMovement)
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		IsKeyDown = function()
			return false
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		IsGamepadButtonDown = function()
			return false
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetMouseLocation = function()
			return Vector2.new(S.W / 2, S.H / 2)
		end,
		GetMouseDelta = function()
			return Vector2.zero
		end,
		GetConnectedGamepads = function()
			return dev.pad and { Enum.UserInputType.Gamepad1 } or {}
		end,
		GetNavigationGamepads = function()
			return dev.pad and { Enum.UserInputType.Gamepad1 } or {}
		end,
		GetGamepadConnected = function()
			return dev.pad == true
		end,
		GetGamepadState = function()
			return {}
		end,
		GetSupportedGamepadKeyCodes = function()
			return {}
		end,
		GamepadSupports = function()
			return true
		end,
		GetStringForKeyCode = function(_, k)
			return k and k.Name or ""
		end,
		GetImageForKeyCode = function()
			return ""
		end,
	}
	H.Service("UserInputService")._props = permissive(uis)
	S.selected = nil
	local guiService = {
		GetGuiInset = function()
			return Vector2.new(0, GS.TOPBAR), Vector2.new(0, 0)
		end,
		IsTenFootInterface = function()
			return dev.pad == true
		end,
		AddSelectionParent = function() end, RemoveSelectionGroup = function() end, Select = function() end,
		GuiNavigationEnabled = true, AutoSelectGuiEnabled = true, MenuIsOpen = false, ReducedMotionEnabled = false,
		PreferredTextSize = Enum.PreferredTextSize and Enum.PreferredTextSize.Medium or nil,
		TopbarInset = roblox.Rect.new(GS.TOPBAR_BUTTONS_W, 0, dev.w, GS.TOPBAR),
		CloseInspectMenu = function() end,
	}
	local gsNode = H.Service("GuiService")
	gsNode._props = guiService
	rawset(gsNode, "_any", function(k)
		if k == "SelectedObject" then
			return S.selected
		end
		return magic
	end)
	-- (a write to a host node lands as a raw field and reads back as one)
	H.Service("TextService")._props = permissive({
		GetTextSize = function(_, text, size, font, frame)
			local w, h = GS.TextBounds(text, size, font ~= nil and tostring(font):find("Oswald") ~= nil, frame and frame.X < 9999 and frame.X or nil)
			return Vector2.new(math.ceil(w), math.ceil(h))
		end,
		GetTextBoundsAsync = function(_, params)
			local w, h = GS.TextBounds(params.Text, params.Size, false, params.Width)
			return Vector2.new(math.ceil(w), math.ceil(h))
		end,
	})
	-- tweens land on their goal when played (a layout check sees where things settle); Completed fires next turn
	H.Service("TweenService")._props = permissive({
		Create = function(_, inst, _info, goal)
			local tw = { PlaybackState = Enum.PlaybackState.Begin, Instance = inst }
			local done = FE.Signal()
			tw.Completed = done
			function tw:Play()
				for k, v in pairs(goal) do
					pcall(function()
						inst[k] = v
					end)
				end
				self.PlaybackState = Enum.PlaybackState.Completed
				ltask.defer(function()
					done:Fire(Enum.PlaybackState.Completed)
				end)
			end
			function tw:Cancel()
				self.PlaybackState = Enum.PlaybackState.Cancelled
			end
			function tw:Pause() end
			function tw:Destroy() end
			return tw
		end,
		GetValue = function(_, a)
			return a
		end,
	})
	H.Service("ContextActionService")._props = permissive({
		BindAction = function() end, BindActionAtPriority = function() end, UnbindAction = function() end,
		BindActivate = function() end, UnbindActivate = function() end, SetTitle = function() end, SetImage = function() end,
		SetPosition = function() end, SetDescription = function() end, GetButton = function()
			return nil
		end,
		GetAllBoundActionInfo = function()
			return {}
		end,
		GetBoundActionInfo = function()
			return {}
		end,
	})
	H.Service("StarterGui")._props = permissive({
		SetCoreGuiEnabled = function() end, GetCoreGuiEnabled = function()
			return true
		end,
		SetCore = function() end, GetCore = function()
			return nil
		end,
	})
	local rs = H.Service("RunService")._props
	rs.BindToRenderStep = function() end
	rs.UnbindFromRenderStep = function() end
	rs.PreRender, rs.PreSimulation, rs.PostSimulation, rs.Stepped = FE.Signal(), FE.Signal(), FE.Signal(), FE.Signal()
	rs.IsStudio = function()
		return false
	end
	rs.IsRunning = function()
		return true
	end
	permissive(rs)
	for _, name in ipairs({ "SoundService", "Lighting", "ProximityPromptService", "HapticService", "Debris", "PhysicsService", "ContentProvider",
		"MarketplaceService", "Stats", "LocalizationService", "TeleportService", "SocialService", "BadgeService", "PolicyService", "VRService",
		"Chat", "TextChatService", "AvatarEditorService", "GroupService", "MaterialService", "Teams", "StarterPlayer", "ServerStorage",
		"AnimationClipProvider", "KeyframeSequenceProvider", "InsertService", "SoundService", "UserService", "ExperienceService",
		"ReplicatedFirst", "AssetService", "CaptureService", "UserGameSettings" }) do
		local svc = H.Service(name)
		local props = rawget(svc, "_props") or {}
		rawset(svc, "_props", permissive(props))
	end
	local lighting = rawget(H.Service("Lighting"), "_props")
	lighting.ClockTime, lighting.Brightness, lighting.ExposureCompensation = 14, 2, 0
	lighting.Ambient, lighting.OutdoorAmbient = roblox.Color3.new(0.5, 0.5, 0.5), roblox.Color3.new(0.5, 0.5, 0.5)
	lighting.FogEnd, lighting.FogStart, lighting.GlobalShadows = 100000, 0, true
	lighting.GetChildren = function()
		return {}
	end
	lighting.GetDescendants = function()
		return {}
	end
	lighting.FindFirstChild = function()
		return nil
	end
	lighting.FindFirstChildOfClass = function()
		return nil
	end
	lighting.FindFirstChildWhichIsA = function()
		return nil
	end
	lighting.GetMinutesAfterMidnight = function()
		return 14 * 60
	end
	lighting.SetMinutesAfterMidnight = function() end
	local ppsProps = rawget(H.Service("ProximityPromptService"), "_props")
	ppsProps.Enabled = true
	local stats = rawget(H.Service("Stats"), "_props")
	stats.GetTotalMemoryUsageMb = function()
		return 900
	end
	stats.GetMemoryUsageMbForTag = function()
		return 10
	end
	stats.HeartbeatTimeMs, stats.RenderCPUFrameTime, stats.RenderGPUFrameTime, stats.FrameTime = 2, 0.004, 0.004, 1 / 60
	local ugs = rawget(H.Service("UserGameSettings"), "_props")
	ugs.SavedQualityLevel = Enum.SavedQualitySetting.Automatic
	ugs.MasterVolume = 1
	H.globals.UserSettings = function()
		return { GetService = function()
			return H.Service("UserGameSettings")
		end }
	end
	H.globals.settings = function()
		return permissive({ Rendering = permissive({ QualityLevel = Enum.QualityLevel.Automatic }) })
	end
	-- the remotes (State: Request / Fight / Profile / Notify ...): FireServer / InvokeServer go to S.onFireServer /
	-- S.onInvokeServer; a test fires OnClientEvent through S.remote(name)
	local RS = H.Service("ReplicatedStorage")
	local remotes = Host.NewNode("Remotes", "Folder", RS)
	S.remotes = {}
	local function remote(name, cls)
		local n = Host.NewNode(name, cls or "RemoteEvent", remotes)
		local sig = FE.Signal()
		local inv = FE.Signal()
		n._props = permissive({
			OnClientEvent = sig, OnClientInvoke = inv,
			FireServer = METHODS.FireServer, InvokeServer = METHODS.InvokeServer,
		})
		S.remotes[name] = n
		S.remotes[name .. "Event"] = sig
		return n
	end
	for _, n in ipairs(opts.remotes or { "Request", "Fight", "Profile", "Notify", "Drill", "PvP", "Anatomy", "Hair", "Look", "Gym", "City" }) do
		remote(n, n == "Request" and "RemoteFunction" or "RemoteEvent")
	end
	S.remoteNode = remotes
	S.makeRemote = remote

	-- the workspace's members the client scripts touch
	local ws = rawget(E.workspace, "_props")
	ws.Gravity = 196.2
	ws.DistributedGameTime = 0
	ws.StreamingEnabled = false
	ws.Raycast = function()
		return nil
	end
	ws.Blockcast, ws.Spherecast, ws.Shapecast = ws.Raycast, ws.Raycast, ws.Raycast
	ws.GetPartBoundsInBox = function()
		return {}
	end
	ws.GetPartBoundsInRadius = ws.GetPartBoundsInBox
	ws.GetPartsInPart = ws.GetPartBoundsInBox
	ws.FindPartOnRay = function()
		return nil
	end
	ws.GetServerTimeNow = function()
		return os.time()
	end
	ws.GetRealPhysicsFPS = function()
		return 60
	end
	-- UDim offsets are integers in the engine (a fractional one is truncated); lune's constructors refuse them
	local function int(v)
		v = tonumber(v) or 0
		local i = math.modf(v)
		return i
	end
	local rUDim2, rUDim = roblox.UDim2, roblox.UDim
	H.globals.UDim2 = setmetatable({
		new = function(a, b, c, d)
			if typeof(a) == "UDim" then
				return rUDim2.new(a, b)
			end
			return rUDim2.new(tonumber(a) or 0, int(b), tonumber(c) or 0, int(d))
		end,
		fromOffset = function(x, y)
			return rUDim2.fromOffset(int(x), int(y))
		end,
		fromScale = function(x, y)
			return rUDim2.fromScale(tonumber(x) or 0, tonumber(y) or 0)
		end,
	}, { __index = rUDim2 })
	H.globals.UDim = setmetatable({
		new = function(a, b)
			return rUDim.new(tonumber(a) or 0, int(b))
		end,
	}, { __index = rUDim })
	H.globals.RaycastParams = { new = function()
		return { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude, AddToFilter = function() end }
	end }
	H.globals.OverlapParams = H.globals.RaycastParams
	H.globals.TweenInfo = { new = function(time, style, dir, rep, rev, delay)
		return { Time = time or 1, EasingStyle = style or Enum.EasingStyle.Quad, EasingDirection = dir or Enum.EasingDirection.Out, RepeatCount = rep or 0,
			Reverses = rev or false, DelayTime = delay or 0 }
	end }
	H.globals.DateTime = { now = function()
		return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000, FormatLocalTime = function()
			return ""
		end, ToLocalTime = function()
			return { Year = 2026, Month = 1, Day = 1, Hour = 12, Minute = 0, Second = 0 }
		end }
	end, fromUnixTimestamp = function(t)
		return { UnixTimestamp = t, FormatLocalTime = function()
			return ""
		end, ToLocalTime = function()
			return { Year = 2026, Month = 1, Day = 1, Hour = 12, Minute = 0, Second = 0 }
		end }
	end }
	H.globals.os = setmetatable({ clock = os.clock, time = os.time, date = os.date, difftime = os.difftime }, { __index = os })
	H.globals.SharedTable = nil
	H.globals.version = function()
		return "0.650"
	end
	H.globals.gcinfo = function()
		return 0
	end
	H.globals.shared = {}
	H.globals._G = {}
	H.globals.delay = function(t, f)
		return ltask.delay(t, f)
	end
	H.globals.spawn = function(f)
		return ltask.spawn(f)
	end
	H.globals.wait = function(t)
		return ltask.wait(t or 0)
	end
	H.globals.EditableImage = nil
	H.globals.Path2DControlPoint = nil

	-- a LocalScript of src/ (path relative to src/), run in its own environment with `script` a node under
	-- StarterPlayerScripts (so script.Parent.BoxerClient resolves)
	function S.loadScript(rel)
		local file = H.src .. "/" .. rel
		local base = rel:match("([^/]+)%.client%.luau?$") or rel:match("([^/]+)%.luau?$")
		local SPS = H.client and rawget(H.client, "Parent")
		local node = Host.NewNode(base, "LocalScript", SPS)
		rawset(node, "_file", file)
		local env = table.clone(H.globals)
		env.script = node
		local chunk = luau.load(fs.readFile(file), { debugName = rel, environment = env })
		local ok, err = pcall(chunk)
		if not ok then
			error(string.format("guisim: %s failed: %s", rel, tostring(err)), 0)
		end
		return node
	end
	function S.require(name)
		return H.require(name)
	end

	-- let deferred / delayed threads run (wall seconds), RenderStepped / Heartbeat fired each frame
	function S.settle(seconds)
		local t0 = os.clock()
		repeat
			E.RenderStepped:Fire(1 / 60)
			E.Heartbeat:Fire(1 / 60)
			ltask.wait(1 / 60)
		until os.clock() - t0 >= (seconds or 0.1)
		dirty = true
	end

	--------------------------------------------------------------------
	-- layout
	--------------------------------------------------------------------
	local function P(o, k)
		return rawget(o, "_props")[k]
	end
	local function kidsOf(o)
		return rawget(o, "_kids")
	end
	local function comp(o, cls)
		for _, c in ipairs(kidsOf(o)) do
			if rawget(c, "_class") == cls then
				return c
			end
		end
		return nil
	end
	local function visibleKids(o, sorted, sortOrder)
		local out = {}
		for i, c in ipairs(kidsOf(o)) do
			if GUIOBJ[rawget(c, "_class")] and P(c, "Visible") ~= false then
				out[#out + 1] = { c, i }
			end
		end
		if sorted then
			local byName = sortOrder == Enum.SortOrder.Name
			table.sort(out, function(a, b)
				if byName then
					local na, nb = rawget(a[1], "_name"), rawget(b[1], "_name")
					if na ~= nb then
						return na < nb
					end
				else
					local la, lb = P(a[1], "LayoutOrder") or 0, P(b[1], "LayoutOrder") or 0
					if la ~= lb then
						return la < lb
					end
				end
				return a[2] < b[2]
			end)
		end
		for i, e in ipairs(out) do
			out[i] = e[1]
		end
		return out
	end
	local function res(ud, ref)
		return ud.Scale * ref + ud.Offset
	end
	local function padding(o, w, h)
		local p = comp(o, "UIPadding")
		if not p then
			return 0, 0, 0, 0
		end
		return res(P(p, "PaddingLeft"), w), res(P(p, "PaddingRight"), w), res(P(p, "PaddingTop"), h), res(P(p, "PaddingBottom"), h)
	end
	local isAuto = function(o, axis)
		local a = P(o, "AutomaticSize")
		if a == nil or a == Enum.AutomaticSize.None then
			return false
		end
		return a == Enum.AutomaticSize.XY or (axis == "X" and a == Enum.AutomaticSize.X) or (axis == "Y" and a == Enum.AutomaticSize.Y)
	end

	local memo
	local sizeU -- forward
	-- the content extents of o (its own units) for a box of w x h: text, list / grid content or children's
	-- extents, plus padding; also the list's content size
	local function contentU(o, w, h)
		local l, r, t, b = padding(o, w, h)
		local iw, ih = w - l - r, h - t - b
		local cw, ch = 0, 0
		local cls = rawget(o, "_class")
		if TEXT[cls] then
			local text = P(o, "Text") or ""
			if cls == "TextBox" and text == "" then
				text = P(o, "PlaceholderText") or ""
			end
			if text ~= "" and not P(o, "TextScaled") then
				local wrapAt = (P(o, "TextWrapped") and not isAuto(o, "X")) and iw or nil
				cw, ch = GS.TextBounds(text, P(o, "TextSize") or 14, isCondensed(o), wrapAt)
			end
		end
		local list, grid = comp(o, "UIListLayout"), comp(o, "UIGridLayout")
		local kw, kh = 0, 0
		if list then
			local horiz = P(list, "FillDirection") == Enum.FillDirection.Horizontal
			local kids = visibleKids(o, true, P(list, "SortOrder"))
			local pad = res(P(list, "Padding"), horiz and iw or ih)
			for i, c in ipairs(kids) do
				local a, bb = sizeU(c, iw, ih)
				if horiz then
					kw += a + (i > 1 and pad or 0)
					kh = math.max(kh, bb)
				else
					kh += bb + (i > 1 and pad or 0)
					kw = math.max(kw, a)
				end
			end
		elseif grid then
			local kids = visibleKids(o, true, P(grid, "SortOrder"))
			local cs, cp = P(grid, "CellSize"), P(grid, "CellPadding")
			local cwd, chd = res(cs.X, iw), res(cs.Y, ih)
			local px, py = res(cp.X, iw), res(cp.Y, ih)
			local perRow = math.max(1, math.floor((iw + px) / math.max(1, cwd + px)))
			local maxCells = P(grid, "FillDirectionMaxCells") or 0
			if maxCells > 0 then
				perRow = math.min(perRow, maxCells)
			end
			local rows = math.ceil(#kids / perRow)
			kw = math.min(#kids, perRow) * (cwd + px) - (#kids > 0 and px or 0)
			kh = rows * (chd + py) - (rows > 0 and py or 0)
		else
			for _, c in ipairs(visibleKids(o, false)) do
				local a, bb = sizeU(c, iw, ih)
				local pos, ap = P(c, "Position"), P(c, "AnchorPoint")
				local x0 = res(pos.X, iw) - ap.X * a
				local y0 = res(pos.Y, ih) - ap.Y * bb
				kw = math.max(kw, x0 + a)
				kh = math.max(kh, y0 + bb)
			end
		end
		return math.max(cw, kw) + l + r, math.max(ch, kh) + t + b, kw, kh
	end
	-- o's size in its parent's units for a parent content box pw x ph
	function sizeU(o, pw, ph)
		local m = memo[o]
		if m and m[1] == pw and m[2] == ph then
			return m[3], m[4]
		end
		local s = P(o, "Size") or UDim2.new()
		local w, h = res(s.X, pw), res(s.Y, ph)
		local ax, ay = isAuto(o, "X"), isAuto(o, "Y")
		if ax or ay then
			local cw, ch = contentU(o, ax and math.max(w, 0) or w, h)
			if ax then
				w = math.max(w, cw)
			end
			if ay then
				-- (wrapped text: measured at the final width)
				if ax and TEXT[rawget(o, "_class")] then
					cw, ch = contentU(o, w, h)
				end
				h = math.max(h, ch)
			end
		end
		local sc = comp(o, "UISizeConstraint")
		if sc then
			local mn, mx = P(sc, "MinSize"), P(sc, "MaxSize")
			w = math.clamp(w, mn.X, math.max(mn.X, mx.X))
			h = math.clamp(h, mn.Y, math.max(mn.Y, mx.Y))
		end
		local ar = comp(o, "UIAspectRatioConstraint")
		if ar then
			local k = P(ar, "AspectRatio")
			if P(ar, "AspectType") == Enum.AspectType.ScaleWithParentSize then
				if P(ar, "DominantAxis") == Enum.DominantAxis.Height then
					w = h * k
				else
					h = w / k
				end
			elseif w / math.max(h, 1e-6) > k then
				w = h * k
			else
				h = w / k
			end
		end
		memo[o] = { pw, ph, w, h }
		return w, h
	end

	local rects
	local function intersect(a, b)
		if not a then
			return b
		end
		local x0, y0 = math.max(a[1], b[1]), math.max(a[2], b[2])
		local x1, y1 = math.min(a[3], b[3]), math.min(a[4], b[4])
		return { x0, y0, math.max(x0, x1), math.max(y0, y1) }
	end
	local place -- forward
	local function placeKids(o, ox, oy, iw, ih, unit, clip, gui)
		local list, grid = comp(o, "UIListLayout"), comp(o, "UIGridLayout")
		if list then
			local horiz = P(list, "FillDirection") == Enum.FillDirection.Horizontal
			local kids = visibleKids(o, true, P(list, "SortOrder"))
			local pad = res(P(list, "Padding"), horiz and iw or ih)
			local sizes, total, cross = {}, 0, 0
			for i, c in ipairs(kids) do
				local a, b = sizeU(c, iw, ih)
				sizes[i] = { a, b }
				total += (horiz and a or b) + (i > 1 and pad or 0)
				cross = math.max(cross, horiz and b or a)
			end
			local ha, va = P(list, "HorizontalAlignment"), P(list, "VerticalAlignment")
			local mainAvail = horiz and iw or ih
			local k = 0
			if horiz then
				k = ha == Enum.HorizontalAlignment.Center and 0.5 or (ha == Enum.HorizontalAlignment.Right and 1 or 0)
			else
				k = va == Enum.VerticalAlignment.Center and 0.5 or (va == Enum.VerticalAlignment.Bottom and 1 or 0)
			end
			local cur = (mainAvail - total) * k
			for i, c in ipairs(kids) do
				local a, b = sizes[i][1], sizes[i][2]
				local x, y
				if horiz then
					local kc = va == Enum.VerticalAlignment.Center and 0.5 or (va == Enum.VerticalAlignment.Bottom and 1 or 0)
					x, y = cur, (ih - b) * kc
					cur += a + pad
				else
					local kc = ha == Enum.HorizontalAlignment.Center and 0.5 or (ha == Enum.HorizontalAlignment.Right and 1 or 0)
					x, y = (iw - a) * kc, cur
					cur += b + pad
				end
				place(c, ox, oy, iw, ih, unit, clip, gui, { x, y, a, b })
			end
			return horiz and total or cross, horiz and cross or total
		elseif grid then
			local kids = visibleKids(o, true, P(grid, "SortOrder"))
			local cs, cp = P(grid, "CellSize"), P(grid, "CellPadding")
			local cwd, chd = res(cs.X, iw), res(cs.Y, ih)
			local px, py = res(cp.X, iw), res(cp.Y, ih)
			local perRow = math.max(1, math.floor((iw + px) / math.max(1, cwd + px)))
			local maxCells = P(grid, "FillDirectionMaxCells") or 0
			if maxCells > 0 then
				perRow = math.min(perRow, maxCells)
			end
			local ha = P(grid, "HorizontalAlignment")
			local rowW = math.min(#kids, perRow) * (cwd + px) - px
			local x0 = ha == Enum.HorizontalAlignment.Center and (iw - rowW) / 2 or (ha == Enum.HorizontalAlignment.Right and (iw - rowW) or 0)
			for i, c in ipairs(kids) do
				local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
				place(c, ox, oy, iw, ih, unit, clip, gui, { x0 + col * (cwd + px), row * (chd + py), cwd, chd })
			end
			local rows = math.ceil(#kids / perRow)
			return rowW, rows * (chd + py) - py
		end
		local kw, kh = 0, 0
		for _, c in ipairs(visibleKids(o, false)) do
			local r = place(c, ox, oy, iw, ih, unit, clip, gui)
			if r then
				kw = math.max(kw, (r.x - ox) / unit + r.w / unit)
				kh = math.max(kh, (r.y - oy) / unit + r.h / unit)
			end
		end
		return kw, kh
	end
	-- o in a parent content box at (ox, oy) screen px, pw x ph units, `unit` screen px per unit; fixed = { x, y,
	-- w, h } from a list / grid (units, relative to the box)
	function place(o, ox, oy, pw, ph, unit, clip, gui, fixed)
		local w, h, x, y
		if fixed then
			x, y, w, h = fixed[1], fixed[2], fixed[3], fixed[4]
		else
			w, h = sizeU(o, pw, ph)
			local pos, ap = P(o, "Position") or UDim2.new(), P(o, "AnchorPoint") or Vector2.zero
			x = res(pos.X, pw) - ap.X * w
			y = res(pos.Y, ph) - ap.Y * h
		end
		local sx, sy, sw, sh = ox + x * unit, oy + y * unit, w * unit, h * unit
		local own = unit
		local scale = comp(o, "UIScale")
		if scale then
			local k = P(scale, "Scale") or 1
			local ap = P(o, "AnchorPoint") or Vector2.zero
			local axp, ayp = sx + ap.X * sw, sy + ap.Y * sh
			sw, sh = sw * k, sh * k
			sx, sy = axp - ap.X * sw, ayp - ap.Y * sh
			own = unit * k
		end
		local r = { x = sx, y = sy, w = sw, h = sh, unit = own, clip = clip, gui = gui }
		rects[o] = r
		local l, rr, t, b = padding(o, w, h)
		local iw, ih = w - l - rr, h - t - b
		local kidClip = clip
		local cls = rawget(o, "_class")
		if cls == "ScrollingFrame" or P(o, "ClipsDescendants") then
			kidClip = intersect(clip, { sx, sy, sx + sw, sy + sh })
		end
		if cls == "ScrollingFrame" then
			local cs = P(o, "CanvasSize") or UDim2.new()
			local cwU, chU = res(cs.X, w), res(cs.Y, h)
			local auto = P(o, "AutomaticCanvasSize")
			local _, _, kw, kh = contentU(o, iw, ih)
			if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
				chU = math.max(chU, kh + t + b)
			end
			if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
				cwU = math.max(cwU, kw + l + rr)
			end
			cwU = math.max(cwU, w)
			r.canvasH = chU * own
			local cp = P(o, "CanvasPosition") or Vector2.zero
			local cw2, ch2 = cwU - l - rr, math.max(chU, h) - t - b
			local kw2, kh2 = placeKids(o, sx + l * own - cp.X, sy + t * own - cp.Y, cw2, ch2, own, kidClip, gui)
			r.content = { kw2, kh2 }
		else
			local kw2, kh2 = placeKids(o, sx + l * own, sy + t * own, iw, ih, own, kidClip, gui)
			r.content = { kw2, kh2 }
		end
		return r
	end

	-- the area a ScreenGui lays out in (screen px)
	function S.guiRect(g)
		local safe = dev.safe or {}
		local insets = P(g, "ScreenInsets")
		local x0, y0, x1, y1 = 0, 0, S.W, S.H
		if insets ~= Enum.ScreenInsets.None then
			x0, x1, y1 = safe.l or 0, S.W - (safe.r or 0), S.H - (safe.b or 0)
			y0 = safe.t or 0
		end
		if not P(g, "IgnoreGuiInset") and insets ~= Enum.ScreenInsets.None and insets ~= Enum.ScreenInsets.DeviceSafeInsets then
			y0 = math.max(y0, GS.TOPBAR)
		end
		return x0, y0, x1 - x0, y1 - y0
	end
	function layout()
		dirty = false
		memo = {}
		rects = {}
		L = rects
		for _, g in ipairs(kidsOf(playerGui)) do
			if rawget(g, "_class") == "ScreenGui" then
				local x, y, w, h = S.guiRect(g)
				rects[g] = { x = x, y = y, w = w, h = h, unit = 1, gui = g }
				local kw, kh = placeKids(g, x, y, w, h, 1, nil, g)
				rects[g].content = { kw, kh }
			end
		end
	end
	function S.layout()
		layout()
		return rects
	end
	function S.rect(o)
		return rectOf(o)
	end

	--------------------------------------------------------------------
	-- what is on the screen
	--------------------------------------------------------------------
	local function pathOf(o)
		local names = {}
		local n = o
		while n and rawget(n, "_class") ~= "PlayerGui" do
			table.insert(names, 1, rawget(n, "_name"))
			n = rawget(n, "_parent")
		end
		return table.concat(names, ".")
	end
	S.pathOf = pathOf
	-- does o draw anything (a background, text, an image, a stroke)?
	local function draws(o)
		local cls = rawget(o, "_class")
		if (P(o, "BackgroundTransparency") or 0) < 0.99 then
			return true
		end
		if TEXT[cls] and (P(o, "Text") or "") ~= "" and (P(o, "TextTransparency") or 0) < 0.99 then
			return true
		end
		if (cls == "ImageLabel" or cls == "ImageButton") and (P(o, "Image") or "") ~= "" and (P(o, "ImageTransparency") or 0) < 0.99 then
			return true
		end
		if cls == "ViewportFrame" then
			return true
		end
		local st = comp(o, "UIStroke")
		if st and (P(st, "Transparency") or 0) < 0.99 and (P(st, "Enabled") ~= false) then
			return true
		end
		return false
	end
	S.draws = draws
	-- every GuiObject on the screen (enabled ScreenGuis, visible chain), with its rect, its clip and flags
	function S.collect()
		layout()
		local out = {}
		local function walk(o, gui, depth, groupT)
			for _, c in ipairs(kidsOf(o)) do
				local cls = rawget(c, "_class")
				if GUIOBJ[cls] and P(c, "Visible") ~= false then
					local r = rects[c]
					if r then
						local gt = groupT
						if cls == "CanvasGroup" then
							gt = math.max(gt, P(c, "GroupTransparency") or 0)
						end
						local item = {
							obj = c, class = cls, name = rawget(c, "_name"), path = pathOf(c), gui = gui, depth = depth,
							x = r.x, y = r.y, w = r.w, h = r.h, unit = r.unit, clip = r.clip, draws = draws(c) and gt < 0.99,
							button = (cls == "TextButton" or cls == "ImageButton" or cls == "TextBox"),
							active = P(c, "Active") == true, selectable = P(c, "Selectable") == true,
							text = TEXT[cls] and (P(c, "Text") or "") or nil, textSize = TEXT[cls] and P(c, "TextSize") or nil,
							z = P(c, "ZIndex") or 1, displayOrder = P(gui, "DisplayOrder") or 0,
						}
						-- the part a clip leaves on the screen
						if r.clip then
							local cx0, cy0 = math.max(r.x, r.clip[1]), math.max(r.y, r.clip[2])
							local cx1, cy1 = math.min(r.x + r.w, r.clip[3]), math.min(r.y + r.h, r.clip[4])
							item.visibleW, item.visibleH = math.max(0, cx1 - cx0), math.max(0, cy1 - cy0)
						else
							item.visibleW, item.visibleH = r.w, r.h
						end
						out[#out + 1] = item
						walk(c, gui, depth + 1, gt)
					end
				end
			end
		end
		local guis = {}
		for i, g in ipairs(kidsOf(playerGui)) do
			if rawget(g, "_class") == "ScreenGui" and P(g, "Enabled") ~= false then
				table.insert(guis, { g, i })
			end
		end
		-- drawn in DisplayOrder (then creation order), each ScreenGui's objects in tree order
		table.sort(guis, function(a, b)
			local da, db = P(a[1], "DisplayOrder") or 0, P(b[1], "DisplayOrder") or 0
			if da ~= db then
				return da < db
			end
			return a[2] < b[2]
		end)
		for _, e in ipairs(guis) do
			walk(e[1], e[1], 1, 0)
		end
		-- a modal shade (an Active frame over most of the screen, as UI.Window's) takes the input and the eye:
		-- what is drawn before it, outside it, is marked blocked (the checks pass over it)
		for i, it in ipairs(out) do
			it.order = i
		end
		local modals = {}
		for _, it in ipairs(out) do
			local _, _, gw, gh = S.guiRect(it.gui)
			if it.active and it.class == "Frame" and it.w * it.h >= 0.85 * gw * gh then
				table.insert(modals, it)
			end
		end
		for _, m in ipairs(modals) do
			for _, it in ipairs(out) do
				if it.order < m.order and not it.obj:IsDescendantOf(m.obj) then
					it.blocked = true
				end
			end
		end
		return out
	end

	-- the checks. opts:
	--   touch (default dev.touch): buttons smaller than GS.TOUCH_PX on the screen are reported
	--   ignore = fn(item) -> true to skip an item (decoration known to bleed, e.g. a full-bleed wipe)
	--   tolerance (px, default 1)
	function S.checks(items, opts2)
		opts2 = opts2 or {}
		local tol = opts2.tolerance or 1
		local touch = opts2.touch
		if touch == nil then
			touch = dev.touch == true
		end
		local out = { offscreen = {}, topbar = {}, touch = {}, text = {}, small = {} }
		for _, it in ipairs(items) do
			if not it.blocked and not (opts2.ignore and opts2.ignore(it)) and it.visibleW > 0.5 and it.visibleH > 0.5 then
				local x0, y0, x1, y1 = it.x, it.y, it.x + it.w, it.y + it.h
				if it.clip then
					x0, y0 = math.max(x0, it.clip[1]), math.max(y0, it.clip[2])
					x1, y1 = math.min(x1, it.clip[3]), math.min(y1, it.clip[4])
				end
				-- off the screen: something that draws or takes input, outside the screen
				if (it.draws or it.button) and (x0 < -tol or y0 < -tol or x1 > S.W + tol or y1 > S.H + tol) then
					-- a full-screen backdrop larger than the screen is fine; a piece that is mostly on the screen
					-- and bleeds a few px is still reported (with its overhang)
					table.insert(out.offscreen, { item = it, over = math.max(-x0, -y0, x1 - S.W, y1 - S.H) })
				end
				-- under the top bar's buttons (a ScreenGui that ignores the inset): text and buttons
				local safe = dev.safe or {}
				local barX1 = (safe.l or 0) + GS.TOPBAR_BUTTONS_W
				if (it.button or (it.text and it.text ~= "" and it.draws)) and y0 < GS.TOPBAR - tol and x0 < barX1 - tol and x1 > (safe.l or 0) then
					table.insert(out.topbar, { item = it })
				end
				-- touch targets: a button that takes input (Active, or a TextButton with handlers) under a fingertip
				if touch and it.button and it.class ~= "TextBox" and (math.min(it.w, it.h) < GS.TOUCH_PX - tol) then
					table.insert(out.touch, { item = it, size = math.min(it.w, it.h) })
				end
				-- text: a single line wider than its box (no truncation, not scaled, not wrapped)
				if it.text and it.text ~= "" and it.draws and it.class ~= "TextBox" then
					local o = it.obj
					if not P(o, "TextScaled") and not P(o, "TextWrapped") and P(o, "TextTruncate") == Enum.TextTruncate.None and not P(o, "RichText") then
						local tw = GS.LineWidth(it.text:match("^[^\n]*"), it.textSize, isCondensed(o)) * it.unit
						local l, rr = 0, 0
						local pad = comp(o, "UIPadding")
						if pad then
							l, rr = res(P(pad, "PaddingLeft"), it.w / it.unit) * it.unit, res(P(pad, "PaddingRight"), it.w / it.unit) * it.unit
						end
						local room = it.w - l - rr
						if tw > room * 1.12 + 4 and not isAuto(o, "X") then
							table.insert(out.text, { item = it, need = tw, room = room })
						end
					end
					local px = it.textSize * it.unit
					if px < (opts2.minText or 10.5) then
						table.insert(out.small, { item = it, px = px })
					end
				end
			end
		end
		return out
	end

	-- rects overlapping (screen px); a, b items or { x, y, w, h }
	function GS.Overlap(a, b, margin)
		margin = margin or 0
		return a.x < b.x + b.w - margin and b.x < a.x + a.w - margin and a.y < b.y + b.h - margin and b.y < a.y + a.h - margin
	end

	return S
end

-- the boxes of a collect() for tools/sim/ui_preview.py: { w, h, device, topbar, safe, guis = [...], items = [...] }
function GS.WriteBoxes(path, S, items, extra)
	local list = {}
	for _, it in ipairs(items) do
		if it.visibleW > 0.5 and it.visibleH > 0.5 and (it.draws or it.button) then
			list[#list + 1] = {
				x = math.floor(it.x * 10 + 0.5) / 10, y = math.floor(it.y * 10 + 0.5) / 10, w = math.floor(it.w * 10 + 0.5) / 10, h = math.floor(it.h * 10 + 0.5) / 10,
				clip = it.clip, class = it.class, name = it.name, path = it.path, button = it.button, depth = it.depth, z = it.z,
				order = it.displayOrder, text = it.text and it.text:sub(1, 160) or nil,
				textSize = it.textSize and it.textSize * it.unit or nil,
				bad = extra and extra.bad and extra.bad[it.obj] or nil, blocked = it.blocked or nil, seq = it.order,
				bgT = rawget(it.obj, "_props").BackgroundTransparency,
				align = it.text and tostring(rawget(it.obj, "_props").TextXAlignment):match("(%a+)$") or nil,
				-- the width the text takes on the screen (as measured here) and whether it is cut short
				textW = (it.text and it.text ~= "" and it.textSize) and math.floor(GS.LineWidth(it.text:match("^[^\n]*"), it.textSize, isCondensed(it.obj)) * it.unit) or nil,
				truncate = it.text and rawget(it.obj, "_props").TextTruncate ~= Enum.TextTruncate.None or nil,
				wrapped = it.text and (rawget(it.obj, "_props").TextWrapped == true) or nil,
			}
		end
	end
	local doc = { w = S.W, h = S.H, device = S.name, topbar = GS.TOPBAR, topbarButtonsW = GS.TOPBAR_BUTTONS_W, safe = S.device.safe, items = list,
		title = extra and extra.title or nil }
	fs.writeFile(path, serde.encode("json", doc, false))
end

return GS
