--!nocheck
-- tools/sim/test_crowd.luau: the fight venues' crowd and stands (src/server/Crowd.lua, src/client/modules/CrowdFX.lua
-- through Venues.New), built offline by tools/sim/crowd_scene.luau at a low house and a packed one:
--   * every fan is a cheap rig (no Builder NPC): the ringside row and the boxes full rigs (torso, head, two arms, a lap
--     or legs, a hat or bald, a phone), the next row lite rigs; fans and their parts never collide, query or touch
--   * the fill: Venues.CrowdFill drives it (a 0.41 house seats fewer fans than a packed one, the front rows first),
--     packed = every seat plus the standing room (standers only when packed), the printed rows drawn fuller
--   * variety: builds, skin tones, drawn faces (the head decals), hats, clothing styles and colours, no two the same
--   * the stands: tiered rows (tread tops at row * rowRise + 0.5), seat rows, stair lights, VIP boxes with glass and
--     leather seats, a media box with monitors, camera platforms, a photographers' pit, sponsor boards, LED fascias,
--     the upper bowl (Arena / Stadium) with its printed tiers
--   * keep-outs: nothing of the crowd's inside the ring, the walkway lanes, the stool corners or the floor cameras
--   * budgets: crowd + stands parts under the caps per venue at a packed house
--   * reactions: 0.9 s into a knockdown wave the ringside rigs are up (torsos and arms higher than at rest), the
--     printed fans' arms rotated; the wave runs outward (near the ring before 60 studs out); Crowd.React writes the
--     arena attribute CrowdFX listens to
--   lune run tools/sim/test_crowd.luau [--keep]   (~20 s; --keep leaves the dump in tools/sim/out/crowd_test)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end

local ROOT = (function()
	local src = debug.info(1, "s"):gsub("^@", "")
	return src:gsub("/tools/sim/[^/]*$", "")
end)()
local OUT = ROOT .. "/tools/sim/out/crowd_test"

local r = process.exec("lune", { "run", ROOT .. "/tools/sim/crowd_scene.luau", "--out", OUT }, { cwd = ROOT })
if not r.ok then
	print(r.stderr)
end
local log = (r.stdout or "") .. (r.stderr or "")
local errs = {}
for line in log:gmatch("[^\n]+") do
	if line:find("%[crowd_scene%]") or line:find("%[Venues%]") and not line:find("athlete") then
		table.insert(errs, line)
	end
