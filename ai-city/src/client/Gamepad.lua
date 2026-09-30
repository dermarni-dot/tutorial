-- Gamepad (ModuleScript) — StarterPlayerScripts.CityClient.Gamepad
-- Console / controller support (Xbox, PlayStation, any gamepad):
--   R2 attack · hold L2 block · L3 sprint (click to toggle) · R1 / L1 next /
--   previous weapon · D-pad ▲ phone · ▼ map · ◀ help · ▶ wardrobe ·
--   B close / back / get out of a hiding spot · X / Y use prompts (talk, buy,
--   pickpocket, hide...) · A jump
-- Menus: when a window, the phone or a conversation opens, the first button is
-- selected so you can move with the D-pad / left stick and press A.
-- Hints on screen (the action bar keycaps, the target card) switch to
-- controller buttons while you're using one, and the controller rumbles when
-- you land or take a hit.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")

local Gamepad = {}
local ctx

-- keyboard key -> controller button label (for on-screen hints)
Gamepad.LABELS = {
	F = "R2", X = "L2", Shift = "L3", Tab = "▲", M = "▼", H = "◀", C = "▶",
	E = "X", G = "Y", R = "Y", Q = "Y", Space = "B", Esc = "B",
}

local active = false -- the last input came from a controller
local sprintToggle = false
local slot = 1

