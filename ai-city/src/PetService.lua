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
-- 🍼 Pets start out as babies (big heads, short legs, tiny) and grow up:
--    Baby → Young → Adult. They grow while they're out with you (faster when
--    you're on the move together) and when you feed them a 🦴 treat from the
--    stand. Every pet grows to its own size: most end up somewhere between a
--    little smaller and a lot bigger than usual, and now and then one turns out
--    tiny or a GIANT. You only find out when it's all grown up.
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

-- growing up
PetService.GROWN = 180 -- growth points to become an adult (half of that: young)
PetService.TREAT = { Price = 10, Growth = 25 }
-- how big each kind can end up (times its usual size)
PetService.SIZES = {
	Dog = { 0.85, 1.35 }, Cat = { 0.8, 1.2 }, Hamster = { 0.8, 1.45 }, Fox = { 0.85, 1.3 },
	Duck = { 0.8, 1.3 }, Bunny = { 0.8, 1.45 }, Parrot = { 0.85, 1.25 }, GoldenPup = { 0.9, 1.5 },
}

PetService.KindName = { GoldenPup = "golden pup" }

local function stageOf(xp)
	if xp >= PetService.GROWN then
		return "Adult"
	elseif xp >= PetService.GROWN / 2 then
		return "Young"
	end
	return "Baby"
end
PetService.StageOf = stageOf

