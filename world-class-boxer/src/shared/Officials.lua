-- Officials: how the ring officials look (the server builds them with Builder.CreateNPC / Cosmetics; the colours are
-- painted by BuilderBody on the mesh outfit, GearAssetData group "official", tools/body/build_official.py)
-- * Look(seed, kind, o) -> app, build, gear, opts: the referee (kind "referee", a fight night) or the spar coach
--   (kind "cornerman", the gym's spar official): a random older man from the seed, a drawn face that suits the job
--   (the referee: neutral or stern; the coach: neutral, focused or stern), bare hands, medium detail, the outfit's
--   colours in opts.officialColors (Colors below)
-- * Colors(kind, o) -> { shirt, trim, trousers, ... } as {r, g, b}: the venue picks the referee's shirt (light blue at
--   the clubs, a paler blue-grey at the Grand Arena), a title fight / the stadium puts him in white; the coach wears
--   his team colour (o.team) or a dark polo
-- Bald (Config.BaldMode) and the headgear (Config.AlwaysHeadgear with Config.HeadgearOfficials) are Builder's.
local Officials = {}

local Shared = script.Parent
local Looks = require(Shared:WaitForChild("Looks"))
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))

-- the referee's shirt per venue (Config.Venues keys); a title fight overrides it with TITLE_SHIRT
Officials.VENUE_SHIRT = {
	CommunityCenter = { 156, 194, 228 },
	ClubArena = { 146, 186, 226 },
	Arena = { 192, 210, 230 },
	Stadium = { 246, 246, 243 },
	Gym = { 146, 186, 226 },
}
Officials.TITLE_SHIRT = { 246, 246, 243 }
Officials.DEFAULT_SHIRT = { 150, 190, 226 }
-- fight kinds (Career offers) that are championship fights: the referee in white
Officials.TITLE_KINDS = { ["World Title"] = true, ["Unification"] = true, ["Title Defense"] = true, ["Regional Title"] = true }

local REF_FACES = { "wcb_neutral", "wcb_stern" }
local COACH_FACES = { "wcb_neutral", "wcb_focused", "wcb_stern" }

local function rgb(t)
	return { t[1], t[2], t[3] }
end
local function darker(t, k)
	return { math.floor(t[1] * k + 0.5), math.floor(t[2] * k + 0.5), math.floor(t[3] * k + 0.5) }
end

-- o = { venue = Config.Venues key | "Gym", kind = the fight kind, championship = bool, team = {r,g,b} }
function Officials.Colors(kind, o)
	o = o or {}
	if kind == "cornerman" then
		local team = type(o.team) == "table" and o.team or { 30, 30, 34 }
		return {
			shirt = rgb(team), trim = darker(team, 0.86), buttons = { 236, 236, 232 }, trousers = { 38, 38, 44 },
			belt = { 30, 30, 34 }, shoes = { 236, 236, 232 }, soles = { 225, 225, 220 }, laces = { 240, 240, 240 },
			towel = { 238, 238, 232 },
		}
	end
	local title = o.championship == true or (o.kind ~= nil and Officials.TITLE_KINDS[o.kind] == true)
	local shirt = title and Officials.TITLE_SHIRT or Officials.VENUE_SHIRT[o.venue or ""] or Officials.DEFAULT_SHIRT
	return {
		shirt = rgb(shirt), trim = darker(shirt, 0.93), buttons = { 240, 240, 236 }, badge = { 212, 172, 64 },
		bowtie = { 16, 16, 18 }, trousers = { 22, 22, 26 }, belt = { 18, 18, 20 }, buckle = { 200, 200, 206 },
		shoes = { 14, 14, 16 }, soles = { 30, 26, 24 }, laces = { 16, 16, 18 },
	}
end

-- the drawn face an official rests on, from his own stream
local function faceOf(seed, list)
	local r = Random.new(seed * 7 + 7717)
	r:NextNumber() -- (a warm-up draw: a fresh stream's first number from a small seed is not well mixed everywhere)
	local k = list[r:NextInteger(1, #list)]
	return BodyTiers.IsDrawnStyle(k) and k or BodyTiers.DefaultStyle()
end

-- seed: any integer (FightEngine draws one per fight). Returns app, build, gear, opts for Builder.CreateNPC
function Officials.Look(seed, kind, o)
	o = o or {}
	local coach = kind == "cornerman"
	local rng = Random.new(seed)
	local s = 9000 + rng:NextInteger(1, 50000)
	local age = coach and rng:NextInteger(45, 62) or rng:NextInteger(38, 58)
	local app = Looks.Random(s, 1, {})
	app.face.style = faceOf(s, coach and COACH_FACES or REF_FACES)
	local build = Looks.RandomBuild(s, coach and 0.35 or 0.2, age)
	local opts = {
		detail = "medium", outfit = coach and "cornerman" or "referee", hands = "bare", age = age, name = "", nick = "",
		waistText = "",
	}
	local co = table.clone(o)
	if coach and co.team == nil and type(app.attire) == "table" and type(app.attire.trim) == "table" then
		co.team = app.attire.trim -- (his own team colour, as before)
	end
	opts.officialColors = Officials.Colors(kind, co)
	return app, build, {}, opts
end

return Officials
