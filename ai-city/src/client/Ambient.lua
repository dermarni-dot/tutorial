-- Ambient (ModuleScript) — StarterPlayerScripts.CityClient.Ambient
-- Little moving things that make the city feel alive, all drawn on your own
-- screen (they cost the server nothing):
--
--   🐦 Pigeons on the plaza strut and peck, and burst into the air when
--      someone walks up, circling before they land again.
--   🕊️ Seagulls wheel over Sunset Beach, flapping and gliding.
--   ⛵ Sailboats drift along the horizon, rocking on the swell.
--   🎈 The inflatable tube man at AutoLand flails in the wind.
--   🌀 Fans on the rooftops turn. 🌊 The surf rolls in and out; 🦀 crabs
--      scuttle sideways along the water's edge.
--   🚩 Flags ripple on their poles; buoys and anything tagged "Bob" bob on the
--      water.
--   🌧️ When it rains (see RainService), rain streaks fall all around you and
--      splash on the ground.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ambient = {}
local folder
local rng = Random.new()
local pigeons = {} -- [server pigeon part] = { Parts, Pos, Home, State, ... }
local gulls, boats, tubes, flags, bobbers = {}, {}, {}, {}, {}
local spinners = {} -- rooftop fan blades and the surf: their resting CFrame
local crabs = {} -- [crab model] = { Base, Parts = { [part] = offset } }
Ambient.Pigeons = pigeons
Ambient.Gulls = gulls
Ambient.Boats = boats

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent, list, name, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	table.insert(list, { Part = p, Offset = offset, Name = name })
	return p
end

local function place(list, cf, flap)
	for _, e in ipairs(list) do
		local off = e.Offset
		if e.Name == "WingL" then
			off = off * CFrame.Angles(0, 0, flap)
		elseif e.Name == "WingR" then
			off = off * CFrame.Angles(0, 0, -flap)
		end
		e.Part.CFrame = cf * off
	end
end

-- a bird: a body, a head, a beak, a tail and two wings (they flap)
local function bird(color, size, wingColor)
	local m = Instance.new("Model")
	m.Name = "Bird"
	local list = {}
	part(m, list, "Body", Vector3.new(0.5, 0.45, 0.9) * size, CFrame.new(0, 0.35 * size, 0), color, Enum.PartType.Ball)
	part(m, list, "Head", Vector3.one * 0.34 * size, CFrame.new(0, 0.62 * size, -0.4 * size), color, Enum.PartType.Ball)
	part(m, list, "Beak", Vector3.new(0.08, 0.08, 0.2) * size, CFrame.new(0, 0.6 * size, -0.62 * size), rgb(230, 170, 60))
	part(m, list, "Tail", Vector3.new(0.3, 0.06, 0.35) * size, CFrame.new(0, 0.38 * size, 0.5 * size), wingColor)
	part(m, list, "WingL", Vector3.new(0.7, 0.05, 0.4) * size, CFrame.new(-0.25 * size, 0.45 * size, 0) * CFrame.new(-0.35 * size, 0, 0), wingColor)
	part(m, list, "WingR", Vector3.new(0.7, 0.05, 0.4) * size, CFrame.new(0.25 * size, 0.45 * size, 0) * CFrame.new(0.35 * size, 0, 0), wingColor)
	-- the wings hinge at the shoulder: move the offset so the flap turns around it
	for _, e in ipairs(list) do
		if e.Name == "WingL" then
			e.Offset = CFrame.new(-0.25 * size, 0.45 * size, 0)
			e.Hinge = CFrame.new(-0.35 * size, 0, 0)
		elseif e.Name == "WingR" then
			e.Offset = CFrame.new(0.25 * size, 0.45 * size, 0)
			e.Hinge = CFrame.new(0.35 * size, 0, 0)
		end
	end
	m.Parent = folder
	return m, list
end

local function placeBird(list, cf, flap)
	for _, e in ipairs(list) do
		if e.Hinge then
			local sign = if e.Name == "WingL" then 1 else -1
			e.Part.CFrame = cf * e.Offset * CFrame.Angles(0, 0, sign * flap) * e.Hinge
		else
			e.Part.CFrame = cf * e.Offset
		end
	end
