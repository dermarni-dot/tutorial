-- Poser: puts a character (player or NPC) at a training spot in the right posture
-- (standing, seated or lying, matched to the equipment height) and attaches
-- held equipment props (barbells, dumbbells, rope handles, mitts...).
-- The joint animation itself runs client-side (Animator) from the "Pose" attribute.
local Poser = {}

local V3 = Vector3.new
local CF = CFrame.new

local function attPos(part, name)
	local a = part and part:FindFirstChild(name)
	return a and a:IsA("Attachment") and a.Position or nil
end

-- height of the Root joint and of the hip joints relative to the HumanoidRootPart centre
function Poser.JointOffsets(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local lt = model:FindFirstChild("LowerTorso")
	local rootAtt = attPos(root, "RootRigAttachment") or V3(0, -0.2, 0)
	local ltRoot = attPos(lt, "RootRigAttachment") or V3(0, 0.2, 0)
	local ltHip = attPos(lt, "RightHipRigAttachment") or V3(0.5, -0.2, 0)
	local lowerTorsoCenter = rootAtt - ltRoot
	return rootAtt.Y, (lowerTorsoCenter + ltHip).Y
end

-- info = { floor = y of the floor, stand = extra platform height, seat = seat height, lie = surface height }
function Poser.Place(model, x, z, yaw, info)
	info = info or {}
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then
		return
	end
	local floor = info.floor or 0.5
	local rootJointY, hipY = Poser.JointOffsets(model)
	local y
	if info.seat then
		local thigh = model:FindFirstChild("RightUpperLeg")
		local half = thigh and thigh.Size.Z / 2 or 0.5
		y = floor + info.seat + half - hipY
	elseif info.lie then
		local ut = model:FindFirstChild("UpperTorso")
		local half = ut and ut.Size.Z / 2 or 0.5
		y = floor + info.lie + half - rootJointY
	else
		y = floor + (info.stand or 0) + hum.HipHeight + root.Size.Y / 2
	end
	root.Anchored = true
	model:PivotTo(CF(x, y, z) * CFrame.Angles(0, yaw or 0, 0))
	root.AssemblyLinearVelocity = Vector3.zero
end

------------------------------------------------------------------------
-- Held props
------------------------------------------------------------------------
local function propFolder(model)
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		look = Instance.new("Folder")
		look.Name = "BoxerLook"
		look.Parent = model
	end
	local f = look:FindFirstChild("Held")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Held"
		f.Parent = look
	end
	return f
end

local function mk(folder, anchor, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = p
	w.Parent = p
	p.Parent = folder
	return p
end

local STEEL = Color3.fromRGB(190, 192, 198)
local IRON = Color3.fromRGB(45, 45, 50)

-- a bar along the anchor's local X axis centred at `center` (CFrame), with plates on both ends
local function barbell(folder, anchor, center, length, plateR, plates, plateColor)
	mk(folder, anchor, "Bar", V3(length, 0.22, 0.22), center * CFrame.Angles(0, 0, 0), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	for side = -1, 1, 2 do
		for i = 1, plates do
			local x = side * (length / 2 - 0.5 - (i - 1) * 0.32)
			local r = plateR * (1 - (i - 1) * 0.12)
			mk(folder, anchor, "Plate", V3(0.28, r * 2, r * 2), center * CF(x, 0, 0), plateColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
		mk(folder, anchor, "Collar", V3(0.18, 0.4, 0.4), center * CF(side * (length / 2 - 0.5 - plates * 0.32 + 0.05), 0, 0), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
end

local function dumbbell(folder, hand, level)
	local c = hand.CFrame * CF(0, -0.15, 0)
	local head = level >= 3 and STEEL or IRON
	mk(folder, hand, "Handle", V3(1.0, 0.18, 0.18), c, STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	for side = -1, 1, 2 do
		mk(folder, hand, "DBHead", V3(0.42, 0.62 + level * 0.05, 0.62 + level * 0.05), c * CF(side * 0.62, 0, 0), head, level >= 3 and Enum.Material.Metal or Enum.Material.SmoothPlastic)
	end
end

function Poser.ClearProps(model)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild("Held")
	if f then
		f:Destroy()
	end
end

-- level = equipment level (heavier / shinier gear at higher levels)
function Poser.AttachProps(model, pose, level)
	Poser.ClearProps(model)
	level = level or 1
	local rh, lh = model:FindFirstChild("RightHand"), model:FindFirstChild("LeftHand")
	local ut = model:FindFirstChild("UpperTorso")
	local ua = model:FindFirstChild("RightUpperArm")
	if not (rh and lh and ut) then
		return
	end
	local folder = propFolder(model)
	local sep = ut.Size.X + (ua and ua.Size.X or 1) -- distance between the hands along the body's X axis
	local plateColors = { Color3.fromRGB(40, 40, 44), Color3.fromRGB(40, 40, 44), Color3.fromRGB(30, 60, 160), Color3.fromRGB(190, 30, 35) }
	local plateColor = plateColors[math.clamp(level, 1, 4)]
	if pose == "bench" then
		barbell(folder, rh, rh.CFrame * CF(-sep / 2, -0.12, 0), 6.6, 0.85 + level * 0.08, math.min(3, level), plateColor)
	elseif pose == "deadlift" then
		barbell(folder, rh, rh.CFrame * CF(-sep / 2, -0.12, 0), 7, 1.25, math.min(3, level), plateColor)
	elseif pose == "squat" then
		local c = ut.CFrame * CF(0, ut.Size.Y * 0.42, ut.Size.Z * 0.62)
		barbell(folder, ut, c, 7, 1.0 + level * 0.06, math.min(3, level), plateColor)
	elseif pose == "curl" then
		dumbbell(folder, rh, level)
		dumbbell(folder, lh, level)
	elseif pose == "rope" then
		for _, hand in ipairs({ rh, lh }) do
			mk(folder, hand, "RopeHandle", V3(0.75, 0.2, 0.2), hand.CFrame * CF(0, -0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
				level >= 3 and Color3.fromRGB(230, 180, 30) or Color3.fromRGB(30, 30, 35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
	elseif pose == "row" then
		mk(folder, rh, "RowHandle", V3(sep + 0.8, 0.2, 0.2), rh.CFrame * CF(-sep / 2, -0.12, 0), Color3.fromRGB(30, 30, 35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	elseif pose == "mitts" then
		for _, hand in ipairs({ rh, lh }) do
			local c = hand.CFrame * CF(0, -0.2, -0.25)
			mk(folder, hand, "Mitt", V3(0.5, 1.25, 1.1), c, Color3.fromRGB(180, 20, 25), Enum.Material.Leather)
			mk(folder, hand, "MittTarget", V3(0.08, 0.6, 0.6), c * CF(0, 0, -0.56) * CFrame.Angles(0, math.rad(90), 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
	elseif pose == "clippers" then
		mk(folder, rh, "Clippers", V3(0.3, 0.7, 0.25), rh.CFrame * CF(0, -0.45, 0), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic)
	end
end

return Poser
