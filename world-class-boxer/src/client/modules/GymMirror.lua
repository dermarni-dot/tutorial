-- GymMirror: a live mirror at the shadow-boxing station. While you are within a few strides of
-- it, a ViewportFrame on the glass shows a copy of YOUR character reflected across the glass
-- plane, seen from your own camera, so you watch your stance and punches the way a real gym
-- mirror shows them (left stays left). Every part of the copy follows the real one each frame
-- (no physics, no Motor6D: positions and rotations are mirrored directly), so anything the
-- Animator, the face rig or hair physics does shows up. Outside the range it is torn down.
-- Limits: a ViewportFrame cannot do an off-axis (window) projection, so the picture is exact
-- when you stand in front of the mirror and slightly skewed at steep angles; asymmetric meshes
-- are not mirrored inside out (none of the boxer's parts depend on that).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local GymMirror = {}
local player = Players.LocalPlayer

local RANGE = 18 -- studs from the glass
local RATE = 1 / 30
local REBUILD_GAP = 1.5 -- seconds between re-copies when the character was rebuilt

local getMirror
local started = false
local disabled = false
local st = {} -- active state: mirror, sg, vp, cam, char, pairs = { {orig, copy, hidden} }, builtAt

local function teardown()
	if st.sg then
		st.sg:Destroy()
	end
	st = {}
end

-- AnatomyClient (the organic EditableMesh characters), required lazily: nil without the module
local anatomy
local anatomyLoaded = false
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

-- every anatomy rebuild destroys the old EditableMeshes, so a copy made before it draws nothing:
-- the mirror re-copies (st.dirty) after a rebuild / restore of YOUR character, like FighterCard
local anatomyHooked = false
local function hookAnatomy()
	if anatomyHooked then
		return
	end
	anatomyHooked = true
	task.spawn(function()
		local ac = anatomyClient()
		if not ac then
			return
		end
		for _, sig in ipairs({ ac.OnBuilt, ac.OnRestored }) do
			if type(sig) == "table" and type(sig.Connect) == "function" then
				pcall(function()
					sig:Connect(function(model)
						if model == player.Character and st.char == model then
							st.dirty = true
						end
					end)
				end)
			end
		end
	end)
end

-- does a copied anatomy MeshPart still show its mesh? Its geometry is an EditableMesh referenced
-- through MeshContent (Content.fromObject): a copy that lost the reference would draw nothing
local function meshCarried(mp)
	local ok, has = pcall(function()
		local c = mp.MeshContent
		return c ~= nil and c.Object ~= nil
	end)
	return ok and has == true
end

-- the copied anatomy meshes (clone.Anatomy): kept when every piece still carries its mesh, else
-- removed so the reflection falls back to the round-1 parts (true = the organic look is in the copy)
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

-- is this original a round-1 part an anatomy mesh replaced (hidden on the live character)?
local function replacedByMesh(orig, isReplaced)
	if not isReplaced then
		return false
	end
	local ok, r = pcall(isReplaced, orig)
	return ok and r == true
end

-- the camera's own fade (first person / close zoom): Roblox's TransparencyController writes
-- LocalTransparencyModifier on every part of the character, the HumanoidRootPart included, which no
-- anatomy rule ever hides; the camera within 2 studs of its focus is the same state seen from it.
-- While it lasts an anatomy piece's LocalTransparencyModifier says nothing about headgear / a hood
-- covering it (every piece reads 1), and a mirror still shows you
local function cameraFading(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.LocalTransparencyModifier > 0 then
		return true
	end
	local cam = workspace.CurrentCamera
	return cam ~= nil and cam.CameraType ~= Enum.CameraType.Scriptable and (cam.Focus.Position - cam.CFrame.Position).Magnitude < 2
end

-- copy the character once; pairs map every original BasePart to its copy
local function copyCharacter(char, parent)
	local list = {}
	for i, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetAttribute("MirrorId", i)
			list[i] = d
		end
	end
	local ok, clone = pcall(function()
		local was = char.Archivable
		char.Archivable = true
		local c = char:Clone()
		char.Archivable = was
		return c
	end)
	if not ok or not clone then
		return nil, nil
	end
	-- strip every CollectionService tag (Clone copies them): the copy is posed by this module
	-- alone; FaceFX / HairFX / BodyFX / the Animator / GymVisuals must not pick it up by tag
	local function stripTags(inst)
		for _, tg in ipairs(CollectionService:GetTags(inst)) do
			CollectionService:RemoveTag(inst, tg)
		end
	end
	stripTags(clone)
	-- what the meshes hide on the live character stays hidden in the glass when the meshes came
	-- along; without them the round-1 parts show (the same rule as FighterCard's photos)
	local meshes = keepMeshes(clone)
	local ac = anatomyClient()
	local isReplaced = meshes and ac and ac.IsReplaced or nil
	local pieces = meshes and char:FindFirstChild("Anatomy") or nil
	local fade = cameraFading(char)
	local pairsOut = {}
	for _, d in ipairs(clone:GetDescendants()) do
		stripTags(d)
		-- scripts, sounds and effects go; joints too, because every part is placed directly
		local junk = d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("BillboardGui")
			or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("JointInstance") or d:IsA("WeldConstraint")
		if junk then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			local orig = list[d:GetAttribute("MirrorId") or -1]
			if orig then
				-- { orig, copy, replaced (fixed per copy), anatomy piece, covered (read live in update) }
				local replaced = replacedByMesh(orig, isReplaced)
				local piece = pieces ~= nil and orig:IsA("MeshPart") and orig:IsDescendantOf(pieces)
				local covered = piece and not fade and orig.LocalTransparencyModifier >= 0.99
				if replaced or covered then
					d.Transparency = 1
				end
				table.insert(pairsOut, { orig, d, replaced, piece, covered })
			end
		elseif (d:IsA("SurfaceGui") or d:IsA("BillboardGui")) and d:GetAttribute("AnatomyHid") == true then
			-- Enabled is copied: false while the live meshes hide the gui; back on without them
			d.Enabled = not meshes
			d:SetAttribute("AnatomyHid", nil)
		elseif d:IsA("Decal") and meshes and isReplaced then
			-- a decal draws even on a transparent part: hide it with the part (or itself) it was replaced on
			local origPart = d.Parent and list[d.Parent:GetAttribute("MirrorId") or -1]
			local origDecal = origPart and origPart:FindFirstChild(d.Name)
			local okP, rp = pcall(isReplaced, origPart)
			local okD, rd = pcall(isReplaced, origDecal)
			if (okP and rp == true) or (okD and rd == true) then
				d.Transparency = 1
			end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone.Parent = parent
	return clone, pairsOut
end

-- reflect a CFrame across the plane through c with unit normal n (a proper rotation: one local
-- axis is flipped so the result is still right-handed, which mirrors symmetric parts exactly)
local function reflect(cf, c, n)
	local p = cf.Position
	local function sw(v)
		return v - 2 * v:Dot(n) * n
	end
	local pos = p - 2 * (p - c):Dot(n) * n
	return CFrame.fromMatrix(pos, sw(-cf.RightVector), sw(cf.UpVector), sw(-cf.LookVector))
end

local function activate(mirror, char)
	teardown()
	local sg = Instance.new("SurfaceGui")
	sg.Name = "LiveMirror"
	sg.Face = Enum.NormalId.Back -- the glass faces the boxer (+Z of the station)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.ClipsDescendants = true
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundColor3 = Color3.fromRGB(58, 52, 48)
	vp.Ambient = Color3.fromRGB(150, 142, 132)
	vp.LightColor = Color3.fromRGB(255, 238, 214)
	vp.LightDirection = Vector3.new(0.2, -1, 0.35)
	vp.ImageTransparency = 0.04
	vp.Parent = sg
	-- a slight silver sheen over the picture so it still reads as glass
	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = Color3.fromRGB(210, 225, 240)
	sheen.BackgroundTransparency = 0.9
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 2
	sheen.Parent = sg
	local world = vp
	pcall(function()
		local wm = Instance.new("WorldModel")
		wm.Parent = vp
		world = wm
	end)
	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam
	-- the room behind you, reflected: the gym floor and a far wall
	local n = -mirror.CFrame.LookVector
	local c = mirror.Position
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(60, 0.4, 60)
	floor.Color = Color3.fromRGB(46, 48, 56)
	floor.Material = Enum.Material.Rubber
	local floorY = mirror.Position.Y - mirror.Size.Y / 2 - 1 + 0.3
	floor.CFrame = CFrame.new(c.X, floorY, c.Z) + n * -20
	floor.Parent = world
	local back = Instance.new("Part")
	back.Anchored = true
	back.Size = Vector3.new(80, 30, 1)
	back.Color = Color3.fromRGB(122, 66, 52)
	back.Material = Enum.Material.Brick
	back.CFrame = CFrame.lookAt(c - n * 45 + Vector3.new(0, 10, 0), c)
	back.Parent = world
	sg.Parent = mirror
	local _, list = copyCharacter(char, world)
	st = { mirror = mirror, sg = sg, vp = vp, cam = cam, char = char, pairs = list or {}, builtAt = os.clock(), n = n, c = c }
end

local function update()
	local cam = workspace.CurrentCamera
	if not (cam and st.cam) then
		return
	end
	local n, c = st.n, st.c
	local dirty = false
	local fade = cameraFading(st.char)
	for _, pr in ipairs(st.pairs) do
		local orig, copy = pr[1], pr[2]
		if orig.Parent then
			copy.CFrame = reflect(orig.CFrame, c, n)
			-- (a mirror still shows you in first person) a mesh piece under headgear / a hood stays
			-- hidden: read live, except during the camera's fade, which keeps the last state seen
			if pr[4] and not fade then
				pr[5] = orig.LocalTransparencyModifier >= 0.99
			end
			copy.Transparency = (pr[3] or pr[5]) and 1 or orig.Transparency
		else
			dirty = true
			copy.Transparency = 1
		end
	end
	-- look through the glass from where you actually are
	local p = cam.CFrame.Position
	local dist = math.max(1, (p - c).Magnitude)
	st.cam.CFrame = CFrame.lookAt(p, c)
	local h = st.mirror.Size.Y
	st.cam.FieldOfView = math.clamp(math.deg(2 * math.atan((h / 2) / dist)), 8, 90)
	return dirty
end

function GymMirror.Start(getter)
	getMirror = getter
	if started then
		return
	end
	started = true
	hookAnatomy()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if disabled then
			return
		end
		acc += dt
		if acc < RATE then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			local mirror = getMirror and getMirror()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not (mirror and mirror.Parent and root) or (root.Position - mirror.Position).Magnitude > RANGE then
				if st.sg then
					teardown()
				end
				return
			end
			if st.mirror ~= mirror or st.char ~= char or not (st.sg and st.sg.Parent) or (st.dirty and os.clock() - (st.builtAt or 0) > REBUILD_GAP) then
				activate(mirror, char)
			end
			st.dirty = update() or st.dirty
		end)
		if not ok then
			warn("[GymMirror]", err)
			teardown()
			disabled = true -- stop quietly; the glass keeps its plain reflectance
		end
	end)
end

return GymMirror
