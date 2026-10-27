--!nocheck
-- tools/sim/creatorframes.luau: every interaction on the character creator (Creator), frame by frame, on the REAL client
-- (ClientMain, FightClient, Animator and every module they start; guisim) with the REAL server build behind its
-- previews (Builder.Cosmetics on a server-side rig, its result replicated onto the client's character).
--   * a first join (no career) and the Creator opened; then: idle, every step (tab), a drag of every slider on every
--     step (one pointer move a frame, as a mouse sends them), colour swatches, the colour wheel, presets / chips /
--     cyclers (face, hair, beard, body type, kit, trunk style), turning (a drag on the 3D view, the dock) and zooming,
--     leaving
--   * per interaction: the longest frame's Lua (client only: the server's build and guisim's layout are not a client
--     frame's), instances created and destroyed on the client, property writes (most in a frame), PreviewLook requests
--     (full / head / colour), the server's rebuilds that ran (full Cosmetics vs partial), instances replicated, the
--     body-tier swaps among them, and meshes the client meets for the first time (a fetch the engine starts then)
--   * "replication": PreviewLook runs the server's handler logic (its throttle: a full rebuild at most every 0.5 s, a
--     partial every 0.2 s) and Builder.Cosmetics on a server rig (ApplyDescription's rescale emulated from
--     Builder.Scales); LAT seconds later the changed tree is mirrored onto the client's character (new copies built
--     outside the frame, their parenting, property writes and destroys inside it, where the client's handlers run)
--   lune run tools/sim/creatorframes.luau [--lat 0.08] [--world 0] [--src DIR] [--only Body,Face] [--json PATH] [--debug 1] [--slices 1]
--   the last line (SUMMARY ...) and --json are for before / after tables
-- Simulated: the engine (instances are Lua tables; no rendering, no physics); the Lua times compare one version of the
-- client with another, the instance / write / request counts are exact.
local process = require("@lune/process")
local ltask = require("@lune/task")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local GS = require("./guisim")
local Host = require("./host")
local FE = require("./fakeengine")
local DrillSim = require("./drillsim")

local Vector3, CFrame, Enum, Color3 = roblox.Vector3, roblox.CFrame, roblox.Enum, roblox.Color3

local args = {}
do
	local a = process.args
	for i = 1, #a, 2 do
		args[(a[i]:gsub("^%-%-", ""))] = a[i + 1]
	end
end
local LAT = tonumber(args.lat) or 0.08 -- one way: the request reaches the server, the rebuild reaches the client
local DEBUG = args.debug == "1"
local writeBy, newBy = {}, {}
local ONLY = {}
for s in tostring(args.only or ""):gmatch("[^,]+") do
	ONLY[s] = true
end

local excluded = 0 -- seconds inside the current frame that are not the client's (layout, the server, mirror copies)
-- (the server's host first: Host.new rebinds GetService for every host made before it, the client's must come last)
------------------------------------------------------------------------
-- the server: Builder on a rig of its own (a second engine), as handlers.PreviewLook / applyLook
------------------------------------------------------------------------
local ES = FE.new()
local HS = Host.new({ server = true, src = args.src, globals = { Instance = ES.Instance, workspace = ES.workspace, Workspace = ES.workspace, warn = function() end } })
ES.install(HS)
local BodyTiers = HS.require("BodyTiers")
local BuilderTiers = HS.require("BuilderTiers")
local BuilderGear = HS.require("BuilderGear")
local Builder = HS.require("Builder")
local LooksS = HS.require("Looks")
local BLOCK = {
	UpperTorso = { size = { 2, 1.6, 1 }, att = { NeckRigAttachment = { 0, 0.8, 0 }, WaistRigAttachment = { 0, -0.8, 0 }, LeftShoulderRigAttachment = { -1, 0.563, 0 }, RightShoulderRigAttachment = { 1, 0.563, 0 } } },
	LowerTorso = { size = { 2, 0.4, 1 }, att = { WaistRigAttachment = { 0, 0.2, 0 }, LeftHipRigAttachment = { -0.5, -0.2, 0 }, RightHipRigAttachment = { 0.5, -0.2, 0 }, RootRigAttachment = { 0, -0.2, 0 } } },
}
for _, side in ipairs({ "Left", "Right" }) do
	local sx = side == "Left" and -1 or 1
	BLOCK[side .. "UpperArm"] = { size = { 1, 1.169, 1 }, att = { [side .. "ShoulderRigAttachment"] = { -0.5 * sx, 0.394, 0 }, [side .. "ElbowRigAttachment"] = { 0, -0.334, 0 } } }
	BLOCK[side .. "LowerArm"] = { size = { 1, 1.052, 1 }, att = { [side .. "ElbowRigAttachment"] = { 0, 0.192, 0 }, [side .. "WristRigAttachment"] = { 0, -0.501, 0 } } }
	BLOCK[side .. "Hand"] = { size = { 1, 0.3, 1 }, att = { [side .. "WristRigAttachment"] = { 0, 0.125, 0 } } }
	BLOCK[side .. "UpperLeg"] = { size = { 1, 1.217, 1 }, att = { [side .. "HipRigAttachment"] = { 0, 0.421, 0 }, [side .. "KneeRigAttachment"] = { 0, -0.408, 0 } } }
	BLOCK[side .. "LowerLeg"] = { size = { 1, 1.193, 1 }, att = { [side .. "KneeRigAttachment"] = { 0, 0.2, 0 }, [side .. "AnkleRigAttachment"] = { 0, -0.547, 0 } } }
	BLOCK[side .. "Foot"] = { size = { 1, 0.3, 1 }, att = { [side .. "AnkleRigAttachment"] = { 0, 0.085, 0 } } }
