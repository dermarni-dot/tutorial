local FS = require("./fightsim")
local S = FS.new()
local modes, fits, n, busy = {}, 0, 0, 0
for i = 1, 8 do
	S.Fight({ red = { style = "OutBoxer", level = 60, noTraits = true }, blue = { style = "Slugger", level = 60, noTraits = true }, rounds = 6, seed = i * 7919 + 13,
		onTick = function(f, now)
			local F = f.P
			if not F.ai or F.state == "down" then return end
			n += 1
			modes[F.ai.mode] = (modes[F.ai.mode] or 0) + 1
			if F.ai:Fits("jab", f:Distance(F, f.O)) then fits += 1 end
			if now < F.busyUntil then busy += 1 end
		end })
end
for k, v in pairs(modes) do print(k, string.format("%.2f", v / n)) end
print("in jab range", fits / n, "busy", busy / n)
