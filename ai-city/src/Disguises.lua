-- Disguises (ModuleScript) — ReplicatedStorage.Shared.Disguises
-- Things you can wear so people don't recognize you. Buy them at the Clothing
-- store; put them on or take them off anytime with C (or the phone's Wardrobe).
--
-- You can wear one TOP (the hoodie) and one FACE item (the ski mask or the
-- disguise kit) at the same time. Their "Hidden" values stack.
--
--   Hidden     how hard you are to recognize (0 = not at all, 1 = impossible)
--   Night      extra Hidden after dark: a black hoodie in a dark street is
--              much harder to make out than in broad daylight
--   Suspicious how much it makes people nervous in the daytime (a ski mask at
--              noon looks like trouble; police keep an eye on you)
--
-- What being hidden does:
--   • witnesses may not recognize you: you get fewer stars, no notoriety, and
--     nobody remembers it was YOU ("someone in a ski mask attacked Asha")
--   • the police can't spot you from as far away, and bystanders rarely point you out
--   • change or take off what you wore at the crime while they can't see you,
--     and they're looking for the wrong person: they only know you up close
--     and give up much faster

local Disguises = {}

Disguises.List = {
	Hoodie = {
		Name = "Hoodie", Emoji = "🧥", Slot = "Top", Price = 30,
		Hidden = 0.2, Night = 0.25, Suspicious = 0,
		Looks = "someone in a dark hoodie",
		Desc = "Hood up, head down. Easy to blend in, and in the dark it's hard to tell who's inside.",
	},
	Disguise = {
		Name = "Disguise Kit", Emoji = "🥸", Slot = "Face", Price = 70,
		Hidden = 0.4, Night = 0.1, Suspicious = 0,
		Looks = "someone with a hat and a mustache",
		Desc = "A hat, dark glasses and a fake mustache. Looks totally normal, so nobody gets suspicious.",
	},
	SkiMask = {
		Name = "Ski Mask", Emoji = "🥷", Slot = "Face", Price = 55,
		Hidden = 0.55, Night = 0.25, Suspicious = 0.6,
		Looks = "someone in a ski mask",
		Desc = "Nobody sees your face. But wearing one in broad daylight makes people nervous and the police suspicious.",
	},
}
-- 👕 fashion: clothes just for looking good (a little harder to recognize,
-- since it's not what you usually wear). One per slot: TOP, HAT, EYES, NECK.
local function fashion(name, emoji, slot, price, desc, color, hidden)
	return { Name = name, Emoji = emoji, Slot = slot, Price = price, Hidden = hidden or 0.04, Night = 0, Suspicious = 0, Desc = desc, Color = color, Fashion = true }
end
local C = Color3.fromRGB
Disguises.List.LeatherJacket = fashion("Leather Jacket", "🧥", "Top", 90, "Black leather and a silver zip. Instantly cooler.", C(28, 26, 28))
Disguises.List.DenimJacket = fashion("Denim Jacket", "👖", "Top", 60, "Classic jean jacket with stitched pockets.", C(80, 110, 160))
Disguises.List.VarsityJacket = fashion("Varsity Jacket", "🏈", "Top", 75, "Team colours with white sleeves.", C(160, 30, 40))
Disguises.List.PufferJacket = fashion("Puffer Jacket", "🧣", "Top", 80, "Big, puffy and warm. Golden yellow.", C(240, 190, 50))
Disguises.List.Tracksuit = fashion("Tracksuit", "🏃", "Top", 55, "Zip-up track jacket with stripes down the sleeves.", C(40, 60, 150))
Disguises.List.Tuxedo = fashion("Tuxedo", "🤵", "Top", 160, "Black jacket, white shirt, bow tie. Very fancy.", C(24, 24, 28))
Disguises.List.Cap = fashion("Baseball Cap", "🧢", "Hat", 20, "A red cap. Wear it forwards like a normal person.", C(200, 40, 50))
Disguises.List.Beanie = fashion("Beanie", "🧶", "Hat", 25, "A warm knit beanie with a pom-pom.", C(60, 120, 90))
Disguises.List.CowboyHat = fashion("Cowboy Hat", "🤠", "Hat", 60, "Yeehaw. Wide brim, brown leather.", C(130, 85, 50), 0.08)
Disguises.List.BucketHat = fashion("Bucket Hat", "👒", "Hat", 35, "Soft and floppy, perfect for the beach.", C(230, 220, 190))
Disguises.List.Crown = fashion("Gold Crown", "👑", "Hat", 400, "For the richest person in the city. Everyone will know it's you.", C(245, 200, 70), 0)
Disguises.List.Sunglasses = fashion("Sunglasses", "🕶️", "Eyes", 40, "Dark lenses. Cool, and a bit harder to recognize.", C(20, 20, 24), 0.08)
Disguises.List.HeartGlasses = fashion("Heart Glasses", "💖", "Eyes", 45, "Pink heart-shaped shades.", C(240, 90, 150), 0.06)
Disguises.List.GoldChain = fashion("Gold Chain", "📿", "Neck", 150, "Heavy gold. It shines in the sun.", C(245, 200, 70), 0)
Disguises.List.Scarf = fashion("Scarf", "🧣", "Neck", 30, "A long striped scarf.", C(200, 60, 60))
Disguises.List.Headphones = fashion("Headphones", "🎧", "Neck", 70, "Big over-ear headphones (round your neck or on).", C(30, 30, 34))
Disguises.Order = { "Hoodie", "Disguise", "SkiMask",
	"LeatherJacket", "DenimJacket", "VarsityJacket", "PufferJacket", "Tracksuit", "Tuxedo",
	"Cap", "Beanie", "CowboyHat", "BucketHat", "Crown",
	"Sunglasses", "HeartGlasses", "GoldChain", "Scarf", "Headphones" }

Disguises.MAX = 0.9 -- nobody is ever completely invisible
Disguises.DARK = 0.1 -- after dark, everyone is a little harder to recognize

function Disguises.IsNight(hour)
	return hour >= 19.5 or hour < 5.5
end

-- How hidden is someone wearing these item ids (a list or a set)?
function Disguises.Hidden(worn, night)
	local visible = if night then 1 - Disguises.DARK else 1
	for key, value in pairs(worn or {}) do
		local id = if type(key) == "number" then value else key
		local d = Disguises.List[id]
		if d and value then
			visible *= 1 - math.min(0.95, d.Hidden + (if night then d.Night else 0))
		end
	end
	return math.min(Disguises.MAX, 1 - visible)
end

-- How suspicious it looks right now (daytime only)
function Disguises.Suspicious(worn, night)
	if night then
		return 0
	end
	local s = 0
	for key, value in pairs(worn or {}) do
		local id = if type(key) == "number" then value else key
		local d = Disguises.List[id]
		if d and value then
			s = math.max(s, d.Suspicious)
		end
	end
	return s
end

-- A short description ("someone in a ski mask and a dark hoodie")
function Disguises.Describe(worn)
	local face, top
	for key, value in pairs(worn or {}) do
		local id = if type(key) == "number" then value else key
		local d = Disguises.List[id]
		if d and value and d.Looks then
			if d.Slot == "Face" then
				face = d
			else
				top = d
			end
		end
	end
	if face and top then
		return face.Looks .. " and a dark hoodie"
	end
	return (face or top) and (face or top).Looks or nil
end

-- A key for "the outfit": the police look for this exact outfit
function Disguises.Signature(worn)
	local ids = {}
	for key, value in pairs(worn or {}) do
		local id = if type(key) == "number" then value else key
		if Disguises.List[id] and value then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, "+")
end

return Disguises
