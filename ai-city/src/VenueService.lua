-- VenueService (ModuleScript) — ServerScriptService.Modules.VenueService
-- Things to do at the new places on the backs of the downtown blocks:
--   🎳 Bowling: press E at a lane. An arrow swings back and forth across the
--      lane; your ball goes where it points. Dead center is a STRIKE.
--   🎤 Karaoke at the Neon Nightclub: sing on the stage. Everyone around
--      cheers, claps or dances, and they tip you when you finish.
--   🧽 The car wash: drive your car into the tunnel. Foam, spinning brushes,
--      and your car sparkles for a few minutes.
--   ⛳ Mini golf: six holes. A power bar swells and shrinks on the tee; putt
--      when it's just right to sink it. Finish all six for a score.
--   💈 The barbershop: dye your hair a new colour.
--   🎨 The art gallery: paint a picture. It goes up on the visitors' wall
--      with your name under it, and people stop to admire it.
--   🐠 The aquarium: feed the fish (they come racing up).
--   🧘 The yoga studio: join the class: heals you and fills your energy.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local VenueService = {}
local S

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function prompt(parent, text, object, hold, fn)
	local p = Instance.new("ProximityPrompt")
	p.Name = "VenuePrompt"
	p.ActionText = text
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Parent = parent
	p.Triggered:Connect(fn)
	return p
end

local function emote(player, name, seconds)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Emote", name)
	task.delay(seconds, function()
		if character.Parent and character:GetAttribute("Emote") == name then
			character:SetAttribute("Emote", nil)
		end
	end)
end

