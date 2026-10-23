--!nocheck
-- fit HitGeometry.TARGET / WIDE to tools/sim/anim_reach.json (every pairing), printing the numbers and the worst error
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Host = require("./host")
local H = Host.new()
local HG = H.require("HitGeometry")
local AR = serde.decode("json", fs.readFile(H.root .. "/tools/sim/anim_reach.json"))
local RIG, CAL, TARGET, WIDE = HG.RIG, HG.CAL, HG.TARGET, HG.WIDE
local function recal(p, zone)
	local lo, hi = 0.2, 4
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		CAL[p][zone] = mid
		if HG.Test(RIG, RIG, p, zone == "body", TARGET[p][zone], { noRedirect = true }).ok then
			hi = mid
		else
			lo = mid
		end
	end
	CAL[p][zone] = hi
end
local function hgB(A, B, p, body)
	local floor = HG.MinSep(A, B) + 0.3
	local last = nil
	local d = HG.MinSep(A, B) - 0.4
	while d <= 8 do
		if HG.Test(A, B, p, body, d, { floor = floor, noRedirect = true }).ok then
			last = d
		end
		d += 0.01
	end
	return last or 0
end
local KEYS = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand", "jab|body", "cross|body", "leadhook|body", "rearhook|body", "uppercut|body" }
local out = { target = {}, wide = {} }
local worstAll = 0
for _, key in ipairs(KEYS) do
	local p, z = key:match("^(%a+)|?(%a*)$")
	local zone = z == "body" and "body" or "head"
	local body = zone == "body"
	for _ = 1, 4 do
		-- residuals and the least squares for (dT, dW) on x = the attacker's width past RIG's
		local sx, sy, sxx, sxy, n = 0, 0, 0, 0, 0
		for _, pr in ipairs(AR.pairs) do
			local x = pr.geoA.torsoHalfW - RIG.torsoHalfW
			local r = pr.boundary[key] - hgB(pr.geoA, pr.geoB, p, body)
			sx += x; sy += r; sxx += x * x; sxy += x * r; n += 1
		end
		local den = n * sxx - sx * sx
		local dW = den > 1e-9 and (n * sxy - sx * sy) / den or 0
		local dT = (sy - dW * sx) / n
		-- (the minimax: centre the residual band after the slope)
		TARGET[p][zone] += dT
		WIDE[p][zone] += dW
		recal(p, zone)
	end
	-- the band: shift so the worst errors either side balance
	local lo, hi = math.huge, -math.huge
	for _, pr in ipairs(AR.pairs) do
		local r = pr.boundary[key] - hgB(pr.geoA, pr.geoB, p, body)
		lo, hi = math.min(lo, r), math.max(hi, r)
	end
	TARGET[p][zone] += (lo + hi) / 2
	recal(p, zone)
	local worst = 0
	for _, pr in ipairs(AR.pairs) do
		worst = math.max(worst, math.abs(pr.boundary[key] - hgB(pr.geoA, pr.geoB, p, body)))
	end
	worstAll = math.max(worstAll, worst)
	print(string.format("%-14s target %.3f wide %.3f worst %.3f", key, TARGET[p][zone], WIDE[p][zone], worst))
	out.target[p] = out.target[p] or {}
	out.wide[p] = out.wide[p] or {}
	out.target[p][zone] = TARGET[p][zone]
	out.wide[p][zone] = WIDE[p][zone]
end
out.target.overhand.body = out.target.overhand.head
out.wide.overhand.body = out.wide.overhand.head
out.rig = RIG
print(string.format("worst over all %.3f", worstAll))
fs.writeFile("/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/reach/fit1.json", serde.encode("json", out))