end

--------------------------------------------------------------------------------
-- 🐦 Pigeons
--------------------------------------------------------------------------------
local function people()
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(out, r.Position)
		end
	end
	return out
end

local function stepPigeons(dt, t, camPos, near)
	for _, src in ipairs(CollectionService:GetTagged("Pigeon")) do
		local d = (src.Position - camPos).Magnitude
		local p = pigeons[src]
		if d < 220 then
			if not p then
				src.Transparency = 1 -- (this screen draws a real bird instead)
				local m, list = bird(if rng:NextNumber() < 0.3 then rgb(170, 170, 176) else rgb(120, 124, 136), 1, rgb(90, 94, 104))
				p = { Model = m, Parts = list, Home = src.Position - Vector3.new(0, 0.35, 0), State = "walk", Yaw = rng:NextNumber(0, 6.28), Phase = rng:NextNumber(0, 6) }
				p.Pos = p.Home
				pigeons[src] = p
			end
			-- anyone close? up they go
			if p.State ~= "fly" then
				for _, q in ipairs(near) do
					if (q - p.Pos).Magnitude < 7 then
						p.State = "fly"
						p.T0 = t
						p.Away = Vector3.new(p.Pos.X - q.X, 0, p.Pos.Z - q.Z)
						p.Away = if p.Away.Magnitude > 0.1 then p.Away.Unit else Vector3.new(1, 0, 0)
						break
					end
				end
			end
			local flap = 0
			if p.State == "fly" then
				-- up and away in a big loop, then back down home
				local u = (t - p.T0) / 9
				if u >= 1 then
					p.State = "walk"
					p.Pos = p.Home
				else
					local a = u * math.pi * 2
					local out = p.Away * math.sin(a * 0.5) * 22
					local side = Vector3.new(-p.Away.Z, 0, p.Away.X) * math.sin(a) * 8
					local h = math.sin(u * math.pi) * 14
					local newPos = p.Home + out + side + Vector3.new(0, h, 0)
					local dir = newPos - p.Pos
					p.Pos = newPos
					if dir.Magnitude > 0.01 then
						p.Yaw = math.atan2(-dir.X, -dir.Z)
					end
					flap = math.sin(t * 28) * 0.9
				end
			else
				-- strut about and peck
				p.Next = p.Next or 0
				if t > p.Next then
					p.Next = t + rng:NextNumber(0.8, 2.5)
					p.Yaw += rng:NextNumber(-1.4, 1.4)
					p.Walking = rng:NextNumber() < 0.6
				end
				if p.Walking then
					local step = Vector3.new(-math.sin(p.Yaw), 0, -math.cos(p.Yaw)) * dt * 1.2
					local nextPos = p.Pos + step
					if (nextPos - p.Home).Magnitude > 4 then
						p.Yaw += math.pi * 0.6
					else
						p.Pos = nextPos
					end
				end
			end
			local bob = if p.State == "walk" and p.Walking then math.abs(math.sin(t * 9 + p.Phase)) * 0.06 else 0
			local peck = if p.State == "walk" and not p.Walking and math.sin(t * 3 + p.Phase) > 0.6 then math.rad(40) else 0
			local cf = CFrame.new(p.Pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, p.Yaw, 0) * CFrame.Angles(-peck, 0, 0)
			placeBird(p.Parts, cf, flap)
		elseif p then
			p.Model:Destroy()
			pigeons[src] = nil
			src.Transparency = 0
		end
	end
end

--------------------------------------------------------------------------------
-- 🕊️ Seagulls and ⛵ sailboats at the beach
--------------------------------------------------------------------------------
local function beachSpot()
	local info = game:GetService("ReplicatedStorage"):FindFirstChild("CityInfo")
	local z = info and info:GetAttribute("WaterZ")
	if not z then
		return nil
	end
	return Vector3.new(info:GetAttribute("BeachX") or -65, 0, z)
