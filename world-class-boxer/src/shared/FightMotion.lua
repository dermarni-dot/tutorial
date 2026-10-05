--!strict
-- FightMotion: shared fight-animation data (R-anim, round 2). The server picks HOW a fighter goes down
-- (from the punch, the severity and where he stands in the ring) and publishes it on the model; the
-- client's Animator (AnimDown) plays it. Pure data + pure functions: no Instances, unit-testable.
--
-- Attributes on the downed fighter's model (all set BEFORE Guard = "down"; cleared when he is up):
--   DownPose  string  how he falls. Round-1 values stay valid: back, side, knee, sit, face.
--                     Round-2 additions: flash, forward, ropes, corner, standing.
--   DownDir   number  fall direction in radians relative to his facing at the moment of the knockdown
--                     (0 = forward, pi = backward, +pi/2 = to his left, -pi/2 = to his right).
--   DownDist  number  studs from him to the ropes along DownDir; for ropes / corner falls: how far the
--                     server walks his root back into the ropes / the corner while he staggers there.
--   KOKind    string  only on a knockout (severity "out"): oneshot | delayed | standing | crumple.
--                     (crumple + back is the backward collapse: knees first, then the fold onto his back)
local FightMotion = {}

local PI = math.pi

-- every DownPose value the client understands (old first)
FightMotion.Falls = { "back", "side", "knee", "sit", "face", "flash", "forward", "ropes", "corner", "standing" }
FightMotion.ValidFall = {} :: { [string]: boolean }
for _, f in ipairs(FightMotion.Falls) do
	FightMotion.ValidFall[f] = true
end

-- KOKind values: oneshot = stiff timber fall off one punch; delayed = out on his feet for a beat, then the
-- legs go; standing = out on his feet, the referee catches him; crumple = folds where he stands
FightMotion.KOKinds = { "oneshot", "delayed", "standing", "crumple" }

-- the server can still ragdoll an out-cold NPC with physics (round 1); animated knockouts are the default
FightMotion.ANIMATED_KO = true

-- seconds the referee holds a fighter knocked out on his feet before he waves it off
FightMotion.CATCH_TIME = 2.2

-- how far inside the rope line a fighter's root stays (FightEngine:ClampToRing)
FightMotion.ROPE_MARGIN = 1.5

-- seconds the get-up takes per fall (FightEngine sends it in the getup act; the client stages it:
-- off the back he rolls to his side, onto hands and knees, one knee, then up; off the ropes he pulls
-- himself up on them). The eight count and the referee check wait for it.
local GETUP = {
	flash = 1.1, sit = 1.3, knee = 1.4, standing = 1.0, forward = 2.0, face = 2.2, back = 2.4, side = 2.3, ropes = 2.0, corner = 2.0,
}
function FightMotion.GetUpTime(fall: string?): number
	return GETUP[fall or "back"] or 2.4
end

-- wall-clock seconds from a knockout punch until the client's fall has landed and settled (the slow-motion
-- beat included). The server waits this long before the referee waves it off and the fight ends, so the
-- KO close-up and the "KO!" banner never cut away from a man still falling.
local KO_WALL = { oneshot = 1.75, crumple = 1.75, delayed = 2.6, standing = 0.6 }
function FightMotion.KOFallWall(ko: string?, pose: string?): number
	local w = KO_WALL[ko or "crumple"] or 1.75
	if pose == "ropes" or pose == "corner" then
		w += 0.35 -- the stagger into the ropes comes first
	elseif ko == "crumple" and pose == "back" then
		w += 0.2 -- the backward collapse goes down in two stages
	end
	return w
end

local function wrap(a: number): number
	return (a + PI) % (2 * PI) - PI
end

-- studs from p (ring-relative, flat) to the rope square of half-size `half` along unit direction (dx, dz)
local function ropeDistance(px: number, pz: number, dx: number, dz: number, half: number): number
	local best = 99
	if dx > 1e-3 then
		best = math.min(best, (half - px) / dx)
	elseif dx < -1e-3 then
		best = math.min(best, (-half - px) / dx)
	end
	if dz > 1e-3 then
		best = math.min(best, (half - pz) / dz)
	elseif dz < -1e-3 then
		best = math.min(best, (-half - pz) / dz)
	end
	return math.max(0, best)
end
FightMotion.ropeDistance = ropeDistance

