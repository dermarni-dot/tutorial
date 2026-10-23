--!nocheck
local process = require("@lune/process")
local FS = require("./fightsim")
local S = FS.new({ root = (process.args[3] and process.args[3] ~= "" and process.args[3]) or nil })
local a, b = process.args[1], process.args[2]
if process.args[4] and process.args[4] ~= "" then
	local luau = require("@lune/luau")
	luau.load(process.args[4], { environment = setmetatable({ AIC = S.Config.FightAI, S = S }, { __index = _G }) })()
end
local w, ko, rr, modes = 0, 0, 0, {}
local st = { rt = 0, rl = 0, bt = 0, bl = 0, secs = 0, rkd = 0, bkd = 0, rd = 0, bd = 0 }
local N = 24
for i = 1, N do
	local r = S.Fight({ red = { style = a, level = 60, noTraits = true }, blue = { style = b, level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f) if f.live then modes[f.O.ai.mode] = (modes[f.O.ai.mode] or 0) + 1 end end })
	w += r.winner == "red" and 1 or (r.winner == "draw" and 0.5 or 0)
	if r.method == "KO" or r.method == "TKO" then ko += 1 end
	rr += r.round
	st.rt += r.thrown.red; st.rl += r.landed.red; st.bt += r.thrown.blue; st.bl += r.landed.blue; st.secs += r.seconds; st.rkd += r.kd.red; st.bkd += r.kd.blue; st.rd += r.P.damageDealt; st.rb = (st.rb or 0) + r.P.totals.body; st.bb = (st.bb or 0) + r.O.totals.body; st.bd += r.O.damageDealt
end
local t = {}
for k, v in pairs(modes) do table.insert(t, k .. "=" .. v) end
print(string.format("%s vs %s: red %.2f ko %.2f r%.1f body share red %.0f%% blue %.0f%% | red %.0f/min %.0f%% dmg %.0f kd %d | blue %.0f/min %.0f%% dmg %.0f kd %d | blue modes %s", a, b, w / N, ko / N, rr / N, st.rb / st.rl * 100, st.bb / st.bl * 100, st.rt / st.secs * 60, st.rl / st.rt * 100, st.rd / N, st.rkd, st.bt / st.secs * 60, st.bl / st.bt * 100, st.bd / N, st.bkd, table.concat(t, " ")))