end

local function boat(i)
	local m = Instance.new("Model")
	m.Name = "Sailboat"
	local list = {}
	local color = ({ rgb(250, 250, 250), rgb(200, 60, 60), rgb(40, 90, 170) })[i % 3 + 1]
	part(m, list, "Hull", Vector3.new(4, 1.6, 12), CFrame.new(0, 0.3, 0), color)
	part(m, list, "Deck", Vector3.new(3.4, 0.2, 10), CFrame.new(0, 1.15, 0), rgb(170, 130, 90), nil, Enum.Material.WoodPlanks)
	part(m, list, "Mast", Vector3.new(0.35, 14, 0.35), CFrame.new(0, 8, -0.5), rgb(230, 230, 230), nil, Enum.Material.Metal)
	part(m, list, "Sail", Vector3.new(0.1, 11, 6), CFrame.new(0.15, 8.2, 2.4), rgb(250, 248, 240), nil, Enum.Material.Fabric)
	part(m, list, "Jib", Vector3.new(0.1, 8, 3.4), CFrame.new(0.15, 6.4, -3.4), ({ rgb(255, 120, 80), rgb(80, 170, 250), rgb(250, 210, 60) })[i % 3 + 1], nil, Enum.Material.Fabric)
	m.Parent = folder
	return list
end

local function stepBeach(dt, t, camPos)
	local spot = beachSpot()
	if not spot then
		return
	end
	local near = (Vector3.new(camPos.X, 0, camPos.Z) - spot).Magnitude < 700
	if near and #gulls == 0 then
		for k = 1, 9 do
			local m, list = bird(rgb(245, 245, 245), 1.8, rgb(170, 176, 186))
			table.insert(gulls, { Model = m, Parts = list, R = rng:NextNumber(25, 70), H = rng:NextNumber(18, 34), Speed = rng:NextNumber(0.15, 0.3) * (if k % 2 == 0 then 1 else -1), Phase = rng:NextNumber(0, 6.28), Center = spot + Vector3.new(rng:NextNumber(-250, 250), 0, rng:NextNumber(-60, 60)) })
		end
		for k = 1, 4 do
			table.insert(boats, { Parts = boat(k), X = rng:NextNumber(-500, 400), Z = spot.Z - rng:NextNumber(120, 380), Speed = rng:NextNumber(2, 5) * (if k % 2 == 0 then 1 else -1), Phase = rng:NextNumber(0, 6) })
		end
	elseif not near and #gulls > 0 then
		for _, g in ipairs(gulls) do
			g.Model:Destroy()
		end
		for _, b in ipairs(boats) do
			b.Parts[1].Part.Parent:Destroy()
		end
		table.clear(gulls)
		table.clear(boats)
	end
	for _, g in ipairs(gulls) do
		local a = t * g.Speed + g.Phase
		local pos = g.Center + Vector3.new(math.cos(a) * g.R, g.H + math.sin(t * 0.7 + g.Phase) * 2, math.sin(a) * g.R)
		local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * (if g.Speed > 0 then 1 else -1)
		-- flap now and then, glide in between, banked into the turn
		local flapping = math.sin(t * 0.8 + g.Phase) > 0.3
		local flap = if flapping then math.sin(t * 14 + g.Phase) * 0.7 else 0.12
		local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, (if g.Speed > 0 then -1 else 1) * 0.35)
		placeBird(g.Parts, cf, flap)
	end
	for _, b in ipairs(boats) do
		b.X += b.Speed * dt
		if b.X > 700 then
			b.X = -700
		elseif b.X < -700 then
			b.X = 700
		end
		local pos = Vector3.new(b.X, -1 + math.sin(t * 1.1 + b.Phase) * 0.35, b.Z)
		local cf = CFrame.new(pos) * CFrame.Angles(0, if b.Speed > 0 then -math.pi / 2 else math.pi / 2, 0) * CFrame.Angles(math.sin(t * 0.9 + b.Phase) * 0.05, 0, math.sin(t * 1.3 + b.Phase) * 0.08)
		place(b.Parts, cf, 0)
	end
