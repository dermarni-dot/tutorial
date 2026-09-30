-- Weapons (ModuleScript) — ReplicatedStorage.Shared.Weapons
-- Everything you can fight with. Buy weapons at the Hardware store; they
-- show up in your hotbar (1, 2, 3...). Click (or F) to attack, hold X (or
-- right mouse) to block.
--
--   Damage    how much health one hit takes (citizens have 100, police 150, SWAT 250)
--   Range     how close you need to be (studs)
--   Cooldown  seconds between attacks
--   Knock     how hard a hit pushes people back
--   Anim      the attack animation: "punch", "swing" or "stab"
--   Severity  how serious the crime is (more stars, more notoriety)

local Weapons = {}

Weapons.List = {
	Fists = {
		Name = "Fists", Emoji = "👊", Damage = 25, Range = 6, Cooldown = 0.45, Knock = 14, Anim = "punch", Severity = 1, Price = 0,
		Verb = "punched", Down = "knocked out",
		Desc = "Always with you. Four good punches put someone down.",
	},
	Bat = {
		Name = "Baseball Bat", Emoji = "🏏", Damage = 40, Range = 7.5, Cooldown = 0.8, Knock = 42, Anim = "swing", Severity = 2, Price = 40,
		Verb = "hit with a bat", Down = "beaten down with a bat",
		Desc = "Slow, heavy swings that send people flying.",
	},
	Hammer = {
		Name = "Hammer", Emoji = "🔨", Damage = 45, Range = 6.5, Cooldown = 0.65, Knock = 26, Anim = "swing", Severity = 2, Price = 75,
		Verb = "hit with a hammer", Down = "taken down with a hammer",
		Desc = "Hits hard and fast. Smash open a register or the bank vault with it for 50% more cash.",
		FastRob = true,
	},
	Knife = {
		Name = "Knife", Emoji = "🔪", Damage = 55, Range = 5, Cooldown = 0.4, Knock = 6, Anim = "stab", Severity = 3, Price = 120,
		Verb = "stabbed", Down = "stabbed",
		Desc = "Quick stabs up close. Two hits and they're down. The most serious crime in the city.",
	},
	-- guns: aim with the camera (or the mouse) and fire. Walls stop bullets.
	-- Gunshots are loud: everyone nearby hears them, runs and calls the police.
	Pistol = {
		Name = "Pistol", Emoji = "🔫", Damage = 34, Range = 90, Cooldown = 0.32, Knock = 8, Anim = "shoot", Severity = 4, Price = 350,
		Verb = "shot", Down = "shot down", Ranged = true, Cone = 0.985, Loud = 140,
		Desc = "Aim and fire from far away. Three hits put someone down. The loudest crime in the city: everyone hears it.",
	},
	Shotgun = {
		Name = "Shotgun", Emoji = "💥", Damage = 75, Range = 38, Cooldown = 1.1, Knock = 40, Anim = "shoot", Severity = 4, Price = 600,
		Verb = "blasted", Down = "blasted down", Ranged = true, Cone = 0.94, Loud = 170, Heavy = true,
		Desc = "A wide, heavy blast up close. Slow to fire, one or two hits put anyone down.",
	},
}
Weapons.Order = { "Bat", "Hammer", "Knife", "Pistol", "Shotgun" }

-- Health by who you're fighting
Weapons.CITIZEN_HP = 100
Weapons.POLICE_HP = 150
Weapons.SWAT_HP = 250
Weapons.BLOCK = 0.3 -- blocking takes this much of the damage

-- Built-in Roblox R15 tool animations (they work in any game)
Weapons.Animations = {
	punch = "rbxassetid://522635514", -- tool slash, sped up: a jab
	swing = "rbxassetid://522635514", -- tool slash: an overhead swing
	stab = "rbxassetid://522638767", -- tool lunge: a stab
	shoot = "rbxassetid://522635514", -- (the recoil is posed in Poses)
}

function Weapons.Get(id)
	return Weapons.List[id] or Weapons.List.Fists
end

return Weapons
