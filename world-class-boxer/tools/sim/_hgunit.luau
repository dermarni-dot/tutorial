local Host = require("./host")
local H = Host.new()
local HG = H.require("HitGeometry")
local U, R = HG.Unit(), HG.RIG
for _, p in ipairs({ "jab", "cross", "leadhook", "rearhook", "uppercut", "overhand" }) do
	print(string.format("%-9s unit %.2f/%.2f  rig %.2f/%.2f  target %.2f/%.2f", p, HG.Range(U, U, p, false), HG.Range(U, U, p, true), HG.Range(R, R, p, false), HG.Range(R, R, p, true), HG.TARGET[p].head, HG.TARGET[p].body))
end