end
check("the venues and the crowd build without errors", #errs == 0, table.concat(errs, "\n  "))
local scene = serde.decode("json", fs.readFile(OUT .. "/scene.json"))
local counts = scene.crowd

local KINDS = { "CommunityCenter", "ClubArena", "Arena", "Stadium" }
-- half, size, tier, ringH, floor cameras (Venues.Specs cameras: the keep-outs)
local SPEC = { CommunityCenter = { 10, 110, 1, 2, 0 }, ClubArena = { 11, 150, 2, 3, 1 }, Arena = { 12, 220, 3, 4, 3 }, Stadium = { 13, 330, 4, 4.5, 4 } }
-- crowd + stands parts at a packed house (the template's crowd; a Stadium clone also carries ~600 other parts)
local CAPS = { CommunityCenter = 700, ClubArena = 1200, Arena = 1600, Stadium = 2000 }

local function partsOf(name)
	local root = scene.roots[name]
	local idx = scene.crowdParts[name]
	local out = {}
	for _, i in ipairs(idx) do
		table.insert(out, root.parts[i])
	end
	return out, root
end

local function byName(parts)
	local out = {}
	for _, p in ipairs(parts) do
		out[p.n] = out[p.n] or {}
		table.insert(out[p.n], p)
	end
	return out
end

local function distinct(list, key)
	local seen, n = {}, 0
	for _, p in ipairs(list) do
		local k = key(p)
		if k and not seen[k] then
			seen[k] = true
			n += 1
		end
	end
	return n
end

local function colKey(c)
	return string.format("%.2f,%.2f,%.2f", c[1], c[2], c[3])
end

-- a part's AABB
local function aabb(p)
	local cf, s = p.cf, p.s
	local hx, hy, hz = s[1] / 2, s[2] / 2, s[3] / 2
	local ex = math.abs(cf[4]) * hx + math.abs(cf[5]) * hy + math.abs(cf[6]) * hz
	local ey = math.abs(cf[7]) * hx + math.abs(cf[8]) * hy + math.abs(cf[9]) * hz
	local ez = math.abs(cf[10]) * hx + math.abs(cf[11]) * hy + math.abs(cf[12]) * hz
	return { cf[1] - ex, cf[2] - ey, cf[3] - ez }, { cf[1] + ex, cf[2] + ey, cf[3] + ez }
end
local function overlap(lo, hi, lo2, hi2, m)
	for i = 1, 3 do
		if hi[i] - m <= lo2[i] or lo[i] + m >= hi2[i] then
			return false
		end
	end
	return true
end

for _, kind in ipairs(KINDS) do
	local half, S, tier, ringH, nCams = SPEC[kind][1], SPEC[kind][2], SPEC[kind][3], SPEC[kind][4], SPEC[kind][5]
	local low, max = counts[kind .. "_low"], counts[kind .. "_max"]
	check(kind .. ": built at both houses", low and max)
	if low and max then
		-- 1. the fill
		check(kind .. ": the low house is Venues.CrowdFill's 0.41", math.abs((tonumber(low.share) or 0) - 0.41) < 0.02, low.share)
		check(kind .. ": a packed house", tonumber(max.share) == 1, max.share)
		check(kind .. ": the low house seats fewer fans", low.fans < max.fans * 0.75, low.fans .. " / " .. max.fans)
		check(kind .. ": the packed house keeps every seat (no empty rig seat)", max.fans >= 40, max.fans)
		if tier >= 2 then
			check(kind .. ": standing room only when packed", low.standing == 0 and max.standing > 0, low.standing .. " / " .. max.standing)
			check(kind .. ": VIP fans", max.vip >= 8, max.vip)
		end
		check(kind .. ": the supporters' signs come with the fans", max.signs >= 6 and low.signs <= max.signs, low.signs .. " / " .. max.signs)
		check(kind .. ": press at ringside", max.press >= 1, max.press)
		if tier >= 3 then
			check(kind .. ": the upper bowl", max.bowlTiers == 4, max.bowlTiers)
		else
			check(kind .. ": no upper bowl", max.bowlTiers == 0, max.bowlTiers)
		end
		-- 2. the budget
		check(kind .. ": crowd + stands under the cap at a packed house", max.parts <= CAPS[kind], max.parts .. " > " .. CAPS[kind])
		print(string.format("%-16s packed: %4d crowd+stands parts (cap %4d), %3d fans (%d full, %d lite, %d VIP, %d standing, %d press), %d printed rows, %d bowl tiers; low house: %3d fans, %4d parts",
			kind, max.parts, CAPS[kind], max.fans, max.full, max.lite, max.vip, max.standing, max.press, max.prints, max.bowlTiers, low.fans, low.parts))
	end
	local parts, root = partsOf(kind .. "_max")
	local named = byName(parts)
	local fans = named.Fan or {}
	-- 3. the rigs: cheap, never physical
	do
		local bad = 0
		for _, p in ipairs(parts) do
			if (p.n == "Fan" or p.n == "Head" or p.n == "ArmL" or p.n == "ArmR" or p.n == "Lap" or p.n == "Legs" or p.n == "Hat" or p.n == "Phone" or p.n == "FanSign") and (p.cc ~= false or p.cq ~= false or p.ct ~= false) then
				bad += 1
			end
		end
		check(kind .. ": fans never collide / query / touch", bad == 0, bad)
		check(kind .. ": every fan has a head and two arms", #(named.Head or {}) >= #fans and #(named.ArmL or {}) >= #fans and #(named.ArmR or {}) >= #fans,
			string.format("%d fans, %d heads, %d / %d arms", #fans, #(named.Head or {}), #(named.ArmL or {}), #(named.ArmR or {})))
		local lapOrLegs = #(named.Lap or {}) + #(named.Legs or {})
		check(kind .. ": the full rigs sit on a lap or stand on legs", lapOrLegs >= counts[kind .. "_max"].full * 0.95, lapOrLegs .. " / " .. counts[kind .. "_max"].full)
		local hats = #(named.Hat or {})
		check(kind .. ": hats on some fans, not all (BaldMode: caps or bald)", hats >= #fans * 0.2 and hats <= #fans * 0.7, hats .. " / " .. #fans)
		local phones = #(named.Phone or {})
		check(kind .. ": phones held up", phones >= 4, phones)
		local perFan = #parts / math.max(1, #fans)
		local _ = perFan
	end
	-- 4. variety
	do
		check(kind .. ": shirt colours vary", distinct(fans, function(p)
			return colKey(p.col)
		end) >= 10)
		check(kind .. ": skin tones vary", distinct(named.Head or {}, function(p)
			return colKey(p.col)
		end) >= 7)
		check(kind .. ": builds vary", distinct(fans, function(p)
			return string.format("%.2fx%.2f", p.s[1], p.s[2])
		end) >= math.min(30, #fans * 0.5))
		-- the drawn faces: a Decal on every head wearing one of several faces
		local faces, heads = {}, 0
		local headIdx = {}
		for i, p in ipairs(root.parts) do
			if p.n == "Head" then
				headIdx[i] = true
			end
		end
		for _, dc in ipairs(root.decals or {}) do
			if headIdx[dc.part] and dc.tex:find("rbxassetid") then
				heads += 1
				faces[dc.tex] = true
			end
		end
		local nf = 0
		for _ in pairs(faces) do
			nf += 1
		end
		check(kind .. ": the fans wear drawn faces, several of them", heads >= #fans * 0.9 and nf >= 5, heads .. " faced heads, " .. nf .. " faces")
		-- clothing styles: jerseys print a number, suits a shirt and tie (SurfaceGuis on torsos)
		local fanIdx = {}
		for i, p in ipairs(root.parts) do
			if p.n == "Fan" then
				fanIdx[i] = true
			end
		end
		local prints = 0
		for _, g in ipairs(root.guis or {}) do
			if fanIdx[g.part] then
				prints += 1
			end
		end
		check(kind .. ": clothing styles print (jerseys, jackets, suits)", prints >= #fans * (tier >= 2 and 0.15 or 0.08), prints .. " / " .. #fans)
	end
	-- 5. the stands
	do
		check(kind .. ": tiered stands", #(named.Stand or {}) >= (tier == 1 and 0 or 8), #(named.Stand or {}))
		if tier >= 2 then
			check(kind .. ": stair lights on the aisles", #(named.StairLight or {}) >= 8, #(named.StairLight or {}))
			check(kind .. ": VIP boxes with glass rails and leather seats", #(named.VIPGlass or {}) >= 2 and #(named.VIPSeat or {}) >= 8, #(named.VIPGlass or {}) .. " / " .. #(named.VIPSeat or {}))
			check(kind .. ": camera platforms", #(named.CamRiser or {}) >= 1, #(named.CamRiser or {}))
			check(kind .. ": sponsor boards", #(named.SponsorBoard or {}) >= 4, #(named.SponsorBoard or {}))
			check(kind .. ": printed rows behind the rigs", #(named.RowPrint or {}) >= 8, #(named.RowPrint or {}))
			check(kind .. ": a standing-room rail", #(named.StandRail or {}) >= 4, #(named.StandRail or {}))
			check(kind .. ": ringside chairs", #(named.ChairSeat or {}) >= 20, #(named.ChairSeat or {}))
		end
		if tier >= 3 then
			check(kind .. ": a media box with monitors", #(named.MediaDesk or {}) >= 1 and #(named.Monitor or {}) >= 2, #(named.Monitor or {}))
			check(kind .. ": LED fascias", #(named.LEDRibbon or {}) >= 8, #(named.LEDRibbon or {}))
			check(kind .. ": the bowl's printed tiers", #(named.BowlTier or {}) == 4)
		end
		check(kind .. ": a photographers' pit", #(named.Camera or {}) >= (tier >= 2 and 4 or 1), #(named.Camera or {}))
		-- tread tops where VenueDetail's nosings expect them: Stand tops at row * rowRise + 0.5
		local rise = ({ 0, 2.2, 2.5, 3.2 })[tier]
		local floorY = scene.cameras[kind .. "_max"][2] - ringH
		local bad = 0
		for _, p in ipairs(named.Stand or {}) do
			local top = p.cf[2] + p.s[2] / 2 - floorY
			if rise > 0 then
				local row = (top - 0.5) / rise
				if math.abs(row - math.floor(row + 0.5)) > 0.02 then
					bad += 1
				end
			end
		end
		check(kind .. ": tread tops on the venue's rake", bad == 0, bad)
	end
	-- 6. keep-outs (venue space: the ring centre is scene.cameras[name])
	do
		local cam = scene.cameras[kind .. "_max"]
		local cx, cz = cam[1], cam[3]
		local fy = cam[2] - ringH
		local E = half + 3.2
		local boxes = {
			{ "ring and apron", { cx - E, fy - 1, cz - E }, { cx + E, fy + 12, cz + E } },
			{ "red stool corner", { cx - half - 7.2, fy + 0.1, cz - half - 7.2 }, { cx - half - 2.8, fy + 4, cz - half - 2.8 } },
			{ "blue stool corner", { cx + half + 2.8, fy + 0.1, cz + half + 2.8 }, { cx + half + 7.2, fy + 4, cz + half + 7.2 } },
			{ "red walkway lane", { cx - 3, fy + 0.25, cz - S / 2 + 4 }, { cx + 3, fy + 9, cz - E - 6 } },
			{ "blue walkway lane", { cx - 3, fy + 0.25, cz + E + 6 }, { cx + 3, fy + 9, cz + S / 2 - 4 } },
		}
		local spots = { { half + 6.2, -(half + 6.2) }, { -(half + 6.2), half + 6.2 }, { 5.8, E + 7 }, { 5.8, -(E + 7) } }
		for i = 1, nCams do
			local sp = spots[i]
			table.insert(boxes, { "floor camera", { cx + sp[1] - 1.5, fy + 0.1, cz + sp[2] - 1.5 }, { cx + sp[1] + 1.5, fy + 7, cz + sp[2] + 1.5 } })
		end
		local hits = {}
		for _, p in ipairs(parts) do
			if p.t < 0.99 and p.n ~= "FanBanner" then
				local lo, hi = aabb(p)
				for _, k in ipairs(boxes) do
					if overlap(lo, hi, k[2], k[3], 0.05) then
						table.insert(hits, string.format("%s in %s at (%.1f, %.1f, %.1f)", p.n, k[1], p.cf[1] - cx, p.cf[2], p.cf[3] - cz))
					end
				end
			end
		end
		check(kind .. ": the crowd keeps the ring, lanes, corners and cameras clear", #hits == 0, #hits .. "\n  " .. table.concat(hits, "\n  ", 1, math.min(#hits, 12)))
	end
	-- 7. the printed rows are drawn (fans on the slabs), fuller when packed
	do
		local function drawn(name)
			local rt = scene.roots[name]
			local slabIdx = {}
			for i, p in ipairs(rt.parts) do
				if p.n == "RowPrint" then
					slabIdx[i] = true
				end
			end
			local items, slabs = 0, 0
			for _, g in ipairs(rt.guis or {}) do
				if slabIdx[g.part] then
					slabs += 1
					items += #g.items
				end
			end
			return items, slabs
		end
		local iMax, sMax = drawn(kind .. "_max")
		local iLow = drawn(kind .. "_low")
		if tier >= 2 then
			check(kind .. ": the printed rows carry fans (packed)", sMax >= 8 and iMax >= sMax * 20, iMax .. " items on " .. sMax .. " slabs")
			check(kind .. ": the printed rows thin out with the house", iLow < iMax * 0.8, iLow .. " / " .. iMax)
		end
	end
	-- 8. the reaction frame
	do
		local rparts = partsOf(kind .. "_max_react")
		local rn = byName(rparts)
		local up, n = 0, 0
		local cam = scene.cameras[kind .. "_max"]
		for i, p in ipairs(fans) do
			local q = (rn.Fan or {})[i]
			if q and math.abs(p.cf[1] - cam[1]) < 60 and math.abs(p.cf[3] - cam[3]) < 60 then
				n += 1
				if q.cf[2] > p.cf[2] + 0.3 then
					up += 1
				end
			end
		end
		check(kind .. ": 0.9 s into a knockdown the fans near the ring are up out of their seats", n > 0 and up >= n * 0.3, up .. " / " .. n)
		local armsUp, an = 0, 0
		for i, p in ipairs(named.ArmR or {}) do
			local q = (rn.ArmR or {})[i]
			if q and math.abs(p.cf[1] - cam[1]) < 60 and math.abs(p.cf[3] - cam[3]) < 60 then
				an += 1
				if q.cf[2] > p.cf[2] + 0.5 then
					armsUp += 1
				end
			end
		end
		check(kind .. ": arms in the air", an > 0 and armsUp >= an * 0.3, armsUp .. " / " .. an)
		if tier >= 2 then
			local rt = scene.roots[kind .. "_max_react"]
			local slabIdx = {}
			for i, p in ipairs(rt.parts) do
				if p.n == "RowPrint" then
					slabIdx[i] = true
				end
			end
			local rotated, total = 0, 0
			for _, g in ipairs(rt.guis or {}) do
				if slabIdx[g.part] then
					for _, it in ipairs(g.items) do
						if it.rot then
							total += 1
							if math.abs(it.rot) > 60 then
								rotated += 1
							end
						end
					end
				end
			end
			check(kind .. ": the printed fans' arms swing up in the wave", total > 0 and rotated >= total * 0.2, rotated .. " / " .. total)
		end
	end
end

-- the wave runs outward and fades; Crowd.React writes the attribute CrowdFX listens to
do
	local w = scene.wave and scene.wave.Stadium_max_react
	check("the wave reaches the ringside before the far rows", w and w.near > 0.5 and w.far < w.near, w and (w.near .. " / " .. w.far))
	check("the wave reaches the far rows later", w and w.later > 0.5, w and w.later)
	check("Crowd.React writes the arena attribute (event|who|extra|seq)", type(scene.reactAttr) == "string" and scene.reactAttr:match("^knockdown|opp|[^|]*|%d+$") ~= nil, scene.reactAttr)
end

if not table.find(process.args, "--keep") then
	pcall(fs.removeDir, OUT)
end
print(string.format("test_crowd: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_crowd failed")
end
