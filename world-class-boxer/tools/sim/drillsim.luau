--!nocheck
-- drillsim.luau: a training drill run by the REAL client (Activities.Start) on a guisim client, with a fake
-- server and a virtual clock (test_drills.luau plays it with bots, test_ui_layout.luau lays its screens out).
--
--   local D = DrillSim.Attach(S, { act = act, lv = 3, params = {...}, P = profile })   -- after the client loaded
--   D.start()                    -- Activities.Start(act.id) in its own thread (StartActivity -> the real plan)
--   D.frame()                    -- one 60 Hz frame on the virtual clock (Heartbeat / RenderStepped)
--   D.ctx()                      -- the running drill's context (nil before / after)
--   D.send(id, down)             -- an input through this device's own path: a key (desktop), a pad button or
--                                   right-stick flick (console), the on-screen button (touch); false when the
--                                   drill has no way in for it on this device (D.unreachable[id] says why)
--   D.finished / D.cancelled     -- FinishActivity's { quality, stats, tEnd } / CancelActivity seen
--   D.events, D.plan             -- the ActivityInput stream the server recorded, the server's plan
--   D.char                       -- the character model the pose attributes land on
-- The server side is the real code: Training.DrillPlan draws the plan; FinishActivity answers ok = false (the
-- result screen is not part of this) after recording what the client handed in, or what o.finish(quality,
-- stats) returns (a real Training.Perform / Record result: the report screen).
local fs = require("@lune/fs")
local task = require("@lune/task")
local Host = require("./host")
local FE = require("./fakeengine")

local DrillSim = {}

function DrillSim.ServerModule(Hh, name)
	local folder = rawget(Hh, "_serverFolder")
	if not folder then
		folder = Host.NewNode("Server", "Folder", Hh.Service("ServerScriptService"))
		for _, f in ipairs(fs.readDir(Hh.src .. "/server")) do
			local base = f:match("^(.-)%.lua$")
			if base and not f:find("%.server%.") then
				local n = Host.NewNode(base, "ModuleScript", folder)
				rawset(n, "_file", Hh.src .. "/server/" .. f)
			end
		end
		rawset(Hh, "_serverFolder", folder)
	end
	return Hh.requireNode(folder._kids[name])
end

-- the server's unseeded Random seeded (every run draws the same plans)
function DrillSim.SeedRandom(Hh)
	local R0, seedN = Hh.globals.Random, 0
	Hh.globals.Random = setmetatable({
		new = function(seed)
			seedN += 1
			return R0.new(seed or (7919 * seedN))
		end,
	}, { __index = R0 })
end

