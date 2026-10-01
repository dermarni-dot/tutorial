-- DisguiseService (ModuleScript) — ServerScriptService.Modules.DisguiseService
-- Hoodies, ski masks and disguise kits:
--   • buy them at the Clothing store (press E at the counter)
--   • wear them anytime: C (or 📱 Wardrobe). One top and one face item at a time.
--   • they show on your character: a hood and sleeves, a knit mask, or a hat,
--     dark glasses and a fake mustache
--   • a ski mask in the daytime makes people nervous
-- How they help you get away with things is in CrimeService (witnesses who
-- can't recognize you, police who can't spot you, changing your look).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Disguises = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Disguises"))

local DisguiseService = {}
local S

local NERVOUS_LINES = { "Why are they wearing a mask...?", "Uh oh. That looks like trouble.", "Is that a ski mask? It's not even cold!", "I'm keeping my eye on that one.", "Hold on to your wallet..." }
local COP_LINES = { "Take that mask off, pal.", "I've got my eye on you.", "Nice mask. Planning something?", "Don't try anything funny." }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- what a player is wearing, as a set { [id] = true }
local function worn(player)
	local pd = S.City.Data(player)
	local out = {}
	for _, id in pairs(pd and pd.Wearing or {}) do
		if Disguises.List[id] then
			out[id] = true
		end
	end
	return out
end

local function isNight()
	return Disguises.IsNight(S.City.Hour())
end

function DisguiseService.Worn(player)
	return worn(player)
end
function DisguiseService.Hidden(player)
	return Disguises.Hidden(worn(player), isNight())
end
function DisguiseService.Suspicious(player)
	return Disguises.Suspicious(worn(player), isNight())
end
function DisguiseService.Signature(player)
	return Disguises.Signature(worn(player))
end
function DisguiseService.Describe(player)
	return Disguises.Describe(worn(player))
end
function DisguiseService.FaceCovered(player)
	local pd = S.City.Data(player)
	return pd ~= nil and pd.Wearing ~= nil and pd.Wearing.Face ~= nil
end

