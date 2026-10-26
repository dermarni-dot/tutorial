--!nocheck
-- tools/sim/hg_fit.luau: fit HitGeometry to tools/sim/anim_reach.json - AnimFight's visible reach over every frame pairing
-- (pairs) and every height pairing (heights), measured by `lune run tools/sim/v9_anim.luau --clips reach ...` (README):
-- per punch and zone the target on the Athletic rig (HitGeometry.TARGET, on HitGeometry.RIG) and the reach per stud of
-- torso half width (WIDE), least squares; with --kinds N also each punch kind's shape (HitGeometry.KIND: the origin, the
-- angles, how far up and down it gets, the rise, the body shot's dip) by a coordinate search of N rounds over the
-- boundaries (the far edge where the glove stops reaching; a punch the animation never lands from 3.2 must not land past
-- it; one it lands only from `near` out not well inside that). Prints the tables and the worst error per punch
-- (test_hitdetect holds it to 0.25 stud on the pairs, 0.3 on the heights). Paste the numbers into HitGeometry.
--   lune run tools/sim/hg_fit.luau [--kinds 14] [--json FILE]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Host = require("./host")
local H = Host.new()
local HG = H.require("HitGeometry")
local argv = {}
do
	local i = 1
	while i <= #process.args do
		argv[process.args[i]:gsub("^%-%-", "")] = process.args[i + 1]
		i += 2
	end
end
local AR = serde.decode("json", fs.readFile(argv.json or (H.root .. "/tools/sim/anim_reach.json")))
local ITER = tonumber(argv.kinds) or 0
local RIG, CAL, TARGET, WIDE, KIND = HG.RIG, HG.CAL, HG.TARGET, HG.WIDE, HG.KIND
local KEYS = { "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand", "jab|body", "cross|body", "leadhook|body", "rearhook|body", "uppercut|body" }
local ALL = {}
for _, pr in ipairs(AR.pairs) do
	table.insert(ALL, pr)
end
for _, pr in ipairs(AR.heights or {}) do
	table.insert(ALL, pr)
