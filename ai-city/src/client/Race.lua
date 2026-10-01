-- Race (ModuleScript) — StarterPlayerScripts.CityClient.Race
-- What you see during a street race (see RaceService): a big countdown, a
-- glowing ring over the next checkpoint (and a faint one over the one after),
-- a beam from your car toward it, and a timer with your checkpoint count.
-- Only you see your rings.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Race = {}
local player = Players.LocalPlayer
local cur -- the race we're in: { Name, Points, Index, Start, Going }
local folder, ring, nextRing, gui, timer, big

local GOLD = Color3.fromRGB(255, 210, 60)
local DIM = Color3.fromRGB(120, 200, 255)

local function makeRing(name, color, transparency)
	local m = Instance.new("Model")
	m.Name = name
	-- twelve glowing bars make a hoop you drive through
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		local p = Instance.new("Part")
		p.Name = "RingBit"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = transparency
		p.Size = Vector3.new(4.6, 1, 1)
		p:SetAttribute("Angle", a)
		p.Parent = m
	end
	m.Parent = folder
	return m
end

local function place(m, pos, look, spin)
	if not m then
		return
	end
	local base = CFrame.lookAt(pos + Vector3.new(0, 9, 0), pos + Vector3.new(0, 9, 0) + look)
	for _, p in ipairs(m:GetChildren()) do
		local a = (p:GetAttribute("Angle") or 0) + spin
		p.CFrame = base * CFrame.Angles(0, 0, a) * CFrame.new(0, 9, 0)
	end
end

local function label(parent, size, pos, text, textSize)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.TextSize = textSize
	t.Text = text
	t.Parent = parent
	return t
end

function Race.Show(d)
	if d.Done then
		cur = nil
		if folder then
			folder:ClearAllChildren()
		end
		ring, nextRing = nil, nil
		if timer then
			timer.Visible = false
		end
		if big then
			big.Text = if d.Time then string.format("🏁 %.1fs", d.Time) else ""
			task.delay(3, function()
				if not cur and big then
					big.Text = ""
				end
			end)
		end
		return
	end
	cur = { Name = d.Name, Points = d.Points, Index = d.Index, Start = d.Start, Going = d.Going }
	if not ring then
		ring = makeRing("RaceRing", GOLD, 0.1)
		nextRing = makeRing("RaceRingNext", DIM, 0.7)
	end
	if timer then
		timer.Visible = true
	end
end

function Race.Current()
	return cur
end

-- every frame: spin the rings, count down, run the clock
function Race.Update(dt)
	if not cur then
		return
	end
	local now = workspace:GetServerTimeNow()
	local pts = cur.Points
	local p = pts[cur.Index]
	if p then
		local nxt = pts[cur.Index + 1]
		local prev = pts[cur.Index - 1] or (p - Vector3.new(0, 0, 1))
		local look = Vector3.new(p.X - prev.X, 0, p.Z - prev.Z)
		if look.Magnitude < 0.1 then
			look = Vector3.new(0, 0, -1)
		end
		local pulse = 1 + math.sin(now * 6) * 0.08
		place(ring, p, look.Unit, now * 1.2)
		for _, b in ipairs(ring:GetChildren()) do
			b.Size = Vector3.new(4.6 * pulse, 1, 1)
		end
		if nxt then
			local l2 = Vector3.new(nxt.X - p.X, 0, nxt.Z - p.Z)
			place(nextRing, nxt, if l2.Magnitude > 0.1 then l2.Unit else look.Unit, -now * 0.6)
		else
			place(nextRing, Vector3.new(0, -500, 0), Vector3.new(0, 0, -1), 0)
		end
	end
	if not timer then
		return
	end
	if now < cur.Start then
		big.Text = tostring(math.ceil(cur.Start - now))
		big.TextColor3 = Color3.fromRGB(255, 120, 90)
		timer.Text = cur.Name
	else
		if now - cur.Start < 1.2 then
			big.Text = "GO!"
			big.TextColor3 = Color3.fromRGB(120, 255, 140)
		else
			big.Text = ""
		end
		timer.Text = string.format("🏁 %s   %.1fs   ✅ %d/%d", cur.Name, now - cur.Start, cur.Index - 1, #pts)
	end
end

function Race.Start(ctx)
	folder = Instance.new("Folder")
	folder.Name = "RaceRings"
	folder.Parent = workspace
	gui = Instance.new("ScreenGui")
	gui.Name = "RaceHud"
	gui.ResetOnSpawn = false
	timer = label(gui, UDim2.fromOffset(460, 40), UDim2.new(0.5, 0, 0, 96), "", 26)
	timer.Visible = false
	big = label(gui, UDim2.fromOffset(300, 120), UDim2.new(0.5, 0, 0.28, 0), "", 96)
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if pg then
		gui.Parent = pg
	end
	RunService.RenderStepped:Connect(function(dt)
		Race.Update(dt)
	end)
end

return Race