local PAD_TYPES = {
	[Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true,
}

function Gamepad.Active()
	return active
end

-- the label for a keyboard key (the controller button while one is in use)
function Gamepad.Key(key)
	if active then
		return Gamepad.LABELS[key] or key
	end
	return key
end

local listeners = {}
function Gamepad.OnChanged(fn)
	table.insert(listeners, fn)
end

local function setActive(on)
	if on == active then
		return
	end
	active = on
	if not on and sprintToggle then
		sprintToggle = false
		ctx.Moves.SetSprint(false)
	end
	for _, fn in ipairs(listeners) do
		task.spawn(fn, on)
	end
end

-- a short buzz (power 0..1)
function Gamepad.Rumble(power, seconds)
	if not active then
		return
	end
	local pad = Enum.UserInputType.Gamepad1
	local ok = pcall(function()
		if HapticService:IsVibrationSupported(pad) and HapticService:IsMotorSupported(pad, Enum.VibrationMotor.Large) then
			HapticService:SetMotor(pad, Enum.VibrationMotor.Large, math.clamp(power, 0, 1))
			HapticService:SetMotor(pad, Enum.VibrationMotor.Small, math.clamp(power * 0.6, 0, 1))
		end
	end)
	if ok then
		task.delay(seconds or 0.15, function()
			pcall(function()
				HapticService:SetMotor(pad, Enum.VibrationMotor.Large, 0)
				HapticService:SetMotor(pad, Enum.VibrationMotor.Small, 0)
			end)
		end)
	end
end

-- select the first button in a menu so the D-pad / stick can move around it
function Gamepad.Focus(container)
	if not active or not container then
		return
	end
	task.delay(0.12, function()
		if not container.Parent or not container.Visible then
			return
		end
		local best, bestY, bestX
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("GuiButton") and d.Visible and d.Selectable ~= false then
				-- skip anything hidden by a hidden parent
				local shown, p = true, d.Parent
				while p and p ~= container do
					if p:IsA("GuiObject") and not p.Visible then
						shown = false
						break
					end
					p = p.Parent
				end
				if shown then
					local y, x = d.AbsolutePosition.Y, d.AbsolutePosition.X
					-- the header's close button is last, not first
					if d.AbsoluteSize.X > 0 and d.AbsoluteSize.X <= 40 and d.AbsoluteSize.Y <= 40 then
						y += 10000
					end
					if not best or y < bestY - 2 or (math.abs(y - bestY) <= 2 and x < bestX) then
						best, bestY, bestX = d, y, x
					end
				end
			end
		end
		if best then
			GuiService.SelectedObject = best
		end
	end)
end

function Gamepad.Unfocus()
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
end

-- step through the hotbar: 1 = fists, then each weapon you own
local function cycleWeapon(dir)
	local Hud = ctx.Hud
	for _ = 1, 5 do
		slot += dir
		if slot < 1 then
			slot = 5
		elseif slot > 5 then
			slot = 1
		end
		if slot == 1 or Hud.Equip(slot) then
			if slot == 1 then
				Hud.Equip(1)
			end
			return
		end
	end
end

local function anyMenuOpen()
	return ctx.Panels.InDialogue() or ctx.Panels.Phone.IsOpen() or ctx.UI.AnyOpen()
end

local function back()
	local Panels = ctx.Panels
	if ctx.Player:GetAttribute("Hiding") then
		task.spawn(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Unhide" })
		end)
	elseif Panels.InDialogue() then
		Panels.EndDialogue(true)
	elseif Panels.Phone.IsOpen() then
		Panels.Phone.Close()
	else
		ctx.UI.closeAll()
	end
	Gamepad.Unfocus()
end

-- handle a controller button (returns true if it was used)
function Gamepad.Button(key, down)
	local Moves, World, Panels = ctx.Moves, ctx.World, ctx.Panels
	if key == Enum.KeyCode.ButtonL2 then
		World.SetBlock(down)
		return true
	elseif key == Enum.KeyCode.ButtonL3 then
		if down then
			sprintToggle = not sprintToggle
			Moves.SetSprint(sprintToggle)
		end
		return true
	end
	if not down then
		return false
	end
	if key == Enum.KeyCode.ButtonB then
		if anyMenuOpen() or ctx.Player:GetAttribute("Hiding") then
			back()
			return true
		end
		return false
	end
	-- in a menu the D-pad moves the selection (Roblox handles that)
	if GuiService.SelectedObject and anyMenuOpen() then
		return false
	end
	if key == Enum.KeyCode.ButtonR2 then
		World.Attack()
	elseif key == Enum.KeyCode.ButtonR1 then
		cycleWeapon(1)
	elseif key == Enum.KeyCode.ButtonL1 then
		cycleWeapon(-1)
	elseif key == Enum.KeyCode.DPadUp then
		Panels.Phone.Toggle()
		if Panels.Phone.IsOpen() then
			Gamepad.Focus(Panels.Phone.Frame)
		end
	elseif key == Enum.KeyCode.DPadDown then
		Panels.Map.Toggle()
	elseif key == Enum.KeyCode.DPadLeft then
		Panels.Help.Toggle()
	elseif key == Enum.KeyCode.DPadRight then
		task.spawn(Panels.ToggleWardrobe)
	else
		return false
	end
	return true
end

function Gamepad.Start(context)
	ctx = context
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	setActive(ok and PAD_TYPES[last] == true)
	UserInputService.LastInputTypeChanged:Connect(function(t)
		if PAD_TYPES[t] then
			setActive(true)
		elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			setActive(false)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not PAD_TYPES[input.UserInputType] then
			return
		end
		-- B and L2/L3 work even when a menu has the selection
		if processed and input.KeyCode ~= Enum.KeyCode.ButtonB and input.KeyCode ~= Enum.KeyCode.ButtonL2 and input.KeyCode ~= Enum.KeyCode.ButtonL3 then
			return
		end
		Gamepad.Button(input.KeyCode, true)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if PAD_TYPES[input.UserInputType] then
			Gamepad.Button(input.KeyCode, false)
		end
	end)
	-- stop the sprint toggle when you stop moving
	game:GetService("RunService").Heartbeat:Connect(function()
		if sprintToggle then
			local character = ctx.Player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.MoveDirection.Magnitude < 0.1 then
				sprintToggle = false
				ctx.Moves.SetSprint(false)
			end
		end
	end)
	-- windows get a selected button when they open
	ctx.UI.OnOpen = function(frame)
		Gamepad.Focus(frame)
	end
end

return Gamepad