--------------------------------------------------------------------------------
-- How it looks on your character
--------------------------------------------------------------------------------
local function part(folder, anchor, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = anchor.CFrame * cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = anchor, p
	weld.Parent = p
	p.Parent = folder
	return p
end

local HOODIE = rgb(46, 48, 58)
local KNIT = rgb(24, 24, 28)
local HAT = rgb(84, 62, 44)

-- How big the head LOOKS (classic heads are a (2,1,1) part with a head mesh
-- that looks about 1.25 studs across; R15 mesh heads look like their size)
local function headDims(head)
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Head then
		local m = math.min(head.Size.X, head.Size.Y, head.Size.Z)
		return Vector3.new(m * mesh.Scale.X, m * mesh.Scale.Y, m * mesh.Scale.Z)
	end
	return head.Size
end

-- a copy of the head's own shape, a bit bigger: fits any avatar's head
local function headShell(folder, head, name, grow, color)
	local shell
	if head:IsA("MeshPart") then
		shell = head:Clone()
		shell:ClearAllChildren()
		shell.Size = head.Size * grow
		shell.TextureID = ""
	else
		shell = Instance.new("Part")
		local mesh = head:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			shell.Size = head.Size
			local m = Instance.new("SpecialMesh")
			m.MeshType = mesh.MeshType
			m.MeshId = mesh.MeshId
			m.Scale = mesh.Scale * grow
			m.Parent = shell
		else
			shell.Size = head.Size * grow
		end
	end
	shell.Name = name
	shell.Color = color
	shell.Material = Enum.Material.Fabric
	shell.Anchored = false
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Massless = true
	shell.CastShadow = false
	shell.CFrame = head.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = head, shell
	weld.Parent = shell
	shell.Parent = folder
	return shell
end

local BUILD = {}
BUILD.Hoodie = function(folder, character, head)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso then
		local t = torso.Size
		part(folder, torso, "HoodieBody", t + Vector3.new(0.14, 0.08, 0.14), CFrame.new(0, 0.02, 0), HOODIE)
		part(folder, torso, "Pocket", Vector3.new(t.X * 0.6, t.Y * 0.22, 0.06), CFrame.new(0, -t.Y * 0.28, -t.Z / 2 - 0.08), rgb(38, 40, 48))
		for _, side in ipairs({ -1, 1 }) do
			part(folder, torso, "String", Vector3.new(0.06, t.Y * 0.3, 0.04), CFrame.new(side * 0.18, t.Y * 0.22, -t.Z / 2 - 0.09), rgb(220, 220, 225), Enum.Material.SmoothPlastic)
		end
	end
	for _, name in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" }) do
		local arm = character:FindFirstChild(name)
		if arm then
			part(folder, arm, "Sleeve", arm.Size + Vector3.new(0.1, 0.02, 0.1), CFrame.new(), HOODIE)
		end
	end
	-- the hood: top, back and sides, open at the front
	local h = headDims(head)
	local w, d = h.X * 1.1, h.Z * 1.1
	part(folder, head, "HoodTop", Vector3.new(w + 0.2, 0.2, d + 0.15), CFrame.new(0, h.Y * 0.55 + 0.08, 0.06), HOODIE)
	part(folder, head, "HoodBack", Vector3.new(w + 0.2, h.Y * 1.1 + 0.25, 0.2), CFrame.new(0, 0, d / 2 + 0.1), HOODIE)
	for _, side in ipairs({ -1, 1 }) do
		part(folder, head, "HoodSide", Vector3.new(0.18, h.Y * 1.1 + 0.2, d + 0.05), CFrame.new(side * (w / 2 + 0.09), 0, 0.04), HOODIE)
	end
end
BUILD.SkiMask = function(folder, character, head)
	local h = headDims(head)
	headShell(folder, head, "SkiMask", 1.1, KNIT)
	local front = -h.Z * 0.55 - 0.03
	-- the eye opening, and the eyes looking out of it
	part(folder, head, "EyeHole", Vector3.new(h.X * 0.62, h.Y * 0.2, 0.05), CFrame.new(0, h.Y * 0.1, front), head.Color, Enum.Material.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		part(folder, head, "Eye", Vector3.new(h.X * 0.11, h.X * 0.11, 0.04), CFrame.new(side * h.X * 0.15, h.Y * 0.1, front - 0.03), rgb(20, 20, 24), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	part(folder, head, "MouthHole", Vector3.new(h.X * 0.26, h.Y * 0.08, 0.05), CFrame.new(0, -h.Y * 0.24, front), rgb(90, 40, 40), Enum.Material.SmoothPlastic)
end
BUILD.Disguise = function(folder, character, head)
	local h = headDims(head)
	local w = h.X
	local front = -h.Z / 2 - 0.05
	local top = h.Y / 2
	-- a fedora
	part(folder, head, "HatBrim", Vector3.new(0.1, w * 1.5, w * 1.5), CFrame.new(0, top + 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), HAT, Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(folder, head, "HatCrown", Vector3.new(0.55, w * 0.98, w * 0.98), CFrame.new(0, top + 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), HAT, Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(folder, head, "HatBand", Vector3.new(0.14, w * 1.01, w * 1.01), CFrame.new(0, top + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(25, 25, 25), Enum.Material.Fabric, Enum.PartType.Cylinder)
	-- dark glasses
	for _, side in ipairs({ -1, 1 }) do
		part(folder, head, "Lens", Vector3.new(w * 0.28, h.Y * 0.18, 0.05), CFrame.new(side * w * 0.18, h.Y * 0.1, front), rgb(18, 18, 22), Enum.Material.Glass)
	end
	part(folder, head, "Bridge", Vector3.new(w * 0.1, 0.05, 0.05), CFrame.new(0, h.Y * 0.13, front), rgb(18, 18, 22), Enum.Material.Metal)
	-- a big fake mustache
	part(folder, head, "Mustache", Vector3.new(w * 0.42, h.Y * 0.1, 0.08), CFrame.new(0, -h.Y * 0.14, front - 0.02), rgb(60, 40, 28))
	for _, side in ipairs({ -1, 1 }) do
		part(folder, head, "MustacheTip", Vector3.new(w * 0.13, h.Y * 0.08, 0.07), CFrame.new(side * w * 0.25, -h.Y * 0.17, front - 0.02) * CFrame.Angles(0, 0, math.rad(side * -25)), rgb(60, 40, 28))
	end
end

--------------------------------------------------------------------------------
-- 👕 fashion
--------------------------------------------------------------------------------
local GOLD = rgb(245, 200, 70)
local WHITE = rgb(248, 248, 245)
local function torsoOf(character)
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end
local function sleeves(folder, character, color, material)
	for _, name in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" }) do
		local arm = character:FindFirstChild(name)
		if arm then
			part(folder, arm, "Sleeve", arm.Size + Vector3.new(0.1, 0.02, 0.1), CFrame.new(), color, material)
		end
	end
end
-- an open jacket: two front panels, the back, the sleeves
local function jacket(folder, character, color, material, inner)
	local torso = torsoOf(character)
	if not torso then
		return nil
	end
	local t = torso.Size
	for _, sx in ipairs({ -1, 1 }) do
		part(folder, torso, "JacketPanel", Vector3.new(t.X * 0.34, t.Y + 0.06, 0.1), CFrame.new(sx * t.X * 0.34, 0, -t.Z / 2 - 0.05), color, material)
		part(folder, torso, "JacketSide", Vector3.new(0.1, t.Y + 0.06, t.Z + 0.12), CFrame.new(sx * (t.X / 2 + 0.05), 0, 0), color, material)
		part(folder, torso, "Lapel", Vector3.new(0.16, t.Y * 0.42, 0.06), CFrame.new(sx * t.X * 0.2, t.Y * 0.26, -t.Z / 2 - 0.1) * CFrame.Angles(0, 0, sx * math.rad(20)), color:Lerp(rgb(0, 0, 0), 0.25), material)
	end
	part(folder, torso, "JacketBack", Vector3.new(t.X + 0.1, t.Y + 0.06, 0.1), CFrame.new(0, 0, t.Z / 2 + 0.05), color, material)
	if inner then
		part(folder, torso, "Shirt", Vector3.new(t.X * 0.3, t.Y, 0.06), CFrame.new(0, 0, -t.Z / 2 - 0.02), inner, Enum.Material.SmoothPlastic)
	end
	sleeves(folder, character, color, material)
	return torso, t
end
local FASHION = {}
FASHION.LeatherJacket = function(f, ch, head, c)
	local torso, t = jacket(f, ch, c, Enum.Material.Leather, rgb(240, 240, 236))
	if torso then
		part(f, torso, "Zip", Vector3.new(0.05, t.Y * 0.9, 0.04), CFrame.new(-t.X * 0.17, 0, -t.Z / 2 - 0.12), rgb(200, 205, 215), Enum.Material.Metal)
	end
end
FASHION.DenimJacket = function(f, ch, head, c)
	local torso, t = jacket(f, ch, c, Enum.Material.Fabric, rgb(250, 250, 248))
	if torso then
		for _, sx in ipairs({ -1, 1 }) do
			part(f, torso, "Pocket", Vector3.new(t.X * 0.2, t.Y * 0.16, 0.04), CFrame.new(sx * t.X * 0.32, t.Y * 0.2, -t.Z / 2 - 0.12), c:Lerp(rgb(0, 0, 0), 0.18))
		end
	end
end
FASHION.VarsityJacket = function(f, ch, head, c)
	local torso, t = jacket(f, ch, c, Enum.Material.Fabric, rgb(30, 30, 34))
	sleeves(f, ch, WHITE, Enum.Material.Leather)
	if torso then
		part(f, torso, "Letter", Vector3.new(t.X * 0.2, t.X * 0.2, 0.05), CFrame.new(t.X * 0.3, t.Y * 0.18, -t.Z / 2 - 0.12), WHITE)
	end
end
FASHION.PufferJacket = function(f, ch, head, c)
	local torso = torsoOf(ch)
	if torso then
		local t = torso.Size
		part(f, torso, "Puffer", t + Vector3.new(0.3, 0.1, 0.3), CFrame.new(), c, Enum.Material.SmoothPlastic)
		for k = -1, 1 do
			part(f, torso, "PufferRidge", Vector3.new(t.X + 0.36, 0.08, t.Z + 0.36), CFrame.new(0, k * t.Y * 0.3, 0), c:Lerp(rgb(0, 0, 0), 0.15), Enum.Material.SmoothPlastic)
		end
		part(f, torso, "Collar", Vector3.new(t.X * 0.8, 0.3, t.Z + 0.4), CFrame.new(0, t.Y / 2 + 0.1, 0), c, Enum.Material.SmoothPlastic)
	end
	sleeves(f, ch, c, Enum.Material.SmoothPlastic)
end
FASHION.Tracksuit = function(f, ch, head, c)
	local torso = torsoOf(ch)
	if torso then
		local t = torso.Size
		part(f, torso, "Track", t + Vector3.new(0.12, 0.06, 0.12), CFrame.new(), c)
		part(f, torso, "Zip", Vector3.new(0.05, t.Y * 0.95, 0.04), CFrame.new(0, 0, -t.Z / 2 - 0.08), WHITE, Enum.Material.SmoothPlastic)
	end
	sleeves(f, ch, c)
	for _, name in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg" }) do
		local limb = ch:FindFirstChild(name)
		if limb then
			if name:find("Leg") then
				part(f, limb, "TrackLeg", limb.Size + Vector3.new(0.08, 0.01, 0.08), CFrame.new(), c)
			end
			local side = if name:find("Left") then -1 else 1
			part(f, limb, "TrackStripe", Vector3.new(0.08, limb.Size.Y, 0.2), CFrame.new(side * (limb.Size.X / 2 + 0.07), 0, 0), WHITE)
		end
	end
end
FASHION.Tuxedo = function(f, ch, head, c)
	local torso, t = jacket(f, ch, c, Enum.Material.Fabric, WHITE)
	if torso then
		part(f, torso, "BowTie", Vector3.new(0.5, 0.2, 0.1), CFrame.new(0, t.Y * 0.4, -t.Z / 2 - 0.1), rgb(20, 20, 22))
		part(f, torso, "Flower", Vector3.new(0.2, 0.2, 0.08), CFrame.new(-t.X * 0.3, t.Y * 0.25, -t.Z / 2 - 0.13), rgb(220, 40, 60), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end
local function hatBase(head)
	local h = headDims(head)
	return h, h.X, h.Y / 2
end
FASHION.Cap = function(f, ch, head, c)
	local h, w, top = hatBase(head)
	part(f, head, "CapCrown", Vector3.new(w * 1.06, h.Y * 0.32, h.Z * 1.08), CFrame.new(0, top - h.Y * 0.02, 0.02), c)
	part(f, head, "CapBrim", Vector3.new(w * 0.9, 0.08, h.Z * 0.5), CFrame.new(0, top - h.Y * 0.15, -h.Z * 0.7), c:Lerp(rgb(0, 0, 0), 0.15))
end
FASHION.Beanie = function(f, ch, head, c)
	local h, w, top = hatBase(head)
	part(f, head, "Beanie", Vector3.new(w * 1.08, h.Y * 0.42, h.Z * 1.1), CFrame.new(0, top - h.Y * 0.06, 0.02), c)
	part(f, head, "BeanieCuff", Vector3.new(w * 1.12, h.Y * 0.12, h.Z * 1.14), CFrame.new(0, top - h.Y * 0.24, 0.02), c:Lerp(rgb(0, 0, 0), 0.15))
	part(f, head, "PomPom", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, top + h.Y * 0.2, 0), WHITE, Enum.Material.Fabric, Enum.PartType.Ball)
end
FASHION.CowboyHat = function(f, ch, head, c)
	local h, w, top = hatBase(head)
	part(f, head, "HatBrim", Vector3.new(0.1, w * 1.9, w * 1.7), CFrame.new(0, top + 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Leather, Enum.PartType.Cylinder)
	part(f, head, "HatCrown", Vector3.new(w * 0.95, 0.75, h.Z * 0.95), CFrame.new(0, top + 0.4, 0), c, Enum.Material.Leather)
	part(f, head, "HatBand", Vector3.new(w * 0.97, 0.14, h.Z * 0.97), CFrame.new(0, top + 0.12, 0), rgb(40, 30, 24), Enum.Material.Leather)
end
FASHION.BucketHat = function(f, ch, head, c)
	local h, w, top = hatBase(head)
	part(f, head, "HatBrim", Vector3.new(0.1, w * 1.45, w * 1.45), CFrame.new(0, top - 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(f, head, "HatCrown", Vector3.new(0.5, w * 1.04, w * 1.04), CFrame.new(0, top + 0.18, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Fabric, Enum.PartType.Cylinder)
end
FASHION.Crown = function(f, ch, head, c)
	local h, w, top = hatBase(head)
	part(f, head, "CrownBand", Vector3.new(0.4, w * 0.95, w * 0.95), CFrame.new(0, top + 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Metal, Enum.PartType.Cylinder)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		part(f, head, "CrownPoint", Vector3.new(0.18, 0.4, 0.18), CFrame.new(math.cos(a) * w * 0.42, top + 0.5, math.sin(a) * w * 0.42), c, Enum.Material.Metal)
		part(f, head, "CrownJewel", Vector3.new(0.15, 0.15, 0.15), CFrame.new(math.cos(a) * w * 0.48, top + 0.15, math.sin(a) * w * 0.48), ({ rgb(220, 30, 60), rgb(40, 120, 230), rgb(40, 200, 120) })[k % 3 + 1], Enum.Material.Neon, Enum.PartType.Ball)
	end
end
local function glasses(f, head, lens, frameColor, heart)
	local h = headDims(head)
	local w = h.X
	local front = -h.Z / 2 - 0.05
	for _, side in ipairs({ -1, 1 }) do
		local l = part(f, head, "Lens", Vector3.new(w * 0.3, h.Y * (if heart then 0.24 else 0.18), 0.05), CFrame.new(side * w * 0.19, h.Y * 0.1, front) * (if heart then CFrame.Angles(0, 0, math.rad(side * 12)) else CFrame.new()), lens, Enum.Material.Glass)
		l.Transparency = 0.1
		part(f, head, "Arm", Vector3.new(0.04, 0.04, h.Z * 0.9), CFrame.new(side * w * 0.36, h.Y * 0.12, 0), frameColor, Enum.Material.SmoothPlastic)
	end
	part(f, head, "Bridge", Vector3.new(w * 0.1, 0.05, 0.05), CFrame.new(0, h.Y * 0.14, front), frameColor, Enum.Material.Metal)
end
FASHION.Sunglasses = function(f, ch, head, c)
	glasses(f, head, c, rgb(20, 20, 22))
end
FASHION.HeartGlasses = function(f, ch, head, c)
	glasses(f, head, c, rgb(250, 120, 170), true)
end
FASHION.GoldChain = function(f, ch, head, c)
	local torso = torsoOf(ch)
	if torso then
		local t = torso.Size
		for k = -3, 3 do
			local a = k / 3 * 0.9
			part(f, torso, "Chain", Vector3.new(0.14, 0.14, 0.14), CFrame.new(math.sin(a) * t.X * 0.26, t.Y * 0.5 - (1 - math.cos(a)) * t.Y * 0.6 - 0.05, -t.Z / 2 - 0.08), c, Enum.Material.Metal, Enum.PartType.Ball)
		end
		part(f, torso, "Pendant", Vector3.new(0.3, 0.36, 0.08), CFrame.new(0, t.Y * 0.5 - t.Y * 0.3, -t.Z / 2 - 0.1), c, Enum.Material.Metal)
	end
end
FASHION.Scarf = function(f, ch, head, c)
	local torso = torsoOf(ch)
	if torso then
		local t = torso.Size
		part(f, torso, "Scarf", Vector3.new(t.X * 0.78, 0.4, t.Z + 0.3), CFrame.new(0, t.Y / 2 - 0.05, 0), c)
		for k = 0, 2 do
			part(f, torso, "ScarfEnd", Vector3.new(0.5, 0.36, 0.1), CFrame.new(t.X * 0.22, t.Y * 0.28 - k * 0.38, -t.Z / 2 - 0.1), if k % 2 == 0 then c else WHITE)
		end
	end
end
FASHION.Headphones = function(f, ch, head, c)
	local h = headDims(head)
	part(f, head, "Band", Vector3.new(h.X * 1.1, 0.14, 0.2), CFrame.new(0, h.Y * 0.55, 0), c, Enum.Material.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		part(f, head, "EarCup", Vector3.new(0.18, 0.55, 0.55), CFrame.new(side * (h.X / 2 + 0.08), 0, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
end

-- hats and hair get in the way of hoods and masks: hide them while you wear one
local function setAccessories(character, hide)
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle then
				if hide then
					if handle:GetAttribute("DisguiseSaved") == nil then
						handle:SetAttribute("DisguiseSaved", handle.Transparency)
					end
					handle.Transparency = 1
				elseif handle:GetAttribute("DisguiseSaved") ~= nil then
					handle.Transparency = handle:GetAttribute("DisguiseSaved")
					handle:SetAttribute("DisguiseSaved", nil)
				end
			end
		end
	end
end

local function dress(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = character:FindFirstChild("Disguise")
	if old then
		old:Destroy()
	end
	local set = worn(player)
	local folder = Instance.new("Folder")
	folder.Name = "Disguise"
	for id in pairs(set) do
		local d = Disguises.List[id]
		if BUILD[id] then
			BUILD[id](folder, character, head)
		elseif FASHION[id] and d then
			-- (the disguise kit's hat and glasses win over a hat or shades; no
			-- hat over a hood or a ski mask)
			local covered = (d.Slot == "Hat" and (set.Disguise or set.SkiMask or set.Hoodie)) or (d.Slot == "Eyes" and (set.Disguise or set.SkiMask))
			if not covered then
				pcall(FASHION[id], folder, character, head, d.Color)
			end
		end
	end
	folder.Parent = character
	local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
	if face then
		if set.SkiMask then
			if face:GetAttribute("DisguiseSaved") == nil then
				face:SetAttribute("DisguiseSaved", face.Transparency)
			end
			face.Transparency = 1
		elseif face:GetAttribute("DisguiseSaved") ~= nil then
			face.Transparency = face:GetAttribute("DisguiseSaved")
			face:SetAttribute("DisguiseSaved", nil)
		end
	end
	-- (your own hats and hair hide under a hood, a mask, a disguise or a hat)
	local hideHats = set.Hoodie or set.SkiMask or set.Disguise
	for id in pairs(set) do
		local d = Disguises.List[id]
		if d and d.Slot == "Hat" then
			hideHats = true
		end
	end
	setAccessories(character, hideHats == true)
	player:SetAttribute("Disguise", Disguises.Describe(set))
end

local function refresh(player)
	local set = worn(player)
	local night = isNight()
	local hidden = Disguises.Hidden(set, night)
	player:SetAttribute("Hidden", if hidden > 0.001 then math.floor(hidden * 100 + 0.5) / 100 else nil)
	player:SetAttribute("Suspicious", if Disguises.Suspicious(set, night) > 0 then true else nil)
	player:SetAttribute("Night", night)
end

--------------------------------------------------------------------------------
-- Wardrobe and shop
--------------------------------------------------------------------------------
local function wardrobe(player, atStore)
	local pd = S.City.Data(player)
	local set = worn(player)
	local items = {}
	for _, id in ipairs(Disguises.Order) do
		local d = Disguises.List[id]
		table.insert(items, {
			Id = id, Name = d.Name, Emoji = d.Emoji, Slot = d.Slot, Price = d.Price, Desc = d.Desc,
			Hidden = d.Hidden, Night = d.Night, Suspicious = d.Suspicious, Fashion = d.Fashion, Color = d.Color,
			Owned = pd ~= nil and pd.Outfits ~= nil and pd.Outfits[id] == true,
			Wearing = set[id] == true,
		})
	end
	return { Ok = true, Items = items, Store = atStore == true, Coins = S.City.Coins(player), Hidden = Disguises.Hidden(set, isNight()), Night = isNight() }
end

local function wear(player, data)
	local pd = S.City.Data(player)
	local d = Disguises.List[data.Id or ""]
	if not pd or not d then
		return { Ok = false }
	end
	if not (pd.Outfits and pd.Outfits[data.Id]) then
		return { Ok = false, Error = "You don't have a " .. d.Name .. ". Get one at the 👕 Clothing store." }
	end
	if S.Crime and S.Crime.IsHiding(player) then
		return { Ok = false, Error = "Not while you're hiding." }
	end
	pd.Wearing = pd.Wearing or {}
	if data.On == false or (data.On == nil and pd.Wearing[d.Slot] == data.Id) then
		pd.Wearing[d.Slot] = nil
	else
		pd.Wearing[d.Slot] = data.Id
	end
	dress(player)
	refresh(player)
	local r = wardrobe(player, data.Store)
	r.Text = if pd.Wearing[d.Slot] == data.Id then d.Emoji .. " You put on the " .. d.Name .. "." else "You took off the " .. d.Name .. "."
	return r
end

local function buy(player, data)
	local pd = S.City.Data(player)
	local d = Disguises.List[data.Id or ""]
	if not pd or not d then
		return { Ok = false, Error = "That's not for sale." }
	end
	pd.Outfits = pd.Outfits or {}
	if pd.Outfits[data.Id] then
		return { Ok = false, Error = "You already have one." }
	end
	if S.Crime and S.Crime.IsJailed(player) then
		return { Ok = false, Error = "Not from jail!" }
	end
	if not S.City.Spend(player, d.Price, d.Emoji .. " Bought a " .. d.Name) then
		return { Ok = false, Error = "You need " .. d.Price .. " coins." }
	end
	pd.Outfits[data.Id] = true
	return wear(player, { Id = data.Id, On = true, Store = true })
end

-- The police take your ski mask when they arrest you
function DisguiseService.Confiscate(player)
	local pd = S.City.Data(player)
	if not pd or not pd.Outfits or not pd.Outfits.SkiMask then
		return
	end
	pd.Outfits.SkiMask = nil
	if pd.Wearing and pd.Wearing.Face == "SkiMask" then
		pd.Wearing.Face = nil
	end
	dress(player)
	refresh(player)
	S.City.Toast(player, "🥷", "Mask confiscated", "The police took your ski mask.", rgb(230, 60, 60))
end

local function addStore(store, at, label)
	if not at and not store then
		return
	end
	local counter = Instance.new("Part")
	counter.Name = "DisguiseShop"
	counter.Anchored = true
	counter.CanCollide = false
	counter.CanQuery = false
	counter.Transparency = 1
	counter.Size = Vector3.new(2, 2, 2)
	counter.CFrame = CFrame.new((at or store.Inside or store.Door) + Vector3.new(0, 3, 0))
	counter.Parent = store and store.Model or workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Shop clothes, hats & disguises"
	prompt.ObjectText = label or "👕 Clothing store"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Shop")
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		local data = wardrobe(player, true)
		data.Type = "Wardrobe"
		S.City.Send(player, data)
	end)
end

--------------------------------------------------------------------------------
-- A ski mask in the daytime makes people nervous
--------------------------------------------------------------------------------
local lastLine = {}
local function suspicionTick()
	for _, player in ipairs(Players:GetPlayers()) do
		refresh(player)
		-- (re)dress anyone whose outfit isn't on yet (their save loaded after they spawned)
		if player.Character and player.Character:FindFirstChild("Head") and not player.Character:FindFirstChild("Disguise") and next(worn(player)) ~= nil then
			dress(player)
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		-- people notice a good outfit
		if root and not player:GetAttribute("Suspicious") and os.clock() - (lastLine[player] or 0) > 25 and math.random() < 0.12 then
			local best
			for id in pairs(worn(player)) do
				local d = Disguises.List[id]
				if d and d.Fashion and (not best or d.Price > best.Price) then
					best = d
				end
			end
			if best then
				for _, brain in ipairs(S.Citizens.Nearby(root.Position, 16)) do
					if brain.State ~= "ko" and brain.State ~= "hospital" and brain.State ~= "talk" and brain.State ~= "police" and brain.Model:GetAttribute("Action") ~= "sleep" then
						local line = if best.Price >= 150 then ({ "Whoa, is that a real " .. best.Name:lower() .. "?!", "Look at you! Fancy!", "Okay, big spender!" })[math.random(1, 3)]
							else ({ "Love the " .. best.Name:lower() .. "!", "Nice " .. best.Name:lower() .. "!", "Ooh, where'd you get that?", "Looking sharp!" })[math.random(1, 4)]
						S.Citizens.Say(brain, line, "happy", 2.5)
						lastLine[player] = os.clock()
						break
					end
				end
			end
		end
		if root and player:GetAttribute("Suspicious") and not (S.Crime and S.Crime.IsHiding(player)) and os.clock() - (lastLine[player] or 0) > 6 then
			for _, brain in ipairs(S.Citizens.Nearby(root.Position, 22)) do
				if brain.State ~= "ko" and brain.State ~= "hospital" and brain.State ~= "talk" and brain.State ~= "police" and brain.Model:GetAttribute("Action") ~= "sleep" and math.random() < 0.15 then
					local job = brain.C.Job
					local cop = job == "Police Officer" or job == "Night Officer" or job == "SWAT Officer"
					local lines = if cop then COP_LINES else NERVOUS_LINES
					S.Citizens.Say(brain, lines[math.random(1, #lines)], if cop then "focused" else "scared", 2.5)
					lastLine[player] = os.clock()
					break
				end
			end
		end
	end
end

function DisguiseService.Start(services)
	S = services
	S.City.Handle("Wardrobe", function(player, data)
		return wardrobe(player, data and data.Store)
	end)
	S.City.Handle("Wear", wear)
	S.City.Handle("BuyOutfit", buy)
	addStore(S.Map.Places.Mall)
	if S.Map.Places.Boutique then
		addStore(S.Map.Places.Boutique, nil, "👗 Trendy Threads")
	end
	-- the Beach Boutique on the sand (see NorthShore)
	if S.Map.Boutique then
		addStore(S.Map.Places.Beach, S.Map.Boutique, "👕 Beach Boutique")
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local head = character:WaitForChild("Head", 10)
			if head then
				task.wait(0.5) -- let the avatar's hats and face load
				dress(player)
				-- hats that load later get hidden too
				character.ChildAdded:Connect(function(child)
					local w = worn(player)
					local hat = w.Hoodie or w.SkiMask or w.Disguise
					for id in pairs(w) do
						if Disguises.List[id].Slot == "Hat" then
							hat = true
						end
					end
					if child:IsA("Accessory") and hat then
						task.wait()
						setAccessories(character, true)
					end
				end)
			end
		end)
		if player.Character then
			task.spawn(dress, player)
		end
		refresh(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastLine[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			suspicionTick()
		end
	end)
end

return DisguiseService
