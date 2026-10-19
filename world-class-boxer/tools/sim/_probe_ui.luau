--!nocheck
local GS = require("./guisim")
local process = require("@lune/process")
local S = GS.new(process.args[1] or "phone")
S.loadScript("client/FightClient.client.lua")
local Moves = S.require("Moves")
local fire = S.remotes.FightEvent
local tape = { you = { name = "Marcus Reed", record = { w = 12, l = 1, d = 0, ko = 9 }, nick = "The Hammer", nat = "US" }, opp = { name = "Dmitri Volkov", record = { w = 20, l = 3, d = 1, ko = 14 }, nat = "RU" } }
fire:Fire({ t = "start", rounds = 12, tape = tape, kind = "Title Fight", venue = "Arena", venueName = "Grand Arena", moves = Moves.List, stakes = { "WBC" } })
S.settle(0.2)
fire:Fire({ t = "round", n = 1, total = 12 })
fire:Fire({ t = "countdown", n = 0, round = 1 })
fire:Fire({ t = "state", time = 170, me = { hp = 80, cap = 100, body = 70, bodyCap = 100, stam = 60, max = 100, stamCap = 100, conc = 0, tier = 1, bal = 80 }, opp = { hp = 60, cap = 90, body = 50, bodyCap = 100, stam = 40, max = 100, stamCap = 100, conc = 0, tier = 1 } })
S.settle(1.2)
local items = S.collect()
print("items", #items)
local c = S.checks(items)
for k, list in pairs(c) do
	print(k, #list)
	for i, e in ipairs(list) do
		if i <= 25 then
			local it = e.item
			print(string.format("   %-70s %4d,%4d %4dx%-4d %s", it.path:sub(-70), it.x, it.y, it.w, it.h, tostring(e.over or e.size or e.need or e.px or "")))
		end
	end
end
GS.WriteBoxes("/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/fight_" .. S.name .. ".json", S, items)
process.exit(0)
