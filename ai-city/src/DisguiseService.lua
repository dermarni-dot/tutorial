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
		if BUILD[id] then
			BUILD[id](folder, character, head)
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
	setAccessories(character, next(set) ~= nil)
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
			Hidden = d.Hidden, Night = d.Night, Suspicious = d.Suspicious,
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

local function addStore()
	local store = S.Map.Places.Mall
	if not store then
		return
	end
	local counter = Instance.new("Part")
	counter.Name = "DisguiseShop"
	counter.Anchored = true
	counter.CanCollide = false
	counter.CanQuery = false
	counter.Transparency = 1
	counter.Size = Vector3.new(2, 2, 2)
	counter.CFrame = CFrame.new((store.Inside or store.Door) + Vector3.new(0, 3, 0))
	counter.Parent = store.Model or workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Hoodies, masks & disguises"
	prompt.ObjectText = "👕 Clothing store"
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
	addStore()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local head = character:WaitForChild("Head", 10)
			if head then
				task.wait(0.5) -- let the avatar's hats and face load
				dress(player)
				-- hats that load later get hidden too
				character.ChildAdded:Connect(function(child)
					if child:IsA("Accessory") and next(worn(player)) ~= nil then
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
