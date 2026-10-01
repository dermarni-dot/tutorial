-- Emotes (ModuleScript) — StarterPlayerScripts.CityClient.Emotes
-- The emote bar: press T (or open the Emote app on your phone) and pick one:
-- wave, dance, cheer, point, clap, laugh, salute, flex, shrug, sit. Everyone
-- sees it, and the people around you react (see SocialService). Walking off
-- stops it.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Emotes = {}
local player = Players.LocalPlayer
local ctx, gui, bar

local LIST = {
	{ "wave", "👋", "Wave" }, { "dance", "💃", "Dance" }, { "cheer", "🙌", "Cheer" }, { "point", "👉", "Point" }, { "clap", "👏", "Clap" },
	{ "laugh", "😂", "Laugh" }, { "salute", "🫡", "Salute" }, { "flex", "💪", "Flex" }, { "shrug", "🤷", "Shrug" }, { "sit", "🧘", "Sit" },
}
Emotes.LIST = LIST

function Emotes.Play(id)
	if not ctx then
		return
	end
	task.spawn(function()
		pcall(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Emote", Id = id })
		end)
	end)
	Emotes.Toggle(false)
end

function Emotes.Toggle(on)
	if not bar then
		return
	end
	if on == nil then
		on = not bar.Visible
	end
	bar.Visible = on
end

function Emotes.IsOpen()
	return bar ~= nil and bar.Visible
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "EmoteBar"
	gui.ResetOnSpawn = false
	bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -190)
	bar.Size = UDim2.fromOffset(#LIST * 66 + 12, 80)
	bar.BackgroundColor3 = Color3.fromRGB(22, 24, 36)
	bar.BackgroundTransparency = 0.15
	bar.Visible = false
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = bar
	for k, e in ipairs(LIST) do
		local b = Instance.new("TextButton")
		b.Name = e[1]
		b.Position = UDim2.fromOffset(8 + (k - 1) * 66, 8)
		b.Size = UDim2.fromOffset(60, 64)
		b.BackgroundColor3 = Color3.fromRGB(44, 48, 70)
		b.Text = ""
		b.Parent = bar
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = b
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(1, 0, 0, 40)
		icon.Text = e[2]
		icon.TextSize = 30
		icon.Font = Enum.Font.GothamBold
		icon.TextColor3 = Color3.new(1, 1, 1)
		icon.Parent = b
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, 40)
		label.Size = UDim2.new(1, 0, 0, 20)
		label.Text = e[3]
		label.TextSize = 12
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(200, 205, 225)
		label.Parent = b
		b.Activated:Connect(function()
			Emotes.Play(e[1])
		end)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

function Emotes.Start(context)
	ctx = context
	build()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			Emotes.Toggle()
		elseif bar.Visible and input.KeyCode == Enum.KeyCode.Escape then
			Emotes.Toggle(false)
		end
	end)
end

return Emotes