end

--------------------------------------------------------------------------------
-- 🎈 The tube man, 🚩 flags and bobbing things
--------------------------------------------------------------------------------
local function stepTubes(t, camPos)
	for _, base in ipairs(CollectionService:GetTagged("TubeMan")) do
		local near = (base.Position - camPos).Magnitude < 300
		local tube = tubes[base]
		if near and not tube then
			local m = Instance.new("Model")
			m.Name = "TubeMan"
			local list = {}
			local color = base.Color
			for k = 1, 7 do
				part(m, list, "Tube", Vector3.new(1.6 - k * 0.05, 2.2, 1.6 - k * 0.05), CFrame.new(), color, Enum.PartType.Cylinder)
			end
			part(m, list, "Face", Vector3.new(1.3, 1.3, 1.3), CFrame.new(), rgb(255, 230, 90), Enum.PartType.Ball)
			part(m, list, "ArmL", Vector3.new(4, 0.6, 0.6), CFrame.new(), color:Lerp(rgb(255, 255, 255), 0.3))
			part(m, list, "ArmR", Vector3.new(4, 0.6, 0.6), CFrame.new(), color:Lerp(rgb(255, 255, 255), 0.3))
			m.Parent = folder
			tube = { Model = m, Parts = list }
			tubes[base] = tube
		elseif not near and tube then
			tube.Model:Destroy()
			tubes[base] = nil
			tube = nil
		end
		if tube then
			-- each segment leans a bit more than the one below: the whole thing waves
			local cf = CFrame.new(base.Position + Vector3.new(0, base.Size.Y / 2, 0))
			local k = 0
			for _, e in ipairs(tube.Parts) do
				if e.Name == "Tube" then
					k += 1
					local lean = math.sin(t * 3.1 - k * 0.7) * 0.18 + math.sin(t * 5.3 - k * 1.1) * 0.08
					local twist = math.sin(t * 2.3 - k * 0.5) * 0.1
					cf = cf * CFrame.Angles(twist, 0, lean) * CFrame.new(0, 1.05, 0)
					e.Part.CFrame = cf * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
					cf = cf * CFrame.new(0, 1.05, 0)
					if k == 5 then
						tube.Shoulders = cf
					end
				elseif e.Name == "Face" then
					e.Part.CFrame = cf * CFrame.new(0, 0.6, 0)
				elseif e.Name == "ArmL" or e.Name == "ArmR" then
					local side = if e.Name == "ArmL" then -1 else 1
					local flail = math.sin(t * 6 + side) * 0.9 + side * 0.3
					e.Part.CFrame = (tube.Shoulders or cf) * CFrame.Angles(0, 0, flail * side) * CFrame.new(side * 2, 0, 0)
				end
			end
		end
	end
end

