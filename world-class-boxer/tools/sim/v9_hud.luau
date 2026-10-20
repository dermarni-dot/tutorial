--!nocheck
-- tools/sim/v9_hud.luau: the fight HUD's bars, the knockdown screen and the get-up panel at chosen moments,
-- built by the real client code (guisim) and dumped as layout JSON for tools/ui/render_mock.py:
--   full / mid / low health, a hit's ghost mid-drain, low stamina, a round's recovery (mid-fill), the
--   gym HUD's condition meters, knocked down (the get-up panel mid-mash, the knock-down blur), knocked out,
--   wobbled on the feet, and the get-up panel's STAND UP / COUNTED OUT states.
-- The camera's post effects (blur, colour correction) go in the JSON as `post` (render_mock blurs and
-- grades the stand-in 3D scene behind the UI with them, as the engine does).
--
--   lune run tools/sim/v9_hud.luau --out tools/sim/out/hud [--only full,ghost] [--devices desktop,phone]
--   python3 tools/ui/render_mock.py --all tools/sim/out/hud --out previews/final/v9/hud
local Host = require("./host")
local GS = require("./guisim")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local args = process.args
local outDir, only, devices, prefix = nil, nil, { "desktop", "phone" }, ""
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
	elseif a == "--prefix" then
		prefix = args[i + 1]
		i += 1
	end
	i += 1
end
local root = Host.FindRoot()
outDir = outDir or (root .. "/tools/sim/out/hud")
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

local function client(dev, gym)
	local S = GS.new(dev)
	local Career = S.host.requireNode(serverFolder(S)._kids.Career)
	local Looks = S.require("Looks")
	local prof = Career.CreateProfile(nil, {
		first = "Marcus", last = "Reed-Okonkwo", name = "Marcus Reed-Okonkwo", nickname = "The Hammer", age = 24, nationality = "USA",
		weightClass = 5, style = "boxer", look = Looks.Defaults(1),
	}, 1)
	prof.record = { w = 18, l = 2, d = 1, ko = 12 }
	local P = Career.Summary(prof, true)
	P.settings = P.settings or {}
	P.settings.ui = { menuAtStart = false }
	if gym and P.condition then
		P.condition.energy, P.condition.hydration, P.condition.nutrition, P.condition.fatigue = 72, 41, 18, 64
	end
	S.onInvokeServer = function(_, action)
		if action == "GetProfile" then
			return P
		end
		return { ok = false }
	end
	if gym then
		S.loadScript("client/ClientMain.client.lua")
	end
	S.loadScript("client/FightClient.client.lua")
	S.settle(0.6)
	return S
end

local TAPE = {
	you = { name = "Marcus Reed-Okonkwo", record = { w = 18, l = 2, d = 1, ko = 12 }, nick = "The Hammer", nat = "USA" },
	opp = { name = "Dmitri Volkovsky", record = { w = 27, l = 3, d = 1, ko = 19 }, nick = "Siberian Express", nat = "Russia" },
}
local function side(hp, body, stam, extra)
	local s = { hp = hp, cap = 100, body = body, bodyCap = 100, stam = stam, max = 100, stamCap = 100, conc = 0, tier = 0, bal = 80 }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end
local function state(S, me, opp, time)
	S.remotes.FightEvent:Fire({ t = "state", time = time or 132, me = me, opp = opp })
end
local function fight(dev, me, opp)
	local S = client(dev)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "start", rounds = 12, tape = TAPE, kind = "World Title Fight", venue = "Arena", venueName = "Grand Arena", moves = { "overhand", "liver" }, stakes = { "WBC" } })
	S.settle(0.2)
	fire:Fire({ t = "round", n = 3, total = 12 })
	fire:Fire({ t = "countdown", n = 0, round = 3 })
	state(S, me or side(100, 100, 100), opp or side(100, 100, 100))
	S.settle(1.4)
	return S
end

local SCREENS, ORDER = {}, {}
local function screen(name, fn)
	SCREENS[name] = fn
	table.insert(ORDER, name)
end

screen("full", function(dev)
	return fight(dev, side(100, 100, 100), side(100, 100, 100))
end)
screen("mid", function(dev)
	return fight(dev, side(58, 64, 61, { cap = 92 }), side(47, 52, 70, { cap = 88, bodyCap = 94 }))
end)
screen("low", function(dev)
	local S = fight(dev, side(16, 22, 38, { cap = 70, tier = 2 }), side(64, 41, 55))
	S.settle(0.4)
	return S
end)
-- a big hit just landed: 78 -> 44, the red ghost part-way down (held, then draining)
screen("ghost", function(dev)
	local S = fight(dev, side(78, 80, 64), side(70, 66, 58))
	state(S, side(44, 72, 58, { hurt = true }), side(70, 66, 55))
	S.settle(0.62)
	return S
end)
screen("lowstam", function(dev)
	local S = fight(dev, side(72, 70, 12, { stamCap = 86 }), side(66, 70, 64))
	state(S, side(72, 70, 14, { stamCap = 86 }), side(66, 70, 64))
	S.settle(0.5)
	return S
end)
-- between rounds: the corner's work comes back on the bars (48 -> 70), mid-fill
screen("recover", function(dev)
	local S = fight(dev, side(48, 52, 30), side(55, 60, 40))
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "bell", n = 3 })
	S.settle(0.2)
	state(S, side(70, 64, 82), side(66, 70, 78), 0)
	S.settle(0.35)
	return S