end
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
	-- (the sims' frames: their own calibration on the unit, the same target)
	local CS = HG.CAL_SCALES
	if CS then
		local U = HG.Unit()
		lo, hi = 0.2, 4
		for _ = 1, 40 do
			local mid = (lo + hi) / 2
			CS[p][zone] = mid
			if HG.Test(U, U, p, zone == "body", TARGET[p][zone], { noRedirect = true }).ok then
				hi = mid
			else
				lo = mid
			end
		end
		CS[p][zone] = hi
	end
end
-- the last distance it lands from, scanning out from MinSep - 0.4 (as test_hitdetect); 0 when it never does
local function hgB(A, B, p, body)
	local sep = HG.MinSep(A, B)
	local last, first
	local d = 3.2
	while d <= 8 do
		if HG.Test(A, B, p, body, d, { noRedirect = true }).ok then
			last = d
			first = first or d
		elseif last then
			break
		end
		d += 0.04
	end
	return last or 0, first, sep
end
local function err(pr, key)
	local p, z = key:match("^(%a+)|?(%a*)$")
	local body = z == "body"
	local hb, hf = hgB(pr.geoA, pr.geoB, p, body)
	local ab = pr.boundary[key]
	local an = pr.near and pr.near[key]
	if ab <= 0 then
		-- (the animation does not land even from 3.2: the test must not land past it)
		return math.max(0, hb - 3.2)
	end
	if hb <= 0 then
		return ab - 3.2 + 0.3
	end
	local e = hb - ab
	-- (and it lands only from `near` out - a straight up at a taller man's chin too close - the test should not land
	-- well inside that)
	if an and an > 3.3 and hf and hf < an - 0.2 then
		local en = an - 0.2 - hf
		if en > math.abs(e) then
			e = -en
		end
	end
	return e
end
-- TARGET / WIDE for a key, least squares on the frame pairs + heights, then the band centred
local function fitTW(key)
	local p, z = key:match("^(%a+)|?(%a*)$")
	local zone = z == "body" and "body" or "head"
	for _ = 1, 3 do
		local sx, sy, sxx, sxy, n = 0, 0, 0, 0, 0
		for _, pr in ipairs(ALL) do
			if pr.boundary[key] > 0 then
				local x = pr.geoA.torsoHalfW - RIG.torsoHalfW
				local r = -err(pr, key)
				sx += x
				sy += r
				sxx += x * x
				sxy += x * r
				n += 1
			end
		end
		if n == 0 then
			return
		end
		local den = n * sxx - sx * sx
		local dW = den > 1e-9 and (n * sxy - sx * sy) / den or 0
		local dT = (sy - dW * sx) / n
		TARGET[p][zone] += dT * 0.9
		WIDE[p][zone] += dW * 0.9
		recal(p, zone)
	end
end
-- (per punch: HitGeometry.Test takes KIND[ptype] before KIND[kind]; the fit gives each punch its own)
local KIND_KEYS = { jab = { "jab", "jab|body" }, cross = { "cross", "cross|body" }, leadhook = { "leadhook", "leadhook|body" },
	rearhook = { "rearhook", "rearhook|body" }, uppercut = { "uppercut", "uppercut|body" }, overhand = { "overhand" } }
local KIND_OF = { jab = "straight", cross = "straight", leadhook = "hook", rearhook = "hook", uppercut = "uppercut", overhand = "overhand" }
for p, k in pairs(KIND_OF) do
	if not KIND[p] then
		KIND[p] = table.clone(KIND[k])
	end
end
local function score(kind)
	local s, worst, n = 0, 0, 0
	for _, key in ipairs(KIND_KEYS[kind]) do
		for _, pr in ipairs(ALL) do
			local e = err(pr, key)
			s += e * e
			worst = math.max(worst, math.abs(e))
			n += 1
		end
	end
	return math.sqrt(s / n) + 0.5 * worst, worst, math.sqrt(s / n)
end
local PARAMS = { "o", "up", "down", "vUp", "vDown", "rise", "dip", "stepH" }
local STEP = { o = 0.05, up = 4, down = 4, vUp = 0.08, vDown = 0.08, rise = 0.05, dip = 0.05, stepH = 0.15 }
local function refit(kind)
	for _, key in ipairs(KIND_KEYS[kind]) do
		fitTW(key)
	end
end
local function fitKinds()
	for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
		local K = KIND[kind]
		refit(kind)
		local best = score(kind)
		local step = table.clone(STEP)
		for it = 1, ITER do
			local improved = false
			for _, pn in ipairs(PARAMS) do
				for _, sg in ipairs({ 1, -1 }) do
					local old = K[pn]
					K[pn] = (old or HG.SHAPE.stepH) + sg * step[pn]
					if pn == "vDown" and old and old < 0 then
						-- (the free way down - max(Rh, arm) - against a real limit: try one)
						K[pn] = sg > 0 and 1.3 or 1.0
					end
					local saveT, saveW = {}, {}
					for _, key in ipairs(KIND_KEYS[kind]) do
						local p, z = key:match("^(%a+)|?(%a*)$")
						local zone = z == "body" and "body" or "head"
						saveT[key], saveW[key] = TARGET[p][zone], WIDE[p][zone]
					end
					refit(kind)
					local sc = score(kind)
					if sc < best - 1e-4 then
						best = sc
						improved = true
					else
						K[pn] = old
						for _, key in ipairs(KIND_KEYS[kind]) do
							local p, z = key:match("^(%a+)|?(%a*)$")
							local zone = z == "body" and "body" or "head"
							TARGET[p][zone], WIDE[p][zone] = saveT[key], saveW[key]
							recal(p, zone)
						end
					end
				end
			end
			if not improved then
				for k, v in pairs(step) do
					step[k] = v / 2
				end
			end
		end
		local _, worst, rms = score(kind)
		print(string.format("%s: o %.3f up %.1f down %.1f vUp %.3f vDown %.3f rise %.3f dip %.3f   rms %.3f worst %.3f", kind, K.o, K.up, K.down, K.vUp, K.vDown, K.rise, K.dip, rms, worst))
	end
end
-- the zones' aimed bands (HitGeometry.ZONE), over every punch, then the kinds' TARGET / WIDE again
local function total()
	local s2, n = 0, 0
	for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
		local a = score(kind)
		s2 += a
		n += 1
	end
	return s2 / n
end
local function fitZone()
	if ITER > 0 then
		local Z = HG.ZONE
		local zs = { { Z.head, 1 }, { Z.head, 2 }, { Z.body, 1 }, { Z.body, 2 }, { HG.SHAPE, "stepH" } }
		local step = 0.1
		for kindRefits = 1, 2 do
			for _ = 1, ITER do
				local improved = false
				for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
					refit(kind)
				end
				local best = total()
				for _, zz in ipairs(zs) do
					for _, sg in ipairs({ 1, -1 }) do
						local old = zz[1][zz[2]]
						zz[1][zz[2]] = old + sg * step
						for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
							refit(kind)
						end
						local sc = total()
						if sc < best - 1e-4 then
							best = sc
							improved = true
						else
							zz[1][zz[2]] = old
						end
					end
				end
				if not improved then
					step /= 2
				end
			end
			print(string.format("ZONE (round %d): head { %.3f, %.3f } body { %.3f, %.3f }  SHAPE.stepH %.3f  score %.3f", kindRefits, Z.head[1], Z.head[2], Z.body[1],
			Z.body[2], HG.SHAPE.stepH, total()))
		end
		for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
			refit(kind)
		end
	end
end
fitKinds()
fitZone()
if ITER > 0 then
	fitKinds()
end
print("KIND:")
for _, kind in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
	local K = KIND[kind]
	print(string.format("\t%s = { o = %.3f, up = %.1f, down = %.1f, vUp = %.3f, vDown = %.3f, rise = %.3f, dip = %.3f%s },", kind, K.o, K.up, K.down, K.vUp, K.vDown,
		K.rise, K.dip, K.stepH and string.format(", stepH = %.3f", K.stepH) or ""))
end
print("TARGET / WIDE:")
for _, p in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
	print(string.format("\t%s = { head = %.2f, body = %.2f },  wide { head = %.2f, body = %.2f }", p, TARGET[p].head, TARGET[p].body, WIDE[p].head, WIDE[p].body))
end
-- the worst per key
for _, key in ipairs(KEYS) do
	local w, wh = 0, ""
	for _, pr in ipairs(ALL) do
		local e = err(pr, key)
		if math.abs(e) > math.abs(w) then
			w = e
			wh = string.format("%s->%s %s->%s", pr.frame, pr.oframe, tostring(pr.height or ""), tostring(pr.oheight or ""))
		end
	end
	print(string.format("  %-14s worst %+.3f (%s)", key, w, wh))
end