local function stepFlags(t, camPos)
	for _, f in ipairs(CollectionService:GetTagged("WavingFlag")) do
		if (f.Position - camPos).Magnitude < 260 then
			flags[f] = flags[f] or f.CFrame
			local base = flags[f]
			-- a ripple: the flag swings from its pole edge
			local swing = math.sin(t * 2.4 + base.Position.X * 0.1) * 0.25 + math.sin(t * 4.1) * 0.08
			local hinge = base * CFrame.new(0, 0, -f.Size.Z / 2)
			f.CFrame = hinge * CFrame.Angles(0, swing, 0) * CFrame.new(0, 0, f.Size.Z / 2)
		end
	end
	for _, b in ipairs(CollectionService:GetTagged("Bob")) do
		if (b.Position - camPos).Magnitude < 400 then
			bobbers[b] = bobbers[b] or b.CFrame
			local base = bobbers[b]
			local ph = base.Position.X * 0.37 + base.Position.Z * 0.11
			b.CFrame = base * CFrame.new(0, math.sin(t * 1.6 + ph) * 0.25, 0) * CFrame.Angles(math.sin(t * 1.2 + ph) * 0.08, 0, math.cos(t * 1.4 + ph) * 0.08)
		end
	end
	-- 🌊 the surf rolls up the sand and slides back
	for _, f in ipairs(CollectionService:GetTagged("Surf")) do
		if (f.Position - camPos).Magnitude < 500 then
			spinners[f] = spinners[f] or f.CFrame
			local base = spinners[f]
			local ph = f:GetAttribute("Phase") or 0
			local w = math.sin(t * 0.55 + ph)
			f.CFrame = base * CFrame.new(math.sin(t * 0.13 + ph) * 3, 0, -w * 3.2)
			f.Transparency = 0.2 + (1 - (w + 1) / 2) * 0.55
		end
	end
	-- 🦀 crabs scuttle sideways, stop, scuttle back
	for _, b in ipairs(CollectionService:GetTagged("Crab")) do
		local m = b.Parent
		if m and (b.Position - camPos).Magnitude < 160 then
			local rec = crabs[m]
			if not rec then
				rec = { Base = b.CFrame, Parts = {} }
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") then
						rec.Parts[p] = b.CFrame:ToObjectSpace(p.CFrame)
					end
				end
				crabs[m] = rec
			end
			local ph = rec.Base.Position.X * 0.31
			local c = (t * 0.25 + ph) % 2
			local slide = if c < 0.7 then c / 0.7 elseif c < 1 then 1 elseif c < 1.7 then 1 - (c - 1) / 0.7 else 0
			local moving = (c < 0.7 or (c >= 1 and c < 1.7))
			local skitter = if moving then math.sin(t * 30) * 0.05 else 0
			local cf = rec.Base * CFrame.new(slide * 4 - 2, skitter, 0)
			for p, off in pairs(rec.Parts) do
				local o = off
				if p.Name == "CrabLeg" and moving then
					o = off * CFrame.Angles(0, 0, math.sin(t * 30 + off.Position.Z * 9) * 0.35)
				elseif p.Name == "CrabClaw" then
					o = off * CFrame.new(0, math.max(0, math.sin(t * 3 + ph)) * 0.12, 0)
				end
				p.CFrame = cf * o
			end
		end
	end
	-- 🐬 dolphins swim along under the surface and leap out in arcs; the jet
	-- ski carves a wide loop (each moves its whole model, kept in a rig like
	-- the crabs')
	local function rig(b)
		local m = b.Parent
		local rec = crabs[m]
		if not rec then
			rec = { Base = b.CFrame, Parts = {} }
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("BasePart") then
					rec.Parts[p] = b.CFrame:ToObjectSpace(p.CFrame)
				end
			end
			crabs[m] = rec
		end
		return rec
	end
	for _, b in ipairs(CollectionService:GetTagged("Dolphin")) do
		if b.Parent and (b.Position - camPos).Magnitude < 700 then
			local rec = rig(b)
			local ph = b.Parent:GetAttribute("Phase") or 0
			-- along a long loop; every 7 seconds a leap
			local a = t * 0.06 + ph * 0.05
			local pos = rec.Base.Position + Vector3.new(math.sin(a) * 140, 0, math.cos(a) * 30)
			local dir = Vector3.new(math.cos(a) * 140, 0, -math.sin(a) * 30).Unit
			local c = ((t + ph) % 7) / 7
			local y, pitch = -4, 0
			if c < 0.25 then
				local u = c / 0.25
				y = -4 + math.sin(u * math.pi) * 9
				pitch = math.cos(u * math.pi) * 0.9
			end
			local at = Vector3.new(pos.X, y, pos.Z)
			local cf = CFrame.lookAt(at, at + dir) * CFrame.Angles(pitch, 0, 0)
			for p, off in pairs(rec.Parts) do
				p.CFrame = cf * off
			end
		end
	end
	for _, b in ipairs(CollectionService:GetTagged("JetSki")) do
		if b.Parent and (b.Position - camPos).Magnitude < 700 then
			local rec = rig(b)
			local a = t * 0.25
			local c = rec.Base.Position
			local pos = Vector3.new(c.X + math.sin(a) * 70, c.Y + math.sin(t * 3) * 0.12, c.Z + math.cos(a) * 45)
			local dir = Vector3.new(math.cos(a) * 70, 0, -math.sin(a) * 45).Unit
			local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.sin(t * 2.2) * 0.04, 0, 0.22)
			for p, off in pairs(rec.Parts) do
				p.CFrame = cf * off
			end
		end
	end
	-- 🪩 the nightclub's dance floor cycles through colours
	for _, tile in ipairs(CollectionService:GetTagged("DanceTile")) do
		if (tile.Position - camPos).Magnitude < 90 then
			local ph = tile:GetAttribute("Phase") or 0
			tile.Color = Color3.fromHSV(((t * 0.25 + ph * 0.13) % 1), 0.75, if math.sin(t * 4.2 + ph) > 0 then 1 else 0.55)
		end
	end
	-- 🐠 aquarium fish swim back and forth (and race to the top at feeding time)
	for _, fish in ipairs(CollectionService:GetTagged("AquaFish")) do
		if (fish.Position - camPos).Magnitude < 90 then
			spinners[fish] = spinners[fish] or fish.CFrame
			local base = spinners[fish]
			local ph = base.Position.X * 0.7 + base.Position.Z * 0.3
			local model = fish.Parent
			local fed = model and (model:GetAttribute("FedUntil") or 0) > workspace:GetServerTimeNow()
			local speed = if fed then 1.6 else 0.45
			local circle = fish:GetAttribute("Circle")
			if circle then
				local a = t * speed + ph
				local pos = base.Position + Vector3.new(math.cos(a) * circle, (if fed then 1.5 else 0) + math.sin(a * 2) * 0.3, math.sin(a) * circle)
				fish.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
			else
				local range = fish:GetAttribute("Range") or 4
				local u = math.sin(t * speed + ph)
				local dir = math.cos(t * speed + ph)
				local along = if fish:GetAttribute("Along") == "Z" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
				local pos = base.Position + along * u * range + Vector3.new(0, (if fed then 2 else 0) + math.sin(t * 1.3 + ph) * 0.3, 0)
				local look = along * (if dir >= 0 then 1 else -1)
				-- (the fish's long side is X: point it along the way it swims)
				fish.CFrame = CFrame.lookAt(pos, pos + look) * CFrame.Angles(0, math.rad(90), 0)
			end
		end
	end
	-- 🌿 kelp sways in the current
	for _, k in ipairs(CollectionService:GetTagged("Sway")) do
		if (k.Position - camPos).Magnitude < 120 then
			spinners[k] = spinners[k] or k.CFrame
			local base = spinners[k]
			local h = k.Size.Y / 2
			k.CFrame = base * CFrame.new(0, -h, 0) * CFrame.Angles(math.sin(t * 0.9 + base.Position.X) * 0.18, 0, math.sin(t * 0.7 + base.Position.Z) * 0.14) * CFrame.new(0, h, 0)
		end
	end
	for m in pairs(crabs) do
		if not m.Parent then
			crabs[m] = nil
		end
	end
	-- rooftop fans turning
	for _, f in ipairs(CollectionService:GetTagged("Spin")) do
		if (f.Position - camPos).Magnitude < 220 then
			spinners[f] = spinners[f] or f.CFrame
			local base = spinners[f]
			f.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, t * 5 + base.Position.X * 0.3, 0) * base.Rotation
		end
	end
	for p in pairs(spinners) do
		if not p.Parent then
			spinners[p] = nil
		end
	end
	for p in pairs(flags) do
		if not p.Parent then
			flags[p] = nil
		end
	end
	for p in pairs(bobbers) do
		if not p.Parent then
			bobbers[p] = nil
		end
	end