function DrillSim.Attach(S, o)
	local Hh = S.host
	local dev = S.name
	local act = o.act
	local D = { events = {}, unreachable = {}, plan = nil, finished = nil, cancelled = false }
	local Training = DrillSim.ServerModule(Hh, "Training")
	local before = S.onInvokeServer
	if not S.remotes.ActivityInput then
		S.makeRemote("ActivityInput")
	end
	local inputRemote = S.remotes.ActivityInput
	local beforeFire = S.onFireServer
	S.onFireServer = function(remote, token, id, down, t, ...)
		if remote == inputRemote then
			table.insert(D.events, { id = id, down = down == true, t = t })
			return
		end
		if beforeFire then
			return beforeFire(remote, token, id, down, t, ...)
		end
	end
	S.onInvokeServer = function(r, action, ...)
		if action == "StartActivity" then
			D.plan = Training.DrillPlan(act, o.lv, o.params)
			return { ok = true, token = "TK", minigame = act.minigame, params = o.params, level = o.lv, plan = D.plan, act = act.id, energy = 10 }
		elseif action == "FinishActivity" then
			local _, quality, stats = ...
			local ctx = D.ctx()
			D.finished = { quality = quality, stats = stats, tEnd = ctx and ctx.now() or 0 }
			if o.finish then
				-- (a test that wants the result screen: the server's real result for this session)
				return o.finish(quality, stats)
			end
			return { ok = false, err = "test" }
		elseif action == "CancelActivity" then
			D.cancelled = true
			return { ok = true }
		end
		if before then
			return before(r, action, ...)
		end
		return { ok = false }
	end
	-- the drill's clock is virtual from here: 60 frames a simulated second
	local vt = 1000
	Hh.globals.os.clock = function()
		return vt
	end
	local uis = Hh.Service("UserInputService")._props
	uis.InputBegan, uis.InputEnded, uis.InputChanged = FE.Signal(), FE.Signal(), FE.Signal()
	local char = Hh.globals.Instance.new("Model")
	char.Name = "Boxer"
	rawget(S.E.localPlayer, "_props").Character = char
	D.char = char
	local State = Hh.require("Client/State")
	local Activities = Hh.require("Client/Activities")
	local K = Hh.globals.Enum.KeyCode
	local UIT = Hh.globals.Enum.UserInputType
	local Vec3 = Hh.globals.Vector3
	local frames = 0
	function D.ctx()
		local cur = State.activity
		return cur and cur.ctx
	end
	function D.start()
		task.spawn(Activities.Start, act.id)
	end
	function D.frame()
		frames += 1
		vt += 1 / 60
		S.E.RenderStepped:Fire(1 / 60)
		S.E.Heartbeat:Fire(1 / 60)
		if frames % 30 == 0 then
			task.wait()
		end
		return frames
	end
	function D.send(id, down)
		local ctx = D.ctx()
		if not ctx then
			return false
		end
		if dev == "phone" or dev == "phone_small" or dev == "tablet" then
			local b = ctx.buttons[id]
			if not b then
				D.unreachable[id] = "no button"
				return false
			end
			S.signal(b, down and "MouseButton1Down" or "MouseButton1Up"):Fire()
			return true
		end
		local pad = dev == "console" or dev == "phone_pad"
		local map = pad and ctx.padmap or ctx.keymap
		local key, flick
		for k, v in pairs(map) do
			-- (a key, not a mouse button binding)
			if v == id and not (typeof(k) == "EnumItem" and k.EnumType == UIT) then
				if k == K.Thumbstick2Left or k == K.Thumbstick2Right or k == K.Thumbstick2Up or k == K.Thumbstick2Down then
					flick = k
				else
					key = k
					break
				end
			end
		end
		if not key and flick then
			-- a right-stick flick: out to the edge and back (a tap; nothing on the release)
			if down then
				local x = flick == K.Thumbstick2Left and -1 or (flick == K.Thumbstick2Right and 1 or 0)
				local y = flick == K.Thumbstick2Down and -1 or (flick == K.Thumbstick2Up and 1 or 0)
				uis.InputChanged:Fire({ KeyCode = K.Thumbstick2, UserInputType = UIT.Gamepad1, Position = Vec3.new(x, y, 0) }, false)
				uis.InputChanged:Fire({ KeyCode = K.Thumbstick2, UserInputType = UIT.Gamepad1, Position = Vec3.new(0, 0, 0) }, false)
			end
			return true
		end
		if not key then
			D.unreachable[id] = pad and "no pad button" or "no key"
			return false
		end
		local input = { KeyCode = key, UserInputType = pad and UIT.Gamepad1 or UIT.Keyboard }
		;(down and uis.InputBegan or uis.InputEnded):Fire(input, false)
		return true
	end
	-- frames until pred(ctx) holds (or the drill ends / maxFrames): true when it held
	function D.until_(pred, maxFrames)
		for _ = 1, maxFrames or 60 * 300 do
			D.frame()
			local ctx = D.ctx()
			if ctx and pred(ctx) then
				return true
			end
			if D.finished or D.cancelled then
				return false
			end
		end
		return false
	end
	return D
end

return DrillSim
