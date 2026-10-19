--!nocheck
local GS = require("./guisim")
local Host = require("./host")
local fs = require("@lune/fs")
local process = require("@lune/process")
local S = GS.new(process.args[1] or "phone")
local H = S.host
-- the server's Career module (CreateProfile / Summary) for a real profile summary
local SSS = H.Service("ServerScriptService")
local folder = Host.NewNode("Server", "Folder", SSS)
for _, f in ipairs(fs.readDir(H.src .. "/server")) do
	local base = f:match("^(.-)%.lua$")
	if base and not f:find("%.server%.") then
		local n = Host.NewNode(base, "ModuleScript", folder)
		rawset(n, "_file", H.src .. "/server/" .. f)
	end
end
local Career = H.requireNode(folder._kids.Career)
local Looks = H.require("Looks")
local prof = Career.CreateProfile(nil, { first = "Marcus", last = "Reed", name = "Marcus Reed", nickname = "The Hammer", age = 24, nationality = "USA", weightClass = 5, style = "boxer", look = Looks.Defaults(1) }, 1)
local P = Career.Summary(prof, true)
P.settings = P.settings or {}
P.pvp = { rating = 1000, w = 0, l = 0 }
print("summary ok", P.created, P.overall, P.tierName)
S.onInvokeServer = function(_, action)
	if action == "GetProfile" then
		return P
	end
	return { ok = false }
end
local ok, err = pcall(S.loadScript, "client/ClientMain.client.lua")
print("main", ok, err)
S.settle(1)
local items = S.collect()
print("items", #items)
local c = S.checks(items)
for k, list in pairs(c) do
	print(k, #list)
	for i, e in ipairs(list) do
		if i <= 25 then
			local it = e.item
			print(string.format("   %-70s %4d,%4d %4dx%-4d %s", it.path:sub(-70), it.x, it.y, it.w, it.h, tostring(e.over or e.size or e.need or e.px or "")))
		end
	end
end
GS.WriteBoxes("/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/gym_" .. S.name .. ".json", S, items)
process.exit(0)
