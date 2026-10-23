--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[1] ~= "" and process.args[1]) or nil })
local Fight = S.FightEngine._Fight
local st = { n = 0, short = 0, stretchSum = 0, ok = 0, dist = 0 }
local oldHT = Fight.HitTest
local inResolve = false
local oldR = Fight.Resolve
Fight.Resolve = function(self, F, O, ...)
	inResolve = true
	local r = table.pack(oldR(self, F, O, ...))
	inResolve = false
	return table.unpack(r, 1, r.n)
end
Fight.HitTest = function(self, F, O, p, body, dist, ...)
	local h = oldHT(self, F, O, p, body, dist, ...)
	if inResolve then
		inResolve = false
		st.n += 1; st.dist += dist
		if h.ok then
			st.ok += 1
			st[h.zone .. (h.redirected and "R" or "")] = (st[h.zone .. (h.redirected and "R" or "")] or 0) + 1
			st[p] = (st[p] or 0) + 1
			if type(h.margin) == "number" and type(h.reach) == "number" and h.reach > 0 then
				st.stretchSum += 1 - math.clamp(h.margin / (0.18 * h.reach), 0, 1)
			end
		else
			st.short += 1
		end
	end
	return h
end
local miss = {}
local oldM = Fight.Miss
Fight.Miss = function(self, F, O, p, why)
	miss[why] = (miss[why] or 0) + 1
	return oldM(self, F, O, p, why)
end
local STY = { "OutBoxer", "Swarmer", "Slugger", "BoxerPuncher", "CounterPuncher" }
local blockedT, n = 0, 0
for i = 1, 16 do
	local r = S.Fight({ red = { style = STY[(i % 5) + 1], level = 60 }, blue = { style = STY[((i + 2) % 5) + 1], level = 60 }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f) if f.live then n += 1; if f.O.blocking then blockedT += 1 end end end })
end
local t = {}
for k, v in pairs(miss) do table.insert(t, k .. " " .. v) end
print(string.format("hits head %d body %d redirected %d | jab %d cross %d lhook %d rhook %d upper %d over %d", st.head or 0, st.body or 0, st.bodyR or 0, st.jab or 0, st.cross or 0, st.leadhook or 0, st.rearhook or 0, st.uppercut or 0, st.overhand or 0))
print(string.format("resolves %d: geometry ok %.0f%%, avg dist %.2f, avg stretch of hits %.2f | misses %s | AI blocking %.0f%% of time", st.n, st.ok / st.n * 100, st.dist / st.n, st.stretchSum / math.max(1, st.ok), table.concat(t, ", "), blockedT / n * 100))