export type FallInfo = {
	ptype: string?, -- jab / cross / leadhook / rearhook / uppercut / overhand
	kind: string?, -- Config.Punches[ptype].kind: straight / hook / uppercut / overhand
	body: boolean?,
	hand: string?, -- the punching hand, "L" / "R"
	severity: string?, -- flash / normal / heavy / out
	cause: string?, -- liver / legs / nil
	tier: number?, -- the victim's damage tier before the punch (0..3)
	counter: boolean?,
	-- geometry (flat world coordinates); any missing value disables the ring logic
	victimX: number?,
	victimZ: number?,
	victimYaw: number?, -- yaw of his facing (radians, Roblox convention: look = (-sin, 0, -cos))
	attackerX: number?,
	attackerZ: number?,
	ringX: number?,
	ringZ: number?,
	ringHalf: number?, -- rope line half size (studs)
	roll: number?, -- 0..1 random numbers from the server's rng
	roll2: number?,
}

-- moveX / moveZ: for ropes / corner falls, the flat world offset the server walks his root over while he
-- staggers into the ropes (so the body never drifts away from the root); nil otherwise
export type FallChoice = { pose: string, dir: number, dist: number, ko: string?, moveX: number?, moveZ: number? }

-- yaw of a flat world direction in the Roblox convention (look = (-sin, 0, -cos))
local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-- forward falls go past the attacker's shoulder, never through him: diagonal, to the side the blow
-- turned him (or either side for straight shots)
local function forwardDir(info: FallInfo, roll: number): number
	local kind = info.kind or "straight"
	if kind == "hook" or kind == "overhand" then
		local left = (info.hand or "R") == "L"
		if kind == "overhand" then
			left = not left
		end
		return left and 0.55 or -0.55
	end
	return roll < 0.5 and 0.5 or -0.5
end

