--!nocheck
local Host = require("./host")
local Bots = require("./drillbots")
local H = Host.new()
local DrillScore = H.require("DrillScore")
local W = DrillScore.Workouts
local Random = H.globals.Random
for _, lvw in ipairs({ 1, 1.5, 2, 2.5, 3, 4, 5 }) do
	local sumQ, n, verdicts, pulls = 0, 0, {}, 0
	for k = 1, 12 do
		local segs = W.Plan("pullup", lvw, {}, Random.new(100 + k), DrillScore.WAIT)
		local rng = Random.new(500 + k)
		for _, seg in ipairs(segs) do
			local j = DrillScore.Judge(seg, 0)
			local mem, t = {}, 0
			while t < 60 do
				j.advance(t)
				if j.closed then break end
				for _, a in ipairs(Bots.Act(seg, j, t, 0, mem, Bots.SKILLS.average, rng)) do
					j.input(a[1], a[2], t)
				end
				if j.closed then break end
				t += 1 / 60
			end
			j.finish(t)
			local r = j.result()
			sumQ += r.q; n += 1; pulls += r.pulls
			verdicts[r.verdict] = (verdicts[r.verdict] or 0) + 1
		end
	end
	local vs = {}
	for v, c in pairs(verdicts) do table.insert(vs, v .. "=" .. c) end
	table.sort(vs)
	print(string.format("W lv %.1f  avg q %.3f  pulls/rep %.1f  %s", lvw, sumQ / n, pulls / n, table.concat(vs, " ")))
end