end

-- 🏐 the beach volleyball goes back and forth over the net
local function stepVolleyball(t, camPos)
	for _, ball in ipairs(CollectionService:GetTagged("Volleyball")) do
		local a, b = ball:GetAttribute("SideA"), ball:GetAttribute("SideB")
		if a and b and (ball.Position - camPos).Magnitude < 250 then
			local c = (t / 1.3) % 2
			local from, to = if c < 1 then a else b, if c < 1 then b else a
			local u = c % 1
			local p = from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * 9, 0)
			ball.CFrame = CFrame.new(p) * CFrame.Angles(t * 5, t * 3, 0)
		end
	end
end

-- 🌧️ rain: an emitter in the sky that follows the camera, and splashes
local rain
function Ambient.Rain(on, camPos)
	if on and not rain then
		local sky = Instance.new("Part")
		sky.Name = "RainCloud"
		sky.Size = Vector3.new(160, 1, 160)
		sky.Transparency = 1
		sky.Anchored, sky.CanCollide, sky.CanQuery, sky.CanTouch = true, false, false, false
		local drops = Instance.new("ParticleEmitter")
		drops.Name = "Drops"
		drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		drops.Color = ColorSequence.new(Color3.fromRGB(200, 215, 235))
		drops.LightEmission = 0.1
		drops.Transparency = NumberSequence.new(0.35)
		drops.Size = NumberSequence.new(0.18)
		drops.Squash = NumberSequence.new(-4) -- long, thin streaks
		drops.Speed = NumberRange.new(90, 110)
		drops.EmissionDirection = Enum.NormalId.Bottom
		drops.Lifetime = NumberRange.new(0.6, 0.8)
		drops.Rate = 900
		drops.Orientation = Enum.ParticleOrientation.VelocityParallel
		drops.Parent = sky
		local splash = Instance.new("Part")
		splash.Name = "RainSplash"
		splash.Size = Vector3.new(90, 0.2, 90)
		splash.Transparency = 1
		splash.Anchored, splash.CanCollide, splash.CanQuery, splash.CanTouch = true, false, false, false
		local splashes = Instance.new("ParticleEmitter")
		splashes.Name = "Splashes"
		splashes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		splashes.Color = ColorSequence.new(Color3.fromRGB(220, 230, 245))
		splashes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		splashes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.5) })
		splashes.Speed = NumberRange.new(2, 4)
		splashes.SpreadAngle = Vector2.new(60, 60)
		splashes.Lifetime = NumberRange.new(0.15, 0.3)
		splashes.Rate = 260
		splashes.Parent = splash
		sky.Parent = folder
		splash.Parent = folder
		rain = { Sky = sky, Splash = splash }
	elseif not on and rain then
		rain.Sky:Destroy()
		rain.Splash:Destroy()
		rain = nil
	end
	if rain and camPos then
		rain.Sky.CFrame = CFrame.new(camPos + Vector3.new(0, 60, 0))
		rain.Splash.CFrame = CFrame.new(camPos.X, 0.6, camPos.Z)
	end
	return rain