-- the direction the blow pushes him, relative to his facing (radians, see DownDir)
local function pushDir(info: FallInfo): number
	local kind = info.kind or "straight"
	local hand = info.hand or "R"
	if info.body then
		return PI -- folds back over the shot (and down)
	elseif kind == "hook" then
		-- a left hook (from the attacker's left) lands on his right side and spins him to his left
		return hand == "L" and (PI / 2 + 0.35) or -(PI / 2 + 0.35)
	elseif kind == "overhand" then
		-- over the top: down and across, forward of his feet
		return hand == "L" and 0.6 or -0.6
	elseif kind == "uppercut" then
		return PI
	end
	return PI -- straights drive him straight back
end

-- ropes / corner falls: where his root goes and which way his back turns. Ropes: along the push until
-- the root reaches the rope margin, his back to that rope line; corner: into the corner, his back to
-- the post. DownDist becomes the length of that stagger. Without ring geometry nothing moves.
function FightMotion.RopeTravel(choice: FallChoice, info: FallInfo, push: number): FallChoice
	local half = info.ringHalf
	if not (half and info.victimX and info.victimZ and info.ringX and info.ringZ and info.victimYaw) then
		return choice
	end
	local px, pz = info.victimX - info.ringX, info.victimZ - info.ringZ
	local lim = half - FightMotion.ROPE_MARGIN
	local gx, gz, nx, nz
	if choice.pose == "corner" then
		local sx, sz = px >= 0 and 1 or -1, pz >= 0 and 1 or -1
		gx, gz = sx * lim, sz * lim
		nx, nz = sx * 0.7071, sz * 0.7071
	else
		local yaw = info.victimYaw + push
		local dx, dz = -math.sin(yaw), -math.cos(yaw)
		local t = ropeDistance(px, pz, dx, dz, lim)
		gx, gz = math.clamp(px + dx * t, -lim, lim), math.clamp(pz + dz * t, -lim, lim)
		-- the rope line he meets: the axis whose limit he reaches first
		if math.abs(math.abs(gx) - lim) <= math.abs(math.abs(gz) - lim) then
			nx, nz = gx >= 0 and 1 or -1, 0
		else
			nx, nz = 0, gz >= 0 and 1 or -1
		end
	end
	local mx, mz = gx - px, gz - pz
	choice.moveX, choice.moveZ = mx, mz
	choice.dist = math.min(math.sqrt(mx * mx + mz * mz), 20)
	-- DownDir: his back turns to the ropes / the post (where he goes, relative to his facing)
	choice.dir = wrap(yawOf(nx, nz) - info.victimYaw)
	return choice
end

-- Choose the fall. Pure: same info -> same answer.
function FightMotion.ChooseFall(info: FallInfo): FallChoice
	local sev = info.severity or "normal"
	local kind = info.kind or "straight"
	local roll = info.roll or 0.5
	local roll2 = info.roll2 or 0.5
	local dir = pushDir(info)
	-- distance to the ropes along the push (needs the ring geometry)
	local dist, nearCorner = 99, false
	local half = info.ringHalf
	if half and info.victimX and info.victimZ and info.ringX and info.ringZ and info.victimYaw then
		local px, pz = info.victimX - info.ringX, info.victimZ - info.ringZ
		local yaw = info.victimYaw + dir
		local dx, dz = -math.sin(yaw), -math.cos(yaw)
		dist = ropeDistance(px, pz, dx, dz, half)
		nearCorner = math.abs(px) > half - 3.2 and math.abs(pz) > half - 3.2
	end
	local ropesBehind = dist < 2.6
	local choice: FallChoice = { pose = "back", dir = dir, dist = math.min(dist, 20), ko = nil }

	if sev == "out" then
		-- knockouts: rare and memorable
		local hurt = (info.tier or 0) >= 2
		if hurt and roll < 0.3 then
			-- out on his feet: the referee catches him
			choice.ko = "standing"
			choice.pose = "standing"
			choice.dir = PI
		elseif kind == "hook" or kind == "overhand" then
			-- the lights go out mid-turn: face first, or spun to the side
			if roll < 0.45 then
				choice.ko, choice.pose, choice.dir = "oneshot", "face", forwardDir(info, roll2)
			elseif roll < 0.75 then
				choice.ko, choice.pose = "crumple", "side"
			else
				choice.ko, choice.pose, choice.dir = "delayed", "face", forwardDir(info, roll2)
			end
		else
			-- straights and uppercuts: the stiff backward fall, or the legs go a beat later
			if roll < 0.55 then
				choice.ko, choice.pose, choice.dir = "oneshot", "back", PI
			elseif roll < 0.8 then
				choice.ko, choice.pose, choice.dir = "delayed", "forward", forwardDir(info, roll2)
			else
				choice.ko, choice.pose, choice.dir = "crumple", "back", PI
			end
		end
		-- nobody timbers through the ropes: against them he slides down instead
		if choice.ko ~= "standing" and ropesBehind and math.abs(wrap(choice.dir - dir)) < 1.0 then
			choice.pose = nearCorner and "corner" or "ropes"
			choice.ko = "crumple"
			return FightMotion.RopeTravel(choice, info, dir)
		end
		return choice
	end
	if sev == "flash" then
		-- a flash knockdown: down and straight back up, more surprised than hurt
		choice.pose = roll < 0.6 and "flash" or "sit"
		return choice
	end
	if info.body or info.cause == "liver" then
		choice.pose = "knee"
		choice.dir = 0
		return choice
	end
	if info.cause == "legs" then
		-- the legs simply go: he folds forward onto a knee or his hands
		choice.pose = roll < 0.5 and "knee" or "forward"
		choice.dir = choice.pose == "forward" and forwardDir(info, roll2) or 0
		return choice
	end
	-- driven into the ropes / the corner: he sags down them
	if ropesBehind and (kind ~= "hook" or roll2 < 0.6) then
		choice.pose = nearCorner and "corner" or "ropes"
		return FightMotion.RopeTravel(choice, info, dir)
	end
	if kind == "hook" then
		choice.pose = (sev == "heavy" or roll < 0.65) and "side" or "knee"
		if choice.pose == "knee" then
			choice.dir = 0
		end
	elseif kind == "overhand" then
		choice.pose = roll < 0.6 and "forward" or "face"
		choice.dir = forwardDir(info, roll2)
	elseif kind == "uppercut" then
		choice.pose = roll < 0.6 and "back" or "sit"
	else
		-- jab / cross: a sit-down or a backward collapse (heavier shots go all the way)
		if sev == "heavy" then
			choice.pose = roll < 0.7 and "back" or "sit"
		else
			choice.pose = roll < 0.5 and "sit" or (roll < 0.8 and "back" or "forward")
			if choice.pose == "forward" then
				choice.dir = forwardDir(info, roll2)
			end
		end
	end
	return choice
end

return FightMotion
