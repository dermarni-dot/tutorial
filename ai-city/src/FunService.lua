-- FunService (ModuleScript) — ServerScriptService.Modules.FunService
-- Things to do at Funland (the park itself is built by NorthShore; the rides
-- turn on everyone's screen, see the client's Rides module):
--
--   🎈 Balloon Pop   5 coins a go: eight balloons blow up on the back wall and
--                    you have 15 seconds to click (or tap) them. One 🎟️ ticket
--                    per pop, +5 more if you get them all.
--   🎟️ Prizes        trade tickets at the prize booth: a rubber duck, a bunny,
--                    a parrot and a golden pup follow you around (PetService),
--                    or a bag of coins.
--   🧗 Sky Obby      step on the green pad and the clock starts. Checkpoints
--                    save your progress (lava, the spinning bars and falling
--                    send you back to the last one). Reach the finish for coins,
--                    beat your best time for a bonus, and get your name on the
--                    board: the server's five fastest runs.

local Players = game:GetService("Players")

local FunService = {}
local S, NS

local BALLOON_COST = 5
local BALLOON_TIME = 15
local game_ -- the balloon game in progress
local board = {} -- the obby's fastest runs: { Name, Time }

FunService.PRIZES = {
	{ Id = "coins", Name = "Bag of coins", Emoji = "💰", Price = 20, Desc = "50 coins, just like that." },
	{ Id = "Duck", Name = "Rubber Duck", Emoji = "🦆", Price = 15, Desc = "A little duck that waddles after you everywhere.", Pet = true },
	{ Id = "Bunny", Name = "Bunny", Emoji = "🐰", Price = 30, Desc = "A fluffy bunny that hops along behind you.", Pet = true },
	{ Id = "Parrot", Name = "Parrot", Emoji = "🦜", Price = 60, Desc = "A bright parrot that flies at your shoulder.", Pet = true },
	{ Id = "GoldenPup", Name = "Golden Pup", Emoji = "🐶", Price = 150, Desc = "The grand prize: a shining golden puppy.", Pet = true },
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function addTickets(player, n)
	local pd = S.City.Data(player)
	if not pd then
		return 0
	end
	pd.Tickets = (pd.Tickets or 0) + n
	player:SetAttribute("Tickets", pd.Tickets)
	return pd.Tickets
end
FunService.AddTickets = addTickets

--------------------------------------------------------------------------------
-- 🎈 Balloon Pop
--------------------------------------------------------------------------------
local function endBalloons()
	local g = game_
	if not g then
		return
	end
	game_ = nil
	for _, b in ipairs(g.Balloons) do
		if b.Parent then
			b:Destroy()
		end
	end
	local player = g.Player
	if not player.Parent then
		return
	end
	local bonus = if g.Popped == #g.Balloons then 5 else 0
	if bonus > 0 then
		addTickets(player, bonus)
	end
	local total = (player:GetAttribute("Tickets") or 0)
	S.City.Toast(player, "🎈", "Popped " .. g.Popped .. " of " .. #g.Balloons .. "!", "+" .. (g.Popped + bonus) .. " 🎟️ tickets" .. (if bonus > 0 then " (all of them: +5 bonus!)" else "") .. ". You have " .. total .. ". Trade them at the 🎟️ prize booth next door.", rgb(80, 170, 240))
end

function FunService.Pop(player, balloon)
	local g = game_
	if not g or g.Player ~= player or not balloon.Parent or not table.find(g.Balloons, balloon) then
		return false
	end
	local pos = balloon.Position
	balloon:Destroy()
	g.Popped += 1
	addTickets(player, 1)
	S.City.SendNear(pos, 90, { Type = "Pop", Position = pos, Color = balloon.Color })
	if g.Popped >= #g.Balloons then
		endBalloons()
	end
	return true
end

function FunService.PlayBalloons(player)
	if game_ and game_.Player.Parent and os.clock() < game_.Until then
		S.City.Toast(player, "⏳", "Someone's playing", (if game_.Player == player then "That's you! Pop them!" else game_.Player.DisplayName .. " is up. Wait a few seconds."), rgb(200, 160, 60))
		return false
	end
	if not S.City.Spend(player, BALLOON_COST, "🎈 Balloon Pop") then
		S.City.Toast(player, "🪙", "Not enough coins", "Balloon Pop costs " .. BALLOON_COST .. " coins.", rgb(220, 90, 80))
		return false
	end
	local g = { Player = player, Until = os.clock() + BALLOON_TIME, Balloons = {}, Popped = 0 }
	game_ = g
	local colors = { rgb(255, 70, 90), rgb(255, 200, 40), rgb(80, 170, 255), rgb(120, 220, 110), rgb(200, 110, 255), rgb(255, 140, 50) }
	for k, pos in ipairs(NS.BalloonGame.Slots) do
		local b = Instance.new("Part")
		b.Name = "Balloon"
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.one * 1.9
		b.Color = colors[(k - 1) % #colors + 1]
		b.Material = Enum.Material.SmoothPlastic
		b.Reflectance = 0.25
		b.Anchored, b.CanCollide = true, false
		b.CFrame = CFrame.new(pos)
		b.Parent = NS.Model
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 60
		click.Parent = b
		pcall(function()
			click.MouseClick:Connect(function(who)
				FunService.Pop(who, b)
			end)
		end)
		table.insert(g.Balloons, b)
	end
	S.City.Toast(player, "🎈", "Pop the balloons!", "Click or tap them: " .. BALLOON_TIME .. " seconds, go!", rgb(80, 170, 240))
	task.delay(BALLOON_TIME, function()
		if game_ == g then
			endBalloons()
		end
	end)
	return true
end

--------------------------------------------------------------------------------
-- 🎟️ The prize booth
--------------------------------------------------------------------------------
local function prizeStore(player)
	local pd = S.City.Data(player)
	local items = {}
	for _, p in ipairs(FunService.PRIZES) do
		local owned = p.Pet and pd and pd.Pets and pd.Pets[p.Id] == true
		table.insert(items, { Id = p.Id, Name = p.Name, Emoji = p.Emoji, Price = p.Price, Desc = p.Desc, Owned = owned, UseText = "🐾 Walk with me", Using = owned and pd.Pet and pd.Pet.Id == p.Id })
	end
	return { Title = "Prize Booth", Emoji = "🎟️", Currency = "tickets", Balance = pd and pd.Tickets or 0, Action = "Prize", BuyText = "Get", Items = items, Note = "Win tickets at 🎈 Balloon Pop (and the Sky Obby gives tickets too). Prize pets follow you around: pick which one in the 🐾 pet stand or here." }
end

function FunService.Prize(player, data)
	local pd = S.City.Data(player)
	local prize
	for _, p in ipairs(FunService.PRIZES) do
		if p.Id == data.Id then
			prize = p
		end
	end
	if not pd or not prize then
		return { Ok = false, Error = "That's not a prize." }
	end
	if data.Op == "use" and prize.Pet and pd.Pets[prize.Id] then
		if S.Pets then
			S.Pets.Equip(player, prize.Id)
		end
		return { Ok = true, Store = prizeStore(player), Toast = { prize.Emoji, prize.Name .. " is with you", "" } }
	end
	if prize.Pet and pd.Pets[prize.Id] then
		return { Ok = false, Error = "You already won that one." }
	end
	if (pd.Tickets or 0) < prize.Price then
		return { Ok = false, Error = "You need " .. prize.Price .. " tickets (you have " .. (pd.Tickets or 0) .. ")." }
	end
	addTickets(player, -prize.Price)
	if prize.Id == "coins" then
		S.City.AddCoins(player, 50, "🎟️ Prize: a bag of coins")
	elseif S.Pets then
		S.Pets.Give(player, prize.Id)
	end
	return { Ok = true, Store = prizeStore(player), Toast = { prize.Emoji, "You won: " .. prize.Name .. "!", if prize.Pet then "It's following you around now." else "" } }
end

--------------------------------------------------------------------------------
-- 🧗 The Sky Obby
--------------------------------------------------------------------------------
local function top(part)
	return part.Position + Vector3.new(0, part.Size.Y / 2, 0)
end

local function drawBoard()
	local o = NS.Obby
	local gui = o.Board:FindFirstChild("ObbyBoardGui")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "ObbyBoardGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = o.Board
	end
	local lines = { "🏆 FASTEST RUNS" }
	for k = 1, 5 do
		local e = board[k]
		table.insert(lines, if e then string.format("%d. %s  %.1fs", k, e.Name, e.Time) else k .. ". ---")
	end
	gui.Text.Text = table.concat(lines, "\n")
end

-- someone stepped on the start pad, a checkpoint or the finish
function FunService.ObbyTouch(player, what)
	local o = NS.Obby
	local now = workspace:GetServerTimeNow()
	if what == "start" then
		if player:GetAttribute("ObbyStart") and now - player:GetAttribute("ObbyStart") < 3 then
			return
		end
		player:SetAttribute("ObbyStart", now)
		player:SetAttribute("ObbyCP", 0)
		player:SetAttribute("ObbyCheckpoint", top(o.Start))
		S.City.Toast(player, "🧗", "Sky Obby: GO!", "Jump to the finish. Checkpoints save your spot; lava and the red bars send you back.", rgb(90, 200, 120))
		return "started"
	end
	local started = player:GetAttribute("ObbyStart")
	if not started then
		return nil
	end
	if type(what) == "number" then
		if what > (player:GetAttribute("ObbyCP") or 0) then
			player:SetAttribute("ObbyCP", what)
			player:SetAttribute("ObbyCheckpoint", top(o.Checkpoints[what]))
			S.City.Toast(player, "🚩", "Checkpoint " .. what .. "!", string.format("%.1f seconds so far.", now - started), rgb(250, 210, 60))
			return "checkpoint"
		end
		return nil
	end
	if what == "finish" then
		local t = now - started
		player:SetAttribute("ObbyStart", nil)
		player:SetAttribute("ObbyCP", nil)
		player:SetAttribute("ObbyCheckpoint", nil)
		local pd = S.City.Data(player)
		local best = pd and pd.ObbyBest
		local record = not best or t < best
		if pd and record then
			pd.ObbyBest = t
		end
		local coins = 40 + (if record then 30 else 0)
		S.City.AddCoins(player, coins, "🧗 Sky Obby")
		addTickets(player, 5)
		table.insert(board, { Name = player.DisplayName, Time = t })
		table.sort(board, function(a, b)
			return a.Time < b.Time
		end)
		while #board > 5 do
			table.remove(board)
		end
		drawBoard()
		S.City.Toast(player, "🏁", string.format("Finished in %.1fs!", t), "+" .. coins .. " coins and 5 🎟️ tickets" .. (if record then " · a new personal best!" else string.format(" · your best is %.1fs", best)), rgb(80, 220, 255))
		S.City.News(string.format("🧗 %s ran the Sky Obby in %.1f seconds!", player.DisplayName, t), "City", true)
		-- down the slide: back to the start
		task.delay(2.5, function()
			local root = rootOf(player)
			if root then
				root.CFrame = CFrame.new(top(o.Start) + Vector3.new(6, 3, 0))
			end
		end)
		return t
	end
end

local function hookTouch(part, what)
	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			FunService.ObbyTouch(player, what)
		end
	end)
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------
local function prompt(part, action, object, fn)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(fn)
	return p
end

function FunService.Start(services)
	S = services
	NS = S.Map and S.Map.NorthShore
	if not NS then
		return
	end
	prompt(NS.BalloonGame.Prompt, "Play Balloon Pop", "🎈 " .. BALLOON_COST .. " coins", FunService.PlayBalloons)
	prompt(NS.PrizeDesk, "Trade tickets", "🎟️ Prize Booth", function(player)
		local d = prizeStore(player)
		d.Type = "Store"
		S.City.Send(player, d)
	end)
	S.City.Handle("Prize", FunService.Prize)
	S.City.Handle("PrizeStore", function(player)
		return { Ok = true, Store = prizeStore(player) }
	end)
	hookTouch(NS.Obby.Start, "start")
	for k, cp in ipairs(NS.Obby.Checkpoints) do
		hookTouch(cp, k)
	end
	hookTouch(NS.Obby.Finish, "finish")
	drawBoard()
	local function show(player)
		local pd = S.City.Data(player)
		if pd then
			player:SetAttribute("Tickets", pd.Tickets or 0)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.delay(2, show, player)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		show(p)
	end
end

FunService.Board = board
function FunService.Balloons()
	return game_
end

return FunService
