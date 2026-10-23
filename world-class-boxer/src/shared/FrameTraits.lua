-- FrameTraits: what a boxer's body frame (Config.BodyTypes: Lean, Athletic, Muscular, Power Build, Heavyweight
-- Build) does to him in the ring, for his whole career, player and AI alike. Pure data and helpers: no engine
-- state. FightEngine multiplies these in at the places marked `-- [FrameTraits]` (damage, knockdowns, stamina,
-- movement, the punch windows, the dodge windows, the clinch, the get-up); FightAI fights to its frame
-- (FrameTraits.Data[id].ai); FightClient predicts its punch windows with the same handSpeed; the Creator and the
-- fighter card read Pros / Cons / Read for the copy. (The frame's muscle cap and the one-off starting-stat mods
-- stay in Config.BodyTypes: these are the permanent traits on top.)
--
-- Every multiplier is 1 for a trait the frame does not change. The meaning of each key:
--   power        damage of his own punches (head and body)
--   kdPower      the knockdown odds of his own head shots (Power Build: the biggest single punch)
--   handSpeed    the punch wind-up (and so the recovery) is DIVIDED by it: 1.1 = 10% faster hands
--   footSpeed    his walking speed in the ring
--   tank         the size of his stamina tank (the max; the second wind and the rounds' erosion scale with it)
--   staminaDrain the stamina every punch costs
--   powerDrain   on top of it for the power punches (everything but the jab)
--   staminaRegen the stamina coming back, in the round and in the corner
--   chin         head damage taken is DIVIDED by it: 1.1 = takes 10% less
--   bodyAbsorb   body damage (and the gas it drains) is DIVIDED by it
--   reachBonus   the arm's length for the hit geometry (a long-armed frame reaches further at the same height)
--   kdResist     the odds of being dropped by a head shot are DIVIDED by it
--   getUpTime    the get-up after a knockdown (the animation and the presses the count asks for)
--   clinch       the inside work in a clinch: what he lands in it, and how long his hold keeps the other man tied up
--   insideBonus  hooks and uppercuts thrown from inside (FightMotion's inside spacing)
--   dodgeWindow  the slip / roll / weave / duck / pull / side-step / parry windows
--   target       the odds of a punch landing on him (the bigger man is the bigger target; HitGeometry already
--                reaches him sooner from his real size)
local FrameTraits = {}

FrameTraits.Keys = { "power", "kdPower", "handSpeed", "footSpeed", "tank", "staminaDrain", "powerDrain", "staminaRegen", "chin", "bodyAbsorb", "reachBonus",
	"kdResist", "getUpTime", "clinch", "insideBonus", "dodgeWindow", "target" }

-- ai: how the AI fights to the frame. range = its preferred distance as a share of the jab range (added to the
-- style's); aggr = aggression added; clinch = the chance per decision inside clinch range to tie up (on top of a
-- hurt man's); inside = weight on hooks / uppercuts (under 1: the straights); press = cuts the ring more
FrameTraits.Data = {
	Lean = {
		name = "Lean", short = "Lean", tag = "Fast hands, long jab",
		power = 0.93, kdPower = 0.90, handSpeed = 1.10, footSpeed = 1.08, tank = 1.04, staminaDrain = 0.92, powerDrain = 1, staminaRegen = 1.10,
		chin = 0.97, bodyAbsorb = 0.90, reachBonus = 1.04, kdResist = 0.98, getUpTime = 0.95, clinch = 0.88, insideBonus = 0.95, dodgeWindow = 1.15, target = 0.92,
		ai = { range = 0.04, aggr = 0.02, clinch = 0.0, inside = 0.8, press = 0 },
		pros = { "Fastest hands: shorter punch windows, quicker recovery", "Quick feet and longer slip and dodge windows", "Spends less stamina a punch, recovers more", "Long arms: reaches further at the same height" },
		cons = { "Less power behind every punch", "A softer chin: goes down easier", "Body shots hurt more and take more gas" },
	},
	Athletic = {
		name = "Athletic", short = "Athletic", tag = "The all-rounder",
		power = 1, kdPower = 1, handSpeed = 1, footSpeed = 1, tank = 1.02, staminaDrain = 0.97, powerDrain = 1, staminaRegen = 1.05,
		chin = 1, bodyAbsorb = 1, reachBonus = 1, kdResist = 1, getUpTime = 1, clinch = 1, insideBonus = 1, dodgeWindow = 1, target = 1,
		ai = { range = 0, aggr = 0, clinch = 0, inside = 1, press = 0 },
		pros = { "No weaknesses: the baseline frame", "A little more stamina and recovery" },
		cons = { "No standout strength either" },
	},
	Muscular = {
		name = "Muscular", short = "Muscular", tag = "Power with a chin",
		power = 1.04, kdPower = 1.02, handSpeed = 0.97, footSpeed = 1, tank = 1, staminaDrain = 1, powerDrain = 1.06, staminaRegen = 1,
		chin = 1.03, bodyAbsorb = 1.02, reachBonus = 1, kdResist = 1.03, getUpTime = 1, clinch = 1.04, insideBonus = 1.03, dodgeWindow = 0.98, target = 1.01,
		ai = { range = -0.02, aggr = 0.04, clinch = 0.02, inside = 1.08, press = 0.05 },
		pros = { "More power in every punch", "A better chin, harder to drop", "Normal footwork" },
		cons = { "Slightly slower hands", "Power punches drain a little more stamina" },
	},
	["Power Build"] = {
		name = "Power Build", short = "Power", tag = "One-punch power inside",
		power = 1.04, kdPower = 1.05, handSpeed = 0.93, footSpeed = 0.94, tank = 0.96, staminaDrain = 1.06, powerDrain = 1.06, staminaRegen = 0.92,
		chin = 1.03, bodyAbsorb = 1.04, reachBonus = 1, kdResist = 1.05, getUpTime = 1.05, clinch = 1.12, insideBonus = 1.06, dodgeWindow = 0.94, target = 1.03,
		ai = { range = -0.08, aggr = 0.08, clinch = 0.06, inside = 1.2, press = 0.12 },
		pros = { "The biggest single punch and knockdown chance", "A hard chin: very hard to drop", "Strong in the clinch and inside: hooks and uppercuts land harder" },
		cons = { "Slower hands and feet", "Gasses in the later rounds", "Easier to outbox at range" },
	},
	["Heavyweight Build"] = {
		name = "Heavyweight Build", short = "Heavyweight", tag = "Raw power, slow burn",
		power = 1.09, kdPower = 1.03, handSpeed = 0.88, footSpeed = 0.88, tank = 0.92, staminaDrain = 1.12, powerDrain = 1.06, staminaRegen = 0.84,
		chin = 1.06, bodyAbsorb = 1.12, reachBonus = 1, kdResist = 1.08, getUpTime = 1.18, clinch = 1.20, insideBonus = 1.06, dodgeWindow = 0.90, target = 1.08,
		ai = { range = -0.10, aggr = 0.1, clinch = 0.09, inside = 1.2, press = 0.15 },
		pros = { "The strongest raw power", "Absorbs body shots best and is the hardest to knock down", "The heaviest clinch: holds and wears the other man" },
		cons = { "The slowest feet and hands", "The worst stamina", "The biggest target, and slower up off the canvas" },
	},
}
FrameTraits.Order = { "Lean", "Athletic", "Muscular", "Power Build", "Heavyweight Build" }

-- [FrameTraits] how fast the frame's stats grow in training (Training.GainMultiplier): small, the frame's nature.
-- A stat not listed grows at the usual rate.
FrameTraits.Growth = {
	Lean = { PunchSpeed = 1.08, Footwork = 1.08, Reflexes = 1.05, Power = 0.94, Chin = 0.95 },
	Athletic = { Stamina = 1.04, Recovery = 1.04 },
	Muscular = { Power = 1.05, Chin = 1.04, PunchSpeed = 0.97 },
	["Power Build"] = { Power = 1.08, Chin = 1.06, PunchSpeed = 0.95, Footwork = 0.95 },
	["Heavyweight Build"] = { Power = 1.08, Chin = 1.08, Endurance = 1.04, PunchSpeed = 0.94, Footwork = 0.93, Stamina = 0.96 },
}
function FrameTraits.GrowthMul(id, statKey)
	local g = FrameTraits.Growth[id]
	local v = g and g[statKey]
	return type(v) == "number" and v or 1
end

local NEUTRAL = {}
for _, k in ipairs(FrameTraits.Keys) do
	NEUTRAL[k] = 1
end
NEUTRAL.name, NEUTRAL.short, NEUTRAL.tag, NEUTRAL.ai, NEUTRAL.pros, NEUTRAL.cons = "Athletic", "Athletic", "", { range = 0, aggr = 0, clinch = 0, inside = 1, press = 0 }, {}, {}
FrameTraits.Neutral = NEUTRAL

-- the traits of a frame id (an unknown / missing id: Athletic's, the baseline)
function FrameTraits.Get(id)
	return FrameTraits.Data[id] or FrameTraits.Data.Athletic or NEUTRAL
end

-- the frame id of a fighter's data (FightEngine: data.app.body.frame; a profile summary: appearance.body.frame)
function FrameTraits.IdOf(data)
	local app = type(data) == "table" and (data.app or data.appearance) or nil
	local body = type(app) == "table" and app.body or nil
	local id = type(body) == "table" and body.frame or nil
	return FrameTraits.Data[id] and id or "Athletic"
end

function FrameTraits.For(data)
	return FrameTraits.Get(FrameTraits.IdOf(data))
end

-- one multiplier, 1 when the id or the key is unknown
function FrameTraits.Mul(id, key)
	local t = FrameTraits.Data[id]
	local v = t and t[key]
	return type(v) == "number" and v or 1
end

-- the short read for the opponent's scouting line and the fighter card: "Heavyweight - raw power, slow burn"
function FrameTraits.Read(id)
	local t = FrameTraits.Data[id]
	if not t then
		return nil
	end
	return string.format("%s - %s", t.short, string.lower(t.tag))
end

-- the pros / cons lists (copies) for the UI
function FrameTraits.Pros(id)
	return table.clone(FrameTraits.Get(id).pros)
end
function FrameTraits.Cons(id)
	return table.clone(FrameTraits.Get(id).cons)
end

-- the display name of a frame ("Heavyweight" for "Heavyweight Build")
function FrameTraits.ShortName(id)
	local t = FrameTraits.Data[id]
	return t and t.short or tostring(id or "?"):gsub(" Build$", "")
end

return FrameTraits
