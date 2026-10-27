-- DiagClient: runs the rig diagnostic (Shared.Diag) on this client and asks the server for its own view of the same
-- models. Invoked by "/wcbdiag" in chat (Player.Chatted and a TextChatCommand, whichever chat the place runs) or the
-- Settings -> GAME -> COPY DIAGNOSTIC TO OUTPUT button; nothing runs otherwise. Reports: the local character and the
-- nearest two other humanoid models (NPCs, other players), each as one [WCBDIAG] block in the Output, then a 4-second
-- motion sample of each at 10 Hz (walk or punch while it runs) and the server's blocks (the same models as the server
-- sees them: part sizes, HipHeight, the swap counters). Copy everything between the first "== " and the last "== end".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Diag = require(Shared:WaitForChild("Diag"))
local BuilderTiers = require(Shared:WaitForChild("BuilderTiers"))

local DiagClient = {}
DiagClient.COMMAND = "/wcbdiag"
DiagClient.SAMPLE_SECONDS = 4
DiagClient.WAIT_FOR_MOVE = 15 -- the sample starts when the local character moves (time to leave the chat box)
DiagClient.SAMPLE_HZ = 10
DiagClient.NEARBY = 2

local player = Players.LocalPlayer
local Modules = script.Parent
local running = false

local function rigOf(model)
	local ok, R = pcall(function()
		return require(Modules:WaitForChild("AnimRig", 5))
	end)
	return ok and type(R) == "table" and type(R.rigs) == "table" and R.rigs[model] or nil
end

local function say(msg)
	print(Diag.PREFIX .. msg)
end

-- the whole run (yields ~2 s for the sample); State = BoxerClient.State for the server request (optional)
function DiagClient.Run(State)
	if running then
		say("already running")
		return
	end
	running = true
	local ok, err = pcall(function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		local center = root and root.Position or (cam and cam.CFrame.Position) or Vector3.zero
		local models = Diag.Pick(center, char, DiagClient.NEARBY)
		say(string.format("v%d client report: %d model(s); place %s; %s; body part swaps refused on this client: %d", Diag.VERSION, #models,
			tostring(game.PlaceId), RunService:IsStudio() and "Studio" or "live", BuilderTiers.SwapFailures))
		if #models == 0 then
			say("no humanoid models found (no character yet?)")
			return
		end
		local ctxs = {}
		for i, m in ipairs(models) do
			local ctx = { label = m == char and "LOCAL" or ("NPC" .. i - (char and 1 or 0)), side = "client", rig = rigOf(m) }
			ctxs[i] = ctx
			Diag.Print(m, ctx)
		end
		-- the server's view in parallel with the sample (it prints to the same Output in Studio; in a live server it
		-- prints to the server log and answers with its lines, printed here)
		if State and type(State.req) == "function" then
			task.spawn(function()
				local names = {}
				for _, m in ipairs(models) do
					table.insert(names, m.Name)
				end
				local r = State.req("Diag", names)
				if type(r) == "table" and r.ok and type(r.lines) == "table" then
					for _, block in ipairs(r.lines) do
						print(block)
					end
				elseif type(r) == "table" and r.err then
					say("server report: " .. tostring(r.err))
				end
			end)
		end
		-- the motion sample: walk / punch while it runs
		-- typing the command leaves the keyboard in the chat box: the sample waits for the character to move (or a
		-- punch: any joint change shows in the bends), up to WAIT_FOR_MOVE seconds, so a run is caught mid-stride
		say(string.format("RUN or WALK now (click the game, hold W, Shift to run): the %d s sample starts when you move (waits up to %d s)",
			DiagClient.SAMPLE_SECONDS, DiagClient.WAIT_FOR_MOVE))
		local w0 = os.clock()
		while root and root.Parent and os.clock() - w0 < DiagClient.WAIT_FOR_MOVE do
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > 1 then
				task.wait(0.4) -- (past the first step's acceleration)
				break
			end
			RunService.Heartbeat:Wait()
		end
		say(string.format("sampling %d model(s) for %d s at %d Hz: keep moving", #models, DiagClient.SAMPLE_SECONDS, DiagClient.SAMPLE_HZ))
		local samples = {}
		for i, m in ipairs(models) do
			samples[i] = Diag.NewSample()
		end
		local t0 = os.clock()
		local period = 1 / DiagClient.SAMPLE_HZ
		local nextT = 0
		while os.clock() - t0 < DiagClient.SAMPLE_SECONDS do
			local t = os.clock() - t0
			if t >= nextT then
				nextT += period
				for i, m in ipairs(models) do
					if m.Parent then
						pcall(Diag.SampleTick, samples[i], m, t)
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
		for i, m in ipairs(models) do
			if m.Parent then
				local res = Diag.SampleLines(samples[i])
				local lines = { "== sample " .. (ctxs[i].label or "") .. " " .. m.Name }
				for _, l in ipairs(res.lines) do
					table.insert(lines, l)
				end
				for _, v in ipairs(res.verdicts) do
					table.insert(lines, "VERDICT " .. v)
				end
				table.insert(lines, "== end sample " .. m.Name)
				print(Diag.Block(lines))
			end
		end
		say("done: copy every [WCBDIAG] line from the Output (right-click > Select All in the Output, or filter it on WCBDIAG)")
	end)
	running = false
	if not ok then
		say("diagnostic failed: " .. tostring(err))
	end
end

-- the chat command and the Settings hook (State.open.Diag)
function DiagClient.Start(State)
	if State and type(State.open) == "table" then
		State.open.Diag = function()
			task.spawn(DiagClient.Run, State)
		end
	end
	local function onText(text)
		if type(text) == "string" and text:lower():sub(1, #DiagClient.COMMAND) == DiagClient.COMMAND then
			task.spawn(DiagClient.Run, State)
			return true
		end
		return false
	end
	pcall(function()
		player.Chatted:Connect(onText)
	end)
	-- TextChatService (the default chat since 2023: a TextChatCommand fires on the sending client)
	pcall(function()
		local TCS = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "WCBDiagCommand"
		cmd.PrimaryAlias = DiagClient.COMMAND
		cmd.SecondaryAlias = "/wcbd"
		cmd.Triggered:Connect(function(origin)
			if origin == nil or origin.UserId == player.UserId then
				task.spawn(DiagClient.Run, State)
			end
		end)
		cmd.Parent = TCS
	end)
end

return DiagClient
