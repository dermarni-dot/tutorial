-- AnatomyStatus: tells the player (and the Output) whether the organic mesh characters are on.
-- * one Output line per change: "[AnatomyClient] meshes ON" / "[AnatomyClient] meshes OFF: <reason>"
-- * while meshes are OFF because the engine refuses the Editable APIs (the usual cause: the experience's
--   "Allow Mesh / Image APIs" setting is off), a small dismissable notice for the local player, at most
--   once per session; it goes away by itself when the meshes come on (AnatomyClient keeps re-probing)
-- Started by AnatomyClient (boot); polls AnatomyClient.MeshState() twice a second (cheap, no allocations
-- while nothing changes). Owns nothing else: no other UI module is touched.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnatomyStatus = {}

local client -- AnatomyClient
local started = false
local lastLine = nil
local noticeShown = false -- once per session
local gui = nil
local offSince = nil -- meshes OFF continuously since (a start-up budget hiccup recovers within seconds)
local onSince = nil
local stageReported = nil
local NOTICE_DELAY = 6 -- seconds OFF before the notice shows

local SETTING_HINT = "Turn on Game Settings > Security > Allow Mesh / Image APIs"

-- a readable reason from the engine's error text
function AnatomyStatus.Reason(raw)
	local r = tostring(raw or "")
	local l = r:lower()
	if l:find("not enabled") or l:find("allow") or l:find("permission") or l:find("not permitted") or l:find("capabilit")
		or l:find("not authorized") or l:find("verified") or l:find("unauthor") or l:find("not available") then
		return "the Mesh / Image APIs are not enabled for this experience"
	elseif l:find("budget") or l:find("memory") then
		return "this device's mesh memory is full"
	elseif l:find("returned nil") then
		return "the engine created no EditableMesh (APIs off or memory full)"
	end
	-- keep the engine's own words, short
	r = r:gsub("^%s+", ""):gsub("%s+$", "")
	if #r > 140 then
		r = r:sub(1, 137) .. "..."
	end
	return r ~= "" and r or "EditableMesh unavailable"
end

local function hideNotice()
	if gui then
		pcall(function()
			gui:Destroy()
		end)
		gui = nil
	end
end

local function showNotice(reason, memory)
	if noticeShown then
		return
	end
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return -- tried again on the next poll
	end
	noticeShown = true
	local ok = pcall(function()
		local sg = Instance.new("ScreenGui")
		sg.Name = "AnatomyStatusNotice"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 50
		sg.IgnoreGuiInset = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

		local frame = Instance.new("Frame")
		frame.Name = "Notice"
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, -16)
		-- 90 % of narrow (phone) screens, 460 px at most
		frame.Size = UDim2.new(0.9, 0, 0, 74)
		frame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
		frame.BackgroundTransparency = 0.12
		frame.BorderSizePixel = 0
		frame.Parent = sg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(214, 168, 72)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = frame
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(460, 74)
		limit.Parent = frame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 12, 0, 7)
		title.Size = UDim2.new(1, -52, 0, 18)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(240, 200, 110)
		title.Text = "Detailed characters are off (simple look shown)"
		title.Parent = frame

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Position = UDim2.new(0, 12, 0, 26)
		body.Size = UDim2.new(1, -52, 0, 44)
		body.Font = Enum.Font.Gotham
		body.TextSize = 12
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = Color3.fromRGB(225, 220, 212)
		local studio = false
		pcall(function()
			studio = RunService:IsStudio()
		end)
		if memory then
			body.Text = "Reason: " .. reason .. ". Retrying automatically. If it stays off: close other Studio windows, check "
				.. SETTING_HINT:sub(9) .. ", and lower Settings > Graphics detail."
		else
			body.Text = "Reason: " .. reason .. ". " .. SETTING_HINT
				.. (studio and " (publish the place first), then press Play again." or " (game owner, ID-verified).")
		end
		body.Parent = frame

		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -8, 0, 8)
		close.Size = UDim2.new(0, 28, 0, 28)
		close.BackgroundColor3 = Color3.fromRGB(60, 56, 50)
		close.BorderSizePixel = 0
		close.Font = Enum.Font.GothamBold
		close.TextSize = 14
		close.TextColor3 = Color3.fromRGB(240, 236, 228)
		close.Text = "X"
		close.Selectable = true
		close.Parent = frame
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 6)
		cc.Parent = close
		close.Activated:Connect(hideNotice)

		sg.Parent = pg
		gui = sg
	end)
	if not ok then
		hideNotice()
	end
	-- gone by itself after a while (the Output line stays): it should never sit over the game for long
	task.delay(40, hideNotice)
end

local function poll()
	local okS, state, reason, kind = pcall(client.MeshState)
	if not okS then
		return
	end
	if state == "pending" then
		return
	end
	local nice = state == "off" and (kind == "api" and AnatomyStatus.Reason(reason) or tostring(reason)) or nil
	local line = state == "on" and "[AnatomyClient] meshes ON" or ("[AnatomyClient] meshes OFF: " .. nice)
	if line ~= lastLine then
		lastLine = line
		print(line)
	end
	local now = os.clock()
	if state == "on" then
		offSince = nil
		onSince = onSince or now
		hideNotice()
		-- the local character's own progress: one line when it is fully built, or the stage it is stuck in
		local okL, stage, all = pcall(client.LocalStage)
		if okL and stage then
			if all and stageReported ~= "built" then
				stageReported = "built"
				print("[AnatomyClient] local character: " .. stage)
			elseif not all and now - onSince > 30 and stageReported == nil then
				stageReported = "stuck"
				print("[AnatomyClient] local character not built after 30 s: " .. stage .. " (press F8 in Studio for a full report)")
			end
		end
	else
		onSince = nil
		offSince = offSince or now
		if (kind == "api" or kind == "generators") and now - offSince >= NOTICE_DELAY then
			showNotice(nice, kind == "api" and nice:find("memory") ~= nil)
		end
	end
end

-- AnatomyClient changed state (probe result, switch-off): report at once instead of on the next poll
function AnatomyStatus.Changed()
	if client then
		poll()
	end
end

-- what was reported last (tests)
function AnatomyStatus.Last()
	return lastLine, gui ~= nil, noticeShown
end

function AnatomyStatus.Start(anatomyClient)
	if started or not RunService:IsClient() then
		return
	end
	started = true
	client = anatomyClient
	-- F8 (Studio, or with AnatomyClient.Settings.debug): the full diagnostic report in the Output
	pcall(function()
		local UIS = game:GetService("UserInputService")
		UIS.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.F8 and not processed then
				local allowed = client.Settings and client.Settings.debug
				pcall(function()
					allowed = allowed or RunService:IsStudio()
				end)
				if allowed then
					pcall(client.Diagnose)
				end
			end
		end)
	end)
	task.spawn(function()
		while started do
			pcall(poll)
			task.wait(0.5)
		end
	end)
end

return AnatomyStatus
