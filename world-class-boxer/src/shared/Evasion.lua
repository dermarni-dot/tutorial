-- Evasion: the head movement and the dodges, as data (shared and pure: FightEngine runs them, FightAI picks them,
-- Keymap / ControlsMenu / the tutorial describe them, tools/sim/test_combos checks them).
--
-- Each dodge is a short EVADE WINDOW (seconds, from the press) and a longer RECOVERY (the act's length, when the
-- next action may start). A punch that arrives inside the window misses when the dodge beats its kind (the
-- `beats` share: 1 = always, 0.5 = half the time, 0 = never); one that arrives after the window but inside the
-- recovery CATCHES the fighter mid-dodge (CAUGHT_HIT more accuracy, CAUGHT_DMG more damage), so the timing has to
-- be right. A dodge that wins opens a counter window (`counter` seconds): a punch thrown in it is a counter
-- (FightEngine's counter damage) with COUNTER_HIT more accuracy, and it continues a combo chain that started with
-- the dodge (Combos: SLIP-COUNTER, WEAVE-COUNTER, DUCK-UPPERCUT, STEP-COUNTER). `punish` = what a punch of that
-- kind does to a fighter it catches in this dodge (an uppercut into a weave or a duck lands bigger).
--
-- Acts (model attribute Act, CONTRACTS section 7; the Animator plays them): slip|L / slip|R, roll (the dodge /
-- quick dodge), weave|L / weave|R (bob and weave), duck, pull (lean back), sidestep|L / sidestep|R (a step off the
-- line: the server also moves the root a little sideways, as a pivot does). A dodge that made a punch miss is
-- told to the clients as `defense` { who, move = its text, dodge = kind } (the HUD's call-out).
--
-- Stamina: `stam` per dodge (a side-step costs the most: it beats everything). A new dodge may replace one started
-- less than CANCEL seconds ago (the controller's flick-then-button chords: the flick's slip turns into the weave,
-- the duck, the pull or the side-step), with half the first one's cost given back.
local Evasion = {}

Evasion.CAUGHT_HIT, Evasion.CAUGHT_DMG = 0.1, 1.15
Evasion.COUNTER_HIT = 0.08
Evasion.CANCEL = 0.35
Evasion.GAP = 0.08 -- the shortest stretch of a dodge's recovery after its window (gap = true: the new dodges)
-- a dodge beats a punch only when it VISIBLY began before the contact: its act had this long (two frames at 60 Hz)
-- to move the head before the glove arrived, as the attacker's screen showed it (FightEngine:Evaded; a player's
-- punch also counts the delay before his client saw the dodge start). FightAI does not start a dodge it cannot get
-- going in time
Evasion.VISIBLE = 0.035

-- window = base + reflexes x Reflexes + head x HeadMovement + feet x Footwork (stats 0..100), times the
-- concussion / daze factor (FightEngine:DefenseMul)
Evasion.Moves = {
	slip = { act = "slip", sided = true, base = 0.26, reflexes = 0.003, head = 0.002, recover = 0.42, stam = 4, counter = 0.85,
		beats = { straight = 1, hook = 0.5 }, text = "SLIPPED", key = "slipL",
		desc = "Head off the line: beats straights (half the hooks)." },
	roll = { act = "roll", base = 0.30, head = 0.003, recover = 0.55, stam = 5, counter = 0.8,
		beats = { hook = 1, overhand = 1, straight = 0.5 }, punish = { uppercut = 1.4 }, text = "ROLLED UNDER", key = "dodge",
		desc = "Roll under: beats hooks and overhands (half the straights). Never into an uppercut." },
	weave = { act = "weave", sided = true, gap = true, base = 0.22, head = 0.003, reflexes = 0.001, recover = 0.5, stam = 5, counter = 0.95,
		beats = { hook = 1, overhand = 1, straight = 0.35 }, punish = { uppercut = 1.35 }, text = "WEAVED", key = "weaveL",
		desc = "Bob and weave under it to one side: beats hooks and overhands, and the counter window is the longest." },
	duck = { act = "duck", gap = true, base = 0.24, head = 0.0025, recover = 0.4, stam = 4, counter = 0.75,
		beats = { hook = 1, overhand = 0.8, straight = 0.6 }, punish = { uppercut = 1.5 }, text = "DUCKED", key = "duck",
		desc = "Drop straight down: beats hooks (most overhands and straights). An uppercut lands huge." },
	pull = { act = "pull", gap = true, base = 0.24, reflexes = 0.003, recover = 0.45, stam = 4, counter = 0.9,
		beats = { straight = 1, uppercut = 0.6, hook = 0.3 }, text = "PULLED BACK", key = "pull",
		desc = "Lean back out of range: beats straights. Hooks still find you." },
	sidestep = { act = "sidestep", sided = true, gap = true, base = 0.30, feet = 0.0025, recover = 0.55, stam = 9, counter = 0.7, body = true, step = 1.6, angle = 1.0,
		beats = { straight = 1, hook = 1, overhand = 1, uppercut = 1 }, text = "SIDESTEPPED", key = "sidestepL",
		desc = "Step off the line: beats everything, body shots too, and leaves you at an angle. The dearest on the gas." },
}
Evasion.List = { "slip", "roll", "weave", "duck", "pull", "sidestep" }

function Evasion.Window(kind, stats, defMul)
	local E = Evasion.Moves[kind]
	if not E then
		return 0
	end
	stats = type(stats) == "table" and stats or {}
	local w = E.base + (E.reflexes or 0) * (tonumber(stats.Reflexes) or 50) + (E.head or 0) * (tonumber(stats.HeadMovement) or 50)
		+ (E.feet or 0) * (tonumber(stats.Footwork) or 50)
	if E.gap then
		-- (the new dodges always leave a gap before the recovery ends: a punch that comes late catches him)
		w = math.min(w, E.recover - Evasion.GAP)
	end
	return w * (tonumber(defMul) or 1)
end

-- the act string for the model (dir = -1 left / 1 right for a sided dodge; dur = the act's length, optional: the
-- Animator reads it as the last field, "weave|L|0.50", "duck|0.40")
function Evasion.Act(kind, dir, dur)
	local E = Evasion.Moves[kind]
	if not E then
		return nil
	end
	local a = E.act
	if E.sided then
		a ..= "|" .. (dir == -1 and "L" or "R")
	end
	if tonumber(dur) then
		a ..= string.format("|%.2f", dur)
	end
	return a
end

-- does the dodge make this punch miss? (punchKind = Config.Punches[p].kind; roll = 0..1 from the server's rng)
function Evasion.Beats(kind, punchKind, body, roll)
	local E = Evasion.Moves[kind]
	if not E then
		return false
	end
	if body and not E.body then
		return false
	end
	local share = E.beats[punchKind] or 0
	return (tonumber(roll) or 0) < share
end

-- what a punch of that kind does to a fighter it catches in this dodge (damage multiplier)
function Evasion.Punish(kind, punchKind)
	local E = Evasion.Moves[kind]
	return (E and E.punish and E.punish[punchKind]) or 1
end

-- the AI: how much each style leans on its head movement (FightAI multiplies its dodge weights by it); the
-- counter-punchers and out-boxers dodge most, the swarmer weaves (peek-a-boo), the slugger mostly blocks
Evasion.StyleDodge = { CounterPuncher = 1.5, OutBoxer = 1.4, BoxerPuncher = 1.1, Swarmer = 1.15, Slugger = 0.65 }
-- each dodge's weight by the punch coming (FightAI:OnOppPunch), before the style and archetype
Evasion.AIWeights = {
	straight = { slip = 1, pull = 0.6, duck = 0.25, sidestep = 0.15 },
	hook = { weave = 1, duck = 0.6, roll = 0.5, sidestep = 0.15 },
	overhand = { weave = 0.8, roll = 0.6, duck = 0.5, sidestep = 0.2 },
	uppercut = { pull = 0.7, sidestep = 0.3 },
}
-- the style's favourite (an extra share on top): the swarmer weaves, the out-boxer steps off and pulls
Evasion.StyleFavourite = { Swarmer = "weave", OutBoxer = "sidestep", CounterPuncher = "pull", BoxerPuncher = "slip", Slugger = "duck" }

return Evasion
