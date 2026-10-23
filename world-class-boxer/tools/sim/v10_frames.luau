--!nocheck
-- tools/sim/v10_frames.luau: the creator's Body step with the frame traits panel (Shared.FrameTraits: the pros / cons of
-- the picked body type), built by the real client code (guisim) and dumped as layout JSON for tools/ui/render_mock.py:
-- one screen per frame (the Lean, Athletic, Muscular, Power Build and Heavyweight Build picked), per device.
--
--   lune run tools/sim/v10_frames.luau --out tools/sim/out/frames [--only lean,heavyweight] [--devices desktop,phone]
--   python3 tools/ui/render_mock.py --all tools/sim/out/frames --out previews/final/v10/frames
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
local outDir, only, devices = nil, nil, { "desktop", "phone", "tablet" }
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--out" then
		outDir = args[i + 1]
		i += 1
	elseif a == "--only" then
		only = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			only[s] = true
		end
		i += 1
	elseif a == "--devices" then
		devices = {}
		for s in args[i + 1]:gmatch("[^,]+") do
			table.insert(devices, s)
		end
		i += 1
	end
	i += 1
end
local root = Host.FindRoot()
outDir = outDir or (root .. "/tools/sim/out/frames")
Host.MkDir(root .. "/tools/sim/out")
Host.MkDir(outDir)

local function serverFolder(S)
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

-- a fresh client on the device with a new career's profile pushed (test_ui_layout's client, in short)
local function client(dev)
	local S = GS.new(dev)
	local folder = serverFolder(S)
	local Career = S.host.requireNode(folder._kids.Career)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	S.loadScript("client/ClientMain.client.lua")
	S.settle(0.6)
	return S
end

local function named(S, name)
	for _, d in ipairs(S.playerGui:GetDescendants()) do
		if d.Name == name and d.Visible ~= false then
			return d
		end
	end
	return nil
end
local function press(S, name)
	local b = named(S, name)
	if not b then
		return false
	end
	S.signal(b, "MouseButton1Click"):Fire()
	S.settle(0.4)
	return true
end
-- scroll the step's list so `name` is at the top (the panel sits under the body-type grid)
local function scrollTo(S, name)
	local obj = named(S, name)
	if not obj then
		return false
	end
	local sc = obj.Parent
	while sc and not sc:IsA("ScrollingFrame") do
		sc = sc.Parent
	end
	if not sc then
		return false
	end
	local y = obj.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
	sc.CanvasPosition = roblox.Vector2.new(0, math.max(0, y - 150))
	S.settle(0.2)
	return true
end

local FRAMES = { { "lean", "Lean" }, { "athletic", "Athletic" }, { "muscular", "Muscular" }, { "power", "Power Build" }, { "heavyweight", "Heavyweight Build" } }
local files = {}
for _, dev in ipairs(devices) do
	for _, fr in ipairs(FRAMES) do
		local key, id = fr[1], fr[2]
		if not only or only[key] then
			local S = client(dev)
			S.require("Client/Creator").Open()
			S.settle(0.8)
			-- the Body step (5): a step button, or the step picker's menu on a phone
			if not press(S, "Step5") then
				press(S, "StepPick")
				press(S, "Step5")
			end
			assert(press(S, "Preset_" .. id), "no body type cell for " .. id .. " on " .. dev)
			S.settle(0.6)
			scrollTo(S, "FrameTraits")
			local items = S.collect()
			local panel = nil
			for _, it in ipairs(items) do
				if it.path and it.path:find("FrameTraits", 1, true) and it.visibleH > 1 then
					panel = it
					break
				end
			end
			assert(panel, "the frame traits panel is not on the screen (" .. id .. " @ " .. dev .. ")")
			local file = string.format("%s/frames_%s_%s.json", outDir, key, dev)
			GS.WriteBoxes(file, S, items, { title = string.format("creator body: %s  ·  %s", id, dev) })
			table.insert(files, file)
			print(string.format("%-12s %-8s %d objects -> %s", id, dev, #items, file))
		end
	end
end
print(string.format("v10_frames: %d screens", #files))