end
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" }, Waist = { "LowerTorso", "UpperTorso" }, Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" }, RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" }, RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" }, RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" }, RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" }, RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" }, RightAnkle = { "RightLowerLeg", "RightFoot" },
}
local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end
local rigScale = Vector3.one
local function newRig(scale, parent)
	local model = ES.new("Model")
	model.Name = "Boxer"
	local hrp = ES.new("Part", model)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1) * scale
	hrp.CFrame = CFrame.new(0, 4, 60)
	local ra = ES.new("Attachment", hrp)
	ra.Name = "RootRigAttachment"
	local function addPart(name, size, orig, atts)
		local p = ES.new("MeshPart", model)
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(0, 4, 60)
		p.Color = Color3.new(1, 1, 1)
		local o = ES.new("Vector3Value", p)
		o.Name = "OriginalSize"
		o.Value = orig
		for an, pos in pairs(atts) do
			local a = ES.new("Attachment", p)
			a.Name = an
			a.Position = pos.cur
			local op = ES.new("Vector3Value", a)
			op.Name = "OriginalPosition"
			op.Value = pos.orig
		end
	end
	for name, b in pairs(BLOCK) do
		local atts = {}
		for an, pos in pairs(b.att) do
			atts[an] = { cur = v3(pos) * scale, orig = v3(pos) }
		end
		addPart(name, v3(b.size) * scale, v3(b.size), atts)
	end
	addPart("Head", Vector3.new(0.927, 0.927, 0.927), Vector3.new(1.2, 1.2, 1.2), { NeckRigAttachment = { cur = Vector3.new(0, -0.46, 0), orig = Vector3.new(0, -0.6, 0) } })
	model:FindFirstChild("Head").CFrame = CFrame.new(0, 6, 60)
	for jn, pp in pairs(JOINTS) do
		local p0, p1 = model:FindFirstChild(pp[1]), model:FindFirstChild(pp[2])
		local m = ES.new("Motor6D", p1)
		m.Name = jn
		m.Part0, m.Part1 = p0, p1
		m.C0 = p0:FindFirstChild(jn .. "RigAttachment").CFrame
		m.C1 = p1:FindFirstChild(jn .. "RigAttachment").CFrame
		m.Transform = CFrame.new()
	end
	local hum = ES.new("Humanoid", model)
	hum.HipHeight = 2 * scale.Y
	hum.ReplaceBodyPartR15 = function(_, enum, part)
		local name = enum.Name
		local old = model:FindFirstChild(name)
		if name ~= "Head" then
			local o = part:FindFirstChild("OriginalSize")
			if o then
				part.Size = o.Value * rigScale
			end
		end
		part.CFrame = old and old.CFrame or CFrame.new(0, 4, 60)
		for _, m in ipairs(model:GetDescendants()) do
			if m.ClassName == "Motor6D" then
				if m.Part0 == old then
					m.Part0 = part
				end
				if m.Part1 == old then
					m.Part1 = part
					m.Parent = part
				end
			end
		end
		part.Parent = model
		old:Destroy()
		return true
	end
	model.Parent = parent
	return model
end
local function fakeAssets()
	local AS = {}
	function AS.CreateMeshPartAsync(_, content)
		local mp = ES.new("MeshPart")
		mp.MeshId = "rbxassetid://" .. tostring(tonumber(tostring(content):match("(%d+)%s*$")))
		return mp
	end
	return AS
end
local Content = { fromUri = function(u)
	return u
end }
BodyTiers.SetData(BodyTiers.Data())
BuilderTiers.Reset()
BuilderTiers.Services = { AssetService = fakeAssets(), Content = Content }
BuilderGear.SetData(BuilderGear.Data())
BuilderGear.Reset()
BuilderGear.Services = { AssetService = fakeAssets(), Content = Content }
local stageF = ES.new("Folder", ES.workspace)
stageF.Name = "BoxerStaging"
Builder.Services.Stage = stageF
local PREVIEW_BUILD = { chest = 8, shoulders = 8, arms = 8, back = 8, legs = 8, core = 8, neck = 8, fat = 14 }
local PREVIEW_GEAR = { gloves = "Worn", glovesCond = 55, wraps = "OldWraps", wrapsCond = 50, shoes = "Sneakers", shoesCond = 60, mouthguard = "BoilBite" }
local srv = newRig(Vector3.one, ES.workspace)
local srvCalls = {} -- the server's layers (spies): Tiers = a body-tier swap pass
do
	local f = BuilderTiers.Apply
	BuilderTiers.Apply = function(...)
		srvCalls.Tiers = (srvCalls.Tiers or 0) + 1
		return f(...)
	end
end
local srvMade = 0
do
	local new0 = ES.Instance.new
	ES.Instance.new = function(...)
		srvMade += 1
		return new0(...)
	end
