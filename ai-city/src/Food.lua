-- Food (ModuleScript) — ReplicatedStorage.Shared.Food
-- What you can buy to eat at the city's food places (press E at the counter).
-- Eating heals you (Heal) and refills stamina (Energy). Coffee and energy
-- drinks also speed up stamina recovery for a while (Boost × for BoostTime s).

local Food = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Food.Items = {
	Croissant = { Name = "Croissant", Icon = "croissant", Price = 4, Heal = 12, Energy = 25, Color = rgb(222, 160, 80), Desc = "Flaky, buttery, fresh out of the oven." },
	Donut = { Name = "Donut", Icon = "donut", Price = 3, Heal = 8, Energy = 30, Color = rgb(240, 130, 180), Desc = "Pink icing and sprinkles. A quick sugar rush." },
	Coffee = { Name = "Coffee", Icon = "coffee", Price = 5, Heal = 0, Energy = 50, Boost = 1.6, BoostTime = 90, Color = rgb(120, 80, 50), Desc = "Stamina refills 60% faster for 90 seconds." },
	Muffin = { Name = "Blueberry Muffin", Icon = "muffin", Price = 4, Heal = 14, Energy = 15, Color = rgb(150, 110, 200), Desc = "Soft and warm, with real blueberries." },
	Burger = { Name = "Cheeseburger", Icon = "burger", Price = 10, Heal = 45, Energy = 30, Color = rgb(200, 120, 60), Desc = "A big, juicy burger. Heals a lot." },
	Fries = { Name = "Fries", Icon = "fries", Price = 5, Heal = 15, Energy = 20, Color = rgb(250, 200, 60), Desc = "Crispy and salty." },
	Milkshake = { Name = "Milkshake", Icon = "milkshake", Price = 6, Heal = 10, Energy = 45, Color = rgb(250, 170, 190), Desc = "Strawberry, with whipped cream on top." },
	Pasta = { Name = "Spaghetti", Icon = "pasta", Price = 15, Heal = 70, Energy = 60, Color = rgb(230, 190, 90), Desc = "The chef's special. Heals almost everything." },
	Pizza = { Name = "Pizza Slice", Icon = "pizza", Price = 8, Heal = 35, Energy = 30, Color = rgb(230, 120, 60), Desc = "Pepperoni, extra cheese." },
	IceCream = { Name = "Ice Cream", Icon = "icecream", Price = 5, Heal = 10, Energy = 35, Color = rgb(250, 210, 230), Desc = "Two scoops in a crunchy cone." },
	Apple = { Name = "Apple", Icon = "apple", Price = 2, Heal = 10, Energy = 12, Color = rgb(220, 50, 60), Desc = "Cheap and healthy." },
	Sandwich = { Name = "Sandwich", Icon = "sandwich", Price = 6, Heal = 25, Energy = 20, Color = rgb(230, 190, 120), Desc = "Ham, cheese and lettuce." },
	Energy = { Name = "Energy Drink", Icon = "energy", Price = 8, Heal = 0, Energy = 100, Boost = 2, BoostTime = 60, Color = rgb(60, 220, 120), Desc = "Full stamina, and it refills twice as fast for a minute." },
}

-- which place sells what
Food.Menus = {
	Bakery = { "Croissant", "Donut", "Muffin" },
	Cafe = { "Coffee", "Muffin", "Croissant" },
	Diner = { "Burger", "Fries", "Milkshake" },
	Restaurant = { "Pasta", "Pizza" },
	IceCream = { "IceCream", "Milkshake" },
	Shop = { "Apple", "Sandwich", "Energy" },
	Pizzeria = { "Pizza", "Fries", "Milkshake" },
	Bistro = { "Sandwich", "Coffee", "Croissant" },
	DonutShop = { "Donut", "Coffee", "Muffin" },
}

return Food
