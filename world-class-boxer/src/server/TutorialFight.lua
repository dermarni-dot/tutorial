-- TutorialFight: the first-time tutorial bout's cast and night (Shared.Tutorial has the steps and the rules).
-- The player does NOT fight as his own boxer: both corners are random boxers made by the world's generator
-- (World.RandomBoxer: name, nick, style, archetype, stats; World.Look through Career.FighterFromBoxer: the
-- Looks.Random face and hair, the build, the kit), the venue is a random fight venue with a modest crowd
-- (Venues.Importance / CrowdFill). Build never reads or writes the profile: the career, its record, money,
-- rankings, injuries, move unlocks (Moves counts the career's records) and the saved character stay as
-- they are. Only Tutorial.MarkDone writes, and only profile.tutorialDone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local World = require(script.Parent.World)
local Career = require(script.Parent.Career)

local TutorialFight = {}

-- the fight venues (not the stadium: a world-title bowl for a first lesson, and not the gym: a real fight night)
TutorialFight.Venues = { "CommunityCenter", "ClubArena", "Arena" }
-- the crowd: an undercard's importance and a little-known boxer (Venues.CrowdFill ~0.3 .. 0.5 of the house)
TutorialFight.Importance = { 0.15, 0.32 }
TutorialFight.Popularity = { 5, 25 }
-- the boxers: the player's a decent prospect, the opponent clearly weaker (and not a defensive or counter
-- puncher: the AI that slips and counters everything is no first opponent)
TutorialFight.PlayerLevel = { 52, 62 }
TutorialFight.OppLevel = { 30, 38 }
local HARD_ARCHETYPES = { Defensive = true, Counter = true }

-- opts = { assist = 0..2 (the player's saved aim-assist level) }. Returns
-- { pData, oData, venue, venueName, venueOpts, offer } for FightEngine.Run (opts.tutorial = true).
function TutorialFight.Build(rng, opts)
	opts = type(opts) == "table" and opts or {}
	rng = rng or Random.new()
	local ci = rng:NextInteger(2, math.min(#Config.WeightClasses, 10))
	local me = World.RandomBoxer(rng, ci, rng:NextNumber(TutorialFight.PlayerLevel[1], TutorialFight.PlayerLevel[2]))
	local opp
	for _ = 1, 12 do
		opp = World.RandomBoxer(rng, ci, rng:NextNumber(TutorialFight.OppLevel[1], TutorialFight.OppLevel[2]), { female = me.gender == 2 })
		if not HARD_ARCHETYPES[opp.archetype] and opp.name ~= me.name then
			break
		end
	end
	local pData = Career.FighterFromBoxer(me)
	pData.isPlayer = true
	pData.id = nil
	pData.learned, pData.h2h, pData.personality = nil, nil, nil
	-- one special move to learn (the career's unlocks are not consulted: Moves.Info reads the career)
	pData.moves = { [Tutorial.SPECIAL] = true }
	pData.assist = math.clamp(math.floor(tonumber(opts.assist) or 0), 0, 2)
	pData.lookOpts.robe = "None"
	local oData = Career.FighterFromBoxer(opp)
	oData.lookOpts.robe = "None"
	oData.learned = {} -- a stranger: he has not studied the player's habits
	oData.moves = {} -- and he throws no special moves at a beginner
	local list = TutorialFight.Venues
	local venue = list[rng:NextInteger(1, #list)]
	local venueName = (Config.Venues and Config.Venues[venue] and Config.Venues[venue].name) or venue
	local venueOpts = {
		kind = "Tutorial Fight", careerTier = 1, supporters = 0.25, nick = me.nick,
		importance = rng:NextNumber(TutorialFight.Importance[1], TutorialFight.Importance[2]),
		popularity = rng:NextInteger(TutorialFight.Popularity[1], TutorialFight.Popularity[2]),
	}
	local offer = {
		kind = "Tutorial Fight", rounds = Tutorial.ROUNDS, venue = venue, venueName = venueName, talk = "", myLine = "",
		stakes = {}, playerStakes = {}, tutorial = true,
	}
	return { pData = pData, oData = oData, venue = venue, venueName = venueName, venueOpts = venueOpts, offer = offer }
end

-- the look options for dressing the player's own rig as the tutorial boxer before the bout (Builder.Apply:
-- his height and frame, face, hair and kit; the player's look comes back with Main's applyLook after it)
function TutorialFight.LookOpts(pData)
	local o = table.clone(pData.lookOpts or {})
	o.hands = "gloves"
	o.detail = "full"
	return o
end

-- the end of a tutorial (how = "completed" | "skipped" | "crashed" | "aborted" | "left"): the flag, nothing else
TutorialFight.Finish = Tutorial.MarkDone

return TutorialFight
