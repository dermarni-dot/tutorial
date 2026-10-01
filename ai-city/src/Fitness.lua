-- Fitness (ModuleScript) — ReplicatedStorage.Shared.Fitness
-- Sprinting and stamina. Hold Shift (or the Sprint button) to run; it uses
-- stamina, which refills when you stop. Sprinting and working out on the gym's
-- treadmills earn fitness XP; every level gives more stamina, faster recovery
-- and a faster sprint. Food refills stamina too (and coffee or an energy drink
-- speeds up recovery for a while).

local Fitness = {}

Fitness.WALK = 12 -- normal walking speed (a walk, not a jog: Shift to run)
Fitness.MAX_LEVEL = 20

-- what a fitness level gets you
function Fitness.Stats(level)
	level = math.clamp(level or 1, 1, Fitness.MAX_LEVEL)
	return {
		MaxStamina = 100 + (level - 1) * 12, -- how much stamina you have
		Sprint = 24 + (level - 1) * 0.6, -- sprint speed (walking is 12)
		Drain = 20, -- stamina per second while sprinting
		Regen = 11 + level * 1.5, -- stamina per second while not sprinting
		Delay = 0.9, -- seconds before it starts refilling
	}
end

-- XP needed to reach the next level
function Fitness.XPFor(level)
	return 60 + level * 45
end

Fitness.SPRINT_XP = 4 -- XP per second of sprinting
Fitness.TREADMILL_XP = 55 -- XP for one treadmill workout
Fitness.TREADMILL_SECONDS = 7

return Fitness
