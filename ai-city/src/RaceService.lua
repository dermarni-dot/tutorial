-- RaceService (ModuleScript) — ServerScriptService.Modules.RaceService
-- 🏁 Street races against the clock, in your own car.
--
-- The start line is a checkered pad on Shore Drive, just north of town (with
-- a gantry and a board of the fastest times). Drive onto it in your car and
-- pick a race by which pad you stop on:
--   🏙️ City Loop      a lap of the whole city: down 5th Avenue, around the
--                     west side, along the south, up the east side and back
--   🌊 Shore Sprint   a quick dash up Shore Drive to the boardwalk and back
-- 3... 2... 1... GO! Glowing rings show the next checkpoint (only you see
-- yours); drive through them in order. Cross the finish for coins, a bonus
-- for a personal best, and a place on the board. Get out of your car or take
-- too long and the race is off. People on the sidewalk cheer you on.

local Players = game:GetService("Players")

local RaceService = {}
local S, NS
local NorthShore = require(script.Parent:WaitForChild("NorthShore"))
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local racing = {} -- [player] = { Route, Index, Start, ... }
local boards = {} -- [route id] = { { Name, Time } }
RaceService.Racing = racing
RaceService.Boards = boards

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- the routes: corner points on the roads; checkpoints sit in the right-hand
-- lane, going the way the route goes
local function buildRoutes()
	local sp = S.Map.Spacing or 134
	local lane = S.Map.Lane or 3.4
	local function L(k)
		return (k + 0.5) * sp
	end
	local x0 = NorthShore.DRIVE_X
	local z0 = -(S.Map.Extent or 737)
	local function lanePoints(corners, every)
		local pts = {}
		for k = 1, #corners - 1 do
			local a, b = corners[k], corners[k + 1]
			local dir = (b - a).Unit
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local len = (b - a).Magnitude
			local n = math.max(1, math.floor(len / every))
			for i = 1, n do
				local p = a + dir * (len * i / n) + right * lane
				table.insert(pts, Vector3.new(p.X, 2, p.Z))
			end
		end
		return pts
	end
	-- down Shore Drive into town, west, the long way south, east, north up
	-- the east side, back west along the top and out to the start
	local loop = {
		Vector3.new(x0, 0, z0 - 40), Vector3.new(x0, 0, L(-3)), Vector3.new(L(-4), 0, L(-3)), Vector3.new(L(-4), 0, L(2)),
		Vector3.new(L(3), 0, L(2)), Vector3.new(L(3), 0, L(-4)), Vector3.new(x0, 0, L(-4)), Vector3.new(x0, 0, z0 - 40),
	}
	local sprintEnd = NorthShore.BOARDWALK_Z + 22
	return {
		{ Id = "loop", Name = "City Loop", Emoji = "🏙️", Points = lanePoints(loop, 150), Par = 120, Reward = 80 },
		{ Id = "sprint", Name = "Shore Sprint", Emoji = "🌊", Points = { Vector3.new(x0 + lane, 2, (z0 + sprintEnd) / 2), Vector3.new(x0 + lane, 2, sprintEnd), Vector3.new(x0 - lane, 2, (z0 + sprintEnd) / 2), Vector3.new(x0 - lane, 2, z0 - 40) }, Par = 25, Reward = 40 },
	}
end

local function carOf(player)
	local car = S.Cars and S.Cars.Spawned and S.Cars.Spawned[player]
	if car and car.Parent and car.PrimaryPart then
		return car
	end
	return nil
end

local function driving(player)
	local car = carOf(player)
	local seat = car and car:FindFirstChild("DriverSeat")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return car ~= nil and seat ~= nil and hum ~= nil and seat.Occupant == hum, car
end

local function drawBoard(route)
	local part = RaceService.BoardParts and RaceService.BoardParts[route.Id]
	if not part then
		return
	end
	local gui = part:FindFirstChild("RaceBoardGui")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "RaceBoardGui"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 25
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = part
	end
	local lines = { route.Emoji .. " " .. string.upper(route.Name) }
	local b = boards[route.Id] or {}
	for k = 1, 5 do
		table.insert(lines, if b[k] then string.format("%d. %s  %.1fs", k, b[k].Name, b[k].Time) else k .. ". ---")
	end
	gui.Text.Text = table.concat(lines, "\n")
