-- SportsService (ModuleScript) — ServerScriptService.Modules.SportsService
-- Pickup basketball: when people are shooting hoops on a court, they split
-- into two teams and play a real match. The ball carrier dribbles up the court
-- (the ball bounces at their side), passes to open teammates, and pulls up for
-- a jump shot; defenders slide over to guard, shots arc to the rim, misses
-- turn into rebounds, and a quick hand can steal it. First to 11 wins, and
-- players nearby see the score. (Soccer lives in CitizenService.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SportsService = {}
local S

local courts = {} -- { A = hoop pos, B = hoop pos, Center, Place, Key }
local games = {} -- [court] = match
local TICK = 0.1

local SHOUT = { "I'm open!", "Ball!", "Pass it!", "Get back on D!", "And one!", "Money!", "Nice pass!", "Box out!" }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function playersNear(pos, radius)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - pos).Magnitude < radius then
			return true
		end
	end
	return false
end

local function findCourts()
	for _, place in ipairs(S.Map.PlaceList or {}) do
		local hoops = {}
		for _, s in ipairs(place.Spots or {}) do
			if s.Hoop then
				local known = false
				for _, h in ipairs(hoops) do
					if (h - s.Hoop).Magnitude < 1 then
						known = true
					end
				end
				if not known then
					table.insert(hoops, s.Hoop)
				end
			end
		end
		-- two hoops facing each other 20-40 studs apart make a court
		local used = {}
		for i = 1, #hoops do
			for j = i + 1, #hoops do
				local d = flat(hoops[i] - hoops[j]).Magnitude
				if not used[i] and not used[j] and d > 18 and d < 42 then
					used[i], used[j] = true, true
					local court = { A = hoops[i], B = hoops[j], Place = place, Spots = {} }
					court.Center = (hoops[i] + hoops[j]) / 2
					court.Ground = court.Center.Y - 9
					for _, s in ipairs(place.Spots) do
						if s.Hoop and ((s.Hoop - hoops[i]).Magnitude < 1 or (s.Hoop - hoops[j]).Magnitude < 1) then
							court.Spots[s] = true
						end
					end
					table.insert(courts, court)
				end
			end
		end
	end
end

local function newBall(court)
	local ball = Instance.new("Part")
	ball.Name = "GameBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 1.2
	ball.Color = Color3.fromRGB(230, 110, 40)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
	ball.CFrame = CFrame.new(court.Center)
	ball.Parent = workspace
	return ball
end

local function setAction(brain, action)
	if brain.Model:GetAttribute("Action") ~= action then
		brain.Model:SetAttribute("Action", action)
	end
end

-- hand the ball to someone (a make: the other team takes it out)
local function giveTo(match, brain)
	match.Carrier = brain
	match.Flight = nil
	match.NextMove = os.clock() + math.random(8, 14) / 10
end

local function endGame(match, why)
	games[match.Court] = nil
	if match.Ball then
		match.Ball:Destroy()
	end
	for brain in pairs(match.Players) do
		if brain.Model.Parent then
			brain.Model:SetAttribute("Team", nil)
			brain.Model:SetAttribute("Action", "")
			if brain.State == "police" then
				S.Citizens.Control(brain, false)
			end
		end
	end
	if why and match.Score[1] + match.Score[2] > 0 then
		local winner = if match.Score[1] > match.Score[2] then 1 else 2
		S.City.SendNear(match.Court.Center, 160, { Type = "Toast", Icon = "🏀", Title = "Game over", Text = string.format("%s team wins %d – %d!", if winner == 1 then "Blue" else "Red", match.Score[winner], match.Score[3 - winner]), Color = if winner == 1 then Color3.fromRGB(70, 130, 240) else Color3.fromRGB(230, 70, 70) })
	end
end

local function startGame(court, brains)
	local match = { Court = court, Players = {}, Score = { 0, 0 }, Started = os.clock(), Ball = newBall(court) }
	for k, brain in ipairs(brains) do
		local team = (k - 1) % 2 + 1
		match.Players[brain] = team
		S.Citizens.Control(brain, true)
		brain.Model:SetAttribute("Team", team)
		brain.Model:SetAttribute("Activity", "🏀 Pickup match (" .. (if team == 1 then "Blue" else "Red") .. " team)")
	end
	giveTo(match, brains[1])
	games[court] = match
	S.Citizens.Say(brains[1], "Let's run a match! First to 11!", "grin", 2.5)
	return match
