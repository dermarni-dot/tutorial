-- Keymap: every fight action, its default keys on keyboard + mouse and on a controller, and the player's
-- custom map (saved with the profile under settings.ui.keymap; the server sanitizes it with the same
-- Keymap.Sanitize). Shared: no Roblox services, so it loads on the server too.
--
-- A binding is a string:
--   "F"                     a KeyCode name (keyboard / pad button) or a mouse button: MouseButton1 / 2 / 3
--   "Q+MouseButton1"        a chord: hold the first key, press the second. On a pad the first key may be a
--                           right-stick flick (Thumbstick2Left ...): the flick counts as "held" for 0.4 s
--   "2xA"                   a double tap of that key within 0.3 s
-- Keymap.Actions lists the actions in menu order with their section (basic / punch / advanced / special).
-- Keymap.Default() is the default map { kbd = { id = { b1, b2 } }, pad = { id = b } }; Keymap.Resolve(saved)
-- lays a saved map over it; Keymap.Conflicts(map) lists two actions on one binding.
local Keymap = {}

local MOUSE = { MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB" }
local KEY_NAMES = {
	LeftControl = "CTRL", RightControl = "CTRL", LeftShift = "SHIFT", RightShift = "SHIFT", LeftAlt = "ALT", RightAlt = "ALT",
	Space = "SPACE", Tab = "TAB", Backquote = "`", Return = "ENTER", Backspace = "BACKSPACE", Semicolon = ";", Comma = ",", Period = ".", Slash = "/",
	Quote = "'", LeftBracket = "[", RightBracket = "]", Minus = "-", Equals = "=", BackSlash = "\\",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	Up = "UP", Down = "DOWN", Left = "LEFT", Right = "RIGHT", CapsLock = "CAPS",
	Thumbstick2Left = "RS LEFT", Thumbstick2Right = "RS RIGHT", Thumbstick2Up = "RS UP", Thumbstick2Down = "RS DOWN",
}
-- keys that never bind: Roblox's own (menu, chat, screenshot) and the movement keys as plain presses
local RESERVED = { Escape = true, Slash = true, F1 = true, F2 = true, F3 = true, F4 = true, F5 = true, F6 = true, F7 = true, F8 = true,
	F9 = true, F10 = true, F11 = true, F12 = true, Print = true, W = true, A = true, S = true, D = true, Unknown = true,
	ButtonStart = true, Thumbstick1 = true, Thumbstick2 = true }
-- plain presses of the movement keys are Roblox's; a double tap or a chord on them is fine
local MOVE_KEYS = { W = true, A = true, S = true, D = true }
-- the right-stick flicks the fight reads (Gamepad.Flick): bindable as pad keys, never as plain buttons of a chord's second half
local FLICKS = { Thumbstick2Left = true, Thumbstick2Right = true, Thumbstick2Up = true, Thumbstick2Down = true }

-- { id, label, section, kbd = { primary, secondary }, pad = binding, touch = pad name, desc, how, fixed }
-- fixed = shown in the menu, not remappable (Roblox's movement, the get-up mash, the hold-to-open)
Keymap.Actions = {
	-- BASIC
	{ id = "move", label = "Move", section = "basic", fixed = true, kbd = { "W/A/S/D" }, pad = "Thumbstick1", touch = "Thumbstick",
		desc = "Step around the ring. Backing off costs nothing; walking in wins the inside." },
	{ id = "sprint", label = "Sprint", section = "basic", kbd = { "LeftShift" }, pad = "ButtonL3", touch = "-",
		desc = "Hold to run around the gym and the city. In the ring it is quicker footwork: cut him off or get off the ropes.",
		how = "In the ring it costs stamina while you move and does nothing while you punch or block. On a pad L3 is the clinch in the ring." },
	{ id = "block", label = "Block (guard up / down)", section = "basic", kbd = { "B" }, pad = "ButtonL2", touch = "BLOCK",
		desc = "Tap to raise the guard, tap again to drop it. A long press blocks while held. Punching drops a tapped guard.",
		how = "Blocks eat most of a head shot. Body shots still get through and the overhand comes over the top." },
	{ id = "body", label = "Body shot (arms the next punch)", section = "basic", kbd = { "C" }, pad = "ButtonL1", touch = "BODY",
		desc = "Tap to send the next punch to the body (lit orange). Hold it to keep every punch low.",
		how = "Body shots drain stamina and body HP and slow the other man down late." },
	{ id = "clinch", label = "Clinch", section = "basic", kbd = { "LeftControl" }, pad = "DPadDown", touch = "CLINCH",
		desc = "Tie him up when you are hurt: a breather, a little head HP back, the legs come back.",
		how = "Only up close, and not more than once every six seconds." },
	{ id = "legend", label = "Controls strip", section = "basic", kbd = { "H" }, pad = "ButtonSelect", touch = "-",
		desc = "Tap to show or hide the key strip during a round (it lists your unlocked special moves too)." },
	-- (Tab is Roblox's player list outside a fight: the fight hides that list and takes Tab; the backquote
	-- key works everywhere)
	{ id = "moveslist", label = "Moves & controls menu", section = "basic", kbd = { "Tab", "Backquote" }, pad = "ButtonSelect(hold)", touch = "MOVES", padFixed = true,
		desc = "This menu. It pauses a career fight or a spar while it is open (a PvP bout goes on). On a pad hold VIEW / SHARE for a second; on touch the MOVES pad.",
		how = "Tab works in a fight (outside one it is Roblox's player list); ` (the key under Esc) works everywhere." },
	{ id = "getup", label = "Get up after a knockdown", section = "basic", fixed = true, kbd = { "Space" }, pad = "ButtonA", touch = "Tap the panel",
		desc = "Mash it. A press while the marker is in the green zone counts three times." },
	-- PUNCH
	{ id = "jab", label = "Jab", section = "punch", kbd = { "MouseButton1", "J" }, pad = "ButtonX", touch = "JAB",
		desc = "Fast and cheap. Measures the distance and starts every combination." },
	{ id = "cross", label = "Cross", section = "punch", kbd = { "MouseButton2", "K" }, pad = "ButtonY", touch = "CROSS",
		desc = "The straight right. Hip turn and full extension: the money punch behind a jab." },
	{ id = "leadhook", label = "Lead hook", section = "punch", kbd = { "F", "L" }, pad = "ButtonB", touch = "HOOK",
		desc = "Round the guard from the left. Lands hard up close.", how = "Best after a cross, or when he leans away from the jab." },
	{ id = "rearhook", label = "Rear hook", section = "punch", kbd = { "R", "Semicolon" }, pad = "ButtonA", touch = "HOOK",
		desc = "The big right hook. Slower, heavier, takes the legs.", how = "Inside range only." },
	{ id = "uppercut", label = "Uppercut", section = "punch", kbd = { "T", "U" }, pad = "ButtonR2", touch = "UPPER",
		desc = "Leg drive under the chin. The hardest head shot in the book.", how = "Catches a man who ducks or rolls: it lands bigger on a rolling head." },
	{ id = "overhand", label = "Overhand", section = "punch", kbd = { "MouseButton3", "O" }, pad = "ButtonR1", touch = "OVERHAND",
		desc = "A looping right over the top of the guard. Slow, half of it goes through a block (the Loaded overhand special is the bigger one).",
		how = "Throw it when he shells up or is too tired to move. On a pad it goes when you let go of RB: RB held with another button is a special move." },
	{ id = "bodyhook", label = "Body hook", section = "punch", kbd = { "G" }, pad = "ButtonL1+ButtonB", touch = "BODY, then HOOK",
		desc = "A hook to the ribs. Drains stamina and bruises the body (the liver is under the right ribs).", how = "Under a high guard, or when he is gassed." },
	-- ADVANCED
	{ id = "slipL", label = "Slip left", section = "advanced", kbd = { "Q" }, pad = "Thumbstick2Left", touch = "Swipe BLOCK left",
		desc = "Move the head off the line to the left. Straight punches miss; so do half the hooks.", how = "Slip, then fire: everything you land for a moment counts as a counter." },
	{ id = "slipR", label = "Slip right", section = "advanced", kbd = { "E" }, pad = "Thumbstick2Right", touch = "Swipe BLOCK right",
		desc = "The same to the right." },
	{ id = "dodge", label = "Dodge (roll under)", section = "advanced", kbd = { "Space" }, pad = "Thumbstick2Down", touch = "Swipe BLOCK down",
		desc = "Duck and roll under hooks and overhands.", how = "Never roll into an uppercut." },
	{ id = "quickdodge", label = "Quick dodge", section = "advanced", kbd = { "LeftShift+Space" }, pad = "ButtonR3", touch = "Hold BLOCK, swipe down",
		desc = "A short, snappy roll: a smaller window but you are back on your feet sooner.", how = "For reading one punch, not a flurry." },
	{ id = "parry", label = "Parry", section = "advanced", kbd = { "V" }, pad = "DPadUp", touch = "Swipe BLOCK up",
		desc = "Catch a straight punch with the glove and fire back: a short window with a big counter.", how = "Time it on the jab or the cross." },
	{ id = "pivotL", label = "Pivot left", section = "advanced", kbd = { "2xA", "Z" }, pad = "DPadLeft", touch = "Swipe CLINCH left",
		desc = "Double-tap A: step off at an angle to the left. The next punch lands at an angle (harder, more accurate).", how = "Off the ropes, or to make a swarmer reset." },
	{ id = "pivotR", label = "Pivot right", section = "advanced", kbd = { "2xD", "X" }, pad = "DPadRight", touch = "Swipe CLINCH right",
		desc = "Double-tap D: the same to the right." },
	{ id = "counterjab", label = "Counter jab", section = "advanced", kbd = { "Q+MouseButton1" }, pad = "Thumbstick2Left+ButtonX", touch = "Swipe BLOCK, then JAB",
		desc = "Slip left and jab as one move: hold Q (slip) and click. The jab comes out of the slip and counts as a counter when it catches him punching.",
		how = "On a pad: flick the right stick left, then X within half a second. On touch: a slip on the BLOCK pad, then JAB within half a second." },
	{ id = "countercross", label = "Counter cross", section = "advanced", kbd = { "E+MouseButton2" }, pad = "Thumbstick2Right+ButtonY", touch = "Swipe BLOCK, then CROSS",
		desc = "Slip right and fire the cross over his jab: hold E and right-click.", how = "On a pad: flick right, then Y." },
	-- SPECIAL (Moves.lua: unlocked per style, career tier and training)
	{ id = "special_checkhook", special = "checkhook", label = "Check hook", section = "special", kbd = { "One" }, pad = "ButtonR1+ButtonX", touch = "CHECK" },
	{ id = "special_phillyshell", special = "phillyshell", label = "Philly shell counter", section = "special", kbd = { "Two" }, pad = "ButtonR1+ButtonL2", touch = "SHELL" },
	{ id = "special_pullcounter", special = "pullcounter", label = "Pull counter", section = "special", kbd = { "Three" }, pad = "ButtonR1+ButtonY", touch = "PULL" },
	{ id = "special_livershot", special = "livershot", label = "Liver shot", section = "special", kbd = { "Four" }, pad = "ButtonR1+ButtonB", touch = "LIVER" },
	{ id = "special_gazelle", special = "gazelle", label = "Gazelle punch", section = "special", kbd = { "Five" }, pad = "ButtonR1+DPadUp", touch = "GAZELLE" },
	{ id = "special_peekaboo", special = "peekaboo", label = "Peek-a-boo rush", section = "special", kbd = { "Six" }, pad = "ButtonR1+DPadDown", touch = "RUSH" },
	{ id = "special_stepback", special = "stepback", label = "Step-back counter", section = "special", kbd = { "Seven" }, pad = "ButtonR1+ButtonL1", touch = "STEP" },
	{ id = "special_overhand", special = "overhand", label = "Loaded overhand", section = "special", kbd = { "Eight" }, pad = "ButtonR1+ButtonA", touch = "LOADED" },
	{ id = "special_leaduppercut", special = "leaduppercut", label = "Lead uppercut", section = "special", kbd = { "Nine" }, pad = "ButtonR1+ButtonR2", touch = "L.UPPER" },
}
Keymap.Sections = {
	{ id = "basic", title = "Basic", blurb = "Moving, guarding and holding on." },
	{ id = "punch", title = "Punches", blurb = "Every punch goes to the head unless the body shot is armed. Punching drops a tapped guard." },
	{ id = "advanced", title = "Advanced", blurb = "Head movement, footwork and counters. A punch you land right after a slip, roll, parry or pivot counts as a counter." },
	{ id = "special", title = "Special moves", blurb = "Signature moves unlocked by your style, your career and your training (Moves & Controls > Special)." },
}

Keymap.ById = {}
for _, a in ipairs(Keymap.Actions) do
	Keymap.ById[a.id] = a
end

local function isPadKeyName(n)
	return n:sub(1, 6) == "Button" or n:sub(1, 4) == "DPad" or n:sub(1, 10) == "Thumbstick"
end
Keymap.IsPadKeyName = isPadKeyName

-- the KeyCode names, built once from the enum (the server runs this on client data: nothing the client
-- sends may grow a cache, so a name outside the enum is never stored); a per-name lookup that caches
-- only real keys is the fallback where the enum cannot be listed
local keySet
local function keyExists(n)
	if not keySet then
		keySet = {}
		pcall(function()
			for _, k in ipairs(Enum.KeyCode:GetEnumItems()) do
				keySet[k.Name] = true
			end
		end)
	end
	if keySet[n] then
		return true
	end
	if next(keySet) ~= nil then
		return false
	end
	local ok, k = pcall(function()
		return Enum.KeyCode[n]
	end)
	if ok and k ~= nil then
		keySet[n] = true
		return true
	end
	return false
end

-- a binding's parts: { keys = { "Q", "MouseButton1" }, double = false } (nil for a malformed one)
function Keymap.Parse(b)
	if type(b) ~= "string" or #b == 0 or #b > 48 then
		return nil
	end
	if b:sub(1, 2) == "2x" then
		local k = b:sub(3)
		return k ~= "" and { keys = { k }, double = true } or nil
	end
	local a, c = b:match("^([%w]+)%+([%w]+)$")
	if a then
		return { keys = { a, c }, double = false }
	end
	if b:match("^[%w]+$") then
		return { keys = { b }, double = false }
	end
	return nil
end

-- is the binding usable on that device? (device = "kbd" | "pad")
local function validKey(n, device)
	if MOUSE[n] then
		return device == "kbd"
	end
	if not keyExists(n) or RESERVED[n] and not MOVE_KEYS[n] then
		return false
	end
	if device == "pad" then
		return isPadKeyName(n)
	end
	return not isPadKeyName(n)
end

function Keymap.Valid(b, device)
	local p = Keymap.Parse(b)
	if not p then
		return false
	end
	for i, k in ipairs(p.keys) do
		if not validKey(k, device) then
			return false
		end
		-- a plain press of a movement key is Roblox's walk; a flick is never the second half of a chord
		if MOVE_KEYS[k] and not p.double and #p.keys == 1 then
			return false
		end
		if i == 2 and FLICKS[k] then
			return false
		end
	end
	if p.double and (FLICKS[p.keys[1]] or MOUSE[p.keys[1]]) then
		return false
	end
	return true
end

-- the default map (a fresh copy)
function Keymap.Default()
	local m = { kbd = {}, pad = {} }
	for _, a in ipairs(Keymap.Actions) do
		if not a.fixed then
			m.kbd[a.id] = table.clone(a.kbd)
			if not a.padFixed and a.pad then
				m.pad[a.id] = a.pad
			end
		end
	end
	return m
end

-- pure: a clean custom map from anything (saved data, client input): only known, remappable actions,
-- at most two keyboard bindings and one pad binding each, every binding valid for its device; an
-- empty table means "all defaults"
function Keymap.Sanitize(t)
	local out = { kbd = {}, pad = {} }
	if type(t) ~= "table" then
		return out
	end
	local kbd, pad = t.kbd, t.pad
	for _, a in ipairs(Keymap.Actions) do
		if not a.fixed then
			local list = type(kbd) == "table" and kbd[a.id] or nil
			if type(list) == "table" then
				local clean = {}
				-- only the first eight entries are read (the menu saves two): the server's cost never grows
				-- with what a client sends
				for i = 1, 8 do
					local b = list[i]
					if b == nil or #clean >= 2 then
						break
					end
					if type(b) == "string" and Keymap.Valid(b, "kbd") and not table.find(clean, b) then
						table.insert(clean, b)
					end
				end
				-- a saved empty list unbinds the action on the keyboard on purpose
				out.kbd[a.id] = clean
			end
			local pb = type(pad) == "table" and pad[a.id] or nil
			if not a.padFixed and type(pb) == "string" and Keymap.Valid(pb, "pad") then
				out.pad[a.id] = pb
			elseif not a.padFixed and pb == "" then
				out.pad[a.id] = ""
			end
		end
	end
	return out
end

-- the defaults with the saved map laid over them (the saved map may be nil / partial / dirty)
function Keymap.Resolve(saved)
	local m = Keymap.Default()
	local s = Keymap.Sanitize(saved)
	for id, list in pairs(s.kbd) do
		m.kbd[id] = list
	end
	for id, b in pairs(s.pad) do
		m.pad[id] = b ~= "" and b or nil
	end
	return m
end

-- what differs from the defaults (the part worth saving); {} when nothing does
function Keymap.Diff(map)
	local def = Keymap.Default()
	local out = { kbd = {}, pad = {} }
	for id, list in pairs(map.kbd or {}) do
		local d = def.kbd[id]
		if d and (#d ~= #list or d[1] ~= list[1] or d[2] ~= list[2]) then
			out.kbd[id] = table.clone(list)
		end
	end
	for _, a in ipairs(Keymap.Actions) do
		if not a.fixed and not a.padFixed then
			local v = map.pad and map.pad[a.id] or nil
			if v ~= def.pad[a.id] then
				out.pad[a.id] = v or ""
			end
		end
	end
	return out
end

-- two actions sharing one binding on one device: { { device, binding, a, b } ... }
function Keymap.Conflicts(map)
	local out = {}
	local seen = {}
	for _, a in ipairs(Keymap.Actions) do
		for _, b in ipairs(map.kbd[a.id] or {}) do
			local key = "kbd:" .. b
			if seen[key] then
				table.insert(out, { device = "kbd", binding = b, a = seen[key], b = a.id })
			else
				seen[key] = a.id
			end
		end
		local pb = map.pad[a.id]
		if pb then
			local key = "pad:" .. pb
			if seen[key] then
				table.insert(out, { device = "pad", binding = pb, a = seen[key], b = a.id })
			else
				seen[key] = a.id
			end
		end
	end
	return out
end

-- the actions bound to a binding on a device, excluding one action
function Keymap.Holders(map, device, binding, except)
	local out = {}
	for _, a in ipairs(Keymap.Actions) do
		if a.id ~= except then
			if device == "kbd" then
				if table.find(map.kbd[a.id] or {}, binding) then
					table.insert(out, a.id)
				end
			elseif map.pad[a.id] == binding then
				table.insert(out, a.id)
			end
		end
	end
	return out
end

-- a key's display name: "Q", "LMB", "SPACE", "CTRL"; pad buttons through Gamepad.Label when given
function Keymap.KeyName(n, Gamepad)
	if MOUSE[n] then
		return MOUSE[n]
	end
	if Gamepad and keyExists(n) then
		local ok, s = pcall(Gamepad.Short, Enum.KeyCode[n])
		if ok and type(s) == "string" and s ~= "" and (isPadKeyName(n) or KEY_NAMES[n] == nil) then
			return s
		end
	end
	return KEY_NAMES[n] or n:upper()
end

-- a binding's display text: "Q + LMB", "2x A", "RB + X", "HOLD VIEW"
function Keymap.Label(b, Gamepad)
	if type(b) ~= "string" or b == "" then
		return "-"
	end
	local hold = b:match("^(%w+)%(hold%)$")
	if hold then
		return "HOLD " .. Keymap.KeyName(hold, Gamepad)
	end
	local p = Keymap.Parse(b)
	if not p then
		return b:upper()
	end
	if p.double then
		return "2x " .. Keymap.KeyName(p.keys[1], Gamepad)
	end
	if #p.keys == 2 then
		return Keymap.KeyName(p.keys[1], Gamepad) .. " + " .. Keymap.KeyName(p.keys[2], Gamepad)
	end
	return Keymap.KeyName(p.keys[1], Gamepad)
end

-- the text for an action on a device: the keyboard's bindings joined with " / ", the pad's one, the touch pad's name
function Keymap.ActionText(map, id, device, Gamepad)
	local a = Keymap.ById[id]
	if not a then
		return "-"
	end
	if device == "touch" then
		return a.touch or "-"
	elseif device == "pad" or device == "gamepad" then
		local b = a.padFixed and a.pad or (a.fixed and a.pad or map.pad[id])
		return Keymap.Label(b, Gamepad)
	end
	local list = a.fixed and a.kbd or map.kbd[id]
	if not list or #list == 0 then
		return "-"
	end
	local parts = {}
	for _, b in ipairs(list) do
		table.insert(parts, a.fixed and b or Keymap.Label(b, Gamepad))
	end
	return table.concat(parts, " / ")
end

-- the Enum items (KeyCode or UserInputType.MouseButtonN) of an action's PLAIN bindings on a device, for code
-- that matches raw input itself (the training drills): chords and double taps are skipped (Keymap.Trigger
-- has their parts), a right-stick flick comes back as its Thumbstick2* KeyCode. Always a table.
function Keymap.Keys(map, id, device)
	local out = {}
	local a = Keymap.ById[id]
	if not (a and type(map) == "table") then
		return out
	end
	local list
	if device == "pad" or device == "gamepad" then
		local b = a.padFixed and a.pad or (a.fixed and a.pad or (map.pad and map.pad[id]))
		list = b and { b } or {}
	else
		list = a.fixed and a.kbd or (map.kbd and map.kbd[id]) or {}
	end
	for _, b in ipairs(list) do
		local p = Keymap.Parse(b)
		if p and #p.keys == 1 and not p.double then
			local n = p.keys[1]
			if MOUSE[n] then
				table.insert(out, Enum.UserInputType[n])
			elseif keyExists(n) then
				table.insert(out, Enum.KeyCode[n])
			end
		end
	end
	return out
end

-- the key names a binding needs held before its last key (the chord's first half), and that last key
function Keymap.Trigger(b)
	local p = Keymap.Parse(b)
	if not p then
		return nil
	end
	if #p.keys == 2 then
		return p.keys[2], p.keys[1], false
	end
	return p.keys[1], nil, p.double
end

return Keymap