end
-- ApplyDescription's rescale (the engine's, emulated): the parts to OriginalSize x Builder.Scales, the joints' attachments
local function rescale(app, build)
	local ok, sc = pcall(Builder.Scales, app, build, {})
	if not ok or type(sc) ~= "table" then
		return
	end
	local s = Vector3.new(sc.width or 1, sc.height or 1, sc.depth or 1)
	if s == rigScale then
		return
	end
	rigScale = s
	for _, p in ipairs(srv:GetChildren()) do
		local o = p:FindFirstChild("OriginalSize")
		if o then
			p.Size = o.Value * s
			for _, a in ipairs(p:GetChildren()) do
				local op = a:FindFirstChild("OriginalPosition")
				if op then
					a.Position = op.Value * s
				end
			end
		end
	end
	srv:FindFirstChildOfClass("Humanoid").HipHeight = 2 * s.Y
end
local server = { full = 0, partial = 0, throttled = 0, ms = 0, made = 0, tiers = 0 }
local lastPreview
local needFull = true
local pendingRep = {} -- os.clock() at which a rebuild's result reaches the client
local function serverBuild(look, hands, popts)
	local app = LooksS.Sanitize(look)
	local opts = { hands = hands == "gloves" and "gloves" or "wraps", name = "", nick = "", waistText = "", detail = "full" }
	local only = type(popts) == "table" and type(popts.only) == "table" and popts.only or nil
	opts.previewGrowth = type(popts) == "table" and popts.growth or nil
	if only and not needFull then
		opts.only = { Face = only.Face == true, Hair = only.Hair == true, Beard = only.Beard == true, Colors = only.Colors == true }
	end
	needFull = false
	local t0 = os.clock()
	srvMade = 0
	table.clear(srvCalls)
	if not opts.only then
		rescale(app, PREVIEW_BUILD)
	end
	local ok, err = pcall(Builder.Cosmetics, srv, app, PREVIEW_BUILD, PREVIEW_GEAR, opts)
	if not ok and not server.warned then
		server.warned = true
		print("[creatorframes] server build failed: " .. tostring(err))
	end
	local dt = os.clock() - t0
	excluded += dt
	server.ms += dt * 1000
	server.made += srvMade
	server.tiers += srvCalls.Tiers or 0
	if opts.only then
		server.partial += 1
	else
		server.full += 1
	end
	table.insert(pendingRep, os.clock() + LAT)
end

