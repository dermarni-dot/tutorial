--!nocheck
-- ui_profile.luau: how much UI each screen builds, on guisim (tools/sim/guisim.luau): instances made per tab
-- of the Career Hub, UI.Icon frames, live signal connections (fakeengine's FE.Connections), the build time, the
-- rebuilds a burst of profile pushes causes, and what a close leaves behind. Numbers, not pass / fail.
--
--   lune run tools/ui/ui_profile.luau [--device desktop] [--tabs Career,Training] [--json OUT]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local GS = require("../sim/guisim")
local FE = require("../sim/fakeengine")
local Host = require("../sim/host")

local args = process.args
local function opt(name, default)
	local at = table.find(args, name)
	return at and args[at + 1] or default
end
local device = opt("--device", "desktop")
local onlyTabs = opt("--tabs")
local jsonOut = opt("--json")

local root = Host.FindRoot()

local function serverModules(S)
	local H = S.host
	local folder = Host.NewNode("Server", "Folder", H.Service("ServerScriptService"))
	for _, f in ipairs(fs.readDir(H.src .. "/server")) do
		local base = f:match("^(.-)%.lua$")
		if base and not f:find("%.server%.") then
			local n = Host.NewNode(base, "ModuleScript", folder)
			rawset(n, "_file", H.src .. "/server/" .. f)
		end
	end
	return folder
end

local function profileFor(S)
	local folder = serverModules(S)
	local Career = S.host.requireNode(folder._kids.Career)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	prof.record = { w = 18, l = 2, d = 1, ko = 12 }
	prof.money = 1250000
	local Training = S.host.requireNode(folder._kids.Training)
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	P.training = Training.ProgramView(prof)
	return P, prof, Career, Training
end

local S = GS.new(device)
local P = profileFor(S)
S.P = P
S.onInvokeServer = function(_, action)
	if action == "GetProfile" then
		return P
	end
	return { ok = false }
end
S.loadScript("client/ClientMain.client.lua")
S.loadScript("client/FightClient.client.lua")
S.settle(0.6)

local function countUnder(o)
	local n, icons, text, images = 0, 0, 0, 0
	for _, d in ipairs(o:GetDescendants()) do
		n += 1
		if d:GetAttribute("Icon") then
			icons += 1
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			text += 1
		elseif d:IsA("ImageLabel") then
			images += 1
		end
	end
	return n, icons, text, images
end

local function find(path)
	local n = S.playerGui
	for part in path:gmatch("[^%.]+") do
		n = n and n:FindFirstChild(part)
	end
	return n
end

local Hub = S.require("Client/Hub")
local State = S.require("Client/State")
local report = { device = device, tabs = {} }
local before = FE.Connections
local baseN = countUnder(S.playerGui)
print(string.format("%-14s %8s %6s %6s %6s %9s %8s", "tab", "objects", "icons", "text", "images", "conns", "ms"))
local tabs = {}
for t in (onlyTabs or "Career,Tournaments,Training,Body,Stats,Gym,Gear,Coaches,Sponsors,Life,Rankings,Rivals,PvP,Shop,Legacy"):gmatch("[^,]+") do
	table.insert(tabs, t)
end
Hub.Open(tabs[1])
S.settle(0.3)
for _, tab in ipairs(tabs) do
	local c0 = FE.Connections
	local t0 = os.clock()
	Hub.Open(tab)
	S.settle(0.3)
	local ms = (os.clock() - t0) * 1000
	local hub = find("BoxerUI.Root.Hub")
	local n, icons, text, images = countUnder(hub or S.playerGui)
	local row = { tab = tab, objects = n, icons = icons, text = text, images = images, conns = FE.Connections - c0, ms = math.floor(ms) }
	table.insert(report.tabs, row)
	print(string.format("%-14s %8d %6d %6d %6d %9d %8d", tab, n, icons, text, images, FE.Connections - c0, math.floor(ms)))
end

-- a burst of pushes within one frame: one rebuild
Hub.Open("Career")
S.settle(0.3)
local r0 = Hub.Renders
local c1 = FE.Connections
for _ = 1, 6 do
	State.Changed:Fire(P)
end
S.settle(0.3)
report.pushRebuilds = Hub.Renders - r0
report.pushConnDelta = FE.Connections - c1
print(string.format("6 profile pushes in one frame: %d rebuild(s), connections %+d", report.pushRebuilds, report.pushConnDelta))

-- open / close leak
local n0 = countUnder(S.playerGui)
local cOpen = FE.Connections
for _ = 1, 3 do
	Hub.Open("Career")
	S.settle(0.2)
	Hub.Close()
	S.settle(0.2)
end
local n1 = countUnder(S.playerGui)
report.closeObjectsLeft = n1 - n0
report.closeConnsLeft = FE.Connections - cOpen
print(string.format("3 open/close cycles: objects %+d, connections %+d (gui objects total %d, baseline %d; connections now %d, before the hub %d)", n1 - n0, FE.Connections - cOpen, n1, baseN, FE.Connections, before))

if jsonOut then
	fs.writeFile(jsonOut, serde.encode("json", report, true))
end
-- (a client leaves threads running: end the process ourselves)
process.exit(0)