end

local function attackHoop(match, team)
	return if team == 1 then match.Court.B else match.Court.A
end

local function arc(from, to, k, height)
	return from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * height, 0)
end

local function tick(match, now)
	local court = match.Court
	-- anyone gone (knocked out, taken away, a fight...)? end it
	local list = {}
	for brain in pairs(match.Players) do
		if not brain.Model.Parent or brain.State ~= "police" or brain.Model:GetAttribute("Fighting") then
			endGame(match, false)
			return
		end
		table.insert(list, brain)
	end
	if now - match.Started > 240 or not playersNear(court.Center, 350) then
		endGame(match, true)
		return
	end
	local ball = match.Ball
	local ground = court.Ground
	-- the ball in the air (a pass or a shot)
	local flight = match.Flight
	if flight then
		local k = math.min(1, (now - flight.Start) / flight.Time)
		ball.CFrame = CFrame.new(arc(flight.From, flight.To, k, flight.Height))
		if k >= 1 then
			if flight.Shot then
				if flight.Make then
					local team = match.Players[flight.By] or 1
					match.Score[team] += if flight.Three then 3 else 2
					S.Citizens.React(flight.By, "cheer", if math.random() < 0.5 then "Buckets!" else nil, "grin", 1.5)
					S.City.SendNear(court.Center, 140, { Type = "Toast", Icon = "🏀", Title = (if flight.Three then "THREE! " else "") .. flight.By.C.First .. " scores!", Text = string.format("Blue %d – %d Red", match.Score[1], match.Score[2]), Color = if team == 1 then Color3.fromRGB(70, 130, 240) else Color3.fromRGB(230, 70, 70) })
					if match.Score[team] >= 11 then
						endGame(match, true)
						return
					end
					-- the other team takes it out
					for _, b in ipairs(list) do
						if match.Players[b] ~= team then
							giveTo(match, b)
							break
						end
					end
				else
					-- a miss: it bounces off the rim, the nearest player grabs the rebound
					local off = flight.To + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
					off = Vector3.new(off.X, ground + 1, off.Z)
					match.Flight = { From = flight.To, To = off, Start = now, Time = 0.5, Height = 2 }
					match.Rebound = true
					return
				end
			else
				local wasRebound = match.Rebound
				match.Rebound = nil
				local best, bestD = nil, math.huge
				for _, b in ipairs(list) do
					local d = flat(b.Root.Position - ball.Position).Magnitude
					if d < bestD then
						best, bestD = b, d
					end
				end
				giveTo(match, flight.Target or best)
				if wasRebound and best then
					if math.random() < 0.3 then
						S.Citizens.Say(best, "Rebound!", "grin", 1.2)
					end
				end
			end
		end
	end
	local carrier = match.Carrier
	-- everyone's movement
	for _, b in ipairs(list) do
		local team = match.Players[b]
		local hoop = attackHoop(match, team)
		local hoopFlat = Vector3.new(hoop.X, ground, hoop.Z)
		local target
		if match.Flight and not match.Flight.Shot and not match.Flight.Target then
			-- a loose ball: go get it
			target = match.Flight.To
			setAction(b, "defend")
		elseif b == carrier then
			local toHoop = hoopFlat - flat(b.Root.Position) - Vector3.new(0, ground, 0)
			b.ShotRange = b.ShotRange or math.random(8, 18)
			if toHoop.Magnitude > b.ShotRange then
				target = b.Root.Position + toHoop.Unit * 4
			else
				target = b.Root.Position
			end
			setAction(b, "dribble")
		elseif carrier and match.Players[carrier] == team then
			-- get open near the hoop
			local side = if (b.C.Id % 2) == 0 then 1 else -1
			local across = (court.B - court.A).Unit:Cross(Vector3.new(0, 1, 0))
			target = hoopFlat + (flat(court.Center) - hoopFlat).Unit * 10 + across * side * 9
			setAction(b, "")
		else
			-- defense: between the nearest opponent and our hoop
			local ourHoop = attackHoop(match, 3 - team)
			local mark, md = carrier, math.huge
			for _, o in ipairs(list) do
				if match.Players[o] ~= team then
					local d = (o.Root.Position - b.Root.Position).Magnitude
					if d < md then
						mark, md = o, d
					end
				end
			end
			if mark then
				local toOur = flat(ourHoop - mark.Root.Position)
				target = mark.Root.Position + (if toOur.Magnitude > 0.1 then toOur.Unit * 3 else Vector3.zero)
			end
			setAction(b, "defend")
		end
		if target then
			S.Citizens.SetGait(b, if b == carrier then 12 else 14, "run")
			b.Humanoid:MoveTo(Vector3.new(target.X, b.Root.Position.Y, target.Z))
		end
	end
	if match.Flight or not carrier then
		return
	end
	-- the ball bounces at the carrier's side
	local root = carrier.Root
	local bounce = math.abs(math.sin(now * 7))
	ball.CFrame = CFrame.new(root.Position + root.CFrame.RightVector * 1.2 + root.CFrame.LookVector * 0.6 + Vector3.new(0, -2.4 + bounce * 2.2, 0))
	-- a steal?
	for _, o in ipairs(list) do
		if match.Players[o] ~= match.Players[carrier] and (o.Root.Position - root.Position).Magnitude < 3 and math.random() < 0.012 then
			giveTo(match, o)
			S.Citizens.Say(o, "Steal!", "grin", 1.2)
			return
		end
	end
	if now < (match.NextMove or 0) then
		return
	end
	match.NextMove = now + math.random(6, 12) / 10
	local team = match.Players[carrier]
	local hoop = attackHoop(match, team)
	local dist = flat(hoop - root.Position).Magnitude
	local hand = root.Position + Vector3.new(0, 2.2, 0)
	if dist <= (carrier.ShotRange or 12) + 1 then
		-- pull up for the shot
		local guarded = false
		for _, o in ipairs(list) do
			if match.Players[o] ~= team and (o.Root.Position - root.Position).Magnitude < 4 then
				guarded = true
			end
		end
		local three = dist > 15
		local chance = (if three then 0.3 else 0.48) - (if guarded then 0.15 else 0) + (if carrier.C.Personality == "sporty" then 0.12 else 0)
		setAction(carrier, "jumpshot")
		carrier.Model:SetAttribute("Swing", now)
		match.Flight = { From = hand, To = hoop + Vector3.new(0, 0.4, 0), Start = now, Time = 0.9 + dist / 60, Height = 5 + dist * 0.2, Shot = true, Make = math.random() < chance, By = carrier, Three = three }
		match.Carrier = nil
		carrier.ShotRange = nil
		if math.random() < 0.2 then
			S.Citizens.Say(carrier, "Cash!", "grin", 1.2)
		end
	else
		-- pass to an open teammate?
		local mates = {}
		for _, b in ipairs(list) do
			if b ~= carrier and match.Players[b] == team then
				table.insert(mates, b)
			end
		end
		if #mates > 0 and math.random() < 0.35 then
			local to = mates[math.random(1, #mates)]
			match.Flight = { From = hand, To = to.Root.Position + Vector3.new(0, 1.5, 0), Start = now, Time = 0.45, Height = 1.2, Target = to }
			match.Carrier = nil
			carrier.Model:SetAttribute("Swing", now)
			if math.random() < 0.25 then
				S.Citizens.Say(to, SHOUT[math.random(1, #SHOUT)], "grin", 1.2)
			end
		end
	end
end

-- people shooting hoops on a court start a match
local function lookForGames()
	for _, court in ipairs(courts) do
		if not games[court] then
			local here = {}
			for _, brain in ipairs(S.Citizens.List) do
				if brain.State == "act" and brain.Spot and court.Spots[brain.Spot] and brain.Model.Parent then
					table.insert(here, brain)
				end
			end
			if #here >= 2 and playersNear(court.Center, 250) then
				-- even teams (up to 3 on 3)
				local n = math.min(6, #here - (#here % 2))
				local chosen = {}
				for k = 1, n do
					chosen[k] = here[k]
				end
				startGame(court, chosen)
			end
		end
	end
end

function SportsService.Start(services)
	S = services
	findCourts()
	task.spawn(function()
		local lastLook = 0
		while true do
			task.wait(TICK)
			local now = os.clock()
			for _, match in pairs(games) do
				local ok, err = pcall(tick, match, now)
				if not ok then
					warn("[SportsService] " .. tostring(err))
					endGame(match, false)
				end
			end
			if Config and Config.PICKUP_GAMES == false then
				continue
			end
			if now - lastLook > 3 and S.Citizens and S.Citizens.List then
				lastLook = now
				pcall(lookForGames)
			end
		end
	end)
end

SportsService.Courts = courts
SportsService.Games = games

return SportsService
