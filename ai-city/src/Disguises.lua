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
Disguises.Order = { "Hoodie", "Disguise", "SkiMask" }

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
		if d and value then
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