end

function Ambient.Step(dt)
	local camera = workspace.CurrentCamera
	if not camera or not folder then
		return
	end
	local camPos = camera.CFrame.Position
	-- (animation time adds up frame by frame: smooth even when a frame hitches)
	Ambient.Clock = (Ambient.Clock or 0) + math.min(dt or 0, 0.1)
	local t = Ambient.Clock
	local near = people()
	-- (people walking by startle the pigeons; people standing still don't)
	for _, m in ipairs(CollectionService:GetTagged("Citizen")) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r and not r.Anchored and (r.Position - camPos).Magnitude < 220 and (r.AssemblyLinearVelocity or Vector3.zero).Magnitude > 2 then
			table.insert(near, r.Position)
		end
	end
	stepPigeons(dt, t, camPos, near)
	stepBeach(dt, t, camPos)
	stepTubes(t, camPos)
	stepFlags(t, camPos)
	stepVolleyball(t, camPos)
	Ambient.Rain(workspace:GetAttribute("Raining") == true, camPos)
end

function Ambient.Start()
	folder = Instance.new("Folder")
	folder.Name = "LocalAmbient"
	folder.Parent = workspace
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(Ambient.Step, math.min(dt, 0.1))
		if not ok then
			warn("[Ambient] " .. tostring(err))
		end
	end)
end

return Ambient
