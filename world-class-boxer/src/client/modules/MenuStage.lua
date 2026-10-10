-- MenuStage: the main menu's set. A closed boxing-gym corner built on this client, far above the map,
-- so nothing replicates, every player gets the same shot and nothing in the world (NPCs, other players,
-- the gym's posts and pillars) can wander into frame:
--   * a ring with your corner behind you (red pad, ropes and ties), the canvas under your feet
--   * the gym beyond the ropes: brick walls, a club banner, old fight posters, heavy bags on chains,
--     hanging lamps, a high window with a shaft of light and dust in it, steel girders
--   * a CLONE of your character on the canvas. The Animator animates it (tag "Preview", Pose / Expr
--     attributes) and AnatomyClient dresses it like any other character; your real character stays
--     exactly where it is
-- MenuStage.Build() -> stage; MenuStage.Place(stage, char) -> clone; MenuStage.Step(stage, t) every
-- frame (swinging bags and lamp, breathing rim light); MenuStage.Shot(stage, view, t) -> camera CFrame,
-- field of view, focus distance; MenuStage.Destroy(stage).
local CollectionService = game:GetService("CollectionService")

local MenuStage = {}
-- the set's floor point under the boxer's feet (well above anything the map builds)
MenuStage.Origin = Vector3.new(0, 1400, 0)

local A = CFrame.Angles
local CF = CFrame.new
local V3 = Vector3.new
local PI = math.pi

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local CANVAS_Y = 0 -- the canvas top is the floor under the boxer
local GYM_Y = -3.6 -- the gym floor outside the ring (apron height below the canvas)
local ROPE_X, ROPE_BACK, ROPE_FRONT = 10, -6, 14 -- rope lines: x = +-ROPE_X, z = ROPE_BACK .. ROPE_FRONT
local ROPE_H = { 4.5, 3.5, 2.5, 1.5 } -- above the canvas, top rope first
local ROPE_COLORS = { rgb(196, 30, 40), rgb(232, 232, 236), rgb(30, 70, 170), rgb(196, 30, 40) }

local function part(st, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = st.base * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = st.folder
	return p
end

-- a cylinder between two local points
local function rod(st, name, a, b, d, color, material)
	local mid = (a + b) / 2
	local dir = b - a
	local len = dir.Magnitude
	-- (a vertical rod needs another up vector for lookAt)
	local up = math.abs(dir.Unit.Y) > 0.99 and V3(0, 0, 1) or V3(0, 1, 0)
	return part(st, name, V3(len, d, d), CFrame.lookAt(mid, b, up) * A(0, PI / 2, 0), color, material, { Shape = Enum.PartType.Cylinder })
end

-- a sign / poster: one TextLabel (lines split by \n) on the part's front face (or face)
local function sign(p, text, fg, bg, bgT, font, face)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Sign"
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 1
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	t.BackgroundTransparency = bgT or 1
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = fg
	t.TextScaled = true
	t.Font = font or Enum.Font.Oswald
	t.Parent = sg
	sg.Parent = p
	return sg
end

local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

------------------------------------------------------------------------
-- The set
------------------------------------------------------------------------
local function buildRing(st)
	-- platform + canvas (the canvas top is y = 0)
	part(st, "RingPlatform", V3(25, 3.4, 25), CF(0, GYM_Y + 1.7, 4), rgb(16, 16, 20), Enum.Material.Fabric)
	local canvas = part(st, "Canvas", V3(25, 0.2, 25), CF(0, CANVAS_Y - 0.1, 4), rgb(178, 186, 198), Enum.Material.Fabric)
	canvas.CastShadow = false
	-- the ring logo printed on the canvas in front of the boxer (worn, low contrast)
	local logo = part(st, "CanvasLogo", V3(9, 0.02, 3.4), CF(0, CANVAS_Y + 0.011, 7), rgb(150, 30, 36), Enum.Material.Fabric, { Transparency = 0.5, CastShadow = false })
	sign(logo, "WCB", rgb(232, 210, 160), nil, 1, Enum.Font.Oswald, Enum.NormalId.Top)
	-- corner posts + pads: your red corner behind-left, the neutral white one behind-right
	local corners = {
		{ -ROPE_X, ROPE_BACK, rgb(176, 22, 32) }, { ROPE_X, ROPE_BACK, rgb(226, 226, 230) },
		{ -ROPE_X, ROPE_FRONT, rgb(226, 226, 230) }, { ROPE_X, ROPE_FRONT, rgb(28, 64, 164) },
	}
	for i, c in ipairs(corners) do
		local x, z = c[1], c[2]
		rod(st, "Post" .. i, V3(x, CANVAS_Y - 0.4, z), V3(x, CANVAS_Y + 5.4, z), 0.4, rgb(36, 36, 42), Enum.Material.Metal)
		-- the turnbuckle pad faces the ring centre
		local inward = V3(-math.sign(x), 0, -math.sign(z - 4)).Unit * 0.35
		local pad = rod(st, "Pad" .. i, V3(x, CANVAS_Y + 0.9, z) + inward, V3(x, CANVAS_Y + 5.1, z) + inward, 1.15, c[3], Enum.Material.SmoothPlastic)
		pad.Reflectance = 0.04
		rod(st, "PadCap" .. i, V3(x, CANVAS_Y + 5.1, z) + inward, V3(x, CANVAS_Y + 5.25, z) + inward, 1.0, rgb(24, 24, 28), Enum.Material.SmoothPlastic)
	end
	-- ropes on the three sides the camera sees (the front side is behind the lens)
	local sides = {
		{ V3(-ROPE_X, 0, ROPE_BACK), V3(ROPE_X, 0, ROPE_BACK) },
		{ V3(-ROPE_X, 0, ROPE_BACK), V3(-ROPE_X, 0, ROPE_FRONT) },
		{ V3(ROPE_X, 0, ROPE_BACK), V3(ROPE_X, 0, ROPE_FRONT) },
	}
	for s, side in ipairs(sides) do
		for i, h in ipairs(ROPE_H) do
			local y = V3(0, CANVAS_Y + h, 0)
			local r = rod(st, "Rope", side[1] + y, side[2] + y, 0.26, ROPE_COLORS[i], Enum.Material.SmoothPlastic)
			r.Reflectance = 0.06
		end
		-- the rope ties: two white straps per side holding the ropes together
		for _, f in ipairs({ 0.33, 0.67 }) do
			local p = side[1]:Lerp(side[2], f)
			part(st, "RopeTie" .. s, V3(0.16, ROPE_H[1] - ROPE_H[4] + 0.3, 0.16), CF(p.X, CANVAS_Y + (ROPE_H[1] + ROPE_H[4]) / 2, p.Z), rgb(238, 238, 240), Enum.Material.Fabric)
		end
	end
	-- the corner stool (folded in, ready for the bell)
	local sx, sz = -ROPE_X + 1.6, ROPE_BACK + 1.6
	part(st, "StoolSeat", V3(1.5, 0.22, 1.5), CF(sx, CANVAS_Y + 1.5, sz), rgb(92, 62, 38), Enum.Material.Wood)
	for _, o in ipairs({ { -0.55, -0.55 }, { 0.55, -0.55 }, { -0.55, 0.55 }, { 0.55, 0.55 } }) do
		part(st, "StoolLeg", V3(0.14, 1.4, 0.14), CF(sx + o[1], CANVAS_Y + 0.7, sz + o[2]), rgb(40, 40, 44), Enum.Material.Metal)
	end
end

local function buildGym(st)
	local floorY = GYM_Y
	part(st, "Floor", V3(84, 1, 84), CF(0, floorY - 0.5, 0), rgb(70, 48, 32), Enum.Material.WoodPlanks)
	local wallH = 30
	local brick, brickDark = rgb(96, 42, 33), rgb(78, 34, 28)
	part(st, "BackWall", V3(84, wallH, 1), CF(0, floorY + wallH / 2, -30.5), brick, Enum.Material.Brick)
	part(st, "LeftWall", V3(1, wallH, 84), CF(-34.5, floorY + wallH / 2, 0), brickDark, Enum.Material.Brick)
	part(st, "RightWall", V3(1, wallH, 84), CF(30.5, floorY + wallH / 2, 0), brickDark, Enum.Material.Brick)
	part(st, "FrontWall", V3(84, wallH, 1), CF(0, floorY + wallH / 2, 26.5), rgb(40, 34, 32), Enum.Material.Concrete)
	part(st, "Ceiling", V3(84, 1, 84), CF(0, floorY + wallH + 0.5, 0), rgb(26, 26, 30), Enum.Material.Concrete)
	-- a dark wainscot along the bottom of the walls (wear and grime)
	part(st, "Wainscot", V3(84, 3.2, 0.3), CF(0, floorY + 1.6, -29.9), rgb(34, 26, 24), Enum.Material.Concrete)
	part(st, "WainscotL", V3(0.3, 3.2, 84), CF(-33.9, floorY + 1.6, 0), rgb(34, 26, 24), Enum.Material.Concrete)
	-- steel girders under the roof
	for _, z in ipairs({ -22, -8, 6 }) do
		part(st, "Girder", V3(84, 1.4, 0.9), CF(0, floorY + wallH - 2.2, z), rgb(38, 40, 46), Enum.Material.Metal)
	end
	-- the club banner, high on the back wall
	-- (a sign's front face is its -Z side: turned around, it faces the room)
	local facing = A(0, PI, 0)
	local banner = part(st, "Banner", V3(30, 4.4, 0.2), CF(-6, floorY + 19.5, -29.85) * facing, rgb(120, 18, 26), Enum.Material.Fabric)
	sign(banner, "WORLD CLASS BOXING CLUB", rgb(244, 200, 90), nil, 1)
	local motto = part(st, "Motto", V3(22, 1.4, 0.2), CF(-6, floorY + 16.4, -29.85) * facing, rgb(20, 18, 18), Enum.Material.Fabric)
	sign(motto, "EST. 1987  -  DISCIPLINE BEATS TALENT", rgb(210, 200, 180), nil, 1)
	-- old fight posters, faded, on the back wall and the left wall
	local posters = {
		{ CF(-21, floorY + 8.5, -29.85) * facing, "FRIDAY NIGHT\nFIGHTS\nRIVERA vs KOVAC", rgb(214, 196, 150), rgb(120, 24, 24) },
		{ CF(-14.5, floorY + 8, -29.85) * facing, "CHAMPIONSHIP\nBOXING\nMADISON HALL", rgb(196, 54, 42), rgb(250, 232, 190) },
		{ CF(14, floorY + 8.5, -29.85) * facing, "THE RETURN\nSANTOS vs VEGA\n12 ROUNDS", rgb(236, 196, 70), rgb(30, 26, 22) },
		{ CF(-33.85, floorY + 9, -14) * A(0, -PI / 2, 0), "GOLDEN GLOVES\nCITY FINALS", rgb(40, 64, 120), rgb(240, 220, 170) },
	}
	for i, ps in ipairs(posters) do
		local p = part(st, "Poster" .. i, V3(4.6, 6.4, 0.08), ps[1], ps[3], Enum.Material.Fabric)
		sign(p, ps[2], ps[4], nil, 1, Enum.Font.Oswald)
		part(st, "PosterFrame" .. i, V3(5, 6.8, 0.06), ps[1] * CF(0, 0, 0.04), rgb(24, 20, 18), Enum.Material.Wood)
	end
	-- a high window (cold daylight) on the back wall with a shaft of light falling into the gym
	local wx = 7
	local win = part(st, "Window", V3(7, 9, 0.2), CF(wx, floorY + 15.5, -29.8), rgb(196, 214, 236), Enum.Material.Neon, { Transparency = 0.25, CastShadow = false })
	part(st, "WindowFrameH", V3(7.4, 0.4, 0.3), CF(wx, floorY + 15.5, -29.7), rgb(30, 30, 34), Enum.Material.Metal)
	part(st, "WindowFrameV", V3(0.4, 9.4, 0.3), CF(wx, floorY + 15.5, -29.7), rgb(30, 30, 34), Enum.Material.Metal)
	st.window = win
	-- (attachments are parented first: WorldPosition is relative to the part they sit on)
	local a0 = Instance.new("Attachment")
	a0.Name = "ShaftTop"
	a0.Parent = win
	a0.WorldPosition = (st.base * CF(wx, floorY + 15.5, -29.4)).Position
	local a1 = Instance.new("Attachment")
	a1.Name = "ShaftFloor"
	a1.Parent = win
	a1.WorldPosition = (st.base * CF(wx - 3, floorY + 0.2, -13)).Position
	local shaft = Instance.new("Beam")
	shaft.Name = "LightShaft"
	shaft.Attachment0, shaft.Attachment1 = a0, a1
	shaft.Width0, shaft.Width1 = 7, 12
	shaft.FaceCamera = true
	shaft.LightEmission = 0.8
	shaft.LightInfluence = 0
	shaft.Color = ColorSequence.new(rgb(214, 228, 255))
	shaft.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1) })
	shaft.Segments = 6
	shaft.Parent = win
	st.shaft = shaft
	light(win, "SpotLight", { Face = Enum.NormalId.Front, Angle = 60, Range = 34, Brightness = 1.6, Color = rgb(190, 210, 255), Shadows = true })
	-- dust drifting in the window light (skipped on low detail)
	if st.detail ~= "Low" then
		local dustAt = Instance.new("Attachment")
		dustAt.Name = "Dust"
		dustAt.Parent = win
		dustAt.WorldPosition = (st.base * CF(wx - 1.5, floorY + 8, -21)).Position
		light(dustAt, "ParticleEmitter", {
			Rate = 7, Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(0.15, 0.4), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(0.07), LightEmission = 1, Color = ColorSequence.new(rgb(255, 240, 214)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = V3(0, 0.03, 0), Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		pcall(function()
			dustAt.ParticleEmitter.Shape = Enum.ParticleEmitterShape.Box
		end)
	end
	-- heavy bags on chains (they swing a little: MenuStage.Step)
	st.bags = {}
	for i, b in ipairs({ { -19, -15, rgb(122, 22, 28), 0 }, { -25, -3, rgb(28, 28, 32), 1.7 }, { 21, -19, rgb(122, 22, 28), 3.1 } }) do
		local top = V3(b[1], floorY + wallH - 2.8, b[2])
		local bagTop = V3(b[1], floorY + 7.8, b[2])
		local chain = rod(st, "BagChain", top, bagTop, 0.12, rgb(70, 70, 76), Enum.Material.Metal)
		local bag = part(st, "HeavyBag", V3(5.6, 2.3, 2.3), CF(bagTop - V3(0, 2.9, 0)) * A(0, 0, PI / 2), b[3], Enum.Material.Leather, { Shape = Enum.PartType.Cylinder })
		local band = part(st, "BagBand", V3(0.5, 2.36, 2.36), CF(bagTop - V3(0, 0.9, 0)) * A(0, 0, PI / 2), rgb(20, 20, 22), Enum.Material.Leather, { Shape = Enum.PartType.Cylinder })
		table.insert(st.bags, { top = top, len = (top - bagTop).Magnitude, chain = chain, bag = bag, band = band, phase = b[4], i = i })
	end
	-- a speed-bag platform and a rack on the right wall (silhouettes for depth)
	part(st, "SpeedBoard", V3(0.6, 0.5, 4), CF(29.8, floorY + 8.5, -10), rgb(60, 40, 26), Enum.Material.Wood)
	part(st, "SpeedBag", V3(1, 1.4, 1), CF(29.2, floorY + 7.6, -10), rgb(150, 26, 30), Enum.Material.Leather, { Shape = Enum.PartType.Ball })
	part(st, "Rack", V3(1.2, 4, 7), CF(29.4, floorY + 2, 4), rgb(34, 34, 38), Enum.Material.Metal)
	for k = 0, 4 do
		part(st, "Plate", V3(0.5, 2.2, 2.2), CF(28.6, floorY + 2.6, 1.4 + k * 1.3) * A(0, 0, PI / 2), rgb(26, 26, 30), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
end

-- hanging lamps over the ring (warm pools on the canvas; one sways a little)
local function buildLamps(st)
	st.lamps = {}
	for i, l in ipairs({ { -4, 2.5 }, { 7, -1.5 } }) do
		local top = V3(l[1], GYM_Y + 29.6, l[2])
		local at = V3(l[1], CANVAS_Y + 14, l[2])
		local cord = rod(st, "LampCord", top, at, 0.1, rgb(20, 20, 22), Enum.Material.Metal)
		local shade = part(st, "LampShade", V3(1.4, 2.6, 2.6), CF(at) * A(0, 0, PI / 2), rgb(40, 58, 50), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		local bulb = part(st, "LampBulb", V3(0.8, 0.8, 0.8), CF(at - V3(0, 0.6, 0)), rgb(255, 226, 170), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CastShadow = false })
		local spot = light(bulb, "SpotLight", { Face = Enum.NormalId.Bottom, Angle = 74, Range = 24, Brightness = 2.4, Color = rgb(255, 212, 158), Shadows = true })
		table.insert(st.lamps, { top = top, len = (top - at).Magnitude, cord = cord, shade = shade, bulb = bulb, spot = spot, phase = i * 1.9 })
	end
end

-- key (warm, front-left, high), rim (gold, behind-right) and a cool fill near the lens, all on the boxer
local function buildLights(st)
	local function rig(name, pos, aim)
		local p = part(st, name, V3(0.2, 0.2, 0.2), CFrame.lookAt(pos, aim), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
		return p
	end
	local chest = V3(0, 4, 0)
	local key = rig("KeyLight", V3(-6, 10, 9), chest)
	st.key = light(key, "SpotLight", { Face = Enum.NormalId.Front, Angle = 46, Range = 26, Brightness = 2.6, Color = rgb(255, 230, 204), Shadows = true })
	local rim = rig("RimLight", V3(5, 10.5, -7), chest + V3(0, 1, 0))
	st.rim = light(rim, "SpotLight", { Face = Enum.NormalId.Front, Angle = 50, Range = 22, Brightness = 4.4, Color = rgb(255, 190, 110) })
	local rim2 = rig("RimLight2", V3(-7, 9, -6), chest + V3(0, 1, 0))
	light(rim2, "SpotLight", { Face = Enum.NormalId.Front, Angle = 44, Range = 20, Brightness = 2.2, Color = rgb(150, 180, 255) })
	local fill = rig("FillLight", V3(3, 4.5, 8), chest)
	light(fill, "PointLight", { Range = 13, Brightness = 0.45, Color = rgb(170, 196, 255) })
end

-- builds the set; detail = Settings graphics detail ("Low" skips the dust)
function MenuStage.Build(detail)
	local folder = Instance.new("Folder")
	folder.Name = "MenuStage"
	local st = { folder = folder, base = CF(MenuStage.Origin), detail = detail, clone = nil }
	st.mark = st.base * A(0, PI, 0) -- the boxer's feet, facing +Z (the lens side)
	buildRing(st)
	buildGym(st)
	buildLamps(st)
	buildLights(st)
	folder.Parent = workspace
	return st
end

------------------------------------------------------------------------
-- The boxer: a clone of your character
------------------------------------------------------------------------
local STRIP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, ProximityPrompt = true, ClickDetector = true, BillboardGui = true,
	AlignPosition = true, AlignOrientation = true, LinearVelocity = true, AngularVelocity = true, VectorForce = true, Torque = true }

function MenuStage.Place(st, char)
	if st.clone then
		st.clone:Destroy()
		st.clone = nil
	end
	local root0 = char and char:FindFirstChild("HumanoidRootPart")
	local hum0 = char and char:FindFirstChildOfClass("Humanoid")
	if not (root0 and hum0) then
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
	-- the generated anatomy meshes belong to the real character (their EditableMeshes die with its next
	-- rebuild): AnatomyClient builds the clone its own (tag "Preview" below), and until then, or when
	-- meshes are unavailable, the clone shows the round-1 parts
	local anatomy = clone:FindFirstChild("Anatomy")
	if anatomy and anatomy:IsA("Folder") then
		anatomy:Destroy()
	end
	for _, d in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do
			CollectionService:RemoveTag(d, tag)
		end
		if STRIP[d.ClassName] or d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("SurfaceGui") and d:GetAttribute("AnatomyHid") == true then
			-- a gui the live character's meshes hid (Enabled is copied, LocalTransparencyModifier is not):
			-- the copy starts with the round-1 look, which stays if AnatomyClient never builds this clone
			d.Enabled = true
			d:SetAttribute("AnatomyHid", nil)
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
			-- whatever the live character's camera / meshes hid stays the live character's business
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(clone)) do
		CollectionService:RemoveTag(clone, tag)
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then
		clone:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	pcall(function()
		hum.EvaluateStateMachine = false -- an anchored puppet: no falling / getting-up states
		hum.BreakJointsOnDeath = false
	end)
	-- the root stands on the canvas (a humanoid's root rides HipHeight + half its size above the floor);
	-- only the root is anchored, the limbs follow the Motor6Ds the Animator drives
	root.Anchored = true
	root.CFrame = st.mark * CF(0, hum0.HipHeight + root.Size.Y / 2, 0)
	clone.Name = "MenuBoxer"
	clone:SetAttribute("Expr", "confident")
	clone:SetAttribute("Pose", nil)
	clone:SetAttribute("Act", nil)
	clone:SetAttribute("Guard", nil)
	clone.Parent = st.folder
	-- the Animator gives a Preview rig the proud stance; AnatomyClient builds its meshes (LookData came along)
	CollectionService:AddTag(clone, "Preview")
	st.clone = clone
	st.root = root
	st.head = clone:FindFirstChild("Head")
	return clone
end

-- the boxer's chest point (world)
function MenuStage.Chest(st)
	local root = st.root
	if root and root.Parent then
		return root.Position + V3(0, 1.2, 0)
	end
	return (st.mark * CF(0, 4.2, 0)).Position
end

------------------------------------------------------------------------
-- Per frame: life in the set (no allocations beyond CFrame math)
------------------------------------------------------------------------
function MenuStage.Step(st, t)
	local base = st.base
	for _, b in ipairs(st.bags or {}) do
		-- a slow pendulum around the chain's top mount
		local ax = math.sin(t * 0.9 + b.phase) * 0.035
		local az = math.sin(t * 0.7 + b.phase * 1.3) * 0.025
		local pivot = base * CF(b.top) * A(ax, 0, az)
		b.chain.CFrame = pivot * CF(0, -b.len / 2, 0) * A(0, 0, PI / 2)
		local bagTop = pivot * CF(0, -b.len, 0)
		b.bag.CFrame = bagTop * CF(0, -2.9, 0) * A(0, 0, PI / 2)
		b.band.CFrame = bagTop * CF(0, -0.9, 0) * A(0, 0, PI / 2)
	end
	for _, l in ipairs(st.lamps or {}) do
		local sway = math.sin(t * 0.55 + l.phase) * 0.03
		local pivot = base * CF(l.top) * A(sway, 0, sway * 0.6)
		l.cord.CFrame = pivot * CF(0, -l.len / 2, 0) * A(0, 0, PI / 2)
		local at = pivot * CF(0, -l.len, 0)
		l.shade.CFrame = at * A(0, 0, PI / 2)
		l.bulb.CFrame = at * CF(0, -0.6, 0)
	end
	if st.rim then
		st.rim.Brightness = 4.2 + math.sin(t * 0.7) * 0.6
	end
end

------------------------------------------------------------------------
-- Camera shots per menu view: distance, side offset (+ = the boxer's left, the lens side x), height
-- above the chest, how far to the boxer's right (screen left) the lens aims, field of view, blur
------------------------------------------------------------------------
MenuStage.Shots = {
	home = { d = 9.6, side = 2.8, h = -0.2, aim = 2.1, fov = 40, blur = 0 },
	career = { d = 8.4, side = -2.4, h = 0.1, aim = -1.6, fov = 36, blur = 16 },
	rankings = { d = 11, side = 3.4, h = 0.4, aim = 3.0, fov = 42, blur = 18 },
	settings = { d = 10.5, side = 3.0, h = 0.3, aim = 2.6, fov = 42, blur = 18 },
	character = { d = 7.4, side = 2.2, h = -0.1, aim = 2.6, fov = 36, blur = 6 },
}

-- the camera for a view at time t: CFrame, field of view, focus distance (shake 0..1.5 scales the drift)
function MenuStage.Shot(st, view, t, shake)
	local shot = MenuStage.Shots[view] or MenuStage.Shots.home
	local chest = MenuStage.Chest(st)
	-- the slow dolly: an orbit that sways +-9 degrees, breathing in and out, plus a little handheld drift
	local sway = math.sin(t * 0.21) * 0.16
	local dir = V3(math.sin(sway), 0, math.cos(sway)) -- +Z is the lens side of the set
	local right = V3(dir.Z, 0, -dir.X) -- the boxer's left as seen from the lens
	local d = shot.d + math.sin(t * 0.13) * 0.6
	local k = shake or 1
	local hand = V3(math.sin(t * 1.3) * 0.03, math.sin(t * 0.9 + 1) * 0.025, 0) * k
	local pos = chest + dir * d + right * shot.side + V3(0, shot.h + math.sin(t * 0.17) * 0.15, 0)
	local aim = chest - right * shot.aim + V3(0, 0.35, 0)
	return CFrame.lookAt(pos, aim) * CF(hand), shot.fov, (pos - chest).Magnitude, shot.blur
end

function MenuStage.Destroy(st)
	if st and st.folder then
		st.folder:Destroy()
		st.folder = nil
	end
	if st then
		st.clone, st.root, st.head = nil, nil, nil
	end
end

return MenuStage
