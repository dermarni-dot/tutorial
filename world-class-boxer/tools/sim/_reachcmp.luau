--!nocheck
-- compare the animation's visible reach (v9_anim --clips reach JSONs) with HitGeometry's boundary on the same frames
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Host = require("./host")
local H = Host.new()
local HG = H.require("HitGeometry")
local dir = process.args[1]
local C = tonumber(process.args[2]) or 0.15
local function boundary(list)
	for i = 1, #list do
		local a, b = list[i], list[i + 1]
		if a.surf > C and (b == nil or b.surf > C) then
			if i == 1 then return list[1].gap end
			local p = list[i - 1]
			return p.gap + (a.gap - p.gap) * (C - p.surf) / (a.surf - p.surf)
		end
	end
	return list[#list].gap
end
local worst, n, sum = 0, 0, 0
local rows = {}
for _, f in ipairs(fs.readDir(dir)) do
	if f:match("%.json$") then
		local d = serde.decode("json", fs.readFile(dir .. "/" .. f))
		local A, B = d.geoA, d.geoB
		local line = string.format("%-18s %-18s", d.frame, d.oframe)
		for _, key in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand", "jab|body", "cross|body", "leadhook|body", "rearhook|body", "uppercut|body" }) do
			local list = d.punches[key]
			if list then
				local p, z = key:match("^(%a+)|?(%a*)$")
				local anim = boundary(list)
				local hg = HG.Range(A, B, p, z == "body")
				local e = hg - anim
				worst = math.max(worst, math.abs(e)); n += 1; sum += e
				line ..= string.format(" %s %.2f/%.2f", key:gsub("|body", "B"):sub(1, 6), anim, hg)
			end
		end
		table.insert(rows, line)
	end
end
table.sort(rows)
for _, r in ipairs(rows) do print(r) end
print(string.format("worst |hg - anim| %.2f, mean %.2f over %d", worst, sum / n, n))