-- a new pet's details: its name, its (secret) adult size, no growth yet
local function newInfo(pd, id)
	pd.PetInfo = pd.PetInfo or {}
	local info = pd.PetInfo[id]
	if info then
		return info
	end
	local names = PetService.NAMES[id] or { "Buddy" }
	local range = PetService.SIZES[id] or { 0.85, 1.3 }
	local size = range[1] + math.random() * (range[2] - range[1])
	local roll = math.random()
	local kind = "normal"
	if roll < 0.05 then
		size, kind = size * 1.6, "giant"
	elseif roll < 0.1 then
		size, kind = size * 0.62, "tiny"
	end
	info = { Name = names[math.random(1, #names)], XP = 0, Size = math.floor(size * 100 + 0.5) / 100, Kind = kind }
	pd.PetInfo[id] = info
	return info
end
PetService.NewInfo = newInfo

local function sizeWord(info)
	if info.Kind == "giant" then
		return "a GIANT"
	elseif info.Kind == "tiny" then
		return "a teeny tiny"
	elseif info.Size >= 1.2 then
		return "a big"
	elseif info.Size <= 0.92 then
		return "a small"
	end
	return "a"
end

local function show(player)
	local pd = S.City.Data(player)
	local pet = pd and pd.Pet
	local info = pet and pd.PetInfo and pd.PetInfo[pet.Id]
	player:SetAttribute("Pet", pet and pet.Id or nil)
	player:SetAttribute("PetName", pet and pet.Name or nil)
	-- how grown up it is (0 = a baby, 1 = all grown up) and its adult size
	player:SetAttribute("PetGrowth", if info then math.clamp(info.XP / PetService.GROWN, 0, 1) else nil)
	player:SetAttribute("PetSize", if info then info.Size else nil)
	player:SetAttribute("PetStage", if info then stageOf(info.XP) else nil)
end
PetService.Show = show

-- growth points for the pet that's out: stage changes get a toast
function PetService.Grow(player, amount)
	local pd = S.City.Data(player)
	local pet = pd and pd.Pet
	if not pet then
		return nil
	end
	local info = newInfo(pd, pet.Id)
	local before = stageOf(info.XP)
	info.XP = math.min(PetService.GROWN, info.XP + amount)
	local after = stageOf(info.XP)
	show(player)
	if after ~= before then
		local kind = string.lower((PetService.KindName and PetService.KindName[pet.Id]) or pet.Id)
		if after == "Young" then
			S.City.Toast(player, "🌱", info.Name .. " is growing up!", "Not a baby anymore: " .. info.Name .. " is a young " .. kind .. " now.", rgb(120, 200, 120))
		else
			local word = sizeWord(info)
			S.City.Toast(player, "🎉", info.Name .. " is all grown up!", info.Name .. " turned out to be " .. word .. " " .. kind .. " (" .. info.Size .. "× the usual size)" .. (if info.Kind == "giant" then " — one in twenty!" elseif info.Kind == "tiny" then " — one in twenty, and adorable." else "."), rgb(250, 200, 60))
			S.City.News("🐾 " .. player.DisplayName .. "'s " .. kind .. " " .. info.Name .. " is all grown up" .. (if info.Kind == "giant" then " — and it's a GIANT!" else "!"), "City", true)
		end
	end
	return after
end

-- a treat from the stand: a big growth boost (and a happy pet)
function PetService.Treat(player)
	local pd = S.City.Data(player)
	if not pd or not pd.Pet then
		return { Ok = false, Error = "Take a pet out first (pick one at the stand)." }
	end
	local info = newInfo(pd, pd.Pet.Id)
	if info.XP >= PetService.GROWN then
		return { Ok = false, Error = info.Name .. " is all grown up already. Good pet!" }
	end
	if not S.City.Spend(player, PetService.TREAT.Price, "🦴 A treat for " .. info.Name) then
		return { Ok = false, Error = "A treat costs " .. PetService.TREAT.Price .. " coins." }
	end
	PetService.Grow(player, PetService.TREAT.Growth)
	player:SetAttribute("PetTreat", os.clock()) -- (hearts on everyone's screen)
	return { Ok = true }
end

function PetService.Equip(player, id)
	local pd = S.City.Data(player)
	if not pd then
		return false
	end
	if id == "none" then
		pd.Pet = nil
	elseif pd.Pets[id] then
		local info = newInfo(pd, id)
		pd.Pet = { Id = id, Name = info.Name }
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
	local function grown(id)
		local info = pd and pd.PetInfo and pd.PetInfo[id]
		if not info then
			return nil
		end
		local stage = stageOf(info.XP)
		local pct = math.floor(math.clamp(info.XP / PetService.GROWN, 0, 1) * 100)
		return info.Name .. " · " .. (if stage == "Adult" then "all grown up (" .. info.Size .. "× size)" else string.lower(stage) .. ", " .. pct .. "% grown")
	end
	for _, p in ipairs(PetService.ADOPT) do
		local owned = pd and pd.Pets[p.Id] == true
		table.insert(items, { Id = p.Id, Name = p.Name, Emoji = p.Emoji, Price = p.Price, Desc = if owned then grown(p.Id) or p.Desc else p.Desc .. " Comes as a baby and grows up.", Owned = owned, UseText = "🐾 Walk with me", Using = owned and pd.Pet and pd.Pet.Id == p.Id })
	end
	-- a treat for the pet that's out (it helps them grow)
	if pd and pd.Pet then
		local info = pd.PetInfo and pd.PetInfo[pd.Pet.Id]
		table.insert(items, 1, { Id = "treat", Name = "Pet treat", Emoji = "🦴", Price = PetService.TREAT.Price, Desc = "A treat for " .. pd.Pet.Name .. ": +" .. PetService.TREAT.Growth .. " growth." .. (if info then " (" .. math.floor(math.clamp(info.XP / PetService.GROWN, 0, 1) * 100) .. "% grown)" else ""), Owned = false })
	end
	-- prize pets you've won can be picked here too
	if S.Fun then
		for _, p in ipairs(S.Fun.PRIZES) do
			if p.Pet and pd and pd.Pets[p.Id] then
				table.insert(items, { Id = p.Id, Name = p.Name, Emoji = p.Emoji, Price = 0, Desc = grown(p.Id) or "A prize from the booth.", Owned = true, UseText = "🐾 Walk with me", Using = pd.Pet and pd.Pet.Id == p.Id })
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
	if id == "treat" then
		local r = PetService.Treat(player)
		if not r.Ok then
			return r
		end
		return { Ok = true, Store = store(player), Toast = { "🦴", pd.Pet.Name .. " loved that!", "" } }
	end
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
	return { Ok = true, Store = store(player), Toast = { pet.Emoji, "Meet " .. pd.Pet.Name .. "!", "Your new baby " .. string.lower(pet.Name) .. " follows you everywhere. Spend time together (and give treats) and watch it grow up." } }
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
	-- growing up: every 10 seconds out together (more on the move): about
	-- 15 minutes to grow up hanging out, 10 walking around, less with treats
	task.spawn(function()
		local last = {}
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local pd = S.City.Data(player)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if pd and pd.Pet and root then
					local moved = last[player] and (root.Position - last[player]).Magnitude > 20
					last[player] = root.Position
					pcall(PetService.Grow, player, if moved then 3 else 2)
				end
			end
		end
	end)
end

return PetService
