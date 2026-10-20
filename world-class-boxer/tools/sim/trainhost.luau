--!nocheck
-- trainhost.luau: the server's Training / Career modules under lune with a fresh career (test_training,
-- careersim). TH.new({ src, seed }) -> { H, Training, Career, Config, TP, profile(age), FixSeed(n), R0 }
local Host = require("./host")
local fs = require("@lune/fs")

local TH = {}

function TH.new(opts)
	opts = opts or {}
	local H = Host.new(opts.src and { src = opts.src } or nil)
	-- the server's unseeded Random is seeded: every run draws the same careers
	-- (T.FixSeed(n): every unseeded Random.new draws from seed n until T.FixSeed(nil): the same plan twice)
	local R0, seedN, fixed = H.globals.Random, 0, nil
	H.globals.Random = setmetatable({
		new = function(seed)
			seedN += 1
			if fixed and seed == nil then
				return R0.new(fixed)
			end
			return R0.new(seed or ((opts.seed or 7919) * seedN))
		end,
	}, { __index = R0 })
	local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
	for _, f in ipairs(fs.readDir(H.src .. "/server")) do
		local base = f:match("^(.-)%.lua$")
		if base and not f:find("%.server%.") then
			local n = Host.NewNode(base, "ModuleScript", folder)
			rawset(n, "_file", H.src .. "/server/" .. f)
		end
	end
	local T = { H = H, R0 = R0 }
	function T.FixSeed(n)
		fixed = n
	end
	T.Training = H.requireNode(folder._kids.Training)
	T.Career = H.requireNode(folder._kids.Career)
	T.Config = H.require("Config")
	local okTP, TP = pcall(H.require, "TrainingPlan")
	T.TP = okTP and TP or nil
	local Looks = H.require("Looks")
	function T.profile(age)
		local prof = T.Career.CreateProfile(nil, {
			first = "Sim", last = "Boxer", name = "Sim Boxer", nickname = "The Test", age = age or 22, nationality = "USA",
			weightClass = 5, style = "BoxerPuncher", look = Looks.Defaults(1),
		}, 1)
		return prof
	end
	return T
end

return TH
