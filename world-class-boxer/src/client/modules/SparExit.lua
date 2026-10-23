-- SparExit: the way out of a sparring session, at any time. A LEAVE SPARRING button on the spar HUD (and an entry
-- in the Moves & Controls menu, FightClient's openMoves) opens a prompt - End session / Return to gym / Keep going -
-- that holds the round like the menu does (opts.pause) and, on a leave, tells the server (opts.leave: FightClient
-- sends `leaveSpar`; FightEngine's Fight:LeaveSpar ends the session on the coach's cards so far, pays out its share
-- and Cleanup / Main's runSpar put the player back in the gym). "Return to gym" also drops the result card on this
-- client (opts.leave("gym")) so he is straight back on the floor; "End session" keeps it (opts.leave("end")).
--
--   local SE = require(BoxerClient.SparExit)
--   SE.Mount(hud, { leave = function(mode) end, pause = function(on) end })
--   SE.Show(true | false)      -- the button (a spar, during the session)
--   SE.Prompt()                -- the prompt (the button, the menu entry)
--   SE.Close()                 -- the prompt, if open (the session ended)
--   SE.IsOpen()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local T = UI.Theme

local SparExit = {}
local player = Players.LocalPlayer
local button, opts
local gui, root
local isOpen = false
local openedAt = 0
local conn

function SparExit.IsOpen()
	return isOpen
end

-- the button on the fight HUD: top right, under the clock's line; shown only for a spar (SparExit.Show)
function SparExit.Mount(hud, o)
	opts = o or {}
	if button and button.Parent then
		return button
	end
	button = UI.Button(hud, "LEAVE SPARRING", {
		Name = "LeaveSpar", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 48), Size = UDim2.fromOffset(164, 32),
		TextSize = 13, Font = T.semi, BackgroundColor3 = T.panel2, TextColor3 = T.text, Visible = false, ZIndex = 12, icon = "close",
	}, function()
		SparExit.Prompt()
	end)
	return button
end

function SparExit.Show(on)
	if button then
		button.Visible = on == true
	end
end

local function leave(mode)
	local fn = opts and opts.leave
	SparExit.Close(true)
	if fn then
		task.spawn(fn, mode)
	end
end

-- the prompt: a small window over the fight. The round holds while it is up (opts.pause, as the Moves menu);
-- Escape / B / Keep going close it and the round goes on
function SparExit.Prompt()
	if isOpen then
		return
	end
	isOpen = true
	openedAt = os.clock()
	if opts and opts.pause then
		pcall(opts.pause, true)
	end
	gui = UI.New("ScreenGui", { Name = "SparExitUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 46, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui") })
	root = UI.MountRoot(gui)
	local short = UI.CanvasSize(gui).Y < 560
	local _, _, body = UI.Window(root, "SparExit", 480, short and 300 or 330, "Leave sparring?", { kicker = "SPARRING  ·  ROUND PAUSED", onClose = SparExit.Close, scroll = false, z = 14 })
	UI.List(body, 10)
	UI.Text(body, "You can stop at any time. The coach scores what you boxed so far and the session pays out its share of the training; your headgear and gloves stay on.", {
		Font = T.font, TextSize = 15, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 1,
	})
	local row = UI.Frame(body, { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.List(row, 8)
	local function btn(order, text, color, textColor, fn)
		return UI.Button(row, text, { Size = UDim2.new(1, 0, 0, short and 40 or 46), TextSize = 15, Font = T.semi, BackgroundColor3 = color, TextColor3 = textColor, LayoutOrder = order }, fn)
	end
	btn(1, "END SESSION  ·  see the coach's card", T.gold, T.ink, function()
		leave("end")
	end)
	btn(2, "RETURN TO GYM  ·  straight back to the floor", T.panel2, T.text, function()
		leave("gym")
	end)
	btn(3, "KEEP GOING", T.blue, T.ink, function()
		SparExit.Close()
	end)
	conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and os.clock() - openedAt > 0.2 then
			SparExit.Close()
		end
	end)
end

-- closes the prompt (and lets the round go on, unless the session is being left: `leaving`)
function SparExit.Close(leaving)
	if not isOpen then
		return
	end
	isOpen = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if gui then
		gui:Destroy()
	end
	gui, root = nil, nil
	if opts and opts.pause and not leaving then
		pcall(opts.pause, false)
	end
end

-- the fight is over: the button goes, the prompt with it (no pause message: there is no round to hold)
function SparExit.Reset()
	SparExit.Show(false)
	if isOpen then
		isOpen = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if gui then
			gui:Destroy()
		end
		gui, root = nil, nil
	end
end

return SparExit
