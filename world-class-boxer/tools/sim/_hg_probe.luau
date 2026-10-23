--!nocheck
local Host = require("./host")
local H = Host.new()
local HG = H.require("HitGeometry")
local U = HG.Unit()
local function f(h, w, d, hin, rin) return HG.FrameFromScales({ height = h, width = w or 1, depth = d or 1 }, { height = hin, reach = rin }) end
print("CAL", HG.CAL.jab, HG.CAL.cross, HG.CAL.leadhook, HG.CAL.uppercut, HG.CAL.overhand)
print("unit: arm", U.arm, "shoulderY", U.shoulderY, "headY", U.headY, "chin", U.headY - U.headR)
for _, p in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
	print(string.format("%-9s old %.3f  head %.3f  body %.3f", p, 4.3 * HG.RANGE[p], HG.Range(U, U, p, false), HG.Range(U, U, p, true)))
end
print("MinSep", HG.MinSep(U, U), "Clinch", HG.ClinchRange(U, U))
local S, T = f(0.86, 0.92, 0.92, 60, 60), f(1.2, 1.18, 1.14, 84, 84)
print("short stand", S.stand, "tall stand", T.stand)
for _, p in ipairs({ "jab", "cross", "leadhook", "uppercut", "overhand" }) do
	print(string.format("%-9s S>T head %.2f body %.2f | T>S head %.2f body %.2f | S>S %.2f T>T %.2f | S>T bent %.2f", p,
		HG.Range(S, T, p, false), HG.Range(S, T, p, true), HG.Range(T, S, p, false), HG.Range(T, S, p, true), HG.Range(S, S, p, false), HG.Range(T, T, p, false), HG.Range(S, T, p, false, { bend = 1 })))
end
for _, d in ipairs({ 3.0, 3.4, 3.8, 4.2 }) do
	local r = HG.Test(S, T, "jab", false, d)
	print("S jab at", d, r.ok, r.zone, r.why, r.redirected, string.format("need %.2f reach %.2f dy %.2f", r.need, r.reach, r.dy))
end
local X, Y = f(1.2, 1.4, 1.4), f(0.86, 0.7, 0.7)
print("extremes MinSep", HG.MinSep(X, Y), HG.MinSep(X, X), HG.MinSep(Y, Y), "clinch", HG.ClinchRange(X, Y), HG.ClinchRange(Y, X))
print("prefs S v T", (function() local p = HG.PunchPrefs(S, T); return p.jab, p.uppercut end)())
local FLOOR = 3.4
local M1, M2 = f(66/70, 0.92, 0.92, 66, 66), f(76/70, 1.05, 1.03, 76, 76)
print("moderate 66 v 76:")
for _, p in ipairs({ "jab", "cross", "leadhook", "uppercut", "overhand" }) do
	print(string.format("%-9s S>T head %.2f body %.2f | T>S head %.2f body %.2f | S>S %.2f T>T %.2f | S>T bent %.2f", p,
		HG.Range(M1, M2, p, false), HG.Range(M1, M2, p, true), HG.Range(M2, M1, p, false), HG.Range(M2, M1, p, true), HG.Range(M1, M1, p, false), HG.Range(M2, M2, p, false), HG.Range(M1, M2, p, false, { bend = 1 })))
end
print("minsep moderate", HG.MinSep(M1, M2))
print("with floor 3.4 (extreme S v T), head verdicts at 3.4:")
for _, p in ipairs({ "jab", "cross", "leadhook", "uppercut", "overhand" }) do
	local r1, r2 = HG.Test(S, T, p, false, 3.4, { floor = 3.4 }), HG.Test(T, S, p, false, 3.4, { floor = 3.4 })
	print(string.format("%-9s S>T %s %s %s | T>S %s %s %s", p, tostring(r1.ok), r1.zone, tostring(r1.why), tostring(r2.ok), r2.zone, tostring(r2.why)))
end
