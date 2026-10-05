-- CityStores: the counters of the city's walk-in shops (prompts in CityMap, dispatched through
-- CityVisuals.Prompt). Iron Supplements and the diners sell real meals through the Eat request
-- (same effects as the gym's nutrition bar), the Pro Shop and Prestige Motors open the gear / car
-- catalogues, the Hall of Fame shows the legends and your place among them, and the Elite
-- Performance Center front desk explains what your facility tier unlocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local CityStores = {}
local shade

local function close()
	State.windows.Store = nil
	if shade then
		shade:Destroy()
		shade = nil
	end
end

local function money(n)
	return Config.Money(n)
end

-- what each counter sells (Config.Meals ids) and how the shop names them
local MENUS = {
	Supplements = {
		title = "IRON SUPPLEMENTS", blurb = "Built in the gym. Fueled by Iron. Shakes and plans that turn training into muscle.",
		items = { { id = "Protein", name = "Iron Whey Protein Shake" }, { id = "SportsDrink", name = "Electrolyte Drink" },
			{ id = "Athlete", name = "Athlete Meal Plan (daily)" }, { id = "Chef", name = "Personal Chef Feast" } },
	},
	Diner = {
		title = "CHAMP'S DINER", blurb = "Fighters eat here. Balance the plate before camp - the burger can wait until after the weigh-in.",
		items = { { id = "Balanced", name = "Grilled Chicken & Rice Plate" }, { id = "FastFood", name = "The Champ Burger (cheat meal)" },
			{ id = "SportsDrink", name = "Fresh Lemonade" } },
	},
	Pizza = {
		title = "TONY'S PIZZA", blurb = "A slice of champions since 1972. Tony still asks every fighter about their next fight.",
		items = { { id = "FastFood", name = "Pepperoni Slice (cheat meal)" }, { id = "Balanced", name = "Grilled Veggie Pizza" },
			{ id = "SportsDrink", name = "Soda" } },
	},
}

local function mealFx(meal)
	local fx = {}
	if meal.nutrition ~= 0 then
		table.insert(fx, string.format("%+d nutrition", meal.nutrition))
	end
	if meal.hydration ~= 0 then
		table.insert(fx, string.format("%+d hydration", meal.hydration))
	end
	if meal.energy ~= 0 then
		table.insert(fx, string.format("%+d energy", meal.energy))
	end
	if meal.fat ~= 0 then
		table.insert(fx, meal.fat > 0 and "adds body fat" or "lean")
	end
	if meal.gainsBuff then
		table.insert(fx, string.format("+%d%% training gains today", meal.gainsBuff * 100))
	end
	if meal.muscleBuff then
		table.insert(fx, string.format("+%d%% muscle growth today", meal.muscleBuff * 100))
	end
	return table.concat(fx, "  -  ")
end

local function renderMenu(body, menu)
	local P = State.P
	UI.Clear(body)
	local head = UI.Card(body)
	UI.Line(head, menu.blurb, { TextSize = 13, TextColor3 = T.sub })
	UI.Line(head, string.format("Money %s   -   Nutrition %d   Hydration %d   Energy %d", money(P.money), P.condition.nutrition, P.condition.hydration, P.condition.energy), { TextSize = 13, Font = T.semi })
	for _, it in ipairs(menu.items) do
		local meal = Config.FindById(Config.Meals, it.id)
		if meal then
			local locked = meal.requires and not (P.owned and P.owned[meal.requires])
			local c = UI.Card(body)
			UI.Line(c, string.format("%s  -  %s", it.name, meal.price > 0 and money(meal.price) or "free"), { Font = T.bold })
			UI.Line(c, mealFx(meal), { TextSize = 13, TextColor3 = T.sub })
			UI.Button(c, locked and "NEEDS NUTRITIONIST" or "BUY", { Size = UDim2.new(0, 170, 0, 30), TextSize = 14, BackgroundColor3 = locked and T.panel2 or T.gold, TextColor3 = locked and T.sub or T.bg }, function()
				if locked then
					return
				end
				local r = State.req("Eat", meal.id)
				if r.ok then
					State.toast(it.name .. ": nutrition " .. math.floor((r.info and r.info.nutrition) or 0), T.green)
				else
					State.toast(r.err or "Can't buy that", T.red)
				end
			end)
		end
	end
end

local function openWindow(title, w, h)
	State.closeAll("Store")
	local s, _, body = UI.Window(State.gui, "Store", w or 560, h or 600, title, { onClose = close })
	shade = s
	State.windows.Store = close
	return body
end

local function hub(tab)
	close()
	if State.open.Hub then
		State.open.Hub(tab)
	end
end

local function food(kind)
	local menu = MENUS[kind] or MENUS.Diner
	local body = openWindow(menu.title)
	local mine = shade
	renderMenu(body, menu)
	-- live numbers while the window is open (every purchase pushes a new profile)
	local conn
	conn = State.Changed:Connect(function()
		if shade == mine and mine.Parent then
			renderMenu(body, menu)
		else
			conn:Disconnect()
		end
	end)
end

local function proShop()
	local P = State.P
	local body = openWindow("WCB PRO SHOP", 600, 620)
	UI.Line(body, "Every brand on the wall. Your gloves, boots and wraps change your stats and how you look in the ring.", { TextSize = 13, TextColor3 = T.sub })
	UI.Button(body, "SHOP GLOVES, BOOTS & WRAPS", { Size = UDim2.new(0, 300, 0, 38), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		hub("Gear")
	end)
	local eq = P.gear and P.gear.equipped or {}
	for _, id in ipairs(Catalog.BrandOrder) do
		local b = Catalog.Brand(id)
		local c = UI.Card(body)
		local line = b.name .. "  (" .. tostring(b.tier) .. ")"
		local wearing = {}
		for _, kind in ipairs({ "gloves", "shoes", "wraps" }) do
			local ok, gb = pcall(Catalog.GearBrand, kind, eq[kind], P.appearance and P.appearance.gloves and P.appearance.gloves.brand)
			if ok and gb and gb.id == id then
				table.insert(wearing, kind)
			end
		end
		UI.Line(c, line .. (#wearing > 0 and ("  -  YOU WEAR: " .. table.concat(wearing, ", ")) or ""), { Font = T.bold, TextColor3 = #wearing > 0 and T.gold or T.text })
		UI.Line(c, tostring(b.desc or ""), { TextSize = 12, TextColor3 = T.sub })
	end
end

local function motors()
	local P = State.P
	local body = openWindow("PRESTIGE MOTORS", 560, 560)
	UI.Line(body, "Drive like a champion. Your best car takes the reserved bay outside the gym and parks at your home.", { TextSize = 13, TextColor3 = T.sub })
	UI.Line(body, "Money " .. money(P.money), { Font = T.bold, TextColor3 = T.green })
	for _, item in ipairs(Catalog.Shop) do
		if item.cat == "Cars" then
			local owned = P.owned and P.owned[item.id]
			local c = UI.Card(body, { stroke = owned and T.gold or nil })
			UI.Line(c, item.name, { Font = T.bold })
			UI.Line(c, item.desc, { TextSize = 13, TextColor3 = T.sub })
			UI.Button(c, owned and "IN YOUR GARAGE" or money(item.price), { Size = UDim2.new(0, 200, 0, 32), TextSize = 14,
				BackgroundColor3 = owned and T.panel2 or (P.money >= item.price and T.gold or Color3.fromRGB(70, 40, 40)), TextColor3 = owned and T.text or T.bg }, function()
				if owned then
					return
				end
				local r = State.req("Buy", item.id)
				if r.ok then
					State.toast("The keys are yours: " .. item.name, T.green)
					close()
				else
					State.toast(r.err or "Can't buy that", T.red)
				end
			end)
		end
	end
end

local function museum()
	local P = State.P
	local body = openWindow("BOXING HALL OF FAME", 560, 620)
	local lg = P.legacy or {}
	local c = UI.Card(body, { stroke = T.gold })
	UI.Line(c, lg.hof and "INDUCTED: " .. P.identity.name:upper() or "YOUR EXHIBIT", { Font = T.bold, TextColor3 = T.gold, TextSize = 18 })
	UI.Line(c, string.format("Legacy %d  -  all-time rank #%d  -  Hall of Fame needs %d", lg.score or 0, lg.goatRank or 0, Config.HallOfFameScore), { TextSize = 14 })
	UI.Line(c, (P.titlesWon or 0) > 0 and "Your title belts have a case in the great room." or "Win a world title and the museum gives you a case next to the legends.", { TextSize = 13, TextColor3 = T.sub })
	UI.Button(c, "FULL LEGACY", { Size = UDim2.new(0, 200, 0, 34), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		hub("Legacy")
	end)
	UI.Header(body, "THE LEGENDS")
	for i, e in ipairs(Config.Legends) do
		if i > 12 then
			break
		end
		UI.Line(body, string.format("%d. %s  -  legacy %d", i, e.name, e.score), { TextSize = 14 })
	end
end

-- what still stands between this gym and the ELITE tier (the summary's needs only cover the next tier
-- up); a lower tier's line is kept only when Elite has none of its kind (e.g. a waived career rank)
local function eliteNeeds(P, frac)
	local list, kinds = {}, {}
	for i = 3, 2, -1 do
		local def = Config.GymTiers and Config.GymTiers[i]
		local ok, needs = pcall(Catalog.GymTierNeeds, def, tonumber(frac) or 0, P.owned, P.tier)
		for _, n in ipairs(ok and type(needs) == "table" and needs or {}) do
			local kind = tostring(n):match("^%a+") or n
			if i == 3 or not kinds[kind] then
				kinds[kind] = true
				table.insert(list, n)
			end
		end
	end
	return list
end

local function eliteCenter()
	local P = State.P
	local gt = P.gymTier or {}
	local idx = gt.index or 1
	-- exact progress (the summary's gt.frac is rounded to 2 places, which can round 54.5% up past 55%)
	local frac = tonumber(gt.frac) or 0
	if P.gym and type(P.gym.levels) == "table" then
		local ok, f = pcall(Catalog.GymProgress, P.gym.levels)
		frac = ok and tonumber(f) or frac
	end
	local body = openWindow("WCB ELITE PERFORMANCE CENTER", 560, 560)
	if idx >= 3 then
		UI.Line(body, "Welcome back. Cryotherapy, hot and cold plunge pools, the sports science lab and the motion capture studio are yours.", { TextSize = 14 })
	else
		UI.Line(body, "Members only. The center opens to fighters whose own gym reaches the Elite tier.", { TextSize = 14, TextColor3 = T.orange })
		for _, n in ipairs(eliteNeeds(P, frac)) do
			UI.Line(body, "  - " .. n, { TextSize = 13, TextColor3 = T.sub })
		end
	end
	UI.Line(body, string.format("Your facility: %s (%d%%)", tostring(gt.name or "Beginner Gym"), math.floor(frac * 100)), { Font = T.semi })
	UI.Button(body, "FACILITY & EQUIPMENT", { Size = UDim2.new(0, 260, 0, 36), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		hub("Gym")
	end)
	UI.Button(body, "TRAINING", { Size = UDim2.new(0, 260, 0, 36) }, function()
		hub("Training")
	end)
end

-- kind = the prompt's Action; store = its Store attribute (shop sign text)
function CityStores.Open(kind, store)
	local P = State.P
	if not (P and P.created) or P.retired or State.inFight() then
		return false
	end
	if kind == "Supplements" then
		food("Supplements")
	elseif kind == "Diner" then
		food(store == "TONY'S PIZZA" and "Pizza" or "Diner")
	elseif kind == "ProShop" then
		proShop()
	elseif kind == "Motors" then
		motors()
	elseif kind == "Museum" then
		museum()
	elseif kind == "EliteCenter" then
		eliteCenter()
	else
		return false
	end
	return true
end

State.open.Store = CityStores.Open
return CityStores