local S = GS.new("desktop", { src = args.src })
local Hh = S.host
local E = S.E
DrillSim.SeedRandom(Hh)
-- real input signals (the sim's defaults are inert): drags are InputBegan on a hit area, then InputChanged / InputEnded
local uis = Hh.Service("UserInputService")._props
uis.InputBegan, uis.InputChanged, uis.InputEnded = FE.Signal(), FE.Signal(), FE.Signal()

------------------------------------------------------------------------
-- frame-driven waits (as loadframes: a task.wait / task.delay resumes on a frame of the harness, as on a Heartbeat)
------------------------------------------------------------------------
local T = Hh.globals.task
local base = { spawn = T.spawn, defer = T.defer, delay = T.delay, wait = T.wait }
local taskLib = table.clone(T)
local waiting = {}
local function resumeDue()
	local t = os.clock()
	local due = {}
	for i = #waiting, 1, -1 do
		local w = waiting[i]
		if t >= w.at then
			table.remove(waiting, i)
			table.insert(due, 1, w)
		end
	end
	for _, w in ipairs(due) do
		if type(w.th) == "thread" then
			base.spawn(w.th, t - w.t0)
		else
			base.spawn(w.th, table.unpack(w.args, 1, w.args.n))
		end
	end
end
taskLib.delay = function(t, f, ...)
	table.insert(waiting, { th = f, at = os.clock() + (tonumber(t) or 0), t0 = os.clock(), args = table.pack(...) })
end
taskLib.wait = function(t)
	table.insert(waiting, { th = coroutine.running(), at = os.clock() + (tonumber(t) or 0), t0 = os.clock() })
	return coroutine.yield()
end
Hh.globals.task = taskLib
Hh.globals.wait = taskLib.wait
Hh.globals.delay = taskLib.delay

------------------------------------------------------------------------
-- counters
------------------------------------------------------------------------
local measuring = false
local cur -- the current frame's record
local created, writes = 0, 0
local layoutDepth = 0
do
	local lazy = E.lazyGet
	E.lazyGet = function(o, k)
		if layoutDepth > 0 then
			return lazy(o, k)
		end
		layoutDepth += 1
		local t0 = os.clock()
		local r = lazy(o, k)
		excluded += os.clock() - t0
		layoutDepth -= 1
		return r
	end
	local onSet = E.onSet
	E.onSet = function(o, k, v)
		if measuring then
			writes += 1
			if DEBUG then
				local key = rawget(o, "_class") .. "." .. tostring(k)
				local src, line = debug.info(3, "sl")
				if src then
					key ..= " @" .. tostring(src):gsub("^.*/", ""):gsub('"%]$', "") .. ":" .. tostring(line)
				end
				writeBy[key] = (writeBy[key] or 0) + 1
			end
		end
		return onSet(o, k, v)
	end
	local new0 = S.Instance.new
	S.Instance.new = function(...)
		if measuring then
			created += 1
			if DEBUG then
				-- the first caller outside UI / LookKit
				local who = "?"
				for lv = 2, 12 do
					local src, line, fname = debug.info(lv, "sln")
					if not src then
						break
					end
					src = tostring(src):gsub("^.*/", ""):gsub('"%]$', "")
					if not (src:find("UI.lua") or src:find("guisim") or src:find("LookKit") or src:find("fakeengine") or src:find("creatorframes")) then
						who = string.format("%s:%d %s", src, line or 0, fname or "")
						break
					end
				end
				newBy[who] = (newBy[who] or 0) + 1
			end
		end
		return new0(...)
	end
end
-- frame-signal handlers, labelled (what runs every frame while the screen is idle)
local handlerMs = {} -- [label] = ms in the current phase
local handlerFrames = {} -- [label] = frames it ran in (current phase)
local frameHandlers = {} -- [label] = ms in the current frame
for _, name in ipairs({ "RenderStepped", "Heartbeat" }) do
	local sig = E[name]
	local connect = sig.Connect
	sig.Connect = function(self, fn)
		local src, line = debug.info(fn, "sl")
		local label = string.format("%s %s:%d", name, tostring(src):gsub("^.*/", ""), line or 0)
		return connect(self, function(...)
			local t0 = os.clock()
			local ex0 = excluded
			fn(...)
			if measuring then
				local ms = (os.clock() - t0 - (excluded - ex0)) * 1000
				handlerMs[label] = (handlerMs[label] or 0) + ms
				handlerFrames[label] = (handlerFrames[label] or 0) + 1
				frameHandlers[label] = (frameHandlers[label] or 0) + ms
			end
		end)
	end
end

------------------------------------------------------------------------
-- replication: the server rig's changes mirrored onto the client's character
------------------------------------------------------------------------
local toCli = setmetatable({}, { __mode = "k" }) -- server instance -> client copy
local toSrv = setmetatable({}, { __mode = "k" }) -- client copy -> server instance
local seenMesh = {}
local rep = { made = 0, destroyed = 0, writes = 0, firstMeshes = 0 }
local function isSrvInst(v)
	return type(v) == "table" and ES.all[v] == true
end
-- a copy of a server subtree, unparented (no client handler can see it yet): built outside the frame
local fixups = {}
local function copyTree(o)
	local n = E.new(rawget(o, "_class"))
	rawset(n, "_name", rawget(o, "_name"))
	toCli[o], toSrv[n] = n, o
	local props = rawget(n, "_props")
	for k, v in pairs(rawget(o, "_props")) do
		if isSrvInst(v) then
			table.insert(fixups, { n, k, v })
		else
			props[k] = v
		end
	end
	for k, v in pairs(rawget(o, "_attr")) do
		rawget(n, "_attr")[k] = v
	end
	if rawget(o, "_class") == "MeshPart" and props.MeshId and props.MeshId ~= "" and not seenMesh[props.MeshId] then
		seenMesh[props.MeshId] = true
		rep.firstMeshes += 1
	end
	rep.made += 1
	for _, c in ipairs(rawget(o, "_kids")) do
		local cc = copyTree(c)
		rawset(cc, "_parent", n)
		table.insert(rawget(n, "_kids"), cc)
	end
	return n
end
local function tagsOf(o, out)
	local tags = ES.CollectionService:GetTags(o)
	if #tags > 0 then
		table.insert(out, { o, tags })
	end
	for _, c in ipairs(rawget(o, "_kids")) do
		tagsOf(c, out)
	end
end
-- the ops a sync applies (inside the frame): { kind, ... }
local function diff(o, n, ops)
	for k, v in pairs(rawget(o, "_props")) do
		local want = v
		if isSrvInst(v) then
			want = toCli[v]
		end
		if want ~= nil and rawget(n, "_props")[k] ~= want then
			table.insert(ops, { "set", n, k, want })
		end
	end
	for k, v in pairs(rawget(o, "_attr")) do
		if rawget(n, "_attr")[k] ~= v then
			table.insert(ops, { "attr", n, k, v })
		end
	end
	for k in pairs(rawget(n, "_attr")) do
		if rawget(o, "_attr")[k] == nil and toSrv[n] then
			table.insert(ops, { "attr", n, k, nil })
		end
	end
	local srvKids = {}
	for _, c in ipairs(rawget(o, "_kids")) do
		srvKids[c] = true
		local cc = toCli[c]
		if cc and not rawget(cc, "_destroyed") then
			if rawget(cc, "_parent") ~= n then
				table.insert(ops, { "parent", cc, n })
			end
			diff(c, cc, ops)
		else
			local copy = copyTree(c)
			local tags = {}
			tagsOf(c, tags)
			table.insert(ops, { "parent", copy, n, tags })
		end
	end
	for _, cc in ipairs(table.clone(rawget(n, "_kids"))) do
		local so = toSrv[cc]
		if so and not srvKids[so] then
			-- (moved elsewhere in the tree: its new parent's pass re-parents it; gone: destroyed)
			if rawget(so, "_destroyed") or rawget(so, "_parent") == nil then
				table.insert(ops, { "destroy", cc })
			end
		end
	end
end
local cliChar
local function replicate()
	local t0 = os.clock()
	table.clear(fixups)
	local ops = {}
	diff(srv, cliChar, ops)
	for _, f in ipairs(fixups) do
		rawget(f[1], "_props")[f[2]] = toCli[f[3]] or f[3]
	end
	excluded += os.clock() - t0
	local wasMeasuring = measuring
	measuring = false -- (the engine's writes of replicated state are not the client's own writes)
	for _, op in ipairs(ops) do
		if op[1] == "set" then
			op[2][op[3]] = op[4]
			rep.writes += 1
		elseif op[1] == "attr" then
			op[2]:SetAttribute(op[3], op[4])
			rep.writes += 1
		elseif op[1] == "parent" then
			op[2].Parent = op[3]
			for _, tt in ipairs(op[4] or {}) do
				local c = toCli[tt[1]]
				for _, tag in ipairs(tt[2]) do
					E.CollectionService:AddTag(c, tag)
				end
			end
		elseif op[1] == "destroy" then
			local n = #op[2]:GetDescendants() + 1
			op[2]:Destroy()
			rep.destroyed += n
		end
	end
	measuring = wasMeasuring
end

------------------------------------------------------------------------
-- the client
------------------------------------------------------------------------
local reqs = { full = 0, head = 0, colors = 0 }
S.onInvokeServer = function(_, action, look, hands, popts)
	if action == "GetProfile" then
		return { created = false }
	end
	if action ~= "PreviewLook" then
		return { ok = true }
	end
	local only = type(popts) == "table" and type(popts.only) == "table" and popts.only or nil
	if not only then
		reqs.full += 1
	elseif only.Colors and not (only.Face or only.Hair or only.Beard) then
		reqs.colors += 1
	else
		reqs.head += 1
	end
	taskLib.wait(LAT)
	-- handlers.PreviewLook's throttle
	local now = os.clock()
	if lastPreview and now - lastPreview < (only and 0.2 or 0.5) then
		server.throttled += 1
		taskLib.wait(LAT)
		return { ok = false, throttled = true }
	end
	lastPreview = now
	if not only then
		needFull = true
	end
	serverBuild(look, hands, popts)
	taskLib.wait(LAT)
	return { ok = true }
end

-- the server's world (as loadframes: the gym and the city the join replicates), then the client's scripts
if args.world ~= "0" then
	local ok, err = pcall(function()
		DrillSim.ServerModule(Hh, "MapBuilder").BuildGym()
	end)
	print("[creatorframes] the server's world: " .. (ok and "built" or ("failed: " .. tostring(err))))
end
-- the character: the server's first full build, mirrored
pcall(Builder.Cosmetics, srv, LooksS.Defaults(1), PREVIEW_BUILD, PREVIEW_GEAR, { hands = "wraps", name = "", nick = "", waistText = "", detail = "full" })
cliChar = copyTree(srv)
for _, f in ipairs(fixups) do
	rawget(f[1], "_props")[f[2]] = toCli[f[3]] or f[3]
end
cliChar.Parent = E.workspace
do
	local tags = {}
	tagsOf(srv, tags)
	for _, tt in ipairs(tags) do
		for _, tag in ipairs(tt[2]) do
			E.CollectionService:AddTag(toCli[tt[1]], tag)
		end
	end
end
S.player.Character = cliChar
-- each LocalScript in a thread of its own (their top-level runs wait on frames)
for _, rel in ipairs({ "client/ClientMain.client.lua", "client/FightClient.client.lua", "client/Animator.client.lua" }) do
	base.spawn(function()
		local ok, err = pcall(S.loadScript, rel)
		if not ok then
			print("[creatorframes] " .. rel .. ": " .. tostring(err))
		end
	end)
end

Hh.globals.__simExcluded = function()
	return excluded
end
local inputMs = 0
local function oneFrame(input)
	table.clear(frameHandlers)
	local t0 = os.clock()
	excluded = 0
	created, writes = 0, 0
	measuring = true
	if pendingRep[1] and os.clock() >= pendingRep[1] then
		while pendingRep[1] and os.clock() >= pendingRep[1] do
			table.remove(pendingRep, 1)
		end
		local a, ex0 = os.clock(), excluded
		replicate()
		frameHandlers["(replication applied)"] = (os.clock() - a - (excluded - ex0)) * 1000
	end
	if input then
		local a, ex0 = os.clock(), excluded
		input()
		inputMs = (os.clock() - a - (excluded - ex0)) * 1000
	else
		inputMs = 0
	end
	E.RenderStepped:Fire(1 / 60)
	resumeDue()
	E.Heartbeat:Fire(1 / 60)
	ltask.wait(0)
	measuring = false
	local ms = (os.clock() - t0 - excluded) * 1000
	local rest = 1 / 60 - (os.clock() - t0)
	ltask.wait(math.max(0.001, rest))
	return ms, created, writes
end
-- --slices 1: the longest stretches of a FrameBudget job between two Ticks (where a job overruns its frame), by the
-- Creator lines that opened and closed them
local sliceGaps = {}
if args.slices == "1" then
	local FB = Hh.require("Client/FrameBudget")
	local tick0 = FB.Tick
	local last = setmetatable({}, { __mode = "k" })
	local function where()
		for lv = 3, 14 do
			local src, line, fname = debug.info(lv, "sln")
			if not src then
				break
			end
			src = tostring(src):gsub("^.*/", ""):gsub('"%]$', "")
			if (src:find("Creator") or (src:find("Detail") and not src:find("DetailKit"))) and fname ~= "slice" then
				return string.format("%s:%d %s", src, line or 0, fname or "")
			end
		end
		return "?"
	end
	FB.Tick = function()
		local co = coroutine.running()
		local now, here = os.clock(), where()
		local l = last[co]
		if l then
			local ms = (now - l[1] - (excluded - l[3])) * 1000
			if ms > 1.5 then
				local key = l[2] .. " -> " .. here
				local g = sliceGaps[key] or { n = 0, max = 0 }
				sliceGaps[key] = g
				g.n += 1
				g.max = math.max(g.max, ms)
			end
		end
		tick0()
		last[co] = { os.clock(), here, excluded }
	end
end
for _ = 1, 90 do
	oneFrame()
end
local Creator = Hh.require("Client/Creator")
if Creator.IsOpen() then
	Creator.Close()
end
for _ = 1, 30 do
	oneFrame()
end

------------------------------------------------------------------------
-- phases
------------------------------------------------------------------------
local results = {}
local destroyedSeen = setmetatable({}, { __mode = "k" })
local function countDestroyed()
	local n = 0
	for o in pairs(E.all) do
		if rawget(o, "_destroyed") and not destroyedSeen[o] then
			destroyedSeen[o] = true
			n += 1
		end
	end
	return n
end
countDestroyed()
local function snapshot()
	return {
		full = reqs.full, head = reqs.head, colors = reqs.colors, sFull = server.full, sPartial = server.partial, sThrottled = server.throttled,
		sMs = server.ms, repMade = rep.made, repDestroyed = rep.destroyed, repWrites = rep.writes, tiers = server.tiers, meshes = rep.firstMeshes,
	}
end
-- one interaction: frames(i) is the input of frame i (nil: none); `settle` frames after it let previews land
local function phase(name, n, input, settle)
	local s0 = snapshot()
	table.clear(writeBy)
	table.clear(newBy)
	table.clear(handlerMs)
	table.clear(handlerFrames)
	local r = { name = name, frames = 0, maxMs = 0, sumMs = 0, created = 0, destroyed = 0, writes = 0, maxWrites = 0, over4 = 0, over8 = 0, over16 = 0, maxMsAt = 0 }
	local total = n + (settle or 30)
	for i = 1, total do
		local ms, c, w = oneFrame(i <= n and input and function()
			input(i)
		end or nil)
		local d = countDestroyed()
		r.frames += 1
		r.sumMs += ms
		if ms > r.maxMs then
			r.second = r.maxMs
			r.maxMs, r.maxMsAt = ms, i
			r.worst = table.clone(frameHandlers)
			r.worst["(input handlers)"] = inputMs
		elseif ms > (r.second or 0) then
			r.second = ms
		end
		r.over4 += ms > 4 and 1 or 0
		r.over8 += ms > 8 and 1 or 0
		r.over16 += ms > 16.7 and 1 or 0
		r.created += c
		r.destroyed += d
		r.writes += w
		r.maxWrites = math.max(r.maxWrites, w)
	end
	local s1 = snapshot()
	for k, v in pairs(s1) do
		r[k] = v - s0[k]
	end
	r.writeBy = table.clone(writeBy)
	r.newBy = table.clone(newBy)
	r.handlers = table.clone(handlerMs)
	r.handlerFrames = table.clone(handlerFrames)
	table.insert(results, r)
	return r
end

-- on screen: it and every GUI ancestor visible (the Creator keeps hidden rows: closed Advanced sections)
local function shown(d)
	local o = d
	while o and o ~= S.playerGui do
		if o.Visible == false then
			return false
		end
		o = o.Parent
	end
	return o == S.playerGui
end
-- the first control on screen that pred accepts (the search is the harness's, not the client's: left out of the frame)
local function find(pred)
	local t0 = os.clock()
	local hit
	for _, d in ipairs(S.playerGui:GetDescendants()) do
		if pred(d) and shown(d) then
			hit = d
			break
		end
	end
	excluded += os.clock() - t0
	return hit
end
local function named(name)
	return find(function(d)
		return d.Name == name
	end)
end
local function click(name)
	return function(i)
		if i == 1 then
			local b = named(name)
			if b then
				S.signal(b, "MouseButton1Click"):Fire()
			else
				print("[creatorframes] no " .. name)
			end
		end
	end
end
local function sliders()
	local t0 = os.clock()
	local out = {}
	for _, d in ipairs(S.playerGui:GetDescendants()) do
		if d:GetAttribute("Slider") and d:FindFirstChild("Label") and shown(d) then
			table.insert(out, d)
		end
	end
	excluded += os.clock() - t0
	return out
end
local MB1, MOVE = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseMovement
-- a pointer drag over n frames (a move every frame), let go on the last
local function dragInput(hit, x0, w, y, n, xs)
	local press0
	return function(i)
		local a = xs and xs(i) or (0.15 + 0.7 * i / n)
		if i == 1 then
			press0 = { UserInputType = MB1, Position = Vector3.new(x0 + w * 0.15, y, 0) }
			S.signal(hit, "InputBegan"):Fire(press0)
		end
		uis.InputChanged:Fire({ UserInputType = MOVE, Position = Vector3.new(x0 + w * a, y, 0) }, false)
		if i == n then
			uis.InputEnded:Fire(press0, false)
		end
	end
end
local function sliderDrag(f, n)
	local hit, track = f:FindFirstChild("Hit"), f:FindFirstChild("Track")
	local p, s = track.AbsolutePosition, track.AbsoluteSize
	return dragInput(hit, p.X, s.X, p.Y + 3, n)
end

local DRAG = 40 -- frames of one slider drag (~0.67 s)
local function step(i, name)
	phase("tab " .. i .. " " .. name, 1, click("Step" .. i), 30)
end
local function dragAll(page)
	for _, f in ipairs(sliders()) do
		local label = f.Label.Text
		phase("drag " .. page .. ": " .. label, DRAG, sliderDrag(f, DRAG), 40)
	end
end
local function openAdvanced()
	local b = named("AdvancedToggle")
	if b and not b.Text:find("Hide") then
		phase("advanced open", 1, click("AdvancedToggle"), 20)
	end
end
local function want(page)
	return next(ONLY) == nil or ONLY[page]
end

phase("open", 1, function()
	Creator.Open()
end, 60)
phase("idle (2 s)", 120, nil, 0)
local PAGES = { "Identity", "Face", "Skin", "Hair", "Body", "Gear", "Style" }
for i, p in ipairs(PAGES) do
	step(i, p)
end
-- Identity: the age slider; the gender cycler (a whole new look)
step(1, "Identity")
if want("Identity") then
	dragAll("Identity")
	for _, g in ipairs({ "gender cycler", "gender cycler back" }) do
		phase(g, 1, function()
			S.signal(named("Next"), "MouseButton1Click"):Fire()
		end, 40)
	end
end
step(2, "Face")
if want("Face") then
	dragAll("Face")
	phase("face preset", 1, click("Preset_Chiselled"), 40)
	phase("face style chip", 1, function()
		local d = find(function(d)
			return d.Name:match("^Chip_") ~= nil and d.BackgroundColor3 ~= nil
		end)
		if d then
			S.signal(d, "MouseButton1Click"):Fire()
		end
	end, 40)
	openAdvanced()
	dragAll("Face+")
end
step(3, "Skin")
if want("Skin") then
	phase("skin tone swatch", 1, click("Swatch2"), 40)
	dragAll("Skin")
end
step(4, "Hair")
if want("Hair") then
	-- (the avatar toggle off: the game's hairstyles)
	local tg = find(function(d)
		return d:IsA("GuiObject") and d.Name == "Label" and d.Text == "Use my avatar's hair & face"
	end)
	tg = tg and tg.Parent
	if tg then
		phase("avatar toggle off", 1, function()
			Hh.require("UI").Nudge(tg, 1)
		end, 40)
	end
	phase("hair style", 1, function()
		local d = find(function(d)
			return d.Name:match("^Preset_") ~= nil and d.Parent ~= nil and d.Parent.Name == "Styles" and d.BackgroundColor3 ~= nil
		end)
		if d then
			S.signal(d, "MouseButton1Click"):Fire()
		end
	end, 40)
	phase("hair colour swatch", 1, click("Swatch3"), 40)
	phase("beard chip", 1, click("Chip_Stubble"), 40)
	dragAll("Hair")
end
step(5, "Body")
if want("Body") then
	phase("body type", 1, click("Preset_Muscular"), 60)
	phase("body type 2", 1, click("Preset_Lean"), 60)
	dragAll("Body")
	phase("preview body: peak", 1, function()
		local d = find(function(d)
			return d.Name == "Label" and d.Text == "Preview body"
		end)
		if d then
			Hh.require("UI").Nudge(d.Parent, 1)
		end
	end, 60)
end
step(6, "Gear")
if want("Gear") then
	phase("kit preset", 1, function()
		local d = find(function(d)
			return d.Name:match("^Preset_") ~= nil and d.Parent ~= nil and d.Parent.Name == "Kits"
		end)
		if d then
			S.signal(d, "MouseButton1Click"):Fire()
		end
	end, 40)
	phase("trunks swatch", 1, click("Swatch4"), 40)
	phase("trunk style cycler", 1, function()
		local d = find(function(d)
			return d.Name == "Label" and d.Text == "Trunk style"
		end)
		if d then
			Hh.require("UI").Nudge(d.Parent, 1)
		end
	end, 40)
	phase("custom colour (wheel open)", 1, click("CustomColour"), 20)
	-- the wheel: a drag round it (hue / saturation), then the brightness bar
	-- (UI.ColorWheel's wheel hit area: ZIndex 4 over the dots)
	local wheelHit = find(function(d)
		return d:IsA("TextButton") and d.ZIndex == 4 and d.Text == "" and d.Parent ~= nil and d.Parent.Parent ~= nil and d.Parent.Parent:FindFirstChild("Brightness", true) == nil
	end)
	if wheelHit then
		local p, s = wheelHit.AbsolutePosition, wheelHit.AbsoluteSize
		phase("colour wheel drag", DRAG, dragInput(wheelHit, p.X, s.X, p.Y + s.Y * 0.3, DRAG), 40)
	else
		print("[creatorframes] no colour wheel hit area")
	end
end
step(7, "Style")
-- the 3D view: a drag to turn, wheel zoom, the dock
phase("turn (drag the 3D view)", 60, function(i)
	if i == 1 then
		uis.InputBegan:Fire({ UserInputType = MB1, Position = Vector3.new(1400, 500, 0) }, false)
	end
	uis.InputChanged:Fire({ UserInputType = MOVE, Position = Vector3.new(1400 + i * 6, 500, 0) }, false)
	if i == 60 then
		uis.InputEnded:Fire({ UserInputType = MB1, Position = Vector3.new(1760, 500, 0) }, false)
	end
end, 30)
phase("zoom (wheel x10)", 10, function(i)
	uis.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(1400, 500, i % 2 == 0 and 1 or -1) }, false)
end, 30)
phase("dock turn / zoom buttons", 1, function()
	for _, n in ipairs({ "Turnleft", "Turnright", "ZoomIn", "ZoomOut", "Front" }) do
		local b = named(n)
		if b then
			S.signal(b, "MouseButton1Click"):Fire()
		end
	end
end, 30)
phase("idle again (2 s)", 120, nil, 0)
phase("leave", 1, function()
	Creator.Close()
end, 30)

------------------------------------------------------------------------
-- report
------------------------------------------------------------------------
print(string.format("%-34s %7s %7s %5s %6s %6s %6s %6s %13s %10s %6s %6s", "interaction", "max ms", "avg ms", ">4ms", "new", "gone", "writes", "w/frm", "req f/h/c", "srv f/p/th", "repl", "mesh1"))
local agg = {}
local function bucket(name)
	local key = name:match("^drag ([^:]+):") and ("drags: " .. name:match("^drag ([^:]+):")) or (name:match("^tab ") and "tab switches") or name
	return key
end
for _, r in ipairs(results) do
	print(string.format("%-34s %7.2f %7.2f %5d %6d %6d %6d %6d %4d/%3d/%3d %4d/%2d/%2d %6d %6d", r.name:sub(1, 34), r.maxMs, r.sumMs / r.frames, r.over4, r.created, r.destroyed, r.writes, r.maxWrites,
		r.full, r.head, r.colors, r.sFull, r.sPartial, r.sThrottled, r.repMade, r.meshes))
	local k = bucket(r.name)
	local a = agg[k] or { n = 0, maxMs = 0, created = 0, writes = 0, maxWrites = 0, sFull = 0, sPartial = 0, full = 0, head = 0, colors = 0, over4 = 0 }
	agg[k] = a
	a.n += 1
	a.maxMs = math.max(a.maxMs, r.maxMs)
	a.created += r.created
	a.writes += r.writes
	a.maxWrites = math.max(a.maxWrites, r.maxWrites)
	a.sFull += r.sFull
	a.sPartial += r.sPartial
	a.full += r.full
	a.head += r.head
	a.colors += r.colors
	a.over4 += r.over4
end
local function top(t, n)
	local list = {}
	for k, v in pairs(t or {}) do
		table.insert(list, { k, v })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local parts = {}
	for i = 1, math.min(n, #list) do
		table.insert(parts, string.format("%s %s", list[i][1], type(list[i][2]) == "number" and (math.floor(list[i][2]) == list[i][2] and tostring(list[i][2]) or string.format("%.2f", list[i][2])) or tostring(list[i][2])))
	end
	return table.concat(parts, "; ")
end
if DEBUG then
	for _, r in ipairs(results) do
		print(string.format("-- %s: worst frame %d (%.2f ms, 2nd %.2f): %s", r.name, r.maxMsAt, r.maxMs, r.second or 0, top(r.worst, 5)))
		print("     writes: " .. top(r.writeBy, 6))
		print("     created by: " .. top(r.newBy, 5))
	end
end
-- what runs every frame while the screen sits idle
for _, r in ipairs(results) do
	if r.name:match("^idle") then
		local list = {}
		for k, v in pairs(r.handlers) do
			table.insert(list, { k, v })
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		print(string.format("idle: frame handlers (ms over %d frames, frames run):", r.frames))
		for i = 1, math.min(12, #list) do
			print(string.format("  %8.2f  %4d  %s", list[i][2], r.handlerFrames[list[i][1]] or 0, list[i][1]))
		end
	end
end
local worstDrag, worstTab, dragFull, dragTicks, worstAll = 0, 0, 0, 0, 0
for _, r in ipairs(results) do
	worstAll = math.max(worstAll, r.maxMs)
	if r.name:match("^drag ") then
		worstDrag = math.max(worstDrag, r.maxMs)
		dragFull += r.sFull
		dragTicks += 1
	elseif r.name:match("^tab ") then
		worstTab = math.max(worstTab, r.maxMs)
	end
end
do
	local FB = Hh.require("Client/FrameBudget")
	print(string.format("FrameBudget: longest slice %.2f ms (%s)", FB.Longest.ms or 0, tostring(FB.Longest.name)))
end
if next(sliceGaps) then
	local list = {}
	for k, g in pairs(sliceGaps) do
		table.insert(list, { k, g })
	end
	table.sort(list, function(a, b)
		return a[2].max > b[2].max
	end)
	print("FrameBudget stretches over 1.5 ms between Ticks (max ms, count):")
	for i = 1, math.min(25, #list) do
		print(string.format("  %7.2f  %4d  %s", list[i][2].max, list[i][2].n, list[i][1]))
	end
end
print(string.format("server: %d full rebuilds, %d partial, %d throttled, %.0f ms of Cosmetics, %d instances built; client: %d replicated, %d destroyed, %d first-time meshes",
	server.full, server.partial, server.throttled, server.ms, server.made, rep.made, rep.destroyed, rep.firstMeshes))
print(string.format("SUMMARY worst_frame_ms=%.2f worst_drag_frame_ms=%.2f worst_tab_frame_ms=%.2f drags=%d drag_full_rebuilds=%d full_rebuilds=%d partial_rebuilds=%d replicated=%d",
	worstAll, worstDrag, worstTab, dragTicks, dragFull, server.full, server.partial, rep.made))
if args.json then
	fs.writeFile(args.json, serde.encode("json", { results = results, server = server, rep = rep }, true))
end
process.exit(0)
