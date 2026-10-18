-- tools/sim/fit_classic_hair.luau: how the asset hair (modelled on the retired organic skull) sits on the classic
-- head every boxer has now (look.headShape = "classic", AnatomyHairKit.CLASSIC). For every HairAssetData entry it
-- places the pieces exactly as the client does (Kit.Scalp -> HK.Fit -> HK.Place) and measures each piece's
-- point cloud against the classic head's surface (nominal studs: < 0 inside the head = clipping, > 0 above it).
--   lune run tools/sim/fit_classic_hair.luau [--organic]   (--organic: the same numbers on the old skull)
local Host = require("./host")
local process = require("@lune/process")
local H = Host.new()
local HK = H.require("HairAssetKit")
local Kit = H.require("AnatomyHairKit")
local Data = H.require("HairAssetData")

local organic = table.find(process.args, "--organic") ~= nil

local function look(entry)
	local hair = { style = entry.styles[1], type = (entry.types and entry.types[1]) or "Straight" }
	local lk = H.Look({ g = 1, hair = hair, headShape = "classic" })
	if organic then
		lk.headShape = nil
	end
	return lk
end

local function stats(list)
	table.sort(list)
	local n = #list
	if n == 0 then
		return nil
	end
	local function at(q)
		return list[math.clamp(math.floor(q * (n - 1) + 1.5), 1, n)]
	end
	return { min = list[1], p10 = at(0.1), med = at(0.5), max = list[n], n = n }
end

local male = H.Look({ g = 1, headShape = "classic" })
if organic then
	male.headShape = nil
end
local S0 = Kit.Scalp(male)
local f0 = HK.Fit(S0, Data.fit0)
print(string.format("%s head: W %.3f T %.3f Fz %.3f Bz %.3f -> fit ax %.3f ay %.3f az %.3f dz %.3f (k %.3f)",
	organic and "organic" or "classic", f0.W, f0.T, f0.Fz, f0.Bz, f0.ax, f0.ay, f0.az, f0.dz, S0.kx))

local worst = { cap = math.huge, cards = math.huge }
local capFloat = {}
for _, e in ipairs(Data.entries) do
	local lk = look(e)
	local S = Kit.Scalp(lk)
	local placed = HK.Place(Data, e, lk, S)
	local cards = {}
	for name, pl in pairs(placed) do
		local d = {}
		local P = pl.P
		for i = 1, #P - 2, 3 do
			table.insert(d, S.f(P[i] / S.kx, P[i + 1] / S.ky, P[i + 2] / S.kz))
		end
		local st = stats(d)
		if st then
			if name == "HairCap" then
				worst.cap = math.min(worst.cap, st.min)
				table.insert(capFloat, st.med)
				print(string.format("  %-14s cap      min %+.3f p10 %+.3f med %+.3f max %+.3f", e.key, st.min, st.p10, st.med, st.max))
			else
				for _, v in ipairs(d) do
					table.insert(cards, v)
				end
			end
		end
	end
	local st = stats(cards)
	if st then
		worst.cards = math.min(worst.cards, st.p10)
		print(string.format("  %-14s cards    min %+.3f p10 %+.3f med %+.3f max %+.3f (%d pts)", e.key, st.min, st.p10, st.med, st.max, st.n))
	end
end
print(string.format("worst cap point %+.3f, worst card p10 %+.3f (nominal studs; x %.3f for real studs)", worst.cap, worst.cards, S0.kx))