end)
screen("gym", function(dev)
	local S = client(dev, true)
	S.settle(0.6)
	return S
end)
local function down(S, severity, mash, count)
	local fire = S.remotes.FightEvent
	fire:Fire({ t = "kd", who = "you", severity = severity })
	S.settle(0.25)
	if severity ~= "out" then
		fire:Fire({ t = "getupStart", who = "you", target = 12, ability = 0.6, severity = severity })
		for n = 1, count or 4 do
			fire:Fire({ t = "count", n = n, who = "you", mash = mash, target = 12 })
		end
	end
end
-- knocked down, mid-mash: the get-up panel, the knock-down blur clearing as the meter fills
screen("down", function(dev)
	local S = fight(dev, side(22, 40, 30, { tier = 2 }), side(64, 60, 50))
	down(S, "heavy", 5, 4)
	S.settle(0.9)
	return S
end)
-- the first instant of a knockdown: the white flash
screen("down_impact", function(dev)
	local S = fight(dev, side(22, 40, 30, { tier = 2 }), side(64, 60, 50))
	S.remotes.FightEvent:Fire({ t = "kd", who = "you", severity = "heavy" })
	S.settle(0.08)
	return S
end)
screen("ko", function(dev)
	local S = fight(dev, side(4, 12, 20, { tier = 3 }), side(64, 60, 50))
	down(S, "out")
	S.settle(1.6)
	return S
end)
screen("wobble", function(dev)
	local S = fight(dev, side(52, 60, 40, { tier = 1 }), side(64, 60, 50))
	state(S, side(31, 55, 36, { tier = 2, hurt = true }), side(64, 60, 50))
	S.settle(0.3)
	return S
end)
screen("standup", function(dev)
	local S = fight(dev, side(22, 40, 30, { tier = 2 }), side(64, 60, 50))
	down(S, "heavy", 11, 6)
	S.settle(0.3)
	S.remotes.FightEvent:Fire({ t = "getup", who = "you" })
	S.settle(0.3)
	return S
end)
screen("countedout", function(dev)
	local S = fight(dev, side(8, 30, 20, { tier = 3 }), side(64, 60, 50))
	down(S, "heavy", 3, 9)
	S.settle(0.3)
	S.remotes.FightEvent:Fire({ t = "count", n = 10, who = "you", mash = 3, target = 12 })
	S.settle(0.3)
	return S
end)

-- the camera's post effects for the renderer
local function postOf(S)
	local cam = S.host.globals.workspace.CurrentCamera
	local post = { blur = 0, sat = 0, bri = 0, con = 0, tint = { 255, 255, 255 } }
	if not cam then
		return post
	end
	for _, c in ipairs(cam:GetChildren()) do
		local ok, cls = pcall(function()
			return c.ClassName
		end)
		local on = (function()
			local okE, e = pcall(function()
				return c.Enabled
			end)
			return not okE or e ~= false
		end)()
		if ok and on and cls == "BlurEffect" then
			post.blur += tonumber(c.Size) or 0
		elseif ok and on and cls == "ColorCorrectionEffect" then
			post.sat += tonumber(c.Saturation) or 0
			post.bri += tonumber(c.Brightness) or 0
			post.con += tonumber(c.Contrast) or 0
			local t = c.TintColor
			if t then
				post.tint = { math.floor(post.tint[1] * t.R), math.floor(post.tint[2] * t.G), math.floor(post.tint[3] * t.B) }
			end
		end
	end
	return post
end

local childAt = table.find(args, "--child")
if childAt then
	local name, dev = args[childAt + 1], args[childAt + 2]
	local ok, err = pcall(function()
		local S = SCREENS[name](dev)
		local items = S.collect()
		local file = string.format("%s/%s%s_%s.json", outDir, prefix, name, dev)
		GS.WriteBoxes(file, S, items, { title = prefix .. name .. "  ·  " .. dev })
		local doc = serde.decode("json", fs.readFile(file))
		doc.post = postOf(S)
		fs.writeFile(file, serde.encode("json", doc, false))
		print("WROTE " .. file)
	end)
	if not ok then
		print("FAIL " .. name .. "@" .. dev .. ": " .. tostring(err))
	end
	process.exit(0)
end

local self = root .. "/tools/sim/v9_hud.luau"
local bad = 0
for _, name in ipairs(ORDER) do
	if not only or only[name] then
		for _, dev in ipairs(devices) do
			local cmd = { "run", self, "--child", name, dev, "--out", outDir }
			if prefix ~= "" then
				table.insert(cmd, "--prefix")
				table.insert(cmd, prefix)
			end
			local r = process.exec("lune", cmd)
			local out = (r.stdout or "") .. (r.stderr or "")
			if not out:find("WROTE") then
				bad += 1
				print(string.format("FAIL %s@%s: %s", name, dev, out:sub(-600)))
			else
				print(out:match("WROTE [^\n]+"))
			end
		end
	end
end
process.exit(bad == 0 and 0 or 1)
