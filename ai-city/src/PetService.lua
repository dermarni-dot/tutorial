-- PetService (ModuleScript) — ServerScriptService.Modules.PetService
-- Pets that follow you around.
--
--   🐾 Paws & Claws, the adoption stand at Funland: adopt a dog, a cat, a
--      hamster or a fox for coins.
--   🎟️ The prize booth: a rubber duck, a bunny, a parrot and a golden pup for
--      carnival tickets (see FunService).
--
-- The pet you pick walks at your heels, sits when you stop, wags its tail
-- (the parrot flies at your shoulder), and wears a name tag. You keep every
-- pet you've got and can switch between them at the stand. Some citizens walk
-- their dogs too.
--
-- The server only stores which pet is out (the player's "Pet" and "PetName"
-- attributes); every screen draws the pets itself (the client's Pets module).

local Players = game:GetService("Players")

local PetService = {}
local S

PetService.ADOPT = {
	{ Id = "Dog", Name = "Dog", Emoji = "🐕", Price = 150, Desc = "A loyal pup. Follows you everywhere and sits when you stop." },
	{ Id = "Cat", Name = "Cat", Emoji = "🐈", Price = 120, Desc = "Independent, but it'll come along. Swishes its tail." },
	{ Id = "Hamster", Name = "Hamster", Emoji = "🐹", Price = 60, Desc = "Tiny and speedy. Scurries to keep up." },
	{ Id = "Fox", Name = "Fox", Emoji = "🦊", Price = 300, Desc = "A clever red fox with a big bushy tail." },
}
PetService.NAMES = {
	Dog = { "Buddy", "Max", "Bella", "Rocky", "Daisy", "Biscuit" }, Cat = { "Luna", "Milo", "Whiskers", "Cleo", "Tiger" },
	Hamster = { "Nibbles", "Peanut", "Squeak" }, Fox = { "Rusty", "Ember", "Foxy" }, Duck = { "Quackers", "Sunny" },
	Bunny = { "Clover", "Thumper", "Snowball" }, Parrot = { "Kiwi", "Captain", "Mango" }, GoldenPup = { "Goldie", "Champ" },
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function show(player)
	local pd = S.City.Data(player)
	local pet = pd and pd.Pet
	player:SetAttribute("Pet", pet and pet.Id or nil)
	player:SetAttribute("PetName", pet and pet.Name or nil)
end

function PetService.Equip(player, id)
	local pd = S.City.Data(player)
	if not pd then
		return false
	end
	if id == "none" then
		pd.Pet = nil
	elseif pd.Pets[id] then
		local names = PetService.NAMES[id] or { "Buddy" }
		local keep = pd.Pet and pd.Pet.Id == id and pd.Pet.Name
		pd.Pet = { Id = id, Name = keep or pd.PetNames and pd.PetNames[id] or names[math.random(1, #names)] }
		pd.PetNames = pd.PetNames or {}
		pd.PetNames[id] = pd.Pet.Name
	else
		return false
	end
	show(player)
	return true
end

-- a new pet (bought or won): it's yours, and it comes out right away
function PetService.Give(player, id)
	local pd = S.City.Data(player)
	if not pd then
		return false
	end
	pd.Pets = pd.Pets or {}
	pd.Pets[id] = true
	return PetService.Equip(player, id)
end

local function store(player)
	local pd = S.City.Data(player)
	local items = {}
	for _, p in ipairs(PetService.ADOPT) do
		local owned = pd and pd.Pets[p.Id] == true
		table.insert(items, { Id = p.Id, Name = p.Name, Emoji = p.Emoji, Price = p.Price, Desc = p.Desc, Owned = owned, UseText = "🐾 Walk with me", Using = owned and pd.Pet and pd.Pet.Id == p.Id })
	end
	-- prize pets you've won can be picked here too
	if S.Fun then
		for _, p in ipairs(S.Fun.PRIZES) do
			if p.Pet and pd and pd.Pets[p.Id] then
				table.insert(items, { Id = p.Id, Name = p.Name, Emoji = p.Emoji, Price = 0, Desc = "A prize from the booth.", Owned = true, UseText = "🐾 Walk with me", Using = pd.Pet and pd.Pet.Id == p.Id })
			end
		end
	end
	table.insert(items, { Id = "none", Name = "Walk alone", Emoji = "🚶", Price = 0, Desc = "Your pets wait at home.", Owned = true, UseText = "Leave them home", Using = pd and pd.Pet == nil })
	return { Title = "Paws & Claws Adoption", Emoji = "🐾", Currency = "coins", Balance = S.City.Coins(player), Action = "Pet", BuyText = "Adopt", Items = items, Note = "Your pet follows you, sits when you stop and wears a name tag. Win more pets with tickets at the 🎟️ prize booth." }
end

function PetService.Request(player, data)
	local pd = S.City.Data(player)
	if not pd then
		return { Ok = false, Error = "Try again in a moment." }
	end
	local id = data.Id
	if data.Op == "use" or id == "none" then
		if id ~= "none" and not pd.Pets[id] then
			return { Ok = false, Error = "That's not your pet." }
		end
		PetService.Equip(player, id)
		return { Ok = true, Store = store(player), Toast = if id == "none" then { "🏠", "Your pets are at home", "" } else { "🐾", pd.Pet.Name .. " is with you", "" } }
	end
	local pet
	for _, p in ipairs(PetService.ADOPT) do
		if p.Id == id then
			pet = p
		end
	end
	if not pet then
		return { Ok = false, Error = "That pet isn't up for adoption." }
	end
	if pd.Pets[id] then
		return { Ok = false, Error = "You already have one." }
	end
	if not S.City.Spend(player, pet.Price, pet.Emoji .. " Adopted a " .. pet.Name) then
		return { Ok = false, Error = "You need " .. pet.Price .. " coins." }
	end
	PetService.Give(player, id)
	return { Ok = true, Store = store(player), Toast = { pet.Emoji, "Meet " .. pd.Pet.Name .. "!", "Your new " .. string.lower(pet.Name) .. " follows you everywhere." } }
end

function PetService.Store(player)
	return store(player)
end

function PetService.Start(services)
	S = services
	S.City.Handle("Pet", PetService.Request)
	local NS = S.Map and S.Map.NorthShore
	if NS and NS.PetDesk then
		local p = Instance.new("ProximityPrompt")
		p.ActionText = "Adopt a pet"
		p.ObjectText = "🐾 Paws & Claws"
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p.Parent = NS.PetDesk
		p.Triggered:Connect(function(player)
			local d = store(player)
			d.Type = "Store"
			S.City.Send(player, d)
		end)
		-- pets waiting for a home in the pens
		for k, pos in ipairs(NS.PetPens or {}) do
			local stand = Instance.new("Part")
			stand.Name = "PenPet"
			stand.Transparency = 1
			stand.Anchored, stand.CanCollide, stand.CanQuery = true, false, false
			stand.Size = Vector3.one
			stand.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
			stand:SetAttribute("Pet", ({ "Dog", "Cat", "Hamster" })[k] or "Dog")
			stand.Parent = NS.Model
			game:GetService("CollectionService"):AddTag(stand, "PetDisplay")
		end
	end
	local function hook(player)
		task.spawn(function()
			for _ = 1, 20 do
				if S.City.Data(player) then
					break
				end
				task.wait(0.5)
			end
			if S.City.Data(player) then
				show(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
end

return PetService
