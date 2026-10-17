-- ControlsMenu: the Moves & Controls window. Opened from the main menu (CONTROLS, or Settings > Controls),
-- the Career Hub (State.open.Controls), anywhere with the backquote key, and a fight (Tab or `, hold VIEW
-- on a pad, the MOVES pad on touch; a career fight or a spar pauses while it is open). The menu's own key
-- closes it again.
--   MOVES       Basic, Punches, Advanced and Special moves with the key / button / touch glyph of the device
--               shown (a cycler picks the device; it starts on the one in use), what each move does and when
--               to use it; special moves say whether they are unlocked and how to unlock them (Moves.lua)
--   KEYBOARD    rebind any action: click a key cap, press the key (a second key while one is held makes a
--               chord, two quick taps a double tap, Backspace clears the slot, Escape cancels). A key that
--               another action holds is swapped over, so no two actions share a key. Two slots per action.
--   CONTROLLER  the same for the pad (press a button, hold one and press another for a chord, flick the
--               right stick for a flick; B cancels). One slot per action.
--   CONSOLE     aim assist (Off / Low / High), vibration on / off and strength, a test rumble.
-- Everything is saved through Settings (SaveSettings; the server sanitizes the map with Keymap.Sanitize).
-- Controller-navigable: the window is a selection group (D-pad / left stick moves, A presses, B closes, the
-- right stick scrolls); a key cap takes the selection first.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Keymap = require(Shared:WaitForChild("Keymap"))
local Moves = require(Shared:WaitForChild("Moves"))
local Modules = script.Parent
local State = require(Modules:WaitForChild("State"))
local Settings = require(Modules:WaitForChild("Settings"))
local Gamepad = UI.Gamepad
local T = UI.Theme
local K = Enum.KeyCode

local ControlsMenu = {}
local player = Players.LocalPlayer

local gui, root, content, tabs, setTab
local isOpen = false
local openedAt, closedAt = 0, -10 -- (the press that opened / closed the window must not close / open it again)
local onCloseFn
local conns = {}
local tab = "moves"
local device = "keyboard" -- the device the MOVES tab shows ("keyboard" | "gamepad" | "touch")
local capture = nil -- { id, device, slot, label, token, held, pending, pendingAt }
-- while a capture is on, every key / mouse button / pad input is taken through ContextActionService and
-- sunk (bindCapture / unbindCapture below), so the game's own hotkeys see it as processed
local bindCapture, unbindCapture
local captureBound = false
local DEVICES = { "keyboard", "gamepad", "touch" }
local DEVICE_NAME = { keyboard = "Keyboard & mouse", gamepad = "Controller", touch = "Touch" }

local function track(c)
	table.insert(conns, c)
	return c
end

local function map()
	return Settings.Keymap()
end

local function labelOf(id)
	local a = Keymap.ById[id]
	return a and a.label or id
end

-- the key caps of one action on a device, as texts
local function capTexts(id, dev)
	local a = Keymap.ById[id]
	if not a then
		return { "-" }
	end
	if dev == "touch" then
		return { a.touch or "-" }
	elseif dev == "gamepad" then
		return { Keymap.ActionText(map(), id, "pad", Gamepad) }
	end
	if a.fixed then
		return { a.kbd[1] }
	end
	local out = {}
	for _, b in ipairs(map().kbd[id] or {}) do
		table.insert(out, Keymap.Label(b, Gamepad))
	end
	if #out == 0 then
		out[1] = "-"
	end
	return out
end

local function keycap(parent, text, order, color)
	local cap = UI.Frame(parent, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color or T.panel2, BackgroundTransparency = 0.1, LayoutOrder = order })
	UI.Corner(cap, 4)
	UI.Stroke(cap, Color3.new(1, 1, 1), 1, 0.8)
	local t = UI.Text(cap, text, { Font = T.semi, TextSize = 12, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	UI.Pad(t, 0, 8)
	return cap, t
end

------------------------------------------------------------------------
-- MOVES tab
------------------------------------------------------------------------
local function movesTab()
	local small = UI.CanvasSize(gui).Y < 560
	local devRow = UI.Cycler(content, "Show the controls for", DEVICES, device, function(v)
		device = v
		setTab("moves")
	end, function(v)
		return DEVICE_NAME[v] or v
	end)
	devRow.LayoutOrder = 1
	UI.PadStart(devRow)
	local info = Moves.Info(State.P)
	local unlocked = Moves.Unlocked(info)
	local order = 1
	for _, sec in ipairs(Keymap.Sections) do
		order += 1
		local h = UI.Header(content, sec.title)
		h.Parent.LayoutOrder = order
		order += 1
		UI.Text(content, sec.blurb, { TextSize = 13, TextColor3 = T.sub, LayoutOrder = order })
		for _, a in ipairs(Keymap.Actions) do
			if a.section == sec.id then
				order += 1
				local M = a.special and Moves.Data[a.special]
				local isUnlocked = M and unlocked[a.special] == true
				local card = UI.Card(content, { order = order, pad = 10, gap = 4, stroke = (M and isUnlocked) and T.gold or nil, transparency = 0.25 })
				local head = UI.Frame(card, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1 })
				UI.Text(head, (M and M.name or a.label):upper(), { Face = "displayMed", TextSize = small and 15 or 17, Size = UDim2.new(0.55, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
				local caps = UI.Frame(head, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 1), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X })
				UI.List(caps, 6, true, Enum.HorizontalAlignment.Right)
				if M then
					keycap(caps, isUnlocked and "UNLOCKED" or "LOCKED", 0, isUnlocked and T.green or T.red)
				end
				for i, text in ipairs(capTexts(a.id, device)) do
					keycap(caps, text, i)
				end
				local desc = M and M.desc or a.desc
				if desc then
					UI.Text(card, desc, { TextSize = 13, TextColor3 = T.text, LayoutOrder = 2 })
				end
				local how = M and M.how or a.how
				if how then
					UI.Text(card, how, { TextSize = 12, TextColor3 = T.sub, LayoutOrder = 3 })
				end
				if M then
					local by = Moves.UnlockedBy(a.special, info)
					UI.Text(card, (isUnlocked and ("Unlocked: " .. tostring(by)) or ("Unlock: " .. Moves.UnlockText(a.special))), { TextSize = 12, TextColor3 = isUnlocked and T.green or T.gold, LayoutOrder = 4 })
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Remapping (KEYBOARD / CONTROLLER tabs)
------------------------------------------------------------------------
local function endCapture()
	if not capture then
		return
	end
	local c = capture
	capture = nil
	unbindCapture()
	-- the kit's window keys come back a step later: the Escape / B that ended this capture is still being
	-- handed to the other InputBegan listeners (UI.padInput would read it as the window's close)
	task.defer(function()
		if not capture then
			UI.PadHold("ControlsCapture", false) -- (the kit's own selection comes back on a pad)
		end
	end)
	if c.label and c.label.Parent then
		c.label.Text = c.oldText or "-"
		c.label.TextColor3 = Color3.new(1, 1, 1)
	end
	if c.cap and c.cap.Parent then
		c.cap.BackgroundColor3 = T.panel2
	end
end

-- a binding goes into an action's slot: whoever else held it takes this slot's old binding (a swap), so
-- no two actions share a key; then the custom map is saved and the tab rebuilt
local function assign(id, dev, slot, b)
	local m = map()
	local new = { kbd = {}, pad = {} }
	for k, list in pairs(m.kbd) do
		new.kbd[k] = table.clone(list)
	end
	for k, v in pairs(m.pad) do
		new.pad[k] = v
	end
	local swapped = nil
	if dev == "kbd" then
		local list = new.kbd[id] or {}
		local old = list[slot]
		for _, holder in ipairs(Keymap.Holders(new, "kbd", b, id)) do
			local hl = new.kbd[holder]
			local i = table.find(hl, b)
			if i then
				if old and not table.find(hl, old) then
					hl[i] = old
				else
					table.remove(hl, i)
				end
				swapped = holder
			end
		end
		if b then
			if slot > #list then
				table.insert(list, b) -- the second cap of an action with no key yet: no hole for ipairs to stop at
			else
				list[slot] = b
			end
		elseif slot <= #list then
			table.remove(list, slot)
		end
		-- no holes, no duplicates
		local clean = {}
		for _, v in ipairs(list) do
			if v and not table.find(clean, v) then
				table.insert(clean, v)
			end
		end
		new.kbd[id] = clean
	else
		local old = new.pad[id]
		for _, holder in ipairs(Keymap.Holders(new, "pad", b, id)) do
			new.pad[holder] = old
			swapped = holder
		end
		new.pad[id] = b
	end
	Settings.Set("keymap", Keymap.Diff(new))
	if swapped then
		State.toast(string.format("%s now has %s's old key.", labelOf(swapped), labelOf(id)), T.gold)
	end
	setTab(tab, { id = id, slot = slot })
end

local function commit(b)
	local c = capture
	if not c then
		return
	end
	if b ~= nil and not Keymap.Valid(b, c.device) then
		State.toast("That key can't be bound.", T.red)
		return
	end
	endCapture()
	assign(c.id, c.device, c.slot, b)
end

local function beginCapture(id, dev, slot, cap, label)
	endCapture()
	capture = { id = id, device = dev, slot = slot, cap = cap, label = label, oldText = label.Text, held = {}, token = 0 }
	label.Text = dev == "pad" and "PRESS A BUTTON" or "PRESS A KEY"
	label.TextColor3 = T.ink
	cap.BackgroundColor3 = T.gold
	bindCapture()
	-- the UI kit's window keys are paused for the capture: Escape / B / Backspace are bindings (or the
	-- capture's own cancel) here, not the window's close, and the pad's own UI selection would re-press
	-- this very cap on A (UI.PadHold clears the selection too)
	UI.PadHold("ControlsCapture", true)
	pcall(function()
		GuiService.SelectedObject = nil
	end)
end

-- the key names a capture reads
local function captureName(input)
	local it = input.UserInputType
	if it == Enum.UserInputType.MouseButton1 then
		return "MouseButton1", "kbd"
	elseif it == Enum.UserInputType.MouseButton2 then
		return "MouseButton2", "kbd"
	elseif it == Enum.UserInputType.MouseButton3 then
		return "MouseButton3", "kbd"
	end
	local k = input.KeyCode
	if k.Value == 0 then
		return nil -- no key (KeyCode 0 is Unknown / None depending on the API version)
	end
	return k.Name, Keymap.IsPadKeyName(k.Name) and "pad" or "kbd"
end

local function captureBegan(input)
	local c = capture
	if not c then
		return
	end
	local name, dev = captureName(input)
	if not name then
		return
	end
	if name == "Escape" or name == "ButtonB" then
		endCapture()
		return
	end
	if dev ~= c.device then
		return
	end
	if name == "Backspace" then
		commit(nil) -- clears the slot
		return
	end
	-- a key held while another goes down: a chord
	for held in pairs(c.held) do
		if held ~= name then
			commit(held .. "+" .. name)
			return
		end
	end
	c.held[name] = true
	-- two quick taps of one key: a double tap; else the plain key once the tap window has passed
	if c.pending == name and os.clock() - (c.pendingAt or 0) < 0.32 then
		commit("2x" .. name)
		return
	end
	c.pending, c.pendingAt = name, os.clock()
	c.token += 1
	local token = c.token
	task.delay(0.33, function()
		if capture == c and c.token == token and c.pending == name then
			commit(name)
		end
	end)
end

local function captureEnded(input)
	local c = capture
	if not c then
		return
	end
	local name = captureName(input)
	if name then
		c.held[name] = nil
	end
end

local flick = Gamepad and Gamepad.Flick()
local FLICK_KEY = { L = "Thumbstick2Left", R = "Thumbstick2Right", U = "Thumbstick2Up", D = "Thumbstick2Down" }
local function captureChanged(input)
	local c = capture
	if not (c and c.device == "pad" and flick and input.KeyCode == K.Thumbstick2) then
		return
	end
	local dir = flick:Update(input.Position.X, input.Position.Y, os.clock())
	if dir then
		local name = FLICK_KEY[dir]
		for held in pairs(c.held) do
			commit(held .. "+" .. name)
			return
		end
		commit(name)
	end
end

-- The capture binding: every keyboard key, the three mouse buttons and the whole gamepad, at a priority
-- above the fight's pad binding, sunk. Without it ClientMain's hotkeys (H the Hub, P the PvP panel, M the
-- main menu) and the fight's keys would fire on the very press being captured (the PvP panel closes every
-- window, this one included), and H / P / M could never be bound. The UserInputService handlers below stay
-- as the fallback when the bind fails.
local CAPTURE_ACTION = "BoxerControlsCapture"
local CAPTURE_INPUTS = {
	Enum.UserInputType.Keyboard, Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3,
	Enum.UserInputType.Gamepad1,
}
local function captureAction(_, state, input)
	if not capture then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		captureBegan(input)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		captureEnded(input)
	elseif state == Enum.UserInputState.Change then
		captureChanged(input)
	end
	return Enum.ContextActionResult.Sink
end

bindCapture = function()
	if captureBound then
		return
	end
	captureBound = pcall(function()
		ContextActionService:BindActionAtPriority(CAPTURE_ACTION, captureAction, false, Enum.ContextActionPriority.High.Value + 1, table.unpack(CAPTURE_INPUTS))
	end)
end

unbindCapture = function()
	if not captureBound then
		return
	end
	captureBound = false
	pcall(ContextActionService.UnbindAction, ContextActionService, CAPTURE_ACTION)
end

local function remapTab(dev)
	local m = map()
	local conflicts = Keymap.Conflicts(m)
	local clash = {}
	for _, cf in ipairs(conflicts) do
		if cf.device == dev then
			clash[cf.a] = cf.b
			clash[cf.b] = cf.a
		end
	end
	local order = 1
	UI.Text(content, dev == "kbd" and "Click a key cap and press the new key. Hold one key and press another for a chord, tap a key twice for a double tap. BACKSPACE clears the slot, ESC cancels. A key another action uses is swapped over."
		or "Select a button cap and press the new button. Hold a button and press another for a chord, flick the right stick for a flick. " .. (Gamepad and Gamepad.Label(K.ButtonB) or "B") .. " cancels.",
		{ TextSize = 13, TextColor3 = T.sub, LayoutOrder = order })
	if #conflicts > 0 then
		order += 1
		UI.Text(content, string.format("%d conflict%s: two actions on one key are shown in red. Rebind one of them.", #conflicts, #conflicts == 1 and "" or "s"), { TextSize = 13, TextColor3 = T.red, LayoutOrder = order })
	end
	local first = true
	for _, sec in ipairs(Keymap.Sections) do
		order += 1
		UI.Header(content, sec.title).Parent.LayoutOrder = order
		for _, a in ipairs(Keymap.Actions) do
			if a.section == sec.id and not a.fixed and not (dev == "pad" and a.padFixed) then
				order += 1
				local row = UI.Frame(content, { Name = "Row_" .. a.id, Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = T.panel, BackgroundTransparency = 0.35, LayoutOrder = order })
				UI.Corner(row, UI.R.md)
				if clash[a.id] then
					UI.Stroke(row, T.red, 1.5, 0.2)
				end
				UI.Text(row, a.label .. (clash[a.id] and ("   (also " .. labelOf(clash[a.id]) .. ")") or ""), { Font = T.semi, TextSize = 14, TextColor3 = clash[a.id] and T.red or T.text, Position = UDim2.fromOffset(14, 0),
					Size = UDim2.new(0.5, -14, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
				local caps = UI.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
				UI.List(caps, 6, true, Enum.HorizontalAlignment.Right)
				local slots = dev == "kbd" and 2 or 1
				for slot = 1, slots do
					-- (not `dev == "kbd" and x or y`: an empty keyboard slot must read "-", not the pad's button)
					local b
					if dev == "kbd" then
						b = (m.kbd[a.id] or {})[slot]
					else
						b = m.pad[a.id]
					end
					local text = b and Keymap.Label(b, Gamepad) or "-"
					local btn = UI.Button(caps, text, { Name = "Cap" .. slot, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 12, LayoutOrder = slot,
						BackgroundColor3 = T.panel2 })
					UI.Pad(btn, 0, 10)
					btn.TextColor3 = clash[a.id] and T.red or Color3.new(1, 1, 1)
					btn.MouseButton1Click:Connect(function()
						beginCapture(a.id, dev, slot, btn, btn)
					end)
					if first then
						UI.PadStart(btn)
						first = false
					end
				end
				-- back to this action's default on this device
				local reset = UI.Button(caps, "", { Name = "Reset", Size = UDim2.fromOffset(30, 30), LayoutOrder = 9, BackgroundColor3 = T.panel2, BackgroundTransparency = 0.3 }, function()
					local def = Keymap.Default()
					local new = Keymap.Resolve(Settings.Values.keymap)
					if dev == "kbd" then
						new.kbd[a.id] = def.kbd[a.id]
					else
						new.pad[a.id] = def.pad[a.id]
					end
					Settings.Set("keymap", Keymap.Diff(new))
					setTab(tab, { id = a.id, slot = "Reset" })
				end)
				UI.Icon(reset, "reset", 12, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			end
		end
	end
	order += 1
	UI.Button(content, "RESET ALL TO DEFAULTS", { Size = UDim2.fromOffset(260, 40), LayoutOrder = order }, function()
		Settings.Set("keymap", {})
		State.toast("Controls back to the defaults.", T.gold)
		setTab(tab)
	end)
end

------------------------------------------------------------------------
-- CONSOLE tab
------------------------------------------------------------------------
local function consoleTab()
	local v = Settings.Values
	local order = 0
	local function add(f)
		order += 1
		f.LayoutOrder = order
		return f
	end
	add(UI.Header(content, "Aim assist (controller)").Parent)
	add(UI.Text(content, "On a gamepad the left stick is read relative to the opponent: up closes the distance, sideways circles him. The server adds a small accuracy forgiveness to punches thrown from a pad (Low 2 points, High 4). It never applies to a keyboard or touch.", { TextSize = 13, TextColor3 = T.sub }))
	local assistRow = UI.Cycler(content, "Aim assist", Settings.AimAssists, v.aimAssist, function(x)
		Settings.Set("aimAssist", x)
	end)
	add(assistRow)
	UI.PadStart(assistRow)
	add(UI.Header(content, "Vibration").Parent)
	add(UI.Toggle(content, "Controller vibration (hits taken and landed, knockdowns)", v.vibration, function(on)
		Settings.Set("vibration", on)
	end))
	add(UI.Slider(content, "Vibration strength", 0, 1, v.vibrationStrength, 0.05, function(x)
		Settings.Set("vibrationStrength", x)
	end, function(x)
		return string.format("%d%%", math.floor(x * 100 + 0.5))
	end, { default = Settings.Defaults.vibrationStrength, words = function(x)
		return x < 0.01 and "Off" or (x < 0.4 and "Light" or (x < 0.8 and "Medium" or "Strong"))
	end }))
	add(UI.Button(content, "TEST RUMBLE", { Size = UDim2.fromOffset(200, 40) }, function()
		if Gamepad and Gamepad.Rumble then
			local ok = Gamepad.Rumble(0.8, 0.6, 0.35)
			if not ok then
				State.toast(Gamepad.IsPad() and "This controller has no vibration (or it is switched off)." or "Pick up the controller first.", T.sub)
			end
		end
	end))
	add(UI.Header(content, "Fight camera").Parent)
	add(UI.Text(content, "The fight camera frames both fighters on its own and eases a touch more on a pad. The right stick nudges it round the pair and up or down; a flick of the same stick is still a slip, roll or parry.", { TextSize = 13, TextColor3 = T.sub }))
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local TABS = { "Moves", "Keyboard", "Controller", "Console" }
local TAB_ID = { Moves = "moves", Keyboard = "kbd", Controller = "pad", Console = "console" }
local TAB_NAME = { moves = "Moves", kbd = "Keyboard", pad = "Controller", console = "Console" }

-- keep = { id, slot } after a rebind / a row reset on the same tab: the list keeps its scroll position and
-- a pad keeps the selection on that action's cap (a rebuild otherwise starts at the top)
function setTab(name, keep)
	if not (content and content.Parent) then
		return
	end
	endCapture()
	local scroll = (keep and name == tab) and content.CanvasPosition or Vector2.zero
	tab = name
	UI.Clear(content)
	content.CanvasPosition = Vector2.zero
	local ok, err = pcall(function()
		if name == "moves" then
			movesTab()
		elseif name == "kbd" then
			remapTab("kbd")
		elseif name == "pad" then
			remapTab("pad")
		else
			consoleTab()
		end
	end)
	if not ok then
		warn("[ControlsMenu] " .. name .. ": " .. tostring(err))
	end
	if tabs then
		tabs(TAB_NAME[name] or "Moves")
	end
	task.defer(UI.PadRefresh)
	if keep then
		-- the rebuilt list lays out (and its automatic canvas grows) before the old position can be held
		content.CanvasPosition = scroll
		local list = content
		task.defer(function()
			if not list.Parent then
				return
			end
			list.CanvasPosition = scroll
			local row = list:FindFirstChild("Row_" .. tostring(keep.id))
			local caps = row and row:FindFirstChildWhichIsA("Frame")
			local cap = caps and caps:FindFirstChild(type(keep.slot) == "number" and ("Cap" .. keep.slot) or tostring(keep.slot))
			if cap and Gamepad and Gamepad.IsPad() then
				pcall(function()
					GuiService.SelectedObject = cap
				end)
			end
		end)
	end
end

function ControlsMenu.IsOpen()
	return isOpen
end

-- closed a moment ago by its own key: the other listeners of that very key press must not open it again
-- (the order Roblox runs the InputBegan handlers in is not fixed)
function ControlsMenu.RecentlyClosed()
	return os.clock() - closedAt < 0.25
end

-- opts = { tab = "moves" | "kbd" | "pad" | "console", onClose = fn }
function ControlsMenu.Open(opts)
	opts = opts or {}
	if isOpen then
		if opts.tab then
			setTab(opts.tab)
		end
		return
	end
	isOpen = true
	openedAt = os.clock()
	onCloseFn = opts.onClose
	device = (Gamepad and Gamepad.Mode()) or "keyboard"
	if device == "touch" and not UserInputService.TouchEnabled then
		device = "keyboard"
	end
	gui = UI.New("ScreenGui", { Name = "ControlsUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 45, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui") })
	root = UI.MountRoot(gui)
	local short = UI.CanvasSize(gui).Y < 560
	-- (opts.kicker: a fight says whether the round waits for you; a phone's window has no kicker line, so
	-- there the note goes into the title)
	local title = (opts.kicker and short) and ("Moves & Controls  ·  " .. opts.kicker) or "Moves & Controls"
	local _, _, body = UI.Window(root, "ControlsMenu", 1100, 760, title, { kicker = opts.kicker or "HOW TO FIGHT", onClose = ControlsMenu.Close, scroll = false, z = 12 })
	-- the tab bar: a fingertip tall on touch (UI.TabsHeight), the list placed under it by hand
	local barH = UI.TabsHeight(body, short and 32 or 38)
	local bar
	bar, tabs = UI.Tabs(body, TABS, TAB_NAME[opts.tab or tab] or "Moves", function(name)
		setTab(TAB_ID[name] or "moves")
	end, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, barH) })
	bar.LayoutOrder = 1
	content = UI.Scroll(body, { Name = "Content", Position = UDim2.fromOffset(0, barH + 8), Size = UDim2.new(1, 0, 1, -(barH + 8)) })
	UI.List(content, 8)
	UI.Pad(content, 2, 6)
	State.windows.Controls = ControlsMenu.Close
	track(UserInputService.InputBegan:Connect(function(input, gp)
		if capture then
			if not captureBound then
				captureBegan(input) -- (the ContextActionService binding reads it otherwise)
			end
			return
		end
		-- Escape and the menu's own key (Tab / ` by default) close it again from the keyboard; B closes through
		-- the window's pad handling. (Tab arrives "processed" while Roblox's player list holds it: the fight
		-- hides that list, so a Tab is taken here either way)
		local k = input.KeyCode
		local ownKey = k ~= K.Escape and os.clock() - openedAt > 0.2 and table.find(Keymap.Keys(map(), "moveslist", "kbd"), k) ~= nil and (not gp or k == K.Tab)
		if (not gp and k == K.Escape) or ownKey then
			ControlsMenu.Close()
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if capture and not captureBound then
			captureEnded(input)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if capture and not captureBound then
			captureChanged(input)
		end
	end))
	if Gamepad then
		track(Gamepad.Changed:Connect(function(mode)
			-- the Moves tab follows the device picked up (a cycler pick lasts until the next change)
			if isOpen and mode ~= device and not capture then
				device = mode
				if tab == "moves" then
					setTab("moves")
				end
			end
			-- a pad picked up takes the selection NOW (setTab's own refresh is deferred): the press that
			-- changed the device is still on its way, and an unselected D-pad up is ClientMain's Hub hotkey
			if isOpen and mode == "gamepad" and not capture then
				pcall(UI.PadRefresh)
			end
		end))
	end
	setTab(opts.tab or "moves")
end

function ControlsMenu.Close()
	if not isOpen then
		return
	end
	isOpen = false
	closedAt = os.clock()
	endCapture()
	State.windows.Controls = nil
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	if gui then
		gui:Destroy()
	end
	gui, root, content, tabs = nil, nil, nil, nil
	local fn = onCloseFn
	onCloseFn = nil
	if fn then
		task.spawn(fn)
	end
end

function ControlsMenu.Toggle(opts)
	if isOpen then
		ControlsMenu.Close()
	else
		ControlsMenu.Open(opts)
	end
end

State.open.Controls = function(tabName)
	ControlsMenu.Open({ tab = tabName })
end

return ControlsMenu
