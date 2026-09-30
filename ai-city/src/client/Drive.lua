-- Drive (ModuleScript) — StarterPlayerScripts.CityClient.Drive
-- Driving your own car (see CarService). Your computer drives it, so it's
-- smooth: W / S (or the triggers and left stick) speed up, brake and reverse,
-- A / D steer (tighter at low speed), and the car grips the road instead of
-- sliding. A speedometer shows while you drive. K (or the Car app on your phone) calls your car to you.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Drive = {}
local player = Players.LocalPlayer
local ctx
local seat -- the driver's seat you're in (if it's your car)
local speedo

-- one frame of driving (also used by the tests)
function Drive.Step(dt, driverSeat, chassis, car)
	local throttle = driverSeat.ThrottleFloat or driverSeat.Throttle or 0
	local steer = driverSeat.SteerFloat or driverSeat.Steer or 0
	local max = car:GetAttribute("MaxSpeed") or 50
	local accel = car:GetAttribute("Accel") or 16
	local turn = car:GetAttribute("Turn") or 1.5
	local look = chassis.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, -1)
	local v = chassis.AssemblyLinearVelocity or Vector3.zero
	local speed = v:Dot(forward)
	if throttle > 0.05 then
		if speed < -1 then
			speed = math.min(0, speed + accel * 2.5 * dt) -- braking from reverse
		else
			speed = math.min(max * throttle, speed + accel * throttle * dt)
		end
	elseif throttle < -0.05 then
		if speed > 1 then
			speed = math.max(0, speed - accel * 2.5 * dt) -- the brakes
		else
			speed = math.max(-max * 0.35, speed - accel * 0.7 * dt) -- reverse
		end
	else
		-- coasting to a stop
		local drag = accel * 0.5 * dt
		speed = if speed > 0 then math.max(0, speed - drag) else math.min(0, speed + drag)
	end
	-- steering: sharper when slow, the right way round in reverse
	local grip = math.clamp(math.abs(speed) / 14, 0, 1) * (if speed < 0 then -1 else 1)
	local yaw = -steer * turn * grip * (1 - math.clamp(math.abs(speed) / (max * 2.2), 0, 0.35))
	chassis.AssemblyLinearVelocity = forward * speed + Vector3.new(0, math.min(v.Y, 30), 0)
	chassis.AssemblyAngularVelocity = Vector3.new(0, yaw, 0)
	return speed
end

local function mine(s)
	local car = s and s.Parent
	return s and s:IsA("VehicleSeat") and car and car:GetAttribute("CityCar") and car:GetAttribute("Owner") == player.UserId
end

local function makeSpeedo()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Speedometer"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -120)
	frame.Size = UDim2.fromOffset(180, 56)
	frame.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	frame.BackgroundTransparency = 0.2
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Speed"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 26
	label.Text = "0 mph"
	label.Parent = frame
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

function Drive.Call()
	if not ctx then
		return
	end
	local ok, r = pcall(function()
		return ctx.Remotes.Request:InvokeServer({ Action = "Car", Op = "call" })
	end)
	if ok and r and r.Ok then
		ctx.Hud.Toast("🚗", "Your car is here", "It pulled up on the nearest road. Hop in the driver's seat.", Color3.fromRGB(80, 170, 240))
	elseif ok and r then
		ctx.Hud.Toast("🚗", "No car", r.Error or "", Color3.fromRGB(220, 90, 80))
	end
end

local function hook(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local ok = pcall(function()
		humanoid.Seated:Connect(function(active, s)
			seat = if active and mine(s) then s else nil
			if speedo then
				speedo.Enabled = seat ~= nil
			end
		end)
	end)
	if not ok then
		warn("[Drive] no Seated event")
	end
end

function Drive.Start(context)
	ctx = context
	speedo = makeSpeedo()
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(hook)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			Drive.Call()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not seat or not seat.Parent then
			return
		end
		local car = seat.Parent
		local chassis = car.PrimaryPart or car:FindFirstChild("Chassis")
		if not chassis then
			return
		end
		local ok, speed = pcall(Drive.Step, math.min(dt, 0.1), seat, chassis, car)
		if ok and speedo then
			speedo.Frame.Speed.Text = math.floor(math.abs(speed) * 0.68 + 0.5) .. " mph"
		end
	end)
end

return Drive
