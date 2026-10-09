-- MuscleScreen: the Muscle Progression screen (Hub Body tab "3D MUSCLE VIEW", training result "MUSCLES").
-- A rotating 3D figure (a ViewportFrame holding a frozen copy of the player's character, meshes and
-- all - the same cloning rules as FighterCard's portrait) with the selected muscle group lit by
-- translucent neon shells laid over the rig parts (a Highlight does not draw inside a ViewportFrame),
-- tabs for Arms, Chest, Core, Legs, Shoulders, Back and Neck with every sub-muscle's level against
-- the frame's potential, and the group's growth over time: a line graph of the per-day history the
-- server keeps (profile.muscleHist, handlers.GetMuscleHistory).
-- Mouse: drag the figure. Touch: drag. Gamepad: right stick rotates, LB / RB step the groups, B closes.
-- Left alone, the figure turns slowly by itself.
--   MuscleScreen.Open({ growth = result.parts, group = "chest", back = fn })   MuscleScreen.Close()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UI"))
local Config = require(Shared:WaitForChild("Config"))
local Gamepad = require(Shared:WaitForChild("Gamepad"))
local State = require(script.Parent:WaitForChild("State"))
local BodyMap = require(script.Parent:WaitForChild("BodyMap"))

local T = UI.Theme
local K = Enum.KeyCode
local player = Players.LocalPlayer
local A = CFrame.Angles
local V = Vector3.new

local MuscleScreen = {}

-- the groups in tab order (the seven coarse groups of Config.MuscleKeys) and their accent colours
local GROUPS = {
	{ id = "arms", name = "Arms", color = Color3.fromRGB(255, 128, 64) },
	{ id = "chest", name = "Chest", color = Color3.fromRGB(255, 82, 92) },
	{ id = "core", name = "Core", color = Color3.fromRGB(255, 204, 72) },
	{ id = "legs", name = "Legs", color = Color3.fromRGB(96, 220, 120) },
	{ id = "shoulders", name = "Shoulders", color = Color3.fromRGB(72, 214, 240) },
	{ id = "back", name = "Back", color = Color3.fromRGB(110, 150, 255) },
	{ id = "neck", name = "Neck", color = Color3.fromRGB(214, 140, 255) },
}
local GROUP_NAMES = {}
for _, g in ipairs(GROUPS) do
	table.insert(GROUP_NAMES, g.name)
end
local function groupDef(id)
	for _, g in ipairs(GROUPS) do
		if g.id == id or g.name == id then
			return g
		end
	end
	return GROUPS[1]
end
MuscleScreen.Groups = GROUPS

-- the glow shells per group: { rig part, centre (fractions of the part's size), size (fractions) }.
-- Front is -Z in a part's own frame; the left arm hangs on the -X side.
local SHELLS = {
	chest = { { "UpperTorso", V(-0.24, 0.17, -0.4), V(0.5, 0.44, 0.36) }, { "UpperTorso", V(0.24, 0.17, -0.4), V(0.5, 0.44, 0.36) } },
	shoulders = { { "LeftUpperArm", V(0, 0.34, 0), V(1.3, 0.52, 1.3) }, { "RightUpperArm", V(0, 0.34, 0), V(1.3, 0.52, 1.3) } },
	arms = { { "LeftUpperArm", V(0, -0.1, 0), V(1.16, 0.82, 1.16) }, { "RightUpperArm", V(0, -0.1, 0), V(1.16, 0.82, 1.16) },
		{ "LeftLowerArm", V(0, 0, 0), V(1.16, 1.04, 1.16) }, { "RightLowerArm", V(0, 0, 0), V(1.16, 1.04, 1.16) } },
	back = { { "UpperTorso", V(0, 0.08, 0.4), V(0.98, 0.9, 0.36) } },
	core = { { "UpperTorso", V(0, -0.3, -0.4), V(0.66, 0.44, 0.32) }, { "LowerTorso", V(0, 0.04, -0.38), V(0.74, 0.98, 0.36) } },
	legs = { { "LeftUpperLeg", V(0, 0, 0), V(1.14, 1.04, 1.14) }, { "RightUpperLeg", V(0, 0, 0), V(1.14, 1.04, 1.14) },
		{ "LeftLowerLeg", V(0, 0, 0), V(1.14, 1.04, 1.14) }, { "RightLowerLeg", V(0, 0, 0), V(1.14, 1.04, 1.14) } },
	neck = { { "Head", V(0, -0.56, 0.04), V(0.66, 0.5, 0.66) } },
}

-- the display stance: arms a little away from the body (the lats and the arms read), elbows soft.
-- Per R15 joint: the Motor6D's Transform in its own frame and the part it moves
local STANCE = {
	LeftShoulder = { "LeftUpperArm", A(0.06, 0, -0.42) },
	RightShoulder = { "RightUpperArm", A(0.06, 0, 0.42) },
	LeftElbow = { "LeftLowerArm", A(0.32, 0, 0) },
	RightElbow = { "RightLowerArm", A(0.32, 0, 0) },
	Waist = { "UpperTorso", A(0.02, 0, 0) },
	Neck = { "Head", A(0, 0, 0) },
}

local STRIP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
	BillboardGui = true, ProximityPrompt = true, ClickDetector = true, BodyMover = true, AlignPosition = true, AlignOrientation = true,
	Fire = true, Smoke = true, Sparkles = true, PointLight = true, SpotLight = true, SurfaceLight = true }
local R15 = { HumanoidRootPart = true, Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }

local FOV = 26
local AUTO_SPIN = 0.45 -- rad/s when nobody touches the figure
local IDLE_BEFORE_SPIN = 2.2
-- the groups that sit on one side of the body: picking one turns the figure to show it (yaw 0 = the
-- front faces the camera), and left alone it sways around that side instead of spinning away
local FACING = { chest = 0, core = 0, back = math.pi }
local TURN_SPEED = 4 -- rad/s
local SWAY = 0.7 -- rad either side of the facing when idle

------------------------------------------------------------------------
-- The figure: a frozen copy of the character (the cloning rules of FighterCard's portrait, without
-- its waist-down pruning: this screen shows the legs)
------------------------------------------------------------------------
-- pairs every clone instance with the live one it was copied from (Clone keeps archivable children in order)
local function pairTrees(src, dst, map)
	map[dst] = src
	local a, b = src:GetChildren(), dst:GetChildren()
	local j = 1
	for _, ca in ipairs(a) do
		if ca.Archivable then
			local cb = b[j]
			if not cb then
				return
			end
			if cb.Name == ca.Name and cb.ClassName == ca.ClassName then
				pairTrees(ca, cb, map)
			end
			j += 1
		end
	end
end

local anatomy, anatomyLoaded = nil, false
local function anatomyClient()
	if not anatomyLoaded then
		anatomyLoaded = true
		local m = script.Parent:FindFirstChild("AnatomyClient")
		local ok, ac = false, nil
		if m then
			ok, ac = pcall(require, m)
		end
		anatomy = (ok and type(ac) == "table") and ac or nil
	end
	return anatomy
end

-- a copied anatomy MeshPart still shows its mesh only while its MeshContent carries the EditableMesh
local function meshCarried(mp)
	local ok, has = pcall(function()
		local c = mp.MeshContent
		return c ~= nil and c.Object ~= nil
	end)
	return ok and has == true
end

local function keepMeshes(clone)
	local folder = clone:FindFirstChild("Anatomy")
	if not folder then
		return false
	end
	local n = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") then
			if not meshCarried(d) then
				folder:Destroy()
				return false
			end
			n += 1
		end
	end
	if n == 0 then
		folder:Destroy()
		return false
	end
	return true
end

-- what the live meshes hide (round-1 parts a mesh replaced, pieces tucked under headgear) stays hidden
-- when the meshes came along; the camera's own first-person fade is never copied
local function copyHidden(char, map, meshes)
	local ac = anatomyClient()
	local isReplaced = ac and ac.IsReplaced
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("LeftHand")
	local cameraFade = hand ~= nil and hand:IsA("BasePart") and hand.LocalTransparencyModifier > 0
	local pieces = char:FindFirstChild("Anatomy")
	for copy, src in pairs(map) do
		local replaced = false
		if isReplaced then
			local ok, r = pcall(isReplaced, src)
			replaced = ok and r == true
		end
		if copy:IsA("SurfaceGui") or copy:IsA("BillboardGui") then
			if copy:GetAttribute("AnatomyHid") == true then
				copy.Enabled = not meshes
				copy:SetAttribute("AnatomyHid", nil)
			end
		elseif meshes and (copy:IsA("BasePart") or copy:IsA("Decal")) then
			local covered = not cameraFade and pieces ~= nil and copy:IsA("MeshPart") and src.LocalTransparencyModifier >= 0.99 and src:IsDescendantOf(pieces)
			if replaced or covered then
				copy.Transparency = 1
			end
		end
	end
end

-- forward kinematics from the root: the stance joints take their transforms, every other joint keeps
-- the offset it has on the live character right now; the joints go afterwards (anchored copy)
local function poseClone(clone, pose, map)
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local function cf(part)
		local src = map[part]
		return (src and src.Parent) and src.CFrame or part.CFrame
	end
	root.CFrame = cf(root)
	local links, joints = {}, {}
	local function link(a, b, rel)
		if not (a and b and a:IsA("BasePart") and b:IsA("BasePart")) then
			return
		end
		links[a] = links[a] or {}
		links[b] = links[b] or {}
		table.insert(links[a], { b, rel })
		table.insert(links[b], { a, rel:Inverse() })
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("JointInstance") then
			local p = d:IsA("Motor6D") and pose[d.Name]
			if p and d.Part1 and d.Part1.Name == p[1] then
				link(d.Part0, d.Part1, d.C0 * p[2] * d.C1:Inverse())
			elseif d.Part0 and d.Part1 then
				link(d.Part0, d.Part1, cf(d.Part0):ToObjectSpace(cf(d.Part1)))
			end
			table.insert(joints, d)
		elseif d:IsA("WeldConstraint") then
			if d.Part0 and d.Part1 then
				link(d.Part0, d.Part1, cf(d.Part0):ToObjectSpace(cf(d.Part1)))
			end
			table.insert(joints, d)
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				local p = pose[d.Name]
				if p and a1.Parent.Name == p[1] then
					link(a0.Parent, a1.Parent, a0.CFrame * p[2] * a1.CFrame:Inverse())
				else
					link(a0.Parent, a1.Parent, cf(a0.Parent):ToObjectSpace(cf(a1.Parent)))
				end
			end
			table.insert(joints, d)
		end
	end
	for _, j in ipairs(joints) do
		j:Destroy()
	end
	local seen = { [root] = true }
	local queue = { root }
	local i = 1
	while i <= #queue do
		local p = queue[i]
		i += 1
		for _, e in ipairs(links[p] or {}) do
			local q = e[1]
			if not seen[q] then
				seen[q] = true
				q.CFrame = p.CFrame * e[2]
				table.insert(queue, q)
			end
		end
	end
end

-- the frozen figure (nil without a character)
local function buildFigure(char)
	if not (char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Head")) then
		return nil
	end
	local was = char.Archivable
	local ok, clone = pcall(function()
		char.Archivable = true
		return char:Clone()
	end)
	pcall(function()
		char.Archivable = was
	end)
	if not (ok and clone) then
		return nil
	end
	local map = {}
	pcall(pairTrees, char, clone, map)
	pcall(copyHidden, char, map, keepMeshes(clone))
	for _, d in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do
			CollectionService:RemoveTag(d, tag)
		end
		if STRIP[d.ClassName] or d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(clone)) do
		CollectionService:RemoveTag(clone, tag)
	end
	pcall(poseClone, clone, STANCE, map)
	for _, d in ipairs(clone:GetDescendants()) do
		if d.Parent then
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				local rigPart = d.Parent == clone and R15[d.Name]
				if not rigPart and d.Transparency >= 0.99 then
					d:Destroy()
				end
			elseif d:IsA("Attachment") or d:IsA("Constraint") then
				d:Destroy()
			end
		end
	end
	clone.Name = "Figure"
	return clone
end

-- the figure's visible extent: bottom / top (world Y) and the widest radius around the root
local function extent(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local cx, cz = root.Position.X, root.Position.Z
	local lo, hi, r = math.huge, -math.huge, 0.5
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local half = d.Size.Magnitude * 0.5
			lo = math.min(lo, d.Position.Y - half)
			hi = math.max(hi, d.Position.Y + half)
			local dx, dz = d.Position.X - cx, d.Position.Z - cz
			r = math.max(r, math.sqrt(dx * dx + dz * dz) + half * 0.6)
		end
	end
	if lo == math.huge then
		lo, hi = root.Position.Y - 3, root.Position.Y + 3
	end
	return lo, hi, r
end

-- the neon shells of one group, parented under a folder in the figure (hidden until the group is picked)
local function buildShells(figure, def)
	local folder = Instance.new("Folder")
	folder.Name = "Shells_" .. def.id
	local parts = {}
	for _, spec in ipairs(SHELLS[def.id] or {}) do
		local rig = figure:FindFirstChild(spec[1])
		if rig and rig:IsA("BasePart") then
			local s = rig.Size
			local p = Instance.new("Part")
			p.Name = "Shell"
			p.Anchored = true
			p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = def.color
			p.Transparency = 1
			p.Size = V(spec[3].X * s.X, spec[3].Y * s.Y, spec[3].Z * s.Z)
			p.CFrame = rig.CFrame * CFrame.new(spec[2].X * s.X, spec[2].Y * s.Y, spec[2].Z * s.Z)
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
			p.Parent = folder
			table.insert(parts, p)
		end
	end
	folder.Parent = figure
	return parts
end

------------------------------------------------------------------------
-- Numbers
------------------------------------------------------------------------
local function frameCap(P)
	local frameDef = Config.FindById(Config.BodyTypes, P and P.appearance and P.appearance.body and P.appearance.body.frame or "") or Config.BodyTypes[2]
	return 100 * (frameDef.potential or 1)
end

local function partLevel(P, id)
	return tonumber(Config.PartValue and Config.PartValue(P and P.body, id) or (P and P.body and P.body[id])) or 0
end

local function groupLevel(P, id)
	local v = P and P.body and tonumber(P.body[id])
	if v then
		return v
	end
	-- an old summary without the group: the share-weighted parts
	local total = 0
	for _, p in ipairs(Config.MuscleGroupParts[id] or {}) do
		total += p.share * partLevel(P, p.id)
	end
	return total
end

local function fmt1(v)
	return string.format("%.1f", v)
end

-- the group's series: the server's per-day rows plus today's live value, oldest first
local function series(hist, id, P)
	local out = {}
	for _, row in ipairs(hist or {}) do
		local v = tonumber(row[id])
		local d = tonumber(row.d)
		if v and d then
			table.insert(out, { d = d, v = v })
		end
	end
	local today = P and tonumber(P.day) or nil
	if today then
		local live = { d = today, v = groupLevel(P, id) }
		if #out > 0 and out[#out].d == today then
			out[#out] = live
		elseif #out == 0 or out[#out].d < today then
			table.insert(out, live)
		end
	end
	return out
end
MuscleScreen.Series = series

------------------------------------------------------------------------
-- The growth graph (a single series: the group over the logged days)
------------------------------------------------------------------------
local PAD_L, PAD_R, PAD_T, PAD_B = 40, 14, 12, 22
local function drawGraph(holder, pts, color)
	UI.Clear(holder)
	local scale = UI.ScaleOf(holder)
	if scale <= 0 then
		scale = 1
	end
	local W = holder.AbsoluteSize.X / scale
	local H = holder.AbsoluteSize.Y / scale
	if W < 60 or H < 40 then
		return false
	end
	local plotW, plotH = W - PAD_L - PAD_R, H - PAD_T - PAD_B
	local n = #pts
	if n == 0 then
		UI.Text(holder, "No history yet", { TextSize = 13, TextColor3 = T.sub, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
		return true
	end
	local lo, hi = math.huge, -math.huge
	for _, p in ipairs(pts) do
		lo, hi = math.min(lo, p.v), math.max(hi, p.v)
	end
	-- a flat line still needs a band to sit in; the band floors at zero
	local span = math.max(hi - lo, 2)
	lo = math.max(0, (lo + hi) * 0.5 - span * 0.5 - span * 0.15)
	hi = lo + span * 1.3
	local d0, d1 = pts[1].d, pts[n].d
	local function X(d)
		return PAD_L + (d1 > d0 and (d - d0) / (d1 - d0) or 0.5) * plotW
	end
	local function Y(v)
		return PAD_T + (1 - (v - lo) / (hi - lo)) * plotH
	end
	-- three recessive grid lines with their values
	for i = 0, 2 do
		local v = lo + (hi - lo) * i / 2
		local y = Y(v)
		UI.Frame(holder, { Name = "Grid", Position = UDim2.fromOffset(PAD_L, math.floor(y)), Size = UDim2.new(0, plotW, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9 })
		UI.Text(holder, fmt1(v), { Face = "number", TextSize = 11, TextColor3 = T.dim, Position = UDim2.fromOffset(0, math.floor(y) - 7), Size = UDim2.fromOffset(PAD_L - 6, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	end
	-- the days along the bottom: first and last (and the middle when the run is long)
	local function dayLabel(d, x, align)
		UI.Text(holder, "DAY " .. tostring(math.floor(d)), { Font = T.semi, TextSize = 11, TextColor3 = T.dim, Position = UDim2.fromOffset(math.floor(x) - 40, H - PAD_B + 6), Size = UDim2.fromOffset(80, 14), AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = align, TextWrapped = false })
	end
	dayLabel(d0, X(d0) + (d1 > d0 and 40 or 0), d1 > d0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center)
	if d1 > d0 then
		dayLabel(d1, X(d1) - 40, Enum.TextXAlignment.Right)
		if d1 - d0 >= 10 then
			dayLabel((d0 + d1) / 2, X((d0 + d1) / 2), Enum.TextXAlignment.Center)
		end
	end
	-- the line: one thin rotated frame per segment (2 px, the group's colour)
	for i = 2, n do
		local x1, y1 = X(pts[i - 1].d), Y(pts[i - 1].v)
		local x2, y2 = X(pts[i].d), Y(pts[i].v)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0.5 then
			UI.Frame(holder, { Name = "Seg", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5), Size = UDim2.fromOffset(len, 2),
				Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = color, ZIndex = 3 })
		end
	end
	-- markers: every point while the run is short, otherwise only the latest; the latest carries its value
	local markers = n <= 24
	for i, p in ipairs(pts) do
		if markers or i == n then
			local dot = UI.Frame(holder, { Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(X(p.d), Y(p.v)), Size = UDim2.fromOffset(i == n and 10 or 8, i == n and 10 or 8),
				BackgroundColor3 = i == n and T.text or color, ZIndex = 4 })
			UI.Corner(dot, 6)
			if i == n then
				UI.Stroke(dot, color, 2, 0)
			end
		end
	end
	local last = pts[n]
	local lx = X(last.d)
	UI.Text(holder, fmt1(last.v), { Face = "number", TextSize = 14, TextColor3 = T.text, Position = UDim2.fromOffset(math.min(lx + 8, W - 50), math.max(PAD_T - 4, Y(last.v) - 22)), Size = UDim2.fromOffset(50, 16),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 5 })
	return true
end
MuscleScreen.DrawGraph = drawGraph

------------------------------------------------------------------------
-- The screen
------------------------------------------------------------------------
local screen -- the open screen's state

function MuscleScreen.IsOpen()
	return screen ~= nil and screen.shade.Parent ~= nil
end

-- silent: another window is taking over (State.closeAll from its opener) - the "back" target (the
-- Hub) must not reopen over it. Only the player's own close (X, B, Backspace) goes back.
function MuscleScreen.Close(silent)
	local s = screen
	if not s then
		return
	end
	screen = nil
	State.windows.Muscle = nil
	for _, c in ipairs(s.conns) do
		c:Disconnect()
	end
	if s.shade then
		s.shade:Destroy()
	end
	State.HideHud("Muscle", false)
	if s.back and silent ~= true then
		task.defer(s.back)
	end
end
local function closeSilently()
	MuscleScreen.Close(true)
end

-- opts: growth = { [partId] = gain } (the session just finished: those parts are marked), group = the
-- group to open on, back = a function to run after closing (the Hub reopens its Body tab)
function MuscleScreen.Open(opts)
	opts = opts or {}
	local P = State.P
	if not (P and P.created) or State.inFight() then
		return
	end
	MuscleScreen.Close(true)
	State.closeAll("Muscle")
	-- modal like the hub: the HUD plate would peek out from behind the window
	State.HideHud("Muscle", true)
	local s = { conns = {}, growth = type(opts.growth) == "table" and opts.growth or nil, back = opts.back, yaw = 0, pitch = 0.12, idle = 0, stick = 0, keys = 0, history = nil }
	if opts.group == "back" then
		s.yaw = math.pi -- opened on the back: start behind the figure
	end
	screen = s
	local compact = UI.CanvasSize(State.gui).Y < 640
	local shade, win, body = UI.Window(State.gui, "Muscle", 1180, 720, "MUSCLE PROGRESSION", { onClose = function()
		MuscleScreen.Close(false)
	end, scroll = false, kicker = "BODY  ·  GROWTH OVER TIME" })
	s.shade, s.win = shade, win
	State.windows.Muscle = closeSilently
	-- which group opens: asked for, else the one that grew most this session, else the arms
	local current = groupDef(opts.group or "arms")
	if not opts.group and s.growth then
		local best = 0
		for id, g in pairs(s.growth) do
			local grp = Config.MusclePartGroup[id]
			g = tonumber(g) or 0
			if grp and g > best then
				best, current = g, groupDef(grp)
			end
		end
	end
	s.group = current

	------------------------------------------------------------------ the figure
	local viewW = compact and 0.38 or 0.42
	local stage = UI.Frame(body, { Name = "Stage", Size = UDim2.new(viewW, -8, 1, 0), BackgroundColor3 = Color3.fromRGB(10, 11, 16), ClipsDescendants = true })
	UI.Corner(stage, UI.R.lg)
	UI.Gradient(stage, { Color3.fromRGB(44, 46, 60), Color3.fromRGB(10, 11, 16) }, 90)
	UI.Stroke(stage, Color3.new(1, 1, 1), 1, 0.9)
	local vf = UI.New("ViewportFrame", {
		Name = "View", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true,
		Ambient = Color3.fromRGB(96, 94, 104), LightColor = Color3.fromRGB(255, 236, 214), Parent = stage,
	})
	s.vf = vf
	local figure = buildFigure(player.Character)
	s.figure = figure
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vf
	vf.CurrentCamera = cam
	s.shells = {}
	s.tints = {}
	if figure then
		local lo, hi, radius = extent(figure)
		local root = figure.HumanoidRootPart
		s.center = V(root.Position.X, (lo + hi) * 0.5, root.Position.Z)
		s.height = (hi - lo) * 1.12
		s.radius = radius
		local look = root.CFrame.LookVector
		s.front = V(look.X, 0, look.Z).Magnitude > 0.01 and V(look.X, 0, look.Z).Unit or V(0, 0, -1)
		figure.Parent = vf
		for _, g in ipairs(GROUPS) do
			s.shells[g.id] = buildShells(figure, g)
			s.tints[g.id] = {}
		end
		-- the muscle overlays of the round-1 body (attribute Group) tint along with their shells
		for _, d in ipairs(figure:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Shell" and d.Transparency < 0.99 then
				local g = d:GetAttribute("Group")
				if type(g) == "string" and s.tints[g] then
					table.insert(s.tints[g], { part = d, color = d.Color })
				end
			end
		end
		vf.LightDirection = (-s.front * 0.6 + V(0.5, -0.7, 0)).Unit
	else
		UI.Text(stage, "No character to show yet", { TextSize = 15, TextColor3 = T.sub, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	end
	-- the caption over the figure: the lit group, and how to turn it
	local cap = UI.Text(stage, "", { Name = "Caption", Face = "displayMed", TextSize = 20, TextColor3 = T.text, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 24), AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	-- (two lines from the bottom up: the keyboard hint wraps on a small window instead of losing its end)
	local hint = UI.Text(stage, "", { Name = "Hint", Font = T.semi, TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -10), Size = UDim2.new(1, -32, 0, 34),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Bottom, ZIndex = 3 })
	UI.BindHint(hint, function(mode)
		if mode == "gamepad" then
			return string.format("%s TURN   ·   %s / %s GROUP   ·   %s BACK", Gamepad.Label(K.Thumbstick2), Gamepad.Label(K.ButtonL1), Gamepad.Label(K.ButtonR1), Gamepad.Label(K.ButtonB))
		elseif mode == "touch" then
			return "DRAG TO TURN THE FIGURE"
		end
		return "DRAG TO TURN  ·  ARROW KEYS TURN  ·  BACKSPACE CLOSES"
	end)

	function s.updateCamera()
		if not figure then
			return
		end
		local abs = vf.AbsoluteSize
		local aspect = (abs.X > 4 and abs.Y > 4) and abs.X / abs.Y or 0.8
		local tanHalf = math.tan(math.rad(FOV / 2))
		local dist = math.max(s.height * 0.5 / tanHalf, s.radius * 2.2 / (tanHalf * aspect))
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, s.yaw) * s.front
		local pos = s.center + dir * dist + V(0, dist * s.pitch, 0)
		cam.CFrame = CFrame.lookAt(pos, s.center)
	end
	s.updateCamera()
	table.insert(s.conns, vf:GetPropertyChangedSignal("AbsoluteSize"):Connect(s.updateCamera))

	------------------------------------------------------------------ the panel
	local panel = UI.Scroll(body, { Name = "Panel", Position = UDim2.new(viewW, 8, 0, 0), Size = UDim2.new(1 - viewW, -8, 1, 0) })
	UI.List(panel, 8)
	UI.Pad(panel, 2, 6)
	local tabBar, pickTab = UI.Tabs(panel, GROUP_NAMES, current.name, function(name)
		s.setGroup(groupDef(name))
	end, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, UI.TabsHeight(panel, 38)), LayoutOrder = 1 })
	s.pickTab = pickTab
	s.tabBar = tabBar
	-- seven tabs across a phone: smaller caps on one line ("SHOULDERS" wrapped at 667 wide)
	local tabButtons = tabBar:FindFirstChild("Buttons")
	for _, b in ipairs(tabButtons and tabButtons:GetChildren() or {}) do
		if b:IsA("TextButton") then
			b.TextSize = compact and 11 or 13
			b.TextWrapped = false
			b.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
	local head = UI.Card(panel, { order = 2 })
	local parts = UI.Card(panel, { order = 3 })
	local growthCard = s.growth and UI.Card(panel, { order = 4, stroke = T.green }) or nil
	local graphCard = UI.Card(panel, { order = 5 })
	UI.Kicker(graphCard, "GROWTH OVER TIME", T.gold)
	local graphHolder = UI.Frame(graphCard, { Name = "Graph", Size = UDim2.new(1, 0, 0, compact and 120 or 150), BackgroundColor3 = T.ink, BackgroundTransparency = 0.35, ClipsDescendants = true })
	UI.Corner(graphHolder, UI.R.md)
	local graphNote = UI.Line(graphCard, "", { TextSize = 12, TextColor3 = T.sub })
	UI.Line(panel, "Every session grows the muscles it works; most of it lands overnight. A group logged once a day; muscles you neglect for a week fade.", { TextSize = 12, TextColor3 = T.dim, LayoutOrder = 6 })

	function s.redrawGraph()
		if not (graphHolder.Parent and screen == s) then
			return
		end
		local pts = series(s.history, s.group.id, State.P)
		if #pts > 40 then
			local trimmed = {}
			for i = #pts - 39, #pts do
				table.insert(trimmed, pts[i])
			end
			pts = trimmed
		end
		s.points = pts
		drawGraph(graphHolder, pts, s.group.color)
		if #pts >= 2 then
			local first, last = pts[1], pts[#pts]
			local d = last.v - first.v
			graphNote.Text = string.format("%s over %d day%s: %s%.1f  (%.1f -> %.1f)", s.group.name, last.d - first.d, last.d - first.d == 1 and "" or "s", d >= 0 and "+" or "", d, first.v, last.v)
			graphNote.TextColor3 = d > 0.05 and T.green or (d < -0.05 and T.orange or T.sub)
		elseif s.history == nil then
			graphNote.Text = "Loading the history..."
			graphNote.TextColor3 = T.sub
		else
			graphNote.Text = "Day one of the log: train, sleep and come back to watch the line climb."
			graphNote.TextColor3 = T.sub
		end
	end

	-- the headline and the sub-muscle rows for the lit group
	function s.render()
		local P1 = State.P or P
		local potential = frameCap(P1)
		local g = s.group
		UI.Clear(head)
		UI.Clear(parts)
		local lv = groupLevel(P1, g.id)
		local sore = tonumber(P1.condition and P1.condition.sore and P1.condition.sore[g.id]) or 0
		local top = UI.Frame(head, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) })
		UI.Text(top, string.upper(g.name), { Face = "display", TextSize = 34, TextColor3 = g.color, Size = UDim2.new(0.6, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		UI.Text(top, string.format('%s <font color="#%s" size="16">/ %d</font>', fmt1(lv), T.sub:ToHex(), math.floor(potential + 0.5)), { Name = "Level", Face = "number", TextSize = 30, RichText = true, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		UI.LevelBar(head, { Size = UDim2.new(1, 0, 0, 10) }, { value = lv, cap = potential, color = BodyMap.DevColor(lv / potential) })
		local chips = UI.Frame(head, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
		UI.List(chips, 6, true)
		local pts = series(s.history, g.id, P1)
		local week = nil
		for i = #pts, 1, -1 do
			if pts[#pts].d - pts[i].d >= 7 then
				week = pts[#pts].v - pts[i].v
				break
			end
		end
		if week == nil and #pts >= 2 then
			week = pts[#pts].v - pts[1].v
		end
		if week then
			UI.Chip(chips, string.format("%s%.1f THIS WEEK", week >= 0 and "+" or "", week), week > 0.05 and T.green or (week < -0.05 and T.orange or T.sub), { order = 1, h = 26, TextSize = 12 })
		end
		if sore >= 0.1 then
			UI.Chip(chips, string.format("SORE %d%%", math.floor(sore * 100 + 0.5)), T.orange, { order = 2, h = 26, TextSize = 12 })
		end
		UI.Chip(chips, string.format("%d%% OF POTENTIAL", math.floor(math.clamp(lv / potential, 0, 1) * 100 + 0.5)), BodyMap.DevColor(lv / potential), { order = 3, h = 26, TextSize = 12 })
		UI.Kicker(parts, g.name .. "  ·  EVERY MUSCLE", g.color)
		for _, part in ipairs(Config.MuscleGroupParts[g.id] or {}) do
			local v = partLevel(P1, part.id)
			local gain = s.growth and tonumber(s.growth[part.id]) or 0
			local row = UI.Frame(parts, { Name = "Part", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) })
			UI.Text(row, string.upper(BodyMap.Short(part.id)), { Font = T.semi, TextSize = 14, TextColor3 = gain > 0.005 and T.green or T.text, Size = UDim2.new(0, 124, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			if gain > 0.005 then
				UI.LevelBar(row, { Position = UDim2.new(0, 130, 0.5, -5), Size = UDim2.new(1, -130 - 118, 0, 10) }, { gain = { v - gain, v }, cap = potential, color = BodyMap.DevColor(v / potential) })
				UI.Text(row, string.format("+%.2f", gain), { Face = "number", TextSize = 15, TextColor3 = T.green, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -54, 0, 2), Size = UDim2.fromOffset(60, 20),
					AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			else
				UI.LevelBar(row, { Position = UDim2.new(0, 130, 0.5, -5), Size = UDim2.new(1, -130 - 118, 0, 10) }, { value = v, cap = potential, color = BodyMap.DevColor(v / potential) })
			end
			UI.Text(row, fmt1(v), { Face = "number", TextSize = 16, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 1), Size = UDim2.fromOffset(50, 22),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		end
		s.redrawGraph()
	end

	-- the session's growth, every part that grew with its gain (opened from the training result)
	if growthCard then
		UI.Kicker(growthCard, "GROWTH THIS SESSION", T.green)
		local list = {}
		for id, g in pairs(s.growth) do
			g = tonumber(g)
			if g and g > 0.005 and Config.MusclePartGroup[id] then
				table.insert(list, { id = id, g = g })
			end
		end
		table.sort(list, function(a, b)
			return a.g > b.g
		end)
		-- rows of chips that wrap by an estimate of their width (the card is about 0.56 of the window)
		local rows = UI.Frame(growthCard, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		UI.List(rows, 6)
		local width = (compact and 420 or 600)
		local row, used, n = nil, 0, 0
		for i, e in ipairs(list) do
			local text = string.format("%s +%.2f", string.upper(BodyMap.Short(e.id)), e.g)
			local est = #text * 7.5 + 24
			if not row or used + est > width then
				n += 1
				row = UI.Frame(rows, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = n })
				UI.List(row, 6, true)
				used = 0
			end
			used += est + 6
			UI.Chip(row, text, groupDef(Config.MusclePartGroup[e.id]).color, { order = i, h = 26, TextSize = 12 })
		end
		if #list == 0 then
			UI.Line(growthCard, "Nothing grew this time.", { TextSize = 13, TextColor3 = T.sub })
		end
	end

	-- lighting the group: its shells show (pulsing), the others hide; the overlays tint
	function s.setGroup(def)
		s.group = def
		for id, list in pairs(s.shells) do
			for _, p in ipairs(list) do
				p.Transparency = id == def.id and 0.5 or 1
			end
		end
		for id, list in pairs(s.tints) do
			for _, e in ipairs(list) do
				e.part.Color = id == def.id and e.color:Lerp(def.color, 0.75) or e.color
			end
		end
		cap.Text = string.upper(def.name) .. "  ·  LIT"
		cap.TextColor3 = def.color
		-- a group on one side of the body: turn the figure to it (the shortest way round) when that
		-- side is not facing the camera
		local face = FACING[def.id]
		if face and math.cos(s.yaw - face) < 0.5 then
			s.turnTo = s.yaw + ((face - s.yaw + math.pi) % (2 * math.pi) - math.pi)
		end
		s.idle = 0
		s.swayFrom = nil
		s.render()
	end
	-- step the groups (LB / RB)
	function s.step(dir)
		local i = 1
		for k, g in ipairs(GROUPS) do
			if g.id == s.group.id then
				i = k
			end
		end
		local def = GROUPS[(i - 1 + dir) % #GROUPS + 1]
		pickTab(def.name)
		s.setGroup(def)
	end
	s.setGroup(current)
	table.insert(s.conns, graphHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(s.redrawGraph)
	end))
	table.insert(s.conns, State.Changed:Connect(function()
		if screen == s and shade.Parent then
			s.render()
		end
	end))

	-- the history from the server (not in the summary); the graph fills in when it lands
	task.spawn(function()
		local ok, res = pcall(State.req, "GetMuscleHistory")
		if screen ~= s or not shade.Parent then
			return
		end
		s.history = (ok and type(res) == "table" and type(res.history) == "table") and res.history or {}
		s.xp = ok and type(res) == "table" and res.level or nil
		s.render()
	end)

	------------------------------------------------------------------ input: drag, right stick, keys
	local dragging, dragInput = false, nil
	table.insert(s.conns, vf.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging, dragInput = true, input
			s.idle = 0
		end
	end))
	table.insert(s.conns, UserInputService.InputChanged:Connect(function(input)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == dragInput)) then
			s.yaw += input.Delta.X * 0.012
			s.idle = 0
			s.updateCamera()
		elseif input.KeyCode == K.Thumbstick2 then
			local x = input.Position.X
			s.stick = math.abs(x) > 0.2 and x or 0
		end
	end))
	table.insert(s.conns, UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == dragInput) then
			dragging, dragInput = false, nil
		elseif input.KeyCode == K.Left or input.KeyCode == K.Right then
			s.keys = 0
		end
	end))
	table.insert(s.conns, UserInputService.InputBegan:Connect(function(input, processed)
		local k = input.KeyCode
		if (k == K.ButtonL1 or k == K.ButtonR1) and UI.PadTop() == win and not UserInputService:GetFocusedTextBox() then
			s.step(k == K.ButtonR1 and 1 or -1)
			local b = tabBar:FindFirstChild("Buttons") and tabBar.Buttons:FindFirstChild(string.upper(s.group.name))
			if b and UI.IsPad() then
				GuiService.SelectedObject = b
			end
		elseif (k == K.Left or k == K.Right) and not processed and not UserInputService:GetFocusedTextBox() then
			s.keys = k == K.Right and 1 or -1
		end
	end))
	-- per frame: the stick / keys turn the figure, the shells breathe, and after a pause it spins alone
	local t = 0
	table.insert(s.conns, RunService.RenderStepped:Connect(function(dt)
		if not figure then
			return
		end
		t += dt
		local turn = s.stick * 2.4 + s.keys * 1.8
		if turn ~= 0 or dragging then
			-- the player's hands on it: no auto turn
			s.turnTo, s.swayFrom = nil, nil
			s.yaw += turn * dt
			s.idle = 0
		elseif s.turnTo then
			local d = s.turnTo - s.yaw
			local step = TURN_SPEED * dt
			if math.abs(d) <= step then
				s.yaw, s.turnTo = s.turnTo, nil
			else
				s.yaw += step * math.sign(d)
			end
			s.idle = 0
		else
			s.idle += dt
			if s.idle > IDLE_BEFORE_SPIN then
				local face = FACING[s.group.id]
				if face then
					-- a one-sided group sways around its side (the shells stay in view)
					if not s.swayFrom then
						s.swayFrom = { yaw = s.yaw, t = s.idle }
					end
					local k = s.idle - s.swayFrom.t
					s.yaw = s.swayFrom.yaw + SWAY * math.sin(k * AUTO_SPIN / SWAY)
				else
					s.yaw += AUTO_SPIN * dt
				end
			end
		end
		s.updateCamera()
		local pulse = 0.46 + 0.14 * math.sin(t * 3)
		for _, p in ipairs(s.shells[s.group.id] or {}) do
			p.Transparency = pulse
		end
	end))
end

State.open.Muscle = MuscleScreen.Open
return MuscleScreen
