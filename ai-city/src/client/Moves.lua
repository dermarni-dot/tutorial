-- Moves (ModuleScript) — StarterPlayerScripts.CityClient.Moves
-- Sprinting and stamina. Hold Shift (or the Sprint button) to run: it uses
-- stamina, which refills when you stop. Your fitness level (from the server,
-- see Shared.Fitness) sets how much stamina you have, how fast it refills and
-- how fast you sprint. Sprinting earns fitness XP; food refills stamina.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fitness = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fitness"))

local Moves = {}
local player = Players.LocalPlayer
local ctx

local want = false -- holding Shift / the button
local stamina = Fitness.Stats(1).MaxStamina
local exhausted = false
local lastSprint = 0
local sprintSeconds = 0 -- not reported yet
local ourSpeed -- the WalkSpeed we set (so we only undo our own change)

function Moves.SetSprint(on)
	want = on == true
end

-- food and workouts refill stamina
function Moves.AddStamina(amount)
	local st = Fitness.Stats(player:GetAttribute("FitLevel") or 1)
	stamina = math.clamp(stamina + (amount or 0), 0, st.MaxStamina)
	if stamina > st.MaxStamina * 0.25 then
		exhausted = false
	end
end

function Moves.Stamina()
	return stamina
end

local function report()
	if sprintSeconds < 0.5 then
		return
	end
	local seconds = sprintSeconds
	sprintSeconds = 0
	task.spawn(function()
		pcall(function()
			ctx.Remotes.Request:InvokeServer({ Action = "Trained", Seconds = seconds })
		end)
	end)
end

local function step(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local level = player:GetAttribute("FitLevel") or 1
	local st = Fitness.Stats(level)
	local boost = 1
	if (player:GetAttribute("BoostUntil") or 0) > workspace:GetServerTimeNow() then
		boost = player:GetAttribute("Boost") or 1
	end
	stamina = math.min(stamina, st.MaxStamina)
	local sprinting = false
	if humanoid and root and humanoid.Health > 0 then
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local busy = root.Anchored or player:GetAttribute("Hiding") or player:GetAttribute("Blocking") or character:GetAttribute("Treadmill")
		sprinting = want and moving and not busy and not exhausted and stamina > 0
		if sprinting then
			stamina = math.max(0, stamina - st.Drain * dt)
			lastSprint = os.clock()
			sprintSeconds += dt
			if stamina <= 0 then
				exhausted = true
				ctx.Hud.Toast("😮‍💨", "Out of breath!", "Stop running for a moment to get your stamina back. Train at the gym for more.", Color3.fromRGB(240, 170, 60))
			end
			if humanoid.WalkSpeed ~= st.Sprint then
				humanoid.WalkSpeed = st.Sprint
				ourSpeed = st.Sprint
			end
		else
			if ourSpeed and humanoid.WalkSpeed == ourSpeed then
				humanoid.WalkSpeed = Fitness.WALK
			end
			ourSpeed = nil
			if os.clock() - lastSprint > st.Delay then
				-- standing still gets your breath back faster
				stamina = math.min(st.MaxStamina, stamina + st.Regen * boost * (if moving then 1 else 1.5) * dt)
			end
			if exhausted and stamina >= st.MaxStamina * 0.25 then
				exhausted = false
			end
		end
		if (character:GetAttribute("Sprinting") == true) ~= sprinting then
			character:SetAttribute("Sprinting", if sprinting then true else nil)
		end
	end
	if sprintSeconds >= 4 then
		report()
	end
	local xp, nextXp = player:GetAttribute("FitXP") or 0, player:GetAttribute("FitNext") or Fitness.XPFor(level)
	ctx.Hud.SetStamina(stamina / st.MaxStamina, level, xp / math.max(1, nextXp), sprinting, exhausted, boost > 1)
end

function Moves.Start(context)
	ctx = context
	RunService.RenderStepped:Connect(function(dt)
		pcall(step, dt)
	end)
	player.CharacterAdded:Connect(function()
		stamina = Fitness.Stats(player:GetAttribute("FitLevel") or 1).MaxStamina
		exhausted = false
		ourSpeed = nil
	end)
end

return Moves