end

local function send(player, r)
	S.City.Send(player, { Type = "Race", Route = r.Route.Id, Name = r.Route.Name, Points = r.Route.Points, Index = r.Index, Start = r.Start, Going = r.Going })
end

local function stop(player, why)
	local r = racing[player]
	racing[player] = nil
	if r then
		S.City.Send(player, { Type = "Race", Done = true })
		if why then
			S.City.Toast(player, "🏁", "Race off", why, rgb(220, 120, 80))
		end
	end
end
RaceService.Stop = stop

function RaceService.Begin(player, routeId)
	local route
	for _, rt in ipairs(RaceService.Routes) do
		if rt.Id == routeId then
			route = rt
		end
	end
	if not route or racing[player] then
		return false
	end
	local r = { Route = route, Index = 1, Start = workspace:GetServerTimeNow() + 3, Going = false }
	racing[player] = r
	send(player, r)
	S.City.Toast(player, route.Emoji, route.Name .. ": get ready!", "3... 2... 1... Drive through the glowing rings in order. Par: " .. route.Par .. "s.", rgb(250, 200, 60))
	-- people nearby cheer
	if S.Social and S.Social.Audience then
		local root = rootOf(player)
		for k, b in ipairs(root and S.Social.Audience(root.Position, 45, 4) or {}) do
			S.Citizens.React(b, "cheer", if k == 1 then "GO GO GO!" else nil, "happy", 4, root.Position)
		end
	end
	return true
end

local function finish(player, r)
	local t = workspace:GetServerTimeNow() - r.Start
	racing[player] = nil
	local pd = S.City.Data(player)
	pd.RaceBest = pd.RaceBest or {}
	local best = pd.RaceBest[r.Route.Id]
	local record = not best or t < best
	if record then
		pd.RaceBest[r.Route.Id] = t
	end
	local coins = r.Route.Reward + (if record then 50 else 0) + (if t < r.Route.Par then 30 else 0)
	S.City.AddCoins(player, coins, "🏁 " .. r.Route.Name)
	local b = boards[r.Route.Id] or {}
	boards[r.Route.Id] = b
	table.insert(b, { Name = player.DisplayName, Time = t })
	table.sort(b, function(x, y)
		return x.Time < y.Time
	end)
	while #b > 5 do
		table.remove(b)
	end
	drawBoard(r.Route)
	S.City.Send(player, { Type = "Race", Done = true, Time = t })
	S.City.Toast(player, "🏁", string.format("%s: %.1fs!", r.Route.Name, t), "+" .. coins .. " coins" .. (if record then " · a new personal best!" else string.format(" · your best: %.1fs", best)) .. (if t < r.Route.Par then " · under par!" else ""), rgb(90, 200, 120))
	S.City.News(string.format("🏁 %s ran the %s in %.1f seconds!", player.DisplayName, r.Route.Name, t), "City", true)
	return t
end
RaceService.Finish = finish

-- every tick: the countdown, checkpoints, giving up
local function step(player, r)
	local isDriving, car = driving(player)
	local now = workspace:GetServerTimeNow()
	if not isDriving then
		r.Away = r.Away or now
		if now - r.Away > 8 then
			stop(player, "You got out of your car.")
		end
		return
	end
	r.Away = nil
	if not r.Going then
		if now >= r.Start then
			r.Going = true
			send(player, r)
		end
		return
	end
	if now - r.Start > r.Route.Par * 4 then
		stop(player, "Out of time.")
		return
	end
	local target = r.Route.Points[r.Index]
	local pos = car.PrimaryPart.Position
	if Vector3.new(pos.X - target.X, 0, pos.Z - target.Z).Magnitude < 18 then
		r.Index += 1
		if r.Index > #r.Route.Points then
			finish(player, r)
		else
			send(player, r)
		end
	end
