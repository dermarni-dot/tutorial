-- SleepService (ModuleScript) — ServerScriptService.Modules.SleepService
-- 💤 Players can sleep in any bed: at home, at the hotel or the hospital, in a
-- prison bunk. Walk up to a bed and hold E ("Sleep"): you lie down under the
-- covers (head on the pillow), little Zs float up, the screen dims. Sleeping
-- heals you and refills your energy, and after a proper rest you wake up
-- "Well rested" (a little faster for a few minutes). Move to get up.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local SleepService = {}
local S

local sleepers = {} -- [player] = { Bed, Since, Root CFrame, Rested }
SleepService.Sleepers = sleepers
SleepService.REST = 20 -- seconds of sleep for "Well rested"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- which way is the head end? toward the pillow if there is one, else along
-- the long side
local function headDir(mattress)
	local best, bestD
	for _, p in ipairs(mattress.Parent and mattress.Parent:GetChildren() or {}) do
		if p.Name == "Pillow" and p:IsA("BasePart") then
			local d = (p.Position - mattress.Position).Magnitude
			if d < 6 and (not bestD or d < bestD) then
				best, bestD = p, d
			end
		end
	end
	local dir
	if best then
		dir = best.Position - mattress.Position
	else
		local cf = mattress.CFrame
		dir = if mattress.Size.Z >= mattress.Size.X then cf.LookVector else cf.RightVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	return if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(0, 0, 1)
end

function SleepService.Sleep(player, mattress)
	local root = rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or sleepers[player] then
		return false
	end
	if (root.Position - mattress.Position).Magnitude > 12 then
		return false
	end
	if (player:GetAttribute("Wanted") or 0) > 0 then
		S.City.Toast(player, "🚨", "Too wired to sleep", "Not with the police after you.", rgb(220, 90, 90))
		return false
	end
	-- lying on the mattress, face up, head toward the pillow
	local head = headDir(mattress)
	local top = mattress.Position + Vector3.new(0, mattress.Size.Y / 2 + 0.6, 0)
	local center = top + head * 0.4
	-- (facing the feet, then tipped back 90°: face up, head on the pillow)
	local cf = CFrame.lookAt(center, center - head) * CFrame.Angles(math.rad(90), 0, 0)
	sleepers[player] = { Bed = mattress, Since = os.clock(), Return = root.CFrame, Rested = false }
	root.Anchored = true
	root.CFrame = cf
	player.Character:SetAttribute("Emote", "sleeping")
	player.Character:SetAttribute("Sleeping", true)
	player:SetAttribute("Sleeping", true)
	S.City.Toast(player, "💤", "Sleeping...", "Resting heals you and refills your energy. Move to get up.", rgb(120, 140, 220))
	return true
end

function SleepService.Wake(player)
	local s = sleepers[player]
	sleepers[player] = nil
	player:SetAttribute("Sleeping", nil)
	local character = player.Character
	if not s or not character then
		return
	end
	character:SetAttribute("Emote", nil)
	character:SetAttribute("Sleeping", nil)
	local root = rootOf(player)
	if root then
		-- stand up beside the bed
		local m = s.Bed
		local side = if m and m.Parent then headDir(m):Cross(Vector3.new(0, 1, 0)) * 3.6 else Vector3.zero
		local at = if m and m.Parent then m.Position + side + Vector3.new(0, 3, 0) else s.Return.Position
		root.CFrame = CFrame.new(at)
		root.Anchored = false
	end
	if s.Rested then
		player:SetAttribute("Boost", 1.15)
		player:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + 180)
		S.City.Toast(player, "🌅", "Well rested!", "You feel great: a little faster for 3 minutes.", rgb(250, 200, 90))
	end
end

-- a "Sleep" prompt on a bed's mattress
local function addBed(mattress)
	if mattress:FindFirstChild("SleepPrompt") or not mattress:IsA("BasePart") then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "SleepPrompt"
	p.ActionText = "Sleep"
	p.ObjectText = "💤"
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0.6
	p.MaxActivationDistance = 7
	p.RequiresLineOfSight = false
	p.Parent = mattress
	p.Triggered:Connect(function(player)
		SleepService.Sleep(player, mattress)
	end)
	CollectionService:AddTag(mattress, "Bed")
end

local function step()
	for player, s in pairs(sleepers) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player.Parent or not humanoid or humanoid.Health <= 0 or not s.Bed.Parent then
			sleepers[player] = nil
			player:SetAttribute("Sleeping", nil)
		else
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 4)
			S.City.Send(player, { Type = "Food", Energy = 6, Name = "rest", Quiet = true })
			if not s.Rested and os.clock() - s.Since >= SleepService.REST then
				s.Rested = true
				S.City.Toast(player, "😌", "A good rest", "Get up whenever you like: you'll be well rested.", rgb(140, 180, 240))
			end
		end
	end
end
SleepService.Step = step

function SleepService.Start(services)
	S = services
	S.City.Handle("Wake", function(player)
		SleepService.Wake(player)
		return { Ok = true }
	end)
	local function scan(d)
		if d.Name == "Mattress" and d:IsA("BasePart") then
			addBed(d)
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		scan(d)
	end
	-- (houses get their furniture when a family moves in)
	workspace.DescendantAdded:Connect(function(d)
		if d.Name == "Mattress" then
			task.defer(scan, d)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sleepers[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(step)
		end
	end)
end

return SleepService