local function anchorPart(name, cf, parent)
	local a = Instance.new("Part")
	a.Name = name
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1)
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function crowd(pos, radius, actions, lines, seconds)
	local n = 0
	for _, b in ipairs(S.Citizens.Nearby(pos, radius)) do
		if S.Citizens.CanReact(b) and not b.Staff and b.Model:GetAttribute("Action") ~= "sleep" then
			n += 1
			S.Citizens.React(b, actions[(n - 1) % #actions + 1], if n <= 2 and lines then lines[math.random(1, #lines)] else nil, "happy", seconds or 3, pos)
		end
	end
	return n
end

local function playersNear(pos, radius)
	for _, p in ipairs(Players:GetPlayers()) do
		local r = rootOf(p)
		if r and (r.Position - pos).Magnitude < radius then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- 🎳 Bowling
--------------------------------------------------------------------------------
local lanes = {}
VenueService.Lanes = lanes
VenueService.BOWL_COST = 3

local function laneScreen(lane, text)
	local screen
	for _, d in ipairs(lane.Part.Parent:GetChildren()) do
		if d.Name == "ScoreScreen" and d:GetAttribute("Lane") == lane.Part:GetAttribute("Lane") and (d.Position - lane.Part.Position).Magnitude < lane.Length then
			screen = d
		end
	end
	if not screen then
		return
	end
	local gui = screen:FindFirstChild("ScoreGui")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "ScoreGui"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = screen
		local label = Instance.new("TextLabel")
		label.Name = "Score"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = rgb(255, 230, 120)
		label.Parent = gui
	end
	gui.Score.Text = text
end

-- where the aim arrow points right now (-1 left gutter .. 1 right gutter)
function VenueService.Aim(lane, now)
	return math.sin((now or os.clock()) * 2.6 + lane.Phase)
end

-- pins knocked down by a ball rolled at aim a
function VenueService.PinsFor(a, rand)
	local off = math.abs(a)
	if off < 0.14 then
		return 10
	end
	local n = math.floor(10 * (1 - off ^ 1.2) + 0.5) + (rand or 0)
	return math.clamp(n, 0, 9)
end

local function bowl(player, lane)
	local root = rootOf(player)
	if not root or lane.Busy then
		return
	end
	if not S.City.Spend(player, VenueService.BOWL_COST, "🎳 Bowling") then
		S.City.Toast(player, "🪙", "Not enough coins", "A ball costs " .. VenueService.BOWL_COST .. " coins.", rgb(220, 120, 80))
		return
	end
	lane.Busy = true
	local a = VenueService.Aim(lane)
	local pins = VenueService.PinsFor(a, math.random(-1, 1))
	emote(player, "bowl", 1.6)
	-- the ball rolls down the lane
	local p = lane.Part
	local start = p.CFrame * CFrame.new(a * p.Size.X * 0.42, 0.6, -p.Size.Z / 2 + 1.5)
	local ball = Instance.new("Part")
	ball.Name = "RollingBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.1, 1.1, 1.1)
	ball.Color = rgb(30, 60, 160)
	ball.Anchored, ball.CanCollide, ball.CanQuery = true, false, false
	ball.CFrame = start
	ball.Parent = p.Parent
	lane.Ball = ball
	task.spawn(function()
		local len = p.Size.Z - 3
		for k = 1, 16 do
			ball.CFrame = start * CFrame.new(0, 0, len * k / 16) * CFrame.Angles(k * 0.8, 0, 0)
			task.wait(0.09)
		end
		ball:Destroy()
		-- knock over the pins (the ones nearest the ball's line go first)
		local list = {}
		for _, pin in ipairs(lane.Pins) do
			table.insert(list, pin)
		end
		local hit = start.Position
		table.sort(list, function(x, y)
			local dx = math.abs(p.CFrame:PointToObjectSpace(x.Part.Position).X - p.CFrame:PointToObjectSpace(hit).X)
			local dy = math.abs(p.CFrame:PointToObjectSpace(y.Part.Position).X - p.CFrame:PointToObjectSpace(hit).X)
			return dx < dy
		end)
		for k = 1, pins do
			local pin = list[k]
			pin.Part.CFrame = pin.Home * CFrame.new(0, -0.6, 0) * CFrame.Angles(math.random(-1, 1) * 0.5, 0, math.rad(90) + math.random() * 0.4)
		end
		local text
		if pins == 10 then
			text = "STRIKE! 🎳"
			S.City.AddCoins(player, 15, "🎳 Strike!")
			S.City.Toast(player, "🎳", "STRIKE!", "All ten pins! +15 coins.", rgb(250, 200, 60))
			crowd(p.Position, 40, { "cheer", "clap" }, { "STRIKE!", "Whoa, nice one!", "Yeah!!" }, 3)
		elseif pins >= 7 then
			text = pins .. " pins!"
			S.City.AddCoins(player, 4, "🎳 " .. pins .. " pins")
			S.City.Toast(player, "🎳", pins .. " pins", "So close! +4 coins. Time it when the arrow's in the middle.", rgb(120, 180, 250))
		elseif pins == 0 then
			text = "Gutter ball..."
			S.City.Toast(player, "🎳", "Gutter ball!", "Wait for the arrow to swing to the middle.", rgb(200, 120, 120))
		else
			text = pins .. " pins"
			S.City.Toast(player, "🎳", pins .. " pins", "Time it when the arrow's in the middle.", rgb(120, 180, 250))
		end
		laneScreen(lane, player.DisplayName .. ": " .. text)
		lane.Last = { Player = player, Pins = pins }
		task.wait(2.2)
		for _, pin in ipairs(lane.Pins) do
			pin.Part.CFrame = pin.Home
		end
		lane.Busy = false
	end)
	return pins
end
VenueService.Bowl = bowl

local function setupLanes()
	for _, part in ipairs(CollectionService:GetTagged("BowlingLane")) do
		local lane = { Part = part, Pins = {}, Phase = math.random() * 6, Length = part.Size.Z }
		for _, pin in ipairs(CollectionService:GetTagged("BowlingPin")) do
			if pin:GetAttribute("Lane") == part:GetAttribute("Lane") and (pin.Position - part.Position).Magnitude < part.Size.Z then
				table.insert(lane.Pins, { Part = pin, Home = pin.CFrame })
			end
		end
		-- the aim arrow at the foul line
		local arrow = Instance.new("Part")
		arrow.Name = "AimArrow"
		arrow.Anchored, arrow.CanCollide, arrow.CanQuery, arrow.CanTouch = true, false, false, false
		arrow.Material = Enum.Material.Neon
		arrow.Color = rgb(255, 220, 60)
		arrow.Size = Vector3.new(0.5, 0.15, 2.4)
		arrow.CFrame = part.CFrame * CFrame.new(0, 0.2, -part.Size.Z / 2 + 3)
		arrow.Parent = part.Parent
		lane.Arrow = arrow
		local at = anchorPart("LaneStart", part.CFrame * CFrame.new(0, 2.5, -part.Size.Z / 2 - 1), part.Parent)
		prompt(at, "Bowl (" .. VenueService.BOWL_COST .. " coins)", "🎳 Lane " .. tostring(part:GetAttribute("Lane")), 0, function(player)
			bowl(player, lane)
		end)
		table.insert(lanes, lane)
	end
end

local function stepLanes(now)
	for _, lane in ipairs(lanes) do
		if lane.Arrow.Parent and playersNear(lane.Part.Position, 60) then
			local a = VenueService.Aim(lane, now)
			local p = lane.Part
			lane.Arrow.CFrame = p.CFrame * CFrame.new(a * p.Size.X * 0.42, 0.2, -p.Size.Z / 2 + 3)
			lane.Arrow.Color = if math.abs(a) < 0.14 then rgb(90, 255, 120) else rgb(255, 220, 60)
		end
	end
end

--------------------------------------------------------------------------------
-- 🎤 Karaoke
--------------------------------------------------------------------------------
local singing = {}
VenueService.Singing = singing
local SONGS = { "♪ Don't stop believin'... ♪", "♫ I will always love youuuu ♫", "♪ We will, we will ROCK YOU ♪", "♫ Here comes the sun ♫", "♪ Sweet Caroline! BA BA BAAA ♪", "♫ Bohemian rhapsodyyy ♫" }
local CHEERS = { "Woooo!", "Encore!", "You're amazing!", "Sing it!", "I love this song!" }

local function sing(player, mic)
	local root = rootOf(player)
	if not root then
		return
	end
	local now = os.clock()
	if singing[player] and now < singing[player] then
		return
	end
	singing[player] = now + 24
	emote(player, "sing", 10)
	local song = SONGS[math.random(1, #SONGS)]
	S.City.Toast(player, "🎤", "You're singing!", song, rgb(240, 90, 200))
	local pos = mic.Position
	local fans = crowd(pos, 40, { "dance", "cheer", "clap", "dance" }, CHEERS, 10)
	task.delay(10, function()
		if not player.Parent then
			return
		end
		local tips = math.min(30, 3 + fans * 3)
		S.City.AddCoins(player, tips, "🎤 Karaoke tips")
		S.City.Toast(player, "🎤", if fans >= 3 then "ENCORE! The crowd loved it" else "Nice song!", fans .. " people listened. +" .. tips .. " coins in tips.", rgb(240, 90, 200))
		crowd(pos, 40, { "clap", "cheer" }, { "Bravo!", "Encore! Encore!", "That was great!" }, 3)
	end)
	return fans
end
VenueService.Sing = sing

--------------------------------------------------------------------------------
-- 🧽 The car wash
--------------------------------------------------------------------------------
VenueService.WASH_COST = 8
local washed = {} -- [car model] = os.clock() when it can be washed again
local function inside(zone, pos)
	local p = zone.CFrame:PointToObjectSpace(pos)
	local h = zone.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y + 4 and math.abs(p.Z) <= h.Z
end

local function startWash(player, car, zone)
	washed[car] = os.clock() + 40
	if not S.City.Spend(player, VenueService.WASH_COST, "🧽 Car wash") then
		S.City.Toast(player, "🪙", "Not enough coins", "The car wash costs " .. VenueService.WASH_COST .. " coins.", rgb(220, 120, 80))
		return false
	end
	S.City.Toast(player, "🧽", "Sparkle Car Wash", "Foam, brushes, rinse... hold still!", rgb(80, 170, 240))
	local model = zone.Parent
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "Foam" then
			d.Rate = 60
		end
	end
	model:SetAttribute("Washing", true)
	task.delay(4, function()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Name == "Foam" then
				d.Rate = 0
			end
		end
		model:SetAttribute("Washing", nil)
		local body = car.PrimaryPart
		if body and body.Parent then
			local old = body:FindFirstChild("Shine")
			if old then
				old:Destroy()
			end
			local shine = Instance.new("Sparkles")
			shine.Name = "Shine"
			shine.SparkleColor = rgb(200, 240, 255)
			shine.Parent = body
			car:SetAttribute("Shiny", true)
			task.delay(180, function()
				if shine.Parent then
					shine:Destroy()
				end
				if car.Parent then
					car:SetAttribute("Shiny", nil)
				end
			end)
		end
		if player.Parent then
			S.City.Toast(player, "✨", "Squeaky clean!", "Your car sparkles for 3 minutes. People will notice.", rgb(120, 220, 250))
		end
	end)
	return true
end
VenueService.StartWash = startWash

local function stepWash()
	local zones = CollectionService:GetTagged("CarWashZone")
	if #zones == 0 or not S.Cars then
		return
	end
	for player, car in pairs(S.Cars.Spawned or {}) do
		local body = car and car.Parent and car.PrimaryPart
		if body and (washed[car] or 0) < os.clock() then
			for _, zone in ipairs(zones) do
				if inside(zone, body.Position) then
					startWash(player, car, zone)
					break
				end
			end
		end
	end
	for car in pairs(washed) do
		if not car.Parent then
			washed[car] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- ⛳ Mini golf
--------------------------------------------------------------------------------
local golfers = {} -- [player] = { Strokes = { [hole] = n }, Sunk = { [hole] = true } }
VenueService.Golfers = golfers
VenueService.HOLES = 6
VenueService.IDEAL = 0.62

-- the power bar right now, 0..1
function VenueService.Power(now)
	return (math.sin((now or os.clock()) * 2.1) + 1) / 2
end

local tees = {}
local function putt(player, tee, power)
	local root = rootOf(player)
	if not root then
		return
	end
	local hole = tee:GetAttribute("Hole")
	local g = golfers[player]
	if not g then
		g = { Strokes = {}, Sunk = {} }
		golfers[player] = g
	end
	if g.Sunk[hole] then
		S.City.Toast(player, "⛳", "Hole " .. hole .. " done", "You sank this one in " .. g.Strokes[hole] .. ". Try another hole!", rgb(120, 200, 120))
		return
	end
	if g.Busy then
		return
	end
	g.Busy = true
	power = power or VenueService.Power()
	g.Strokes[hole] = (g.Strokes[hole] or 0) + 1
	local strokes = g.Strokes[hole]
	local err = math.abs(power - VenueService.IDEAL)
	local sunk = err < 0.09 or strokes >= 4 or (err < 0.2 and strokes >= 2)
	emote(player, "putt", 1.4)
	-- the ball rolls toward the cup (short, long, or in)
	local cup = tee:GetAttribute("Cup")
	local from = tee.Position + Vector3.new(0, 0.5, 0)
	local dir = Vector3.new(cup.X - from.X, 0, cup.Z - from.Z)
	local reach = if sunk then 1 else math.clamp(power / VenueService.IDEAL, 0.2, 1.3)
	local ball = Instance.new("Part")
	ball.Name = "GolfBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.5, 0.5, 0.5)
	ball.Color = rgb(250, 250, 250)
	ball.Anchored, ball.CanCollide, ball.CanQuery = true, false, false
	ball.CFrame = CFrame.new(from)
	ball.Parent = tee.Parent
	task.spawn(function()
		for k = 1, 12 do
			local u = 1 - (1 - k / 12) ^ 2
			ball.CFrame = CFrame.new(from + dir * reach * u)
			task.wait(0.07)
		end
		if sunk then
			ball.CFrame = ball.CFrame * CFrame.new(0, -0.4, 0)
		end
		task.wait(0.8)
		ball:Destroy()
		g.Busy = false
	end)
	if sunk then
		g.Sunk[hole] = true
		local done = 0
		local total = 0
		for h = 1, VenueService.HOLES do
			if g.Sunk[h] then
				done += 1
				total += g.Strokes[h]
			end
		end
		local word = if strokes == 1 then "HOLE IN ONE!" elseif strokes == 2 then "Birdie!" else "In the cup"
		S.City.Toast(player, "⛳", word, "Hole " .. hole .. " in " .. strokes .. (if strokes == 1 then " stroke" else " strokes") .. ". " .. done .. "/" .. VenueService.HOLES .. " holes done.", rgb(120, 220, 120))
		if strokes == 1 then
			S.City.AddCoins(player, 6, "⛳ Hole in one")
			crowd(tee.Position, 30, { "cheer", "clap" }, { "HOLE IN ONE!", "No way!" }, 3)
		end
		if done == VenueService.HOLES then
			local coins = math.max(5, 40 - (total - VenueService.HOLES) * 3)
			S.City.AddCoins(player, coins, "⛳ Mini golf")
			S.City.Toast(player, "🏆", "Round finished: " .. total .. " strokes", "Par is " .. VenueService.HOLES * 2 .. ". +" .. coins .. " coins.", rgb(250, 200, 60))
			local pd = S.City.Data(player)
			if pd and (not pd.GolfBest or total < pd.GolfBest) then
				pd.GolfBest = total
				S.City.News("⛳ " .. player.DisplayName .. " went round the mini golf in " .. total .. " strokes!", "Fun")
			end
			golfers[player] = nil
		end
	else
		S.City.Toast(player, "⛳", if power > VenueService.IDEAL then "Too hard!" else "Too soft!", "Putt when the bar's about two-thirds full. Stroke " .. strokes .. ".", rgb(200, 200, 120))
	end
	return sunk
end
VenueService.Putt = putt

local function setupGolf()
	for _, tee in ipairs(CollectionService:GetTagged("GolfTee")) do
		local bar = Instance.new("Part")
		bar.Name = "PowerBar"
		bar.Anchored, bar.CanCollide, bar.CanQuery, bar.CanTouch = true, false, false, false
		bar.Material = Enum.Material.Neon
		bar.Size = Vector3.new(0.4, 0.4, 0.4)
		bar.CFrame = tee.CFrame * CFrame.new(2, 0.2, 0)
		bar.Parent = tee.Parent
		table.insert(tees, { Tee = tee, Bar = bar })
		prompt(tee, "Putt", "⛳ Hole " .. tostring(tee:GetAttribute("Hole")), 0, function(player)
			putt(player, tee)
		end)
	end
end

local function stepGolf(now)
	local power = VenueService.Power(now)
	for _, t in ipairs(tees) do
		if playersNear(t.Tee.Position, 40) then
			local h = 0.4 + power * 3
			t.Bar.Size = Vector3.new(0.4, h, 0.4)
			t.Bar.CFrame = t.Tee.CFrame * CFrame.new(2, h / 2, 0)
			t.Bar.Color = if math.abs(power - VenueService.IDEAL) < 0.09 then rgb(90, 255, 120) elseif power > VenueService.IDEAL then rgb(255, 90, 80) else rgb(255, 220, 60)
		end
	end
end

--------------------------------------------------------------------------------
-- 💈 Hair dye
--------------------------------------------------------------------------------
VenueService.DYES = { { "Jet black", rgb(25, 22, 22) }, { "Chestnut", rgb(110, 60, 30) }, { "Golden blonde", rgb(235, 200, 110) }, { "Fire red", rgb(200, 50, 30) }, { "Bubblegum pink", rgb(250, 120, 190) }, { "Electric blue", rgb(50, 120, 250) }, { "Lavender", rgb(170, 130, 240) }, { "Mint", rgb(110, 220, 170) }, { "Silver", rgb(210, 214, 222) } }
VenueService.DYE_COST = 10
local dyeIndex = {}

local function applyDye(character, color)
	local n = 0
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local isHair = string.find(string.lower(acc.Name), "hair") ~= nil
			pcall(function()
				isHair = isHair or acc.AccessoryType == Enum.AccessoryType.Hair
			end)
			local handle = acc:FindFirstChild("Handle")
			if isHair and handle then
				pcall(function()
					if handle:IsA("MeshPart") then
						handle.TextureID = ""
					end
				end)
				local mesh = handle:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					mesh.TextureId = ""
				end
				handle.Color = color
				n += 1
			end
		end
	end
	character:SetAttribute("HairDye", color)
	return n
end
VenueService.ApplyDye = applyDye

local function dye(player)
	local character = player.Character
	if not character then
		return
	end
	if not S.City.Spend(player, VenueService.DYE_COST, "💈 Hair dye") then
		S.City.Toast(player, "🪙", "Not enough coins", "A new colour costs " .. VenueService.DYE_COST .. " coins.", rgb(220, 120, 80))
		return
	end
	local k = (dyeIndex[player] or 0) % #VenueService.DYES + 1
	dyeIndex[player] = k
	local d = VenueService.DYES[k]
	local n = applyDye(character, d[2])
	local pd = S.City.Data(player)
	if pd then
		pd.HairDye = { d[2].R, d[2].G, d[2].B }
	end
	S.City.Toast(player, "💈", d[1] .. "!", if n > 0 then "Fresh new colour. Come back for another one." else "(Your avatar has no hair to dye, but the barber tried.)", d[2])
	for _, b in ipairs(S.Citizens.Nearby(rootOf(player).Position, 20)) do
		if S.Citizens.CanReact(b) and b.Model:GetAttribute("Action") ~= "sleep" then
			S.Citizens.Say(b, ({ "Ooh, " .. string.lower(d[1]) .. "! Suits you.", "Love the new look!", "Bold choice!" })[math.random(1, 3)], "happy", 2.5)
			break
		end
	end
	return d[1]
end
VenueService.Dye = dye

--------------------------------------------------------------------------------
-- 🎨 Painting at the gallery
--------------------------------------------------------------------------------
local paintings = {} -- [wall] = { models }
local SHAPES = { "Block", "Ball", "Stripe" }
local function paint(player, easel)
	local root = rootOf(player)
	if not root then
		return
	end
	-- the nearest visitors' wall
	local wall, best
	for _, w in ipairs(CollectionService:GetTagged("VisitorWall")) do
		local d = (w.Position - easel.Position).Magnitude
		if d < 80 and (not best or d < best) then
			wall, best = w, d
		end
	end
	if not wall then
		return
	end
	local list = paintings[wall] or {}
	paintings[wall] = list
	if #list >= 5 then
		table.remove(list, 1):Destroy()
	end
	-- slots along the wall, facing into the room
	local into = wall.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local toRoom = if (easel.Position - wall.Position):Dot(into) > 0 then 1 else -1
	local slot = (#list) % 5
	local along = (slot - 2) * (wall.Size.Z / 5.4)
	local cf = wall.CFrame * CFrame.new(toRoom * 0.3, 1, along) * CFrame.Angles(0, toRoom * math.rad(90), 0)
	local m = Instance.new("Model")
	m.Name = "VisitorPainting"
	local function piece(name, size, offset, color, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Parent = m
		return p
	end
	piece("Frame", Vector3.new(5, 4, 0.2), CFrame.new(), rgb(40, 34, 30))
	piece("Canvas", Vector3.new(4.4, 3.4, 0.1), CFrame.new(0, 0, -0.12), Color3.fromHSV(math.random(), 0.15, 0.97))
	for k = 1, math.random(3, 6) do
		local kind = SHAPES[math.random(1, #SHAPES)]
		local c = Color3.fromHSV(math.random(), 0.7, 0.9)
		local x, y = math.random(-15, 15) / 10, math.random(-11, 11) / 10
		if kind == "Block" then
			piece("Paint", Vector3.new(math.random(4, 14) / 10, math.random(4, 14) / 10, 0.05), CFrame.new(x, y, -0.18 - k * 0.005) * CFrame.Angles(0, 0, math.random() * 3), c)
		elseif kind == "Ball" then
			local d = math.random(5, 12) / 10
			piece("Paint", Vector3.new(0.05, d, d), CFrame.new(x, y, -0.18 - k * 0.005) * CFrame.Angles(0, math.rad(90), 0), c, Enum.PartType.Cylinder)
		else
			piece("Paint", Vector3.new(3.8, 0.18, 0.05), CFrame.new(0, y, -0.18 - k * 0.005) * CFrame.Angles(0, 0, math.random() - 0.5), c)
		end
	end
	local plaque = piece("Plaque", Vector3.new(2.6, 0.5, 0.1), CFrame.new(0, -2.5, -0.1), rgb(220, 190, 110))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = plaque
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = rgb(40, 30, 20)
	label.Text = "by " .. player.DisplayName
	label.Parent = gui
	m:SetAttribute("Artist", player.Name)
	m.Parent = wall.Parent
	table.insert(list, m)
	local admirers = 0
	for _, b in ipairs(S.Citizens.Nearby(wall.Position, 45)) do
		if S.Citizens.CanReact(b) and b.Model:GetAttribute("Action") ~= "sleep" and admirers < 3 then
			admirers += 1
			S.Citizens.React(b, "admire", if admirers == 1 then ({ "Ooh, who painted that?", "That's lovely!", "So colourful!", "Is that a new " .. player.DisplayName .. "?" })[math.random(1, 4)] else nil, "happy", 4, (cf * CFrame.new(0, 0, -3)).Position)
		end
	end
	local tips = admirers * 2
	if tips > 0 then
		S.City.AddCoins(player, tips, "🎨 Art lovers")
	end
	S.City.Toast(player, "🎨", "Your painting is up!", "It's hanging on the visitors' wall with your name on it." .. (if tips > 0 then " Admirers tipped " .. tips .. " coins." else ""), rgb(230, 140, 200))
	return m
end
VenueService.Paint = paint

--------------------------------------------------------------------------------
-- 🐠 Feeding the fish, 🧘 yoga
--------------------------------------------------------------------------------
local function feed(player, feeder)
	if not S.City.Spend(player, 2, "🐠 Fish food") then
		S.City.Toast(player, "🪙", "Not enough coins", "Fish food costs 2 coins.", rgb(220, 120, 80))
		return
	end
	feeder.Parent:SetAttribute("FedUntil", workspace:GetServerTimeNow() + 12)
	S.City.Toast(player, "🐠", "Feeding time!", "The fish come racing up to the top.", rgb(80, 180, 240))
	crowd(feeder.Position, 30, { "point", "cheer" }, { "Look at them go!", "Ooh, feeding time!" }, 4)
end

local inClass = {}
local function yoga(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or (inClass[player] and os.clock() < inClass[player]) then
		return
	end
	inClass[player] = os.clock() + 14
	emote(player, "yoga", 12)
	S.City.Toast(player, "🧘", "Breathe in... breathe out", "A few minutes of yoga: you heal and get your energy back.", rgb(140, 200, 140))
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(2)
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 8)
			end
		end
		if player.Parent then
			S.City.Send(player, { Type = "Food", Energy = 60, Name = "yoga", Quiet = true })
			S.City.Toast(player, "🧘", "Namaste", "You feel calm and full of energy.", rgb(140, 200, 140))
		end
	end)
end

--------------------------------------------------------------------------------
function VenueService.Start(services)
	S = services
	setupLanes()
	setupGolf()
	for _, mic in ipairs(CollectionService:GetTagged("KaraokeMic")) do
		prompt(anchorPart("MicPrompt", mic.CFrame, mic.Parent), "Sing karaoke", "🎤 Neon Nightclub", 0.4, function(player)
			sing(player, mic)
		end)
	end
	for _, d in ipairs(CollectionService:GetTagged("BarberChairPrompt")) do
		prompt(d, "Dye your hair (" .. VenueService.DYE_COST .. " coins)", "💈 Fresh Cuts", 0.5, dye)
	end
	for _, e in ipairs(CollectionService:GetTagged("PaintEasel")) do
		prompt(e, "Paint a picture", "🎨 Art Gallery", 1, function(player)
			paint(player, e)
		end)
	end
	for _, f in ipairs(CollectionService:GetTagged("FishFeeder")) do
		prompt(f, "Feed the fish (2 coins)", "🐠 City Aquarium", 0, function(player)
			feed(player, f)
		end)
	end
	for _, y in ipairs(CollectionService:GetTagged("YogaClass")) do
		prompt(y, "Join the yoga class", "🧘 Zen Yoga", 0.5, yoga)
	end
	-- your hair colour comes back when you respawn
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			task.wait(1)
			local pd = S.City.Data(player)
			if pd and type(pd.HairDye) == "table" then
				applyDye(character, Color3.new(pd.HairDye[1], pd.HairDye[2], pd.HairDye[3]))
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		golfers[player] = nil
		singing[player] = nil
		inClass[player] = nil
		dyeIndex[player] = nil
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			tick += 1
			local now = os.clock()
			pcall(stepLanes, now)
			pcall(stepGolf, now)
			if tick % 5 == 0 then
				pcall(stepWash)
			end
		end
	end)
end

return VenueService
