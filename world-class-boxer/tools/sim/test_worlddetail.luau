--!nocheck
-- tools/sim/test_worlddetail.luau: the world's client detail layer (WorldDetail: GymDetail + CityDetail, VenueDetail,
-- MenuStage's extras) never gets in the way of play, and stays inside its budget per Graphics level.
--   * builds the world three times (world_scene.luau --level 1 / 2 / 3) and reads the dumps
--   * every detail part: no collision, no queries, no touches (walking, the camera, mouse and fight rays pass through)
--   * keep-outs: no detail part (thicker than a floor decal) inside a station's use / equipment volume, a prompt,
--     an Ambient member's spot, the spawn pad, the gym doors, the entrance path, the lounge stair, the gym ring's
--     canvas, the venue rings' canvas and walkways, Main Street's pedestrian and traffic lanes
--   * budgets: detail parts per level (Low < Medium < High, High under the caps below)
--   * reports (not failures): detail parts overlapping a solid server prop by more than 0.3 studs on every axis
--   lune run tools/sim/test_worlddetail.luau [--keep]   (--keep leaves the dumps in tools/sim/out/wd_test)
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
local OUT = ROOT .. "/tools/sim/out/wd_test"

local function build(level)
	local dir = OUT .. "/L" .. level
	local r = process.exec("lune", { "run", ROOT .. "/tools/sim/world_scene.luau", "--out", dir, "--level", tostring(level) }, { cwd = ROOT })
	if not r.ok then
		print(r.stderr)
	end
	local log = (r.stdout or "") .. (r.stderr or "")
	local errs = {}
	for line in log:gmatch("[^\n]+") do
		if line:find("%[DetailKit%]") or line:find("%[WorldDetail%]") or line:find("%[VenueDetail%]") or line:find("WorldDetail.BuildAll failed") or line:find("VenueDetail.Build .- failed") or line:find("MenuStage.Build failed") then
			table.insert(errs, line)
		end
	end
	check("L" .. level .. ": the detail layer builds without errors", #errs == 0, table.concat(errs, "\n  "))
	return serde.decode("json", fs.readFile(dir .. "/scene.json"))
end

-- AABB of a dumped part
local function aabb(p)
	local cf, s = p.cf, p.s
	local hx, hy, hz = s[1] / 2, s[2] / 2, s[3] / 2
	local ex = math.abs(cf[4]) * hx + math.abs(cf[5]) * hy + math.abs(cf[6]) * hz
	local ey = math.abs(cf[7]) * hx + math.abs(cf[8]) * hy + math.abs(cf[9]) * hz
	local ez = math.abs(cf[10]) * hx + math.abs(cf[11]) * hy + math.abs(cf[12]) * hz
	return { cf[1] - ex, cf[2] - ey, cf[3] - ez }, { cf[1] + ex, cf[2] + ey, cf[3] + ez }
end

-- AABBs overlap by more than margin on every axis (on an axis where either box is thin, by more than a quarter of
-- the thinner extent: two posters on one wall overlap although each is 0.1 thick)
local function overlap(lo, hi, blo, bhi, margin)
	margin = margin or 0
	for i = 1, 3 do
		local m = math.min(margin, 0.25 * math.min(hi[i] - lo[i], bhi[i] - blo[i]))
		if hi[i] <= blo[i] + m or lo[i] >= bhi[i] - m then
			return false
		end
	end
	return true
end

-- the keep-out volumes (min, max) of the world as the server builds it
local KEEP = {}
local function keep(name, lo, hi)
	table.insert(KEEP, { name = name, lo = lo, hi = hi })
end
local function cyl(name, x, z, r, y0, y1)
	keep(name, { x - r, y0 or 0.6, z - r }, { x + r, y1 or 7, z + r })
end
-- stations (MapBuilder.StationDefs: pos = equipment, use = where the boxer trains)
do
	local src = fs.readFile(ROOT .. "/src/server/MapBuilder.lua")
	for id, px, pz, ux, uz in src:gmatch('id = "(%w+)",[^\n]-pos = V3%(([%-%d%.]+), [%-%d%.]+, ([%-%d%.]+)%), use = V3%(([%-%d%.]+), [%-%d%.]+, ([%-%d%.]+)%)') do
		cyl("station use " .. id, tonumber(ux), tonumber(uz), 2.6)
		cyl("station " .. id, tonumber(px), tonumber(pz), 2.2)
	end
	-- Ambient members' spots
	local amb = fs.readFile(ROOT .. "/src/server/Ambient.lua")
	for line in amb:gmatch("[^\n]+") do
		local name, x, z = line:match('name = "([^"]+)",.-at = V3%(([%-%d%.]+), [%-%d%.]+, ([%-%d%.]+)%)')
		if name then
			local floor = tonumber(line:match("floor = ([%d%.]+)")) or 0.5
			cyl("member " .. name, tonumber(x), tonumber(z), 1.6, floor + 0.1, floor + 6)
		end
	end
end
keep("spawn pad", { -5, 0.6, 55 }, { 5, 6, 65 })
keep("south door", { -10, 0.6, 76 }, { 10, 13, 84 })
keep("north door", { -8, 0.6, -84 }, { 8, 13, -76 })
keep("elite door", { 106, 0.6, 44 }, { 114, 13, 56 })
keep("entrance path", { -5, 0.6, 84 }, { 5, 7, 115 })
keep("lounge stair", { 15.8, 0.6, 40 }, { 20.2, 13, 64 })
keep("gym ring canvas", { -10.4, 2.9, -60.4 }, { 10.4, 9, -39.6 })
-- Main Street lanes (CityVisuals: pedestrians at z 166.3 / 184.6, cars at 169.6 / 174.8)
keep("north pedestrian lane", { -330, 0.65, 165.95 }, { 330, 3.2, 166.65 })
keep("south pedestrian lane", { -330, 0.65, 184.25 }, { 330, 3.2, 184.95 })
keep("traffic lanes", { -330, 0.45, 168.2 }, { 330, 4.5, 176.2 })

local function isPrompt(n)
	return n == "PromptPart" or (n:sub(-6) == "Prompt" and n ~= "TimerPrompt")
end

local DETAIL_ROOTS = { "WorldDetail_gym", "WorldDetail_city" }
local SOLID_SKIP = {
	Floor = true, Ground = true, Wall = true, Roof = true, BoxingFloor = true, WeightFloor = true, CardioFloor = true, RecoveryFloor = true,
	ServicesFloor = true, MainStreet = true, SidewalkS = true, SidewalkN = true, ChampionAve = true, AveSidewalk = true, ParkingLot = true,
	Wainscot = true, Baseboard = true, WallStripe = true, Divider = true, Building = true, BuildingUpper = true, Cornice = true,
}

local scenes = {}
for level = 1, 3 do
	scenes[level] = build(level)
end

-- 1. detail parts never collide, query or touch
for level = 1, 3 do
	local bad = {}
	for _, rn in ipairs(DETAIL_ROOTS) do
		local root = scenes[level].roots[rn]
		for _, p in ipairs(root and root.parts or {}) do
			if p.cc ~= false or p.cq ~= false or p.ct ~= false then
				table.insert(bad, rn .. "/" .. p.n)
			end
		end
	end
	check("L" .. level .. ": detail parts are CanCollide / CanQuery / CanTouch false", #bad == 0, table.concat(bad, ", ", 1, math.min(#bad, 8)))
end

-- 2. keep-outs (prompts from the server dump join the list)
local s3 = scenes[3]
for _, p in ipairs(s3.roots.server_gym_and_city.parts) do
	if isPrompt(p.n) then
		local c = p.cf
		cyl("prompt " .. p.n, c[1], c[3], 1.6, c[2] - 3, c[2] + 3)
	end
end
for level = 1, 3 do
	local hits = {}
	for _, rn in ipairs(DETAIL_ROOTS) do
		local root = scenes[level].roots[rn]
		for _, p in ipairs(root and root.parts or {}) do
			local lo, hi = aabb(p)
			local flat = (hi[2] - lo[2]) <= 0.12 -- floor decals, overlays and road paint lie under the feet
			if not flat and p.t < 0.99 then
				for _, k in ipairs(KEEP) do
					if overlap(lo, hi, k.lo, k.hi, 0.02) then
						table.insert(hits, string.format("%s in %s at (%.1f, %.1f, %.1f)", p.n, k.name, p.cf[1], p.cf[2], p.cf[3]))
					end
				end
			end
		end
	end
	check("L" .. level .. ": no detail in a keep-out volume", #hits == 0, #hits .. "\n  " .. table.concat(hits, "\n  ", 1, math.min(#hits, 30)))
end

-- 2b. venues: the ring inside the ropes, the walkway lanes, the corner stools / cornermen and the floor cameras stay
-- clear; VenueDetail never overlaps the template's own solid props (reported)
local VENUES = { CommunityCenter = { 10, 2, 110 }, ClubArena = { 11, 3, 150 }, Arena = { 12, 4, 220 }, Stadium = { 13, 4.5, 330 }, Gym = { 10, 2.5, 70 } }
for level = 1, 3 do
	local sc = scenes[level]
	local hits = {}
	for kind, v in pairs(VENUES) do
		local cam = sc.cameras["venue_" .. kind]
		local root = sc.roots["VenueDetail_" .. kind]
		if cam and root then
			local cx, cz = cam[1], cam[3]
			local half, RH, S = v[1], v[2], v[3]
			local E = half + 3.2
			local boxes = {
				{ "ring inside the ropes", { cx - half + 0.4, RH + 0.1, cz - half + 0.4 }, { cx + half - 0.4, RH + 9, cz + half - 0.4 } },
				{ "red stool corner", { cx - half - 7.2, 0.1, cz - half - 7.2 }, { cx - half - 2.8, 4, cz - half - 2.8 } },
				{ "blue stool corner", { cx + half + 2.8, 0.1, cz + half + 2.8 }, { cx + half + 7.2, 4, cz + half + 7.2 } },
			}
			if kind ~= "Gym" then
				table.insert(boxes, { "red walkway lane", { cx - 3, 0.25, cz - S / 2 + 4 }, { cx + 3, 9, cz - E - 6 } })
				table.insert(boxes, { "blue walkway lane", { cx - 3, 0.25, cz + E + 6 }, { cx + 3, 9, cz + S / 2 - 4 } })
				for _, sp in ipairs({ { half + 6.2, -(half + 6.2) }, { -(half + 6.2), half + 6.2 }, { 5.8, E + 7 }, { 5.8, -(E + 7) } }) do
					table.insert(boxes, { "floor camera", { cx + sp[1] - 1.5, 0.1, cz + sp[2] - 1.5 }, { cx + sp[1] + 1.5, 7, cz + sp[2] + 1.5 } })
				end
			end
			for _, p in ipairs(root.parts) do
				local lo, hi = aabb(p)
				if (hi[2] - lo[2]) > 0.12 and p.t < 0.99 then
					for _, k in ipairs(boxes) do
						if overlap(lo, hi, k[2], k[3], 0.02) then
							table.insert(hits, string.format("%s %s in %s at (%.1f, %.1f, %.1f)", kind, p.n, k[1], p.cf[1] - cx, p.cf[2], p.cf[3] - cz))
						end
					end
				end
			end
		end
	end
	check("L" .. level .. ": venue detail keeps the ring, lanes, corners and cameras clear", #hits == 0, #hits .. "\n  " .. table.concat(hits, "\n  ", 1, math.min(#hits, 30)))
	for _, rn in ipairs({ "VenueDetail_CommunityCenter", "VenueDetail_ClubArena", "VenueDetail_Arena", "VenueDetail_Stadium", "VenueDetail_Gym" }) do
		local root = sc.roots[rn]
		for _, p in ipairs(root and root.parts or {}) do
			if p.cc ~= false or p.cq ~= false or p.ct ~= false then
				check("L" .. level .. ": " .. rn .. " parts never collide / query / touch", false, p.n)
				break
			end
		end
	end
end
do
	local n = 0
	for kind in pairs(VENUES) do
		local base, det = s3.roots["venue_" .. kind], s3.roots["VenueDetail_" .. kind]
		if base and det then
			local solids = {}
			local signed = {}
			for _, g in ipairs(base.guis or {}) do
				signed[g.part] = true
			end
			for i, p in ipairs(base.parts) do
				if not SOLID_SKIP[p.n] and p.n ~= "Fan" and p.n ~= "Head" and (p.t < 0.6 or signed[i]) then
					local lo, hi = aabb(p)
					if (hi[1] - lo[1]) < 60 and (hi[3] - lo[3]) < 60 then
						table.insert(solids, { n = p.n, lo = lo, hi = hi })
					end
				end
			end
			for _, p in ipairs(det.parts) do
				local lo, hi = aabb(p)
				if p.t < 0.99 and (hi[2] - lo[2]) > 0.12 then
					for _, q in ipairs(solids) do
						if overlap(lo, hi, q.lo, q.hi, 0.3) then
							n += 1
							if n <= 400 then
								print(string.format("  venue overlap: %s/%s with %s", kind, p.n, q.n))
							end
							break
						end
					end
				end
			end
		end
	end
	print("venue detail parts overlapping a solid template prop by > 0.3 studs: " .. n)
end

-- 2c. VenueDetail's copy of the venue geometry matches the server's Venues.Specs
for kind, row in pairs(s3.venueSpecs or {}) do
	local bad = {}
	for f, v in pairs(row.server) do
		if row.client[f] ~= v then
			table.insert(bad, string.format("%s server %s client %s", f, tostring(v), tostring(row.client[f])))
		end
	end
	check("VenueDetail.Specs." .. kind .. " matches Venues.Specs", row.hasClient and #bad == 0, table.concat(bad, ", "))
end

-- 3. budgets: monotone in the level, High under the caps
local CAPS = {
	WorldDetail_gym = 2600, WorldDetail_city = 3200, VenueDetail_CommunityCenter = 600, VenueDetail_ClubArena = 900,
	VenueDetail_Arena = 1100, VenueDetail_Stadium = 1300,
}
for _, rn in ipairs({ "WorldDetail_gym", "WorldDetail_city", "VenueDetail_CommunityCenter", "VenueDetail_ClubArena", "VenueDetail_Arena", "VenueDetail_Stadium" }) do
	local c1, c2, c3 = scenes[1].counts[rn], scenes[2].counts[rn], scenes[3].counts[rn]
	local n1, n2, n3 = c1 and c1.parts or 0, c2 and c2.parts or 0, c3 and c3.parts or 0
	check(rn .. ": Low < Medium < High parts", n1 < n2 and n2 < n3, string.format("%d / %d / %d", n1, n2, n3))
	check(rn .. ": High under the cap", n3 <= CAPS[rn], string.format("%d > %d", n3, CAPS[rn]))
	print(string.format("%-18s parts  L %5d   M %5d   H %5d   (instances H %d)", rn, n1, n2, n3, c3 and c3.instances or 0))
end
for level = 1, 3 do
	local total = 0
	for rn, c in pairs(scenes[level].counts) do
		if rn:match("^venue_") then
			total += 0
		end
		local _ = c
	end
	local _ = total
end

-- 4. report overlaps with solid server props (diagnostic)
do
	local solids = {}
	for _, rn in ipairs({ "server_gym_and_city", "LocalGym" }) do
		-- a see-through part carrying a sign (painted wall slogans) counts as solid too
		local signed = {}
		for _, g in ipairs(s3.roots[rn].guis or {}) do
			signed[g.part] = true
		end
		for i, p in ipairs(s3.roots[rn].parts) do
			if not SOLID_SKIP[p.n] and (p.t < 0.6 or signed[i]) then
				local lo, hi = aabb(p)
				if (hi[1] - lo[1]) < 60 and (hi[3] - lo[3]) < 60 then
					table.insert(solids, { n = p.n, lo = lo, hi = hi })
				end
			end
		end
	end
	local n = 0
	for _, rn in ipairs(DETAIL_ROOTS) do
		for _, p in ipairs(s3.roots[rn].parts) do
			if p.t < 0.99 then
				local lo, hi = aabb(p)
				local flat = (hi[2] - lo[2]) <= 0.12
				for _, q in ipairs(flat and {} or solids) do
					if overlap(lo, hi, q.lo, q.hi, 0.3) then
						n += 1
						if n <= 40 then
							print(string.format("  overlap: %s/%s with %s at (%.1f, %.1f, %.1f)", rn, p.n, q.n, p.cf[1], p.cf[2], p.cf[3]))
						end
						break
					end
				end
			end
		end
	end
	print("detail parts overlapping a solid prop by > 0.3 studs: " .. n)
end

if not process.args[1] or process.args[1] ~= "--keep" then
	pcall(fs.removeDir, OUT)
end
print(string.format("test_worlddetail: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("test_worlddetail failed")
end