end
RaceService.Step = step

function RaceService.Start(services)
	S = services
	NS = S.Map and S.Map.NorthShore
	RaceService.Routes = buildRoutes()
	-- the start line: two pads under a checkered gantry on Shore Drive
	local x0 = NorthShore.DRIVE_X
	local z0 = -(S.Map.Extent or 737) - 40
	local folder = Instance.new("Folder")
	folder.Name = "RaceStart"
	folder.Parent = workspace:FindFirstChild("City") or workspace
	RaceService.Pads = {}
	RaceService.BoardParts = {}
	for k, route in ipairs(RaceService.Routes) do
		local px = x0 + (if k == 1 then -6.5 else 6.5)
		local pad = MapKit.part(folder, "RacePad", Vector3.new(11, 0.2, 8), CFrame.new(px, 0.15, z0 + 14), rgb(30, 30, 34), Enum.Material.SmoothPlastic)
		pad.CanCollide = false
		for i = 0, 5 do
			for j = 0, 3 do
				if (i + j) % 2 == 0 then
					MapKit.deco(folder, "Checker", Vector3.new(1.8, 0.21, 2), CFrame.new(px - 4.6 + i * 1.84, 0.16, z0 + 11 + j * 2), rgb(245, 245, 245))
				end
			end
		end
		local label = MapKit.deco(folder, "PadLabel", Vector3.new(10, 0.05, 2.4), CFrame.new(px, 0.27, z0 + 19.5), rgb(30, 30, 34))
		MapKit.signText(label, Enum.NormalId.Top, route.Emoji .. " " .. route.Name, rgb(255, 220, 90), Enum.Font.GothamBlack)
		pad:SetAttribute("Route", route.Id)
		RaceService.Pads[route.Id] = pad
		-- the board of fastest times beside the gantry
		local board = MapKit.deco(folder, "RaceBoard", Vector3.new(12, 8, 0.4), CFrame.new(px + (if k == 1 then -18 else 18), 6, z0 + 6), rgb(20, 22, 32))
		MapKit.deco(folder, "RaceBoardPost", Vector3.new(0.5, 6, 0.5), CFrame.new(px + (if k == 1 then -18 else 18), 3, z0 + 6.3), rgb(60, 60, 66), Enum.Material.Metal)
		RaceService.BoardParts[route.Id] = board
		drawBoard(route)
	end
	for _, sx in ipairs({ -1, 1 }) do
		MapKit.deco(folder, "GantryPost", Vector3.new(1, 14, 1), CFrame.new(x0 + sx * 14, 7, z0 + 14), rgb(230, 230, 236), Enum.Material.Metal)
	end
	local banner = MapKit.deco(folder, "GantryBanner", Vector3.new(29, 3, 0.6), CFrame.new(x0, 13, z0 + 14), rgb(20, 20, 24))
	MapKit.signText(banner, Enum.NormalId.Front, "🏁 STREET RACES · drive onto a pad 🏁", MapKit.WHITE, Enum.Font.GothamBlack)
	MapKit.signText(banner, Enum.NormalId.Back, "🏁 START / FINISH 🏁", Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, player in ipairs(Players:GetPlayers()) do
				local r = racing[player]
				if r then
					local ok, err = pcall(step, player, r)
					if not ok then
						warn("[RaceService] " .. tostring(err))
					end
				else
					-- parked on a start pad in your car: off we go
					local isDriving, car = driving(player)
					if isDriving then
						local pos = car.PrimaryPart.Position
						for id, pad in pairs(RaceService.Pads) do
							local rel = pad.CFrame:PointToObjectSpace(pos)
							local v = car.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
							if math.abs(rel.X) < 6.5 and math.abs(rel.Z) < 6 and v.Magnitude < 4 and os.clock() > (player:GetAttribute("RaceCool") or 0) then
								player:SetAttribute("RaceCool", os.clock() + 8)
								RaceService.Begin(player, id)
							end
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		racing[player] = nil
	end)
end

return RaceService
