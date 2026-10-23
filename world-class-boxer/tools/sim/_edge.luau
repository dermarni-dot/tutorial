--!nocheck
local FS = require("./fightsim")
local S = FS.new()
local STYLES = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local function edge(n, traits)
	local dealt, taken = 0, 0
	for i = 1, n do
		local r = S.Fight({ red = { bot = "volume", style = "BoxerPuncher", level = 60 }, blue = { style = STYLES[(i % 5) + 1], level = 60, traits = traits, noTraits = traits == nil }, rounds = 6, seed = i * 7919 + 13 })
		dealt += r.P.damageDealt
		taken += r.P.damageTaken
	end
	return dealt / taken
end
print(string.format("volume edge: with CS %.2f, without %.2f", edge(24, { { id = "CounterSpecialist", s = 1 } }), edge(24, nil)))
